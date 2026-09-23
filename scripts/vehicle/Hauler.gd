class_name Hauler
extends RigidBody3D

## Flatbed hauler.
##
## Deliberately not a VehicleBody3D: four raycast suspension springs plus drive
## and steering forces behave identically on any backend, stay stable at high
## speed, and cost four ray queries per frame.
##
## The load is real. Whatever is in the bed is an ordinary physics body resting
## on the deck and held in by the sides, headboard and tailgate: it shifts when
## you brake, piles against a wall in a hard corner, adds its weight to the
## springs, and falls out if you roll the truck. Driven sensibly it stays put.

signal cargo_changed(count: int, capacity: int)

@export var engine_force_max: float = 16000.0     ## total, split over the wheels
@export var max_steer_angle: float = 0.55         ## radians, at a standstill
@export var max_speed: float = 22.0
@export var suspension_rest: float = 0.75
@export var suspension_strength: float = 78000.0
@export var suspension_damping: float = 7000.0
## Friction coefficient at the tyre. What a wheel can do is this times the load
## it carries, so a wheel in the air grips nothing and a light end lets go first.
@export var tyre_grip: float = 1.7
## How hard a sliding tyre is pulled back into line, per metre per second of slip.
@export var lateral_stiffness: float = 16.0
@export var rolling_resistance: float = 0.02
@export var cargo_capacity_m3: float = 8.0
@export var wheel_radius: float = 0.45
@export var wheel_width: float = 0.34

var manager: LooseItemManager
var plot_id: int = 0
var driver: Node3D = null
## The land under the truck, for road speed and for drowning the engine.
var terrain: Terrain
## Drive inputs, filled from the keyboard while a driver is aboard. Exposed so
## tests (and, later, any automation) can drive the hauler without a keyboard.
var input_throttle: float = 0.0
var input_steer: float = 0.0
var input_brake: bool = false
var autopilot: bool = false

const BODY_SIZE := Vector3(2.6, 0.7, 5.0)
## The bed, inside the walls: from the headboard to the tailgate.
const BED_FLOOR := 0.35
const BED_FRONT := -0.72
const BED_BACK := 2.26
const BED_LENGTH := BED_BACK - BED_FRONT
const BED_MID_Z := (BED_FRONT + BED_BACK) * 0.5
const BED_HALF_WIDTH := 1.15
const WALL_HEIGHT := 1.1
const HEADBOARD_HEIGHT := 1.45
const BED_FRICTION := 0.9
## Ray origins sit at the chassis underside: the springs, not the box, must
## carry the hauler, or the chassis grinds along the ground and the drive force
## fights friction instead of moving the truck.
const WHEEL_OFFSETS := [
	Vector3(-1.1, -0.35, -1.7), Vector3(1.1, -0.35, -1.7),
	Vector3(-1.1, -0.35, 1.7), Vector3(1.1, -0.35, 1.7),
]

