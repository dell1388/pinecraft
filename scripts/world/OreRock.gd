class_name OreRock
extends StaticBody3D

## A chunk of ore sitting part-buried in the ground.
##
## There are two ways to get it out, and they cost different things. Pulling
## takes it whole, but the pull needed is its own weight plus the share of it
## that is still buried - so a big chunk simply will not come, however long you
## heave. Hammering takes time instead of strength: every blow opens a crack
## somewhere random or drives an existing one deeper, and when a crack goes all
## the way through, the piece on the near side of it breaks away and can be
## carried off while the rest stays in the ground.
##
## Either way the ore is conserved: what comes out of the hole adds up to what
## was in it.

signal broken(rock: OreRock)
signal yielded(rock: OreRock, ore_volume: float)

@export var ore_item: StringName = &"ore_iron"
## How much of the chunk is buried, as a fraction. The pull needed to free it
## is its mass plus this much of its mass again.
@export var embed: float = 0.45

## A chunk of radius r holds about this much ore: it is a lumpy thing, not a
## box, so it does not fill its own bounds.
const SHAPE_FILL := 2.36
## Below this there is no chunk left to work; the remainder comes free whole.
const MIN_CHUNK := 0.06
## Crack depth opened per kilogram of hammer head, before the chunk's size is
## taken into account. A heavier head cracks deeper, a bigger chunk cracks slower.
const CRACK_GAIN := 0.05
## Two blows closer together than this along the chunk work the same crack.
const CRACK_SPREAD := 0.18
## The least of the chunk a single fracture can take off.
const MIN_SPLIT := 0.12

var volume: float = 1.0
## Open cracks: {t: where along the chunk, 0..1; depth: how far through, 0..1}.
var cracks: Array[Dictionary] = []
var plot_id: int = 0
var manager: LooseItemManager

var _parts: Array[MeshInstance3D] = []
var _crack_meshes: Array[MeshInstance3D] = []
var _shape: CollisionShape3D
var _consumed: bool = false
## Set by the first blow or heave. A field only retires chunks nobody has worked.
var touched: bool = false
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	collision_layer = Layers.TREE      # shares the "resource node" layer
	collision_mask = Layers.WORLD
	if _rng.seed == 0:
		_rng.seed = hash(name) + int(position.x * 13.0) + int(position.z * 29.0)
	_rebuild()

func seed_form(value: int) -> void:
	_rng.seed = value

## Sets the chunk's size by the ore in it. The visible rock follows from this,
## never the other way round.
func set_volume(value: float) -> void:
	volume = maxf(MIN_CHUNK, value)
	if is_inside_tree():
		_rebuild()

## Half-width of the chunk, derived from how much ore is left in it.
func radius() -> float:
	return pow(maxf(0.0001, volume / SHAPE_FILL), 1.0 / 3.0)

func density() -> float:
	var def := GameData.item(ore_item)
	return def.density if def != null else 900.0

func mass() -> float:
	return density() * volume

## Spec: the pull to disgorge a chunk is its mass plus the buried fraction of
## its mass again.
func pull_required() -> float:
	return mass() * (1.0 + embed)

func untouched() -> bool:
	return not _consumed and not touched

func consumed() -> bool:
	return _consumed

## How close the worst crack is to going through, 0..1. Drives the aim prompt.
func worst_crack() -> float:
	var worst := 0.0
	for c in cracks:
		worst = maxf(worst, float(c.depth))
	return worst

# --- Working the chunk -----------------------------------------------------

## One blow of a hammer. Opens a crack at a random spot, or drives a nearby one
## deeper, and fractures the chunk when a crack goes all the way through.
func strike(head_kg: float) -> String:
	if _consumed:
		return ""
	touched = true
	var t := _rng.randf()
	var index := _crack_near(t)
	if index < 0:
		cracks.append({"t": t, "depth": 0.0})
		index = cracks.size() - 1
	# Depth won per blow falls off with the chunk's cross-section, so the same
	# hammer that shatters a boulder-chip barely marks a boulder.
	var gain: float = head_kg * CRACK_GAIN / pow(maxf(0.05, volume), 2.0 / 3.0)
	cracks[index]["depth"] = float(cracks[index].depth) + gain
	_nudge()
	if float(cracks[index].depth) < 1.0:
		_refresh_cracks()
		return "crack deepens (%d%%)" % int(float(cracks[index].depth) * 100.0)
	return _fracture(index)

func _crack_near(t: float) -> int:
	for i in cracks.size():
		if absf(float(cracks[i].t) - t) <= CRACK_SPREAD:
			return i
	return -1

## A crack has gone through: the piece on its near side breaks away.
func _fracture(index: int) -> String:
	var t: float = cracks[index].t
	# The crack splits the chunk where it fell; the smaller side is what comes
	# off, so hammering peels a chunk down rather than halving it forever.
	var share: float = clampf(minf(t, 1.0 - t), MIN_SPLIT, 0.5)
	var piece: float = volume * share
	cracks.remove_at(index)
	_drop_ore(piece, Vector3.UP * 1.2)
	volume -= piece
	# What is left sits deeper in its hole than what came off it.
	embed = clampf(embed + 0.06, 0.0, 0.85)
	if volume <= MIN_CHUNK:
		var last := volume
		_drop_ore(last, Vector3.UP * 1.0)
		_consume()
		return "chunk broken up"
	_rebuild()
	yielded.emit(self, piece)
	return "%.2f m3 breaks off" % piece

## Tries to haul the whole chunk out of the ground. Returns the freed ore, or
## null when the pull is not enough.
func try_free(pull_kg: float) -> LooseItem:
	if _consumed:
		return null
	touched = true
	if pull_kg < pull_required():
		return null
	var freed := _drop_ore(volume, Vector3.UP * 0.6)
	_consume()
	return freed

