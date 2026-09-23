class_name Splitter
extends Node3D

## Kinematic router: captures an item and hands it to one of its outputs in
## round-robin order (left, straight, right). Like the conveyor it owns captured
## items outright, so routing never depends on friction or luck.

@export var building_id: StringName = &"splitter"
@export var speed: float = 3.5
@export var enabled_outputs: Array[bool] = [true, true, true]

## Overridden by Filter; kept here so the chassis build code is shared.
var body_color: Color = Color(0.22, 0.26, 0.34)

const OUTPUT_DIRS := [Vector3.LEFT, Vector3.FORWARD, Vector3.RIGHT]
const PLATE_THICKNESS := 0.2
const OUTPUT_DISTANCE := 1.6

var def: BuildingDef
var sink_finder: Callable = Callable()
var total_routed: int = 0

var _area: Area3D
var _area_shape: CollisionShape3D
var _routing: Array[LooseItem] = []
var _targets: Dictionary = {}       ## LooseItem -> Vector3 (local target)
var _dirs: Dictionary = {}          ## LooseItem -> int (output index)
var _next_output: int = 0
var _poll_timer: float = 0.0

func setup(p_def: BuildingDef) -> void:
	def = p_def
	building_id = p_def.id

func _ready() -> void:
	if def == null:
		def = GameData.building(building_id)
	var size: Vector3 = def.footprint_world(1.0)

	var body := StaticBody3D.new()
	body.collision_layer = Layers.MACHINE
	body.collision_mask = Layers.MASK_MACHINE
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, PLATE_THICKNESS, size.z)
	cs.shape = box
	# Sitting on the origin, not centred on it: the origin is where a building
	# meets the ground, so a plate centred there is half buried.
	cs.position = Vector3(0, PLATE_THICKNESS * 0.5, 0)
	body.add_child(cs)
	body.add_child(_dress(size).instance("Plate", false))
	add_child(body)

	_area = Area3D.new()
	_area.collision_layer = Layers.TRIGGER
	_area.collision_mask = Layers.LOOSE
	var acs := CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = Vector3(size.x, 1.0, size.z)
	acs.shape = ab
	acs.position = Vector3(0, PLATE_THICKNESS + 0.6, 0)
	_area_shape = acs
	_area.add_child(acs)
	_area.body_entered.connect(_on_body)
	add_child(_area)
	set_physics_process(true)

## A turntable on a bolted plate, with an arrow painted toward each output.
func _dress(size: Vector3) -> Greeble:
	var g := Greeble.new()
	var steel := Color(0.40, 0.42, 0.46)
	g.block(Vector3(size.x, PLATE_THICKNESS, size.z), Vector3(0, PLATE_THICKNESS * 0.5, 0), body_color)
	g.frame(Vector3(size.x, PLATE_THICKNESS, size.z), Transform3D(Basis(), Vector3(0, PLATE_THICKNESS * 0.5, 0)), 0.08, body_color.darkened(0.35))
	g.prism(10, minf(size.x, size.z) * 0.3, minf(size.x, size.z) * 0.28, 0.05,
		Transform3D(Basis(), Vector3(0, PLATE_THICKNESS, 0)), steel)
	g.prism(6, 0.12, 0.12, 0.09, Transform3D(Basis(), Vector3(0, PLATE_THICKNESS, 0)), body_color.lightened(0.25))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			g.block(Vector3(0.08, 0.05, 0.08), Vector3(sx * (size.x * 0.5 - 0.15), PLATE_THICKNESS + 0.02, sz * (size.z * 0.5 - 0.15)), Color(0.72, 0.72, 0.7))
	for dir in OUTPUT_DIRS:
		var d: Vector3 = dir
		var basis := Basis.looking_at(d, Vector3.UP)
		var at := d * minf(size.x, size.z) * 0.36 + Vector3(0, PLATE_THICKNESS + 0.01, 0)
		for side in [-1.0, 1.0]:
			g.box(Vector3(0.07, 0.012, 0.3), Transform3D(basis * Basis(Vector3.UP, side * 0.7), at + basis * Vector3(side * 0.1, 0, 0.08)), Color(0.96, 0.76, 0.20))
	return g

func _on_body(body: Node) -> void:
	var item := body as LooseItem
	if item == null or item.state != LooseItem.State.FREE:
		return
	if not Trigger.contains_point(_area_shape, item.global_position, 0.2):
		return
	var out_index := route_index_for(item)
	if out_index < 0:
		return
	item.set_state(LooseItem.State.CAPTURED)
	_routing.append(item)
	_targets[item] = OUTPUT_DIRS[out_index] * OUTPUT_DISTANCE + Vector3(0, 0.45, 0)
	_dirs[item] = out_index

## Which output a given item should take. Round-robin here; Filter overrides it.
func route_index_for(_item: LooseItem) -> int:
	return _pick_output()

func _pick_output() -> int:
	for i in OUTPUT_DIRS.size():
		var index := (_next_output + i) % OUTPUT_DIRS.size()
		if index < enabled_outputs.size() and enabled_outputs[index]:
			_next_output = (index + 1) % OUTPUT_DIRS.size()
			return index
	return -1

func _physics_process(delta: float) -> void:
	# Polled as well as signalled: a belt can release an item straight onto the
	# splitter without it ever crossing the trigger boundary.
	_poll_timer -= delta
	if _poll_timer <= 0.0:
		_poll_timer = 0.15
		for body in Trigger.bodies_inside(_area, _area_shape):
			_on_body(body)
	if _routing.is_empty():
		return
	var step := speed * delta
	for i in range(_routing.size() - 1, -1, -1):
		var item: LooseItem = _routing[i]
		if not is_instance_valid(item) or item.state != LooseItem.State.CAPTURED:
			_forget(i)
			continue
		var target: Vector3 = _targets[item]
		var local: Vector3 = global_transform.affine_inverse() * item.global_position
		var to_target := target - local
		if to_target.length() <= step:
			_release(i)
			continue
		local += to_target.normalized() * step
		var dir_index: int = _dirs.get(item, 1)
		var yaw: float = atan2(OUTPUT_DIRS[dir_index].x, OUTPUT_DIRS[dir_index].z)
		item.global_transform = global_transform * Transform3D(LooseItem.lying_basis(yaw), local)

func _release(index: int) -> void:
	var item: LooseItem = _routing[index]
	var dir_index: int = _dirs.get(item, 1)
	_forget(index)
	if not is_instance_valid(item) or item.state != LooseItem.State.CAPTURED:
		return
	item.set_state(LooseItem.State.FREE)
	total_routed += 1
	var world_dir: Vector3 = (global_transform.basis * OUTPUT_DIRS[dir_index]).normalized()
	if sink_finder.is_valid():
		var probe: Vector3 = global_position + world_dir * (OUTPUT_DISTANCE + 0.6)
		var sink: Object = sink_finder.call(probe)
		if sink != null and sink.has_method("can_accept") \
				and sink.can_accept(item.item_id) and sink.accept_item(item):
			return
	item.linear_velocity = world_dir * speed

func _forget(index: int) -> void:
	var item: LooseItem = _routing[index]
	_routing.remove_at(index)
	_targets.erase(item)
	_dirs.erase(item)
