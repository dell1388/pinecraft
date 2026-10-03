class_name World
extends Node3D

## The game scene: terrain, forest, quarry, the player's plot, the sell depot,
## the player and the HUD, plus save/load and vehicle handling.

const Workers := preload("res://scripts/core/Workers.gd")

## 4.8 km across: a big home island and five more round it, joined by bridges
## and a causeway - bar one, which only a tunnel under the sea reaches.
const MAP_HALF := 2400.0
const DEPOT_POSITION := Vector3(32, 0, 86)
## The yard's open front faces the drive (west); its hut is at the back.
const DEPOT_YAW := -PI * 0.5
const STORE_POSITION := Vector3(185, 0, 52)
## The town's other shops, each its own building on its own lot: vehicles at
## the dealer, machines at the works.
const DEALER_POSITION := Vector3(125, 0, 105)
const WORKS_POSITION := Vector3(232, 0, 100)
## Out on its own in a taiga valley west of the north road, clear of
## everything else, and drawn out north to south into a long oval.
const QUARRY_CENTRE := Vector3(-360, 0, -680)
const QUARRY_RADIUS := 90.0
const QUARRY_STRETCH := 1.7
## The long axis runs north-south; the road comes in on the east side.
const QUARRY_ANGLE := -PI * 0.5
const QUARRY_FLOOR_RADIUS := 24.0
## Where the demo lines stand when they are switched on (Settings > Debug).
const SHOWCASE_POSITION := Vector3(28, 0, 188)
const SHOWCASE_GROUND := 2.0
## The cave networks: one per island (the home island's is huge), each with
## its cave biomes placed under the country that matches them, and how many
## surface mouths it gets. Home and Hollow Isle are joined by the deep tunnel.
const CAVE_ZONES := [
	{"name": "Home", "centre": Vector2(0, 0), "radius": 1150.0, "rooms": 36, "mouths": 9,
		"kinds": [[CaveNetwork.Kind.RIVER, Vector2(80, 260)], [CaveNetwork.Kind.RIVER, Vector2(-980, -120)],
			[CaveNetwork.Kind.CRYSTAL, Vector2(660, -540)], [CaveNetwork.Kind.DESERT, Vector2(-640, 680)],
			[CaveNetwork.Kind.ICE, Vector2(-320, -820)], [CaveNetwork.Kind.MAGMA, Vector2(900, 500)]]},
	{"name": "Frostreach", "centre": Vector2(0, -1850), "radius": 380.0, "rooms": 6, "mouths": 2,
		"kinds": [[CaveNetwork.Kind.ICE, Vector2(0, -1850)]]},
	{"name": "Sunscar", "centre": Vector2(1850, 120), "radius": 370.0, "rooms": 6, "mouths": 2,
		"kinds": [[CaveNetwork.Kind.MAGMA, Vector2(1850, 120)]]},
	{"name": "Mirewood", "centre": Vector2(-1850, 220), "radius": 380.0, "rooms": 6, "mouths": 2,
		"kinds": [[CaveNetwork.Kind.FUNGAL, Vector2(-1850, 220)]]},
	{"name": "Hollow Isle", "centre": Vector2(-1450, 1450), "radius": 240.0, "rooms": 4, "mouths": 1,
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

@export var tree_count: int = int(Balance.num("world.tree_count", 14000.0))
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
var dealer_store: Store
var works_store: Store
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
## fell out of the sky; and Hollow Isle in the south-west, reached by a road
## over two bridges and a stepping-stone islet (and the deep tunnel under the
## sea).
const ISLANDS := [
	{"name": "Home Island", "centre": Vector2(0, 0), "radius": 1220.0},
	{"name": "Frostreach", "centre": Vector2(0, -1850), "radius": 403.0},
	{"name": "Sunscar", "centre": Vector2(1850, 120), "radius": 396.0},
	{"name": "Mirewood", "centre": Vector2(-1850, 220), "radius": 403.0},
	{"name": "Crater Isle", "centre": Vector2(1150, 1150), "radius": 247.0},
	{"name": "Hollow Isle", "centre": Vector2(-1450, 1450), "radius": 262.0},
	{"name": "Stepping Stone", "centre": Vector2(-1060, 1060), "radius": 150.0},
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
	# Rolling woodland, not taiga crags: easy going for a loaded truck.
	{"name": "Hollow Isle", "centre": Vector2(-1450, 1450), "biome": Terrain.Biome.WOODLAND, "scale": 1.4},
]
## Places that are there to be found (the valley has a road now; the crater has none).
const HIDDEN_VALLEY := "Hidden Valley"
const STAR_CRATER := "Star Crater"
var decor: Decor
## Grass and flowers round the camera (the Grass setting).
var grass: GrassField
## Birds in the sky (the Birds setting).
var birds: Birds
var _discover_timer: float = 0.0

## Where the land is under a loose item, for the manager's fall-through
## check. Nothing is claimed inside a cave, where everything is below the land.
func _ground_for_items(p: Vector3) -> float:
	if network != null and network.contains(p, 2.0):
		return -INF
	if absf(p.x) > MAP_HALF or absf(p.z) > MAP_HALF:
		return -INF
	var ground := terrain.height_at(p.x, p.z)
	if p.y < ground - 1.0 and _on_cave_rock(p):
		return -INF
	return ground

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
## The moon: cool, dim light from the other side of the sky at night.
var moon: DirectionalLight3D
## Where a winch to hand would hook on, if you pressed the key now.
var winch_reticle: WinchReticle
var _sky: ProceduralSkyMaterial
## How much daylight there is, 1 at noon to 0 at midnight, and how dark it is
## (the other way round, eased so dusk is short).
var daylight: float = 1.0
var night: float = 0.0
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

## Set by the boot screen: build in stages, a frame apart, with the world held
## still until it is done, so the loading screen can show how far along it is.
var staged_load: bool = false
signal load_progress(stage: String, fraction: float)
## One step inside a stage, as it starts: what is being done, with numbers.
signal load_detail(text: String)
signal finished_loading()

## The stages of building the world, and how far along the whole each one
## starts, for the boot screen's checklist.
const LOAD_STAGES := [
	["Raising the land", 0.02],
	["Planting the forests", 0.55],
	["Laying the rock", 0.70],
	["Digging the caves", 0.80],
	["Opening the shops", 0.92],
	["Setting you down", 0.96],
]

## Between build stages: says how far along it is and, loading behind the boot
## screen, gives it a frame to draw.
func _stage(next: String, fraction: float) -> void:
	if not staged_load:
		return
	load_progress.emit(next, fraction)
	await get_tree().process_frame
	await get_tree().process_frame

## Behind the boot screen, the tree: the slow sums in building the world run
## on worker threads while frames go by here, so the screen goes on drawing
## (see Workers). Otherwise null, and they just run.
func _loading_tree() -> SceneTree:
	return get_tree() if staged_load else null

## Inside a stage: says what it is doing now and, behind the boot screen,
## gives it a frame to show it. Off the boot screen it does nothing and
## returns at once.
func _detail(text: String) -> void:
	if not staged_load:
		return
	if OS.has_environment("PROFILE_LOAD"):
		print("load detail: ", text)
	load_detail.emit(text)
	await get_tree().process_frame

func _ready() -> void:
	_lap_ms = Time.get_ticks_msec()
	if staged_load:
		# Nothing moves or falls until the whole world is there.
		process_mode = Node.PROCESS_MODE_DISABLED
	await _stage(LOAD_STAGES[0][0], LOAD_STAGES[0][1])
	_rng.seed = 20260921
	InputSetup.ensure()
	# Which map: a guest builds the host's; otherwise the slot's own, or the
	# one picked for a new game.
	if Net.is_client():
		WorldMap.current = WorldMap.valid(Net.host_map)
	else:
		SaveSystem.choose_start_slot()
		WorldMap.pick_for_slot()
	await _detail("Setting up the sky, the sun and the sea")
	_build_environment()
	await _build_terrain()
	_lap("terrain")
	await _stage(LOAD_STAGES[1][0], LOAD_STAGES[1][1])
	await _detail("Scattering rocks, grass and flowers over the land")
	decor = Decor.new()
	decor.name = "Decor"
	decor.setup(terrain, 7331)
	add_child(decor)
	grass = GrassField.new()
	grass.name = "Grass"
	grass.setup(terrain)
	add_child(grass)
	birds = Birds.new()
	birds.name = "Birds"
	birds.setup(terrain)
	add_child(birds)

	manager = LooseItemManager.new()
	manager.name = "LooseItems"
	add_child(manager)
	manager.register_plot(0, Vector3(0, 6, 0))
	manager.ground_height = _ground_for_items
	Net.guest_world = Net.is_client()
	if Net.is_client():
		# Every piece here is a copy of one on the host, moved by the host.
		manager.mirror = true
		manager.set_physics_process(false)

	plot = Plot.new()
	plot.name = "Plot"
	plot.position.y = PAD_HEIGHT
	plot.setup(manager, 0)
	plot.vehicle_host = self
	plot.terrain = terrain
	# Over the cap, pieces are recycled off the property first, and never on it.
	manager.on_property = func(p: Vector3) -> bool: return plot.contains_world(p, 1.0)
	plot.vehicle_spawned.connect(_on_vehicle_spawned)
	add_child(plot)

	quests = QuestLog.new()
	quests.name = "Quests"
	quests.setup(GameData.quest_pool(), GameData.quest_slots())
	add_child(quests)

	_lap("terrain+decor")
	await _build_forest()
	_lap("forest")
	await _stage(LOAD_STAGES[2][0], LOAD_STAGES[2][1])
	await _build_quarry()
	await _detail("Dropping starmetal into the crater where it fell")
	if WorldMap.is_ostars():
		_build_kael()
	else:
		_build_crater()
	_lap("rocks")
	await _stage(LOAD_STAGES[3][0], LOAD_STAGES[3][1])
	await _build_caves()
	_lap("cave fields")
	await _stage(LOAD_STAGES[4][0], LOAD_STAGES[4][1])
	if WorldMap.is_ostars():
		await _detail("Opening the shops, and the traders' yards: Old Bjorn, Dusty and Granny Opal")
		_build_ostars_places()
	else:
		await _detail("Building the outposts, trading posts and miners' camps")
		_build_outposts()
		await _detail("Opening the sell depot")
		_build_depot()
		await _detail("Stocking the hardware store, the vehicle dealer and the machine works")
		_build_store()
	_lap("places")
	await _stage(LOAD_STAGES[5][0], LOAD_STAGES[5][1])
	await _detail("Making you, your tools and your build kit")

	player = _make_player()
	add_child(player)
	# The traders look at you and talk to you.
	NpcFigure.default_watch = func(): return player
	# Fields keep their churn and spawning away from wherever the player is.
	for field in tree_fields + rock_fields:
		field.focus = player
	decor.focus = player
	grass.pusher = player
	_keep_grass_off_plot()
	plot.expanded.connect(func(_t: int, _h: float):
		_keep_grass_off_plot()
		grass.refresh())
	birds.focus = player
	player.manager = manager
	player.plot = plot
	player.store = store
	player.stores = all_stores()
	for shop in player.stores:
		shop.kit_source = all_kits
	player.wants_to_drive.connect(func(v: Node3D): drive(v as Hauler))

	build_system = BuildSystem.new()
	build_system.setup(plot, player.camera, player)
	add_child(build_system)
	player.build_system = build_system

	hud = GameHUD.new()
	hud.setup(player, plot, manager, self)
	add_child(hud)

	var loaded := false
	if Net.is_client():
		# A guest plays in the host's world: nothing of its own save is used.
		autosave = false
		player.net_view = true
		# Walks on the ground here but is nothing for anything else to hit.
		player.collision_layer = 0
		# Nothing of this player's own game comes along: the host's money,
		# unlocks and quests arrive with its world, and a blank kit till then.
		PlayerState.reset()
		Economy.from_dict({})
		quests.from_dict({})
	else:
		SaveSystem.choose_start_slot()
	if Net.is_client():
		await _detail("Waiting for the host's world")
	elif SaveSystem.has_save():
		await _detail("Loading your save: your plot, buildings, vehicles, money and quests")
	else:
		await _detail("No save yet: a new game, with a starting float")
	if not Net.is_client() and SaveSystem.has_save():
		loaded = SaveSystem.load_game(plot, player, "", manager,
			_spawn_vehicle_for_load, quests)
		if loaded:
			_unstick_player()
			# Trucks on their pads may come a frame later.
			_unstick_player.call_deferred()
	loaded_game = loaded
	if not loaded and not Net.is_client():
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
	if leave_reason != "":
		hud.toast("Left co-op: %s" % leave_reason, UITheme.BAD)
		hud.log_message("left co-op: %s" % leave_reason)
		leave_reason = ""
	hud.toast("Welcome back - day %d" % Economy.day if loaded else
		"You have %s. Fell a tree to get started." % UIKit.money(Economy.money), UITheme.ACCENT)

	await _detail("Applying your settings and building the menus")
	Settings.changed.connect(_on_setting_changed)
	_apply_all_settings()
	_build_menus()
	set_physics_process(true)
	if staged_load:
		process_mode = Node.PROCESS_MODE_INHERIT
		load_progress.emit("Ready", 1.0)
	if Net.is_client():
		net_client = NetClient.new()
		net_client.name = "NetClient"
		net_client.world = self
		add_child(net_client)
	elif Net.is_host():
		start_hosting()
	finished_loading.emit()

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
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	add_child(moon)
	winch_reticle = WinchReticle.new()
	winch_reticle.name = "WinchReticle"
	add_child(winch_reticle)

	var env_node := WorldEnvironment.new()
	environment = Environment.new()
	var env := environment
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	var sky := ProceduralSkyMaterial.new()
	_sky = sky
	sky.sky_top_color = Color(0.16, 0.42, 0.86)
	sky.sky_horizon_color = Color(0.62, 0.80, 0.95)
	sky.sky_curve = 0.12
	# Below the horizon the sky is the haze, so past the far plane there is
	# only haze.
	sky.ground_bottom_color = Color(0.62, 0.78, 0.92)
	sky.ground_horizon_color = Color(0.62, 0.78, 0.92)
	sky.sun_angle_max = 24.0
	sky.sun_curve = 0.08
	env.sky.sky_material = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = OUTDOOR_AMBIENT
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Bright and punchy: a plain response keeps the colours as painted (filmic
	# greyed them), with a little headroom so snow does not clip.
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 0.92
	env.tonemap_white = 1.0
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.06
	# Haze the colour of the horizon, so distance reads as air rather than grey.
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.78, 0.92)
	env.fog_sun_scatter = 0.18
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_curve = 1.6
	env.fog_density = 1.0
	env.fog_aerial_perspective = 0.15
	env.fog_sky_affect = 0.0
	env_node.environment = env
	add_child(env_node)

## The ring road round home: an ellipse about the plot and the yard.
const RING_CENTRE := Vector2(0, 15)
const RING_RADII := Vector2(88, 105)
const RING_POINTS := 72

static func ring_point(angle: float) -> Vector3:
	return Vector3(RING_CENTRE.x + RING_RADII.x * cos(angle), 0, RING_CENTRE.y + RING_RADII.y * sin(angle))

## Waypoints for a road leaving the ring at `angle`: straight out, square to
## the ring, before it is routed on to `onward`.
## The haul road into the quarry: from the rim on the south side, twice round
## the pit's wall to its floor - the same line the pit's benches are cut along.
static func quarry_haul_road() -> Array:
	var f := quarry_feature()
	var road := 14.0
	var turns := 2.0
	var span := QUARRY_RADIUS - QUARRY_FLOOR_RADIUS - road
	var out: Array = [quarry_gate()]
	var steps := 96
	for i in steps + 1:
		var sv := float(i) / float(steps)
		var a := PI * 0.5 + TAU * turns * sv
		var r := QUARRY_RADIUS - road * 0.5 - span * sv
		var p := Terrain.from_pit_space(f, Vector2(cos(a) * r, sin(a) * r))
		out.append(Vector3(p.x, 0, p.y))
	return out

## Where the lane in meets the quarry's rim: just outside it, on the road side.
static func quarry_gate() -> Vector3:
	var p := Terrain.from_pit_space(quarry_feature(), Vector2(0, QUARRY_RADIUS + 14.0))
	return Vector3(p.x, 0, p.y)

## The quarry's pit as the terrain carves it.
static func quarry_feature() -> Dictionary:
	return {"name": "Quarry", "kind": "pit", "centre": Vector2(QUARRY_CENTRE.x, QUARRY_CENTRE.z), "radius": QUARRY_RADIUS,
		"rim": 30.0, "floor": 4.0, "inner": QUARRY_FLOOR_RADIUS, "road": 14.0, "turns": 2.0, "entry": PI * 0.5,
		"stretch": QUARRY_STRETCH, "angle": QUARRY_ANGLE}

static func _arterial(angle: float, onward: Array) -> Array:
	var at := ring_point(angle)
	var normal := Vector2(cos(angle) / RING_RADII.x, sin(angle) / RING_RADII.y).normalized()
	var out: Array = [at, at + Vector3(normal.x, 0, normal.y) * 60.0]
	out.append_array(onward)
	return out

## Spec: a large, simple, polygonal map with several biomes, rivers to ford or
## bridge, and roads that are quicker to drive. The build sites are levelled out
## of it first, so a factory floor is never on a slope.
func _build_terrain() -> void:
	if WorldMap.is_ostars():
		await _build_ostars_terrain()
		return
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
	# Roads. Round home a ring road, with the drive up from the plot and the
	# yard meeting it square on; the rest leave the ring square on too, as
	# waypoints routed over the land, so they wind round hills, switch back
	# up the mountains, and take water where the crossing is short.
	var ring: Array = []
	for i in RING_POINTS + 1:
		ring.append(ring_point(TAU * float(i % RING_POINTS) / float(RING_POINTS)))
	terrain.roads = [
		ring,
		# The quarry's haul road, spiralling down the pit wall to the floor,
		# and the lane in to its top, branching off the north road (below)
		# wherever that runs nearest.
		quarry_haul_road(),
		{"branch_of": 5, "route": [Vector3.ZERO, quarry_gate() + Vector3(50, 0, 0), quarry_gate()]},
		[Vector3(0, 0, 50), Vector3(0, 0, 86), ring_point(PI * 0.5)],
		# East, past the store, to the far coast.
		{"bridge": true, "route": _arterial(0.0, [Vector3(260, 0, 15), Vector3(1000, 0, 180),
			Vector3(1850, 0, 120)])},
		# North, past the quarry, up into the high country.
		{"bridge": true, "route": _arterial(-PI * 0.5, [Vector3(0, 0, -240), Vector3(-140, 0, -330), Vector3(-150, 0, -470),
			Vector3(-60, 0, -1150), Vector3(0, 0, -1850)])},
		# West.
		{"bridge": true, "route": _arterial(PI, [Vector3(-500, 0, 60), Vector3(-1150, 0, 160),
			Vector3(-1850, 0, 220)])},
		# South-west from the desert, over the stepping stone to Hollow Isle and
		# in through the gorge to the Hidden Valley.
		{"bridge": true, "route": [Vector3(-640, 0, 680), Vector3(-900, 0, 900), Vector3(-1060, 0, 1060),
			Vector3(-1250, 0, 1250), Vector3(-1395, 0, 1405), Vector3(-1445, 0, 1455)]},
		# South-east, a gravel track with fords.
		{"ford": true, "style": "gravel", "route": _arterial(PI * 0.25, [Vector3(500, 0, 520),
			Vector3(1150, 0, 1150)])},
		# Into the desert, and up into the Spine Mountains.
		{"bridge": true, "route": _arterial(PI * 0.6, [Vector3(-150, 0, 330), Vector3(-640, 0, 680)])},
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
		# Its gorge faces home, wide enough for a truck and a trailer, and the
		# road runs in through it.
		{"name": HIDDEN_VALLEY, "kind": "valley", "centre": Vector2(-1470, 1480), "radius": 55.0,
			"gap": -PI * 0.25, "floor": 12.0, "gorge": 16.0, "ridge": 28.0},
		{"name": STAR_CRATER, "kind": "crater", "centre": Vector2(1160, 1170), "radius": 48.0,
			"rim": 30.0, "floor": 8.0},
		# The quarry: an open pit a good 26 m deep, a haul road spiralling
		# twice round its wall from the rim on the road side down to the floor.
		quarry_feature(),
	]
	# Everything that has to stand on the level, and all of it above the water
	# line so a levelled site is never under the sheet.
	terrain.reserve_site(Vector3(0, PLOT_GROUND, 0), 56.0)
	# The plot at its biggest, and a margin: flat under the pad all the way to
	# its corners, and no road across it.
	terrain.reserve_clear_square(Vector3(0, PLOT_GROUND, 0), 50.0, PLOT_GROUND, 10.0)
	# Levelled to the lie of the land round them (NAN), and each with a short
	# drive in from the road to its way in.
	terrain.reserve_site(Vector3(DEPOT_POSITION.x, NAN, DEPOT_POSITION.z), 14.0)
	terrain.reserve_site(Vector3(STORE_POSITION.x, NAN, STORE_POSITION.z), 20.0)
	terrain.reserve_site(Vector3(DEALER_POSITION.x, NAN, DEALER_POSITION.z), 17.0)
	terrain.reserve_site(Vector3(WORKS_POSITION.x, NAN, WORKS_POSITION.z), 17.0)
	terrain.driveways = [
		{"name": "Sell Yard", "centre": DEPOT_POSITION, "radius": 14.0,
			"door": DEPOT_POSITION + Vector3(-8.0, 0, 0)},
		{"name": "Store", "centre": STORE_POSITION, "radius": 20.0,
			"door": STORE_POSITION + Vector3(0, 0, -13.0)},
		{"name": "Vehicle Dealer", "centre": DEALER_POSITION, "radius": 17.0,
			"door": DEALER_POSITION + Vector3(0, 0, -11.0)},
		{"name": "Machine Works", "centre": WORKS_POSITION, "radius": 17.0,
			"door": WORKS_POSITION + Vector3(0, 0, -11.0)},
	]
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
	if staged_load:
		terrain.loading_hook = _detail
	add_child(terrain)
	# Behind the boot screen the land builds a step a frame: wait for it.
	if not terrain.generated:
		await terrain.finished_generating
	await _detail("Walling the edge of the map and building %d bridges" % terrain.bridges.size())
	_build_map_edge()
	_build_bridges()
	await _detail("Standing up the landmarks: spires, arches and lookouts")
	landmarks = Landmarks.new()
	landmarks.name = "Landmarks"
	landmarks.setup(terrain, 911)
	add_child(landmarks)
	await _detail("Laying %d roads' surfaces, kerbs and markings" % terrain.road_paths.size())
	var roads := RoadSurface.new()
	roads.name = "RoadSurface"
	roads.setup(terrain)
	add_child(roads)

## A wall at the map edge, so nothing drives off the world.
func _build_map_edge() -> void:
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

## Ostars: the continent as drawn (see Ostars), with the plot levelled at
## home in the middle, roads out to its places (see ostars_roads), rock
## outcrops, the rivers, and the lava in Orodruin's crater.
var ostars: Ostars

func _build_ostars_terrain() -> void:
	terrain = Terrain.new()
	terrain.name = "Terrain"
	terrain.half_extent = MAP_HALF
	terrain.noise_seed = 20260929
	ostars = Ostars.new()
	ostars.configure(terrain)
	terrain.reserve_site(Vector3(0, PLOT_GROUND, 0), 56.0)
	terrain.reserve_clear_square(Vector3(0, PLOT_GROUND, 0), 50.0, PLOT_GROUND, 10.0)
	# The shops and the traders' yards, each levelled to the lie of its land.
	for key in Ostars.SITES:
		terrain.reserve_site(_ostars_site_centre(key), float(Ostars.SITES[key][2]))
	terrain.roads = ostars_roads()
	terrain.cave_count = 12
	for zone in Ostars.CAVE_ZONES:
		terrain.cave_zones.append({"centre": zone.centre, "radius": zone.radius * 0.92, "count": zone.mouths})
	terrain.cache_path = "user://terrain_cache_ostars.bin"
	if staged_load:
		terrain.loading_hook = _detail
	add_child(terrain)
	if not terrain.generated:
		await terrain.finished_generating
	await _detail("Walling the edge of the map and building %d bridges" % terrain.bridges.size())
	_build_map_edge()
	_build_bridges()
	await _detail("Laying %d roads' surfaces, kerbs and markings" % terrain.road_paths.size())
	var surface := RoadSurface.new()
	surface.name = "RoadSurface"
	surface.setup(terrain)
	add_child(surface)
	await _detail("Standing up the rock outcrops")
	landmarks = Landmarks.new()
	landmarks.name = "Landmarks"
	landmarks.setup(terrain, 929)
	add_child(landmarks)
	await _detail("Filling Mt. Orodruin with lava")
	_build_volcano()

## Ostars' roads: the drive from the plot down to the main street, which runs
## past the town (the hardware store, the dealer, the works) west to Old
## Bjorn's yard and east out of town; from there north up through the
## foothills to Dusty's and on over the pass to Summit Outfitters; and west
## from Bjorn's to the sea at Granny Opal's. The long ones are routed over the
## land (round the hills, switching back up the slopes, bridging the rivers);
## each ends on the side of its yard that faces home, where the way in is.
static func ostars_roads() -> Array:
	var lumber := _ostars_gate("lumber", 27.0)
	var metal := _ostars_gate("metal", 27.0)
	var gems := _ostars_gate("gems", 27.0)
	var summit := _ostars_gate("summit", 18.0)
	# South of the town, clear of the dealer's and the works' yards.
	var main := [lumber, Vector3(-120, 0, 140), Vector3(-30, 0, 138), Vector3(80, 0, 138), Vector3(185, 0, 138),
		Vector3(300, 0, 132), Vector3(420, 0, 110)]
	return [
		# The plot's drive, square onto the main street.
		[Vector3(0, 0, 52), Vector3(0, 0, 138)],
		{"bridge": true, "route": main},
		# Up between the dealer and the works to the hardware store.
		[Vector3(185, 0, 138), Vector3(185, 0, 80)],
		# North to Dusty's, and on to Summit Outfitters.
		{"bridge": true, "branch_of": 1, "route": [Vector3(420, 0, 110), Vector3(460, 0, -150),
			Vector3(360, 0, -480), metal]},
		{"bridge": true, "route": [metal, Vector3(420, 0, -1000), Vector3(560, 0, -1300), summit]},
		# West to the coast.
		{"bridge": true, "route": [lumber, Vector3(-560, 0, 260), Vector3(-950, 0, 400), gems]},
	]

## Where a road meets one of Ostars' places: just outside its levelled
## ground, on the side facing home.
static func _ostars_gate(key: String, radius: float) -> Vector3:
	var at: Array = Ostars.SITES[key]
	var c := Vector2(float(at[0]), float(at[1]))
	var home := -c.normalized()
	var p := c + home * (radius + 7.0)
	return Vector3(p.x, 0, p.y)

## The lava lake in Orodruin's crater, glowing, and smoke going up off it.
func _build_volcano() -> void:
	var node := Node3D.new()
	node.name = "Orodruin"
	var c: Vector2 = Ostars.VOLCANO.centre
	node.position = Vector3(c.x, Ostars.lava_level(), c.y)
	add_child(node)
	var lava := MeshInstance3D.new()
	lava.name = "Lava"
	var disc := CylinderMesh.new()
	var r := float(Ostars.VOLCANO.crater) * 0.78
	disc.top_radius = r
	disc.bottom_radius = r
	disc.height = 1.0
	disc.radial_segments = 20
	lava.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.36, 0.06)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.42, 0.08)
	mat.emission_energy_multiplier = 2.6
	mat.roughness = 0.9
	lava.material_override = mat
	lava.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(lava)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.45, 0.15)
	glow.light_energy = 4.0
	glow.omni_range = 110.0
	glow.position = Vector3(0, 12, 0)
	node.add_child(glow)
	var smoke := Blast._burst(Color(0.32, 0.30, 0.30), false, 40, 5.0, 14.0, 9.0)
	smoke.one_shot = false
	smoke.explosiveness = 0.0
	smoke.spread = 25.0
	smoke.gravity = Vector3(0.6, 2.2, 0.3)
	smoke.damping_min = 0.2
	smoke.damping_max = 0.5
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = r * 0.6
	smoke.visibility_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 400, 400))
	node.add_child(smoke)

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
	if WorldMap.is_ostars():
		await _build_ostars_forest()
		return
	var species := SPECIES
	# Quotas follow how much country each species actually has, so a seed that
	# happens to grow little swamp gets few willows rather than an empty field
	# grinding away at a region that is not there.
	var pools: Array[PackedVector3Array] = []
	var total := 0
	var step := 2 if MAP_HALF <= 400.0 else 3
	await _detail("Finding the right country for %d kinds of tree" % species.size())
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
		await _detail("Growing %d %s trees in their groves (%d of %d kinds)" % [quota, String(kind.name).to_lower(), i + 1, species.size()])
		var field := _tree_field(kind, quota)
		# Each species grows in groves of its own, with a few strays between.
		var sampler := _from_pool(pool) if kind.has("site") else _grove_sampler(kind, pool, _groves(pool, String(kind.name)))
		field.setup([kind], _build_tree, sampler, _rng.randi())
		add_child(field)
		field.prefill()
		tree_fields.append(field)
	await _detail("Planting the wood by your plot")
	_build_starter_forest(species)