## Pieces lying in the bed right now, refreshed by the bed poll.
var _load: Array[LooseItem] = []
var _tailgate: CollisionShape3D
var _tailgate_mesh: Node3D
## Unloading: seconds left of the bed floor walking the load out the back,
## and the pieces being walked out.
var _tip_time: float = 0.0
var _tipping: Array[LooseItem] = []
var _wheels: Array[MeshInstance3D] = []
var _wheel_spin: float = 0.0
var _cargo_area: Area3D
var _cargo_shape: CollisionShape3D
var _seat: Node3D
var rig: VehicleRig
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


	# The bed: tall sides, a headboard that guards the cab, and a tailgate.
	# Thick, so a piece thrown at them at speed meets a wall rather than
	# slipping through one.
	for spec in [
		[Vector3(-BED_HALF_WIDTH - 0.15, BED_FLOOR + WALL_HEIGHT * 0.5, BED_MID_Z), Vector3(0.3, WALL_HEIGHT, BED_LENGTH + 0.2)],
		[Vector3(BED_HALF_WIDTH + 0.15, BED_FLOOR + WALL_HEIGHT * 0.5, BED_MID_Z), Vector3(0.3, WALL_HEIGHT, BED_LENGTH + 0.2)],
		[Vector3(0, BED_FLOOR + HEADBOARD_HEIGHT * 0.5, BED_FRONT - 0.12), Vector3(BED_HALF_WIDTH * 2.0 + 0.6, HEADBOARD_HEIGHT, 0.24)],
	]:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = spec[1]
		cs.shape = b
		cs.position = spec[0]
		add_child(cs)
	_tailgate = CollisionShape3D.new()
	var gate := BoxShape3D.new()
	gate.size = Vector3(BED_HALF_WIDTH * 2.0 + 0.6, WALL_HEIGHT, 0.24)
	_tailgate.shape = gate
	_tailgate.position = Vector3(0, BED_FLOOR + WALL_HEIGHT * 0.5, BED_BACK + 0.12)
	add_child(_tailgate)
	# Boards and loads grip one another: a load slides when it is thrown about,
	# not at every touch of the brakes.
	var pm := PhysicsMaterial.new()
	pm.friction = BED_FRICTION
	physics_material_override = pm

	_cargo_area = Area3D.new()
	_cargo_area.collision_layer = Layers.TRIGGER
	_cargo_area.collision_mask = Layers.LOOSE
	var acs := CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = Vector3(BED_HALF_WIDTH * 2.0, WALL_HEIGHT + 0.6, BED_LENGTH)
	acs.shape = ab
	acs.position = Vector3(0, BED_FLOOR + (WALL_HEIGHT + 0.6) * 0.5, BED_MID_Z)
	_cargo_shape = acs
	_cargo_area.add_child(acs)
	add_child(_cargo_area)

	_build_dressing()

	# Spec: most vehicles carry a winch, many carry a crane. The hauler has both.
	rig = VehicleRig.new()
	rig.name = "Rig"
	rig.setup(self)
	add_child(rig)

	_seat = Node3D.new()
	_seat.position = Vector3(0, 1.2, -1.9)
	add_child(_seat)

