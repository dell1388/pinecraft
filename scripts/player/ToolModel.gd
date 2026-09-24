class_name ToolModel
extends RefCounted

## A hand tool as a mesh, built from its row in tools.json: a handle and a
## head, an axe's blade (or two, on a twin-bit) or a hammer's block. Used for
## the one in your hand and on the store shelf.

static func mesh(def: Dictionary) -> ArrayMesh:
	var g := Greeble.new()
	var head := _color(def.get("head", [0.6, 0.6, 0.62]))
	var handle := _color(def.get("handle", [0.5, 0.35, 0.2]))
	var glow := bool(def.get("glow", false))
	var hammer := String(def.get("kind", "axe")) == "hammer"
	var length := 0.72 if hammer else 0.78
	# The handle runs up +Y from the grip.
	g.box(Vector3(0.045, length, 0.045), Transform3D(Basis(), Vector3(0, length * 0.5, 0)), handle)
	g.box(Vector3(0.055, 0.12, 0.055), Transform3D(Basis(), Vector3(0, 0.08, 0)), handle.darkened(0.3))
	var top := Vector3(0, length - 0.05, 0)
	if hammer:
		var kg := float(def.get("head_kg", 3.0))
		var s := clampf(0.1 + kg * 0.006, 0.1, 0.3)
		g.box(Vector3(s * 2.2, s, s), Transform3D(Basis(), top), head, glow)
		for side in [-1.0, 1.0]:
			g.box(Vector3(0.03, s * 1.1, s * 1.1), Transform3D(Basis(), top + Vector3(side * s * 1.1, 0, 0)), head.darkened(0.25))
	else:
		var sides := [1.0, -1.0] if bool(def.get("twin", false)) else [1.0]
		g.box(Vector3(0.08, 0.1, 0.06), Transform3D(Basis(), top), head.darkened(0.3))
		for side in sides:
			# The blade: a wedge flaring out from the eye to the edge.
			var blade := Transform3D(Basis(Vector3.FORWARD, -side * PI * 0.5), top + Vector3(side * 0.13, 0, 0))
			g.wedge(Vector3(0.2, 0.18, 0.035), blade, head)
			g.box(Vector3(0.02, 0.2, 0.04), Transform3D(Basis(), top + Vector3(side * 0.225, 0, 0)), head.lightened(0.35), glow)
	return g.commit()

static func _color(a: Variant) -> Color:
	var arr: Array = a
	return Color(float(arr[0]), float(arr[1]), float(arr[2]))

static func color_of(def: Dictionary) -> Color:
	return _color(def.get("head", [0.6, 0.6, 0.62]))
