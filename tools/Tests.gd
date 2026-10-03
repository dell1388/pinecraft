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
	await _test(&"an untouched tree is one draw, and comes apart when cut", test_tree_merged)
	await _test(&"wood is cut wherever the axe lands", test_cut_anywhere)
	await _test(&"a hammer cracks loose chunks down to fit a machine", test_crack_loose)
	await _test(&"resource fields fill to a quota and stop", test_resource_field)
	await _test(&"nothing grows up through a parked vehicle", test_field_avoids_vehicles)
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
	await _test(&"stones are either polished or cut, and which pays depends on the stone", test_gem_line)
	await _test(&"islands, bridges and carved places", test_islands)
	await _test(&"big consolidated biome regions with real relief", test_regions)
	await _test(&"ostars: the continent is where the map puts it", test_ostars_land)
	await _test(&"ostars: forests grow in stands, on dry land, apart", test_ostars_forest)
	await _test(&"ostars: the plot and the build sites lie level, no plate across them", test_ostars_level_ground)
	await _test(&"grass grows on the ground, on green land, not on roads, water or the plot", test_grass_field)
	await _test(&"far trees are leaf clusters and tiers, not buns; leaves marked for the shader", test_tree_stand_ins)
	await _test(&"shaders switch trees and ground between plain and fancy", test_shaders_switch)
	await _test(&"birds fly round you, above the ground, and roost at night", test_birds)
	await _test(&"ostars: each save remembers its map", test_ostars_save_map)
	await _test(&"ostars: roads from home to the town and every trader", test_ostars_roads)
	await _test(&"ostars: ore by hardness, the best in the hardest country", test_ostars_ore)
	await _test(&"traders: each has a model, a tool or a chair, and pivots", test_trader_models)
	await _test(&"traders: each yard buys only its own goods", test_trader_yards)
	await _test(&"traders: an order is loaded into the truck in the bay", test_trader_order)
	await _test(&"traders: fell Old Bjorn's tree and he lets you know", test_bjorns_tree)
	await _test(&"roads are routed over the land, graded, with no tight bends", test_road_routing)
	await _test(&"cave networks: joined up, below sea level, with open mouths", test_cave_network)
	await _test(&"a cave plan read back from its file is the plan as made", test_cave_plan_kept)
	await _test(&"loading work on the worker threads leaves cores free and misses nothing", test_load_workers)
	await _test(&"belted lines of machines keep flowing without jamming", test_machine_lines)
	await _test(&"a tunnel mouth is a real opening", test_tunnel_mouth)
	await _test(&"logs never stick inside a tunnel", test_tunnel_flow)
	await _test(&"a machine takes a trunk with its branches if it fits", test_machine_takes_branches)
	await _test(&"the planker puts a trunk's branches into its plank", test_planker_merges_branches)
	await _test(&"crane keys follow the camera", test_crane_view_axes)
	await _test(&"a front loader pushes a pile, scoops it, lifts it and pours it out", test_front_loader)
	await _test(&"belts dump off their end - no hand-offs", test_belt_dumps_off_end)
	await _test(&"a stretched ramp loads a truck", test_ramp_loads_truck)
	await _test(&"bends carry pieces round", test_belt_bend)
	await _test(&"the merger takes three ways in to one out", test_belt_merge)
	await _test(&"the aligning belt sets pieces straight", test_belt_align)
	await _test(&"the T splitter sends left and right", test_splitter_t)
	await _test(&"a lone machine dumps on the ground until it is full", test_machine_dumps_on_ground)
	await _test(&"workbench assembles from volumes", test_workbench)
	await _test(&"the yard buys what the player owns in it", test_sell_yard)
	await _test(&"orders pay out on delivery", test_quests)
	await _test(&"storage bin stores and dispenses", test_storage)
	await _test(&"a belt runs straight into a machine", test_conveyor_to_machine)
	await _test(&"belts come as ramps, borderless and stoppable", test_conveyor_options)
	await _test(&"belts carry by friction, and things on them can jam", test_conveyor_physics)
	await _test(&"splitter routes round-robin", test_splitter)
	await _test(&"the 3-way splitter takes a belt in and deals onto three belts", test_splitter_belts)
	await _test(&"a splitter's ways lock and unlock, and stay locked through a save", test_splitter_locks)
	await _test(&"filter sorts items by type", test_filter)
	await _test(&"building placement, cost and removal", test_building)
	await _test(&"buildings sit on the pad, not in it", test_buildings_sit_on_pad)
	await _test(&"plans fill with material and turn solid", test_schematic)
	await _test(&"frost wood builds are slippery", test_frost_slip)
	await _test(&"a ladder plan becomes a ladder", test_ladder_plan)
	await _test(&"a sign plan becomes a sign you can write on", test_sign_plan)
	await _test(&"top gear is sold at the summit, the rest in town", test_gear_split)
	await _test(&"hard materials need a better tool and a higher machine tier", test_material_levels)
	await _test(&"a blueprint turned any way fills exactly its grid footprint", test_turned_blueprints)
	await _test(&"sandstone refines into glass; building stone only crushes", test_stone)
	await _test(&"a field kept to a minimum grows one back at once", test_field_minimum)
	await _test(&"utility and mower trailers have gates that come down as ramps", test_trailer_gates)
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
	await _test(&"picking a piece up disturbs nothing", test_pick_up_disturbs_nothing)
	await _test(&"lift and drag limits are weight limits", test_handling_limits)
	await _test(&"things are dragged by the point grabbed", test_drag_at_point)
	await _test(&"tools come from an inventory onto a hotbar", test_hotbar_tools)
	await _test(&"build mode edits placed buildings", test_build_edit)
	await _test(&"dragging a building, its knobs go with it", test_build_knobs_follow)
	await _test(&"an unfilled plan is picked by aiming at it, and shows what it is made of", test_plan_pick)
	await _test(&"several buildings are selected, moved and removed together", test_build_multiselect)
	await _test(&"walls can be thin", test_thin_walls)
	await _test(&"build mode previews the building itself", test_build_preview)
	await _test(&"build mode only opens on your own land", test_build_territory)
	await _test(&"an old save still gets the new belt pieces", test_old_save_belts)
	await _test(&"crane and loader go back to their default pose", test_rig_home)
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
	await _test(&"a seated driver does not upset the vehicle", test_seated_driver)
	await _test(&"getting into a vehicle drops what you carry", test_enter_drops_load)
	await _test(&"bridges give more speed than roads", test_bridge_speed)
	await _test(&"a bridge is smooth to cross flat out", test_bridge_smooth)
	await _test(&"a vehicle left alone stays put", test_parked_holds)
	await _test(&"getting out does not shove the vehicle", test_exit_still)
	await _test(&"the crane claw drops, grabs and comes back up", test_crane_claw)
	await _test(&"the crane lets its grapple down a drop until it meets the ground", test_crane_reaches_down)
	await _test(&"vehicles reach their rated top speed", test_top_speed)
	await _test(&"store-bought buildings are counted copies", test_building_copies)
	await _test(&"winch and crane respect their power ratings", test_vehicle_rig)
	await _test(&"a driven truck's settled load is fixed as it lies", test_load_fixed_while_driven)
	await _test(&"a load heaped over the sides is fixed too", test_heaped_load_fixed)
	await _test(&"trucks tow trailers on a hitch", test_trailers)
	await _test(&"the pickup pulls the utility trailer and lighter, not the big ones", test_pickup_tow_limit)
	await _test(&"trailers chain behind one another", test_trailer_train)
	await _test(&"the driving camera looks past its own truck, trailer and load", test_chase_camera_clear)
	await _test(&"the front loader drives up onto the low-loader and rides on it", test_low_loader)
	await _test(&"vehicles bump into each other", test_vehicles_collide)
	await _test(&"a hard brake at speed slides", test_handbrake_slide)
	await _test(&"a ladder takes you up onto the cab roof", test_cab_ladder)
	await _test(&"the dirt bike rides upright and leans into turns", test_dirtbike)
	await _test(&"a crane lifts another vehicle, not its own trailer", test_crane_lifts_vehicle)
	await _test(&"a piece off the rack can be thrown", test_throw)
	await _test(&"the player walks up a step but not a wall", test_step_up)
	await _test(&"a loader's attachment is picked at its pad", test_loader_pad_attachment)
	await _test(&"plans and belts size to the fine grid", test_fine_scaling)
	await _test(&"a ramp plan fills into a solid wedge", test_ramp_plan)
	await _test(&"door plans open and shut", test_door_plans)
	await _test(&"kill plane rescues fallen items", test_kill_plane)
	await _test(&"the kill plane is below every cave", test_kill_plane_below_caves)
	await _test(&"co-op addresses are read with or without a port", test_net_address)
	await _test(&"co-op guests keep their own tools and gear", test_guest_kit)
	await _test(&"co-op a guest's copy of a world is never saved", test_guest_world_not_saved)
	await _test(&"respawning a truck puts its driver out, solid", test_respawn_with_driver)
	await _test(&"co-op the host's clock shows a new day once", test_guest_new_day_once)
	await _test(&"every balance knob is read by the game", test_balance_file)
	await _test(&"controls can be rebound and saved", test_controls)
	await _test(&"build mode opens empty-handed, with a menu and a copy key", test_build_menu_and_pick)
	await _test(&"the build grid is a quarter metre", test_fine_grid)
	await _test(&"the market moves by material, cheap ones most", test_market_by_material)
	await _test(&"branches are paid for, stored and milled with their trunk", test_branches_counted)
	await _test(&"a felled tree comes down without its leaves", test_felled_no_leaves)
	await _test(&"machines make their output in the size they are set to", test_machine_output_size)
	await _test(&"trucks change gear, climb and turn tighter", test_gearbox)
	await _test(&"a loaded log truck climbs a 38-degree slope", test_climb)
	await _test(&"vehicle parts are bought, fitted to one vehicle at its pad, and switched on and off", test_vehicle_upgrades)
	await _test(&"overdrive gears are more top speed", test_overdrive_speed)
	await _test(&"recovering is rate-limited and not on outriggers", test_recover_limits)
	await _test(&"a crane picks logs out of the trailer it tows", test_crane_from_trailer)
	await _test(&"the loader swaps its bucket for a log grapple", test_loader_grapple)
	await _test(&"the winch hooks what is near the crosshair", test_winch_snap)
	await _test(&"the carry rack does not block the crosshair", test_rack_not_aimed)
	await _test(&"the plot is flat and road-free to its corners", test_plot_clear)
	await _test(&"save slots: several games, and the old save moves in", test_save_slots)
	await _test(&"the lumberjack is posed from what you do, and third person still aims true", test_avatar)
	await _test(&"per-plot cap is enforced", test_cap)
	await _test(&"the cap takes pieces off the property, never on it", test_cap_spares_property)
	await _test(&"shop stock stays on the shelf however busy the world gets", test_shop_stock_kept)
	await _test(&"ore blocks are built to fit any box", test_ore_look_fits_any_box)
	await _test(&"a knock throws the player limp, and he gets back up", test_knocked_flying)
	await _test(&"a truck driving into a player sends him flying", test_truck_knocks_player)
	await _test(&"running into a parked truck does not knock him over", test_run_into_parked_truck)
	await _test(&"a crane's grapple picks a player up", test_crane_lifts_player)
	await _test(&"the crusher crushes a player into meat", test_crusher_crushes_player)
	await _test(&"jumping over or standing by the crusher's hopper is safe", test_crusher_rim_safe)
	await _test(&"TNT: $50 a stick, blows players about, cracks easy ore, not the best", test_tnt)
	await _test(&"one stick of TNT sets off the rest, and throws you far", test_tnt_chain)
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
	# TEST_ONLY=word runs just the tests whose names contain it (or any of
	# several words, split by |).
	var only := OS.get_environment("TEST_ONLY")
	if only != "" and not Array(only.split("|")).any(func(w): return String(name).contains(w)):
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
			total += item.volume() + item.limb_volume()
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
	check(float(b) >= float(a) * 2.0 - 2.0 and float(b) <= float(a) * 2.0 * 1.3,
		"price is not in step with volume (%d vs %d)" % [a, b])
	# Big pieces carry a bonus: a piece eight times the usual size pays well
	# over eight times as much, a small one pays the plain rate.
	var def := GameData.item(&"lumber_pine")
	var usual := def.default_dims()
	var small_piece := Solid.box(Solid.bounds(usual) * 0.5)
	var big_piece := Solid.box(Solid.bounds(usual) * 2.0)
	var rate_small := float(Economy.price_of(&"lumber_pine", small_piece)) / Solid.volume(small_piece)
	var rate_big := float(Economy.price_of(&"lumber_pine", big_piece)) / Solid.volume(big_piece)
	check(rate_big > rate_small * 1.6, "no bonus for a big piece (%.0f vs %.0f per m3)" % [rate_big, rate_small])
	check_near(Economy.size_bonus(def, small_piece), 1.0, 0.0001, "a small piece is marked down")
	# A gemstone's price runs with the square of its volume.
	var gem := GameData.item(&"gem_ruby")
	var g1 := Solid.box(Solid.bounds(gem.default_dims()))
	var g2 := Solid.box(Solid.bounds(gem.default_dims()) * pow(2.0, 1.0 / 3.0))
	var p1 := float(Economy.price_of(&"gem_ruby", g1))
	var p2 := float(Economy.price_of(&"gem_ruby", g2))
	check(absf(p2 / p1 - 4.0) < 0.1, "twice the stone is not four times the price (%.0f vs %.0f)" % [p1, p2])
	# At any size: a stone far past the usual, and one far under it.
	for scale in [16.0, 0.1]:
		var one := Solid.box(Solid.bounds(gem.default_dims()) * pow(scale, 1.0 / 3.0))
		var two := Solid.box(Solid.bounds(gem.default_dims()) * pow(scale * 2.0, 1.0 / 3.0))
		var ratio := Economy.size_bonus(gem, two) * Solid.volume(two) / (Economy.size_bonus(gem, one) * Solid.volume(one))
		check_near(ratio, 4.0, 0.05, "at %.1fx the usual size, twice the stone is not four times the price" % scale)
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
	# One piece: the branches come down still on it.
	check_eq(manager.active_count(), 1, "felling produced the wrong piece count")
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
		check_eq(trunk.limbs.size(), 4, "the felled trunk lost its branches")
	check_near(loose_volume(), grown_volume, 0.0001,
		"felling did not conserve the tree's wood volume")
	# Limbed close in to the trunk, each limb comes off whole, as a piece.
	var player := _make_player()
	world.add_child(player)
	await step(1)
	if trunk != null:
		for n in 4:
			for s in 50:
				if trunk.limbs.size() == 4 - n:
					var l: Dictionary = trunk.limbs[0]
					player._limb(trunk, 0, trunk.global_transform * ((l.origin as Vector3) + (l.dir as Vector3) * 0.2))
		check_eq(trunk.limbs.size(), 0, "limbing did not clear the branches")
		check_eq(manager.active_count(), 5, "each limb did not come off as its own piece")
		check_near(loose_volume(), grown_volume, 0.0001, "limbing did not conserve wood")
		check(trunk.mass < 10000.0 and trunk.mass > 200.0, "trunk mass odd after limbing")

	# And it should topple rather than stand there.
	await step(90)
	if trunk != null and is_instance_valid(trunk):
		var upright: float = absf(trunk.global_transform.basis.y.dot(Vector3.UP))
		check(upright < 0.8, "the felled trunk never fell over (upright %.2f)" % upright)
	done()

## Spec: the player cuts through the individual cylinders the tree is made of.
## A branch comes off on its own; the trunk is severed at the height of the cut
## and what is below it keeps standing.
## Spec: a forest is hundreds of trees, and a tree of a dozen and a half
## separate meshes is a dozen and a half draws. Untouched, it is drawn as one;
## the first swing brings back the parts that cutting works on.
func test_tree_merged() -> void:
	_setup()
	var tree := _make_tree(8.0, 0.34, 0.6, 4)
	world.add_child(tree)
	await step(2)
	var shown := 0
	for c in tree.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).visible:
			shown += 1
	check(tree.is_merged(), "an untouched tree is not merged")
	check_eq(shown, 1, "an untouched tree draws more than one mesh")
	var merged: MeshInstance3D = tree.get_node("Merged")
	check(merged.mesh.get_faces().size() > 100, "the merged mesh is empty")
	# The whole tree is in it: as tall as the tree and as wide as its crown.
	var box := merged.mesh.get_aabb()
	check(box.size.y >= 8.0, "the merged mesh is shorter than the tree (%.1f m)" % box.size.y)
	var branch: Dictionary = tree.branches[0]
	var aim: Vector3 = tree.global_position + Vector3(0, float(branch.height), 0) \
		+ (branch.dir as Vector3) * (tree._joint_reach(branch) - 0.07)
	tree.cut(10.0, aim, tree.global_position + Vector3(0, 0, 4))
	await step(2)
	shown = 0
	for c in tree.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).visible:
			shown += 1
	check(not tree.is_merged(), "a cut tree is still drawn merged")
	check(shown >= 6, "a cut tree did not get its parts back (%d showing)" % shown)
	done()

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
	# Close in to the trunk: the whole branch.
	var aim: Vector3 = tree.global_position + Vector3(0, float(branch.height), 0) \
		+ (branch.dir as Vector3) * (tree._joint_reach(branch) - 0.07)
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
func test_field_avoids_vehicles() -> void:
	_setup(false)
	var trucks: Array[Hauler] = []
	for i in 6:
		var t := Hauler.new()
		t.setup(manager, 0, &"pickup")
		world.add_child(t)
		var a := TAU * float(i) / 6.0
		t.global_position = Vector3(cos(a) * 12.0, t.spawn_height(), sin(a) * 12.0)
		trucks.append(t)
	await step(10)
	var field := ResourceField.new()
	field.quota = 40
	field.min_spacing = 1.0
	field.setup([{"h": 5.0}],
		func(_kind: Dictionary, form_seed: int) -> Node3D:
			var tree := _make_tree(5.0, 0.3, 0.6, 2)
			tree.seed_form(form_seed)
			return tree,
		ResourceField.annulus(6.0, 18.0), 99)
	world.add_child(field)
	field.prefill()
	check(field.count() > 10, "the field barely filled (%d)" % field.count())
	for node in field.alive:
		for t in trucks:
			var d := Vector2(node.global_position.x - t.global_position.x, node.global_position.z - t.global_position.z).length()
			check(d >= ResourceField.VEHICLE_CLEARANCE, "a tree grew %.1f m from a parked truck" % d)
	done()

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

## Any part of a tree, standing or felled, is cut where the axe lands: a
## branch part way out leaves a stub, a log is bucked at the aim point and its
## branches go with whichever piece they grow from. Wood is never made or lost.
func test_cut_anywhere() -> void:
	_setup()
	var tree := _make_tree(8.0, 0.34, 0.6, 4)
	world.add_child(tree)
	await step(2)
	var grown := tree.wood_volume()
	var b: Dictionary = tree.branches[1]
	var length := float(b.length)
	var along := length * 0.6
	var aim: Vector3 = tree.global_position + Vector3(0, float(b.height), 0) + (b.dir as Vector3) * along
	check_eq(tree.limb_at(aim), 1, "aiming out along a branch did not pick it")
	for i in 400:
		if float(b.length) < length - 0.01:
			break
		tree.cut(34.0, aim, tree.global_position + Vector3(0, 0, 4))
	await step(2)
	check_eq(tree.branches.size(), 4, "cutting a branch part way out took the whole branch")
	check_near(float(b.length), along, 0.05, "the stub is not as long as where it was cut")
	check_eq(manager.active_count(), 1, "the branch end did not come off as a piece")
	check_near(loose_volume() + tree.wood_volume(), grown, 0.0001, "cutting a branch back lost wood")

	# Felled: buck the trunk a quarter of the way up, branches still on.
	tree.fell(tree.global_position + Vector3(0, 0, 4))
	await step(2)
	var trunk: LooseItem = null
	for item in manager.free_items():
		if trunk == null or item.volume() > trunk.volume():
			trunk = item
	var limbs_on := trunk.limbs.size()
	check_eq(limbs_on, 4, "the felled trunk lost branches")
	var total := loose_volume()
	var player := _make_player()
	world.add_child(player)
	await step(1)
	# A limb cut part way out leaves a stub on the trunk.
	var l: Dictionary = trunk.limbs[0]
	var l_len := float(l.length)
	var mid := trunk.global_transform * ((l.origin as Vector3) + (l.dir as Vector3) * l_len * 0.7)
	for i in 200:
		if float(l.length) < l_len - 0.01:
			break
		player._swing_cd = 0.0
		player._limb(trunk, 0, mid)
	check_eq(trunk.limbs.size(), limbs_on, "a limb cut part way out came off whole")
	check_near(float(l.length), l_len * 0.7, 0.05, "the limb stub is the wrong length")
	check_near(loose_volume(), total, 0.0001, "cutting a limb back lost wood")
	var trunk_len := trunk.length()
	var at := trunk.global_transform * Vector3(0, -trunk_len * 0.25, 0)
	var before := manager.active_count()
	for i in 400:
		if manager.active_count() > before:
			break
		player._swing_cd = 0.0
		player._buck(trunk, at)
	await step(2)
	check_eq(manager.active_count(), before + 1, "bucking with branches on did not cut the trunk")
	var pieces: Array[LooseItem] = []
	for item in manager.free_items():
		if absf(item.length() - trunk_len * 0.25) < 0.05 or absf(item.length() - trunk_len * 0.75) < 0.05:
			if item.dims.get("r0", 0.0) > 0.15:
				pieces.append(item)
	check_eq(pieces.size(), 2, "the trunk was not cut at the quarter mark")
	var limbs_after := 0
	for p in pieces:
		limbs_after += p.limbs.size()
	check_eq(limbs_after, limbs_on, "branches were lost bucking the trunk")
	check_near(loose_volume(), total, 0.0001, "bucking with branches on lost wood")
	done()

## A rough stone too big for the gem cutter's mouth is hammered in two, and
## the halves again, until the pieces fit - and the stone is conserved.
func test_crack_loose() -> void:
	_setup()
	var player := _make_player()
	world.add_child(player)
	await step(2)
	player.select_slot(1)   # the club hammer
	var cutter := _inline(&"gem_cutter", Vector3(8, 0, 0))
	await step(2)
	var stone := spawn(&"gem_quartz", Vector3(0, 0.6, -2), Solid.cube(0.5))
	var total := stone.volume()
	await step(10)
	var guard := 0
	while guard < 4000:
		guard += 1
		var big: LooseItem = null
		for item in manager.free_items():
			if not Solid.fits_through(item.dims, cutter.hole * 0.9) and item.is_rough_stone():
				big = item
		if big == null:
			break
		player._swing_cd = 0.0
		player._crack(big)
		if guard % 20 == 0:
			await step(1)
	await step(10)
	check(manager.active_count() >= 2, "the stone was never cracked")
	check_near(loose_volume(), total, 0.0001, "cracking the stone lost some of it")
	for item in manager.free_items():
		check(Solid.fits_through(item.dims, cutter.hole * 0.9), "a piece is still too big for the cutter")
	# Tiny bits are left alone.
	var bit := spawn(&"gem_quartz", Vector3(3, 0.6, -2), Solid.cube(0.004))
	await step(2)
	var count := manager.active_count()
	for i in 200:
		player._swing_cd = 0.0
		player._crack(bit)
	check_eq(manager.active_count(), count, "a tiny bit was cracked")
	done()

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
	player._buck(trunk, trunk.global_position)
	check_eq(manager.active_count(), 1, "a single swing split a full trunk")
	check(trunk.cut_progress > 0.0, "the swing did no work")

	# Keep swinging until it gives.
	var swings := 1
	while manager.active_count() == 1 and swings < 60:
		player._swing_cd = 0.0
		player._buck(trunk, trunk.global_position)
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
	var stub := spawn(&"wood_pine", Vector3(6, 1.0, 0), Solid.cylinder(0.2, 0.2, 0.3))
	var before := manager.active_count()
	for i in 20:
		player._swing_cd = 0.0
		player._buck(stub, stub.global_position)
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

func _inline(id: StringName, pos: Vector3 = Vector3.ZERO, tier: int = 1) -> InlineMachine:
	var m := InlineMachine.new()
	m.setup_machine(manager, PlayerState.def_at_tier(id, tier), 0)
	m.position = pos
	world.add_child(m)
	return m

## A long belt carrying what comes out of a machine away from its exit, the
## way a line would: output held at the exit waits for it to be clear.
func _runout(m: InlineMachine, run: float = 14.0) -> Conveyor:
	var belt := Conveyor.new()
	belt.length = run
	belt.width = 1.8
	belt.speed = 3.0
	belt.transform = m.global_transform * Transform3D(Basis(), Vector3(0, 0, -m.length * 0.5 - run * 0.5))
	world.add_child(belt)
	return belt

## Puts a piece on a machine's in-feed lip, lying along the belt.
func _feed(m: InlineMachine, id: StringName, dims: Dictionary = {}) -> LooseItem:
	var at := m.global_transform * Vector3(0, 0.6, m.length * 0.5 - 0.35)
	return manager.spawn(id, Transform3D(m.global_transform.basis * LooseItem.lying_basis(0.0), at),
		0, Vector3.ZERO, dims, true)

## Drops a piece into a top-loaded machine's hopper.
func _drop_in(m: InlineMachine, id: StringName, dims: Dictionary) -> LooseItem:
	var at := m.global_transform * Vector3(0, InlineMachine.DECK_THICKNESS + m.canopy_height() + InlineMachine.HOPPER_DEPTH + 0.6, 0)
	return manager.spawn(id, Transform3D(Basis(), at), 0, Vector3.ZERO, dims, true)

## Waits for the next piece out of the machine's far end and returns it (a
## piece going in is taken off the belt; what comes out is a new body).
func _through(m: InlineMachine, _item: LooseItem, frames: int = 600) -> LooseItem:
	var before := m.total_out
	for i in frames:
		await step(1)
		if m.total_out > before:
			return m.last_out
	return null

