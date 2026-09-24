class_name Landmarks
extends Node3D

## The big pieces the land is built from, stood on the smooth ground the way
## parts are in a block-built world: mountains are massifs of huge grey slabs
## stacked and leaning on each other with snow on the tops; the desert has
## flat-topped mesas and buttes of banded red rock, layer on layer; the woods
## have grass-topped rock outcrops and here and there a natural arch. All of it
## is textured, solid and walkable round (or, for an arch, under).
##
## Placed on a jittered grid, each spot seeded from its own position, and kept
## off the roads, the building sites, the cave mouths and the water. The ground
## under each one is marked on the terrain so nothing grows through it.

const SPACING := 72.0

var terrain: Terrain
var seed_value: int = 1
## {size, xform, color} for every block, for tests and the map.
var blocks: Array[Dictionary] = []
var _tiles: Dictionary = {}           ## Vector2i -> Greeble
var _body: StaticBody3D

const GREY := Color(0.60, 0.60, 0.62)
const DARK := Color(0.36, 0.35, 0.36)
const SNOWCAP := Color(0.95, 0.97, 1.0)
const REDS := [Color(0.88, 0.56, 0.44), Color(0.93, 0.66, 0.50), Color(0.84, 0.50, 0.40)]
const MOSS := Color(0.34, 0.64, 0.26)

func setup(p_terrain: Terrain, p_seed: int) -> void:
	terrain = p_terrain
	seed_value = p_seed

func _ready() -> void:
	_body = StaticBody3D.new()
	_body.name = "Blocks"
	_body.collision_layer = Layers.WORLD
	_body.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	_body.physics_material_override = pm
	add_child(_body)
	var half := terrain.half_extent
	var n := int(half * 2.0 / SPACING)
	for iz in n:
		for ix in n:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(Vector3i(ix, iz, seed_value))
			var p := Vector3(-half + (float(ix) + rng.randf_range(0.2, 0.8)) * SPACING, 0.0,
				-half + (float(iz) + rng.randf_range(0.2, 0.8)) * SPACING)
			_place_at(p, rng)
	var mat := Textures.material("rock", 12.0)
	for key in _tiles:
		var g: Greeble = _tiles[key]
		var mi := MeshInstance3D.new()
		mi.name = "Rocks_%d_%d" % [key.x, key.y]
		mi.mesh = g.commit()
		mi.material_override = mat
		add_child(mi)

func _place_at(p: Vector3, rng: RandomNumberGenerator) -> void:
	var ground := terrain.height_at(p.x, p.z)
	if ground < Terrain.WATER_LEVEL + 1.5:
		return
	var biome := terrain.biome_at(p.x, p.z)
	var roll := rng.randf()
	match biome:
		Terrain.Biome.MOUNTAIN, Terrain.Biome.SNOW:
			if roll < 0.62:
				_massif(p, rng, biome == Terrain.Biome.SNOW or ground > 70.0)
			elif roll < 0.8:
				_arch(p, rng, GREY)
		Terrain.Biome.DESERT:
			if roll < 0.22:
				_mesa(p, rng)
			elif roll < 0.38:
				_arch(p, rng, REDS[0])
			elif roll < 0.44:
				_butte(p, rng)
		Terrain.Biome.WOODLAND, Terrain.Biome.TAIGA:
			if roll < 0.13:
				_outcrop(p, rng)
			elif roll < 0.15:
				_arch(p, rng, GREY)
		Terrain.Biome.SWAMP:
			if roll < 0.06:
				_outcrop(p, rng)

## Whether a footprint of `radius` round `p` is free to build on.
func _clear(p: Vector3, radius: float) -> bool:
	for i in 9:
		var q := p
		if i > 0:
			var a := TAU * float(i) / 8.0
			q += Vector3(cos(a), 0.0, sin(a)) * radius
		if terrain.is_road(q.x, q.z) or terrain.water_depth(q.x, q.z) > 0.0 \
				or terrain._in_build_site(q.x, q.z) or terrain.in_cave_zone(q.x, q.z):
			return false
		# Well clear of the road too, not just off it.
		for k in 4:
			var b := TAU * float(k) / 4.0
			var r2 := q + Vector3(cos(b), 0.0, sin(b)) * 14.0
			if terrain.is_road(r2.x, r2.z):
				return false
	for cave in terrain.caves:
		var e: Vector3 = cave.entrance
		if Vector2(e.x - p.x, e.z - p.z).length() < radius + 45.0:
			return false
	for f in terrain.features:
		if String(f.kind) != "basin" and Vector2(p.x, p.z).distance_to(f.centre) < float(f.radius) * 2.2 + radius:
			return false
	return true

