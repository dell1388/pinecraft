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

## Towing. A truck with a hitch can pull a trailer; a trailer is a vehicle
## with no engine, no seat and no steering, that rolls on free wheels and
## brakes when whatever pulls it brakes. They are joined by a ball joint at
## the hitch, so the trailer follows round corners and over bumps by itself.
var is_trailer: bool = false
var hitch_offset: Vector3 = Vector3.ZERO       ## a truck's hitch, in its frame
var tongue_offset: Vector3 = Vector3.ZERO      ## a trailer's coupling, in its frame
var towing: Hauler = null
var towed_by: Hauler = null
## The heaviest trailer this truck will pull, by the trailer's own weight
## (kg), from `tow_limit` in vehicles.json; 0 pulls anything. The pickup
## takes the utility trailer and anything lighter, and not the big ones.
var tow_limit: float = 0.0
var _hitch_joint: PinJoint3D
var _stand: CollisionShape3D
var _stand_mesh: Node3D
## Exhaust smoke from the stack (trucks only).
var _smoke: CPUParticles3D
## How close a trailer's coupling has to be to a hitch to be hooked on.
const HITCH_REACH := 2.5

## Which vehicle this is, and its row from vehicles.json.
var vehicle_id: StringName = &"hauler"
var display_name: String = "Flatbed Hauler"
var spec: Dictionary = {}
## Body style (truck, quad, buggy) and bed kind (sides, stakes, tub, rack, deck, none).
var style: StringName = &"truck"
var bed_kind: StringName = &"sides"
var paint: Color = Color(0.62, 0.20, 0.16)
## A colour chosen at its pad, in place of the factory paint (alpha 0: none).
var paint_override: Color = Color(0, 0, 0, 0)
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
## The front axle's Z: those wheels steer. And the rearmost axle's, which on
## the long tandem trucks steers a little the other way to tighten the turn.
var _front_z: float = -1.7
var _rear_z: float = 1.7
var rear_steer: float = 0.0

# --- Gearbox ------------------------------------------------------------------

## Each gear's top speed as a share of the vehicle's. Low gears trade speed for
## pull: the torque at the wheels goes up as the gear comes down, which is what
## gets a loaded truck up a hill. Automatic unless the player turns on the
## manual gearbox (Settings > Controls), which only trucks have.
var gears: Array[float] = [0.3, 0.52, 0.76, 1.0]
var gear: int = 0
static var GEAR_TORQUE_EXP: float = Balance.num("vehicles.gear_torque_exponent", 1.0)
## The transmission upgrades add overdrive gears above a vehicle's own top
## gear: each one a higher top speed with less pull, so it is a cruising gear
## on the flat and the automatic drops out of it on a hill.
const OVERDRIVE: Array[float] = [1.15, 1.32, 1.5]
## Whole-fleet knobs, and what the tyre upgrades add on top.
static var ENGINE_MULT: float = Balance.num("vehicles.engine_multiplier", 1.0)
static var TOP_SPEED_MULT: float = Balance.num("vehicles.top_speed_multiplier", 1.0)
static var GRIP_MULT: float = Balance.num("vehicles.grip_multiplier", 1.0)
static var STEER_MULT: float = Balance.num("vehicles.steer_multiplier", 1.0)
## How much steering eases off with speed (per m/s).
static var STEER_SOFTEN: float = Balance.num("vehicles.steer_soften", 0.05)
## Recovering (setting it back on its wheels) is allowed this often.
static var RECOVER_COOLDOWN: float = Balance.num("vehicles.recover_cooldown", 1.0)
var _last_recover_frame: int = -100000

## Pieces lying in the bed right now, refreshed by the bed poll.
var _load: Array[LooseItem] = []
## Settled pieces fixed into the truck while it is driven: each is part of the
## truck - its shape in the truck's collision, its weight in the truck's mass
## - lying exactly as it settled. {item: {shapes, mass}}
var _fixed: Dictionary = {}
## How long each piece in the bed has lain still, relative to the truck.
var _still_for: Dictionary = {}
## How high over the walls a heaped load still counts as aboard.
const HEAP_HEIGHT := 2.5
const FIX_SPEED := 0.25          ## m/s relative to the bed, and rad/s of spin
const FIX_SECONDS := 0.4
var _tailgate: CollisionShape3D
## A low-loader's loading ramps: up (stowed on end at the back, a gate) or
## down to the ground to drive a machine aboard.
var ramps_down := false
var _ramps_flat: Array[CollisionShape3D] = []
var ramp_meshes: Array[Node3D] = []
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
var loader: LoaderArm
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
	tow_limit = float(spec.get("tow_limit", 0.0))
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
	if paint_override.a > 0.0:
		paint = Color(paint_override.r, paint_override.g, paint_override.b)
	wheel_offsets.clear()
	_front_z = INF
	for w in spec.get("wheels", []):
		var v := _vec(w)
		wheel_offsets.append(v)
		_front_z = minf(_front_z, v.z)
		_rear_z = maxf(_rear_z, v.z) if wheel_offsets.size() > 1 else v.z
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
	is_trailer = bool(spec.get("trailer", false))
	bike = bool(spec.get("bike", false))
	hitch_offset = _vec(spec.get("hitch", [0, 0, 0]))
	tongue_offset = _vec(spec.get("tongue", [0, 0, 0]))
	rear_steer = float(spec.get("rear_steer", 0.0))
	var box: Variant = spec.get("gears", null)
	if box is Array and not (box as Array).is_empty():
		gears.clear()
		for g in box:
			gears.append(float(g))
	elif style == &"quad" or style == &"buggy":
		gears = [0.45, 1.0]
	if is_trailer:
		# No axle steers; nothing drives.
		_front_z = -INF
		rear_steer = 0.0

static func _vec(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))

func has_bed() -> bool:
	return bed_kind != &"none" and cargo_capacity_m3 > 0.0

## Trucks can be driven with a manual gearbox; quads, buggies, the loader and
## trailers are always automatic.
func manual_gearbox() -> bool:
	return Settings.flag(&"manual_gearbox") and style == &"truck" and loader == null and not is_trailer

## Up or down a gear (manual). Returns what the gauge should say.
func shift_gear(step: int) -> String:
	var box := gear_ratios()
	gear = clampi(gear + step, 0, box.size() - 1)
	return "gear %d of %d" % [gear + 1, box.size()]

## Engine speed for the rev counter (and the engine note): idle at a stand,
## the red line at the top speed of the gear it is in.
const IDLE_RPM := 800.0
const REDLINE_RPM := 6000.0

