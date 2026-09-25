class_name Hauler
extends RigidBody3D

## A drivable vehicle: quad bike, pickup, flatbed, log truck, dump truck...
## They are all this one body, sized, weighted and dressed from vehicles.json.
## The class keeps its old name because the flatbed hauler came first.
##
## The wheels are real: each is its own rigid body, hung from the chassis on a
## sprung joint, turned by a motor on its axle and steered by turning the joint.
## Nothing pushes the truck but its tyres on the ground - grip is the tyre's
## friction under the weight on it, a wheel in the air drives nothing, and a
## truck that bottoms out or loses a wheel over an edge behaves like it.
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
## How far a wheel sinks under the truck's own weight, and how far it can go
## up into the arch or down off an edge.
const SAG := 0.12
const BUMP := 0.22
const DROOP := 0.3
## Friction coefficient at the tyre. What a wheel can do is this times the load
## it carries, so a wheel in the air grips nothing and a light end lets go first.
@export var tyre_grip: float = 1.7
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
## tests (and, later, any automation) can drive the vehicle without a keyboard.
var input_throttle: float = 0.0
var input_steer: float = 0.0
var input_brake: bool = false
var autopilot: bool = false

## Which vehicle this is, and its row from vehicles.json.
var vehicle_id: StringName = &"hauler"
var display_name: String = "Flatbed Hauler"
var spec: Dictionary = {}
## Body style (truck, quad, buggy) and bed kind (sides, stakes, tub, rack, none).
var style: StringName = &"truck"
var bed_kind: StringName = &"sides"
var paint: Color = Color(0.62, 0.20, 0.16)
## How far back the chase camera sits.
var camera_distance: float = 9.0

## The hull and the bed, in the vehicle's own frame. The bed is the space
## inside the walls: from the headboard to the tailgate.
var body_size := Vector3(2.6, 0.7, 5.0)
var bed_floor := 0.35
var bed_front := -0.72
var bed_back := 2.26
var bed_length := 2.98
var bed_mid_z := 0.77
var bed_half_width := 1.15
var wall_height := 1.1
var headboard_height := 1.45
const BED_FRICTION := 0.9
## Ray origins sit at the chassis underside: the springs, not the box, must
## carry the vehicle, or the chassis grinds along the ground and the drive
## force fights friction instead of moving it.
var wheel_offsets: Array = [
	Vector3(-1.1, -0.35, -1.7), Vector3(1.1, -0.35, -1.7),
	Vector3(-1.1, -0.35, 1.7), Vector3(1.1, -0.35, 1.7),
]
## The front axle's Z: those wheels steer.
var _front_z: float = -1.7

## Pieces lying in the bed right now, refreshed by the bed poll.
var _load: Array[LooseItem] = []
## Settled pieces fixed into the truck while it is driven: each is part of the
## truck - its shape in the truck's collision, its weight in the truck's mass
## - lying exactly as it settled. {item: {shapes, mass}}
var _fixed: Dictionary = {}
## How long each piece in the bed has lain still, relative to the truck.
var _still_for: Dictionary = {}
const FIX_SPEED := 0.25          ## m/s relative to the bed, and rad/s of spin
const FIX_SECONDS := 0.4
var _tailgate: CollisionShape3D
var _tailgate_mesh: Node3D
## Unloading: seconds left of the bed floor walking the load out the back,
## and the pieces being walked out.
var _tip_time: float = 0.0
var _tipping: Array[LooseItem] = []
## Dump tub: its colliders and mesh with their resting poses, and how far it
## is tipped (radians about the rear hinge) and wants to be.
var _tub_parts: Array = []
var _tub_mesh: Node3D
var _tub_angle: float = 0.0
var _tub_target: float = 0.0
var _tub_hold: float = 0.0
const TUB_TIP := 0.95
const TUB_SPEED := 0.45
var _wheels: Array[MeshInstance3D] = []
## The wheels as bodies, their joints, and where each hangs in the chassis frame.
var wheel_bodies: Array[RigidBody3D] = []
var _joints: Array[Generic6DOFJoint3D] = []
var _anchors: Array[Vector3] = []
var _cargo_area: Area3D
var _cargo_shape: CollisionShape3D
var _seat: Node3D
var rig: VehicleRig
var _grounded: int = 0
var _poll: float = 0.0

