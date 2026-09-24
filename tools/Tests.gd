extends Node3D

## Headless integration tests for the whole game loop.
##   godot --headless --path . --fixed-fps 60 scenes/tests.tscn
##
## Each test builds a throwaway world, drives the real systems (no mocks) and
## asserts on observable state. Exit code is non-zero when anything fails.

var _checks: int = 0
var _failures: Array[String] = []
var _current: String = ""
var _lines: Array[String] = []

var world: Node3D
var manager: LooseItemManager
var plot: Plot

func _ready() -> void:
	Engine.max_fps = 0
	InputSetup.ensure()
	await _run_all()

func _run_all() -> void:
	_say("=== Pinecraft integration tests | Godot %s | %s ===" % [
		Engine.get_version_info().string,
		ProjectSettings.get_setting("physics/3d/physics_engine")])

	await _test(&"data integrity", test_data_integrity)
	await _test(&"deterministic daily prices", test_prices)
	await _test(&"felling drops the trunk as it grew", test_chop)
	await _test(&"branches and trunk are cut separately", test_limb_cutting)
	await _test(&"resource fields fill to a quota and stop", test_resource_field)
	await _test(&"terrain has biomes, rivers and roads", test_terrain)
	await _test(&"you can stand on the terrain anywhere", test_terrain_collision)
	await _test(&"a species only gets offered its own country", test_biome_pools)
	await _test(&"the land steps in terraces with no sheer plinths", test_terraces)
	await _test(&"caves are dug under enough hill, and you can walk into them", test_caves)
	await _test(&"greebled meshes face outward", test_greeble_winding)
	await _test(&"a full field retires far, untouched nodes", test_field_churn)
	await _test(&"things that fall through the ground come back up", test_resurface)
	await _test(&"traders pay a premium, caches pay once a day", test_trader_and_cache)
	await _test(&"round stock is drawn as octagons", test_octagonal_stock)
	await _test(&"bucking splits wood and conserves volume", test_bucking)
	await _test(&"a chunk is pulled out whole when the pull is enough", test_chunk_pull)
	await _test(&"hammering cracks a chunk apart piece by piece", test_chunk_cracking)
	await _test(&"the planker makes one big plank from a log", test_planker)
	await _test(&"the sander finishes wood and adds value", test_sander)
	await _test(&"crusher, smelter and refiner work ore down the line", test_ore_line)
	await _test(&"every material is worth its raw, pre and final values", test_material_values)
	await _test(&"stones are polished in the sander and faceted in the gem cutter", test_gem_line)
	await _test(&"islands, bridges and carved places", test_islands)
	await _test(&"belted lines of machines keep flowing without jamming", test_machine_lines)
	await _test(&"a tunnel mouth is a real opening", test_tunnel_mouth)
	await _test(&"workbench assembles from volumes", test_workbench)
	await _test(&"the yard buys what the player owns in it", test_sell_yard)
	await _test(&"orders pay out on delivery", test_quests)
	await _test(&"storage bin stores and dispenses", test_storage)
	await _test(&"a belt runs straight into a machine", test_conveyor_to_machine)
	await _test(&"belts come as ramps, borderless and stoppable", test_conveyor_options)
	await _test(&"belts carry by friction, and things on them can jam", test_conveyor_physics)
	await _test(&"splitter routes round-robin", test_splitter)
	await _test(&"filter sorts items by type", test_filter)
	await _test(&"building placement, cost and removal", test_building)
	await _test(&"buildings sit on the pad, not in it", test_buildings_sit_on_pad)
	await _test(&"plans fill with material and turn solid", test_schematic)
	await _test(&"save/load round-trip", test_save_load)
	await _test(&"the title screen reads the save without loading it", test_save_summary)
	await _test(&"settings coerce, persist and reset", test_settings)
	await _test(&"prompt keys are drawn as keycaps", test_prompt_keys)
	await _test(&"the compass points the right way", test_compass)
	await _test(&"the checklist follows what the player has done", test_tutorial)
	await _test(&"plot expansion raises bounds and cap", test_expansion)
	await _test(&"gear upgrades apply and charge", test_upgrades)
	await _test(&"the store sells boxes over a counter", test_store)
	await _test(&"carry rack limits and deposits", test_carry)
	await _test(&"lift and drag limits are weight limits", test_handling_limits)
	await _test(&"things are dragged by the point grabbed", test_drag_at_point)
	await _test(&"tools come from an inventory onto a hotbar", test_hotbar_tools)
	await _test(&"build mode edits placed buildings", test_build_edit)
	await _test(&"ownership is tracked and saved", test_ownership)
	await _test(&"hauler drives, carries and stays upright", test_hauler)
	await _test(&"the load in the bed is loose and real", test_hauler_loose_load)
	await _test(&"the hauler corners instead of sliding", test_hauler_grip)
	await _test(&"a parked hauler stays put", test_hauler_parked)
	await _test(&"a pad spawns one vehicle and replaces it", test_vehicle_pad)
	await _test(&"every vehicle is for sale and has its own pad", test_vehicle_catalogue)
	await _test(&"every vehicle settles, drives and carries", test_vehicle_fleet)
	await _test(&"the dump truck tips its load out", test_dump_truck)
	await _test(&"debug unlimited money", test_unlimited_money)
	await _test(&"winch and crane respect their power ratings", test_vehicle_rig)
	await _test(&"kill plane rescues fallen items", test_kill_plane)
	await _test(&"per-plot cap is enforced", test_cap)
	await _test(&"full automated base stays in budget", test_full_base)

	_say("")
	if _failures.is_empty():
		_say("PASS - %d checks" % _checks)
	else:
		_say("FAIL - %d of %d checks failed" % [_failures.size(), _checks])
		for f in _failures:
			_say("  * " + f)
	_write_log()
	get_tree().quit(0 if _failures.is_empty() else 1)

# --- Harness ---------------------------------------------------------------

func _say(text: String) -> void:
	print(text)
	_lines.append(text)

func _write_log() -> void:
	var f := FileAccess.open("res://test_results.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()

func _test(name: StringName, fn: Callable) -> void:
	# TEST_ONLY=word runs just the tests whose names contain it.
	var only := OS.get_environment("TEST_ONLY")
	if only != "" and not String(name).contains(only):
		return
	_current = String(name)
	var before := _failures.size()
	var checks_before := _checks
	_finished = false
	await fn.call()
	# A test that dies part way through - a parse error in what it exercises,
	# say - used to contribute fewer checks and still read as a pass, so each
	# one has to say it got to the end.
	if not _finished:
		_failures.append("%s: did not run to completion (%d checks in)" % [
			_current, _checks - checks_before])
	_teardown()
	var status := "ok  " if _failures.size() == before else "FAIL"
	_say("  [%s] %s" % [status, _current])

var _finished: bool = false

## Every test calls this as its last line.
func done() -> void:
	_finished = true

func check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append("%s: %s" % [_current, message])
	return condition

func check_eq(actual: Variant, expected: Variant, message: String) -> bool:
	return check(actual == expected, "%s (got %s, expected %s)" % [message, actual, expected])

func check_near(actual: float, expected: float, tolerance: float, message: String) -> bool:
	return check(absf(actual - expected) <= tolerance,
		"%s (got %.3f, expected %.3f +/- %.3f)" % [message, actual, expected, tolerance])

func step(frames: int = 1) -> void:
	for i in frames:
		await get_tree().physics_frame

## Fresh world with ground, an item manager and an empty plot.
func _setup(with_plot: bool = true) -> void:
	_teardown()
	Economy.from_dict({"money": 100000, "day": 1})
	PlayerState.reset()
	world = Node3D.new()
	add_child(world)
	StressWorld.build_ground(world, 90.0)
	manager = LooseItemManager.new()
	manager.per_plot_cap = 400
	world.add_child(manager)
	manager.register_plot(0, Vector3(0, 6, 0))
	if with_plot:
		plot = Plot.new()
		plot.setup(manager, 0)
		world.add_child(plot)

func _teardown() -> void:
	if world != null:
		world.queue_free()
		world = null
	manager = null
	plot = null

func spawn(item_id: StringName, pos: Vector3, dims: Dictionary = {}) -> LooseItem:
	return manager.spawn(item_id, Transform3D(Basis(), pos), 0, Vector3.ZERO, dims)

func loose_volume(item_id: StringName = &"") -> float:
	var total := 0.0
	for item in manager.free_items():
		if item_id == &"" or item.item_id == item_id:
			total += item.volume()
	return total

# --- Tests -----------------------------------------------------------------

func test_data_integrity() -> void:
	check(GameData.load_errors.is_empty(),
		"data tables have errors: %s" % ", ".join(GameData.load_errors))
	check(GameData.items.size() >= 10, "expected a real item table")
	check(GameData.recipes.size() >= 2, "expected a real assembly recipe table")
	var conversions := 0
	for m: MachineDef in GameData.machines.values():
		conversions += m.conversion.size()
	check(conversions >= 6, "expected a real conversion table across the machines")
	for def: ItemDef in GameData.items.values():
		check(def.density > 0.0, "item %s has no density" % def.id)
		# Store stock has no sale price on purpose: the yard will not buy it and
		# its shelf price comes from the track or building it delivers.
		if def.sellable:
			check(def.value_per_m3 > 0.0 or def.fixed_value > 0, "item %s has no price" % def.id)
		var dims := def.default_dims()
		check(Solid.volume(dims) > 0.0, "item %s has no volume" % def.id)
		check(def.mass_of(dims) > 0.0, "item %s weighs nothing" % def.id)
	for r: RecipeDef in GameData.recipes.values():
		check(not r.inputs.is_empty(), "recipe %s has no inputs" % r.id)
		check(GameData.items.has(r.output), "recipe %s has no output item" % r.id)
		check(r.seconds > 0.0, "recipe %s is instant" % r.id)
	for m: MachineDef in GameData.machines.values():
		check(not m.accepts.is_empty(), "machine %s accepts nothing" % m.id)
		if m.is_inline():
			check(m.tunnel.x > 0.3 and m.tunnel.y > 0.3, "machine %s has no tunnel mouth" % m.id)
			check(m.belt_speed > 0.2, "machine %s has a stopped belt" % m.id)
			if m.mode == MachineDef.MODE_PLANK or m.mode == MachineDef.MODE_SMELT:
				check(not m.conversion.is_empty(), "machine %s converts nothing" % m.id)
			continue
		check(m.intake_hole.x > 0.1 and m.intake_hole.y > 0.1, "machine %s has no intake hole" % m.id)
		check(m.outlet_hole.x > 0.1 and m.outlet_hole.y > 0.1, "machine %s has no outlet hole" % m.id)
		if m.mode != MachineDef.MODE_ASSEMBLE:
			check(not m.conversion.is_empty(), "machine %s converts nothing" % m.id)
			check(m.cross_section.x > 0.0 and m.cross_section.y > 0.0,
				"machine %s has no output cross-section" % m.id)
	for def: BuildingDef in GameData.buildings.values():
		check(def.cost > 0, "building %s is free" % def.id)
	done()

func test_prices() -> void:
	Economy.from_dict({"money": 0, "day": 7})
	var first := Economy.price_of(&"wood_pine")
	var again := Economy.price_of(&"wood_pine")
	check_eq(first, again, "price is not stable within a day")
	var day7_multiplier := Economy.price_multiplier(&"wood_oak")
	Economy.from_dict({"money": 0, "day": 8})
	var day8_multiplier := Economy.price_multiplier(&"wood_oak")
	Economy.from_dict({"money": 0, "day": 7})
	check_near(Economy.price_multiplier(&"wood_oak"), day7_multiplier, 0.0001,
		"price for a given day is not reproducible")
	check(absf(day8_multiplier - day7_multiplier) > 0.0001, "prices never change between days")
	# A day's prices must stay in a sane band, or the economy is meaningless.
	for row in Economy.market_rows():
		check(row.multiplier >= 0.35 and row.multiplier <= 2.4,
			"price multiplier out of band for %s" % row.name)
		check(row.typical >= 1, "price below 1 for %s" % row.name)
	# Volume pricing: twice the board is worth twice the money.
	var short_board := Solid.box(Vector3(0.3, 1.0, 0.3))
	var long_board := Solid.box(Vector3(0.3, 2.0, 0.3))
	var a := Economy.price_of(&"lumber_pine", short_board)
	var b := Economy.price_of(&"lumber_pine", long_board)
	check(absf(float(b) - float(a) * 2.0) <= 2.0,
		"price is not proportional to volume (%d vs %d)" % [a, b])
	done()

func test_chop() -> void:
	_setup()
	var tree := _make_tree(7.0, 0.34, 0.6, 4)
	world.add_child(tree)
	await step(2)
	check_eq(manager.active_count(), 0, "wood existed before chopping")

	var grown_volume := tree.wood_volume()
	tree.fell(Vector3(0, 0, 5))
	await step(2)

	# The trunk must arrive as one piece, exactly the shape it grew to - not as
	# a pile of pre-cut logs.
	check_eq(manager.active_count(), 1 + 4, "felling produced the wrong piece count")
	check(not tree.standing(), "the tree is still standing after being cut through")
	var trunk: LooseItem = null
	for item in manager.free_items():
		if trunk == null or item.volume() > trunk.volume():
			trunk = item
	check(trunk != null, "no trunk piece was spawned")
	if trunk != null:
		check_near(trunk.length(), 7.0, 0.001, "the felled trunk is not the height the tree grew to")
		check_near(float(trunk.dims.r0), 0.34, 0.001, "the felled trunk lost its base radius")
		check_near(float(trunk.dims.r1), 0.34 * 0.6, 0.001, "the felled trunk lost its taper")
		check(trunk.mass > 200.0, "a 7 m trunk should be far too heavy to pocket (%.0f kg)" % trunk.mass)
	check_near(loose_volume(), grown_volume, 0.0001,
		"felling did not conserve the tree's wood volume")

	# And it should topple rather than stand there.
	await step(90)
	if trunk != null and is_instance_valid(trunk):
		var upright: float = absf(trunk.global_transform.basis.y.dot(Vector3.UP))
		check(upright < 0.8, "the felled trunk never fell over (upright %.2f)" % upright)
	done()

## Spec: the player cuts through the individual cylinders the tree is made of.
## A branch comes off on its own; the trunk is severed at the height of the cut
## and what is below it keeps standing.
func test_limb_cutting() -> void:
	_setup()
	var tree := _make_tree(8.0, 0.34, 0.6, 4)
	world.add_child(tree)
	await step(2)
	var grown := tree.wood_volume()
	var branches_before := tree.branches.size()
	check_eq(branches_before, 4, "test tree did not grow its branches")

	# Aim at a branch: that branch alone comes off, and the tree stays up.
	var branch: Dictionary = tree.branches[0]
	var aim: Vector3 = tree.global_position + Vector3(0, float(branch.height), 0) \
		+ (branch.dir as Vector3) * float(branch.length) * 0.5
	check_eq(tree.limb_at(aim), 0, "aiming along a branch did not select that branch")
	var branch_volume := Solid.volume(Solid.cylinder(
		float(branch.radius), float(branch.radius) * 0.7, float(branch.length)))
	var swings := 0
	while tree.branches.size() == branches_before and swings < 200:
		tree.cut(34.0, aim, tree.global_position + Vector3(0, 0, 4))
		swings += 1
	await step(2)
	check_eq(tree.branches.size(), branches_before - 1, "cutting a branch did not take it off")
	check(swings > 1, "a branch came off in a single swing")
	check(tree.standing(), "cutting one branch felled the whole tree")
	check_near(loose_volume(), branch_volume, 0.0001, "the dropped branch is the wrong size")
	check_near(tree.wood_volume(), grown - branch_volume, 0.0001,
		"the tree did not lose exactly the branch it dropped")

	# Aim at the trunk, high up: everything above that line leaves and the
	# stump below it is still a tree.
	var high := tree.global_position + Vector3(0, 5.0, 0)
	check_eq(tree.limb_at(high), -1, "aiming at the trunk did not select the trunk")
	var trunk_swings := 0
	while tree.trunk_height > 7.9 and trunk_swings < 400:
		tree.cut(40.0, high, tree.global_position + Vector3(0, 0, 4))
		trunk_swings += 1
	await step(2)
	check(trunk_swings > 3, "a 0.3 m trunk was cut through in %d swings" % trunk_swings)
	check_near(tree.trunk_height, 5.0, 0.001, "the trunk was not severed at the height of the cut")
	check(tree.standing(), "severing the top of a trunk removed the whole tree")
	check_near(loose_volume() + tree.wood_volume(), grown, 0.0001,
		"cutting the trunk did not conserve wood")

	# Cut the stump through at the bottom and the tree is done.
	tree.cut(99999.0, tree.global_position + Vector3(0, 0.2, 0), tree.global_position + Vector3(0, 0, 4))
	await step(2)
	check(not tree.standing(), "cutting the base did not finish the tree")
	check_near(loose_volume(), grown, 0.0001, "the tree did not yield exactly what it grew")
	done()

## Spec: resources spawn procedurally in form and place up to a quota, and stop
## once the quota is reached.
func test_resource_field() -> void:
	_setup(false)
	var field := ResourceField.new()
	field.quota = 8
	field.min_spacing = 3.0
	field.refill_seconds = 0.4
	var forms: Array[Dictionary] = []
	var heights: Array[float] = []
	field.setup([{"h": 6.0}, {"h": 9.0}],
		func(kind: Dictionary, form_seed: int) -> Node3D:
			var rng := RandomNumberGenerator.new()
			rng.seed = form_seed
			var tree := _make_tree(rng.randf_range(4.0, float(kind.h)), 0.3, 0.6, 3)
			tree.seed_form(form_seed)
			heights.append(tree.trunk_height)
			return tree,
		ResourceField.annulus(10.0, 24.0), 4242)
	world.add_child(field)

	check_eq(field.prefill(), 8, "prefill did not reach the quota")
	check_eq(field.count(), 8, "field is not holding its quota")
	check(field.at_quota(), "field does not report being at quota")

	# Spawning stops dead at the quota, however long it runs.
	var spawned_at_quota := field.total_spawned
	await step(30)
	check_eq(field.total_spawned, spawned_at_quota, "the field kept spawning past its quota")

	# Form and place are both procedural.
	var unique_heights: Dictionary = {}
	for h in heights:
		unique_heights["%.3f" % h] = true
	check(unique_heights.size() > 1, "every tree in the field grew to the same height")
	for node in field.alive:
		var r: float = Vector2(node.position.x, node.position.z).length()
		check(r >= 9.99 and r <= 24.01, "a node landed outside the field's ring (r=%.1f)" % r)
	for i in field.alive.size():
		for j in range(i + 1, field.alive.size()):
			check(field.alive[i].position.distance_to(field.alive[j].position) >= 2.99,
				"two nodes spawned inside the minimum spacing")

	# Use one up and the field refills - back to the quota, never past it.
	(field.alive[0] as ChoppableTree).fell()
	await step(2)
	check_eq(field.count(), 7, "a felled tree was not released from the field")
	for i in 40:
		await step(4)
		if field.at_quota():
			break
	check_eq(field.count(), 8, "the field did not refill to its quota")
	done()

## Spec: a large simplistic polygonal map with several biomes, rivers that are
## sometimes fordable, and roads that are quicker to drive on.
func test_terrain() -> void:
	_setup(false)
	var land := Terrain.new()
	land.half_extent = 150.0
	land.noise_seed = 4242
	land.rivers = [{
		"width": 9.0, "depth": 3.0,
		"fords": [{"at": 100.0, "width": 24.0}],
		"path": [Vector3(-140, 0, -60), Vector3(0, 0, -20), Vector3(140, 0, 40)],
	}]
	land.roads = [[Vector3(-130, 0, -130), Vector3(-40, 0, -50), Vector3(40, 0, 40), Vector3(130, 0, 130)]]
	land.reserve_site(Vector3.ZERO, 40.0)
	world.add_child(land)
	await step(2)

	# The map is large, and the ground under a point is a real answer.
	check(land.half_extent * 2.0 >= 300.0, "the map is only %.0f m across" % (land.half_extent * 2.0))
	var probe := land.height_at(20.0, -30.0)
	check(is_finite(probe), "the ground has no height at a sampled point")

	# Several biomes, not one.
	var seen: Dictionary = {}
	var step_m := 12.0
	var x := -land.half_extent + step_m
	while x < land.half_extent - step_m:
		var z := -land.half_extent + step_m
		while z < land.half_extent - step_m:
			seen[land.biome_at(x, z)] = true
			z += step_m
		x += step_m
	check(seen.size() >= 3, "the map only has %d biome(s)" % seen.size())
	for biome in seen:
		check(land.biome_name(biome) != "", "a biome has no name")

	# The land is not flat, and it is quantised into facets.
	var lowest := INF
	var highest := -INF
	for i in 400:
		var px := randf_range(-land.half_extent + 10.0, land.half_extent - 10.0)
		var pz := randf_range(-land.half_extent + 10.0, land.half_extent - 10.0)
		var h := land.height_at(px, pz)
		lowest = minf(lowest, h)
		highest = maxf(highest, h)
	check(highest - lowest > 5.0, "the map has only %.1f m of relief" % (highest - lowest))

	# The build site is level, so a factory floor is never on a slope.
	var site_heights: Array[float] = []
	for angle in [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]:
		site_heights.append(land.height_at(cos(angle) * 25.0, sin(angle) * 25.0))
	for h in site_heights:
		check_near(h, 0.0, 0.001, "the reserved build site is not level")

	# The river is cut below the water line, and its ford is shallow enough to
	# drive through while the rest of it is not.
	var deep := land.water_depth(-70.0, -40.0)
	check(deep > 1.0, "the river is only %.1f m deep at its channel" % deep)
	var ford_point: Variant = _ford_point(land)
	check(ford_point != null, "the river has no fordable stretch")
	if ford_point != null:
		var shallow: float = land.water_depth((ford_point as Vector3).x, (ford_point as Vector3).z)
		check(shallow < 0.8, "the ford is %.1f m deep, too deep to drive" % shallow)
		check(shallow > 0.0, "the ford is not water at all")

	# The road is marked where it runs and nowhere else.
	check(land.is_road(40.0, 40.0), "the road is not marked along its own line")
	check(not land.is_road(-120.0, 110.0), "open ground far off the road is marked as road")

	# And it is flat across its width. A road blended in from the centre-line is
	# cambered, which is a road you slide off rather than drive on.
	#
	# Measured only where the land around the road actually slopes: over flat
	# ground every grading scheme looks identical, so a test that sampled the
	# levelled build site would pass whatever the code did.
	# Measured in two bands, because they matter differently. The truck is
	# 2.6 m wide, so what can tip it is the fall across its own track; the
	# carriageway edge only has to stay sane. Measured only where the land
	# around the road actually slopes - over flat ground every grading scheme
	# looks identical, so sampling the levelled build site would prove nothing.
	var worst_track := 0.0
	var worst_edge := 0.0
	var samples := 0
	var sloped := 0
	var across_dir := Vector3(1, 0, -1).normalized()
	for step in range(-130, 131, 4):
		var along := float(step)
		if absf(along) < 55.0:
			continue
		var centre := Vector3(along, 0.0, along)
		if not land.is_road(centre.x, centre.z):
			continue
		# The map is an island; where this small test map's road runs down
		# into the shore it is going into the sea, not over a hill.
		if land.half_extent - maxf(absf(centre.x), absf(centre.z)) < Terrain.SHORE_WIDTH:
			continue
		var middle := land.height_at(centre.x, centre.z)
		if absf(land.height_at(centre.x + across_dir.x * 26.0,
				centre.z + across_dir.z * 26.0) - middle) > 0.5:
			sloped += 1
		# Cross-fall is the difference between the two sides at equal distance.
		# Comparing either side against the centre instead would count the
		# road's gradient *along* its length, and a road climbing a hill is
		# perfectly drivable - it is the sideways tilt that throws a truck.
		for offset in [1.5, 3.0, 6.0]:
			var out := float(offset)
			var left_x := centre.x + across_dir.x * out
			var left_z := centre.z + across_dir.z * out
			var right_x := centre.x - across_dir.x * out
			var right_z := centre.z - across_dir.z * out
			if not land.is_road(left_x, left_z) or not land.is_road(right_x, right_z):
				continue
			var fall := absf(land.height_at(left_x, left_z) - land.height_at(right_x, right_z))
			if out <= 3.0:
				worst_track = maxf(worst_track, fall)
			else:
				worst_edge = maxf(worst_edge, fall)
			samples += 1
	check(sloped > 3,
		"the test road only crosses %d sloping spots, so camber cannot be measured here" % sloped)
	check(samples > 10, "only %d points sampled across the carriageway" % samples)
	check(worst_track < 0.25,
		"the road tilts %.2f m across the truck's own track - that will throw it sideways" % worst_track)
	check(worst_edge < 0.8,
		"the carriageway tilts %.2f m from edge to edge" % worst_edge)

	# And dropping a point onto the ground puts it on the ground.
	var dropped := land.place(Vector3(40.0, 99.0, -70.0), 0.5)
	check_near(dropped.y, land.height_at(40.0, -70.0) + 0.5, 0.001,
		"placing a point on the ground missed the ground")
	done()

## The land has to be solid, not just queryable. `test_terrain` only ever asked
## it questions; this one stands on it.
func test_terrain_collision() -> void:
	_teardown()
	Economy.from_dict({"money": 1000, "day": 1})
	PlayerState.reset()
	world = Node3D.new()
	add_child(world)                       # deliberately no flat ground under it
	manager = LooseItemManager.new()
	world.add_child(manager)
	manager.register_plot(0, Vector3(0, 6, 0))

	var land := Terrain.new()
	land.half_extent = 120.0
	land.noise_seed = 4242
	land.reserve_site(Vector3.ZERO, 30.0)
	world.add_child(land)
	await step(4)

	# A ray fired straight down has to find the ground, on the levelled pad and
	# out in open country alike.
	var space := world.get_world_3d().direct_space_state
	var probes := [Vector3(0, 0, 0), Vector3(20, 0, 14), Vector3(45, 0, -38),
		Vector3(-70, 0, 55), Vector3(95, 0, 95), Vector3(-100, 0, -20)]
	var missed: Array[String] = []
	for probe in probes:
		var expected := land.height_at(probe.x, probe.z)
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(probe.x, expected + 60.0, probe.z),
			Vector3(probe.x, expected - 30.0, probe.z), Layers.WORLD)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			missed.append("(%.0f, %.0f)" % [probe.x, probe.z])
			continue
		check_near(float(hit.position.y), expected, 0.4,
			"the ground at (%.0f, %.0f) is not where height_at says it is" % [probe.x, probe.z])
	check(missed.is_empty(), "nothing solid under %s" % ", ".join(missed))

	# The same winding decides which way the land faces the camera, which a
	# headless run cannot see. Check the winding itself rather than the normals
	# the mesh carries: culling and collision both read the vertex order, and
	# the stored normals are computed separately - under the original bug they
	# pointed up quite happily while every face was inside out.
	#
	# Godot's front face is clockwise seen from the front, which for ground
	# means (v1 - v0) x (v2 - v0) points *down*.
	var mesh_instance: MeshInstance3D = null
	for child in land.get_children():
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh is ArrayMesh:
			mesh_instance = mi
			break
	check(mesh_instance != null, "the terrain built no mesh")
	if mesh_instance != null:
		var arrays: Array = (mesh_instance.mesh as ArrayMesh).surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		check(points.size() >= 3, "the terrain mesh has no triangles")
		var inside_out := 0
		var total := points.size() / 3
		for t in total:
			var v0 := points[t * 3]
			var wound := (points[t * 3 + 1] - v0).cross(points[t * 3 + 2] - v0)
			if wound.y > 0.0:
				inside_out += 1
		check_eq(inside_out, 0,
			"%d of %d terrain faces are wound inside out - nothing to stand on, and invisible from above" % [
				inside_out, total])

	# And something dropped on it has to stop, rather than fall forever.
	var dropped := manager.spawn(&"ore_iron",
		Transform3D(Basis(), Vector3(45, land.height_at(45, -38) + 6.0, -38)), 0,
		Vector3.ZERO, Solid.cube(0.05))
	check(dropped != null, "could not spawn a test piece")
	var floor_y := land.height_at(45, -38)
	for i in 240:
		await step(1)
		if dropped.sleeping or dropped.linear_velocity.length() < 0.05:
			break
	check(dropped.global_position.y > floor_y - 1.0,
		"a piece dropped off the plot fell through the land (y=%.1f, ground %.1f)" % [
			dropped.global_position.y, floor_y])
	done()

