class_name NpcFigure
extends Node3D

## The people you trade with: one of the models in assets/models/npc_*.glb
## (built in Blender by source/npc_build.py, with the same pivots as the
## lumberjack), posed in code every frame the way the player's avatar is.
##
##   GRANNY      rocks in her chair all day, knitting, nodding off now and
##               then, and looks up when you come by
##   MINER       swings his pickaxe at his rock, paces about, then leans on
##               the pick for a breather and wipes his brow
##   LUMBERMAN   the same with his axe and his tree - and if you fell his
##               tree for him, he lets you know what he thinks of that
##   HELPER      the short fellow at a shop who carries your order out to the
##               loading bay; stands about whistling in between
##   SHOPKEEP    the helper model behind a yard's counter, waving you in
##
## He is a model and a body to aim at: whatever owns him (a yard, a counter)
## does the trading. He says things in a bubble over his head (`say`).

enum Role { GRANNY, MINER, LUMBERMAN, HELPER, SHOPKEEP }

const MODELS := {
	Role.GRANNY: "res://assets/models/npc_granny.glb",
	Role.MINER: "res://assets/models/npc_miner.glb",
	Role.LUMBERMAN: "res://assets/models/npc_lumberman.glb",
	Role.HELPER: "res://assets/models/npc_helper.glb",
	Role.SHOPKEEP: "res://assets/models/npc_helper.glb",
}
## How tall each is to the top of the head (for the bubble and the body).
const HEIGHT := {Role.GRANNY: 1.5, Role.MINER: 2.0, Role.LUMBERMAN: 2.15, Role.HELPER: 1.45, Role.SHOPKEEP: 1.45}
const PARTS := PlayerAvatar.PARTS
## Where a tool's grip sits in the right hand, and how it is held: the same
## as the lumberjack's.
const GRIP := Vector3(0.0, -0.09, 0.0)
const REST_CURL := 0.4

## What the lumberman shouts when you fell his tree.
const GRUMBLES := [
	"Oi! I didn't need your help!",
	"That was MY tree!",
	"Forty years I've been working that one!",
	"Go and chop your own!",
	"Un-be-lievable.",
	"I had a system going there!",
	"Well, don't just stand there. Take it, then.",
]
const GRANNY_HELLOS := ["Hello, dearie!", "Brought me something shiny?", "Mind the cat.",
	"Ooh, what have you got there?", "You look peaky. Have a biscuit."]
const MINER_LINES := ["Rock won't break itself.", "Mind your toes.", "Good seam, this one.",
	"Bring me ore, I'll pay fair."]
const LUMBER_LINES := ["Timber!", "Put your back into it.", "Good wood round here.",
	"Bring me logs, I'll pay fair."]

signal struck(at: Vector3)

var role: Role = Role.HELPER
## Shown in the bubble's name and in prompts.
var display_name: String = ""
## Ground height under a world point (x, z), for walking. Unset: level.
var ground: Callable
## The player (or anyone) he looks at and talks to when they come close.
var watch: Callable
## For figures nobody gave a `watch`: the world sets this to the player.
static var default_watch: Callable
## Works nowhere: a trader at a counter, leaning on his tool all day.
var stationary: bool = false
## The miner's rock or the lumberman's tree, in the parent's frame: he
## faces it and swings at it. Set by whoever places him.
var work_at: Vector3 = Vector3.ZERO
## Where he stands to work, and where he paces to and back (parent's frame).
var post: Vector3 = Vector3.ZERO
var pace_to: Vector3 = Vector3.ZERO
## False while the thing he works at is not there (a felled tree).
var has_work: bool = true

var model: Node3D
var body: StaticBody3D
var _part := {}
var _rest := {}
var _now := {}
var _tool: Node3D
var _chair: Node3D
var _rocker: Node3D
var _figure: Node3D
var _bubble: Label3D
var _bubble_t := 0.0
var _carry: Node3D

var _t := 0.0
var state: StringName = &"idle"
var _state_t := 0.0
var _state_len := 5.0
var _swings := 0
var _phase := 0.0
var _walk_to: Vector3 = Vector3.INF
var _walk_then: StringName = &""
var _turn := 0.0
var _heading := 0.0
var _chat_cd := 0.0
var _awake := true
var _wake_t := 0.0

