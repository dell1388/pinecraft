class_name VehicleModel
extends RefCounted

## Each part a millimetre proud of the last, so flush parts never z-fight.
const LAYER := 0.001

## Dresses a vehicle from its spec: cab, bed, wheels and all the little parts.
## Mesh only - the colliders are the vehicle's own, built from the same
## numbers, so the dressing and the physics cannot disagree about where a wall
## is. Everything on the hull is one merged Greeble mesh; the parts that move
## (tailgate, dump tub, wheels) are their own nodes.

const DARK := Color(0.14, 0.14, 0.15)
const STEEL := Color(0.60, 0.61, 0.64)
const GLASS := Color(0.22, 0.32, 0.40)
const WOOD := Color(0.46, 0.34, 0.22)
const AMBER := Color(1.0, 0.62, 0.15)
const HEADLIGHT := Color(1.0, 0.95, 0.75)
const TAIL := Color(1.0, 0.15, 0.1)

static func dress(v: Hauler) -> void:
	var g := Greeble.new()
	g.layer_step = LAYER
	match v.style:
		&"quad":
			_quad(v, g)
		&"buggy":
			_buggy(v, g)
		_:
			_truck(v, g)
	match v.bed_kind:
		&"sides", &"rack":
			_walled_bed(v, g)
		&"stakes":
			_stake_bed(v, g)
		&"tub":
			_tub(v)
	var gear: Variant = v.spec.get("rig", null)
	if gear is Dictionary and bool(gear.get("mast", false)):
		_mast(v, g, Hauler._vec(gear.get("head", [0, 3, -1])))
	v.add_child(g.instance("Body"))
	_wheels(v)

# --- Bodies ----------------------------------------------------------------

static func _truck(v: Hauler, g: Greeble) -> void:
	var size := v.body_size
	var paint := v.paint
	var top := size.y * 0.5
	g.block(size, Vector3.ZERO, paint)
	for side in [-1.0, 1.0]:
		g.block(Vector3(0.1, 0.18, size.z - 0.4), Vector3(side * (size.x * 0.5 + 0.03), -top + 0.15, 0), DARK)
	# The cab: body, glass, roof, a light bar, door lines and mirrors.
	var cab_spec: Dictionary = v.spec.get("cab", {})
	var cab_size := Hauler._vec(cab_spec.get("size", [2.3, 0.95, 1.5]))
	var cab := Vector3(0, top + cab_size.y * 0.5, float(cab_spec.get("z", -1.55)))
	var hx := cab_size.x * 0.5
	var hz := cab_size.z * 0.5
	g.block(cab_size, cab, paint.darkened(0.08))
	g.block(Vector3(cab_size.x + 0.06, 0.1, cab_size.z + 0.06), cab + Vector3(0, cab_size.y * 0.5 + 0.02, 0), paint.darkened(0.25))
	g.block(Vector3(cab_size.x - 0.3, cab_size.y * 0.5, 0.06), cab + Vector3(0, cab_size.y * 0.22, -hz - 0.01), GLASS)
	g.block(Vector3(cab_size.x - 0.4, cab_size.y * 0.35, 0.06), cab + Vector3(0, cab_size.y * 0.25, hz + 0.01), GLASS)
	for side in [-1.0, 1.0]:
		g.block(Vector3(0.06, cab_size.y * 0.45, cab_size.z * 0.7), cab + Vector3(side * (hx + 0.01), cab_size.y * 0.22, 0.02), GLASS)
		g.block(Vector3(0.05, cab_size.y * 0.9, 0.04), cab + Vector3(side * (hx + 0.01), -0.02, hz * 0.8), paint.darkened(0.35))
		g.block(Vector3(0.12, 0.05, 0.05), cab + Vector3(side * (hx + 0.01), -cab_size.y * 0.1, hz * 0.4), STEEL)
		g.block(Vector3(0.3, 0.05, 0.05), cab + Vector3(side * (hx + 0.14), cab_size.y * 0.2, -hz + 0.1), DARK)
		g.block(Vector3(0.06, 0.28, 0.18), cab + Vector3(side * (hx + 0.29), cab_size.y * 0.2, -hz + 0.1), DARK)
	var lights := maxi(2, int(cab_size.x / 0.5))
	for i in lights:
		var x := -hx + 0.3 + (cab_size.x - 0.6) * float(i) / float(lights - 1)
		g.box(Vector3(0.24, 0.1, 0.14), Transform3D(Basis(), cab + Vector3(x, cab_size.y * 0.5 + 0.12, -hz + 0.25)), AMBER, true)
	g.block(Vector3(cab_size.x - 0.4, 0.06, 0.2), cab + Vector3(0, cab_size.y * 0.5 + 0.07, -hz + 0.25), DARK)
	# Front: grille, bumper, headlights. Back: tail lights and a step.
	var nose := -size.z * 0.5
	g.vent(size.x * 0.5, size.y * 0.6, Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.05, nose)), Color(0.35, 0.35, 0.37), 5)
	g.block(Vector3(size.x + 0.1, 0.22, 0.22), Vector3(0, -top + 0.07, nose - 0.08), STEEL)
	for side in [-1.0, 1.0]:
		g.block(Vector3(0.32, 0.2, 0.08), Vector3(side * (size.x * 0.5 - 0.35), 0.1, nose - 0.03), HEADLIGHT, true)
		g.block(Vector3(0.24, 0.16, 0.06), Vector3(side * (size.x * 0.5 - 0.25), 0.05, -nose + 0.03), TAIL, true)
	g.block(Vector3(1.2, 0.08, 0.3), Vector3(0, -top + 0.05, -nose + 0.1), STEEL)
	# An exhaust stack behind the cab, and a fuel tank under the door.
	var stack := Vector3(hx - 0.2, top, cab.z + hz + 0.1)
	g.pipe(stack, stack + Vector3(0, cab_size.y + 0.9, 0), 0.08, STEEL.darkened(0.2), 6)
	g.prism(6, 0.1, 0.1, 0.2, Transform3D(Basis(Vector3.FORWARD, 0.4), stack + Vector3(0, cab_size.y + 0.9, 0)), DARK)
	g.pipe(Vector3(-size.x * 0.5 - 0.05, -top + 0.25, cab.z - 0.3), Vector3(-size.x * 0.5 - 0.05, -top + 0.25, cab.z + 0.4), 0.2, STEEL, 8)
	_mudguards(v, g)

