class_name VehicleRig
extends Node3D

## The gear bolted to a vehicle: a winch and a crane.
##
## Both are rated, and a rating is a wall rather than a slope. Ask the winch for
## more than it pulls and nothing happens at all - no crawling, no slow drift -
## because a machine past its power does not have a weaker effect, it has none.
##
## The crane works the way the doc describes rather than the way a crane does.
## Once it has hold of something, the player drives the *object*: WASD slides it
## about, Shift and Control raise and lower it, R and T swing it round in
## quarter turns, and the boom is drawn afterwards to wherever the object ended
## up. The load is kinematic while this is happening, so an awkward shape being
## threaded into a machine mouth cannot fight the solver or shove the truck.

signal winch_attached(anchor: Vector3)
signal winch_released()
signal crane_grabbed(item: LooseItem)
signal crane_released(item: LooseItem)

## What the winch can pull, in kilograms. Past this it has no effect.
@export var winch_power_kg: float = 4000.0
## What the crane can pick up, in kilograms.
@export var crane_power_kg: float = 1200.0
## How far either can work from the vehicle.
@export var reach: float = 14.0
## How fast the winch takes up line, and how fast the crane moves a load.
@export var winch_speed: float = 3.2
@export var crane_speed: float = 3.4

var vehicle: RigidBody3D

## Winch state. `anchor_body` is null for a plain world surface.
var anchored: bool = false
var anchor_point: Vector3 = Vector3.ZERO
var anchor_body: Node3D = null

## Crane state.
var held: LooseItem = null
var hold_point: Vector3 = Vector3.ZERO
var hold_yaw: float = 0.0

var _cable: MeshInstance3D
var _boom: MeshInstance3D

func setup(p_vehicle: RigidBody3D) -> void:
	vehicle = p_vehicle

func _ready() -> void:
	_build()
	set_physics_process(true)

## Where the hook and the boom foot sit on the truck.
func head_point() -> Vector3:
	if vehicle == null:
		return global_position
	return vehicle.global_position + vehicle.global_transform.basis.y * 1.1 \
		- vehicle.global_transform.basis.z * 1.2

# --- Winch -----------------------------------------------------------------

## Hooks the winch to a surface or a loose object. Returns "" on success.
func attach_winch(target: Node3D, point: Vector3) -> String:
	if anchored:
		return "the winch is already hooked on"
	if head_point().distance_to(point) > reach:
		return "too far for the winch (%.0f m of line)" % reach
	var item := target as LooseItem
	if item != null and item.mass > winch_power_kg:
		return "%.0f kg is past the winch's %.0f kg rating" % [item.mass, winch_power_kg]
	anchored = true
	anchor_body = target
	anchor_point = point
	if item != null:
		item.set_state(LooseItem.State.FREE)
	winch_attached.emit(point)
	return ""

func release_winch() -> void:
	if not anchored:
		return
	anchored = false
	anchor_body = null
	_cable.visible = false
	winch_released.emit()

## The load the winch would be working against right now.
func winch_load_kg() -> float:
	var item := anchor_body as LooseItem
	if item != null:
		return item.mass
	return vehicle.mass if vehicle != null else 0.0

## Whether the winch can shift what it is hooked to at all.
func winch_can_pull() -> bool:
	return anchored and winch_load_kg() <= winch_power_kg

## Takes up line. Hooked to a surface it drags the truck in; hooked to something
## loose it drags that to the truck instead.
func reel(delta: float) -> void:
	if not anchored or vehicle == null:
		return
	if not winch_can_pull():
		return        # past its rating: no effect, not a slow one
	var item := anchor_body as LooseItem
	if item != null and is_instance_valid(item):
		anchor_point = item.global_position
		var to_truck := head_point() - item.global_position
		if to_truck.length() < 2.2:
			return
		item.linear_velocity = to_truck.normalized() * winch_speed
		item.angular_velocity *= 0.7
		return
	var to_anchor := anchor_point - head_point()
	if to_anchor.length() < 2.0:
		release_winch()
		return
	# Pulling the truck itself: a force, so suspension and terrain still argue.
	vehicle.apply_central_force(to_anchor.normalized() * winch_power_kg * 9.0)

# --- Crane -----------------------------------------------------------------

## Takes hold of a piece, if it is in reach and inside the crane's rating.
func grab(item: LooseItem) -> String:
	if held != null:
		return "the crane is already holding something"
	if item == null or item.state != LooseItem.State.FREE:
		return "nothing to lift"
	if item.mass > crane_power_kg:
		return "%.0f kg is past the crane's %.0f kg rating" % [item.mass, crane_power_kg]
	if head_point().distance_to(item.global_position) > reach:
		return "out of the crane's reach"
	held = item
	item.owned = true
	hold_point = item.global_position
	hold_yaw = item.global_rotation.y
	# Kinematic while the crane has it: the load is being positioned, not
	# simulated, so it cannot fight the solver or shove the truck about.
	item.set_state(LooseItem.State.HELD)
	crane_grabbed.emit(item)
	return ""

