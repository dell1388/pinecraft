class_name Cave
extends Node3D

## A cave: a trench cut down into the ground, a timber portal, a sloping tunnel
## and a chamber under the hill with ore in it.
##
## The land is a heightfield, which cannot have a hole with a roof over it, so
## a cave is built rather than carved. The terrain leaves out the two cells the
## trench runs through (and levels the ground round them); everything below the
## surface - walls, floors, roofs - is geometry here, and the trench walls stand
## a little proud of the cut edge so there is never a crack to see the sky
## through. The terrain only picks a spot where the hill is high enough over the
## whole footprint that the roof never pokes out of it.
##
## Local frame: origin at the top of the trench, on the ground; +Z runs into the
## hill; X is across.

const SHAFT_WIDTH := 6.0         ## one terrain cell
const SHAFT_LENGTH := 12.0       ## two terrain cells
const SHAFT_DROP := 7.0
const TUNNEL_LENGTH := 22.0
const TUNNEL_HEIGHT := 5.0
const CHAMBER_DROP := 11.0       ## chamber floor below the mouth
const CHAMBER_WIDTH := 34.0
const CHAMBER_LENGTH := 30.0
const CHAMBER_HEIGHT := 9.0
const SLAB := 0.6
const FOOTPRINT_LENGTH := SHAFT_LENGTH + TUNNEL_LENGTH + CHAMBER_LENGTH

const ROCK := Color(0.30, 0.29, 0.30)
const ROCK_DARK := Color(0.21, 0.20, 0.22)
const TIMBER := Color(0.42, 0.29, 0.17)
const CRYSTAL_COLORS := [Color(0.55, 0.40, 1.0), Color(0.30, 0.85, 0.95), Color(0.95, 0.55, 0.85)]

var cave_name: String = "Cave"
## False for a cave that opens into a cave network: the network puts a cavern
## where the chamber would be, so the entrance is only the trench, the portal
## and the sloping tunnel.
var with_chamber: bool = true
var dir: Vector3 = Vector3(0, 0, 1)
var _rng := RandomNumberGenerator.new()
var _body: StaticBody3D
var _mesh: Greeble

## Floor height, relative to the mouth, at a distance `z` in.
static func floor_at(z: float) -> float:
	if z <= SHAFT_LENGTH:
		return -SHAFT_DROP * clampf(z / SHAFT_LENGTH, 0.0, 1.0)
	if z <= SHAFT_LENGTH + TUNNEL_LENGTH:
		return lerpf(-SHAFT_DROP, -CHAMBER_DROP, (z - SHAFT_LENGTH) / TUNNEL_LENGTH)
	return -CHAMBER_DROP

## Top of the roof slab, relative to the mouth, at a distance `z` in. The
## terrain checks the hill clears this everywhere.
static func roof_at(z: float) -> float:
	if z <= SHAFT_LENGTH + TUNNEL_LENGTH:
		return floor_at(z) + TUNNEL_HEIGHT + SLAB
	return -CHAMBER_DROP + CHAMBER_HEIGHT + SLAB

## Placed at the mouth, facing `into` the hill.
func setup(entrance: Vector3, into: Vector3, p_name: String, seed_value: int) -> void:
	dir = into.normalized()
	cave_name = p_name
	_rng.seed = seed_value
	var side := Vector3(dir.z, 0.0, -dir.x)
	transform = Transform3D(Basis(side, Vector3.UP, dir), entrance)

func _ready() -> void:
	_body = StaticBody3D.new()
	_body.name = "CaveRock"
	_body.collision_layer = Layers.WORLD
	_body.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	_body.physics_material_override = pm
	add_child(_body)
	# Two meshes rather than one: renderers cap the lights on a single mesh
	# (the compatibility one at eight), and the tunnel and the chamber each
	# have about that many of their own.
	_mesh = Greeble.new()
	_build_trench()
	_build_tunnel()
	_build_surface()
	add_child(_mesh.instance("CaveMouth"))
	if with_chamber:
		_mesh = Greeble.new()
		_build_chamber()
		add_child(_mesh.instance("CaveChamber"))
	Nameplate.landmark(self, cave_name.to_upper(), 9.0, Color(0.80, 0.72, 1.0))

# --- Pieces ----------------------------------------------------------------

