class_name Terrain
extends StaticBody3D

## The land: one large, deliberately faceted heightfield.
##
## Height and biome come from two low-frequency fields, elevation and moisture,
## the way a real biome table works - so the map is procedural but legible, and
## the same seed gives the same country every time. Everything else is carved
## into that afterwards: build sites are flattened, rivers are cut down through
## it, and roads are graded across it.
##
## Nothing here is shaded smoothly. Each quad gets its own vertices and its own
## face normal, which is what makes the hills read as facets rather than as a
## blurry blanket, and it is also what the doc asks for.

const Workers := preload("res://scripts/core/Workers.gd")

## ICE and ASH only turn up on the maps that ask for them (the frozen lakes and
## the volcano's slopes on Ostars): nothing grows on ice, and ash is charred
## country.
enum Biome { WOODLAND, SWAMP, DESERT, MOUNTAIN, TAIGA, SNOW, ICE, ASH }

## Metres per quad. Bigger is coarser and cheaper; this is the knob for both.
const CELL := 6.0
## Anything below this is under water.
const WATER_LEVEL := 0.0
## How wide a road is graded, and how much faster it is to drive on.
## Half the carriageway. This has to be comfortably wider than a terrain cell,
## or the road is narrower than the grid that represents it and "flat across"
## stops meaning anything - which is what a 4.5 m half-width on a 6 m grid was.
const ROAD_HALF_WIDTH := 6.5
## Beyond the carriageway the grade blends back into whatever the land was
## doing, so a road does not sit on a plinth. It has to be generous: a short
## shoulder on steep ground is a cliff at the roadside, and because the heightfield
## is sampled between grid points, a sharp step just outside the carriageway
## bleeds back into it.
const ROAD_SHOULDER := 10.0
static var ROAD_SPEED_BONUS: float = Balance.num("vehicles.road_speed_bonus", 0.18)
## Bridges are faster still: the road's bonus and this much more.
static var BRIDGE_SPEED_BONUS: float = ROAD_SPEED_BONUS + Balance.num("vehicles.bridge_extra_bonus", 0.10)
## The steepest a road is graded, as rise over run.
const MAX_GRADE := 0.12
## How far under the road's level the land under the carriageway is laid.
const ROAD_SINK := 0.2

@export var half_extent: float = 300.0
@export var noise_seed: int = 20260921

## Flat pads that must stay flat, whatever the land wants to do: {centre, radius}
var build_sites: Array[Dictionary] = []
## River centre-lines, as arrays of Vector3. Carved down through the land.
var rivers: Array = []
## Road centre-lines, as arrays of Vector3. Graded flat and marked. A road can
## also be a dictionary {path, bridge, ford}: a bridged road leaves the water
## alone and asks for a bridge over every wet stretch (see `bridges`); a ford
## road builds its bed up to wading depth instead - a causeway.
var roads: Array = []
## Where the bridged roads cross water: {a, b} deck ends on the graded road,
## filled in by `generate` for the world to build decks on.
var bridges: Array[Dictionary] = []
## The land, when it is more than one island: {centre (Vector2), radius, cold,
## wet, lift}. The biases nudge each island's climate - a colder north island,
## a drier desert one. Empty means the old single square island.
var islands: Array[Dictionary] = []
## Hand-made places carved into the land: {name, kind ("valley" or "crater"),
## centre (Vector2), radius, gap (angle of a valley's one way in)}.
var features: Array[Dictionary] = []
## Found sites that want a road to them: names from `site_requests`.
var spur_sites: Array = []
## Short drives from the nearest road to a fixed place's way in:
## {name, centre, radius, door (a point, or null for the edge nearest the road)}.
var driveways: Array = []
## Where each spur and driveway ends, by name: the way in to the place. A
## place turns its front toward it.
var road_ends: Dictionary = {}
## Big consolidated biome regions: {name, centre (Vector2), biome, scale}. A
## point belongs to the nearest centre (measured through a slow warp, so the
## borders wander), and each biome has its own shape of land - rolling woods,
## dunes and mesas, a range of peaks. Empty means the old noise-picked biomes.
var regions: Array[Dictionary] = []
## Where a found or routed road got to, for drawing its surface: {path,
## style}. Filled by `generate`.
var road_paths: Array[Dictionary] = []
## While generating: the cells under each graded carriageway proper (the mask
## also covers a cell beyond it).
var _road_core := PackedByteArray()
## When set, the whole generated country is written here and read back next
## time the same country is asked for, which skips all of generation bar the
## meshing.
var cache_path: String = ""
## Bumped whenever generation changes, so an old cache is not trusted.
const GENERATOR_VERSION := 27

var _cells: int = 0
var _heights: PackedFloat32Array = PackedFloat32Array()
var _biomes: PackedByteArray = PackedByteArray()
var _road_mask: PackedByteArray = PackedByteArray()
## Cells left out of the ground altogether, where a cave's shaft goes down.
var _holes: PackedByteArray = PackedByteArray()

## How many caves to look for. Zero, the default, looks for none, so a test
## terrain is exactly the ground it asks for.
@export var cave_count: int = 0
## Where the caves are wanted, when it matters which island they are on:
## {centre (Vector2), radius, count}. Each zone gets its own count of the best
## mouths inside it. Empty means the best `cave_count` anywhere.
var cave_zones: Array[Dictionary] = []
## Where the caves went: {entrance, dir, ground, name}. Filled by `generate`.
var caves: Array[Dictionary] = []
## Places the world wants put somewhere suitable rather than at fixed spots:
## {name, biomes, radius, near, far}. Each is given a reasonably flat patch of
## its own country, levelled like any build site. Results go in `found_sites`.
var site_requests: Array[Dictionary] = []
var found_sites: Dictionary = {}

var _coast := FastNoiseLite.new()
var _elevation := FastNoiseLite.new()
var _moisture := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _mesa := FastNoiseLite.new()
## Where the land comes down to the sea: the lowest ground above the water.
const SHORE_BASE := 1.5
## The land as welded plates (the region map), once built.
var facets: Facets
## A hand-drawn country instead of the islands and regions: an object with
## `sample(x, z) -> [biome, height]` (called from worker threads, so it only
## reads) and `key() -> String` (for the map cache). Rivers, features, caves
## and everything after the heights work on it the same as ever.
var shaper: Object = null

## Drawn as welded plates with the toon colours (the region map, or a shaped one).
func _plated() -> bool:
	return not regions.is_empty() or shaper != null

## Open water all round, out past the edge of the map.
func _open_sea() -> bool:
	return not islands.is_empty() or shaper != null

## Flat ground, per biome: the tops of the terraces.
const BIOME_COLORS := {
	Biome.WOODLAND: Color(0.34, 0.56, 0.23),
	Biome.SWAMP: Color(0.30, 0.40, 0.21),
	Biome.DESERT: Color(0.88, 0.75, 0.47),
	Biome.MOUNTAIN: Color(0.47, 0.47, 0.45),
	Biome.TAIGA: Color(0.26, 0.44, 0.31),
	Biome.SNOW: Color(0.88, 0.91, 0.96),
	Biome.ICE: Color(0.70, 0.86, 0.96),
	Biome.ASH: Color(0.24, 0.22, 0.23),
}
## Steep ground, per biome: the risers between terraces, and cliffs.
const CLIFF_COLORS := {
	Biome.WOODLAND: Color(0.47, 0.41, 0.33),
	Biome.SWAMP: Color(0.33, 0.30, 0.23),
	Biome.DESERT: Color(0.80, 0.50, 0.30),
	Biome.MOUNTAIN: Color(0.42, 0.42, 0.45),
	Biome.TAIGA: Color(0.41, 0.40, 0.37),
	Biome.SNOW: Color(0.60, 0.65, 0.74),
	Biome.ICE: Color(0.56, 0.70, 0.82),
	Biome.ASH: Color(0.30, 0.20, 0.18),
}
## Faces steeper than this (the normal's vertical part) are drawn as rock.
const CLIFF_NORMAL_Y := 0.82
const ROAD_COLOR := Color(0.37, 0.34, 0.31)
const SHORE_COLOR := Color(0.82, 0.76, 0.54)
const BED_COLOR := Color(0.28, 0.26, 0.21)

## The land steps rather than rolls: heights are banded into terraces of this
## many metres, flat on top with a short steep riser between. Big flat panels
## and sharp edges, which is the look, and ground you can read at a glance -
## a riser is a step up, a cliff is a cliff. The swamp is left unbanded, as
## wet ground should be.
const TERRACE_STEP := {
	Biome.WOODLAND: 2.0,
	Biome.SWAMP: 0.0,
	Biome.DESERT: 3.0,
	Biome.MOUNTAIN: 4.0,
	Biome.TAIGA: 2.5,
	Biome.SNOW: 3.5,
	Biome.ICE: 0.0,
	Biome.ASH: 3.0,
}
## Where in each band the riser starts. Higher is flatter tops and steeper risers.
const TERRACE_EDGE := 0.74
## How far in from the edge of the map the land starts to fall to the sea.
const SHORE_WIDTH := 48.0

## Base height and how much relief each biome gets.
const BIOME_HEIGHT := {
	Biome.WOODLAND: [2.0, 7.0],
	Biome.SWAMP: [-0.6, 1.6],
	Biome.DESERT: [1.4, 5.0],
	Biome.MOUNTAIN: [14.0, 34.0],
	Biome.TAIGA: [3.5, 10.0],
	Biome.SNOW: [10.0, 22.0],
	Biome.ICE: [4.0, 0.0],
	Biome.ASH: [14.0, 30.0],
}

func _ready() -> void:
	collision_layer = Layers.WORLD
	collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	physics_material_override = pm
	_configure_noise()
	await generate()
	generated = true
	finished_generating.emit()

## Loading behind the boot screen, the world sets this: it is told what the
## land is doing between each step, and given a frame to show it. Awaited.
var loading_hook: Callable
var generated: bool = false
signal finished_generating()

## Between two steps of generation: says what comes next. Off the boot
## screen this returns at once and generation runs straight through.
func _pause(what: String) -> void:
	if loading_hook.is_valid():
		await loading_hook.call(what)

## Behind the boot screen, the tree: the big jobs on the worker threads let
## frames go by while they work, so the screen keeps drawing (see Workers).
## Otherwise null, and they are simply waited for.
func _loading_tree() -> SceneTree:
	return get_tree() if loading_hook.is_valid() and is_inside_tree() else null

func _road_km() -> float:
	var metres := 0.0
	for rp in road_paths:
		var path: Array = rp.path
		for i in range(1, path.size()):
			metres += Vector2((path[i] as Vector3).x - (path[i - 1] as Vector3).x,
				(path[i] as Vector3).z - (path[i - 1] as Vector3).z).length()
	return metres / 1000.0

func _configure_noise() -> void:
	_elevation.seed = noise_seed
	_elevation.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_elevation.frequency = 0.0022
	_elevation.fractal_octaves = 4

	_moisture.seed = noise_seed + 977
	_moisture.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_moisture.frequency = 0.0031
	_moisture.fractal_octaves = 3

	_coast.seed = noise_seed + 313
	_coast.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_coast.frequency = 0.0045
	_coast.fractal_octaves = 3

	_hills.seed = noise_seed + 71
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_hills.frequency = 0.0017
	_hills.fractal_octaves = 5

	_ridge.seed = noise_seed + 191
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.frequency = 0.0014
	_ridge.fractal_octaves = 5

	_warp.seed = noise_seed + 404
	_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_warp.frequency = 0.0009
	_warp.fractal_octaves = 2

	_mesa.seed = noise_seed + 808
	_mesa.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_mesa.frequency = 0.004
	_mesa.fractal_octaves = 2

	_detail.seed = noise_seed + 5501
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_detail.frequency = 0.021
	_detail.fractal_octaves = 2

# --- Queries ---------------------------------------------------------------

func _index(ix: int, iz: int) -> int:
	return clampi(iz, 0, _cells) * (_cells + 1) + clampi(ix, 0, _cells)

func _grid_coord(v: float) -> float:
	return (v + half_extent) / CELL

## Ground height under a world position, interpolated across the quad.
func height_at(x: float, z: float) -> float:
	# On the region map the ground is the plates, which follow the grid
	# closely but not exactly: what stands on the land stands on them.
	if facets != null:
		var y := facets.height(x, z)
		if not is_nan(y):
			return y
	return grid_height(x, z)

## The height grid itself, interpolated on the two triangles of each cell.
func grid_height(x: float, z: float) -> float:
	if _heights.is_empty():
		return 0.0
	var gx := _grid_coord(x)
	var gz := _grid_coord(z)
	var ix := int(floor(gx))
	var iz := int(floor(gz))
	var fx := gx - float(ix)
	var fz := gz - float(iz)
	var h00 := _heights[_index(ix, iz)]
	var h10 := _heights[_index(ix + 1, iz)]
	var h01 := _heights[_index(ix, iz + 1)]
	var h11 := _heights[_index(ix + 1, iz + 1)]
	if fx >= fz:
		return h00 + (h10 - h00) * fx + (h11 - h10) * fz
	return h00 + (h01 - h00) * fz + (h11 - h01) * fx

## Whether a point is over a hole in the ground (a cave mouth).
func _is_hole(x: float, z: float) -> bool:
	if _holes.is_empty():
		return false
	var ix := int(floor(_grid_coord(x)))
	var iz := int(floor(_grid_coord(z)))
	if ix < 0 or iz < 0 or ix >= _cells or iz >= _cells:
		return false
	return _holes[iz * _cells + ix] != 0

## Whether any cell touching a grid point is a hole.
func _hole_near(ix: int, iz: int) -> bool:
	if _holes.is_empty():
		return false
	for dz in [-1, 0]:
		for dx in [-1, 0]:
			var cx: int = ix + dx
			var cz: int = iz + dz
			if cx >= 0 and cz >= 0 and cx < _cells and cz < _cells and _holes[cz * _cells + cx] != 0:
				return true
	return false

## The ground at a point, in one look: [height (NAN over a hole), colour].
func ground_sample(x: float, z: float) -> Array:
	if facets != null:
		var hit := facets.plate_at(x, z)
		if not hit.is_empty():
			return hit
	var h := height_at(x, z)
	return [h, BIOME_COLORS.get(biome_at(x, z), Color(0.34, 0.56, 0.23))]

## The colour the ground is drawn at a point: its plate's, on the region
## maps; otherwise its biome's grass.
func ground_color(x: float, z: float) -> Color:
	if facets != null:
		var c := facets.color_at(x, z)
		if c.a > 0.0:
			return c
	return BIOME_COLORS.get(biome_at(x, z), Color(0.34, 0.56, 0.23))

