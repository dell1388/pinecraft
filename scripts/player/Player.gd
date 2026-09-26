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
## How far back the camera sits from the log in crane operator mode (the
## wheel zooms it; it pulls further back to keep the bed in view).
var crane_zoom: float = 7.0
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
## The piece's turn relative to the player's facing, held while it is in hand.
var _drag_turn: Basis = Basis()
const DRAG_TURN_RATE := 1.6          ## rad/s, Shift + WASDQE
const DRAG_SPIN_GAIN := 10.0
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
	# The pivot is the hand: it rests and swings. The tool sits in it turned
	# a quarter round, so the blade (or the hammer's face) leads the swing
	# rather than going in edge-sideways.
	_viewmodel_pivot = Node3D.new()
	_viewmodel_pivot.name = "ViewmodelPivot"
	camera.add_child(_viewmodel_pivot)
	_viewmodel = MeshInstance3D.new()
	_viewmodel.name = "Viewmodel"
	_viewmodel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_viewmodel.rotation = Vector3(0, PI * 0.5, 0)
	_viewmodel_pivot.add_child(_viewmodel)
	swung.connect(_swing_viewmodel)

# --- The tool in hand --------------------------------------------------------

var _viewmodel: MeshInstance3D
var _viewmodel_pivot: Node3D
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
		_viewmodel_pivot.position = Vector3(0.42, -0.62, -0.95)
		_viewmodel_pivot.rotation = VIEWMODEL_REST

