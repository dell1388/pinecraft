class_name Boot
extends Node

## The first thing on screen: a loading screen, drawn before the world starts
## building so the window is never a blank grey. The world is built in stages
## behind it, each one moving the bar on, and the screen fades away once the
## world is ready.

const WORLD_SCENE := "res://scenes/world.tscn"
const TIPS := [
	"Take the branches off a felled trunk before you cut it into lengths.",
	"A machine with nothing after it sets its work down on the ground.",
	"Prices change once a week - the journal says when.",
	"Planks fill a log order too, cubic metre for cubic metre.",
	"In the crane you move the log: W/S along the truck, A/D across it.",
	"Hold the right mouse button in the crane for fine control.",
	"Outriggers [O] lock a truck in place for the winch.",
	"Nights are dark - your headlamp comes on by itself.",
]

var _layer: CanvasLayer
var _root: Control
var _bar: ProgressBar
var _stage: Label

func _ready() -> void:
	_build_screen()
	# Two frames, so the screen is actually drawn before the long build.
	await get_tree().process_frame
	await get_tree().process_frame
	var world: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.set("staged_load", true)
	world.connect("load_progress", _on_progress)
	world.connect("finished_loading", _on_loaded.bind(world))
	get_tree().root.add_child(world)

func _on_progress(stage: String, fraction: float) -> void:
	_stage.text = stage
	var t := create_tween()
	t.tween_property(_bar, "value", fraction * 100.0, 0.25)

func _on_loaded(world: Node) -> void:
	get_tree().current_scene = world
	_bar.value = 100.0
	_stage.text = "Ready"
	var t := create_tween()
	t.tween_interval(0.2)
	t.tween_property(_root, "modulate:a", 0.0, 0.5)
	t.tween_callback(queue_free)

func _build_screen() -> void:
	RenderingServer.set_default_clear_color(UITheme.PANEL_SOLID)
	_layer = CanvasLayer.new()
	_layer.layer = 120
	add_child(_layer)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.theme()
	_layer.add_child(_root)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.055, 0.075, 0.065)
	_root.add_child(bg)
	# A band of low hills along the bottom, so it is a place and not a void.
	var far := Polygon2D.new()
	far.color = Color(0.075, 0.105, 0.085)
	_root.add_child(far)
	var hills := Polygon2D.new()
	hills.color = Color(0.09, 0.13, 0.10)
	_root.add_child(hills)
	var shape_hills := func() -> void:
		var s := get_viewport().get_visible_rect().size
		hills.polygon = _ridge(s, 0.78, [0.0, 0.06, -0.04, 0.05, -0.02, 0.07, 0.0])
		far.polygon = _ridge(s, 0.7, [0.02, -0.05, 0.03, -0.06, 0.04, -0.03, 0.02])
	get_viewport().size_changed.connect(shape_hills)
	shape_hills.call()
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.custom_minimum_size = Vector2(520, 0)
	column.position = Vector2(-260, -120)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	_root.add_child(column)
	var title := Label.new()
	title.text = "PINECRAFT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UITheme.display_font())
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", UITheme.INK)
	column.add_child(title)
	var sub := Label.new()
	sub.text = "fell  -  haul  -  mill  -  build"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", UITheme.MUTED)
	column.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 24)
	column.add_child(gap)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(520, 10)
	_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITheme.ACCENT
	fill.set_corner_radius_all(5)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.08)
	track.set_corner_radius_all(5)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", track)
	column.add_child(_bar)
	_stage = Label.new()
	_stage.text = "Starting up"
	_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage.add_theme_color_override("font_color", UITheme.MUTED)
	column.add_child(_stage)
	var tip := Label.new()
	tip.text = "Tip: " + String(TIPS[randi() % TIPS.size()])
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(520, 0)
	tip.add_theme_color_override("font_color", UITheme.FAINT)
	column.add_child(tip)

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
