class_name Store
extends Node3D

## A shop you walk around in.
##
## Tools, machines and vehicles sit on the shelves in labelled boxes. You carry
## what you want to the counter, the till charges for everything standing on it,
## and a paid box is yours to carry off and open wherever you like. Walk out
## holding something you have not paid for and it goes back on its shelf, which
## is the politest possible way to say no.
##
## Land is sold at the desk by the door, since a bigger plot does not come in
## a box.

signal purchased(box_id: StringName, price: int)
signal opened(box_id: StringName, what: String)

## Footprint of the shop floor. Unpaid stock may not leave it.
@export var extents: Vector3 = Vector3(20.0, 5.0, 14.0)

var manager: LooseItemManager
var plot: Plot
var plot_id: int = 0

## One shelf slot per product: {box, kind, target, spot, item}
var slots: Array[Dictionary] = []

var _counter_area: Area3D
var _counter_shape: CollisionShape3D
var _till: Node3D
var _desk: Node3D
var _poll: float = 0.0

func setup(p_manager: LooseItemManager, p_plot: Plot = null, p_plot_id: int = 0) -> void:
	manager = p_manager
	plot = p_plot
	plot_id = p_plot_id

func _ready() -> void:
	_build()
	restock()
	set_physics_process(true)

func contains(point: Vector3) -> bool:
	var local := to_local(point)
	return absf(local.x) <= extents.x * 0.5 and absf(local.z) <= extents.z * 0.5 \
		and local.y >= -2.0 and local.y <= extents.y

func till_position() -> Vector3:
	return _till.global_position

func desk_position() -> Vector3:
	return _desk.global_position

## Which part of the shop the player is aiming at.
func role_at(point: Vector3) -> StringName:
	if point.distance_to(till_position()) <= 2.6:
		return &"till"
	if point.distance_to(desk_position()) <= 2.2:
		return &"desk"
	return &""

# --- Stock -----------------------------------------------------------------

## What this box costs today. Upgrade boxes follow their track's next level and
## machine crates follow their building's unlock price, so nothing is priced in
## two places.
func price_of(slot: Dictionary) -> int:
	if slot.kind == &"upgrade":
		return PlayerState.next_cost(slot.target)
	var def := GameData.building(slot.target)
	return def.unlock_cost if def != null else -1

## Whether the shop still has a reason to stock this: a maxed track or a
## building you already own is not for sale.
func available(slot: Dictionary) -> bool:
	if slot.kind == &"upgrade":
		return not PlayerState.at_max(slot.target)
	return not PlayerState.is_unlocked(slot.target)

## Puts a box back on every shelf slot that should have one.
func restock() -> int:
	var placed := 0
	for slot in slots:
		var live := slot.item as LooseItem
		if live != null and is_instance_valid(live) and live.state != LooseItem.State.POOLED:
			if available(slot):
				continue
			# No longer for sale: take it back off the shelf.
			manager.despawn(live)
			slot.item = null
			continue
		slot.item = null
		if not available(slot):
			continue
		var box := manager.spawn(slot.box, Transform3D(Basis(), slot.spot), plot_id)
		if box == null:
			continue
		box.sleeping = true
		slot.item = box
		placed += 1
	return placed

## Everything standing on the counter right now.
func on_counter() -> Array[LooseItem]:
	var out: Array[LooseItem] = []
	if manager == null:
		return out
	for body in Trigger.bodies_inside(_counter_area, _counter_shape, 0.3):
		var item := body as LooseItem
		if item != null and item.state == LooseItem.State.FREE:
			out.append(item)
	return out

func _slot_for(box_id: StringName) -> Dictionary:
	for slot in slots:
		if slot.box == box_id:
			return slot
	return {}

