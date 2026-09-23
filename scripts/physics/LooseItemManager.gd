class_name LooseItemManager
extends Node3D

## Owns every loose physics object in the world.
##
## Responsibilities (all of them centralised on purpose):
##  * pooling            - nodes are recycled, never freed during play
##  * per-plot cap       - oldest item recycled once a plot is over budget
##  * velocity clamping  - one tight loop instead of 500 _integrate_forces
##  * CCD toggling       - only fast movers pay for continuous collision
##  * kill plane         - anything below KILL_PLANE_Y returns to its plot


@export var per_plot_cap: int = Tuning.LOOSE_ITEMS_PER_PLOT
@export var kill_plane_y: float = Tuning.KILL_PLANE_Y

var _pool: Array[LooseItem] = []
var _active: Array[LooseItem] = []          # all live items, any plot
var _by_plot: Dictionary = {}               # int -> Array[LooseItem]
var _plot_spawns: Dictionary = {}           # int -> Vector3
var _spawn_counter: int = 0
var _ccd_accum: float = 0.0
var _plot_quiet: Dictionary = {}   # plot_id -> seconds the whole plot has been still

# Cheap counters the HUD/benchmark read.
var stat_recycled: int = 0
var stat_killplane: int = 0
var stat_resurfaced: int = 0
## Ground height under a point, or -INF where there is no answer (underground
## in a cave, off the map). Set by the world; unset, nothing is resurfaced.
##
## The land is a surface with no thickness, so a log that lands hard enough on
## a steep face can punch through it and fall forever. The kill plane would
## catch it eventually and send it home to the plot, which is no help to
## someone who just felled a tree a long walk away. Anything found well below
## the ground is put back on top of it where it went through.
var ground_height: Callable = Callable()
var _ground_timer: float = 0.0
const RESURFACE_DEPTH := 1.5
var stat_ccd_on: int = 0
var stat_forced_sleeps: int = 0

func _ready() -> void:
	set_physics_process(true)

func register_plot(plot_id: int, spawn_point: Vector3) -> void:
	_plot_spawns[plot_id] = spawn_point
	if not _by_plot.has(plot_id):
		_by_plot[plot_id] = [] as Array[LooseItem]

func active_count() -> int:
	return _active.size()

func pooled_count() -> int:
	return _pool.size()

func plot_count(plot_id: int) -> int:
	var arr: Array = _by_plot.get(plot_id, [])
	return arr.size()

## Every item currently simulated and unowned. Used by pickup and by tools that
## need to scan the loose world; the array is rebuilt per call, so callers
## should not do this every frame for large plots.
func free_items() -> Array[LooseItem]:
	var out: Array[LooseItem] = []
	for item in _active:
		if item.state == LooseItem.State.FREE:
			out.append(item)
	return out

## Every loose piece the player owns, optionally only those within `radius` of
## a point. Used by the save file and by the sell yard.
func owned_items(centre: Vector3 = Vector3.ZERO, radius: float = -1.0) -> Array[LooseItem]:
	var out: Array[LooseItem] = []
	for item in _active:
		if not item.owned or item.state == LooseItem.State.POOLED:
			continue
		if radius >= 0.0 and item.global_position.distance_to(centre) > radius:
			continue
		out.append(item)
	return out

func awake_count() -> int:
	var n := 0
	for item in _active:
		if item.state == LooseItem.State.FREE and not item.sleeping:
			n += 1
	return n

# --- Spawning --------------------------------------------------------------

## `dims` overrides the item's default size (a felled trunk, a long board).
func spawn(item_id: StringName, xform: Transform3D, plot_id: int = 0,
		impulse: Vector3 = Vector3.ZERO, dims: Dictionary = {},
		owned: bool = false) -> LooseItem:
	var def: ItemDef = GameData.item(item_id)
	if def == null:
		push_error("LooseItemManager: unknown item '%s'" % item_id)
		return null

	var plot_items: Array = _by_plot.get(plot_id, null)
	if plot_items == null:
		plot_items = [] as Array[LooseItem]
		_by_plot[plot_id] = plot_items

	# Enforce the per-plot ceiling before adding, recycling oldest-first.
	while plot_items.size() >= per_plot_cap:
		var victim: LooseItem = _oldest(plot_items)
		if victim == null:
			break
		despawn(victim)
		stat_recycled += 1

	var item: LooseItem = _acquire()
	item.configure(def, dims)
	item.owned = owned
	item.plot_id = plot_id
	item.spawn_index = _spawn_counter
	_spawn_counter += 1
	if item.get_parent() == null:
		add_child(item)
	item.teleport(xform)
	item.set_state(LooseItem.State.FREE)
	if impulse != Vector3.ZERO:
		item.apply_central_impulse(impulse)
	_active.append(item)
	plot_items.append(item)
	return item

