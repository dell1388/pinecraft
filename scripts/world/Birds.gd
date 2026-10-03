class_name Birds
extends Node3D

## Birds in the sky, only for the look: a few flocks of small dark birds
## wheeling over the country round you, a pair of gulls along the water, and
## a hawk circling high up. They keep their distance, take no notice of
## anything, and go to roost at night.
##
## All of them are one MultiMesh (one draw); their wings flap in the vertex
## shader, each bird at its own pace, gliding between bursts. Each frame moves
## a few dozen points, which is nothing.

## [birds in the flock, kind (0 small, 1 gull, 2 hawk), size, height above ground from..to]
const FLOCKS := [
	[9, 0, 1.0, Vector2(16, 34)],
	[7, 0, 1.0, Vector2(20, 40)],
	[11, 0, 0.9, Vector2(14, 30)],
	[2, 1, 1.9, Vector2(12, 24)],
	[1, 2, 3.2, Vector2(55, 80)],
]
## How far from you the flocks roam, and where they are sent back.
const ROAM := Vector2(40.0, 190.0)
const LEASH := 320.0

var terrain: Terrain
## Whoever they roam round (the player); the camera if not set.
var focus: Node3D
var enabled: bool = true

var _mmi: MultiMeshInstance3D
var _flocks: Array = []
var _birds: Array = []
var _rng := RandomNumberGenerator.new()

class Bird:
	var flock: int
	var pos: Vector3
	var vel: Vector3
	var offset: Vector3       ## its place in the flock
	var phase: float
	var flap: float = 1.0
	var kind: int
	var size: float

class Flock:
	var centre: Vector3
	var target: Vector3
	var speed: float
	var height: Vector2
	var kind: int
	var circle: float = 0.0   ## a hawk's circling angle
	var retarget: float = 0.0

func setup(p_terrain: Terrain) -> void:
	terrain = p_terrain
	_rng.seed = 5150

func set_enabled(on: bool) -> void:
	enabled = on
	if _mmi != null:
		_mmi.visible = on

func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _bird_mesh()
	var total := 0
	for f in FLOCKS:
		total += int(f[0])
	mm.instance_count = total
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Flocks"
	_mmi.multimesh = mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SHADER
	mat.shader = shader
	_mmi.material_override = mat
	# They move about all round you: never cull the lot by a stale box.
	_mmi.custom_aabb = AABB(Vector3(-5000, -500, -5000), Vector3(10000, 2000, 10000))
	add_child(_mmi)
	var at := _around()
	for fi in FLOCKS.size():
		var spec: Array = FLOCKS[fi]
		var f := Flock.new()
		f.kind = int(spec[1])
		f.height = spec[3]
		f.speed = 11.0 if f.kind == 0 else (8.0 if f.kind == 1 else 6.0)
		f.centre = _pick(at, f)
		f.target = _pick(at, f)
		f.circle = _rng.randf() * TAU
		_flocks.append(f)
		for k in int(spec[0]):
			var b := Bird.new()
			b.flock = fi
			b.kind = f.kind
			b.size = float(spec[2]) * _rng.randf_range(0.85, 1.15)
			b.offset = Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-2, 2), _rng.randf_range(-6, 6)) \
				* (0.4 if f.kind == 1 else 1.0)
			b.pos = f.centre + b.offset
			b.vel = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * f.speed
			b.phase = _rng.randf()
			_birds.append(b)
	_mmi.visible = enabled

## Where they roam round: the player, or the camera.
func _around() -> Vector3:
	if focus != null and is_instance_valid(focus):
		return focus.global_position
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_position if cam != null else Vector3.ZERO

## A place for a flock to head for: out round you, at its height over the ground.
func _pick(at: Vector3, f: Flock) -> Vector3:
	var a := _rng.randf() * TAU
	var d := _rng.randf_range(ROAM.x, ROAM.y)
	var p := at + Vector3(cos(a) * d, 0, sin(a) * d)
	if f.kind == 1 and terrain != null:
		# Gulls keep to the water where there is some near.
		for i in 6:
			var q := at + Vector3(cos(a + float(i)) * d, 0, sin(a + float(i)) * d)
			if terrain.water_depth(q.x, q.z) > 0.5:
				p = q
				break
	return Vector3(p.x, _ground(p.x, p.z) + _rng.randf_range(f.height.x, f.height.y), p.z)

func _ground(x: float, z: float) -> float:
	if terrain == null:
		return 0.0
	var h := terrain.height_at(x, z)
	return maxf(h if not is_nan(h) else 0.0, Terrain.WATER_LEVEL)

## Microseconds spent this frame (read by the perf harness).
static var spent_usec: int = 0

func _process(delta: float) -> void:
	var t_in := Time.get_ticks_usec()
	_fly(delta)
	spent_usec += Time.get_ticks_usec() - t_in

