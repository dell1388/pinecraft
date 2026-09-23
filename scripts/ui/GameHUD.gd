class_name GameHUD
extends CanvasLayer

## Everything drawn over play.
##
##   top left      money, the day, the carry rack
##   top middle    compass with the places worth going
##   top right     orders, and the getting-started checklist
##   middle        crosshair, and what [E] would do here
##   bottom left   what just happened
##   bottom right  the keys that matter right now
##   bottom middle the build bar in build mode, the gauges when driving
##
## And the journal window over the top of it on Tab / M / U / F1.

const TOAST_SECONDS := 6.0
const TOAST_MAX := 6

var player: Player
var plot: Plot
var manager: LooseItemManager
var world: Node
var build_system: BuildSystem
var quests: QuestLog
var tutorial: Tutorial

var _root: Control
var _money: Label
var _money_shown: float = 0.0
var _money_pop: Control
var _day: Label
var _day_left: Label
var _day_bar: ProgressBar
var _rack: Label
var _rack_bar: ProgressBar
var _tools: Label
var _compass: Compass
var _orders_box: VBoxContainer
var _orders_card: PanelContainer
var _tutorial_card: PanelContainer
var _tutorial_title: Label
var _tutorial_hint: VBoxContainer
var _tutorial_count: Label
var _crosshair: Crosshair
var _prompt_card: PanelContainer
var _prompt_rows: VBoxContainer
var _prompt_text: String = "<unset>"
var _toasts: VBoxContainer
var _hints_card: PanelContainer
var _hints_box: VBoxContainer
var _hints_state: String = ""
var _build_panel: VBoxContainer
var _build_slots: HBoxContainer
var _build_name: Label
var _build_blurb: Label
var _build_error: Label
var _build_sig: String = ""
var _drive_panel: PanelContainer
var _speed: Label
var _cargo: Label
var _cargo_bar: ProgressBar
var _drive_state: Label
var _debug: Label
var _saved: Label
var _banner: Label
var journal: Journal

var _refresh: float = 0.0
var _orders_sig: String = ""
## Sales and money moves arrive an item at a time - a yard of fifty logs is
## fifty signals in one frame - so they are summed and shown once per frame.
var _sold_count: int = 0
var _sold_value: int = 0
var _sold_name: String = ""
var _money_delta: int = 0
var show_debug: bool = false

func setup(p_player: Player, p_plot: Plot, p_manager: LooseItemManager, p_world: Node) -> void:
	player = p_player
	plot = p_plot
	manager = p_manager
	world = p_world
	build_system = p_world.get("build_system") as BuildSystem
	quests = p_world.get("quests") as QuestLog
	player.interacted.connect(func(msg: String): if msg != "": log_message(msg))
	Economy.item_sold.connect(_on_item_sold)
	Economy.day_changed.connect(func(day: int):
		# Not while a save is being read in: that is not a new day.
		if day > 1 and bool(world.get("playing")):
			show_banner("Day %d" % day, "The market has moved - check prices with [P]"))
	Economy.money_changed.connect(_on_money_changed)
	PlayerState.upgraded.connect(func(track: StringName, _level: int):
		toast("Upgraded: %s" % PlayerState.label(track), UITheme.ACCENT))
	PlayerState.unlocked.connect(func(id: StringName):
		var def := GameData.building(id)
		toast("Unlocked %s - find it on the build bar [B]" % (def.display_name if def else String(id)), UITheme.ACCENT))
	if quests != null:
		quests.completed.connect(func(quest: Dictionary, reward: int):
			show_banner("Order filled", "%s  +%s" % [quest.title, UIKit.money(reward)]))
	if build_system != null:
		build_system.selection_changed.connect(func(_d): _build_sig = "")
	_money_shown = Economy.money

func bind_tutorial(t: Tutorial) -> void:
	tutorial = t
	if journal != null:
		journal.tutorial = t
	t.advanced.connect(_on_tutorial_advanced)
	_update_tutorial()

func _init() -> void:
	layer = 10