## Breaks the whole chunk up at once. Not a player action: this is how tests and
## the smoke run empty a chunk without simulating a hundred hammer blows.
func shatter() -> int:
	var pieces := 0
	var guard := 0
	while not _consumed and guard < 200:
		guard += 1
		if strike(10000.0) != "":
			pieces += 1
	return pieces

func _drop_ore(piece_volume: float, impulse: Vector3) -> LooseItem:
	if manager == null or piece_volume <= 0.0:
		return null
	var top := global_position + Vector3(0, radius() * (1.0 - embed) + 0.35, 0)
	var spot := top + Vector3(_rng.randf_range(-0.3, 0.3), 0.0, _rng.randf_range(-0.3, 0.3))
	var item := manager.spawn(ore_item, Transform3D(Basis(), spot), plot_id, impulse,
		Solid.cube(piece_volume))
	yielded.emit(self, piece_volume)
	return item

func _consume() -> void:
	_consumed = true
	_shape.disabled = true
	for p in _parts:
		p.visible = false
	for c in _crack_meshes:
		c.visible = false
	collision_layer = 0
	broken.emit(self)

# --- Geometry --------------------------------------------------------------

## The chunk is drawn from the ore left in it, so hammering a piece off visibly
## shrinks the rock in the ground.
func _rebuild() -> void:
	for p in _parts:
		p.queue_free()
	_parts.clear()
	var r := radius()
	var ore_def := GameData.item(ore_item)
	var stone := Color(0.47, 0.45, 0.42)
	var seam: Color = ore_def.color if ore_def != null else Color(0.5, 0.5, 0.5)
	# Buried up to `embed`, so the chunk reads as part of the ground rather
	# than something dropped on it.
	var lift := -r * embed

	if _shape == null:
		_shape = CollisionShape3D.new()
		_shape.shape = BoxShape3D.new()
		add_child(_shape)
	(_shape.shape as BoxShape3D).size = Vector3(r * 1.9, r * 1.5, r * 1.9)
	_shape.position = Vector3(0, lift + r * 0.75, 0)

	var form := RandomNumberGenerator.new()
	form.seed = _rng.seed                 # same rock, same lumps, as it shrinks

	# One merged mesh: a slabby main block, a few shoulders of rock leaning on
	# it, and the ore itself as crystals breaking out of the surface - so iron,
	# copper and gold read differently at a glance, and gold catches the light.
	var g := Greeble.new()
	g.box(Vector3(r * 1.7, r * 1.4, r * 1.6), Transform3D(
		Basis(Vector3.UP, form.randf() * PI) * Basis(Vector3.FORWARD, form.randf_range(-0.2, 0.2)),
		Vector3(0, lift + r * 0.7, 0)), stone)
	for i in 3:
		var scale: float = form.randf_range(0.45, 0.75)
		var angle: float = TAU * float(i) / 3.0 + form.randf_range(-0.4, 0.4)
		g.box(Vector3(r * scale, r * scale * 0.9, r * scale),
			Transform3D(Basis(Vector3.UP, form.randf() * PI) * Basis(Vector3.RIGHT, form.randf_range(-0.4, 0.4)),
				Vector3(cos(angle) * r * 0.7, lift + r * form.randf_range(0.3, 0.95), sin(angle) * r * 0.7)),
			stone.lightened(form.randf_range(0.0, 0.12)))
	var glint := ore_item == &"ore_gold"
	for i in 5:
		var angle2: float = TAU * form.randf()
		var out := Vector3(cos(angle2), form.randf_range(0.2, 0.9), sin(angle2)).normalized()
		var at := Vector3(0, lift + r * 0.75, 0) + out * r * 0.72
		var up := out.lerp(Vector3.UP, 0.3).normalized()
		var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
		var basis := Basis(side, up, side.cross(up))
		for k in 2:
			var tilt := Basis(Vector3.FORWARD, form.randf_range(-0.4, 0.4))
			g.prism(6, r * form.randf_range(0.08, 0.14), 0.0, r * form.randf_range(0.35, 0.6),
				Transform3D(basis * tilt, at + side * r * 0.1 * float(k)), seam, glint)
		g.box(Vector3(r * 0.34, r * 0.1, r * 0.3), Transform3D(basis, at - up * r * 0.02), seam.darkened(0.2))
	var mi := g.instance("Rock")
	add_child(mi)
	_parts.append(mi)
	_refresh_cracks()

## Cracks are drawn as dark seams that lengthen as they deepen, so a chunk that
## is nearly through looks it.
func _refresh_cracks() -> void:
	for c in _crack_meshes:
		c.queue_free()
	_crack_meshes.clear()
	var r := radius()
	var lift := -r * embed
	for crack in cracks:
		var depth: float = clampf(float(crack.depth), 0.0, 1.0)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(r * 0.06, r * 1.45 * depth, r * 2.0 * depth)
		mi.mesh = bm
		mi.position = Vector3((float(crack.t) - 0.5) * r * 1.6, lift + r * 0.75, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.06, 0.06, 0.07)
		mat.roughness = 1.0
		mi.material_override = mat
		add_child(mi)
		_crack_meshes.append(mi)

func _nudge() -> void:
	if _parts.is_empty() or not is_instance_valid(_parts[0]):
		return
	_parts[0].scale = Vector3(1.04, 0.97, 1.04)
	create_tween().tween_property(_parts[0], "scale", Vector3.ONE, 0.1)

func status_line() -> String:
	return "%s chunk  %.2f m3  %.0f kg  needs %.0f kg of pull" % [
		GameData.item_name(ore_item), volume, mass(), pull_required()]
