class_name Facets
extends RefCounted

## The land as welded plates: a handful of big flat panels where the ground is
## a plain slope, many small ones where it is rough, none of it on a grid.
##
## The height grid is split where a flat plate would not follow it closely
## enough - more readily in some country than others, so a hectare of hillside
## can be one plate while a crag next to it is a dozen - and the corners of
## those splits are pushed off the grid so nothing lines up. They are joined
## into triangles, and neighbouring triangles that lie nearly flat to one
## another are welded into one panel, shaded as one sheet. What you see are
## the panels and their seams, not the triangles.
##
## Built per tile, so each tile is its own mesh and collision shape. Tiles
## share the points along their edges exactly, so the panels meet without a
## crack.

const TILE := 64                 ## cells per tile side
const MAX_LEAF := 32             ## the biggest plate, in cells
const WELD_DEGREES := 9.0        ## neighbours flatter than this weld together
const BUCKET := 12.0             ## metres, for finding the triangle under a point

var terrain: Terrain
var tiles: Array = []            ## TileBuf per tile, row-major
var tiles_x: int = 0

class TileBuf:
	var x0: int
	var z0: int
	var x1: int
	var z1: int
	var tris := PackedVector3Array()          ## 3 per triangle, world space
	var face_n := PackedVector3Array()        ## per triangle, before welding
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var buckets: Dictionary = {}              ## Vector2i -> PackedInt32Array of tri indices

func _init(p_terrain: Terrain) -> void:
	terrain = p_terrain

# --- Building ----------------------------------------------------------------

func build() -> void:
	var cells := terrain._cells
	tiles_x = int(ceil(float(cells) / float(TILE)))
	var count := tiles_x * tiles_x
	tiles.clear()
	for i in count:
		var t := TileBuf.new()
		t.x0 = (i % tiles_x) * TILE
		t.z0 = (i / tiles_x) * TILE
		t.x1 = mini(cells, t.x0 + TILE)
		t.z1 = mini(cells, t.z0 + TILE)
		tiles.append(t)
	var task := WorkerThreadPool.add_group_task(_build_tile, count, -1, true, "facets")
	WorkerThreadPool.wait_for_group_task_completion(task)
	# Welded across the whole map at once, so a plate can run over a tile's
	# edge like any other seam-free stretch.
	_weld_all()
	for t: TileBuf in tiles:
		for k in t.tris.size() / 3:
			_bucket(t, k, t.tris[k * 3], t.tris[k * 3 + 1], t.tris[k * 3 + 2])

func _build_tile(i: int) -> void:
	var t: TileBuf = tiles[i]
	var points := {}                           # Vector2i grid point -> leaf size
	_split(t, t.x0, t.z0, maxi(t.x1 - t.x0, t.z1 - t.z0), points)
	# Every tile edge carries the same points as its neighbour's, whichever
	# side split it finer, so the two meet exactly.
	_edge_points(t, points)
	var flat := PackedVector2Array()
	var keys: Array = points.keys()
	for k: Vector2i in keys:
		flat.append(_jittered(k, int(points[k]), t))
	var idx := Geometry2D.triangulate_delaunay(flat)
	var verts := PackedVector3Array()
	verts.resize(flat.size())
	for j in flat.size():
		var p := flat[j]
		verts[j] = Vector3(p.x, terrain.grid_height(p.x, p.y), p.y)
	# Triangles, facing up; the thin slivers a straight edge can leave, gone.
	for k in range(0, idx.size(), 3):
		var a := verts[idx[k]]
		var b := verts[idx[k + 1]]
		var c := verts[idx[k + 2]]
		var n := (c - a).cross(b - a)
		if absf(n.y) < 0.01:
			continue
		var ia := idx[k]
		var ib := idx[k + 1]
		var ic := idx[k + 2]
		if n.y < 0.0:
			var sw := ib
			ib = ic
			ic = sw
			n = -n
		var centre := (a + b + c) / 3.0
		if terrain._is_hole(centre.x, centre.z):
			continue
		# Wound so (c - a) x (b - a) points up: the front face, for drawing
		# and for collision alike.
		t.tris.append_array(PackedVector3Array([verts[ia], verts[ib], verts[ic]]))
		t.face_n.append(n.normalized())

