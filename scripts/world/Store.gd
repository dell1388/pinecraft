class_name Store
extends Node3D

## A shop you walk around in.
##
## The floor is laid out in sections - Tools, Vehicles, Conveyors, Machinery,
## Gear, Doodads - each a bay with a big sign over it and a stepped shelf of
## boxes. Every box has a picture of what is inside printed on its front, and
## machine tiers wear a T1 / T2 / T3 badge. You carry what you want to the
## counter, the till charges for everything standing on it, and a paid box is
## yours to carry off and open wherever you like. Walk out holding something
## you have not paid for and it goes back on its shelf.
##
## There are two: the general store in town, and Summit Outfitters up in the
## high country, which sells the best tools, the heavy trucks and the top tier
## of every machine. Land is sold at the general store's desk.

signal purchased(box_id: StringName, price: int)
signal opened(box_id: StringName, what: String)

## Footprint of the shop floor. Unpaid stock may not leave it.
@export var extents: Vector3 = Vector3(30.0, 5.0, 22.0)

var manager: LooseItemManager
var plot: Plot
var plot_id: int = 0
var store_id: StringName = &"general"
var store_name: String = "GENERAL STORE"

## One shelf slot per product:
## {box, kind, target, tier, section, color, spot, basis, item}
var slots: Array[Dictionary] = []

var _g: Greeble
var _counter_area: Area3D
var _counter_shape: CollisionShape3D
var _till: Node3D
var _desk: Node3D
var _poll: float = 0.0
var _art: BoxArt

const WALL_HEIGHT := 5.0
const BAY_DEPTH := 2.8

func setup(p_manager: LooseItemManager, p_plot: Plot = null, p_plot_id: int = 0,
		p_store: StringName = &"general") -> void:
	manager = p_manager
	plot = p_plot
	plot_id = p_plot_id
	store_id = p_store
	var def := GameData.store_def(p_store)
	store_name = String(def.get("name", "STORE"))
	if p_store != &"general":
		extents = Vector3(26.0, 5.0, 18.0)

func _ready() -> void:
	_art = BoxArt.new()
	add_child(_art)
	_build()
	restock()
	set_physics_process(true)

func has_land_desk() -> bool:
	return store_id == &"general"

func contains(point: Vector3) -> bool:
	var local := to_local(point)
	return absf(local.x) <= extents.x * 0.5 and absf(local.z) <= extents.z * 0.5 \
		and local.y >= -2.0 and local.y <= extents.y

func till_position() -> Vector3:
	return _till.global_position

func desk_position() -> Vector3:
	return _desk.global_position if _desk != null else Vector3(INF, INF, INF)

## Which part of the shop the player is aiming at.
func role_at(point: Vector3) -> StringName:
	if point.distance_to(till_position()) <= 2.6:
		return &"till"
	if _desk != null and point.distance_to(desk_position()) <= 2.2:
		return &"desk"
	return &""

# --- Stock -----------------------------------------------------------------

## What this box costs. Nothing is priced in two places: tools cost what
## tools.json says, a building costs its unit price (a machine above its
## first tier, that level of its track), gear costs its next level.
func price_of(slot: Dictionary) -> int:
	var target: StringName = slot.target
	match slot.kind:
		&"tool":
			return int(GameData.tool(target).get("cost", -1))
		&"upgrade":
			return PlayerState.next_cost(target)
		&"tier":
			var tier: int = int(slot.tier)
			if tier <= 1:
				var def := GameData.building(target)
				return def.cost if def != null else -1
			return int(GameData.upgrade_level(target, tier).get("cost", -1))
	var b := GameData.building(target)
	return b.cost if b != null else -1

## Whether the shop still has a reason to stock this: a tool you have or a
## maxed track is gone. Buildings are always on the shelf - each box is one
## copy to build, so you buy as many as you want to put up.
func available(slot: Dictionary) -> bool:
	var target: StringName = slot.target
	match slot.kind:
		&"tool":
			return not PlayerState.owns_tool(target)
		&"upgrade":
			return not PlayerState.at_max(target)
	return true

