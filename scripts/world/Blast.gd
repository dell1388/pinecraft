class_name Blast
extends RefCounted

## TNT: lighting a stick, and what happens when one goes off.
##
## A lit stick fizzes for a few seconds (pick it up and throw it, or run),
## then goes off: players nearby are thrown a long way (they go limp - see
## Player.knock), loose things are blown about, every other stick (or box of
## sticks) in reach goes off too a split second later - lying about, on
## someone's rack or in their hand - and ore in the ground is cracked apart - easy ores come to pieces, the
## middle ones are knocked about, the top ones (platinum, sunstone,
## starmetal, the finest gems) barely notice. Loose ore chunks in the blast
## crack in two the same way.

## How far a blast reaches, and how hard it throws a player at its heart.
static var RADIUS: float = Balance.num("explosives.radius", 6.0)
static var LAUNCH: float = Balance.num("explosives.launch", 38.0)
## How far a blast sets off other TNT (a little further than it throws things).
static var CHAIN_RADIUS: float = Balance.num("explosives.chain_radius", 8.0)
## The hammer-head weight a blast hits ore with, at its heart.
static var ORE_HIT_KG: float = Balance.num("explosives.ore_hit_kg", 60.0)
## Seconds a lit fuse burns.
static var FUSE_SECONDS: float = Balance.num("explosives.fuse_seconds", 4.0)
## How much of a blast each tier of ore takes: the top ones hardly any.
const TIER_TAKES := {1: 1.0, 2: 0.3, 3: 0.03}

## Lights `item`'s fuse. Returns false if it is already burning.
static func light(item: LooseItem, manager: LooseItemManager, seconds: float = -1.0) -> bool:
	if item == null or not is_instance_valid(item) or item.has_meta("fuse"):
		return false
	var f := Fuse.new()
	f.item = item
	f.manager = manager
	f.left = FUSE_SECONDS if seconds < 0.0 else seconds
	item.set_meta("fuse", f)
	item.get_tree().current_scene.add_child(f)
	return true

## TNT, loose or still in its box.
static func explosive(item: LooseItem) -> bool:
	return item != null and (item.item_id == &"tnt_stick" or item.item_id == &"box_tnt_stick")

## Sets another stick off a moment after a blast reaches it: a quick ripple,
## not all at once.
static func _chain(item: LooseItem, manager: LooseItemManager) -> void:
	if explosive(item) and item.state != LooseItem.State.POOLED and not lit(item):
		light(item, manager, randf_range(0.06, 0.2))

## Whether this item's fuse is burning.
static func lit(item: LooseItem) -> bool:
	return item != null and is_instance_valid(item) and item.has_meta("fuse")

## Sets off a blast at `at`. Returns how many things it reached.
static func detonate(host: Node, at: Vector3, manager: LooseItemManager) -> int:
	var root: Node = host.get_tree().current_scene
	_effects(root, at)
	Sfx.play(&"boom", at, 6.0)
	var space := (host as Node3D).get_world_3d().direct_space_state if host is Node3D else root.get_viewport().world_3d.direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(RADIUS, CHAIN_RADIUS)
	q.shape = sphere
	q.transform = Transform3D(Basis(), at)
	q.collision_mask = Layers.PLAYER | Layers.LOOSE | Layers.TREE | Layers.VEHICLE
	var reached := 0
	var seen := {}
	for hit in space.intersect_shape(q, 96):
		var o: Object = hit.collider
		if o == null or seen.has(o):
			continue
		seen[o] = true
		if o is RigidBody3D and (o as Node).has_meta("player"):
			o = (o as Node).get_meta("player")
			if seen.has(o):
				continue
			seen[o] = true
		if o is Player:
			var p := o as Player
			var centre := p.global_position + Vector3.UP * 0.9
			# TNT on his rack or in his hand goes up with him.
			for carried in p.held:
				if is_instance_valid(carried):
					_chain(carried, manager)
			if p.dragged != null and is_instance_valid(p.dragged):
				_chain(p.dragged, manager)
			var k := _falloff(centre, at)
			if k > 0.0:
				# Thrown hard even near the edge (the square root), up and away.
				var throw := LAUNCH * sqrt(k)
				var away := (centre - at)
				away.y = maxf(away.y, 0.0)
				p.knock(away.normalized() * throw + Vector3.UP * throw * 0.6)
				reached += 1
		elif o is OreRock:
			if _hit_rock(o as OreRock, at):
				reached += 1
		elif o is LooseItem:
			var item := o as LooseItem
			if item.global_position.distance_to(at) <= CHAIN_RADIUS:
				_chain(item, manager)
			if item.state != LooseItem.State.FREE:
				continue
			var k := _falloff(item.global_position, at)
			if k <= 0.0:
				continue
			reached += 1
			var away := (item.global_position - at).normalized() + Vector3.UP * 0.6
			item.apply_central_impulse(away.normalized() * item.mass * 12.0 * k)
			_crack_loose(item, k, manager)
		elif o is Hauler:
			var v := o as Hauler
			var k := _falloff(v.global_position, at)
			if k > 0.0:
				v.apply_central_impulse(((v.global_position - at).normalized() + Vector3.UP) * v.mass * 3.0 * k)
				reached += 1
	return reached

## 1 at the heart of the blast, 0 at its edge.
static func _falloff(p: Vector3, at: Vector3) -> float:
	return clampf(1.0 - p.distance_to(at) / RADIUS, 0.0, 1.0)

