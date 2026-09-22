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

## How many nodes this field maintains.
@export var quota: int = 60
## Seconds between refill attempts once the field is below quota.
@export var refill_seconds: float = 3.0
## Nodes are kept this far apart, so a forest is not a thicket of overlaps.
@export var min_spacing: float = 3.4
## How many positions to try before giving up on this attempt.
@export var placement_tries: int = 24

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
var _next_index: int = 0

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
	return alive.size()

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
	if at_quota():
		# Armed while full, so the first loss waits out a refill interval like
		# any other. Otherwise a felled tree is replaced the same frame it falls.
		_timer = refill_seconds
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
	var node: Node3D = builder.call(entry, _rng.randi())
	if node == null:
		return null
	node.position = position
	add_child(node)
	alive.append(node)
	total_spawned += 1
	_watch(node)
	populated.emit(self, node)
	return node

func _find_spot() -> Variant:
	for i in placement_tries:
		var candidate: Vector3 = sampler.call(_rng)
		var clear := true
		for other in alive:
			if not is_instance_valid(other):
				continue
			if other.position.distance_to(candidate) < min_spacing:
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