## Why a box cannot be bought yet, or "" if it can. Nothing is: buy in any
## order you like - a higher tier bought first brings the machine with it.
func blocked(_slot: Dictionary) -> String:
	return ""

## Puts a box back on every shelf slot that should have one.
func restock() -> int:
	var placed := 0
	for slot in slots:
		var live := slot.item as LooseItem
		if live != null and is_instance_valid(live) and live.state != LooseItem.State.POOLED:
			if available(slot) or live.owned:
				continue
			# No longer for sale: take it back off the shelf.
			manager.despawn(live)
			slot.item = null
			continue
		slot.item = null
		if not available(slot):
			continue
		var box := manager.spawn(slot.box, Transform3D(slot.basis, slot.spot), plot_id)
		if box == null:
			continue
		_dress_box(box, slot)
		box.sleeping = true
		slot.item = box
		placed += 1
	return placed

## The box's printed front: the product's picture, its name, a price, and a
## tier badge where there is one.
func _dress_box(box: LooseItem, slot: Dictionary) -> void:
	var size: Vector3 = box.dims.size
	var face := size.z * 0.5 + 0.004
	var flat := size.y < 0.6
	# The picture: on the front of a tall box, on the lid of a flat one.
	var sticker := MeshInstance3D.new()
	var quad := QuadMesh.new()
	if flat:
		var side := minf(size.x, size.z) * 0.92
		quad.size = Vector2(side, side)
		sticker.rotation = Vector3(-PI * 0.5, 0, 0)
		sticker.position = Vector3(0, size.y * 0.5 + 0.004, 0)
	else:
		var side := minf(size.x * 0.9, size.y * 0.66)
		quad.size = Vector2(side, side)
		sticker.position = Vector3(0, size.y * 0.5 - side * 0.5 - 0.04, face)
	sticker.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = (slot.color as Color).lightened(0.3)
	mat.roughness = 0.8
	sticker.material_override = mat
	box.add_extra_node(sticker)
	_art.request(slot, func(tex: Texture2D):
		if is_instance_valid(sticker):
			mat.albedo_color = Color.WHITE
			mat.albedo_texture = tex)
	# Name and price along the bottom of the front.
	var px := 0.0026
	var label := Label3D.new()
	label.text = "%s   %s" % [GameData.product_name(slot), UIKit.money(price_of(slot)) if price_of(slot) >= 0 else ""]
	label.font = UITheme.font(800)
	label.font_size = 48
	label.pixel_size = px
	label.width = (size.x - 0.08) / px
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.outline_size = 10
	label.outline_modulate = Color(0, 0, 0, 0.6)
	label.modulate = Color.WHITE
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.position = Vector3(0, -size.y * 0.5 + 0.05, face + 0.002)
	box.add_extra_node(label)
	if slot.kind == &"tier":
		var badge := Label3D.new()
		badge.text = "T%d" % int(slot.tier)
		badge.font = UITheme.font(800)
		badge.font_size = 96
		badge.pixel_size = 0.003
		badge.outline_size = 18
		badge.outline_modulate = (slot.color as Color).darkened(0.5)
		badge.modulate = Color(1, 1, 1)
		badge.position = Vector3(size.x * 0.5 - 0.14, size.y * 0.5 - 0.12, face + 0.004)
		box.add_extra_node(badge)

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
		var why := blocked(slot)
		if why != "":
			refused.append(why)
			continue
		if not Economy.try_spend(price):
			refused.append("%s costs $%d" % [GameData.product_name(slot), price])
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
	var target: StringName = slot.target
	var what := ""
	match slot.kind:
		&"tool":
			PlayerState.give_tool(target)
			what = "%s added to your inventory - it is on the hotbar [I]" % GameData.tool_name(target)
		&"upgrade":
			what = _level_up(target)
		_:
			# One copy of the building, at the box's tier, to put up in build
			# mode for free. A higher tier is its own machine: it does not
			# bring the lower one with it.
			var tier: int = int(slot.get("tier", 1))
			_unlock(target)
			PlayerState.add_copy(target, tier)
			var def := PlayerState.def_at_tier(target, tier)
			what = "%s added - build it in build mode (%d to build)" % [
				def.display_name if def != null else String(target), PlayerState.spare_count(target, tier)]
	manager.despawn(item)
	restock()
	opened.emit(item.item_id, what)
	return what

