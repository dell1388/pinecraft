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
	_check_ground()
	_check_forest()

## Different biomes are supposed to grow different trees. Count what actually
## came up, and check each one is standing in country its species belongs to.
func _check_forest() -> void:
	var terrain: Terrain = world.terrain
	var census: Dictionary = {}
	var misplaced := 0
	for field in world.tree_fields:
		var kind: Dictionary = field.species[0]
		for node in field.alive:
			var tree := node as ChoppableTree
			if tree == null:
				continue
			census[kind.name] = int(census.get(kind.name, 0)) + 1
			var biome := terrain.biome_at(tree.global_position.x, tree.global_position.z)
			if not (kind.biomes as Array).has(int(biome)):
				misplaced += 1
	var mix: Array[String] = []
	for name in world.terrain.biome_mix():
		mix.append("%s %.0f%%" % [name, float(world.terrain.biome_mix()[name]) * 100.0])
	print("biomes: " + ", ".join(mix))
	var parts: Array[String] = []
	for name in census:
		parts.append("%s x%d" % [name, int(census[name])])
	print("forest: " + ", ".join(parts))
	_require(census.size() >= 3, "only %d tree species grew" % census.size())
	_require(misplaced == 0, "%d trees grew outside their own biomes" % misplaced)

## The land has to be solid off the plot, and the plot has to stand clear of it.
## Both of these shipped broken once: the terrain's triangles were wound
## inside-out so there was nothing to stand on past the kerb, and the pad, the
## ground and the water sheet all sat on y = 0 and fought over it.
func _check_ground() -> void:
	var terrain: Terrain = world.terrain
	var space := world.get_world_3d().direct_space_state
	var missed: Array[String] = []
	for probe in [Vector3(0, 0, 0), Vector3(30, 0, 30), Vector3(-45, 0, 20),
			Vector3(80, 0, -60), Vector3(-120, 0, 90), Vector3(150, 0, 150),
			world.DEPOT_POSITION, world.STORE_POSITION, world.QUARRY_CENTRE]:
		var expected := terrain.height_at(probe.x, probe.z)
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(probe.x, expected + 80.0, probe.z),
			Vector3(probe.x, expected - 40.0, probe.z), Layers.WORLD)
		if space.intersect_ray(query).is_empty():
			missed.append("(%.0f, %.0f)" % [probe.x, probe.z])
	_require(missed.is_empty(), "nothing solid to stand on at " + ", ".join(missed))

	# The pad sits proud of the ground and above the water, so no two surfaces
	# share a plane and the plot is never under the sheet.
	var under_pad := terrain.height_at(0.0, 0.0)
	var pad_top := world.plot.global_position.y
	_require(pad_top > under_pad + 0.02,
		"the plot pad (%.2f m) is not clear of the ground under it (%.2f m)" % [pad_top, under_pad])
	_require(under_pad > Terrain.WATER_LEVEL,
		"the ground under the plot (%.2f m) is at or below the water line" % under_pad)
	print("ground ok: pad %.2f m over land at %.2f m, water at %.2f m" % [
		pad_top, under_pad, Terrain.WATER_LEVEL])

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
		PlayerState.try_buy_vehicle()
		world.spawn_vehicle()
		print("built %d buildings, hauler spawned: %s" % [built, world.hauler != null])
		_require(built == 3, "only %d of 3 buildings could be placed" % built)
	if frames >= 120 and frames < 600 and frames % 12 == 0:
		# Feed the real machines through their real hoppers, and the sell chute
		# the way a belt would.
		for m in world.plot.inline_machines():
			var item_id: StringName = &"wood_pine" if m.def.machine == &"sawmill" else &"ore_iron"
			var dims := Solid.cylinder(0.2, 0.17, randf_range(1.4, 3.0)) if item_id == &"wood_pine" else Solid.cube(0.25)
			world.manager.spawn(item_id, Transform3D(m.global_transform.basis * LooseItem.lying_basis(0.0),
				m.global_transform * Vector3(0, 0.6, m.length * 0.5 - 0.35)), 0, Vector3.ZERO, dims, true)
	if frames == 420:
		_check_ui()
	if frames == 400:
		print("mid-run: %d loose, %d awake, $%d, machines produced %d, %.2f m3 in / %.2f m3 out" % [
			world.manager.active_count(), world.manager.awake_count(), Economy.money,
			_produced(), _volume_in(), _volume_out()])
	if frames >= 900:
		_report()

