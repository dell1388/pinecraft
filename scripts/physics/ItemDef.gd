class_name ItemDef
extends Resource

## Data-driven item definition, loaded from data/items.json.
##
## An item is a solid with a density and a price per cubic metre. "Variable"
## items (wood, lumber, billets) carry their own dimensions at runtime, so a
## 4 m trunk and a 1 m log are the same item id at different sizes.

@export var id: StringName = &"wood_pine"
@export var display_name: String = "Pine Wood"
@export var category: StringName = &"wood"
@export var shape: StringName = Solid.CYLINDER
@export var variable: bool = true
@export var density: float = 150.0           ## kg per cubic metre (game-scaled)
@export var value_per_m3: float = 22.0
@export var fixed_value: int = 0             ## set for goods priced per piece
@export var volatility: float = 0.25
## Whether the yard will buy this. False for things that are containers for
## something else, like an unopened crate of tools from the store.
@export var sellable: bool = true
## Whether picking this up is enough to own it. False for store stock, which
## has to go over the counter first.
@export var must_buy: bool = false
@export var color: Color = Color(0.47, 0.32, 0.19)
## This material's own price multiplier per finish (sanded, polished, refined),
## set from the materials table at load. Anything missing uses Solid's default.
@export var finish_value: Dictionary = {}

## Defaults used when a spawn does not specify dimensions.
@export var default_size: Vector3 = Vector3(0.3, 0.3, 0.3)
@export var radius: float = 0.18
@export var length: float = 1.6
@export var taper: float = 0.86
@export var cross_section: Vector2 = Vector2(0.3, 0.3)

func default_dims() -> Dictionary:
	if shape == Solid.CYLINDER:
		return Solid.cylinder(radius, radius * taper, length)
	if variable:
		return Solid.box(Vector3(cross_section.x, length, cross_section.y))
	return Solid.box(default_size)

func volume_of(dims: Dictionary) -> float:
	return Solid.volume(dims)

func mass_of(dims: Dictionary) -> float:
	return maxf(0.5, density * Solid.volume(dims))

## Price of one piece at the base rate, before the day's market multiplier.
func base_value_of(dims: Dictionary) -> float:
	if fixed_value > 0:
		return float(fixed_value)
	return value_per_m3 * Solid.volume(dims) * Solid.quality(dims, finish_value)

static func from_dict(d: Dictionary) -> ItemDef:
	var def := ItemDef.new()
	def.id = StringName(d.get("id", "unknown"))
	def.display_name = String(d.get("display_name", "Unknown"))
	def.category = StringName(d.get("category", "misc"))
	def.shape = StringName(d.get("shape", "box"))
	def.variable = bool(d.get("variable", false))
	def.density = float(d.get("density", 300.0))
	def.value_per_m3 = float(d.get("value_per_m3", 0.0))
	def.fixed_value = int(d.get("value", 0))
	def.volatility = float(d.get("volatility", 0.25))
	def.sellable = bool(d.get("sellable", true))
	def.must_buy = bool(d.get("must_buy", false))
	var c: Array = d.get("color", [0.6, 0.6, 0.6])
	def.color = Color(c[0], c[1], c[2])
	if d.has("size"):
		var s: Array = d["size"]
		def.default_size = Vector3(s[0], s[1], s[2])
	if d.has("cross_section"):
		var cs: Array = d["cross_section"]
		def.cross_section = Vector2(cs[0], cs[1])
	def.radius = float(d.get("radius", 0.18))
	def.length = float(d.get("length", 1.6))
	def.taper = float(d.get("taper", 1.0))
	return def

static func defaults() -> Array[ItemDef]:
	# Minimal fallback so scenes can run without the data files present.
	var wood := ItemDef.new()
	var lumber := ItemDef.new()
	lumber.id = &"lumber_pine"
	lumber.display_name = "Pine Lumber"
	lumber.category = &"lumber"
	lumber.shape = Solid.BOX
	lumber.variable = true
	lumber.cross_section = Vector2(0.3, 0.3)
	lumber.length = 1.55
	lumber.density = 140.0
	lumber.value_per_m3 = 72.0
	lumber.color = Color(0.74, 0.57, 0.34)
	return [wood, lumber]
