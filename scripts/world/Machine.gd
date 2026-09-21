class_name Machine
extends Node3D

## A processing machine (sawmill / furnace / workbench).
##
## Kinematic by construction: a static collider for the chassis plus two trigger
## volumes. Items that touch the input trigger are removed from the physics
## world and become counters in a buffer, so a busy factory does not accumulate
## simulated bodies. Outputs are spawned back as real items at the output port.

signal produced(machine: Machine, recipe: RecipeDef)
signal state_changed(machine: Machine)

@export var building_id: StringName = &"sawmill"

var def: BuildingDef
var machine_def: MachineDef
var manager: LooseItemManager
var plot_id: int = 0

var buffer: Dictionary = {}          ## StringName -> int, waiting inputs
var active_recipe: RecipeDef = null
var progress: float = 0.0
var stalled: bool = false
var total_produced: int = 0

var _body: StaticBody3D
var _input_area: Area3D
var _output_area: Area3D
var _output_point: Node3D
var _input_shape: CollisionShape3D
var _output_shape: CollisionShape3D
var _output_backlog: int = 0
var _backlog_timer: float = 0.0

func setup(p_manager: LooseItemManager, p_def: BuildingDef, p_plot_id: int = 0) -> void:
	manager = p_manager
	def = p_def
	building_id = p_def.id
	plot_id = p_plot_id
	machine_def = GameData.machine(p_def.machine)

func _ready() -> void:
	if def == null:
		def = GameData.building(building_id)
	if machine_def == null and def != null:
		machine_def = GameData.machine(def.machine)
	_build()
	set_physics_process(true)

func _build() -> void:
	var size: Vector3 = def.footprint_world(1.0)
	_body = StaticBody3D.new()
	_body.collision_layer = Layers.MACHINE
	_body.collision_mask = Layers.MASK_MACHINE
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = Vector3(0, size.y * 0.5, 0)
	_body.add_child(cs)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.position = cs.position
	var mat := StandardMaterial3D.new()
	mat.albedo_color = machine_def.color if machine_def != null else Color(0.4, 0.4, 0.4)
	mesh.material_override = mat
	_body.add_child(mesh)
	add_child(_body)

	# Input hopper: a mouth on the +Z face.
	_input_area = Area3D.new()
	_input_area.collision_layer = Layers.TRIGGER
	_input_area.collision_mask = Layers.LOOSE
	var ics := CollisionShape3D.new()
	var ib := BoxShape3D.new()
	ib.size = Vector3(size.x * 0.9, 1.4, 1.2)
	ics.shape = ib
	ics.position = Vector3(0, size.y + 0.2, size.z * 0.5 + 0.4)
	_input_shape = ics
	_input_area.add_child(ics)
	_input_area.body_entered.connect(_on_input_body)
	add_child(_input_area)

	# Output port on the -Z face, with a zone that measures backlog.
	_output_point = Node3D.new()
	_output_point.position = Vector3(0, size.y * 0.55, -size.z * 0.5 - 0.9)
	add_child(_output_point)

	_output_area = Area3D.new()
	_output_area.collision_layer = Layers.TRIGGER
	_output_area.collision_mask = Layers.LOOSE
	var ocs := CollisionShape3D.new()
	var ob := BoxShape3D.new()
	ob.size = Vector3(maxf(2.0, size.x), 2.0, 2.4)
	ocs.shape = ob
	ocs.position = _output_point.position
	_output_shape = ocs
	_output_area.add_child(ocs)
	add_child(_output_area)

## World-space centre of the input mouth: where belts should deliver and where
## the player should aim a dropped load.
func input_point() -> Vector3:
	return _input_shape.global_position if _input_shape != null else global_position

## World-space point where finished goods appear.
func output_point() -> Vector3:
	return _output_point.global_position if _output_point != null else global_position

