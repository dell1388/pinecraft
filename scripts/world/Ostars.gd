class_name Ostars
extends RefCounted

## Ostars, the Known Continent: the second map, drawn after the owner's map of
## it rather than rolled from noise. One big continent in a 4.8 km square of
## sea, and the islands off it:
##
##   north       the Frostpeak Wilds (snow crags) and the Frostpeak Tundra, flat
##               snowfields with frozen lakes
##   across it   the Avalanche Mountains, snow-capped, with two passes through
##   west        Sylvenwood, the Silverflow River down to Halyon Port, Mt.
##               Orodruin smoking on the coast, and over the Aethel Sea the
##               Great Sky Arch to the Whispering Woods on their island
##   middle      the Shattered Desert, the Al-Khalid Sands, and the Emperor's
##               Spine, a rock ridge with a flat top running through them
##   south       the Sunscorched Badlands and the Meteor Crater of Kael
##   south-west  the Gulf of Krakens
##   east        the other Whispering Woods, the Ostar River past Ostaros City
##               to the Bay of the Wyrm, Sylvanwood, the two Mor'uk Bogs, and
##               the Veiled Archipelago off the coast
##   south-east  the Dragon's Teeth, running out to their own island
##
## No buildings: the towns on the map are empty sites. Home (the plot) is in
## the Silverflow Meadows at the middle of the map, where the plot always is.
##
## This is the terrain's shaper (see Terrain.shaper): `sample` gives the biome
## and the height at any point, from worker threads, so it only reads.
## World coordinates throughout: x east, z south, metres.

## Bumped whenever the shape changes, so an old map cache is not trusted.
const VERSION := 3
const SEA_FLOOR := -7.0
const MAP_HALF := 2400.0
const SNOWLINE := 105.0

# --- The coast -------------------------------------------------------------------
# Ellipses: [centre x, centre z, radius x, radius z, turn in degrees]. The
# land is the land ones, less the seas, plus the islands, wobbled.

const LAND := [
	[150, 150, 1500, 1650, 0],       # the heart of the continent
	[100, -1620, 1750, 560, 0],      # the frozen north
	[-1000, -1050, 520, 700, 15],    # Orodruin's shoulder
	[-950, 250, 450, 600, 0],        # the Sylvenwood coast
	[-800, 1180, 560, 620, 0],       # the south-west, round the gulf
	[250, 1780, 1350, 430, 0],       # the badlands along the south coast
	[1300, -450, 560, 1150, 0],      # the east
	[1300, 1350, 700, 520, 20],      # under the Dragon's Teeth
]
const SEAS := [
	[-2050, -300, 780, 1400, 0],     # the Aethel Sea
	[-1380, 1480, 720, 470, -28],    # the Gulf of Krakens
	[2150, 750, 480, 400, 0],        # the Bay of the Wyrm
	[1950, -1950, 380, 300, 0],      # a firth in the north-east
]
const ISLES := [
	[-1940, -360, 300, 630, -8],     # the Whispering Woods
	[2190, -1360, 115, 95, 20],      # the Veiled Archipelago, north to south
	[2250, -1090, 85, 75, 0],
	[2160, -830, 140, 110, -30],
	[2260, -570, 80, 80, 0],
	[2180, -310, 115, 95, 10],
	[2270, -70, 70, 65, 0],
	[2000, 1960, 290, 260, 15],      # the Dragon's Teeth's island
]

# --- The country -----------------------------------------------------------------
# Regions own the ground nearest their centre (through a slow warp, so the
# borders wander) and give it its biome, its lie (`kind`) and its woods: how
# wooded it is (`wood`, 0-1) and the mix of trees (species name -> weight).

enum Kind { MEADOW, FOREST, OLDWOOD, WILDS, TUNDRA, ASHLAND, SHATTERED, DUNES, BADLANDS, BOG, CRAGS, ISLE }

