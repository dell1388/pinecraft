class_name TradePost
extends Node3D

## A trader's place, each with its own trader (see NpcFigure):
##
##   LUMBER   Old Bjorn's lumber yard: he buys wood, lumber and goods, and
##            chops at his own tree all day beside the yard
##   METAL    Dusty's assay office: he buys ore, metal, stone and glass, and
##            swings his pick at his own rock
##   GEMS     Granny Opal's: she buys gems and cut jewels from her rocking
##            chair on the porch
##
## Selling is the sell yard's (SellYard): drop it in the yard, talk to the
## trader wherever he is. The lumber yard and the assay office also sell -
## lumber and refined metal - at a shop counter (TradeCounter) beside the
## yard, and their helper carries each order out to the loading bay: into
## your truck if it is parked in the bay, onto the bay floor if not.
##
## Local frame: the yard's gate faces +Z; the work spot is off to -X, the
## shop and the bay to +X. The whole place fits in a circle of FOOTPRINT
## round (FOOTPRINT_CENTRE).

enum Kind { LUMBER, METAL, GEMS }

const FOOTPRINT := 25.0
const FOOTPRINT_CENTRE := Vector3(2.0, 0, 0)

const SPECS := {
	Kind.LUMBER: {"title": "LUMBER YARD", "keeper": "Old Bjorn", "role": NpcFigure.Role.LUMBERMAN,
		"accepts": [&"wood", &"lumber", &"goods"], "helper": "Pip", "shop": "Bjorn's Lumber",
		"hut": Color(0.46, 0.32, 0.2), "board": Color(0.18, 0.3, 0.18),
		"sells": [&"lumber_pine", &"lumber_spruce", &"lumber_birch", &"lumber_oak", &"lumber_maple",
			&"lumber_cherry", &"lumber_willow", &"lumber_redwood", &"lumber_ironwood"], "carry": 4},
	Kind.METAL: {"title": "ASSAY OFFICE", "keeper": "Dusty McGrath", "role": NpcFigure.Role.MINER,
		"accepts": [&"ore", &"metal", &"stone", &"glass"], "helper": "Nugget", "shop": "Dusty's Metals",
		"hut": Color(0.42, 0.4, 0.38), "board": Color(0.25, 0.22, 0.3),
		"sells": [&"ingot_iron", &"ingot_copper", &"ingot_tin", &"ingot_zinc", &"ingot_nickel",
			&"ingot_lodesteel", &"ingot_silver", &"ingot_cobalt", &"ingot_gold"], "carry": 6},
	Kind.GEMS: {"title": "GRANNY'S GEMS", "keeper": "Granny Opal", "role": NpcFigure.Role.GRANNY,
		"accepts": [&"gem", &"jewel"], "helper": "", "shop": "",
		"hut": Color(0.78, 0.62, 0.66), "board": Color(0.42, 0.24, 0.4), "sells": [], "carry": 0},
}

## Where things are, in the post's frame.
const WORK_SPOT := Vector3(-12.6, 0, -3.0)
const COUNTER_AT := Vector3(15.5, 0, -3.6)
const STOCK_AT := Vector3(13.2, 0, -6.6)
const BAY_CENTRE := Vector3(15.5, 0, 6.2)
const BAY_SIZE := Vector2(7.0, 11.0)
const DROP_AT := Vector3(11.3, 0, 4.2)
## How long the lumberman's tree takes to grow back.
const REGROW_SECONDS := 45.0

var kind: Kind = Kind.LUMBER
var manager: LooseItemManager
var quests: QuestLog
## Ground height at a world (x, z): the land, levelled under the post.
var ground: Callable
## Who the traders look at and talk to (the player).
var watch: Callable
## Makes the lumberman's tree: (seed) -> ChoppableTree. Unset: no tree.
var tree_builder: Callable
## Every vehicle (for finding one parked in the bay).
var vehicles: Callable

var yard: SellYard
var keeper: NpcFigure
var counter: TradeCounter
var helper: NpcFigure
var tree: ChoppableTree
var _regrow := -1.0
var _tree_seed := 1

## Items still to go out: [[item_id, count], ...], and the trip under way.
var _queue: Array = []
var _trip: Array = []
var _trip_state: StringName = &""
var _dropped := 0

