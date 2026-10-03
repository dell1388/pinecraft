class_name MainMenu
extends CanvasLayer

## The title screen, laid over the real world with a camera circling the valley,
## so the first thing a player sees is the game rather than a picture of it.
## The world is built and paused behind it; Continue just lets it run.

signal continue_requested
signal new_game_requested
signal quit_requested
signal load_slot_requested(slot: int)
signal new_slot_requested(slot: int)

## Set before a reload that should drop straight into play (New Game from the
## menu), and cleared as soon as the fresh world has read it.
static var skip_once: bool = false

const ORBIT_CENTRE := Vector3(0, 0, 24)
const ORBIT_RADIUS := 95.0
const ORBIT_HEIGHT := 42.0
const ORBIT_SPEED := 0.035

var world: Node3D
var _camera: Camera3D
var _previous_camera: Camera3D
var _angle: float = 0.6
var _root: Control
var _buttons: VBoxContainer
var _page_host: CenterContainer
var _page: Control
var _dialog: Control
var _continue: Button
var _load_button: Button
var _save_line: Label

func _init() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	_root = UIKit.fill(Control.new())
	_root.theme = UITheme.theme()
	add_child(_root)

	# Darken the left third, where the words are, and leave the view clear.
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.03, 0.05, 0.04, 0.92))
	gradient.set_color(1, Color(0.03, 0.05, 0.04, 0.0))
	gradient.add_point(0.45, Color(0.03, 0.05, 0.04, 0.7))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)
	tex.width = 256
	tex.height = 4
	shade.texture = tex
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.anchor_right = 0.62
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)

	var column := UIKit.vbox(6)
	column.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	column.offset_left = 96
	column.offset_right = 640
	column.offset_top = 110
	column.offset_bottom = -60
	_root.add_child(column)

	var title := UIKit.label("PINECRAFT", "Title")
	column.add_child(title)
	var tagline := UIKit.label("CHOP  ·  MILL  ·  HAUL  ·  AUTOMATE", "Subheader", 16)
	column.add_child(tagline)
	column.add_child(UIKit.spacer(false, 44))

	_buttons = UIKit.vbox(10)
	_buttons.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_buttons.custom_minimum_size.x = 380
	column.add_child(_buttons)
	_continue = _menu_button("Continue", func(): continue_requested.emit())
	_save_line = UIKit.label("", "Muted", 15)
	_buttons.add_child(_save_line)
	_load_button = _menu_button("Load Game", func(): _open_page("Load a game", _slots(SavePanel.Mode.LOAD)))
	_menu_button("New Game", _on_new_game)
	_menu_button("Co-op", func(): _open_page("Co-op", _coop_page()))
	_menu_button("Settings", func(): _open_page("Settings", SettingsPanel.new()))
	_menu_button("Controls", func(): _open_page("Controls", KeyGuide.sheet()))
	_menu_button("Quit", func(): quit_requested.emit())

	var footer := UIKit.label("%s   ·   Fonts: Rubik & Lilita One (SIL OFL)   ·   Godot %s" % [
		Version.line(), Engine.get_version_info().string], "Small")
	footer.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	footer.offset_left = 96
	footer.offset_top = -44
	_root.add_child(footer)

	_page_host = CenterContainer.new()
	_page_host.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_page_host.anchor_left = 0.36
	_page_host.offset_right = -60
	_root.add_child(_page_host)
	refresh()

func _menu_button(text: String, action: Callable) -> Button:
	var b := UIKit.button(text, action, "Big")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.x = 380
	_buttons.add_child(b)
	return b