func _fly(delta: float) -> void:
	if not enabled or _mmi == null:
		return
	# Gone to roost at night.
	var world := get_parent()
	var dark := float(world.get("night")) if world != null and world.get("night") != null else 0.0
	_mmi.visible = dark < 0.6
	if not _mmi.visible:
		return
	delta = minf(delta, 0.1)
	var at := _around()
	for f: Flock in _flocks:
		_steer_flock(f, at, delta)
	var mm := _mmi.multimesh
	for i in _birds.size():
		var b: Bird = _birds[i]
		var f: Flock = _flocks[b.flock]
		var want: Vector3
		if f.kind == 2:
			# The hawk rides the air in wide slow circles.
			want = f.centre + Vector3(cos(f.circle) * 38.0, sin(f.circle * 0.5) * 3.0, sin(f.circle) * 38.0)
		else:
			var swirl := Basis(Vector3.UP, Time.get_ticks_msec() * 0.0004 + b.phase * TAU)
			want = f.centre + swirl * b.offset
		var steer := (want - b.pos)
		var top := f.speed * (1.25 if f.kind == 0 else 1.1)
		b.vel = b.vel.lerp(steer.limit_length(1.0) * top, clampf(delta * (1.6 if f.kind != 2 else 0.8), 0.0, 1.0))
		if b.vel.length() < f.speed * 0.6:
			b.vel = b.vel.normalized() * f.speed * 0.6 if b.vel.length() > 0.01 else Vector3.FORWARD * f.speed * 0.6
		b.pos += b.vel * delta
		# Flap climbing, glide coming down.
		var climb := b.vel.y / maxf(0.1, b.vel.length())
		var want_flap := clampf(0.55 + climb * 2.5, 0.12, 1.0) if f.kind == 0 else clampf(0.25 + climb * 2.0, 0.05, 0.8)
		b.flap = lerpf(b.flap, want_flap, clampf(delta * 2.0, 0.0, 1.0))
		var fwd := b.vel.normalized()
		if absf(fwd.y) > 0.95:
			fwd = Vector3(fwd.x, signf(fwd.y) * 0.95, fwd.z).normalized()
		var bank := clampf(fwd.cross(steer.normalized()).y * 0.8, -0.7, 0.7)
		var basis := Basis.looking_at(fwd, Vector3.UP) * Basis(Vector3.FORWARD, bank)
		mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * b.size), b.pos))
		var beat := 13.0 if b.kind == 0 else (6.0 if b.kind == 1 else 3.5)
		mm.set_instance_custom_data(i, Color(b.phase, b.flap, float(b.kind) * 0.5, beat))

func _steer_flock(f: Flock, at: Vector3, delta: float) -> void:
	f.retarget -= delta
	if f.kind == 2:
		f.circle += delta * 0.16
	var to := f.target - f.centre
	var far := Vector2(f.centre.x - at.x, f.centre.z - at.z).length()
	if to.length() < 12.0 or f.retarget <= 0.0 or far > LEASH:
		f.target = _pick(at, f)
		f.retarget = _rng.randf_range(12.0, 30.0)
		to = f.target - f.centre
	f.centre += to.limit_length(f.speed * delta)
	# Never through the ground.
	var floor_y := _ground(f.centre.x, f.centre.z) + f.height.x * 0.6
	f.centre.y = maxf(f.centre.y, floor_y)

## A little bird, beak along -Z: a body, a tail, and wings in two parts.
## Vertex colour r: 0 on the body, out to 1 at the wing tips (how far the
## flap moves it); g: 1 underneath.
static func _bird_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nose := Vector3(0, 0, -0.2)
	var tail := Vector3(0, 0.01, 0.16)
	var top := Vector3(0, 0.045, -0.02)
	var belly := Vector3(0, -0.04, -0.02)
	var l := Vector3(-0.045, 0, -0.02)
	var r := Vector3(0.045, 0, -0.02)
	for tri in [[nose, top, l], [nose, r, top], [nose, l, belly], [nose, belly, r],
			[tail, l, top], [tail, top, r], [tail, belly, l], [tail, r, belly]]:
		for p in tri:
			st.set_color(Color(0, 1.0 if p == belly else 0.0, 0))
			st.add_vertex(p)
	# The tail fan.
	for p in [Vector3(0, 0.01, 0.1), Vector3(-0.06, 0.0, 0.27), Vector3(0.06, 0.0, 0.27)]:
		st.set_color(Color(0, 0, 0))
		st.add_vertex(p)
	for s in [-1.0, 1.0]:
		var sh0 := Vector3(0.03 * s, 0.01, -0.07)
		var sh1 := Vector3(0.03 * s, 0.01, 0.05)
		var el0 := Vector3(0.2 * s, 0.02, -0.05)
		var el1 := Vector3(0.2 * s, 0.02, 0.06)
		var tip := Vector3(0.36 * s, 0.0, 0.1)
		for tri in [[sh0, el0, sh1], [sh1, el0, el1], [el0, tip, el1]]:
			for p in tri:
				st.set_color(Color(absf(p.x) / 0.36, 0, 0))
				st.add_vertex(p)
	st.generate_normals()
	return st.commit()

const SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_disabled;

varying float v_under;
varying float v_kind;
varying float v_wing;

void vertex() {
	float wing = COLOR.r;
	float beat = INSTANCE_CUSTOM.a;
	// Bursts of flapping, then a glide.
	float burst = smoothstep(0.2, 0.6, sin(TIME * 0.9 + INSTANCE_CUSTOM.r * 31.0) * 0.5 + 0.5);
	float amount = INSTANCE_CUSTOM.g * mix(0.25, 1.0, burst);
	float angle = sin(TIME * beat + INSTANCE_CUSTOM.r * 6.2832) * 0.85 * amount + 0.12;
	float side = sign(VERTEX.x);
	float out_x = abs(VERTEX.x);
	VERTEX.x = side * out_x * cos(angle);
	VERTEX.y += out_x * sin(angle);
	v_under = COLOR.g;
	v_kind = INSTANCE_CUSTOM.b;
	v_wing = wing;
}

void fragment() {
	vec3 c = vec3(0.07, 0.07, 0.08);
	if (v_kind > 0.75) {
		c = mix(vec3(0.30, 0.20, 0.12), vec3(0.62, 0.52, 0.40), v_under);
	} else if (v_kind > 0.25) {
		c = mix(vec3(0.92, 0.93, 0.95), vec3(0.22, 0.22, 0.24), smoothstep(0.75, 0.95, v_wing));
	}
	ALBEDO = c;
	ROUGHNESS = 0.9;
}
"""
