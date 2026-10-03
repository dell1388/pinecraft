class_name Boot
extends Node

## The first thing on screen: a loading screen, drawn before the world starts
## building so the window is never a blank grey. The world is built in stages
## behind it, a frame apart, and says as it goes what it is doing - raising
## the land, grading so many kilometres of road, growing so many pines - so the
## screen shows every stage as a checklist with its time, the step under way,
## a running log of the steps so far, and a truck hauling logs across the
## bottom as far along as the build is. It fades away once the world is ready.

const WORLD_SCENE := "res://scenes/world.tscn"
const TIPS := [
	"Take the branches off a felled trunk before you cut it into lengths.",
	"A machine with nothing after it sets its work down on the ground.",
	"Prices change once a week - the journal says when.",
	"Planks fill a log order too, cubic metre for cubic metre.",
	"In the crane you move the log: W/S away from / toward the camera, A/D left / right.",
	"Hold the right mouse button in the crane for fine control.",
	"Outriggers [O] lock a crane truck in place for the crane or winch.",
	"Nights are dark - your headlamp comes on by itself.",
	"The crusher takes anything you can drop in its hopper, however big.",
	"Gems sell by the square of their size: a stone twice as big is worth four times as much.",
	"Frost wood is slick as ice once you build with it.",
	"[G] in build mode adds another building to the selection.",
	"The mobile crane's grapple goes down a pit or over a cliff until it meets something.",
	"A sign plan is a board you can write on: fill it, then [E] at it.",
	"Unpaid boxes knocked off their shelf are cleared away and restocked five minutes later.",
]
const TIP_SECONDS := 7.0
const LOG_LINES := 9

var _layer: CanvasLayer
var _root: Control
var _bar: ProgressBar
var _percent: Label
var _clock: Label
var _now: Label
var _stage_title: Label
var _log: VBoxContainer
var _tip: Label
var _rows: Array = []          ## [icon Control, name Label, time Label] per stage
var _scene: Node2D
var _truck: Node2D
var _far: Polygon2D
var _near: Polygon2D
var _trees: Node2D

var _started_ms: int = 0
var _stage_index: int = -1
var _stage_started_ms: int = 0
var _stage_times: Array[float] = []
var _target: float = 0.0
var _shown: float = 0.0
var _tip_index: int = 0
var _tip_time: float = 0.0
var _spin: float = 0.0
var _done: bool = false

## The frame rate cap from before loading, put back once the world is up.
var _fps_before: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_started_ms = Time.get_ticks_msec()
	# The loading screen needs no more than 60 frames a second, and with the
	# monitor sync off it would otherwise draw as fast as it can, taking a
	# core the world's builders could have.
	_fps_before = Engine.max_fps
	if Engine.max_fps == 0 or Engine.max_fps > 60:
		Engine.max_fps = 60
	_tip_index = randi() % TIPS.size()
	_build_screen()
	_say("Starting up: reading the game's data, your settings and your controls")
	# Two frames, so the screen is actually drawn before the long build.
	await get_tree().process_frame
	await get_tree().process_frame
	_say("Loading the world scene")
	await get_tree().process_frame
	var world: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.set("staged_load", true)
	world.connect("load_progress", _on_progress)
	world.connect("load_detail", _say)
	world.connect("finished_loading", _on_loaded.bind(world))
	get_tree().root.add_child(world)

# --- Hearing from the world ------------------------------------------------------

func _on_progress(stage: String, fraction: float) -> void:
	var stages: Array = World.LOAD_STAGES
	var index := -1
	for i in stages.size():
		if String(stages[i][0]) == stage:
			index = i
	if stage == "Ready":
		index = stages.size()
	if index < 0:
		return
	var now := Time.get_ticks_msec()
	# Everything before this stage is done, with the time it took.
	while _stage_index < index:
		if _stage_index >= 0 and _stage_index < stages.size():
			_stage_times[_stage_index] = float(now - _stage_started_ms) / 1000.0
		_stage_index += 1
		_stage_started_ms = now
	_target = maxf(_target, fraction)
	if index < stages.size():
		_stage_title.text = "%s  (%d of %d)" % [stage, index + 1, stages.size()]
	_refresh_rows()

