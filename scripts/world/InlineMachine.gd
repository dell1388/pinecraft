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
## comes out as it went in, so machines chain on one line. A piece still on
## its branches is not taken: limb it first.

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
	speed = machine_def.belt_speed * float(stats.get("rate_scale", 1.0))

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
	_solid(Vector3(outer, 0.12, run), Vector3(0, floor_y + h + 0.06, 0))
	# Inside, a duct exactly the size of the mouths, from one bulkhead to the
	# other. With room to spare in there, pieces wandered off the line -
	# sideways, or up on top of each other - and fetched up against the out
	# bulkhead beside the opening, where the belt could never free them.
	var duct := run - WALL * 2.0
	for side in [-1.0, 1.0]:
		_solid(Vector3(WALL, hole.y, duct), Vector3(side * (hole.x * 0.5 + WALL * 0.5), floor_y + hole.y * 0.5, 0))
	if h - hole.y > 0.01:
		_solid(Vector3(hole.x, WALL, duct), Vector3(0, floor_y + hole.y + WALL * 0.5, 0))
	# The bulkheads at each end, with the mouth cut out of them.
	for end in [-1.0, 1.0]:
		var z: float = end * (run * 0.5 - WALL * 0.5)
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
	if hole.x < width - 0.1:
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
	g.box(Vector3(outer + 0.08, 0.12, run + 0.08), Transform3D(Basis(), Vector3(0, floor_y + h + 0.06, 0)), body.darkened(0.15))
	g.box(Vector3(hole.x, 0.02, run - 0.2), Transform3D(Basis(), Vector3(0, floor_y + hole.y + 0.01, 0)), dark)
	# Mouths: a bulkhead each end with a hazard-striped frame round the hole
	# and strip curtains hanging over it.
	for end in [-1.0, 1.0]:
		var z: float = end * (run * 0.5 - WALL * 0.5)
		var face := Transform3D(Basis(Vector3.UP, 0.0 if end > 0 else PI), Vector3(0, 0, z))
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
			g.wedge(Vector3(outer * 0.7, 0.5, run * 0.5), Transform3D(Basis(), Vector3(0, top + 0.25, 0)), body.darkened(0.25))
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

const MOUTH_DEPTH := 0.1          ## how far into the mouth a piece has to get

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
	if running:
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
## for the mouth never does: it is stopped at the bulkhead.
func _in_mouth(item: LooseItem) -> bool:
	if not item.limbs.is_empty():
		return false
	var inverse := global_transform.affine_inverse()
	var local := inverse * item.global_position
	# Only what is coming in: what the machine has set down is on the far side.
	if local.z < 0.0:
		return false
	var axis := inverse.basis * item.global_transform.basis.y.normalized()
	var reach := absf(axis.normalized().z) * item.length() * 0.5
	var b := Solid.bounds(item.dims)
	reach += maxf(b.x, b.z) * 0.5 * sqrt(maxf(0.0, 1.0 - axis.normalized().z * axis.normalized().z))
	return local.z - reach < canopy_length() * 0.5 - MOUTH_DEPTH and absf(local.x) < hole.x * 0.5 + 0.2

## Takes a piece off the belt into the machine. Returns true if it went in.
func take(item: LooseItem) -> bool:
	if manager == null or item == null or item.state != LooseItem.State.FREE:
		return false
	var entry := {"id": item.item_id, "dims": item.dims.duplicate(true), "owned": true,
		"plot": item.plot_id, "changed": false,
		"ready": _clock + canopy_length() / maxf(0.5, speed)}
	_riding.erase(item)
	manager.despawn(item)
	var outs := work(entry)
	if bool(outs[0].changed):
		var before := Solid.volume(entry.dims)
		var after := 0.0
		for o: Dictionary in outs:
			after += Solid.volume(o.dims)
		volume_in += before
		volume_out += after
		total_processed += 1
	queue.append_array(outs)
	if _burst != null:
		_burst.restart()
	return true

## Sets the next finished entry down on the out-feed lip, if there is room.
func _release() -> void:
	if queue.is_empty() or float(queue[0].ready) > _clock:
		return
	var entry: Dictionary = queue[0]
	var xform := exit_transform(entry.dims)
	if not exit_clear(entry.dims, xform):
		return
	queue.pop_front()
	var item := manager.spawn(entry.id, xform, int(entry.plot), Vector3.ZERO, entry.dims, bool(entry.owned))
	if item == null:
		return
	item.linear_velocity = belt_velocity()
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