## Spec from play-testing: machines are tunnels on a belt. A log rides in and
## comes out as ONE big plank, as long as the log - not a heap of little ones.
func test_planker() -> void:
	_setup()
	var m := _inline(&"sawmill")
	await step(3)
	check(m.canopy_length() > 2.0, "the planker has no tunnel")
	# Unsanded, a log goes through untouched: there are no rough planks.
	var rough := _feed(m, &"wood_pine", Solid.cylinder(0.26, 0.22, 3.0))
	rough = await _through(m, rough)
	check(rough != null and rough.item_id == &"wood_pine", "the planker planked an unsanded log")
	check_eq(m.total_processed, 0, "the planker counted an unsanded log as work")
	if rough != null:
		manager.despawn(rough)
	var log_piece := _feed(m, &"wood_pine", Solid.with_finish(Solid.cylinder(0.26, 0.22, 3.0), &"sanded"))
	var log_volume := log_piece.volume()
	log_piece = await _through(m, log_piece)
	check(log_piece != null, "the log never came out of the far end")
	if log_piece == null:
		done()
		return
	check_eq(m.total_processed, 1, "the planker processed %d pieces" % m.total_processed)
	check_eq(log_piece.item_id, &"lumber_pine", "the log came out as %s" % log_piece.item_id)
	check_eq(manager.active_count(), 1, "one log made %d pieces" % manager.active_count())
	var size: Vector3 = log_piece.dims.get("size", Vector3.ZERO)
	check_near(size.y, 3.0, 0.001, "the plank is not as long as the log")
	check(size.x > 0.35 and size.z > 0.15, "the plank is thin: %s" % str(size))
	check(size.x > size.z * 1.5, "that is a beam, not a plank: %s" % str(size))
	check_near(log_piece.volume(), log_volume, 0.001, "milling lost or made wood")
	check(Economy.price_of(&"lumber_pine", log_piece.dims) > Economy.price_of(&"wood_pine", Solid.with_finish(Solid.cylinder(0.26, 0.22, 3.0), &"sanded")),
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
	log_piece = await _through(m, log_piece)
	check(log_piece != null, "the log never came through the sander")
	check(Solid.has_finish(log_piece.dims, &"sanded"), "the log came out unsanded")
	check(Economy.price_of(log_piece.item_id, log_piece.dims) > raw_price, "sanding added no value")
	check(log_piece.display_name().begins_with("Sanded"), "a sanded log is not called sanded")
	var ore := _feed(m, &"ore_iron")
	ore = await _through(m, ore)
	check(ore != null, "the sander stopped ore riding through")
	check_eq(ore.item_id, &"ore_iron", "the sander changed ore")
	check(not Solid.has_finish(ore.dims, &"sanded"), "the sander sanded ore")
	check_eq(m.total_processed, 1, "the sander counted work it did not do")

	# A sanded log planked is a sanded plank, and the finish is saved.
	var planker := _inline(&"sawmill", Vector3(6, 0, 0))
	await step(3)
	var again := _feed(planker, log_piece.item_id, log_piece.dims)
	again = await _through(planker, again)
	check(again != null, "the sanded log did not get through the planker")
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
				var plank := Solid.keep_finish(sanded, Solid.box(Vector3(r * 2.6, 2.0, v / (2.0 * r * 2.6))))
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
				# Cut from rough, not from polished: one or the other.
				var jewel := Solid.cylinder(r0, r0 * 0.5, r0 * 0.9)
				fin = fin_def.base_value_of(jewel) / v3
			"stone":
				# Dug, and crushed, it is worth the same; sandstone alone goes
				# on, into glass.
				var lump := Solid.chunk(0.4)
				var v4 := Solid.volume(lump)
				raw = raw_def.base_value_of(lump) / v4
				pre = raw
				fin = fin_def.base_value_of(Solid.box(Vector3(0.6, v4 / 0.03, 0.05))) / v4
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

## Rough stone > gem polisher (polished) > gem cutter (a faceted jewel). The
## sander is for wood: a stone rides through it untouched.
func test_gem_line() -> void:
	_setup()
	var sander := _inline(&"gem_polisher")
	var cutter := _inline(&"gem_cutter", Vector3(6, 0, 0))
	await step(3)
	# An emerald is level 2: it takes second-tier machines.
	sander.level = 2
	cutter.level = 2
	# Small enough for the cutter's 0.8 x 0.6 mouth.
	var stone := _feed(sander, &"gem_emerald", Solid.cube(0.012))
	var volume := stone.volume()
	var raw_price := Economy.price_of(stone.item_id, stone.dims)
	stone = await _through(sander, stone)
	check(stone != null, "the stone never came through the polisher")
	check(Solid.has_finish(stone.dims, &"polished"), "the polisher did not polish the stone")
	check(not Solid.has_finish(stone.dims, &"sanded"), "the stone was sanded like wood")
	check(stone.display_name().begins_with("Polished"), "a polished stone is called %s" % stone.display_name())
	var polished_price := Economy.price_of(stone.item_id, stone.dims)
	check(polished_price >= raw_price, "polishing an emerald lost value")
	# Polished is finished: the cutter sends it through as it came.
	var again := _feed(cutter, stone.item_id, stone.dims)
	again = await _through(cutter, again)
	check(again != null, "the polished stone never came through the gem cutter")
	check_eq(again.item_id, &"gem_emerald", "the cutter cut a polished stone")
	# Rough goes under the cutting head instead.
	var rough_em := _feed(cutter, &"gem_emerald", Solid.cube(0.012))
	var cut := await _through(cutter, rough_em)
	check(cut != null, "the rough stone never came through the gem cutter")
	check_eq(cut.item_id, &"jewel_emerald", "the cutter made %s" % cut.item_id)
	check_eq(cut.dims.get("shape"), Solid.CYLINDER, "a jewel is not faceted round")
	check_near(cut.volume(), volume * cutter.machine_def.yield_share, 0.0001, "the jewel is the wrong size")
	check(not Solid.has_finish(cut.dims, &"polished"), "a cut jewel came out polished")
	# And a jewel is not polished afterwards.
	var jewel := _feed(sander, cut.item_id, Solid.cylinder(0.1, 0.05, 0.09))
	jewel = await _through(sander, jewel)
	check(jewel != null and not Solid.has_finish(jewel.dims, &"polished"), "a cut jewel was polished")
	# An emerald is one of the stones worth more cut than polished.
	check(Economy.price_of(cut.item_id, cut.dims) > polished_price, "a cut emerald is worth less than a polished one")
	# About half the stones are worth more one way, half the other.
	var cut_better := 0
	var gems := 0
	for mat in GameData.materials.values():
		if String(mat.get("path", "")) == "gem":
			gems += 1
			if float(mat.final) > float(mat.pre):
				cut_better += 1
	check(cut_better * 2 >= gems - 1 and cut_better * 2 <= gems + 1,
		"%d of %d stones are worth more cut" % [cut_better, gems])
	# The gem cutter leaves ore alone.
	var ore := _feed(cutter, &"ore_iron", Solid.cube(0.012))
	ore = await _through(cutter, ore)
	check(ore != null, "ore did not ride through the cutter")
	check_eq(ore.item_id, &"ore_iron", "the cutter changed ore")
	# The crusher breaks rough stone down too - a quartz boulder far too big
	# for the cutter comes out as lumps that fit it.
	_setup()
	var crusher := _inline(&"crusher")
	_runout(crusher)
	await step(3)
	var quartz := _drop_in(crusher, &"gem_quartz", Solid.cube(0.4))
	var q_volume := quartz.volume()
	for i in 1800:
		if crusher.total_processed >= 1 and crusher.queue.is_empty():
			break
		await step(1)
	check(crusher.total_out >= 2, "the crusher did not break up quartz")
	var got := 0.0
	var mouth := 0.6
	for lump in manager.free_items():
		check_eq(lump.item_id, &"gem_quartz", "crushing quartz made %s" % lump.item_id)
		got += lump.volume()
		var b := Solid.bounds(lump.dims)
		check(maxf(b.x, maxf(b.y, b.z)) < mouth, "a quartz lump is too big for the gem cutter")
	check_near(got, q_volume, 0.001, "crushing quartz lost stone")
	# The sander is for wood: a stone goes through it as it went in.
	var wood_sander := _inline(&"sander", Vector3(-6, 0, 0))
	await step(3)
	var rough := _feed(wood_sander, &"gem_quartz", Solid.cube(0.1))
	rough = await _through(wood_sander, rough)
	check(rough != null and not Solid.has_finish(rough.dims, &"polished"), "the sander polished a stone")
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

## A small island map laid out the way the real one is, for the tests below.
func _region_land() -> Terrain:
	var land := Terrain.new()
	land.half_extent = 640.0
	land.noise_seed = 20260921
	land.islands = [{"centre": Vector2(0, 0), "radius": 560.0}]
	land.regions = [
		{"name": "Woods", "centre": Vector2(-220, 120), "biome": Terrain.Biome.WOODLAND},
		{"name": "Peaks", "centre": Vector2(260, -160), "biome": Terrain.Biome.MOUNTAIN},
		{"name": "Sand", "centre": Vector2(-120, -330), "biome": Terrain.Biome.DESERT},
	]
	return land

## Spec: larger, consolidated biomes - one big desert, one big range - and
## real topography everywhere, with the mountains amplified.
func test_regions() -> void:
	_setup(false)
	var land := _region_land()
	world.add_child(land)
	await step(2)
	var agree := 0
	var total := 0
	var woods := [INF, -INF]
	var peak := -INF
	var x := -420.0
	while x <= 420.0:
		var z := -420.0
		while z <= 420.0:
			var h := land.height_at(x, z)
			if h > Terrain.WATER_LEVEL + 1.0 and Vector2(x, z).length() < 380.0:
				total += 1
				var nearest := 0
				var best := INF
				for i in land.regions.size():
					var d := Vector2(x, z).distance_to(land.regions[i].centre)
					if d < best:
						best = d
						nearest = i
				var b := land.biome_at(x, z)
				var want: Terrain.Biome = land.regions[nearest].biome
				if b == want or (want == Terrain.Biome.MOUNTAIN and b == Terrain.Biome.SNOW):
					agree += 1
				if want == Terrain.Biome.WOODLAND and best < 180.0:
					woods = [minf(woods[0], h), maxf(woods[1], h)]
				if want == Terrain.Biome.MOUNTAIN:
					peak = maxf(peak, h)
			z += 20.0
		x += 20.0
	check(total > 200, "the test island is mostly sea")
	check(float(agree) / float(total) > 0.75, "biomes are scattered, not regional (%d of %d agree)" % [agree, total])
	check(float(woods[1]) - float(woods[0]) > 12.0, "the woods are flat (%.1f m of relief)" % (float(woods[1]) - float(woods[0])))
	# The ground itself rises; the peaks are the stacks on it.
	check(peak > 40.0, "the mountain ground tops out at %.0f m" % peak)
	# The land is welded plates of very different sizes, not a grid: a few
	# big panels over calm ground, many small ones where it is rough - and
	# it follows the ground closely, with no gaps between the plates.
	check(land.facets != null, "the region map was not built of plates")
	var smallest := INF
	var biggest := 0.0
	var tris := 0
	for t in land.facets.tiles:
		for k in range(0, t.tris.size(), 3):
			var area: float = ((t.tris[k + 2] - t.tris[k]).cross(t.tris[k + 1] - t.tris[k])).length() * 0.5
			smallest = minf(smallest, area)
			biggest = maxf(biggest, area)
			tris += 1
	check(tris < land._cells * land._cells, "%d triangles is no fewer than the grid's" % tris)
	check(biggest > 2000.0, "the biggest plate triangle is only %.0f m2" % biggest)
	check(smallest < 40.0, "the smallest plate triangle is %.0f m2" % smallest)
	var space := world.get_world_3d().direct_space_state
	var probed := 0
	var gaps := 0
	for iz in range(3, land._cells - 3, 11):
		for ix in range(3, land._cells - 3, 11):
			var px: float = -land.half_extent + (float(ix) + 0.37) * Terrain.CELL
			var pz: float = -land.half_extent + (float(iz) + 0.61) * Terrain.CELL
			var ray := PhysicsRayQueryParameters3D.create(Vector3(px, 400, pz), Vector3(px, -50, pz), Layers.WORLD)
			var hit := space.intersect_ray(ray)
			if hit.is_empty():
				gaps += 1
				continue
			probed += 1
			check(absf(float(hit.position.y) - land.height_at(px, pz)) < 0.05,
				"height_at is %.2f where the plates are at %.2f" % [land.height_at(px, pz), float(hit.position.y)])
			check(absf(land.height_at(px, pz) - land.grid_height(px, pz)) < 7.0,
				"the plates stray %.1f m from the ground they stand for" % absf(land.height_at(px, pz) - land.grid_height(px, pz)))
	check_eq(gaps, 0, "rays fell through the plates")
	check(probed > 100, "only %d points probed" % probed)
	# Rock outcrops, solid, off the roads.
	var marks := Landmarks.new()
	marks.setup(land, 5)
	world.add_child(marks)
	await step(2)
	check(marks.rocks.size() > 30, "only %d outcrops" % marks.rocks.size())
	for r in marks.rocks:
		var p: Vector3 = r.pos
		check(not land.is_road(p.x, p.z), "an outcrop stands on a road")
	var r0: Vector3 = marks.rocks[0].pos + Vector3(0, (marks.rocks[0].size as Vector3).y * 0.4, 0)
	var q2 := PhysicsRayQueryParameters3D.create(r0 + Vector3(0, 60, 0), r0)
	check(not space.intersect_ray(q2).is_empty(), "an outcrop is not solid")
	done()

## Spec: roads that wind round hills and switch back up mountains, laid on the
## ground as a road you can see.
func test_road_routing() -> void:
	_setup(false)
	var land := _region_land()
	var a := Vector3(-300, 0, 150)
	var b := Vector3(300, 0, -200)
	land.roads = [{"route": [a, b]}]
	world.add_child(land)
	await step(2)
	var path: Array = land.roads[0].get("path", [])
	check(path.size() > 20, "the road was not routed")
	var span := land._path_length(path)
	# No bend tighter than a truck takes: turning radius over each 8 m.
	var tightest := INF
	var s := 8.0
	while s + 8.0 <= span - 8.0:
		var p0 := land._point_along(path, s - 8.0)
		var p1 := land._point_along(path, s)
		var p2 := land._point_along(path, s + 8.0)
		var turn := absf(Vector2(p1.x - p0.x, p1.z - p0.z).angle_to(Vector2(p2.x - p1.x, p2.z - p1.z)))
		if turn > 0.001:
			tightest = minf(tightest, 8.0 / turn)
		s += 4.0
	check(tightest >= Terrain.ROAD_MIN_RADIUS * 0.8, "a bend of %.0f m radius" % tightest)
	# Graded no steeper than the limit, over any 30 m of it.
	var worst := 0.0
	var along := 0.0
	while along + 30.0 <= span:
		var p := land._point_along(path, along)
		var q := land._point_along(path, along + 30.0)
		worst = maxf(worst, absf(land.height_at(q.x, q.z) - land.height_at(p.x, p.z)) / 30.0)
		along += 15.0
	check(worst <= Terrain.MAX_GRADE + 0.03, "the road climbs at %.2f" % worst)
	# The road is laid on the land: a textured surface a little above it.
	var surface := RoadSurface.new()
	surface.setup(land)
	world.add_child(surface)
	await step(1)
	var meshes := 0
	for c in surface.get_children():
		if c is MeshInstance3D and c.name.begins_with("Road"):
			meshes += 1
	check(meshes >= 1, "no road surface was built")
	var mid := land._point_along(path, span * 0.5)
	check(land.is_road(mid.x, mid.z), "the middle of the road is not marked as road")
	# The road lies on the land and nothing pokes up through it: a ray down
	# anywhere on the carriageway meets the road first, not a plate.
	await step(2)
	var space := world.get_world_3d().direct_space_state
	var poked := 0
	var tried := 0
	var along2 := 20.0
	while along2 < span - 20.0:
		var p := land._point_along(path, along2)
		var ahead := land._point_along(path, along2 + 1.0)
		var tangent := Vector3(ahead.x - p.x, 0.0, ahead.z - p.z).normalized()
		var side := Vector3(-tangent.z, 0.0, tangent.x)
		for off in [-3.5, -1.5, 0.0, 1.5, 3.5]:
			var q: Vector3 = p + side * float(off)
			if land.water_depth(q.x, q.z) > 0.0:
				continue
			var ray := PhysicsRayQueryParameters3D.create(Vector3(q.x, 300, q.z), Vector3(q.x, -50, q.z), Layers.WORLD)
			var hit := space.intersect_ray(ray)
			if hit.is_empty():
				continue
			tried += 1
			if not (hit.collider as Node).get_parent() is RoadSurface:
				poked += 1
		along2 += 2.7
	check(tried > 50, "only %d points tried on the road" % tried)
	check(poked * 50 <= tried, "the ground pokes through the road at %d of %d points" % [poked, tried])
	done()

## Planning the caves is the slow part of building them, so the plan is kept
## in a file and read back on the next load: what comes back must be exactly
## the plan as it was made, entrances and all, and only for the same key. And
## the quicker bend relaxing must move the same points as looking at every
## point every time round did.
func test_cave_plan_kept() -> void:
	_setup(false)
	var land := _region_land()
	land.cave_count = 3
	land.cave_zones = [{"centre": Vector2(0, 0), "radius": 520.0, "count": 3}]
	world.add_child(land)
	await step(2)
	var zones := [{"name": "Test", "centre": Vector2(0, 0), "radius": 520.0, "rooms": 10,
		"kinds": [[CaveNetwork.Kind.RIVER, Vector2(-220, 120)], [CaveNetwork.Kind.CRYSTAL, Vector2(260, -160)]]}]
	var made := CaveNetwork.new()
	made.plan(land, zones, [], 11)
	check(made.rooms.size() > 3 and made.tunnels.size() > 2, "too small a plan to test: %d caverns, %d tunnels" % [
		made.rooms.size(), made.tunnels.size()])
	var path := "user://test_cave_plan.bin"
	made.save_plan(path, "key-a")
	var read := CaveNetwork.new()
	check(not read.load_plan(land, path, "key-b", 11), "a plan was read back for another key")
	check(read.rooms.is_empty(), "a refused plan left caverns behind")
	check(read.load_plan(land, path, "key-a", 11), "the plan was not read back")
	check_eq(read.rooms.size(), made.rooms.size(), "caverns read back")
	check_eq(read.tunnels.size(), made.tunnels.size(), "tunnels read back")
	check_eq(var_to_str(read.tunnels), var_to_str(made.tunnels), "tunnels as made")
	var entrances := 0
	for i in mini(read.rooms.size(), made.rooms.size()):
		var a: Dictionary = made.rooms[i]
		var b: Dictionary = read.rooms[i]
		for k in ["centre", "rx", "ry", "rz", "floor", "yaw", "kind", "zone", "links", "index"]:
			check_eq(b[k], a[k], "cavern %d's %s" % [i, k])
		check(is_same(b.entrance, a.entrance), "cavern %d's entrance is not the terrain's own cave plan" % i)
		entrances += int(b.entrance != null)
	check(entrances > 0, "no cavern read back with its entrance")
	# The same queries answer the same way.
	for t: Dictionary in made.tunnels:
		var mid: Vector3 = (t.points as PackedVector3Array)[(t.points as PackedVector3Array).size() / 2]
		check(read.contains(mid), "a point in a tunnel is not in the read-back plan's caves")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	made.free()
	read.free()
	# Bend relaxing, against the plain way of doing it.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for trial in 40:
		var pts := PackedVector3Array()
		var p := Vector3.ZERO
		var heading := 0.0
		for i in rng.randi_range(8, 70):
			heading += rng.randf_range(-1.4, 1.4)
			p += Vector3(cos(heading), rng.randf_range(-0.4, 0.4), sin(heading)) * 2.5
			pts.append(p)
		var r := rng.randf_range(3.0, 8.0)
		check_eq(CaveNetwork._relax_bends(pts, r), _relax_plain(pts, r), "relaxed bends, trial %d" % trial)
	done()

## Bend relaxing as it was first written: every point, every time round.
func _relax_plain(pts: PackedVector3Array, r: float) -> PackedVector3Array:
	var tightest := CaveNetwork.min_bend(r) * 1.05
	var out := pts.duplicate()
	var keep := 2
	for it in 120:
		var moved := false
		for i in range(keep, out.size() - keep):
			if CaveNetwork.bend_radius(out, i) >= tightest:
				continue
			for j in [i - 1, i, i + 1]:
				if j < keep or j >= out.size() - keep:
					continue
				var mid := (out[j - 1] + out[j + 1]) * 0.5
				out[j] = out[j].lerp(mid, 0.5)
			moved = true
		if not moved:
			break
	return out

## The big jobs of loading are split over the worker threads: every piece
## done once, with or without frames going by meanwhile, and some cores left
## for the rest of the computer.
func test_load_workers() -> void:
	const Workers := preload("res://scripts/core/Workers.gd")
	var n := OS.get_processor_count()
	check(Workers.tasks() >= 1, "no threads at all")
	if n > 2:
		check(Workers.tasks() < n, "every core used: %d of %d" % [Workers.tasks(), n])
	for tree in [null, get_tree()]:
		var hits: Array = []
		hits.resize(500)
		hits.fill(0)
		await Workers.group(func(i: int): hits[i] = int(hits[i]) + 1, 500, "test", tree)
		var wrong := 0
		for h in hits:
			wrong += int(h != 1)
		check_eq(wrong, 0, "pieces not done exactly once (%s)" % ("with frames" if tree != null else "waited"))
		var out := [0]
		await Workers.one(func(): out[0] = 42, "test", tree)
		check_eq(out[0], 42, "a single job's result (%s)" % ("with frames" if tree != null else "waited"))
	done()

## Spec: caves much more extensive and interconnected, below sea level, big and
## small caverns with many tunnels, cave biomes with their own resources.
func test_cave_network() -> void:
	_setup(false)
	var land := _region_land()
	land.cave_count = 3
	land.cave_zones = [{"centre": Vector2(0, 0), "radius": 520.0, "count": 3}]
	world.add_child(land)
	await step(2)
	check(land.caves.size() >= 2, "only %d cave mouths" % land.caves.size())
	var net := CaveNetwork.new()
	net.plan(land, [{"name": "Test", "centre": Vector2(0, 0), "radius": 520.0, "rooms": 14,
		"kinds": [[CaveNetwork.Kind.RIVER, Vector2(-220, 120)], [CaveNetwork.Kind.CRYSTAL, Vector2(260, -160)],
			[CaveNetwork.Kind.DESERT, Vector2(-120, -330)]]}], [], 11)
	for plan_entry in land.caves:
		var cave := Cave.new()
		cave.with_chamber = false
		cave.setup(plan_entry.entrance, plan_entry.dir, plan_entry.name, 3)
		world.add_child(cave)
		net.entrances.append(cave)
	world.add_child(net)
	await step(3)
	var ids: Array = []
	for i in net.rooms.size():
		ids.append(i)
	var comp := net._components(ids)
	var pieces := {}
	for i in ids:
		pieces[comp[i]] = true
	check(net.rooms.size() >= 12, "only %d caverns" % net.rooms.size())
	check(pieces.size() == 1, "the network is in %d pieces" % pieces.size())
	check(net.tunnels.size() >= net.rooms.size() - 1, "too few tunnels to join %d caverns" % net.rooms.size())
	var below := 0
	var big := 0
	var small := 0
	for room in net.rooms:
		below += int(float(room.floor) < Terrain.WATER_LEVEL)
		big += int(maxf(room.rx, room.rz) >= 50.0)
		small += int(maxf(room.rx, room.rz) < 35.0)
	check(below > net.rooms.size() / 2, "most caverns are above sea level")
	check(big >= 1 and small >= 1, "the caverns are all one size")
	# Not balls: each cavern bulges out into bays, and its dressing grows out
	# of the walls, clear of the floor.
	var lobed := 0
	var on_floor := 0
	var rng := RandomNumberGenerator.new()
	for room in net.rooms:
		var lo := INF
		var hi := 0.0
		for i in 48:
			var a := TAU * float(i) / 48.0
			var b := net._bump(room, Vector3(cos(a), 0.0, sin(a)))
			lo = minf(lo, b)
			hi = maxf(hi, b)
		lobed += int(hi / lo > 1.3)
		for i in 20:
			var spot: Variant = net.wall_point(room, rng)
			if spot != null and (spot[0] as Vector3).y < float(room.floor) + 0.9:
				on_floor += 1
	check(lobed >= net.rooms.size() / 2, "only %d of %d caverns have bays" % [lobed, net.rooms.size()])
	check(on_floor == 0, "%d formations on a cavern floor" % on_floor)
	# No tunnel bends tighter than it is wide: its walls never fold through
	# themselves.
	var folds := 0
	for t in net.tunnels:
		var tp: PackedVector3Array = t.points
		for i in range(2, tp.size() - 2):
			if CaveNetwork.bend_radius(tp, i) < CaveNetwork.min_bend(float(t.radius)) * 0.99:
				folds += 1
	check_eq(folds, 0, "places a tunnel bends tighter than it is wide")
	# Every tunnel mouth open into its cavern, and every tunnel floored.
	var space := world.get_world_3d().direct_space_state
	var blocked := 0
	var gaps := 0
	for t in net.tunnels:
		var pts: PackedVector3Array = t.points
		for k in range(1, pts.size() - 1, 3):
			var q := PhysicsRayQueryParameters3D.create(pts[k], pts[k] - Vector3(0, float(t.radius) * 2.0, 0))
			q.hit_back_faces = false
			if space.intersect_ray(q).is_empty():
				gaps += 1
		for end in [[int(t.a), 0, 3], [int(t.b), pts.size() - 1, pts.size() - 4]]:
			var room: Dictionary = net.rooms[end[0]]
			var from := pts[end[2]] + Vector3(0, 0.3, 0)
			var mouth := pts[end[1]] + Vector3(0, 0.3, 0)
			var centre: Vector3 = room.centre
			centre.y = mouth.y
			for leg in [[from, mouth], [mouth, centre]]:
				var q2 := PhysicsRayQueryParameters3D.create(leg[0], leg[1])
				q2.hit_back_faces = false
				if not space.intersect_ray(q2).is_empty():
					blocked += 1
	check(gaps == 0, "%d places a tunnel has no floor" % gaps)
	check(blocked == 0, "%d tunnel mouths are walled off" % blocked)
	# Sealed where tunnel meets cavern: from just either side of every mouth,
	# every way you look you see rock - no crack through to nothing.
	var leaks := 0
	var looks := 0
	for ti in net.tunnels.size():
		var t: Dictionary = net.tunnels[ti]
		var width := float(t.radius) * CaveNetwork.WIDEN
		for ri in [int(t.a), int(t.b)]:
			var end := net._tube_end(ti, ri)
			var o: Vector3 = end.origin
			var out_dir: Vector3 = end.out
			var centre: Vector3 = net.rooms[ri].centre
			centre.y = o.y
			for eye in [o + (centre - o).normalized() * 5.0 + Vector3(0, 1.6, 0), o + out_dir * 6.0 + Vector3(0, 1.6, 0)]:
				# Beside a mouth that leaves at a slant, the first can be in the
				# rock; a look from there says nothing.
				if eye.distance_to(o) < 5.5 and not net._inside_wall(net.rooms[ri], eye):
					continue
				for i in 48:
					var yaw := TAU * float(i) / 48.0
					var pitch: float = [-0.3, 0.15, 0.6][i % 3]
					var dir := Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch))
					var q3 := PhysicsRayQueryParameters3D.create(eye, eye + dir * (width * 2.0 + 520.0))
					q3.hit_back_faces = false
					looks += 1
					if space.intersect_ray(q3).is_empty():
						leaks += 1
	check(leaks == 0, "%d of %d looks round the tunnel mouths see through the rock" % [leaks, looks])
	# No two tunnels open out of a cavern on top of one another.
	var overlaps := 0
	for ri in net.rooms.size():
		var ends: Array = []
		for ti in net.rooms[ri].links:
			var e := net._tube_end(ti, ri)
			var tt: Dictionary = net.tunnels[ti]
			var rr := float(tt.get("ra", tt.radius)) if int(tt.a) == ri else float(tt.get("rb", tt.radius))
			for other in ends:
				var o: Vector3 = other[0]
				if Vector2(o.x - e.origin.x, o.z - e.origin.z).length() < (rr + float(other[1])) * CaveNetwork.WIDEN:
					overlaps += 1
			ends.append([e.origin, rr])
	check_eq(overlaps, 0, "tunnel mouths overlapping in one cavern")
	# Floor all the way across the threshold where each way in meets its hall.
	var holes := 0
	for plan_entry in land.caves:
		var e: Vector3 = plan_entry.entrance
		var d: Vector3 = plan_entry.dir
		var side := Vector3(-d.z, 0, d.x)
		var z_end := Cave.SHAFT_LENGTH + Cave.TUNNEL_LENGTH
		var fl := float(plan_entry.ground) - Cave.CHAMBER_DROP
		for along in [z_end - 1.0, z_end, z_end + 1.0, z_end + 2.5]:
			for across in [-2.4, -1.2, 0.0, 1.2, 2.4]:
				var p: Vector3 = e + d * along + side * across
				var q4 := PhysicsRayQueryParameters3D.create(Vector3(p.x, fl + 2.0, p.z), Vector3(p.x, fl - 2.0, p.z))
				q4.hit_back_faces = false
				if space.intersect_ray(q4).is_empty():
					holes += 1
	check_eq(holes, 0, "holes in the floor where a way in meets its hall")
	var widest := 0.0
	for t in net.tunnels:
		widest = maxf(widest, float(t.radius) * CaveNetwork.WIDEN * 2.0)
	check(widest >= 20.0, "the widest tunnel is only %.0f m across" % widest)
	# Underground below sea level is dry, and it is dark.
	var deep: Dictionary = net.rooms[net.rooms.size() - 1]
	var inside: Vector3 = deep.centre
	check(net.contains(inside), "the middle of a cavern is not in the caves")
	check(net.depth_factor(inside) > 0.9, "a cavern is not underground")
	check(not net.contains(Vector3(0, 400, 0)), "the sky is in the caves")
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
	var jewel: Dictionary = show.lines[2]
	var sander: InlineMachine = stone.machines[0]
	var cutter: InlineMachine = jewel.machines[0]
	check(sander.total_processed >= 12, "the polisher polished only %d stones" % sander.total_processed)
	check(cutter.total_processed >= 12, "the gem cutter cut only %d stones" % cutter.total_processed)
	check(int(ore.made) > 20 and int(stone.made) > 8 and int(jewel.made) > 8,
		"the lines finished too little (%d, %d, %d)" % [ore.made, stone.made, jewel.made])
	show.clear_all()
	check_eq(manager.active_count(), 0, "switching the demo off left pieces behind")
	done()

## Rocks > crusher > smelter > refiner.
func test_ore_line() -> void:
	_setup()
	var crusher := _inline(&"crusher")
	_runout(crusher)
	await step(3)
	check(crusher.top_loaded(), "the crusher is not fed from above")
	var chunk := _drop_in(crusher, &"ore_iron", Solid.cube(0.45))
	var chunk_volume := chunk.volume()
	chunk = await _through(crusher, chunk)
	check(chunk != null, "the chunk never came out of the crusher")
	for i in 900:
		if crusher.queue.is_empty():
			break
		await step(1)
	check(crusher.queue.is_empty(), "the crusher never let all its lumps out")
	var lumps := manager.free_items()
	check(lumps.size() >= 5, "the crusher made %d piece(s) from a 0.45 m3 chunk" % lumps.size())
	var total := 0.0
	for lump in lumps:
		total += lump.volume()
		check(lump.volume() <= 0.1001, "a lump is bigger than 0.1 m3 (%.3f)" % lump.volume())
	check_near(total, chunk_volume, 0.0001, "the crusher did not conserve ore")
	# There is no size limit: a chunk bigger than any lump, dropped in
	# skewed, is crushed all the same.
	var huge := _drop_in(crusher, &"ore_iron", Solid.cube(1.6))
	huge.global_basis = Basis(Vector3.UP, 0.7)
	var done_before := crusher.total_processed
	for i in 240:
		if crusher.total_processed > done_before:
			break
		await step(1)
	check(crusher.total_processed > done_before, "a 1.6 m3 chunk sat in the hopper uncrushed")
	check(crusher.hopper_opening() >= 2.0, "the hopper is only %.1f m across" % crusher.hopper_opening())
	for i in 3000:
		if crusher.queue.is_empty():
			break
		await step(1)
	for lump in manager.free_items():
		manager.despawn(lump)
	await step(2)
	done_before = crusher.total_processed
	# Nothing goes in along the belt.
	var along := _feed(crusher, &"ore_iron", Solid.cube(0.05))
	await step(200)
	check_eq(crusher.total_processed, done_before, "the crusher took a piece along the belt")
	manager.despawn(along)
	# A piece already small enough still gets crushed; its own lumps do not.
	var small := _drop_in(crusher, &"ore_iron", Solid.cube(0.03))
	var before := crusher.total_out
	for i in 900:
		if crusher.total_out - before >= 2 and crusher.queue.is_empty():
			break
		await step(1)
	check(crusher.total_out - before >= 2, "a small chunk went through the crusher whole")
	check(crusher.work({"id": &"ore_iron", "dims": Solid.cube(0.1).merged({"crushed": true}), "owned": true,
		"plot": 0, "changed": false, "ready": 0.0}).size() == 1, "the crusher crushed its own lumps again")

	_setup()
	var smelter := _inline(&"furnace")
	var refiner := _inline(&"refiner", Vector3(6, 0, 0))
	await step(3)
	var ore := _feed(smelter, &"ore_iron", Solid.cube(0.035))
	var ore_price := Economy.price_of(&"ore_iron", ore.dims)
	var ore_volume := ore.volume()
	ore = await _through(smelter, ore)
	check(ore != null, "the ore never came out of the smelter")
	check_eq(ore.item_id, &"ingot_iron", "the smelter made %s" % ore.item_id)
	check_near(ore.volume(), ore_volume * smelter.machine_def.yield_share, 0.0001, "the bar is the wrong size")
	var size: Vector3 = ore.dims.size
	check(size.y > size.x and size.x > size.z, "the bar is not bar-shaped: %s" % str(size))
	var bar_price := Economy.price_of(ore.item_id, ore.dims)
	check(bar_price > ore_price, "smelting lost value")
	var bar := _feed(refiner, ore.item_id, ore.dims)
	bar = await _through(refiner, bar)
	check(bar != null, "the bar never came out of the refiner")
	check(Solid.has_finish(bar.dims, &"refined"), "the refiner did not refine the bar")
	check(Economy.price_of(bar.item_id, bar.dims) > bar_price, "refining added no value")
	done()

## The tunnel mouth is a real opening: a trunk too big for it jams against the
## bulkhead, and a higher tier machine's wider mouth takes it.
func test_tunnel_mouth() -> void:
	_setup()
	var m := _inline(&"sawmill")
	# Fed from a belt behind it, so the trunk arrives at the mouth end-on.
	var belt := Conveyor.new()
	belt.length = 6.0
	belt.width = 1.8
	belt.speed = 2.0
	belt.position = Vector3(0, 0, m.length * 0.5 + 3.0)
	world.add_child(belt)
	await step(3)
	var fat := Solid.with_finish(Solid.cylinder(m.hole.y * 0.62, m.hole.y * 0.6, 3.0), &"sanded")
	var trunk := manager.spawn(&"wood_pine", Transform3D(LooseItem.lying_basis(0.0),
		belt.global_position + Vector3(0, 0.8, 1.2)), 0, Vector3.ZERO, fat, true)
	await step(300)
	var z := (m.global_transform.affine_inverse() * trunk.global_position).z
	check(z > m.canopy_length() * 0.5 - 0.3, "an oversized trunk got into the tunnel (z=%.2f)" % z)
	check_eq(trunk.item_id, &"wood_pine", "an oversized trunk was planked anyway")
	check_eq(m.total_processed, 0, "the jammed machine counted work")
	var small_mouth := m.hole
	# Swapped for a T3 sawmill in the same spot: tiers are per machine.
	var at := m.position
	m.queue_free()
	await step(1)
	m = _inline(&"sawmill", at, 3)
	await step(3)
	check_eq(m.level, 3, "the T3 sawmill is not tier 3")
	check(m.hole.x > small_mouth.x and m.hole.y > small_mouth.y, "the top tier did not widen the mouth")
	check(m.speed > GameData.machine(&"sawmill").belt_speed, "the top tier did not speed the belt")
	trunk = await _through(m, trunk, 900)
	check(trunk != null, "the wider mouth still would not take the trunk")
	check_eq(trunk.item_id, &"lumber_pine", "the trunk was not planked once it got in")
	done()

## From play: logs got stuck inside the sander and the planker. Whatever fits
## the mouth - fed crooked, fat, thin, long or in a crowd - comes out the far
## end.
func test_tunnel_flow() -> void:
	for machine in [&"sawmill", &"sander"]:
		_setup()
		var m := _inline(machine)
		_runout(m, 12.0)
		await step(3)
		var pieces: Array[LooseItem] = []
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 8:
			var r := rng.randf_range(0.12, minf(m.hole.x, m.hole.y) * 0.45)
			var span := rng.randf_range(1.2, m.canopy_length() * 1.2)
			var yaw := rng.randf_range(-0.5, 0.5)
			var at := m.global_transform * Vector3(rng.randf_range(-0.2, 0.2), 0.3 + r, m.length * 0.5 - 0.35)
			var dims := Solid.cylinder(r, r * 0.85, span)
			if machine == &"sander" and i % 2 == 1:
				dims = Solid.box(Vector3(r * 1.8, span, r * 0.8))
			var piece := manager.spawn(&"wood_pine" if dims.shape == Solid.CYLINDER else &"lumber_pine",
				Transform3D(m.global_transform.basis * LooseItem.lying_basis(yaw), at), 0, Vector3.ZERO, dims, true)
			pieces.append(piece)
			await step(50)
		# Whatever reaches the end of the run-out is taken away, as a player
		# unloading the line would.
		for f in 60 * 20:
			await step(1)
			for it in manager.free_items():
				if m.to_local(it.global_position).z < -m.length * 0.5 - 10.0:
					manager.despawn(it)
		check_eq(m.total_out, pieces.size(), "%s: only %d of %d pieces came out (%d still queued)" % [
			machine, m.total_out, pieces.size(), m.queue.size()])
	done()

## From play: a trunk still on its branches goes into a machine if it fits
## the mouth, and the branches come out after it as pieces of their own.
func test_machine_takes_branches() -> void:
	_setup()
	var m := _inline(&"sander")
	_runout(m, 12.0)
	await step(3)
	var trunk := _feed(m, &"wood_pine", Solid.cylinder(0.18, 0.16, 2.4))
	# Two short branches laid along the trunk, well inside the mouth.
	trunk.add_limb(Vector3(0.1, -0.3, 0), Vector3(0.05, 1, 0), 0.05, 0.6)
	trunk.add_limb(Vector3(-0.1, 0.4, 0), Vector3(-0.05, 1, 0), 0.05, 0.5)
	var total := trunk.volume() + trunk.limb_volume()
	for i in 900:
		if m.total_out >= 3:
			break
		await step(1)
	check_eq(m.total_out, 3, "a trunk and its two branches did not all come out")
	check_near(loose_volume(), total, 0.0001, "the machine lost or made wood taking the branches off")
	var sanded := 0
	for item in manager.free_items():
		check(item.limbs.is_empty(), "a piece came out still on its branches")
		if Solid.has_finish(item.dims, &"sanded"):
			sanded += 1
	check_eq(sanded, 3, "the branches were not sanded with the trunk")
	done()

## The planker makes one plank of a trunk and its branches together: the
## branch wood goes into the plank at the trunk's yield, not out on its own.
func test_planker_merges_branches() -> void:
	_setup()
	var m := _inline(&"sawmill")
	_runout(m, 12.0)
	await step(3)
	var bare := _feed(m, &"wood_pine", Solid.with_finish(Solid.cylinder(0.18, 0.16, 2.4), &"sanded"))
	var plain := await _through(m, bare)
	check(plain != null, "a bare trunk made no plank")
	var plain_vol := Solid.volume(plain.dims)
	var plain_len := Solid.length_of(plain.dims)
	var ratio := plain_vol / Solid.volume(Solid.cylinder(0.18, 0.16, 2.4))
	manager.despawn(plain)
	await step(3)
	var trunk := _feed(m, &"wood_pine", Solid.with_finish(Solid.cylinder(0.18, 0.16, 2.4), &"sanded"))
	trunk.add_limb(Vector3(0.1, -0.3, 0), Vector3(0.05, 1, 0), 0.05, 0.6)
	trunk.add_limb(Vector3(-0.1, 0.4, 0), Vector3(-0.05, 1, 0), 0.05, 0.5)
	var extra := trunk.limb_volume()
	var before := m.total_out
	var plank := await _through(m, trunk)
	for i in 120:
		await step(1)
	check_eq(m.total_out - before, 1, "branches came out of the planker on their own")
	check(plank != null and plank.item_id != &"wood_pine", "the trunk was not planked")
	if plank != null:
		check_near(Solid.volume(plank.dims), plain_vol + extra * ratio, 0.0001, "the plank did not take in the branch wood")
		check_near(Solid.length_of(plank.dims), plain_len, 0.001, "the plank changed length")
	done()

## Working the crane, W moves the log away from the camera and A to the
## camera's left, whichever way the truck faces.
func test_crane_view_axes() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"crane_truck")
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), 0)
	truck.rotation.y = 0.7
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	await step(30)
	for look in [Vector3(0, -0.3, -1), Vector3(1, -0.5, 0), Vector3(-0.4, -0.2, 1)]:
		var d: Vector3 = look.normalized()
		cam.global_transform = Transform3D(Basis.looking_at(d, Vector3.UP), truck.global_position - d * 8.0)
		var axes := truck.rig.view_axes()
		var basis := truck.global_transform.basis
		var away := (basis * axes[1]).normalized()
		var left := (basis * axes[0]).normalized()
		var flat := Vector3(d.x, 0, d.z).normalized()
		check(away.dot(flat) > 0.99, "W does not go away from the camera looking %s" % look)
		check(left.dot(Vector3.UP.cross(flat)) > 0.99, "A does not go to the camera's left looking %s" % look)
	done()

## A front loader with its bucket down shoves a pile of small pieces along;
## curled and raised it carries them high; tipped, it pours them out.
func test_front_loader() -> void:
	_setup(false)
	var v := Hauler.new()
	v.setup(manager, 0, &"loader")
	world.add_child(v)
	v.global_position = Vector3(0, v.spawn_height(), 0)
	await step(60)
	var l := v.loader
	check(l != null, "the loader has no arms")
	if l == null:
		done()
		return
	# Bucket flat and down.
	l.tilt = 0.0
	l.lift = l.lift_min
	await step(30)
	var lip := l.bucket.global_transform * Vector3(0, 0, -l.depth)
	check(lip.y < 0.3, "the lowered bucket is %.2f m off the ground" % lip.y)
	var pile: Array[LooseItem] = []
	for i in 16:
		pile.append(spawn(&"ore_iron", Vector3(-0.9 + 0.6 * float(i % 4), 0.3, -8.0 - 0.6 * float(i / 4)), Solid.cube(0.02)))
	await step(60)
	var start := 0.0
	for item in pile:
		start += item.global_position.z
	v.autopilot = true
	v.input_throttle = 0.6
	await step(150)
	v.input_throttle = 0.0
	v.input_brake = true
	await step(60)
	var after := 0.0
	for item in pile:
		after += item.global_position.z
	check((start - after) / float(pile.size()) > 1.5, "the bucket did not push the pile (%.1f m)" % ((start - after) / float(pile.size())))
	# Curl and raise.
	for i in 90:
		l.drive(0.0, 1.0, 1.0 / 60.0)
		await step(1)
	for i in 240:
		l.drive(1.0, 0.0, 1.0 / 60.0)
		await step(1)
	await step(30)
	var held := l.held()
	check(held.size() >= 4, "only %d pieces in the raised bucket" % held.size())
	var high := 0
	for item in held:
		if item.global_position.y > 2.0:
			high += 1
	check(high >= 4, "only %d pieces lifted above 2 m" % high)
	# Locked: the load is clamped in, the thumb shuts, and even tipped right
	# over and driven about nothing falls out.
	var before := held.size()
	check(l.set_locked(true) != "", "the bucket would not lock")
	check_eq(l.locked_items().size(), before, "not everything in the bucket was clamped")
	for i in 120:
		l.drive(0.0, -1.0, 1.0 / 60.0)
		await step(1)
	check_near(l.thumb_angle, LoaderArm.THUMB_CLOSED, 0.01, "the thumb did not close over the load")
	v.input_brake = false
	v.input_throttle = -0.5
	await step(90)
	v.input_throttle = 0.0
	v.input_brake = true
	await step(60)
	check_eq(l.held().size(), before, "pieces fell out of the locked bucket")
	for item in l.locked_items():
		check(item.global_position.y > 1.5, "a locked piece is not up in the bucket")
	check(l.locked, "the lock let go with a driver in")
	v.autopilot = false
	await step(10)
	check(l.locked and l.locked_items().size() == before, "the lock let go when nobody was at the controls")
	# Saved and loaded, it comes back locked with its load.
	var doc := v.to_dict()
	var ids := l.locked_items().size()
	v.from_dict(doc)
	await step(10)
	check(l.locked, "the bucket came back from a save unlocked")
	check_eq(l.locked_items().size(), ids, "the locked load did not come back from a save")
	v.autopilot = true
	l.set_locked(false)
	await step(60)
	check(l.thumb_angle > 1.0, "the thumb did not open")
	# Tip it out.
	for i in 120:
		l.drive(0.0, -1.0, 1.0 / 60.0)
		await step(1)
	await step(120)
	check(l.held().size() <= 1, "%d pieces stayed in the tipped bucket" % l.held().size())
	check(v.global_transform.basis.y.dot(Vector3.UP) > 0.9, "the loader tipped over")
	done()

