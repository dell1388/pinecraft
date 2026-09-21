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
	await _test(&"chopping a tree yields logs", test_chop)
	await _test(&"mining a rock yields ore", test_mine)
	await _test(&"sawmill converts logs to planks", test_sawmill)
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

func spawn(item_id: StringName, pos: Vector3) -> LooseItem:
	return manager.spawn(item_id, Transform3D(Basis(), pos), 0)

# --- Tests -----------------------------------------------------------------

func test_data_integrity() -> void:
	check(GameData.load_errors.is_empty(),
		"data tables have errors: %s" % ", ".join(GameData.load_errors))
	check(GameData.items.size() >= 10, "expected a real item table")
	check(GameData.recipes.size() >= 6, "expected a real recipe table")
	for def: ItemDef in GameData.items.values():
		check(def.base_value > 0, "item %s has no value" % def.id)
		check(def.mass > 0.0, "item %s has no mass" % def.id)
	for r: RecipeDef in GameData.recipes.values():
		check(not r.inputs.is_empty(), "recipe %s has no inputs" % r.id)
		check(not r.outputs.is_empty(), "recipe %s has no outputs" % r.id)
		check(r.seconds > 0.0, "recipe %s is instant" % r.id)
	for def: BuildingDef in GameData.buildings.values():
		check(def.cost > 0, "building %s is free" % def.id)

func test_prices() -> void:
	Economy.from_dict({"money": 0, "day": 7})
	var first := Economy.price_of(&"log_pine")
	var again := Economy.price_of(&"log_pine")
	check_eq(first, again, "price is not stable within a day")
	var day7_multiplier := Economy.price_multiplier(&"log_oak")
	Economy.from_dict({"money": 0, "day": 8})
	var day8_multiplier := Economy.price_multiplier(&"log_oak")
	Economy.from_dict({"money": 0, "day": 7})
	check_near(Economy.price_multiplier(&"log_oak"), day7_multiplier, 0.0001,
		"price for a given day is not reproducible")
	check(absf(day8_multiplier - day7_multiplier) > 0.0001, "prices never change between days")
	# A day's prices must stay in a sane band, or the economy is meaningless.
	for row in Economy.market_rows():
		check(row.multiplier >= 0.35 and row.multiplier <= 2.4,
			"price multiplier out of band for %s" % row.name)
		check(row.price >= 1, "price below 1 for %s" % row.name)

func test_chop() -> void:
	_setup()
	var tree := ChoppableTree.new()
	tree.manager = manager
	tree.max_health = 100.0
	tree.log_count = 5
	tree.log_item = &"log_pine"
	tree.respawn_seconds = 0.0
	tree.position = Vector3(0, 0, 0)
	world.add_child(tree)
	await step(2)
	check_eq(manager.active_count(), 0, "logs existed before chopping")
	var felled := tree.chop(60.0, Vector3(0, 0, 5))
	check(not felled, "tree fell in one hit when it should not have")
	check_near(tree.health, 40.0, 0.01, "damage was not applied")
	felled = tree.chop(60.0, Vector3(0, 0, 5))
	check(felled, "tree did not fall when health hit zero")
	await step(2)
	check_eq(manager.active_count(), 5, "wrong number of logs spawned")
	for item in manager.free_items():
		check_eq(item.item_id, &"log_pine", "wrong item spawned by tree")

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
	mill.position = Vector3(0, 0, 0)
	world.add_child(mill)
	await step(2)
	# Two logs into the hopper.
	var mouth: Vector3 = mill.global_position + Vector3(0, 2.6, 2.6)
	spawn(&"log_pine", mouth)
	spawn(&"log_pine", mouth + Vector3(0.2, 0.6, 0))
	await step(45)
	var loose_logs := 0
	for item in manager.free_items():
		if item.item_id == &"log_pine":
			loose_logs += 1
	check_eq(loose_logs, 0, "sawmill left logs lying in its hopper")
	await step(260)
	check(mill.total_produced >= 2, "sawmill produced nothing (produced %d)" % mill.total_produced)
	var planks := 0
	for item in manager.free_items():
		if item.item_id == &"plank_pine":
			planks += 1
	check(planks >= 2, "planks were not spawned at the output (found %d)" % planks)