func setup(p_manager: LooseItemManager, p_plot_id: int = 0, p_vehicle: StringName = &"hauler") -> void:
	manager = p_manager
	plot_id = p_plot_id
	vehicle_id = p_vehicle

## Reads the vehicle's row. Called from _ready, so `vehicle_id` (or `spec`)
## has to be set before the vehicle enters the tree.
func _apply_spec() -> void:
	if spec.is_empty():
		spec = GameData.vehicle(vehicle_id)
	if spec.is_empty():
		spec = GameData.vehicle(&"hauler")
	if spec.is_empty():
		return
	vehicle_id = StringName(spec.get("id", "hauler"))
	display_name = String(spec.get("display_name", "Vehicle"))
	style = StringName(spec.get("style", "truck"))
	mass = float(spec.get("mass", 900))
	engine_force_max = float(spec.get("engine", 16000))
	max_speed = float(spec.get("max_speed", 22))
	tyre_grip = float(spec.get("grip", 1.7))
	max_steer_angle = float(spec.get("steer", 0.55))
	body_size = _vec(spec.get("body", [2.6, 0.7, 5.0]))
	wheel_radius = float(spec.get("wheel_radius", 0.45))
	wheel_width = float(spec.get("wheel_width", 0.34))
	suspension_rest = float(spec.get("suspension_rest", 0.75))
	cargo_capacity_m3 = float(spec.get("capacity", 8))
	camera_distance = float(spec.get("camera", 9.0))
	var c: Array = spec.get("paint", [0.62, 0.2, 0.16])
	paint = Color(c[0], c[1], c[2])
	wheel_offsets.clear()
	_front_z = INF
	for w in spec.get("wheels", []):
		var v := _vec(w)
		wheel_offsets.append(v)
		_front_z = minf(_front_z, v.z)
	var bed: Dictionary = spec.get("bed", {})
	bed_kind = StringName(bed.get("kind", "none"))
	bed_floor = body_size.y * 0.5
	bed_front = float(bed.get("front", 0.0))
	bed_back = float(bed.get("back", 0.0))
	bed_half_width = float(bed.get("half_width", 0.0))
	wall_height = float(bed.get("wall", 0.0))
	headboard_height = float(bed.get("head", 0.0))
	if bed_kind == &"tub":
		bed_floor += 0.15       # the tub has its own floor plate on the chassis
	bed_length = bed_back - bed_front
	bed_mid_z = (bed_front + bed_back) * 0.5

static func _vec(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))

func has_bed() -> bool:
	return bed_kind != &"none" and cargo_capacity_m3 > 0.0

func _ready() -> void:
	_apply_spec()
	collision_layer = Layers.VEHICLE
	collision_mask = Layers.WORLD | Layers.LOOSE | Layers.MACHINE | Layers.TREE | Layers.PLAYER
	can_sleep = true
	continuous_cd = true          # a heavy box at 20+ m/s must never tunnel
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.25
	angular_damp = 2.5
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	# Low: makes rollovers very unlikely.
	center_of_mass = Vector3(0, float(spec.get("com_y", -0.45)), 0)
	_build()
	# The wheels go on once the truck is where it is going: a pad puts it in
	# place just after adding it.
	_build_wheels.call_deferred()

