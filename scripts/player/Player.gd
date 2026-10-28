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
## [R] at a machine that can be set to a size: the HUD opens its settings.
signal machine_config_requested(machine: InlineMachine)
## [R] at a vehicle pad: the HUD opens its paint and fittings.
signal pad_config_requested(pad: VehiclePad)
signal filter_config_requested(filter: Filter)
## [E] at a finished sign: the HUD opens a box to write on it.
signal sign_edit_requested(sign: Schematic)
## At a trader's counter: the order sheet (OrderPanel) for it.
signal order_requested(counter: Node)
## Co-op, on the host: a guest's player was moved here rather than by the
## guest (back to base, out of a truck), so the guest must be told.
signal warped()

@export var jump_velocity: float = Balance.num("player.jump_velocity", 6.5)
@export var mouse_sensitivity: float = 0.0022
@export var reach: float = Balance.num("player.reach", 4.5)
@export var vacuum_radius: float = 2.6
@export var carry_distance: float = 2.2
@export var carry_gain: float = 14.0
@export var carry_max_speed: float = Balance.num("player.carry_max_speed", 14.0)
@export var throw_impulse: float = Balance.num("player.throw_impulse", 9.0)
## Spec: driving is third-person on the vehicle.
@export var chase_distance: float = 9.0
## The mouse wheel's zoom on the camera behind a vehicle, and on the one
## orbiting the log in crane operator mode: a multiple of how far back each
## sits by itself (under 1 is in closer).
var drive_zoom: float = 1.0
var crane_zoom: float = 1.0
const ZOOM_MIN := 0.35
const ZOOM_MAX := 3.0
@export var chase_height: float = 2.8

## Walking and sprinting, as a multiple of what the boots give.
static var WALK_MULT: float = Balance.num("player.walk_multiplier", 1.0)

## Water deeper than this is swum rather than waded.
const WADE_DEPTH := 1.1
static var SWIM_SPEED_FACTOR: float = Balance.num("player.swim_speed_factor", 0.38)

## Wood shorter than this cannot be split any further.
static var MIN_BUCK_LENGTH: float = Balance.num("cutting.min_buck_length", 0.35)
## Axe work required per square metre of cut face.
static var BUCK_WORK_PER_M2: float = Balance.num("cutting.buck_work_per_m2", 700.0)
## The smallest piece a hammer will split a loose chunk into.
static var MIN_CRACK_VOLUME: float = Balance.num("cutting.min_crack_volume", 0.004)
## How hard the grabbed point is pulled toward the hold point (per second),
## and how strong the player is: the most force the hand can put on it.
const DRAG_GAIN := 9.0
static var DRAG_STRENGTH_KG: float = Balance.num("player.drag_strength_kg", 1000.0)
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
static var DRAG_TURN_RATE: float = Balance.num("player.drag_turn_rate", 1.6)         ## rad/s, Shift + WASDQE
const DRAG_SPIN_GAIN := 10.0
## The hotbar slot in hand, or -1 for an empty hand.
var selected_slot: int = -1
var last_prompt: String = ""

var _swing_cd: float = 0.0
var _mouse_captured: bool = false
## Where this player's keys and buttons come from: the keyboard, or a co-op
## guest's game.
var input := PlayerInput.new()

## Co-op, on a guest's machine: this player walks here, so moving is instant,
## and the host is told where it is; its keys and clicks are sent to the host
## to act on, and in a truck it is wherever the host has the truck.
var net_view: bool = false
## Co-op, on the host: a guest's player, standing where the guest says.
var net_follow: bool = false
var net_target: Vector3 = Vector3.ZERO
var net_has_target: bool = false
## Bumped each time the host moves the player itself; the guest's reports of
## where it is count again once they carry the new number.
var net_warp_seq: int = 0
var _follow_last: Variant = null
## What the host says is on the rack: [count, volume].
var net_carry: Array = [0, 0.0]
## A co-op guest's own tools, hotbar and gear (a PlayerKit). Null for the
## player at this machine, whose kit is PlayerState.
var kit: PlayerKit = null

func kit_of() -> Object:
	return kit if kit != null else PlayerState

## On the host: a key or button a co-op guest pressed, acted on as if pressed
## here.
func remote_press(event: InputEvent) -> void:
	if _on_mouse_action(event):
		return
	_on_key(event)

## The lumberjack himself, posed from what you are doing (see PlayerAvatar).
var avatar: PlayerAvatar
## Looking over his shoulder rather than out of his eyes (the camera-view key).
var third_person: bool = false
## How far behind and to the side the camera sits in third person.
const THIRD_PERSON_DISTANCE := 3.4
const THIRD_PERSON_SHOULDER := 0.55
var _tp_distance: float = THIRD_PERSON_DISTANCE
var _ui_blocking: bool = false

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	InputSetup.ensure()
	add_to_group(&"players")
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
	avatar = PlayerAvatar.new(self)
	add_child(avatar)
	swung.connect(act.bind(&"swing"))
	third_person = Settings.flag(&"third_person")

# --- The tool in hand --------------------------------------------------------

var _viewmodel: MeshInstance3D
var _viewmodel_pivot: Node3D
var _viewmodel_tool: StringName = &"<none>"
var _viewmodel_tween: Tween
const VIEWMODEL_REST := Vector3(-0.45, 0.35, -0.35)

func _process(delta: float) -> void:
	if knocked() or crushed():
		_update_down_camera(delta)
	# Every drawn frame, not every physics tick: the mouse turns the camera
	# each frame, and placed only on the ticks it steps round in jerks.
	elif driving():
		_update_chase_camera(delta)
	# In the crusher's wheels, the view shakes.
	if grinding():
		camera.h_offset = randf_range(-1.0, 1.0) * 0.06 * _shake
		camera.v_offset = randf_range(-1.0, 1.0) * 0.06 * _shake
	elif camera.h_offset != 0.0 or camera.v_offset != 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	_update_view(delta)
	var tool := selected_tool() if not driving() and not (build_system != null and build_system.active) else &""
	_viewmodel_pivot.visible = not third_person
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

## A move for the lumberjack to make: a gesture name from PlayerAvatar.
func act(kind: StringName) -> void:
	if avatar != null:
		avatar.play(kind)

# --- First and third person --------------------------------------------------

func set_third_person(on: bool) -> void:
	third_person = on
	Settings.set_value(&"third_person", on)
	if not on and not driving() and not camera.top_level:
		camera.position = Vector3(0, 1.65, 0)
		camera.rotation.y = 0.0
		camera.rotation.z = 0.0

## On foot in third person, the camera hangs behind his right shoulder, looking
## the way you look, and comes in when something is in the way. Driving has its
## own camera, and build mode flies it.
func _update_view(delta: float) -> void:
	if driving() or camera.top_level or not third_person:
		return
	var basis := Basis.from_euler(Vector3(camera.rotation.x, global_rotation.y, 0.0))
	var pivot := global_position + Vector3(0, 1.75, 0) + basis.x * THIRD_PERSON_SHOULDER
	var skip: Array[RID] = []
	if dragged != null and is_instance_valid(dragged):
		skip.append(dragged.get_rid())
	var clear := _camera_clearance(pivot, basis.z, THIRD_PERSON_DISTANCE, skip)
	_tp_distance = clear if clear < _tp_distance else move_toward(_tp_distance, clear, 8.0 * delta)
	camera.global_transform = Transform3D(basis, pivot + basis.z * _tp_distance)

## Where aiming, reach and holding are measured from. In first person that is
## the camera; in third person it is the point on the camera's line of sight
## level with his head, so the crosshair still picks what it covers but reach
## is counted from him rather than from the camera behind him.
func eye() -> Vector3:
	var cam := camera.global_position
	if not third_person or driving() or camera.top_level:
		return cam
	var forward := -camera.global_transform.basis.z
	var head := global_position + Vector3(0, 1.65, 0)
	return cam + forward * maxf(0.0, (head - cam).dot(forward))

func capture_mouse(capture: bool) -> void:
	_mouse_captured = capture
	if not input.remote:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE

## Set by the HUD while a menu is open, so clicks do not chop trees behind it.
func set_ui_blocking(blocking: bool) -> void:
	_ui_blocking = blocking
	capture_mouse(not blocking)