## Different biomes grow different trees, which only works if a species is
## offered ground it actually belongs on.
func test_biome_pools() -> void:
	_teardown()
	world = Node3D.new()
	add_child(world)
	var land := Terrain.new()
	land.half_extent = 150.0
	land.noise_seed = 4242
	land.roads = [[Vector3(0, 0, -120), Vector3(0, 0, 120)]]
	land.reserve_site(Vector3(0, 0.45, 0), 40.0)
	world.add_child(land)
	await step(2)

	var wanted := [Terrain.Biome.WOODLAND, Terrain.Biome.TAIGA]
	var pool := land.points_in_biomes(wanted)
	check(pool.size() > 0, "no ground at all for woodland or taiga")
	# Counted over the whole pool, then reported once. A check per point would
	# bury the suite in a couple of hundred identical lines.
	var wrong_biome := 0
	var on_road := 0
	var in_water := 0
	var on_site := 0
	var off_ground := 0
	for point in pool:
		if not wanted.has(int(land.biome_at(point.x, point.z))):
			wrong_biome += 1
		if land.is_road(point.x, point.z):
			on_road += 1
		if land.water_depth(point.x, point.z) > 0.0:
			in_water += 1
		if Vector2(point.x, point.z).length() <= 40.0:
			on_site += 1
		if absf(point.y - land.height_at(point.x, point.z)) > 0.001:
			off_ground += 1
	check_eq(off_ground, 0, "%d pool points are not at ground height" % off_ground)
	check_eq(wrong_biome, 0, "%d points were offered in the wrong biome" % wrong_biome)
	check_eq(on_road, 0, "%d points were offered on a road" % on_road)
	check_eq(in_water, 0, "%d points were offered to a dry species under water" % in_water)
	check_eq(on_site, 0, "%d points were offered inside a build site" % on_site)

	# Asking for a different biome gets different ground.
	var desert := land.points_in_biomes([Terrain.Biome.DESERT])
	var overlap := 0
	for point in desert:
		if wanted.has(int(land.biome_at(point.x, point.z))):
			overlap += 1
	check_eq(overlap, 0, "the desert pool included woodland")

	# A species allowed to stand in shallow water gets offered more of a wet
	# biome than a dry one does - which is how the swamp keeps its willows.
	var dry := land.points_in_biomes([Terrain.Biome.SWAMP])
	var wet := land.points_in_biomes([Terrain.Biome.SWAMP], 2, 0.7)
	check(wet.size() >= dry.size(),
		"allowing shallow water offered fewer spots (%d) than dry land (%d)" % [
			wet.size(), dry.size()])
	done()

## Spec: the land is faceted, and so is the wood. Trunks, branches and felled
## logs are octagons, not smooth cylinders.
func test_octagonal_stock() -> void:
	_setup()
	check_eq(Tuning.ROUND_SIDES, 8, "round stock is not octagonal")

	var log_piece := spawn(&"wood_pine", Vector3(0, 1, 0), Solid.cylinder(0.3, 0.25, 2.0))
	await step(2)
	var sides := 0
	for child in log_piece.get_children():
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh is CylinderMesh:
			sides = (mi.mesh as CylinderMesh).radial_segments
	check_eq(sides, 8, "a felled log is drawn with %d sides" % sides)

	# The collider is the same octagon the log is drawn as: a true cylinder
	# lying on its side sinks into moving bodies under Jolt.
	var shape: ConvexPolygonShape3D = null
	for child in log_piece.get_children():
		var cs := child as CollisionShape3D
		if cs != null:
			shape = cs.shape as ConvexPolygonShape3D
	check(shape != null, "the log has no octagonal collider")
	if shape != null:
		check_eq(shape.points.size(), 16, "the log collider is not an eight-sided prism")
		var widest := 0.0
		for p in shape.points:
			widest = maxf(widest, Vector2(p.x, p.z).length())
		check_near(widest, 0.3, 0.001, "the collider corners are not at the full radius")

	var tree := _make_tree(7.0, 0.34, 0.6, 3)
	world.add_child(tree)
	await step(2)
	var faceted := 0
	var round_bits := 0
	for child in tree.get_children():
		var mi := child as MeshInstance3D
		if mi == null or not (mi.mesh is CylinderMesh):
			continue
		if (mi.mesh as CylinderMesh).radial_segments == 8:
			faceted += 1
		else:
			round_bits += 1
	check(faceted > 0, "the tree drew no octagonal parts")
	check_eq(round_bits, 0, "%d parts of the tree are still round" % round_bits)
	done()

## Walks the river looking for the shallow stretch the ford should have made.
func _ford_point(land: Terrain) -> Variant:
	var a := Vector3(-140, 0, -60)
	var b := Vector3(0, 0, -20)
	var c := Vector3(140, 0, 40)
	for i in 400:
		var t := float(i) / 400.0
		var point := a.lerp(b, t * 2.0) if t < 0.5 else b.lerp(c, (t - 0.5) * 2.0)
		var d := land.water_depth(point.x, point.z)
		if d > 0.0 and d < 0.8:
			return point
	return null

func test_bucking() -> void:
	_setup()
	var player := _make_player()
	world.add_child(player)
	await step(2)
	player.select_slot(0)   # the rusty axe

	var trunk := spawn(&"wood_pine", Vector3(0, 1.0, 0), Solid.cylinder(0.34, 0.20, 7.0))
	var start_volume := trunk.volume()
	check(start_volume > 0.5, "test trunk is too small to be interesting")

	# One swing does not cut a 0.34 m trunk in half.
	player._buck(trunk)
	check_eq(manager.active_count(), 1, "a single swing split a full trunk")
	check(trunk.cut_progress > 0.0, "the swing did no work")

	# Keep swinging until it gives.
	var swings := 1
	while manager.active_count() == 1 and swings < 60:
		player._swing_cd = 0.0
		player._buck(trunk)
		swings += 1
	await step(4)
	check_eq(manager.active_count(), 2, "bucking never split the trunk (%d swings)" % swings)
	check(swings > 3, "a full trunk should take several swings, took %d" % swings)
	check_near(loose_volume(), start_volume, 0.0001, "bucking did not conserve volume")
	var lengths: Array[float] = []
	for item in manager.free_items():
		lengths.append(item.length())
	check_near(lengths[0] + lengths[1], 7.0, 0.001, "the two halves do not add up to the trunk")

	# Short offcuts cannot be split forever.
	var stub := spawn(&"wood_pine", Vector3(6, 1.0, 0), Solid.cylinder(0.2, 0.2, 0.5))
	var before := manager.active_count()
	for i in 20:
		player._swing_cd = 0.0
		player._buck(stub)
	await step(2)
	check_eq(manager.active_count(), before, "a piece under the minimum length was still split")
	done()

## Spec: disgorging a chunk needs a pull of its mass plus the buried share of
## its mass again. Under that, it does not move.
func test_chunk_pull() -> void:
	_setup()
	var rock := OreRock.new()
	rock.manager = manager
	rock.ore_item = &"ore_iron"
	rock.embed = 0.5
	rock.volume = 0.4
	world.add_child(rock)
	await step(2)

	var density := rock.density()
	check_near(rock.mass(), density * 0.4, 0.001, "chunk mass is not density times volume")
	check_near(rock.pull_required(), rock.mass() * 1.5, 0.001,
		"pull needed is not mass plus half of it again at 50%% embedment")

	# A pull short of the requirement does nothing at all.
	check(rock.try_free(rock.pull_required() - 1.0) == null, "an under-strength pull freed the chunk")
	check(not rock.consumed(), "a failed pull still took the chunk")
	check_eq(manager.active_count(), 0, "a failed pull dropped ore anyway")

	# Enough pull takes the whole thing, and the whole thing is all of it.
	var freed := rock.try_free(rock.pull_required())
	check(freed != null, "a pull at the requirement did not free the chunk")
	check(rock.consumed(), "freeing the chunk did not clear it from the ground")
	check_eq(manager.active_count(), 1, "freeing a chunk should give exactly one piece")
	if freed != null:
		check_near(freed.volume(), 0.4, 0.0001, "the freed piece is not the whole chunk")
		check_near(freed.mass, density * 0.4, 0.01, "the freed piece weighs the wrong amount")

	# Deeper burial means a harder pull for the same rock.
	var deep := OreRock.new()
	deep.manager = manager
	deep.ore_item = &"ore_iron"
	deep.embed = 0.8
	deep.volume = 0.4
	world.add_child(deep)
	await step(2)
	check(deep.pull_required() > rock.pull_required(),
		"a chunk buried deeper did not need a harder pull")
	done()

