class_name LooseItem
extends RigidBody3D

## A single loose physical piece: a log, a length of lumber, a billet, a crate.
##
## Its shape is data, not a model file: a box or a tapered cylinder whose long
## axis is local +Y. Mass comes from the item's density times its real volume,
## so a 4 m trunk weighs what a 4 m trunk should and the sawmill that conserves
## volume also conserves mass and price.
##
## Kept deliberately dumb: no _physics_process, no _integrate_forces. Velocity
## clamping, CCD toggling and kill-plane rescue are driven by LooseItemManager
## so that 500 of these cost one loop instead of 500 script callbacks per step.

enum State { FREE, CARRIED, HELD, CAPTURED, POOLED }

signal state_changed(item: LooseItem, from: State, to: State)

var item_id: StringName = &"wood_pine"
var category: StringName = &"wood"
var dims: Dictionary = {}
var plot_id: int = 0
var state: State = State.FREE
var spawn_index: int = 0
## Whether this piece belongs to the player: picked up, bought, or made by a
## machine on their plot. Owned pieces are what the yard buys and what a save
## remembers; a trunk lying in the forest is neither.
var owned: bool = false
var ccd_active: bool = false
var quiet_time: float = 0.0
var cut_progress: float = 0.0     ## axe work done on this piece since the last cut
var cut_at: float = 0.0           ## where along the piece that cut is (local Y)
## The shortest stub or end a cut can leave.
const MIN_STUB := 0.15
## The vehicle whose bed this piece is lying in, if any. The piece is still a
## free body; this is only so the truck can count its load and save it.
var carrier: Node3D = null

## Branches still on a felled trunk, each with its own collider and weight:
## {origin, dir (both in this piece's frame), radius, length, cut, shape, nodes}.
var limbs: Array[Dictionary] = []

var _shape: CollisionShape3D
var _mesh: MeshInstance3D
var _extras: Array[Node3D] = []

func _init() -> void:
	collision_layer = Layers.LOOSE
	collision_mask = Layers.MASK_LOOSE
	can_sleep = true
	continuous_cd = false
	max_contacts_reported = 0
	contact_monitor = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.1
	angular_damp = 0.4

func configure(def: ItemDef, p_dims: Dictionary = {}) -> void:
	item_id = def.id
	category = def.category
	dims = p_dims if not p_dims.is_empty() else def.default_dims()
	mass = def.mass_of(dims)
	cut_progress = 0.0
	owned = false
	clear_extras()
	clear_limbs()
	# Round stock rolls; a little extra spin damping stops a felled trunk
	# rolling across the plot forever without making it feel glued down.
	angular_damp = 0.9 if dims.get("shape", Solid.BOX) == Solid.CYLINDER else 0.4
	_build_shape()
	_build_mesh(def.color)

func _build_shape() -> void:
	if _shape == null:
		_shape = CollisionShape3D.new()
		add_child(_shape)
	if dims.get("shape", Solid.BOX) == Solid.CYLINDER:
		# Collision is the same eight-sided prism the log is drawn as, taper
		# and all. Jolt lets a true cylinder lying on its side sink a hand's
		# width into anything that moves - a truck bed, a belt - so round
		# stock is flat-sided in the physics as well as to look at.
		var hull := _shape.shape as ConvexPolygonShape3D
		if hull == null:
			hull = ConvexPolygonShape3D.new()
			_shape.shape = hull
		hull.points = prism_points(float(dims.r0), float(dims.r1), float(dims.length))
	else:
		var box := _shape.shape as BoxShape3D
		if box == null:
			box = BoxShape3D.new()
			_shape.shape = box
		box.size = dims.size

func _build_mesh(color: Color) -> void:
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		add_child(_mesh)
	if _is_rough_stone():
		_build_rock_mesh(color)
		return
	if dims.get("shape", Solid.BOX) == Solid.CYLINDER:
		var cm := _mesh.mesh as CylinderMesh
		if cm == null:
			cm = CylinderMesh.new()
			cm.radial_segments = Tuning.ROUND_SIDES
			cm.rings = 1
			_mesh.mesh = cm
		cm.bottom_radius = float(dims.r0)
		cm.top_radius = float(dims.r1)
		cm.height = float(dims.length)
	else:
		var bm := _mesh.mesh as BoxMesh
		if bm == null:
			bm = BoxMesh.new()
			_mesh.mesh = bm
		bm.size = dims.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	# What a piece has been through shows: sanded wood is pale and smooth,
	# refined metal is bright and polished.
	if Solid.has_finish(dims, &"sanded"):
		mat.albedo_color = color.lerp(Color(0.93, 0.82, 0.62), 0.45)
		mat.roughness = 0.55
	if Solid.has_finish(dims, &"refined"):
		mat.albedo_color = color.lightened(0.25)
		mat.metallic = 0.85
		mat.roughness = 0.22
	# Polished stone is glossy; a cut jewel glitters.
	if Solid.has_finish(dims, &"polished"):
		mat.albedo_color = color.lightened(0.12)
		mat.roughness = 0.12
		mat.metallic = 0.2
	if category == &"jewel":
		mat.roughness = 0.05
		mat.metallic = 0.35
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.35
	elif category == &"gem":
		mat.roughness = minf(mat.roughness, 0.5)
	_mesh.material_override = mat