var problems: Array[String] = []

## The screens over the world: none of this is visible headless, but all of it
## builds, lays out and runs, so a broken menu fails here rather than on launch.
func _check_ui() -> void:
	var hud: GameHUD = world.hud
	_require(world.main_menu == null, "the title screen opened in a world run as a child")
	_require(world.playing, "a world with no title screen should be in play")
	for tab in Journal.TABS:
		hud.open_journal(tab)
		_require(hud.journal_open() and hud.journal.current_tab() == tab, "journal did not open on %s" % tab)
	hud.open_journal("Controls")
	_require(not hud.journal_open(), "the same key again should close the journal")
	world.pause_game()
	_require(get_tree().paused and world.pause_menu.visible, "pausing did not pause")
	world.resume_play()
	_require(not get_tree().paused and not world.pause_menu.visible, "resuming did not resume")
	# Sales arrive one signal per item; the HUD has to fold a yard's worth into
	# one line rather than burying the screen.
	for i in 40:
		Economy.sell(&"wood_pine", {})
	hud._flush_events()
	_require(hud._toasts.get_child_count() <= GameHUD.TOAST_MAX, "toasts are not capped")
	var last := hud._toasts.get_child(hud._toasts.get_child_count() - 1)
	_require(String(last.get_meta("text", "")).begins_with("Sold 40"), "a burst of sales was not folded into one toast")
	_require(world.tutorial != null, "no getting-started checklist")
	# The world out past the plot: caves, outposts and dressing all built, and
	# walking up to a place puts it on the map.
	_require(world.caves.size() >= 2, "only %d caves" % world.caves.size())
	_require(world.outposts.size() >= 6, "only %d outposts" % world.outposts.size())
	_require(world.decor.instance_count > 400, "the land is bare: %d decor pieces" % world.decor.instance_count)
	var place: Outpost = world.outposts[0]
	var was: Vector3 = world.player.global_position
	world.player.global_position = place.global_position + Vector3(0, 3, 12)
	world._discover_timer = 0.0
	world._check_discovery(0.1)
	_require(world.discovered(place.place_name), "walking up to %s did not discover it" % place.place_name)
	world.player.global_position = was
	print("world: %d caves, %d outposts, %d decor, %d boulders" % [world.caves.size(),
		world.outposts.size(), world.decor.instance_count, world.decor.boulder_count])
	var species := {}
	for tree in world.trees():
		species[tree.species] = int(species.get(tree.species, 0)) + 1
	var ores := {}
	for rock in world.rocks():
		ores[rock.ore_item] = int(ores.get(rock.ore_item, 0)) + 1
	print("forest: %d trees of %d species %s" % [world.trees().size(), species.size(), str(species)])
	print("rocks: %d %s" % [world.rocks().size(), str(ores)])
	_check_spread()
	_require(world.trees().size() >= 100, "only %d trees built round home" % world.trees().size())
	print("ui ok: journal %d tabs, pause/resume, %d toasts, checklist %d/%d" % [
		Journal.TABS.size(), hud._toasts.get_child_count(), world.tutorial.done_count(), Tutorial.STEPS.size()])

