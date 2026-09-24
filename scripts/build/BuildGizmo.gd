class_name BuildGizmo
extends Node3D

## The handles drawn on a selected building in build mode.
##
##   Move    blue diamonds on each face: drag one to slide the building that
##           way, a cell at a time (up and down in quarter metres)
##   Scale   blue diamonds on each face: drag one to stretch or shrink that
##           side, a cell at a time, for the things that can be resized
##   Rotate  a red, green and blue ring round each axis with two balls on it:
##           drag a ball round its ring to turn the building a quarter at a time
##
## Everything here draws over the world, so a handle is never hidden inside
## the building it belongs to. Handles are picked on screen, by how close the
## cursor is to where the handle is drawn.

enum Mode { MOVE, SCALE, ROTATE }

const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const AXIS_COLORS := [Color(0.95, 0.25, 0.25), Color(0.3, 0.9, 0.35), Color(0.25, 0.5, 1.0)]
const HANDLE_COLOR := Color(0.2, 0.55, 1.0)
const PICK_PIXELS := 24.0

var mode: Mode = Mode.MOVE
## {node, axis (0-2), sign (+1/-1), point (world)}
var handles: Array[Dictionary] = []
var centre: Vector3 = Vector3.ZERO
var half: Vector3 = Vector3.ONE

var _box: MeshInstance3D
var _box_material: StandardMaterial3D
var _handle_material: StandardMaterial3D
var _ring_materials: Array[StandardMaterial3D] = []
var _rings: MeshInstance3D
var _hover: int = -1

func _ready() -> void:
	_box_material = _overlay(Color(0.25, 0.6, 1.0, 0.22))
	_box = MeshInstance3D.new()
	_box.mesh = BoxMesh.new()
	_box.material_override = _box_material
	add_child(_box)
	_handle_material = _overlay(HANDLE_COLOR)
	for c in AXIS_COLORS:
		_ring_materials.append(_overlay(c))
	_rings = MeshInstance3D.new()
	add_child(_rings)
	visible = false

static func _overlay(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	m.render_priority = 10
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

## Wraps a box (world centre and half extents) in handles for the mode.
func show_on(p_centre: Vector3, p_half: Vector3, p_mode: Mode) -> void:
	centre = p_centre
	half = p_half
	mode = p_mode
	visible = true
	global_position = Vector3.ZERO
	(_box.mesh as BoxMesh).size = half * 2.0 + Vector3.ONE * 0.06
	_box.global_position = centre
	for h in handles:
		(h.node as Node).queue_free()
	handles.clear()
	_rings.mesh = null
	match mode:
		Mode.MOVE, Mode.SCALE:
			for axis in 3:
				for sign in [-1.0, 1.0]:
					var at: Vector3 = centre + (AXES[axis] as Vector3) * (half[axis] + 0.55) * sign
					handles.append({"node": _diamond(at, mode == Mode.SCALE), "axis": axis, "sign": sign, "point": at})
		Mode.ROTATE:
			var radius := half.length() + 0.6
			var im := ImmediateMesh.new()
			for axis in 3:
				im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _ring_materials[axis])
				var u: Vector3 = AXES[(axis + 1) % 3]
				var v: Vector3 = AXES[(axis + 2) % 3]
				for k in 49:
					var a := TAU * float(k) / 48.0
					im.surface_add_vertex(centre + (u * cos(a) + v * sin(a)) * radius)
				im.surface_end()
				for sign in [-1.0, 1.0]:
					var at: Vector3 = centre + (u * 0.7071 + v * 0.7071) * radius * sign
					handles.append({"node": _ball(at, _ring_materials[axis]), "axis": axis, "sign": sign, "point": at})
			_rings.mesh = im
	_hover = -1

func hide_all() -> void:
	visible = false
	for h in handles:
		(h.node as Node).queue_free()
	handles.clear()

func _diamond(at: Vector3, square: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * (0.32 if square else 0.36)
	mi.mesh = bm
	mi.material_override = _handle_material
	add_child(mi)
	mi.global_transform = Transform3D(Basis() if square else
		Basis.from_euler(Vector3(0.6155, PI * 0.25, 0)), at)
	return mi

func _ball(at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.24
	sm.height = 0.48
	sm.radial_segments = 10
	sm.rings = 5
	mi.mesh = sm
	mi.material_override = mat
	add_child(mi)
	mi.global_position = at
	return mi

## The handle drawn nearest the cursor, if it is close enough; -1 otherwise.
func pick(camera: Camera3D, mouse: Vector2) -> int:
	var best := -1
	var best_d := PICK_PIXELS
	for i in handles.size():
		var p: Vector3 = handles[i].point
		if camera.is_position_behind(p):
			continue
		var d := camera.unproject_position(p).distance_to(mouse)
		if d < best_d:
			best_d = d
			best = i
	return best

## Lights up the handle under the cursor.
func hover(index: int) -> void:
	if index == _hover:
		return
	if _hover >= 0 and _hover < handles.size():
		(handles[_hover].node as Node3D).scale = Vector3.ONE
	_hover = index
	if index >= 0 and index < handles.size():
		(handles[index].node as Node3D).scale = Vector3.ONE * 1.35

# --- Drag maths ------------------------------------------------------------

## How far along `axis` (a unit vector through `origin`) a camera ray reaches
## at its closest approach: the distance a handle has been dragged.
static func along_axis(origin: Vector3, axis: Vector3, ray_from: Vector3, ray_dir: Vector3) -> float:
	var w := origin - ray_from
	var b := axis.dot(ray_dir)
	var denom := 1.0 - b * b
	if absf(denom) < 0.0001:
		return 0.0
	return (b * ray_dir.dot(w) - axis.dot(w)) / denom

## The angle (radians, about `axis`) from `start` to where the ray crosses the
## plane through `centre` square to that axis.
static func angle_about(centre: Vector3, axis: Vector3, start: Vector3, ray_from: Vector3,
		ray_dir: Vector3) -> float:
	var plane := Plane(axis, centre)
	var hit: Variant = plane.intersects_ray(ray_from, ray_dir)
	if hit == null:
		return 0.0
	var a := start - centre
	var b := (hit as Vector3) - centre
	a -= axis * a.dot(axis)
	b -= axis * b.dot(axis)
	if a.length() < 0.001 or b.length() < 0.001:
		return 0.0
	return atan2(axis.dot(a.cross(b)), a.dot(b))