## Ore, and gems not yet polished, as they come out of the ground: rock, not
## a block of colour.
func _is_rough_stone() -> bool:
	if dims.get("shape", Solid.BOX) != Solid.BOX:
		return false
	if category == &"ore":
		return true
	return category == &"gem" and not Solid.has_finish(dims, &"polished")

## A lump of the ore's host rock - the same stone its chunk sat in - with small
## flecks and crystals of the ore itself set into its faces, glinting for the
## ores that do. The collider stays the plain box.
func _build_rock_mesh(color: Color) -> void:
	var size: Vector3 = dims.size
	var stone: Color = OreRock.HOST_STONE.get(item_id, Color(0.47, 0.45, 0.42))
	var glint := OreRock.GLOWING_ORES.has(item_id) or category == &"gem"
	var form := RandomNumberGenerator.new()
	form.seed = hash([item_id, size.snapped(Vector3.ONE * 0.001)])
	var g := Greeble.new()
	g.box(size, Transform3D(), stone)
	# A couple of knobbly shoulders so it does not read as a brick.
	for i in 3:
		var s := size * form.randf_range(0.4, 0.6)
		var at := Vector3(form.randf_range(-0.4, 0.4) * size.x, form.randf_range(-0.3, 0.45) * size.y,
			form.randf_range(-0.4, 0.4) * size.z)
		g.box(s, Transform3D(Basis(Vector3.UP, form.randf() * PI), at), stone.lightened(form.randf_range(0.02, 0.1)))
	# Flecks of ore on the faces: more on a bigger lump, never many.
	var smallest := minf(size.x, minf(size.y, size.z))
	var area := 2.0 * (size.x * size.y + size.y * size.z + size.x * size.z)
	var flecks := clampi(int(area / maxf(smallest * smallest, 0.0001) * 1.5), 8, 22)
	for i in flecks:
		var axis := form.randi() % 3
		var side := -1.0 if form.randf() < 0.5 else 1.0
		var normal := Vector3.ZERO
		normal[axis] = side
		var at := Vector3(form.randf_range(-0.4, 0.4) * size.x, form.randf_range(-0.4, 0.4) * size.y,
			form.randf_range(-0.4, 0.4) * size.z)
		at[axis] = side * size[axis] * 0.5
		var f := smallest * form.randf_range(0.1, 0.2)
		var fleck := Vector3(f, f, f)
		fleck[axis] = f * 0.5
		g.box(fleck, Transform3D(Basis(Vector3.UP, form.randf() * PI) if axis == 1 else Basis(), at),
			color.lightened(form.randf_range(0.0, 0.15)), glint and form.randf() < 0.5)
	_mesh.mesh = g.commit()
	_mesh.material_override = null

