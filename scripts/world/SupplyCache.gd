class_name SupplyCache
extends StaticBody3D

## A strongbox left out on the map. Open it once a market day for a bit of
## cash - more the further it is from home - which is a reason to go and look
## at the far corners, and a reason to go back.

## Who remembers which caches were opened: PlayerState, by this name.
var cache_name: String = "Cache"
var base_reward: int = 100

var _lid: MeshInstance3D
var _rng := RandomNumberGenerator.new()

func setup(p_name: String, reward: int) -> void:
	cache_name = p_name
	base_reward = reward

func _ready() -> void:
	collision_layer = Layers.MACHINE
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.1, 0.8, 0.8)
	cs.shape = box
	cs.position = Vector3(0, 0.4, 0)
	add_child(cs)
	var g := Greeble.new()
	var wood := Color(0.45, 0.30, 0.16)
	var iron := Color(0.28, 0.28, 0.30)
	g.block(Vector3(1.1, 0.55, 0.8), Vector3(0, 0.275, 0), wood)
	for x in [-0.45, 0.0, 0.45]:
		g.block(Vector3(0.08, 0.57, 0.82), Vector3(x, 0.275, 0), iron)
	g.block(Vector3(0.18, 0.2, 0.06), Vector3(0, 0.45, 0.42), Color(0.85, 0.68, 0.22))
	add_child(g.instance("CacheBody"))
	var lid := Greeble.new()
	lid.block(Vector3(1.14, 0.22, 0.84), Vector3(0, 0.11, 0.42), wood.lightened(0.06))
	for x in [-0.45, 0.0, 0.45]:
		lid.block(Vector3(0.08, 0.24, 0.86), Vector3(x, 0.11, 0.42), iron)
	_lid = lid.instance("Lid")
	_lid.position = Vector3(0, 0.55, -0.42)
	add_child(_lid)
	_refresh()

func ready_to_open() -> bool:
	return int(PlayerState.caches.get(cache_name, 0)) < Economy.day

func reward() -> int:
	_rng.seed = hash("%s:%d" % [cache_name, Economy.day])
	return int(round(float(base_reward) * _rng.randf_range(0.8, 1.25)))

func interact_prompt() -> String:
	if ready_to_open():
		return "Supply cache: [E] open it"
	return "Supply cache: empty - it is restocked each market day"

func interact(_player: Node) -> String:
	if not ready_to_open():
		return "the cache is empty until tomorrow"
	var cash := reward()
	PlayerState.caches[cache_name] = Economy.day
	Economy.add_money(cash)
	_refresh()
	return "found $%d in the %s cache" % [cash, cache_name]

func _refresh() -> void:
	if _lid != null:
		_lid.rotation.x = 0.0 if ready_to_open() else -1.1
