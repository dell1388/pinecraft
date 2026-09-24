class_name Textures
extends RefCounted

## Tileable detail textures, made once in code: a pale greyscale grain that the
## ground, the rock blocks and the roads multiply their own colour by, mapped
## in world space so a hundred-metre slab and a four-metre boulder carry grain
## of the same size. The look is big clean surfaces with a little texture on
## them, not noise.

static var _cache: Dictionary = {}

## `kind`: "grass", "rock", "sand" or "road".
static func detail(kind: String) -> Texture2D:
	if _cache.has(kind):
		return _cache[kind]
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = hash(kind)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.06
	noise.fractal_octaves = 3
	var fine := FastNoiseLite.new()
	fine.seed = hash(kind) + 1
	fine.noise_type = FastNoiseLite.TYPE_VALUE
	fine.frequency = 0.5
	# Seamless images, so the texture tiles without a seam.
	var coarse := noise.get_seamless_image(size, size, false, false, 0.1, true)
	var grain := fine.get_seamless_image(size, size, false, false, 0.1, true)
	for y in size:
		for x in size:
			var n := coarse.get_pixel(x, y).r * 2.0 - 1.0
			var g := grain.get_pixel(x, y).r * 2.0 - 1.0
			var v := 0.92
			match kind:
				"grass":
					v = 0.9 + n * 0.05 + g * 0.035
				"rock":
					# Faint strata, as on a rock part.
					var band := sin(float(y) * TAU / 16.0 + n * 2.0) * 0.5 + 0.5
					v = 0.84 + band * 0.08 + g * 0.04 + n * 0.04
				"sand":
					v = 0.92 + g * 0.045 + n * 0.02
				"road":
					v = 0.9 + g * 0.05 + n * 0.03
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[kind] = tex
	return tex

## A vertex-coloured material with the grain laid on in world space.
static func material(kind: String, metres_per_tile: float = 8.0, roughness: float = 0.95) -> StandardMaterial3D:
	var key := "%s@%.1f" % [kind, metres_per_tile]
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = detail(kind)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / metres_per_tile
	mat.roughness = roughness
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = mat
	return mat
