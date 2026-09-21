class_name StorageBin
extends Node3D

## A buffer that swallows items into counters and can pour them back out.
## Useful as an automation sink and as a stockpile while prices are bad.

signal contents_changed(bin: StorageBin)

@export var building_id: StringName = &"storage"

var def: BuildingDef
var manager: LooseItemManager
var plot_id: int = 0
var contents: Dictionary = {}       ## StringName -> int
var capacity: int = 60

var _area: Area3D
var _area_shape: CollisionShape3D
var _output_point: Node3D
var _dispensing: Array = []         ## queued [item_id] to pour out
var _dispense_timer: float = 0.0
var _poll_timer: float = 0.0

func setup(p_manager: LooseItemManager, p_def: BuildingDef, p_plot_id: int = 0) -> void:
	manager = p_manager
	def = p_def
	building_id = p_def.id
	capacity = p_def.capacity
	plot_id = p_plot_id

func _ready() -> void:
	if def == null:
		def = GameData.building(building_id)
		capacity = def.capacity
	var size: Vector3 = def.footprint_world(1.0)

	var body := StaticBody3D.new()
	body.collision_layer = Layers.MACHINE
	body.collision_mask = Layers.MASK_MACHINE
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = Vector3(0, size.y * 0.5, 0)
	body.add_child(cs)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.position = cs.position
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.34, 0.30)
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)

	_area = Area3D.new()
	_area.collision_layer = Layers.TRIGGER
	_area.collision_mask = Layers.LOOSE
	var acs := CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = Vector3(size.x * 0.95, 1.2, size.z * 0.95)
	acs.shape = ab
	acs.position = Vector3(0, size.y + 0.3, 0)
	_area_shape = acs
	_area.add_child(acs)
	_area.body_entered.connect(_on_body)
	add_child(_area)

	_output_point = Node3D.new()
	_output_point.position = Vector3(0, size.y * 0.6, -size.z * 0.5 - 0.8)
	add_child(_output_point)
	set_physics_process(true)

func count() -> int:
	var n := 0
	for k in contents:
		n += int(contents[k])
	return n

func can_accept(_item_id: StringName) -> bool:
	return count() < capacity

func accept_item(item: LooseItem) -> bool:
	if not can_accept(item.item_id):
		return false
	contents[item.item_id] = int(contents.get(item.item_id, 0)) + 1
	manager.despawn(item)
	contents_changed.emit(self)
	return true

func _on_body(body: Node) -> void:
	var item := body as LooseItem
	if item == null or item.state != LooseItem.State.FREE:
		return
	if not Trigger.contains_point(_area_shape, item.global_position, 0.25):
		return
	accept_item(item)

## Queue everything (or one kind) to be poured back out of the front port.
func dispense_all(item_id: StringName = &"") -> int:
	var queued := 0
	for k in contents.keys():
		if item_id != &"" and k != item_id:
			continue
		for i in int(contents[k]):
			_dispensing.append(k)
			queued += 1
		contents.erase(k)
	contents_changed.emit(self)
	return queued

func _physics_process(delta: float) -> void:
	_poll_timer -= delta
	if _poll_timer <= 0.0:
		_poll_timer = 0.25
		for body in Trigger.bodies_inside(_area, _area_shape):
			_on_body(body)
	if _dispensing.is_empty():
		return
	_dispense_timer -= delta
	if _dispense_timer > 0.0:
		return
	_dispense_timer = 0.12       # paced so a full bin cannot spike the solver
	var item_id: StringName = _dispensing.pop_front()
	manager.spawn(item_id, _output_point.global_transform, plot_id,
		-global_transform.basis.z * 1.5)

func summary() -> String:
	if contents.is_empty():
		return "Storage: empty"
	var parts: Array[String] = []
	for k in contents:
		parts.append("%s x%d" % [GameData.item_name(k), int(contents[k])])
	return "Storage (%d/%d): %s" % [count(), capacity, ", ".join(parts)]

func to_dict() -> Dictionary:
	var d := {}
	for k in contents:
		d[String(k)] = int(contents[k])
	return d

func from_dict(d: Dictionary) -> void:
	contents.clear()
	for k in d:
		contents[StringName(k)] = int(d[k])
	contents_changed.emit(self)
