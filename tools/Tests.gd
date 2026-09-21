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
	await _test(&"bucking splits wood and conserves volume", test_bucking)
	await _test(&"mining a rock yields ore", test_mine)
	await _test(&"sawmill mills wood and conserves volume", test_sawmill)
	await _test(&"furnace smelts ore into billets", test_furnace)
	await _test(&"workbench assembles from volumes", test_workbench)
	await _test(&"machines reject items they cannot use", test_machine_rejects)
	await _test(&"sell zone pays today's price", test_sell_zone)
	await _test(&"storage bin stores and dispenses", test_storage)
	await _test(&"conveyor feeds a machine directly", test_conveyor_to_machine)
	await _test(&"splitter routes round-robin", test_splitter)
	await _test(&"filter sorts items by type", test_filter)
	await _test(&"building placement, cost and removal", test_building)
	await _test(&"save/load round-trip", test_save_load)
	await _test(&"plot expansion raises bounds and cap", test_expansion)
	await _test(&"tool upgrades apply and charge", test_upgrades)
	await _test(&"carry rack limits and deposits", test_carry)
	await _test(&"lift and drag limits are weight limits", test_handling_limits)
	await _test(&"ownership is tracked and saved", test_ownership)
	await _test(&"hauler drives, carries and stays upright", test_hauler)
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
	_current = String(name)
	var before := _failures.size()
	await fn.call()
	_teardown()
	var status := "ok  " if _failures.size() == before else "FAIL"
	_say("  [%s] %s" % [status, _current])

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
		check(m.intake_hole.x > 0.1 and m.intake_hole.y > 0.1, "machine %s has no intake hole" % m.id)
		check(m.outlet_hole.x > 0.1 and m.outlet_hole.y > 0.1, "machine %s has no outlet hole" % m.id)
		if m.mode != MachineDef.MODE_ASSEMBLE:
			check(not m.conversion.is_empty(), "machine %s converts nothing" % m.id)
			check(m.cross_section.x > 0.0 and m.cross_section.y > 0.0,
				"machine %s has no output cross-section" % m.id)
	for def: BuildingDef in GameData.buildings.values():
		check(def.cost > 0, "building %s is free" % def.id)

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

func test_chop() -> void:
	_setup()
	var tree := ChoppableTree.new()
	tree.manager = manager
	tree.max_health = 100.0
	tree.wood_item = &"wood_pine"
	tree.trunk_height = 7.0
	tree.trunk_radius = 0.34
	tree.trunk_taper = 0.6
	tree.branch_count = 4
	tree.respawn_seconds = 0.0
	tree.position = Vector3(0, 0, 0)
	world.add_child(tree)
	await step(2)
	check_eq(manager.active_count(), 0, "wood existed before chopping")

	var grown_volume := tree.wood_volume()
	var felled := tree.chop(60.0, Vector3(0, 0, 5))
	check(not felled, "tree fell in one hit when it should not have")
	check_near(tree.health, 40.0, 0.01, "damage was not applied")
	felled = tree.chop(60.0, Vector3(0, 0, 5))
	check(felled, "tree did not fall when health hit zero")
	await step(2)

	# The trunk must arrive as one piece, exactly the shape it grew to - not as
	# a pile of pre-cut logs.
	check_eq(manager.active_count(), 1 + tree.branch_count, "felling produced the wrong piece count")
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

func test_bucking() -> void:
	_setup()
	var player := _make_player()
	world.add_child(player)
	await step(2)
	PlayerState.levels[&"axe"] = 1

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

func test_mine() -> void:
	_setup()
	var rock := OreRock.new()
	rock.manager = manager
	rock.max_health = 50.0
	rock.ore_item = &"ore_copper"
	rock.ore_count = 3
	rock.respawn_seconds = 0.0
	world.add_child(rock)
	await step(2)
	check(not rock.mine(20.0, Vector3.ZERO), "rock broke too early")
	check(rock.mine(40.0, Vector3.ZERO), "rock did not break")
	await step(2)
	check_eq(manager.active_count(), 3, "wrong amount of ore spawned")