const REGIONS := [
	{"name": "Silverflow Meadows", "centre": Vector2(0, 40), "kind": Kind.MEADOW, "scale": 0.8,
		"biome": Terrain.Biome.WOODLAND, "wood": 0.16,
		"mix": {"Oak": 3.0, "Birch": 3.0, "Pine": 3.0, "Maple": 1.0, "Cherry Blossom": 0.6}},
	{"name": "Sylvenwood", "centre": Vector2(-700, -260), "kind": Kind.FOREST,
		"biome": Terrain.Biome.WOODLAND, "wood": 0.9,
		"mix": {"Oak": 4.0, "Birch": 2.0, "Maple": 2.0, "Pine": 2.0, "Cherry Blossom": 0.8, "Ebony": 0.05}},
	{"name": "Halyon Downs", "centre": Vector2(-1050, 560), "kind": Kind.MEADOW,
		"biome": Terrain.Biome.WOODLAND, "wood": 0.24,
		"mix": {"Oak": 2.0, "Birch": 2.0, "Pine": 1.0, "Willow": 0.5}},
	{"name": "Kraken Heath", "centre": Vector2(-700, 1150), "kind": Kind.FOREST,
		"biome": Terrain.Biome.WOODLAND, "wood": 0.45,
		"mix": {"Pine": 3.0, "Birch": 2.0, "Oak": 1.0, "Dead Snag": 0.4}},
	{"name": "Orodruin Ashlands", "centre": Vector2(-1050, -1000), "kind": Kind.ASHLAND, "scale": 1.6,
		"biome": Terrain.Biome.ASH, "wood": 0.22,
		"mix": {"Charred Snag": 4.0, "Emberbark": 0.8}},
	{"name": "Frostpeak Wilds", "centre": Vector2(-850, -1760), "kind": Kind.WILDS,
		"biome": Terrain.Biome.SNOW, "wood": 0.34,
		"mix": {"Spruce": 5.0, "Frostbark": 1.0, "Pine": 1.0}},
	{"name": "Frostpeak Tundra", "centre": Vector2(700, -1820), "kind": Kind.TUNDRA,
		"biome": Terrain.Biome.SNOW, "wood": 0.07,
		"mix": {"Spruce": 3.0, "Frostbark": 0.5}},
	{"name": "Frostpeak Tundra East", "centre": Vector2(1500, -1760), "kind": Kind.TUNDRA,
		"biome": Terrain.Biome.SNOW, "wood": 0.07,
		"mix": {"Spruce": 3.0, "Frostbark": 0.5}},
	{"name": "Avalanche Foothills", "centre": Vector2(300, -1000), "kind": Kind.OLDWOOD,
		"biome": Terrain.Biome.TAIGA, "wood": 0.55,
		"mix": {"Pine": 4.0, "Spruce": 2.0, "Birch": 1.0, "Redwood": 0.5}},
	{"name": "Whispering Woods (East)", "centre": Vector2(1200, -700), "kind": Kind.OLDWOOD,
		"biome": Terrain.Biome.TAIGA, "wood": 0.88,
		"mix": {"Whisperbark": 3.0, "Pine": 3.0, "Redwood": 2.0, "Birch": 1.0}},
	{"name": "Ostaros Vale", "centre": Vector2(1500, -160), "kind": Kind.MEADOW,
		"biome": Terrain.Biome.WOODLAND, "wood": 0.2,
		"mix": {"Oak": 2.0, "Maple": 2.0, "Birch": 1.0, "Cherry Blossom": 1.0}},
	{"name": "Sylvanwood", "centre": Vector2(1480, 320), "kind": Kind.FOREST,
		"biome": Terrain.Biome.WOODLAND, "wood": 0.85,
		"mix": {"Maple": 3.0, "Oak": 3.0, "Cherry Blossom": 2.0, "Birch": 1.5, "Mahogany": 0.35}},
	{"name": "Mor'uk Bogs", "centre": Vector2(1450, 760), "kind": Kind.BOG,
		"biome": Terrain.Biome.SWAMP, "wood": 0.6,
		"mix": {"Bog Cypress": 3.0, "Willow": 3.0, "Spirit Tree": 0.5, "Dead Snag": 1.0}},
	{"name": "Lesser Mor'uk Bog", "centre": Vector2(1120, 1060), "kind": Kind.BOG, "scale": 1.25,
		"biome": Terrain.Biome.SWAMP, "wood": 0.55,
		"mix": {"Bog Cypress": 3.0, "Willow": 2.0, "Dead Snag": 1.0}},
	{"name": "Shattered Desert", "centre": Vector2(450, 360), "kind": Kind.SHATTERED, "scale": 0.95,
		"biome": Terrain.Biome.DESERT, "wood": 0.03,
		"mix": {"Desert Ironwood": 2.0, "Dead Snag": 1.0, "Baobab": 1.0}},
	{"name": "Al-Khalid Sands", "centre": Vector2(640, 960), "kind": Kind.DUNES,
		"biome": Terrain.Biome.DESERT, "wood": 0.02,
		"mix": {"Palm": 1.0, "Baobab": 1.0}},
	{"name": "Sunscorched Badlands West", "centre": Vector2(-350, 1760), "kind": Kind.BADLANDS,
		"biome": Terrain.Biome.DESERT, "wood": 0.04,
		"mix": {"Dead Snag": 2.0, "Desert Ironwood": 2.0, "Baobab": 1.0}},
	{"name": "Sunscorched Badlands", "centre": Vector2(520, 1820), "kind": Kind.BADLANDS,
		"biome": Terrain.Biome.DESERT, "wood": 0.04,
		"mix": {"Dead Snag": 2.0, "Desert Ironwood": 2.0, "Baobab": 1.0}},
	{"name": "Dragon's Teeth", "centre": Vector2(1300, 1500), "kind": Kind.CRAGS,
		"biome": Terrain.Biome.MOUNTAIN, "wood": 0.22,
		"mix": {"Ironwood": 3.0, "Pine": 1.0, "Dead Snag": 1.0, "Emberbark": 0.3}},
	{"name": "Whispering Woods", "centre": Vector2(-1940, -360), "kind": Kind.OLDWOOD,
		"biome": Terrain.Biome.WOODLAND, "wood": 0.95,
		"mix": {"Whisperbark": 4.0, "Redwood": 2.0, "Pine": 2.0, "Spirit Tree": 0.4, "Ebony": 0.08}},
	{"name": "Veiled Archipelago", "centre": Vector2(2180, -700), "kind": Kind.ISLE, "scale": 0.8,
		"biome": Terrain.Biome.TAIGA, "wood": 0.5,
		"mix": {"Pine": 2.0, "Whisperbark": 1.0, "Spirit Tree": 0.3}},
	{"name": "Dragon's Tooth Isle", "centre": Vector2(2000, 1960), "kind": Kind.CRAGS,
		"biome": Terrain.Biome.MOUNTAIN, "wood": 0.25,
		"mix": {"Ironwood": 2.0, "Pine": 1.0, "Ebony": 0.1}},
]
## How far two regions' ground blends into each other, metres.
const BLEND := 170.0

