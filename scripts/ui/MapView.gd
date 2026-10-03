class_name MapView
extends Control

## The map in the journal: the land drawn from above, with home, the yard, the
## store, the quarry, your truck, and every place you have found out on it.
## Places not yet found show as a question mark, so the map says where to go
## without saying what is there. The mouse wheel zooms (about the pointer),
## dragging moves it about, a double-click puts it back.

const MAX_ZOOM := 8.0
var zoom: float = 1.0
## The map's top-left corner in view, as a share of the whole map.
var offset: Vector2 = Vector2.ZERO
var _dragging: bool = false

var world: Node
var _texture: Texture2D
var _font: Font
var _bold: Font

func _ready() -> void:
	_font = UITheme.font(600)
	_bold = UITheme.font(800)
	custom_minimum_size = Vector2(520, 520)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		zoom_by(1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8, mb.position)
		accept_event()
	elif mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		_dragging = mb.pressed
		if mb.pressed and mb.double_click:
			zoom = 1.0
			offset = Vector2.ZERO
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var rect := _map_rect()
		offset -= (event as InputEventMouseMotion).relative / (rect.size * zoom)
		_clamp()
		accept_event()
	elif Controls.pressed(event, &"map_zoom_in") or Controls.pressed(event, &"map_zoom_out"):
		zoom_by(1.25 if Controls.pressed(event, &"map_zoom_in") else 0.8, size * 0.5)
		accept_event()

## Zooms keeping the point under `at` (in this control) where it is.
func zoom_by(factor: float, at: Vector2) -> void:
	var rect := _map_rect()
	var under := offset + (at - rect.position) / (rect.size * zoom)
	zoom = clampf(zoom * factor, 1.0, MAX_ZOOM)
	offset = under - (at - rect.position) / (rect.size * zoom)
	_clamp()

func _clamp() -> void:
	var view := 1.0 / zoom
	offset = offset.clamp(Vector2.ZERO, Vector2.ONE * (1.0 - view))

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
	return rect.position + (t - offset) * rect.size * zoom

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
	draw_texture_rect(_texture, Rect2(rect.position - offset * rect.size * zoom, rect.size * zoom), false)

	# Home and the fixed places.
	var fixed := [
		["Plot", world.get("plot").global_position, Color(0.55, 0.85, 0.50)],
	]
	# A map with no buildings (Ostars) has none of the rest.
	if not WorldMap.is_ostars():
		fixed.append(["Quarry", World.QUARRY_CENTRE, Color(0.80, 0.70, 0.62)])
	# On Ostars the yards are the traders' (points of interest, below).
	for extra in [["Sell Yard", null if WorldMap.is_ostars() else world.get("depot"), Color(0.98, 0.80, 0.30)],
			["Hardware Store", world.get("store"), Color(0.55, 0.78, 1.0)],
			["Vehicle Dealer", world.get("dealer_store"), Color(0.45, 0.9, 0.95)],
			["Machine Works", world.get("works_store"), Color(0.95, 0.6, 0.35)]]:
		if extra[1] != null:
			fixed.append([extra[0], (extra[1] as Node3D).global_position, extra[2]])
	var summit: Node3D = world.get("summit_store")
	if summit != null:
		fixed.append(["Summit Outfitters", summit.global_position, Color(0.7, 0.62, 1.0)])
	for f in fixed:
		_marker(_to_map(f[1], rect), f[0], f[2], 6.0)
	for poi in world.call("points_of_interest"):
		var found: bool = poi.get("known", false) or world.call("discovered", poi.name)
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
	# North, and how to work it.
	_text("N", rect.position + Vector2(rect.size.x - 18, 24), 18, UITheme.ACCENT, _bold)
	_text("wheel or +/- zoom  ·  drag to move  ·  double-click resets", rect.position + Vector2(rect.size.x * 0.5, rect.size.y - 8), 12, UITheme.INK, _font)

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
