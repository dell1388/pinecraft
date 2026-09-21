class_name RecipeDef
extends Resource

## An assembly recipe: volumes of material by category in, one finished good out.

@export var id: StringName = &""
@export var machine: StringName = &"workbench"
@export var inputs: Dictionary = {}     ## StringName category -> float cubic metres
@export var output: StringName = &"crate"
@export var seconds: float = 6.0

static func from_dict(d: Dictionary) -> RecipeDef:
	var r := RecipeDef.new()
	r.id = StringName(d.get("id", "unknown"))
	r.machine = StringName(d.get("machine", "workbench"))
	r.output = StringName(d.get("output", "crate"))
	r.seconds = float(d.get("seconds", 6.0))
	for k in d.get("inputs", {}):
		r.inputs[StringName(k)] = float(d["inputs"][k])
	return r

## True when `stock` (category -> cubic metres) covers every input.
func satisfied_by(stock: Dictionary) -> bool:
	for category in inputs:
		if float(stock.get(category, 0.0)) + 0.0001 < float(inputs[category]):
			return false
	return true

func consume_from(stock: Dictionary) -> void:
	for category in inputs:
		stock[category] = float(stock.get(category, 0.0)) - float(inputs[category])
		if float(stock[category]) <= 0.0001:
			stock.erase(category)

func summary() -> String:
	var parts: Array[String] = []
	for category in inputs:
		parts.append("%.3f m3 %s" % [float(inputs[category]), String(category)])
	return "%s -> %s" % [" + ".join(parts), String(output)]
