class_name SettingsPanel
extends VBoxContainer

## The settings screen, shared by the main menu and the pause menu. Every row
## writes straight through to `Settings`, which saves and broadcasts, so there is
## no Apply button to forget.

const PAGES := ["Controls", "Video", "Interface", "Game"]

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
		"Video":
			_toggle(&"fullscreen", "Fullscreen")
			_toggle(&"vsync", "V-Sync")
			_slider(&"render_scale", "Render scale", 0.5, 1.0, 0.05, "%d%%", 100.0)
			_choice(&"shadows", "Shadows", ["Off", "Low", "High"])
			_toggle(&"ambient_occlusion", "Ambient occlusion")
			_toggle(&"bloom", "Bloom")
			_slider(&"view_distance", "View distance", 150.0, 1200.0, 50.0, "%d m")
			_toggle(&"moving_sun", "Sun moves through the day")
		"Interface":
			_slider(&"ui_scale", "Interface scale", 0.75, 1.5, 0.05, "%d%%", 100.0)
			_toggle(&"show_hints", "Key hints in the corner")
			_toggle(&"show_compass", "Compass")
			_toggle(&"show_tutorial", "Getting-started checklist")
			_toggle(&"show_fps", "Frame rate")
		"Game":
			_toggle(&"autosave", "Autosave every minute")
			var debug := UIKit.label("Debug", "Subheader")
			_body.add_child(debug)
			_toggle(&"unlimited_money", "Unlimited money (buying costs nothing)")
			var note := UIKit.label("Settings are kept separately from your save, so starting a new game keeps them.", "Small")
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_body.add_child(note)

func _reset() -> void:
	Settings.reset_to_defaults()
	show_page(_page)

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

func _choice(key: StringName, title: String, options: Array) -> void:
	var row := _row(title)
	var pick := OptionButton.new()
	for o in options:
		pick.add_item(String(o))
	pick.selected = clampi(int(Settings.value(key)), 0, options.size() - 1)
	pick.custom_minimum_size.x = 140
	pick.item_selected.connect(func(i: int): Settings.set_value(key, i))
	row.add_child(pick)
