class_name StorageBin
extends Node3D

## A buffer that swallows items into counters and can pour them back out.
## Useful as an automation sink and as a stockpile while prices are bad.

signal contents_changed(bin: StorageBin)

@export var building_id: StringName = &"storage"

var def: BuildingDef
var manager: LooseItemManager
var plot_id: int = 0
var contents: Array[Dictionary] = []   ## {id: StringName, dims: Dictionary}
var capacity_m3: float = 6.0

var _area: Area3D
var _area_shape: CollisionShape3D
var _output_point: Node3D
var _dispensing: Array[Dictionary] = []   ## queued {id, dims} to pour out
var _dispense_timer: float = 0.0
var _poll_timer: float = 0.0

func setup(p_manager: LooseItemManager, p_def: BuildingDef, p_plot_id: int = 0) -> void:
	manager = p_manager
	def = p_def
	building_id = p_def.id
	capacity_m3 = float(p_def.capacity)
	plot_id = p_plot_id

func _ready() -> void:
	if def == null:
		def = GameData.building(building_id)
		capacity_m3 = float(def.capacity)
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
	return contents.size()

## Bins hold a volume, not a number of items, so one trunk fills more of a bin
## than one billet does.
func stored_m3() -> float:
	var total := 0.0
	for entry in contents:
		total += Solid.volume(entry.dims)
	return total

func can_accept(_item_id: StringName) -> bool:
	return stored_m3() < capacity_m3

func accept_item(item: LooseItem) -> bool:
	if not can_accept(item.item_id):
		return false
	contents.append({"id": item.item_id, "dims": item.dims.duplicate()})
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
	var keep: Array[Dictionary] = []
	var queued := 0
	for entry in contents:
		if item_id != &"" and entry.id != item_id:
			keep.append(entry)
			continue
		_dispensing.append(entry)
		queued += 1
	contents = keep
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
	var entry: Dictionary = _dispensing.pop_front()
	var origin := _output_point.global_transform
	manager.spawn(entry.id, Transform3D(LooseItem.lying_basis(origin.basis.get_euler().y),
		origin.origin), plot_id, -global_transform.basis.z * 1.5, entry.dims)

func summary() -> String:
	if contents.is_empty():
		return "Storage: empty (0.0/%.1f m3)" % capacity_m3
	var counts: Dictionary = {}
	for entry in contents:
		counts[entry.id] = int(counts.get(entry.id, 0)) + 1
	var parts: Array[String] = []
	for k in counts:
		parts.append("%s x%d" % [GameData.item_name(k), int(counts[k])])
	return "Storage (%.2f/%.1f m3): %s" % [stored_m3(), capacity_m3, ", ".join(parts)]

func to_dict() -> Dictionary:
	var out: Array = []
	for entry in contents:
		out.append({"id": String(entry.id), "dims": Solid.to_dict(entry.dims)})
	return {"contents": out}

func from_dict(d: Dictionary) -> void:
	contents.clear()
	for entry in d.get("contents", []):
		contents.append({"id": StringName(entry.get("id", "")), "dims": Solid.from_dict(entry.get("dims", {}))})
	contents_changed.emit(self)
