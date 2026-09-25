class_name World
extends Node3D

## The game scene: terrain, forest, quarry, the player's plot, the sell depot,
## the player and the HUD, plus save/load and vehicle handling.

## 4.8 km across: a big home island and five more round it, joined by bridges
## and a causeway - bar one, which only a tunnel under the sea reaches.
const MAP_HALF := 2400.0
const DEPOT_POSITION := Vector3(0, 0, 70)
const STORE_POSITION := Vector3(-52, 0, 62)
const QUARRY_CENTRE := Vector3(-150, 0, -40)
## Where the demo lines stand when they are switched on (Settings > Debug).
const SHOWCASE_POSITION := Vector3(28, 0, 188)
const SHOWCASE_GROUND := 2.0
## The cave networks: one per island (the home island's is huge), each with
## its cave biomes placed under the country that matches them, and how many
## surface mouths it gets. Home and Hollow Isle are joined by the deep tunnel.
const CAVE_ZONES := [
	{"name": "Home", "centre": Vector2(0, 0), "radius": 1150.0, "rooms": 44, "mouths": 9,
		"kinds": [[CaveNetwork.Kind.RIVER, Vector2(80, 260)], [CaveNetwork.Kind.RIVER, Vector2(-980, -120)],
			[CaveNetwork.Kind.CRYSTAL, Vector2(660, -540)], [CaveNetwork.Kind.DESERT, Vector2(-640, 680)],
			[CaveNetwork.Kind.ICE, Vector2(-320, -820)], [CaveNetwork.Kind.MAGMA, Vector2(900, 500)]]},
	{"name": "Frostreach", "centre": Vector2(0, -1850), "radius": 380.0, "rooms": 10, "mouths": 2,
		"kinds": [[CaveNetwork.Kind.ICE, Vector2(0, -1850)]]},
	{"name": "Sunscar", "centre": Vector2(1850, 120), "radius": 370.0, "rooms": 10, "mouths": 2,
		"kinds": [[CaveNetwork.Kind.MAGMA, Vector2(1850, 120)]]},
	{"name": "Mirewood", "centre": Vector2(-1850, 220), "radius": 380.0, "rooms": 10, "mouths": 2,
		"kinds": [[CaveNetwork.Kind.FUNGAL, Vector2(-1850, 220)]]},
	{"name": "Hollow Isle", "centre": Vector2(-1450, 1450), "radius": 240.0, "rooms": 5, "mouths": 1,
		"kinds": [[CaveNetwork.Kind.CRYSTAL, Vector2(-1450, 1450)]]},
]
const CAVE_LINKS := [[0, 4]]
## The plot pad stands clear of two things: the water line, so the yard is never
## flooded, and the ground itself, so the pad and the land are not two surfaces
## fighting over one plane. The slab's top is PLOT_GROUND + 0.05.
const PLOT_GROUND := 0.45
const PAD_HEIGHT := 0.5
const AUTOSAVE_SECONDS := 60.0
## Sky light outdoors. Kept low enough that a grey rock still reads as grey in
## full sun rather than bleaching to white.
const OUTDOOR_AMBIENT := 0.6
const STARTING_MONEY := 250

@export var tree_count: int = 1800
@export var rock_count: int = 80
@export var autosave: bool = true

var manager: LooseItemManager
var plot: Plot
var player: Player
var hud: GameHUD
var build_system: BuildSystem
var depot: SellYard
var quests: QuestLog
var store: Store
var terrain: Terrain
var hauler: Hauler
## The high-country shop: the best tools, heavy trucks, top machine tiers.
var summit_store: Store
const SUMMIT_STORE := "Summit Outfitters"
## One field per species, each keeping its own ring or patch stocked.
var tree_fields: Array[ResourceField] = []
var rock_fields: Array[ResourceField] = []
var caves: Array[Cave] = []
var outposts: Array[Outpost] = []
var bridges: Array[Bridge] = []
var network: CaveNetwork
var landmarks: Landmarks
var showcase: Showcase

## The islands: a big home island in the middle; the cold north, the desert
## east and the wet west; a scorched isle in the south-east where something
## fell out of the sky; and Hollow Isle in the south-west, which no road or
## bridge reaches - only the deep tunnel under the sea.
const ISLANDS := [
	{"name": "Home Island", "centre": Vector2(0, 0), "radius": 1220.0},
	{"name": "Frostreach", "centre": Vector2(0, -1850), "radius": 403.0},
	{"name": "Sunscar", "centre": Vector2(1850, 120), "radius": 396.0},
	{"name": "Mirewood", "centre": Vector2(-1850, 220), "radius": 403.0},
	{"name": "Crater Isle", "centre": Vector2(1150, 1150), "radius": 247.0},
	{"name": "Hollow Isle", "centre": Vector2(-1450, 1450), "radius": 262.0},
]
## One big region per kind of country: the home island's woods round the plot,
## a mountain range to the north-east, a desert to the south-west, a swamp
## along the west coast and taiga to the north-west; then an island each.
const REGIONS := [
	{"name": "The Greenwood", "centre": Vector2(80, 260), "biome": Terrain.Biome.WOODLAND, "scale": 0.85},
	{"name": "Spine Mountains", "centre": Vector2(660, -540), "biome": Terrain.Biome.MOUNTAIN},
	{"name": "Redsand Desert", "centre": Vector2(-640, 680), "biome": Terrain.Biome.DESERT},
	{"name": "Mudflat Swamp", "centre": Vector2(-980, -120), "biome": Terrain.Biome.SWAMP},
	{"name": "Northpine Taiga", "centre": Vector2(-320, -820), "biome": Terrain.Biome.TAIGA},
	{"name": "Frostreach", "centre": Vector2(0, -1850), "biome": Terrain.Biome.SNOW},
	{"name": "Sunscar Mesas", "centre": Vector2(1850, 120), "biome": Terrain.Biome.DESERT},
	{"name": "Sunscar Crags", "centre": Vector2(1960, -60), "biome": Terrain.Biome.MOUNTAIN, "scale": 1.6},
	{"name": "Mirewood", "centre": Vector2(-1900, 320), "biome": Terrain.Biome.SWAMP},
	{"name": "Mirewood Hills", "centre": Vector2(-1760, 60), "biome": Terrain.Biome.WOODLAND, "scale": 1.3},
	{"name": "Crater Isle", "centre": Vector2(1150, 1150), "biome": Terrain.Biome.WOODLAND},
	{"name": "Hollow Isle", "centre": Vector2(-1450, 1450), "biome": Terrain.Biome.TAIGA},
]
## Places that are there to be found: no road goes to them.
const HIDDEN_VALLEY := "Hidden Valley"
const STAR_CRATER := "Star Crater"
var decor: Decor
var _discover_timer: float = 0.0

## Where the land is under a loose item, for the manager's fall-through
## check. Nothing is claimed inside a cave, where everything is below the land.
func _ground_for_items(p: Vector3) -> float:
	if network != null and network.contains(p, 2.0):
		return -INF
	if absf(p.x) > MAP_HALF or absf(p.z) > MAP_HALF:
		return -INF
	return terrain.height_at(p.x, p.z)

## Places out on the map, found for their country by the terrain rather than
## put at fixed spots, so each sits on a level patch of the right ground.
const OUTPOSTS := [
	{"name": "Dune Trading Post", "kind": Outpost.Kind.TRADING_POST, "radius": 15.0,
		"biomes": [Terrain.Biome.DESERT], "near": 1500.0, "far": 2300.0,
		"premium": {&"lumber": 1.45, &"goods": 1.3, &"jewel": 1.25}},
	{"name": "Frostline Post", "kind": Outpost.Kind.TRADING_POST, "radius": 15.0,
		"biomes": [Terrain.Biome.SNOW], "near": 1450.0, "far": 2300.0,
		"premium": {&"ore": 1.35, &"metal": 1.45}},
	{"name": "Mire Gem Exchange", "kind": Outpost.Kind.TRADING_POST, "radius": 15.0,
		"biomes": [Terrain.Biome.SWAMP, Terrain.Biome.WOODLAND], "near": 1450.0, "far": 2300.0,
		"toward": Vector2(-1, 0), "premium": {&"gem": 1.3, &"jewel": 1.5}},
	{"name": "Eagle's Rest", "kind": Outpost.Kind.LOOKOUT, "radius": 9.0,
		"biomes": [Terrain.Biome.MOUNTAIN, Terrain.Biome.SNOW], "near": 450.0, "far": 1100.0,
		"toward": Vector2(0.7, -0.7), "high": true},
	{"name": "Ranger Lookout", "kind": Outpost.Kind.LOOKOUT, "radius": 9.0,
		"biomes": [Terrain.Biome.WOODLAND, Terrain.Biome.TAIGA], "near": 300.0, "far": 1000.0},
	{"name": "Old Logging Camp", "kind": Outpost.Kind.CAMP, "radius": 11.0,
		"biomes": [Terrain.Biome.TAIGA], "near": 400.0, "far": 1150.0},
	{"name": "Stilt Shack", "kind": Outpost.Kind.SHACK, "radius": 10.0,
		"biomes": [Terrain.Biome.SWAMP], "near": 500.0, "far": 1200.0},
	{"name": "Sunken Ruins", "kind": Outpost.Kind.RUINS, "radius": 11.0,
		"biomes": [Terrain.Biome.DESERT], "near": 400.0, "far": 1200.0},
	{"name": "Far Camp", "kind": Outpost.Kind.CAMP, "radius": 11.0,
		"biomes": [Terrain.Biome.SNOW], "near": 1500.0, "far": 2300.0},
]
## 0 in daylight, 1 deep in a cave: eased, so going underground is a descent.
var underground: float = 0.0
var _headlamp: OmniLight3D
var _plates_shown: bool = true