## The rack is measured in cubic metres, not items: one trunk is a load, a
## pocketful of billets is not.
func capacity_m3() -> float:
	return kit_of().stat(&"carry", "capacity_m3", 0.18)

## The longest single piece the rack will take. Anything longer has to be
## dragged, bucked shorter, or loaded onto the hauler - a 6 m pole does not go
## on a shoulder at any weight.
func max_piece_length() -> float:
	return kit_of().track_value(&"carry", "max_piece_m", 2.6)

## What the player can pick up and carry. Bulk is one limit; weight is the
## other, and a short length of ironwood hits the weight limit long before it
## fills the rack.
func lift_limit_kg() -> float:
	return kit_of().stat(&"carry", "lift_kg", 100.0)

## What the player can shift without lifting it: the heavy drag, which is how
## anything between the lift limit and a tonne gets moved by hand.
func move_limit_kg() -> float:
	return kit_of().track_value(&"carry", "move_kg", 1000.0)

func carried_volume() -> float:
	if net_view:
		return float(net_carry[1])
	var total := 0.0
	for item in held:
		if is_instance_valid(item):
			total += item.volume()
	return total

func carried_count() -> int:
	if net_view:
		return int(net_carry[0])
	return held.size()

func driving() -> bool:
	return vehicle != null and is_instance_valid(vehicle)

## In a vehicle but not at the wheel: riding along in co-op.
var passenger: bool = false

## At the wheel (not a passenger): the keys work the vehicle.
func at_wheel() -> bool:
	return driving() and not passenger

## The vehicle went from under the player (a pad sent it back and made a new
## one): on their feet again, solid, where they sat.
func _vehicle_gone() -> void:
	vehicle = null
	velocity = Vector3.ZERO
	collision_layer = 0 if net_view else Layers.PLAYER
	collision_mask = Layers.MASK_PLAYER
	camera.position = Vector3(0, 1.65, 0)
	camera.rotation.y = 0.0
	camera.rotation.z = 0.0

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
	# A co-op guest's player on the host: its keys come from the guest, not
	# from this keyboard and mouse.
	if input.remote:
		return
	# Editing a building in build mode: the mouse is the gizmo's.
	if build_system != null and build_system.editing() and not _ui_blocking \
			and (event is InputEventMouseButton or event is InputEventMouseMotion):
		if build_system.edit_input(event):
			return
	if event is InputEventMouseMotion and _mouse_captured:
		var sens := mouse_sensitivity * Settings.mouse_scale()
		var look_y: float = event.relative.y * (-1.0 if Settings.invert_y() else 1.0)
		if knocked() or crushed():
			# Down: the mouse swings the watching camera round him.
			rotate_y(-event.relative.x * sens)
			return
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
	if knocked() or crushed() or grinding():
		# Nothing to be done while flying through the air, or in the wheels.
		return
	var press := (event is InputEventMouseButton or event is InputEventKey) \
		and event.is_pressed() and not event.is_echo()
	if not press:
		return
	if event is InputEventMouseButton and not _mouse_captured:
		capture_mouse(true)
		return
	if net_view:
		# A co-op guest builds here - the host is asked to put it up - and
		# every other press is the host's to act on.
		var building := build_system != null and build_system.active
		if building or Controls.pressed(event, &"build_mode"):
			if not _on_mouse_action(event):
				_on_key(event)
			return
		# A machine's sizes are set here, on its picture, and sent on.
		if Controls.pressed(event, &"machine_output") and not driving() and (_cycle_machine_output() or _cycle_pad_attachment()):
			return
		if Net.client_side != null:
			Net.client_side.call("send_press", event)
		return
	if _on_mouse_action(event):
		return
	_on_key(event)

## The mouse-button jobs: whatever `primary`, `secondary` and the wheel are
## bound to. Returns true when the event was one of them.
func _on_mouse_action(event: InputEvent) -> bool:
	var building := build_system != null and build_system.active
	if Controls.pressed(event, &"primary"):
		if building:
			build_system.try_place()
			act(&"place")
		elif driving():
			pass
		elif selected_tool() != &"":
			_swing()
		else:
			_grab_drag()
		return true
	if Controls.pressed(event, &"secondary"):
		if building:
			build_system.try_remove()
			act(&"remove")
		elif driving():
			pass
		elif dragged != null:
			_throw_dragged()
		else:
			_pick_up()
		return true
	if building and Controls.pressed(event, &"pick_block"):
		interacted.emit(build_system.pick_block())
		act(&"use")
		return true
	for step in [-1, 1]:
		if not Controls.pressed(event, &"wheel_up" if step < 0 else &"wheel_down"):
			continue
		if building:
			build_system.cycle(step)
		elif steering_load():
			crane_zoom = clampf(crane_zoom * pow(1.12, float(step)), ZOOM_MIN, ZOOM_MAX)
		elif driving():
			drive_zoom = clampf(drive_zoom * pow(1.12, float(step)), ZOOM_MIN, ZOOM_MAX)
		elif dragged != null:
			_drag_distance = clampf(_drag_distance - 0.3 * float(step), DRAG_MIN_DISTANCE, reach)
		elif not driving():
			cycle_hotbar(step)
		return true
	return false

# --- Hotbar ----------------------------------------------------------------

## The tool in hand, or &"" for an empty hand.
func selected_tool() -> StringName:
	return kit_of().hotbar_tool(selected_slot)

func selected_tool_def() -> Dictionary:
	return GameData.tool(selected_tool())

## Number keys pick a slot; pressing the one in hand again empties the hand.
func select_slot(slot: int) -> void:
	if slot == selected_slot or kit_of().hotbar_tool(slot) == &"":
		selected_slot = -1
	else:
		selected_slot = slot
		_release_dragged()

## The wheel steps through the filled slots and an empty hand.
func cycle_hotbar(step: int) -> void:
	var filled: Array[int] = [-1]
	for i in PlayerKit.HOTBAR_SLOTS:
		if kit_of().hotbar_tool(i) != &"":
			filled.append(i)
	var at := maxi(0, filled.find(selected_slot))
	selected_slot = filled[wrapi(at + step, 0, filled.size())]
	if selected_slot >= 0:
		_release_dragged()

func _on_key(event: InputEvent) -> void:
	if Controls.pressed(event, &"camera_view"):
		set_third_person(not third_person)
		return
	if at_wheel() and _on_driving_key(event):
		act(&"lever")
		return
	var building := build_system != null and build_system.active
	if building:
		if Controls.pressed(event, &"add_select"):
			build_system.toggle_select(true)
			return
		if Controls.pressed(event, &"edit_select"):
			build_system.toggle_select(false)
			return
		if build_system.editing():
			var mode := Controls.slot_pressed(event)
			if mode >= 0 and mode <= 2:
				build_system.set_edit_mode(mode)
				return
			if Controls.pressed(event, &"remove_selected"):
				build_system.remove_selected()
				return
		if Controls.pressed(event, &"build_menu"):
			build_system.toggle_menu()
			return
	# The number row picks off the hotbar on foot; in build mode the build
	# menu is where things are chosen, and Q empties your hand.
	var slot := Controls.slot_pressed(event)
	if slot >= 0:
		if not building and not driving():
			select_slot(slot)
		return
	if building and Controls.pressed(event, &"drop_one"):
		build_system.clear_choice()
		return
	if Controls.pressed(event, &"build_mode"):
		if build_system != null:
			var was := build_system.active
			build_system.toggle()
			if not was and not build_system.active:
				interacted.emit(build_system.last_error)
		return
	if building:
		if Controls.pressed(event, &"rotate_x"):
			build_system.rotate_axis(0)
		elif Controls.pressed(event, &"rotate_y"):
			build_system.rotate_axis(1)
		elif Controls.pressed(event, &"rotate_z"):
			build_system.rotate_axis(2)
		return
	if driving():
		return
	# Shift and the turn keys roll whatever is in hand.
	if turning_held() and (Controls.pressed(event, &"turn_ccw") or Controls.pressed(event, &"turn_cw")):
		return
	if Controls.pressed(event, &"machine_output") and (_cycle_machine_output() or _cycle_pad_attachment()):
		act(&"use")
		return
	if Controls.pressed(event, &"use"):
		act(&"use")
		_interact()
	elif Controls.pressed(event, &"drop_one"):
		_drop(1)
	elif Controls.pressed(event, &"drop_all"):
		_drop(held.size())
	elif Controls.pressed(event, &"throw"):
		if dragged != null:
			_throw_dragged()
		else:
			throw_one()

