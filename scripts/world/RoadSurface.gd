class_name RoadSurface
extends Node3D

## The roads as something laid on the land rather than a grey stripe of it: a
## textured carriageway sitting a hand's width proud of the graded ground, with
## painted edge lines and a dashed centre line, a gravel verge down each side,
## and marker posts with red reflectors every forty metres. Dirt spurs get a
## rutted track instead, and no paint.
##
## Visual only - the ground under it is already graded flat, so vehicles drive
## on the terrain and the surface simply shows where the road is.

const HALF := 4.8                   ## half the carriageway
const VERGE := 1.5                  ## gravel each side of that
const LIFT := 0.07
const STEP := 3.0                   ## metres between cross-sections
const PIECE := 360.0                ## metres of road per mesh, for culling
const POST_EVERY := 40.0

var terrain: Terrain
static var _materials: Dictionary = {}

func setup(p_terrain: Terrain) -> void:
	terrain = p_terrain

func _ready() -> void:
	if terrain == null:
		return
	for road in terrain.road_paths:
		_build_road(road.path, String(road.style))

func _build_road(path: Array, style: String) -> void:
	if path.size() < 2:
		return
	var span := terrain._path_length(path)
	var dirt := style == "dirt"
	var half := HALF * (0.75 if dirt else 1.0)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var posts := Greeble.new()
	var piece_start := 0.0
	var prev: Array = []
	var along := 0.0
	var next_post := POST_EVERY * 0.5
	while along <= span:
		var p := terrain._point_along(path, along)
		var ahead := terrain._point_along(path, minf(span, along + 1.5))
		var behind := terrain._point_along(path, maxf(0.0, along - 1.5))
		var tangent := Vector3(ahead.x - behind.x, 0.0, ahead.z - behind.z).normalized()
		var side := Vector3(-tangent.z, 0.0, tangent.x)
		var ground := terrain.height_at(p.x, p.z)
		# Over water the bridge deck carries the road; the surface stops at
		# either end of it.
		var wet := ground < Terrain.WATER_LEVEL - 0.05 and not dirt
		var section: Array = []
		if not wet:
			for k in [-(half + VERGE), -half, half, half + VERGE]:
				var q: Vector3 = p + side * float(k)
				section.append(Vector3(q.x, terrain.height_at(q.x, q.z) + LIFT, q.z))
			# The carriageway is graded flat across, so it rides at the
			# centre's height; only the verges follow the land down.
			section[1].y = ground + LIFT
			section[2].y = ground + LIFT
			section[0].y = minf(section[0].y, ground + LIFT - 0.01)
			section[3].y = minf(section[3].y, ground + LIFT - 0.01)
		if not prev.is_empty() and not section.is_empty():
			_quad_strip(verts, uvs, colors, prev, section, along, dirt)
		prev = section
		if not wet and along >= next_post and not dirt:
			next_post += POST_EVERY
			for s in [-1.0, 1.0]:
				var at: Vector3 = p + side * s * (half + VERGE + 0.4)
				at.y = terrain.height_at(at.x, at.z)
				posts.block(Vector3(0.14, 1.0, 0.14), at + Vector3(0, 0.5, 0), Color(0.94, 0.94, 0.9))
				posts.block(Vector3(0.16, 0.14, 0.16), at + Vector3(0, 0.86, 0), Color(0.9, 0.12, 0.1), true)
		if along - piece_start >= PIECE:
			_flush(verts, uvs, colors, dirt)
			verts = PackedVector3Array()
			uvs = PackedVector2Array()
			colors = PackedColorArray()
			piece_start = along
		along += STEP
	_flush(verts, uvs, colors, dirt)
	if not posts.is_empty():
		add_child(posts.instance("RoadPosts", false))

## One step of road: the verge, the carriageway and the other verge.
func _quad_strip(verts: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray,
		a: Array, b: Array, along: float, dirt: bool) -> void:
	var v0 := (along - STEP) / 8.0
	var v1 := along / 8.0
	var gravel := Color(0.52, 0.47, 0.40) if not dirt else Color(0.46, 0.38, 0.28)
	for k in 3:
		var u0 := 0.0
		var u1 := 1.0
		var tint := Color.WHITE
		if k != 1:
			# Verges use the plain corner of the texture, tinted gravel.
			u0 = 0.0
			u1 = 0.02
			tint = gravel
		_quad(verts, uvs, colors, a[k], a[k + 1], b[k + 1], b[k],
			Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1), tint)

func _quad(verts: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray,
		p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		t0: Vector2, t1: Vector2, t2: Vector2, t3: Vector2, tint: Color) -> void:
	# Wound so the face is up: clockwise seen from above.
	for tri in [[p0, p2, p1, t0, t2, t1], [p0, p3, p2, t0, t3, t2]]:
		var n: Vector3 = ((tri[2] as Vector3) - (tri[0] as Vector3)).cross((tri[1] as Vector3) - (tri[0] as Vector3))
		if n.y < 0.0:
			tri = [tri[0], tri[2], tri[1], tri[3], tri[5], tri[4]]
		for i in 3:
			verts.append(tri[i])
			uvs.append(tri[i + 3])
			colors.append(tint)

func _flush(verts: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, dirt: bool) -> void:
	if verts.is_empty():
		return
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in range(0, verts.size(), 3):
		var n := (verts[i + 2] - verts[i]).cross(verts[i + 1] - verts[i]).normalized()
		normals[i] = n
		normals[i + 1] = n
		normals[i + 2] = n
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Road"
	mi.mesh = mesh
	mi.material_override = material(dirt)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## Asphalt with white edge lines and a dashed yellow centre, or a dirt track
## with two ruts; drawn once and shared.
static func material(dirt: bool) -> StandardMaterial3D:
	var key := "dirt" if dirt else "asphalt"
	if _materials.has(key):
		return _materials[key]
	var w := 64
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91 if dirt else 17
	for y in h:
		for x in w:
			var grain := rng.randf_range(-0.035, 0.035)
			var c: Color
			if dirt:
				c = Color(0.50, 0.40, 0.28).lightened(grain)
				var u := float(x) / float(w)
				if absf(u - 0.3) < 0.06 or absf(u - 0.7) < 0.06:
					c = c.darkened(0.16)
			else:
				c = Color(0.26, 0.26, 0.27).lightened(grain)
				var u2 := float(x) / float(w)
				if (u2 > 0.05 and u2 < 0.08) or (u2 > 0.92 and u2 < 0.95):
					c = Color(0.9, 0.9, 0.86)
				elif absf(u2 - 0.5) < 0.018 and (y % 128) < 72:
					c = Color(0.95, 0.76, 0.16)
			img.set_pixel(x, y, c)
	# The plain corner the verges sample.
	for y in h:
		for x in 2:
			img.set_pixel(x, y, Color(0.95, 0.95, 0.95).darkened(rng.randf_range(0.0, 0.1)))
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials[key] = mat
	return mat
