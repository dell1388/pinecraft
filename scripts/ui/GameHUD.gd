class_name GameHUD
extends CanvasLayer

## All in-game UI: status readout, crosshair, prompts, event log and the three
## keyboard-driven panels (market, shop, help).

enum PanelKind { NONE, MARKET, SHOP, HELP }

var player: Player
var plot: Plot
var manager: LooseItemManager
var world: Node

var panel: PanelKind = PanelKind.NONE

var _status: Label
var _prompt: Label
var _log_label: Label
var _panel_box: PanelContainer
var _panel_label: Label
var _crosshair: Label
var _messages: Array[String] = []
var _refresh: float = 0.0

const HELP_TEXT := """PINECRAFT - controls

  WASD / Shift / Space   move, sprint, jump
  LMB                    chop tree / mine rock (or place, in build mode)
  RMB                    pick up item onto carry rack (or remove, in build mode)
  F                      heavy-drag a single item / release
  Q / G                  drop one / drop all
  E                      deposit into machine, bin or sell zone
  Shift+E                empty a storage bin back onto the ground
  B                      build mode      R rotate      wheel cycle building
  M                      market board    U shop & upgrades    F1 this help
  F5 / F9                save / load     F8 new game
  V                      enter / exit hauler   X unload hauler   C recover hauler

The loop: fell trees -> haul logs to a sawmill -> planks to a furnace/workbench
or straight to a sell zone -> buy belts so the plot runs itself."""

func setup(p_player: Player, p_plot: Plot, p_manager: LooseItemManager, p_world: Node) -> void:
	player = p_player
	plot = p_plot
	manager = p_manager
	world = p_world
	player.interacted.connect(func(msg: String): if msg != "": log_message(msg))
	Economy.item_sold.connect(func(id: StringName, value: int):
		log_message("sold %s for $%d" % [GameData.item_name(id), value]))
	Economy.day_changed.connect(func(day: int): log_message("--- day %d: prices moved ---" % day))
	PlayerState.upgraded.connect(func(track: StringName, level: int):
		log_message("%s upgraded to %s" % [String(track), PlayerState.label(track)]))

func _ready() -> void:
	var top := PanelContainer.new()
	top.position = Vector2(12, 10)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	top.add_child(_status)
	add_child(top)

	_crosshair = Label.new()
	_crosshair.text = "+"
	_crosshair.anchor_left = 0.5
	_crosshair.anchor_top = 0.5
	_crosshair.offset_left = -5
	_crosshair.offset_top = -10
	add_child(_crosshair)

	var prompt_panel := PanelContainer.new()
	prompt_panel.anchor_left = 0.5
	prompt_panel.anchor_top = 1.0
	prompt_panel.anchor_bottom = 1.0
	prompt_panel.offset_left = -260
	prompt_panel.offset_top = -96
	prompt_panel.offset_bottom = -64
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.custom_minimum_size = Vector2(520, 0)
	prompt_panel.add_child(_prompt)
	add_child(prompt_panel)

	var log_panel := PanelContainer.new()
	log_panel.anchor_top = 1.0
	log_panel.anchor_bottom = 1.0
	log_panel.offset_left = 12
	log_panel.offset_top = -120
	log_panel.offset_bottom = -12
	_log_label = Label.new()
	_log_label.add_theme_font_size_override("font_size", 13)
	log_panel.add_child(_log_label)
	add_child(log_panel)

	_panel_box = PanelContainer.new()
	_panel_box.anchor_left = 1.0
	_panel_box.anchor_right = 1.0
	_panel_box.offset_left = -520
	_panel_box.offset_top = 10
	_panel_box.visible = false
	_panel_label = Label.new()
	_panel_label.add_theme_font_size_override("font_size", 14)
	_panel_box.add_child(_panel_label)
	add_child(_panel_box)

	log_message("F1 for controls. Chop a tree to start.")

func log_message(text: String) -> void:
	_messages.append(text)
	while _messages.size() > 6:
		_messages.pop_front()
	_log_label.text = "\n".join(_messages)

# --- Panels ----------------------------------------------------------------

func open_panel(p: PanelKind) -> void:
	panel = PanelKind.NONE if panel == p else p
	_panel_box.visible = panel != PanelKind.NONE
	if player != null:
		player.set_ui_blocking(panel == PanelKind.SHOP)
	_rebuild_panel()

func _rebuild_panel() -> void:
	match panel:
		PanelKind.MARKET:
			_panel_label.text = _market_text()
		PanelKind.SHOP:
			_panel_label.text = _shop_text()
		PanelKind.HELP:
			_panel_label.text = HELP_TEXT
		_:
			_panel_label.text = ""

