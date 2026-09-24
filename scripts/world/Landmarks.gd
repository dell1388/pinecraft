class_name Landmarks
extends Node3D

## The high ground, built the way a block-built world builds it: stacks of
## flat-topped plateaus with sheer cliff walls, each level a big irregular
## polygon a step smaller than the one below, and a ramp up the side of each
## level that doubles back from the one before - so a mountain is a climb you
## can drive, switchback by switchback, to the top.
##
##   Mountains  tall stacks, grass low down, bare rock higher, snow on top
##   Frostreach snowfields on brown cliffs
##   Desert     red mesas in bands with sandy tops
##   Woods      low grass plateaus on brown rock, and the odd natural arch
##
## Tops are registered with the terrain, so trees, rocks and grass grow up on
## them and anything placed stands on them. Stacks keep off the roads, the
## building sites, the cave mouths and the water.

const SPACING := 150.0
const RAMP_WIDTH := 8.0
const RAMP_GRADE := 0.2

var terrain: Terrain
var seed_value: int = 1
## Every plateau level: {poly, bottom, top, top_color, wall_color, stack}.
var levels: Array[Dictionary] = []
## Every ramp: {a, b, y0, y1}.
var ramps: Array[Dictionary] = []
## Arch pieces and other plain boxes: {size, xform, color}.
var blocks: Array[Dictionary] = []
var stacks: int = 0
var _pending: Array = []            ## stacks awaiting their ramps

var _body: StaticBody3D
var _tops: Dictionary = {}          ## tile -> [verts, normals, colors]
var _walls: Dictionary = {}

const GRASS := Color(0.36, 0.64, 0.29)
const DARK_GRASS := Color(0.26, 0.52, 0.30)
const SNOW := Color(0.93, 0.95, 0.98)
const SAND := Color(0.93, 0.84, 0.60)
const BARE := Color(0.58, 0.56, 0.54)
const BROWN := Color(0.46, 0.36, 0.28)
const GREY_BROWN := Color(0.48, 0.43, 0.39)
const REDS := [Color(0.80, 0.46, 0.36), Color(0.86, 0.55, 0.42), Color(0.74, 0.42, 0.34)]

func setup(p_terrain: Terrain, p_seed: int) -> void:
	terrain = p_terrain
	seed_value = p_seed

func _ready() -> void:
	_body = StaticBody3D.new()
	_body.name = "Plateaus"
	_body.collision_layer = Layers.WORLD
	_body.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.95
	_body.physics_material_override = pm
	add_child(_body)
	var half := terrain.half_extent
	var n := int(half * 2.0 / SPACING)
	var placed: Array = []
	for iz in n:
		for ix in n:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(Vector3i(ix, iz, seed_value))
			var p := Vector3(-half + (float(ix) + rng.randf_range(0.15, 0.85)) * SPACING, 0.0,
				-half + (float(iz) + rng.randf_range(0.15, 0.85)) * SPACING)
			_place_at(p, rng, placed)
	# Ramps once every level stands, so none is laid where another stack's
	# cliff comes down over it.
	for plan in _pending:
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = int(plan.seed)
		var last_end: Variant = null
		for step: Array in plan.steps:
			var end: Variant = _ramp(step[0], step[1], step[2], step[3], last_end, rng2, int(plan.stack))
			if end != null:
				last_end = end
	_pending.clear()
	_flush()