func _ready() -> void:
	_root = UIKit.fill(Control.new())
	_root.theme = UITheme.theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_status()
	_build_compass()
	_build_orders()
	_build_center()
	_build_toasts()
	_build_hints()
	_build_build_bar()
	_build_drive()
	_build_misc()
	journal = Journal.new()
	_root.add_child(journal)
	journal.quests = quests
	journal.plot = plot
	journal.world = world
	journal.visibility_changed.connect(_on_journal_visibility)
	_ignore_mouse(_root)
	journal.mouse_filter = Control.MOUSE_FILTER_STOP
	Settings.changed.connect(func(_k): _apply_settings())
	_apply_settings()

## Nothing on the HUD should eat a click meant for the world.
func _ignore_mouse(node: Node) -> void:
	for child in node.get_children():
		if child is Control and child != journal:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			_ignore_mouse(child)

## Pins a box to a corner or edge a margin in from it, growing away from the
## edge as its contents grow.
func _pin(c: Control, preset: int, margin: int = 18) -> void:
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, margin)
	match preset:
		Control.PRESET_BOTTOM_RIGHT:
			c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			c.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_BOTTOM:
			c.grow_horizontal = Control.GROW_DIRECTION_BOTH
			c.grow_vertical = Control.GROW_DIRECTION_BEGIN

# --- Construction ----------------------------------------------------------

func _build_status() -> void:
	var card := UIKit.panel("Card")
	card.custom_minimum_size.x = 290
	_root.add_child(card)
	card.position = Vector2(18, 16)
	var col := UIKit.vbox(4)
	card.add_child(col)

	var money_row := UIKit.hbox(10)
	_money = UIKit.label(UIKit.money(Economy.money), "Money")
	money_row.add_child(_money)
	_money_pop = Control.new()
	_money_pop.custom_minimum_size = Vector2(80, 10)
	money_row.add_child(_money_pop)
	col.add_child(money_row)

	var day_row := UIKit.hbox(8)
	_day = UIKit.label("DAY 1", "Subheader", 14)
	day_row.add_child(_day)
	day_row.add_child(UIKit.spacer())
	_day_left = UIKit.label("", "Small")
	day_row.add_child(_day_left)
	col.add_child(day_row)
	_day_bar = UIKit.bar(0.0, UITheme.ACCENT, 5)
	col.add_child(_day_bar)

	col.add_child(UIKit.spacer(false, 6))
	var rack_row := UIKit.hbox(8)
	rack_row.add_child(UIKit.label("RACK", "Subheader", 14))
	rack_row.add_child(UIKit.spacer())
	_rack = UIKit.label("", "Small")
	rack_row.add_child(_rack)
	col.add_child(rack_row)
	_rack_bar = UIKit.bar(0.0, UITheme.INFO, 5)
	col.add_child(_rack_bar)
	_tools = UIKit.label("", "Small")
	col.add_child(_tools)

func _build_compass() -> void:
	_compass = Compass.new()
	_root.add_child(_compass)
	_compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_compass.offset_left = -310
	_compass.offset_right = 310
	_compass.offset_top = 14
	_compass.offset_bottom = 64
	if player != null:
		_compass.camera = player.camera
	if world != null and world.has_method("compass_markers"):
		_compass.markers = world.call("compass_markers")

func _build_orders() -> void:
	var right := UIKit.vbox(10)
	right.custom_minimum_size.x = 330
	_root.add_child(right)
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -348
	right.offset_right = -18
	right.offset_top = 16

	_orders_card = UIKit.panel("Card")
	var col := UIKit.vbox(8)
	_orders_card.add_child(col)
	var head := UIKit.hbox(6)
	var title := UIKit.label("ORDERS", "Subheader", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UIKit.keycap("Tab", 11))
	col.add_child(head)
	_orders_box = UIKit.vbox(9)
	col.add_child(_orders_box)
	right.add_child(_orders_card)

	_tutorial_card = UIKit.panel("Card")
	var tcol := UIKit.vbox(6)
	_tutorial_card.add_child(tcol)
	var thead := UIKit.hbox(6)
	var ttitle := UIKit.label("GETTING STARTED", "Subheader", 14)
	ttitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thead.add_child(ttitle)
	_tutorial_count = UIKit.label("", "Small")
	thead.add_child(_tutorial_count)
	tcol.add_child(thead)
	_tutorial_title = UIKit.label("", "", 19)
	_tutorial_title.add_theme_font_override("font", UITheme.font(600))
	tcol.add_child(_tutorial_title)
	_tutorial_hint = UIKit.vbox(3)
	tcol.add_child(_tutorial_hint)
	_tutorial_card.visible = false
	right.add_child(_tutorial_card)