func engine_rpm() -> float:
	var box := gear_ratios()
	if box.is_empty():
		return IDLE_RPM
	var ratio: float = box[clampi(gear, 0, box.size() - 1)]
	var gear_top := maxf(0.5, max_speed * speed_scale() * ratio)
	var v := absf(linear_velocity.dot(-global_transform.basis.z))
	var rpm := IDLE_RPM + (REDLINE_RPM - IDLE_RPM) * v / gear_top
	# Revving against the clutch at a stand.
	rpm = maxf(rpm, IDLE_RPM + absf(input_throttle) * 1200.0)
	return minf(rpm, REDLINE_RPM * 1.12)

func gear_label() -> String:
	return "%s%d" % ["M" if manual_gearbox() else "A", gear + 1]

## Automatic: the lowest gear that still reaches the speed it is doing, with a
## margin so it does not hunt between two. Up a hill it drops a gear when it
## slows down, which is when it needs the pull.
func _auto_gear(speed: float, top: float) -> void:
	var v := absf(speed)
	var box := gear_ratios()
	gear = clampi(gear, 0, box.size() - 1)
	if gear < box.size() - 1 and v > box[gear] * top * 0.9:
		gear += 1
	elif gear > 0 and v < box[gear - 1] * top * 0.7:
		gear -= 1

## Engine and gearing are the vehicle's own; the transmission upgrade (bought
## once for every vehicle) adds overdrive gears.
func engine_scale() -> float:
	return ENGINE_MULT

func speed_scale() -> float:
	return TOP_SPEED_MULT

## The gears in the box now: the vehicle's own, then any overdrives bought.
func gear_ratios() -> Array[float]:
	var out: Array[float] = gears.duplicate()
	if is_trailer or loader != null:
		return out
	var extra := clampi(int(part_stat(&"transmission", "overdrive", 0.0)), 0, OVERDRIVE.size())
	for k in extra:
		out.append(OVERDRIVE[k])
	return out

## The fastest the box will take it on the flat.
func top_ratio() -> float:
	var g := gear_ratios()
	return g[g.size() - 1] if not g.is_empty() else 1.0

func grip_scale() -> float:
	return GRIP_MULT * part_stat(&"tyres", "grip", 1.0)

## The parts fitted to this vehicle (from its pad): track -> level.
var part_levels: Dictionary = {}

func part_stat(track: StringName, key: String, fallback: float) -> float:
	var lvl := int(part_levels.get(track, 1))
	return float(GameData.upgrade_level(track, lvl).get(key, fallback))

## New parts on (or switched off) while it is out.
func set_parts(levels: Dictionary) -> void:
	part_levels = levels.duplicate()
	_refresh_grip()

## Tyres bought since the wheels went on: new rubber on every wheel.
func _refresh_grip() -> void:
	for i in wheel_bodies.size():
		var old := wheel_bodies[i].physics_material_override as PhysicsMaterial
		if old == null:
			continue
		var slip := 1.0
		if _skidding:
			# The brake locks them and they let go: the back most of all,
			# so it steps out and slides rather than stopping dead.
			slip = HANDBRAKE_FRONT if _is_front(i) else HANDBRAKE_REAR
		# A fresh material each time: the physics reads it when it is set,
		# not when one already set is changed.
		var pm := old.duplicate() as PhysicsMaterial
		pm.friction = tyre_grip * grip_scale() * slip
		wheel_bodies[i].physics_material_override = pm

## Braking hard at speed, the tyres give: this much of their grip is left.
static var HANDBRAKE_REAR: float = Balance.num("vehicles.handbrake_rear_grip", 0.12)
static var HANDBRAKE_FRONT: float = Balance.num("vehicles.handbrake_front_grip", 0.22)
var _skidding: bool = false

## Recover, unless it was done less than a second ago or the truck is down on
## its outriggers. Returns "" or why not.
func try_recover() -> String:
	if planted or (rig != null and rig.planted()):
		return "not while it is on its outriggers - bring them up first [O]"
	# Counted in physics steps, so it is game time: a paused game does not
	# run the clock down.
	var now := Engine.get_physics_frames()
	if float(now - _last_recover_frame) < RECOVER_COOLDOWN * float(Engine.physics_ticks_per_second):
		return "recovering - wait a moment"
	_last_recover_frame = now
	recover()
	return ""

func _ready() -> void:
	add_to_group(&"vehicles")
	_apply_spec()
	if not is_trailer:
		_engine_sound = Sfx.loop(StringName("engine_" + String(engine_voice())))
		add_child(_engine_sound)
	collision_layer = Layers.VEHICLE
	collision_mask = Layers.WORLD | Layers.LOOSE | Layers.MACHINE | Layers.TREE | Layers.PLAYER | Layers.VEHICLE
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
	if is_trailer:
		# The drawbar out to the coupling, and a leg under it that holds the
		# front up when it is not hitched.
		var bar := CollisionShape3D.new()
		var bb := BoxShape3D.new()
		var from_z := -body_size.z * 0.5
		bb.size = Vector3(0.3, 0.2, absf(tongue_offset.z - from_z))
		bar.shape = bb
		bar.position = Vector3(0, tongue_offset.y, (tongue_offset.z + from_z) * 0.5)
		add_child(bar)
		var ride := wheel_radius - _lowest_wheel_y() + SAG
		var leg_height := ride + tongue_offset.y
		_stand = CollisionShape3D.new()
		var sb := BoxShape3D.new()
		sb.size = Vector3(0.3, leg_height, 0.3)
		_stand.shape = sb
		_stand.position = Vector3(0, tongue_offset.y - leg_height * 0.5, tongue_offset.z + 0.4)
		add_child(_stand)
	# A cab is solid: loads fetch up against it and it keeps logs out of it.
	var cab: Dictionary = spec.get("cab", {})
	if not cab.is_empty():
		var cab_size := _vec(cab.size)
		_collider(cab_size, Vector3(0, body_size.y * 0.5 + cab_size.y * 0.5, float(cab.z)))
		# A ladder up the left side to the cab roof, from the ground.
		var bottom := -body_size.y * 0.5 - suspension_rest * 0.5 - wheel_radius
		var top := body_size.y * 0.5 + cab_size.y + 0.7
		var ladder := Ladder.new()
		ladder.name = "Ladder"
		ladder.size = Vector3(0.9, top - bottom, 0.7)
		ladder.position = Vector3(-body_size.x * 0.5 - 0.45, (top + bottom) * 0.5, float(cab.z) + cab_size.z * 0.5 - 0.35)
		add_child(ladder)

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
		&"deck":
			_build_deck()
		&"gate":
			_build_gate_bed()

	if has_bed():
		_cargo_area = Area3D.new()
		_cargo_area.collision_layer = Layers.TRIGGER
		_cargo_area.collision_mask = Layers.LOOSE
		var acs := CollisionShape3D.new()
		var ab := BoxShape3D.new()
		# Up past the walls by a heap's height: a load piled above the sides
		# is still aboard, and is fixed with the rest when someone drives.
		var tall := maxf(wall_height, 0.3) + HEAP_HEIGHT
		# A little wider than the bed, for pieces heaped over the tops of the
		# side walls.
		ab.size = Vector3(bed_half_width * 2.0 + 0.4, tall, bed_length)
		acs.shape = ab
		acs.position = Vector3(0, bed_floor + tall * 0.5, bed_mid_z)
		_cargo_shape = acs
		_cargo_area.add_child(acs)
		add_child(_cargo_area)

	VehicleModel.dress(self)
	_pose_ramps()

	# Spec: most vehicles carry a winch, many carry a crane.
	var gear: Variant = spec.get("rig", null)
	if gear is Dictionary:
		rig = VehicleRig.new()
		rig.name = "Rig"
		rig.winch_power_kg = float(gear.get("winch", 4000)) * Balance.num("vehicles.winch_multiplier", 1.0)
		rig.crane_power_kg = float(gear.get("crane", 0)) * Balance.num("crane.power_multiplier", 1.0)
		rig.reach = float(gear.get("reach", 14))
		rig.head_offset = _vec(gear.get("head", [0, 1.1, -1.2]))
		rig.setup(self)
		rig.configure(gear)
		add_child(rig)

	var arms: Variant = spec.get("loader", null)
	if arms is Dictionary:
		loader = LoaderArm.new()
		loader.name = "Loader"
		loader.setup(self, arms)
		add_child(loader)

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

