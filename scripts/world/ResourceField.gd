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

func count() -> int:
	_prune()
	return alive.size() + dormant.size()

func at_quota() -> bool:
	return count() >= quota

## Fills the field to its quota in one go. Used when the world is first built,
## where paced spawning would just mean walking into an empty forest.
func prefill() -> int:
	var placed := 0
	# Bounded by more than the quota because spacing rejects some candidates,
	# but bounded, so a region too small for its quota cannot spin forever.
	for i in quota * 8:
		if at_quota():
			break
		if _try_spawn() != null:
			placed += 1
	return placed

func _process(delta: float) -> void:
	if wake_distance > 0.0:
		_wake_timer -= delta
		if _wake_timer <= 0.0:
			_wake_timer = 0.4
			_wake_and_sleep()
	if at_quota():
		# Armed while full, so the first loss waits out a refill interval like
		# any other. Otherwise a felled tree is replaced the same frame it falls.
		_timer = refill_seconds
		if churn_seconds > 0.0:
			_churn_timer -= delta
			if _churn_timer <= 0.0:
				_churn_timer = churn_seconds * _rng.randf_range(0.7, 1.3)
				retire_one()
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = refill_seconds
	_try_spawn()

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
	if wake_distance > 0.0 and not _near_focus(to_global(position), wake_distance):
		dormant.append({"entry": entry, "seed": form_seed, "position": position})
		return self
	return _build(entry, form_seed, position)

func _build(entry: Dictionary, form_seed: int, position: Vector3) -> Node3D:
	var node: Node3D = builder.call(entry, form_seed)
	if node == null:
		return null
	node.position = position
	node.set_meta("form_seed", form_seed)
	node.set_meta("entry", entry)
	add_child(node)
	alive.append(node)
	_watch(node)
	populated.emit(self, node)
	return node

## Builds the notes that have come within reach, a few at a time, and turns
## untouched nodes well out of reach back into notes.
func _wake_and_sleep() -> void:
	var woken := 0
	for i in range(dormant.size() - 1, -1, -1):
		if woken >= 8:
			break
		var d: Dictionary = dormant[i]
		if _near_focus(to_global(d.position), wake_distance):
			dormant.remove_at(i)
			_build(d.entry, int(d.seed), d.position)
			woken += 1
	for i in range(alive.size() - 1, -1, -1):
		var node := alive[i]
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node.has_method("untouched") and not node.call("untouched"):
			continue
		if not node.has_meta("form_seed") or _near_focus(node.global_position, wake_distance * 1.35):
			continue
		alive.remove_at(i)
		dormant.append({"entry": node.get_meta("entry"), "seed": int(node.get_meta("form_seed")),
			"position": node.position})
		node.queue_free()

## Takes away one untouched node out of the player's reach, if there is one.
## Returns what it took, or null.
func retire_one() -> Node3D:
	# A note far away is the cheapest thing to retire, and nobody can see it go.
	if not dormant.is_empty():
		dormant.remove_at(_rng.randi() % dormant.size())
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
	total_retired += 1
	retired.emit(self, node)
	node.queue_free()
	return node

func _near_focus(point: Vector3, distance: float) -> bool:
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
		var clear := true
		for other in alive:
			if not is_instance_valid(other):
				continue
			if other.position.distance_to(candidate) < min_spacing:
				clear = false
				break
		if clear:
			for note in dormant:
				if (note.position as Vector3).distance_to(candidate) < min_spacing:
					clear = false
					break
		if clear:
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
