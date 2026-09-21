class_name Player
extends CharacterBody3D

## First-person player: move, chop, mine, haul, build, drive.
##
## Hauling uses a kinematic carry rack (items are frozen and snapped to slots),
## which costs the solver nothing and cannot jitter. The single-item heavy drag
## kept from the stress test stays velocity-driven, because steering a body's
## velocity toward a hold point is stable at any mass where a joint is not.

signal carry_changed(count: int, capacity_m3: float)
signal interacted(message: String)

@export var jump_velocity: float = 6.5
@export var mouse_sensitivity: float = 0.0022
@export var reach: float = 4.5
@export var vacuum_radius: float = 2.6
@export var carry_distance: float = 2.2
@export var carry_gain: float = 14.0
@export var carry_max_speed: float = 14.0
@export var throw_impulse: float = 9.0

## Wood shorter than this cannot be split any further.
const MIN_BUCK_LENGTH := 0.70
## Axe work required per square metre of cut face.
const BUCK_WORK_PER_M2 := 700.0

var manager: LooseItemManager
var plot: Plot
var build_system: BuildSystem
var vehicle: Node3D = null              ## set while driving

var held: Array[LooseItem] = []
var dragged: LooseItem = null
var last_prompt: String = ""

var _swing_cd: float = 0.0
var _mouse_captured: bool = false
var _ui_blocking: bool = false

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	InputSetup.ensure()
	collision_layer = Layers.PLAYER
	collision_mask = Layers.MASK_PLAYER
	capture_mouse(true)

func capture_mouse(capture: bool) -> void:
	_mouse_captured = capture
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE

## Set by the HUD while a menu is open, so clicks do not chop trees behind it.
func set_ui_blocking(blocking: bool) -> void:
	_ui_blocking = blocking
	capture_mouse(not blocking)

## The rack is measured in cubic metres, not items: one trunk is a load, a
## pocketful of billets is not.
func capacity_m3() -> float:
	return PlayerState.stat(&"carry", "capacity_m3", 0.18)

## The longest single piece the rack will take. Anything longer has to be
## dragged, bucked shorter, or loaded onto the hauler - a 6 m pole does not go
## on a shoulder at any weight.
func max_piece_length() -> float:
	return PlayerState.track_value(&"carry", "max_piece_m", 2.6)

## What the player can pick up and carry. Bulk is one limit; weight is the
## other, and a short length of ironwood hits the weight limit long before it
## fills the rack.
func lift_limit_kg() -> float:
	return PlayerState.stat(&"carry", "lift_kg", 100.0)

## What the player can shift without lifting it: the heavy drag, which is how
## anything between the lift limit and a tonne gets moved by hand.
func move_limit_kg() -> float:
	return PlayerState.track_value(&"carry", "move_kg", 1000.0)

func carried_volume() -> float:
	var total := 0.0
	for item in held:
		if is_instance_valid(item):
			total += item.volume()
	return total

func carried_count() -> int:
	return held.size()

func driving() -> bool:
	return vehicle != null

# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x, -1.45, 1.45)
		return
	if _ui_blocking:
		return
	if event is InputEventMouseButton and event.pressed:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventKey and event.pressed and not event.echo:
		_on_key(event as InputEventKey)

func _on_mouse_button(event: InputEventMouseButton) -> void:
	if not _mouse_captured:
		capture_mouse(true)
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if build_system != null and build_system.active:
				build_system.try_place()
			elif dragged != null:
				_throw_dragged()
			else:
				_swing()
		MOUSE_BUTTON_RIGHT:
			if build_system != null and build_system.active:
				build_system.try_remove()
			else:
				_pick_up()
		MOUSE_BUTTON_WHEEL_UP:
			if build_system != null and build_system.active:
				build_system.cycle(-1)
		MOUSE_BUTTON_WHEEL_DOWN:
			if build_system != null and build_system.active:
				build_system.cycle(1)

func _on_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_E:
			_interact()
		KEY_Q:
			_drop(1)
		KEY_G:
			_drop(held.size())
		KEY_F:
			if dragged != null:
				_release_dragged()
			else:
				_grab_drag()
		KEY_B:
			if build_system != null:
				build_system.toggle()
		KEY_R:
			if build_system != null and build_system.active:
				build_system.rotate_ghost()

