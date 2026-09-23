class_name Greeble
extends RefCounted

## Detail for models, built as one merged mesh.
##
## Every model used to be a handful of BoxMeshes, each with its own material:
## plain, and a draw call apiece. This builds the same kind of shapes - boxes,
## prisms, wedges - plus the small stuff that makes a box read as a machine
## (bolts, plates, vents, stripes, frames, pipes) into a single flat-shaded mesh
## coloured per vertex. One mesh, one shared material, however busy the model.
##
## Emissive parts (lamps, furnace mouths, crystals) go in a second surface
## with a glowing material, so a model is still one MeshInstance.
##
## Faces are wound by an outward hint rather than by bookkeeping: each quad is
## flipped if its normal points the wrong way, so nothing here can be built
## inside-out.

var _solid: SurfaceTool
var _glow: SurfaceTool
var _solid_count: int = 0
var _glow_count: int = 0

static var _solid_material: StandardMaterial3D
static var _glow_material: ShaderMaterial

func _init() -> void:
	_solid = SurfaceTool.new()
	_solid.begin(Mesh.PRIMITIVE_TRIANGLES)
	_glow = SurfaceTool.new()
	_glow.begin(Mesh.PRIMITIVE_TRIANGLES)

static func solid_material() -> StandardMaterial3D:
	if _solid_material == null:
		_solid_material = StandardMaterial3D.new()
		_solid_material.vertex_color_use_as_albedo = true
		_solid_material.roughness = 0.82
	return _solid_material

static func glow_material() -> ShaderMaterial:
	if _glow_material == null:
		var shader := Shader.new()
		shader.code = """
shader_type spatial;
void fragment() {
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * 2.2;
	ROUGHNESS = 0.4;
}
"""
		_glow_material = ShaderMaterial.new()
		_glow_material.shader = shader
	return _glow_material

# --- Primitives ------------------------------------------------------------

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	# Godot's front face is (C-A)x(B-A) pointing out; callers pass a, b, c
	# counter-clockwise seen from outside, so they are emitted a, c, b.
	var n := (b - a).cross(c - a).normalized()
	st.set_color(color)
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(c)
	st.set_normal(n)
	st.add_vertex(b)

## A quad from four corners in order round its edge; `outward` says which side
## is the outside, and the quad is turned to face it.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, color: Color,
		glow: bool = false) -> void:
	var st := _glow if glow else _solid
	if (b - a).cross(c - a).dot(outward) < 0.0:
		var t := b
		b = d
		d = t
	_tri(st, a, b, c, color)
	_tri(st, a, c, d, color)
	if glow:
		_glow_count += 1
	else:
		_solid_count += 1

func tri(a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color, glow: bool = false) -> void:
	var st := _glow if glow else _solid
	if (b - a).cross(c - a).dot(outward) < 0.0:
		var t := b
		b = c
		c = t
	_tri(st, a, b, c, color)
	if glow:
		_glow_count += 1
	else:
		_solid_count += 1

