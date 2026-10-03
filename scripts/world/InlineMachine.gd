class_name InlineMachine
extends Conveyor

## A processing machine you run material *through*: a belt with a tunnel over
## the middle of it, like a curing oven on a production line. A piece rides
## into one mouth and is taken in; the machine changes it and sets it back
## down on the belt outside the other mouth, one piece at a time, whenever
## there is room there.
##
##   Planker   a log becomes one plank as long as the log and as wide as it
##             allows - not a heap of little boards
##   Sander    wood (log or plank) comes out sanded, which sells for more
##   Crusher   a big ore chunk comes out as lumps a smelter will take
##   Smelter   ore comes out as a metal bar
##   Refiner   a metal bar comes out refined, which sells for more
##
## The tunnel mouths are real openings in real walls: a piece too big for the
## mouth hits the bulkhead and jams there, which is what the tier upgrades
## (wider mouths, faster belts) are for. Anything the machine does not work on
## comes out as it went in, so machines chain on one line. A trunk still on
## its branches goes in if it fits the mouth, branches and all; they come
## off inside and follow it out as pieces of their own.

signal processed(machine: InlineMachine, item: LooseItem)

var def: BuildingDef
var machine_def: MachineDef
var manager: LooseItemManager
var plot_id: int = 0
var level: int = 1
var hole: Vector2 = Vector2(1.0, 0.8)
var total_processed: int = 0
var volume_in: float = 0.0
var volume_out: float = 0.0
## What the machine is set to make, in centimetres (see config_fields): the
## planker's board width and thickness, the crusher's biggest lump, the
## smelter's bar thickness, the refiner's cross-section, the cutter's jewel
## size. Zero (or unset) is as it comes: one piece, its natural size. Volume
## is the same whatever it is set to; only the size of the pieces changes.
var config: Dictionary = {}
## A running machine hums (quietly: there may be a dozen of them).
var _hum: AudioStreamPlayer3D

func _process(_delta: float) -> void:
	if _hum != null:
		_hum.volume_db = (Sfx.sfx_db() - 20.0) if running else -80.0

## Longest a bar or a refined piece is made before it is cut in two.
const MAX_BAR := 0.8

const WALL := 0.15
const LIP_LENGTH := 0.7

var _canopy: StaticBody3D
var _canopy_nodes: Array[Node] = []
var _burst: CPUParticles3D
var _ambient: Array[CPUParticles3D] = []
var _lamp_material: StandardMaterial3D
var _glow: OmniLight3D

func setup_machine(p_manager: LooseItemManager, p_def: BuildingDef, p_plot_id: int = 0) -> void:
	manager = p_manager
	def = p_def
	plot_id = p_plot_id
	machine_def = GameData.machine(p_def.machine)
	length = float(p_def.size.z) * Plot.CELL
	width = float(p_def.size.x) * Plot.CELL * 0.9
	railed = true
	_apply_level()

func _ready() -> void:
	if machine_def == null and def != null:
		machine_def = GameData.machine(def.machine)
	super()
	_hum = Sfx.loop(&"hum")
	add_child(_hum)
	_build_canopy()

## Tiers widen the mouth and speed the belt.
func _apply_level() -> void:
	# Each machine is the tier it was bought at.
	level = def.tier if def != null else 1
	var stats := GameData.upgrade_level(machine_def.id, level)
	var hole_scale := float(stats.get("hole_scale", 1.0))
	var outer := float(def.size.x) * Plot.CELL
	hole = Vector2(minf(machine_def.tunnel.x * hole_scale, outer - WALL * 2.0 - 0.1),
		minf(machine_def.tunnel.y * hole_scale, float(def.size.y) * Plot.CELL - 0.9))
	speed = machine_def.belt_speed * float(stats.get("rate_scale", 1.0)) * Balance.num("machines.speed_multiplier", 1.0)

## The last piece that went through untouched because it was too hard for
## this tier, to say so on the status line.
var too_hard: String = ""

func tier_label() -> String:
	return String(GameData.upgrade_level(machine_def.id, level).get("label", "T%d" % level))

func canopy_length() -> float:
	return length - LIP_LENGTH * 2.0

func canopy_height() -> float:
	return maxf(hole.y + 0.45, 1.3)

# --- The tunnel ----------------------------------------------------------------

