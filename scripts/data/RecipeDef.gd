class_name RecipeDef
extends Resource

## One machine recipe: N inputs -> M outputs over a fixed time.

@export var id: StringName = &""
@export var machine: StringName = &""
@export var inputs: Dictionary = {}     ## StringName -> int
@export var outputs: Dictionary = {}    ## StringName -> int
@export var seconds: float = 2.0

static func from_dict(d: Dictionary) -> RecipeDef:
	var r := RecipeDef.new()
	r.id = StringName(d.get("id", "unknown"))
	r.machine = StringName(d.get("machine", ""))
	r.seconds = float(d.get("seconds", 2.0))
	for entry in d.get("inputs", []):
		r.inputs[StringName(entry["item"])] = int(entry.get("count", 1))
	for entry in d.get("outputs", []):
		r.outputs[StringName(entry["item"])] = int(entry.get("count", 1))
	return r

## True when `buffer` (StringName -> int) holds everything this recipe needs.
func satisfied_by(buffer: Dictionary) -> bool:
	for item_id in inputs:
		if int(buffer.get(item_id, 0)) < int(inputs[item_id]):
			return false
	return true

func consume_from(buffer: Dictionary) -> void:
	for item_id in inputs:
		buffer[item_id] = int(buffer[item_id]) - int(inputs[item_id])
		if int(buffer[item_id]) <= 0:
			buffer.erase(item_id)