# --- Movement --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_swing_cd = maxf(0.0, _swing_cd - delta)
	if driving():
		_update_rack()
		return

	if not is_on_floor():
		velocity += get_gravity() * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var walk := PlayerState.stat(&"boots", "walk", 5.5)
	var sprint := PlayerState.stat(&"boots", "sprint", 8.5)
	# Hauling a full rack slows you down: the reason to build belts.
	var load_factor: float = 1.0 - 0.35 * clampf(carried_volume() / maxf(0.01, capacity_m3()), 0.0, 1.0)
	var speed: float = (sprint if Input.is_action_pressed("sprint") else walk) * load_factor

	var input := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_back"))
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	if dir != Vector3.ZERO:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 5.0 * delta)
	move_and_slide()

	_update_rack()
	_update_drag()
	_update_prompt()

# --- Aiming ----------------------------------------------------------------

func aim_hit() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * reach
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.MASK_RAY_INTERACT, [get_rid()])
	return space.intersect_ray(q)

## Walks up from a collider to the gameplay node that owns it (machines and
## bins put their collider in a child StaticBody3D).
func _owner_of(collider: Object) -> Node:
	var node := collider as Node
	while node != null:
		if node is ChoppableTree or node is OreRock or node is LooseItem \
				or node is Machine or node is StorageBin or node is SellZone \
				or node is Conveyor or node is Filter or node is Splitter \
				or node is Hauler:
			return node
		node = node.get_parent()
	return null

func _update_prompt() -> void:
	if build_system != null and build_system.active:
		last_prompt = build_system.status_line()
		return
	var hit := aim_hit()
	if hit.is_empty():
		last_prompt = ""
		return
	var target := _owner_of(hit.collider)
	if target is ChoppableTree:
		var t := target as ChoppableTree
		var limb := t.limb_at(hit.position)
		var what := "branch" if limb >= 0 else "trunk at %.1f m" % t.to_local(hit.position).y
		last_prompt = "[LMB] cut %s  (%d%%)" % [what, int(t.cut_progress_at(hit.position) * 100.0)]
	elif target is OreRock:
		var r := target as OreRock
		var can_pull := r.pull_required() <= move_limit_kg()
		last_prompt = "[LMB] hammer (%d%%)   %s\n%s" % [
			int(r.worst_crack() * 100.0),
			"[F] haul it out" if can_pull else "[F] too deep to pull",
			r.status_line()]
	elif target is LooseItem:
		var i := target as LooseItem
		var label := "%s  %.2f m  %.3f m3  %.0f kg" % [
			GameData.item_name(i.item_id), i.length(), i.volume(), i.mass]
		var verbs: Array[String] = []
		if i.is_wood() and i.length() > MIN_BUCK_LENGTH:
			verbs.append("[LMB] buck")
		if i.mass <= lift_limit_kg() and i.length() <= max_piece_length():
			verbs.append("[RMB] pick up")
		if i.mass <= move_limit_kg():
			verbs.append("[F] drag")
		else:
			verbs.append("too heavy to move")
		last_prompt = "   ".join(verbs) + "\n" + label
	elif target is Machine:
		last_prompt = "[E] deposit   %s" % (target as Machine).status_line()
	elif target is StorageBin:
		last_prompt = "[E] deposit / [E+shift] empty   %s" % (target as StorageBin).summary()
	elif target is SellZone:
		last_prompt = "[E] sell carried items"
	elif target is Filter:
		last_prompt = "[E] change filter   %s" % (target as Filter).status_line()
	elif target is Hauler:
		var h := target as Hauler
		last_prompt = "[E] load   [V] drive   cargo %d/%d (%s)" % [
			h.cargo_count(), h.cargo_capacity, h.cargo_summary()]
	else:
		last_prompt = ""

# --- Tools -----------------------------------------------------------------

func _swing() -> void:
	if _swing_cd > 0.0:
		return
	var hit := aim_hit()
	if hit.is_empty():
		return
	var target := _owner_of(hit.collider)
	if target is ChoppableTree:
		_swing_cd = PlayerState.stat(&"axe", "cooldown", 0.4)
		# The cut lands where the axe lands, so the limb under the crosshair is
		# the one that comes off.
		var said := (target as ChoppableTree).cut(
			PlayerState.stat(&"axe", "damage", 34.0), hit.position, global_position)
		if said != "":
			interacted.emit(said)
	elif target is OreRock:
		# Rock is not chipped away at, it is cracked: the hammer's head mass is
		# what opens a crack, so a heavier hammer breaks a chunk in fewer blows.
		_swing_cd = PlayerState.stat(&"hammer", "cooldown", 0.55)
		var said := (target as OreRock).strike(PlayerState.stat(&"hammer", "head_kg", 3.0))
		if said != "":
			interacted.emit(said)
	elif target is LooseItem:
		_buck(target as LooseItem)