## Keys that only mean something with a vehicle under you. Returns true when the
## key was used here, so it does not also do its on-foot job.
func _on_driving_key(event: InputEvent) -> bool:
	var l := loader()
	# In a loader the turn keys work the bucket (held, in _update_vehicle_controls).
	if l != null and (Controls.pressed(event, &"turn_ccw") or Controls.pressed(event, &"turn_cw")):
		return true
	if Controls.pressed(event, &"rig_home"):
		if l != null:
			l.home()
			interacted.emit("bucket back to its carrying pose")
			return true
		if rig() != null and rig().operating:
			rig().home()
			interacted.emit("crane back to its starting spot")
			return true
		return false
	if l != null and Controls.pressed(event, &"loader_lock"):
		interacted.emit(l.set_locked(not l.locked))
		return true
	var truck := vehicle as Hauler
	if truck != null and l == null and (rig() == null or not rig().operating):
		if Controls.pressed(event, &"gear_up") and truck.manual_gearbox():
			interacted.emit(truck.shift_gear(1))
			return true
		if Controls.pressed(event, &"gear_down") and truck.manual_gearbox():
			interacted.emit(truck.shift_gear(-1))
			return true
	var r := rig()
	if r == null:
		return false
	if Controls.pressed(event, &"crane"):
		if not r.has_crane():
			interacted.emit("this vehicle has no crane")
		else:
			r.set_operating(not r.operating)
			interacted.emit("crane: you move the log - [W/S] away from / toward the camera, [A/D] left/right, [Shift/Ctrl] up and down, [Q/E] turn it, [F] drop the claw"
				if r.operating else "crane folding away")
		return true
	if r.operating:
		if Controls.pressed(event, &"enter_vehicle"):
			# Working the crane, the get-out key is the grapple.
			var had := r.held != null
			var said := r.claw()
			interacted.emit(said if said != "" else ("let go" if had else "claw going down"))
			return true
		# In operator mode the turn keys turn the log.
		if Controls.pressed(event, &"turn_ccw") or Controls.pressed(event, &"turn_cw"):
			return true
	if Controls.pressed(event, &"winch_hook") or (not r.operating and Controls.pressed(event, &"use")):
		interacted.emit(hook_winch(r))
		return true
	if Controls.pressed(event, &"outriggers"):
		interacted.emit(toggle_outriggers(r))
		return true
	return false

## Puts a rig's outriggers out, locking the truck where it stands, or brings
## them in.
func toggle_outriggers(r: VehicleRig) -> String:
	if not r.has_crane():
		return "only a crane truck has outriggers"
	if r.operating or r.folding:
		return "the crane is working on them - stow it first [R]"
	r.set_outriggers(not r.outriggers_down)
	return "outriggers down - the truck is locked in place" if r.outriggers_down else "outriggers up"

## Hooks a rig's winch line to whatever the player is aiming at, or unhooks it.
func hook_winch(r: VehicleRig) -> String:
	if r.anchored:
		r.release_winch()
		return "winch unhooked"
	var hit := winch_target(r)
	if hit.is_empty():
		return "nothing there to hook the winch to"
	var target := _owner_of(hit.collider) as Node3D
	if target == null:
		target = hit.collider as Node3D
	return _said(r.attach_winch(target, hit.position), "winch hooked on - [K] reel in, [L] let out")

## Where the winch hook would go: what the crosshair is on - or, when that is
## only the ground (or nothing), the log, chunk or tree nearest the line of
## sight, so the hook does not need pixel-perfect aim. The reticle shows the
## same point.
func winch_target(r: VehicleRig) -> Dictionary:
	var distance := r.reach + 6.0
	var hit := aim_hit_far(distance)
	if not hit.is_empty() and _hookable(hit.collider):
		return hit
	var from := eye()
	var dir := -camera.global_transform.basis.z
	var along_to := distance if hit.is_empty() else from.distance_to(hit.position) + 1.5
	var box := BoxShape3D.new()
	box.size = Vector3(WINCH_SNAP * 2.0, WINCH_SNAP * 2.0, along_to)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT),
		from + dir * along_to * 0.5)
	q.collision_mask = Layers.LOOSE | Layers.TREE
	var excluded: Array[RID] = [get_rid()]
	if vehicle is CollisionObject3D:
		excluded.append((vehicle as CollisionObject3D).get_rid())
	q.exclude = excluded
	var best: Dictionary = {}
	var best_score := INF
	for h in get_world_3d().direct_space_state.intersect_shape(q, 32):
		var body := h.collider as Node3D
		if body == null or not _hookable(body):
			continue
		var p := body.global_position
		if body is ChoppableTree:
			p += Vector3(0, 1.0, 0)
		var t := (p - from).dot(dir)
		if t < 1.0 or t > along_to:
			continue
		var off := (p - (from + dir * t)).length()
		if off > WINCH_SNAP:
			continue
		var score := off + t * 0.02
		if score < best_score:
			best_score = score
			best = {"collider": body, "position": p, "normal": Vector3.UP}
	if not best.is_empty():
		return best
	return hit

## How far off the line of sight the winch looks for something to hook.
const WINCH_SNAP := 1.4

func _hookable(collider: Object) -> bool:
	var n := _owner_of(collider)
	if n is LooseItem:
		return (n as LooseItem).state == LooseItem.State.FREE
	return n is OreRock or n is ChoppableTree or n is Hauler

## What the player is aiming at, further out than arm's reach.
func aim_hit_far(distance: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := eye()
	var to := from - camera.global_transform.basis.z * distance
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = _aim_exclusions()
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
	_physics_step(delta)
	input.end_frame()

func _physics_step(delta: float) -> void:
	if crushed():
		_crushed_step(delta)
		return
	if grinding():
		_grind_step(delta)
		return
	if tumble != null and not is_instance_valid(tumble):
		# The body went (dropped into something): up he gets.
		_end_ragdoll()
		collision_layer = Layers.PLAYER
		collision_mask = Layers.MASK_PLAYER
		_restore_camera()
	if knocked():
		_tumble_step(delta)
		return
	if vehicle != null and not is_instance_valid(vehicle):
		_vehicle_gone()
	if net_view and driving():
		# In a truck the body is where the host has it. Driving it here, the
		# arms are worked here too.
		if vehicle is Hauler and (vehicle as Hauler).net_mirror and not passenger:
			_update_vehicle_controls(delta)
		return
	_swing_cd = maxf(0.0, _swing_cd - delta)
	if net_follow and driving():
		_follow_last = null
	if driving():
		_update_rack()
		if not passenger:
			_update_vehicle_controls(delta)
		return

	if build_system != null and build_system.active:
		# The freecam has the camera; the body stays put until build mode ends.
		velocity = Vector3.ZERO
		_update_rack()
		return

	if net_follow:
		_follow_guest()
		_check_vehicles()
		_update_rack()
		_update_drag()
		_update_prompt()
		return

	var ladder := _ladder_here()
	if ladder != null:
		# On a ladder: forward or jump climbs, down climbs down, and nothing
		# held hangs on - no falling off it.
		if input.pressed("move_forward") or input.pressed("jump"):
			velocity.y = CLIMB_SPEED
		elif input.pressed("lower") or input.pressed("move_back"):
			velocity.y = -CLIMB_SPEED
		else:
			velocity.y = 0.0
	elif not is_on_floor():
		velocity += get_gravity() * delta
	elif input.pressed("jump"):
		# Held, it jumps again each time it lands.
		velocity.y = jump_velocity
		act(&"jump")

	var walk: float = kit_of().stat(&"boots", "walk", 5.5) * WALK_MULT
	var sprint: float = kit_of().stat(&"boots", "sprint", 8.5) * WALK_MULT
	# Hauling a full rack slows you down: the reason to build belts.
	var load_factor: float = 1.0 - 0.35 * clampf(carried_volume() / maxf(0.01, capacity_m3()), 0.0, 1.0)
	var speed: float = (sprint if sprinting() else walk) * load_factor
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
		input.axis("move_left", "move_right"),
		input.axis("move_forward", "move_back"))
	# Holding Shift with something in hand, WASD turn it instead.
	if turning_held():
		input = Vector2.ZERO
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	if on_ice():
		# On frost wood: slow to get going, slower to stop.
		var aim := dir * speed
		velocity.x = move_toward(velocity.x, aim.x, 2.0 * delta)
		velocity.z = move_toward(velocity.z, aim.z, 2.0 * delta)
	elif dir != Vector3.ZERO:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		# Standing still ends a toggled run.
		_sprint_latched = false
		velocity.x = move_toward(velocity.x, 0.0, speed * 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 5.0 * delta)
	var wanted := Vector3(velocity.x, 0.0, velocity.z)
	var was_floor := is_on_floor()
	var fall_speed := -velocity.y
	move_and_slide()
	if not was_floor and is_on_floor() and fall_speed > FALL_KNOCK_SPEED:
		knock(Vector3(velocity.x * 0.3, fall_speed * 0.25, velocity.z * 0.3))
		return
	if not net_view:
		_check_vehicles()
		if knocked():
			return
	_footsteps(delta)
	if was_floor and wanted.length() > 0.5 and is_on_wall():
		_step_up(wanted * delta)
	if net_view:
		# The rest - what is carried, dragged, looked at - is the host's.
		return

	_update_rack()
	_update_drag()
	_update_prompt()