## Ostars' forests: grown by the Forester (stands, glades, river banks, the
## treeline) into spots for each kind of tree; each kind gets a field that
## keeps most of its spots stood and regrows on the rest.
var forester: Forester
## Of a kind's spots, the share stood at once; the rest are where it regrows.
const OSTARS_STOOD := 0.85

func _build_ostars_forest() -> void:
	await _detail("Working out how wooded Ostars is, region by region, and where the stands are")
	forester = Forester.new(terrain, ostars, SPECIES)
	var target := int(Balance.num("world.ostars_tree_count", 20000.0) / OSTARS_STOOD)
	var out := [0]
	await Workers.one(func(): out[0] = forester.grow(target), "forester", _loading_tree())
	var grown: int = out[0]
	_lap("forester")
	var census := forester.census()
	await _detail("Grew %d trees of %d kinds in %d stands" % [grown, census.size(), forester.stands.size()])
	for pair in census:
		var name: String = pair[0]
		var pool: PackedVector3Array = forester.spots[name]
		var kind: Dictionary = forester.kinds[name]
		var field := _tree_field(kind, maxi(1, int(ceil(float(pool.size()) * OSTARS_STOOD))))
		field.setup([kind], _build_tree, _from_spots(pool), _rng.randi())
		add_child(field)
		field.prefill()
		tree_fields.append(field)
	if forester.home_wood == Vector3.INF or forester.home_spots.is_empty():
		return
	await _detail("Planting the wood by your plot")
	starter_forest = forester.home_wood
	var kinds: Array = [forester.kinds["Pine"], forester.kinds["Birch"], forester.kinds["Oak"]]
	var home := ResourceField.new()
	home.name = "Forest_Starter"
	home.quota = forester.home_spots.size()
	home.min_spacing = 3.4
	home.refill_seconds = 20.0
	home.wake_distance = TREE_WAKE
	home.impostor = _tree_impostor(kinds[0])
	home.impostor_height = (float(kinds[0].height[0]) + float(kinds[0].height[1])) * 0.5
	home.setup(kinds, _build_tree, _from_spots(forester.home_spots), 4242)
	add_child(home)
	home.prefill()
	tree_fields.append(home)