## Spec: a hammer opens cracks at random that deepen until the chunk breaks
## apart, and a heavier hammer cracks faster.
func test_chunk_cracking() -> void:
	_setup()
	var rock := OreRock.new()
	rock.manager = manager
	rock.ore_item = &"ore_iron"
	rock.embed = 0.5
	rock.volume = 2.0
	rock.seed_form(99)
	world.add_child(rock)
	await step(2)
	var started_with := rock.volume

	# It takes real work, and it is not free the first time.
	rock.strike(3.0)
	check(rock.cracks.size() >= 1, "a blow opened no crack")
	check(rock.worst_crack() > 0.0 and rock.worst_crack() < 1.0,
		"one blow with a light hammer went straight through a 2 m3 chunk")

	# Keep hammering: the chunk sheds pieces rather than vanishing.
	var blows := 1
	while not rock.consumed() and blows < 4000:
		rock.strike(3.0)
		blows += 1
	await step(4)
	check(blows > 10, "a 2 m3 chunk broke up in %d blows" % blows)
	check(rock.consumed(), "the chunk never broke up")
	check(manager.active_count() >= 2, "breaking a chunk up gave only %d piece(s)" %
		manager.active_count())
	check_near(loose_volume(), started_with, 0.0001,
		"breaking the chunk up did not conserve its ore")

	# A heavier head does the same job in fewer blows.
	var heavy := OreRock.new()
	heavy.manager = manager
	heavy.ore_item = &"ore_iron"
	heavy.embed = 0.5
	heavy.volume = 2.0
	heavy.seed_form(99)
	world.add_child(heavy)
	await step(2)
	var heavy_blows := 0
	while not heavy.consumed() and heavy_blows < 4000:
		heavy.strike(20.0)
		heavy_blows += 1
	check(heavy_blows < blows, "a 20 kg hammer took %d blows against a 3 kg hammer's %d" % [
		heavy_blows, blows])
	done()

func _inline(id: StringName, pos: Vector3 = Vector3.ZERO) -> InlineMachine:
	var m := InlineMachine.new()
	m.setup_machine(manager, GameData.building(id), 0)
	m.position = pos
	world.add_child(m)
	return m

## Puts a piece on a machine's in-feed lip, lying along the belt.
func _feed(m: InlineMachine, id: StringName, dims: Dictionary = {}) -> LooseItem:
	var at := m.global_transform * Vector3(0, 0.6, m.length * 0.5 - 0.35)
	return manager.spawn(id, Transform3D(m.global_transform.basis * LooseItem.lying_basis(0.0), at),
		0, Vector3.ZERO, dims, true)

func _through(m: InlineMachine, item: LooseItem, frames: int = 600) -> bool:
	for i in frames:
		await step(1)
		if not is_instance_valid(item) or item.state == LooseItem.State.POOLED:
			return false
		if (m.global_transform.affine_inverse() * item.global_position).z < -m.canopy_length() * 0.5 - 0.1:
			return true
	return false

## Spec from play-testing: machines are tunnels on a belt. A log rides in and
## comes out as ONE big plank, as long as the log - not a heap of little ones.
func test_planker() -> void:
	_setup()
	var m := _inline(&"sawmill")
	await step(3)
	check(m.canopy_length() > 2.0, "the planker has no tunnel")
	var log_piece := _feed(m, &"wood_pine", Solid.cylinder(0.26, 0.22, 3.0))
	var log_volume := log_piece.volume()
	var out: bool = await _through(m, log_piece)
	check(out, "the log never came out of the far end")
	check_eq(m.total_processed, 1, "the planker processed %d pieces" % m.total_processed)
	check_eq(log_piece.item_id, &"lumber_pine", "the log came out as %s" % log_piece.item_id)
	check_eq(manager.active_count(), 1, "one log made %d pieces" % manager.active_count())
	var size: Vector3 = log_piece.dims.get("size", Vector3.ZERO)
	check_near(size.y, 3.0, 0.001, "the plank is not as long as the log")
	check(size.x > 0.35 and size.z > 0.15, "the plank is thin: %s" % str(size))
	check(size.x > size.z * 1.5, "that is a beam, not a plank: %s" % str(size))
	check(log_piece.volume() < log_volume, "milling made wood out of nothing")
	check(Economy.price_of(&"lumber_pine", log_piece.dims) > Economy.price_of(&"wood_pine", Solid.cylinder(0.26, 0.22, 3.0)),
		"a plank is worth less than the log it came from")
	check(not log_piece.freeze and log_piece.state == LooseItem.State.FREE, "the plank is not a free body")
	done()

## The sander finishes wood - logs or planks - and finished wood sells for more.
## It works on each piece once, and lets what it does not work on through.
func test_sander() -> void:
	_setup()
	var m := _inline(&"sander")
	await step(3)
	var dims := Solid.cylinder(0.2, 0.18, 2.0)
	var raw_price := Economy.price_of(&"wood_oak", dims)
	var log_piece := _feed(m, &"wood_oak", dims)
	check(await _through(m, log_piece), "the log never came through the sander")
	check(Solid.has_finish(log_piece.dims, &"sanded"), "the log came out unsanded")
	check(Economy.price_of(log_piece.item_id, log_piece.dims) > raw_price, "sanding added no value")
	check(log_piece.display_name().begins_with("Sanded"), "a sanded log is not called sanded")
	var ore := _feed(m, &"ore_iron")
	check(await _through(m, ore), "the sander stopped ore riding through")
	check_eq(ore.item_id, &"ore_iron", "the sander changed ore")
	check(not Solid.has_finish(ore.dims, &"sanded"), "the sander sanded ore")
	check_eq(m.total_processed, 1, "the sander counted work it did not do")

	# A sanded log planked is a sanded plank, and the finish is saved.
	var planker := _inline(&"sawmill", Vector3(6, 0, 0))
	await step(3)
	var again := _feed(planker, log_piece.item_id, log_piece.dims)
	check(await _through(planker, again), "the sanded log did not get through the planker")
	check(Solid.has_finish(again.dims, &"sanded"), "planking lost the sanding")
	var round_trip := Solid.from_dict(JSON.parse_string(JSON.stringify(Solid.to_dict(again.dims))))
	check(Solid.has_finish(round_trip, &"sanded"), "the finish does not survive a save")
	done()

## Spec: each material has a raw value, a value after the first step and a
## final value along its processing path - per m3 of what was dug or felled.
## Checked through the same shapes the machines make, so the table is what the
## yard actually pays. And the oddities are there: not everything gains.
func test_material_values() -> void:
	_setup()
	var smelt: MachineDef = GameData.machines[&"furnace"]
	var cut: MachineDef = GameData.machines[&"gem_cutter"]
	var dips := 0
	var growth := 0.0
	check(GameData.materials.size() >= 30, "only %d materials priced" % GameData.materials.size())
	for id in GameData.materials:
		var m: Dictionary = GameData.materials[id]
		var raw_def := GameData.item(StringName(m.raw_item))
		var fin_def := GameData.item(StringName(m.final_item))
		var raw := 0.0
		var pre := 0.0
		var fin := 0.0
		match String(m.path):
			"wood":
				var log_dims := Solid.cylinder(0.3, 0.26, 2.0)
				var v := Solid.volume(log_dims)
				raw = raw_def.base_value_of(log_dims) / v
				var sanded := Solid.with_finish(log_dims, &"sanded")
				pre = raw_def.base_value_of(sanded) / v
				var r := 0.28
				var plank := Solid.keep_finish(sanded, Solid.box(Vector3(r * 1.8, 2.0, r * 0.8)))
				fin = fin_def.base_value_of(plank) / v
			"metal":
				var ore := Solid.cube(0.5)
				var v2 := Solid.volume(ore)
				raw = raw_def.base_value_of(ore) / v2
				var bar := Solid.box(Vector3(1, 1, v2 * smelt.yield_share))
				pre = fin_def.base_value_of(bar) / v2
				fin = fin_def.base_value_of(Solid.with_finish(bar, &"refined")) / v2
			"gem":
				var rough := Solid.cube(0.3)
				var v3 := Solid.volume(rough)
				raw = raw_def.base_value_of(rough) / v3
				var polished := Solid.with_finish(rough, &"polished")
				pre = raw_def.base_value_of(polished) / v3
				var r0 := pow(v3 * cut.yield_share / 1.649, 1.0 / 3.0)
				var jewel := Solid.keep_finish(polished, Solid.cylinder(r0, r0 * 0.5, r0 * 0.9))
				fin = fin_def.base_value_of(jewel) / v3
		# The wood check uses a plank from the log's mean radius, as the planker does.
		var tol := 0.02
		check_near(raw / float(m.raw), 1.0, tol, "%s raw value" % id)
		check_near(pre / float(m.pre), 1.0, tol, "%s value after the first step" % id)
		check_near(fin / float(m.final), 1.0, tol, "%s final value" % id)
		if float(m.pre) <= float(m.raw) or float(m.final) <= float(m.pre):
			dips += 1
		growth += float(m.final) / float(m.raw)
	check(dips >= 5, "only %d materials break the pattern" % dips)
	check(growth / float(GameData.materials.size()) > 1.8, "processing adds too little on the whole")
	# Each new stone and metal is in the game, with a path to its end.
	for id in [&"ore_tungsten", &"ore_zinc", &"gem_emerald", &"gem_jade", &"ore_magnetite", &"gem_diamond"]:
		check(GameData.item(id) != null, "%s is missing" % id)
		check(not GameData.material_for(id).is_empty(), "%s has no value path" % id)
	done()

## Rough stone > sander (polished) > gem cutter (a faceted jewel).
func test_gem_line() -> void:
	_setup()
	var sander := _inline(&"sander")
	var cutter := _inline(&"gem_cutter", Vector3(6, 0, 0))
	await step(3)
	# Small enough for the cutter's 0.8 x 0.6 mouth.
	var stone := _feed(sander, &"gem_emerald", Solid.cube(0.12))
	var volume := stone.volume()
	var raw_price := Economy.price_of(stone.item_id, stone.dims)
	check(await _through(sander, stone), "the stone never came through the sander")
	check(Solid.has_finish(stone.dims, &"polished"), "the sander did not polish the stone")
	check(not Solid.has_finish(stone.dims, &"sanded"), "the stone was sanded like wood")
	check(stone.display_name().begins_with("Polished"), "a polished stone is called %s" % stone.display_name())
	var polished_price := Economy.price_of(stone.item_id, stone.dims)
	check(polished_price >= raw_price, "polishing an emerald lost value")
	var again := _feed(cutter, stone.item_id, stone.dims)
	check(await _through(cutter, again), "the stone never came through the gem cutter")
	check_eq(again.item_id, &"jewel_emerald", "the cutter made %s" % again.item_id)
	check_eq(again.dims.get("shape"), Solid.CYLINDER, "a jewel is not faceted round")
	check_near(again.volume(), volume * cutter.machine_def.yield_share, 0.0001, "the jewel is the wrong size")
	check(Solid.has_finish(again.dims, &"polished"), "cutting lost the polish")
	check(Economy.price_of(again.item_id, again.dims) > polished_price * 2.0, "a cut emerald is not worth the cutting")
	# The gem cutter leaves ore alone; the crusher leaves stones alone.
	var ore := _feed(cutter, &"ore_iron", Solid.cube(0.2))
	check(await _through(cutter, ore), "ore did not ride through the cutter")
	check_eq(ore.item_id, &"ore_iron", "the cutter changed ore")
	done()

## Spec: a 2.5 km map of islands with bridges between, and places hidden in it.
## Checked on a small map built the same way.
func test_islands() -> void:
	_setup(false)
	var land := Terrain.new()
	land.half_extent = 420.0
	land.noise_seed = 4242
	land.islands = [
		{"centre": Vector2(-190, 0), "radius": 170.0},
		{"centre": Vector2(200, 0), "radius": 150.0, "wet": -0.3},
	]
	land.roads = [{"bridge": true, "path": [Vector3(-260, 0, 0), Vector3(280, 0, 0)]}]
	land.features = [{"name": "Vale", "kind": "valley", "centre": Vector2(-200, 90), "radius": 30.0,
		"gap": PI * 0.5, "floor": 6.0}]
	world.add_child(land)
	await step(2)
	# Sea between the islands, deep enough that only a bridge crosses it.
	check(land.height_at(5.0, 60.0) < -4.0, "there is no sea between the islands (%.1f m)" % land.height_at(5.0, 60.0))
	check(land.height_at(-190.0, -60.0) > Terrain.WATER_LEVEL, "the first island is under water")
	check(land.height_at(260.0, 0.0) > Terrain.WATER_LEVEL, "the second island is under water")
	check(land.height_at(410.0, 400.0) <= Terrain.WATER_LEVEL, "the corners of the map are land")
	# The road asked for a bridge over the water, from dry road to dry road.
	check(land.bridges.size() >= 1, "the road across the strait has no bridge")
	var sea_bridge: Dictionary = {}
	for b in land.bridges:
		if float(b.span) > 40.0:
			sea_bridge = b
	check(not sea_bridge.is_empty(), "no bridge spans the strait")
	if not sea_bridge.is_empty():
		var ends := land.bridge_ends(sea_bridge)
		check((ends[0] as Vector3).y > Terrain.WATER_LEVEL and (ends[1] as Vector3).y > Terrain.WATER_LEVEL,
			"a bridge ends in the water: %s" % str(ends))
		var bridge := Bridge.new()
		bridge.setup(ends[0], ends[1], land)
		world.add_child(bridge)
		await step(2)
		# Something dropped on the middle of the deck stays on it.
		var mid: Vector3 = (ends[0] as Vector3).lerp(ends[1], 0.5)
		var deck := bridge.deck_height(0.5)
		check(deck > Terrain.WATER_LEVEL + 0.5, "the deck is not clear of the water")
		var crate := manager_free_crate(Vector3(mid.x, deck + 1.0, mid.z))
		await step(90)
		check(crate.global_position.y > deck - 0.1, "a crate fell through the bridge deck (y %.2f, deck %.2f)" % [crate.global_position.y, deck])
		check(bridge.over_deck(crate.global_position), "the crate slid off the deck")
	# The valley: a flat floor walled in by a ridge, with one way in.
	var floor_points := land.points_in_feature("Vale")
	check(floor_points.size() > 10, "nothing can grow in the valley")
	var wall := land.height_at(-200.0 - 55.0, 90.0)
	check(wall > land.height_at(-200.0, 90.0) + 15.0, "the valley has no ridge round it (%.1f)" % wall)
	check(land.height_at(-200.0, 90.0 + 55.0) < land.height_at(-200.0, 90.0) + 3.0, "the valley has no way in")
	done()

func manager_free_crate(at: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 0.8, 0.8)
	cs.shape = box
	body.add_child(cs)
	body.mass = 40.0
	body.collision_mask = Layers.WORLD
	world.add_child(body)
	body.global_position = at
	return body

## Spec: automate the lines with belts. Machines fed one piece at a time never
## showed it, but chained on belts the crusher's burst of lumps jammed the
## smelter, standing bars jammed the refiner, and pieces riding off-centre
## heaped against the bulkhead beside a mouth. The demo lines run both chains
## for a minute; every machine has to keep up with the one before it.
func test_machine_lines() -> void:
	_setup()
	await step(2)
	var show := Showcase.new()
	show.setup(manager)
	world.add_child(show)
	show.position = Vector3(0, 0.2, 0)
	await step(60 * 75)
	var ore: Dictionary = show.lines[0]
	var stone: Dictionary = show.lines[1]
	var crusher: InlineMachine = ore.machines[0]
	var smelter: InlineMachine = ore.machines[1]
	var refiner: InlineMachine = ore.machines[2]
	check(crusher.total_processed >= 12, "the crusher took only %d chunks" % crusher.total_processed)
	check(smelter.total_processed > crusher.total_processed * 3, "the lumps did not reach the smelter")
	check(refiner.total_processed >= smelter.total_processed * 0.8,
		"the refiner fell behind the smelter (%d of %d)" % [refiner.total_processed, smelter.total_processed])
	var sander: InlineMachine = stone.machines[0]
	var cutter: InlineMachine = stone.machines[1]
	check(sander.total_processed >= 12, "the sander polished only %d stones" % sander.total_processed)
	check(cutter.total_processed >= sander.total_processed - 2, "the gem cutter fell behind the sander")
	check(int(ore.made) > 20 and int(stone.made) > 8, "the lines finished too little (%d, %d)" % [ore.made, stone.made])
	show.clear_all()
	check_eq(manager.active_count(), 0, "switching the demo off left pieces behind")
	done()

## Rocks > crusher > smelter > refiner.
func test_ore_line() -> void:
	_setup()
	var crusher := _inline(&"crusher")
	await step(3)
	var chunk := _feed(crusher, &"ore_iron", Solid.cube(0.9))
	var chunk_volume := chunk.volume()
	check(await _through(crusher, chunk), "the chunk never came out of the crusher")
	var lumps := manager.free_items()
	check(lumps.size() > 1, "the crusher made %d piece(s) from a big chunk" % lumps.size())
	var total := 0.0
	for lump in lumps:
		total += lump.volume()
		var b := Solid.bounds(lump.dims)
		check(maxf(b.x, maxf(b.y, b.z)) <= crusher.machine_def.max_piece + 0.001, "a lump is still too big")
	check_near(total, chunk_volume, 0.0001, "the crusher did not conserve ore")

	_setup()
	var smelter := _inline(&"furnace")
	var refiner := _inline(&"refiner", Vector3(6, 0, 0))
	await step(3)
	var ore := _feed(smelter, &"ore_iron", Solid.cube(0.3))
	var ore_price := Economy.price_of(&"ore_iron", ore.dims)
	var ore_volume := ore.volume()
	check(await _through(smelter, ore), "the ore never came out of the smelter")
	check_eq(ore.item_id, &"ingot_iron", "the smelter made %s" % ore.item_id)
	check_near(ore.volume(), ore_volume * smelter.machine_def.yield_share, 0.0001, "the bar is the wrong size")
	var size: Vector3 = ore.dims.size
	check(size.y > size.x and size.x > size.z, "the bar is not bar-shaped: %s" % str(size))
	var bar_price := Economy.price_of(ore.item_id, ore.dims)
	check(bar_price > ore_price, "smelting lost value")
	var bar := _feed(refiner, ore.item_id, ore.dims)
	check(await _through(refiner, bar), "the bar never came out of the refiner")
	check(Solid.has_finish(bar.dims, &"refined"), "the refiner did not refine the bar")
	check(Economy.price_of(bar.item_id, bar.dims) > bar_price, "refining added no value")
	done()

