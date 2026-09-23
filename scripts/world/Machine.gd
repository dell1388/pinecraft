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
## Everything the shell draws, merged; built up by _add_part and _decorate.
var _g: Greeble
var _lamp_material: StandardMaterial3D
var _intake_area: Area3D
var _intake_shape: CollisionShape3D
var _outlet_area: Area3D
var _outlet_shape: CollisionShape3D
var _outlet_point: Node3D
var _intake_point: Node3D
var _backlog: int = 0
var _poll: float = 0.0
var _size: Vector3 = Vector3(3, 3, 3)
## Per-machine, because upgrading a sawmill must not widen every sawmill's
## definition. These are the definition's holes and rate scaled by this
## machine's level.
var intake_hole: Vector2 = Vector2(0.7, 0.7)
var outlet_hole: Vector2 = Vector2(0.4, 0.4)
var rate_m3_per_second: float = 0.05
var level: int = 1

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
	_apply_level()
	_build()
	# A machine already standing on the plot has to grow when its line is
	# upgraded; buying a wider mouth and not getting one would be absurd.
	PlayerState.upgraded.connect(_on_upgraded)
	set_physics_process(true)

func _on_upgraded(track: StringName, _new_level: int) -> void:
	if machine_def == null or track != machine_def.id:
		return
	_apply_level()
	_rebuild_shell()

## Rebuilds the shell around the new hole sizes. Buffered work is bookkeeping
## rather than geometry, so it rides through untouched.
func _rebuild_shell() -> void:
	for node in [_body, _intake_area, _outlet_area, _intake_point, _outlet_point]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_body = null
	_intake_area = null
	_outlet_area = null
	_intake_point = null
	_outlet_point = null
	_build()

## Spec: machine levels give larger intake and outlet holes, and get through
## more material. A bigger mouth is the upgrade that matters, because the hole
## is what decides whether a whole trunk goes in or has to be bucked first.
func _apply_level() -> void:
	level = PlayerState.level(machine_def.id)
	var hole_scale := PlayerState.stat(machine_def.id, "hole_scale", 1.0)
	var rate_scale := PlayerState.stat(machine_def.id, "rate_scale", 1.0)
	intake_hole = machine_def.intake_hole * hole_scale
	outlet_hole = machine_def.outlet_hole * hole_scale
	rate_m3_per_second = machine_def.m3_per_second * rate_scale

# --- Geometry --------------------------------------------------------------

func _build() -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = Layers.MACHINE
	_body.collision_mask = Layers.MASK_MACHINE
	add_child(_body)
	_g = Greeble.new()

	var faces := ["front", "back", "left", "right", "top"]
	for face in faces:
		var hole := Vector2.ZERO
		var height := 0.0
		if StringName(face) == machine_def.intake_face:
			hole = intake_hole
			height = machine_def.intake_height
		elif StringName(face) == machine_def.outlet_face:
			hole = outlet_hole
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
	var mouth := intake_hole
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
	_body.add_child(_g.instance("Shell"))
	_add_status_lamp()

func _add_part(size: Vector3, pos: Vector3, color: Color, collide: bool = true) -> void:
	if collide:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		cs.position = pos
		_body.add_child(cs)
	_g.block(size, pos, color)

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

## Where a face is, as a frame on its outside surface with +Z pointing out.
func _face_frame(face: String) -> Transform3D:
	match face:
		"front":
			return Transform3D(Basis(), Vector3(0, 0, _size.z * 0.5))
		"back":
			return Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -_size.z * 0.5))
		"left":
			return Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-_size.x * 0.5, 0, 0))
		"right":
			return Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(_size.x * 0.5, 0, 0))
	return Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, _size.y, 0))

func _face_width(face: String) -> float:
	return _size.x if face == "front" or face == "back" else _size.z

