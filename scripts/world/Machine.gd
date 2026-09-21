class_name Machine
extends Node3D

## A processing machine: a shell with a hole to feed and a hole to collect from.
##
## Sawmill and furnace conserve volume. Whatever is fed in is measured, cut or
## smelted at a fixed cubic-metres-per-second rate, and comes back out as pieces
## with the outlet's cross-section, at whatever length that volume needs. Nothing
## is created or destroyed on the way through, so a fat trunk yields long boards
## and a thin branch yields a short one.
##
## Kinematic by construction: a static shell plus trigger volumes. Material
## inside the machine is bookkeeping, not physics bodies.

signal produced(machine: Machine, output_id: StringName, volume: float)
signal state_changed(machine: Machine)

const WALL := 0.2

@export var building_id: StringName = &"sawmill"

var def: BuildingDef
var machine_def: MachineDef
var manager: LooseItemManager
var plot_id: int = 0

var queue: Array[Dictionary] = []      ## mill/smelt jobs: {output_id, volume}
var stock: Dictionary = {}             ## assemble mode: category -> cubic metres
var job: Dictionary = {}               ## current job being worked
var progress: float = 0.0
var stalled: bool = false
var total_produced: int = 0
var volume_in: float = 0.0
var volume_out: float = 0.0

var _body: StaticBody3D
var _intake_area: Area3D
var _intake_shape: CollisionShape3D
var _outlet_area: Area3D
var _outlet_shape: CollisionShape3D
var _outlet_point: Node3D
var _intake_point: Node3D
var _backlog: int = 0
var _poll: float = 0.0
var _size: Vector3 = Vector3(3, 3, 3)

func setup(p_manager: LooseItemManager, p_def: BuildingDef, p_plot_id: int = 0) -> void:
	manager = p_manager
	def = p_def
	building_id = p_def.id
	plot_id = p_plot_id
	machine_def = GameData.machine(p_def.machine)

func _ready() -> void:
	if def == null:
		def = GameData.building(building_id)
	if machine_def == null and def != null:
		machine_def = GameData.machine(def.machine)
	_size = def.footprint_world(1.0)
	_build()
	set_physics_process(true)

# --- Geometry --------------------------------------------------------------

func _build() -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = Layers.MACHINE
	_body.collision_mask = Layers.MASK_MACHINE
	add_child(_body)

	var faces := ["front", "back", "left", "right", "top"]
	for face in faces:
		var hole := Vector2.ZERO
		var height := 0.0
		if StringName(face) == machine_def.intake_face:
			hole = machine_def.intake_hole
			height = machine_def.intake_height
		elif StringName(face) == machine_def.outlet_face:
			hole = machine_def.outlet_hole
			height = machine_def.outlet_height
		_add_wall(face, hole, height)
	_add_part(Vector3(_size.x, WALL, _size.z), Vector3(0, WALL * 0.5, 0), machine_def.color.darkened(0.25))

	_intake_point = _face_point(machine_def.intake_face, machine_def.intake_height, 0.55)
	add_child(_intake_point)
	_outlet_point = _face_point(machine_def.outlet_face, machine_def.outlet_height, 0.75)
	add_child(_outlet_point)

	# The intake volume straddles the hole so material resting in the mouth is
	# taken, whether it was carried, thrown, dropped or delivered by a belt.
	_intake_area = Area3D.new()
	_intake_area.collision_layer = Layers.TRIGGER
	_intake_area.collision_mask = Layers.LOOSE
	_intake_shape = CollisionShape3D.new()
	var ib := BoxShape3D.new()
	var mouth := machine_def.intake_hole
	ib.size = Vector3(maxf(mouth.x, 0.6) + 0.5, maxf(mouth.y, 0.6) + 0.5, 1.5)
	if machine_def.intake_face == &"top":
		ib.size = Vector3(mouth.x + 0.5, 1.5, mouth.y + 0.5)
	elif machine_def.intake_face == &"left" or machine_def.intake_face == &"right":
		ib.size = Vector3(1.5, mouth.y + 0.5, mouth.x + 0.5)
	_intake_shape.shape = ib
	_intake_area.add_child(_intake_shape)
	_intake_area.body_entered.connect(_on_intake_body)
	add_child(_intake_area)
	_intake_area.global_transform = _intake_point.global_transform

	_outlet_area = Area3D.new()
	_outlet_area.collision_layer = Layers.TRIGGER
	_outlet_area.collision_mask = Layers.LOOSE
	_outlet_shape = CollisionShape3D.new()
	var ob := BoxShape3D.new()
	ob.size = Vector3(2.4, 1.8, 2.4)
	_outlet_shape.shape = ob
	_outlet_area.add_child(_outlet_shape)
	add_child(_outlet_area)
	_outlet_area.global_transform = _outlet_point.global_transform

	_decorate()

