class_name ChoppableTree
extends StaticBody3D

## A tree built from cylinders: a flared stump, a tapered trunk, angled branches
## and a few canopy cones.
##
## Felling does not turn a tree into tidy logs. The trunk falls as one piece
## with exactly the dimensions it grew to - a 7 m tapered pole - and the branches
## come off as their own pieces. Turning that into something you can carry or
## mill is the player's job: buck it with the axe.

signal felled(tree: ChoppableTree)

@export var max_health: float = 100.0
@export var wood_item: StringName = &"wood_pine"
@export var trunk_height: float = 6.5
@export var trunk_radius: float = 0.34
@export var trunk_taper: float = 0.62      ## top radius as a fraction of the base
@export var branch_count: int = 5
@export var respawn_seconds: float = 35.0

## How fast the trunk swings over once it is cut through, in radians per second
## about the stump.
const FALL_RATE := 0.9

var health: float
var plot_id: int = 0
var manager: LooseItemManager

var _parts: Array[MeshInstance3D] = []
var _shape: CollisionShape3D
var _branches: Array[Dictionary] = []      ## {offset, dir, radius, length}
var _respawn_timer: float = -1.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	health = max_health
	collision_layer = Layers.TREE
	collision_mask = Layers.WORLD
	_rng.seed = hash(name) + int(position.x * 31.0) + int(position.z * 17.0)
	_build()
	set_process(false)

func trunk_dims() -> Dictionary:
	return Solid.cylinder(trunk_radius, trunk_radius * trunk_taper, trunk_height)

## Total wood in the tree: what felling must hand back, to the cubic centimetre.
func wood_volume() -> float:
	var total := Solid.volume(trunk_dims())
	for b in _branches:
		total += Solid.volume(Solid.cylinder(b.radius, b.radius * 0.7, b.length))
	return total

func _build() -> void:
	var wood_def := GameData.item(wood_item)
	var bark: Color = wood_def.color if wood_def != null else Color(0.42, 0.29, 0.17)
	var leaf := Color(0.13, 0.42, 0.18).lerp(Color(0.20, 0.50, 0.22), _rng.randf())

	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(trunk_radius * 2.0, trunk_height, trunk_radius * 2.0)
	_shape.shape = box
	_shape.position = Vector3(0, trunk_height * 0.5, 0)
	add_child(_shape)

	# Root flare, so trunks meet the ground instead of ending at it.
	_add_cylinder(trunk_radius * 1.45, trunk_radius * 1.02, 0.5,
		Transform3D(Basis(), Vector3(0, 0.25, 0)), bark.darkened(0.15))
	# The trunk itself: this is the shape that falls.
	_add_cylinder(trunk_radius, trunk_radius * trunk_taper, trunk_height,
		Transform3D(Basis(), Vector3(0, trunk_height * 0.5, 0)), bark)

	_branches.clear()
	for i in branch_count:
		var t: float = 0.45 + 0.5 * float(i) / maxf(1.0, float(branch_count - 1))
		var height: float = trunk_height * t
		var yaw: float = _rng.randf_range(0.0, TAU)
		var pitch: float = _rng.randf_range(0.5, 0.95)      # up-and-out
		var length: float = trunk_height * _rng.randf_range(0.18, 0.30)
		var radius: float = lerpf(trunk_radius, trunk_radius * trunk_taper, t) * 0.42
		var dir := Vector3(cos(yaw) * sin(pitch), cos(pitch), sin(yaw) * sin(pitch)).normalized()
		var base := Vector3(0, height, 0)
		_branches.append({"offset": base, "dir": dir, "radius": radius, "length": length})

		var basis := _basis_from_up(dir)
		_add_cylinder(radius, radius * 0.7, length,
			Transform3D(basis, base + dir * length * 0.5), bark.lightened(0.05))
		# A clump of foliage on the end of each branch.
		_add_cone(radius * 7.0, length * 1.25,
			Transform3D(Basis(), base + dir * (length + length * 0.35)), leaf)

	_add_cone(trunk_radius * 6.5, trunk_height * 0.45,
		Transform3D(Basis(), Vector3(0, trunk_height * 1.02, 0)), leaf.darkened(0.05))

func _basis_from_up(up: Vector3) -> Basis:
	var axis := Vector3.UP.cross(up)
	if axis.length_squared() < 0.0001:
		return Basis()
	return Basis(axis.normalized(), Vector3.UP.angle_to(up))

func _add_cylinder(r_bottom: float, r_top: float, height: float, xform: Transform3D, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = r_bottom
	cm.top_radius = r_top
	cm.height = height
	cm.radial_segments = 9
	cm.rings = 1
	mi.mesh = cm
	mi.transform = xform
	mi.material_override = _mat(color)
	add_child(mi)
	_parts.append(mi)

func _add_cone(radius: float, height: float, xform: Transform3D, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = 0.0
	cm.height = height
	cm.radial_segments = 9
	cm.rings = 1
	mi.mesh = cm
	mi.transform = xform
	mi.material_override = _mat(color)
	add_child(mi)
	_parts.append(mi)

func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	return m

## Returns true if this hit felled the tree.
func chop(damage: float, from: Vector3) -> bool:
	if health <= 0.0:
		return false
	health -= damage
	if not _parts.is_empty():
		var trunk := _parts[1] if _parts.size() > 1 else _parts[0]
		trunk.scale = Vector3(1.05, 0.99, 1.05)
		create_tween().tween_property(trunk, "scale", Vector3.ONE, 0.12)
	if health > 0.0:
		return false
	_fell(from)
	return true

func _fell(from: Vector3) -> void:
	var dir := global_position - from
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.01 else Vector3.FORWARD

	if manager != null:
		# The trunk falls as one piece, exactly as it grew.
		#
		# It has to pivot about its stump, not spin about its middle: a cylinder
		# given angular velocity about its own centre just drives one edge of
		# its base into the ground and the contact constraint cancels it, which
		# is exactly what a standing 250 kg pole does - nothing. So the trunk is
		# handed a rotation about the base plus the matching centre-of-mass
		# velocity, and a couple of degrees of lean to break the symmetry.
		var axis := Vector3.UP.cross(dir).normalized()
		var lean := Basis(axis, 0.06)
		var centre := global_position + Vector3(0, trunk_height * 0.5, 0)
		var trunk := manager.spawn(wood_item, Transform3D(lean, centre), plot_id,
			Vector3.ZERO, trunk_dims())
		if trunk != null:
			var spin := axis * FALL_RATE
			trunk.angular_velocity = spin
			trunk.linear_velocity = spin.cross(Vector3(0, trunk_height * 0.5, 0))
		for b in _branches:
			var branch_dims := Solid.cylinder(b.radius, b.radius * 0.7, b.length)
			var basis := _basis_from_up(b.dir)
			var pos: Vector3 = global_position + b.offset + b.dir * float(b.length) * 0.5
			var piece := manager.spawn(wood_item, Transform3D(basis, pos), plot_id,
				b.dir * 1.5, branch_dims)
			if piece == null:
				break

	_set_standing(false)
	felled.emit(self)
	if respawn_seconds > 0.0:
		_respawn_timer = respawn_seconds
		set_process(true)

func _set_standing(standing: bool) -> void:
	for p in _parts:
		p.visible = standing
	_shape.disabled = not standing
	collision_layer = Layers.TREE if standing else 0

func _process(delta: float) -> void:
	if _respawn_timer < 0.0:
		return
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_timer = -1.0
		health = max_health
		_set_standing(true)
		set_process(false)
