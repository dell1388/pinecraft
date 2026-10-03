extends Node
## Frame-time harness (not part of the game): boots the world with no menu,
## walks the player through the woods near home and out along a road, and
## prints what each frame cost - script time, physics time, and what was drawn.
##   xvfb-run -a godot --rendering-driver opengl3 --path . res://scenes/perf.tscn
## Headless it still measures the CPU side (scripts, physics, culling).

var world: World
var samples: Array[Dictionary] = []

func _ready() -> void:
	world = load("res://scenes/world.tscn").instantiate()
	world.show_menu = false
	world.autosave = false
	var t0 := Time.get_ticks_msec()
	add_child(world)
	for i in 30:
		await get_tree().process_frame
	print("PERF load %d ms" % (Time.get_ticks_msec() - t0))
	Settings.set_value(&"moving_sun", true, false)
	var off := OS.get_environment("PERF_OFF").split(",")
	for n in _all(world):
		if "fields" in off and n is ResourceField:
			n.set_process(false)
		if "decor" in off and n is Decor:
			n.set_process(false)
		if "hud" in off and n is CanvasItem and n.get_parent() == world.hud:
			pass
	if "hud" in off:
		world.hud.visible = false
		world.hud.process_mode = Node.PROCESS_MODE_DISABLED
	if "world" in off:
		world.set_process(false)
	if "physics" in off:
		PhysicsServer3D.set_active(false)
	if "player" in off:
		world.player.process_mode = Node.PROCESS_MODE_DISABLED
	if OS.get_environment("PERF_COUNT") != "":
		var by: Dictionary = {}
		for n in _all(world):
			if n is GeometryInstance3D and (n as GeometryInstance3D).is_visible_in_tree():
				var top: Node = n
				while top.get_parent() != world and top.get_parent() != null:
					top = top.get_parent()
				var key := String(top.name).get_slice("_", 0) + ":" + n.get_class()
				by[key] = int(by.get(key, 0)) + 1
		var keys := by.keys()
		keys.sort_custom(func(a, b): return by[a] > by[b])
		for k in keys.slice(0, 25):
			print("PERF count %-40s %d" % [k, by[k]])
		# One tree, what it is made of.
		for f in world.tree_fields:
			if not f.alive.is_empty():
				var tree: Node = f.alive[0]
				var parts: Dictionary = {}
				for n in _all(tree):
					parts[n.get_class()] = int(parts.get(n.get_class(), 0)) + 1
				print("PERF one tree ", tree.get_class(), " ", parts)
				break
	var p: Player = world.player
	var start: Vector3 = world.starter_forest
	if OS.get_environment("PERF_SPLIT") != "":
		p.global_position = start + Vector3(0, world.terrain.height_at(start.x, start.z) - start.y + 1.0, 0)
		for i in 10:
			await get_tree().process_frame
		var base := _stats()
		print("PERF split all ", base)
		var prefixes: Array = ["impostors", "shadows"]
		for c in world.get_children():
			var pre := String(c.name).get_slice("_", 0)
			if not pre in prefixes:
				prefixes.append(pre)
		for group in prefixes:
			var hidden: Array[Node] = []
			for n in _all(world):
				var hit := false
				if group == "impostors":
					hit = n is MultiMeshInstance3D and String(n.name).begins_with("Impostors")
				elif group == "shadows":
					hit = false
				else:
					hit = n.get_parent() == world and String(n.name).begins_with(group)
				if hit and n is Node3D and (n as Node3D).visible:
					(n as Node3D).visible = false
					hidden.append(n)
			if group == "shadows":
				world.sun.shadow_enabled = false
			for i in 4:
				await get_tree().process_frame
			var s := _stats()
			if base.x - s.x < 8:
				for n in hidden:
					(n as Node3D).visible = true
				world.sun.shadow_enabled = true
				continue
			print("PERF split without %-10s draws -%d  prims -%dk" % [group, base.x - s.x, (base.y - s.y) / 1000])
			for n in hidden:
				(n as Node3D).visible = true
			world.sun.shadow_enabled = true
		get_tree().quit()
		return
	# Stand still in the woods, then walk out through them and along a road.
	await _run("standing in the woods", func(_t: float) -> Vector3: return start, _frames(240))
	await _run("walking through the woods", func(t: float) -> Vector3:
		return start + Vector3(t * 6.0, 0, sin(t * 0.3) * 40.0), _frames(600))
	await _run("driving the east road", func(t: float) -> Vector3:
		return Vector3(90.0 + t * 18.0, 0, 20.0), _frames(600))
	get_tree().quit()

func _run(label: String, path: Callable, frames: int) -> void:
	var p: Player = world.player
	var times := PackedFloat32Array()
	var proc := 0.0
	var phys := 0.0
	var draws := 0.0
	var objects := 0.0
	var prims := 0.0
	var worst := 0.0
	var grass_ms := 0.0
	var grass_worst := 0.0
	var birds_ms := 0.0
	var last := Time.get_ticks_usec()
	var t := 0.0
	for i in frames:
		var at: Vector3 = path.call(t)
		at.y = world.terrain.height_at(at.x, at.z) + 1.0
		p.global_position = at
		p.velocity = Vector3.ZERO
		ResourceField.spent_usec = 0
		ResourceField.built_count = 0
		ResourceField.slept_count = 0
		Decor.spent_usec = 0
		GrassField.spent_usec = 0
		Birds.spent_usec = 0
		var tw0 := Time.get_ticks_usec()
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := float(now - last) / 1000.0
		last = now
		t += 1.0 / 60.0
		if i < 10:
			continue
		times.append(ms)
		if ms > 25.0:
			print("PERF slow frame %.1f ms: fields %.1f ms, built %d, slept %d, decor %.1f ms" % [ms, ResourceField.spent_usec / 1000.0, ResourceField.built_count, ResourceField.slept_count, Decor.spent_usec / 1000.0])
		worst = maxf(worst, ms)
		grass_ms += GrassField.spent_usec / 1000.0
		grass_worst = maxf(grass_worst, GrassField.spent_usec / 1000.0)
		birds_ms += Birds.spent_usec / 1000.0
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var n := float(times.size())
	var sorted := times.duplicate()
	sorted.sort()
	print("PERF %-26s frame avg %6.2f ms  p95 %6.2f  worst %7.2f | process %5.2f  physics %5.2f | draws %5d  objects %5d  prims %7dk | nodes %d" % [
		label, _sum(times) / n, sorted[int(n * 0.95)], worst, proc / n, phys / n,
		int(draws / n), int(objects / n), int(prims / n / 1000.0),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	print("PERF %-26s grass %.3f ms a frame (worst %.2f), birds %.3f ms" % [label, grass_ms / n, grass_worst, birds_ms / n])

static func _stats() -> Vector2i:
	return Vector2i(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))

static func _frames(n: int) -> int:
	var env := OS.get_environment("PERF_FRAMES")
	return int(env) if env != "" else n

static func _all(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out

static func _sum(a: PackedFloat32Array) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s