## Spec: an interaction at the counter buys the objects on it. `carried` is
## whatever the player is holding as they ask.
func buy(carried: Array[LooseItem] = []) -> Dictionary:
	var items := on_counter()
	for item in carried:
		if is_instance_valid(item) and not items.has(item):
			items.append(item)
	var bought := 0
	var spent := 0
	var refused: Array[String] = []
	for item in items:
		if item.owned:
			continue        # already paid for, just sitting there
		var slot := _slot_for(item.item_id)
		if slot.is_empty():
			continue
		var price := price_of(slot)
		if price < 0:
			refused.append("%s is not for sale" % GameData.item_name(item.item_id))
			continue
		if not Economy.try_spend(price):
			refused.append("%s costs $%d" % [GameData.item_name(item.item_id), price])
			continue
		item.owned = true
		if slot.item == item:
			slot.item = null
		bought += 1
		spent += price
		purchased.emit(item.item_id, price)
	restock()
	return {"bought": bought, "spent": spent, "refused": refused}

## Spec: once purchased, the box can be carried and moved like any other object.
## Opening one is what actually delivers what is inside.
func open_box(item: LooseItem) -> String:
	if item == null or not is_instance_valid(item):
		return "nothing to open"
	var slot := _slot_for(item.item_id)
	if slot.is_empty():
		return "that is not a box"
	if not item.owned:
		return "that one has not been paid for"
	var what := ""
	if slot.kind == &"upgrade":
		# The box is the payment, so the upgrade itself is free at this point.
		PlayerState.levels[slot.target] = PlayerState.level(slot.target) + 1
		PlayerState.upgraded.emit(slot.target, PlayerState.level(slot.target))
		what = "%s is now %s" % [String(slot.target), PlayerState.label(slot.target)]
	else:
		if not PlayerState.is_unlocked(slot.target):
			PlayerState.unlocked_buildings.append(slot.target)
			PlayerState.unlocked.emit(slot.target)
		var def := GameData.building(slot.target)
		what = "%s unlocked - place it in build mode" % (
			def.display_name if def != null else String(slot.target))
	manager.despawn(item)
	restock()
	opened.emit(item.item_id, what)
	return what

## Spec: the store also sells land.
func buy_land() -> String:
	if plot == null:
		return "no plot to expand"
	var cost := plot.next_expansion_cost()
	if cost < 0:
		return "your plot is already as big as it gets"
	if not Economy.can_afford(cost):
		return "the next parcel costs $%d" % cost
	if not plot.try_expand():
		return "the sale fell through"
	return "plot expanded to %.0f m across" % (plot.half_extent * 2.0)

## Spec: unpaid stock carried out of the store disappears - and reappears on
## the shelf it came from.
func _physics_process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.4
	var lost := false
	for slot in slots:
		var item := slot.item as LooseItem
		if item == null or not is_instance_valid(item):
			continue
		if item.owned or item.state == LooseItem.State.POOLED:
			continue
		if contains(item.global_position):
			continue
		manager.despawn(item)
		slot.item = null
		lost = true
	if lost:
		restock()

func status_line(role: StringName) -> String:
	if role == &"desk":
		var cost := plot.next_expansion_cost() if plot != null else -1
		if cost < 0:
			return "Land desk: nothing left to sell you"
		return "Land desk: [E] buy the next parcel for $%d" % cost
	var items := on_counter()
	if items.is_empty():
		return "Till: put boxes on the counter and [E] to pay"
	var total := 0
	for item in items:
		if item.owned:
			continue
		var slot := _slot_for(item.item_id)
		if not slot.is_empty():
			total += maxi(0, price_of(slot))
	return "Till: [E] pay $%d for %d box(es)" % [total, items.size()]

# --- Geometry --------------------------------------------------------------

