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

	add_child(_dress().instance("Chute"))

## A grated pit with a glowing rim and a coin sign on a post: somewhere you
## throw things and money comes back.
func _dress() -> Greeble:
	var g := Greeble.new()
	var gold := Color(0.95, 0.76, 0.22)
	var steel := Color(0.36, 0.37, 0.40)
	g.block(Vector3(extents.x, 0.1, extents.z), Vector3(0, 0.05, 0), Color(0.10, 0.10, 0.11))
	var bars := int(extents.x / 0.25)
	for i in bars:
		var x := -extents.x * 0.5 + (float(i) + 0.5) * extents.x / float(bars)
		g.block(Vector3(0.06, 0.06, extents.z - 0.2), Vector3(x, 0.13, 0), steel)
	g.frame(Vector3(extents.x, 0.2, extents.z), Transform3D(Basis(), Vector3(0, 0.1, 0)), 0.16, gold.darkened(0.2))
	for sx in [-1.0, 1.0]:
		g.box(Vector3(0.05, 0.05, extents.z), Transform3D(Basis(), Vector3(sx * extents.x * 0.5, 0.22, 0)), gold, true)
		g.box(Vector3(extents.x, 0.05, 0.05), Transform3D(Basis(), Vector3(0, 0.22, sx * extents.z * 0.5)), gold, true)
	var post := Vector3(extents.x * 0.5 - 0.1, 0, -extents.z * 0.5 + 0.1)
	g.block(Vector3(0.12, 2.2, 0.12), post + Vector3(0, 1.1, 0), steel)
	g.prism(12, 0.42, 0.42, 0.08, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), post + Vector3(0, 2.3, 0.04)), gold, true)
	g.box(Vector3(0.1, 0.46, 0.1), Transform3D(Basis(), post + Vector3(0, 2.3, 0.13)), Color(0.55, 0.40, 0.08))
	return g

func can_accept(_item_id: StringName) -> bool:
	return true

func accept_item(item: LooseItem) -> bool:
	var value := Economy.sell(item.item_id, item.dims)
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
