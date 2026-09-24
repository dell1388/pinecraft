class_name Showcase
extends Node3D

## A demo yard beside home with two automated lines running on their own, to
## watch the machines work (Settings > Game > Debug > Demo lines):
##
##   Ore    hopper > belt > Crusher > belt > Smelter > belt > Refiner > belt
##   Stone  hopper > belt > Sander (polish) > belt > Gem Cutter > belt
##
## A hopper at the head of each line drops a raw piece every few seconds, a
## mix from cheap to rare. A sign over each machine shows the last piece it
## made and what it is worth, the hoppers show what went in, and a board at the
## end of each line keeps the running totals. Finished pieces lie on the tray
## past the last belt for a while so you can look at them, then are cleared.
## None of it is saved or owned: it is a display.

const ORE_FEED := [&"ore_iron", &"ore_copper", &"ore_tin", &"ore_zinc", &"ore_magnetite",
	&"ore_tungsten", &"ore_bismuth", &"ore_gold", &"ore_platinum", &"ore_starmetal"]
const GEM_FEED := [&"gem_quartz", &"gem_obsidian", &"gem_jade", &"gem_amethyst",
	&"gem_emerald", &"gem_ruby", &"gem_diamond"]
## Seconds between drops, and how long a finished piece stays on show.
const DROP_EVERY := 4.0
const SHOW_FOR := 25.0
## The hoppers pause while this many pieces are out anywhere.
const ITEM_CEILING := 150
const LANE_GAP := 7.0

var manager: LooseItemManager
var lines: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func setup(p_manager: LooseItemManager) -> void:
	manager = p_manager

func _ready() -> void:
	_rng.seed = 777
	_build_slab()
	lines.append(_build_line("ORE LINE", ORE_FEED, Vector3(-LANE_GAP * 0.5, 0, 0),
		[&"crusher", &"furnace", &"refiner"], Vector2(0.15, 0.4)))
	lines.append(_build_line("STONE LINE", GEM_FEED, Vector3(LANE_GAP * 0.5, 0, 0),
		[&"sander", &"gem_cutter"], Vector2(0.03, 0.12)))