func despawn(item: LooseItem) -> void:
	if item == null or item.state == LooseItem.State.POOLED:
		return
	_active.erase(item)
	var plot_items: Array = _by_plot.get(item.plot_id, null)
	if plot_items != null:
		plot_items.erase(item)
	item.set_state(LooseItem.State.POOLED)
	item.reset_motion()
	# Detaching removes the body from the physics space entirely: a pooled
	# item costs nothing in broadphase.
	if item.get_parent() != null:
		remove_child(item)
	_pool.append(item)

## Cuts a piece in two across its long axis, conserving volume exactly. The
## halves keep the original's orientation and are nudged apart so the solver
## does not have to resolve them out of each other.
func split_item(item: LooseItem, t: float = 0.5) -> Array[LooseItem]:
	var out: Array[LooseItem] = []
	if item == null or item.state == LooseItem.State.POOLED:
		return out
	var halves := Solid.split(item.dims, t)
	var xform := item.global_transform
	var axis := xform.basis.y.normalized()
	var length := Solid.length_of(item.dims)
	var plot := item.plot_id
	var id := item.item_id
	var owned := item.owned
	var velocity := item.linear_velocity
	despawn(item)
	var offsets := [
		-axis * (length * 0.5 - Solid.length_of(halves[0]) * 0.5),
		axis * (length * 0.5 - Solid.length_of(halves[1]) * 0.5),
	]
	for i in 2:
		var piece := spawn(id, Transform3D(xform.basis, xform.origin + offsets[i]), plot,
			Vector3.ZERO, halves[i], owned)
		if piece == null:
			continue
		piece.linear_velocity = velocity + (offsets[i].normalized() * 0.6)
		out.append(piece)
	return out

func despawn_all() -> void:
	for item in _active.duplicate():
		despawn(item)

func _acquire() -> LooseItem:
	if _pool.is_empty():
		return LooseItem.new()
	return _pool.pop_back()

func _oldest(items: Array) -> LooseItem:
	var best: LooseItem = null
	for i in items:
		var it: LooseItem = i
		# Never recycle something the player is holding or a machine owns.
		if it.state != LooseItem.State.FREE or it.carrier != null:
			continue
		if best == null or it.spawn_index < best.spawn_index:
			best = it
	if best == null and not items.is_empty():
		best = items[0]
	return best

# --- Per-frame maintenance -------------------------------------------------