func _build_canopy() -> void:
	_canopy = StaticBody3D.new()
	_canopy.name = "Canopy"
	_canopy.collision_layer = Layers.MACHINE
	_canopy.collision_mask = Layers.MASK_MACHINE
	# Slick steel: a piece pushed against a wall or a guide wing slides along
	# it instead of sticking and holding up the line behind it.
	var slick := PhysicsMaterial.new()
	slick.friction = 0.08
	_canopy.physics_material_override = slick
	add_child(_canopy)
	_canopy_nodes.append(_canopy)
	var outer := float(def.size.x) * Plot.CELL
	var run := canopy_length()
	var h := canopy_height()
	var floor_y := DECK_THICKNESS
	var half := outer * 0.5
	# Side walls and roof.
	for side in [-1.0, 1.0]:
		_solid(Vector3(WALL, h, run), Vector3(side * (half - WALL * 0.5), floor_y + h * 0.5, 0))
	if top_loaded():
		_build_hopper(outer, run, h)
	else:
		_solid(Vector3(outer, 0.12, run), Vector3(0, floor_y + h + 0.06, 0))
	# Inside, a duct exactly the size of the mouths, from one bulkhead to the
	# other. With room to spare in there, pieces wandered off the line -
	# sideways, or up on top of each other - and fetched up against the out
	# bulkhead beside the opening, where the belt could never free them.
	var duct := run - WALL * 2.0
	for side in [-1.0, 1.0]:
		_solid(Vector3(WALL, hole.y, duct), Vector3(side * (hole.x * 0.5 + WALL * 0.5), floor_y + hole.y * 0.5, 0))
	if h - hole.y > 0.01 and not top_loaded():
		_solid(Vector3(hole.x, WALL, duct), Vector3(0, floor_y + hole.y + WALL * 0.5, 0))
	# The bulkheads at each end, with the mouth cut out of them - but a
	# top-loaded machine is shut at the in-feed end.
	for end in [-1.0, 1.0]:
		var z: float = end * (run * 0.5 - WALL * 0.5)
		if end > 0.0 and top_loaded():
			_solid(Vector3(outer, h, WALL), Vector3(0, floor_y + h * 0.5, z))
			continue
		var jamb := (outer - hole.x) * 0.5
		for side in [-1.0, 1.0]:
			_solid(Vector3(jamb, h, WALL), Vector3(side * (half - jamb * 0.5), floor_y + h * 0.5, z))
		var over := h - hole.y
		if over > 0.01:
			_solid(Vector3(hole.x, over, WALL), Vector3(0, floor_y + hole.y + over * 0.5, z))
	var dress := _dress_canopy(outer, run, h)
	# Guide wings on the in-feed lip, angled from the belt's edges to the
	# mouth, so a piece riding off-centre is steered in rather than stopped
	# against the bulkhead beside the opening - with the rest heaping up
	# behind it.
	if hole.x < width - 0.1 and not top_loaded():
		for side in [-1.0, 1.0]:
			var a := Vector3(side * (width * 0.5 - 0.04), floor_y, length * 0.5)
			var b := Vector3(side * (hole.x * 0.5 - 0.02), floor_y, run * 0.5)
			var along := (b - a)
			var basis := Basis(Vector3.UP.cross(along.normalized()), Vector3.UP, along.normalized())
			var centre := (a + b) * 0.5 + Vector3(0, 0.25, 0)
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.06, 0.5, along.length() + 0.04)
			cs.shape = box
			cs.transform = Transform3D(basis, centre)
			_canopy.add_child(cs)
			dress.box(box.size, Transform3D(basis, centre), Color(0.95, 0.74, 0.16))
	var mesh := dress.instance("Tunnel")
	_canopy.add_child(mesh)
	_add_lamp(Vector3(half - 0.05, floor_y + h * 0.75, run * 0.5 - 0.3))
	_add_effects(run, h)

## The crusher is fed from above: a hopper on the roof, open to the sky,
## nearly the whole roof wide. Whatever lands in it is crushed, however big.
## It is not fed along the belt.
const HOPPER_DEPTH := 0.8

func top_loaded() -> bool:
	return machine_def != null and machine_def.mode == MachineDef.MODE_CRUSH

func hopper_opening() -> float:
	var outer := float(def.size.x) * Plot.CELL if def != null else 3.0
	return minf(outer, canopy_length()) - 0.3

var _hopper_area: Area3D
var _hopper_shape: CollisionShape3D

func _build_hopper(outer: float, run: float, h: float) -> void:
	var floor_y := DECK_THICKNESS
	var open := hopper_opening()
	var roof_y := floor_y + h + 0.06
	# The roof round the opening.
	var side_w := (outer - open) * 0.5
	var end_l := (run - open) * 0.5
	for s in [-1.0, 1.0]:
		_solid(Vector3(side_w, 0.12, run), Vector3(s * (open * 0.5 + side_w * 0.5), roof_y, 0))
		_solid(Vector3(open, 0.12, end_l), Vector3(0, roof_y, s * (open * 0.5 + end_l * 0.5)))
	# The hopper's walls, standing up round it.
	for s in [-1.0, 1.0]:
		_solid(Vector3(0.08, HOPPER_DEPTH, open + 0.16), Vector3(s * (open * 0.5 + 0.04), roof_y + HOPPER_DEPTH * 0.5, 0))
		_solid(Vector3(open, HOPPER_DEPTH, 0.08), Vector3(0, roof_y + HOPPER_DEPTH * 0.5, s * (open * 0.5 + 0.04)))
	# What falls into it is taken.
	_hopper_area = Area3D.new()
	_hopper_area.collision_layer = Layers.TRIGGER
	_hopper_area.collision_mask = Layers.LOOSE | Layers.PLAYER
	_hopper_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	# From down inside the machine to well over the rims, so a piece too
	# big to drop through, sitting on top, is taken as well.
	var tall := h + HOPPER_DEPTH + 1.2
	box.size = Vector3(open + 0.3, tall, open + 0.3)
	_hopper_shape.shape = box
	_hopper_shape.position = Vector3(0, floor_y + 0.2 + tall * 0.5, 0)
	_hopper_area.add_child(_hopper_shape)
	_canopy.add_child(_hopper_area)
	if machine_def.mode == MachineDef.MODE_CRUSH:
		_build_wheels(open, roof_y, h)

# --- The grinding wheels ------------------------------------------------------------

## Two toothed steel drums under the hopper's mouth, turning in toward each
## other while the crusher runs. Only the look: what drops in is taken by the
## hopper, as ever. Someone who falls in is drawn down between them, slowly.
var _wheels: Array[Node3D] = []
var _wheel_nip: Vector3 = Vector3.ZERO
var _blood: CPUParticles3D
## Players being drawn in: Player -> true.
var _grinding: Dictionary = {}
## Seconds from falling in to going through.
const GRIND_SECONDS := 2.6

## The rollers (assets/models/crusher_roller.glb, built in Blender from
## source/crusher.blend): a shaft, a core drum and seven cutter discs with
## hooked teeth staggered round it, 2 m long and 1 m to the tooth tips; and a
## bearing block for each end of the shaft.
const ROLLER_MODEL := "res://assets/models/crusher_roller.glb"
static var _roller_mesh: Mesh
static var _bearing_mesh: Mesh

static func _roller_parts() -> void:
	if _roller_mesh != null:
		return
	var scene := load(ROLLER_MODEL) as PackedScene
	if scene == null:
		return
	var root := scene.instantiate()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if String(n.name).begins_with("CrusherRoller"):
			_roller_mesh = (n as MeshInstance3D).mesh
		elif String(n.name).begins_with("CrusherBearing"):
			_bearing_mesh = (n as MeshInstance3D).mesh
	root.free()

