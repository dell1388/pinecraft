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
	# Content assertions: a scene that builds but is empty used to pass quietly.
	_require(world.trees().size() >= 40, "forest is missing: %d trees" % world.trees().size())
	_require(world.rocks().size() >= 20, "quarry is missing: %d rocks" % world.rocks().size())
	_require(world.depot != null, "no sell depot")
	_require(world.player != null and world.hud != null, "no player or HUD")

func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _prev > 0:
		samples.append(float(now - _prev) / 1000.0)
	_prev = now
	frames += 1

	# Drive the world the way a player would: fell trees, mine, build, sell.
	if frames == 30:
		var felled := 0
		for tree in world.trees():
			if felled >= 6:
				break
			tree.fell(tree.global_position + Vector3(0, 0, 3))
			felled += 1
		print("felled %d trees" % felled)
		_require(felled > 0, "no trees could be felled")
	if frames == 60:
		var mined := 0
		for rock in world.rocks():
			if mined >= 5:
				break
			rock.shatter()
			mined += 1
		print("broke %d rocks -> %d loose items" % [mined, world.manager.active_count()])
		_require(mined > 0, "no rocks could be mined")
	if frames == 90:
		Economy.add_money(100000)
		PlayerState.try_unlock(&"furnace")
		var built := 0
		if world.plot.place(GameData.building(&"sawmill"), Vector2i(-9, -5), 0) != null:
			built += 1
		if world.plot.place(GameData.building(&"furnace"), Vector2i(2, -5), 0) != null:
			built += 1
		if world.plot.place(GameData.building(&"conveyor"), Vector2i(-9, 4), 0) != null:
			built += 1
		if world.plot.place(GameData.building(&"sell_chute"), Vector2i(8, 4), 0) != null:
			built += 1
		PlayerState.try_buy_vehicle()
		world.spawn_vehicle()
		print("built %d buildings, hauler spawned: %s" % [built, world.hauler != null])
		_require(built == 4, "only %d of 4 buildings could be placed" % built)
	if frames >= 120 and frames < 600 and frames % 12 == 0:
		# Feed the real machines through their real hoppers, and the sell chute
		# the way a belt would.
		for m in world.plot.machines():
			var item_id: StringName = &"wood_pine" if m.def.machine == &"sawmill" else &"ore_iron"
			var dims := Solid.cylinder(0.2, 0.17, randf_range(1.4, 3.0)) if item_id == &"wood_pine" else {}
			world.manager.spawn(item_id, Transform3D(Basis(), m.input_point()), 0, Vector3.ZERO, dims)
		for rec in world.plot.placed:
			var zone := rec.node as SellZone
			if zone != null:
				world.manager.spawn(&"lumber_pine", Transform3D(Basis(),
					zone.global_position + Vector3(0, 1.5, 0)), 0)
	if frames == 400:
		print("mid-run: %d loose, %d awake, $%d, machines produced %d, %.2f m3 in / %.2f m3 out" % [
			world.manager.active_count(), world.manager.awake_count(), Economy.money,
			_produced(), _volume_in(), _volume_out()])
	if frames >= 900:
		_report()

var problems: Array[String] = []

func _require(condition: bool, message: String) -> void:
	if not condition:
		problems.append(message)
		print("PROBLEM: " + message)

func _count_of(type_name: String) -> int:
	var n := 0
	for child in world.get_children():
		if child.get_class() == "Node3D" or true:
			var script: Script = child.get_script()
			if script != null and script.resource_path.ends_with(type_name + ".gd"):
				n += 1
	return n

func _volume_in() -> float:
	var v := 0.0
	for m in world.plot.machines():
		v += m.volume_in
	return v

func _volume_out() -> float:
	var v := 0.0
	for m in world.plot.machines():
		v += m.volume_out
	return v

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
	print("machine output    %d pieces (%.2f m3 in, %.2f m3 out)" % [
		_produced(), _volume_in(), _volume_out()])
	print("money             $%d" % Economy.money)
	print("kill-plane saves  %d" % world.manager.stat_killplane)
	print("bulk sleeps       %d" % world.manager.stat_forced_sleeps)
	_require(_produced() > 0, "no machine produced anything")
	_require(_volume_out() <= _volume_in() + 0.0001, "a machine created volume from nothing")
	var ok := avg < 16.67 and world.manager.active_count() <= world.manager.per_plot_cap \
		and problems.is_empty()
	if not problems.is_empty():
		print("problems: " + str(problems))
	print("RESULT: %s" % ("ok" if ok else "FAILED"))
	get_tree().quit(0 if ok else 1)
