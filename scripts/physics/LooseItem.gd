class_name LooseItem
extends RigidBody3D

## A single loose physics object (log, plank, ore chunk...).
##
## Kept deliberately dumb: no _physics_process, no _integrate_forces. Every
## per-frame concern (velocity clamping, CCD toggling, kill-plane rescue) is
## driven by LooseItemManager so that 500 of these cost one GDScript loop
## instead of 500 script callbacks per step.

enum State { FREE, CARRIED, CAPTURED, POOLED }

signal state_changed(item: LooseItem, from: State, to: State)

var item_id: StringName = &"log_pine"
var plot_id: int = 0
var state: State = State.FREE
var spawn_index: int = 0            ## monotonic, used for oldest-first recycling
var ccd_active: bool = false
var quiet_time: float = 0.0     ## seconds spent below the manager's quiet thresholds

var _shape: CollisionShape3D
var _mesh: MeshInstance3D

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

func configure(id: StringName, size: Vector3, item_mass: float, color: Color) -> void:
	item_id = id
	mass = item_mass
	if _shape == null:
		_shape = CollisionShape3D.new()
		# Primitive box: cheapest possible convex, and stacks predictably.
		_shape.shape = BoxShape3D.new()
		add_child(_shape)
	(_shape.shape as BoxShape3D).size = size
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_mesh.mesh = BoxMesh.new()
		add_child(_mesh)
	(_mesh.mesh as BoxMesh).size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	_mesh.material_override = mat

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
			# Carried items stay dynamic but are velocity-driven by the player,
			# which cannot explode the solver the way a stiff joint can.
			freeze = false
			sleeping = false
			angular_damp = 6.0
		State.CAPTURED:
			# Owned by a conveyor/machine: no solver involvement at all.
			freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			freeze = true
		State.POOLED:
			freeze = false
			sleeping = true
	quiet_time = 0.0
	if next != State.CARRIED:
		angular_damp = 0.4
	state_changed.emit(self, prev, next)

## Zero out motion. Used on spawn, pool release and kill-plane rescue.
func reset_motion() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if ccd_active:
		continuous_cd = false
		ccd_active = false

func teleport(xform: Transform3D) -> void:
	# PhysicsServer-level move so Jolt does not integrate a huge delta.
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xform)
	global_transform = xform
	reset_motion()

## Half of the item's vertical extent, used by machines that place items by
## transform rather than letting them settle.
func get_aabb_half_height() -> float:
	if _shape != null and _shape.shape is BoxShape3D:
		return (_shape.shape as BoxShape3D).size.y * 0.5
	return 0.25
