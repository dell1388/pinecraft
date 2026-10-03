class_name Prospector
extends RefCounted

## Where the ore and the gems are on Ostars, read from the land itself.
##
## Every spot gets a hardness: how hard its country is to get to and to work -
## the region's own (the meadows round home are easy; the forests a little
## harder; the desert, the bogs and the old woods more; the tundra, the
## Frostpeak Wilds, Orodruin and the Dragon's Teeth hardest), plus how high
## up it is, plus how steep. Each ore and gem has its kind of country and a
## band of hardness: tin, iron, quartz and limestone lie in the easy country
## by home; copper, zinc, amethyst and sandstone in the desert; silver,
## nickel and granite up the mountains; and the best - gold, platinum,
## tungsten, rubies, emeralds, sunstone - only in the hardest country there
## is, high and steep and far off. Within its band an ore is thickest where
## the country is hardest.


## How hard each region's country is, before height and steepness.
const HARD := {
	Ostars.Kind.MEADOW: 0.0, Ostars.Kind.FOREST: 0.5, Ostars.Kind.OLDWOOD: 1.2, Ostars.Kind.WILDS: 2.6,
	Ostars.Kind.TUNDRA: 2.2, Ostars.Kind.ASHLAND: 2.4, Ostars.Kind.SHATTERED: 1.3, Ostars.Kind.DUNES: 1.0,
	Ostars.Kind.BADLANDS: 1.9, Ostars.Kind.BOG: 1.5, Ostars.Kind.CRAGS: 2.6, Ostars.Kind.ISLE: 1.8,
}
## Metres of climb that add one to the hardness, and the most it adds.
const CLIMB := 70.0
const CLIMB_MOST := 2.5

## [item, country (biomes), hardness from, hardness to, how many]
const ORES := [
	# The easy country round home.
	[&"ore_tin", [Terrain.Biome.WOODLAND, Terrain.Biome.TAIGA, Terrain.Biome.MOUNTAIN], 0.0, 1.6, 52],
	[&"gem_quartz", [Terrain.Biome.WOODLAND, Terrain.Biome.MOUNTAIN, Terrain.Biome.DESERT, Terrain.Biome.TAIGA], 0.0, 2.2, 36],
	[&"stone_limestone", [Terrain.Biome.WOODLAND], 0.0, 1.4, 38],
	[&"ore_iron", [Terrain.Biome.MOUNTAIN, Terrain.Biome.TAIGA, Terrain.Biome.WOODLAND], 0.3, 2.6, 64],
	# A trip out: the desert, the foothills, the bogs.
	[&"ore_zinc", [Terrain.Biome.DESERT, Terrain.Biome.MOUNTAIN, Terrain.Biome.WOODLAND], 0.6, 2.4, 40],
	[&"ore_copper", [Terrain.Biome.DESERT, Terrain.Biome.MOUNTAIN], 0.8, 2.8, 46],
	[&"stone_sandstone", [Terrain.Biome.DESERT], 0.5, 9.0, 42],
	[&"stone_slate", [Terrain.Biome.TAIGA, Terrain.Biome.SWAMP], 0.8, 3.5, 30],
	[&"ore_magnetite", [Terrain.Biome.MOUNTAIN, Terrain.Biome.TAIGA], 1.4, 3.6, 30],
	[&"gem_amethyst", [Terrain.Biome.MOUNTAIN, Terrain.Biome.DESERT], 1.4, 3.8, 24],
	[&"gem_jade", [Terrain.Biome.SWAMP, Terrain.Biome.WOODLAND, Terrain.Biome.TAIGA], 1.4, 4.0, 22],
	[&"ore_cobalt", [Terrain.Biome.SWAMP, Terrain.Biome.MOUNTAIN], 1.5, 4.0, 22],
	# Up the mountains and out to the far country.
	[&"ore_silver", [Terrain.Biome.TAIGA, Terrain.Biome.SNOW, Terrain.Biome.MOUNTAIN], 1.8, 4.4, 30],
	[&"ore_nickel", [Terrain.Biome.SNOW, Terrain.Biome.TAIGA, Terrain.Biome.MOUNTAIN], 2.0, 4.6, 26],
	[&"stone_granite", [Terrain.Biome.MOUNTAIN, Terrain.Biome.SNOW], 1.6, 9.0, 30],
	[&"gem_obsidian", [Terrain.Biome.ASH, Terrain.Biome.DESERT, Terrain.Biome.MOUNTAIN], 2.2, 9.0, 26],
	[&"stone_basalt", [Terrain.Biome.ASH, Terrain.Biome.MOUNTAIN], 2.2, 9.0, 24],
	[&"ore_bismuth", [Terrain.Biome.DESERT], 1.9, 9.0, 16],
	[&"stone_marble", [Terrain.Biome.SNOW], 2.2, 9.0, 20],
	[&"gem_turquoise", [Terrain.Biome.DESERT, Terrain.Biome.MOUNTAIN], 2.4, 9.0, 12],
	# Only the hardest country: high, steep and far.
	[&"gem_emerald", [Terrain.Biome.SWAMP, Terrain.Biome.WOODLAND, Terrain.Biome.TAIGA], 2.3, 9.0, 12],
	[&"ore_tungsten", [Terrain.Biome.MOUNTAIN, Terrain.Biome.SNOW, Terrain.Biome.ASH], 3.0, 9.0, 20],
	[&"ore_gold", [Terrain.Biome.SNOW, Terrain.Biome.MOUNTAIN], 3.2, 9.0, 16],
	[&"gem_ruby", [Terrain.Biome.DESERT, Terrain.Biome.MOUNTAIN, Terrain.Biome.ASH], 3.0, 9.0, 12],
	[&"ore_sunstone", [Terrain.Biome.ASH, Terrain.Biome.DESERT], 3.2, 9.0, 9],
	[&"ore_platinum", [Terrain.Biome.SNOW], 3.4, 9.0, 10],
	[&"gem_lapis", [Terrain.Biome.WOODLAND, Terrain.Biome.SWAMP, Terrain.Biome.DESERT, Terrain.Biome.MOUNTAIN, Terrain.Biome.TAIGA, Terrain.Biome.SNOW, Terrain.Biome.ASH], 2.8, 9.0, 6],
]