var tutorial: Tutorial
var main_menu: MainMenu
var pause_menu: PauseMenu
## Off for the headless runs that instance the world as a child and drive it.
@export var show_menu: bool = true
## True once the player has left the title screen, so quitting from it does not
## write a save for a game nobody played.
var playing: bool = false

var sun: DirectionalLight3D
var environment: Environment
var _rng := RandomNumberGenerator.new()
var _autosave_timer: float = AUTOSAVE_SECONDS
var _fader: ColorRect

var _lap_ms: int = 0

## Load timing, printed when PROFILE_LOAD is set.
func _lap(what: String) -> void:
	var now := Time.get_ticks_msec()
	if OS.has_environment("PROFILE_LOAD"):
		print("load: %-16s %5d ms" % [what, now - _lap_ms])
	_lap_ms = now

func _ready() -> void:
	_lap_ms = Time.get_ticks_msec()
	_rng.seed = 20260921
	InputSetup.ensure()
	_build_environment()
	_build_terrain()
	_lap("terrain")
	decor = Decor.new()
	decor.name = "Decor"
	decor.setup(terrain, 7331)
	add_child(decor)

	manager = LooseItemManager.new()
	manager.name = "LooseItems"
	add_child(manager)
	manager.register_plot(0, Vector3(0, 6, 0))
	manager.ground_height = _ground_for_items

	plot = Plot.new()
	plot.name = "Plot"
	plot.position.y = PAD_HEIGHT
	plot.setup(manager, 0)
	plot.vehicle_host = self
	plot.terrain = terrain
	plot.vehicle_spawned.connect(_on_vehicle_spawned)
	add_child(plot)

	quests = QuestLog.new()
	quests.name = "Quests"
	quests.setup(GameData.quest_pool(), GameData.quest_slots())
	add_child(quests)

	_lap("terrain+decor")
	_build_forest()
	_lap("forest")
	_build_quarry()
	_build_crater()
	_lap("rocks")
	_build_caves()
	_lap("cave fields")
	_build_outposts()
	_build_depot()
	_build_store()
	_lap("places")

	player = _make_player()
	add_child(player)
	# Fields keep their churn and spawning away from wherever the player is.
	for field in tree_fields + rock_fields:
		field.focus = player
	decor.focus = player
	player.manager = manager
	player.plot = plot
	player.store = store
	player.stores = [store]
	if summit_store != null:
		player.stores.append(summit_store)
	player.wants_to_drive.connect(func(v: Node3D): drive(v as Hauler))

	build_system = BuildSystem.new()
	build_system.setup(plot, player.camera, player)
	add_child(build_system)
	player.build_system = build_system

	hud = GameHUD.new()
	hud.setup(player, plot, manager, self)
	add_child(hud)

	var loaded := false
	if SaveSystem.has_save():
		loaded = SaveSystem.load_game(plot, player, SaveSystem.SAVE_PATH, manager,
			_spawn_vehicle_for_load, quests)
	if not loaded:
		# A starting float, so the first sawmill is a few tree-loads away
		# rather than an hour of hauling.
		Economy.add_money(STARTING_MONEY)

	# The checklist catches up with the save before anyone is listening, so a
	# loaded game does not open with a volley of "done" messages.
	tutorial = Tutorial.new()
	tutorial.name = "Tutorial"
	tutorial.setup(player, plot, store, build_system, quests, tree_fields)
	add_child(tutorial)
	tutorial.evaluate()
	hud.bind_tutorial(tutorial)
	hud.toast("Welcome back - day %d" % Economy.day if loaded else
		"You have %s. Fell a tree to get started." % UIKit.money(Economy.money), UITheme.ACCENT)

	Settings.changed.connect(_on_setting_changed)
	_apply_all_settings()
	_build_menus()
	set_physics_process(true)

# --- World construction ----------------------------------------------------

func _build_environment() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_blend_splits = true
	add_child(sun)

	var env_node := WorldEnvironment.new()
	environment = Environment.new()
	var env := environment
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color(0.24, 0.45, 0.78)
	sky.sky_horizon_color = Color(0.70, 0.80, 0.88)
	sky.sky_curve = 0.12
	# Below the horizon the sky is the haze, so past the far plane there is
	# only haze.
	sky.ground_bottom_color = Color(0.68, 0.78, 0.87)
	sky.ground_horizon_color = Color(0.68, 0.78, 0.87)
	sky.sun_angle_max = 24.0
	sky.sun_curve = 0.08
	env.sky.sky_material = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = OUTDOOR_AMBIENT
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Filmic response, so bright ground and snow roll off rather than clip.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	# Haze the colour of the horizon, so distance reads as air rather than grey.
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.78, 0.87)
	env.fog_sun_scatter = 0.18
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_curve = 1.6
	env.fog_density = 1.0
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.0
	env_node.environment = env
	add_child(env_node)

## Spec: a large, simple, polygonal map with several biomes, rivers to ford or
## bridge, and roads that are quicker to drive. The build sites are levelled out
## of it first, so a factory floor is never on a slope.
func _build_terrain() -> void:
	terrain = Terrain.new()
	terrain.name = "Terrain"
	terrain.half_extent = MAP_HALF
	terrain.noise_seed = 20260921

	# Two rivers through the home valley and down to the sea, each with a
	# couple of places shallow enough to drive through.
	terrain.rivers = [
		{"width": 11.0, "depth": 3.4, "fords": [{"at": 300.0, "width": 26.0}, {"at": 700.0, "width": 24.0}],
			"path": [Vector3(-360, 0, -350), Vector3(-240, 0, -220), Vector3(-150, 0, -130),
				Vector3(-115, 0, -30), Vector3(-135, 0, 85), Vector3(-85, 0, 210), Vector3(15, 0, 400),
				Vector3(100, 0, 700), Vector3(200, 0, 1000), Vector3(300, 0, 1300)]},
		{"width": 9.0, "depth": 2.8, "fords": [{"at": 380.0, "width": 24.0}],
			"path": [Vector3(390, 0, -250), Vector3(240, 0, -170), Vector3(110, 0, -135),
				Vector3(-55, 0, -155), Vector3(-250, 0, -240), Vector3(-600, 0, -350),
				Vector3(-1000, 0, -420), Vector3(-1350, 0, -450)]},
	]
	# Roads. The two short ones round home are laid; the rest are given as
	# waypoints and routed over the land, so they wind round hills, switch
	# back up the mountains, and take water where the crossing is short.
	terrain.roads = [
		[Vector3(0, 0, 0), Vector3(0, 0, 30), DEPOT_POSITION,
			Vector3(-20, 0, 66), STORE_POSITION],
		[Vector3(0, 0, 0), Vector3(-40, 0, -14), Vector3(-90, 0, -28), QUARRY_CENTRE],
		{"bridge": true, "route": [Vector3(40, 0, -20), Vector3(260, 0, 40), Vector3(1000, 0, 180),
			Vector3(1850, 0, 120)]},
		{"bridge": true, "route": [Vector3(-40, 0, -14), Vector3(-120, 0, -500), Vector3(-60, 0, -1150),
			Vector3(0, 0, -1850)]},
		{"bridge": true, "route": [QUARRY_CENTRE, Vector3(-500, 0, 60), Vector3(-1150, 0, 160),
			Vector3(-1850, 0, 220)]},
		{"ford": true, "style": "gravel", "route": [Vector3(30, 0, 80), Vector3(500, 0, 520),
			Vector3(1150, 0, 1150)]},
		# Into the desert, and up into the Spine Mountains.
		{"bridge": true, "route": [Vector3(-20, 0, 66), Vector3(-640, 0, 680)]},
		{"bridge": true, "route": [Vector3(260, 0, 40), Vector3(560, 0, -380)]},
	]
	for isle in ISLANDS:
		terrain.islands.append(isle)
	for region in REGIONS:
		terrain.regions.append(region)
	# The hidden places: a green valley walled in by a ridge with one gorge
	# into it, on Hollow Isle; and the crater where the starmetal came down.
	# And the low, sheltered valley round home that the plot sits in.
	terrain.features = [
		{"name": "Home Valley", "kind": "basin", "centre": Vector2(-20, 60), "radius": 330.0},
		{"name": HIDDEN_VALLEY, "kind": "valley", "centre": Vector2(-1470, 1480), "radius": 45.0,
			"gap": PI * 0.5, "floor": 16.0},
		{"name": STAR_CRATER, "kind": "crater", "centre": Vector2(1160, 1170), "radius": 48.0,
			"rim": 30.0, "floor": 8.0},
	]
	# Everything that has to stand on the level, and all of it above the water
	# line so a levelled site is never under the sheet.
	terrain.reserve_site(Vector3(0, PLOT_GROUND, 0), 56.0)
	terrain.reserve_site(Vector3(DEPOT_POSITION.x, 0.6, DEPOT_POSITION.z), 16.0)
	terrain.reserve_site(Vector3(STORE_POSITION.x, 0.6, STORE_POSITION.z), 20.0)
	terrain.reserve_site(Vector3(QUARRY_CENTRE.x, 0.5, QUARRY_CENTRE.z), 34.0)
	# Kept clear for the demo lines, whether or not they are switched on.
	terrain.reserve_site(Vector3(SHOWCASE_POSITION.x, SHOWCASE_GROUND, SHOWCASE_POSITION.z - 4.0), 30.0)
	# Cave mouths: most on the home island, a couple on each of the others,
	# and one on Hollow Isle for the far end of the deep tunnel.
	terrain.cave_count = 16
	for zone in CAVE_ZONES:
		terrain.cave_zones.append({"centre": zone.centre, "radius": zone.radius * 0.92,
			"count": zone.mouths})
	for spec in OUTPOSTS:
		var request := {"name": spec.name, "biomes": spec.biomes,
			"radius": spec.radius, "near": spec.near, "far": spec.far}
		if spec.has("toward"):
			request["toward"] = spec.toward
		if spec.get("high", false):
			request["high"] = true
		terrain.site_requests.append(request)
		# The traders, the far camp and the mountain lookout are on the road;
		# the rest are found.
		if spec.kind == Outpost.Kind.TRADING_POST or spec.name == "Far Camp" or spec.name == "Eagle's Rest":
			terrain.spur_sites.append(spec.name)
	# The better shop is a trip: up in the snowfields of Frostreach.
	terrain.site_requests.append({"name": SUMMIT_STORE, "biomes": [Terrain.Biome.SNOW],
		"radius": 18.0, "near": 1500.0, "far": 2300.0})
	terrain.spur_sites.append(SUMMIT_STORE)
	terrain.cache_path = "user://terrain_cache.bin"
	add_child(terrain)

	# A wall at the map edge, so nothing drives off the world.
	var bounds := StaticBody3D.new()
	bounds.name = "MapEdge"
	bounds.collision_layer = Layers.WORLD
	bounds.collision_mask = 0
	for spec in [
		[Vector3(0, 20.0, -MAP_HALF), Vector3(MAP_HALF * 2.0, 80.0, 2.0)],
		[Vector3(0, 20.0, MAP_HALF), Vector3(MAP_HALF * 2.0, 80.0, 2.0)],
		[Vector3(-MAP_HALF, 20.0, 0), Vector3(2.0, 80.0, MAP_HALF * 2.0)],
		[Vector3(MAP_HALF, 20.0, 0), Vector3(2.0, 80.0, MAP_HALF * 2.0)],
	]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[1]
		cs.shape = box
		cs.position = spec[0]
		bounds.add_child(cs)
	add_child(bounds)
	_build_bridges()
	landmarks = Landmarks.new()
	landmarks.name = "Landmarks"
	landmarks.setup(terrain, 911)
	add_child(landmarks)
	var roads := RoadSurface.new()
	roads.name = "RoadSurface"
	roads.setup(terrain)
	add_child(roads)

