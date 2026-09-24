class_name Decor
extends Node3D

## The small stuff that makes open ground look like somewhere: grass and
## flowers in the woods, ferns and toadstools under the taiga, reeds and lily
## pads in the swamp, cacti and dry scrub in the desert, scree on the hills and
## drifts in the snow - and boulders everywhere, big enough to walk round.
##
## None of it is a resource and none of it (bar the boulders) collides. It is
## drawn as MultiMeshes in tiles, each tile fading out past a distance, so the
## whole map can be dressed for a few dozen draw calls in view at a time.

const TILE := 75.0
const REACH := 150.0

## Per biome: [kind, instances per terrain cell]. Fractions are chances.
const PLANTING := {
	Terrain.Biome.WOODLAND: [["grass", 1.4], ["flower_red", 0.12], ["flower_yellow", 0.12],
		["flower_white", 0.10], ["bush", 0.20], ["pebbles", 0.08]],
	Terrain.Biome.TAIGA: [["grass", 0.6], ["fern", 0.7], ["toadstool", 0.12], ["bush", 0.14],
		["pebbles", 0.12]],
	Terrain.Biome.SWAMP: [["reeds", 1.1], ["grass", 0.5], ["lily", 0.6], ["toadstool", 0.06]],
	Terrain.Biome.DESERT: [["cactus", 0.07], ["scrub", 0.28], ["pebbles", 0.30]],
	Terrain.Biome.MOUNTAIN: [["pebbles", 0.7], ["grass", 0.18], ["shard", 0.10]],
	Terrain.Biome.SNOW: [["drift", 0.30], ["shard", 0.12], ["pebbles", 0.15]],
}
## Boulders per terrain cell, by biome.
const BOULDERS := {
	Terrain.Biome.WOODLAND: 0.012, Terrain.Biome.TAIGA: 0.02, Terrain.Biome.SWAMP: 0.004,
	Terrain.Biome.DESERT: 0.02, Terrain.Biome.MOUNTAIN: 0.035, Terrain.Biome.SNOW: 0.02,
}

var terrain: Terrain
var instance_count: int = 0
var boulder_count: int = 0
var _meshes: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func setup(p_terrain: Terrain, seed_value: int) -> void:
	terrain = p_terrain
	_rng.seed = seed_value

func _ready() -> void:
	_build_meshes()
	_scatter()

# --- The pieces ------------------------------------------------------------