## A solid, drawn box: collision plus mesh.
func _solid(size: Vector3, xform: Transform3D, color: Color) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.transform = xform
	_body.add_child(cs)
	_mesh.box(size, xform, color)

## A slab whose top surface runs from (z0, y0) to (z1, y1), `width` across.
func _slope(width: float, z0: float, y0: float, z1: float, y1: float, thickness: float,
		color: Color, x: float = 0.0, up: bool = true) -> void:
	var run := Vector2(z1 - z0, y1 - y0)
	var pitch := -atan2(run.y, run.x)
	var basis := Basis(Vector3.RIGHT, pitch)
	var mid := Vector3(x, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
	# Hung below the line (a floor) or sat above it (a roof).
	mid += basis.y * (-thickness * 0.5 if up else thickness * 0.5)
	_solid(Vector3(width, thickness, run.length() + 0.05), Transform3D(basis, mid), color)

func _lamp(pos: Vector3, facing: Vector3, energy: float = 2.4, color: Color = Color(1.0, 0.78, 0.45)) -> void:
	var basis := Basis.looking_at(-facing, Vector3.UP) if absf(facing.y) < 0.9 else Basis()
	_mesh.lamp(Transform3D(basis, pos), color, 0.26)
	var light := OmniLight3D.new()
	light.position = pos + facing * 0.5
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 14.0
	light.omni_attenuation = 0.9
	light.distance_fade_enabled = true
	light.distance_fade_begin = 45.0
	light.distance_fade_length = 15.0
	add_child(light)

func _build_trench() -> void:
	var half := SHAFT_WIDTH * 0.5
	_slope(SHAFT_WIDTH + 1.6, 0.0, 0.0, SHAFT_LENGTH, -SHAFT_DROP, SLAB, ROCK_DARK)
	# The walls straddle the cut edge and stand a little proud of the ground.
	var wall_h := SHAFT_DROP + 1.6
	for sx in [-1.0, 1.0]:
		_solid(Vector3(0.8, wall_h, SHAFT_LENGTH + 0.8),
			Transform3D(Basis(), Vector3(sx * half, 0.3 - wall_h * 0.5, SHAFT_LENGTH * 0.5)), ROCK)
		# Timber shoring along the trench.
		var z := 1.5
		while z < SHAFT_LENGTH - 0.5:
			var top := 0.3
			var bottom := floor_at(z)
			_mesh.block(Vector3(0.25, top - bottom, 0.25),
				Vector3(sx * (half - 0.52), (top + bottom) * 0.5, z), TIMBER)
			z += 3.5
		# Ragged rock along the lip, so the cut does not look ruled.
		for i in 4:
			var along := 1.0 + float(i) * 3.2 + _rng.randf_range(-0.5, 0.5)
			_mesh.box(Vector3(_rng.randf_range(0.8, 1.6), _rng.randf_range(0.4, 1.0), _rng.randf_range(1.2, 2.4)),
				Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.4, 0.4)),
					Vector3(sx * (half + 0.5), 0.35, along)), ROCK.lightened(0.08))
	# Where the trench meets the tunnel: rock from the tunnel roof up past the
	# ground, closing the end of the cut.
	var roof := roof_at(SHAFT_LENGTH)
	_solid(Vector3(SHAFT_WIDTH + 1.6, 0.3 - roof + 0.4, 0.8),
		Transform3D(Basis(), Vector3(0, (0.3 + roof) * 0.5 + 0.2, SHAFT_LENGTH + 0.4)), ROCK)
	# The portal: two posts and a lintel at the tunnel mouth.
	var mouth_floor := floor_at(SHAFT_LENGTH)
	var mouth_top := mouth_floor + TUNNEL_HEIGHT
	for sx in [-1.0, 1.0]:
		_mesh.block(Vector3(0.45, TUNNEL_HEIGHT, 0.45),
			Vector3(sx * (half - 0.45), mouth_floor + TUNNEL_HEIGHT * 0.5, SHAFT_LENGTH - 0.3), TIMBER)
	_mesh.block(Vector3(SHAFT_WIDTH - 0.2, 0.5, 0.55), Vector3(0, mouth_top - 0.2, SHAFT_LENGTH - 0.3), TIMBER.darkened(0.1))
	_lamp(Vector3(half - 1.0, mouth_top - 0.9, SHAFT_LENGTH - 0.7), Vector3(0, 0, -1), 1.6)