static func _quad(v: Hauler, g: Greeble) -> void:
	var size := v.body_size
	var paint := v.paint
	var top := size.y * 0.5
	# A frame, a fuel tank you straddle, a seat and handlebars.
	g.block(Vector3(size.x * 0.6, size.y, size.z), Vector3.ZERO, DARK)
	g.block(Vector3(size.x * 0.75, 0.3, 0.8), Vector3(0, top + 0.15, -0.45), paint)
	g.block(Vector3(size.x * 0.55, 0.16, 0.9), Vector3(0, top + 0.12, 0.15), Color(0.12, 0.12, 0.13))
	g.pipe(Vector3(0, top + 0.3, -0.7), Vector3(0, top + 0.6, -0.8), 0.04, DARK, 6)
	g.pipe(Vector3(-0.42, top + 0.62, -0.8), Vector3(0.42, top + 0.62, -0.8), 0.03, STEEL, 6)
	for side in [-1.0, 1.0]:
		g.block(Vector3(0.1, 0.06, 0.06), Vector3(side * 0.46, top + 0.62, -0.8), DARK)
		# Big plastic fenders over every wheel.
		for z in [-0.72, 0.72]:
			g.block(Vector3(0.4, 0.08, 0.8), Vector3(side * 0.55, top + 0.12, z), paint.darkened(0.1))
			g.block(Vector3(0.4, 0.2, 0.08), Vector3(side * 0.55, top + 0.02, z - 0.4 * signf(z)), paint.darkened(0.1))
	for side in [-1.0, 1.0]:
		g.block(Vector3(0.16, 0.1, 0.06), Vector3(side * 0.18, top + 0.15, -0.87), HEADLIGHT, true)
	g.block(Vector3(0.3, 0.08, 0.04), Vector3(0, top + 0.05, size.z * 0.5 + 0.02), TAIL, true)
	g.block(Vector3(size.x * 0.9, 0.08, 0.1), Vector3(0, -top + 0.1, -size.z * 0.5 - 0.05), STEEL)