func _build_center() -> void:
	_crosshair = Crosshair.new()
	_root.add_child(_crosshair)
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.offset_left = -16
	_crosshair.offset_top = -16
	_crosshair.offset_right = 16
	_crosshair.offset_bottom = 16

	var holder := CenterContainer.new()
	_root.add_child(holder)
	holder.set_anchors_preset(Control.PRESET_CENTER)
	holder.offset_left = -500
	holder.offset_right = 500
	holder.offset_top = 46
	holder.offset_bottom = 150
	holder.use_top_left = false
	_prompt_card = UIKit.panel("Pill")
	_prompt_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_prompt_rows = UIKit.vbox(4)
	_prompt_card.add_child(_prompt_rows)
	_prompt_card.visible = false
	var top := VBoxContainer.new()
	top.add_child(_prompt_card)
	holder.add_child(top)

func _build_toasts() -> void:
	_toasts = UIKit.vbox(6)
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(_toasts)
	_toasts.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_toasts.offset_left = 18
	_toasts.offset_right = 560
	_toasts.offset_top = -330
	_toasts.offset_bottom = -18

func _build_hints() -> void:
	_hints_card = UIKit.panel("Card")
	_root.add_child(_hints_card)
	_hints_box = UIKit.vbox(6)
	_hints_card.add_child(_hints_box)
	_pin(_hints_card, Control.PRESET_BOTTOM_RIGHT)

func _build_build_bar() -> void:
	_build_panel = UIKit.vbox(8)
	_root.add_child(_build_panel)
	_build_panel.alignment = BoxContainer.ALIGNMENT_END

	var info := UIKit.panel("Card")
	info.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var icol := UIKit.vbox(2)
	info.add_child(icol)
	var head := UIKit.hbox(10)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(UIKit.label("BUILD MODE", "Subheader", 14))
	_build_name = UIKit.label("", "", 20)
	_build_name.add_theme_font_override("font", UITheme.font(600))
	head.add_child(_build_name)
	icol.add_child(head)
	_build_blurb = UIKit.label("", "Muted", 15)
	_build_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icol.add_child(_build_blurb)
	_build_error = UIKit.label("", "", 15, UITheme.BAD)
	_build_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icol.add_child(_build_error)
	_build_panel.add_child(info)

	_build_slots = UIKit.hbox(8)
	_build_slots.alignment = BoxContainer.ALIGNMENT_CENTER
	_build_panel.add_child(_build_slots)
	_pin(_build_panel, Control.PRESET_CENTER_BOTTOM)
	_build_panel.visible = false

func _build_drive() -> void:
	_drive_panel = UIKit.panel("Card")
	_root.add_child(_drive_panel)
	var row := UIKit.hbox(22)
	_drive_panel.add_child(row)
	var speed_col := UIKit.vbox(0)
	_speed = UIKit.label("0", "Money", 46)
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed.custom_minimum_size.x = 90
	speed_col.add_child(_speed)
	var unit := UIKit.label("KM/H", "Subheader", 12)
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_col.add_child(unit)
	row.add_child(speed_col)
	var cargo_col := UIKit.vbox(5)
	cargo_col.custom_minimum_size.x = 220
	cargo_col.alignment = BoxContainer.ALIGNMENT_CENTER
	var ch := UIKit.hbox(6)
	ch.add_child(UIKit.label("CARGO", "Subheader", 14))
	ch.add_child(UIKit.spacer())
	_cargo = UIKit.label("", "Small")
	ch.add_child(_cargo)
	cargo_col.add_child(ch)
	_cargo_bar = UIKit.bar(0.0, UITheme.ACCENT, 7)
	cargo_col.add_child(_cargo_bar)
	_drive_state = UIKit.label("", "Small")
	cargo_col.add_child(_drive_state)
	row.add_child(cargo_col)
	_pin(_drive_panel, Control.PRESET_CENTER_BOTTOM)
	_drive_panel.visible = false

