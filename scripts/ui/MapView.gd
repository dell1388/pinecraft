class_name MapView
extends Control

## The map in the journal: the land drawn from above, with home, the yard, the
## store, the quarry, your truck, and every place you have found out on it.
## Places not yet found show as a question mark, so the map says where to go
## without saying what is there.

var world: Node
var _texture: Texture2D
var _font: Font
var _bold: Font

func _ready() -> void:
	_font = UITheme.font(600)
	_bold = UITheme.font(800)
	custom_minimum_size = Vector2(520, 520)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()

func _map_rect() -> Rect2:
	var side := minf(size.x, size.y)
	return Rect2((size.x - side) * 0.5, 0, side, side)

func _to_map(p: Vector3, rect: Rect2) -> Vector2:
	var terrain: Terrain = world.get("terrain")
	var t := Vector2((p.x + terrain.half_extent) / (terrain.half_extent * 2.0),
		(p.z + terrain.half_extent) / (terrain.half_extent * 2.0))
	return rect.position + t * rect.size

func _draw() -> void:
	if world == null:
		return
	var terrain: Terrain = world.get("terrain")
	if terrain == null:
		return
	if _texture == null:
		_texture = world.call("map_texture")
	var rect := _map_rect()
	draw_style_box(UITheme.box(Color(0, 0, 0, 0.4), 12, Vector4.ZERO, Color(1, 1, 1, 0.15), 1), rect.grow(4))
	draw_texture_rect(_texture, rect, false)

	# Home and the fixed places.
	var fixed := [
		["Plot", world.get("plot").global_position, Color(0.55, 0.85, 0.50)],
		["Sell Yard", world.get("depot").global_position, Color(0.98, 0.80, 0.30)],
		["Store", world.get("store").global_position, Color(0.55, 0.78, 1.0)],
		["Quarry", World.QUARRY_CENTRE, Color(0.80, 0.70, 0.62)],
	]
	for f in fixed:
		_marker(_to_map(f[1], rect), f[0], f[2], 6.0)
	for poi in world.call("points_of_interest"):
		var found: bool = world.call("discovered", poi.name)
		var at := _to_map(poi.pos, rect)
		if found:
			_marker(at, poi.name, poi.color, 6.0)
		else:
			draw_circle(at, 9.0, Color(0, 0, 0, 0.55))
			_text("?", at + Vector2(0, 6), 16, UITheme.INK, _bold)
	for v in world.call("vehicles"):
		var truck := v as Hauler
		_marker(_to_map(truck.global_position, rect), truck.display_name, truck.paint.lightened(0.2), 5.0)

	# You: an arrow pointing where you are looking.
	var player: Node3D = world.get("player")
	var cam: Camera3D = player.get("camera")
	var forward := -cam.global_transform.basis.z
	var heading := Vector2(forward.x, forward.z).normalized()
	if heading.length() < 0.1:
		heading = Vector2(0, -1)
	var at := _to_map(player.global_position, rect)
	var side := Vector2(-heading.y, heading.x)
	var tip := at + heading * 12.0
	var poly := PackedVector2Array([tip, at - heading * 7.0 + side * 7.0, at - heading * 3.0, at - heading * 7.0 - side * 7.0])
	draw_colored_polygon(poly, Color(0, 0, 0, 0.6))
	var inner := PackedVector2Array()
	for v in poly:
		inner.append(at + (v - at) * 0.75)
	draw_colored_polygon(inner, UITheme.ACCENT)
	# North.
	_text("N", rect.position + Vector2(rect.size.x - 18, 24), 18, UITheme.ACCENT, _bold)

func _marker(at: Vector2, label: String, color: Color, radius: float) -> void:
	var diamond := PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius, 0),
		at + Vector2(0, radius), at + Vector2(-radius, 0)])
	draw_colored_polygon(diamond, color)
	diamond.append(diamond[0])
	draw_polyline(diamond, Color(0, 0, 0, 0.7), 1.5, true)
	_text(label, at + Vector2(0, radius + 14), 13, UITheme.INK, _font)

func _text(text: String, at: Vector2, size: int, color: Color, font: Font) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := at - Vector2(width * 0.5, 0)
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.8))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
