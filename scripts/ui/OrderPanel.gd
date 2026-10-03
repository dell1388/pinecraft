class_name OrderPanel
extends Control

## A trader's order sheet (TradeCounter): a row for each thing the shop sells,
## its price a piece today, and buttons to order 1, 5, 10 or 25. Paid on the
## spot; the helper carries it out to the loading bay, into your truck if it
## is parked there.

var player: Player
var counter: TradeCounter
var _title: Label
var _rows: VBoxContainer
var _note: Label
var _money: Label

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
	card.custom_minimum_size = Vector2(620, 0)
	center.add_child(card)
	var col := UIKit.vbox(12)
	card.add_child(col)
	var head := UIKit.hbox(8)
	_title = UIKit.label("", "Header")
	head.add_child(_title)
	head.add_child(UIKit.spacer())
	var close := UIKit.button("Done", func(): visible = false)
	close.focus_mode = Control.FOCUS_NONE
	head.add_child(close)
	col.add_child(head)
	_money = UIKit.label("", "Subheader", 14)
	col.add_child(_money)
	_rows = UIKit.vbox(6)
	col.add_child(_rows)
	_note = UIKit.label("", "Small")
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = 580
	col.add_child(_note)
	visibility_changed.connect(func():
		if player != null:
			player.set_ui_blocking(visible))

func open(c: TradeCounter) -> void:
	counter = c
	_title.text = c.shop_name
	_note.text = "Paid now. %s carries it out to the loading bay: park your truck in the bay and it goes in the back, or it is stacked on the bay floor." % c.helper_name
	_refresh()
	visible = true

func _refresh() -> void:
	for ch in _rows.get_children():
		ch.queue_free()
	_money.text = "You have %s" % UIKit.money(Economy.money)
	var waiting := counter.post.queued() if counter.post != null else 0
	if waiting > 0:
		_money.text += "   ·   %d piece(s) still being loaded" % waiting
	for entry in counter.catalogue():
		var row := UIKit.hbox(8)
		var swatch := ColorRect.new()
		swatch.color = entry.color
		swatch.custom_minimum_size = Vector2(18, 18)
		row.add_child(swatch)
		var name_label := UIKit.label(String(entry.name))
		name_label.custom_minimum_size.x = 170
		row.add_child(name_label)
		var price := UIKit.label("%s each" % UIKit.money(int(entry.price)), "Muted")
		price.custom_minimum_size.x = 100
		row.add_child(price)
		for n in TradeCounter.AMOUNTS:
			var amount: int = n
			var id: StringName = entry.item
			var b := UIKit.button("x%d" % amount, func(): _order(id, amount))
			b.focus_mode = Control.FOCUS_NONE
			b.disabled = not Economy.can_afford(int(entry.price) * amount)
			b.tooltip_text = UIKit.money(int(entry.price) * amount)
			row.add_child(b)
		_rows.add_child(row)

func _order(id: StringName, amount: int) -> void:
	if counter == null or not is_instance_valid(counter):
		return
	var msg := counter.order(id, amount)
	if player != null:
		player.interacted.emit(msg)
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_pressed() and (Controls.pressed(event, &"pause") or (event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE)):
		visible = false
		get_viewport().set_input_as_handled()