# --- Mountains, rivers and the rest ----------------------------------------------

## Ranges: a line of peaks, `reach` either side of it, `peak` metres high at
## most. The Avalanche Mountains have passes, so you can get north.
const RANGES := [
	{"name": "Avalanche Mountains", "reach": 270.0, "peak": 205.0, "teeth": false,
		"path": [Vector2(-560, -1250), Vector2(-150, -1180), Vector2(250, -1300), Vector2(650, -1200),
			Vector2(1050, -1150), Vector2(1420, -1300)],
		"passes": [Vector3(430, -1255, 150), Vector3(-360, -1215, 120)]},
	{"name": "Frostpeak", "reach": 210.0, "peak": 150.0, "teeth": false,
		"path": [Vector2(-1480, -1640), Vector2(-1020, -1860), Vector2(-560, -1920)], "passes": []},
	{"name": "Dragon's Teeth", "reach": 240.0, "peak": 180.0, "teeth": true,
		"path": [Vector2(700, 1210), Vector2(1050, 1400), Vector2(1400, 1550), Vector2(1700, 1700),
			Vector2(1960, 1900), Vector2(2150, 2030)], "passes": [Vector3(1250, 1480, 110)]},
]

## Rivers: cut to the sea by the terrain; here their valleys are drawn down so
## they run through low ground rather than canyons.
const RIVERS := [
	{"name": "Silverflow River", "width": 12.0, "depth": 3.4,
		"fords": [{"at": 900.0, "width": 26.0}, {"at": 1500.0, "width": 26.0}, {"at": 2300.0, "width": 24.0}],
		"path": [Vector2(-150, -1080), Vector2(-220, -820), Vector2(-160, -560), Vector2(-60, -330),
			Vector2(-120, -150), Vector2(-330, 30), Vector2(-600, 180), Vector2(-880, 300),
			Vector2(-1150, 360), Vector2(-1380, 400), Vector2(-1620, 420)]},
	{"name": "Ostar River", "width": 14.0, "depth": 3.6,
		"fords": [{"at": 700.0, "width": 26.0}, {"at": 1500.0, "width": 26.0}],
		"path": [Vector2(850, -1050), Vector2(1000, -850), Vector2(1200, -620), Vector2(1400, -380),
			Vector2(1520, -120), Vector2(1600, 150), Vector2(1720, 420), Vector2(1850, 620), Vector2(2080, 730)]},
]
## How wide a river's valley is drawn down, each side of it.
const VALLEY := 160.0

## Mt. Orodruin: a cone with a crater in the top and a lava lake in it.
const VOLCANO := {"name": "Mt. Orodruin", "centre": Vector2(-1080, -980), "radius": 440.0,
	"peak": 250.0, "crater": 70.0, "depth": 55.0}

## The Emperor's Spine: a wall of rock through the desert with a flat top you
## can drive along, ramping down to the ground at each end.
const SPINE := {"name": "Emperor's Spine", "top": 38.0, "half": 15.0, "side": 18.0, "ramp": 300.0,
	"path": [Vector2(180, -120), Vector2(420, 180), Vector2(700, 520), Vector2(950, 850), Vector2(1120, 1100)]}
## The Great Sky Arch: a rock causeway over the Aethel Sea to the Whispering
## Woods, humped up in the middle.
const ARCH := {"name": "Great Sky Arch", "rise": 14.0, "base": 5.0, "half": 10.0, "side": 20.0,
	"path": [Vector2(-1230, -430), Vector2(-1470, -400), Vector2(-1690, -375)]}

## Frozen lakes: [x, z, radius]. Flat ice at the lie of the land round them.
const LAKES := [
	[520, -1830, 120], [880, -1960, 85], [1150, -1700, 150], [760, -1640, 70], [1420, -1880, 100],
	[-760, -1960, 75],
]

## Meteor Crater of Kael: the terrain's crater feature (scorched, starmetal).
const CRATER := {"name": "Meteor Crater of Kael", "kind": "crater", "centre": Vector2(180, 1450),
	"radius": 120.0, "rim": 28.0, "floor": 3.0}

## Home: the ground round the plot is drawn down low and gentle.
const HOME_RADIUS := 260.0

