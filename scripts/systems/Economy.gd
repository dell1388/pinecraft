extends Node

## Autoload. Money, the day clock and the weekly price table.
##
## A day is a full turn of the sun, dawn to dawn. The market moves once a
## week, so there is time to go out, gather and come back to the same prices.
## Prices are deterministic: the multiplier for (week, item) is derived from a
## hash, so a save reloaded on day 12 sees exactly the prices it saw before, and
## no price history needs to be stored.

signal money_changed(amount: int, delta: int)
signal day_changed(day: int)
signal week_changed(week: int)
signal item_sold(item_id: StringName, amount: int)

var money: int = 0
var day: int = 1
var day_time: float = 0.0
var total_earned: int = 0
var items_sold: int = 0

var _day_length: float = 900.0
## Days between price changes.
static var WEEK: int = int(Balance.num("economy.week_days", 7))
var _seed: int = 20260921
var _trend_strength: float = 0.35
var _price_cache: Dictionary = {}
var _cached_day: int = -1

func _ready() -> void:
	_day_length = float(GameData.price_config.get("day_length_seconds", 900.0))
	_seed = int(GameData.price_config.get("seed", 20260921))
	_trend_strength = float(GameData.price_config.get("trend_strength", 0.35))

func _process(delta: float) -> void:
	day_time += delta
	if day_time >= _day_length:
		day_time -= _day_length
		advance_day()

func advance_day() -> void:
	var was := week()
	day += 1
	_price_cache.clear()
	_cached_day = -1
	day_changed.emit(day)
	if week() != was:
		week_changed.emit(week())

## Which market week it is, from 0; day 1 to 7 is the first.
func week() -> int:
	return (day - 1) / WEEK

## Day of the market week, 1 to 7.
func day_of_week() -> int:
	return (day - 1) % WEEK + 1

## Until the market next moves: what is left of today and the rest of the week.
func seconds_left_this_week() -> float:
	return seconds_left_today() + float(WEEK - day_of_week()) * _day_length

## The hour of the day, 0 to 24. A day begins at six in the morning.
func hour() -> float:
	return fposmod(6.0 + day_progress() * 24.0, 24.0)

func day_length() -> float:
	return _day_length

func day_progress() -> float:
	return clampf(day_time / maxf(0.001, _day_length), 0.0, 1.0)

func seconds_left_today() -> float:
	return maxf(0.0, _day_length - day_time)

# --- Money -----------------------------------------------------------------

func add_money(amount: int) -> void:
	if amount == 0:
		return
	money += amount
	if amount > 0:
		total_earned += amount
	money_changed.emit(money, amount)

## Debug setting: everything is affordable and nothing is ever taken off
## you. Earnings still count, so the rest of the game behaves as normal.
func unlimited() -> bool:
	return Settings.flag(&"unlimited_money")

func can_afford(amount: int) -> bool:
	return unlimited() or money >= amount

## Spends `amount` if affordable; returns whether the purchase went through.
func try_spend(amount: int) -> bool:
	if unlimited():
		money_changed.emit(money, 0)
		return true
	if amount > money:
		return false
	money -= amount
	money_changed.emit(money, -amount)
	return true

# --- Prices ----------------------------------------------------------------

## Deterministic pseudo-random value in [-1, 1] for a (day, key) pair.
func _noise(day_index: int, key: String) -> float:
	var h: int = hash("%d:%d:%s" % [_seed, day_index, key])
	# Two mixes so neighbouring keys do not produce visibly similar values.
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h % 20001 - 10000) / 10000.0

func _rebuild_prices() -> void:
	_price_cache.clear()
	var category_trend: Dictionary = {}
	for def: ItemDef in GameData.items.values():
		var cat := def.category
		if not category_trend.has(cat):
			category_trend[cat] = _noise(week(), "cat:" + String(cat)) * _trend_strength
		var mult: float = 1.0 + def.volatility * _noise(week(), String(def.id)) + float(category_trend[cat])
		mult = clampf(mult, 0.35, 2.4)
		_price_cache[def.id] = mult
	_cached_day = day

func price_multiplier(item_id: StringName) -> float:
	if _cached_day != day:
		_rebuild_prices()
	return float(_price_cache.get(item_id, 1.0))

## Price of one piece at today's rate. Variable items (wood, lumber, billets)
## are priced by volume, so milling a trunk into boards is worth exactly what
## the boards are worth - never more or less because of how it was cut.
func price_of(item_id: StringName, dims: Dictionary = {}) -> int:
	var def: ItemDef = GameData.item(item_id)
	if def == null:
		return 0
	var d := dims if not dims.is_empty() else def.default_dims()
	return maxi(1, int(round(def.base_value_of(d) * price_multiplier(item_id))))

## Rate per cubic metre, for the market board.
func rate_of(item_id: StringName) -> float:
	var def: ItemDef = GameData.item(item_id)
	if def == null:
		return 0.0
	if def.fixed_value > 0:
		return float(def.fixed_value) * price_multiplier(item_id)
	return def.value_per_m3 * price_multiplier(item_id)

func sell(item_id: StringName, dims: Dictionary = {}) -> int:
	var value := price_of(item_id, dims)
	add_money(value)
	items_sold += 1
	item_sold.emit(item_id, value)
	return value

## Sorted market board rows: [{id, name, rate, unit, multiplier}]
func market_rows() -> Array:
	var rows: Array = []
	for def: ItemDef in GameData.items.values():
		if not def.sellable:
			continue            # store boxes: nobody buys those back
		rows.append({
			"id": def.id,
			"name": def.display_name,
			"rate": rate_of(def.id),
			"unit": "each" if def.fixed_value > 0 else "m3",
			"typical": price_of(def.id),
			"multiplier": price_multiplier(def.id),
		})
	rows.sort_custom(func(a, b): return a.rate < b.rate)
	return rows

func to_dict() -> Dictionary:
	return {"money": money, "day": day, "day_time": day_time,
		"total_earned": total_earned, "items_sold": items_sold}

func from_dict(d: Dictionary) -> void:
	money = int(d.get("money", 0))
	day = int(d.get("day", 1))
	day_time = float(d.get("day_time", 0.0))
	total_earned = int(d.get("total_earned", 0))
	items_sold = int(d.get("items_sold", 0))
	_cached_day = -1
	money_changed.emit(money, 0)
	day_changed.emit(day)