## A box standing on the ground, sunk into it a little, turned by `yaw` and
## leaning by `tilt`. Returns the height of its top.
func _block(centre_xz: Vector3, size: Vector3, base: float, yaw: float, tilt: Vector2,
		color: Color) -> float:
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt.x) * Basis(Vector3.FORWARD, tilt.y)
	var centre := Vector3(centre_xz.x, base + size.y * 0.5, centre_xz.z)
	var xform := Transform3D(basis, centre)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.transform = xform
	_body.add_child(cs)
	_tile(centre).box(size, xform, color)
	blocks.append({"size": size, "xform": xform, "color": color})
	terrain.mark_blocked(centre, maxf(size.x, size.z) * 0.55)
	return base + size.y

func _tile(p: Vector3) -> Greeble:
	var key := Vector2i(int(floor(p.x / 400.0)), int(floor(p.z / 400.0)))
	if not _tiles.has(key):
		_tiles[key] = Greeble.new()
	return _tiles[key]

## The lowest ground under a footprint, so a block never floats at a corner.
func _low(p: Vector3, radius: float) -> float:
	var lo := terrain.height_at(p.x, p.z)
	for i in 6:
		var a := TAU * float(i) / 6.0
		lo = minf(lo, terrain.height_at(p.x + cos(a) * radius, p.z + sin(a) * radius))
	return lo

func _shade(c: Color, rng: RandomNumberGenerator) -> Color:
	var j := rng.randf_range(-0.06, 0.06)
	return c.lightened(j) if j > 0.0 else c.darkened(-j)

## A mountain: a pile of broad slabs, each turned and leaning its own way,
## stacked in steps toward a summit - wide rather than tall, so a range reads
## as rock heaped up, not towers. Snow on the highest tops.
func _massif(p: Vector3, rng: RandomNumberGenerator, snowy: bool) -> void:
	var foot := rng.randf_range(45.0, 85.0)
	if not _clear(p, foot * 0.6):
		return
	var ground := _low(p, foot * 0.5) - 4.0
	var top := ground
	var peak := p
	var yaw := rng.randf() * TAU
	# The broad base, then smaller slabs piled on it, each stepped in.
	var w := foot
	var level := ground
	var layers := rng.randi_range(3, 5)
	for layer in layers:
		var h := rng.randf_range(12.0, 24.0) * (1.0 if layer > 0 else 1.4)
		var off := Vector3(rng.randf_range(-0.18, 0.18), 0.0, rng.randf_range(-0.18, 0.18)) * w
		var q := peak + off
		var lean := Vector2(rng.randf_range(-0.14, 0.14), rng.randf_range(-0.14, 0.14))
		var t := _block(q, Vector3(w, h, w * rng.randf_range(0.6, 0.95)), level - 1.5,
			yaw + rng.randf_range(-0.6, 0.6), lean, _shade(GREY if layer % 2 == 0 else GREY.darkened(0.08), rng))
		# Shoulders: a couple of slabs leaning on the side of this layer.
		for k in rng.randi_range(1, 2):
			var a := rng.randf() * TAU
			var r := q + Vector3(cos(a), 0.0, sin(a)) * w * 0.5
			var sw := w * rng.randf_range(0.3, 0.5)
			var sh := h * rng.randf_range(0.8, 1.5)
			_block(r, Vector3(sw, sh, sw * rng.randf_range(0.5, 0.9)), maxf(_low(r, sw * 0.4) - 3.0, level - sh * 0.5),
				rng.randf() * TAU, Vector2(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25)),
				_shade(DARK.lightened(0.14), rng))
		level = t - 1.0
		top = maxf(top, t)
		peak = q
		w *= rng.randf_range(0.62, 0.8)
	if snowy or top > 105.0:
		_block(peak, Vector3(w * 1.25, 2.2, w * 1.25), top - 1.0, yaw, Vector2.ZERO, SNOWCAP)

