class_name Landmarks
extends Node3D

## Rock outcrops: big faceted lumps of rock sat about the land, thickest in the
## mountains and the taiga, pink in the desert, snow-dusted in the north. The
## big ones carry a cap of grass. Solid, off the roads, the building sites,
## the cave mouths and the water; nothing else grows where one stands.

const SPACING := 46.0

var terrain: Terrain
var seed_value: int = 1
## Every outcrop: {pos (Vector3, on the ground), size (Vector3), color}.
var rocks: Array[Dictionary] = []

var _body: StaticBody3D
var _tiles: Dictionary = {}         ## tile -> MeshBuf

## How many outcrops each kind of country gets (a chance per spot) and how big.
const KINDS := {
	Terrain.Biome.MOUNTAIN: [0.55, 4.0, 16.0],
	Terrain.Biome.TAIGA: [0.30, 3.0, 11.0],
	Terrain.Biome.SNOW: [0.30, 3.0, 12.0],
	Terrain.Biome.WOODLAND: [0.16, 2.5, 9.0],
	Terrain.Biome.DESERT: [0.20, 3.0, 12.0],
	Terrain.Biome.SWAMP: [0.05, 2.0, 5.0],
}
const CAP := {
	Terrain.Biome.MOUNTAIN: Color(0.40, 0.66, 0.40),
	Terrain.Biome.TAIGA: Color(0.30, 0.60, 0.40),
	Terrain.Biome.SNOW: Color(0.95, 0.97, 1.0),
	Terrain.Biome.WOODLAND: Color(0.42, 0.74, 0.36),
	Terrain.Biome.DESERT: Color(0.96, 0.84, 0.60),
	Terrain.Biome.SWAMP: Color(0.44, 0.60, 0.30),
}

class MeshBuf:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

func setup(p_terrain: Terrain, p_seed: int) -> void:
	terrain = p_terrain
	seed_value = p_seed

func _ready() -> void:
	_body = StaticBody3D.new()
	_body.name = "Outcrops"
	_body.collision_layer = Layers.WORLD
	_body.collision_mask = 0
	add_child(_body)
	var half := terrain.half_extent
	var n := int(half * 2.0 / SPACING)
	for iz in n:
		for ix in n:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(Vector3i(ix, iz, seed_value))
			var p := Vector3(-half + (float(ix) + rng.randf_range(0.1, 0.9)) * SPACING, 0.0,
				-half + (float(iz) + rng.randf_range(0.1, 0.9)) * SPACING)
			_place_at(p, rng)
	_flush()

func _place_at(p: Vector3, rng: RandomNumberGenerator) -> void:
	var ground := terrain.height_at(p.x, p.z)
	if ground < Terrain.WATER_LEVEL + 1.0:
		return
	var biome := terrain.biome_at(p.x, p.z)
	var kind: Array = KINDS[biome]
	if rng.randf() > float(kind[0]):
		return
	var size := rng.randf_range(float(kind[1]), float(kind[2])) * lerpf(0.6, 1.0, rng.randf())
	var tall := rng.randf_range(0.6, 1.2)
	# Now and then a spire in the mountains.
	if biome == Terrain.Biome.MOUNTAIN and rng.randf() < 0.15:
		tall = rng.randf_range(2.0, 3.2)
	var dims := Vector3(size * rng.randf_range(0.8, 1.3), size * tall, size * rng.randf_range(0.8, 1.3))
	var reach := maxf(dims.x, dims.z) * 0.6
	if not _clear(p, reach):
		return
	# Sat on the lowest ground under it, sunk a little, so it never floats
	# off the downhill side.
	var low := ground
	for a in 6:
		var q := p + Vector3(cos(a * TAU / 6.0), 0, sin(a * TAU / 6.0)) * reach
		low = minf(low, terrain.height_at(q.x, q.z))
	var at := Vector3(p.x, low, p.z)
	var rock: Color = Terrain.TOON_ROCK[biome]
	_rock(at, dims, rng.randf() * TAU, rock, CAP[biome] if size > 6.0 else rock, rng)
	rocks.append({"pos": at, "size": dims, "color": rock})
	terrain.mark_blocked(at, reach + 1.5)

