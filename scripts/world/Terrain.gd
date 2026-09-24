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

enum Biome { WOODLAND, SWAMP, DESERT, MOUNTAIN, TAIGA, SNOW }

## Metres per quad. Bigger is coarser and cheaper; this is the knob for both.
const CELL := 6.0
## Anything below this is under water.
const WATER_LEVEL := 0.0
## How wide a road is graded, and how much faster it is to drive on.
## Half the carriageway. This has to be comfortably wider than a terrain cell,
## or the road is narrower than the grid that represents it and "flat across"
## stops meaning anything - which is what a 4.5 m half-width on a 6 m grid was.
const ROAD_HALF_WIDTH := 9.0
## Beyond the carriageway the grade blends back into whatever the land was
## doing, so a road does not sit on a plinth. It has to be generous: a short
## shoulder on steep ground is a cliff at the roadside, and because the heightfield
## is sampled between grid points, a sharp step just outside the carriageway
## bleeds back into it.
const ROAD_SHOULDER := 20.0
const ROAD_SPEED_BONUS := 0.18
## The steepest a road is graded, as rise over run.
const MAX_GRADE := 0.1

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

var _cells: int = 0
var _heights: PackedFloat32Array = PackedFloat32Array()
var _biomes: PackedByteArray = PackedByteArray()
var _road_mask: PackedByteArray = PackedByteArray()
## Cells left out of the ground altogether, where a cave's shaft goes down.
var _holes: PackedByteArray = PackedByteArray()

## How many caves to look for. Zero, the default, looks for none, so a test
## terrain is exactly the ground it asks for.
@export var cave_count: int = 0
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

## Flat ground, per biome: the tops of the terraces.
const BIOME_COLORS := {
	Biome.WOODLAND: Color(0.34, 0.56, 0.23),
	Biome.SWAMP: Color(0.30, 0.40, 0.21),
	Biome.DESERT: Color(0.88, 0.75, 0.47),
	Biome.MOUNTAIN: Color(0.47, 0.47, 0.45),
	Biome.TAIGA: Color(0.26, 0.44, 0.31),
	Biome.SNOW: Color(0.88, 0.91, 0.96),
}
## Steep ground, per biome: the risers between terraces, and cliffs.
const CLIFF_COLORS := {
	Biome.WOODLAND: Color(0.47, 0.41, 0.33),
	Biome.SWAMP: Color(0.33, 0.30, 0.23),
	Biome.DESERT: Color(0.80, 0.50, 0.30),
	Biome.MOUNTAIN: Color(0.42, 0.42, 0.45),
	Biome.TAIGA: Color(0.41, 0.40, 0.37),
	Biome.SNOW: Color(0.60, 0.65, 0.74),
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
}

func _ready() -> void:
	collision_layer = Layers.WORLD
	collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	physics_material_override = pm
	_configure_noise()
	generate()

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
	# On the same two triangles the mesh is built from, split corner to
	# corner from (0,0) to (1,1). Blending all four corners instead reads a
	# terrace edge as a slope the ground does not have.
	if fx >= fz:
		return h00 + (h10 - h00) * fx + (h11 - h10) * fz
	return h00 + (h01 - h00) * fz + (h11 - h01) * fx

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
	return ["woodland", "swamp", "desert", "mountains", "taiga", "snowland"][int(biome)]

## How deep the water is over a point. Zero on dry land.
func water_depth(x: float, z: float) -> float:
	return maxf(0.0, WATER_LEVEL - height_at(x, z))

## Spec: roads give a slight speed increase when driven on.
func is_road(x: float, z: float) -> bool:
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
			var height := _heights[index]
			if height <= WATER_LEVEL - max_water:
				continue
			var x := -half_extent + float(ix) * CELL
			var z := -half_extent + float(iz) * CELL
			if _in_build_site(x, z) or _in_crater(x, z):
				continue
			out.append(Vector3(x, height, z))
	return out

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
	return Vector3(point.x, height_at(point.x, point.z) + lift, point.z)