func _build_meshes() -> void:
	var g: Greeble
	var grass := Color(0.36, 0.60, 0.24)
	g = Greeble.new()
	for i in 5:
		var a := TAU * float(i) / 5.0
		var tilt := Basis(Vector3(cos(a + PI * 0.5), 0, sin(a + PI * 0.5)), 0.25)
		g.prism(3, 0.07, 0.0, 0.45 + 0.12 * float(i % 3), Transform3D(tilt, Vector3(cos(a) * 0.12, 0, sin(a) * 0.12)),
			grass.lightened(0.04 * float(i % 3)))
	_meshes["grass"] = g.commit()

	for spec in [["flower_red", Color(0.92, 0.30, 0.28)], ["flower_yellow", Color(0.98, 0.84, 0.25)],
			["flower_white", Color(0.95, 0.95, 0.92)]]:
		g = Greeble.new()
		for i in 3:
			var a := TAU * float(i) / 3.0
			var p := Vector3(cos(a) * 0.18, 0, sin(a) * 0.18)
			g.block(Vector3(0.03, 0.34, 0.03), p + Vector3(0, 0.17, 0), grass.darkened(0.1))
			g.box(Vector3(0.13, 0.05, 0.13), Transform3D(Basis(Vector3.UP, a), p + Vector3(0, 0.36, 0)), spec[1])
			g.block(Vector3(0.05, 0.06, 0.05), p + Vector3(0, 0.39, 0), Color(0.95, 0.75, 0.2))
		_meshes[spec[0]] = g.commit()

	g = Greeble.new()
	var leaf := Color(0.24, 0.46, 0.20)
	g.box(Vector3(1.1, 0.7, 0.9), Transform3D(Basis(Vector3.UP, 0.3), Vector3(0, 0.35, 0)), leaf)
	g.box(Vector3(0.8, 0.6, 0.8), Transform3D(Basis(Vector3.UP, 1.1), Vector3(0.35, 0.55, 0.2)), leaf.lightened(0.08))
	g.box(Vector3(0.7, 0.5, 0.6), Transform3D(Basis(Vector3.UP, 0.7), Vector3(-0.3, 0.5, -0.2)), leaf.darkened(0.06))
	_meshes["bush"] = g.commit()

	g = Greeble.new()
	var frond := Color(0.22, 0.44, 0.26)
	for i in 6:
		var a := TAU * float(i) / 6.0
		var dir := Vector3(cos(a), 0, sin(a))
		var basis := Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.RIGHT, 0.55)
		g.box(Vector3(0.16, 0.03, 0.75), Transform3D(basis, dir * 0.3 + Vector3(0, 0.2, 0)), frond.lightened(0.05 * float(i % 2)))
	_meshes["fern"] = g.commit()

	g = Greeble.new()
	g.prism(6, 0.07, 0.06, 0.22, Transform3D(), Color(0.92, 0.88, 0.80))
	g.prism(6, 0.22, 0.05, 0.14, Transform3D(Basis(), Vector3(0, 0.2, 0)), Color(0.82, 0.18, 0.15))
	g.prism(5, 0.05, 0.04, 0.14, Transform3D(Basis(), Vector3(0.18, 0, 0.1)), Color(0.92, 0.88, 0.80))
	g.prism(5, 0.12, 0.03, 0.08, Transform3D(Basis(), Vector3(0.18, 0.13, 0.1)), Color(0.82, 0.18, 0.15))
	_meshes["toadstool"] = g.commit()

	g = Greeble.new()
	for i in 7:
		var a := TAU * float(i) / 7.0
		var r := 0.12 + 0.08 * float(i % 3)
		g.box(Vector3(0.05, 1.2 + 0.25 * float(i % 3), 0.05), Transform3D(Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), 0.08),
			Vector3(cos(a) * r, 0.6, sin(a) * r)), Color(0.46, 0.52, 0.28).lightened(0.05 * float(i % 2)))
	g.block(Vector3(0.08, 0.22, 0.08), Vector3(0.12, 1.35, 0.0), Color(0.40, 0.28, 0.18))
	_meshes["reeds"] = g.commit()

	g = Greeble.new()
	g.prism(7, 0.45, 0.45, 0.04, Transform3D(), Color(0.26, 0.50, 0.24))
	g.block(Vector3(0.12, 0.08, 0.12), Vector3(0.1, 0.05, 0.05), Color(0.95, 0.72, 0.85))
	_meshes["lily"] = g.commit()

	g = Greeble.new()
	var cactus := Color(0.30, 0.52, 0.30)
	g.box(Vector3(0.45, 2.4, 0.45), Transform3D(Basis(), Vector3(0, 1.2, 0)), cactus)
	g.box(Vector3(0.8, 0.3, 0.3), Transform3D(Basis(), Vector3(0.45, 1.1, 0)), cactus)
	g.box(Vector3(0.3, 0.9, 0.3), Transform3D(Basis(), Vector3(0.75, 1.55, 0)), cactus.lightened(0.05))
	g.box(Vector3(0.6, 0.28, 0.28), Transform3D(Basis(), Vector3(-0.38, 1.5, 0)), cactus)
	g.box(Vector3(0.28, 0.6, 0.28), Transform3D(Basis(), Vector3(-0.6, 1.75, 0)), cactus.lightened(0.05))
	g.block(Vector3(0.18, 0.12, 0.18), Vector3(0, 2.45, 0), Color(0.95, 0.55, 0.65))
	_meshes["cactus"] = g.commit()

	g = Greeble.new()
	var twig := Color(0.55, 0.42, 0.28)
	for i in 6:
		var a := TAU * float(i) / 6.0
		g.pipe(Vector3.ZERO, Vector3(cos(a) * 0.45, 0.5 + 0.1 * float(i % 2), sin(a) * 0.45), 0.03, twig, 4)
	_meshes["scrub"] = g.commit()

	g = Greeble.new()
	var stone := Color(0.52, 0.51, 0.49)
	g.box(Vector3(0.35, 0.18, 0.28), Transform3D(Basis(Vector3.UP, 0.4), Vector3(0, 0.07, 0)), stone)
	g.box(Vector3(0.22, 0.14, 0.2), Transform3D(Basis(Vector3.UP, 1.2), Vector3(0.3, 0.05, 0.12)), stone.darkened(0.08))
	g.box(Vector3(0.18, 0.1, 0.16), Transform3D(Basis(Vector3.UP, 2.1), Vector3(-0.22, 0.04, -0.2)), stone.lightened(0.08))
	_meshes["pebbles"] = g.commit()

	g = Greeble.new()
	g.prism(5, 0.3, 0.0, 1.1, Transform3D(Basis(Vector3.FORWARD, 0.2), Vector3.ZERO), Color(0.62, 0.62, 0.64))
	g.prism(5, 0.2, 0.0, 0.7, Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0.3, 0, 0.1)), Color(0.55, 0.55, 0.58))
	_meshes["shard"] = g.commit()

	g = Greeble.new()
	g.prism(7, 1.3, 0.7, 0.45, Transform3D(), Color(0.95, 0.96, 0.99))
	g.prism(6, 0.7, 0.3, 0.25, Transform3D(Basis(), Vector3(0.2, 0.4, 0)), Color(0.98, 0.98, 1.0))
	_meshes["drift"] = g.commit()