func test_sawmill() -> void:
	_setup()
	var mill := Machine.new()
	mill.setup(manager, GameData.building(&"sawmill"), 0)
	world.add_child(mill)
	await step(2)
	var machine_def: MachineDef = mill.machine_def

	# Feed it one fat log and one long thin one.
	var fed := 0.0
	for dims in [Solid.cylinder(0.30, 0.26, 2.2), Solid.cylinder(0.16, 0.14, 3.4)]:
		var log_piece := manager.spawn(&"wood_pine", Transform3D(Basis(), mill.input_point()),
			0, Vector3.ZERO, dims)
		fed += log_piece.volume()
		await step(12)
	await step(20)
	check_near(mill.volume_in, fed, 0.0001, "the sawmill did not measure what it was fed")
	check_eq(loose_volume(&"wood_pine"), 0.0, "wood was left sitting in the intake")

	# Milling takes real time, proportional to volume.
	var expected_seconds: float = fed / machine_def.m3_per_second
	check(expected_seconds > 2.0, "test volume is too small to time")
	await step(int(expected_seconds * 60.0) + 120)

	check(mill.total_produced > 0, "the sawmill produced nothing")
	check_near(mill.volume_out, fed, 0.001,
		"volume was not conserved: %.4f in, %.4f out" % [mill.volume_in, mill.volume_out])
	check_near(loose_volume(&"lumber_pine"), fed, 0.001,
		"the lumber on the ground does not add up to the wood that went in")

	# Every board matches the outlet, and none is longer than the machine cuts.
	for item in manager.free_items():
		if item.item_id != &"lumber_pine":
			continue
		var size: Vector3 = item.dims.size
		check_near(size.x, machine_def.cross_section.x, 0.0001, "board is not the width of the outlet")
		check_near(size.z, machine_def.cross_section.y, 0.0001, "board is not the height of the outlet")
		check(size.y <= machine_def.max_piece_length + 0.0001,
			"board is longer than the machine cuts (%.2f m)" % size.y)
	# A bigger log must yield more board, not more pieces of the same board.
	check(mill.total_produced >= 2, "a 5.6 m of log should not come out as one short board")

func test_furnace() -> void:
	_setup()
	var furnace := Machine.new()
	furnace.setup(manager, GameData.building(&"furnace"), 0)
	world.add_child(furnace)
	await step(2)
	var machine_def: MachineDef = furnace.machine_def
	check_eq(machine_def.intake_face, &"top", "the furnace should be fed from the top")
	check(machine_def.outlet_face != &"top", "the furnace should not pour out of its own lid")

	var fed := 0.0
	for i in 2:
		var ore := manager.spawn(&"ore_iron", Transform3D(Basis(), furnace.input_point()), 0)
		fed += ore.volume()
		await step(10)
	await step(30)
	check_near(furnace.volume_in, fed, 0.0001, "the furnace did not take both ore pieces")

	await step(int(fed / machine_def.m3_per_second * 60.0) + 180)
	check_near(furnace.volume_out, fed, 0.001,
		"smelting did not conserve volume: %.4f in, %.4f out" % [furnace.volume_in, furnace.volume_out])
	var billets := 0
	for item in manager.free_items():
		if item.item_id != &"ingot_iron":
			continue
		billets += 1
		var size: Vector3 = item.dims.size
		check_near(size.x, machine_def.cross_section.x, 0.0001, "billet is not the width of the outlet")
		check(size.y <= machine_def.max_piece_length + 0.0001, "billet is too long to leave the outlet")
		check(size.y > size.x * 0.5, "billet should be a bar, not a cube")
	check(billets > 0, "the furnace produced no billets")

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

func test_machine_rejects() -> void:
	_setup()
	var mill := Machine.new()
	mill.setup(manager, GameData.building(&"sawmill"), 0)
	world.add_child(mill)
	await step(2)
	check(not mill.can_accept(&"ore_iron"), "sawmill claims it can mill ore")
	check(mill.can_accept(&"wood_oak"), "sawmill refuses a wood it should accept")
	var ore := manager.spawn(&"ore_iron", Transform3D(Basis(), mill.input_point()), 0)
	await step(40)
	check_eq(mill.queue.size(), 0, "sawmill swallowed an item it cannot process")
	check(is_instance_valid(ore) and ore.state == LooseItem.State.FREE,
		"the rejected ore was destroyed")
	check_near(mill.volume_in, 0.0, 0.0001, "sawmill counted material it refused")

func test_sell_zone() -> void:
	_setup()
	var zone := SellZone.new()
	zone.setup(manager)
	zone.extents = Vector3(4, 2, 4)
	world.add_child(zone)
	await step(2)
	Economy.from_dict({"money": 0, "day": 3})
	var price := Economy.price_of(&"lumber_oak")
	spawn(&"lumber_oak", Vector3(0, 1.0, 0))
	await step(30)
	check_eq(Economy.money, price, "sell zone paid the wrong amount")
	check_eq(manager.active_count(), 0, "sold item was not removed")

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

