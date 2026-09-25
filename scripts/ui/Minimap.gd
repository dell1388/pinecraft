class_name Minimap
extends Control

## The minimap in the corner: the land around you from above, north up, the
## same picture as the journal's map. You are the arrow in the middle, facing
## where you look. Your trucks and the places you have found show where they
## are; home, the yard and the stores sit on the rim when they are off it,
## pointing the way.

const SIDE := 200.0
## Metres across the square.
const SPAN := 260.0

var world: Node
var _texture: Texture2D
var _font: Font

func _ready() -> void:
	_font = UITheme.font(700)
	custom_minimum_size = Vector2(SIDE, SIDE)
	size = Vector2(SIDE, SIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()

## Minimap position of a world point; the player is the centre.
func _to_mini(p: Vector3, centre: Vector3) -> Vector2:
	return size * 0.5 + Vector2(p.x - centre.x, p.z - centre.z) * (size.x / SPAN)

func _draw() -> void:
	if world == null:
		return
	var terrain: Terrain = world.get("terrain")
	var player: Node3D = world.get("player")
	if terrain == null or player == null:
		return
	if _texture == null:
		_texture = world.call("map_texture")
	var rect := Rect2(Vector2.ZERO, size)
	# Sea past the edge of the map.
	draw_rect(rect, Color(0.16, 0.34, 0.5))
	var here := player.global_position
	var tex_size := _texture.get_size()
	var px_per_m := tex_size.x / (terrain.half_extent * 2.0)
	var centre_px := Vector2(here.x + terrain.half_extent, here.z + terrain.half_extent) * px_per_m
	var half_px := Vector2.ONE * SPAN * 0.5 * px_per_m
	var src := Rect2(centre_px - half_px, half_px * 2.0).intersection(Rect2(Vector2.ZERO, tex_size))
	if src.has_area():
		var to_dst := size.x / (half_px.x * 2.0)
		var dst := Rect2((src.position - (centre_px - half_px)) * to_dst, src.size * to_dst)
		draw_texture_rect_region(_texture, dst, src)

	# Found places, and the trucks.
	for poi in world.call("points_of_interest"):
		if world.call("discovered", poi.name):
			var at := _to_mini(poi.pos, here)
			if rect.has_point(at):
				_dot(at, poi.color, 4.0)
	for v in world.call("vehicles"):
		var truck := v as Hauler
		if truck == null or (player.get("vehicle") == truck):
			continue
		var at := _to_mini(truck.global_position, here)
		if rect.has_point(at):
			_square(at, truck.paint.lightened(0.2))
	# Home, the yard and the stores: on the rim when out of sight.
	var fixed := [
		["H", world.get("plot"), Color(0.55, 0.85, 0.50)],
		["$", world.get("depot"), Color(0.98, 0.80, 0.30)],
		["S", world.get("store"), Color(0.55, 0.78, 1.0)],
		["S", world.get("summit_store"), Color(0.7, 0.62, 1.0)],
	]
	for f in fixed:
		var node := f[1] as Node3D
		if node == null:
			continue
		var at := _to_mini(node.global_position, here)
		var inside := rect.grow(-10).has_point(at)
		if not inside:
			var from := size * 0.5
			var dir := (at - from).normalized()
			# Out to where the ray meets the rim, just inside it.
			var reach := minf(absf((size.x * 0.5 - 10) / maxf(absf(dir.x), 0.001)),
				absf((size.y * 0.5 - 10) / maxf(absf(dir.y), 0.001)))
			at = from + dir * reach
		draw_circle(at, 8.0, Color(0, 0, 0, 0.6))
		draw_circle(at, 6.5, f[2])
		_label(f[0], at + Vector2(0, 4.5), 11)

	# You.
	var cam: Camera3D = player.get("camera")
	var forward := -cam.global_transform.basis.z
	var heading := Vector2(forward.x, forward.z)
	heading = heading.normalized() if heading.length() > 0.05 else Vector2(0, -1)
	var mid := size * 0.5
	var side := Vector2(-heading.y, heading.x)
	var poly := PackedVector2Array([mid + heading * 10.0, mid - heading * 6.0 + side * 6.0,
		mid - heading * 2.5, mid - heading * 6.0 - side * 6.0])
	draw_colored_polygon(poly, Color(0, 0, 0, 0.65))
	var inner := PackedVector2Array()
	for p in poly:
		inner.append(mid + (p - mid) * 0.72)
	draw_colored_polygon(inner, UITheme.ACCENT)
	# North, and the frame.
	_label("N", Vector2(size.x * 0.5, 14), 13, UITheme.ACCENT)
	draw_rect(rect, Color(0, 0, 0, 0.55), false, 3.0)
	draw_rect(rect.grow(-1.5), Color(1, 1, 1, 0.14), false, 1.0)

func _dot(at: Vector2, color: Color, r: float) -> void:
	draw_circle(at, r + 1.5, Color(0, 0, 0, 0.6))
	draw_circle(at, r, color)

func _square(at: Vector2, color: Color) -> void:
	draw_rect(Rect2(at - Vector2(5, 5), Vector2(10, 10)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(at - Vector2(3.5, 3.5), Vector2(7, 7)), color)

func _label(text: String, at: Vector2, font_size: int, color: Color = UITheme.INK) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var p := at - Vector2(width * 0.5, 0)
	draw_string_outline(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.8))
	draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