## Named places, for the map, the compass and discovering them: [name, x, z,
## how close counts as having found it].
const PLACES := [
	["Mt. Orodruin", -1080, -980, 170.0],
	["Great Sky Arch", -1470, -400, 70.0],
	["Halyon Port", -1330, 395, 120.0],
	["Silverflow River", -600, 180, 90.0],
	["Sylvenwood", -700, -260, 220.0],
	["Whispering Woods", -1940, -360, 260.0],
	["Frostpeak Wilds", -850, -1760, 300.0],
	["Frostpeak Tundra", 900, -1800, 300.0],
	["Avalanche Mountains", 250, -1290, 220.0],
	["Shattered Desert", 450, 360, 250.0],
	["Al-Khalid Sands", 640, 960, 250.0],
	["Emperor's Spine", 560, 350, 80.0],
	["Meteor Crater of Kael", 180, 1450, 140.0],
	["Sunscorched Badlands", 400, 1850, 300.0],
	["Dragon's Teeth", 1400, 1550, 250.0],
	["Mor'uk Bogs", 1450, 760, 220.0],
	["Lesser Mor'uk Bog", 1120, 1060, 180.0],
	["Ostaros City", 1500, -160, 150.0],
	["Ostar River", 1400, -380, 90.0],
	["Sylvanwood", 1480, 320, 220.0],
	["Whispering Woods (East)", 1200, -700, 250.0],
	["Bay of the Wyrm", 1720, 760, 200.0],
	["Gulf of Krakens", -1050, 1420, 250.0],
	["Aethel Sea", -1290, -120, 160.0],
	["Veiled Archipelago", 2120, -820, 260.0],
]

## Where the places are built, each levelled and facing home: the town by
## home (the hardware store, the vehicle dealer, the machine works), the three
## traders (TradePost: Old Bjorn's lumber yard at the edge of the meadows,
## Dusty's assay office up in the Avalanche foothills, Granny Opal's by the
## sea at Halyon Port), and Summit Outfitters up on the tundra past the pass.
## [x, z, how much ground it needs levelled round it].
const SITES := {
	"lumber": [-230.0, 140.0, 27.0],
	"metal": [300.0, -780.0, 27.0],
	"gems": [-1250.0, 470.0, 27.0],
	"store": [185.0, 52.0, 20.0],
	"dealer": [125.0, 105.0, 17.0],
	"works": [232.0, 100.0, 17.0],
	"summit": [650.0, -1520.0, 18.0],
}

## Which way a place at (x, z) turns its front (local +Z): toward home.
static func facing(x: float, z: float) -> float:
	return atan2(-x, -z)

## The cave networks: one under the continent, a cave biome under each kind of
## country, and a small one under the Whispering Woods. (See CaveNetwork.)
const CAVE_ZONES := [
	{"name": "Ostars", "centre": Vector2(0, 0), "radius": 1500.0, "rooms": 40, "mouths": 11,
		"kinds": [[CaveNetwork.Kind.RIVER, Vector2(-650, -150)], [CaveNetwork.Kind.MAGMA, Vector2(-1000, -950)],
			[CaveNetwork.Kind.ICE, Vector2(300, -1300)], [CaveNetwork.Kind.DESERT, Vector2(500, 600)],
			[CaveNetwork.Kind.FUNGAL, Vector2(1350, 850)], [CaveNetwork.Kind.CRYSTAL, Vector2(1150, 1400)]]},
	{"name": "Whispering Woods", "centre": Vector2(-1940, -360), "radius": 290.0, "rooms": 4, "mouths": 1,
		"kinds": [[CaveNetwork.Kind.FUNGAL, Vector2(-1940, -360)]]},
]

# --- Built once, read from every worker thread ---------------------------------
# The worker threads that sample the land read only these members: noise, and
# packed arrays and plain numbers copied out of the tables above (the tables
# themselves are shared constants, and not safe to walk from several threads).

var _hills := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _teeth := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _knoll := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _coast := FastNoiseLite.new()
var _wet := FastNoiseLite.new()
var _plates := FastNoiseLite.new()
var _cracks := FastNoiseLite.new()

var _reg_centre := PackedVector2Array()
var _reg_scale := PackedFloat32Array()
var _reg_kind := PackedInt32Array()
var _reg_biome := PackedInt32Array()
## Ellipses, 7 numbers each: centre x, z, 1/rx, 1/rz, smaller radius, cos, sin.
var _ell := PackedFloat32Array()
var _n_land := 0
var _n_sea := 0
var _n_isle := 0
## Every line (ranges, then rivers, then the Spine, then the Arch): its points
## and the distance along it at each, from `_from[i]` up to `_to[i]`, and its
## bounds grown by its reach (x0, z0, x1, z1).
var _pts := PackedVector2Array()
var _cum := PackedFloat32Array()
var _from := PackedInt32Array()
var _to := PackedInt32Array()
var _box := PackedFloat32Array()
var _n_ranges := 0
var _river0 := 0
var _n_rivers := 0
var _spine_i := 0
var _arch_i := 0
var _range_reach := PackedFloat32Array()
var _range_peak := PackedFloat32Array()
var _range_teeth := PackedByteArray()
var _passes := PackedVector3Array()
var _pass_of := PackedInt32Array()
var _river_width := PackedFloat32Array()
var _lakes := PackedVector3Array()
var _lake_h := PackedFloat32Array()
var _vx := 0.0
var _vz := 0.0
var _vr := 1.0
var _vpeak := 0.0
var _vcrater := 1.0
var _vdepth := 0.0
var _sp_top := 0.0
var _sp_half := 0.0
var _sp_side := 0.0
var _sp_ramp := 1.0
var _ar_rise := 0.0
var _ar_base := 0.0
var _ar_half := 0.0
var _ar_side := 0.0

