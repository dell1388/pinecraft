class_name Journal
extends Control

## The in-game book: orders, today's prices, upgrades and land, and the
## controls. Opens over play without pausing it - the belts keep running while
## you read the market.

const TABS := ["Orders", "Map", "Market", "Upgrades", "Controls"]

var quests: QuestLog
var plot: Plot
var tutorial: Tutorial
var world: Node
var _map: MapView
var _tab_buttons: Array[Button] = []
var _body: VBoxContainer
var _tab: int = 0
var _refresh: float = 0.0
var _built_sig: String = ""
var _clock_label: Label
var _title: Label

func _ready() -> void:
	UIKit.fill(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	UIKit.fill(shade)
	add_child(shade)
	var center := CenterContainer.new()
	UIKit.fill(center)
	add_child(center)
	var card := UIKit.panel("WindowPanel")
	card.custom_minimum_size = Vector2(860, 600)
	center.add_child(card)
	var col := UIKit.vbox(14)
	card.add_child(col)

	var head := UIKit.hbox(8)
	_title = UIKit.label("Journal", "Header")
	head.add_child(_title)
	head.add_child(UIKit.spacer(false, 18))
	for i in TABS.size():
		var tab := UIKit.button(TABS[i], show_tab.bind(i), "Tab")
		tab.toggle_mode = true
		# Tab closes the journal; a focused button would take it for focus.
		tab.focus_mode = Control.FOCUS_NONE
		_tab_buttons.append(tab)
		head.add_child(tab)
	head.add_child(UIKit.spacer())
	var close := UIKit.button("Close", func(): visible = false, "Ghost")
	close.focus_mode = Control.FOCUS_NONE
	head.add_child(close)
	col.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body = UIKit.vbox(8)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	col.add_child(scroll)
	visible = false

func tab_index(name: String) -> int:
	return TABS.find(name)

func current_tab() -> String:
	return TABS[_tab]

func show_tab(i: int) -> void:
	_tab = clampi(i, 0, TABS.size() - 1)
	for j in _tab_buttons.size():
		_tab_buttons[j].set_pressed_no_signal(j == _tab)
	_rebuild()

## Rebuilding a page is tens of milliseconds of UI, so a page is rebuilt only
## when what it shows has changed - not once a second while it is open, which
## is a stutter you can feel.
func _process(delta: float) -> void:
	if not visible:
		return
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = 0.5
	if _clock_label != null and is_instance_valid(_clock_label):
		_clock_label.text = _market_note()
	var sig := _signature()
	if sig != _built_sig:
		_rebuild()

func _signature() -> String:
	match TABS[_tab]:
		"Orders":
			var sig := ""
			if quests != null:
				for q in quests.active:
					sig += "%s:%.3f;" % [q.id, float(q.delivered)]
			if tutorial != null:
				sig += "t%d" % tutorial.done_count()
			return sig
		"Market":
			return "day%d" % Economy.day
		"Upgrades":
			var sig := "m%d;" % Economy.money
			for track in GameData.upgrade_tracks:
				sig += "%d" % PlayerState.level(track)
			return sig + "u%d" % PlayerState.unlocked_buildings.size()
	return TABS[_tab]

func _market_note() -> String:
	return "Day %d  ·  prices redraw in %s. Wood, lumber and billets are priced by volume, so milling never creates or destroys value - only the rate changes." % [
		Economy.day, UIKit.clock(Economy.seconds_left_today())]

func _rebuild() -> void:
	_built_sig = _signature()
	_clock_label = null
	for child in _body.get_children():
		child.queue_free()
	match TABS[_tab]:
		"Orders":
			_orders()
		"Map":
			_map_page()
		"Market":
			_market()
		"Upgrades":
			_upgrades()
		"Controls":
			_body.add_child(KeyGuide.sheet())

func _map_page() -> void:
	var row := UIKit.hbox(18)
	_map = MapView.new()
	_map.world = world
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_map)
	var side := UIKit.vbox(6)
	side.custom_minimum_size.x = 230
	side.add_child(UIKit.label("PLACES", "Subheader"))
	if world != null:
		var found := 0
		var pois: Array = world.call("points_of_interest")
		for poi in pois:
			var known: bool = world.call("discovered", poi.name)
			if known:
				found += 1
			var line := UIKit.hbox(8)
			var dot := ColorRect.new()
			dot.custom_minimum_size = Vector2(10, 10)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			dot.color = poi.color if known else UITheme.FAINT
			line.add_child(dot)
			line.add_child(UIKit.label(poi.name if known else "undiscovered", "", 15,
				UITheme.INK if known else UITheme.FAINT))
			side.add_child(line)
		side.add_child(UIKit.spacer(false, 8))
		side.add_child(UIKit.label("%d of %d found" % [found, pois.size()], "Small"))
	var note := UIKit.label("Traders pay over the day's rate for what they are short of. Supply caches restock every market day. Caves are dark - and where most of the gold is.", "Small")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(note)
	row.add_child(side)
	_body.add_child(row)

func _note(text: String) -> void:
	var l := UIKit.label(text, "Muted", 15)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)

func _section(text: String) -> void:
	_body.add_child(UIKit.spacer(false, 4))
	_body.add_child(UIKit.label(text.to_upper(), "Subheader"))

