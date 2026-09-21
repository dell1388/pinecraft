class_name Filter
extends Splitter

## Belt logic: items matching the configured type continue straight ahead,
## everything else is pushed out to the right. Interacting cycles the filter
## through the item table, so a plot can sort planks from ingots without the
## player standing there.

@export var filter_item: StringName = &"log_pine"
@export var invert: bool = false

const OUT_LEFT := 0
const OUT_STRAIGHT := 1
const OUT_RIGHT := 2

func _init() -> void:
	body_color = Color(0.34, 0.30, 0.16)

func _ready() -> void:
	if def == null:
		def = GameData.building(&"filter")
	super()

func route_index_for(item: LooseItem) -> int:
	var matched := item.item_id == filter_item
	if invert:
		matched = not matched
	return OUT_STRAIGHT if matched else OUT_RIGHT

## Cycles the accepted item type. Returns the new selection's display name.
func cycle_filter(step: int = 1) -> String:
	var ids: Array = GameData.items.keys()
	if ids.is_empty():
		return ""
	var index := ids.find(filter_item)
	filter_item = ids[wrapi(index + step, 0, ids.size())]
	return GameData.item_name(filter_item)

func status_line() -> String:
	return "Filter: %s %s -> straight, rest -> right" % [
		"NOT " if invert else "", GameData.item_name(filter_item)]

func to_dict() -> Dictionary:
	return {"filter_item": String(filter_item), "invert": invert}

func from_dict(d: Dictionary) -> void:
	filter_item = StringName(d.get("filter_item", "log_pine"))
	invert = bool(d.get("invert", false))