func _build() -> void:
	var chassis := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = body_size
	chassis.shape = box
	add_child(chassis)
	# A cab is solid: loads fetch up against it and it keeps logs out of it.
	var cab: Dictionary = spec.get("cab", {})
	if not cab.is_empty():
		var cab_size := _vec(cab.size)
		_collider(cab_size, Vector3(0, body_size.y * 0.5 + cab_size.y * 0.5, float(cab.z)))

	# Boards and loads grip one another: a load slides when it is thrown about,
	# not at every touch of the brakes.
	var pm := PhysicsMaterial.new()
	pm.friction = BED_FRICTION
	physics_material_override = pm

	match bed_kind:
		&"sides", &"rack":
			_build_walled_bed()
		&"stakes":
			_build_stake_bed()
		&"tub":
			_build_tub()

	if has_bed():
		_cargo_area = Area3D.new()
		_cargo_area.collision_layer = Layers.TRIGGER
		_cargo_area.collision_mask = Layers.LOOSE
		var acs := CollisionShape3D.new()
		var ab := BoxShape3D.new()
		var tall := maxf(wall_height, 0.3) + 0.6
		ab.size = Vector3(bed_half_width * 2.0, tall, bed_length)
		acs.shape = ab
		acs.position = Vector3(0, bed_floor + tall * 0.5, bed_mid_z)
		_cargo_shape = acs
		_cargo_area.add_child(acs)
		add_child(_cargo_area)

	VehicleModel.dress(self)

	# Spec: most vehicles carry a winch, many carry a crane.
	var gear: Variant = spec.get("rig", null)
	if gear is Dictionary:
		rig = VehicleRig.new()
		rig.name = "Rig"
		rig.winch_power_kg = float(gear.get("winch", 4000))
		rig.crane_power_kg = float(gear.get("crane", 0))
		rig.reach = float(gear.get("reach", 14))
		rig.head_offset = _vec(gear.get("head", [0, 1.1, -1.2]))
		rig.setup(self)
		add_child(rig)

	_seat = Node3D.new()
	_seat.position = _vec(spec.get("seat", [0, 1.2, -1.9]))
	add_child(_seat)