func reserve_site(centre: Vector3, radius: float) -> void:
	build_sites.append({"centre": centre, "radius": radius})

# --- Generation ------------------------------------------------------------

func generate() -> void:
	_lap_ms = Time.get_ticks_msec()
	_cells = int(round(half_extent * 2.0 / CELL))
	var verts := (_cells + 1) * (_cells + 1)
	_heights.resize(verts)
	_biomes.resize(verts)
	_road_mask.resize(verts)

	for iz in _cells + 1:
		for ix in _cells + 1:
			var x := -half_extent + float(ix) * CELL
			var z := -half_extent + float(iz) * CELL
			var sample := _sample(x, z)
			_biomes[_index(ix, iz)] = int(sample[0])
			_heights[_index(ix, iz)] = float(sample[1])

	_lap("heights")
	_holes.resize(_cells * _cells)
	_holes.fill(0)
	bridges.clear()
	_carve_rivers()
	_grade_roads(roads)
	_lap("rivers+roads")
	_place_requested_sites()
	_grade_roads(_spur_roads())
	_lap("sites")
	_plan_caves()
	_lap("caves")
	_flatten_sites()
	_build_mesh()
	_lap("mesh")

var _lap_ms: int = 0

func _lap(what: String) -> void:
	var now := Time.get_ticks_msec()
	if OS.has_environment("PROFILE_LOAD") and _lap_ms > 0:
		print("  terrain: %-14s %5d ms" % [what, now - _lap_ms])
	_lap_ms = now

## Biome and height at a point, from one read of the noise.
func _sample(x: float, z: float) -> Array:
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
			"valley":
				var floor_h: float = float(f.get("floor", 6.0))
				if d <= r:
					return [1.0, Biome.WOODLAND, floor_h]
				# The way in: a gorge the width of a truck through the ridge.
				var gap: float = float(f.get("gap", 0.0))
				var across := absf(off.rotated(-gap).y)
				var along := off.rotated(-gap).x
				if along > 0.0 and across < 9.0:
					return [1.0, Biome.WOODLAND, floor_h]
				var t := (d - r) / (r * 1.6)
				var ridge := floor_h + 46.0 * sin(clampf(t, 0.0, 1.0) * PI * 0.5)
				var w := 1.0 - smoothstep(0.7, 1.0, t)
				return [w, Biome.MOUNTAIN if t < 0.8 else Biome.WOODLAND, ridge]
			"crater":
				var rim_h: float = float(f.get("rim", 9.0))
				var floor_c: float = float(f.get("floor", 2.0))
				if d <= r:
					return [1.0, Biome.MOUNTAIN, lerpf(floor_c, rim_h, pow(d / r, 2.2))]
				var t2 := (d - r) / (r * 1.2)
				return [1.0 - smoothstep(0.3, 1.0, t2), Biome.MOUNTAIN, rim_h * (1.0 - t2 * 0.8)]
	return []

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
		var profile := _road_profile(path, span, floor_h)
		if profile.is_empty():
			continue
		var reach := ROAD_HALF_WIDTH + ROAD_SHOULDER
		var near := _cells_near(path, reach)
		for index in near:
			var d: float = near[index].x
			# A bridged road leaves the water alone: the deck goes over it.
			if bridged and _heights[index] < WATER_LEVEL - 0.05:
				continue
			var target := _profile_height(profile, near[index].y, span)
			# Where a road meets a carved channel it crosses at a ford
			# rather than filling the river in.
			if not bridged and _heights[index] < WATER_LEVEL - 0.3:
				target = minf(target, -0.35)
			# Flat a cell beyond the carriageway too, so no triangle that
			# reaches onto the road has a corner up a bank.
			if d <= ROAD_HALF_WIDTH + CELL:
				_heights[index] = target
				_road_mask[index] = 1
			else:
				var t: float = clampf((d - ROAD_HALF_WIDTH - CELL) / ROAD_SHOULDER, 0.0, 1.0)
				_heights[index] = lerpf(target, _heights[index], smoothstep(0.0, 1.0, t))

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
	for name in spur_sites:
		if not found_sites.has(name):
			continue
		var site: Vector3 = found_sites[name]
		var best := Vector3.ZERO
		var best_d := INF
		for road in roads:
			var path: Array = road.get("path", []) if road is Dictionary else road
			var span := _path_length(path)
			var along := 0.0
			while along <= span:
				var p := _point_along(path, along)
				var d := Vector2(p.x - site.x, p.z - site.z).length()
				if d < best_d:
					best_d = d
					best = p
				along += 12.0
		if best_d == INF or best_d > 700.0:
			continue
		out.append({"path": [Vector3(site.x, 0, site.z), best], "bridge": true})
	return out

