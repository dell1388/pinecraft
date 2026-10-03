class_name CaveNetwork
extends Node3D

## The world under the world: networks of caverns, big and small, joined by
## tunnels that wind back and forth, climb and drop, and run well below sea
## level. Each island has its own; the home island's is by far the biggest,
## and one tunnel runs under the sea from it to an island with no other way in.
##
## Every cavern belongs to a cave biome, taken from the country above it and
## consolidated the same way: river caves under the woods, with pools of dark
## water; desert caves of sandstone and drifted sand; crystal caves under the
## mountains; ice caves in the north; fungal caves on the wet island, where
## giant glowcaps grow; magma caves under the burnt east; and the abyss, the
## deep passage under the sea. Each has its own ores, colours, light and look.
##
## Geometry: a cavern is a faceted, lumpy ellipsoid with a flat floor, pushed
## out into bays and side lobes so no two are the same shape - the big ones a
## couple of hundred metres across - and a tunnel is a broad, low tube
## along a smooth curve with a flat floor, both drawn and collided on the
## inside only. Where a tunnel meets a cavern the two are made to fit exactly:
## the tube's end ring is slid onto the cavern's wall, point by point, and the
## wall inside the tube's outline is pulled out onto the tube and opened, so
## the join is sealed all round with no crack to see through. Tunnels never
## cross one another or pass through a cavern that is not theirs; the planner
## rules those out.
##
## Surface entrances are the built trench-and-portal `Cave`s, each opening into
## a cavern where its old chamber was.

enum Kind { RIVER, DESERT, CRYSTAL, ICE, FUNGAL, MAGMA, ABYSS }
const KIND_NAMES := ["River Caves", "Desert Caves", "Crystal Caves", "Ice Caves", "Fungal Caves",
	"Magma Caves", "The Abyss"]

## Wall, floor and light colours per cave biome.
const PALETTE := {
	Kind.RIVER: [Color(0.30, 0.36, 0.37), Color(0.20, 0.25, 0.25), Color(0.45, 0.85, 1.0)],
	Kind.DESERT: [Color(0.64, 0.46, 0.31), Color(0.80, 0.66, 0.44), Color(1.0, 0.72, 0.42)],
	Kind.CRYSTAL: [Color(0.26, 0.22, 0.32), Color(0.20, 0.18, 0.25), Color(0.75, 0.50, 1.0)],
	Kind.ICE: [Color(0.66, 0.80, 0.92), Color(0.86, 0.92, 0.98), Color(0.55, 0.80, 1.0)],
	Kind.FUNGAL: [Color(0.27, 0.25, 0.19), Color(0.22, 0.20, 0.14), Color(0.55, 1.0, 0.6)],
	Kind.MAGMA: [Color(0.16, 0.14, 0.14), Color(0.22, 0.17, 0.15), Color(1.0, 0.45, 0.15)],
	Kind.ABYSS: [Color(0.10, 0.13, 0.20), Color(0.08, 0.10, 0.15), Color(0.35, 0.55, 1.0)],
}
## What grows in each: the rock field's mix, cheap to dear.
const ORES := {
	Kind.RIVER: [&"ore_copper", &"ore_magnetite", &"ore_silver", &"gem_jade", &"gem_emerald"],
	Kind.DESERT: [&"gem_turquoise", &"ore_gold", &"ore_bismuth", &"gem_ruby", &"ore_sunstone"],
	Kind.CRYSTAL: [&"gem_quartz", &"gem_amethyst", &"ore_platinum", &"gem_amethyst", &"gem_quartz"],
	Kind.ICE: [&"ore_nickel", &"ore_silver", &"ore_platinum", &"gem_sapphire", &"gem_sapphire"],
	Kind.FUNGAL: [&"ore_zinc", &"ore_cobalt", &"gem_jade", &"ore_cobalt", &"gem_emerald"],
	Kind.MAGMA: [&"gem_obsidian", &"ore_tungsten", &"gem_obsidian", &"ore_sunstone", &"ore_tungsten"],
	Kind.ABYSS: [&"ore_platinum", &"gem_sapphire", &"ore_platinum", &"ore_starmetal", &"gem_sapphire"],
}

## Cover of rock kept over every cavern and tunnel, metres.
const COVER := 9.0
## Steepest a tunnel runs, rise over run.
const MAX_GRADE := 0.4
## Tube floor as a share of the radius below the tube's axis.
const FLOOR_CUT := 0.62
const SIDES := 12
## Tunnels are this much wider than they are tall: thoroughfares, not pipes.
const WIDEN := 1.6
## Biggest tunnel radius; the width is WIDEN times this each side.
const MAX_TUNNEL := 8.5
const RING_STEP := 2.5
const GRID := 48.0
## Furthest a cavern's wall bulges out past its ellipsoid, as a multiple.
const BUMP_MAX := 1.75

static var active: CaveNetwork

var terrain: Terrain
var rooms: Array[Dictionary] = []
var tunnels: Array[Dictionary] = []
var entrances: Array[Cave] = []
var manager: LooseItemManager
var _rng := RandomNumberGenerator.new()
var _grid: Dictionary = {}
var _noise := FastNoiseLite.new()

# --- Planning ------------------------------------------------------------------

## Lays the networks out. `zones`: [{name, centre, radius, rooms, kinds: [[Kind,
## Vector2 centre], ...]}]; `links`: [[zone a, zone b]] joined by a deep
## passage; entrances come from the terrain's cave plans, each in the zone
## that contains it.
func plan(p_terrain: Terrain, zones: Array, links: Array, seed_value: int) -> void:
	terrain = p_terrain
	_rng.seed = seed_value
	_noise.seed = seed_value
	_noise.frequency = 0.9
	rooms.clear()
	tunnels.clear()
	_grid.clear()
	var by_zone: Array = []
	for zi in zones.size():
		by_zone.append(_plan_zone(zones[zi], zi))
	for link in links:
		_plan_link(zones, by_zone, int(link[0]), int(link[1]))
		# The two networks and the passage between are one network now; join
		# up anything the passage left hanging.
		var joined: Array = []
		for i in rooms.size():
			if int(rooms[i].zone) == int(link[0]) or int(rooms[i].zone) == int(link[1]):
				joined.append(i)
		_repair(joined)
	_prune_unreached()

## The plan, kept in a file: it comes out the same every time for the same
## land, and working it out is the slow part of the caves, so the next load
## reads it back instead. `key` says what it was planned for; a plan made for
## anything else (other land, other zones, another build of the game) is not
## read back. Entrances are kept as their place in the terrain's cave list.
func save_plan(path: String, key: String) -> void:
	if path == "":
		return
	var saved: Array = []
	for room: Dictionary in rooms:
		var copy := room.duplicate()
		copy["entrance"] = _entrance_index(room.entrance)
		saved.append(copy)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_var({"key": key, "rooms": saved, "tunnels": tunnels, "rng": _rng.state})

## Reads back a plan saved for `key`, as if `plan` had just made it. False
## (and nothing changed) when there is none for this key.
func load_plan(p_terrain: Terrain, path: String, key: String, seed_value: int) -> bool:
	if path == "" or not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var data: Variant = f.get_var()
	if not (data is Dictionary) or String(data.get("key", "")) != key:
		return false
	var saved_rooms: Array = data.get("rooms", [])
	var saved_tunnels: Array = data.get("tunnels", [])
	for room: Dictionary in saved_rooms:
		var ei := int(room.get("entrance", -1))
		if ei >= p_terrain.caves.size():
			return false
	terrain = p_terrain
	_rng.seed = seed_value
	_rng.state = int(data.get("rng", _rng.state))
	_noise.seed = seed_value
	_noise.frequency = 0.9
	rooms.clear()
	for room: Dictionary in saved_rooms:
		var ei := int(room.entrance)
		room["entrance"] = terrain.caves[ei] if ei >= 0 else null
		rooms.append(room)
	tunnels.assign(saved_tunnels)
	_grid.clear()
	for ti in tunnels.size():
		_index_tunnel(ti)
	return true

func _entrance_index(entrance: Variant) -> int:
	if entrance == null:
		return -1
	for i in terrain.caves.size():
		if is_same(terrain.caves[i], entrance):
			return i
	return -1