## A step sound every stride or so, on the ground and moving. Only for the
## player at this machine; a co-op guest's player on the host is heard on
## the guest's own machine.
var _stride: float = 0.0
func _footsteps(delta: float) -> void:
	if input.remote or not is_on_floor():
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 1.0:
		_stride = 0.0
		return
	_stride += speed * delta
	if _stride >= 1.7:
		_stride = 0.0
		Sfx.play(&"step", global_position, -10.0)

## Sprinting: held down, or (with toggle sprint on) tapped on and left on
## until tapped again or you stop.
var _sprint_latched: bool = false
func sprinting() -> bool:
	if not Settings.flag(&"toggle_sprint") or input.remote:
		return input.pressed("sprint")
	if input.just_pressed("sprint"):
		_sprint_latched = not _sprint_latched
	return _sprint_latched

const CLIMB_SPEED := 2.6

## The ladder the player is on, if any.
func _ladder_here() -> Ladder:
	for l in get_tree().get_nodes_in_group(&"ladders"):
		var ladder := l as Ladder
		if ladder != null and ladder.holds(global_position + Vector3.UP * 0.3):
			return ladder
	return null

## A kerb, a step, the edge of a slab: walked up rather than stopped at.
const STEP_HEIGHT := 0.45
func _step_up(motion: Vector3) -> void:
	# Far enough on that the body comes down on top of the step, not on its
	# edge.
	var ahead := motion.normalized() * maxf(motion.length(), 0.3)
	var start := global_transform
	var up := Vector3.UP * STEP_HEIGHT
	# Room above, and nothing in the way up there.
	if test_move(start, up):
		return
	var raised := start.translated(up)
	if test_move(raised, ahead):
		return
	global_transform = raised.translated(ahead)
	# Back down onto whatever the step is.
	var hit := move_and_collide(-up * 1.05)
	if hit == null:
		# Nothing under it: it was not a step.
		global_transform = start
		return
	if global_position.y < start.origin.y + 0.02:
		global_transform = start

## On the host: a guest's player goes where the guest last said it was. If
## something here moved it instead - or it has just got out of a truck, or
## just arrived - the guest is sent to where it is.
func _follow_guest() -> void:
	if _follow_last == null or global_position.distance_to(_follow_last) > 2.0:
		net_warp_seq += 1
		net_has_target = false
		velocity = Vector3.ZERO
		warped.emit()
	elif net_has_target:
		velocity = (net_target - global_position) * float(Engine.physics_ticks_per_second)
		global_position = net_target
	_follow_last = global_position

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
	var mask := CAMERA_MASK
	var crane := r != null and r.operating
	if crane:
		var focus := r.focus_point()
		var bed: Vector3 = vehicle.global_transform * Vector3(0, float(vehicle.get("bed_floor")), float(vehicle.get("bed_mid_z"))) \
			if vehicle.get("bed_mid_z") != null else vehicle.global_position
		var frame := clampf(focus.distance_to(bed) * 1.1 + 3.0, 5.0, 26.0)
		distance = frame * crane_zoom
		pivot = focus + Vector3(0, 0.6, 0)
		# Logs on the ground, in the bed and in the grapple never push the
		# camera in: working a pile, there is always one going past.
		mask &= ~Layers.LOOSE
		if r.held != null and is_instance_valid(r.held):
			skip.append(r.held.get_rid())
	else:
		pivot = vehicle.global_position + Vector3(0, chase_height, 0)
		distance = chase_distance
		if vehicle.get("camera_distance") != null:
			distance = float(vehicle.get("camera_distance"))
		distance *= drive_zoom
		# The truck itself, what it tows and what it carries never push the
		# camera in: only the world around it does.
		if vehicle is Hauler:
			skip.append_array((vehicle as Hauler).train_rids())
	# A swinging log and the pull-back that keeps the bed in view both move
	# the camera, so on the crane it follows them smoothly rather than
	# shaking with every sway. Behind a truck it stays locked on.
	if crane and _cam_crane:
		var k := 1.0 - exp(-8.0 * delta)
		_cam_pivot = _cam_pivot.lerp(pivot, k)
		_cam_want = lerpf(_cam_want, distance, k)
	else:
		_cam_pivot = pivot
		_cam_want = distance
	_cam_crane = crane
	var clear := _camera_clearance(_cam_pivot, basis.z, _cam_want, skip, mask)
	# In at once when something is in the way; back out gently once clear.
	_cam_distance = clear if clear < _cam_distance else move_toward(_cam_distance, clear, 12.0 * delta)
	camera.global_transform = Transform3D(basis, _cam_pivot + basis.z * _cam_distance)

var _cam_pivot: Vector3 = Vector3.ZERO
var _cam_want: float = 9.0
var _cam_crane: bool = false
var _cam_distance: float = 9.0
## How far the camera sits off the land and anything solid.
const CAMERA_RADIUS := 0.35
## What the camera keeps out of.
const CAMERA_MASK := Layers.WORLD | Layers.VEHICLE | Layers.MACHINE | Layers.TREE | Layers.LOOSE | Layers.KERB

## How far back from `pivot` along `back` the camera can sit, up to `most`,
## without being inside terrain, a vehicle, a building, a tree or a log: a
## small sphere swept out from the pivot, stopped short of what it meets. If
## the pivot itself is inside something (the truck's own roof, say), that one
## thing is ignored rather than the camera jammed on the pivot.
func _camera_clearance(pivot: Vector3, back: Vector3, most: float, skip: Array[RID],
		mask: int = CAMERA_MASK) -> float:
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = CAMERA_RADIUS
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.collision_mask = mask
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
	# A guest driving on their own machine works the arms there.
	var theirs := net_follow and vehicle is Hauler and (vehicle as Hauler).net_follow
	var l := loader()
	if l != null and not theirs:
		# Shift raises the arms, Ctrl lowers them; E curls the bucket back,
		# Q tips it forward.
		l.drive(input.axis(&"lower", &"sprint"), input.axis(&"turn_ccw", &"turn_cw"), delta)
	var r := rig()
	if r == null:
		return
	if not net_view:
		work_winch(r, delta)
	if r.claw_said != "":
		interacted.emit(r.claw_said)
		r.claw_said = ""
	if not r.operating or theirs:
		return
	# W takes the log away from the camera, S toward it, A and D to the
	# camera's left and right - turned into the truck's frame.
	var axes := r.view_axes(camera)
	var move := axes[0] * input.axis("move_right", "move_left") \
		+ axes[1] * input.axis("move_back", "move_forward") \
		+ Vector3.UP * input.axis("lower", "sprint")
	var turn := input.axis(&"turn_cw", &"turn_ccw")
	r.drive(move, turn, input.held(&"secondary"), delta)

func work_winch(r: VehicleRig, delta: float) -> void:
	if input.held(&"winch_in") or (driving() and loader() == null and input.held(&"drop_all")):
		r.reel(delta)
	if input.held(&"winch_out"):
		r.pay_out(delta)