static func _buggy(v: Hauler, g: Greeble) -> void:
	var size := v.body_size
	var paint := v.paint
	var top := size.y * 0.5
	# Floor pan, a wedge nose, an engine at the back and two bucket seats.
	g.block(size, Vector3.ZERO, DARK)
	g.wedge(Vector3(size.x * 0.8, 0.35, 0.9), Transform3D(Basis(Vector3.UP, PI), Vector3(0, top, -size.z * 0.5 + 0.45)), paint)
	g.block(Vector3(size.x * 0.7, 0.5, 0.9), Vector3(0, top + 0.25, size.z * 0.5 - 0.5), Color(0.3, 0.3, 0.32))
	g.vent(size.x * 0.5, 0.3, Transform3D(Basis(), Vector3(0, top + 0.3, size.z * 0.5 - 0.04)), DARK, 4)
	for side in [-1.0, 1.0]:
		g.block(Vector3(0.5, 0.5, 0.12), Vector3(side * 0.35, top + 0.35, 0.45), Color(0.12, 0.12, 0.13))
		g.block(Vector3(0.5, 0.1, 0.5), Vector3(side * 0.35, top + 0.1, 0.2), Color(0.12, 0.12, 0.13))
		g.block(Vector3(0.14, 0.1, 0.06), Vector3(side * 0.5, top + 0.12, -size.z * 0.5 + 0.02), HEADLIGHT, true)
		g.block(Vector3(0.16, 0.1, 0.05), Vector3(side * 0.6, top + 0.2, size.z * 0.5 + 0.02), TAIL, true)
	# Roll cage: four uprights, hoops over the top, and a light bar.
	var cage := 1.15
	var front := -0.55
	var back := 0.75
	var hw := size.x * 0.45
	var c := paint.lightened(0.1)
	for x in [-hw, hw]:
		g.pipe(Vector3(x, top, front - 0.2), Vector3(x * 0.85, top + cage, front + 0.1), 0.05, c, 6)
		g.pipe(Vector3(x, top, back), Vector3(x * 0.85, top + cage, back), 0.05, c, 6)
		g.pipe(Vector3(x * 0.85, top + cage, front + 0.1), Vector3(x * 0.85, top + cage, back), 0.05, c, 6)
	# The hoops a hair thinner than the uprights, so where they meet the two
	# never share a face.
	g.pipe(Vector3(-hw * 0.85, top + cage, front + 0.1), Vector3(hw * 0.85, top + cage, front + 0.1), 0.046, c, 6)
	g.pipe(Vector3(-hw * 0.85, top + cage, back), Vector3(hw * 0.85, top + cage, back), 0.046, c, 6)
	g.pipe(Vector3(-hw * 0.85, top + cage, back), Vector3(hw * 0.85, top + 0.2, back), 0.04, c, 6)
	for i in 4:
		g.box(Vector3(0.2, 0.1, 0.1), Transform3D(Basis(), Vector3(-0.45 + float(i) * 0.3, top + cage + 0.08, front + 0.1)), AMBER, true)
	# Spare wheel on the engine cover.
	g.prism(10, v.wheel_radius * 0.8, v.wheel_radius * 0.8, 0.22, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, top + 0.5, size.z * 0.5 - 0.1)), Color(0.10, 0.10, 0.11))
	_mudguards(v, g)

static func _mudguards(v: Hauler, g: Greeble) -> void:
	for offset in v.wheel_offsets:
		var o: Vector3 = offset
		var x: float = o.x + signf(o.x) * 0.12
		g.box(Vector3(v.wheel_width + 0.16, 0.08, v.wheel_radius * 2.3), Transform3D(Basis(), Vector3(x, o.y + v.wheel_radius + 0.12, o.z)), DARK)

# --- Beds ------------------------------------------------------------------

