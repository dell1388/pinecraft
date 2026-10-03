class_name Forester
extends RefCounted

## Ostars' forests, grown from scratch rather than scattered by biome.
##
## Real woods come in stands: a patch where one or two kinds of tree have
## taken hold, thick in the middle and thinning to its edge, with glades
## between and a lone tree out in the open now and then. So:
##
##   1. How wooded the land is, everywhere (`wood_at`): each region of the map
##      has its own (Sylvenwood thick, the desert all but bare), broken up by
##      glades and patchiness, thickened along the rivers, thinning to nothing
##      at the treeline, and nothing on ice, rock ridges, the beach or the plot.
##   2. Stands: spots tried all over the land on a jittered grid, each kept by
##      how wooded it is there, given a size by the same, and a leading and a
##      second kind of tree drawn from the region's mix (`mix_at`: willows and
##      birches along a river, palms at a desert oasis).
##   3. Trees: the budget shared out between the stands by how much wood each
##      holds, and each stand's trees dropped round its middle in a clump
##      (most near the middle, fewer out to the edge), mostly its leading
##      kind, some its second, now and then anything from the mix. A spot too
##      wet, too steep or too close to another tree is passed over.
##   4. Strays: a few lone trees anywhere wooded enough.
##   5. The home wood: a stand of easy pine, birch and oak a short walk from
##      the plot, so the first tree is not a trek.
##
## What comes out is a list of spots per kind of tree; the world gives each
## kind a field (ResourceField) that keeps most of its spots stood and regrows
## what is felled on the spare ones. Same seed, same forests.

## Ostars' own trees, beside the islands' (World.SPECIES). Each cuts into a
## wood the game already has.
const OWN_SPECIES := [
	# The Whispering Woods: tall and pale, a soft blue-green head up high.
	{"name": "Whisperbark", "item": &"wood_birch",
		"biomes": [Terrain.Biome.WOODLAND, Terrain.Biome.TAIGA],
		"leaf": Color(0.46, 0.70, 0.66), "accent": Color(0.74, 0.90, 0.86), "bark": Color(0.80, 0.82, 0.84),
		"work": 560.0, "marks": true,
		"radius": [0.30, 0.42], "height": [11.0, 15.0], "taper": 0.55, "branches": [6, 8],
		"start": 0.52, "pitch": [0.9, 1.3], "length": [0.16, 0.26],
		"foliage": 8.0, "crown": [6.0, 0.4], "style": &"puff"},
	# The Mor'uk Bogs: a fat grey-brown trunk standing in the water, and a
	# flat, spread head of dark moss-green.
	{"name": "Bog Cypress", "item": &"wood_willow",
		"biomes": [Terrain.Biome.SWAMP],
		"leaf": Color(0.30, 0.42, 0.20), "bark": Color(0.40, 0.33, 0.26), "work": 900.0,
		"radius": [0.45, 0.62], "height": [7.0, 9.5], "taper": 0.5, "branches": [5, 7],
		"start": 0.62, "pitch": [1.1, 1.4], "length": [0.22, 0.32],
		"foliage": 7.0, "crown": [7.0, 0.22], "style": &"canopy", "wet": 0.8},
	# Orodruin's slopes: burnt black and bare.
	{"name": "Charred Snag", "item": &"wood_pine",
		"biomes": [Terrain.Biome.ASH],
		"leaf": Color(0.2, 0.2, 0.2), "bark": Color(0.13, 0.11, 0.11), "work": 380.0,
		"radius": [0.22, 0.34], "height": [4.0, 7.0], "taper": 0.45, "branches": [2, 4],
		"start": 0.45, "pitch": [0.5, 1.1], "length": [0.10, 0.18],
		"foliage": 0.0, "crown": [0.0, 0.0], "style": &"bare"},
]

## A tree with less than this weight in its region's mix is rare: never the
## leading or second kind of a stand.
const RARE := 0.6
## Stands are tried this far apart (jittered).
const STAND_GRID := 64.0
## A stand's reach, thinnest to thickest wood.
const STAND_RADIUS := Vector2(22.0, 64.0)
## No two trees closer than this.
const SPACING := 3.6
## Share of the trees that are strays rather than in a stand.
const STRAYS := 0.05
## Trees at most this high up (snow country a little higher).
const TREELINE := Vector2(120.0, 165.0)
## The home wood.
const HOME_WOOD := {"near": 95.0, "far": 175.0, "radius": 34.0, "trees": 70}