## One step, as it starts: the headline, a line in the log, and the bar
## creeps a little toward the next stage.
func _say(text: String) -> void:
	_now.text = text
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var at := Label.new()
	at.text = "%6.1f s" % (float(Time.get_ticks_msec() - _started_ms) / 1000.0)
	at.custom_minimum_size.x = 64
	at.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	at.add_theme_color_override("font_color", UITheme.FAINT)
	at.add_theme_font_size_override("font_size", 14)
	line.add_child(at)
	var what := Label.new()
	what.text = text
	what.clip_text = true
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	what.add_theme_font_size_override("font_size", 14)
	line.add_child(what)
	_log.add_child(line)
	while _log.get_child_count() > LOG_LINES:
		var old := _log.get_child(0)
		_log.remove_child(old)
		old.queue_free()
	# Newest brightest, the rest fading back.
	var n := _log.get_child_count()
	for i in n:
		var row := _log.get_child(i) as Control
		row.modulate.a = lerpf(0.35, 1.0, float(i + 1) / float(n))
		((row.get_child(1)) as Label).add_theme_color_override("font_color",
			UITheme.INK if i == n - 1 else UITheme.MUTED)
	var stages: Array = World.LOAD_STAGES
	var next := 1.0
	if _stage_index + 1 < stages.size():
		next = float(stages[_stage_index + 1][1])
	_target = maxf(_target, _target + (next - _target) * 0.12)

func _on_loaded(world: Node) -> void:
	Engine.max_fps = _fps_before
	get_tree().current_scene = world
	_on_progress("Ready", 1.0)
	_done = true
	_target = 1.0
	_stage_title.text = "Ready"
	_say("Ready - the world took %.1f s to build" % (float(Time.get_ticks_msec() - _started_ms) / 1000.0))
	var t := create_tween()
	t.tween_interval(0.6)
	t.tween_property(_root, "modulate:a", 0.0, 0.5)
	t.tween_callback(queue_free)

# --- Every frame -----------------------------------------------------------------

func _process(delta: float) -> void:
	_shown = move_toward(_shown, _target, maxf(0.002, (_target - _shown) * 4.0 * delta))
	_bar.value = _shown * 100.0
	_percent.text = "%d%%" % int(round(_shown * 100.0))
	_clock.text = "%.1f s" % (float(Time.get_ticks_msec() - _started_ms) / 1000.0)
	_spin += delta * 5.0
	_refresh_rows()
	_tip_time += delta
	if _tip_time >= TIP_SECONDS:
		_tip_time = 0.0
		_tip_index = (_tip_index + 1) % TIPS.size()
		_tip.text = "Tip: " + String(TIPS[_tip_index])
	_move_scene(delta)

func _refresh_rows() -> void:
	var now := Time.get_ticks_msec()
	for i in _rows.size():
		var row: Array = _rows[i]
		var icon := row[0] as Control
		var name_label := row[1] as Label
		var time_label := row[2] as Label
		var state := 0 if i > _stage_index else (1 if i == _stage_index and not _done else 2)
		icon.set_meta(&"state", state)
		icon.set_meta(&"spin", _spin)
		icon.queue_redraw()
		match state:
			0:
				name_label.add_theme_color_override("font_color", UITheme.FAINT)
				time_label.text = ""
			1:
				name_label.add_theme_color_override("font_color", UITheme.ACCENT)
				time_label.text = "%.1f s" % (float(now - _stage_started_ms) / 1000.0)
				time_label.add_theme_color_override("font_color", UITheme.ACCENT)
			2:
				name_label.add_theme_color_override("font_color", UITheme.INK)
				time_label.text = "%.1f s" % _stage_times[i]
				time_label.add_theme_color_override("font_color", UITheme.GOOD)

# --- The scene along the bottom ---------------------------------------------------

