class_name GrassField
extends Node3D

## Grass and wild flowers over the ground round the camera - only the look:
## nothing collides with it, nothing grows or is picked.
##
## The ground is cut into 16 m chunks. Every chunk draws the same few thousand
## tufts of blades (one MultiMesh, made once and shared), and its own small
## picture of the ground under it - a 9 x 9 lattice of heights, how grassy and
## how flowery each spot is, and the colour of the plate there - which the
## vertex shader reads to stand each tuft on the ground in the ground's own
## colour, or fold it away where nothing grows (roads, water, rock, sand,
## snow, the plot, the shops' yards). So a chunk costs a handful of height
## lookups to make, not one per blade, and nothing per frame.
##
## Cheap to draw: blades are single triangles with their normals up (lit like
## the ground they grow from), cast no shadow, and thin out with distance - a
## chunk further off draws a half or a quarter of its tufts, the shader
## thinning smoothly in between so nothing pops - then shrink into the ground
## at the edge of their range. The wind sways them (with shaders on) and they
## bend away from your legs as you walk through.

const CHUNK := 16.0
## Lattice intervals per chunk side: a point every 2 m.
const LATTICE := 8
## Tufts in a whole chunk (44 x 44, jittered): seven and a half a square metre,
## five blades each.
const SIDE := 44
## Flowers in a chunk, before the ground says how many actually grow.
const FLOWER_SIDE := 13
## Milliseconds a frame spent making chunks, at most.
const BUDGET_MS := 1.2

## How far grass reaches, by the Grass setting (1 short, 2 far).
const REACH := [0.0, 32.0, 60.0]

## Per biome: [grass 0..1, flowers 0..1].
const GROWTH := {
	Terrain.Biome.WOODLAND: [1.0, 0.4],
	Terrain.Biome.TAIGA: [0.75, 0.12],
	Terrain.Biome.SWAMP: [0.7, 0.12],
	Terrain.Biome.MOUNTAIN: [0.45, 0.25],
	Terrain.Biome.DESERT: [0.0, 0.0],
	Terrain.Biome.SNOW: [0.0, 0.0],
	Terrain.Biome.ICE: [0.0, 0.0],
	Terrain.Biome.ASH: [0.0, 0.0],
}

var terrain: Terrain
## Whoever the grass bends away from (the player).
var pusher: Node3D
## 0 off, 1 short, 2 far.
var level: int = 2
## Swaying in the wind (the Shaders setting).
var wind: bool = true
## The camera it grows round; the viewport's own if not set.
var camera: Camera3D
## Squares nothing grows on: [centre, half size] - the plot's concrete, which
## the grass would come up through. The levelled ground round it is grassed.
var keep_off: Array = []

var _chunks: Dictionary = {}          ## Vector2i -> Chunk
var _pool: Array = []
var _flower_noise := FastNoiseLite.new()
## Built tufts, for the tests and the perf harness.
var chunk_count: int = 0

class Chunk:
	var key: Vector2i
	var node: Node3D
	var grass: MultiMeshInstance3D
	var flowers: MultiMeshInstance3D
	var material: ShaderMaterial
	var ground: ImageTexture
	var tint: ImageTexture
	var lod: int = -1
	var empty: bool = false

static var _shader: Shader
static var _clump: ArrayMesh
static var _flower: ArrayMesh
static var _patterns: Array = []     ## grass MultiMesh: all, half, quarter
static var _flower_pattern: MultiMesh
static var _gust: Texture2D

func setup(p_terrain: Terrain) -> void:
	terrain = p_terrain
	_flower_noise.seed = 4411
	_flower_noise.frequency = 0.018

func _ready() -> void:
	_make_shared()

func reach() -> float:
	return float(REACH[clampi(level, 0, 2)])

## Grows it all again (after the plot has grown, say).
func refresh() -> void:
	_job = {}
	_idle_at = Vector3(INF, INF, INF)
	for key in _chunks.keys():
		_free_chunk(key)

