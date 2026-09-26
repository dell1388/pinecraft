class_name VehicleRig
extends Node3D

## The gear bolted to a vehicle: a winch and, on some, a loader crane.
##
## The winch line is a rope: slack until it is drawn tight, then it pulls both
## ends together as hard as it has to - up to what the winch is rated for.
## Past that the drum stalls when you reel in, and slips when something drags
## on it. It runs from the fairlead on the front of the truck to whatever it
## is hooked to: a log, a tree, a rock face, another truck. Use it from the
## seat or standing near the truck.
##
## The crane is a slewing, luffing, telescoping boom with a grapple on a line,
## worked the easy way: the player moves the LOG, not the crane. Input slides
## a target about in the truck's own frame - along it, across it, up and down,
## and turns it - and the crane works out the rest: the turntable slews to
## face it, the boom raises and runs out until its tip is right over it, and
## the line lets down to it. The line hangs dead straight - no swing at all,
## which is not how a real one behaves but is far easier to work. Each joint
## moves at a hydraulic's pace, so the crane lags the target a little and the
## ghost shows where it is going. The target stays inside what the crane can
## reach, sliding along the edge rather than stopping dead; the log itself is
## swept so it never goes through the bed, the stakes or the truck. While it
## works the truck stands on its outriggers.

signal winch_attached(anchor: Vector3)
signal winch_released()
signal crane_grabbed(item: LooseItem)
signal crane_released(item: LooseItem)

## What the winch can pull, in kilograms. Past this it stalls.
@export var winch_power_kg: float = 4000.0
## What the crane can lift, in kilograms.
@export var crane_power_kg: float = 1200.0
## Line on the winch drum; the crane's reach is scaled from it.
@export var reach: float = 14.0
## How fast the winch takes up line, in m/s.
@export var winch_speed: float = 1.8
## Where the crane's turntable sits (or, with no crane, the winch fairlead),
## in the vehicle's frame.
@export var head_offset: Vector3 = Vector3(0, 1.1, -1.2)

const SHORTEST_LINE := 1.2

# --- Crane tuning ------------------------------------------------------------------

## How fast the log goes where it is steered, and gets there.
static var MOVE_SPEED: float = Balance.num("crane.move_speed", 2.4)          ## m/s
const MOVE_ACCEL := 5.0           ## m/s^2
const TURN_SPEED := 1.1           ## rad/s
const TURN_ACCEL := 4.0
## Held right mouse: the fine-control speed for setting a log down.
const FINE := 0.25
## The crane's envelope, from its turntable. The slew arc is either side of
## straight back over the bed: it does not swing through the cab.
const REACH_MIN := 1.6
const SLEW_ARC := deg_to_rad(155.0)
const HEIGHT_ABOVE := 0.75        ## of the boom's length, above the turntable
const DEPTH_BELOW := 3.0          ## m below the turntable
## Joint speeds and accelerations: rad/s (m/s for the telescope).
## slew and luff in rad/s, the telescope and the line in m/s.
const JOINT_SPEED := {"slew": 0.9, "luff": 0.7, "ext": 2.0, "line": 2.6, "rot": 1.6}
const JOINT_ACCEL := {"slew": 2.2, "luff": 2.0, "ext": 4.0, "line": 5.0, "rot": 4.0}
## The shortest the line gets: from the boom tip down to the middle of the
## grapple's jaws.
const HANG := 1.2
## The boom keeps its tip at least this far above the turntable, so the line
## always has somewhere to hang from.
const TIP_LOWEST := 1.2
## How close a log has to be to the jaws for them to close on it.
const GRAB_RADIUS := 0.7
## A log let go this close above the bed and this near square to it is set
## down square.
const SETTLE_HEIGHT := 0.6
const SETTLE_YAW := deg_to_rad(14.0)
## Heavier loads shorten the reach and slow the crane, down to these at its
## rating.
const LOAD_REACH := 0.65
const LOAD_SPEED := 0.5
## The folded, travelling pose.
const REST := {"slew": 0.0, "luff": 0.08, "ext": 0.0, "line": 1.2, "rot": 0.0}
## What the log may not pass through while it is being moved.
const SWEEP_MASK := Layers.WORLD | Layers.VEHICLE | Layers.MACHINE | Layers.TREE | Layers.KERB

var vehicle: RigidBody3D

# --- Winch state ---------------------------------------------------------------

## Hooked on to something. `anchor_body` is the body hooked (null for the
## ground, a wall, anything that does not move), `anchor_local` the point on
## it in its own frame (or in the world, for a fixed anchor).
var anchored: bool = false
var anchor_body: Node3D = null
var anchor_local: Vector3 = Vector3.ZERO
var anchor_point: Vector3 = Vector3.ZERO
var line_length: float = 0.0
var winch_tension: float = 0.0
## The winch hooked on an ore chunk still in the ground.
var anchor_rock: OreRock = null
var _reeling: int = 0

# --- Crane state -----------------------------------------------------------------

## In operator mode: the truck on its outriggers, the controls on the log.
var operating: bool = false
## Folding back to the travelling pose after operator mode.
var folding: bool = false
## Link lengths, from the reach.
## The boom's length run in and run out.
var boom_min: float = 4.8
var boom_max: float = 11.0
## The joints, where they are and how fast they are moving.
var joints := {"slew": 0.0, "luff": 0.08, "ext": 4.8, "line": 1.2, "rot": 0.0}
var _joint_vel := {"slew": 0.0, "luff": 0.0, "ext": 0.0, "line": 0.0, "rot": 0.0}
## The target: the jaws' point and the log's yaw, in the truck's frame.
var target: Vector3 = Vector3.ZERO
var target_yaw: float = 0.0
var _target_vel: Vector3 = Vector3.ZERO
var _yaw_vel: float = 0.0
## True while the target is pressed against the edge of the envelope.
var at_limit: bool = false
## The log in the grapple.
var held: LooseItem = null
## The cab, in the truck's frame: the log is kept out of it.
var cab_box: AABB = AABB()
var _grab_blend: float = 1.0
var _held_basis_from: Basis = Basis()
var _held_vel: Vector3 = Vector3.ZERO