func _build_wheels(open: float, roof_y: float, h: float) -> void:
	_roller_parts()
	# Two big rollers filling the hopper's mouth side by side, their shafts
	# level with the hopper's floor: the top halves turn in the hopper, the
	# bottoms down in the machine. Their ends stop inside the hopper's walls,
	# the bearings between them and the walls.
	var r := clampf(open * 0.245, 0.3, 0.75)
	var y := roof_y
	var bearing_w := 0.22 * r
	var span := open - 0.1 - bearing_w * 2.0
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "Roller_%s" % ("front" if side < 0 else "back")
		pivot.position = Vector3(0, y, side * r * 0.98)
		if _roller_mesh != null:
			var mi := MeshInstance3D.new()
			mi.mesh = _roller_mesh
			mi.scale = Vector3(span / 2.0, r, r)
			# Staggered, so the teeth of one pass between the other's.
			mi.rotation.x = 0.0 if side < 0 else PI * 0.25
			pivot.add_child(mi)
		_canopy.add_child(pivot)
		pivot.set_meta("turn", -side)
		_wheels.append(pivot)
		if _bearing_mesh != null:
			for e in [-1.0, 1.0]:
				var b := MeshInstance3D.new()
				b.mesh = _bearing_mesh
				b.scale = Vector3(r, r, r)
				b.position = Vector3(e * (span * 0.5 + bearing_w * 0.5 + 0.02), y, side * r * 0.98)
				_canopy.add_child(b)
	_wheel_nip = Vector3(0, y, 0)
	_blood = CPUParticles3D.new()
	_blood.name = "Blood"
	_blood.amount = 220
	_blood.lifetime = 1.1
	_blood.emitting = false
	_blood.position = _wheel_nip + Vector3(0, r * 0.5, 0)
	_blood.direction = Vector3(0, 1, 0)
	_blood.spread = 50.0
	_blood.initial_velocity_min = 3.5
	_blood.initial_velocity_max = 7.5
	_blood.gravity = Vector3(0, -9.8, 0)
	_blood.scale_amount_min = 0.8
	_blood.scale_amount_max = 2.2
	_blood.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_blood.emission_box_extents = Vector3(span * 0.3, 0.05, r * 0.3)
	var drop := SphereMesh.new()
	drop.radius = 0.045
	drop.height = 0.09
	drop.radial_segments = 6
	drop.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.02, 0.03)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.0, 0.0)
	mat.roughness = 0.3
	drop.material = mat
	_blood.mesh = drop
	_canopy.add_child(_blood)

func _turn_wheels(delta: float) -> void:
	if _wheels.is_empty() or not running:
		return
	var rate := 5.0 + 4.0 * float(not _grinding.is_empty())
	for w in _wheels:
		w.rotate_object_local(Vector3.RIGHT, float(w.get_meta("turn")) * rate * delta)

## Pieces that have dropped into the hopper: taken, whatever their size.
func _feed_hopper() -> void:
	if _hopper_area == null:
		return
	for body in Trigger.bodies_inside(_hopper_area, _hopper_shape, 0.05):
		if machine_def.mode == MachineDef.MODE_CRUSH:
			var who: Variant = (body as Node).get_meta("player") if (body as Node).has_meta("player") else body
			if who is Player:
				# Only someone actually down in the hopper is caught: not
				# someone jumping over it, or standing by its rim.
				if _in_hopper((body as Node3D).global_position):
					_catch(who as Player)
				continue
		var item := body as LooseItem
		if item == null or item.state != LooseItem.State.FREE:
			continue
		if not GameData.machine_accepts(machine_def.id, item.item_id):
			continue
		take(item)

## Down inside the hopper's mouth: within its walls, below its rims.
func _in_hopper(point: Vector3) -> bool:
	var local := _canopy.global_transform.affine_inverse() * point
	var open := hopper_opening()
	var rim := DECK_THICKNESS + canopy_height() + 0.06 + HOPPER_DEPTH
	return absf(local.x) < open * 0.5 - 0.05 and absf(local.z) < open * 0.5 - 0.05 and local.y < rim - 0.15

## Someone has fallen into the hopper: the wheels have them, and draw them
## down between them over a couple of seconds, blood flying, before they go
## through.
func _catch(who: Player) -> void:
	if _grinding.has(who) or who.crushed() or who.grinding() or who.driving():
		return
	_grinding[who] = true
	who.grind(_canopy.to_global(_wheel_nip), GRIND_SECONDS)
	Sfx.play(&"grind", global_position, 0.0, 0.8)

func _grind_step() -> void:
	if _blood != null:
		_blood.emitting = not _grinding.is_empty()
	for who in _grinding.keys():
		var p := who as Player
		if not is_instance_valid(p) or not p.grinding():
			_grinding.erase(who)
			if is_instance_valid(p) and not p.crushed():
				# Done drawing in: through he goes.
				crush_player(p)

## How many pieces of meat a player comes out as.
const MEAT_PIECES := 10

## Someone fell (or was dropped) into the crusher. He goes through; what
## comes out the far end is meat.
func crush_player(who: Player) -> void:
	if who.crushed() or who.driving():
		return
	_grinding.erase(who)
	if _blood != null:
		_blood.restart()
	who.crush(global_position + Vector3.UP * 1.5)
	var ready := _clock + canopy_length() / maxf(0.5, speed)
	for i in MEAT_PIECES:
		var size := Vector3(0.16, 0.12, 0.14) * randf_range(0.7, 1.25)
		queue.append({"id": &"meat_bits", "dims": Solid.box(size), "owned": false,
			"plot": plot_id, "changed": false, "ready": ready + 0.12 * float(i)})
	if _burst != null:
		_burst.restart()
	Sfx.play(&"squish", global_position, 2.0)
	Sfx.play(&"grind", global_position, 0.0, 0.8)