## Grass setting and shaders setting, applied.
func configure(p_level: int, p_wind: bool) -> void:
	var changed := p_level != level
	level = p_level
	wind = p_wind
	if level <= 0 or changed:
		refresh()
	for c: Chunk in _chunks.values():
		if c.material != null:
			_set_fade(c.material)
	visible = level > 0

# --- Every frame ------------------------------------------------------------------

## Microseconds spent this frame (read by the perf harness).
static var spent_usec: int = 0

func _process(_delta: float) -> void:
	var t_in := Time.get_ticks_usec()
	_step()
	spent_usec += Time.get_ticks_usec() - t_in

func _step() -> void:
	if level <= 0 or terrain == null:
		return
	var cam := _camera()
	if cam == null:
		return
	var eye := cam.global_position
	var push := Vector3(0, -10000, 0)
	if pusher != null and is_instance_valid(pusher):
		push = pusher.global_position
	# Drop what is out of reach, set how many tufts each chunk draws.
	var r := reach()
	for key in _chunks.keys():
		var c: Chunk = _chunks[key]
		var near := _nearest(key, eye)
		if near > r + CHUNK:
			_free_chunk(key)
			continue
		if c.empty:
			continue
		_set_lod(c, near)
		c.material.set_shader_parameter(&"pusher", push)
	# Make what has come into reach, nearest first, a few rows of its lattice
	# at a time, within the time allowed.
	# (Nothing to look for until the camera has moved or a chunk was made.)
	if _job.is_empty() and _idle_at.distance_to(eye) < 2.0:
		return
	var t0 := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - t0) / 1000.0 < BUDGET_MS:
		if _job.is_empty():
			var wanted := _wanted(eye, r)
			if wanted.is_empty():
				_idle_at = eye
				break
			_job = _start_chunk(wanted[0])
		_chunk_row(_job)
		if int(_job.row) > LATTICE:
			_finish_chunk(_job)
			_job = {}

## Where the camera was when every chunk in reach was made.
var _idle_at := Vector3(INF, INF, INF)

## A chunk being made: {key, row, ground, tint, ...}.
var _job: Dictionary = {}

## Every chunk in reach round a point at once: for the first frame, and tests.
func build_around(at: Vector3) -> void:
	_job = {}
	for key in _wanted(at, reach()):
		var job := _start_chunk(key)
		while int(job.row) <= LATTICE:
			_chunk_row(job)
		_finish_chunk(job)
	for key in _chunks:
		var c: Chunk = _chunks[key]
		if not c.empty:
			_set_lod(c, _nearest(key, at))

func _camera() -> Camera3D:
	if camera != null and is_instance_valid(camera) and camera.is_inside_tree():
		return camera
	return get_viewport().get_camera_3d() if is_inside_tree() else null

## The chunks in reach of `eye` not made yet, nearest first.
func _wanted(eye: Vector3, r: float) -> Array:
	var out: Array = []
	# High above the ground there is nothing near enough to see.
	var ground := terrain.height_at(eye.x, eye.z)
	if is_nan(ground):
		ground = eye.y
	var up := eye.y - ground
	if up > r:
		return out
	var flat := sqrt(maxf(0.0, r * r - up * up))
	var lo := Vector2i(int(floor((eye.x - flat) / CHUNK)), int(floor((eye.z - flat) / CHUNK)))
	var hi := Vector2i(int(floor((eye.x + flat) / CHUNK)), int(floor((eye.z + flat) / CHUNK)))
	var list: Array = []
	for kz in range(lo.y, hi.y + 1):
		for kx in range(lo.x, hi.x + 1):
			var key := Vector2i(kx, kz)
			if _chunks.has(key):
				continue
			var d := _nearest(key, Vector3(eye.x, ground, eye.z))
			if d <= flat:
				list.append([d, key])
	list.sort_custom(func(a, b): return a[0] < b[0])
	for e in list:
		out.append(e[1])
	return out