## With nothing after it, a machine tips what it makes out on the ground past
## its end - a few pieces, until there is no room left - then holds the rest.
func test_machine_dumps_on_ground() -> void:
	_setup()
	var m := _inline(&"sander")
	await step(3)
	for i in 12:
		_feed(m, &"wood_pine", Solid.cylinder(0.15, 0.13, 1.2))
		await step(40)
	await step(60 * 8)
	check(m.total_out >= 5, "a lone machine put out only %d pieces before stopping" % m.total_out)
	check(m.total_out < 12 and not m.queue.is_empty(), "the ground past a lone machine never filled up")
	check_eq(m.total_out + m.queue.size(), 12, "pieces went missing in the machine")
	for item in manager.free_items():
		var local := m.to_local(item.global_position)
		check(local.z < -m.canopy_length() * 0.5, "a dumped piece is back inside the machine")
		check(local.y > -0.5, "a dumped piece went through the ground")
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
		belt.global_position + Vector3(0, 0.6, 1.2)), 0, Vector3.ZERO, Solid.with_finish(Solid.cylinder(0.2, 0.18, 2.0), &"sanded"))
	log_piece = await _through(m, log_piece, 900)
	check(log_piece != null, "the belt did not carry the log through the planker")
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

	# An order for a wood takes its planks too.
	quests.active = [{
		"id": &"plank_order", "title": "Pine order", "item": &"wood_pine",
		"category": &"", "volume": 0.5, "delivered": 0.0, "reward": 250,
	}]
	check_eq(quests.deliver(&"lumber_oak", &"lumber", 0.6), 0, "a pine order took oak planks")
	check_eq(quests.deliver(&"lumber_pine", &"lumber", 0.6), 250, "a pine order would not take pine planks")

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
	PlayerState.add_copy(&"conveyor_ramp")
	check(ramp_def.rise > 0.5, "the belt ramp does not climb")
	var ramp := plot.place(ramp_def, Vector2i(-4, -4) * Plot.SUB, 0) as Conveyor
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
	var flat := plot.place(GameData.building(&"conveyor"), Vector2i(4, -4) * Plot.SUB, 0) as Conveyor
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

## Spec: belts carry by friction and nothing else. Whatever reaches the end
## rides off it and falls - it is never handed to what is beside it.
func test_belt_dumps_off_end() -> void:
	_setup()
	var belt := Conveyor.new()
	belt.length = 4.0
	belt.width = 0.9
	world.add_child(belt)
	var bin := StorageBin.new()
	bin.setup(manager, GameData.building(&"storage"), 0)
	# Within the old hand-off reach (1.2 m) of the end, clear of where it falls.
	bin.position = Vector3(0, 0, -3.9)
	world.add_child(bin)
	await step(3)
	var piece := spawn(&"lumber_pine", Vector3(0, 0.5, 1.2))
	await step(240)
	check_eq(bin.count(), 0, "the belt handed its piece into the bin beside its end")
	check(is_instance_valid(piece) and piece.state == LooseItem.State.FREE, "the piece is not a loose body")
	check(piece.global_position.y < 1.2, "the piece did not fall off the end (y %.2f)" % piece.global_position.y)
	check(belt.total_delivered >= 1, "going off the end was not counted")
	done()

## Spec: a ramp stretched long enough climbs over a truck's side, and what
## rides off the top drops into the bed - that is how a belt loads a truck.
func test_ramp_loads_truck() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0)
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), 0)
	await step(60)
	var tail: Vector3 = truck.global_transform * Vector3(0, truck.bed_floor + truck.wall_height, truck.bed_back)
	# Half a metre up for every metre along, as the ramp piece climbs.
	var length := float(2 * int(ceil(tail.y / 0.5 + 3.0)))
	var ramp := Conveyor.new()
	ramp.length = length
	ramp.width = 0.9
	ramp.rise = length * 0.5
	var top_end := tail.z - 0.7
	ramp.position = Vector3(0, 0, top_end + length * 0.5)
	world.add_child(ramp)
	await step(3)
	for i in 3:
		spawn(&"lumber_pine", ramp.global_position + Vector3(0, 0.6, length * 0.5 - 0.8))
		await step(50)
	await step(60 * 8)
	check(truck.cargo_count() >= 3, "the ramp loaded %d of 3 pieces into the truck" % truck.cargo_count())
	done()

## A bend carries a piece round the corner by friction alone.
func test_belt_bend() -> void:
	for turn in [-1.0, 1.0]:
		_setup()
		var bend := ConveyorBend.new()
		bend.turn = turn
		bend.length = 2.0
		bend.width = 0.9
		world.add_child(bend)
		await step(3)
		var piece := spawn(&"ingot_iron", Vector3(0, 0.5, 0.85), Solid.box(Vector3(0.2, 0.4, 0.1)))
		await step(150)
		check(piece.global_position.x * turn > 1.0, "a %s bend did not carry the piece round (at %s)" % [
			"left" if turn < 0 else "right", str(piece.global_position)])
		check(absf(piece.global_position.z) < 0.9, "the piece left the %s bend the wrong way (at %s)" % [
			"left" if turn < 0 else "right", str(piece.global_position)])
	done()

## Three ways in, one way out.
func test_belt_merge() -> void:
	_setup()
	var merge := ConveyorMerge.new()
	merge.length = 3.0
	merge.width = 3.0 * 0.9
	world.add_child(merge)
	await step(3)
	var from_back := spawn(&"ingot_iron", Vector3(0, 0.5, 1.2), Solid.box(Vector3(0.2, 0.3, 0.1)))
	var from_left := spawn(&"ingot_iron", Vector3(-1.25, 0.5, 0.3), Solid.box(Vector3(0.2, 0.3, 0.1)))
	from_left.linear_velocity = Vector3(2.5, 0, 0)
	var from_right := spawn(&"ingot_iron", Vector3(1.25, 0.5, 0.6), Solid.box(Vector3(0.2, 0.3, 0.1)))
	from_right.linear_velocity = Vector3(-2.5, 0, 0)
	await step(240)
	for piece: LooseItem in [from_back, from_left, from_right]:
		var p := piece.global_position
		check(p.z < -1.5, "a piece did not come out of the merger's front (at %s)" % str(p))
		check(absf(p.x) < 0.9, "a piece left the merger beside its mouth (at %s)" % str(p))
	done()

## The aligning belt sets a crooked piece in the middle, lying along the run.
func test_belt_align() -> void:
	_setup()
	var belt := ConveyorAlign.new()
	belt.length = 4.0
	belt.width = 0.9
	world.add_child(belt)
	await step(3)
	var plank := manager.spawn(&"lumber_pine", Transform3D(Basis(Vector3.UP, 0.8) * Basis(Vector3.RIGHT, PI * 0.5),
		Vector3(0.25, 0.4, 1.3)), 0, Vector3.ZERO, Solid.box(Vector3(0.3, 1.0, 0.06)))
	await step(20)
	check(belt.total_aligned >= 1, "the aligning belt set nothing straight")
	var local := belt.to_local(plank.global_position)
	check(absf(local.x) < 0.05, "the piece is not in the middle of the belt (x %.2f)" % local.x)
	var along := belt.global_transform.basis.inverse() * plank.global_transform.basis.y
	check(absf(along.z) > 0.98, "the piece is not lying along the belt (%s)" % str(along))
	done()

## The T: left and right in turn, never straight on.
func test_splitter_t() -> void:
	_setup()
	var t := Splitter.new()
	t.setup(GameData.building(&"splitter_t"))
	t.enabled_outputs = [true, false, true]
	t.position = Vector3(0, 0.6, 0)
	world.add_child(t)
	await step(2)
	for i in 4:
		spawn(&"lumber_pine", Vector3(0, 1.1, 0))
		await step(40)
	await step(60)
	var left := 0
	var right := 0
	for item in manager.free_items():
		if item.global_position.x < -0.8:
			left += 1
		elif item.global_position.x > 0.8:
			right += 1
	check(left >= 1 and right >= 1, "the T did not send pieces both ways (left %d, right %d)" % [left, right])
	check_eq(left + right, 4, "a piece went straight through the T")
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

## Built from build mode on the plot, in a line of belts: a belt into the back
## of the 3-way splitter, a belt off each side and the front. Pieces go out
## all three, and none is left on the plate.
func test_splitter_belts() -> void:
	_setup()
	var def := GameData.building(&"splitter")
	check(not def.hidden, "the 3-way splitter is not in build mode")
	check(def.id in PlayerState.available_buildings().map(func(d): return d.id), "the 3-way splitter is not offered")
	var sp := plot.place(def, Vector2i(0, 0), 0, false) as Splitter
	check(sp != null, "the splitter would not go down")
	await step(3)
	# Belts round it, each running away from it, the in-belt running into it.
	var belts: Array = []
	for spec in [[Vector3(0, 0, 3.5), 0.0], [Vector3(-3.5, 0, 0), PI * 0.5], [Vector3(0, 0, -3.5), 0.0], [Vector3(3.5, 0, 0), -PI * 0.5]]:
		var belt := Conveyor.new()
		belt.length = 4.0
		belt.width = 0.9
		belt.speed = 3.0
		world.add_child(belt)
		belt.global_transform = Transform3D(Basis(Vector3.UP, spec[1]), sp.global_position + spec[0])
		belts.append(belt)
	await step(3)
	for i in 6:
		spawn(&"ingot_iron", sp.global_position + Vector3(0, 0.45, 4.8), Solid.box(Vector3(0.2, 0.3, 0.1)))
		await step(45)
	await step(150)
	var ways := {"left": 0, "straight": 0, "right": 0}
	var lost := 0
	for item in manager.free_items():
		var local: Vector3 = sp.global_transform.affine_inverse() * item.global_position
		if local.x < -1.6:
			ways.left += 1
		elif local.x > 1.6:
			ways.right += 1
		elif local.z < -1.6:
			ways.straight += 1
		if absf(local.x) < 1.6 and absf(local.z) < 1.6:
			lost += 1
	check(int(ways.left) > 0 and int(ways.straight) > 0 and int(ways.right) > 0,
		"the splitter did not deal onto all three belts (%s)" % str(ways))
	check_eq(lost, 0, "pieces left sitting on the splitter")
	done()

## Aiming at a side of a splitter and pressing [R] locks that way (a gate
## comes down across it) or opens it again; pieces only go out the open ways,
## and which are locked is kept with the plot.
func test_splitter_locks() -> void:
	_setup()
	var sp := plot.place(GameData.building(&"splitter"), Vector2i(0, 0), 0, false) as Splitter
	await step(3)
	var at := sp.global_position
	check_eq(sp.toggle_toward(at + Vector3(-1.2, 0.2, 0)), 0, "aiming left did not pick the left way")
	check_eq(sp.toggle_toward(at + Vector3(1.2, 0.2, 0.1)), 2, "aiming right did not pick the right way")
	check_eq(sp.toggle_toward(at + Vector3(0, 0.2, 1.3)), -1, "aiming at the way in locked something")
	check(not sp.enabled_outputs[0] and sp.enabled_outputs[1] and not sp.enabled_outputs[2], "the wrong ways are locked")
	check(sp._gates[0].visible and not sp._gates[1].visible, "no gate across the locked way")
	check(sp.status_line().contains("left LOCKED"), "the prompt does not say the left is locked")
	for i in 5:
		spawn(&"ingot_iron", at + Vector3(0, 0.45, 0.9), Solid.box(Vector3(0.2, 0.3, 0.1)))
		await step(40)
	await step(90)
	var sideways := 0
	var front := 0
	for item in manager.free_items():
		var local: Vector3 = sp.global_transform.affine_inverse() * item.global_position
		if absf(local.x) > 1.6:
			sideways += 1
		elif local.z < -1.4:
			front += 1
	check_eq(sideways, 0, "a piece went out a locked way")
	check(front >= 4, "only %d of 5 went out the open front" % front)
	# Kept with the plot.
	var saved := plot.to_dict()
	plot.clear_buildings()
	await step(2)
	plot.from_dict(saved)
	await step(3)
	var back: Splitter = null
	for rec in plot.placed:
		if rec.node is Splitter:
			back = rec.node
	check(back != null and not back.enabled_outputs[0] and back.enabled_outputs[1] and not back.enabled_outputs[2],
		"the locks were not kept through a save")
	sp = back
	sp.toggle_toward(sp.global_position + Vector3(-1.2, 0.2, 0))
	check(sp.enabled_outputs[0] and not sp._gates[0].visible, "the left way would not open again")
	done()

func test_filter() -> void:
	_setup()
	await _filter_run(GameData.building(&"filter"), 0.0, "")
	# Turned a quarter round, and stretched long and narrow: it sorts the same.
	var long := Plot.resized(GameData.building(&"filter"), Vector3i(1, 1, 8))
	check(not Plot.size_limits(GameData.building(&"filter")).is_empty(), "the filter cannot be resized")
	await _filter_run(long, PI * 0.5, "turned, stretched: ", Vector3(14, 0, 0))

	# The rules themselves: first match wins, then the default.
	var f2 := Filter.new()
	f2.set_rules([
		{"type": "ore", "stage": "crushed", "let": false},
		{"type": "ore", "sub": "iron", "size": "under", "m3": 0.1, "let": true},
	], true)
	var crushed := Solid.chunk(0.05)
	crushed["crushed"] = true
	check(not f2.decide(&"ore_iron", crushed), "crushed iron dropped despite the first rule")
	check(f2.decide(&"ore_iron", Solid.chunk(0.05)), "small iron ore did not drop")
	check(f2.decide(&"ore_copper", Solid.chunk(0.5)), "the default (drop) was not used")
	f2.drop_by_default = false
	check(not f2.decide(&"ore_iron", Solid.chunk(0.5)), "big iron dropped with nothing letting it")
	check(f2.decide(&"ore_iron", Solid.chunk(0.05)), "small iron stopped dropping")
	check(Filter.stage_of(&"lumber_mahogany", Solid.box(Vector3(0.3, 1, 0.1))) == "plank", "a plank is not a plank")
	check(Filter.stage_of(&"ingot_iron", Solid.with_finish(Solid.box(Vector3(0.1, 0.4, 0.1)), &"refined")) == "refined", "a refined bar is not refined")
	check(Filter.type_of(&"glass") == "stone", "glass is not under stone")
	var back := Filter.new()
	back.from_dict(f2.to_dict())
	check(back.rules.size() == 2 and not back.drop_by_default, "the rules did not survive a save")
	f2.free()
	back.free()
	done()

## Planks and ore lumps down a filter set to drop wood: planks fall through,
## ore rides over. Checks run for any size and heading.
func _filter_run(def: BuildingDef, yaw: float, tag: String, at := Vector3.ZERO) -> void:
	var filter := Filter.new()
	filter.setup(def)
	filter.length = def.extent().z
	filter.width = def.extent().x * 0.9
	filter.set_rules([{"type": "wood", "let": true}], false)
	filter.position = at + Vector3(0, 1.5, 0)
	filter.rotation.y = yaw
	world.add_child(filter)
	await step(2)
	var entry: Vector3 = filter.global_transform * Vector3(0, 0.4, filter.length * 0.5 - 0.35)
	var mine: Array[LooseItem] = []
	for i in 3:
		mine.append(spawn(&"lumber_pine", entry, Solid.box(Vector3(0.3, 0.4, 0.1))))
		await step(40)
		mine.append(spawn(&"ore_iron", entry, Solid.chunk(0.02)))
		await step(40)
	await step(120 + int(filter.length * 30.0))
	var dropped_planks := 0
	var carried_ore := 0
	var wrong := 0
	for item in mine:
		if not is_instance_valid(item):
			continue
		var local: Vector3 = filter.global_transform.affine_inverse() * item.global_position
		var fell := local.y < -0.5 and absf(local.z) < filter.length * 0.5
		var rode_off := local.z < -filter.length * 0.5
		if item.item_id == &"lumber_pine":
			if fell:
				dropped_planks += 1
			elif rode_off:
				wrong += 1
		else:
			if rode_off:
				carried_ore += 1
			elif fell:
				wrong += 1
	check(dropped_planks >= 2, tag + "only %d of 3 planks dropped through the grate" % dropped_planks)
	check(carried_ore >= 2, tag + "only %d of 3 ore lumps rode over the grate" % carried_ore)
	check_eq(wrong, 0, tag + "the filter sent pieces the wrong way")

## A load heaped up over the sides is fixed like the rest: the top of the
## pile used to be left out of the cargo, and slid off on the road.
func test_heaped_load_fixed() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0)
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), 0)
	await step(40)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mine: Array[LooseItem] = []
	for i in 360:
		var top: Vector3 = truck.global_transform * Vector3(rng.randf_range(-0.5, 0.5),
			truck.bed_floor + truck.wall_height + 2.5, truck.bed_mid_z + rng.randf_range(-0.6, 0.6))
		mine.append(spawn(&"ore_iron" if i % 2 == 0 else &"lumber_pine", top,
			Solid.chunk(0.03) if i % 2 == 0 else Solid.box(Vector3(0.2, 0.1, 0.9))))
		await step(4)
	await step(240)
	var driver := Node3D.new()
	world.add_child(driver)
	truck.driver = driver
	await step(400)
	var in_bed := 0
	var above := 0
	var loose := 0
	for it in mine:
		var l: Vector3 = truck.global_transform.affine_inverse() * it.global_position
		if absf(l.x) > truck.bed_half_width + 0.2 or l.z > truck.bed_back + 0.1 or l.z < truck.bed_front - 0.1 or l.y < truck.bed_floor - 0.1:
			continue
		in_bed += 1
		if l.y > truck.bed_floor + truck.wall_height + 0.7:
			above += 1
		if not truck.is_fixed(it):
			loose += 1
	check(above > 5, "the test load was not heaped well over the sides (%d above)" % above)
	check(loose <= 2, "%d of %d pieces in a heaped bed were left loose" % [loose, in_bed])
	done()

## Picking a piece up touches nothing else: taken out of the middle of a row,
## its neighbours stay exactly where they were, and carried about it does
## not knock things over. Put down, it is solid again.
func test_pick_up_disturbs_nothing() -> void:
	_setup()
	var player := _make_player()
	world.add_child(player)
	PlayerState.levels[&"carry"] = 5
	var box := Solid.box(Vector3(0.4, 0.4, 0.4))
	var row: Array[LooseItem] = []
	for i in 3:
		row.append(spawn(&"lumber_pine", Vector3(3.0 + float(i) * 0.41, 0.25, 0), box))
	await step(90)
	var was: Array[Vector3] = []
	for it in row:
		was.append(it.global_position)
	check(player.pick_up(row[1]), "could not pick up the middle piece")
	await step(3)
	# Walk the rack straight through where the others are.
	for f in 40:
		player.global_position = Vector3(2.0 + f * 0.05, 0.0, 0.85)
		await step(1)
	await step(30)
	for i in [0, 2]:
		check(row[i].global_position.distance_to(was[i]) < 0.02,
			"a neighbour moved %.2f m when its fellow was picked up" % row[i].global_position.distance_to(was[i]))
	player._drop(1)
	await step(60)
	check(row[1].state == LooseItem.State.FREE and row[1].collision_layer == Layers.LOOSE,
		"a piece put down is not solid again")
	check(row[1].global_position.y > -0.1, "a piece put down fell through the ground")
	done()

func test_building() -> void:
	_setup()
	await step(2)
	Economy.from_dict({"money": 1000, "day": 1})
	var def := GameData.building(&"sawmill")
	var node := plot.place(def, Vector2i(0, 0) * Plot.SUB, 0)
	check(node != null, "could not place a sawmill on an empty plot (money=%d, err=%s, extent=%.1f)" % [
		Economy.money, plot.placement_error(def, Vector2i(0, 0) * Plot.SUB, 0), plot.half_extent])
	check_eq(Economy.money, 1000 - def.cost, "placement did not charge the cost")
	check_eq(plot.placed.size(), 1, "plot did not record the building")
	check(plot.occupied.size() == def.size.x * def.size.z * Plot.SUB * Plot.SUB, "wrong number of cells reserved")

	# Buildings may overlap: a second one goes in the same space, and taking
	# it away leaves the first where it was.
	Economy.from_dict({"money": 1000, "day": 1})
	check_eq(plot.placement_error(def, Vector2i(1, 1) * Plot.SUB, 0), "", "overlapping placement was refused")
	var overlap := plot.place(def, Vector2i(1, 1) * Plot.SUB, 0)
	check(overlap != null, "overlapping placement was refused")
	check_eq(plot.index_at_world(overlap.global_position), 1, "the newest building is not the one found in a shared cell")
	check(plot.remove(overlap), "could not remove the overlapping building")
	check_eq(plot.placed.size(), 1, "removing the overlap removed the other too")
	check(plot.index_at_world(node.global_position) == 0, "the first building lost its cells")
	Economy.from_dict({"money": 1000 - def.cost, "day": 1})
	var outside := plot.place(def, Vector2i(9999, 9999) * Plot.SUB, 0)
	check(outside == null, "placement outside the plot was allowed")

	Economy.from_dict({"money": 10, "day": 1})
	check(plot.place(def, Vector2i(-10, -10) * Plot.SUB, 0) == null, "placed a building without money")

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
	var cell := Vector2i(-16, -16) * Plot.SUB
	for def: BuildingDef in GameData.buildings.values():
		if not plot.can_place(def, cell, Vector3i.ZERO, false):
			cell = Vector2i(-16 * Plot.SUB, cell.y + 8 * Plot.SUB)
			if not plot.can_place(def, cell, Vector3i.ZERO, false):
				continue
		var node := plot.place(def, cell, Vector3i.ZERO, false)
		cell.x += (def.size.x + 2) * Plot.SUB
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
func test_ladder_plan() -> void:
	_setup()
	Economy.from_dict({"money": 50000, "day": 1})
	var plan := plot.place(GameData.building(&"schematic_ladder"), Vector2i(0, 0) * Plot.SUB, 0) as Schematic
	await step(4)
	check(plan != null and plan.is_ladder(), "no ladder plan")
	var cap := plan.capacity_m3()
	check(cap < 0.2, "a ladder takes %.2f m3 - as much as a wall" % cap)
	check(plan.accept_item(spawn(&"lumber_pine", Vector3(0, 6, 0), Solid.box(Vector3(0.25, cap / 0.0625 + 0.1, 0.25)))), "the plan refused wood")
	await step(4)
	check(plan.solid, "the full ladder plan is not solid")
	var ladder := plan.get_node_or_null("Ladder") as Ladder
	check(ladder != null, "the finished plan has no ladder")
	if ladder != null:
		check(ladder.holds(plan.global_position + Vector3(0, 1.5, 0)), "halfway up is not on the ladder")
		check(ladder.holds(plan.global_position + Vector3(0, 0.1, 0)), "the foot of the ladder is not on it")
	done()

func test_sign_plan() -> void:
	_setup()
	Economy.from_dict({"money": 50000, "day": 1})
	var plan := plot.place(GameData.building(&"schematic_sign"), Vector2i(0, 0) * Plot.SUB, 0) as Schematic
	await step(4)
	check(plan != null and plan.is_sign(), "no sign plan")
	var cap := plan.capacity_m3()
	check(plan.accept_item(spawn(&"lumber_pine", Vector3(0, 6, 0), Solid.box(Vector3(0.25, cap / 0.0625 + 0.1, 0.25)))), "the plan refused wood")
	await step(4)
	check(plan.solid, "the full sign plan is not solid")
	plan.set_text("  Pine Yard, this way  ")
	check_eq(plan.text, "Pine Yard, this way", "the sign did not take its words")
	var labels := plan.find_children("*", "Label3D", true, false)
	check_eq(labels.size(), 2, "the sign is not written on both faces")
	for l in labels:
		check_eq((l as Label3D).text, "Pine Yard, this way", "a face of the sign does not say it")
	plan.set_text("x".repeat(100))
	check_eq(plan.text.length(), Schematic.SIGN_MAX, "a sign took more than it has room for")
	plan.set_text("Keep out")
	var saved := plan.to_dict()
	var again := plot.place(GameData.building(&"schematic_sign"), Vector2i(8, 0) * Plot.SUB, 0) as Schematic
	await step(2)
	again.from_dict(saved)
	check(again.solid and again.text == "Keep out", "a sign did not come back from a save with its words")
	done()

func test_gear_split() -> void:
	_setup()
	PlayerState.reset()
	var town := Store.new()
	town.setup(manager, plot, 0, &"general")
	world.add_child(town)
	var summit := Store.new()
	summit.setup(manager, plot, 0, &"summit")
	summit.position = Vector3(80, 0, 0)
	world.add_child(summit)
	await step(4)
	var find := func(shop: Store, target: StringName) -> Dictionary:
		for slot in shop.slots:
			if slot.kind == &"upgrade" and slot.target == target:
				return slot
		return {}
	var town_carry: Dictionary = find.call(town, &"carry")
	var top_carry: Dictionary = find.call(summit, &"carry")
	check(not town_carry.is_empty() and not top_carry.is_empty(), "the carry rack is not stocked in both shops")
	check(town.available(town_carry) and not summit.available(top_carry), "a new player is offered the top rack")
	PlayerState.levels[&"carry"] = GameData.max_upgrade_level(&"carry") - 1
	check(not town.available(town_carry), "town still sells the carry rack's top level")
	check(summit.available(top_carry), "the summit does not sell the carry rack's top level")
	check_eq(summit.price_of(top_carry), int(GameData.upgrade_level(&"carry", GameData.max_upgrade_level(&"carry")).cost), "the top rack is mispriced")
	PlayerState.reset()
	done()

func test_trailer_gates() -> void:
	_setup()
	for id in [&"trailer", &"mower_trailer"]:
		var t := Hauler.new()
		t.setup(manager, 0, id)
		world.add_child(t)
		t.global_position = Vector3(0 if id == &"trailer" else 8, t.spawn_height(), 0)
		await step(40)
		check(t.has_ramps() and t.bed_kind == &"gate", "the %s has no gate" % id)
		check(not t.ramps_down, "the %s's gate starts down" % id)
		# Closed, the gate stands across the back of the bed.
		var up := t.ramp_transform(0.0, 1.0)
		check(up.basis.z.y > 0.9, "the %s's gate is not stood up when shut" % id)
		t.toggle_ramps()
		for i in 400:
			await step(1)
			if t.ramp_pose <= 0.0:
				break
		check(t.ramps_down, "the %s's gate did not come down" % id)
		var foot := t.global_transform * (t.ramp_transform(0.0, 0.0) * Vector3(0, 0, t.ramp_length() * 0.5))
		check(foot.y < 0.4, "the %s's gate does not reach the ground (%.2f m up)" % [id, foot.y])
		t.toggle_ramps()
		for i in 400:
			await step(1)
			if t.ramp_pose >= 1.0:
				break
		check(not t.ramps_down, "the %s's gate did not go back up" % id)
	var mower: Dictionary = GameData.vehicle(&"mower_trailer")
	check_eq(float(mower.mass), 200.0, "the mower trailer is not 200 kg")
	check(mower.has("hitch"), "the mower trailer has no hitch on the back")
	check_eq(GameData.building(&"pad_mower_trailer").cost, 2500, "the mower trailer pad is not $2,500")
	var sold := false
	for p in GameData.store_products():
		if p.target == &"pad_mower_trailer" and String(GameData.store_def(StringName(p.store)).get("name", "")) == "VEHICLE DEALER":
			sold = true
	check(sold, "the vehicle dealer does not sell the mower trailer")
	done()

func test_field_minimum() -> void:
	_setup(false)
	var field := ResourceField.new()
	field.quota = 3
	field.min_present = 1
	field.refill_seconds = 9999.0
	field.spawn_clearance = 0.0
	field.setup([{"item": &"gem_black_opal", "volume": [0.1, 0.2], "embed": [0.5, 0.6]}],
		func(kind: Dictionary, form_seed: int) -> Node3D:
			var rock := OreRock.new()
			rock.manager = manager
			rock.ore_item = kind.item
			rock.seed_form(form_seed)
			rock.volume = 0.15
			return rock,
		ResourceField.annulus(6.0, 14.0), 7)
	world.add_child(field)
	field.prefill()
	check_eq(field.count(), 3, "the field did not fill")
	for node in field.alive.duplicate():
		(node as OreRock).shatter()
	await step(30)
	check(field.count() >= 1, "the field ran out and did not grow one back")
	check(field.count() < 3, "the field refilled to quota without waiting")
	var opal := GameData.item(&"gem_black_opal")
	var obsidian := GameData.item(&"gem_obsidian")
	check(opal.color != obsidian.color and OreRock.PLAY_OF_COLOUR.has(&"gem_black_opal"),
		"black opal looks just like obsidian")
	done()

func test_stone() -> void:
	_setup()
	Economy.from_dict({"money": 90000, "day": 1})
	var refiner := plot.place(GameData.building(&"refiner"), Vector2i(0, 0), 0, false) as InlineMachine
	var crusher := plot.place(GameData.building(&"crusher"), Vector2i(0, 24), 0, false) as InlineMachine
	var furnace := plot.place(GameData.building(&"furnace"), Vector2i(0, 48), 0, false) as InlineMachine
	await step(2)
	var lump := func(id: StringName, v: float) -> Dictionary:
		return {"id": id, "dims": Solid.chunk(v), "owned": true, "plot": 0, "changed": false, "ready": 0.0}
	var glass := refiner.work(lump.call(&"stone_sandstone", 0.3))
	check(glass.size() >= 1 and glass[0].id == &"glass" and bool(glass[0].changed), "sandstone did not refine into glass")
	var total := 0.0
	for e in glass:
		total += Solid.volume(e.dims)
		check(Solid.bounds(e.dims).y <= InlineMachine.GLASS_PANE + 0.001, "a sheet of glass is too long")
	check_near(total, 0.3, 0.0001, "refining sandstone lost some of it")
	check(Economy.price_of(&"glass", glass[0].dims) > Economy.price_of(&"stone_sandstone", Solid.chunk(Solid.volume(glass[0].dims))),
		"glass is worth no more than the sandstone it came from")
	check(not GameData.machine_accepts(&"refiner", &"stone_granite"), "the refiner takes granite")
	check(not GameData.machine_accepts(&"furnace", &"stone_marble"), "the smelter takes marble")
	check(GameData.machine_accepts(&"crusher", &"stone_basalt"), "the crusher will not take basalt")
	var crushed := crusher.work(lump.call(&"stone_basalt", 0.2))
	check(crushed.size() >= 2 and crushed[0].id == &"stone_basalt", "basalt was not crushed")
	check(Economy.price_of(&"stone_marble") > 0, "marble cannot be sold")
	done()

func test_turned_blueprints() -> void:
	_setup()
	Economy.from_dict({"money": 90000, "day": 1})
	var def := GameData.building(&"schematic_ramp")
	var worst := 0.0
	var worst_rot := Vector3i.ZERO
	for rx in 4:
		for ry in 4:
			for rz in 4:
				var rot := Vector3i(rx, ry, rz)
				var node := plot.place(def, Vector2i(0, 0), rot, false) as Schematic
				if node == null:
					continue
				await step(1)
				var box: AABB = (node._ghost.global_transform * node._ghost.get_aabb())
				var fp := Plot.oriented_extent(def.extent(), rot)
				var base := plot.cell_to_world(Vector2i(0, 0), def.size, rot, def.trim)
				var want := AABB(base - Vector3(fp.x * 0.5, 0, fp.z * 0.5), fp)
				var off := maxf((box.position - want.position).abs().length(), (box.end - want.end).abs().length())
				if off > worst:
					worst = off
					worst_rot = rot
				plot.remove(node)
				await step(1)
	check(worst < 0.02, "a ramp turned %s sits %.2f m off its footprint" % [worst_rot, worst])
	done()

func test_material_levels() -> void:
	_setup()
	Economy.from_dict({"money": 90000, "day": 1})
	check_eq(GameData.material_level(&"wood_pine"), 1, "pine is not level 1")
	check_eq(GameData.material_level(&"wood_ebony"), 3, "ebony is not level 3")
	check_eq(GameData.material_level(&"lumber_ebony"), 3, "ebony lumber is not level 3")
	check_eq(GameData.material_level(&"gem_turquoise"), 2, "turquoise is not level 2")
	check_eq(int(GameData.tools[&"ember_axe"].get("level", 0)), 3, "the ember axe is not level 3")
	# A level-3 tree shrugs off a level-1 axe, and gives to a level-3 one.
	var player := _make_player()
	world.add_child(player)
	await step(4)
	# Thick enough that one ember-axe blow does not fell it.
	var tree := _make_tree(6.0, 0.6, 0.6, 0)
	tree.wood_item = &"wood_ebony"
	tree.position = Vector3(0, 0, -2.0)
	world.add_child(tree)
	await step(2)
	player.select_slot(0)
	check_eq(player.selected_tool(), &"rusty_axe", "not holding the rusty axe")
	player.camera.look_at(tree.global_position + Vector3(0, 1.5, 0))
	player._swing_cd = 0.0
	player._swing()
	check_near(tree.trunk_cut, 0.0, 0.001, "a rusty axe cut ebony")
	PlayerState.give_tool(&"ember_axe", false)
	PlayerState.set_hotbar(1, &"ember_axe")
	player.select_slot(1)
	player._swing_cd = 0.0
	player._swing()
	check(tree.trunk_cut > 0.0, "the ember axe did not cut ebony")
	# A T1 planker passes a sanded level-3 log through untouched; T3 planks it.
	var log_dims := Solid.with_finish(Solid.cylinder(0.2, 0.2, 1.0), &"sanded")
	var saw := plot.place(GameData.building(&"sawmill"), Vector2i(0, 0), 0, false) as InlineMachine
	await step(2)
	var entry := func(id: StringName) -> Dictionary:
		return {"id": id, "dims": log_dims.duplicate(true), "owned": true, "plot": 0, "changed": false, "ready": 0.0}
	check(bool(saw.work(entry.call(&"wood_pine"))[0].changed), "a T1 planker did not plank pine")
	check(not bool(saw.work(entry.call(&"wood_ebony"))[0].changed), "a T1 planker planked ebony")
	check(saw.status_line().contains("higher tier"), "the planker does not say ebony needs a higher tier")
	saw.level = 2
	check(not bool(saw.work(entry.call(&"wood_ebony"))[0].changed), "a T2 planker planked ebony")
	saw.level = 3
	check(bool(saw.work(entry.call(&"wood_ebony"))[0].changed), "a T3 planker did not plank ebony")
	done()

func test_frost_slip() -> void:
	_setup()
	Economy.from_dict({"money": 50000, "day": 1})
	var plan := plot.place(GameData.building(&"schematic_slab"), Vector2i(0, 0) * Plot.SUB, 0) as Schematic
	var pine := plot.place(GameData.building(&"schematic_slab"), Vector2i(12, 0) * Plot.SUB, 0) as Schematic
	await step(4)
	var cap := plan.capacity_m3()
	check(plan.accept_item(spawn(&"lumber_frost", Vector3(0, 6, 0), Solid.box(Vector3(0.25, cap / 0.0625 + 0.1, 0.25)))), "the plan refused frost wood")
	check(pine.accept_item(spawn(&"lumber_pine", Vector3(12, 6, 0), Solid.box(Vector3(0.25, cap / 0.0625 + 0.1, 0.25)))), "the plan refused pine")
	await step(4)
	check(plan.solid and plan.is_slippery(), "a finished frost-wood slab is not slippery")
	check(not pine.is_slippery(), "pine is slippery")
	# Walking onto each and letting go of the keys: on frost wood you slide on.
	var slides: Array[float] = []
	for slab in [plan, pine]:
		var player := _make_player()
		world.add_child(player)
		player.global_position = (slab as Node3D).global_position + Vector3(0, 1.5, 0)
		await step(30)
		player.velocity = Vector3(4.0, 0, 0)
		var start := player.global_position
		for i in 20:
			await step(1)
		slides.append(player.global_position.distance_to(start))
		player.queue_free()
		await step(2)
	check(slides[0] > slides[1] * 1.8, "no slide on frost wood (%.2f m vs %.2f m)" % [slides[0], slides[1]])
	done()