func _solid(size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	_canopy.add_child(cs)

func _dress_canopy(outer: float, run: float, h: float) -> Greeble:
	var g := Greeble.new()
	var body := machine_def.color
	var dark := Color(0.08, 0.08, 0.09)
	var steel := Color(0.55, 0.57, 0.6)
	var floor_y := DECK_THICKNESS
	var half := outer * 0.5
	# Shell: side panels, roof, and the dark inside that the belt disappears into.
	for side in [-1.0, 1.0]:
		g.box(Vector3(WALL, h, run), Transform3D(Basis(), Vector3(side * (half - WALL * 0.5), floor_y + h * 0.5, 0)), body)
		g.box(Vector3(0.02, hole.y, run - 0.1), Transform3D(Basis(), Vector3(side * (hole.x * 0.5 + 0.01), floor_y + hole.y * 0.5, 0)), dark)
		# Ribs and a bolted access panel down each side.
		var ribs := maxi(2, int(run / 0.9) + 1)
		for i in ribs:
			var z := -run * 0.5 + 0.08 + (run - 0.16) * float(i) / float(ribs - 1)
			g.box(Vector3(0.06, h + 0.1, 0.12), Transform3D(Basis(), Vector3(side * (half + 0.03), floor_y + h * 0.5, z)), body.darkened(0.3))
		g.box(Vector3(0.03, h * 0.45, run * 0.4), Transform3D(Basis(), Vector3(side * (half + 0.02), floor_y + h * 0.45, 0)), body.lightened(0.12))
		g.rivets(Vector3(side * (half + 0.04), floor_y + h * 0.7, -run * 0.2), Vector3(side * (half + 0.04), floor_y + h * 0.7, run * 0.2), 5, steel, 0.035)
	if top_loaded():
		var open := hopper_opening()
		var roof_y := floor_y + h + 0.06
		var side_w := (outer + 0.08 - open) * 0.5
		var end_l := (run + 0.08 - open) * 0.5
		for sd in [-1.0, 1.0]:
			g.box(Vector3(side_w, 0.12, run + 0.08), Transform3D(Basis(), Vector3(sd * (open * 0.5 + side_w * 0.5), roof_y, 0)), body.darkened(0.15))
			g.box(Vector3(open, 0.12, end_l), Transform3D(Basis(), Vector3(0, roof_y, sd * (open * 0.5 + end_l * 0.5))), body.darkened(0.15))
			g.box(Vector3(0.08, HOPPER_DEPTH, open + 0.16), Transform3D(Basis(), Vector3(sd * (open * 0.5 + 0.04), roof_y + HOPPER_DEPTH * 0.5, 0)), body)
			g.box(Vector3(open, HOPPER_DEPTH, 0.08), Transform3D(Basis(), Vector3(0, roof_y + HOPPER_DEPTH * 0.5, sd * (open * 0.5 + 0.04))), body)
		g.stripes(open + 0.2, 0.1, Transform3D(Basis(), Vector3(0, roof_y + HOPPER_DEPTH + 0.01, 0)))
		# The jaws, down in the dark under the hopper.
		g.box(Vector3(open, 0.02, open), Transform3D(Basis(), Vector3(0, floor_y + h * 0.5, 0)), dark)
	else:
		g.box(Vector3(outer + 0.08, 0.12, run + 0.08), Transform3D(Basis(), Vector3(0, floor_y + h + 0.06, 0)), body.darkened(0.15))
	g.box(Vector3(hole.x, 0.02, run - 0.2), Transform3D(Basis(), Vector3(0, floor_y + hole.y + 0.01, 0)), dark)
	# Mouths: a bulkhead each end with a hazard-striped frame round the hole
	# and strip curtains hanging over it.
	for end in [-1.0, 1.0]:
		var z: float = end * (run * 0.5 - WALL * 0.5)
		var face := Transform3D(Basis(Vector3.UP, 0.0 if end > 0 else PI), Vector3(0, 0, z))
		if end > 0.0 and top_loaded():
			g.box(Vector3(outer, h, WALL), face * Transform3D(Basis(), Vector3(0, floor_y + h * 0.5, 0)), body.darkened(0.1))
			continue
		var jamb := (outer - hole.x) * 0.5
		for side in [-1.0, 1.0]:
			g.box(Vector3(jamb, h, WALL), face * Transform3D(Basis(), Vector3(side * (half - jamb * 0.5), floor_y + h * 0.5, 0)), body.darkened(0.1))
		var over := h - hole.y
		if over > 0.01:
			g.box(Vector3(hole.x, over, WALL), face * Transform3D(Basis(), Vector3(0, floor_y + hole.y + over * 0.5, 0)), body.darkened(0.1))
		g.stripes(hole.x + 0.2, 0.08, face * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, floor_y + hole.y + 0.05, WALL * 0.5 + 0.01)))
		for side in [-1.0, 1.0]:
			g.box(Vector3(0.07, hole.y, 0.03), face * Transform3D(Basis(), Vector3(side * (hole.x * 0.5 + 0.04), floor_y + hole.y * 0.5, WALL * 0.5 + 0.01)), Color(0.95, 0.74, 0.16))
		# Curtains: overlapping dark strips over the top of the opening.
		var strips := maxi(3, int(hole.x / 0.16))
		for k in strips:
			var x := -hole.x * 0.5 + (float(k) + 0.5) * hole.x / float(strips)
			g.box(Vector3(hole.x / float(strips) - 0.015, hole.y * 0.55, 0.012), face * Transform3D(Basis(), Vector3(x, floor_y + hole.y * 0.72, WALL * 0.5 - 0.03)), Color(0.18, 0.2, 0.22))
	# The machine's own parts on top.
	var top := floor_y + h + 0.12
	match machine_def.mode:
		&"smelt":
			g.pipe(Vector3(0.3, top, -run * 0.2), Vector3(0.3, top + 1.6, -run * 0.2), 0.2, dark, 8)
			g.prism(8, 0.26, 0.26, 0.14, Transform3D(Basis(), Vector3(0.3, top + 1.6, -run * 0.2)), steel)
			g.box(Vector3(outer * 0.6, 0.3, run * 0.5), Transform3D(Basis(), Vector3(-0.1, top + 0.15, run * 0.1)), body.darkened(0.2))
			g.lamp(Transform3D(Basis(), Vector3(0, floor_y + 0.2, run * 0.5 + 0.05)), Color(1.0, 0.45, 0.1), 0.18)
		&"refine":
			for k in 3:
				g.prism(10, 0.18, 0.18, 0.5, Transform3D(Basis(), Vector3(-0.45 + float(k) * 0.45, top, 0)), Color(0.5, 0.75, 0.95), k == 1)
			g.pipe(Vector3(-0.45, top + 0.5, 0), Vector3(0.45, top + 0.5, 0), 0.05, steel, 6)
		&"cut":
			# A cutting head on a gantry, and a loupe lamp.
			g.box(Vector3(outer * 0.8, 0.12, 0.3), Transform3D(Basis(), Vector3(0, top + 0.5, 0)), steel)
			for x in [-outer * 0.38, outer * 0.38]:
				g.block(Vector3(0.1, 0.5, 0.1), Vector3(x, top + 0.25, 0), dark)
			g.prism(10, 0.22, 0.08, 0.35, Transform3D(Basis(), Vector3(0, top + 0.2, 0)), Color(0.75, 0.6, 1.0), true)
			g.lamp(Transform3D(Basis(), Vector3(0, floor_y + 0.2, run * 0.5 + 0.05)), Color(0.7, 0.5, 1.0), 0.16)
		&"crush":
			g.prism(12, 0.4, 0.4, 0.14, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(half + 0.1, floor_y + h * 0.55, 0)), steel)
		_:
			# Planker and sander: a motor and a drive belt guard.
			g.box(Vector3(0.6, 0.45, 0.8), Transform3D(Basis(), Vector3(-0.2, top + 0.22, -run * 0.15)), body.darkened(0.2))
			g.vent(0.5, 0.3, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.1, top + 0.22, -run * 0.15)), dark, 4)
			g.prism(10, 0.35, 0.35, 0.1, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(half + 0.08, floor_y + h * 0.6, -run * 0.15)), steel)
	return g