## Draws one of a set of spots already vetted for a tree, nudged no more than
## a stride so the stands keep their shape.
func _from_spots(points: PackedVector3Array) -> Callable:
	return func(rng: RandomNumberGenerator) -> Vector3:
		var spot := points[rng.randi() % points.size()]
		var nudged := Vector3(spot.x + rng.randf_range(-0.8, 0.8), 0.0, spot.z + rng.randf_range(-0.8, 0.8))
		if terrain.water_depth(nudged.x, nudged.z) > terrain.water_depth(spot.x, spot.z) + 0.05 \
				or terrain.is_blocked(nudged.x, nudged.z):
			return terrain.place(spot)
		return terrain.place(nudged)

## A field for one species' trees, set up the way every forest's is.
func _tree_field(kind: Dictionary, quota: int) -> ResourceField:
	var field := ResourceField.new()
	field.name = "Forest_%s" % String(kind.name).replace(" ", "_").replace("'", "")
	field.quota = quota
	field.min_spacing = 3.3
	field.refill_seconds = 6.0
	field.churn_seconds = 30.0
	field.wake_distance = TREE_WAKE
	field.impostor = _tree_impostor(kind)
	field.impostor_height = (float(kind.height[0]) + float(kind.height[1])) * 0.5
	return field

## Every kind of tree on the islands. Ostars grows these and a few of its own
## (Forester.OWN_SPECIES).
const SPECIES := [
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
			"foliage": 9.5, "crown": [8.5, 0.30], "style": &"canopy"},

		{"name": "Willow", "item": &"wood_willow",
			"biomes": [Terrain.Biome.SWAMP],
			"leaf": Color(0.38, 0.47, 0.22), "work": 880.0,
			"radius": [0.34, 0.46], "height": [4.5, 6.5], "taper": 0.70, "branches": [7, 9],
			# Drooping: branches thrown almost flat and long with it.
			"start": 0.52, "pitch": [1.05, 1.45], "length": [0.34, 0.52],
			"foliage": 8.0, "crown": [6.0, 0.26], "style": &"canopy",
			# Standing in the water, which is where a willow belongs.
			"wet": 0.7},

		{"name": "Ironwood", "near": 700.0, "item": &"wood_ironwood",
			"biomes": [Terrain.Biome.MOUNTAIN],
			"leaf": Color(0.18, 0.30, 0.20), "work": 1900.0,
			"radius": [0.46, 0.60], "height": [5.0, 7.0], "taper": 0.82, "branches": [4, 6],
			# Squat and thick, holding on to a mountainside.
			"start": 0.48, "pitch": [0.70, 1.10], "length": [0.20, 0.32],
			"foliage": 6.0, "crown": [4.6, 0.28], "style": &"canopy"},

		{"name": "Desert Ironwood", "near": 700.0, "item": &"wood_ironwood",
			"biomes": [Terrain.Biome.DESERT],
			"leaf": Color(0.42, 0.46, 0.28), "work": 1750.0,
			"radius": [0.38, 0.50], "height": [3.8, 5.4], "taper": 0.80, "branches": [5, 7],
			# Low, wide and sparse, the way things grow with no water.
			"start": 0.40, "pitch": [0.95, 1.35], "length": [0.26, 0.40],
			"foliage": 5.0, "crown": [0.0, 0.0], "style": &"canopy"},

		# --- The rest of the forest: every one a tree you would know on sight.

		{"name": "Birch", "item": &"wood_birch",
			"biomes": [Terrain.Biome.WOODLAND, Terrain.Biome.TAIGA],
			"leaf": Color(0.55, 0.68, 0.25), "bark": Color(0.90, 0.89, 0.84), "work": 520.0,
			"radius": [0.18, 0.26], "height": [7.0, 10.0], "taper": 0.6, "branches": [5, 7],
			# Slim white trunk, a light rounded head of small leaves.
			"start": 0.55, "pitch": [0.35, 0.75], "length": [0.14, 0.22],
			"foliage": 7.0, "crown": [7.0, 0.28], "style": &"ball", "marks": true},

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

		# Only in the Hidden Valley on Hollow Isle: walled in by a ridge, one
		# gorge in. The best timber on the map.
		{"name": "Mahogany", "item": &"wood_mahogany", "site": HIDDEN_VALLEY,
			"biomes": [Terrain.Biome.WOODLAND],
			"leaf": Color(0.16, 0.36, 0.14), "bark": Color(0.42, 0.20, 0.13), "work": 1600.0,
			"radius": [0.5, 0.66], "height": [9.0, 12.0], "taper": 0.7, "branches": [6, 8],
			# Tall, straight and buttressed, with a broad dark canopy on top.
			"start": 0.6, "pitch": [0.8, 1.15], "length": [0.2, 0.3],
			"foliage": 9.0, "crown": [8.0, 0.24], "style": &"canopy", "quota": 16},

		# Ebony: a knee-high sapling of a tree, a handful scattered wide over
		# the far country. The dearest wood if you can find it.
		{"name": "Ebony", "near": 1500.0, "item": &"wood_ebony", "quota": 12,
			"biomes": [Terrain.Biome.WOODLAND, Terrain.Biome.SWAMP, Terrain.Biome.MOUNTAIN],
			"leaf": Color(0.10, 0.22, 0.10), "bark": Color(0.10, 0.08, 0.07), "work": 2000.0,
			"radius": [0.12, 0.17], "height": [2.2, 3.2], "taper": 0.75, "branches": [2, 4],
			"start": 0.55, "pitch": [0.7, 1.1], "length": [0.12, 0.2],
			"foliage": 3.0, "crown": [2.0, 0.3], "style": &"ball"},

		{"name": "Dead Snag", "item": &"wood_pine",
			"biomes": [Terrain.Biome.MOUNTAIN, Terrain.Biome.DESERT, Terrain.Biome.SWAMP],
			"leaf": Color(0.4, 0.4, 0.4), "bark": Color(0.52, 0.49, 0.45), "work": 400.0,
			"radius": [0.22, 0.32], "height": [4.0, 6.5], "taper": 0.5, "branches": [2, 4],
			# Grey, bare and broken: cheap wood, but it breaks up the skyline.
			"start": 0.5, "pitch": [0.5, 1.1], "length": [0.12, 0.2],
			"foliage": 0.0, "crown": [0.0, 0.0], "style": &"bare", "weight": 0.3},
]