func _swing_viewmodel() -> void:
	if not _viewmodel.visible:
		return
	if _viewmodel_tween != null:
		_viewmodel_tween.kill()
	var t := maxf(0.12, float(selected_tool_def().get("cooldown", 0.4)))
	_viewmodel_pivot.rotation = VIEWMODEL_REST
	_viewmodel_tween = create_tween()
	_viewmodel_tween.tween_property(_viewmodel_pivot, "rotation", VIEWMODEL_REST + Vector3(-1.2, 0.2, 0.3), t * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_viewmodel_tween.tween_property(_viewmodel_pivot, "rotation", VIEWMODEL_REST, t * 0.6).set_trans(Tween.TRANS_SINE)

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
	# Standing clear of the water line - on a bridge over the sea - you are
	# not in it, however deep it is underneath.
	if global_position.y > Terrain.WATER_LEVEL + 0.2:
		return 0.0
	# Nor in a cave below sea level: the rock keeps the sea out.
	if CaveNetwork.active != null and CaveNetwork.active.contains(global_position, 1.0):
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

## The loader arms on the vehicle being driven, if it has them.
func loader() -> LoaderArm:
	if vehicle == null:
		return null
	return vehicle.get("loader") as LoaderArm

## True while the crane has hold of something, which is when the player is
## driving the load rather than the truck.
func steering_load() -> bool:
	var r := rig()
	return r != null and r.operating

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
			elif driving():
				pass
			elif dragged != null:
				_throw_dragged()
			else:
				_pick_up()
		MOUSE_BUTTON_WHEEL_UP:
			if building:
				build_system.cycle(-1)
			elif steering_load():
				crane_zoom = maxf(3.0, crane_zoom - 1.0)
			elif dragged != null:
				_drag_distance = minf(_drag_distance + 0.3, reach)
			elif not driving():
				cycle_hotbar(-1)
		MOUSE_BUTTON_WHEEL_DOWN:
			if building:
				build_system.cycle(1)
			elif steering_load():
				crane_zoom = minf(30.0, crane_zoom + 1.0)
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
	# Shift and Q/E roll whatever is in hand.
	if turning_held() and (event.keycode == KEY_Q or event.keycode == KEY_E):
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
	# In a loader Q and E work the bucket (held, in _update_vehicle_controls).
	if loader() != null and (event.keycode == KEY_Q or event.keycode == KEY_E):
		return true
	if loader() != null and event.keycode == KEY_G:
		interacted.emit(loader().set_locked(not loader().locked))
		return true
	var r := rig()
	if r == null:
		return false
	match event.keycode:
		KEY_R:
			if not r.has_crane():
				interacted.emit("this vehicle has no crane")
			else:
				r.set_operating(not r.operating)
				interacted.emit("crane: you move the log - W/S away from / toward the camera, A/D left/right, Shift/Ctrl up and down, Q/E turn it, F grab"
					if r.operating else "crane folding away")
			return true
		KEY_F:
			# Working the crane, F is the grapple; otherwise it is the door.
			if r.operating:
				var had := r.held != null
				interacted.emit(_said(r.latch(), "let go" if had else "grapple closed"))
				return true
			return false
		KEY_Q, KEY_E:
			# In operator mode Q and E turn the log.
			if r.operating:
				return true
			if event.keycode == KEY_E:
				interacted.emit(hook_winch(r))
			return true
		KEY_Y:
			interacted.emit(hook_winch(r))
			return true
		KEY_O:
			interacted.emit(toggle_outriggers(r))
			return true
	return false

## Puts a rig's outriggers out, locking the truck where it stands, or brings
## them in.
func toggle_outriggers(r: VehicleRig) -> String:
	if r.operating or r.folding:
		return "the crane is working on them - stow it first [R]"
	r.set_outriggers(not r.outriggers_down)
	return "outriggers down - the truck is locked in place" if r.outriggers_down else "outriggers up"

## Hooks a rig's winch line to whatever the player is aiming at, or unhooks it.
func hook_winch(r: VehicleRig) -> String:
	if r.anchored:
		r.release_winch()
		return "winch unhooked"
	var hit := aim_hit_far(r.reach + 6.0)
	if hit.is_empty():
		return "nothing there to hook the winch to"
	var target := _owner_of(hit.collider) as Node3D
	if target == null:
		target = hit.collider as Node3D
	return _said(r.attach_winch(target, hit.position), "winch hooked on - [K] reel in, [L] let out")

## What the player is aiming at, further out than arm's reach.
func aim_hit_far(distance: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * distance
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var v := vehicle as CollisionObject3D
	if v != null:
		q.exclude.append(v.get_rid())
	return space.intersect_ray(q)

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
	# Holding Shift with something in hand, WASD turn it instead.
	if turning_held():
		input = Vector2.ZERO
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

## Spec: the camera is third-person on the vehicle while driving. Working the
## crane it orbits the log (or the empty grapple) - the mouse turns it, the
## wheel zooms - and pulls back far enough to keep the truck's bed in view.
## Turning it never changes which way the keys move the log.
func _update_chase_camera(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var basis := Basis.from_euler(Vector3(camera.rotation.x, rotation.y, 0.0))
	var r := rig()
	var pivot: Vector3
	var distance: float
	var skip: Array[RID] = []
	if r != null and r.operating:
		var focus := r.focus_point()
		var bed: Vector3 = vehicle.global_transform * Vector3(0, float(vehicle.get("bed_floor")), float(vehicle.get("bed_mid_z"))) \
			if vehicle.get("bed_mid_z") != null else vehicle.global_position
		var frame := clampf(focus.distance_to(bed) * 1.1 + 3.0, 5.0, 26.0)
		distance = maxf(crane_zoom, frame)
		pivot = focus + Vector3(0, 0.6, 0)
		# The log being looked at does not push the camera in.
		if r.held != null and is_instance_valid(r.held):
			skip.append(r.held.get_rid())
	else:
		pivot = vehicle.global_position + Vector3(0, chase_height, 0)
		distance = chase_distance
		if vehicle.get("camera_distance") != null:
			distance = float(vehicle.get("camera_distance"))
	var clear := _camera_clearance(pivot, basis.z, distance, skip)
	# In at once when something is in the way; back out gently once clear.
	_cam_distance = clear if clear < _cam_distance else move_toward(_cam_distance, clear, 12.0 * delta)
	camera.global_transform = Transform3D(basis, pivot + basis.z * _cam_distance)

var _cam_distance: float = 9.0
## How far the camera sits off the land and anything solid.
const CAMERA_RADIUS := 0.35

## How far back from `pivot` along `back` the camera can sit, up to `most`,
## without being inside terrain, a vehicle, a building, a tree or a log: a
## small sphere swept out from the pivot, stopped short of what it meets. If
## the pivot itself is inside something (the truck's own roof, say), that one
## thing is ignored rather than the camera jammed on the pivot.
func _camera_clearance(pivot: Vector3, back: Vector3, most: float, skip: Array[RID]) -> float:
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = CAMERA_RADIUS
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.collision_mask = Layers.WORLD | Layers.VEHICLE | Layers.MACHINE | Layers.TREE | Layers.LOOSE | Layers.KERB
	var excluded: Array[RID] = [get_rid()]
	excluded.append_array(skip)
	for attempt in 3:
		q.exclude = excluded
		q.transform = Transform3D(Basis(), pivot)
		var inside := space.get_rest_info(q)
		if not inside.is_empty():
			excluded.append(inside.rid)
			continue
		q.motion = back * most
		var f: float = space.cast_motion(q)[0]
		return maxf(0.5, most * f - 0.1)
	return most
## The winch (reel in, let out) whenever there is one, and in crane operator
## mode the log itself, relative to the camera: W/S away from and toward it,
## A/D to its left and right, Shift/Ctrl up and down, Q/E turn it. Holding the
## right mouse button is the slow, fine speed for setting it down.
func _update_vehicle_controls(delta: float) -> void:
	var l := loader()
	if l != null:
		# Shift raises the arms, Ctrl lowers them; E curls the bucket back,
		# Q tips it forward.
		var curl := (1.0 if Input.is_physical_key_pressed(KEY_E) else 0.0) \
			- (1.0 if Input.is_physical_key_pressed(KEY_Q) else 0.0)
		l.drive(Input.get_axis("lower", "sprint"), curl, delta)
	var r := rig()
	if r == null:
		return
	work_winch(r, delta)
	if not r.operating:
		return
	# W takes the log away from the camera, S toward it, A and D to the
	# camera's left and right - turned into the truck's frame.
	var axes := r.view_axes()
	var move := axes[0] * Input.get_axis("move_right", "move_left") \
		+ axes[1] * Input.get_axis("move_back", "move_forward") \
		+ Vector3.UP * Input.get_axis("lower", "sprint")
	var turn := (1.0 if Input.is_physical_key_pressed(KEY_Q) else 0.0) \
		- (1.0 if Input.is_physical_key_pressed(KEY_E) else 0.0)
	r.drive(move, turn, Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT), delta)

func work_winch(r: VehicleRig, delta: float) -> void:
	if Input.is_action_pressed("winch_in") or (driving() and Input.is_action_pressed("reel")):
		r.reel(delta)
	if Input.is_action_pressed("winch_out"):
		r.pay_out(delta)


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
		if h.has_bed():
			last_prompt = "[F] drive the %s   ·   [E] load\ncargo %d (%s)" % [
				h.display_name.to_lower(), h.cargo_count(), h.cargo_summary()]
		else:
			last_prompt = "[F] drive the %s" % h.display_name.to_lower()
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
		var piece := target as LooseItem
		var limb := piece.limb_at(hit.position)
		if limb >= 0:
			_limb(piece, limb)
		else:
			_buck(piece)
	else:
		_swing_cd = _tool_stat("cooldown", 0.4)

## Bucking: cutting felled wood down to a size you can move. Work needed scales
## with the cross-section at the cut, so a fat trunk takes real swings and a
## branch takes one or two - and a better axe cuts through more per swing.
## Limbing: taking a branch off a felled trunk. It comes away as a piece of
## its own; work scales with its cross-section, like any cut.
func _limb(item: LooseItem, index: int) -> void:
	_swing_cd = _tool_stat("cooldown", 0.4)
	var l: Dictionary = item.limbs[index]
	var needed: float = PI * float(l.radius) * float(l.radius) * BUCK_WORK_PER_M2
	l.cut = float(l.cut) + _tool_stat("damage", 34.0)
	if float(l.cut) < needed:
		interacted.emit("cutting branch: %d%%" % int(float(l.cut) / needed * 100.0))
		return
	var xform := item.limb_transform(index)
	var dims := item.limb_dims(index)
	item.remove_limb(index)
	var branch := manager.spawn(item.item_id, xform, item.plot_id, item.linear_velocity, dims, item.owned)
	if branch != null:
		branch.owned = item.owned
	interacted.emit("branch off" if not item.limbs.is_empty() else "last branch off - clean trunk")

func _buck(item: LooseItem) -> void:
	if not item.is_wood() or item.state != LooseItem.State.FREE:
		return
	_swing_cd = _tool_stat("cooldown", 0.4)
	if not item.limbs.is_empty():
		interacted.emit("take the branches off first (%d left)" % item.limbs.size())
		return
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
	_drag_turn = (_facing().inverse() * item.global_transform.basis).orthonormalized()
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

## The player's facing: yaw only, so looking up and down does not tip what
## is in hand.
func _facing() -> Basis:
	return Basis(Vector3.UP, global_rotation.y)

## Shift held with something in hand: WASDQE turn it rather than walk.
func turning_held() -> bool:
	return dragged != null and not driving() and Input.is_action_pressed("sprint")

## The turn the piece is held at: its angle to the player, kept as the player
## turns, so it swings round with them like something gripped in both hands.
func drag_basis() -> Basis:
	return (_facing() * _drag_turn).orthonormalized()

## Holds the piece where the hand is and at the angle it was picked up at
## (relative to the player). The grabbed point is put on the hold point, the
## piece turned to its held angle - both as velocity changes at its centre,
## capped at the player's strength, so heavy things come round slowly.
func _update_drag() -> void:
	if dragged == null:
		return
	if not is_instance_valid(dragged) or dragged.state != LooseItem.State.CARRIED:
		dragged = null
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _mouse_captured and not _hold_for_tests:
		_release_dragged()
		return
	var dt := get_physics_process_delta_time()
	if turning_held():
		# In the player's frame: W/S tip it over away/toward, A/D turn it
		# about the vertical, Q/E roll it about the line of sight.
		var pitch := Input.get_axis("move_back", "move_forward")
		var yaw := Input.get_axis("move_right", "move_left")
		var roll := (1.0 if Input.is_physical_key_pressed(KEY_Q) else 0.0) \
			- (1.0 if Input.is_physical_key_pressed(KEY_E) else 0.0)
		var spin := Vector3(-pitch, yaw, roll) * DRAG_TURN_RATE * dt
		if spin.length() > 0.0:
			_drag_turn = (Basis(spin.normalized(), spin.length()) * _drag_turn).orthonormalized()
	var want := drag_basis()
	var centre := drag_target() - want * _drag_point
	if centre.distance_to(dragged.global_position) > reach * 2.0 + dragged.length():
		_release_dragged()
		return
	# Heavy things are turned more slowly.
	var heft := clampf(DRAG_STRENGTH_KG / maxf(dragged.mass, 1.0) * 0.1, 0.15, 1.0)
	var wanted := (centre - dragged.global_position) * DRAG_GAIN
	if wanted.length() > carry_max_speed:
		wanted = wanted.normalized() * carry_max_speed
	# No gravity to fight: a held thing weighs nothing (see LooseItem).
	var impulse := (wanted - dragged.linear_velocity) * dragged.mass * 0.8
	var most := DRAG_STRENGTH_KG * 9.8 * 1.4 * dt
	if impulse.length() > most:
		impulse = impulse.normalized() * most
	dragged.apply_central_impulse(impulse)
	var q := (want * dragged.global_transform.basis.orthonormalized().inverse()).get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	var angle := 2.0 * acos(clampf(q.w, -1.0, 1.0))
	var spin_to := Vector3.ZERO
	if angle > 0.0001:
		spin_to = Vector3(q.x, q.y, q.z).normalized() * angle * DRAG_SPIN_GAIN
	var spin_top := 8.0 * heft
	if spin_to.length() > spin_top:
		spin_to = spin_to.normalized() * spin_top
	dragged.angular_velocity = spin_to

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
	# Seated, the body is carried in the cab: it must not collide with the
	# vehicle it sits in, or it shoves the chassis down onto its own wheels.
	collision_layer = 0
	collision_mask = 0

func exit_vehicle() -> void:
	var r := rig()
	if r != null:
		r.set_operating(false)
		r.release_winch()
	vehicle = null
	collision_layer = Layers.PLAYER
	collision_mask = Layers.MASK_PLAYER
	camera.position = Vector3(0, 1.65, 0)
	camera.rotation.y = 0.0
	camera.rotation.z = 0.0
