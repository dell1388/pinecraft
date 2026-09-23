class_name Outpost
extends Node3D

## A place out on the map worth the trip: a trading post that pays over the
## odds for what it is short of, a lookout tower you can climb, an old logging
## camp, a shack on stilts in the swamp, ruins in the sand, a miner's camp at a
## cave mouth. Most have a supply cache; all have a name on the map.
##
## Built from flat panels and hard edges like everything else, as one merged
## mesh with a handful of box colliders.

enum Kind { TRADING_POST, LOOKOUT, CAMP, SHACK, RUINS, MINERS_CAMP }

const TIMBER := Color(0.46, 0.32, 0.19)
const TIMBER_DARK := Color(0.33, 0.22, 0.13)
const CANVAS := Color(0.80, 0.74, 0.60)
const STONE := Color(0.62, 0.58, 0.50)
const ROOF := Color(0.55, 0.22, 0.16)

var kind: Kind = Kind.CAMP
var place_name: String = "Outpost"
var cache: SupplyCache
var yard: SellYard
var cache_reward: int = 120

var _body: StaticBody3D
var _g: Greeble
var _rng := RandomNumberGenerator.new()
var _manager: LooseItemManager
var _quests: QuestLog
var _premium: Dictionary = {}

func setup(p_kind: Kind, p_name: String, seed_value: int, reward: int = 120) -> void:
	kind = p_kind
	place_name = p_name
	cache_reward = reward
	_rng.seed = seed_value

## Trading posts need the item manager to buy from.
func setup_trade(manager: LooseItemManager, quests: QuestLog, premium: Dictionary) -> void:
	_manager = manager
	_quests = quests
	_premium = premium

func _ready() -> void:
	_body = StaticBody3D.new()
	_body.name = "Structure"
	_body.collision_layer = Layers.WORLD
	_body.collision_mask = 0
	add_child(_body)
	_g = Greeble.new()
	var plate_height := 6.0
	match kind:
		Kind.TRADING_POST:
			_trading_post()
		Kind.LOOKOUT:
			_lookout()
			plate_height = 16.0
		Kind.CAMP:
			_camp()
		Kind.SHACK:
			_shack()
		Kind.RUINS:
			_ruins()
		Kind.MINERS_CAMP:
			_miners_camp()
	if not _g.is_empty():
		add_child(_g.instance("OutpostMesh"))
	Nameplate.landmark(self, place_name.to_upper(), plate_height, Color(0.95, 0.85, 0.60))

# --- Helpers ---------------------------------------------------------------

func _solid(size: Vector3, xform: Transform3D, color: Color) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.transform = xform
	_body.add_child(cs)
	_g.box(size, xform, color)

