extends Node

## Autoload. Everything the player owns that is not money: tool levels, the
## buildings they have unlocked and whether the hauler has been bought.

signal upgraded(track: StringName, level: int)
signal unlocked(building_id: StringName)
signal vehicle_purchased()

const VEHICLE_PAD := &"vehicle_pad"

var levels: Dictionary = {}              ## StringName -> int
var unlocked_buildings: Array[StringName] = []

func _ready() -> void:
	reset()

func reset() -> void:
	levels.clear()
	for track_id in GameData.upgrade_tracks:
		levels[track_id] = 1
	unlocked_buildings.clear()
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

func to_dict() -> Dictionary:
	var lv := {}
	for k in levels:
		lv[String(k)] = int(levels[k])
	var ub: Array = []
	for b in unlocked_buildings:
		ub.append(String(b))
	return {"levels": lv, "unlocked": ub}

func from_dict(d: Dictionary) -> void:
	reset()
	for k in d.get("levels", {}):
		levels[StringName(k)] = int(d["levels"][k])
	var ub: Array = d.get("unlocked", [])
	if not ub.is_empty():
		unlocked_buildings.clear()
		for b in ub:
			unlocked_buildings.append(StringName(b))
	# Older saves recorded the truck as a flag rather than as an unlocked pad.
	if bool(d.get("owns_vehicle", false)) and not is_unlocked(VEHICLE_PAD):
		unlocked_buildings.append(VEHICLE_PAD)
