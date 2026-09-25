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
		[["1", "/", "9"], "Take a tool from the hotbar (again to put it away)"],
		[["Wheel"], "Step through the hotbar"],
		[["LMB"], "Empty hand: hold to drag by the point you grab"],
		[["LMB"], "Axe: chop and buck. Hammer: crack rock"],
		[["Wheel"], "While dragging: pull it closer or push it away"],
		[["RMB"], "Pick up onto your carry rack (while dragging: throw)"],
		[["I"], "Inventory: put tools on the hotbar"],
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
		[["F"], "Select the building you aim at to edit it (again: done)"],
		[["1", "/", "3"], "While editing: move, scale or rotate handles"],
		[["LMB"], "While editing: drag a handle"],
		[["RMB"], "While editing: hold to look around"],
		[["Del"], "While editing: remove it"],
		[["Esc"], "Leave build mode"],
	]},
	{"title": "Vehicles", "rows": [
		[["E"], "Aim at the driver's seat or cab to get in"],
		[["V"], "Get out"],
		[["W", "S"], "Throttle and reverse"],
		[["A", "D"], "Steer"],
		[["Space"], "Brake"],
		[["X"], "Drop the tailgate and tip the load out"],
		[["Z"], "Drop one piece off the back"],
		[["C"], "Recover (set it back on its wheels)"],
		[["Y"], "Winch: hook on what you aim at, or unhook (seated or standing by it)"],
		[["K", "/", "L"], "Winch: reel in / let out"],
		[["O"], "Outriggers out or in: locks the truck where it stands (seated or standing by it)"],
		[["Q"], "Crane: work it (outriggers down) or stow it"],
		[["A", "D"], "Crane: swing the boom"],
		[["W", "S"], "Crane: boom up / down"],
		[["R", "/", "T"], "Crane: boom out / in"],
		[["Shift", "/", "Ctrl"], "Crane: hoist up / down"],
		[["F"], "Crane: latch the hook on, or let go"],
	]},
	{"title": "Game", "rows": [
		[["Esc"], "Pause menu"],
		[["Tab"], "Journal: orders, map, market, upgrades"],
		[["I"], "Inventory and hotbar"],
		[["M"], "Map"],
		[["P"], "Market prices"],
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
			return [[["LMB"], "Place"], [["RMB"], "Remove"], [["F"], "Edit what you aim at"],
				[["Wheel"], "Choose"], [["Z", "X", "C"], "Rotate"], [["Shift", "/", "Ctrl"], "Up / down"], [["B"], "Done"]]
		"drive":
			return [[["W", "S"], "Drive"], [["Space"], "Brake"], [["X"], "Unload"],
				[["Y"], "Winch"], [["K", "/", "L"], "Reel"], [["Q"], "Crane"], [["V"], "Get out"]]
		"crane":
			return [[["A", "D"], "Swing"], [["W", "S"], "Boom up / down"], [["R", "/", "T"], "Boom out / in"],
				[["Shift", "/", "Ctrl"], "Hoist"], [["F"], "Latch / let go"], [["Q"], "Stow"]]
		"dragging":
			return [[["LMB"], "Hold to keep hold"], [["Wheel"], "Closer / further"], [["RMB"], "Throw"]]
		"carrying":
			return [[["E"], "Deposit / sell"], [["Q"], "Drop one"], [["G"], "Drop all"],
				[["RMB"], "Pick up more"], [["B"], "Build"]]
	return [[["1", "/", "9"], "Tools"], [["LMB"], "Drag / use tool"], [["RMB"], "Pick up"],
		[["E"], "Use"], [["I"], "Inventory"], [["B"], "Build"], [["Tab"], "Journal"]]