## Bucking: cutting felled wood down to a size you can move. Work needed scales
## with the cross-section at the cut, so a fat trunk takes real swings and a
## branch takes one or two - and a better axe cuts through more per swing.
func _buck(item: LooseItem) -> void:
	if not item.is_wood() or item.state != LooseItem.State.FREE:
		return
	_swing_cd = PlayerState.stat(&"axe", "cooldown", 0.4)
	if item.length() <= MIN_BUCK_LENGTH:
		interacted.emit("too short to cut - carry it or mill it")
		return
	var radius := Solid.max_radius(item.dims)
	var work_needed: float = PI * radius * radius * BUCK_WORK_PER_M2
	item.cut_progress += PlayerState.stat(&"axe", "damage", 34.0)
	if item.cut_progress < work_needed:
		interacted.emit("cutting: %d%%" % int(item.cut_progress / work_needed * 100.0))
		return
	var halves := manager.split_item(item, 0.5)
	if halves.is_empty():
		return
	interacted.emit("cut in two: %.2f m each" % halves[0].length())

# --- Carry rack ------------------------------------------------------------

func _pick_up() -> void:
	if carried_volume() >= capacity_m3():
		interacted.emit("carry rack full (%.2f m3)" % capacity_m3())
		return
	var hit := aim_hit()
	var target := _owner_of(hit.get("collider")) if not hit.is_empty() else null
	var item := target as LooseItem
	if item == null:
		item = _nearest_free_item(vacuum_radius)
	pick_up(item)

## Puts one free item on the carry rack. Returns false if it is full or the item
## is not available.
func pick_up(item: LooseItem) -> bool:
	if item == null or item.state != LooseItem.State.FREE:
		return false
	var volume := item.volume()
	if item.length() > max_piece_length():
		interacted.emit("%.1f m is too long to shoulder (limit %.1f m) - buck it or drag it [F]" % [
			item.length(), max_piece_length()])
		return false
	if item.mass > lift_limit_kg():
		interacted.emit("%.0f kg is too heavy to lift (limit %.0f kg) - drag it [F]" % [
			item.mass, lift_limit_kg()])
		return false
	if carried_volume() + volume > capacity_m3():
		return false
	if item == dragged:
		dragged = null
	item.owned = true
	item.set_state(LooseItem.State.HELD)
	held.append(item)
	carry_changed.emit(held.size(), capacity_m3())
	return true

func _nearest_free_item(radius: float) -> LooseItem:
	if manager == null:
		return null
	var best: LooseItem = null
	var best_d := radius * radius
	var origin := global_position + Vector3(0, 1.0, 0)
	for item in manager.free_items():
		var d: float = origin.distance_squared_to(item.global_position)
		if d < best_d:
			best_d = d
			best = item
	return best

func _drop(count: int) -> void:
	var forward := -camera.global_transform.basis.z
	for i in mini(count, held.size()):
		var item: LooseItem = held.pop_back()
		if not is_instance_valid(item):
			continue
		var pos := global_position + Vector3(0, 1.2 + float(i) * 0.25, 0) + forward * 1.2
		item.teleport(Transform3D(LooseItem.lying_basis(rotation.y), pos))
		item.set_state(LooseItem.State.FREE)
		item.linear_velocity = forward * 1.5 + Vector3.UP * 0.5
	carry_changed.emit(held.size(), capacity_m3())

## Slots are stacked in front of the chest; items are kinematic here, so this is
## a transform write and nothing else.
func _update_rack() -> void:
	if held.is_empty():
		return
	var forward := -global_transform.basis.z
	var stack_height := 0.0
	for i in range(held.size() - 1, -1, -1):
		var item: LooseItem = held[i]
		if not is_instance_valid(item) or item.state != LooseItem.State.HELD:
			held.remove_at(i)
			carry_changed.emit(held.size(), capacity_m3())
			return
	for i in held.size():
		var item: LooseItem = held[i]
		var thickness := item.resting_half_height() * 2.0
		var pos := global_position + Vector3(0, 0.8 + stack_height + thickness * 0.5, 0) \
			+ forward * 0.85
		stack_height += thickness + 0.02
		# Carried across the chest, so long pieces read as a shouldered load.
		item.global_transform = Transform3D(LooseItem.lying_basis(rotation.y + PI * 0.5), pos)