## Heights along a road's centre-line, taken off the land it crosses and then
## smoothed twice, which is the difference between a grade and a switchback.
func _road_profile(path: Array, span: float, floor_h: float = -INF) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var steps := maxi(2, int(ceil(span / CELL)))
	for i in steps + 1:
		var point := _point_along(path, span * float(i) / float(steps))
		out.append(maxf(floor_h, height_at(point.x, point.z)))
	for pass_index in 2:
		var smoothed := out.duplicate()
		for i in range(1, out.size() - 1):
			smoothed[i] = (out[i - 1] + out[i] * 2.0 + out[i + 1]) * 0.25
		out = smoothed
	# No steeper than a truck can climb: where the land is, the road goes
	# through it in a cutting instead of up the face.
	var rise := MAX_GRADE * span / float(steps)
	for i in range(1, out.size()):
		out[i] = minf(out[i], out[i - 1] + rise)
	for i in range(out.size() - 2, -1, -1):
		out[i] = minf(out[i], out[i + 1] + rise)
	return out

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

func _build_mesh() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	var chunks := int(ceil(float(_cells) / float(CHUNK)))
	for cz in chunks:
		for cx in chunks:
			_build_chunk(cx * CHUNK, cz * CHUNK, mini(_cells, (cx + 1) * CHUNK),
				mini(_cells, (cz + 1) * CHUNK), mat)
	_build_sea_floor()
	_build_water()

## The open sea floor is one flat sheet (see `_build_sea_floor`), so a cell
## lying flat on it is not drawn again.
const SEA_FLOOR := -7.0

func _drawn(ix: int, iz: int) -> bool:
	if _holes[iz * _cells + ix] != 0:
		return false
	return _heights[_index(ix, iz)] > SEA_FLOOR + 0.01 or _heights[_index(ix + 1, iz)] > SEA_FLOOR + 0.01 \
		or _heights[_index(ix, iz + 1)] > SEA_FLOOR + 0.01 or _heights[_index(ix + 1, iz + 1)] > SEA_FLOOR + 0.01

