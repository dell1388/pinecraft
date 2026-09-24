class_name PauseMenu
extends CanvasLayer

## Esc in play. The world stops behind frosted glass; everything the old
## function keys did is here as a button, with the keys still working.

signal resume_requested
signal home_requested
signal save_requested
signal load_requested
signal main_menu_requested
signal quit_requested

var _root: Control
var _card: PanelContainer
var _content: VBoxContainer
var _stats: Label
var _dialog: Control
var _on_subpage: bool = false

func _init() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _ready() -> void:
	_root = UIKit.fill(Control.new())
	_root.theme = UITheme.theme()
	add_child(_root)
	_root.add_child(UIKit.frosted())
	var center := CenterContainer.new()
	UIKit.fill(center)
	_root.add_child(center)
	_card = UIKit.panel("WindowPanel")
	center.add_child(_card)
	_content = UIKit.vbox(10)
	_card.add_child(_content)

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_main()

func close() -> void:
	visible = false
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null

func _clear() -> void:
	for child in _content.get_children():
		child.queue_free()

func _show_main() -> void:
	_clear()
	_on_subpage = false
	_card.custom_minimum_size = Vector2(420, 0)
	_content.add_child(UIKit.label("Paused", "Header", 44))
	_stats = UIKit.label("Day %d   ·   %s   ·   earned %s so far" % [
		Economy.day, UIKit.money(Economy.money), UIKit.money(Economy.total_earned)], "Muted")
	_content.add_child(_stats)
	_content.add_child(UIKit.spacer(false, 8))
	var first := _add("Resume", func(): resume_requested.emit())
	_add("Return to base", func(): home_requested.emit())
	_add("Settings", func(): _show_page("Settings", SettingsPanel.new()))
	_add("Controls", func(): _show_page("Controls", KeyGuide.sheet()))
	_add_row([["Save  [F5]", func(): save_requested.emit()],
		["Load  [F9]", _confirm_load]])
	_content.add_child(HSeparator.new())
	_add_row([["Main menu", func(): main_menu_requested.emit()],
		["Quit to desktop", func(): quit_requested.emit()]])
	var note := UIKit.label("Your game saves when you leave for the menu or quit.", "Small")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(note)
	first.grab_focus.call_deferred()

func _add(text: String, action: Callable) -> Button:
	var b := UIKit.button(text, action)
	b.custom_minimum_size.y = 46
	_content.add_child(b)
	return b

func _add_row(entries: Array) -> void:
	var row := UIKit.hbox(10)
	for entry in entries:
		var b := UIKit.button(entry[0], entry[1])
		b.custom_minimum_size.y = 42
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	_content.add_child(row)

## A yes/no over the pause menu that Esc cancels.
func ask(title: String, body: String, yes_text: String, on_yes: Callable) -> void:
	_dialog = UIKit.confirm(_root, title, body, yes_text, on_yes)

func _confirm_load() -> void:
	if not SaveSystem.has_save():
		return
	_dialog = UIKit.confirm(_root, "Load your last save?",
		"Anything since you last saved will be lost.", "Load",
		func(): load_requested.emit())

func _show_page(title: String, page: Control) -> void:
	_clear()
	_on_subpage = true
	_card.custom_minimum_size = Vector2(760, 0)
	var head := UIKit.hbox(10)
	var name_label := UIKit.label(title, "Header")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	head.add_child(UIKit.button("Back", _show_main, "Ghost"))
	_content.add_child(head)
	_content.add_child(page)

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
	elif _on_subpage:
		_show_main()
	else:
		resume_requested.emit()