func _unlock(target: StringName) -> void:
	if not PlayerState.is_unlocked(target):
		PlayerState.unlocked_buildings.append(target)
		PlayerState.unlocked.emit(target)

func _level_up(track: StringName) -> String:
	PlayerState.levels[track] = PlayerState.level(track) + 1
	PlayerState.upgraded.emit(track, PlayerState.level(track))
	return "%s is now %s" % [String(track), PlayerState.label(track)]

## Spec: the store also sells land.
func buy_land() -> String:
	if plot == null or not has_land_desk():
		return "no land for sale here"
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

## What the player sees aiming at a box on a shelf.
func box_line(item: LooseItem) -> String:
	var slot := _slot_for(item.item_id)
	if slot.is_empty():
		return ""
	if item.owned:
		return "%s - paid for. [E] open it" % GameData.product_name(slot)
	var line := "%s   %s   [LMB] drag it to the counter" % [GameData.product_name(slot), UIKit.money(price_of(slot))]
	var why := blocked(slot)
	return line + ("\n" + why if why != "" else "")

# --- Geometry --------------------------------------------------------------

func _palette() -> Dictionary:
	if store_id == &"general":
		return {"wall": Color(0.62, 0.58, 0.52), "trim": Color(0.32, 0.30, 0.28), "floor": Color(0.62, 0.52, 0.38),
			"tile": Color(0.56, 0.46, 0.33), "sign": Color(0.20, 0.34, 0.24), "sign_text": Color(0.98, 0.88, 0.55),
			"awning": Color(0.82, 0.22, 0.18), "shelf": Color(0.84, 0.84, 0.82), "brick": Color(0.66, 0.66, 0.66)}
	return {"wall": Color(0.42, 0.44, 0.50), "trim": Color(0.18, 0.18, 0.22), "floor": Color(0.36, 0.30, 0.26),
		"tile": Color(0.30, 0.25, 0.22), "sign": Color(0.12, 0.16, 0.30), "sign_text": Color(0.98, 0.80, 0.35),
		"awning": Color(0.16, 0.26, 0.52), "shelf": Color(0.72, 0.74, 0.78), "brick": Color(0.52, 0.54, 0.60)}