func _init(p_role: Role = Role.HELPER, p_name: String = "") -> void:
	role = p_role
	display_name = p_name
	name = "Npc_%s" % Role.keys()[role].capitalize()

func _ready() -> void:
	_load_model()
	body = StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = Layers.MACHINE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	var h: float = HEIGHT[role]
	cap.radius = 0.45 if role != Role.HELPER and role != Role.SHOPKEEP else 0.38
	cap.height = h
	cs.shape = cap
	cs.position = Vector3(0, h * 0.5, 0)
	body.add_child(cs)
	add_child(body)
	_bubble = Label3D.new()
	_bubble.name = "Bubble"
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.font = UITheme.display_font()
	_bubble.font_size = 56
	_bubble.pixel_size = 0.0045
	_bubble.outline_size = 14
	_bubble.outline_modulate = Color(0.08, 0.07, 0.06)
	_bubble.modulate = Color(1.0, 0.97, 0.88)
	_bubble.position = Vector3(0, float(HEIGHT[role]) + 0.45, 0)
	_bubble.no_depth_test = true
	_bubble.visible = false
	add_child(_bubble)
	_heading = rotation.y
	_start(_first_state())
	_wake_t = randf() * 0.5

func _first_state() -> StringName:
	if stationary and (role == Role.MINER or role == Role.LUMBERMAN):
		return &"rest"
	match role:
		Role.GRANNY:
			return &"rock"
		Role.MINER, Role.LUMBERMAN:
			return &"work"
	return &"idle"

func _load_model() -> void:
	var path: String = MODELS[role]
	var scene := load(path) as PackedScene
	if scene != null:
		model = scene.instantiate() as Node3D
	else:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(ProjectSettings.globalize_path(path), st) == OK:
			model = doc.generate_scene(st) as Node3D
	if model == null:
		push_warning("NpcFigure: could not load %s" % path)
		return
	model.name = "Model"
	_rocker = Node3D.new()
	_rocker.name = "Rocker"
	add_child(_rocker)
	_rocker.add_child(model)
	# The person is the node with the pivots under it; the props are beside.
	for c in model.get_children():
		if c.find_child("Torso", true, false) != null or c.name == "Torso":
			_figure = c as Node3D
	for n in PARTS:
		var node := model.find_child(String(n), true, false) as Node3D
		if node != null:
			_part[n] = node
	var torso := _part.get(&"Torso") as Node3D
	if torso != null:
		for n in [&"Arm_L", &"Arm_R", &"Head"]:
			var node := _part.get(n) as Node3D
			if node != null:
				node.reparent(torso, true)
	for n in _part:
		_rest[n] = (_part[n] as Node3D).rotation
		_now[n] = _rest[n]
	# The tool goes in his right hand, held as the lumberjack holds his.
	for tool_name in ["Pickaxe", "Axe"]:
		var t := model.find_child(tool_name, true, false) as Node3D
		if t != null:
			_tool = t
			_to_hand()
	_chair = model.find_child("RockingChair", true, false) as Node3D
	if _chair != null and _figure != null:
		# Sat in the chair: hips on the cushion, her knitting in her hands.
		_figure.position = Vector3(0, 0.024, -0.05)
		_knitting()

## A scarf coming off her needles, in her left hand; the needles cross it.
func _knitting() -> void:
	var hand := _part.get(&"Hand_L") as Node3D
	if hand == null:
		return
	var g := Greeble.new()
	var yarn := Color(0.3, 0.55, 0.8)
	g.box(Vector3(0.2, 0.03, 0.16), Transform3D(Basis(), Vector3(-0.08, -0.16, -0.04)), yarn)
	g.box(Vector3(0.18, 0.025, 0.2), Transform3D(Basis(Vector3.RIGHT, 0.9), Vector3(-0.08, -0.25, 0.02)), yarn.darkened(0.15))
	for k in [-1.0, 1.0]:
		g.box(Vector3(0.012, 0.012, 0.34), Transform3D(Basis(Vector3.UP, 0.5 * k), Vector3(-0.08 + 0.04 * k, -0.14, -0.04)), Color(0.85, 0.8, 0.7))
	hand.add_child(g.instance("Knitting"))

