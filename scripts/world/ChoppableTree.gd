class_name ChoppableTree
extends StaticBody3D

## A tree built from cylinders, each of which can be cut on its own.
##
## There is no single "tree health": the trunk and every branch is a limb with
## its own collider and its own accumulated axe work, and a cut goes through
## whichever limb the player is actually aiming at. Work needed scales with the
## area of the cut face, so a branch is a swing or two and a trunk is real
## labour, and a sharper axe removes more area per swing.
##
## Cutting the trunk severs it at the height of the cut. Everything above that
## line leaves as one falling piece with exactly the shape it grew to, the
## branches above it come away as their own pieces, and what is left standing
## is a shorter tree that can be cut again. Leaves are decoration: they carry no
## collider and go when the wood they hang on goes.

signal felled(tree: ChoppableTree)
signal limb_cut(tree: ChoppableTree, wood_volume: float)

@export var wood_item: StringName = &"wood_pine"
@export var trunk_height: float = 6.5
@export var trunk_radius: float = 0.34
@export var trunk_taper: float = 0.62      ## top radius as a fraction of the base
@export var branch_count: int = 5
## Axe work per square metre of cut face. A fat trunk is many swings.
@export var work_per_m2: float = 900.0

## What kind of tree this is. Wood is a separate thing: a swamp willow and a
## woodland oak are different trees that both cut into oak.
@export var species: String = "Tree"
@export var leaf_color: Color = Color(0.16, 0.44, 0.20)
## Where up the trunk the lowest branch sits, as a fraction of its height. Low
## for a conifer, high for a broadleaf carrying its crown above open trunk.
@export var branch_start: float = 0.45
## How far branches are swept up or out, in radians from vertical. A small
## range is a spire; a wide one is a spreading canopy.
@export var branch_pitch: Vector2 = Vector2(0.5, 0.95)
## Branch length as a fraction of trunk height.
@export var branch_length: Vector2 = Vector2(0.18, 0.30)
## Foliage clump radius, as a multiple of the branch it hangs on.
@export var foliage_spread: float = 7.0
## The crown on top: radius as a multiple of trunk radius, and height as a
## fraction of trunk height. A zero radius leaves the tree bare-topped.
@export var crown_spread: float = 6.5
@export var crown_height: float = 0.45
## How the leaves are drawn: cone (a conifer's tiers), ball (a round
## broadleaf), puff (a cloud of blossom), palm (fronds from the top only) or
## bare (a dead snag, or something stranger).
@export var foliage_style: StringName = &"cone"
## Bark colour when it is not the wood's own (a birch is white outside).
@export var bark_color: Color = Color(0, 0, 0, 0)
## Leaves (or cracks) that give off light, for the stranger trees.
@export var leaf_glow: float = 0.0
## A second leaf colour mixed through the canopy (blossom, autumn).
@export var leaf_accent: Color = Color(0, 0, 0, 0)

## Past this a tree is not drawn at all; the fog has it by then.
const VIEW_RANGE := 300.0
## How fast a severed trunk swings over, in radians per second about the cut.
const FALL_RATE := 0.9
## A trunk shorter than this is a stump: nothing left worth cutting.
const MIN_TRUNK := 0.6

var plot_id: int = 0
var manager: LooseItemManager

## Every branch still attached: {height, dir, radius, length, cut, mesh, leaf, shape}
var branches: Array[Dictionary] = []
## Work done on the trunk so far, and the height the current cut is being made.
var trunk_cut: float = 0.0
var trunk_cut_height: float = 0.0

var _trunk_mesh: MeshInstance3D
var _flare_mesh: MeshInstance3D
var _crown: MeshInstance3D
var _trunk_shape: CollisionShape3D
var _standing: bool = true
var _rng := RandomNumberGenerator.new()
## Set by the first blow. A field only ever retires trees nobody has started on.
var touched: bool = false

func _ready() -> void:
	collision_layer = Layers.TREE
	collision_mask = Layers.WORLD
	if _rng.seed == 0:
		_rng.seed = hash(name) + int(position.x * 31.0) + int(position.z * 17.0)
	_build()

## Lets the spawner decide the tree's form deterministically.
func seed_form(value: int) -> void:
	_rng.seed = value