# --- Visuals ---------------------------------------------------------------------

var _cable: MeshInstance3D
var _column: MeshInstance3D
var _boom: MeshInstance3D
var _tele: MeshInstance3D
var _line: MeshInstance3D
var _grapple: Node3D
var _claws: Array[Node3D] = []
var _outriggers: Array[MeshInstance3D] = []
var _aids: Node3D
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _drop_line: MeshInstance3D
var _footprint: MeshInstance3D
var _gizmo: Node3D

func setup(p_vehicle: RigidBody3D) -> void:
	vehicle = p_vehicle

func _ready() -> void:
	boom_min = reach * 0.35
	boom_max = reach * 0.8
	joints = REST.duplicate()
	joints.ext = boom_min
	if vehicle != null and vehicle.get("spec") is Dictionary:
		var cab: Dictionary = (vehicle.get("spec") as Dictionary).get("cab", {})
		var body: Vector3 = vehicle.get("body_size")
		if not cab.is_empty():
			var size := Hauler._vec(cab.size)
			var centre := Vector3(0, body.y * 0.5 + size.y * 0.5, float(cab.z))
			cab_box = AABB(centre - size * 0.5, size)
	_build()
	set_physics_process(true)

func has_crane() -> bool:
	return crane_power_kg > 0.0

## Where the crane turntable sits.
func head_point() -> Vector3:
	if vehicle == null:
		return global_position
	return vehicle.global_transform * head_offset

## Where the winch line leaves the truck: its front bumper on a crane truck,
## otherwise the head.
func fairlead() -> Vector3:
	if vehicle == null:
		return global_position
	if has_crane():
		var size: Vector3 = vehicle.get("body_size") if vehicle.get("body_size") != null else Vector3(2, 1, 4)
		return vehicle.global_transform * Vector3(0, 0.0, -size.z * 0.5 - 0.1)
	return head_point()

# --- The rope --------------------------------------------------------------------

## A rope between two points. Slack, it does nothing; drawn tight past its
## length it pulls the two ends together with a spring and damper sized to the
## masses on it, capped at `most` newtons. Returns the tension it pulled with.
## `a` and `b` are the bodies (null for something fixed).
static func pull(a: RigidBody3D, pa: Vector3, b: RigidBody3D, pb: Vector3, length: float,
		most: float, extra_mass_b: float = 0.0) -> float:
	var span := pb - pa
	var dist := span.length()
	if dist <= length or dist < 0.0001:
		return 0.0
	var n := span / dist
	var inv := 0.0
	var va := Vector3.ZERO
	var vb := Vector3.ZERO
	if a != null and not a.freeze:
		inv += 1.0 / a.mass
		va = a.linear_velocity + a.angular_velocity.cross(pa - a.global_position)
	if b != null and not b.freeze:
		inv += 1.0 / (b.mass + extra_mass_b)
		vb = b.linear_velocity + b.angular_velocity.cross(pb - b.global_position)
	if inv <= 0.0:
		# Both ends fixed (a locked truck on a rock): the line is as good as
		# rigid, so drawing it tighter only raises the pull.
		return clampf((dist - length) * 200000.0, 0.0, most)
	for body in [a, b]:
		if body != null and body.sleeping:
			body.sleeping = false
	var m_eff := 1.0 / inv
	var omega := 16.0
	var stretch := dist - length
	var separating := (vb - va).dot(n)
	var tension := clampf(m_eff * (stretch * omega * omega + separating * 1.6 * omega), 0.0, most)
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	if a != null and not a.freeze:
		a.apply_impulse(n * tension * dt, pa - a.global_position)
	if b != null and not b.freeze:
		b.apply_impulse(-n * tension * dt, pb - b.global_position)
	return tension

# --- Winch ---------------------------------------------------------------------

## Hooks the winch line on at `point`, on `target` (a body, or anything else
## for a fixed anchor). Returns "" or why not.
func attach_winch(target: Node3D, point: Vector3) -> String:
	if anchored:
		return "the winch is already hooked on"
	if fairlead().distance_to(point) > reach:
		return "too far for the winch (%.0f m of line)" % reach
	if target == vehicle or (target != null and target.get_parent() == vehicle):
		return "the winch will not hook its own truck"
	anchored = true
	anchor_rock = target as OreRock
	anchor_body = target as RigidBody3D
	anchor_local = anchor_body.global_transform.affine_inverse() * point if anchor_body != null else point
	anchor_point = point
	line_length = fairlead().distance_to(point) + 0.2
	winch_tension = 0.0
	var item := target as LooseItem
	if item != null:
		item.owned = true
		if item.state != LooseItem.State.FREE:
			item.set_state(LooseItem.State.FREE)
	winch_attached.emit(point)
	return ""

func release_winch() -> void:
	if not anchored:
		return
	anchored = false
	anchor_body = null
	anchor_rock = null
	winch_tension = 0.0
	_cable.visible = false
	winch_released.emit()

func _anchor_world() -> Vector3:
	if anchor_body != null and is_instance_valid(anchor_body):
		return anchor_body.global_transform * anchor_local
	return anchor_local

## Takes up line. It comes in unless the pull has reached the winch's rating,
## when the drum stalls - it does not drag what it cannot.
func reel(delta: float) -> void:
	if not anchored:
		return
	_reeling = 2
	if winch_tension >= winch_power_kg * 9.8 * 0.97:
		return
	line_length = maxf(SHORTEST_LINE, line_length - winch_speed * delta)