static func tier_takes(item_id: StringName) -> float:
	return float(TIER_TAKES.get(clampi(GameData.material_level(item_id), 1, 3), 1.0))

## Ore in the ground: struck several times over, by how much of the blast
## its tier takes.
static func _hit_rock(rock: OreRock, at: Vector3) -> bool:
	if rock.consumed():
		return false
	var k := _falloff(rock.global_position, at)
	if k <= 0.0:
		return false
	var head := ORE_HIT_KG * k * tier_takes(rock.ore_item)
	for i in 6:
		if rock.consumed():
			break
		rock.strike(head)
	return true

## A loose chunk of ore or stone: cracked in two if the blast has it.
static func _crack_loose(item: LooseItem, k: float, manager: LooseItemManager) -> void:
	if manager == null or not item.is_rough_stone():
		return
	var v := item.volume()
	if v < Player.MIN_CRACK_VOLUME * 2.0:
		return
	item.cut_progress += ORE_HIT_KG * 3.0 * k * tier_takes(item.item_id) * OreRock.CRACK_GAIN / pow(maxf(0.05, v), 2.0 / 3.0)
	if item.cut_progress < 1.0:
		return
	var at := item.global_transform
	var id := item.item_id
	var dims := item.dims
	var plot := item.plot_id
	var owned := item.owned
	var velocity := item.linear_velocity
	manager.despawn(item)
	var half := Solid.keep_finish(dims, Solid.chunk(v * 0.5))
	var side := pow(v * 0.5, 1.0 / 3.0)
	for s in [-1.0, 1.0]:
		var piece := manager.spawn(id, Transform3D(at.basis, at.origin + at.basis.x.normalized() * s * side * 0.55),
			plot, velocity + at.basis.x.normalized() * s * 2.0 + Vector3.UP * 2.0, half.duplicate(true), owned)
		if piece != null:
			piece.owned = owned

# --- What it looks like ------------------------------------------------------------

static func _effects(root: Node, at: Vector3) -> void:
	var fx := Node3D.new()
	fx.name = "Blast"
	root.add_child(fx)
	fx.global_position = at
	# The fireball: a core of big glowing cubes, bright chunks flung out
	# round it, burning out fast.
	fx.add_child(_burst(Color(1.0, 0.85, 0.35), true, 16, 2.5, 0.6, 1.1))
	fx.add_child(_burst(Color(1.0, 0.55, 0.12), true, 60, 8.0, 0.8, 0.45))
	fx.add_child(_burst(Color(1.0, 0.9, 0.5), true, 30, 12.0, 0.5, 0.18))
	# Smoke: big grey cubes rolling up and out, hanging about.
	var smoke := _burst(Color(0.3, 0.29, 0.29), false, 36, 3.2, 3.5, 1.0)
	smoke.gravity = Vector3(0, 1.4, 0)
	smoke.damping_min = 1.0
	smoke.damping_max = 2.0
	var puff := Curve.new()
	puff.add_point(Vector2(0.0, 0.3))
	puff.add_point(Vector2(0.25, 1.0))
	puff.add_point(Vector2(1.0, 0.0))
	smoke.scale_amount_curve = puff
	fx.add_child(smoke)
	# Dirt thrown up.
	fx.add_child(_burst(Color(0.36, 0.26, 0.17), false, 50, 9.0, 1.6, 0.16))
	# The flash.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.light_energy = 12.0
	light.omni_range = RADIUS * 2.5
	fx.add_child(light)
	var tw := fx.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.5)
	tw.tween_interval(4.0)
	tw.tween_callback(fx.queue_free)

static func _burst(color: Color, glowing: bool, amount: int, speed: float, life: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if glowing:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 3.0
	mesh.material = mat
	p.mesh = mesh
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -3.0, 0) if glowing else Vector3(0, -9.8, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	var fade := Curve.new()
	fade.add_point(Vector2(0, 1))
	fade.add_point(Vector2(1, 0.1))
	p.scale_amount_curve = fade
	p.emitting = true
	return p


## A burning fuse on a stick: sparks at its end, a fizz, then the bang.
class Fuse:
	extends Node3D
	var item: LooseItem
	var manager: LooseItemManager
	var left: float = 4.0
	var _sparks: CPUParticles3D
	var _hiss: AudioStreamPlayer3D

	func _ready() -> void:
		name = "Fuse"
		top_level = true
		_sparks = Blast._burst(Color(1.0, 0.8, 0.3), true, 24, 2.5, 0.35, 0.03)
		_sparks.one_shot = false
		_sparks.explosiveness = 0.0
		add_child(_sparks)
		_hiss = Sfx.loop(&"fuse")
		if _hiss != null:
			add_child(_hiss)
			_hiss.play()

	func _physics_process(delta: float) -> void:
		if item == null or not is_instance_valid(item) or item.state == LooseItem.State.POOLED:
			# Sold, crushed or cleared away before it went: it just goes out.
			if item != null and is_instance_valid(item):
				item.remove_meta("fuse")
			queue_free()
			return
		# The fuse is at one end of the stick.
		var tip := item.global_transform * Vector3(0, 0, Solid.bounds(item.dims).z * 0.5)
		global_position = tip
		left -= delta
		if left > 0.0:
			return
		var at := item.global_position
		item.remove_meta("fuse")
		if manager != null:
			manager.despawn(item)
		Blast.detonate(self, at, manager)
		queue_free()