func _to_hand() -> void:
	var hand := _part.get(&"Hand_R") as Node3D
	if _tool == null or hand == null:
		return
	if _tool.get_parent() != hand:
		_tool.reparent(hand, false)
	var b := Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, PI * 0.5)
	_tool.transform = Transform3D(b, GRIP + b * Vector3(0, -0.08, 0))
	# The model's own scale is on the figure, not the hand.
	_tool.scale = Vector3.ONE

## The tool stood on its head in front of him, handle up, for him to lean on.
func _to_ground() -> void:
	if _tool == null or _figure == null:
		return
	if _tool.get_parent() != _figure:
		_tool.reparent(_figure, false)
	_tool.transform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0.05, 0.86, -0.46))

# --- Talking ---------------------------------------------------------------------

func say(text: String, seconds: float = 3.5) -> void:
	if _bubble == null:
		return
	_bubble.text = text
	_bubble.visible = true
	_bubble.modulate.a = 1.0
	_bubble.outline_modulate.a = 1.0
	_bubble_t = seconds

func saying() -> String:
	return _bubble.text if _bubble != null and _bubble.visible else ""

# --- Orders from outside -----------------------------------------------------------

## His tree has been felled (by someone else): he is not happy about it.
func tree_felled() -> void:
	has_work = false
	if role != Role.LUMBERMAN:
		return
	_to_hand()
	say(GRUMBLES[randi() % GRUMBLES.size()], 4.5)
	_start(&"angry")

## A new tree has grown in: back to work.
func tree_back() -> void:
	has_work = true
	if role == Role.LUMBERMAN and state in [&"sulk", &"angry"]:
		say("Right. Back to it.", 3.0)
		_start(&"work")

## The helper: walk to `where` (parent's frame), then do `then`.
func walk(where: Vector3, then: StringName = &"idle") -> void:
	_walk_to = where
	_walk_then = then
	_start(&"walk")

func walking() -> bool:
	return state == &"walk"

## The helper: something in his arms (a stack), or nothing.
func hold(stack: Node3D) -> void:
	if _carry != null and is_instance_valid(_carry):
		_carry.queue_free()
	_carry = stack
	if stack != null and _figure != null:
		_figure.add_child(stack)
		# Real size, whatever the model's own scale.
		var sc := _figure.scale.x if _figure.scale.x > 0.01 else 1.0
		stack.scale = Vector3.ONE / sc
		stack.position = Vector3(0, 0.62 / sc + 0.15, -0.45 / sc)

func holding() -> bool:
	return _carry != null and is_instance_valid(_carry)

## A short cheer or wave, over whatever else he is doing.
func gesture(kind: StringName) -> void:
	_gesture = kind
	_gesture_t = 0.0

var _gesture: StringName = &""
var _gesture_t := 0.0

# --- The day -------------------------------------------------------------------------

func _start(s: StringName) -> void:
	state = s
	_state_t = 0.0
	match s:
		&"work":
			_to_hand()
			_swings = 0
			_state_len = randf_range(9.0, 15.0)
		&"pace":
			_to_hand()
			_phase_out = true
			_state_len = 60.0
		&"rest":
			_to_ground()
			_state_len = randf_range(6.0, 10.0)
		&"angry":
			_state_len = 4.0
		&"sulk":
			_state_len = 1e9
		&"idle":
			_state_len = randf_range(4.0, 9.0)
		&"rock":
			_state_len = randf_range(14.0, 30.0)
		&"doze":
			_state_len = randf_range(6.0, 10.0)
			say("Zzz...", _state_len)