## Hills and pines drifting past, and a log truck driving from the left edge
## to the right as the world gets built.
func _move_scene(delta: float) -> void:
	var s := get_viewport().get_visible_rect().size
	if _trees != null:
		_trees.position.x = fposmod(_trees.position.x - delta * 14.0, 240.0) - 240.0
	if _truck != null:
		var road_y := s.y * 0.93
		var x := lerpf(s.x * 0.06, s.x * 0.86, _shown)
		_truck.position = Vector2(x, road_y + sin(_spin * 1.7) * 0.8)
		for w in _truck.get_children():
			if w.has_meta(&"wheel"):
				(w as Node2D).rotation += delta * 6.0

func _shape_scene() -> void:
	var s := get_viewport().get_visible_rect().size
	_far.polygon = _ridge(s, 0.70, [0.02, -0.05, 0.03, -0.06, 0.04, -0.03, 0.02, -0.04, 0.03])
	_near.polygon = _ridge(s, 0.80, [0.0, 0.05, -0.03, 0.04, -0.02, 0.06, 0.0, 0.03, -0.02])
	for c in _trees.get_children():
		c.queue_free()
	# Rows of pines along the near ridge, wide enough to scroll a gap's worth.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var x := 0.0
	while x < s.x + 480.0:
		var h := rng.randf_range(34.0, 70.0)
		var base := s.y * (0.80 + rng.randf_range(-0.015, 0.03))
		var pine := Polygon2D.new()
		pine.color = Color(0.06, 0.10, 0.075).lerp(Color(0.09, 0.14, 0.10), rng.randf())
		pine.polygon = PackedVector2Array([
			Vector2(x, base - h), Vector2(x + h * 0.22, base - h * 0.55), Vector2(x + h * 0.12, base - h * 0.55),
			Vector2(x + h * 0.30, base - h * 0.2), Vector2(x + h * 0.16, base - h * 0.2),
			Vector2(x + h * 0.36, base + 4.0), Vector2(x - h * 0.36, base + 4.0),
			Vector2(x - h * 0.16, base - h * 0.2), Vector2(x - h * 0.30, base - h * 0.2),
			Vector2(x - h * 0.12, base - h * 0.55), Vector2(x - h * 0.22, base - h * 0.55)])
		_trees.add_child(pine)
		x += rng.randf_range(22.0, 60.0)

func _make_truck() -> Node2D:
	var truck := Node2D.new()
	var body := Color(0.86, 0.62, 0.20)
	var dark := Color(0.08, 0.09, 0.08)
	var log_color := Color(0.46, 0.31, 0.18)
	var add := func(points: Array, color: Color) -> void:
		var p := Polygon2D.new()
		p.polygon = PackedVector2Array(points)
		p.color = color
		truck.add_child(p)
	# Trailer bed with a load of logs, the cab in front.
	add.call([Vector2(-150, -16), Vector2(-20, -16), Vector2(-20, -8), Vector2(-150, -8)], dark)
	for i in 3:
		for j in 3 - i:
			var cx := -136.0 + float(j) * 20.0 + float(i) * 10.0
			var cy := -26.0 - float(i) * 17.0
			var pts: Array = []
			for k in 10:
				var a := TAU * float(k) / 10.0
				pts.append(Vector2(cx + cos(a) * 9.0, cy + sin(a) * 9.0))
			add.call(pts, log_color.lightened(0.08 * float((i + j) % 2)))
	# The logs' long sides, running the length of the bed.
	add.call([Vector2(-146, -34), Vector2(-26, -34), Vector2(-26, -18), Vector2(-146, -18)], log_color.darkened(0.15))
	for x in [-144.0, -84.0, -28.0]:
		add.call([Vector2(x, -64), Vector2(x + 4, -64), Vector2(x + 4, -16), Vector2(x, -16)], dark)
	add.call([Vector2(-18, -44), Vector2(18, -44), Vector2(30, -26), Vector2(30, -8), Vector2(-18, -8)], body)
	add.call([Vector2(-10, -40), Vector2(14, -40), Vector2(22, -28), Vector2(-10, -28)], Color(0.35, 0.5, 0.6))
	add.call([Vector2(-16, -58), Vector2(-12, -58), Vector2(-12, -44), Vector2(-16, -44)], dark)
	for wx in [-130.0, -104.0, -40.0, 16.0]:
		var wheel := Node2D.new()
		wheel.position = Vector2(wx, -6)
		wheel.set_meta(&"wheel", true)
		var tyre := Polygon2D.new()
		var ring: Array = []
		for k in 12:
			var a := TAU * float(k) / 12.0
			ring.append(Vector2(cos(a), sin(a)) * 10.0)
		tyre.polygon = PackedVector2Array(ring)
		tyre.color = dark
		wheel.add_child(tyre)
		var hub := Polygon2D.new()
		hub.polygon = PackedVector2Array([Vector2(-4, -1.5), Vector2(4, -1.5), Vector2(4, 1.5), Vector2(-4, 1.5)])
		hub.color = Color(0.5, 0.5, 0.48)
		wheel.add_child(hub)
		truck.add_child(wheel)
	return truck

