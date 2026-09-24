class_name InventoryPanel
extends Control

## The inventory: every tool you own, and the hotbar they go on. Drag a tool
## onto a slot (or click it to drop it in the next free one), right-click a
## slot to clear it. Opens with [I].

var player: Player
var _grid: GridContainer
var _bar: HBoxContainer
var _sig: String = ""

func _ready() -> void:
	UIKit.fill(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	UIKit.fill(shade)
	add_child(shade)
	var center := CenterContainer.new()
	UIKit.fill(center)
	add_child(center)
	var card := UIKit.panel("WindowPanel")
	card.custom_minimum_size = Vector2(780, 520)
	center.add_child(card)
	var col := UIKit.vbox(14)
	card.add_child(col)
	var head := UIKit.hbox(8)
	head.add_child(UIKit.label("Inventory", "Header"))
	head.add_child(UIKit.spacer())
	var close := UIKit.button("Close", func(): visible = false, "Ghost")
	close.focus_mode = Control.FOCUS_NONE
	head.add_child(close)
	col.add_child(head)
	var note := UIKit.label("Drag a tool onto the hotbar, or click it to add it. Right-click a slot to empty it. With nothing in hand, the left mouse button drags things.", "Muted", 14)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 740
	col.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)
	col.add_child(scroll)
	col.add_child(UIKit.label("HOTBAR", "Subheader", 13))
	_bar = UIKit.hbox(8)
	_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_bar)
	PlayerState.inventory_changed.connect(func(): _sig = "")
	visibility_changed.connect(func():
		_sig = ""
		if player != null:
			player.set_ui_blocking(visible))

func toggle() -> void:
	visible = not visible

func _process(_delta: float) -> void:
	if not visible:
		return
	var sig := "%s|%s|%d" % [",".join(PlayerState.tools), ",".join(PlayerState.hotbar),
		player.selected_slot if player != null else -1]
	if sig == _sig:
		return
	_sig = sig
	for c in _grid.get_children():
		c.queue_free()
	for c in _bar.get_children():
		c.queue_free()
	for id in PlayerState.tools:
		_grid.add_child(_tool_card(id))
	for i in PlayerState.HOTBAR_SLOTS:
		_bar.add_child(_Slot.new(i, player))

func _tool_card(id: StringName) -> Control:
	var def := GameData.tool(id)
	var card := _Card.new()
	card.tool_id = id
	card.custom_minimum_size = Vector2(178, 0)
	var on_bar := PlayerState.hotbar.has(id)
	card.add_theme_stylebox_override("panel", UITheme.box(UITheme.PANEL, 10, Vector4(10, 8, 10, 8),
		UITheme.ACCENT if on_bar else UITheme.EDGE, 2 if on_bar else 1))
	var row := UIKit.hbox(8)
	card.add_child(row)
	var icon := ToolIcon.new()
	icon.tool_id = id
	row.add_child(icon)
	var col := UIKit.vbox(0)
	row.add_child(col)
	var name_label := UIKit.label(String(def.get("display_name", id)), "", 14)
	name_label.add_theme_font_override("font", UITheme.font(600))
	col.add_child(name_label)
	col.add_child(UIKit.label(tool_line(def), "Small", 12))
	card.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and e.double_click == false:
			if not PlayerState.hotbar.has(id):
				var free := PlayerState.hotbar.find(&"")
				if free >= 0:
					PlayerState.set_hotbar(free, id))
	return card

static func tool_line(def: Dictionary) -> String:
	if String(def.get("kind", "")) == "hammer":
		return "hammer · %.0f kg head · %.2f s" % [float(def.get("head_kg", 3)), float(def.get("cooldown", 0.5))]
	return "axe · %.0f cut · %.2f s" % [float(def.get("damage", 34)), float(def.get("cooldown", 0.4))]

## A tool card you can pick up and drop on a slot.
class _Card extends PanelContainer:
	var tool_id: StringName
	func _get_drag_data(_at: Vector2) -> Variant:
		var icon := ToolIcon.new()
		icon.tool_id = tool_id
		icon.custom_minimum_size = Vector2(48, 48)
		set_drag_preview(icon)
		return {"tool": tool_id}

## A hotbar slot in the inventory window: a drop target.
class _Slot extends PanelContainer:
	var index: int
	var player: Player
	func _init(i: int, p: Player) -> void:
		index = i
		player = p
		custom_minimum_size = Vector2(70, 74)
		var id := PlayerState.hotbar_tool(i)
		var held := p != null and p.selected_slot == i
		add_theme_stylebox_override("panel", UITheme.box(UITheme.PANEL, 10, Vector4(6, 4, 6, 4),
			UITheme.ACCENT if held else UITheme.EDGE, 2 if held else 1))
		var col := UIKit.vbox(0)
		add_child(col)
		col.add_child(UIKit.keycap(str(i + 1), 10))
		var icon := ToolIcon.new()
		icon.tool_id = id
		col.add_child(icon)
		tooltip_text = GameData.tool_name(id) if id != &"" else "empty"
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("tool")
	func _drop_data(_at: Vector2, data: Variant) -> void:
		PlayerState.set_hotbar(index, StringName(data.tool))
	func _get_drag_data(_at: Vector2) -> Variant:
		var id := PlayerState.hotbar_tool(index)
		return {"tool": id} if id != &"" else null
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			PlayerState.set_hotbar(index, &"")