func _process(delta: float) -> void:
	if model == null:
		return
	delta = minf(delta, 0.1)
	# Far from everyone he stops moving: nobody is there to see.
	_wake_t -= delta
	if _wake_t <= 0.0:
		_wake_t = 1.0
		_awake = _someone_within(140.0)
	if not _awake:
		return
	_t += delta
	_state_t += delta
	_chat_cd = maxf(0.0, _chat_cd - delta)
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t < 0.6:
			_bubble.modulate.a = maxf(0.0, _bubble_t / 0.6)
			_bubble.outline_modulate.a = _bubble.modulate.a
		if _bubble_t <= 0.0:
			_bubble.visible = false
	var p := {}
	for n in _rest:
		p[n] = _rest[n]
	p[&"root"] = Vector3.ZERO
	p[&"rock"] = 0.0
	match state:
		&"rock", &"doze":
			_rocking(p, delta)
		&"work":
			_working(p, delta)
		&"pace":
			_pacing(p, delta)
		&"rest":
			_resting(p)
		&"angry":
			_angry(p)
		&"sulk":
			_sulking(p)
		&"walk":
			_walking(p, delta)
		_:
			_idling(p)
	_overlay(p, delta)
	_apply(p, delta)
	_chat()

## Whoever he watches (the player), or null.
func _watcher() -> Variant:
	var w := watch if watch.is_valid() else default_watch
	if not w.is_valid():
		return null
	var who: Variant = w.call()
	return who if who is Node3D and is_instance_valid(who) else null

func _someone_within(reach: float) -> bool:
	var who: Variant = _watcher()
	if who == null:
		return true
	return who is Node3D and (who as Node3D).global_position.distance_to(global_position) < reach

## Says hello (or something like it) now and then when you come close.
func _chat() -> void:
	if _chat_cd > 0.0 or state in [&"angry", &"doze"]:
		return
	var who: Variant = _watcher()
	if not (who is Node3D):
		return
	var d := (who as Node3D).global_position.distance_to(global_position)
	if d < 7.0:
		_chat_cd = randf_range(25.0, 45.0)
		match role:
			Role.GRANNY:
				say(GRANNY_HELLOS[randi() % GRANNY_HELLOS.size()])
			Role.MINER:
				say(MINER_LINES[randi() % MINER_LINES.size()])
			Role.LUMBERMAN:
				if has_work:
					say(LUMBER_LINES[randi() % LUMBER_LINES.size()])
			Role.SHOPKEEP:
				say("Howdy! Bring it in the yard.")
				gesture(&"wave")

# --- Poses -----------------------------------------------------------------------

func _add(p: Dictionary, n: StringName, v: Vector3) -> void:
	if p.has(n):
		p[n] = (p[n] as Vector3) + v

func _put(p: Dictionary, n: StringName, v: Vector3) -> void:
	if _rest.has(n):
		p[n] = v

## Linear keys: [[u, value], ...] with u rising 0..1.
static func _keys(u: float, keys: Array) -> float:
	if u <= float(keys[0][0]):
		return float(keys[0][1])
	for i in range(1, keys.size()):
		var a: Array = keys[i - 1]
		var b: Array = keys[i]
		if u <= float(b[0]):
			var f := (u - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), smoothstep(0.0, 1.0, f))
	return float(keys[keys.size() - 1][1])

func _bend(p: Dictionary, knee_l: float, knee_r: float, elbow_l: float, elbow_r: float, curl_l: float, curl_r: float) -> void:
	p[&"Knee_L"] = _rest.get(&"Knee_L", Vector3.ZERO) + Vector3(-knee_l, 0, 0)
	p[&"Knee_R"] = _rest.get(&"Knee_R", Vector3.ZERO) + Vector3(-knee_r, 0, 0)
	p[&"Foot_L"] = _rest.get(&"Foot_L", Vector3.ZERO) + Vector3(knee_l * 0.35, 0, 0)
	p[&"Foot_R"] = _rest.get(&"Foot_R", Vector3.ZERO) + Vector3(knee_r * 0.35, 0, 0)
	p[&"Elbow_L"] = _rest.get(&"Elbow_L", Vector3.ZERO) + Vector3(elbow_l, 0, 0)
	p[&"Elbow_R"] = _rest.get(&"Elbow_R", Vector3.ZERO) + Vector3(elbow_r, 0, 0)
	_curl(p, &"L", curl_l)
	_curl(p, &"R", curl_r)

func _curl(p: Dictionary, side: StringName, amount: float) -> void:
	var sign := 1.0 if side == &"L" else -1.0
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