## How close `eye` comes to a chunk, flat on the ground.
func _nearest(key: Vector2i, eye: Vector3) -> float:
	var x0 := float(key.x) * CHUNK
	var z0 := float(key.y) * CHUNK
	var dx := maxf(0.0, maxf(x0 - eye.x, eye.x - (x0 + CHUNK)))
	var dz := maxf(0.0, maxf(z0 - eye.z, eye.z - (z0 + CHUNK)))
	return Vector2(dx, dz).length()

## How many of its tufts a spot this far off keeps (the shader's own rule,
## see keep() there): all near, half, then a quarter.
func keep_at(d: float) -> float:
	var r := reach()
	var a := r * 0.22
	var b := r * 0.42
	var c := r * 0.68
	if d <= a:
		return 1.0
	if d <= b:
		return lerpf(1.0, 0.5, (d - a) / (b - a))
	if d <= c:
		return lerpf(0.5, 0.25, (d - b) / (c - b))
	return 0.25

func _set_lod(c: Chunk, near: float) -> void:
	var keep := keep_at(near)
	var lod := 0 if keep > 0.5 else (1 if keep > 0.25 else 2)
	if lod != c.lod:
		c.lod = lod
		c.grass.multimesh = _patterns[lod]
		# Flowers only nearer in; out there they are specks.
		c.flowers.visible = lod < 2

func _set_fade(m: ShaderMaterial) -> void:
	var r := reach()
	m.set_shader_parameter(&"thin", Vector3(r * 0.22, r * 0.42, r * 0.68))
	m.set_shader_parameter(&"gone", Vector2(r * 0.78, r))
	m.set_shader_parameter(&"wind", 1.0 if wind else 0.0)

# --- A chunk ------------------------------------------------------------------------

func _start_chunk(key: Vector2i) -> Dictionary:
	var n := LATTICE + 1
	var x0 := float(key.x) * CHUNK
	var z0 := float(key.y) * CHUNK
	var ground := PackedFloat32Array()
	ground.resize(n * n * 4)
	var tint := PackedByteArray()
	tint.resize(n * n * 4)
	# Only the yards and cave mouths near this chunk are looked at, point by
	# point.
	var sites := PackedFloat32Array()
	for site in terrain.build_sites:
		var c: Vector3 = site.centre
		if terrain.in_clear_zone(c.x, c.z):
			continue
		var reach_out := float(site.radius) + 1.0
		if c.x + reach_out >= x0 and c.x - reach_out <= x0 + CHUNK and c.z + reach_out >= z0 and c.z - reach_out <= z0 + CHUNK:
			sites.append_array(PackedFloat32Array([c.x, c.z, reach_out]))
	var caves := PackedFloat32Array()
	for cave in terrain.caves:
		var e: Vector3 = cave.entrance
		var d: Vector3 = cave.dir
		var m := e + d * Cave.SHAFT_LENGTH * 0.5
		if m.x + 16.0 >= x0 and m.x - 16.0 <= x0 + CHUNK and m.z + 16.0 >= z0 and m.z - 16.0 <= z0 + CHUNK:
			caves.append_array(PackedFloat32Array([m.x, m.z]))
	return {"key": key, "row": 0, "ground": ground, "tint": tint, "lo": INF, "hi": -INF, "grows": false,
		"sites": sites, "caves": caves}

