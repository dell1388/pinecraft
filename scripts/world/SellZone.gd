class_name SellZone
extends Node3D

## Sells anything dropped into it at today's price, then removes it.

signal sold(item_id: StringName, value: int)

@export var building_id: StringName = &"sell_chute"
@export var extents: Vector3 = Vector3(3.0, 2.0, 3.0)

var manager: LooseItemManager
var def: BuildingDef
var session_total: int = 0
var last_sale_text: String = ""

var _area: Area3D
var _area_shape: CollisionShape3D

func setup(p_manager: LooseItemManager, p_def: BuildingDef = null) -> void:
	manager = p_manager
	def = p_def
	if p_def != null:
		extents = p_def.footprint_world(1.0)

func _ready() -> void:
	_area = Area3D.new()
	_area.collision_layer = Layers.TRIGGER
	_area.collision_mask = Layers.LOOSE
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = extents
	cs.shape = box
	cs.position = Vector3(0, extents.y * 0.5, 0)
	_area_shape = cs
	_area.add_child(cs)
	_area.body_entered.connect(_on_body)
	add_child(_area)
	set_physics_process(true)

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(extents.x, 0.12, extents.z)
	mesh.mesh = bm
	mesh.position = Vector3(0, 0.06, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.72, 0.20)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.42, 0.08)
	mesh.material_override = mat
	add_child(mesh)

func can_accept(_item_id: StringName) -> bool:
	return true

func accept_item(item: LooseItem) -> bool:
	var value := Economy.sell(item.item_id, 1)
	session_total += value
	last_sale_text = "+$%d  %s" % [value, GameData.item_name(item.item_id)]
	sold.emit(item.item_id, value)
	manager.despawn(item)
	return true

var _poll_timer: float = 0.0

func _physics_process(delta: float) -> void:
	# Polled as well as signalled: an item dropped inside the zone, or spawned
	# there by a belt hand-off, may never cross the boundary.
	_poll_timer -= delta
	if _poll_timer > 0.0:
		return
	_poll_timer = 0.2
	for body in Trigger.bodies_inside(_area, _area_shape):
		_on_body(body)

func _on_body(body: Node) -> void:
	var item := body as LooseItem
	if item == null or item.state != LooseItem.State.FREE:
		return
	if not Trigger.contains_point(_area_shape, item.global_position, 0.25):
		return
	accept_item(item)