## Cab, deck boards and wheels. All mesh, no collision: the hull box above is
## the only thing the solver sees, and the "wheels" are the four suspension
## rays in _apply_wheels.
func _build_dressing() -> void:
	var g := Greeble.new()
	var paint := Color(0.62, 0.20, 0.16)
	var dark := Color(0.14, 0.14, 0.15)
	var steel := Color(0.60, 0.61, 0.64)
	var glass := Color(0.22, 0.32, 0.40)
	# Chassis and a steel sill down each side.
	g.block(BODY_SIZE, Vector3.ZERO, paint)
	for side in [-1.0, 1.0]:
		g.block(Vector3(0.1, 0.18, BODY_SIZE.z - 0.4), Vector3(side * (BODY_SIZE.x * 0.5 + 0.03), -0.2, 0), dark)
	# The cab: body, glass, roof, a light bar and a door line.
	var cab := Vector3(0, 0.75, -1.55)
	g.block(Vector3(2.3, 0.95, 1.5), cab, paint.darkened(0.08))
	g.block(Vector3(2.36, 0.1, 1.56), cab + Vector3(0, 0.5, 0), paint.darkened(0.25))
	g.block(Vector3(2.0, 0.5, 0.06), cab + Vector3(0, 0.22, -0.76), glass)
	for side in [-1.0, 1.0]:
		g.block(Vector3(0.06, 0.42, 1.1), cab + Vector3(side * 1.16, 0.22, 0.05), glass)
		g.block(Vector3(0.05, 0.85, 0.04), cab + Vector3(side * 1.16, -0.05, 0.62), paint.darkened(0.35))
		g.block(Vector3(0.12, 0.05, 0.05), cab + Vector3(side * 1.16, -0.1, 0.3), steel)
		# Mirrors.
		g.block(Vector3(0.3, 0.05, 0.05), cab + Vector3(side * 1.3, 0.2, -0.6), dark)
		g.block(Vector3(0.06, 0.28, 0.18), cab + Vector3(side * 1.45, 0.2, -0.6), dark)
	for i in 4:
		g.box(Vector3(0.28, 0.1, 0.14), Transform3D(Basis(), cab + Vector3(-0.6 + float(i) * 0.4, 0.62, -0.5)), Color(1.0, 0.62, 0.15), true)
	g.block(Vector3(1.8, 0.06, 0.2), cab + Vector3(0, 0.57, -0.5), dark)
	# Front: grille, bumper, headlights. Back: tail lights and a step.
	var nose := -BODY_SIZE.z * 0.5
	g.vent(1.3, 0.42, Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.05, nose)), Color(0.35, 0.35, 0.37), 5)
	g.block(Vector3(BODY_SIZE.x + 0.1, 0.22, 0.22), Vector3(0, -0.28, nose - 0.08), steel)
	for side in [-1.0, 1.0]:
		g.block(Vector3(0.32, 0.2, 0.08), Vector3(side * 0.95, 0.1, nose - 0.03), Color(1.0, 0.95, 0.75), true)
		g.block(Vector3(0.24, 0.16, 0.06), Vector3(side * 1.05, 0.05, -nose + 0.03), Color(1.0, 0.15, 0.1), true)
	g.block(Vector3(1.2, 0.08, 0.3), Vector3(0, -0.3, -nose + 0.1), steel)
	# Exhaust stack behind the cab.
	g.pipe(Vector3(1.05, 0.3, -0.72), Vector3(1.05, 1.9, -0.72), 0.08, steel.darkened(0.2), 6)
	g.prism(6, 0.1, 0.1, 0.2, Transform3D(Basis(Vector3.FORWARD, 0.4), Vector3(1.05, 1.9, -0.72)), dark)
	# Mudguards over the wheels.
	for offset in WHEEL_OFFSETS:
		var o: Vector3 = offset
		var x: float = o.x + signf(o.x) * 0.12
		g.box(Vector3(wheel_width + 0.16, 0.08, wheel_radius * 2.3), Transform3D(Basis(), Vector3(x, o.y + wheel_radius + 0.12, o.z)), dark)
	# The bed: boards, slatted sides on stake posts, a cab guard, and a
	# tailgate on hinges (its own mesh, so it can drop open).
	var boards := 6
	for i in boards:
		var z := BED_FRONT + (float(i) + 0.5) * BED_LENGTH / float(boards)
		g.block(Vector3(BED_HALF_WIDTH * 2.0, 0.05, BED_LENGTH / float(boards) - 0.04), Vector3(0, BED_FLOOR + 0.025, z), Color(0.46, 0.34, 0.22))
	var wall_mid := BED_FLOOR + WALL_HEIGHT * 0.5
	for side in [-1.0, 1.0]:
		var x: float = side * (BED_HALF_WIDTH + 0.15)
		for k in 3:
			var y := BED_FLOOR + 0.2 + float(k) * 0.34
			g.block(Vector3(0.3, 0.26, BED_LENGTH + 0.1), Vector3(x, y, BED_MID_Z), paint.darkened(0.15))
		for k in 5:
			var z := BED_FRONT + float(k) * BED_LENGTH / 4.0
			g.block(Vector3(0.36, WALL_HEIGHT + 0.06, 0.12), Vector3(x, wall_mid + 0.03, z), dark)
		g.block(Vector3(0.38, 0.08, BED_LENGTH + 0.3), Vector3(x, BED_FLOOR + WALL_HEIGHT + 0.02, BED_MID_Z), steel)
		g.rivets(Vector3(x + side * 0.16, BED_FLOOR + WALL_HEIGHT - 0.12, BED_FRONT + 0.2),
			Vector3(x + side * 0.16, BED_FLOOR + WALL_HEIGHT - 0.12, BED_BACK - 0.2), 10, steel, 0.04)
	# Headboard: a solid lower panel and a steel grille over the cab.
	var head_z := BED_FRONT - 0.12
	g.block(Vector3(BED_HALF_WIDTH * 2.0 + 0.6, WALL_HEIGHT, 0.24), Vector3(0, wall_mid, head_z), paint.darkened(0.2))
	var top := BED_FLOOR + HEADBOARD_HEIGHT
	g.block(Vector3(BED_HALF_WIDTH * 2.0 + 0.6, 0.1, 0.26), Vector3(0, top - 0.05, head_z), steel)
	for k in 7:
		var x := -BED_HALF_WIDTH + float(k) * BED_HALF_WIDTH * 2.0 / 6.0
		g.block(Vector3(0.05, HEADBOARD_HEIGHT - WALL_HEIGHT, 0.05), Vector3(x, BED_FLOOR + (WALL_HEIGHT + HEADBOARD_HEIGHT) * 0.5, head_z), steel.darkened(0.1))
	for sx in [-1.0, 1.0]:
		g.block(Vector3(0.14, HEADBOARD_HEIGHT, 0.26), Vector3(sx * (BED_HALF_WIDTH + 0.23), BED_FLOOR + HEADBOARD_HEIGHT * 0.5, head_z), dark)
	add_child(g.instance("Body"))

	# The tailgate, hinged along its bottom edge.
	var gate := Greeble.new()
	var gate_w := BED_HALF_WIDTH * 2.0 + 0.6
	gate.block(Vector3(gate_w, WALL_HEIGHT, 0.24), Vector3(0, WALL_HEIGHT * 0.5, 0), paint.darkened(0.15))
	gate.block(Vector3(gate_w + 0.04, 0.08, 0.28), Vector3(0, WALL_HEIGHT - 0.04, 0), steel)
	for k in 2:
		gate.block(Vector3(gate_w - 0.4, 0.06, 0.04), Vector3(0, 0.3 + float(k) * 0.4, 0.13), paint.darkened(0.35))
	for sx in [-1.0, 1.0]:
		gate.block(Vector3(0.1, 0.16, 0.06), Vector3(sx * (gate_w * 0.5 - 0.3), WALL_HEIGHT * 0.6, 0.15), dark)
		gate.block(Vector3(0.2, 0.14, 0.14), Vector3(sx * (gate_w * 0.5 - 0.3), 0.07, 0.0), dark)
	_tailgate_mesh = gate.instance("Tailgate")
	_tailgate_mesh.position = Vector3(0, BED_FLOOR, BED_BACK + 0.12)
	add_child(_tailgate_mesh)

	var wheel_mesh := _wheel_mesh()
	for offset in WHEEL_OFFSETS:
		var wheel := MeshInstance3D.new()
		wheel.mesh = wheel_mesh
		wheel.position = Vector3(offset.x + signf(offset.x) * 0.12, offset.y, offset.z)
		# The wheel mesh stands on Y; a wheel spins about X.
		wheel.rotation = Vector3(0, 0, PI * 0.5)
		add_child(wheel)
		_wheels.append(wheel)

