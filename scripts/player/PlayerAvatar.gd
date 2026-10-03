class_name PlayerAvatar
extends Node3D

## The lumberjack you play as: the model in assets/models/player.glb, posed in
## code every frame from what the player is doing. Nothing is keyframed in the
## file - the model is six pivots (legs, torso, arms, head) and this works them,
## the same way the rest of the game is built in code. Each arm bends at the
## elbow and wrist, each leg at the knee and ankle, and each hand has four
## fingers and a thumb that close round a handle or a wheel.
##
## There are two kinds of motion:
##
##   the base pose   what the body is doing all the time: standing, walking,
##                   sprinting, in the air, swimming, wading, carrying a load,
##                   dragging something, holding a tool, sitting at the wheel,
##                   working a crane or loader, or watching from build mode
##   gestures        one-off moves laid over it, started by `play`: a chop, a
##                   hammer blow, picking up, throwing, dropping, using
##                   something, pulling a lever in the cab, placing and
##                   removing buildings, drawing a tool, and, when stood about
##                   for a while, a fidget (a beard stroke, a look round, a
##                   stretch, a scratch under the hat)
##
## In first person only the shadow is drawn, so the body never gets in front of
## the camera; in third person, at the wheel and in build mode, all of him.
##
## `player` is a Player, or in co-op a stand-in for someone on another machine
## (Avatar) that answers the same few questions. What happens on the host -
## what is carried or dragged, build mode, gestures - comes in `net_state`
## when the host has sent it, and wins over what this machine can see.

const MODEL := "res://assets/models/player.glb"
const PARTS: Array[StringName] = [&"Leg_L", &"Leg_R", &"Torso", &"Arm_L", &"Arm_R", &"Head",
	&"Elbow_L", &"Elbow_R", &"Hand_L", &"Hand_R", &"Knee_L", &"Knee_R", &"Foot_L", &"Foot_R",
	&"Finger_L0", &"Finger_L1", &"Finger_L2", &"Finger_L3", &"Thumb_L",
	&"Finger_R0", &"Finger_R1", &"Finger_R2", &"Finger_R3", &"Thumb_R",
	&"FingerTip_L0", &"FingerTip_L1", &"FingerTip_L2", &"FingerTip_L3", &"ThumbTip_L",
	&"FingerTip_R0", &"FingerTip_R1", &"FingerTip_R2", &"FingerTip_R3", &"ThumbTip_R"]
## Where a tool's grip sits in the right hand, in the hand's own frame.
const GRIP := Vector3(0.0, -0.09, 0.0)

## His hip pivots above his feet, from the hips to the top of his hat, and
## how far the underside of a thigh is below the hip pivot when sitting.
const HIP_HEIGHT := 0.62
const SEATED_HEIGHT := 1.12
const THIGH := 0.13
## Where the fist is on an arm, in the arm's own frame.
const HAND := Vector3(0.0, -0.52, -0.02)

## How long each gesture lasts, in seconds. A swing is as long as the tool's
## cooldown.
const GESTURES := {
	&"swing": 0.45, &"pick_up": 0.45, &"throw": 0.45, &"drop": 0.35, &"use": 0.4,
	&"grab": 0.3, &"lever": 0.35, &"jump": 0.3, &"place": 0.5, &"remove": 0.6,
	&"tool": 0.35, &"stroke": 2.4, &"look": 2.6, &"stretch": 1.8, &"scratch": 1.7,
}
const FIDGETS: Array[StringName] = [&"stroke", &"look", &"stretch", &"scratch"]

var player          ## a Player, or an Avatar standing in for one
## From the co-op host: {held, drag: [x, y, z, kg], build, tool, g: [count, gesture]}.
var net_state: Dictionary = {}
## Off for a stand-in, whose fidgets come from the host like any gesture.
var fidgets: bool = true
## How many gestures have been played, and the last one, for the host to send.
var gesture_count: int = 0
var last_gesture: StringName = &""
var _net_count: int = -1
var _label: Label3D
var _shirt: Color = Color(0, 0, 0, 0)
var _display: String = ""
var model: Node3D
var _part := {}              ## name -> Node3D
var _rest := {}              ## name -> rest rotation (Euler)
var _now := {}               ## name -> current rotation (Euler), smoothed
var _rest_pos := {}          ## name -> where the pivot sits on its parent
var _root_now := Vector3.ZERO
var _meshes: Array[GeometryInstance3D] = []
var _tool: MeshInstance3D
var _tool_id: StringName = &"<none>"
var _shadow_only := false

var _t := 0.0
var _phase := 0.0            ## the walk cycle
var _gait := 0.0             ## 0 standing, 1 walking, more when sprinting
var _air := 0.0              ## seconds off the ground
var _fall := 0.0             ## the fastest fall this jump, for the landing
var _land := 0.0             ## the landing squash, decaying
var _steer := 0.0
var _mode: StringName = &"foot"
var _gesture: StringName = &""
var _g_t := 0.0
var _g_len := 1.0
var _still := 0.0            ## seconds stood still with nothing going on
var _next_fidget := 8.0

func _init(p = null) -> void:
	player = p
	name = "Avatar"