func _add_part(size: Vector3, pos: Vector3, color: Color, collide: bool = true) -> void:
	if collide:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		cs.position = pos
		_body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mi.material_override = mat
	_body.add_child(mi)

## Builds one wall as up to four boxes around a rectangular opening. `hole` of
## zero size makes a solid wall.
func _add_wall(face: String, hole: Vector2, hole_height: float) -> void:
	var u_size: float
	var v_size: float
	match face:
		"front", "back":
			u_size = _size.x; v_size = _size.y
		"left", "right":
			u_size = _size.z; v_size = _size.y
		_:
			u_size = _size.x; v_size = _size.z
	var color := machine_def.color
	var cu := 0.0
	var cv := 0.0 if face == "top" else clampf(hole_height, hole.y * 0.5, v_size - hole.y * 0.5) - v_size * 0.5
	var rects: Array = []
	if hole.x <= 0.01 or hole.y <= 0.01:
		rects.append([0.0, 0.0, u_size, v_size])
	else:
		var hu := minf(hole.x, u_size - 0.1)
		var hv := minf(hole.y, v_size - 0.1)
		var below := (cv - hv * 0.5) + v_size * 0.5
		var above := v_size * 0.5 - (cv + hv * 0.5)
		var left := (cu - hu * 0.5) + u_size * 0.5
		var right := u_size * 0.5 - (cu + hu * 0.5)
		if below > 0.01:
			rects.append([0.0, -v_size * 0.5 + below * 0.5, u_size, below])
		if above > 0.01:
			rects.append([0.0, v_size * 0.5 - above * 0.5, u_size, above])
		if left > 0.01:
			rects.append([-u_size * 0.5 + left * 0.5, cv, left, hv])
		if right > 0.01:
			rects.append([u_size * 0.5 - right * 0.5, cv, right, hv])
	for r in rects:
		_add_part(_wall_size(face, r[2], r[3]), _wall_pos(face, r[0], r[1]), color)

func _wall_size(face: String, u: float, v: float) -> Vector3:
	match face:
		"front", "back":
			return Vector3(u, v, WALL)
		"left", "right":
			return Vector3(WALL, v, u)
		_:
			return Vector3(u, WALL, v)

func _wall_pos(face: String, u: float, v: float) -> Vector3:
	match face:
		"front":
			return Vector3(u, _size.y * 0.5 + v, _size.z * 0.5 - WALL * 0.5)
		"back":
			return Vector3(u, _size.y * 0.5 + v, -_size.z * 0.5 + WALL * 0.5)
		"left":
			return Vector3(-_size.x * 0.5 + WALL * 0.5, _size.y * 0.5 + v, u)
		"right":
			return Vector3(_size.x * 0.5 - WALL * 0.5, _size.y * 0.5 + v, u)
		_:
			return Vector3(u, _size.y - WALL * 0.5, v)

## A point just outside (or above) a face, at the hole's height.
func _face_point(face: StringName, height: float, offset: float) -> Node3D:
	var n := Node3D.new()
	match face:
		&"front":
			n.position = Vector3(0, height, _size.z * 0.5 + offset)
		&"back":
			n.position = Vector3(0, height, -_size.z * 0.5 - offset)
			n.rotation.y = PI
		&"left":
			n.position = Vector3(-_size.x * 0.5 - offset, height, 0)
			n.rotation.y = -PI * 0.5
		&"right":
			n.position = Vector3(_size.x * 0.5 + offset, height, 0)
			n.rotation.y = PI * 0.5
		_:
			n.position = Vector3(0, _size.y + offset, 0)
	return n

