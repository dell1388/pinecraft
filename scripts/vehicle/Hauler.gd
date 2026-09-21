class_name Hauler
extends RigidBody3D

## Flatbed hauler.
##
## Deliberately not a VehicleBody3D: four raycast suspension springs plus drive
## and steering forces behave identically on any backend, stay stable at high
## speed, and cost four ray queries per frame. Cargo is *captured* (kinematic,
## snapped to bed slots) rather than left loose on the deck, so a bumpy ride can
## never fling the load or wake a hundred contacts.

signal cargo_changed(count: int, capacity: int)

@export var engine_force_max: float = 9000.0
@export var brake_force: float = 12000.0
@export var steer_torque: float = 2600.0
@export var max_speed: float = 22.0
@export var suspension_rest: float = 0.75
@export var suspension_strength: float = 78000.0
@export var suspension_damping: float = 7000.0
@export var lateral_grip: float = 0.55
@export var cargo_capacity_m3: float = 8.0
@export var wheel_radius: float = 0.45
@export var wheel_width: float = 0.34

var manager: LooseItemManager
var plot_id: int = 0
var driver: Node3D = null
## The load, as {id, dims}. There are no physics bodies aboard: see the cargo
## section for why.
var cargo_items: Array[Dictionary] = []
## Drive inputs, filled from the keyboard while a driver is aboard. Exposed so
## tests (and, later, any automation) can drive the hauler without a keyboard.
var input_throttle: float = 0.0
var input_steer: float = 0.0
var input_brake: bool = false
var autopilot: bool = false

const BODY_SIZE := Vector3(2.6, 0.7, 5.0)
## Ray origins sit at the chassis underside: the springs, not the box, must
## carry the hauler, or the chassis grinds along the ground and the drive force
## fights friction instead of moving the truck.
const WHEEL_OFFSETS := [
	Vector3(-1.1, -0.35, -1.7), Vector3(1.1, -0.35, -1.7),
	Vector3(-1.1, -0.35, 1.7), Vector3(1.1, -0.35, 1.7),
]

var _props: Array[MeshInstance3D] = []
var _wheels: Array[MeshInstance3D] = []
var _wheel_spin: float = 0.0
var _cargo_area: Area3D
var _cargo_shape: CollisionShape3D
var _seat: Node3D
var _grounded: int = 0
var _poll: float = 0.0

func setup(p_manager: LooseItemManager, p_plot_id: int = 0) -> void:
	manager = p_manager
	plot_id = p_plot_id

func _ready() -> void:
	mass = 900.0
	collision_layer = Layers.VEHICLE
	collision_mask = Layers.WORLD | Layers.LOOSE | Layers.MACHINE | Layers.TREE | Layers.PLAYER
	can_sleep = true
	continuous_cd = true          # a 900 kg box at 22 m/s must never tunnel
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.25
	angular_damp = 2.5
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.45, 0)   # low: makes rollovers very unlikely
	_build()

func _build() -> void:
	var chassis := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = BODY_SIZE
	chassis.shape = box
	add_child(chassis)

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = BODY_SIZE
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.22, 0.18)
	mesh.material_override = mat
	add_child(mesh)

	# Bed walls, so cargo that is released on board does not slide off.
	for spec in [
		[Vector3(0, 0.55, 2.4), Vector3(2.6, 0.9, 0.2)],
		[Vector3(-1.3, 0.55, 0.6), Vector3(0.2, 0.9, 3.8)],
		[Vector3(1.3, 0.55, 0.6), Vector3(0.2, 0.9, 3.8)],
	]:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = spec[1]
		cs.shape = b
		cs.position = spec[0]
		add_child(cs)

	_cargo_area = Area3D.new()
	_cargo_area.collision_layer = Layers.TRIGGER
	_cargo_area.collision_mask = Layers.LOOSE
	var acs := CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = Vector3(2.3, 1.4, 3.6)
	acs.shape = ab
	acs.position = Vector3(0, 0.9, 0.6)
	_cargo_shape = acs
	_cargo_area.add_child(acs)
	_cargo_area.body_entered.connect(_on_cargo_body)
	add_child(_cargo_area)

	_build_dressing()

	_seat = Node3D.new()
	_seat.position = Vector3(0, 1.2, -1.9)
	add_child(_seat)