func height_at_point(point: Vector3) -> float:
	return height_at(point.x, point.z)

func biome_at(x: float, z: float) -> Biome:
	if _biomes.is_empty():
		return Biome.WOODLAND
	return _biomes[_index(int(round(_grid_coord(x))), int(round(_grid_coord(z))))] as Biome

## How much of the map each biome covers, as a share of its cells. Printed by
## the smoke run, because a biome that covers almost nothing is a biome whose
## trees effectively do not exist.
func biome_mix() -> Dictionary:
	var counts: Dictionary = {}
	if _biomes.is_empty():
		return counts
	for value in _biomes:
		counts[value] = int(counts.get(value, 0)) + 1
	var mix: Dictionary = {}
	for value in counts:
		mix[biome_name(value as Biome)] = float(counts[value]) / float(_biomes.size())
	return mix

func biome_name(biome: Biome) -> String:
	return ["woodland", "swamp", "desert", "mountains", "taiga", "snowland", "ice", "ash"][int(biome)]

## How deep the water is over a point. Zero on dry land.
func water_depth(x: float, z: float) -> float:
	return maxf(0.0, WATER_LEVEL - height_at(x, z))

## Spec: roads give a slight speed increase when driven on.
func is_road(x: float, z: float) -> bool:
	if not clear_zones.is_empty() and in_clear_zone(x, z):
		return false
	if _road_mask.is_empty():
		return false
	return _road_mask[_index(int(round(_grid_coord(x))), int(round(_grid_coord(z))))] != 0

