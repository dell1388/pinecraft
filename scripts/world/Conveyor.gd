class_name Conveyor
extends Node3D

## A conveyor belt that carries things the way a real one does: by friction.
##
## The deck is a StaticBody3D with a surface velocity, so whatever rests on it
## is dragged along at belt speed by the physics engine itself. Nothing is
## captured, frozen or placed by hand. A piece can be knocked off, roll back
## down a ramp, jam against a wall or wedge across the rails - and a belt that
## is stopped is just a rubber deck things sit on.
##
## The one concession: a piece that reaches the far lip and is right in front
## of a machine, bin or chute is handed to it, the same as dropping it into a
## hopper, so a line does not need pixel-perfect alignment to work.

@export var length: float = 12.0
@export var width: float = 1.4
@export var speed: float = 3.0
## Spec's belt options. `rise` is how far the belt climbs over its run, and a
## belt without rails is one things can be pushed on and off sideways.
@export var rise: float = 0.0
@export var railed: bool = true
## Spec: retractable. A stopped belt is a still deck: what is on it stays put.
@export var running: bool = true

## Set by the plot: given a world point, returns the machine/bin/sell zone that
## should receive items leaving this belt, or null.
var sink_finder: Callable = Callable()

const DECK_THICKNESS := 0.16
## How far short of the far end a piece has to be before it is offered to
## whatever is there.
const LIP := 0.2

var _deck: StaticBody3D
var _area: Area3D
var _area_shape: CollisionShape3D
var _riding: Dictionary = {}            ## LooseItem -> true, pieces on the belt now
var _output_point: Node3D
var _poll_counter: int = 0
var _pitch: float = 0.0

## Throughput counters, read by the benchmark and the tests.
var total_captured: int = 0             ## pieces that have come aboard
var total_delivered: int = 0            ## pieces that went off the far end

func _ready() -> void:
	_build()
	set_physics_process(true)

func _build() -> void:
	_deck = StaticBody3D.new()
	_deck.collision_layer = Layers.MACHINE
	_deck.collision_mask = Layers.MASK_MACHINE
	# A ramp is the same deck, pitched and lengthened to the slope it covers.
	var run := sqrt(length * length + rise * rise)
	# The belt runs toward -Z and climbs as it goes, so the deck has to be high
	# at the -Z end. Pitch it the other way and the mesh slopes against the
	# pieces riding it.
	var pitch := atan2(rise, length)
	# The deck rests on the origin rather than straddling it, so a belt sits on
	# the pad instead of being sunk half a deck into it.
	var deck_pose := Transform3D(Basis(Vector3.RIGHT, pitch),
		Vector3(0, DECK_THICKNESS * 0.5 + rise * 0.5, 0))
	var deck_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, DECK_THICKNESS, run)
	deck_shape.shape = box
	deck_shape.transform = deck_pose
	_deck.add_child(deck_shape)

	_deck.add_child(_dress(deck_pose, run).instance("Belt", false))

	# Side rails keep things from wandering off the belt. A
	# borderless deck goes without, so things can be pushed on and off it.
	if railed:
		for side in [-1.0, 1.0]:
			var rail := CollisionShape3D.new()
			var rb := BoxShape3D.new()
			rb.size = Vector3(0.08, 0.35, run)
			rail.shape = rb
			rail.transform = deck_pose.translated_local(
				Vector3(side * (width * 0.5 + 0.04), 0.25, 0.0))
			_deck.add_child(rail)

	# Grippy rubber: the friction is what carries things, and what holds
	# them on a ramp.
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	pm.rough = true
	_deck.physics_material_override = pm
	_pitch = pitch

	# Tracks what is aboard, so it can be kept awake and handed on.
	_area = Area3D.new()
	_area.collision_layer = Layers.TRIGGER
	_area.collision_mask = Layers.LOOSE
	_area.monitoring = true
	_area.monitorable = false
	var acs := CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = Vector3(width + 0.2, 1.2 + absf(rise), length)
	acs.shape = ab
	acs.position = Vector3(0, DECK_THICKNESS + 0.6 + rise * 0.5, 0)
	_area_shape = acs
	_area.add_child(acs)
	add_child(_area)

	add_child(_deck)

	_output_point = Node3D.new()
	_output_point.position = Vector3(0, DECK_THICKNESS + 0.4 + rise, -length * 0.5 - 0.3)
	add_child(_output_point)

