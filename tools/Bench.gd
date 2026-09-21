extends Node3D

## Headless physics benchmark. Run with:
##   godot --headless --path . --fixed-fps 60 scenes/bench.tscn -- [--quick]
##
## Every scenario builds a fresh world, warms up, then samples per-frame cost.
## Reported physics time is Godot's TIME_PHYSICS_PROCESS monitor (the whole
## physics frame, including the Jolt step); wall time is the real cost of one
## main-loop iteration with rendering stubbed out.

const PHYSICS_HZ := 60.0
const FRAME_BUDGET_MS := 1000.0 / PHYSICS_HZ

enum Phase { BUILD, WARM, MEASURE, SETTLE, REST, DONE }

var scenarios: Array[Dictionary] = []
var results: Array[Dictionary] = []

var _idx: int = -1
var _phase: int = Phase.DONE
var _frames: int = 0
var _samples: PackedFloat32Array = PackedFloat32Array()
var _rest_samples: PackedFloat32Array = PackedFloat32Array()
var _wall_start: int = 0
var _wall_us: int = 0
var _prev_frame_us: int = 0
var _monitor_samples: PackedFloat32Array = PackedFloat32Array()
var _settle_frames: int = 0
var _peak_active: int = 0
var _peak_awake: int = 0
var _drag_targets: Array[LooseItem] = []
var _drag_time: float = 0.0
var _peak_pairs: int = 0
var _world: Node3D
var _manager: LooseItemManager
var _conveyors: Array[Conveyor] = []
var _rng := RandomNumberGenerator.new()
var _current: Dictionary = {}

func _ready() -> void:
	Engine.max_fps = 0
	_rng.seed = 20260921
	var quick := OS.get_cmdline_user_args().has("--quick")
	var counts := [100, 250, 500] if quick else [100, 250, 500, 1000, 2000]
	for n in counts:
		scenarios.append({"name": "pile_%d" % n, "kind": "pile", "count": n,
			"warm": 30, "measure": 300, "rest": 120})
	scenarios.append({"name": "conveyor_kinematic_fed", "kind": "conveyor",
		"mode": Conveyor.Mode.KINEMATIC, "feed_every": 12, "warm": 30, "measure": 600, "rest": 0})
	scenarios.append({"name": "conveyor_surface_fed", "kind": "conveyor",
		"mode": Conveyor.Mode.SURFACE, "feed_every": 12, "warm": 30, "measure": 600, "rest": 0})
	scenarios.append({"name": "drag_20_while_200_pile", "kind": "drag",
		"count": 200, "drag": 20, "warm": 60, "measure": 480, "rest": 0})
	scenarios.append({"name": "ccd_cannon_60_at_60ms", "kind": "cannon",
		"count": 60, "speed": 60.0, "warm": 5, "measure": 240, "rest": 0})
	scenarios.append({"name": "churn_spawn_despawn", "kind": "churn",
		"count": 0, "warm": 30, "measure": 600, "rest": 0})
	scenarios.append({"name": "cap_overflow_1500_into_cap_200", "kind": "overflow",
		"count": 1500, "warm": 10, "measure": 300, "rest": 60})
	print("\n=== Pinecraft physics bench | Godot %s | Jolt | %d Hz ===" % [
		Engine.get_version_info().string, int(PHYSICS_HZ)])
	_next_scenario()

# --- World construction ----------------------------------------------------

func _build_world() -> void:
	_teardown()
	_world = Node3D.new()
	add_child(_world)
	StressWorld.build_ground(_world)
	StressWorld.build_funnel(_world)
	_manager = LooseItemManager.new()
	_world.add_child(_manager)
	_manager.register_plot(StressWorld.PLOT_ID, Vector3(0, 8, 0))
	_conveyors.clear()

func _teardown() -> void:
	if _world != null:
		_world.queue_free()
		_world = null
	_manager = null
	_conveyors.clear()

func _setup_scenario(s: Dictionary) -> void:
	_build_world()
	match s.kind:
		"pile":
			_manager.per_plot_cap = 4000      # cap disabled: we want raw scaling
			StressWorld.rain_items(_manager, &"log_pine", int(s.count), _rng,
				Vector3(0, 14, 0), 3.4, 0.5)
		"conveyor":
			var c := StressWorld.build_conveyor(_world, Vector3(0, 0.6, 0), 0.0, s.mode, 16.0, 3.0)
			_conveyors.append(c)
		"cannon":
			StressWorld.fire_cannon(_manager, &"ore_iron", int(s.count),
				Vector3(0, 3, 20), Vector3(0, -0.05, -1), float(s.speed), _rng)
		"churn":
			pass
		"overflow":
			_manager.per_plot_cap = Tuning.LOOSE_ITEMS_PER_PLOT
		"drag":
			_manager.per_plot_cap = 4000
			StressWorld.rain_items(_manager, &"log_pine", int(s.count), _rng,
				Vector3(0, 12, 0), 3.2, 0.5)
			_drag_targets.clear()
			_drag_time = 0.0
			for i in int(s.drag):
				var ang := TAU * float(i) / float(s.drag)
				var pos := Vector3(cos(ang) * 14.0, 3.0, sin(ang) * 14.0)
				var item := _manager.spawn(&"log_pine", Transform3D(Basis(), pos), StressWorld.PLOT_ID)
				if item != null:
					item.set_state(LooseItem.State.CARRIED)
					_drag_targets.append(item)