## A mesa: broad red slabs stacked in bands, each a little smaller and turned
## a touch from the one below, with a pale sandy top.
func _mesa(p: Vector3, rng: RandomNumberGenerator) -> void:
	var foot := rng.randf_range(55.0, 110.0)
	if not _clear(p, foot * 0.6):
		return
	var y := _low(p, foot * 0.5) - 3.0
	var yaw := rng.randf() * TAU
	var w := foot
	var d := foot * rng.randf_range(0.55, 0.9)
	var at := p
	for layer in rng.randi_range(3, 4):
		var h := rng.randf_range(9.0, 16.0)
		at += Vector3(rng.randf_range(-0.07, 0.07) * w, 0.0, rng.randf_range(-0.07, 0.07) * d)
		y = _block(at, Vector3(w, h, d), y - 0.3, yaw + rng.randf_range(-0.12, 0.12), Vector2.ZERO,
			REDS[layer % REDS.size()])
		w *= rng.randf_range(0.74, 0.9)
		d *= rng.randf_range(0.74, 0.9)
	_block(at, Vector3(w * 1.12, 0.6, d * 1.12), y - 0.3, yaw, Vector2.ZERO, Color(0.94, 0.84, 0.6))

## A lone butte or a tumble of red boulders.
func _butte(p: Vector3, rng: RandomNumberGenerator) -> void:
	var s := rng.randf_range(8.0, 18.0)
	if not _clear(p, s):
		return
	var base := _low(p, s * 0.5) - 2.0
	_block(p, Vector3(s, rng.randf_range(10.0, 26.0), s * rng.randf_range(0.7, 1.1)), base,
		rng.randf() * TAU, Vector2(rng.randf_range(-0.06, 0.06), 0.0), REDS[rng.randi() % REDS.size()])
	for k in 2:
		var a := rng.randf() * TAU
		var q := p + Vector3(cos(a), 0.0, sin(a)) * s * 0.9
		var r := rng.randf_range(3.0, 6.0)
		_block(q, Vector3(r, r * 0.8, r), _low(q, r * 0.5) - 0.8, rng.randf() * TAU,
			Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2)), REDS[(k + 1) % REDS.size()])

## A grass-topped rock outcrop: dark stone with a lawn on the top.
func _outcrop(p: Vector3, rng: RandomNumberGenerator) -> void:
	var s := rng.randf_range(12.0, 28.0)
	if not _clear(p, s * 0.8):
		return
	var base := _low(p, s * 0.6) - 2.0
	var yaw := rng.randf() * TAU
	var h := rng.randf_range(6.0, 16.0)
	var d := s * rng.randf_range(0.6, 1.0)
	var top := _block(p, Vector3(s, h, d), base, yaw, Vector2.ZERO, _shade(DARK.lightened(0.08), rng))
	_block(p, Vector3(s + 0.4, 0.8, d + 0.4), top - 0.5, yaw, Vector2.ZERO, MOSS)
	if rng.randf() < 0.5:
		var q := p + Vector3(cos(yaw), 0.0, -sin(yaw)) * s * 0.55
		var s2 := s * 0.5
		var t2 := _block(q, Vector3(s2, h * 0.6, s2), _low(q, s2 * 0.5) - 1.5, yaw + 0.5, Vector2.ZERO,
			_shade(DARK.lightened(0.12), rng))
		_block(q, Vector3(s2 + 0.3, 0.7, s2 + 0.3), t2 - 0.45, yaw + 0.5, Vector2.ZERO, MOSS)

## A natural arch: two legs and a slab across, high enough to walk (or drive)
## under.
func _arch(p: Vector3, rng: RandomNumberGenerator, color: Color) -> void:
	var span := rng.randf_range(22.0, 36.0)
	if not _clear(p, span * 0.7):
		return
	var yaw := rng.randf() * TAU
	var across := Vector3(cos(yaw), 0.0, -sin(yaw))
	var leg := rng.randf_range(7.0, 11.0)
	var rise := rng.randf_range(14.0, 24.0)
	var ground := _low(p, span * 0.6)
	var top := ground
	for s in [-1.0, 1.0]:
		var q: Vector3 = p + across * s * span * 0.5
		top = maxf(top, _block(q, Vector3(leg, rise, leg * 1.1), _low(q, leg * 0.6) - 2.0, yaw,
			Vector2(0.0, s * 0.06), _shade(color, rng)))
	_block(p, Vector3(span + leg, rng.randf_range(6.0, 9.0), leg * 1.2), ground + rise - 3.0, yaw,
		Vector2.ZERO, _shade(color.lightened(0.04), rng))
