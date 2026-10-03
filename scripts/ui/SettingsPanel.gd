class_name SettingsPanel
extends VBoxContainer

## The settings screen, shared by the main menu and the pause menu. Every row
## writes straight through to `Settings`, which saves and broadcasts, so there is
## no Apply button to forget.

const PAGES := ["Controls", "Video", "Audio", "Interface", "Game"]

var _tabs: Array[Button] = []
var _body: VBoxContainer
var _page: int = 0

func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var bar := UIKit.hbox(6)
	for i in PAGES.size():
		var tab := UIKit.button(PAGES[i], show_page.bind(i), "Tab")
		tab.toggle_mode = true
		_tabs.append(tab)
		bar.add_child(tab)
	bar.add_child(UIKit.spacer())
	bar.add_child(UIKit.button("Reset to defaults", _reset, "Ghost"))
	add_child(bar)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(620, 380)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body = UIKit.vbox(8)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	add_child(scroll)
	show_page(0)

func show_page(i: int) -> void:
	_page = i
	for j in _tabs.size():
		_tabs[j].set_pressed_no_signal(j == i)
	for child in _body.get_children():
		child.queue_free()
	match PAGES[i]:
		"Controls":
			_slider(&"mouse_sensitivity", "Mouse sensitivity", 0.2, 3.0, 0.05, "%.2fx")
			_toggle(&"invert_y", "Invert mouse Y")
			_slider(&"fov", "Field of view", 60.0, 100.0, 1.0, "%d°")
			_toggle(&"toggle_sprint", "Toggle sprint (tap to run, tap again to walk)")
			_toggle(&"manual_gearbox", "Manual gearbox for trucks (change gear yourself)")
			_bindings()
		"Video":
			_preset()
			_toggle(&"fullscreen", "Fullscreen")
			_toggle(&"vsync", "V-Sync")
			_slider(&"render_scale", "Render scale", 0.5, 1.0, 0.05, "%d%%", 100.0)
			_choice(&"shadows", "Shadows", ["Off", "Low", "High"])
			_choice(&"anti_aliasing", "Anti-aliasing", ["Off", "FXAA", "MSAA 2x"])
			_toggle(&"ambient_occlusion", "Ambient occlusion")
			_toggle(&"bloom", "Bloom")
			_slider(&"view_distance", "View distance", 150.0, 1200.0, 50.0, "%d m")
			_toggle(&"shaders", "Shaders: grass and trees sway, leafy trees, grassy ground")
			_choice(&"grass", "Grass and flowers", ["Off", "Short range", "Far"])
			_toggle(&"birds", "Birds")
			_toggle(&"moving_sun", "Day and night (off: always day)")
		"Audio":
			_slider(&"music_volume", "Music", 0.0, 1.0, 0.05, "%d%%", 100.0)
			_slider(&"sfx_volume", "Sound effects", 0.0, 1.0, 0.05, "%d%%", 100.0)
		"Interface":
			_slider(&"ui_scale", "Interface scale", 0.75, 1.5, 0.05, "%d%%", 100.0)
			_toggle(&"show_hints", "Key hints in the corner")
			_toggle(&"show_rig_banner", "Crane / winch / loader controls banner while driving")
			_toggle(&"show_labels", "Name labels over placed buildings")
			_toggle(&"minimap", "Minimap")
			_choice(&"minimap_zoom", "Minimap zoom", ["Close", "Normal", "Far", "Very far"])
			_toggle(&"minimap_rotate", "Minimap turns with you (off: north up)")
			_toggle(&"show_compass", "Compass")
			_toggle(&"show_tutorial", "Getting-started checklist")
			_toggle(&"show_fps", "Frame rate")
		"Game":
			_toggle(&"autosave", "Autosave every minute")
			var debug := UIKit.label("Debug", "Subheader")
			_body.add_child(debug)
			_toggle(&"unlimited_money", "Unlimited money (buying costs nothing)")
			_toggle(&"demo_lines", "Demo lines: an automated ore line and stone line running by the road east of home")
			var note := UIKit.label("Settings and controls are kept in your own config file, apart from your saves, so starting a new game keeps them.", "Small")
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_body.add_child(note)
			_config_buttons()

func _reset() -> void:
	if PAGES[_page] == "Controls":
		Settings.reset_controls()
	Settings.reset_to_defaults()
	show_page(_page)

## The config file: where it is, open its folder, read it again.
func _config_buttons() -> void:
	var row := _row("Config file: %s" % ProjectSettings.globalize_path(Settings.path))
	row.add_child(UIKit.button("Open folder", func(): Settings.open_config_folder(), "Ghost"))
	row.add_child(UIKit.button("Reload", func():
		Settings.reload()
		show_page(_page), "Ghost"))