## The tunnel mouth is a real opening: a trunk too big for it jams against the
## bulkhead, and a higher tier's wider mouth takes it.
func test_tunnel_mouth() -> void:
	_setup()
	PlayerState.levels[&"sawmill"] = 1
	var m := _inline(&"sawmill")
	# Fed from a belt behind it, so the trunk arrives at the mouth end-on.
	var belt := Conveyor.new()
	belt.length = 6.0
	belt.width = 1.8
	belt.speed = 2.0
	belt.position = Vector3(0, 0, m.length * 0.5 + 3.0)
	world.add_child(belt)
	await step(3)
	var fat := Solid.cylinder(m.hole.y * 0.62, m.hole.y * 0.6, 3.0)
	var trunk := manager.spawn(&"wood_pine", Transform3D(LooseItem.lying_basis(0.0),
		belt.global_position + Vector3(0, 0.8, 1.2)), 0, Vector3.ZERO, fat, true)
	await step(300)
	var z := (m.global_transform.affine_inverse() * trunk.global_position).z
	check(z > m.canopy_length() * 0.5 - 0.3, "an oversized trunk got into the tunnel (z=%.2f)" % z)
	check_eq(trunk.item_id, &"wood_pine", "an oversized trunk was planked anyway")
	check_eq(m.total_processed, 0, "the jammed machine counted work")
	var small_mouth := m.hole
	PlayerState.levels[&"sawmill"] = 3
	PlayerState.upgraded.emit(&"sawmill", 3)
	await step(3)
	check(m.hole.x > small_mouth.x and m.hole.y > small_mouth.y, "the top tier did not widen the mouth")
	check(m.speed > GameData.machine(&"sawmill").belt_speed, "the top tier did not speed the belt")
	check(await _through(m, trunk, 900), "the wider mouth still would not take the trunk")
	check_eq(trunk.item_id, &"lumber_pine", "the trunk was not planked once it got in")
	done()

## A plain belt runs straight into a machine and the machine takes it from there.
func test_conveyor_to_machine() -> void:
	_setup()
	var m := _inline(&"sawmill", Vector3(0, 0, 0))
	var belt := Conveyor.new()
	belt.length = 4.0
	belt.width = 1.8
	belt.speed = 2.0
	belt.position = Vector3(0, 0, m.length * 0.5 + 2.0)
	world.add_child(belt)
	await step(3)
	var log_piece := manager.spawn(&"wood_pine", Transform3D(LooseItem.lying_basis(0.0),
		belt.global_position + Vector3(0, 0.6, 1.2)), 0, Vector3.ZERO, Solid.cylinder(0.2, 0.18, 2.0))
	check(await _through(m, log_piece, 900), "the belt did not carry the log through the planker")
	check_eq(log_piece.item_id, &"lumber_pine", "the log was not planked")
	done()

func test_workbench() -> void:
	_setup()
	var bench := Machine.new()
	bench.setup(manager, GameData.building(&"workbench"), 0)
	world.add_child(bench)
	await step(2)
	var recipe: RecipeDef = GameData.machine_recipes(&"workbench")[0]
	check(recipe != null, "no assembly recipe for the workbench")

	# Assembly consumes volume by category, so any lengths will do.
	var lumber_needed: float = float(recipe.inputs.get(&"lumber", 0.0))
	var metal_needed: float = float(recipe.inputs.get(&"metal", 0.0))
	var board := Solid.box(Vector3(0.3, lumber_needed / 0.09 + 0.2, 0.3))
	manager.spawn(&"lumber_pine", Transform3D(Basis(), bench.input_point()), 0, Vector3.ZERO, board)
	await step(10)
	manager.spawn(&"ingot_iron", Transform3D(Basis(), bench.input_point()), 0, Vector3.ZERO,
		Solid.box(Vector3(0.26, metal_needed / 0.0364 + 0.1, 0.14)))
	await step(20)
	check(float(bench.stock.get(&"lumber", 0.0)) > 0.0, "the workbench took no lumber")
	check(float(bench.stock.get(&"metal", 0.0)) > 0.0, "the workbench took no metal")

	await step(int(recipe.seconds * 60.0) + 120)
	check(bench.total_produced > 0, "the workbench assembled nothing")
	var made := 0
	for item in manager.free_items():
		if item.item_id == recipe.output:
			made += 1
	check(made > 0, "the finished good never appeared at the outlet")
	done()


func test_sell_yard() -> void:
	_setup()
	var quests := QuestLog.new()
	quests.setup(GameData.quest_pool(), GameData.quest_slots())
	world.add_child(quests)
	var yard := SellYard.new()
	yard.setup(manager, quests)
	yard.extents = Vector3(12.0, 4.0, 12.0)
	yard.position = Vector3(0, 0, 40)
	world.add_child(yard)
	await step(4)
	Economy.from_dict({"money": 0, "day": 3})

	var dims := Solid.cylinder(0.2, 0.18, 1.2)
	var mine_a := spawn(&"wood_pine", yard.position + Vector3(2, 1, 1), dims)
	var mine_b := spawn(&"wood_pine", yard.position + Vector3(-2, 1, -1), dims)
	mine_a.owned = true
	mine_b.owned = true
	# Somebody else's wood in the yard, and my wood outside it: neither sells.
	var not_mine := spawn(&"wood_pine", yard.position + Vector3(1, 1, 3), dims)
	var outside := spawn(&"wood_pine", yard.position + Vector3(0, 1, 40), dims)
	outside.owned = true
	await step(4)

	check_eq(yard.stock().size(), 2, "the yard counted the wrong stock")
	var expected := Economy.price_of(&"wood_pine", dims) * 2
	check_eq(yard.stock_value(), expected, "the yard quoted the wrong price")

	var receipt := yard.sell_all()
	check_eq(int(receipt.count), 2, "the shopkeep bought the wrong number of pieces")
	check_eq(int(receipt.total), expected, "the shopkeep paid the wrong amount")
	check_eq(Economy.money, expected + int(receipt.bonus), "money does not match the receipt")
	await step(4)
	check(not is_instance_valid(not_mine) or not_mine.state != LooseItem.State.POOLED,
		"the shopkeep bought wood that was not the player's")
	check_eq(yard.stock().size(), 0, "stock remained in the yard after selling")
	check(outside.state == LooseItem.State.FREE, "wood outside the yard was sold")

	# Nothing left to sell is not an error, it is just nothing.
	var empty := yard.sell_all()
	check_eq(int(empty.count), 0, "the shopkeep bought something from an empty yard")
	done()

## Spec: orders reward delivering a quantity of a named material.
func test_quests() -> void:
	_setup()
	var quests := QuestLog.new()
	quests.setup(GameData.quest_pool(), GameData.quest_slots())
	world.add_child(quests)
	await step(2)
	check_eq(quests.active.size(), GameData.quest_slots(), "the log did not fill its slots")

	# Aim at the pine order specifically, so the test does not depend on which
	# orders happen to be drawn.
	quests.active = [{
		"id": &"test_order", "title": "Test order", "item": &"wood_pine",
		"category": &"", "volume": 1.0, "delivered": 0.0, "reward": 500,
	}]
	Economy.from_dict({"money": 0, "day": 1})

	# Material that does not match does not count.
	check_eq(quests.deliver(&"wood_oak", &"wood", 5.0), 0, "an order paid for the wrong material")
	check_near(float(quests.active[0].delivered), 0.0, 0.0001, "the wrong material advanced an order")

	# A part delivery advances it without paying.
	check_eq(quests.deliver(&"wood_pine", &"wood", 0.4), 0, "an order paid before it was filled")
	check_near(float(quests.active[0].delivered), 0.4, 0.0001, "a part delivery was not credited")
	check_eq(Economy.money, 0, "money moved on a part delivery")

	# Finishing it pays out and draws a replacement.
	var paid := quests.deliver(&"wood_pine", &"wood", 0.7)
	check_eq(paid, 500, "a filled order paid $%d" % paid)
	check_eq(Economy.money, 500, "the reward did not reach the player")
	check_eq(quests.active.size(), GameData.quest_slots(), "the log did not refill after a payout")
	for quest in quests.active:
		check(quest.id != &"test_order", "the filled order is still running")

	# Category orders take anything in the category.
	quests.active = [{
		"id": &"cat_order", "title": "Category order", "item": &"",
		"category": &"lumber", "volume": 0.5, "delivered": 0.0, "reward": 300,
	}]
	check_eq(quests.deliver(&"lumber_oak", &"lumber", 0.6), 300,
		"a category order did not take matching lumber")

	# Progress survives a save.
	quests.active = [{
		"id": &"pine_order", "title": "Pine order", "item": &"wood_pine",
		"category": &"", "volume": 4.0, "delivered": 1.75, "reward": 400,
	}]
	var path := "user://test_quests.json"
	check(SaveSystem.save_game(plot, null, path, null, null, quests), "saving failed")
	quests.active.clear()
	check(SaveSystem.load_game(plot, null, path, null, Callable(), quests), "loading failed")
	var found := false
	for quest in quests.active:
		if quest.id == &"pine_order":
			found = true
			check_near(float(quest.delivered), 1.75, 0.0001, "order progress did not survive a save")
	check(found, "the running order was not restored")
	SaveSystem.delete_save(path)
	done()

func test_storage() -> void:
	_setup()
	var bin := StorageBin.new()
	bin.setup(manager, GameData.building(&"storage"), 0)
	world.add_child(bin)
	await step(2)
	var stored := 0.0
	for i in 5:
		var billet := spawn(&"ingot_iron", bin.global_position + Vector3(0, 2.6 + float(i) * 0.3, 0),
			Solid.box(Vector3(0.26, 0.4 + float(i) * 0.1, 0.14)))
		stored += billet.volume()
	await step(40)
	check_eq(bin.count(), 5, "bin did not absorb the items")
	check_near(bin.stored_m3(), stored, 0.0001, "bin does not account for what it holds")
	check_eq(manager.active_count(), 0, "items still loose after storage")
	var queued := bin.dispense_all()
	check_eq(queued, 5, "dispense queued the wrong count")
	await step(80)
	check_eq(manager.active_count(), 5, "bin did not pour the items back out")
	check_near(loose_volume(), stored, 0.0001, "the bin gave back a different amount than it took")
	check_eq(bin.count(), 0, "bin still reports contents after emptying")
	done()

## Spec: belts want options - ramps to climb, borderless decks, and
## retractables that can be stopped.
func test_conveyor_options() -> void:
	_setup()
	Economy.from_dict({"money": 50000, "day": 1})

	var ramp_def := GameData.building(&"conveyor_ramp")
	check(ramp_def != null, "there is no belt ramp to build")
	check(ramp_def.rise > 0.5, "the belt ramp does not climb")
	var ramp := plot.place(ramp_def, Vector2i(-4, -4), 0) as Conveyor
	check(ramp != null, "the ramp was not placed")
	await step(4)

	# A ramp lifts what rides it - by friction, with the piece still a free body.
	# Laid down along the belt: a tall piece stood on its end at the foot of
	# a moving ramp topples, as it would on a real one.
	var box := manager.spawn(&"lumber_pine", Transform3D(
		ramp.global_transform.basis * LooseItem.lying_basis(0.0),
		ramp.global_transform * Vector3(0, 0.9, 1.2)), 0, Vector3.ZERO,
		Solid.box(Vector3(0.3, 0.9, 0.3)))
	for i in 200:
		await step(1)
		if ramp.captured_count() > 0:
			break
	check(ramp.captured_count() > 0, "the ramp never noticed the piece")
	var lifted := box.global_position.y
	for i in 20:
		await step(1)
	check(box.state == LooseItem.State.FREE and not box.freeze,
		"a piece on the ramp was taken out of the physics")
	check(box.global_position.y > lifted + 0.1, "the ramp did not carry the piece upward")
	check(ramp.output_transform().origin.y > ramp.global_position.y + 0.5,
		"the ramp's far end is not above its near end")
	check_near(ramp.surface_height(0.0), 0.0, 0.0001, "the ramp starts above its own base")
	check_near(ramp.surface_height(ramp.length), ramp_def.rise, 0.0001,
		"the ramp does not climb its full rise")

	# Fire a ray down at the far end and see what it lands on: this is what
	# catches a deck pitched against the pieces riding it, which the item
	# positions alone cannot, since they are computed separately.
	var space := world.get_world_3d().direct_space_state
	var far := ramp.global_position - ramp.global_transform.basis.z * (ramp.length * 0.4)
	var query := PhysicsRayQueryParameters3D.create(
		far + Vector3(0, ramp.rise + 3.0, 0), far - Vector3(0, 1.0, 0), Layers.MACHINE)
	var hit := space.intersect_ray(query)
	check(not hit.is_empty(), "nothing under the ramp's far end")
	if not hit.is_empty():
		var expected: float = ramp.global_position.y + ramp.surface_height(ramp.length * 0.9)
		check_near(float(hit.position.y), expected, 0.35,
			"the deck at the far end is at %.2f m, not the %.2f m the pieces ride at" % [
				float(hit.position.y), expected])

	# A borderless belt is a deck without rails.
	var open_def := GameData.building(&"conveyor_open")
	check(open_def != null, "there is no borderless belt to build")
	check(not open_def.railed, "the borderless belt still has rails")
	check(open_def.cost < GameData.building(&"conveyor").cost,
		"a belt with less on it costs more")

	# A stopped belt is a still deck: what lands on it stays where it lands.
	var flat := plot.place(GameData.building(&"conveyor"), Vector2i(4, -4), 0) as Conveyor
	await step(4)
	check(flat.running, "a new belt starts stopped")
	check(not flat.toggle(), "toggling a running belt did not stop it")
	var resting := spawn(&"lumber_pine", flat.global_position + Vector3(0, 0.9, 1.6),
		Solid.box(Vector3(0.3, 0.9, 0.3)))
	await step(60)
	var parked := resting.global_position
	await step(60)
	check(parked.distance_to(resting.global_position) < 0.05,
		"a stopped belt moved what was on it (%.2f m)" % parked.distance_to(resting.global_position))
	check(flat.toggle(), "toggling a stopped belt did not start it")
	await step(30)
	check(parked.distance_to(resting.global_position) > 0.5,
		"a restarted belt did not carry off what was sitting on it")
	done()

## Spec from play-testing: things on a belt are not locked down. They ride it
## by friction as free bodies, keep moving while it runs, and pile up or jam
## against whatever is in the way instead of passing through it.
func test_conveyor_physics() -> void:
	_setup()
	var belt := Conveyor.new()
	belt.length = 10.0
	belt.speed = 3.0
	belt.position = Vector3(0, 0.6, 0)
	world.add_child(belt)
	await step(2)
	var piece := spawn(&"lumber_pine", Vector3(0, 1.3, 3.5), Solid.box(Vector3(0.3, 0.9, 0.3)))
	await step(50)
	check(piece.state == LooseItem.State.FREE and not piece.freeze,
		"the belt took the piece out of the physics")
	var v := piece.linear_velocity.dot(-belt.global_transform.basis.z)
	check_near(v, belt.speed, 0.6, "the piece rides at %.2f m/s on a %.1f m/s belt" % [v, belt.speed])
	check(not piece.sleeping, "a piece fell asleep on a running belt")

	# A wall across the belt: the piece jams against it and stays jammed,
	# rather than being dragged through it.
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.MACHINE
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 1.5, 0.3)
	cs.shape = box
	wall.add_child(cs)
	wall.position = Vector3(0, 1.2, -3.0)
	world.add_child(wall)
	await step(180)
	check(piece.global_position.z > -3.0, "the belt dragged the piece through a wall")
	check(piece.global_position.z < -1.5, "the piece never reached the wall (z=%.2f)" % piece.global_position.z)
	check_eq(belt.captured_count(), 1, "the jammed piece is not counted as on the belt")
	# Take the wall away and the jam clears by itself.
	wall.queue_free()
	await step(150)
	check(piece.global_position.z < -5.0, "the jam did not clear when the wall went")
	check(belt.total_delivered >= 1, "the piece going off the end was not counted")
	done()

func test_splitter() -> void:
	_setup()
	var splitter := Splitter.new()
	splitter.setup(GameData.building(&"splitter"))
	splitter.position = Vector3(0, 0.6, 0)
	world.add_child(splitter)
	await step(2)
	for i in 6:
		spawn(&"lumber_pine", Vector3(0, 1.1, 0))
		await step(25)
	await step(60)
	check(splitter.total_routed >= 5, "splitter routed only %d of 6" % splitter.total_routed)
	var left := 0
	var right := 0
	var straight := 0
	for item in manager.free_items():
		var local: Vector3 = splitter.global_transform.affine_inverse() * item.global_position
		if local.x < -0.8:
			left += 1
		elif local.x > 0.8:
			right += 1
		elif local.z < -0.8:
			straight += 1
	check(left > 0 and right > 0 and straight > 0,
		"splitter did not use all three outputs (l%d s%d r%d)" % [left, straight, right])
	done()

func test_filter() -> void:
	_setup()
	var filter := Filter.new()
	filter.setup(GameData.building(&"filter"))
	filter.filter_item = &"lumber_pine"
	filter.position = Vector3(0, 0.6, 0)
	world.add_child(filter)
	await step(2)
	for i in 4:
		spawn(&"lumber_pine", Vector3(0, 1.1, 0))
		await step(22)
		spawn(&"ore_iron", Vector3(0, 1.1, 0))
		await step(22)
	await step(60)
	var straight_planks := 0
	var right_ore := 0
	var misrouted := 0
	for item in manager.free_items():
		var local: Vector3 = filter.global_transform.affine_inverse() * item.global_position
		var went_right: bool = local.x > 0.8
		var went_straight: bool = local.z < -0.8
		if item.item_id == &"lumber_pine":
			if went_straight:
				straight_planks += 1
			elif went_right:
				misrouted += 1
		else:
			if went_right:
				right_ore += 1
			elif went_straight:
				misrouted += 1
	check(straight_planks >= 3, "filter sent only %d of 4 planks straight on" % straight_planks)
	check(right_ore >= 3, "filter diverted only %d of 4 non-matching items" % right_ore)
	check_eq(misrouted, 0, "filter sent items the wrong way")

	# Inverting swaps the two paths.
	filter.invert = true
	var plank := spawn(&"lumber_pine", Vector3(0, 1.1, 0))
	await step(70)
	var local_after: Vector3 = filter.global_transform.affine_inverse() * plank.global_position
	check(local_after.x > 0.5, "inverted filter did not divert the matching item")
	done()

func test_building() -> void:
	_setup()
	await step(2)
	Economy.from_dict({"money": 1000, "day": 1})
	var def := GameData.building(&"sawmill")
	var node := plot.place(def, Vector2i(0, 0), 0)
	check(node != null, "could not place a sawmill on an empty plot (money=%d, err=%s, extent=%.1f)" % [
		Economy.money, plot.placement_error(def, Vector2i(0, 0), 0), plot.half_extent])
	check_eq(Economy.money, 1000 - def.cost, "placement did not charge the cost")
	check_eq(plot.placed.size(), 1, "plot did not record the building")
	check(plot.occupied.size() == def.size.x * def.size.z, "wrong number of cells reserved")

	var overlap := plot.place(def, Vector2i(1, 1), 0)
	check(overlap == null, "overlapping placement was allowed")
	var outside := plot.place(def, Vector2i(9999, 9999), 0)
	check(outside == null, "placement outside the plot was allowed")
	check_eq(plot.placement_error(def, Vector2i(1, 1), 0), "space taken", "wrong error for overlap")

	Economy.from_dict({"money": 10, "day": 1})
	check(plot.place(def, Vector2i(-10, -10), 0) == null, "placed a building without money")

	Economy.from_dict({"money": 0, "day": 1})
	check(plot.remove(node), "could not remove a placed building")
	check_eq(Economy.money, def.cost / 2, "removal refunded the wrong amount")
	check_eq(plot.placed.size(), 0, "plot still lists a removed building")
	check_eq(plot.occupied.size(), 0, "removed building left cells reserved")

	# Rotation must swap the footprint.
	var rotated := Plot.rotated_footprint(Vector3i(3, 2, 4), 1)
	check_eq(rotated, Vector3i(4, 2, 3), "rotating a footprint did not swap x/z")
	done()