func _chunk_row(job: Dictionary) -> void:
	var n := LATTICE + 1
	var step := CHUNK / float(LATTICE)
	var key: Vector2i = job.key
	var x0 := float(key.x) * CHUNK
	var z0 := float(key.y) * CHUNK
	var ground: PackedFloat32Array = job.ground
	var tint: PackedByteArray = job.tint
	var iz: int = job.row
	var z := z0 + float(iz) * step
	for ix in n:
		var x := x0 + float(ix) * step
		var here := terrain.ground_sample(x, z)
		var h: float = here[0]
		var col: Color = here[1]
		var growth := Vector2.ZERO
		if is_nan(h):
			h = terrain.grid_height(x, z)
		else:
			growth = _growth(x, z, h, col, job.sites, job.caves)
		job.lo = minf(float(job.lo), h)
		job.hi = maxf(float(job.hi), h)
		if growth.x > 0.0 or growth.y > 0.0:
			job.grows = true
		var i := (iz * n + ix) * 4
		ground[i] = h
		ground[i + 1] = growth.x
		ground[i + 2] = growth.y
		ground[i + 3] = 0.0
		tint[i] = int(clampf(col.r, 0.0, 1.0) * 255.0)
		tint[i + 1] = int(clampf(col.g, 0.0, 1.0) * 255.0)
		tint[i + 2] = int(clampf(col.b, 0.0, 1.0) * 255.0)
		tint[i + 3] = 255
	# Packed arrays are copied on write: put them back.
	job.ground = ground
	job.tint = tint
	job.row = iz + 1

func _finish_chunk(job: Dictionary) -> void:
	var n := LATTICE + 1
	var key: Vector2i = job.key
	var x0 := float(key.x) * CHUNK
	var z0 := float(key.y) * CHUNK
	var c: Chunk = _pool.pop_back() if not _pool.is_empty() else _new_chunk()
	c.key = key
	c.lod = -1
	c.empty = not bool(job.grows)
	_chunks[key] = c
	chunk_count += 1
	if c.empty:
		c.node.visible = false
		return
	c.node.visible = true
	c.node.position = Vector3(x0, 0.0, z0)
	var gimg := Image.create_from_data(n, n, false, Image.FORMAT_RGBAF, (job.ground as PackedFloat32Array).to_byte_array())
	var timg := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, job.tint)
	if c.ground == null:
		c.ground = ImageTexture.create_from_image(gimg)
		c.tint = ImageTexture.create_from_image(timg)
		c.material.set_shader_parameter(&"ground", c.ground)
		c.material.set_shader_parameter(&"tint", c.tint)
	else:
		c.ground.update(gimg)
		c.tint.update(timg)
	c.material.set_shader_parameter(&"origin", Vector3(x0, 0.0, z0))
	_set_fade(c.material)
	# The tufts are laid flat in the MultiMesh; the shader stands them on the
	# ground, so the box they are culled by has to be the ground's.
	var lo: float = job.lo
	var hi: float = job.hi
	var box := AABB(Vector3(-1.0, lo - 1.0, -1.0), Vector3(CHUNK + 2.0, hi - lo + 3.0, CHUNK + 2.0))
	c.grass.custom_aabb = box
	c.flowers.custom_aabb = box

func _new_chunk() -> Chunk:
	var c := Chunk.new()
	c.node = Node3D.new()
	add_child(c.node)
	c.material = ShaderMaterial.new()
	c.material.shader = _shader
	c.material.set_shader_parameter(&"gust", _gust)
	c.material.set_shader_parameter(&"chunk", CHUNK)
	c.material.set_shader_parameter(&"lattice", float(LATTICE))
	c.grass = MultiMeshInstance3D.new()
	c.grass.multimesh = _patterns[0]
	c.flowers = MultiMeshInstance3D.new()
	c.flowers.multimesh = _flower_pattern
	for mmi in [c.grass, c.flowers]:
		mmi.material_override = c.material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.node.add_child(mmi)
	return c

func _free_chunk(key: Vector2i) -> void:
	var c: Chunk = _chunks.get(key)
	if c == null:
		return
	_chunks.erase(key)
	chunk_count -= 1
	c.node.visible = false
	_pool.append(c)