func _init(seed_value: int = 20260929) -> void:
	_setup(_hills, seed_value + 71, FastNoiseLite.TYPE_SIMPLEX, 0.0017, 5)
	_setup(_ridge, seed_value + 191, FastNoiseLite.TYPE_SIMPLEX, 0.0024, 5)
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_setup(_teeth, seed_value + 233, FastNoiseLite.TYPE_SIMPLEX, 0.0065, 3)
	_teeth.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_setup(_detail, seed_value + 5501, FastNoiseLite.TYPE_SIMPLEX, 0.021, 2)
	_setup(_knoll, seed_value + 808, FastNoiseLite.TYPE_SIMPLEX, 0.0042, 2)
	_setup(_warp, seed_value + 404, FastNoiseLite.TYPE_SIMPLEX, 0.0009, 2)
	_setup(_coast, seed_value + 313, FastNoiseLite.TYPE_SIMPLEX, 0.0036, 4)
	_setup(_wet, seed_value + 977, FastNoiseLite.TYPE_SIMPLEX, 0.006, 2)
	# The shattered desert: big cells of rock, each lifted its own amount,
	# with cracks down to the sand between them.
	_setup(_plates, seed_value + 1201, FastNoiseLite.TYPE_CELLULAR, 0.0065, 1)
	_plates.fractal_type = FastNoiseLite.FRACTAL_NONE
	_plates.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	_plates.cellular_jitter = 0.9
	_setup(_cracks, seed_value + 1201, FastNoiseLite.TYPE_CELLULAR, 0.0065, 1)
	_cracks.fractal_type = FastNoiseLite.FRACTAL_NONE
	_cracks.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	_cracks.cellular_jitter = 0.9
	for r in REGIONS:
		_reg_centre.append(r.centre)
		_reg_scale.append(float(r.get("scale", 1.0)))
		_reg_kind.append(int(r.kind))
		_reg_biome.append(int(r.biome))
	for e in LAND:
		_add_ellipse(e)
	for e in SEAS:
		_add_ellipse(e)
	for e in ISLES:
		_add_ellipse(e)
	_n_land = LAND.size()
	_n_sea = SEAS.size()
	_n_isle = ISLES.size()
	for i in RANGES.size():
		var r: Dictionary = RANGES[i]
		_add_line(r.path, float(r.reach) + 100.0)
		_range_reach.append(float(r.reach))
		_range_peak.append(float(r.peak))
		_range_teeth.append(1 if r.teeth else 0)
		for pass_spec: Vector3 in r.passes:
			_passes.append(pass_spec)
			_pass_of.append(i)
	_n_ranges = RANGES.size()
	_river0 = _from.size()
	for r in RIVERS:
		_add_line(r.path, VALLEY)
		_river_width.append(float(r.width))
	_n_rivers = RIVERS.size()
	_spine_i = _from.size()
	_sp_top = float(SPINE.top)
	_sp_half = float(SPINE.half)
	_sp_side = float(SPINE.side)
	_sp_ramp = float(SPINE.ramp)
	_add_line(SPINE.path, _sp_half + _sp_side)
	_arch_i = _from.size()
	_ar_rise = float(ARCH.rise)
	_ar_base = float(ARCH.base)
	_ar_half = float(ARCH.half)
	_ar_side = float(ARCH.side)
	_add_line(ARCH.path, _ar_half + _ar_side)
	var vc: Vector2 = VOLCANO.centre
	_vx = vc.x
	_vz = vc.y
	_vr = float(VOLCANO.radius)
	_vpeak = float(VOLCANO.peak)
	_vcrater = float(VOLCANO.crater)
	_vdepth = float(VOLCANO.depth)
	for lake in LAKES:
		_lakes.append(Vector3(float(lake[0]), float(lake[1]), float(lake[2])))
	# Each lake is as high as the land round it, measured before any lake is.
	for lake in _lakes:
		_lake_h.append(_land(lake.x, lake.y)[1])

static func _setup(n: FastNoiseLite, s: int, type: int, freq: float, octaves: int) -> void:
	n.seed = s
	n.noise_type = type
	n.frequency = freq
	n.fractal_octaves = octaves

func _add_ellipse(e: Array) -> void:
	var turn := deg_to_rad(float(e[4]))
	_ell.append_array(PackedFloat32Array([float(e[0]), float(e[1]), 1.0 / float(e[2]), 1.0 / float(e[3]),
		minf(float(e[2]), float(e[3])), cos(turn), sin(turn)]))

func _add_line(path: Array, reach: float) -> void:
	_from.append(_pts.size())
	var run := 0.0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in path.size():
		var pt: Vector2 = path[i]
		if i > 0:
			run += pt.distance_to(path[i - 1])
		_pts.append(pt)
		_cum.append(run)
		lo = Vector2(minf(lo.x, pt.x), minf(lo.y, pt.y))
		hi = Vector2(maxf(hi.x, pt.x), maxf(hi.y, pt.y))
	_to.append(_pts.size())
	_box.append_array(PackedFloat32Array([lo.x - reach, lo.y - reach, hi.x + reach, hi.y + reach]))

func key() -> String:
	return "ostars:%d" % VERSION

## The terrain's configuration for this map: rivers, the crater, and the rest
## of what Terrain carves itself.
func configure(terrain: Terrain) -> void:
	terrain.shaper = self
	for r in RIVERS:
		var path: Array = []
		for p: Vector2 in r.path:
			path.append(Vector3(p.x, 0.0, p.y))
		terrain.rivers.append({"width": float(r.width), "depth": float(r.depth),
			"fords": (r.fords as Array).duplicate(true), "path": path})
	terrain.features = [CRATER.duplicate(true)]