func _place_at(p: Vector3, rng: RandomNumberGenerator, placed: Array) -> void:
	var ground := terrain.height_at(p.x, p.z)
	if ground < Terrain.WATER_LEVEL + 2.0:
		return
	var biome := terrain.biome_at(p.x, p.z)
	var roll := rng.randf()
	var spec: Dictionary = {}
	match biome:
		Terrain.Biome.MOUNTAIN:
			if roll < 0.85:
				spec = {"r": [110.0, 200.0], "levels": [5, 9], "h": [10.0, 15.0], "kind": "mountain",
					"shrink": [0.78, 0.88], "overlap": 0.45}
		Terrain.Biome.SNOW:
			if roll < 0.8:
				spec = {"r": [80.0, 150.0], "levels": [2, 5], "h": [9.0, 14.0], "kind": "snow",
					"shrink": [0.72, 0.85], "overlap": 0.55}
		Terrain.Biome.DESERT:
			if roll < 0.5:
				spec = {"r": [60.0, 120.0], "levels": [2, 5], "h": [8.0, 13.0], "kind": "mesa"}
			elif roll < 0.52:
				_arch(p, rng, REDS[0])
		Terrain.Biome.TAIGA:
			if roll < 0.4:
				spec = {"r": [40.0, 85.0], "levels": [1, 3], "h": [6.0, 11.0], "kind": "taiga"}
		Terrain.Biome.WOODLAND:
			if roll < 0.28:
				spec = {"r": [35.0, 75.0], "levels": [1, 2], "h": [5.0, 9.0], "kind": "woods"}
			elif roll < 0.33:
				_arch(p, rng, GREY_BROWN)
		Terrain.Biome.SWAMP:
			if roll < 0.08:
				spec = {"r": [30.0, 50.0], "levels": [1, 1], "h": [4.0, 6.0], "kind": "woods"}
	if spec.is_empty():
		return
	var r := rng.randf_range(spec.r[0], spec.r[1])
	var overlap: float = spec.get("overlap", 0.75)
	for other in placed:
		if Vector2(p.x, p.z).distance_to(other[0]) < (r + float(other[1])) * overlap:
			return
	var poly := _outline(Vector2(p.x, p.z), r, rng)
	if not _clear(poly, Vector2(p.x, p.z), r):
		return
	placed.append([Vector2(p.x, p.z), r])
	_stack(poly, Vector2(p.x, p.z), r, spec, rng)

