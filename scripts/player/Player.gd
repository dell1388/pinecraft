class_name Player
extends CharacterBody3D

## First-person player: move, chop, mine, haul, build, drive.
##
## Hands and tools. With nothing selected on the hotbar, the left mouse button
## grabs whatever is under the crosshair *by the point you clicked* and pulls
## that point toward the hold point, so a log grabbed by one end swings from
## that end. Tools (axes, hammers) live in the inventory and are used by
## selecting them on the hotbar. The carry rack (right mouse) is kept for now.

signal carry_changed(count: int, capacity_m3: float)
signal interacted(message: String)
signal swung()
## Asks the world to put the player in a vehicle's driving seat.
signal wants_to_drive(vehicle: Node3D)

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
## How hard the grabbed point is pulled toward the hold point (per second),
## and how strong the player is: the most force the hand can put on it.
const DRAG_GAIN := 9.0
const DRAG_STRENGTH_KG := 1000.0
const DRAG_MIN_DISTANCE := 1.2

var manager: LooseItemManager
var plot: Plot
var store: Store
## Every shop in the world; a box from either can be opened anywhere.
var stores: Array[Store] = []
var terrain: Terrain
var build_system: BuildSystem
var vehicle: Node3D = null              ## set while driving

var held: Array[LooseItem] = []
var dragged: LooseItem = null
## Where on the dragged piece it was grabbed, in the piece's own frame, and how
## far in front of the eye it is held.
var _drag_point: Vector3 = Vector3.ZERO
var _drag_distance: float = 2.2
## The hotbar slot in hand, or -1 for an empty hand.
var selected_slot: int = -1
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
	_viewmodel = MeshInstance3D.new()
	_viewmodel.name = "Viewmodel"
	_viewmodel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(_viewmodel)
	swung.connect(_swing_viewmodel)

# --- The tool in hand --------------------------------------------------------

var _viewmodel: MeshInstance3D
var _viewmodel_tool: StringName = &"<none>"
var _viewmodel_tween: Tween
const VIEWMODEL_REST := Vector3(-0.45, 0.35, -0.35)

func _process(_delta: float) -> void:
	var tool := selected_tool() if not driving() and not (build_system != null and build_system.active) else &""
	if tool == _viewmodel_tool:
		return
	_viewmodel_tool = tool
	_viewmodel.visible = tool != &""
	if tool != &"":
		_viewmodel.mesh = ToolModel.mesh(GameData.tool(tool))
		_viewmodel.position = Vector3(0.42, -0.62, -0.95)
		_viewmodel.rotation = VIEWMODEL_REST

