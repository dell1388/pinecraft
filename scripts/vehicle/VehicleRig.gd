class_name VehicleRig
extends Node3D

## The gear bolted to a vehicle: a winch and, on some, a crane. Both are real
## machines working through a real line.
##
## A line is a rope: slack until it is drawn tight, then it pulls both ends
## together as hard as it has to - up to what the machine on it is rated for.
## Past that the drum stalls when you reel in, and slips when something drags
## on it. Nothing is snapped to anything and nothing is made weightless.
##
## The winch line runs from the fairlead on the front of the truck to whatever
## it is hooked to: a log, a tree, a rock face, another truck. Reel in and the
## lighter end comes: a log is dragged to the truck, the truck is dragged to a
## tree. Use it from the seat or standing near the truck.
##
## The crane is a boom on a turntable - slew it round, luff it up and down,
## run it out and in - with a hook hanging from its tip on the hoist rope.
## Latch the hook to a load and hoist: the load comes up on the rope and
## swings under the boom. While it works the truck stands on its outriggers.

signal winch_attached(anchor: Vector3)
signal winch_released()
signal crane_grabbed(item: LooseItem)
signal crane_released(item: LooseItem)

## What the winch can pull, in kilograms. Past this it stalls.
@export var winch_power_kg: float = 4000.0
## What the crane can hoist, in kilograms.
@export var crane_power_kg: float = 1200.0
## Line on the winch drum, and the crane's longest boom.
@export var reach: float = 14.0
## How fast the winch takes up line, and the hoist its rope, in m/s.
@export var winch_speed: float = 1.8
@export var hoist_speed: float = 1.6
## Where the crane's turntable sits (or, with no crane, the winch fairlead),
## in the vehicle's frame.
@export var head_offset: Vector3 = Vector3(0, 1.1, -1.2)

const SHORTEST_LINE := 1.2
const BOOM_MIN := 3.0
const LUFF_MIN := 0.05
const LUFF_MAX := 1.25
const HOOK_MASS := 50.0

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

# --- Crane state ---------------------------------------------------------------

var operating: bool = false
var slew: float = 0.0
var luff: float = 0.6
var boom_length: float = 5.0
var hoist_length: float = 2.0
var hoist_tension: float = 0.0
var hook: RigidBody3D
var held: LooseItem = null
var _latch: Joint3D

var _cable: MeshInstance3D
var _boom: MeshInstance3D
var _rope: MeshInstance3D
var _outriggers: Array[MeshInstance3D] = []

func setup(p_vehicle: RigidBody3D) -> void:
	vehicle = p_vehicle

## Where the boom lies when stowed: folded back over the bed.
const REST_SLEW := PI
const REST_LUFF := 0.06

func _ready() -> void:
	slew = REST_SLEW
	luff = REST_LUFF
	boom_length = BOOM_MIN
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
		return 0.0
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
	# Dragged on harder than the drum holds, it slips and pays out.
	if winch_tension > most:
		line_length = minf(reach, line_length + (winch_tension - most) / most * 0.02)
	if fairlead().distance_to(anchor_point) > reach + 3.0:
		release_winch()

# --- Crane ---------------------------------------------------------------------

## Where the boom's tip is.
func tip_point() -> Vector3:
	var b := vehicle.global_transform.basis if vehicle != null else Basis()
	var dir := b * (Basis(Vector3.UP, slew) * Basis(Vector3.RIGHT, luff) * Vector3(0, 0, -1))
	return head_point() + dir * boom_length

## Crane mode: the truck stands on its outriggers and the controls work the
## crane. Off, the hook is stowed against the boom tip.
func set_operating(on: bool) -> void:
	if not has_crane() or operating == on:
		return
	operating = on
	if vehicle != null and vehicle.has_method("set_planted"):
		vehicle.call("set_planted", on)
	for leg in _outriggers:
		leg.visible = on
	if on:
		# Up off the bed, ready to work.
		if luff < 0.3:
			luff = 0.6
		hook.freeze = false
		hook.collision_layer = Layers.VEHICLE
		hook.collision_mask = Layers.WORLD | Layers.LOOSE | Layers.MACHINE | Layers.TREE
		hook.sleeping = false
		hoist_length = maxf(1.0, hoist_length)
	elif held == null:
		_stow_hook()

