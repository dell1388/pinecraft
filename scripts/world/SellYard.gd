class_name SellYard
extends Node3D

## The buyer's yard: a fenced pad with a shopkeep standing at one end.
##
## Nothing sells by touching the ground here. The player drops material inside
## the fence, walks up to the shopkeep and asks - and everything of theirs
## standing in the yard is bought at once, at the day's rate, with any standing
## orders it fills paid on top.

signal sold(total: int, count: int)

@export var extents: Vector3 = Vector3(18.0, 4.0, 18.0)

var manager: LooseItemManager
var quests: QuestLog
var session_total: int = 0
var last_receipt: String = "nothing sold yet"

var _keep: Node3D

func setup(p_manager: LooseItemManager, p_quests: QuestLog = null) -> void:
	manager = p_manager
	quests = p_quests

func _ready() -> void:
	_build()

## Where the player has to stand to be heard.
func shopkeep_position() -> Vector3:
	return _keep.global_position

func contains(point: Vector3) -> bool:
	var local := to_local(point)
	return absf(local.x) <= extents.x * 0.5 and absf(local.z) <= extents.z * 0.5 \
		and local.y >= -1.0 and local.y <= extents.y

## Everything of the player's currently standing in the yard.
func stock() -> Array[LooseItem]:
	var out: Array[LooseItem] = []
	if manager == null:
		return out
	for item in manager.owned_items():
		if item.state != LooseItem.State.FREE:
			continue
		var def := GameData.item(item.item_id)
		if def != null and not def.sellable:
			continue
		if contains(item.global_position):
			out.append(item)
	return out

func stock_value() -> int:
	var total := 0
	for item in stock():
		total += Economy.price_of(item.item_id, item.dims)
	return total

## Spec: speaking to the shopkeep makes every owned material in the yard
## disappear and pays the equivalent in cash. `carried` is whatever the player
## is holding as they ask, which goes over the counter without being put down.
func sell_all(carried: Array[LooseItem] = []) -> Dictionary:
	var items := stock()
	for item in carried:
		if not is_instance_valid(item) or items.has(item):
			continue
		var def := GameData.item(item.item_id)
		if def != null and not def.sellable:
			continue
		items.append(item)
	if items.is_empty():
		last_receipt = "nothing of yours in the yard"
		return {"count": 0, "total": 0, "bonus": 0}
	var total := 0
	var bonus := 0
	for item in items:
		total += Economy.sell(item.item_id, item.dims)
		if quests != null:
			bonus += quests.deliver(item.item_id, item.category, item.volume())
		manager.despawn(item)
	session_total += total + bonus
	last_receipt = "sold %d piece(s) for $%d" % [items.size(), total]
	if bonus > 0:
		last_receipt += "  (+$%d in filled orders)" % bonus
	sold.emit(total + bonus, items.size())
	return {"count": items.size(), "total": total, "bonus": bonus}

# --- Geometry --------------------------------------------------------------

func _build() -> void:
	var pad := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(extents.x, 0.12, extents.z)
	pad.mesh = bm
	pad.position = Vector3(0, 0.06, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.40, 0.36)
	mat.roughness = 1.0
	pad.material_override = mat
	add_child(pad)

	# A low fence, so the yard's edge is somewhere you can see rather than a
	# number in a tooltip. Posts only: the player and the truck drive straight in.
	var half_x := extents.x * 0.5
	var half_z := extents.z * 0.5
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.52, 0.42, 0.28)
	var step := 3.0
	var x := -half_x
	while x <= half_x + 0.01:
		for z in [-half_z, half_z]:
			_post(Vector3(x, 0, z), post_mat)
		x += step
	var z2 := -half_z + step
	while z2 <= half_z - step + 0.01:
		for sx in [-half_x, half_x]:
			_post(Vector3(sx, 0, z2), post_mat)
		z2 += step

	_keep = Node3D.new()
	_keep.position = Vector3(0, 0, -half_z + 1.4)
	add_child(_keep)
	_figure(_keep)

	# A hut behind the shopkeep, so the yard reads as somewhere staffed.
	_slab(Vector3(4.0, 2.6, 3.0), Vector3(0, 1.3, -half_z - 1.2), Color(0.46, 0.34, 0.24))
	_slab(Vector3(4.6, 0.25, 3.6), Vector3(0, 2.7, -half_z - 1.2), Color(0.34, 0.24, 0.17))

func _post(pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, 1.1, 0.18)
	mi.mesh = bm
	mi.position = pos + Vector3(0, 0.55, 0)
	mi.material_override = mat
	add_child(mi)

func _slab(size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mi.material_override = mat
	add_child(mi)

## The shopkeep: a body the player can walk up to and aim at.
func _figure(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.MACHINE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	body.add_child(cs)
	parent.add_child(body)

	var torso := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.62, 0.95, 0.38)
	torso.mesh = tb
	torso.position = Vector3(0, 1.05, 0)
	var coat := StandardMaterial3D.new()
	coat.albedo_color = Color(0.22, 0.34, 0.48)
	torso.material_override = coat
	body.add_child(torso)

	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.19
	hs.height = 0.38
	head.mesh = hs
	head.position = Vector3(0, 1.72, 0)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.78, 0.62, 0.48)
	head.material_override = skin
	body.add_child(head)

	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.22, 0.6, 0.24)
		leg.mesh = lb
		leg.position = Vector3(side * 0.16, 0.3, 0)
		var trousers := StandardMaterial3D.new()
		trousers.albedo_color = Color(0.24, 0.22, 0.20)
		leg.material_override = trousers
		body.add_child(leg)

func status_line() -> String:
	var items := stock()
	if items.is_empty():
		return "Shopkeep: bring material into the yard and I will buy it"
	return "Shopkeep: [E] sell %d piece(s) in the yard for about $%d" % [
		items.size(), stock_value()]
