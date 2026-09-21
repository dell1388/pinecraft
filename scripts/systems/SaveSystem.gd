class_name SaveSystem
extends RefCounted

## Plot + progress persistence, as a single human-readable JSON document.

const SAVE_PATH := "user://pinecraft_save.json"
const VERSION := 2

## Loose material is only worth remembering when the player owns it and it is
## on their land: a trunk they felled and left in the forest is part of the
## world, and the world regenerates.
static func save_game(plot: Plot, player: Node3D = null, path: String = SAVE_PATH,
		manager: LooseItemManager = null, vehicle: Node3D = null,
		quests: QuestLog = null) -> bool:
	var doc := {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
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
		doc["player_position"] = [p.x, p.y, p.z]
		doc["player_yaw"] = player.rotation.y
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: cannot write %s (%d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(doc, "  "))
	file.close()
	return true

static func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)

## `vehicle_spawner` is called only when the save says a vehicle was owned. The
## truck has to exist before its cargo and pose can be restored, but whether it
## exists at all is itself part of the save, so the world hands us the means to
## make one rather than making one up front.
static func load_game(plot: Plot, player: Node3D = null, path: String = SAVE_PATH,
		manager: LooseItemManager = null, vehicle_spawner: Callable = Callable(),
		quests: QuestLog = null) -> bool:
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
	plot.from_dict(doc.get("plot", {}))
	if manager != null:
		# Clear exactly what a save would have written before writing it back,
		# or loading twice doubles the stockpile.
		for stale in manager.owned_items(plot.global_position, plot.half_extent * 1.4142):
			manager.despawn(stale)
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
		var t := item.global_transform
		out.append({
			"id": String(item.item_id),
			"dims": Solid.to_dict(item.dims),
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
		manager.spawn(StringName(entry.get("id", "")),
			Transform3D(basis, Vector3(pos[0], pos[1], pos[2])), plot_id,
			Vector3.ZERO, Solid.from_dict(entry.get("dims", {})), true)

static func delete_save(path: String = SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