## From play-testing: things placed in build mode were ending up sunk into the
## pad and out of reach. Every kind gets measured rather than eyeballed.
func test_buildings_sit_on_pad() -> void:
	_setup()
	Economy.from_dict({"money": 900000, "day": 1})
	for def: BuildingDef in GameData.buildings.values():
		if not PlayerState.is_unlocked(def.id):
			PlayerState.unlocked_buildings.append(def.id)
	await step(2)

	var pad := plot.global_position.y
	var sunk: Array[String] = []
	var checked := 0
	var cell := Vector2i(-16, -16)
	for def: BuildingDef in GameData.buildings.values():
		if not plot.can_place(def, cell, Vector3i.ZERO, false):
			cell = Vector2i(-16, cell.y + 8)
			if not plot.can_place(def, cell, Vector3i.ZERO, false):
				continue
		var node := plot.place(def, cell, Vector3i.ZERO, false)
		cell.x += def.size.x + 2
		if node == null:
			continue
		await step(2)
		var lowest := _lowest_collider_y(node)
		if lowest == INF:
			continue                    # nothing solid: a plan, before it is filled
		checked += 1
		if lowest < pad - 0.02:
			sunk.append("%s by %.2f m" % [def.display_name, pad - lowest])
	check(checked >= 6, "only measured %d building types" % checked)
	check(sunk.is_empty(), "placed into the pad: " + ", ".join(sunk))
	done()

## The lowest point of anything *solid* under a node, in world space. Area3D
## shapes are skipped: a machine's outlet zone reaching below the pad so it can
## catch what rolls out of it is correct, and only the floor you stand on and
## bump into counts as placement.
func _lowest_collider_y(node: Node) -> float:
	var lowest := INF
	if node is Area3D:
		return lowest
	for child in node.get_children():
		var cs := child as CollisionShape3D
		if cs != null and not cs.disabled:
			var box := cs.shape as BoxShape3D
			if box != null:
				lowest = minf(lowest, cs.global_position.y - box.size.y * 0.5)
			var cyl := cs.shape as CylinderShape3D
			if cyl != null:
				lowest = minf(lowest, cs.global_position.y - cyl.height * 0.5)
		lowest = minf(lowest, _lowest_collider_y(child))
	return lowest

## Spec: a plan is filled by touching material to it, the first material fed to
## it is the only one it will take, and it turns solid when it is full.
func test_schematic() -> void:
	_setup()
	Economy.from_dict({"money": 50000, "day": 1})
	var node := plot.place(GameData.building(&"schematic_slab"), Vector2i(0, 0), 0)
	var plan := node as Schematic
	check(plan != null, "the slab plan was not placed")
	await step(4)

	# A 2 x 1 x 2 plan holds four cubic metres and starts as a drawing.
	check_near(plan.capacity_m3(), 4.0, 0.0001, "the plan wants the wrong volume")
	check(not plan.solid, "an empty plan is already solid")
	check_eq(plan.material, &"", "an empty plan already has a material")
	check(plan.can_accept(&"lumber_pine"), "an empty plan refused lumber")
	check(plan.can_accept(&"ingot_iron"), "an empty plan refused metal")

	# The first piece in decides what it is made of.
	var first := spawn(&"lumber_pine", Vector3(0, 6, 0), Solid.box(Vector3(0.5, 2.0, 0.5)))
	check_near(first.volume(), 0.5, 0.0001, "test piece is the wrong size")
	check(plan.accept_item(first), "the plan refused the first piece")
	check_eq(plan.material, &"lumber_pine", "the plan did not take its material from the first piece")
	check_near(plan.filled_m3, 0.5, 0.0001, "the plan filled by the wrong amount")
	check(not plan.solid, "a plan one eighth full turned solid")

	# And from then on it takes nothing else.
	check(not plan.can_accept(&"lumber_oak"), "a pine plan accepted oak")
	var wrong := spawn(&"lumber_oak", Vector3(0, 6, 0), Solid.box(Vector3(0.5, 2.0, 0.5)))
	check(not plan.accept_item(wrong), "a pine plan swallowed oak")
	check_near(plan.filled_m3, 0.5, 0.0001, "a refused piece still filled the plan")

	# Fill it the rest of the way, with the last piece deliberately too big.
	var second := spawn(&"lumber_pine", Vector3(0, 6, 0), Solid.box(Vector3(1.0, 3.0, 1.0)))
	check(plan.accept_item(second), "the plan refused more of its own material")
	check_near(plan.filled_m3, 3.5, 0.0001, "the plan did not take the whole piece")

	var oversized := spawn(&"lumber_pine", Vector3(0, 6, 0), Solid.box(Vector3(1.0, 2.0, 1.0)))
	var oversized_volume := oversized.volume()
	check(oversized_volume > plan.remaining_m3(), "the oversized piece is not actually oversized")
	check(plan.accept_item(oversized), "the plan refused the last piece")
	await step(4)
	check(plan.solid, "a full plan did not turn solid")
	check_near(plan.filled_m3, 4.0, 0.0001, "a full plan holds the wrong volume")
	# The offcut comes back rather than vanishing into the wall.
	check_near(loose_volume(&"lumber_pine"), oversized_volume - 0.5, 0.0001,
		"the offcut from the last piece was not returned")
	check(not plan.can_accept(&"lumber_pine"), "a finished plan still takes material")

	# Pulling it down gives the material back, not cash.
	var before := loose_volume(&"lumber_pine")
	var reclaimed := plan.reclaim()
	await step(4)
	check_near(reclaimed, 4.0, 0.0001, "reclaiming returned the wrong volume")
	check_near(loose_volume(&"lumber_pine") - before, 4.0, 0.0001,
		"the material did not come back out of the plan")
	done()

func test_terraces() -> void:
	_setup(false)
	var land := Terrain.new()
	land.half_extent = 300.0
	land.noise_seed = 20260921
	world.add_child(land)
	await step(2)
	# Mostly flat panels: most of the ground's faces are level to the eye.
	var flat := 0
	var total := 0
	var worst_step := 0.0
	var x := -land.half_extent + 60.0
	while x < land.half_extent - 60.0:
		var z := -land.half_extent + 60.0
		while z < land.half_extent - 60.0:
			var h := land.height_at(x, z)
			var hx := land.height_at(x + Terrain.CELL, z)
			var hz := land.height_at(x, z + Terrain.CELL)
			var n := Vector3(h - hx, Terrain.CELL, h - hz).normalized()
			total += 1
			if n.y > 0.985:
				flat += 1
			worst_step = maxf(worst_step, maxf(absf(h - hx), absf(h - hz)))
			z += Terrain.CELL
		x += Terrain.CELL
	var share := float(flat) / float(maxi(1, total))
	check(share > 0.45, "only %.0f%% of the ground is flat panels" % (share * 100.0))
	# Heights are one continuous surface, so no neighbouring points are a
	# cliff apart the way the old per-biome plinths were.
	check(worst_step < 9.0, "a %.1f m wall between neighbouring ground points" % worst_step)
	# The island runs down into the sea at its edge.
	for p in [Vector3(-296, 0, 0), Vector3(296, 0, 40), Vector3(0, 0, -296), Vector3(-80, 0, 296)]:
		check(land.height_at(p.x, p.z) < Terrain.WATER_LEVEL, "the map edge at %s is not sea" % p)
	check_near(Terrain.terrace(5.0, 2.0), 4.0, 0.01, "the middle of a band is its flat top")
	check(Terrain.terrace(5.9, 2.0) > 4.0, "the top of a band rises toward the next")
	done()

func test_caves() -> void:
	_setup(false)
	var land := Terrain.new()
	land.half_extent = 300.0
	land.noise_seed = 20260921
	land.cave_count = 3
	world.add_child(land)
	await step(2)
	check(land.caves.size() >= 2, "only %d cave(s) found a site" % land.caves.size())
	if land.caves.is_empty():
		done()
		return
	var plan: Dictionary = land.caves[0]
	var cave := Cave.new()
	cave.setup(plan.entrance, plan.dir, plan.name, 5)
	world.add_child(cave)
	await step(2)
	var ground: float = plan.ground
	check(ground - Cave.CHAMBER_DROP > Terrain.WATER_LEVEL, "the chamber floor is under the water line")
	# Rock over the whole of it: nothing pokes out of the hillside.
	var least := INF
	var z := Cave.SHAFT_LENGTH + 1.0
	while z <= Cave.FOOTPRINT_LENGTH:
		var x := -Cave.CHAMBER_WIDTH * 0.5
		while x <= Cave.CHAMBER_WIDTH * 0.5:
			if z >= Cave.SHAFT_LENGTH + Cave.TUNNEL_LENGTH or absf(x) < Cave.SHAFT_WIDTH * 0.5 + 1.0:
				var p := cave.to_global(Vector3(x, Cave.roof_at(z), z))
				least = minf(least, land.height_at(p.x, p.z) - p.y)
			x += 2.0
		z += 2.0
	check(least > 0.3, "the cave roof is only %.2f m under the hill somewhere" % least)
	# The trench is open - no ground over it - and has a floor you land on.
	var space := world.get_world_3d().direct_space_state
	var mid := cave.to_global(Vector3(0, 0, Cave.SHAFT_LENGTH * 0.5))
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(mid + Vector3(0, 10, 0), mid + Vector3(0, -30, 0), Layers.WORLD))
	check(not hit.is_empty() and hit.collider != land, "the trench is still covered by the ground")
	if not hit.is_empty():
		check_near(hit.position.y, ground + Cave.floor_at(Cave.SHAFT_LENGTH * 0.5), 0.2, "the trench floor is not where the ramp should be")
	# And the chamber has a floor under the hill.
	var inside := cave.to_global(Vector3(0, -Cave.CHAMBER_DROP + 2.0, Cave.SHAFT_LENGTH + Cave.TUNNEL_LENGTH + 10.0))
	hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(inside, inside + Vector3(0, -6, 0), Layers.WORLD))
	check(not hit.is_empty(), "the chamber has no floor")
	if not hit.is_empty():
		check_near(hit.position.y, ground - Cave.CHAMBER_DROP, 0.1, "the chamber floor is at the wrong depth")
	check(cave.depth_factor(inside) > 0.9, "the chamber does not count as underground")
	check_eq(cave.depth_factor(cave.to_global(Vector3(0, 2, -10))), 0.0, "outside the mouth counts as underground")
	done()

func test_greeble_winding() -> void:
	var g := Greeble.new()
	var centre := Vector3(1, 2, 3)
	g.box(Vector3(2, 1, 3), Transform3D(Basis(Vector3.UP, 0.6) * Basis(Vector3.RIGHT, 0.3), centre), Color.RED)
	g.prism(7, 1.0, 0.5, 2.0, Transform3D(Basis(), centre + Vector3(0, -1, 0)), Color.GREEN)
	var mesh := g.commit()
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var inward := 0
	var i := 0
	while i < verts.size():
		var a := verts[i]
		var b := verts[i + 1]
		var c := verts[i + 2]
		# Godot's front face: (C - A) x (B - A) points out of the solid.
		var n := (c - a).cross(b - a)
		var mid := (a + b + c) / 3.0
		if n.dot(mid - centre) < 0.0:
			inward += 1
		i += 3
	check(verts.size() > 0, "the greeble mesh is empty")
	check_eq(inward, 0, "%d triangles face into the solid and would render inside-out" % inward)
	done()

func test_field_churn() -> void:
	_setup(false)
	var field := ResourceField.new()
	field.quota = 12
	field.min_spacing = 1.0
	field.churn_distance = 50.0
	field.spawn_clearance = 20.0
	var near := Node3D.new()
	world.add_child(near)
	field.focus = near
	var built := func(_kind: Dictionary, _seed: int) -> Node3D:
		var rock := OreRock.new()
		rock.manager = manager
		rock.volume = 0.4
		return rock
	# Half the spots are right by the player, half far off.
	var flip := [0]
	field.setup([{}], built, func(rng: RandomNumberGenerator) -> Vector3:
		flip[0] += 1
		return Vector3(rng.randf_range(-60, -40) if flip[0] % 2 == 0 else rng.randf_range(15, 25), 0.5, rng.randf_range(-5, 5)), 7)
	world.add_child(field)
	field.prefill()
	check(field.at_quota(), "the field did not fill")
	for node in field.alive:
		check(node.global_position.distance_to(near.global_position) >= 20.0, "a node spawned inside the player's clearance")
	# Touch every far node but one: that one is all churn may take.
	var far: Array[Node3D] = []
	for node in field.alive:
		if node.global_position.distance_to(near.global_position) > 50.0:
			far.append(node)
	check(far.size() >= 2, "the test needs far nodes to work with")
	for k in range(1, far.size()):
		(far[k] as OreRock).touched = true
	var taken := field.retire_one()
	check(taken == far[0], "churn took something other than the only far, untouched node")
	check(field.retire_one() == null, "churn took a touched or nearby node")
	check_eq(field.total_retired, 1, "retired count is off")
	check_eq(field.count(), field.quota - 1, "retiring should open the quota for a regrow")
	done()

func test_resurface() -> void:
	_setup(false)
	manager.ground_height = func(p: Vector3) -> float: return 0.0 if p.x < 50.0 else -INF
	var sunk := spawn(&"wood_pine", Vector3(3, -6, 3), Solid.cylinder(0.2, 0.18, 1.2))
	var ignored := spawn(&"wood_pine", Vector3(60, -6, 3), Solid.cylinder(0.2, 0.18, 1.2))
	sunk.gravity_scale = 0.0
	ignored.gravity_scale = 0.0
	await step(20)
	check(sunk.global_position.y > -0.5, "a piece under the ground was left there (y %.1f)" % sunk.global_position.y)
	check_near(sunk.global_position.x, 3.0, 0.5, "a resurfaced piece should come up where it went down")
	check(ignored.global_position.y < -4.0, "a piece where the ground has no answer (a cave) was moved")
	check(manager.stat_resurfaced >= 1, "nothing counted as resurfaced")
	done()

func test_trader_and_cache() -> void:
	_setup()
	var yard := SellYard.new()
	yard.setup(manager, null)
	yard.keeper = "Trader"
	yard.premium = {&"lumber": 1.5}
	yard.extents = Vector3(12.0, 4.0, 12.0)
	yard.position = Vector3(0, 0, 40)
	world.add_child(yard)
	await step(4)
	Economy.from_dict({"money": 0, "day": 2})
	var plank := spawn(&"lumber_pine", yard.position + Vector3(1, 1, 1), Solid.box(Vector3(0.3, 0.3, 2.0)))
	var log := spawn(&"wood_pine", yard.position + Vector3(-1, 1, -1), Solid.cylinder(0.2, 0.18, 1.2))
	plank.owned = true
	log.owned = true
	await step(4)
	var base := Economy.price_of(&"lumber_pine", plank.dims) + Economy.price_of(&"wood_pine", log.dims)
	var premium := int(round(float(Economy.price_of(&"lumber_pine", plank.dims)) * 0.5))
	var receipt := yard.sell_all()
	check_eq(int(receipt.total), base, "the trader's base price is off")
	check_eq(Economy.money, base + premium, "the trader paid no premium on lumber, or paid it on wood")
	check(yard.status_line().contains("lumber +50%"), "the trader does not say what they pay extra for")

	var cache := SupplyCache.new()
	cache.setup("Test Cache", 200)
	world.add_child(cache)
	await step(1)
	var before := Economy.money
	check(cache.ready_to_open(), "a new cache should be full")
	cache.interact(null)
	var paid := Economy.money - before
	check(paid >= 150 and paid <= 260, "the cache paid %d, outside its range" % paid)
	check(not cache.ready_to_open(), "a cache should be empty once opened")
	cache.interact(null)
	check_eq(Economy.money - before, paid, "an opened cache paid out twice in one day")
	var saved := PlayerState.to_dict()
	PlayerState.reset()
	PlayerState.from_dict(saved)
	check(not cache.ready_to_open(), "an opened cache came back full after a save")
	Economy.advance_day()
	check(cache.ready_to_open(), "the cache did not restock the next day")
	done()

func test_save_summary() -> void:
	_setup()
	await step(2)
	plot.place(GameData.building(&"sawmill"), Vector2i(0, 0), 0)
	plot.place(GameData.building(&"storage"), Vector2i(4, -6), 0)
	Economy.from_dict({"money": 12345, "day": 6})
	var path := "user://test_summary.json"
	check(SaveSystem.save_game(plot, null, path), "saving failed")
	var info := SaveSystem.summary(path)
	check_eq(int(info.get("day", 0)), 6, "summary has the wrong day")
	check_eq(int(info.get("money", 0)), 12345, "summary has the wrong money")
	check_eq(int(info.get("buildings", 0)), 2, "summary has the wrong building count")
	check(UIKit.ago(String(info.get("saved_at", ""))) == "just now",
		"a save made this second should read 'just now', got '%s'" % UIKit.ago(String(info.get("saved_at", ""))))
	check(SaveSystem.summary("user://no_such_save.json").is_empty(), "a missing save should summarise to nothing")
	SaveSystem.delete_save(path)
	# The tutorial rides along in the player's progress.
	PlayerState.reset()
	PlayerState.tutorial_done.append(&"chop")
	var progress := PlayerState.to_dict()
	PlayerState.reset()
	check(PlayerState.tutorial_done.is_empty(), "reset should clear the checklist")
	PlayerState.from_dict(progress)
	check(PlayerState.tutorial_done.has(&"chop"), "the checklist did not survive a save")
	done()

