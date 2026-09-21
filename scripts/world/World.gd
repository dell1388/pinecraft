class_name World
extends Node3D

## The game scene: terrain, forest, quarry, the player's plot, the sell depot,
## the player and the HUD, plus save/load and vehicle handling.

const MAP_HALF := 110.0
const DEPOT_POSITION := Vector3(0, 0, 54)
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
var depot: SellZone
var hauler: Hauler

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
	add_child(plot)

	_build_forest()
	_build_quarry()
	_build_depot()

	player = _make_player()
	add_child(player)
	player.manager = manager
	player.plot = plot

	build_system = BuildSystem.new()
	build_system.setup(plot, player.camera, player)
	add_child(build_system)
	player.build_system = build_system

	hud = GameHUD.new()
	hud.setup(player, plot, manager, self)
	add_child(hud)

	if SaveSystem.has_save():
		if SaveSystem.load_game(plot, player):
			hud.log_message("save loaded")
	else:
		# A starting float, so the first sawmill is a few tree-loads away
		# rather than an hour of hauling.
		Economy.add_money(STARTING_MONEY)
		hud.log_message("start: $%d. Fell trees, haul logs to the gold pad at z=%d." % [
			STARTING_MONEY, int(DEPOT_POSITION.z)])
	if PlayerState.owns_vehicle:
		spawn_vehicle()
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

func _build_terrain() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Terrain"
	ground.collision_layer = Layers.WORLD
	ground.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.85
	ground.physics_material_override = pm

	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(MAP_HALF * 2.0, 2.0, MAP_HALF * 2.0)
	cs.shape = box
	# Terrain top sits 5 cm below the plot slab, so the plot reads as a pad and
	# the two floors never fight over the same contact plane.
	cs.position = Vector3(0, -1.05, 0)
	ground.add_child(cs)

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mesh.mesh = bm
	mesh.position = cs.position
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.28, 0.16)
	mesh.material_override = mat
	ground.add_child(mesh)

	for spec in [
		[Vector3(0, 3.0, -MAP_HALF), Vector3(MAP_HALF * 2.0, 8.0, 2.0)],
		[Vector3(0, 3.0, MAP_HALF), Vector3(MAP_HALF * 2.0, 8.0, 2.0)],
		[Vector3(-MAP_HALF, 3.0, 0), Vector3(2.0, 8.0, MAP_HALF * 2.0)],
		[Vector3(MAP_HALF, 3.0, 0), Vector3(2.0, 8.0, MAP_HALF * 2.0)],
	]:
		var wcs := CollisionShape3D.new()
		var wb := BoxShape3D.new()
		wb.size = spec[1]
		wcs.shape = wb
		wcs.position = spec[0]
		ground.add_child(wcs)
	add_child(ground)

func _build_forest() -> void:
	var species := [
		# Kept outside the largest plot tier so an expanded plot never swallows
		# the forest or leaves trees standing inside a factory.
		{"item": &"wood_pine", "min_r": 52.0, "max_r": 68.0, "health": 100.0,
			"radius": [0.30, 0.40], "height": [6.0, 8.5], "taper": 0.60, "branches": 5},
		{"item": &"wood_oak", "min_r": 64.0, "max_r": 84.0, "health": 190.0,
			"radius": [0.38, 0.50], "height": [6.5, 9.0], "taper": 0.66, "branches": 6},
		{"item": &"wood_ironwood", "min_r": 80.0, "max_r": 104.0, "health": 420.0,
			"radius": [0.44, 0.58], "height": [7.0, 10.0], "taper": 0.72, "branches": 7},
	]
	for i in tree_count:
		var kind: Dictionary = species[i % species.size()]
		var angle := _rng.randf_range(0.0, TAU)
		var radius := _rng.randf_range(kind.min_r, kind.max_r)
		var tree := ChoppableTree.new()
		tree.manager = manager
		tree.plot_id = 0
		tree.max_health = float(kind.health)
		tree.wood_item = kind.item
		tree.branch_count = int(kind.branches)
		tree.trunk_height = _rng.randf_range(kind.height[0], kind.height[1])
		tree.trunk_radius = _rng.randf_range(kind.radius[0], kind.radius[1])
		tree.trunk_taper = float(kind.taper)
		tree.respawn_seconds = 35.0
		tree.position = Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		add_child(tree)

func _build_quarry() -> void:
	var ores := [
		{"item": &"ore_iron", "health": 140.0, "count": 4},
		{"item": &"ore_copper", "health": 230.0, "count": 4},
		{"item": &"ore_gold", "health": 520.0, "count": 3},
	]
	for i in rock_count:
		var kind: Dictionary = ores[i % ores.size()]
		var rock := OreRock.new()
		rock.manager = manager
		rock.plot_id = 0
		rock.ore_item = kind.item
		rock.max_health = float(kind.health)
		rock.ore_count = int(kind.count)
		rock.radius = _rng.randf_range(1.0, 1.6)
		rock.respawn_seconds = 40.0
		# Quarry is its own corner of the map, so mining is a trip.
		rock.position = Vector3(
			_rng.randf_range(-100.0, -56.0),
			0,
			_rng.randf_range(-34.0, 34.0) + float(i % 3) * 2.0)
		add_child(rock)

func _build_depot() -> void:
	depot = SellZone.new()
	depot.setup(manager)
	depot.extents = Vector3(8.0, 2.5, 8.0)
	depot.position = DEPOT_POSITION
	add_child(depot)

	var sign_mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(8.0, 0.4, 0.4)
	sign_mesh.mesh = bm
	sign_mesh.position = DEPOT_POSITION + Vector3(0, 3.2, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.78, 0.2)
	sign_mesh.material_override = mat
	add_child(sign_mesh)

func _make_player() -> Player:
	var p := Player.new()
	p.name = "Player"
	p.position = Vector3(0, 2.0, 12.0)
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

func spawn_vehicle() -> void:
	if hauler != null:
		return
	hauler = Hauler.new()
	hauler.setup(manager, 0)
	hauler.position = Vector3(10, 1.5, 16)
	add_child(hauler)

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
		SaveSystem.save_game(plot, player)

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F5:
			hud.log_message("saved" if SaveSystem.save_game(plot, player) else "save failed")
		KEY_F9:
			hud.log_message("loaded" if SaveSystem.load_game(plot, player) else "no save found")
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