# --- Aiming ----------------------------------------------------------------

## The nearest unfilled plan along the aim, within reach.
func _aim_plan() -> Dictionary:
	var from := eye()
	var q := PhysicsRayQueryParameters3D.create(from, from - camera.global_transform.basis.z * reach, Layers.TRIGGER)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var skip: Array[RID] = []
	for attempt in 6:
		q.exclude = skip
		var h := get_world_3d().direct_space_state.intersect_ray(q)
		if h.is_empty():
			return {}
		var area := h.collider as Area3D
		if area != null and area.get_parent() is Schematic:
			return {"collider": area.get_parent(), "position": h.position, "normal": h.normal}
		skip.append(h.rid)
	return {}

## Standing on something slick (a frost-wood build).
func on_ice() -> bool:
	if not is_on_floor():
		return false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var body := c.get_collider() as Node
		if body != null and body.has_meta(&"slippery") and c.get_normal().y > 0.6:
			return true
	# Standing still there may be no fresh contact: look straight down too.
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.2, 0),
		global_position - Vector3(0, 1.4, 0), Layers.WORLD | Layers.MACHINE, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and (hit.collider as Node).has_meta(&"slippery")

func aim_hit() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := eye()
	var to := from - camera.global_transform.basis.z * reach
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.MASK_RAY_INTERACT, _aim_exclusions())
	return space.intersect_ray(q)

## The player, and what is on their carry rack: the rack is in front of the
## chest, and the crosshair looks past it rather than at it.
func _aim_exclusions() -> Array[RID]:
	var out: Array[RID] = [get_rid()]
	for item in held:
		if is_instance_valid(item):
			out.append(item.get_rid())
	return out

## At a loader's pad: which attachment the next loader comes with.
func _cycle_pad_attachment() -> bool:
	var hit := aim_hit()
	var pad := _owner_of(hit.get("collider")) as VehiclePad if not hit.is_empty() else null
	if pad == null:
		return false
	pad_config_requested.emit(pad)
	return true

## At a machine: steps through the sizes it can make its output in. Returns
## false when not aiming at one that has a choice.
func _cycle_machine_output() -> bool:
	var hit := aim_hit()
	var target := _owner_of(hit.get("collider")) if not hit.is_empty() else null
	if target is Filter:
		filter_config_requested.emit(target as Filter)
		return true
	if target is Splitter:
		var sp := target as Splitter
		var way := sp.toggle_toward(hit.position)
		if way < 0:
			interacted.emit("aim at the side you want to lock (left, front or right), not the way in")
			return true
		interacted.emit("%s way %s" % [Splitter.WAY_NAMES[way], "opened" if sp.enabled_outputs[way] else "locked"])
		# A guest's splitter is a picture of the host's: the host is told.
		if Net.is_client() and Net.client_side != null:
			var id := int(Net.client_side.call("id_of", sp))
			if id >= 0:
				Net.client_side.call("send_event", {"t": "fcfg", "id": id, "state": sp.to_dict()})
		return true
	var m := target as InlineMachine
	if m == null or m.config_fields().is_empty():
		return false
	machine_config_requested.emit(m)
	return true

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
		var over := build_system.plan_hover_text()
		if over != "":
			last_prompt += "\n" + over
		return
	var hit := aim_hit()
	# A plan not yet filled has nothing solid to aim at: its box counts.
	var plan_hit := _aim_plan()
	if not plan_hit.is_empty() and (hit.is_empty() or eye().distance_to(plan_hit.position) < eye().distance_to(hit.position) + 0.3):
		hit = plan_hit
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
		elif _tool_kind() == "hammer" and i.is_rough_stone() and i.volume() >= MIN_CRACK_VOLUME * 2.0:
			verbs.append("[LMB] crack (%d%%)" % int(i.cut_progress * 100.0))
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
	elif target is Conveyor:
		last_prompt = (target as Conveyor).status_line()
	elif target is Splitter:
		last_prompt = (target as Splitter).status_line()
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
		Sfx.play(&"whoosh", camera.global_position, -10.0)
		return
	var target := _owner_of(hit.collider)
	var kind := _tool_kind()
	# What it sounds like: wood takes an axe with a thunk, rock rings.
	if (target is ChoppableTree or target is LooseItem) and kind == "axe":
		Sfx.play(&"chop", hit.position)
	elif (target is OreRock or target is LooseItem) and kind == "hammer":
		Sfx.play(&"clink", hit.position)
	if target is ChoppableTree:
		if kind != "axe":
			interacted.emit("a hammer will not fell a tree - take an axe")
			return
		_swing_cd = _tool_stat("cooldown", 0.4)
		if not _tool_can_work((target as ChoppableTree).wood_item):
			return
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
		if not _tool_can_work((target as OreRock).ore_item):
			return
		var said := (target as OreRock).strike(_tool_stat("head_kg", 3.0))
		if said != "":
			interacted.emit(said)
	elif target is LooseItem and kind == "hammer" and (target as LooseItem).is_rough_stone():
		_crack(target as LooseItem)
	elif target is LooseItem and kind == "axe":
		var piece := target as LooseItem
		var limb := piece.limb_at(hit.position)
		if limb >= 0:
			_limb(piece, limb, hit.position)
		else:
			_buck(piece, hit.position)
	else:
		_swing_cd = _tool_stat("cooldown", 0.4)

## Harder woods and stones need a better tool: a level-2 material will not
## give to a level-1 axe or hammer. Says so and returns false if the tool in
## hand is not up to it.
func _tool_can_work(item_id: StringName) -> bool:
	var need := GameData.material_level(item_id)
	var have := int(_tool_stat("level", 1.0))
	if have >= need:
		return true
	interacted.emit("%s needs a level %d %s - this one is level %d" % [
		GameData.item_name(item_id), need, _tool_kind(), have])
	return false

## Limbing: cutting a branch on a felled trunk wherever the axe lands. Cut at
## the trunk it comes away whole; further out, the end comes off and a stub
## stays on. Work scales with the cross-section at the cut, like any cut.
func _limb(item: LooseItem, index: int, at: Vector3) -> void:
	_swing_cd = _tool_stat("cooldown", 0.4)
	var l: Dictionary = item.limbs[index]
	# The cut goes where the axe lands, anywhere along the branch; aiming
	# somewhere else starts a fresh cut.
	var along := item.limb_distance(index, at)
	if float(l.cut_at) < 0.0 or absf(along - float(l.cut_at)) > 0.3:
		l.cut_at = along
		l.cut = 0.0
	var r0 := float(l.radius)
	var r := lerpf(r0, float(l.get("tip", r0 * 0.7)), float(l.cut_at) / maxf(0.01, float(l.length)))
	var needed: float = PI * r * r * BUCK_WORK_PER_M2
	l.cut = float(l.cut) + _tool_stat("damage", 34.0)
	if float(l.cut) < needed:
		interacted.emit("cutting branch: %d%%" % int(float(l.cut) / needed * 100.0))
		return
	var had := item.limbs.size()
	var off := item.cut_limb(index, float(l.cut_at))
	var branch := manager.spawn(item.item_id, off.xform, item.plot_id, item.linear_velocity, off.dims, item.owned)
	if branch != null:
		branch.owned = item.owned
	if item.limbs.size() == had:
		interacted.emit("branch cut back: %.2f m off" % Solid.length_of(off.dims))
	else:
		interacted.emit("branch off" if not item.limbs.is_empty() else "last branch off - clean trunk")

## Bucking: cutting felled wood wherever the axe lands. Work scales with the
## cross-section there, so a fat trunk takes real swings and a branch takes
## one or two. Branches still on it go with whichever piece they grow from.
func _buck(item: LooseItem, at: Vector3) -> void:
	if not item.is_wood() or item.state != LooseItem.State.FREE:
		return
	_swing_cd = _tool_stat("cooldown", 0.4)
	var length := item.length()
	if length <= MIN_BUCK_LENGTH:
		interacted.emit("too short to cut - carry it or mill it")
		return
	var y := clampf(item.to_local(at).y, -length * 0.5 + LooseItem.MIN_STUB, length * 0.5 - LooseItem.MIN_STUB)
	if absf(y - item.cut_at) > 0.3:
		item.cut_at = y
		item.cut_progress = 0.0
	var t := (item.cut_at + length * 0.5) / length
	var radius := Solid.max_radius(Solid.split(item.dims, t)[1]) if item.dims.get("shape", Solid.BOX) == Solid.CYLINDER \
		else Solid.max_radius(item.dims)
	var work_needed: float = PI * radius * radius * BUCK_WORK_PER_M2
	item.cut_progress += _tool_stat("damage", 34.0)
	if item.cut_progress < work_needed:
		interacted.emit("cutting: %d%%" % int(item.cut_progress / work_needed * 100.0))
		return
	var pieces := manager.split_item(item, t)
	if pieces.size() < 2:
		return
	interacted.emit("cut: %.2f m and %.2f m" % [pieces[0].length(), pieces[1].length()])