func test_schematic() -> void:
	_setup()
	Economy.from_dict({"money": 50000, "day": 1})
	var node := plot.place(GameData.building(&"schematic_slab"), Vector2i(0, 0) * Plot.SUB, 0)
	var plan := node as Schematic
	check(plan != null, "the slab plan was not placed")
	await step(4)

	# A 2 x 1 x 2 plan is four cubic metres of shape, and takes a tenth of
	# that (the balance file's share) in material. It starts as a drawing.
	var cap := 4.0 * Schematic.MATERIAL_SHARE
	check_near(plan.capacity_m3(), cap, 0.0001, "the plan wants the wrong volume")
	check_near(Schematic.MATERIAL_SHARE, 0.05, 0.0001, "a plan should take a twentieth of its volume")
	check(not plan.solid, "an empty plan is already solid")
	check_eq(plan.material, &"", "an empty plan already has a material")
	check(plan.can_accept(&"lumber_pine"), "an empty plan refused lumber")
	check(plan.can_accept(&"ingot_iron"), "an empty plan refused metal")

	# The first piece in decides what it is made of.
	var first := spawn(&"lumber_pine", Vector3(0, 6, 0), Solid.box(Vector3(0.25, cap / 8.0 / 0.0625, 0.25)))
	check_near(first.volume(), cap / 8.0, 0.0001, "test piece is the wrong size")
	check(plan.accept_item(first), "the plan refused the first piece")
	check_eq(plan.material, &"lumber_pine", "the plan did not take its material from the first piece")
	check_near(plan.filled_m3, cap / 8.0, 0.0001, "the plan filled by the wrong amount")
	check(not plan.solid, "a plan one eighth full turned solid")

	# And from then on it takes nothing else.
	check(not plan.can_accept(&"lumber_oak"), "a pine plan accepted oak")
	var wrong := spawn(&"lumber_oak", Vector3(0, 6, 0), Solid.box(Vector3(0.25, 2.0, 0.25)))
	check(not plan.accept_item(wrong), "a pine plan swallowed oak")
	check_near(plan.filled_m3, cap / 8.0, 0.0001, "a refused piece still filled the plan")

	# Fill it the rest of the way, with the last piece deliberately too big.
	var second := spawn(&"lumber_pine", Vector3(0, 6, 0), Solid.box(Vector3(0.25, cap * 0.75 / 0.0625, 0.25)))
	check(plan.accept_item(second), "the plan refused more of its own material")
	check_near(plan.filled_m3, cap * 0.875, 0.0001, "the plan did not take the whole piece")

	var oversized := spawn(&"lumber_pine", Vector3(0, 6, 0), Solid.box(Vector3(0.25, cap * 0.5 / 0.0625, 0.25)))
	var oversized_volume := oversized.volume()
	check(oversized_volume > plan.remaining_m3(), "the oversized piece is not actually oversized")
	check(plan.accept_item(oversized), "the plan refused the last piece")
	await step(4)
	check(plan.solid, "a full plan did not turn solid")
	check_near(plan.filled_m3, cap, 0.0001, "a full plan holds the wrong volume")
	# The offcut comes back rather than vanishing into the wall.
	check_near(loose_volume(&"lumber_pine"), oversized_volume - cap / 8.0, 0.0001,
		"the offcut from the last piece was not returned")
	check(not plan.can_accept(&"lumber_pine"), "a finished plan still takes material")

	# Pulling it down gives the material back, not cash.
	var before := loose_volume(&"lumber_pine")
	var reclaimed := plan.reclaim()
	await step(4)
	check_near(reclaimed, cap, 0.0001, "reclaiming returned the wrong volume")
	check_near(loose_volume(&"lumber_pine") - before, cap, 0.0001,
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
	var z := Cave.COVERED_FROM + 1.0
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
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(mid + Vector3(0, 3, 0), mid + Vector3(0, -30, 0), Layers.WORLD))
	check(not hit.is_empty() and hit.collider != land, "the way in is still full of ground")
	if not hit.is_empty():
		check_near(hit.position.y, ground, 0.2, "the way in is not level with the ground at the door")
	# A doorway, not a ramp: from in front, walk straight in at head height
	# with nothing in the way, and room either side for a truck.
	var front := cave.to_global(Vector3(0, 1.7, -6.0))
	var deep := cave.to_global(Vector3(0, 1.7, Cave.SHAFT_LENGTH - 1.0))
	check(space.intersect_ray(PhysicsRayQueryParameters3D.create(front, deep, Layers.WORLD)).is_empty(), "something blocks the doorway")
	for sx in [-1.0, 1.0]:
		var side_from := cave.to_global(Vector3(sx * 1.4, 3.5, -2.0))
		var side_to := cave.to_global(Vector3(sx * 1.4, 3.5, Cave.SHAFT_LENGTH - 1.0))
		check(space.intersect_ray(PhysicsRayQueryParameters3D.create(side_from, side_to, Layers.WORLD)).is_empty(),
			"the doorway is too narrow or low for a truck")
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
	plot.place(GameData.building(&"sawmill"), Vector2i(0, 0) * Plot.SUB, 0)
	plot.place(GameData.building(&"storage"), Vector2i(4, -6) * Plot.SUB, 0)
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
	# Co-op: your name and the host you last joined are remembered.
	Settings.set_value(&"player_name", "Rowan")
	Settings.set_value(&"last_address", "192.168.1.20:7777")
	Settings.load_from(path)
	check_eq(Settings.value(&"player_name"), "Rowan", "the co-op name was not remembered")
	check_eq(Settings.value(&"last_address"), "192.168.1.20:7777", "the last host address was not remembered")
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
	# Every action the controls sheet names is a real action, and its key
	# draws as a keycap.
	for group in KeyGuide.GROUPS:
		for row in group.rows:
			for k in row[0]:
				if k is StringName:
					check(not Controls.info(k).is_empty(), "controls sheet names '%s', which is not an action" % k)
					check(UIKit.is_key_text(Controls.key(k)), "'%s' is on '%s', which is not a key" % [k, Controls.key(k)])
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
	plot.place(GameData.building(&"sawmill"), Vector2i(0, 0) * Plot.SUB, 0)
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
	plot.place(GameData.building(&"workbench"), Vector2i(0, 0) * Plot.SUB, 0)
	plot.place(GameData.building(&"sawmill"), Vector2i(8, 8) * Plot.SUB, 0)
	plot.place(GameData.building(&"conveyor"), Vector2i(-6, 0) * Plot.SUB, 1)
	plot.place(GameData.building(&"storage"), Vector2i(4, -6) * Plot.SUB, 0)
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
	var far_cell := Vector2i(int(before_extent) + 2, 0) * Plot.SUB
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

	check(shop.slots.size() > 12, "the store has only %d shelf slots" % shop.slots.size())
	var sections := {}
	for slot in shop.slots:
		sections[slot.section] = true
	# The hardware store in town has the tools, gear and doodads; vehicles are
	# at the dealer and machines at the works, each a shop of its own.
	for want in ["TOOLS", "GEAR", "DOODADS"]:
		check(sections.has(want), "the store has no %s section" % want)
	check(not sections.has("VEHICLES") and not sections.has("MACHINERY"), "the hardware store still sells vehicles or machines")
	var works := Store.new()
	works.setup(manager, plot, 0, &"works")
	works.position = Vector3(60, 0, 0)
	world.add_child(works)
	var dealer := Store.new()
	dealer.setup(manager, plot, 0, &"dealer")
	dealer.position = Vector3(-60, 0, 0)
	world.add_child(dealer)
	await step(60)
	var in_works := {}
	for slot in works.slots:
		in_works[slot.section] = true
	check(in_works.has("MACHINERY"), "the machine works sells no machinery")
	var pads := 0
	for slot in dealer.slots:
		pads += int(String(slot.target).begins_with("pad_"))
	check(pads >= 5, "the dealer has only %d vehicles" % pads)
	# Each box stands beside a model of what is in it.
	var shown := 0
	for c in dealer.get_children():
		shown += int(c.name.begins_with("Display"))
	check(shown >= 6, "only %d display models at the dealer" % shown)
	var stocked := 0
	for slot in shop.slots:
		if slot.item != null:
			stocked += 1
			var box: LooseItem = slot.item
			check(shop.contains(box.global_position), "a %s box is not on a shelf in the shop" % slot.box)
	check(stocked > 12, "only %d boxes on the shelves" % stocked)

	# The timber axe is a tool: priced off tools.json, and opening it puts the
	# axe in the inventory and on the hotbar.
	var axe_slot: Dictionary = {}
	for slot in shop.slots:
		if slot.kind == &"tool" and slot.target == &"timber_axe":
			axe_slot = slot
	check(not axe_slot.is_empty(), "the store does not stock a timber axe")
	check_eq(shop.price_of(axe_slot), int(GameData.tool(&"timber_axe").cost), "the axe box is mispriced")
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
	check(not PlayerState.owns_tool(&"timber_axe"), "the axe was handed over before the box was opened")
	shop.open_box(box)
	check(PlayerState.owns_tool(&"timber_axe"), "opening the box did not give the axe")
	check(PlayerState.hotbar.has(&"timber_axe"), "the new axe did not go on the hotbar")
	await step(4)
	check_eq(box.state, LooseItem.State.POOLED, "the opened box is still lying about")
	shop.restock()
	check(axe_slot.item == null, "a tool you own is still on the shelf")

	# Machine tiers can be bought in any order, and each box is one machine
	# at its own tier.
	var t1: Dictionary = {}
	var t2: Dictionary = {}
	var town := shop
	shop = works
	for slot in shop.slots:
		if slot.kind == &"tier" and slot.target == &"sander":
			if slot.tier == 1:
				t1 = slot
			elif slot.tier == 2:
				t2 = slot
	check(not t1.is_empty() and not t2.is_empty(), "the sander tiers are not stocked")
	check_eq(shop.blocked(t2), "", "sander T2 is held back until the sander is bought")
	var t2_box: LooseItem = t2.item
	shop.buy([t2_box] as Array[LooseItem])
	check(t2_box.owned, "sander T2 was refused before the sander")
	shop.open_box(t2_box)
	# One T2 sander to build, and no T1: every copy is bought on its own.
	check_eq(PlayerState.spare_count(&"sander", 2), 1, "sander T2 did not give one T2 sander")
	check_eq(PlayerState.spare_count(&"sander", 1), 0, "sander T2 gave a T1 sander too")
	await step(2)
	check(shop.available(t1) and shop.available(t2), "machine boxes left the shelf once bought")

	# An unpaid box will not open, and carried out it goes back on the shelf.
	shop = dealer
	var pad_slot: Dictionary = {}
	for slot in shop.slots:
		if slot.target == &"pad_quad":
			pad_slot = slot
	var fresh: LooseItem = pad_slot.item
	check_eq(shop.open_box(fresh), "that one has not been paid for", "an unpaid box opened anyway")
	var outside := shop.global_position + Vector3(0, 1, 60)
	fresh.teleport(Transform3D(Basis(), outside))
	await step(40)
	check(pad_slot.item == fresh and is_instance_valid(fresh) and fresh.state == LooseItem.State.FREE,
		"a moved box was cleared before it had been gone a minute")
	# A minute on, it is gone and a fresh box is on the shelf at once.
	pad_slot["away"] = Store.MISPLACED_GRACE - 0.5
	await step(60)
	var stranded := 0
	for item in manager.free_items():
		if item.item_id == pad_slot.box and not shop.contains(item.global_position):
			stranded += 1
	check_eq(stranded, 0, "unpaid stock survived being carried out of the shop")
	# (The pool may hand back the very same box object, so check where it is.)
	var on_shelf := func() -> bool:
		var it: LooseItem = pad_slot.item
		return it != null and is_instance_valid(it) and it.state == LooseItem.State.FREE \
			and it.global_position.distance_to(pad_slot.spot) < Store.MISPLACED_BY
	check(on_shelf.call(), "the shelf was not restocked at once")
	# Knocked off its place inside the shop and left: cleared away too.
	var nudged: LooseItem = pad_slot.item
	nudged.teleport(Transform3D(Basis(), (pad_slot.spot as Vector3) + (pad_slot.basis as Basis).z * 3.0 + Vector3(0, 0.2, 0)))
	await step(60 * 2)
	check(pad_slot.item == nudged, "a nudged box was cleared within a minute")
	pad_slot["away"] = Store.MISPLACED_GRACE - 0.5
	await step(60)
	check(on_shelf.call(), "a box knocked off its place was left lying about")
	# Knocked over where it stood: cleared away as well.
	var tipped: LooseItem = pad_slot.item
	if tipped != null:
		tipped.teleport(Transform3D((pad_slot.basis as Basis) * Basis(Vector3.RIGHT, PI * 0.5), pad_slot.spot as Vector3))
		tipped.freeze = true
		await step(60)
		pad_slot["away"] = Store.MISPLACED_GRACE - 0.5
		await step(60)
		check(on_shelf.call() and (pad_slot.item as LooseItem).global_transform.basis.y.dot((pad_slot.basis as Basis).y) > 0.9,
			"a box knocked over on its spot was left lying there")
		if is_instance_valid(tipped):
			tipped.freeze = false

	# Land is sold at the desk.
	shop = town
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
	for slot in dealer.slots:
		check(slot.target != &"pad_log_truck", "the town dealer sells the log truck")
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
## by one end comes along by that end - and, weightless while held, stays
## level rather than drooping from it.
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
	check(log_piece.global_position.y > point.y - 0.3, "a held log sagged %.2f m from the end it was grabbed by" % (point.y - log_piece.global_position.y))
	check(log_piece.global_position.distance_to(target) > 0.6, "the log was pulled by its middle, not the point grabbed")
	# Held at its angle to the player: turning, it swings round with them and
	# keeps that angle.
	var rel := (Basis(Vector3.UP, player.global_rotation.y).inverse() * log_piece.global_transform.basis).orthonormalized()
	var offset := Basis(Vector3.UP, player.global_rotation.y).inverse() * (log_piece.global_position - player.global_position)
	player.rotation.y += PI * 0.5
	for i in 120:
		await step(1)
	var now := Basis(Vector3.UP, player.global_rotation.y)
	var rel_now := (now.inverse() * log_piece.global_transform.basis).orthonormalized()
	check(rel_now.y.dot(rel.y) > 0.97, "the held log did not keep its angle to the player as they turned")
	var offset_now := now.inverse() * (log_piece.global_position - player.global_position)
	check(offset_now.distance_to(offset) < 0.5, "the held log did not swing round with the player (%.2f m off)" % offset_now.distance_to(offset))
	# Turning it by hand (as Shift + WASDQE does) turns it and it stays turned.
	player._drag_turn = Basis(Vector3.UP, PI * 0.5) * player._drag_turn
	for i in 120:
		await step(1)
	var turned := (now.inverse() * log_piece.global_transform.basis).orthonormalized()
	check(turned.y.dot(rel.y) < 0.3, "turning the held log did not turn it")
	check(turned.y.dot(player._drag_turn.y) > 0.97, "the held log did not settle at the angle it was turned to")
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
	check(PlayerState.owns_tool(&"rusty_axe"), "a new player has no axe")
	check(not PlayerState.owns_tool(&"club_hammer"), "a new player starts with more than an axe")
	check_eq(PlayerState.hotbar_tool(0), &"rusty_axe", "the axe is not in slot 1")
	check(PlayerState.give_tool(&"club_hammer"), "could not give the hammer")
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
## The build ghost is the building itself: every kind of building gives a
## model of meshes only (nothing that collides, spawns or runs), and it is
## shown where the building would go, turned the way it would face.
func test_build_preview() -> void:
	_setup()
	var items_before := manager.active_count()
	var children_before := plot.get_child_count()
	for id in GameData.buildings:
		var def: BuildingDef = GameData.building(id)
		var model := plot.preview_model(def)
		check(model != null, "%s has no preview" % id)
		if model == null:
			continue
		var meshes := 0
		for c in model.get_children():
			if c is MeshInstance3D:
				meshes += 1
			check(not (c is CollisionObject3D), "the %s preview has a body" % id)
		check(meshes > 0, "the %s preview has nothing to see" % id)
		model.free()
	await step(2)
	check_eq(plot.get_child_count(), children_before, "making previews left things on the plot")
	check_eq(manager.active_count(), items_before, "making previews spawned items")
	check(plot.placed.is_empty(), "making previews placed buildings")
	# In build mode the preview stands where the building would go.
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.global_transform = Transform3D(Basis.looking_at(Vector3(0, -1, -0.6).normalized(), Vector3.UP), plot.global_position + Vector3(0, 8, 4))
	var bs := BuildSystem.new()
	world.add_child(bs)
	bs.setup(plot, cam, null)
	bs.refresh_palette()
	bs.index = 0
	bs.active = true
	bs.rotate_axis(1)
	await step(3)
	var def0 := bs.current()
	check(bs._preview != null and bs._preview.visible, "no preview in build mode")
	if bs._preview != null:
		var want := plot.cell_to_world(bs.target_cell, def0.size, bs.rot)
		check(bs._preview.global_position.distance_to(want) < 0.01, "the preview is not where the building would go")
		var facing := bs._preview.global_transform.basis * Vector3.FORWARD
		var placed_facing := plot.global_transform.basis * Plot.orientation_basis(bs.rot) * Vector3.FORWARD
		check(facing.dot(placed_facing) > 0.99, "the preview does not face the way the building would")
	bs.active = false
	bs.free()
	done()

func test_old_save_belts() -> void:
	PlayerState.reset()
	var doc := PlayerState.to_dict()
	doc["unlocked"] = ["conveyor"]
	PlayerState.from_dict(doc)
	for id in [&"conveyor", &"conveyor_ramp"]:
		check(PlayerState.is_unlocked(id), "%s is missing after loading an old save" % id)
	var belts := 0
	for def in PlayerState.available_buildings():
		if def.kind == &"conveyor":
			belts += 1
	check(belts >= 5, "only %d belt pieces in the build bar after an old save" % belts)
	PlayerState.reset()
	done()

## Spec: thin walls. A wall plan starts a quarter metre thick, can be made
## thicker or thinner a quarter at a time, and keeps its thickness through a
## save.
func test_thin_walls() -> void:
	_setup()
	Economy.from_dict({"money": 100000, "day": 1})
	var wall := plot.place(GameData.building(&"schematic_wall"), Vector2i(0, 0), 0)
	check(wall != null, "the wall was not placed")
	await step(1)
	var index := plot.index_at_world(wall.global_position)
	var def: BuildingDef = plot.placed[index].def
	check_near(def.extent().z, 0.25, 0.001, "a new wall is %.2f m thick" % def.extent().z)
	# Made a full metre thick, it stays so through a save.
	check_eq(plot.edit(index, plot.placed[index].cell, Vector3i.ZERO, def.size, 0.0, Vector3i.ZERO), "", "thickening the wall failed")
	var saved := plot.to_dict()
	plot.from_dict(saved)
	await step(1)
	check_near((plot.placed[0].def as BuildingDef).extent().z, 1.0, 0.001, "a 1 m wall came back %.2f m thick" % (plot.placed[0].def as BuildingDef).extent().z)
	# And back to thin.
	check_eq(plot.edit(0, plot.placed[0].cell, Vector3i.ZERO, def.size, 0.0, Vector3i(0, 0, 3)), "", "thinning the wall failed")
	plot.from_dict(plot.to_dict())
	await step(1)
	check_near((plot.placed[0].def as BuildingDef).extent().z, 0.25, 0.001, "a thin wall came back thick")
	done()

## Spec: dragging a building, its knobs go with it, and the drag is still
## measured from where it began.
func test_build_knobs_follow() -> void:
	_setup()
	Economy.from_dict({"money": 100000, "day": 1})
	var player := _make_player()
	world.add_child(player)
	await step(2)
	var bs := BuildSystem.new()
	world.add_child(bs)
	bs.setup(plot, player.camera, player)
	player.global_position = plot.global_position + Vector3(2, 1, 2)
	bs.set_active(true)
	var node := plot.place(GameData.building(&"conveyor"), Vector2i(0, 0) * Plot.SUB, 0)
	await step(2)
	var index := plot.index_at_world(node.global_position)
	bs.select_building(index)
	await step(1)
	var h: Dictionary = bs._gizmo.handles[0]
	var knob_was: Vector3 = (h.node as Node3D).global_position
	var point_was: Vector3 = h.point
	check_eq(plot.edit(index, Vector2i(2, 0) * Plot.SUB, Vector3i.ZERO, Vector3i(1, 1, 4), 0.0), "", "moving the belt failed")
	bs._refresh_gizmo_box()
	await step(1)
	var knob_now: Vector3 = (h.node as Node3D).global_position
	check_near(knob_now.x - knob_was.x, 2.0 * Plot.CELL, 0.01, "the knob did not move with the building")
	check((h.point as Vector3).is_equal_approx(point_was), "the drag's starting point moved")
	bs.set_active(false)
	bs.free()
	done()

func test_build_multiselect() -> void:
	_setup()
	Economy.from_dict({"money": 100000, "day": 1})
	var player := _make_player()
	world.add_child(player)
	await step(2)
	var bs := BuildSystem.new()
	world.add_child(bs)
	bs.setup(plot, player.camera, player)
	bs.set_active(true)
	var a := plot.place(GameData.building(&"conveyor"), Vector2i(0, 0) * Plot.SUB, 0)
	var b := plot.place(GameData.building(&"conveyor"), Vector2i(3, 0) * Plot.SUB, 0)
	var c := plot.place(GameData.building(&"conveyor"), Vector2i(6, 0) * Plot.SUB, 0)
	await step(2)
	bs.select_building(plot.index_at_world(a.global_position))
	bs.multi.append(b)
	bs._refresh_multi()
	check_eq(bs.selection_count(), 2, "two buildings are not selected")
	var b_was: Vector3 = b.global_position
	var c_was: Vector3 = c.global_position
	# Dragging the first along z moves the second the same.
	bs._drag = {"cell": plot.placed[bs.selected].cell, "lift": 0.0, "others": bs._others_start()}
	bs._move_others(Vector2i(0, 2 * Plot.SUB), 0.0)
	bs._drag = {}
	await step(1)
	b = bs.multi[0]
	check_near(b.global_position.z - b_was.z, 2.0 * Plot.CELL, 0.01, "the second building did not move with the first")
	a = plot.placed[bs.selected].node
	check(c.global_position.is_equal_approx(c_was), "a building not selected moved")
	# [G] is the add-to-selection key, on its own - not Shift+F.
	var g := InputEventKey.new()
	g.physical_keycode = KEY_G
	g.pressed = true
	check(Controls.pressed(g, &"add_select"), "G does not add to the selection")
	bs.remove_selected()
	await step(2)
	check(not is_instance_valid(a) or a.is_queued_for_deletion() or a.get_parent() == null, "the first selected building was not removed")
	check(not is_instance_valid(b) or b.is_queued_for_deletion() or b.get_parent() == null, "the second selected building was not removed")
	check(is_instance_valid(c) and c.get_parent() != null, "an unselected building was removed")
	bs.set_active(false)
	bs.free()
	done()

func test_plan_pick() -> void:
	_setup()
	Economy.from_dict({"money": 100000, "day": 1})
	var player := _make_player()
	world.add_child(player)
	await step(2)
	var bs := BuildSystem.new()
	world.add_child(bs)
	bs.setup(plot, player.camera, player)
	var node := plot.place(GameData.building(&"schematic_wall"), Vector2i(0, 0) * Plot.SUB, 0) as Schematic
	await step(2)
	var cap := node.capacity_m3()
	node.accept_item(spawn(&"lumber_oak", Vector3(0, 6, 0), Solid.box(Vector3(0.25, cap * 0.3 / 0.0625, 0.25))))
	await step(2)
	check(not node.solid, "the plan filled up")
	# Stand back and look straight at the middle of it.
	var target := node.global_position + Vector3(0, 1.0, 0)
	player.global_position = target + Vector3(0, -1.0, 6.0)
	await step(2)
	player.camera.global_transform = Transform3D(Basis.looking_at(target - (target + Vector3(0, 0, 6)), Vector3.UP), target + Vector3(0, 0, 6))
	bs.set_active(true)
	await step(1)
	bs.toggle_select()
	check(bs.editing(), "aiming at an unfilled plan did not select it")
	check(bs.plan_hover_text().contains("Oak"), "hovering a plan does not say it is oak: '%s'" % bs.plan_hover_text())
	bs.deselect()
	bs.set_active(false)
	player.global_position = target + Vector3(0, -1.6, 2.5)
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	await step(2)
	player._update_prompt()
	check(player.last_prompt.contains("Oak"), "looking at a plan does not say what it is made of: '%s'" % player.last_prompt)
	bs.free()
	done()

func test_build_territory() -> void:
	_setup()
	var player := _make_player()
	world.add_child(player)
	await step(2)
	var bs := BuildSystem.new()
	world.add_child(bs)
	bs.setup(plot, player.camera, player)
	player.global_position = plot.global_position + Vector3(plot.half_extent + 20.0, 1, 0)
	bs.set_active(true)
	check(not bs.active, "build mode opened off the plot")
	check(bs.last_error != "", "no reason given for refusing build mode")
	player.global_position = plot.global_position + Vector3(2, 1, 2)
	bs.set_active(true)
	check(bs.active, "build mode would not open on the plot")
	bs.set_active(false)
	bs.free()
	done()

## [N] puts a crane back where operator mode starts it and a loader's bucket
## back in its carrying pose.
func test_rig_home() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"crane_truck")
	world.add_child(truck)
	truck.global_position = Vector3(-10, truck.spawn_height(), 0)
	var loader := Hauler.new()
	loader.setup(manager, 0, &"loader")
	world.add_child(loader)
	loader.global_position = Vector3(10, loader.spawn_height(), 0)
	await step(30)
	var r := truck.rig
	r.set_operating(true)
	var start := r.target
	var start_yaw := r.target_yaw
	for i in 60:
		r.drive(Vector3(1, 0.5, -1), 1.0, false, 1.0 / 60.0)
		await step(1)
	check(r.target.distance_to(start) > 0.5, "the crane did not move")
	r.home()
	check(r.target.distance_to(start) < 0.001 and absf(angle_difference(r.target_yaw, start_yaw)) < 0.001, "the crane did not go back to its start")
	var l := loader.loader
	var lift0 := l.lift
	var tilt0 := l.tilt
	for i in 60:
		l.drive(1.0, -1.0, 1.0 / 60.0)
		await step(1)
	check(absf(l.lift - lift0) > 0.2, "the arms did not move")
	l.home()
	for i in 300:
		l.drive(0.0, 0.0, 1.0 / 60.0)
		await step(1)
	check_near(l.lift, lift0, 0.001, "the arms did not go back to their carrying pose")
	check_near(l.tilt, tilt0, 0.001, "the bucket did not go back to its carrying pose")
	done()

func test_build_edit() -> void:
	_setup()
	Economy.from_dict({"money": 100000, "day": 1})
	var belt := plot.place(GameData.building(&"conveyor"), Vector2i(0, 0) * Plot.SUB, 0) as Conveyor
	var mill := plot.place(GameData.building(&"sawmill"), Vector2i(-8, -8) * Plot.SUB, 0)
	check(mill != null, "the mill was not placed")
	await step(2)
	var belt_at := belt.global_position
	var index := plot.index_at_world(belt_at)
	check(index >= 0, "the belt is not on the occupancy grid")
	check_eq(plot.edit(index, Vector2i(3, 0) * Plot.SUB, Vector3i.ZERO, Vector3i(1, 1, 4), 0.0), "", "moving the belt failed")
	await step(2)
	var moved := plot.placed[index].node as Conveyor
	check(plot.index_at_world(moved.global_position) == index, "the moved belt is not where the grid says")
	check_eq(plot.index_at_world(belt_at), -1, "the old cells are still taken")

	# Belts stretch, and stretching is free.
	var money := Economy.money
	check_eq(plot.edit(index, Vector2i(3, 0) * Plot.SUB, Vector3i.ZERO, Vector3i(1, 1, 8), 0.0), "", "stretching the belt failed")
	await step(2)
	var long := plot.placed[index].node as Conveyor
	check_near(long.length, 8.0, 0.001, "the stretched belt is %.1f m" % long.length)
	check_eq(Economy.money, money, "stretching the belt cost money")
	check(Plot.size_limits(GameData.building(&"sawmill")).is_empty(), "a machine can be resized")

	# Turned a quarter, and lifted.
	check_eq(plot.edit(index, Vector2i(3, 0) * Plot.SUB, Vector3i(0, 1, 0), Vector3i(1, 1, 8), 0.5), "", "turning the belt failed")
	await step(2)
	var turned: Node3D = plot.placed[index].node
	check_near(turned.position.y - plot.to_local(plot.cell_to_world(Vector2i(3, 0) * Plot.SUB, Vector3i(1, 1, 8), Vector3i(0, 1, 0))).y,
		0.5, 0.001, "the belt was not lifted")
	# A move off the plot is refused and changes nothing.
	var before: Dictionary = plot.placed[index].duplicate()
	var err := plot.edit(index, Vector2i(9999, 9999) * Plot.SUB, Vector3i(0, 1, 0), Vector3i(1, 1, 8), 0.5)
	check(err != "", "a belt was moved off the plot")
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
		Vector3(0, 0.6, -12 + mill.length * 0.5 - 0.35)), 0, Vector3.ZERO, Solid.with_finish(Solid.cylinder(0.2, 0.2, 1.0), &"sanded"))
	check(not wild_log.owned, "a log dropped on the belt should start unowned")
	wild_log = await _through(mill, wild_log)
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

## Play-test: getting in used to crush the front suspension and send the
## truck backwards - the driver's body, carried in the seat, was colliding
## with the vehicle it sat in. Seated, every wheel stays on the ground and a
## truck left alone stays put.
## Play-test: the road bonus only moved the speedometer. The physics capped
## how fast any body may spin, which held every wheel - and so every
## vehicle - under its rated speed, with the road bonus on top of that.
func test_top_speed() -> void:
	_setup(false)
	var strip := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 2, 1600)
	cs.shape = box
	cs.position = Vector3(0, -1, -700)
	strip.add_child(cs)
	world.add_child(strip)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"quad")
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), 0)
	await step(60)
	truck.autopilot = true
	truck.input_throttle = 1.0
	var top := 0.0
	for i in 600:
		await step(1)
		top = maxf(top, truck.linear_velocity.length())
	check(top > truck.max_speed * 0.9, "the %s topped out at %.1f of %.1f m/s" % [truck.vehicle_id, top, truck.max_speed])
	done()

## Nothing comes into the cab: getting in lets go of what is dragged and sets
## the carry rack down beside you, on the far side from the vehicle.
func test_enter_drops_load() -> void:
	_setup(false)
	var player := _make_player()
	world.add_child(player)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"pickup")
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), 0)
	player.global_position = Vector3(3, 1, 0)
	await step(30)
	var a := spawn(&"ore_iron", player.global_position + Vector3(0, 0.3, -1), Solid.cube(0.002))
	var b := spawn(&"ore_iron", player.global_position + Vector3(0.3, 0.3, -1), Solid.cube(0.002))
	await step(2)
	check(player.pick_up(a) and player.pick_up(b), "could not pick up the test pieces")
	var log_piece := spawn(&"wood_pine", player.global_position + Vector3(0, 0.3, -2), Solid.cylinder(0.1, 0.1, 1.0))
	await step(2)
	player._hold_for_tests = true
	check(player._grab_drag_item(log_piece), "could not take hold of the log")
	var stood := player.global_position
	player.enter_vehicle(truck)
	truck.driver = player
	check(player.held.is_empty(), "the carry rack came into the cab")
	check(player.dragged == null, "the dragged log came into the cab")
	for item in [a, b, log_piece]:
		check_eq((item as LooseItem).state, LooseItem.State.FREE, "a carried piece was not let go")
	for item in [a, b]:
		check((item as LooseItem).global_position.x > stood.x, "a dropped piece went toward the vehicle")
	player.exit_vehicle()
	truck.driver = null
	done()

## Out of the seat, a vehicle comes to rest and is held there: shoved, it
## does not creep or skate. Someone gets in and it drives again.
## Getting out - by the driver's door, as the game does it - leaves every
## vehicle where it stood.
func test_exit_still() -> void:
	_setup(false)
	var player := _make_player()
	world.add_child(player)
	var x := -30.0
	for id in GameData.vehicles:
		if bool(GameData.vehicle(id).get("trailer", false)):
			continue
		var truck := Hauler.new()
		truck.setup(manager, 0, id)
		truck.position = Vector3(x, truck.spawn_height() + 0.2, 20)
		x += 8.0
		world.add_child(truck)
		await step(60)
		player.enter_vehicle(truck)
		truck.driver = player
		for i in 90:
			player.global_position = truck.seat_transform().origin
			await step(1)
		var at := truck.global_position
		player.exit_vehicle()
		truck.driver = null
		player.global_position = truck.global_position \
			+ truck.global_transform.basis.x * (truck.body_size.x * 0.5 + 1.3) + Vector3(0, 1.0, 0)
		var worst := 0.0
		for i in 120:
			await step(1)
			worst = maxf(worst, truck.global_position.distance_to(at))
		check(worst < 0.3, "the %s moved %.2f m when the driver got out" % [id, worst])
		truck.queue_free()
		await step(1)
	done()

## Parked at the top of a 10 m drop, the crane lets the claw right down to the
## ground at the bottom - and not through it.
func test_crane_reaches_down() -> void:
	_setup(false)
	var ledge := StaticBody3D.new()
	ledge.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 10, 16)
	cs.shape = box
	ledge.add_child(cs)
	world.add_child(ledge)
	ledge.global_position = Vector3(0, 5, 0)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"crane_truck")
	world.add_child(truck)
	truck.global_position = Vector3(0, 10.0 + truck.spawn_height(), 0)
	await step(90)
	var rig := truck.rig
	check(float(rig.fk().tip.z) < float(rig.head_offset.z), "the mobile crane's boom does not rest forward")
	rig.set_operating(true)
	check(rig.target.z < rig.head_offset.z, "taking the controls swung the mobile crane's boom round to the back")
	var frame := truck.global_transform
	var out := frame.affine_inverse() * Vector3(9.0, frame.origin.y, 2.0)
	rig.target = rig.clamp_target(Vector3(out.x, rig.head_offset.y, out.z))
	for i in 600:
		await step(1)
		if rig._settled(rig.solve(rig.target, rig.target_yaw), 0.01):
			break
	rig.claw()
	for i in 1500:
		await step(1)
		if rig.claw_state != &"down":
			break
	var low := rig.target.y
	var jaw_y := (truck.global_transform * Vector3(0, low, 0)).y
	check(jaw_y < 1.0, "the claw stopped %.1f m above the ground below the drop" % jaw_y)
	# The reach is a domed cylinder: run all the way out, the hook goes down
	# without the boom coming in.
	var far := rig.max_reach()
	var at_head := rig.clamp_target(Vector3(0, rig.head_offset.y - rig.HANG, far))
	var deep := rig.clamp_target(Vector3(0, rig.head_offset.y - rig.HANG - 12.0, far))
	check_near(Vector2(deep.x, deep.z).length(), Vector2(at_head.x, at_head.z).length(), 0.05,
		"lowering the hook at full reach drew the boom in")
	check_near(float(rig.solve(deep, 0.0).ext), float(rig.solve(at_head, 0.0).ext), 0.05,
		"lowering the hook at full reach shortened the boom")
	check(jaw_y > -0.05, "the claw went through the ground (%.2f)" % jaw_y)
	# Driven down by hand it stops on the ground too.
	for i in 300:
		rig.drive(Vector3(0, -1, 0), 0.0, false, 1.0 / 60.0)
	jaw_y = (truck.global_transform * Vector3(0, rig.target.y, 0)).y
	check(jaw_y > -0.05, "driven down, the claw went into the ground (%.2f)" % jaw_y)
	done()

func test_crane_claw() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"crane_truck")
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), 0)
	await step(60)
	var rig := truck.rig
	rig.set_operating(true)
	var frame := truck.global_transform
	var beside: Vector3 = frame * Vector3(3.6, 0.0, 1.0)
	var log_piece := spawn(&"wood_pine", Vector3(beside.x, 0.3, beside.z), Solid.cylinder(0.2, 0.18, 2.0))
	await step(40)
	# Over the log, well up above it.
	var over := frame.affine_inverse() * log_piece.global_position
	rig.target = rig.clamp_target(Vector3(over.x, over.y + 3.0, over.z))
	for i in 400:
		await step(1)
	var top := rig.target.y
	rig.claw()
	check_eq(rig.claw_state, &"down", "F did not drop the claw")
	for i in 900:
		await step(1)
		if rig.claw_state == &"":
			break
	check_eq(rig.claw_state, &"", "the claw never finished")
	check(rig.held == log_piece, "the claw did not come up with the log")
	check_near(rig.target.y, top, 0.02, "the claw did not come back up to where it started")
	# F lets go; dropped again over bare ground it comes back up empty.
	rig.claw()
	check(rig.held == null, "F did not let the log go")
	await step(60)
	var bare := frame.affine_inverse() * (frame * Vector3(-3.6, 0.0, 1.0))
	rig.target = rig.clamp_target(Vector3(bare.x, top, bare.z))
	for i in 300:
		await step(1)
	rig.claw()
	for i in 900:
		await step(1)
		if rig.claw_state == &"":
			break
	check_eq(rig.claw_state, &"", "the claw never came back from bare ground")
	check(rig.held == null, "the claw came up from bare ground with something")
	done()

