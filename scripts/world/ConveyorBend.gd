class_name ConveyorBend
extends Conveyor

## A quarter-turn belt: in along -Z at the back edge, out the left or right
## side, turned 90 degrees. The deck is a curve of short segments, each a
## rubber deck of its own dragging what is on it along the curve there - so a
## piece is carried round by friction the whole way, a long log swings its
## tail out, and one too long for the curve jams against the rail.

## -1 turns left, +1 turns right.
@export var turn: float = -1.0

## Radius of the belt's centre line, and how many segments make the curve.
var radius: float = 1.0
const SEGMENTS := 8

var _segments: Array[StaticBody3D] = []
var _tangents: Array[Vector3] = []

## The centre of the curve, in the belt's own frame: level with the back edge,
## out to the side it turns toward.
func _centre() -> Vector3:
	return Vector3(turn * radius, 0.0, length * 0.5)

func _build() -> void:
	radius = length * 0.5
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	pm.rough = true
	var g := Greeble.new()
	var steel := Color(0.40, 0.42, 0.46)
	var rubber := Color(0.14, 0.14, 0.16)
	var paint := Color(0.96, 0.76, 0.20)
	var c := _centre()
	var step := (PI * 0.5) / float(SEGMENTS)
	var outer := radius + width * 0.5
	for i in SEGMENTS:
		# The angle is measured from the entry: 0 at the back edge, PI/2 at
		# the side it leaves by.
		var a := step * (float(i) + 0.5)
		var from_c := Vector3(-turn * cos(a), 0.0, -sin(a))
		var mid := c + from_c * radius
		# Travel direction: along the curve, away from the entry.
		var along := Vector3(-turn * -sin(a), 0.0, -cos(a)).normalized()
		var basis := Basis.looking_at(along, Vector3.UP)
		var seg_len := outer * step * 1.08
		var pose := Transform3D(basis, mid + Vector3(0, DECK_THICKNESS * 0.5, 0))
		var body := StaticBody3D.new()
		body.collision_layer = Layers.MACHINE
		body.collision_mask = Layers.MASK_MACHINE
		body.physics_material_override = pm
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(width, DECK_THICKNESS, seg_len)
		cs.shape = box
		cs.transform = pose
		body.add_child(cs)
		if railed:
			for side in [-1.0, 1.0]:
				var rail := CollisionShape3D.new()
				var rb := BoxShape3D.new()
				rb.size = Vector3(0.08, 0.35, seg_len)
				rail.shape = rb
				rail.transform = pose.translated_local(Vector3(side * (width * 0.5 + 0.04), 0.25, 0))
				body.add_child(rail)
				g.box(Vector3(0.08, 0.3, seg_len), pose.translated_local(Vector3(side * (width * 0.5 + 0.04), 0.25, 0)), steel.lightened(0.1))
		add_child(body)
		_segments.append(body)
		_tangents.append(along)
		g.box(Vector3(width - 0.2, DECK_THICKNESS, seg_len), pose, rubber)
		for side in [-1.0, 1.0]:
			g.box(Vector3(0.1, DECK_THICKNESS + 0.1, seg_len), pose.translated_local(Vector3(side * (width * 0.5 - 0.05), 0.02, 0)), steel)
		# A chevron on every other segment, pointing the way it goes.
		if i % 2 == 0:
			for side in [-1.0, 1.0]:
				g.box(Vector3(0.09, 0.012, 0.36), pose * Transform3D(Basis(Vector3.UP, side * 0.7),
					Vector3(side * 0.12, DECK_THICKNESS * 0.5 + 0.005, 0.08)), paint)
	var dress := g.instance("Bend", false)
	add_child(dress)
	_deck = _segments[0]

	_area = Area3D.new()
	_area.collision_layer = Layers.TRIGGER
	_area.collision_mask = Layers.LOOSE
	_area.monitorable = false
	var acs := CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = Vector3(length + 0.2, 1.2, length + 0.2)
	acs.shape = ab
	acs.position = Vector3(0, DECK_THICKNESS + 0.6, 0)
	_area_shape = acs
	_area.add_child(acs)
	add_child(_area)

	_output_point = Node3D.new()
	# Just past the side it leaves by.
	_output_point.position = Vector3(turn * (radius + 0.3), DECK_THICKNESS + 0.4, 0.0)
	add_child(_output_point)

func _drive() -> void:
	var b := global_transform.basis
	for i in _segments.size():
		_segments[i].constant_linear_velocity = (b * _tangents[i]).normalized() * speed if running else Vector3.ZERO

## Leaving: out of the side it turns toward, the way it was going.
func belt_velocity() -> Vector3:
	if not running:
		return Vector3.ZERO
	return (global_transform.basis * Vector3(turn, 0, 0)).normalized() * speed

func _off_far_end(item: LooseItem) -> bool:
	return _local(item).x * turn > length * 0.5 - LIP

func status_line() -> String:
	return "%s bend: %s, %d aboard  [E] %s" % ["left" if turn < 0.0 else "right",
		"running" if running else "stopped", _riding.size(), "stop" if running else "start"]
