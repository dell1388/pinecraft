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
## Every vehicle's spec, as read from vehicles.json: id -> Dictionary.
var vehicles: Dictionary = {}
## Hand tools, id -> Dictionary, and the ones a new player starts with.
var tools: Dictionary = {}
var start_tools: Array[StringName] = []
var price_config: Dictionary = {}
var quest_config: Dictionary = {}
var store_config: Dictionary = {}

var load_errors: Array[String] = []
## What each material is worth along its processing path: id -> {path, raw_item,
## final_item, raw, pre, final, note}, all in $ per m3 of the raw material.
var materials: Dictionary = {}
## Raw or finished item id -> material id, both ways round.
var material_of: Dictionary = {}

## How much of a log's volume the planker keeps: a plank 1.8 r wide and 0.8 r
## thick out of a round of radius r.
const PLANK_SHARE := 1.44 / PI
## The bonus a finished piece (a plank, a jewel) gets for having been through
## the first step (sanded, polished) before it was shaped. The rest of the
## first step's worth is in the raw material's own bonus.
const CARRIED_FINISH := 1.2

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

	tools.clear()
	start_tools.clear()
	var t_data := _read("tools.json")
	for entry in t_data.get("tools", []):
		tools[StringName(entry["id"])] = entry
	for id in t_data.get("start", []):
		start_tools.append(StringName(id))

	vehicles.clear()
	for entry in _read("vehicles.json").get("vehicles", []):
		vehicles[StringName(entry["id"])] = entry

	_apply_materials(_read("items.json").get("materials", []))
	price_config = _read("prices.json")
	quest_config = _read("quests.json")
	store_config = _read("store.json")
	_make_boxes()
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

## Prices every stage of every material from its raw / pre / final values.
## The table is written per cubic metre of raw material, so here each stage's
## price is worked back through what the machines keep of the volume:
##   wood   log (raw)  -> sanded log (pre)  -> sanded plank (final)
##   metal  ore (raw)  -> smelted bar (pre) -> refined bar (final)
##   gem    rough (raw)-> polished (pre)    -> cut jewel (final)
func _apply_materials(table: Array) -> void:
	materials.clear()
	material_of.clear()
	var smelt_yield := 0.6
	var cut_yield := 0.5
	for m: MachineDef in machines.values():
		if m.mode == MachineDef.MODE_SMELT:
			smelt_yield = m.yield_share
		elif m.mode == MachineDef.MODE_CUT:
			cut_yield = m.yield_share
	for entry in table:
		var id := StringName(entry.get("id", ""))
		var raw_def: ItemDef = items.get(StringName(entry.get("raw_item", "")))
		var final_def: ItemDef = items.get(StringName(entry.get("final_item", "")))
		if raw_def == null or final_def == null:
			load_errors.append("material '%s' names an unknown item" % id)
			continue
		var raw := float(entry.get("raw", 1.0))
		var pre := float(entry.get("pre", raw))
		var fin := float(entry.get("final", pre))
		materials[id] = entry
		material_of[raw_def.id] = id
		material_of[final_def.id] = id
		raw_def.value_per_m3 = raw
		match String(entry.get("path", "")):
			"wood":
				raw_def.finish_value = {&"sanded": pre / raw}
				final_def.finish_value = {&"sanded": CARRIED_FINISH}
				final_def.value_per_m3 = fin / (PLANK_SHARE * CARRIED_FINISH)
			"metal":
				final_def.value_per_m3 = pre / smelt_yield
				final_def.finish_value = {&"refined": fin / pre}
			"gem":
				raw_def.finish_value = {&"polished": pre / raw}
				final_def.finish_value = {&"polished": CARRIED_FINISH}
				final_def.value_per_m3 = fin / (cut_yield * CARRIED_FINISH)
			_:
				load_errors.append("material '%s' has no path" % id)

## The material an item belongs to, or {}.
func material_for(item_id: StringName) -> Dictionary:
	return materials.get(material_of.get(item_id, &""), {})

## The stage names along a path, for the price guide.
static func stage_names(path: String) -> Array:
	match path:
		"wood":
			return ["Log", "Sanded", "Plank"]
		"metal":
			return ["Ore", "Smelted", "Refined"]
		"gem":
			return ["Rough", "Polished", "Cut"]
	return ["Raw", "Pre", "Final"]

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
	for quest in quest_pool():
		var q_item := StringName(quest.get("item", ""))
		var q_cat := StringName(quest.get("category", ""))
		if q_item != &"" and not items.has(q_item):
			load_errors.append("quest '%s' wants unknown item '%s'" % [quest.get("id", "?"), q_item])
		if q_item == &"" and not categories.has(q_cat):
			load_errors.append("quest '%s' wants unknown category '%s'" % [quest.get("id", "?"), q_cat])
	for entry in store_products():
		var box := StringName(entry.get("box", ""))
		var target := StringName(entry.get("target", ""))
		if not items.has(box):
			load_errors.append("store sells unknown box '%s'" % box)
		match String(entry.get("kind", "")):
			"tool":
				if not tools.has(target):
					load_errors.append("store box '%s' holds unknown tool '%s'" % [box, target])
			"upgrade":
				if not upgrade_tracks.has(target):
					load_errors.append("store box '%s' upgrades unknown track '%s'" % [box, target])
			"tier":
				if not upgrade_tracks.has(target) or not buildings.has(target):
					load_errors.append("store box '%s' tiers unknown machine '%s'" % [box, target])
			_:
				if not buildings.has(target):
					load_errors.append("store box '%s' unlocks unknown building '%s'" % [box, target])
	for b: BuildingDef in buildings.values():
		if (b.kind == &"machine" or b.kind == &"inline") and not machines.has(b.machine):
			load_errors.append("building '%s' references unknown machine '%s'" % [b.id, b.machine])
		if b.kind == &"pad" and not vehicles.has(b.vehicle):
			load_errors.append("pad '%s' spawns unknown vehicle '%s'" % [b.id, b.vehicle])
	for e in load_errors:
		push_error("GameData: %s" % e)