func _build() -> void:
	var half_x := extents.x * 0.5
	var half_z := extents.z * 0.5
	_slab(Vector3(extents.x, 0.2, extents.z), Vector3(0, 0.1, 0), Color(0.48, 0.46, 0.43), true)
	# Three walls and a wide doorway on the +Z side, so the shop is a room you
	# walk into rather than a pad you walk over.
	_slab(Vector3(extents.x, 4.0, 0.3), Vector3(0, 2.0, -half_z), Color(0.62, 0.58, 0.52), true)
	_slab(Vector3(0.3, 4.0, extents.z), Vector3(-half_x, 2.0, 0), Color(0.62, 0.58, 0.52), true)
	_slab(Vector3(0.3, 4.0, extents.z), Vector3(half_x, 2.0, 0), Color(0.62, 0.58, 0.52), true)
	for side in [-1.0, 1.0]:
		_slab(Vector3(extents.x * 0.32, 4.0, 0.3),
			Vector3(side * (half_x - extents.x * 0.16), 2.0, half_z),
			Color(0.62, 0.58, 0.52), true)
	_slab(Vector3(extents.x, 0.3, extents.z), Vector3(0, 4.15, 0), Color(0.40, 0.36, 0.33), true)

	# Shelving down the back and the left wall.
	var products := GameData.store_products()
	var per_shelf := 4
	var shelf_levels := [0.9, 1.75]
	slots.clear()
	for i in products.size():
		var entry: Dictionary = products[i]
		var row: int = (i / per_shelf) % shelf_levels.size()
		var bay: int = i / (per_shelf * shelf_levels.size())
		var column: int = i % per_shelf
		var shelf_z: float = -half_z + 1.2 + float(bay) * 3.2
		var x: float = -half_x + 2.2 + float(column) * ((extents.x - 4.4) / float(per_shelf - 1))
		var spot := to_global(Vector3(x, shelf_levels[row] + 0.35, shelf_z))
		slots.append({
			"box": StringName(entry.get("box", "")),
			"kind": StringName(entry.get("kind", "unlock")),
			"target": StringName(entry.get("target", "")),
			"spot": spot,
			"item": null,
		})
	# The shelves themselves: one board per level per bay.
	var bays: int = int(ceil(float(products.size()) / float(per_shelf * shelf_levels.size())))
	for bay in maxi(1, bays):
		var shelf_z: float = -half_z + 1.2 + float(bay) * 3.2
		for level in shelf_levels:
			_slab(Vector3(extents.x - 3.6, 0.12, 1.1), Vector3(0, level, shelf_z),
				Color(0.55, 0.44, 0.30), true)
		for side in [-1.0, 1.0]:
			_slab(Vector3(0.18, 2.1, 1.1),
				Vector3(side * (extents.x * 0.5 - 1.9), 1.05, shelf_z),
				Color(0.42, 0.33, 0.22), true)

	# The counter, near the door, with a till on it.
	var counter_z := half_z - 3.0
	_slab(Vector3(6.0, 1.0, 1.4), Vector3(-2.0, 0.5, counter_z), Color(0.50, 0.38, 0.26), true)
	_till = Node3D.new()
	_till.position = Vector3(-2.0, 1.05, counter_z)
	add_child(_till)
	_slab(Vector3(0.7, 0.45, 0.5), Vector3(-4.2, 1.25, counter_z), Color(0.24, 0.26, 0.30), false)

	_counter_area = Area3D.new()
	_counter_area.collision_layer = Layers.TRIGGER
	_counter_area.collision_mask = Layers.LOOSE
	_counter_shape = CollisionShape3D.new()
	var cb := BoxShape3D.new()
	cb.size = Vector3(6.0, 1.4, 1.4)
	_counter_shape.shape = cb
	_counter_shape.position = Vector3(-2.0, 1.7, counter_z)
	_counter_area.add_child(_counter_shape)
	add_child(_counter_area)

	# The land desk, opposite the counter.
	_desk = Node3D.new()
	_desk.position = Vector3(half_x - 2.4, 1.05, counter_z)
	add_child(_desk)
	_slab(Vector3(2.4, 1.0, 1.2), Vector3(half_x - 2.4, 0.5, counter_z), Color(0.34, 0.40, 0.46), true)
	_slab(Vector3(1.6, 0.9, 0.08), Vector3(half_x - 2.4, 2.0, counter_z - 0.5),
		Color(0.80, 0.78, 0.70), false)

func _slab(size: Vector3, pos: Vector3, color: Color, collide: bool) -> void:
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = Layers.MACHINE
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		cs.position = pos
		body.add_child(cs)
		add_child(body)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mi.material_override = mat
	add_child(mi)