func _ready() -> void:
	var scene := load(MODEL) as PackedScene
	if scene != null:
		model = scene.instantiate() as Node3D
	else:
		# Not imported yet (a fresh checkout run without the editor): read the
		# file directly.
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(ProjectSettings.globalize_path(MODEL), state) == OK:
			model = doc.generate_scene(state) as Node3D
	if model == null:
		push_warning("PlayerAvatar: could not load %s" % MODEL)
		return
	add_child(model)
	for n in PARTS:
		var node := model.find_child(String(n), true, false) as Node3D
		if node != null:
			_part[n] = node
	# The arms and head hang off the torso, so bending at the waist takes
	# them with it.
	var torso := _part.get(&"Torso") as Node3D
	if torso != null:
		for n in [&"Arm_L", &"Arm_R", &"Head"]:
			var node := _part.get(n) as Node3D
			if node != null:
				node.reparent(torso, true)
	for n in _part:
		_rest[n] = (_part[n] as Node3D).rotation
		_rest_pos[n] = (_part[n] as Node3D).position
		_now[n] = _rest[n]
	for m in model.find_children("*", "GeometryInstance3D", true, false):
		_meshes.append(m as GeometryInstance3D)
	_tool = MeshInstance3D.new()
	_tool.name = "ToolInHand"
	_tool.visible = false
	var hand := _part.get(&"Hand_R") as Node3D
	var arm := _part.get(&"Arm_R") as Node3D
	if hand != null or arm != null:
		(hand if hand != null else arm).add_child(_tool)
		# Gripped near the bottom of the handle, pointing forward out of the
		# fist, blade leading the swing.
		var b := Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, PI * 0.5)
		_tool.transform = Transform3D(b, (GRIP if hand != null else HAND) + b * Vector3(0, -0.08, 0))
		_meshes.append(_tool)
	_next_fidget = randf_range(6.0, 11.0)
	_apply_identity()

## Co-op: their name over their head, and their colour on the shirt, so you
## can tell who is who.
func set_look(display: String, shirt: Color) -> void:
	_display = display
	_shirt = shirt
	if model != null:
		_apply_identity()

func _apply_identity() -> void:
	if _display == "" and _shirt.a == 0.0:
		return
	if _shirt.a > 0.0:
		for m in _meshes:
			var mi := m as MeshInstance3D
			if mi == null or mi.mesh == null or mi == _tool:
				continue
			for i in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(i) as BaseMaterial3D
				if mat == null:
					continue
				if mat.resource_name == "Plaid" or mat.resource_name == "PlaidDark":
					var tinted := mat.duplicate() as BaseMaterial3D
					tinted.albedo_color = _shirt if mat.resource_name == "Plaid" else _shirt.darkened(0.45)
					mi.set_surface_override_material(i, tinted)
	if _display != "":
		if _label == null:
			_label = Label3D.new()
			_label.name = "Name"
			_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_label.font_size = 40
			_label.pixel_size = 0.006
			_label.outline_size = 10
			_label.position = Vector3(0, 2.15, 0)
			add_child(_label)
		_label.text = _display
		_label.modulate = _shirt.lightened(0.3) if _shirt.a > 0.0 else Color.WHITE

## The host's word on what this player is doing (see net_state).
func apply_net_state(state: Dictionary) -> void:
	net_state = state
	var g: Array = state.get("g", [])
	if g.size() >= 2:
		var count := int(g[0])
		# The first word is where things stand, not something that just happened.
		if _net_count >= 0 and count != _net_count:
			play(StringName(g[1]))
		_net_count = count

## Starts a one-off move. Unknown names are ignored.
func play(kind: StringName) -> void:
	if not GESTURES.has(kind):
		return
	_gesture = kind
	gesture_count += 1
	last_gesture = kind
	_g_t = 0.0
	_g_len = float(GESTURES[kind])
	if kind == &"swing" and player != null:
		var def: Dictionary = player.selected_tool_def()
		_g_len = clampf(float(def.get("cooldown", 0.45)), 0.3, 0.75)
	if not kind in FIDGETS:
		_still = 0.0

## What the body is doing, for tests and the debug readout.
func mode() -> StringName:
	return _mode

func gesture() -> StringName:
	return _gesture

func ready_to_draw() -> bool:
	return model != null

func _process(delta: float) -> void:
	if model == null or player == null or not is_instance_valid(player):
		return
	delta = minf(delta, 0.1)
	_t += delta
	var m := _current_mode(delta)
	if m != _mode:
		if _mode == &"air" and m == &"foot":
			_land = clampf(_fall / 9.0, 0.25, 1.0)
		if m != &"air":
			_fall = 0.0
		_mode = m
	_place()
	_update_tool()
	_update_visibility()
	var pose := _base_pose(delta)
	_overlay_gesture(pose, delta)
	_blend(pose, delta)
	# Limp: the ragdoll has his body, head, arms and legs.
	var rd: Variant = player.get("ragdoll")
	if rd != null and is_instance_valid(rd):
		(rd as Ragdoll).pose_model()

# --- What he is doing --------------------------------------------------------

func _current_mode(delta: float) -> StringName:
	if _limp_body() != null:
		_air = 0.0
		return &"ragdoll"
	if player.driving():
		var r: VehicleRig = player.rig()
		if player.loader() != null or (r != null and r.operating):
			return &"operate"
		return &"drive"
	if _building():
		return &"build"
	if player.swimming():
		_air = 0.0
		return &"swim"
	if player.is_on_floor():
		_air = 0.0
		return &"foot"
	_air += delta
	# A step down a slope is not a jump.
	if _air < 0.12:
		return _mode if _mode == &"air" else &"foot"
	_fall = maxf(_fall, -player.velocity.y)
	return &"air"

