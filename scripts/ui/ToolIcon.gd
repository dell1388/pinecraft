class_name ToolIcon
extends Control

## A flat drawing of a tool for the hotbar and the inventory: the handle on a
## slant and the head in the tool's own colour, so an ember axe and a rusty
## one are told apart at a glance.

var tool_id: StringName = &"":
	set(value):
		tool_id = value
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(44, 44)

func _draw() -> void:
	var def := GameData.tool(tool_id)
	if def.is_empty():
		return
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var head := ToolModel.color_of(def)
	var handle := ToolModel._color(def.get("handle", [0.5, 0.35, 0.2]))
	var a := o + Vector2(0.22, 0.86) * s
	var b := o + Vector2(0.70, 0.22) * s
	draw_line(a, b, Color(0, 0, 0, 0.6), s * 0.13, true)
	draw_line(a, b, handle, s * 0.08, true)
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x)
	if String(def.get("kind", "")) == "hammer":
		var c := b
		var w := s * 0.22
		var h := s * 0.13
		var pts := PackedVector2Array([c + side * w + dir * h, c + side * w - dir * h,
			c - side * w - dir * h, c - side * w + dir * h])
		draw_colored_polygon(pts, head)
		pts.append(pts[0])
		draw_polyline(pts, Color(0, 0, 0, 0.6), 1.5, true)
	else:
		var sides := [1.0, -1.0] if bool(def.get("twin", false)) else [1.0]
		for k in sides:
			var root := b - dir * s * 0.02
			var pts := PackedVector2Array([root + dir * s * 0.07, root - dir * s * 0.07,
				root - side * k * s * 0.28 - dir * s * 0.16, root - side * k * s * 0.3 + dir * s * 0.14])
			draw_colored_polygon(pts, head)
			pts.append(pts[0])
			draw_polyline(pts, Color(0, 0, 0, 0.6), 1.5, true)
	if bool(def.get("glow", false)):
		draw_circle(b, s * 0.34, Color(head.r, head.g, head.b, 0.18))