## The corners of an eight-sided log, matching CylinderMesh's own vertices:
## `r0` at the bottom (-Y), `r1` at the top.
static func prism_points(r0: float, r1: float, length: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var sides := Tuning.ROUND_SIDES
	for i in sides:
		var a := TAU * float(i) / float(sides)
		var d := Vector3(sin(a), 0.0, cos(a))
		out.append(d * r0 + Vector3(0, -length * 0.5, 0))
		out.append(d * r1 + Vector3(0, length * 0.5, 0))
	return out

## Decorative meshes carried by this piece (cut branch stubs on a felled trunk).
## Visual only: the collider stays one primitive.
func add_extra_mesh(mesh: Mesh, xform: Transform3D, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xform
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mi.material_override = mat
	add_child(mi)
	_extras.append(mi)

## Any other decoration to carry (a box's printed art and label).
func add_extra_node(node: Node3D) -> void:
	add_child(node)
	_extras.append(node)

# --- Limbs -------------------------------------------------------------------

## Puts a branch on this piece: solid, weighed with it, carried with it. The
## `visuals` (the branch's own model, its foliage) are reparented to ride
## along; with none, a plain one is made.
func add_limb(origin: Vector3, dir: Vector3, radius: float, length: float, visuals: Array = [],
		bark: Color = Color(0.42, 0.3, 0.2), tip: float = -1.0) -> void:
	dir = dir.normalized()
	if tip <= 0.0:
		tip = radius * 0.7
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = maxf(0.03, radius)
	cyl.height = maxf(0.1, length)
	cs.shape = cyl
	cs.transform = Transform3D(_up_basis(dir), origin + dir * length * 0.5)
	add_child(cs)
	var nodes: Array = []
	for v in visuals:
		var n := v as Node3D
		if n == null or not is_instance_valid(n):
			continue
		n.reparent(self, true)
		nodes.append(n)
	if nodes.is_empty():
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.bottom_radius = radius
		cm.top_radius = tip
		cm.height = length
		cm.radial_segments = 6
		mi.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = bark
		mat.roughness = 0.9
		mi.material_override = mat
		mi.transform = cs.transform
		add_child(mi)
		nodes.append(mi)
	mass += Solid.volume(Solid.cylinder(radius, tip, length)) * _density()
	limbs.append({"origin": origin, "dir": dir, "radius": radius, "tip": tip, "length": length, "cut": 0.0,
		"cut_at": -1.0, "shape": cs, "nodes": nodes, "bark": bark})

func _density() -> float:
	var def: ItemDef = GameData.item(item_id)
	var v := Solid.volume(dims)
	return def.mass_of(dims) / v if def != null and v > 0.0 else 600.0

static func _up_basis(up: Vector3) -> Basis:
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(side, up, side.cross(up)).orthonormalized()

## The limb nearest a world point, or -1 when the point is not on one.
func limb_at(world_point: Vector3) -> int:
	var local := to_local(world_point)
	var best := -1
	var best_d := INF
	for i in limbs.size():
		var l: Dictionary = limbs[i]
		var a: Vector3 = l.origin
		var b: Vector3 = a + (l.dir as Vector3) * float(l.length)
		var d := local.distance_to(Geometry3D.get_closest_point_to_segment(local, a, b))
		if d < float(l.radius) + 0.3 and d < best_d:
			best_d = d
			best = i
	return best

## The branch as a piece of its own: its shape, and where it lies in the world.
func limb_dims(i: int) -> Dictionary:
	var l: Dictionary = limbs[i]
	return Solid.cylinder(float(l.radius), float(l.get("tip", float(l.radius) * 0.7)), float(l.length))

## How far out along limb `i` a world point is, from where it joins the trunk.
func limb_distance(i: int, world_point: Vector3) -> float:
	var l: Dictionary = limbs[i]
	return clampf((to_local(world_point) - (l.origin as Vector3)).dot(l.dir as Vector3), 0.0, float(l.length))

## Cuts limb `i` through `at` metres out from the trunk. What is past the cut
## comes away as a piece of its own (returned as its shape and where it lies);
## the stub stays on. A cut right at the trunk takes the whole limb.
func cut_limb(i: int, at: float) -> Dictionary:
	var l: Dictionary = limbs[i]
	var length := float(l.length)
	var r0 := float(l.radius)
	var r1 := float(l.get("tip", r0 * 0.7))
	# Cut close in to the trunk (limbs start at its centre line), the whole
	# limb comes away.
	if at < Solid.max_radius(dims) * 1.1 + MIN_STUB:
		var whole := {"dims": limb_dims(i), "xform": limb_transform(i)}
		remove_limb(i)
		return whole
	at = minf(at, length - MIN_STUB)
	var r_cut := lerpf(r0, r1, at / length)
	var outer := Solid.cylinder(r_cut, r1, length - at)
	var dir: Vector3 = l.dir
	var xform := global_transform * Transform3D(_up_basis(dir), (l.origin as Vector3) + dir * (at + (length - at) * 0.5))
	mass = maxf(1.0, mass - Solid.volume(outer) * _density())
	l.length = at
	l.tip = r_cut
	l.cut = 0.0
	l.cut_at = -1.0
	# The stub is redrawn plain: leaves went with the end that came off.
	for n in l.nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	var cs := l.shape as CollisionShape3D
	var cyl := cs.shape as CylinderShape3D
	cyl = cyl.duplicate()
	cyl.height = maxf(0.1, at)
	cs.shape = cyl
	cs.transform = Transform3D(_up_basis(dir), (l.origin as Vector3) + dir * at * 0.5)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = r0
	cm.top_radius = r_cut
	cm.height = at
	cm.radial_segments = 6
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = l.get("bark", Color(0.42, 0.3, 0.2))
	mat.roughness = 0.9
	mi.material_override = mat
	mi.transform = cs.transform
	add_child(mi)
	l.nodes = [mi]
	return {"dims": outer, "xform": xform}

func limb_transform(i: int) -> Transform3D:
	var l: Dictionary = limbs[i]
	return global_transform * Transform3D(_up_basis(l.dir), (l.origin as Vector3) + (l.dir as Vector3) * float(l.length) * 0.5)

func remove_limb(i: int) -> void:
	var l: Dictionary = limbs[i]
	mass = maxf(1.0, mass - Solid.volume(limb_dims(i)) * _density())
	(l.shape as Node).queue_free()
	for n in l.nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	limbs.remove_at(i)

func limb_volume() -> float:
	var total := 0.0
	for i in limbs.size():
		total += Solid.volume(limb_dims(i))
	return total

func clear_limbs() -> void:
	for l in limbs:
		if is_instance_valid(l.shape):
			(l.shape as Node).queue_free()
		for n in l.nodes:
			if is_instance_valid(n):
				(n as Node).queue_free()
	limbs.clear()

## For saving: each limb as numbers.
func limbs_to_array() -> Array:
	var out: Array = []
	for l in limbs:
		var o: Vector3 = l.origin
		var d: Vector3 = l.dir
		out.append([o.x, o.y, o.z, d.x, d.y, d.z, float(l.radius), float(l.length),
			float(l.get("tip", float(l.radius) * 0.7))])
	return out

func clear_extras() -> void:
	for e in _extras:
		if is_instance_valid(e):
			e.queue_free()
	_extras.clear()

## Its name as the player sees it, finish and all: "Sanded Pine Wood".
func display_name() -> String:
	var prefix := Solid.finish_prefix(dims)
	var base := GameData.item_name(item_id)
	return base if prefix == "" else "%s %s" % [prefix, base]

func volume() -> float:
	return Solid.volume(dims)

func length() -> float:
	return Solid.length_of(dims)

func is_wood() -> bool:
	return category == &"wood"

func set_state(next: State) -> void:
	if next == state:
		return
	var prev := state
	state = next
	match next:
		State.FREE:
			freeze = false
			sleeping = false
		State.CARRIED:
			freeze = false
			sleeping = false
			# Held by one point it swings, but settles rather than spinning.
			angular_damp = 2.5
			# Whatever holds it takes its weight: it goes where it is steered
			# and stays there, rather than sagging out of the hand.
			gravity_scale = 0.0
		State.HELD, State.CAPTURED:
			# Owned by the player's rack or a machine: kinematic, so it still
			# pushes loose items aside but costs the solver nothing.
			freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			freeze = true
		State.POOLED:
			freeze = false
			sleeping = true
			carrier = null
			clear_limbs()
	quiet_time = 0.0
	if next != State.CARRIED:
		gravity_scale = 1.0
		angular_damp = 0.9 if dims.get("shape", Solid.BOX) == Solid.CYLINDER else 0.4
	state_changed.emit(self, prev, next)

func reset_motion() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if ccd_active:
		continuous_cd = false
		ccd_active = false

func teleport(xform: Transform3D) -> void:
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xform)
	global_transform = xform
	reset_motion()

## Half the vertical extent, used by machines that place items by transform.
func get_aabb_half_height() -> float:
	return Solid.bounds(dims).y * 0.5

## Vertical half-extent once the piece is lying on its side, which is how belts,
## racks and vehicle beds carry things.
func resting_half_height() -> float:
	if dims.get("shape", Solid.BOX) == Solid.CYLINDER:
		return Solid.max_radius(dims)
	return (dims.size as Vector3).z * 0.5

## A basis that lays this piece down with its long axis horizontal, pointing
## along `yaw` (radians around +Y).
static func lying_basis(yaw: float = 0.0) -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5)