func _build_misc() -> void:
	_debug = UIKit.label("", "Small", 13)
	_root.add_child(_debug)
	_debug.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_debug.offset_left = -300
	_debug.offset_right = 300
	_debug.offset_top = 70
	_debug.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_debug.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_debug.add_theme_constant_override("outline_size", 4)

	_saved = UIKit.label("Saved", "Subheader", 13)
	_root.add_child(_saved)
	_saved.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_saved.offset_left = -100
	_saved.offset_right = 100
	_saved.offset_top = 92
	_saved.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_saved.modulate.a = 0.0

	_banner = Label.new()
	_banner.theme_type_variation = "Header"
	_banner.add_theme_font_size_override("font_size", 46)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_banner)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_left = -500
	_banner.offset_right = 500
	_banner.offset_top = 150
	_banner.modulate.a = 0.0

func _apply_settings() -> void:
	_compass.visible = Settings.flag(&"show_compass")
	_hints_card.visible = Settings.flag(&"show_hints")
	_update_tutorial()

# --- Messages --------------------------------------------------------------

## Kept for the callers that just want a line on screen.
func log_message(text: String) -> void:
	var color := UITheme.INK
	var lower := text.to_lower()
	if lower.contains("too ") or lower.contains("can't") or lower.contains("cannot") \
			or lower.contains("not ") or lower.contains("no ") or lower.contains("failed"):
		color = UITheme.BAD
	elif lower.begins_with("sold") or lower.contains("paid") or lower.contains("bought"):
		color = UITheme.GOOD
	toast(text, color)

func toast(text: String, color: Color = UITheme.INK) -> void:
	if _toasts == null:
		return
	# The same line twice in a row counts up rather than stacking.
	var last := _toasts.get_child(_toasts.get_child_count() - 1) if _toasts.get_child_count() > 0 else null
	if last != null and last.get_meta("text", "") == text and not last.is_queued_for_deletion():
		var n: int = int(last.get_meta("count", 1)) + 1
		last.set_meta("count", n)
		(last.get_meta("label") as Label).text = "%s  x%d" % [text, n]
		_restart_fade(last)
		return
	var card := UIKit.panel("Toast")
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var row := UIKit.hbox(10)
	var stripe := ColorRect.new()
	stripe.color = color
	stripe.custom_minimum_size = Vector2(3, 0)
	row.add_child(stripe)
	var l := UIKit.label(text, "", 15)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 0
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	card.add_child(row)
	card.set_meta("text", text)
	card.set_meta("label", l)
	card.custom_minimum_size.x = minf(520.0, 40.0 + l.get_theme_font("font").get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x)
	_toasts.add_child(card)
	_ignore_mouse(card)
	while _toasts.get_child_count() > TOAST_MAX:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	_restart_fade(card)

func _restart_fade(card: Control) -> void:
	if card.has_meta("tween"):
		(card.get_meta("tween") as Tween).kill()
	card.modulate.a = 1.0
	var tween := card.create_tween()
	tween.tween_interval(TOAST_SECONDS)
	tween.tween_property(card, "modulate:a", 0.0, 0.8)
	tween.tween_callback(card.queue_free)
	card.set_meta("tween", tween)

## A big line across the upper middle: a new day, an order filled.
func show_banner(title: String, subtitle: String = "") -> void:
	_banner.text = title if subtitle == "" else "%s\n%s" % [title, subtitle.replace("[P]", "(P)")]
	var tween := _banner.create_tween()
	_banner.modulate.a = 0.0
	tween.tween_property(_banner, "modulate:a", 1.0, 0.25)
	tween.tween_interval(2.4)
	tween.tween_property(_banner, "modulate:a", 0.0, 0.6)

func flash_saved() -> void:
	var tween := _saved.create_tween()
	_saved.modulate.a = 1.0
	tween.tween_interval(1.2)
	tween.tween_property(_saved, "modulate:a", 0.0, 0.6)

func _on_item_sold(id: StringName, value: int) -> void:
	var name := GameData.item_name(id)
	_sold_name = name if _sold_count == 0 or _sold_name == name else ""
	_sold_count += 1
	_sold_value += value

func _on_money_changed(amount: int, delta: int) -> void:
	if delta == 0:
		_money_shown = amount
		return
	_money_delta += delta

func _flush_events() -> void:
	if _sold_count > 0:
		var what := _sold_name if _sold_name != "" else "items"
		if _sold_count == 1:
			toast("Sold %s for %s" % [what, UIKit.money(_sold_value)], UITheme.GOOD)
		else:
			toast("Sold %d %s for %s" % [_sold_count, what, UIKit.money(_sold_value)], UITheme.GOOD)
		_sold_count = 0
		_sold_value = 0
	if _money_delta != 0:
		_pop_money(_money_delta)
		_money_delta = 0