func test_parked_holds() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"hauler")
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), 0)
	truck.autopilot = true
	truck.input_throttle = 1.0
	await step(90)
	# Get out at speed: it stops, and is held.
	truck.autopilot = false
	var t := 0
	while not truck.held and t < 600:
		await step(1)
		t += 1
	check(truck.held, "a truck left alone was never held")
	var at := truck.global_position
	var yaw := truck.global_rotation.y
	# A good shove from a loose log does not move it.
	var log_piece := spawn(&"wood_pine", at + Vector3(3, 1.0, 0), Solid.cylinder(0.3, 0.3, 2.0))
	log_piece.linear_velocity = Vector3(-8, 0, 0)
	await step(120)
	check(truck.global_position.distance_to(at) < 0.05, "a held truck moved %.2f m" % truck.global_position.distance_to(at))
	check(absf(truck.global_rotation.y - yaw) < 0.01, "a held truck turned")
	# In the seat again, it drives.
	truck.autopilot = true
	truck.input_throttle = 1.0
	await step(90)
	check(not truck.held, "the truck stayed held with someone driving")
	check(truck.global_position.distance_to(at) > 2.0, "the truck would not drive off after being held")
	done()

func test_bridge_speed() -> void:
	_setup(false)
	var bridge := Bridge.new()
	bridge.setup(Vector3(-20, 0.0, 0), Vector3(20, 0.0, 0), null)
	world.add_child(bridge)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"pickup")
	world.add_child(truck)
	truck.global_position = Vector3(0, bridge.deck_height(0.5) + truck.spawn_height(), 0)
	await step(30)
	check(truck.on_bridge(), "a truck on the deck is not on the bridge")
	check_near(truck.speed_bonus(), Terrain.ROAD_SPEED_BONUS + Balance.num("vehicles.bridge_extra_bonus", 0.10), 0.0001,
		"the bridge bonus is not the road's plus the balance file's extra")
	truck.move_to(Transform3D(Basis(), Vector3(0, 0, 30) + Vector3(0, truck.spawn_height(), 0)))
	await step(5)
	check(not truck.on_bridge(), "a truck off to the side counts as on the bridge")
	check_eq(truck.speed_bonus(), 0.0, "a truck off road and bridge got a bonus")
	done()

func test_bridge_smooth() -> void:
	_setup(false)
	# A long bridge with a proper arch, driven along its length flat out.
	var bridge := Bridge.new()
	bridge.setup(Vector3(0, 0.3, -36), Vector3(0, 0.3, 36), null)
	world.add_child(bridge)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"pickup")
	world.add_child(truck)
	await step(2)
	truck.move_to(Transform3D(Basis(), Vector3(0, bridge.deck_height(0.02) + truck.spawn_height(), -34.5)))
	await step(20)
	truck.autopilot = true
	truck.input_throttle = 1.0
	# The body's vertical kicks: the change in its up-down speed frame to frame.
	var worst := 0.0
	var last_vy := truck.linear_velocity.y
	var airborne := 0
	for i in 240:
		await step(1)
		if not bridge.over_deck(truck.global_position):
			break
		var vy := truck.linear_velocity.y
		if truck.linear_velocity.length() > 8.0:
			worst = maxf(worst, absf(vy - last_vy))
			if truck._grounded == 0:
				airborne += 1
		last_vy = vy
	truck.input_throttle = 0.0
	check(truck.linear_velocity.length() > 8.0, "the truck never got up to speed on the bridge")
	check(worst < 0.35, "the truck was jolted crossing the bridge (%.2f m/s in one frame)" % worst)
	check(airborne < 3, "the truck left the deck %d frames" % airborne)
	done()

func test_seated_driver() -> void:
	_setup(false)
	var player := _make_player()
	world.add_child(player)
	var x := -30.0
	for id in GameData.vehicles:
		# Trailers have no engine and no seat: they are towed, tested elsewhere.
		if bool(GameData.vehicle(id).get("trailer", false)):
			continue
		var truck := Hauler.new()
		truck.setup(manager, 0, id)
		truck.position = Vector3(x, truck.spawn_height() + 0.2, -10)
		x += 8.0
		world.add_child(truck)
		await step(60)
		var start := truck.global_position
		var wheels: int = truck.wheel_offsets.size()
		player.enter_vehicle(truck)
		truck.driver = player
		for i in 150:
			player.global_position = truck.seat_transform().origin
			await step(1)
		check_eq(truck._grounded, wheels, "the %s lifted wheels with a driver in" % id)
		var drift := Vector2(truck.global_position.x - start.x, truck.global_position.z - start.z).length()
		check(drift < 0.5, "the %s rolled %.1f m with a driver sat still" % [id, drift])
		player.exit_vehicle()
		truck.driver = null
		truck.queue_free()
		await step(1)
	await step(3)
	check_eq(player.collision_layer, Layers.PLAYER, "getting out did not make the driver solid again")
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

	# Real wheels: bodies under the chassis, each wearing its tyre.
	var wheels := 0
	for body in truck.wheel_bodies:
		var local := truck.global_transform.affine_inverse() * body.global_position
		if local.y < 0.0 and truck._wheels.any(func(m): return m.get_parent() == body):
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

	# [X] only swings the tailgate: the load stays put.
	check_eq(truck.work_tailgate(), "tailgate down", "[X] did not drop the tailgate")
	await step(120)
	check(truck._tailgate.disabled, "the tailgate is not open")
	check_eq(truck.cargo_count(), 4, "dropping the tailgate pushed the load out")
	check_eq(truck.work_tailgate(), "tailgate up", "[X] again did not shut the tailgate")
	check(not truck._tailgate.disabled, "the tailgate did not shut")

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
	# No carry limit: past its nominal size the bed still takes more.
	truck.cargo_capacity_m3 = 0.001
	check(truck.can_accept(&"lumber_pine"), "the bed refused a piece for being 'full'")
	done()

## Spec from play-testing: the load is loose - it slides forward under hard
## braking, and a truck that goes over dumps it - but it does not weigh the
## truck down on its springs.
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
	check(absf(laden_y - empty_y) < 0.02,
		"the load pressed the truck down on its springs (%.3f empty, %.3f laden)" % [empty_y, laden_y])

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
	# A piece can wedge between the side walls, as a real one would; the
	# load as a whole must fall out.
	check(truck.cargo_count() <= 1, "upside down, %d pieces stayed in the bed" % truck.cargo_count())
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
	var node := plot.place(GameData.building(&"vehicle_pad"), Vector2i(2, 2) * Plot.SUB, 0)
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
	var x := -20
	var row := -20
	for id in GameData.vehicles:
		var pad_def: BuildingDef = null
		for b: BuildingDef in GameData.buildings.values():
			if b.kind == &"pad" and b.vehicle == id:
				pad_def = b
		check(pad_def != null, "no pad spawns the %s" % id)
		if pad_def == null:
			continue
		check(sold.has(String(pad_def.id)), "the store does not sell the %s" % pad_def.display_name)
		check(pad_def.cost > 0, "the %s is free" % id)
		PlayerState.add_copy(pad_def.id)
		# Two rows: ten pads do not fit in one across the plot.
		if x > 16:
			x = -20
			row += 14
		var pad := plot.place(pad_def, Vector2i(x, row) * Plot.SUB, 0) as VehiclePad
		x += 5
		check(pad != null, "could not place the %s: %s" % [pad_def.display_name, plot.placement_error(pad_def, Vector2i(x - 5, row) * Plot.SUB, 0)])
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
		# Trailers have no engine and no seat: they are towed, tested elsewhere.
		if bool(GameData.vehicle(id).get("trailer", false)):
			continue
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
		check((inverse * item.global_position).z > truck.bed_mid_z, "a plank came out somewhere other than the back (%s, truck moved to %s)" % [str((inverse * item.global_position).snapped(Vector3(0.01, 0.01, 0.01))), str(truck.global_position.snapped(Vector3(0.01, 0.01, 0.01)))])
	done()

## Debug setting: with unlimited money on, anything can be bought and nothing
## is taken off you.
## Play-test: a building bought at the store is one copy - built for free,
## and only as many as were bought; each copy keeps its tier, and a higher
## tier is not a lower one too. Plain shapes are free and unlimited.
func test_building_copies() -> void:
	_setup()
	Economy.from_dict({"money": 1000, "day": 1})
	PlayerState.reset()
	var sander := GameData.building(&"sander")
	check(plot.placement_error(sander, Vector2i(-8, -8) * Plot.SUB, 0) != "", "a sander was buildable without buying one")
	PlayerState.add_copy(&"sander")
	var first := plot.place(sander, Vector2i(-8, -8) * Plot.SUB, 0)
	check(first != null, "a bought sander could not be built")
	check_eq(Economy.money, 1000, "building a bought sander cost money")
	check(plot.place(sander, Vector2i(0, -8) * Plot.SUB, 0) == null, "one sander bought, two built")
	check(plot.remove(first), "the sander would not come down")
	check_eq(PlayerState.spare_count(&"sander"), 1, "taking the sander down did not give the copy back")
	check_eq(Economy.money, 1000, "taking a bought sander down paid out money")
	# Tiers are per copy.
	PlayerState.add_copy(&"furnace", 2)
	var palette := PlayerState.available_buildings()
	var t2: BuildingDef = null
	for d in palette:
		if d.id == &"furnace":
			check_eq(d.tier, 2, "a T2 furnace box offered a furnace at T%d" % d.tier)
			t2 = d
	check(t2 != null, "the T2 furnace is not offered to build")
	check(plot.placement_error(GameData.building(&"furnace"), Vector2i(4, -8) * Plot.SUB, 0) != "",
		"a T2 furnace made a T1 furnace buildable")
	var furnace := plot.place(t2, Vector2i(4, -8) * Plot.SUB, 0) as InlineMachine
	check(furnace != null, "the T2 furnace could not be built")
	await step(2)
	if furnace != null:
		check_eq(furnace.level, 2, "the T2 furnace built at T%d" % furnace.level)
	# Shapes: free, as many as you like.
	var block := GameData.building(&"schematic_block")
	for i in 5:
		check(plot.place(block, Vector2i(-12 + i * 2, 6) * Plot.SUB, 0) != null, "shape %d could not be built" % i)
	check_eq(Economy.money, 1000, "shapes cost money")
	# Saved and loaded, the tier and the spare copies survive.
	var saved_plot := plot.to_dict()
	var saved_state := PlayerState.to_dict()
	PlayerState.reset()
	PlayerState.from_dict(saved_state)
	plot.from_dict(saved_plot)
	await step(2)
	check_eq(PlayerState.spare_count(&"sander"), 1, "the spare sander was lost in the save")
	var found := 0
	for m in plot.inline_machines():
		if m.def.id == &"furnace":
			found = m.level
	check_eq(found, 2, "the T2 furnace came back as T%d" % found)
	done()

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

## Spec: the winch and crane are real machines on real lines. The winch drags
## what it is hooked to - up to its rating, where it stalls - or, hooked to
## something fixed, drags the truck. The crane hoists a load on its hook,
## swings it with the boom, stands the truck on outriggers while it works,
## and cannot lift past its rating.
func test_vehicle_rig() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0)
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), 0)
	await step(60)
	var rig := truck.rig
	check(rig != null, "the hauler has no rig")
	check(rig.has_crane(), "the hauler has no crane")
	rig.winch_power_kg = 3000.0
	var ahead := -truck.global_transform.basis.z
	var front := rig.fairlead()

	# The winch drags a log in.
	var log_piece := spawn(&"wood_pine", front + ahead * 9.0 + Vector3(0, 0.2, 0), Solid.cylinder(0.25, 0.25, 2.0))
	await step(20)
	# The aiming ring: green on something in reach, red past the line's end,
	# gone once hooked on.
	var reticle := WinchReticle.new()
	world.add_child(reticle)
	reticle.show_for(rig, {"position": log_piece.global_position, "normal": Vector3.UP})
	check(reticle.visible and reticle.in_reach, "the winch reticle does not show a log in reach as in reach")
	reticle.show_for(rig, {"position": front + ahead * (rig.reach + 4.0), "normal": Vector3.UP})
	check(reticle.visible and not reticle.in_reach, "the winch reticle shows a point past the line's end as in reach")
	check_eq(rig.attach_winch(log_piece, log_piece.global_position), "", "the winch would not hook a log")
	check(rig.anchored and log_piece.owned, "hooking a log did not take it")
	reticle.show_for(rig, {"position": log_piece.global_position, "normal": Vector3.UP})
	check(not reticle.visible, "the winch reticle stays up with the hook already on")
	var start := log_piece.global_position.distance_to(rig.fairlead())
	var stretched := 0.0
	for i in 240:
		rig.reel(1.0 / 60.0)
		await step(1)
		if rig.winch_tension > 0.0:
			stretched = maxf(stretched, rig.anchor_point.distance_to(rig.fairlead()) - rig.line_length)
	# A steel line: pulling the log along, it does not stretch.
	check(stretched < 0.08, "the winch line stretched %.2f m under load" % stretched)
	var now := log_piece.global_position.distance_to(rig.fairlead())
	check(now < start - 3.0, "reeling in moved the log %.1f m" % (start - now))
	check(rig.winch_load_kg() < rig.winch_power_kg, "a light log stalled the winch")
	rig.release_winch()
	check(not rig.anchored, "unhooking left the winch hooked")

	# Past its rating the drum stalls and the load stays put.
	# Laid on the ground along the pull, so it cannot roll in by itself: a
	# log dropped on end topples and rolls, and the winch takes up the slack.
	var lie_at := front + ahead * 8.0 + Vector3(3, 0, 0)
	lie_at.y = 0.55
	var heavy := manager.spawn(&"wood_ironwood", Transform3D(LooseItem.lying_basis(atan2(ahead.x, ahead.z)), lie_at),
		0, Vector3.ZERO, Solid.cylinder(0.5, 0.5, 4.0))
	await step(60)
	rig.winch_power_kg = 100.0
	check_eq(rig.attach_winch(heavy, heavy.global_position), "", "the winch would not hook a heavy log")
	var stood := heavy.global_position
	for i in 180:
		rig.reel(1.0 / 60.0)
		await step(1)
	check(heavy.global_position.distance_to(stood) < 0.6,
		"a %.0f kg winch dragged a %.0f kg log %.1f m" % [rig.winch_power_kg, heavy.mass, heavy.global_position.distance_to(stood)])
	check(rig.winch_stalled(), "an over-rated pull did not stall the winch")
	# Stalled, the line still gives nothing: dragged on harder than the
	# winch is rated for, it neither pays out nor stretches.
	var held := rig.line_length
	var worst := 0.0
	for i in 90:
		heavy.apply_central_force((heavy.global_position - rig.fairlead()).normalized() * heavy.mass * 30.0)
		await step(1)
		worst = maxf(worst, rig.anchor_point.distance_to(rig.fairlead()) - rig.line_length)
	check_near(rig.line_length, held, 0.001, "the stalled winch let line slip out")
	check(worst < 0.1, "the stalled line stretched %.2f m" % worst)
	rig.release_winch()

	# Hooked to something fixed, it drags the truck instead (brakes off).
	rig.winch_power_kg = 6000.0
	truck.autopilot = true
	var post := StaticBody3D.new()
	world.add_child(post)
	var anchor := rig.fairlead() + ahead * 10.0
	check_eq(rig.attach_winch(post, anchor), "", "the winch would not hook a fixed point")
	var truck_start := truck.global_position
	for i in 240:
		rig.reel(1.0 / 60.0)
		await step(1)
	check(truck.global_position.distance_to(truck_start) > 2.0,
		"winching on a fixed point did not pull the truck (%.1f m)" % truck.global_position.distance_to(truck_start))
	rig.release_winch()
	truck.autopilot = false
	check(rig.attach_winch(post, rig.fairlead() + ahead * 40.0) != "", "the winch hooked on 40 m away")
	await step(60)

	# The crane: the player moves the log, and the crane solves its joints to
	# follow.
	rig.crane_power_kg = 1200.0
	rig.set_operating(true)
	check(truck.freeze, "working the crane did not plant the truck")
	var dt := 1.0 / 60.0
	for spot: Vector3 in [Vector3(3.5, -0.5, 2.0), Vector3(-4.0, 0.5, 1.0), Vector3(0.0, 1.5, 5.0)]:
		rig.target = rig.clamp_target(spot)
		for i in 600:
			await step(1)
			if rig._settled(rig.solve(rig.target, rig.target_yaw), 0.003):
				break
		await step(90)
		var jaw: Vector3 = rig.fk().jaw
		check(jaw.distance_to(rig.target) < 0.1, "the crane did not put its jaws on the target (%.2f m off at %s)" % [
			jaw.distance_to(rig.target), str(rig.target)])
	# Keys move the target in straight lines in the truck's frame.
	rig.target = rig.clamp_target(Vector3(3.0, 0.0, 2.0))
	var from_spot := rig.target
	for i in 60:
		rig.drive(Vector3(0, 0, -1), 0.0, false, dt)
	check(from_spot.z - rig.target.z > 1.0, "W did not move the log toward the cab")
	check(absf(rig.target.x - from_spot.x) < 0.05 and absf(rig.target.y - from_spot.y) < 0.05,
		"moving along the truck drifted across it or up")
	# Pushed at the cab or out past the reach, the target stops at the edge
	# and slides along it.
	for i in 900:
		rig.drive(Vector3(-0.4, 0, -1), 0.0, false, dt)
	check(not rig.cab_box.grow(0.3).has_point(rig.target), "the target went into the cab")
	check(rig.at_limit, "pushing at the edge did not show the limit")
	var reach_rel := rig.target + Vector3.UP * VehicleRig.HANG - rig.head_offset
	check(absf(atan2(reach_rel.x, reach_rel.z)) <= VehicleRig.SLEW_ARC + 0.01, "the crane swung through the cab")
	for i in 900:
		rig.drive(Vector3(1, 0, 0.3), 0.0, false, dt)
	reach_rel = rig.target + Vector3.UP * VehicleRig.HANG - rig.head_offset
	check(Vector2(reach_rel.x, reach_rel.z).length() <= rig.max_reach() + 0.01, "the target went past the crane's reach")
	# The line hangs dead straight under the boom tip, even mid-swing.
	rig.target = rig.clamp_target(Vector3(-3.5, 0.0, 3.0))
	for i in 40:
		await step(1)
		var pose := rig.fk()
		var off := Vector2(pose.jaw.x - pose.tip.x, pose.jaw.z - pose.tip.z).length()
		if off > 0.001:
			check(false, "the line swung %.3f m off vertical" % off)
			break
	# Q and E turn it.
	var yaw_was := rig.target_yaw
	for i in 30:
		rig.drive(Vector3.ZERO, 1.0, false, dt)
	check(rig.target_yaw - yaw_was > 0.2, "Q did not turn the log")

	# A log beside the truck: grapple on, lift, over the bed, set down.
	var truck_frame := truck.global_transform
	var beside: Vector3 = truck_frame * Vector3(3.4, 0.0, 1.2)
	var grabbed := spawn(&"wood_pine", Vector3(beside.x, 0.3, beside.z), Solid.cylinder(0.22, 0.2, 2.4))
	await step(40)
	rig.target = rig.clamp_target(truck_frame.affine_inverse() * grabbed.global_position)
	for i in 600:
		await step(1)
		if rig.jaw_world().distance_to(grabbed.global_position) < 0.15:
			break
	check_eq(rig.latch(), "", "the grapple would not close on the log between its jaws")
	check(rig.holding() and grabbed.state == LooseItem.State.CAPTURED, "the crane does not have the log")
	var lift_from := grabbed.global_position.y
	for i in 90:
		rig.drive(Vector3(0, 1, 0), 0.0, false, dt)
		await step(1)
	await step(30)
	check(grabbed.global_position.y > lift_from + 1.0, "lifting raised the log %.2f m" % (grabbed.global_position.y - lift_from))
	rig.target = rig.clamp_target(Vector3(0, truck.bed_floor + truck.wall_height + 1.2, truck.bed_mid_z))
	rig.target_yaw = 0.0
	for i in 600:
		await step(1)
		if rig._settled(rig.solve(rig.target, rig.target_yaw), 0.003):
			break
	await step(30)
	for i in 240:
		rig.drive(Vector3(0, -1, 0), 0.0, false, dt)
		await step(1)
	var in_truck := truck.global_transform.affine_inverse() * grabbed.global_position
	check(in_truck.y > truck.bed_floor, "the log was lowered through the bed (y %.2f, floor %.2f)" % [in_truck.y, truck.bed_floor])
	check(in_truck.y < truck.bed_floor + 0.7, "lowering onto the bed stopped %.2f m above it" % (in_truck.y - truck.bed_floor))
	check(absf(in_truck.x) < truck.bed_half_width and in_truck.z > truck.bed_front and in_truck.z < truck.bed_back,
		"the log is not over the bed: %s" % str(in_truck))
	rig.drop()
	check(not rig.holding() and grabbed.state == LooseItem.State.FREE, "letting go left the log held")
	await step(90)
	in_truck = truck.global_transform.affine_inverse() * grabbed.global_position
	check(absf(in_truck.x) < truck.bed_half_width and in_truck.z > truck.bed_front and in_truck.z < truck.bed_back
		and in_truck.y > truck.bed_floor - 0.05, "the log set down did not stay in the bed: %s" % str(in_truck))
	var squared := truck.global_transform.basis.inverse() * grabbed.global_transform.basis.y
	check(absf(squared.x) < 0.1, "a log set down near square was not squared up (%s)" % str(squared))

	# Too heavy for the crane: the grapple will not take it.
	rig.target = rig.clamp_target(Vector3(-3.4, -0.2, 1.5))
	for i in 600:
		await step(1)
		if rig._settled(rig.solve(rig.target, rig.target_yaw), 0.003):
			break
	var jaw_at := rig.jaw_world()
	rig.crane_power_kg = 150.0
	var too_big := spawn(&"wood_ironwood", Vector3(jaw_at.x, 0.5, jaw_at.z), Solid.cylinder(0.4, 0.4, 2.0))
	await step(40)
	rig.target = rig.clamp_target(truck_frame.affine_inverse() * too_big.global_position)
	for i in 400:
		await step(1)
		if rig.jaw_world().distance_to(too_big.global_position) < 0.2:
			break
	check(rig.latch() != "", "a %.0f kg crane took a %.0f kg log" % [rig.crane_power_kg, too_big.mass])
	check(not rig.holding(), "a refused log is in the grapple")

	# Ore still in the ground: the grapple pulls it out if the crane can.
	rig.crane_power_kg = 1200.0
	var ore_at: Vector3 = truck_frame * Vector3(3.0, 0.0, 4.0)
	var seam_rock := OreRock.new()
	seam_rock.manager = manager
	seam_rock.ore_item = &"ore_iron"
	seam_rock.embed = 0.4
	seam_rock.volume = 0.05
	seam_rock.position = Vector3(ore_at.x, 0.0, ore_at.z)
	world.add_child(seam_rock)
	await step(4)
	check(seam_rock.pull_required() < rig.crane_power_kg, "the test chunk needs %.0f kg" % seam_rock.pull_required())
	rig.target = rig.clamp_target(truck_frame.affine_inverse() * (seam_rock.global_position + Vector3(0, 0.3, 0)))
	for i in 600:
		await step(1)
		if rig._settled(rig.solve(rig.target, rig.target_yaw), 0.003):
			break
	check_eq(rig.latch(), "", "the grapple would not take ore in the ground")
	check(seam_rock.consumed(), "the grapple did not pull the ore out of the ground")
	check(rig.held != null and rig.held.item_id == &"ore_iron", "the freed ore is not in the grapple")
	rig.drop()
	rig.crane_power_kg = 50.0
	var deep_rock := OreRock.new()
	deep_rock.manager = manager
	deep_rock.ore_item = &"ore_iron"
	deep_rock.embed = 0.5
	deep_rock.volume = 0.4
	var stuck_at: Vector3 = truck_frame * Vector3(-3.0, 0.0, 4.0)
	deep_rock.position = Vector3(stuck_at.x, 0.0, stuck_at.z)
	world.add_child(deep_rock)
	await step(4)
	rig.target = rig.clamp_target(truck_frame.affine_inverse() * (deep_rock.global_position + Vector3(0, 0.3, 0)))
	for i in 600:
		await step(1)
		if rig._settled(rig.solve(rig.target, rig.target_yaw), 0.003):
			break
	check(rig.latch() != "", "a %.0f kg crane pulled out ore needing %.0f kg" % [rig.crane_power_kg, deep_rock.pull_required()])
	check(not deep_rock.consumed(), "ore past the crane came out anyway")
	rig.set_operating(false)
	for i in 900:
		await step(1)
		if not rig.folding:
			break
	check(not rig.folding and rig._settled(rig._rest_goals(), 0.06), "the crane did not fold away")
	check(not truck.freeze, "stowing the crane left the truck planted")
	await step(60)

	# The winch on ore in the ground: pulled hard enough, the chunk comes out
	# and stays on the line.
	rig.winch_power_kg = 6000.0
	var front2 := rig.fairlead() - truck.global_transform.basis.z * 8.0
	var seam := OreRock.new()
	seam.manager = manager
	seam.ore_item = &"ore_copper"
	seam.embed = 0.4
	seam.volume = 0.08
	seam.position = Vector3(front2.x, 0.0, front2.z)
	world.add_child(seam)
	await step(4)
	check_eq(rig.attach_winch(seam, seam.global_position + Vector3(0, 0.2, 0)), "", "the winch would not hook ore in the ground")
	# Outriggers lock the truck: reeling on a fixed chunk no longer drags it.
	rig.set_outriggers(true)
	check(truck.freeze, "outriggers down did not lock the truck")
	var locked_at := truck.global_position
	for i in 300:
		rig.reel(1.0 / 60.0)
		await step(1)
	check(seam.consumed(), "winching did not pull the ore out (pull %.0f of %.0f kg)" % [rig.winch_load_kg(), seam.pull_required()])
	check(rig.anchor_body is LooseItem, "the freed ore is not on the winch line")
	check(truck.global_position.distance_to(locked_at) < 0.05, "a truck on its outriggers moved")
	rig.release_winch()
	rig.set_outriggers(false)
	check(not truck.freeze, "outriggers up left the truck locked")
	# Jerked: a line snatched tight past the chunk's pull frees it, whatever
	# the winch's own rating.
	var jerk := OreRock.new()
	jerk.manager = manager
	jerk.ore_item = &"ore_tin"
	jerk.embed = 0.4
	jerk.volume = 0.08
	var spot := rig.fairlead() - truck.global_transform.basis.z * 6.0
	jerk.position = Vector3(spot.x, 0.0, spot.z)
	world.add_child(jerk)
	await step(4)
	check_eq(rig.attach_winch(jerk, jerk.global_position + Vector3(0, 0.2, 0)), "", "the winch would not hook the chunk to jerk")
	# Rated under what the chunk needs, but the line holds more than the
	# drum pulls: backed away hard, the truck snatches it out.
	rig.winch_power_kg = jerk.pull_required() * 0.9
	truck.autopilot = true
	truck.input_throttle = -1.0
	for i in 240:
		await step(1)
		if jerk.consumed():
			break
	truck.input_throttle = 0.0
	truck.autopilot = false
	check(jerk.consumed(), "a line snatched tight (%.0f kg) did not jerk out a chunk needing %.0f kg" % [rig.winch_load_kg(), jerk.pull_required()])
	rig.release_winch()
	done()

## Spec: with someone in the seat, the load settled in the bed is part of the
## truck exactly as it lies - driven hard, nothing in it moves - and it comes
## loose again when the driver gets out.
func test_load_fixed_while_driven() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0)
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), 0)
	await step(40)
	for i in 3:
		truck.load_item(&"wood_pine", Solid.cylinder(0.2, 0.18, 2.4))
		await step(20)
	await step(120)
	var aboard := truck.cargo_count()
	check(aboard >= 3, "the test load did not go in the bed (%d)" % aboard)
	var mass_empty := truck.mass
	check_eq(truck.fixed_count(), 0, "the load was fixed with nobody in the seat")
	var driver := Node3D.new()
	world.add_child(driver)
	truck.driver = driver
	await step(60)
	check_eq(truck.fixed_count(), aboard, "the settled load was not fixed when a driver got in")
	# Its shape is the truck's; its weight is not (loads never weigh a truck down).
	check_near(truck.mass, mass_empty, 0.5, "fixing the load changed the truck's weight")
	var was := {}
	for item in truck.cargo_list():
		was[item] = truck.global_transform.affine_inverse() * item.global_transform
		check(item.get_parent() == truck and item.state == LooseItem.State.CAPTURED, "a fixed piece is still a loose body")
	# Flat out and hard over, then a hard stop.
	Input.action_press("move_forward")
	Input.action_press("move_right")
	await step(180)
	Input.action_release("move_forward")
	Input.action_release("move_right")
	Input.action_press("jump")
	await step(60)
	Input.action_release("jump")
	check(truck.linear_velocity.length() < 30.0, "sanity")
	for item: LooseItem in was:
		var now := truck.global_transform.affine_inverse() * item.global_transform
		check(now.origin.distance_to((was[item] as Transform3D).origin) < 0.001, "a fixed piece shifted in the bed")
	check_eq(truck.cargo_count(), aboard, "driving hard lost a piece of the fixed load")
	truck.driver = null
	await step(3)
	check_eq(truck.fixed_count(), 0, "getting out did not let the load loose")
	check_near(truck.mass, mass_empty, 0.5, "the load's weight stayed on the truck")
	for item: LooseItem in was:
		check(item.state == LooseItem.State.FREE and item.get_parent() == manager, "a released piece is not a loose body again")
	await step(30)
	check_eq(truck.cargo_count(), aboard, "the released load is not in the bed")
	done()

## Spec: trucks with a hitch tow trailers. A trailer is hooked on at the
## ball, follows the truck round corners by itself, brakes when it brakes,
## stays upright, and stands on its leg once let go.
func test_door_plans() -> void:
	for id in [&"schematic_door", &"schematic_garage"]:
		_setup()
		var def := GameData.building(id)
		check(def != null, "no %s" % id)
		var door := plot.place(def, Vector2i(0, 0), Vector3i.ZERO, false) as Schematic
		await step(2)
		check(door.is_door(), "%s is not a door" % id)
		var piece := spawn(&"wood_pine", door.global_position + Vector3(0, 4, 0), Solid.cube(door.capacity_m3() + 0.01))
		await step(1)
		check(door.accept_item(piece) and door.solid, "%s did not fill" % id)
		await step(3)
		var space := world.get_world_3d().direct_space_state
		# Straight through the doorway, at waist height.
		var mid := door.global_position + Vector3(0, 1.0, 0)
		var through := func() -> bool:
			var q := PhysicsRayQueryParameters3D.create(mid + door.global_transform.basis.z * 2.0, mid - door.global_transform.basis.z * 2.0, Layers.MACHINE)
			return not space.intersect_ray(q).is_empty()
		check(through.call(), "a shut %s lets you through" % id)
		check(door.toggle_door() != "", "%s would not open" % id)
		await step(60)
		check(not through.call(), "an open %s is still in the way" % id)
		var saved := door.to_dict()
		check(bool(saved.get("open", false)), "the open %s is not saved open" % id)
		door.toggle_door()
		await step(60)
		check(through.call(), "a %s shut again lets you through" % id)
	done()

func test_ramp_plan() -> void:
	_setup()
	var def := GameData.building(&"schematic_ramp")
	check(def != null and def.shape == &"wedge", "no ramp plan")
	var ramp := plot.place(def, Vector2i(0, 0), Vector3i.ZERO, false) as Schematic
	await step(2)
	var e := def.extent()
	check(is_equal_approx(ramp.capacity_m3(), e.x * e.y * e.z * Schematic.MATERIAL_SHARE * 0.5), "a ramp takes a box's worth")
	var piece := spawn(&"wood_pine", ramp.global_position + Vector3(0, 3, 0), Solid.cube(ramp.capacity_m3() + 0.01))
	await step(2)
	check(piece != null and ramp.accept_item(piece), "the ramp would not take wood")
	check(ramp.solid, "the ramp is not solid when full")
	await step(3)
	var space := world.get_world_3d().direct_space_state
	var heights := []
	for dz in [-e.z * 0.4, e.z * 0.4]:
		var top: Vector3 = ramp.global_position + ramp.global_transform.basis.z * dz + Vector3(0, 5, 0)
		var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 10.0, Layers.MACHINE)
		var hit := space.intersect_ray(q)
		heights.append(float(hit.position.y) if not hit.is_empty() else -99.0)
	check(heights[0] > heights[1] + 0.3, "the ramp is not high at its front (%.2f vs %.2f)" % heights)
	done()

func test_fine_scaling() -> void:
	_setup()
	var schem: BuildingDef = null
	for d: BuildingDef in GameData.buildings.values():
		if d.kind == &"schematic" and not d.hidden:
			schem = d
			break
	check(schem != null and Plot.fine_scalable(schem), "no plan to size")
	var node := plot.place(schem, Vector2i(0, 0), Vector3i.ZERO, false) as Schematic
	await step(2)
	var index := plot.placed.size() - 1
	# 1.75 m wide: two cells, one fine step short.
	check_eq(plot.edit(index, Vector2i(0, 0), Vector3i.ZERO, Vector3i(2, 1, 1), 0.0, Vector3i(1, 0, 0)), "", "fine resize refused")
	await step(2)
	var def: BuildingDef = plot.placed[index].def
	check(is_equal_approx(def.extent().x, 2.0 - Plot.SNAP), "the plan is %.2f m wide, not %.2f" % [def.extent().x, 2.0 - Plot.SNAP])
	var saved := plot.to_dict()
	plot.from_dict(saved)
	await step(2)
	var back: BuildingDef = plot.placed[plot.placed.size() - 1].def
	check_eq(back.trim, Vector3i(1, 0, 0), "the fine size did not come back from the save")
	# A belt too.
	var belt := plot.place(GameData.building(&"conveyor"), Vector2i(0, 16), Vector3i.ZERO, false) as Conveyor
	await step(2)
	var bi := plot.placed.size() - 1
	check_eq(plot.edit(bi, Vector2i(0, 16), Vector3i.ZERO, Vector3i(1, 1, 4), 0.0, Vector3i(0, 0, 2)), "", "belt resize refused")
	await step(2)
	var nb := plot.placed[bi].node as Conveyor
	check(nb != null and is_equal_approx(nb.length, 4.0 - 2.0 * Plot.SNAP), "the belt is %.2f m long" % (nb.length if nb != null else -1.0))
	done()

func test_loader_pad_attachment() -> void:
	_setup()
	plot.vehicle_host = world
	var def := GameData.building(&"loader_pad") if GameData.building(&"loader_pad") != null else null
	if def == null:
		for d: BuildingDef in GameData.buildings.values():
			if d.vehicle == &"loader":
				def = d
	check(def != null, "no pad makes a loader")
	if def == null:
		done()
		return
	var pad := plot.place(def, Vector2i(2, 2) * Plot.SUB, 0, false) as VehiclePad
	await step(3)
	check(pad.is_loader_pad(), "the loader's pad does not know it is one")
	var first := pad.spawn() as Hauler
	await step(3)
	check_eq(first.loader.attachment, &"bucket", "first loader")
	check(pad.cycle_attachment() != "", "changing the attachment said nothing")
	check_eq(first.loader.attachment, &"bucket", "the loader out in the world changed without a respawn")
	var second := pad.spawn() as Hauler
	await step(3)
	check_eq(second.loader.attachment, &"grapple", "respawned loader")
	var saved := pad.to_dict()
	check_eq(String(saved.get("attachment", "")), "grapple", "the pad's choice is not saved")
	# Paint: the next one off the pad comes in the colour chosen.
	pad.paint = Color(0.08, 0.58, 0.60)
	var third := pad.spawn() as Hauler
	await step(3)
	check(third.paint.is_equal_approx(Color(0.08, 0.58, 0.60)), "the respawned loader is not painted teal")
	var back := VehiclePad.new()
	back.from_dict(pad.to_dict())
	check(back.paint.is_equal_approx(pad.paint), "the pad's paint is not saved")
	back.free()
	done()