func test_settings() -> void:
	var original_path: String = Settings.path
	var path := "user://test_settings.cfg"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Settings.path = path
	Settings.load_from(path)
	check_eq(Settings.value(&"fov"), 75.0, "missing file should give defaults")
	var heard: Array[StringName] = []
	var listener := func(key: StringName): heard.append(key)
	Settings.changed.connect(listener)
	Settings.set_value(&"fov", 90)
	check(typeof(Settings.value(&"fov")) == TYPE_FLOAT, "an int written to a float setting should come back a float")
	check_eq(Settings.value(&"fov"), 90.0, "set_value did not stick")
	Settings.set_value(&"shadows", 1.0)
	check(typeof(Settings.value(&"shadows")) == TYPE_INT, "a float written to an int setting should come back an int")
	Settings.set_value(&"invert_y", 1)
	check(Settings.invert_y(), "invert_y should read true")
	Settings.set_value(&"fov", 90)
	check_eq(heard.count(&"fov"), 1, "setting the same value twice should only announce once")
	Settings.set_value(&"no_such_setting", 3)
	check(not heard.has(&"no_such_setting"), "an unknown key should be ignored")
	check(FileAccess.file_exists(path), "set_value should persist to disk")
	Settings.load_from(path)
	check_eq(Settings.value(&"fov"), 90.0, "fov did not survive a reload")
	check_eq(Settings.value(&"shadows"), 1, "shadows did not survive a reload")
	Settings.reset_to_defaults()
	check_eq(Settings.value(&"fov"), 75.0, "reset should restore the default fov")
	check(not Settings.invert_y(), "reset should restore invert_y")
	Settings.changed.disconnect(listener)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Settings.path = original_path
	Settings.load_from(original_path)
	done()

func test_prompt_keys() -> void:
	check_eq(UIKit.money(1234567), "$1,234,567", "thousands separators")
	check_eq(UIKit.money(-450), "-$450", "negative money")
	check_eq(UIKit.money(0), "$0", "zero money")
	check_eq(UIKit.clock(125.4), "2:05", "clock formatting")
	for text in ["E", "LMB", "Shift+E", "R/T", "WASD", "E+shift", "F1", "Shift/Ctrl", "Tab"]:
		check(UIKit.is_key_text(text), "'%s' should read as a key" % text)
	for text in ["1/17", "locked", "full", "", "F100", "12"]:
		check(not UIKit.is_key_text(text), "'%s' should not read as a key" % text)
	var parts := UIKit.parse_keys("Till: [E] pay $40 for [2/5] boxes")
	var keys: Array = parts.filter(func(p): return p[0] == "key")
	check_eq(keys.size(), 1, "only [E] is a key in that prompt")
	check_eq(keys[0][1] if not keys.is_empty() else "", "E", "the key should be E")
	var joined := "".join(parts.map(func(p): return ("[%s]" % p[1]) if p[0] == "key" else p[1]))
	check_eq(joined, "Till: [E] pay $40 for [2/5] boxes", "parsing should lose no text")
	# Every key the controls sheet names must draw as a keycap.
	for group in KeyGuide.GROUPS:
		for row in group.rows:
			for k in row[0]:
				if k != "/":
					check(UIKit.is_key_text(String(k)), "controls sheet names '%s', which is not a key" % k)
	for state in ["foot", "carrying", "dragging", "build", "drive", "crane"]:
		check(not KeyGuide.hints_for(state).is_empty(), "no hints for %s" % state)
	done()

func test_compass() -> void:
	check_near(Compass.heading_of(Vector3(0, 0, -1)), 0.0, 0.001, "-Z is north")
	check_near(Compass.heading_of(Vector3(1, 0, 0)), PI * 0.5, 0.001, "+X is east")
	check_near(Compass.heading_of(Vector3(0, 0, 1)), PI, 0.001, "+Z is south")
	check_near(Compass.heading_of(Vector3(-1, 0, 0)), PI * 1.5, 0.001, "-X is west")
	check_near(Compass.offset_of(0.0, 0.0), 0.0, 0.001, "dead ahead is the middle")
	check(Compass.offset_of(deg_to_rad(30.0), 0.0) > 0.0, "a place to the east of north is right of centre")
	check(Compass.offset_of(deg_to_rad(330.0), 0.0) < 0.0, "a place to the west of north is left of centre")
	check_near(Compass.offset_of(deg_to_rad(10.0), deg_to_rad(350.0)),
		Compass.offset_of(deg_to_rad(20.0), 0.0), 0.001, "wrapping through north")
	done()

func test_tutorial() -> void:
	_setup()
	await step(2)
	var t := Tutorial.new()
	t.setup(null, plot, null, null, null, [])
	world.add_child(t)
	var completed: Array = []
	t.step_completed.connect(func(s: Dictionary): completed.append(s.id))
	t.evaluate()
	check_eq(t.done_count(), 0, "nothing done on a fresh game")
	check_eq(t.current().get("id"), &"chop", "the first step is to fell a tree")
	t.note(&"chop")
	check(t.done(&"chop"), "felling a tree should tick the first step")
	check_eq(t.current().get("id"), &"pick", "then pick up the wood")
	# A building on the plot means the player got there somehow; everything
	# before it is done, without being asked to go back and do it.
	plot.place(GameData.building(&"sawmill"), Vector2i(0, 0), 0)
	t.evaluate()
	for id in [&"pick", &"sell", &"store", &"build", &"place"]:
		check(t.done(id), "placing a building should also tick '%s'" % id)
	check_eq(t.current().get("id"), &"order", "the last step is an order")
	check(not t.finished(), "not finished until an order is filled")
	t.note(&"order")
	check(t.finished(), "filling an order finishes the list")
	check_eq(completed.size(), Tutorial.STEPS.size(), "each step should announce itself once")
	# Money that did not come from a sale is not a sale.
	PlayerState.reset()
	plot.clear_buildings()
	Economy.from_dict({})
	Economy.add_money(250)
	var fresh := Tutorial.new()
	fresh.setup(null, plot, null, null, null, [])
	world.add_child(fresh)
	fresh.evaluate()
	check(not fresh.done(&"sell"), "a starting float is not selling anything")
	done()

func test_save_load() -> void:
	_setup()
	await step(2)
	Economy.from_dict({"money": 50000, "day": 4})
	PlayerState.try_upgrade(&"carry")
	PlayerState.give_tool(&"steel_axe")
	PlayerState.try_unlock(&"furnace")
	PlayerState.try_unlock(&"workbench")
	plot.place(GameData.building(&"workbench"), Vector2i(0, 0), 0)
	plot.place(GameData.building(&"sawmill"), Vector2i(8, 8), 0)
	plot.place(GameData.building(&"conveyor"), Vector2i(-6, 0), 1)
	plot.place(GameData.building(&"storage"), Vector2i(4, -6), 0)
	await step(2)
	var mill: Machine = plot.machines()[0]
	mill.stock[&"lumber"] = 0.42
	mill.total_produced = 7
	mill.volume_in = 1.25
	var money_before := Economy.money
	var expected_buildings := plot.placed.size()

	var path := "user://test_save.json"
	check(SaveSystem.save_game(plot, null, path), "saving failed")
	check(FileAccess.file_exists(path), "no save file was written")

	plot.clear_buildings()
	Economy.from_dict({"money": 1, "day": 1})
	PlayerState.reset()
	await step(2)
	check_eq(plot.placed.size(), 0, "clearing the plot left buildings behind")

	check(SaveSystem.load_game(plot, null, path), "loading failed")
	await step(4)
	check_eq(plot.placed.size(), expected_buildings, "wrong building count after load")
	check_eq(Economy.money, money_before, "money did not survive the round-trip")
	check_eq(Economy.day, 4, "day did not survive the round-trip")
	check_eq(PlayerState.level(&"carry"), 2, "upgrades did not survive the round-trip")
	check(PlayerState.owns_tool(&"steel_axe"), "tools did not survive the round-trip")
	check_eq(plot.inline_machines().size(), 1, "the planker did not come back")
	check(PlayerState.is_unlocked(&"furnace"), "unlocks did not survive the round-trip")
	var restored: Array[Machine] = plot.machines()
	check(restored.size() == 1, "machine was not restored")
	if restored.size() == 1:
		# The restored mill starts working immediately, so the queued job may
		# already have moved into the machine.
		check_near(restored[0].buffered_m3(), 0.42, 0.0001, "queued work was not restored")
		check_eq(restored[0].total_produced, 7, "machine counters were not restored")
		check_near(restored[0].volume_in, 1.25, 0.0001, "machine totals were not restored")
	# The document must be plain, readable JSON.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(typeof(parsed) == TYPE_DICTIONARY, "save file is not a JSON object")
	check(parsed.has("plot") and parsed.has("economy"), "save file is missing sections")
	SaveSystem.delete_save(path)
	done()

func test_expansion() -> void:
	_setup()
	await step(2)
	var before_extent := plot.half_extent
	var before_cap := manager.per_plot_cap
	Economy.from_dict({"money": 0, "day": 1})
	check(not plot.try_expand(), "expanded the plot without money")
	Economy.from_dict({"money": 100000, "day": 1})
	check(plot.try_expand(), "could not expand with plenty of money")
	check(plot.half_extent > before_extent, "expansion did not grow the plot")
	check(manager.per_plot_cap > before_cap, "expansion did not raise the item cap")
	var far_cell := Vector2i(int(before_extent) + 2, 0)
	check(plot.in_bounds(far_cell), "newly gained ground is still out of bounds")
	done()

func test_upgrades() -> void:
	_setup(false)
	PlayerState.reset()
	Economy.from_dict({"money": 0, "day": 1})
	var base_capacity := PlayerState.stat(&"carry", "capacity_m3")
	check(not PlayerState.try_upgrade(&"carry"), "upgraded with no money")
	Economy.from_dict({"money": 100000, "day": 1})
	var cost := PlayerState.next_cost(&"carry")
	check(PlayerState.try_upgrade(&"carry"), "could not buy an affordable upgrade")
	check_eq(Economy.money, 100000 - cost, "upgrade charged the wrong amount")
	check(PlayerState.stat(&"carry", "capacity_m3") > base_capacity, "upgrade did not improve the rack")
	while not PlayerState.at_max(&"carry"):
		PlayerState.try_upgrade(&"carry")
	check(not PlayerState.try_upgrade(&"carry"), "bought past the last level")
	check_eq(PlayerState.next_cost(&"carry"), -1, "maxed track still reports a cost")
	done()

## Spec: stock sits in boxes on shelves, is carried to the counter and paid for
## there, and walking out with something unpaid makes it disappear.
func test_store() -> void:
	_setup()
	var shop := Store.new()
	shop.setup(manager, plot, 0)
	shop.position = Vector3(0, 0, 0)
	world.add_child(shop)
	await step(4)
	Economy.from_dict({"money": 100000, "day": 1})

	check(shop.slots.size() > 20, "the store has only %d shelf slots" % shop.slots.size())
	var sections := {}
	for slot in shop.slots:
		sections[slot.section] = true
	for want in ["TOOLS", "VEHICLES", "CONVEYORS", "MACHINERY", "DOODADS"]:
		check(sections.has(want), "the store has no %s section" % want)
	var stocked := 0
	for slot in shop.slots:
		if slot.item != null:
			stocked += 1
			var box: LooseItem = slot.item
			check(shop.contains(box.global_position), "a %s box is not on a shelf in the shop" % slot.box)
	check(stocked > 20, "only %d boxes on the shelves" % stocked)

	# The steel axe is a tool: priced off tools.json, and opening it puts the
	# axe in the inventory and on the hotbar.
	var axe_slot: Dictionary = {}
	for slot in shop.slots:
		if slot.kind == &"tool" and slot.target == &"steel_axe":
			axe_slot = slot
	check(not axe_slot.is_empty(), "the store does not stock a steel axe")
	check_eq(shop.price_of(axe_slot), int(GameData.tool(&"steel_axe").cost), "the axe box is mispriced")
	var box: LooseItem = axe_slot.item
	check(box != null, "no axe box on the shelf")
	check(not box.owned, "shelf stock starts out owned")

	# Dragged off the shelf and on to the counter, it is still not yours;
	# paying at the till makes it so.
	var player := _make_player()
	world.add_child(player)
	await step(2)
	check(player._grab_drag_item(box), "could not take hold of the box")
	check(not box.owned, "taking a box off the shelf made it the player's")
	player._release_dragged()
	box.teleport(Transform3D(Basis(), shop.till_position() + Vector3(0, 0.5, 0)))
	await step(10)
	var money_before := Economy.money
	var price := shop.price_of(axe_slot)
	var receipt := shop.buy()
	check_eq(int(receipt.bought), 1, "the till bought %d box(es)" % int(receipt.bought))
	check_eq(Economy.money, money_before - price, "money did not move by the price")
	check(box.owned, "a paid box is still not the player's")
	check(not PlayerState.owns_tool(&"steel_axe"), "the axe was handed over before the box was opened")
	shop.open_box(box)
	check(PlayerState.owns_tool(&"steel_axe"), "opening the box did not give the axe")
	check(PlayerState.hotbar.has(&"steel_axe"), "the new axe did not go on the hotbar")
	await step(4)
	check_eq(box.state, LooseItem.State.POOLED, "the opened box is still lying about")
	shop.restock()
	check(axe_slot.item == null, "a tool you own is still on the shelf")

	# Machine tiers: T2 cannot be bought before the machine itself, and
	# opening T2 raises the machine's tier.
	var t1: Dictionary = {}
	var t2: Dictionary = {}
	for slot in shop.slots:
		if slot.kind == &"tier" and slot.target == &"crusher":
			if slot.tier == 1:
				t1 = slot
			elif slot.tier == 2:
				t2 = slot
	check(not t1.is_empty() and not t2.is_empty(), "the crusher tiers are not stocked")
	check(shop.blocked(t2) != "", "crusher T2 could be bought without a crusher")
	var t2_box: LooseItem = t2.item
	t2_box.teleport(Transform3D(Basis(), shop.till_position() + Vector3(0, 0.6, 0)))
	var refused := shop.buy()
	check_eq(int(refused.bought), 0, "crusher T2 sold before the crusher")
	var t1_box: LooseItem = t1.item
	var receipt2 := shop.buy([t1_box] as Array[LooseItem])
	check(t1_box.owned, "crusher T1 was not bought")
	shop.open_box(t1_box)
	check(PlayerState.is_unlocked(&"crusher"), "crusher T1 did not unlock the crusher")
	await step(2)
	shop.buy([t2_box] as Array[LooseItem])
	check(t2_box.owned, "crusher T2 was refused once the crusher was owned")
	shop.open_box(t2_box)
	check_eq(PlayerState.level(&"crusher"), 2, "crusher T2 did not raise the tier")

	# An unpaid box will not open, and carried out it goes back on the shelf.
	var pad_slot: Dictionary = {}
	for slot in shop.slots:
		if slot.target == &"pad_quad":
			pad_slot = slot
	var fresh: LooseItem = pad_slot.item
	check_eq(shop.open_box(fresh), "that one has not been paid for", "an unpaid box opened anyway")
	var outside := shop.global_position + Vector3(0, 1, 60)
	fresh.teleport(Transform3D(Basis(), outside))
	await step(40)
	var stranded := 0
	for item in manager.free_items():
		if item.item_id == pad_slot.box and not shop.contains(item.global_position):
			stranded += 1
	check_eq(stranded, 0, "unpaid stock survived being carried out of the shop")
	check(pad_slot.item != null, "the shelf did not put a replacement out")

	# Land is sold at the desk.
	var tier_before := plot.tier
	var land := shop.buy_land()
	check(plot.tier == tier_before + 1, "the desk did not sell a parcel (%s)" % land)

	# The summit store sells what the town store does not.
	var summit := Store.new()
	summit.setup(manager, plot, 0, &"summit")
	summit.position = Vector3(80, 0, 0)
	world.add_child(summit)
	await step(4)
	var has_heavy := false
	var has_pro := false
	for slot in summit.slots:
		has_heavy = has_heavy or slot.target == &"pad_log_truck"
		has_pro = has_pro or slot.target == &"goldleaf_axe"
	check(has_heavy and has_pro, "the summit store is missing its heavy trucks or pro tools")
	check(not summit.has_land_desk(), "the summit store sells land")
	for slot in shop.slots:
		check(slot.target != &"pad_log_truck", "the town store sells the log truck")
	done()

func test_carry() -> void:
	_setup()
	var player := _make_player()
	world.add_child(player)
	var bin := StorageBin.new()
	bin.setup(manager, GameData.building(&"storage"), 0)
	bin.position = Vector3(0, 0, -10)
	world.add_child(bin)
	await step(4)

	PlayerState.levels[&"carry"] = 1
	var small := Solid.cylinder(0.20, 0.18, 1.2)   # ~0.13 m3: one fills a bare rack
	var first := spawn(&"wood_pine", Vector3(1, 1, 1), small)
	var second := spawn(&"wood_pine", Vector3(2, 1, 1), small)
	check(player.pick_up(first), "could not pick up a small log")
	check_eq(player.carried_count(), 1, "rack count is wrong")
	check_near(player.carried_volume(), first.volume(), 0.0001, "rack volume is wrong")
	check(not player.pick_up(second), "the starting rack took more than its %.2f m3" % player.capacity_m3())

	PlayerState.levels[&"carry"] = 3
	check(player.pick_up(second), "rack did not grow with the upgrade")
	await step(10)
	check_eq(first.state, LooseItem.State.HELD, "carried item is not in the held state")
	check(first.global_position.distance_to(player.global_position) < 2.5,
		"held item did not follow the player")

	# A whole trunk is not pocket-sized, whatever the rack level.
	PlayerState.levels[&"carry"] = 5
	var trunk := spawn(&"wood_pine", Vector3(4, 1, 1), Solid.cylinder(0.34, 0.2, 6.0))
	check(not player.pick_up(trunk), "the rack accepted a 6 m trunk")
	check(trunk.length() > player.max_piece_length(), "test trunk is not actually oversized")

	var moved := player.deposit_into(bin)
	check_eq(moved, 2, "depositing into the bin moved %d pieces" % moved)
	check_eq(player.carried_count(), 0, "rack not emptied after depositing")
	check(bin.count() > 0, "the bin did not receive the deposit")

	var third := spawn(&"wood_pine", Vector3(3, 1, 1), small)
	player.pick_up(third)
	player._drop(1)
	await step(10)
	check_eq(third.state, LooseItem.State.FREE, "dropped item is not free again")
	done()

## Spec: the player lifts up to 100 kg and moves up to 1000 kg. Both limits are
## about weight, so the same shape in a denser wood stops being liftable.
func test_handling_limits() -> void:
	_setup()
	var player := _make_player()
	world.add_child(player)
	await step(4)
	# Play-test: carry and drag both reach a tonne.
	check_near(player.lift_limit_kg(), 1000.0, 0.001, "the lift limit is not 1000 kg")
	check_near(player.move_limit_kg(), 1000.0, 0.001, "the drag limit is not 1000 kg")
	PlayerState.levels[&"carry"] = 4
	var heavy := spawn(&"wood_ironwood", Vector3(3, 1, 0), Solid.cylinder(0.42, 0.42, 2.5))
	check(heavy.mass > 420.0 and heavy.mass < 1000.0, "heavy test piece is %.0f kg" % heavy.mass)
	check(player.pick_up(heavy), "a %.0f kg piece would not go on the rack" % heavy.mass)
	player._drop(1)
	await step(4)
	player._grab_drag_item(heavy)
	check_eq(heavy.state, LooseItem.State.CARRIED, "a draggable piece was refused")
	check(heavy.owned, "dragging a piece did not make it the player's")
	player._release_dragged()
	await step(2)
	# A full ironwood trunk is past a tonne: neither lifted nor dragged.
	var trunk := spawn(&"wood_ironwood", Vector3(6, 1, 0), Solid.cylinder(0.58, 0.42, 10.0))
	check(trunk.mass > 1000.0, "test trunk is %.0f kg, expected over 1000" % trunk.mass)
	check(not player.pick_up(trunk), "the rack lifted a %.0f kg trunk" % trunk.mass)
	player._grab_drag_item(trunk)
	check(player.dragged == null, "a %.0f kg trunk was dragged past a 1000 kg limit" % trunk.mass)
	done()