func _pop_money(delta: int) -> void:
	var pop := UIKit.label(("+" if delta > 0 else "") + UIKit.money(delta), "", 20,
		UITheme.GOOD if delta > 0 else UITheme.BAD)
	pop.add_theme_font_override("font", UITheme.display_font())
	pop.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	pop.add_theme_constant_override("outline_size", 5)
	pop.position = Vector2(0, 10)
	_money_pop.add_child(pop)
	var tween := pop.create_tween().set_parallel()
	tween.tween_property(pop, "position:y", -14.0, 1.4).set_ease(Tween.EASE_OUT)
	tween.tween_property(pop, "modulate:a", 0.0, 1.4).set_delay(0.5)
	tween.chain().tween_callback(pop.queue_free)

func _on_tutorial_advanced() -> void:
	var i := tutorial.current_index()
	if i < 0:
		show_banner("You're up and running", "Everything else is in the journal [Tab]".replace("[Tab]", "(Tab)"))
	else:
		var last: Dictionary = Tutorial.STEPS[i - 1] if i > 0 else {}
		if not last.is_empty():
			toast("Done: %s" % last.title, UITheme.GOOD)
	_update_tutorial()

func _update_tutorial() -> void:
	if _tutorial_card == null:
		return
	if tutorial == null or tutorial.finished() or not Settings.flag(&"show_tutorial"):
		_tutorial_card.visible = false
		return
	var step := tutorial.current()
	_tutorial_card.visible = true
	_tutorial_count.text = "%d / %d" % [tutorial.done_count() + 1, Tutorial.STEPS.size()]
	_tutorial_title.text = step.title
	for child in _tutorial_hint.get_children():
		child.queue_free()
	_tutorial_hint.add_child(_wrapped_key_text(step.hint, 294))

## Keycaps inline in a paragraph: an HFlowContainer of words and caps, so a long
## hint wraps where a label would.
static func _wrapped_key_text(text: String, width: float, size: int = 15) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.custom_minimum_size.x = width
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 3)
	for part in UIKit.parse_keys(text):
		if part[0] == "key":
			flow.add_child(UIKit.keycap(part[1], 11))
		else:
			for word in String(part[1]).split(" ", false):
				flow.add_child(UIKit.label(word, "Muted", size))
	return flow

# --- Journal ---------------------------------------------------------------

func journal_open() -> bool:
	return journal != null and journal.visible

func open_journal(tab: String) -> void:
	var i := journal.tab_index(tab)
	if journal.visible and journal.current_tab() == tab:
		journal.visible = false
		return
	journal.show_tab(i)
	journal.visible = true

func _on_journal_visibility() -> void:
	if player != null:
		player.set_ui_blocking(journal.visible)

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_TAB, KEY_J:
			open_journal("Orders")
		KEY_M:
			open_journal("Map")
		KEY_P:
			open_journal("Market")
		KEY_U:
			open_journal("Upgrades")
		KEY_F1:
			open_journal("Controls")
		KEY_H:
			Settings.set_value(&"show_hints", not Settings.flag(&"show_hints"))
		KEY_F3:
			show_debug = not show_debug
		KEY_ESCAPE:
			if journal_open():
				journal.visible = false
			elif build_system != null and build_system.active:
				build_system.set_active(false)
			elif world != null and world.has_method("pause_game"):
				world.call("pause_game")
		_:
			return
	get_viewport().set_input_as_handled()

# --- Per frame -------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null:
		return
	_flush_events()
	# Money counts up to its value rather than jumping.
	var target := float(Economy.money)
	if _money_shown != target:
		_money_shown = lerpf(_money_shown, target, clampf(delta * 8.0, 0.0, 1.0))
		if absf(_money_shown - target) < 1.0:
			_money_shown = target
		_money.text = UIKit.money(int(round(_money_shown)))

	var building := build_system != null and build_system.active
	var driving := player.driving()
	_crosshair.hot = player.last_prompt != "" and not building and not driving
	_crosshair.visible = not driving or player.steering_load()
	_set_prompt(_current_prompt(building, driving))

	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = 0.1
	_update_status()
	_update_orders()
	_update_hints(building, driving)
	_build_panel.visible = building
	# The build bar takes the bottom of the screen; the messages step up over it.
	var lift := 110.0 if building else 0.0
	_toasts.offset_bottom = -18.0 - lift
	_toasts.offset_top = -330.0 - lift
	if building:
		_update_build_bar()
	_drive_panel.visible = driving and not building
	if driving:
		_update_drive()
	_update_debug()