## Machine-specific dressing. Meshes only: none of it collides.
func _decorate() -> void:
	var accent := machine_def.color.lightened(0.18)
	match machine_def.id:
		&"sawmill":
			# Blade housing and the blade itself, poking through the roof.
			_add_part(Vector3(1.1, 0.5, 0.35), Vector3(0, _size.y + 0.25, 0.6), accent, false)
			var blade := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = 0.85
			disc.bottom_radius = 0.85
			disc.height = 0.06
			disc.radial_segments = 20
			blade.mesh = disc
			blade.position = Vector3(0, _size.y + 0.45, 0.6)
			blade.rotation = Vector3(0, 0, PI * 0.5)
			var bmat := StandardMaterial3D.new()
			bmat.albedo_color = Color(0.72, 0.74, 0.78)
			bmat.metallic = 0.6
			bmat.roughness = 0.35
			blade.material_override = bmat
			_body.add_child(blade)
			# Infeed ramp and outfeed lip, so the holes read as holes.
			_add_part(Vector3(machine_def.intake_hole.x + 0.4, 0.12, 1.0),
				Vector3(0, machine_def.intake_height - machine_def.intake_hole.y * 0.5,
					_size.z * 0.5 + 0.45), accent, false)
			_add_part(Vector3(machine_def.outlet_hole.x + 0.5, 0.12, 0.9),
				Vector3(0, machine_def.outlet_height - machine_def.outlet_hole.y * 0.5,
					-_size.z * 0.5 - 0.4), accent, false)
			for side in [-1.0, 1.0]:
				_add_part(Vector3(0.22, 0.9, 0.22), Vector3(side * (_size.x * 0.5 - 0.2), 0.45,
					_size.z * 0.5 - 0.3), accent.darkened(0.25), false)
		&"furnace":
			var stack := MeshInstance3D.new()
			var pipe := CylinderMesh.new()
			pipe.top_radius = 0.26
			pipe.bottom_radius = 0.32
			pipe.height = 1.6
			pipe.radial_segments = 12
			stack.mesh = pipe
			stack.position = Vector3(_size.x * 0.28, _size.y + 0.8, -_size.z * 0.28)
			var smat := StandardMaterial3D.new()
			smat.albedo_color = machine_def.color.darkened(0.3)
			stack.material_override = smat
			_body.add_child(stack)
			# Glowing mouth around the outlet.
			var glow := MeshInstance3D.new()
			var gb := BoxMesh.new()
			gb.size = Vector3(0.12, machine_def.outlet_hole.y, machine_def.outlet_hole.x)
			glow.mesh = gb
			glow.position = Vector3(_size.x * 0.5 - 0.02, machine_def.outlet_height, 0)
			var gmat := StandardMaterial3D.new()
			gmat.albedo_color = Color(0.95, 0.45, 0.12)
			gmat.emission_enabled = true
			gmat.emission = Color(0.85, 0.32, 0.06)
			gmat.emission_energy_multiplier = 1.6
			glow.material_override = gmat
			_body.add_child(glow)
			_add_part(Vector3(machine_def.intake_hole.x + 0.5, 0.14, machine_def.intake_hole.y + 0.5),
				Vector3(0, _size.y + 0.07, 0), accent, false)
		&"workbench":
			_add_part(Vector3(_size.x - 0.4, 0.16, _size.z - 0.4), Vector3(0, _size.y + 0.08, 0),
				Color(0.55, 0.41, 0.26), false)
			for i in 3:
				_add_part(Vector3(0.1, 0.55, 0.1),
					Vector3(-0.8 + float(i) * 0.8, _size.y + 0.4, -_size.z * 0.5 + 0.35),
					accent.darkened(0.2), false)

# --- Intake ----------------------------------------------------------------

func buffered_m3() -> float:
	var total := 0.0
	for j in queue:
		total += float(j.volume)
	for c in stock:
		total += float(stock[c])
	if not job.is_empty():
		total += float(job.volume)
	return total

func can_accept(item_id: StringName) -> bool:
	if machine_def == null:
		return false
	if buffered_m3() >= machine_def.buffer_m3:
		return false
	return GameData.machine_accepts(machine_def.id, item_id)

func accept_item(item: LooseItem) -> bool:
	if not can_accept(item.item_id):
		return false
	var v := item.volume()
	volume_in += v
	if machine_def.mode == MachineDef.MODE_ASSEMBLE:
		stock[item.category] = float(stock.get(item.category, 0.0)) + v
	else:
		queue.append({"output_id": machine_def.output_for(item.item_id), "volume": v})
	manager.despawn(item)
	state_changed.emit(self)
	return true