## Collision with nothing drawn: the rough bulk of something detailed.
func _collider(size: Vector3, xform: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.transform = xform
	_body.add_child(cs)

func _at(size: Vector3, pos: Vector3, color: Color, yaw: float = 0.0) -> void:
	_solid(size, Transform3D(Basis(Vector3.UP, yaw), pos), color)

func _add_cache(pos: Vector3, yaw: float = 0.0) -> void:
	cache = SupplyCache.new()
	cache.name = "Cache"
	cache.setup(place_name, cache_reward)
	cache.position = pos
	cache.rotation.y = yaw
	add_child(cache)

## A small cabin: walls with a door gap, a pitched roof, a window and a lamp.
func _cabin(centre: Vector3, size: Vector3, wall: Color, roof: Color, yaw: float = 0.0) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), centre)
	var h := size * 0.5
	var t := 0.25
	var door := 1.4
	# Back and sides.
	_solid(Vector3(size.x, size.y, t), frame * Transform3D(Basis(), Vector3(0, h.y, -h.z)), wall)
	_solid(Vector3(t, size.y, size.z), frame * Transform3D(Basis(), Vector3(-h.x, h.y, 0)), wall)
	_solid(Vector3(t, size.y, size.z), frame * Transform3D(Basis(), Vector3(h.x, h.y, 0)), wall)
	# Front with a doorway.
	var side_w := (size.x - door) * 0.5
	for sx in [-1.0, 1.0]:
		_solid(Vector3(side_w, size.y, t), frame * Transform3D(Basis(), Vector3(sx * (door * 0.5 + side_w * 0.5), h.y, h.z)), wall)
	_solid(Vector3(door, size.y - 2.2, t), frame * Transform3D(Basis(), Vector3(0, 2.2 + (size.y - 2.2) * 0.5, h.z)), wall)
	# Corner posts and a sill, for edges.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_g.box(Vector3(0.3, size.y + 0.1, 0.3), frame * Transform3D(Basis(), Vector3(sx * h.x, h.y, sz * h.z)), wall.darkened(0.25))
	_g.box(Vector3(size.x + 0.3, 0.2, size.z + 0.3), frame * Transform3D(Basis(), Vector3(0, 0.1, 0)), wall.darkened(0.3))
	# Roof: two pitched slabs.
	var pitch := 0.5
	var run := h.x / cos(pitch) + 0.5
	for sx in [-1.0, 1.0]:
		var basis := Basis(Vector3.FORWARD, sx * pitch)
		_solid(Vector3(run, 0.2, size.z + 0.8), frame * Transform3D(basis,
			Vector3(sx * h.x * 0.5, size.y + tan(pitch) * h.x * 0.5 + 0.1, 0)), roof)
	_g.block(Vector3(0.3, 0.3, size.z + 0.9), (frame * Vector3(0, size.y + tan(pitch) * h.x + 0.1, 0)), roof.darkened(0.2))
	# Gable ends.
	for sz in [-1.0, 1.0]:
		var a: Vector3 = frame * Vector3(-h.x, size.y, sz * h.z)
		var b: Vector3 = frame * Vector3(h.x, size.y, sz * h.z)
		var c: Vector3 = frame * Vector3(0, size.y + tan(pitch) * h.x, sz * h.z)
		_g.tri(a, b, c, frame.basis * Vector3(0, 0, sz), wall.darkened(0.08))
	# A window on the side and a lamp by the door.
	_g.box(Vector3(0.1, 0.7, 1.0), frame * Transform3D(Basis(), Vector3(h.x + 0.1, size.y * 0.6, 0)), Color(0.95, 0.85, 0.55), true)
	_g.box(Vector3(0.18, 0.9, 1.25), frame * Transform3D(Basis(), Vector3(h.x + 0.05, size.y * 0.6, 0)), wall.darkened(0.3))
	_g.lamp(frame * Transform3D(Basis(), Vector3(door * 0.5 + 0.35, 2.3, h.z + 0.2)))

func _crate_stack(pos: Vector3, count: int) -> void:
	for i in count:
		var s := _rng.randf_range(0.6, 0.9)
		var p := pos + Vector3(_rng.randf_range(-0.6, 0.6), s * 0.5 + (0.0 if i < 2 else 0.8), _rng.randf_range(-0.6, 0.6))
		var xform := Transform3D(Basis(Vector3.UP, _rng.randf() * 0.6), p)
		_g.box(Vector3(s, s, s), xform, TIMBER.lightened(0.1))
		_g.frame(Vector3(s, s, s), xform, 0.06, TIMBER_DARK)

func _log_pile(pos: Vector3, yaw: float) -> void:
	var frame := Transform3D(Basis(Vector3.UP, yaw), pos)
	var row := [3, 2, 1]
	for level in row.size():
		for i in row[level]:
			var x := (float(i) - float(row[level] - 1) * 0.5) * 0.62
			var from: Vector3 = frame * Vector3(x, 0.3 + float(level) * 0.52, -2.0)
			var to: Vector3 = frame * Vector3(x, 0.3 + float(level) * 0.52, 2.0)
			_g.pipe(from, to, 0.3, Color(0.50, 0.36, 0.22), 8)
			_g.prism(8, 0.24, 0.24, 0.02, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, yaw), to), Color(0.80, 0.66, 0.44))
	_collider(Vector3(2.0, 1.4, 4.0), frame * Transform3D(Basis(), Vector3(0, 0.7, 0)))