## How grassy and how flowery a spot is: [grass, flowers], each 0..1.
## `sites`: [x, z, radius] of the yards near (the shops' and traders' - not
## the levelled ground round the plot, which is only lawn; its concrete is
## kept clear by `keep_off`); `caves`: [x, z] of the cave mouths near.
func _growth(x: float, z: float, h: float, col: Color, sites: PackedFloat32Array,
		caves: PackedFloat32Array) -> Vector2:
	if h < Terrain.WATER_LEVEL + 0.05:
		return Vector2.ZERO
	if terrain.is_road(x, z) or terrain.is_blocked(x, z):
		return Vector2.ZERO
	for square in keep_off:
		var sc: Vector3 = square[0]
		var half := float(square[1])
		if absf(x - sc.x) <= half and absf(z - sc.z) <= half:
			return Vector2.ZERO
	for i in range(0, sites.size(), 3):
		if Vector2(x - sites[i], z - sites[i + 1]).length() < sites[i + 2]:
			return Vector2.ZERO
	for i in range(0, caves.size(), 2):
		if Vector2(x - caves[i], z - caves[i + 1]).length() < 16.0:
			return Vector2.ZERO
	var g: Array = GROWTH.get(terrain.biome_at(x, z), [0.0, 0.0])
	# Grass grows where the ground is green: not on the rock of a steep
	# plate, nor the sand by the water.
	var green := smoothstep(0.015, 0.07, col.g - maxf(col.r, col.b))
	var patch := smoothstep(0.05, 0.45, _flower_noise.get_noise_2d(x, z))
	return Vector2(float(g[0]) * green, float(g[1]) * green * patch)

# --- Made once ------------------------------------------------------------------------

func _make_shared() -> void:
	if _shader != null:
		return
	_shader = Shader.new()
	_shader.code = SHADER
	_clump = _make_clump()
	_flower = _make_flower()
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	# The tufts, jittered over the chunk, each with its own random numbers:
	# r - grows where the ground is at least this grassy; a - kept while the
	# distance keeps at least this share. Sorted by a, so the first half of
	# them are the ones kept at half, the first quarter at a quarter.
	var tufts: Array = []
	for j in SIDE:
		for i in SIDE:
			var p := Vector3((float(i) + rng.randf()) * CHUNK / float(SIDE), 0.0,
				(float(j) + rng.randf()) * CHUNK / float(SIDE))
			var s := rng.randf_range(0.8, 1.25)
			var xform := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.2), s)), p)
			# g - a touch lighter or darker, yellower or bluer, tuft by tuft.
			tufts.append([rng.randf(), xform, Color(rng.randf(), rng.randf(), 0.0, 0.0)])
	tufts.sort_custom(func(a, b): return a[0] < b[0])
	_patterns.clear()
	for share in [1.0, 0.5, 0.25]:
		var n := int(float(tufts.size()) * share)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _clump
		mm.instance_count = n
		for k in n:
			mm.set_instance_transform(k, tufts[k][1])
			var cd: Color = tufts[k][2]
			cd.a = tufts[k][0]
			mm.set_instance_custom_data(k, cd)
		_patterns.append(mm)
	_flower_pattern = MultiMesh.new()
	_flower_pattern.transform_format = MultiMesh.TRANSFORM_3D
	_flower_pattern.use_custom_data = true
	_flower_pattern.mesh = _flower
	_flower_pattern.instance_count = FLOWER_SIDE * FLOWER_SIDE
	var k2 := 0
	for j in FLOWER_SIDE:
		for i in FLOWER_SIDE:
			var p := Vector3((float(i) + rng.randf()) * CHUNK / float(FLOWER_SIDE), 0.0,
				(float(j) + rng.randf()) * CHUNK / float(FLOWER_SIDE))
			var s := rng.randf_range(0.8, 1.2)
			_flower_pattern.set_instance_transform(k2, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), p))
			# g - grows where the ground is at least this flowery; b - which
			# colour; a - kept to this share of the distance, as the grass.
			_flower_pattern.set_instance_custom_data(k2, Color(0.0, rng.randf() * 0.2, rng.randf(), rng.randf() * 0.5))
			k2 += 1
	_gust = _gust_texture()