func _block(at: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	world.add_child(b)
	b.global_position = at
	return b

func test_step_up() -> void:
	for h in [0.3, 1.2]:
		_setup(false)
		var p := _make_player()
		world.add_child(p)
		p.global_position = Vector3(0, 0.1, 0)
		_block(Vector3(0, h * 0.5, -3.0), Vector3(6, h, 2))
		await step(10)
		p.input.remote = true
		p.input.apply({"a": ["move_forward"], "k": [], "b": []})
		var top := 0.0
		for i in 90:
			await get_tree().physics_frame
			top = maxf(top, p.global_position.y)
		if h < 0.5:
			check(top > h - 0.05, "the player did not step up %.1f m (top y=%.2f)" % [h, top])
		else:
			check(p.global_position.y < 0.3 and p.global_position.z > -2.2, "the player climbed a %.1f m wall (y=%.2f)" % [h, p.global_position.y])
		p.queue_free()
	done()

func test_throw() -> void:
	_setup()
	var p := _make_player()
	world.add_child(p)
	await step(3)
	var log_piece := spawn(&"wood_pine", p.global_position + Vector3(0, 0.5, -1.5), Solid.cylinder(0.08, 0.08, 0.8))
	await step(2)
	p.held.append(log_piece)
	log_piece.set_state(LooseItem.State.HELD)
	var from := p.global_position
	check(p.throw_one(), "nothing was thrown")
	await step(40)
	check(p.held.is_empty(), "the piece is still on the rack")
	check(log_piece.state == LooseItem.State.FREE, "the thrown piece is not loose")
	var flat := Vector2(log_piece.global_position.x - from.x, log_piece.global_position.z - from.z).length()
	check(flat > 3.0, "the piece only went %.1f m" % flat)
	p.queue_free()
	done()

func test_crane_lifts_vehicle() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"crane_truck")
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), 0)
	var quad := Hauler.new()
	quad.setup(manager, 0, &"quad")
	world.add_child(quad)
	await step(2)
	quad.global_position = truck.global_transform * Vector3(4.5, 0, 0) + Vector3(0, quad.spawn_height(), 0)
	await step(90)
	var rig := truck.rig
	rig.set_operating(true)
	await step(10)
	var roof := quad.global_position + Vector3(0, quad.body_size.y * 0.5 + 0.2, 0)
	rig.target = rig.clamp_target(truck.global_transform.affine_inverse() * roof)
	for i in 900:
		await step(1)
		if rig.jaw_world().distance_to(roof) < 0.4:
			break
	check(rig.jaw_world().distance_to(roof) < 1.0, "the crane could not reach the quad (%.1f m off)" % rig.jaw_world().distance_to(roof))
	check_eq(rig.latch(), "", "the grapple would not take the quad")
	check(rig.held_vehicle == quad, "the crane is not holding the quad")
	var low := quad.global_position.y
	rig.target += Vector3(0, 2.0, 0)
	await step(180)
	check(quad.global_position.y > low + 1.0, "the quad did not go up with the crane (%.2f m)" % (quad.global_position.y - low))
	rig.drop()
	await step(120)
	check(not quad.crane_carried, "the quad is still hung up after letting go")
	check(quad.global_position.y < low + 0.6, "the quad did not come back down")
	# Its own trailer, or a truck with someone in it, is not for lifting.
	var trailer := Hauler.new()
	trailer.setup(manager, 0, &"trailer")
	world.add_child(trailer)
	await step(2)
	truck.towing = trailer
	check(not rig.can_lift_vehicle(trailer), "the crane may lift its own trailer")
	truck.towing = null
	quad.driver = Node3D.new()
	check(not rig.can_lift_vehicle(quad), "the crane may lift a vehicle with a driver in it")
	quad.driver.free()
	quad.driver = null
	done()

func test_dirtbike() -> void:
	_setup(false)
	var bike := Hauler.new()
	bike.setup(manager, 0, &"dirtbike")
	world.add_child(bike)
	bike.global_position = Vector3(0, bike.spawn_height(), 0)
	await step(90)
	check(bike.bike and bike.wheel_bodies.size() == 2, "the dirt bike is not on two wheels")
	check(bike.global_transform.basis.y.dot(Vector3.UP) > 0.95, "the dirt bike fell over standing still")
	var from := bike.global_position
	bike.autopilot = true
	bike.input_throttle = 1.0
	await step(70)
	bike.input_throttle = 0.4
	check(bike.global_transform.basis.y.dot(Vector3.UP) > 0.9, "the dirt bike fell over riding")
	check(bike.global_position.distance_to(from) > 8.0, "the dirt bike did not go (%.1f m)" % bike.global_position.distance_to(from))
	bike.input_steer = 1.0
	await step(45)
	var lean := bike.global_transform.basis.x.dot(Vector3.UP)
	check(bike.global_transform.basis.y.dot(Vector3.UP) > 0.8, "the dirt bike went down in the turn")
	check(absf(lean) > 0.05, "the dirt bike does not lean into a turn (%.2f)" % lean)
	done()

func test_cab_ladder() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"hauler")
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), 0)
	await step(90)
	var ladder := truck.get_node_or_null("Ladder") as Ladder
	check(ladder != null, "the hauler has no ladder")
	if ladder == null:
		done()
		return
	var p := _make_player()
	world.add_child(p)
	var foot := ladder.global_position + truck.global_transform.basis.x * -0.2
	p.global_position = Vector3(foot.x, 0.1, foot.z)
	p.rotation.y = truck.rotation.y - PI * 0.5
	await step(5)
	p.input.remote = true
	p.input.apply({"a": ["move_forward"], "k": [], "b": []})
	var top := 0.0
	var roof := truck.global_position.y + truck.body_size.y * 0.5
	for i in 300:
		await get_tree().physics_frame
		top = maxf(top, p.global_position.y)
		# Up and standing on something: stop there, rather than walk on
		# across the roof and off the far side.
		if p.global_position.y > roof + 0.5 and p.is_on_floor() and p._ladder_here() == null:
			break
	check(top > roof + 0.5, "the ladder did not take the player up (top %.2f, deck %.2f)" % [top, roof])
	p.input.apply({"a": [], "k": [], "b": []})
	await step(60)
	check(p.global_position.y > roof, "the player did not end up on the truck (y %.2f)" % p.global_position.y)
	p.queue_free()
	done()

func test_handbrake_slide() -> void:
	# The same stop twice: tyres that let go under the brake carry the truck
	# further than tyres that do not.
	var runs := []
	for grip in [1.0, Hauler.HANDBRAKE_REAR]:
		_setup(false)
		var saved_rear := Hauler.HANDBRAKE_REAR
		var saved_front := Hauler.HANDBRAKE_FRONT
		Hauler.HANDBRAKE_REAR = grip
		Hauler.HANDBRAKE_FRONT = 1.0 if grip >= 1.0 else saved_front
		var truck := Hauler.new()
		truck.setup(manager, 0, &"pickup")
		world.add_child(truck)
		truck.global_position = Vector3(0, truck.spawn_height(), 0)
		await step(60)
		truck.autopilot = true
		truck.input_throttle = 1.0
		await step(130)
		var at := truck.global_position
		check(truck.linear_velocity.length() > 6.0, "the truck is not going fast enough to brake from (%.1f m/s)" % truck.linear_velocity.length())
		truck.input_throttle = 0.0
		truck.input_brake = true
		await step(240)
		runs.append(truck.global_position.distance_to(at))
		check(grip >= 1.0 or truck._skidding == false or truck.linear_velocity.length() < 2.5, "still skidding at a stop")
		Hauler.HANDBRAKE_REAR = saved_rear
		Hauler.HANDBRAKE_FRONT = saved_front
	check(runs[1] > runs[0] * 1.1, "the brake does not slide (%.1f m vs %.1f m)" % [runs[1], runs[0]])
	done()

func test_vehicles_collide() -> void:
	_setup(false)
	var a := Hauler.new()
	a.setup(manager, 0, &"pickup")
	world.add_child(a)
	a.global_position = Vector3(0, a.spawn_height(), 0)
	var b := Hauler.new()
	b.setup(manager, 0, &"dump_truck")
	world.add_child(b)
	await step(2)
	var ahead := -a.global_transform.basis.z
	b.global_position = Vector3(0, b.spawn_height(), 0) + ahead * 10.0
	await step(60)
	a.autopilot = true
	a.input_throttle = 1.0
	await step(300)
	a.input_throttle = 0.0
	var gap := (b.global_position - a.global_position).dot(ahead)
	var touch := (a.body_size.z + b.body_size.z) * 0.5
	check(gap > touch * 0.8, "the pickup drove through the dump truck (gap %.1f m, touching at %.1f)" % [gap, touch])
	done()

func test_low_loader() -> void:
	_setup(false)
	var deck := Hauler.new()
	deck.setup(manager, 0, &"low_loader")
	world.add_child(deck)
	deck.global_position = Vector3(0, deck.spawn_height(), 0)
	var digger := Hauler.new()
	digger.setup(manager, 0, &"loader")
	world.add_child(digger)
	digger.global_position = Vector3(0, digger.spawn_height(), deck.bed_back + Hauler.RAMP_LENGTH + 4.0)
	await step(90)
	check(deck.bed_kind == &"deck" and not deck.has_bed(), "the low-loader is not a bare deck")
	check(not deck.ramps_down, "the ramps start down")
	deck.toggle_ramps()
	await step(60)
	# Pressed again while they swing, they stop where they are.
	deck.toggle_ramps()
	var held_at := deck.ramp_pose
	check(held_at > 0.05 and held_at < 0.95, "the ramps did not stop part way (%.2f)" % held_at)
	await step(30)
	check_near(deck.ramp_pose, held_at, 0.001, "the ramps did not stay where they were stopped")
	deck.toggle_ramps()
	await step(200)
	check(deck.ramps_down and deck.ramp_pose < 0.01, "the ramps did not come all the way down (%.2f)" % deck.ramp_pose)
	digger.loader.lift = digger.loader.lift_min + 0.3
	await step(20)
	# Up the ramps and on until it is over the middle of the deck.
	digger.autopilot = true
	var aboard := false
	for i in 900:
		var local := deck.to_local(digger.global_position)
		digger.input_throttle = 0.5 if local.z > deck.bed_mid_z + 0.4 else 0.0
		digger.input_brake = local.z <= deck.bed_mid_z + 0.4
		if digger.input_brake and digger.linear_velocity.length() < 0.3:
			aboard = true
			break
		await step(1)
	var on := deck.to_local(digger.global_position)
	check(aboard, "the loader never got over the deck (%.1f m back)" % on.z)
	check(on.y > deck.bed_floor + 0.3, "the loader is not up on the deck (%.2f m)" % on.y)
	deck.toggle_ramps()
	await step(200)
	check(not deck.ramps_down, "the ramps did not go up")
	digger.input_throttle = 0.0
	digger.input_brake = true
	digger.autopilot = false
	# Hitched behind the log truck and towed off, it stays aboard.
	var truck := Hauler.new()
	truck.setup(manager, 0, &"log_truck")
	world.add_child(truck)
	var ahead := deck.tongue_point() - Vector3(0, 0, truck.hitch_offset.z + 0.5)
	truck.global_position = Vector3(ahead.x, truck.spawn_height(), ahead.z)
	await step(60)
	check_eq(truck.hitch(deck), "", "the truck would not hitch the low-loader")
	await step(30)
	truck.autopilot = true
	truck.input_throttle = 0.6
	await step(30)
	check(digger.carried_on == deck, "the loader is not locked to the deck while it is towed")
	await step(90)
	truck.input_steer = 0.6
	await step(60)
	truck.input_steer = 0.0
	truck.input_throttle = 0.0
	truck.input_brake = true
	await step(120)
	var moved := Vector2(deck.global_position.x, deck.global_position.z).length()
	var still := deck.to_local(digger.global_position)
	check(moved > 8.0, "the low-loader was not towed (%.1f m)" % moved)
	check(still.y > deck.bed_floor + 0.3 and absf(still.z - deck.bed_mid_z) < 1.5 and absf(still.x) < 1.0,
		"the loader fell off or slid on the deck (%.1f, %.1f, %.1f)" % [still.x, still.y, still.z])
	done()

func test_chase_camera_clear() -> void:
	_setup(false)
	var player := _make_player()
	world.add_child(player)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"log_truck")
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), 0)
	var trailer := Hauler.new()
	trailer.setup(manager, 0, &"log_trailer")
	world.add_child(trailer)
	await step(2)
	var at := truck.hitch_point() - trailer.tongue_offset + Vector3(0, 0, 0.3)
	trailer.global_position = Vector3(at.x, trailer.spawn_height(), at.z)
	await step(40)
	truck.hitch(trailer)
	# A tall log on the bed, right where the camera looks from.
	manager.spawn(&"wood_pine", Transform3D(trailer.global_transform.basis * LooseItem.lying_basis(0.0),
		trailer.global_transform * Vector3(0, trailer.bed_floor + 0.8, trailer.bed_front + 3.0)), 0, Vector3.ZERO, Solid.cylinder(0.5, 0.45, 5.0), true)
	await step(30)
	player.enter_vehicle(truck)
	truck.driver = player
	for i in 90:
		player.global_position = truck.seat_transform().origin
		await step(1)
	var want := float(truck.get("camera_distance")) if truck.get("camera_distance") != null else player.chase_distance
	check(trailer.cargo_count() >= 1, "the log is not on the trailer")
	check(player._cam_distance > want * 0.9, "the camera was pulled in to %.1f m (of %.1f) by its own truck" % [player._cam_distance, want])
	# The mouse wheel brings it in and takes it back out.
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	for i in 6:
		player._unhandled_input(wheel)
	for i in 30:
		player.global_position = truck.seat_transform().origin
		await step(1)
	check(player._cam_distance < want * 0.6, "the wheel did not zoom the driving camera in (%.1f m of %.1f)" % [player._cam_distance, want])
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	for i in 12:
		player._unhandled_input(wheel)
	for i in 120:
		player.global_position = truck.seat_transform().origin
		await step(1)
	check(player._cam_distance > want * 1.1, "the wheel did not zoom the driving camera out (%.1f m of %.1f)" % [player._cam_distance, want])
	player.exit_vehicle()
	done()

func test_trailer_train() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"hauler")
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), -10.0)
	var first := Hauler.new()
	first.setup(manager, 0, &"trailer")
	world.add_child(first)
	var second := Hauler.new()
	second.setup(manager, 0, &"trailer")
	world.add_child(second)
	var deck := Hauler.new()
	deck.setup(manager, 0, &"low_loader")
	world.add_child(deck)
	await step(2)
	check(first.has_hitch() and not deck.has_hitch(), "trailers should have hitches, the low-loader not")
	deck.queue_free()
	var at := truck.hitch_point() - first.tongue_offset + Vector3(0, 0, 0.3)
	first.global_position = Vector3(at.x, first.spawn_height(), at.z)
	await step(30)
	check_eq(truck.hitch(first), "", "the truck would not take the first trailer")
	await step(20)
	var at2 := first.hitch_point() - second.tongue_offset + Vector3(0, 0, 0.3)
	second.global_position = Vector3(at2.x, second.spawn_height(), at2.z)
	await step(30)
	check_eq(first.hitch(second), "", "the trailer would not take a second trailer")
	check(second.lead() == truck, "the second trailer does not know who pulls it")
	truck.autopilot = true
	truck.input_throttle = 0.7
	await step(180)
	truck.input_throttle = 0.0
	truck.input_brake = true
	await step(120)
	check(second.global_position.z < -12.0, "the second trailer was not pulled along (z %.1f, first %.1f, truck %.1f)" % [second.global_position.z, first.global_position.z, truck.global_position.z])
	check(second.tongue_point().distance_to(first.hitch_point()) < 0.3, "the second trailer came off")
	# Knocked on its side, recovering the truck rights the trailers too.
	second.move_to(Transform3D(Basis(Vector3.FORWARD, 1.5) * second.global_transform.basis, second.global_position + Vector3(0, 0.5, 0)))
	await step(10)
	truck.recover()
	await step(60)
	check(second.global_transform.basis.y.dot(Vector3.UP) > 0.95, "recovering left the trailer on its side")
	check(second.tongue_point().distance_to(first.hitch_point()) < 0.3, "recovering took the trailer off the hitch")
	done()

func test_trailers() -> void:
	for pair in [[&"hauler", &"trailer"], [&"log_truck", &"log_trailer"], [&"dump_truck", &"dump_trailer"],
			[&"pickup", &"trailer"], [&"pickup", &"mower_trailer"]]:
		_setup(false)
		var truck := Hauler.new()
		truck.setup(manager, 0, pair[0])
		world.add_child(truck)
		truck.global_position = Vector3(0, truck.spawn_height(), 0)
		var trailer := Hauler.new()
		trailer.setup(manager, 0, pair[1])
		world.add_child(trailer)
		await step(2)
		# Parked just behind, its coupling a little way off the ball.
		var behind := truck.hitch_point() + Vector3(0.4, 0, 1.0) - trailer.tongue_offset
		trailer.global_position = Vector3(behind.x, trailer.spawn_height(), behind.z)
		await step(90)
		check(trailer.is_trailer and not trailer.is_seat_point(trailer.global_position), "a %s has a seat" % pair[1])
		# Standing alone, it is on its leg: level-ish, not nose-down in the dirt.
		check(absf(trailer.global_transform.basis.z.y) < 0.25, "the unhitched %s is not standing on its leg" % pair[1])
		check_eq(truck.hitch(trailer), "", "the %s would not hitch the %s" % pair)
		check(truck.towing == trailer and trailer.towed_by == truck, "the hitch did not join them")
		await step(30)
		check(trailer.tongue_point().distance_to(truck.hitch_point()) < 0.15, "the coupling is not on the ball")
		# Drive off, then round a bend.
		truck.autopilot = true
		truck.input_throttle = 1.0
		await step(150)
		truck.input_steer = 1.0
		await step(150)
		truck.input_steer = 0.0
		await step(60)
		var moved := Vector2(trailer.global_position.x, trailer.global_position.z).length()
		check(moved > 15.0, "the %s was not towed (moved %.1f m)" % [pair[1], moved])
		check(trailer.tongue_point().distance_to(truck.hitch_point()) < 0.3,
			"the %s came off the hitch (%.2f m)" % [pair[1], trailer.tongue_point().distance_to(truck.hitch_point())])
		check(trailer.global_transform.basis.y.dot(Vector3.UP) > 0.8, "the %s rolled over" % pair[1])
		# Braking: it stops with the truck, still hitched.
		truck.input_throttle = 0.0
		truck.input_brake = true
		await step(180)
		check(trailer.linear_velocity.length() < 1.0, "the %s did not stop with the truck" % pair[1])
		check(trailer.tongue_point().distance_to(truck.hitch_point()) < 0.3, "braking pulled the %s off" % pair[1])
		truck.autopilot = false
		var let_go := truck.unhitch()
		check(let_go == trailer and truck.towing == null and trailer.towed_by == null, "unhitching left them joined")
		await step(90)
		check(trailer.parked() and absf(trailer.global_transform.basis.z.y) < 0.25,
			"the let-go %s is not standing on its leg" % pair[1])
	done()

## The pickup pulls the utility trailer and anything lighter; the logging and
## dump trailers and the low-loader are too heavy for it, and it says so. A
## trailer hitched on the back of the pickup's trailer counts the same.
## Bigger trucks pull anything.
func test_pickup_tow_limit() -> void:
	for id in [&"trailer", &"mower_trailer", &"log_trailer", &"dump_trailer", &"low_loader"]:
		_setup(false)
		var truck := Hauler.new()
		truck.setup(manager, 0, &"pickup")
		world.add_child(truck)
		truck.global_position = Vector3(0, truck.spawn_height(), 0)
		var trailer := Hauler.new()
		trailer.setup(manager, 0, id)
		world.add_child(trailer)
		await step(2)
		var behind := truck.hitch_point() + Vector3(0.2, 0, 0.6) - trailer.tongue_offset
		trailer.global_position = Vector3(behind.x, trailer.spawn_height(), behind.z)
		await step(60)
		var said := truck.hitch(trailer)
		var light := float(GameData.vehicle(id).get("mass", 0)) <= 400.0
		if light:
			check_eq(said, "", "the pickup would not pull the %s" % id)
			check(truck.towing == trailer, "the pickup is not towing the %s" % id)
		else:
			check(said.contains("too heavy for the pickup") and said.contains("utility trailer"),
				"the pickup took on the %s (said '%s')" % [id, said])
			check(truck.towing == null and trailer.towed_by == null, "the %s was hitched to the pickup anyway" % id)
	# A heavy trailer on the back of the pickup's own trailer is refused too.
	_setup(false)
	var pickup := Hauler.new()
	pickup.setup(manager, 0, &"pickup")
	world.add_child(pickup)
	pickup.global_position = Vector3(0, pickup.spawn_height(), 0)
	var mower := Hauler.new()
	mower.setup(manager, 0, &"mower_trailer")
	world.add_child(mower)
	var dump := Hauler.new()
	dump.setup(manager, 0, &"dump_trailer")
	world.add_child(dump)
	await step(2)
	# Light enough to roll: set down just behind, and hitched as soon as it
	# has settled.
	var at := pickup.hitch_point() + Vector3(0, 0, 0.4) - mower.tongue_offset
	mower.global_position = Vector3(at.x, mower.spawn_height(), at.z)
	await step(15)
	check_eq(pickup.hitch(mower), "", "the pickup would not pull the lawnmower trailer")
	await step(20)
	at = mower.hitch_point() + Vector3(0, 0, 0.6) - dump.tongue_offset
	dump.global_position = Vector3(at.x, dump.spawn_height(), at.z)
	await step(60)
	check(mower.hitch(dump).contains("too heavy for the pickup"), "a dump trailer went on behind the pickup's trailer")
	check(mower.towing == null, "the dump trailer is on the pickup's train")
	# The bigger trucks have no such limit.
	for id in [&"hauler", &"log_truck", &"dump_truck", &"crane_truck"]:
		check_eq(float(GameData.vehicle(id).get("tow_limit", 0.0)), 0.0, "the %s has a towing limit" % id)
	done()

func _haulers_in(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child is Hauler and not child.is_queued_for_deletion():
			n += 1
	return n

## data/balance.json: every value in it is one the game reads, so a typo in
## a name is caught rather than silently ignored.
func test_balance_file() -> void:
	var values := Balance.all()
	check(values.size() >= 20, "balance.json has only %d values" % values.size())
	var source := ""
	for dir in ["res://scripts/core", "res://scripts/player", "res://scripts/physics", "res://scripts/vehicle",
			"res://scripts/world", "res://scripts/systems", "res://scripts/build"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				source += FileAccess.get_file_as_string(dir + "/" + f)
	for key: String in values:
		check(source.contains("\"%s\"" % key), "balance.json sets %s, which nothing reads" % key)
		check(values[key] is float or values[key] is int, "balance.json %s is not a number" % key)
	check_near(Terrain.ROAD_SPEED_BONUS, float(values["vehicles.road_speed_bonus"]), 0.0001, "the road bonus is not the file's")
	done()

func test_net_address() -> void:
	check_eq(Net.split_address("136.53.206.104"), ["136.53.206.104", Net.PORT], "a bare IP")
	check_eq(Net.split_address(" 136.53.206.104:24565 "), ["136.53.206.104", 24565], "an IP with the port")
	check_eq(Net.split_address("10.0.0.2:30000"), ["10.0.0.2", 30000], "an IP with another port")
	check_eq(Net.split_address("myhost.example.com"), ["myhost.example.com", Net.PORT], "a host name")
	check_eq(Net.split_address("10.0.0.2:banana"), ["10.0.0.2", Net.PORT], "a junk port falls back")
	done()

func test_guest_new_day_once() -> void:
	Economy.from_dict({"money": 100, "day": 3, "day_time": 10.0})
	var days := [0]
	var count := func(_d: int): days[0] += 1
	Economy.day_changed.connect(count)
	for i in 5:
		Economy.apply_remote({"money": 100 + i, "day": 3, "day_time": 11.0 + i})
	check_eq(days[0], 0, "same-day updates announced a new day")
	Economy.apply_remote({"money": 200, "day": 4, "day_time": 1.0})
	Economy.apply_remote({"money": 210, "day": 4, "day_time": 2.0})
	check_eq(days[0], 1, "new days announced")
	Economy.day_changed.disconnect(count)
	done()

func test_respawn_with_driver() -> void:
	_setup()
	Economy.from_dict({"money": 50000, "day": 1})
	plot.vehicle_host = world
	PlayerState.try_buy_vehicle()
	var pad := plot.place(GameData.building(&"vehicle_pad"), Vector2i(2, 2) * Plot.SUB, 0) as VehiclePad
	await step(4)
	var truck := pad.spawn() as Hauler
	await step(10)
	var p := _make_player()
	world.add_child(p)
	await step(2)
	p.enter_vehicle(truck)
	truck.driver = p
	await step(2)
	pad.spawn()
	await step(10)
	check(not p.driving(), "the driver is still in a truck that has gone")
	check(p.collision_mask != 0, "the driver was left with nothing to stand on")
	check(p.global_position.y > -5.0, "the driver fell through the world (y=%.1f)" % p.global_position.y)
	p.queue_free()
	done()

func test_guest_world_not_saved() -> void:
	# The connection has already gone (Net is offline), but the world on
	# screen is still the host's copy: it must not go over this player's save.
	var w := World.new()
	Net.guest_world = true
	check(not Net.is_client(), "offline, as after a failed or dropped join")
	check(not w.quick_save(), "a guest's copy of the world was saved")
	check(not w.save_to_slot(SaveSystem.slot), "a guest's copy was saved to a slot")
	Net.guest_world = false
	w.free()
	done()

func test_guest_kit() -> void:
	PlayerState.reset()
	var kit := PlayerKit.new()
	var axe := &"steel_axe"
	check(not kit.owns_tool(axe), "a new kit starts with the start tools only")
	check(kit.give_tool(axe), "a guest can get a tool")
	check(kit.owns_tool(axe) and not PlayerState.owns_tool(axe), "a guest's tool is theirs, not the host's")
	check(kit.hotbar.has(axe) and not PlayerState.hotbar.has(axe), "it goes on the guest's hotbar only")
	check(kit.level_up(&"carry"), "a guest's carry rack goes up")
	check_eq(kit.level(&"carry"), 2, "guest's rack")
	check_eq(PlayerState.level(&"carry"), 1, "host's rack is untouched")
	check(not kit.level_up(&"sawmill"), "machines are shared, not a guest's to level")
	PlayerState.levels[&"sawmill"] = 3
	check_eq(kit.level(&"sawmill"), 3, "a guest sees the shared machine level")
	# What the guest's own game is told, and the save round trip.
	var seen := kit.over(PlayerState.to_dict())
	check((seen.tools as Array).has(String(axe)), "the guest is told of their own tools")
	check_eq(int(seen.levels["carry"]), 2, "the guest is told of their own rack")
	check_eq(int(seen.levels["sawmill"]), 3, "and of the shared machines")
	PlayerState.guest_kits["Sam"] = kit.to_dict()
	var saved := PlayerState.to_dict()
	PlayerState.reset()
	PlayerState.from_dict(saved)
	var back := PlayerKit.new()
	back.from_dict(PlayerState.guest_kits.get("Sam", {}))
	check(back.owns_tool(axe) and back.level(&"carry") == 2, "a guest's kit comes back with the host's save")
	# The store stocks what any player still lacks.
	var shop := Store.new()
	shop.kit_source = func(): return [PlayerState, kit]
	check(shop.available({"kind": &"tool", "target": axe}), "a tool the host lacks is still stocked")
	PlayerState.give_tool(axe, false)
	check(not shop.available({"kind": &"tool", "target": axe}), "a tool everyone has is not stocked")
	shop.free()
	PlayerState.reset()
	done()

func test_kill_plane_below_caves() -> void:
	_setup(false)
	check(Tuning.KILL_PLANE_Y < World.FELL_OUT_Y, "the kill plane is above where the world ends")
	# A piece worked loose on a deep cave floor stays down there.
	var deep := spawn(&"ore_iron", Vector3(0, -85.0, 0), Solid.cube(0.02))
	deep.freeze = true
	await step(10)
	check(deep.global_position.y < -80.0, "a piece at cave depth was sent up to the surface")
	done()

func test_kill_plane() -> void:
	_setup()
	await step(2)
	var item := spawn(&"wood_pine", Vector3(0, 2, 0))
	item.teleport(Transform3D(Basis(), Vector3(0, Tuning.KILL_PLANE_Y - 10.0, 0)))
	await step(6)
	check(item.global_position.y > Tuning.KILL_PLANE_Y,
		"item below the kill plane was not rescued (y=%.1f)" % item.global_position.y)
	check(manager.stat_killplane > 0, "kill-plane rescue was not counted")
	# With land under it, it goes back on the surface right above where it
	# fell, not off to its plot.
	manager.ground_height = func(_p: Vector3) -> float: return 3.0
	var lost := spawn(&"wood_pine", Vector3(40, 2, -30))
	lost.teleport(Transform3D(Basis(), Vector3(40, Tuning.KILL_PLANE_Y - 5.0, -30)))
	await step(6)
	check(lost.global_position.y > 3.0 and Vector2(lost.global_position.x, lost.global_position.z).distance_to(Vector2(40, -30)) < 1.5,
		"a piece under the kill plane was not put back on the surface above it (%s)" % str(lost.global_position))
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

## Over the cap, the oldest pieces off the property go first, and nothing on
## the property ever does - however old it is.
func test_cap_spares_property() -> void:
	_setup()
	manager.per_plot_cap = 20
	manager.on_property = func(p: Vector3) -> bool: return p.x < 0.0
	await step(2)
	var home: Array[LooseItem] = []
	for i in 15:
		home.append(spawn(&"wood_pine", Vector3(-3.0 - float(i % 5), 0.5 + float(i / 5) * 0.6, -3.0)))
	var away: Array[LooseItem] = []
	for i in 5:
		away.append(spawn(&"wood_pine", Vector3(5.0 + float(i) * 1.5, 0.5, 5.0)))
	await step(10)
	# Five more past the cap: the five off the property go, oldest first.
	for i in 3:
		spawn(&"wood_pine", Vector3(20.0 + float(i) * 1.5, 0.5, 5.0))
	await step(2)
	for it in home:
		check(it.state == LooseItem.State.FREE and it.item_id == &"wood_pine" and it.global_position.x < 0.0,
			"a piece on the property was recycled for the cap")
	var gone := 0
	for i in 3:
		if away[i].state == LooseItem.State.POOLED or away[i].global_position.x > 19.0:
			gone += 1
	check_eq(gone, 3, "the three oldest pieces off the property were not the ones recycled")
	check(away[3].state == LooseItem.State.FREE and away[3].global_position.x < 19.0, "a newer piece went before an older one")
	# With nothing left off the property to take, the cap gives way.
	for i in 12:
		spawn(&"wood_pine", Vector3(-12.0 - float(i % 4), 0.5 + float(i / 4) * 0.6, 3.0))
	await step(2)
	for it in home:
		check(it.state == LooseItem.State.FREE and it.global_position.x < 0.0, "a piece on the property was recycled once the cap was full")
	done()

func test_shop_stock_kept() -> void:
	_setup()
	manager.per_plot_cap = 40
	await step(2)
	var stock: Array[LooseItem] = []
	for i in 12:
		var box := spawn(&"wood_pine", Vector3(10.0 + float(i), 1.0, 10.0))
		box.shop_stock = true
		stock.append(box)
	await step(2)
	for i in 120:
		spawn(&"wood_pine", Vector3(randf_range(-2, 2), 4.0 + float(i) * 0.05, randf_range(-2, 2)))
	await step(10)
	var kept := 0
	for box in stock:
		if is_instance_valid(box) and box.state != LooseItem.State.POOLED and box.shop_stock:
			kept += 1
	check_eq(kept, 12, "shop stock was recycled to make room")
	check(manager.active_count() <= 40 + 12, "the cap stopped holding with shop stock about (%d)" % manager.active_count())
	check(manager.active_count() >= 40, "shop stock took up the room that everything else is allowed (%d)" % manager.active_count())
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
	plot.place(GameData.building(&"sawmill"), Vector2i(-10, -8) * Plot.SUB, 0)
	plot.place(GameData.building(&"sander"), Vector2i(-7, -8) * Plot.SUB, 0)
	plot.place(GameData.building(&"crusher"), Vector2i(-2, -8) * Plot.SUB, 0)
	plot.place(GameData.building(&"furnace"), Vector2i(1, -8) * Plot.SUB, 0)
	plot.place(GameData.building(&"refiner"), Vector2i(4, -8) * Plot.SUB, 0)
	plot.place(GameData.building(&"splitter"), Vector2i(0, 2) * Plot.SUB, 0)
	plot.place(GameData.building(&"storage"), Vector2i(8, 2) * Plot.SUB, 0)
	plot.place(GameData.building(&"workbench"), Vector2i(8, -8) * Plot.SUB, 0)
	plot.place(GameData.building(&"conveyor"), Vector2i(-10, 2) * Plot.SUB, 0)
	plot.place(GameData.building(&"conveyor"), Vector2i(-4, 2) * Plot.SUB, 0)
	plot.place(GameData.building(&"conveyor"), Vector2i(4, 2) * Plot.SUB, 0)
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
				var dims := Solid.cylinder(0.2, 0.17, randf_range(1.2, 2.6)) if wood else Solid.cube(0.03)
				# The planker only planks sanded logs.
				if wood and m.machine_def.id == &"sawmill":
					dims = Solid.with_finish(dims, &"sanded")
				if m.top_loaded():
					_drop_in(m, feed, dims)
					continue
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

# --- The September list ---------------------------------------------------------

func test_controls() -> void:
	var original := Controls.to_dict()
	Controls.reset()
	check_eq(Controls.key(&"use"), "E", "use should default to E")
	check_eq(Controls.key(&"pause"), "Esc", "pause should show as Esc")
	check_eq(Controls.key(&"remove_selected"), "Del", "delete should show as Del")
	# Rebinding moves the action to the new key, everywhere.
	Controls.set_binding(&"use", ["R"])
	var r := InputEventKey.new()
	r.physical_keycode = KEY_R
	r.pressed = true
	var e := InputEventKey.new()
	e.physical_keycode = KEY_E
	e.pressed = true
	check(Controls.pressed(r, &"use"), "R did not do 'use' after rebinding")
	check(not Controls.pressed(e, &"use"), "E still did 'use' after rebinding it away")
	check(Controls.pressed(e, &"turn_cw"), "rebinding use should not move the turn key")
	# Prompts draw the key that does the job now.
	var parts := UIKit.parse_keys("Till: [E] pay")
	check_eq(String(parts[1][1]), "R", "a prompt's [E] should show the rebound key")
	# A mouse button can be bound, and a modifier combination.
	Controls.set_binding(&"crane", ["Mouse4", "Shift+C"])
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_XBUTTON1
	mb.pressed = true
	check(Controls.pressed(mb, &"crane"), "a mouse button binding did not work")
	var sc := InputEventKey.new()
	sc.physical_keycode = KEY_C
	sc.shift_pressed = true
	sc.pressed = true
	check(Controls.pressed(sc, &"crane"), "a Shift+C binding did not work")
	check_eq(Controls.label_for_event(sc), "Shift+C", "a pressed combination is not named as it is written")
	# Round trip through the config file, comments and all.
	var path := "user://test_config.cfg"
	var was_path: String = Settings.path
	Settings.path = path
	check(Settings.save_to(path), "the config file could not be written")
	var text := FileAccess.get_file_as_string(path)
	check(text.contains("[controls]") and text.contains("[settings]"), "the config file lacks a section")
	check(text.contains("; ") and text.contains("use=\"R\""), "the config file lacks its comments or the rebound key")
	Controls.reset()
	Settings.load_from(path)
	check_eq(Controls.key(&"use"), "R", "a rebound key did not survive the config file")
	check_eq(Controls.keys_text(&"crane"), "Mouse4 / Shift+C", "two bindings did not survive the config file")
	# Junk in the file falls back rather than breaking anything.
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[controls]\nuse=\"NotAKey\"\njump=\"Space, LMB\"\n")
	f.close()
	Settings.load_from(path)
	check_eq(Controls.keys_text(&"use"), "unbound", "a key that does not exist should leave the action unbound")
	check_eq(Controls.keys_text(&"jump"), "Space / LMB", "a hand-written binding was not read")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Settings.path = was_path
	Controls.apply(original)
	done()

func test_build_menu_and_pick() -> void:
	_setup()
	Economy.from_dict({"money": 50000, "day": 1})
	var cam := Camera3D.new()
	world.add_child(cam)
	var body := Node3D.new()
	world.add_child(body)
	var bs := BuildSystem.new()
	bs.setup(plot, cam, body)
	world.add_child(bs)
	await step(2)
	bs.set_active(true)
	check(bs.active, "build mode did not open")
	check(bs.current() == null, "build mode opened with something in hand")
	check(not bs.try_place(), "placed something with an empty hand")
	var opened: Array = []
	bs.menu_toggled.connect(func(o: bool): opened.append(o))
	bs.toggle_menu()
	check(bs.menu_open and opened == [true], "the build menu did not open")
	var belt := GameData.building(&"conveyor")
	bs.choose(belt)
	bs.set_menu(false)
	check(bs.current() != null and bs.current().id == &"conveyor", "choosing from the menu did not put it in hand")
	# Copy: a stretched, turned belt on the plot is picked up exactly.
	var node := plot.place(belt, Vector2i(0, 0), Vector3i(0, 1, 0))
	var index := plot.placed.size() - 1
	check_eq(plot.edit(index, Vector2i(0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 9), 0.0), "", "stretching the belt failed")
	await step(2)
	var rec: Dictionary = plot.placed[index]
	cam.global_transform = Transform3D(Basis(), (rec.node as Node3D).global_position + Vector3(0, 6, 0.01)).looking_at((rec.node as Node3D).global_position, Vector3.UP)
	await step(2)
	var said := bs.pick_block()
	check(said.begins_with("copied"), "the copy key did not copy the belt: %s" % said)
	check(bs.current() != null and bs.current().size == Vector3i(1, 1, 9), "the copy is not the stretched belt")
	check_eq(bs.rot, Vector3i(0, 1, 0), "the copy did not take the belt's turn")
	# Leaving and coming back is empty-handed again.
	bs.set_active(false)
	check(not bs.menu_open, "leaving build mode left the menu open")
	bs.set_active(true)
	check(bs.current() == null, "build mode reopened with something in hand")
	bs.set_active(false)
	done()

func test_fine_grid() -> void:
	_setup()
	Economy.from_dict({"money": 50000, "day": 1})
	check_near(Plot.SNAP, 0.25, 0.0001, "the grid should be a quarter of a metre")
	check_eq(Plot.SUB, 4, "four grid steps to the metre")
	var belt := GameData.building(&"conveyor")
	var a := plot.place(belt, Vector2i(0, 0), 0)
	var b := plot.place(belt, Vector2i(1, 0), 0)
	check(a != null and b != null, "belts a quarter metre apart could not both be placed")
	if a != null and b != null:
		check_near(b.position.x - a.position.x, 0.25, 0.001, "one grid step is not a quarter metre")
	# Every sixteenth of a square is marked taken under a building.
	check_eq(plot.indices_at_cell(Vector2i(3, 15)).size(), 2, "the two belts do not share the cells they overlap")
	# An old save counted cells in metres: it comes back where it was.
	var old := {"tier": 0, "buildings": [{"id": "conveyor", "cell": [2, -3], "rot": [0, 0, 0]}]}
	plot.from_dict(old)
	await step(2)
	check_eq(plot.placed[0].cell, Vector2i(8, -12), "an old save's cell was not moved to the fine grid")
	var saved := plot.to_dict()
	check_near(float(saved.get("grid", 0.0)), 0.25, 0.0001, "a save does not say what grid it is on")
	plot.from_dict(saved)
	await step(2)
	check_eq(plot.placed[0].cell, Vector2i(8, -12), "a new save's cell moved on reload")
	done()

func test_market_by_material() -> void:
	Economy.from_dict({"money": 0, "day": 1})
	for d in [1, 8, 15, 22, 29]:
		Economy.from_dict({"money": 0, "day": d})
		check_near(Economy.price_multiplier(&"wood_mahogany"), Economy.price_multiplier(&"lumber_mahogany"), 0.0001,
			"mahogany logs and lumber moved differently")
		check_near(Economy.price_multiplier(&"ore_iron"), Economy.price_multiplier(&"ingot_iron"), 0.0001,
			"iron ore and bars moved differently")
	check_eq(Economy.market_key(&"lumber_pine"), &"pine", "lumber is not priced as its material")
	# Cheap swings, dear barely moves.
	var cheap := Economy.volatility(&"pine")
	var dear := Economy.volatility(&"diamond")
	check(cheap > dear * 3.0, "pine (%.2f) should swing far more than diamond (%.2f)" % [cheap, dear])
	var spread_cheap := 0.0
	var spread_dear := 0.0
	for w in 20:
		Economy.from_dict({"money": 0, "day": 1 + w * Economy.WEEK})
		spread_cheap = maxf(spread_cheap, absf(Economy.price_multiplier(&"wood_pine") - 1.0))
		spread_dear = maxf(spread_dear, absf(Economy.price_multiplier(&"gem_diamond") - 1.0))
	check(spread_cheap > spread_dear * 2.0, "over twenty weeks pine moved %.2f and diamond %.2f" % [spread_cheap, spread_dear])
	# One row per material on the board.
	var names: Array = []
	for row in Economy.market_rows():
		check(not names.has(row.id), "the market board lists %s twice" % row.id)
		names.append(row.id)
	check(names.has(&"mahogany") and not names.has(&"lumber_mahogany"), "the board is not by material")
	Economy.from_dict({"money": 0, "day": 1})
	done()

func _branchy_trunk() -> LooseItem:
	var trunk := spawn(&"wood_pine", Vector3(0, 1, 0), Solid.cylinder(0.2, 0.15, 3.0))
	trunk.add_limb(Vector3(0, 0.5, 0), Vector3(1, 0.5, 0), 0.06, 1.2)
	trunk.add_limb(Vector3(0, 1.0, 0), Vector3(-1, 0.4, 0), 0.05, 1.0)
	trunk.owned = true
	return trunk

func test_branches_counted() -> void:
	_setup()
	Economy.from_dict({"money": 0, "day": 1})
	var trunk := _branchy_trunk()
	var bare := Economy.price_of(&"wood_pine", trunk.dims)
	var branch_pay := Economy.price_of(&"wood_pine", trunk.limb_dims(0)) + Economy.price_of(&"wood_pine", trunk.limb_dims(1))
	var yard := SellYard.new()
	yard.setup(manager, null)
	world.add_child(yard)
	await step(2)
	yard.sell_all([trunk])
	check_eq(Economy.money, bare + branch_pay, "a trunk's branches were not paid for")
	var bin := StorageBin.new()
	bin.setup(manager, GameData.building(&"storage"), 0)
	world.add_child(bin)
	await step(2)
	var second := _branchy_trunk()
	var total := second.volume() + second.limb_volume()
	check(bin.accept_item(second), "the bin refused a trunk with branches")
	var stored := 0.0
	for c in bin.contents:
		stored += Solid.volume(c.dims)
	check_near(stored, total, 0.0001, "the bin lost a trunk's branches")
	done()

func test_felled_no_leaves() -> void:
	_setup()
	var tree := _make_tree(7.0, 0.34, 0.6, 5)
	tree.foliage_style = &"ball"
	world.add_child(tree)
	await step(2)
	tree.fell(Vector3(0, 0, 5))
	await step(4)
	var trunk: LooseItem = manager.free_items()[0]
	check(trunk.limbs.size() > 0, "the felled trunk has no branches")
	var spheres := 0
	for n in trunk.get_children():
		if n is MeshInstance3D and ((n as MeshInstance3D).mesh is SphereMesh):
			spheres += 1
	check_eq(spheres, 0, "the felled trunk still has its leaves")
	done()

func test_machine_output_size() -> void:
	_setup()
	Economy.from_dict({"money": 90000, "day": 1})
	var log_dims := Solid.with_finish(Solid.cylinder(0.2, 0.2, 2.0), &"sanded")
	# The planker: boards 10 cm wide and 4 cm thick.
	var saw := plot.place(GameData.building(&"sawmill"), Vector2i(0, 0), 0, false) as InlineMachine
	await step(2)
	check(saw.config_fields().size() == 2, "the planker has no board sizes")
	# Boards can be set as big as the out-feed opening passes: short, fat bricks too.
	saw.set_setting(&"width_cm", 9999)
	saw.set_setting(&"thick_cm", 9999)
	check_eq(int(saw.setting(&"width_cm")), int(floor(saw.hole.x * 100.0)), "board width is not capped at the opening")
	check_eq(int(saw.setting(&"thick_cm")), int(floor(saw.hole.y * 100.0)), "board thickness is not capped at the opening")
	saw.set_setting(&"width_cm", 0)
	saw.set_setting(&"thick_cm", 0)
	var whole := saw._cut_to_size(saw.work({"id": &"wood_pine", "dims": log_dims.duplicate(true), "owned": true, "plot": 0, "changed": false, "ready": 0.0}))
	check_eq(whole.size(), 1, "as it comes, one plank")
	saw.set_setting(&"width_cm", 10)
	saw.set_setting(&"thick_cm", 4)
	var boards := saw._cut_to_size(saw.work({"id": &"wood_pine", "dims": log_dims.duplicate(true), "owned": true, "plot": 0, "changed": false, "ready": 0.0}))
	check(boards.size() > 1, "set to 10 x 4 cm, still one plank")
	var b0: Vector3 = boards[0].dims.size
	for o in boards:
		var bs: Vector3 = o.dims.size
		check(absf(bs.x - 0.10) < 0.001 and absf(bs.z - 0.04) < 0.001, "a board is %.3f x %.3f m, not 0.10 x 0.04" % [bs.x, bs.z])
	# A board bigger than the log's section: the size set, and short.
	saw.set_setting(&"width_cm", 60)
	saw.set_setting(&"thick_cm", 30)
	var brick := saw._cut_to_size(saw.work({"id": &"wood_pine", "dims": log_dims.duplicate(true), "owned": true, "plot": 0, "changed": false, "ready": 0.0}))
	var bb: Vector3 = brick[0].dims.size
	check(brick.size() == 1 and absf(bb.x - minf(0.6, saw.hole.x)) < 0.011 and absf(bb.z - minf(0.3, saw.hole.y)) < 0.011 and bb.y < 2.0,
		"a big board from a thin log is %s" % str(bb))
	saw.set_setting(&"width_cm", 10)
	saw.set_setting(&"thick_cm", 4)
	var sum := 0.0
	for o in boards:
		sum += Solid.volume(o.dims)
	check_near(sum, Solid.volume(whole[0].dims), 0.0001, "cutting boards lost volume")
	check_eq(float((saw.to_dict().config as Dictionary).get(&"width_cm", 0.0)), 10.0, "the board width is not saved")
	var back := plot.place(GameData.building(&"sawmill"), Vector2i(0, 16), 0, false) as InlineMachine
	await step(2)
	back.from_dict(saw.to_dict())
	check_eq(back.setting(&"thick_cm"), 4.0, "the board thickness did not come back")
	# The smelter: bars 3 cm thick.
	var furnace := plot.place(GameData.building(&"furnace"), Vector2i(0, 32), 0, false) as InlineMachine
	await step(2)
	furnace.set_setting(&"section_cm", 3)
	var bars := furnace._cut_to_size(furnace.work({"id": &"ore_iron", "dims": Solid.cube(0.3), "owned": true, "plot": 0, "changed": false, "ready": 0.0}))
	check(bars.size() >= 1 and absf((bars[0].dims.size as Vector3).z - 0.03) < 0.001, "the bars are not 3 cm thick")
	# The crusher: smaller lumps, more of them.
	var crusher := plot.place(GameData.building(&"crusher"), Vector2i(0, 48), 0, false) as InlineMachine
	await step(2)
	var coarse := crusher.work({"id": &"ore_iron", "dims": Solid.cube(0.02), "owned": true, "plot": 0, "changed": false, "ready": 0.0}).size()
	crusher.set_setting(&"max_cm", 8)
	var fine := crusher.work({"id": &"ore_iron", "dims": Solid.cube(0.02), "owned": true, "plot": 0, "changed": false, "ready": 0.0})
	check(fine.size() > coarse, "an 8 cm crusher made no more lumps (%d vs %d)" % [fine.size(), coarse])
	check(Solid.bounds(fine[0].dims).x <= 0.081, "a lump is bigger than 8 cm (%s, %d lumps)" % [Solid.bounds(fine[0].dims), fine.size()])
	done()

func test_gearbox() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"log_truck")
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), 0)
	await step(60)
	check(truck.gears.size() >= 3, "a truck has no gears")
	check(truck.rear_steer > 0.0, "the log truck's rear axle does not steer")
	check(truck.max_steer_angle >= 0.65, "the log truck still turns like a barge (%.2f)" % truck.max_steer_angle)
	# Automatic: it pulls away in first and changes up as it goes.
	truck.autopilot = true
	truck.input_throttle = 1.0
	await step(6)
	check_eq(truck.gear, 0, "the automatic did not pull away in first")
	var top_gear := 0
	for k in 100:
		await step(1)
		top_gear = maxi(top_gear, truck.gear)
	check(top_gear >= 2, "the automatic did not change up (gear %d at %.1f m/s)" % [top_gear + 1, truck.linear_velocity.length()])
	truck.input_throttle = 0.0
	truck.input_brake = true
	await step(60)
	# Manual: only the player changes gear.
	Settings.set_value(&"manual_gearbox", true, false)
	check(truck.manual_gearbox(), "the manual gearbox setting did not take")
	var held_gear := truck.gear
	await step(60)
	check_eq(truck.gear, held_gear, "the manual gearbox changed gear by itself")
	truck.shift_gear(-10)
	check_eq(truck.gear, 0, "shifting down did not stop at first")
	truck.shift_gear(1)
	check_eq(truck.gear, 1, "shifting up did not go up one")
	Settings.set_value(&"manual_gearbox", false, false)
	var loader := Hauler.new()
	loader.setup(manager, 0, &"loader")
	world.add_child(loader)
	await step(2)
	check(not loader.manual_gearbox(), "the loader should always be automatic")
	done()