## An irregular outline round `c`: a star-shaped polygon, some sides long and
## straight, the corners pushed in and out.
func _outline(c: Vector2, r: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var n := rng.randi_range(6, 9)
	var out := PackedVector2Array()
	var start := rng.randf() * TAU
	for i in n:
		var a := start + TAU * (float(i) + rng.randf_range(-0.25, 0.25)) / float(n)
		out.append(c + Vector2(cos(a), sin(a)) * r * rng.randf_range(0.78, 1.12))
	return out

## Whether an outline is clear to build on: no road, site, cave mouth or water
## under it or close round it.
func _clear(poly: PackedVector2Array, c: Vector2, r: float) -> bool:
	var probes: Array = [c]
	for p in poly:
		probes.append(p)
		probes.append(c.lerp(p, 0.5))
		probes.append(p + (p - c).normalized() * 16.0)
	for q: Vector2 in probes:
		if terrain.is_road(q.x, q.y) or terrain.water_depth(q.x, q.y) > 0.0 \
				or terrain._in_build_site(q.x, q.y) or terrain.in_cave_zone(q.x, q.y):
			return false
	for cave in terrain.caves:
		var e: Vector3 = cave.entrance
		if Vector2(e.x, e.z).distance_to(c) < r + 50.0:
			return false
	for f in terrain.features:
		if String(f.kind) != "basin" and c.distance_to(f.centre) < float(f.radius) * 2.4 + r:
			return false
	# Not straddling the sea.
	for p in poly:
		if terrain.height_at(p.x, p.y) < Terrain.WATER_LEVEL + 1.0:
			return false
	return true

## A stack: levels of the outline, each shrunk toward a drifting centre and
## raised a step, walls sheer, and a ramp to each level from the one below,
## doubling back each time.
func _stack(poly: PackedVector2Array, c: Vector2, r: float, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	stacks += 1
	var kind: String = spec.kind
	var count := rng.randi_range(int(spec.levels[0]), int(spec.levels[1]))
	var lo := INF
	var hi := -INF
	for p in poly:
		var h := terrain.height_at(p.x, p.y)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	var centre_h := terrain.height_at(c.x, c.y)
	lo = minf(lo, centre_h)
	hi = maxf(hi, centre_h)
	var bottom := lo - 3.0
	var top := hi + rng.randf_range(spec.h[0], spec.h[1]) * 0.8
	var outline := poly
	var centre := c
	var steps: Array = []
	_pending.append({"stack": stacks, "seed": rng.randi(), "steps": steps})
	for k in count:
		var wall := _wall_color(kind, k, count)
		var top_color := _top_color(kind, k, count, top)
		levels.append({"poly": outline, "bottom": bottom, "top": top, "top_color": top_color,
			"wall_color": wall})
		_prism(outline, bottom, top, top_color, wall)
		terrain.add_top(outline, top, top_color)
		# The ramp onto this level: along one of its sides, from the level
		# below (or the ground) up to this top, near where the last ramp
		# came out, running the other way.
		var below_poly: Variant = levels[levels.size() - 2].poly if k > 0 else null
		var from_y := bottom + 3.0 if k == 0 else float(levels[levels.size() - 2].top)
		steps.append([outline, below_poly, from_y, top])
		if k == count - 1:
			break
		# The next level: smaller, drifted, a step up.
		var sh: Array = spec.get("shrink", [0.66, 0.8])
		var shrink := rng.randf_range(sh[0], sh[1])
		centre = centre.lerp(centre + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * r * 0.12, 1.0)
		var next := PackedVector2Array()
		for p in outline:
			next.append(centre + (p - centre) * shrink)
		# Keep the ledge round every side at least a ramp wide.
		var ok := true
		for i in next.size():
			if Geometry2D.is_point_in_polygon(next[i], outline) == false:
				ok = false
		if not ok:
			break
		outline = next
		bottom = top - 0.5
		top = top + rng.randf_range(spec.h[0], spec.h[1])

func _wall_color(kind: String, k: int, count: int) -> Color:
	match kind:
		"mesa":
			return REDS[k % REDS.size()]
		"mountain":
			return GREY_BROWN.lerp(BARE.darkened(0.15), float(k) / maxf(1.0, float(count - 1))).darkened(0.03 * float(k % 2))
	return BROWN.lightened(0.04 * float(k % 2))

func _top_color(kind: String, k: int, count: int, top: float) -> Color:
	match kind:
		"mesa":
			return SAND
		"snow":
			return SNOW
		"mountain":
			if k == count - 1 or top > 115.0:
				return SNOW
			return GRASS if k < count / 2 else BARE
		"taiga":
			return DARK_GRASS
	return GRASS

## One level: a flat top polygon (a fan from its middle) and a sheer wall down
## every side.
func _prism(poly: PackedVector2Array, bottom: float, top: float, top_color: Color, wall: Color) -> void:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= float(poly.size())
	var tile := Vector2i(int(floor(c.x / 400.0)), int(floor(c.y / 400.0)))
	var tb := _buffer(_tops, tile)
	var wb := _buffer(_walls, tile)
	var faces := PackedVector3Array()
	var mid := Vector3(c.x, top, c.y)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var pa := Vector3(a.x, top, a.y)
		var pb := Vector3(b.x, top, b.y)
		_tri(tb, mid, pa, pb, Vector3.UP, top_color, faces)
		# The wall, facing out.
		var out := Vector3(b.y - a.y, 0.0, -(b.x - a.x)).normalized()
		if out.dot(Vector3(a.x - c.x, 0.0, a.y - c.y)) < 0.0:
			out = -out
		var qa := Vector3(a.x, bottom, a.y)
		var qb := Vector3(b.x, bottom, b.y)
		var shade := wall.darkened(0.08 * (1.0 - absf(out.x)))
		_tri(wb, pa, qa, qb, out, shade, faces)
		_tri(wb, pa, qb, pb, out, shade, faces)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	cs.shape = shape
	_body.add_child(cs)

class MeshBuf:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

func _buffer(store: Dictionary, tile: Vector2i) -> MeshBuf:
	if not store.has(tile):
		store[tile] = MeshBuf.new()
	return store[tile]

## Adds a triangle facing `facing`, to a mesh buffer and to the collision faces.
func _tri(buf: MeshBuf, a: Vector3, b: Vector3, c: Vector3, facing: Vector3, color: Color,
		faces: PackedVector3Array) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 0.000001:
		return
	if n.dot(facing) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	buf.verts.append_array(PackedVector3Array([a, b, c]))
	buf.normals.append_array(PackedVector3Array([n, n, n]))
	buf.colors.append_array(PackedColorArray([color, color, color]))
	faces.append_array(PackedVector3Array([a, b, c]))

## A ramp up one side of `poly`, on the ledge inside `below` (or on the ground),
## from `y0` to `y1`: a solid wedge, as steep as a truck can take. Chooses the
## side whose low end is nearest `near`, so each ramp starts about where the
## last one came out. Returns where this one comes out.
func _ramp(poly: PackedVector2Array, below: Variant, y0: float, y1: float, near: Variant,
		rng: RandomNumberGenerator, stack: int) -> Variant:
	var rise := y1 - y0
	var need := rise / RAMP_GRADE
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= float(poly.size())
	var best: Array = []
	var best_score := INF
	for i in poly.size():
		for dir in [1, -1]:
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			if dir < 0:
				var t := a
				a = b
				b = t
			var run := a.distance_to(b) - 6.0
			if run < need:
				continue
			var along := (b - a).normalized()
			var out := Vector2(along.y, -along.x)
			if out.dot(a - c) < 0.0:
				out = -out
			var s := a + along * 3.0 + out * (RAMP_WIDTH * 0.5 + 0.1)
			var e := s + along * need
			# Nothing higher over the ramp than the surface it starts from -
			# no other stack's cliff in the way, below or at the landing.
			var blocked := false
			for t4 in [0.0, 0.25, 0.5, 0.75, 1.0, 1.25]:
				var q4: Vector2 = s.lerp(e, t4) + out * RAMP_WIDTH * 0.25
				var over := terrain.top_at(q4.x, q4.y)
				if t4 > 1.0:
					continue
				if not over.is_empty() and float(over[0]) > y0 + 0.6:
					blocked = true
				for side in [-1.0, 1.0]:
					var q5: Vector2 = s.lerp(e, t4) + out * side * (RAMP_WIDTH * 0.5 + 1.5)
					var over2 := terrain.top_at(q5.x, q5.y)
					if side > 0.0 and not over2.is_empty() and float(over2[0]) > y0 + 0.6:
						blocked = true
			# The landing past the top end, clear to drive off.
			for k2 in [1.0, 3.0, 5.5]:
				for side3 in [-0.4, 0.0, 0.4]:
					var q7: Vector2 = e + along * k2 + out * side3 * RAMP_WIDTH
					var over3 := terrain.top_at(q7.x, q7.y)
					if not over3.is_empty() and float(over3[0]) > y1 + 0.3:
						blocked = true
			if blocked:
				continue
			# The whole ramp has to sit on the ledge below, clear of its edge.
			if below != null:
				var ok := true
				for t2 in [0.0, 0.5, 1.0]:
					var q: Vector2 = s.lerp(e, t2) + out * (RAMP_WIDTH * 0.5 + 2.0)
					if not Geometry2D.is_point_in_polygon(q, below):
						ok = false
				if not ok:
					continue
			else:
				# A ramp up from the ground: the ground must stay under the
				# ramp all the way up, or it pokes through and stops you.
				var clear := true
				var g0 := terrain.height_at(s.x, s.y)
				for step in 11:
					var t3 := float(step) / 10.0
					for side2 in [-0.5, 0.0, 0.5]:
						var q2: Vector2 = s.lerp(e, t3) + out * side2 * RAMP_WIDTH
						if terrain.is_road(q2.x, q2.y) or terrain.water_depth(q2.x, q2.y) > 0.0:
							clear = false
						if terrain.height_at(q2.x, q2.y) > g0 + (y1 - g0) * t3 + 0.25:
							clear = false
				if not clear or y1 - g0 > need * RAMP_GRADE + 0.5:
					continue
			# Clear of every other ramp and arch.
			var crossing := false
			for t5 in [0.0, 0.33, 0.66, 1.0]:
				var q6: Vector2 = s.lerp(e, t5)
				if terrain.is_blocked(q6.x, q6.y):
					crossing = true
			if crossing:
				continue
			var score := rng.randf() * 10.0
			if near != null:
				score = (near as Vector2).distance_to(s)
			if score < best_score:
				best_score = score
				best = [s, e, out]
	if best.is_empty():
		return null
	var s2: Vector2 = best[0]
	var e2: Vector2 = best[1]
	var o2: Vector2 = best[2]
	# On the ground the low end meets the ground where it is.
	var low := y0
	if below == null:
		low = terrain.height_at(s2.x, s2.y)
	_wedge(s2, e2, o2, low, y1)
	ramps.append({"a": Vector3(s2.x, low, s2.y), "b": Vector3(e2.x, y1, e2.y), "stack": stack})
	terrain.mark_blocked(Vector3((s2.x + e2.x) * 0.5, 0, (s2.y + e2.y) * 0.5), s2.distance_to(e2) * 0.5 + 4.0)
	return e2

## A solid wedge: level with `low` at `s`, rising to `high` at `e`, a ramp
## wide, the inner side hard against the wall it climbs. The top overlaps the
## level above at its high end, so it runs straight on to the top.
func _wedge(s: Vector2, e: Vector2, out: Vector2, low: float, high: float) -> void:
	var inward := -out * (RAMP_WIDTH * 0.5 + 1.2)
	var outward := out * (RAMP_WIDTH * 0.5)
	var base := minf(low, high) - 2.0
	var along := (e - s).normalized()
	# The high end runs a few metres on, level, as a landing.
	var land := e + along * 5.0
	var pts := [
		Vector3(s.x + inward.x, base, s.y + inward.y), Vector3(s.x + outward.x, base, s.y + outward.y),
		Vector3(land.x + inward.x, base, land.y + inward.y), Vector3(land.x + outward.x, base, land.y + outward.y),
		Vector3(s.x + inward.x, low, s.y + inward.y), Vector3(s.x + outward.x, low, s.y + outward.y),
		Vector3(e.x + inward.x, high, e.y + inward.y), Vector3(e.x + outward.x, high, e.y + outward.y),
		Vector3(land.x + inward.x, high, land.y + inward.y), Vector3(land.x + outward.x, high, land.y + outward.y),
	]
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array(pts)
	cs.shape = shape
	_body.add_child(cs)
	var mid := Vector2((s.x + land.x) * 0.5, (s.y + land.y) * 0.5)
	var tile := Vector2i(int(floor(mid.x / 400.0)), int(floor(mid.y / 400.0)))
	var tb := _buffer(_tops, tile)
	var wb := _buffer(_walls, tile)
	var dummy := PackedVector3Array()
	var ramp_color := Color(0.64, 0.66, 0.70)
	var side_color := BROWN.lightened(0.05)
	# Surface: the slope, then the landing.
	var up := Vector3(0, 1, 0)
	_tri(tb, pts[4], pts[5], pts[7], up, ramp_color, dummy)
	_tri(tb, pts[4], pts[7], pts[6], up, ramp_color, dummy)
	_tri(tb, pts[6], pts[7], pts[9], up, ramp_color, dummy)
	_tri(tb, pts[6], pts[9], pts[8], up, ramp_color, dummy)
	# The outer side and the low end.
	var o3 := Vector3(out.x, 0, out.y)
	_tri(wb, pts[1], pts[3], pts[9], o3, side_color, dummy)
	_tri(wb, pts[1], pts[9], pts[7], o3, side_color, dummy)
	_tri(wb, pts[1], pts[7], pts[5], o3, side_color, dummy)
	var back := Vector3(-along.x, 0, -along.y)
	_tri(wb, pts[0], pts[1], pts[5], back, side_color, dummy)
	_tri(wb, pts[0], pts[5], pts[4], back, side_color, dummy)
	var fwd := Vector3(along.x, 0, along.y)
	_tri(wb, pts[2], pts[3], pts[9], fwd, side_color, dummy)
	_tri(wb, pts[2], pts[9], pts[8], fwd, side_color, dummy)

## A natural arch: two legs and a slab across, high enough to drive under.
func _arch(p: Vector3, rng: RandomNumberGenerator, color: Color) -> void:
	var span := rng.randf_range(24.0, 38.0)
	var c := Vector2(p.x, p.z)
	var ring := PackedVector2Array()
	for i in 6:
		ring.append(c + Vector2(cos(TAU * i / 6.0), sin(TAU * i / 6.0)) * span * 0.7)
	if not _clear(ring, c, span * 0.7):
		return
	var yaw := rng.randf() * TAU
	var across := Vector3(cos(yaw), 0.0, -sin(yaw))
	var leg := rng.randf_range(7.0, 11.0)
	var rise := rng.randf_range(14.0, 22.0)
	var ground := terrain.height_at(p.x, p.z)
	for s in [-1.0, 1.0]:
		var q: Vector3 = p + across * s * span * 0.5
		var g2 := terrain.height_at(q.x, q.z)
		_box(Vector3(leg, rise + (ground - g2) + 3.0, leg * 1.1),
			Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, g2 - 3.0 + (rise + ground - g2 + 3.0) * 0.5, q.z)), color)
	_box(Vector3(span + leg, rng.randf_range(6.0, 9.0), leg * 1.2),
		Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, ground + rise + 2.5, p.z)), color.lightened(0.04))