## Play-test: things are dragged by the point you grab them at. A log taken
## by one end comes along by that end, and hangs from it.
func test_drag_at_point() -> void:
	_setup(false)
	var player := _make_player()
	world.add_child(player)
	await step(4)
	player._hold_for_tests = true
	var log_piece := manager.spawn(&"wood_pine", Transform3D(LooseItem.lying_basis(PI * 0.5),
		Vector3(0, 0.3, -2.5)), 0, Vector3.ZERO, Solid.cylinder(0.15, 0.13, 2.4))
	await step(30)
	var end := log_piece.global_transform * Vector3(0, 1.1, 0)
	check(player._grab_drag_item(log_piece, end), "could not grab the log by its end")
	for i in 120:
		await step(1)
	var point := player.drag_point()
	var target := player.drag_target()
	check(point.distance_to(target) < 0.6, "the grabbed end is %.2f m from the hand" % point.distance_to(target))
	check(log_piece.global_position.y < point.y - 0.3, "the log does not hang from the end it was grabbed by")
	check(log_piece.global_position.distance_to(target) > 0.6, "the log was pulled by its middle, not the point grabbed")
	player._release_dragged()
	check_eq(log_piece.state, LooseItem.State.FREE, "letting go did not free the log")

	# Heavy things come slowly: the hand has a tonne of strength, not more.
	var heavy := manager.spawn(&"wood_ironwood", Transform3D(LooseItem.lying_basis(PI * 0.5),
		Vector3(2, 0.5, -3)), 0, Vector3.ZERO, Solid.cylinder(0.4, 0.38, 2.4))
	await step(30)
	check(heavy.mass > 300.0, "the heavy test piece is only %.0f kg" % heavy.mass)
	check(player._grab_drag_item(heavy, heavy.global_position), "could not grab a %.0f kg log" % heavy.mass)
	await step(20)
	check(heavy.linear_velocity.length() < 14.0, "a heavy log was yanked about")
	player._release_dragged()
	done()

## Play-test: tools live in an inventory and are used from a hotbar; with an
## empty hand the left button drags.
func test_hotbar_tools() -> void:
	_setup()
	var player := _make_player()
	world.add_child(player)
	await step(4)
	check(PlayerState.owns_tool(&"rusty_axe") and PlayerState.owns_tool(&"club_hammer"), "a new player has no tools")
	check_eq(PlayerState.hotbar_tool(0), &"rusty_axe", "the axe is not in slot 1")
	check_eq(PlayerState.hotbar_tool(1), &"club_hammer", "the hammer is not in slot 2")
	check_eq(player.selected_tool(), &"", "the player starts with a tool in hand")
	player.select_slot(0)
	check_eq(player.selected_tool(), &"rusty_axe", "slot 1 did not take the axe")
	check_near(player._tool_stat("damage", 0.0), 34.0, 0.001, "the axe in hand does not cut like a rusty axe")
	player.select_slot(0)
	check_eq(player.selected_tool(), &"", "pressing the slot again did not empty the hand")
	player.cycle_hotbar(1)
	check_eq(player.selected_tool(), &"rusty_axe", "the wheel did not step to the first tool")
	player.cycle_hotbar(-1)
	check_eq(player.selected_tool(), &"", "the wheel did not step back to an empty hand")

	check(PlayerState.give_tool(&"goldleaf_axe"), "could not give a tool")
	check(PlayerState.hotbar.has(&"goldleaf_axe"), "a new tool did not land on the hotbar")
	PlayerState.set_hotbar(0, &"goldleaf_axe")
	check_eq(PlayerState.hotbar_tool(0), &"goldleaf_axe", "set_hotbar did not put the tool in the slot")
	check_eq(PlayerState.hotbar.count(&"goldleaf_axe"), 1, "a tool is on the hotbar twice")
	player.select_slot(0)
	check_near(player._tool_stat("damage", 0.0), 320.0, 0.001, "the goldleaf axe cuts like something else")

	# A tree takes an axe; a hammer will not fell it.
	var tree := _make_tree(6.0, 0.3, 0.6, 0)
	tree.position = Vector3(0, 0, -2.0)
	world.add_child(tree)
	await step(2)
	PlayerState.set_hotbar(1, &"club_hammer")
	player.select_slot(1)
	player.camera.look_at(tree.global_position + Vector3(0, 1.5, 0))
	player._swing_cd = 0.0
	player._swing()
	check_near(tree.trunk_cut, 0.0, 0.001, "a hammer cut the tree")

	var saved := PlayerState.to_dict()
	PlayerState.reset()
	PlayerState.from_dict(saved)
	check(PlayerState.owns_tool(&"goldleaf_axe"), "tools did not survive a save")
	check_eq(PlayerState.hotbar_tool(0), &"goldleaf_axe", "the hotbar did not survive a save")
	# Saves from before tools were things turn axe levels into axes.
	PlayerState.from_dict({"levels": {"axe": 3, "hammer": 2}})
	check(PlayerState.owns_tool(&"timber_axe") and PlayerState.owns_tool(&"sledge"), "an old save lost its tools")
	done()

## Play-test: in build mode, F selects a building to edit, and the handles
## move it, resize it and turn it.
func test_build_edit() -> void:
	_setup()
	Economy.from_dict({"money": 100000, "day": 1})
	var belt := plot.place(GameData.building(&"conveyor"), Vector2i(0, 0), 0) as Conveyor
	var mill := plot.place(GameData.building(&"sawmill"), Vector2i(-8, -8), 0)
	check(mill != null, "the mill was not placed")
	await step(2)
	var belt_at := belt.global_position
	var index := plot.index_at_world(belt_at)
	check(index >= 0, "the belt is not on the occupancy grid")
	check_eq(plot.edit(index, Vector2i(3, 0), Vector3i.ZERO, Vector3i(1, 1, 4), 0.0), "", "moving the belt failed")
	await step(2)
	var moved := plot.placed[index].node as Conveyor
	check(plot.index_at_world(moved.global_position) == index, "the moved belt is not where the grid says")
	check_eq(plot.index_at_world(belt_at), -1, "the old cells are still taken")

	# Belts stretch: longer belt, longer price.
	var money := Economy.money
	check_eq(plot.edit(index, Vector2i(3, 0), Vector3i.ZERO, Vector3i(1, 1, 8), 0.0), "", "stretching the belt failed")
	await step(2)
	var long := plot.placed[index].node as Conveyor
	check_near(long.length, 8.0, 0.001, "the stretched belt is %.1f m" % long.length)
	check(Economy.money < money, "stretching the belt was free")
	check(Plot.size_limits(GameData.building(&"sawmill")).is_empty(), "a machine can be resized")

	# Turned a quarter, and lifted.
	check_eq(plot.edit(index, Vector2i(3, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 8), 0.5), "", "turning the belt failed")
	await step(2)
	var turned: Node3D = plot.placed[index].node
	check_near(turned.position.y - plot.to_local(plot.cell_to_world(Vector2i(3, 0), Vector3i(1, 1, 8), Vector3i(0, 1, 0))).y,
		0.5, 0.001, "the belt was not lifted")
	# A move onto the mill is refused and changes nothing.
	var before: Dictionary = plot.placed[index].duplicate()
	var err := plot.edit(index, Vector2i(-8, -8), Vector3i(0, 1, 0), Vector3i(1, 1, 8), 0.5)
	check(err != "", "a belt was moved on top of a machine")
	check_eq(plot.placed[index].cell, before.cell, "a refused move still moved the belt")

	# Size and height survive a save.
	var doc := plot.to_dict()
	plot.from_dict(doc)
	await step(2)
	var found := false
	for rec in plot.placed:
		if (rec.def as BuildingDef).id == &"conveyor":
			found = true
			check_eq((rec.def as BuildingDef).size, Vector3i(1, 1, 8), "the belt's size was not saved")
			check_near(float(rec.get("lift", 0.0)), 0.5, 0.001, "the belt's height was not saved")
	check(found, "the belt did not come back from the save")

	# The drag maths: a ray passing 3 m along an axis reads as 3 m.
	var along := BuildGizmo.along_axis(Vector3.ZERO, Vector3.RIGHT, Vector3(3, 5, 5), Vector3(0, -1, -1).normalized())
	check_near(along, 3.0, 0.001, "dragging along an axis measured %.2f m" % along)
	var angle := BuildGizmo.angle_about(Vector3.ZERO, Vector3.UP, Vector3(1, 0, 0), Vector3(0, 5, -1), Vector3(0, -1, 0))
	check_near(absf(angle), PI * 0.5, 0.001, "a quarter turn measured %.2f rad" % angle)
	done()

## Spec: an object is owned once the player picks it up or buys it, and owned
## objects on the property are saved with the game.
func test_ownership() -> void:
	_setup()
	var player := _make_player()
	world.add_child(player)
	await step(4)
	PlayerState.levels[&"carry"] = 4

	var small := Solid.cylinder(0.20, 0.18, 1.2)
	var wild := spawn(&"wood_pine", Vector3(1, 1, 1), small)
	check(not wild.owned, "a freshly spawned piece is already owned")
	check(player.pick_up(wild), "could not pick the test piece up")
	check(wild.owned, "picking a piece up did not make it the player's")
	player._drop(1)
	await step(6)
	check(wild.owned, "putting a piece down gave it away again")

	# Cutting your own wood leaves you owning both halves.
	var halves := manager.split_item(wild, 0.5)
	check_eq(halves.size(), 2, "split did not produce two pieces")
	for half in halves:
		check(half.owned, "a cut half was not owned")

	# A machine on your plot makes your material.
	var mill := _inline(&"sawmill", Vector3(0, 0, -12))
	await step(4)
	var wild_log := manager.spawn(&"wood_pine", Transform3D(LooseItem.lying_basis(0.0),
		Vector3(0, 0.6, -12 + mill.length * 0.5 - 0.35)), 0, Vector3.ZERO, Solid.cylinder(0.2, 0.2, 1.0))
	check(not wild_log.owned, "a log dropped on the belt should start unowned")
	await _through(mill, wild_log)
	check(mill.total_processed > 0, "the planker produced nothing")
	var milled := 0
	for item in manager.free_items():
		if item.item_id == &"lumber_pine":
			milled += 1
			check(item.owned, "lumber milled on the player's plot was not owned")
	check(milled > 0, "no lumber came out of the mill")

	# Owned material on the plot survives a save round-trip; wild material does not.
	var owned_before := manager.owned_items(plot.global_position, plot.half_extent * 1.4142).size()
	check(owned_before > 0, "nothing owned on the plot to save")
	var stray := spawn(&"wood_oak", Vector3(2, 1, 4), small)
	check(not stray.owned, "stray test piece should not be owned")
	var path := "user://test_owned.json"
	check(SaveSystem.save_game(plot, null, path, manager), "saving failed")
	check(SaveSystem.load_game(plot, null, path, manager), "loading failed")
	await step(4)
	var owned_after := manager.owned_items(plot.global_position, plot.half_extent * 1.4142).size()
	check_eq(owned_after, owned_before, "owned item count changed over a save round-trip")
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(typeof(doc) == TYPE_DICTIONARY and doc.has("loose"), "save has no loose-item section")
	if typeof(doc) == TYPE_DICTIONARY:
		check_eq((doc["loose"] as Array).size(), owned_before, "wrong number of pieces written")
	SaveSystem.delete_save(path)
	done()

func test_hauler() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0)
	truck.position = Vector3(0, 1.5, 0)
	world.add_child(truck)
	await step(60)
	var resting_y := truck.global_position.y
	check(resting_y > 0.2 and resting_y < 2.0,
		"hauler did not settle on its suspension (y=%.2f)" % resting_y)
	check(truck.global_transform.basis.y.dot(Vector3.UP) > 0.9, "hauler is not upright at rest")

	# Logs dropped into the bed land in it and stay real bodies.
	var loaded := 0.0
	for i in 4:
		var piece := manager.spawn(&"wood_pine", Transform3D(
			truck.global_transform.basis * LooseItem.lying_basis(PI * 0.5),
			truck.global_transform * Vector3(0, 2.0 + float(i) * 0.5, 0.2 + float(i) * 0.5)),
			0, Vector3.ZERO, Solid.cylinder(0.18, 0.16, 1.6))
		loaded += piece.volume()
	await step(60)
	check_eq(truck.cargo_count(), 4, "hauler did not see the load in its bed")
	check_near(truck.cargo_volume(), loaded, 0.0001, "hauler miscounted its load")
	check(truck.cargo_capacity_m3 > loaded, "test load should fit well inside the bed")
	check_eq(manager.active_count(), 4, "the load stopped being physics bodies")
	for item in truck.cargo_list():
		check(not item.freeze and item.state == LooseItem.State.FREE, "a piece in the bed was locked down")
		check(item.carrier == truck, "a piece in the bed does not know it is in the truck")

	# Driven sensibly - away from a standstill, then braking - the load stays in.
	var start := truck.global_position
	truck.autopilot = true
	truck.input_throttle = 1.0
	await step(150)
	var travelled: float = start.distance_to(truck.global_position)
	check(travelled > 6.0, "hauler barely moved under throttle (%.1f m)" % travelled)
	check(truck.linear_velocity.length() <= truck.max_speed * 1.5, "hauler exceeded its speed cap")
	check(truck.global_transform.basis.y.dot(Vector3.UP) > 0.7, "hauler rolled while driving")
	check_eq(truck.cargo_count(), 4, "the load fell out while pulling away")
	truck.input_throttle = 0.0
	truck.input_brake = true
	await step(120)
	check(truck.linear_velocity.length() < 1.0, "the truck did not stop under braking")
	check_eq(truck.cargo_count(), 4, "the load went over the headboard under braking")
	truck.input_brake = false
	truck.autopilot = false

	var wheels := 0
	for child in truck.get_children():
		if child is MeshInstance3D and truck._wheels.has(child) and (child as Node3D).position.y < 0.0:
			wheels += 1
	check(wheels >= 4, "the hauler should have wheels, found %d" % wheels)

	# The load is saved with the truck, relative to the bed.
	var doc := truck.to_dict()
	check_eq((doc.cargo as Array).size(), 4, "the save did not record the load")
	truck.from_dict(doc)
	await step(30)
	check_eq(truck.cargo_count(), 4, "cargo did not survive a save/load round-trip")
	check_eq(manager.active_count(), 4, "reloading the truck doubled or lost its load")
	check_near(truck.cargo_volume(), loaded, 0.0001, "the reloaded load is a different size")

	# Unloading drops the tailgate and walks the load out the back.
	var dropped := truck.unload()
	check_eq(dropped, 4, "unloading counted the wrong number of pieces")
	await step(20)
	check(truck._tailgate.disabled, "the tailgate did not open to unload")
	await step(360)
	check_eq(truck.cargo_count(), 0, "the bed is not empty after unloading")
	var returned := manager.free_items()
	check_eq(returned.size(), 4, "pieces went missing while unloading")
	check_near(loose_volume(), loaded, 0.0001, "the load changed size on the way out")
	var inverse := truck.global_transform.affine_inverse()
	for item in returned:
		# Out at the rear: behind the back axle, if not always clear of the
		# overhang - a log dropped off a tailgate can roll back under it.
		check((inverse * item.global_position).z > 1.7, "a piece came out somewhere other than the back (%s)" % str((inverse * item.global_position).snapped(Vector3(0.01, 0.01, 0.01))))
		check(item.carrier == null, "an unloaded piece still thinks it is in the truck")
	check(not truck._tailgate.disabled, "the tailgate did not close after unloading")

	# One at a time, and the sink protocol the player and belts use.
	check(truck.load_item(&"ore_iron"), "load_item refused with room in the bed")
	check(truck.load_item(&"ore_iron"), "load_item refused a second piece")
	await step(30)
	check_eq(truck.cargo_count(), 2, "load_item did not put pieces in the bed")
	check(truck.unload_one(), "could not drop a single item")
	await step(240)
	check_eq(truck.cargo_count(), 1, "drop-one removed the wrong amount")
	check(truck.can_accept(&"lumber_pine"), "hauler refuses items while it has room")
	truck.cargo_capacity_m3 = 0.001
	check(not truck.can_accept(&"lumber_pine"), "hauler accepts items when full")
	done()

## Spec from play-testing: the load is loose. It weighs the truck down, slides
## forward under hard braking, and a truck that goes over dumps it.
func test_hauler_loose_load() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0)
	truck.position = Vector3(0, 1.5, 0)
	world.add_child(truck)
	await step(90)
	var empty_y := truck.global_position.y
	for i in 6:
		check(truck.load_item(&"wood_pine", Solid.cylinder(0.22, 0.2, 1.8)), "the bed refused a log")
	await step(120)
	check_eq(truck.cargo_count(), 6, "the logs did not all stay in the bed")
	var laden_y := truck.global_position.y
	check(laden_y < empty_y - 0.01,
		"the load does not weigh the truck down (%.3f empty, %.3f laden)" % [empty_y, laden_y])

	# Hard braking from speed: the load surges toward the cab and fetches up
	# against the headboard - it moves, but it stays aboard.
	truck.autopilot = true
	truck.input_throttle = 1.0
	await step(150)
	var inverse := truck.global_transform.affine_inverse()
	var before := 0.0
	for item in truck.cargo_list():
		before += (inverse * item.global_position).z
	truck.input_throttle = 0.0
	truck.input_brake = true
	await step(90)
	inverse = truck.global_transform.affine_inverse()
	var after := 0.0
	for item in truck.cargo_list():
		after += (inverse * item.global_position).z
	check_eq(truck.cargo_count(), 6, "hard braking threw the load out")
	check(after < before - 0.05, "the load did not shift forward under hard braking")
	truck.input_brake = false

	# Hold the truck upside down in the air: nothing holds the load in but
	# the sides and gravity, so it falls out of the open top. Truck and load
	# are turned over together, as if the truck had rolled.
	truck.autopilot = false
	var before_roll := truck.global_transform
	var rolled := Transform3D(before_roll.basis * Basis(Vector3.FORWARD, PI),
		before_roll.origin + Vector3(0, 4.0, 0))
	for item in truck.cargo_list():
		item.teleport(rolled * (before_roll.affine_inverse() * item.global_transform))
	truck.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	truck.freeze = true
	PhysicsServer3D.body_set_state(truck.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, rolled)
	await step(150)
	check_eq(truck.cargo_count(), 0, "upside down, %d pieces stayed in the bed" % truck.cargo_count())
	check_eq(manager.active_count(), 6, "the spilled load did not land as real pieces")
	done()

