class_name InlineMachine
extends Conveyor

## A processing machine you run material *through*: a belt with a tunnel over
## the middle of it, like a curing oven on a production line. Pieces ride in
## one mouth on the belt, are changed as they pass the middle of the tunnel,
## and ride out of the other mouth on the same belt.
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
## rides straight through, so machines chain on one line. The change itself is
## hidden inside the tunnel, behind strip curtains and the machine's own
## smoke, sparks or sawdust.

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
var _last_z: Dictionary = {}          ## LooseItem -> local z last frame
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
	PlayerState.upgraded.connect(_on_upgraded)

## Tiers widen the mouth and speed the belt.
func _apply_level() -> void:
	level = PlayerState.level(machine_def.id)
	var hole_scale := PlayerState.stat(machine_def.id, "hole_scale", 1.0)
	var outer := float(def.size.x) * Plot.CELL
	hole = Vector2(minf(machine_def.tunnel.x * hole_scale, outer - WALL * 2.0 - 0.1),
		minf(machine_def.tunnel.y * hole_scale, float(def.size.y) * Plot.CELL - 0.9))
	speed = machine_def.belt_speed * PlayerState.stat(machine_def.id, "rate_scale", 1.0)

func _on_upgraded(track: StringName, _level: int) -> void:
	if machine_def == null or track != machine_def.id:
		return
	_apply_level()
	for n in _canopy_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_canopy_nodes.clear()
	_ambient.clear()
	_burst = null
	_glow = null
	_lamp_material = null
	_build_canopy()

func tier_label() -> String:
	return PlayerState.label(machine_def.id)

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
	# The bulkheads at each end, with the mouth cut out of them.
	for end in [-1.0, 1.0]:
		var z: float = end * (run * 0.5 - WALL * 0.5)
		var jamb := (outer - hole.x) * 0.5
		for side in [-1.0, 1.0]:
			_solid(Vector3(jamb, h, WALL), Vector3(side * (half - jamb * 0.5), floor_y + h * 0.5, z))
		var over := h - hole.y
		if over > 0.01:
			_solid(Vector3(hole.x, over, WALL), Vector3(0, floor_y + hole.y + over * 0.5, z))
	var mesh := _dress_canopy(outer, run, h).instance("Tunnel")
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
		g.box(Vector3(0.02, h - 0.05, run - 0.1), Transform3D(Basis(), Vector3(side * (half - WALL - 0.01), floor_y + h * 0.5, 0)), dark)
		# Ribs and a bolted access panel down each side.
		var ribs := maxi(2, int(run / 0.9) + 1)
		for i in ribs:
			var z := -run * 0.5 + 0.08 + (run - 0.16) * float(i) / float(ribs - 1)
			g.box(Vector3(0.06, h + 0.1, 0.12), Transform3D(Basis(), Vector3(side * (half + 0.03), floor_y + h * 0.5, z)), body.darkened(0.3))
		g.box(Vector3(0.03, h * 0.45, run * 0.4), Transform3D(Basis(), Vector3(side * (half + 0.02), floor_y + h * 0.45, 0)), body.lightened(0.12))
		g.rivets(Vector3(side * (half + 0.04), floor_y + h * 0.7, -run * 0.2), Vector3(side * (half + 0.04), floor_y + h * 0.7, run * 0.2), 5, steel, 0.035)
	g.box(Vector3(outer + 0.08, 0.12, run + 0.08), Transform3D(Basis(), Vector3(0, floor_y + h + 0.06, 0)), body.darkened(0.15))
	g.box(Vector3(outer - 0.3, 0.02, run - 0.2), Transform3D(Basis(), Vector3(0, floor_y + h - 0.01, 0)), dark)
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

func _physics_process(delta: float) -> void:
	super(delta)
	var inverse := global_transform.affine_inverse()
	for item in _riding.keys():
		if not is_instance_valid(item) or item.state != LooseItem.State.FREE:
			_last_z.erase(item)
			continue
		var z: float = (inverse * item.global_position).z
		var was: float = _last_z.get(item, z)
		_last_z[item] = z
		# The belt runs toward -Z: the change happens as a piece crosses the
		# middle of the tunnel, out of sight.
		if was > 0.0 and z <= 0.0:
			work_on(item)
	for item in _last_z.keys():
		if not _riding.has(item):
			_last_z.erase(item)
	for p in _ambient:
		p.emitting = running and captured_count() > 0
	if _glow != null:
		_glow.light_energy = 1.6 if running else 0.3
	_refresh_lamp()

