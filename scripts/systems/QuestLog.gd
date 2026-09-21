class_name QuestLog
extends Node

## Standing orders for materials.
##
## Each order wants a volume of one item or one category. Delivering material to
## the sell yard fills whatever orders it matches, on top of the ordinary sale
## price, and a filled order is replaced from the pool so there is always
## something worth going and cutting.

signal changed(log: QuestLog)
signal completed(quest: Dictionary, reward: int)

## Live orders: {id, title, item, category, volume, delivered, reward}
var active: Array[Dictionary] = []

var _pool: Array[Dictionary] = []
var _slots: int = 3
var _next: int = 0

func _ready() -> void:
	refill()

func setup(pool: Array, slots: int) -> void:
	_pool.clear()
	for entry in pool:
		_pool.append(entry)
	_slots = maxi(1, slots)

## Tops the log back up to its slot count, skipping orders already running.
func refill() -> void:
	if _pool.is_empty():
		_pool = GameData.quest_pool()
		_slots = GameData.quest_slots()
	var guard := 0
	while active.size() < _slots and guard < _pool.size() * 2:
		guard += 1
		var entry: Dictionary = _pool[_next % _pool.size()]
		_next += 1
		if _running(StringName(entry.get("id", ""))):
			continue
		active.append({
			"id": StringName(entry.get("id", "")),
			"title": String(entry.get("title", "Order")),
			"item": StringName(entry.get("item", "")),
			"category": StringName(entry.get("category", "")),
			"volume": float(entry.get("volume", 1.0)),
			"delivered": 0.0,
			"reward": int(entry.get("reward", 0)),
		})
	changed.emit(self)

func _running(id: StringName) -> bool:
	for q in active:
		if q.id == id:
			return true
	return false

func _matches(quest: Dictionary, item_id: StringName, category: StringName) -> bool:
	if quest.item != &"":
		return quest.item == item_id
	return quest.category != &"" and quest.category == category

## Credits a delivery against every order it fits. Returns the reward paid.
func deliver(item_id: StringName, category: StringName, volume: float) -> int:
	var paid := 0
	var filled: Array[Dictionary] = []
	for quest in active:
		if not _matches(quest, item_id, category):
			continue
		quest.delivered = float(quest.delivered) + volume
		if float(quest.delivered) + 0.0001 >= float(quest.volume):
			filled.append(quest)
	for quest in filled:
		active.erase(quest)
		var reward := int(quest.reward)
		paid += reward
		Economy.add_money(reward)
		completed.emit(quest, reward)
	if not filled.is_empty():
		refill()
	elif not active.is_empty():
		changed.emit(self)
	return paid

func lines() -> Array[String]:
	var out: Array[String] = []
	for quest in active:
		var want: String = GameData.item_name(quest.item) if quest.item != &"" \
			else String(quest.category)
		out.append("%s: %.2f / %.2f m3 %s  ->  $%d" % [
			quest.title, float(quest.delivered), float(quest.volume), want, int(quest.reward)])
	return out

func to_dict() -> Dictionary:
	var out: Array = []
	for quest in active:
		out.append({"id": String(quest.id), "delivered": float(quest.delivered)})
	return {"active": out, "next": _next}

func from_dict(d: Dictionary) -> void:
	active.clear()
	_next = int(d.get("next", 0))
	var by_id: Dictionary = {}
	for entry in GameData.quest_pool():
		by_id[StringName(entry.get("id", ""))] = entry
	for saved in d.get("active", []):
		var entry: Dictionary = by_id.get(StringName(saved.get("id", "")), {})
		if entry.is_empty():
			continue
		active.append({
			"id": StringName(entry.get("id", "")),
			"title": String(entry.get("title", "Order")),
			"item": StringName(entry.get("item", "")),
			"category": StringName(entry.get("category", "")),
			"volume": float(entry.get("volume", 1.0)),
			"delivered": float(saved.get("delivered", 0.0)),
			"reward": int(entry.get("reward", 0)),
		})
	refill()