func _add_lamp(at: Vector3) -> void:
	var lamp := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.16, 0.16)
	lamp.mesh = bm
	lamp.position = at + Vector3(0.05, 0, 0)
	_lamp_material = StandardMaterial3D.new()
	_lamp_material.emission_enabled = true
	lamp.material_override = _lamp_material
	_canopy.add_child(lamp)
	_refresh_lamp()

func status_color() -> Color:
	if not running:
		return Color(1.0, 0.25, 0.2)
	return Color(0.35, 1.0, 0.45) if captured_count() > 0 else Color(1.0, 0.72, 0.2)

func _refresh_lamp() -> void:
	if _lamp_material == null:
		return
	var c := status_color()
	_lamp_material.albedo_color = c
	_lamp_material.emission = c
	_lamp_material.emission_energy_multiplier = 2.0

## What hides the change: sawdust, steam, sparks, dust or a furnace glow.
func _add_effects(run: float, h: float) -> void:
	var colors := {
		&"sawdust": Color(0.86, 0.72, 0.48), &"steam": Color(0.9, 0.92, 0.95, 0.6),
		&"sparks": Color(1.0, 0.72, 0.25), &"dust": Color(0.62, 0.6, 0.58), &"fire": Color(1.0, 0.45, 0.12)}
	var color: Color = colors.get(machine_def.effect, Color(0.9, 0.9, 0.9))
	var glowing := machine_def.effect == &"sparks" or machine_def.effect == &"fire"
	for end in [-1.0, 1.0]:
		var p := _particles(color, glowing, 14)
		p.position = Vector3(0, DECK_THICKNESS + hole.y * 0.5, end * run * 0.5)
		p.direction = Vector3(0, 0.6, end)
		_canopy.add_child(p)
		_ambient.append(p)
	_burst = _particles(color, glowing, 40)
	_burst.one_shot = true
	_burst.emitting = false
	_burst.explosiveness = 0.9
	_burst.position = Vector3(0, DECK_THICKNESS + hole.y * 0.5, -run * 0.5)
	_burst.direction = Vector3(0, 0.5, -1)
	_canopy.add_child(_burst)
	if glowing:
		_glow = OmniLight3D.new()
		_glow.light_color = color
		_glow.light_energy = 1.6
		_glow.omni_range = 3.2
		_glow.position = Vector3(0, DECK_THICKNESS + h * 0.5, 0)
		_canopy.add_child(_glow)

