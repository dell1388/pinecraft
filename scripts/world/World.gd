class_name World
extends Node3D

## The game scene: terrain, forest, quarry, the player's plot, the sell depot,
## the player and the HUD, plus save/load and vehicle handling.

const MAP_HALF := 300.0
const DEPOT_POSITION := Vector3(0, 0, 70)
const STORE_POSITION := Vector3(-52, 0, 62)
const QUARRY_CENTRE := Vector3(-150, 0, -40)
## The plot pad stands clear of two things: the water line, so the yard is never
## flooded, and the ground itself, so the pad and the land are not two surfaces
## fighting over one plane. The slab's top is PLOT_GROUND + 0.05.
const PLOT_GROUND := 0.45
const PAD_HEIGHT := 0.5
const AUTOSAVE_SECONDS := 60.0
const STARTING_MONEY := 250

@export var tree_count: int = 90
@export var rock_count: int = 34
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
## One field per species, each keeping its own ring or patch stocked.
var tree_fields: Array[ResourceField] = []
var rock_fields: Array[ResourceField] = []

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

func _ready() -> void:
	_rng.seed = 20260921
	InputSetup.ensure()
	_build_environment()
	_build_terrain()

	manager = LooseItemManager.new()
	manager.name = "LooseItems"
	add_child(manager)
	manager.register_plot(0, Vector3(0, 6, 0))

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

	_build_forest()
	_build_quarry()
	_build_depot()
	_build_store()

	player = _make_player()
	add_child(player)
	player.manager = manager
	player.plot = plot
	player.store = store

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
	sky.ground_bottom_color = Color(0.20, 0.24, 0.20)
	sky.ground_horizon_color = Color(0.70, 0.80, 0.88)
	sky.sun_angle_max = 24.0
	sky.sun_curve = 0.08
	env.sky.sky_material = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Filmic response, so bright ground and snow roll off rather than clip.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
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
	env.fog_density = 0.0028
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

	# Two rivers off the high ground, each with a couple of places shallow
	# enough to drive through. Everywhere else wants a bridge.
	terrain.rivers = [
		{"width": 10.0, "depth": 3.4, "fords": [{"at": 120.0, "width": 26.0},
			{"at": 300.0, "width": 22.0}],
			"path": [Vector3(-260, 0, -250), Vector3(-170, 0, -160), Vector3(-110, 0, -95),
				Vector3(-82, 0, -20), Vector3(-96, 0, 60), Vector3(-60, 0, 150),
				Vector3(10, 0, 285)]},
		{"width": 8.0, "depth": 2.8, "fords": [{"at": 90.0, "width": 24.0}],
			"path": [Vector3(280, 0, -180), Vector3(170, 0, -120), Vector3(80, 0, -95),
				Vector3(-40, 0, -110), Vector3(-180, 0, -170)]},
	]
	# Roads joining the places worth driving between.
	terrain.roads = [
		[Vector3(0, 0, 0), Vector3(0, 0, 30), DEPOT_POSITION,
			Vector3(-20, 0, 66), STORE_POSITION],
		[Vector3(0, 0, 0), Vector3(-40, 0, -14), Vector3(-90, 0, -28), QUARRY_CENTRE],
		[Vector3(0, 0, 0), Vector3(40, 0, -20), Vector3(110, 0, -40), Vector3(190, 0, -30)],
	]
	# Everything that has to stand on the level, and all of it above the water
	# line so a levelled site is never under the sheet.
	terrain.reserve_site(Vector3(0, PLOT_GROUND, 0), 56.0)
	terrain.reserve_site(Vector3(DEPOT_POSITION.x, 0.6, DEPOT_POSITION.z), 16.0)
	terrain.reserve_site(Vector3(STORE_POSITION.x, 0.6, STORE_POSITION.z), 14.0)
	terrain.reserve_site(Vector3(QUARRY_CENTRE.x, 0.5, QUARRY_CENTRE.z), 34.0)
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

		{"name": "Ironwood", "item": &"wood_ironwood",
			"biomes": [Terrain.Biome.MOUNTAIN],
			"leaf": Color(0.18, 0.30, 0.20), "work": 1900.0,
			"radius": [0.46, 0.60], "height": [5.0, 7.0], "taper": 0.82, "branches": [4, 6],
			# Squat and thick, holding on to a mountainside.
			"start": 0.48, "pitch": [0.70, 1.10], "length": [0.20, 0.32],
			"foliage": 6.0, "crown": [4.6, 0.28]},

		{"name": "Desert Ironwood", "item": &"wood_ironwood",
			"biomes": [Terrain.Biome.DESERT],
			"leaf": Color(0.42, 0.46, 0.28), "work": 1750.0,
			"radius": [0.38, 0.50], "height": [3.8, 5.4], "taper": 0.80, "branches": [5, 7],
			# Low, wide and sparse, the way things grow with no water.
			"start": 0.40, "pitch": [0.95, 1.35], "length": [0.26, 0.40],
			"foliage": 5.0, "crown": [0.0, 0.0]},
	]

	# Quotas follow how much country each species actually has, so a seed that
	# happens to grow little swamp gets few willows rather than an empty field
	# grinding away at a region that is not there.
	var pools: Array[PackedVector3Array] = []
	var total := 0
	for kind in species:
		var pool := terrain.points_in_biomes(kind.biomes, 2, float(kind.get("wet", 0.0)))
		pools.append(pool)
		total += pool.size()
	if total == 0:
		return

	for i in species.size():
		var kind: Dictionary = species[i]
		var pool := pools[i]
		if pool.is_empty():
			continue
		var quota: int = int(round(float(tree_count) * float(pool.size()) / float(total)))
		if quota <= 0:
			continue
		var field := ResourceField.new()
		field.name = "Forest_%s" % kind.name.replace(" ", "_")
		field.quota = quota
		field.min_spacing = 4.2
		field.refill_seconds = 6.0
		field.setup([kind], _build_tree, _from_pool(pool), _rng.randi())
		add_child(field)
		field.prefill()
		tree_fields.append(field)

