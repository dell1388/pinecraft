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
var _ghost_label: Label3D
## The building itself, see-through, where it would go and turned the way it
## would face; rebuilt when the choice (or its size or tier) changes.
var _preview: Node3D
var _preview_key: String = ""
var _preview_ok: StandardMaterial3D
var _preview_bad: StandardMaterial3D
var _preview_valid: bool = true
var _stowed: Transform3D
var _flying: bool = false

## Editing a placed building: which one (index into plot.placed, -1 for
## none), what the handles do, and the drag under way.
var selected: int = -1
var edit_mode: BuildGizmo.Mode = BuildGizmo.Mode.MOVE
var edit_error: String = ""
var _gizmo: BuildGizmo
var _drag: Dictionary = {}
## Where a handle drag has got to on screen: it starts at the crosshair and
## follows the mouse from there.
var _cursor: Vector2 = Vector2.ZERO

func setup(p_plot: Plot, p_camera: Camera3D, p_player: Node3D) -> void:
	plot = p_plot
	camera = p_camera
	player = p_player
	refresh_palette()
	# Building the last copy of something, or taking one down, changes what
	# there is to build.
	PlayerState.inventory_changed.connect(refresh_palette)

func _ready() -> void:
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.albedo_color = Color(0.3, 1.0, 0.4, 0.4)
	_preview_ok = _preview_material(Color(0.85, 1.0, 0.85, 0.62))
	_preview_bad = _preview_material(Color(1.0, 0.45, 0.4, 0.62))
	_ghost = MeshInstance3D.new()
	_ghost.mesh = BoxMesh.new()
	_ghost.material_override = _ghost_material
	_ghost.visible = false
	add_child(_ghost)
	# What you are about to place, named, because a translucent box is not a
	# description of anything.
	_ghost_label = Nameplate.attach(_ghost, "", 0.0)
	_gizmo = BuildGizmo.new()
	_gizmo.top_level = true
	add_child(_gizmo)
	set_process(true)

func refresh_palette() -> void:
	var was := current()
	palette = PlayerState.available_buildings()
	index = clampi(index, 0, maxi(0, palette.size() - 1))
	# Stay on the same thing if it is still there.
	if was != null:
		for i in palette.size():
			if palette[i].id == was.id and palette[i].tier == was.tier:
				index = i
				break
	selection_changed.emit(current())