func _breathe(p: Dictionary, rate: float = 1.8) -> void:
	var b := sin(_t * rate)
	_add(p, &"Torso", Vector3(0.015 * b, 0, 0))
	_add(p, &"Arm_L", Vector3(0, 0, -0.025 * b))
	_add(p, &"Arm_R", Vector3(0, 0, 0.025 * b))

## Turns the whole figure to face a point (parent's frame), smoothly.
func _face(at: Vector3, delta: float, rate: float = 5.0) -> void:
	var d := at - position
	if Vector2(d.x, d.z).length() < 0.05:
		return
	var want := atan2(-d.x, -d.z)
	rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-rate * delta))

## Head turned toward whoever is watching, if they are close and in front.
func _look_round(p: Dictionary, most: float = 0.9) -> void:
	var who: Variant = _watcher()
	if not (who is Node3D):
		return
	var here := global_transform
	var local := here.affine_inverse() * (who as Node3D).global_position
	if local.length() > 12.0:
		return
	var yaw := atan2(-local.x, -local.z)
	if absf(yaw) > 2.0:
		return
	_add(p, &"Head", Vector3(0.08, clampf(yaw, -most, most), 0))

# Granny: rocking and knitting, dozing off, looking up at visitors.
func _rocking(p: Dictionary, delta: float) -> void:
	var rock := sin(_t * 1.5)
	p[&"rock"] = 0.09 * rock
	for s in [&"L", &"R"]:
		_put(p, StringName("Leg_%s" % s), Vector3(1.45, 0, 0))
	_put(p, &"Torso", Vector3(-0.08, 0, 0))
	_put(p, &"Arm_L", Vector3(0.7, 0, 0.42))
	_put(p, &"Arm_R", Vector3(0.7, 0, -0.42))
	var knit := sin(_t * 7.0)
	var elbow := 0.95
	var curl := 1.1
	if state == &"doze":
		# Chin on her chest, hands still in her lap.
		_add(p, &"Head", Vector3(-0.45, 0, 0.08 * sin(_t * 0.8)))
		knit = 0.0
		elbow = 0.7
		curl = 0.8
		if _state_t > _state_len:
			say("Hm? Oh!", 2.0)
			_start(&"rock")
	else:
		_add(p, &"Head", Vector3(-0.12 - 0.04 * rock, 0, 0))
		_look_round(p, 0.7)
		if _state_t > _state_len:
			_start(&"doze")
	_bend(p, 0.0, 0.0, elbow + 0.12 * knit, elbow - 0.12 * knit, curl, curl)
	p[&"Knee_L"] = _rest.get(&"Knee_L", Vector3.ZERO) + Vector3(-1.35 - 0.05 * rock, 0, 0)
	p[&"Knee_R"] = _rest.get(&"Knee_R", Vector3.ZERO) + Vector3(-1.35 - 0.05 * rock, 0, 0)
	_breathe(p, 1.3)

# The miner and the lumberman at their work.
func _working(p: Dictionary, delta: float) -> void:
	if not has_work:
		_start(&"sulk" if role == Role.LUMBERMAN else &"pace")
		return
	# At his spot, facing what he works at.
	position = position.move_toward(_on_ground(post), delta * 1.5)
	_face(work_at, delta)
	var period := 1.7 if role == Role.MINER else 1.5
	var u := fmod(_state_t, period) / period
	var before := fmod(_state_t - delta, period) / period
	var strike := 0.5
	if before < strike and u >= strike:
		_swings += 1
		var at := global_transform * Vector3(0, 0.4 if role == Role.MINER else 1.0, -1.0)
		struck.emit(at)
		Sfx.play(&"clink" if role == Role.MINER else &"chop", at, -4.0, randf_range(0.9, 1.1))
	_swing(p, u)
	if _state_t > _state_len and u < 0.1:
		_start(&"pace" if randf() < 0.5 else &"rest")