## How big a grove is, and what share of a species' trees stand in one rather
## than scattered on their own.
static var GROVE_RADIUS: float = Balance.num("world.grove_radius", 55.0)
static var GROVE_SHARE: float = Balance.num("world.grove_share", 0.93)
## Roughly one grove for this many of a species' vetted spots: fewer, bigger
## woods rather than a thin sprinkle.
const GROVE_SPOTS := 48

## Where a species' groves stand: spots picked from its own country, kept
## apart from each other. The same seed gives the same woods.
func _groves(pool: PackedVector3Array, species_name: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	if pool.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("groves:" + species_name)
	var want := clampi(pool.size() / GROVE_SPOTS, 1, 48)
	var apart := GROVE_RADIUS * 2.6
	for attempt in want * 12:
		if out.size() >= want:
			break
		var p := pool[rng.randi() % pool.size()]
		var ok := true
		for q in out:
			if Vector2(p.x - q.x, p.z - q.z).length() < apart:
				ok = false
				break
		if ok:
			out.append(p)
	return out

## Draws a spot for a tree: most of the time somewhere in one of its groves,
## denser toward the middle; now and then a stray anywhere in its country. A
## spot that lands somewhere the species cannot stand falls back to a vetted one.
func _grove_sampler(kind: Dictionary, pool: PackedVector3Array, groves: PackedVector3Array) -> Callable:
	var scatter := _from_pool(pool)
	var biomes: Array = kind.biomes
	var wet := float(kind.get("wet", 0.0))
	return func(rng: RandomNumberGenerator) -> Vector3:
		if groves.is_empty() or rng.randf() > GROVE_SHARE:
			return scatter.call(rng)
		var centre := groves[rng.randi() % groves.size()]
		for attempt in 6:
			var a := rng.randf() * TAU
			var r := GROVE_RADIUS * pow(rng.randf(), 0.7)
			var x := centre.x + cos(a) * r
			var z := centre.z + sin(a) * r
			if _tree_can_stand(x, z, biomes, wet):
				return terrain.place(Vector3(x, 0.0, z))
		return scatter.call(rng)

func _tree_can_stand(x: float, z: float, biomes: Array, wet: float) -> bool:
	if not biomes.has(int(terrain.biome_at(x, z))):
		return false
	if terrain.water_depth(x, z) > wet or terrain.is_road(x, z) or terrain.in_cave_zone(x, z) \
			or terrain.is_blocked(x, z) or terrain._in_build_site(x, z) or terrain.in_clear_zone(x, z, 8.0):
		return false
	# Not on a crag.
	var h := terrain.height_at(x, z)
	return absf(terrain.height_at(x + 2.0, z) - h) < 2.2 and absf(terrain.height_at(x, z + 2.0) - h) < 2.2

## A wood of cheap, easy trees a short walk from the plot, so the first tree
## is not a trek: pine, birch and a few oaks in the nearest patch of woodland.
const STARTER_NEAR := 75.0
const STARTER_FAR := 190.0
const STARTER_RADIUS := 38.0
var starter_forest: Vector3 = Vector3.INF

func _build_starter_forest(species: Array) -> void:
	var kinds: Array = []
	for kind in species:
		if kind.name in ["Pine", "Birch", "Oak"]:
			kinds.append(kind)
	if kinds.is_empty():
		return
	var land := terrain.points_in_biomes([Terrain.Biome.WOODLAND, Terrain.Biome.TAIGA], 2)
	var near := PackedVector3Array()
	for p in land:
		var d := Vector2(p.x, p.z).length()
		if d >= STARTER_NEAR and d <= STARTER_FAR:
			near.append(p)
	if near.is_empty():
		return
	# The densest patch: the spot with the most good ground round it, the
	# nearer home the better.
	var best := near[0]
	var best_score := -INF
	for p in near:
		var n := 0
		for q in near:
			if Vector2(p.x - q.x, p.z - q.z).length() <= STARTER_RADIUS:
				n += 1
		var score := float(n) - Vector2(p.x, p.z).length() * 0.02
		if score > best_score:
			best_score = score
			best = p
	starter_forest = best
	var biomes := [Terrain.Biome.WOODLAND, Terrain.Biome.TAIGA]
	var patch := PackedVector3Array()
	for q in near:
		if Vector2(best.x - q.x, best.z - q.z).length() <= STARTER_RADIUS:
			patch.append(q)
	var scatter := _from_pool(patch)
	var sampler := func(rng: RandomNumberGenerator) -> Vector3:
		for attempt in 8:
			var a := rng.randf() * TAU
			var r := STARTER_RADIUS * sqrt(rng.randf())
			var x := best.x + cos(a) * r
			var z := best.z + sin(a) * r
			if _tree_can_stand(x, z, biomes, 0.0):
				return terrain.place(Vector3(x, 0.0, z))
		return scatter.call(rng)
	var field := ResourceField.new()
	field.name = "Forest_Starter"
	field.quota = int(Balance.num("world.starter_forest_trees", 70.0))
	field.min_spacing = 3.4
	field.refill_seconds = 20.0
	field.churn_seconds = 0.0
	field.wake_distance = TREE_WAKE
	field.impostor = _tree_impostor(kinds[0])
	field.impostor_height = (float(kinds[0].height[0]) + float(kinds[0].height[1])) * 0.5
	field.setup(kinds, _build_tree, sampler, 4242)
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
		if terrain.water_depth(flat.x, flat.z) > 0.0 or terrain.is_road(flat.x, flat.z) or terrain.is_blocked(flat.x, flat.z):
			# Nudged rather than rejected, so a field near a river still fills.
			flat += Vector3(rng.randf_range(-18.0, 18.0), 0.0, rng.randf_range(-18.0, 18.0))
		return terrain.place(flat)

## Real trees stand within this many metres of a player; further off they are
## drawn as stand-ins (see ResourceField.impostor).
static var TREE_WAKE: float = Balance.num("world.tree_wake_distance", 230.0)

## A species' stand-in for the far distance (see ChoppableTree.stand_in).
static func _tree_impostor(kind: Dictionary) -> Mesh:
	return ChoppableTree.stand_in(kind)

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
	tree.work_per_m2 = float(kind.work) * Balance.num("cutting.chop_work_multiplier", 1.0)
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
	tree.bark_marks = bool(kind.get("marks", false))
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
	{"item": &"gem_turquoise", "biomes": [Terrain.Biome.DESERT, Terrain.Biome.MOUNTAIN],
		"quota": 10, "volume": [0.15, 0.7], "embed": [0.50, 0.70], "near": 1575.0},
	# Building stone: plenty of it, each in its own country. Sandstone is the
	# one that goes further, into glass.
	{"item": &"stone_limestone", "biomes": [Terrain.Biome.WOODLAND],
		"quota": 40, "volume": [0.4, 2.0], "embed": [0.2, 0.5]},
	{"item": &"stone_sandstone", "biomes": [Terrain.Biome.DESERT],
		"quota": 44, "volume": [0.4, 2.0], "embed": [0.2, 0.5]},
	{"item": &"stone_slate", "biomes": [Terrain.Biome.TAIGA, Terrain.Biome.SWAMP],
		"quota": 32, "volume": [0.4, 2.0], "embed": [0.25, 0.55]},
	{"item": &"stone_granite", "biomes": [Terrain.Biome.MOUNTAIN],
		"quota": 32, "volume": [0.4, 2.0], "embed": [0.25, 0.55], "near": 300.0},
	{"item": &"stone_basalt", "biomes": [Terrain.Biome.DESERT, Terrain.Biome.MOUNTAIN],
		"quota": 24, "volume": [0.4, 2.0], "embed": [0.25, 0.55], "near": 900.0},
	{"item": &"stone_marble", "biomes": [Terrain.Biome.SNOW],
		"quota": 20, "volume": [0.4, 2.0], "embed": [0.3, 0.6]},
	# Lapis is rare, and could be anywhere at all.
	{"item": &"gem_lapis", "biomes": [Terrain.Biome.WOODLAND, Terrain.Biome.SWAMP, Terrain.Biome.DESERT,
		Terrain.Biome.MOUNTAIN, Terrain.Biome.TAIGA, Terrain.Biome.SNOW],
		"quota": 5, "volume": [0.15, 0.6], "embed": [0.55, 0.75]},
]

## Underground, by how far out the cave is: the nearest are worked-over seams of
## the common stuff, the farthest holds what the surface does not have at all.
const CAVE_TIERS := [
	[&"ore_copper", &"ore_iron", &"ore_tin", &"ore_zinc", &"gem_quartz", &"gem_amethyst"],
	[&"ore_silver", &"ore_magnetite", &"ore_nickel", &"gem_jade", &"ore_cobalt", &"ore_gold"],
	[&"ore_gold", &"gem_emerald", &"gem_ruby", &"ore_platinum", &"ore_tungsten", &"ore_sunstone",
		&"gem_turquoise"],
]
## The farthest cave of all: diamonds, and nowhere else.
const DEEPEST_CAVE := [&"ore_platinum", &"ore_starmetal", &"gem_sapphire", &"ore_platinum", &"gem_sapphire"]

## The quarry works the same way: a patch per ore, stocked to a quota.
func _build_quarry() -> void:
	# Chunk sizes straddle the player's pull: the small end of iron comes out of
	# the ground whole, the big end has to be cracked up first.
	var ores := [
		{"item": &"ore_iron", "volume": [0.35, 2.6], "embed": [0.30, 0.55]},
		{"item": &"ore_copper", "volume": [0.30, 2.2], "embed": [0.35, 0.60]},
		{"item": &"ore_tin", "volume": [0.35, 2.4], "embed": [0.30, 0.55]},
		{"item": &"gem_quartz", "volume": [0.25, 1.4], "embed": [0.35, 0.60]},
		{"item": &"stone_granite", "volume": [0.4, 2.0], "embed": [0.25, 0.50]},
		{"item": &"ore_gold", "volume": [0.20, 1.4], "embed": [0.45, 0.70]},
	]
	var per_ore: int = maxi(1, rock_count / ores.size())
	if WorldMap.is_ostars():
		ores = []
	else:
		await _detail("Stocking the quarry with %d kinds of ore, bedded in the pit floor" % ores.size())
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
			_on_ground(ResourceField.rect(QUARRY_CENTRE, Vector2(30.0, 30.0))), _rng.randi())
		add_child(field)
		field.prefill()
		rock_fields.append(field)

	var step := 3 if MAP_HALF <= 400.0 else 4
	if WorldMap.is_ostars():
		await _build_ostars_ore(step)
		return
	for kind in WILD_ORE:
		var biomes: Array = kind.biomes.duplicate()
		# Ostars' volcano is mountain country for what turns up in it.
		if WorldMap.is_ostars() and biomes.has(Terrain.Biome.MOUNTAIN):
			biomes.append(Terrain.Biome.ASH)
		var pool := _banded(terrain.points_in_biomes(biomes, step),
			float(kind.get("near", 0.0)), float(kind.get("far", INF)))
		if pool.is_empty():
			continue
		await _detail("Scattering %d %s out in the wild" % [int(kind.quota), GameData.item_name(kind.item).to_lower()])
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
	# Black opal: a rare stone lying about on the surface of the starmetal
	# island, nowhere else.
	var isle: Dictionary = ISLANDS[4]
	var opal_pool := PackedVector3Array()
	for p in terrain.points_in_biomes([0, 1, 2, 3, 4, 5], 4):
		if Vector2(p.x, p.z).distance_to(isle.centre) < float(isle.radius) * 0.85 and not terrain.is_road(p.x, p.z):
			opal_pool.append(p)
	if not opal_pool.is_empty():
		var opal := ResourceField.new()
		opal.name = "Isle_BlackOpal"
		opal.quota = 3
		opal.min_spacing = 30.0
		opal.refill_seconds = 240.0
		# There is always at least one to find.
		opal.min_present = 1
		opal.setup([{"item": &"gem_black_opal", "volume": [0.1, 0.5], "embed": [0.5, 0.75]}],
			_build_rock, _from_pool(opal_pool), _rng.randi())
		add_child(opal)
		opal.prefill()
		rock_fields.append(opal)