## Cracking a loose chunk of ore or rough stone in two, so a piece too big
## for a machine's mouth can be broken down to fit. Like cracking it in the
## ground: a heavier hammer gets through in fewer blows, a bigger chunk takes
## more. The two halves hold exactly what the chunk did.
func _crack(item: LooseItem) -> void:
	if item.state != LooseItem.State.FREE:
		return
	_swing_cd = _tool_stat("cooldown", 0.55)
	var v := item.volume()
	if v < MIN_CRACK_VOLUME * 2.0:
		interacted.emit("too small to crack - it will go through any machine")
		return
	item.cut_progress += _tool_stat("head_kg", 3.0) * OreRock.CRACK_GAIN / pow(maxf(0.05, v), 2.0 / 3.0)
	if item.cut_progress < 1.0:
		interacted.emit("cracking: %d%%" % int(item.cut_progress * 100.0))
		return
	var at := item.global_transform
	var id := item.item_id
	var dims := item.dims
	var plot := item.plot_id
	var owned := item.owned
	var velocity := item.linear_velocity
	manager.despawn(item)
	var half := Solid.keep_finish(dims, Solid.chunk(v * 0.5))
	var side := pow(v * 0.5, 1.0 / 3.0)
	for s in [-1.0, 1.0]:
		var piece := manager.spawn(id, Transform3D(at.basis, at.origin + at.basis.x.normalized() * s * side * 0.55),
			plot, velocity + at.basis.x.normalized() * s * 0.8 + Vector3.UP * 0.6, half.duplicate(true), owned)
		if piece != null:
			piece.owned = owned
	interacted.emit("cracked in two: %.3f m3 each (%.2f m across)" % [v * 0.5, side])

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
	act(&"pick_up")
	Sfx.play(&"pickup", item.global_position, -4.0)
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

func _drop(count: int, toward: Vector3 = Vector3.ZERO) -> void:
	if count > 0 and not held.is_empty():
		act(&"drop")
	var forward := toward.normalized() if toward.length_squared() > 0.0001 else -camera.global_transform.basis.z
	for i in mini(count, held.size()):
		var item: LooseItem = held.pop_back()
		if not is_instance_valid(item):
			continue
		var pos := global_position + Vector3(0, 1.2 + float(i) * 0.25, 0) + forward * 1.2
		item.teleport(Transform3D(LooseItem.lying_basis(rotation.y), pos))
		item.set_state(LooseItem.State.FREE)
		item.linear_velocity = forward * 1.5 + Vector3.UP * 0.5
		Sfx.play(&"drop", pos, -6.0)
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
	act(&"grab")
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
	_drag_distance = clampf(eye().distance_to(at), DRAG_MIN_DISTANCE, reach)
	_drag_turn = (_facing().inverse() * item.global_transform.basis).orthonormalized()
	item.set_state(LooseItem.State.CARRIED)
	act(&"grab")
	return true

func _release_dragged() -> void:
	if dragged == null:
		return
	if is_instance_valid(dragged) and dragged.state == LooseItem.State.CARRIED:
		dragged.set_state(LooseItem.State.FREE)
	dragged = null

## Throws the top piece off the rack where the camera looks: a light one
## flies, a heavy one is more of a heave.
func throw_one() -> bool:
	if held.is_empty():
		return false
	var item: LooseItem = held.pop_back()
	carry_changed.emit(held.size(), capacity_m3())
	if not is_instance_valid(item):
		return false
	var aim := -camera.global_transform.basis.z
	var pos := eye() + aim * 0.9 + Vector3.DOWN * 0.2
	act(&"throw")
	item.teleport(Transform3D(LooseItem.lying_basis(rotation.y), pos))
	item.set_state(LooseItem.State.FREE)
	var speed := throw_impulse * clampf(25.0 / maxf(item.mass, 1.0), 0.3, 1.2)
	item.linear_velocity = aim * speed + velocity
	Sfx.play(&"whoosh", pos)
	return true

func _throw_dragged() -> void:
	if dragged == null:
		return
	var item := dragged
	_release_dragged()
	act(&"throw")
	item.apply_central_impulse(-camera.global_transform.basis.z * throw_impulse * minf(item.mass, 60.0) * 0.5)

## Where the grabbed point is right now.
func drag_point() -> Vector3:
	if dragged == null:
		return Vector3.ZERO
	return dragged.global_transform * _drag_point

## Where the hand is trying to put it.
func drag_target() -> Vector3:
	return eye() - camera.global_transform.basis.z * _drag_distance

## The player's facing: yaw only, so looking up and down does not tip what
## is in hand.
func _facing() -> Basis:
	return Basis(Vector3.UP, global_rotation.y)

## Shift held with something in hand: WASDQE turn it rather than walk.
func turning_held() -> bool:
	return dragged != null and not driving() and input.pressed("sprint")

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
	if not input.held(&"primary") and _mouse_captured and not _hold_for_tests:
		_release_dragged()
		return
	var dt := get_physics_process_delta_time()
	if turning_held():
		# In the player's frame: W/S tip it over away/toward, A/D turn it
		# about the vertical, Q/E roll it about the line of sight.
		var pitch := input.axis("move_back", "move_forward")
		var yaw := input.axis("move_right", "move_left")
		var roll := input.axis(&"turn_cw", &"turn_ccw")
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
	if target is Store:
		_use_store(target as Store, hit.get("position", global_position))
		return
	if target is Schematic and (target as Schematic).is_sign() and (target as Schematic).solid:
		sign_edit_requested.emit(target as Schematic)
		interacted.emit("")
		return
	if target is Schematic and (target as Schematic).is_door() and (target as Schematic).solid:
		interacted.emit((target as Schematic).toggle_door())
		return
	if target is LooseItem and (target as LooseItem).item_id == &"tnt_stick":
		interacted.emit(_light_tnt(target as LooseItem))
		return
	if target is LooseItem:
		var shop := _shop_for(target as LooseItem)
		if shop != null:
			var box := target as LooseItem
			# Not paid for: [E] buys it where it stands; then [E] opens it.
			if not box.owned:
				var receipt := shop.buy([box] as Array[LooseItem])
				if int(receipt.bought) > 0:
					interacted.emit("bought %s for %s - [E] again to open it" % [
						GameData.item_name(box.item_id).replace("Boxed ", ""), UIKit.money(int(receipt.spent))])
				elif not (receipt.refused as Array).is_empty():
					interacted.emit(String((receipt.refused as Array)[0]))
				return
			interacted.emit(shop.open_box(box, kit_of()))
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
		# player does not have to put it down first - what this yard buys,
		# anyway; the rest stays on the rack.
		var carried: Array[LooseItem] = []
		for i in range(held.size() - 1, -1, -1):
			var item: LooseItem = held[i]
			if is_instance_valid(item) and yard.takes(item):
				held.remove_at(i)
				item.owned = true
				item.set_state(LooseItem.State.FREE)
				carried.append(item)
		carry_changed.emit(held.size(), capacity_m3())
		yard.sell_all(carried)
		interacted.emit(yard.last_receipt)
		return
	if target is StorageBin and input.pressed("sprint"):
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
	# Nothing comes into the cab: what is in hand is let go, and the rack is
	# set down on the ground beside you, away from the vehicle.
	_release_dragged()
	if not held.is_empty():
		var away := global_position - v.global_position
		away.y = 0.0
		_drop(held.size(), away if away.length_squared() > 0.01 else global_transform.basis.z)
	vehicle = v
	velocity = Vector3.ZERO
	# Seated, the body is carried in the cab: it must not collide with the
	# vehicle it sits in, or it shoves the chassis down onto its own wheels.
	collision_layer = 0
	collision_mask = 0

