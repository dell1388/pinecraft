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
## Spec: driving is third-person on the vehicle.
@export var chase_distance: float = 9.0
@export var chase_height: float = 2.8

## Water deeper than this is swum rather than waded.
const WADE_DEPTH := 1.1
const SWIM_SPEED_FACTOR := 0.38

## Wood shorter than this cannot be split any further.
const MIN_BUCK_LENGTH := 0.70
## Axe work required per square metre of cut face.
const BUCK_WORK_PER_M2 := 700.0
## How briskly a dragged piece is turned back into line with the player.
const DRAG_TURN_GAIN := 6.0

var manager: LooseItemManager
var plot: Plot
var store: Store
var terrain: Terrain
var build_system: BuildSystem
var vehicle: Node3D = null              ## set while driving

var held: Array[LooseItem] = []
var dragged: LooseItem = null
## The dragged piece's orientation relative to the player, captured when it was
## grabbed. Held constant, so the piece turns with the player instead of hanging
## in one world orientation while they pan around it.
var _drag_basis: Basis = Basis()
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

## How deep the water is where the player is standing.
func water_depth() -> float:
	if terrain == null:
		return 0.0
	return terrain.water_depth(global_position.x, global_position.z)

func _water_surface() -> float:
	return Terrain.WATER_LEVEL

func swimming() -> bool:
	return water_depth() > WADE_DEPTH

## The winch and crane on the vehicle being driven, if it has any.
func rig() -> VehicleRig:
	if vehicle == null:
		return null
	return vehicle.get("rig") as VehicleRig

## True while the crane has hold of something, which is when the player is
## driving the load rather than the truck.
func steering_load() -> bool:
	var r := rig()
	return r != null and r.holding()

# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		if camera.top_level:
			# Freecam: the camera carries its own yaw, since it is no longer
			# hanging off the player's shoulders.
			camera.rotation.y -= event.relative.x * mouse_sensitivity
			camera.rotation.x = clampf(
				camera.rotation.x - event.relative.y * mouse_sensitivity, -1.45, 1.45)
			return
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
	if driving() and _on_driving_key(event):
		return
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
		KEY_Z:
			if build_system != null and build_system.active:
				build_system.rotate_axis(0)
		KEY_X:
			if build_system != null and build_system.active:
				build_system.rotate_axis(1)
		KEY_C:
			if build_system != null and build_system.active:
				build_system.rotate_axis(2)

## Keys that only mean something with a vehicle under you. Returns true when the
## key was used here, so it does not also do its on-foot job.
func _on_driving_key(event: InputEventKey) -> bool:
	var r := rig()
	if r == null:
		return false
	match event.keycode:
		KEY_F:
			if r.holding():
				r.drop()
				interacted.emit("load released")
			else:
				var hit := aim_hit()
				var item := _owner_of(hit.get("collider")) as LooseItem if not hit.is_empty() else null
				interacted.emit(_said(r.grab(item), "crane has it"))
			return true
		KEY_E:
			if r.anchored:
				r.release_winch()
				interacted.emit("winch unhooked")
			else:
				var hit := aim_hit()
				if hit.is_empty():
					interacted.emit("nothing in front of the winch")
				else:
					interacted.emit(_said(
						r.attach_winch(_owner_of(hit.collider) as Node3D, hit.position),
						"winch hooked on"))
			return true
		KEY_R:
			if r.holding():
				_load_spin = 1
				return true
		KEY_T:
			if r.holding():
				_load_spin = -1
				return true
	return false

## Tool calls report a problem as text and success as an empty string; this
## turns that into something to show the player either way.
func _said(problem: String, success: String) -> String:
	return success if problem == "" else problem

# --- Movement --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_swing_cd = maxf(0.0, _swing_cd - delta)
	if driving():
		_update_rack()
		_update_vehicle_controls(delta)
		_update_chase_camera(delta)
		return

	if build_system != null and build_system.active:
		# The freecam has the camera; the body stays put until build mode ends.
		velocity = Vector3.ZERO
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
	# Spec: the player bobs slowly across water rather than swimming it.
	var depth := water_depth()
	if depth > WADE_DEPTH:
		speed *= SWIM_SPEED_FACTOR
		# Held at the surface with just enough give to bob, so deep water is
		# crossable but never quick.
		velocity.y = move_toward(velocity.y, 0.0, 40.0 * delta)
		if global_position.y < _water_surface() - 0.5:
			velocity.y = maxf(velocity.y, 2.4)

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

## Spec: the camera is third-person on the vehicle while driving, and fixed on
## the object while the crane is moving one.
func _update_chase_camera(_delta: float) -> void:
	var focus: Node3D = vehicle
	var r := rig()
	if r != null and r.holding():
		focus = r.held
	if focus == null or not is_instance_valid(focus):
		return
	var pivot := focus.global_position + Vector3(0, chase_height, 0)
	var basis := Basis.from_euler(Vector3(camera.rotation.x, rotation.y, 0.0))
	camera.global_transform = Transform3D(basis, pivot + basis.z * chase_distance)

