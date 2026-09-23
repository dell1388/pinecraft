class_name UITheme
extends RefCounted

## One look for every screen: the fonts, the palette and the Theme built from
## them. Built in code, like the rest of the game, so there is no .tres to drift
## out of step with the scripts that use it.
##
## Type variations callers can ask for by name:
##   Label:          Title, Header, Subheader, Muted, Small, Money
##   PanelContainer: Card, WindowPanel, Keycap, Pill, Toast, Row
##   Button:         Big, Ghost, Tab

const INK := Color(0.95, 0.94, 0.89)
const MUTED := Color(0.66, 0.70, 0.66)
const FAINT := Color(0.46, 0.50, 0.47)
const ACCENT := Color(0.98, 0.74, 0.30)        ## amber: selection, focus, warnings
const GOOD := Color(0.49, 0.83, 0.47)          ## money in, done, allowed
const BAD := Color(0.95, 0.42, 0.36)           ## blocked, money out
const INFO := Color(0.50, 0.74, 0.96)
const PANEL := Color(0.055, 0.075, 0.065, 0.88)
const PANEL_SOLID := Color(0.075, 0.095, 0.085, 0.97)
const EDGE := Color(1.0, 1.0, 1.0, 0.09)
const RAISED := Color(0.13, 0.16, 0.145, 0.95)

const FONT_DIR := "res://assets/fonts/"

static var _theme: Theme
static var _fonts: Dictionary = {}

## Rubik at 400, 600 or 800.
static func font(weight: int = 400) -> Font:
	var key := "Rubik-%d" % weight
	if not _fonts.has(key):
		_fonts[key] = _load_font(FONT_DIR + key + ".woff2")
	return _fonts[key]

## Lilita One: the logo and the big numbers.
static func display_font() -> Font:
	if not _fonts.has("display"):
		_fonts["display"] = _load_font(FONT_DIR + "LilitaOne.woff2")
	return _fonts["display"]

## The raw file when it is there (running from the project folder, imported or
## not), the imported resource when it is not (an exported build), and the
## engine's own font if neither - a missing font should cost looks, not a crash.
static func _load_font(path: String) -> Font:
	var loaded: Font = null
	if FileAccess.file_exists(path):
		var file := FontFile.new()
		if file.load_dynamic_font(path) == OK:
			loaded = file
	elif ResourceLoader.exists(path):
		loaded = load(path) as Font
	if loaded == null:
		return ThemeDB.fallback_font
	# The subset is Latin only; anything else drops through to the engine font.
	var fallback := ThemeDB.fallback_font
	if fallback != null and loaded is FontFile:
		(loaded as FontFile).fallbacks = [fallback]
	return loaded

static func theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme

static func box(bg: Color, radius: int = 10, pad: Vector4 = Vector4(14, 10, 14, 10),
		border: Color = EDGE, border_width: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	if border_width > 0:
		s.border_color = border
		s.set_border_width_all(border_width)
	s.anti_aliasing = true
	return s

static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = font(400)
	t.default_font_size = 17

	# --- Labels
	t.set_color("font_color", "Label", INK)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 1)
	_variation(t, "Title", "Label")
	t.set_font("font", "Title", display_font())
	t.set_font_size("font_size", "Title", 108)
	t.set_color("font_color", "Title", INK)
	t.set_color("font_outline_color", "Title", Color(0.05, 0.08, 0.06, 0.9))
	t.set_constant("outline_size", "Title", 14)
	t.set_color("font_shadow_color", "Title", Color(0, 0, 0, 0.45))
	t.set_constant("shadow_offset_y", "Title", 6)
	_variation(t, "Header", "Label")
	t.set_font("font", "Header", display_font())
	t.set_font_size("font_size", "Header", 30)
	t.set_color("font_color", "Header", INK)
	_variation(t, "Subheader", "Label")
	t.set_font("font", "Subheader", font(600))
	t.set_font_size("font_size", "Subheader", 13)
	t.set_color("font_color", "Subheader", ACCENT)
	_variation(t, "Muted", "Label")
	t.set_color("font_color", "Muted", MUTED)
	t.set_font_size("font_size", "Muted", 15)
	_variation(t, "Small", "Label")
	t.set_color("font_color", "Small", MUTED)
	t.set_font_size("font_size", "Small", 13)
	_variation(t, "Money", "Label")
	t.set_font("font", "Money", display_font())
	t.set_font_size("font_size", "Money", 38)
	t.set_color("font_color", "Money", Color(0.93, 0.97, 0.82))
	t.set_color("font_outline_color", "Money", Color(0, 0, 0, 0.5))
	t.set_constant("outline_size", "Money", 6)

	t.set_color("default_color", "RichTextLabel", INK)
	t.set_font("normal_font", "RichTextLabel", font(400))
	t.set_font("bold_font", "RichTextLabel", font(600))
	t.set_font_size("normal_font_size", "RichTextLabel", 17)
	t.set_font_size("bold_font_size", "RichTextLabel", 17)

	# --- Panels
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 12))
	t.set_stylebox("panel", "Panel", box(PANEL, 12))
	_variation(t, "Card", "PanelContainer")
	t.set_stylebox("panel", "Card", box(PANEL, 14, Vector4(18, 14, 18, 14)))
	_variation(t, "WindowPanel", "PanelContainer")
	var window := box(PANEL_SOLID, 18, Vector4(28, 22, 28, 24), Color(1, 1, 1, 0.12))
	window.shadow_color = Color(0, 0, 0, 0.45)
	window.shadow_size = 26
	window.shadow_offset = Vector2(0, 8)
	t.set_stylebox("panel", "WindowPanel", window)
	_variation(t, "Keycap", "PanelContainer")
	var cap := box(Color(0.92, 0.91, 0.86), 6, Vector4(7, 1, 7, 2), Color(0.55, 0.55, 0.5), 0)
	cap.border_width_bottom = 3
	cap.border_color = Color(0.58, 0.57, 0.52)
	t.set_stylebox("panel", "Keycap", cap)
	_variation(t, "Pill", "PanelContainer")
	t.set_stylebox("panel", "Pill", box(PANEL, 22, Vector4(18, 8, 18, 9)))
	_variation(t, "Toast", "PanelContainer")
	t.set_stylebox("panel", "Toast", box(PANEL, 9, Vector4(12, 6, 14, 7)))
	_variation(t, "Row", "PanelContainer")
	t.set_stylebox("panel", "Row", box(Color(1, 1, 1, 0.035), 10, Vector4(14, 9, 14, 9), EDGE, 0))

	# --- Buttons
	t.set_font("font", "Button", font(600))
	t.set_font_size("font_size", "Button", 17)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", Color(0.08, 0.08, 0.06))
	t.set_color("font_focus_color", "Button", Color(1, 1, 1))
	t.set_color("font_disabled_color", "Button", FAINT)
	t.set_stylebox("normal", "Button", box(RAISED, 10, Vector4(18, 9, 18, 10)))
	t.set_stylebox("hover", "Button", box(Color(0.20, 0.25, 0.22, 0.98), 10,
		Vector4(18, 9, 18, 10), Color(ACCENT, 0.55)))
	t.set_stylebox("pressed", "Button", box(ACCENT, 10, Vector4(18, 9, 18, 10), ACCENT))
	t.set_stylebox("disabled", "Button", box(Color(0.1, 0.12, 0.11, 0.7), 10,
		Vector4(18, 9, 18, 10), Color(1, 1, 1, 0.04)))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 10, Vector4(18, 9, 18, 10),
		Color(ACCENT, 0.9), 2))

	_variation(t, "Big", "Button")
	t.set_font("font", "Big", display_font())
	t.set_font_size("font_size", "Big", 30)
	t.set_constant("h_separation", "Big", 12)
	var big_pad := Vector4(26, 8, 26, 10)
	t.set_stylebox("normal", "Big", box(Color(0.06, 0.08, 0.07, 0.72), 12, big_pad, Color(1, 1, 1, 0.07)))
	t.set_stylebox("hover", "Big", box(Color(0.14, 0.18, 0.15, 0.94), 12, big_pad, Color(ACCENT, 0.9), 2))
	t.set_stylebox("pressed", "Big", box(ACCENT, 12, big_pad, ACCENT))
	t.set_stylebox("disabled", "Big", box(Color(0.06, 0.08, 0.07, 0.45), 12, big_pad, Color(1, 1, 1, 0.03)))
	t.set_stylebox("focus", "Big", box(Color(0, 0, 0, 0), 12, big_pad, Color(ACCENT, 0.9), 2))

	_variation(t, "Ghost", "Button")
	var ghost_pad := Vector4(12, 6, 12, 7)
	t.set_stylebox("normal", "Ghost", box(Color(0, 0, 0, 0), 8, ghost_pad, Color(0, 0, 0, 0), 0))
	t.set_stylebox("hover", "Ghost", box(Color(1, 1, 1, 0.07), 8, ghost_pad, Color(0, 0, 0, 0), 0))
	t.set_stylebox("pressed", "Ghost", box(Color(1, 1, 1, 0.12), 8, ghost_pad, Color(0, 0, 0, 0), 0))
	t.set_stylebox("focus", "Ghost", box(Color(0, 0, 0, 0), 8, ghost_pad, Color(ACCENT, 0.7), 1))
	t.set_color("font_color", "Ghost", MUTED)
	t.set_color("font_pressed_color", "Ghost", INK)

	_variation(t, "Tab", "Button")
	var tab_pad := Vector4(16, 7, 16, 8)
	t.set_stylebox("normal", "Tab", box(Color(0, 0, 0, 0), 9, tab_pad, Color(0, 0, 0, 0), 0))
	t.set_stylebox("hover", "Tab", box(Color(1, 1, 1, 0.06), 9, tab_pad, Color(0, 0, 0, 0), 0))
	t.set_stylebox("pressed", "Tab", box(Color(ACCENT, 0.16), 9, tab_pad, Color(ACCENT, 0.7), 1))
	t.set_stylebox("hover_pressed", "Tab", box(Color(ACCENT, 0.22), 9, tab_pad, Color(ACCENT, 0.8), 1))
	t.set_stylebox("focus", "Tab", box(Color(0, 0, 0, 0), 9, tab_pad, Color(ACCENT, 0.5), 1))
	t.set_color("font_color", "Tab", MUTED)
	t.set_color("font_pressed_color", "Tab", ACCENT)
	t.set_color("font_hover_pressed_color", "Tab", ACCENT)

	# --- Inputs
	t.set_stylebox("slider", "HSlider", box(Color(1, 1, 1, 0.10), 4, Vector4(0, 3, 0, 3), EDGE, 0))
	t.set_stylebox("grabber_area", "HSlider", box(Color(ACCENT, 0.85), 4, Vector4(0, 3, 0, 3), EDGE, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, 4, Vector4(0, 3, 0, 3), EDGE, 0))
	t.set_icon("grabber", "HSlider", _dot(18, INK))
	t.set_icon("grabber_highlight", "HSlider", _dot(20, Color(1, 1, 1)))

	t.set_font("font", "CheckButton", font(400))
	t.set_color("font_color", "CheckButton", INK)
	t.set_color("font_hover_color", "CheckButton", Color(1, 1, 1))
	t.set_color("font_pressed_color", "CheckButton", INK)
	t.set_color("font_hover_pressed_color", "CheckButton", Color(1, 1, 1))
	t.set_color("font_focus_color", "CheckButton", Color(1, 1, 1))
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		t.set_stylebox(state, "CheckButton", box(Color(0, 0, 0, 0), 6, Vector4(0, 2, 0, 2),
			Color(ACCENT, 0.6) if state == "focus" else Color(0, 0, 0, 0), 1 if state == "focus" else 0))
	t.set_icon("checked", "CheckButton", _switch(true))
	t.set_icon("unchecked", "CheckButton", _switch(false))

	t.set_stylebox("normal", "OptionButton", box(RAISED, 8, Vector4(12, 6, 30, 7)))
	t.set_stylebox("hover", "OptionButton", box(Color(0.20, 0.25, 0.22, 0.98), 8, Vector4(12, 6, 30, 7), Color(ACCENT, 0.5)))
	t.set_stylebox("pressed", "OptionButton", box(RAISED, 8, Vector4(12, 6, 30, 7), ACCENT))
	t.set_stylebox("focus", "OptionButton", box(Color(0, 0, 0, 0), 8, Vector4(12, 6, 30, 7), Color(ACCENT, 0.8), 2))
	t.set_color("font_color", "OptionButton", INK)
	t.set_color("font_pressed_color", "OptionButton", INK)
	t.set_stylebox("panel", "PopupMenu", box(PANEL_SOLID, 8, Vector4(6, 6, 6, 6), Color(1, 1, 1, 0.14)))
	t.set_stylebox("hover", "PopupMenu", box(Color(ACCENT, 0.22), 6, Vector4(8, 4, 8, 4), EDGE, 0))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", Color(1, 1, 1))

	# --- Bars and scrolling
	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.09), 4, Vector4.ZERO, EDGE, 0))
	t.set_stylebox("fill", "ProgressBar", box(GOOD, 4, Vector4.ZERO, EDGE, 0))
	t.set_constant("outline_size", "ProgressBar", 0)
	t.set_font_size("font_size", "ProgressBar", 1)
	t.set_color("font_color", "ProgressBar", Color(0, 0, 0, 0))
	t.set_stylebox("scroll", "VScrollBar", box(Color(1, 1, 1, 0.04), 4, Vector4(4, 0, 4, 0), EDGE, 0))
	t.set_stylebox("grabber", "VScrollBar", box(Color(1, 1, 1, 0.18), 4, Vector4(4, 0, 4, 0), EDGE, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(1, 1, 1, 0.3), 4, Vector4(4, 0, 4, 0), EDGE, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(ACCENT, 4, Vector4(4, 0, 4, 0), EDGE, 0))
	t.set_stylebox("panel", "TooltipPanel", box(PANEL_SOLID, 8, Vector4(10, 6, 10, 7), Color(1, 1, 1, 0.14)))
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_stylebox("separator", "HSeparator", box(Color(1, 1, 1, 0.08), 0, Vector4.ZERO, EDGE, 0))
	t.set_constant("separation", "HSeparator", 14)
	return t

static func _variation(t: Theme, name: String, base: String) -> void:
	t.add_type(name)
	t.set_type_variation(name, base)

static func _dot(size: int, color: Color) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			img.set_pixel(x, y, Color(color, clampf(r - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

## A pill switch, drawn rather than shipped.
static func _switch(on: bool) -> Texture2D:
	var w := 44
	var h := 24
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := ACCENT if on else Color(1, 1, 1, 0.16)
	var knob_x := w - h * 0.5 if on else h * 0.5
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			# Distance to the capsule's spine.
			var spine := Vector2(clampf(p.x, h * 0.5, w - h * 0.5), h * 0.5)
			var track_a := clampf(h * 0.5 - p.distance_to(spine), 0.0, 1.0)
			var knob_a := clampf(h * 0.5 - 3.0 - p.distance_to(Vector2(knob_x, h * 0.5)), 0.0, 1.0)
			var c := Color(track, track.a * track_a)
			if knob_a > 0.0:
				c = c.blend(Color(1, 1, 1, knob_a))
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