## Every grid point standing in one of `biomes`: dry, off the roads and clear of
## the levelled build sites. This is how a species finds its own country instead
## of being scattered round a ring drawn about the origin.
## `max_water` lets a species stand in shallow water - a willow in a swamp is
## not on dry land, and excluding wet ground made the swamp's tree effectively
## extinct.
func points_in_biomes(wanted: Array, step: int = 2, max_water: float = 0.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _heights.is_empty():
		return out
	for iz in range(1, _cells, maxi(1, step)):
		for ix in range(1, _cells, maxi(1, step)):
			var index := _index(ix, iz)
			if not wanted.has(int(_biomes[index])):
				continue
			if _road_mask[index] != 0:
				continue
			if _heights[index] <= WATER_LEVEL - max_water:
				continue
			var x := -half_extent + float(ix) * CELL
			var z := -half_extent + float(iz) * CELL
			if _in_build_site(x, z) or _in_crater(x, z) or is_blocked(x, z):
				continue
			# Not on a crag too steep to stand on.
			if absf(_heights[_index(ix + 1, iz)] - _heights[_index(ix - 1, iz)]) > CELL * 2.2 \
					or absf(_heights[_index(ix, iz + 1)] - _heights[_index(ix, iz - 1)]) > CELL * 2.2:
				continue
			out.append(Vector3(x, height_at(x, z), z))
	return out

## Where something stands: the ground.
func surface_at(x: float, z: float) -> float:
	return height_at(x, z)

## Ground under a rock outcrop, on a coarse grid: nothing grows there.
var _blocked: Dictionary = {}
const BLOCK_GRID := 8.0

## Nothing grows on a bridge or up through its deck: the ground along each one,
## ends and all, is kept clear.
func _block_bridges() -> void:
	for b in bridges:
		var a: Vector3 = b.a
		var e: Vector3 = b.b
		var run := Vector2(e.x - a.x, e.z - a.z).length()
		var n := maxi(1, int(run / 4.0))
		for k in n + 1:
			mark_blocked(a.lerp(e, float(k) / float(n)), 10.0)

func mark_blocked(centre: Vector3, radius: float) -> void:
	var r := int(ceil(radius / BLOCK_GRID))
	var c := Vector2i(int(floor(centre.x / BLOCK_GRID)), int(floor(centre.z / BLOCK_GRID)))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if Vector2(dx, dz).length() * BLOCK_GRID <= radius + BLOCK_GRID * 0.5:
				_blocked[Vector2i(c.x + dx, c.y + dz)] = true

func is_blocked(x: float, z: float) -> bool:
	return _blocked.has(Vector2i(int(floor(x / BLOCK_GRID)), int(floor(z / BLOCK_GRID))))

## Is grid point `index` on a levelled place (inside its radius)?
func _on_site(index: int) -> bool:
	var x := -half_extent + float(index % (_cells + 1)) * CELL
	var z := -half_extent + float(index / (_cells + 1)) * CELL
	for site in build_sites:
		var c: Vector3 = site.centre
		if not is_nan(c.y) and Vector2(x - c.x, z - c.z).length() < float(site.radius):
			return true
	return false

## Build sites are kept clear, so an expanded plot never swallows a forest and
## nothing grows through the middle of the yard.
func _in_build_site(x: float, z: float) -> bool:
	for site in build_sites:
		var centre: Vector3 = site.centre
		if Vector2(x - centre.x, z - centre.z).length() <= float(site.radius) * 1.25:
			return true
	return false

## Drops a point onto the ground, which is how anything gets placed out here.
func place(point: Vector3, lift: float = 0.0) -> Vector3:
	return Vector3(point.x, surface_at(point.x, point.z) + lift, point.z)

func reserve_site(centre: Vector3, radius: float) -> void:
	build_sites.append({"centre": centre, "radius": radius})

## Squares kept flat, clear and road-free under something built on them - the
## player's plot, at its biggest: the land is levelled a hand's width under
## `height` across the whole square (so it never pokes up through the pad),
## eased back to the country round it over `margin`, and no road is laid
## across it. {centre, half, height, margin}
var clear_zones: Array[Dictionary] = []

func reserve_clear_square(centre: Vector3, half: float, height: float, margin: float = 12.0) -> void:
	clear_zones.append({"centre": centre, "half": half, "height": height, "margin": margin})

## Inside a clear square (plus `pad` metres round it)?
func in_clear_zone(x: float, z: float, pad: float = 0.0) -> bool:
	for zone in clear_zones:
		var c: Vector3 = zone.centre
		var h := float(zone.half) + pad
		if absf(x - c.x) <= h and absf(z - c.z) <= h:
			return true
	return false

func _flatten_clear_zones() -> void:
	for zone in clear_zones:
		var c: Vector3 = zone.centre
		var half := float(zone.half)
		var margin := float(zone.margin)
		var reach := half + margin
		for iz in range(maxi(0, int(floor(_grid_coord(c.z - reach)))), mini(_cells, int(ceil(_grid_coord(c.z + reach)))) + 1):
			for ix in range(maxi(0, int(floor(_grid_coord(c.x - reach)))), mini(_cells, int(ceil(_grid_coord(c.x + reach)))) + 1):
				var x := -half_extent + float(ix) * CELL
				var z := -half_extent + float(iz) * CELL
				# Distance out from the square's edge (0 inside it).
				var out := maxf(absf(x - c.x) - half, absf(z - c.z) - half)
				if out > margin:
					continue
				var index := _index(ix, iz)
				if out <= CELL:
					# The square and one grid step past it: level, and a
					# little under the pad, so no facet reaches up through it.
					_heights[index] = float(zone.height)
					_road_mask[index] = 0
				elif _road_mask[index] == 0:
					# Easing back to the land, but never under a road: the
					# road was graded already, and its surface is laid to that.
					var t: float = clampf((out - CELL) / maxf(0.01, margin - CELL), 0.0, 1.0)
					_heights[index] = lerpf(float(zone.height), _heights[index], smoothstep(0.0, 1.0, t))

# --- Generation ------------------------------------------------------------

func generate() -> void:
	_lap_ms = Time.get_ticks_msec()
	_key_at_start = _cache_key()
	_cells = int(round(half_extent * 2.0 / CELL))
	var verts := (_cells + 1) * (_cells + 1)
	_heights.resize(verts)
	_biomes.resize(verts)
	_road_mask.resize(verts)

	await _pause("Measuring out %.1f km of land: %d x %d cells of %.0f m" % [half_extent * 2.0 / 1000.0, _cells, _cells, CELL])
	if _load_cache():
		await _pause("Read the land from the map cache (%d roads, %d bridges, %d caves) - no need to build it again" % [
			road_paths.size(), bridges.size(), caves.size()])
	else:
		await _pause("No map cache yet: shaping the hills, valleys and coasts, %s height points - the slow part, done once" % UIKit.money((_cells + 1) * (_cells + 1)).replace("$", ""))
		await _fill_heights()
		_lap("heights")
		await _pause("Cutting %d rivers to the sea, with their fords" % rivers.size())
		_holes.resize(_cells * _cells)
		_holes.fill(0)
		bridges.clear()
		road_paths.clear()
		road_ends.clear()
		_road_core.resize(_road_mask.size())
		_road_core.fill(0)
		_carve_rivers()
		await _pause("Levelling %d build sites" % build_sites.size())
		_level_sites()
		await _pause("Surveying %d roads over the hills, round the lakes and across the rivers" % roads.size())
		_route_roads()
		_lap("routing")
		await _pause("Grading %.1f km of road, with %d bridges" % [_road_km(), bridges.size()])
		# The plot's square is levelled before the roads are graded as well as
		# after, so a road running up to it comes down to its level instead of
		# ending in mid-air at its edge.
		_flatten_clear_zones()
		# The places asked for up front are levelled before the roads are
		# graded, so a road running past or up to one is laid over it as it
		# will be, and levelling it afterwards never digs under a road.
		_flatten_sites()
		_grade_roads(roads)
		_lap("rivers+roads")
		await _pause("Finding places for %d outposts, camps and lookouts, and roads out to them" % site_requests.size())
		_place_requested_sites()
		_grade_roads(_spur_roads())
		_lap("sites")
		await _pause("Looking for hillsides with rock enough over them for cave mouths")
		_plan_caves()
		_lap("caves")
		await _pause("Found %d cave mouths; cutting their ways in" % caves.size())
		_flatten_sites()
		_flatten_clear_zones()
		_cut_cave_holes()
		await _pause("Saving the map cache, so next time is quicker")
		_save_cache()
	_block_bridges()
	await _pause("Building the ground mesh and its collision (%d chunks)" % int(pow(ceil(float(_cells) / float(CHUNK)), 2.0)))
	await _build_mesh()
	_lap("mesh")
	await _pause("Working out what hides what, so hidden land is not drawn")
	_build_occluders()
	_lap("occluders")

## A row of samples, filled on a worker thread.
class RowBuf:
	var heights := PackedFloat32Array()
	var biomes := PackedByteArray()

## Every grid point's height and biome, a row per task across the worker
## threads: on a big map this is the bulk of generation.
func _fill_heights() -> void:
	var rows := _cells + 1
	var bufs: Array = []
	for i in rows:
		bufs.append(RowBuf.new())
	await Workers.group(_fill_row.bind(bufs), rows, "terrain rows", _loading_tree())
	_heights = PackedFloat32Array()
	_biomes = PackedByteArray()
	for buf: RowBuf in bufs:
		_heights.append_array(buf.heights)
		_biomes.append_array(buf.biomes)

func _fill_row(iz: int, bufs: Array) -> void:
	var buf: RowBuf = bufs[iz]
	buf.heights.resize(_cells + 1)
	buf.biomes.resize(_cells + 1)
	var z := -half_extent + float(iz) * CELL
	for ix in _cells + 1:
		var sample := _sample(-half_extent + float(ix) * CELL, z)
		buf.biomes[ix] = int(sample[0])
		buf.heights[ix] = float(sample[1])

# --- Cache -------------------------------------------------------------------

func _cache_key() -> String:
	var config := [GENERATOR_VERSION, half_extent, noise_seed, islands, regions, features, rivers,
		roads, build_sites, site_requests, spur_sites, driveways, cave_count, clear_zones]
	# A shaped country has its own key (and the islands' key is left as it was).
	if shaper != null:
		config.append(String(shaper.call("key")))
	return str(hash(var_to_str(config)))

func _load_cache() -> bool:
	if cache_path == "" or not FileAccess.file_exists(cache_path):
		return false
	var f := FileAccess.open(cache_path, FileAccess.READ)
	if f == null:
		return false
	var data: Variant = f.get_var()
	if not (data is Dictionary) or String(data.get("key", "")) != _key_at_start:
		return false
	_heights = data.heights
	_biomes = data.biomes
	_road_mask = data.road_mask
	_holes = data.holes
	bridges.assign(data.bridges)
	caves.assign(data.caves)
	found_sites = data.found_sites
	road_paths.assign(data.road_paths)
	build_sites.assign(data.build_sites)
	roads = data.roads
	road_ends = data.get("road_ends", {})
	return _heights.size() == (_cells + 1) * (_cells + 1)

func _save_cache() -> void:
	if cache_path == "":
		return
	# The key is taken from the config as it was asked for, before generation
	# added the found sites and routed roads to it.
	var f := FileAccess.open(cache_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_var({"key": _key_at_start, "heights": _heights, "biomes": _biomes,
		"road_mask": _road_mask, "holes": _holes, "bridges": bridges, "caves": caves,
		"found_sites": found_sites, "road_paths": road_paths, "build_sites": build_sites,
		"roads": roads, "road_ends": road_ends})

var _key_at_start: String = ""

## What this land was made from, as the map cache knows it: the same key, the
## same land.
func cache_key() -> String:
	return _key_at_start

var _lap_ms: int = 0

func _lap(what: String) -> void:
	var now := Time.get_ticks_msec()
	if OS.has_environment("PROFILE_LOAD") and _lap_ms > 0:
		print("  terrain: %-14s %5d ms" % [what, now - _lap_ms])
	_lap_ms = now

## Biome and height at a point, from one read of the noise.
func _sample(x: float, z: float) -> Array:
	if shaper != null:
		var shaped: Array = shaper.call("sample", x, z)
		var feature := _feature_at(x, z)
		if feature.size() > 0:
			# A crater's rock is its bowl and rim; past that, the country round it.
			var fb: int = feature[1] if not _crater_near(x, z) or _crater_bowl(x, z) else shaped[0]
			shaped = [fb, lerpf(float(shaped[1]), float(feature[2]), float(feature[0]))]
		return shaped
	if not regions.is_empty():
		return _sample_regions(x, z)
	var isle := _island_at(x, z)
	if isle.x <= 0.0:
		return [Biome.WOODLAND, -7.0]          # open sea: nothing to work out
	var e := (_elevation.get_noise_2d(x, z) + 1.0) * 0.5 + isle.w
	var m := (_moisture.get_noise_2d(x, z) + 1.0) * 0.5 + isle.z
	var biome := _biome_from(e, m, z, isle.y)
	var feature := _feature_at(x, z)
	if feature.size() > 0:
		biome = feature[1]
	var h := _height_from(e, m, x, z, isle.x)
	if feature.size() > 0:
		h = lerpf(h, float(feature[2]), float(feature[0]))
	return [biome, terrace(h, float(TERRACE_STEP[biome]))]

## How far apart two regions' land blends, metres.
const REGION_BLEND := 160.0
## Mountains above this are snow-capped.
const SNOWLINE := 95.0

## The region map: whichever region centre is nearest (through the warp) owns
## the point, and the land blends into its neighbour's near the border.
func _sample_regions(x: float, z: float) -> Array:
	var isle := _island_at(x, z)
	if isle.x <= 0.0:
		return [Biome.WOODLAND, SEA_FLOOR]
	var wx := x + _warp.get_noise_2d(x, z) * 240.0
	var wz := z + _warp.get_noise_2d(x + 7000.0, z - 3000.0) * 240.0
	var d1 := INF
	var d2 := INF
	var r1 := 0
	var r2 := -1
	for i in regions.size():
		var reg: Dictionary = regions[i]
		var d := Vector2(wx, wz).distance_to(reg.centre) * float(reg.get("scale", 1.0))
		if d < d1:
			d2 = d1
			r2 = r1
			d1 = d
			r1 = i
		elif d < d2:
			d2 = d
			r2 = i
	var biome: Biome = regions[r1].biome
	var h := _biome_height(biome, x, z)
	if r2 >= 0 and r2 != r1 and d2 - d1 < REGION_BLEND:
		var other: Biome = regions[r2].biome
		if other != biome:
			var t := 0.5 + 0.5 * smoothstep(0.0, 1.0, (d2 - d1) / REGION_BLEND)
			h = lerpf(_biome_height(other, x, z), h, t)
	# Down to the beach and the sea bed round every island.
	var coast := smoothstep(0.0, 1.0, isle.x)
	h = lerpf(SEA_FLOOR, h, coast)
	var to_edge := half_extent - maxf(absf(x), absf(z))
	h = lerpf(SEA_FLOOR, h, smoothstep(4.0, SHORE_WIDTH, to_edge))
	if biome == Biome.MOUNTAIN and h > SNOWLINE:
		biome = Biome.SNOW
	h = _basins(x, z, h)
	var feature := _feature_at(x, z)
	if feature.size() > 0:
		biome = feature[1]
		h = lerpf(h, float(feature[2]), float(feature[0]))
	return [biome, h]

## A basin draws the land down toward the water line: the sheltered valley
## home sits in, low enough for the rivers, the yard and the store.
func _basins(x: float, z: float, h: float) -> float:
	for f in features:
		if String(f.kind) != "basin":
			continue
		var d := Vector2(x, z).distance_to(f.centre) / float(f.radius)
		var w := 1.0 - smoothstep(0.55, 1.35, d)
		if w > 0.0:
			h = lerpf(h, SHORE_BASE + 1.2 + maxf(0.0, h - 8.0) * 0.12, w)
	return h

## The shape of each kind of country. Every one has real relief - the woods
## roll, the desert has dunes and flat-topped mesas, the taiga climbs - and the
## mountains are a range of ridged peaks well over two hundred metres high.
func _biome_height(biome: Biome, x: float, z: float) -> float:
	var e := _hills.get_noise_2d(x, z) * 0.5 + 0.5
	var d := _detail.get_noise_2d(x, z)
	match biome:
		Biome.WOODLAND:
			# Rolling country: a few shelves up and down, knolls on them.
			var knoll := _mesa.get_noise_2d(x * 0.9, z * 0.9)
			return 4.0 + 40.0 * e + 12.0 * knoll + 1.5 * d
		Biome.TAIGA:
			var r := _ridge.get_noise_2d(x, z) * 0.5 + 0.5
			var knoll2 := _mesa.get_noise_2d(x * 0.9 + 900.0, z * 0.9)
			return 8.0 + 44.0 * e + 30.0 * r * r + 9.0 * knoll2 + 1.5 * d
		Biome.SWAMP:
			var wet := smoothstep(0.55, 0.78, _moisture.get_noise_2d(x, z) * 0.5 + 0.5)
			return 2.2 + 7.0 * e - 3.4 * wet + 0.5 * d
		Biome.DESERT:
			# A broad floor with flat-topped mesas stood up out of it.
			var mesa := smoothstep(0.3, 0.62, _mesa.get_noise_2d(x * 1.3, z * 1.3) * 0.5 + 0.5)
			var dune := sin((x * 0.8 + z * 0.35) * 0.02 + d * 1.5) * 0.5 + 0.5
			return 4.0 + 14.0 * e + 3.0 * dune + 30.0 * mesa * (0.6 + 0.6 * e)
		Biome.MOUNTAIN:
			var r2 := _ridge.get_noise_2d(x, z) * 0.5 + 0.5
			return 16.0 + 50.0 * e + 85.0 * pow(r2, 2.0) + 2.0 * d
		Biome.SNOW:
			var r3 := _ridge.get_noise_2d(x * 1.2, z * 1.2) * 0.5 + 0.5
			return 14.0 + 36.0 * e + 54.0 * pow(r3, 2.0) + 2.0 * d
	return 6.0 + 20.0 * e

## How much a point is land (x, 0..1), and the climate nudges of the island it
## is on: y cold, z wet, w lift. With no islands everywhere is land.
func _island_at(x: float, z: float) -> Vector4:
	if islands.is_empty():
		return Vector4(1.0, 0.0, 0.0, 0.0)
	var best := 0.0
	var total := 0.0
	var bias := Vector3.ZERO
	var wobble := _coast.get_noise_2d(x, z) * 55.0
	for isle in islands:
		var c: Vector2 = isle.centre
		var r: float = float(isle.radius)
		var d := (Vector2(x, z).distance_to(c) + wobble) / r
		var f := 1.0 - smoothstep(0.78, 1.0, d)
		if f <= 0.0:
			continue
		best = maxf(best, f)
		total += f
		bias += Vector3(float(isle.get("cold", 0.0)), float(isle.get("wet", 0.0)),
			float(isle.get("lift", 0.0))) * f
	if total > 0.0:
		bias /= total
	return Vector4(best, bias.x, bias.y, bias.z)

## Spec's biome list, chosen from elevation and moisture rather than from
## hand-drawn regions.
func _pick_biome(x: float, z: float) -> Biome:
	return _sample(x, z)[0]

func _biome_from(e: float, m: float, z: float, cold_bias: float) -> Biome:
	# A north-south temperature gradient, so the cold biomes sit together
	# instead of being sprinkled over the whole map.
	var cold: float = clampf(0.5 - z / (half_extent * 2.0), 0.0, 1.0) + (e - 0.5) * 0.6 + cold_bias
	if e > 0.78:
		return Biome.SNOW if cold > 0.62 else Biome.MOUNTAIN
	if e > 0.64:
		return Biome.MOUNTAIN
	if cold > 0.66:
		return Biome.SNOW if cold > 0.80 else Biome.TAIGA
	if m < 0.34:
		return Biome.DESERT
	if m > 0.70 and e < 0.42:
		return Biome.SWAMP
	return Biome.WOODLAND

## Height comes from the elevation field alone, as one continuous surface, and
## the biome only decides how it is banded and coloured. Deriving the height
## from the biome - a base per biome, which is what this used to do - stood the
## mountains on sheer plinths wherever two biomes met: walls thirty metres high
## that cut the map into pieces you could not walk between.
func _raw_height(x: float, z: float, _biome: Biome) -> float:
	return _sample(x, z)[1]

func _height_from(e: float, m: float, x: float, z: float, land: float) -> float:
	var d := _detail.get_noise_2d(x, z)
	# Lowland, then rolling country, then the hills climbing steeply.
	var h := 1.2 + 9.0 * smoothstep(0.30, 0.66, e) + 150.0 * pow(maxf(0.0, e - 0.60), 1.35)
	# Wet ground sinks toward the water line.
	h -= 2.4 * smoothstep(0.64, 0.76, m) * (1.0 - smoothstep(0.40, 0.50, e))
	# More texture in the high country than in the lowland.
	h += d * lerpf(0.7, 1.8, smoothstep(0.55, 0.75, e))
	# The map is an island: the land runs down to a beach and into the sea
	# round its edge, so the horizon is water rather than the end of the world.
	var to_edge := half_extent - maxf(absf(x), absf(z))
	h = lerpf(-3.5, h, smoothstep(4.0, SHORE_WIDTH, to_edge))
	# Between islands the sea floor, deep enough that only a bridge crosses.
	if land < 1.0:
		h = lerpf(-7.0, h, smoothstep(0.0, 1.0, land))
	return h

## Inside a carved feature: [weight 0..1, biome, height the feature wants].
## A valley is a flat green floor ringed by a high ridge with one narrow way
## in; a crater is a scorched bowl with a raised rim.
func _feature_at(x: float, z: float) -> Array:
	for f in features:
		var c: Vector2 = f.centre
		var r: float = float(f.radius)
		var off := Vector2(x, z) - c
		var d := off.length()
		if d > r * 2.6:
			continue
		match String(f.kind):
			"basin":
				continue
			"valley":
				var floor_h: float = float(f.get("floor", 6.0))
				if d <= r:
					return [1.0, Biome.WOODLAND, floor_h]
				# The way in: a gorge the width of a truck through the ridge.
				var gap: float = float(f.get("gap", 0.0))
				var across := absf(off.rotated(-gap).y)
				var along := off.rotated(-gap).x
				if along > 0.0 and across < float(f.get("gorge", 9.0)):
					return [1.0, Biome.WOODLAND, floor_h]
				var t := (d - r) / (r * 1.6)
				var ridge := floor_h + float(f.get("ridge", 46.0)) * sin(clampf(t, 0.0, 1.0) * PI * 0.5)
				var w := 1.0 - smoothstep(0.7, 1.0, t)
				return [w, Biome.MOUNTAIN if t < 0.8 else Biome.WOODLAND, ridge]
			"pit":
				var q := pit_space(f, x, z)
				return _pit_at(f, q, q.length())
			"crater":
				var rim_h: float = float(f.get("rim", 9.0))
				var floor_c: float = float(f.get("floor", 2.0))
				if d <= r:
					return [1.0, Biome.MOUNTAIN, lerpf(floor_c, rim_h, pow(d / r, 2.2))]
				var t2 := (d - r) / (r * 1.2)
				return [1.0 - smoothstep(0.3, 1.0, t2), Biome.MOUNTAIN, rim_h * (1.0 - t2 * 0.8)]
	return []

## An open-pit quarry: a deep round pit with a haul road spiralling down its
## wall to a flat floor - benches of road with steep rock between, as a real
## pit is worked. {rim, floor, radius, inner, road, turns, entry (radians)}
func _pit_at(f: Dictionary, off: Vector2, d: float) -> Array:
	var rim: float = float(f.get("rim", 30.0))
	var bottom: float = float(f.get("floor", 4.0))
	var top_r: float = float(f.radius)
	var in_r: float = float(f.get("inner", 24.0))
	var road: float = float(f.get("road", 14.0))
	var turns: float = float(f.get("turns", 2.0))
	var entry: float = float(f.get("entry", PI * 0.5))
	var depth := rim - bottom
	if d >= top_r:
		# Round the rim: level with it, easing out into the country.
		var t := smoothstep(top_r, top_r + 36.0, d)
		return [1.0 - t, Biome.MOUNTAIN if d < top_r + 8.0 else Biome.WOODLAND, rim]
	if d <= in_r:
		return [1.0, Biome.MOUNTAIN, bottom]
	# The road's centre line: radius and height for s, 0 at the rim to 1 on the
	# floor, going round `turns` times.
	var span := top_r - in_r - road
	var phi := atan2(off.y, off.x)
	var base := fposmod(phi - entry, TAU) / TAU / turns
	# Each wrap of the road at this bearing, outermost (highest) first; the
	# rim above them all, the floor below.
	var rings: Array = [[top_r + road * 0.5, rim]]
	var k := 0
	while k <= int(ceil(turns)):
		var sk := base + float(k) / turns
		if sk <= 1.0:
			rings.append([top_r - road * 0.5 - span * sk, rim - depth * sk])
		k += 1
	rings.append([in_r - road * 0.5, bottom])
	for i in rings.size():
		var ring: Array = rings[i]
		if absf(d - float(ring[0])) <= road * 0.5:
			return [1.0, Biome.MOUNTAIN, float(ring[1])]
	# Between two wraps: the rock wall from the one below up to the one above.
	for i in rings.size() - 1:
		var outer: Array = rings[i]
		var inner: Array = rings[i + 1]
		var r_out := float(outer[0]) - road * 0.5
		var r_in := float(inner[0]) + road * 0.5
		if d <= r_out and d >= r_in:
			var t := smoothstep(r_in, r_out, d)
			return [1.0, Biome.MOUNTAIN, lerpf(float(inner[1]), float(outer[1]), t)]
	return [1.0, Biome.MOUNTAIN, bottom]

## Inside a quarry pit (plus `pad` metres round it)?
func _in_pit(x: float, z: float, pad: float = 0.0) -> bool:
	for f in features:
		if String(f.kind) == "pit" and pit_space(f, x, z).length() < float(f.radius) + pad:
			return true
	return false

## A pit need not be round: `stretch` draws it out along `angle`. This is a
## point in the pit's own round frame, where it is laid out as a circle.
static func pit_space(f: Dictionary, x: float, z: float) -> Vector2:
	var off := (Vector2(x, z) - (f.centre as Vector2)).rotated(-float(f.get("angle", 0.0)))
	return Vector2(off.x / float(f.get("stretch", 1.0)), off.y)

## Back from the pit's round frame to the map.
static func from_pit_space(f: Dictionary, q: Vector2) -> Vector2:
	return (f.centre as Vector2) + Vector2(q.x * float(f.get("stretch", 1.0)), q.y).rotated(float(f.get("angle", 0.0)))

## In a crater's scorched bowl (as far out as it is drawn scorched).
func _crater_bowl(x: float, z: float) -> bool:
	for f in features:
		if String(f.kind) == "crater" and Vector2(x, z).distance_to(f.centre) < float(f.radius) * 1.3:
			return true
	return false

## Within reach of a crater at all (its rim eases out a long way).
func _crater_near(x: float, z: float) -> bool:
	for f in features:
		if String(f.kind) == "crater" and Vector2(x, z).distance_to(f.centre) < float(f.radius) * 2.7:
			return true
	return false

## Nothing grows in a crater.
func _in_crater(x: float, z: float) -> bool:
	for f in features:
		if String(f.kind) == "crater" and Vector2(x, z).distance_to(f.centre) < float(f.radius) * 1.4:
			return true
	return false

## Every found point within a feature's floor, for what grows there.
func points_in_feature(name: String, step: int = 1) -> PackedVector3Array:
	var out := PackedVector3Array()
	for f in features:
		if String(f.name) != name:
			continue
		var c: Vector2 = f.centre
		var r: float = float(f.radius) * 0.92
		var z := c.y - r
		while z <= c.y + r:
			var x := c.x - r
			while x <= c.x + r:
				if Vector2(x - c.x, z - c.y).length() <= r and height_at(x, z) > WATER_LEVEL + 0.2:
					out.append(Vector3(x, height_at(x, z), z))
				x += CELL * float(step)
			z += CELL * float(step)
	return out

## Bands a height into terraces: flat for most of each band, then a riser.
static func terrace(h: float, step: float) -> float:
	if step <= 0.0:
		return snappedf(h, 0.25)
	var t := h / step
	var k := floorf(t)
	return (k + smoothstep(TERRACE_EDGE, 1.0, t - k)) * step

## Spec: rivers, some fordable and some not. A river is cut down through
## whatever the land was doing, with banks that fall away over a few metres.
func _carve_rivers() -> void:
	for river in rivers:
		var path: Array = river.get("path", [])
		var width: float = float(river.get("width", 9.0))
		var depth: float = float(river.get("depth", 3.2))
		var fords: Array = river.get("fords", [])
		if path.size() < 2:
			continue
		var near := _cells_near(path, width * 2.2)
		for index in near:
			var d: float = near[index].x
			# A ford is a stretch where the bed is left shallow enough to
			# drive through; everywhere else wants a bridge.
			var along: float = near[index].y
			var bed := -depth
			for ford in fords:
				var span: float = float(ford.get("width", 22.0))
				if absf(along - float(ford.get("at", 0.0))) < span * 0.5:
					bed = -0.45
					break
			var t: float = clampf(d / maxf(0.5, width), 0.0, 1.0)
			# Flat bed in the channel, then a bank up to the old ground.
			var carved: float = lerpf(bed, _heights[index], smoothstep(0.0, 1.0, t))
			_heights[index] = minf(_heights[index], carved)

## Every grid point within `reach` of a polyline, as index -> Vector2(distance,
## distance along). Walks each segment's own bounding box rather than the whole
## map, which is the difference between a second and a minute on a big map.
func _cells_near(path: Array, reach: float) -> Dictionary:
	var out: Dictionary = {}
	var travelled := 0.0
	for i in path.size() - 1:
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var length := ab.length()
		if length < 0.001:
			continue
		var x0 := maxi(0, int(floor(_grid_coord(minf(a.x, b.x) - reach))))
		var x1 := mini(_cells, int(ceil(_grid_coord(maxf(a.x, b.x) + reach))))
		var z0 := maxi(0, int(floor(_grid_coord(minf(a.z, b.z) - reach))))
		var z1 := mini(_cells, int(ceil(_grid_coord(maxf(a.z, b.z) + reach))))
		for iz in range(z0, z1 + 1):
			var z := -half_extent + float(iz) * CELL
			for ix in range(x0, x1 + 1):
				var x := -half_extent + float(ix) * CELL
				var t: float = clampf(Vector2(x - a.x, z - a.z).dot(ab) / (length * length), 0.0, 1.0)
				var d := Vector2(x - a.x - ab.x * t, z - a.z - ab.y * t).length()
				if d > reach:
					continue
				var index := _index(ix, iz)
				var have: Variant = out.get(index)
				if have == null or d < (have as Vector2).x:
					out[index] = Vector2(d, travelled + length * t)
		travelled += length
	return out

## For every grid point within `band` of any stretch of the road, the lowest
## road level over it: index -> height.
func _lowest_under_road(path: Array, profile: PackedFloat32Array, span: float, band: float,
		near: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	# Only other legs of the road count: the stretch a point is nearest to has
	# set it already, and the few metres either side of that are the same road.
	var same_leg := band * 3.0
	var travelled := 0.0
	for i in path.size() - 1:
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var length := ab.length()
		if length < 0.001:
			continue
		var x0 := maxi(0, int(floor(_grid_coord(minf(a.x, b.x) - band))))
		var x1 := mini(_cells, int(ceil(_grid_coord(maxf(a.x, b.x) + band))))
		var z0 := maxi(0, int(floor(_grid_coord(minf(a.z, b.z) - band))))
		var z1 := mini(_cells, int(ceil(_grid_coord(maxf(a.z, b.z) + band))))
		for iz in range(z0, z1 + 1):
			var z := -half_extent + float(iz) * CELL
			for ix in range(x0, x1 + 1):
				var x := -half_extent + float(ix) * CELL
				var t: float = clampf(Vector2(x - a.x, z - a.z).dot(ab) / (length * length), 0.0, 1.0)
				var d := Vector2(x - a.x - ab.x * t, z - a.z - ab.y * t).length()
				if d > band:
					continue
				var index := _index(ix, iz)
				var along := travelled + length * t
				if near.has(index) and absf(along - float((near[index] as Vector2).y)) < same_leg:
					continue
				var h := _profile_height(profile, along, span)
				if not out.has(index) or h < float(out[index]):
					out[index] = h
		travelled += length
	return out

## Spec: roads across the land, giving a small speed bonus to drive on.
##
## The carriageway is graded to one height clean across its width. Blending it
## in gradually from the centre-line - which is what this used to do - leaves
## the surface cambered, and a cambered road is one you slide off rather than
## drive on. It still follows the lie of the land lengthwise, but off a smoothed
## profile, so it is a graded road and not a rollercoaster draped over every bump.
func _grade_roads(list: Array) -> void:
	for road in list:
		var path: Array = road.get("path", []) if road is Dictionary else road
		var bridged: bool = road is Dictionary and bool(road.get("bridge", false))
		var ford: bool = road is Dictionary and bool(road.get("ford", false))
		if path.size() < 2:
			continue
		var span := _path_length(path)
		if bridged:
			_find_bridges(path, span)
		var floor_h := -INF
		if bridged:
			floor_h = WATER_LEVEL + 0.8
		elif ford:
			floor_h = WATER_LEVEL - 0.45
		var hold := float(road.get("hold_end", 0.0)) if road is Dictionary else 0.0
		var end_level := float(road.get("end_level", NAN)) if road is Dictionary else NAN
		var profile := _road_profile(path, span, floor_h, hold, end_level)
		if profile.is_empty():
			continue
		var reach := ROAD_HALF_WIDTH + ROAD_SHOULDER
		var near := _cells_near(path, reach)
		# Another road's carriageway, already laid, keeps its own level: a
		# road joining it starts at that level and does not regrade it.
		var laid := _road_core.duplicate()
		for index in near:
			if laid[index] == 1:
				continue
			var d: float = near[index].x
			if d <= ROAD_HALF_WIDTH:
				_road_core[index] = 1
			# A bridged road leaves the water alone: the deck goes over it.
			if bridged and _heights[index] < WATER_LEVEL - 0.05:
				continue
			var target := _profile_height(profile, near[index].y, span)
			# On a levelled place the road lies on it: no cut under it.
			var sink := 0.0 if _on_site(index) else ROAD_SINK
			# Where a road meets a carved channel it crosses at a ford
			# rather than filling the river in.
			if not bridged and _heights[index] < WATER_LEVEL - 0.3:
				target = minf(target, -0.35)
			# Flat a cell beyond the carriageway too, so no triangle that
			# reaches onto the road has a corner up a bank.
			if d <= ROAD_HALF_WIDTH + CELL:
				# A little under the road's own level: the carriageway is laid
				# on top (RoadSurface), level across, and on a bend the land
				# between grid points must not come up through its edge.
				_heights[index] = target - sink
				_road_mask[index] = 1
			else:
				var t: float = clampf((d - ROAD_HALF_WIDTH - CELL) / ROAD_SHOULDER, 0.0, 1.0)
				_heights[index] = lerpf(target - sink, _heights[index], smoothstep(0.0, 1.0, t))
		# Where the road comes back past itself - a hairpin, a switchback, a
		# tight bend on a hillside - the ground between the two legs belongs
		# to whichever is nearer, and the other leg's edge would have the land
		# standing up over it. So under every stretch of carriageway the land
		# is taken down to that stretch's own level: nothing pokes up through
		# a road on a turn.
		var under := _lowest_under_road(path, profile, span, ROAD_HALF_WIDTH + CELL * 0.75, near)
		for index in under:
			if laid[index] == 1:
				continue
			if bridged and _heights[index] < WATER_LEVEL - 0.05:
				continue
			_heights[index] = minf(_heights[index], float(under[index]) - ROAD_SINK)
		# RoadSurface lays the carriageway at the profile's height.
		for entry in road_paths:
			if entry.path == path:
				entry["profile"] = profile
				entry["span"] = span

## The wet stretches of a bridged road, before it is graded: each becomes a
## bridge from dry road to dry road.
func _find_bridges(path: Array, span: float) -> void:
	var step := 3.0
	var start := -1.0
	var last_wet := -INF
	var along := 0.0
	while along <= span:
		var p := _point_along(path, along)
		var wet := height_at(p.x, p.z) < WATER_LEVEL - 0.1
		if wet:
			if start < 0.0:
				start = along
			last_wet = along
		elif start >= 0.0 and along - last_wet > 20.0:
			# A strip of dry ground this short is not worth coming down onto:
			# one bridge spans both waters.
			_add_bridge(path, span, start, last_wet)
			start = -1.0
		along += step
	if start >= 0.0:
		_add_bridge(path, span, start, minf(span, last_wet))

func _add_bridge(path: Array, span: float, from: float, to: float) -> void:
	var a := _point_along(path, maxf(0.0, from - 12.0))
	var b := _point_along(path, minf(span, to + 12.0))
	# Two roads sharing a crossing share its bridge: a second deck laid
	# alongside would put its railing across the first one's road.
	for other in bridges:
		var oa: Vector3 = other.a
		var ob: Vector3 = other.b
		var mid := (a + b) * 0.5
		var near := Geometry3D.get_closest_point_to_segment(mid, oa, ob)
		if Vector2(near.x - mid.x, near.z - mid.z).length() < 25.0:
			return
	bridges.append({"a": a, "b": b, "span": to - from})

## Once the deck ends are graded, their heights are known.
func bridge_ends(bridge: Dictionary) -> Array:
	var a: Vector3 = bridge.a
	var b: Vector3 = bridge.b
	return [Vector3(a.x, height_at(a.x, a.z), a.z), Vector3(b.x, height_at(b.x, b.z), b.z)]

## A road from each found site that asked for one to the nearest road, so the
## trading posts and the far store can be driven to. Hidden places get none.
func _spur_roads() -> Array:
	var out: Array = []
	_spurs_laid = out
	for name in spur_sites:
		if not found_sites.has(name):
			continue
		var site: Vector3 = found_sites[name]
		var near := _nearest_road_point(site)
		if near.is_empty() or float(near.d) > 900.0:
			continue
		# Where it meets the road is where the way there first comes down to
		# it - not the nearest point as the crow flies, which may be round the
		# far side of a mountain from the way a road would actually go.
		var way := _route(Vector3(site.x, 0, site.z), near.at, false)
		for q in way:
			var close := _nearest_road_point(q)
			if not close.is_empty() and float(close.d) < 70.0:
				near = close
				break
		var best: Vector3 = near.at
		var best_tangent: Vector3 = near.tangent
		# It leaves the road square on, a real junction, and bends round to
		# the site from there: driven outward from the junction, so the
		# square end is the one at the road.
		var normal := Vector3(-best_tangent.z, 0.0, best_tangent.x)
		if normal.dot(Vector3(site.x - best.x, 0.0, site.z - best.z)) < 0.0:
			normal = -normal
		# Off the end of a road there is no junction to square off: it sets
		# out straight for the place.
		if near.get("end", false):
			normal = Vector3(site.x - best.x, 0.0, site.z - best.z).normalized()
		var lead := best + normal * 40.0
		var routed: Array = [best]
		for p in _route(lead, Vector3(site.x, 0, site.z), false):
			routed.append(p)
		var path := _drive_path(_smooth_path(routed), normal)
		var radius := _site_radius(site)
		# It stops at the edge of the place's levelled ground - its way in -
		# rather than running on into the middle of it; the place turns its
		# front to face the road there.
		path = _stop_at(path, site, radius * 0.9)
		_add_driveway(out, name, path, site.y, bool(near.get("end", false)))
	for dw in driveways:
		var centre: Vector3 = dw.centre
		var radius := float(dw.radius)
		var level := _site_level(centre)
		var door: Variant = dw.get("door")
		var near := _nearest_road_point(door if door != null else centre)
		if near.is_empty():
			continue
		# No door named: the edge of the place nearest the road.
		if door == null:
			var toward := Vector3(near.at.x - centre.x, 0.0, near.at.z - centre.z).normalized()
			door = centre + toward * radius * 0.9
			near = _nearest_road_point(door)
		var start: Vector3 = near.at
		# The nearest point on a road is square off it: a straight drive in.
		var path: Array = [Vector3(start.x, 0, start.z)]
		var d: Vector3 = door
		var run := Vector2(d.x - start.x, d.z - start.z).length()
		var n := maxi(2, int(run / 6.0))
		for k in range(1, n + 1):
			path.append(Vector3(start.x, 0, start.z).lerp(Vector3(d.x, 0, d.z), float(k) / float(n)))
		_add_driveway(out, String(dw.name), path, level)
	return out

func _add_driveway(out: Array, name: String, path: Array, level: float, from_end: bool = false) -> void:
	# Level with the place for its last stretch, so levelling the place
	# afterwards leaves the road where it was.
	out.append({"path": path, "bridge": true, "style": "dirt", "hold_end": 8.0, "end_level": level})
	# Its surface starts at the edge of the road it leaves, not over it.
	road_paths.append({"path": path, "style": "dirt", "bridge": true,
		"trim": 0.0 if from_end else RoadSurface.HALF + 1.0})
	road_ends[name] = path[path.size() - 1]

## The path cut where it first comes within `reach` of `centre`, ending on
## that circle.
func _stop_at(path: Array, centre: Vector3, reach: float) -> Array:
	var out: Array = [path[0]]
	for i in range(1, path.size()):
		var p: Vector3 = path[i]
		if Vector2(p.x - centre.x, p.z - centre.z).length() <= reach:
			var q: Vector3 = out[out.size() - 1]
			var dir := Vector3(q.x - centre.x, 0.0, q.z - centre.z).normalized()
			if Vector2(q.x - centre.x, q.z - centre.z).length() > reach + 0.5:
				out.append(Vector3(centre.x, 0, centre.z) + dir * reach)
			return out
		out.append(p)
	return out

func _site_radius(p: Vector3) -> float:
	for bs in build_sites:
		if Vector2((bs.centre as Vector3).x - p.x, (bs.centre as Vector3).z - p.z).length() < 1.0:
			return float(bs.radius)
	return 10.0

func _site_level(p: Vector3) -> float:
	for bs in build_sites:
		var c: Vector3 = bs.centre
		if Vector2(c.x - p.x, c.z - p.z).length() < 1.0:
			return c.y
	return height_at(p.x, p.z)

## Sites asked for without a height (NAN) are levelled to the lie of the land
## round them, not dug into it or stood up out of it.
func _level_sites() -> void:
	for i in build_sites.size():
		var c: Vector3 = build_sites[i].centre
		if is_nan(c.y):
			c.y = maxf(WATER_LEVEL + 0.6, snappedf(_mean_height(c, float(build_sites[i].radius)), 0.25))
			build_sites[i].centre = c
	for dw in driveways:
		var c: Vector3 = dw.centre
		if is_nan(c.y):
			dw.centre = Vector3(c.x, _site_level(c), c.z)

## The nearest point on a road to `point` - not on a bridge, not in a road's
## last few metres - with the road's direction there: {at, tangent, d}.
## Does this road stop in open country (rather than at another road)?
func _dead_end(path: Array) -> bool:
	var end: Vector3 = path[path.size() - 1]
	for road in roads + _spurs_laid:
		var other: Array = road.get("path", []) if road is Dictionary else road
		if other == path or other.size() < 2:
			continue
		if _distance_to_path(end, other).x < 15.0:
			return false
	return true

## Spurs laid so far this generation, which later spurs may branch from.
var _spurs_laid: Array = []

func _nearest_road_point(point: Vector3) -> Dictionary:
	var out: Dictionary = {}
	var best_d := INF
	for road in roads + _spurs_laid:
		var path: Array = road.get("path", []) if road is Dictionary else road
		if path.size() < 2:
			continue
		var span := _path_length(path)
		# Exactly the nearest point on it (square off the road), kept out of
		# its last few metres.
		var hit := _distance_to_path(point, path)
		# Near its far end, the road is carried on from its end instead: no
		# junction just short of the end with the new road doubling back
		# alongside it.
		var at_end := hit.y > span - 30.0 and _dead_end(path)
		var along := span if at_end else clampf(hit.y, 30.0, span - 30.0)
		var p := _point_along(path, along)
		var d := Vector2(p.x - point.x, p.z - point.z).length()
		if d >= best_d or height_at(p.x, p.z) <= WATER_LEVEL + 0.3:
			continue
		best_d = d
		var ahead := _point_along(path, minf(span, along + 6.0))
		var behind := _point_along(path, along - 6.0)
		out = {"at": p, "d": d, "end": at_end,
			"tangent": Vector3(ahead.x - behind.x, 0.0, ahead.z - behind.z).normalized()}
	return out

# --- Routing -----------------------------------------------------------------

## Grid spacing roads are routed on, metres.
const ROUTE_STEP := 20.0
## Steepest a routed leg may climb. Steeper ground is not ruled out, only
## climbed at an angle - which up a mountainside means switchbacks.
const ROUTE_GRADE := 0.11

## Turns every road given as waypoints ({route: [...]}) into a real path: one
## that goes round the hills rather than over them, eases across valleys and
## zig-zags up a mountain, and crosses water where the crossing is short.
func _route_roads() -> void:
	# Branches last: a road that leaves another (`branch_of`, its index) sets
	# off from wherever that road was actually laid nearest its next waypoint,
	# not from a waypoint the other road's curves may have left out in a field.
	var order: Array = []
	for i in roads.size():
		if not (roads[i] is Dictionary and (roads[i] as Dictionary).has("branch_of")):
			order.append(i)
	for i in roads.size():
		if not order.has(i):
			order.append(i)
	for ri in order:
		var road = roads[ri]
		if road is Dictionary and road.has("route"):
			var points: Array = (road.route as Array).duplicate()
			if road.has("branch_of"):
				var trunk = roads[int(road.branch_of)]
				var trunk_path: Array = trunk.get("path", []) if trunk is Dictionary else trunk
				var aim: Vector3 = points[1]
				var best_d := INF
				for q: Vector3 in trunk_path:
					var d := Vector2(q.x - aim.x, q.z - aim.z).length()
					if d < best_d:
						best_d = d
						points[0] = Vector3(q.x, 0.0, q.z)
			var path: Array = [points[0]]
			for i in points.size() - 1:
				var leg := _route(points[i], points[i + 1], bool(road.get("ford", false)))
				for k in range(1, leg.size()):
					path.append(leg[k])
			# Driven, not just joined up: the first waypoint pair gives the
			# heading it sets off on (square off whatever it leaves), and no
			# bend is tighter than a truck takes at speed.
			var first: Vector3 = points[1] - points[0]
			road["path"] = _drive_path(_smooth_path(path), Vector3(first.x, 0.0, first.z).normalized())
	for road in roads:
		var p: Array = road.get("path", []) if road is Dictionary else road
		road_paths.append({"path": p, "style": String(road.get("style", "asphalt")) if road is Dictionary else "asphalt",
			"bridge": road is Dictionary and bool(road.get("bridge", false))})

## Tightest bend a road is laid with, metres of radius.
const ROAD_MIN_RADIUS := 24.0
## How far ahead the driver looks down the planned line.
const ROAD_LOOKAHEAD := 50.0

## The planned line as a vehicle would drive it: setting off along `heading`,
## steering toward a point a little way down the line, never turning tighter
## than ROAD_MIN_RADIUS. Where the plan zig-zags or kinks, the road swings
## round in a proper curve instead; it ends on the plan's last point.
func _drive_path(plan: Array, heading: Vector3) -> Array:
	if plan.size() < 3:
		return plan
	# Zig-zags ironed out of the plan first: a switchback is a climb the
	# grading can make in a cutting, where a car following it would loop.
	for pass_index in 40:
		var eased := plan.duplicate()
		for i in range(1, plan.size() - 1):
			eased[i] = (plan[i - 1] + plan[i] * 2.0 + plan[i + 1]) * 0.25
		plan = eased
	var span := _path_length(plan)
	var step := 2.0
	var pos: Vector3 = plan[0]
	var dir := Vector2(heading.x, heading.z)
	if dir.length() < 0.01:
		var b: Vector3 = plan[1]
		dir = Vector2(b.x - pos.x, b.z - pos.z)
	dir = dir.normalized()
	var progress := 0.0
	var out: Array = [Vector3(pos.x, 0.0, pos.z)]
	var travelled := 0.0
	var max_turn := step / ROAD_MIN_RADIUS
	var end: Vector3 = plan[plan.size() - 1]
	while travelled < span * 3.0 + 200.0:
		# How far down the plan we are: the nearest point a little either side
		# of where we were, never going back.
		var best := progress
		var best_d := INF
		var s := progress
		while s <= minf(span, progress + 30.0):
			var q := _point_along(plan, s)
			var d := Vector2(q.x - pos.x, q.z - pos.z).length_squared()
			if d < best_d:
				best_d = d
				best = s
			s += 1.0
		progress = best
		var to_end := Vector2(end.x - pos.x, end.z - pos.z).length()
		if progress >= span - 1.0 or to_end < 10.0:
			break
		# Close to the end but pointed away from it: no circling round to hit
		# the exact point - the road ends here.
		if to_end < ROAD_MIN_RADIUS * 2.5 and absf(dir.angle_to(Vector2(end.x - pos.x, end.z - pos.z))) > PI * 0.4:
			end = Vector3(pos.x, 0.0, pos.z)
			break
		var target := _point_along(plan, minf(span, progress + ROAD_LOOKAHEAD))
		var want := Vector2(target.x - pos.x, target.z - pos.z)
		if want.length() > 0.01:
			var turn := clampf(dir.angle_to(want.normalized()), -max_turn, max_turn)
			dir = dir.rotated(turn)
		pos += Vector3(dir.x, 0.0, dir.y) * step
		travelled += step
		out.append(Vector3(pos.x, 0.0, pos.z))
	out.append(end)
	# Back to one point every few metres.
	var total := _path_length(out)
	var even: Array = []
	var n := maxi(2, int(total / 8.0))
	for i in n + 1:
		even.append(_point_along(out, total * float(i) / float(n)))
	return even

func _beside_road(x: float, z: float) -> bool:
	for o in [Vector2.ZERO, Vector2(18, 0), Vector2(-18, 0), Vector2(0, 18), Vector2(0, -18)]:
		var ix := clampi(int(round(_grid_coord(x + o.x))), 0, _cells)
		var iz := clampi(int(round(_grid_coord(z + o.y))), 0, _cells)
		if _road_mask[_index(ix, iz)] == 1:
			return true
	return false

## A* over a coarse grid in the box round the two ends. Edges steeper than the
## grade limit are left out altogether, so the search has to find a way that
## climbs gently; each point costs more on rough or wet ground, so the way it
## finds keeps to easy country and crosses water where it is narrow.
func _route(a: Vector3, b: Vector3, wade: bool) -> Array:
	var reach := maxf(260.0, Vector2(a.x - b.x, a.z - b.z).length() * 0.35)
	var lo := Vector2(minf(a.x, b.x) - reach, minf(a.z, b.z) - reach)
	var hi := Vector2(maxf(a.x, b.x) + reach, maxf(a.z, b.z) + reach)
	lo = lo.clamp(Vector2(-half_extent + 30.0, -half_extent + 30.0), Vector2(half_extent - 30.0, half_extent - 30.0))
	hi = hi.clamp(Vector2(-half_extent + 30.0, -half_extent + 30.0), Vector2(half_extent - 30.0, half_extent - 30.0))
	var nx := int((hi.x - lo.x) / ROUTE_STEP) + 1
	var nz := int((hi.y - lo.y) / ROUTE_STEP) + 1
	for grade in [ROUTE_GRADE, ROUTE_GRADE * 1.8, 10.0]:
		var path := _route_on(a, b, lo, nx, nz, grade, wade)
		if path.size() >= 2:
			return path
	return [a, b]

func _route_on(a: Vector3, b: Vector3, lo: Vector2, nx: int, nz: int, grade: float, wade: bool) -> Array:
	var astar := AStar2D.new()
	astar.reserve_space(nx * nz)
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	var wet := PackedByteArray()
	wet.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var id := iz * nx + ix
			var x := lo.x + float(ix) * ROUTE_STEP
			var z := lo.y + float(iz) * ROUTE_STEP
			var h := height_at(x, z)
			wet[id] = int(h < WATER_LEVEL + 0.3)
			# Across water the deck or the causeway is level, whatever the bed.
			heights[id] = maxf(h, WATER_LEVEL + 0.8)
			var rough := absf(height_at(x + ROUTE_STEP * 0.5, z) - height_at(x - ROUTE_STEP * 0.5, z)) \
				+ absf(height_at(x, z + ROUTE_STEP * 0.5) - height_at(x, z - ROUTE_STEP * 0.5))
			# Rough ground costs more, and a slow wander in the cost makes a road
			# drift about across open country rather than run dead straight.
			var weight := 1.0 + rough * 0.14 + 6.0 * pow(_warp.get_noise_2d(x * 7.0, z * 7.0) * 0.5 + 0.5, 2.0)
			if wet[id] != 0:
				weight += 1.5 if wade else 5.0
			var near_ends := Vector2(x - a.x, z - a.z).length() < 60.0 or Vector2(x - b.x, z - b.z).length() < 60.0
			if _in_build_site(x, z) and not near_ends:
				weight += 3.0
			# Never through a quarry pit: its haul road is its own.
			if _in_pit(x, z, 8.0):
				weight += 800.0
			# Not along another road: a way that runs beside one is a road
			# too many, and two carriageways side by side fight over the land.
			if not near_ends and _beside_road(x, z):
				weight += 12.0
			astar.add_point(id, Vector2(x, z), weight)
	var steps := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1),
		Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, -1), Vector2i(1, -2)]
	for iz in nz:
		for ix in nx:
			var id := iz * nx + ix
			for st: Vector2i in steps:
				var jx := ix + st.x
				var jz := iz + st.y
				if jx < 0 or jz < 0 or jx >= nx or jz >= nz:
					continue
				var jd := jz * nx + jx
				var run := Vector2(st).length() * ROUTE_STEP
				if absf(heights[id] - heights[jd]) > grade * run:
					continue
				astar.connect_points(id, jd)
	var start := astar.get_closest_point(Vector2(a.x, a.z))
	var goal := astar.get_closest_point(Vector2(b.x, b.z))
	var ids := astar.get_id_path(start, goal)
	if ids.is_empty():
		return []
	var out: Array = [a]
	for k in range(1, ids.size() - 1):
		var p := astar.get_point_position(ids[k])
		out.append(Vector3(p.x, 0.0, p.y))
	out.append(b)
	return out