# --- Scattering --------------------------------------------------------------

func _scatter() -> void:
	if terrain == null:
		return
	var half := terrain.half_extent
	var tiles := int(ceil(half * 2.0 / TILE))
	# kind -> tile index -> transforms
	var buckets: Dictionary = {}
	var boulders := Greeble.new()
	var body := StaticBody3D.new()
	body.name = "Boulders"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	add_child(body)

	var cells := int(round(half * 2.0 / Terrain.CELL))
	for iz in cells:
		for ix in cells:
			var x0 := -half + float(ix) * Terrain.CELL
			var z0 := -half + float(iz) * Terrain.CELL
			var centre := Vector3(x0 + Terrain.CELL * 0.5, 0, z0 + Terrain.CELL * 0.5)
			# Open water between the islands: nothing grows there.
			if terrain.height_at(centre.x, centre.z) < Terrain.WATER_LEVEL - 1.8:
				continue
			var biome := terrain.biome_at(centre.x, centre.z)
			if not _clear(centre.x, centre.z, 4.0):
				continue
			var tile := int((centre.x + half) / TILE) + int((centre.z + half) / TILE) * tiles
			for entry in PLANTING.get(biome, []):
				var kind: String = entry[0]
				var n := _count(float(entry[1]))
				for i in n:
					var p := Vector3(x0 + _rng.randf() * Terrain.CELL, 0, z0 + _rng.randf() * Terrain.CELL)
					var depth := terrain.water_depth(p.x, p.z)
					if kind == "lily":
						if depth < 0.15 or depth > 1.6:
							continue
						p.y = Terrain.WATER_LEVEL + 0.01
					else:
						if depth > 0.0 and kind != "reeds":
							continue
						if kind == "reeds" and depth > 0.5:
							continue
						if terrain.is_road(p.x, p.z) or _steep(p.x, p.z):
							continue
						p.y = terrain.height_at(p.x, p.z) - 0.02
					var s := _rng.randf_range(0.75, 1.3)
					var xform := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s)), p)
					if not buckets.has(kind):
						buckets[kind] = {}
					if not buckets[kind].has(tile):
						buckets[kind][tile] = []
					buckets[kind][tile].append(xform)
			if _rng.randf() < float(BOULDERS.get(biome, 0.0)) and _clear(centre.x, centre.z, 8.0):
				_boulder(boulders, body, centre + Vector3(_rng.randf_range(-2, 2), 0, _rng.randf_range(-2, 2)), biome)

	for kind in buckets:
		for tile in buckets[kind]:
			var list: Array = buckets[kind][tile]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _meshes[kind]
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = REACH if kind != "cactus" else REACH * 1.6
			mmi.visibility_range_end_margin = 20.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(mmi)
			instance_count += list.size()
	if not boulders.is_empty():
		add_child(boulders.instance("BoulderMesh"))

