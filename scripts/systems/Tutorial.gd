class_name Tutorial
extends Node

## A getting-started checklist that watches what the player actually does.
##
## Steps complete from events (a tree came down) or from state (there is a
## building on the plot), and finishing a later step finishes every one before
## it - so a loaded game that already has a sawmill is not asked to chop its
## first tree, and a player who finds their own way is never told off for it.

signal step_completed(step: Dictionary)
signal advanced

const STEPS := [
	{"id": &"chop", "title": "Fell a tree",
		"hint": "Take your axe with [1], aim at a trunk and swing [LMB] until it comes down. The Home Woods on the compass are close by."},
	{"id": &"pick", "title": "Pick up the wood",
		"hint": "[RMB] puts a piece on your rack. Too long? Buck it with the axe, or put the axe away [1] and drag it with [LMB]."},
	{"id": &"sell", "title": "Sell it at the Sell Yard",
		"hint": "Follow the compass to the yard, drop the wood inside the fence [G] and ask the shopkeep [E]."},
	{"id": &"store", "title": "Visit the Store",
		"hint": "Machines, belts and upgrades come in boxes. Carry one to the till and press [E]."},
	{"id": &"build", "title": "Open build mode",
		"hint": "On your plot, press [B]. Fly with [WASD], open the build menu with [E] and pick a building."},
	{"id": &"place", "title": "Place a building",
		"hint": "A Planker turns a sanded log into one big plank, which sells for more - sand logs first. [LMB] places it."},
	{"id": &"order", "title": "Fill an order",
		"hint": "Orders pay a bonus on top of the sale. See them any time with [Tab]."},
]

const POLL := 0.25

## The steps this world has: all of them, bar any `skip` takes out (Ostars has
## no yard, store or orders to send you to).
var steps: Array = STEPS

func skip(ids: Array) -> void:
	steps = STEPS.filter(func(step: Dictionary) -> bool: return not ids.has(step.id))

var player: Player
var plot: Plot
var store: Node3D
var build_system: BuildSystem
var _flags: Dictionary = {}
var _poll: float = 0.0

func setup(p_player: Player, p_plot: Plot, p_store: Node3D, p_build: BuildSystem,
		quests: QuestLog, tree_fields: Array) -> void:
	player = p_player
	plot = p_plot
	store = p_store
	build_system = p_build
	if quests != null:
		quests.completed.connect(func(_q: Dictionary, _r: int): note(&"order"))
	if build_system != null:
		build_system.mode_changed.connect(func(on: bool): if on: note(&"build"))
	Economy.item_sold.connect(func(_id: StringName, _v: int): note(&"sell"))
	for field in tree_fields:
		for node in field.alive:
			_watch_tree(node)
		field.populated.connect(func(_f, node: Node3D): _watch_tree(node))

func _watch_tree(node: Node3D) -> void:
	var tree := node as ChoppableTree
	if tree != null and not tree.felled.is_connected(_on_felled):
		tree.felled.connect(_on_felled)

func _on_felled(_tree: ChoppableTree) -> void:
	note(&"chop")

## Something happened that finishes a step.
func note(id: StringName) -> void:
	_flags[id] = true
	evaluate()

func done(id: StringName) -> bool:
	return PlayerState.tutorial_done.has(id)

func finished() -> bool:
	return current_index() < 0

## The first step not yet done, or -1 when the list is finished.
func current_index() -> int:
	for i in steps.size():
		if not done(steps[i].id):
			return i
	return -1

func current() -> Dictionary:
	var i := current_index()
	return {} if i < 0 else steps[i]

func done_count() -> int:
	var n := 0
	for step in steps:
		if done(step.id):
			n += 1
	return n

func _met(id: StringName) -> bool:
	if _flags.get(id, false):
		return true
	match id:
		&"pick":
			return player != null and (player.carried_count() > 0 or player.dragged != null)
		&"sell":
			return Economy.items_sold > 0
		&"store":
			return player != null and store != null and \
				player.global_position.distance_to(store.global_position) < 14.0
		&"build":
			return build_system != null and build_system.active
		&"place":
			return plot != null and not plot.placed.is_empty()
	return false

## Marks every step up to the furthest one that is met.
func evaluate() -> void:
	var furthest := -1
	for i in steps.size():
		if _met(steps[i].id):
			furthest = i
	if furthest < 0:
		return
	var changed := false
	for i in furthest + 1:
		var step: Dictionary = steps[i]
		if not done(step.id):
			PlayerState.tutorial_done.append(step.id)
			step_completed.emit(step)
			changed = true
	if changed:
		advanced.emit()

func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0 or finished():
		return
	_poll = POLL
	evaluate()