## Boards, slatted sides on stake posts (or a light rail frame on a rack), a
## headboard with a cab guard, and a tailgate on hinges.
static func _walled_bed(v: Hauler, g: Greeble) -> void:
	var rack := v.bed_kind == &"rack"
	var paint := v.paint
	var t := 0.12 if rack else 0.3
	var boards := maxi(2, int(v.bed_length / 0.5))
	for i in boards:
		var z := v.bed_front + (float(i) + 0.5) * v.bed_length / float(boards)
		g.block(Vector3(v.bed_half_width * 2.0, 0.05, v.bed_length / float(boards) - 0.04), Vector3(0, v.bed_floor + 0.025, z), DARK if rack else WOOD)
	var wall_mid := v.bed_floor + v.wall_height * 0.5
	for side in [-1.0, 1.0]:
		var x: float = side * (v.bed_half_width + t * 0.5)
		if rack:
			g.pipe(Vector3(x, v.bed_floor + v.wall_height, v.bed_front), Vector3(x, v.bed_floor + v.wall_height, v.bed_back), 0.03, STEEL, 6)
			for z in [v.bed_front, v.bed_mid_z, v.bed_back]:
				g.pipe(Vector3(x, v.bed_floor, z), Vector3(x, v.bed_floor + v.wall_height, z), 0.025, STEEL, 6)
			continue
		var slats := maxi(1, int(v.wall_height / 0.34))
		for k in slats:
			var y := v.bed_floor + 0.2 + float(k) * (v.wall_height - 0.2) / float(maxi(1, slats))
			g.block(Vector3(t, 0.26, v.bed_length + 0.1), Vector3(x, minf(y, v.bed_floor + v.wall_height - 0.13), v.bed_mid_z), paint.darkened(0.15))
		var posts := maxi(2, int(v.bed_length / 0.8) + 1)
		for k in posts:
			var z := v.bed_front + float(k) * v.bed_length / float(posts - 1)
			g.block(Vector3(t + 0.06, v.wall_height + 0.06, 0.12), Vector3(x, wall_mid + 0.03, z), DARK)
		g.block(Vector3(t + 0.08, 0.08, v.bed_length + 0.3), Vector3(x, v.bed_floor + v.wall_height + 0.02, v.bed_mid_z), STEEL)
		g.rivets(Vector3(x + side * (t * 0.5 + 0.01), v.bed_floor + v.wall_height - 0.12, v.bed_front + 0.2),
			Vector3(x + side * (t * 0.5 + 0.01), v.bed_floor + v.wall_height - 0.12, v.bed_back - 0.2), maxi(3, int(v.bed_length * 3.3)), STEEL, 0.04)
	# Headboard: a solid lower panel, and a steel grille above if it stands
	# taller than the sides.
	var head_z := v.bed_front - 0.12
	var across := v.bed_half_width * 2.0 + t * 2.0
	var solid := minf(v.wall_height, v.headboard_height)
	g.block(Vector3(across, solid, 0.24), Vector3(0, v.bed_floor + solid * 0.5, head_z), DARK if rack else paint.darkened(0.2))
	if v.headboard_height > v.wall_height + 0.05:
		var top := v.bed_floor + v.headboard_height
		g.block(Vector3(across, 0.1, 0.26), Vector3(0, top - 0.05, head_z), STEEL)
		var bars := maxi(3, int(across / 0.4))
		for k in bars:
			var x := -v.bed_half_width + float(k) * v.bed_half_width * 2.0 / float(bars - 1)
			g.block(Vector3(0.05, v.headboard_height - v.wall_height, 0.05), Vector3(x, v.bed_floor + (v.wall_height + v.headboard_height) * 0.5, head_z), STEEL.darkened(0.1))
		for sx in [-1.0, 1.0]:
			g.block(Vector3(0.14, v.headboard_height, 0.26), Vector3(sx * (v.bed_half_width + t - 0.07), v.bed_floor + v.headboard_height * 0.5, head_z), DARK)

	# The tailgate, hinged along its bottom edge.
	var gate := Greeble.new()
	gate.layer_step = LAYER
	gate.layer_base = LAYER * 0.5
	gate.block(Vector3(across, v.wall_height, 0.24 if not rack else 0.08), Vector3(0, v.wall_height * 0.5, 0), DARK if rack else paint.darkened(0.15))
	if not rack:
		gate.block(Vector3(across + 0.04, 0.08, 0.28), Vector3(0, v.wall_height - 0.04, 0), STEEL)
		for sx in [-1.0, 1.0]:
			gate.block(Vector3(0.1, 0.16, 0.06), Vector3(sx * (across * 0.5 - 0.3), v.wall_height * 0.6, 0.15), DARK)
			gate.block(Vector3(0.2, 0.14, 0.14), Vector3(sx * (across * 0.5 - 0.3), 0.07, 0.0), DARK)
	v._tailgate_mesh = gate.instance("Tailgate")
	v._tailgate_mesh.position = Vector3(0, v.bed_floor, v.bed_back + 0.12)
	v.add_child(v._tailgate_mesh)