func setup(p_kind: Kind, p_manager: LooseItemManager, p_quests: QuestLog = null) -> void:
	kind = p_kind
	manager = p_manager
	quests = p_quests

func spec() -> Dictionary:
	return SPECS[kind]

func title() -> String:
	return String(spec().title)

func _ready() -> void:
	name = "TradePost_%s" % Kind.keys()[kind].capitalize()
	var s := spec()
	keeper = NpcFigure.new(s.role, s.keeper)
	keeper.watch = watch
	keeper.ground = ground
	yard = SellYard.new()
	yard.name = "Yard"
	yard.setup(manager, quests)
	yard.accepts = s.accepts
	yard.keeper = s.keeper
	yard.sign_text = s.title
	yard.hut_color = s.hut
	yard.board_color = s.board
	yard.npc = keeper
	add_child(yard)
	match kind:
		Kind.GEMS:
			# On her porch, in front of the cottage, looking out over the yard.
			keeper.position = Vector3(0.6, 0.12, -yard.extents.z * 0.5 + 2.0)
			keeper.rotation.y = PI
		_:
			keeper.post = WORK_SPOT + Vector3(1.15, 0, 0)
			keeper.work_at = WORK_SPOT
			keeper.pace_to = keeper.post + Vector3(0.5, 0, 6.5)
			keeper.position = keeper.post
			keeper.rotation.y = -PI * 0.5
	if kind == Kind.LUMBER:
		keeper.struck.connect(func(at: Vector3): _chips(at, Color(0.8, 0.62, 0.36)))
		_grow_tree()
	elif kind == Kind.METAL:
		_build_rock()
		keeper.struck.connect(func(at: Vector3): _chips(at, Color(1.0, 0.85, 0.5)))
	if not (s.sells as Array).is_empty():
		_build_shop()

# --- Selling to them ------------------------------------------------------------

## What the trader buys, for the map and the prompt: "wood, lumber and goods".
func buys_text() -> String:
	var parts: Array[String] = []
	for c in spec().accepts:
		parts.append(String(c))
	if parts.size() <= 1:
		return "".join(parts)
	return ", ".join(parts.slice(0, parts.size() - 1)) + " and " + parts[parts.size() - 1]

# --- The work spot ------------------------------------------------------------------

func _grow_tree() -> void:
	if not tree_builder.is_valid():
		keeper.has_work = true
		return
	_tree_seed += 1
	tree = tree_builder.call(hash("bjorn:%d" % _tree_seed)) as ChoppableTree
	if tree == null:
		return
	tree.name = "BjornsTree"
	add_child(tree)
	tree.position = Vector3(WORK_SPOT.x, _local_ground(WORK_SPOT), WORK_SPOT.z)
	tree.felled.connect(_on_tree_felled)
	keeper.tree_back()

func _on_tree_felled(_t: ChoppableTree) -> void:
	keeper.tree_felled()
	_regrow = REGROW_SECONDS

## The miner's rock: a great lump of ore-streaked stone, solid, not for mining.
func _build_rock() -> void:
	var at := Vector3(WORK_SPOT.x, _local_ground(WORK_SPOT), WORK_SPOT.z)
	var rock := Node3D.new()
	rock.name = "DustysRock"
	add_child(rock)
	rock.position = at
	for mi in OreLook.rock(&"ore_iron", Vector3(1.5, 1.0, 1.3), Vector3(0, 0.35, 0), 0.4, 7):
		rock.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 1.0, 1.3)
	cs.shape = box
	cs.position = Vector3(0, 0.35, 0)
	body.add_child(cs)
	rock.add_child(body)

## Chips flying off where he strikes: wood chips off the tree, sparks off rock.
func _chips(at: Vector3, color: Color) -> void:
	var p := Blast._burst(color, kind == Kind.METAL, 10, 3.5, 0.5, 0.06)
	p.spread = 70.0
	p.gravity = Vector3(0, -9.8, 0)
	get_tree().current_scene.add_child(p)
	p.global_position = at
	get_tree().create_timer(1.5, false).timeout.connect(p.queue_free)