## A low, flat deck for carrying a machine: a kerb down each side to keep
## its wheels on, a headboard, and a pair of ramps at the back that fold down
## to the ground to drive up and stand on end as a gate for the road.
const RAMP_LENGTH := 2.8
const RAMP_WIDTH := 0.9

## How far up the ramps are: 0 down on the ground, 1 stood on end. They swing
## smoothly toward `ramp_target`; [X] sends them the other way, and pressed
## while they are moving it stops them where they are - so they can be set at
## any angle in between, to meet a bank or a loading dock.
var ramp_pose: float = 1.0
var ramp_target: float = 1.0
const RAMP_SPEED := 0.45     ## of the swing, per second

func _build_deck() -> void:
	for side in [-1.0, 1.0]:
		_collider(Vector3(0.14, wall_height, bed_length),
			Vector3(side * (bed_half_width + 0.07), bed_floor + wall_height * 0.5, bed_mid_z))
	_collider(Vector3(bed_half_width * 2.0 + 0.28, headboard_height, 0.3),
		Vector3(0, bed_floor + headboard_height * 0.5, bed_front - 0.15))
	for x in ramp_xs():
		_ramps_flat.append(_collider(Vector3(RAMP_WIDTH, 0.14, RAMP_LENGTH), Vector3.ZERO))
	_pose_ramps()

## A walled bed whose tailgate is a ramp: sides and a headboard, and a
## full-width gate across the back that stands up to close the bed and comes
## down to the ground to wheel or drive things aboard.
func _build_gate_bed() -> void:
	var t := 0.12
	for side in [-1.0, 1.0]:
		_collider(Vector3(t, wall_height, bed_length + 0.2),
			Vector3(side * (bed_half_width + t * 0.5), bed_floor + wall_height * 0.5, bed_mid_z))
	_collider(Vector3(bed_half_width * 2.0 + t * 2.0, headboard_height, 0.2),
		Vector3(0, bed_floor + headboard_height * 0.5, bed_front - 0.1))
	_ramps_flat.append(_collider(Vector3(ramp_width(), 0.1, ramp_length()), Vector3.ZERO))
	_pose_ramps()

## Whether this bed has ramps (or a ramp gate) to work with [X].
func has_ramps() -> bool:
	return bed_kind == &"deck" or bed_kind == &"gate"

## A ramp's length and width: the low-loader's pair, or a gate as tall as
## the sides and as wide as the bed.
func ramp_length() -> float:
	return maxf(0.6, wall_height + 0.1) if bed_kind == &"gate" else RAMP_LENGTH

func ramp_width() -> float:
	return bed_half_width * 2.0 + 0.2 if bed_kind == &"gate" else RAMP_WIDTH

## Across the deck, where each ramp sits: under the wheels of the widest
## machine it carries. A gate is one, across the whole back.
func ramp_xs() -> Array[float]:
	if bed_kind == &"gate":
		return [0.0]
	var x := bed_half_width - RAMP_WIDTH * 0.5
	return [-x, x]

## The ramp's angle down from level when its foot is on the ground.
func _ramp_down_angle() -> float:
	var ground := -(wheel_radius - _lowest_wheel_y() + SAG)
	return asin(clampf((bed_floor - ground) / ramp_length(), 0.0, 1.0))

## A ramp at `pose` (0 down, 1 up): hinged on the deck's back edge; the
## transform is the middle of the ramp's plate.
func ramp_transform(x: float, pose: float) -> Transform3D:
	var angle := lerpf(_ramp_down_angle(), -PI * 0.5, pose)
	var basis := Basis(Vector3.RIGHT, angle)
	var hinge := Vector3(x, bed_floor - 0.07, bed_back)
	return Transform3D(basis, hinge + basis * Vector3(0, 0, ramp_length() * 0.5))

func ramp_down_transform(x: float) -> Transform3D:
	return ramp_transform(x, 0.0)

## [X]: down if up, up if down; stops them if they are on the move. Says what
## it did.
func toggle_ramps() -> String:
	if not has_ramps():
		return ""
	var what := "gate" if bed_kind == &"gate" else "ramps"
	if not is_equal_approx(ramp_pose, ramp_target):
		ramp_target = ramp_pose
		return "%s held at %d%%" % [what, int(round((1.0 - ramp_pose) * 100.0))]
	ramp_target = 0.0 if ramp_pose > 0.5 else 1.0
	if bed_kind == &"gate":
		return "gate coming down" if ramp_target < 0.5 else "gate going up"
	return "ramps coming down - drive aboard" if ramp_target < 0.5 else "ramps going up"