## Under the open sea: one plane to see and one to land on.
func _build_sea_floor() -> void:
	if islands.is_empty():
		return
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(half_extent * 8.0, half_extent * 8.0)
	mi.mesh = plane
	mi.position = Vector3(0, SEA_FLOOR - 0.01, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BED_COLOR
	mat.roughness = 1.0
	mi.material_override = mat
	add_child(mi)
	# A thick slab rather than a boundary plane: its top is the sea floor.
	var cs := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(half_extent * 4.0, 4.0, half_extent * 4.0)
	cs.shape = slab
	cs.position = Vector3(0, SEA_FLOOR - 2.0, 0)
	add_child(cs)

func _build_chunk(x0: int, z0: int, x1: int, z1: int, mat: Material) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var count := 0
	for iz in range(z0, z1):
		for ix in range(x0, x1):
			count += int(_drawn(ix, iz))
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
				var normal: Vector3 = (t2 - t0).cross(t1 - t0).normalized()
				# Coloured per face: a flat top is ground, a steep face is rock.
				var color := _face_color(ix, iz, (t0.y + t1.y + t2.y) / 3.0, normal)
				verts[v] = t0
				verts[v + 1] = t1
				verts[v + 2] = t2
				normals[v] = normal
				normals[v + 1] = normal
				normals[v + 2] = normal
				colors[v] = color
				colors[v + 1] = color
				colors[v + 2] = color
				v += 3
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(verts)
	cs.shape = shape
	add_child(cs)

## One sheet at the water line. With the land mostly above it, it only shows in
## the river channels and the low ground, which is exactly where water belongs.
func _build_water() -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	# Out to the horizon: the island sits in open water.
	plane.size = Vector2(half_extent * 8.0, half_extent * 8.0)
	mi.mesh = plane
	mi.position = Vector3(0, WATER_LEVEL - 0.02, 0)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.18, 0.34, 0.46, 0.72)
	mat.roughness = 0.15
	mat.metallic = 0.2
	mi.material_override = mat
	add_child(mi)

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
		"Crystal Throat", "Wormhole Drift", "Lantern Gallery", "Hollow King", "Starless Deep"]
	var spacing := 150.0 if islands.is_empty() else 280.0
	for c in candidates:
		if caves.size() >= cave_count:
			break
		var entrance: Vector3 = c[1]
		var clear := true
		for other in caves:
			if (other.entrance as Vector3).distance_to(entrance) < spacing:
				clear = false
				break
		if not clear:
			continue
		var dir: Vector3 = c[2]
		var ground := height_at(entrance.x, entrance.z)
		entrance.y = ground
		caves.append({"entrance": entrance, "dir": dir, "ground": ground,
			"name": names[caves.size() % names.size()]})
		# Level the mouth and the approach to it.
		reserve_site(Vector3(entrance.x, ground, entrance.z) + dir * Cave.SHAFT_LENGTH * 0.4, 14.0)
		var side := Vector3(-dir.z, 0.0, dir.x)
		for along in [Cave.SHAFT_LENGTH * 0.25, Cave.SHAFT_LENGTH * 0.75]:
			var p: Vector3 = entrance + dir * along
			var gx := int(floor(_grid_coord(p.x)))
			var gz := int(floor(_grid_coord(p.z)))
			if gx >= 0 and gz >= 0 and gx < _cells and gz < _cells:
				_holes[gz * _cells + gx] = 1

## How much rock is over a cave dug here, in metres of spare cover; zero or
## less means no.
func _cave_score(entrance: Vector3, dir: Vector3) -> float:
	var ground := height_at(entrance.x, entrance.z)
	if ground < Cave.CHAMBER_DROP + 1.0:
		return 0.0           # the chamber floor would be under the water line
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
	var z := Cave.SHAFT_LENGTH
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
	if not islands.is_empty():
		return minf(spare, 6.0) + float(hash(Vector2i(int(entrance.x), int(entrance.z))) % 1000) / 50.0
	return minf(spare, 6.0) + 60.0 / (1.0 + entrance.length() / 100.0)

# --- The map -------------------------------------------------------------------

## The land drawn from above, one pixel per `scale` metres: ground colours,
## water, roads, with hill shading, for the journal's map.
func map_image(px_per_cell: int = 2) -> Image:
	# One pixel per cell, then scaled up: the cells are what the land is made
	# of, so drawing each several times over only costs time.
	var img := Image.create(_cells, _cells, false, Image.FORMAT_RGB8)
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
				color = _face_color(ix, iz, height, normal)
				color = color.darkened(clampf(0.35 - normal.dot(sun) * 0.45, 0.0, 0.4))
			img.set_pixel(ix, iz, color)
	if px_per_cell > 1:
		img.resize(_cells * px_per_cell, _cells * px_per_cell, Image.INTERPOLATE_NEAREST)
	return img

## Map pixel for a world position, in an image from `map_image`.
func map_pixel(point: Vector3, image_size: float) -> Vector2:
	return Vector2((point.x + half_extent) / (half_extent * 2.0),
		(point.z + half_extent) / (half_extent * 2.0)) * image_size
