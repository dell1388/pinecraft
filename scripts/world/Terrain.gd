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
const ROAD_HALF_WIDTH := 4.5
const ROAD_SPEED_BONUS := 0.18

@export var half_extent: float = 300.0
@export var noise_seed: int = 20260921

## Flat pads that must stay flat, whatever the land wants to do: {centre, radius}
var build_sites: Array[Dictionary] = []
## River centre-lines, as arrays of Vector3. Carved down through the land.
var rivers: Array = []
## Road centre-lines, as arrays of Vector3. Graded flat and marked.
var roads: Array = []

var _cells: int = 0
var _heights: PackedFloat32Array = PackedFloat32Array()
var _biomes: PackedByteArray = PackedByteArray()
var _road_mask: PackedByteArray = PackedByteArray()

var _elevation := FastNoiseLite.new()
var _moisture := FastNoiseLite.new()
var _detail := FastNoiseLite.new()

const BIOME_COLORS := {
	Biome.WOODLAND: Color(0.22, 0.36, 0.17),
	Biome.SWAMP: Color(0.24, 0.30, 0.19),
	Biome.DESERT: Color(0.72, 0.62, 0.36),
	Biome.MOUNTAIN: Color(0.40, 0.39, 0.37),
	Biome.TAIGA: Color(0.19, 0.31, 0.24),
	Biome.SNOW: Color(0.86, 0.88, 0.92),
}

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
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)

func height_at_point(point: Vector3) -> float:
	return height_at(point.x, point.z)

func biome_at(x: float, z: float) -> Biome:
	if _biomes.is_empty():
		return Biome.WOODLAND
	return _biomes[_index(int(round(_grid_coord(x))), int(round(_grid_coord(z))))] as Biome

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

## Drops a point onto the ground, which is how anything gets placed out here.
func place(point: Vector3, lift: float = 0.0) -> Vector3:
	return Vector3(point.x, height_at(point.x, point.z) + lift, point.z)

func reserve_site(centre: Vector3, radius: float) -> void:
	build_sites.append({"centre": centre, "radius": radius})

# --- Generation ------------------------------------------------------------

func generate() -> void:
	_cells = int(round(half_extent * 2.0 / CELL))
	var verts := (_cells + 1) * (_cells + 1)
	_heights.resize(verts)
	_biomes.resize(verts)
	_road_mask.resize(verts)

	for iz in _cells + 1:
		for ix in _cells + 1:
			var x := -half_extent + float(ix) * CELL
			var z := -half_extent + float(iz) * CELL
			var biome := _pick_biome(x, z)
			var h := _raw_height(x, z, biome)
			_biomes[_index(ix, iz)] = int(biome)
			_heights[_index(ix, iz)] = h

	_carve_rivers()
	_grade_roads()
	_flatten_sites()
	_build_mesh()

## Spec's biome list, chosen from elevation and moisture rather than from
## hand-drawn regions.
func _pick_biome(x: float, z: float) -> Biome:
	var e := (_elevation.get_noise_2d(x, z) + 1.0) * 0.5
	var m := (_moisture.get_noise_2d(x, z) + 1.0) * 0.5
	# A north-south temperature gradient, so the cold biomes sit together
	# instead of being sprinkled over the whole map.
	var cold: float = clampf(0.5 - z / (half_extent * 2.0), 0.0, 1.0) + (e - 0.5) * 0.6
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

func _raw_height(x: float, z: float, biome: Biome) -> float:
	var spec: Array = BIOME_HEIGHT[biome]
	var e := (_elevation.get_noise_2d(x, z) + 1.0) * 0.5
	var d := _detail.get_noise_2d(x, z)
	var h: float = float(spec[0]) + float(spec[1]) * e + d * 1.2
	# Quantised, so the land steps in facets rather than rolling smoothly.
	return snappedf(h, 0.5)

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
		for iz in _cells + 1:
			for ix in _cells + 1:
				var x := -half_extent + float(ix) * CELL
				var z := -half_extent + float(iz) * CELL
				var here := Vector3(x, 0, z)
				var nearest := _distance_to_path(here, path)
				var d: float = nearest.x
				if d > width * 2.2:
					continue
				# A ford is a stretch where the bed is left shallow enough to
				# drive through; everywhere else wants a bridge.
				var along: float = nearest.y
				var bed := -depth
				for ford in fords:
					var span: float = float(ford.get("width", 22.0))
					if absf(along - float(ford.get("at", 0.0))) < span * 0.5:
						bed = -0.45
						break
				var t: float = clampf(d / maxf(0.5, width), 0.0, 1.0)
				# Flat bed in the channel, then a bank up to the old ground.
				var carved: float = lerpf(bed, _heights[_index(ix, iz)], smoothstep(0.0, 1.0, t))
				_heights[_index(ix, iz)] = minf(_heights[_index(ix, iz)], carved)

