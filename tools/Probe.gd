extends Node3D
## Throwaway diagnostic harness; mode is chosen with a -- flag.

var manager: LooseItemManager
var tree: ChoppableTree
var trunk: LooseItem
var t := 0.0
var mode := "fell"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--pile"):
		mode = "pile"
	StressWorld.build_ground(self, 60.0)
	manager = LooseItemManager.new()
	manager.per_plot_cap = 400
	add_child(manager)
	manager.register_plot(0, Vector3(0, 6, 0))
	await get_tree().physics_frame
	if mode == "fell":
		tree = ChoppableTree.new()
		tree.manager = manager
		tree.trunk_height = 7.0
		tree.trunk_radius = 0.34
		tree.trunk_taper = 0.6
		tree.branch_count = 3
		tree.respawn_seconds = 0.0
		add_child(tree)
		await get_tree().physics_frame
		tree.chop(9999.0, Vector3(0, 0, 6))
		await get_tree().physics_frame
		for item in manager.free_items():
			if trunk == null or item.volume() > trunk.volume():
				trunk = item
		print("trunk mass=%.0f kg  volume=%.3f  sleeping=%s  av=%s  lv=%s" % [
			trunk.mass, trunk.volume(), trunk.sleeping, trunk.angular_velocity, trunk.linear_velocity])
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		StressWorld.rain_items(manager, &"wood_pine", 500, rng, Vector3(0, 14, 0), 3.4, 0.5)

func _physics_process(delta: float) -> void:
	t += delta
	if fmod(t, 0.5) >= delta:
		return
	if mode == "fell" and is_instance_valid(trunk):
		print("t=%.1f  upright=%.2f  y=%.2f  av=%.2f  lv=%.2f  sleep=%s  awake=%d" % [
			t, absf(trunk.global_transform.basis.y.dot(Vector3.UP)), trunk.global_position.y,
			trunk.angular_velocity.length(), trunk.linear_velocity.length(),
			trunk.sleeping, manager.awake_count()])
	elif mode == "pile":
		print("t=%.1f awake=%d" % [t, manager.awake_count()])
	if t > 6.0:
		get_tree().quit()