func _build_bridges() -> void:
	for plan in terrain.bridges:
		var ends := terrain.bridge_ends(plan)
		var bridge := Bridge.new()
		bridge.name = "Bridge%d" % bridges.size()
		bridge.setup(ends[0], ends[1], terrain)
		add_child(bridge)
		bridges.append(bridge)

## The forest is not a fixed list of trees: each species has a field that keeps
## its own ring stocked up to a quota and stops there. Fell one and the field
## grows another somewhere else in the ring, but never more than the quota, so
## a cleared forest comes back and a full one stays put.
## Spec: several biomes, and now a forest that belongs to them. A species grows
## where its country is rather than in a ring drawn round the origin, so the
## look of the land tells you what you will be cutting - and the hard woods are
## out in the hard country, which is what makes the trip worth making.
##
## Tree and wood are separate things. A swamp willow and a woodland oak are
## different trees that both cut into oak, so the map can be varied without the
## economy growing a new material for every silhouette.
func _build_forest() -> void:
	var species := [
		{"name": "Pine", "item": &"wood_pine",
			"biomes": [Terrain.Biome.WOODLAND, Terrain.Biome.TAIGA],
			"leaf": Color(0.15, 0.38, 0.22), "work": 620.0,
			"radius": [0.26, 0.36], "height": [7.5, 10.5], "taper": 0.50, "branches": [5, 7],
			# A spire: branches from low down, swept up, short.
			"start": 0.34, "pitch": [0.30, 0.62], "length": [0.11, 0.19],
			"foliage": 5.0, "crown": [4.0, 0.60]},

		{"name": "Spruce", "item": &"wood_spruce",
			"biomes": [Terrain.Biome.SNOW],
			"leaf": Color(0.52, 0.60, 0.58), "work": 700.0,
			"radius": [0.24, 0.32], "height": [6.0, 8.5], "taper": 0.44, "branches": [6, 8],
			# Narrower again, and pale with the snow on it.
			"start": 0.26, "pitch": [0.22, 0.48], "length": [0.09, 0.15],
			"foliage": 4.2, "crown": [3.4, 0.66]},

		{"name": "Oak", "item": &"wood_oak",
			"biomes": [Terrain.Biome.WOODLAND],
			"leaf": Color(0.24, 0.45, 0.16), "work": 1000.0,
			"radius": [0.40, 0.54], "height": [5.0, 7.0], "taper": 0.74, "branches": [6, 8],
			# Open trunk, then a broad crown thrown wide.
			"start": 0.58, "pitch": [0.80, 1.20], "length": [0.28, 0.44],
			"foliage": 9.5, "crown": [8.5, 0.30]},

		{"name": "Willow", "item": &"wood_willow",
			"biomes": [Terrain.Biome.SWAMP],
			"leaf": Color(0.38, 0.47, 0.22), "work": 880.0,
			"radius": [0.34, 0.46], "height": [4.5, 6.5], "taper": 0.70, "branches": [7, 9],
			# Drooping: branches thrown almost flat and long with it.
			"start": 0.52, "pitch": [1.05, 1.45], "length": [0.34, 0.52],
			"foliage": 8.0, "crown": [6.0, 0.26],
			# Standing in the water, which is where a willow belongs.
			"wet": 0.7},

		{"name": "Ironwood", "near": 700.0, "item": &"wood_ironwood",
			"biomes": [Terrain.Biome.MOUNTAIN],
			"leaf": Color(0.18, 0.30, 0.20), "work": 1900.0,
			"radius": [0.46, 0.60], "height": [5.0, 7.0], "taper": 0.82, "branches": [4, 6],
			# Squat and thick, holding on to a mountainside.
			"start": 0.48, "pitch": [0.70, 1.10], "length": [0.20, 0.32],
			"foliage": 6.0, "crown": [4.6, 0.28]},

		{"name": "Desert Ironwood", "near": 700.0, "item": &"wood_ironwood",
			"biomes": [Terrain.Biome.DESERT],
			"leaf": Color(0.42, 0.46, 0.28), "work": 1750.0,
			"radius": [0.38, 0.50], "height": [3.8, 5.4], "taper": 0.80, "branches": [5, 7],
			# Low, wide and sparse, the way things grow with no water.
			"start": 0.40, "pitch": [0.95, 1.35], "length": [0.26, 0.40],
			"foliage": 5.0, "crown": [0.0, 0.0]},

		# --- The rest of the forest: every one a tree you would know on sight.

		{"name": "Birch", "item": &"wood_birch",
			"biomes": [Terrain.Biome.WOODLAND, Terrain.Biome.TAIGA],
			"leaf": Color(0.55, 0.68, 0.25), "bark": Color(0.90, 0.89, 0.84), "work": 520.0,
			"radius": [0.18, 0.26], "height": [7.0, 10.0], "taper": 0.6, "branches": [5, 7],
			# Slim white trunk, a light rounded head of small leaves.
			"start": 0.55, "pitch": [0.35, 0.75], "length": [0.14, 0.22],
			"foliage": 7.0, "crown": [7.0, 0.28], "style": &"ball"},

		{"name": "Maple", "near": 360.0, "item": &"wood_maple",
			"biomes": [Terrain.Biome.WOODLAND],
			"leaf": Color(0.86, 0.32, 0.14), "accent": Color(0.96, 0.62, 0.16), "work": 900.0,
			"radius": [0.34, 0.46], "height": [5.5, 7.5], "taper": 0.7, "branches": [6, 8],
			# Autumn all year round: a big round crown in reds and oranges.
			"start": 0.5, "pitch": [0.6, 1.05], "length": [0.22, 0.34],
			"foliage": 8.5, "crown": [9.0, 0.34], "style": &"ball", "weight": 0.7},

		{"name": "Cherry Blossom", "near": 440.0, "item": &"wood_cherry",
			"biomes": [Terrain.Biome.WOODLAND, Terrain.Biome.SWAMP],
			"leaf": Color(0.98, 0.70, 0.82), "accent": Color(1.0, 0.86, 0.92), "work": 820.0,
			"bark": Color(0.36, 0.20, 0.18),
			"radius": [0.26, 0.36], "height": [4.0, 5.5], "taper": 0.68, "branches": [6, 8],
			# Low and wide, and a cloud of pink.
			"start": 0.45, "pitch": [0.9, 1.3], "length": [0.3, 0.44],
			"foliage": 9.0, "crown": [7.5, 0.3], "style": &"puff", "weight": 0.45},

		{"name": "Redwood", "min": 14, "near": 500.0, "item": &"wood_redwood",
			"biomes": [Terrain.Biome.TAIGA],
			"leaf": Color(0.13, 0.30, 0.18), "work": 760.0,
			"radius": [0.70, 0.95], "height": [14.0, 19.0], "taper": 0.45, "branches": [6, 8],
			# A giant: a great bare red column, then a narrow spire way up top.
			# You will want the log truck.
			"start": 0.62, "pitch": [0.35, 0.6], "length": [0.07, 0.11],
			"foliage": 5.0, "crown": [3.2, 0.3], "weight": 0.35},

		{"name": "Palm", "item": &"wood_palm",
			"biomes": [Terrain.Biome.DESERT],
			"leaf": Color(0.34, 0.60, 0.22), "work": 420.0,
			"radius": [0.18, 0.24], "height": [6.0, 8.5], "taper": 0.8, "branches": [0, 0],
			"start": 0.9, "pitch": [0.0, 0.1], "length": [0.1, 0.1],
			"foliage": 1.0, "crown": [14.0, 0.2], "style": &"palm", "wet": 0.2},

		{"name": "Baobab", "near": 600.0, "item": &"wood_baobab",
			"biomes": [Terrain.Biome.DESERT],
			"leaf": Color(0.40, 0.52, 0.22), "work": 700.0,
			"radius": [0.9, 1.2], "height": [4.5, 6.0], "taper": 0.62, "branches": [5, 7],
			# A barrel of a trunk with a little tuft of branches on top.
			"start": 0.86, "pitch": [0.9, 1.3], "length": [0.16, 0.24],
			"foliage": 3.5, "crown": [2.2, 0.16], "style": &"ball", "weight": 0.4},

		{"name": "Frostbark", "min": 14, "near": 1300.0, "item": &"wood_frost",
			"biomes": [Terrain.Biome.SNOW],
			"leaf": Color(0.62, 0.86, 1.0), "work": 1300.0, "glow": 0.35,
			"radius": [0.28, 0.38], "height": [6.0, 8.0], "taper": 0.55, "branches": [6, 8],
			# Ice-blue needles that catch the light, on a pale blue trunk.
			"start": 0.3, "pitch": [0.35, 0.6], "length": [0.1, 0.16],
			"foliage": 5.0, "crown": [3.6, 0.5], "weight": 0.35},

		{"name": "Spirit Tree", "min": 10, "near": 1300.0, "item": &"wood_spirit",
			"biomes": [Terrain.Biome.SWAMP],
			"leaf": Color(0.45, 0.95, 0.85), "work": 1500.0, "glow": 1.2,
			"radius": [0.34, 0.44], "height": [5.0, 7.0], "taper": 0.66, "branches": [6, 8],
			# Ghost-white wood and glowing teal leaves hanging over the water.
			"start": 0.48, "pitch": [1.0, 1.4], "length": [0.3, 0.44],
			"foliage": 7.0, "crown": [5.5, 0.26], "style": &"puff", "weight": 0.2, "wet": 0.6},

		{"name": "Emberbark", "min": 12, "near": 1400.0, "item": &"wood_ember",
			"biomes": [Terrain.Biome.MOUNTAIN],
			"leaf": Color(1.0, 0.42, 0.10), "work": 2200.0, "glow": 1.6,
			"radius": [0.40, 0.52], "height": [4.5, 6.0], "taper": 0.7, "branches": [4, 6],
			# Charcoal-black and smouldering: ember-lit knots instead of leaves.
			"start": 0.45, "pitch": [0.6, 1.0], "length": [0.18, 0.28],
			"foliage": 2.5, "crown": [0.0, 0.0], "style": &"ball", "weight": 0.2},

		# Only in the Hidden Valley: walled in by a ridge on the far side of
		# Mirewood, one gorge in and no road. The best timber on the map.
		{"name": "Mahogany", "item": &"wood_mahogany", "site": HIDDEN_VALLEY,
			"biomes": [Terrain.Biome.WOODLAND],
			"leaf": Color(0.16, 0.36, 0.14), "bark": Color(0.42, 0.20, 0.13), "work": 1600.0,
			"radius": [0.5, 0.66], "height": [9.0, 12.0], "taper": 0.7, "branches": [6, 8],
			# Tall, straight and buttressed, with a broad dark canopy on top.
			"start": 0.6, "pitch": [0.8, 1.15], "length": [0.2, 0.3],
			"foliage": 9.0, "crown": [8.0, 0.24], "style": &"ball", "quota": 16},

		{"name": "Dead Snag", "item": &"wood_pine",
			"biomes": [Terrain.Biome.MOUNTAIN, Terrain.Biome.DESERT, Terrain.Biome.SWAMP],
			"leaf": Color(0.4, 0.4, 0.4), "bark": Color(0.52, 0.49, 0.45), "work": 400.0,
			"radius": [0.22, 0.32], "height": [4.0, 6.5], "taper": 0.5, "branches": [2, 4],
			# Grey, bare and broken: cheap wood, but it breaks up the skyline.
			"start": 0.5, "pitch": [0.5, 1.1], "length": [0.12, 0.2],
			"foliage": 0.0, "crown": [0.0, 0.0], "style": &"bare", "weight": 0.3},
	]

	# Quotas follow how much country each species actually has, so a seed that
	# happens to grow little swamp gets few willows rather than an empty field
	# grinding away at a region that is not there.
	var pools: Array[PackedVector3Array] = []
	var total := 0
	var step := 2 if MAP_HALF <= 400.0 else 3
	for kind in species:
		var pool: PackedVector3Array
		if kind.has("site"):
			pool = terrain.points_in_feature(String(kind.site))
		else:
			pool = _banded(terrain.points_in_biomes(kind.biomes, step, float(kind.get("wet", 0.0))),
				float(kind.get("near", 0.0)), float(kind.get("far", INF)))
			total += pool.size()
		pools.append(pool)
	if total == 0:
		return

	for i in species.size():
		var kind: Dictionary = species[i]
		var pool := pools[i]
		if pool.is_empty():
			continue
		var quota: int = int(kind.get("quota", 0))
		if quota == 0:
			quota = int(round(float(tree_count) * float(pool.size()) / float(total)
				* float(kind.get("weight", 1.0)) * 2.0))
		# The rare ones get a few, however little of their country there is.
		quota = maxi(quota, int(kind.get("min", 0)))
		if quota <= 0:
			continue
		var field := ResourceField.new()
		field.name = "Forest_%s" % kind.name.replace(" ", "_")
		field.quota = quota
		field.min_spacing = 4.2
		field.refill_seconds = 6.0
		field.churn_seconds = 30.0
		field.wake_distance = 360.0
		field.setup([kind], _build_tree, _from_pool(pool), _rng.randi())
		add_child(field)
		field.prefill()
		tree_fields.append(field)