func _build() -> void:
	_g = Greeble.new()
	var pal := _palette()
	var half_x := extents.x * 0.5
	var half_z := extents.z * 0.5
	_slab(Vector3(extents.x, 0.2, extents.z), Vector3(0, 0.1, 0), pal.floor, true)
	# Three walls and a wide doorway on the +Z side, so the shop is a room you
	# walk into rather than a pad you walk over.
	_slab(Vector3(extents.x, WALL_HEIGHT, 0.3), Vector3(0, WALL_HEIGHT * 0.5, -half_z), pal.brick, true)
	_slab(Vector3(0.3, WALL_HEIGHT, extents.z), Vector3(-half_x, WALL_HEIGHT * 0.5, 0), pal.brick, true)
	_slab(Vector3(0.3, WALL_HEIGHT, extents.z), Vector3(half_x, WALL_HEIGHT * 0.5, 0), pal.brick, true)
	var door := 6.0
	var side_w := (extents.x - door) * 0.5
	for side in [-1.0, 1.0]:
		_slab(Vector3(side_w, WALL_HEIGHT, 0.3), Vector3(side * (half_x - side_w * 0.5), WALL_HEIGHT * 0.5, half_z), pal.wall, true)
	_slab(Vector3(extents.x, 0.3, extents.z), Vector3(0, WALL_HEIGHT + 0.15, 0), pal.trim, true)
	# Brick coursing on the inside walls, and a timber beam round the top.
	for k in 8:
		var y := 0.5 + float(k) * 0.55
		_g.block(Vector3(extents.x - 0.4, 0.04, 0.02), Vector3(0, y, -half_z + 0.16), pal.brick.darkened(0.12))
		for side in [-1.0, 1.0]:
			_g.block(Vector3(0.02, 0.04, extents.z - 0.4), Vector3(side * (half_x - 0.16), y, 0), pal.brick.darkened(0.12))
	_g.frame(Vector3(extents.x - 0.3, 0.3, extents.z - 0.3), Transform3D(Basis(), Vector3(0, WALL_HEIGHT - 0.15, 0)), 0.3, Color(0.62, 0.46, 0.28))

	_lay_out_sections()
	# Shop lights: warm lamps down the middle of the ceiling.
	for k in 4:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.92, 0.78)
		lamp.light_energy = 1.4
		lamp.omni_range = extents.x * 0.45
		lamp.position = Vector3(-extents.x * 0.3 + float(k % 2) * extents.x * 0.6, WALL_HEIGHT - 0.6, -extents.z * 0.22 + float(k / 2) * extents.z * 0.4)
		add_child(lamp)
		_g.block(Vector3(1.2, 0.08, 0.4), lamp.position + Vector3(0, 0.45, 0), Color(1.0, 0.95, 0.8), true)

	# The counter, near the door, with a till on it.
	var counter_z := half_z - 3.4
	_slab(Vector3(6.0, 1.0, 1.4), Vector3(-2.0, 0.5, counter_z), Color(0.50, 0.38, 0.26), true)
	_g.block(Vector3(6.1, 0.08, 1.5), Vector3(-2.0, 1.02, counter_z), Color(0.86, 0.84, 0.8))
	_till = Node3D.new()
	_till.position = Vector3(-2.0, 1.05, counter_z)
	add_child(_till)
	_slab(Vector3(0.7, 0.45, 0.5), Vector3(-4.2, 1.25, counter_z), Color(0.24, 0.26, 0.30), false)
	_g.block(Vector3(0.5, 0.25, 0.04), Vector3(-4.2, 1.55, counter_z + 0.2), Color(0.4, 0.9, 0.5), true)

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

	if has_land_desk():
		_desk = Node3D.new()
		_desk.position = Vector3(4.0, 1.05, counter_z)
		add_child(_desk)
		_slab(Vector3(2.4, 1.0, 1.2), Vector3(4.0, 0.5, counter_z), Color(0.34, 0.40, 0.46), true)
		_slab(Vector3(1.6, 0.9, 0.08), Vector3(4.0, 2.0, counter_z - 0.5), Color(0.80, 0.78, 0.70), false)
		_label("LAND", Vector3(4.0, 2.0, counter_z - 0.44), Basis(), 64, Color(0.2, 0.3, 0.2), 0)
	_storefront(half_x, half_z, pal)
	add_child(_g.instance("StoreMesh"))

## Where each section's bay goes: along the back wall first, then down the
## sides, each facing into the room.
func _bay_frames(count: int) -> Array[Transform3D]:
	var half_x := extents.x * 0.5
	var half_z := extents.z * 0.5
	var out: Array[Transform3D] = []
	var back := mini(3, count)
	var bay_w := (extents.x - 1.0) / float(back)
	for i in back:
		var x := -half_x + 0.5 + bay_w * (float(i) + 0.5)
		out.append(Transform3D(Basis(), Vector3(x, 0.2, -half_z + 0.15)))
	var rest := count - back
	var per_side := int(ceil(float(rest) / 2.0))
	var run := extents.z - 2.0 * BAY_DEPTH - 5.5
	for i in rest:
		var side := -1.0 if i % 2 == 0 else 1.0
		var k := i / 2
		var z := -half_z + BAY_DEPTH + 0.4 + run * (float(k) + 0.5) / float(maxi(1, per_side))
		var basis := Basis(Vector3.UP, -side * PI * 0.5)
		out.append(Transform3D(basis, Vector3(side * (half_x - 0.15), 0.2, z)))
	return out

func _bay_width(index: int, count: int) -> float:
	if index < mini(3, count):
		return (extents.x - 1.0) / float(mini(3, count)) - 0.6
	var rest := count - mini(3, count)
	var per_side := int(ceil(float(rest) / 2.0))
	return minf(7.5, (extents.z - 2.0 * BAY_DEPTH - 5.5) / float(maxi(1, per_side)) - 0.4)