## The belt as a built thing: a rubber belt between steel side channels, legs
## down to the pad, rollers at each end, and chevrons painted on it pointing
## the way it runs - which is the thing you most need to know about a belt.
func _dress(deck_pose: Transform3D, run: float) -> Greeble:
	var g := Greeble.new()
	var steel := Color(0.40, 0.42, 0.46)
	var rubber := Color(0.14, 0.14, 0.16)
	var fast := speed > 4.5
	var paint := Color(0.35, 0.80, 0.95) if fast else Color(0.96, 0.76, 0.20)
	g.box(Vector3(width - 0.2, DECK_THICKNESS, run), deck_pose, rubber)
	for side in [-1.0, 1.0]:
		g.box(Vector3(0.1, DECK_THICKNESS + 0.1, run + 0.05), deck_pose.translated_local(Vector3(side * (width * 0.5 - 0.05), 0.02, 0)), steel)
		if railed:
			g.box(Vector3(0.08, 0.3, run), deck_pose.translated_local(Vector3(side * (width * 0.5 + 0.04), 0.25, 0)), steel.lightened(0.1))
			var posts := maxi(2, int(run / 1.5) + 1)
			for i in posts:
				var z := -run * 0.5 + run * float(i) / float(posts - 1)
				g.box(Vector3(0.08, 0.34, 0.08), deck_pose.translated_local(Vector3(side * (width * 0.5 + 0.04), 0.18, z)), steel.darkened(0.15))
	# Chevrons pointing along -Z, the way the belt carries things.
	var count := maxi(1, int(run / 1.0))
	for i in count:
		var z := run * 0.5 - (float(i) + 0.5) * run / float(count)
		for side in [-1.0, 1.0]:
			var arm := Transform3D(Basis(Vector3.UP, side * 0.7), Vector3(side * 0.14, DECK_THICKNESS * 0.5 + 0.005, z + 0.1))
			g.box(Vector3(0.09, 0.012, 0.42), deck_pose * arm, paint)
	# Rollers at each end.
	for end in [-1.0, 1.0]:
		var at := deck_pose * Vector3(0, -0.02, end * run * 0.5)
		var across := deck_pose.basis.x * (width * 0.5 - 0.02)
		g.pipe(at - across, at + across, DECK_THICKNESS * 0.62, steel.lightened(0.15), 8)
	# Legs down to the pad under the deck, at each end and every couple of metres.
	var legs := maxi(2, int(run / 2.0) + 1)
	for i in legs:
		var z := -run * 0.5 + 0.2 + (run - 0.4) * float(i) / float(legs - 1)
		var top := deck_pose * Vector3(0, -DECK_THICKNESS * 0.5, z)
		if top.y < 0.12:
			continue
		for side in [-1.0, 1.0]:
			var x: float = side * (width * 0.5 - 0.1)
			var foot := Vector3((deck_pose * Vector3(x, 0, z)).x, 0.0, (deck_pose * Vector3(x, 0, z)).z)
			var head := deck_pose * Vector3(x, -DECK_THICKNESS * 0.5, z)
			g.block(Vector3(0.08, head.y, 0.08), (foot + head) * 0.5, steel.darkened(0.2))
	return g

func output_transform() -> Transform3D:
	return _output_point.global_transform

## Pieces on the belt right now.
func captured_count() -> int:
	return _riding.size()

## How far the deck has climbed this far along the belt. The mesh, the collider
## and the pieces riding it all come off this, so they cannot disagree.
func surface_height(progress: float) -> float:
	return rise * clampf(progress / maxf(0.01, length), 0.0, 1.0)

## Spec: retractable belts. A stopped belt stops moving what is on it; the
## pieces stay where they are, as they would on any stopped belt.
func set_running(value: bool) -> void:
	running = value

func toggle() -> bool:
	running = not running
	return running

func status_line() -> String:
	var shape := "ramp" if absf(rise) > 0.01 else "belt"
	return "%s: %s, %d aboard  [E] %s" % [
		shape, "running" if running else "stopped", _riding.size(),
		"stop" if running else "start"]

# --- Carrying ----------------------------------------------------------------

## The way the belt surface moves, in world space: along -Z, up the slope.
func belt_velocity() -> Vector3:
	if not running:
		return Vector3.ZERO
	var along := global_transform.basis * (Basis(Vector3.RIGHT, _pitch) * Vector3.FORWARD)
	return along.normalized() * speed

func _physics_process(_delta: float) -> void:
	# The engine drags anything touching the deck toward this velocity. Set
	# every frame, so a belt that is moved or stopped is right at once.
	_deck.constant_linear_velocity = belt_velocity()
	_poll_counter += 1
	if _poll_counter < 3:
		return
	_poll_counter = 0
	var inside: Dictionary = {}
	for body in Trigger.bodies_inside(_area, _area_shape, 0.1):
		var item := body as LooseItem
		if item != null and item.state == LooseItem.State.FREE:
			inside[item] = true
	for item in _riding.keys():
		if inside.has(item):
			continue
		_riding.erase(item)
		if is_instance_valid(item) and item.get_parent() != null \
				and _local(item).z < -length * 0.5 + LIP:
			total_delivered += 1
	for item in inside:
		if not _riding.has(item):
			_riding[item] = true
			total_captured += 1
		# A belt that is running is a cause to move: nothing sleeps on it.
		if running and item.sleeping:
			item.sleeping = false
		if _local(item).z < -length * 0.5 + LIP:
			_offer(item)

func _local(item: LooseItem) -> Vector3:
	return global_transform.affine_inverse() * item.global_position

## At the far lip: whatever the belt runs into can take the piece.
func _offer(item: LooseItem) -> void:
	if not running or not sink_finder.is_valid():
		return
	var sink: Object = sink_finder.call(output_transform().origin)
	if sink == null or not sink.has_method("can_accept") or not sink.can_accept(item.item_id):
		return
	if sink.accept_item(item):
		_riding.erase(item)
		total_delivered += 1