# --- Sampling ---------------------------------------------------------------------

## [biome, height] at a point.
func sample(x: float, z: float) -> Array:
	var p := Vector2(x, z)
	var s := coast(p)
	if s < -160.0:
		# Open sea - bar the Arch, which crosses it.
		var over := _arch_height(p)
		if over > SEA_FLOOR:
			return [Terrain.Biome.MOUNTAIN, over]
		return [Terrain.Biome.WOODLAND, SEA_FLOOR]
	var land := _land(x, z)
	var biome: int = land[0]
	var h: float = land[1]
	# Down to the beach, and under the sea past it.
	var shore := lerpf(1.3, h, smoothstep(0.0, 220.0, s))
	h = lerpf(SEA_FLOOR, shore, smoothstep(-55.0, 18.0, s))
	# The ridges that stand out of the sea or the sand on their own.
	var spine := _spine_height(p)
	if spine > h:
		h = spine
		# Sandstone: sand on its top, red rock down its sides.
		biome = Terrain.Biome.DESERT
	var arch := _arch_height(p)
	if arch > h:
		h = arch
		biome = Terrain.Biome.MOUNTAIN
	# The edge of the map is open sea.
	var to_edge := MAP_HALF - maxf(absf(x), absf(z))
	h = lerpf(SEA_FLOOR, h, smoothstep(4.0, 60.0, to_edge))
	if h < -0.5 and biome == Terrain.Biome.ICE:
		biome = Terrain.Biome.SNOW
	return [biome, h]

## The country before the coast: regions, mountains, the volcano, the river
## valleys and the frozen lakes. [biome, height]
func _land(x: float, z: float) -> Array:
	var p := Vector2(x, z)
	var wx := x + _warp.get_noise_2d(x, z) * 240.0
	var wz := z + _warp.get_noise_2d(x + 7000.0, z - 3000.0) * 240.0
	var w := Vector2(wx, wz)
	var d1 := INF
	var d2 := INF
	var r1 := 0
	var r2 := -1
	for i in _reg_centre.size():
		var d := w.distance_to(_reg_centre[i]) * _reg_scale[i]
		if d < d1:
			d2 = d1
			r2 = r1
			d1 = d
			r1 = i
		elif d < d2:
			d2 = d
			r2 = i
	var biome := _reg_biome[r1]
	var h := _shape(_reg_kind[r1], x, z)
	if r2 >= 0 and d2 - d1 < BLEND and _reg_kind[r2] != _reg_kind[r1]:
		var t := 0.5 + 0.5 * smoothstep(0.0, 1.0, (d2 - d1) / BLEND)
		h = lerpf(_shape(_reg_kind[r2], x, z), h, t)
	# Home: low, gentle ground round the plot.
	var home := 1.0 - smoothstep(HOME_RADIUS * 0.45, HOME_RADIUS, p.length())
	if home > 0.0:
		h = lerpf(h, 2.4 + maxf(0.0, h - 6.0) * 0.1, home)
	# The mountain ranges.
	var mount := 0.0
	var teeth := false
	for i in _n_ranges:
		var m := _range_height(i, p)
		if m > mount:
			mount = m
			teeth = _range_teeth[i] != 0
	h += mount
	if mount > 26.0:
		biome = Terrain.Biome.MOUNTAIN
	# The volcano, stood up out of whatever is round it.
	var cone := _volcano_height(p)
	if cone > 0.0:
		var vd := Vector2(x - _vx, z - _vz).length() / _vr
		h = maxf(h, cone + h * clampf(vd, 0.0, 1.0))
		if vd < 0.97:
			biome = Terrain.Biome.ASH
	# Snow on the high peaks, and on every mountain in the frozen north.
	if biome == Terrain.Biome.MOUNTAIN and not teeth and (h > SNOWLINE or _reg_biome[r1] == Terrain.Biome.SNOW):
		biome = Terrain.Biome.SNOW
	# The river valleys, drawn down to near the water.
	for k in _n_rivers:
		var i := _river0 + k
		if not _in_box(i, p):
			continue
		var near := _near(i, p)
		if near.x >= VALLEY:
			continue
		var width := _river_width[k]
		var pull := 1.0 - smoothstep(width * 1.2, VALLEY, near.x)
		# The head of the valley closes in over its first stretch.
		pull *= smoothstep(-60.0, 160.0, near.y)
		var floor_h := 2.0 + near.x * 0.012
		if h > floor_h:
			h = lerpf(h, floor_h, pull)
			if pull > 0.6 and (biome == Terrain.Biome.MOUNTAIN or biome == Terrain.Biome.SNOW) and h < 40.0:
				biome = _reg_biome[r1] if _reg_biome[r1] != Terrain.Biome.MOUNTAIN else Terrain.Biome.TAIGA
	# The frozen lakes: flat ice at the lie of the land, a low bank round it.
	for i in _lake_h.size():
		var lake := _lakes[i]
		var dist := Vector2(x - lake.x, z - lake.y).length()
		if dist > lake.z * 1.9:
			continue
		# Not quite round: the shore wanders in and out.
		var shore := 1.0 + _coast.get_noise_2d(x * 3.0, z * 3.0) * 0.28
		var ld := dist / (lake.z * shore)
		if ld > 1.5:
			continue
		var lh := _lake_h[i]
		if ld <= 1.0:
			return [Terrain.Biome.ICE, lh]
		var bank := lh + 1.2 * sin((ld - 1.0) / 0.5 * PI)
		h = lerpf(bank, h, smoothstep(1.0, 1.5, ld))
	return [biome, h]