## One swing: up over the head, down hard, back to ready.
func _swing(p: Dictionary, u: float) -> void:
	var low := role == Role.MINER
	var arm := _keys(u, [[0.0, 0.6], [0.4, 2.8], [0.5, 0.05 if low else 0.3], [0.62, 0.15 if low else 0.4], [1.0, 0.6]])
	var lean := _keys(u, [[0.0, 0.0], [0.4, 0.2], [0.5, -0.5 if low else -0.38], [0.7, -0.35 if low else -0.25], [1.0, 0.0]])
	var twist := 0.0 if low else _keys(u, [[0.0, 0.0], [0.4, -0.35], [0.5, 0.25], [1.0, 0.0]])
	_put(p, &"Arm_R", Vector3(arm, 0, 0.05))
	_put(p, &"Arm_L", Vector3(arm - 0.1, 0, 0.35))
	_add(p, &"Torso", Vector3(lean, twist, 0))
	_add(p, &"Head", Vector3(-lean * 0.5, 0, 0))
	var knee := maxf(0.0, -lean) * (0.8 if low else 0.5)
	_add(p, &"Leg_L", Vector3(knee * 0.6, 0, 0))
	_add(p, &"Leg_R", Vector3(knee * 0.6, 0, 0))
	p[&"root"] += Vector3(0, -0.08 * knee, 0)
	var wind := 1.2 * (1.0 - smoothstep(0.3, 0.5, u)) * smoothstep(0.0, 0.2, u)
	_bend(p, knee, knee, 0.4 + wind * 0.6, 0.35 + wind, 1.4, 1.45)

# Pacing about: off to a spot and back, tool over his shoulder.
func _pacing(p: Dictionary, delta: float) -> void:
	var goal := _on_ground(pace_to if _phase_out else post)
	var gap := goal - position
	gap.y = 0.0
	if gap.length() < 0.25:
		if _phase_out:
			_phase_out = false
		else:
			_start(&"work" if randf() < 0.65 else &"rest")
			return
	_step_toward(p, goal, delta, 1.25)
	_tool_up(p)

var _phase_out := true

func _tool_up(p: Dictionary) -> void:
	if _tool == null:
		return
	_put(p, &"Arm_R", Vector3(0.5, 0, 0.12))
	p[&"Elbow_R"] = _rest.get(&"Elbow_R", Vector3.ZERO) + Vector3(0.95, 0, 0)
	_curl(p, &"R", 1.45)

## A step toward `goal` (parent's frame, on the ground), legs and arms going.
func _step_toward(p: Dictionary, goal: Vector3, delta: float, speed: float) -> void:
	var gap := goal - position
	gap.y = 0.0
	var step := minf(gap.length(), speed * delta)
	if gap.length() > 0.001:
		position += gap.normalized() * step
		position.y = _on_ground(position).y
		_face(position + gap, delta, 8.0)
	_phase = fmod(_phase + delta * speed * 3.0, TAU)
	var s := sin(_phase)
	var c := cos(_phase)
	var amp := 0.5
	_add(p, &"Leg_L", Vector3(amp * s, 0, 0))
	_add(p, &"Leg_R", Vector3(-amp * s, 0, 0))
	_add(p, &"Arm_L", Vector3(-amp * 0.8 * s, 0, 0))
	_add(p, &"Arm_R", Vector3(amp * 0.8 * s, 0, 0))
	_add(p, &"Torso", Vector3(-0.06, 0.1 * amp * s, 0))
	p[&"root"] += Vector3(0, 0.04 * absf(c), 0)
	_bend(p, 0.06 + 0.9 * maxf(0.0, c), 0.06 + 0.9 * maxf(0.0, -c), 0.3, 0.3, 0.5, 0.5)
	if _state_t > 0.3 and fmod(_phase, PI) < delta * speed * 3.0:
		Sfx.play(&"step", global_position, -18.0, randf_range(0.9, 1.1))