## Grid corners rounded off (Chaikin), then evened out to one point every few
## metres, so a routed road reads as curves and hairpins rather than steps.
func _smooth_path(path: Array) -> Array:
	var pts := path
	for pass_index in 3:
		if pts.size() < 3:
			break
		var next: Array = [pts[0]]
		for i in pts.size() - 1:
			var p0: Vector3 = pts[i]
			var p1: Vector3 = pts[i + 1]
			next.append(p0.lerp(p1, 0.25))
			next.append(p0.lerp(p1, 0.75))
		next.append(pts[pts.size() - 1])
		pts = next
	var span := _path_length(pts)
	var out: Array = []
	var n := maxi(2, int(span / 8.0))
	for i in n + 1:
		out.append(_point_along(pts, span * float(i) / float(n)))
	return out

## Heights along a road's centre-line: taken off the land, then averaged over
## a long stretch either way so the road rides over bumps and hollows instead
## of following each one; held no steeper than a truck climbs, cutting through
## rises and banking up over dips alike; and at each end brought to the level
## of whatever it meets - the road it joins, the site it ends at - so a
## junction is level and not a step.
const PROFILE_REACH := 20.0
const PROFILE_EASE := 45.0

func _road_profile(path: Array, span: float, floor_h: float = -INF, hold_end: float = 0.0,
		end_level: float = NAN) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var steps := maxi(2, int(ceil(span / CELL)))
	var ds := span / float(steps)
	for i in steps + 1:
		var point := _point_along(path, span * float(i) / float(steps))
		out.append(maxf(floor_h, height_at(point.x, point.z)))
	var w := maxi(1, int(round(PROFILE_REACH / ds)))
	for pass_index in 3:
		var sums := PackedFloat64Array()
		sums.resize(out.size() + 1)
		sums[0] = 0.0
		for i in out.size():
			sums[i + 1] = sums[i] + out[i]
		var smoothed := out.duplicate()
		for i in out.size():
			var lo := maxi(0, i - w)
			var hi := mini(out.size() - 1, i + w)
			# Symmetric near the ends, so they are not dragged toward the middle.
			var r := mini(i - lo, hi - i)
			smoothed[i] = float(sums[i + r + 1] - sums[i - r]) / float(2 * r + 1)
		out = smoothed
	for i in out.size():
		out[i] = maxf(out[i], floor_h)
	var n := out.size() - 1
	var start_h := _road_level_near(path[0], path)
	if is_nan(start_h):
		start_h = maxf(floor_h, height_at((path[0] as Vector3).x, (path[0] as Vector3).z))
	var end_h := end_level
	if is_nan(end_h):
		end_h = _road_level_near(path[path.size() - 1], path)
	if is_nan(end_h):
		var e: Vector3 = path[path.size() - 1]
		end_h = maxf(floor_h, height_at(e.x, e.z))
	# Eased onto the end levels rather than stepped.
	var fixed := PackedByteArray()
	fixed.resize(out.size())
	var d0 := start_h - out[0]
	var d1 := end_h - out[n]
	for i in out.size():
		var along := float(i) * ds
		var from_end := span - along
		out[i] += d0 * smoothstep(PROFILE_EASE, 0.0, along)
		if from_end <= hold_end:
			out[i] = end_h
			fixed[i] = 1
		else:
			out[i] += d1 * smoothstep(PROFILE_EASE, 0.0, from_end - hold_end)
	out[0] = start_h
	out[n] = end_h
	fixed[0] = 1
	fixed[n] = 1
	# Across a levelled place the road is level with it.
	for i in out.size():
		var q := _point_along(path, float(i) * ds)
		for bs in build_sites:
			var c: Vector3 = bs.centre
			if not is_nan(c.y) and Vector2(q.x - c.x, q.z - c.z).length() < float(bs.radius):
				out[i] = c.y
				fixed[i] = 1
				break
	# No steeper than a truck can climb, either way - or, where the two
	# ends are further apart in height than that allows (a road up a peak),
	# one steady climb the whole way rather than a wall at the end.
	var need := absf(end_h - start_h) / maxf(1.0, span - hold_end) * 1.15
	var rise := maxf(MAX_GRADE, need) * ds
	for pass_index in 2:
		for i in range(1, out.size()):
			if fixed[i] == 0:
				out[i] = clampf(out[i], out[i - 1] - rise, out[i - 1] + rise)
		for i in range(out.size() - 2, -1, -1):
			if fixed[i] == 0:
				out[i] = clampf(out[i], out[i + 1] - rise, out[i + 1] + rise)
	# And the corners the limit left rounded off.
	for pass_index in 2:
		var smoothed := out.duplicate()
		for i in range(1, out.size() - 1):
			if fixed[i] == 0:
				smoothed[i] = (out[i - 1] + out[i] * 2.0 + out[i + 1]) * 0.25
		out = smoothed
	return out