## At the wheel he sits in the seat and turns with the vehicle; otherwise he
## stands where the player stands.
func _place() -> void:
	var body := _limp_body()
	if body != null:
		if player.get("ragdoll") != null:
			# The ragdoll places each part itself.
			return
		# Knocked flying as one capsule: he goes wherever it goes, head over
		# heels with it.
		global_transform = body.global_transform * Transform3D(Basis(), Vector3.DOWN * Player.TUMBLE_HIPS)
		return
	var v: Node3D = player.vehicle as Node3D if player.driving() else null
	if v != null and is_instance_valid(v) and v.has_method("seat_transform"):
		var b := v.global_transform.basis.orthonormalized()
		global_transform = Transform3D(b, v.global_transform * seat_hips(v))
	else:
		transform = Transform3D.IDENTITY

## Where he goes in a vehicle, in its own frame: the model's origin (his feet
## when standing), placed so his hips rest on the seat. The quad's seat is a
## pad over the tank, the buggy's a bucket seat on the left; a cab is a closed
## box, so in one he sits low enough to be all inside it.
static func seat_hips(v: Node3D) -> Vector3:
	var spec: Dictionary = v.get("spec") if v.get("spec") is Dictionary else {}
	var seat: Vector3 = Hauler._vec(spec.get("seat", [0, 1.0, 0]))
	var body: Vector3 = Hauler._vec(spec.get("body", [2.0, 0.5, 4.0]))
	var top := body.y * 0.5
	var hips: Vector3
	match String(spec.get("style", "truck")):
		"quad":
			# The seat pad's top (see VehicleModel._quad), plus the thighs under him.
			hips = Vector3(0, top + 0.20 + THIGH, 0.1)
		"buggy":
			hips = Vector3(-0.35, top + 0.15 + THIGH, 0.3)
		_:
			var cab: Dictionary = spec.get("cab", {})
			var roof := top + float(Hauler._vec(cab.get("size", [2.3, 0.95, 1.5])).y)
			hips = Vector3(seat.x, roof - SEATED_HEIGHT - 0.04, seat.z + 0.1)
	return hips - Vector3(0, HIP_HEIGHT, 0)

func _update_tool() -> void:
	var id: StringName = _selected_tool() if _mode in [&"foot", &"air"] else &""
	if id == _tool_id:
		return
	var was := _tool_id
	_tool_id = id
	_tool.visible = id != &""
	if id != &"":
		_tool.mesh = ToolModel.mesh(GameData.tool(id))
		if was != &"<none>":
			play(&"tool")

## Only the shadow in first person, on foot: the camera is inside his head.
func _update_visibility() -> void:
	var cam: Variant = player.camera
	var mine: bool = cam is Camera3D and (cam as Camera3D).current
	var shadow_only: bool = mine and not player.third_person and _mode in [&"foot", &"air", &"swim"]
	if shadow_only == _shadow_only:
		return
	_shadow_only = shadow_only
	for m in _meshes:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if shadow_only \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

# --- The base pose -------------------------------------------------------------

func _base_pose(delta: float) -> Dictionary:
	var p := {}
	for n in _rest:
		p[n] = _rest[n]
	p[&"root"] = Vector3.ZERO
	var breathe := sin(_t * 1.8)
	match _mode:
		&"drive", &"operate":
			_seated(p, delta)
		&"swim":
			_swimming(p)
		&"air":
			_airborne(p)
		&"build":
			_supervising(p)
		&"ragdoll":
			_limp(p)
		_:
			_walking(p, delta)
	if _mode != &"ragdoll":
		_joints(p)
	# Breathing, whatever else is going on: the belly rises, the arms drift.
	_add(p, &"Torso", Vector3(0.015 * breathe, 0, 0))
	_add(p, &"Arm_L", Vector3(0, 0, -0.03 * breathe))
	_add(p, &"Arm_R", Vector3(0, 0, 0.03 * breathe))
	p[&"root"] += Vector3(0, 0.006 * breathe, 0)
	# The landing squash.
	if _land > 0.0:
		_add(p, &"Torso", Vector3(-0.3 * _land, 0, 0))
		_add(p, &"Arm_L", Vector3(0.4 * _land, 0, -0.4 * _land))
		_add(p, &"Arm_R", Vector3(0.4 * _land, 0, 0.4 * _land))
		p[&"root"] += Vector3(0, -0.14 * _land, 0)
		_land = move_toward(_land, 0.0, delta * 3.5)
	# He looks where you look (a little: the body does the rest).
	if _mode in [&"foot", &"air", &"swim"]:
		var pitch: float = player.camera.rotation.x
		_add(p, &"Head", Vector3(clampf(pitch * 0.5, -0.45, 0.5), 0, 0))
	return p

