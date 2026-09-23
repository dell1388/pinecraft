class_name KeyGuide
extends RefCounted

## Every binding in the game, grouped the way the player meets them. The
## controls screen, the journal and the context hints all read from here, so a
## key only has to be described once.

const GROUPS := [
	{"title": "On foot", "rows": [
		[["W", "A", "S", "D"], "Move"],
		[["Shift"], "Sprint"],
		[["Space"], "Jump"],
		[["LMB"], "Chop, mine, hammer or buck what you aim at"],
		[["RMB"], "Pick up onto your carry rack"],
		[["F"], "Heavy-drag one piece (again to let go, LMB to throw)"],
		[["Q"], "Drop one piece from the rack"],
		[["G"], "Drop everything on the rack"],
		[["E"], "Use: deposit, sell, pay, load, talk"],
		[["Shift", "E"], "Empty a storage bin onto the ground"],
	]},
	{"title": "Build mode", "rows": [
		[["B"], "Enter or leave build mode"],
		[["W", "A", "S", "D"], "Fly the camera"],
		[["Shift"], "Up / faster"],
		[["Ctrl"], "Down"],
		[["LMB"], "Place the selected building"],
		[["RMB"], "Remove the building you aim at"],
		[["Wheel"], "Next / previous building"],
		[["1", "/", "7"], "Pick from the build bar"],
		[["Z", "X", "C"], "Rotate around each axis"],
		[["Esc"], "Leave build mode"],
	]},
	{"title": "Hauler", "rows": [
		[["V"], "Get in or out"],
		[["W", "S"], "Throttle and reverse"],
		[["A", "D"], "Steer"],
		[["Space"], "Brake"],
		[["X"], "Unload the whole bed"],
		[["Z"], "Drop one piece off the back"],
		[["C"], "Recover (set it back on its wheels)"],
		[["E"], "Hook or unhook the winch"],
		[["G"], "Reel the winch in"],
		[["F"], "Crane: grab or release"],
		[["R", "/", "T"], "Crane: turn the load"],
	]},
	{"title": "Game", "rows": [
		[["Esc"], "Pause menu"],
		[["Tab"], "Journal: orders, market, upgrades"],
		[["M"], "Market prices"],
		[["U"], "Upgrades and land"],
		[["F1"], "This list"],
		[["H"], "Show or hide key hints"],
		[["F5"], "Quick save"],
		[["F9"], "Quick load"],
		[["F3"], "Debug readout"],
	]},
]

## The whole reference as a two-column sheet.
static func sheet() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 34)
	grid.add_theme_constant_override("v_separation", 18)
	for group in GROUPS:
		var col := UIKit.vbox(6)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		col.add_child(UIKit.label(String(group.title).to_upper(), "Subheader"))
		for row in group.rows:
			col.add_child(UIKit.binding_row(row[0], row[1]))
		grid.add_child(col)
	return grid

## The handful of keys that matter right now, for the corner of the screen.
## `state` is "foot", "carrying", "dragging", "build", "drive" or "crane".
static func hints_for(state: String) -> Array:
	match state:
		"build":
			return [[["LMB"], "Place"], [["RMB"], "Remove"], [["Wheel"], "Choose"],
				[["Z", "X", "C"], "Rotate"], [["Shift", "/", "Ctrl"], "Up / down"], [["B"], "Done"]]
		"drive":
			return [[["W", "S"], "Drive"], [["Space"], "Brake"], [["X"], "Unload"],
				[["E"], "Winch"], [["F"], "Crane"], [["C"], "Recover"], [["V"], "Get out"]]
		"crane":
			return [[["W", "A", "S", "D"], "Move load"], [["Shift", "/", "Ctrl"], "Raise / lower"],
				[["R", "/", "T"], "Turn"], [["F"], "Release"]]
		"dragging":
			return [[["F"], "Let go"], [["LMB"], "Throw"], [["E"], "Deposit"]]
		"carrying":
			return [[["E"], "Deposit / sell"], [["Q"], "Drop one"], [["G"], "Drop all"],
				[["RMB"], "Pick up more"], [["B"], "Build"]]
	return [[["LMB"], "Chop / mine"], [["RMB"], "Pick up"], [["F"], "Drag"],
		[["E"], "Use"], [["B"], "Build"], [["Tab"], "Journal"]]