## Bolsters across the deck and tall steel stakes, with a big cab guard - a
## bed for whole trunks, open at the back.
static func _stake_bed(v: Hauler, g: Greeble) -> void:
	var top := v.bed_floor + v.wall_height
	g.block(Vector3(v.bed_half_width * 2.0, 0.04, v.bed_length), Vector3(0, v.bed_floor + 0.02, v.bed_mid_z), DARK)
	for z in v.stake_positions():
		g.block(Vector3(v.bed_half_width * 2.0 + 0.4, 0.16, 0.22), Vector3(0, v.bed_floor + 0.08, z), STEEL.darkened(0.25))
		for side in [-1.0, 1.0]:
			var x: float = side * (v.bed_half_width + 0.09)
			g.block(Vector3(0.18, v.wall_height, 0.18), Vector3(x, v.bed_floor + v.wall_height * 0.5, z), DARK)
			g.block(Vector3(0.2, 0.2, 0.2), Vector3(x, top - 0.1, z), v.paint)
	var head_z := v.bed_front - 0.15
	var across := v.bed_half_width * 2.0 + 0.5
	g.frame(Vector3(across, v.headboard_height, 0.3), Transform3D(Basis(), Vector3(0, v.bed_floor + v.headboard_height * 0.5, head_z)), 0.14, DARK)
	var bars := 8
	for k in bars:
		var x := -across * 0.5 + 0.2 + (across - 0.4) * float(k) / float(bars - 1)
		g.block(Vector3(0.06, v.headboard_height - 0.2, 0.06), Vector3(x, v.bed_floor + v.headboard_height * 0.5, head_z), STEEL)
	g.block(Vector3(across, 0.1, 0.32), Vector3(0, v.bed_floor + v.headboard_height * 0.55, head_z), v.paint)
	# Chain boxes along the chassis.
	for side in [-1.0, 1.0]:
		g.block(Vector3(0.25, 0.3, 0.8), Vector3(side * (v.body_size.x * 0.5 + 0.1), 0.0, v.bed_mid_z), DARK)

## The dump tub: its own node, so it swings up on its hinge with the colliders.
static func _tub(v: Hauler) -> void:
	var g := Greeble.new()
	g.layer_step = LAYER
	g.layer_base = LAYER * 0.5
	var paint := v.paint
	var across := v.bed_half_width * 2.0 + 0.4
	var run := v.bed_length + 0.3
	var mid := v.bed_mid_z
	g.block(Vector3(across, 0.15, run), Vector3(0, v.bed_floor - 0.075, mid), paint.darkened(0.3))
	for side in [-1.0, 1.0]:
		var x: float = side * (v.bed_half_width + 0.1)
		g.block(Vector3(0.2, v.wall_height, run), Vector3(x, v.bed_floor + v.wall_height * 0.5, mid), paint)
		# Ribs down the outside of the tub.
		for k in 5:
			var z := v.bed_front + 0.2 + (v.bed_length - 0.4) * float(k) / 4.0
			g.block(Vector3(0.1, v.wall_height, 0.14), Vector3(x + side * 0.14, v.bed_floor + v.wall_height * 0.5, z), paint.darkened(0.2))
		g.block(Vector3(0.28, 0.12, run + 0.1), Vector3(x + side * 0.05, v.bed_floor + v.wall_height, mid), paint.darkened(0.2))
	var head_z := v.bed_front - 0.12
	g.block(Vector3(across, v.headboard_height, 0.24), Vector3(0, v.bed_floor + v.headboard_height * 0.5, head_z), paint)
	# The cab protector: a canopy reaching forward over the cab roof.
	g.block(Vector3(across, 0.1, 1.3), Vector3(0, v.bed_floor + v.headboard_height, head_z - 0.55), paint.darkened(0.15))
	g.block(Vector3(across, v.wall_height, 0.2), Vector3(0, v.bed_floor + v.wall_height * 0.5, v.bed_back + 0.1), paint.darkened(0.1))
	g.block(Vector3(across + 0.04, 0.1, 0.24), Vector3(0, v.bed_floor + v.wall_height, v.bed_back + 0.1), STEEL)
	v._tub_mesh = g.instance("Tub")
	v.add_child(v._tub_mesh)

