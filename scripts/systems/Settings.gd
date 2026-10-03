extends Node

## Player preferences: kept apart from the save, because a new game should not
## throw away your mouse sensitivity. Autoloaded as `Settings`.
##
## They live in one personal config file, `user://config.cfg`, together with
## the key bindings: every primary setting and every control, each with a
## comment saying what it is, so it can be read and edited by hand as easily as
## from the Settings screen. (On Windows that is
## %APPDATA%/Godot/app_userdata/Pinecraft/config.cfg; Settings has a button that
## opens the folder.)
##
## Anything that reads a setting either asks for it when it needs it (mouse
## look) or listens to `changed` (the camera, the sun, the environment), so a
## slider moved in the pause menu shows its effect with the menu still open.

signal changed(key: StringName)
signal controls_changed

const PATH := "user://config.cfg"
## Where settings were kept before there was one config file; read once if the
## new file is not there yet.
const LEGACY_PATH := "user://settings.cfg"
const SECTION := "settings"
const CONTROLS := "controls"

## Every setting and its default. The type of the default is the type of the
## setting; `set_value` coerces to it.
const DEFAULTS := {
	# Controls
	&"mouse_sensitivity": 1.0,
	&"invert_y": false,
	&"fov": 75.0,
	&"manual_gearbox": false,
	&"toggle_sprint": false,
	&"third_person": false,
	# Video
	&"fullscreen": false,
	&"vsync": true,
	&"render_scale": 1.0,
	&"quality": 2,            ## 0 low, 1 medium, 2 high, 3 custom
	&"shadows": 2,            ## 0 off, 1 low, 2 high
	&"anti_aliasing": 2,      ## 0 off, 1 FXAA, 2 MSAA 2x
	&"ambient_occlusion": true,
	&"bloom": true,
	&"view_distance": 600.0,
	&"moving_sun": true,
	&"shaders": true,         ## swaying grass and trees, leafy trees, grassy ground
	&"grass": 2,              ## 0 off, 1 short range, 2 far
	&"birds": true,
	# Interface
	&"ui_scale": 1.0,
	&"show_hints": true,
	&"show_rig_banner": true,
	&"minimap": true,
	&"minimap_zoom": 1,       ## 0 close .. 3 far
	&"minimap_rotate": false,
	&"show_compass": true,
	&"show_tutorial": true,
	&"show_fps": false,
	&"show_labels": false,
	# Game
	&"autosave": true,
	# Co-op: remembered from the last time
	&"player_name": "Player",
	&"last_address": "",
	# Sound
	&"music_volume": 0.5,
	&"sfx_volume": 0.8,
	# Debug
	&"unlimited_money": false,
	&"demo_lines": false,
}

## What each setting is, for the comments in the config file.
const NOTES := {
	&"player_name": "Your name in co-op",
	&"last_address": "The host you joined last, as typed",
	&"mouse_sensitivity": "Mouse look speed, 0.2 to 3.0",
	&"invert_y": "true to invert the mouse's up and down",
	&"fov": "Field of view in degrees, 60 to 100",
	&"toggle_sprint": "true: tap sprint to run until you tap it again or stop. false: hold it",
	&"manual_gearbox": "true: trucks change gear only when you do (gear up / gear down keys). false: automatic",
	&"third_person": "true: on foot, look over his shoulder instead of out of his eyes (camera-view key)",
	&"fullscreen": "true for fullscreen",
	&"vsync": "true to sync to the monitor",
	&"render_scale": "3D resolution as a share of the window, 0.5 to 1.0",
	&"quality": "Graphics preset: 0 low, 1 medium, 2 high, 3 custom (set by changing any video setting)",
	&"shadows": "0 off, 1 low, 2 high",
	&"anti_aliasing": "Smoothing of jagged edges: 0 off, 1 FXAA (cheap), 2 MSAA 2x",
	&"ambient_occlusion": "Screen-space ambient occlusion",
	&"bloom": "Glow round bright things",
	&"view_distance": "How far you can see, in metres (150 to 1200)",
	&"moving_sun": "false keeps it mid-morning all day",
	&"shaders": "true: grass and trees sway in the wind, leaves look leafy, the ground looks grassy. false: plain and flat (a little quicker)",
	&"grass": "Grass and flowers over the ground round you: 0 off, 1 short range, 2 far",
	&"birds": "Birds in the sky",
	&"ui_scale": "Interface size, 0.75 to 1.5",
	&"show_hints": "Key hints in the bottom-right corner",
	&"show_rig_banner": "The crane / winch / loader controls banner while driving",
	&"minimap": "The minimap under the money",
	&"minimap_zoom": "Minimap zoom, 0 (closest) to 3 (furthest)",
	&"minimap_rotate": "true: the minimap turns with you, what is ahead at the top. false: north up",
	&"show_compass": "The compass along the top",
	&"show_tutorial": "The getting-started checklist",
	&"show_fps": "Frame rate readout",
	&"show_labels": "Floating name labels over placed buildings",
	&"autosave": "Save every minute while playing",
	&"music_volume": "Music volume, 0 to 1",
	&"sfx_volume": "Sound effects volume, 0 to 1",
	&"unlimited_money": "Debug: buying costs nothing",
	&"demo_lines": "Debug: automated demo lines south of home",
}