func _walking(p: Dictionary, delta: float) -> void:
	var basis: Basis = player.global_transform.basis
	var vel: Vector3 = player.velocity
	var local := basis.inverse() * vel
	var speed := Vector2(local.x, local.z).length()
	_gait = move_toward(_gait, clampf(speed / 5.0, 0.0, 1.7), delta * 6.0)
	# Short legs, quick steps.
	_phase = fmod(_phase + delta * speed * 2.7, TAU)
	var back := -1.0 if local.z > 0.5 and absf(local.z) > absf(local.x) else 1.0
	var s := sin(_phase) * back
	var amp := 0.55 * minf(_gait, 1.3)
	_add(p, &"Leg_L", Vector3(amp * s, 0, 0))
	_add(p, &"Leg_R", Vector3(-amp * s, 0, 0))
	_add(p, &"Arm_L", Vector3(-amp * 0.9 * s, 0, 0))
	_add(p, &"Arm_R", Vector3(amp * 0.9 * s, 0, 0))
	_add(p, &"Torso", Vector3(-0.08 * _gait - 0.12 * maxf(0.0, _gait - 1.1), 0.12 * amp * s, 0))
	_add(p, &"Head", Vector3(0.06 * _gait, -0.08 * amp * s, 0))
	p[&"root"] += Vector3(0, 0.05 * _gait * absf(cos(_phase)), 0)
	var busy := false
	# Knee-deep: mittens held up out of the wet.
	var depth: float = player.water_depth()
	if depth > 0.45:
		p[&"Arm_L"] = Vector3(0.3, 0, -1.15)
		p[&"Arm_R"] = Vector3(0.3, 0, 1.15)
		busy = true
	var drag: Variant = _drag()
	if _carrying():
		# The load is carried across the chest, in both arms, leaning back.
		var sway := 0.08 * sin(_phase) * minf(_gait, 1.0)
		p[&"Arm_L"] = Vector3(1.25 + sway, 0, 0.2)
		p[&"Arm_R"] = Vector3(1.25 - sway, 0, -0.2)
		_add(p, &"Torso", Vector3(0.1, 0, 0))
		busy = true
	elif drag != null:
		# Reaching for the point he has hold of; both hands on anything heavy,
		# leaning back into it.
		var at: Vector3 = (drag as Array)[0]
		p[&"Arm_R"] = _reach(&"Arm_R", at)
		if float((drag as Array)[1]) > 30.0:
			p[&"Arm_L"] = _reach(&"Arm_L", at)
			_add(p, &"Torso", Vector3(0.18, 0, 0))
		busy = true
	elif _tool_id != &"":
		# Tool up and ready, over the shoulder.
		p[&"Arm_R"] = Vector3(0.55 + amp * 0.3 * s, 0, 0.1)
		busy = true
	# Stood about with nothing going on long enough, he fidgets.
	if fidgets and _gait < 0.05 and not busy and _gesture == &"":
		_still += delta
		if _still > _next_fidget:
			play(FIDGETS[randi() % FIDGETS.size()])
			_still = 0.0
			_next_fidget = randf_range(7.0, 14.0)
	else:
		_still = 0.0

func _airborne(p: Dictionary) -> void:
	p[&"Leg_L"] = _rest[&"Leg_L"] + Vector3(0.6, 0, 0)
	p[&"Leg_R"] = _rest[&"Leg_R"] + Vector3(-0.25, 0, 0)
	var flail := 0.0
	var vel: Vector3 = player.velocity
	if vel.y < -5.0:
		# A long drop: arms windmilling.
		flail = sin(_t * 18.0) * 0.5
	p[&"Arm_L"] = Vector3(0.3 + flail, 0, -1.3)
	p[&"Arm_R"] = Vector3(0.3 - flail, 0, 1.3)
	_add(p, &"Torso", Vector3(0.1, 0, 0))
	if _carrying():
		p[&"Arm_L"] = Vector3(1.25, 0, 0.2)
		p[&"Arm_R"] = Vector3(1.25, 0, -0.2)

## Elbows, knees and fingers, for whatever the body is doing. Elbows bend
## forward (+x), knees back (-x); a curl of 0 is an open hand, 1.5 a fist.
func _joints(p: Dictionary) -> void:
	var knee_l := 0.06
	var knee_r := 0.06
	var elbow_l := 0.22
	var elbow_r := 0.22
	var curl_l := 0.4
	var curl_r := 0.4
	var s := sin(_phase)
	var c := cos(_phase)
	match _mode:
		&"foot":
			# The leg coming through lifts its foot; sprinting, the arms pump
			# bent.
			var bend := 0.95 * minf(_gait, 1.4)
			knee_l += bend * maxf(0.0, c)
			knee_r += bend * maxf(0.0, -c)
			var pump := clampf(_gait - 0.7, 0.0, 1.0)
			elbow_l += 1.0 * pump + 0.15 * _gait
			elbow_r += 1.0 * pump + 0.15 * _gait
			# Each arm bends a little more as it swings forward.
			elbow_l += 0.3 * minf(_gait, 1.0) * maxf(0.0, -s)
			elbow_r += 0.3 * minf(_gait, 1.0) * maxf(0.0, s)
			curl_l += 0.6 * pump
			curl_r += 0.6 * pump
			# Stood still, he shifts his weight slowly from leg to leg.
			var idle := 1.0 - clampf(_gait * 4.0, 0.0, 1.0)
			var shift := sin(_t * 0.45)
			knee_l += 0.1 * idle * maxf(0.0, shift)
			knee_r += 0.1 * idle * maxf(0.0, -shift)
		&"air":
			knee_l = 0.9
			knee_r = 0.35
			elbow_l = 0.45
			elbow_r = 0.45
			curl_l = 0.1
			curl_r = 0.1
		&"swim":
			knee_l = 0.5 + 0.4 * s
			knee_r = 0.5 - 0.4 * s
			elbow_l = 0.6
			elbow_r = 0.6
			curl_l = 0.05
			curl_r = 0.05
		&"drive", &"operate":
			# Sat down: shins straight down from the seat, hands on the wheel
			# or the levers.
			knee_l = 1.5
			knee_r = 1.5
			elbow_l = 0.55
			elbow_r = 0.55
			curl_l = 1.35
			curl_r = 1.35
		&"build":
			elbow_r = 0.05
			curl_r = 0.7
	if _carrying():
		elbow_l = 0.55
		elbow_r = 0.55
		curl_l = 0.9
		curl_r = 0.9
	elif _drag() != null:
		elbow_l = 0.1
		elbow_r = 0.1
		curl_l = 1.3
		curl_r = 1.3
	elif _tool_id != &"":
		# The tool up over his shoulder, fist closed round the handle.
		elbow_r = 0.95
		curl_r = 1.45
	if _land > 0.0:
		knee_l += 1.0 * _land
		knee_r += 1.0 * _land
	# A swing winds the elbows up, then snaps them straight through the blow.
	if _gesture == &"swing":
		var k := _g_t / maxf(_g_len, 0.01)
		var wind := 1.3 * (1.0 - smoothstep(0.3, 0.5, k)) * smoothstep(0.0, 0.2, k)
		elbow_r += wind
		elbow_l += wind * 0.6
	elif _gesture == &"throw" or _gesture == &"pick_up":
		var k := _g_t / maxf(_g_len, 0.01)
		elbow_l += 0.8 * sin(k * PI)
		elbow_r += 0.8 * sin(k * PI)
	_bend(p, knee_l, knee_r, elbow_l, elbow_r, curl_l, curl_r)