func _build_tunnel() -> void:
	var half := SHAFT_WIDTH * 0.5
	var z0 := SHAFT_LENGTH
	var z1 := SHAFT_LENGTH + TUNNEL_LENGTH
	var y0 := floor_at(z0)
	var y1 := floor_at(z1)
	_slope(SHAFT_WIDTH + 1.6, z0, y0, z1 + 0.4, y1, SLAB, ROCK_DARK)
	_slope(SHAFT_WIDTH + 1.6, z0, y0 + TUNNEL_HEIGHT, z1, y1 + TUNNEL_HEIGHT, SLAB, ROCK, 0.0, false)
	for sx in [-1.0, 1.0]:
		var run := Vector2(z1 - z0, y1 - y0)
		var basis := Basis(Vector3.RIGHT, -atan2(run.y, run.x))
		var mid := Vector3(sx * (half + 0.4), (y0 + y1) * 0.5 + TUNNEL_HEIGHT * 0.5, (z0 + z1) * 0.5)
		_solid(Vector3(0.8, TUNNEL_HEIGHT + 1.2, run.length()), Transform3D(basis, mid), ROCK)
	# Timber sets, rails and lamps down the tunnel.
	var z := z0 + 3.0
	var n := 0
	while z < z1 - 1.0:
		var f := floor_at(z)
		for sx in [-1.0, 1.0]:
			_mesh.block(Vector3(0.3, TUNNEL_HEIGHT - 0.2, 0.3), Vector3(sx * (half - 0.2), f + TUNNEL_HEIGHT * 0.5, z), TIMBER)
		_mesh.block(Vector3(SHAFT_WIDTH - 0.2, 0.3, 0.35), Vector3(0, f + TUNNEL_HEIGHT - 0.25, z), TIMBER.darkened(0.1))
		# Lamps on alternate walls at every set, so the tunnel is a string of
		# pools of light rather than a black pipe between two of them.
		var wall := 1.0 if n % 2 == 0 else -1.0
		_lamp(Vector3(wall * (half - 0.45), f + TUNNEL_HEIGHT - 1.0, z + 0.3), Vector3(-wall, 0, 0), 2.2)
		z += 4.5
		n += 1
	for sx in [-0.55, 0.55]:
		var from := Vector3(sx, floor_at(z0 + 0.5) + 0.06, z0 + 0.5)
		var to := Vector3(sx, floor_at(z1) + 0.06, z1 + 6.0)
		_mesh.pipe(from, to, 0.06, Color(0.46, 0.44, 0.42), 4)
	var t := z0 + 1.0
	while t < z1 + 6.0:
		_mesh.block(Vector3(1.6, 0.08, 0.25), Vector3(0, floor_at(t) + 0.02, t), TIMBER.darkened(0.25))
		t += 1.0