## Straight to down or up (loading a save, a co-op picture, tests).
func set_ramps(down: bool) -> void:
	set_ramp_pose(0.0 if down else 1.0)

func set_ramp_pose(pose: float) -> void:
	if not has_ramps():
		return
	ramp_pose = clampf(pose, 0.0, 1.0)
	ramp_target = ramp_pose
	_pose_ramps()

func _update_ramps(delta: float) -> void:
	if not has_ramps() or is_equal_approx(ramp_pose, ramp_target):
		return
	ramp_pose = move_toward(ramp_pose, ramp_target, RAMP_SPEED * delta)
	_pose_ramps()

func _pose_ramps() -> void:
	ramps_down = ramp_pose < 0.5
	var xs := ramp_xs()
	for i in _ramps_flat.size():
		_ramps_flat[i].transform = ramp_transform(xs[i], ramp_pose)
	for i in ramp_meshes.size():
		var t := ramp_transform(xs[i], ramp_pose)
		ramp_meshes[i].transform = Transform3D(t.basis, t.origin - t.basis * Vector3(0, 0, ramp_length() * 0.5))

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
## close to the seat on an open vehicle. A trailer has nowhere to sit.
func is_seat_point(world_point: Vector3) -> bool:
	if is_trailer:
		return false
	var local := global_transform.affine_inverse() * world_point
	var seat := _vec(spec.get("seat", [0, 1.2, -1.9]))
	var cab: Dictionary = spec.get("cab", {})
	if not cab.is_empty():
		var size := _vec(cab.size)
		return absf(local.z - float(cab.z)) <= size.z * 0.5 + 0.2 and local.y > body_size.y * 0.5 - 0.3
	return Vector2(local.x - seat.x, local.z - seat.z).length() < 1.1

func seat_transform() -> Transform3D:
	return _seat.global_transform

## Riding along: other players in the passenger seat(s), in co-op. A bike or
## quad carries one on the back; anything with a cab one beside the driver.
var passengers: Array[Node3D] = []

func passenger_seats() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if is_trailer:
		return out
	var s := _vec(spec.get("seat", [0, 1.2, -1.9]))
	for extra in spec.get("passenger_seats", []):
		out.append(_vec(extra))
	if not out.is_empty():
		return out
	if bike or style == &"quad":
		out.append(s + Vector3(0, 0.08, 0.5))
	else:
		out.append(s + Vector3(0.65, 0, 0))
	return out

func free_passenger_seat() -> bool:
	passengers = passengers.filter(func(n): return is_instance_valid(n))
	return passengers.size() < passenger_seats().size()

## Where `who` sits: the driver's seat, or their passenger seat.
func seat_of(who: Node3D) -> Transform3D:
	var i := passengers.find(who)
	if i < 0:
		return seat_transform()
	var seats := passenger_seats()
	return global_transform * Transform3D(Basis(), seats[mini(i, seats.size() - 1)])

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

## There is no carry limit: a bed takes whatever fits in it.
func cargo_full() -> bool:
	return false

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
	var manned := lead().driver != null
	var may_fix := manned and not _crane_busy() and _tipping_items().is_empty() \
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

## A load does not weigh the truck down: its weight on the bed is met by an
## equal push up under each piece, so the springs never feel it. The pieces
## still sit on the bed, slide and shift as they would.
func _carry_load() -> void:
	if freeze or _load.is_empty():
		return
	var g := get_gravity()
	for item in _load:
		if _fixed.has(item) or not is_instance_valid(item) or item.state != LooseItem.State.FREE:
			continue
		apply_force(-g * item.mass, item.global_position - global_position)

## A crane at work - this truck's, or the one towing it - wants the load loose,
## so it can be picked out of the bed.
func _crane_busy() -> bool:
	if rig != null and (rig.operating or rig.folding):
		return true
	return towed_by != null and is_instance_valid(towed_by) and towed_by.rig != null \
		and (towed_by.rig.operating or towed_by.rig.folding)

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
	# Its shape is the truck's, but not its weight: a load does not press the
	# truck down on its springs.
	_fixed[item] = {"shapes": shapes, "mass": 0.0}
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
	# A trailer behind tips with it.
	if towing != null and is_instance_valid(towing):
		towing.unload(_behind)
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

## [X]: a walled bed's tailgate (or a trailer's ramp gate) swings down, or
## back up - and that is all: what is in the bed stays where it is until it
## is taken out or slides out on its own. The dump tub still tips its load
## out, and a log bed with no tailgate walks its logs off the back. Says what
## it did; a trailer behind follows suit.
func work_tailgate() -> String:
	var said := ""
	match bed_kind:
		&"sides", &"rack":
			tailgate_open = not tailgate_open
			_set_tailgate(tailgate_open)
			said = "tailgate down" if tailgate_open else "tailgate up"
		&"gate", &"deck":
			said = toggle_ramps()
		&"tub", &"stakes":
			var n := unload()
			var how := "tub up" if bed_kind == &"tub" else "logs off the back"
			return "%s: tipping out %d piece(s)" % [how, n] if n > 0 else "the bed is empty"
		_:
			return "the %s has nothing to unload" % display_name.to_lower()
	if towing != null and is_instance_valid(towing) and towing.bed_kind != &"tub" and towing.bed_kind != &"stakes":
		towing.set_tailgate_open(tailgate_open if (bed_kind == &"sides" or bed_kind == &"rack") else ramp_target < 0.5)
	return said

## Held open (or shut) by [X], for a walled bed.
var tailgate_open: bool = false

## Straight to open or shut: a trailer following the truck in front.
func set_tailgate_open(open: bool) -> void:
	match bed_kind:
		&"sides", &"rack":
			tailgate_open = open
			_set_tailgate(open)
		&"gate":
			ramp_target = 0.0 if open else 1.0

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
	if bed_kind == &"gate":
		# The gate is the tailgate: down for tipping out, back up after.
		ramp_target = 0.0 if open else 1.0
		return
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
	_set_tailgate(tailgate_open)

func cargo_summary() -> String:
	if _load.is_empty():
		return "empty"
	var counts: Dictionary = {}
	for item in _load:
		counts[item.item_id] = int(counts.get(item.item_id, 0)) + 1
	var parts: Array[String] = []
	for id in counts:
		parts.append("%s x%d" % [GameData.item_name(id), int(counts[id])])
	return "%.2f m3: %s" % [cargo_volume(), ", ".join(parts)]