func _fence_run(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	var n := maxi(1, int(length / 2.5))
	for i in n + 1:
		var p := from.lerp(to, float(i) / float(n))
		_g.block(Vector3(0.18, 1.1, 0.18), p + Vector3(0, 0.55, 0), TIMBER_DARK)
	_g.pipe(from + Vector3(0, 0.8, 0), to + Vector3(0, 0.8, 0), 0.06, TIMBER, 4)
	_g.pipe(from + Vector3(0, 0.45, 0), to + Vector3(0, 0.45, 0), 0.06, TIMBER, 4)

# --- The places ------------------------------------------------------------

func _trading_post() -> void:
	yard = SellYard.new()
	yard.name = "Yard"
	yard.keeper = "Trader"
	yard.extents = Vector3(14.0, 4.0, 14.0)
	yard.setup(_manager, _quests)
	yard.premium = _premium
	add_child(yard)
	_cabin(Vector3(0, 0, -13.0), Vector3(6.0, 3.0, 4.0), Color(0.62, 0.48, 0.32), ROOF)
	# A sign on two posts saying what they want.
	for sx in [-1.0, 1.0]:
		_g.block(Vector3(0.2, 3.2, 0.2), Vector3(sx * 2.4, 1.6, 8.5), TIMBER_DARK)
	_g.block(Vector3(5.2, 1.0, 0.15), Vector3(0, 2.8, 8.5), TIMBER.lightened(0.15))
	_g.stripes(5.0, 0.18, Transform3D(Basis(), Vector3(0, 2.35, 8.58)), Color(0.95, 0.74, 0.20), TIMBER_DARK)
	var sign := Label3D.new()
	sign.text = "WE PAY MORE FOR\n" + ", ".join(_premium.keys()).to_upper()
	sign.font_size = 48
	sign.pixel_size = 0.009
	sign.outline_size = 8
	sign.modulate = Color(0.12, 0.09, 0.05)
	sign.outline_modulate = Color(0.95, 0.88, 0.70, 0.0)
	sign.position = Vector3(0, 2.8, 8.6)
	add_child(sign)
	_crate_stack(Vector3(-5.5, 0, -9.0), 4)
	_crate_stack(Vector3(5.5, 0, -9.5), 3)
	_add_cache(Vector3(4.4, 0, -12.0), PI)

func _lookout() -> void:
	# A timber tower with a stair climbing round it, one flight to a side and a
	# landing at each corner, to a roofed platform at the top.
	var h := 10.0
	var w := 4.0
	var deck := 3.6                        ## half-width of the platform
	var r := w * 0.5 + 2.2                 ## the stair's centre-line
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_at(Vector3(0.4, h, 0.4), Vector3(sx * w * 0.5, h * 0.5, sz * w * 0.5), TIMBER_DARK)
	for y in [2.5, 5.0, 7.5]:
		for side in 4:
			var a := float(side) * PI * 0.5
			_g.box(Vector3(w, 0.18, 0.18), Transform3D(Basis(Vector3.UP, a), Vector3(sin(a), 0, cos(a)) * w * 0.5 + Vector3(0, y, 0)), TIMBER)
	_at(Vector3(deck * 2.0, 0.3, deck * 2.0), Vector3(0, h + 0.15, 0), TIMBER)
	_solid(Vector3(deck * 2.0 + 1.0, 0.2, deck * 2.0 + 1.0), Transform3D(Basis(), Vector3(0, h + 3.3, 0)), ROOF)
	_g.prism(4, (deck * 2.0 + 1.0) * 0.72, 0.0, 1.4, Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, h + 3.4, 0)), ROOF.darkened(0.1))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_g.block(Vector3(0.2, 3.0, 0.2), Vector3(sx * (deck - 0.2), h + 1.8, sz * (deck - 0.2)), TIMBER_DARK)
	# Rails, leaving the corner the stair arrives at open.
	_at(Vector3(0.12, 1.0, deck * 2.0), Vector3(deck, h + 0.8, 0), TIMBER_DARK)
	_at(Vector3(deck * 2.0, 1.0, 0.12), Vector3(0, h + 0.8, -deck), TIMBER_DARK)
	_at(Vector3(0.12, 1.0, deck * 1.2), Vector3(-deck, h + 0.8, -deck * 0.4), TIMBER_DARK)
	_at(Vector3(deck * 1.2, 1.0, 0.12), Vector3(deck * 0.4, h + 0.8, deck), TIMBER_DARK)
	var corners := [Vector3(-r, 0, r), Vector3(r, 0, r), Vector3(r, 0, -r), Vector3(-r, 0, -r), Vector3(-r, 0, r)]
	var landing := 1.8
	var rise := h / 4.0
	for i in 4:
		var c0: Vector3 = corners[i]
		var c1: Vector3 = corners[i + 1]
		var dir := (c1 - c0).normalized()
		var from := c0 + dir * landing * 0.5 + Vector3(0, float(i) * rise, 0)
		var to := c1 - dir * landing * 0.5 + Vector3(0, float(i + 1) * rise, 0)
		var basis := Basis.looking_at(to - from, Vector3.UP)
		_solid(Vector3(1.6, 0.25, from.distance_to(to)), Transform3D(basis, (from + to) * 0.5 - basis.y * 0.12), TIMBER.lightened(0.05))
		for k in 8:
			var t := (float(k) + 0.5) / 8.0
			_g.box(Vector3(1.6, 0.08, 0.3), Transform3D(Basis.looking_at(dir, Vector3.UP), from.lerp(to, t) + Vector3(0, 0.05, 0)), TIMBER_DARK)
		_at(Vector3(landing, 0.25, landing), c1 + Vector3(0, float(i + 1) * rise - 0.12, 0), TIMBER)
		_g.block(Vector3(0.25, float(i + 1) * rise, 0.25), c1 + Vector3(0, float(i + 1) * rise * 0.5, 0), TIMBER_DARK)
	# The last landing reaches the platform's open corner.
	_at(Vector3(r - deck + 0.8, 0.25, r - deck + 0.8), Vector3(-(deck + r) * 0.5, h - 0.12, (deck + r) * 0.5), TIMBER)
	_add_cache(Vector3(1.2, h + 0.3, -1.6))
	# A spyglass on a stand.
	_g.block(Vector3(0.12, 1.1, 0.12), Vector3(1.8, h + 0.85, 1.8), TIMBER_DARK)
	_g.pipe(Vector3(1.6, h + 1.45, 1.6), Vector3(2.2, h + 1.6, 2.2), 0.08, Color(0.75, 0.62, 0.30), 6)

