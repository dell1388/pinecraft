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
	await _test(&"bucking splits wood and conserves volume", test_bucking)
	await _test(&"a chunk is pulled out whole when the pull is enough", test_chunk_pull)
	await _test(&"hammering cracks a chunk apart piece by piece", test_chunk_cracking)
	await _test(&"the crusher breaks ore down faster than a hammer", test_crusher)
	await _test(&"sawmill mills wood and conserves volume", test_sawmill)
	await _test(&"furnace smelts ore into billets", test_furnace)
	await _test(&"workbench assembles from volumes", test_workbench)
	await _test(&"machines reject items they cannot use", test_machine_rejects)
	await _test(&"sell zone pays today's price", test_sell_zone)
	await _test(&"the yard buys what the player owns in it", test_sell_yard)
	await _test(&"orders pay out on delivery", test_quests)
	await _test(&"storage bin stores and dispenses", test_storage)
	await _test(&"conveyor feeds a machine directly", test_conveyor_to_machine)
	await _test(&"splitter routes round-robin", test_splitter)
	await _test(&"filter sorts items by type", test_filter)
	await _test(&"building placement, cost and removal", test_building)
	await _test(&"plans fill with material and turn solid", test_schematic)
	await _test(&"save/load round-trip", test_save_load)
	await _test(&"plot expansion raises bounds and cap", test_expansion)
	await _test(&"tool upgrades apply and charge", test_upgrades)
	await _test(&"the store sells boxes over a counter", test_store)
	await _test(&"carry rack limits and deposits", test_carry)
	await _test(&"lift and drag limits are weight limits", test_handling_limits)
	await _test(&"ownership is tracked and saved", test_ownership)
	await _test(&"hauler drives, carries and stays upright", test_hauler)
	await _test(&"a pad spawns one vehicle and replaces it", test_vehicle_pad)
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

## Spec: a crusher breaks whole chunks and large pieces down, faster than by
## hand. It conserves volume like every other machine.
func test_crusher() -> void:
	_setup()
	var crusher := Machine.new()
	crusher.setup(manager, GameData.building(&"crusher"), 0)
	world.add_child(crusher)
	await step(2)

	# A lump far too big to carry goes in whole.
	var lump := spawn(&"ore_iron", crusher.input_point(), Solid.cube(0.9))
	var lump_volume := lump.volume()
	check(lump.mass > 500.0, "test lump is only %.0f kg" % lump.mass)
	check(crusher.accept_item(lump), "the crusher refused a whole chunk")
	check_near(crusher.buffered_m3(), lump_volume, 0.0001, "the crusher mismeasured the lump")

	for i in 1200:
		await step(1)
		if crusher.job.is_empty() and crusher.queue.is_empty() and crusher.total_produced > 0:
			break
	check(crusher.total_produced > 1, "the crusher made %d piece(s) from one lump" %
		crusher.total_produced)
	check_near(crusher.volume_out, lump_volume, 0.0001, "the crusher did not conserve ore")
	var biggest := 0.0
	for item in manager.free_items():
		biggest = maxf(biggest, item.volume())
	check(biggest < lump_volume, "the crusher handed back a piece as big as it was given")
	var def: MachineDef = crusher.machine_def
	for item in manager.free_items():
		check(item.length() <= def.max_piece_length + 0.0001,
			"a crushed piece is %.2f m, over the %.2f m limit" % [item.length(), def.max_piece_length])

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

## Spec: material left in the yard is bought when the player asks the shopkeep -
## all of it, and only what the player actually owns.
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

	check(shop.slots.size() > 0, "the store has no shelf slots")
	var stocked := 0
	for slot in shop.slots:
		if slot.item != null:
			stocked += 1
	check(stocked > 0, "the shelves are empty")

	# Find the axe box and check it is priced off the upgrade track, not twice.
	var axe_slot: Dictionary = {}
	for slot in shop.slots:
		if slot.box == &"box_axe":
			axe_slot = slot
	check(not axe_slot.is_empty(), "the store does not stock an axe")
	check_eq(shop.price_of(axe_slot), PlayerState.next_cost(&"axe"),
		"the boxed axe is not priced off its track")

	var box: LooseItem = axe_slot.item
	check(box != null, "no axe box on the shelf")
	check(not box.owned, "shelf stock starts out owned")

	# Taking it off the shelf is not buying it.
	var player := _make_player()
	world.add_child(player)
	await step(2)
	check(player.pick_up(box), "could not pick the box off the shelf")
	check(not box.owned, "carrying a box off the shelf made it the player's")

	# Paying for it at the counter does.
	var money_before := Economy.money
	var price := shop.price_of(axe_slot)
	var carried: Array[LooseItem] = []
	for item in player.held:
		carried.append(item)
	player.held.clear()
	for item in carried:
		item.set_state(LooseItem.State.FREE)
	var receipt := shop.buy(carried)
	check_eq(int(receipt.bought), 1, "the till bought %d box(es)" % int(receipt.bought))
	check_eq(int(receipt.spent), price, "the till charged the wrong amount")
	check_eq(Economy.money, money_before - price, "money did not move by the price")
	check(box.owned, "a paid box is still not the player's")

	# Opening the paid box delivers what is inside.
	var level_before := PlayerState.level(&"axe")
	var said := shop.open_box(box)
	check(said != "that one has not been paid for", "the box refused to open after payment")
	check_eq(PlayerState.level(&"axe"), level_before + 1, "opening the box did not upgrade the axe")
	await step(4)
	check_eq(box.state, LooseItem.State.POOLED, "the opened box is still lying about")

	# The shelf restocks, at the new price.
	shop.restock()
	check(axe_slot.item != null, "the shelf did not restock")
	check_eq(shop.price_of(axe_slot), PlayerState.next_cost(&"axe"),
		"the restocked box is not priced off the upgraded track")

	# An unpaid box will not open.
	var fresh: LooseItem = axe_slot.item
	check_eq(shop.open_box(fresh), "that one has not been paid for",
		"an unpaid box opened anyway")

	# And carried out of the shop, it goes back to the shelf. Identity is no
	# use for checking this: the despawned box is pooled and the replacement
	# reuses the very same node, so the test asks where the stock is instead.
	var outside := shop.global_position + Vector3(0, 1, 60)
	fresh.teleport(Transform3D(Basis(), outside))
	check(not shop.contains(outside), "the test position is still inside the store")
	await step(40)
	var stranded := 0
	for item in manager.free_items():
		if item.item_id == &"box_axe" and not shop.contains(item.global_position):
			stranded += 1
	check_eq(stranded, 0, "unpaid stock survived being carried out of the shop")
	check(axe_slot.item != null, "the shelf did not put a replacement out")
	if axe_slot.item != null:
		check(shop.contains((axe_slot.item as LooseItem).global_position),
			"the replacement box is not in the shop")

	# Land is sold at the desk.
	var tier_before := plot.tier
	var land := shop.buy_land()
	check(plot.tier == tier_before + 1, "the desk did not sell a parcel (%s)" % land)

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

## Spec: a pad spawns one copy of its vehicle; triggering it again removes the
## old one first.
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