## Ostars' ore and gems, placed by the Prospector: each in its own country,
## the better ones in the harder country - higher, steeper, further out.
func _build_ostars_ore(step: int) -> void:
	await _detail("Prospecting Ostars: ore and gems by how hard the country is")
	var sizes := {}
	for kind in WILD_ORE:
		sizes[kind.item] = kind
	var prospector := Prospector.new(terrain, ostars)
	var found: Array = []
	await Workers.one(func(): found.append_array(prospector.survey(step)), "prospector", _loading_tree())
	_lap("prospect")
	for entry in found:
		var id: StringName = entry[0]
		var spots: PackedVector3Array = entry[1]
		var weights: PackedFloat32Array = entry[2]
		if spots.is_empty():
			continue
		var like: Dictionary = sizes.get(id, {"volume": [0.25, 1.4], "embed": [0.4, 0.65]})
		var field := ResourceField.new()
		field.name = "Wild_%s" % id
		field.quota = int(entry[3])
		field.min_spacing = 14.0
		field.refill_seconds = 20.0
		field.churn_seconds = 60.0
		field.wake_distance = 320.0
		field.setup([{"item": id, "volume": like.volume, "embed": like.embed}], _build_rock,
			Prospector.weighted(spots, weights, terrain), _rng.randi())
		add_child(field)
		field.prefill()
		rock_fields.append(field)

## The traders' places on Ostars (and on nothing else, yet).
var trade_posts: Array[TradePost] = []

## Where a place on Ostars is levelled round: a trader's whole footprint, or a
## shop's lot. Its height is left to the lie of the land (NAN).
func _ostars_site_centre(key: String) -> Vector3:
	var at: Array = Ostars.SITES[key]
	var c := Vector3(float(at[0]), NAN, float(at[1]))
	if key in ["lumber", "metal", "gems"]:
		var off := Basis(Vector3.UP, Ostars.facing(c.x, c.z)) * TradePost.FOOTPRINT_CENTRE
		c.x += off.x
		c.z += off.z
	return c

## Ostars' shops and traders: the town by home, Summit Outfitters on the
## tundra, and Old Bjorn's, Dusty's and Granny Opal's. Bjorn's yard is the
## one the checklist and the compass call the sell yard.
func _build_ostars_places() -> void:
	store = _ostars_shop("Store", &"general", "store")
	dealer_store = _ostars_shop("Dealer", &"dealer", "dealer")
	works_store = _ostars_shop("Works", &"works", "works")
	summit_store = _ostars_shop("SummitStore", &"summit", "summit")
	var pine: Dictionary = {}
	for kind in SPECIES:
		if kind.name == "Pine":
			pine = kind
	for pair in [["lumber", TradePost.Kind.LUMBER], ["metal", TradePost.Kind.METAL], ["gems", TradePost.Kind.GEMS]]:
		var at: Array = Ostars.SITES[pair[0]]
		var tp := TradePost.new()
		tp.setup(pair[1], manager, quests)
		tp.ground = func(x: float, z: float) -> float: return terrain.height_at(x, z)
		tp.watch = func(): return player
		tp.vehicles = func(): return vehicles()
		if pair[1] == TradePost.Kind.LUMBER and not pine.is_empty():
			tp.tree_builder = func(form_seed: int) -> Node3D: return _build_tree(pine, form_seed)
		tp.position = terrain.place(Vector3(float(at[0]), 0.0, float(at[1])))
		tp.rotation.y = Ostars.facing(float(at[0]), float(at[1]))
		add_child(tp)
		trade_posts.append(tp)
	depot = trade_posts[0].yard

func _ostars_shop(node_name: String, id: StringName, key: String) -> Store:
	var at: Array = Ostars.SITES[key]
	var shop := Store.new()
	shop.name = node_name
	shop.setup(manager, plot, 0, id)
	shop.position = terrain.place(Vector3(float(at[0]), 0.0, float(at[1])))
	shop.rotation.y = Ostars.facing(float(at[0]), float(at[1]))
	add_child(shop)
	if Settings.flag(&"show_labels"):
		Nameplate.landmark(shop, shop.store_name, 6.0)
	return shop

## Ostars: starmetal lies in the Meteor Crater of Kael where it fell, and
## black opal on the Dragon's Tooth Isle, nowhere else.
func _build_kael() -> void:
	var pool := terrain.points_in_feature(String(Ostars.CRATER.name))
	if not pool.is_empty():
		var field := ResourceField.new()
		field.name = "Crater_Starmetal"
		field.quota = 9
		field.min_spacing = 6.0
		field.refill_seconds = 45.0
		field.setup([{"item": &"ore_starmetal", "volume": [0.3, 1.4], "embed": [0.35, 0.6]}],
			_build_rock, _from_pool(pool), _rng.randi())
		add_child(field)
		field.prefill()
		rock_fields.append(field)
	var isle := Vector2(2000, 1960)
	var opal_pool := PackedVector3Array()
	for p in terrain.points_in_biomes([0, 1, 2, 3, 4, 5], 4):
		if Vector2(p.x, p.z).distance_to(isle) < 240.0:
			opal_pool.append(p)
	if not opal_pool.is_empty():
		var opal := ResourceField.new()
		opal.name = "Isle_BlackOpal"
		opal.quota = 3
		opal.min_spacing = 30.0
		opal.refill_seconds = 240.0
		opal.min_present = 1
		opal.setup([{"item": &"gem_black_opal", "volume": [0.1, 0.5], "embed": [0.5, 0.75]}],
			_build_rock, _from_pool(opal_pool), _rng.randi())
		add_child(opal)
		opal.prefill()
		rock_fields.append(opal)

## Diamonds: a few, in one cavern only, the deepest one under the mountains.
func _build_diamond_cavern() -> void:
	var best: Dictionary = {}
	var best_cover := -INF
	for room in network.rooms:
		var c: Vector3 = room.centre
		if terrain.biome_at(c.x, c.z) != Terrain.Biome.MOUNTAIN:
			continue
		var cover := terrain.height_at(c.x, c.z) - float(room.floor)
		if cover > best_cover:
			best_cover = cover
			best = room
	if best.is_empty():
		return
	diamond_cavern = int(best.index)
	var field := ResourceField.new()
	field.name = "DiamondCavern"
	field.quota = 4
	field.min_spacing = 5.0
	field.refill_seconds = 300.0
	field.spawn_clearance = 0.0
	field.wake_distance = 240.0
	var cavern := best
	field.setup([{"item": &"gem_diamond", "volume": [0.1, 0.45], "embed": [0.55, 0.8]}], _build_rock,
		func(rng: RandomNumberGenerator) -> Vector3: return network.floor_point(cavern, rng), _rng.randi())
	add_child(field)
	field.prefill()
	rock_fields.append(field)

## Bump to throw away every saved cave plan.
const CAVE_PLAN_VERSION := 1
const CAVE_SEED := 4242

## Plans the cave networks - or, when the land, the zones and the game are
## all as they were last time, reads that plan back from the file it was kept
## in (see CaveNetwork.save_plan), which is most of the time the caves take
## to build. Behind the boot screen the planning runs on a worker thread,
## with the screen still drawing.
func _plan_caves(zones: Array, links: Array) -> void:
	var path := terrain.cache_path.replace("terrain_cache", "cave_plan") if terrain.cache_path != "" else ""
	var source := (network.get_script() as Script).source_code
	var key := str(hash(var_to_str([CAVE_PLAN_VERSION, BuildInfo.NUMBER, terrain.cache_key(), zones, links,
		CAVE_SEED, source.hash()])))
	if network.load_plan(terrain, path, key, CAVE_SEED):
		await _detail("Read the cave plan back from last time - no need to work it out again")
		return
	await Workers.one(network.plan.bind(terrain, zones, links, CAVE_SEED), "cave plan", _loading_tree())
	network.save_plan(path, key)

## The cavern the diamonds are in, by room index; -1 until the caves are built.
var diamond_cavern: int = -1

## The caves: the networks are planned under every island, the surface mouths
## the terrain found are built as trench-and-portal entrances into their first
## caverns, and every cavern gets a field of its cave biome's ore - and in the
## fungal caves, giant glowcaps to fell.
func _build_caves() -> void:
	network = CaveNetwork.new()
	network.name = "Caves"
	network.manager = manager
	var zones: Array = Ostars.CAVE_ZONES if WorldMap.is_ostars() else CAVE_ZONES
	var links: Array = [] if WorldMap.is_ostars() else CAVE_LINKS
	await _detail("Planning %d cave networks under the land, and the deep passages between them" % zones.size())
	await _plan_caves(zones, links)
	_lap("cave plan")
	var net_summary: Dictionary = network.summary()
	await _detail("Hollowing out %d caverns and %.1f km of tunnel, %d of them below the sea" % [
		int(net_summary.caverns), float(net_summary.tunnel_km), int(net_summary.below_sea)])
	for plan in terrain.caves:
		var cave := Cave.new()
		cave.name = String(plan.name).replace(" ", "").replace("'", "")
		cave.with_chamber = false
		cave.caps = plan.get("caps", [])
		cave.setup(plan.entrance, plan.dir, String(plan.name), _rng.randi())
		add_child(cave)
		caves.append(cave)
		network.entrances.append(cave)
	await _detail("Framing %d cave entrances with timber and lamps" % terrain.caves.size())
	add_child(network)
	_lap("cave build")
	for i in network.rooms.size():
		if i % 8 == 0:
			await _detail("Bedding ore in the caverns (%d-%d of %d)" % [i + 1, mini(i + 8, network.rooms.size()), network.rooms.size()])
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
		field.quota = clampi(int(size / 5.0), 3, 16)
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
		if int(room.kind) == CaveNetwork.Kind.FUNGAL and size >= 20.0:
			var grove := ResourceField.new()
			grove.name = "Glowcaps_%d" % i
			grove.quota = clampi(int(size / 8.0), 3, 10)
			grove.min_spacing = 5.0
			grove.refill_seconds = 60.0
			grove.spawn_clearance = 0.0
			grove.wake_distance = 240.0
			grove.setup([GLOWCAP], _build_tree, func(rng: RandomNumberGenerator) -> Vector3:
				return network.floor_point(cavern, rng), _rng.randi())
			add_child(grove)
			grove.prefill()
			tree_fields.append(grove)
	_build_diamond_cavern()

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
		# Facing the road in, or home when there is none, so a trader's
		# sign reads as you arrive.
		outpost.rotation.y = _facing(String(spec.name), at)
		add_child(outpost)
		outposts.append(outpost)
	# A miner's camp by each cave mouth, off to one side of the yard in front.
	for cave in caves:
		var camp := Outpost.new()
		camp.name = "%sCamp" % cave.name
		var mouth := cave.global_transform
		camp.setup(Outpost.Kind.MINERS_CAMP, "%s Camp" % cave.cave_name, _rng.randi(),
			int(80.0 + mouth.origin.length() * 0.6))
		# Well clear of the doorway: room to drive up, turn and back in.
		camp.position = terrain.place(mouth * Vector3(-15.0, 0.0, -9.0))
		camp.rotation.y = atan2(-mouth.basis.z.x, -mouth.basis.z.z)
		add_child(camp)
		outposts.append(camp)