## Works the crane: `swing` slews, `raise` luffs, `extend` runs the boom out
## or in, `hoist` takes up (+) or lets out (-) rope. Each is -1..1.
func work(swing: float, raise: float, extend: float, hoist: float, delta: float) -> void:
	if not operating:
		return
	slew = wrapf(slew + swing * 0.55 * delta, -PI, PI)
	luff = clampf(luff + raise * 0.35 * delta, LUFF_MIN, LUFF_MAX)
	boom_length = clampf(boom_length + extend * 1.4 * delta, BOOM_MIN, reach)
	if hoist > 0.0:
		# The hoist stalls at its rating: it does not lift what it cannot.
		if hoist_tension < crane_power_kg * 9.8 * 0.97:
			hoist_length = maxf(0.6, hoist_length - hoist * hoist_speed * delta)
	elif hoist < 0.0:
		# A slack-line cut-out: with the hook resting on something, the drum
		# stops paying out rather than piling rope on top of it.
		var hanging := tip_point().distance_to(hook.global_position + Vector3(0, 0.25, 0))
		hoist_length = minf(minf(reach * 1.5, hanging + 0.5), hoist_length - hoist * hoist_speed * delta)
	hook.sleeping = false

## Latches the hook to whatever loose piece it is touching, or lets go of
## what it has. Returns "" or why not.
func latch() -> String:
	if not has_crane():
		return "this vehicle has no crane"
	if not operating:
		return "work the crane first [Q]"
	if held != null:
		drop()
		return ""
	var item := _touching_hook()
	if item == null:
		return "the hook is not touching anything to lift"
	held = item
	item.owned = true
	if item.state != LooseItem.State.FREE:
		item.set_state(LooseItem.State.FREE)
	item.sleeping = false
	var pin := PinJoint3D.new()
	pin.name = "Latch"
	add_child(pin)
	pin.global_position = hook.global_position
	pin.node_a = pin.get_path_to(hook)
	pin.node_b = pin.get_path_to(item)
	_latch = pin
	crane_grabbed.emit(item)
	return ""

## Kept for the old key: latch whatever the hook is touching.
func grab(_item: LooseItem = null) -> String:
	if held != null:
		return "the crane is already holding something"
	return latch()

func drop() -> LooseItem:
	if held == null:
		return null
	var item := held
	held = null
	if _latch != null and is_instance_valid(_latch):
		_latch.queue_free()
	_latch = null
	crane_released.emit(item)
	return item

func holding() -> bool:
	if held != null and (not is_instance_valid(held) or held.state == LooseItem.State.POOLED):
		drop()
	return held != null

func _touching_hook() -> LooseItem:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.75
	q.shape = sphere
	q.transform = Transform3D(Basis(), hook.global_position)
	q.collision_mask = Layers.LOOSE
	q.exclude = [hook.get_rid()]
	var best: LooseItem = null
	var best_d := INF
	for hit in space.intersect_shape(q, 16):
		var item := hit.collider as LooseItem
		if item == null or item.state == LooseItem.State.POOLED:
			continue
		var d := item.global_position.distance_to(hook.global_position)
		if d < best_d:
			best_d = d
			best = item
	return best

func _stow_hook() -> void:
	# Stowed, the hook is clipped to the boom and touches nothing - not the
	# load in the bed it hangs over.
	hook.freeze = true
	hook.collision_layer = 0
	hook.collision_mask = 0
	var tip := tip_point()
	hook.global_transform = Transform3D(Basis(), tip + Vector3(0, -0.6, 0))
	hook.linear_velocity = Vector3.ZERO
	hook.angular_velocity = Vector3.ZERO
	hoist_length = 0.6
	hoist_tension = 0.0

func _work_crane() -> void:
	if not has_crane():
		return
	holding()
	if not operating and held == null:
		# Stowed, the boom folds itself back down over the bed.
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		slew = rotate_toward(slew, REST_SLEW, 0.8 * dt)
		luff = move_toward(luff, REST_LUFF, 0.4 * dt)
		boom_length = move_toward(boom_length, BOOM_MIN, 2.0 * dt)
		_stow_hook()
		return
	if hook.freeze:
		hook.freeze = false
		hook.collision_layer = Layers.VEHICLE
		hook.collision_mask = Layers.WORLD | Layers.LOOSE | Layers.MACHINE | Layers.TREE
	var extra := held.mass if held != null else 0.0
	if held != null:
		_wake(held)
	hoist_tension = pull(null, tip_point(), hook, hook.global_position + Vector3(0, 0.25, 0), hoist_length,
		crane_power_kg * 9.8 * 1.25 + HOOK_MASS * 9.8, extra)
	# The crane truck's tip is carried by its outriggers; stood down with a
	# load still on, the load pulls on the truck.
	if not operating and vehicle != null and hoist_tension > 0.0:
		var n := (hook.global_position - tip_point()).normalized()
		vehicle.apply_impulse(n * hoist_tension / float(Engine.physics_ticks_per_second),
			tip_point() - vehicle.global_position)