## Re-reads the save, so Continue says what it will continue.
func refresh() -> void:
	var info := SaveSystem.summary()
	var has_save := not info.is_empty()
	_continue.visible = has_save
	_save_line.visible = has_save
	_load_button.visible = SaveSystem.any_save()
	if has_save:
		var when := UIKit.ago(String(info.saved_at))
		_save_line.text = "Slot %d   ·   %s   ·   Day %d   ·   %s   ·   %d building%s%s" % [SaveSystem.slot,
			WorldMap.title(WorldMap.valid(info.get("map", WorldMap.ISLES))),
			int(info.day), UIKit.money(int(info.money)), int(info.buildings),
			"" if int(info.buildings) == 1 else "s",
			("   ·   saved " + when) if when != "" else ""]

func open(p_world: Node3D) -> void:
	world = p_world
	visible = true
	refresh()
	_close_page()
	_start_orbit()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_focus_first.call_deferred()

func close() -> void:
	visible = false
	_close_page()
	_stop_orbit()

func _focus_first() -> void:
	for b in _buttons.get_children():
		if b is Button and b.visible:
			(b as Button).grab_focus()
			return

## Always the page, even with no saves yet: it is where the map is picked.
func _on_new_game() -> void:
	_open_page("New game", _slots(SavePanel.Mode.NEW))

func _slots(mode: SavePanel.Mode) -> Control:
	var panel := SavePanel.new(mode, _root)
	panel.load_requested.connect(func(n: int): load_slot_requested.emit(n))
	panel.new_requested.connect(func(n: int): new_slot_requested.emit(n))
	return panel

func _open_page(title: String, content: Control) -> void:
	_close_page()
	var card := UIKit.panel("WindowPanel")
	card.custom_minimum_size = Vector2(700, 0)
	var col := UIKit.vbox(16)
	card.add_child(col)
	var head := UIKit.hbox(10)
	var name_label := UIKit.label(title, "Header")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	head.add_child(UIKit.button("Back", _close_page, "Ghost"))
	col.add_child(head)
	col.add_child(content)
	_page = card
	_page_host.add_child(card)

# --- Co-op ------------------------------------------------------------------------------

var _coop_status: Label

## Host this game for friends, or join someone else's. Everything is shared:
## one world, one purse, one set of unlocks.
func _coop_page() -> Control:
	var col := UIKit.vbox(14)
	col.add_child(UIKit.label("Play together, on the host's world. Everything is shared - money, unlocks, vehicles, the lot.", "Muted", 15))
	var name_row := UIKit.hbox(10)
	name_row.add_child(UIKit.label("Your name", "", 16))
	var name_edit := LineEdit.new()
	name_edit.text = Net.player_name
	name_edit.custom_minimum_size.x = 260
	name_edit.text_changed.connect(func(t: String):
		Net.player_name = t.strip_edges() if t.strip_edges() != "" else "Player"
		Settings.set_value(&"player_name", Net.player_name))
	name_row.add_child(name_edit)
	col.add_child(name_row)

	col.add_child(UIKit.label("Host", "Header", 20))
	if Net.is_host():
		col.add_child(UIKit.label("Hosting on port %d. Friends join with your IP address: %s" % [Net.port, _local_addresses()], "", 15))
		col.add_child(UIKit.button("Stop hosting", func():
			if world != null:
				world.call("stop_hosting")
			_open_page("Co-op", _coop_page()), ""))
	else:
		col.add_child(UIKit.label("Opens this game to friends. They need your IP address, and port %d open or forwarded if they are not on your network." % Net.PORT, "Muted", 14))
		col.add_child(UIKit.button("Host this game", _on_host, ""))

	col.add_child(UIKit.label("Join", "Header", 20))
	var join_row := UIKit.hbox(10)
	var address := LineEdit.new()
	address.placeholder_text = "host's IP address (IP or IP:port)"
	var last := String(Settings.value(&"last_address"))
	address.text = last if last != "" else Net.address
	address.custom_minimum_size.x = 260
	join_row.add_child(address)
	join_row.add_child(UIKit.button("Join", func(): _on_join(address.text), ""))
	col.add_child(join_row)
	col.add_child(UIKit.label("Joining leaves your own world (it is saved) and plays in the host's.", "Muted", 14))
	_coop_status = UIKit.label("", "", 15)
	col.add_child(_coop_status)
	return col