func _solid_again() -> void:
	for i in 2:
		await get_tree().physics_frame
	if vehicle == null:
		collision_layer = Layers.PLAYER
		collision_mask = Layers.MASK_PLAYER

func exit_vehicle() -> void:
	var r := rig()
	if r != null:
		r.set_operating(false)
		r.release_winch()
	vehicle = null
	passenger = false
	# Solid again only once the body has been moved out to the door and the
	# physics has caught up: the jump from the seat would otherwise be taken
	# as a sweep through the cab, and kick the vehicle metres away.
	_solid_again()
	camera.position = Vector3(0, 1.65, 0)
	camera.rotation.y = 0.0
	camera.rotation.z = 0.0

# --- Knocked flying ---------------------------------------------------------------
#
# A long fall, a truck, a blast or a crane's grapple and he goes limp: he
# becomes a ragdoll (Ragdoll: body, head, arms and legs each a physics body,
# jointed), the camera pulls back to watch - shaking as he hits the ground -
# his hat flies off on a big hit, and once he has
# come to rest he gets up where he lies. The crusher is worse.

## Co-op, on the host: something happened to a guest's player that the
## guest's own game has to act out (thrown, crushed).
signal net_event(entry: Dictionary)

## Landing faster than this (m/s) knocks him over: about a twelve metre drop.
static var FALL_KNOCK_SPEED: float = Balance.num("player.fall_knock_speed", 16.0)
## A vehicle coming at him faster than this (m/s) sends him flying - its own
## speed at him; running into a parked one does nothing.
static var CAR_KNOCK_SPEED: float = Balance.num("player.car_knock_speed", 5.0)
## Seconds lying still before he gets up; the longest he stays down.
const TUMBLE_REST := 1.6
const TUMBLE_MOST := 12.0
## Seconds watching the crusher before he is back at base.
const CRUSHED_SECONDS := 4.5
## The tumbling body's middle, above his feet (a plain capsule, when there is
## no model to make a ragdoll of); a ragdoll's body is held at the hips.
const TUMBLE_HIPS := 0.9
const RAGDOLL_HIPS := 0.62
## A knock this hard (m/s) knocks his hat off.
const BIG_KNOCK := 13.0

## The body he is tumbling as, while knocked flying: the ragdoll's body, or a
## plain capsule.
var tumble: RigidBody3D = null
## The whole of him, limp.
var ragdoll: Ragdoll = null
var _hips: float = TUMBLE_HIPS
## Camera shake, 0..1, dying away.
var _shake: float = 0.0
var _last_v: Vector3 = Vector3.ZERO
var _impact_cd: float = 0.0
## Held up by a crane's grapple: he stays limp until it lets go.
var crane_hold: bool = false
var _tumble_t: float = 0.0
var _tumble_still: float = 0.0
var _crushed_t: float = -1.0
var _wriggle: float = 0.0
var _crushed_at: Vector3 = Vector3.ZERO

func knocked() -> bool:
	return tumble != null and is_instance_valid(tumble)

func crushed() -> bool:
	return _crushed_t >= 0.0

## Throws him limp, `push` added to however he was moving (m/s).
func knock(push: Vector3) -> void:
	if net_follow:
		# A guest: his body is on the guest's machine, which acts it out.
		net_event.emit({"t": "knock", "v": [push.x, push.y, push.z]})
		return
	if driving() or crushed() or (build_system != null and build_system.active):
		return
	if knocked():
		if ragdoll != null:
			ragdoll.shove(push, _spin_for(push))
		else:
			tumble.linear_velocity += push
			tumble.angular_velocity += _spin_for(push)
		_tumble_still = 0.0
		_drama(push)
		return
	_release_dragged()
	# Whatever was on the rack goes everywhere.
	for item in held:
		if is_instance_valid(item) and item.state != LooseItem.State.POOLED:
			item.set_state(LooseItem.State.FREE)
			item.linear_velocity = velocity + push * 0.6 + Vector3(randf_range(-2, 2), randf_range(1, 3), randf_range(-2, 2))
	if not held.is_empty():
		held.clear()
		carry_changed.emit(0, capacity_m3())
	var rd := Ragdoll.new()
	get_parent().add_child(rd)
	if avatar != null and avatar.model != null and rd.build(avatar.part, velocity, self):
		ragdoll = rd
		tumble = rd.torso
		_hips = RAGDOLL_HIPS
		rd.shove(push, _spin_for(push))
	else:
		rd.queue_free()
		ragdoll = null
		tumble = _capsule_body(push)
		_hips = TUMBLE_HIPS
	_tumble_t = 0.0
	_tumble_still = 0.0
	_last_v = tumble.linear_velocity
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	camera.top_level = true
	Sfx.play(&"whoosh", global_position, 0.0, 0.7)
	_drama(push)

## With no model to make a ragdoll of: one capsule for all of him.
func _capsule_body(push: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "Tumble"
	body.mass = 80.0
	body.collision_layer = Layers.PLAYER
	body.collision_mask = Layers.MASK_PLAYER | Layers.KERB
	body.continuous_cd = true
	body.angular_damp = 0.8
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.2
	body.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	cs.shape = cap
	body.add_child(cs)
	body.set_meta("player", self)
	get_parent().add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.UP, global_rotation.y), global_position + Vector3.UP * TUMBLE_HIPS)
	body.linear_velocity = velocity + push
	body.angular_velocity = _spin_for(push)
	return body

## The show: the camera shakes, and a big hit knocks his hat off.
func _drama(push: Vector3) -> void:
	var hard := push.length()
	_shake = maxf(_shake, clampf(hard / 18.0, 0.25, 1.0))
	if hard >= BIG_KNOCK and avatar != null:
		avatar.lose_hat(tumble.linear_velocity + push * 0.4 + Vector3.UP * 3.0)

## Hitting the ground: a thud, a puff of dust, the camera shaken.
func _impact(at: Vector3, strength: float) -> void:
	_impact_cd = 0.18
	_shake = maxf(_shake, clampf(strength / 16.0, 0.15, 1.0))
	Sfx.play(&"thud", at, clampf(strength * 0.6 - 6.0, -12.0, 4.0), randf_range(0.85, 1.1))
	var dust := Blast._burst(Color(0.55, 0.45, 0.33), false, int(clampf(strength * 2.0, 8.0, 30.0)), 2.5, 0.9, 0.14)
	dust.gravity = Vector3(0, 0.6, 0)
	var parent := get_parent()
	if parent == null:
		return
	parent.add_child(dust)
	dust.global_position = at + Vector3.DOWN * 0.3
	get_tree().create_timer(2.0).timeout.connect(dust.queue_free)

## A crane's grapple has hold of him (or lets go).
func set_held(on: bool, let_go_velocity: Vector3 = Vector3.ZERO) -> void:
	if not knocked():
		return
	if ragdoll != null:
		ragdoll.set_held(on)
	else:
		tumble.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		tumble.freeze = on
	if not on:
		tumble.linear_velocity = let_go_velocity

## How far below a grapple's jaws the held body hangs.
func hang_drop() -> float:
	return 0.72 if ragdoll != null else 0.85

## Puts the ragdoll (or capsule) away.
func _end_ragdoll(immediately: bool = false) -> void:
	if ragdoll != null and is_instance_valid(ragdoll):
		if immediately:
			ragdoll.free()
		else:
			ragdoll.queue_free()
	elif tumble != null and is_instance_valid(tumble):
		if immediately:
			tumble.free()
		else:
			tumble.queue_free()
	ragdoll = null
	tumble = null
	crane_hold = false
	if avatar != null:
		avatar.recover()

## Head over heels, harder the harder he was hit.
func _spin_for(push: Vector3) -> Vector3:
	var side := push.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	return side.normalized() * clampf(push.length() * 0.45, 1.5, 10.0) + Vector3(0, randf_range(-2, 2), 0)

