class_name WorldMap
extends RefCounted

## Which map the world is built as. There are two:
##
##   isles    Pinecraft Isles - the home island and the five round it, with
##            the town, the sell yard, the quarry, the outposts and the roads
##   ostars   Ostars, the Known Continent - one big hand-drawn continent, no
##            buildings at all, and forests of its own (see Ostars, Forester)
##
## Each save slot remembers its map. A new game is started on whichever map
## was picked for it; a co-op guest builds whatever map the host is playing.

const ISLES := &"isles"
const OSTARS := &"ostars"
const ALL: Array[StringName] = [ISLES, OSTARS]

## The map the world is built as (read by World as it builds).
static var current: StringName = ISLES
## The map the next new game starts on (picked on the New Game page).
static var chosen: StringName = ISLES
## Set by the test and screenshot harnesses: build this map whatever the slot
## says.
static var forced: StringName = &""

static func title(id: StringName) -> String:
	match id:
		OSTARS:
			return "Ostars"
	return "Pinecraft Isles"

static func blurb(id: StringName) -> String:
	match id:
		OSTARS:
			return "The Known Continent. Frozen north, a volcano, a shattered desert, bogs and old forests. No buildings - just the land."
	return "The home island and five more: the town, the sell yard, the quarry, outposts, roads and bridges."

## A known map id, or the islands.
static func valid(id: Variant) -> StringName:
	var s := StringName(str(id)) if id != null else ISLES
	return s if ALL.has(s) else ISLES

## Picks the map to build: the saved slot's own, else the one chosen for a new
## game. A guest is told the host's (Net.host_map) instead.
static func pick_for_slot() -> void:
	if forced != &"":
		current = forced
		return
	var info := SaveSystem.summary()
	current = valid(info.get("map", ISLES)) if not info.is_empty() else chosen

static func is_ostars() -> bool:
	return current == OSTARS