## Splits a square of cells until a flat plate over it is close enough to the
## ground under it. How close is close enough varies across the map.
func _split(t: TileBuf, x: int, z: int, size: int, points: Dictionary) -> void:
	var x1 := mini(x + size, t.x1)
	var z1 := mini(z + size, t.z1)
	if x >= t.x1 or z >= t.z1:
		return
	var must := 0
	if size > 1:
		must = _needs(x, z, x1, z1, size)
	if size > MAX_LEAF or (size > 1 and must > 0 and size > must) or (size > 1 and must == 0 and _error(x, z, x1, z1) > _tolerance(x, z, x1, z1)):
		var h := size / 2
		_split(t, x, z, h, points)
		_split(t, x + h, z, h, points)
		_split(t, x, z + h, h, points)
		_split(t, x + h, z + h, h, points)
		return
	for c in [Vector2i(x, z), Vector2i(x1, z), Vector2i(x, z1), Vector2i(x1, z1)]:
		# Points on the tile's edge are the edge's business (see below).
		if c.x == t.x0 or c.x == t.x1 or c.y == t.z0 or c.y == t.z1:
			continue
		points[c] = mini(int(points.get(c, size)), size)

## The finest a square has to go whatever its shape: cave mouths and roads
## to the cell - so every plate under a road lies on its flat bed and none
## pokes up through it - and the water's edge to two.
func _needs(x0: int, z0: int, x1: int, z1: int, size: int) -> int:
	var stride := maxi(1, size / 8)
	var wet := false
	var dry := false
	var road := false
	for iz in range(z0, z1 + 1, stride):
		for ix in range(x0, x1 + 1, stride):
			if terrain._hole_near(ix, iz):
				return 1
			var i := terrain._index(ix, iz)
			if terrain._road_mask[i] != 0:
				road = true
			if terrain._heights[i] < Terrain.WATER_LEVEL:
				wet = true
			else:
				dry = true
	if road:
		return 1
	if wet and dry:
		return 2
	return 0

## How far the ground strays from a flat plate across the square's corners.
func _error(x0: int, z0: int, x1: int, z1: int) -> float:
	var h00 := terrain._heights[terrain._index(x0, z0)]
	var h10 := terrain._heights[terrain._index(x1, z0)]
	var h01 := terrain._heights[terrain._index(x0, z1)]
	var h11 := terrain._heights[terrain._index(x1, z1)]
	var w := float(maxi(1, x1 - x0))
	var d := float(maxi(1, z1 - z0))
	var stride := maxi(1, (x1 - x0) / 10)
	var worst := 0.0
	for iz in range(z0, z1 + 1, stride):
		var fz := float(iz - z0) / d
		for ix in range(x0, x1 + 1, stride):
			var fx := float(ix - x0) / w
			var flat: float
			if fx >= fz:
				flat = h00 + (h10 - h00) * fx + (h11 - h10) * fz
			else:
				flat = h00 + (h01 - h00) * fz + (h11 - h01) * fx
			worst = maxf(worst, absf(terrain._heights[terrain._index(ix, iz)] - flat))
	return worst

## How closely a plate has to follow the ground here: loosely in broad calm
## country, tightly where the land is meant to look worked and craggy.
func _tolerance(x0: int, z0: int, x1: int, z1: int) -> float:
	var cx := -terrain.half_extent + (float(x0 + x1) * 0.5) * Terrain.CELL
	var cz := -terrain.half_extent + (float(z0 + z1) * 0.5) * Terrain.CELL
	var calm := terrain._warp.get_noise_2d(cx * 2.3 + 500.0, cz * 2.3) * 0.5 + 0.5
	var base: float = BIOME_TOLERANCE.get(terrain.biome_at(cx, cz), 1.0)
	return base * lerpf(0.5, 2.8, smoothstep(0.25, 0.75, calm))

const BIOME_TOLERANCE := {
	Terrain.Biome.WOODLAND: 1.3,
	Terrain.Biome.SWAMP: 0.7,
	Terrain.Biome.DESERT: 1.6,
	Terrain.Biome.MOUNTAIN: 2.2,
	Terrain.Biome.TAIGA: 1.5,
	Terrain.Biome.SNOW: 2.0,
}

## The points along a tile's four edges. An edge is split on its own terms -
## finely enough for the ground either side of it - so the tiles on both
## sides of it come up with exactly the same points.
func _edge_points(t: TileBuf, points: Dictionary) -> void:
	for side in 4:
		var horizontal := side < 2
		var fixed := t.z0 if side == 0 else (t.z1 if side == 1 else (t.x0 if side == 2 else t.x1))
		var a := t.x0 if horizontal else t.z0
		var b := t.x1 if horizontal else t.z1
		_split_edge(horizontal, fixed, a, b, points)

