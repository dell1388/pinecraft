extends Node

## Player preferences: kept apart from the save, because a new game should not
## throw away your mouse sensitivity. Autoloaded as `Settings`.
##
## Anything that reads a setting either asks for it when it needs it (mouse
## look) or listens to `changed` (the camera, the sun, the environment), so a
## slider moved in the pause menu shows its effect with the menu still open.

signal changed(key: StringName)

const PATH := "user://settings.cfg"
const SECTION := "settings"

## Every setting and its default. The type of the default is the type of the
## setting; `set_value` coerces to it.
const DEFAULTS := {
	# Controls
	&"mouse_sensitivity": 1.0,
	&"invert_y": false,
	&"fov": 75.0,
	# Video
	&"fullscreen": false,
	&"vsync": true,
	&"render_scale": 1.0,
	&"shadows": 2,            ## 0 off, 1 low, 2 high
	&"ambient_occlusion": true,
	&"bloom": true,
	&"view_distance": 600.0,
	&"moving_sun": true,
	# Interface
	&"ui_scale": 1.0,
	&"show_hints": true,
	&"minimap": true,
	&"show_compass": true,
	&"show_tutorial": true,
	&"show_fps": false,
	# Game
	&"autosave": true,
	# Debug
	&"unlimited_money": false,
	&"demo_lines": false,
}

## Where the settings live. Tests point this somewhere disposable.
var path: String = PATH
var _values: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_from(path)
	apply_display()

func value(key: StringName) -> Variant:
	return _values.get(key, DEFAULTS.get(key))

func set_value(key: StringName, v: Variant, persist: bool = true) -> void:
	if not DEFAULTS.has(key):
		push_warning("Settings: unknown key %s" % key)
		return
	var coerced: Variant = _coerce(DEFAULTS[key], v)
	if _values.get(key) == coerced:
		return
	_values[key] = coerced
	if key in [&"fullscreen", &"vsync", &"render_scale", &"ui_scale"]:
		apply_display()
	changed.emit(key)
	if persist:
		save_to(path)

func reset_to_defaults() -> void:
	_values = DEFAULTS.duplicate()
	apply_display()
	for key in DEFAULTS:
		changed.emit(key)
	save_to(path)

func load_from(p: String) -> void:
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(p) != OK:
		return
	for key in DEFAULTS:
		if cfg.has_section_key(SECTION, String(key)):
			_values[key] = _coerce(DEFAULTS[key], cfg.get_value(SECTION, String(key)))

func save_to(p: String) -> bool:
	var cfg := ConfigFile.new()
	for key in _values:
		cfg.set_value(SECTION, String(key), _values[key])
	return cfg.save(p) == OK

static func _coerce(like: Variant, v: Variant) -> Variant:
	match typeof(like):
		TYPE_BOOL:
			return bool(v)
		TYPE_INT:
			return int(v)
		TYPE_FLOAT:
			return float(v)
	return v

# --- Convenience -----------------------------------------------------------

func mouse_scale() -> float:
	return float(value(&"mouse_sensitivity"))

func invert_y() -> bool:
	return bool(value(&"invert_y"))

func flag(key: StringName) -> bool:
	return bool(value(key))

## Window-level settings. A headless run has no window to change.
func apply_display() -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var window := get_window()
	var fullscreen: bool = value(&"fullscreen")
	if (window.mode == Window.MODE_FULLSCREEN) != fullscreen:
		window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if value(&"vsync") else DisplayServer.VSYNC_DISABLED)
	window.scaling_3d_scale = clampf(float(value(&"render_scale")), 0.5, 1.0)
	window.content_scale_factor = clampf(float(value(&"ui_scale")), 0.75, 1.5)