func drop() -> LooseItem:
	if held == null:
		return null
	var item := held
	held = null
	if is_instance_valid(item):
		item.set_state(LooseItem.State.FREE)
		item.linear_velocity = Vector3.ZERO
		item.angular_velocity = Vector3.ZERO
	crane_released.emit(item)
	return item

func holding() -> bool:
	return held != null and is_instance_valid(held)

## Drives the load directly. `move` is lateral input in the camera's frame,
## `lift` is Shift/Control, `spin` is -1 or 1 for a quarter turn.
func steer(move: Vector3, lift: float, spin: int, delta: float) -> void:
	if not holding():
		held = null
		return
	if spin != 0:
		hold_yaw = snappedf(hold_yaw + float(spin) * PI * 0.5, PI * 0.5)
	var step := move * crane_speed * delta
	step.y = lift * crane_speed * delta
	var wanted := hold_point + step
	# The boom has a reach, so the load cannot be walked over the horizon.
	var from := head_point()
	var offset := wanted - from
	if offset.length() > reach:
		offset = offset.normalized() * reach
		wanted = from + offset
	# Nor can it be pushed underground.
	wanted.y = maxf(wanted.y, from.y - reach * 0.5)
	hold_point = wanted
	held.global_transform = Transform3D(
		Basis.from_euler(Vector3(0, hold_yaw, 0)) * Basis(Vector3.RIGHT, PI * 0.5), hold_point)

func _physics_process(delta: float) -> void:
	_draw_cable()
	_draw_boom()
	if holding():
		# Keeps the load with the truck when the truck moves under it.
		steer(Vector3.ZERO, 0.0, 0, delta)

func status_line() -> String:
	if holding():
		return "crane: %s  [WASD] move  [Shift/Ctrl] raise  [R/T] turn  [F] release" % \
			GameData.item_name(held.item_id)
	if anchored:
		if not winch_can_pull():
			return "winch: %.0f kg is past its %.0f kg rating - nothing doing" % [
				winch_load_kg(), winch_power_kg]
		return "winch: hooked on  [G] reel in  [E] unhook"
	return "winch %.0f kg / crane %.0f kg, %.0f m reach" % [
		winch_power_kg, crane_power_kg, reach]

# --- Geometry --------------------------------------------------------------

func _build() -> void:
	_cable = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.035
	cm.radial_segments = 6
	_cable.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.14, 0.14, 0.16)
	_cable.material_override = cmat
	_cable.visible = false
	_cable.top_level = true
	add_child(_cable)

	_boom = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.22, 1.0)
	_boom.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.82, 0.66, 0.14)
	bmat.metallic = 0.3
	_boom.material_override = bmat
	_boom.visible = false
	_boom.top_level = true
	add_child(_boom)

## The cable is drawn last, from the hook to wherever the load ended up: the
## boom follows the object, not the other way round.
func _draw_cable() -> void:
	if not anchored:
		_cable.visible = false
		return
	if anchor_body is LooseItem and is_instance_valid(anchor_body):
		anchor_point = (anchor_body as Node3D).global_position
	_span(_cable, head_point(), anchor_point, 0.035)

func _draw_boom() -> void:
	if not holding():
		_boom.visible = false
		return
	_span(_boom, head_point(), held.global_position, 0.11)

func _span(mesh: MeshInstance3D, from: Vector3, to: Vector3, thickness: float) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.05:
		mesh.visible = false
		return
	mesh.visible = true
	if mesh.mesh is CylinderMesh:
		var cm := mesh.mesh as CylinderMesh
		cm.height = length
		cm.top_radius = thickness
		cm.bottom_radius = thickness
	else:
		(mesh.mesh as BoxMesh).size = Vector3(thickness * 2.0, thickness * 2.0, length)
	var mid := from + delta * 0.5
	var basis := Basis()
	var forward := delta.normalized()
	if mesh.mesh is CylinderMesh:
		# Cylinders run along their own Y.
		var axis := Vector3.UP.cross(forward)
		basis = Basis() if axis.length_squared() < 0.0001 \
			else Basis(axis.normalized(), Vector3.UP.angle_to(forward))
	else:
		basis = Basis.looking_at(forward, Vector3.UP)
	mesh.global_transform = Transform3D(basis, mid)
