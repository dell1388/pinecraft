extends Node3D
## Throwaway diagnostic: watches one surface conveyor and one settling pile.

var manager: LooseItemManager
var belt: Conveyor
var t := 0.0
var mode := "surface"

func _ready() -> void:
	mode = "pile" if OS.get_cmdline_user_args().has("--pile") else "surface"
	StressWorld.build_ground(self)
	manager = LooseItemManager.new()
	manager.per_plot_cap = 4000
	add_child(manager)
	manager.register_plot(0, Vector3(0, 8, 0))
	if mode == "surface":
		belt = StressWorld.build_conveyor(self, Vector3(0, 0.6, 0), 0.0, Conveyor.Mode.SURFACE, 16.0, 3.0)
		await get_tree().physics_frame
		print("belt constant_linear_velocity = ", belt.get_child(0).constant_linear_velocity if belt.get_child_count() > 0 else "n/a")
		for i in 5:
			manager.spawn(&"log_pine", Transform3D(Basis(), Vector3(0, 1.2, 7.0 - float(i) * 1.5)), 0)
	else:
		StressWorld.build_funnel(self)
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		StressWorld.rain_items(manager, &"log_pine", 500, rng, Vector3(0, 14, 0), 3.4, 0.5)

func _physics_process(delta: float) -> void:
	t += delta
	if fmod(t, 1.0) < delta:
		if mode == "surface":
			var zs := []
			for item in manager._active:
				zs.append("z%.1f y%.2f v%.2f %s" % [item.global_position.z, item.global_position.y,
					item.linear_velocity.z, "SLEEP" if item.sleeping else "awake"])
			print("t=%.0fs  z: %s" % [t, ", ".join(zs)])
		else:
			var awake := manager.awake_count()
			var vsum := 0.0
			var vmax := 0.0
			for item in manager._active:
				var s: float = item.linear_velocity.length()
				vsum += s
				vmax = maxf(vmax, s)
			print("t=%.0fs awake=%d avg_speed=%.3f max_speed=%.3f" % [t, awake, vsum / 500.0, vmax])
	if t > 30.0:
		get_tree().quit()
