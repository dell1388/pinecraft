extends Node3D
## Throwaway diagnostic harness; mode is chosen with a -- flag.

var manager: LooseItemManager
var bin: StorageBin
var t := 0.0
var mode := "bin"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--pile"):
		mode = "pile"
	elif args.has("--surface"):
		mode = "surface"
	StressWorld.build_ground(self, 60.0)
	manager = LooseItemManager.new()
	manager.per_plot_cap = 400
	add_child(manager)
	manager.register_plot(0, Vector3(0, 6, 0))
	await get_tree().physics_frame
	match mode:
		"bin":
			bin = StorageBin.new()
			bin.setup(manager, GameData.building(&"storage"), 0)
			add_child(bin)
			await get_tree().physics_frame
			for i in 5:
				manager.spawn(&"ingot_iron", Transform3D(Basis(),
					bin.global_position + Vector3(0, 2.6 + float(i) * 0.3, 0)), 0)
			print("bin size=", (bin.get_child(0) as StaticBody3D).get_child(0).shape.size,
				" output=", bin.get_node_or_null("."), " ")
		"pile":
			StressWorld.build_funnel(self)
			var rng := RandomNumberGenerator.new()
			rng.seed = 1
			StressWorld.rain_items(manager, &"log_pine", 500, rng, Vector3(0, 14, 0), 3.4, 0.5)

func _physics_process(delta: float) -> void:
	t += delta
	if fmod(t, 0.5) >= delta:
		return
	match mode:
		"bin":
			if bin == null:
				return
			if absf(t - 1.5) < delta:
				print("dispensing ", bin.dispense_all())
			var lines := []
			for item in manager._active:
				lines.append("%s@%.2f,%.2f,%.2f %s" % [item.item_id,
					item.global_position.x, item.global_position.y, item.global_position.z,
					LooseItem.State.keys()[item.state]])
			print("t=%.1f bin=%d loose=%d  %s" % [t, bin.count(), manager.active_count(), ", ".join(lines)])
		"pile":
			print("t=%.1f awake=%d" % [t, manager.awake_count()])
	if t > 6.0:
		get_tree().quit()