# --- The shop and the loading bay ---------------------------------------------------

func _build_shop() -> void:
	var s := spec()
	var g := Greeble.new()
	var wood := (s.hut as Color)
	var dark := wood.darkened(0.35)
	var shed := Vector3(COUNTER_AT.x, 0, COUNTER_AT.z - 2.6)
	var y0 := _local_ground(shed)
	# An open-fronted shed: floor, back and sides, a lean-to roof.
	g.block(Vector3(7.0, 0.2, 5.0), shed + Vector3(0, y0 + 0.1, 0), Color(0.45, 0.43, 0.4))
	g.block(Vector3(7.0, 3.2, 0.2), shed + Vector3(0, y0 + 1.6, -2.4), wood)
	for sx in [-1.0, 1.0]:
		g.block(Vector3(0.2, 3.0, 5.0), shed + Vector3(sx * 3.4, y0 + 1.5, 0), wood)
	g.box(Vector3(7.6, 0.14, 5.8), Transform3D(Basis(Vector3.RIGHT, 0.12), shed + Vector3(0, y0 + 3.35, 0.2)), Color(0.5, 0.52, 0.55))
	for k in 5:
		g.block(Vector3(7.02, 0.04, 0.22), shed + Vector3(0, y0 + 0.5 + float(k) * 0.6, -2.29), dark)
	# The counter across the front, with a bell on it.
	var c := COUNTER_AT
	var cy := _local_ground(c)
	g.block(Vector3(4.2, 1.05, 0.7), c + Vector3(0, cy + 0.525, 0), dark)
	g.block(Vector3(4.4, 0.08, 0.85), c + Vector3(0, cy + 1.09, 0), wood.lightened(0.2))
	g.prism(8, 0.07, 0.05, 0.08, Transform3D(Basis(), c + Vector3(1.4, cy + 1.13, 0.1)), Color(0.85, 0.7, 0.3), true)
	# What is for sale, stacked up inside: a pile of each of the first few.
	var sells: Array = s.sells
	for i in mini(sells.size(), 6):
		var def := GameData.item(sells[i])
		if def == null:
			continue
		var at := shed + Vector3(-2.6 + float(i) * 1.05, y0 + 0.2, -1.3)
		var size := def.default_dims().size as Vector3
		var lying := Vector3(size.x, size.z, size.y)
		for layer in 3:
			for col in 2:
				var off := Vector3((float(col) - 0.5) * (lying.x + 0.03) * 0.5, lying.y * (0.5 + float(layer)), 0)
				g.box(Vector3(lying.x * 0.5, lying.y, minf(lying.z, 1.4)), Transform3D(Basis(), at + off), def.color, false)
	add_child(g.instance("Shop"))
	# The sign over the shed.
	var board := Label3D.new()
	board.text = String(s.shop).to_upper()
	board.font = UITheme.display_font()
	board.font_size = 88
	board.pixel_size = 0.005
	board.modulate = Color(0.98, 0.9, 0.62)
	board.outline_size = 10
	board.outline_modulate = Color(0.12, 0.09, 0.06)
	board.position = shed + Vector3(0, y0 + 3.75, 2.2)
	add_child(board)
	# The counter you talk at, with the helper stood behind it.
	counter = TradeCounter.new()
	counter.name = "Counter"
	counter.post = self
	counter.sells = sells
	counter.shop_name = String(s.shop)
	counter.helper_name = String(s.helper)
	counter.position = c + Vector3(0, cy, 0)
	add_child(counter)
	var body := StaticBody3D.new()
	body.collision_layer = Layers.MACHINE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.2, 1.1, 0.7)
	cs.shape = box
	cs.position = Vector3(0, 0.55, 0)
	body.add_child(cs)
	counter.add_child(body)
	helper = NpcFigure.new(NpcFigure.Role.HELPER, s.helper)
	helper.watch = watch
	helper.ground = ground
	counter.add_child(helper)
	helper.position = Vector3(0, 0, -1.0)
	helper.rotation.y = PI
	_build_bay()