## Keeps the spots between `near` and `far` metres from home: the better the
## material, the further out it is.
static func _banded(points: PackedVector3Array, near: float, far: float) -> PackedVector3Array:
	if near <= 0.0 and far == INF:
		return points
	var out := PackedVector3Array()
	for p in points:
		var d := Vector2(p.x, p.z).length()
		if d >= near and d <= far:
			out.append(p)
	return out

## A sampler that draws from a fixed set of spots the terrain already vetted -
## right biome, dry, off the roads and outside the build sites - and then
## shuffles each one a little, so a forest does not stand on the terrain grid
## like an orchard. A nudge that lands somewhere it should not falls back to
## the vetted spot.
func _from_pool(points: PackedVector3Array) -> Callable:
	return func(rng: RandomNumberGenerator) -> Vector3:
		var spot := points[rng.randi() % points.size()]
		var reach := Terrain.CELL * 0.8
		var nudged := Vector3(spot.x + rng.randf_range(-reach, reach), 0.0,
			spot.z + rng.randf_range(-reach, reach))
		if terrain.water_depth(nudged.x, nudged.z) > terrain.water_depth(spot.x, spot.z) \
				or terrain.is_road(nudged.x, nudged.z) or terrain.in_cave_zone(nudged.x, nudged.z) \
				or terrain.biome_at(nudged.x, nudged.z) != terrain.biome_at(spot.x, spot.z) \
				or terrain.is_blocked(nudged.x, nudged.z):
			return spot
		return terrain.place(nudged)

## Wraps a flat-plane sampler so what it returns sits on the actual ground, and
## not in a river or on a road.
func _on_ground(sampler: Callable) -> Callable:
	return func(rng: RandomNumberGenerator) -> Vector3:
		var flat: Vector3 = sampler.call(rng)
		if terrain == null:
			return flat
		if terrain.water_depth(flat.x, flat.z) > 0.0 or terrain.is_road(flat.x, flat.z):
			# Nudged rather than rejected, so a field near a river still fills.
			flat += Vector3(rng.randf_range(-18.0, 18.0), 0.0, rng.randf_range(-18.0, 18.0))
		return terrain.place(flat)