func _bend(p: Dictionary, knee_l: float, knee_r: float, elbow_l: float, elbow_r: float, curl_l: float, curl_r: float) -> void:
	p[&"Knee_L"] = _rest.get(&"Knee_L", Vector3.ZERO) + Vector3(-knee_l, 0, 0)
	p[&"Knee_R"] = _rest.get(&"Knee_R", Vector3.ZERO) + Vector3(-knee_r, 0, 0)
	# The foot stays roughly level as the knee bends.
	p[&"Foot_L"] = _rest.get(&"Foot_L", Vector3.ZERO) + Vector3(knee_l * 0.35, 0, 0)
	p[&"Foot_R"] = _rest.get(&"Foot_R", Vector3.ZERO) + Vector3(knee_r * 0.35, 0, 0)
	p[&"Elbow_L"] = _rest.get(&"Elbow_L", Vector3.ZERO) + Vector3(elbow_l, 0, 0)
	p[&"Elbow_R"] = _rest.get(&"Elbow_R", Vector3.ZERO) + Vector3(elbow_r, 0, 0)
	_curl(p, &"L", curl_l)
	_curl(p, &"R", curl_r)

## Closes a hand: each finger rolls in at the knuckle and again halfway (the
## little finger most), the thumb folds across. The model's rest pose is a
## relaxed, half-open hand; a curl of about 1.3 on top of it is a fist.
func _curl(p: Dictionary, side: StringName, amount: float) -> void:
	var sign := FINGER_CURL_SIGN * (1.0 if side == &"L" else -1.0)
	var open := amount - REST_CURL
	for i in 4:
		var n := StringName("Finger_%s%d" % [side, i])
		var tip := StringName("FingerTip_%s%d" % [side, i])
		p[n] = _rest.get(n, Vector3.ZERO) + Vector3(0, 0, sign * open * (0.9 + 0.06 * float(i)))
		p[tip] = _rest.get(tip, Vector3.ZERO) + Vector3(0, 0, sign * open * 1.05)
	var t := StringName("Thumb_%s" % side)
	var tt := StringName("ThumbTip_%s" % side)
	p[t] = _rest.get(t, Vector3.ZERO) + Vector3(0.35 * open, 0, 0)
	p[tt] = _rest.get(tt, Vector3.ZERO) + Vector3(0.4 * open, 0, 0)

## How curled the fingers already are in the model as built.
const REST_CURL := 0.4

## Which way round the fingers turn to close toward the palm.
const FINGER_CURL_SIGN := 1.0

## A model pivot by name (for the ragdoll to build itself from).
func part(n: StringName) -> Node3D:
	return _part.get(n) as Node3D

## Back from being limp: the pose eases up from however he was lying.
var _recover := 0.0
func recover() -> void:
	for n in _part:
		var node := _part[n] as Node3D
		_now[n] = node.rotation
		# The ragdoll moved the pivots about; each goes back on its joint.
		node.position = _rest_pos[n]
	_recover = 0.7
	_mode = &"foot"

# --- His hat ---------------------------------------------------------------------

var _hat: RigidBody3D = null
var _hat_meshes: Array[Node3D] = []