# --- Layout ----------------------------------------------------------------------

func _build_screen() -> void:
	RenderingServer.set_default_clear_color(UITheme.PANEL_SOLID)
	_layer = CanvasLayer.new()
	_layer.layer = 120
	add_child(_layer)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.theme()
	_layer.add_child(_root)

	# Dusk: a sky fading down to the hills, the land along the bottom, and a
	# road for the truck.
	var sky := TextureRect.new()
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.035, 0.05, 0.075))
	grad.set_color(1, Color(0.10, 0.12, 0.10))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	sky.texture = gt
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	_root.add_child(sky)
	_scene = Node2D.new()
	_root.add_child(_scene)
	_far = Polygon2D.new()
	_far.color = Color(0.075, 0.105, 0.085)
	_scene.add_child(_far)
	_trees = Node2D.new()
	_scene.add_child(_trees)
	_near = Polygon2D.new()
	_near.color = Color(0.09, 0.13, 0.10)
	_scene.add_child(_near)
	var road := ColorRect.new()
	road.color = Color(0.05, 0.06, 0.055)
	road.anchor_left = 0.0
	road.anchor_right = 1.0
	road.anchor_top = 0.93
	road.anchor_bottom = 1.0
	_root.add_child(road)
	_truck = _make_truck()
	_root.add_child(_truck)
	get_viewport().size_changed.connect(_shape_scene)
	_shape_scene()

	# Two cards side by side: the stages on the left, what is happening now
	# on the right.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 90)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 170)
	_root.add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	margin.add_child(columns)

	var left := _card(columns, 0.38)
	var title := Label.new()
	title.text = "PINECRAFT"
	title.add_theme_font_override("font", UITheme.display_font())
	title.add_theme_font_size_override("font_size", 58)
	title.add_theme_color_override("font_color", UITheme.INK)
	left.add_child(title)
	var sub := Label.new()
	sub.text = "fell  -  haul  -  mill  -  build"
	sub.add_theme_color_override("font_color", UITheme.MUTED)
	left.add_child(sub)
	var version := Label.new()
	version.text = "version %s  ·  built %s" % [BuildInfo.NUMBER, BuildInfo.RELEASED]
	version.add_theme_color_override("font_color", UITheme.FAINT)
	version.add_theme_font_size_override("font_size", 13)
	left.add_child(version)
	left.add_child(_gap(14))
	var heading := Label.new()
	heading.text = "BUILDING THE WORLD"
	heading.add_theme_color_override("font_color", UITheme.FAINT)
	heading.add_theme_font_size_override("font_size", 13)
	left.add_child(heading)
	for stage in World.LOAD_STAGES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(22, 22)
		icon.set_meta(&"state", 0)
		icon.draw.connect(_draw_icon.bind(icon))
		row.add_child(icon)
		var name_label := Label.new()
		name_label.text = String(stage[0])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 19)
		row.add_child(name_label)
		var time_label := Label.new()
		time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		time_label.custom_minimum_size.x = 70
		row.add_child(time_label)
		left.add_child(row)
		_rows.append([icon, name_label, time_label])
		_stage_times.append(0.0)
	left.add_child(_gap(10))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	_tip = Label.new()
	_tip.text = "Tip: " + String(TIPS[_tip_index])
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_color_override("font_color", UITheme.MUTED)
	_tip.add_theme_font_size_override("font_size", 15)
	left.add_child(_tip)

	var right := _card(columns, 0.62)
	var top := HBoxContainer.new()
	_stage_title = Label.new()
	_stage_title.text = "Getting ready"
	_stage_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_title.add_theme_font_override("font", UITheme.display_font())
	_stage_title.add_theme_font_size_override("font_size", 30)
	_stage_title.add_theme_color_override("font_color", UITheme.ACCENT)
	top.add_child(_stage_title)
	_percent = Label.new()
	_percent.add_theme_font_override("font", UITheme.display_font())
	_percent.add_theme_font_size_override("font_size", 30)
	_percent.add_theme_color_override("font_color", UITheme.INK)
	top.add_child(_percent)
	right.add_child(top)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 14)
	_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITheme.ACCENT
	fill.set_corner_radius_all(7)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.08)
	track.set_corner_radius_all(7)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", track)
	right.add_child(_bar)
	var under := HBoxContainer.new()
	var now_label := Label.new()
	now_label.text = "NOW"
	now_label.add_theme_color_override("font_color", UITheme.FAINT)
	now_label.add_theme_font_size_override("font_size", 13)
	now_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	under.add_child(now_label)
	_clock = Label.new()
	_clock.add_theme_color_override("font_color", UITheme.FAINT)
	_clock.add_theme_font_size_override("font_size", 13)
	under.add_child(_clock)
	right.add_child(under)
	_now = Label.new()
	_now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_now.custom_minimum_size.y = 56
	_now.add_theme_font_size_override("font_size", 20)
	_now.add_theme_color_override("font_color", UITheme.INK)
	right.add_child(_now)
	right.add_child(_gap(6))
	var log_heading := Label.new()
	log_heading.text = "SO FAR"
	log_heading.add_theme_color_override("font_color", UITheme.FAINT)
	log_heading.add_theme_font_size_override("font_size", 13)
	right.add_child(log_heading)
	_log = VBoxContainer.new()
	_log.add_theme_constant_override("separation", 3)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_log)