func _build_bay() -> void:
	var g := Greeble.new()
	var c := BAY_CENTRE
	var y := _local_ground(c)
	g.block(Vector3(BAY_SIZE.x, 0.1, BAY_SIZE.y), c + Vector3(0, y + 0.05, 0), Color(0.5, 0.49, 0.46))
	# Yellow lines round it and chevrons at the mouth.
	var yellow := Color(0.98, 0.78, 0.16)
	for sx in [-1.0, 1.0]:
		g.block(Vector3(0.18, 0.02, BAY_SIZE.y), c + Vector3(sx * (BAY_SIZE.x * 0.5 - 0.15), y + 0.11, 0), yellow)
	g.block(Vector3(BAY_SIZE.x, 0.02, 0.18), c + Vector3(0, y + 0.11, -BAY_SIZE.y * 0.5 + 0.15), yellow)
	for k in 6:
		g.box(Vector3(0.25, 0.02, 1.2), Transform3D(Basis(Vector3.UP, 0.7), c + Vector3(-2.6 + float(k) * 1.05, y + 0.115, BAY_SIZE.y * 0.5 - 0.8)), yellow)
	# Bollards and the sign.
	for sx in [-1.0, 1.0]:
		g.prism(8, 0.14, 0.14, 1.0, Transform3D(Basis(), c + Vector3(sx * (BAY_SIZE.x * 0.5 + 0.4), y, -BAY_SIZE.y * 0.5 + 0.5)), yellow)
	var post_at := c + Vector3(BAY_SIZE.x * 0.5 + 0.6, y, BAY_SIZE.y * 0.5 - 0.5)
	g.block(Vector3(0.14, 2.6, 0.14), post_at + Vector3(0, 1.3, 0), Color(0.3, 0.3, 0.32))
	g.block(Vector3(2.2, 0.8, 0.1), post_at + Vector3(0, 2.4, 0), Color(0.16, 0.2, 0.3))
	add_child(g.instance("Bay"))
	var sign := Label3D.new()
	sign.text = "LOADING\nBAY"
	sign.font = UITheme.display_font()
	sign.font_size = 64
	sign.pixel_size = 0.0045
	sign.modulate = yellow
	sign.position = post_at + Vector3(0, 2.4, 0.07)
	add_child(sign)

## Local ground height at a point in the post's frame.
func _local_ground(at: Vector3) -> float:
	if not ground.is_valid() or not is_inside_tree():
		return 0.0
	var g := to_global(Vector3(at.x, 0.0, at.z))
	var h: float = ground.call(g.x, g.z)
	return to_local(Vector3(g.x, h, g.z)).y

# --- Orders ------------------------------------------------------------------------

## Something bought at the counter: into the queue for the helper.
func enqueue(item_id: StringName, count: int) -> void:
	_queue.append([item_id, count])

## How many pieces are still to be carried out.
func queued() -> int:
	var n := _trip.size()
	for job in _queue:
		n += int(job[1])
	return n

func _process(delta: float) -> void:
	if _regrow > 0.0:
		_regrow -= delta
		if _regrow <= 0.0:
			if tree != null and is_instance_valid(tree):
				tree.queue_free()
			_grow_tree()
	if helper == null:
		return
	match _trip_state:
		&"":
			if not _queue.is_empty() and not helper.walking():
				_take_trip()
		&"fetch":
			if not helper.walking():
				helper.gesture(&"pick_up")
				_trip_state = &"lift"
				_lift_t = 0.7
		&"lift":
			_lift_t -= delta
			if _lift_t <= 0.0:
				helper.hold(_stack(_trip))
				helper.walk(counter.to_local(to_global(DROP_AT)), &"idle")
				_trip_state = &"carry"
		&"carry":
			if not helper.walking():
				_unload()
				helper.hold(null)
				if _queue.is_empty():
					helper.say("All loaded!" if _dropped > 0 else "Done!", 3.0)
					helper.gesture(&"cheer")
					helper.walk(Vector3(0, 0, -1.0), &"idle")
					_trip_state = &"home"
				else:
					_trip_state = &""
		&"home":
			if not helper.walking():
				helper.rotation.y = PI
				_trip_state = &""
				_dropped = 0

var _lift_t := 0.0