## The crane truck's mast: a pedestal behind the cab and a column. The boom
## itself is the working one (see VehicleRig), folded back over the bed.
static func _mast(v: Hauler, g: Greeble, head: Vector3) -> void:
	var base := Vector3(0, v.body_size.y * 0.5, head.z)
	g.prism(8, 0.55, 0.5, 0.35, Transform3D(Basis(), base), STEEL.darkened(0.3))
	g.block(Vector3(0.6, head.y - base.y, 0.6), base + Vector3(0, (head.y - base.y) * 0.5 + 0.35, 0), Color(0.95, 0.78, 0.15))
	g.block(Vector3(0.5, 0.5, 0.5), head + Vector3(0, 0.2, 0), DARK)
	g.pipe(base + Vector3(0, 0.8, 0.1), head + Vector3(0, -0.1, 0.9), 0.1, STEEL, 6)
	for side in [-1.0, 1.0]:
		# Outriggers folded against the chassis.
		g.block(Vector3(0.3, 0.3, 0.9), Vector3(side * (v.body_size.x * 0.5 + 0.15), 0.0, head.z), DARK)
		g.block(Vector3(0.3, 0.06, 0.3), Vector3(side * (v.body_size.x * 0.5 + 0.15), -0.35, head.z + 0.3), STEEL)
	g.block(Vector3(0.8, 0.9, 0.3), Vector3(0, v.bed_floor + 1.0, v.bed_back - 0.2), DARK)

# --- Wheels ----------------------------------------------------------------

static func _wheels(v: Hauler) -> void:
	var mesh := wheel_mesh(v.wheel_radius, v.wheel_width)
	for offset in v.wheel_offsets:
		var o: Vector3 = offset
		var wheel := MeshInstance3D.new()
		wheel.mesh = mesh
		wheel.position = Vector3(o.x + signf(o.x) * 0.12, o.y, o.z)
		# The wheel mesh stands on Y; a wheel spins about X.
		wheel.rotation = Vector3(0, 0, PI * 0.5)
		v.add_child(wheel)
		v._wheels.append(wheel)

## A tyre with a tread, a rim and lug nuts, so you can see it turn.
static func wheel_mesh(radius: float, width: float) -> ArrayMesh:
	var g := Greeble.new()
	g.layer_step = LAYER
	var half := width * 0.5
	var base := Transform3D(Basis(), Vector3(0, -half, 0))
	g.prism(12, radius, radius, width, base, Color(0.10, 0.10, 0.11))
	for i in 12:
		var a := TAU * (float(i) + 0.5) / 12.0
		g.box(Vector3(0.1, width * 0.9, 0.06), Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a), 0, sin(a)) * (radius + 0.01)), Color(0.07, 0.07, 0.08))
	for s in [-1.0, 1.0]:
		g.prism(8, radius * 0.5, radius * 0.45, 0.04, Transform3D(Basis(), Vector3(0, s * half, 0)).rotated_local(Vector3.RIGHT, 0.0 if s > 0 else PI), Color(0.72, 0.72, 0.75))
		for k in 5:
			var a := TAU * float(k) / 5.0
			g.block(Vector3(0.05, 0.05, 0.05), Vector3(cos(a) * radius * 0.3, s * (half + 0.05), sin(a) * radius * 0.3), Color(0.35, 0.35, 0.37))
	return g.commit()