## Spec: roads across the land, giving a small speed bonus to drive on.
func _grade_roads() -> void:
	for road in roads:
		var path: Array = road
		if path.size() < 2:
			continue
		for iz in _cells + 1:
			for ix in _cells + 1:
				var x := -half_extent + float(ix) * CELL
				var z := -half_extent + float(iz) * CELL
				var nearest := _distance_to_path(Vector3(x, 0, z), path)
				var d: float = nearest.x
				if d > ROAD_HALF_WIDTH * 2.0:
					continue
				# A road is graded toward the height of its own centre-line, so
				# it does not simply drape over every bump.
				var target: float = _path_height(path, nearest.y)
				var t: float = clampf(d / (ROAD_HALF_WIDTH * 2.0), 0.0, 1.0)
				var index := _index(ix, iz)
				# Where a road meets a carved channel it crosses at a ford
				# rather than filling the river in: shallow enough to drive
				# through, still visibly water.
				if _heights[index] < WATER_LEVEL - 0.3:
					target = -0.35
				_heights[index] = lerpf(target, _heights[index], smoothstep(0.0, 1.0, t))
				if d <= ROAD_HALF_WIDTH:
					_road_mask[index] = 1

## Build sites are levelled last, so nothing the land does afterwards tilts a
## factory floor.
func _flatten_sites() -> void:
	for site in build_sites:
		var centre: Vector3 = site.centre
		var radius: float = float(site.radius)
		var margin: float = radius * 0.45
		for iz in _cells + 1:
			for ix in _cells + 1:
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

func _path_height(path: Array, along: float) -> float:
	var travelled := 0.0
	for i in path.size() - 1:
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var length := Vector2(b.x - a.x, b.z - a.z).length()
		if along <= travelled + length or i == path.size() - 2:
			var t: float = clampf((along - travelled) / maxf(0.001, length), 0.0, 1.0)
			return lerpf(a.y, b.y, t)
		travelled += length
	return path[path.size() - 1].y

# --- Mesh ------------------------------------------------------------------

func _build_mesh() -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(_cells * _cells * 6)
	normals.resize(verts.size())
	colors.resize(verts.size())
	var v := 0
	for iz in _cells:
		for ix in _cells:
			var x0 := -half_extent + float(ix) * CELL
			var z0 := -half_extent + float(iz) * CELL
			var p00 := Vector3(x0, _heights[_index(ix, iz)], z0)
			var p10 := Vector3(x0 + CELL, _heights[_index(ix + 1, iz)], z0)
			var p01 := Vector3(x0, _heights[_index(ix, iz + 1)], z0 + CELL)
			var p11 := Vector3(x0 + CELL, _heights[_index(ix + 1, iz + 1)], z0 + CELL)
			var color := _quad_color(ix, iz, p00.y)
			# Each triangle carries its own normal, which is what makes the land
			# read as facets instead of as a smooth blanket.
			var tris: Array[PackedVector3Array] = [
				PackedVector3Array([p00, p01, p11]),
				PackedVector3Array([p00, p11, p10]),
			]
			for tri in tris:
				var normal: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				for corner in tri:
					verts[v] = corner
					normals[v] = normal
					colors[v] = color
					v += 1

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mi.material_override = mat
	add_child(mi)

	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(verts)
	cs.shape = shape
	add_child(cs)

	_build_water()

## One sheet at the water line. With the land mostly above it, it only shows in
## the river channels and the low ground, which is exactly where water belongs.
func _build_water() -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(half_extent * 2.0, half_extent * 2.0)
	mi.mesh = plane
	mi.position = Vector3(0, WATER_LEVEL, 0)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.18, 0.34, 0.46, 0.72)
	mat.roughness = 0.15
	mat.metallic = 0.2
	mi.material_override = mat
	add_child(mi)

func _quad_color(ix: int, iz: int, height: float) -> Color:
	var index := _index(ix, iz)
	if _road_mask[index] != 0:
		return Color(0.34, 0.31, 0.28)
	if height < WATER_LEVEL - 0.2:
		return Color(0.26, 0.24, 0.19)        # riverbed
	var base: Color = BIOME_COLORS[_biomes[index] as Biome]
	# A little variation per facet, keyed off the cell, so neighbouring quads
	# differ without needing a texture.
	var jitter := float((ix * 73 + iz * 151) % 17) / 17.0 - 0.5
	return base.lightened(jitter * 0.12) if jitter > 0.0 else base.darkened(-jitter * 0.12)