func test_machine_rejects() -> void:
	_setup()
	var mill := Machine.new()
	mill.setup(manager, GameData.building(&"sawmill"), 0)
	world.add_child(mill)
	await step(2)
	check(not mill.can_accept(&"ore_iron"), "sawmill claims it can smelt ore")
	var ore := spawn(&"ore_iron", mill.global_position + Vector3(0, 2.6, 2.6))
	await step(40)
	check_eq(mill.buffer.size(), 0, "sawmill swallowed an item it cannot process")
	check(is_instance_valid(ore) and ore.state == LooseItem.State.FREE,
		"the rejected ore was destroyed")

func test_sell_zone() -> void:
	_setup()
	var zone := SellZone.new()
	zone.setup(manager)
	zone.extents = Vector3(4, 2, 4)
	world.add_child(zone)
	await step(2)
	Economy.from_dict({"money": 0, "day": 3})
	var price := Economy.price_of(&"plank_oak")
	spawn(&"plank_oak", Vector3(0, 1.0, 0))
	await step(30)
	check_eq(Economy.money, price, "sell zone paid the wrong amount")
	check_eq(manager.active_count(), 0, "sold item was not removed")

func test_storage() -> void:
	_setup()
	var bin := StorageBin.new()
	bin.setup(manager, GameData.building(&"storage"), 0)
	world.add_child(bin)
	await step(2)
	for i in 5:
		spawn(&"ingot_iron", bin.global_position + Vector3(0, 2.6 + float(i) * 0.3, 0))
	await step(40)
	check_eq(bin.count(), 5, "bin did not absorb the items")
	check_eq(manager.active_count(), 0, "items still loose after storage")
	var queued := bin.dispense_all()
	check_eq(queued, 5, "dispense queued the wrong count")
	await step(80)
	check_eq(manager.active_count(), 5, "bin did not pour the items back out")
	check_eq(bin.count(), 0, "bin still reports contents after emptying")

func test_conveyor_to_machine() -> void:
	_setup()
	var mill := Machine.new()
	mill.setup(manager, GameData.building(&"sawmill"), 0)
	mill.position = Vector3(0, 0, -6)
	mill.rotation.y = PI          # hopper faces the belt
	world.add_child(mill)
	var belt := Conveyor.new()
	belt.mode = Conveyor.Mode.KINEMATIC
	belt.length = 8.0
	belt.speed = 4.0
	belt.position = Vector3(0, 0.6, 2.0)
	belt.sink_finder = func(pos: Vector3) -> Object:
		return mill if pos.distance_to(mill.global_position) < 6.0 else null
	world.add_child(belt)
	await step(2)
	for i in 3:
		spawn(&"log_pine", Vector3(0, 1.2, 5.6))
		await step(20)
	await step(150)
	check(belt.total_delivered >= 3, "belt delivered %d of 3 items" % belt.total_delivered)
	var buffered: int = int(mill.buffer.get(&"log_pine", 0))
	check(buffered + mill.total_produced > 0, "belt did not hand anything to the machine")