# Leaning on his tool for a breather, and wiping his brow.
func _resting(p: Dictionary) -> void:
	_put(p, &"Arm_R", Vector3(0.78, 0, -0.12))
	_put(p, &"Arm_L", Vector3(0.78, 0, 0.36))
	_add(p, &"Torso", Vector3(-0.14, 0, 0))
	# Weight on one leg, the other knee easy.
	_add(p, &"Leg_L", Vector3(-0.06, 0, -0.05))
	var wipe := smoothstep(0.35, 0.45, _state_t / _state_len) * (1.0 - smoothstep(0.6, 0.7, _state_t / _state_len))
	if wipe > 0.0:
		_put(p, &"Arm_L", Vector3(lerpf(0.78, 2.3, wipe), 0, lerpf(0.36, 0.75, wipe)))
		_add(p, &"Head", Vector3(-0.15 * wipe, 0, 0))
	_bend(p, 0.28, 0.06, lerpf(0.55, 1.9, wipe), 0.55, lerpf(1.35, 0.3, wipe), 1.35)
	_breathe(p, 2.4)
	_look_round(p)
	if _state_t > _state_len:
		if stationary:
			_state_t = 0.0
			return
		_to_hand()
		_start(&"work")

# The lumberman, when his tree has come down: stamping, fists in the air.
func _angry(p: Dictionary) -> void:
	_face_watcher()
	var shake := sin(_t * 18.0)
	_put(p, &"Arm_R", Vector3(2.6 + 0.2 * shake, 0, 0.4))
	_put(p, &"Arm_L", Vector3(2.6 - 0.2 * shake, 0, -0.4))
	var stamp := absf(sin(_t * 7.0))
	_add(p, &"Leg_L", Vector3(0.35 * stamp, 0, 0))
	_add(p, &"Torso", Vector3(0.12, 0, 0))
	_add(p, &"Head", Vector3(0.15, 0, 0.1 * shake))
	_bend(p, 0.6 * stamp, 0.1, 0.9, 0.9, 1.5, 1.5)
	if _state_t > _state_len:
		_start(&"sulk")

# Waiting for his tree to grow back: arms folded, foot tapping.
func _sulking(p: Dictionary) -> void:
	_put(p, &"Arm_R", Vector3(0.9, 0, -0.55))
	_put(p, &"Arm_L", Vector3(0.9, 0, 0.55))
	_add(p, &"Torso", Vector3(0.05, 0, 0))
	var tap := maxf(0.0, sin(_t * 6.0))
	_add(p, &"Foot_R", Vector3(-0.3 * tap, 0, 0))
	_bend(p, 0.05, 0.05, 1.7, 1.7, 1.2, 1.2)
	_look_round(p)
	_breathe(p)
	if has_work:
		_start(&"work")

func _face_watcher() -> void:
	var who: Variant = _watcher()
	if who is Node3D and get_parent() is Node3D:
		var local := (get_parent() as Node3D).to_local((who as Node3D).global_position)
		_face(local, get_process_delta_time(), 6.0)

# The helper walking somewhere (with or without a load).
func _walking(p: Dictionary, delta: float) -> void:
	if _walk_to == Vector3.INF:
		_start(&"idle")
		return
	var goal := _on_ground(_walk_to)
	var gap := goal - position
	gap.y = 0.0
	if gap.length() < 0.2:
		_walk_to = Vector3.INF
		_start(_walk_then)
		return
	_step_toward(p, goal, delta, 2.1)
	if holding():
		_carry_pose(p)

func _carry_pose(p: Dictionary) -> void:
	_put(p, &"Arm_L", Vector3(1.2, 0, 0.22))
	_put(p, &"Arm_R", Vector3(1.2, 0, -0.22))
	p[&"Elbow_L"] = _rest.get(&"Elbow_L", Vector3.ZERO) + Vector3(0.6, 0, 0)
	p[&"Elbow_R"] = _rest.get(&"Elbow_R", Vector3.ZERO) + Vector3(0.6, 0, 0)
	_add(p, &"Torso", Vector3(0.12, 0, 0))