## Up to a load's worth off the front of the queue, and off to the stock.
func _take_trip() -> void:
	_trip.clear()
	var most: int = spec().carry
	while _trip.size() < most and not _queue.is_empty():
		var job: Array = _queue[0]
		_trip.append(job[0])
		job[1] = int(job[1]) - 1
		if int(job[1]) <= 0:
			_queue.pop_front()
	helper.walk(counter.to_local(to_global(STOCK_AT)), &"idle")
	_trip_state = &"fetch"

## What he carries: the pieces as boxes in his arms.
func _stack(ids: Array) -> Node3D:
	var g := Greeble.new()
	var y := 0.0
	for id in ids:
		var def := GameData.item(id)
		if def == null:
			continue
		var size := def.default_dims().size as Vector3
		# Laid across his arms, long way sideways.
		var lying := Vector3(minf(size.y, 1.2), size.z, size.x)
		g.box(lying, Transform3D(Basis(), Vector3(0, y + lying.y * 0.5, 0)), def.color, false)
		y += lying.y
	var load := g.instance("Load")
	# An armful: a tall load is shown shrunk to what he can see over.
	var fit := minf(1.0, 0.6 / maxf(0.01, y))
	var holder := Node3D.new()
	holder.name = "Armful"
	holder.add_child(load)
	load.scale = Vector3.ONE * fit
	return holder

## The load goes into the truck in the bay, or onto the bay floor.
func _unload() -> void:
	if manager == null or _trip.is_empty():
		_trip.clear()
		return
	var truck := _truck_in_bay()
	for id in _trip:
		var def := GameData.item(id)
		if def == null:
			continue
		var dims := def.default_dims()
		var xform := _slot(truck, dims, _dropped)
		var item := manager.spawn(id, xform, 0, Vector3.ZERO, dims, true)
		if item != null:
			item.owned = true
		_dropped += 1
	Sfx.play(&"drop", to_global(DROP_AT), -2.0)
	_trip.clear()

## A parked vehicle with a bed, in the bay.
func _truck_in_bay() -> Hauler:
	var list: Array = vehicles.call() if vehicles.is_valid() else get_tree().get_nodes_in_group(&"vehicles")
	for v in list:
		var h := v as Hauler
		if h == null or not is_instance_valid(h) or not h.has_bed():
			continue
		var local := to_local(h.global_position) - BAY_CENTRE
		if absf(local.x) < BAY_SIZE.x * 0.5 + 1.0 and absf(local.z) < BAY_SIZE.y * 0.5 + 1.5:
			return h
	return null

## Where the n-th piece of a delivery goes: rows in the truck's bed, laid
## lengthways; or rows on the bay floor. A little above, to settle.
func _slot(truck: Hauler, dims: Dictionary, n: int) -> Transform3D:
	var size := Solid.bounds(dims)
	# Lying down, long way along the bed or the bay.
	var lie := Basis(Vector3.RIGHT, PI * 0.5)
	var w := size.x + 0.04
	var h := size.z + 0.03
	var l := size.y + 0.05
	if truck != null:
		var across := maxi(1, int(truck.bed_half_width * 2.0 / w))
		var along := maxi(1, int(truck.bed_length / l))
		var per := across * along
		var layer := n / per
		var i := n % per
		var x := -truck.bed_half_width + w * (0.5 + float(i % across))
		var z := truck.bed_front + l * (0.5 + float(i / across))
		var local := Vector3(x, truck.bed_floor + h * (0.5 + float(layer)) + 0.06, z)
		return truck.global_transform * Transform3D(lie, local)
	var across2 := maxi(1, int((BAY_SIZE.x - 1.0) / w))
	var along2 := maxi(1, int((BAY_SIZE.y * 0.5) / l))
	var per2 := across2 * along2
	var layer2 := n / per2
	var i2 := n % per2
	var fx := -BAY_SIZE.x * 0.5 + 0.5 + w * (0.5 + float(i2 % across2))
	var fz := -BAY_SIZE.y * 0.5 + 0.6 + l * (0.5 + float(i2 / across2))
	var floor_y := _local_ground(BAY_CENTRE) + 0.1
	return global_transform * Transform3D(lie, BAY_CENTRE + Vector3(fx, floor_y + h * (0.5 + float(layer2)) + 0.05, fz))