func _split_edge(horizontal: bool, fixed: int, a: int, b: int, points: Dictionary) -> void:
	var size := b - a
	var p0 := Vector2i(a, fixed) if horizontal else Vector2i(fixed, a)
	var p1 := Vector2i(b, fixed) if horizontal else Vector2i(fixed, b)
	var must := 0
	var bad := false
	if size > 1:
		var x0 := mini(p0.x, p1.x)
		var z0 := mini(p0.y, p1.y)
		var x1 := maxi(p0.x, p1.x)
		var z1 := maxi(p0.y, p1.y)
		# A band either side of the edge decides it, as it would for the
		# squares on either side.
		var bx0 := x0 if horizontal else maxi(0, x0 - size / 2)
		var bx1 := x1 if horizontal else mini(terrain._cells, x1 + size / 2)
		var bz0 := maxi(0, z0 - size / 2) if horizontal else z0
		var bz1 := mini(terrain._cells, z1 + size / 2) if horizontal else z1
		must = _needs(bx0, bz0, bx1, bz1, size)
		bad = _edge_error(p0, p1) > _tolerance(bx0, bz0, bx1, bz1)
	if size > 1 and (size > MAX_LEAF or (must > 0 and size > must) or (must == 0 and bad)):
		var m := a + size / 2
		_split_edge(horizontal, fixed, a, m, points)
		_split_edge(horizontal, fixed, m, b, points)
		return
	points[p0] = mini(int(points.get(p0, size)), size)
	points[p1] = mini(int(points.get(p1, size)), size)

func _edge_error(p0: Vector2i, p1: Vector2i) -> float:
	var h0 := terrain._heights[terrain._index(p0.x, p0.y)]
	var h1 := terrain._heights[terrain._index(p1.x, p1.y)]
	var n := maxi(absi(p1.x - p0.x), absi(p1.y - p0.y))
	var worst := 0.0
	for k in range(0, n + 1, maxi(1, n / 10)):
		var f := float(k) / float(maxi(1, n))
		var q := Vector2i(p0.x + int(round((p1.x - p0.x) * f)), p0.y + int(round((p1.y - p0.y) * f)))
		worst = maxf(worst, absf(terrain._heights[terrain._index(q.x, q.y)] - lerpf(h0, h1, f)))
	return worst

## A grid point pushed off the grid by up to a third of the plate it came
## from: along the edge only on a tile's edge, not at all at its corners or
## where the ground has to be followed cell by cell.
func _jittered(k: Vector2i, size: int, t: TileBuf) -> Vector2:
	var x := -terrain.half_extent + float(k.x) * Terrain.CELL
	var z := -terrain.half_extent + float(k.y) * Terrain.CELL
	if size <= 2:
		return Vector2(x, z)
	var on_x_edge := k.x == t.x0 or k.x == t.x1
	var on_z_edge := k.y == t.z0 or k.y == t.z1
	var reach := float(size) * Terrain.CELL * 0.42
	var h := hash(k)
	var jx := (float(h % 1000) / 1000.0 - 0.5) * 2.0 * reach
	var jz := (float((h / 1000) % 1000) / 1000.0 - 0.5) * 2.0 * reach
	if not on_x_edge:
		x += jx
	if not on_z_edge:
		z += jz
	return Vector2(x, z)

# --- Welding -------------------------------------------------------------------

## Joins triangles that lie nearly flat to their neighbour into one plate,
## across the whole map, and gives each plate one normal and one colour.
func _weld_all() -> void:
	var offsets := PackedInt32Array()
	var n_tri := 0
	for t: TileBuf in tiles:
		offsets.append(n_tri)
		n_tri += t.face_n.size()
	var parent := PackedInt32Array()
	parent.resize(n_tri)
	for i in n_tri:
		parent[i] = i
	var normals := PackedVector3Array()
	normals.resize(n_tri)
	var edges := {}
	var limit := cos(deg_to_rad(WELD_DEGREES))
	for ti in tiles.size():
		var t: TileBuf = tiles[ti]
		for k in t.face_n.size():
			var g := offsets[ti] + k
			normals[g] = t.face_n[k]
			for e in 3:
				var a := _key(t.tris[k * 3 + e])
				var b := _key(t.tris[k * 3 + (e + 1) % 3])
				var key := [a, b] if a < b else [b, a]
				var h := hash(key)
				if edges.has(h):
					var j: int = edges[h]
					if normals[g].dot(normals[j]) > limit:
						var ri := _find(parent, g)
						var rj := _find(parent, j)
						if ri != rj:
							parent[ri] = rj
				else:
					edges[h] = g
	# Each plate's normal, weighted by area, and its middle.
	var sum_n := {}
	var sum_c := {}
	var sum_a := {}
	for ti in tiles.size():
		var t: TileBuf = tiles[ti]
		for k in t.face_n.size():
			var r := _find(parent, offsets[ti] + k)
			var a := t.tris[k * 3]
			var b := t.tris[k * 3 + 1]
			var c := t.tris[k * 3 + 2]
			var area := (c - a).cross(b - a).length()
			sum_n[r] = (sum_n.get(r, Vector3.ZERO) as Vector3) + t.face_n[k] * area
			sum_c[r] = (sum_c.get(r, Vector3.ZERO) as Vector3) + (a + b + c) / 3.0 * area
			sum_a[r] = float(sum_a.get(r, 0.0)) + area
	var plate_n := {}
	var plate_c := {}
	for r in sum_n:
		var nn: Vector3 = (sum_n[r] as Vector3).normalized()
		var centre: Vector3 = (sum_c[r] as Vector3) / maxf(0.0001, float(sum_a[r]))
		plate_n[r] = nn
		plate_c[r] = terrain.panel_color(centre, nn, int(r) * 7919)
	for ti in tiles.size():
		var t: TileBuf = tiles[ti]
		t.normals.resize(t.tris.size())
		t.colors.resize(t.tris.size())
		for k in t.face_n.size():
			var r := _find(parent, offsets[ti] + k)
			var nn: Vector3 = plate_n[r]
			var col: Color = plate_c[r]
			for v in 3:
				t.normals[k * 3 + v] = nn
				t.colors[k * 3 + v] = col
	plates = sum_n.size()