var terrain: Terrain
var land: Ostars
## name -> species dictionary
var kinds: Dictionary = {}
## name -> PackedVector3Array of spots (filled by `grow`)
var spots: Dictionary = {}
## name -> Array of spots while growing (an Array is shared, a packed array
## would be copied on every append)
var _growing: Dictionary = {}
## {centre, radius, lead, second}
var stands: Array = []
## The home wood's middle, and its spots (pine, birch, oak by turn).
var home_wood: Vector3 = Vector3.INF
var home_spots := PackedVector3Array()

var _glades := FastNoiseLite.new()
var _patches := FastNoiseLite.new()
var _taken: Dictionary = {}           ## Vector2i -> Array of Vector2
var _rng := RandomNumberGenerator.new()

func _init(p_terrain: Terrain, p_land: Ostars, species: Array, seed_value: int = 20260929) -> void:
	terrain = p_terrain
	land = p_land
	for kind in species + OWN_SPECIES:
		kinds[String(kind.name)] = kind
	_rng.seed = seed_value
	_glades.seed = seed_value + 61
	_glades.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_glades.frequency = 0.011
	_glades.fractal_octaves = 2
	_patches.seed = seed_value + 67
	_patches.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_patches.frequency = 0.0032
	_patches.fractal_octaves = 3

# --- The land -------------------------------------------------------------------

## How wooded the ground is, 0 (nothing grows) to 1 (thick forest).
func wood_at(x: float, z: float) -> float:
	var biome := terrain.biome_at(x, z)
	if biome == Terrain.Biome.ICE:
		return 0.0
	var h := terrain.height_at(x, z)
	var region := land.region_at(x, z)
	var wet_ok := biome == Terrain.Biome.SWAMP
	if h < (-0.6 if wet_ok else 1.0):
		return 0.0
	if land.on_ridge(x, z) or land.on_lake(x, z, 6.0) or terrain.in_clear_zone(x, z, 10.0) \
			or terrain._in_crater(x, z):
		return 0.0
	var wood := float(region.wood)
	# Thick along the rivers: willows and birches, or palms in the desert.
	var rd := land.river_distance(x, z)
	if rd < 80.0:
		var bank := 1.0 - smoothstep(12.0, 80.0, rd)
		var most := 0.45 if biome == Terrain.Biome.DESERT else 0.8
		wood = lerpf(wood, maxf(wood, most), bank)
	# Patchy: some ground thicker, some thinner, and glades.
	wood *= clampf(0.45 + 1.1 * (_patches.get_noise_2d(x, z) * 0.5 + 0.5), 0.0, 1.25)
	wood *= smoothstep(-0.55, -0.2, _glades.get_noise_2d(x, z))
	# Thinning out up to the treeline.
	var cold := biome == Terrain.Biome.SNOW
	var line := TREELINE.y if cold else TREELINE.x
	wood *= 1.0 - smoothstep(line - 45.0, line, h)
	return clampf(wood, 0.0, 1.0)

## The kinds of tree at a point and how common each is.
func mix_at(x: float, z: float) -> Dictionary:
	var region := land.region_at(x, z)
	var mix: Dictionary = (region.mix as Dictionary).duplicate()
	var biome := terrain.biome_at(x, z)
	if land.river_distance(x, z) < 60.0:
		if biome == Terrain.Biome.DESERT:
			mix["Palm"] = float(mix.get("Palm", 0.0)) + 4.0
		elif biome != Terrain.Biome.SNOW:
			mix["Willow"] = float(mix.get("Willow", 0.0)) + 2.0
			mix["Birch"] = float(mix.get("Birch", 0.0)) + 1.0
	# The mountains keep their own trees whatever region they run through.
	if biome == Terrain.Biome.MOUNTAIN and region.kind != Ostars.Kind.CRAGS:
		mix = {"Pine": 3.0, "Ironwood": 2.0, "Spruce": 1.0, "Dead Snag": 1.0}
	elif biome == Terrain.Biome.SNOW and not (mix.has("Spruce")):
		mix = {"Spruce": 4.0, "Frostbark": 0.5, "Pine": 1.0}
	return mix

