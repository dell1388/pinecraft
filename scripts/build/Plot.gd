class_name Plot
extends Node3D

## The player's buildable area: a grid of cells, the buildings on it, and the
## rules for placing, removing, saving and expanding them.

signal buildings_changed(plot: Plot)
signal vehicle_spawned(vehicle: Node3D)
signal expanded(tier: int, half_extent: float)

const CELL := 1.0

@export var plot_id: int = 0

var manager: LooseItemManager
## Where a pad parents the vehicle it spawns. A truck cannot be a child of the
## pad it came off, or it could never drive away from it.
var vehicle_host: Node3D
var tier: int = 0
var half_extent: float = 22.0
var placed: Array[Dictionary] = []      ## {def, cell, yaw, node}
var occupied: Dictionary = {}           ## Vector2i -> index into `placed`

var _floor_body: StaticBody3D
var _floor_shape: CollisionShape3D
var _floor_mesh: MeshInstance3D
var _kerb_body: StaticBody3D
var _wall_shapes: Array[CollisionShape3D] = []

func setup(p_manager: LooseItemManager, p_plot_id: int = 0) -> void:
	manager = p_manager
	plot_id = p_plot_id

func _ready() -> void:
	_apply_expansion(tier, false)

# --- Ground ----------------------------------------------------------------

func _ensure_floor() -> void:
	if _floor_body != null:
		return
	_floor_body = StaticBody3D.new()
	_floor_body.name = "PlotFloor"
	_floor_body.collision_layer = Layers.WORLD
	_floor_body.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	_floor_body.physics_material_override = pm
	_floor_shape = CollisionShape3D.new()
	_floor_shape.shape = BoxShape3D.new()
	_floor_body.add_child(_floor_shape)
	_floor_mesh = MeshInstance3D.new()
	_floor_mesh.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.27, 0.30, 0.24)
	_floor_mesh.material_override = mat
	_floor_body.add_child(_floor_mesh)
	add_child(_floor_body)

	# Kerbing sits on its own layer: loose items and cargo bounce off it, the
	# player and vehicles drive straight over.
	_kerb_body = StaticBody3D.new()
	_kerb_body.name = "PlotKerb"
	_kerb_body.collision_layer = Layers.KERB
	_kerb_body.collision_mask = 0
	for i in 4:
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		_kerb_body.add_child(cs)
		_wall_shapes.append(cs)
	add_child(_kerb_body)

func _apply_expansion(new_tier: int, announce: bool = true) -> void:
	var data := GameData.expansion(new_tier)
	tier = new_tier
	half_extent = float(data.get("half_extent", 22.0))
	if manager != null:
		manager.per_plot_cap = int(data.get("item_cap", Tuning.LOOSE_ITEMS_PER_PLOT))
	_ensure_floor()
	var size := half_extent * 2.0
	(_floor_shape.shape as BoxShape3D).size = Vector3(size, 1.0, size)
	_floor_shape.position = Vector3(0, -0.5, 0)
	(_floor_mesh.mesh as BoxMesh).size = Vector3(size, 1.0, size)
	_floor_mesh.position = _floor_shape.position
	# Low kerb walls: they stop items rolling off the plot without boxing the
	# player in, and they are four boxes rather than a mesh collider.
	var offsets := [
		[Vector3(0, 0.3, -half_extent), Vector3(size, 0.6, 0.4)],
		[Vector3(0, 0.3, half_extent), Vector3(size, 0.6, 0.4)],
		[Vector3(-half_extent, 0.3, 0), Vector3(0.4, 0.6, size)],
		[Vector3(half_extent, 0.3, 0), Vector3(0.4, 0.6, size)],
	]
	for i in _wall_shapes.size():
		(_wall_shapes[i].shape as BoxShape3D).size = offsets[i][1]
		_wall_shapes[i].position = offsets[i][0]
	if announce:
		expanded.emit(tier, half_extent)

# --- Grid helpers ----------------------------------------------------------

