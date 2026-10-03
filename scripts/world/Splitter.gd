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
## Level with a belt's deck, so a piece rides off a belt straight onto it
## and off it onto the next.
const PLATE_THICKNESS := Conveyor.DECK_THICKNESS
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

	# A gate across each way out, down when that way is locked.
	for i in OUTPUT_DIRS.size():
		_gates.append(_make_gate(i, size))
	_show_gates()

	_area = Area3D.new()
	_area.collision_layer = Layers.TRIGGER
	_area.collision_mask = Layers.LOOSE
	var acs := CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = Vector3(size.x, 1.0, size.z)
	acs.shape = ab
	# From the plate's top up: a flat piece (an ingot lying down) is in it too.
	acs.position = Vector3(0, PLATE_THICKNESS + 0.45, 0)
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

# --- Locking ways ---------------------------------------------------------------

const WAY_NAMES := ["left", "front", "right"]
var _gates: Array = []          ## [StaticBody3D] per output

## A red-and-white bar across a way out, its own collider, so a locked way
## also stops a piece shoved toward it.
func _make_gate(i: int, size: Vector3) -> StaticBody3D:
	var d: Vector3 = OUTPUT_DIRS[i]
	var along_x := absf(d.z) > 0.5
	var span := (size.x if along_x else size.z) - 0.2
	var at := Vector3(d.x * (size.x * 0.5 - 0.06), PLATE_THICKNESS + 0.18, d.z * (size.z * 0.5 - 0.06))
	var body := StaticBody3D.new()
	body.name = "Gate_%s" % WAY_NAMES[i]
	body.collision_layer = Layers.MACHINE
	body.collision_mask = Layers.MASK_MACHINE
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(span if along_x else 0.08, 0.36, 0.08 if along_x else span)
	cs.shape = box
	cs.position = at
	body.add_child(cs)
	var g := Greeble.new()
	var stripes := 6
	for k in stripes:
		var f := (float(k) + 0.5) / float(stripes) - 0.5
		var piece := Vector3(span / float(stripes) if along_x else 0.09, 0.12, 0.09 if along_x else span / float(stripes))
		var off := Vector3(f * span, 0, 0) if along_x else Vector3(0, 0, f * span)
		g.block(piece, at + off + Vector3(0, 0.1, 0), Color(0.86, 0.12, 0.10) if k % 2 == 0 else Color(0.95, 0.95, 0.92))
	for side in [-0.5, 0.5]:
		var post := Vector3(side * span, 0, 0) if along_x else Vector3(0, 0, side * span)
		g.block(Vector3(0.08, 0.36, 0.08), at + post, Color(0.25, 0.25, 0.27))
	body.add_child(g.instance("GateMesh", false))
	add_child(body)
	return body

func _show_gates() -> void:
	for i in _gates.size():
		var gate: StaticBody3D = _gates[i]
		var open := i < enabled_outputs.size() and enabled_outputs[i]
		gate.visible = not open
		gate.process_mode = Node.PROCESS_MODE_INHERIT if not open else Node.PROCESS_MODE_DISABLED
		gate.collision_layer = 0 if open else Layers.MACHINE

## Locks the way out nearest `world_point` (where you are aiming on it), or
## opens it again if it is locked. Returns which way, or -1.
func toggle_toward(world_point: Vector3) -> int:
	var local := global_transform.affine_inverse() * world_point
	var flat := Vector3(local.x, 0, local.z)
	if flat.length() < 0.05:
		return -1
	var best := -1
	var best_dot := -INF
	for i in OUTPUT_DIRS.size():
		var d := flat.normalized().dot(OUTPUT_DIRS[i])
		if d > best_dot:
			best_dot = d
			best = i
	# Aiming at the back (the way in) locks nothing.
	if best_dot < 0.3:
		return -1
	set_open(best, not enabled_outputs[best])
	return best

func set_open(i: int, open: bool) -> void:
	if i < 0 or i >= enabled_outputs.size():
		return
	enabled_outputs[i] = open
	# What is on the plate heading for a way just locked picks again.
	for item in _dirs.keys():
		if int(_dirs[item]) == i and not open:
			var again := route_index_for(item)
			if again < 0:
				_dirs.erase(item)
			else:
				_dirs[item] = again
	_show_gates()

func status_line() -> String:
	var ways: Array = []
	for i in OUTPUT_DIRS.size():
		ways.append("%s %s" % [WAY_NAMES[i], "open" if enabled_outputs[i] else "LOCKED"])
	var name := def.display_name if def != null else "Splitter"
	var all_locked := not enabled_outputs.has(true)
	return "%s: %s%s   [R] lock / unlock the way you aim at" % [name, ", ".join(ways),
		"  (all locked: nothing moves)" if all_locked else ""]

func to_dict() -> Dictionary:
	return {"open": enabled_outputs.duplicate()}

func from_dict(d: Dictionary) -> void:
	var open: Array = d.get("open", [])
	for i in mini(open.size(), enabled_outputs.size()):
		enabled_outputs[i] = bool(open[i])
	if is_inside_tree() and not _gates.is_empty():
		_show_gates()

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
