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
var terrain: Terrain
var tier: int = 0
var half_extent: float = 22.0
var placed: Array[Dictionary] = []      ## {def, cell, rot, node}
var occupied: Dictionary = {}           ## Vector2i -> index into `placed`

var _floor_body: StaticBody3D
var _floor_shape: CollisionShape3D
var _floor_mesh: MeshInstance3D
var _kerb_body: StaticBody3D
var _kerb_mesh: MeshInstance3D
var _floor_material: ShaderMaterial
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
	_floor_material = ShaderMaterial.new()
	_floor_material.shader = _pad_shader()
	_floor_mesh.material_override = _floor_material
	_floor_body.add_child(_floor_mesh)
	add_child(_floor_body)
	_kerb_mesh = MeshInstance3D.new()
	_kerb_mesh.name = "KerbMesh"
	var kerb_mat := StandardMaterial3D.new()
	kerb_mat.albedo_color = Color(0.46, 0.47, 0.43)
	kerb_mat.roughness = 0.9
	_kerb_mesh.material_override = kerb_mat
	add_child(_kerb_mesh)

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
	# The kerb is drawn lower than it collides, as a lip rather than a wall.
	var kerb := ArrayMesh.new()
	var st := SurfaceTool.new()
	for spec in offsets:
		var b := BoxMesh.new()
		b.size = Vector3(spec[1].x, 0.22, spec[1].z)
		st.append_from(b, 0, Transform3D(Basis(), Vector3(spec[0].x, 0.11, spec[0].z)))
	_kerb_mesh.mesh = st.commit(kerb)
	_floor_material.set_shader_parameter("half_extent", half_extent)
	if announce:
		expanded.emit(tier, half_extent)

## Build mode brings the grid up; the rest of the time it is a faint hint on
## the concrete.
func show_grid(on: bool) -> void:
	if _floor_material != null:
		_floor_material.set_shader_parameter("grid_strength", 0.42 if on else 0.10)

static var _shader_cache: Shader

## Concrete with the cell grid drawn on it (every metre, heavier every four) and
## a hazard stripe round the edge, so the plot reads as a build site and the
## grid a building will snap to is visible before you open build mode.
static func _pad_shader() -> Shader:
	if _shader_cache != null:
		return _shader_cache
	_shader_cache = Shader.new()
	_shader_cache.code = """
shader_type spatial;
render_mode cull_back;
uniform vec3 base : source_color = vec3(0.31, 0.33, 0.29);
uniform vec3 line : source_color = vec3(0.88, 0.90, 0.80);
uniform float grid_strength = 0.10;
uniform float half_extent = 22.0;
varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

float grid_line(vec2 p, float width) {
	vec2 g = abs(fract(p - 0.5) - 0.5) / max(fwidth(p), vec2(1e-4));
	return 1.0 - min(min(g.x, g.y) / width, 1.0);
}

void fragment() {
	vec3 c = base;
	if (local_normal.y > 0.5) {
		// A little unevenness in the concrete, in tiles.
		vec2 tile = floor(local_pos.xz / 4.0);
		float n = fract(sin(dot(tile, vec2(12.9898, 78.233))) * 43758.5453);
		c *= 0.94 + n * 0.08;
		float fine = grid_line(local_pos.xz, 1.0);
		float major = grid_line(local_pos.xz / 4.0, 1.6);
		c = mix(c, line, clamp(fine * grid_strength + major * grid_strength * 1.6, 0.0, 1.0));
		float edge = max(abs(local_pos.x), abs(local_pos.z));
		if (edge > half_extent - 0.7) {
			float stripe = step(0.5, fract((local_pos.x + local_pos.z) * 0.5));
			c = mix(vec3(0.10, 0.10, 0.09), vec3(0.92, 0.70, 0.18), stripe);
		}
	} else {
		c *= 0.7;
	}
	ALBEDO = c;
	ROUGHNESS = 0.93;
}
"""
	return _shader_cache

# --- Grid helpers ----------------------------------------------------------

func world_to_cell(world_pos: Vector3) -> Vector2i:
	var local := to_local(world_pos)
	return Vector2i(int(floor(local.x / CELL)), int(floor(local.z / CELL)))