func _camp() -> void:
	# Two canvas tents, a fire ring, a sawhorse and a log pile.
	for spec in [[Vector3(-4.0, 0, -2.0), 0.4], [Vector3(3.5, 0, -3.5), -0.3]]:
		var frame := Transform3D(Basis(Vector3.UP, spec[1]), spec[0])
		var half := 1.6
		var ridge := 2.2
		for sx in [-1.0, 1.0]:
			var a: Vector3 = frame * Vector3(sx * half, 0, -1.8)
			var b: Vector3 = frame * Vector3(sx * half, 0, 1.8)
			var c: Vector3 = frame * Vector3(0, ridge, 1.8)
			var d: Vector3 = frame * Vector3(0, ridge, -1.8)
			_g.quad(a, b, c, d, frame.basis * Vector3(sx, 0.6, 0), CANVAS.darkened(0.05 if sx > 0 else 0.0))
		_g.tri(frame * Vector3(-half, 0, -1.8), frame * Vector3(half, 0, -1.8), frame * Vector3(0, ridge, -1.8), frame.basis * Vector3(0, 0, -1), CANVAS.darkened(0.12))
		_g.block(Vector3(0.12, ridge + 0.3, 0.12), frame * Vector3(0, (ridge + 0.3) * 0.5, 1.9), TIMBER_DARK)
		_collider(Vector3(half * 2.0, ridge * 0.6, 3.6), frame * Transform3D(Basis(), Vector3(0, ridge * 0.3, 0)))
	for i in 8:
		var a := TAU * float(i) / 8.0
		_g.box(Vector3(0.35, 0.25, 0.3), Transform3D(Basis(Vector3.UP, a), Vector3(cos(a) * 0.8, 0.12, 2.5 + sin(a) * 0.8)), STONE)
	for i in 3:
		var a := TAU * float(i) / 3.0
		_g.pipe(Vector3(cos(a) * 0.5, 0.1, 2.5 + sin(a) * 0.5), Vector3(0, 0.5, 2.5), 0.08, Color(0.3, 0.2, 0.12), 5)
	_g.prism(5, 0.3, 0.0, 0.6, Transform3D(Basis(), Vector3(0, 0.1, 2.5)), Color(1.0, 0.55, 0.15), true)
	var fire := OmniLight3D.new()
	fire.position = Vector3(0, 1.0, 2.5)
	fire.light_color = Color(1.0, 0.6, 0.25)
	fire.light_energy = 1.2
	fire.omni_range = 7.0
	fire.distance_fade_enabled = true
	fire.distance_fade_begin = 60.0
	add_child(fire)
	_log_pile(Vector3(6.0, 0, 2.5), 0.2)
	# Sawhorse with a log across it.
	for z in [-0.6, 0.6]:
		for sx in [-1.0, 1.0]:
			_g.box(Vector3(0.1, 1.0, 0.1), Transform3D(Basis(Vector3.FORWARD, sx * 0.35), Vector3(-5.0 + sx * 0.18, 0.45, 4.0 + z)), TIMBER)
	_g.pipe(Vector3(-5.0, 0.95, 2.8), Vector3(-5.0, 0.95, 5.2), 0.22, Color(0.50, 0.36, 0.22), 8)
	_add_cache(Vector3(-1.5, 0, -4.5), 0.3)