## Drops any cavern (and its tunnels) that no cave mouth leads to: one the
## tunnelling could not join up is a sealed bubble in the rock, never seen and
## never reached, with its ore wasted.
func _prune_unreached() -> void:
	var ids: Array = []
	for i in rooms.size():
		ids.append(i)
	var comp := _components(ids)
	var lit: Dictionary = {}
	for i in ids:
		if rooms[i].entrance != null:
			lit[comp[i]] = true
	var keep_room: Dictionary = {}
	var new_rooms: Array = []
	for i in ids:
		if lit.has(comp[i]):
			keep_room[i] = new_rooms.size()
			new_rooms.append(rooms[i])
	if new_rooms.size() == rooms.size():
		return
	var keep_tunnel: Dictionary = {}
	var new_tunnels: Array = []
	for ti in tunnels.size():
		var t: Dictionary = tunnels[ti]
		if keep_room.has(int(t.a)) and keep_room.has(int(t.b)):
			keep_tunnel[ti] = new_tunnels.size()
			t.a = keep_room[int(t.a)]
			t.b = keep_room[int(t.b)]
			new_tunnels.append(t)
	for ri in new_rooms.size():
		var room: Dictionary = new_rooms[ri]
		room.index = ri
		var links: Array = []
		for ti in room.links:
			if keep_tunnel.has(ti):
				links.append(keep_tunnel[ti])
		room.links = links
	rooms.assign(new_rooms)
	tunnels.assign(new_tunnels)
	_grid.clear()
	for ti in tunnels.size():
		_index_tunnel(ti)

func _kind_at(zone: Dictionary, p: Vector2) -> Kind:
	var best := Kind.RIVER
	var best_d := INF
	for k in zone.kinds:
		var d := p.distance_to(k[1])
		if d < best_d:
			best_d = d
			best = k[0]
	return best

func _plan_zone(zone: Dictionary, zi: int) -> Array:
	var mine: Array = []
	var centre: Vector2 = zone.centre
	var radius: float = float(zone.radius)
	# The entrances first: a cavern where each one's chamber would be.
	for plan_entry in terrain.caves:
		var e: Vector3 = plan_entry.entrance
		if Vector2(e.x, e.z).distance_to(centre) > radius:
			continue
		var d: Vector3 = plan_entry.dir
		var z_end := Cave.SHAFT_LENGTH + Cave.TUNNEL_LENGTH
		var rz := 18.0
		var c := e + d * (z_end + rz * 0.83 - 2.0)
		var floor_y := float(plan_entry.ground) - Cave.CHAMBER_DROP
		var room := _room(Vector3(c.x, 0, c.z), 24.0, 6.0, rz, floor_y, atan2(d.x, d.z),
			_kind_at(zone, Vector2(c.x, c.z)), zi)
		room["entrance"] = plan_entry
		mine.append(rooms.size())
		rooms.append(room)
	# Then the caverns proper, spread through the island, deep.
	var target: int = int(zone.rooms)
	var tries := 0
	var made := 0
	# An even share round each cave biome's centre, so every biome gets its
	# caverns and each biome's caverns are together.
	var kinds: Array = zone.kinds
	var per := maxi(1, int(ceil(float(target) / float(kinds.size()))))
	var made_by_kind: Dictionary = {}
	while tries < target * 60 and made < target:
		tries += 1
		var ki := tries % kinds.size()
		if int(made_by_kind.get(ki, 0)) >= per:
			continue
		var home: Vector2 = kinds[ki][1]
		var a := _rng.randf() * TAU
		var spread := radius * (0.5 if kinds.size() > 1 else 0.8)
		var p := home + Vector2(cos(a), sin(a)) * sqrt(_rng.randf()) * spread
		if p.distance_to(centre) > radius * 0.85:
			continue
		# Caverns, not rooms: the small ones are the size of a barn, the
		# big ones you could lose a village in.
		var roll := _rng.randf()
		var rx := _rng.randf_range(30.0, 44.0)
		if roll < 0.25:
			rx = _rng.randf_range(85.0, 120.0)
		elif roll < 0.7:
			rx = _rng.randf_range(50.0, 75.0)
		# Smaller islands have less room under them.
		rx = minf(rx, radius * 0.28)
		var rz := rx * _rng.randf_range(0.55, 1.45)
		var ry := minf(40.0, minf(rx, rz) * _rng.randf_range(0.4, 0.55))
		var reach := maxf(rx, rz)
		var clear := true
		for other in mine:
			var o: Dictionary = rooms[other]
			if Vector2(o.centre.x, o.centre.z).distance_to(p) < (reach + maxf(o.rx, o.rz)) * 1.4 + 50.0:
				clear = false
				break
		if not clear:
			continue
		var floor_y := _rng.randf_range(-110.0, -15.0)
		var ceiling := _lowest_ground(Vector3(p.x, 0, p.y), reach * BUMP_MAX) - COVER - ry * 1.6
		floor_y = minf(floor_y, ceiling)
		if floor_y < -170.0:
			continue
		mine.append(rooms.size())
		made += 1
		made_by_kind[ki] = int(made_by_kind.get(ki, 0)) + 1
		rooms.append(_room(Vector3(p.x, 0, p.y), rx, ry, rz, floor_y, _rng.randf() * TAU,
			_kind_at(zone, p), zi))
	_connect(mine)
	return mine

func _room(c: Vector3, rx: float, ry: float, rz: float, floor_y: float, yaw: float, kind: Kind,
		zone: int) -> Dictionary:
	return {"centre": Vector3(c.x, floor_y + ry * 0.55, c.z), "rx": rx, "ry": ry, "rz": rz,
		"floor": floor_y, "yaw": yaw, "kind": kind, "zone": zone, "links": [], "entrance": null,
		"index": rooms.size()}

## Lowest ground (or sea bed) over a disc: what a cavern has to stay under.
func _lowest_ground(c: Vector3, r: float) -> float:
	var lo := terrain.height_at(c.x, c.z)
	for i in 8:
		var a := TAU * float(i) / 8.0
		lo = minf(lo, terrain.height_at(c.x + cos(a) * r, c.z + sin(a) * r))
	return lo

## A spanning tree of the nearest pairs, so every cavern can be reached, then
## a share of the other near pairs as extra loops, so there is more than one way
## round and tunnels double back past each other.
func _connect(ids: Array) -> void:
	var pairs: Array = []
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Dictionary = rooms[ids[i]]
			var b: Dictionary = rooms[ids[j]]
			var d := Vector2(a.centre.x - b.centre.x, a.centre.z - b.centre.z).length()
			if d < 340.0:
				pairs.append([d, ids[i], ids[j]])
	pairs.sort_custom(func(x, y): return x[0] < y[0])
	var parent: Dictionary = {}
	for id in ids:
		parent[id] = id
	var find := func(x: int) -> int:
		while parent[x] != x:
			x = parent[x]
		return x
	var tree: Array = []
	var rest: Array = []
	for pr in pairs:
		var ra: int = find.call(pr[1])
		var rb: int = find.call(pr[2])
		if ra != rb:
			parent[ra] = rb
			tree.append(pr)
		else:
			rest.append(pr)
	_relax_depths(tree)
	for pr in tree:
		_try_tunnel(pr[1], pr[2], 6)
	_repair(ids)
	for pr in rest:
		var a2: Dictionary = rooms[pr[1]]
		var b2: Dictionary = rooms[pr[2]]
		if float(pr[0]) < 240.0 and a2.links.size() < 4 and b2.links.size() < 4 and _rng.randf() < 0.4:
			_try_tunnel(pr[1], pr[2], 2)

## Joins up whatever the spanning tree failed to: while the zone is in more
## than one piece, the closest pair of caverns in different pieces is tunnelled,
## trying harder and allowing a steeper climb, until it is whole or nothing
## more can be joined.
func _repair(ids: Array) -> void:
	var tried: Dictionary = {}
	for round_index in 240:
		var comp := _components(ids)
		var groups: Dictionary = {}
		for id in ids:
			groups[comp[id]] = true
		if groups.size() <= 1:
			return
		var best: Array = []
		var best_d := INF
		for i in ids:
			for j in ids:
				if comp[i] == comp[j] or i >= j or tried.has(Vector2i(i, j)):
					continue
				var a: Dictionary = rooms[i]
				var b: Dictionary = rooms[j]
				var d := Vector2(a.centre.x - b.centre.x, a.centre.z - b.centre.z).length()
				if d < best_d:
					best_d = d
					best = [i, j]
		if best.is_empty() or best_d > 600.0:
			return
		tried[Vector2i(best[0], best[1])] = true
		_relax_depths([[best_d, best[0], best[1]]])
		_grade_scale = 1.2
		_try_tunnel(best[0], best[1], 14)
		_grade_scale = 1.0

var _grade_scale: float = 1.0