## Each section: a coloured back panel, a stepped shelf two boxes deep, and a
## sign over it in the section's colour.
func _lay_out_sections() -> void:
	slots.clear()
	var def := GameData.store_def(store_id)
	var sections: Array = def.get("sections", [])
	var frames := _bay_frames(sections.size())
	var products := GameData.store_products(store_id)
	var pal := _palette()
	for i in sections.size():
		var section: Dictionary = sections[i]
		var frame := frames[i]
		var width := _bay_width(i, sections.size())
		var color := BoxArt._color(section.get("color", [0.5, 0.5, 0.5]))
		# Back panel and the sign.
		_g.box(Vector3(width, 3.2, 0.05), frame * Transform3D(Basis(), Vector3(0, 1.8, 0.03)), color.lerp(Color.WHITE, 0.75))
		_g.box(Vector3(width * 0.8 + 0.24, 1.25, 0.12), frame * Transform3D(Basis(), Vector3(0, 3.9, 0.25)), color)
		_g.box(Vector3(width * 0.8, 1.05, 0.14), frame * Transform3D(Basis(), Vector3(0, 3.9, 0.26)), Color(0.9, 0.9, 0.92))
		var title := String(section.get("title", ""))
		var fit := int(minf(210.0, width * 0.8 * 0.92 / (float(maxi(1, title.length())) * 0.62 * 0.0045)))
		_label(title, frame * Vector3(0, 3.9, 0.34), frame.basis, fit, color, 0)
		# Stepped shelf: a low front step and a high back step.
		var steps := [[Vector3(width, 0.45, 1.3), Vector3(0, 0.225, 2.0)],
			[Vector3(width, 1.05, 1.3), Vector3(0, 0.525, 0.7)]]
		for st in steps:
			var size: Vector3 = st[0]
			var at: Vector3 = st[1]
			_slab_at(size, frame * Transform3D(Basis(), at), pal.shelf)
			_g.box(Vector3(size.x + 0.02, 0.06, size.z + 0.02), frame * Transform3D(Basis(), at + Vector3(0, size.y * 0.5, 0)), Color(0.62, 0.46, 0.28))
		var mine: Array = products.filter(func(p): return p.section == section.get("title", ""))
		var per_row := int(ceil(float(mine.size()) / 2.0))
		for k in mine.size():
			var p: Dictionary = mine[k]
			var row := 0 if k < per_row else 1          # back row first, then front
			var col := k if row == 0 else k - per_row
			var n := per_row if row == 0 else mine.size() - per_row
			var bs: Array = p.box_size
			var x := -width * 0.5 + width * (float(col) + 0.5) / float(maxi(1, n))
			var y := 0.2 + (1.05 if row == 0 else 0.45) + float(bs[1]) * 0.5 + 0.03
			var z := 0.7 if row == 0 else 2.0
			var spot := frame * Vector3(x, y - 0.2, z)
			slots.append({
				"box": p.box, "kind": StringName(p.kind), "target": StringName(p.target),
				"tier": int(p.get("tier", 0)), "section": p.section, "color": BoxArt._color(p.color),
				"spot": to_global(spot), "basis": global_transform.basis * frame.basis, "item": null})