func _shack() -> void:
	# A cabin up on stilts with a ramp to its door.
	var up := 1.8
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_at(Vector3(0.3, up + 0.5, 0.3), Vector3(sx * 2.4, (up + 0.5) * 0.5 - 0.5, sz * 2.0), TIMBER_DARK)
	_at(Vector3(5.6, 0.25, 4.8), Vector3(0, up, 0), TIMBER)
	_cabin(Vector3(0, up + 0.12, -0.2), Vector3(4.6, 2.6, 3.6), Color(0.42, 0.36, 0.24), Color(0.30, 0.34, 0.22))
	var from := Vector3(0, 0.0, 6.8)
	var to := Vector3(0, up, 2.4)
	var basis := Basis.looking_at(to - from, Vector3.UP)
	_solid(Vector3(1.4, 0.2, from.distance_to(to)), Transform3D(basis, (from + to) * 0.5 - basis.y * 0.1), TIMBER)
	for k in 6:
		_g.block(Vector3(1.4, 0.07, 0.2), from.lerp(to, (float(k) + 0.5) / 6.0) + Vector3(0, 0.06, 0), TIMBER_DARK)
	_add_cache(Vector3(1.5, up + 0.12, 1.6))
	# A little jetty and a rowing boat.
	_at(Vector3(1.4, 0.2, 5.0), Vector3(-4.5, 0.25, 3.0), TIMBER)
	var boat := Transform3D(Basis(Vector3.UP, 0.2), Vector3(-6.2, 0.15, 3.5))
	_g.box(Vector3(1.1, 0.35, 2.6), boat, Color(0.36, 0.26, 0.16))
	_g.box(Vector3(0.9, 0.1, 2.3), boat * Transform3D(Basis(), Vector3(0, 0.15, 0)), Color(0.25, 0.18, 0.11))