# --- Heavy drag (single item) ---------------------------------------------

func _grab_drag() -> void:
	var hit := aim_hit()
	if hit.is_empty():
		return
	var target := _owner_of(hit.collider)
	if target is OreRock:
		_pull_chunk(target as OreRock)
		return
	_grab_drag_item(target as LooseItem)

## Spec: freeing a buried chunk takes a pull of its mass plus the buried share
## of its mass again. The player's pull is the same strength as their drag.
func _pull_chunk(rock: OreRock) -> void:
	var freed := rock.try_free(move_limit_kg())
	if freed == null:
		interacted.emit("needs %.0f kg of pull, you have %.0f - crack it up instead" % [
			rock.pull_required(), move_limit_kg()])
		return
	freed.owned = true
	interacted.emit("hauled out a %.0f kg chunk" % freed.mass)

## Takes hold of one piece for the heavy drag. Refuses anything past the move
## limit: that is what a winch or a crane is for.
func _grab_drag_item(item: LooseItem) -> bool:
	if item == null or item.state != LooseItem.State.FREE:
		return false
	if item.mass > move_limit_kg():
		interacted.emit("%.0f kg will not budge (limit %.0f kg) - cut it down or winch it" % [
			item.mass, move_limit_kg()])
		return false
	item.owned = true
	dragged = item
	item.set_state(LooseItem.State.CARRIED)
	return true

func _release_dragged() -> void:
	if dragged == null:
		return
	dragged.set_state(LooseItem.State.FREE)
	dragged = null

func _throw_dragged() -> void:
	if dragged == null:
		return
	var item := dragged
	_release_dragged()
	item.apply_central_impulse(-camera.global_transform.basis.z * throw_impulse * item.mass * 0.15)

func _update_drag() -> void:
	if dragged == null:
		return
	if not is_instance_valid(dragged) or dragged.state != LooseItem.State.CARRIED:
		dragged = null
		return
	var target := camera.global_position - camera.global_transform.basis.z * carry_distance
	var to_target := target - dragged.global_position
	if to_target.length() > reach * 2.0:
		_release_dragged()
		return
	var desired := to_target * carry_gain
	if desired.length() > carry_max_speed:
		desired = desired.normalized() * carry_max_speed
	dragged.linear_velocity = desired
	dragged.angular_velocity *= 0.6

# --- Interaction -----------------------------------------------------------

func _interact() -> void:
	var hit := aim_hit()
	var target := _owner_of(hit.get("collider")) if not hit.is_empty() else null
	if target == null:
		interacted.emit("")
		return
	if target is Filter:
		var f := target as Filter
		if Input.is_action_pressed("sprint"):
			f.invert = not f.invert
		else:
			f.cycle_filter(1)
		interacted.emit(f.status_line())
		return
	if target is StorageBin and Input.is_action_pressed("sprint"):
		var n := (target as StorageBin).dispense_all()
		interacted.emit("emptying bin: %d item(s)" % n)
		return
	if target.has_method("accept_item"):
		var moved := deposit_into(target)
		if moved > 0:
			interacted.emit("deposited %d item(s)" % moved)
		else:
			interacted.emit("nothing to deposit")
		return
	interacted.emit("")

## Hands as many carried items as possible to a machine, bin or sell zone.
func deposit_into(sink: Object) -> int:
	var moved := 0
	for i in range(held.size() - 1, -1, -1):
		var item: LooseItem = held[i]
		if not is_instance_valid(item):
			held.remove_at(i)
			continue
		if not sink.can_accept(item.item_id):
			continue
		held.remove_at(i)
		item.set_state(LooseItem.State.FREE)
		if sink.accept_item(item):
			moved += 1
		else:
			held.append(item)
			item.set_state(LooseItem.State.HELD)
	if moved > 0:
		carry_changed.emit(held.size(), capacity_m3())
	return moved

func enter_vehicle(v: Node3D) -> void:
	vehicle = v
	velocity = Vector3.ZERO

func exit_vehicle() -> void:
	vehicle = null