# --- Driving ---------------------------------------------------------------

# --- Co-op -------------------------------------------------------------------------

## On a guest's machine: this copy is being driven there, so all it does is
## drive. What is in the bed, on the hook or on the winch is the host's.
var net_mirror: bool = false
## On the host: a guest is driving this on their machine, and it goes where
## they say (its wheels too) rather than where its own motors would take it.
var net_follow: bool = false
var _net_goal: Transform3D
var _net_wheels: Array = []
var _net_heard: float = 0.0
var _net_vel: Vector3 = Vector3.ZERO

## Where the guest driving it has it now.
func net_follow_to(goal: Transform3D, wheels: Array) -> void:
	if net_follow:
		var gap := maxf(_net_heard, 1.0 / 60.0)
		_net_vel = (goal.origin - _net_goal.origin) / gap
	else:
		_net_vel = Vector3.ZERO
		release_hold()
	net_follow = true
	_net_goal = goal
	_net_wheels = wheels
	_net_heard = 0.0

## Moved by the host (recovered): held there until the guest's next word.
func net_hold_at(t: Transform3D) -> void:
	_net_goal = t
	_net_wheels = []
	_net_vel = Vector3.ZERO

func end_net_follow() -> void:
	if not net_follow:
		return
	net_follow = false
	freeze = planted
	for body in wheel_bodies:
		body.freeze = false
		body.linear_velocity = _net_vel
	if not planted:
		linear_velocity = _net_vel
		angular_velocity = Vector3.ZERO

func _net_follow_step(delta: float) -> void:
	_net_heard += delta
	if driver == null or _net_heard > 1.0:
		end_net_follow()
		return
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	global_transform = _net_goal
	for i in wheel_bodies.size():
		var body := wheel_bodies[i]
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = true
		if i < _net_wheels.size():
			body.global_transform = _net_wheels[i]

## The engine note: silent with nobody at the wheel, rising with speed and
## throttle.
var _engine_sound: AudioStreamPlayer3D
func _engine_note() -> void:
	if _engine_sound == null:
		return
	if _smoke != null:
		_smoke.emitting = driver != null or autopilot
		# A black cloud under load, a thin wisp at idle.
		var pull := absf(input_throttle)
		_smoke.initial_velocity_max = 1.6 + 2.5 * pull
		_smoke.scale_amount_max = 0.8 + 1.4 * pull
		_smoke.color = Color(1, 1, 1, 0.35 + 0.65 * pull)
	if driver == null and not autopilot:
		_engine_sound.volume_db = -80.0
		return
	# Pitch follows the revs: it climbs through a gear and drops at a change.
	var revs := (engine_rpm() - IDLE_RPM) / (REDLINE_RPM - IDLE_RPM)
	_engine_sound.volume_db = Sfx.sfx_db() - 10.0 + absf(input_throttle) * 2.5
	_engine_sound.pitch_scale = clampf(0.8 + revs * 0.65, 0.75, 1.6)

## Which engine this vehicle sounds like.
func engine_voice() -> StringName:
	var v := String(spec.get("voice", ""))
	if v != "":
		return StringName(v)
	match style:
		&"bike":
			return &"two_stroke"
		&"quad":
			return &"thumper"
		&"buggy":
			return &"flat4"
	return &"diesel"

# --- Lifted by a crane ------------------------------------------------------------

## Hanging from another truck's crane: held still, wheels and all, and put
## wherever the crane has it; let go, it drops and rolls as any vehicle.
var crane_carried: bool = false

## What a crane has to lift: the vehicle, its wheels and whatever is aboard.
func lift_mass() -> float:
	var kg := mass
	for w in wheel_bodies:
		kg += w.mass
	for item in _load:
		if is_instance_valid(item):
			kg += item.mass
	return kg

func set_crane_carried(on: bool) -> void:
	crane_carried = on
	release_hold()
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = on or planted
	for w in wheel_bodies:
		w.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		w.freeze = on
		w.sleeping = false
	sleeping = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func carried_to(t: Transform3D) -> void:
	global_transform = t
	_snap_wheels()

## Two wheels: a bike is held up the way a rider holds it up, and leans into
## a turn - more the faster it goes. Nothing here stops it pitching over a
## lip or taking off; it just does not fall over sideways.
var bike: bool = false
static var BIKE_LEAN: float = Balance.num("vehicles.bike_lean", 0.38)

func _balance() -> void:
	if not bike or freeze:
		return
	var forward := -global_transform.basis.z
	var up := global_transform.basis.y
	var right := global_transform.basis.x
	var speed := linear_velocity.dot(forward)
	var lean := input_steer * BIKE_LEAN * clampf(absf(speed) / 10.0, 0.0, 1.0)
	var want := (Vector3.UP - right * lean).normalized()
	# How far it is off upright about its own length: its roll is set to
	# close that gap steadily (a torque strong enough to do it overshoots).
	var off := forward.dot(up.cross(want))
	var roll := forward.dot(angular_velocity)
	angular_velocity += forward * (clampf(off, -1.0, 1.0) * 5.0 - roll)

func _physics_process(delta: float) -> void:
	_engine_note()
	if crane_carried:
		return
	if net_mirror:
		if driver != null:
			_read_input()
		if not freeze:
			_drive_wheels()
			_balance()
			_clamp_motion()
		return
	if net_follow:
		_net_follow_step(delta)
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.1
		_poll_bed()
		_poll_riders()
	_update_unload(delta)
	_update_ramps(delta)
	_update_tub(delta)
	_update_fixed(delta)
	_carry_load()

	if towed_by != null and not is_instance_valid(towed_by):
		towed_by = null
	if towing != null and not is_instance_valid(towing):
		towing = null
	if net_follow:
		return
	if carried_on != null and (not is_instance_valid(carried_on) or driver != null):
		unglue()
	if driver != null:
		_read_input()
	elif towed_by != null:
		# Towed: it brakes when the truck does, and otherwise rolls.
		input_throttle = 0.0
		input_steer = 0.0
		input_brake = towed_by.input_brake or towed_by.parked()
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
	_update_hold(delta)
	if held:
		return
	_drive_wheels()
	_balance()
	_clamp_motion()

# --- Carrying other vehicles ---------------------------------------------------------

## A vehicle standing on this one's bed or deck (the loader on the low-loader,
## a dirt bike in a pickup) is locked to it while this one is being driven, so
## it rides as part of it instead of shuffling about on its tyres - and let go
## the moment someone gets into it or this one is left parked.
var carried_on: Hauler = null
var _carry_joint: Generic6DOFJoint3D