# --- Lookups ---------------------------------------------------------------

func item(id: StringName) -> ItemDef:
	return items.get(id)

func item_name(id: StringName) -> String:
	var def: ItemDef = items.get(id)
	return def.display_name if def != null else String(id)

func tool(id: StringName) -> Dictionary:
	return tools.get(id, {})

func tool_name(id: StringName) -> String:
	return String(tool(id).get("display_name", id))

func vehicle(id: StringName) -> Dictionary:
	return vehicles.get(id, {})

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
	if m.mode == MachineDef.MODE_ASSEMBLE or m.mode == MachineDef.MODE_SAND \
			or m.mode == MachineDef.MODE_CRUSH or m.mode == MachineDef.MODE_REFINE:
		return true
	return m.output_for(item_id) != &""

# --- Stores ------------------------------------------------------------------

func stores() -> Array:
	return store_config.get("stores", [])

var _sold: Dictionary = {}

## Whether the store sells copies of this building at this tier: an unlock
## box is a tier 1 copy, a tier box that tier. Those are built from what you
## have bought; everything else is built for its price.
func sold_copy(id: StringName, tier: int = 1) -> bool:
	if _sold.is_empty():
		for store in store_config.get("stores", []):
			for section in store.get("sections", []):
				for p in section.get("products", []):
					match String(p.get("kind", "")):
						"unlock":
							_sold["%s:1" % p.target] = true
						"tier":
							_sold["%s:%d" % [p.target, int(p.get("tier", 1))]] = true
		_sold["-"] = false
	return _sold.has("%s:%d" % [id, tier])

func store_def(id: StringName) -> Dictionary:
	for st in stores():
		if StringName(st.get("id", "")) == id:
			return st
	return {}

## Every product on every shelf (or one store's), each a copy of its row with
## where it sits filled in: store, section, colours and box id.
func store_products(store_id: StringName = &"") -> Array:
	var out: Array = []
	for st in stores():
		if store_id != &"" and StringName(st.get("id", "")) != store_id:
			continue
		for section in st.get("sections", []):
			for entry in section.get("products", []):
				var p: Dictionary = (entry as Dictionary).duplicate()
				p["store"] = StringName(st.get("id", ""))
				p["section"] = String(section.get("title", ""))
				p["color"] = section.get("color", [0.5, 0.5, 0.5])
				p["box_size"] = section.get("box", [0.9, 0.7, 0.7])
				p["box"] = box_id(p)
				# Machine tiers wear their tier's colour, the way the cartons do.
				if p.has("tier"):
					p["color"] = TIER_COLORS[clampi(int(p.tier), 1, 3) - 1]
				out.append(p)
	return out

const TIER_COLORS := [[0.92, 0.45, 0.15], [0.52, 0.56, 0.64], [0.20, 0.36, 0.82]]

static func box_id(p: Dictionary) -> StringName:
	var id := "box_%s" % String(p.get("target", ""))
	if p.has("tier"):
		id += "_t%d" % int(p.tier)
	elif String(p.get("kind", "")) == "upgrade":
		id += "_up"
	return StringName(id)

## What a product is called on its box.
func product_name(p: Dictionary) -> String:
	var target := StringName(p.get("target", ""))
	match String(p.get("kind", "")):
		"tool":
			return tool_name(target)
		"upgrade":
			var t: Dictionary = upgrade_tracks.get(target, {})
			return "%s Upgrade" % String(t.get("display_name", target))
		"tier":
			var b := building(target)
			return "%s T%d" % [b.display_name if b != null else String(target), int(p.get("tier", 1))]
	var def := building(target)
	return def.display_name if def != null else String(target)

## The boxes are items like any other, made from the store table rather than
## listed by hand, so adding a product is one line of data.
func _make_boxes() -> void:
	for p in store_products():
		var c: Array = p.color
		var size: Array = p.box_size
		var def := ItemDef.from_dict({"id": String(p.box), "display_name": "Boxed %s" % product_name(p),
			"category": "package", "shape": "box", "variable": false, "size": size,
			"density": 60, "value_per_m3": 0, "sellable": false, "must_buy": true, "color": c})
		items[def.id] = def

func quest_pool() -> Array:
	return quest_config.get("quests", [])

func quest_slots() -> int:
	return int(quest_config.get("active_slots", 3))

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