func test_conveyor_to_machine() -> void:
	_setup()
	var mill := Machine.new()
	mill.setup(manager, GameData.building(&"sawmill"), 0)
	mill.position = Vector3(0, 0, -8)   # intake face (+Z) looks back at the belt
	world.add_child(mill)
	var belt := Conveyor.new()
	belt.mode = Conveyor.Mode.KINEMATIC
	belt.length = 8.0
	belt.speed = 4.0
	belt.position = Vector3(0, 0.6, 2.0)
	belt.sink_finder = func(pos: Vector3) -> Object:
		return mill if pos.distance_to(mill.input_point()) < 7.0 else null
	world.add_child(belt)
	await step(2)
	for i in 3:
		spawn(&"wood_pine", Vector3(0, 1.2, 5.6))
		await step(20)
	await step(150)
	check(belt.total_delivered >= 3, "belt delivered %d of 3 items" % belt.total_delivered)
	check(mill.volume_in > 0.0, "belt did not hand anything to the machine")

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

func test_save_load() -> void:
	_setup()
	await step(2)
	Economy.from_dict({"money": 50000, "day": 4})
	PlayerState.try_upgrade(&"axe")
	PlayerState.try_unlock(&"furnace")
	plot.place(GameData.building(&"sawmill"), Vector2i(0, 0), 0)
	plot.place(GameData.building(&"conveyor"), Vector2i(-6, 0), 1)
	plot.place(GameData.building(&"storage"), Vector2i(4, -6), 0)
	await step(2)
	var mill: Machine = plot.machines()[0]
	mill.queue.append({"output_id": &"lumber_pine", "volume": 0.42})
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
	check_eq(PlayerState.level(&"axe"), 2, "upgrades did not survive the round-trip")
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

func test_upgrades() -> void:
	_setup(false)
	PlayerState.reset()
	Economy.from_dict({"money": 0, "day": 1})
	var base_damage := PlayerState.stat(&"axe", "damage")
	check(not PlayerState.try_upgrade(&"axe"), "upgraded with no money")
	Economy.from_dict({"money": 100000, "day": 1})
	var cost := PlayerState.next_cost(&"axe")
	check(PlayerState.try_upgrade(&"axe"), "could not buy an affordable upgrade")
	check_eq(Economy.money, 100000 - cost, "upgrade charged the wrong amount")
	check(PlayerState.stat(&"axe", "damage") > base_damage, "upgrade did not improve the axe")
	while not PlayerState.at_max(&"axe"):
		PlayerState.try_upgrade(&"axe")
	check(not PlayerState.try_upgrade(&"axe"), "bought past the last level")
	check_eq(PlayerState.next_cost(&"axe"), -1, "maxed track still reports a cost")

func test_carry() -> void:
	_setup()
	var player := _make_player()
	world.add_child(player)
	var mill := Machine.new()
	mill.setup(manager, GameData.building(&"sawmill"), 0)
	mill.position = Vector3(0, 0, -10)
	world.add_child(mill)
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

	var moved := player.deposit_into(mill)
	check_eq(moved, 2, "depositing into the sawmill moved %d pieces" % moved)
	check_eq(player.carried_count(), 0, "rack not emptied after depositing")
	check(mill.volume_in > 0.0, "machine did not receive the deposit")

	var third := spawn(&"wood_pine", Vector3(3, 1, 1), small)
	player.pick_up(third)
	player._drop(1)
	await step(10)
	check_eq(third.state, LooseItem.State.FREE, "dropped item is not free again")

