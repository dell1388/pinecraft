class_name TradeCounter
extends Node3D

## A trader's shop counter: [E] opens the order sheet (OrderPanel). You pick
## what you want and how many, pay up front, and the shop's helper carries it
## out to the loading bay - into your truck if one is parked in the bay, or
## stacked on the bay floor if not. Built and run by a TradePost.

## Buying costs this much over what the same piece sells for today.
const MARKUP := 1.5
## How many of each the order sheet offers at a time.
const AMOUNTS := [1, 5, 10, 25]

var post: TradePost
## What the shop sells: item ids.
var sells: Array = []
var shop_name: String = ""
var helper_name: String = ""

func interact_prompt() -> String:
	var busy := post.queued() if post != null else 0
	var line := "[E] order from %s - %s loads it at the bay" % [shop_name, helper_name]
	if busy > 0:
		line += "   (%d still to load)" % busy
	return line

func interact(p: Node) -> String:
	if p != null and p.has_signal("order_requested"):
		p.emit_signal("order_requested", self)
	return ""

## One piece of `item_id`, at the shop's price today.
func price_of(item_id: StringName) -> int:
	return maxi(1, int(ceil(float(Economy.price_of(item_id)) * MARKUP)))

## The order sheet's rows: {item, name, price, color}.
func catalogue() -> Array:
	var out: Array = []
	for id in sells:
		var def := GameData.item(id)
		if def == null:
			continue
		out.append({"item": id, "name": GameData.item_name(id), "price": price_of(id), "color": def.color})
	return out

## Pays for `count` of `item_id` and hands the job to the helper. Returns
## what to tell the player.
func order(item_id: StringName, count: int) -> String:
	if post == null or not sells.has(item_id) or count <= 0:
		return "they don't sell that here"
	var cost := price_of(item_id) * count
	if not Economy.try_spend(cost):
		return "not enough money: %d x %s is %s" % [count, GameData.item_name(item_id), UIKit.money(cost)]
	post.enqueue(item_id, count)
	Sfx.play(&"cash", global_position)
	return "ordered %d x %s for %s - %s is bringing it to the loading bay" % [
		count, GameData.item_name(item_id), UIKit.money(cost), helper_name]