func world_to_cell(world_pos: Vector3) -> Vector2i:
	var local := to_local(world_pos)
	return Vector2i(int(floor(local.x / CELL)), int(floor(local.z / CELL)))

func cell_to_world(cell: Vector2i, size: Vector3i, yaw: int) -> Vector3:
	var fp := rotated_footprint(size, yaw)
	return to_global(Vector3(
		(float(cell.x) + float(fp.x) * 0.5) * CELL,
		0.0,
		(float(cell.y) + float(fp.z) * 0.5) * CELL))

static func rotated_footprint(size: Vector3i, yaw: int) -> Vector3i:
	if yaw % 2 == 1:
		return Vector3i(size.z, size.y, size.x)
	return size

func cells_for(cell: Vector2i, size: Vector3i, yaw: int) -> Array[Vector2i]:
	var fp := rotated_footprint(size, yaw)
	var out: Array[Vector2i] = []
	for x in fp.x:
		for z in fp.z:
			out.append(Vector2i(cell.x + x, cell.y + z))
	return out

func in_bounds(cell: Vector2i) -> bool:
	var x := float(cell.x) * CELL
	var z := float(cell.y) * CELL
	return absf(x) <= half_extent - CELL and absf(z) <= half_extent - CELL

## Returns "" when placement is legal, otherwise the reason it is not.
func placement_error(def: BuildingDef, cell: Vector2i, yaw: int, check_cost: bool = true) -> String:
	if def == null:
		return "unknown building"
	if check_cost and not Economy.can_afford(def.cost):
		return "need $%d" % def.cost
	for c in cells_for(cell, def.size, yaw):
		if not in_bounds(c):
			return "outside plot"
		if occupied.has(c):
			return "space taken"
	return ""

func can_place(def: BuildingDef, cell: Vector2i, yaw: int, check_cost: bool = true) -> bool:
	return placement_error(def, cell, yaw, check_cost) == ""

# --- Placement -------------------------------------------------------------

func place(def: BuildingDef, cell: Vector2i, yaw: int, charge: bool = true) -> Node3D:
	if not can_place(def, cell, yaw, charge):
		return null
	if charge and not Economy.try_spend(def.cost):
		return null
	var node := _instantiate(def)
	if node == null:
		return null
	node.position = to_local(cell_to_world(cell, def.size, yaw))
	node.rotation.y = float(yaw) * PI * 0.5
	add_child(node)
	var record := {"def": def, "cell": cell, "yaw": yaw, "node": node}
	placed.append(record)
	var index := placed.size() - 1
	for c in cells_for(cell, def.size, yaw):
		occupied[c] = index
	buildings_changed.emit(self)
	return node

func _instantiate(def: BuildingDef) -> Node3D:
	match def.kind:
		&"machine":
			var m := Machine.new()
			m.setup(manager, def, plot_id)
			return m
		&"conveyor":
			var c := Conveyor.new()
			c.mode = Conveyor.Mode.KINEMATIC
			c.length = float(def.size.z) * CELL
			c.width = float(def.size.x) * CELL * 0.9
			c.speed = def.speed
			c.sink_finder = find_sink_near
			return c
		&"splitter":
			var s := Splitter.new()
			s.setup(def)
			s.sink_finder = find_sink_near
			return s
		&"filter":
			var f := Filter.new()
			f.setup(def)
			f.sink_finder = find_sink_near
			return f
		&"storage":
			var b := StorageBin.new()
			b.setup(manager, def, plot_id)
			return b
		&"sell":
			var z := SellZone.new()
			z.setup(manager, def)
			return z
		&"schematic":
			var sc := Schematic.new()
			sc.setup(manager, def, plot_id)
			return sc
		&"pad":
			var pad := VehiclePad.new()
			pad.setup(manager, def, plot_id, vehicle_host if vehicle_host != null else self)
			pad.vehicle_spawned.connect(func(_p, v): vehicle_spawned.emit(v))
			return pad
	push_error("Plot: unknown building kind '%s'" % def.kind)
	return null

