class_name MachineDef
extends Resource

## Static description of a machine type; recipes are looked up separately.

@export var id: StringName = &""
@export var display_name: String = ""
@export var input_slots: int = 12        ## items that fit in the input buffer
@export var output_backlog: int = 10     ## unclaimed outputs before the machine stalls
@export var color: Color = Color(0.4, 0.4, 0.4)

static func from_dict(d: Dictionary) -> MachineDef:
	var m := MachineDef.new()
	m.id = StringName(d.get("id", "unknown"))
	m.display_name = String(d.get("display_name", "Machine"))
	m.input_slots = int(d.get("input_slots", 12))
	m.output_backlog = int(d.get("output_backlog", 10))
	var c: Array = d.get("color", [0.4, 0.4, 0.4])
	m.color = Color(c[0], c[1], c[2])
	return m