# Standing about: weight shifting, a whistle now and then, watching you.
func _idling(p: Dictionary) -> void:
	var shift := sin(_t * 0.45)
	_add(p, &"Torso", Vector3(0, 0, 0.03 * shift))
	_bend(p, 0.1 * maxf(0.0, shift), 0.1 * maxf(0.0, -shift), 0.25, 0.25, 0.5, 0.5)
	if role == Role.HELPER or role == Role.SHOPKEEP:
		# Arms folded, rocking on his heels.
		_put(p, &"Arm_R", Vector3(0.85, 0, -0.5))
		_put(p, &"Arm_L", Vector3(0.8, 0, 0.5))
		p[&"Elbow_L"] = _rest.get(&"Elbow_L", Vector3.ZERO) + Vector3(1.75, 0, 0)
		p[&"Elbow_R"] = _rest.get(&"Elbow_R", Vector3.ZERO) + Vector3(1.75, 0, 0)
		_curl(p, &"L", 1.1)
		_curl(p, &"R", 1.1)
		_add(p, &"Foot_L", Vector3(-0.12 * maxf(0.0, sin(_t * 1.3)), 0, 0))
		_add(p, &"Foot_R", Vector3(-0.12 * maxf(0.0, sin(_t * 1.3)), 0, 0))
		if holding():
			_carry_pose(p)
	_look_round(p)
	_breathe(p)
	if _state_t > _state_len:
		_state_t = 0.0
		if (role == Role.HELPER or role == Role.SHOPKEEP) and randf() < 0.3 and _bubble_t <= 0.0:
			say("~ whistles ~", 2.0)

## Cheers and waves on top of whatever else.
func _overlay(p: Dictionary, delta: float) -> void:
	if _gesture == &"":
		return
	_gesture_t += delta
	var k := _gesture_t / 1.4
	if k >= 1.0:
		_gesture = &""
		return
	var w := sin(k * PI)
	match _gesture:
		&"wave":
			p[&"Arm_R"] = (p[&"Arm_R"] as Vector3).lerp(Vector3(2.7, 0, 0.5 + 0.3 * sin(_gesture_t * 14.0)), w)
			p[&"Elbow_R"] = (p[&"Elbow_R"] as Vector3).lerp(_rest.get(&"Elbow_R", Vector3.ZERO) + Vector3(0.4, 0, 0), w)
		&"cheer":
			p[&"Arm_R"] = (p[&"Arm_R"] as Vector3).lerp(Vector3(2.9, 0, 0.3), w)
			p[&"Arm_L"] = (p[&"Arm_L"] as Vector3).lerp(Vector3(2.9, 0, -0.3), w)
			p[&"root"] += Vector3(0, 0.12 * w * absf(sin(_gesture_t * 9.0)), 0)
		&"pick_up":
			_add(p, &"Torso", Vector3(-0.8 * w, 0, 0))
			p[&"Arm_L"] = (p[&"Arm_L"] as Vector3).lerp(Vector3(1.0, 0, 0.2), w)
			p[&"Arm_R"] = (p[&"Arm_R"] as Vector3).lerp(Vector3(1.0, 0, -0.2), w)
			_add(p, &"Leg_L", Vector3(0.5 * w, 0, 0))
			_add(p, &"Leg_R", Vector3(0.5 * w, 0, 0))
			p[&"Knee_L"] = (p[&"Knee_L"] as Vector3) + Vector3(-0.9 * w, 0, 0)
			p[&"Knee_R"] = (p[&"Knee_R"] as Vector3) + Vector3(-0.9 * w, 0, 0)
			p[&"root"] += Vector3(0, -0.12 * w, 0)

func _apply(p: Dictionary, delta: float) -> void:
	var k := 1.0 - exp(-14.0 * delta)
	for n in _part:
		var want: Vector3 = p.get(n, _rest[n])
		_now[n] = (_now[n] as Vector3).lerp(want, k)
		(_part[n] as Node3D).rotation = _now[n]
	if _figure != null and _chair == null:
		_figure.position = _figure.position.lerp(p[&"root"], k)
	if _rocker != null:
		# The chair rocks on its runners: about the point under the seat.
		var a: float = p[&"rock"]
		_rocker.transform = Transform3D(Basis(Vector3.RIGHT, a), Vector3(0, absf(a) * 0.2, 0))

func _on_ground(at: Vector3) -> Vector3:
	if not ground.is_valid() or not (get_parent() is Node3D):
		return Vector3(at.x, position.y, at.z)
	var parent := get_parent() as Node3D
	var g := parent.to_global(Vector3(at.x, 0.0, at.z))
	var y: float = ground.call(g.x, g.z)
	return Vector3(at.x, parent.to_local(Vector3(g.x, y, g.z)).y, at.z)