func _build_chamber() -> void:
	var half_w := CHAMBER_WIDTH * 0.5
	var z0 := SHAFT_LENGTH + TUNNEL_LENGTH
	var z1 := z0 + CHAMBER_LENGTH
	var fy := -CHAMBER_DROP
	var ry := fy + CHAMBER_HEIGHT
	var zc := (z0 + z1) * 0.5
	_solid(Vector3(CHAMBER_WIDTH + 1.6, SLAB, CHAMBER_LENGTH + 1.6), Transform3D(Basis(), Vector3(0, fy - SLAB * 0.5, zc)), ROCK_DARK)
	_solid(Vector3(CHAMBER_WIDTH + 1.6, SLAB, CHAMBER_LENGTH + 1.6), Transform3D(Basis(), Vector3(0, ry + SLAB * 0.5, zc)), ROCK)
	for sx in [-1.0, 1.0]:
		_solid(Vector3(0.8, CHAMBER_HEIGHT, CHAMBER_LENGTH), Transform3D(Basis(), Vector3(sx * (half_w + 0.4), fy + CHAMBER_HEIGHT * 0.5, zc)), ROCK)
	_solid(Vector3(CHAMBER_WIDTH, CHAMBER_HEIGHT, 0.8), Transform3D(Basis(), Vector3(0, fy + CHAMBER_HEIGHT * 0.5, z1 + 0.4)), ROCK)
	# The near wall, with the tunnel coming through it.
	var gap := SHAFT_WIDTH * 0.5 + 0.8
	for sx in [-1.0, 1.0]:
		var w := half_w - gap
		_solid(Vector3(w, CHAMBER_HEIGHT, 0.8), Transform3D(Basis(), Vector3(sx * (gap + w * 0.5), fy + CHAMBER_HEIGHT * 0.5, z0 - 0.4)), ROCK)
	var over := CHAMBER_HEIGHT - TUNNEL_HEIGHT
	_solid(Vector3(gap * 2.0, over, 0.8), Transform3D(Basis(), Vector3(0, fy + TUNNEL_HEIGHT + over * 0.5, z0 - 0.4)), ROCK)

	# Faceted walls: slabs of rock leaning out of them, so the room reads as
	# dug out of something rather than boxed in.
	for i in 22:
		var on_side := i % 2 == 0
		var p: Vector3
		var size := Vector3(_rng.randf_range(1.0, 2.2), _rng.randf_range(2.0, 6.5), _rng.randf_range(2.0, 4.5))
		if on_side:
			var sx := -1.0 if i % 4 == 0 else 1.0
			p = Vector3(sx * (half_w - size.x * 0.3), fy + size.y * 0.5, _rng.randf_range(z0 + 3.0, z1 - 2.0))
		else:
			size = Vector3(size.z, size.y, size.x)
			p = Vector3(_rng.randf_range(-half_w + 2.0, half_w - 2.0), fy + size.y * 0.5, z1 - size.z * 0.3)
		_solid(size, Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.35, 0.35)), p),
			ROCK.lightened(_rng.randf_range(-0.05, 0.08)))

	# Pillars holding the roof up, and a raised ledge with a ramp onto it.
	for spot in [Vector3(-7, 0, zc - 3), Vector3(8, 0, zc + 5)]:
		var pillar := Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, 1.0)), Vector3(spot.x, fy, spot.z))
		var cs := CollisionShape3D.new()
		var cyl := BoxShape3D.new()
		cyl.size = Vector3(2.6, CHAMBER_HEIGHT, 2.6)
		cs.shape = cyl
		cs.transform = pillar.translated_local(Vector3(0, CHAMBER_HEIGHT * 0.5, 0))
		_body.add_child(cs)
		_mesh.prism(6, 1.9, 1.3, CHAMBER_HEIGHT, pillar, ROCK.lightened(0.04))
	var ledge := Vector3(half_w - 5.0, fy + 0.8, z1 - 6.0)
	_solid(Vector3(8.0, 1.6, 10.0), Transform3D(Basis(), ledge), ROCK.lightened(0.02))
	_slope(3.0, z1 - 16.0, fy, z1 - 11.0, fy + 1.6, 0.5, ROCK_DARK, half_w - 5.0)

	# Stalagmites and stalactites.
	for i in 18:
		var x := _rng.randf_range(-half_w + 1.5, half_w - 1.5)
		var z := _rng.randf_range(z0 + 2.0, z1 - 1.5)
		if absf(x) < 4.0 and z < z0 + 8.0:
			continue
		var h := _rng.randf_range(0.8, 2.6)
		if i % 2 == 0:
			_mesh.prism(5, _rng.randf_range(0.3, 0.7), 0.0, h, Transform3D(Basis(Vector3.UP, _rng.randf()), Vector3(x, fy, z)), ROCK.lightened(0.1))
		else:
			_mesh.prism(5, _rng.randf_range(0.3, 0.6), 0.0, h, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(x, ry, z)), ROCK.lightened(0.05))

	# Crystals, which light the place.
	for i in 6:
		var color: Color = CRYSTAL_COLORS[i % CRYSTAL_COLORS.size()]
		var sx := -1.0 if i % 2 == 0 else 1.0
		var at := Vector3(sx * (half_w - 1.2), fy, lerpf(z0 + 4.0, z1 - 3.0, float(i) / 5.0))
		for k in 4:
			var tilt := Basis(Vector3.FORWARD, _rng.randf_range(-0.5, 0.5)) * Basis(Vector3.RIGHT, _rng.randf_range(-0.4, 0.4))
			_mesh.prism(6, _rng.randf_range(0.15, 0.3), 0.0, _rng.randf_range(0.8, 2.0),
				Transform3D(tilt, at + Vector3(_rng.randf_range(-0.6, 0.6), 0, _rng.randf_range(-0.6, 0.6))), color, true)
		if i % 3 == 2:
			continue          # every crystal glows; not every one needs a light
		var light := OmniLight3D.new()
		light.position = at + Vector3(-sx * 1.2, 1.4, 0)
		light.light_color = color
		light.light_energy = 2.6
		light.omni_range = 14.0
		light.distance_fade_enabled = true
		light.distance_fade_begin = 50.0
		light.distance_fade_length = 15.0
		add_child(light)
	# A mine cart where the rails end, and lamps on the walls.
	var cart := Transform3D(Basis(), Vector3(0, fy + 0.55, z0 + 4.5))
	_mesh.box(Vector3(1.4, 0.8, 2.0), cart, Color(0.36, 0.33, 0.30))
	_mesh.box(Vector3(1.2, 0.2, 1.8), cart.translated_local(Vector3(0, 0.35, 0)), Color(0.55, 0.42, 0.22))
	for sx in [-0.6, 0.6]:
		for sz in [-0.65, 0.65]:
			_mesh.pipe(Vector3(sx - 0.1, fy + 0.2, z0 + 4.5 + sz), Vector3(sx + 0.1, fy + 0.2, z0 + 4.5 + sz), 0.2, Color(0.2, 0.2, 0.2), 6)
	for p in [Vector3(-half_w + 0.2, ry - 2.0, z0 + 8.0), Vector3(half_w - 0.2, ry - 2.0, z0 + 16.0),
			Vector3(-half_w + 0.2, ry - 2.0, z1 - 6.0)]:
		_lamp(p, Vector3(-signf(p.x), 0, 0), 2.6)

