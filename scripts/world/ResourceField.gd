class_name ResourceField
extends Node3D

## Keeps a region stocked with resource nodes up to a quota, and no further.
##
## Nodes are procedural in both form and place: the field draws a species from
## its table, a position from its sampler and a seed from its own generator, so
## no two trees are the same tree and none of it is authored by hand. Once the
## quota is met the field stops spawning entirely; it only starts again when
## something is used up, and then only back to the quota.
##
## Spawning is paced rather than instant, so a field refilling after a clear-cut
## never drops a hundred colliders into one physics step.

signal populated(field: ResourceField, node: Node3D)
signal depleted(field: ResourceField, node: Node3D)
## A node taken away unused to make room elsewhere: see `churn_seconds`.
signal retired(field: ResourceField, node: Node3D)

## How many nodes this field maintains.
@export var quota: int = 60
## Seconds between refill attempts once the field is below quota.
@export var refill_seconds: float = 3.0
## The least there ever is: below this, one is grown back straight away.
@export var min_present: int = 0
## Nodes are kept this far apart, so a forest is not a thicket of overlaps.
@export var min_spacing: float = 3.4
## How many positions to try before giving up on this attempt.
@export var placement_tries: int = 24
## A full field is not a finished one. Left alone, a field fills to quota and
## stops, and once the player has cleared the woods near home every tree left
## is a long walk away - forever. So a full field now and then retires one
## untouched node far from the player, and the refill that follows can land
## anywhere, including near them. Zero turns it off.
@export var churn_seconds: float = 0.0
## Only nodes at least this far from the player are retired, so nothing ever
## vanishes in front of them.
@export var churn_distance: float = 90.0
## New nodes do not appear right next to the player either.
@export var spawn_clearance: float = 30.0

## The player, or whatever the distances above are measured from. Optional.
var focus: Node3D
## More players the distances are measured from (co-op guests on the host).
var extra_focus: Array[Node3D] = []
## Where distances are measured from until there is a focus: the spawn.
var anchor: Vector3 = Vector3.ZERO
## Past this distance a node is kept as a note - what it is, its seed and where
## it stands - rather than as a built node, and built when the player comes
## within it; an untouched node well behind them goes back to being a note. The
## same seed makes the same tree, so nothing visibly changes. Zero builds all.
@export var wake_distance: float = 0.0
## The notes: {entry, seed, position}.
var dormant: Array[Dictionary] = []
var _wake_timer: float = 0.0
## Far off, each note is drawn as a stand-in - one cheap mesh for the whole
## field, placed by a MultiMesh - so a forest reads as a forest out to the
## horizon without a real tree for every one. Null draws nothing.
var impostor: Mesh = null
var _impostors_dirty: bool = false
## The notes are kept in square tiles this many metres across, each with its
## own batch of stand-ins: a tile out of view is not drawn, one past the view
## distance is not drawn, and a tree waking or sleeping redraws its own tile
## only. Waking looks at the tiles round the player, not every note.
const TILE := 200.0
var _tiles: Dictionary = {}             ## Vector2i -> Array of notes
var _tile_draws: Dictionary = {}        ## Vector2i -> MultiMeshInstance3D
## The built, untouched trees' shadows, cast by stand-ins batched per tile:
## one draw per tile in the shadow pass instead of one (or several) per tree.
var _shadow_draws: Dictionary = {}      ## Vector2i -> MultiMeshInstance3D
var _shadowed: Dictionary = {}          ## tree instance id -> tile
## Height the stand-in mesh was made for, so each stand-in is scaled to its tree.
var impostor_height: float = 0.0
var _dirty_tiles: Dictionary = {}       ## Vector2i -> true
## How far off stand-ins are drawn: the view distance.
static var impostor_range: float = 600.0
var _quota_timer: float = 0.0
## Notes near someone, nearest first, waiting their turn to be built. Building
## a tree is a millisecond or so; all the fields together build no more than
## BUILDS_PER_FRAME a frame, so walking or driving into a forest fills it in
## over a few frames rather than stalling one.
var _wake_queue: Array = []
const BUILDS_PER_FRAME := 2
static var _budget_frame: int = -1
static var _budget_left: int = 0

## And no more than this many trees behind you go back to notes a frame.
const SLEEPS_PER_FRAME := 6
static var _sleep_frame: int = -1
static var _sleep_left: int = 0

