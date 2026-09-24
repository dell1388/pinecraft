class_name Doodad
extends StaticBody3D

## Things you put on the plot because you like them: fences, lamps, benches,
## a gnome. Solid, placeable in build mode like any building, and doing
## nothing at all - except the lamp, which comes on at dusk, and the beacon,
## which glows.

var def: BuildingDef
var _size: Vector3 = Vector3.ONE

func setup(p_def: BuildingDef) -> void:
	def = p_def

func _ready() -> void:
	collision_layer = Layers.MACHINE
	collision_mask = 0
	_size = def.footprint_world(Plot.CELL)
	# Resized in build mode, a doodad is drawn at its own size and scaled up
	# to the new one - except a fence, which just gets longer.
	var base_def := GameData.building(def.id)
	var base := base_def.footprint_world(Plot.CELL) if base_def != null else _size
	var stretch := Vector3.ONE
	if def.id == &"fence":
		base = Vector3(base.x, base.y, _size.z)
	else:
		stretch = _size / base
	var g := Greeble.new()
	var h := build(g, def.id, base)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(base.x * 0.8, h, base.z * 0.8) * stretch
	cs.shape = box
	cs.position = Vector3(0, h * 0.5 * stretch.y, 0)
	add_child(cs)
	var mesh := g.instance("Doodad")
	mesh.scale = stretch
	add_child(mesh)
	if def.id == &"lamp_post":
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.85, 0.55)
		light.omni_range = 9.0
		light.light_energy = 1.2
		light.position = Vector3(0, h - 0.3, 0)
		add_child(light)

