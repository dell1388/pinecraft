class_name WinchReticle
extends Node3D

## Where the winch hook would go: a ring laid on whatever the player is aiming
## at, and a faint line from the truck's fairlead to it. Green in reach,
## red past the end of the line. Shown only while a winch is to hand and not
## already hooked on.

const IN_REACH := Color(0.35, 1.0, 0.45)
const TOO_FAR := Color(1.0, 0.3, 0.25)

## The rig whose winch is being aimed, if it can reach the point.
var rig: VehicleRig = null
var in_reach: bool = false

var _ring: MeshInstance3D
var _dot: MeshInstance3D
var _line: MeshInstance3D
var _mat: StandardMaterial3D

func _ready() -> void:
	top_level = true
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.no_depth_test = true
	_mat.render_priority = 10
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.42
	torus.rings = 24
	torus.ring_segments = 6
	_ring.mesh = torus
	_ring.material_override = _mat
	add_child(_ring)
	_dot = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.09
	dot.height = 0.18
	_dot.mesh = dot
	_dot.material_override = _mat
	add_child(_dot)
	_line = MeshInstance3D.new()
	var line := CylinderMesh.new()
	line.top_radius = 0.015
	line.bottom_radius = 0.015
	line.height = 1.0
	line.radial_segments = 4
	_line.mesh = line
	var line_mat := _mat.duplicate() as StandardMaterial3D
	line_mat.no_depth_test = false
	_line.material_override = line_mat
	add_child(_line)
	visible = false

## Points the reticle at `hit` (a ray result) for `r`, or hides it.
func show_for(r: VehicleRig, hit: Dictionary) -> void:
	if r == null or r.anchored or hit.is_empty():
		hide_reticle()
		return
	rig = r
	var point: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	var from := r.fairlead()
	in_reach = from.distance_to(point) <= r.reach
	var c := IN_REACH if in_reach else TOO_FAR
	c.a = 0.9
	_mat.albedo_color = c
	var lm := _line.material_override as StandardMaterial3D
	lm.albedo_color = Color(c.r, c.g, c.b, 0.45)
	# The ring lies flat on the surface hit.
	var up := normal.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	_ring.global_transform = Transform3D(Basis(side, up, side.cross(up)), point + up * 0.03)
	_dot.global_position = point + up * 0.03
	var span := point - from
	var n := span.length()
	if n > 0.05:
		var y := span / n
		var x := y.cross(Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
		_line.global_transform = Transform3D(Basis(x, span, x.cross(y)), from + span * 0.5)
		_line.visible = true
	else:
		_line.visible = false
	visible = true

func hide_reticle() -> void:
	rig = null
	in_reach = false
	visible = false