static func _take_sleep() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _sleep_frame:
		_sleep_frame = frame
		_sleep_left = SLEEPS_PER_FRAME
	if _sleep_left <= 0:
		return false
	_sleep_left -= 1
	return true

static func _take_build() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_budget_left = BUILDS_PER_FRAME
	if _budget_left <= 0:
		return false
	_budget_left -= 1
	return true
var _full: bool = false
## Every standing spot, built or noted, bucketed by `min_spacing` squares, so
## checking a new spot's spacing looks at its neighbours, not the whole field.
var _grid: Dictionary = {}              ## Vector2i -> Array of Vector3

func _tile_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.z / TILE))

## A note goes into the list and its tile, with where its stand-in stands.
func _add_note(note: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(note.seed)
	var sc := rng.randf_range(0.85, 1.15)
	note["xform"] = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), note.position)
	var key := _tile_of(note.position)
	note["tile"] = key
	note["i"] = dormant.size()
	dormant.append(note)
	if not _tiles.has(key):
		_tiles[key] = []
	(_tiles[key] as Array).append(note)
	_dirty_tiles[key] = true
	_impostors_dirty = true

func _remove_note_at(i: int) -> Dictionary:
	# Swapped out with the last, so taking one away never shifts the rest.
	var note: Dictionary = dormant[i]
	var last: Dictionary = dormant[dormant.size() - 1]
	dormant.remove_at(dormant.size() - 1)
	if i < dormant.size():
		dormant[i] = last
		last["i"] = i
	var key: Vector2i = note.get("tile", _tile_of(note.position))
	var list: Array = _tiles.get(key, [])
	for k in list.size():
		if is_same(list[k], note):
			list.remove_at(k)
			break
	_dirty_tiles[key] = true
	_impostors_dirty = true
	return note

func _cell_of(p: Vector3) -> Vector2i:
	var s := maxf(min_spacing, 0.5)
	return Vector2i(floori(p.x / s), floori(p.z / s))

func _grid_add(p: Vector3) -> void:
	var c := _cell_of(p)
	if not _grid.has(c):
		_grid[c] = []
	(_grid[c] as Array).append(p)

func _grid_remove(p: Vector3) -> void:
	var c := _cell_of(p)
	var bucket: Array = _grid.get(c, [])
	for i in bucket.size():
		if (bucket[i] as Vector3).is_equal_approx(p):
			bucket.remove_at(i)
			return

func _spacing_clear(p: Vector3) -> bool:
	var c := _cell_of(p)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for q in _grid.get(c + Vector2i(dx, dz), []):
				if (q as Vector3).distance_to(p) < min_spacing:
					return false
	return true

## Forms to draw from. Each entry is passed to `builder` as-is.
var species: Array[Dictionary] = []
## `builder.call(species_entry, seed) -> Node3D`, which configures but does not
## place the node.
var builder: Callable = Callable()
## `sampler.call(rng) -> Vector3`, a candidate position in this field's region.
var sampler: Callable = Callable()

var alive: Array[Node3D] = []
var total_spawned: int = 0

var _rng := RandomNumberGenerator.new()
var _timer: float = 0.0
var _churn_timer: float = 0.0
var _next_index: int = 0
var total_retired: int = 0

func setup(p_species: Array, p_builder: Callable, p_sampler: Callable, p_seed: int = 0) -> void:
	species.clear()
	for entry in p_species:
		species.append(entry)
	builder = p_builder
	sampler = p_sampler
	_rng.seed = p_seed if p_seed != 0 else hash(name)

func _ready() -> void:
	set_process(true)
	# Fields look round at different moments, not all in one frame.
	_wake_timer = randf() * 0.4

func count() -> int:
	_prune()
	return alive.size() + dormant.size()

func at_quota() -> bool:
	return count() >= quota

## Fills the field to its quota in one go. Used when the world is first built,
## where paced spawning would just mean walking into an empty forest.
func prefill() -> int:
	# A co-op guest grows nothing of its own: the host says what stands where.
	if Net.is_client():
		return 0
	var placed := 0
	# Bounded by more than the quota because spacing rejects some candidates,
	# but bounded, so a region too small for its quota cannot spin forever.
	for i in quota * 8:
		if at_quota():
			break
		if _try_spawn() != null:
			placed += 1
	_refresh_impostors()
	return placed