## Lets line out, up to what is on the drum.
func pay_out(delta: float) -> void:
	if not anchored:
		return
	line_length = minf(reach, line_length + winch_speed * delta)

## Whether the winch is pulling at its limit right now.
func winch_stalled() -> bool:
	return anchored and winch_tension >= winch_power_kg * 9.8 * 0.97

## The weight on the line, in kilograms of pull.
func winch_load_kg() -> float:
	return winch_tension / 9.8

## Kept for callers that ask whether reeling would do anything.
func winch_can_pull() -> bool:
	return anchored and not winch_stalled()

func _work_winch() -> void:
	if not anchored:
		return
	if anchor_body != null and not is_instance_valid(anchor_body):
		release_winch()
		return
	var body := anchor_body as RigidBody3D
	if body is LooseItem and (body as LooseItem).state == LooseItem.State.POOLED:
		release_winch()
		return
	anchor_point = _anchor_world()
	var most := winch_power_kg * 9.8
	_wake(body)
	winch_tension = pull(vehicle, fairlead(), body, anchor_point, line_length, most * 1.25)
	# Hooked on ore still in the ground: pulled hard enough, it comes out,
	# and the line stays on the chunk.
	if anchor_rock != null:
		if not is_instance_valid(anchor_rock) or anchor_rock.consumed():
			release_winch()
			return
		# Reeling on it with the line tight, the drum pulls with all it is
		# rated for - the truck on its brakes is the anchor at the other end.
		# Or jerked: whatever the line is actually pulling with - a truck's
		# momentum snatching it tight - counts in full.
		var reeled := _reeling > 0 and winch_tension > 0.0 and winch_power_kg >= anchor_rock.pull_required()
		if reeled or winch_load_kg() >= anchor_rock.pull_required():
			var freed := anchor_rock.try_free(maxf(winch_power_kg, winch_load_kg()))
			anchor_rock = null
			if freed != null:
				freed.owned = true
				anchor_body = freed
				anchor_local = Vector3.ZERO
	# Dragged on harder than the drum holds, it slips and pays out.
	if winch_tension > most:
		line_length = minf(reach, line_length + (winch_tension - most) / most * 0.02)
	if fairlead().distance_to(anchor_point) > reach + 3.0:
		release_winch()
	_reeling = maxi(0, _reeling - 1)

# --- Crane: operator mode ------------------------------------------------------------

## Operator mode on: outriggers down, the crane unfolds and the controls move
## the log. Off: whatever is in the grapple is let go, and the crane folds
## back to its travelling pose - the truck stays on its outriggers until it
## has.
func set_operating(on: bool) -> void:
	if not has_crane() or operating == on:
		return
	operating = on
	if on:
		folding = false
		home()
	else:
		drop()
		folding = true
	_apply_plant()

## Sends the grapple back to where operator mode starts it: behind the
## turntable, over the bed, square to the truck. The crane gets there at its
## own pace, carrying whatever it holds.
func home() -> void:
	target = clamp_target(head_offset + Vector3(0, 0.3, boom_min * 0.9))
	target_yaw = 0.0
	_target_vel = Vector3.ZERO
	_yaw_vel = 0.0

## Moves the target: `move` in the truck's frame (x across, y up, z along,
## each -1..1), `turn` the log's yaw (-1..1). `fine` is the slow speed for
## setting down.
func drive(move: Vector3, turn: float, fine: bool, delta: float) -> void:
	if not operating:
		return
	var scale := (FINE if fine else 1.0) * _load_factor(LOAD_SPEED)
	_target_vel = _target_vel.move_toward(move.limit_length(1.0) * MOVE_SPEED * scale, MOVE_ACCEL * delta)
	_yaw_vel = move_toward(_yaw_vel, clampf(turn, -1.0, 1.0) * TURN_SPEED * scale, TURN_ACCEL * delta)
	var raw := target + _target_vel * delta
	var clamped := clamp_target(raw)
	at_limit = clamped.distance_to(raw) > 0.0005
	if at_limit:
		# Pressed against the edge: the push into it goes, the slide along
		# it stays.
		var n := (raw - clamped).normalized()
		_target_vel -= n * maxf(0.0, _target_vel.dot(n))
	target = clamped
	target_yaw = wrapf(target_yaw + _yaw_vel * delta, -PI, PI)

## The camera's left and away-from-camera directions, flat in the truck's
## frame: W moves the log away from the camera, A to the camera's left.
func view_axes() -> Array[Vector3]:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return [Vector3(1, 0, 0), Vector3(0, 0, 1)]
	var inv := _frame().basis.inverse()
	var away := inv * -cam.global_transform.basis.z
	away.y = 0.0
	if away.length() < 0.001:
		away = inv * cam.global_transform.basis.y
		away.y = 0.0
	away = away.normalized()
	return [Vector3.UP.cross(away).normalized(), away]

## The nearest point to `p` (the jaws, in the truck's frame) the crane can
## put its grapple: within its reach and height, inside its slew arc, and out
## of the cab.
func clamp_target(p: Vector3) -> Vector3:
	var rel := p + Vector3.UP * HANG - head_offset
	var h := clampf(rel.y, -DEPTH_BELOW, boom_max * HEIGHT_ABOVE)
	var r := Vector2(rel.x, rel.z).length()
	var ang := atan2(rel.x, rel.z) if r > 0.001 else float(joints.slew)
	ang = clampf(ang, -SLEW_ARC, SLEW_ARC)
	var most := max_reach()
	r = clampf(r, REACH_MIN, most)
	if r * r + h * h > most * most:
		r = sqrt(maxf(most * most - h * h, REACH_MIN * REACH_MIN))
	var out := head_offset + Vector3(sin(ang) * r, h, cos(ang) * r) - Vector3.UP * HANG
	if cab_box.size != Vector3.ZERO:
		var keep_out := cab_box.grow(0.45 + _held_half_height())
		if keep_out.has_point(out):
			var faces := [Vector3(out.x, keep_out.end.y, out.z),
				Vector3(keep_out.position.x, out.y, out.z), Vector3(keep_out.end.x, out.y, out.z),
				Vector3(out.x, out.y, keep_out.position.z), Vector3(out.x, out.y, keep_out.end.z)]
			var best: Vector3 = faces[0]
			for f: Vector3 in faces:
				if f.distance_to(out) < best.distance_to(out):
					best = f
			out = best
	return out