func _orders() -> void:
	_note("Orders are bought at the Sell Yard. Deliver the material and the bonus is paid on top of the sale price.")
	if quests == null or quests.active.is_empty():
		_note("No orders right now.")
	else:
		for quest in quests.active:
			_body.add_child(_order_row(quest))
	if tutorial != null and Settings.flag(&"show_tutorial"):
		_section("Getting started  %d / %d" % [tutorial.done_count(), Tutorial.STEPS.size()])
		for step in Tutorial.STEPS:
			var row := UIKit.hbox(10)
			var is_done := tutorial.done(step.id)
			var mark := UIKit.label("DONE" if is_done else "  -  ", "Small",
				12, UITheme.GOOD if is_done else UITheme.FAINT)
			mark.custom_minimum_size.x = 44
			row.add_child(mark)
			row.add_child(UIKit.label(step.title, "", 16,
				UITheme.MUTED if is_done else UITheme.INK))
			_body.add_child(row)

static func _order_row(quest: Dictionary) -> Control:
	var shell := UIKit.panel("Row")
	var col := UIKit.vbox(5)
	shell.add_child(col)
	var top := UIKit.hbox(8)
	var title := UIKit.label(String(quest.title), "", 18)
	title.add_theme_font_override("font", UITheme.font(600))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UIKit.label("+" + UIKit.money(int(quest.reward)), "", 18, UITheme.GOOD))
	col.add_child(top)
	var want: String = GameData.item_name(quest.item) if quest.item != &"" \
		else String(quest.category).capitalize()
	var got := float(quest.delivered)
	var need := maxf(0.001, float(quest.volume))
	col.add_child(UIKit.bar(got / need, UITheme.ACCENT, 7))
	col.add_child(UIKit.label("%.2f of %.2f m³ %s delivered" % [got, need, want], "Small"))
	return shell

func _market() -> void:
	_note(_market_note())
	_clock_label = _body.get_child(_body.get_child_count() - 1) as Label
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 6)
	for h in ["Material", "Price", "Today", ""]:
		grid.add_child(UIKit.label(h.to_upper(), "Subheader"))
	var rows: Array = Economy.market_rows()
	rows.reverse()
	for row in rows:
		var name_label := UIKit.label(String(row.name))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_label)
		grid.add_child(UIKit.label("%s / %s" % [UIKit.money(int(round(float(row.rate)))),
			"m³" if row.unit == "m3" else row.unit]))
		var m := float(row.multiplier)
		var pct := int(round((m - 1.0) * 100.0))
		var tint := UITheme.GOOD if pct > 2 else (UITheme.BAD if pct < -2 else UITheme.MUTED)
		grid.add_child(UIKit.label("%+d%%" % pct, "", 17, tint))
		var trend := UIKit.bar(clampf((m - 0.6) / 0.8, 0.0, 1.0), tint, 6)
		trend.custom_minimum_size.x = 120
		trend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(trend)
	_body.add_child(grid)

func _upgrades() -> void:
	_note("Upgrades and machines are bought at the Store: carry the box to the till and press [E]. Land is sold at the desk by the door.")
	_section("Tools and machines")
	for track_id in GameData.upgrade_tracks:
		var track: Dictionary = GameData.upgrade_tracks[track_id]
		var shell := UIKit.panel("Row")
		var row := UIKit.hbox(12)
		shell.add_child(row)
		var what := UIKit.vbox(2)
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		what.add_child(UIKit.label(String(track.get("display_name", track_id)), "Small"))
		what.add_child(UIKit.label(PlayerState.label(track_id), "", 18))
		row.add_child(what)
		var lv := PlayerState.level(track_id)
		var top := GameData.max_upgrade_level(track_id)
		var pips := UIKit.hbox(4)
		for i in top:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(16, 6)
			pip.color = UITheme.ACCENT if i < lv else Color(1, 1, 1, 0.12)
			pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pips.add_child(pip)
		row.add_child(pips)
		var cost := PlayerState.next_cost(track_id)
		var price := UIKit.label("MAX" if cost < 0 else "next " + UIKit.money(cost), "", 16,
			UITheme.FAINT if cost < 0 else (UITheme.GOOD if Economy.can_afford(cost) else UITheme.MUTED))
		price.custom_minimum_size.x = 120
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(price)
		_body.add_child(shell)

	if plot != null:
		_section("Land")
		var expand_cost := plot.next_expansion_cost()
		_note("Tier %d, %.0f m across. Next parcel: %s." % [plot.tier, plot.half_extent * 2.0,
			"none left" if expand_cost < 0 else UIKit.money(expand_cost)])

	_section("Still on the shelf")
	var any := false
	for def: BuildingDef in GameData.buildings.values():
		if PlayerState.is_unlocked(def.id):
			continue
		any = true
		var row := UIKit.hbox(12)
		var n := UIKit.label(def.display_name)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		row.add_child(UIKit.label("unlock %s  ·  build %s" % [UIKit.money(def.unlock_cost),
			UIKit.money(def.cost)], "Muted"))
		_body.add_child(row)
	if not any:
		_note("Nothing - you own one of everything.")