## The lie of each kind of country.
func _shape(kind: int, x: float, z: float) -> float:
	var e := _hills.get_noise_2d(x, z) * 0.5 + 0.5
	var d := _detail.get_noise_2d(x, z)
	match kind:
		Kind.MEADOW:
			return 3.0 + 12.0 * e + 3.0 * _knoll.get_noise_2d(x, z) + 0.6 * d
		Kind.FOREST:
			return 4.0 + 28.0 * e + 9.0 * _knoll.get_noise_2d(x, z) + 1.2 * d
		Kind.OLDWOOD:
			var r := _ridge.get_noise_2d(x, z) * 0.5 + 0.5
			return 6.0 + 34.0 * e + 18.0 * r * r + 1.5 * d
		Kind.WILDS:
			var r2 := _ridge.get_noise_2d(x * 1.3, z * 1.3) * 0.5 + 0.5
			return 16.0 + 44.0 * e + 52.0 * r2 * r2 + 2.0 * d
		Kind.TUNDRA:
			return 7.0 + 9.0 * e + 0.5 * d
		Kind.ASHLAND:
			return 6.0 + 18.0 * e + 1.2 * d
		Kind.SHATTERED:
			# Plates of rock lifted in steps, cracks down to the sand floor.
			var floor_h := 5.0 + 5.0 * e + 0.4 * d
			var lift := snappedf(maxf(0.0, _plates.get_noise_2d(x, z) + 0.2) * 18.0, 4.0) + 3.0
			var crack := _cracks.get_noise_2d(x, z) + 1.0
			var edge := smoothstep(0.07, 0.16, crack)
			return floor_h + lift * edge
		Kind.DUNES:
			var ripple := sin((x * 0.8 + z * 0.45) * 0.022 + d * 2.2)
			return 5.0 + 9.0 * e + 7.0 * ripple * ripple + 0.5 * d
		Kind.BADLANDS:
			# Flat-topped mesas, stepped, and dry gullies between.
			var m := _knoll.get_noise_2d(x * 1.4, z * 1.4) * 0.5 + 0.5
			var mesa := smoothstep(0.52, 0.6, m) * 22.0 + smoothstep(0.66, 0.72, m) * 14.0
			var gully := smoothstep(0.82, 0.95, _ridge.get_noise_2d(x * 0.9, z * 0.9) * 0.5 + 0.5)
			return 6.0 + 12.0 * e + mesa - 5.0 * gully + 0.6 * d
		Kind.BOG:
			var wet := smoothstep(0.45, 0.72, _wet.get_noise_2d(x, z) * 0.5 + 0.5)
			return 1.8 + 5.0 * e - 3.4 * wet + 0.4 * d
		Kind.CRAGS:
			var r3 := _ridge.get_noise_2d(x, z) * 0.5 + 0.5
			return 14.0 + 36.0 * e + 60.0 * r3 * r3 + 2.0 * d
		Kind.ISLE:
			return 3.0 + 26.0 * e + 1.0 * d
	return 4.0 + 20.0 * e

## How high a range stands at `p`: highest along its line, falling away to
## nothing at its reach, ridged, with its passes cut down.
func _range_height(i: int, p: Vector2) -> float:
	if not _in_box(i, p):
		return 0.0
	var reach := _range_reach[i]
	# The line is wobbled so the range is not a ruler-straight wall.
	var wobble := _warp.get_noise_2d(p.x * 3.0, p.y * 3.0) * 80.0
	var near := _near(i, p)
	var t := (near.x + wobble) / reach
	if t >= 1.0:
		return 0.0
	var body := pow(1.0 - clampf(t, 0.0, 1.0), 1.6)
	# The ends taper off.
	var span := _cum[_to[i] - 1]
	body *= smoothstep(0.0, 260.0, near.y) * smoothstep(0.0, 260.0, span - near.y)
	var peaks: float
	if _range_teeth[i] != 0:
		# Dragon's teeth: fangs of rock, sharp and far apart.
		var fang := _teeth.get_noise_2d(p.x, p.y) * 0.5 + 0.5
		peaks = 0.28 + 0.9 * pow(fang, 3.0)
	else:
		var r := _ridge.get_noise_2d(p.x, p.y) * 0.5 + 0.5
		peaks = 0.4 + 0.6 * r
	var h := _range_peak[i] * body * peaks
	for k in _passes.size():
		if _pass_of[k] != i:
			continue
		var pass_spec := _passes[k]
		var pd := Vector2(p.x - pass_spec.x, p.y - pass_spec.y).length() / pass_spec.z
		if pd < 1.6:
			h *= lerpf(0.12, 1.0, smoothstep(0.35, 1.6, pd))
	return h