func _box(size: Vector3, xform: Transform3D, color: Color) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.transform = xform
	_body.add_child(cs)
	blocks.append({"size": size, "xform": xform, "color": color})
	var tile := Vector2i(int(floor(xform.origin.x / 400.0)), int(floor(xform.origin.z / 400.0)))
	var wb := _buffer(_walls, tile)
	var dummy := PackedVector3Array()
	var h := size * 0.5
	var corners: Array = []
	for i in 8:
		corners.append(xform * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	for face in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		var a: Vector3 = corners[face[0]]
		var b: Vector3 = corners[face[1]]
		var cc: Vector3 = corners[face[2]]
		var d: Vector3 = corners[face[3]]
		var out := ((a + b + cc + d) * 0.25 - xform.origin).normalized()
		_tri(wb, a, b, cc, out, color, dummy)
		_tri(wb, a, cc, d, out, color, dummy)
	terrain.mark_blocked(xform.origin, maxf(size.x, size.z) * 0.55)

## The meshes, a pair per tile: tops with a grass grain, walls with a rock one.
func _flush() -> void:
	var grass := Textures.material("grass", 6.0)
	var rock := Textures.material("rock", 10.0)
	for pair in [[_tops, grass, "Tops"], [_walls, rock, "Walls"]]:
		var store: Dictionary = pair[0]
		for tile in store:
			var buf: MeshBuf = store[tile]
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
			mi.name = "%s_%d_%d" % [pair[2], tile.x, tile.y]
			mi.mesh = mesh
			mi.material_override = pair[1]
			add_child(mi)