## The graphics presets: what each sets. Low is for integrated graphics and
## older cards; High is everything on.
const PRESETS := [
	{&"shadows": 1, &"ambient_occlusion": false, &"bloom": false, &"anti_aliasing": 1, &"render_scale": 0.8, &"view_distance": 400.0,
		&"shaders": false, &"grass": 1},
	{&"shadows": 1, &"ambient_occlusion": false, &"bloom": true, &"anti_aliasing": 1, &"render_scale": 1.0, &"view_distance": 500.0,
		&"shaders": true, &"grass": 1},
	{&"shadows": 2, &"ambient_occlusion": true, &"bloom": true, &"anti_aliasing": 2, &"render_scale": 1.0, &"view_distance": 600.0,
		&"shaders": true, &"grass": 2},
]
const PRESET_KEYS := [&"shadows", &"ambient_occlusion", &"bloom", &"anti_aliasing", &"render_scale", &"view_distance",
	&"shaders", &"grass"]
var _applying_preset: bool = false

## Sets every video setting from a preset (0 low, 1 medium, 2 high).
func apply_preset(i: int) -> void:
	if i < 0 or i >= PRESETS.size():
		return
	_applying_preset = true
	for key in PRESETS[i]:
		set_value(key, PRESETS[i][key], false)
	_applying_preset = false
	set_value(&"quality", i)

## Where the settings live. Tests point this somewhere disposable.
var path: String = PATH
var _values: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_from(path)
	# Everything but fullscreen now; fullscreen once the window is up (see
	# _place_window), because switched on this early, as the game starts, the
	# window can come up screen-sized but still where the plain window was
	# put - hanging off the bottom and right of the screen.
	_starting = true
	apply_display()
	_starting = false
	_place_window.call_deferred()

var _starting: bool = false
var _placing: bool = false

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
	if key in PRESET_KEYS and not _applying_preset and int(_values.get(&"quality", 2)) != 3:
		# Changing one video setting by hand makes the preset "custom".
		_values[&"quality"] = 3
		changed.emit(&"quality")
	if key in [&"fullscreen", &"vsync", &"render_scale", &"ui_scale", &"anti_aliasing"]:
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

## Puts every key back where it started, and saves.
func reset_controls() -> void:
	Controls.reset()
	controls_changed.emit()
	save_to(path)

## Rebinds one action and saves.
func bind(action: StringName, labels: Array) -> void:
	Controls.set_binding(action, labels)
	controls_changed.emit()
	save_to(path)

func load_from(p: String) -> void:
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	var err := cfg.load(p)
	if err != OK and p == PATH and FileAccess.file_exists(LEGACY_PATH):
		err = cfg.load(LEGACY_PATH)
	if err != OK:
		Controls.apply({})
		controls_changed.emit()
		return
	for key in DEFAULTS:
		if cfg.has_section_key(SECTION, String(key)):
			_values[key] = _coerce(DEFAULTS[key], cfg.get_value(SECTION, String(key)))
	var keys := {}
	if cfg.has_section(CONTROLS):
		for k in cfg.get_section_keys(CONTROLS):
			keys[k] = cfg.get_value(CONTROLS, k)
	Controls.apply(keys)
	controls_changed.emit()

## Reads the file again, for after it has been edited by hand.
func reload() -> void:
	load_from(path)
	apply_display()
	for key in DEFAULTS:
		changed.emit(key)

