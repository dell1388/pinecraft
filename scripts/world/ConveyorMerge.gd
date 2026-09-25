class_name ConveyorMerge
extends Conveyor

## Three belts into one: a square rubber plate moving toward -Z, open at the
## back and on both sides, with angled guides that funnel whatever lands on it
## into a single belt-wide mouth at the front. A piece arriving from the side
## is caught by the plate's grip, turned forward and steered in by the guides;
## two arriving together shove each other about, as they would.

const MOUTH := 0.9

func _build() -> void:
	var size := Vector2(width / 0.9, length)     # the plot shrinks width for rails
	var w := size.x
	_deck = StaticBody3D.new()
	_deck.collision_layer = Layers.MACHINE
	_deck.collision_mask = Layers.MASK_MACHINE
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	pm.rough = true
	_deck.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, DECK_THICKNESS, length)
	cs.shape = box
	cs.position = Vector3(0, DECK_THICKNESS * 0.5, 0)
	_deck.add_child(cs)
	add_child(_deck)

	var g := Greeble.new()
	var steel := Color(0.40, 0.42, 0.46)
	var rubber := Color(0.14, 0.14, 0.16)
	var guide := Color(0.95, 0.74, 0.16)
	g.box(Vector3(w, DECK_THICKNESS, length), Transform3D(Basis(), Vector3(0, DECK_THICKNESS * 0.5, 0)), rubber)
	g.frame(Vector3(w, DECK_THICKNESS, length), Transform3D(Basis(), Vector3(0, DECK_THICKNESS * 0.5, 0)), 0.06, steel)
	# The guides: from the plate's front corners, a third of the way back,
	# in to the edges of the mouth. Slick steel, so a piece slides along them.
	var slick := PhysicsMaterial.new()
	slick.friction = 0.08
	var guides := StaticBody3D.new()
	guides.collision_layer = Layers.MACHINE
	guides.collision_mask = Layers.MASK_MACHINE
	guides.physics_material_override = slick
	add_child(guides)
	for side in [-1.0, 1.0]:
		var a := Vector3(side * (w * 0.5 - 0.04), 0, -length * 0.5 + length * 0.4)
		var b := Vector3(side * (MOUTH * 0.5 + 0.04), 0, -length * 0.5)
		var along := b - a
		var basis := Basis.looking_at(along.normalized(), Vector3.UP)
		var centre := (a + b) * 0.5 + Vector3(0, DECK_THICKNESS + 0.2, 0)
		var gs := CollisionShape3D.new()
		var gb := BoxShape3D.new()
		gb.size = Vector3(0.08, 0.4, along.length() + 0.08)
		gs.shape = gb
		gs.transform = Transform3D(basis, centre)
		guides.add_child(gs)
		g.box(gb.size, gs.transform, guide)
	# Arrows from each way in, toward the mouth.
	for dir in [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		var d: Vector3 = dir
		var from := -d * minf(w, length) * 0.32 + Vector3(0, DECK_THICKNESS + 0.005, 0.15)
		var basis := Basis.looking_at(Vector3(d.x, 0, -1).normalized() if d.x != 0.0 else d, Vector3.UP)
		for s2 in [-1.0, 1.0]:
			g.box(Vector3(0.08, 0.012, 0.3), Transform3D(basis * Basis(Vector3.UP, s2 * 0.7), from + basis * Vector3(s2 * 0.1, 0, 0.08)), guide)
	add_child(g.instance("Merger", false))

	_area = Area3D.new()
	_area.collision_layer = Layers.TRIGGER
	_area.collision_mask = Layers.LOOSE
	_area.monitorable = false
	var acs := CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = Vector3(w + 0.2, 1.2, length)
	acs.shape = ab
	acs.position = Vector3(0, DECK_THICKNESS + 0.6, 0)
	_area_shape = acs
	_area.add_child(acs)
	add_child(_area)

	_output_point = Node3D.new()
	_output_point.position = Vector3(0, DECK_THICKNESS + 0.4, -length * 0.5 - 0.3)
	add_child(_output_point)

func status_line() -> String:
	return "3-into-1 merger: %s, %d aboard  [E] %s" % [
		"running" if running else "stopped", _riding.size(), "stop" if running else "start"]