## Knocked clean off: the beanie flies away on its own, to be found again
## when he gets up.
func lose_hat(fling: Vector3) -> void:
	if model == null or (_hat != null and is_instance_valid(_hat)):
		return
	_hat_meshes.clear()
	for n in model.find_children("Beanie*", "Node3D", true, false):
		if (n as Node3D).visible:
			_hat_meshes.append(n)
	if _hat_meshes.is_empty():
		return
	var world := player.get_parent() as Node3D if player != null else null
	if world == null:
		return
	var hat := RigidBody3D.new()
	hat.name = "Hat"
	hat.mass = 0.4
	hat.collision_layer = 0
	hat.collision_mask = Layers.WORLD | Layers.KERB | Layers.VEHICLE | Layers.LOOSE | Layers.MACHINE
	hat.angular_damp = 1.0
	world.add_child(hat)
	hat.global_transform = _hat_meshes[0].global_transform.orthonormalized()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.2, 0.38)
	cs.shape = box
	cs.position = Vector3(0, 0.02, 0)
	hat.add_child(cs)
	for m in _hat_meshes:
		var copy := m.duplicate() as Node3D
		hat.add_child(copy)
		copy.global_transform = m.global_transform
		m.visible = false
	hat.linear_velocity = fling
	hat.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-6, 6), randf_range(-9, 9))
	_hat = hat

## Back on his head.
func restore_hat() -> void:
	if _hat != null and is_instance_valid(_hat):
		_hat.queue_free()
	_hat = null
	for m in _hat_meshes:
		if is_instance_valid(m):
			m.visible = true
	_hat_meshes.clear()

func hat_off() -> bool:
	return _hat != null and is_instance_valid(_hat)

## The tumbling body he is flopping about on, or null.
func _limp_body() -> RigidBody3D:
	if player.has_method("knocked") and player.knocked():
		return player.tumble
	return null

## Limp: arms and legs flung out and flopping with the spin; hanging from a
## crane's grapple, arms up and legs dangling, kicking now and then.
func _limp(p: Dictionary) -> void:
	if player.get("ragdoll") != null:
		# The limbs are the ragdoll's; the hands hang open and floppy.
		var loose := 0.25 + 0.2 * sin(_t * 7.0)
		_curl(p, &"L", loose)
		_curl(p, &"R", 0.25 + 0.2 * sin(_t * 6.1 + 1.0))
		return
	var body := _limp_body()
	var spin := body.angular_velocity.length() + body.linear_velocity.length() * 0.3 if body != null else 0.0
	var flop := sin(_t * 11.0) * clampf(spin * 0.06, 0.05, 0.7)
	var flop2 := sin(_t * 8.3 + 1.7) * clampf(spin * 0.06, 0.05, 0.7)
	if bool(player.get("crane_hold")):
		p[&"Arm_L"] = Vector3(-2.7 + flop * 0.3, 0, -0.35)
		p[&"Arm_R"] = Vector3(-2.7 - flop * 0.3, 0, 0.35)
		p[&"Leg_L"] = _rest[&"Leg_L"] + Vector3(0.35 * sin(_t * 6.0), 0, 0)
		p[&"Leg_R"] = _rest[&"Leg_R"] + Vector3(-0.35 * sin(_t * 6.0), 0, 0)
		_add(p, &"Head", Vector3(0.25, 0, 0))
		return
	p[&"Arm_L"] = Vector3(-0.5 + flop, 0.3, -1.5 + flop2 * 0.5)
	p[&"Arm_R"] = Vector3(-0.5 - flop2, -0.3, 1.5 + flop * 0.5)
	p[&"Leg_L"] = _rest[&"Leg_L"] + Vector3(0.45 + flop * 0.6, 0, -0.35)
	p[&"Leg_R"] = _rest[&"Leg_R"] + Vector3(-0.3 - flop2 * 0.6, 0, 0.35)
	_add(p, &"Torso", Vector3(0.15, 0, 0))
	_add(p, &"Head", Vector3(0.35 * sin(_t * 5.0), 0.3 * flop2, 0))

func _swimming(p: Dictionary) -> void:
	# A doggy paddle, head held up out of the water.
	var a := _t * 7.0
	_add(p, &"Torso", Vector3(-0.45, 0, 0))
	p[&"Arm_L"] = Vector3(1.6 + 0.7 * sin(a), 0, 0.15)
	p[&"Arm_R"] = Vector3(1.6 + 0.7 * sin(a + PI), 0, -0.15)
	_add(p, &"Leg_L", Vector3(0.35 * sin(a * 1.3), 0, 0))
	_add(p, &"Leg_R", Vector3(0.35 * sin(a * 1.3 + PI), 0, 0))
	_add(p, &"Head", Vector3(0.45, 0, 0))
	p[&"root"] += Vector3(0, 0.05 * sin(_t * 3.0), 0)

func _seated(p: Dictionary, delta: float) -> void:
	p[&"Leg_L"] = _rest[&"Leg_L"] + Vector3(1.45, 0, -0.12)
	p[&"Leg_R"] = _rest[&"Leg_R"] + Vector3(1.45, 0, 0.12)
	if _mode == &"drive":
		# Hands on the wheel; it turns as he steers, and he leans into it.
		_steer = move_toward(_steer, _axis(&"move_left", &"move_right"), delta * 4.0)
		var throttle := _axis(&"move_back", &"move_forward")
		p[&"Arm_L"] = Vector3(1.05 - 0.3 * _steer, 0, 0.25)
		p[&"Arm_R"] = Vector3(1.05 + 0.3 * _steer, 0, -0.25)
		_add(p, &"Torso", Vector3(-0.06 * throttle, 0, -0.1 * _steer))
		_add(p, &"Head", Vector3(0, -0.3 * _steer, 0))
		return
	# Working levers: each hand jiggles with the keys it is on, and he watches
	# the log (or the bucket).
	var along := _axis(&"move_back", &"move_forward")
	var across := _axis(&"move_left", &"move_right")
	var lift := _axis(&"lower", &"sprint")
	var twist := _axis(&"turn_ccw", &"turn_cw")
	p[&"Arm_L"] = Vector3(0.85 + 0.25 * along, 0, 0.15 + 0.15 * across)
	p[&"Arm_R"] = Vector3(0.85 + 0.25 * lift, 0, -0.15 + 0.15 * twist)
	var r: VehicleRig = player.rig()
	if r != null and r.operating:
		p[&"Head"] = _look(r.focus_point(), 0.8)