## Spec: the transmission upgrades are more top speed on the flat - the
## stock box tops out at the vehicle's own speed, the best box well past it.
func test_overdrive_speed() -> void:
	var tops: Array[float] = []
	for lvl in [1, 4]:
		_setup(false)
		PlayerState.reset()
		Economy.from_dict({"money": 1000000, "day": 1})
		for c in world.get_children():
			if c.name == "Ground":
				c.free()
		# Open road, as far as it takes.
		var floor_body := StaticBody3D.new()
		floor_body.collision_layer = Layers.WORLD
		var fs := CollisionShape3D.new()
		fs.shape = WorldBoundaryShape3D.new()
		floor_body.add_child(fs)
		world.add_child(floor_body)
		var truck := Hauler.new()
		truck.setup(manager, 0, &"pickup")
		truck.part_levels = {&"transmission": lvl}
		world.add_child(truck)
		truck.global_position = Vector3(0, 1.5, 0)
		truck.rotation.y = -PI * 0.5
		await step(20)
		truck.autopilot = true
		var best := 0.0
		for i in 60 * 8:
			truck.input_throttle = 1.0
			await step(1)
			best = maxf(best, Vector2(truck.linear_velocity.x, truck.linear_velocity.z).length())
		tops.append(best)
		truck.queue_free()
	check(tops[0] > 21.0 and tops[0] < 26.0, "the stock pickup tops out at %.1f m/s" % tops[0])
	check(tops[1] > tops[0] * 1.3, "the best gearbox is only %.1f m/s against %.1f" % [tops[1], tops[0]])
	done()

func test_vehicle_upgrades() -> void:
	_setup()
	PlayerState.reset()
	plot.vehicle_host = world
	for track in [&"transmission", &"tyres"]:
		check(GameData.upgrade_tracks.has(track), "there is no %s upgrade" % track)
	check(not GameData.upgrade_tracks.has(&"engine"), "engines are still upgraded")
	# Parts are bought boxed and go into the inventory; nothing changes yet.
	PlayerState.add_part(&"transmission", 2)
	PlayerState.add_part(&"tyres", 2)
	PlayerState.add_copy(&"pad_pickup")
	PlayerState.add_copy(&"pad_pickup")
	var pad := plot.place(GameData.building(&"pad_pickup"), Vector2i(-12, -12) * Plot.SUB, 0) as VehiclePad
	var other_pad := plot.place(GameData.building(&"pad_pickup"), Vector2i(0, -12) * Plot.SUB, 0) as VehiclePad
	check(pad != null and other_pad != null, "the pads were not placed")
	if pad == null or other_pad == null:
		done()
		return
	var truck := pad.spawn() as Hauler
	var other := other_pad.spawn() as Hauler
	await step(10)
	var grip0 := (truck.wheel_bodies[0].physics_material_override as PhysicsMaterial).friction
	var gears0 := truck.gear_ratios().size()
	var top0 := truck.top_ratio()
	# Fitted at the pad: that one vehicle gets it, out of the inventory.
	check_eq(pad.fit(&"transmission", 2), "", "could not fit the gearbox")
	check_eq(pad.fit(&"tyres", 2), "", "could not fit the tyres")
	check_eq(PlayerState.part_count(&"transmission", 2), 0, "fitting the gearbox did not use it up")
	check(pad.fit(&"transmission", 3) != "", "a gearbox not owned was fitted")
	check_eq(truck.gear_ratios().size(), gears0 + 1, "the new gearbox has no extra gear")
	check(truck.top_ratio() > top0, "the new gearbox is no faster at the top")
	check(pow(1.0 / truck.top_ratio(), Hauler.GEAR_TORQUE_EXP) < pow(1.0 / top0, Hauler.GEAR_TORQUE_EXP),
		"the overdrive pulls as hard as the old top gear")
	var grip1 := (truck.wheel_bodies[0].physics_material_override as PhysicsMaterial).friction
	check(grip1 > grip0, "new tyres did not grip better (%.2f -> %.2f)" % [grip0, grip1])
	check_eq(other.gear_ratios().size(), gears0, "a part fitted to one pickup went on the other too")
	# Switched off in the customisation, it runs as stock; on again, not.
	pad.set_part_on(&"transmission", false)
	check_eq(truck.gear_ratios().size(), gears0, "a switched-off gearbox still has its extra gear")
	pad.set_part_on(&"transmission", true)
	check_eq(truck.gear_ratios().size(), gears0 + 1, "switched back on, the gearbox is not there")
	# A new vehicle off the pad comes with them; taken off, a part goes back.
	var again := pad.spawn() as Hauler
	await step(4)
	check_eq(again.gear_ratios().size(), gears0 + 1, "the respawned pickup lost its gearbox")
	check_eq(pad.fit(&"transmission", 1), "", "could not go back to stock")
	check_eq(PlayerState.part_count(&"transmission", 2), 1, "the gearbox taken off did not go back into the parts")
	# Saved: parts and what is fitted.
	pad.fit(&"transmission", 2)
	var saved_pad := pad.to_dict()
	var saved_state := PlayerState.to_dict()
	PlayerState.reset()
	PlayerState.from_dict(saved_state)
	check_eq(PlayerState.part_count(&"tyres", 2), 0, "the save gave back a fitted part")
	var fresh := VehiclePad.new()
	fresh.fitted = {}
	fresh.from_dict({"fitted": saved_pad.fitted, "off": saved_pad.off})
	check_eq(fresh.fitted_level(&"transmission"), 2, "the pad forgot its gearbox")
	fresh.free()
	var buggy := Hauler.new()
	buggy.setup(manager, 0, &"buggy")
	world.add_child(buggy)
	await step(2)
	check(buggy.rig != null and is_equal_approx(buggy.rig.winch_power_kg, 2000.0), "the dune buggy has no 2 t winch")
	check(buggy.rig != null and not buggy.rig.has_crane(), "the dune buggy should not have a crane")
	# Every level of both is on the store's shelf as a part.
	var sold: Array = []
	for p in GameData.store_products():
		if String(p.get("kind", "")) == "part":
			sold.append("%s:%d" % [p.target, int(p.level)])
	for track in ["transmission", "tyres"]:
		for lvl in [2, 3, 4]:
			check(sold.has("%s:%d" % [track, lvl]), "the store does not sell %s level %d" % [track, lvl])
	# An old save's engine level comes back as a gearbox part to fit.
	PlayerState.from_dict({"levels": {"engine": 3}})
	check_eq(PlayerState.part_count(&"transmission", 3), 1, "an old save's engine did not become a gearbox part")
	done()

func test_recover_limits() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"hauler")
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), 0)
	await step(30)
	check_eq(truck.try_recover(), "", "recovering was refused")
	check(truck.try_recover() != "", "recovering twice at once was allowed")
	await step(70)
	check_eq(truck.try_recover(), "", "recovering a second later was refused")
	await step(70)
	truck.rig.set_outriggers(true)
	check(truck.try_recover() != "", "recovering was allowed on the outriggers")
	truck.rig.set_outriggers(false)
	# Only a crane truck has outriggers: a dump truck stays on its wheels.
	var dump := Hauler.new()
	dump.setup(manager, 0, &"dump_truck")
	world.add_child(dump)
	dump.global_position = Vector3(8, 2, 0)
	await step(3)
	if dump.rig != null:
		dump.rig.set_outriggers(true)
		check(not dump.rig.outriggers_down and not dump.freeze, "a truck with no crane put outriggers out")
		check(Player.new().toggle_outriggers(dump.rig).contains("crane"), "O on a truck with no crane should say why")
	done()

func test_crane_from_trailer() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"log_truck")
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), 0)
	var trailer := Hauler.new()
	trailer.setup(manager, 0, &"log_trailer")
	world.add_child(trailer)
	await step(2)
	var behind := truck.hitch_point() + Vector3(0, 0, 0.6) - trailer.tongue_offset
	trailer.global_position = Vector3(behind.x, trailer.spawn_height(), behind.z)
	await step(90)
	check_eq(truck.hitch(trailer), "", "the trailer would not hitch")
	await step(30)
	check(trailer.load_item(&"wood_pine", Solid.cylinder(0.2, 0.18, 2.0)), "the trailer would not take a log")
	var log: LooseItem = trailer.cargo_list()[0]
	# Someone in the cab: the trailer's settled load is fixed in place.
	var driver := Node3D.new()
	world.add_child(driver)
	truck.driver = driver
	await step(90)
	check(trailer.is_fixed(log), "a driven trailer did not fix its load")
	# Working the crane lets the trailer's load go, so it can be picked out.
	truck.rig.set_operating(true)
	await step(10)
	check(not trailer.is_fixed(log) and log.state == LooseItem.State.FREE, "the trailer kept its load fixed under the crane")
	var rig := truck.rig
	var frame := truck.global_transform
	rig.target = rig.clamp_target(frame.affine_inverse() * log.global_position)
	for i in 900:
		await step(1)
		if rig.jaw_world().distance_to(log.global_position) < 0.3:
			break
	check(rig.jaw_world().distance_to(log.global_position) < 0.7, "the crane could not reach into the trailer (%.1f m off)" % rig.jaw_world().distance_to(log.global_position))
	check_eq(rig.latch(), "", "the grapple would not close on the log in the trailer")
	check(rig.holding(), "the crane did not take the log out of the trailer")
	truck.driver = null
	done()

func test_loader_grapple() -> void:
	_setup(false)
	var v := Hauler.new()
	v.setup(manager, 0, &"loader")
	world.add_child(v)
	v.global_position = Vector3(0, v.spawn_height(), 0)
	await step(60)
	var l := v.loader
	check_eq(l.attachment, &"bucket", "the loader should start with its bucket")
	var said := l.swap_attachment()
	check_eq(l.attachment, &"grapple", "the grapple did not go on: %s" % said)
	var tines := 0
	for c in l.bucket.get_children():
		if c is CollisionShape3D:
			tines += 1
	check(tines >= 5, "the grapple has no tines to lift on")
	# A load in it stops the swap.
	l.lift = l.lift_min
	l.tilt = 0.0
	await step(30)
	var tip := l.bucket.global_transform * Vector3(0, 0.3, -l.depth * 0.6)
	var log := spawn(&"wood_pine", tip + Vector3(0, 0.3, 0), Solid.cylinder(0.15, 0.15, 2.4))
	log.global_transform = Transform3D(LooseItem.lying_basis(PI * 0.5), log.global_position)
	await step(40)
	if not l.held().is_empty():
		check(l.swap_attachment().begins_with("empty"), "swapped with a log on the tines")
		check_eq(l.attachment, &"grapple", "the grapple came off with a load on it")
	manager.despawn(log)
	await step(10)
	var saved := v.to_dict()
	check_eq(String(saved.loader[3]), "grapple", "the attachment is not saved")
	l.swap_attachment()
	check_eq(l.attachment, &"bucket", "the bucket did not go back on")
	v.from_dict(saved)
	await step(5)
	check_eq(l.attachment, &"grapple", "loading did not put the grapple back on")
	done()

func test_winch_snap() -> void:
	_setup(false)
	var player := Player.new()
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	player.add_child(cam)
	world.add_child(player)
	player.global_position = Vector3(0, 0.1, 0)
	await step(2)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"pickup")
	world.add_child(truck)
	truck.global_position = Vector3(4, truck.spawn_height(), 0)
	await step(30)
	var log := spawn(&"wood_pine", Vector3(0, 0.3, -9), Solid.cylinder(0.2, 0.2, 2.0))
	await step(30)
	# Aimed at the ground a metre to one side of the log.
	cam.global_transform = Transform3D(Basis(), Vector3(0, 1.7, 0)).looking_at(Vector3(1.0, 0, -9.0), Vector3.UP)
	var hit := player.winch_target(truck.rig)
	check(not hit.is_empty() and hit.collider == log, "the winch did not find the log near the crosshair")
	check_eq(player.hook_winch(truck.rig).begins_with("winch hooked"), true, "the winch did not hook the log")
	check(truck.rig.anchor_body == log, "the winch hooked something else")
	player.queue_free()
	done()

func test_rack_not_aimed() -> void:
	_setup(false)
	var player := Player.new()
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	player.add_child(cam)
	world.add_child(player)
	player.manager = manager
	player.global_position = Vector3(0, 0.1, 0)
	await step(2)
	cam.position = Vector3(0, 1.65, 0)
	var billet := spawn(&"wood_pine", Vector3(0, 1, -1.5), Solid.cylinder(0.08, 0.08, 0.6))
	await step(2)
	check(player.pick_up(billet), "could not pick up a billet")
	await step(2)
	var behind := spawn(&"ore_iron", Vector3(0, 0.3, -3.0), Solid.cube(0.3))
	await step(10)
	cam.look_at(behind.global_position, Vector3.UP)
	var hit := player.aim_hit()
	check(hit.is_empty() or hit.collider != billet, "the crosshair stopped on what is on the rack")
	player.queue_free()
	done()

func test_avatar() -> void:
	_setup(false)
	var player := _make_player()
	world.add_child(player)
	player.global_position = Vector3(0, 0.1, 0)
	await step(5)
	var av := player.avatar
	check(av != null and av.ready_to_draw(), "the player model did not load")
	if av == null or not av.ready_to_draw():
		player.queue_free()
		done()
		return
	check_eq(av._part.size(), PlayerAvatar.PARTS.size(), "the model is missing pivots (elbows, knees, fingers...)")
	player.third_person = false
	await step(2)
	check_eq(av._meshes[0].cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
		"in first person only his shadow should be drawn")
	check(player.eye().is_equal_approx(player.camera.global_position), "in first person the eye is the camera")
	# A gesture plays and ends.
	av.play(&"pick_up")
	check_eq(av.gesture(), &"pick_up", "a gesture should start")
	await step(60)
	check_eq(av.gesture(), &"", "a gesture should end")
	check(not av.GESTURES.has(&"nonsense"), "unknown gestures are ignored")
	av.play(&"nonsense")
	check_eq(av.gesture(), &"", "an unknown gesture should not play")
	# Third person: the camera goes behind him, he is drawn, and the
	# crosshair still picks what it covers, with reach counted from him.
	player.third_person = true
	var block := spawn(&"ore_iron", Vector3(0, 1.4, -2.5), Solid.cube(0.4))
	await step(10)
	check_eq(av._meshes[0].cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "in third person he should be drawn")
	var head := player.global_position + Vector3(0, 1.65, 0)
	check(player.camera.global_position.distance_to(head) > 1.5, "the third-person camera should sit back from him")
	player.camera.look_at(block.global_position, Vector3.UP)
	check(player.eye().distance_to(head) < 1.0, "reach should be counted from his head, not the camera")
	var hit := player.aim_hit()
	check(not hit.is_empty() and hit.collider == block, "the crosshair should still pick what it covers in third person")
	player.third_person = false
	player.queue_free()
	done()

func test_plot_clear() -> void:
	_setup(false)
	var land := Terrain.new()
	land.half_extent = 300.0
	land.noise_seed = 20260921
	land.roads = [[Vector3(-250, 0, 0), Vector3(0, 0, 0), Vector3(250, 0, 40)]]
	land.reserve_clear_square(Vector3(0, 0.45, 0), 50.0, 0.45, 10.0)
	world.add_child(land)
	await step(2)
	var worst := -INF
	var roads := 0
	for x in range(-50, 51, 5):
		for z in range(-50, 51, 5):
			worst = maxf(worst, land.height_at(float(x), float(z)))
			if land.is_road(float(x), float(z)):
				roads += 1
	check(worst <= 0.46, "the land comes up to %.2f m inside the plot's square" % worst)
	check_eq(roads, 0, "a road runs across the plot's square")
	check(land.is_road(-150.0, 0.0) or land.is_road(-150.0, 6.0), "the road outside the plot is gone too")
	var surface := RoadSurface.new()
	surface.setup(land)
	world.add_child(surface)
	await step(2)
	var space := world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(0, 50, 0), Vector3(0, -50, 0), Layers.WORLD)
	q.exclude = []
	var hit := space.intersect_ray(q)
	check(hit.is_empty() or (hit.position as Vector3).y < 0.5, "road surface laid across the plot")
	done()

func test_save_slots() -> void:
	var was_slot := SaveSystem.slot
	var was_chosen := SaveSystem.slot_chosen
	check_eq(SaveSystem.SLOTS, 6, "there should be six save slots")
	check(SaveSystem.slot_path(3).ends_with("slot_3.json"), "slot paths are wrong")
	_setup()
	var a := SaveSystem.slot_path(5)
	var b := SaveSystem.slot_path(6)
	for p in [a, b]:
		SaveSystem.delete_save(p)
	Economy.from_dict({"money": 111, "day": 3})
	check(SaveSystem.save_game(plot, null, a), "could not save to slot 5")
	Economy.from_dict({"money": 222, "day": 9})
	check(SaveSystem.save_game(plot, null, b), "could not save to slot 6")
	var listed := SaveSystem.slots()
	check_eq(listed.size(), 6, "slots() should list every slot")
	check_eq(int(listed[4].info.day), 3, "slot 5 does not hold its own game")
	check_eq(int(listed[5].info.money), 222, "slot 6 does not hold its own game")
	SaveSystem.slot = 5
	check(SaveSystem.load_game(plot, null, ""), "could not load the current slot")
	check_eq(Economy.money, 111, "loading the current slot read the wrong game")
	SaveSystem.delete_save(b)
	check(SaveSystem.summary(b).is_empty(), "a deleted slot still has a game in it")
	SaveSystem.delete_save(a)
	check(not Version.number().is_empty() and Version.line().contains("released"), "there is no version to show")
	SaveSystem.slot = was_slot
	SaveSystem.slot_chosen = was_chosen
	Economy.from_dict({"money": 100000, "day": 1})
	done()

func test_climb() -> void:
	_setup(false)
	var ramp := StaticBody3D.new()
	ramp.collision_layer = Layers.WORLD
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	ramp.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var length := 60.0
	box.size = Vector3(14, 1, length)
	cs.shape = box
	var a := deg_to_rad(38.0)
	cs.transform = Transform3D(Basis(Vector3.RIGHT, a), Vector3(0, sin(a) * length * 0.5 - 0.5 * cos(a), -8.0 - cos(a) * length * 0.5))
	ramp.add_child(cs)
	world.add_child(ramp)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"log_truck")
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), 6)
	await step(60)
	for i in 4:
		truck.load_item(&"wood_oak", Solid.cylinder(0.3, 0.28, 3.0))
	await step(60)
	truck.autopilot = true
	truck.input_throttle = 1.0
	var best := 0.0
	for i in 600:
		await step(1)
		best = maxf(best, truck.global_position.y)
	check(best > 15.0, "a loaded log truck only got %.1f m up a 38-degree slope" % best)
	done()

## Ore blocks are built for the box they fill: any aspect ratio, cubes kept
## (nearly) cubic, the rock filling the box and only glowing ore sticking out.
func test_ore_look_fits_any_box() -> void:
	for size: Vector3 in [Vector3(1, 1, 1), Vector3(2.4, 0.4, 0.9), Vector3(0.3, 1.6, 0.5), Vector3(0.12, 0.2, 0.15)]:
		var n := OreLook.cells_for(size)
		var cube := Vector3(size.x / n.x, size.y / n.y, size.z / n.z)
		var ratio := maxf(cube.x, maxf(cube.y, cube.z)) / minf(cube.x, minf(cube.y, cube.z))
		check(ratio < 1.35, "ore cubes stay near cubes in %s (ratio %.2f)" % [size, ratio])
		for id: StringName in [&"ore_iron", &"ore_bismuth", &"ore_starmetal"]:
			var parts := OreLook.rock(id, size, Vector3.ZERO, 0.0, 7)
			check(parts.size() >= 1, "%s has a rock for %s" % [id, size])
			if parts.is_empty():
				continue
			var box: AABB = parts[0].mesh.get_aabb()
			for k in range(1, parts.size()):
				box = box.merge(parts[k].mesh.get_aabb())
			# Ore stands out of a face by under half a cube.
			var slack := Vector3.ONE * (maxf(cube.x, maxf(cube.y, cube.z)) * 0.9 + 0.001)
			check(box.size.x >= size.x * 0.99 and box.size.x <= size.x + slack.x
				and box.size.y >= size.y * 0.99 and box.size.y <= size.y + slack.y
				and box.size.z >= size.z * 0.99 and box.size.z <= size.z + slack.z,
				"%s rock fills %s (got %s)" % [id, size, box.size])
			for p in parts:
				p.free()
	done()

# --- Friends' list: ragdolls, cranes, the crusher, TNT ------------------------------

## A player standing on the test ground, ready to be thrown about.
func _standing_player(at: Vector3) -> Player:
	var p := _make_player()
	p.position = at
	world.add_child(p)
	return p

func test_knocked_flying() -> void:
	_setup(false)
	var p := _standing_player(Vector3(0, 1.0, 0))
	await step(30)
	check(p.is_on_floor(), "the player is not standing to start with")
	p.knock(Vector3(8, 7, 0))
	check(p.knocked(), "a knock did not throw him limp")
	await step(10)
	check_eq(p.avatar.mode(), &"ragdoll", "the lumberjack does not go limp when thrown")
	check(p.ragdoll != null, "he went limp as one lump, not a ragdoll with arms and legs")
	var went := false
	var worst_gap := 0.0
	for i in 60 * 14:
		await step(1)
		if p.global_position.x > 3.0:
			went = true
		if p.ragdoll != null and is_instance_valid(p.ragdoll):
			# Every limb stays on at its joint, however he lands.
			for pair in [[&"arm_r", &"fore_r", 0.24], [&"thigh_l", &"shin_l", 0.28], [&"torso", &"head", 0.0]]:
				var a: RigidBody3D = p.ragdoll.bodies[pair[0]]
				var b: RigidBody3D = p.ragdoll.bodies[pair[1]]
				var joint: Vector3 = a.global_transform * (Vector3.DOWN * float(pair[2])) if float(pair[2]) > 0.0 else b.global_position
				worst_gap = maxf(worst_gap, joint.distance_to(b.global_position))
		if not p.knocked():
			break
	check(worst_gap < 0.2, "a limb came off at the joint (%.2f m)" % worst_gap)
	check(went, "the knock did not send him flying")
	check(not p.knocked(), "he never got back up")
	check_eq(p.collision_layer, Layers.PLAYER, "standing up did not give him his body back")
	check(not p.camera.top_level, "the camera stayed off watching after he got up")
	check(p.avatar.part(&"Torso").position.distance_to(Vector3(0, 0.62, 0)) < 0.01, "his body did not go back on his hips after getting up")
	check(not p.avatar.hat_off(), "his hat is still off after getting up")
	# A long drop lands him in a heap too.
	p.global_position = Vector3(0, 40, 0)
	p.velocity = Vector3.ZERO
	var fell := false
	for i in 60 * 6:
		await step(1)
		if p.knocked():
			fell = true
			break
	check(fell, "a long fall did not knock him over")
	p.free_tumble_for_test()
	done()