## Five blades from one spot, leaning out: single thin triangles, their
## normals up. Vertex colour r is how far up the blade (0 root, 1 tip).
static func _make_clump() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for b in 5:
		var a := TAU * float(b) / 5.0 + rng.randf_range(-0.5, 0.5)
		var out := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-out.z, 0.0, out.x)
		var root := out * rng.randf_range(0.02, 0.1)
		var tall := rng.randf_range(0.2, 0.4)
		var tip := root + out * tall * rng.randf_range(0.15, 0.4) + Vector3.UP * tall
		var w := rng.randf_range(0.018, 0.028)
		for v in [[root - side * w, 0.0], [root + side * w, 0.0], [tip, 1.0]]:
			st.set_color(Color(v[1], 0.0, 0.0))
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0])
	return st.commit()

## A wild flower: a stalk, and a flat head of five petals round a middle.
## Vertex colour r is how far up (for the wind), g marks it a flower (0.5 the
## stalk, 1 the petals, 0.8 the middle).
static func _make_flower() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0.03, 0.3, 0.0)
	for v in [[Vector3(-0.012, 0, 0), 0.0], [Vector3(0.012, 0, 0), 0.0], [top, 1.0]]:
		st.set_color(Color(v[1], 0.5, 0.0))
		st.set_normal(Vector3.UP)
		st.add_vertex(v[0])
	# A leaf off the stalk.
	for v in [[Vector3(0.0, 0.06, 0.0), 0.2], [Vector3(0.0, 0.09, 0.012), 0.25], [Vector3(0.09, 0.15, 0.03), 0.45]]:
		st.set_color(Color(v[1], 0.5, 0.0))
		st.set_normal(Vector3.UP)
		st.add_vertex(v[0])
	var petals := 5
	for k in petals:
		var a0 := TAU * float(k) / float(petals)
		var a1 := a0 + TAU / float(petals) * 0.5
		var a2 := a0 + TAU / float(petals)
		var r := 0.085
		for v in [top, top + Vector3(cos(a0) * r * 0.55, 0.01, sin(a0) * r * 0.55), top + Vector3(cos(a1) * r, 0.02, sin(a1) * r)]:
			st.set_color(Color(1.0, 1.0, 0.0))
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
		for v in [top, top + Vector3(cos(a1) * r, 0.02, sin(a1) * r), top + Vector3(cos(a2) * r * 0.55, 0.01, sin(a2) * r * 0.55)]:
			st.set_color(Color(1.0, 1.0, 0.0))
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	# The middle, a little raised.
	for k in 3:
		var a0 := TAU * float(k) / 3.0
		var a1 := TAU * float(k + 1) / 3.0
		for v in [top + Vector3(0, 0.03, 0), top + Vector3(cos(a0) * 0.022, 0.025, sin(a0) * 0.022),
				top + Vector3(cos(a1) * 0.022, 0.025, sin(a1) * 0.022)]:
			st.set_color(Color(1.0, 0.8, 0.0))
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	# Shared corners once each: fewer points for the shader to move.
	st.index()
	return st.commit()

## Soft blotches of wind, tiling, blown across the grass.
static func _gust_texture() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.03
	noise.fractal_octaves = 2
	var img := noise.get_seamless_image(128, 128, false, false, 0.1, true)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