## Machine dressing. Meshes only: none of it collides. Every machine gets a
## framed, plated, vented shell, so a box reads as built; then each gets what
## makes it that machine - a blade, a chimney, a hopper, a bench.
func _decorate() -> void:
	var body := machine_def.color
	var accent := body.lightened(0.18)
	var trim := body.darkened(0.35)
	var steel := Color(0.62, 0.63, 0.66)
	# Frame on every edge, and a plinth.
	_g.frame(Vector3(_size.x, _size.y, _size.z), Transform3D(Basis(), Vector3(0, _size.y * 0.5, 0)), 0.14, trim)
	_g.block(Vector3(_size.x + 0.16, 0.16, _size.z + 0.16), Vector3(0, 0.08, 0), trim.darkened(0.2))
	# Plates, vents and stripes on the faces with no hole in them.
	var holes := [String(machine_def.intake_face), String(machine_def.outlet_face)]
	var first_solid := ""
	for face in ["front", "back", "left", "right"]:
		var f := _face_frame(face)
		var w := _face_width(face)
		if holes.has(face):
			# Warning stripes under the hole, so you can find the mouth.
			_g.stripes(w - 0.3, 0.16, f * Transform3D(Basis(), Vector3(0, 0.3, 0.0)))
			continue
		if first_solid == "":
			first_solid = face
		_g.plate(w * 0.55, _size.y * 0.34, f * Transform3D(Basis(), Vector3(-w * 0.12, _size.y * 0.42, 0)), accent)
		_g.vent(w * 0.26, _size.y * 0.16, f * Transform3D(Basis(), Vector3(w * 0.3, _size.y * 0.74, 0)), trim)
	# A control box with the status light on the first solid face.
	if first_solid != "":
		var f := _face_frame(first_solid)
		var w := _face_width(first_solid)
		var box_at := f * Transform3D(Basis(), Vector3(w * 0.3, _size.y * 0.36, 0.12))
		_g.box(Vector3(0.5, 0.62, 0.24), box_at, Color(0.22, 0.23, 0.25))
		_g.box(Vector3(0.1, 0.1, 0.06), box_at * Transform3D(Basis(), Vector3(-0.12, -0.14, 0.14)), Color(0.85, 0.22, 0.18))
		_g.box(Vector3(0.1, 0.1, 0.06), box_at * Transform3D(Basis(), Vector3(0.12, -0.14, 0.14)), Color(0.25, 0.72, 0.30))
		_g.pipe((box_at * Vector3(0, -0.31, 0)), Vector3((box_at * Vector3.ZERO).x, 0.1, (box_at * Vector3.ZERO).z), 0.04, steel, 4)
		_lamp_at = box_at * Transform3D(Basis(), Vector3(0, 0.14, 0.13))

	match machine_def.id:
		&"sawmill":
			# Blade housing and the blade itself, through the roof.
			_g.block(Vector3(1.3, 0.55, 1.1), Vector3(0, _size.y + 0.27, 0.6), accent)
			_g.stripes(1.3, 0.12, Transform3D(Basis(), Vector3(0, _size.y + 0.2, 1.16)))
			_g.prism(16, 0.9, 0.9, 0.06, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.03, _size.y + 0.62, 0.6)), steel)
			for i in 16:
				var a := TAU * float(i) / 16.0
				_g.box(Vector3(0.07, 0.12, 0.05), Transform3D(Basis(Vector3.RIGHT, a), Vector3(0, _size.y + 0.62, 0.6) + Vector3(0, cos(a), sin(a)) * 0.93), Color(0.8, 0.8, 0.82))
			_g.prism(8, 0.18, 0.18, 0.12, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.1, _size.y + 0.62, 0.6)), trim)
			# Motor with cooling fins, and a belt guard to the blade.
			var motor := Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(_size.x * 0.5 - 0.1, _size.y + 0.35, -1.2))
			_g.prism(8, 0.35, 0.35, 0.8, motor, Color(0.25, 0.42, 0.30))
			for k in 5:
				_g.prism(8, 0.39, 0.39, 0.04, motor.translated_local(Vector3(0, 0.12 + float(k) * 0.14, 0)), Color(0.2, 0.34, 0.24))
			_g.block(Vector3(0.2, 0.3, 1.6), Vector3(_size.x * 0.5 - 0.5, _size.y + 0.35, -0.3), trim)
			# In-feed ramp and rollers, out-feed lip.
			_g.box(Vector3(intake_hole.x + 0.4, 0.12, 1.0), Transform3D(Basis(), Vector3(0, machine_def.intake_height - intake_hole.y * 0.5, _size.z * 0.5 + 0.45)), accent)
			for k in 3:
				_g.pipe(Vector3(-intake_hole.x * 0.5 - 0.1, machine_def.intake_height - intake_hole.y * 0.5 + 0.1, _size.z * 0.5 + 0.15 + float(k) * 0.3),
					Vector3(intake_hole.x * 0.5 + 0.1, machine_def.intake_height - intake_hole.y * 0.5 + 0.1, _size.z * 0.5 + 0.15 + float(k) * 0.3), 0.06, steel, 6)
			_g.block(Vector3(outlet_hole.x + 0.5, 0.12, 0.9), Vector3(0, machine_def.outlet_height - outlet_hole.y * 0.5, -_size.z * 0.5 - 0.4), accent)
			# Sawdust chute.
			_g.pipe(Vector3(-_size.x * 0.5 - 0.1, _size.y - 0.4, 0.8), Vector3(-_size.x * 0.5 - 0.35, 0.2, 1.6), 0.16, Color(0.72, 0.60, 0.24), 6)
		&"furnace":
			# Brick courses, a chimney with a cap, and a glowing mouth.
			var y := 0.35
			while y < _size.y - 0.2:
				for face in ["front", "back", "left", "right"]:
					if face == String(machine_def.outlet_face):
						continue
					var f := _face_frame(face)
					_g.box(Vector3(_face_width(face) - 0.3, 0.04, 0.03), f * Transform3D(Basis(), Vector3(0, y, 0.015)), body.darkened(0.3))
				y += 0.36
			var stack := Transform3D(Basis(), Vector3(_size.x * 0.28, _size.y, -_size.z * 0.28))
			_g.prism(8, 0.38, 0.3, 2.0, stack, body.darkened(0.3))
			_g.prism(8, 0.46, 0.46, 0.12, stack.translated_local(Vector3(0, 1.9, 0)), trim)
			_g.prism(8, 0.5, 0.2, 0.25, stack.translated_local(Vector3(0, 2.25, 0)), trim)
			for k in 3:
				_g.prism(8, 0.34, 0.34, 0.06, stack.translated_local(Vector3(0, 0.5 + float(k) * 0.5, 0)), steel.darkened(0.2))
			var out := _face_frame(String(machine_def.outlet_face))
			_g.box(Vector3(outlet_hole.x + 0.3, outlet_hole.y + 0.3, 0.1), out * Transform3D(Basis(), Vector3(0, machine_def.outlet_height, 0.03)), Color(1.0, 0.45, 0.10), true)
			_g.box(Vector3(outlet_hole.x + 0.6, 0.14, 0.6), out * Transform3D(Basis(), Vector3(0, machine_def.outlet_height - outlet_hole.y * 0.5 - 0.1, 0.3)), trim)
			# The charging hatch round the hole in the top.
			_g.frame(Vector3(intake_hole.x + 0.3, 0.2, intake_hole.y + 0.3), Transform3D(Basis(), Vector3(0, _size.y + 0.1, 0)), 0.14, accent)
			var glow := OmniLight3D.new()
			glow.light_color = Color(1.0, 0.5, 0.2)
			glow.light_energy = 1.0
			glow.omni_range = 4.0
			glow.position = out * Vector3(0, machine_def.outlet_height, 0.8)
			glow.distance_fade_enabled = true
			glow.distance_fade_begin = 40.0
			_body.add_child(glow)
		&"workbench":
			# Bench top, a vise, tools on a pegboard and a lamp over it all.
			_g.block(Vector3(_size.x - 0.2, 0.16, _size.z - 0.4), Vector3(0, _size.y + 0.08, 0), Color(0.55, 0.41, 0.26))
			_g.box(Vector3(0.5, 0.3, 0.3), Transform3D(Basis(), Vector3(-_size.x * 0.3, _size.y + 0.3, _size.z * 0.3)), steel.darkened(0.2))
			_g.pipe(Vector3(-_size.x * 0.3, _size.y + 0.3, _size.z * 0.3 + 0.15), Vector3(-_size.x * 0.3, _size.y + 0.3, _size.z * 0.3 + 0.5), 0.03, steel, 4)
			var board := Transform3D(Basis(), Vector3(0, _size.y + 0.9, -_size.z * 0.5 + 0.25))
			_g.box(Vector3(_size.x - 0.6, 1.4, 0.08), board, Color(0.72, 0.62, 0.46))
			for k in 5:
				var x := -_size.x * 0.35 + float(k) * _size.x * 0.17
				_g.box(Vector3(0.06, 0.45 + 0.1 * float(k % 2), 0.05), board * Transform3D(Basis(Vector3.FORWARD, 0.15 * float(k - 2)), Vector3(x, 0.1, 0.07)), steel.darkened(0.1 * float(k % 3)))
				_g.box(Vector3(0.18, 0.1, 0.06), board * Transform3D(Basis(), Vector3(x, 0.35, 0.08)), Color(0.8, 0.25, 0.2) if k % 2 == 0 else Color(0.25, 0.4, 0.75))
			_g.pipe(Vector3(_size.x * 0.4, _size.y, -_size.z * 0.35), Vector3(_size.x * 0.4, _size.y + 1.8, -_size.z * 0.35), 0.04, trim, 4)
			_g.pipe(Vector3(_size.x * 0.4, _size.y + 1.8, -_size.z * 0.35), Vector3(_size.x * 0.1, _size.y + 1.9, -_size.z * 0.1), 0.04, trim, 4)
			_g.lamp(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(_size.x * 0.1, _size.y + 1.8, -_size.z * 0.1)), Color(1.0, 0.92, 0.7), 0.24)
		&"crusher":
			# A hopper over the mouth, a flywheel on the side, and a drive belt.
			var hop := Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, _size.y, 0))
			_g.prism(4, intake_hole.x * 0.72 + 0.1, intake_hole.x * 0.72 + 0.55, 0.9, hop, accent, false, false)
			_g.prism(4, intake_hole.x * 0.72 + 0.62, intake_hole.x * 0.72 + 0.62, 0.1, hop.translated_local(Vector3(0, 0.9, 0)), trim)
			var side := _face_frame("left")
			var wheel := side * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.4, _size.y * 0.55, 0.05))
			_g.prism(10, 0.95, 0.95, 0.18, wheel, Color(0.22, 0.22, 0.24))
			_g.prism(10, 0.3, 0.3, 0.26, wheel, steel)
			for k in 5:
				var a := TAU * float(k) / 5.0
				var spoke := wheel * Transform3D(Basis(Vector3.UP, a), Vector3(0, 0.09, 0))
				_g.box(Vector3(0.12, 0.08, 1.7), spoke, Color(0.3, 0.3, 0.32))
			var motor := side * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.9, 0.5, 0.05))
			_g.prism(8, 0.32, 0.32, 0.7, motor, Color(0.25, 0.42, 0.30))
			_g.pipe(side * Vector3(-0.9, 0.5, 0.45), side * Vector3(0.4, _size.y * 0.55 + 0.9, 0.2), 0.05, Color(0.1, 0.1, 0.1), 4)
			_g.pipe(side * Vector3(-0.9, 0.5, 0.45), side * Vector3(0.4, _size.y * 0.55 - 0.9, 0.2), 0.05, Color(0.1, 0.1, 0.1), 4)
			var out := _face_frame(String(machine_def.outlet_face))
			_g.box(Vector3(outlet_hole.x + 0.4, 0.12, 0.8), out * Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, machine_def.outlet_height - outlet_hole.y * 0.5 - 0.05, 0.4)), steel.darkened(0.15))