## Spec: the player lifts up to 100 kg and moves up to 1000 kg. Both limits are
## about weight, so the same shape in a denser wood stops being liftable.
func test_handling_limits() -> void:
	_setup()
	var player := _make_player()
	world.add_child(player)
	await step(4)
	check_near(player.lift_limit_kg(), 100.0, 0.001, "starting lift limit is not 100 kg")
	check_near(player.move_limit_kg(), 1000.0, 0.001, "drag limit is not 1000 kg")

	# One rack level for the rest, with bulk and length kept inside their own
	# limits so weight is the only thing that can refuse a piece.
	PlayerState.levels[&"carry"] = 4
	var lift := player.lift_limit_kg()
	check_near(lift, 420.0, 0.001, "level 4 lift limit is wrong")

	# Pine at 150 kg/m3: 1.39 m3 is 208 kg, inside every limit.
	var light := spawn(&"wood_pine", Vector3(1, 1, 0), Solid.cylinder(0.42, 0.42, 2.5))
	check(light.mass < lift, "light test piece is %.0f kg, expected under %.0f" % [light.mass, lift])
	check(light.volume() < player.capacity_m3(), "light test piece does not fit the rack by bulk")
	check(light.length() < player.max_piece_length(), "light test piece is too long for the rack")
	check(player.pick_up(light), "a %.0f kg piece would not go on the rack" % light.mass)
	player._drop(1)
	await step(4)

	# Ironwood at 320 kg/m3: the same shape is 443 kg - over the lift limit,
	# well under the drag limit, so it has to be dragged rather than carried.
	var heavy := spawn(&"wood_ironwood", Vector3(3, 1, 0), Solid.cylinder(0.42, 0.42, 2.5))
	check(heavy.mass > lift and heavy.mass < 1000.0,
		"heavy test piece is %.0f kg, expected between %.0f and 1000" % [heavy.mass, lift])
	check(heavy.length() <= player.max_piece_length(), "heavy test piece is refused on length")
	check(heavy.volume() <= player.capacity_m3(), "heavy test piece is refused on bulk")
	check(not player.pick_up(heavy), "the rack lifted %.0f kg past a %.0f kg limit" % [heavy.mass, lift])
	player.dragged = null
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
	var mill := Machine.new()
	mill.setup(manager, GameData.building(&"sawmill"), 0)
	mill.position = Vector3(0, 0, -12)
	world.add_child(mill)
	await step(4)
	mill.accept_item(spawn(&"wood_pine", Vector3(0, 1, -12), Solid.cylinder(0.2, 0.2, 1.0)))
	for i in 240:
		await step(1)
		if mill.total_produced > 0:
			break
	check(mill.total_produced > 0, "sawmill produced nothing")
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

	var loaded := 0.0
	for i in 4:
		var piece := spawn(&"wood_pine", truck.global_position + Vector3(0, 2.0 + float(i) * 0.4, 0.6),
			Solid.cylinder(0.18, 0.16, 1.6))
		loaded += piece.volume()
	await step(45)
	check_eq(truck.cargo_count(), 4, "hauler did not take the load aboard")
	check_near(truck.cargo_volume(), loaded, 0.0001, "hauler miscounted its load")
	check(truck.cargo_capacity_m3 > loaded, "test load should fit well inside the bed")
	# Loaded cargo must leave the physics world entirely: no bodies to bounce,
	# be grabbed, be sold or be knocked off.
	check_eq(manager.active_count(), 0, "cargo is still a loose physics body after loading")

	var start := truck.global_position
	truck.autopilot = true
	truck.input_throttle = 1.0
	await step(150)
	var travelled: float = start.distance_to(truck.global_position)
	check(travelled > 6.0, "hauler barely moved under throttle (%.1f m)" % travelled)
	check(truck.linear_velocity.length() <= truck.max_speed * 1.5, "hauler exceeded its speed cap")
	check(truck.global_transform.basis.y.dot(Vector3.UP) > 0.7, "hauler rolled while driving")
	check_eq(truck.cargo_count(), 4, "hauler lost cargo while driving")
	check_eq(manager.active_count(), 0, "something fell out of the bed while driving")

	# The load rides exactly with the hull, whatever happens to the hull.
	var cargo_props := 0
	var wheels := 0
	for child in truck.get_children():
		var prop := child as MeshInstance3D
		if prop == null:
			continue
		if prop.mesh is CylinderMesh and prop.position.y < 0.0:
			wheels += 1
		elif prop.mesh is CylinderMesh and prop.position.y > 0.3:
			cargo_props += 1
	check(cargo_props == 4, "expected 4 cargo props on the hull, saw %d" % cargo_props)
	check(wheels >= 4, "the hauler should have wheels, found %d" % wheels)

	# Slam it into the boundary wall at full speed, then flip it upside down and
	# spin it: nothing may come loose.
	truck.input_throttle = 1.0
	await step(240)
	check_eq(truck.cargo_count(), 4, "cargo was lost in a collision")
	PhysicsServer3D.body_set_state(truck.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM,
		Transform3D(Basis.from_euler(Vector3(PI, 0, 0)), truck.global_position + Vector3(0, 4, 0)))
	truck.angular_velocity = Vector3(6, 6, 6)
	await step(90)
	check_eq(truck.cargo_count(), 4, "cargo was lost in a rollover")
	check_eq(manager.active_count(), 0, "a rollover shook an item loose")
	truck.recover()
	await step(30)
	check_eq(truck.cargo_count(), 4, "cargo was lost when the truck was recovered")

	# Cargo survives a save/load round-trip as part of the vehicle.
	var doc := truck.to_dict()
	truck.cargo_items.clear()
	truck._rebuild_props()
	truck.from_dict(doc)
	check_eq(truck.cargo_count(), 4, "cargo did not survive a save/load round-trip")

	truck.input_throttle = 0.0
	await step(30)
	var dropped := truck.unload()
	check_eq(dropped, 4, "unloading returned the wrong count")
	await step(20)
	check_eq(truck.cargo_count(), 0, "hauler still holds cargo after unloading")
	var returned := manager.free_items()
	check_eq(returned.size(), 4, "unloaded cargo did not come back as real items")
	check_near(loose_volume(), loaded, 0.0001, "the hauler gave back a different volume than it took")
	for item in returned:
		check_eq(item.item_id, &"wood_pine", "unloaded item changed type")

	# One-at-a-time unloading, and the sink protocol the player and belts use.
	truck.load_item(&"ore_iron")
	truck.load_item(&"ore_iron")
	check_eq(truck.cargo_count(), 2, "load_item did not stack the load")
	check(truck.unload_one(), "could not drop a single item")
	check_eq(truck.cargo_count(), 1, "drop-one removed the wrong amount")
	check(truck.can_accept(&"lumber_pine"), "hauler refuses items while it has room")
	truck.cargo_capacity_m3 = 0.001
	check(not truck.can_accept(&"lumber_pine"), "hauler accepts items when full")