## How far out the crane reaches with what it is holding.
func max_reach() -> float:
	return boom_max * 0.97 * _load_factor(LOAD_REACH)

## 1 empty, falling to `at_rating` with the rated load on.
func _load_factor(at_rating: float) -> float:
	if held == null or crane_power_kg <= 0.0:
		return 1.0
	return lerpf(1.0, at_rating, clampf(held.mass / crane_power_kg, 0.0, 1.0))

func _held_half_height() -> float:
	if held == null:
		return 0.0
	var b := Solid.bounds(held.dims)
	return b.z * 0.5

# --- Crane: kinematics ------------------------------------------------------------------

## The joints that put the jaws on `p` (truck frame) with the log at `yaw`:
## slew to face it, the boom raised and run out so its tip is straight over
## it, and the line let down to it.
func solve(p: Vector3, yaw: float) -> Dictionary:
	var rel := p + Vector3.UP * HANG - head_offset
	var d := Vector2(rel.x, rel.z).length()
	var slew := atan2(rel.x, rel.z) if d > 0.05 else float(joints.slew)
	# The tip goes over the target, no lower than it has to be: at least a
	# short line above it, and not down near the deck.
	var h := maxf(rel.y, TIP_LOWEST)
	var length := sqrt(d * d + h * h)
	if length > boom_max:
		h = sqrt(maxf(boom_max * boom_max - d * d, 0.0))
		length = boom_max
	elif length < boom_min:
		h = sqrt(maxf(boom_min * boom_min - d * d, 0.0))
		length = boom_min
	var luff := atan2(h, d)
	return {"slew": slew, "luff": luff, "ext": length, "line": maxf(HANG, h - rel.y + HANG),
		"rot": wrapf(yaw - slew, -PI, PI)}

## Where the crane's parts are for a set of joints, in the truck's frame. The
## line hangs straight down from the tip: no sway at all.
func fk(j: Dictionary = joints) -> Dictionary:
	var dir := Vector3(sin(float(j.slew)), 0.0, cos(float(j.slew)))
	var along := dir * cos(float(j.luff)) + Vector3.UP * sin(float(j.luff))
	var tip := head_offset + along * float(j.ext)
	return {"base": head_offset, "sleeve": head_offset + along * boom_min * 0.92, "tip": tip,
		"jaw": tip - Vector3.UP * float(j.line), "yaw": float(j.slew) + float(j.rot)}

## The jaws, in the world.
func jaw_world() -> Vector3:
	return _frame() * fk().jaw

## What the camera looks at in operator mode: the log, or the empty grapple.
func focus_point() -> Vector3:
	if held != null and is_instance_valid(held):
		return held.global_position
	return jaw_world()

func _frame() -> Transform3D:
	if vehicle == null:
		return global_transform
	return vehicle.global_transform.orthonormalized()

## A basis with a log's long axis (+Y) lying at `yaw` in the truck's frame,
## its top face up.
static func yaw_basis(yaw: float) -> Basis:
	var along := Vector3(sin(yaw), 0.0, cos(yaw))
	return Basis(along.cross(Vector3.UP), along, Vector3.UP)

## Moves every joint toward its goal at hydraulic speed.
func _step_joints(goals: Dictionary, delta: float, speed_scale: float) -> void:
	for k: String in joints:
		var cur := float(joints[k])
		var goal := float(goals[k])
		# The rotator turns the short way; the slew never swings through the
		# cab, so it goes the way the arc allows.
		var err := angle_difference(cur, goal) if k == "rot" else goal - cur
		var top: float = JOINT_SPEED[k] * speed_scale
		var want := clampf(err * 5.0, -top, top)
		_joint_vel[k] = move_toward(float(_joint_vel[k]), want, float(JOINT_ACCEL[k]) * delta)
		cur += float(_joint_vel[k]) * delta
		joints[k] = wrapf(cur, -PI, PI) if k == "rot" else cur

func _settled(goals: Dictionary, tolerance: float = 0.02) -> bool:
	for k: String in joints:
		var err := angle_difference(float(joints[k]), float(goals[k])) if k == "rot" \
			else float(goals[k]) - float(joints[k])
		if absf(err) > tolerance:
			return false
	return true

# --- Crane: the log ------------------------------------------------------------------

## Closes the grapple on the log between its jaws, or opens it. Returns "" or
## why not.
func latch() -> String:
	if not has_crane():
		return "this vehicle has no crane"
	if not operating:
		return "work the crane first [R]"
	if held != null:
		drop()
		return ""
	var target_node := _between_jaws()
	if target_node == null:
		return "nothing between the jaws - put the grapple on a log"
	var item := target_node as LooseItem
	if target_node is OreRock:
		var rock := target_node as OreRock
		if rock.pull_required() > crane_power_kg:
			return "needs %.0f kg of pull - past this %.0f kg crane" % [rock.pull_required(), crane_power_kg]
		item = rock.try_free(crane_power_kg)
		if item == null:
			return "it will not come out of the ground"
	if item.mass > crane_power_kg:
		return "%.0f kg is too heavy for this crane (rated %.0f kg)" % [item.mass, crane_power_kg]
	_take(item)
	return ""