## Standing and never cut: safe for a field to take away and grow elsewhere.
func untouched() -> bool:
	return _standing and not touched

func standing() -> bool:
	return _standing

func trunk_dims() -> Dictionary:
	return Solid.cylinder(trunk_radius, trunk_radius * trunk_taper, trunk_height)

## Radius of the trunk at a given height above the ground.
func radius_at(height: float) -> float:
	var t := clampf(height / maxf(0.01, trunk_height), 0.0, 1.0)
	return lerpf(trunk_radius, trunk_radius * trunk_taper, t)

## Total wood still standing: what is left to be cut out of this tree.
func wood_volume() -> float:
	if not _standing:
		return 0.0
	var total := Solid.volume(trunk_dims())
	for b in branches:
		total += Solid.volume(_branch_dims(b))
	return total

func _branch_dims(b: Dictionary) -> Dictionary:
	return Solid.cylinder(float(b.radius), float(b.radius) * 0.7, float(b.length))

# --- Construction ----------------------------------------------------------

func _build() -> void:
	var wood_def := GameData.item(wood_item)
	var bark: Color = wood_def.color if wood_def != null else Color(0.42, 0.29, 0.17)
	if bark_color.a > 0.0:
		bark = bark_color
	# A little variation per tree, so a stand is not one colour repeated.
	var leaf := leaf_color.lightened(_rng.randf_range(0.0, 0.10)) \
		if _rng.randf() > 0.5 else leaf_color.darkened(_rng.randf_range(0.0, 0.10))

	_trunk_shape = CollisionShape3D.new()
	_trunk_shape.shape = CylinderShape3D.new()
	add_child(_trunk_shape)

	_flare_mesh = _add_cylinder(trunk_radius * 1.45, trunk_radius * 1.02, 0.5,
		Transform3D(Basis(), Vector3(0, 0.25, 0)), bark.darkened(0.15))
	_trunk_mesh = _add_cylinder(trunk_radius, trunk_radius * trunk_taper, trunk_height,
		Transform3D(Basis(), Vector3(0, trunk_height * 0.5, 0)), bark)
	if crown_spread > 0.01 and foliage_style != &"bare":
		_crown = _add_foliage(trunk_radius * crown_spread, trunk_height * crown_height,
			Transform3D(Basis(), Vector3(0, trunk_height * 1.02, 0)), leaf.darkened(0.05), true)

	for i in branch_count:
		var span: float = maxf(0.05, 0.98 - branch_start)
		var t: float = branch_start + span * float(i) / maxf(1.0, float(branch_count - 1))
		var height: float = trunk_height * t
		var yaw: float = _rng.randf_range(0.0, TAU)
		var pitch: float = _rng.randf_range(branch_pitch.x, branch_pitch.y)
		var length: float = trunk_height * _rng.randf_range(branch_length.x, branch_length.y)
		var radius: float = radius_at(height) * 0.42
		var dir := Vector3(cos(yaw) * sin(pitch), cos(pitch), sin(yaw) * sin(pitch)).normalized()
		var base := Vector3(0, height, 0)
		var basis := _basis_from_up(dir)
		var mesh := _add_cylinder(radius, radius * 0.7, length,
			Transform3D(basis, base + dir * length * 0.5), bark.lightened(0.05))
		var tint := leaf
		if leaf_accent.a > 0.0 and _rng.randf() < 0.45:
			tint = leaf_accent
		var foliage: MeshInstance3D = null
		if foliage_style != &"bare" and foliage_style != &"palm":
			foliage = _add_foliage(radius * foliage_spread, length * 1.25,
				Transform3D(Basis(), base + dir * (length + length * 0.35)), tint, false)
		# Each branch gets its own collider, so the aim ray can say which one
		# the player is standing under.
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = radius
		cyl.height = length
		shape.shape = cyl
		shape.transform = Transform3D(basis, base + dir * length * 0.5)
		add_child(shape)
		branches.append({"height": height, "dir": dir, "radius": radius, "length": length,
			"cut": 0.0, "mesh": mesh, "leaf": foliage, "shape": shape})

	_refresh_trunk()

