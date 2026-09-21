class_name Player
extends CharacterBody3D

## First-person player: move, chop, grab/drag, throw.
##
## Dragging is velocity-driven rather than joint-driven on purpose. A pin/
## generic6DOF joint between the camera and an 8 kg log is the classic way to
## make a solver scream; steering the body's velocity toward a hold point is
## stable at any mass and cannot inject energy without bound.

@export var walk_speed: float = 5.5
@export var sprint_speed: float = 8.5
@export var jump_velocity: float = 5.0
@export var mouse_sensitivity: float = 0.0022
@export var reach: float = 4.0
@export var chop_damage: float = 34.0
@export var chop_cooldown: float = 0.35
@export var carry_distance: float = 2.2
@export var carry_gain: float = 14.0        ## velocity P-gain toward hold point
@export var carry_max_speed: float = 14.0
@export var throw_impulse: float = 9.0

var manager: LooseItemManager
var carried: LooseItem = null
var _chop_cd: float = 0.0
var _mouse_captured: bool = false

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	collision_layer = Layers.PLAYER
	collision_mask = Layers.MASK_PLAYER
	_capture_mouse(true)

func _capture_mouse(capture: bool) -> void:
	_mouse_captured = capture
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x, -1.4, 1.4)
	elif event.is_action_pressed("ui_cancel"):
		_capture_mouse(not _mouse_captured)
	elif event is InputEventMouseButton and event.pressed:
		if not _mouse_captured:
			_capture_mouse(true)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if carried != null:
				_throw()
			else:
				_chop()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if carried != null:
				_release()
			else:
				_grab()

func _physics_process(delta: float) -> void:
	_chop_cd = maxf(0.0, _chop_cd - delta)

	if not is_on_floor():
		velocity += get_gravity() * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var input := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_back"))
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed: float = sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	if dir != Vector3.ZERO:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 4.0 * delta)
	move_and_slide()

	_update_carry(delta)

# --- Interaction -----------------------------------------------------------

func _ray() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * reach
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.MASK_RAY_INTERACT, [get_rid()])
	return space.intersect_ray(q)

func _chop() -> void:
	if _chop_cd > 0.0:
		return
	_chop_cd = chop_cooldown
	var hit := _ray()
	if hit.is_empty():
		return
	var tree := hit.collider as ChoppableTree
	if tree != null:
		tree.chop(chop_damage, global_position)

func _grab() -> void:
	var hit := _ray()
	if hit.is_empty():
		return
	var item := hit.collider as LooseItem
	if item == null or item.state != LooseItem.State.FREE:
		return
	carried = item
	item.set_state(LooseItem.State.CARRIED)

func _release() -> void:
	if carried == null:
		return
	carried.set_state(LooseItem.State.FREE)
	carried = null

func _throw() -> void:
	if carried == null:
		return
	var item := carried
	_release()
	item.apply_central_impulse(-camera.global_transform.basis.z * throw_impulse * item.mass * 0.15)

func _update_carry(delta: float) -> void:
	if carried == null:
		return
	if not is_instance_valid(carried) or carried.state != LooseItem.State.CARRIED:
		carried = null
		return
	var target := camera.global_position - camera.global_transform.basis.z * carry_distance
	var to_target := target - carried.global_position
	if to_target.length() > reach * 2.0:
		_release()          # dropped through geometry or yanked too far
		return
	var desired := to_target * carry_gain
	if desired.length() > carry_max_speed:
		desired = desired.normalized() * carry_max_speed
	carried.linear_velocity = desired
	carried.angular_velocity = carried.angular_velocity * 0.6