## Spec: a 2.5 km map of islands, and the better the material the further out
## it is - with the best of all hidden: mahogany in a walled valley, diamonds
## in the farthest cave, starmetal in the crater.
func _check_spread() -> void:
	_require(world.terrain.half_extent * 2.0 >= 4000.0, "the map is %.0f m across" % (world.terrain.half_extent * 2.0))
	_require(world.bridges.size() >= 3, "only %d bridges" % world.bridges.size())
	for b in world.bridges:
		var bridge: Bridge = b
		_require(bridge.from_point.y > Terrain.WATER_LEVEL and bridge.to_point.y > Terrain.WATER_LEVEL,
			"a bridge ends in the water")
	# Cheap stuff near home, dear stuff far out: mean distance by value.
	var all := world.census()
	var cheap := [0.0, 0]
	var dear := [0.0, 0]
	var species := {}
	var diamonds := 0
	var mahogany := 0
	var starmetal := 0
	var deepest: Cave = null
	for cave in world.caves:
		if deepest == null or cave.global_position.length() > deepest.global_position.length():
			deepest = cave
	for rec in all:
		var pos: Vector3 = rec.pos
		var id: StringName = rec.what
		if rec.species != "":
			species[rec.species] = int(species.get(rec.species, 0)) + 1
		if String(id).begins_with("ore_") or String(id).begins_with("gem_"):
			var def := GameData.item(id)
			var d := Vector2(pos.x, pos.z).length()
			if pos.y > world.terrain.height_at(pos.x, pos.z) - 4.0:
				if def.value_per_m3 >= 1800.0:
					dear[0] += d
					dear[1] += 1
				elif def.value_per_m3 <= 900.0:
					cheap[0] += d
					cheap[1] += 1
		if id == &"gem_diamond":
			diamonds += 1
			_require(pos.y < world.terrain.height_at(pos.x, pos.z) - 6.0, "a diamond is not underground")
		if id == &"ore_starmetal" and pos.y > world.terrain.height_at(pos.x, pos.z) - 4.0:
			starmetal += 1
			_require(Vector2(pos.x - 1160.0, pos.z - 1170.0).length() < 70.0, "surface starmetal is outside the crater")
		if rec.species == "Mahogany":
			mahogany += 1
			_require(Vector2(pos.x + 1470.0, pos.z - 1480.0).length() < 50.0, "a mahogany grew outside the hidden valley")
	var near_mean: float = cheap[0] / maxf(1.0, cheap[1])
	var far_mean: float = dear[0] / maxf(1.0, dear[1])
	print("census: %d trees and rocks (built and dormant), %d species" % [all.size(), species.size()])
	print("spread: cheap ore %.0f m out on average, dear ore %.0f m, %d bridges" % [near_mean, far_mean, world.bridges.size()])
	_require(far_mean > near_mean * 1.8, "the dear ore is not further out than the cheap (%.0f vs %.0f)" % [far_mean, near_mean])
	_require(diamonds > 0, "there are no diamonds")
	_require(starmetal > 0, "there is no starmetal in the crater")
	_require(mahogany > 0, "no mahogany grew")
	_require(species.size() >= 16, "only %d tree species" % species.size())
	_require(deepest != null and deepest.global_position.length() > 1500.0, "no cave mouth on a far island")
	# The caves: big, deep and joined up.
	var net: Dictionary = world.network.summary()
	print("caves: %s" % str(net))
	_require(int(net.caverns) >= 60, "only %d caverns" % int(net.caverns))
	_require(float(net.tunnel_km) >= 8.0, "only %.1f km of tunnel" % float(net.tunnel_km))
	_require(int(net.below_sea) > int(net.caverns) / 2, "most caverns are above sea level")
	_require((net.kinds as Dictionary).size() >= 6, "only %d cave biomes" % (net.kinds as Dictionary).size())
	# Every piece of cave can be reached from the surface.
	var ids: Array = []
	for i in world.network.rooms.size():
		ids.append(i)
	var comp: Dictionary = world.network._components(ids)
	var mouths: Dictionary = {}
	for i in ids:
		if world.network.rooms[i].entrance != null:
			mouths[comp[i]] = true
	for i in ids:
		if not mouths.has(comp[i]):
			_require(false, "cavern %d cannot be reached from any cave mouth" % i)
			break

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
	for m in world.plot.inline_machines():
		v += m.volume_in
	return v

func _volume_out() -> float:
	var v := 0.0
	for m in world.plot.inline_machines():
		v += m.volume_out
	return v

func _produced() -> int:
	var n := 0
	for m in world.plot.inline_machines():
		n += m.total_processed
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
	print("resurfaced        %d" % world.manager.stat_resurfaced)
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