func _ruins() -> void:
	# Broken walls and fallen columns of an older building.
	var wall := STONE
	var pieces := [
		[Vector3(9.0, 3.2, 0.8), Vector3(0, 1.6, -5.0), 0.0],
		[Vector3(0.8, 2.2, 6.0), Vector3(-4.6, 1.1, -2.0), 0.0],
		[Vector3(0.8, 4.0, 4.0), Vector3(4.6, 2.0, -3.0), 0.0],
		[Vector3(3.0, 1.2, 0.8), Vector3(-3.0, 0.6, 3.0), 0.0],
	]
	for p in pieces:
		_at(p[0], p[1], wall.lightened(_rng.randf_range(-0.05, 0.05)), p[2])
		# Broken tops: a few blocks missing and a few loose ones.
		var size: Vector3 = p[0]
		for k in 3:
			_g.box(Vector3(0.7, 0.5, 0.7), Transform3D(Basis(Vector3.UP, _rng.randf()), (p[1] as Vector3) +
				Vector3(_rng.randf_range(-size.x, size.x) * 0.4, size.y * 0.5 + 0.25, _rng.randf_range(-size.z, size.z) * 0.4)), wall.darkened(0.08))
	for i in 4:
		var x := -3.0 + float(i) * 2.0
		var height := _rng.randf_range(1.2, 3.6) if i != 2 else 0.4
		_solid(Vector3(0.9, height, 0.9), Transform3D(Basis(), Vector3(x, height * 0.5, 0.0)), wall.lightened(0.06))
		_g.box(Vector3(1.2, 0.3, 1.2), Transform3D(Basis(), Vector3(x, 0.15, 0)), wall.darkened(0.1))
	# One lying where it fell.
	_g.pipe(Vector3(1.5, 0.45, 1.5), Vector3(4.5, 0.45, 3.5), 0.45, wall.lightened(0.04), 8)
	_collider(Vector3(3.6, 0.9, 0.9), Transform3D(Basis(Vector3.UP, -0.59), Vector3(3.0, 0.45, 2.5)))
	# Sand drifted against the walls.
	_g.wedge(Vector3(9.0, 1.0, 2.0), Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.5, -3.6)), Color(0.86, 0.74, 0.47))
	_add_cache(Vector3(-2.2, 0, -3.8), 0.4)

func _miners_camp() -> void:
	_cabin(Vector3(0, 0, 0), Vector3(4.0, 2.6, 3.4), Color(0.44, 0.40, 0.36), Color(0.30, 0.30, 0.32))
	_crate_stack(Vector3(3.6, 0, 1.0), 3)
	# An ore cart on a short bit of track, and a pick leaning on the wall.
	for sx in [-0.5, 0.5]:
		_g.pipe(Vector3(-4.0, 0.06, 3.0 + sx), Vector3(-1.0, 0.06, 3.0 + sx), 0.05, Color(0.45, 0.43, 0.40), 4)
	_g.box(Vector3(1.3, 0.8, 1.0), Transform3D(Basis(), Vector3(-2.5, 0.55, 3.0)), Color(0.36, 0.33, 0.30))
	_g.box(Vector3(1.1, 0.25, 0.8), Transform3D(Basis(), Vector3(-2.5, 0.95, 3.0)), Color(0.82, 0.62, 0.24))
	_g.pipe(Vector3(2.0, 0.0, 1.8), Vector3(2.1, 1.3, 1.75), 0.04, TIMBER, 4)
	_g.box(Vector3(0.1, 0.1, 0.8), Transform3D(Basis(), Vector3(2.1, 1.3, 1.75)), Color(0.5, 0.5, 0.52))
	_add_cache(Vector3(-1.2, 0, -2.4))