# --- Key bindings -----------------------------------------------------------------

## The action being rebound, and its button, while waiting for a key.
var _capturing: StringName = &""
var _capture_add: bool = false
var _capture_button: Button

func _bindings() -> void:
	var head := UIKit.label("Keys - click one, then press the key or mouse button you want. + adds a second key, x clears it.", "Small")
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(head)
	_config_buttons()
	var group := ""
	for a in Controls.ACTIONS:
		if String(a[2]) != group:
			group = String(a[2])
			_body.add_child(UIKit.label(group, "Subheader"))
		var id: StringName = a[0]
		var row := _row(String(a[1]))
		var key := UIKit.button(Controls.keys_text(id), Callable(), "")
		key.custom_minimum_size.x = 170
		key.pressed.connect(_start_capture.bind(id, key, false))
		row.add_child(key)
		var add := UIKit.button("+", Callable(), "Ghost")
		add.tooltip_text = "Add another key for this"
		add.pressed.connect(_start_capture.bind(id, key, true))
		row.add_child(add)
		var clear := UIKit.button("x", func():
			Settings.bind(id, [])
			key.text = Controls.keys_text(id), "Ghost")
		clear.tooltip_text = "Unbind"
		row.add_child(clear)

func _start_capture(action: StringName, button: Button, add: bool) -> void:
	if _capture_button != null and is_instance_valid(_capture_button):
		_capture_button.text = Controls.keys_text(_capturing)
	_capturing = action
	_capture_add = add
	_capture_button = button
	button.text = "press a key... (Esc cancels)"

func _input(event: InputEvent) -> void:
	if _capturing == &"":
		return
	var press := (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed() \
		and not event.is_echo()
	if not press:
		return
	get_viewport().set_input_as_handled()
	var key := event as InputEventKey
	var action := _capturing
	_capturing = &""
	if key != null and key.keycode == KEY_ESCAPE:
		if is_instance_valid(_capture_button):
			_capture_button.text = Controls.keys_text(action)
		return
	var label := Controls.label_for_event(event)
	if label == "":
		return
	var labels: Array = (Controls.bindings.get(action, []) as Array).duplicate() if _capture_add else []
	if not labels.has(label):
		labels.append(label)
	Settings.bind(action, labels)
	if is_instance_valid(_capture_button):
		_capture_button.text = Controls.keys_text(action)
	_capture_button = null

func _row(title: String) -> HBoxContainer:
	var shell := UIKit.panel("Row")
	var row := UIKit.hbox(12)
	var name_label := UIKit.label(title)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	shell.add_child(row)
	_body.add_child(shell)
	return row

func _toggle(key: StringName, title: String) -> void:
	var row := _row(title)
	var check := CheckButton.new()
	check.button_pressed = Settings.flag(key)
	check.focus_mode = Control.FOCUS_ALL
	check.toggled.connect(func(on: bool): Settings.set_value(key, on))
	row.add_child(check)

## `display_scale` turns a 0.5-1.0 fraction into a percentage for the readout.
func _slider(key: StringName, title: String, lo: float, hi: float, step: float,
		fmt: String, display_scale: float = 1.0) -> void:
	var row := _row(title)
	var readout := UIKit.label("", "Muted")
	readout.custom_minimum_size.x = 64
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.custom_minimum_size = Vector2(240, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = float(Settings.value(key))
	var show := func(v: float):
		var shown: float = v * display_scale
		readout.text = fmt % (int(round(shown)) if fmt.contains("%d") else shown)
	show.call(slider.value)
	slider.value_changed.connect(func(v: float):
		show.call(v)
		Settings.set_value(key, v))
	row.add_child(slider)
	row.add_child(readout)

## The graphics preset: picking one sets every video setting below it, and
## the page redraws to show them.
func _preset() -> void:
	var row := _row("Graphics quality")
	var pick := OptionButton.new()
	for o in ["Low (fastest)", "Medium", "High", "Custom"]:
		pick.add_item(o)
	pick.selected = clampi(int(Settings.value(&"quality")), 0, 3)
	pick.set_item_disabled(3, true)
	pick.custom_minimum_size.x = 160
	pick.item_selected.connect(func(i: int):
		Settings.apply_preset(i)
		show_page.call_deferred(_page))
	row.add_child(pick)

func _choice(key: StringName, title: String, options: Array) -> void:
	var row := _row(title)
	var pick := OptionButton.new()
	for o in options:
		pick.add_item(String(o))
	pick.selected = clampi(int(Settings.value(key)), 0, options.size() - 1)
	pick.custom_minimum_size.x = 140
	pick.item_selected.connect(func(i: int): Settings.set_value(key, i))
	row.add_child(pick)
