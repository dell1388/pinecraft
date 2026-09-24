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
## The vehicle whose bed this piece is lying in, if any. The piece is still a
## free body; this is only so the truck can count its load and save it.
var carrier: Node3D = null

var _shape: CollisionShape3D
var _mesh: MeshInstance3D
var _extras: Array[Node3D] = []

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
		# Collision is the same eight-sided prism the log is drawn as, taper
		# and all. Jolt lets a true cylinder lying on its side sink a hand's
		# width into anything that moves - a truck bed, a belt - so round
		# stock is flat-sided in the physics as well as to look at.
		var hull := _shape.shape as ConvexPolygonShape3D
		if hull == null:
			hull = ConvexPolygonShape3D.new()
			_shape.shape = hull
		hull.points = prism_points(float(dims.r0), float(dims.r1), float(dims.length))
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
	# What a piece has been through shows: sanded wood is pale and smooth,
	# refined metal is bright and polished.
	if Solid.has_finish(dims, &"sanded"):
		mat.albedo_color = color.lerp(Color(0.93, 0.82, 0.62), 0.45)
		mat.roughness = 0.55
	if Solid.has_finish(dims, &"refined"):
		mat.albedo_color = color.lightened(0.25)
		mat.metallic = 0.85
		mat.roughness = 0.22
	# Polished stone is glossy; a cut jewel glitters.
	if Solid.has_finish(dims, &"polished"):
		mat.albedo_color = color.lightened(0.12)
		mat.roughness = 0.12
		mat.metallic = 0.2
	if category == &"jewel":
		mat.roughness = 0.05
		mat.metallic = 0.35
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.35
	elif category == &"gem":
		mat.roughness = minf(mat.roughness, 0.5)
	_mesh.material_override = mat

## The corners of an eight-sided log, matching CylinderMesh's own vertices:
## `r0` at the bottom (-Y), `r1` at the top.
static func prism_points(r0: float, r1: float, length: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var sides := Tuning.ROUND_SIDES
	for i in sides:
		var a := TAU * float(i) / float(sides)
		var d := Vector3(sin(a), 0.0, cos(a))
		out.append(d * r0 + Vector3(0, -length * 0.5, 0))
		out.append(d * r1 + Vector3(0, length * 0.5, 0))
	return out

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

## Any other decoration to carry (a box's printed art and label).
func add_extra_node(node: Node3D) -> void:
	add_child(node)
	_extras.append(node)

func clear_extras() -> void:
	for e in _extras:
		if is_instance_valid(e):
			e.queue_free()
	_extras.clear()

## Its name as the player sees it, finish and all: "Sanded Pine Wood".
func display_name() -> String:
	var prefix := Solid.finish_prefix(dims)
	var base := GameData.item_name(item_id)
	return base if prefix == "" else "%s %s" % [prefix, base]

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
			# Held by one point it swings, but settles rather than spinning.
			angular_damp = 2.5
			# Whatever holds it takes its weight: it goes where it is steered
			# and stays there, rather than sagging out of the hand.
			gravity_scale = 0.0
		State.HELD, State.CAPTURED:
			# Owned by the player's rack or a machine: kinematic, so it still
			# pushes loose items aside but costs the solver nothing.
			freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			freeze = true
		State.POOLED:
			freeze = false
			sleeping = true
			carrier = null
	quiet_time = 0.0
	if next != State.CARRIED:
		gravity_scale = 1.0
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

## Half the piece's thickness measured along `dir`, as it is lying now.
func extent_along(dir: Vector3) -> float:
	var b := global_transform.basis
	var d := dir.normalized()
	if dims.get("shape", Solid.BOX) == Solid.CYLINDER:
		var r := Solid.max_radius(dims)
		var axis := b.y.normalized()
		var along := absf(axis.dot(d))
		return along * length() * 0.5 + sqrt(maxf(0.0, 1.0 - along * along)) * r
	var half: Vector3 = (dims.size as Vector3) * 0.5
	return absf(b.x.normalized().dot(d)) * half.x + absf(b.y.normalized().dot(d)) * half.y \
		+ absf(b.z.normalized().dot(d)) * half.z

## Friction from a driven surface under the piece - a roller, a belt: pulls
## its velocity in the surface plane toward `surface_velocity`, but never by
## more than `grip` times gravity, so a heavy or jammed piece slips instead
## of being yanked about.
func grip_toward(surface_velocity: Vector3, up: Vector3, grip: float, delta: float) -> void:
	var slip := linear_velocity - surface_velocity
	slip -= up * slip.dot(up)
	var most := grip * 9.8 * delta
	var change := -slip
	if change.length() > most:
		change = change.normalized() * most
	if change.length_squared() < 0.000001:
		return
	sleeping = false
	linear_velocity += change
