class_name SaveSystem
extends RefCounted

## Plot + progress persistence, as a single human-readable JSON document.

const SAVE_PATH := "user://pinecraft_save.json"
const VERSION := 1

static func save_game(plot: Plot, player: Node3D = null, path: String = SAVE_PATH) -> bool:
	var doc := {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"economy": Economy.to_dict(),
		"player_state": PlayerState.to_dict(),
		"plot": plot.to_dict(),
	}
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

static func load_game(plot: Plot, player: Node3D = null, path: String = SAVE_PATH) -> bool:
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
	if player != null and doc.has("player_position"):
		var p: Array = doc["player_position"]
		player.global_position = Vector3(p[0], p[1], p[2])
		player.rotation.y = float(doc.get("player_yaw", 0.0))
	return true

static func delete_save(path: String = SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