static func _wake(body: RigidBody3D) -> void:
	if body != null and body.sleeping:
		body.sleeping = false

func _physics_process(_delta: float) -> void:
	if vehicle == null:
		return
	_work_winch()
	_work_crane()
	_draw()

## One line of what the rig is doing, for the prompt.
func status_line() -> String:
	var bits: Array[String] = []
	if operating:
		bits.append("crane: %.0f° slew, %.0f m boom, hoist %.0f / %.0f kg%s  [A/D] swing [W/S] boom up/down [R/T] out/in [Shift/Ctrl] hoist [F] %s [Q] done" % [
			rad_to_deg(slew), boom_length, hoist_tension / 9.8, crane_power_kg,
			" - STALLED" if hoist_tension >= crane_power_kg * 9.8 * 0.97 else "",
			"let go" if held != null else "latch"])
	if anchored:
		bits.append("winch: %.0f m of line, pulling %.0f / %.0f kg%s  [K] reel in [L] let out [Y] unhook" % [
			line_length, winch_load_kg(), winch_power_kg, " - STALLED" if winch_stalled() else ""])
	if not bits.is_empty():
		return "\n".join(bits)
	if not has_crane():
		return "winch %.0f kg, %.0f m of line  [Y] hook what you aim at" % [winch_power_kg, reach]
	return "winch %.0f kg / crane %.0f kg, %.0f m reach  [Y] winch [Q] crane" % [
		winch_power_kg, crane_power_kg, reach]

# --- Geometry --------------------------------------------------------------------

func _build() -> void:
	_cable = _line_mesh(Color(0.14, 0.14, 0.16))
	_rope = _line_mesh(Color(0.12, 0.12, 0.13))
	_boom = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.3, 1.0)
	_boom.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.9, 0.7, 0.12)
	bmat.metallic = 0.3
	_boom.material_override = bmat
	_boom.visible = false
	_boom.top_level = true
	add_child(_boom)
	if not has_crane():
		return
	hook = RigidBody3D.new()
	hook.name = "Hook"
	hook.top_level = true
	hook.mass = HOOK_MASS
	hook.collision_layer = Layers.VEHICLE
	hook.collision_mask = Layers.WORLD | Layers.LOOSE | Layers.MACHINE | Layers.TREE
	hook.angular_damp = 2.0
	hook.linear_damp = 0.1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.35, 0.5, 0.35)
	cs.shape = box
	hook.add_child(cs)
	var g := Greeble.new()
	g.box(Vector3(0.35, 0.5, 0.35), Transform3D(), Color(0.95, 0.72, 0.1))
	g.box(Vector3(0.1, 0.25, 0.3), Transform3D(Basis(), Vector3(0, -0.35, 0)), Color(0.2, 0.2, 0.22))
	hook.add_child(g.instance("HookModel", false))
	add_child(hook)
	if vehicle != null:
		hook.add_collision_exception_with(vehicle)
	_stow_hook.call_deferred()
	# Outrigger legs, out to each side at front and back, shown while working.
	if vehicle != null and vehicle.get("body_size") != null:
		var size: Vector3 = vehicle.get("body_size")
		for zf in [-0.35, 0.35]:
			for side in [-1.0, 1.0]:
				var leg := MeshInstance3D.new()
				var lm := BoxMesh.new()
				lm.size = Vector3(1.4, 0.2, 0.3)
				leg.mesh = lm
				leg.material_override = bmat
				leg.position = Vector3(side * (size.x * 0.5 + 0.5), -size.y * 0.5 + 0.05, zf * size.z)
				leg.visible = false
				vehicle.add_child.call_deferred(leg)
				var foot := MeshInstance3D.new()
				var fm := BoxMesh.new()
				fm.size = Vector3(0.5, 0.9, 0.5)
				foot.mesh = fm
				foot.material_override = bmat
				foot.position = Vector3(side * 0.6, -0.45, 0)
				leg.add_child(foot)
				_outriggers.append(leg)

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
	if has_crane():
		_span(_boom, head_point(), tip_point(), 0.15)
		_span(_rope, tip_point(), hook.global_position + Vector3(0, 0.25, 0), 0.03)
	else:
		_boom.visible = false

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