## The level of an already-graded road under `point` (another road than
## `own`), or NAN when there is none there.
func _road_level_near(point: Vector3, own: Array) -> float:
	for entry in road_paths:
		if entry.path == own or not entry.has("profile"):
			continue
		var hit := _distance_to_path(point, entry.path)
		if hit.x <= ROAD_HALF_WIDTH:
			return _profile_height(entry.profile, hit.y, float(entry.span))
	return NAN

func _profile_height(profile: PackedFloat32Array, along: float, span: float) -> float:
	if profile.is_empty():
		return 0.0
	var f: float = clampf(along / maxf(0.001, span), 0.0, 1.0) * float(profile.size() - 1)
	var i := int(floor(f))
	var j := mini(i + 1, profile.size() - 1)
	return lerpf(profile[i], profile[j], f - float(i))

func _path_length(path: Array) -> float:
	var total := 0.0
	for i in path.size() - 1:
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		total += Vector2(b.x - a.x, b.z - a.z).length()
	return total

func _point_along(path: Array, along: float) -> Vector3:
	var travelled := 0.0
	for i in path.size() - 1:
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var length := Vector2(b.x - a.x, b.z - a.z).length()
		if along <= travelled + length or i == path.size() - 2:
			return a.lerp(b, clampf((along - travelled) / maxf(0.001, length), 0.0, 1.0))
		travelled += length
	return path[path.size() - 1]