static func _preview_material(tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = tint
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m

## Swaps the see-through model for `def`'s, if it is not already showing.
func _ensure_preview(def: BuildingDef) -> void:
	var key := "%s|%s|%d" % [def.id, def.size, def.tier]
	if key == _preview_key and _preview != null:
		return
	if _preview != null:
		_preview.queue_free()
		_preview = null
	_preview_key = key
	_preview = plot.preview_model(def)
	if _preview == null:
		return
	_preview.top_level = true
	# Which way is its front: an arrow on the floor out of its -Z side, the
	# way belts run and machines take things in and put them out.
	var fp := Vector3(def.size) * Plot.CELL
	var arrow := MeshInstance3D.new()
	var g := Greeble.new()
	var ahead := -fp.z * 0.5 - 0.35
	g.box(Vector3(0.12, 0.03, 0.5), Transform3D(Basis(), Vector3(0, 0.03, ahead + 0.1)), Color(1.0, 0.85, 0.3))
	for side in [-1.0, 1.0]:
		g.box(Vector3(0.1, 0.03, 0.34), Transform3D(Basis(Vector3.UP, side * 0.6), Vector3(side * 0.09, 0.03, ahead - 0.12)), Color(1.0, 0.85, 0.3))
	arrow.mesh = g.commit()
	arrow.name = "FrontArrow"
	_preview.add_child(arrow)
	add_child(_preview)
	_preview_valid = not _preview_valid
	_tint_preview(not _preview_valid)

func _hide_ghost() -> void:
	_ghost.visible = false
	if _preview != null:
		_preview.visible = false

func _tint_preview(valid: bool) -> void:
	if _preview == null or valid == _preview_valid:
		return
	_preview_valid = valid
	for c in _preview.get_children():
		var mi := c as MeshInstance3D
		if mi != null:
			mi.material_override = _preview_ok if valid else _preview_bad

func current() -> BuildingDef:
	if palette.is_empty():
		return null
	return palette[clampi(index, 0, palette.size() - 1)]

func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	_ghost.visible = value
	if not value and _preview != null:
		_preview.visible = false
	if plot != null:
		plot.show_grid(value)
	if value:
		refresh_palette()
		_enter_freecam()
	else:
		deselect()
		_leave_freecam()
	mode_changed.emit(active)

## Spec: build mode puts the player into a freecam - WASD and the mouse fly it,
## Shift and Control work elevation.
func _enter_freecam() -> void:
	if camera == null or _flying:
		return
	_stowed = camera.transform
	# Detached from the player, so flying the camera does not walk the body.
	var start := camera.global_transform
	camera.top_level = true
	# Up a few metres and tipped down at the ground, so the first thing you see
	# is where the building will go rather than the horizon.
	var e := start.basis.get_euler()
	camera.global_transform = Transform3D(
		Basis.from_euler(Vector3(minf(e.x, deg_to_rad(-32.0)), e.y, 0.0)),
		start.origin + Vector3(0, 5.0, 0))
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

## The build bar shows the palette a page at a time, so the number keys keep
## meaning the same slots while you scroll within a page.
const BAR_SLOTS := 7

func bar_first() -> int:
	return (index / BAR_SLOTS) * BAR_SLOTS

## Number key 1-7: a slot on the page the selection is on.
func select_slot(slot: int) -> void:
	if slot >= 0 and slot < BAR_SLOTS:
		select_index(bar_first() + slot)

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
	if editing():
		_hide_ghost()
		if selected >= plot.placed.size():
			deselect()
		elif _drag.is_empty():
			_gizmo.hover(_gizmo.pick(camera, _centre()))
		return
	_update_ghost()

# --- Editing placed buildings ----------------------------------------------

func editing() -> bool:
	return active and selected >= 0

## Spec: F picks the building under the crosshair for editing; F again lets
## it go. While editing, the crosshair picks a handle and the camera still
## flies and looks about as usual.
func toggle_select() -> void:
	if editing():
		deselect()
		return
	var point: Variant = _aim_point()
	if point == null:
		return
	select_building(plot.index_at_world(point))

func select_building(index: int) -> void:
	if index < 0 or index >= plot.placed.size():
		deselect()
		return
	selected = index
	edit_error = ""
	_refresh_gizmo()

func deselect() -> void:
	selected = -1
	_drag = {}
	_gizmo.hide_all()
	if active and player != null and player.has_method("capture_mouse"):
		player.call("capture_mouse", true)

func set_edit_mode(mode: int) -> void:
	edit_mode = mode as BuildGizmo.Mode
	_refresh_gizmo()

func selected_record() -> Dictionary:
	return plot.placed[selected] if editing() else {}

## The world box a record occupies.
func _record_box(rec: Dictionary) -> Array:
	var def: BuildingDef = rec.def
	var fp := Plot.oriented_size(def.size, rec.rot)
	var size := Vector3(float(fp.x), float(fp.y), float(fp.z)) * Plot.CELL
	var base := plot.cell_to_world(rec.cell, def.size, rec.rot)
	return [base + Vector3(0, size.y * 0.5 + float(rec.get("lift", 0.0)), 0), size * 0.5]

func _refresh_gizmo() -> void:
	if not editing():
		_gizmo.hide_all()
		return
	var box := _record_box(selected_record())
	var mode := edit_mode
	if mode == BuildGizmo.Mode.SCALE and Plot.size_limits(selected_record().def).is_empty():
		edit_error = "%s has a fixed size" % (selected_record().def as BuildingDef).display_name
	_gizmo.show_on(box[0], box[1], mode)

## Mouse input while editing. Returns true when it was used. The mouse stays
## captured: the crosshair picks a handle, and while a handle is held the
## mouse drags it (the view holds still) - otherwise the mouse looks about.
func edit_input(event: InputEvent) -> bool:
	if not editing():
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_cursor = _centre()
				_press(_cursor)
			else:
				_drag = {}
				_refresh_gizmo()
			return true
		return false
	if event is InputEventMouseMotion and not _drag.is_empty():
		var mm := event as InputEventMouseMotion
		var view := get_viewport().get_visible_rect().size
		_cursor = (_cursor + mm.relative).clamp(Vector2.ZERO, view)
		_drag_to(_cursor)
		return true
	return false

## The crosshair, in screen space.
func _centre() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5

func _ray(mouse: Vector2) -> Array:
	return [camera.project_ray_origin(mouse), camera.project_ray_normal(mouse)]

func _press(mouse: Vector2) -> void:
	var handle := _gizmo.pick(camera, mouse)
	if handle >= 0:
		var rec := selected_record()
		var ray := _ray(mouse)
		var h: Dictionary = _gizmo.handles[handle]
		var axis: Vector3 = BuildGizmo.AXES[h.axis]
		_drag = {"handle": h, "cell": rec.cell, "rot": rec.rot, "size": (rec.def as BuildingDef).size,
			"lift": float(rec.get("lift", 0.0)), "centre": _gizmo.centre,
			"t0": BuildGizmo.along_axis(h.point, axis, ray[0], ray[1]), "steps": 0}
		return
	# Clicked off the handles: pick another building, or let go.
	var ray2 := _ray(mouse)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(ray2[0], ray2[0] + ray2[1] * REACH, Layers.WORLD | Layers.MACHINE)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		deselect()
		return
	var index := plot.index_at_world(hit.position)
	if index < 0:
		deselect()
	else:
		select_building(index)

## Turns a drag into whole steps and applies each new step as it is reached.
func _drag_to(mouse: Vector2) -> void:
	var d := _drag
	var h: Dictionary = d.handle
	var axis_i: int = h.axis
	var axis: Vector3 = BuildGizmo.AXES[axis_i]
	var ray := _ray(mouse)
	var steps := 0
	var cell: Vector2i = d.cell
	var rot: Vector3i = d.rot
	var size: Vector3i = d.size
	var lift: float = d.lift
	match edit_mode:
		BuildGizmo.Mode.MOVE:
			var moved: float = BuildGizmo.along_axis(h.point, axis, ray[0], ray[1]) - float(d.t0)
			if axis_i == 1:
				lift = maxf(0.0, snappedf(lift + moved, 0.25))
				steps = int(round(lift * 4.0))
			else:
				steps = int(round(moved / Plot.CELL))
				cell += Vector2i(steps, 0) if axis_i == 0 else Vector2i(0, steps)
		BuildGizmo.Mode.SCALE:
			var limits := Plot.size_limits(selected_record().def)
			if limits.is_empty():
				return
			var grow: float = (BuildGizmo.along_axis(h.point, axis, ray[0], ray[1]) - float(d.t0)) * float(h.sign)
			steps = int(round(grow / Plot.CELL))
			# Which of the building's own axes lies along this world axis.
			var perm := Plot.oriented_size(Vector3i(0, 1, 2) + Vector3i.ONE, rot) - Vector3i.ONE
			var own: int = perm[axis_i]
			var new_size := size
			new_size[own] = clampi(size[own] + steps, (limits[0] as Vector3i)[own], (limits[1] as Vector3i)[own])
			steps = new_size[own] - size[own]
			size = new_size
			# Grown from the minus side, the building's corner cell moves too.
			if h.sign < 0.0 and axis_i != 1:
				cell += Vector2i(-steps, 0) if axis_i == 0 else Vector2i(0, -steps)
		BuildGizmo.Mode.ROTATE:
			var start: Vector3 = h.point
			var angle := BuildGizmo.angle_about(d.centre, axis, start, ray[0], ray[1])
			steps = int(round(angle / (PI * 0.5)))
			var turn := Vector3i.ZERO
			turn[axis_i] = steps
			rot = Vector3i(posmod(rot.x + turn.x, 4), posmod(rot.y + turn.y, 4), posmod(rot.z + turn.z, 4))
			# Keep it turning about its middle rather than its corner.
			var def: BuildingDef = selected_record().def
			var old_fp := Plot.oriented_size(def.size, d.rot)
			var new_fp := Plot.oriented_size(def.size, rot)
			cell += Vector2i((old_fp.x - new_fp.x) / 2, (old_fp.z - new_fp.z) / 2)
	if steps == int(d.steps):
		return
	d.steps = steps
	var rec := selected_record()
	if rec.cell == cell and rec.rot == rot and (rec.def as BuildingDef).size == size \
			and is_equal_approx(float(rec.get("lift", 0.0)), lift):
		return
	edit_error = plot.edit(selected, cell, rot, size, lift)
	_refresh_gizmo_box()

## Moves the selection box with the building without rebuilding the handles
## being dragged.
func _refresh_gizmo_box() -> void:
	var box := _record_box(selected_record())
	_gizmo._box.global_position = box[0]
	(_gizmo._box.mesh as BoxMesh).size = (box[1] as Vector3) * 2.0 + Vector3.ONE * 0.06

func remove_selected() -> void:
	if not editing():
		return
	var node: Node3D = selected_record().node
	deselect()
	plot.remove(node)

func edit_hint() -> String:
	var names := ["(1) Move", "(2) Scale", "(3) Rotate"]
	var parts: Array[String] = []
	for i in 3:
		parts.append(("[%s]" % names[i]) if i == int(edit_mode) else names[i])
	return "   ".join(parts) + "      aim at a handle, hold LMB and move the mouse   ·   [Del] remove   ·   [F] done"

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
		_hide_ghost()
		last_error = "no target"
		return
	var world_point: Vector3 = point
	var fp := Plot.oriented_size(def.size, rot)
	var cursor := plot.world_to_cell(world_point)
	target_cell = Vector2i(cursor.x - fp.x / 2, cursor.y - fp.z / 2)
	has_target = true

	var size := Vector3(float(fp.x), float(def.size.y), float(fp.z)) * Plot.CELL
	var base := plot.cell_to_world(target_cell, def.size, rot)
	(_ghost.mesh as BoxMesh).size = size
	_ghost.global_position = base + Vector3(0, size.y * 0.5, 0)
	_ghost.rotation = Vector3.ZERO
	_ghost.visible = true
	_ghost_label.text = def.display_name
	_ghost_label.position = Vector3(0, size.y * 0.5 + 0.7, 0)

	last_error = plot.placement_error(def, target_cell, rot)
	# The box is only the footprint now, faint; the model shows the building.
	_ghost_material.albedo_color = Color(0.3, 1.0, 0.4, 0.10) if last_error == "" \
		else Color(1.0, 0.3, 0.25, 0.16)
	_ensure_preview(def)
	if _preview != null:
		_preview.visible = true
		_preview.global_transform = Transform3D(plot.global_transform.basis * Plot.orientation_basis(rot), base)
		_tint_preview(last_error == "")

func try_place() -> bool:
	if not active or not has_target or editing():
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
	var base := "%s  %s  [%d/%d]" % [def.display_name, PlayerState.build_note(def), index + 1, palette.size()]
	if last_error != "":
		return base + "  -- " + last_error
	return base
