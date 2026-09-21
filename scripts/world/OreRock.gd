class_name OreRock
extends StaticBody3D

## A minable outcrop: one box collider under a small cluster of rotated boxes,
## so it reads as broken rock rather than a crate. Breaking it drops ore pieces.

signal broken(rock: OreRock)

@export var max_health: float = 140.0
@export var ore_item: StringName = &"ore_iron"
@export var ore_count: int = 4
@export var radius: float = 1.2
@export var respawn_seconds: float = 40.0

var health: float
var plot_id: int = 0
var manager: LooseItemManager

var _parts: Array[MeshInstance3D] = []
var _shape: CollisionShape3D
var _respawn_timer: float = -1.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	health = max_health
	collision_layer = Layers.TREE      # shares the "resource node" layer
	collision_mask = Layers.WORLD
	_rng.seed = hash(name) + int(position.x * 13.0) + int(position.z * 29.0)
	_build()
	set_process(false)

func _build() -> void:
	var ore_def := GameData.item(ore_item)
	var stone := Color(0.34, 0.33, 0.31)
	var seam: Color = ore_def.color if ore_def != null else Color(0.5, 0.5, 0.5)

	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(radius * 1.9, radius * 1.5, radius * 1.9)
	_shape.shape = box
	_shape.position = Vector3(0, radius * 0.75, 0)
	add_child(_shape)

	# A main mass plus a few shoulders, each tilted a little.
	_add_block(Vector3(radius * 1.7, radius * 1.4, radius * 1.6),
		Vector3(0, radius * 0.7, 0), _rng.randf_range(-0.2, 0.2), stone)
	for i in 3:
		var scale: float = _rng.randf_range(0.45, 0.75)
		var angle: float = TAU * float(i) / 3.0 + _rng.randf_range(-0.4, 0.4)
		_add_block(Vector3(radius * scale, radius * scale * 0.9, radius * scale),
			Vector3(cos(angle) * radius * 0.7, radius * _rng.randf_range(0.3, 0.95),
				sin(angle) * radius * 0.7),
			_rng.randf_range(-0.5, 0.5), stone.lightened(_rng.randf_range(0.0, 0.12)))
	# Ore seams: small bright blocks, so you can tell iron from gold at a glance.
	for i in 3:
		var angle2: float = TAU * _rng.randf()
		_add_block(Vector3(radius * 0.32, radius * 0.22, radius * 0.3),
			Vector3(cos(angle2) * radius * 0.78, radius * _rng.randf_range(0.4, 1.1),
				sin(angle2) * radius * 0.78),
			_rng.randf_range(-0.6, 0.6), seam)

func _add_block(size: Vector3, pos: Vector3, tilt: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation = Vector3(tilt * 0.6, _rng.randf_range(0.0, PI), tilt)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mi.material_override = mat
	add_child(mi)
	_parts.append(mi)

## Returns true if this hit broke the rock.
func mine(damage: float, from: Vector3) -> bool:
	if health <= 0.0:
		return false
	health -= damage
	if not _parts.is_empty():
		_parts[0].scale = Vector3(1.04, 0.97, 1.04)
		create_tween().tween_property(_parts[0], "scale", Vector3.ONE, 0.1)
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
	for p in _parts:
		p.visible = intact
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
