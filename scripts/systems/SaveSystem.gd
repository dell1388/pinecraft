class_name SaveSystem
extends RefCounted

## Plot + progress persistence, as a single human-readable JSON document per
## save slot. There are several slots (user://saves/slot_1.json and on): the
## game plays in one at a time, saves and autosaves go to it, and the menus
## can load, save into, start a new game in, or clear any of them.

## The one save of the days before slots. Read as slot 1 if slot 1 is empty.
const SAVE_PATH := "user://pinecraft_save.json"
const SAVE_DIR := "user://saves"
const SLOTS := 6
const VERSION := 2

## The slot being played.
static var slot: int = 1
## Set once a slot has been picked this run (by the menus, or the newest save
## at start-up), so a scene reload keeps it.
static var slot_chosen: bool = false

static func slot_path(n: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, n]

static func current_path() -> String:
	_migrate()
	return slot_path(slot)

## Moves the old single save into slot 1, once, if there is nothing there.
static var _migrated: bool = false
static func _migrate() -> void:
	if _migrated:
		return
	_migrated = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	if FileAccess.file_exists(SAVE_PATH) and not FileAccess.file_exists(slot_path(1)):
		# Moved, not copied, so a slot 1 cleared later stays cleared.
		DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(slot_path(1)))

## The slot with the newest save in it, or 1 when there are none.
static func newest_slot() -> int:
	_migrate()
	var best := 1
	var best_time := -1
	for n in range(1, SLOTS + 1):
		var p := slot_path(n)
		if FileAccess.file_exists(p):
			var t := FileAccess.get_modified_time(p)
			if t > best_time:
				best_time = t
				best = n
	return best

## Picks the slot to play at start-up: the newest save, unless one was chosen.
static func choose_start_slot() -> void:
	if slot_chosen:
		return
	slot = newest_slot()
	slot_chosen = true

## Every slot and what is in it: [{slot, info}] (info empty for an empty slot).
static func slots() -> Array:
	_migrate()
	var out: Array = []
	for n in range(1, SLOTS + 1):
		out.append({"slot": n, "info": summary(slot_path(n))})
	return out

static func any_save() -> bool:
	for s in slots():
		if not (s.info as Dictionary).is_empty():
			return true
	return false

## Loose material is only worth remembering when the player owns it and it is
## on their land: a trunk they felled and left in the forest is part of the
## world, and the world regenerates.
static func save_game(plot: Plot, player: Node3D = null, path: String = "",
		manager: LooseItemManager = null, vehicle: Node3D = null,
		quests: QuestLog = null) -> bool:
	if path == "":
		path = current_path()
	var doc := {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		# Which map the game is on; a save without one is on the islands.
		"map": String(WorldMap.current),
		"economy": Economy.to_dict(),
		"player_state": PlayerState.to_dict(),
		"plot": plot.to_dict(),
	}
	if manager != null:
		doc["loose"] = _loose_to_array(manager, plot)
	if quests != null:
		doc["quests"] = quests.to_dict()
	if vehicle != null and vehicle.has_method("to_dict"):
		doc["vehicle"] = vehicle.call("to_dict")
	if player != null:
		var p := player.global_position
		# Seated, the body is inside the cab: saved there, it would come back
		# standing inside the truck and shove it down through the ground. It
		# is saved by the driver's door instead.
		var seat: Variant = player.get("vehicle")
		if seat is Node3D and is_instance_valid(seat):
			var truck := seat as Node3D
			var size: Variant = truck.get("body_size")
			var out := (size as Vector3).x * 0.5 + 1.3 if size is Vector3 else 2.5
			p = truck.global_position + truck.global_transform.basis.x * out + Vector3(0, 1.0, 0)
		doc["player_position"] = [p.x, p.y, p.z]
		doc["player_yaw"] = player.rotation.y
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: cannot write %s (%d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(doc, "  "))
	file.close()
	return true

static func has_save(path: String = "") -> bool:
	return FileAccess.file_exists(path if path != "" else current_path())

