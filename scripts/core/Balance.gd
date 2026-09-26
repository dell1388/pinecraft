class_name Balance
extends RefCounted

## The game's balance knobs, read from res://data/balance.json - one file to
## open when something is too slow, too strong, too cheap or too far.
##
## Each value is looked up by "section.name" with the default the code was
## tuned with, so a missing or mistyped entry falls back rather than breaking
## anything. Values are read once, when the game starts.

const PATH := "res://data/balance.json"

static var _values: Dictionary = {}
static var _loaded: bool = false

## A number from the file, or `fallback` when it is not there.
static func num(key: String, fallback: float) -> float:
	_load()
	var v: Variant = _values.get(key, null)
	if v is float or v is int:
		return float(v)
	return fallback

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_values.clear()
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary:
		push_error("Balance: %s is not valid JSON" % PATH)
		return
	for section in parsed:
		var group: Variant = parsed[section]
		if not group is Dictionary or String(section).begins_with("_"):
			continue
		for key in group:
			if not String(key).begins_with("_"):
				_values["%s.%s" % [section, key]] = group[key]

## Every value the file sets, "section.name" -> value. For checks and tools.
static func all() -> Dictionary:
	_load()
	return _values.duplicate()