func _swing_viewmodel() -> void:
	if not _viewmodel.visible:
		return
	if _viewmodel_tween != null:
		_viewmodel_tween.kill()
	var t := maxf(0.12, float(selected_tool_def().get("cooldown", 0.4)))
	_viewmodel.rotation = VIEWMODEL_REST
	_viewmodel_tween = create_tween()
	_viewmodel_tween.tween_property(_viewmodel, "rotation", VIEWMODEL_REST + Vector3(-1.2, 0.2, 0.3), t * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_viewmodel_tween.tween_property(_viewmodel, "rotation", VIEWMODEL_REST, t * 0.6).set_trans(Tween.TRANS_SINE)

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
	# Editing a building in build mode: the mouse is the gizmo's.
	if build_system != null and build_system.editing() and not _ui_blocking \
			and (event is InputEventMouseButton or event is InputEventMouseMotion):
		if build_system.edit_input(event):
			return
	if event is InputEventMouseMotion and _mouse_captured:
		var sens := mouse_sensitivity * Settings.mouse_scale()
		var look_y: float = event.relative.y * (-1.0 if Settings.invert_y() else 1.0)
		if camera.top_level:
			# Freecam: the camera carries its own yaw, since it is no longer
			# hanging off the player's shoulders.
			camera.rotation.y -= event.relative.x * sens
			camera.rotation.x = clampf(camera.rotation.x - look_y * sens, -1.45, 1.45)
			return
		rotate_y(-event.relative.x * sens)
		camera.rotate_x(-look_y * sens)
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
	var building := build_system != null and build_system.active
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if building:
				build_system.try_place()
			elif driving():
				pass
			elif selected_tool() != &"":
				_swing()
			else:
				_grab_drag()
		MOUSE_BUTTON_RIGHT:
			if building:
				build_system.try_remove()
			elif dragged != null:
				_throw_dragged()
			else:
				_pick_up()
		MOUSE_BUTTON_WHEEL_UP:
			if building:
				build_system.cycle(-1)
			elif dragged != null:
				_drag_distance = minf(_drag_distance + 0.3, reach)
			elif not driving():
				cycle_hotbar(-1)
		MOUSE_BUTTON_WHEEL_DOWN:
			if building:
				build_system.cycle(1)
			elif dragged != null:
				_drag_distance = maxf(_drag_distance - 0.3, DRAG_MIN_DISTANCE)
			elif not driving():
				cycle_hotbar(1)

# --- Hotbar ----------------------------------------------------------------

## The tool in hand, or &"" for an empty hand.
func selected_tool() -> StringName:
	return PlayerState.hotbar_tool(selected_slot)

func selected_tool_def() -> Dictionary:
	return GameData.tool(selected_tool())

## Number keys pick a slot; pressing the one in hand again empties the hand.
func select_slot(slot: int) -> void:
	if slot == selected_slot or PlayerState.hotbar_tool(slot) == &"":
		selected_slot = -1
	else:
		selected_slot = slot
		_release_dragged()

## The wheel steps through the filled slots and an empty hand.
func cycle_hotbar(step: int) -> void:
	var filled: Array[int] = [-1]
	for i in PlayerState.HOTBAR_SLOTS:
		if PlayerState.hotbar_tool(i) != &"":
			filled.append(i)
	var at := maxi(0, filled.find(selected_slot))
	selected_slot = filled[wrapi(at + step, 0, filled.size())]
	if selected_slot >= 0:
		_release_dragged()

func _on_key(event: InputEventKey) -> void:
	if driving() and _on_driving_key(event):
		return
	if build_system != null and build_system.active:
		if event.keycode == KEY_F:
			build_system.toggle_select()
			return
		if build_system.editing():
			if event.keycode >= KEY_1 and event.keycode <= KEY_3:
				build_system.set_edit_mode(int(event.keycode - KEY_1))
				return
			if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
				build_system.remove_selected()
				return
	# The number row picks off the build bar, or the hotbar on foot.
	if event.keycode >= KEY_1 and event.keycode <= KEY_9:
		if build_system != null and build_system.active:
			build_system.select_slot(int(event.keycode - KEY_1))
		elif not driving():
			select_slot(int(event.keycode - KEY_1))
		return
	match event.keycode:
		KEY_E:
			_interact()
		KEY_Q:
			_drop(1)
		KEY_G:
			_drop(held.size())
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
	var distance: float = chase_distance
	if focus == vehicle and vehicle.get("camera_distance") != null:
		distance = float(vehicle.get("camera_distance"))
	camera.global_transform = Transform3D(basis, pivot + basis.z * distance)

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
				or node is Machine or node is StorageBin \
				or node is SellYard or node is Schematic or node is VehiclePad \
				or node is Store \
				or node is Conveyor or node is Filter or node is Splitter \
				or node is Hauler or node.has_method("interact_prompt"):
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
	if target != null and target.has_method("interact_prompt"):
		last_prompt = String(target.call("interact_prompt"))
		return
	if target is ChoppableTree:
		var t := target as ChoppableTree
		var limb := t.limb_at(hit.position)
		var what := "branch" if limb >= 0 else "trunk at %.1f m" % t.to_local(hit.position).y
		if _tool_kind() == "axe":
			last_prompt = "[LMB] cut %s  (%d%%)" % [what, int(t.cut_progress_at(hit.position) * 100.0)]
		else:
			last_prompt = "take an axe from the hotbar to cut it"
	elif target is OreRock:
		var r := target as OreRock
		var can_pull := r.pull_required() <= move_limit_kg()
		var verbs := "[LMB] hammer (%d%%)" % int(r.worst_crack() * 100.0) if _tool_kind() == "hammer" \
			else ("[LMB] haul it out" if can_pull else "too deep to pull - crack it with a hammer") \
			if selected_slot < 0 else "take a hammer from the hotbar to crack it"
		last_prompt = "%s\n%s" % [verbs, r.status_line()]
	elif target is LooseItem and _shop_for(target as LooseItem) != null:
		last_prompt = _shop_for(target as LooseItem).box_line(target as LooseItem)
	elif target is LooseItem:
		var i := target as LooseItem
		var label := "%s   ·   %.2f m   ·   %.3f m³   ·   %.0f kg" % [
			i.display_name(), i.length(), i.volume(), i.mass]
		var verbs: Array[String] = []
		if _tool_kind() == "axe" and i.is_wood() and i.length() > MIN_BUCK_LENGTH:
			verbs.append("[LMB] buck")
		elif selected_slot < 0:
			verbs.append("[LMB] drag" if i.mass <= move_limit_kg() else "too heavy to move")
		if i.mass <= lift_limit_kg() and i.length() <= max_piece_length():
			verbs.append("[RMB] pick up")
		last_prompt = "   ".join(verbs) + "\n" + label
	elif target is Machine:
		last_prompt = "[E] deposit   %s" % (target as Machine).status_line()
	elif target is StorageBin:
		last_prompt = "[E] deposit / [E+shift] empty   %s" % (target as StorageBin).summary()
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
		if h.is_seat_point(hit.position):
			last_prompt = "[E] drive the %s" % h.display_name.to_lower()
		elif h.has_bed():
			last_prompt = "[E] load   ·   aim at the cab to drive\ncargo %d (%s)" % [
				h.cargo_count(), h.cargo_summary()]
		else:
			last_prompt = h.display_name
	else:
		last_prompt = ""

# --- Tools -----------------------------------------------------------------

func _tool_kind() -> String:
	return String(selected_tool_def().get("kind", ""))

func _tool_stat(key: String, fallback: float) -> float:
	return float(selected_tool_def().get(key, fallback))

## Swings whatever is in hand. An axe cuts trees and bucks felled wood; a
## hammer cracks rock. The wrong tool just says so.
func _swing() -> void:
	if _swing_cd > 0.0:
		return
	swung.emit()
	var hit := aim_hit()
	if hit.is_empty():
		_swing_cd = _tool_stat("cooldown", 0.4)
		return
	var target := _owner_of(hit.collider)
	var kind := _tool_kind()
	if target is ChoppableTree:
		if kind != "axe":
			interacted.emit("a hammer will not fell a tree - take an axe")
			return
		_swing_cd = _tool_stat("cooldown", 0.4)
		# The cut lands where the axe lands, so the limb under the crosshair is
		# the one that comes off.
		var said := (target as ChoppableTree).cut(_tool_stat("damage", 34.0), hit.position, global_position)
		if said != "":
			interacted.emit(said)
	elif target is OreRock:
		if kind != "hammer":
			interacted.emit("an axe will not crack rock - take a hammer")
			return
		# Rock is not chipped away at, it is cracked: the hammer's head mass is
		# what opens a crack, so a heavier hammer breaks a chunk in fewer blows.
		_swing_cd = _tool_stat("cooldown", 0.55)
		var said := (target as OreRock).strike(_tool_stat("head_kg", 3.0))
		if said != "":
			interacted.emit(said)
	elif target is LooseItem and kind == "axe":
		_buck(target as LooseItem)
	else:
		_swing_cd = _tool_stat("cooldown", 0.4)

## Bucking: cutting felled wood down to a size you can move. Work needed scales
## with the cross-section at the cut, so a fat trunk takes real swings and a
## branch takes one or two - and a better axe cuts through more per swing.
func _buck(item: LooseItem) -> void:
	if not item.is_wood() or item.state != LooseItem.State.FREE:
		return
	_swing_cd = _tool_stat("cooldown", 0.4)
	if item.length() <= MIN_BUCK_LENGTH:
		interacted.emit("too short to cut - carry it or mill it")
		return
	var radius := Solid.max_radius(item.dims)
	var work_needed: float = PI * radius * radius * BUCK_WORK_PER_M2
	item.cut_progress += _tool_stat("damage", 34.0)
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

# --- Dragging --------------------------------------------------------------

## Left mouse with an empty hand: take hold of whatever is under the
## crosshair, at the point under the crosshair.
func _grab_drag() -> void:
	var hit := aim_hit()
	if hit.is_empty():
		return
	var target := _owner_of(hit.collider)
	if target is OreRock:
		_pull_chunk(target as OreRock)
		return
	_grab_drag_item(target as LooseItem, hit.position)

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

## Takes hold of one piece at `point` (world space; the piece's centre if
## omitted). Refuses anything past the move limit: that is what a winch or a
## crane is for.
func _grab_drag_item(item: LooseItem, point: Variant = null) -> bool:
	if item == null or item.state != LooseItem.State.FREE:
		return false
	if item.mass > move_limit_kg():
		interacted.emit("%.0f kg will not budge (limit %.0f kg) - cut it down or winch it" % [
			item.mass, move_limit_kg()])
		return false
	item.owned = item.owned or not _must_buy(item)
	var at: Vector3 = point if point is Vector3 else item.global_position
	dragged = item
	_drag_point = item.global_transform.affine_inverse() * at
	_drag_distance = clampf(camera.global_position.distance_to(at), DRAG_MIN_DISTANCE, reach)
	item.set_state(LooseItem.State.CARRIED)
	return true

func _release_dragged() -> void:
	if dragged == null:
		return
	if is_instance_valid(dragged) and dragged.state == LooseItem.State.CARRIED:
		dragged.set_state(LooseItem.State.FREE)
	dragged = null

func _throw_dragged() -> void:
	if dragged == null:
		return
	var item := dragged
	_release_dragged()
	item.apply_central_impulse(-camera.global_transform.basis.z * throw_impulse * minf(item.mass, 60.0) * 0.5)

## Where the grabbed point is right now.
func drag_point() -> Vector3:
	if dragged == null:
		return Vector3.ZERO
	return dragged.global_transform * _drag_point

## Where the hand is trying to put it.
func drag_target() -> Vector3:
	return camera.global_position - camera.global_transform.basis.z * _drag_distance

## Pulls the grabbed point toward the hold point with an impulse applied *at
## that point*, sized with the body's real mass and inertia as seen from there
## (so a long log grabbed by the end swings rather than snapping straight),
## and capped at the player's strength. Heavy things come slowly; a light
## thing comes at once.
func _update_drag() -> void:
	if dragged == null:
		return
	if not is_instance_valid(dragged) or dragged.state != LooseItem.State.CARRIED:
		dragged = null
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _mouse_captured and not _hold_for_tests:
		_release_dragged()
		return
	var point := drag_point()
	var to_target := drag_target() - point
	if to_target.length() > reach * 2.0:
		_release_dragged()
		return
	var dt := get_physics_process_delta_time()
	var arm := point - dragged.global_position
	var state := PhysicsServer3D.body_get_direct_state(dragged.get_rid())
	var inv_inertia: Basis = state.inverse_inertia_tensor if state != null else Basis()
	var point_velocity := dragged.linear_velocity + dragged.angular_velocity.cross(arm)
	var wanted := to_target * DRAG_GAIN
	if wanted.length() > carry_max_speed:
		wanted = wanted.normalized() * carry_max_speed
	# Hold it up against gravity as well as moving it.
	var change := wanted - point_velocity + Vector3(0, 9.8 * dt, 0)
	# K maps an impulse at the point to the velocity change of the point.
	var skew := Basis(Vector3(0, arm.z, -arm.y), Vector3(-arm.z, 0, arm.x), Vector3(arm.y, -arm.x, 0))
	var m: Basis = skew * inv_inertia * skew
	var inv_mass := 1.0 / dragged.mass
	var k := Basis(Vector3(inv_mass, 0, 0) - m.x, Vector3(0, inv_mass, 0) - m.y, Vector3(0, 0, inv_mass) - m.z)
	var impulse: Vector3 = k.inverse() * change * 0.8
	var most := DRAG_STRENGTH_KG * 9.8 * 1.4 * dt
	if impulse.length() > most:
		impulse = impulse.normalized() * most
	dragged.apply_impulse(impulse, arm)

## Tests hold the mouse button in code.
var _hold_for_tests: bool = false

# --- Interaction -----------------------------------------------------------

func _interact() -> void:
	var hit := aim_hit()
	var target := _owner_of(hit.get("collider")) if not hit.is_empty() else null
	if target == null:
		interacted.emit("")
		return
	# Anything out in the world that just wants a press of [E]: caches, signs.
	if target.has_method("interact"):
		interacted.emit(String(target.call("interact", self)))
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
	if target is LooseItem:
		var shop := _shop_for(target as LooseItem)
		if shop != null:
			interacted.emit(shop.open_box(target as LooseItem))
			return
	if target is Hauler and (target as Hauler).is_seat_point(hit.get("position", Vector3.ZERO)):
		wants_to_drive.emit(target)
		return
	if target is VehiclePad:
		var pad := target as VehiclePad
		var had := pad.has_vehicle()
		pad.spawn()
		interacted.emit("%s %s" % [pad.vehicle_name(), "respawned" if had else "delivered"])
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
## The shop a box belongs to, if it is a shop box.
func _shop_for(item: LooseItem) -> Store:
	var all := stores.duplicate()
	if store != null and not all.has(store):
		all.append(store)
	for shop in all:
		if is_instance_valid(shop) and not shop._slot_for(item.item_id).is_empty():
			return shop
	return null

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
	_release_dragged()
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
