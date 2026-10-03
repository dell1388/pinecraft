extends Node3D
## Look at the traders (not part of the game): the four figures on a lawn,
## a camera, and a snapshot now and then. Run with
##   --state=<work|rest|pace|angry|sulk|rock|doze|idle|walk> --at=<seconds,...>
## Saves user://shots/npc_<state>_<n>.png.

var args := {}
var figures: Array[NpcFigure] = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := String(a).trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.74, 0.86)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.75)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var lawn := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	lawn.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.36, 0.58, 0.28)
	lawn.material_override = m
	add_child(lawn)
	var roles := [NpcFigure.Role.LUMBERMAN, NpcFigure.Role.MINER, NpcFigure.Role.GRANNY, NpcFigure.Role.HELPER]
	var only: String = args.get("who", "")
	for i in roles.size():
		if only != "" and String(NpcFigure.Role.keys()[roles[i]]).to_lower() != only:
			continue
		var f := NpcFigure.new(roles[i], "")
		var x := -4.5 + 3.0 * float(i)
		f.position = Vector3(x, 0, 0)
		f.post = f.position
		f.pace_to = f.position + Vector3(0, 0, 4)
		f.work_at = f.position + Vector3(0, 0, -1.2)
		add_child(f)
		figures.append(f)
		# What they work at: a stump of a trunk, a rock.
		if roles[i] == NpcFigure.Role.LUMBERMAN or roles[i] == NpcFigure.Role.MINER:
			var prop := MeshInstance3D.new()
			if roles[i] == NpcFigure.Role.LUMBERMAN:
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.32
				cyl.bottom_radius = 0.38
				cyl.height = 3.0
				prop.mesh = cyl
				prop.position = f.work_at + Vector3(0, 1.5, 0)
			else:
				var b := BoxMesh.new()
				b.size = Vector3(0.9, 0.5, 0.7)
				prop.mesh = b
				prop.position = f.work_at + Vector3(0, 0.25, 0)
			add_child(prop)
	var cam := Camera3D.new()
	var from := Vector3(float(args.get("cx", "3.5")), float(args.get("cy", "2.2")), float(args.get("cz", "-7.5")))
	cam.position = from
	add_child(cam)
	cam.look_at(Vector3(float(args.get("lx", "0")), float(args.get("ly", "1.0")), 0))
	cam.fov = float(args.get("fov", "50"))
	cam.current = true
	var st: String = args.get("state", "")
	if st != "":
		for f in figures:
			f.call("_start", StringName(st))
	if args.has("carry"):
		# The helper with an armful of lumber, walking off.
		for f in figures:
			if f.role == NpcFigure.Role.HELPER:
				var g := Greeble.new()
				for k in 4:
					g.box(Vector3(1.2, 0.3, 0.3), Transform3D(Basis(), Vector3(0, 0.15 + 0.3 * float(k), 0)), Color(0.74, 0.57, 0.34))
				f.hold(g.instance("Load"))
				f.walk(f.position + Vector3(0, 0, 30), &"idle")
	var times := String(args.get("at", "0.5")).split(",")
	var n := 0
	var last := 0.0
	for t in times:
		var until := float(t)
		while last < until:
			await get_tree().process_frame
			last += get_process_delta_time()
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://shots"))
		img.save_png("user://shots/npc_%s_%d.png" % [st if st != "" else "default", n])
		print("saved npc_%s_%d" % [st, n])
		n += 1
	get_tree().quit()