## A concrete slab to stand it all on, level whatever the land does.
func _build_slab() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	add_child(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(22, 1.0, 46)
	cs.shape = box
	cs.position = Vector3(0, -0.5, -4)
	body.add_child(cs)
	var g := Greeble.new()
	g.box(Vector3(22, 1.0, 46), Transform3D(Basis(), Vector3(0, -0.5, -4)), Color(0.55, 0.55, 0.53))
	g.stripes(20.0, 0.3, Transform3D(Basis(), Vector3(0, 0.01, 18.5)))
	body.add_child(g.instance("Slab"))

func _build_line(title: String, feed: Array, origin: Vector3, machines: Array,
		volume: Vector2) -> Dictionary:
	var line := {"title": title, "feed": feed, "volume": volume, "timer": 0.0,
		"in_value": 0, "out_value": 0, "made": 0, "items": {}, "machines": []}
	var cursor := origin.z + 18.0
	# Hopper belt, then belt / machine pairs, then a run-out belt onto the tray.
	var head := _belt(Vector3(origin.x, 0, cursor - 2.0), 4.0)
	line["head"] = head
	cursor -= 4.0
	for id in machines:
		var def := GameData.building(id)
		var m := InlineMachine.new()
		m.setup_machine(manager, def, 0)
		m.position = Vector3(origin.x, 0, cursor - m.length * 0.5)
		add_child(m)
		cursor -= m.length
		var sign := _sign(m.position + Vector3(0, 4.3, 0), def.display_name)
		m.processed.connect(_on_processed.bind(line, sign))
		line.machines.append(m)
		_belt(Vector3(origin.x, 0, cursor - 2.0), 4.0)
		cursor -= 4.0
	line["end_z"] = cursor
	line["hopper_sign"] = _sign(head.position + Vector3(0, 3.2, 1.0), "Hopper")
	line["board"] = _sign(Vector3(origin.x, 3.0, cursor - 3.5), title, 34)
	_hopper(head.position + Vector3(0, 0, 1.2))
	_refresh_board(line)
	return line

func _belt(at: Vector3, length: float) -> Conveyor:
	var c := Conveyor.new()
	c.length = length
	# No wider than a tunnel mouth, so nothing rides in off to one side.
	c.width = 1.0
	c.speed = 3.0
	c.position = at
	add_child(c)
	return c

func _sign(at: Vector3, text: String, font: int = 26) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font
	l.outline_size = 8
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.01
	l.position = at
	add_child(l)
	return l

## A funnel over the head of the line, so the drops look like they come from
## somewhere.
func _hopper(at: Vector3) -> void:
	var g := Greeble.new()
	var steel := Color(0.42, 0.44, 0.47)
	g.prism(4, 1.3, 0.55, 1.1, Transform3D(Basis(Vector3.UP, PI * 0.25) * Basis(Vector3.RIGHT, PI),
		at + Vector3(0, 2.9, 0)), steel)
	for x in [-1.0, 1.0]:
		g.block(Vector3(0.12, 2.4, 0.12), at + Vector3(x, 1.2, 0), steel.darkened(0.3))
	g.stripes(1.8, 0.2, Transform3D(Basis(), at + Vector3(0, 3.5, 0.95)))
	add_child(g.instance("Hopper"))

func _physics_process(delta: float) -> void:
	if manager == null:
		return
	_adopt_strays()
	for line in lines:
		line.timer -= delta
		if line.timer <= 0.0:
			line.timer = DROP_EVERY
			if manager.active_count() < ITEM_CEILING:
				_drop(line)
		_clear_shown(line, delta)

func _drop(line: Dictionary) -> void:
	var head: Conveyor = line.head
	var feed: Array = line.feed
	# Cheap stuff most of the time, the rare stuff now and then.
	var pick: int = mini(feed.size() - 1, int(pow(_rng.randf(), 1.6) * float(feed.size())))
	var id: StringName = feed[pick]
	var vol: Vector2 = line.volume
	var dims := Solid.cube(_rng.randf_range(vol.x, vol.y))
	var at := head.global_transform * Vector3(_rng.randf_range(-0.1, 0.1), 1.6, 1.2)
	# Dropped square to the belt: a chunk turned corner-first is wider than
	# the crusher's mouth, and jams there as it would for you.
	var item := manager.spawn(id, Transform3D(head.global_transform.basis * Basis(Vector3.UP,
		_rng.randf_range(-0.15, 0.15)), at), 0,
		Vector3.ZERO, dims, true)
	if item == null:
		return
	var price := Economy.price_of(id, dims)
	line.in_value += price
	line.items[item] = {"age": 0.0, "done": false}
	(line.hopper_sign as Label3D).text = "IN: %s\n%.2f m³  %s" % [item.display_name(), item.volume(),
		UIKit.money(price)]
	_refresh_board(line)

func _on_processed(_machine: InlineMachine, item: LooseItem, line: Dictionary, sign: Label3D) -> void:
	var what := "%s\n%s" % [item.display_name(), UIKit.money(Economy.price_of(item.item_id, item.dims))]
	# The crusher makes several lumps; the sign counts them.
	var lumps := 0
	for other in manager.free_items():
		if other.item_id == item.item_id and other.global_position.distance_to(item.global_position) < 1.6:
			lumps += 1
	if _machine.machine_def.mode == MachineDef.MODE_CRUSH and lumps > 1:
		what = "%s x%d lumps" % [item.display_name(), lumps]
	sign.text = "%s\n%s" % [_machine.def.display_name.to_upper(), what]
	# Pieces the crusher split off are the line's to track too.
	for other in manager.free_items():
		if not line.items.has(other) and other.global_position.distance_to(item.global_position) < 2.0:
			line.items[other] = {"age": 0.0, "done": false}

## Anything lying on the slab belongs to the lane it is in: crusher lumps,
## pieces knocked off a belt. Each lane is claimed by its x.
func _adopt_strays() -> void:
	for item in manager.free_items():
		var local := to_local(item.global_position)
		if absf(local.x) > 11.0 or local.z < -27.0 or local.z > 19.0 or local.y < -3.0:
			continue
		var line: Dictionary = lines[0] if local.x < 0.0 else lines[1]
		if not line.items.has(item):
			line.items[item] = {"age": 0.0, "done": false}

## Clears every piece off the slab, for switching the demo off.
func clear_all() -> void:
	_adopt_strays()
	for line in lines:
		for item in line.items:
			if is_instance_valid(item) and item.state != LooseItem.State.POOLED:
				manager.despawn(item)
		line.items.clear()

## Once a piece is off the last belt it is counted, left on show for a while,
## then cleared.
func _clear_shown(line: Dictionary, delta: float) -> void:
	var gone: Array = []
	for item in line.items:
		if not is_instance_valid(item) or item.state == LooseItem.State.POOLED:
			gone.append(item)
			continue
		var local_z := to_local(item.global_position).z
		var rec: Dictionary = line.items[item]
		if local_z < float(line.end_z):
			if not rec.done:
				rec.done = true
				line.made += 1
				line.out_value += Economy.price_of(item.item_id, item.dims)
				_refresh_board(line)
			rec.age += delta
			if rec.age > SHOW_FOR:
				manager.despawn(item)
				gone.append(item)
		elif item.global_position.y < -20.0:
			manager.despawn(item)
			gone.append(item)
	for item in gone:
		line.items.erase(item)

func _refresh_board(line: Dictionary) -> void:
	var gain := float(line.out_value) / maxf(1.0, float(line.in_value)) - 1.0
	(line.board as Label3D).text = "%s\nraw in %s   finished %s\n%d pieces out   %+.0f%%" % [
		line.title, UIKit.money(int(line.in_value)), UIKit.money(int(line.out_value)), int(line.made),
		gain * 100.0]
