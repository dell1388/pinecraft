class_name ItemDef
extends Resource

## Data-driven item definition. Loaded from data/items.json at runtime; the
## defaults below exist so the stress-test scene can run standalone.

@export var id: StringName = &"log_pine"
@export var display_name: String = "Pine Log"
@export var size: Vector3 = Vector3(0.35, 0.35, 1.6)
@export var mass: float = 8.0
@export var color: Color = Color(0.45, 0.30, 0.18)
@export var base_value: int = 3
@export var category: StringName = &"misc"
@export var volatility: float = 0.25

static func make(p_id: StringName, p_name: String, p_size: Vector3, p_mass: float,
		p_color: Color, p_value: int) -> ItemDef:
	var d := ItemDef.new()
	d.id = p_id
	d.display_name = p_name
	d.size = p_size
	d.mass = p_mass
	d.color = p_color
	d.base_value = p_value
	return d

static func defaults() -> Array[ItemDef]:
	return [
		make(&"log_pine", "Pine Log", Vector3(0.35, 0.35, 1.6), 8.0, Color(0.45, 0.30, 0.18), 3),
		make(&"log_oak", "Oak Log", Vector3(0.42, 0.42, 1.7), 12.0, Color(0.36, 0.24, 0.14), 6),
		make(&"plank", "Plank", Vector3(0.18, 0.08, 1.4), 3.0, Color(0.72, 0.55, 0.32), 9),
		make(&"ore_iron", "Iron Ore", Vector3(0.45, 0.40, 0.45), 14.0, Color(0.52, 0.53, 0.58), 11),
		make(&"ingot_iron", "Iron Ingot", Vector3(0.5, 0.18, 0.24), 9.0, Color(0.70, 0.72, 0.78), 26),
	]

static func from_dict(d: Dictionary) -> ItemDef:
	var s: Array = d.get("size", [0.35, 0.35, 1.6])
	var c: Array = d.get("color", [1.0, 1.0, 1.0])
	var def := make(
		StringName(d.get("id", "unknown")),
		String(d.get("display_name", "Unknown")),
		Vector3(s[0], s[1], s[2]),
		float(d.get("mass", 5.0)),
		Color(c[0], c[1], c[2]),
		int(d.get("base_value", 1)))
	def.category = StringName(d.get("category", "misc"))
	def.volatility = float(d.get("volatility", 0.25))
	return def