func _build_tree(kind: Dictionary, form_seed: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = form_seed
	var tree := ChoppableTree.new()
	tree.manager = manager
	tree.plot_id = 0
	tree.wood_item = kind.item
	tree.species = String(kind.name)
	tree.seed_form(form_seed)
	tree.branch_count = rng.randi_range(int(kind.branches[0]), int(kind.branches[1]))
	tree.trunk_height = rng.randf_range(kind.height[0], kind.height[1])
	tree.trunk_radius = rng.randf_range(kind.radius[0], kind.radius[1])
	tree.trunk_taper = float(kind.taper)
	tree.work_per_m2 = float(kind.work)
	tree.leaf_color = kind.leaf
	tree.branch_start = float(kind.start)
	tree.branch_pitch = Vector2(kind.pitch[0], kind.pitch[1])
	tree.branch_length = Vector2(kind.length[0], kind.length[1])
	tree.foliage_spread = float(kind.foliage)
	tree.crown_spread = float(kind.crown[0])
	tree.crown_height = float(kind.crown[1])
	tree.foliage_style = kind.get("style", &"cone")
	tree.bark_color = kind.get("bark", Color(0, 0, 0, 0))
	tree.leaf_accent = kind.get("accent", Color(0, 0, 0, 0))
	tree.leaf_glow = float(kind.get("glow", 0.0))
	return tree

## Ore is not only in the quarry. Each kind has country it turns up in out on
## the map - iron in the hills, copper in the desert, a little gold up in the
## snow - and the quarry is simply where there is most of everything, close to
## home. Gold is mostly underground: see the caves.
const WILD_ORE := [
	# Common, and close to home.
	{"item": &"ore_tin", "biomes": [Terrain.Biome.WOODLAND, Terrain.Biome.TAIGA, Terrain.Biome.MOUNTAIN],
		"quota": 52, "volume": [0.35, 2.4], "embed": [0.30, 0.55], "far": 1092.0},
	{"item": &"gem_quartz", "biomes": [Terrain.Biome.WOODLAND, Terrain.Biome.MOUNTAIN, Terrain.Biome.DESERT, Terrain.Biome.TAIGA],
		"quota": 36, "volume": [0.25, 1.4], "embed": [0.35, 0.60], "far": 1260.0},
	{"item": &"ore_iron", "biomes": [Terrain.Biome.MOUNTAIN, Terrain.Biome.TAIGA, Terrain.Biome.WOODLAND],
		"quota": 68, "volume": [0.35, 2.4], "embed": [0.30, 0.55], "far": 1890.0},
	{"item": &"ore_zinc", "biomes": [Terrain.Biome.DESERT, Terrain.Biome.MOUNTAIN, Terrain.Biome.WOODLAND],
		"quota": 40, "volume": [0.30, 2.0], "embed": [0.35, 0.60], "near": 252.0, "far": 1470.0},
	{"item": &"ore_copper", "biomes": [Terrain.Biome.DESERT, Terrain.Biome.MOUNTAIN],
		"quota": 48, "volume": [0.30, 2.0], "embed": [0.35, 0.60], "near": 252.0},
	# A trip: the edge of home island and the near shores of the others.
	{"item": &"ore_magnetite", "biomes": [Terrain.Biome.MOUNTAIN, Terrain.Biome.TAIGA],
		"quota": 32, "volume": [0.3, 1.8], "embed": [0.40, 0.60], "near": 630.0},
	{"item": &"ore_silver", "biomes": [Terrain.Biome.TAIGA, Terrain.Biome.SNOW],
		"quota": 32, "volume": [0.25, 1.5], "embed": [0.40, 0.60], "near": 798.0},
	{"item": &"gem_amethyst", "biomes": [Terrain.Biome.MOUNTAIN, Terrain.Biome.DESERT],
		"quota": 24, "volume": [0.2, 1.1], "embed": [0.40, 0.65], "near": 840.0},
	{"item": &"ore_nickel", "biomes": [Terrain.Biome.SNOW, Terrain.Biome.TAIGA, Terrain.Biome.MOUNTAIN],
		"quota": 28, "volume": [0.25, 1.5], "embed": [0.40, 0.60], "near": 945.0},
	{"item": &"gem_jade", "biomes": [Terrain.Biome.SWAMP, Terrain.Biome.WOODLAND],
		"quota": 24, "volume": [0.25, 1.3], "embed": [0.40, 0.65], "near": 1260.0},
	{"item": &"gem_obsidian", "biomes": [Terrain.Biome.DESERT, Terrain.Biome.MOUNTAIN],
		"quota": 24, "volume": [0.25, 1.4], "embed": [0.40, 0.60], "near": 1260.0},
	{"item": &"ore_cobalt", "biomes": [Terrain.Biome.SWAMP, Terrain.Biome.MOUNTAIN],
		"quota": 24, "volume": [0.25, 1.4], "embed": [0.40, 0.65], "near": 1155.0},
	# The far islands.
	{"item": &"ore_bismuth", "biomes": [Terrain.Biome.DESERT],
		"quota": 16, "volume": [0.2, 1.0], "embed": [0.45, 0.65], "near": 1470.0},
	{"item": &"ore_tungsten", "biomes": [Terrain.Biome.MOUNTAIN, Terrain.Biome.SNOW],
		"quota": 20, "volume": [0.25, 1.4], "embed": [0.45, 0.70], "near": 1575.0},
	{"item": &"ore_gold", "biomes": [Terrain.Biome.SNOW, Terrain.Biome.MOUNTAIN],
		"quota": 16, "volume": [0.20, 1.0], "embed": [0.45, 0.70], "near": 1575.0},
	{"item": &"gem_emerald", "biomes": [Terrain.Biome.SWAMP, Terrain.Biome.WOODLAND],
		"quota": 10, "volume": [0.15, 0.7], "embed": [0.50, 0.70], "near": 1680.0},
	{"item": &"ore_platinum", "biomes": [Terrain.Biome.SNOW],
		"quota": 10, "volume": [0.15, 0.8], "embed": [0.50, 0.70], "near": 1785.0},
	{"item": &"gem_ruby", "biomes": [Terrain.Biome.DESERT],
		"quota": 10, "volume": [0.15, 0.7], "embed": [0.50, 0.70], "near": 1785.0},
	{"item": &"ore_sunstone", "biomes": [Terrain.Biome.DESERT],
		"quota": 8, "volume": [0.15, 0.7], "embed": [0.50, 0.70], "near": 1785.0},
]

## Underground, by how far out the cave is: the nearest are worked-over seams of
## the common stuff, the farthest holds what the surface does not have at all.
const CAVE_TIERS := [
	[&"ore_copper", &"ore_iron", &"ore_tin", &"ore_zinc", &"gem_quartz", &"gem_amethyst"],
	[&"ore_silver", &"ore_magnetite", &"ore_nickel", &"gem_jade", &"ore_cobalt", &"ore_gold"],
	[&"ore_gold", &"gem_emerald", &"gem_ruby", &"ore_platinum", &"ore_tungsten", &"ore_sunstone"],
]
## The farthest cave of all: diamonds, and nowhere else.
const DEEPEST_CAVE := [&"gem_diamond", &"gem_diamond", &"gem_emerald", &"ore_platinum", &"gem_diamond"]

## The quarry works the same way: a patch per ore, stocked to a quota.
func _build_quarry() -> void:
	# Chunk sizes straddle the player's pull: the small end of iron comes out of
	# the ground whole, the big end has to be cracked up first.
	var ores := [
		{"item": &"ore_iron", "volume": [0.35, 2.6], "embed": [0.30, 0.55]},
		{"item": &"ore_copper", "volume": [0.30, 2.2], "embed": [0.35, 0.60]},
		{"item": &"ore_tin", "volume": [0.35, 2.4], "embed": [0.30, 0.55]},
		{"item": &"gem_quartz", "volume": [0.25, 1.4], "embed": [0.35, 0.60]},
		{"item": &"ore_gold", "volume": [0.20, 1.4], "embed": [0.45, 0.70]},
	]
	var per_ore: int = maxi(1, rock_count / ores.size())
	for i in ores.size():
		var kind: Dictionary = ores[i]
		var field := ResourceField.new()
		field.name = "Quarry_%s" % kind.item
		# Gold is scarce even here; the caves and the far north are where it is.
		field.quota = per_ore if kind.item != &"ore_gold" else maxi(1, per_ore / 5)
		field.min_spacing = 4.0
		field.refill_seconds = 8.0
		# Its own corner of the map, so mining is a trip.
		field.setup([kind], _build_rock,
			_on_ground(ResourceField.rect(QUARRY_CENTRE, Vector2(26.0, 30.0))), _rng.randi())
		add_child(field)
		field.prefill()
		rock_fields.append(field)

	var step := 3 if MAP_HALF <= 400.0 else 4
	for kind in WILD_ORE:
		var pool := _banded(terrain.points_in_biomes(kind.biomes, step),
			float(kind.get("near", 0.0)), float(kind.get("far", INF)))
		if pool.is_empty():
			continue
		var field := ResourceField.new()
		field.name = "Wild_%s" % kind.item
		field.quota = int(kind.quota)
		field.min_spacing = 14.0
		field.refill_seconds = 20.0
		field.churn_seconds = 60.0
		field.wake_distance = 320.0
		field.setup([kind], _build_rock, _from_pool(pool), _rng.randi())
		add_child(field)
		field.prefill()
		rock_fields.append(field)

## Starmetal lies where it fell, in the crater on the south-east isle.
func _build_crater() -> void:
	var pool := terrain.points_in_feature(STAR_CRATER)
	if pool.is_empty():
		return
	var field := ResourceField.new()
	field.name = "Crater_Starmetal"
	field.quota = 7
	field.min_spacing = 6.0
	field.refill_seconds = 45.0
	field.setup([{"item": &"ore_starmetal", "volume": [0.3, 1.4], "embed": [0.35, 0.6]}],
		_build_rock, _from_pool(pool), _rng.randi())
	add_child(field)
	field.prefill()
	rock_fields.append(field)

## The caves: the networks are planned under every island, the surface mouths
## the terrain found are built as trench-and-portal entrances into their first
## caverns, and every cavern gets a field of its cave biome's ore - and in the
## fungal caves, giant glowcaps to fell.
func _build_caves() -> void:
	network = CaveNetwork.new()
	network.name = "Caves"
	network.manager = manager
	network.plan(terrain, CAVE_ZONES, CAVE_LINKS, 4242)
	_lap("cave plan")
	for plan in terrain.caves:
		var cave := Cave.new()
		cave.name = String(plan.name).replace(" ", "").replace("'", "")
		cave.with_chamber = false
		cave.setup(plan.entrance, plan.dir, String(plan.name), _rng.randi())
		add_child(cave)
		caves.append(cave)
		network.entrances.append(cave)
	add_child(network)
	_lap("cave build")
	for i in network.rooms.size():
		var room: Dictionary = network.rooms[i]
		var size := maxf(float(room.rx), float(room.rz))
		var ores: Array = []
		for id in CaveNetwork.ORES[int(room.kind)]:
			var def := GameData.item(id)
			var rare := def != null and def.value_per_m3 >= 2400.0
			ores.append({"item": id, "volume": [0.15, 0.9] if rare else [0.3, 1.8],
				"embed": [0.4, 0.65] if rare else [0.3, 0.55]})
		var field := ResourceField.new()
		field.name = "Cavern_%d" % i
		field.quota = 2 if size < 10.0 else (4 if size < 17.0 else 7)
		field.min_spacing = 3.6
		field.refill_seconds = 40.0
		field.spawn_clearance = 0.0
		field.wake_distance = 240.0
		var cavern := room
		field.setup(ores, _build_rock, func(rng: RandomNumberGenerator) -> Vector3:
			return network.floor_point(cavern, rng), _rng.randi())
		add_child(field)
		field.prefill()
		rock_fields.append(field)
		if int(room.kind) == CaveNetwork.Kind.FUNGAL and size >= 9.0:
			var grove := ResourceField.new()
			grove.name = "Glowcaps_%d" % i
			grove.quota = 3 if size < 16.0 else 6
			grove.min_spacing = 5.0
			grove.refill_seconds = 60.0
			grove.spawn_clearance = 0.0
			grove.wake_distance = 240.0
			grove.setup([GLOWCAP], _build_tree, func(rng: RandomNumberGenerator) -> Vector3:
				return network.floor_point(cavern, rng), _rng.randi())
			add_child(grove)
			grove.prefill()
			tree_fields.append(grove)

## The giant mushroom of the fungal caves: a pale stem and a glowing cap.
const GLOWCAP := {"name": "Glowcap", "item": &"wood_glowcap",
	"biomes": [0, 1, 2, 3, 4, 5], "underground": true,
	"leaf": Color(0.35, 0.95, 0.75), "accent": Color(0.85, 1.0, 0.9), "bark": Color(0.86, 0.84, 0.76),
	"work": 450.0, "glow": 1.4,
	"radius": [0.45, 0.75], "height": [3.5, 6.5], "taper": 0.9, "branches": [0, 0],
	"start": 0.9, "pitch": [0.0, 0.1], "length": [0.1, 0.1],
	"foliage": 1.0, "crown": [6.0, 0.45], "style": &"cap"}

func _build_outposts() -> void:
	for spec in OUTPOSTS:
		if not terrain.found_sites.has(spec.name):
			continue
		var at: Vector3 = terrain.found_sites[spec.name]
		var outpost := Outpost.new()
		outpost.name = String(spec.name).replace(" ", "")
		# The further out, the more a cache is worth the trip.
		var reward := int(60.0 + Vector2(at.x, at.z).length() * 0.7)
		outpost.setup(spec.kind, spec.name, _rng.randi(), reward)
		if spec.kind == Outpost.Kind.TRADING_POST:
			outpost.setup_trade(manager, quests, spec.premium)
		outpost.position = at
		# Facing home, so a trader's sign reads as you arrive from the plot.
		outpost.rotation.y = atan2(-at.x, -at.z)
		add_child(outpost)
		outposts.append(outpost)
	# A miner's camp by each cave mouth, off to one side of the trench.
	for cave in caves:
		var camp := Outpost.new()
		camp.name = "%sCamp" % cave.name
		var mouth := cave.global_transform
		camp.setup(Outpost.Kind.MINERS_CAMP, "%s Camp" % cave.cave_name, _rng.randi(),
			int(80.0 + mouth.origin.length() * 0.6))
		camp.position = mouth * Vector3(-9.0, 0.0, -3.0)
		camp.rotation.y = atan2(-mouth.basis.z.x, -mouth.basis.z.z)
		add_child(camp)
		outposts.append(camp)

## Everything worth marking on the map and the compass.
func points_of_interest() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cave in caves:
		out.append({"name": cave.cave_name, "kind": "cave", "pos": cave.global_position,
			"color": Color(0.78, 0.66, 1.0)})
	for outpost in outposts:
		if outpost.kind == Outpost.Kind.MINERS_CAMP:
			continue
		var trade := outpost.kind == Outpost.Kind.TRADING_POST
		out.append({"name": outpost.place_name, "kind": "trade" if trade else "place",
			"pos": outpost.global_position,
			"color": Color(0.98, 0.72, 0.35) if trade else Color(0.70, 0.90, 0.62)})
	return out

var _map_texture: Texture2D

## The land from above for the journal's map, drawn once per world.
func map_texture() -> Texture2D:
	if _map_texture == null:
		_map_texture = ImageTexture.create_from_image(terrain.map_image(4))
	return _map_texture

func discovered(name: String) -> bool:
	return PlayerState.discovered.has(name)

## Walking up to a place puts its name on the map for good.
func _check_discovery(delta: float) -> void:
	_discover_timer -= delta
	if _discover_timer > 0.0:
		return
	_discover_timer = 0.5
	var here := player.global_position
	for poi in points_of_interest():
		if discovered(poi.name):
			continue
		var p: Vector3 = poi.pos
		if Vector2(p.x - here.x, p.z - here.z).length() < 40.0:
			PlayerState.discovered.append(poi.name)
			hud.show_banner("Discovered", poi.name)

func _build_rock(kind: Dictionary, form_seed: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = form_seed
	var rock := OreRock.new()
	rock.manager = manager
	rock.plot_id = 0
	rock.ore_item = kind.item
	rock.seed_form(form_seed)
	rock.embed = rng.randf_range(kind.embed[0], kind.embed[1])
	rock.volume = rng.randf_range(kind.volume[0], kind.volume[1])
	return rock

## The buyer's yard: material left inside the fence is bought when the player
## asks the shopkeep, not the moment it touches the ground.
func _build_depot() -> void:
	depot = SellYard.new()
	depot.name = "SellYard"
	depot.setup(manager, quests)
	depot.extents = Vector3(18.0, 4.0, 18.0)
	depot.position = terrain.place(DEPOT_POSITION)
	add_child(depot)
	Nameplate.landmark(depot, "SELL YARD", 5.5)

	var sign_mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(8.0, 0.4, 0.4)
	sign_mesh.mesh = bm
	sign_mesh.position = terrain.place(DEPOT_POSITION, 3.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.78, 0.2)
	sign_mesh.material_override = mat
	add_child(sign_mesh)

## Spec: a store you walk into, with stock in boxes on shelves and a counter to
## carry them to.
func _build_store() -> void:
	if terrain.found_sites.has(SUMMIT_STORE):
		var at: Vector3 = terrain.found_sites[SUMMIT_STORE]
		summit_store = Store.new()
		summit_store.name = "SummitStore"
		summit_store.setup(manager, plot, 0, &"summit")
		summit_store.position = at
		# Door toward home.
		summit_store.rotation.y = atan2(-at.x, -at.z)
		add_child(summit_store)
		Nameplate.landmark(summit_store, "SUMMIT OUTFITTERS", 6.5)
	store = Store.new()
	store.name = "Store"
	store.setup(manager, plot, 0)
	store.position = terrain.place(STORE_POSITION)
	store.rotation.y = PI
	add_child(store)
	Nameplate.landmark(store, "STORE", 6.0)

func _make_player() -> Player:
	var p := Player.new()
	p.name = "Player"
	p.position = Vector3(0, 2.0, 12.0)
	# Facing down the road to the yard and the store, not at a hillside.
	p.rotation.y = PI
	p.terrain = terrain
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	p.add_child(cs)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.position = Vector3(0, 1.65, 0)
	cam.far = 400.0
	cam.current = true
	p.add_child(cam)
	return p

## Handed to the save system so a game saved before pads existed still gets its
## truck back.
func _spawn_vehicle_for_load() -> Node3D:
	spawn_vehicle()
	return hauler

## Every tree still standing, across all fields.
func trees() -> Array[ChoppableTree]:
	var out: Array[ChoppableTree] = []
	for field in tree_fields:
		for node in field.alive:
			var tree := node as ChoppableTree
			if tree != null and tree.standing():
				out.append(tree)
	return out

## Everything the fields hold, built or still a note far away: {what, pos,
## species}. `what` is the wood or ore item id.
func census() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for field in tree_fields + rock_fields:
		for node in field.alive:
			if not is_instance_valid(node):
				continue
			if node is ChoppableTree:
				var tree := node as ChoppableTree
				if tree.standing():
					out.append({"what": tree.wood_item, "pos": tree.global_position, "species": tree.species})
			elif node is OreRock:
				out.append({"what": (node as OreRock).ore_item, "pos": node.global_position, "species": ""})
		for note in field.dormant:
			var entry: Dictionary = note.entry
			out.append({"what": entry.get("item", &""), "pos": field.to_global(note.position),
				"species": String(entry.get("name", ""))})
	return out

## Every rock still intact, across all fields.
func rocks() -> Array[OreRock]:
	var out: Array[OreRock] = []
	for field in rock_fields:
		for node in field.alive:
			var rock := node as OreRock
			if rock != null:
				out.append(rock)
	return out

## The truck comes off a pad now, so this only covers the case where the player
## owns one and has no pad standing - a game saved before pads existed.
func spawn_vehicle() -> void:
	if hauler != null and is_instance_valid(hauler):
		return
	for pad in plot.pads():
		hauler = pad.spawn() as Hauler
		return
	hauler = Hauler.new()
	hauler.setup(manager, 0)
	hauler.terrain = terrain
	hauler.position = terrain.place(Vector3(10, 0, 16), 1.5)
	add_child(hauler)

## Pads save their own vehicles with the plot. Only a truck from a game that
## predates pads needs saving on its own.
func _padless_vehicle() -> Node3D:
	if hauler == null or not is_instance_valid(hauler):
		return null
	for pad in plot.pads():
		if pad.vehicle == hauler:
			return null
	return hauler

## A pad replaces its own vehicle; if that is the one being driven, the driver
## is put back on their feet first.
func _on_vehicle_spawned(vehicle: Node3D) -> void:
	if player != null and player.driving():
		var riding: Node3D = player.vehicle
		if riding == null or not is_instance_valid(riding) or riding.is_queued_for_deletion():
			player.exit_vehicle()
	if player == null or not player.driving():
		hauler = vehicle as Hauler

## Every vehicle out in the world: one per pad, plus a truck from a save that
## predates pads.
func vehicles() -> Array[Hauler]:
	var out: Array[Hauler] = []
	for pad in plot.pads():
		if pad.has_vehicle() and not pad.vehicle.is_queued_for_deletion():
			out.append(pad.vehicle as Hauler)
	if hauler != null and is_instance_valid(hauler) and not hauler.is_queued_for_deletion() \
			and not out.has(hauler):
		out.append(hauler)
	return out

## The vehicle you are driving, or else the nearest one within `reach`
## (measured to its hull, so a long truck is as easy to get into as a quad).
## How far the player stands from a vehicle's body.
func _distance_to(v: Hauler) -> float:
	var local := v.global_transform.affine_inverse() * player.global_position
	var half := v.body_size * 0.5
	return Vector3(maxf(absf(local.x) - half.x, 0.0), 0.0, maxf(absf(local.z) - half.z, 0.0)).length()

func vehicle_at_hand(reach: float = 6.0) -> Hauler:
	if player != null and player.driving():
		return player.vehicle as Hauler
	var best: Hauler = null
	var best_d := INF
	for v in vehicles():
		var local := v.global_transform.affine_inverse() * player.global_position
		var half := v.body_size * 0.5
		var outside := Vector3(maxf(absf(local.x) - half.x, 0.0), 0.0, maxf(absf(local.z) - half.z, 0.0))
		var d := outside.length()
		if d < best_d:
			best = v
			best_d = d
	return best if best_d <= reach else null

# --- Menus, settings and the HUD's view of the world -----------------------

## Places the compass marks. Each returns null while it does not exist.
func compass_markers() -> Array[Dictionary]:
	var base: Array[Dictionary] = [
		{"name": "Plot", "color": Color(0.55, 0.85, 0.50), "where": func(): return plot.global_position},
		{"name": "Sell Yard", "color": Color(0.98, 0.80, 0.30), "where": func(): return depot.global_position},
		{"name": "Store", "color": Color(0.55, 0.78, 1.0), "where": func(): return store.global_position},
		{"name": "Summit Outfitters", "color": Color(0.7, 0.62, 1.0), "where": func():
			return summit_store.global_position if summit_store != null else null},
		{"name": "Quarry", "color": Color(0.80, 0.70, 0.62), "where": func(): return QUARRY_CENTRE},
		{"name": "Demo Lines", "color": Color(0.95, 0.55, 0.9), "where": func():
			return showcase.global_position if showcase != null else null},
	]
	# Each kind of vehicle you own, wherever it was left.
	for id in GameData.vehicles:
		var spec: Dictionary = GameData.vehicles[id]
		var c: Array = spec.get("paint", [1.0, 0.55, 0.4])
		var kind: StringName = id
		base.append({"name": String(spec.get("display_name", id)),
			"color": Color(c[0], c[1], c[2]).lightened(0.2), "where": func():
				for v in vehicles():
					if v.vehicle_id == kind and v != player.vehicle:
						return v.global_position
				return null})
	# Places out on the map: named once found, a "?" when close and not yet.
	var markers: Array[Dictionary] = base
	for poi in points_of_interest():
		var poi_name: String = poi.name
		var pos: Vector3 = poi.pos
		markers.append({"name": func(): return poi_name if discovered(poi_name) else "?",
			"color": poi.color, "where": func():
				if discovered(poi_name) or player.global_position.distance_to(pos) < 220.0:
					return pos
				return null})
	return markers

func _build_menus() -> void:
	_fader = ColorRect.new()
	_fader.color = Color(0.03, 0.05, 0.04)
	_fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 100
	fade_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	fade_layer.add_child(UIKit.fill(_fader))
	add_child(fade_layer)
	var tween := _fader.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_fader, "color:a", 0.0, 0.9).set_ease(Tween.EASE_IN)

	pause_menu = PauseMenu.new()
	pause_menu.resume_requested.connect(resume_play)
	pause_menu.home_requested.connect(func():
		return_to_base()
		resume_play())
	pause_menu.save_requested.connect(func():
		quick_save()
		resume_play())
	pause_menu.load_requested.connect(func():
		quick_load()
		resume_play())
	pause_menu.main_menu_requested.connect(func():
		quick_save()
		pause_menu.close()
		show_main_menu())
	pause_menu.quit_requested.connect(quit_game)
	add_child(pause_menu)

	var menu_wanted := show_menu and get_tree().current_scene == self and not MainMenu.skip_once
	MainMenu.skip_once = false
	if menu_wanted:
		main_menu = MainMenu.new()
		main_menu.continue_requested.connect(resume_play)
		main_menu.new_game_requested.connect(start_new_game)
		main_menu.quit_requested.connect(quit_game)
		add_child(main_menu)
		show_main_menu()
	else:
		playing = true

func show_main_menu() -> void:
	if main_menu == null:
		main_menu = MainMenu.new()
		main_menu.continue_requested.connect(resume_play)
		main_menu.new_game_requested.connect(start_new_game)
		main_menu.quit_requested.connect(quit_game)
		add_child(main_menu)
	hud.visible = false
	get_tree().paused = true
	main_menu.open(self)

func pause_game() -> void:
	if get_tree().paused:
		return
	get_tree().paused = true
	pause_menu.open()

func resume_play() -> void:
	if main_menu != null and main_menu.visible:
		main_menu.close()
	pause_menu.close()
	hud.visible = true
	playing = true
	get_tree().paused = false
	player.capture_mouse(not hud.journal_open())

func quick_save() -> bool:
	var ok := SaveSystem.save_game(plot, player, SaveSystem.SAVE_PATH, manager, _padless_vehicle(), quests)
	if ok:
		hud.flash_saved()
	else:
		hud.toast("Save failed", UITheme.BAD)
	return ok

func quick_load() -> void:
	if SaveSystem.load_game(plot, player, SaveSystem.SAVE_PATH, manager,
			_spawn_vehicle_for_load, quests):
		hud.toast("Loaded your last save", UITheme.ACCENT)
	else:
		hud.toast("No save to load", UITheme.BAD)

## A fresh world, not this one scrubbed: the progress autoloads are reset and
## the scene is built again from nothing.
func start_new_game() -> void:
	if not SaveSystem.has_save() and not playing:
		# Nothing to throw away - the world behind the menu is already new.
		resume_play()
		return
	SaveSystem.delete_save()
	PlayerState.reset()
	Economy.from_dict({})
	MainMenu.skip_once = true
	var tween := _fader.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_fader, "color:a", 1.0, 0.35)
	tween.tween_callback(func():
		get_tree().paused = false
		get_tree().reload_current_scene())