## In build mode the body stays put: one hand on his hip, the other pointing at
## where you are looking, head following it, one foot tapping.
func _supervising(p: Dictionary) -> void:
	var cam: Node3D = player.camera
	var at := cam.global_position - cam.global_transform.basis.z * 10.0
	p[&"Arm_R"] = _reach(&"Arm_R", at)
	p[&"Arm_L"] = Vector3(-0.35, 0, -0.65)
	p[&"Head"] = _look(at, 0.7)
	_add(p, &"Leg_L", Vector3(0.14 * maxf(0.0, sin(_t * 7.0)) * float(fmod(_t, 4.0) < 2.0), 0, 0))

# --- What the host says, or what this machine can see -----------------------

func _carrying() -> bool:
	if net_state.has("held"):
		return int(net_state.held) > 0
	var held: Array = player.held
	return not held.is_empty()

## [grabbed point, mass] while dragging something, else null.
func _drag() -> Variant:
	if net_state.has("held"):
		var d: Array = net_state.get("drag", [])
		return [Vector3(d[0], d[1], d[2]), float(d[3])] if d.size() >= 4 else null
	var item: Variant = player.dragged
	if item == null or not is_instance_valid(item):
		return null
	return [player.drag_point(), float(item.mass)]

func _building() -> bool:
	if net_state.has("build"):
		return bool(net_state.build)
	var bs: Variant = player.build_system
	return bs != null and bool(bs.active)

func _selected_tool() -> StringName:
	if net_state.has("tool"):
		return StringName(net_state.tool)
	return player.selected_tool()

## A pair of keys as -1..1, from whoever is at this player's keys.
func _axis(negative: StringName, positive: StringName) -> float:
	var input: Variant = player.get("input")
	if input != null:
		return float(input.axis(negative, positive))
	return 0.0

## The head turned to look at a world point (as far as a neck goes).
func _look(at: Vector3, up_limit: float) -> Vector3:
	var head := _part.get(&"Head") as Node3D
	if head == null:
		return Vector3.ZERO
	var parent := head.get_parent() as Node3D
	var to := parent.global_transform.basis.orthonormalized().inverse() * (at - head.global_position)
	return Vector3(clampf(atan2(to.y, Vector2(to.x, to.z).length()), -0.6, up_limit),
		clampf(atan2(-to.x, -to.z), -1.2, 1.2), 0)

## The rotation that points an arm (hanging down at rest) at a world point.
func _reach(arm_name: StringName, at: Vector3) -> Vector3:
	var arm := _part.get(arm_name) as Node3D
	if arm == null:
		return Vector3.ZERO
	var parent := arm.get_parent() as Node3D
	var d := parent.global_transform.basis.orthonormalized().inverse() * (at - arm.global_position)
	if d.length_squared() < 0.0001:
		return _rest[arm_name]
	d = d.normalized()
	# Not straight up: past that the shoulder would flip over.
	d.y = minf(d.y, 0.94)
	d = d.normalized()
	return Basis(Quaternion(Vector3.DOWN, d)).get_euler()

# --- Gestures --------------------------------------------------------------------