var _lamp_at: Transform3D = Transform3D(Basis(), Vector3(0, -10, 0))
var _lamp: MeshInstance3D

## The machine's state as a light on its control box: green working, amber
## waiting for something, red when it has stopped because its outlet is full.
func _add_status_lamp() -> void:
	if _lamp_at.origin.y < -5.0:
		return
	_lamp = MeshInstance3D.new()
	_lamp.name = "StatusLamp"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.16, 0.06)
	_lamp.mesh = bm
	_lamp.transform = _lamp_at
	_lamp_material = StandardMaterial3D.new()
	_lamp_material.emission_enabled = true
	_lamp.material_override = _lamp_material
	_body.add_child(_lamp)
	if not state_changed.is_connected(_refresh_lamp):
		state_changed.connect(_refresh_lamp)
	_refresh_lamp(self)

func status_color() -> Color:
	if stalled:
		return Color(1.0, 0.25, 0.2)
	if not job.is_empty():
		return Color(0.35, 1.0, 0.45)
	return Color(1.0, 0.72, 0.2)

func _refresh_lamp(_m: Machine) -> void:
	if _lamp_material == null:
		return
	var c := status_color()
	_lamp_material.albedo_color = c
	_lamp_material.emission = c
	_lamp_material.emission_energy_multiplier = 2.0

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

## Spec: the intake hole is a real hole. A piece that will not go through it
## does not go in, which is what makes bucking a trunk down - or upgrading the
## machine's mouth - worth doing.
func fits(dims: Dictionary) -> bool:
	return Solid.fits_through(dims, intake_hole)

func accept_item(item: LooseItem) -> bool:
	if not can_accept(item.item_id):
		return false
	if not fits(item.dims):
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
		var duration: float = maxf(0.4, float(next.volume) / maxf(0.001, rate_m3_per_second))
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
		# Output is cut to whatever the outlet will pass, so a wider outlet
		# hands back longer, fatter pieces.
		var section := machine_def.cross_section.min(outlet_hole)
		pieces = Solid.cut_to_pieces(volume, section, machine_def.max_piece_length)

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
	return "%s lv%d: idle, mouth %.2f x %.2f m (%s)" % [
		def.display_name, level, intake_hole.x, intake_hole.y, input_summary()]

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