func _manned() -> bool:
	var front := lead()
	return front.driver != null or front.autopilot

func _poll_riders() -> void:
	if bed_kind == &"none" or bed_length <= 0.0:
		return
	var manned := _manned()
	for node in get_tree().get_nodes_in_group(&"vehicles"):
		var v := node as Hauler
		if v == null or v == self or v.is_trailer and v.towed_by != null:
			continue
		if v.carried_on == self:
			if not manned or v.driver != null or v.autopilot or not _rides_on(v, 0.6):
				v.unglue()
			continue
		if manned and v.carried_on == null and v.driver == null and not v.autopilot \
				and v.towing == null and v.towed_by == null and _rides_on(v, 0.0):
			var rel := v.linear_velocity - linear_velocity
			if rel.length() < 1.5:
				v.glue_to(self)

## Is `v` standing on this bed or deck (with `slack` metres to spare)?
func _rides_on(v: Hauler, slack: float) -> bool:
	var local := global_transform.affine_inverse() * v.global_position
	if absf(local.x) > bed_half_width + 0.4 + slack:
		return false
	if local.z < bed_front - 0.5 - slack or local.z > bed_back + 0.5 + slack:
		return false
	var lowest := v.wheel_radius - v._lowest_wheel_y()
	var above := local.y - bed_floor
	if above < -0.3 - slack or above > lowest + 1.5 + slack:
		return false
	return v.global_transform.basis.y.dot(global_transform.basis.y) > 0.8

func glue_to(carrier: Hauler) -> void:
	release_hold()
	carried_on = carrier
	_carry_joint = Generic6DOFJoint3D.new()
	_carry_joint.name = "Carried_%s" % name
	carrier.add_child(_carry_joint)
	_carry_joint.global_transform = global_transform
	_carry_joint.node_a = _carry_joint.get_path_to(carrier)
	_carry_joint.node_b = _carry_joint.get_path_to(self)

func unglue() -> void:
	if _carry_joint != null and is_instance_valid(_carry_joint):
		_carry_joint.queue_free()
	_carry_joint = null
	carried_on = null
	sleeping = false

# --- Parked and held ---------------------------------------------------------------

## Left with nobody at the controls, a vehicle that has come (nearly) to rest
## on its wheels is held exactly where it is - chassis and wheels frozen - so
## getting out, a load settling or a bump does not send it creeping, rocking
## or skating off. It lets go the moment someone drives it, tows it, or plants
## it for the crane.
var held: bool = false
var _hold_time: float = 0.0
static var HOLD_SPEED: float = Balance.num("vehicles.hold_speed", 1.2)          ## m/s; slower than this and it is held
static var HOLD_AFTER: float = Balance.num("vehicles.hold_after", 0.3)          ## seconds of being slow before it is

func _may_hold() -> bool:
	return parked() and not planted and towed_by == null and not wheel_bodies.is_empty() and carried_on == null

func _update_hold(delta: float) -> void:
	if not _may_hold():
		_hold_time = 0.0
		if held:
			release_hold()
		return
	if held:
		return
	var slow := linear_velocity.length() < HOLD_SPEED and angular_velocity.length() < 0.8
	var grounded := _grounded * 2 >= wheel_bodies.size()
	_hold_time = _hold_time + delta if slow and grounded else 0.0
	if _hold_time >= HOLD_AFTER:
		_hold()

func _hold() -> void:
	held = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	for body in wheel_bodies:
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = true

func release_hold() -> void:
	if not held:
		return
	held = false
	_hold_time = 0.0
	if not planted:
		freeze = false
	for body in wheel_bodies:
		body.freeze = false
	sleeping = false

func _read_input() -> void:
	if planted:
		# The controls are working the crane.
		input_throttle = 0.0
		input_steer = 0.0
		input_brake = true
		return
	# The driver's keys: this machine's, or a co-op guest's.
	var inp: PlayerInput = driver.get("input") as PlayerInput if driver.get("input") != null else PlayerInput.new()
	input_throttle = inp.axis("move_back", "move_forward")
	input_steer = inp.axis("move_right", "move_left")
	# In a loader Space works the bucket lock, not the brake.
	input_brake = loader == null and inp.pressed("jump")

## Stood on its outriggers for the crane: it does not roll, rock or tip, and
## the crane's load is carried into the ground.
var planted: bool = false

func set_planted(on: bool) -> void:
	release_hold()
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

## On a bridge deck.
func on_bridge() -> bool:
	if not is_inside_tree():
		return false
	for b in get_tree().get_nodes_in_group(&"bridges"):
		if (b as Bridge).on_deck(global_position):
			return true
	return false

## The extra top speed the surface gives: roads some, bridges more.
func speed_bonus() -> float:
	if on_bridge():
		return Terrain.BRIDGE_SPEED_BONUS
	return Terrain.ROAD_SPEED_BONUS if on_road() else 0.0

## True when nobody is at the wheel. A parked truck has its brakes on: it stays
## where it was left rather than being shoved about by whatever walks into it.
func parked() -> bool:
	return driver == null and not autopilot and towed_by == null

func _lowest_wheel_y() -> float:
	var low := 0.0
	for o in wheel_offsets:
		low = minf(low, (o as Vector3).y)
	return low

# --- Towing ---------------------------------------------------------------------

## Every body that is part of this vehicle, what it tows (and what they tow),
## and the loads aboard all of them.
func train_rids() -> Array[RID]:
	var out: Array[RID] = []
	var v := lead()
	var guard := 0
	while v != null and is_instance_valid(v) and guard < 8:
		out.append(v.get_rid())
		for w in v.wheel_bodies:
			out.append((w as PhysicsBody3D).get_rid())
		for item in v._load:
			if is_instance_valid(item):
				out.append(item.get_rid())
		if v.loader != null:
			if v.loader.bucket != null:
				out.append(v.loader.bucket.get_rid())
			for item in v.loader.locked_items():
				if is_instance_valid(item):
					out.append(item.get_rid())
		v = v.towing
		guard += 1
	return out

## The front of the train this is part of: the truck pulling it all.
func lead() -> Hauler:
	var v := self
	var guard := 0
	while v.towed_by != null and is_instance_valid(v.towed_by) and guard < 8:
		v = v.towed_by
		guard += 1
	return v

func has_hitch() -> bool:
	return hitch_offset != Vector3.ZERO

func hitch_point() -> Vector3:
	return global_transform * hitch_offset