func _count(rate: float) -> int:
	var n := int(rate)
	if _rng.randf() < rate - float(n):
		n += 1
	return n

## Clear of roads, the levelled sites, cave mouths and deep water.
func _clear(x: float, z: float, margin: float) -> bool:
	if terrain.in_cave_zone(x, z):
		return false
	for site in terrain.build_sites:
		var c: Vector3 = site.centre
		if Vector2(x - c.x, z - c.z).length() < float(site.radius) + margin:
			return false
	return true

func _steep(x: float, z: float) -> bool:
	var dx := terrain.height_at(x + 1.0, z) - terrain.height_at(x - 1.0, z)
	var dz := terrain.height_at(x, z + 1.0) - terrain.height_at(x, z - 1.0)
	return Vector2(dx, dz).length() > 1.4

## A big angular rock: a few leaning blocks, one collider round the lot.
func _boulder(g: Greeble, body: StaticBody3D, at: Vector3, biome: Terrain.Biome) -> void:
	if terrain.is_road(at.x, at.z) or terrain.water_depth(at.x, at.z) > 0.0:
		return
	var base: Color = Terrain.CLIFF_COLORS[biome]
	var size := _rng.randf_range(1.4, 3.4)
	var ground := terrain.height_at(at.x, at.z)
	var yaw := _rng.randf() * TAU
	var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, ground, at.z))
	g.box(Vector3(size * 1.3, size, size), frame * Transform3D(Basis(Vector3.RIGHT, _rng.randf_range(-0.2, 0.2)),
		Vector3(0, size * 0.4, 0)), base)
	g.box(Vector3(size * 0.7, size * 0.8, size * 0.7), frame * Transform3D(Basis(Vector3.FORWARD, _rng.randf_range(-0.3, 0.3)),
		Vector3(size * 0.6, size * 0.3, size * 0.2)), base.lightened(0.07))
	g.box(Vector3(size * 0.6, size * 0.5, size * 0.6), frame * Transform3D(Basis(Vector3.UP, 0.7),
		Vector3(-size * 0.5, size * 0.2, -size * 0.3)), base.darkened(0.06))
	if biome == Terrain.Biome.SNOW:
		g.box(Vector3(size * 1.2, size * 0.12, size * 0.9), frame * Transform3D(Basis(), Vector3(0, size * 0.92, 0)), Color(0.96, 0.97, 1.0))
	elif biome != Terrain.Biome.DESERT:
		g.box(Vector3(size * 0.9, size * 0.08, size * 0.6), frame * Transform3D(Basis(), Vector3(-size * 0.1, size * 0.91, 0.1)), Color(0.30, 0.50, 0.24))
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size * 1.5, size * 0.9, size * 1.1)
	cs.shape = box
	cs.transform = frame * Transform3D(Basis(), Vector3(0, size * 0.4, 0))
	body.add_child(cs)
	boulder_count += 1