## A tyre with a tread, a rim and lug nuts, so you can see it turn.
func _wheel_mesh() -> ArrayMesh:
	var g := Greeble.new()
	var half := wheel_width * 0.5
	var base := Transform3D(Basis(), Vector3(0, -half, 0))
	g.prism(12, wheel_radius, wheel_radius, wheel_width, base, Color(0.10, 0.10, 0.11))
	for i in 12:
		var a := TAU * (float(i) + 0.5) / 12.0
		g.box(Vector3(0.1, wheel_width * 0.9, 0.06), Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a), 0, sin(a)) * (wheel_radius + 0.01)), Color(0.07, 0.07, 0.08))
	for s in [-1.0, 1.0]:
		g.prism(8, wheel_radius * 0.5, wheel_radius * 0.45, 0.04, Transform3D(Basis(), Vector3(0, s * half, 0)).rotated_local(Vector3.RIGHT, 0.0 if s > 0 else PI), Color(0.72, 0.72, 0.75))
		for k in 5:
			var a := TAU * float(k) / 5.0
			g.block(Vector3(0.05, 0.05, 0.05), Vector3(cos(a) * wheel_radius * 0.3, s * (half + 0.05), sin(a) * wheel_radius * 0.3), Color(0.35, 0.35, 0.37))
	return g.commit()

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

## The load is whatever is lying in the bed: real pieces, counted by looking.
## Nothing is snapped, frozen or hidden. The truck only keeps track of them -
## so it can say what it is carrying, save it with the truck, keep it awake
## while the truck moves, and give it continuous collision at speed so a
## piece flung at a wall meets it.

func cargo_count() -> int:
	return _load.size()

func cargo_list() -> Array[LooseItem]:
	return _load.duplicate()

func cargo_volume() -> float:
	var total := 0.0
	for item in _load:
		if is_instance_valid(item):
			total += item.volume()
	return total