## Rebuilds the trunk mesh and collider from the current height, after a cut has
## shortened the tree.
func _refresh_trunk() -> void:
	var cm := _trunk_mesh.mesh as CylinderMesh
	cm.bottom_radius = trunk_radius
	cm.top_radius = trunk_radius * trunk_taper
	cm.height = trunk_height
	_trunk_mesh.position = Vector3(0, trunk_height * 0.5, 0)
	var cyl := _trunk_shape.shape as CylinderShape3D
	cyl.radius = trunk_radius
	cyl.height = trunk_height
	_trunk_shape.position = Vector3(0, trunk_height * 0.5, 0)
	if _crown != null and is_instance_valid(_crown):
		_crown.visible = _standing and (not branches.is_empty() or foliage_style == &"palm" \
			or foliage_style == &"cap")
		_crown.position = Vector3(0, trunk_height * 1.02, 0)

func _basis_from_up(up: Vector3) -> Basis:
	var axis := Vector3.UP.cross(up)
	if axis.length_squared() < 0.0001:
		return Basis()
	return Basis(axis.normalized(), Vector3.UP.angle_to(up))

func _add_cylinder(r_bottom: float, r_top: float, height: float, xform: Transform3D,
		color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = r_bottom
	cm.top_radius = r_top
	cm.height = height
	cm.radial_segments = Tuning.ROUND_SIDES
	cm.rings = 1
	mi.mesh = cm
	mi.transform = xform
	mi.material_override = _mat(color)
	mi.visibility_range_end = VIEW_RANGE
	add_child(mi)
	return mi

func _add_cone(radius: float, height: float, xform: Transform3D, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = 0.0
	cm.height = height
	cm.radial_segments = Tuning.ROUND_SIDES
	cm.rings = 1
	mi.mesh = cm
	mi.transform = xform
	mi.material_override = _mat(color)
	mi.visibility_range_end = VIEW_RANGE
	add_child(mi)
	return mi

## Trees share materials by colour, so a forest of a few species is a few
## materials rather than one per branch.
static var _materials: Dictionary = {}

func _mat(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f" % [color.to_html(), glow]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	_materials[key] = m
	return m

## One clump of leaves in the tree's style. `crown` is the top of the tree.
func _add_foliage(radius: float, height: float, xform: Transform3D, color: Color,
		crown: bool) -> MeshInstance3D:
	var mi: MeshInstance3D
	match foliage_style:
		&"ball":
			mi = _add_ball(radius * 0.85, height * 0.85, xform.translated(Vector3(0, height * 0.2, 0)), color)
		&"puff":
			# A few overlapping balls: blossom or a cloud of small leaves.
			mi = _add_ball(radius * 0.7, height * 0.7, xform.translated(Vector3(0, height * 0.2, 0)), color)
			for k in 3:
				var a := TAU * float(k) / 3.0 + _rng.randf()
				var puff := _add_ball(radius * 0.5, height * 0.5,
					Transform3D(Basis(), Vector3(cos(a) * radius * 0.55, height * 0.1, sin(a) * radius * 0.55)),
					color.lightened(_rng.randf_range(0.0, 0.12)))
				remove_child(puff)
				mi.add_child(puff)
		&"palm":
			mi = _add_fronds(radius, xform, color)
		&"cap":
			# A giant mushroom's cap: a broad, flattened dome with a pale
			# rim of gills under it.
			mi = _add_ball(radius, height * 0.5, xform.translated(Vector3(0, height * 0.05, 0)), color)
			var gills := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = radius * 0.92
			cyl.bottom_radius = trunk_radius * 1.3
			cyl.height = height * 0.14
			cyl.radial_segments = 10
			gills.mesh = cyl
			gills.position = Vector3(0, -height * 0.02, 0)
			gills.material_override = _mat(leaf_accent if leaf_accent.a > 0.0 else color.lightened(0.4), leaf_glow * 0.6)
			mi.add_child(gills)
		_:
			mi = _add_cone(radius, height, xform, color)
	if leaf_glow > 0.0:
		mi.material_override = _mat(color, leaf_glow)
	return mi

func _add_ball(radius: float, height: float, xform: Transform3D, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = maxf(height, radius * 1.2)
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	mi.transform = xform
	mi.material_override = _mat(color)
	mi.visibility_range_end = VIEW_RANGE
	add_child(mi)
	return mi

## Palm fronds: long flat blades drooping out from the top of the trunk.
func _add_fronds(radius: float, xform: Transform3D, color: Color) -> MeshInstance3D:
	var root := MeshInstance3D.new()
	var hub := SphereMesh.new()
	hub.radius = trunk_radius * 1.4
	hub.height = trunk_radius * 2.0
	hub.radial_segments = 6
	hub.rings = 3
	root.mesh = hub
	root.transform = xform
	root.material_override = _mat(color.darkened(0.2))
	add_child(root)
	var count := 8
	var reach := maxf(radius, 2.2)
	for k in count:
		var a := TAU * float(k) / float(count) + _rng.randf_range(-0.2, 0.2)
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.1, 0.06, reach)
		blade.mesh = bm
		var dir := Vector3(cos(a), 0, sin(a))
		var droop := _rng.randf_range(0.25, 0.55)
		blade.transform = Transform3D(Basis(Vector3.UP, -a + PI * 0.5) * Basis(Vector3.RIGHT, droop),
			dir * reach * 0.45 + Vector3(0, -reach * 0.18, 0))
		blade.material_override = _mat(color if k % 2 == 0 else color.lightened(0.08))
		root.add_child(blade)
	return root

# --- Cutting ---------------------------------------------------------------

## Which limb a world point belongs to: -1 for the trunk, otherwise an index
## into `branches`. Points are matched to the nearest branch axis, so aiming at
## a branch cuts that branch and aiming past it cuts the trunk.
func limb_at(world_point: Vector3) -> int:
	var local := to_local(world_point)
	var best := -1
	var best_d := INF
	for i in branches.size():
		var b: Dictionary = branches[i]
		var base := Vector3(0, float(b.height), 0)
		var dir: Vector3 = b.dir
		var along: float = clampf((local - base).dot(dir), 0.0, float(b.length))
		var d: float = local.distance_to(base + dir * along)
		if d < best_d and d < float(b.radius) * 2.2:
			best_d = d
			best = i
	# The trunk wins when the point is inside it, whatever branch is nearby.
	var height := clampf(local.y, 0.0, trunk_height)
	var trunk_d := Vector2(local.x, local.z).length()
	if trunk_d <= radius_at(height) * 1.25:
		return -1
	return best

## Work one swing of the axe into the limb under `world_point`. Returns a short
## line describing what happened.
func cut(damage: float, world_point: Vector3, from: Vector3) -> String:
	if not _standing:
		return ""
	touched = true
	var index := limb_at(world_point)
	if index >= 0:
		return _cut_branch(index, damage)
	return _cut_trunk(damage, to_local(world_point).y, from)

func _cut_branch(index: int, damage: float) -> String:
	var b: Dictionary = branches[index]
	var area: float = PI * float(b.radius) * float(b.radius)
	var needed: float = area * work_per_m2
	b.cut = float(b.cut) + damage
	if float(b.cut) < needed:
		_nudge(b.mesh)
		return "cutting branch: %d%%" % int(float(b.cut) / needed * 100.0)
	_drop_branch(index, Vector3.ZERO)
	return "branch off"

## Severs the trunk at `height`. Everything above leaves; what is below stays
## standing and can be cut again.
func _cut_trunk(damage: float, height: float, from: Vector3) -> String:
	height = clampf(height, 0.0, trunk_height)
	# Moving the cut to a different height starts a new cut.
	if absf(height - trunk_cut_height) > 0.45:
		trunk_cut_height = height
		trunk_cut = 0.0
	var radius := radius_at(trunk_cut_height)
	var needed: float = PI * radius * radius * work_per_m2
	trunk_cut += damage
	if trunk_cut < needed:
		_nudge(_trunk_mesh)
		return "cutting trunk: %d%%" % int(trunk_cut / needed * 100.0)
	return _sever(trunk_cut_height, from)

## Drops everything above `height` as loose wood and leaves the rest standing.
func _sever(height: float, from: Vector3) -> String:
	var dir := global_position - from
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.01 else Vector3.FORWARD

	var cut_radius := radius_at(height)
	var top_radius := trunk_radius * trunk_taper
	var upper := Solid.cylinder(cut_radius, top_radius, maxf(0.05, trunk_height - height))
	var dropped := Solid.volume(upper)

	if manager != null and trunk_height - height > 0.05:
		# The severed length has to pivot about the cut, not spin about its own
		# middle: a cylinder given angular velocity about its centre drives one
		# edge of its base into whatever it is standing on and the contact
		# cancels it, which is what a standing quarter-tonne pole does - nothing.
		# So it gets a rotation about the cut plus the matching centre-of-mass
		# velocity, and a couple of degrees of lean to break the symmetry.
		var axis := Vector3.UP.cross(dir).normalized()
		var lean := Basis(axis, 0.06)
		var centre := global_position + Vector3(0, height + (trunk_height - height) * 0.5, 0)
		var piece := manager.spawn(wood_item, Transform3D(lean, centre), plot_id,
			Vector3.ZERO, upper)
		if piece != null:
			var spin := axis * FALL_RATE
			piece.angular_velocity = spin
			piece.linear_velocity = spin.cross(Vector3(0, (trunk_height - height) * 0.5, 0))

	# Branches above the cut go with it.
	for i in range(branches.size() - 1, -1, -1):
		if float(branches[i].height) >= height:
			dropped += _drop_branch(i, dir * 1.5)

	# The stump keeps the taper it actually grew: it runs from its base radius
	# to the radius at the cut, not to the radius the whole tree ended at. Get
	# this wrong and the two halves of a cut no longer add up to the tree.
	trunk_taper = cut_radius / maxf(0.001, trunk_radius)
	trunk_height = height
	trunk_cut = 0.0
	trunk_cut_height = 0.0
	_refresh_trunk()
	limb_cut.emit(self, dropped)
	if trunk_height <= MIN_TRUNK:
		_standing = false
		_trunk_shape.disabled = true
		_trunk_mesh.visible = false
		_flare_mesh.visible = false
		if _crown != null:
			_crown.visible = false
		collision_layer = 0
		felled.emit(self)
		return "tree down"
	return "trunk severed at %.1f m" % height

## Takes one branch off the tree and turns it into loose wood. Returns its volume.
## Cuts the tree right through at the base, dropping the whole thing. What a
## perfect swing with an oversized axe would do, and how tests and the smoke
## run take a tree down in one call.
func fell(from: Vector3 = Vector3.ZERO) -> String:
	if not _standing:
		return ""
	var origin := from if from != Vector3.ZERO else global_position + Vector3(0, 0, 3)
	return _sever(0.0, origin)

func _drop_branch(index: int, impulse: Vector3) -> float:
	var b: Dictionary = branches[index]
	var dims := _branch_dims(b)
	if manager != null:
		var basis := _basis_from_up(b.dir)
		var pos: Vector3 = global_position + Vector3(0, float(b.height), 0) \
			+ (b.dir as Vector3) * float(b.length) * 0.5
		manager.spawn(wood_item, Transform3D(basis, pos), plot_id,
			impulse + (b.dir as Vector3) * 0.8, dims)
	(b.mesh as MeshInstance3D).queue_free()
	if b.leaf != null and is_instance_valid(b.leaf):
		(b.leaf as MeshInstance3D).queue_free()
	(b.shape as CollisionShape3D).queue_free()
	branches.remove_at(index)
	if branches.is_empty() and _crown != null and foliage_style != &"palm" and foliage_style != &"cap":
		_crown.visible = false
	return Solid.volume(dims)

func _nudge(mesh: MeshInstance3D) -> void:
	if not is_instance_valid(mesh):
		return
	mesh.scale = Vector3(1.05, 0.99, 1.05)
	create_tween().tween_property(mesh, "scale", Vector3.ONE, 0.12)

## How far through the limb under this point the current cut is, 0..1. Drives
## the aim prompt.
func cut_progress_at(world_point: Vector3) -> float:
	var index := limb_at(world_point)
	if index >= 0:
		var b: Dictionary = branches[index]
		var needed: float = PI * float(b.radius) * float(b.radius) * work_per_m2
		return clampf(float(b.cut) / maxf(0.001, needed), 0.0, 1.0)
	var height := clampf(to_local(world_point).y, 0.0, trunk_height)
	if absf(height - trunk_cut_height) > 0.45:
		return 0.0
	var radius := radius_at(trunk_cut_height)
	return clampf(trunk_cut / maxf(0.001, PI * radius * radius * work_per_m2), 0.0, 1.0)