## Redraws the stand-ins in the tiles that changed.
func _refresh_impostors() -> void:
	_impostors_dirty = false
	if impostor == null:
		_dirty_tiles.clear()
		return
	var shadows_by_tile: Dictionary = {}
	for node in alive:
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node is ChoppableTree \
				and (node as ChoppableTree).is_merged() and (node as ChoppableTree).field_shadows:
			var key := _tile_of(node.position)
			if _dirty_tiles.has(key):
				if not shadows_by_tile.has(key):
					shadows_by_tile[key] = []
				(shadows_by_tile[key] as Array).append(node)
	for key in _dirty_tiles:
		var notes: Array = _tiles.get(key, [])
		var xforms: Array = []
		for note in notes:
			xforms.append(note.xform)
		_draw_tile(_tile_draws, key, xforms, "Impostors", GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			impostor_range)
		var casters: Array = []
		for node in shadows_by_tile.get(key, []):
			var tree := node as ChoppableTree
			var sc := tree.trunk_height / impostor_height if impostor_height > 0.0 else 1.0
			casters.append(Transform3D(Basis().scaled(Vector3(1.0, sc, 1.0)), tree.position))
			_shadowed[tree.get_instance_id()] = key
		_draw_tile(_shadow_draws, key, casters, "Shadows", GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
			ChoppableTree.VIEW_RANGE)
	_dirty_tiles.clear()

func _draw_tile(draws: Dictionary, key: Vector2i, xforms: Array, label: String,
		shadows: GeometryInstance3D.ShadowCastingSetting, reach: float) -> void:
	var draw: MultiMeshInstance3D = draws.get(key)
	if xforms.is_empty():
		if draw != null:
			draw.queue_free()
			draws.erase(key)
		return
	if draw == null:
		draw = MultiMeshInstance3D.new()
		draw.name = "%s_%d_%d" % [label, key.x, key.y]
		draw.cast_shadow = shadows
		if label == "Impostors":
			draw.add_to_group(&"tree_impostors")
			# The foliage shader, with shaders on (see ChoppableTree.set_fancy).
			if ChoppableTree.fancy:
				draw.material_override = ChoppableTree.foliage_material()
		add_child(draw)
		draws[key] = draw
	draw.visibility_range_end = reach
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = impostor
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	draw.multimesh = mm

## A built tree came, went, or was touched: its tile's shadows are redrawn.
func _shadows_changed(node: Node3D) -> void:
	if impostor == null:
		return
	var key: Vector2i = _shadowed.get(node.get_instance_id(), _tile_of(node.position))
	_shadowed.erase(node.get_instance_id())
	_dirty_tiles[key] = true
	_impostors_dirty = true

## Microseconds spent in fields this frame (read by the perf harness).
static var spent_usec: int = 0
static var built_count: int = 0
static var slept_count: int = 0

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_step(delta)
	spent_usec += Time.get_ticks_usec() - t0

func _step(delta: float) -> void:
	if Net.is_client():
		return
	if wake_distance > 0.0:
		_wake_timer -= delta
		if _wake_timer <= 0.0:
			_wake_timer = 0.4
			_wake_and_sleep()
		_build_queued()
	if _impostors_dirty:
		_refresh_impostors()
	# Whether it is full only changes when something is used up or grown,
	# and counting every frame is a waste: every half second will do.
	_quota_timer -= delta
	if _quota_timer <= 0.0:
		_quota_timer = 0.5
		_full = at_quota()
	if _full:
		# Armed while full, so the first loss waits out a refill interval like
		# any other. Otherwise a felled tree is replaced the same frame it falls.
		_timer = refill_seconds
		if churn_seconds > 0.0:
			_churn_timer -= delta
			if _churn_timer <= 0.0:
				_churn_timer = churn_seconds * _rng.randf_range(0.7, 1.3)
				retire_one()
		return
	# Some finds are never allowed to run out: with fewer than this about,
	# one grows back at once rather than after the refill wait.
	if count() < min_present and _try_spawn() != null:
		_quota_timer = 0.0
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = refill_seconds
	_try_spawn()
	_quota_timer = 0.0

func _try_spawn() -> Node3D:
	if species.is_empty() or not builder.is_valid() or not sampler.is_valid():
		return null
	var position: Variant = _find_spot()
	if position == null:
		return null
	# Species are taken in turn rather than at random, so a mixed forest stays
	# mixed instead of drifting to whatever the generator favoured.
	var entry: Dictionary = species[_next_index % species.size()]
	_next_index += 1
	var form_seed := _rng.randi()
	total_spawned += 1
	_grid_add(position)
	if wake_distance > 0.0 and not _near_focus(to_global(position), wake_distance):
		_add_note({"entry": entry, "seed": form_seed, "position": position})
		return self
	return _build(entry, form_seed, position)