## Build sites are levelled last, so nothing the land does afterwards tilts a
## factory floor.
func _flatten_sites() -> void:
	for site in build_sites:
		# Each is levelled once: later passes leave alone what the roads have
		# since been graded over.
		if site.get("done", false):
			continue
		site["done"] = true
		var centre: Vector3 = site.centre
		var radius: float = float(site.radius)
		var margin: float = radius * 0.45
		var reach := radius + margin
		for iz in range(maxi(0, int(floor(_grid_coord(centre.z - reach)))), mini(_cells, int(ceil(_grid_coord(centre.z + reach)))) + 1):
			for ix in range(maxi(0, int(floor(_grid_coord(centre.x - reach)))), mini(_cells, int(ceil(_grid_coord(centre.x + reach)))) + 1):
				var x := -half_extent + float(ix) * CELL
				var z := -half_extent + float(iz) * CELL
				var d := Vector2(x - centre.x, z - centre.z).length()
				if d > radius + margin:
					continue
				var t: float = clampf((d - radius) / maxf(0.01, margin), 0.0, 1.0)
				var index := _index(ix, iz)
				# Nor under a road graded since (a cave mouth by the road): the
				# road's surface is laid to its own level.
				if _road_mask[index] == 1 and t > 0.0:
					continue
				_heights[index] = lerpf(centre.y, _heights[index], smoothstep(0.0, 1.0, t))
				if d <= radius:
					_road_mask[index] = _road_mask[index]

## Shortest distance from a point to a polyline, plus how far along it that was.
func _distance_to_path(point: Vector3, path: Array) -> Vector2:
	var best := INF
	var best_along := 0.0
	var travelled := 0.0
	for i in path.size() - 1:
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var ab := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var length := ab.length()
		if length < 0.001:
			continue
		var t: float = clampf(Vector3(point.x - a.x, 0.0, point.z - a.z).dot(ab) / (length * length),
			0.0, 1.0)
		var closest := Vector3(a.x + ab.x * t, 0.0, a.z + ab.z * t)
		var d := Vector2(point.x - closest.x, point.z - closest.z).length()
		if d < best:
			best = d
			best_along = travelled + length * t
		travelled += length
	return Vector2(best, best_along)

# --- Mesh ------------------------------------------------------------------

## Cells per side of one chunk of ground. A big map is drawn and collided in
## chunks, so the renderer can cull what is behind you and no one collision
## shape holds the whole country.
const CHUNK := 32

## The land's own meshes (not the water or the sea bed), and what they are
## drawn with plain; with shaders on they get the ground shader instead.
var _land_meshes: Array[MeshInstance3D] = []
var _land_plain: Material
var _land_fancy: ShaderMaterial
var _fancy: bool = true

## Shaders on or off for the ground.
func set_fancy(on: bool) -> void:
	_fancy = on
	var mat: Material = _land_plain
	if on and _land_plain != null:
		if _land_fancy == null:
			_land_fancy = _make_land_shader()
		mat = _land_fancy
	for mi in _land_meshes:
		if is_instance_valid(mi):
			mi.material_override = mat

## The ground with shaders on: the plates' own colours and grain as before,
## and where the ground is grass - green and facing up - drifts of lighter and
## darker, yellower and bluer green across it at a few sizes, a fine speckle
## like blades up close, and a soft sheen rather than the plates' shine.
func _make_land_shader() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = LAND_SHADER
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter(&"grain", Textures.detail("grass"))
	var noise := FastNoiseLite.new()
	noise.seed = 57
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	var img := noise.get_seamless_image(256, 256, false, false, 0.1, true)
	img.generate_mipmaps()
	m.set_shader_parameter(&"patches", ImageTexture.create_from_image(img))
	var plated := _plated()
	m.set_shader_parameter(&"plain_roughness", 0.62 if plated else 1.0)
	m.set_shader_parameter(&"plain_specular", 0.6 if plated else 0.5)
	return m

const LAND_SHADER := """
shader_type spatial;

uniform sampler2D grain : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D patches : filter_linear_mipmap, repeat_enable;
uniform float grain_metres = 6.0;
uniform float plain_roughness = 0.62;
uniform float plain_specular = 0.6;

varying vec3 v_world;
varying vec3 v_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 base = COLOR.rgb;
	vec3 w = abs(v_normal);
	w /= (w.x + w.y + w.z);
	vec3 p = v_world / grain_metres;
	float g = texture(grain, p.zy).r * w.x + texture(grain, p.xz).r * w.y + texture(grain, p.xy).r * w.z;
	vec3 c = base * g;
	float green = smoothstep(0.015, 0.07, base.g - max(base.r, base.b)) * smoothstep(0.72, 0.9, v_normal.y);
	float big = texture(patches, v_world.xz / 160.0).r;
	float mid = texture(patches, v_world.xz / 41.0 + vec2(0.37, 0.71)).r;
	float fine = texture(patches, v_world.xz / 2.3 + vec2(0.13, 0.29)).r;
	vec3 meadow = c * mix(0.82, 1.12, big) * mix(0.92, 1.07, mid);
	meadow = mix(meadow, meadow * vec3(1.12, 1.06, 0.74), smoothstep(0.58, 0.82, mid) * 0.5);
	meadow = mix(meadow, meadow * vec3(0.84, 0.97, 0.92), smoothstep(0.62, 0.86, big) * 0.4);
	meadow *= mix(0.9, 1.07, fine);
	c = mix(c, meadow, green);
	ALBEDO = c;
	ROUGHNESS = mix(plain_roughness, 0.95, green);
	SPECULAR = mix(plain_specular, 0.28, green);
}
"""

func _build_mesh() -> void:
	var mat: StandardMaterial3D
	if not _plated():
		mat = StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 1.0
	else:
		# Sheet metal: a touch of sheen on every plate, so the panels catch
		# the light differently as you move.
		mat = Textures.material("grass", 6.0).duplicate()
		mat.roughness = 0.62
		mat.metallic_specular = 0.6
	_land_plain = mat
	if _plated():
		await _build_plates(mat)
		if _fancy:
			set_fancy(true)
		return
	var chunks := int(ceil(float(_cells) / float(CHUNK)))
	var bufs: Array = []
	for i in chunks * chunks:
		bufs.append(ChunkBuf.new())
	# The triangles for each chunk are worked out across the worker threads;
	# the meshes and shapes are made here, on the main one.
	await Workers.group(_chunk_task.bind(bufs, chunks), chunks * chunks, "terrain chunks", _loading_tree())
	var sea := PackedVector3Array()
	var water := PackedVector3Array()
	for buf: ChunkBuf in bufs:
		sea.append_array(buf.sea)
		water.append_array(buf.water)
		if not buf.sea.is_empty():
			var sea_cs := CollisionShape3D.new()
			var sea_shape := ConcavePolygonShape3D.new()
			sea_shape.set_faces(buf.sea)
			sea_cs.shape = sea_shape
			add_child(sea_cs)
		if buf.verts.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = buf.verts
		arrays[Mesh.ARRAY_NORMAL] = buf.normals
		arrays[Mesh.ARRAY_COLOR] = buf.colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		add_child(mi)
		_land_meshes.append(mi)
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(buf.verts)
		cs.shape = shape
		add_child(cs)
	_build_sheets(sea, water)
	if _fancy:
		set_fancy(true)

## Occluders: the ground as seen by the renderer's occlusion culling, so a
## wood behind a hill is not drawn at all. A coarse copy of the land, one
## vertex every OCCLUDER_STEP cells, kept OCCLUDER_SINK metres under the lowest
## ground round each vertex so it never hides anything that shows over the
## real ridge line. Tiled, so each tile is only tested when it is in view.
const OCCLUDER_STEP := 4
const OCCLUDER_TILE := 32
const OCCLUDER_SINK := 3.0

func _build_occluders() -> void:
	return  # disabled: embree avx512 crash on Zen 5 (Godot 4.6.3)
	if _cells <= 0 or _heights.is_empty():
		return
	var tiles := int(ceil(float(_cells) / float(OCCLUDER_TILE)))
	var half := OCCLUDER_STEP / 2
	for tz in tiles:
		for tx in tiles:
			var x0 := tx * OCCLUDER_TILE
			var z0 := tz * OCCLUDER_TILE
			var x1 := mini(_cells, x0 + OCCLUDER_TILE)
			var z1 := mini(_cells, z0 + OCCLUDER_TILE)
			var cols := (x1 - x0) / OCCLUDER_STEP + 1
			var rows := (z1 - z0) / OCCLUDER_STEP + 1
			if cols < 2 or rows < 2:
				continue
			var verts := PackedVector3Array()
			var lowest := INF
			for r in rows:
				for c in cols:
					var ix := x0 + c * OCCLUDER_STEP
					var iz := z0 + r * OCCLUDER_STEP
					var h := _heights[_index(ix, iz)]
					for o in [Vector2i(-half, -half), Vector2i(half, -half), Vector2i(-half, half), Vector2i(half, half),
							Vector2i(-OCCLUDER_STEP, 0), Vector2i(OCCLUDER_STEP, 0), Vector2i(0, -OCCLUDER_STEP), Vector2i(0, OCCLUDER_STEP)]:
						h = minf(h, _heights[_index(ix + o.x, iz + o.y)])
					h -= OCCLUDER_SINK
					lowest = minf(lowest, h)
					verts.append(Vector3(-half_extent + float(ix) * CELL, h, -half_extent + float(iz) * CELL))
			# Ground that is all under the sea hides nothing worth the test.
			if lowest < WATER_LEVEL - 40.0 and _all_below(verts, WATER_LEVEL - 2.0):
				continue
			var idx := PackedInt32Array()
			for r in rows - 1:
				for c in cols - 1:
					var i := r * cols + c
					idx.append_array([i, i + 1, i + cols, i + 1, i + cols + 1, i + cols])
			var occ := ArrayOccluder3D.new()
			occ.set_arrays(verts, idx)
			var inst := OccluderInstance3D.new()
			inst.name = "Occluder_%d_%d" % [tx, tz]
			inst.occluder = occ
			add_child(inst)

