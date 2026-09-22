class_name LooseItem
extends RigidBody3D

## A single loose physical piece: a log, a length of lumber, a billet, a crate.
##
## Its shape is data, not a model file: a box or a tapered cylinder whose long
## axis is local +Y. Mass comes from the item's density times its real volume,
## so a 4 m trunk weighs what a 4 m trunk should and the sawmill that conserves
## volume also conserves mass and price.
##
## Kept deliberately dumb: no _physics_process, no _integrate_forces. Velocity
## clamping, CCD toggling and kill-plane rescue are driven by LooseItemManager
## so that 500 of these cost one loop instead of 500 script callbacks per step.

enum State { FREE, CARRIED, HELD, CAPTURED, POOLED }

signal state_changed(item: LooseItem, from: State, to: State)

var item_id: StringName = &"wood_pine"
var category: StringName = &"wood"
var dims: Dictionary = {}
var plot_id: int = 0
var state: State = State.FREE
var spawn_index: int = 0
## Whether this piece belongs to the player: picked up, bought, or made by a
## machine on their plot. Owned pieces are what the yard buys and what a save
## remembers; a trunk lying in the forest is neither.
var owned: bool = false
var ccd_active: bool = false
var quiet_time: float = 0.0
var cut_progress: float = 0.0     ## axe work done on this piece since the last cut

var _shape: CollisionShape3D
var _mesh: MeshInstance3D
var _extras: Array[MeshInstance3D] = []

func _init() -> void:
	collision_layer = Layers.LOOSE
	collision_mask = Layers.MASK_LOOSE
	can_sleep = true
	continuous_cd = false
	max_contacts_reported = 0
	contact_monitor = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.1
	angular_damp = 0.4

func configure(def: ItemDef, p_dims: Dictionary = {}) -> void:
	item_id = def.id
	category = def.category
	dims = p_dims if not p_dims.is_empty() else def.default_dims()
	mass = def.mass_of(dims)
	cut_progress = 0.0
	owned = false
	clear_extras()
	# Round stock rolls; a little extra spin damping stops a felled trunk
	# rolling across the plot forever without making it feel glued down.
	angular_damp = 0.9 if dims.get("shape", Solid.BOX) == Solid.CYLINDER else 0.4
	_build_shape()
	_build_mesh(def.color)

func _build_shape() -> void:
	if _shape == null:
		_shape = CollisionShape3D.new()
		add_child(_shape)
	if dims.get("shape", Solid.BOX) == Solid.CYLINDER:
		var cyl := _shape.shape as CylinderShape3D
		if cyl == null:
			cyl = CylinderShape3D.new()
			_shape.shape = cyl
		# Collision is a straight cylinder at the widest radius: one primitive,
		# and never thinner than the mesh it stands in for.
		cyl.radius = Solid.max_radius(dims)
		cyl.height = float(dims.length)
	else:
		var box := _shape.shape as BoxShape3D
		if box == null:
			box = BoxShape3D.new()
			_shape.shape = box
		box.size = dims.size

func _build_mesh(color: Color) -> void:
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		add_child(_mesh)
	if dims.get("shape", Solid.BOX) == Solid.CYLINDER:
		var cm := _mesh.mesh as CylinderMesh
		if cm == null:
			cm = CylinderMesh.new()
			cm.radial_segments = Tuning.ROUND_SIDES
			cm.rings = 1
			_mesh.mesh = cm
		cm.bottom_radius = float(dims.r0)
		cm.top_radius = float(dims.r1)
		cm.height = float(dims.length)
	else:
		var bm := _mesh.mesh as BoxMesh
		if bm == null:
			bm = BoxMesh.new()
			_mesh.mesh = bm
		bm.size = dims.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	_mesh.material_override = mat

## Decorative meshes carried by this piece (cut branch stubs on a felled trunk).
## Visual only: the collider stays one primitive.
func add_extra_mesh(mesh: Mesh, xform: Transform3D, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xform
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mi.material_override = mat
	add_child(mi)
	_extras.append(mi)

func clear_extras() -> void:
	for e in _extras:
		if is_instance_valid(e):
			e.queue_free()
	_extras.clear()

func volume() -> float:
	return Solid.volume(dims)

func length() -> float:
	return Solid.length_of(dims)

func is_wood() -> bool:
	return category == &"wood"

func set_state(next: State) -> void:
	if next == state:
		return
	var prev := state
	state = next
	match next:
		State.FREE:
			freeze = false
			sleeping = false
		State.CARRIED:
			freeze = false
			sleeping = false
			angular_damp = 6.0
		State.HELD, State.CAPTURED:
			# Owned by the player's rack or a machine: kinematic, so it still
			# pushes loose items aside but costs the solver nothing.
			freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			freeze = true
		State.POOLED:
			freeze = false
			sleeping = true
	quiet_time = 0.0
	if next != State.CARRIED:
		angular_damp = 0.9 if dims.get("shape", Solid.BOX) == Solid.CYLINDER else 0.4
	state_changed.emit(self, prev, next)

func reset_motion() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if ccd_active:
		continuous_cd = false
		ccd_active = false

func teleport(xform: Transform3D) -> void:
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xform)
	global_transform = xform
	reset_motion()

## Half the vertical extent, used by machines that place items by transform.
func get_aabb_half_height() -> float:
	return Solid.bounds(dims).y * 0.5

## Vertical half-extent once the piece is lying on its side, which is how belts,
## racks and vehicle beds carry things.
func resting_half_height() -> float:
	if dims.get("shape", Solid.BOX) == Solid.CYLINDER:
		return Solid.max_radius(dims)
	return (dims.size as Vector3).z * 0.5

## A basis that lays this piece down with its long axis horizontal, pointing
## along `yaw` (radians around +Y).
static func lying_basis(yaw: float = 0.0) -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5)