func _next_scenario() -> void:
	_idx += 1
	if _idx >= scenarios.size():
		_report()
		return
	_current = scenarios[_idx]
	_setup_scenario(_current)
	_frames = 0
	_samples = PackedFloat32Array()
	_monitor_samples = PackedFloat32Array()
	_prev_frame_us = 0
	_rest_samples = PackedFloat32Array()
	_settle_frames = 0
	_peak_active = 0
	_peak_pairs = 0
	_peak_awake = 0
	_phase = Phase.WARM

# --- Main loop -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _phase == Phase.DONE:
		return
	_tick_scenario(delta)

	var active := int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	var pairs := int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))
	_peak_active = maxi(_peak_active, active)
	if _frames % 10 == 0:
		_peak_awake = maxi(_peak_awake, _manager.awake_count())
	_peak_pairs = maxi(_peak_pairs, pairs)
	# Wall clock between consecutive physics iterations. With --fixed-fps the
	# main loop runs flat out, so this is the real cost of one simulated frame.
	# (The TIME_PHYSICS_PROCESS monitor only refreshes per rendered frame and is
	# useless in headless, so it is kept only as a cross-check.)
	var now := Time.get_ticks_usec()
	var ms := 0.0
	if _prev_frame_us > 0:
		ms = float(now - _prev_frame_us) / 1000.0
	_prev_frame_us = now
	_monitor_samples.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
	_frames += 1

	match _phase:
		Phase.WARM:
			if _frames >= int(_current.warm):
				_frames = 0
				_wall_start = Time.get_ticks_usec()
				_phase = Phase.MEASURE
		Phase.MEASURE:
			_samples.append(ms)
			if _frames >= int(_current.measure):
				_wall_us = Time.get_ticks_usec() - _wall_start
				_frames = 0
				if int(_current.rest) > 0:
					_phase = Phase.SETTLE
				else:
					_finish_scenario()
		Phase.SETTLE:
			_settle_frames += 1
			# Wait for the pile to go to sleep (or give up after 30 s).
			if _manager.awake_count() == 0 or _settle_frames > 1800:
				_frames = 0
				_phase = Phase.REST
		Phase.REST:
			_rest_samples.append(ms)
			if _frames >= int(_current.rest):
				_finish_scenario()

func _tick_scenario(_delta: float) -> void:
	match _current.get("kind", ""):
		"churn":
			# Continuous spawn/despawn: exercises pooling with zero allocation.
			if _manager.active_count() < 150:
				StressWorld.rain_items(_manager, &"log_pine", 10, _rng, Vector3(0, 10, 0), 2.0, 0.4)
			elif _frames % 3 == 0:
				StressWorld.rain_items(_manager, &"log_pine", 6, _rng, Vector3(0, 10, 0), 2.0, 0.4)
		"overflow":
			if _phase == Phase.WARM or _phase == Phase.MEASURE:
				StressWorld.rain_items(_manager, &"log_pine", 8, _rng, Vector3(0, 12, 0), 3.0, 0.4)
		"conveyor":
			# Feed the belt at a steady rate rather than dumping a heap on it.
			var every: int = int(_current.get("feed_every", 12))
			if _frames % every == 0 and not _conveyors.is_empty():
				var belt: Conveyor = _conveyors[0]
				var entry: Transform3D = belt.global_transform
				var pos: Vector3 = entry.origin + entry.basis.z * (belt.length * 0.5 - 1.0) + Vector3(0, 1.1, 0)
				_manager.spawn(&"log_pine", Transform3D(Basis(), pos), StressWorld.PLOT_ID)
		"drag":
			# Steer carried items along circular paths: the same velocity-driven
			# drag the player uses, 20 of them at once, over a live pile.
			_drag_time += _delta
			for i in _drag_targets.size():
				var item: LooseItem = _drag_targets[i]
				if not is_instance_valid(item) or item.state != LooseItem.State.CARRIED:
					continue
				var ang := TAU * float(i) / float(_drag_targets.size()) + _drag_time * 0.9
				var target := Vector3(cos(ang) * 9.0, 3.5 + sin(_drag_time * 2.0 + float(i)) * 1.5, sin(ang) * 9.0)
				var desired := (target - item.global_position) * 14.0
				if desired.length() > 14.0:
					desired = desired.normalized() * 14.0
				item.linear_velocity = desired
				item.angular_velocity *= 0.6