func tongue_point() -> Vector3:
	return global_transform * tongue_offset

## Hooks `trailer` on behind. Its coupling has to be within reach of the
## hitch; it is set on the ball, keeping the way it faces. Returns "" or why
## not.
func hitch(trailer: Hauler) -> String:
	if not has_hitch():
		return "the %s has no hitch" % display_name.to_lower()
	if trailer == null or not trailer.is_trailer:
		return "that is not a trailer"
	if trailer == self or trailer == towed_by:
		return "that is the one pulling it"
	if towing != null:
		return "already towing the %s" % towing.display_name.to_lower()
	if trailer.towed_by != null:
		return "that trailer is hitched to something else"
	var too_heavy := can_tow(trailer)
	if too_heavy != "":
		return too_heavy
	var gap := trailer.tongue_point().distance_to(hitch_point())
	if gap > HITCH_REACH:
		return "back up to it: the hitch is %.1f m from the coupling" % gap
	trailer.release_load()
	# Level, facing the way it faced, with its coupling on the ball.
	var yaw := trailer.global_rotation.y
	var basis := Basis.from_euler(Vector3(0, yaw, 0))
	var at := hitch_point() - basis * trailer.tongue_offset + Vector3(0, 0.02, 0)
	trailer.move_to(Transform3D(basis, at))
	trailer.sleeping = false
	_hitch_joint = PinJoint3D.new()
	_hitch_joint.name = "Hitch"
	add_child(_hitch_joint)
	_hitch_joint.global_position = hitch_point()
	_hitch_joint.node_a = _hitch_joint.get_path_to(self)
	_hitch_joint.node_b = _hitch_joint.get_path_to(trailer)
	_ignore_towed(trailer, true)
	towing = trailer
	release_hold()
	trailer.release_hold()
	trailer.towed_by = self
	trailer.set_stand(false)
	return ""

## Whether the truck at the head of this train can pull `trailer`: "" if it
## can, or why not. A trailer counts by its own weight, empty; one hitched on
## behind another trailer is still the truck's to pull, so it counts the same.
func can_tow(trailer: Hauler) -> String:
	var puller := lead()
	if puller.tow_limit <= 0.0 or trailer == null:
		return ""
	if float(trailer.spec.get("mass", trailer.mass)) <= puller.tow_limit + 0.5:
		return ""
	var most := Hauler.heaviest_trailer_within(puller.tow_limit)
	return "the %s is too heavy for the %s - it pulls the %s or anything lighter" % [
		trailer.display_name.to_lower(), puller.display_name.to_lower(), most.to_lower() if most != "" else "lightest trailers"]

## The name of the heaviest trailer weighing no more than `limit` kg.
static func heaviest_trailer_within(limit: float) -> String:
	var best := ""
	var best_mass := -1.0
	for id in GameData.vehicles:
		var v: Dictionary = GameData.vehicles[id]
		if not bool(v.get("trailer", false)):
			continue
		var m := float(v.get("mass", 0.0))
		if m <= limit + 0.5 and m > best_mass:
			best_mass = m
			best = String(v.get("display_name", id))
	return best

## Lets the trailer go, where it stands, down on its leg.
func unhitch() -> Hauler:
	var trailer := towing
	if _hitch_joint != null and is_instance_valid(_hitch_joint):
		_hitch_joint.queue_free()
	_hitch_joint = null
	towing = null
	if trailer != null and is_instance_valid(trailer):
		_ignore_towed(trailer, false)
		trailer.towed_by = null
		trailer.set_stand(true)
	return trailer

## A truck and what it tows do not bump each other, wheels included.
func _ignore_towed(trailer: Hauler, on: bool) -> void:
	var mine: Array = [self]
	mine.append_array(wheel_bodies)
	var theirs: Array = [trailer]
	theirs.append_array(trailer.wheel_bodies)
	for a: PhysicsBody3D in mine:
		for b: PhysicsBody3D in theirs:
			if on:
				a.add_collision_exception_with(b)
			else:
				a.remove_collision_exception_with(b)

## The front leg: down when it stands alone, up when it is hitched.
func set_stand(down: bool) -> void:
	if _stand != null:
		_stand.disabled = not down
	if _stand_mesh != null:
		_stand_mesh.visible = down

# --- Wheels -------------------------------------------------------------------