func test_splitter() -> void:
	_setup()
	var splitter := Splitter.new()
	splitter.setup(GameData.building(&"splitter"))
	splitter.position = Vector3(0, 0.6, 0)
	world.add_child(splitter)
	await step(2)
	for i in 6:
		spawn(&"plank_pine", Vector3(0, 1.1, 0))
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
	filter.filter_item = &"plank_pine"
	filter.position = Vector3(0, 0.6, 0)
	world.add_child(filter)
	await step(2)
	for i in 4:
		spawn(&"plank_pine", Vector3(0, 1.1, 0))
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
		if item.item_id == &"plank_pine":
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
	var plank := spawn(&"plank_pine", Vector3(0, 1.1, 0))
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
	mill.buffer[&"log_pine"] = 3
	mill.total_produced = 7
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
		# The restored mill starts working immediately, so a log may already be
		# inside the active recipe rather than in the buffer.
		var in_recipe: int = 0
		if restored[0].active_recipe != null:
			in_recipe = int(restored[0].active_recipe.inputs.get(&"log_pine", 0))
		check_eq(int(restored[0].buffer.get(&"log_pine", 0)) + in_recipe, 3,
			"machine buffer was not restored")
		check_eq(restored[0].total_produced, 7, "machine counters were not restored")
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
	mill.position = Vector3(0, 0, -8)
	world.add_child(mill)
	await step(4)

	PlayerState.levels[&"carry"] = 1
	var first := spawn(&"log_pine", Vector3(1, 1, 1))
	var second := spawn(&"log_pine", Vector3(2, 1, 1))
	check(player.pick_up(first), "could not pick up an item")
	check_eq(player.carried_count(), 1, "rack count is wrong")
	check(not player.pick_up(second), "rack accepted more than its capacity")

	PlayerState.levels[&"carry"] = 3
	check(player.pick_up(second), "rack did not grow with the upgrade")
	await step(10)
	# Held items are kinematic and must ride with the player.
	check_eq(first.state, LooseItem.State.HELD, "carried item is not in the held state")
	check(first.global_position.distance_to(player.global_position) < 2.5,
		"held item did not follow the player")

	var moved := player.deposit_into(mill)
	check_eq(moved, 2, "depositing into the sawmill moved %d items" % moved)
	check_eq(player.carried_count(), 0, "rack not emptied after depositing")
	check_eq(int(mill.buffer.get(&"log_pine", 0)), 2, "machine did not receive the deposit")

	# Dropping puts items back into the simulation.
	var third := spawn(&"log_pine", Vector3(3, 1, 1))
	player.pick_up(third)
	player._drop(1)
	await step(10)
	check_eq(third.state, LooseItem.State.FREE, "dropped item is not free again")

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

	for i in 4:
		spawn(&"log_pine", truck.global_position + Vector3(0, 2.0 + float(i) * 0.4, 0.6))
	await step(45)
	check_eq(truck.cargo.size(), 4, "hauler did not capture its cargo")

	var start := truck.global_position
	truck.autopilot = true
	truck.input_throttle = 1.0
	await step(150)
	var travelled: float = start.distance_to(truck.global_position)
	check(travelled > 6.0, "hauler barely moved under throttle (%.1f m)" % travelled)
	check(truck.linear_velocity.length() <= truck.max_speed * 1.5, "hauler exceeded its speed cap")
	check(truck.global_transform.basis.y.dot(Vector3.UP) > 0.7, "hauler rolled while driving")
	check_eq(truck.cargo.size(), 4, "hauler lost cargo while driving")

	truck.input_throttle = 0.0
	var dropped := truck.unload()
	check_eq(dropped, 4, "unloading returned the wrong count")
	await step(20)
	check_eq(truck.cargo.size(), 0, "hauler still holds cargo after unloading")
	check_eq(manager.free_items().size(), 4, "unloaded cargo is not free")

func test_kill_plane() -> void:
	_setup()
	await step(2)
	var item := spawn(&"log_pine", Vector3(0, 2, 0))
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
		spawn(&"log_pine", Vector3(randf_range(-2, 2), 4.0 + float(i) * 0.05, randf_range(-2, 2)))
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
	plot.place(GameData.building(&"sawmill"), Vector2i(-8, -6), 0)
	plot.place(GameData.building(&"sawmill"), Vector2i(4, -6), 0)
	PlayerState.try_unlock(&"furnace")
	plot.place(GameData.building(&"furnace"), Vector2i(-2, 6), 0)
	plot.place(GameData.building(&"splitter"), Vector2i(0, 0), 0)
	plot.place(GameData.building(&"storage"), Vector2i(8, 2), 0)
	plot.place(GameData.building(&"conveyor"), Vector2i(-8, 0), 0)
	plot.place(GameData.building(&"conveyor"), Vector2i(4, 0), 0)
	plot.place(GameData.building(&"conveyor"), Vector2i(-2, 2), 0)
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
			spawn(&"log_pine", Vector3(randf_range(-9, -7), 5.0, randf_range(-2, 2)))
			spawn(&"ore_iron", Vector3(randf_range(-3, -1), 5.0, randf_range(5, 7)))
		if i % 30 == 0 and chute != null:
			# Stand in for a belt feeding the chute, so the sell path is exercised.
			spawn(&"plank_pine", chute.global_position + Vector3(0, 2.0, 0))
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
