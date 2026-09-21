extends Node

## Boots the real game scene headless, runs it, and reports cost and content.
## Catches anything that only breaks in the assembled world.

var world: World
var frames: int = 0
var samples: PackedFloat32Array = PackedFloat32Array()
var _prev: int = 0

func _ready() -> void:
	Engine.max_fps = 0
	world = load("res://scenes/world.tscn").instantiate()
	world.autosave = false
	add_child(world)
	await get_tree().physics_frame
	print("world built: %d children, plot extent %.0fm, money $%d" % [
		world.get_child_count(), world.plot.half_extent * 2.0, Economy.money])

func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _prev > 0:
		samples.append(float(now - _prev) / 1000.0)
	_prev = now
	frames += 1

	# Drive the world the way a player would: fell trees, mine, build, sell.
	if frames == 30:
		var felled := 0
		for child in world.get_children():
			var tree := child as ChoppableTree
			if tree != null and felled < 6:
				tree.chop(9999.0, tree.global_position + Vector3(0, 0, 3))
				felled += 1
		print("felled %d trees" % felled)
	if frames == 60:
		var mined := 0
		for child in world.get_children():
			var rock := child as OreRock
			if rock != null and mined < 5:
				rock.mine(9999.0, rock.global_position + Vector3(3, 0, 0))
				mined += 1
		print("broke %d rocks -> %d loose items" % [mined, world.manager.active_count()])
	if frames == 90:
		Economy.add_money(100000)
		PlayerState.try_unlock(&"furnace")
		var built := 0
		if world.plot.place(GameData.building(&"sawmill"), Vector2i(-6, -4), 0) != null:
			built += 1
		if world.plot.place(GameData.building(&"furnace"), Vector2i(2, -4), 0) != null:
			built += 1
		if world.plot.place(GameData.building(&"conveyor"), Vector2i(-6, 2), 0) != null:
			built += 1
		if world.plot.place(GameData.building(&"sell_chute"), Vector2i(8, 4), 0) != null:
			built += 1
		PlayerState.try_buy_vehicle()
		world.spawn_vehicle()
		print("built %d buildings, hauler spawned: %s" % [built, world.hauler != null])
	if frames >= 120 and frames < 600 and frames % 12 == 0:
		# Feed the real machines through their real hoppers, and the sell chute
		# the way a belt would.
		for m in world.plot.machines():
			var item_id: StringName = &"log_pine" if m.def.machine == &"sawmill" else &"ore_iron"
			world.manager.spawn(item_id, Transform3D(Basis(), m.input_point()), 0)
		for rec in world.plot.placed:
			var zone := rec.node as SellZone
			if zone != null:
				world.manager.spawn(&"plank_pine", Transform3D(Basis(),
					zone.global_position + Vector3(0, 1.5, 0)), 0)
	if frames == 400:
		print("mid-run: %d loose, %d awake, $%d, machines produced %d" % [
			world.manager.active_count(), world.manager.awake_count(), Economy.money,
			_produced()])
	if frames >= 900:
		_report()

func _produced() -> int:
	var n := 0
	for m in world.plot.machines():
		n += m.total_produced
	return n

func _report() -> void:
	var total := 0.0
	var worst := 0.0
	for v in samples:
		total += v
		worst = maxf(worst, v)
	var avg := total / float(samples.size())
	print("\n--- world smoke test ---")
	print("frames            %d" % frames)
	print("avg frame         %.2f ms (budget 16.67)" % avg)
	print("worst frame       %.2f ms" % worst)
	print("loose items       %d / cap %d" % [world.manager.active_count(), world.manager.per_plot_cap])
	print("awake items       %d" % world.manager.awake_count())
	print("machine output    %d" % _produced())
	print("money             $%d" % Economy.money)
	print("kill-plane saves  %d" % world.manager.stat_killplane)
	print("bulk sleeps       %d" % world.manager.stat_forced_sleeps)
	var ok := avg < 16.67 and world.manager.active_count() <= world.manager.per_plot_cap
	print("RESULT: %s" % ("ok" if ok else "OVER BUDGET"))
	get_tree().quit(0 if ok else 1)