## Refunds half the cost, rounded down.
func remove(node: Node3D) -> bool:
	for i in placed.size():
		if placed[i].node != node:
			continue
		var def: BuildingDef = placed[i].def
		var schematic := node as Schematic
		if schematic != null:
			schematic.reclaim()
		var pad := node as VehiclePad
		if pad != null:
			pad.recall()
		Economy.add_money(def.cost / 2)
		placed.remove_at(i)
		node.queue_free()
		_reindex()
		buildings_changed.emit(self)
		return true
	return false

func remove_at_world(world_pos: Vector3) -> bool:
	var index: int = occupied.get(world_to_cell(world_pos), -1)
	if index < 0 or index >= placed.size():
		return false
	return remove(placed[index].node)

func _reindex() -> void:
	occupied.clear()
	for i in placed.size():
		var rec := placed[i]
		for c in cells_for(rec.cell, (rec.def as BuildingDef).size, rec.yaw):
			occupied[c] = i

func clear_buildings() -> void:
	for rec in placed:
		(rec.node as Node3D).queue_free()
	placed.clear()
	occupied.clear()
	buildings_changed.emit(self)

## The machine / bin / sell zone whose footprint contains (or nearly contains)
## a world point. Used by belts and splitters to hand items over directly.
func find_sink_near(world_pos: Vector3, radius: float = 1.2) -> Object:
	var cell := world_to_cell(world_pos)
	var span := int(ceil(radius / CELL))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var index: int = occupied.get(Vector2i(cell.x + dx, cell.y + dz), -1)
			if index < 0 or index >= placed.size():
				continue
			var node: Node3D = placed[index].node
			if node != null and node.has_method("accept_item"):
				return node
	return null

func pads() -> Array[VehiclePad]:
	var out: Array[VehiclePad] = []
	for rec in placed:
		var pad := rec.node as VehiclePad
		if pad != null:
			out.append(pad)
	return out

func machines() -> Array[Machine]:
	var out: Array[Machine] = []
	for rec in placed:
		var m := rec.node as Machine
		if m != null:
			out.append(m)
	return out

func building_count(kind: StringName = &"") -> int:
	if kind == &"":
		return placed.size()
	var n := 0
	for rec in placed:
		if (rec.def as BuildingDef).kind == kind:
			n += 1
	return n

# --- Expansion -------------------------------------------------------------

func next_expansion_cost() -> int:
	if tier >= GameData.max_expansion_tier():
		return -1
	return int(GameData.expansion(tier + 1).get("cost", 0))

func try_expand() -> bool:
	var cost := next_expansion_cost()
	if cost < 0 or not Economy.try_spend(cost):
		return false
	_apply_expansion(tier + 1)
	return true

# --- Persistence -----------------------------------------------------------

func to_dict() -> Dictionary:
	var items: Array = []
	for rec in placed:
		var entry := {
			"id": String((rec.def as BuildingDef).id),
			"cell": [rec.cell.x, rec.cell.y],
			"yaw": rec.yaw,
		}
		var node: Node3D = rec.node
		if node != null and node.has_method("to_dict"):
			entry["state"] = node.call("to_dict")
		items.append(entry)
	return {"tier": tier, "buildings": items}

func from_dict(d: Dictionary) -> void:
	clear_buildings()
	_apply_expansion(int(d.get("tier", 0)), false)
	for entry in d.get("buildings", []):
		var def := GameData.building(StringName(entry.get("id", "")))
		if def == null:
			push_warning("Plot: save references unknown building '%s'" % entry.get("id", ""))
			continue
		var cell_array: Array = entry.get("cell", [0, 0])
		var cell := Vector2i(int(cell_array[0]), int(cell_array[1]))
		var node := place(def, cell, int(entry.get("yaw", 0)), false)
		if node != null and entry.has("state") and node.has_method("from_dict"):
			# Deferred: the node's _ready must run before its state is restored.
			node.call_deferred("from_dict", entry["state"])
	buildings_changed.emit(self)