func cell_to_world(cell: Vector2i, size: Vector3i, rot: Variant) -> Vector3:
	var fp := oriented_size(size, _as_rot(rot))
	return to_global(Vector3(
		(float(cell.x) + float(fp.x) * 0.5) * CELL,
		0.0,
		(float(cell.y) + float(fp.z) * 0.5) * CELL))

## A footprint after quarter turns about each axis. Rotation is in 90 degree
## steps per axis, so a rotated box still occupies whole cells and the
## occupancy grid stays exact.
static func oriented_size(size: Vector3i, rot: Vector3i) -> Vector3i:
	var out := size
	for i in posmod(rot.x, 4):
		out = Vector3i(out.x, out.z, out.y)
	for i in posmod(rot.y, 4):
		out = Vector3i(out.z, out.y, out.x)
	for i in posmod(rot.z, 4):
		out = Vector3i(out.y, out.x, out.z)
	return out

static func rotated_footprint(size: Vector3i, yaw: int) -> Vector3i:
	return oriented_size(size, Vector3i(0, yaw, 0))

## Callers may pass a bare yaw where a full orientation is wanted; a yaw is
## just a turn about Y.
static func _as_rot(rot: Variant) -> Vector3i:
	if rot is Vector3i:
		return rot
	return Vector3i(0, int(rot), 0)

## The visual orientation matching `oriented_size`.
static func orientation_basis(rot: Vector3i) -> Basis:
	return Basis.from_euler(Vector3(
		float(posmod(rot.x, 4)) * PI * 0.5,
		float(posmod(rot.y, 4)) * PI * 0.5,
		float(posmod(rot.z, 4)) * PI * 0.5))

func cells_for(cell: Vector2i, size: Vector3i, rot: Variant) -> Array[Vector2i]:
	var fp := oriented_size(size, _as_rot(rot))
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
func placement_error(def: BuildingDef, cell: Vector2i, rot: Variant, check_cost: bool = true) -> String:
	if def == null:
		return "unknown building"
	if check_cost and not Economy.can_afford(def.cost):
		return "need $%d" % def.cost
	for c in cells_for(cell, def.size, rot):
		if not in_bounds(c):
			return "outside plot"
		if occupied.has(c):
			return "space taken"
	return ""

func can_place(def: BuildingDef, cell: Vector2i, rot: Variant, check_cost: bool = true) -> bool:
	return placement_error(def, cell, rot, check_cost) == ""

# --- Placement -------------------------------------------------------------

func place(def: BuildingDef, cell: Vector2i, rot: Variant, charge: bool = true) -> Node3D:
	var orientation := _as_rot(rot)
	if not can_place(def, cell, orientation, charge):
		return null
	if charge and not Economy.try_spend(def.cost):
		return null
	var node := _instantiate(def)
	if node == null:
		return null
	node.position = to_local(cell_to_world(cell, def.size, orientation))
	node.basis = orientation_basis(orientation)
	add_child(node)
	# The models are primitives and a plot is a field of similar boxes, so
	# every building says what it is.
	Nameplate.attach(node, def.display_name, float(def.size.y) * CELL + 0.7)
	var record := {"def": def, "cell": cell, "rot": orientation, "node": node}
	placed.append(record)
	var index := placed.size() - 1
	for c in cells_for(cell, def.size, orientation):
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
			c.length = float(def.size.z) * CELL
			c.width = float(def.size.x) * CELL * 0.9
			c.speed = def.speed
			c.rise = def.rise
			c.railed = def.railed
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
			pad.terrain = terrain
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
		for c in cells_for(rec.cell, (rec.def as BuildingDef).size, rec.rot):
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
			"rot": [rec.rot.x, rec.rot.y, rec.rot.z],
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
		# Saves written before three-axis rotation carry a bare yaw.
		var orientation := Vector3i(0, int(entry.get("yaw", 0)), 0)
		if entry.has("rot"):
			var r: Array = entry["rot"]
			orientation = Vector3i(int(r[0]), int(r[1]), int(r[2]))
		var node := place(def, cell, orientation, false)
		if node != null and entry.has("state") and node.has_method("from_dict"):
			# Deferred: the node's _ready must run before its state is restored.
			node.call_deferred("from_dict", entry["state"])
	buildings_changed.emit(self)