## Draws one doodad into `g`, standing on the origin. Returns its height.
static func build(g: Greeble, id: StringName, size: Vector3) -> float:
	var wood := Color(0.55, 0.38, 0.22)
	var dark := Color(0.16, 0.16, 0.17)
	var white := Color(0.93, 0.92, 0.88)
	var stone := Color(0.62, 0.60, 0.56)
	match id:
		&"fence":
			var run := size.z
			for k in 5:
				var z := -run * 0.5 + 0.2 + (run - 0.4) * float(k) / 4.0
				g.block(Vector3(0.1, 0.9, 0.1), Vector3(0, 0.45, z), white)
				g.wedge(Vector3(0.1, 0.12, 0.1), Transform3D(Basis(), Vector3(0, 0.96, z)), white)
			for y in [0.3, 0.7]:
				g.block(Vector3(0.05, 0.1, run - 0.1), Vector3(0, y, 0), white.darkened(0.08))
			return 1.0
		&"lamp_post":
			g.prism(8, 0.18, 0.14, 0.2, Transform3D(), dark)
			g.pipe(Vector3(0, 0.2, 0), Vector3(0, 2.6, 0), 0.06, dark, 6)
			g.block(Vector3(0.36, 0.06, 0.36), Vector3(0, 2.62, 0), dark)
			g.block(Vector3(0.26, 0.34, 0.26), Vector3(0, 2.82, 0), Color(1.0, 0.86, 0.5), true)
			g.prism(4, 0.26, 0.05, 0.18, Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 3.0, 0)), dark)
			return 3.2
		&"bench":
			for k in 3:
				g.block(Vector3(0.14, 0.05, size.z * 0.9), Vector3(-0.15 + float(k) * 0.15, 0.45, 0), wood)
			for k in 2:
				g.block(Vector3(0.04, 0.12, size.z * 0.9), Vector3(0.22, 0.65 + float(k) * 0.16, 0), wood)
			for z in [-size.z * 0.35, size.z * 0.35]:
				g.block(Vector3(0.5, 0.45, 0.06), Vector3(0, 0.22, z), dark)
				g.block(Vector3(0.05, 0.5, 0.06), Vector3(0.22, 0.65, z), dark)
			return 1.0
		&"planter":
			g.block(Vector3(0.8, 0.45, 0.8), Vector3(0, 0.225, 0), wood.darkened(0.15))
			g.block(Vector3(0.7, 0.05, 0.7), Vector3(0, 0.44, 0), Color(0.3, 0.2, 0.12))
			var colors := [Color(0.95, 0.3, 0.4), Color(1.0, 0.8, 0.2), Color(0.6, 0.4, 0.95), Color(1.0, 0.55, 0.2)]
			for k in 8:
				var a := TAU * float(k) / 8.0
				var at := Vector3(cos(a) * 0.22, 0.46, sin(a) * 0.22)
				g.block(Vector3(0.03, 0.25, 0.03), at + Vector3(0, 0.12, 0), Color(0.3, 0.55, 0.2))
				g.block(Vector3(0.11, 0.08, 0.11), at + Vector3(0, 0.28, 0), colors[k % colors.size()])
			return 0.8
		&"barrel":
			g.prism(8, 0.32, 0.32, 0.9, Transform3D(), wood)
			for y in [0.15, 0.45, 0.75]:
				g.prism(8, 0.335, 0.335, 0.05, Transform3D(Basis(), Vector3(0, y, 0)), dark)
			return 0.9
		&"crate_stack":
			g.block(Vector3(0.8, 0.8, 0.8), Vector3(0, 0.4, 0), wood)
			g.frame(Vector3(0.8, 0.8, 0.8), Transform3D(Basis(), Vector3(0, 0.4, 0)), 0.07, wood.darkened(0.3))
			g.box(Vector3(0.6, 0.6, 0.6), Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.05, 1.1, 0)), wood.lightened(0.1))
			g.frame(Vector3(0.6, 0.6, 0.6), Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.05, 1.1, 0)), 0.06, wood.darkened(0.3))
			return 1.4
		&"flag_pole":
			g.pipe(Vector3.ZERO, Vector3(0, 4.8, 0), 0.05, Color(0.8, 0.8, 0.82), 6)
			g.prism(8, 0.08, 0.08, 0.08, Transform3D(Basis(), Vector3(0, 4.8, 0)), Color(1.0, 0.8, 0.2))
			g.block(Vector3(0.02, 0.6, 0.9), Vector3(0, 4.35, 0.48), Color(0.20, 0.55, 0.30))
			g.block(Vector3(0.025, 0.2, 0.9), Vector3(0, 4.35, 0.48), Color(0.98, 0.76, 0.2))
			return 4.9
		&"signpost":
			g.block(Vector3(0.1, 1.7, 0.1), Vector3(0, 0.85, 0), wood)
			g.box(Vector3(0.05, 0.22, 0.8), Transform3D(Basis(Vector3.UP, 0.3), Vector3(0, 1.45, 0.1)), white)
			g.box(Vector3(0.05, 0.22, 0.7), Transform3D(Basis(Vector3.UP, -0.9), Vector3(0, 1.15, -0.05)), white.darkened(0.1))
			return 1.7
		&"hay_bale":
			for z in [-0.45, 0.45]:
				g.block(Vector3(0.7, 0.5, 0.85), Vector3(0, 0.25, z), Color(0.86, 0.74, 0.36))
				g.block(Vector3(0.72, 0.52, 0.04), Vector3(0, 0.25, z - 0.2), Color(0.55, 0.4, 0.2))
				g.block(Vector3(0.72, 0.52, 0.04), Vector3(0, 0.25, z + 0.2), Color(0.55, 0.4, 0.2))
			g.block(Vector3(0.7, 0.5, 0.85), Vector3(0, 0.75, 0), Color(0.9, 0.78, 0.4))
			return 1.0
		&"garden_gnome":
			g.prism(6, 0.18, 0.16, 0.3, Transform3D(), Color(0.25, 0.45, 0.8))
			g.prism(6, 0.14, 0.14, 0.18, Transform3D(Basis(), Vector3(0, 0.3, 0)), Color(0.95, 0.8, 0.68))
			g.prism(6, 0.13, 0.1, 0.12, Transform3D(Basis(), Vector3(0, 0.22, 0.05)), white)
			g.prism(6, 0.16, 0.0, 0.35, Transform3D(Basis(), Vector3(0, 0.46, 0)), Color(0.9, 0.2, 0.2))
			return 0.8
		&"statue":
			g.block(Vector3(1.6, 0.6, 1.6), Vector3(0, 0.3, 0), stone)
			g.frame(Vector3(1.6, 0.6, 1.6), Transform3D(Basis(), Vector3(0, 0.3, 0)), 0.08, stone.darkened(0.2))
			var gold := Color(0.95, 0.78, 0.28)
			for x in [-0.18, 0.18]:
				g.block(Vector3(0.22, 0.9, 0.26), Vector3(x, 1.05, 0), gold)
			g.block(Vector3(0.7, 1.0, 0.4), Vector3(0, 2.0, 0), gold)
			g.block(Vector3(0.36, 0.36, 0.36), Vector3(0, 2.72, 0), gold.lightened(0.1))
			g.block(Vector3(0.2, 0.8, 0.2), Vector3(0.48, 2.4, 0), gold)
			g.pipe(Vector3(0.5, 2.7, 0), Vector3(0.5, 3.7, 0), 0.05, gold.darkened(0.2), 6)
			g.wedge(Vector3(0.45, 0.35, 0.06), Transform3D(Basis(Vector3.FORWARD, -PI * 0.5), Vector3(0.72, 3.6, 0)), Color(0.85, 0.86, 0.9))
			return 3.8
		&"fountain":
			g.prism(8, 1.4, 1.4, 0.5, Transform3D(), stone)
			g.prism(8, 1.25, 1.25, 0.02, Transform3D(Basis(), Vector3(0, 0.46, 0)), Color(0.35, 0.6, 0.85), true)
			g.prism(8, 0.25, 0.2, 1.2, Transform3D(Basis(), Vector3(0, 0.5, 0)), stone.lightened(0.1))
			g.prism(8, 0.6, 0.6, 0.15, Transform3D(Basis(), Vector3(0, 1.6, 0)), stone)
			g.prism(8, 0.5, 0.5, 0.02, Transform3D(Basis(), Vector3(0, 1.74, 0)), Color(0.4, 0.7, 0.95), true)
			return 1.8
		&"beacon":
			g.prism(6, 0.4, 0.34, 0.3, Transform3D(), dark)
			g.prism(6, 0.22, 0.0, 2.3, Transform3D(Basis(), Vector3(0, 0.3, 0)), Color(0.45, 0.85, 1.0), true)
			for k in 3:
				var a := TAU * float(k) / 3.0
				g.prism(5, 0.08, 0.0, 0.7, Transform3D(Basis(Vector3(sin(a), 0, -cos(a)), 0.4), Vector3(cos(a) * 0.25, 0.3, sin(a) * 0.25)), Color(0.7, 0.5, 1.0), true)
			return 2.6
		&"topiary":
			g.block(Vector3(0.6, 0.4, 0.6), Vector3(0, 0.2, 0), Color(0.62, 0.36, 0.24))
			for k in 4:
				var r := 0.42 - float(k) * 0.08
				g.prism(8, r, r * 0.8, 0.32, Transform3D(Basis(Vector3.UP, float(k) * 0.5), Vector3(0, 0.4 + float(k) * 0.36, 0)), Color(0.22, 0.5, 0.22).lightened(float(k) * 0.04))
			return 1.9
	g.block(size * Vector3(0.8, 1.0, 0.8), Vector3(0, size.y * 0.5, 0), wood)
	return size.y

func status_line() -> String:
	return def.display_name