## Above ground: a craggy outcrop over the portal, so the mouth is a place you
## can see from a distance, and a signpost.
func _build_surface() -> void:
	for i in 7:
		var size := Vector3(_rng.randf_range(3.0, 6.0), _rng.randf_range(2.5, 6.0), _rng.randf_range(3.0, 5.0))
		var x := _rng.randf_range(-7.0, 7.0)
		var z := SHAFT_LENGTH + _rng.randf_range(0.5, 6.0)
		_solid(size, Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.5, 0.5)) * Basis(Vector3.RIGHT, _rng.randf_range(-0.15, 0.15)),
			Vector3(x, size.y * 0.5 - 0.3, z + size.z * 0.5)), Color(0.44, 0.43, 0.45).lightened(_rng.randf_range(-0.05, 0.06)))
	var post := Vector3(-SHAFT_WIDTH * 0.5 - 2.0, 0, -1.5)
	_mesh.block(Vector3(0.2, 2.4, 0.2), post + Vector3(0, 1.2, 0), TIMBER)
	_mesh.block(Vector3(1.8, 0.7, 0.12), post + Vector3(0, 2.1, 0), TIMBER.lightened(0.15))
	_lamp(Vector3(SHAFT_WIDTH * 0.5 + 0.9, 1.6, 0.4), Vector3(0, 0, -1), 0.8)

# --- Queries ---------------------------------------------------------------

## A spot on the chamber floor, for the ore field. Local x and z.
func chamber_point(rng: RandomNumberGenerator) -> Vector3:
	var z0 := SHAFT_LENGTH + TUNNEL_LENGTH
	var x := rng.randf_range(-CHAMBER_WIDTH * 0.5 + 3.0, CHAMBER_WIDTH * 0.5 - 3.0)
	var z := rng.randf_range(z0 + 7.0, z0 + CHAMBER_LENGTH - 3.0)
	return to_global(Vector3(x, -CHAMBER_DROP, z))

## How far underground a point is, 0 at the surface to 1 in the tunnel and
## beyond. Drives the darkness when the player goes in.
func depth_factor(point: Vector3) -> float:
	var local := to_local(point)
	if absf(local.x) > CHAMBER_WIDTH * 0.5 + 1.0 or local.z < 0.0 or local.z > FOOTPRINT_LENGTH + 1.0:
		return 0.0
	if local.y > 1.5 or local.y < -CHAMBER_DROP - 2.0:
		return 0.0
	if local.z < SHAFT_LENGTH + TUNNEL_LENGTH and absf(local.x) > SHAFT_WIDTH * 0.5 + 0.5:
		return 0.0
	if not with_chamber and local.z > SHAFT_LENGTH + TUNNEL_LENGTH + 2.0:
		return 0.0
	return clampf((local.z - 3.0) / (SHAFT_LENGTH + 2.0), 0.0, 1.0)