## The mix without its rare trees (unless that leaves nothing).
func _common(mix: Dictionary) -> Dictionary:
	var out := {}
	for k in mix:
		if float(mix[k]) >= RARE:
			out[k] = mix[k]
	return out if not out.is_empty() else mix

func _pick(mix: Dictionary) -> String:
	var total := 0.0
	for k in mix:
		total += float(mix[k])
	var roll := _rng.randf() * total
	for k in mix:
		roll -= float(mix[k])
		if roll <= 0.0:
			return String(k)
	return String(mix.keys()[0])

## Whether a tree of `kind` can stand at x, z: not too wet for it, not on a
## crag, clear of caves, outcrops, the plot and every other tree.
func can_stand(kind: Dictionary, x: float, z: float) -> bool:
	if terrain.water_depth(x, z) > float(kind.get("wet", 0.0)):
		return false
	if terrain.is_road(x, z) or terrain.in_cave_zone(x, z) or terrain.is_blocked(x, z) \
			or terrain._in_build_site(x, z) or terrain.in_clear_zone(x, z, 8.0):
		return false
	var h := terrain.height_at(x, z)
	if absf(terrain.height_at(x + 2.0, z) - h) > 2.2 or absf(terrain.height_at(x, z + 2.0) - h) > 2.2:
		return false
	return _clear_of_trees(x, z)

func _cell(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / SPACING), floori(z / SPACING))