static func _all_below(verts: PackedVector3Array, y: float) -> bool:
	for v in verts:
		if v.y > y:
			return false
	return true

## The region map's land: welded plates (see Facets), a mesh and a collision
## shape per tile, and the water over every wet cell.
func _build_plates(mat: Material) -> void:
	facets = Facets.new(self)
	await facets.build(_loading_tree())
	for t: Facets.TileBuf in facets.tiles:
		if t.tris.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = t.tris
		arrays[Mesh.ARRAY_NORMAL] = t.normals
		arrays[Mesh.ARRAY_COLOR] = t.colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = "Plates_%d_%d" % [t.x0, t.z0]
		mi.mesh = mesh
		mi.material_override = mat
		add_child(mi)
		_land_meshes.append(mi)
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(t.tris)
		cs.shape = shape
		add_child(cs)
	var water := PackedVector3Array()
	var chunks := int(ceil(float(_cells) / float(CHUNK)))
	for cz in chunks:
		for cx in chunks:
			var x0 := cx * CHUNK
			var z0 := cz * CHUNK
			var x1 := mini(_cells, x0 + CHUNK)
			var z1 := mini(_cells, z0 + CHUNK)
			var wet := 0
			for iz in range(z0, z1):
				for ix in range(x0, x1):
					wet += int(_wet(ix, iz))
			if wet == (x1 - x0) * (z1 - z0):
				_quad_into(water, x0, z0, x1, z1, WATER_LEVEL - 0.02)
			elif wet > 0:
				for iz in range(z0, z1):
					for ix in range(x0, x1):
						if _wet(ix, iz):
							_quad_into(water, ix, iz, ix + 1, iz + 1, WATER_LEVEL - 0.02)
	_build_sheets(PackedVector3Array(), water)

## One plate's colour, from where it is and which way it faces: grass, sand,
## snow, bare rock on the steep, with a small difference plate to plate so
## the seams read.
func panel_color(centre: Vector3, normal: Vector3, seed: int) -> Color:
	var ix := clampi(int(_grid_coord(centre.x)), 0, _cells)
	var iz := clampi(int(_grid_coord(centre.z)), 0, _cells)
	var biome := _biomes[_index(ix, iz)] as Biome
	var color: Color
	if normal.y < 0.62:
		color = TOON_ROCK[biome]
	else:
		color = _toon_ground(ix, iz, centre.y, biome)
		# Getting steeper, the grass wears to rock.
		color = color.lerp(TOON_ROCK[biome], smoothstep(0.86, 0.64, normal.y) * 0.6)
	var j := float(posmod(hash(seed), 1000)) / 1000.0 - 0.5
	return color.lightened(j * 0.10) if j > 0.0 else color.darkened(-j * 0.10)

class ChunkBuf:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	## The flat sea bed where no land cell is drawn, and the water surface
	## over every cell with any of it below the water line - each one quad for
	## a chunk that is all sea. Kept to where the sea is, so neither sheet runs
	## through the caves under the land.
	var sea := PackedVector3Array()
	var water := PackedVector3Array()

func _chunk_task(i: int, bufs: Array, chunks: int) -> void:
	var cx := i % chunks
	var cz := i / chunks
	_chunk_arrays(bufs[i], cx * CHUNK, cz * CHUNK, mini(_cells, (cx + 1) * CHUNK),
		mini(_cells, (cz + 1) * CHUNK))

## The open sea floor is drawn flat (see `_build_sheets`), so a cell
## lying flat on it is not drawn again.
const SEA_FLOOR := -7.0

func _drawn(ix: int, iz: int) -> bool:
	if _holes[iz * _cells + ix] != 0:
		return false
	return _heights[_index(ix, iz)] > SEA_FLOOR + 0.01 or _heights[_index(ix + 1, iz)] > SEA_FLOOR + 0.01 \
		or _heights[_index(ix, iz + 1)] > SEA_FLOOR + 0.01 or _heights[_index(ix + 1, iz + 1)] > SEA_FLOOR + 0.01

## The sea bed and the water surface, drawn only where the sea is; and past
## the edge of the map, open water out to the horizon.
func _build_sheets(sea: PackedVector3Array, water: PackedVector3Array) -> void:
	if not sea.is_empty():
		var bed := StandardMaterial3D.new()
		bed.albedo_color = BED_COLOR
		bed.roughness = 1.0
		add_child(_flat_mesh(sea, bed, "SeaBed"))
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.18, 0.34, 0.46, 0.72) if not _plated() else Color(0.10, 0.42, 0.78, 0.86)
	mat.roughness = 0.15
	mat.metallic = 0.2 if not _plated() else 0.05
	var outer := PackedVector3Array()
	var h := half_extent
	var far := half_extent * 4.0
	var y := WATER_LEVEL - 0.02
	for r in [[-far, -far, far, -h], [-far, h, far, far], [-far, -h, -h, h], [h, -h, far, h]]:
		var p00 := Vector3(r[0], y, r[1])
		var p10 := Vector3(r[2], y, r[1])
		var p01 := Vector3(r[0], y, r[3])
		var p11 := Vector3(r[2], y, r[3])
		outer.append_array(PackedVector3Array([p00, p11, p01, p00, p10, p11]))
	water.append_array(outer)
	add_child(_flat_mesh(water, mat, "Water"))
	# The sea bed goes on past the edge of the map too, so open water looks
	# the same inside the map and out.
	if _open_sea():
		var bed_out := PackedVector3Array()
		for i in range(0, outer.size()):
			bed_out.append(Vector3(outer[i].x, SEA_FLOOR, outer[i].z))
		var bed2 := StandardMaterial3D.new()
		bed2.albedo_color = BED_COLOR
		bed2.roughness = 1.0
		add_child(_flat_mesh(bed_out, bed2, "SeaBedOuter"))

func _flat_mesh(verts: PackedVector3Array, mat: Material, label: String) -> MeshInstance3D:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _wet(ix: int, iz: int) -> bool:
	return minf(minf(_heights[_index(ix, iz)], _heights[_index(ix + 1, iz)]),
		minf(_heights[_index(ix, iz + 1)], _heights[_index(ix + 1, iz + 1)])) < WATER_LEVEL

## A flat, face-up rectangle of grid cells at height `y`.
func _quad_into(out: PackedVector3Array, ix0: int, iz0: int, ix1: int, iz1: int, y: float) -> void:
	var xa := -half_extent + float(ix0) * CELL
	var za := -half_extent + float(iz0) * CELL
	var xb := -half_extent + float(ix1) * CELL
	var zb := -half_extent + float(iz1) * CELL
	var p00 := Vector3(xa, y, za)
	var p10 := Vector3(xb, y, za)
	var p01 := Vector3(xa, y, zb)
	var p11 := Vector3(xb, y, zb)
	out.append_array(PackedVector3Array([p00, p11, p01, p00, p10, p11]))

func _chunk_arrays(buf: ChunkBuf, x0: int, z0: int, x1: int, z1: int) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var count := 0
	var wet := 0
	for iz in range(z0, z1):
		for ix in range(x0, x1):
			count += int(_drawn(ix, iz))
			wet += int(_wet(ix, iz))
	var cells := (x1 - x0) * (z1 - z0)
	if count == 0:
		_quad_into(buf.sea, x0, z0, x1, z1, SEA_FLOOR)
	else:
		for iz in range(z0, z1):
			for ix in range(x0, x1):
				if not _drawn(ix, iz) and _holes[iz * _cells + ix] == 0:
					_quad_into(buf.sea, ix, iz, ix + 1, iz + 1, SEA_FLOOR)
	if wet == cells:
		_quad_into(buf.water, x0, z0, x1, z1, WATER_LEVEL - 0.02)
	elif wet > 0:
		for iz in range(z0, z1):
			for ix in range(x0, x1):
				if _wet(ix, iz):
					_quad_into(buf.water, ix, iz, ix + 1, iz + 1, WATER_LEVEL - 0.02)
	if count == 0:
		return
	verts.resize(count * 6)
	normals.resize(verts.size())
	colors.resize(verts.size())
	var v := 0
	for iz in range(z0, z1):
		for ix in range(x0, x1):
			if not _drawn(ix, iz):
				continue
			var xa := -half_extent + float(ix) * CELL
			var za := -half_extent + float(iz) * CELL
			var p00 := Vector3(xa, _heights[_index(ix, iz)], za)
			var p10 := Vector3(xa + CELL, _heights[_index(ix + 1, iz)], za)
			var p01 := Vector3(xa, _heights[_index(ix, iz + 1)], za + CELL)
			var p11 := Vector3(xa + CELL, _heights[_index(ix + 1, iz + 1)], za + CELL)
			# Wound clockwise seen from above, because that is the front face for
			# both Godot's renderer and its collision shapes. Wound the other
			# way the land is one enormous back face: invisible from above, and
			# with nothing solid to stand on.
			for k in 2:
				var t0 := p00
				var t1 := p11 if k == 0 else p10
				var t2 := p01 if k == 0 else p11
				verts[v] = t0
				verts[v + 1] = t1
				verts[v + 2] = t2
				var normal: Vector3 = (t2 - t0).cross(t1 - t0).normalized()
				# Coloured per face: a flat top is ground, a steep face is rock.
				var color := _face_color(ix, iz, (t0.y + t1.y + t2.y) / 3.0, normal)
				normals[v] = normal
				normals[v + 1] = normal
				normals[v + 2] = normal
				colors[v] = color
				colors[v + 1] = color
				colors[v + 2] = color
				v += 3
	buf.verts = verts
	buf.normals = normals
	buf.colors = colors

## Bright, simple ground: grass, sand, snow, a shade apart shelf to shelf.
const TOON_GROUND := {
	Biome.WOODLAND: Color(0.30, 0.58, 0.20),
	Biome.SWAMP: Color(0.34, 0.46, 0.16),
	Biome.DESERT: Color(0.92, 0.70, 0.38),
	Biome.MOUNTAIN: Color(0.32, 0.52, 0.26),
	Biome.TAIGA: Color(0.20, 0.48, 0.30),
	Biome.SNOW: Color(0.95, 0.97, 1.0),
	Biome.ICE: Color(0.66, 0.86, 0.98),
	Biome.ASH: Color(0.25, 0.23, 0.24),
}
const TOON_ROCK := {
	Biome.WOODLAND: Color(0.52, 0.53, 0.58),
	Biome.SWAMP: Color(0.50, 0.48, 0.44),
	Biome.DESERT: Color(0.90, 0.56, 0.54),
	Biome.MOUNTAIN: Color(0.55, 0.55, 0.60),
	Biome.TAIGA: Color(0.49, 0.50, 0.56),
	Biome.SNOW: Color(0.68, 0.73, 0.84),
	Biome.ICE: Color(0.60, 0.76, 0.90),
	Biome.ASH: Color(0.33, 0.22, 0.20),
}
const TOON_BEACH := Color(0.97, 0.89, 0.66)

func _toon_ground(ix: int, iz: int, height: float, biome: Biome) -> Color:
	var color: Color = TOON_GROUND[biome]
	if height < WATER_LEVEL - 0.3:
		return TOON_BEACH.darkened(0.2)
	# Sand only right at the water's edge: low ground away from the water is
	# still grass (the plain round home sits barely above the sea).
	if height < 0.9 and biome != Biome.SWAMP and biome != Biome.SNOW and _near_water(ix, iz):
		return TOON_BEACH
	if biome == Biome.MOUNTAIN and height > 60.0:
		color = color.lerp(Color(0.56, 0.62, 0.46), smoothstep(60.0, 90.0, height))
	for f in features:
		if String(f.kind) != "crater":
			continue
		var d := Vector2(-half_extent + (float(ix) + 0.5) * CELL, -half_extent + (float(iz) + 0.5) * CELL).distance_to(f.centre)
		var r: float = float(f.radius)
		if d < r * 1.35 and height >= WATER_LEVEL - 0.2:
			return Color(0.26, 0.22, 0.26).lerp(Color(0.50, 0.38, 0.36), clampf(d / (r * 1.35), 0.0, 1.0))
	return color

func _rock_color(biome: Biome, at: Vector3) -> Color:
	var color: Color = TOON_ROCK[biome]
	var j := float(hash(Vector3i(int(at.x * 3.0), int(at.y * 3.0), int(at.z * 3.0))) % 100) / 100.0 - 0.5
	return color.lightened(j * 0.14) if j > 0.0 else color.darkened(-j * 0.14)

func _face_color(ix: int, iz: int, height: float, normal: Vector3) -> Color:
	var index := _index(ix, iz)
	var biome := _biomes[index] as Biome
	var steep := normal.y < CLIFF_NORMAL_Y
	var color: Color
	if _road_mask[index] != 0 and not steep:
		color = ROAD_COLOR
	elif height < WATER_LEVEL - 0.2:
		color = BED_COLOR
	elif not steep and biome != Biome.SWAMP and biome != Biome.SNOW and height < WATER_LEVEL + 1.4 \
			and _near_water(ix, iz):
		color = SHORE_COLOR
	elif steep:
		color = CLIFF_COLORS[biome]
		# Darker the steeper, so a cliff reads as a cliff and a riser as a step.
		color = color.darkened(clampf((CLIFF_NORMAL_Y - normal.y) * 0.6, 0.0, 0.25))
	else:
		color = BIOME_COLORS[biome]
		# Each terrace a shade apart from the next, so the bands read at a
		# distance the way contour lines do.
		var step: float = TERRACE_STEP[biome]
		if step > 0.0 and int(floorf(height / step + 0.2)) % 2 == 1:
			color = color.darkened(0.05)
	# A crater is scorched: black glassy rock, darker toward the middle.
	for f in features:
		if String(f.kind) != "crater":
			continue
		var c: Vector2 = f.centre
		var d := Vector2(-half_extent + (float(ix) + 0.5) * CELL - c.x, -half_extent + (float(iz) + 0.5) * CELL - c.y).length()
		var r: float = float(f.radius)
		if d < r * 1.35 and height >= WATER_LEVEL - 0.2:
			color = Color(0.20, 0.17, 0.19).lerp(Color(0.42, 0.30, 0.26), clampf(d / (r * 1.35), 0.0, 1.0))
	# A little variation per facet, keyed off the cell, so neighbouring quads
	# differ without needing a texture.
	var jitter := float((ix * 73 + iz * 151) % 17) / 17.0 - 0.5
	return color.lightened(jitter * 0.07) if jitter > 0.0 else color.darkened(-jitter * 0.07)