## A card in the row: a panel, with a column inside it.
func _card(parent: Container, share: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.055, 0.05, 0.82)
	style.border_color = UITheme.EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = share
	parent.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	return col

func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

## A stage's mark: an empty ring still to come, a turning arc under way, a
## tick in a green disc when done.
func _draw_icon(icon: Control) -> void:
	var c := icon.size * 0.5
	var r := minf(c.x, c.y) - 2.0
	match int(icon.get_meta(&"state", 0)):
		0:
			icon.draw_arc(c, r, 0.0, TAU, 24, UITheme.FAINT, 2.0, true)
		1:
			icon.draw_arc(c, r, 0.0, TAU, 24, Color(UITheme.ACCENT, 0.25), 2.0, true)
			var a := float(icon.get_meta(&"spin", 0.0))
			icon.draw_arc(c, r, a, a + PI * 1.2, 16, UITheme.ACCENT, 2.5, true)
		2:
			icon.draw_circle(c, r, UITheme.GOOD)
			icon.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.5, 0), c + Vector2(-r * 0.12, r * 0.4),
				c + Vector2(r * 0.55, -r * 0.4)]), Color(0.05, 0.1, 0.05), 2.5, true)

## A ridge line across the bottom of the screen: heights are fractions of
## the screen height added to `base`.
static func _ridge(s: Vector2, base: float, bumps: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2(0, s.y))
	for i in bumps.size():
		var x := s.x * float(i) / float(bumps.size() - 1)
		pts.append(Vector2(x, s.y * (base + float(bumps[i]))))
	pts.append(Vector2(s.x, s.y))
	return pts