## Which way a place at `at` turns its front (local +Z): toward where its road
## arrives, or toward home.
func _facing(place: String, at: Vector3) -> float:
	if terrain.road_ends.has(place):
		var end: Vector3 = terrain.road_ends[place]
		var d := Vector2(end.x - at.x, end.z - at.z)
		if d.length() > 1.0:
			return atan2(d.x, d.y)
	return atan2(-at.x, -at.z)

## Everything worth marking on the map and the compass.
func points_of_interest() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# The traders are known from the start: the compass always points to them.
	for tp in trade_posts:
		out.append({"name": tp.title().capitalize(), "kind": "trade", "pos": tp.global_position, "reach": 45.0,
			"color": Color(0.98, 0.72, 0.35), "known": true})
	if WorldMap.is_ostars():
		# The places on the owner's map: found by going there (each has its
		# own reach - a forest is found at its edge, not its middle).
		for place in Ostars.PLACES:
			var at := Vector3(float(place[1]), 0.0, float(place[2]))
			at.y = terrain.height_at(at.x, at.z)
			out.append({"name": String(place[0]), "kind": "place", "pos": at, "reach": float(place[3]),
				"color": Color(0.70, 0.90, 0.62)})
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
		if Vector2(p.x - here.x, p.z - here.z).length() < float(poi.get("reach", 40.0)):
			PlayerState.discovered.append(poi.name)
			hud.show_banner("Discovered", poi.name)

## The biggest chunk of ore that turns up in the ground, m3.
const MAX_CHUNK := 2.0