const SHADER := """
shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

uniform sampler2D ground : filter_linear, repeat_disable;
uniform sampler2D tint : filter_linear, repeat_disable;
uniform sampler2D gust : filter_linear_mipmap, repeat_enable;
uniform vec3 origin;
uniform float chunk = 16.0;
uniform float lattice = 8.0;
uniform vec3 thin = vec3(13.0, 25.0, 41.0);
uniform vec2 gone = vec2(47.0, 60.0);
uniform float wind = 1.0;
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform vec3 pusher = vec3(0.0, -10000.0, 0.0);

varying vec3 v_tint;
varying float v_shade;
varying float v_tip;
varying float v_part;
varying vec3 v_petal;

const vec3 PETALS[5] = vec3[5](vec3(0.85, 0.06, 0.05), vec3(1.0, 0.72, 0.02), vec3(0.95, 0.95, 0.92),
	vec3(0.45, 0.12, 0.75), vec3(0.15, 0.30, 0.95));

float keep(float d) {
	if (d <= thin.x) return 1.0;
	if (d <= thin.y) return mix(1.0, 0.5, (d - thin.x) / (thin.y - thin.x));
	if (d <= thin.z) return mix(0.5, 0.25, (d - thin.y) / (thin.z - thin.y));
	return 0.25;
}

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	vec2 local = clamp((base.xz - origin.xz) / chunk, 0.0, 1.0);
	vec2 uv = (local * lattice + 0.5) / (lattice + 1.0);
	vec4 g = textureLod(ground, uv, 0.0);
	vec3 col = textureLod(tint, uv, 0.0).rgb;
	vec3 root = vec3(base.x, g.r, base.z);
	bool flower = COLOR.g > 0.0;
	float want = flower ? g.b : g.g;
	float rnd = flower ? INSTANCE_CUSTOM.g : INSTANCE_CUSTOM.r;
	float d = distance(root, CAMERA_POSITION_WORLD);
	float s = step(rnd, want) * step(INSTANCE_CUSTOM.a, keep(d)) * (1.0 - smoothstep(gone.x, gone.y, d));
	// A little shorter where the ground is only just grassy.
	s *= mix(0.55, 1.0, smoothstep(0.0, 0.6, want));
	vec3 rel = (VERTEX - base) * s;
	float tip = COLOR.r;
	float t = TIME;
	float blow = textureLod(gust, base.xz * 0.012 - wind_dir * t * 0.035, 0.0).r;
	float sway = wind * (sin(t * 2.3 + dot(base.xz, vec2(0.37, 0.23)) + INSTANCE_CUSTOM.r * 6.28) * 0.18
		+ (blow - 0.35) * 1.1);
	rel.xz += wind_dir * sway * tip * tip * 0.20 * s;
	// Trodden down round whoever walks through.
	vec2 away = base.xz - pusher.xz;
	float pd = length(away);
	float press = (1.0 - smoothstep(0.25, 1.2, pd)) * step(abs(pusher.y - g.r), 1.8);
	rel.xz += normalize(away + vec2(0.0001)) * press * tip * 0.30 * s;
	rel.y *= 1.0 - press * 0.6;
	VERTEX = root + rel;
	NORMAL = vec3(0.0, 1.0, 0.0);
	v_tint = col;
	v_shade = flower ? 0.5 : INSTANCE_CUSTOM.g;
	v_tip = tip;
	v_part = COLOR.g;
	v_petal = PETALS[clamp(int(INSTANCE_CUSTOM.b * 5.0), 0, 4)];
}

void fragment() {
	vec3 c = v_tint * mix(0.78, 1.16, v_tip);
	// Tuft by tuft a little lighter or darker, yellower or bluer.
	c *= mix(0.9, 1.08, v_shade);
	c = mix(c, c * vec3(1.1, 1.06, 0.72), smoothstep(0.7, 1.0, v_shade) * 0.6);
	// Sun-bleached tips, a little.
	c = mix(c, c * vec3(1.12, 1.08, 0.78), v_tip * v_tip * 0.3);
	if (v_part > 0.9) {
		c = v_petal;
	} else if (v_part > 0.7) {
		c = vec3(0.95, 0.80, 0.20);
	}
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	BACKLIGHT = c * 0.35 * v_tip;
}
"""
