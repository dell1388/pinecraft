class_name StressWorld
extends RefCounted

## Procedural construction of the stress-test world. Shared by the playable
## scene and the headless benchmark so both measure exactly the same setup.

const PLOT_SIZE := 44.0
const PLOT_ID := 0

static func build_environment(parent: Node3D) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -38, 0)
	light.shadow_enabled = true
	parent.add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.sky.sky_material = ProceduralSkyMaterial.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment = e
	parent.add_child(env)

## Flat plot floor plus a low perimeter wall, all primitive boxes.
static func build_ground(parent: Node3D, size: float = PLOT_SIZE) -> StaticBody3D:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = Layers.WORLD
	ground.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	ground.physics_material_override = pm

	var floor_shape := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(size, 1.0, size)
	floor_shape.shape = fb
	floor_shape.position = Vector3(0, -0.5, 0)
	ground.add_child(floor_shape)

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = fb.size
	mesh.mesh = bm
	mesh.position = floor_shape.position
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.32, 0.20)
	mesh.material_override = mat
	ground.add_child(mesh)

	var half := size * 0.5
	var walls := [
		[Vector3(0, 1.0, -half), Vector3(size, 2.0, 0.6)],
		[Vector3(0, 1.0, half), Vector3(size, 2.0, 0.6)],
		[Vector3(-half, 1.0, 0), Vector3(0.6, 2.0, size)],
		[Vector3(half, 1.0, 0), Vector3(0.6, 2.0, size)],
	]
	for w in walls:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = w[1]
		cs.shape = b
		cs.position = w[0]
		ground.add_child(cs)
		var wm := MeshInstance3D.new()
		var wbm := BoxMesh.new()
		wbm.size = b.size
		wm.mesh = wbm
		wm.position = w[0]
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(0.30, 0.28, 0.25)
		wm.material_override = wmat
		ground.add_child(wm)

	parent.add_child(ground)
	return ground

## A funnel of angled ramps so dropped logs pile into a dense heap: the worst
## case for contact counts.
static func build_funnel(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Funnel"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var ramps := [
		[Vector3(-5.0, 3.0, 0), Vector3(0, 0, -0.5)],
		[Vector3(5.0, 3.0, 0), Vector3(0, 0, 0.5)],
		[Vector3(0, 3.0, -5.0), Vector3(0.5, 0, 0)],
		[Vector3(0, 3.0, 5.0), Vector3(-0.5, 0, 0)],
	]
	for r in ramps:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(10.0, 0.4, 10.0)
		cs.shape = b
		cs.position = r[0]
		cs.rotation = r[1]
		body.add_child(cs)
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b.size
		m.mesh = bm
		m.position = r[0]
		m.rotation = r[1]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.33, 0.30)
		m.material_override = mat
		body.add_child(m)
	parent.add_child(body)

static func build_trees(parent: Node3D, manager: LooseItemManager, count: int,
		rng: RandomNumberGenerator) -> Array[ChoppableTree]:
	var trees: Array[ChoppableTree] = []
	var half := PLOT_SIZE * 0.5 - 4.0
	for i in count:
		var t := ChoppableTree.new()
		t.manager = manager
		t.plot_id = PLOT_ID
		t.trunk_height = rng.randf_range(5.0, 8.0)
		t.trunk_radius = rng.randf_range(0.30, 0.45)
		t.branch_count = rng.randi_range(4, 6)
		# Keep the middle clear so trees do not sit inside the funnel/pile.
		var pos := Vector3.ZERO
		for _attempt in 12:
			pos = Vector3(rng.randf_range(-half, half), 0.0, rng.randf_range(-half, half))
			if pos.length() > 12.0:
				break
		t.position = pos
		parent.add_child(t)
		trees.append(t)
	return trees

static func build_conveyor(parent: Node3D, origin: Vector3, yaw_deg: float,
		length: float = 12.0, speed: float = 3.0) -> Conveyor:
	var c := Conveyor.new()
	c.length = length
	c.speed = speed
	c.position = origin
	c.rotation_degrees = Vector3(0, yaw_deg, 0)
	parent.add_child(c)
	return c

## Drops `count` items in a loose column above the funnel.
static func rain_items(manager: LooseItemManager, item_id: StringName, count: int,
		rng: RandomNumberGenerator, centre: Vector3 = Vector3(0, 12, 0),
		spread: float = 3.2, layer_height: float = 0.55) -> void:
	var per_layer := 12
	for i in count:
		var layer := i / per_layer
		var pos := centre + Vector3(
			rng.randf_range(-spread, spread),
			float(layer) * layer_height,
			rng.randf_range(-spread, spread))
		var basis := Basis.from_euler(Vector3(
			rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI)))
		manager.spawn(item_id, Transform3D(basis, pos), PLOT_ID)

## Fires items at high speed to exercise CCD and the velocity clamp.
static func fire_cannon(manager: LooseItemManager, item_id: StringName, count: int,
		from: Vector3, dir: Vector3, speed: float, rng: RandomNumberGenerator) -> void:
	for i in count:
		var jitter := Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.2, 0.4), rng.randf_range(-0.4, 0.4))
		var item := manager.spawn(item_id, Transform3D(Basis(), from + jitter), PLOT_ID)
		if item != null:
			item.linear_velocity = (dir.normalized() * speed)