func _clear(p: Vector3, reach: float) -> bool:
	for k in 9:
		var q := p
		if k > 0:
			q += Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0)) * (reach + 8.0)
		if terrain.is_road(q.x, q.z) or terrain.water_depth(q.x, q.z) > 0.0 \
				or terrain._in_build_site(q.x, q.z) or terrain.in_cave_zone(q.x, q.z) \
				or terrain.is_blocked(q.x, q.z):
			return false
	for cave in terrain.caves:
		var e: Vector3 = cave.entrance
		if Vector2(e.x - p.x, e.z - p.z).length() < reach + 30.0:
			return false
	return true

## A lump of rock: a squashed, jittered ball of big flat facets, its base sunk
## below the ground, the upward faces capped in `cap`.
func _rock(at: Vector3, dims: Vector3, yaw: float, color: Color, cap: Color, rng: RandomNumberGenerator) -> void:
	var rings := 3
	var around := rng.randi_range(6, 8)
	var pts: Array = []           # rings of points, bottom to top
	var basis := Basis(Vector3.UP, yaw)
	for r in rings + 1:
		var t := float(r) / float(rings)
		var ring: Array = []
		var y := lerpf(-0.25, 1.0, t) * dims.y
		# Widest a little below the middle, narrowing to a flat-ish top.
		var w := sin(lerpf(0.55, 2.7, t)) * 0.6 + 0.2
		if r == rings:
			w = rng.randf_range(0.25, 0.45)
		for i in around:
			var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3) + 0.5 * float(r % 2)) / float(around)
			var j := rng.randf_range(0.8, 1.15)
			var local := Vector3(cos(a) * dims.x * 0.5 * w * j, y + rng.randf_range(-0.08, 0.08) * dims.y,
				sin(a) * dims.z * 0.5 * w * j)
			ring.append(at + basis * local)
		pts.append(ring)
	var top := at + Vector3(0, dims.y * rng.randf_range(1.0, 1.08), 0)
	var tile := Vector2i(int(floor(at.x / 400.0)), int(floor(at.z / 400.0)))
	if not _tiles.has(tile):
		_tiles[tile] = MeshBuf.new()
	var buf: MeshBuf = _tiles[tile]
	var hull := PackedVector3Array()
	for ring: Array in pts:
		for p: Vector3 in ring:
			hull.append(p)
	hull.append(top)
	var centre := at + Vector3(0, dims.y * 0.4, 0)
	for r in rings:
		var lo: Array = pts[r]
		var hi: Array = pts[r + 1]
		for i in around:
			var i2 := (i + 1) % around
			_tri(buf, lo[i], lo[i2], hi[i2], centre, color, cap, rng)
			_tri(buf, lo[i], hi[i2], hi[i], centre, color, cap, rng)
	var last: Array = pts[rings]
	for i in around:
		_tri(buf, last[i], last[(i + 1) % around], top, centre, color, cap, rng)
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = hull
	cs.shape = shape
	_body.add_child(cs)

## A facet facing out from `centre`: rock, or the cap colour if it faces up.
func _tri(buf: MeshBuf, a: Vector3, b: Vector3, c: Vector3, centre: Vector3, color: Color,
		cap: Color, rng: RandomNumberGenerator) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 0.000001:
		return
	var facing := (a + b + c) / 3.0 - centre
	if n.dot(facing) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	var shade := rng.randf_range(-0.06, 0.06)
	var col := cap if n.y > 0.72 else color
	col = col.lightened(shade) if shade > 0.0 else col.darkened(-shade)
	buf.verts.append_array(PackedVector3Array([a, b, c]))
	buf.normals.append_array(PackedVector3Array([n, n, n]))
	buf.colors.append_array(PackedColorArray([col, col, col]))

func _flush() -> void:
	var rock := Textures.material("rock", 10.0)
	for tile in _tiles:
		var buf: MeshBuf = _tiles[tile]
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
		mi.name = "Rocks_%d_%d" % [tile.x, tile.y]
		mi.mesh = mesh
		mi.material_override = rock
		add_child(mi)
	_tiles.clear()