func _set_prompt(text: String) -> void:
	if text == _prompt_text:
		return
	_prompt_text = text
	_prompt_card.visible = text != ""
	if text != "":
		UIKit.fill_key_text(_prompt_rows, text, 17)
		_ignore_mouse(_prompt_rows)

## Build mode says what it needs to on the build bar. In the truck the prompt
## is the rig's, and only while it has hold of something.
func _current_prompt(building: bool, driving: bool) -> String:
	if building:
		return ""
	if driving:
		var r := player.rig()
		if r != null and (r.holding() or r.anchored):
			return r.status_line()
		return ""
	return player.last_prompt

func _update_status() -> void:
	_day.text = "DAY %d" % Economy.day
	_day_left.text = "%s until prices change" % UIKit.clock(Economy.seconds_left_today())
	_day_bar.value = Economy.day_progress()
	var cap := maxf(0.001, player.capacity_m3())
	var used := player.carried_volume()
	_rack.text = "%.2f / %.2f m³   ·   %d piece%s" % [used, cap, player.carried_count(),
		"" if player.carried_count() == 1 else "s"]
	_rack_bar.value = used / cap
	UIKit.tint_bar(_rack_bar, UITheme.BAD if used / cap > 0.95 else UITheme.INFO)
	_tools.text = "%s   ·   %s   ·   %s" % [PlayerState.label(&"axe"),
		PlayerState.label(&"hammer"), PlayerState.label(&"boots")]

func _update_orders() -> void:
	if quests == null:
		_orders_card.visible = false
		return
	var sig := ""
	for q in quests.active:
		sig += "%s:%.3f;" % [q.id, float(q.delivered)]
	if sig == _orders_sig:
		return
	_orders_sig = sig
	for child in _orders_box.get_children():
		child.queue_free()
	_orders_card.visible = not quests.active.is_empty()
	for q in quests.active:
		var col := UIKit.vbox(3)
		var top := UIKit.hbox(6)
		var t := UIKit.label(String(q.title), "", 16)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.clip_text = true
		top.add_child(t)
		top.add_child(UIKit.label("+" + UIKit.money(int(q.reward)), "", 16, UITheme.GOOD))
		col.add_child(top)
		var need := maxf(0.001, float(q.volume))
		col.add_child(UIKit.bar(float(q.delivered) / need, UITheme.ACCENT, 5))
		var want: String = GameData.item_name(q.item) if q.item != &"" \
			else String(q.category).capitalize()
		col.add_child(UIKit.label("%.2f / %.2f m³  %s" % [float(q.delivered), need, want], "Small"))
		_orders_box.add_child(col)
	_ignore_mouse(_orders_box)

func _hint_state(building: bool, driving: bool) -> String:
	if building:
		return "build"
	if driving:
		return "crane" if player.steering_load() else "drive"
	if player.dragged != null:
		return "dragging"
	if player.carried_count() > 0:
		return "carrying"
	return "foot"

func _update_hints(building: bool, driving: bool) -> void:
	var state := _hint_state(building, driving)
	if state == _hints_state:
		return
	_hints_state = state
	for child in _hints_box.get_children():
		child.queue_free()
	for row in KeyGuide.hints_for(state):
		_hints_box.add_child(UIKit.binding_row(row[0], row[1], 14, false))
	var foot := UIKit.hbox(5)
	foot.add_child(UIKit.keycap("H", 10))
	foot.add_child(UIKit.label("hide", "Small", 12))
	foot.alignment = BoxContainer.ALIGNMENT_END
	_hints_box.add_child(foot)
	for row in _hints_box.get_children():
		for caps in row.get_children():
			if caps is HBoxContainer:
				caps.custom_minimum_size.x = 84
	_ignore_mouse(_hints_box)