func _clear_of_trees(x: float, z: float) -> bool:
	var c := _cell(x, z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for q: Vector2 in _taken.get(Vector2i(c.x + dx, c.y + dz), []):
				if q.distance_squared_to(Vector2(x, z)) < SPACING * SPACING:
					return false
	return true

func _take(name: String, x: float, z: float) -> void:
	var c := _cell(x, z)
	if not _taken.has(c):
		_taken[c] = []
	(_taken[c] as Array).append(Vector2(x, z))
	if not _growing.has(name):
		_growing[name] = []
	(_growing[name] as Array).append(Vector3(x, terrain.height_at(x, z), z))

# --- Growing --------------------------------------------------------------------

## Grows the whole map's forest: about `budget` trees. Returns how many.
func grow(budget: int) -> int:
	var half := terrain.half_extent - 60.0
	_grow_home_wood()
	# 2. Stands.
	var n := int(half * 2.0 / STAND_GRID)
	var capacity := 0.0
	for iz in n:
		for ix in n:
			var x := -half + (float(ix) + _rng.randf_range(0.1, 0.9)) * STAND_GRID
			var z := -half + (float(iz) + _rng.randf_range(0.1, 0.9)) * STAND_GRID
			var wood := wood_at(x, z)
			if wood <= 0.02 or _rng.randf() > pow(wood, 0.7):
				continue
			var mix := mix_at(x, z)
			if mix.is_empty():
				continue
			# A rare tree (a small share of its mix) never leads a stand: it
			# turns up one here and there, not a grove of them.
			var common := _common(mix)
			var lead := _pick(common)
			var second := _pick(common)
			var radius := lerpf(STAND_RADIUS.x, STAND_RADIUS.y, wood) * _rng.randf_range(0.8, 1.2)
			var holds := radius * radius * wood
			capacity += holds
			stands.append({"centre": Vector2(x, z), "radius": radius, "wood": wood, "lead": lead,
				"second": second, "mix": mix, "holds": holds})
	# 3. Trees, shared out by what each stand holds.
	var in_stands := int(float(budget) * (1.0 - STRAYS))
	var grown := 0
	for stand in stands:
		var want := int(round(float(in_stands) * float(stand.holds) / maxf(1.0, capacity)))
		grown += _fill_stand(stand, want)
	# 4. Strays.
	var strays := int(float(budget) * STRAYS)
	var tries := 0
	var placed := 0
	while placed < strays and tries < strays * 30:
		tries += 1
		var x := _rng.randf_range(-half, half)
		var z := _rng.randf_range(-half, half)
		var wood := wood_at(x, z)
		if wood <= 0.0 or _rng.randf() > wood * 0.8 + 0.05:
			continue
		var mix := mix_at(x, z)
		var name := _pick(mix)
		if kinds.has(name) and can_stand(kinds[name], x, z):
			_take(name, x, z)
			placed += 1
	for name in _growing:
		spots[name] = PackedVector3Array(_growing[name])
	_growing.clear()
	return grown + placed + home_spots.size()

## A stand's trees: a clump round its middle, thinning out to its edge.
func _fill_stand(stand: Dictionary, want: int) -> int:
	var c: Vector2 = stand.centre
	var radius: float = stand.radius
	var made := 0
	for attempt in want * 4:
		if made >= want:
			break
		# Most near the middle: a normal spread, cut off past the edge.
		var off := Vector2(_rng.randfn(0.0, radius * 0.5), _rng.randfn(0.0, radius * 0.5))
		if off.length() > radius * 1.25:
			continue
		var x := c.x + off.x
		var z := c.y + off.y
		# The land thins a stand where it is less wooded than its middle.
		var here := wood_at(x, z)
		if here <= 0.0 or _rng.randf() > here / float(stand.wood) + 0.25:
			continue
		var roll := _rng.randf()
		var name: String = stand.lead if roll < 0.7 else (stand.second if roll < 0.9 else _pick(stand.mix))
		if not kinds.has(name):
			continue
		var kind: Dictionary = kinds[name]
		if not can_stand(kind, x, z):
			# Too wet for this one: something in the mix that likes it wet.
			var other := _wettest(stand.mix)
			if other == "" or other == name or not can_stand(kinds[other], x, z):
				continue
			name = other
		_take(name, x, z)
		made += 1
	return made

func _wettest(mix: Dictionary) -> String:
	var best := ""
	var wet := 0.0
	for k in mix:
		if kinds.has(k) and float(kinds[k].get("wet", 0.0)) > wet:
			wet = float(kinds[k].get("wet", 0.0))
			best = String(k)
	return best

## 5. The home wood: the most wooded spot a short walk out, packed with pine,
## birch and oak.
func _grow_home_wood() -> void:
	var best := Vector2.INF
	var best_score := -INF
	for i in 48:
		var a := TAU * float(i) / 48.0
		for r in [HOME_WOOD.near, (HOME_WOOD.near + HOME_WOOD.far) * 0.5, HOME_WOOD.far]:
			var p := Vector2(cos(a), sin(a)) * float(r)
			var score := 0.0
			for k in 7:
				var q := p + Vector2(cos(k * TAU / 6.0), sin(k * TAU / 6.0)) * (float(HOME_WOOD.radius) * 0.7 if k > 0 else 0.0)
				if terrain.water_depth(q.x, q.y) > 0.0 or terrain.in_clear_zone(q.x, q.y, 20.0) or land.on_ridge(q.x, q.y):
					score -= 3.0
				else:
					score += 1.0 - absf(terrain.height_at(q.x + 3.0, q.y) - terrain.height_at(q.x, q.y))
			score -= float(r) * 0.004
			if score > best_score:
				best_score = score
				best = p
	if best == Vector2.INF:
		return
	home_wood = Vector3(best.x, terrain.height_at(best.x, best.y), best.y)
	var names := ["Pine", "Birch", "Oak"]
	var radius := float(HOME_WOOD.radius)
	var made := 0
	for attempt in int(HOME_WOOD.trees) * 12:
		if made >= int(HOME_WOOD.trees):
			break
		var a := _rng.randf() * TAU
		var r := radius * sqrt(_rng.randf())
		var x := best.x + cos(a) * r
		var z := best.y + sin(a) * r
		var kind: Dictionary = kinds[names[made % names.size()]]
		if not can_stand(kind, x, z):
			continue
		var c := _cell(x, z)
		if not _taken.has(c):
			_taken[c] = []
		(_taken[c] as Array).append(Vector2(x, z))
		home_spots.append(Vector3(x, terrain.height_at(x, z), z))
		made += 1

## How many spots each kind of tree got, most first: [[name, count]].
func census() -> Array:
	var out: Array = []
	for name in spots:
		out.append([name, (spots[name] as PackedVector3Array).size()])
	out.sort_custom(func(a, b): return a[1] > b[1])
	return out
