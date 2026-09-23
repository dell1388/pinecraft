class_name StressTest
extends Node3D

## Playable physics stress-test scene: 500 logs piling, trees to chop, items to
## drag, and a normal and a fast conveyor running side by side.

@export var tree_count: int = 14
@export var initial_logs: int = 0

var manager: LooseItemManager
var player: Player
var hud: StressHUD
var conveyors: Array[Conveyor] = []
var trees: Array[ChoppableTree] = []

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 20260921
	InputSetup.ensure()
	StressWorld.build_environment(self)
	StressWorld.build_ground(self)
	StressWorld.build_funnel(self)

	manager = LooseItemManager.new()
	manager.name = "LooseItems"
	add_child(manager)
	manager.register_plot(StressWorld.PLOT_ID, Vector3(0, 8, 0))

	trees = StressWorld.build_trees(self, manager, tree_count, _rng)

	conveyors.append(StressWorld.build_conveyor(
		self, Vector3(-14, 0.6, 0), 0.0))
	conveyors.append(StressWorld.build_conveyor(
		self, Vector3(14, 0.6, 0), 0.0, 12.0, 5.0))

	player = _make_player()
	add_child(player)
	player.manager = manager

	hud = StressHUD.new()
	hud.manager = manager
	hud.conveyors = conveyors
	add_child(hud)

	if initial_logs > 0:
		StressWorld.rain_items(manager, &"wood_pine", initial_logs, _rng)

func _make_player() -> Player:
	var p := Player.new()
	p.name = "Player"
	p.position = Vector3(0, 2, 18)
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
	cam.current = true
	p.add_child(cam)
	return p

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			StressWorld.rain_items(manager, &"wood_pine", 100, _rng)
		KEY_2:
			StressWorld.rain_items(manager, &"wood_pine", 500, _rng)
		KEY_3:
			manager.despawn_all()
		KEY_4:
			var from: Vector3 = player.global_position + Vector3(0, 1.5, 0)
			var dir: Vector3 = -player.camera.global_transform.basis.z
			StressWorld.fire_cannon(manager, &"ore_iron", 20, from + dir * 2.0, dir, 60.0, _rng)
		KEY_5:
			_feed_conveyors(24)
		KEY_6:
			for t in trees:
				t.chop(9999.0, global_position)
		KEY_7:
			hud.reset_worst()

func _feed_conveyors(count: int) -> void:
	for c in conveyors:
		var entry: Transform3D = c.global_transform
		for i in count:
			var pos: Vector3 = entry.origin + entry.basis.z * (c.length * 0.5 - 0.8) \
				+ Vector3(0, 1.2 + float(i) * 0.05, 0)
			manager.spawn(&"wood_pine", Transform3D(Basis(), pos), StressWorld.PLOT_ID)