var terrain: Terrain
var land: Ostars

func _init(p_terrain: Terrain, p_land: Ostars) -> void:
	terrain = p_terrain
	land = p_land

## How hard the country is at a point.
func hardness(x: float, z: float) -> float:
	var region := land.region_at(x, z)
	var h := terrain.height_at(x, z)
	var hard: float = float(HARD.get(int(region.kind), 1.0))
	hard += clampf(h / CLIMB, 0.0, CLIMB_MOST)
	var slope := absf(terrain.height_at(x + 4.0, z) - terrain.height_at(x - 4.0, z)) \
		+ absf(terrain.height_at(x, z + 4.0) - terrain.height_at(x, z - 4.0))
	hard += clampf(slope / 8.0, 0.0, 1.0) * 0.6
	return hard

## Each ore's spots: [item, PackedVector3Array of spots, PackedFloat32Array of
## weights (thicker where harder), quota].
func survey(step: int = 4) -> Array:
	var biomes := [Terrain.Biome.WOODLAND, Terrain.Biome.SWAMP, Terrain.Biome.DESERT, Terrain.Biome.MOUNTAIN, Terrain.Biome.TAIGA, Terrain.Biome.SNOW, Terrain.Biome.ASH]
	var land_points := terrain.points_in_biomes(biomes, step)
	var hard := PackedFloat32Array()
	hard.resize(land_points.size())
	var kinds := PackedByteArray()
	kinds.resize(land_points.size())
	for i in land_points.size():
		var p := land_points[i]
		hard[i] = hardness(p.x, p.z)
		kinds[i] = int(terrain.biome_at(p.x, p.z))
	var out: Array = []
	for entry in ORES:
		var country: Array = entry[1]
		var lo: float = entry[2]
		var hi: float = entry[3]
		var spots := PackedVector3Array()
		var weights := PackedFloat32Array()
		for i in land_points.size():
			if hard[i] < lo or hard[i] > hi or not country.has(int(kinds[i])):
				continue
			var p := land_points[i]
			if terrain.in_clear_zone(p.x, p.z, 20.0) or land.on_lake(p.x, p.z, 4.0):
				continue
			spots.append(p)
			# Thicker the harder the country, within the band.
			var w := 0.35 + (hard[i] - lo)
			weights.append(w * w)
		out.append([entry[0], spots, weights, int(entry[4])])
	return out

## A sampler that draws from spots by weight, nudged a little.
static func weighted(spots: PackedVector3Array, weights: PackedFloat32Array, terrain: Terrain) -> Callable:
	var cum := PackedFloat32Array()
	var total := 0.0
	for w in weights:
		total += w
		cum.append(total)
	return func(rng: RandomNumberGenerator) -> Vector3:
		var r := rng.randf() * total
		var lo := 0
		var hi := cum.size() - 1
		while lo < hi:
			var mid := (lo + hi) / 2
			if cum[mid] < r:
				lo = mid + 1
			else:
				hi = mid
		var spot := spots[lo]
		var nudged := Vector3(spot.x + rng.randf_range(-4.0, 4.0), 0.0, spot.z + rng.randf_range(-4.0, 4.0))
		if terrain.water_depth(nudged.x, nudged.z) > 0.0 or terrain.biome_at(nudged.x, nudged.z) != terrain.biome_at(spot.x, spot.z):
			return terrain.place(spot)
		return terrain.place(nudged)