## Which piece each cavern is in, joined by tunnels: id -> piece number.
func _components(ids: Array) -> Dictionary:
	var comp: Dictionary = {}
	var n := 0
	for start in ids:
		if comp.has(start):
			continue
		var stack: Array = [start]
		comp[start] = n
		while not stack.is_empty():
			var r: int = stack.pop_back()
			for ti in rooms[r].links:
				var t: Dictionary = tunnels[ti]
				for o in [int(t.a), int(t.b)]:
					if not comp.has(o):
						comp[o] = n
						stack.append(o)
		n += 1
	return comp

## Moves caverns up or down so that each tree edge can be tunnelled at a
## walkable grade. Entrances stay put; nothing is raised past its cover.
func _relax_depths(tree: Array) -> void:
	for it in 40:
		var moved := false
		for pr in tree:
			var a: Dictionary = rooms[pr[1]]
			var b: Dictionary = rooms[pr[2]]
			var run := maxf(20.0, float(pr[0]) - maxf(a.rx, a.rz) - maxf(b.rx, b.rz))
			var allowed := run * MAX_GRADE * 0.8
			var dy: float = float(b.floor) - float(a.floor)
			if absf(dy) <= allowed:
				continue
			var excess := absf(dy) - allowed
			var up: Dictionary = a if dy < 0.0 else b     # the higher one comes down
			var down: Dictionary = b if dy < 0.0 else a
			# A cavern with a way in, or with tunnels dug already, stays put:
			# moving it would leave them hanging.
			var up_fixed: bool = up.entrance != null or not (up.links as Array).is_empty()
			var down_fixed: bool = down.entrance != null or not (down.links as Array).is_empty()
			if up_fixed and down_fixed:
				continue
			if not up_fixed:
				_set_floor(up, float(up.floor) - excess * (0.5 if not down_fixed else 1.0))
				moved = true
			if not down_fixed:
				var limit := _lowest_ground(down.centre, maxf(down.rx, down.rz) * BUMP_MAX) - COVER - float(down.ry) * 1.6
				_set_floor(down, minf(limit, float(down.floor) + excess * (0.5 if not up_fixed else 1.0)))
				moved = true
		if not moved:
			break

func _set_floor(room: Dictionary, floor_y: float) -> void:
	room.floor = floor_y
	room.centre = Vector3(room.centre.x, floor_y + float(room.ry) * 0.55, room.centre.z)

## The deep passage between two zones: a chain of pockets under the sea bed,
## the whole way at abyssal depth.
func _plan_link(zones: Array, by_zone: Array, za: int, zb: int) -> void:
	var cb: Vector2 = zones[zb].centre
	var ca: Vector2 = zones[za].centre
	var from := _nearest_room(by_zone[za], cb)
	var to := _nearest_room(by_zone[zb], ca)
	if from < 0 or to < 0:
		return
	var a: Vector3 = rooms[from].centre
	var b: Vector3 = rooms[to].centre
	var span := Vector2(a.x - b.x, a.z - b.z).length()
	var n := maxi(1, int(span / 170.0))
	var chain: Array = [from]
	for i in range(1, n):
		var t := float(i) / float(n)
		var p := a.lerp(b, t)
		var wob := Vector2(-(b.z - a.z), b.x - a.x).normalized() * _rng.randf_range(-40.0, 40.0)
		var ry := _rng.randf_range(11.0, 14.0)
		var floor_y := minf(_rng.randf_range(-110.0, -85.0), _lowest_ground(p, 30.0) - COVER - ry * 1.6)
		var id := rooms.size()
		rooms.append(_room(Vector3(p.x + wob.x, 0, p.z + wob.y), _rng.randf_range(24.0, 34.0),
			ry, _rng.randf_range(24.0, 34.0), floor_y, _rng.randf() * TAU,
			Kind.ABYSS, za))
		chain.append(id)
	chain.append(to)
	var tree: Array = []
	for i in chain.size() - 1:
		var ra: Dictionary = rooms[chain[i]]
		var rb: Dictionary = rooms[chain[i + 1]]
		tree.append([Vector2(ra.centre.x - rb.centre.x, ra.centre.z - rb.centre.z).length(), chain[i], chain[i + 1]])
	_relax_depths(tree)
	for pr in tree:
		_try_tunnel(pr[1], pr[2], 10)

func _nearest_room(ids: Array, toward: Vector2) -> int:
	var best := -1
	var best_d := INF
	for id in ids:
		var r: Dictionary = rooms[id]
		if r.entrance != null:
			continue
		var d := Vector2(r.centre.x, r.centre.z).distance_to(toward)
		if d < best_d:
			best_d = d
			best = id
	return best

## Plans a tunnel between two caverns: a curve that wanders side to side and up
## and down on the way, kept walkable, under cover, clear of every other
## cavern and every other tunnel. Several shapes are tried before giving up.
func _try_tunnel(ia: int, ib: int, attempts: int) -> bool:
	var a: Dictionary = rooms[ia]
	var b: Dictionary = rooms[ib]
	# Never back out along an entrance's own tunnel: if the other cavern lies
	# behind the way in, the tunnel leaves by the side and swings round.
	var via_a: Variant = _side_exit(a, b)
	var via_b: Variant = _side_exit(b, a)
	# Broad all the way, narrowing only where a cavern is too low to take
	# it at full size (the entrance halls).
	var r := _rng.randf_range(6.5, MAX_TUNNEL)
	var ra := minf(r, _fits(a))
	var rb := minf(r, _fits(b))
	r = maxf(ra, rb)
	# Each end aims straight at the other cavern first; where that would put
	# its mouth over another tunnel's, it swings round the wall a way.
	var swings := [0.0, 0.55, -0.55, 1.1, -1.1, 1.6, -1.6]
	var tries := maxi(attempts, swings.size())
	for attempt in tries:
		var wander := 0.3 if attempt < tries - 1 else 0.08
		var off: float = swings[attempt % swings.size()]
		var aim_a: Variant = via_a if via_a != null else _aim(a, b, off)
		var aim_b: Variant = via_b if via_b != null else _aim(b, a, -off)
		var pts := _relax_bends(_tunnel_curve(a, b, ra, rb, wander, aim_a, aim_b), r)
		if pts.size() < 2 or _mouth_clash(ia, pts[0], ra) or _mouth_clash(ib, pts[pts.size() - 1], rb):
			continue
		if _tunnel_ok(pts, r, ia, ib):
			var tunnel := {"a": ia, "b": ib, "points": pts, "radius": r, "ra": ra, "rb": rb,
				"kind_a": a.kind, "kind_b": b.kind}
			var ti := tunnels.size()
			tunnels.append(tunnel)
			a.links.append(ti)
			b.links.append(ti)
			_index_tunnel(ti)
			return true
	return false

## A point to aim a mouth at: toward `to`, swung `off` radians round `from`.
func _aim(from: Dictionary, to: Dictionary, off: float) -> Variant:
	if off == 0.0:
		return null
	var d := Vector3(to.centre.x - from.centre.x, 0.0, to.centre.z - from.centre.z).normalized()
	var p: Vector3 = (from.centre as Vector3) + d.rotated(Vector3.UP, off) * (maxf(float(from.rx), float(from.rz)) * BUMP_MAX + 30.0)
	return Vector3(p.x, float(from.floor) + 3.0, p.z)

## Would a mouth at `at` (of radius r) overlap one already opened in cavern `ri`?
func _mouth_clash(ri: int, at: Vector3, r: float) -> bool:
	for ti in rooms[ri].links:
		var t: Dictionary = tunnels[ti]
		var tp: PackedVector3Array = t.points
		var other := tp[0] if int(t.a) == ri else tp[tp.size() - 1]
		var other_r := float(t.get("ra", t.radius)) if int(t.a) == ri else float(t.get("rb", t.radius))
		if Vector2(at.x - other.x, at.z - other.z).length() < (r + other_r) * WIDEN + 3.0:
			return true
	return false

## Largest tunnel radius a cavern takes: the tube, floor to roof, under its
## lowest-bulging ceiling with a little to spare.
func _fits(room: Dictionary) -> float:
	var ceiling := float(room.ry) * (0.55 + 0.84) - 1.0
	return clampf(ceiling / (1.08 + FLOOR_CUT), 2.5, MAX_TUNNEL)