func _update_build_bar() -> void:
	var def := build_system.current()
	_build_name.text = def.display_name if def != null else "Nothing unlocked"
	_build_blurb.text = def.blurb if def != null else "Buy machines at the Store."
	var err := build_system.last_error
	_build_error.text = "" if err == "" or err == "no target" else err[0].to_upper() + err.substr(1)
	_build_error.visible = _build_error.text != ""
	var sig := "%d:%d:%d" % [build_system.index, build_system.palette.size(), Economy.money / 10]
	if sig == _build_sig:
		return
	_build_sig = sig
	for child in _build_slots.get_children():
		child.queue_free()
	var count := build_system.palette.size()
	if count == 0:
		return
	# A page of the palette at a time, with a marker when there is more.
	var first := build_system.bar_first()
	if first > 0:
		_build_slots.add_child(UIKit.label("<", "Header"))
	for i in range(first, mini(count, first + BuildSystem.BAR_SLOTS)):
		_build_slots.add_child(_slot(build_system.palette[i], i - first + 1, i == build_system.index))
	if first + BuildSystem.BAR_SLOTS < count:
		_build_slots.add_child(UIKit.label(">", "Header"))
	_ignore_mouse(_build_slots)

func _slot(def: BuildingDef, number: int, selected: bool) -> Control:
	var card := PanelContainer.new()
	var style := UITheme.box(Color(0.10, 0.13, 0.11, 0.92) if selected else UITheme.PANEL, 10,
		Vector4(10, 8, 10, 8), UITheme.ACCENT if selected else UITheme.EDGE, 2 if selected else 1)
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(128, 0)
	var col := UIKit.vbox(2)
	card.add_child(col)
	var top := UIKit.hbox(4)
	top.add_child(UIKit.keycap(str(number), 10))
	top.add_child(UIKit.spacer())
	top.add_child(UIKit.label("%dx%dx%d" % [def.size.x, def.size.y, def.size.z], "Small", 11))
	col.add_child(top)
	var name_label := UIKit.label(def.display_name, "", 14,
		UITheme.ACCENT if selected else UITheme.INK)
	name_label.add_theme_font_override("font", UITheme.font(600))
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size.x = 108
	col.add_child(name_label)
	col.add_child(UIKit.label(UIKit.money(def.cost), "", 14,
		UITheme.GOOD if Economy.can_afford(def.cost) else UITheme.BAD))
	return card

func _update_drive() -> void:
	var truck := player.vehicle as Hauler
	if truck == null:
		return
	_speed.text = str(int(round(truck.linear_velocity.length() * 3.6)))
	var cap := maxf(0.001, truck.cargo_capacity_m3)
	_cargo.text = "%.1f / %.1f m³   ·   %d" % [truck.cargo_volume(), cap, truck.cargo_count()]
	_cargo_bar.value = truck.cargo_volume() / cap
	var bits: Array[String] = []
	if truck.input_brake:
		bits.append("braking")
	if player.steering_load():
		bits.append("crane has a load")
	_drive_state.text = "   ·   ".join(bits) if not bits.is_empty() else "cargo is locked while you drive"

func _update_debug() -> void:
	var lines: Array[String] = []
	if Settings.flag(&"show_fps") or show_debug:
		lines.append("%d fps" % Engine.get_frames_per_second())
	if show_debug:
		var p := player.global_position
		lines.append("pos %.0f, %.0f, %.0f   loose %d / %d   buildings %d" % [p.x, p.y, p.z,
			manager.active_count(), manager.per_plot_cap, plot.placed.size()])
		var terrain: Terrain = player.terrain
		if terrain != null:
			lines.append("biome %s   water %.1f m" % [
				Terrain.Biome.keys()[terrain.biome_at(p.x, p.z)].to_lower(), player.water_depth()])
	_debug.text = "\n".join(lines)
	_debug.visible = not lines.is_empty()


## The centre of the screen: a dot, with a ring round it when there is
## something here to use.
class Crosshair extends Control:
	var hot: bool = false:
		set(v):
			if v != hot:
				hot = v
				queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 3.6, Color(0, 0, 0, 0.55))
		draw_circle(c, 2.3, Color(1, 1, 1, 0.95))
		if hot:
			draw_arc(c, 10.0, 0.0, TAU, 40, Color(0, 0, 0, 0.45), 4.0, true)
			draw_arc(c, 10.0, 0.0, TAU, 40, UITheme.ACCENT, 2.0, true)