## Does this machine's job to one piece, if it is a piece it works on.
## Returns true when it changed something.
func work_on(item: LooseItem) -> bool:
	if manager == null or item == null or not GameData.machine_accepts(machine_def.id, item.item_id):
		return false
	var before := item.volume()
	var changed := false
	match machine_def.mode:
		MachineDef.MODE_PLANK:
			changed = _plank(item)
		MachineDef.MODE_SAND:
			# Stone is polished rather than sanded: same belt, finer grit.
			var stone := item.category == &"gem" or item.category == &"jewel"
			changed = _finish(item, &"polished" if stone else &"sanded")
		MachineDef.MODE_CUT:
			changed = _cut(item)
		MachineDef.MODE_REFINE:
			changed = _finish(item, &"refined")
		MachineDef.MODE_SMELT:
			changed = _smelt(item)
		MachineDef.MODE_CRUSH:
			changed = _crush(item)
	if not changed:
		return false
	volume_in += before
	volume_out += item.volume()
	total_processed += 1
	item.owned = true
	if _burst != null:
		_burst.restart()
	processed.emit(self, item)
	return true

## Swaps what a piece is while keeping it the same physics body: same place,
## same speed, new shape and material.
func _become(item: LooseItem, new_id: StringName, dims: Dictionary) -> void:
	var def_out := GameData.item(new_id)
	var velocity := item.linear_velocity
	var owned := item.owned
	item.configure(def_out, dims)
	item.owned = owned
	item.linear_velocity = velocity

## A log becomes one plank: as long as the log, as wide as the log allows
## (1.8 radii) and thick (0.8 radii). The slabs and sawdust are the waste.
func _plank(item: LooseItem) -> bool:
	if item.category != &"wood" or item.dims.get("shape", Solid.BOX) != Solid.CYLINDER:
		return false
	var out := machine_def.output_for(item.item_id)
	if out == &"":
		return false
	var r := (float(item.dims.r0) + float(item.dims.r1)) * 0.5
	var plank := Solid.keep_finish(item.dims, Solid.box(Vector3(r * 1.8, item.length(), r * 0.8)))
	# Lay it flat along the log's run, broad face up.
	var up := global_transform.basis.y.normalized()
	var along := item.global_transform.basis.y.normalized()
	along = (along - up * along.dot(up)).normalized()
	if along.length() < 0.5:
		along = -global_transform.basis.z.normalized()
	var basis := Basis(along.cross(up).normalized(), along, up)
	var pos := item.global_position
	_become(item, out, plank)
	item.teleport(Transform3D(basis, pos))
	item.linear_velocity = belt_velocity()
	return true

func _finish(item: LooseItem, finish: StringName) -> bool:
	if Solid.has_finish(item.dims, finish):
		return false
	_become(item, item.item_id, Solid.with_finish(item.dims, finish))
	return true

## Ore becomes a bar, keeping `yield_share` of its volume.
func _smelt(item: LooseItem) -> bool:
	var out := machine_def.output_for(item.item_id)
	if out == &"":
		return false
	var v := item.volume() * machine_def.yield_share
	var t := pow(v / 6.4, 1.0 / 3.0)
	_become(item, out, Solid.box(Vector3(t * 1.6, t * 4.0, t)))
	return true

## A rough stone becomes one faceted jewel - a squat, eight-sided crown -
## keeping `yield_share` of its volume. The polish, if it had one, stays.
func _cut(item: LooseItem) -> bool:
	var out := machine_def.output_for(item.item_id)
	if out == &"":
		return false
	var v := item.volume() * machine_def.yield_share
	# Volume of a frustum r0 -> r0/2 over 0.9 r0 is 1.649 r0^3.
	var r0 := pow(v / 1.649, 1.0 / 3.0)
	var jewel := Solid.keep_finish(item.dims, Solid.cylinder(r0, r0 * 0.5, r0 * 0.9))
	_become(item, out, jewel)
	return true

## A chunk bigger than `max_piece` comes out as several lumps that are not.
func _crush(item: LooseItem) -> bool:
	var b := Solid.bounds(item.dims)
	if maxf(b.x, maxf(b.y, b.z)) <= machine_def.max_piece + 0.001:
		return false
	var v := item.volume()
	var count := int(ceil(v / pow(machine_def.max_piece * 0.9, 3.0)))
	count = clampi(count, 2, 64)
	var lump := Solid.cube(v / float(count))
	var at := item.global_position
	var id := item.item_id
	var velocity := belt_velocity()
	_become(item, id, lump)
	var side := global_transform.basis.x.normalized()
	var back := global_transform.basis.z.normalized()
	for i in count - 1:
		var offset := side * (float(i % 3) - 1.0) * 0.3 + back * (0.3 + float(i / 3) * 0.3) + Vector3(0, 0.1, 0)
		var piece := manager.spawn(id, Transform3D(Basis(), at + offset), plot_id, Vector3.ZERO, lump, true)
		if piece != null:
			piece.linear_velocity = velocity
	return true

func status_line() -> String:
	return "%s (%s): %s, %d through  [E] %s" % [def.display_name, tier_label(),
		"running" if running else "stopped", total_processed, "stop" if running else "start"]

func to_dict() -> Dictionary:
	return {"running": running, "total_processed": total_processed}

func from_dict(d: Dictionary) -> void:
	running = bool(d.get("running", true))
	total_processed = int(d.get("total_processed", 0))