## Where a tunnel leaves a cavern: toward `toward`, at the height that puts
## the tube's floor a hair under the cavern's, and as far out as the widest
## part of the tube's outline still meets the wall - so every part of the
## tube's end is at or beyond the wall and slides back onto it.
func _mouth(room: Dictionary, toward: Vector3, r: float) -> Vector3:
	var dir := Vector3(toward.x - room.centre.x, 0.0, toward.z - room.centre.z).normalized()
	var side := Vector3.UP.cross(dir).normalized()
	var base := Vector3(room.centre.x, float(room.floor) - 0.03 + r * FLOOR_CUT, room.centre.z)
	var far := maxf(float(room.rx), float(room.rz)) * BUMP_MAX * 1.1 + 4.0
	var reach := 0.0
	for s in section(r):
		var o := base + side * s.x + Vector3.UP * s.y
		if not _inside_wall(room, o):
			continue
		reach = maxf(reach, _wall_hit(room, o, dir, 0.0, far))
	return base + dir * reach

## The tube's outline at radius r, about its axis: x across, y up. Flat along
## the bottom - the floor - and wider than it is tall.
static func section(r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for j in SIDES:
		var a := TAU * float(j) / float(SIDES) - PI * 0.5
		out.append(Vector2(cos(a) * r * WIDEN, maxf(sin(a) * r * 1.08, -r * FLOOR_CUT)))
	return out

## How far out along `v` the outline's edge is, as a multiple of v (over 1
## when v is inside the outline).
static func _outline_scale(poly: PackedVector2Array, v: Vector2) -> float:
	var best := INF
	for j in poly.size():
		var a := poly[j]
		var e := poly[(j + 1) % poly.size()] - a
		var det := v.x * (-e.y) - v.y * (-e.x)
		if absf(det) < 0.000001:
			continue
		var k := (a.x * (-e.y) - a.y * (-e.x)) / det
		var m := (v.x * a.y - v.y * a.x) / det
		if k > 0.0 and m >= -0.0001 and m <= 1.0001:
			best = minf(best, k)
	return best

## The lumpiness of a cavern's wall in a direction (a unit vector in the
## cavern's own frame): the same noise its mesh is built from. Broad lobes
## push the sides out into bays - hardly at all up in the roof, so the cover
## over it holds - with smaller lumps over everything.
func _bump(room: Dictionary, v: Vector3) -> float:
	var seed_at := float(room.index) * 7.3
	var lobe := maxf(0.0, _noise.get_noise_3d(v.x * 0.75 + seed_at, v.y * 0.75 + 40.0, v.z * 0.75))
	lobe = minf(lobe * 1.2, 0.62) * (1.0 - 0.8 * absf(v.y))
	return 1.0 + lobe + 0.1 * _noise.get_noise_3d(v.x * 2.0 + float(room.index), v.y * 2.0, v.z * 2.0)

## Inside the cavern's wall (its floor aside)?
func _inside_wall(room: Dictionary, p: Vector3) -> bool:
	var local: Vector3 = (p - (room.centre as Vector3)).rotated(Vector3.UP, -float(room.yaw))
	var q := Vector3(local.x / float(room.rx), local.y / float(room.ry), local.z / float(room.rz))
	var length := q.length()
	if length < 0.0001:
		return true
	return length < _bump(room, q / length)

## How far along `dir` from `from` the wall is, between `lo` (inside) and `hi`
## (outside).
func _wall_hit(room: Dictionary, from: Vector3, dir: Vector3, lo: float, hi: float) -> float:
	if _inside_wall(room, from + dir * hi):
		return hi
	for i in 26:
		var mid := (lo + hi) * 0.5
		if _inside_wall(room, from + dir * mid):
			lo = mid
		else:
			hi = mid
	return lo

## For an entrance cavern whose partner lies behind the way in: a point off to
## the side and a little below, for the tunnel to leave toward. Else null.
func _side_exit(from: Dictionary, to: Dictionary) -> Variant:
	if from.entrance == null:
		return null
	var dir: Vector3 = from.entrance.dir
	var toward: Vector3 = to.centre - from.centre
	toward.y = 0.0
	if toward.normalized().dot(-dir) <= 0.2:
		return null
	var side := Vector3(dir.z, 0.0, -dir.x)
	if toward.dot(side) < 0.0:
		side = -side
	var reach := maxf(float(from.rx), float(from.rz)) * BUMP_MAX + 40.0
	var p: Vector3 = from.centre + side * reach + dir * 6.0
	return Vector3(p.x, float(from.floor) - 4.0, p.z)

func _tunnel_curve(a: Dictionary, b: Dictionary, ra: float, rb: float, wander: float, via_a: Variant = null,
		via_b: Variant = null) -> PackedVector3Array:
	var s := _mouth(a, via_a if via_a != null else b.centre, ra)
	var e := _mouth(b, via_b if via_b != null else a.centre, rb)
	var span := Vector2(e.x - s.x, e.z - s.z).length()
	var side := Vector3(-(e.z - s.z), 0.0, e.x - s.x).normalized()
	var mids := clampi(int(span / 60.0), 1, 5)
	# Each end leaves its cavern level and square to the wall for a stretch,
	# so the tube's floor runs on from the cavern's floor, not down through it.
	var lead := maxf(16.0, maxf(ra, rb) * WIDEN * 2.0)
	var lead_a := s + _flat(s - (a.centre as Vector3)) * lead
	var lead_b := e + _flat(e - (b.centre as Vector3)) * lead
	var ctrl: Array = [s - (lead_a - s).normalized() * 0.01, s, lead_a]
	if via_a != null:
		ctrl.append(via_a)
	for i in mids:
		var t := float(i + 1) / float(mids + 1)
		var p := s.lerp(e, t)
		p += side * _rng.randf_range(-wander, wander) * span / float(mids + 1) * 1.6
		p.y += _rng.randf_range(-3.0, 3.0) * wander * 4.0
		ctrl.append(p)
	if via_b != null:
		ctrl.append(via_b)
	ctrl.append(lead_b)
	ctrl.append(e)
	ctrl.append(e - (lead_b - e).normalized() * 0.01)
	var out := PackedVector3Array()
	for i in range(1, ctrl.size() - 2):
		var p0: Vector3 = ctrl[i - 1]
		var p1: Vector3 = ctrl[i]
		var p2: Vector3 = ctrl[i + 1]
		var p3: Vector3 = ctrl[i + 2]
		var seg := p1.distance_to(p2)
		var n := maxi(1, int(seg / RING_STEP))
		for k in n:
			var t := float(k) / float(n)
			out.append(_catmull(p0, p1, p2, p3, t))
	out.append(e)
	# Dead level for the first stretch out of each cavern.
	for i in out.size():
		var q := out[i]
		if Vector2(q.x - s.x, q.z - s.z).length() < 14.0:
			q.y = s.y
		elif Vector2(q.x - e.x, q.z - e.z).length() < 14.0:
			q.y = e.y
		out[i] = q
	return out

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()

static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

## How tight the tube bends at point i: the radius of the circle through the
## points either side of it. A bend tighter than the tube is wide folds its
## inside wall through itself.
static func bend_radius(pts: PackedVector3Array, i: int, reach: int = 2) -> float:
	if i - reach < 0 or i + reach >= pts.size():
		return INF
	var a := pts[i - reach]
	var b := pts[i]
	var c := pts[i + reach]
	var ab := a.distance_to(b)
	var bc := b.distance_to(c)
	var ca := c.distance_to(a)
	var area := (b - a).cross(c - a).length() * 0.5
	if area < 0.0001:
		return INF
	return ab * bc * ca / (4.0 * area)

## Eases out any bend tighter than the tube can take: each point on it is
## drawn toward the middle of its neighbours, a little at a time, until the
## line is smooth enough. The ends, square to their caverns' walls, stay put.
##
## Only the points whose bend may have changed since they were last found
## easy enough are measured again (a point's bend hangs on it and the points
## two either side), and the measuring is written out here rather than called:
## the same points move in the same order as measuring every point every time
## round, for a fraction of the work. Planning the caves is mostly this.
static func _relax_bends(pts: PackedVector3Array, r: float) -> PackedVector3Array:
	var tightest := min_bend(r) * 1.05
	var out := pts.duplicate()
	var keep := 2
	var n := out.size()
	var dirty := PackedByteArray()
	dirty.resize(n)
	dirty.fill(1)
	for it in 120:
		var moved := false
		for i in range(keep, n - keep):
			if dirty[i] == 0:
				continue
			# bend_radius(out, i), inline.
			var a := out[i - 2]
			var b := out[i]
			var c := out[i + 2]
			var area := (b - a).cross(c - a).length() * 0.5
			if area < 0.0001 or a.distance_to(b) * b.distance_to(c) * c.distance_to(a) / (4.0 * area) >= tightest:
				dirty[i] = 0
				continue
			for j in range(i - 1, i + 2):
				if j < keep or j >= n - keep:
					continue
				var mid := (out[j - 1] + out[j + 1]) * 0.5
				out[j] = out[j].lerp(mid, 0.5)
				for m in range(maxi(0, j - 2), mini(n, j + 3)):
					dirty[m] = 1
			moved = true
		if not moved:
			break
	return out

## The tightest a tunnel of radius r may bend.
static func min_bend(r: float) -> float:
	return r * WIDEN * 1.3

func _tunnel_ok(pts: PackedVector3Array, r: float, ia: int, ib: int) -> bool:
	var tightest := min_bend(r)
	for i in range(2, pts.size() - 2):
		if bend_radius(pts, i) < tightest:
			return false
	for i in pts.size():
		var p := pts[i]
		if i > 0:
			var q := pts[i - 1]
			var run := Vector2(p.x - q.x, p.z - q.z).length()
			if absf(p.y - q.y) > maxf(0.3, run) * MAX_GRADE * _grade_scale:
				return false
		# Near the caverns it joins a tunnel may run as shallow as they do.
		var near_end := minf(p.distance_to(pts[0]), p.distance_to(pts[pts.size() - 1]))
		var cover := COVER if near_end > 60.0 else 2.5
		if i % 2 == 0 and terrain.height_at(p.x, p.z) - (p.y + r * 1.1) < cover:
			return false
		# Clear of every cavern but its own two.
		for ri in _near_rooms(p):
			if ri == ia or ri == ib:
				continue
			if _in_room(rooms[ri], p, r * WIDEN + 4.0):
				return false
		# Clear of every other tunnel, except close to the caverns it joins,
		# where tunnels meet anyway.
		if p.distance_to(pts[0]) < 40.0 or p.distance_to(pts[pts.size() - 1]) < 40.0:
			continue
		for hit in _near_tunnel_points(p):
			var other: Dictionary = tunnels[hit[0]]
			var q2: Vector3 = (other.points as PackedVector3Array)[hit[1]]
			if p.distance_to(q2) < (r + float(other.radius)) * WIDEN + 5.0:
				return false
	return true

# --- Spatial index ------------------------------------------------------------

func _cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / GRID)), int(floor(p.z / GRID)))