func _particles(color: Color, glowing: bool, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.9
	p.spread = 35.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -2.0 if not glowing else -4.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(hole.x * 0.4, hole.y * 0.3, 0.05)
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.05
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	if glowing:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 3.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	p.mesh = mesh
	return p

# --- Working -------------------------------------------------------------------

## What the machine does with what goes in: a piece that gets through the
## in-feed mouth is taken off the belt altogether and becomes an entry in the
## queue - already changed into whatever it comes out as - and each entry is
## set down on the out-feed lip once its time in the tunnel is up and there
## is room for it there. Nothing rides through the inside, so nothing can
## jam in there; a busy out-feed just holds the queue up.

## How far into the mouth a piece has to get before it is taken in: well in,
## so it is plainly through the opening (all of it, if it is shorter).
const MOUTH_DEPTH := 0.5

## Entries waiting inside: {id, dims, owned, plot, changed, ready}.
var queue: Array[Dictionary] = []
## Pieces that have come out of the far end, and the last one.
var total_out: int = 0
var last_out: LooseItem = null
var _clock: float = 0.0

signal emerged(machine: InlineMachine, item: LooseItem)

func captured_count() -> int:
	return _riding.size() + queue.size()

func _physics_process(delta: float) -> void:
	super(delta)
	_clock += delta
	_turn_wheels(delta)
	if not _grinding.is_empty() or (_blood != null and _blood.emitting):
		_grind_step()
	if running:
		if top_loaded():
			_feed_hopper()
		else:
			for item in _riding.keys():
				if is_instance_valid(item) and item.state == LooseItem.State.FREE and _in_mouth(item):
					take(item)
		_release()
	var busy := running and not queue.is_empty()
	for p in _ambient:
		p.emitting = busy
	if _glow != null:
		_glow.light_energy = 1.6 if running else 0.3
	_refresh_lamp()

## Has the front of this piece got into the in-feed mouth? A piece too big
## for the mouth never does: it is stopped at the bulkhead. (The crusher is
## fed through its hopper instead.)
func _in_mouth(item: LooseItem) -> bool:
	var inverse := global_transform.affine_inverse()
	var local := inverse * item.global_position
	# Only what is coming in: what the machine has set down is on the far side.
	if local.z < 0.0:
		return false
	# No size rule beyond the opening itself: the bulkhead stops what is too
	# big, and whatever has got well into the tunnel is taken and worked.
	var reach := item.extent_along(global_transform.basis.z)
	var depth := minf(MOUTH_DEPTH, reach * 2.0)
	return local.z - reach < canopy_length() * 0.5 - depth and absf(local.x) < hole.x * 0.5 + 0.2

## Would this piece, lying as it lies, pass through the opening?
func fits_mouth(item: LooseItem) -> bool:
	var across := item.extent_along(global_transform.basis.x) * 2.0
	var up := item.extent_along(global_transform.basis.y) * 2.0
	if across <= hole.x + 0.02 and up <= hole.y + 0.02:
		return true
	# A long piece coming in a little crooked is squared up by the mouth's
	# sides as it enters: what counts is its own cross-section.
	var long_axis := item.global_transform.basis.y.normalized()
	if absf(long_axis.dot(global_transform.basis.z)) < cos(0.7):
		return false
	var size := Solid.bounds(item.dims)
	if item.dims.get("shape", Solid.BOX) == Solid.CYLINDER:
		var d := Solid.max_radius(item.dims) * 2.0
		return d <= minf(hole.x, hole.y) + 0.02
	var a := minf(size.x, size.z)
	var b := maxf(size.x, size.z)
	return (b <= hole.x + 0.02 and a <= hole.y + 0.02)

## Takes a piece off the belt into the machine. Returns true if it went in.
func take(item: LooseItem) -> bool:
	if manager == null or item == null or item.state != LooseItem.State.FREE:
		return false
	var entry := {"id": item.item_id, "dims": item.dims.duplicate(true), "owned": true,
		"plot": item.plot_id, "changed": false,
		"ready": _clock + canopy_length() / maxf(0.5, speed)}
	# Branches still on a trunk that got through the mouth come off inside
	# and follow it out, each a piece of its own.
	var branches: Array[Dictionary] = []
	for i in item.limbs.size():
		branches.append({"id": item.item_id, "dims": item.limb_dims(i), "owned": true,
			"plot": item.plot_id, "changed": false, "ready": float(entry.ready) + 0.05 * float(i + 1)})
	_riding.erase(item)
	manager.despawn(item)
	var before := Solid.volume(entry.dims)
	var outs := work(entry)
	if machine_def.mode == MachineDef.MODE_PLANK and bool(entry.changed) and not branches.is_empty():
		# The planker takes the branches with the trunk: their wood goes into
		# the one plank, at the same yield, which comes out broader and thicker.
		var extra := 0.0
		for branch in branches:
			extra += Solid.volume(branch.dims)
		var grow := sqrt(1.0 + extra / before)
		before += extra
		var size: Vector3 = entry.dims.size
		entry.dims.size = Vector3(size.x * grow, size.y, size.z * grow)
		branches.clear()
	for branch in branches:
		before += Solid.volume(branch.dims)
		outs.append_array(work(branch))
	outs = _cut_to_size(outs)
	if outs.any(func(o: Dictionary) -> bool: return bool(o.changed)):
		var after := 0.0
		for o: Dictionary in outs:
			after += Solid.volume(o.dims)
		volume_in += before
		volume_out += after
		total_processed += 1
	queue.append_array(outs)
	if _burst != null:
		_burst.restart()
	Sfx.play(&"grind", global_position, -6.0)
	return true

## Sets the next finished entry down on the out-feed lip, if there is room.
func _release() -> void:
	if queue.is_empty() or float(queue[0].ready) > _clock:
		return
	var entry: Dictionary = queue[0]
	var xform := exit_transform(entry.dims)
	var on_belt := exit_clear(entry.dims, xform)
	# With nothing after the machine to carry things off, it tips them out
	# on the ground past its end instead - a few of them, until that fills.
	if not on_belt:
		if fed_onward():
			return
		var spot: Variant = ground_spot(entry.dims)
		if spot == null:
			return
		xform = spot
	queue.pop_front()
	var item := manager.spawn(entry.id, xform, int(entry.plot), Vector3.ZERO, entry.dims, bool(entry.owned))
	if item == null:
		return
	item.linear_velocity = belt_velocity() if on_belt else Vector3.ZERO
	total_out += 1
	last_out = item
	emerged.emit(self, item)
	if bool(entry.changed):
		processed.emit(self, item)

## Where a piece of this shape comes out: lying down the belt, broad face
## up, its back end just clear of the out-feed bulkhead.
func exit_transform(dims: Dictionary) -> Transform3D:
	var b := Solid.bounds(dims)
	var local := Vector3(0, DECK_THICKNESS + b.z * 0.5 + 0.03, -canopy_length() * 0.5 - b.y * 0.5 - 0.05)
	return Transform3D(_along_belt(), global_transform * local)

## Is there a belt, bin or machine right after this one's out-feed?
func fed_onward() -> bool:
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.3, 0.4)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = global_transform * Transform3D(Basis(), Vector3(0, DECK_THICKNESS, -length * 0.5 - 0.35))
	q.collision_mask = Layers.MACHINE
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 4):
		if hit.collider != _deck and hit.collider != _canopy:
			return true
	return false

## A clear patch of ground past the out-feed end to set a piece down on: the
## middle first, then either side, then a row further out. Null if all full.
func ground_spot(dims: Dictionary) -> Variant:
	var b := Solid.bounds(dims)
	var space := get_world_3d().direct_space_state
	for row in 2:
		for lane in [0, -1, 1]:
			var local := Vector3(float(lane) * (b.x + 0.35), 0.0,
				-length * 0.5 - b.y * 0.5 - 0.4 - float(row) * (b.y + 0.4))
			var top := global_transform * (local + Vector3(0, 3.0, 0))
			var ray := PhysicsRayQueryParameters3D.create(top, top - global_transform.basis.y * 8.0, Layers.WORLD)
			var hit := space.intersect_ray(ray)
			if hit.is_empty():
				continue
			var at: Vector3 = hit.position + global_transform.basis.y.normalized() * (b.z * 0.5 + 0.1)
			var xform := Transform3D(_along_belt(), at)
			if exit_clear(dims, xform, Layers.MACHINE | Layers.TREE):
				return xform
	return null