func _physics_process(delta: float) -> void:
	_ground_timer -= delta
	if _ground_timer <= 0.0 and ground_height.is_valid():
		_ground_timer = 0.2
		_resurface()
	var review_ccd := false
	_ccd_accum += delta
	if _ccd_accum >= 1.0 / Tuning.CCD_REVIEW_HZ:
		_ccd_accum = 0.0
		review_ccd = true
		stat_ccd_on = 0

	var max_lin_sq := Tuning.MAX_LINEAR_SPEED * Tuning.MAX_LINEAR_SPEED
	var max_ang_sq := Tuning.MAX_ANGULAR_SPEED * Tuning.MAX_ANGULAR_SPEED
	var ccd_on_sq := Tuning.CCD_ENABLE_SPEED * Tuning.CCD_ENABLE_SPEED
	var ccd_off_sq := Tuning.CCD_DISABLE_SPEED * Tuning.CCD_DISABLE_SPEED
	var quiet_lin_sq := Tuning.QUIET_LINEAR_THRESHOLD * Tuning.QUIET_LINEAR_THRESHOLD
	var quiet_ang_sq := Tuning.QUIET_ANGULAR_THRESHOLD * Tuning.QUIET_ANGULAR_THRESHOLD

	# Per-plot peak motion, used for the bulk-sleep decision below.
	var plot_peak: Dictionary = {}

	for i in range(_active.size() - 1, -1, -1):
		var item: LooseItem = _active[i]
		if item.state == LooseItem.State.CAPTURED or item.state == LooseItem.State.HELD:
			continue
		# Sleeping bodies cannot move, so every check below is skipped for them.
		# This is what keeps a settled 500-log pile essentially free.
		if item.sleeping:
			continue

		var lv: Vector3 = item.linear_velocity
		var speed_sq := lv.length_squared()
		if speed_sq > max_lin_sq:
			item.linear_velocity = lv.normalized() * Tuning.MAX_LINEAR_SPEED
			speed_sq = max_lin_sq
		var av: Vector3 = item.angular_velocity
		var spin_sq := av.length_squared()
		if spin_sq > max_ang_sq:
			item.angular_velocity = av.normalized() * Tuning.MAX_ANGULAR_SPEED
			spin_sq = max_ang_sq

		# A truck looks after the CCD of whatever is in its bed.
		if review_ccd and item.carrier == null:
			if item.ccd_active:
				if speed_sq < ccd_off_sq:
					item.continuous_cd = false
					item.ccd_active = false
				else:
					stat_ccd_on += 1
			elif speed_sq > ccd_on_sq:
				item.continuous_cd = true
				item.ccd_active = true
				stat_ccd_on += 1

		if item.state == LooseItem.State.FREE:
			var motion: float = maxf(speed_sq / quiet_lin_sq, spin_sq / quiet_ang_sq)
			var peak: float = plot_peak.get(item.plot_id, 0.0)
			if motion > peak:
				plot_peak[item.plot_id] = motion

		if item.global_position.y < kill_plane_y:
			_rescue(item)

	_update_bulk_sleep(delta, plot_peak)

## Jolt sleeps whole islands, so a single twitching log keeps a 500-log pile
## awake for ~20 s after it has visually settled. Putting bodies to sleep one at
## a time does not stick (contacting neighbours re-activate them), so once an
## entire plot has been quiet for QUIET_TIME_TO_SLEEP the whole plot is slept in
## a single pass, leaving no active body to wake the island.
func _update_bulk_sleep(delta: float, plot_peak: Dictionary) -> void:
	for plot_id in _by_plot:
		var peak: float = plot_peak.get(plot_id, 0.0)
		if peak > 1.0:
			_plot_quiet[plot_id] = 0.0
			continue
		if peak <= 0.0:
			continue          # nothing awake in this plot
		var quiet: float = float(_plot_quiet.get(plot_id, 0.0)) + delta
		if quiet < Tuning.QUIET_TIME_TO_SLEEP:
			_plot_quiet[plot_id] = quiet
			continue
		_plot_quiet[plot_id] = 0.0
		for i in _by_plot[plot_id]:
			var item: LooseItem = i
			if item.state != LooseItem.State.FREE or item.sleeping:
				continue
			item.linear_velocity = Vector3.ZERO
			item.angular_velocity = Vector3.ZERO
			item.sleeping = true
			stat_forced_sleeps += 1

func _resurface() -> void:
	for item in _active:
		if not is_instance_valid(item) or item.state != LooseItem.State.FREE:
			continue
		var p := item.global_position
		var ground: float = ground_height.call(p)
		if ground == -INF or p.y > ground - RESURFACE_DEPTH:
			continue
		stat_resurfaced += 1
		item.teleport(Transform3D(item.global_transform.basis,
			Vector3(p.x, ground + item.get_aabb_half_height() + 0.3, p.z)))

func _rescue(item: LooseItem) -> void:
	stat_killplane += 1
	var spawn: Vector3 = _plot_spawns.get(item.plot_id, Vector3(0, 4, 0))
	# Small scatter so rescued items do not spawn inside each other.
	var jitter := Vector3(randf_range(-0.6, 0.6), randf_range(0.0, 1.5), randf_range(-0.6, 0.6))
	item.teleport(Transform3D(Basis(), spawn + jitter))
