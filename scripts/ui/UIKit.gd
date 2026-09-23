class_name UIKit
extends RefCounted

## Small builders for the pieces every screen is made of, so the menus, the HUD
## and the journal all speak the same visual language without each hand-rolling
## a keycap.

const KEY_NAMES := ["LMB", "RMB", "MMB", "WASD", "SHIFT", "CTRL", "SPACE", "TAB",
	"ESC", "WHEEL", "ENTER", "ALT"]

static var _key_pattern: RegEx

# --- Text ------------------------------------------------------------------

static func label(text: String, variation: String = "", size: int = 0,
		color: Variant = null) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color != null:
		l.add_theme_color_override("font_color", color)
	return l

static func money(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-$" if amount < 0 else "$") + digits + out

static func clock(seconds: float) -> String:
	var s := maxi(0, int(seconds))
	return "%d:%02d" % [s / 60, s % 60]

## "3 minutes ago" from an ISO datetime string, as the save stamps it.
static func ago(iso: String) -> String:
	if iso == "":
		return ""
	var then := Time.get_unix_time_from_datetime_string(iso)
	var now := Time.get_unix_time_from_system()
	var d := int(now - then)
	if d < 0 or then <= 0:
		return ""
	if d < 60:
		return "just now"
	if d < 3600:
		return "%d min ago" % (d / 60)
	if d < 86400:
		return "%d h ago" % (d / 3600)
	return "%d days ago" % (d / 86400)

# --- Keys ------------------------------------------------------------------

## True for the contents of a bracket that name a key: "E", "LMB", "Shift+E",
## "R/T", "WASD". Not for "1/17" or "locked", which are just words in brackets.
static func is_key_text(inner: String) -> bool:
	var parts := inner.to_upper().replace("+", "/").split("/", false)
	if parts.is_empty():
		return false
	# "2/5" is a count, not two keys.
	if parts.size() > 1 and Array(parts).all(func(p: String): return p.strip_edges().is_valid_int()):
		return false
	for part in parts:
		var p := part.strip_edges()
		if p.length() == 1 and (p >= "A" and p <= "Z" or p >= "0" and p <= "9"):
			continue
		if p.begins_with("F") and p.length() <= 3 and p.substr(1).is_valid_int():
			continue
		if p in KEY_NAMES:
			continue
		return false
	return true

## Splits "Till: [E] pay $40" into [["text","Till: "],["key","E"],["text"," pay $40"]].
static func parse_keys(text: String) -> Array:
	if _key_pattern == null:
		_key_pattern = RegEx.new()
		_key_pattern.compile("\\[([^\\[\\]]{1,12})\\]")
	var out: Array = []
	var at := 0
	for m in _key_pattern.search_all(text):
		if not is_key_text(m.get_string(1)):
			continue
		if m.get_start() > at:
			out.append(["text", text.substr(at, m.get_start() - at)])
		out.append(["key", m.get_string(1)])
		at = m.get_end()
	if at < text.length():
		out.append(["text", text.substr(at)])
	return out

static func keycap(key: String, size: int = 14) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.theme_type_variation = "Keycap"
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = key.to_upper() if key.length() <= 3 else key
	l.add_theme_font_override("font", UITheme.font(800))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.10, 0.11, 0.10))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = size * 0.9
	cap.add_child(l)
	return cap

## A line of text with its [keys] drawn as keycaps, one row per line.
static func key_text(text: String, size: int = 17, color: Color = UITheme.INK) -> VBoxContainer:
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	fill_key_text(rows, text, size, color)
	return rows

static func fill_key_text(rows: VBoxContainer, text: String, size: int = 17,
		color: Color = UITheme.INK) -> void:
	for child in rows.get_children():
		child.queue_free()
	for line in text.split("\n"):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 5)
		for part in parse_keys(line):
			if part[0] == "key":
				row.add_child(keycap(part[1], maxi(11, size - 3)))
			else:
				var words: String = part[1].strip_edges()
				if words != "":
					row.add_child(label(words, "", size, color))
		rows.add_child(row)

## A row for the controls reference: the keys on the left, what they do after.
static func binding_row(keys: Array, action: String, size: int = 15,
		wrap: bool = true) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var caps := HBoxContainer.new()
	caps.add_theme_constant_override("separation", 4)
	caps.custom_minimum_size.x = 150
	for k in keys:
		if k == "/":
			caps.add_child(label("/", "Small"))
		else:
			caps.add_child(keycap(String(k), size - 2))
	row.add_child(caps)
	var what := label(action, "", size)
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if wrap:
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(what)
	return row

# --- Structure -------------------------------------------------------------

static func vbox(separation: int = 8) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	return b

static func hbox(separation: int = 8) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	return b

static func panel(variation: String = "Card") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	return p

static func spacer(expand: bool = true, min_size: float = 0.0) -> Control:
	var c := Control.new()
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(min_size, min_size)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func button(text: String, on_press: Callable, variation: String = "") -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b

static func bar(fraction: float, color: Color = UITheme.GOOD, height: float = 6.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0.0
	p.max_value = 1.0
	p.step = 0.0
	p.value = clampf(fraction, 0.0, 1.0)
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, height)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint_bar(p, color)
	return p

static func tint_bar(p: ProgressBar, color: Color) -> void:
	var fill := UITheme.box(color, 4, Vector4.ZERO, UITheme.EDGE, 0)
	p.add_theme_stylebox_override("fill", fill)

## A full-rect control on a CanvasLayer.
static func fill(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0
	return c

## Frosted glass: whatever is behind, blurred and darkened. Mipmapped screen
## reads are cheap and work on both renderers.
static func frosted(dim: float = 0.45, blur: float = 2.6) -> ColorRect:
	var rect := ColorRect.new()
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur = 2.6;
uniform float dim = 0.45;
uniform vec4 tint : source_color = vec4(0.03, 0.05, 0.04, 1.0);
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, blur).rgb;
	// A soft vignette, so the edges fall away and the middle reads.
	float v = smoothstep(1.15, 0.25, length(UV - 0.5) * 1.4);
	COLOR = vec4(mix(c, tint.rgb, dim + (1.0 - v) * 0.25), 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("blur", blur)
	mat.set_shader_parameter("dim", dim)
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	fill(rect)
	return rect

## A modal yes/no over everything, built on demand and gone when answered.
static func confirm(host: Node, title: String, body: String, yes_text: String,
		on_yes: Callable, danger: bool = true) -> Control:
	var root := Control.new()
	root.theme = UITheme.theme()
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	fill(root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	fill(shade)
	root.add_child(shade)
	var center := CenterContainer.new()
	fill(center)
	root.add_child(center)
	var card := panel("WindowPanel")
	card.custom_minimum_size = Vector2(460, 0)
	center.add_child(card)
	var col := vbox(14)
	card.add_child(col)
	col.add_child(label(title, "Header"))
	var text := label(body, "Muted", 17)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(text)
	var row := hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_END
	var no := button("Cancel", func(): root.queue_free(), "Ghost")
	row.add_child(no)
	var yes := button(yes_text, func():
		root.queue_free()
		on_yes.call())
	if danger:
		yes.add_theme_color_override("font_color", UITheme.BAD)
	row.add_child(yes)
	col.add_child(row)
	host.add_child(root)
	no.grab_focus.call_deferred()
	return root