func _tumble_step(delta: float) -> void:
	var b := tumble
	if b.global_position.y < -120.0:
		# Through the world: up he gets, down there, and the world's own
		# rescue brings him back.
		stand_up()
		return
	global_position = b.global_position - Vector3.UP * _hips
	velocity = b.linear_velocity
	_tumble_t += delta
	# A sudden stop is him hitting something.
	_impact_cd = maxf(0.0, _impact_cd - delta)
	var dv := (_last_v - b.linear_velocity).length()
	if dv > 5.0 and _impact_cd <= 0.0 and not b.freeze:
		_impact(b.global_position, dv)
	_last_v = b.linear_velocity
	if crane_hold:
		_tumble_still = 0.0
		# Hold jump to wriggle free of the grapple.
		_wriggle = _wriggle + delta if input.pressed("jump") else 0.0
		if _wriggle > 1.0:
			_wriggle = 0.0
			crane_hold = false
			set_held(false)
		return
	var moving := ragdoll.speed() if ragdoll != null else b.linear_velocity.length()
	if moving < 0.8 and b.angular_velocity.length() < 1.5:
		_tumble_still += delta
	else:
		_tumble_still = 0.0
	if (_tumble_still > TUMBLE_REST and _tumble_t > 1.2) or _tumble_t > TUMBLE_MOST:
		stand_up()

## Back on his feet where the body lies.
func stand_up() -> void:
	if not knocked():
		return
	var at := tumble.global_position
	var along := tumble.global_basis.y
	var yaw := atan2(-along.x, -along.z) if Vector2(along.x, along.z).length() > 0.3 else global_rotation.y
	var hips := _hips
	var skip := ragdoll.rids() if ragdoll != null else [tumble.get_rid()] as Array[RID]
	# Feet on whatever is under him (not on his own limbs).
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 3.0, Layers.MASK_PLAYER | Layers.KERB)
	q.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	_end_ragdoll()
	var feet: Vector3 = (hit.position as Vector3) + Vector3.UP * 0.05 if not hit.is_empty() else at - Vector3.UP * hips
	global_position = feet
	rotation = Vector3(0, yaw, 0)
	velocity = Vector3.ZERO
	collision_layer = Layers.PLAYER
	collision_mask = Layers.MASK_PLAYER
	_restore_camera()
	if avatar != null:
		avatar.restore_hat()

func _restore_camera() -> void:
	camera.top_level = false
	camera.transform = Transform3D(Basis(), Vector3(0, 1.65, 0))

## While he is down: the camera stands off and watches him (the mouse still
## swings it round).
func _update_down_camera(delta: float) -> void:
	var look: Vector3 = tumble.global_position + Vector3.UP * (0.35 if ragdoll != null else 0.0) if knocked() else _crushed_at
	var yaw := global_rotation.y
	var back := Basis(Vector3.UP, yaw).z
	# Further back the faster he is going, so a big throw stays in frame.
	var far := 4.5 + clampf(tumble.linear_velocity.length() * 0.15, 0.0, 3.5) if knocked() else 7.0
	var want := look + back * far + Vector3.UP * (2.2 if knocked() else 4.0)
	if knocked():
		# Pulled in rather than behind a wall. (Over the crusher it just stands
		# up and back: the machine's own walls would pull it into the hopper.)
		var skip: Array[RID] = ragdoll.rids() if ragdoll != null else [tumble.get_rid()] as Array[RID]
		var clear := _camera_clearance(look + Vector3.UP * 0.5, (want - look - Vector3.UP * 0.5).normalized(),
			want.distance_to(look + Vector3.UP * 0.5), skip)
		want = look + Vector3.UP * 0.5 + (want - look - Vector3.UP * 0.5).normalized() * clear
	camera.global_position = camera.global_position.lerp(want, 1.0 - exp(-8.0 * delta))
	if camera.global_position.distance_to(look) > 0.2:
		camera.look_at(look, Vector3.UP)
	if _shake > 0.0:
		camera.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.22 * _shake * _shake
		_shake = maxf(0.0, _shake - delta * 2.5)

## A truck coming at him.
func _check_vehicles() -> void:
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.6
	cap.height = 2.0
	q.shape = cap
	q.transform = Transform3D(Basis(), global_position + Vector3.UP * 0.95)
	q.collision_mask = Layers.VEHICLE
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 4):
		var n: Node = hit.collider
		for i in 3:
			if n == null or n is Hauler:
				break
			n = n.get_parent()
		var car := n as Hauler
		if car == null or car == vehicle:
			continue
		var to_me := global_position - car.global_position
		to_me.y = 0.0
		if to_me.length_squared() < 0.0001:
			continue
		var rel := car.linear_velocity - velocity
		var closing := rel.dot(to_me.normalized())
		# The car has to be the one doing the hitting: coming at him fast
		# itself, not him running into it standing still (or rolling along
		# slower than he runs). And the two have to be closing, so riding on
		# a moving truck's bed is not being run over by it.
		var driving_at := car.linear_velocity.dot(to_me.normalized())
		if closing > CAR_KNOCK_SPEED and driving_at > CAR_KNOCK_SPEED:
			knock(rel * 1.1 + to_me.normalized() * 2.0 + Vector3.UP * (3.0 + closing * 0.35))
			return

## Caught by the crusher's wheels: drawn down into them over `seconds`,
## slowly at first, shaking, with no way out; then the machine puts him
## through (crush).
var _grind_t: float = -1.0
var _grind_total: float = 1.0
var _grind_from: Vector3
var _grind_to: Vector3

func grinding() -> bool:
	return _grind_t >= 0.0

func grind(into: Vector3, seconds: float) -> void:
	if grinding() or crushed():
		return
	if knocked():
		var at := tumble.global_position
		_end_ragdoll()
		global_position = at
	_release_dragged()
	_grind_total = maxf(0.2, seconds)
	_grind_t = 0.0
	_grind_from = global_position
	# Feet first, the wheels at his waist by the end.
	_grind_to = into - Vector3(0, 1.1, 0)
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	if net_follow:
		net_event.emit({"t": "grind", "x": [into.x, into.y, into.z], "s": seconds})
	interacted.emit("the crusher's got you!")

func _grind_step(delta: float) -> void:
	velocity = Vector3.ZERO
	_grind_t += delta
	var f := clampf(_grind_t / _grind_total, 0.0, 1.0)
	var p := _grind_from.lerp(_grind_to, f * f)
	p += Vector3(sin(_grind_t * 23.0), 0.0, cos(_grind_t * 19.0)) * 0.04 * (0.3 + f)
	global_position = p
	_shake = maxf(_shake, 0.45 + 0.5 * f)
	if f >= 1.0:
		_grind_t = -1.0

## Into the crusher. The meat is the machine's to make; here he is gone for a
## moment, the camera on the machine, then back at base.
func crush(at: Vector3) -> void:
	if crushed():
		return
	if net_follow:
		# A guest: his game shows it; here his body is put away the same, and
		# he is sent back to base from here when it is over.
		net_event.emit({"t": "crush", "x": [at.x, at.y, at.z]})
	if knocked():
		_end_ragdoll()
	_grind_t = -1.0
	_release_dragged()
	_crushed_t = CRUSHED_SECONDS
	_crushed_at = at
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	if avatar != null:
		avatar.visible = false
	camera.top_level = true
	camera.global_position = at + Vector3(0, 4.0, 7.0)
	interacted.emit("you went through the crusher")

func _crushed_step(delta: float) -> void:
	velocity = Vector3.ZERO
	_crushed_t -= delta
	if _crushed_t > 0.0:
		return
	_crushed_t = -1.0
	# Back at base (or, with no base to go to, set down clear of the machine).
	var w := get_parent()
	if w != null and w.has_method("return_to_base"):
		w.call("return_to_base", self)
	else:
		global_position = _crushed_at + Vector3(0, 0, 8)
	collision_layer = Layers.PLAYER
	collision_mask = Layers.MASK_PLAYER
	if avatar != null:
		avatar.visible = true
		avatar.restore_hat()
	_restore_camera()

## [E] on a stick of TNT: light it.
func _light_tnt(item: LooseItem) -> String:
	if Blast.lit(item):
		return "it is already lit - throw it!"
	Blast.light(item, manager)
	return "fuse lit - %.0f seconds! pick it up and throw it" % Blast.FUSE_SECONDS

## Tests: puts away a tumbling body without the getting-up.
func free_tumble_for_test() -> void:
	_end_ragdoll(true)
	if avatar != null:
		avatar.restore_hat()