func _build_rock(kind: Dictionary, form_seed: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = form_seed
	var rock := OreRock.new()
	rock.manager = manager
	rock.plot_id = 0
	rock.ore_item = kind.item
	rock.seed_form(form_seed)
	# Every kind can come as big as MAX_CHUNK and bedded almost all the way
	# in; the big and the deep are the rarer ends of the range.
	rock.embed = lerpf(float(kind.embed[0]), OreRock.MAX_EMBED, pow(rng.randf(), 1.4))
	rock.volume = lerpf(float(kind.volume[0]), MAX_CHUNK, pow(rng.randf(), 1.6))
	return rock

## The buyer's yard: material left inside the fence is bought when the player
## asks the shopkeep, not the moment it touches the ground.
func _build_depot() -> void:
	depot = SellYard.new()
	depot.name = "SellYard"
	depot.setup(manager, quests)
	depot.extents = Vector3(18.0, 4.0, 18.0)
	# The yard hand: behind the counter, waving you in.
	depot.npc = NpcFigure.new(NpcFigure.Role.SHOPKEEP, "Shopkeep")
	depot.npc.position = Vector3(0, 0, -depot.extents.z * 0.5 + 1.4)
	depot.npc.rotation.y = PI
	# On the highest ground under the pad, so no corner of the land comes up
	# through it.
	var top := -INF
	for dx in [-9.0, 0.0, 9.0]:
		for dz in [-9.0, 0.0, 9.0]:
			top = maxf(top, terrain.height_at(DEPOT_POSITION.x + dx, DEPOT_POSITION.z + dz))
	depot.position = Vector3(DEPOT_POSITION.x, top, DEPOT_POSITION.z)
	depot.rotation.y = DEPOT_YAW
	add_child(depot)
	# The buildings have their own signs now; floating names are optional.
	if Settings.flag(&"show_labels"):
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
		summit_store.rotation.y = _facing(SUMMIT_STORE, at)
		add_child(summit_store)
		# The buildings have their own signs now; floating names are optional.
		if Settings.flag(&"show_labels"):
			Nameplate.landmark(summit_store, "SUMMIT OUTFITTERS", 6.5)
	store = Store.new()
	store.name = "Store"
	store.setup(manager, plot, 0)
	store.position = terrain.place(STORE_POSITION)
	store.rotation.y = PI
	add_child(store)
	dealer_store = _town_shop("Dealer", &"dealer", DEALER_POSITION)
	works_store = _town_shop("Works", &"works", WORKS_POSITION)
	# The buildings have their own signs now; floating names are optional.
	if Settings.flag(&"show_labels"):
		Nameplate.landmark(store, "STORE", 6.0)

func _town_shop(node_name: String, id: StringName, at: Vector3) -> Store:
	var shop := Store.new()
	shop.name = node_name
	shop.setup(manager, plot, 0, id)
	shop.position = terrain.place(at)
	shop.rotation.y = PI
	add_child(shop)
	if Settings.flag(&"show_labels"):
		Nameplate.landmark(shop, shop.store_name, 6.0)
	return shop

## Every shop in the world.
func all_stores() -> Array[Store]:
	var out: Array[Store] = []
	for s in [store, dealer_store, works_store, summit_store]:
		if s != null:
			out.append(s)
	return out

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
	for p in players():
		var riding: Variant = p.vehicle
		if riding != null and (not is_instance_valid(riding) or (riding as Node).is_queued_for_deletion()):
			p.exit_vehicle()
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
func _distance_to(v: Hauler, p: Player = null) -> float:
	if p == null:
		p = player
	var local := v.global_transform.affine_inverse() * p.global_position
	var half := v.body_size * 0.5
	return Vector3(maxf(absf(local.x) - half.x, 0.0), 0.0, maxf(absf(local.z) - half.z, 0.0)).length()

## The nearest vehicle with a ramped deck within `reach` of the player
## (measured to its outline), leaving out `skip`.
func _deck_near(p: Player, reach: float, skip: Hauler = null) -> Hauler:
	var best: Hauler = null
	var best_d := reach
	for v in vehicles():
		if v == skip or not v.has_ramps():
			continue
		var local := v.global_transform.affine_inverse() * p.global_position
		var half := v.body_size * 0.5
		var d := Vector2(maxf(absf(local.x) - half.x, 0.0), maxf(absf(local.z) - half.z, 0.0)).length()
		if d <= best_d:
			best = v
			best_d = d
	return best

func vehicle_at_hand(reach: float = 6.0, p: Player = null) -> Hauler:
	if p == null:
		p = player
	if p != null and p.driving():
		return p.vehicle as Hauler
	var best: Hauler = null
	var best_d := INF
	for v in vehicles():
		var local := v.global_transform.affine_inverse() * p.global_position
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
		{"name": "Sell Yard", "color": Color(0.98, 0.80, 0.30), "where": func():
			return depot.global_position if depot != null and trade_posts.is_empty() else null},
		{"name": "Hardware Store", "color": Color(0.55, 0.78, 1.0), "where": func():
			return store.global_position if store != null else null},
		{"name": "Vehicle Dealer", "color": Color(0.45, 0.9, 0.95), "where": func():
			return dealer_store.global_position if dealer_store != null else null},
		{"name": "Machine Works", "color": Color(0.95, 0.6, 0.35), "where": func():
			return works_store.global_position if works_store != null else null},
		{"name": "Summit Outfitters", "color": Color(0.7, 0.62, 1.0), "where": func():
			return summit_store.global_position if summit_store != null else null},
		{"name": "Quarry", "color": Color(0.80, 0.70, 0.62), "where": func():
			return null if WorldMap.is_ostars() else QUARRY_CENTRE},
		{"name": "Home Woods", "color": Color(0.45, 0.80, 0.40), "where": func():
			return starter_forest if starter_forest != Vector3.INF else null},
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
		var known: bool = poi.get("known", false)
		markers.append({"name": func(): return poi_name if known or discovered(poi_name) else "?",
			"color": poi.color, "where": func():
				if known or discovered(poi_name) or player.global_position.distance_to(pos) < 220.0:
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
		if Net.guest_world:
			Net.leave()
			host_gone()
			return
		show_main_menu())
	pause_menu.quit_requested.connect(quit_game)
	pause_menu.leave_requested.connect(func():
		if Net.guest_world:
			Net.leave()
			host_gone()
		else:
			stop_hosting()
			resume_play())
	pause_menu.load_slot_requested.connect(load_slot)
	pause_menu.save_slot_requested.connect(func(n: int):
		if save_to_slot(n):
			hud.toast("Saved to slot %d" % n, UITheme.GOOD))
	add_child(pause_menu)

	# Started by the loading screen, the world is not the current scene yet
	# (Boot hands it over once it is built), but it is the game all the same.
	var menu_wanted := show_menu and (get_tree().current_scene == self or staged_load) and not MainMenu.skip_once
	MainMenu.skip_once = false
	if menu_wanted:
		main_menu = MainMenu.new()
		main_menu.continue_requested.connect(resume_play)
		main_menu.new_game_requested.connect(start_new_game)
		main_menu.quit_requested.connect(quit_game)
		main_menu.load_slot_requested.connect(_menu_load_slot)
		main_menu.new_slot_requested.connect(start_new_game_in)
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
		main_menu.load_slot_requested.connect(_menu_load_slot)
		main_menu.new_slot_requested.connect(start_new_game_in)
		add_child(main_menu)
	hud.visible = false
	if not Net.online():
		get_tree().paused = true
	main_menu.open(self)

func pause_game() -> void:
	if get_tree().paused or (pause_menu.visible and Net.online()):
		return
	# In co-op the world goes on for everyone else.
	if not Net.online():
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

## Whether this world came out of a save (rather than being a new game).
var loaded_game: bool = false

func quick_save() -> bool:
	# A guest's world is the host's; saving it here would overwrite their own.
	if Net.guest_world:
		return false
	var ok := SaveSystem.save_game(plot, player, "", manager, _padless_vehicle(), quests)
	if ok:
		hud.flash_saved()
	else:
		hud.toast("Save failed", UITheme.BAD)
	return ok

func quick_load() -> void:
	# Out of the seat first: the truck being sat in is replaced by the one in
	# the save.
	if player.driving():
		_toggle_vehicle()
	if SaveSystem.load_game(plot, player, "", manager,
			_spawn_vehicle_for_load, quests):
		_unstick_player()
		_unstick_player.call_deferred()
		hud.toast("Loaded your last save", UITheme.ACCENT)
	else:
		hud.toast("No save to load", UITheme.BAD)

## A fresh world, not this one scrubbed: the progress autoloads are reset and
## the scene is built again from nothing.
func start_new_game() -> void:
	# The world behind the menu is already a new one, on the map wanted.
	if not SaveSystem.has_save() and not playing and not loaded_game and WorldMap.chosen == WorldMap.current:
		# Nothing to throw away - the world behind the menu is already new.
		resume_play()
		return
	SaveSystem.delete_save()
	_rebuild_world()

## A new game in save slot `n` (what was in it is replaced).
func start_new_game_in(n: int) -> void:
	if playing and SaveSystem.slot != n:
		quick_save()
	SaveSystem.slot = n
	SaveSystem.slot_chosen = true
	start_new_game()

## From the title screen: the slot already loaded behind it just carries on.
func _menu_load_slot(n: int) -> void:
	if n == SaveSystem.slot and loaded_game:
		resume_play()
	else:
		load_slot(n)

## Plays the game saved in slot `n`: the current one is saved first, then the
## world is built again and that slot read into it.
func load_slot(n: int) -> void:
	if playing:
		quick_save()
	SaveSystem.slot = n
	SaveSystem.slot_chosen = true
	_rebuild_world()

## Saves the game being played into slot `n`, which it then plays in.
func save_to_slot(n: int) -> bool:
	SaveSystem.slot = n
	SaveSystem.slot_chosen = true
	return quick_save()

## The scene built again from nothing, with the progress autoloads reset; the
## slot in play is read in if it has a save.
func _rebuild_world() -> void:
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
	if playing and not Net.guest_world:
		SaveSystem.save_game(plot, player, "", manager, _padless_vehicle(), quests)
	get_tree().quit()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			if playing and hud != null and not Net.guest_world:
				SaveSystem.save_game(plot, player, "", manager, _padless_vehicle(), quests)
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			# Alt-tab pauses, rather than leaving the truck rolling.
			if playing and pause_menu != null and not get_tree().paused and not Net.online() \
					and DisplayServer.get_name() != "headless":
				pause_game()

func _on_setting_changed(_key: StringName) -> void:
	_apply_all_settings()

## No grass through the plot's concrete, however big it has grown.
func _keep_grass_off_plot() -> void:
	grass.keep_off = [[plot.global_position, plot.half_extent + 0.6]]

## The demo lines come and go with their setting.
func _apply_showcase() -> void:
	# Not on Ostars: nothing is built there.
	var wanted := Settings.flag(&"demo_lines") and not WorldMap.is_ostars()
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
	# The far woods are drawn out to the view distance and no further.
	ResourceField.impostor_range = reach
	get_tree().call_group(&"tree_impostors", "set", "visibility_range_end", reach)
	var shadows := int(Settings.value(&"shadows"))
	sun.shadow_enabled = shadows > 0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if shadows >= 2 \
		else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 160.0 if shadows >= 2 else 70.0
	environment.ssao_enabled = Settings.flag(&"ambient_occlusion")
	environment.glow_enabled = Settings.flag(&"bloom")
	var fancy := Settings.flag(&"shaders")
	grass.configure(int(Settings.value(&"grass")), fancy)
	birds.set_enabled(Settings.flag(&"birds"))
	terrain.set_fancy(fancy)
	ChoppableTree.set_fancy(fancy)
	if not Settings.flag(&"moving_sun"):
		sun.rotation_degrees = Vector3(-52, -38, 0)
		sun.light_color = Color(1.0, 0.95, 0.86)
		sun.light_energy = 1.25
		sun.visible = true
		moon.visible = false

## Day and night. The sun rises at five and sets at nine, crossing the sky
## on a long arc; the sky and the haze go gold at either end of the day and
## deep blue at night, when the moon gives just enough light to find your way
## and your hat lamp comes on. With the moving sun turned off it is always
## mid-morning.
const DAY_SKY_TOP := Color(0.16, 0.42, 0.86)
const DAY_SKY_HORIZON := Color(0.62, 0.80, 0.95)
const DUSK_HORIZON := Color(0.98, 0.62, 0.42)
const NIGHT_SKY_TOP := Color(0.02, 0.03, 0.08)
const NIGHT_SKY_HORIZON := Color(0.07, 0.09, 0.17)
const DAY_HAZE := Color(0.62, 0.78, 0.92)
const NIGHT_HAZE := Color(0.05, 0.07, 0.12)

func _update_sun() -> void:
	if not Settings.flag(&"moving_sun"):
		daylight = 1.0
		night = 0.0
		_paint_sky(1.0, 0.0)
		return
	var h := Economy.hour()
	# Up from 5:00 to 21:00.
	var t := (h - 5.0) / 16.0
	var arc := sin(clampf(t, 0.0, 1.0) * PI) if t >= 0.0 and t <= 1.0 else -0.2
	var elevation := arc * 64.0
	var azimuth := lerpf(-110.0, 110.0, clampf(t, 0.0, 1.0))
	daylight = smoothstep(-0.05, 0.35, arc)
	night = 1.0 - smoothstep(-0.12, 0.06, arc)
	sun.rotation_degrees = Vector3(-maxf(elevation, 4.0), azimuth, 0.0)
	sun.light_color = Color(1.0, 0.62, 0.42).lerp(Color(1.0, 0.96, 0.88), smoothstep(0.05, 0.4, arc))
	sun.light_energy = lerpf(0.0, 1.3, daylight)
	sun.visible = daylight > 0.01
	# The moon rides opposite the sun.
	moon.rotation_degrees = Vector3(-50.0, azimuth + 180.0, 0.0)
	moon.light_energy = 0.45 * night
	moon.visible = night > 0.01
	_paint_sky(daylight, night)

func _paint_sky(day: float, dark: float) -> void:
	if _sky == null:
		return
	var dusk := clampf(1.0 - absf(day - 0.5) * 2.0, 0.0, 1.0) * (1.0 - dark)
	var top := NIGHT_SKY_TOP.lerp(DAY_SKY_TOP, day)
	var horizon := NIGHT_SKY_HORIZON.lerp(DAY_SKY_HORIZON, day).lerp(DUSK_HORIZON, dusk * 0.8)
	_sky.sky_top_color = top
	_sky.sky_horizon_color = horizon
	var haze := NIGHT_HAZE.lerp(DAY_HAZE, day).lerp(DUSK_HORIZON.darkened(0.2), dusk * 0.4)
	_sky.ground_bottom_color = haze
	_sky.ground_horizon_color = haze
	_haze = haze

var _haze: Color = DAY_HAZE

# --- Runtime ---------------------------------------------------------------

func _process(delta: float) -> void:
	_update_sun()
	_update_winch_reticle()
	_update_underground(delta)
	_check_discovery(delta)

## Aiming a winch: seated in a truck with one, the ring shows where the hook
## would catch and whether the line reaches. On foot there is no ring (the
## winch still hooks what you aim at from beside the truck).
func _update_winch_reticle() -> void:
	if winch_reticle == null or player == null:
		return
	var r: VehicleRig = null
	var truck: Hauler = null
	if player.driving() and playing:
		truck = player.vehicle as Hauler
		if truck != null and truck.rig != null and not truck.rig.operating:
			r = truck.rig
	if r == null or r.anchored:
		winch_reticle.hide_reticle()
		return
	var hit := player.winch_target(r)
	# Pointed at the truck itself there is nothing to show.
	if not hit.is_empty():
		var n := hit.collider as Node
		while n != null and n != truck:
			n = n.get_parent()
		if n == truck:
			hit = {}
	winch_reticle.show_for(r, hit)

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
		# The night sky lights little, so the ambient is lifted a touch to
		# keep the land readable by moonlight.
		environment.ambient_light_energy = OUTDOOR_AMBIENT * lerpf(1.0, 2.2, night)
	environment.fog_light_color = _haze.lerp(Color(0.03, 0.03, 0.05), underground)
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
	# On underground, and outside after dark.
	var lamp := maxf(underground, night * 0.8)
	_headlamp.light_energy = lamp * 1.8
	_headlamp.omni_range = lerpf(22.0, 14.0, underground) if night > underground else 14.0
	_headlamp.visible = lamp > 0.01
	var plates_on := underground < 0.5
	if plates_on != _plates_shown:
		_plates_shown = plates_on
		get_tree().call_group(Nameplate.LANDMARK_GROUP, "set_visible", plates_on)

## Below every cave: anyone down here has fallen out of the world.
const FELL_OUT_Y := -160.0
## How far under the land a truck or the player has to be before they are
## taken to have fallen through it.
const UNDER_GROUND := 3.0
var _rescue_timer: float = 0.0

## Anything that has fallen through the land - or out of the world - is put
## back on the surface right above where it went: trucks (with their load)
## and the player on foot. Loose pieces are the item manager's to rescue.
func _rescue_fallen() -> void:
	for v in vehicles():
		var p := v.global_position
		var ground := _ground_for_items(p)
		var fell := p.y < FELL_OUT_Y or (ground != -INF and p.y < ground - UNDER_GROUND)
		if not fell:
			continue
		var at := Vector3(clampf(p.x, -MAP_HALF, MAP_HALF), 0.0, clampf(p.z, -MAP_HALF, MAP_HALF))
		at.y = terrain.height_at(at.x, at.z) + v.spawn_height()
		v.move_to(Transform3D(Basis.from_euler(Vector3(0, v.global_rotation.y, 0)), at))
		hud.log_message("the %s fell through the ground - put back on top" % v.display_name.to_lower())
	for p in players():
		if p.driving():
			continue
		var pp := p.global_position
		var under := _ground_for_items(pp)
		if under != -INF and pp.y < under - UNDER_GROUND:
			p.global_position = Vector3(pp.x, under + 1.0, pp.z)
			p.velocity = Vector3.ZERO

## Standing on the caves' own rock: somewhere under the land that the cave
## shapes' sums miss (the edge of a cavern floor, where its wall was drawn out
## to a tunnel mouth) is still a cave, not a fall through the ground.
func _on_cave_rock(p: Vector3) -> bool:
	if network == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP, p + Vector3.DOWN * 4.0, Layers.WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var body := hit.collider as Node
	return body != null and (network.is_ancestor_of(body) or body.get_parent() is Cave)

## Back to where the game starts, by the plot: for when you are stuck out
## somewhere, or have fallen through the world. The truck stays where it is.
func return_to_base(p: Player = null) -> void:
	if p == null:
		p = player
	# A guest asking for this from their pause menu has it done on the host.
	if p == player and Net.is_client():
		Net.client_side.call("send_event", {"t": "base"})
		return
	# Lying in a heap somewhere: up first.
	p.stand_up()
	if p.driving():
		var riding := p.vehicle as Hauler
		p.exit_vehicle()
		if riding != null and is_instance_valid(riding):
			riding.driver = null
	var spot := Vector3(0, 0, 12.0)
	spot.y = terrain.height_at(spot.x, spot.z) + 1.0
	p.global_position = spot
	p.velocity = Vector3.ZERO
	p.rotation.y = PI
	if p == player:
		hud.toast("Back at base", UITheme.GOOD)
	else:
		_tell(p, "back at base")

func _physics_process(delta: float) -> void:
	# A co-op guest's world is the host's to run.
	if Net.is_client():
		return
	for g in guests.values():
		if is_instance_valid(g) and (g as Player).global_position.y < FELL_OUT_Y:
			return_to_base(g)
	if player != null and player.global_position.y < FELL_OUT_Y:
		return_to_base()
	_rescue_timer -= delta
	if _rescue_timer <= 0.0 and player != null:
		_rescue_timer = 0.5
		_rescue_fallen()
	for p in players():
		if Net.is_client():
			break
		# Standing by a truck, its winch answers the reel keys too.
		if not p.driving() and playing:
			var wv := vehicle_at_hand(10.0, p)
			if wv != null and wv.rig != null and wv.rig.anchored and _distance_to(wv, p) <= 10.0:
				p.work_winch(wv.rig, delta)
		var riding := p.vehicle as Hauler if p.driving() else null
		if riding != null and is_instance_valid(riding):
			# The player rides the seat; the camera is a child of the player,
			# so this doubles as the driving camera.
			p.global_position = riding.seat_of(p).origin
			p.velocity = Vector3.ZERO
	if not autosave or not playing or not Settings.flag(&"autosave"):
		return
	_autosave_timer -= delta
	if _autosave_timer <= 0.0:
		_autosave_timer = AUTOSAVE_SECONDS
		quick_save()

func _unhandled_input(event: InputEvent) -> void:
	var press := (event is InputEventKey or event is InputEventMouseButton) \
		and event.is_pressed() and not event.is_echo()
	if not press or hud.journal_open() or player == null:
		return
	# A co-op guest's presses go to the host, which does what they mean there.
	if Net.is_client():
		return
	if Controls.pressed(event, &"quick_save"):
		if quick_save():
			hud.toast("Saved", UITheme.GOOD)
	elif Controls.pressed(event, &"quick_load"):
		if not Net.online():
			quick_load()
	elif Controls.pressed(event, &"new_game"):
		if Net.online():
			return
		pause_game()
		pause_menu.ask("Start a new game?",
			"This save slot will be replaced. Settings are kept.", "Start over",
			func():
				# Over again on the same map.
				WorldMap.chosen = WorldMap.current
				start_new_game())
	else:
		handle_key(player, event)

# --- Co-op ------------------------------------------------------------------------------

var net_client: NetClient
var _guest_names: Dictionary = {}

## Opens this world to co-op guests (Net.host() has opened the port).
func start_hosting() -> void:
	if net_host != null:
		return
	net_host = NetHost.new()
	net_host.name = "NetHost"
	net_host.world = self
	add_child(net_host)
	# You in the shirt the others see you in (the host is peer 1).
	if player != null and player.avatar != null:
		player.avatar.set_look("", Avatar.color_for(1))

## Closes it again: every guest goes.
func stop_hosting() -> void:
	for peer in guests.keys():
		remove_guest(peer)
	if net_host != null:
		net_host.queue_free()
		net_host = null
	Net.leave()

## A guest's player: a real player in this world, moved by their keys.
func add_guest(peer: int, display: String) -> Player:
	if guests.has(peer) and is_instance_valid(guests[peer]):
		return guests[peer]
	_guest_names[peer] = display
	var p := _make_player()
	p.name = "Guest_%d" % peer
	p.input.remote = true
	p.net_follow = true
	(p.get_node("Camera3D") as Camera3D).current = false
	# Off to one side of the spawn, so guests do not land on each other.
	p.position = Vector3(2.0 + 1.5 * float(guests.size()), 2.0, 12.0)
	p.position.y = terrain.height_at(p.position.x, p.position.z) + 1.0
	add_child(p)
	# They look like you, in their own colour, with their name over them.
	p.avatar.set_look(display, Avatar.color_for(peer))
	p.manager = manager
	p.plot = plot
	p.store = store
	p.stores = player.stores.duplicate()
	p.wants_to_drive.connect(func(v: Node3D): drive(v as Hauler, p))
	p.interacted.connect(func(m: String): _tell(p, m))
	# Their own tools and gear, as they left them last time in this world.
	p.kit = PlayerKit.new()
	p.kit.from_dict(PlayerState.guest_kits.get(display, {}))
	p.kit.changed.connect(func(): PlayerState.guest_kits[display] = p.kit.to_dict())
	PlayerState.guest_kits[display] = p.kit.to_dict()
	guests[peer] = p
	for field in tree_fields + rock_fields:
		field.extra_focus.append(p)
	return p

func remove_guest(peer: int) -> void:
	var p: Player = guests.get(peer, null)
	guests.erase(peer)
	var display: String = _guest_names.get(peer, "A player")
	_guest_names.erase(peer)
	if p == null or not is_instance_valid(p):
		return
	if p.kit != null:
		PlayerState.guest_kits[display] = p.kit.to_dict()
	if p.driving():
		var riding := p.vehicle as Hauler
		p.exit_vehicle()
		if riding != null and is_instance_valid(riding):
			riding.driver = null
	p._release_dragged()
	p._drop(p.held.size())
	for field in tree_fields + rock_fields:
		field.extra_focus.erase(p)
	p.queue_free()
	hud.log_message("%s left" % display)

## Every kit in the game: this machine's (PlayerState) and each guest's.
func all_kits() -> Array:
	var out: Array = [PlayerState]
	for p in guests.values():
		if is_instance_valid(p) and (p as Player).kit != null:
			out.append((p as Player).kit)
	return out

func guest_name(peer: int) -> String:
	return String(_guest_names.get(peer, "Player %d" % peer))

## Guest: the host has gone (or could not be reached). Back to your own world.
static var leave_reason: String = ""
func host_gone(reason: String = "") -> void:
	leave_reason = reason
	Net.leave()
	# Nothing of the host's comes home: your own save is read in afresh.
	PlayerState.reset()
	Economy.from_dict({})
	MainMenu.skip_once = false
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/boot.tscn")

## Every player on this game: this machine's, and each co-op guest's.
func players() -> Array[Player]:
	var out: Array[Player] = []
	if player != null:
		out.append(player)
	for g in guests.values():
		if is_instance_valid(g):
			out.append(g as Player)
	return out

## Co-op guests' players on the host, by peer id.
var guests: Dictionary = {}
var net_host: NetHost

## A message for one player: on this screen, or sent to their game.
func _tell(p: Player, message: String) -> void:
	if p == player or p == null:
		hud.log_message(message)
	elif net_host != null:
		net_host.tell(p, message)

## The presses that work on the world round a player: vehicles, hitches, the
## winch from outside. `p` is this machine's player or a co-op guest's.
func handle_key(p: Player, event: InputEvent) -> void:
	# In build mode Z, X and C turn the ghost; they must not also empty the truck.
	if p.build_system != null and p.build_system.active:
		return
	if Controls.pressed(event, &"hitch"):
		p.act(&"lever" if p.driving() else &"use")
		_tell(p, _toggle_hitch(p))
	elif Controls.pressed(event, &"enter_vehicle"):
		# In and out: seated, it gets out (unless it is working the crane's
		# grapple); on foot, it gets into the vehicle looked at or stood by.
		if p.driving():
			var r := p.rig()
			if r == null or not r.operating:
				_toggle_vehicle(p)
		else:
			var v := _vehicle_looked_at(p)
			if v == null or v.is_trailer:
				v = vehicle_at_hand(3.0, p)
				if v != null and _distance_to(v, p) > 3.0:
					v = null
			if v != null:
				drive(v, p)
	elif Controls.pressed(event, &"unload"):
		p.act(&"lever" if p.driving() else &"use")
		var v := vehicle_at_hand(8.0, p)
		if v != null and v.towing != null and is_instance_valid(v.towing) \
				and (v.towing.bed_kind == &"deck" or (v.towing.has_ramps() and not v.has_bed())):
			v = v.towing
		# Nothing of its own to unload - a loader parked on the low-loader, or
		# being driven onto or off it: [X] works the deck's ramps instead.
		if v == null or (not v.has_ramps() and not v.has_bed()):
			var deck := _deck_near(p, 8.0, v)
			if deck != null:
				v = deck
		if v != null:
			_tell(p, v.work_tailgate())
	elif Controls.pressed(event, &"unload_one"):
		p.act(&"lever" if p.driving() else &"use")
		var v := vehicle_at_hand(8.0, p)
		if v != null and v.unload_one():
			_tell(p, "dropping one off the back (%d left)" % (v.cargo_count() - 1))
	elif Controls.pressed(event, &"winch_hook") and not p.driving():
		p.act(&"use")
		# The winch from outside the truck: stand by it, aim, hook on.
		var wv := vehicle_at_hand(10.0, p)
		if wv == null or wv.rig == null or _distance_to(wv, p) > 10.0:
			_tell(p, "stand by a truck with a winch to use it")
		else:
			_tell(p, p.hook_winch(wv.rig))
	elif Controls.pressed(event, &"outriggers") and not p.driving():
		p.act(&"use")
		var ov := vehicle_at_hand(10.0, p)
		if ov == null or ov.rig == null or not ov.rig.has_crane() or _distance_to(ov, p) > 10.0:
			_tell(p, "stand by a crane truck to put its outriggers out")
		else:
			_tell(p, p.toggle_outriggers(ov.rig))
	elif Controls.pressed(event, &"recover"):
		p.act(&"lever" if p.driving() else &"use")
		var v := vehicle_at_hand(8.0, p)
		if v != null:
			var said := v.try_recover()
			if said == "":
				_tell(p, "%s recovered" % v.display_name)
				# Driven on a guest's machine: it is put right there too.
				if v.net_follow and net_host != null:
					net_host.call("recovered", v)
			else:
				_tell(p, said)

## A save made in the driver's seat (before saves knew better) puts the
## player inside the truck: out by the driver's door instead, before the
## body can shove the truck down through the ground.
func _unstick_player() -> void:
	for v in vehicles():
		var local := v.global_transform.affine_inverse() * player.global_position
		var half := v.body_size * 0.5 + Vector3(0.6, 0.0, 0.6)
		if absf(local.x) < half.x and absf(local.z) < half.z and local.y > -2.5 and local.y < 3.5:
			player.global_position = v.global_position \
				+ v.global_transform.basis.x * (v.body_size.x * 0.5 + 1.3) + Vector3(0, 1.0, 0)
			player.velocity = Vector3.ZERO
			return

## The vehicle under the crosshair, if one is within reach.
func _vehicle_looked_at(p: Player = null) -> Hauler:
	if p == null:
		p = player
	var hit := p.aim_hit()
	if hit.is_empty():
		return null
	var n := hit.collider as Node
	while n != null and not (n is Hauler):
		n = n.get_parent()
	return n as Hauler

func _toggle_vehicle(p: Player = null) -> void:
	if p == null:
		p = player
	if p.driving():
		var riding := p.vehicle as Hauler
		var was_passenger := p.passenger
		p.exit_vehicle()
		if riding != null and is_instance_valid(riding) and was_passenger:
			riding.passengers.erase(p)
			# Out of the passenger's side.
			p.global_position = riding.global_position \
				- riding.global_transform.basis.x * (riding.body_size.x * 0.5 + 1.3) + Vector3(0, 1.0, 0)
			_tell(p, "got out of the %s" % riding.display_name.to_lower())
			return
		if riding != null and is_instance_valid(riding):
			riding.driver = null
			# Out of the driver's door, clear of the body whatever its width.
			p.global_position = riding.global_position \
				+ riding.global_transform.basis.x * (riding.body_size.x * 0.5 + 1.3) + Vector3(0, 1.0, 0)
			_tell(p, "left the %s" % riding.display_name.to_lower())
		return
	if vehicles().is_empty():
		_tell(p, "No vehicle yet - they are sold at the Store, and each spawns on its own pad")
		return
	_tell(p, "look at a vehicle, or stand by it, and press [F] to get in")

## Hitches the trailer behind the truck you are in (or stand by), or lets it
## go. Returns what happened.
func _toggle_hitch(p: Player = null) -> String:
	if p == null:
		p = player
	var truck: Hauler = null
	if p.driving():
		truck = p.vehicle as Hauler
	else:
		# Standing by: the truck with a hitch, or the truck a trailer near you
		# is hitched to.
		var near := vehicle_at_hand(6.0, p)
		if near != null and near.is_trailer:
			if near.towed_by != null:
				truck = near.towed_by
			else:
				for v in vehicles():
					if v.has_hitch() and v.towing == null \
							and v.hitch_point().distance_to(near.tongue_point()) <= Hauler.HITCH_REACH:
						truck = v
						break
		elif near != null:
			truck = near
	if truck == null:
		return "stand by a truck and a trailer to hitch them [T]"
	if not truck.has_hitch():
		return "the %s has no hitch" % truck.display_name.to_lower()
	# Trailers with hitches of their own make a train: the free trailer
	# nearest the back of the train goes on the end, and with none there
	# the last one comes off.
	if truck.towing != null:
		var tail := truck
		while tail.towing != null and is_instance_valid(tail.towing):
			tail = tail.towing
		var extra := _free_trailer_near(tail)
		if extra != null and tail.has_hitch() and \
				extra.tongue_point().distance_to(tail.hitch_point()) <= Hauler.HITCH_REACH:
			var e := tail.hitch(extra)
			return e if e != "" else "hitched the %s behind the %s" % [extra.display_name.to_lower(), tail.display_name.to_lower()]
		var front := tail.towed_by if tail != truck else truck
		var t := front.unhitch()
		return "unhitched the %s" % t.display_name.to_lower()
	var best: Hauler = _free_trailer_near(truck)
	if best == null:
		return "no trailer to hitch - they are sold at the Store"
	var err := truck.hitch(best)
	return err if err != "" else "hitched the %s - [T] to let it go" % best.display_name.to_lower()

## The unhitched trailer whose coupling is nearest `v`'s hitch.
func _free_trailer_near(v: Hauler) -> Hauler:
	var best: Hauler = null
	var best_d := INF
	for other in vehicles():
		if other != v and other.is_trailer and other.towed_by == null and other.towing != v:
			var d := other.tongue_point().distance_to(v.hitch_point())
			if d < best_d:
				best_d = d
				best = other
	return best

## Into the driving seat of `v`.
func drive(v: Hauler, p: Player = null) -> void:
	if p == null:
		p = player
	if v == null or p.driving():
		return
	if v.driver != null:
		# Someone is at the wheel: ride along, if there is a seat.
		if v.driver != p and not v.is_trailer and v.free_passenger_seat():
			p.enter_vehicle(v)
			p.passenger = true
			v.passengers.append(p)
			_tell(p, "riding along in the %s - [F] to get out" % v.display_name.to_lower())
			return
		_tell(p, "someone else is driving the %s, and there is no seat free" % v.display_name.to_lower())
		return
	if v.is_trailer:
		_tell(p, "a trailer has no seat - back a truck up to it and hitch it [T]")
		return
	if p == player:
		hauler = v
	p.enter_vehicle(v)
	v.driver = p
	_tell(p, "driving the %s - [F] to get out" % v.display_name.to_lower())
	if v.cargo_count() > 0:
		_tell(p, "%d piece(s) in the bed - they ride loose, so mind the corners" % v.cargo_count())
