extends Node

## Autoload. Everything the player owns that is not money: tool levels, the
## buildings they have unlocked and whether the hauler has been bought.

signal upgraded(track: StringName, level: int)
signal unlocked(building_id: StringName)
signal vehicle_purchased()
signal inventory_changed()

const VEHICLE_PAD := &"vehicle_pad"

var levels: Dictionary = {}              ## StringName -> int
var unlocked_buildings: Array[StringName] = []
## Getting-started steps already done, so a loaded game does not teach you to
## chop a tree again.
var tutorial_done: Array[StringName] = []
## Places the player has been to, by name, so the map and compass can name them.
var discovered: Array[String] = []
## Supply caches opened: name -> the market day it was last opened.
var caches: Dictionary = {}
## Tools owned, in the order they were got, and what is on each hotbar slot
## (a tool id, or &"" for an empty slot).
var tools: Array[StringName] = []
var hotbar: Array[StringName] = []
const HOTBAR_SLOTS := 9

func _ready() -> void:
	reset()

func reset() -> void:
	levels.clear()
	for track_id in GameData.upgrade_tracks:
		levels[track_id] = 1
	unlocked_buildings.clear()
	tutorial_done.clear()
	discovered.clear()
	caches.clear()
	tools.clear()
	hotbar.clear()
	hotbar.resize(HOTBAR_SLOTS)
	hotbar.fill(&"")
	for id in GameData.start_tools:
		give_tool(id, false)
	for def: BuildingDef in GameData.buildings.values():
		if def.unlock_cost <= 0:
			unlocked_buildings.append(def.id)

func level(track: StringName) -> int:
	return int(levels.get(track, 1))

func stats(track: StringName) -> Dictionary:
	return GameData.upgrade_level(track, level(track))

func stat(track: StringName, key: String, fallback: float = 0.0) -> float:
	var d := stats(track)
	return float(d.get(key, fallback))

## A value stored on the track itself rather than on one of its levels.
func track_value(track: StringName, key: String, fallback: float = 0.0) -> float:
	var t: Dictionary = GameData.upgrade_tracks.get(track, {})
	return float(t.get(key, fallback))

func label(track: StringName) -> String:
	return String(stats(track).get("label", String(track)))

func at_max(track: StringName) -> bool:
	return level(track) >= GameData.max_upgrade_level(track)

## Cost of the next level, or -1 when the track is maxed.
func next_cost(track: StringName) -> int:
	if at_max(track):
		return -1
	return int(GameData.upgrade_level(track, level(track) + 1).get("cost", 0))

func try_upgrade(track: StringName) -> bool:
	var cost := next_cost(track)
	if cost < 0 or not Economy.try_spend(cost):
		return false
	levels[track] = level(track) + 1
	upgraded.emit(track, level(track))
	return true

# --- Building unlocks ------------------------------------------------------

func is_unlocked(building_id: StringName) -> bool:
	return unlocked_buildings.has(building_id)

func try_unlock(building_id: StringName) -> bool:
	var def := GameData.building(building_id)
	if def == null or is_unlocked(building_id):
		return false
	if not Economy.try_spend(def.unlock_cost):
		return false
	unlocked_buildings.append(building_id)
	unlocked.emit(building_id)
	return true

func available_buildings() -> Array[BuildingDef]:
	var out: Array[BuildingDef] = []
	for def: BuildingDef in GameData.buildings.values():
		if is_unlocked(def.id):
			out.append(def)
	out.sort_custom(func(a, b): return a.cost < b.cost)
	return out

## A hauler is bought by unlocking its pad; the pad is then placed like any
## other building and the truck appears on it.
func owns_vehicle() -> bool:
	return is_unlocked(VEHICLE_PAD)

func vehicle_cost() -> int:
	var def := GameData.building(VEHICLE_PAD)
	return def.unlock_cost if def != null else 5000

func try_buy_vehicle() -> bool:
	if not try_unlock(VEHICLE_PAD):
		return false
	vehicle_purchased.emit()
	return true