## Spec: while the crane holds something the player drives the object - WASD
## slides it, Shift and Control raise and lower it, R and T turn it.
func _update_vehicle_controls(delta: float) -> void:
	var r := rig()
	if r == null:
		return
	if Input.is_action_pressed("reel"):
		r.reel(delta)
	if not r.holding():
		return
	var input := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_back"))
	# Lateral movement is read in the camera's frame, so "forward" is whichever
	# way the player is looking at the load from.
	var flat := Basis.from_euler(Vector3(0, rotation.y, 0))
	var move := (flat * Vector3(input.x, 0.0, input.y))
	var lift := 0.0
	if Input.is_action_pressed("sprint"):
		lift += 1.0
	if Input.is_action_pressed("lower"):
		lift -= 1.0
	r.steer(move, lift, _load_spin, delta)
	_load_spin = 0

var _load_spin: int = 0

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
				or node is SellYard or node is Schematic or node is VehiclePad \
				or node is Store \
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
	elif target is SellYard:
		last_prompt = (target as SellYard).status_line()
	elif target is Store:
		var shop := target as Store
		var role := shop.role_at(hit.position)
		last_prompt = shop.status_line(role) if role != &"" else "the store"
	elif target is VehiclePad:
		last_prompt = (target as VehiclePad).status_line()
	elif target is Schematic:
		var plan := target as Schematic
		last_prompt = ("%s" if plan.solid else "[E] add material   %s") % plan.status_line()
	elif target is Filter:
		last_prompt = "[E] change filter   %s" % (target as Filter).status_line()
	elif target is Conveyor:
		last_prompt = (target as Conveyor).status_line()
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
	item.owned = item.owned or not _must_buy(item)
	item.set_state(LooseItem.State.HELD)
	held.append(item)
	carry_changed.emit(held.size(), capacity_m3())
	return true

## Store stock has to be paid for before it is yours, so carrying it off a
## shelf does not make it yours the way picking up a log does.
func _must_buy(item: LooseItem) -> bool:
	var def := GameData.item(item.item_id)
	return def != null and def.must_buy

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
	item.owned = item.owned or not _must_buy(item)
	dragged = item
	_drag_basis = Basis(Vector3.UP, -rotation.y) * item.global_transform.basis.orthonormalized()
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

	# Turn the piece back to the orientation it had relative to the player, so
	# a length of timber swings round with them rather than staying put while
	# they walk around its end.
	var wanted := (Basis(Vector3.UP, rotation.y) * _drag_basis).get_rotation_quaternion()
	var current := dragged.global_transform.basis.get_rotation_quaternion()
	var turn := wanted * current.inverse()
	if turn.w < 0.0:
		turn = Quaternion(-turn.x, -turn.y, -turn.z, -turn.w)   # the short way round
	var angle := turn.get_angle()
	if angle > 0.002:
		var spin := turn.get_axis() * angle * DRAG_TURN_GAIN
		if spin.length() > Tuning.MAX_ANGULAR_SPEED:
			spin = spin.normalized() * Tuning.MAX_ANGULAR_SPEED
		dragged.angular_velocity = spin
	else:
		dragged.angular_velocity = Vector3.ZERO

# --- Interaction -----------------------------------------------------------

func _interact() -> void:
	var hit := aim_hit()
	var target := _owner_of(hit.get("collider")) if not hit.is_empty() else null
	if target == null:
		interacted.emit("")
		return
	if target is Conveyor:
		var belt := target as Conveyor
		interacted.emit("belt %s" % ("running" if belt.toggle() else "stopped"))
		return
	if target is Filter:
		var f := target as Filter
		if Input.is_action_pressed("sprint"):
			f.invert = not f.invert
		else:
			f.cycle_filter(1)
		interacted.emit(f.status_line())
		return
	if target is Store:
		_use_store(target as Store, hit.get("position", global_position))
		return
	if target is LooseItem and store != null:
		var said := store.open_box(target as LooseItem)
		if said != "that is not a box":
			interacted.emit(said)
			return
	if target is VehiclePad:
		var pad := target as VehiclePad
		var had := pad.has_vehicle()
		pad.spawn()
		interacted.emit("hauler respawned" if had else "hauler delivered")
		return
	if target is SellYard:
		var yard := target as SellYard
		# Whatever is on the rack goes over the counter with the rest, so the
		# player does not have to put it down first.
		var carried := held.duplicate()
		held.clear()
		for item in carried:
			item.owned = true
			item.set_state(LooseItem.State.FREE)
		carry_changed.emit(0, capacity_m3())
		yard.sell_all(carried)
		interacted.emit(yard.last_receipt)
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

## The till buys whatever is on the counter, including whatever the player is
## still holding; the desk sells land.
func _use_store(shop: Store, point: Vector3) -> void:
	match shop.role_at(point):
		&"desk":
			interacted.emit(shop.buy_land())
		&"till":
			var carried := held.duplicate()
			held.clear()
			for item in carried:
				item.set_state(LooseItem.State.FREE)
			carry_changed.emit(0, capacity_m3())
			var receipt := shop.buy(carried)
			if int(receipt.bought) > 0:
				interacted.emit("bought %d box(es) for $%d" % [
					int(receipt.bought), int(receipt.spent)])
			elif not (receipt.refused as Array).is_empty():
				interacted.emit(String((receipt.refused as Array)[0]))
			else:
				interacted.emit("nothing on the counter to pay for")
		_:
			interacted.emit("bring a box to the counter")

func enter_vehicle(v: Node3D) -> void:
	vehicle = v
	velocity = Vector3.ZERO

func exit_vehicle() -> void:
	var r := rig()
	if r != null:
		r.drop()
		r.release_winch()
	vehicle = null
	camera.position = Vector3(0, 1.65, 0)
	camera.rotation.y = 0.0
	camera.rotation.z = 0.0