func _market_text() -> String:
	var lines: Array[String] = ["MARKET - day %d  (%d s left)" % [
		Economy.day, int(Economy.seconds_left_today())], ""]
	for row in Economy.market_rows():
		var arrow := "up  " if row.multiplier >= 1.0 else "down"
		lines.append("  %-16s $%-5d  x%.2f %s" % [row.name, row.price, row.multiplier, arrow])
	lines.append("")
	lines.append("Prices redraw every day. Stockpile in bins while a price is low.")
	return "\n".join(lines)

func _shop_text() -> String:
	var lines: Array[String] = ["SHOP - $%d" % Economy.money, "", "Upgrades:"]
	var keys := ["1", "2", "3", "4"]
	var tracks := GameData.upgrade_tracks.keys()
	for i in tracks.size():
		var track: StringName = tracks[i]
		var cost := PlayerState.next_cost(track)
		var cost_text := "MAX" if cost < 0 else "$%d" % cost
		lines.append("  [%s] %-9s lv%d %-22s -> %s" % [
			keys[i] if i < keys.size() else " ", String(track),
			PlayerState.level(track), PlayerState.label(track), cost_text])
	lines.append("")
	var expand_cost := plot.next_expansion_cost()
	lines.append("  [5] expand plot (tier %d, %.0fm) -> %s" % [
		plot.tier, plot.half_extent * 2.0,
		"MAX" if expand_cost < 0 else "$%d" % expand_cost])
	lines.append("  [6] buy hauler -> %s" % (
		"owned" if PlayerState.owns_vehicle else "$%d" % int(GameData.vehicle_def.get("cost", 5000))))
	lines.append("")
	lines.append("Unlock buildings:")
	var locked_keys := ["7", "8", "9", "0"]
	var n := 0
	for def: BuildingDef in GameData.buildings.values():
		if PlayerState.is_unlocked(def.id) or n >= locked_keys.size():
			continue
		lines.append("  [%s] %-16s unlock $%d  (build cost $%d)" % [
			locked_keys[n], def.display_name, def.unlock_cost, def.cost])
		n += 1
	if n == 0:
		lines.append("  everything unlocked")
	return "\n".join(lines)

func _shop_key(index: int) -> void:
	var tracks := GameData.upgrade_tracks.keys()
	if index < tracks.size():
		if not PlayerState.try_upgrade(tracks[index]):
			log_message("cannot afford that upgrade")
		_rebuild_panel()
		return
	match index:
		4:
			if plot.try_expand():
				log_message("plot expanded to tier %d (%.0fm)" % [plot.tier, plot.half_extent * 2.0])
			else:
				log_message("cannot expand yet")
		5:
			if PlayerState.try_buy_vehicle():
				log_message("hauler delivered")
				if world != null and world.has_method("spawn_vehicle"):
					world.call("spawn_vehicle")
			else:
				log_message("cannot buy the hauler")
		_:
			var locked: Array[BuildingDef] = []
			for def: BuildingDef in GameData.buildings.values():
				if not PlayerState.is_unlocked(def.id):
					locked.append(def)
			var i := index - 6
			if i >= 0 and i < locked.size():
				if PlayerState.try_unlock(locked[i].id):
					log_message("unlocked %s" % locked[i].display_name)
					if player != null and player.build_system != null:
						player.build_system.refresh_palette()
				else:
					log_message("cannot afford that unlock")
	_rebuild_panel()

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_M:
			open_panel(PanelKind.MARKET)
		KEY_U:
			open_panel(PanelKind.SHOP)
		KEY_F1:
			open_panel(PanelKind.HELP)
		KEY_ESCAPE:
			if panel != PanelKind.NONE:
				open_panel(panel)
			elif player != null:
				player.capture_mouse(not Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
		_:
			if panel == PanelKind.SHOP:
				var digits := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]
				var idx := digits.find(key.keycode)
				if idx >= 0:
					_shop_key(idx)

# --- Status ----------------------------------------------------------------

func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = 0.1
	if player == null:
		return
	var lines: Array[String] = [
		"$%d    day %d  (%d%%)    plot tier %d" % [
			Economy.money, Economy.day, int(Economy.day_progress() * 100.0), plot.tier],
		"carry %d/%d    loose %d/%d    buildings %d" % [
			player.carried_count(), player.capacity(),
			manager.active_count(), manager.per_plot_cap, plot.placed.size()],
		"axe %s   pick %s   %d fps" % [
			PlayerState.label(&"axe"), PlayerState.label(&"pickaxe"),
			Engine.get_frames_per_second()],
	]
	if player.driving():
		lines.append("driving - [X] unload  [V] exit  [C] recover")
	_status.text = "\n".join(lines)
	_prompt.text = player.last_prompt
	if panel == PanelKind.MARKET or panel == PanelKind.SHOP:
		_rebuild_panel()