## Is there room at the exit for it? Anything loose in the way holds it back.
func exit_clear(dims: Dictionary, xform: Transform3D) -> bool:
	var box := BoxShape3D.new()
	box.size = Solid.bounds(dims) + Vector3.ONE * 0.06
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = xform
	q.collision_mask = Layers.LOOSE | Layers.PLAYER | Layers.VEHICLE
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

## Does this machine's job to one entry. Returns what comes out - one entry,
## or several for the crusher - each marked `changed` if the machine did
## anything to it.
func work(entry: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = [entry]
	if not GameData.machine_accepts(machine_def.id, entry.id):
		return out
	var def_in := GameData.item(entry.id)
	var category: StringName = def_in.category if def_in != null else &""
	var dims: Dictionary = entry.dims
	match machine_def.mode:
		MachineDef.MODE_PLANK:
			var to := machine_def.output_for(entry.id)
			if category == &"wood" and dims.get("shape", Solid.BOX) == Solid.CYLINDER and to != &"":
				var r := (float(dims.r0) + float(dims.r1)) * 0.5
				_change(entry, to, Solid.keep_finish(dims, Solid.box(Vector3(r * 1.8, Solid.length_of(dims), r * 0.8))))
		MachineDef.MODE_SAND:
			# Stone is polished rather than sanded: same belt, finer grit.
			var finish := &"polished" if category == &"gem" or category == &"jewel" else &"sanded"
			if not Solid.has_finish(dims, finish):
				_change(entry, entry.id, Solid.with_finish(dims, finish))
		MachineDef.MODE_REFINE:
			if not Solid.has_finish(dims, &"refined"):
				_change(entry, entry.id, Solid.with_finish(dims, &"refined"))
		MachineDef.MODE_CUT:
			var to := machine_def.output_for(entry.id)
			if to != &"":
				# Volume of a frustum r0 -> r0/2 over 0.9 r0 is 1.649 r0^3.
				var r0 := pow(Solid.volume(dims) * machine_def.yield_share / 1.649, 1.0 / 3.0)
				_change(entry, to, Solid.keep_finish(dims, Solid.cylinder(r0, r0 * 0.5, r0 * 0.9)))
		MachineDef.MODE_SMELT:
			var to := machine_def.output_for(entry.id)
			if to != &"":
				var t := pow(Solid.volume(dims) * machine_def.yield_share / 6.4, 1.0 / 3.0)
				_change(entry, to, Solid.box(Vector3(t * 1.6, t * 4.0, t)))
		MachineDef.MODE_CRUSH:
			var b := Solid.bounds(dims)
			if maxf(b.x, maxf(b.y, b.z)) > machine_def.max_piece + 0.001:
				var v := Solid.volume(dims)
				var count := clampi(int(ceil(v / pow(machine_def.max_piece * 0.9, 3.0))), 2, 64)
				var lump := Solid.cube(v / float(count))
				_change(entry, entry.id, lump)
				for i in range(1, count):
					var more := entry.duplicate(true)
					more.ready = float(entry.ready) + 0.05 * float(i)
					out.append(more)
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

func status_line() -> String:
	return "%s (%s): %s, %d through  [E] %s" % [def.display_name, tier_label(),
		"running" if running else "stopped", total_processed, "stop" if running else "start"]

func to_dict() -> Dictionary:
	var held: Array = []
	for e in queue:
		held.append({"id": String(e.id), "dims": Solid.to_dict(e.dims), "owned": e.owned,
			"plot": e.plot, "changed": e.changed})
	return {"running": running, "total_processed": total_processed, "queue": held}

func from_dict(d: Dictionary) -> void:
	running = bool(d.get("running", true))
	total_processed = int(d.get("total_processed", 0))
	queue.clear()
	for e in d.get("queue", []):
		queue.append({"id": StringName(e.id), "dims": Solid.from_dict(e.dims), "owned": bool(e.get("owned", true)),
			"plot": int(e.get("plot", plot_id)), "changed": bool(e.get("changed", false)), "ready": 0.0})
