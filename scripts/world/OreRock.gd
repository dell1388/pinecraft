class_name OreRock
extends StaticBody3D

## A minable rock. Same shape as ChoppableTree: static while alive, spawns loose
## ore when broken, then respawns after a delay.

signal broken(rock: OreRock)

@export var max_health: float = 120.0
@export var ore_item: StringName = &"ore_iron"
@export var ore_count: int = 4
@export var radius: float = 1.2
@export var respawn_seconds: float = 30.0

var health: float
var plot_id: int = 0
var manager: LooseItemManager

var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _respawn_timer: float = -1.0

func _ready() -> void:
	health = max_health
	collision_layer = Layers.TREE      # same "resource node" layer as trees
	collision_mask = Layers.WORLD
	_build()
	set_process(false)

func _build() -> void:
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(radius * 1.8, radius * 1.5, radius * 1.8)
	_shape.shape = box
	_shape.position = Vector3(0, radius * 0.75, 0)
	add_child(_shape)

	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	_mesh.mesh = bm
	_mesh.position = _shape.position
	_mesh.rotation.y = randf_range(0.0, PI)
	var mat := StandardMaterial3D.new()
	var ore_def := GameData.item(ore_item)
	mat.albedo_color = ore_def.color.darkened(0.25) if ore_def != null else Color(0.4, 0.4, 0.4)
	_mesh.material_override = mat
	add_child(_mesh)

## Returns true if this hit broke the rock.
func mine(damage: float, from: Vector3) -> bool:
	if health <= 0.0:
		return false
	health -= damage
	_mesh.scale = Vector3(1.05, 0.96, 1.05)
	create_tween().tween_property(_mesh, "scale", Vector3.ONE, 0.1)
	if health > 0.0:
		return false
	_break(from)
	return true

func _break(from: Vector3) -> void:
	var dir := global_position - from
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.01 else Vector3.FORWARD
	if manager != null:
		for i in ore_count:
			var pos := global_position + Vector3(
				randf_range(-0.5, 0.5), radius + 0.4 + float(i) * 0.3, randf_range(-0.5, 0.5))
			manager.spawn(ore_item, Transform3D(Basis(), pos), plot_id,
				dir * 1.5 + Vector3.UP * 2.0)
	_set_intact(false)
	broken.emit(self)
	if respawn_seconds > 0.0:
		_respawn_timer = respawn_seconds
		set_process(true)

func _set_intact(intact: bool) -> void:
	_mesh.visible = intact
	_shape.disabled = not intact
	collision_layer = Layers.TREE if intact else 0

func _process(delta: float) -> void:
	if _respawn_timer < 0.0:
		return
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_timer = -1.0
		health = max_health
		_set_intact(true)
		set_process(false)