func _build(entry: Dictionary, form_seed: int, position: Vector3) -> Node3D:
	built_count += 1
	var node: Node3D = builder.call(entry, form_seed)
	if node == null:
		return null
	if impostor != null and node is ChoppableTree:
		(node as ChoppableTree).field_shadows = true
	node.position = position
	node.set_meta("form_seed", form_seed)
	node.set_meta("entry", entry)
	add_child(node)
	alive.append(node)
	_watch(node)
	if impostor != null and node is ChoppableTree:
		_dirty_tiles[_tile_of(position)] = true
		_impostors_dirty = true
	populated.emit(self, node)
	return node

## Builds the notes that have come within reach, a few at a time, and turns
## untouched nodes well out of reach back into notes.
var _last_look: Array[Vector3] = []
var _look_age: float = 0.0

func _wake_and_sleep() -> void:
	var focus_points := _focus_points()
	# Nobody has moved since the last look: nothing new has come in reach.
	_look_age += 0.4
	var moved := focus_points.size() != _last_look.size() or _look_age > 3.0
	if not moved:
		for k in focus_points.size():
			if focus_points[k].distance_squared_to(_last_look[k]) > 64.0:
				moved = true
				break
	if moved:
		_last_look = focus_points.duplicate()
		_look_age = 0.0
		_queue_wakes(focus_points)
	_sleep_far()

func _queue_wakes(focus_points: Array[Vector3]) -> void:
	# Only the tiles that reach into someone's circle can hold a note to wake.
	var reach := int(ceil(wake_distance / TILE))
	var seen: Dictionary = {}
	var locals: Array[Vector2] = []
	for f in focus_points:
		var lf := to_local(f)
		locals.append(Vector2(lf.x, lf.z))
		var centre := _tile_of(lf)
		for dx in range(-reach, reach + 1):
			for dz in range(-reach, reach + 1):
				var key := centre + Vector2i(dx, dz)
				# The tile's nearest point to the player is within reach.
				var lo := Vector2(key) * TILE
				var nearest := Vector2(clampf(lf.x, lo.x, lo.x + TILE), clampf(lf.z, lo.y, lo.y + TILE))
				if nearest.distance_to(Vector2(lf.x, lf.z)) <= wake_distance:
					seen[key] = true
	var r2 := wake_distance * wake_distance
	var queued: Array = []
	for key in seen:
		for d in _tiles.get(key, []):
			var p: Vector3 = d.position
			var best := INF
			for l in locals:
				best = minf(best, Vector2(p.x - l.x, p.z - l.y).length_squared())
			if best < r2:
				queued.append([best, d])
	# Nearest first: what is right in front of you is built before the rest.
	queued.sort_custom(func(a, b): return a[0] < b[0])
	_wake_queue.clear()
	for q in queued:
		_wake_queue.append(q[1])

func _sleep_far() -> void:
	for i in range(alive.size() - 1, -1, -1):
		var node := alive[i]
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		# Cut into since last look: it casts its own shadow now.
		if node is ChoppableTree and _shadowed.has(node.get_instance_id()) and not (node as ChoppableTree).is_merged():
			_shadows_changed(node)
		if node.has_method("untouched") and not node.call("untouched"):
			continue
		if not node.has_meta("form_seed") or _near_focus(node.global_position, wake_distance * 1.35):
			continue
		if not _take_sleep():
			break
		alive.remove_at(i)
		slept_count += 1
		_shadows_changed(node)
		_add_note({"entry": node.get_meta("entry"), "seed": int(node.get_meta("form_seed")),
			"position": node.position})
		node.queue_free()

func _focus_distance(p: Vector3, points: Array[Vector3]) -> float:
	var g := to_global(p)
	var best := INF
	for f in points:
		best = minf(best, Vector2(g.x - f.x, g.z - f.z).length_squared())
	return best

## Builds from the queue while the frame's budget lasts.
func _build_queued() -> void:
	while not _wake_queue.is_empty():
		var d: Dictionary = _wake_queue[0]
		var i := int(d.get("i", -1))
		# Gone meanwhile (retired, or built already).
		if i < 0 or i >= dormant.size() or not is_same(dormant[i], d):
			_wake_queue.pop_front()
			continue
		# Not up through a vehicle parked on the spot: it waits until the
		# vehicle has gone.
		if vehicle_near(to_global(d.position)):
			_wake_queue.pop_front()
			continue
		if not _take_build():
			return
		_wake_queue.pop_front()
		_remove_note_at(i)
		_build(d.entry, int(d.seed), d.position)