# --- The claw drop -------------------------------------------------------------------

## [F] with the grapple empty works it like a claw machine: the grapple goes
## straight down until it meets something it can take (or the ground, the bed
## or anything else solid), closes, and comes back up to the height it started
## from - with whatever it caught. [F] again on the way lets go / calls it back.
var claw_state: StringName = &""     ## "", "down" or "up"
var claw_said: String = ""           ## what the last drop came to, for the HUD
var _claw_top: float = 0.0
static var CLAW_SPEED: float = Balance.num("crane.claw_speed", 2.4)             ## m/s the target drops and climbs
const CLAW_FLOOR := 0.35             ## how close below the jaws "the ground" is

func claw() -> String:
	if not has_crane():
		return "this vehicle has no crane"
	if not operating:
		return "work the crane first [R]"
	if held != null:
		claw_state = &""
		drop()
		return ""
	if claw_state == &"down":
		claw_state = &"up"
		return "grapple coming back up"
	if claw_state == &"up":
		return ""
	claw_state = &"down"
	claw_said = ""
	_claw_top = target.y
	return ""

func _work_claw(delta: float) -> void:
	match claw_state:
		&"down":
			var found := _between_jaws()
			if found != null or _jaws_on_something():
				_close_claw()
				return
			var next := target + Vector3.DOWN * CLAW_SPEED * delta
			var clamped := clamp_target(next)
			if clamped.y > next.y + 0.001 and (_frame() * target).distance_to(jaw_world()) < 0.2:
				# As low as the crane goes: close on whatever is there.
				_close_claw()
				return
			target = clamped
		&"up":
			target = clamp_target(Vector3(target.x, move_toward(target.y, _claw_top, CLAW_SPEED * delta), target.z))
			if absf(target.y - _claw_top) < 0.01:
				claw_state = &""

## Something solid right under the jaws: the ground, the bed, a machine.
func _jaws_on_something() -> bool:
	var jaw := jaw_world()
	var q := PhysicsRayQueryParameters3D.create(jaw, jaw + Vector3.DOWN * CLAW_FLOOR,
		Layers.WORLD | Layers.VEHICLE | Layers.MACHINE | Layers.KERB)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _close_claw() -> void:
	var said := latch()
	claw_said = said if said != "" else ("got %s" % held.display_name() if held != null else "")
	if held == null and claw_said == "":
		claw_said = "nothing there"
	claw_state = &"up"

## Kept for the old key.
func grab(_item: LooseItem = null) -> String:
	if held != null:
		return "the crane is already holding something"
	return latch()

## The loose piece (or ore in the ground) nearest the jaws, within reach of
## them.
func _between_jaws() -> Node3D:
	var jaw := jaw_world()
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = GRAB_RADIUS
	q.shape = sphere
	q.transform = Transform3D(Basis(), jaw)
	q.collision_mask = Layers.LOOSE | Layers.TREE
	var best: Node3D = null
	var best_d := INF
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 16):
		var o: Object = hit.collider
		var n: Node3D = null
		if o is OreRock and not (o as OreRock).consumed():
			n = o
		elif o is LooseItem and (o as LooseItem).state == LooseItem.State.FREE:
			n = o
		if n != null and n.global_position.distance_to(jaw) < best_d:
			best_d = n.global_position.distance_to(jaw)
			best = n
	return best

func _take(item: LooseItem) -> void:
	held = item
	item.owned = true
	item.set_state(LooseItem.State.CAPTURED)
	var frame := _frame()
	_held_basis_from = (frame.basis.inverse() * item.global_transform.basis).orthonormalized()
	_grab_blend = 0.0
	# The target goes to the log, turned whichever way round is nearer.
	var along := _held_basis_from.y
	var yaw := atan2(along.x, along.z)
	var now := float(joints.slew) + float(joints.rot)
	if absf(angle_difference(now, yaw + PI)) < absf(angle_difference(now, yaw)):
		yaw = wrapf(yaw + PI, -PI, PI)
	target_yaw = yaw
	target = clamp_target(frame.affine_inverse() * item.global_position)
	_target_vel = Vector3.ZERO
	crane_grabbed.emit(item)

## Opens the grapple. A log let go low over the bed and near square to it is
## set down square. Returns what it let go of.
func drop() -> LooseItem:
	if held == null:
		return null
	var item := held
	held = null
	if is_instance_valid(item) and item.state == LooseItem.State.CAPTURED:
		_settle(item)
		item.set_state(LooseItem.State.FREE)
		item.linear_velocity = _held_vel.limit_length(3.0)
	crane_released.emit(item)
	return item

func holding() -> bool:
	if held != null and (not is_instance_valid(held) or held.state != LooseItem.State.CAPTURED):
		held = null
	return held != null

func _settle(item: LooseItem) -> void:
	if vehicle == null or vehicle.get("bed_half_width") == null:
		return
	var frame := _frame()
	var local := frame.affine_inverse() * item.global_position
	var half_w := float(vehicle.get("bed_half_width"))
	if half_w <= 0.0 or absf(local.x) > half_w \
			or local.z < float(vehicle.get("bed_front")) or local.z > float(vehicle.get("bed_back")):
		return
	if local.y - float(vehicle.get("bed_floor")) - Solid.bounds(item.dims).z * 0.5 > SETTLE_HEIGHT:
		return
	var yaw := float(fk().yaw)
	for square in [0.0, PI]:
		if absf(angle_difference(yaw, square)) < SETTLE_YAW:
			var basis := frame.basis * yaw_basis(square)
			if not _overlaps(item, Transform3D(basis, item.global_position)):
				item.global_transform = Transform3D(basis, item.global_position)
			return

