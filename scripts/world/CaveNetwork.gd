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
## Geometry: a cavern is a faceted, lumpy ellipsoid with a flat floor, and a
## tunnel is an eight-sided tube along a smooth curve with a flat floor, both
## drawn and collided on the inside only. Where a tunnel meets a cavern the
## cavern's wall is cut away inside the tube, and the tube starts just inside
## the cavern with its floor a hair under the cavern's - so the two join with
## an opening you can walk and drive through. Tunnels never cross one another
## or pass through a cavern that is not theirs; the planner rules those out.
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
	Kind.DESERT: [&"ore_copper", &"ore_gold", &"ore_bismuth", &"gem_ruby", &"ore_sunstone"],
	Kind.CRYSTAL: [&"gem_quartz", &"gem_amethyst", &"ore_platinum", &"gem_amethyst", &"gem_diamond"],
	Kind.ICE: [&"ore_nickel", &"ore_silver", &"ore_platinum", &"gem_sapphire", &"gem_sapphire"],
	Kind.FUNGAL: [&"ore_zinc", &"ore_cobalt", &"gem_jade", &"ore_cobalt", &"gem_emerald"],
	Kind.MAGMA: [&"gem_obsidian", &"ore_tungsten", &"gem_obsidian", &"ore_sunstone", &"ore_tungsten"],
	Kind.ABYSS: [&"ore_platinum", &"gem_diamond", &"gem_diamond", &"ore_starmetal", &"gem_sapphire"],
}