func _label(text: String, at: Vector3, basis: Basis, size: int, color: Color, outline: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UITheme.display_font()
	l.font_size = size
	l.pixel_size = 0.0045
	l.outline_size = outline
	l.modulate = color
	l.transform = Transform3D(basis, at)
	l.double_sided = false
	add_child(l)
	return l

## The outside: a parapet, a striped awning over the door, lit windows, the
## sign board, lamps and some stock stacked by the door.
func _storefront(half_x: float, half_z: float, pal: Dictionary) -> void:
	var wall: Color = pal.wall
	var trim: Color = pal.trim
	_g.frame(Vector3(extents.x + 0.3, 0.5, extents.z + 0.3), Transform3D(Basis(), Vector3(0, WALL_HEIGHT + 0.45, 0)), 0.3, trim)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_g.block(Vector3(0.5, WALL_HEIGHT + 0.3, 0.5), Vector3(sx * half_x, (WALL_HEIGHT + 0.3) * 0.5, sz * half_z), trim.lightened(0.1))
	_g.frame(Vector3(extents.x + 0.1, 0.6, extents.z + 0.1), Transform3D(Basis(), Vector3(0, 0.3, 0)), 0.2, wall.darkened(0.3))
	var door_w := 6.0
	var stripes := 8
	for i in stripes:
		var x := -door_w * 0.5 - 0.5 + (float(i) + 0.5) * (door_w + 1.0) / float(stripes)
		var color: Color = pal.awning if i % 2 == 0 else Color(0.95, 0.92, 0.86)
		_g.box(Vector3((door_w + 1.0) / float(stripes), 0.08, 1.8), Transform3D(Basis(Vector3.RIGHT, 0.32), Vector3(x, 3.95, half_z + 0.85)), color)
	_g.block(Vector3(door_w + 1.2, 0.12, 0.12), Vector3(0, 3.68, half_z + 1.7), trim)
	var board_w := door_w + 4.0
	_g.box(Vector3(board_w, 1.0, 0.15), Transform3D(Basis(), Vector3(0, WALL_HEIGHT - 0.2, half_z + 0.25)), pal.sign)
	_g.frame(Vector3(board_w, 1.0, 0.15), Transform3D(Basis(), Vector3(0, WALL_HEIGHT - 0.2, half_z + 0.25)), 0.08, Color(0.92, 0.76, 0.30))
	var sign := Label3D.new()
	sign.text = store_name
	sign.font = UITheme.display_font()
	sign.font_size = 96
	sign.pixel_size = 0.008
	sign.outline_size = 0
	sign.modulate = pal.sign_text
	sign.position = Vector3(0, WALL_HEIGHT - 0.2, half_z + 0.34)
	add_child(sign)
	for sx in [-1.0, 1.0]:
		for k in 2:
			var z := -half_z * 0.5 + float(k) * half_z
			_g.box(Vector3(0.1, 1.4, 2.2), Transform3D(Basis(), Vector3(sx * (half_x + 0.1), 2.6, z)), Color(0.95, 0.85, 0.55), true)
			_g.frame(Vector3(0.12, 1.5, 2.3), Transform3D(Basis(), Vector3(sx * (half_x + 0.12), 2.6, z)), 0.1, trim)
	for sx in [-1.0, 1.0]:
		_g.lamp(Transform3D(Basis(), Vector3(sx * (door_w * 0.5 + 0.5), 3.1, half_z + 0.25)))
	for i in 3:
		var at := Vector3(-half_x + 1.2 + float(i % 2) * 0.9, 0.4 + float(i / 2) * 0.8, half_z + 0.9)
		_g.box(Vector3(0.8, 0.8, 0.8), Transform3D(Basis(Vector3.UP, 0.2 * float(i)), at), Color(0.58, 0.44, 0.26))
		_g.frame(Vector3(0.8, 0.8, 0.8), Transform3D(Basis(Vector3.UP, 0.2 * float(i)), at), 0.06, Color(0.38, 0.27, 0.15))
	for ix in int(extents.x / 2.0):
		for iz in int(extents.z / 2.0):
			if (ix + iz) % 2 == 0:
				continue
			_g.block(Vector3(1.96, 0.01, 1.96), Vector3(-half_x + 1.0 + float(ix) * 2.0, 0.205, -half_z + 1.0 + float(iz) * 2.0), pal.tile)

func _slab(size: Vector3, pos: Vector3, color: Color, collide: bool) -> void:
	if collide:
		_collider(Transform3D(Basis(), pos), size)
	_g.block(size, pos, color)

func _slab_at(size: Vector3, xform: Transform3D, color: Color) -> void:
	_collider(xform, size)
	_g.box(size, xform, color)

func _collider(xform: Transform3D, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.MACHINE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.transform = xform
	body.add_child(cs)
	add_child(body)