## Is there room at the exit for it? Anything loose in the way holds it back.
func exit_clear(dims: Dictionary, xform: Transform3D, also: int = 0) -> bool:
	var box := BoxShape3D.new()
	box.size = Solid.bounds(dims) + Vector3.ONE * 0.06
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = xform
	q.collision_mask = Layers.LOOSE | Layers.PLAYER | Layers.VEHICLE | also
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

## The longest sheet of glass the refiner turns out, metres.
const GLASS_PANE := 1.2

## Does this machine's job to one entry. Returns what comes out - one entry,
## or several for the crusher - each marked `changed` if the machine did
## anything to it.
func work(entry: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = [entry]
	if not GameData.machine_accepts(machine_def.id, entry.id):
		return out
	# Harder materials need a better machine: a level-3 wood goes through a
	# T1 or T2 planker untouched. The crusher only breaks rock up, any rock.
	if machine_def.mode != MachineDef.MODE_CRUSH and not tier_fits(entry.id):
		too_hard = GameData.item_name(entry.id)
		return out
	var def_in := GameData.item(entry.id)
	var category: StringName = def_in.category if def_in != null else &""
	var dims: Dictionary = entry.dims
	match machine_def.mode:
		MachineDef.MODE_PLANK:
			var to := machine_def.output_for(entry.id)
			# Planks are only ever cut from sanded logs: an unsanded log goes
			# through untouched - sand it first.
			if category == &"wood" and dims.get("shape", Solid.BOX) == Solid.CYLINDER and to != &"" \
					and Solid.has_finish(dims, &"sanded"):
				# All of the log's wood, as one broad plank.
				var r := (float(dims.r0) + float(dims.r1)) * 0.5
				var run := Solid.length_of(dims)
				var wide := r * 2.6
				var thick := Solid.volume(dims) / maxf(0.001, run * wide)
				_change(entry, to, Solid.keep_finish(dims, Solid.box(Vector3(wide, run, thick))))
		MachineDef.MODE_SAND:
			# Stone is polished rather than sanded: same belt, finer grit. A
			# cut jewel is finished already and goes through as it is.
			var finish := &"polished" if category == &"gem" else &"sanded"
			if category != &"jewel" and not Solid.has_finish(dims, finish):
				_change(entry, entry.id, Solid.with_finish(dims, finish))
		MachineDef.MODE_REFINE:
			var into := machine_def.output_for(entry.id)
			if into != &"":
				# Sandstone melts down into glass: sheets 5 cm thick.
				var v := Solid.volume(dims)
				var cs: Vector3 = Solid.bounds(GameData.item(into).default_dims())
				var run := v / maxf(0.0001, cs.x * cs.z)
				var count := clampi(int(ceil(run / GLASS_PANE)), 1, 128)
				_change(entry, into, Solid.box(Vector3(cs.x, run / float(count), cs.z)))
				for i in range(1, count):
					var more := entry.duplicate(true)
					more.ready = float(entry.ready) + 0.05 * float(i)
					out.append(more)
			elif not Solid.has_finish(dims, &"refined"):
				_change(entry, entry.id, Solid.with_finish(dims, &"refined"))
		MachineDef.MODE_CUT:
			var to := machine_def.output_for(entry.id)
			# A polished stone has had its finish: it is sold as it is, not cut
			# as well. Only rough goes under the cutting head.
			if to != &"" and not Solid.has_finish(dims, &"polished"):
				# Volume of a frustum r0 -> r0/2 over 0.9 r0 is 1.649 r0^3.
				var r0 := pow(Solid.volume(dims) * machine_def.yield_share / 1.649, 1.0 / 3.0)
				_change(entry, to, Solid.cylinder(r0, r0 * 0.5, r0 * 0.9))
		MachineDef.MODE_SMELT:
			var to := machine_def.output_for(entry.id)
			if to != &"":
				var t := pow(Solid.volume(dims) * machine_def.yield_share / 6.4, 1.0 / 3.0)
				_change(entry, to, Solid.box(Vector3(t * 1.6, t * 4.0, t)))
		MachineDef.MODE_CRUSH:
			# Whatever fits through the mouth is broken up, however small -
			# into lumps no bigger than max_piece (less, set finer), and at
			# least two. Only its own lumps go through untouched.
			if not bool(dims.get("crushed", false)):
				var v := Solid.volume(dims)
				var side := machine_def.max_piece * 0.9
				var want := setting(&"max_cm") / 100.0
				if want > 0.0:
					side = minf(side, want)
				var count := clampi(int(ceil(v / pow(side, 3.0))), 2, 128)
				var lump := Solid.cube(v / float(count))
				lump["crushed"] = true
				_change(entry, entry.id, lump)
				for i in range(1, count):
					var more := entry.duplicate(true)
					more.ready = float(entry.ready) + 0.05 * float(i)
					out.append(more)
	return out

## Set to a size: what it made is cut to it.
func _cut_to_size(outs: Array[Dictionary]) -> Array[Dictionary]:
	var split: Array[Dictionary] = []
	for e in outs:
		if bool(e.changed):
			split.append_array(_shape_output(e))
		else:
			split.append(e)
	return split

# --- Output size ---------------------------------------------------------------

## What can be set, as [key, label, min, max, step] in centimetres. The
## minimum, 0, means "as it comes".
func config_fields() -> Array:
	if machine_def == null:
		return []
	# Anything up to what the out-feed opening passes: short, fat bricks
	# included.
	var wide := int(floor(hole.x * 100.0))
	var tall := int(floor(hole.y * 100.0))
	match machine_def.mode:
		MachineDef.MODE_PLANK:
			return [[&"width_cm", "Board width", 0, wide, 1], [&"thick_cm", "Board thickness", 0, tall, 1]]
		MachineDef.MODE_CRUSH:
			return [[&"max_cm", "Largest lump", 0, int(machine_def.max_piece * 90.0), 1]]
		MachineDef.MODE_SMELT:
			return [[&"section_cm", "Bar thickness", 0, mini(int(floor(hole.x * 100.0 / 1.6)), tall), 1]]
		MachineDef.MODE_REFINE:
			return [[&"section_cm", "Cross-section", 0, mini(wide, tall), 1]]
		MachineDef.MODE_CUT:
			return [[&"jewel_cm", "Jewel size", 0, mini(wide, tall), 1]]
	return []

func setting(key: StringName) -> float:
	return float(config.get(key, 0.0))

## Sets one size (in cm; 0 for as it comes). Returns what it is set to now.
func set_setting(key: StringName, cm: float) -> String:
	for f in config_fields():
		if f[0] == key:
			config[key] = clampf(cm, float(f[2]), float(f[3]))
			return "%s: %s" % [def.display_name, output_label()]
	return ""

## The settings in words.
func output_label() -> String:
	var parts: Array[String] = []
	for f in config_fields():
		var v := setting(f[0])
		parts.append("%s %s" % [String(f[1]).to_lower(), ("%d cm" % int(v)) if v > 0.0 else "as it comes"])
	return ", ".join(parts)

## Cuts one finished entry to the sizes set, the way the machine would -
## boards side by side and stacked, bars and refined stock to a cross-section,
## jewels to a size. Volume and finish are kept exactly.
func _shape_output(entry: Dictionary) -> Array[Dictionary]:
	var dims: Dictionary = entry.dims
	var v := Solid.volume(dims)
	var n := 1
	var each: Dictionary = {}
	var leftover: Array[Dictionary] = []
	match machine_def.mode:
		MachineDef.MODE_PLANK:
			var sz: Vector3 = dims.size
			var w := setting(&"width_cm") / 100.0
			var t := setting(&"thick_cm") / 100.0
			# Boards are exactly the size set, across and through; the
			# length is what the wood makes of it - a big board from a thin
			# log comes out short.
			if w > 0.0 and t > 0.0:
				n = maxi(1, int(floor(sz.x * sz.z / (w * t))))
				each = Solid.box(Vector3(w, v / (float(n) * w * t), t))
			elif w > 0.0:
				n = maxi(1, int(floor(sz.x / w)))
				each = Solid.box(Vector3(w, v / (float(n) * w * sz.z), sz.z))
			elif t > 0.0:
				n = maxi(1, int(floor(sz.z / t)))
				each = Solid.box(Vector3(sz.x, v / (float(n) * sz.x * t), t))
		MachineDef.MODE_SMELT:
			var t := setting(&"section_cm") / 100.0
			if t > 0.0:
				var run := v / (1.6 * t * t)
				n = maxi(1, int(ceil(run / MAX_BAR)))
				each = Solid.box(Vector3(t * 1.6, run / float(n), t))
		MachineDef.MODE_REFINE:
			var t := setting(&"section_cm") / 100.0
			# Glass comes out as sheets whatever the bar size is set to.
			if t > 0.0 and machine_def.output_for(entry.id) == &"" and GameData.item(entry.id).category != &"glass":
				var run := v / (t * t)
				n = maxi(1, int(ceil(run / MAX_BAR)))
				each = Solid.box(Vector3(t, run / float(n), t))
		MachineDef.MODE_CUT:
			var size := setting(&"jewel_cm") / 100.0
			if size > 0.0:
				# Jewels of exactly the size set; what is left over too small
				# for one more is cut as one smaller stone.
				var r0 := size * 0.5
				var one := 1.649 * r0 * r0 * r0
				n = clampi(int(floor(v / one)), 0, 64)
				if n == 0:
					var rs := pow(v / 1.649, 1.0 / 3.0)
					each = Solid.cylinder(rs, rs * 0.5, rs * 0.9)
					n = 1
				else:
					each = Solid.cylinder(r0, r0 * 0.5, r0 * 0.9)
					var rest := v - one * float(n)
					if rest > one * 0.05:
						var rr := pow(rest / 1.649, 1.0 / 3.0)
						var extra := entry.duplicate(true)
						extra.dims = Solid.keep_finish(dims, Solid.cylinder(rr, rr * 0.5, rr * 0.9))
						extra.ready = float(entry.ready) + 0.05 * float(n)
						leftover.append(extra)
	var out: Array[Dictionary] = []
	if each.is_empty():
		out.append(entry)
		return out
	Solid.keep_finish(dims, each)
	for i in n:
		var piece := entry.duplicate(true)
		piece.dims = each.duplicate(true)
		piece.ready = float(entry.ready) + 0.05 * float(i)
		out.append(piece)
	out.append_array(leftover)
	return out

func _change(entry: Dictionary, id: StringName, dims: Dictionary) -> void:
	entry.id = id
	entry.dims = dims
	entry.changed = true

## A basis with the piece's long axis (+Y) down the belt and its broad face up.
func _along_belt() -> Basis:
	var up := global_transform.basis.y.normalized()
	var along := -global_transform.basis.z.normalized()
	return Basis(along.cross(up).normalized(), along, up).orthonormalized()

## Whether this machine's tier is up to working a material.
func tier_fits(item_id: StringName) -> bool:
	return level >= GameData.material_level(item_id)

func status_line() -> String:
	var line := "%s (%s): %s, %d through  [E] %s" % [def.display_name, tier_label(),
		"running" if running else "stopped", total_processed, "stop" if running else "start"]
	if too_hard != "":
		line += "\n%s passed through untouched - it needs a higher tier" % too_hard
	if not config_fields().is_empty():
		line += "\n%s  [R] set sizes" % output_label()
	return line

func to_dict() -> Dictionary:
	var held: Array = []
	for e in queue:
		held.append({"id": String(e.id), "dims": Solid.to_dict(e.dims), "owned": e.owned,
			"plot": e.plot, "changed": e.changed})
	return {"running": running, "total_processed": total_processed, "queue": held, "config": config.duplicate()}

func from_dict(d: Dictionary) -> void:
	running = bool(d.get("running", true))
	total_processed = int(d.get("total_processed", 0))
	config.clear()
	var c: Dictionary = d.get("config", {})
	for k in c:
		config[StringName(k)] = float(c[k])
	queue.clear()
	for e in d.get("queue", []):
		queue.append({"id": StringName(e.id), "dims": Solid.from_dict(e.dims), "owned": bool(e.get("owned", true)),
			"plot": int(e.get("plot", plot_id)), "changed": bool(e.get("changed", false)), "ready": 0.0})