## Cover of rock kept over every cavern and tunnel, metres.
const COVER := 9.0
## Steepest a tunnel runs, rise over run.
const MAX_GRADE := 0.55
## Tube floor as a share of the radius below the tube's axis.
const FLOOR_CUT := 0.62
const SIDES := 9
const RING_STEP := 2.5
const GRID := 48.0

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
		var rz := 13.0
		var c := e + d * (z_end + rz * 0.83 - 2.0)
		var floor_y := float(plan_entry.ground) - Cave.CHAMBER_DROP
		var room := _room(Vector3(c.x, 0, c.z), 15.0, 6.0, rz, floor_y, atan2(d.x, d.z),
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
		var roll := _rng.randf()
		var rx := _rng.randf_range(6.0, 9.0)
		if roll < 0.14:
			rx = _rng.randf_range(20.0, 30.0)
		elif roll < 0.5:
			rx = _rng.randf_range(11.0, 16.0)
		var rz := rx * _rng.randf_range(0.75, 1.25)
		var ry := rx * _rng.randf_range(0.5, 0.7)
		var reach := maxf(rx, rz)
		var clear := true
		for other in mine:
			var o: Dictionary = rooms[other]
			if Vector2(o.centre.x, o.centre.z).distance_to(p) < reach + maxf(o.rx, o.rz) + 45.0:
				clear = false
				break
		if not clear:
			continue
		var floor_y := _rng.randf_range(-60.0, -8.0)
		var ceiling := _lowest_ground(Vector3(p.x, 0, p.y), reach) - COVER - ry * 1.6
		floor_y = minf(floor_y, ceiling)
		if floor_y < -90.0:
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
		"floor": floor_y, "yaw": yaw, "kind": kind, "zone": zone, "links": [], "entrance": null}

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
	for round_index in 60:
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
			if up.entrance == null:
				_set_floor(up, float(up.floor) - excess * (0.5 if down.entrance == null else 1.0))
				moved = true
			if down.entrance == null:
				var limit := _lowest_ground(down.centre, maxf(down.rx, down.rz)) - COVER - float(down.ry) * 1.6
				_set_floor(down, minf(limit, float(down.floor) + excess * (0.5 if up.entrance == null else 1.0)))
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
		var floor_y := minf(_rng.randf_range(-80.0, -62.0), _lowest_ground(p, 12.0) - COVER - 12.0)
		var id := rooms.size()
		rooms.append(_room(Vector3(p.x + wob.x, 0, p.z + wob.y), _rng.randf_range(9.0, 14.0),
			_rng.randf_range(5.0, 7.0), _rng.randf_range(9.0, 14.0), floor_y, _rng.randf() * TAU,
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
	var r := _rng.randf_range(2.6, 3.6)
	if int(a.kind) == Kind.ABYSS or int(b.kind) == Kind.ABYSS:
		r = 3.2
	for attempt in attempts:
		var wander := 0.3 if attempt < attempts - 1 else 0.08
		var pts := _tunnel_curve(a, b, r, wander, via_a, via_b)
		if pts.size() >= 2 and _tunnel_ok(pts, r, ia, ib):
			var tunnel := {"a": ia, "b": ib, "points": pts, "radius": r,
				"kind_a": a.kind, "kind_b": b.kind}
			var ti := tunnels.size()
			tunnels.append(tunnel)
			a.links.append(ti)
			b.links.append(ti)
			_index_tunnel(ti)
			return true
	return false

## Where a tunnel leaves a cavern: just inside its wall, toward `toward`, at
## the height that puts the tube's floor a hair under the cavern's.
func _mouth(room: Dictionary, toward: Vector3, r: float) -> Vector3:
	var dir := Vector3(toward.x - room.centre.x, 0.0, toward.z - room.centre.z).normalized()
	var local := dir.rotated(Vector3.UP, -float(room.yaw))
	var along := 1.0 / sqrt(pow(local.x / float(room.rx), 2.0) + pow(local.z / float(room.rz), 2.0))
	# The ellipsoid is narrower at floor height than at its widest.
	var at_floor := along * 0.83
	var p: Vector3 = room.centre + dir * (at_floor - 1.6)
	return Vector3(p.x, float(room.floor) - 0.03 + r * FLOOR_CUT, p.z)

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
	var reach := maxf(float(from.rx), float(from.rz)) + 28.0
	var p: Vector3 = from.centre + side * reach + dir * 6.0
	return Vector3(p.x, float(from.floor) - 4.0, p.z)

func _tunnel_curve(a: Dictionary, b: Dictionary, r: float, wander: float, via_a: Variant = null,
		via_b: Variant = null) -> PackedVector3Array:
	var s := _mouth(a, via_a if via_a != null else b.centre, r)
	var e := _mouth(b, via_b if via_b != null else a.centre, r)
	var span := Vector2(e.x - s.x, e.z - s.z).length()
	var side := Vector3(-(e.z - s.z), 0.0, e.x - s.x).normalized()
	var mids := clampi(int(span / 60.0), 1, 5)
	var ctrl: Array = [s + (s - e).normalized() * 0.01, s]
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
	ctrl.append(e)
	ctrl.append(e + (e - s).normalized() * 0.01)
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
	return out

static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

func _tunnel_ok(pts: PackedVector3Array, r: float, ia: int, ib: int) -> bool:
	for i in pts.size():
		var p := pts[i]
		if i > 0:
			var q := pts[i - 1]
			var run := Vector2(p.x - q.x, p.z - q.z).length()
			if absf(p.y - q.y) > maxf(0.3, run) * MAX_GRADE * _grade_scale:
				return false
		# Near the caverns it joins a tunnel may run as shallow as they do.
		var near_end := minf(p.distance_to(pts[0]), p.distance_to(pts[pts.size() - 1]))
		var cover := COVER if near_end > 40.0 else 2.5
		if i % 2 == 0 and terrain.height_at(p.x, p.z) - (p.y + r * 1.1) < cover:
			return false
		# Clear of every cavern but its own two.
		for ri in _near_rooms(p):
			if ri == ia or ri == ib:
				continue
			if _in_room(rooms[ri], p, r + 4.0):
				return false
		# Clear of every other tunnel, except close to the caverns it joins,
		# where tunnels meet anyway.
		if p.distance_to(pts[0]) < 18.0 or p.distance_to(pts[pts.size() - 1]) < 18.0:
			continue
		for hit in _near_tunnel_points(p):
			var other: Dictionary = tunnels[hit[0]]
			var q2: Vector3 = (other.points as PackedVector3Array)[hit[1]]
			if p.distance_to(q2) < r + float(other.radius) + 4.0:
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
		var reach := maxf(room.rx, room.rz) + 40.0
		if absf(room.centre.x - p.x) < reach and absf(room.centre.z - p.z) < reach:
			out.append(i)
	return out

func _in_room(room: Dictionary, p: Vector3, margin: float) -> bool:
	var local: Vector3 = (p - (room.centre as Vector3)).rotated(Vector3.UP, -float(room.yaw))
	var q := Vector3(local.x / (float(room.rx) + margin), local.y / (float(room.ry) + margin),
		local.z / (float(room.rz) + margin))
	return q.length() <= 1.0 and p.y >= float(room.floor) - margin

# --- Queries -------------------------------------------------------------------

## True inside a cavern or tunnel (or within `margin` of one).
func contains(p: Vector3, margin: float = 0.5) -> bool:
	for ri in _near_rooms_fast(p):
		if _in_room(rooms[ri], p, margin):
			return true
	for hit in _near_tunnel_points(p):
		var t: Dictionary = tunnels[hit[0]]
		var q: Vector3 = (t.points as PackedVector3Array)[hit[1]]
		if p.distance_to(q) < float(t.radius) * 1.05 + margin + RING_STEP * 0.5:
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
		var reach := maxf(room.rx, room.rz) + 2.0
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
		if p.distance_to(pts[hit[1]]) < float(t.radius) + 2.0:
			return int(t.kind_a) if hit[1] < pts.size() / 2 else int(t.kind_b)
	return -1

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
	mi.visibility_range_end = 260.0
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

## A cavern: a lumpy ellipsoid, floor flattened, with the wall cut away inside
## every tunnel that starts here and inside the entrance tunnel if it has one.
func _room_mesh(ri: int) -> Buf:
	var room: Dictionary = rooms[ri]
	var out := Buf.new()
	var size := maxf(float(room.rx), float(room.rz))
	var level := 2 if size < 10.0 else 3
	var ico := _icosphere(level)
	var basis := Basis(Vector3.UP, float(room.yaw))
	var c: Vector3 = room.centre
	var floor_y: float = room.floor
	var pts: Array = []
	for v: Vector3 in ico[0]:
		var bump := 1.0 + 0.16 * _noise.get_noise_3d(v.x * 2.0 + float(ri), v.y * 2.0, v.z * 2.0)
		var p := c + basis * Vector3(v.x * float(room.rx), v.y * float(room.ry), v.z * float(room.rz)) * bump
		p.y = maxf(p.y, floor_y)
		pts.append(p)
	# The tubes that start here: their first stretch, to cut the wall along.
	var cuts: Array = []
	for ti in room.links:
		var t: Dictionary = tunnels[ti]
		var tp: PackedVector3Array = t.points
		var from_start: bool = int(t.a) == ri
		var s := tp[0] if from_start else tp[tp.size() - 1]
		var s2 := tp[mini(4, tp.size() - 1)] if from_start else tp[maxi(0, tp.size() - 5)]
		cuts.append([s, s2, float(t.radius)])
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
		if _cut_away(mid, cuts, entrance_frame, floor_y):
			continue
		var n := (cc - a).cross(b - a)
		if n.dot(inside - mid) < 0.0:
			n = -n
		_tri(out, a, b, cc, inside, _shade(int(room.kind), n.normalized(), mid))
	return out

func _cut_away(p: Vector3, cuts: Array, entrance_frame: Variant, floor_y: float) -> bool:
	for cut in cuts:
		var s: Vector3 = cut[0]
		var s2: Vector3 = cut[1]
		var r: float = cut[2]
		var axis := s2 - s
		var t := (p - s).dot(axis) / maxf(0.001, axis.length_squared())
		if t < 0.0:
			continue
		var q := s + axis * minf(t, 1.0)
		if p.distance_to(q) < r * 1.02:
			return true
	if entrance_frame != null:
		var local: Vector3 = (entrance_frame as Transform3D) * p
		var z_end := Cave.SHAFT_LENGTH + Cave.TUNNEL_LENGTH
		if absf(local.x) < Cave.SHAFT_WIDTH * 0.5 + 0.9 and local.z < z_end + 1.0 \
				and p.y < floor_y + Cave.TUNNEL_HEIGHT + 0.9:
			return true
	return false

## A tunnel: an eight-sided tube along the curve, floor flattened, radius
## wandering a little ring to ring.
func _tunnel_mesh(ti: int) -> Buf:
	var t: Dictionary = tunnels[ti]
	var pts: PackedVector3Array = t.points
	var r: float = t.radius
	var out := Buf.new()
	# Each end is carried back a little way into its cavern, under the
	# cavern's floor and behind its wall, so the seam where the cavern floor was
	# cut away is always floored.
	var src := pts
	pts = PackedVector3Array()
	pts.append(src[0] - (src[1] - src[0]).normalized() * 1.8)
	pts.append_array(src)
	pts.append(src[src.size() - 1] + (src[src.size() - 1] - src[src.size() - 2]).normalized() * 1.8)
	var rings: Array = []
	for k in pts.size():
		var prev := pts[maxi(0, k - 1)]
		var next := pts[mini(pts.size() - 1, k + 1)]
		var tangent := (next - prev).normalized()
		var side := Vector3.UP.cross(tangent).normalized()
		var up := tangent.cross(side).normalized()
		if up.y < 0.0:
			up = -up
		var rk := r * (1.0 + 0.1 * _noise.get_noise_2d(float(k) * 0.7, float(ti) * 3.1))
		# The rings at the caverns are true to size, so they meet the walls.
		if k <= 1 or k >= pts.size() - 2:
			rk = r
		var ring: Array = []
		for j in SIDES:
			var a := TAU * float(j) / float(SIDES) - PI * 0.5
			var across := cos(a) * rk
			var height := maxf(sin(a) * rk * 1.08, -r * FLOOR_CUT)
			ring.append(pts[k] + side * across + up * height)
		rings.append(ring)
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
	for i in count:
		var p := floor_point(room, rng)
		match kind:
			Kind.CRYSTAL, Kind.ABYSS:
				var color: Color = [Color(0.7, 0.45, 1.0), Color(0.45, 0.9, 1.0), Color(1.0, 0.55, 0.9)][i % 3] \
					if kind == Kind.CRYSTAL else Color(0.3, 0.6, 1.0)
				for k in 3:
					var tilt := Basis(Vector3.FORWARD, rng.randf_range(-0.5, 0.5)) * Basis(Vector3.RIGHT, rng.randf_range(-0.5, 0.5))
					g.prism(6, rng.randf_range(0.2, 0.55), 0.0, rng.randf_range(1.0, 3.2),
						Transform3D(tilt, p + Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))), color, true)
			Kind.ICE:
				var drop := rng.randf_range(1.0, 3.5)
				g.prism(5, rng.randf_range(0.2, 0.5), 0.0, drop, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(p.x, top, p.z)),
					Color(0.8, 0.92, 1.0), i % 4 == 0)
				if i % 3 == 0:
					g.prism(6, rng.randf_range(0.6, 1.2), 0.3, rng.randf_range(1.5, 4.0), Transform3D(Basis(), p), Color(0.7, 0.86, 0.98))
			Kind.DESERT:
				g.box(Vector3(rng.randf_range(2.0, 4.0), rng.randf_range(0.3, 0.8), rng.randf_range(2.0, 4.0)),
					Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p + Vector3(0, 0.1, 0)), (pal[1] as Color).lightened(0.05))
				if i % 4 == 0:
					g.prism(6, rng.randf_range(0.7, 1.1), rng.randf_range(0.6, 1.0), top - floor_y,
						Transform3D(Basis(), p), (pal[0] as Color).lightened(0.06))
			Kind.FUNGAL:
				var stem := rng.randf_range(0.4, 1.4)
				g.prism(6, 0.08, 0.06, stem, Transform3D(Basis(), p), Color(0.85, 0.82, 0.7))
				g.prism(8, rng.randf_range(0.25, 0.6), 0.05, 0.25, Transform3D(Basis(), p + Vector3(0, stem, 0)),
					[Color(0.4, 1.0, 0.6), Color(0.3, 0.9, 1.0), Color(0.9, 0.5, 1.0)][i % 3], true)
			Kind.MAGMA:
				if i % 2 == 0:
					g.prism(6, rng.randf_range(0.5, 0.9), rng.randf_range(0.4, 0.8), rng.randf_range(1.5, 5.0),
						Transform3D(Basis(), p), Color(0.14, 0.12, 0.12))
				else:
					g.box(Vector3(rng.randf_range(1.5, 3.5), 0.1, rng.randf_range(1.5, 3.5)),
						Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p + Vector3(0, 0.03, 0)), Color(1.0, 0.42, 0.1), true)
			_:
				# River caves: stalagmites, and stalactites dripping over them.
				var h := rng.randf_range(0.8, 2.8)
				g.prism(5, rng.randf_range(0.3, 0.7), 0.0, h, Transform3D(Basis(Vector3.UP, rng.randf()), p), (pal[0] as Color).lightened(0.1))
				g.prism(5, rng.randf_range(0.3, 0.6), 0.0, h * 0.8, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(p.x, top, p.z)), (pal[0] as Color).lightened(0.05))
	if not g.is_empty():
		var mi := g.instance("CaveDressing", false)
		mi.visibility_range_end = 200.0
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
	light.omni_range = size * 1.7 + 4.0
	light.omni_attenuation = 0.8
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 90.0
	light.distance_fade_length = 30.0
	add_child(light)

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
		var at := pts[k] + side * s * r * 0.8 - Vector3(0, r * FLOOR_CUT, 0)
		g.prism(5, 0.18, 0.0, 0.9, Transform3D(Basis(tangent, -s * 0.5), at), (PALETTE[kind][2] as Color), true)
		g.prism(5, 0.12, 0.0, 0.6, Transform3D(Basis(tangent, -s * 0.8), at + tangent * 0.4), (PALETTE[kind][2] as Color).lightened(0.2), true)
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