func cargo_full() -> bool:
	return cargo_volume() >= cargo_capacity_m3

## Item-sink protocol, so the player can deposit into the bed with [E] and a
## conveyor can load the hauler like any other sink.
func can_accept(_item_id: StringName) -> bool:
	return not cargo_full()

## Puts a piece into the bed: set down on the lowest part of the load, lying
## the way it fits - short pieces across, long ones fore-and-aft - and moving
## with the truck. From there it is on its own.
func accept_item(item: LooseItem) -> bool:
	if cargo_full() or item == null or item.state == LooseItem.State.POOLED:
		return false
	if item.state != LooseItem.State.FREE:
		item.set_state(LooseItem.State.FREE)
	var long := item.length() > BED_HALF_WIDTH * 2.0 - 0.2
	var basis := LooseItem.lying_basis(0.0 if long else PI * 0.5)
	var xs := [-0.55, 0.0, 0.55] if long else [0.0]
	var zs := [BED_MID_Z] if long else [BED_FRONT + 0.5, BED_MID_Z, BED_BACK - 0.5]
	var best := Vector3(0, INF, BED_MID_Z)
	for x in xs:
		for z in zs:
			var y := _pile_height(Vector3(x, 0, z), item)
			if y < best.y:
				best = Vector3(x, y, z)
	item.teleport(global_transform * Transform3D(basis, Vector3.ZERO))
	var up := global_transform.basis.y
	var at := global_transform * Vector3(best.x, best.y, best.z)
	at += up * (item.extent_along(up) + 0.04)
	item.teleport(Transform3D(item.global_transform.basis, at))
	item.linear_velocity = linear_velocity + angular_velocity.cross(at - global_position)
	item.owned = true
	_take(item)
	return true

