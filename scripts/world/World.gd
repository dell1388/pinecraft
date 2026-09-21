class_name World
extends Node3D

## The game scene: terrain, forest, quarry, the player's plot, the sell depot,
## the player and the HUD, plus save/load and vehicle handling.

const MAP_HALF := 300.0
const DEPOT_POSITION := Vector3(0, 0, 70)
const STORE_POSITION := Vector3(-52, 0, 62)
const QUARRY_CENTRE := Vector3(-150, 0, -40)
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

var _rng := RandomNumberGenerator.new()
var _autosave_timer: float = AUTOSAVE_SECONDS

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

	if SaveSystem.has_save():
		if SaveSystem.load_game(plot, player, SaveSystem.SAVE_PATH, manager, _spawn_vehicle_for_load, quests):
			hud.log_message("save loaded")
	else:
		# A starting float, so the first sawmill is a few tree-loads away
		# rather than an hour of hauling.
		Economy.add_money(STARTING_MONEY)
		hud.log_message("start: $%d. Fell trees, bring the wood to the yard at z=%d and ask the shopkeep." % [
			STARTING_MONEY, int(DEPOT_POSITION.z)])
	set_physics_process(true)

# --- World construction ----------------------------------------------------

func _build_environment() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -38, 0)
	light.shadow_enabled = true
	light.light_energy = 1.1
	add_child(light)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.fog_enabled = true
	env.fog_density = 0.004
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
	# Everything that has to stand on the level.
	terrain.reserve_site(Vector3.ZERO, 56.0)
	terrain.reserve_site(DEPOT_POSITION, 16.0)
	terrain.reserve_site(STORE_POSITION, 14.0)
	terrain.reserve_site(QUARRY_CENTRE, 34.0)
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
func _build_forest() -> void:
	var species := [
		# Kept outside the largest plot tier so an expanded plot never swallows
		# the forest or leaves trees standing inside a factory.
		{"item": &"wood_pine", "ring": [62.0, 110.0], "work": 620.0,
			"radius": [0.30, 0.40], "height": [6.0, 8.5], "taper": 0.60, "branches": [4, 6]},
		{"item": &"wood_oak", "ring": [100.0, 180.0], "work": 1000.0,
			"radius": [0.38, 0.50], "height": [6.5, 9.0], "taper": 0.66, "branches": [5, 7]},
		{"item": &"wood_ironwood", "ring": [160.0, 280.0], "work": 1900.0,
			"radius": [0.44, 0.58], "height": [7.0, 10.0], "taper": 0.72, "branches": [6, 8]},
	]
	var per_species: int = maxi(1, tree_count / species.size())
	for i in species.size():
		var kind: Dictionary = species[i]
		var field := ResourceField.new()
		field.name = "Forest_%s" % kind.item
		field.quota = per_species
		field.min_spacing = 4.2
		field.refill_seconds = 6.0
		field.setup([kind], _build_tree,
			_on_ground(ResourceField.annulus(kind.ring[0], kind.ring[1])), _rng.randi())
		add_child(field)
		field.prefill()
		tree_fields.append(field)

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
	tree.seed_form(form_seed)
	tree.branch_count = rng.randi_range(int(kind.branches[0]), int(kind.branches[1]))
	tree.trunk_height = rng.randf_range(kind.height[0], kind.height[1])
	tree.trunk_radius = rng.randf_range(kind.radius[0], kind.radius[1])
	tree.trunk_taper = float(kind.taper)
	tree.work_per_m2 = float(kind.work)
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

func _make_player() -> Player:
	var p := Player.new()
	p.name = "Player"
	p.position = Vector3(0, 2.0, 12.0)
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

# --- Runtime ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if player != null and player.driving() and hauler != null:
		# The player rides the seat; the camera is a child of the player, so
		# this doubles as the driving camera.
		player.global_position = hauler.seat_transform().origin
		player.velocity = Vector3.ZERO
	if not autosave:
		return
	_autosave_timer -= delta
	if _autosave_timer <= 0.0:
		_autosave_timer = AUTOSAVE_SECONDS
		SaveSystem.save_game(plot, player, SaveSystem.SAVE_PATH, manager, hauler, quests)

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F5:
			hud.log_message("saved" if SaveSystem.save_game(
				plot, player, SaveSystem.SAVE_PATH, manager, hauler, quests) else "save failed")
		KEY_F9:
			hud.log_message("loaded" if SaveSystem.load_game(
				plot, player, SaveSystem.SAVE_PATH, manager, _spawn_vehicle_for_load, quests) else "no save found")
		KEY_F8:
			_new_game()
		KEY_V:
			_toggle_vehicle()
		KEY_X:
			if hauler != null:
				hud.log_message("unloaded %d item(s)" % hauler.unload())
		KEY_Z:
			if hauler != null and hauler.unload_one():
				hud.log_message("dropped one (%d left)" % hauler.cargo_count())
		KEY_C:
			if hauler != null:
				hauler.recover()

func _new_game() -> void:
	SaveSystem.delete_save()
	plot.clear_buildings()
	manager.despawn_all()
	PlayerState.reset()
	Economy.from_dict({})
	if hauler != null:
		hauler.queue_free()
		hauler = null
	player.global_position = Vector3(0, 2, 12)
	hud.log_message("new game")

func _toggle_vehicle() -> void:
	if hauler == null:
		hud.log_message("no hauler - buy one in the shop [U]")
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
	hud.log_message("driving - WASD, Space brake, X unload, Z drop one%s" % (
		"  (secured %d item(s))" % secured if secured > 0 else ""))