## Cab, deck boards and wheels. All mesh, no collision: the hull box above is
## the only thing the solver sees, and the "wheels" are the four suspension
## rays in _apply_suspension.
func _build_dressing() -> void:
	var paint := Color(0.55, 0.22, 0.18)
	_add_mesh(BoxMesh.new(), Vector3(2.3, 0.95, 1.5), Vector3(0, 0.75, -1.55), paint.darkened(0.1))
	_add_mesh(BoxMesh.new(), Vector3(2.0, 0.5, 0.12), Vector3(0, 1.0, -2.28), Color(0.28, 0.35, 0.40))
	for side in [-1.0, 1.0]:
		_add_mesh(BoxMesh.new(), Vector3(0.12, 0.45, 1.2), Vector3(side * 1.16, 1.0, -1.55),
			Color(0.28, 0.35, 0.40))
		_add_mesh(BoxMesh.new(), Vector3(0.22, 0.16, 0.1), Vector3(side * 0.9, 0.2, -2.52),
			Color(0.95, 0.92, 0.72))
	# Deck boards, so the bed does not read as one slab.
	for i in 5:
		_add_mesh(BoxMesh.new(), Vector3(2.3, 0.06, 0.62),
			Vector3(0, 0.37, -0.55 + float(i) * 0.68), paint.darkened(0.3))

	var tyre := Color(0.10, 0.10, 0.11)
	for offset in WHEEL_OFFSETS:
		var wheel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = wheel_radius
		cyl.bottom_radius = wheel_radius
		cyl.height = wheel_width
		cyl.radial_segments = 16
		wheel.mesh = cyl
		wheel.position = Vector3(offset.x + signf(offset.x) * 0.12, offset.y, offset.z)
		# Cylinders stand on Y; a wheel spins about X.
		wheel.rotation = Vector3(0, 0, PI * 0.5)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tyre
		mat.roughness = 0.95
		wheel.material_override = mat
		add_child(wheel)
		_wheels.append(wheel)
		var hub := MeshInstance3D.new()
		var hub_mesh := CylinderMesh.new()
		hub_mesh.top_radius = wheel_radius * 0.42
		hub_mesh.bottom_radius = wheel_radius * 0.42
		hub_mesh.height = wheel_width + 0.04
		hub_mesh.radial_segments = 12
		hub.mesh = hub_mesh
		hub.position = wheel.position
		hub.rotation = wheel.rotation
		var hub_mat := StandardMaterial3D.new()
		hub_mat.albedo_color = Color(0.72, 0.72, 0.75)
		hub_mat.metallic = 0.5
		hub_mat.roughness = 0.4
		hub.material_override = hub_mat
		add_child(hub)