## A box of `size` centred on `xform`'s origin.
func box(size: Vector3, xform: Transform3D, color: Color, glow: bool = false) -> void:
	var h := size * 0.5
	var corners: Array[Vector3] = []
	for i in 8:
		corners.append(xform * Vector3(
			h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	var centre := xform.origin
	# Each face as four corner indices round its edge.
	for f in [[1, 3, 7, 5], [0, 4, 6, 2], [2, 6, 7, 3], [0, 1, 5, 4], [4, 5, 7, 6], [0, 2, 3, 1]]:
		var a: Vector3 = corners[f[0]]
		var b: Vector3 = corners[f[1]]
		var c: Vector3 = corners[f[2]]
		var d: Vector3 = corners[f[3]]
		var face_centre := (a + b + c + d) * 0.25
		# Top faces a touch lighter and undersides darker: a cheap bevel of
		# light that keeps flat colours from looking flat.
		var n := (face_centre - centre)
		var shade := color
		if n.normalized().dot(xform.basis.y.normalized()) > 0.7:
			shade = color.lightened(0.06)
		elif n.normalized().dot(xform.basis.y.normalized()) < -0.7:
			shade = color.darkened(0.12)
		quad(a, b, c, d, n, shade, glow)

## Shorthand: a box at a position, unrotated.
func block(size: Vector3, pos: Vector3, color: Color, glow: bool = false) -> void:
	box(size, Transform3D(Basis(), pos), color, glow)

## An n-sided prism standing on `xform`'s origin, up its Y axis. Different
## radii make a frustum, a zero top radius a pyramid.
func prism(sides: int, r_bottom: float, r_top: float, height: float, xform: Transform3D,
		color: Color, glow: bool = false, caps: bool = true) -> void:
	sides = maxi(3, sides)
	var bottom: Array[Vector3] = []
	var top: Array[Vector3] = []
	for i in sides:
		var a := TAU * (float(i) + 0.5) / float(sides)
		bottom.append(xform * Vector3(cos(a) * r_bottom, 0.0, sin(a) * r_bottom))
		top.append(xform * Vector3(cos(a) * r_top, height, sin(a) * r_top))
	var axis_bottom := xform * Vector3.ZERO
	var axis_top := xform * Vector3(0, height, 0)
	for i in sides:
		var j := (i + 1) % sides
		var mid := (bottom[i] + bottom[j] + top[i] + top[j]) * 0.25
		var out := mid - (axis_bottom + axis_top) * 0.5
		if r_top <= 0.001:
			tri(bottom[i], bottom[j], axis_top, out, color, glow)
		else:
			quad(bottom[i], bottom[j], top[j], top[i], out, color, glow)
	if caps:
		var up := axis_top - axis_bottom
		for i in sides:
			var j := (i + 1) % sides
			tri(axis_bottom, bottom[i], bottom[j], -up, color.darkened(0.12), glow)
			if r_top > 0.001:
				tri(axis_top, top[i], top[j], up, color.lightened(0.06), glow)

## A prism lying from `from` to `to`: pipes, rollers, rails, beams.
func pipe(from: Vector3, to: Vector3, radius: float, color: Color, sides: int = 6,
		glow: bool = false) -> void:
	var along := to - from
	if along.length() < 0.001:
		return
	var y := along.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	prism(sides, radius, radius, along.length(), Transform3D(Basis(x, y, z), from), color, glow)

## A wedge: a box whose top slopes down from the back (-Z) to the front (+Z).
func wedge(size: Vector3, xform: Transform3D, color: Color) -> void:
	var h := size * 0.5
	var p := func(x: float, y: float, z: float) -> Vector3: return xform * Vector3(x, y, z)
	var bl: Vector3 = p.call(-h.x, -h.y, h.z)
	var br: Vector3 = p.call(h.x, -h.y, h.z)
	var bbl: Vector3 = p.call(-h.x, -h.y, -h.z)
	var bbr: Vector3 = p.call(h.x, -h.y, -h.z)
	var tl: Vector3 = p.call(-h.x, h.y, -h.z)
	var tr: Vector3 = p.call(h.x, h.y, -h.z)
	var c := xform.origin
	quad(bl, br, bbr, bbl, (bl + bbr) * 0.5 - c - xform.basis.y, color.darkened(0.12))
	quad(bbl, bbr, tr, tl, (bbl + tr) * 0.5 - c, color)
	quad(bl, br, tr, tl, (bl + tr) * 0.5 - c + xform.basis.y * 0.01, color.lightened(0.06))
	tri(bl, bbl, tl, -xform.basis.x, color)
	tri(br, bbr, tr, xform.basis.x, color)

# --- Detail ----------------------------------------------------------------

## The edges of a box as square beams: a frame that makes a panel read as a
## built thing with corners, rather than a block.
func frame(size: Vector3, xform: Transform3D, beam: float, color: Color) -> void:
	var h := size * 0.5
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			box(Vector3(beam, size.y, beam), xform * Transform3D(Basis(), Vector3(sx * h.x, 0, sz * h.z)), color)
	for sy in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			box(Vector3(beam, beam, size.z), xform * Transform3D(Basis(), Vector3(sx * h.x, sy * h.y, 0)), color)
		for sz in [-1.0, 1.0]:
			box(Vector3(size.x, beam, beam), xform * Transform3D(Basis(), Vector3(0, sy * h.y, sz * h.z)), color)

## A raised plate on a face, with a bolt at each corner. `xform` sits on the
## face with +Z pointing out of it.
func plate(width: float, height: float, xform: Transform3D, color: Color,
		bolt_color: Color = Color(0.72, 0.72, 0.70)) -> void:
	box(Vector3(width, height, 0.05), xform * Transform3D(Basis(), Vector3(0, 0, 0.025)), color)
	var inset := minf(0.12, minf(width, height) * 0.2)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			box(Vector3(0.06, 0.06, 0.04), xform * Transform3D(Basis(),
				Vector3(sx * (width * 0.5 - inset), sy * (height * 0.5 - inset), 0.07)), bolt_color)

## Horizontal slats on a face: a vent or a grille.
func vent(width: float, height: float, xform: Transform3D, color: Color, slats: int = 4) -> void:
	box(Vector3(width, height, 0.03), xform * Transform3D(Basis(), Vector3(0, 0, 0.015)), color.darkened(0.45))
	for i in slats:
		var y := -height * 0.5 + height * (float(i) + 0.5) / float(slats)
		box(Vector3(width * 0.94, height / float(slats) * 0.45, 0.06),
			xform * Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, y, 0.05)), color)

## Diagonal warning stripes along a strip lying on a face.
func stripes(length: float, width: float, xform: Transform3D, a: Color = Color(0.95, 0.74, 0.16),
		b: Color = Color(0.10, 0.10, 0.09)) -> void:
	var count := maxi(2, int(length / (width * 1.2)))
	var seg := length / float(count)
	for i in count:
		var x := -length * 0.5 + seg * (float(i) + 0.5)
		box(Vector3(seg, width, 0.04), xform * Transform3D(Basis(), Vector3(x, 0, 0.02)),
			a if i % 2 == 0 else b)

## A lamp: a small housing and a glowing lens.
func lamp(xform: Transform3D, color: Color = Color(1.0, 0.82, 0.45), size: float = 0.22) -> void:
	box(Vector3(size * 1.4, size * 1.4, size * 0.6), xform, Color(0.16, 0.16, 0.15))
	box(Vector3(size, size, size * 0.4), xform * Transform3D(Basis(), Vector3(0, 0, size * 0.4)), color, true)

## Scatters rivets along a line.
func rivets(from: Vector3, to: Vector3, count: int, color: Color = Color(0.7, 0.7, 0.68),
		size: float = 0.05) -> void:
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		block(Vector3(size, size, size), from.lerp(to, t), color)

# --- Output ----------------------------------------------------------------

func is_empty() -> bool:
	return _solid_count == 0 and _glow_count == 0

func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _solid_count > 0:
		_solid.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, solid_material())
	if _glow_count > 0:
		_glow.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, glow_material())
	return mesh

## The mesh as a MeshInstance3D, ready to add.
func instance(name: String = "Greeble", cast_shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = commit()
	if not cast_shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