## The volcano's cone over the ground, 0 away from it.
func _volcano_height(p: Vector2) -> float:
	var dx := p.x - _vx
	var dz := p.y - _vz
	var d := sqrt(dx * dx + dz * dz)
	if d >= _vr:
		return 0.0
	if d <= _vcrater:
		# The crater: steep walls down to a flat floor (the lava lake).
		return lerpf(_vpeak - _vdepth, _vpeak, smoothstep(0.55, 1.0, d / _vcrater))
	var t := (d - _vcrater) / (_vr - _vcrater)
	var h := _vpeak * pow(1.0 - t, 1.35)
	# Gullies running down its flanks.
	var a := atan2(dz, dx)
	var gully := absf(sin(a * 11.0 + _warp.get_noise_2d(p.x * 4.0, p.y * 4.0) * 3.0))
	return h * (1.0 - 0.08 * gully * smoothstep(0.1, 0.5, t))

## The height of the lava lake's surface.
static func lava_level() -> float:
	return float(VOLCANO.peak) - float(VOLCANO.depth) + 1.5

func _spine_height(p: Vector2) -> float:
	if not _in_box(_spine_i, p):
		return -INF
	var near := _near(_spine_i, p)
	if near.x > _sp_half + _sp_side:
		return -INF
	var span := _cum[_to[_spine_i] - 1]
	var top := _sp_top * smoothstep(0.0, _sp_ramp, near.y) * smoothstep(0.0, _sp_ramp, span - near.y)
	return top - (top + 4.0) * smoothstep(_sp_half, _sp_half + _sp_side, near.x)

func _arch_height(p: Vector2) -> float:
	if not _in_box(_arch_i, p):
		return -INF
	var near := _near(_arch_i, p)
	if near.x > _ar_half + _ar_side:
		return -INF
	var t := near.y / _cum[_to[_arch_i] - 1]
	var top := _ar_base + _ar_rise * smoothstep(0.0, 0.36, t) * smoothstep(1.0, 0.64, t)
	return lerpf(top, SEA_FLOOR, smoothstep(_ar_half, _ar_half + _ar_side, near.x))

# --- The coast ----------------------------------------------------------------

## Metres inland (negative: out to sea) of the coast, roughly.
func coast(p: Vector2) -> float:
	var q := p + Vector2(_warp.get_noise_2d(p.x + 1300.0, p.y), _warp.get_noise_2d(p.x, p.y + 900.0)) * 150.0
	var s := -INF
	var e := 0
	for i in _n_land:
		s = maxf(s, _ellipse(q, e))
		e += 7
	for i in _n_sea:
		s = minf(s, -_ellipse(q, e))
		e += 7
	for i in _n_isle:
		s = maxf(s, _ellipse(q, e))
		e += 7
	return s + _coast.get_noise_2d(p.x, p.y) * 60.0

func _ellipse(p: Vector2, e: int) -> float:
	var dx := p.x - _ell[e]
	var dz := p.y - _ell[e + 1]
	var c := _ell[e + 5]
	var sn := _ell[e + 6]
	var qx := (dx * c + dz * sn) * _ell[e + 2]
	var qz := (-dx * sn + dz * c) * _ell[e + 3]
	return (1.0 - sqrt(qx * qx + qz * qz)) * _ell[e + 4]

# --- Lines ----------------------------------------------------------------------

func _in_box(i: int, p: Vector2) -> bool:
	var b := i * 4
	return p.x >= _box[b] and p.y >= _box[b + 1] and p.x <= _box[b + 2] and p.y <= _box[b + 3]

## (distance to line `i`, distance along it to the nearest point).
func _near(i: int, p: Vector2) -> Vector2:
	var best := INF
	var along := 0.0
	for k in range(_from[i], _to[i] - 1):
		var a := _pts[k]
		var ab := _pts[k + 1] - a
		var l2 := ab.length_squared()
		var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
		var d := p.distance_squared_to(a + ab * t)
		if d < best:
			best = d
			along = _cum[k] + (_cum[k + 1] - _cum[k]) * t
	return Vector2(sqrt(best), along)

# --- For the rest of the world ----------------------------------------------------

## The region whose ground a point is on (by the same warped nearest-centre
## rule as the land), as its dictionary.
func region_at(x: float, z: float) -> Dictionary:
	var wx := x + _warp.get_noise_2d(x, z) * 240.0
	var wz := z + _warp.get_noise_2d(x + 7000.0, z - 3000.0) * 240.0
	var w := Vector2(wx, wz)
	var best := 0
	var best_d := INF
	for i in _reg_centre.size():
		var d := w.distance_to(_reg_centre[i]) * _reg_scale[i]
		if d < best_d:
			best_d = d
			best = i
	return REGIONS[best]

## How far a point is from the nearest river's centre line, metres.
func river_distance(x: float, z: float) -> float:
	var best := INF
	for k in _n_rivers:
		best = minf(best, _near(_river0 + k, Vector2(x, z)).x)
	return best

## Whether a point is on one of the frozen lakes (give or take its wandering
## shore: `pad` metres more).
func on_lake(x: float, z: float, pad: float = 0.0) -> bool:
	for lake in _lakes:
		if Vector2(x - lake.x, z - lake.y).length() < lake.z * 1.3 + pad:
			return true
	return false

## Whether a point is up on the Spine or the Arch (nothing grows there).
func on_ridge(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	if _in_box(_spine_i, p) and _near(_spine_i, p).x < _sp_half + _sp_side:
		return true
	if _in_box(_arch_i, p) and _near(_arch_i, p).x < _ar_half + _ar_side:
		return true
	return false