func quit_game() -> void:
	if playing:
		SaveSystem.save_game(plot, player, SaveSystem.SAVE_PATH, manager, _padless_vehicle(), quests)
	get_tree().quit()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			if playing and hud != null:
				SaveSystem.save_game(plot, player, SaveSystem.SAVE_PATH, manager, _padless_vehicle(), quests)
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			# Alt-tab pauses, rather than leaving the truck rolling.
			if playing and pause_menu != null and not get_tree().paused \
					and DisplayServer.get_name() != "headless":
				pause_game()

func _on_setting_changed(_key: StringName) -> void:
	_apply_all_settings()

## The demo lines come and go with their setting.
func _apply_showcase() -> void:
	var wanted := Settings.flag(&"demo_lines")
	if wanted and showcase == null:
		showcase = Showcase.new()
		showcase.name = "Showcase"
		showcase.setup(manager)
		# Stood on the highest ground under the slab, so none of it is buried.
		var top := -INF
		for dx in range(-11, 12, 2):
			for dz in range(-27, 20, 2):
				top = maxf(top, terrain.height_at(SHOWCASE_POSITION.x + dx, SHOWCASE_POSITION.z + dz))
		showcase.position = Vector3(SHOWCASE_POSITION.x, top + 0.05, SHOWCASE_POSITION.z)
		add_child(showcase)
		Nameplate.landmark(showcase, "DEMO LINES", 7.0)
	elif not wanted and showcase != null:
		showcase.clear_all()
		showcase.queue_free()
		showcase = null