func _index_tunnel(ti: int) -> void:
	var pts: PackedVector3Array = tunnels[ti].points
	for k in pts.size():
		var c := _cell(pts[k])
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var key := Vector2i(c.x + dx, c.y + dz)
				if not _grid.has(key):
					_grid[key] = []
				(_grid[key] as Array).append([ti, k])

func _near_tunnel_points(p: Vector3) -> Array:
	return _grid.get(_cell(p), [])

func _near_rooms(p: Vector3) -> Array:
	var out: Array = []
	for i in rooms.size():
		var room: Dictionary = rooms[i]
		var reach := maxf(room.rx, room.rz) * BUMP_MAX + 80.0
		if absf(room.centre.x - p.x) < reach and absf(room.centre.z - p.z) < reach:
			out.append(i)
	return out

func _in_room(room: Dictionary, p: Vector3, margin: float) -> bool:
	var local: Vector3 = (p - (room.centre as Vector3)).rotated(Vector3.UP, -float(room.yaw))
	var q := Vector3(local.x / (float(room.rx) + margin), local.y / (float(room.ry) + margin),
		local.z / (float(room.rz) + margin))
	var length := q.length()
	if p.y < float(room.floor) - margin:
		return false
	return length <= 1.0 or length <= _bump(room, q / length)

# --- Queries -------------------------------------------------------------------

## True inside a cavern or tunnel (or within `margin` of one).
func contains(p: Vector3, margin: float = 0.5) -> bool:
	for ri in _near_rooms_fast(p):
		if _in_room(rooms[ri], p, margin):
			return true
	for hit in _near_tunnel_points(p):
		var t: Dictionary = tunnels[hit[0]]
		var q: Vector3 = (t.points as PackedVector3Array)[hit[1]]
		if p.distance_to(q) < float(t.radius) * WIDEN * 1.05 + margin + RING_STEP * 0.5:
			return true
	for cave in entrances:
		if cave.depth_factor(p) > 0.0:
			return true
	return false

var _room_cells: Dictionary = {}

func _near_rooms_fast(p: Vector3) -> Array:
	return _room_cells.get(_cell(p), [])

func _index_rooms() -> void:
	_room_cells.clear()
	for i in rooms.size():
		var room: Dictionary = rooms[i]
		var reach := maxf(room.rx, room.rz) * BUMP_MAX + 2.0
		var lo := _cell(room.centre - Vector3(reach, 0, reach))
		var hi := _cell(room.centre + Vector3(reach, 0, reach))
		for x in range(lo.x, hi.x + 1):
			for z in range(lo.y, hi.y + 1):
				var key := Vector2i(x, z)
				if not _room_cells.has(key):
					_room_cells[key] = []
				(_room_cells[key] as Array).append(i)

## 0 above ground, 1 in the caves: drives the darkness underground.
func depth_factor(eye: Vector3) -> float:
	for cave in entrances:
		var f := cave.depth_factor(eye)
		if f > 0.0:
			return f
	if eye.y < terrain.height_at(eye.x, eye.z) - 1.0 and contains(eye, 1.0):
		return 1.0
	return 0.0

## The cave biome at a point underground, or -1.
func kind_at(p: Vector3) -> int:
	for ri in _near_rooms_fast(p):
		if _in_room(rooms[ri], p, 1.0):
			return int(rooms[ri].kind)
	for hit in _near_tunnel_points(p):
		var t: Dictionary = tunnels[hit[0]]
		var pts: PackedVector3Array = t.points
		if p.distance_to(pts[hit[1]]) < float(t.radius) * WIDEN + 2.0:
			return int(t.kind_a) if hit[1] < pts.size() / 2 else int(t.kind_b)
	return -1

## A random spot on a cavern's wall, from knee height to well up the side,
## and the way back into the cavern from it: [point, inward]. Null where it
## would land in a tunnel's mouth or the way in.
func wall_point(room: Dictionary, rng: RandomNumberGenerator) -> Variant:
	var a := rng.randf() * TAU
	var dir := Vector3(cos(a), 0.0, sin(a))
	var from := Vector3(room.centre.x, float(room.floor) + rng.randf_range(1.0, float(room.ry) * 0.9), room.centre.z)
	if not _inside_wall(room, from):
		return null
	var far := maxf(float(room.rx), float(room.rz)) * BUMP_MAX * 1.1 + 4.0
	var hit := _wall_hit(room, from, dir, 0.0, far)
	if hit >= far - 0.1:
		return null
	var p := from + dir * hit
	for ti in room.links:
		var mouth := _tube_end(ti, int(room.index))
		var d: Vector3 = p - (mouth.origin as Vector3)
		var r := float(tunnels[ti].radius)
		if d.length() < r * WIDEN + 6.0:
			return null
	if room.entrance != null:
		var e: Dictionary = room.entrance
		var ed: Vector3 = e.dir
		var local: Vector3 = Transform3D(Basis(Vector3(ed.z, 0.0, -ed.x), Vector3.UP, ed), e.entrance).affine_inverse() * p
		if absf(local.x) < Cave.SHAFT_WIDTH * 0.5 + 5.0 and local.z < Cave.SHAFT_LENGTH + Cave.TUNNEL_LENGTH + 8.0:
			return null
	# Inward: square to the wall, from the wall's slope either side.
	var probe := 1.5
	var up_hit := _wall_hit(room, from + Vector3.UP * probe, dir, 0.0, far)
	var side := Vector3(-dir.z, 0.0, dir.x)
	var side_hit := _wall_hit(room, from + side * probe, dir, 0.0, far)
	var q_up := from + Vector3.UP * probe + dir * up_hit
	var q_side := from + side * probe + dir * side_hit
	var n := (q_up - p).cross(q_side - p).normalized()
	if n.dot(-dir) < 0.0:
		n = -n
	if n.dot(-dir) < 0.3:
		n = -dir
	return [p, n]