## Height of the load (or the boards) under a point in the bed, in local Y.
func _pile_height(local: Vector3, ignore: LooseItem) -> float:
	var space := get_world_3d().direct_space_state
	var from := global_transform * Vector3(local.x, BED_FLOOR + WALL_HEIGHT + 2.0, local.z)
	var to := global_transform * Vector3(local.x, BED_FLOOR - 0.2, local.z)
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.LOOSE | Layers.VEHICLE,
		[ignore.get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return BED_FLOOR
	return maxf(BED_FLOOR, (global_transform.affine_inverse() * (hit.position as Vector3)).y)

## Adds one piece to the load. There is no physics-free cargo any more, so
## this makes a real piece and puts it in the bed.
func load_item(item_id: StringName, dims: Dictionary = {}) -> bool:
	if cargo_full() or manager == null:
		return false
	var item := manager.spawn(item_id, global_transform * Transform3D(Basis(), Vector3(0, 3, BED_MID_Z)),
		plot_id, Vector3.ZERO, dims, true)
	if item == null:
		return false
	return accept_item(item)

func _take(item: LooseItem) -> void:
	if _load.has(item):
		return
	item.carrier = self
	_load.append(item)
	cargo_changed.emit(_load.size(), cargo_capacity_m3)

## Who is in the bed now. Run a few times a second.
func _poll_bed() -> void:
	var inside: Array[LooseItem] = []
	for body in Trigger.bodies_inside(_cargo_area, _cargo_shape, 0.05):
		var item := body as LooseItem
		if item != null and item.state == LooseItem.State.FREE:
			inside.append(item)
	var before := _load.size()
	for item in _load.duplicate():
		if not inside.has(item):
			_load.erase(item)
			if is_instance_valid(item) and item.carrier == self:
				item.carrier = null
	for item in inside:
		if not _load.has(item):
			item.carrier = self
			item.owned = true
			_load.append(item)
	if _load.size() != before:
		cargo_changed.emit(_load.size(), cargo_capacity_m3)
	# A moving truck is cause to move for everything on it: nothing in the
	# bed may doze off and be left hanging in the air as the deck drives
	# away beneath it. And at speed, a piece that hits a wall must not pass
	# through it.
	var moving := linear_velocity.length() > 0.3 or angular_velocity.length() > 0.2
	var fast := linear_velocity.length() > 5.0
	for item in _load:
		if moving and item.sleeping:
			item.sleeping = false
		if item.ccd_active != fast:
			item.continuous_cd = fast
			item.ccd_active = fast

## Spec: unload. The tailgate drops and the bed floor walks the load out the
## back - it slides out under the push, and a piece that is wedged stays
## wedged. Returns how many pieces were aboard.
func unload(_behind: bool = true) -> int:
	var n := _load.size()
	if n == 0:
		return 0
	_start_tipping(_load.duplicate(), 5.0)
	return n

## Drops exactly one piece - the one nearest the tailgate - off the back.
func unload_one() -> bool:
	if _load.is_empty():
		return false
	var inverse := global_transform.affine_inverse()
	var last: LooseItem = _load[0]
	for item in _load:
		if (inverse * item.global_position).z > (inverse * last.global_position).z:
			last = item
	_start_tipping([last], 3.0)
	return true

func unloading() -> bool:
	return _tip_time > 0.0

func _start_tipping(items: Array, seconds: float) -> void:
	_tipping.clear()
	for item in items:
		_tipping.append(item)
	_tip_time = seconds
	_set_tailgate(true)
	_set_floor_slick(true)

## While the floor is walking the load out it is a moving floor, not a
## grippy one: the load slides on it under the push.
func _set_floor_slick(slick: bool) -> void:
	(physics_material_override as PhysicsMaterial).friction = 0.1 if slick else BED_FRICTION

func _set_tailgate(open: bool) -> void:
	_tailgate.disabled = open
	if _tailgate_mesh != null:
		_tailgate_mesh.rotation.x = PI * 0.5 if open else 0.0

## Still on the truck: in the bed, or lying across the open tailgate and the
## back of the chassis.
func _on_back(item: LooseItem) -> bool:
	if not is_instance_valid(item) or item.state != LooseItem.State.FREE:
		return false
	var local := global_transform.affine_inverse() * item.global_position
	var reach := item.extent_along(global_transform.basis.z)
	return local.y > BED_FLOOR - 0.15 and local.z - reach < BODY_SIZE.z * 0.5 + 0.05 \
		and absf(local.x) < BODY_SIZE.x * 0.5 + 0.3

func _update_unload(delta: float) -> void:
	if _tip_time <= 0.0:
		return
	_tip_time -= delta
	var back := global_transform.basis.z
	var up := global_transform.basis.y
	for item in _tipping.duplicate():
		if not _on_back(item):
			_tipping.erase(item)
			continue
		var carry := linear_velocity + angular_velocity.cross(item.global_position - global_position)
		item.grip_toward(carry + back * 2.5, up, 0.6, delta)
	if _tipping.is_empty():
		_tip_time = 0.0
	if _tip_time <= 0.0:
		_finish_tipping()

## Floor back to grippy, and the tailgate shut - unless something is still
## lying across it, since closing it through a log would fling the log. That
## piece keeps being walked off first.
func _finish_tipping() -> void:
	var inverse := global_transform.affine_inverse()
	for item in _tipping + _load:
		if not _on_back(item):
			continue
		if (inverse * item.global_position).z > BED_BACK - item.extent_along(global_transform.basis.z) + 0.08:
			_start_tipping([item], 1.0)
			return
	_tipping.clear()
	_set_floor_slick(false)
	_set_tailgate(false)

func cargo_summary() -> String:
	if _load.is_empty():
		return "empty"
	var counts: Dictionary = {}
	for item in _load:
		counts[item.item_id] = int(counts.get(item.item_id, 0)) + 1
	var parts: Array[String] = []
	for id in counts:
		parts.append("%s x%d" % [GameData.item_name(id), int(counts[id])])
	return "%.2f/%.1f m3: %s" % [cargo_volume(), cargo_capacity_m3, ", ".join(parts)]

# --- Driving ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.1
		_poll_bed()
	_update_unload(delta)

	_animate_wheels(delta)
	if driver != null:
		_read_input()
	elif parked():
		# No driver and no autopilot: the controls are nobody's, so they are
		# cleared rather than left holding whatever was last pressed.
		input_throttle = 0.0
		input_steer = 0.0
		input_brake = false
	if sleeping and not parked():
		sleeping = false
	_apply_wheels(delta)
	_clamp_motion()

func _read_input() -> void:
	input_throttle = Input.get_axis("move_back", "move_forward")
	input_steer = Input.get_axis("move_right", "move_left")
	input_brake = Input.is_action_pressed("jump")

## Spec: a driver seat under water means the truck can no longer be driven.
func flooded() -> bool:
	if terrain == null or _seat == null:
		return false
	return _seat.global_position.y < Terrain.WATER_LEVEL

## Spec: roads give a slight speed increase.
func on_road() -> bool:
	if terrain == null:
		return false
	return terrain.is_road(global_position.x, global_position.z)

## True when nobody is at the wheel. A parked truck has its brakes on: it stays
## where it was left rather than being shoved about by whatever walks into it.
func parked() -> bool:
	return driver == null and not autopilot

## Suspension and tyres, per wheel.
##
## The truck used to be steered by dropping a yaw torque on the chassis and
## driven by a force through its centre of mass, which is why it behaved like a
## shopping trolley on ice: the body turned, and the velocity carried straight
## on regardless. Now every wheel does its own work at its own contact patch.
## The front pair points where it is steered and the whole thing corners because
## those tyres bite, and what any tyre can do - drive, brake or hold a line - is
## bounded by the load that wheel is carrying.
func _apply_wheels(delta: float) -> void:
	# A parked truck asleep on its brakes gets no forces at all. Forces pushed
	# at a sleeping body are not thrown away: they pile up, and the first
	# frame it wakes it gets every frame's worth of spring at once and leaps.
	if sleeping and parked():
		return
	var space := get_world_3d().direct_space_state
	var up := global_transform.basis.y
	var forward := -global_transform.basis.z
	var standing := parked()
	_grounded = 0

	# Steering softens with speed, so the truck is not twitchy at 20 m/s.
	var speed := linear_velocity.length()
	var steer_angle: float = input_steer * max_steer_angle / (1.0 + speed * 0.07)
	var road_bonus: float = 1.0 + (Terrain.ROAD_SPEED_BONUS if on_road() else 0.0)
	var throttle: float = 0.0 if (standing or flooded()) else input_throttle
	var along := linear_velocity.dot(forward)
	# At the ceiling the engine stops pushing that way, rather than the velocity
	# being yanked back, which would fight the tyres.
	if along > max_speed * road_bonus:
		throttle = minf(throttle, 0.0)
	elif along < -max_speed * road_bonus * 0.5:
		throttle = maxf(throttle, 0.0)

	var contacts: Array[Dictionary] = []
	for i in WHEEL_OFFSETS.size():
		var start: Vector3 = global_transform * (WHEEL_OFFSETS[i] as Vector3)
		var q := PhysicsRayQueryParameters3D.create(start, start - up * suspension_rest,
			Layers.WORLD | Layers.MACHINE, [get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		_grounded += 1
		var arm: Vector3 = start - global_position
		var point_velocity: Vector3 = linear_velocity + angular_velocity.cross(arm)
		var compression: float = clampf(
			1.0 - start.distance_to(hit.position) / suspension_rest, 0.0, 1.0)
		var load: float = maxf(0.0, compression * suspension_strength
			- point_velocity.dot(up) * suspension_damping)
		apply_force(up * load, arm)
		contacts.append({"index": i, "arm": arm, "load": load, "velocity": point_velocity})

	if contacts.is_empty():
		return

	var share := float(contacts.size())
	for contact in contacts:
		var index: int = contact.index
		var arm: Vector3 = contact.arm
		var load: float = contact.load
		var v: Vector3 = contact.velocity

		# The front pair points where it is steered; the rear stays straight.
		var wheel_forward := forward
		if (WHEEL_OFFSETS[index] as Vector3).z < 0.0 and absf(steer_angle) > 0.001:
			wheel_forward = forward.rotated(up, steer_angle)
		var wheel_side := wheel_forward.cross(up).normalized()

		var grip: float = tyre_grip * load
		var lateral: float = clampf(
			-v.dot(wheel_side) * lateral_stiffness * mass / share, -grip, grip)

		var rolling := v.dot(wheel_forward)
		var drive := 0.0
		if standing or input_brake:
			# Locked wheels.
			drive = -rolling * lateral_stiffness * mass / share
		elif absf(throttle) > 0.05:
			drive = throttle * engine_force_max * road_bonus / share
		else:
			drive = -rolling * rolling_resistance * mass * 9.0
		drive = clampf(drive, -grip, grip)

		apply_force(wheel_forward * drive + wheel_side * lateral, arm)

	# Settled and nobody aboard: let it sleep, so it is genuinely parked rather
	# than merely slow.
	if standing and _grounded >= 3 and speed < 0.25 and angular_velocity.length() < 0.25 \
			and not unloading() and not _load_settling():
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		sleeping = true
		# The load goes to sleep with it, in the same step. A sleeping truck
		# under a load that is still awake does not push back properly.
		for item in _load:
			item.linear_velocity = Vector3.ZERO
			item.angular_velocity = Vector3.ZERO
			item.sleeping = true

## Something in the bed is still moving about relative to the truck - rolling,
## sliding, landing. The truck waits for it to settle before parking up, and
## then truck and load go to sleep together.
func _load_settling() -> bool:
	for item in _load:
		if item.sleeping:
			continue
		var carry := linear_velocity + angular_velocity.cross(item.global_position - global_position)
		if (item.linear_velocity - carry).length() > 0.3 or item.angular_velocity.length() > 0.6:
			return true
	return false

func _clamp_motion() -> void:
	var ceiling := max_speed * 1.4 * (1.0 + Terrain.ROAD_SPEED_BONUS)
	if linear_velocity.length() > ceiling:
		linear_velocity = linear_velocity.normalized() * ceiling
	if angular_velocity.length() > 3.5:
		angular_velocity = angular_velocity.normalized() * 3.5

## Upright rescue: a hauler on its roof is unrecoverable for the player.
## Whatever is still in the bed is lifted with it, rather than left where the
## truck was and dropped through the deck.
func recover() -> void:
	var before := global_transform
	var riders: Array = []
	for item in _load:
		riders.append([item, before.affine_inverse() * item.global_transform])
	var pos := global_position + Vector3(0, 1.2, 0)
	var yaw := global_rotation.y
	var after := Transform3D(Basis.from_euler(Vector3(0, yaw, 0)), pos)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, after)
	global_transform = after
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	for pair in riders:
		(pair[0] as LooseItem).teleport(after * (pair[1] as Transform3D))

## The load is saved with the truck, relative to the bed, so it comes back
## lying where it was wherever the truck was left.
func to_dict() -> Dictionary:
	var entries: Array = []
	var inverse := global_transform.affine_inverse()
	for item in _load:
		var t := inverse * item.global_transform
		entries.append({"id": String(item.item_id), "dims": Solid.to_dict(item.dims),
			"local": [t.origin.x, t.origin.y, t.origin.z,
				t.basis.x.x, t.basis.x.y, t.basis.x.z,
				t.basis.y.x, t.basis.y.y, t.basis.y.z,
				t.basis.z.x, t.basis.z.y, t.basis.z.z]})
	return {"position": [global_position.x, global_position.y, global_position.z],
		"yaw": global_rotation.y, "cargo": entries}

func from_dict(d: Dictionary) -> void:
	var p: Array = d.get("position", [0, 2, 0])
	var xform := Transform3D(Basis.from_euler(Vector3(0, float(d.get("yaw", 0.0)), 0)),
		Vector3(p[0], p[1], p[2]))
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xform)
	global_transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if manager != null:
		for item in _load:
			manager.despawn(item)
	_load.clear()
	for entry in d.get("cargo", []):
		var id := StringName(entry.get("id", ""))
		var dims := Solid.from_dict(entry.get("dims", {}))
		var l: Array = entry.get("local", [])
		if l.size() != 12 or manager == null:
			# Saves from before the load was real: put it in the bed.
			load_item(id, dims)
			continue
		var local := Transform3D(Basis(Vector3(l[3], l[4], l[5]), Vector3(l[6], l[7], l[8]),
			Vector3(l[9], l[10], l[11])), Vector3(l[0], l[1], l[2]))
		var item := manager.spawn(id, xform * local, plot_id, Vector3.ZERO, dims, true)
		if item != null:
			_take(item)
	cargo_changed.emit(_load.size(), cargo_capacity_m3)