## A sampler that draws from a fixed set of spots the terrain already vetted -
## right biome, dry, off the roads and outside the build sites.
func _from_pool(points: PackedVector3Array) -> Callable:
	return func(rng: RandomNumberGenerator) -> Vector3:
		return points[rng.randi() % points.size()]

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
	return tree

## The quarry works the same way: a patch per ore, stocked to a quota.
func _build_quarry() -> void:
	# Chunk sizes straddle the player's pull: the small end of iron comes out of
	# the ground whole, the big end has to be cracked up first.
	var ores := [
		{"item": &"ore_iron", "volume": [0.35, 2.6], "embed": [0.30, 0.55]},
		{"item": &"ore_copper", "volume": [0.30, 2.2], "embed": [0.35, 0.60]},
		{"item": &"ore_gold", "volume": [0.20, 1.4], "embed": [0.45, 0.70]},
	]
	var per_ore: int = maxi(1, rock_count / ores.size())
	for i in ores.size():
		var kind: Dictionary = ores[i]
		var field := ResourceField.new()
		field.name = "Quarry_%s" % kind.item
		field.quota = per_ore
		field.min_spacing = 4.0
		field.refill_seconds = 8.0
		# Its own corner of the map, so mining is a trip.
		field.setup([kind], _build_rock,
			_on_ground(ResourceField.rect(QUARRY_CENTRE, Vector2(26.0, 30.0))), _rng.randi())
		add_child(field)
		field.prefill()
		rock_fields.append(field)

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

func _on_vehicle_spawned(vehicle: Node3D) -> void:
	if player != null and player.driving():
		player.exit_vehicle()
	hauler = vehicle as Hauler

# --- Menus, settings and the HUD's view of the world -----------------------

## Places the compass marks. Each returns null while it does not exist.
func compass_markers() -> Array[Dictionary]:
	return [
		{"name": "Plot", "color": Color(0.55, 0.85, 0.50), "where": func(): return plot.global_position},
		{"name": "Sell Yard", "color": Color(0.98, 0.80, 0.30), "where": func(): return depot.global_position},
		{"name": "Store", "color": Color(0.55, 0.78, 1.0), "where": func(): return store.global_position},
		{"name": "Quarry", "color": Color(0.80, 0.70, 0.62), "where": func(): return QUARRY_CENTRE},
		{"name": "Hauler", "color": Color(1.0, 0.55, 0.40), "where": func():
			if hauler == null or not is_instance_valid(hauler) or player.driving():
				return null
			return hauler.global_position},
	]

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
	var ok := SaveSystem.save_game(plot, player, SaveSystem.SAVE_PATH, manager, hauler, quests)
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
		SaveSystem.save_game(plot, player, SaveSystem.SAVE_PATH, manager, hauler, quests)
	get_tree().quit()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			if playing and hud != null:
				SaveSystem.save_game(plot, player, SaveSystem.SAVE_PATH, manager, hauler, quests)
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			# Alt-tab pauses, rather than leaving the truck rolling.
			if playing and pause_menu != null and not get_tree().paused \
					and DisplayServer.get_name() != "headless":
				pause_game()

func _on_setting_changed(_key: StringName) -> void:
	_apply_all_settings()

func _apply_all_settings() -> void:
	var cam := player.camera
	cam.fov = float(Settings.value(&"fov"))
	var reach := float(Settings.value(&"view_distance"))
	cam.far = reach
	# Fog thick enough that the far plane is lost in haze, never a hard edge.
	environment.fog_density = clampf(1.1 / reach, 0.0016, 0.0075)
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

func _process(_delta: float) -> void:
	_update_sun()

func _physics_process(delta: float) -> void:
	if player != null and player.driving() and hauler != null:
		# The player rides the seat; the camera is a child of the player, so
		# this doubles as the driving camera.
		player.global_position = hauler.seat_transform().origin
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
			if hauler != null and not building:
				hud.log_message("unloaded %d item(s)" % hauler.unload())
		KEY_Z:
			if hauler != null and not building and hauler.unload_one():
				hud.log_message("dropped one (%d left)" % hauler.cargo_count())
		KEY_C:
			if hauler != null and not building:
				hauler.recover()
				hud.toast("Hauler recovered", UITheme.ACCENT)

func _toggle_vehicle() -> void:
	if hauler == null:
		hud.log_message("No hauler yet - it is sold at the Store, and spawns on a Hauler Pad")
		return
	if player.driving():
		player.exit_vehicle()
		hauler.driver = null
		player.global_position = hauler.global_position + hauler.global_transform.basis.x * 2.6 + Vector3(0, 1.0, 0)
		hud.log_message("left the hauler")
		return
	if player.global_position.distance_to(hauler.global_position) > 6.0:
		hud.log_message("too far from the hauler")
		return
	player.enter_vehicle(hauler)
	hauler.driver = player
	# Everything loose in the bed becomes part of the truck before it moves.
	var secured := hauler.secure_load()
	if secured > 0:
		hud.log_message("secured %d item(s) in the bed" % secured)