## `vehicle_spawner` is called only when the save says a vehicle was owned. The
## truck has to exist before its cargo and pose can be restored, but whether it
## exists at all is itself part of the save, so the world hands us the means to
## make one rather than making one up front.
static func load_game(plot: Plot, player: Node3D = null, path: String = "",
		manager: LooseItemManager = null, vehicle_spawner: Callable = Callable(),
		quests: QuestLog = null) -> bool:
	if path == "":
		path = current_path()
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveSystem: malformed save at %s" % path)
		return false
	var doc: Dictionary = parsed
	if int(doc.get("version", 0)) > VERSION:
		push_warning("SaveSystem: save is from a newer version; loading anyway")
	PlayerState.from_dict(doc.get("player_state", {}))
	Economy.from_dict(doc.get("economy", {}))
	if manager != null:
		# Clear exactly what a save would have written before writing it back,
		# or loading twice doubles the stockpile. That includes whatever is in
		# a truck bed, wherever the truck is: it is saved with the truck.
		# Done before the plot, whose pads bring the truck and its load back.
		var reach: float = plot.half_extent * 1.4142
		for stale in manager.owned_items():
			if stale.carrier != null or stale.global_position.distance_to(plot.global_position) <= reach:
				manager.despawn(stale)
	plot.from_dict(doc.get("plot", {}))
	if manager != null:
		_loose_from_array(manager, doc.get("loose", []), plot.plot_id)
	if quests != null:
		quests.from_dict(doc.get("quests", {}))
	# Pads restore their own trucks as part of the plot, so a save only needs
	# the spawner for a game that predates pads.
	if PlayerState.owns_vehicle() and vehicle_spawner.is_valid() and doc.has("vehicle"):
		var vehicle: Object = vehicle_spawner.call()
		if vehicle != null and vehicle.has_method("from_dict"):
			vehicle.call("from_dict", doc["vehicle"])
	if player != null and doc.has("player_position"):
		var p: Array = doc["player_position"]
		player.global_position = Vector3(p[0], p[1], p[2])
		player.rotation.y = float(doc.get("player_yaw", 0.0))
	return true

## Owned pieces standing on the plot, with their real size and pose, so a base
## reloads with its stockpile exactly where it was left.
static func _loose_to_array(manager: LooseItemManager, plot: Plot) -> Array:
	var out: Array = []
	var centre := plot.global_position
	var reach: float = plot.half_extent * 1.4142
	for item in manager.owned_items(centre, reach):
		if item.carrier != null and is_instance_valid(item.carrier):
			continue      # saved with the truck it is riding in
		var t := item.global_transform
		out.append({
			"id": String(item.item_id),
			"dims": Solid.to_dict(item.dims),
			"limbs": item.limbs_to_array(),
			"position": [t.origin.x, t.origin.y, t.origin.z],
			"basis": [t.basis.x.x, t.basis.x.y, t.basis.x.z,
				t.basis.y.x, t.basis.y.y, t.basis.y.z,
				t.basis.z.x, t.basis.z.y, t.basis.z.z],
		})
	return out

static func _loose_from_array(manager: LooseItemManager, entries: Array, plot_id: int) -> void:
	for entry in entries:
		var pos: Array = entry.get("position", [0, 2, 0])
		var b: Array = entry.get("basis", [])
		var basis := Basis()
		if b.size() == 9:
			basis = Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]),
				Vector3(b[6], b[7], b[8]))
		var item := manager.spawn(StringName(entry.get("id", "")),
			Transform3D(basis, Vector3(pos[0], pos[1], pos[2])), plot_id,
			Vector3.ZERO, Solid.from_dict(entry.get("dims", {})), true)
		if item != null:
			for l in entry.get("limbs", []):
				var a: Array = l
				if a.size() >= 8:
					item.add_limb(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), float(a[6]), float(a[7]),
						[], Color(0.42, 0.3, 0.2), float(a[8]) if a.size() > 8 else -1.0)

## What the main menu shows under Continue, read without loading anything.
static func summary(path: String = "") -> Dictionary:
	if path == "":
		path = current_path()
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var doc: Dictionary = parsed
	var economy: Dictionary = doc.get("economy", {})
	var plot: Dictionary = doc.get("plot", {})
	return {
		"day": int(economy.get("day", 1)),
		"money": int(economy.get("money", 0)),
		"buildings": (plot.get("buildings", []) as Array).size(),
		"saved_at": String(doc.get("saved_at", "")),
		"map": WorldMap.valid(doc.get("map", WorldMap.ISLES)),
	}

static func delete_save(path: String = "") -> void:
	if path == "":
		path = current_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