func _collider(size: Vector3, pos: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = pos
	add_child(cs)
	return cs

## Tall sides, a headboard that guards the cab, and a tailgate. Thick, so a
## piece thrown at them at speed meets a wall rather than slipping through.
func _build_walled_bed() -> void:
	var t := 0.3 if bed_kind == &"sides" else 0.12
	for side in [-1.0, 1.0]:
		_collider(Vector3(t, wall_height, bed_length + 0.2),
			Vector3(side * (bed_half_width + t * 0.5), bed_floor + wall_height * 0.5, bed_mid_z))
	_collider(Vector3(bed_half_width * 2.0 + t * 2.0, headboard_height, 0.24),
		Vector3(0, bed_floor + headboard_height * 0.5, bed_front - 0.12))
	_tailgate = _collider(Vector3(bed_half_width * 2.0 + t * 2.0, wall_height, 0.24),
		Vector3(0, bed_floor + wall_height * 0.5, bed_back + 0.12))

## A log bed: a headboard and rows of tall stakes down each side, open at the
## back so long trunks can hang over it.
func _build_stake_bed() -> void:
	_collider(Vector3(bed_half_width * 2.0 + 0.5, headboard_height, 0.3),
		Vector3(0, bed_floor + headboard_height * 0.5, bed_front - 0.15))
	for z in stake_positions():
		for side in [-1.0, 1.0]:
			_collider(Vector3(0.18, wall_height, 0.18),
				Vector3(side * (bed_half_width + 0.09), bed_floor + wall_height * 0.5, z))

func stake_positions() -> Array[float]:
	var out: Array[float] = []
	var n := maxi(2, int(bed_length / 1.4) + 1)
	for i in n:
		out.append(bed_front + 0.3 + (bed_length - 0.6) * float(i) / float(n - 1))
	return out

## A steel tub on its own floor plate, hinged at the back: it tips up to
## pour out whatever is in it. Its colliders are kept with their resting
## poses so they can be swung about the hinge.
func _build_tub() -> void:
	var parts := [
		[Vector3(bed_half_width * 2.0 + 0.4, 0.15, bed_length + 0.3), Vector3(0, bed_floor - 0.075, bed_mid_z)],
		[Vector3(0.2, wall_height, bed_length + 0.3), Vector3(-bed_half_width - 0.1, bed_floor + wall_height * 0.5, bed_mid_z)],
		[Vector3(0.2, wall_height, bed_length + 0.3), Vector3(bed_half_width + 0.1, bed_floor + wall_height * 0.5, bed_mid_z)],
		[Vector3(bed_half_width * 2.0 + 0.4, headboard_height, 0.24), Vector3(0, bed_floor + headboard_height * 0.5, bed_front - 0.12)],
	]
	for p in parts:
		var cs := _collider(p[0], p[1])
		_tub_parts.append([cs, cs.transform])
	_tailgate = _collider(Vector3(bed_half_width * 2.0 + 0.4, wall_height, 0.2),
		Vector3(0, bed_floor + wall_height * 0.5, bed_back + 0.1))
	_tub_parts.append([_tailgate, _tailgate.transform])

func hinge() -> Vector3:
	return Vector3(0, body_size.y * 0.5, bed_back + 0.1)

## Swings the tub (and its tailgate) about the rear hinge.
func _pose_tub(angle: float) -> void:
	var h := hinge()
	var swing := Transform3D(Basis(Vector3.RIGHT, angle), h) * Transform3D(Basis(), -h)
	for part in _tub_parts:
		(part[0] as CollisionShape3D).transform = swing * (part[1] as Transform3D)
	if _tub_mesh != null:
		_tub_mesh.transform = swing

func tub_angle() -> float:
	return _tub_angle

func _update_tub(delta: float) -> void:
	if _tub_parts.is_empty():
		return
	if _tub_hold > 0.0 and absf(_tub_angle - _tub_target) < 0.01:
		_tub_hold -= delta
		if _tub_hold <= 0.0:
			_tub_target = 0.0
			_set_floor_slick(false)
	if absf(_tub_angle - _tub_target) < 0.0005:
		return
	_tub_angle = move_toward(_tub_angle, _tub_target, TUB_SPEED * delta)
	_pose_tub(_tub_angle)
	# Moving colliders do not wake what rests on them - nor the truck they
	# are part of, which has to be awake for them to push anything.
	sleeping = false
	for item in _load:
		item.sleeping = false
	if _tub_angle == 0.0 and _tub_target == 0.0:
		_set_tailgate(false)
		_clear_under_tub()

## Anything that slid in under the raised tub would be crushed into the
## chassis as it came down; it is squeezed out behind the truck instead.
func _clear_under_tub() -> void:
	if manager == null:
		return
	var inverse := global_transform.affine_inverse()
	for item in manager.free_items():
		var local := inverse * item.global_position
		if absf(local.x) < bed_half_width + 0.2 and local.z > bed_front and local.z < bed_back \
				and local.y > body_size.y * 0.5 - 0.2 and local.y < bed_floor:
			item.teleport(Transform3D(item.global_transform.basis,
				global_transform * Vector3(local.x, bed_floor + 0.3, bed_back + 1.2)))

## The front axle's wheels are the ones that steer.
func _is_front(index: int) -> bool:
	return absf((wheel_offsets[index] as Vector3).z - _front_z) < 0.1

## Whether a point on the vehicle is where you would climb in: the cab, or
## close to the seat on an open vehicle.
func is_seat_point(world_point: Vector3) -> bool:
	var local := global_transform.affine_inverse() * world_point
	var seat := _vec(spec.get("seat", [0, 1.2, -1.9]))
	var cab: Dictionary = spec.get("cab", {})
	if not cab.is_empty():
		var size := _vec(cab.size)
		return absf(local.z - float(cab.z)) <= size.z * 0.5 + 0.2 and local.y > body_size.y * 0.5 - 0.3
	return Vector2(local.x - seat.x, local.z - seat.z).length() < 1.1

func seat_transform() -> Transform3D:
	return _seat.global_transform

## How high above a pad to put the vehicle so it drops onto its wheels.
func spawn_height() -> float:
	var low := 0.0
	for o in wheel_offsets:
		low = minf(low, (o as Vector3).y)
	return wheel_radius - low + SAG + 0.3

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
	return has_bed() and not cargo_full()

## Puts a piece into the bed: set down on the lowest part of the load, lying
## the way it fits - short pieces across, long ones fore-and-aft - and moving
## with the truck. From there it is on its own.
func accept_item(item: LooseItem) -> bool:
	if not has_bed() or cargo_full() or item == null or item.state == LooseItem.State.POOLED:
		return false
	if item.state != LooseItem.State.FREE:
		item.set_state(LooseItem.State.FREE)
	var long := item.length() > bed_half_width * 2.0 - 0.2
	var basis := LooseItem.lying_basis(0.0 if long else PI * 0.5)
	var xs := [-0.55, 0.0, 0.55] if long else [0.0]
	var zs := [bed_mid_z] if long else [bed_front + 0.5, bed_mid_z, bed_back - 0.5]
	var best := Vector3(0, INF, bed_mid_z)
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
	var from := global_transform * Vector3(local.x, bed_floor + wall_height + 2.0, local.z)
	var to := global_transform * Vector3(local.x, bed_floor - 0.2, local.z)
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.LOOSE | Layers.VEHICLE,
		[ignore.get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return bed_floor
	return maxf(bed_floor, (global_transform.affine_inverse() * (hit.position as Vector3)).y)

## Adds one piece to the load. There is no physics-free cargo any more, so
## this makes a real piece and puts it in the bed.
func load_item(item_id: StringName, dims: Dictionary = {}) -> bool:
	if not has_bed() or cargo_full() or manager == null:
		return false
	var item := manager.spawn(item_id, global_transform * Transform3D(Basis(), Vector3(0, 3, bed_mid_z)),
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
	if _cargo_area == null:
		return
	var inside: Array[LooseItem] = []
	for body in Trigger.bodies_inside(_cargo_area, _cargo_shape, 0.05):
		var item := body as LooseItem
		if item != null and item.state == LooseItem.State.FREE:
			inside.append(item)
	var before := _load.size()
	for item in _load.duplicate():
		if not inside.has(item) and not _fixed.has(item):
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

# --- A load fixed in place -------------------------------------------------------

## With someone in the seat, the load that has settled in the bed becomes part
## of the truck, exactly as it lies: nothing in it shifts, slides or bounces
## out however the truck is driven. It comes loose again when the driver gets
## out, the crane goes to work, or the load is tipped or dropped off.
func _update_fixed(delta: float) -> void:
	var may_fix := driver != null and not _crane_busy() and _tipping_items().is_empty() \
		and _tub_angle < 0.001 and _tub_target < 0.001
	if not may_fix:
		if not _fixed.is_empty():
			release_load()
		_still_for.clear()
		return
	for item in _load:
		if _fixed.has(item) or not is_instance_valid(item) or item.state != LooseItem.State.FREE:
			continue
		var at := item.global_position
		var carried := linear_velocity + angular_velocity.cross(at - global_position)
		var still := (item.linear_velocity - carried).length() < FIX_SPEED \
			and (item.angular_velocity - angular_velocity).length() < FIX_SPEED
		_still_for[item] = float(_still_for.get(item, 0.0)) + delta if still else 0.0
		if float(_still_for[item]) >= FIX_SECONDS:
			_fix(item)

func _crane_busy() -> bool:
	return rig != null and (rig.operating or rig.folding)

## Whatever is being walked out of the back right now.
func _tipping_items() -> Array:
	return _tipping

## Makes one settled piece part of the truck.
func _fix(item: LooseItem) -> void:
	item.set_state(LooseItem.State.CAPTURED)
	item.collision_layer = 0
	item.collision_mask = 0
	item.reparent(self, true)
	# Out of the physics world altogether: it is only the truck's shape and
	# the truck's weight now, carried exactly where it lies.
	item.disable_mode = CollisionObject3D.DISABLE_MODE_REMOVE
	item.process_mode = Node.PROCESS_MODE_DISABLED
	var shapes: Array[CollisionShape3D] = []
	for c in item.get_children():
		var cs := c as CollisionShape3D
		if cs == null or cs.shape == null or cs.disabled:
			continue
		var copy := CollisionShape3D.new()
		copy.shape = cs.shape
		copy.transform = item.transform * cs.transform
		add_child(copy)
		shapes.append(copy)
	_fixed[item] = {"shapes": shapes, "mass": item.mass}
	mass += item.mass
	_still_for.erase(item)

## Lets every fixed piece loose again, where it lies and moving with the truck.
func release_load() -> void:
	for item: LooseItem in _fixed.keys():
		var rec: Dictionary = _fixed[item]
		for cs: CollisionShape3D in rec.shapes:
			if is_instance_valid(cs):
				cs.queue_free()
		mass = maxf(1.0, mass - float(rec.mass))
		if not is_instance_valid(item) or item.state != LooseItem.State.CAPTURED:
			continue
		var at := item.global_transform
		if manager != null:
			item.reparent(manager, true)
		item.process_mode = Node.PROCESS_MODE_INHERIT
		item.collision_layer = Layers.LOOSE
		item.collision_mask = Layers.MASK_LOOSE
		item.set_state(LooseItem.State.FREE)
		item.teleport(at)
		item.linear_velocity = linear_velocity + angular_velocity.cross(at.origin - global_position)
	_fixed.clear()

## How many pieces of the load are fixed in place.
func fixed_count() -> int:
	return _fixed.size()

func is_fixed(item: LooseItem) -> bool:
	return _fixed.has(item)

## Spec: unload. The tailgate drops and the bed floor walks the load out the
## back - it slides out under the push, and a piece that is wedged stays
## wedged. Returns how many pieces were aboard.
func unload(_behind: bool = true) -> int:
	release_load()
	var n := _load.size()
	if n == 0:
		return 0
	if bed_kind == &"tub":
		# Up goes the tub, and the load pours out over the tailgate.
		_tub_target = TUB_TIP
		_tub_hold = 3.0
		_set_tailgate(true)
		_set_floor_slick(true)
		return n
	_start_tipping(_load.duplicate(), 5.0)
	return n

## Drops exactly one piece - the one nearest the tailgate - off the back.
func unload_one() -> bool:
	if _load.is_empty():
		return false
	release_load()
	var inverse := global_transform.affine_inverse()
	var last: LooseItem = _load[0]
	for item in _load:
		if (inverse * item.global_position).z > (inverse * last.global_position).z:
			last = item
	_start_tipping([last], 3.0)
	return true

func unloading() -> bool:
	return _tip_time > 0.0 or _tub_target > 0.0 or _tub_angle > 0.0

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
	if _tailgate == null:
		return
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
	return local.y > bed_floor - 0.15 and local.z - reach < body_size.z * 0.5 + 0.05 \
		and absf(local.x) < body_size.x * 0.5 + 0.3

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
		if (inverse * item.global_position).z > bed_back - item.extent_along(global_transform.basis.z) + 0.08:
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
	_update_tub(delta)
	_update_fixed(delta)

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
		for body in wheel_bodies:
			body.sleeping = false
	_drive_wheels()
	_clamp_motion()

func _read_input() -> void:
	if planted:
		# The controls are working the crane.
		input_throttle = 0.0
		input_steer = 0.0
		input_brake = true
		return
	input_throttle = Input.get_axis("move_back", "move_forward")
	input_steer = Input.get_axis("move_right", "move_left")
	input_brake = Input.is_action_pressed("jump")

## Stood on its outriggers for the crane: it does not roll, rock or tip, and
## the crane's load is carried into the ground.
var planted: bool = false

func set_planted(on: bool) -> void:
	planted = on
	if on:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = on
	sleeping = false

## Spec: a driver seat under water means the truck can no longer be driven.
func flooded() -> bool:
	if terrain == null or _seat == null:
		return false
	if _seat.global_position.y >= Terrain.WATER_LEVEL:
		return false
	# Below the sea in a cave is dry.
	return CaveNetwork.active == null or not CaveNetwork.active.contains(_seat.global_position, 1.0)

## Spec: roads give a slight speed increase.
func on_road() -> bool:
	if terrain == null:
		return false
	return terrain.is_road(global_position.x, global_position.z)

## True when nobody is at the wheel. A parked truck has its brakes on: it stays
## where it was left rather than being shoved about by whatever walks into it.
func parked() -> bool:
	return driver == null and not autopilot

# --- Wheels -------------------------------------------------------------------

## Hangs a wheel body under each wheel position: a cylinder of rubber on a
## joint that lets it ride up and down on a spring, spin on its axle under a
## motor, and - at the front - turn to steer. The wheel models go on them.
func _build_wheels() -> void:
	if not wheel_bodies.is_empty() or not is_inside_tree():
		return
	var n := maxi(1, wheel_offsets.size())
	var share := mass * 9.8 / float(n)
	var wheel_mass := maxf(15.0, mass * 0.035)
	# The joint spring is softer than its number says (Jolt), by this much.
	var stiffness := share / SAG * 2.4
	var damping := 2.0 * 0.55 * sqrt(stiffness * mass / float(n))
	var grip := PhysicsMaterial.new()
	grip.friction = tyre_grip
	grip.rough = true
	for i in wheel_offsets.size():
		var o: Vector3 = wheel_offsets[i]
		var anchor := Vector3(o.x + signf(o.x) * 0.12, o.y, o.z)
		var body := RigidBody3D.new()
		body.name = "Wheel%d" % i
		body.top_level = true
		body.mass = wheel_mass
		body.collision_layer = Layers.VEHICLE
		body.collision_mask = Layers.WORLD | Layers.LOOSE | Layers.MACHINE | Layers.TREE
		body.physics_material_override = grip
		body.continuous_cd = true
		body.angular_damp = 0.3
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = wheel_radius
		cyl.height = wheel_width
		cs.shape = cyl
		cs.rotation = Vector3(0, 0, PI * 0.5)
		body.add_child(cs)
		add_child(body)
		body.global_transform = global_transform * Transform3D(Basis(), anchor)
		add_collision_exception_with(body)
		for other in wheel_bodies:
			body.add_collision_exception_with(other)
		if i < _wheels.size():
			var mesh := _wheels[i]
			mesh.reparent(body, false)
			mesh.transform = Transform3D(Basis.from_euler(Vector3(0, 0, PI * 0.5)), Vector3.ZERO)
		var j := Generic6DOFJoint3D.new()
		j.name = "Axle%d" % i
		j.position = anchor
		add_child(j)
		for ax in ["x", "z"]:
			j.set("linear_limit_%s/enabled" % ax, true)
			j.set("linear_limit_%s/upper_distance" % ax, 0.0)
			j.set("linear_limit_%s/lower_distance" % ax, 0.0)
		j.set("linear_limit_y/enabled", true)
		j.set("linear_limit_y/upper_distance", BUMP)
		j.set("linear_limit_y/lower_distance", -DROOP)
		j.set("linear_spring_y/enabled", true)
		j.set("linear_spring_y/stiffness", stiffness)
		j.set("linear_spring_y/damping", damping)
		# Where the spring would put the wheel with no weight on it: one
		# sag below, so under the truck it sits where it is drawn.
		j.set("linear_spring_y/equilibrium_point", -SAG)
		j.set("angular_limit_x/enabled", false)
		j.set("angular_motor_x/enabled", true)
		j.set("angular_motor_x/target_velocity", 0.0)
		j.set("angular_motor_x/force_limit", _brake_torque())
		for ax2 in ["y", "z"]:
			j.set("angular_limit_%s/enabled" % ax2, true)
			j.set("angular_limit_%s/upper_angle" % ax2, 0.0)
			j.set("angular_limit_%s/lower_angle" % ax2, 0.0)
		j.node_a = j.get_path_to(self)
		j.node_b = j.get_path_to(body)
		wheel_bodies.append(body)
		_joints.append(j)
		_anchors.append(anchor)

func _brake_torque() -> float:
	return mass * 9.8 / float(maxi(1, wheel_offsets.size())) * wheel_radius * 1.6

## Puts the wheels back under the chassis wherever it now is: for a truck
## moved in one go (a pad, a recovery, a load) rather than driven there.
func _snap_wheels() -> void:
	for i in wheel_bodies.size():
		var body := wheel_bodies[i]
		var xform := global_transform * Transform3D(Basis(), _anchors[i])
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xform)
		body.global_transform = xform
		body.linear_velocity = linear_velocity
		body.angular_velocity = Vector3.ZERO

## Throttle, brakes and steering, through the joints. The motor on each axle
## turns the wheel toward the speed asked for with no more than the engine's
## torque; the tyre on the ground does the rest.
func _drive_wheels() -> void:
	if wheel_bodies.is_empty():
		return
	# Anything that moved the chassis in one jump takes its wheels with it.
	if global_transform.origin.distance_to(wheel_bodies[0].global_position
			- global_transform.basis * _anchors[0]) > 1.5:
		_snap_wheels()
	var standing := parked() or planted
	if sleeping and standing:
		return
	var forward := -global_transform.basis.z
	var speed := linear_velocity.dot(forward)
	# Steering softens with speed, so the truck is not twitchy at 20 m/s.
	var steer: float = input_steer * max_steer_angle / (1.0 + absf(speed) * 0.07)
	var bonus: float = 1.0 + (Terrain.ROAD_SPEED_BONUS if on_road() else 0.0)
	var throttle: float = 0.0 if (standing or flooded()) else input_throttle
	var n := float(wheel_bodies.size())
	var target := 0.0
	var torque := 0.0
	if standing or input_brake:
		torque = _brake_torque()
	elif absf(throttle) > 0.05:
		var top: float = max_speed * bonus if throttle > 0.0 else max_speed * 0.5
		target = throttle * top / wheel_radius
		torque = engine_force_max * bonus * wheel_radius / n
	else:
		# Coasting: only the drag of the drivetrain.
		torque = mass * 9.8 / n * wheel_radius * rolling_resistance
	_grounded = 0
	var space := get_world_3d().direct_space_state
	for i in wheel_bodies.size():
		var j := _joints[i]
		j.set("angular_motor_x/target_velocity", target)
		j.set("angular_motor_x/force_limit", torque)
		if _is_front(i):
			j.set("angular_limit_y/upper_angle", -steer)
			j.set("angular_limit_y/lower_angle", -steer)
		var at := wheel_bodies[i].global_position
		var q := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * (wheel_radius + 0.25),
			Layers.WORLD | Layers.MACHINE, [get_rid(), wheel_bodies[i].get_rid()])
		if not space.intersect_ray(q).is_empty():
			_grounded += 1
	# Parked, it goes to sleep once it, its wheels and its load have all been
	# still for a moment - so a load dropped in still presses the springs
	# down before it does.
	if standing and _still():
		_rest_time += get_physics_process_delta_time()
		if _rest_time > 0.5:
			sleeping = true
			for body in wheel_bodies:
				body.sleeping = true
			for item in _load:
				item.sleeping = true
	else:
		_rest_time = 0.0

var _rest_time: float = 0.0

func _still() -> bool:
	if linear_velocity.length() > 0.05 or angular_velocity.length() > 0.05:
		return false
	for body in wheel_bodies:
		if (body.linear_velocity - linear_velocity).length() > 0.05:
			return false
	for item in _load:
		if not item.sleeping and (item.linear_velocity.length() > 0.08 or item.angular_velocity.length() > 0.2):
			return false
	return not unloading()

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
	move_to(Transform3D(Basis.from_euler(Vector3(0, global_rotation.y, 0)), global_position + Vector3(0, 1.2, 0)))

## Puts the truck at `after`, stopped, its wheels under it and its load still
## in the bed.
func move_to(after: Transform3D) -> void:
	var before := global_transform
	var riders: Array = []
	for item in _load:
		if not _fixed.has(item):
			riders.append([item, before.affine_inverse() * item.global_transform])
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, after)
	global_transform = after
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_snap_wheels()
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
	return {"vehicle": String(vehicle_id),
		"position": [global_position.x, global_position.y, global_position.z],
		"yaw": global_rotation.y, "cargo": entries}

func from_dict(d: Dictionary) -> void:
	var p: Array = d.get("position", [0, 2, 0])
	var at := Vector3(p[0], p[1], p[2])
	# Never back under the land: saved mid-bounce, or sunk, it comes back
	# stood on top.
	if terrain != null:
		at.y = maxf(at.y, terrain.height_at(at.x, at.z) + spawn_height())
	var xform := Transform3D(Basis.from_euler(Vector3(0, float(d.get("yaw", 0.0)), 0)), at)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xform)
	global_transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_snap_wheels()
	# A truck spawned for the load builds its wheels a frame late: they go
	# under it once they exist.
	_snap_wheels.call_deferred()
	release_load()
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