func _apply_all_settings() -> void:
	_apply_showcase()
	var cam := player.camera
	cam.fov = float(Settings.value(&"fov"))
	var reach := float(Settings.value(&"view_distance"))
	cam.far = reach
	# Clear air most of the way out, then haze thick enough that the far
	# plane is lost in it, never a hard edge.
	environment.fog_depth_begin = reach * 0.6
	environment.fog_depth_end = reach * 0.98
	var shadows := int(Settings.value(&"shadows"))
	sun.shadow_enabled = shadows > 0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if shadows >= 2 \
		else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 160.0 if shadows >= 2 else 70.0
	environment.ssao_enabled = Settings.flag(&"ambient_occlusion")
	environment.glow_enabled = Settings.flag(&"bloom")
	if not Settings.flag(&"moving_sun"):
		sun.rotation_degrees = Vector3(-52, -38, 0)
		sun.light_color = Color(1.0, 0.95, 0.86)

## Spec: a market day. The sun crosses the sky with it - morning light when the
## prices are new, long shadows when they are about to change - but it never
## sets, because nobody wants to chop trees in the dark.
func _update_sun() -> void:
	if not Settings.flag(&"moving_sun"):
		return
	var t := Economy.day_progress()
	var arc := sin(t * PI)
	var elevation := lerpf(16.0, 62.0, arc)
	var azimuth := lerpf(-110.0, 70.0, t)
	sun.rotation_degrees = Vector3(-elevation, azimuth, 0.0)
	sun.light_color = Color(1.0, 0.80, 0.62).lerp(Color(1.0, 0.96, 0.88), clampf(arc * 1.6, 0.0, 1.0))
	sun.light_energy = lerpf(1.0, 1.3, arc)