func _finish_scenario() -> void:
	var r := {
		"name": _current.name,
		"items": _manager.active_count(),
		"peak_active_bodies": _peak_active,
		"peak_awake_items": _peak_awake,
		"awake_at_end": _manager.awake_count(),
		"peak_pairs": _peak_pairs,
		"monitor_avg_ms": _avg(_monitor_samples),
		"avg_ms": _avg(_samples),
		"p95_ms": _percentile(_samples, 0.95),
		"max_ms": _max(_samples),
		"wall_ms_per_frame": float(_wall_us) / 1000.0 / maxf(1.0, float(_samples.size())),
		"rest_avg_ms": _avg(_rest_samples),
		"settle_frames": _settle_frames,
		"recycled": _manager.stat_recycled,
		"killplane": _manager.stat_killplane,
		"forced_sleeps": _manager.stat_forced_sleeps,
		"pooled": _manager.pooled_count(),
	}
	if _current.kind == "cannon":
		r["escaped"] = _count_escaped()
	if _current.kind == "conveyor" and not _conveyors.is_empty():
		r["delivered"] = _count_delivered()
		r["spawned"] = _manager.active_count() + _manager.stat_recycled
	if _current.kind == "drag":
		r["dragged"] = _drag_targets.size()
		r["drag_escaped"] = _count_escaped()
	results.append(r)
	_log_line("  %-34s avg %6.2f ms  p95 %6.2f  max %6.2f  rest %5.2f  items %4d" % [
		r.name, r.avg_ms, r.p95_ms, r.max_ms, r.rest_avg_ms, r.items])
	print("  %-34s avg %6.2f ms  p95 %6.2f  max %6.2f  rest %5.2f  items %4d" % [
		r.name, r.avg_ms, r.p95_ms, r.max_ms, r.rest_avg_ms, r.items])
	_next_scenario()

## Items that left the plot entirely = tunnelling failures.
func _count_escaped() -> int:
	var half := StressWorld.PLOT_SIZE * 0.5 + 1.5
	var escaped := 0
	for item in _manager._active:
		var p: Vector3 = item.global_position
		if absf(p.x) > half or absf(p.z) > half or p.y < -1.0:
			escaped += 1
	return escaped + _manager.stat_killplane

## Items that made it past the far end of the belt. KINEMATIC mode also keeps
## its own counter; position is used so both modes are measured the same way.
func _count_delivered() -> int:
	var belt: Conveyor = _conveyors[0]
	var inv := belt.global_transform.affine_inverse()
	var n := 0
	for item in _manager._active:
		if (inv * item.global_position).z < -belt.length * 0.5:
			n += 1
	return n

## Progress log flushed immediately, so a long run can be watched.
func _log_line(text: String) -> void:
	var f := FileAccess.open("res://bench_progress.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("res://bench_progress.log", FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(text)
	f.close()

# --- Stats -----------------------------------------------------------------

func _avg(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += v
	return t / float(a.size())

func _max(a: PackedFloat32Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, v)
	return m

func _percentile(a: PackedFloat32Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var copy := Array(a)
	copy.sort()
	return float(copy[clampi(int(float(copy.size() - 1) * q), 0, copy.size() - 1)])

func _report() -> void:
	_phase = Phase.DONE
	print("\n--- results (budget %.2f ms/frame at %d Hz) ---" % [FRAME_BUDGET_MS, int(PHYSICS_HZ)])
	print("cpu: %s (%d threads)" % [OS.get_processor_name(), OS.get_processor_count()])
	print("%-34s %8s %8s %8s %8s %7s %7s %8s" % [
		"scenario", "avg ms", "p95 ms", "max ms", "rest ms", "items", "awake", "budget"])
	for r in results:
		print("%-34s %8.2f %8.2f %8.2f %8.2f %7d %7d %7.0f%%" % [
			r.name, r.avg_ms, r.p95_ms, r.max_ms, r.rest_avg_ms,
			r.items, r.peak_awake_items, r.avg_ms / FRAME_BUDGET_MS * 100.0])
	for r in results:
		if r.has("escaped"):
			print("\ntunnelling check (%s): %d item(s) escaped the plot" % [r.name, r.escaped])
		if r.has("delivered"):
			print("conveyor (%s): %d spawned, %d past the far end, %d on belt" % [
				r.name, r.spawned, r.delivered, r.items - r.delivered])
		if r.has("dragged"):
			print("drag (%s): %d items steered, %d escaped/rescued, %d awake at end" % [
				r.name, r.dragged, r.drag_escaped, r.awake_at_end])
	for r in results:
		if r.name.begins_with("pile_") and r.settle_frames > 0:
			print("sleep: %s settled in %.2f s (%d frames) -> %.2f ms/frame at rest" % [
				r.name, float(r.settle_frames) / PHYSICS_HZ, r.settle_frames, r.rest_avg_ms])
	var f := FileAccess.open("res://bench_results.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"godot": Engine.get_version_info().string,
			"engine": ProjectSettings.get_setting("physics/3d/physics_engine"),
			"cpu": OS.get_processor_name(),
			"threads": OS.get_processor_count(),
			"physics_hz": PHYSICS_HZ,
			"results": results,
		}, "  "))
		f.close()
	print("\nwrote bench_results.json")
	get_tree().quit()