# --- Tools and the hotbar --------------------------------------------------

func owns_tool(id: StringName) -> bool:
	return tools.has(id)

## Adds a tool to the inventory and, if there is room, the hotbar.
func give_tool(id: StringName, announce: bool = true) -> bool:
	if GameData.tool(id).is_empty() or tools.has(id):
		return false
	tools.append(id)
	var free := hotbar.find(&"")
	if free >= 0:
		hotbar[free] = id
	if announce:
		inventory_changed.emit()
	return true

## Puts a tool on a hotbar slot. A tool is on the bar at most once, so it
## moves if it was already somewhere else; `id` &"" clears the slot.
func set_hotbar(slot: int, id: StringName) -> void:
	if slot < 0 or slot >= HOTBAR_SLOTS:
		return
	if id != &"" and not tools.has(id):
		return
	var was := hotbar.find(id) if id != &"" else -1
	if was >= 0:
		hotbar[was] = hotbar[slot]
	hotbar[slot] = id
	inventory_changed.emit()

func hotbar_tool(slot: int) -> StringName:
	if slot < 0 or slot >= hotbar.size():
		return &""
	return hotbar[slot]

## The best tool of a kind you own (for things that do not care which).
func best_tool(kind: String) -> StringName:
	var best := &""
	var best_cost := -1
	for id in tools:
		var t := GameData.tool(id)
		if String(t.get("kind", "")) == kind and int(t.get("cost", 0)) > best_cost:
			best = id
			best_cost = int(t.get("cost", 0))
	return best

func to_dict() -> Dictionary:
	var lv := {}
	for k in levels:
		lv[String(k)] = int(levels[k])
	var ub: Array = []
	for b in unlocked_buildings:
		ub.append(String(b))
	var tut: Array = []
	for step in tutorial_done:
		tut.append(String(step))
	return {"levels": lv, "unlocked": ub, "tutorial": tut,
		"discovered": discovered.duplicate(), "caches": caches.duplicate(),
		"tools": tools.map(func(t): return String(t)),
		"hotbar": hotbar.map(func(t): return String(t))}

func from_dict(d: Dictionary) -> void:
	reset()
	for k in d.get("levels", {}):
		levels[StringName(k)] = int(d["levels"][k])
	var ub: Array = d.get("unlocked", [])
	if not ub.is_empty():
		unlocked_buildings.clear()
		for b in ub:
			unlocked_buildings.append(StringName(b))
	for step in d.get("tutorial", []):
		tutorial_done.append(StringName(step))
	for place in d.get("discovered", []):
		discovered.append(String(place))
	if d.has("tools"):
		tools.clear()
		for id in d["tools"]:
			if not GameData.tool(StringName(id)).is_empty():
				tools.append(StringName(id))
		var bar: Array = d.get("hotbar", [])
		for i in HOTBAR_SLOTS:
			var id := StringName(bar[i]) if i < bar.size() else &""
			hotbar[i] = id if tools.has(id) else &""
	# Saves from before tools were things: the old axe and hammer levels
	# become the matching tools.
	var old_levels: Dictionary = d.get("levels", {})
	for pair in [["axe", ["rusty_axe", "steel_axe", "timber_axe", "ironwood_cleaver", "goldleaf_axe"]],
			["hammer", ["club_hammer", "sledge", "splitting_maul", "drop_hammer"]]]:
		var lv := int(old_levels.get(pair[0], 0))
		for i in mini(lv, (pair[1] as Array).size()):
			give_tool(StringName(pair[1][i]), false)
	var opened: Dictionary = d.get("caches", {})
	for key in opened:
		caches[String(key)] = int(opened[key])
	# Older saves recorded the truck as a flag rather than as an unlocked pad.
	if bool(d.get("owns_vehicle", false)) and not is_unlocked(VEHICLE_PAD):
		unlocked_buildings.append(VEHICLE_PAD)