## Written as text rather than through ConfigFile, so it keeps a comment on
## every line saying what the value is. ConfigFile still reads it.
func save_to(p: String) -> bool:
	var lines: Array[String] = [
		"; Pinecraft - your personal config: settings and controls.",
		"; Edit a value and save; the game reads this file when it starts, and",
		"; Settings > Reload config file picks up changes without restarting.",
		"; Delete a line (or the whole file) to go back to the default.",
		"",
		"[%s]" % SECTION,
		""]
	for key in DEFAULTS:
		lines.append("; %s (default %s)" % [NOTES.get(key, String(key)), var_to_str(DEFAULTS[key])])
		lines.append("%s=%s" % [String(key), var_to_str(value(key))])
	lines.append("")
	lines.append("[%s]" % CONTROLS)
	lines.append("")
	lines.append("; action=\"Key, Other key\". Keys are written as shown on the Controls page:")
	lines.append("; letters and digits, Shift, Ctrl, Alt, Space, Tab, Esc, Enter, Del, Backspace,")
	lines.append("; F1-F12, Up, Down, Left, Right, Kp 1 (keypad), and the mouse: LMB, RMB, MMB,")
	lines.append("; WheelUp, WheelDown, Mouse4, Mouse5. A combination is Shift+E. Empty means unbound.")
	var group := ""
	var bound := Controls.to_dict()
	for a in Controls.ACTIONS:
		if String(a[2]) != group:
			group = String(a[2])
			lines.append("")
			lines.append("; --- %s" % group)
		lines.append("; %s (default %s)" % [a[1], ", ".join(PackedStringArray(a[3]))])
		lines.append("%s=%s" % [String(a[0]), var_to_str(String(bound.get(String(a[0]), "")))])
	var file := FileAccess.open(p, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string("\n".join(lines) + "\n")
	file.close()
	return true

## The folder the config file is in, for the button that opens it.
func config_folder() -> String:
	return ProjectSettings.globalize_path(path.get_base_dir())

func open_config_folder() -> void:
	if not FileAccess.file_exists(path):
		save_to(path)
	OS.shell_open(config_folder())

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

## Fullscreen or a plain window, as set, and then a check that it is where it
## should be. Run in the editor's Game view the editor owns the window - where
## it is and how big - so it is left alone.
func _set_window_mode(window: Window) -> void:
	if Engine.is_embedded_in_editor():
		return
	var fullscreen: bool = value(&"fullscreen")
	if (window.mode == Window.MODE_FULLSCREEN) != fullscreen:
		window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
		_place_window.call_deferred()

## Once the window is up: the mode as set, then, a few frames on, a look at
## where the window actually is. Fullscreen has to cover its screen from the
## screen's corner; if it came up anywhere else it goes back to a window,
## centred, and fullscreen again from there. A plain window has to fit on its
## screen; if it hangs off, it is shrunk to fit and centred.
func _place_window() -> void:
	if _placing or DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	_placing = true
	var window := get_window()
	_set_window_mode(window)
	for i in 3:
		await get_tree().process_frame
	_placing = false
	if Engine.is_embedded_in_editor():
		return
	var screen := window.current_screen
	var origin := DisplayServer.screen_get_position(screen)
	var screen_size := DisplayServer.screen_get_size(screen)
	if window.mode == Window.MODE_FULLSCREEN:
		if (window.position - origin).length() <= 2:
			return
		window.mode = Window.MODE_WINDOWED
		await get_tree().process_frame
		window.size = _windowed_size(screen_size)
		window.position = origin + (screen_size - window.size) / 2
		await get_tree().process_frame
		window.mode = Window.MODE_FULLSCREEN
	elif window.mode == Window.MODE_WINDOWED:
		var usable := DisplayServer.screen_get_usable_rect(screen)
		if usable.grow(8).encloses(Rect2i(window.get_position_with_decorations(), window.get_size_with_decorations())):
			return
		window.size = _windowed_size(usable.size)
		window.move_to_center()

## The window's own size (the project's), no bigger than 90% of the room.
func _windowed_size(room: Vector2i) -> Vector2i:
	var want := Vector2i(int(ProjectSettings.get_setting("display/window/size/viewport_width", 1600)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 900)))
	var fit := minf(1.0, minf(float(room.x) * 0.9 / float(want.x), float(room.y) * 0.9 / float(want.y)))
	return Vector2i(int(float(want.x) * fit), int(float(want.y) * fit))

## Window-level settings. A headless run has no window to change.
func apply_display() -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var window := get_window()
	if not _starting:
		_set_window_mode(window)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if value(&"vsync") else DisplayServer.VSYNC_DISABLED)
	window.scaling_3d_scale = clampf(float(value(&"render_scale")), 0.5, 1.0)
	# Below full resolution, FSR sharpens the upscale (Forward+ and Mobile only).
	var method := RenderingServer.get_current_rendering_method()
	if method == "forward_plus" or method == "mobile":
		window.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if window.scaling_3d_scale < 0.99 \
			else Viewport.SCALING_3D_MODE_BILINEAR
	var aa := int(value(&"anti_aliasing"))
	window.msaa_3d = Viewport.MSAA_2X if aa >= 2 else Viewport.MSAA_DISABLED
	window.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	window.content_scale_factor = clampf(float(value(&"ui_scale")), 0.75, 1.5)
