class_name ChoppableTree
extends StaticBody3D

## A tree that takes hits and, when felled, turns into loose logs.
## Static until it dies: a standing tree costs one static box in broadphase.

signal felled(tree: ChoppableTree)

@export var max_health: float = 100.0
@export var log_count: int = 6
@export var log_item: StringName = &"log_pine"
@export var trunk_height: float = 6.0
@export var trunk_radius: float = 0.4
@export var respawn_seconds: float = 25.0

var health: float
var plot_id: int = 0
var manager: LooseItemManager

var _mesh: MeshInstance3D
var _canopy: MeshInstance3D
var _shape: CollisionShape3D
var _respawn_timer: float = -1.0

func _ready() -> void:
	health = max_health
	collision_layer = Layers.TREE
	collision_mask = Layers.WORLD
	_build()
	set_process(false)

func _build() -> void:
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(trunk_radius * 2.0, trunk_height, trunk_radius * 2.0)
	_shape.shape = box
	_shape.position = Vector3(0, trunk_height * 0.5, 0)
	add_child(_shape)

	_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = trunk_radius * 0.8
	cyl.bottom_radius = trunk_radius
	cyl.height = trunk_height
	_mesh.mesh = cyl
	_mesh.position = Vector3(0, trunk_height * 0.5, 0)
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.36, 0.25, 0.15)
	_mesh.material_override = trunk_mat
	add_child(_mesh)

	_canopy = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = trunk_radius * 6.0
	cone.height = trunk_height * 0.9
	_canopy.mesh = cone
	_canopy.position = Vector3(0, trunk_height * 1.05, 0)
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.13, 0.42, 0.18)
	_canopy.material_override = leaf_mat
	add_child(_canopy)

## Returns true if this hit felled the tree.
func chop(damage: float, from: Vector3) -> bool:
	if health <= 0.0:
		return false
	health -= damage
	_mesh.scale = Vector3(1.04, 0.99, 1.04)   # cheap hit feedback
	create_tween().tween_property(_mesh, "scale", Vector3.ONE, 0.12)
	if health > 0.0:
		return false
	_fell(from)
	return true

func _fell(from: Vector3) -> void:
	var dir := (global_position - from)
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	if manager != null:
		for i in log_count:
			var height := 1.0 + float(i) * (trunk_height / float(log_count))
			var pos := global_position + Vector3(0, height, 0) + dir * 0.2
			var xform := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), pos)
			manager.spawn(log_item, xform, plot_id, dir * 3.0 + Vector3.UP * 1.5)
	_set_standing(false)
	felled.emit(self)
	if respawn_seconds > 0.0:
		_respawn_timer = respawn_seconds
		set_process(true)

func _set_standing(standing: bool) -> void:
	_mesh.visible = standing
	_canopy.visible = standing
	_shape.disabled = not standing
	collision_layer = Layers.TREE if standing else 0

func _process(delta: float) -> void:
	if _respawn_timer < 0.0:
		return
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_timer = -1.0
		health = max_health
		_set_standing(true)
		set_process(false)
