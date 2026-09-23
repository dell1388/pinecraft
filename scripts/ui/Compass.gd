class_name Compass
extends Control

## A heading strip across the top of the screen with the places worth going
## marked on it. The map is big and the landmarks are boxes; this is how you
## find the sell yard again with a load on your back.

const SPAN := deg_to_rad(150.0)       ## how much of the horizon the strip shows

## Each marker: {"name": String, "color": Color, "where": Callable -> Variant}.
## `where` returns a Vector3, or null while the place does not exist (no truck).
var markers: Array[Dictionary] = []
var camera: Camera3D
var _font: Font
var _bold: Font

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(620, 50)

func _ready() -> void:
	_font = UITheme.font(600)
	_bold = UITheme.font(800)

var _last_view: Transform3D
var _since: float = 0.0

## Redrawn when the view turns or moves, and a few times a second regardless
## so a marker that moves on its own (the truck) keeps up.
func _process(delta: float) -> void:
	if not is_visible_in_tree() or camera == null or not is_instance_valid(camera):
		return
	_since += delta
	var view := camera.global_transform
	if _since > 0.25 or not view.is_equal_approx(_last_view):
		_last_view = view
		_since = 0.0
		queue_redraw()

## Heading in radians, 0 = north (-Z), growing clockwise.
static func heading_of(forward: Vector3) -> float:
	return fposmod(atan2(forward.x, -forward.z), TAU)

## Where a bearing sits across the strip, from -1 (left edge) to 1 (right).
static func offset_of(bearing: float, heading: float) -> float:
	return wrapf(bearing - heading, -PI, PI) / (SPAN * 0.5)

func _draw() -> void:
	if camera == null or not is_instance_valid(camera):
		return
	var w := size.x
	var mid := w * 0.5
	var strip := Rect2(0, 0, w, 30)
	draw_style_box(UITheme.box(UITheme.PANEL, 15, Vector4.ZERO), strip)
	var forward := -camera.global_transform.basis.z
	var heading := heading_of(forward)
	var here := camera.global_position

	# Ticks and the cardinal letters.
	for i in 24:
		var bearing := deg_to_rad(i * 15.0)
		var x := offset_of(bearing, heading)
		if absf(x) > 0.97:
			continue
		var px := mid + x * mid
		var fade := 1.0 - absf(x) * 0.8
		if i % 6 == 0:
			var letter: String = ["N", "E", "S", "W"][i / 6]
			var col := UITheme.ACCENT if letter == "N" else UITheme.INK
			_centred(letter, px, 21, 16, Color(col, fade), _bold)
		elif i % 3 == 0:
			var ordinal: String = ["NE", "SE", "SW", "NW"][i / 6]
			_centred(ordinal, px, 20, 11, Color(UITheme.MUTED, fade), _font)
		else:
			draw_line(Vector2(px, 11), Vector2(px, 19), Color(1, 1, 1, 0.22 * fade), 1.5)

	# Markers: on the strip if in view, pinned to the edge with an arrow if not.
	for m in markers:
		var where: Variant = (m.where as Callable).call()
		if where == null:
			continue
		var target: Vector3 = where
		var flat := Vector3(target.x - here.x, 0.0, target.z - here.z)
		var dist := flat.length()
		if dist < 6.0:
			continue
		var x := offset_of(heading_of(flat), heading)
		var col: Color = m.color
		var off_strip := absf(x) > 0.95
		var px := mid + clampf(x, -0.95, 0.95) * mid
		if off_strip:
			var dir := signf(x)
			var tip := Vector2(px + dir * 8.0, 15)
			draw_colored_polygon(PackedVector2Array([tip, Vector2(px - dir * 2.0, 8),
				Vector2(px - dir * 2.0, 22)]), col)
			continue
		draw_colored_polygon(PackedVector2Array([Vector2(px, 7), Vector2(px + 6, 15),
			Vector2(px, 23), Vector2(px - 6, 15)]), col)
		draw_polyline(PackedVector2Array([Vector2(px, 7), Vector2(px + 6, 15),
			Vector2(px, 23), Vector2(px - 6, 15), Vector2(px, 7)]), Color(0, 0, 0, 0.6), 1.2, true)
		# Name and distance under the strip, only near the middle so the edges
		# do not turn into a pile of words.
		if absf(x) < 0.55:
			var label: String = (m.name as Callable).call() if m.name is Callable else String(m.name)
			var text := "%s  %dm" % [label, int(dist)]
			_centred(text, px, 46, 13, Color(col, 1.0 - absf(x)), _font, true)

	# The heading pointer.
	draw_colored_polygon(PackedVector2Array([Vector2(mid - 6, 30), Vector2(mid + 6, 30),
		Vector2(mid, 24)]), UITheme.ACCENT)

func _centred(text: String, x: float, baseline: float, size: int, color: Color,
		font: Font, shadow: bool = false) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := Vector2(x - width * 0.5, baseline)
	if shadow:
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.7 * color.a))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