func test_truck_knocks_player() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"pickup")
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), 30)
	await step(30)
	var p := _standing_player(Vector3(0, 1.0, 0))
	await step(20)
	# Straight at him, flat out.
	truck.autopilot = true
	truck.input_throttle = 1.0
	var toward := (p.global_position - truck.global_position).normalized()
	if (-truck.global_transform.basis.z).dot(toward) < 0.0:
		truck.input_throttle = -1.0
	var hit := false
	for i in 60 * 8:
		await step(1)
		if p.knocked():
			hit = true
			break
	check(hit, "a truck driving into him did not send him flying")
	if hit:
		check(p.tumble.linear_velocity.dot(toward) > 3.0, "he did not go the way the truck was going")
	p.free_tumble_for_test()
	done()

## Only a vehicle coming at him knocks him flying. Sprinting flat out into a
## parked one (faster than the knock speed) just stops him against it; so
## does riding along on a moving one.
func test_run_into_parked_truck() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"pickup")
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), -7)
	await step(40)
	var p := _standing_player(Vector3(0, 1.0, 0))
	await step(20)
	p.rotation.y = 0.0
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var fastest := 0.0
	var knocked := false
	for i in 150:
		await step(1)
		fastest = maxf(fastest, Vector2(p.velocity.x, p.velocity.z).length())
		knocked = knocked or p.knocked()
	Input.action_release("move_forward")
	Input.action_release("sprint")
	check(fastest > Player.CAR_KNOCK_SPEED, "he never ran faster than the knock speed (%.1f m/s)" % fastest)
	check(p.global_position.z < -3.0, "he did not get to the truck (z %.1f)" % p.global_position.z)
	check(not knocked, "running into a parked truck knocked him flying")
	if p.knocked():
		p.free_tumble_for_test()
	done()

func test_crane_lifts_player() -> void:
	_setup(false)
	var truck := Hauler.new()
	truck.setup(manager, 0, &"crane_truck")
	world.add_child(truck)
	truck.global_position = Vector3(0, truck.spawn_height(), 0)
	await step(60)
	var rig := truck.rig
	rig.set_operating(true)
	var frame := truck.global_transform
	var beside: Vector3 = frame * Vector3(3.6, 0.0, 1.0)
	var p := _standing_player(Vector3(beside.x, 1.0, beside.z))
	await step(40)
	var over := frame.affine_inverse() * (p.global_position + Vector3.UP * 1.0)
	rig.target = rig.clamp_target(Vector3(over.x, over.y + 3.0, over.z))
	for i in 400:
		await step(1)
	rig.claw()
	for i in 900:
		await step(1)
		if rig.claw_state == &"":
			break
	check(rig.held_player == p, "the claw did not pick the player up")
	check(p.knocked() and p.crane_hold, "the player is not hanging from the grapple")
	var low := p.global_position.y
	rig.target += Vector3(0, 1.5, 0)
	for i in 120:
		await step(1)
	check(p.global_position.y > low + 0.8, "the player did not go up with the crane")
	# Let go: he drops, and gets up again.
	rig.claw()
	check(rig.held_player == null, "F did not let the player go")
	for i in 60 * 14:
		await step(1)
		if not p.knocked():
			break
	check(not p.knocked(), "dropped by the crane, he never got up")
	done()

func test_crusher_crushes_player() -> void:
	_setup(false)
	var crusher := _inline(&"crusher")
	_runout(crusher)
	await step(10)
	var top := crusher.global_transform * Vector3(0, InlineMachine.DECK_THICKNESS + crusher.canopy_height() + InlineMachine.HOPPER_DEPTH + 1.0, 0)
	var p := _standing_player(top)
	var got := false
	var pulled := false
	var frames_drawn := 0
	for i in 600:
		await step(1)
		if p.grinding():
			pulled = true
			frames_drawn += 1
		if p.crushed():
			got = true
			break
	check(pulled, "he was not drawn into the wheels first")
	check(frames_drawn > 100, "he went through in %d frames: not slowly" % frames_drawn)
	check(got, "falling into the crusher did not crush him")
	check(crusher._wheels.size() == 2, "the crusher has no grinding wheels")
	var meat := 0
	for i in 60 * 6:
		await step(1)
	for item in manager.free_items():
		if item.item_id == &"meat_bits":
			meat += 1
	check(meat >= 5, "the crusher did not spit out meat (%d bits)" % meat)
	check(not p.crushed(), "he was never let out of the crusher")
	done()

## The crusher only takes someone who is down inside its hopper: standing on
## its roof beside the mouth, or passing just over the rims, is safe.
func test_crusher_rim_safe() -> void:
	_setup(false)
	var crusher := _inline(&"crusher")
	_runout(crusher)
	await step(10)
	var roof := InlineMachine.DECK_THICKNESS + crusher.canopy_height() + 0.06
	var rim := roof + InlineMachine.HOPPER_DEPTH
	var open := crusher.hopper_opening()
	var t := crusher.global_transform
	# Just over the rims, as at the top of a jump across.
	check(not crusher._in_hopper(t * Vector3(0, rim + 0.3, 0)), "just over the hopper counts as in it")
	check(not crusher._in_hopper(t * Vector3(open * 0.5 + 0.1, rim - 0.4, 0)), "beside the rim counts as in it")
	check(crusher._in_hopper(t * Vector3(0, rim - 0.5, 0)), "down in the hopper does not count")
	# A player standing on the roof next to the hopper for a while.
	var p := _standing_player(t * Vector3(open * 0.5 + 0.45, roof + 0.3, 0))
	for i in 120:
		await step(1)
	check(not p.grinding() and not p.crushed(), "standing by the hopper pulled him in")
	p.queue_free()
	done()

func test_tnt() -> void:
	_setup()
	# Sold by the stick at the hardware store, $50 a go, and always back on
	# the shelf.
	check_eq(GameData.item(&"tnt_stick").cost, 50, "a stick of TNT is not $50")
	var town := Store.new()
	town.setup(manager, plot, 0, &"general")
	world.add_child(town)
	await step(4)
	var slot: Dictionary = {}
	for s in town.slots:
		if s.target == &"tnt_stick":
			slot = s
	check(not slot.is_empty(), "the hardware store does not sell TNT")
	if not slot.is_empty():
		check_eq(town.price_of(slot), 50, "the shop does not charge $50 for TNT")
		var box := slot.item as LooseItem
		check(box != null, "no TNT on the shelf")
		if box != null:
			var before := Economy.money
			town.buy([box] as Array[LooseItem])
			check_eq(Economy.money, before - 50, "buying TNT did not take $50")
			town.open_box(box)
			await step(2)
			check(slot.item != null and slot.item != box, "the TNT was not put back on the shelf")
	var sticks := 0
	for item in manager.free_items():
		if item.item_id == &"tnt_stick":
			sticks += 1
	check_eq(sticks, 1, "opening the box did not give a stick of TNT")
	# In a quarry: an iron chunk and a platinum one the same size, the same
	# distance from a stick, and a player standing by.
	var iron := OreRock.new()
	iron.manager = manager
	iron.ore_item = &"ore_iron"
	iron.embed = 0.3
	iron.volume = 0.8
	iron.position = Vector3(-30, 0, 30)
	world.add_child(iron)
	var plat := OreRock.new()
	plat.manager = manager
	plat.ore_item = &"ore_platinum"
	plat.embed = 0.3
	plat.volume = 0.8
	plat.position = Vector3(-30, 0, 26)
	world.add_child(plat)
	var p := _standing_player(Vector3(-27, 1.0, 28))
	await step(20)
	var stick := spawn(&"tnt_stick", Vector3(-30, 0.5, 28))
	await step(10)
	check(Blast.light(stick, manager, 0.2), "the stick would not light")
	check(not Blast.light(stick, manager), "a lit stick lit again")
	for i in 30:
		await step(1)
	var left := 0
	for item in manager.free_items():
		if item.item_id == &"tnt_stick":
			left += 1
	# Only the one unpacked at the shop is left.
	check_eq(left, 1, "the stick did not go off")
	check(iron.consumed() or iron.volume < 0.5, "TNT barely touched an iron chunk (%.2f m3 left)" % iron.volume)
	check(not plat.consumed() and plat.volume > 0.75, "TNT tore up platinum (%.2f m3 left)" % plat.volume)
	check(p.knocked(), "the blast did not throw the player")
	if p.knocked():
		check(p.tumble.linear_velocity.length() > 4.0 or p.global_position.distance_to(Vector3(-27, 1, 28)) > 1.0,
			"the blast barely moved the player")
	p.free_tumble_for_test()
	done()

## One stick sets off the rest: loose, boxed, or on someone's rack - and he
## goes a long way.
func test_tnt_chain() -> void:
	_setup()
	var a := spawn(&"tnt_stick", Vector3(20, 0.5, -20))
	var b := spawn(&"tnt_stick", Vector3(23, 0.5, -20))
	var boxed := spawn(&"box_tnt_stick", Vector3(20, 0.5, -15))
	var p := _standing_player(Vector3(18, 1.0, -22))
	await step(20)
	var carried := spawn(&"tnt_stick", p.global_position + Vector3(0, 1.2, 0))
	await step(2)
	check(p.pick_up(carried), "could not pick a stick of TNT up onto the rack")
	await step(5)
	check(Blast.light(a, manager, 0.1), "the first stick would not light")
	var fastest := 0.0
	for i in 90:
		await step(1)
		if p.knocked():
			fastest = maxf(fastest, p.tumble.linear_velocity.length())
	var left := 0
	for item in manager.free_items():
		if Blast.explosive(item):
			left += 1
	check_eq(left, 0, "not every stick went up in the chain")
	check(not p.held.has(carried), "the stick on his rack did not go off")
	check(fastest > 18.0, "the blast only threw him at %.1f m/s" % fastest)
	p.free_tumble_for_test()
	done()

# --- Ostars -------------------------------------------------------------------

## The second map is drawn, not rolled: the places on it are where it says.
func test_ostars_land() -> void:
	var o := Ostars.new()
	var home: Array = o.sample(0.0, 0.0)
	check(float(home[1]) > 0.5 and float(home[1]) < 10.0, "home is not low dry ground (%.1f)" % float(home[1]))
	check_eq(int(home[0]), Terrain.Biome.WOODLAND, "home is not in the meadows")
	for corner in [Vector2(2350, 2350), Vector2(-2350, -2350), Vector2(2350, -2350), Vector2(-2350, 2350)]:
		check(float(o.sample(corner.x, corner.y)[1]) < -3.0, "the map's corner %s is not sea" % corner)
	check(float(o.sample(-1500.0, 200.0)[1]) < 0.0, "the Aethel Sea is dry")
	check(float(o.sample(-1940.0, -360.0)[1]) > 3.0, "the Whispering Woods' island is not there")
	# The Arch stands out of the sea, with sea either side of it.
	check(float(o.sample(-1470.0, -400.0)[1]) > 10.0, "the Great Sky Arch is not up out of the sea")
	check(float(o.sample(-1470.0, -330.0)[1]) < 0.0 and float(o.sample(-1470.0, -470.0)[1]) < 0.0,
		"the Arch is not over open water")
	# The Spine: a flat top well up off the desert, and it drops away.
	var top: float = o.sample(560.0, 350.0)[1]
	check_near(top, 38.0, 1.0, "the Emperor's Spine's top")
	check(float(o.sample(620.0, 300.0)[1]) < top - 4.0, "the Spine is not a ridge")
	# Orodruin: a high cone with a crater sunk in its top.
	var rim: float = o.sample(-1010.0, -980.0)[1]
	var pit: float = o.sample(-1080.0, -980.0)[1]
	check(rim > 200.0, "Mt. Orodruin is only %.0f m high" % rim)
	check(pit < rim - 30.0, "Orodruin has no crater (%.0f in, %.0f at the rim)" % [pit, rim])
	check_eq(int(o.sample(-1080.0, -900.0)[0]), Terrain.Biome.ASH, "Orodruin is not ash")
	check(Ostars.lava_level() < rim and Ostars.lava_level() > pit, "the lava is not in the crater")
	# The frozen lakes are flat ice; the north is snow.
	var lake: Array = o.sample(520.0, -1830.0)
	check_eq(int(lake[0]), Terrain.Biome.ICE, "the tundra lake is not ice")
	check_near(float(o.sample(560.0, -1830.0)[1]), float(lake[1]), 0.01, "the ice is not flat")
	check_eq(int(o.sample(900.0, -1800.0)[0]), Terrain.Biome.SNOW, "the Frostpeak Tundra is not snow")
	check_eq(int(o.sample(450.0, 360.0)[0]), Terrain.Biome.DESERT, "the Shattered Desert is not desert")
	check_eq(int(o.sample(1450.0, 760.0)[0]), Terrain.Biome.SWAMP, "the Mor'uk Bogs are not swamp")
	check_eq(String(o.region_at(-700.0, -260.0).name), "Sylvenwood", "Sylvenwood is not where the map has it")
	# The rivers run in low valleys all the way down.
	for k in Ostars.RIVERS.size():
		var path: Array = Ostars.RIVERS[k].path
		for i in range(2, path.size()):
			var at: Vector2 = path[i]
			check(float(o.sample(at.x, at.y)[1]) < 6.0, "%s is up on high ground at %s" % [Ostars.RIVERS[k].name, at])
	# The Dragon's Teeth are fangs, and the shaper is a pure function of place.
	var teeth := -INF
	for x in range(700, 2150, 25):
		for z in range(1150, 2050, 25):
			teeth = maxf(teeth, float(o.sample(x, z)[1]))
	check(teeth > 120.0, "the Dragon's Teeth top out at %.0f m" % teeth)
	check_eq(Ostars.new().sample(123.0, -456.0), o.sample(123.0, -456.0), "the same place sampled twice differs")
	done()

## A piece of Ostars round home, as the terrain builds it, for the tests.
func _ostars_patch(half: float) -> Terrain:
	var land := Terrain.new()
	land.half_extent = half
	land.noise_seed = 20260929
	var o := Ostars.new()
	o.configure(land)
	land.reserve_site(Vector3(0, World.PLOT_GROUND, 0), 56.0)
	land.reserve_clear_square(Vector3(0, World.PLOT_GROUND, 0), 50.0, World.PLOT_GROUND, 10.0)
	return land

## The land round the plot is levelled, and the plates that draw the land
## have to follow it: none reaching in over the plot from the rising ground
## round it (which used to lay a slanted plate across half the concrete), and
## none across a levelled build site either.
func test_ostars_level_ground() -> void:
	_setup(false)
	var land := _ostars_patch(420.0)
	land.reserve_site(Vector3(160, NAN, -140), 20.0)
	world.add_child(land)
	await step(2)
	check(land.facets != null, "Ostars is not drawn in plates")
	var highest := -INF
	var lowest := INF
	# The plot at its biggest, and a little past its kerb.
	for x in range(-50, 51, 2):
		for z in range(-50, 51, 2):
			var h := land.height_at(float(x), float(z))
			highest = maxf(highest, h)
			lowest = minf(lowest, h)
	check(highest <= World.PLOT_GROUND + 0.01, "the land comes up to %.2f m over the plot (level %.2f)" % [highest, World.PLOT_GROUND])
	check(lowest >= World.PLOT_GROUND - 0.1, "the land dips to %.2f m under the plot" % lowest)
	# A levelled site: dead level over most of it; toward its edge the grid
	# cells there reach out onto the eased ground, a few centimetres, no more.
	var site: Dictionary = land.build_sites[land.build_sites.size() - 1]
	var c: Vector3 = site.centre
	var inner := 0.0
	var edge := 0.0
	for k in 400:
		var a := float(k) * 2.39996
		var f := sqrt(float(k) / 400.0) * 0.9
		var d := f * float(site.radius)
		var off := absf(land.height_at(c.x + cos(a) * d, c.z + sin(a) * d) - c.y)
		if f <= 0.7:
			inner = maxf(inner, off)
		else:
			edge = maxf(edge, off)
	check(inner < 0.02, "the ground strays %.2f m off the level inside a build site" % inner)
	check(edge < 0.25, "the ground strays %.2f m off the level near a build site's edge" % edge)
	done()

## Grass stands on the ground (its lattice heights are the ground's), grows
## where the ground is green, and not on the roads, the water or the plot's
## concrete; it thins out and stops with distance.
func test_grass_field() -> void:
	_setup(false)
	var land := _ostars_patch(420.0)
	world.add_child(land)
	await step(2)
	var grass := GrassField.new()
	grass.setup(land)
	grass.keep_off = [[Vector3(0, 0, 0), 22.6]]
	world.add_child(grass)
	grass.configure(2, true)
	var at := Vector3(70, land.height_at(70, 70), 70)
	grass.build_around(at)
	check(grass.chunk_count >= 20, "only %d chunks of grass round a point" % grass.chunk_count)
	var grown := 0
	var bad_height := 0
	var on_plot := 0
	var on_water := 0
	var looked := 0
	for key in grass._chunks:
		var c: GrassField.Chunk = grass._chunks[key]
		if c.empty:
			continue
		var img := c.ground.get_image()
		for iz in GrassField.LATTICE + 1:
			for ix in GrassField.LATTICE + 1:
				var x := float(key.x) * GrassField.CHUNK + float(ix) * GrassField.CHUNK / float(GrassField.LATTICE)
				var z := float(key.y) * GrassField.CHUNK + float(iz) * GrassField.CHUNK / float(GrassField.LATTICE)
				var px := img.get_pixel(ix, iz)
				looked += 1
				if absf(px.r - land.height_at(x, z)) > 0.05:
					bad_height += 1
				if px.g > 0.0:
					grown += 1
					if absf(x) <= 22.6 and absf(z) <= 22.6:
						on_plot += 1
					if land.water_depth(x, z) > 0.0 or land.is_road(x, z):
						on_water += 1
	check(looked > 0 and grown * 3 > looked, "grass on only %d of %d points round home" % [grown, looked])
	check_eq(bad_height, 0, "grass lattice points off the ground")
	check_eq(on_plot, 0, "grass growing through the plot's concrete")
	check_eq(on_water, 0, "grass growing in the water or on a road")
	# Near, all of it; further, a half, then a quarter; past the reach, none.
	check_near(grass.keep_at(5.0), 1.0, 0.001, "grass kept at 5 m")
	check(grass.keep_at(35.0) < 0.6 and grass.keep_at(35.0) > 0.25, "grass kept at 35 m: %.2f" % grass.keep_at(35.0))
	check_near(grass.keep_at(58.0), 0.25, 0.001, "grass kept far off")
	# Off: nothing left.
	grass.configure(0, true)
	check_eq(grass.chunk_count, 0, "grass left with grass off")
	done()

## The far stand-ins are the tree's shape in a hundred-odd triangles - leaf
## lumps round a middle for a broadleaf, stacked tiers for a conifer - not
## two stacked prisms; leaves carry alpha 0 and bark 1, for the shader.
func test_tree_stand_ins() -> void:
	for kind in World.SPECIES:
		var mesh := ChoppableTree.stand_in(kind)
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var idx = arrays[Mesh.ARRAY_INDEX]
		var tris := (idx as PackedInt32Array).size() / 3 if idx != null and not (idx as PackedInt32Array).is_empty() else verts.size() / 3
		var name := String(kind.get("name", "?"))
		var style: StringName = kind.get("style", &"cone")
		if style == &"bare":
			continue
		check(tris >= (30 if style == &"palm" else 50) and tris <= 260, "%s's stand-in is %d triangles" % [name, tris])
		var leaves := 0
		var wood := 0
		for c in cols:
			if c.a < 0.5:
				leaves += 1
			else:
				wood += 1
		check(leaves > 0 and wood > 0, "%s's stand-in has %d leaf and %d bark points" % [name, leaves, wood])
		# As tall as the tree, give or take.
		var top := -INF
		for v in verts:
			top = maxf(top, v.y)
		var h := (float(kind.height[0]) + float(kind.height[1])) * 0.5
		check(top > h * 0.8 and top < h * 1.6, "%s's stand-in is %.1f m tall for a %.1f m tree" % [name, top, h])
	done()

## Shaders on: the ground and every merged tree and stand-in drawn with the
## shaders; off: the plain materials, as before.
func test_shaders_switch() -> void:
	_setup(false)
	var land := _region_land()
	world.add_child(land)
	await step(2)
	var tree := ChoppableTree.new()
	tree.manager = manager
	tree.trunk_height = 9.0
	tree.foliage_style = &"ball"
	world.add_child(tree)
	await step(3)
	tree._merge()
	check(tree.is_merged(), "the test tree did not merge")
	var land_mesh: MeshInstance3D = land._land_meshes[0]
	land.set_fancy(true)
	ChoppableTree.set_fancy(true)
	check(land_mesh.material_override is ShaderMaterial, "the ground has no shader with shaders on")
	check(tree._merged.material_override is ShaderMaterial, "the tree has no shader with shaders on")
	land.set_fancy(false)
	ChoppableTree.set_fancy(false)
	check(land_mesh.material_override is StandardMaterial3D, "the ground kept its shader with shaders off")
	check(tree._merged.material_override is StandardMaterial3D, "the tree kept its shader with shaders off")
	ChoppableTree.set_fancy(true)
	done()

## Birds: up in the air over the ground, round whoever they follow, and put
## away at night.
func test_birds() -> void:
	_setup(false)
	var land := _region_land()
	world.add_child(land)
	await step(2)
	var focus := Node3D.new()
	world.add_child(focus)
	focus.global_position = Vector3(-200, land.height_at(-200, 100) + 1.0, 100)
	var birds := Birds.new()
	birds.setup(land)
	birds.focus = focus
	world.add_child(birds)
	for i in 240:
		await get_tree().process_frame
	var low := 0
	var far := 0
	for b: Birds.Bird in birds._birds:
		if b.pos.y < land.height_at(b.pos.x, b.pos.z) + 3.0:
			low += 1
		if Vector2(b.pos.x - focus.global_position.x, b.pos.z - focus.global_position.z).length() > Birds.LEASH + 120.0:
			far += 1
	check(birds._birds.size() >= 20, "only %d birds" % birds._birds.size())
	check_eq(low, 0, "birds flying into the ground")
	check_eq(far, 0, "birds wandered off")
	birds.set_enabled(false)
	check(not birds._mmi.visible, "birds still shown with birds off")
	done()

## Ostars has roads: from the plot to the main street, and one to each of the
## traders and Summit Outfitters, ending just outside their yards.
func test_ostars_roads() -> void:
	var roads := World.ostars_roads()
	check(roads.size() >= 5, "only %d roads on Ostars" % roads.size())
	var ends: Array = []
	for road in roads:
		var pts: Array = road.route if road is Dictionary else road
		ends.append(pts[0])
		ends.append(pts[pts.size() - 1])
	check(ends.has(Vector3(0, 0, 52)), "no road from the plot")
	for key in ["lumber", "metal", "gems", "summit"]:
		var at: Array = Ostars.SITES[key]
		var c := Vector3(float(at[0]), 0, float(at[1]))
		var nearest := INF
		for e: Vector3 in ends:
			nearest = minf(nearest, e.distance_to(c))
		check(nearest < float(at[2]) + 12.0 and nearest > float(at[2]), "the road to %s ends %.0f m from it" % [key, nearest])
	done()

func test_ostars_forest() -> void:
	_setup(false)
	var land := _ostars_patch(420.0)
	world.add_child(land)
	await step(2)
	var o: Ostars = land.shaper
	var forester := Forester.new(land, o, World.SPECIES)
	var grown := forester.grow(1500)
	check(grown > 900, "only %d trees grew round home" % grown)
	check(forester.stands.size() > 20, "the trees are not in stands (%d)" % forester.stands.size())
	# The home wood, a short walk out, of easy trees.
	check(forester.home_wood != Vector3.INF, "no wood by the plot")
	var out := Vector2(forester.home_wood.x, forester.home_wood.z).length()
	check(out >= Forester.HOME_WOOD.near - 1.0 and out <= Forester.HOME_WOOD.far + 1.0,
		"the home wood is %.0f m out" % out)
	check(forester.home_spots.size() >= 40, "the home wood has %d trees" % forester.home_spots.size())
	# Every tree: somewhere it can stand, off the plot, and not in another.
	var all: Array[Vector2] = []
	var bad_wet := 0
	var on_plot := 0
	var off_mix := 0
	for name in forester.spots:
		var kind: Dictionary = forester.kinds[name]
		for p: Vector3 in forester.spots[name]:
			all.append(Vector2(p.x, p.z))
			if land.water_depth(p.x, p.z) > float(kind.get("wet", 0.0)) + 0.05:
				bad_wet += 1
			if land.in_clear_zone(p.x, p.z, 5.0):
				on_plot += 1
			var mix: Dictionary = forester.mix_at(p.x, p.z)
			if not mix.has(name):
				off_mix += 1
	for p in forester.home_spots:
		all.append(Vector2(p.x, p.z))
	check_eq(bad_wet, 0, "trees standing in water too deep for them")
	check_eq(on_plot, 0, "trees on the plot")
	check(float(off_mix) < float(all.size()) * 0.12, "%d of %d trees are not of their country" % [off_mix, all.size()])
	var cells := {}
	var close := 0
	for p in all:
		var c := Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for q: Vector2 in cells.get(Vector2i(c.x + dx, c.y + dz), []):
					if q.distance_to(p) < Forester.SPACING - 0.01:
						close += 1
		if not cells.has(c):
			cells[c] = []
		(cells[c] as Array).append(p)
	check_eq(close, 0, "trees closer than %.1f m" % Forester.SPACING)
	# Thick in the woods, thin in the open: the same ground grows the same forest.
	var again := Forester.new(land, o, World.SPECIES)
	check_eq(again.grow(1500), grown, "the same seed grew a different forest")
	check(forester.wood_at(0.0, 0.0) == 0.0, "trees could grow on the plot")
	done()

func test_ostars_save_map() -> void:
	_setup()
	await step(2)
	var was := WorldMap.current
	var path := "user://test_map.json"
	WorldMap.current = WorldMap.OSTARS
	check(SaveSystem.save_game(plot, null, path), "saving failed")
	check_eq(SaveSystem.summary(path).get("map"), WorldMap.OSTARS, "the save does not say it is Ostars")
	WorldMap.current = WorldMap.ISLES
	check(SaveSystem.save_game(plot, null, path), "saving failed")
	check_eq(SaveSystem.summary(path).get("map"), WorldMap.ISLES, "the save does not say it is the islands")
	# A save from before there were maps is on the islands; nonsense is too.
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 2, "economy": {"day": 2}}))
	f.close()
	check_eq(SaveSystem.summary(path).get("map"), WorldMap.ISLES, "an old save is not on the islands")
	check_eq(WorldMap.valid("atlantis"), WorldMap.ISLES, "an unknown map is not the islands")
	check_eq(WorldMap.valid("ostars"), WorldMap.OSTARS, "ostars is not a map")
	SaveSystem.delete_save(path)
	# An empty slot builds the map chosen for a new game; a used one its own.
	var was_slot := SaveSystem.slot
	var was_chosen := WorldMap.chosen
	SaveSystem.slot = 6
	var slot_path := SaveSystem.slot_path(6)
	var kept := FileAccess.get_file_as_string(slot_path) if FileAccess.file_exists(slot_path) else ""
	SaveSystem.delete_save(slot_path)
	WorldMap.chosen = WorldMap.OSTARS
	WorldMap.pick_for_slot()
	check_eq(WorldMap.current, WorldMap.OSTARS, "a new game is not on the map chosen for it")
	WorldMap.current = WorldMap.ISLES
	check(SaveSystem.save_game(plot, null, slot_path), "saving to slot 6 failed")
	WorldMap.pick_for_slot()
	check_eq(WorldMap.current, WorldMap.ISLES, "a saved game is not built on its own map")
	SaveSystem.delete_save(slot_path)
	if kept != "":
		var back := FileAccess.open(slot_path, FileAccess.WRITE)
		back.store_string(kept)
		back.close()
	SaveSystem.slot = was_slot
	WorldMap.chosen = was_chosen
	WorldMap.current = was
	# The checklist on a map with no yard or store leaves those steps out,
	# and doing the rest still finishes it.
	var t := Tutorial.new()
	t.skip([&"sell", &"store", &"order"])
	check_eq(t.steps.size(), Tutorial.STEPS.size() - 3, "the skipped steps are still on the list")
	for step_def in t.steps:
		check(not [&"sell", &"store", &"order"].has(step_def.id), "%s is still on the list" % step_def.id)
	t.free()
	done()

func test_ostars_ore() -> void:
	_setup(false)
	var land := _ostars_patch(420.0)
	world.add_child(land)
	await step(2)
	var pro := Prospector.new(land, land.shaper)
	check(pro.hardness(0.0, 60.0) < 1.0, "home is hard country (%.2f)" % pro.hardness(0.0, 60.0))
	var found := {}
	for entry in pro.survey(4):
		found[entry[0]] = (entry[1] as PackedVector3Array).size()
	check(int(found.get(&"ore_tin", 0)) > 20, "no tin round home")
	check(int(found.get(&"gem_quartz", 0)) > 20, "no quartz round home")
	check(int(found.get(&"ore_gold", 0)) == 0, "gold in the easy country round home")
	check(int(found.get(&"ore_platinum", 0)) == 0, "platinum round home")
	# Up Orodruin the country is as hard as it gets.
	var o: Ostars = land.shaper
	check(o.sample(-1060.0, -1000.0)[1] > 150.0, "Orodruin is not up there")
	done()

func test_trader_models() -> void:
	_setup(false)
	for role in [NpcFigure.Role.LUMBERMAN, NpcFigure.Role.MINER, NpcFigure.Role.GRANNY, NpcFigure.Role.HELPER]:
		var f := NpcFigure.new(role, "x")
		world.add_child(f)
		await step(2)
		var who := String(NpcFigure.Role.keys()[role])
		check(f.model != null, "%s has no model" % who)
		for n in [&"Torso", &"Head", &"Hand_R", &"Knee_L", &"Finger_R2"]:
			check(f._part.has(n), "%s has no %s" % [who, n])
		if role == NpcFigure.Role.MINER or role == NpcFigure.Role.LUMBERMAN:
			check(f._tool != null and f._tool.get_parent() == f._part[&"Hand_R"], "%s's tool is not in his hand" % who)
		if role == NpcFigure.Role.GRANNY:
			check(f._chair != null, "Granny has no rocking chair")
			check(f.state == &"rock", "Granny is not rocking")
		check(f.body != null, "%s has nothing to aim at" % who)
	# The miner's day: work, then pace or rest, and back to work.
	var m := NpcFigure.new(NpcFigure.Role.MINER, "Dusty")
	m.post = Vector3(5, 0, 0)
	m.position = m.post
	m.work_at = Vector3(5, 0, -1.2)
	m.pace_to = Vector3(5, 0, 5)
	world.add_child(m)
	var hits := [0]
	m.struck.connect(func(_at: Vector3): hits[0] += 1)
	var seen := {}
	for i in 60 * 40:
		await get_tree().process_frame
		seen[m.state] = true
		if seen.has(&"rest") and seen.has(&"pace") and hits[0] > 3:
			break
	check(hits[0] > 3, "the miner never struck his rock")
	check(seen.has(&"rest") or seen.has(&"pace"), "the miner never took a break (%s)" % [seen.keys()])
	done()

func test_trader_yards() -> void:
	_setup(false)
	var yard := SellYard.new()
	yard.setup(manager)
	yard.accepts = [&"gem", &"jewel"]
	yard.keeper = "Granny Opal"
	yard.npc = NpcFigure.new(NpcFigure.Role.GRANNY, "Granny Opal")
	world.add_child(yard)
	await step(2)
	var gem := spawn(&"gem_quartz", Vector3(1, 1, 1))
	var log := spawn(&"wood_pine", Vector3(-2, 1, 1))
	for item in [gem, log]:
		item.owned = true
	await step(30)
	check(yard.stock().has(gem), "Granny does not want the quartz")
	check(not yard.stock().has(log), "Granny wants the log")
	var money := Economy.money
	var sold := yard.sell_all()
	check_eq(int(sold.count), 1, "Granny bought the wrong things")
	check(Economy.money > money, "Granny did not pay")
	check(is_instance_valid(log) and log.state != LooseItem.State.POOLED, "the log was taken")
	check(yard.npc.saying() != "", "Granny said nothing as she paid")
	done()

func _post(kind: TradePost.Kind) -> TradePost:
	var tp := TradePost.new()
	tp.setup(kind, manager)
	tp.ground = func(_x: float, _z: float) -> float: return 0.0
	return tp

func test_trader_order() -> void:
	_setup(false)
	manager.per_plot_cap = 800
	var tp := _post(TradePost.Kind.METAL)
	world.add_child(tp)
	await step(5)
	check(tp.counter != null and tp.helper != null, "the assay office has no counter or no helper")
	# A truck backed into the bay.
	var truck := Hauler.new()
	truck.setup(manager, 0, &"pickup")
	world.add_child(truck)
	truck.global_position = tp.to_global(TradePost.BAY_CENTRE) + Vector3(0, truck.spawn_height(), 0)
	await step(30)
	Economy.from_dict({"money": 100000, "day": 1})
	var price := tp.counter.price_of(&"ingot_iron")
	check(price > Economy.price_of(&"ingot_iron"), "buying is no dearer than selling")
	var msg := tp.counter.order(&"ingot_iron", 8)
	check(msg.begins_with("ordered"), "the order was refused: %s" % msg)
	check_eq(Economy.money, 100000 - price * 8, "the order was not paid for")
	check_eq(tp.queued(), 8, "the order is not waiting to go out")
	var frames := 0
	while tp.queued() > 0 and frames < 60 * 60:
		await get_tree().process_frame
		frames += 1
	await step(60)
	check_eq(tp.queued(), 0, "the helper never finished loading")
	var in_bed := 0
	for item in manager.owned_items():
		if item.item_id != &"ingot_iron":
			continue
		var local := truck.to_local(item.global_position)
		if absf(local.x) < truck.bed_half_width + 0.3 and local.z > truck.bed_front - 0.3 and local.z < truck.bed_back + 0.3:
			in_bed += 1
	check_eq(in_bed, 8, "not everything went into the truck")
	# No truck: onto the bay floor. And too dear: refused, nothing taken.
	truck.queue_free()
	await step(10)
	Economy.from_dict({"money": 5, "day": 1})
	check(not tp.counter.order(&"ingot_gold", 25).begins_with("ordered"), "an order it could not pay for went through")
	check_eq(Economy.money, 5, "money went on an order that was refused")
	done()

func test_bjorns_tree() -> void:
	_setup(false)
	var tp := _post(TradePost.Kind.LUMBER)
	var pine: Dictionary = {}
	for kind in World.SPECIES:
		if kind.name == "Pine":
			pine = kind
	tp.tree_builder = func(form_seed: int) -> Node3D:
		var t := ChoppableTree.new()
		t.manager = manager
		t.wood_item = pine.item
		t.species = "Pine"
		t.seed_form(form_seed)
		t.trunk_height = 8.0
		t.trunk_radius = 0.3
		return t
	world.add_child(tp)
	await step(10)
	check(tp.tree != null, "Old Bjorn has no tree")
	check(tp.keeper.state == &"work", "Old Bjorn is not working (%s)" % tp.keeper.state)
	tp.tree.fell(Vector3(10, 0, 0))
	await step(5)
	check(tp.keeper.state == &"angry", "Old Bjorn does not mind his tree being felled (%s)" % tp.keeper.state)
	check(NpcFigure.GRUMBLES.has(tp.keeper.saying()), "Old Bjorn said nothing (%s)" % tp.keeper.saying())
	# It grows back, and he gets back to it.
	tp._regrow = 0.05
	await step(20)
	check(tp.tree != null and is_instance_valid(tp.tree) and tp.tree.standing(), "his tree did not grow back")
	for i in 60 * 6:
		await get_tree().process_frame
		if tp.keeper.state == &"work":
			break
	check(tp.keeper.state == &"work", "Old Bjorn did not go back to work (%s)" % tp.keeper.state)
	done()