## Half the piece's thickness measured along `dir`, as it is lying now.
func extent_along(dir: Vector3) -> float:
	var b := global_transform.basis
	var d := dir.normalized()
	if dims.get("shape", Solid.BOX) == Solid.CYLINDER:
		var r := Solid.max_radius(dims)
		var axis := b.y.normalized()
		var along := absf(axis.dot(d))
		return along * length() * 0.5 + sqrt(maxf(0.0, 1.0 - along * along)) * r
	var half: Vector3 = (dims.size as Vector3) * 0.5
	return absf(b.x.normalized().dot(d)) * half.x + absf(b.y.normalized().dot(d)) * half.y \
		+ absf(b.z.normalized().dot(d)) * half.z

## Friction from a driven surface under the piece - a roller, a belt: pulls
## its velocity in the surface plane toward `surface_velocity`, but never by
## more than `grip` times gravity, so a heavy or jammed piece slips instead
## of being yanked about.
func grip_toward(surface_velocity: Vector3, up: Vector3, grip: float, delta: float) -> void:
	var slip := linear_velocity - surface_velocity
	slip -= up * slip.dot(up)
	var most := grip * 9.8 * delta
	var change := -slip
	if change.length() > most:
		change = change.normalized() * most
	if change.length_squared() < 0.000001:
		return
	sleeping = false
	linear_velocity += change