## Carries the log in the grapple to the jaws, swept so it stops against the
## truck, the ground or a building rather than going through.
func _carry(delta: float) -> void:
	var frame := _frame()
	var pose := fk()
	var want_basis := yaw_basis(float(pose.yaw))
	if _grab_blend < 1.0:
		_grab_blend = minf(1.0, _grab_blend + delta / 0.6)
		want_basis = _held_basis_from.slerp(want_basis, smoothstep(0.0, 1.0, _grab_blend))
	var from := held.global_position
	# Turned first, on the spot - unless turning would put it into something.
	var turned := Transform3D(frame.basis * want_basis, from)
	if not _overlaps(held, turned) or _overlaps(held, held.global_transform):
		held.global_transform = turned
	else:
		_yaw_vel = 0.0
		var along := (frame.basis.inverse() * held.global_transform.basis.y)
		target_yaw = atan2(along.x, along.z)
	var motion: Vector3 = frame * Vector3(pose.jaw) - from
	var moved := _sweep(held, motion)
	held.global_position = from + moved
	_held_vel = moved / maxf(delta, 0.0001)
	if (motion - moved).length() > 0.03:
		# Up against something: the target stops at the log, so the crane
		# does not go on pressing it in.
		var at := frame.affine_inverse() * held.global_position
		target = target.lerp(at, 0.35)
		_target_vel = Vector3.ZERO

## How far `item` can go along `motion` before it hits something it may not
## pass through, sliding along what it hits.
func _sweep(item: LooseItem, motion: Vector3) -> Vector3:
	if motion.length() < 0.00001:
		return Vector3.ZERO
	var frac := _cast(item, item.global_transform, motion)
	if frac >= 1.0:
		return motion
	var done := motion * frac
	var n := _contact_normal(item, item.global_transform.translated(done + motion.normalized() * 0.03))
	if n == Vector3.ZERO:
		return done
	var rest := motion - done
	rest -= n * minf(0.0, rest.dot(n))
	return done + rest * _cast(item, item.global_transform.translated(done), rest)

func _shapes(item: LooseItem) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for c in item.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null and not (c as CollisionShape3D).disabled:
			out.append(c)
	return out

func _query(item: LooseItem, cs: CollisionShape3D, xform: Transform3D) -> PhysicsShapeQueryParameters3D:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cs.shape
	q.transform = xform * (item.global_transform.affine_inverse() * cs.global_transform)
	q.collision_mask = SWEEP_MASK
	q.exclude = [item.get_rid()]
	return q

