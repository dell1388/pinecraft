class_name Splitter
extends Node3D

## A diverter plate: powered rollers under each piece that lands on it push
## it toward one of the outputs, in round-robin order (left, straight, right).
## The piece stays a free physics body the whole way - the rollers only grip
## it, the way a belt does - so a heavy log turns slowly, a light billet
## shoots off, and two pieces arriving together can shove each other about.

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
var _dirs: Dictionary = {}          ## LooseItem -> int (output index), pieces on the plate
var _half: Vector2 = Vector2.ONE
var _next_output: int = 0
var _poll_timer: float = 0.0

func setup(p_def: BuildingDef) -> void:
	def = p_def
	building_id = p_def.id

func _ready() -> void:
	if def == null:
		def = GameData.building(building_id)
	var size: Vector3 = def.footprint_world(1.0)
	_half = Vector2(size.x, size.z) * 0.5

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
	# Slick steel: the rollers do the pushing, not the plate.
	var pm := PhysicsMaterial.new()
	pm.friction = 0.15
	body.physics_material_override = pm
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

## How hard the rollers can push, as a fraction of gravity: a real grip,
## not a grab.
const GRIP := 0.9

func _physics_process(delta: float) -> void:
	_poll_timer -= delta
	if _poll_timer <= 0.0:
		_poll_timer = 0.05
		_poll()
	if _dirs.is_empty():
		return
	var up := global_transform.basis.y
	for item in _dirs.keys():
		if not is_instance_valid(item) or item.state != LooseItem.State.FREE:
			_dirs.erase(item)
			continue
		# Only what is actually down on the rollers is driven.
		var local: Vector3 = global_transform.affine_inverse() * item.global_position
		if local.y - item.extent_along(up) > PLATE_THICKNESS + 0.12:
			continue
		var index: int = _dirs[item]
		var dir: Vector3 = (global_transform.basis * OUTPUT_DIRS[index]).normalized()
		item.grip_toward(dir * speed, up, GRIP, delta)

## Who is on the plate. A piece gets its output the moment it lands and keeps
## it until it leaves, which is when it counts as routed.
func _poll() -> void:
	var inside: Dictionary = {}
	for body in Trigger.bodies_inside(_area, _area_shape, 0.1):
		var item := body as LooseItem
		if item != null and item.state == LooseItem.State.FREE:
			inside[item] = true
	for item in _dirs.keys():
		if inside.has(item):
			continue
		_dirs.erase(item)
		if is_instance_valid(item) and item.get_parent() != null:
			total_routed += 1
	for item in inside:
		if not _dirs.has(item):
			var index := route_index_for(item)
			if index < 0:
				continue
			_dirs[item] = index