## Spec: a pad spawns one copy of its vehicle; triggering it again removes the
## old one first.
## It used to be steered by dropping a yaw torque on the chassis, so the body
## turned and the velocity carried straight on - the truck slid about like it
## was on ice. Cornering means the velocity follows the nose.
func test_hauler_grip() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0)
	truck.position = Vector3(0, 1.5, 0)
	world.add_child(truck)
	await step(60)

	# Get it rolling in a straight line first - not so far that the turn runs
	# it into the edge of the test ground.
	truck.autopilot = true
	truck.input_throttle = 1.0
	await step(70)
	var cruising := truck.linear_velocity.length()
	check(cruising > 4.0, "the truck only reached %.1f m/s under full throttle" % cruising)

	# Now turn. The nose has to come round, and the velocity has to come round
	# with it rather than carrying on in the old direction.
	var heading_before := (-truck.global_transform.basis.z)
	truck.input_steer = 1.0
	var worst_slip := 0.0
	for i in 90:
		await step(1)
		var forward := -truck.global_transform.basis.z
		var velocity := truck.linear_velocity
		velocity.y = 0.0
		if velocity.length() < 1.0:
			continue
		# The angle between where the truck points and where it is actually
		# going. On ice this opens right up; with grip it stays small.
		worst_slip = maxf(worst_slip, rad_to_deg(forward.angle_to(velocity.normalized())))
	var heading_after := (-truck.global_transform.basis.z)
	var turned := rad_to_deg(heading_before.angle_to(heading_after))

	check(turned > 15.0, "steering only turned the truck %.0f degrees in 1.5 s" % turned)
	check(worst_slip < 35.0,
		"the truck slid at up to %.0f degrees away from its nose - that is ice, not grip" % worst_slip)
	check(truck.global_transform.basis.y.dot(Vector3.UP) > 0.7, "the truck rolled over while cornering")
	done()

## Spec from play-testing: a truck with nobody in it should not be shoved
## around by whatever walks into it.
func test_hauler_parked() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0)
	truck.position = Vector3(0, 1.5, 0)
	world.add_child(truck)
	await step(90)
	check(truck.parked(), "a truck with no driver does not think it is parked")
	var resting := truck.global_position

	# Shove it, hard, several times over - the sort of thing a player walking
	# into it or a rolling log would do.
	for i in 6:
		truck.sleeping = false
		truck.apply_central_impulse(Vector3(2500, 0, 1800))
		await step(20)
	var shifted := resting.distance_to(truck.global_position)
	check(shifted < 2.0, "a parked truck was shoved %.1f m" % shifted)

	# With a driver aboard it moves again, so the brake is not just glue.
	truck.autopilot = true
	truck.sleeping = false
	check(not truck.parked(), "the truck still thinks it is parked with a driver aboard")
	truck.input_throttle = 1.0
	var before := truck.global_position
	await step(150)
	check(before.distance_to(truck.global_position) > 5.0,
		"the truck would not drive away after being parked")
	done()

func test_vehicle_pad() -> void:
	_setup()
	Economy.from_dict({"money": 50000, "day": 1})
	plot.vehicle_host = world
	check(PlayerState.try_buy_vehicle(), "could not buy the hauler")
	check(PlayerState.owns_vehicle(), "buying the hauler did not register")
	var node := plot.place(GameData.building(&"vehicle_pad"), Vector2i(2, 2), 0)
	var pad := node as VehiclePad
	check(pad != null, "the pad was not placed")
	await step(4)
	check(not pad.has_vehicle(), "a fresh pad already has a truck on it")

	var first := pad.spawn()
	await step(10)
	check(first != null, "the pad spawned nothing")
	check(pad.has_vehicle(), "the pad does not know about the truck it spawned")
	check(_haulers_in(world) == 1, "spawning made %d trucks" % _haulers_in(world))
	if first != null:
		check(first.global_position.distance_to(pad.global_position) < 4.0,
			"the truck did not appear on its pad")
		# Drive it away, so a respawn has something to clean up at a distance.
		first.global_position = pad.global_position + Vector3(20, 1.4, 20)

	var second := pad.spawn()
	await step(10)
	check(second != null, "the pad would not spawn a replacement")
	check(second != first, "the pad handed back the same truck")
	check(not is_instance_valid(first), "the old truck was left standing after a respawn")
	check(_haulers_in(world) == 1, "after a respawn there are %d trucks" % _haulers_in(world))

	check(pad.recall(), "recalling the truck did nothing")
	await step(10)
	check(not pad.has_vehicle(), "the pad still has a truck after a recall")
	check(_haulers_in(world) == 0, "a recall left %d trucks behind" % _haulers_in(world))
	done()

## Spec from play-testing: more vehicles. Each one is sold in the store as a
## crated pad, and the pad spawns that vehicle and no other.
func test_vehicle_catalogue() -> void:
	_setup()
	check(GameData.vehicles.size() >= 7, "only %d vehicles in the game" % GameData.vehicles.size())
	plot.vehicle_host = world
	var sold: Array = []
	for entry in GameData.store_products():
		sold.append(String(entry.get("target", "")))
	var x := -12
	for id in GameData.vehicles:
		var pad_def: BuildingDef = null
		for b: BuildingDef in GameData.buildings.values():
			if b.kind == &"pad" and b.vehicle == id:
				pad_def = b
		check(pad_def != null, "no pad spawns the %s" % id)
		if pad_def == null:
			continue
		check(sold.has(String(pad_def.id)), "the store does not sell the %s" % pad_def.display_name)
		check(pad_def.unlock_cost > 0, "the %s is free" % id)
		PlayerState.unlocked_buildings.append(pad_def.id)
		var pad := plot.place(pad_def, Vector2i(x, -12), 0) as VehiclePad
		x += 5
		check(pad != null, "could not place the %s" % pad_def.display_name)
		if pad == null:
			continue
		await step(2)
		var v := pad.spawn() as Hauler
		await step(2)
		check(v != null and v.vehicle_id == id, "the %s pad spawned the wrong thing" % id)
		if v != null:
			pad.recall()
	done()

## Every vehicle sits on its wheels, drives off under throttle without
## tipping over, and - if it has a bed - holds what is put in it.
func test_vehicle_fleet() -> void:
	for id in GameData.vehicles:
		_setup(false)
		var truck := Hauler.new()
		truck.setup(manager, 0, id)
		world.add_child(truck)
		truck.global_position = Vector3(0, truck.spawn_height(), 0)
		await step(90)
		var up := truck.global_transform.basis.y.dot(Vector3.UP)
		check(up > 0.95, "the %s does not sit level (up %.2f)" % [id, up])
		var belly := truck.global_position.y - truck.body_size.y * 0.5
		check(belly > 0.1, "the %s sits on its belly (%.2f m clear)" % [id, belly])
		check(truck.parked() and truck.sleeping, "the parked %s did not settle" % id)
		if truck.has_bed():
			check(truck.load_item(&"lumber_pine"), "the %s would not take a plank" % id)
			await step(40)
			check_eq(truck.cargo_count(), 1, "the %s lost the plank from its bed" % id)
		else:
			check(not truck.can_accept(&"lumber_pine"), "the %s has no bed but takes cargo" % id)
		var start := truck.global_position
		truck.autopilot = true
		truck.input_throttle = 1.0
		await step(100)
		var went := start.distance_to(truck.global_position)
		check(went > 5.0, "the %s only moved %.1f m under full throttle" % [id, went])
		check(truck.linear_velocity.length() <= truck.max_speed * 1.5, "the %s broke its speed cap" % id)
		check(truck.global_transform.basis.y.dot(Vector3.UP) > 0.8, "the %s tipped over pulling away" % id)
		if truck.has_bed():
			check_eq(truck.cargo_count(), 1, "the %s dropped its plank pulling away" % id)
		truck.queue_free()
	done()

## The dump truck's tub swings up on its hinge, the load slides out of the
## back under gravity, and the tub comes back down empty.
func test_dump_truck() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"dump_truck")
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), 0)
	await step(60)
	for i in 5:
		check(truck.load_item(&"lumber_pine"), "the tub refused a plank")
	await step(60)
	check_eq(truck.cargo_count(), 5, "the tub did not hold its load")
	check_eq(truck.unload(), 5, "unloading counted the wrong load")
	var highest := 0.0
	for i in 12:
		await step(20)
		highest = maxf(highest, truck.tub_angle())
	check(highest > 0.8, "the tub only tipped to %.2f rad" % highest)
	await step(300)
	check_eq(truck.cargo_count(), 0, "the tub kept %d pieces" % truck.cargo_count())
	check_near(truck.tub_angle(), 0.0, 0.001, "the tub did not come back down")
	check(not truck._tailgate.disabled, "the tub's tailgate stayed open")
	var inverse := truck.global_transform.affine_inverse()
	for item in manager.free_items():
		check((inverse * item.global_position).z > truck.bed_mid_z, "a plank came out somewhere other than the back")
	done()

## Debug setting: with unlimited money on, anything can be bought and nothing
## is taken off you.
func test_unlimited_money() -> void:
	_setup()
	Economy.from_dict({"money": 100, "day": 1})
	check(not Economy.can_afford(1000000), "a fortune is affordable with $100")
	Settings.set_value(&"unlimited_money", true, false)
	check(Economy.can_afford(1000000), "unlimited money cannot afford things")
	check(Economy.try_spend(1000000), "unlimited money would not spend")
	check_eq(Economy.money, 100, "unlimited money still took the money")
	check(PlayerState.try_unlock(&"pad_crane_truck"), "unlimited money could not unlock the crane truck")
	Settings.set_value(&"unlimited_money", false, false)
	check(not Economy.try_spend(1000000), "turning it off left money unlimited")
	done()

## Spec: every machine has a set power, beyond which it has no effect. The crane
## will not lift past its rating and the winch will not pull past its own.
func test_vehicle_rig() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0)
	truck.position = Vector3(0, 1.5, 0)
	world.add_child(truck)
	await step(40)
	var rig := truck.rig
	check(rig != null, "the hauler has no rig")
	rig.crane_power_kg = 800.0
	rig.winch_power_kg = 3000.0
	rig.reach = 14.0

	# Inside the rating: the crane takes it, and the load goes kinematic so it
	# cannot fight the solver while it is being placed.
	var light := spawn(&"wood_pine", truck.global_position + Vector3(3, 1, 0),
		Solid.cylinder(0.3, 0.3, 3.0))
	check(light.mass < 800.0, "light test piece is %.0f kg" % light.mass)
	check_eq(rig.grab(light), "", "the crane refused a piece inside its rating")
	check(rig.holding(), "the crane does not think it is holding anything")
	check_eq(light.state, LooseItem.State.HELD, "a crane load is still loose in the solver")
	check(light.owned, "lifting a piece with the crane did not make it the player's")

	# The crane drives the object: WASD in, object moves, boom follows.
	var before := light.global_position
	rig.steer(Vector3(1, 0, 0), 0.0, 0, 0.5)
	check(light.global_position.distance_to(before) > 0.1, "steering did not move the load")
	var height := light.global_position.y
	rig.steer(Vector3.ZERO, 1.0, 0, 0.5)
	check(light.global_position.y > height, "raising the load did not lift it")
	var yaw := rig.hold_yaw
	rig.steer(Vector3.ZERO, 0.0, 1, 0.1)
	check_near(absf(rig.hold_yaw - yaw), PI * 0.5, 0.0001, "a turn was not a quarter turn")

	# It cannot be walked past the boom's reach.
	for i in 400:
		rig.steer(Vector3(1, 0, 0), 0.0, 0, 0.1)
	check(rig.head_point().distance_to(light.global_position) <= rig.reach + 0.01,
		"the load went past the crane's reach")

	rig.drop()
	check(not rig.holding(), "dropping left the crane holding on")
	check_eq(light.state, LooseItem.State.FREE, "a dropped load is still kinematic")

	# Past the rating: refused outright, not lifted slowly.
	var heavy := spawn(&"wood_ironwood", truck.global_position + Vector3(3, 1, 2),
		Solid.cylinder(0.5, 0.5, 4.0))
	check(heavy.mass > 800.0, "heavy test piece is only %.0f kg" % heavy.mass)
	check(rig.grab(heavy) != "", "the crane lifted a piece past its rating")
	check(not rig.holding(), "a refused lift still left the crane holding something")

	# Out of reach is refused too, whatever it weighs.
	var distant := spawn(&"wood_pine", truck.global_position + Vector3(40, 1, 0),
		Solid.cylinder(0.2, 0.2, 1.0))
	check(rig.grab(distant) != "", "the crane reached 40 m")

	# The winch takes a load up to its rating and no further.
	check_eq(rig.attach_winch(heavy, heavy.global_position), "",
		"the winch refused a load inside its rating")
	check(rig.anchored, "the winch does not think it is hooked on")
	check(rig.winch_can_pull(), "the winch will not pull a load inside its rating")
	rig.release_winch()

	rig.winch_power_kg = 100.0
	check(rig.attach_winch(heavy, heavy.global_position) != "",
		"the winch hooked a load past its rating")
	check(not rig.anchored, "a refused hook still left the winch attached")

	# And a hooked load past the rating simply does not move.
	rig.winch_power_kg = 100000.0
	check_eq(rig.attach_winch(heavy, heavy.global_position), "", "re-hooking failed")
	rig.winch_power_kg = 10.0
	check(not rig.winch_can_pull(), "an over-rated load still counts as pullable")
	var stood := heavy.global_position
	for i in 30:
		rig.reel(1.0 / 60.0)
	await step(4)
	check(heavy.global_position.distance_to(stood) < 0.5,
		"the winch dragged a load %.0f times past its rating" % (heavy.mass / 10.0))
	done()

func _haulers_in(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child is Hauler and not child.is_queued_for_deletion():
			n += 1
	return n

func test_kill_plane() -> void:
	_setup()
	await step(2)
	var item := spawn(&"wood_pine", Vector3(0, 2, 0))
	item.teleport(Transform3D(Basis(), Vector3(0, Tuning.KILL_PLANE_Y - 10.0, 0)))
	await step(6)
	check(item.global_position.y > Tuning.KILL_PLANE_Y,
		"item below the kill plane was not rescued (y=%.1f)" % item.global_position.y)
	check(manager.stat_killplane > 0, "kill-plane rescue was not counted")
	done()

func test_cap() -> void:
	_setup()
	manager.per_plot_cap = 40
	await step(2)
	for i in 120:
		spawn(&"wood_pine", Vector3(randf_range(-2, 2), 4.0 + float(i) * 0.05, randf_range(-2, 2)))
	await step(10)
	check(manager.active_count() <= 40, "per-plot cap exceeded (%d)" % manager.active_count())
	check(manager.stat_recycled >= 80, "items over the cap were not recycled")
	# Pooling means the node count stays near the cap however many spawns happen.
	var nodes := manager.active_count() + manager.pooled_count()
	check(nodes <= 45, "pooling leaked nodes: %d live+pooled for a cap of 40" % nodes)
	done()

func test_full_base() -> void:
	_setup()
	await step(2)
	Economy.from_dict({"money": 200000, "day": 1})
	PlayerState.reset()
	# A plausible mid-game base: both lines of tunnel machines, belts, a
	# splitter, storage and a workbench, all running at once.
	for id in [&"furnace", &"crusher", &"sander", &"refiner", &"workbench"]:
		PlayerState.try_unlock(id)
	plot.place(GameData.building(&"sawmill"), Vector2i(-10, -8), 0)
	plot.place(GameData.building(&"sander"), Vector2i(-7, -8), 0)
	plot.place(GameData.building(&"crusher"), Vector2i(-2, -8), 0)
	plot.place(GameData.building(&"furnace"), Vector2i(1, -8), 0)
	plot.place(GameData.building(&"refiner"), Vector2i(4, -8), 0)
	plot.place(GameData.building(&"splitter"), Vector2i(0, 2), 0)
	plot.place(GameData.building(&"storage"), Vector2i(8, 2), 0)
	plot.place(GameData.building(&"workbench"), Vector2i(8, -8), 0)
	plot.place(GameData.building(&"conveyor"), Vector2i(-10, 2), 0)
	plot.place(GameData.building(&"conveyor"), Vector2i(-4, 2), 0)
	plot.place(GameData.building(&"conveyor"), Vector2i(4, 2), 0)
	check_eq(plot.placed.size(), 11, "test base was not fully built")
	check_eq(plot.inline_machines().size(), 5, "the tunnel machines were not all placed")
	await step(10)

	var samples: PackedFloat32Array = PackedFloat32Array()
	var prev := Time.get_ticks_usec()
	for i in 600:
		if i % 40 == 0:
			# Fed on to each machine's in-feed lip, the way a belt would.
			for m in plot.inline_machines():
				var wood := m.machine_def.accepts.has(&"wood")
				var feed: StringName = &"wood_pine" if wood else (&"ingot_iron" if m.machine_def.id == &"refiner" else &"ore_iron")
				var dims := Solid.cylinder(0.2, 0.17, randf_range(1.2, 2.6)) if wood else Solid.cube(0.25)
				manager.spawn(feed, Transform3D(m.global_transform.basis * LooseItem.lying_basis(0.0),
					m.global_transform * Vector3(0, 0.6, m.length * 0.5 - 0.35)), 0, Vector3.ZERO, dims, true)
		await get_tree().physics_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - prev) / 1000.0)
		prev = now

	var total := 0.0
	var worst := 0.0
	for v in samples:
		total += v
		worst = maxf(worst, v)
	var avg := total / float(samples.size())
	var budget := 1000.0 / 60.0
	_say("      full base: %d items live, avg %.2f ms/frame, worst %.2f ms (budget %.2f)" % [
		manager.active_count(), avg, worst, budget])
	check(avg < budget, "a full base blew the frame budget (%.2f ms)" % avg)
	check(manager.active_count() <= manager.per_plot_cap, "item cap exceeded under load")
	for m in plot.inline_machines():
		check(m.total_processed > 0, "the %s processed nothing in the running base" % m.def.display_name)
	done()

func _make_tree(height: float, radius: float, taper: float, branches: int) -> ChoppableTree:
	var tree := ChoppableTree.new()
	tree.manager = manager
	tree.wood_item = &"wood_pine"
	tree.trunk_height = height
	tree.trunk_radius = radius
	tree.trunk_taper = taper
	tree.branch_count = branches
	tree.work_per_m2 = 900.0
	return tree

func _make_player() -> Player:
	var p := Player.new()
	p.position = Vector3(0, 1.0, 0)
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
	p.add_child(cam)
	p.manager = manager
	p.plot = plot
	return p
