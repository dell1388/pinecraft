class_name Conveyor
extends Node3D

## A conveyor belt, in two flavours, so their cost can be compared directly.
##
## MODE_SURFACE  - a StaticBody3D with constant_linear_velocity. Items ride it
##                 through friction. One line of setup, but items stay fully
##                 simulated and can jam, bounce or fall off.
## MODE_KINEMATIC- an Area3D captures items, freezes them (FREEZE_MODE_KINEMATIC)
##                 and slides them along the belt axis by transform. Zero solver
##                 work, deterministic spacing, no jamming. This is the mode the
##                 automation layer will be built on.

enum Mode { SURFACE, KINEMATIC }

@export var mode: Mode = Mode.KINEMATIC
@export var length: float = 12.0
@export var width: float = 1.4
@export var speed: float = 3.0
@export var min_spacing: float = 1.1     ## KINEMATIC mode: gap between items

## Set by the plot: given a world point, returns the machine/bin/sell zone that
## should receive items leaving this belt, or null. Handing items straight to a
## sink is what keeps belt ends from jamming the way surface belts do.
var sink_finder: Callable = Callable()

const DECK_THICKNESS := 0.16

var _deck: StaticBody3D
var _area: Area3D
var _area_shape: CollisionShape3D
var _captured: Array[LooseItem] = []
var _progress: Dictionary = {}           ## LooseItem -> float (metres along belt)
var _output_point: Node3D
var _poll_counter: int = 0

## Throughput counters, read by the benchmark and later by the automation UI.
var total_captured: int = 0
var total_delivered: int = 0

func _ready() -> void:
	_build()
	set_physics_process(mode == Mode.KINEMATIC)

func _build() -> void:
	_deck = StaticBody3D.new()
	_deck.collision_layer = Layers.MACHINE
	_deck.collision_mask = Layers.MASK_MACHINE
	var deck_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, DECK_THICKNESS, length)
	deck_shape.shape = box
	_deck.add_child(deck_shape)

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.19, 0.22)
	mesh.material_override = mat
	_deck.add_child(mesh)

	# Side rails keep SURFACE-mode items from wandering off the belt.
	for side in [-1.0, 1.0]:
		var rail := CollisionShape3D.new()
		var rb := BoxShape3D.new()
		rb.size = Vector3(0.08, 0.35, length)
		rail.shape = rb
		rail.position = Vector3(side * (width * 0.5 + 0.04), 0.25, 0.0)
		_deck.add_child(rail)

	if mode == Mode.SURFACE:
		var pm := PhysicsMaterial.new()
		pm.friction = 1.0
		pm.rough = true
		_deck.physics_material_override = pm
		# Jolt moves bodies resting on the surface without moving the collider.
		_deck.constant_linear_velocity = -global_transform.basis.z.normalized() * speed
	else:
		_area = Area3D.new()
		_area.collision_layer = Layers.TRIGGER
		_area.collision_mask = Layers.LOOSE
		_area.monitoring = true
		_area.monitorable = false
		var acs := CollisionShape3D.new()
		var ab := BoxShape3D.new()
		ab.size = Vector3(width, 1.2, length)
		acs.shape = ab
		acs.position = Vector3(0, 0.6, 0)
		_area_shape = acs
		_area.add_child(acs)
		_area.body_entered.connect(_on_body_entered)
		add_child(_area)

	add_child(_deck)

	_output_point = Node3D.new()
	_output_point.position = Vector3(0, 0.4, -length * 0.5 - 0.3)
	add_child(_output_point)

func output_transform() -> Transform3D:
	return _output_point.global_transform

func captured_count() -> int:
	return _captured.size()

# --- KINEMATIC mode --------------------------------------------------------

func _on_body_entered(body: Node) -> void:
	if mode != Mode.KINEMATIC:
		return
	var item := body as LooseItem
	if item == null or item.state != LooseItem.State.FREE:
		return
	if not Trigger.contains_point(_area_shape, item.global_position, 0.2):
		return
	var local := global_transform.affine_inverse() * item.global_position
	# Belt runs along -Z; progress 0 is the input end (+Z).
	var progress: float = clampf(length * 0.5 - local.z, 0.0, length)
	if not _has_room(progress):
		return
	item.set_state(LooseItem.State.CAPTURED)
	total_captured += 1
	_captured.append(item)
	_progress[item] = progress

func _has_room(progress: float) -> bool:
	for item in _captured:
		if absf(float(_progress[item]) - progress) < min_spacing:
			return false
	return true

func _physics_process(delta: float) -> void:
	# body_entered fires once; an item rejected for spacing would otherwise never
	# be reconsidered, so the capture zone is re-polled a few times a second.
	_poll_counter += 1
	if _poll_counter >= 6:
		_poll_counter = 0
		for body in Trigger.bodies_inside(_area, _area_shape):
			_on_body_entered(body)
	if _captured.is_empty():
		return
	var step := speed * delta
	for i in range(_captured.size() - 1, -1, -1):
		var item: LooseItem = _captured[i]
		if not is_instance_valid(item) or item.state != LooseItem.State.CAPTURED:
			_release_at(i, false)
			continue
		var p: float = float(_progress[item]) + step
		if p >= length:
			_release_at(i, true)
			continue
		_progress[item] = p
		var half_h: float = item.get_aabb_half_height()
		var local := Vector3(0.0, DECK_THICKNESS * 0.5 + half_h + 0.01, length * 0.5 - p)
		var basis := Basis()  # aligned with the belt: predictable, no tumbling
		item.global_transform = global_transform * Transform3D(basis, local)

func _release_at(index: int, impart_velocity: bool) -> void:
	var item: LooseItem = _captured[index]
	_captured.remove_at(index)
	_progress.erase(item)
	if not is_instance_valid(item):
		return
	if item.state != LooseItem.State.CAPTURED:
		return
	item.set_state(LooseItem.State.FREE)
	if not impart_velocity:
		return
	total_delivered += 1
	# Prefer handing the item directly to whatever is at the end of the belt.
	if sink_finder.is_valid():
		var sink: Object = sink_finder.call(output_transform().origin)
		if sink != null and sink.has_method("can_accept") \
				and sink.can_accept(item.item_id) and sink.accept_item(item):
			return
	item.linear_velocity = -global_transform.basis.z.normalized() * speed