## Item-sink protocol, shared with Storage and SellZone.
func can_accept(item_id: StringName) -> bool:
	if machine_def == null:
		return false
	if _buffer_count() >= machine_def.input_slots:
		return false
	return GameData.machine_accepts(def.machine, item_id)

func accept_item(item: LooseItem) -> bool:
	if not can_accept(item.item_id):
		return false
	buffer[item.item_id] = int(buffer.get(item.item_id, 0)) + 1
	manager.despawn(item)
	state_changed.emit(self)
	return true

func _on_input_body(body: Node) -> void:
	var item := body as LooseItem
	if item == null or item.state == LooseItem.State.POOLED:
		return
	# Never swallow something the player is holding or a belt owns.
	if item.state != LooseItem.State.FREE:
		return
	if not Trigger.contains_point(_input_shape, item.global_position, 0.25):
		return
	accept_item(item)

func _buffer_count() -> int:
	var n := 0
	for k in buffer:
		n += int(buffer[k])
	return n

func input_summary() -> String:
	if buffer.is_empty():
		return "empty"
	var parts: Array[String] = []
	for k in buffer:
		parts.append("%s x%d" % [GameData.item_name(k), int(buffer[k])])
	return ", ".join(parts)

# --- Processing ------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# Backlog is polled rather than tracked per item: items can leave the output
	# zone by belt, by player or by rolling away, and polling handles all three.
	_backlog_timer += delta
	if _backlog_timer >= 0.25:
		_backlog_timer = 0.0
		_output_backlog = Trigger.bodies_inside(_output_area, _output_shape).size()
		# Items dropped straight into the hopper (or released there by a belt)
		# may never fire body_entered, so the mouth is polled as well.
		for body in Trigger.bodies_inside(_input_area, _input_shape):
			_on_input_body(body)

	if active_recipe == null:
		if machine_def != null and _output_backlog >= machine_def.output_backlog:
			_set_stalled(true)
			return
		var next := GameData.first_ready_recipe(def.machine, buffer)
		if next == null:
			_set_stalled(false)
			return
		active_recipe = next
		active_recipe.consume_from(buffer)
		progress = 0.0
		_set_stalled(false)
		state_changed.emit(self)
		return

	progress += delta
	if progress < active_recipe.seconds:
		return
	_finish()

func _finish() -> void:
	var recipe := active_recipe
	active_recipe = null
	progress = 0.0
	for item_id in recipe.outputs:
		for i in int(recipe.outputs[item_id]):
			var xform := _output_point.global_transform
			xform.origin += Vector3(randf_range(-0.15, 0.15), float(i) * 0.12, randf_range(-0.15, 0.15))
			var spawned := manager.spawn(item_id, xform, plot_id,
				-global_transform.basis.z * 1.2)
			if spawned == null:
				break
			total_produced += 1
	produced.emit(self, recipe)
	state_changed.emit(self)

func _set_stalled(value: bool) -> void:
	if stalled == value:
		return
	stalled = value
	state_changed.emit(self)

func status_line() -> String:
	if active_recipe != null:
		return "%s: %d%%" % [def.display_name, int(progress / active_recipe.seconds * 100.0)]
	if stalled:
		return "%s: output blocked" % def.display_name
	return "%s: idle (%s)" % [def.display_name, input_summary()]

func to_dict() -> Dictionary:
	var d := {"buffer": {}, "progress": progress, "total_produced": total_produced}
	for k in buffer:
		d["buffer"][String(k)] = int(buffer[k])
	if active_recipe != null:
		d["recipe"] = String(active_recipe.id)
	return d

func from_dict(d: Dictionary) -> void:
	buffer.clear()
	for k in d.get("buffer", {}):
		buffer[StringName(k)] = int(d["buffer"][k])
	total_produced = int(d.get("total_produced", 0))
	progress = float(d.get("progress", 0.0))
	var rid := StringName(d.get("recipe", ""))
	active_recipe = GameData.recipes.get(rid) if rid != &"" else null