var plates: int = 0

## A vertex as a key: to the centimetre, so both tiles' copies of a shared
## edge point agree.
static func _key(v: Vector3) -> Vector3i:
	return Vector3i(int(round(v.x * 100.0)), int(round(v.y * 100.0)), int(round(v.z * 100.0)))

static func _find(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i

func _bucket(t: TileBuf, k: int, a: Vector3, b: Vector3, c: Vector3) -> void:
	var lo := Vector2i(int(floor(minf(a.x, minf(b.x, c.x)) / BUCKET)), int(floor(minf(a.z, minf(b.z, c.z)) / BUCKET)))
	var hi := Vector2i(int(floor(maxf(a.x, maxf(b.x, c.x)) / BUCKET)), int(floor(maxf(a.z, maxf(b.z, c.z)) / BUCKET)))
	for bz in range(lo.y, hi.y + 1):
		for bx in range(lo.x, hi.x + 1):
			var key := Vector2i(bx, bz)
			if not t.buckets.has(key):
				t.buckets[key] = PackedInt32Array()
			var list: PackedInt32Array = t.buckets[key]
			list.append(k)
			t.buckets[key] = list

# --- Queries -------------------------------------------------------------------

## The height of the panels over a point, or NAN off them (a cave mouth).
func height(x: float, z: float) -> float:
	if tiles.is_empty():
		return NAN
	var gx := int(floor((x + terrain.half_extent) / Terrain.CELL))
	var gz := int(floor((z + terrain.half_extent) / Terrain.CELL))
	var tx := clampi(gx / TILE, 0, tiles_x - 1)
	var tz := clampi(gz / TILE, 0, tiles_x - 1)
	# The point may sit in the next tile when the edge's points were pushed.
	for dz in [0, -1, 1]:
		for dx in [0, -1, 1]:
			var ux: int = tx + dx
			var uz: int = tz + dz
			if ux < 0 or uz < 0 or ux >= tiles_x or uz >= tiles_x:
				continue
			var y := _height_in(tiles[uz * tiles_x + ux], x, z)
			if not is_nan(y):
				return y
	return NAN

func _height_in(t: TileBuf, x: float, z: float) -> float:
	var key := Vector2i(int(floor(x / BUCKET)), int(floor(z / BUCKET)))
	if not t.buckets.has(key):
		return NAN
	var p := Vector2(x, z)
	for k in (t.buckets[key] as PackedInt32Array):
		var a := t.tris[k * 3]
		var b := t.tris[k * 3 + 1]
		var c := t.tris[k * 3 + 2]
		var bc := _barycentric(p, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z))
		if bc.x >= -0.0001 and bc.y >= -0.0001 and bc.z >= -0.0001:
			return a.y * bc.x + b.y * bc.y + c.y * bc.z
	return NAN

static func _barycentric(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var den := v0.x * v1.y - v1.x * v0.y
	if absf(den) < 0.000001:
		return Vector3(-1, -1, -1)
	var v := (v2.x * v1.y - v1.x * v2.y) / den
	var w := (v0.x * v2.y - v2.x * v0.y) / den
	return Vector3(1.0 - v - w, v, w)

func triangle_count() -> int:
	var n := 0
	for t: TileBuf in tiles:
		n += t.tris.size() / 3
	return n
