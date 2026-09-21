class_name BuildSystem
extends Node3D

## Build mode: a grid-snapped ghost that follows the player's aim, with
## placement validity resolved by the plot itself.

signal mode_changed(active: bool)
signal selection_changed(def: BuildingDef)

var plot: Plot
var camera: Camera3D
var player: Node3D

var active: bool = false
## Quarter turns about each axis. Spec binds Z, X and C to the three of them.
var rot: Vector3i = Vector3i.ZERO
var yaw: int = 0
var index: int = 0
var palette: Array[BuildingDef] = []
var last_error: String = ""
var target_cell: Vector2i = Vector2i.ZERO
var has_target: bool = false

const REACH := 40.0
## Spec: build mode is a freecam. These are how fast it flies.
const FLY_SPEED := 14.0
const FLY_SPRINT := 32.0

var _ghost: MeshInstance3D
var _ghost_material: StandardMaterial3D
## Where the camera was before build mode took it, so leaving puts it back.
var _stowed: Transform3D
var _flying: bool = false

func setup(p_plot: Plot, p_camera: Camera3D, p_player: Node3D) -> void:
	plot = p_plot
	camera = p_camera
	player = p_player
	refresh_palette()

func _ready() -> void:
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.albedo_color = Color(0.3, 1.0, 0.4, 0.4)
	_ghost = MeshInstance3D.new()
	_ghost.mesh = BoxMesh.new()
	_ghost.material_override = _ghost_material
	_ghost.visible = false
	add_child(_ghost)
	set_process(true)

func refresh_palette() -> void:
	palette = PlayerState.available_buildings()
	index = clampi(index, 0, maxi(0, palette.size() - 1))
	selection_changed.emit(current())

func current() -> BuildingDef:
	if palette.is_empty():
		return null
	return palette[clampi(index, 0, palette.size() - 1)]

func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	_ghost.visible = value
	if value:
		refresh_palette()
		_enter_freecam()
	else:
		_leave_freecam()
	mode_changed.emit(active)

## Spec: build mode puts the player into a freecam - WASD and the mouse fly it,
## Shift and Control work elevation.
func _enter_freecam() -> void:
	if camera == null or _flying:
		return
	_stowed = camera.transform
	# Detached from the player, so flying the camera does not walk the body.
	camera.top_level = true
	camera.global_transform = camera.global_transform
	_flying = true

func _leave_freecam() -> void:
	if camera == null or not _flying:
		return
	camera.top_level = false
	camera.transform = _stowed
	_flying = false

func _fly(delta: float) -> void:
	if not _flying:
		return
	var input := Vector3(
		Input.get_axis("move_left", "move_right"), 0.0,
		Input.get_axis("move_forward", "move_back"))
	var lift := 0.0
	if Input.is_action_pressed("sprint"):
		lift += 1.0
	if Input.is_action_pressed("lower"):
		lift -= 1.0
	var speed: float = FLY_SPRINT if Input.is_action_pressed("sprint") and lift <= 0.0 else FLY_SPEED
	var basis := camera.global_transform.basis
	var move := (basis * input) + Vector3.UP * lift
	if move.length_squared() > 0.0001:
		camera.global_position += move.normalized() * speed * delta

func toggle() -> void:
	set_active(not active)

func cycle(step: int) -> void:
	if palette.is_empty():
		return
	index = wrapi(index + step, 0, palette.size())
	selection_changed.emit(current())

func select_index(i: int) -> void:
	if i < 0 or i >= palette.size():
		return
	index = i
	selection_changed.emit(current())

## Spec: Z, X and C each control an axis of rotation.
func rotate_axis(axis: int, step: int = 1) -> void:
	match axis:
		0: rot.x = wrapi(rot.x + step, 0, 4)
		1: rot.y = wrapi(rot.y + step, 0, 4)
		_: rot.z = wrapi(rot.z + step, 0, 4)
	yaw = rot.y

func rotate_ghost() -> void:
	rotate_axis(1)

func _process(delta: float) -> void:
	if not active or camera == null or plot == null:
		return
	_fly(delta)
	_update_ghost()

## Aim ray against the world layer, then snap the footprint so it is centred on
## the cell under the crosshair.
func _aim_point() -> Variant:
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * REACH
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD | Layers.MACHINE)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		# Fall back to the ground plane so the ghost still tracks over open space.
		var dir := -camera.global_transform.basis.z
		if dir.y >= -0.05:
			return null
		var t: float = (plot.global_position.y - from.y) / dir.y
		if t < 0.0 or t > REACH:
			return null
		return from + dir * t
	return hit.position

func _update_ghost() -> void:
	var def := current()
	var point: Variant = _aim_point()
	if def == null or point == null:
		has_target = false
		_ghost.visible = false
		last_error = "no target"
		return
	var world_point: Vector3 = point
	var fp := Plot.oriented_size(def.size, rot)
	var cursor := plot.world_to_cell(world_point)
	target_cell = Vector2i(cursor.x - fp.x / 2, cursor.y - fp.z / 2)
	has_target = true

	var size := Vector3(float(fp.x), float(def.size.y), float(fp.z)) * Plot.CELL
	(_ghost.mesh as BoxMesh).size = size
	_ghost.global_position = plot.cell_to_world(target_cell, def.size, rot) + Vector3(0, size.y * 0.5, 0)
	_ghost.rotation = Vector3.ZERO
	_ghost.visible = true

	last_error = plot.placement_error(def, target_cell, rot)
	_ghost_material.albedo_color = Color(0.3, 1.0, 0.4, 0.35) if last_error == "" \
		else Color(1.0, 0.3, 0.25, 0.35)

func try_place() -> bool:
	if not active or not has_target:
		return false
	var def := current()
	if def == null:
		return false
	var node := plot.place(def, target_cell, rot)
	return node != null

func try_remove() -> bool:
	if not active:
		return false
	var point: Variant = _aim_point()
	if point == null:
		return false
	return plot.remove_at_world(point)

func status_line() -> String:
	var def := current()
	if def == null:
		return "no buildings unlocked"
	var base := "%s  $%d  [%d/%d]" % [def.display_name, def.cost, index + 1, palette.size()]
	if last_error != "":
		return base + "  -- " + last_error
	return base