## Hangs a wheel body under each wheel position: a cylinder of rubber on a
## joint that lets it ride up and down on a spring, spin on its axle under a
## motor, and - at the front - turn to steer. The wheel models go on them.
func _build_wheels() -> void:
	if not wheel_bodies.is_empty() or not is_inside_tree():
		return
	var n := maxi(1, wheel_offsets.size())
	# Springs are sized for what the vehicle is built to carry: a light
	# trailer rated for a loader aboard (`spring_mass`) is sprung for it.
	var sprung := maxf(mass, float(spec.get("spring_mass", mass)))
	var share := sprung * 9.8 / float(n)
	var wheel_mass := maxf(15.0, mass * 0.035)
	# The joint spring is softer than its number says (Jolt), by this much.
	var stiffness := share / SAG * 2.4
	var damping := 2.0 * 0.55 * sqrt(stiffness * sprung / float(n))
	var grip := PhysicsMaterial.new()
	grip.friction = tyre_grip * grip_scale()
	grip.rough = true
	for i in wheel_offsets.size():
		var o: Vector3 = wheel_offsets[i]
		var anchor := Vector3(o.x + signf(o.x) * 0.12, o.y, o.z)
		var body := RigidBody3D.new()
		body.name = "Wheel%d" % i
		body.top_level = true
		body.mass = wheel_mass
		body.collision_layer = Layers.VEHICLE
		body.collision_mask = Layers.WORLD | Layers.LOOSE | Layers.MACHINE | Layers.TREE | Layers.VEHICLE
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
	var steer: float = input_steer * max_steer_angle * STEER_MULT / (1.0 + absf(speed) * STEER_SOFTEN)
	var bonus: float = 1.0 + speed_bonus()
	var throttle: float = 0.0 if (standing or flooded()) else input_throttle
	var n := float(wheel_bodies.size())
	var target := 0.0
	var torque := 0.0
	var full := max_speed * speed_scale() * bonus
	var manual := manual_gearbox()
	if not manual:
		# It shifts for the speed being asked for, not flat-out's.
		_auto_gear(speed, full * clampf(absf(throttle), 0.3, 1.0))
	# Pull goes up as the gear comes down; the gear's own top speed caps it.
	var box := gear_ratios()
	var ratio: float = box[clampi(gear, 0, box.size() - 1)] if not box.is_empty() else 1.0
	var pull: float = pow(1.0 / maxf(0.05, ratio), GEAR_TORQUE_EXP)
	if not manual:
		# The automatic brings half the low gears' extra pull to bear on the
		# flat - enough to feel, not so much a loose load is snatched off the
		# back - and all of it going uphill, where it is needed.
		var uphill := forward.y * signf(throttle if absf(throttle) > 0.05 else 1.0)
		# (Past a few degrees: pulling away squats the tail and lifts the
		# nose a little, which is not a hill.)
		var climb := clampf((uphill - 0.08) / 0.22, 0.0, 1.0)
		# Light runabouts keep the gentle start (a loose load stays aboard).
		var flat := minf(lerpf(1.0, pull, 0.5), 1.3) if mass > 1000.0 else 1.0
		pull = lerpf(flat, pull, climb)
	# An overdrive always pulls less: that is the price of its speed.
	if ratio > 1.0:
		pull = minf(pull, pow(1.0 / ratio, GEAR_TORQUE_EXP))
	var skid := input_brake and not standing and absf(speed) > 2.5
	if skid != _skidding:
		_skidding = skid
		_refresh_grip()
	if standing or input_brake:
		# At speed the brake locks the wheels, and a locked tyre slides.
		torque = _brake_torque() * (8.0 if skid else 1.0)
	elif absf(throttle) > 0.05:
		# Reverse is a low gear of its own.
		var top: float = full * ratio if throttle > 0.0 else max_speed * 0.5
		if throttle < 0.0 and manual:
			pull = pow(1.0 / maxf(0.05, gears[0] if not gears.is_empty() else 1.0), GEAR_TORQUE_EXP)
		target = throttle * top / wheel_radius
		torque = engine_force_max * engine_scale() * pull * bonus * wheel_radius / n
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
		elif rear_steer > 0.0 and absf((wheel_offsets[i] as Vector3).z - _rear_z) < 0.1:
			j.set("angular_limit_y/upper_angle", steer * rear_steer)
			j.set("angular_limit_y/lower_angle", steer * rear_steer)
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
	var ceiling := max_speed * speed_scale() * top_ratio() * 1.25 * (1.0 + Terrain.BRIDGE_SPEED_BONUS)
	if linear_velocity.length() > ceiling:
		linear_velocity = linear_velocity.normalized() * ceiling
	if angular_velocity.length() > 3.5:
		angular_velocity = angular_velocity.normalized() * 3.5

## Upright rescue: a hauler on its roof is unrecoverable for the player.
## Whatever is still in the bed is lifted with it, rather than left where the
## truck was and dropped through the deck.
func recover() -> void:
	if towed_by != null and is_instance_valid(towed_by):
		lead().recover()
		return
	move_to(Transform3D(Basis.from_euler(Vector3(0, global_rotation.y, 0)), global_position + Vector3(0, 1.2, 0)))
	# Whatever it tows is righted too, set back on the hitch behind it.
	var front := self
	var back := towing
	var guard := 0
	while back != null and is_instance_valid(back) and guard < 8:
		var yaw := _flat_yaw(back)
		var basis := Basis.from_euler(Vector3(0, yaw, 0))
		back.move_to(Transform3D(basis, front.hitch_point() - basis * back.tongue_offset + Vector3(0, 0.05, 0)))
		front = back
		back = back.towing
		guard += 1

## Which way a vehicle faces across the ground, even lying on its side.
static func _flat_yaw(v: Hauler) -> float:
	var fwd := -v.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.2:
		fwd = v.global_transform.basis.y
		fwd.y = 0.0
	return atan2(-fwd.x, -fwd.z)

## Puts the truck at `after`, stopped, its wheels under it and its load still
## in the bed.
func move_to(after: Transform3D) -> void:
	release_hold()
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
	if loader != null:
		loader.snap()
	for pair in riders:
		(pair[0] as LooseItem).teleport(after * (pair[1] as Transform3D))

## The load is saved with the truck, relative to the bed, so it comes back
## lying where it was wherever the truck was left.
func to_dict() -> Dictionary:
	var entries: Array = []
	var inverse := global_transform.affine_inverse()
	var aboard: Array[LooseItem] = _load.duplicate()
	if loader != null:
		aboard.append_array(loader.locked_items())
	for item in aboard:
		var t := inverse * item.global_transform
		entries.append({"id": String(item.item_id), "dims": Solid.to_dict(item.dims),
			"local": [t.origin.x, t.origin.y, t.origin.z,
				t.basis.x.x, t.basis.x.y, t.basis.x.z,
				t.basis.y.x, t.basis.y.y, t.basis.y.z,
				t.basis.z.x, t.basis.z.y, t.basis.z.z]})
	return {"vehicle": String(vehicle_id),
		"position": [global_position.x, global_position.y, global_position.z],
		"yaw": global_rotation.y, "cargo": entries,
		"loader": [loader.lift, loader.tilt, loader.locked, String(loader.attachment)] if loader != null else []}

func from_dict(d: Dictionary) -> void:
	var p: Array = d.get("position", [0, 2, 0])
	var at := Vector3(p[0], p[1], p[2])
	# Never back under the land: saved mid-bounce, or sunk, it comes back
	# stood on top.
	if terrain != null:
		at.y = maxf(at.y, terrain.height_at(at.x, at.z) + spawn_height())
	var xform := Transform3D(Basis.from_euler(Vector3(0, float(d.get("yaw", 0.0)), 0)), at)
	release_hold()
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xform)
	global_transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_snap_wheels()
	var arms: Array = d.get("loader", [])
	if loader != null and arms.size() >= 2:
		loader.lift = clampf(float(arms[0]), loader.lift_min, loader.lift_max)
		loader.tilt = clampf(float(arms[1]), LoaderArm.TILT_MIN, LoaderArm.TILT_MAX)
		loader.snap()
	# A truck spawned for the load builds its wheels a frame late: they go
	# under it once they exist.
	_snap_wheels.call_deferred()
	release_load()
	if loader != null:
		# What was clamped in the bucket is in the save too.
		var clamped := loader.locked_items()
		loader.set_locked(false)
		if manager != null:
			for item in clamped:
				manager.despawn(item)
		if arms.size() >= 4:
			loader.set_attachment(StringName(arms[3]))
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
	if loader != null and arms.size() >= 3 and bool(arms[2]):
		loader.set_locked(false)
		loader.relock_after_load()