# --- Runtime ---------------------------------------------------------------

func _process(delta: float) -> void:
	_update_sun()
	_update_underground(delta)
	_check_discovery(delta)

## Underground the sky goes away: ambient light and the sun fade, the haze
## turns dark, and a lamp on the player's hat comes on. The caves' own lamps
## and crystals are then what you see by.
func _update_underground(delta: float) -> void:
	var eye := player.camera.global_position
	var target := network.depth_factor(eye) if network != null else 0.0
	underground = move_toward(underground, target, delta * 1.5)
	# Underground the ambient light is the cave's own - dim and cool - rather
	# than the sky's; the lamps and crystals do the rest.
	if underground > 0.02:
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(0.62, 0.70, 0.80).lerp(Color(0.34, 0.32, 0.42), underground)
		environment.ambient_light_energy = lerpf(OUTDOOR_AMBIENT, 1.1, underground)
		# Without this the "colour" ambient is still mostly the (dimmed) sky.
		environment.ambient_light_sky_contribution = 1.0 - underground
	else:
		environment.ambient_light_sky_contribution = 1.0
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.ambient_light_energy = OUTDOOR_AMBIENT
	environment.fog_light_color = Color(0.68, 0.78, 0.87).lerp(Color(0.03, 0.03, 0.05), underground)
	environment.background_energy_multiplier = lerpf(1.0, 0.05, underground)
	sun.light_energy = lerpf(sun.light_energy, 0.0, underground)
	if _headlamp == null:
		_headlamp = OmniLight3D.new()
		_headlamp.name = "Headlamp"
		_headlamp.light_color = Color(1.0, 0.92, 0.80)
		_headlamp.omni_range = 14.0
		_headlamp.shadow_enabled = false
		_headlamp.position = Vector3(0.3, 0.2, 0.0)
		player.camera.add_child(_headlamp)
	_headlamp.light_energy = underground * 1.8
	_headlamp.visible = underground > 0.01
	var plates_on := underground < 0.5
	if plates_on != _plates_shown:
		_plates_shown = plates_on
		get_tree().call_group(Nameplate.LANDMARK_GROUP, "set_visible", plates_on)

## Below every cave: anyone down here has fallen out of the world.
const FELL_OUT_Y := -160.0

## Back to where the game starts, by the plot: for when you are stuck out
## somewhere, or have fallen through the world. The truck stays where it is.
func return_to_base() -> void:
	if player.driving():
		player.exit_vehicle()
	var spot := Vector3(0, 0, 12.0)
	spot.y = terrain.height_at(spot.x, spot.z) + 1.0
	player.global_position = spot
	player.velocity = Vector3.ZERO
	player.rotation.y = PI
	hud.toast("Back at base", UITheme.GOOD)

func _physics_process(delta: float) -> void:
	if player != null and player.global_position.y < FELL_OUT_Y:
		return_to_base()
	# Standing by a truck, its winch answers the reel keys too.
	if player != null and not player.driving() and playing:
		var wv := vehicle_at_hand(10.0)
		if wv != null and wv.rig != null and wv.rig.anchored and _distance_to(wv) <= 10.0:
			player.work_winch(wv.rig, delta)
	var riding := player.vehicle as Hauler if player != null and player.driving() else null
	if riding != null and is_instance_valid(riding):
		# The player rides the seat; the camera is a child of the player, so
		# this doubles as the driving camera.
		player.global_position = riding.seat_transform().origin
		player.velocity = Vector3.ZERO
	if not autosave or not playing or not Settings.flag(&"autosave"):
		return
	_autosave_timer -= delta
	if _autosave_timer <= 0.0:
		_autosave_timer = AUTOSAVE_SECONDS
		quick_save()

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or hud.journal_open():
		return
	# In build mode Z, X and C turn the ghost; they must not also empty the truck.
	var building := build_system != null and build_system.active
	match key.keycode:
		KEY_F5:
			if quick_save():
				hud.toast("Saved", UITheme.GOOD)
		KEY_F9:
			quick_load()
		KEY_F8:
			pause_game()
			pause_menu.ask("Start a new game?",
				"Your saved game will be replaced. Settings are kept.", "Start over",
				start_new_game)
		KEY_V:
			if not building:
				_toggle_vehicle()
		KEY_X:
			var v := vehicle_at_hand(8.0)
			if v != null and not building:
				if not v.has_bed():
					hud.log_message("the %s has nothing to unload" % v.display_name.to_lower())
				else:
					var n := v.unload()
					var how := "tub up" if v.bed_kind == &"tub" else "tailgate down"
					hud.log_message("%s: tipping out %d piece(s)" % [how, n] if n > 0 else "the bed is empty")
		KEY_Z:
			var v := vehicle_at_hand(8.0)
			if v != null and not building and v.unload_one():
				hud.log_message("dropping one off the back (%d left)" % (v.cargo_count() - 1))
		KEY_Y:
			# The winch from outside the truck: stand by it, aim, hook on.
			if not player.driving() and not building:
				var wv := vehicle_at_hand(10.0)
				if wv == null or wv.rig == null or _distance_to(wv) > 10.0:
					hud.log_message("stand by a truck with a winch to use it")
				else:
					hud.log_message(player.hook_winch(wv.rig))
		KEY_O:
			if not player.driving() and not building:
				var ov := vehicle_at_hand(10.0)
				if ov == null or ov.rig == null or _distance_to(ov) > 10.0:
					hud.log_message("stand by a truck with outriggers to put them out")
				else:
					hud.log_message(player.toggle_outriggers(ov.rig))
		KEY_C:
			var v := vehicle_at_hand(8.0)
			if v != null and not building:
				v.recover()
				hud.toast("%s recovered" % v.display_name, UITheme.ACCENT)

func _toggle_vehicle() -> void:
	if player.driving():
		var riding := player.vehicle as Hauler
		player.exit_vehicle()
		if riding != null and is_instance_valid(riding):
			riding.driver = null
			# Out of the driver's door, clear of the body whatever its width.
			player.global_position = riding.global_position \
				+ riding.global_transform.basis.x * (riding.body_size.x * 0.5 + 1.3) + Vector3(0, 1.0, 0)
			hud.log_message("left the %s" % riding.display_name.to_lower())
		return
	if vehicles().is_empty():
		hud.log_message("No vehicle yet - they are sold at the Store, and each spawns on its own pad")
		return
	hud.log_message("aim at a vehicle's driver seat and press [E] to get in")

## Into the driving seat of `v`.
func drive(v: Hauler) -> void:
	if v == null or player.driving():
		return
	hauler = v
	player.enter_vehicle(v)
	v.driver = player
	hud.log_message("driving the %s - [V] to get out" % v.display_name.to_lower())
	if v.cargo_count() > 0:
		hud.log_message("%d piece(s) in the bed - they ride loose, so mind the corners" % v.cargo_count())
