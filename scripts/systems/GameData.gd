extends Node

## Autoload. Loads every JSON data table once and hands out typed definitions.
## Nothing in the game hard-codes item stats, recipes, costs or prices.

const DATA_DIR := "res://data/"

var items: Dictionary = {}          ## StringName -> ItemDef
var recipes: Dictionary = {}        ## StringName -> RecipeDef
var recipes_by_machine: Dictionary = {}  ## StringName -> Array[RecipeDef]
var buildings: Dictionary = {}      ## StringName -> BuildingDef
var machines: Dictionary = {}       ## StringName -> MachineDef
var upgrade_tracks: Dictionary = {} ## StringName -> Array[Dictionary]
var plot_expansions: Array = []
var vehicle_def: Dictionary = {}
var price_config: Dictionary = {}

var load_errors: Array[String] = []

func _ready() -> void:
	load_all()

func load_all() -> void:
	load_errors.clear()
	items.clear()
	recipes.clear()
	recipes_by_machine.clear()
	buildings.clear()
	machines.clear()
	upgrade_tracks.clear()
	plot_expansions.clear()

	for entry in _read("items.json").get("items", []):
		var def := ItemDef.from_dict(entry)
		items[def.id] = def

	for entry in _read("recipes.json").get("recipes", []):
		var r := RecipeDef.from_dict(entry)
		recipes[r.id] = r
		if not recipes_by_machine.has(r.machine):
			recipes_by_machine[r.machine] = [] as Array[RecipeDef]
		recipes_by_machine[r.machine].append(r)

	var b_data := _read("buildings.json")
	for entry in b_data.get("buildings", []):
		var b := BuildingDef.from_dict(entry)
		buildings[b.id] = b
	for entry in b_data.get("machines", []):
		var m := MachineDef.from_dict(entry)
		machines[m.id] = m

	var u_data := _read("upgrades.json")
	for track in u_data.get("tracks", []):
		upgrade_tracks[StringName(track["id"])] = track
	plot_expansions = u_data.get("plot_expansions", [])
	vehicle_def = u_data.get("vehicle", {})

	price_config = _read("prices.json")
	_validate()

func _read(file_name: String) -> Dictionary:
	var path := DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		load_errors.append("missing data file: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		load_errors.append("malformed JSON: %s" % path)
		return {}
	return parsed

## Cross-checks every reference between the tables, so a typo in a data file
## surfaces at load instead of as a silent no-op three systems later.
func _validate() -> void:
	var categories: Dictionary = {}
	for def: ItemDef in items.values():
		categories[def.category] = true
	for r: RecipeDef in recipes.values():
		if not machines.has(r.machine):
			load_errors.append("recipe '%s' targets unknown machine '%s'" % [r.id, r.machine])
		for category in r.inputs:
			if not categories.has(category):
				load_errors.append("recipe '%s' wants unknown category '%s'" % [r.id, category])
		if not items.has(r.output):
			load_errors.append("recipe '%s' produces unknown item '%s'" % [r.id, r.output])
	for m: MachineDef in machines.values():
		for category in m.accepts:
			if not categories.has(category):
				load_errors.append("machine '%s' accepts unknown category '%s'" % [m.id, category])
		for input_id in m.conversion:
			if not items.has(input_id):
				load_errors.append("machine '%s' converts unknown item '%s'" % [m.id, input_id])
			elif not items.has(m.conversion[input_id]):
				load_errors.append("machine '%s' produces unknown item '%s'" % [m.id, m.conversion[input_id]])
	for b: BuildingDef in buildings.values():
		if b.kind == &"machine" and not machines.has(b.machine):
			load_errors.append("building '%s' references unknown machine '%s'" % [b.id, b.machine])
	for e in load_errors:
		push_error("GameData: %s" % e)

# --- Lookups ---------------------------------------------------------------

func item(id: StringName) -> ItemDef:
	return items.get(id)

func item_name(id: StringName) -> String:
	var def: ItemDef = items.get(id)
	return def.display_name if def != null else String(id)

func building(id: StringName) -> BuildingDef:
	return buildings.get(id)

func machine(id: StringName) -> MachineDef:
	return machines.get(id)

func machine_recipes(machine_id: StringName) -> Array:
	return recipes_by_machine.get(machine_id, [])

## First assembly recipe on `machine_id` whose inputs are covered by `stock`
## (category -> cubic metres).
func first_ready_recipe(machine_id: StringName, stock: Dictionary) -> RecipeDef:
	for r: RecipeDef in machine_recipes(machine_id):
		if r.satisfied_by(stock):
			return r
	return null

## Whether this machine has any use for the item at all. Used to reject items
## rather than swallow them.
func machine_accepts(machine_id: StringName, item_id: StringName) -> bool:
	var m: MachineDef = machines.get(machine_id)
	var def: ItemDef = items.get(item_id)
	if m == null or def == null:
		return false
	if not m.accepts_category(def.category):
		return false
	if m.mode == MachineDef.MODE_ASSEMBLE:
		return true
	return m.output_for(item_id) != &""

func upgrade_levels(track_id: StringName) -> Array:
	var track: Dictionary = upgrade_tracks.get(track_id, {})
	return track.get("levels", [])

func upgrade_level(track_id: StringName, level: int) -> Dictionary:
	var levels := upgrade_levels(track_id)
	if levels.is_empty():
		return {}
	return levels[clampi(level - 1, 0, levels.size() - 1)]

func max_upgrade_level(track_id: StringName) -> int:
	return upgrade_levels(track_id).size()

func expansion(tier: int) -> Dictionary:
	if plot_expansions.is_empty():
		return {}
	return plot_expansions[clampi(tier, 0, plot_expansions.size() - 1)]

func max_expansion_tier() -> int:
	return maxi(0, plot_expansions.size() - 1)