func _overlay_gesture(p: Dictionary, delta: float) -> void:
	if _gesture == &"":
		return
	_g_t += delta
	var u := clampf(_g_t / _g_len, 0.0, 1.0)
	var g := p.duplicate()
	var w := sin(PI * u)                  # in and out
	var hold := _ease_hold(u)             # in, hold, out
	match _gesture:
		&"swing":
			var def: Dictionary = player.selected_tool_def()
			var hammer := String(def.get("kind", "axe")) == "hammer"
			# Up over the head, down hard, back to ready.
			var arm := _keys(u, [[0.0, 0.55], [0.38, 2.75], [0.55 if hammer else 0.6, -0.05], [1.0, 0.55]])
			var lean := _keys(u, [[0.0, 0.0], [0.38, 0.18], [0.6, -0.32], [1.0, 0.0]])
			g[&"Arm_R"] = Vector3(arm, 0, 0.05)
			g[&"Arm_L"] = Vector3(arm - 0.1, 0, 0.35)
			g[&"Torso"] = _rest[&"Torso"] + Vector3(lean, 0, 0)
			g[&"root"] = p[&"root"] + Vector3(0, -0.05 * maxf(0.0, -lean) / 0.32, 0)
			w = hold
		&"pick_up":
			g[&"Torso"] = _rest[&"Torso"] + Vector3(-0.75, 0, 0)
			g[&"Arm_L"] = Vector3(0.9, 0, 0.2)
			g[&"Arm_R"] = Vector3(0.9, 0, -0.2)
			g[&"Head"] = _rest[&"Head"] + Vector3(0.3, 0, 0)
			g[&"root"] = p[&"root"] + Vector3(0, -0.12, 0)
		&"throw":
			var arm := _keys(u, [[0.0, 1.0], [0.35, -0.9], [0.55, 2.4], [1.0, 1.2]])
			var twist := _keys(u, [[0.0, 0.0], [0.35, 0.4], [0.55, -0.35], [1.0, 0.0]])
			g[&"Arm_R"] = Vector3(arm, 0, 0.2)
			g[&"Arm_L"] = Vector3(0.6, 0, -0.5)
			g[&"Torso"] = _rest[&"Torso"] + Vector3(-0.1, twist, 0)
			w = hold
		&"drop":
			g[&"Arm_L"] = Vector3(0.9, 0, -0.6)
			g[&"Arm_R"] = Vector3(0.9, 0, 0.6)
			g[&"Torso"] = _rest[&"Torso"] + Vector3(-0.15, 0, 0)
		&"use":
			g[&"Arm_R"] = Vector3(1.45, 0, -0.1)
			g[&"Head"] = _rest[&"Head"] + Vector3(-0.2, 0, 0)
		&"grab":
			g[&"Arm_R"] = Vector3(1.6, 0, 0)
			g[&"Torso"] = _rest[&"Torso"] + Vector3(-0.2, 0, 0)
		&"lever":
			g[&"Arm_R"] = Vector3(_keys(u, [[0.0, 1.0], [0.3, 1.35], [0.7, 0.45], [1.0, 0.9]]), 0, -0.2)
			g[&"Torso"] = p[&"Torso"] + Vector3(0.12, 0, 0)
			w = hold
		&"jump":
			g[&"Arm_L"] = Vector3(0.9, 0, -0.9)
			g[&"Arm_R"] = Vector3(0.9, 0, 0.9)
		&"place":
			# A fist pump and a little hop.
			g[&"Arm_R"] = Vector3(_keys(u, [[0.0, 1.0], [0.3, 2.9], [0.5, 2.3], [0.7, 2.9], [1.0, 1.0]]), 0, -0.1)
			g[&"Head"] = _rest[&"Head"] + Vector3(0.2, 0, 0)
			g[&"root"] = p[&"root"] + Vector3(0, 0.06 * sin(PI * clampf(u * 2.0, 0.0, 1.0)), 0)
			w = hold
		&"remove":
			# Shakes his head at it.
			g[&"Head"] = p[&"Head"] + Vector3(-0.1, 0.4 * sin(u * TAU * 2.0), 0)
			g[&"Arm_R"] = Vector3(0.9, 0, -0.3)
		&"tool":
			g[&"Arm_R"] = Vector3(_keys(u, [[0.0, 0.2], [0.45, 2.3], [1.0, 0.55]]), 0, 0.1)
			w = hold
		&"stroke":
			# Strokes the beard, chin up, very pleased with it.
			g[&"Arm_L"] = Vector3(1.85 + 0.14 * sin(_t * 9.0), 0, 0.6)
			g[&"Head"] = _rest[&"Head"] + Vector3(0.22, 0.1, 0)
			w = hold
		&"look":
			g[&"Head"] = _rest[&"Head"] + Vector3(0.05, 0.8 * sin(u * TAU), 0)
			g[&"Torso"] = _rest[&"Torso"] + Vector3(0, 0.15 * sin(u * TAU), 0)
			w = hold
		&"stretch":
			g[&"Arm_L"] = Vector3(0.2, 0, -2.7)
			g[&"Arm_R"] = Vector3(0.2, 0, 2.7)
			g[&"Torso"] = _rest[&"Torso"] + Vector3(0.22, 0, 0)
			g[&"Head"] = _rest[&"Head"] + Vector3(0.35, 0, 0)
			g[&"root"] = p[&"root"] + Vector3(0, 0.04, 0)
			w = hold
		&"scratch":
			g[&"Arm_R"] = Vector3(2.75 + 0.15 * sin(_t * 16.0), 0, -0.55)
			g[&"Head"] = _rest[&"Head"] + Vector3(-0.1, 0, -0.2)
			w = hold
	for k in p:
		if g.has(k):
			p[k] = (p[k] as Vector3).lerp(g[k], w)
	if u >= 1.0:
		_gesture = &""

## Linear through a list of [time, value] keys, time 0..1.
static func _keys(u: float, keys: Array) -> float:
	for i in range(1, keys.size()):
		var a: Array = keys[i - 1]
		var b: Array = keys[i]
		if u <= float(b[0]):
			var span := maxf(0.0001, float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), smoothstep(0.0, 1.0, (u - float(a[0])) / span))
	return float((keys[keys.size() - 1] as Array)[1])

## 0 -> 1 quickly, held, then back to 0 at the end.
static func _ease_hold(u: float) -> float:
	return smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.85, 1.0, u))

static func _add(p: Dictionary, n: StringName, v: Vector3) -> void:
	if p.has(n):
		p[n] = (p[n] as Vector3) + v

func _blend(p: Dictionary, delta: float) -> void:
	# Quick enough that a chop lands, soft enough that changes of pose flow.
	var rate := 30.0 if _gesture != &"" else 14.0
	if _recover > 0.0:
		# Getting up: slower, so he visibly picks himself up.
		_recover = maxf(0.0, _recover - delta)
		rate = 5.0
	var k := 1.0 - exp(-rate * delta)
	for n in _part:
		_now[n] = (_now[n] as Vector3).lerp(p.get(n, _rest[n]), k)
		(_part[n] as Node3D).rotation = _now[n]
	_root_now = _root_now.lerp(p[&"root"], k)
	model.position = _root_now