func _add_mesh(mesh: Mesh, size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mi.material_override = mat
	add_child(mi)

## Wheels turn with the ground speed and the front pair follows the steering,
## which is what sells a vehicle as driven rather than slid.
func _animate_wheels(delta: float) -> void:
	if _wheels.is_empty():
		return
	var forward := -global_transform.basis.z
	var speed := linear_velocity.dot(forward)
	_wheel_spin += speed / maxf(0.05, wheel_radius) * delta
	var steer := clampf(input_steer, -1.0, 1.0) * 0.5
	for i in _wheels.size():
		var wheel: MeshInstance3D = _wheels[i]
		var is_front: bool = WHEEL_OFFSETS[i].z < 0.0
		wheel.rotation = Vector3(0, steer if is_front else 0.0, PI * 0.5)
		wheel.rotate_object_local(Vector3.UP, -_wheel_spin)

func seat_transform() -> Transform3D:
	return _seat.global_transform

# --- Cargo -----------------------------------------------------------------

## Loading removes the item from the physics world entirely and replaces it
## with a mesh parented to the hauler. From that moment the load *is* part of
## the vehicle: it has no collider, no body and no velocity of its own, so no
## bump, collision, ramp or rollover can shake it loose, and nothing outside can
## push, grab or steal it. Unloading spawns the real items back.

func cargo_count() -> int:
	return cargo_items.size()

func cargo_volume() -> float:
	var total := 0.0
	for entry in cargo_items:
		total += Solid.volume(entry.dims)
	return total

func cargo_full() -> bool:
	return cargo_volume() >= cargo_capacity_m3

## Item-sink protocol, so the player can deposit into the bed with [E] and a
## conveyor can load the hauler like any other sink.
func can_accept(_item_id: StringName) -> bool:
	return not cargo_full()

func accept_item(item: LooseItem) -> bool:
	if cargo_full() or item == null:
		return false
	var id := item.item_id
	var dims := item.dims.duplicate()
	if manager != null:
		manager.despawn(item)
	return load_item(id, dims)

## Adds one piece to the load, without any physics object involved.
func load_item(item_id: StringName, dims: Dictionary = {}) -> bool:
	if cargo_full():
		return false
	var def := GameData.item(item_id)
	if def == null:
		return false
	cargo_items.append({"id": item_id, "dims": dims if not dims.is_empty() else def.default_dims()})
	_rebuild_props()
	cargo_changed.emit(cargo_items.size(), cargo_capacity_m3)
	return true

func _on_cargo_body(body: Node) -> void:
	var item := body as LooseItem
	if item == null or item.state != LooseItem.State.FREE:
		return
	if not Trigger.contains_point(_cargo_shape, item.global_position, 0.3):
		return
	accept_item(item)

## Sweeps the whole bed and absorbs everything loose on it. Called when a driver
## climbs in, and on the regular poll, so a load is never left half-physical.
func secure_load() -> int:
	var taken := 0
	for body in Trigger.bodies_inside(_cargo_area, _cargo_shape, 0.35):
		var item := body as LooseItem
		if item == null or item.state != LooseItem.State.FREE:
			continue
		if accept_item(item):
			taken += 1
	return taken

func unload(behind: bool = true) -> int:
	var n := cargo_items.size()
	if n == 0:
		return 0
	var dir := global_transform.basis.z if behind else -global_transform.basis.z
	var drop := global_position + dir * 3.4
	var yaw := global_rotation.y
	for i in n:
		var pos := drop + Vector3(
			randf_range(-0.6, 0.6), 1.2 + float(i) * 0.22, randf_range(-0.6, 0.6))
		if manager != null:
			manager.spawn(cargo_items[i].id, Transform3D(LooseItem.lying_basis(yaw), pos),
				plot_id, Vector3.ZERO, cargo_items[i].dims)
	cargo_items.clear()
	_clear_props()
	cargo_changed.emit(0, cargo_capacity_m3)
	return n

## Drops exactly one item, for topping a machine up without emptying the truck.
func unload_one() -> bool:
	if cargo_items.is_empty():
		return false
	var entry: Dictionary = cargo_items.pop_back()
	var dir := global_transform.basis.z
	if manager != null:
		manager.spawn(entry.id, Transform3D(LooseItem.lying_basis(global_rotation.y),
			global_position + dir * 3.4 + Vector3(0, 1.2, 0)), plot_id, Vector3.ZERO, entry.dims)
	_rebuild_props()
	cargo_changed.emit(cargo_items.size(), cargo_capacity_m3)
	return true

func cargo_summary() -> String:
	if cargo_items.is_empty():
		return "empty"
	var counts: Dictionary = {}
	for entry in cargo_items:
		counts[entry.id] = int(counts.get(entry.id, 0)) + 1
	var parts: Array[String] = []
	for id in counts:
		parts.append("%s x%d" % [GameData.item_name(id), int(counts[id])])
	return "%.2f/%.1f m3: %s" % [cargo_volume(), cargo_capacity_m3, ", ".join(parts)]

# --- Cargo visuals ---------------------------------------------------------

## Load is packed for real: short pieces lie across the bed in three columns,
## long ones run fore-and-aft down the middle, and each column stacks by the
## actual thickness of what is in it.
func _rebuild_props() -> void:
	_clear_props()
	var columns := [-0.75, 0.05, 0.85]
	var heights := [0.0, 0.0, 0.0]
	var long_height := 0.0
	for entry in cargo_items:
		var dims: Dictionary = entry.dims
		var def := GameData.item(entry.id)
		if def == null:
			continue
		var bounds := Solid.bounds(dims)
		var thickness: float = maxf(bounds.x, bounds.z)
		if bounds.y <= 2.1:
			var col := 0
			for i in 3:
				if heights[i] < heights[col]:
					col = i
			var pos := Vector3(0.0, 0.42 + heights[col] + thickness * 0.5, columns[col])
			heights[col] += thickness + 0.02
			_add_prop(def, dims, Transform3D(LooseItem.lying_basis(PI * 0.5), pos))
		else:
			var pos_long := Vector3(0.0, 0.42 + long_height + thickness * 0.5, 0.3)
			long_height += thickness + 0.02
			_add_prop(def, dims, Transform3D(LooseItem.lying_basis(0.0), pos_long))

func _add_prop(def: ItemDef, dims: Dictionary, xform: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	if dims.get("shape", Solid.BOX) == Solid.CYLINDER:
		var cm := CylinderMesh.new()
		cm.bottom_radius = float(dims.r0)
		cm.top_radius = float(dims.r1)
		cm.height = float(dims.length)
		cm.radial_segments = 10
		mi.mesh = cm
	else:
		var bm := BoxMesh.new()
		bm.size = dims.size
		mi.mesh = bm
	mi.transform = xform
	var mat := StandardMaterial3D.new()
	mat.albedo_color = def.color
	mat.roughness = 0.9
	mi.material_override = mat
	add_child(mi)
	_props.append(mi)

func _clear_props() -> void:
	for prop in _props:
		if is_instance_valid(prop):
			prop.queue_free()
	_props.clear()

# --- Driving ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# Anything resting in the bed is absorbed promptly, whether it was thrown
	# in, dropped by the player or driven over, so there is never a loose item
	# aboard waiting to be flung off at the first bump.
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.2 if driver == null else 0.1
		secure_load()

	_animate_wheels(delta)
	_apply_suspension(delta)
	if driver != null:
		_read_input()
	if driver != null or autopilot:
		_apply_drive(delta)
	_clamp_motion()

func _apply_suspension(_delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var up := global_transform.basis.y
	_grounded = 0
	for offset in WHEEL_OFFSETS:
		var start: Vector3 = global_transform * offset
		var end: Vector3 = start - up * suspension_rest
		var q := PhysicsRayQueryParameters3D.create(start, end, Layers.WORLD | Layers.MACHINE, [get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		_grounded += 1
		var distance: float = start.distance_to(hit.position)
		var compression: float = clampf(1.0 - distance / suspension_rest, 0.0, 1.0)
		var point_velocity: Vector3 = linear_velocity + angular_velocity.cross(start - global_position)
		var damping: float = point_velocity.dot(up) * suspension_damping
		var force: float = compression * suspension_strength - damping
		apply_force(up * maxf(0.0, force), start - global_position)
		# Lateral grip: kill sideways slip at the contact point so the hauler
		# turns instead of drifting.
		var side: Vector3 = global_transform.basis.x
		var slip: float = clampf(point_velocity.dot(side), -6.0, 6.0)
		apply_force(-side * slip * mass * lateral_grip, start - global_position)

func _read_input() -> void:
	input_throttle = Input.get_axis("move_back", "move_forward")
	input_steer = Input.get_axis("move_right", "move_left")
	input_brake = Input.is_action_pressed("jump")

func _apply_drive(_delta: float) -> void:
	var throttle := input_throttle
	var steer := input_steer
	var forward := -global_transform.basis.z
	var speed := linear_velocity.dot(forward)

	if _grounded > 0:
		if absf(throttle) > 0.05 and absf(speed) < max_speed:
			apply_central_force(forward * throttle * engine_force_max)
		elif absf(speed) > 0.2:
			apply_central_force(-forward * signf(speed) * brake_force * 0.15)
		# Steering authority scales with speed: no pirouettes while parked.
		var authority: float = clampf(absf(speed) / 6.0, 0.0, 1.0) * signf(speed if absf(speed) > 0.2 else 1.0)
		apply_torque(Vector3.UP * steer * steer_torque * authority)
	if input_brake and _grounded > 0:
		apply_central_force(-linear_velocity.normalized() * brake_force)

func _clamp_motion() -> void:
	if linear_velocity.length() > max_speed * 1.4:
		linear_velocity = linear_velocity.normalized() * max_speed * 1.4
	if angular_velocity.length() > 3.5:
		angular_velocity = angular_velocity.normalized() * 3.5

## Upright rescue: a hauler on its roof is unrecoverable for the player.
func recover() -> void:
	var pos := global_position + Vector3(0, 1.2, 0)
	var yaw := global_rotation.y
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM,
		Transform3D(Basis.from_euler(Vector3(0, yaw, 0)), pos))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func to_dict() -> Dictionary:
	var ids: Array = []
	for entry in cargo_items:
		ids.append({"id": String(entry.id), "dims": Solid.to_dict(entry.dims)})
	return {"position": [global_position.x, global_position.y, global_position.z],
		"yaw": global_rotation.y, "cargo": ids}

func from_dict(d: Dictionary) -> void:
	var p: Array = d.get("position", [0, 2, 0])
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM,
		Transform3D(Basis.from_euler(Vector3(0, float(d.get("yaw", 0.0)), 0)),
			Vector3(p[0], p[1], p[2])))
	cargo_items.clear()
	for entry in d.get("cargo", []):
		cargo_items.append({"id": StringName(entry.get("id", "")),
			"dims": Solid.from_dict(entry.get("dims", {}))})
	_rebuild_props()
	cargo_changed.emit(cargo_items.size(), cargo_capacity_m3)