## Where the players are (or the spawn, before there is one).
func _focus_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for other in extra_focus:
		if is_instance_valid(other):
			out.append(other.global_position)
	if focus != null and is_instance_valid(focus):
		out.append(focus.global_position)
	else:
		out.append(anchor)
	return out

## Takes away one untouched node out of the player's reach, if there is one.
## Returns what it took, or null.
func retire_one() -> Node3D:
	# A note far away is the cheapest thing to retire, and nobody can see it go.
	if not dormant.is_empty():
		var gone: int = _rng.randi() % dormant.size()
		_grid_remove(dormant[gone].position)
		_remove_note_at(gone)
		total_retired += 1
		return self
	var candidates: Array[Node3D] = []
	for node in alive:
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node.has_method("untouched") and not node.call("untouched"):
			continue
		if _near_focus(node.global_position, churn_distance):
			continue
		candidates.append(node)
	if candidates.is_empty():
		return null
	var node := candidates[_rng.randi() % candidates.size()]
	alive.erase(node)
	_shadows_changed(node)
	_grid_remove(node.position)
	total_retired += 1
	retired.emit(self, node)
	node.queue_free()
	return node

## Nothing grows up through a vehicle: no tree or rock appears within this
## many metres (across the ground) of one.
static var VEHICLE_CLEARANCE: float = Balance.num("world.vehicle_clearance", 7.0)

func vehicle_near(point: Vector3) -> bool:
	if not is_inside_tree():
		return false
	for v in get_tree().get_nodes_in_group(&"vehicles"):
		var n := v as Node3D
		if n != null and Vector2(point.x - n.global_position.x, point.z - n.global_position.z).length() < VEHICLE_CLEARANCE:
			return true
	return false

func _near_focus(point: Vector3, distance: float) -> bool:
	# Co-op: every player counts, so a field wakes round a guest out on their
	# own as well as round the host.
	for other in extra_focus:
		if is_instance_valid(other) and Vector2(point.x - other.global_position.x, point.z - other.global_position.z).length() < distance:
			return true
	var f := anchor
	if focus != null and is_instance_valid(focus):
		f = focus.global_position
	elif wake_distance <= 0.0:
		return false
	return Vector2(point.x - f.x, point.z - f.z).length() < distance

func _find_spot() -> Variant:
	for i in placement_tries:
		var candidate: Vector3 = sampler.call(_rng)
		if spawn_clearance > 0.0 and _near_focus(to_global(candidate), spawn_clearance):
			continue
		if vehicle_near(to_global(candidate)):
			continue
		if _spacing_clear(candidate):
			return candidate
	return null

## Resource nodes announce their own end; the field frees them and the quota
## opens up again.
func _watch(node: Node3D) -> void:
	if node.has_signal("felled"):
		node.connect("felled", _on_consumed)
	elif node.has_signal("broken"):
		node.connect("broken", _on_consumed)

func _on_consumed(node: Node3D) -> void:
	alive.erase(node)
	_shadows_changed(node)
	_grid_remove(node.position)
	depleted.emit(self, node)
	# One frame of grace: the node is mid-signal, and whatever it dropped is
	# still being spawned out of it.
	node.call_deferred("queue_free")

func _prune() -> void:
	for i in range(alive.size() - 1, -1, -1):
		if not is_instance_valid(alive[i]):
			alive.remove_at(i)

# --- Region samplers -------------------------------------------------------

## A ring around the origin: the forest, kept clear of the plot in the middle.
static func annulus(inner: float, outer: float) -> Callable:
	return func(rng: RandomNumberGenerator) -> Vector3:
		var angle := rng.randf_range(0.0, TAU)
		# Square-rooted so points spread evenly over the ring's area rather
		# than bunching against its inner edge.
		var t := sqrt(rng.randf())
		var radius := lerpf(inner * inner, outer * outer, t * t)
		radius = sqrt(maxf(inner * inner, radius))
		return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

## An axis-aligned patch: the quarry.
static func rect(centre: Vector3, extents: Vector2) -> Callable:
	return func(rng: RandomNumberGenerator) -> Vector3:
		return centre + Vector3(
			rng.randf_range(-extents.x, extents.x), 0.0,
			rng.randf_range(-extents.y, extents.y))