func test_kill_plane() -> void:
	_setup()
	await step(2)
	var item := spawn(&"wood_pine", Vector3(0, 2, 0))
	item.teleport(Transform3D(Basis(), Vector3(0, Tuning.KILL_PLANE_Y - 10.0, 0)))
	await step(6)
	check(item.global_position.y > Tuning.KILL_PLANE_Y,
		"item below the kill plane was not rescued (y=%.1f)" % item.global_position.y)
	check(manager.stat_killplane > 0, "kill-plane rescue was not counted")

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

func test_full_base() -> void:
	_setup()
	await step(2)
	Economy.from_dict({"money": 200000, "day": 1})
	PlayerState.reset()
	# A plausible mid-game base: two sawmills, a furnace, belts, a splitter,
	# storage and a sell chute, all running at once.
	plot.place(GameData.building(&"sawmill"), Vector2i(-10, -8), 0)
	plot.place(GameData.building(&"sawmill"), Vector2i(-4, -8), 0)
	PlayerState.try_unlock(&"furnace")
	plot.place(GameData.building(&"furnace"), Vector2i(2, -8), 0)
	plot.place(GameData.building(&"splitter"), Vector2i(0, 0), 0)
	plot.place(GameData.building(&"storage"), Vector2i(8, 2), 0)
	plot.place(GameData.building(&"conveyor"), Vector2i(-10, 2), 0)
	plot.place(GameData.building(&"conveyor"), Vector2i(-2, 2), 0)
	plot.place(GameData.building(&"conveyor"), Vector2i(4, 2), 0)
	PlayerState.try_unlock(&"sell_chute")
	var chute := plot.place(GameData.building(&"sell_chute"), Vector2i(10, -8), 0)
	check(chute != null, "could not place the sell chute")
	check_eq(plot.placed.size(), 9, "test base was not fully built")
	await step(10)

	var money_before := Economy.money
	var samples: PackedFloat32Array = PackedFloat32Array()
	var prev := Time.get_ticks_usec()
	for i in 600:
		if i % 6 == 0:
			# Fed through the real intakes, so the base is actually running.
			for m in plot.machines():
				var feed: StringName = &"wood_pine" if m.def.machine == &"sawmill" else &"ore_iron"
				var dims := Solid.cylinder(0.2, 0.17, randf_range(1.2, 2.6)) if feed == &"wood_pine" else {}
				manager.spawn(feed, Transform3D(Basis(), m.input_point()), 0, Vector3.ZERO, dims)
		if i % 30 == 0 and chute != null:
			# Stand in for a belt feeding the chute, so the sell path is exercised.
			spawn(&"lumber_pine", chute.global_position + Vector3(0, 2.0, 0))
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
	var produced := 0
	for m in plot.machines():
		produced += m.total_produced
	check(produced > 0, "no machine produced anything in the running base")
	check(Economy.money != money_before, "the base earned nothing (sell chute never fired)")

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