func _cast(item: LooseItem, xform: Transform3D, motion: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var least := 1.0
	for cs in _shapes(item):
		var q := _query(item, cs, xform)
		q.motion = motion
		var f: float = space.cast_motion(q)[0]
		if f <= 0.0:
			# Already touching (lying on the ground, say): moving away from
			# what it touches is allowed.
			q.margin = 0.02
			var info := space.get_rest_info(q)
			if not info.is_empty() and (info.normal as Vector3).dot(motion.normalized()) > -0.05:
				f = 1.0
		least = minf(least, f)
	return least

func _contact_normal(item: LooseItem, xform: Transform3D) -> Vector3:
	var space := get_world_3d().direct_space_state
	for cs in _shapes(item):
		var q := _query(item, cs, xform)
		q.margin = 0.03
		var info := space.get_rest_info(q)
		if not info.is_empty():
			return info.normal
	return Vector3.ZERO

func _overlaps(item: LooseItem, xform: Transform3D) -> bool:
	var space := get_world_3d().direct_space_state
	for cs in _shapes(item):
		if not space.intersect_shape(_query(item, cs, xform), 1).is_empty():
			return true
	return false

## Folded for the road: slewed back over the bed, the boom down and run in,
## the line wound up short.
func _rest_goals() -> Dictionary:
	var rest := REST.duplicate()
	rest.ext = boom_min
	return rest

func _work_crane(delta: float) -> void:
	if not has_crane():
		return
	holding()
	if operating:
		_work_claw(delta)
	else:
		claw_state = &""
	var goals: Dictionary = solve(target, target_yaw) if operating else _rest_goals()
	_step_joints(goals, delta, _load_factor(LOAD_SPEED))
	if folding and _settled(_rest_goals(), 0.05):
		folding = false
		_apply_plant()
	if held != null:
		_carry(delta)

# --- Outriggers ------------------------------------------------------------------

## Outriggers out: the truck stands on them, locked where it is - an anchor
## for the winch, or a steady base for the crane. Working the crane puts them
## down too; stowing it leaves them as they were set.
var outriggers_down: bool = false

func set_outriggers(on: bool) -> void:
	outriggers_down = on
	_apply_plant()

func planted() -> bool:
	return outriggers_down or operating or folding

func _apply_plant() -> void:
	var on := planted()
	if vehicle != null and vehicle.has_method("set_planted"):
		vehicle.call("set_planted", on)
	for leg in _outriggers:
		leg.visible = on

static func _wake(body: RigidBody3D) -> void:
	if body != null and body.sleeping:
		body.sleeping = false

func _physics_process(delta: float) -> void:
	if vehicle == null:
		return
	_work_winch()
	_work_crane(delta)
	_draw()

## One line of what the rig is doing, for the prompt.
func status_line() -> String:
	var bits: Array[String] = []
	if outriggers_down and not operating:
		bits.append("outriggers down - locked in place  [O] up")
	if operating:
		var load := "%s, %.0f / %.0f kg" % [held.display_name(), held.mass, crane_power_kg] if held != null \
			else "grapple open, %.0f kg crane" % crane_power_kg
		bits.append("crane: %s%s  [W/S] away/toward [A/D] left/right [Shift/Ctrl] up/down [Q/E] turn [F] %s [RMB] fine [N] reset [R] done" % [
			load, " - AT ITS LIMIT" if at_limit else "", "let go" if held != null else ("stop" if claw_state == &"down" else "drop the claw")])
	elif folding:
		bits.append("crane folding away")
	if anchored:
		if anchor_rock != null:
			bits.append("winch on %s in the ground: needs %.0f kg of pull" % [
				GameData.item_name(anchor_rock.ore_item), anchor_rock.pull_required()])
		bits.append("winch: %.0f m of line, pulling %.0f / %.0f kg%s  [K] reel in [L] let out [Y] unhook" % [
			line_length, winch_load_kg(), winch_power_kg, " - STALLED" if winch_stalled() else ""])
	if not bits.is_empty():
		return "\n".join(bits)
	if not has_crane():
		return "winch %.0f kg, %.0f m of line  [Y] hook what you aim at" % [winch_power_kg, reach]
	return "winch %.0f kg / crane %.0f kg, %.0f m reach  [Y] winch [R] crane" % [
		winch_power_kg, crane_power_kg, max_reach()]

# --- Geometry --------------------------------------------------------------------

const CRANE_YELLOW := Color(0.92, 0.7, 0.12)
const CRANE_DARK := Color(0.2, 0.2, 0.22)

func _build() -> void:
	_cable = _line_mesh(Color(0.14, 0.14, 0.16))
	var paint := _mat(CRANE_YELLOW, 0.3)
	# Outrigger legs, out to each side at front and back, shown while down.
	if vehicle != null and vehicle.get("body_size") != null:
		var size: Vector3 = vehicle.get("body_size")
		for zf in [-0.35, 0.35]:
			for side in [-1.0, 1.0]:
				var leg := MeshInstance3D.new()
				var lm := BoxMesh.new()
				lm.size = Vector3(1.4, 0.2, 0.3)
				leg.mesh = lm
				leg.material_override = paint
				leg.position = Vector3(side * (size.x * 0.5 + 0.5), -size.y * 0.5 + 0.05, zf * size.z)
				leg.visible = false
				vehicle.add_child.call_deferred(leg)
				var foot := MeshInstance3D.new()
				var fm := BoxMesh.new()
				fm.size = Vector3(0.5, 0.9, 0.5)
				foot.mesh = fm
				foot.material_override = paint
				foot.position = Vector3(side * 0.6, -0.45, 0)
				leg.add_child(foot)
				_outriggers.append(leg)
	if not has_crane():
		return
	_column = _box_part(paint, "CraneColumn")
	_boom = _box_part(paint, "CraneBoom")
	_tele = _box_part(_mat(CRANE_YELLOW.lightened(0.25), 0.4), "CraneTelescope")
	_line = _line_mesh(CRANE_DARK)
	_line.name = "CraneLine"
	_build_grapple()
	_build_aids()

func _mat(color: Color, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = 0.5
	return m

func _box_part(mat: Material, part: String) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = part
	var bm := BoxMesh.new()
	m.mesh = bm
	m.material_override = mat
	m.top_level = true
	m.visible = false
	add_child(m)
	return m

## The grapple: a rotator on top and two curved jaws that close round a log.
func _build_grapple() -> void:
	_grapple = Node3D.new()
	_grapple.name = "Grapple"
	_grapple.top_level = true
	add_child(_grapple)
	var dark := _mat(CRANE_DARK, 0.5)
	var rot := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.16
	rm.bottom_radius = 0.16
	rm.height = 0.25
	rot.mesh = rm
	rot.material_override = dark
	rot.position = Vector3(0, 0.62, 0)
	_grapple.add_child(rot)
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.5, 0.18, 0.4)
	head.mesh = hm
	head.material_override = _mat(CRANE_YELLOW, 0.3)
	head.position = Vector3(0, 0.45, 0)
	_grapple.add_child(head)
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.2, 0.4, 0)
		_grapple.add_child(pivot)
		# Two plates per jaw, angled in, so it reads as a curved claw.
		for k in 2:
			var plate := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.07, 0.45, 0.34)
			plate.mesh = pm
			plate.material_override = dark
			plate.position = Vector3(side * 0.05, -0.22, 0) if k == 0 else Vector3(side * 0.02, -0.62, 0)
			plate.rotation.z = side * (0.15 if k == 0 else -0.55)
			if k == 1:
				plate.position.x += side * 0.1
			pivot.add_child(plate)
		_claws.append(pivot)

## The operator's aids: the ghost of where the log is heading, a drop line and
## footprint under it, and arrows for which way the keys move it.
func _build_aids() -> void:
	_aids = Node3D.new()
	_aids.name = "CraneAids"
	_aids.top_level = true
	_aids.visible = false
	add_child(_aids)
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(0.5, 0.9, 1.0, 0.25)
	_ghost = MeshInstance3D.new()
	_ghost.mesh = BoxMesh.new()
	_ghost.material_override = _ghost_mat
	_ghost.top_level = true
	_aids.add_child(_ghost)
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.albedo_color = Color(1, 1, 1, 0.55)
	_drop_line = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.015
	cm.bottom_radius = 0.015
	cm.radial_segments = 4
	_drop_line.mesh = cm
	_drop_line.material_override = line_mat
	_drop_line.top_level = true
	_aids.add_child(_drop_line)
	_footprint = MeshInstance3D.new()
	_footprint.mesh = BoxMesh.new()
	var foot_mat := line_mat.duplicate() as StandardMaterial3D
	foot_mat.albedo_color = Color(0, 0, 0, 0.35)
	_footprint.material_override = foot_mat
	_footprint.top_level = true
	_aids.add_child(_footprint)
	# The move gizmo: W away from the camera, S toward it, A and D to its
	# left and right, laid flat in the truck's frame.
	_gizmo = Node3D.new()
	_gizmo.top_level = true
	_aids.add_child(_gizmo)
	var arrow_mat := line_mat.duplicate() as StandardMaterial3D
	arrow_mat.albedo_color = Color(1.0, 0.85, 0.3, 0.8)
	arrow_mat.no_depth_test = true
	for spec in [["W", Vector3(0, 0, 1)], ["S", Vector3(0, 0, -1)], ["A", Vector3(1, 0, 0)], ["D", Vector3(-1, 0, 0)]]:
		var dir: Vector3 = spec[1]
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.05, 0.05, 0.6) if dir.x == 0.0 else Vector3(0.6, 0.05, 0.05)
		arm.mesh = am
		arm.material_override = arrow_mat
		arm.position = dir * 0.75
		_gizmo.add_child(arm)
		var label := Label3D.new()
		label.text = spec[0]
		label.font_size = 48
		label.pixel_size = 0.006
		label.outline_size = 10
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color(1.0, 0.9, 0.4)
		label.position = dir * 1.2
		_gizmo.add_child(label)

