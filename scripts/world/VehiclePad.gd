class_name VehiclePad
extends Node3D

## A marked slab on the property that a vehicle appears on.
##
## The pad is the vehicle: owning one is what lets you have a truck, and one pad
## is worth exactly one truck. Triggering it again does not give you a second -
## it takes the old one away first, wherever it happens to have been left, which
## is also how you get a truck back after driving it into a ravine.

signal vehicle_spawned(pad: VehiclePad, vehicle: Node3D)

@export var building_id: StringName = &"vehicle_pad"

var def: BuildingDef
var manager: LooseItemManager
var plot_id: int = 0
## Where a spawned vehicle is parented. Not the pad itself: a truck has to be
## able to drive off it.
var host: Node3D
var terrain: Terrain

var vehicle: Node3D = null

var _size: Vector3 = Vector3(4, 0.2, 6)

func setup(p_manager: LooseItemManager, p_def: BuildingDef, p_plot_id: int = 0,
		p_host: Node3D = null) -> void:
	manager = p_manager
	def = p_def
	building_id = p_def.id
	plot_id = p_plot_id
	host = p_host

func _ready() -> void:
	if def == null:
		def = GameData.building(building_id)
	_size = def.footprint_world(Plot.CELL)
	_build()

func has_vehicle() -> bool:
	return vehicle != null and is_instance_valid(vehicle)

## Spec: one copy at a time. A second call clears the first.
func spawn() -> Node3D:
	recall()
	var truck := Hauler.new()
	truck.setup(manager, plot_id)
	truck.terrain = terrain
	var target: Node3D = host if host != null else get_parent() as Node3D
	if target == null:
		return null
	target.add_child(truck)
	truck.global_transform = Transform3D(
		Basis.from_euler(Vector3(0, global_rotation.y, 0)),
		global_position + Vector3(0, 1.4, 0))
	vehicle = truck
	vehicle_spawned.emit(self, truck)
	return truck

## Takes the current vehicle away, wherever it is. Its load goes with it.
func recall() -> bool:
	if not has_vehicle():
		vehicle = null
		return false
	vehicle.queue_free()
	vehicle = null
	return true

func status_line() -> String:
	if has_vehicle():
		var distance := global_position.distance_to((vehicle as Node3D).global_position)
		return "%s: [E] recall and respawn (truck is %.0f m away)" % [def.display_name, distance]
	return "%s: [E] spawn the hauler" % def.display_name

# --- Geometry --------------------------------------------------------------

func _build() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.MACHINE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_size.x, 0.2, _size.z)
	cs.shape = box
	cs.position = Vector3(0, 0.1, 0)
	body.add_child(cs)
	add_child(body)

	var g := Greeble.new()
	g.block(Vector3(_size.x, 0.2, _size.z), Vector3(0, 0.1, 0), Color(0.24, 0.25, 0.27))
	g.frame(Vector3(_size.x, 0.2, _size.z), Transform3D(Basis(), Vector3(0, 0.1, 0)), 0.1, Color(0.16, 0.16, 0.18))
	# Hazard stripes down the long edges, so the pad reads as somewhere a
	# vehicle lands rather than as a floor tile.
	for side in [-1.0, 1.0]:
		g.stripes(_size.z - 0.3, 0.32, Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, -PI * 0.5),
			Vector3(side * (_size.x * 0.5 - 0.24), 0.2, 0)))
	# A painted "H" and parking lines.
	var paint := Color(0.92, 0.92, 0.88)
	g.block(Vector3(0.2, 0.02, 1.6), Vector3(-0.55, 0.21, 0), paint)
	g.block(Vector3(0.2, 0.02, 1.6), Vector3(0.55, 0.21, 0), paint)
	g.block(Vector3(1.1, 0.02, 0.2), Vector3(0, 0.21, 0), paint)
	# A post at the head of the pad with a sign, and lamps on the corners.
	g.block(Vector3(0.16, 1.6, 0.16), Vector3(0, 0.8, -_size.z * 0.5 + 0.3), Color(0.35, 0.36, 0.38))
	g.plate(1.1, 0.5, Transform3D(Basis(), Vector3(0, 1.7, -_size.z * 0.5 + 0.38)), Color(0.86, 0.72, 0.16))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var at := Vector3(sx * (_size.x * 0.5 - 0.1), 0.2, sz * (_size.z * 0.5 - 0.1))
			g.block(Vector3(0.14, 0.5, 0.14), at + Vector3(0, 0.25, 0), Color(0.2, 0.2, 0.22))
			g.block(Vector3(0.18, 0.12, 0.18), at + Vector3(0, 0.56, 0), Color(1.0, 0.62, 0.2), true)
	add_child(g.instance("Pad"))

func _slab(size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mi.material_override = mat
	add_child(mi)

func to_dict() -> Dictionary:
	var d := {"has_vehicle": has_vehicle()}
	if has_vehicle() and vehicle.has_method("to_dict"):
		d["vehicle"] = vehicle.call("to_dict")
	return d

func from_dict(d: Dictionary) -> void:
	if not bool(d.get("has_vehicle", false)):
		return
	var truck := spawn()
	if truck != null and d.has("vehicle") and truck.has_method("from_dict"):
		truck.call("from_dict", d["vehicle"])