static func _basis_along(axis: Vector3, spin: float) -> Basis:
	var ref := Vector3.RIGHT if absf(axis.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := ref.cross(axis).normalized()
	var z := x.cross(axis).normalized()
	return Basis(x, axis, z) * Basis(Vector3.UP, spin)

## A random spot on a cavern's floor, for its ore and its mushrooms.
func floor_point(room: Dictionary, rng: RandomNumberGenerator) -> Vector3:
	var a := rng.randf() * TAU
	var d := sqrt(rng.randf()) * 0.62
	var local := Vector3(cos(a) * float(room.rx) * d, 0.0, sin(a) * float(room.rz) * d)
	var p: Vector3 = room.centre + local.rotated(Vector3.UP, float(room.yaw))
	return Vector3(p.x, float(room.floor), p.z)

# --- Building ------------------------------------------------------------------

func _ready() -> void:
	active = self
	_index_rooms()
	var body := StaticBody3D.new()
	body.name = "CaveRock"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	body.physics_material_override = pm
	add_child(body)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	# Both sides drawn: where a tunnel's end stands proud of a bulging wall,
	# its outside shows as rock rather than a see-through gap.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in rooms.size():
		_emit(body, mat, _room_mesh(i), "Cavern%d" % i)
		_dress_room(i)
	for ti in tunnels.size():
		_emit(body, mat, _tunnel_mesh(ti), "Tunnel%d" % ti)
		_dress_tunnel(ti)

func _exit_tree() -> void:
	if active == self:
		active = null

class Buf:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

func _emit(body: StaticBody3D, mat: Material, buf: Buf, label: String) -> void:
	var verts := buf.verts
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = buf.normals
	arrays[Mesh.ARRAY_COLOR] = buf.colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 900.0
	add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(verts)
	cs.shape = shape
	body.add_child(cs)

## Adds a triangle facing `inward` (towards the open side), flat shaded.
static func _tri(out: Buf, a: Vector3, b: Vector3, c: Vector3, toward: Vector3, color: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 0.000001:
		return
	if n.dot(toward - (a + b + c) / 3.0) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	out.verts.append_array(PackedVector3Array([a, b, c]))
	out.normals.append_array(PackedVector3Array([n, n, n]))
	out.colors.append_array(PackedColorArray([color, color, color]))

func _shade(kind: int, n: Vector3, seed_pos: Vector3) -> Color:
	var pal: Array = PALETTE[kind]
	var base: Color = pal[1] if n.y > 0.75 else pal[0]
	if n.y < -0.6:
		base = base.darkened(0.12)
	var j := float(hash(Vector3i(seed_pos.floor())) % 100) / 100.0 - 0.5
	return base.lightened(j * 0.12) if j > 0.0 else base.darkened(-j * 0.12)

static var _ico_cache: Dictionary = {}

## A unit icosphere, subdivided `level` times: [vertices, triangles].
static func _icosphere(level: int) -> Array:
	if _ico_cache.has(level):
		return _ico_cache[level]
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in v.size():
		v[i] = (v[i] as Vector3).normalized()
	var f: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4],
		[11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for l in level:
		var mid: Dictionary = {}
		var nf: Array = []
		for tri in f:
			var m: Array = []
			for e in 3:
				var i0: int = tri[e]
				var i1: int = tri[(e + 1) % 3]
				var key := Vector2i(mini(i0, i1), maxi(i0, i1))
				if not mid.has(key):
					mid[key] = v.size()
					v.append(((v[i0] as Vector3) + (v[i1] as Vector3)).normalized())
				m.append(mid[key])
			nf.append([tri[0], m[0], m[2]])
			nf.append([tri[1], m[1], m[0]])
			nf.append([tri[2], m[2], m[1]])
			nf.append([m[0], m[1], m[2]])
		f = nf
	var out := [v, f]
	_ico_cache[level] = out
	return out

## A cavern: a lumpy ellipsoid, floor flattened. Where a tunnel leaves it the
## wall inside the tube's outline is pulled out onto the tube's own surface
## and the part that would close the tube off is opened, so the cavern's wall
## runs into the tunnel's with no seam; the entrance tunnel's way in is cut.
func _room_mesh(ri: int) -> Buf:
	var room: Dictionary = rooms[ri]
	var out := Buf.new()
	var size := maxf(float(room.rx), float(room.rz))
	var level := 3 if size < 30.0 else (4 if size < 70.0 else 5)
	var ico := _icosphere(level)
	var basis := Basis(Vector3.UP, float(room.yaw))
	var c: Vector3 = room.centre
	var floor_y: float = room.floor
	var pts: Array = []
	var on_floor := PackedByteArray()
	for v: Vector3 in ico[0]:
		var p := c + basis * Vector3(v.x * float(room.rx), v.y * float(room.ry), v.z * float(room.rz)) * _bump(room, v)
		on_floor.append(int(p.y <= floor_y))
		p.y = maxf(p.y, floor_y)
		pts.append(p)
	# The tubes that start here, each as the frame and outline of its end.
	# Which tube's outline each point was pulled onto (-1: none).
	var opened := PackedInt32Array()
	opened.resize(pts.size())
	opened.fill(-1)
	var mouths: Array = []
	for ti in room.links:
		var mouth := _tube_end(ti, ri)
		mouths.append(mouth)
		var o: Vector3 = mouth.origin
		var out_dir: Vector3 = mouth.out
		var side: Vector3 = mouth.side
		var up: Vector3 = mouth.up
		var poly: PackedVector2Array = mouth.outline
		# Only the near side of the cavern: the wall the tunnel goes through,
		# and the roof just in front of it where the tube is taller.
		# Far enough back to take in a wall that bulges out past the mouth
		# lower down - left standing, it fences off the bottom of the tunnel -
		# and never so far as the cavern's far side.
		var behind := -minf(40.0, Vector2(o.x - c.x, o.z - c.z).length() * 0.6)
		for i in pts.size():
			# The floor stays as it is: the tube's floor carries on from it.
			if on_floor[i]:
				continue
			var d: Vector3 = pts[i] - o
			var t := d.dot(out_dir)
			if t < behind:
				continue
			var v := Vector2(d.dot(side), d.dot(up))
			var k := _outline_scale(poly, v)
			if k < 1.0:
				continue
			v *= k
			pts[i] = o + out_dir * t + side * v.x + up * v.y
			opened[i] = mouths.size() - 1
	var entrance_frame: Variant = null
	if room.entrance != null:
		var e: Dictionary = room.entrance
		var d: Vector3 = e.dir
		var side := Vector3(d.z, 0.0, -d.x)
		entrance_frame = Transform3D(Basis(side, Vector3.UP, d), e.entrance).affine_inverse()
	var inside := c + Vector3(0, float(room.ry) * 0.1, 0)
	for tri in ico[1]:
		var a: Vector3 = pts[tri[0]]
		var b: Vector3 = pts[tri[1]]
		var cc: Vector3 = pts[tri[2]]
		var mid := (a + b + cc) / 3.0
		var floor_tri: bool = on_floor[tri[0]] and on_floor[tri[1]] and on_floor[tri[2]]
		# Pulled wholly onto one tube's outline: if it lies along the outline
		# it is wall (the tube's sides carried back into the cavern), and it
		# stays; if it spans across the outline it would close the tube off,
		# and that is the opening.
		var m := opened[tri[0]]
		if m >= 0 and opened[tri[1]] == m and opened[tri[2]] == m:
			var mouth: Dictionary = mouths[m]
			var d: Vector3 = mid - (mouth.origin as Vector3)
			if _outline_scale(mouth.outline, Vector2(d.dot(mouth.side), d.dot(mouth.up))) > 1.03:
				continue
		# The way in is cut through the wall; the floor under it stays, so
		# there is no gap at the threshold.
		if not floor_tri and _cut_away(mid, entrance_frame, floor_y):
			continue
		var n := (cc - a).cross(b - a)
		if n.dot(inside - mid) < 0.0:
			n = -n
		_tri(out, a, b, cc, inside, _shade(int(room.kind), n.normalized(), mid))
	return out

## A tunnel's end at cavern `ri`: where its axis starts, the way out along it
## into the tunnel, its across and up, and its outline there - the same frame
## the tube's end ring is built in.
func _tube_end(ti: int, ri: int) -> Dictionary:
	var t: Dictionary = tunnels[ti]
	var tp: PackedVector3Array = t.points
	var at_a: bool = int(t.a) == ri
	var o := tp[0] if at_a else tp[tp.size() - 1]
	var along := (tp[1] - tp[0]).normalized() if at_a else (tp[tp.size() - 1] - tp[tp.size() - 2]).normalized()
	var frame := _ring_frame(along)
	var r := float(t.get("ra", t.radius)) if at_a else float(t.get("rb", t.radius))
	return {"origin": o, "out": along if at_a else -along, "side": frame[0], "up": frame[1],
		"outline": section(r)}

## Across and up for a ring on a tube running along `tangent`.
static func _ring_frame(tangent: Vector3) -> Array:
	var side := Vector3.UP.cross(tangent).normalized()
	var up := tangent.cross(side).normalized()
	if up.y < 0.0:
		up = -up
	return [side, up]

func _cut_away(p: Vector3, entrance_frame: Variant, floor_y: float) -> bool:
	if entrance_frame != null:
		var local: Vector3 = (entrance_frame as Transform3D) * p
		var z_end := Cave.SHAFT_LENGTH + Cave.TUNNEL_LENGTH
		if absf(local.x) < Cave.SHAFT_WIDTH * 0.5 + 0.9 and local.z < z_end + 1.0 \
				and p.y < floor_y + Cave.TUNNEL_HEIGHT + 0.9:
			return true
	return false

## A tunnel: a broad tube along the curve, floor flat, its size easing from
## one end's to the other's and wandering a little ring to ring. Each end ring
## is slid, point by point, along the tunnel onto its cavern's wall, so the
## tube ends exactly where the wall is.
func _tunnel_mesh(ti: int) -> Buf:
	var t: Dictionary = tunnels[ti]
	var pts: PackedVector3Array = t.points
	var ra := float(t.get("ra", t.radius))
	var rb := float(t.get("rb", t.radius))
	var out := Buf.new()
	var rings: Array = []
	var last := pts.size() - 1
	for k in pts.size():
		var prev := pts[maxi(0, k - 1)]
		var next := pts[mini(last, k + 1)]
		var frame := _ring_frame((next - prev).normalized())
		var along := float(k) / float(maxi(1, last))
		var rk := lerpf(ra, rb, smoothstep(0.0, 1.0, along))
		# The rings at the caverns are true to size, so they meet the walls.
		if k > 1 and k < last - 1:
			rk *= 1.0 + 0.1 * _noise.get_noise_2d(float(k) * 0.7, float(ti) * 3.1)
		var ring: Array = []
		for sp in section(rk):
			ring.append(pts[k] + (frame[0] as Vector3) * sp.x + (frame[1] as Vector3) * sp.y)
		rings.append(ring)
	if pts.size() >= 2:
		var out_a := (pts[1] - pts[0]).normalized()
		var out_b := (pts[last - 1] - pts[last]).normalized()
		_fit_to_wall(rings[0], rooms[int(t.a)], out_a)
		_fit_to_wall(rings[last], rooms[int(t.b)], out_b)
		# An end ring slid on along the tunnel must not pass the rings after
		# it, or the tube folds back through itself.
		_keep_ahead(rings, out_a, 1)
		_keep_ahead(rings, out_b, -1)
	for k in rings.size() - 1:
		var kind: int = int(t.kind_a) if k < rings.size() / 2 else int(t.kind_b)
		var axis := (pts[k] + pts[k + 1]) * 0.5
		for j in SIDES:
			var j2 := (j + 1) % SIDES
			var a: Vector3 = rings[k][j]
			var b: Vector3 = rings[k][j2]
			var c: Vector3 = rings[k + 1][j2]
			var d: Vector3 = rings[k + 1][j]
			var mid := (a + b + c + d) * 0.25
			var n := (b - a).cross(d - a)
			if n.dot(axis - mid) < 0.0:
				n = -n
			var col := _shade(kind, n.normalized(), mid)
			_tri(out, a, b, c, axis, col)
			_tri(out, a, c, d, axis, col)
	return out

## Walks in from one end (`step` 1 from the start, -1 from the end): each
## ring's points stay at least a little further along `out` than the ring
## before them.
static func _keep_ahead(rings: Array, out: Vector3, step: int) -> void:
	var k := 0 if step > 0 else rings.size() - 1
	while k + step >= 0 and k + step < rings.size():
		var moved := false
		for j in (rings[k] as Array).size():
			var here: Vector3 = rings[k][j]
			var next: Vector3 = rings[k + step][j]
			var gap := (next - here).dot(out)
			if gap < 0.4:
				rings[k + step][j] = next + out * (0.4 - gap)
				moved = true
		if not moved:
			return
		k += step

## Slides each point of an end ring back along the tunnel (`out` points away
## from the cavern) to where the cavern's wall is, a hand's width inside it.
func _fit_to_wall(ring: Array, room: Dictionary, out: Vector3) -> void:
	var reach := maxf(float(room.rx), float(room.rz)) * BUMP_MAX * 1.1 + 4.0
	for j in ring.size():
		var p: Vector3 = ring[j]
		if _inside_wall(room, p + out * 0.3):
			# Still in the cavern - the wall bulges out past the mouth here:
			# on along the tunnel to where the wall is.
			var u2 := 0.5
			while u2 <= reach and _inside_wall(room, p + out * u2):
				u2 += 0.5
			if u2 <= reach:
				ring[j] = p + out * (_wall_hit(room, p, out, maxf(0.0, u2 - 0.5), u2) - 0.15)
			continue
		# The nearest point back along the tunnel that is inside the cavern;
		# the wall is between there and here.
		var inside_at := -1.0
		var u := 0.5
		while u <= reach:
			if _inside_wall(room, p - out * u):
				inside_at = u
				break
			u += 0.5
		if inside_at < 0.0:
			continue
		var back := p - out * inside_at
		var hit := _wall_hit(room, back, out, 0.0, inside_at + 3.0)
		# Never forward of where it was: that would fold it over the next ring.
		ring[j] = back + out * minf(hit - 0.15, inside_at)

# --- Dressing --------------------------------------------------------------------

func _dress_room(ri: int) -> void:
	var room: Dictionary = rooms[ri]
	var kind: int = room.kind
	var pal: Array = PALETTE[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(ri) + 17
	var g := Greeble.new()
	var size := maxf(float(room.rx), float(room.rz))
	var count := int(size * 0.8) + 3
	var floor_y: float = room.floor
	var top: float = room.centre.y + float(room.ry) * 0.85
	# Formations grow out of the walls, never the floor - the floor is left
	# clear to drive and work on. Kept close to the rock: a big cavern gets
	# more of them, not bigger ones.
	var grand := clampf(size / 40.0, 1.0, 2.0)
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 4:
		tries += 1
		var spot: Variant = wall_point(room, rng)
		if spot == null:
			continue
		placed += 1
		var p: Vector3 = spot[0]
		var inward: Vector3 = spot[1]
		var i := placed
		# Out of the wall, tipped a little up or down, spun about its own axis.
		var tip := Vector3.UP if rng.randf() < 0.5 else Vector3.DOWN
		var axis := (inward + tip * rng.randf_range(0.1, 0.5)).normalized()
		var out := _basis_along(axis, rng.randf() * TAU)
		var flat := Basis.looking_at(Vector3(inward.x, 0.0, inward.z).normalized(), Vector3.UP)
		match kind:
			Kind.CRYSTAL, Kind.ABYSS:
				var color: Color = [Color(0.7, 0.45, 1.0), Color(0.45, 0.9, 1.0), Color(1.0, 0.55, 0.9)][i % 3] \
					if kind == Kind.CRYSTAL else Color(0.3, 0.6, 1.0)
				for k in 3:
					var fan := _basis_along((axis + Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35),
						rng.randf_range(-0.35, 0.35))).normalized(), rng.randf() * TAU)
					g.prism(6, rng.randf_range(0.15, 0.4), 0.0, rng.randf_range(0.6, 1.8) * grand,
						Transform3D(fan, p - axis * 0.3), color, true)
			Kind.ICE:
				g.prism(5, rng.randf_range(0.25, 0.5) * grand, 0.0, rng.randf_range(0.8, 2.0) * grand,
					Transform3D(out, p - axis * 0.3), Color(0.8, 0.92, 1.0), i % 4 == 0)
			Kind.DESERT:
				# Sandstone ledges, lying along the wall.
				g.box(Vector3(rng.randf_range(2.0, 4.5), rng.randf_range(0.3, 0.7), rng.randf_range(0.6, 1.2)) * grand,
					Transform3D(flat, p), (pal[0] as Color).lightened(0.06))
			Kind.FUNGAL:
				# Bracket fungus: flat glowing shelves on the rock.
				var shelf := rng.randf_range(0.3, 0.7) * grand
				g.prism(8, shelf, shelf * 0.2, 0.18, Transform3D(Basis(), p + inward * shelf * 0.4),
					[Color(0.4, 1.0, 0.6), Color(0.3, 0.9, 1.0), Color(0.9, 0.5, 1.0)][i % 3], true)
			Kind.MAGMA:
				if i % 2 == 0:
					g.prism(6, rng.randf_range(0.4, 0.7) * grand, 0.0, rng.randf_range(0.8, 2.0) * grand,
						Transform3D(out, p - axis * 0.3), Color(0.14, 0.12, 0.12))
				else:
					# A glowing seam in the rock.
					g.box(Vector3(rng.randf_range(1.5, 3.5), 0.12, 0.1) * grand,
						Transform3D(flat * Basis(Vector3.FORWARD, rng.randf_range(-0.6, 0.6)),
						p + inward * 0.05), Color(1.0, 0.42, 0.1), true)
			_:
				# River caves: short, stubby knuckles of flowstone.
				g.prism(5, rng.randf_range(0.3, 0.6) * grand, 0.0, rng.randf_range(0.6, 1.6) * grand,
					Transform3D(out, p - axis * 0.3), (pal[0] as Color).lightened(0.1))
	_dress_ceiling(room, kind, pal, rng, g, int(size * 0.5) + 4)
	if not g.is_empty():
		var mi := g.instance("CaveDressing", false)
		mi.visibility_range_end = 320.0
		add_child(mi)
	# A pool in the river caves' bigger caverns; a lava pool in the magma ones.
	if (kind == Kind.RIVER or kind == Kind.MAGMA) and size > 10.0:
		var pool := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(float(room.rx) * 0.9, float(room.rz) * 0.7)
		pool.mesh = pm
		pool.position = Vector3(room.centre.x, floor_y + 0.12, room.centre.z) \
			+ Vector3(float(room.rx) * 0.2, 0, 0).rotated(Vector3.UP, float(room.yaw))
		pool.rotation.y = float(room.yaw)
		var wm := StandardMaterial3D.new()
		if kind == Kind.RIVER:
			wm.albedo_color = Color(0.1, 0.3, 0.38, 0.8)
			wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			wm.roughness = 0.05
			wm.metallic = 0.3
		else:
			wm.albedo_color = Color(1.0, 0.4, 0.1)
			wm.emission_enabled = true
			wm.emission = Color(1.0, 0.35, 0.05)
			wm.emission_energy_multiplier = 2.2
		pool.material_override = wm
		add_child(pool)
	var light := OmniLight3D.new()
	light.position = room.centre + Vector3(0, float(room.ry) * 0.2, 0)
	light.light_color = pal[2]
	light.light_energy = 1.3 if kind != Kind.MAGMA else 2.0
	light.omni_range = minf(size * 1.5 + 4.0, 140.0)
	light.omni_attenuation = 0.8
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 180.0
	light.distance_fade_length = 30.0
	add_child(light)

## Hanging from the roof: stalactites, icicles, crystal clusters and the like,
## short and pointing down, spread over the ceiling.
func _dress_ceiling(room: Dictionary, kind: int, pal: Array, rng: RandomNumberGenerator, g: Greeble, count: int) -> void:
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 4:
		tries += 1
		var p: Variant = ceiling_point(room, rng)
		if p == null:
			continue
		placed += 1
		var at: Vector3 = p
		var hang := Basis(Vector3.RIGHT, PI) * Basis(Vector3.UP, rng.randf() * TAU)
		match kind:
			Kind.CRYSTAL, Kind.ABYSS:
				var color: Color = [Color(0.7, 0.45, 1.0), Color(0.45, 0.9, 1.0)][placed % 2] if kind == Kind.CRYSTAL else Color(0.3, 0.6, 1.0)
				for k in 2:
					g.prism(6, rng.randf_range(0.12, 0.3), 0.0, rng.randf_range(0.5, 1.4),
						Transform3D(hang, at + Vector3(rng.randf_range(-0.4, 0.4), 0.2, rng.randf_range(-0.4, 0.4))), color, true)
			Kind.ICE:
				g.prism(5, rng.randf_range(0.12, 0.3), 0.0, rng.randf_range(0.8, 2.2), Transform3D(hang, at + Vector3(0, 0.2, 0)),
					Color(0.82, 0.93, 1.0), placed % 5 == 0)
			Kind.FUNGAL:
				# Glowing threads hanging down.
				g.prism(4, 0.04, 0.02, rng.randf_range(0.8, 2.5), Transform3D(hang, at + Vector3(0, 0.1, 0)),
					[Color(0.4, 1.0, 0.6), Color(0.3, 0.9, 1.0)][placed % 2], true)
			Kind.MAGMA:
				g.prism(6, rng.randf_range(0.25, 0.5), 0.0, rng.randf_range(0.6, 1.5), Transform3D(hang, at + Vector3(0, 0.2, 0)),
					Color(0.16, 0.13, 0.12))
			Kind.DESERT:
				g.prism(6, rng.randf_range(0.3, 0.6), rng.randf_range(0.1, 0.2), rng.randf_range(0.3, 0.8), Transform3D(hang, at + Vector3(0, 0.2, 0)),
					(pal[0] as Color).lightened(0.05))
			_:
				g.prism(5, rng.randf_range(0.2, 0.45), 0.0, rng.randf_range(0.6, 1.8), Transform3D(hang, at + Vector3(0, 0.25, 0)),
					(pal[0] as Color).lightened(0.08))

## A spot on a cavern's roof, straight up from somewhere over its floor.
func ceiling_point(room: Dictionary, rng: RandomNumberGenerator) -> Variant:
	var a := rng.randf() * TAU
	var d := sqrt(rng.randf()) * 0.7
	var local := Vector3(cos(a) * float(room.rx) * d, 0.0, sin(a) * float(room.rz) * d)
	var from: Vector3 = (room.centre as Vector3) + local.rotated(Vector3.UP, float(room.yaw))
	from.y = float(room.floor) + 1.0
	if not _inside_wall(room, from):
		return null
	var up := _wall_hit(room, from, Vector3.UP, 0.0, float(room.ry) * 3.0)
	if up < 3.0:
		return null
	# Clear of the tunnel mouths, whose roofs are the tunnels' own.
	var p := from + Vector3.UP * up
	for ti in room.links:
		var mouth := _tube_end(ti, int(room.index))
		if Vector2(p.x - mouth.origin.x, p.z - mouth.origin.z).length() < float(tunnels[ti].radius) * WIDEN + 4.0:
			return null
	return p

## Glowing bits along a tunnel's walls every so often, in its biome's colour,
## so a tunnel has landmarks and is never pitch black between caverns.
func _dress_tunnel(ti: int) -> void:
	var t: Dictionary = tunnels[ti]
	var pts: PackedVector3Array = t.points
	var g := Greeble.new()
	var r: float = t.radius
	var k := 6
	while k < pts.size() - 6:
		var kind: int = int(t.kind_a) if k < pts.size() / 2 else int(t.kind_b)
		var tangent := (pts[k + 1] - pts[k - 1]).normalized()
		var side := Vector3.UP.cross(tangent).normalized()
		var s := 1.0 if k % 2 == 0 else -1.0
		var at := pts[k] + side * s * r * WIDEN * 0.75 - Vector3(0, r * FLOOR_CUT, 0)
		g.prism(5, 0.18, 0.0, 0.9, Transform3D(Basis(tangent, -s * 0.5), at), (PALETTE[kind][2] as Color), true)
		g.prism(5, 0.12, 0.0, 0.6, Transform3D(Basis(tangent, -s * 0.8), at + tangent * 0.4), (PALETTE[kind][2] as Color).lightened(0.2), true)
		# And a few short points hanging from the roof.
		var roof := pts[k] + Vector3(0, r * 1.08 * 0.93, 0)
		for n in 3:
			var off := side * float(n - 1) * r * 0.5 + tangent * float(n % 2) * 1.2
			g.prism(5, 0.14 + 0.05 * float(n), 0.0, 0.5 + 0.3 * float(n % 2),
				Transform3D(Basis(Vector3.RIGHT, PI), roof + off + Vector3(0, 0.15, 0)), (PALETTE[kind][0] as Color).lightened(0.08))
		k += 11
	if not g.is_empty():
		var mi := g.instance("TunnelGlow", false)
		mi.visibility_range_end = 160.0
		add_child(mi)

## Counts, for the smoke run and the journal.
func summary() -> Dictionary:
	var kinds: Dictionary = {}
	var below := 0
	for room in rooms:
		kinds[KIND_NAMES[int(room.kind)]] = int(kinds.get(KIND_NAMES[int(room.kind)], 0)) + 1
		if float(room.floor) < Terrain.WATER_LEVEL:
			below += 1
	var length := 0.0
	for t in tunnels:
		var pts: PackedVector3Array = t.points
		for i in pts.size() - 1:
			length += pts[i].distance_to(pts[i + 1])
	return {"caverns": rooms.size(), "tunnels": tunnels.size(), "tunnel_km": length / 1000.0,
		"below_sea": below, "kinds": kinds}