static func _local_addresses() -> String:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		if a.contains(".") and not a.begins_with("127.") and not a.begins_with("169.254"):
			out.append(a)
	return ", ".join(out) if not out.is_empty() else "(see your network settings)"

func _on_host() -> void:
	var err := Net.host()
	if err != "":
		_coop_status.text = err
		return
	if world != null:
		world.call("start_hosting")
		# Straight into play: the world runs for guests while the host plays.
		world.call("resume_play")
		var hud: Variant = world.get("hud")
		if hud != null:
			hud.call("log_message", "hosting co-op on port %d - friends join with: %s" % [Net.port, _local_addresses()])

var _joining: bool = false

## Connects first, and only then leaves this world for the host's: a join
## that gets no answer leaves you where you are, with the reason on screen.
func _on_join(address: String) -> void:
	address = address.strip_edges()
	if address == "":
		_coop_status.text = "type the host's IP address"
		return
	if _joining:
		return
	Settings.set_value(&"last_address", address)
	var at := Net.split_address(address)
	var host_part: String = at[0]
	var port: int = at[1]
	var err := Net.join(host_part, port)
	if err != "":
		_coop_status.text = err
		return
	_joining = true
	_coop_status.text = "connecting to %s:%d..." % [host_part, port]
	var result := [0, ""]
	var ok_cb := func(): result[0] = 1
	var fail_cb := func(reason: String):
		result[0] = -1
		result[1] = reason
	Net.joined.connect(ok_cb, CONNECT_ONE_SHOT)
	Net.join_failed.connect(fail_cb, CONNECT_ONE_SHOT)
	var waited := 0.0
	while result[0] == 0 and waited < 12.0:
		await get_tree().create_timer(0.1, true).timeout
		waited += 0.1
	for pair in [[Net.joined, ok_cb], [Net.join_failed, fail_cb]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	_joining = false
	if result[0] != 1:
		Net.leave()
		_coop_status.text = ("could not join: %s. " % (result[1] if result[1] != "" else "no answer from %s:%d" % [host_part, port])) \
			+ "Check the host has pressed Host this game, the address is theirs, and their firewall lets the game in (UDP %d)." % port
		return
	# Connected: the host says which map first (a moment); then save this
	# world, and build the host's and join it.
	var waited_map := 0.0
	while Net.host_map == &"" and waited_map < 4.0 and Net.is_client():
		await get_tree().create_timer(0.1, true).timeout
		waited_map += 0.1
	if world != null:
		world.call("quick_save")
	skip_once = true
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/boot.tscn")

func _close_page() -> void:
	if _page != null and is_instance_valid(_page):
		_page.queue_free()
	_page = null

func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_ESCAPE:
		return
	get_viewport().set_input_as_handled()
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()
		_dialog = null
	elif _page != null:
		_close_page()
		_focus_first()

# --- The flyover -----------------------------------------------------------

func _start_orbit() -> void:
	if world == null:
		return
	_previous_camera = world.get_viewport().get_camera_3d()
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "MenuCamera"
		_camera.far = 600.0
		_camera.fov = 60.0
		world.add_child(_camera)
	_camera.current = true
	_orbit(0.0)

func _stop_orbit() -> void:
	if _camera != null and is_instance_valid(_camera):
		_camera.current = false
	if _previous_camera != null and is_instance_valid(_previous_camera):
		_previous_camera.current = true

func _process(delta: float) -> void:
	if visible and _camera != null:
		_orbit(delta)

func _orbit(delta: float) -> void:
	_angle += delta * ORBIT_SPEED
	var eye := ORBIT_CENTRE + Vector3(cos(_angle) * ORBIT_RADIUS, ORBIT_HEIGHT,
		sin(_angle) * ORBIT_RADIUS)
	_camera.look_at_from_position(eye, ORBIT_CENTRE + Vector3(0, 4, 0))