func _line_mesh(color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.radial_segments = 6
	m.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material_override = mat
	m.visible = false
	m.top_level = true
	add_child(m)
	return m

func _draw() -> void:
	if anchored:
		_span(_cable, fairlead(), anchor_point, 0.035)
	else:
		_cable.visible = false
	if not has_crane():
		return
	var frame := _frame()
	var pose := fk()
	var base: Vector3 = frame * Vector3(pose.base)
	var sleeve: Vector3 = frame * Vector3(pose.sleeve)
	var tip: Vector3 = frame * Vector3(pose.tip)
	var up := frame.basis.y.normalized()
	_span(_column, base - up * 0.5, base + up * 0.25, 0.26)
	# The boom: a heavy outer section off the turntable, and the telescoping
	# inner one sliding out of it to the tip.
	_span(_boom, base, sleeve, 0.18)
	var run := (tip - base).normalized()
	_span(_tele, base + run * boom_min * 0.3, tip + run * 0.05, 0.12)
	# The grapple hangs from the tip; holding a log it is wherever the log is.
	var yaw := float(pose.yaw)
	var grip: Vector3 = held.global_position if held != null else frame * Vector3(pose.jaw)
	var grapple_basis := frame.basis * Basis(Vector3.UP, yaw)
	var lift := _held_half_height()
	_grapple.global_transform = Transform3D(grapple_basis, grip + up * lift)
	_span(_line, tip, grip + up * (lift + 0.75), 0.025)
	var open := 0.1 if held != null else 0.75
	for i in _claws.size():
		var side := -1.0 if i == 0 else 1.0
		_claws[i].rotation.z = lerp_angle(_claws[i].rotation.z, side * open, 0.25)
	_draw_aids(frame, grip, yaw)

func _draw_aids(frame: Transform3D, grip: Vector3, yaw: float) -> void:
	_aids.visible = operating
	if not operating:
		return
	var ghost_at: Vector3 = frame * target
	_ghost_mat.albedo_color = Color(1.0, 0.3, 0.25, 0.35) if at_limit else Color(0.5, 0.9, 1.0, 0.22)
	var gm := _ghost.mesh as BoxMesh
	if held != null:
		gm.size = Solid.bounds(held.dims)
		_ghost.global_transform = Transform3D(frame.basis * yaw_basis(target_yaw), ghost_at)
	else:
		gm.size = Vector3(0.5, 0.5, 0.5)
		_ghost.global_transform = Transform3D(frame.basis * Basis(Vector3.UP, target_yaw), ghost_at)
	# Scaled to clear the log, so the arrows stand out beyond its ends.
	var spread := 1.0 if held == null else maxf(1.0, Solid.bounds(held.dims).y * 0.6)
	var axes := view_axes()
	var view := Basis(axes[0], Vector3.UP, axes[1])
	_gizmo.global_transform = Transform3D((frame.basis * view).scaled(Vector3.ONE * spread), ghost_at + frame.basis.y * 0.9)
	# Straight down from the log (or the jaws) to whatever it would land on.
	var down := -frame.basis.y.normalized()
	var q := PhysicsRayQueryParameters3D.create(grip, grip + down * 40.0,
		Layers.WORLD | Layers.VEHICLE | Layers.LOOSE | Layers.MACHINE)
	if held != null:
		q.exclude = [held.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_drop_line.visible = false
		_footprint.visible = false
		return
	var land: Vector3 = hit.position
	_span(_drop_line, grip, land, 0.015)
	_footprint.visible = true
	var fm := _footprint.mesh as BoxMesh
	if held != null:
		var b := Solid.bounds(held.dims)
		fm.size = Vector3(b.x, 0.02, b.y)
	else:
		fm.size = Vector3(0.6, 0.02, 0.6)
	var n: Vector3 = hit.normal
	var along := (frame.basis * Vector3(sin(yaw), 0.0, cos(yaw)))
	along = (along - n * along.dot(n)).normalized()
	_footprint.global_transform = Transform3D(Basis(n.cross(along), n, along).orthonormalized(), land + n * 0.03)

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
	var forward := delta / length
	var basis: Basis
	if mesh.mesh is CylinderMesh:
		# Cylinders run along their own Y.
		var axis := Vector3.UP.cross(forward)
		basis = Basis() if axis.length_squared() < 0.0001 \
			else Basis(axis.normalized(), Vector3.UP.angle_to(forward))
	else:
		basis = Basis.looking_at(forward, Vector3.UP if absf(forward.y) < 0.99 else Vector3.RIGHT)
	mesh.global_transform = Transform3D(basis, from + delta * 0.5)