func _on_intake_body(body: Node) -> void:
	var item := body as LooseItem
	if item == null or item.state != LooseItem.State.FREE:
		return
	if not Trigger.contains_point(_intake_shape, item.global_position, 0.3):
		return
	accept_item(item)

func input_point() -> Vector3:
	return _intake_point.global_position

func output_point() -> Vector3:
	return _outlet_point.global_position

# --- Processing ------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_poll += delta
	if _poll >= 0.2:
		_poll = 0.0
		_backlog = Trigger.bodies_inside(_outlet_area, _outlet_shape).size()
		for body in Trigger.bodies_inside(_intake_area, _intake_shape):
			_on_intake_body(body)

	if job.is_empty():
		_start_job()
		return
	if _backlog >= 14:
		_set_stalled(true)
		return
	_set_stalled(false)
	progress += delta
	if progress >= float(job.duration):
		_finish_job()

func _start_job() -> void:
	if machine_def.mode == MachineDef.MODE_ASSEMBLE:
		var recipe := GameData.first_ready_recipe(machine_def.id, stock)
		if recipe == null:
			return
		recipe.consume_from(stock)
		job = {"recipe": recipe.id, "output_id": recipe.output, "volume": 0.0,
			"duration": recipe.seconds}
	else:
		if queue.is_empty():
			return
		var next: Dictionary = queue.pop_front()
		var duration: float = maxf(0.4, float(next.volume) / maxf(0.001, machine_def.m3_per_second))
		job = {"output_id": next.output_id, "volume": float(next.volume), "duration": duration}
	progress = 0.0
	state_changed.emit(self)

func _finish_job() -> void:
	var output_id: StringName = job.output_id
	var volume: float = float(job.volume)
	job = {}
	progress = 0.0

	var pieces: Array[Dictionary] = []
	if machine_def.mode == MachineDef.MODE_ASSEMBLE:
		var def_out: ItemDef = GameData.item(output_id)
		if def_out != null:
			pieces.append(def_out.default_dims())
	else:
		pieces = Solid.cut_to_pieces(volume, machine_def.cross_section, machine_def.max_piece_length)

	var origin := _outlet_point.global_transform
	var forward := -origin.basis.z
	for i in pieces.size():
		var xform := Transform3D(
			LooseItem.lying_basis(origin.basis.get_euler().y),
			origin.origin + Vector3(0, float(i) * 0.05, 0) + forward * float(i) * 0.12)
		var spawned := manager.spawn(output_id, xform, plot_id, forward * 1.2, pieces[i], true)
		if spawned == null:
			break
		volume_out += spawned.volume()
		total_produced += 1
	produced.emit(self, output_id, volume)
	state_changed.emit(self)

func _set_stalled(value: bool) -> void:
	if stalled == value:
		return
	stalled = value
	state_changed.emit(self)

func input_summary() -> String:
	if machine_def.mode == MachineDef.MODE_ASSEMBLE:
		if stock.is_empty():
			return "empty"
		var parts: Array[String] = []
		for c in stock:
			parts.append("%.2f m3 %s" % [float(stock[c]), String(c)])
		return ", ".join(parts)
	if queue.is_empty():
		return "empty"
	return "%d job(s), %.2f m3" % [queue.size(), buffered_m3()]

func status_line() -> String:
	if not job.is_empty():
		return "%s: %d%% (%.2f m3)" % [def.display_name,
			int(progress / maxf(0.01, float(job.duration)) * 100.0), float(job.volume)]
	if stalled:
		return "%s: outlet blocked" % def.display_name
	return "%s: idle (%s)" % [def.display_name, input_summary()]

func to_dict() -> Dictionary:
	var jobs: Array = []
	for j in queue:
		jobs.append({"output_id": String(j.output_id), "volume": float(j.volume)})
	var st := {}
	for c in stock:
		st[String(c)] = float(stock[c])
	return {"queue": jobs, "stock": st, "total_produced": total_produced,
		"volume_in": volume_in, "volume_out": volume_out}

func from_dict(d: Dictionary) -> void:
	queue.clear()
	for j in d.get("queue", []):
		queue.append({"output_id": StringName(j.get("output_id", "")), "volume": float(j.get("volume", 0.0))})
	stock.clear()
	for c in d.get("stock", {}):
		stock[StringName(c)] = float(d["stock"][c])
	total_produced = int(d.get("total_produced", 0))
	volume_in = float(d.get("volume_in", 0.0))
	volume_out = float(d.get("volume_out", 0.0))