## Sand only where the water actually is: a cell with water within a cell of it.
func _near_water(ix: int, iz: int) -> bool:
	for dz in range(-1, 3):
		for dx in range(-1, 3):
			if _heights[_index(ix + dx, iz + dz)] < WATER_LEVEL - 0.05:
				return true
	return false

# --- Requested sites ---------------------------------------------------------

func _place_requested_sites() -> void:
	found_sites.clear()
	for request in site_requests:
		var wanted: Array = request.get("biomes", [])
		var radius: float = float(request.get("radius", 10.0))
		var near: float = float(request.get("near", 100.0))
		var far: float = float(request.get("far", half_extent))
		var best_score := -INF
		var best := Vector3.ZERO
		var stride := 3 if _cells <= 160 else 5
		for iz in range(3, _cells - 2, stride):
			for ix in range(3, _cells - 2, stride):
				var p := Vector3(-half_extent + float(ix) * CELL, 0.0, -half_extent + float(iz) * CELL)
				var from_middle := p.length()
				if from_middle < near or from_middle > far:
					continue
				if absf(p.x) > half_extent - radius - 20.0 or absf(p.z) > half_extent - radius - 20.0:
					continue
				if not wanted.has(int(_biomes[_index(ix, iz)])):
					continue
				if request.has("toward") and Vector2(p.x, p.z).normalized().dot(request.toward) < 0.6:
					continue
				var score := _site_score(p, radius)
				if request.get("high", false) and score > -INF:
					score += height_at(p.x, p.z) * 0.08
				if score > best_score:
					best_score = score
					best = p
		if best_score == -INF:
			continue
		var level := maxf(WATER_LEVEL + 0.6, snappedf(_mean_height(best, radius), 0.25))
		best.y = level
		found_sites[String(request.get("name", "site"))] = best
		reserve_site(best, radius)

## Flatter is better; roads, water, other sites and other finds rule a spot out.
func _site_score(p: Vector3, radius: float) -> float:
	if _in_build_site(p.x, p.z) or _feature_at(p.x, p.z).size() > 0:
		return -INF
	for other in found_sites.values():
		if (other as Vector3).distance_to(Vector3(p.x, other.y, p.z)) < 140.0:
			return -INF
	var lo := INF
	var hi := -INF
	for i in 9:
		var q := p
		if i > 0:
			var a := TAU * float(i) / 8.0
			q += Vector3(cos(a), 0.0, sin(a)) * radius
		if is_road(q.x, q.z) or height_at(q.x, q.z) < WATER_LEVEL + 0.3:
			return -INF
		var h := height_at(q.x, q.z)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var q := p + Vector3(cos(a), 0.0, sin(a)) * (radius + 14.0)
		if is_road(q.x, q.z):
			return -INF
	# A tie-break that is steady for a seed but not always the first cell found.
	var jitter := float(hash(Vector2i(int(p.x), int(p.z))) % 1000) / 1000.0
	return -(hi - lo) + jitter * 0.8

func _mean_height(p: Vector3, radius: float) -> float:
	var total := height_at(p.x, p.z)
	for i in 8:
		var a := TAU * float(i) / 8.0
		total += height_at(p.x + cos(a) * radius, p.z + sin(a) * radius)
	return total / 9.0

# --- Caves -------------------------------------------------------------------

## How far behind the mouth the hill has to have risen.
const SHAFT_REAR := 26.0

## True near a cave mouth, where nothing should grow or be dropped.
func in_cave_zone(x: float, z: float) -> bool:
	for cave in caves:
		var e: Vector3 = cave.entrance
		var d: Vector3 = cave.dir
		var centre := e + d * Cave.SHAFT_LENGTH * 0.5
		if Vector2(x - centre.x, z - centre.z).length() < 16.0:
			return true
	return false

## Looks for places a cave can go: at the foot of high ground, facing into it,
## with enough rock over the whole of the tunnel and chamber that nothing pokes
## out of the hillside, and high enough that the chamber floor stays above the
## water line. The mouth is levelled and the shaft cells are cut out of the
## ground; `Cave` builds everything else.
func _plan_caves() -> void:
	caves.clear()
	if cave_count <= 0:
		return
	var wanted := [Biome.MOUNTAIN, Biome.SNOW, Biome.TAIGA, Biome.DESERT, Biome.WOODLAND]
	var dirs := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var candidates: Array = []
	var margin := 90.0
	# A big map is searched more coarsely; there is plenty of hill to choose from.
	var stride := 2 if _cells <= 160 else 4
	for iz in range(2, _cells - 1, stride):
		for ix in range(2, _cells - 1, stride):
			var corner := Vector3(-half_extent + float(ix) * CELL, 0.0, -half_extent + float(iz) * CELL)
			if absf(corner.x) > half_extent - margin or absf(corner.z) > half_extent - margin:
				continue
			if not wanted.has(int(_biomes[_index(ix, iz)])):
				continue
			if corner.length() < 110.0:
				continue
			for dir in dirs:
				var side := Vector3(-dir.z, 0.0, dir.x)
				var entrance := corner + side * Cave.SHAFT_WIDTH * 0.5
				var score := _cave_score(entrance, dir)
				if score > 0.0:
					candidates.append([score, entrance, dir])
	candidates.sort_custom(func(a, b): return a[0] > b[0])
	var names := ["Glimmer Cave", "Old Seam", "Frostvein Hollow", "Deepcut", "Echo Mine",
		"Crystal Throat", "Wormhole Drift", "Lantern Gallery", "Hollow King", "Blackwater Sink",
		"Sandglass Hole", "Rimefall", "Moonmilk Grotto", "Cinder Vent", "Spore Hollow",
		"Drowned Stair", "Whistling Adit", "Bramble Pit", "Gull's Throat", "Lastlight"]
	var spacing := 150.0 if not _open_sea() else 280.0
	var zones: Array = cave_zones if not cave_zones.is_empty() else \
		[{"centre": Vector2.ZERO, "radius": INF, "count": cave_count}]
	for zone in zones:
		var taken := 0
		for c in candidates:
			if taken >= int(zone.count):
				break
			var at: Vector3 = c[1]
			if Vector2(at.x, at.z).distance_to(zone.centre) > float(zone.radius):
				continue
			if _take_cave(c, spacing, names):
				taken += 1

func _take_cave(c: Array, spacing: float, names: Array) -> bool:
	var entrance: Vector3 = c[1]
	var clear := true
	for other in caves:
		if (other.entrance as Vector3).distance_to(entrance) < spacing:
			clear = false
			break
	if not clear:
		return false
	var dir: Vector3 = c[2]
	var ground := height_at(entrance.x, entrance.z)
	entrance.y = ground
	caves.append({"entrance": entrance, "dir": dir, "ground": ground,
		"name": names[caves.size() % names.size()]})
	# Level the mouth and the approach to it.
	# A good yard in front of the door, to drive up to and turn round in.
	reserve_site(Vector3(entrance.x, ground, entrance.z) - dir * 6.0, 20.0)
	return true

## Cuts each cave's way in out of the ground, once the land is final: the
## level passage, and on down the slope every cell whose ground would come
## down through the tunnel - otherwise the hillside closes the passage off
## where the slope starts, a wall of grass across the way in. Each cell cut
## past the door gets a cap of rock (`caps`: along, top, both relative to the
## mouth) for `Cave` to build, so the hill has no hole in it.
func _cut_cave_holes() -> void:
	for cave in caves:
		var e: Vector3 = cave.entrance
		var dir: Vector3 = cave.dir
		var ground := float(cave.ground)
		var caps: Array = []
		var k := 0
		while float(k) * CELL < Cave.SHAFT_LENGTH + Cave.TUNNEL_LENGTH:
			var z0 := float(k) * CELL
			var p: Vector3 = e + dir * (z0 + CELL * 0.5)
			var gx := int(floor(_grid_coord(p.x)))
			var gz := int(floor(_grid_coord(p.z)))
			if gx < 0 or gz < 0 or gx >= _cells or gz >= _cells:
				break
			var lo := INF
			var hi := -INF
			for c in [[0, 0], [1, 0], [0, 1], [1, 1]]:
				var h := _heights[_index(gx + int(c[0]), gz + int(c[1]))]
				lo = minf(lo, h)
				hi = maxf(hi, h)
			var in_shaft := z0 < Cave.SHAFT_LENGTH
			if not in_shaft and lo > ground + Cave.roof_at(z0) + 1.0:
				break
			_holes[gz * _cells + gx] = 1
			if not in_shaft:
				caps.append([z0, hi - ground])
			k += 1
		cave["caps"] = caps

## How much rock is over a cave dug here, in metres of spare cover; zero or
## less means no.
func _cave_score(entrance: Vector3, dir: Vector3) -> float:
	var ground := height_at(entrance.x, entrance.z)
	if ground < Cave.CHAMBER_DROP + 1.0:
		return 0.0           # the chamber floor would be under the water line
	if _in_pit(entrance.x, entrance.z, 80.0):
		return 0.0           # the quarry keeps its ground to itself
	var side := Vector3(-dir.z, 0.0, dir.x)
	# The mouth faces open ground: nothing much higher than it for a way out in
	# front, or levelling it digs a crater rather than a doorway.
	var z_out := -24.0
	while z_out <= -6.0:
		for x_out in [-8.0, 0.0, 8.0]:
			var q: Vector3 = entrance + dir * z_out + side * x_out
			if height_at(q.x, q.z) > ground + 1.0:
				return 0.0
		z_out += 6.0
	# And the hill rises behind it, so it goes in under something.
	var behind: Vector3 = entrance + dir * (SHAFT_REAR)
	if height_at(behind.x, behind.z) < ground + 4.0:
		return 0.0
	# Nothing in the way of the mouth: roads, rivers and other sites.
	for along in [-10.0, 0.0, 6.0, 12.0]:
		var p: Vector3 = entrance + dir * along
		if is_road(p.x, p.z) or water_depth(p.x, p.z) > 0.0 or _in_build_site(p.x, p.z):
			return 0.0
	var spare := INF
	var z := Cave.COVERED_FROM
	while z <= Cave.FOOTPRINT_LENGTH + 2.0:
		var x := -Cave.CHAMBER_WIDTH * 0.5 - 2.0
		while x <= Cave.CHAMBER_WIDTH * 0.5 + 2.0:
			var p: Vector3 = entrance + dir * z + side * x
			if absf(p.x) > half_extent - 4.0 or absf(p.z) > half_extent - 4.0:
				return 0.0
			var needed := ground + Cave.roof_at(z) + 0.8
			spare = minf(spare, height_at(p.x, p.z) - needed)
			if spare <= 0.0:
				return 0.0
			x += 4.0
		z += 4.0
	# Some cover is enough; beyond that prefer caves nearer the middle of the
	# map, so they are a trip but not a pilgrimage. On an island map they are
	# spread about instead, near and far alike.
	if _open_sea():
		return minf(spare, 6.0) + float(hash(Vector2i(int(entrance.x), int(entrance.z))) % 1000) / 50.0
	return minf(spare, 6.0) + 60.0 / (1.0 + entrance.length() / 100.0)

# --- The map -------------------------------------------------------------------

## The land drawn from above, one pixel per `scale` metres: ground colours,
## water, roads, with hill shading, for the journal's map.
func map_image(px_per_cell: int = 2) -> Image:
	# One pixel per cell, then scaled up: the cells are what the land is made
	# of, so drawing each several times over only costs time.
	var img := Image.create(_cells, _cells, false, Image.FORMAT_RGBA8)
	var sun := Vector3(-0.6, 0.75, -0.4).normalized()
	for iz in _cells:
		for ix in _cells:
			var h00 := _heights[_index(ix, iz)]
			var h10 := _heights[_index(ix + 1, iz)]
			var h01 := _heights[_index(ix, iz + 1)]
			var normal := Vector3(h00 - h10, CELL, h00 - h01).normalized()
			var height := (h00 + h10 + h01 + _heights[_index(ix + 1, iz + 1)]) * 0.25
			var color: Color
			if height < WATER_LEVEL - 0.05:
				color = Color(0.20, 0.42, 0.60).darkened(clampf(-height * 0.08, 0.0, 0.3))
			else:
				color = _face_color(ix, iz, height, normal) if not _plated() \
					else _map_color(ix, iz, height)
				color = color.darkened(clampf(0.35 - normal.dot(sun) * 0.45, 0.0, 0.4))
			img.set_pixel(ix, iz, color)
	if px_per_cell > 1:
		img.resize(_cells * px_per_cell, _cells * px_per_cell, Image.INTERPOLATE_NEAREST)
	_draw_roads(img)
	return img

## The roads on the map, drawn over the land at their own width.
func _draw_roads(img: Image) -> void:
	var scale := float(img.get_width()) / (half_extent * 2.0)
	var r := maxi(1, int(round(4.0 * scale)))
	for road in road_paths:
		var dirt := String(road.get("style", "")) == "dirt"
		var color := Color(0.80, 0.66, 0.48) if dirt else Color(0.86, 0.85, 0.80)
		var path: Array = road.path
		var span := _path_length(path)
		var along := 0.0
		while along <= span:
			var p := _point_along(path, along)
			var cx := int((p.x + half_extent) * scale)
			var cz := int((p.z + half_extent) * scale)
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if dx * dx + dz * dz > r * r:
						continue
					var x := cx + dx
					var z := cz + dz
					if x >= 0 and z >= 0 and x < img.get_width() and z < img.get_height():
						img.set_pixel(x, z, color)
			along += maxf(1.0, 1.0 / scale)

## A cell's colour on the map: its ground, or rock where it is steep.
func _map_color(ix: int, iz: int, height: float) -> Color:
	var biome := _biomes[_index(ix, iz)] as Biome
	var rise := absf(_heights[_index(ix + 1, iz + 1)] - _heights[_index(ix, iz)])
	if rise > CELL * 1.6:
		return TOON_ROCK[biome]
	return _toon_ground(ix, iz, height, biome)

## Map pixel for a world position, in an image from `map_image`.
func map_pixel(point: Vector3, image_size: float) -> Vector2:
	return Vector2((point.x + half_extent) / (half_extent * 2.0),
		(point.z + half_extent) / (half_extent * 2.0)) * image_size
