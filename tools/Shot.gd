extends Node
## Screenshot harness (not part of the game): boots the world with no menu,
## runs a scenario named by --shot=<name>, saves PNGs to user://shots.

var world: World
var args := {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := String(a).trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	world = load("res://scenes/world.tscn").instantiate()
	world.show_menu = false
	world.autosave = false
	add_child(world)
	for i in 30:
		await get_tree().process_frame
	var shot: String = args.get("shot", "home")
	await call("shot_" + shot)
	get_tree().quit()

func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://shots"))
	img.save_png("user://shots/%s.png" % name)
	print("saved ", name)

func look(from: Vector3, at: Vector3) -> void:
	var cam := world.player.camera
	cam.top_level = true
	cam.global_transform = Transform3D(Basis(), from).looking_at(at, Vector3.UP)
	world.hud.visible = args.has("hud")
	for i in 20:
		await get_tree().process_frame

func shot_home() -> void:
	await look(Vector3(0, 60, 90), Vector3(0, 0, 0))
	await snap("home")

func _cam_state() -> String:
	var c := world.player.camera
	return "pos=%s rot=%s" % [c.global_position.snapped(Vector3.ONE * 0.01), c.global_rotation.snapped(Vector3.ONE * 0.001)]

func _mouse(button: int, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = get_viewport().get_visible_rect().size * 0.5
	Input.parse_input_event(ev)

func _motion(rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = rel
	ev.position = get_viewport().get_visible_rect().size * 0.5
	Input.parse_input_event(ev)

func shot_dragcam() -> void:
	var p := world.player
	p.global_position = world.plot.global_position + Vector3(0, 1, 8)
	for i in 5:
		await get_tree().physics_frame
	Settings.set_value(&"unlimited_money", true, false)
	world.build_system.set_active(true)
	var node := world.plot.place(GameData.building(&"conveyor"), Vector2i(0, 0), 0, false)
	var idx := world.plot.placed.size() - 1
	world.build_system.select_building(idx)
	await get_tree().process_frame
	var bs := world.build_system
	var h: Dictionary = bs._gizmo.handles[0]
	var cam := p.camera
	cam.global_transform = Transform3D(Basis(), cam.global_position).looking_at(h.point, Vector3.UP)
	await get_tree().process_frame
	print("handle pick=", bs._gizmo.pick(cam, bs._centre()), " ", _cam_state())
	_mouse(MOUSE_BUTTON_LEFT, true)
	await get_tree().process_frame
	print("dragging=", not bs._drag.is_empty(), " ", _cam_state())
	for i in 10:
		_motion(Vector2(12, 0))
		await get_tree().process_frame
		print("  drag ", i, " ", _cam_state(), " cell=", world.plot.placed[idx].cell)
	_mouse(MOUSE_BUTTON_LEFT, false)
	for i in 6:
		await get_tree().process_frame
		print("  after ", i, " ", _cam_state())
	_motion(Vector2(1, 0))
	await get_tree().process_frame
	print("  after small motion ", _cam_state())

func shot_roads() -> void:
	var t: Terrain = world.terrain
	var found: Array = []
	for road in t.road_paths:
		var path: Array = road.path
		if path.size() < 3:
			continue
		var span := t._path_length(path)
		var along := 10.0
		while along < span - 10.0:
			var a := t._point_along(path, along - 8.0)
			var p := t._point_along(path, along)
			var b := t._point_along(path, along + 8.0)
			var d1 := Vector2(p.x - a.x, p.z - a.z).normalized()
			var d2 := Vector2(b.x - p.x, b.z - p.z).normalized()
			var turn := absf(d1.angle_to(d2))
			var relief := 0.0
			for k in 8:
				var ang := TAU * k / 8.0
				relief = maxf(relief, absf(t.height_at(p.x + cos(ang) * 20.0, p.z + sin(ang) * 20.0) - t.height_at(p.x, p.z)))
			if turn > 0.6 and relief > 6.0:
				found.append({"p": p, "turn": turn, "relief": relief, "back": t._point_along(path, maxf(0.0, along - 22.0))})
				along += 60.0
			along += 3.0
	found.sort_custom(func(x, y): return x.turn * x.relief > y.turn * y.relief)
	print("sharp steep turns: ", found.size())
	for i in mini(4, found.size()):
		var f: Dictionary = found[i]
		var p: Vector3 = f.p
		p.y = t.height_at(p.x, p.z)
		print("turn %d at %s angle %.2f relief %.1f" % [i, p, f.turn, f.relief])
		await look(p + Vector3(18, 22, 18), p)
		await snap("road_%d" % i)
		var back: Vector3 = f.back
		back.y = t.height_at(back.x, back.z) + 2.5
		await look(back, p + Vector3(0, 1.0, 0))
		await snap("road_%d_low" % i)

func shot_plot() -> void:
	Settings.set_value(&"unlimited_money", true, false)
	while world.plot.try_expand():
		pass
	await look(Vector3(70, 45, 70), Vector3(0, 0, 0))
	await snap("plot_corner")
	await look(Vector3(0, 90, 1), Vector3(0, 0, 0))
	await snap("plot_top")

func shot_forest() -> void:
	var c: Vector3 = world.starter_forest
	print("starter forest at ", c)
	await look(c + Vector3(40, 35, 40), c)
	await snap("starter_forest")
	await look(Vector3(0, 380, 200), Vector3(0, 0, -150))
	await snap("groves")

func shot_store() -> void:
	var s: Store = world.store
	var door := s.global_transform * Vector3(0, 1.6, s.extents.z * 0.5 + 5.0)
	await look(door + Vector3(3, 0.5, 0), s.global_transform * Vector3(0, 0.2, s.extents.z * 0.5))
	await snap("store_door")
	# The gear bay.
	await look(s.global_transform * Vector3(0, 3.0, 2.0), s.global_transform * Vector3(0, 0.5, -s.extents.z * 0.5))
	await snap("store_inside")
	# The vehicle dealer and the machine works, from inside.
	for pair in [[world.dealer_store, "dealer_inside"], [world.works_store, "works_inside"]]:
		var shop: Store = pair[0]
		if shop == null:
			continue
		for i in 90:
			await get_tree().process_frame
		await look(shop.global_transform * Vector3(0, 3.0, 3.0), shop.global_transform * Vector3(0, 0.8, -shop.extents.z * 0.5))
		await snap(pair[1])

func shot_build() -> void:
	var p := world.player
	p.global_position = world.plot.global_position + Vector3(0, 1, 6)
	Settings.set_value(&"unlimited_money", true, false)
	for i in 5:
		await get_tree().physics_frame
	for x in 3:
		world.plot.place(GameData.building(&"conveyor_open"), Vector2i(x * 4, -8), Vector3i.ZERO, false)
	world.plot.place(GameData.building(&"conveyor"), Vector2i(-12, -8), Vector3i.ZERO, false)
	world.build_system.set_active(true)
	world.hud.visible = true
	await get_tree().process_frame
	var cam := p.camera
	cam.global_transform = Transform3D(Basis(), world.plot.global_position + Vector3(1, 4.5, 4)).looking_at(world.plot.global_position + Vector3(0.5, 0, -1), Vector3.UP)
	for i in 10:
		await get_tree().process_frame
	await snap("build_empty")
	world.build_system.toggle_menu()
	for i in 10:
		await get_tree().process_frame
	await snap("build_menu")
	world.hud.close_build_menu()
	world.build_system.choose(GameData.building(&"sander"))
	for i in 10:
		await get_tree().process_frame
	await snap("build_ghost")

func shot_loader() -> void:
	var p := world.player
	var at := world.plot.global_position + Vector3(0, 0, 30)
	at.y = world.terrain.height_at(at.x, at.z)
	var v := Hauler.new()
	v.setup(world.manager, 0, &"loader")
	world.add_child(v)
	v.global_position = at + Vector3(0, v.spawn_height(), 0)
	for i in 30:
		await get_tree().physics_frame
	print(v.loader.swap_attachment())
	for i in 10:
		await get_tree().physics_frame
	await look(at + Vector3(-6, 3.5, -7), at + Vector3(0, 1, -1.5))
	await snap("loader_grapple")

func shot_fell() -> void:
	var trees: Array = world.trees()
	var best: ChoppableTree = null
	for t in trees:
		if t.foliage_style == &"ball" or t.foliage_style == &"cone":
			if best == null or t.global_position.distance_to(world.plot.global_position) < best.global_position.distance_to(world.plot.global_position):
				best = t
	var at := best.global_position
	best.fell(at + Vector3(0, 0, 3))
	for i in 180:
		await get_tree().physics_frame
	await look(at + Vector3(8, 5, 8), at + Vector3(0, 0.5, -3))
	await snap("felled")

func shot_pause() -> void:
	world.pause_game()
	for i in 10:
		await get_tree().process_frame
	await snap("pause")
	world.pause_menu._show_slots()
	for i in 10:
		await get_tree().process_frame
	await snap("pause_slots")
	world.pause_menu._show_page("Settings", SettingsPanel.new())
	for i in 10:
		await get_tree().process_frame
	await snap("settings_controls")

func shot_drive() -> void:
	var at := world.plot.global_position + Vector3(0, 0, 60)
	at.y = world.terrain.height_at(at.x, at.z)
	var v := Hauler.new()
	v.setup(world.manager, 0, &"crane_truck")
	world.add_child(v)
	v.global_position = at + Vector3(0, v.spawn_height(), 0)
	for i in 30:
		await get_tree().physics_frame
	world.drive(v)
	world.hud.visible = true
	Settings.set_value(&"manual_gearbox", true, false)
	for i in 30:
		await get_tree().process_frame
	await snap("drive_manual")
	v.rig.set_operating(true)
	for i in 60:
		await get_tree().physics_frame
	await snap("crane_banner")

## The mobile crane: on the road with its boom laid forward, then set up with
## the boom run out and up.
func shot_mobilecrane() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var at := world.plot.global_position + Vector3(0, 0, 60)
	at.y = world.terrain.height_at(at.x, at.z)
	var v := Hauler.new()
	v.setup(world.manager, 0, &"crane_truck")
	world.add_child(v)
	v.global_position = at + Vector3(0, v.spawn_height(), 0)
	for i in 90:
		await get_tree().physics_frame
	var f := v.global_transform
	var eye := f * Vector3(-9.0, 3.5, -10.0)
	world.player.global_position = eye
	await look(eye, f * Vector3(0, 1.2, 0))
	await snap("mcrane_road")
	eye = f * Vector3(9.0, 2.5, 6.0)
	await look(eye, f * Vector3(0, 1.5, 0))
	await snap("mcrane_back")
	v.rig.set_operating(true)
	v.rig.target = v.rig.clamp_target(Vector3(-12.0, 14.0, 16.0))
	for i in 400:
		await get_tree().physics_frame
	eye = f * Vector3(-26.0, 8.0, -18.0)
	world.player.global_position = eye
	await look(eye, f * Vector3(-4, 8, 6))
	await snap("mcrane_up")

## The carton pictures for everything at the vehicle dealer, one file each.
func shot_boxart() -> void:
	var shop: Store = world.dealer_store
	var left := 0
	for slot in shop.slots:
		var product := {"box": slot.box, "kind": String(slot.kind), "target": slot.target,
			"tier": slot.tier, "level": slot.level, "color": Color(0.8, 0.5, 0.2)}
		left += 1
		var id := String(slot.target)
		shop._art.request(product, func(tex: Texture2D):
			tex.get_image().save_png(OS.get_user_data_dir() + "/shots/box_%s.png" % id)
			left -= 1)
	for i in 1200:
		if left <= 0:
			break
		await get_tree().process_frame
	print("box art done, %d left" % left)

func shot_menu() -> void:
	world.show_main_menu()
	for i in 20:
		await get_tree().process_frame
	await snap("main_menu")
	world.main_menu._open_page("Controls", KeyGuide.sheet())
	for i in 10:
		await get_tree().process_frame
	await snap("main_controls")

func shot_axe() -> void:
	var p := world.player
	PlayerState.give_tool(&"steel_axe", false)
	p.select_slot(PlayerState.hotbar.find(&"steel_axe"))
	world.hud.visible = false
	for i in 20:
		await get_tree().process_frame
	await snap("axe")

func shot_minimap() -> void:
	var p := world.player
	p.rotation.y = 0.8
	Settings.set_value(&"minimap_rotate", true, false)
	Settings.set_value(&"minimap_zoom", 2, false)
	world.hud.visible = true
	for i in 30:
		await get_tree().process_frame
	await snap("minimap")

## The lumberjack in third person, in one pose after another.
func _pose_cam(p: Player, side: float = 1.0, dist: float = 2.6) -> void:
	var at := p.global_position + Vector3(0, 0.95, 0)
	var f := -p.global_transform.basis.z
	var r := p.global_transform.basis.x
	var cam := p.camera
	cam.top_level = true
	cam.global_transform = Transform3D(Basis(), at + f * dist + r * dist * 0.55 * side + Vector3(0, 0.35, 0)).looking_at(at, Vector3.UP)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

## Plays a gesture and waits until it is `share` of the way through.
func _gesture_at(p: Player, kind: StringName, share: float) -> void:
	# Slowed right down, so a slow frame here does not skip the moment.
	p.avatar.play(kind)
	Engine.time_scale = clampf(p.avatar._g_len * 0.4, 0.12, 1.0)
	while p.avatar._gesture == kind and p.avatar._g_t < p.avatar._g_len * share:
		await get_tree().process_frame
	for i in 3:
		await get_tree().process_frame
	Engine.time_scale = 1.0

func _stand(p: Player) -> Vector3:
	world.hud.visible = false
	var at := world.plot.global_position + Vector3(4, 0, 10)
	at.y = world.terrain.height_at(at.x, at.z) + 0.2
	p.global_position = at
	p.third_person = true
	for i in 30:
		await get_tree().physics_frame
	return at

func shot_avatar() -> void:
	var p := world.player
	await _stand(p)
	_pose_cam(p)
	await _frames(10)
	await snap("av_idle")
	await _gesture_at(p, &"stroke", 0.5)
	await snap("av_stroke")
	await _gesture_at(p, &"stretch", 0.5)
	await snap("av_stretch")
	await _gesture_at(p, &"scratch", 0.5)
	await snap("av_scratch")
	PlayerState.give_tool(&"steel_axe", false)
	p.select_slot(PlayerState.hotbar.find(&"steel_axe"))
	await _frames(20)
	await snap("av_tool")
	await _gesture_at(p, &"swing", 0.36)
	await snap("av_swing_up")
	await _gesture_at(p, &"swing", 0.6)
	await snap("av_swing_down")
	p.select_slot(p.selected_slot)
	await _frames(20)
	await _gesture_at(p, &"pick_up", 0.5)
	await snap("av_pick_up")
	await _gesture_at(p, &"throw", 0.34)
	await snap("av_throw")
	await _gesture_at(p, &"use", 0.5)
	await snap("av_use")
	await _gesture_at(p, &"drop", 0.5)
	await snap("av_drop")
	Input.action_press("move_forward")
	for i in 40:
		await get_tree().physics_frame
		_pose_cam(p)
	await snap("av_walk")
	Input.action_release("move_forward")
	p.velocity.y = p.jump_velocity
	for i in 16:
		await get_tree().physics_frame
		_pose_cam(p)
	await snap("av_jump")

func shot_avatar_drive() -> void:
	var p := world.player
	var at := await _stand(p)
	world.build_system.set_active(true)
	await _frames(10)
	_pose_cam(p, -1.0, 3.0)
	await _frames(2)
	await snap("av_build")
	await _gesture_at(p, &"place", 0.3)
	await snap("av_place")
	world.build_system.set_active(false)
	await _frames(5)
	var v := Hauler.new()
	v.setup(world.manager, 0, StringName(args.get("vehicle", "quad")))
	world.add_child(v)
	v.global_position = at + Vector3(6, v.spawn_height(), 0)
	for i in 40:
		await get_tree().physics_frame
	world.drive(v)
	for i in 20:
		await get_tree().physics_frame
	var vb := v.global_transform.basis
	var cam := p.camera
	cam.top_level = true
	Input.action_press("move_right")
	await _frames(30)
	vb = v.global_transform.basis
	p.rotation.y += PI * 0.5
	p.camera.rotation.x = -0.15
	await _frames(10)
	cam.global_transform = Transform3D(Basis(), v.global_position - vb.x * 3.2 + Vector3(0, 0.9, 0) + vb.z * 0.3).looking_at(v.global_position + Vector3(0, 0.6, 0), Vector3.UP)
	await _frames(3)
	await snap("av_drive")
	Input.action_release("move_right")
	vb = v.global_transform.basis
	cam.global_transform = Transform3D(Basis(), v.global_position - vb.z * 3.5 + Vector3(0, 1.5, 0)).looking_at(v.global_position + Vector3(0, 0.6, 0), Vector3.UP)
	await _frames(3)
	await snap("av_drive_front")

func shot_views() -> void:
	var p := world.player
	await _stand(p)
	world.hud.visible = true
	p.camera.top_level = false
	p.camera.rotation.x = -0.15
	p.set_third_person(true)
	PlayerState.give_tool(&"steel_axe", false)
	p.select_slot(PlayerState.hotbar.find(&"steel_axe"))
	await _frames(30)
	await snap("view_third")
	p.set_third_person(false)
	p.camera.rotation.x = -0.9
	await _frames(30)
	await snap("view_first_down")
	Settings.set_value(&"third_person", false)

## How other co-op players look: the lumberjack in their colour, named.
func shot_coop() -> void:
	var p := world.player
	var at := await _stand(p)
	var names := ["Dell", "Sam"]
	for i in 2:
		var a := Avatar.new()
		a.setup(names[i], Avatar.color_for(i + 2))
		world.add_child(a)
		a.global_position = at + Vector3(-1.2 + 2.4 * i, 0, -4.0)
		a.rotation.y = PI
		a.apply_state({"pitch": 0.0, "veh": -1, "tool": "steel_axe" if i == 0 else "", "held": 0, "build": false}, null)
	for i in 30:
		await get_tree().physics_frame
	var cam := p.camera
	cam.top_level = true
	cam.global_transform = Transform3D(Basis(), at + Vector3(0, 1.8, 0.5)).looking_at(at + Vector3(0, 1.1, -4.0), Vector3.UP)
	await _frames(5)
	await snap("coop")

func shot_aerial() -> void:
	Settings.set_value(&"moving_sun", false, false)
	await look(Vector3(40, 170, 220), Vector3(-30, 0, -40))
	await snap("aerial")

func shot_ground() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var c: Vector3 = world.starter_forest
	await look(c + Vector3(50, 8, 55), c)
	await snap("ground")

func shot_junction() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var j := World.ring_point(0.0)
	await look(Vector3(j.x + 40, world.terrain.height_at(j.x + 40, j.z - 30) + 9, j.z - 30), Vector3(j.x, world.terrain.height_at(j.x, j.z), j.z))
	await snap("junction")

func shot_eagle() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var site: Vector3 = world.terrain.found_sites["Eagle's Rest"]
	var from := site + Vector3(-70, 25, 60)
	await look(from, site)
	await snap("eagle")

func shot_storeroad() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var s := World.STORE_POSITION
	await look(Vector3(s.x - 60, world.terrain.height_at(s.x - 60, s.z - 60) + 18, s.z - 60), Vector3(s.x, world.terrain.height_at(s.x, s.z), s.z))
	await snap("storeroad")

## The biggest cavern, from the mouth of one of its tunnels, and that mouth
## seen from inside the cavern.
func shot_cavern() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var net: CaveNetwork = world.network
	var best := 0
	for i in net.rooms.size():
		if net.rooms[i].links.size() > 0 and maxf(net.rooms[i].rx, net.rooms[i].rz) > maxf(net.rooms[best].rx, net.rooms[best].rz):
			best = i
	var room: Dictionary = net.rooms[best]
	var end := net._tube_end(room.links[0], best)
	var o: Vector3 = end.origin
	var out_dir: Vector3 = end.out
	var c: Vector3 = room.centre
	world.player.global_position = o + out_dir * 8.0
	# A floodlight on the camera, so the rock can be seen at all.
	var lamp := OmniLight3D.new()
	lamp.omni_range = 400.0
	lamp.light_energy = 3.0
	lamp.omni_attenuation = 0.4
	world.player.camera.add_child(lamp)
	await look(o + out_dir * 14.0 + Vector3(0, 2.5, 0), Vector3(c.x, float(room.floor) + 6.0, c.z))
	await snap("cavern")
	var toward := Vector3(c.x - o.x, 0, c.z - o.z).normalized()
	var floor_y := float(room.floor)
	var eye := Vector3(o.x, floor_y + 9.0, o.z) + toward * 32.0
	world.player.global_position = eye
	await look(eye, Vector3(o.x, floor_y + 4.0, o.z))
	await snap("cavemouth")
	var low := Vector3(o.x, floor_y + 1.4, o.z) + out_dir * 5.0
	await look(low, Vector3(o.x, floor_y, o.z) - out_dir * 4.0)
	await snap("caveseam")

## Every cave mouth, from out in front and a little above.
func shot_mouths() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var t: Terrain = world.terrain
	var only := int(args.get("n", "-1"))
	for i in t.caves.size():
		if only >= 0 and i != only:
			continue
		var c: Dictionary = t.caves[i]
		var e: Vector3 = c.entrance
		var d: Vector3 = c.dir
		var side := Vector3(-d.z, 0, d.x)
		var far := float(args.get("far", "26"))
		var eye := e - d * far + side * far * 0.6
		eye.y = maxf(t.height_at(eye.x, eye.z), e.y) + far * 0.25 + 1.5
		world.player.global_position = eye
		await look(eye, e + d * 6.0)
		print("mouth ", i, " ", c.name, " at ", e, " dir ", d)
		await snap("mouth_%d" % i)

## Inside each entrance hall, looking in from the end of the way down.
func shot_halls() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var t: Terrain = world.terrain
	var lamp := OmniLight3D.new()
	lamp.omni_range = 120.0
	lamp.light_energy = 2.0
	world.player.camera.add_child(lamp)
	var only := int(args.get("n", "-1"))
	for i in t.caves.size():
		if only >= 0 and i != only:
			continue
		var c: Dictionary = t.caves[i]
		var e: Vector3 = c.entrance
		var d: Vector3 = c.dir
		var z_end := Cave.SHAFT_LENGTH + Cave.TUNNEL_LENGTH
		var floor_y := float(c.ground) - Cave.CHAMBER_DROP
		var eye := e + d * (z_end - 4.0)
		eye.y = floor_y + 2.5
		world.player.global_position = eye
		await look(eye, eye + d * 20.0 + Vector3(0, 1.5, 0))
		await snap("hall_%d" % i)

## Down the way in of one cave, a frame every few metres.
func shot_walkin() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var t: Terrain = world.terrain
	var c: Dictionary = t.caves[int(args.get("n", "0"))]
	var e: Vector3 = c.entrance
	var d: Vector3 = c.dir
	var z := 0.0
	var k := 0
	while z < Cave.SHAFT_LENGTH + Cave.TUNNEL_LENGTH + 10.0:
		var eye := e + d * z + Vector3(0, Cave.floor_at(z) + 1.7, 0)
		world.player.global_position = eye
		await look(eye, eye + d * 10.0 + Vector3(0, Cave.floor_at(z + 10.0) - Cave.floor_at(z), 0))
		await snap("walk_%d" % k)
		z += 8.0
		k += 1

## From just outside each door, looking in along the way in.
func shot_doors() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var t: Terrain = world.terrain
	var only := int(args.get("n", "-1"))
	var back := float(args.get("back", "3"))
	for i in t.caves.size():
		if only >= 0 and i != only:
			continue
		var c: Dictionary = t.caves[i]
		var e: Vector3 = c.entrance
		var d: Vector3 = c.dir
		var eye := e - d * back + Vector3(0, 1.7, 0)
		world.player.global_position = eye
		await look(eye, eye + d * 20.0 - Vector3(0, 2.0, 0))
		await snap("door_%d" % i)

## Where each road ends at a place: the last stretch, from behind and above.
func shot_roadends() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var t: Terrain = world.terrain
	var i := 0
	for rp in t.road_paths:
		if String(rp.style) != "dirt":
			continue
		var path: Array = rp.path
		var end: Vector3 = path[path.size() - 1]
		var back: Vector3 = t._point_along(path, maxf(0.0, t._path_length(path) - 40.0))
		var eye := back + Vector3(0, 0, 0)
		eye.y = t.height_at(back.x, back.z) + 9.0
		end.y = t.height_at(end.x, end.z) + 1.0
		world.player.global_position = eye
		await look(eye, end)
		print("roadend ", i, " at ", end)
		await snap("roadend_%d" % i)
		i += 1

## Each place with a drive or spur, from back along its road.
func shot_places() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var t: Terrain = world.terrain
	var i := 0
	for place in t.road_ends:
		var end: Vector3 = t.road_ends[place]
		var road_path: Array = []
		for rp in t.road_paths:
			var path: Array = rp.path
			if (path[path.size() - 1] as Vector3).distance_to(end) < 0.5:
				road_path = path
		if road_path.is_empty():
			continue
		var span := t._path_length(road_path)
		var back: Vector3 = t._point_along(road_path, maxf(0.0, span - 30.0))
		var dir := Vector3(end.x - back.x, 0, end.z - back.z).normalized()
		var eye := back - dir * 6.0 + Vector3(0, 0, 0)
		eye.y = t.height_at(eye.x, eye.z) + 7.0
		var at := end + dir * 10.0
		at.y = t.height_at(at.x, at.z) + 2.0
		world.player.global_position = eye
		await look(eye, at)
		print("place ", i, " ", place)
		await snap("place_%d" % i)
		i += 1

func shot_yardtop() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var d: Vector3 = world.depot.global_position
	var eye := d + Vector3(-12, 70, 0.01)
	world.player.global_position = eye
	await look(eye, d + Vector3(-12, 0, 0))
	await snap("yardtop")

func shot_depot() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var d: Vector3 = world.depot.global_position
	for k in 4:
		var a := TAU * float(k) / 4.0 + 0.4
		var eye := d + Vector3(cos(a), 0, sin(a)) * 30.0
		eye.y = world.terrain.height_at(eye.x, eye.z) + 5.0
		world.player.global_position = eye
		await look(eye, d)
		await snap("depot_%d" % k)

func shot_machinecfg() -> void:
	var m := world.plot.place(GameData.building(&"sawmill"), Vector2i(0, 0), 0, false) as InlineMachine
	await get_tree().process_frame
	m.set_setting(&"width_cm", 15)
	world.hud.visible = true
	world.hud.machine_config.open(m)
	for i in 10:
		await get_tree().process_frame
	await snap("machinecfg")

func shot_padpanel() -> void:
	var pad := world.plot.place(GameData.building(&"pad_loader"), Vector2i(0, 0), 0, false) as VehiclePad
	await get_tree().process_frame
	pad.paint = VehiclePad.PAINTS[6][1]
	world.hud.visible = true
	world.hud.pad_panel.open(pad)
	for i in 10:
		await get_tree().process_frame
	await snap("padpanel")

func shot_ladder() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var truck := Hauler.new()
	truck.setup(world.manager, 0, &"hauler")
	truck.terrain = world.terrain
	world.add_child(truck)
	var at := Vector3(20, 0, 30)
	truck.global_position = Vector3(at.x, world.terrain.height_at(at.x, at.z) + truck.spawn_height(), at.z)
	for i in 90:
		await get_tree().physics_frame
	await look(truck.global_position + Vector3(-7, 3, 4), truck.global_position + Vector3(0, 1, -1))
	await snap("ladder")

func shot_bike() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var bike := Hauler.new()
	bike.setup(world.manager, 0, &"dirtbike")
	bike.terrain = world.terrain
	world.add_child(bike)
	var at := Vector3(20, 0, 30)
	bike.global_position = Vector3(at.x, world.terrain.height_at(at.x, at.z) + bike.spawn_height(), at.z)
	for i in 90:
		await get_tree().physics_frame
	await look(bike.global_position + Vector3(-3, 1.5, 1.5), bike.global_position)
	await snap("bike")

## One of each of the main species, photographed where it grows.
func shot_trees() -> void:
	await _tree_shots(["Pine", "Oak", "Birch", "Maple", "Palm", "Ironwood"])

func shot_ebony() -> void:
	Settings.set_value(&"moving_sun", false, false)
	# Far off, it sleeps as a note until someone comes near: go to one first.
	for field in world.tree_fields:
		if String(field.species[0].name) != "Ebony":
			continue
		for key in field._tiles:
			for d in field._tiles[key]:
				world.player.global_position = field.to_global(d.position) + Vector3(0, 2, 0)
				break
			break
		for key in field.alive:
			world.player.global_position = (key as Node3D).global_position + Vector3(0, 2, 0)
			break
	for i in 900:
		if world.trees().any(func(t): return t.species == "Ebony"):
			break
		await get_tree().physics_frame
	await _tree_shots(["Ebony"])

## A belt, a ramp and a belt at the ramp's top, with pieces riding up it:
## frames from the side as they cross each join.
func shot_rampline() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var plot: Plot = world.plot
	var S := Plot.SUB
	var base := Vector2i(4 * S, 0)
	var a := plot.place(GameData.building(&"conveyor"), base + Vector2i(0, 4 * S), 0, false)
	plot.place(GameData.building(&"conveyor_ramp"), base, 0, false)
	plot.place(GameData.building(&"conveyor"), base + Vector2i(0, -4 * S), 0, false, 2.0)
	var start: Vector3 = a.global_transform * Vector3(0, 0.6, 1.5)
	var mid: Vector3 = a.global_transform * Vector3(0, 1.0, -4.0)
	world.player.global_position = mid + Vector3(14, 0, 0)
	await look(mid + Vector3(12, 4.0, 3.0), mid)
	print("line from ", start, " mid ", mid)
	var kinds := [[&"ore_iron", Solid.chunk(0.02)], [&"lumber_pine", Solid.box(Vector3(0.3, 0.1, 1.2))],
		[&"gem_ruby", Solid.chunk(0.004)], [&"ore_copper", Solid.chunk(0.1)]]
	for i in 16:
		var k: Array = kinds[i % kinds.size()]
		world.manager.spawn(k[0], Transform3D(Basis(), start), 0, Vector3.ZERO, k[1])
		await _frames(20)
		if i % 2 == 1:
			await snap("rampline_%02d" % i)
			for it in world.manager.free_items():
				if it.global_position.distance_to(mid) < 12.0:
					print("  ", it.item_id, " ", it.global_position, " vis ", it.visible, " in tree ", it.is_visible_in_tree())

func _tree_shots(want: Array) -> void:
	world.hud.visible = false
	for i in 60:
		await get_tree().physics_frame
	var cam := world.player.camera
	cam.top_level = true
	for species in want:
		var best: ChoppableTree = null
		for t in world.trees():
			if t.species == species and t.standing() and (best == null or t.trunk_height > best.trunk_height):
				best = t
		if best == null:
			print("no ", species)
			continue
		var at := best.global_position
		var h := best.trunk_height
		var back := Vector3(0.6, 0, 1).normalized() * (h * 1.5 + (1.5 if h < 4.0 else 6.0))
		var eye := at + back
		eye.y = maxf(world.terrain.height_at(eye.x, eye.z) + 1.7, at.y + 1.7)
		world.player.global_position = at + back * 0.5
		for i in 20:
			await get_tree().physics_frame
		cam.global_transform = Transform3D(Basis(), eye).looking_at(at + Vector3(0, h * 0.55, 0), Vector3.UP)
		await _frames(10)
		await snap("tree_" + species.to_lower())

func shot_perflog() -> void:
	world.hud.show_debug = true
	for i in 200:
		await get_tree().process_frame
	await snap("perflog")

## Straight down over the quarry and the road past it.
func shot_quarrytop() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var c := World.QUARRY_CENTRE + Vector3(80, 0, 0)
	c.y = world.terrain.height_at(c.x, c.z)
	world.player.global_position = c + Vector3(0, 250, 0)
	for i in 60:
		await get_tree().process_frame
	await look(c + Vector3(0, 420, 1), c)
	await snap("quarry_top")
	var j := World.quarry_gate()
	j.y = world.terrain.height_at(j.x, j.z)
	await look(j + Vector3(40, 25, 40), j)
	await snap("quarry_junction")

## The quarry pit from above its rim, and from its floor looking up the haul road.
func shot_quarry() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var c := World.QUARRY_CENTRE
	c.y = world.terrain.height_at(c.x, c.z)
	world.player.global_position = c + Vector3(0, 40, 0)
	for i in 60:
		await get_tree().process_frame
	await look(c + Vector3(-60, 75, 130), c)
	await snap("quarry_above")
	await look(c + Vector3(0, 3, 0), c + Vector3(40, 18, 60))
	await snap("quarry_floor")

## Hollow Isle: the road over the stepping stone, and the gorge into the
## Hidden Valley.
func shot_hollow() -> void:
	Settings.set_value(&"moving_sun", false, false)
	var t: Terrain = world.terrain
	var v := Vector3(-1470, 0, 1480)
	v.y = t.height_at(v.x, v.z)
	world.player.global_position = v + Vector3(0, 30, 0)
	for i in 90:
		await get_tree().process_frame
	await look(Vector3(-1100, 180, 1150), Vector3(-1350, 0, 1350))
	await snap("hollow_approach")
	await look(v + Vector3(140, 60, -140), v)
	await snap("hollow_valley")

## A line-up of ore and gem chunks in the ground, for judging their looks.
func shot_ores() -> void:
	Settings.set_value(&"moving_sun", false, false)
	world.hud.visible = false
	var ids := []
	for id in GameData.items:
		if String(id).begins_with("gem_") or String(id).begins_with("ore_"):
			ids.append(id)
	var base := Vector3(-24, World.PLOT_GROUND + 0.05, -20)
	for i in ids.size():
		var rock := OreRock.new()
		rock.manager = world.manager
		rock.ore_item = ids[i]
		rock.seed_form(1000 + i)
		rock.embed = 0.25
		rock.volume = 0.9
		rock.position = base + Vector3(float(i % 7) * 3.4, 0, float(i / 7) * 4.0)
		world.add_child(rock)
	world.player.global_position = base + Vector3(10, 0, 22)
	await _frames(30)
	await look(base + Vector3(10.2, 9.0, 20.0), base + Vector3(10.2, 0, 5.5))
	await snap("ores")

func shot_filter() -> void:
	Settings.set_value(&"moving_sun", false, false)
	Economy.from_dict({"money": 90000, "day": 1})
	var f := world.plot.place(GameData.building(&"filter"), Vector2i(-40, -40), Vector3i.ZERO, false, 1.5) as Filter
	f.set_rules([{"type": "wood", "stage": "plank", "let": true},
		{"type": "ore", "sub": "iron", "size": "over", "m3": 0.4, "let": false}], false)
	await _frames(20)
	var at := f.global_position
	await look(at + Vector3(3, 3.5, 3.5), at + Vector3(0, 1.4, 0))
	await snap("filter_belt")
	world.hud.visible = true
	world.hud.filter_panel.open(f)
	await _frames(10)
	await snap("filter_panel")

## The utility trailer and the mower trailer, gates up and down.
func shot_trailers() -> void:
	Settings.set_value(&"moving_sun", false, false)
	world.hud.visible = false
	var base := Vector3(-12, World.PLOT_GROUND + 0.1, -12)
	var made: Array = []
	for i in 2:
		var t := Hauler.new()
		t.setup(world.manager, 0, &"trailer" if i == 0 else &"mower_trailer")
		world.add_child(t)
		t.global_position = base + Vector3(float(i) * 5.0, t.spawn_height(), 0)
		made.append(t)
	await _frames(60)
	await look(base + Vector3(-3.5, 3.2, 7.5), base + Vector3(2.5, 0.6, 0))
	await snap("trailers_shut")
	for t in made:
		t.set_ramps(true)
	await _frames(20)
	await snap("trailers_open")

## A black opal as it lies in the ground, half buried and fully out.
func shot_opal() -> void:
	Settings.set_value(&"moving_sun", false, false)
	world.hud.visible = false
	var base := Vector3(-12, World.PLOT_GROUND + 0.05, -12)
	var ids := [&"gem_obsidian", &"gem_black_opal", &"gem_black_opal"]
	var embeds := [0.3, 0.3, 0.7]
	for i in ids.size():
		var rock := OreRock.new()
		rock.manager = world.manager
		rock.ore_item = ids[i]
		rock.seed_form(77 + i)
		rock.embed = embeds[i]
		rock.volume = 0.5
		rock.position = base + Vector3(float(i) * 2.2, 0, 0)
		world.add_child(rock)
	world.player.global_position = base + Vector3(2.2, 0, 8)
	await _frames(30)
	await look(base + Vector3(2.2, 1.6, 3.6), base + Vector3(2.2, 0.2, 0))
	await snap("opal")

## Where a tunnel meets an Abyss cavern: the join that did not fit (tunnel 50
## into cavern 57), from inside the cavern.
func shot_join() -> void:
	Settings.set_value(&"moving_sun", false, false)
	world.hud.visible = false
	var net: CaveNetwork = world.network
	var end := net._tube_end(50, 57)
	var o: Vector3 = end.origin
	var out_dir: Vector3 = end.out
	var lamp := OmniLight3D.new()
	lamp.omni_range = 200.0
	lamp.light_energy = 3.0
	lamp.omni_attenuation = 0.4
	world.player.camera.add_child(lamp)
	var eye := o - out_dir * 16.0 + Vector3(0, 4.0, 0)
	world.player.global_position = eye
	await look(eye, o + Vector3(0, 3.0, 0))
	await snap("join")

## Every tunnel mouth into an Abyss cavern, from in the tunnel and from the
## cavern: for hunting joins that do not meet.
func shot_abyssjoins() -> void:
	Settings.set_value(&"moving_sun", false, false)
	world.hud.visible = false
	var net: CaveNetwork = world.network
	var lamp := OmniLight3D.new()
	lamp.omni_range = 120.0
	lamp.light_energy = 2.5
	lamp.omni_attenuation = 0.5
	world.player.camera.add_child(lamp)
	var n := 0
	for ti in net.tunnels.size():
		var t: Dictionary = net.tunnels[ti]
		for ri in [int(t.a), int(t.b)]:
			if int(net.rooms[ri].kind) != CaveNetwork.Kind.ABYSS and int(net.rooms[int(t.a)].kind) != CaveNetwork.Kind.ABYSS \
					and int(net.rooms[int(t.b)].kind) != CaveNetwork.Kind.ABYSS:
				continue
			var e := net._tube_end(ti, ri)
			var o: Vector3 = e.origin
			var out: Vector3 = e.out
			var r := float(t.get("ra", t.radius)) if ri == int(t.a) else float(t.get("rb", t.radius))
			var floor_y := o.y - r * CaveNetwork.FLOOR_CUT
			var inside := o + out * 12.0
			inside.y = floor_y + 2.0
			world.player.global_position = inside
			await look(inside, Vector3(o.x, floor_y + 2.0, o.z) - out * 6.0)
			await snap("aj_%d_%d_in" % [ti, ri])
			var room_side := o - out * 14.0
			room_side.y = floor_y + 3.0
			world.player.global_position = room_side
			await look(room_side, Vector3(o.x, floor_y + 2.0, o.z))
			await snap("aj_%d_%d_out" % [ti, ri])
			n += 1
	print("ABYSS JOINS ", n)

## From partway down each cave's way in, looking on into its first cavern.
func shot_entryviews() -> void:
	Settings.set_value(&"moving_sun", false, false)
	world.hud.visible = false
	var lamp := OmniLight3D.new()
	lamp.omni_range = 120.0
	lamp.light_energy = 2.5
	lamp.omni_attenuation = 0.5
	world.player.camera.add_child(lamp)
	for i in world.caves.size():
		var cave: Cave = world.caves[i]
		var z := Cave.SHAFT_LENGTH + Cave.TUNNEL_LENGTH - 8.0
		var eye := cave.to_global(Vector3(0, Cave.floor_at(z) + 1.8, z))
		var at := cave.to_global(Vector3(0, -Cave.CHAMBER_DROP + 1.5, z + 20.0))
		world.player.global_position = eye
		await look(eye, at)
		await snap("ev_%02d" % i)

## From inside the tunnel, looking into the cavern, at the joins listed.
func shot_joinsin() -> void:
	Settings.set_value(&"moving_sun", false, false)
	world.hud.visible = false
	var net: CaveNetwork = world.network
	var lamp := OmniLight3D.new()
	lamp.omni_range = 120.0
	lamp.light_energy = 2.5
	lamp.omni_attenuation = 0.5
	world.player.camera.add_child(lamp)
	for pair in [[48, 54], [49, 55], [50, 57], [51, 59], [55, 61], [46, 52], [48, 56], [52, 60], [10, 25], [16, 36], [53, 60]]:
		var e := net._tube_end(pair[0], pair[1])
		var o: Vector3 = e.origin
		var out: Vector3 = e.out
		var t: Dictionary = net.tunnels[pair[0]]
		var r := float(t.get("ra", t.radius)) if pair[1] == int(t.a) else float(t.get("rb", t.radius))
		var fy := o.y - r * CaveNetwork.FLOOR_CUT
		var eye := o + out * 10.0
		eye.y = fy + 1.8
		world.player.global_position = eye
		await look(eye, Vector3(o.x, fy + 1.8, o.z) - out * 8.0)
		await snap("ji_%d_%d" % pair)

## One chunk of every ore in the ground, with a mined piece of it in front.
func shot_ore_looks() -> void:
	Settings.set_value(&"moving_sun", false, false)
	world.hud.visible = false
	var ores := ["ore_iron", "ore_copper", "ore_gold", "ore_silver", "ore_cobalt", "ore_sunstone", "ore_tin",
		"ore_zinc", "ore_magnetite", "ore_nickel", "ore_bismuth", "ore_tungsten", "ore_platinum", "ore_starmetal"]
	var base := world.plot.global_position + Vector3(-16, 0, 26)
	for i in ores.size():
		var at := base + Vector3(float(i % 7) * 4.5, 0, float(i / 7) * 6.0)
		at.y = world.terrain.height_at(at.x, at.z)
		var rock := OreRock.new()
		rock.manager = world.manager
		rock.ore_item = StringName(ores[i])
		rock.seed_form(100 + i)
		rock.embed = 0.35
		rock.volume = 1.6
		world.add_child(rock)
		rock.global_position = at
		var piece := world.manager.spawn(StringName(ores[i]), Transform3D(Basis(), at + Vector3(0, 0.6, 2.2)), 0, Vector3.ZERO, Solid.chunk(0.45))
		if piece != null:
			piece.freeze = true
	for i in 30:
		await get_tree().physics_frame
	var mid := base + Vector3(13.5, 0, 3)
	mid.y = world.terrain.height_at(mid.x, mid.z)
	await look(mid + Vector3(0, 9, 17), mid + Vector3(0, 0.5, 0))
	await snap("ores_all")
	var near := base + Vector3(0, 0, 0)
	near.y = world.terrain.height_at(near.x, near.z)
	await look(near + Vector3(5, 3.2, 6), near + Vector3(4.5, 0.6, 0.8))
	await snap("ores_close")
	near = base + Vector3(0, 0, 6)
	near.y = world.terrain.height_at(near.x, near.z)
	await look(near + Vector3(9, 3.2, 6), near + Vector3(9, 0.6, 0.8))
	await snap("ores_close2")

## The friends' list: a player blown up by TNT, ore going up, a player on a
## crane, and the crusher.
func shot_slop() -> void:
	Settings.set_value(&"moving_sun", false, false)
	world.hud.visible = false
	var p: Player = world.player
	var base := world.plot.global_position + Vector3(-14, 0, 24)
	base.y = world.terrain.height_at(base.x, base.z)
	# TNT among ore, the camera well back.
	for i in 3:
		var rock := OreRock.new()
		rock.manager = world.manager
		rock.ore_item = [&"ore_iron", &"ore_copper", &"ore_platinum"][i]
		rock.seed_form(300 + i)
		rock.embed = 0.35
		rock.volume = 1.2
		world.add_child(rock)
		var at := base + Vector3(float(i - 1) * 2.6, 0, 0)
		at.y = world.terrain.height_at(at.x, at.z)
		rock.global_position = at
	p.global_position = base + Vector3(0, 0, 30)
	await _frames(20)
	var stick := world.manager.spawn(&"tnt_stick", Transform3D(Basis(), base + Vector3(0, 0.8, 1.2)), 0)
	await _frames(20)
	await look(base + Vector3(6, 4, 10), base + Vector3(0, 0.8, 0))
	await snap("slop_tnt_lit")
	Blast.light(stick, world.manager, 0.05)
	await _frames(12)
	await snap("slop_tnt_boom")
	await _frames(60)
	await snap("slop_tnt_after")
	# The player blown sky high.
	var cam := p.camera
	cam.top_level = false
	p.global_position = base + Vector3(10, 0.2, 6)
	await _frames(30)
	var stick2 := world.manager.spawn(&"tnt_stick", Transform3D(Basis(), p.global_position + Vector3(0.8, 0.3, 0.5)), 0)
	Blast.light(stick2, world.manager, 0.05)
	await _frames(24)
	await snap("slop_launched")
	for i in 60 * 10:
		await get_tree().physics_frame
		if not p.knocked():
			break
	# Hanging from a crane.
	var truck := Hauler.new()
	truck.setup(world.manager, 0, &"crane_truck")
	world.add_child(truck)
	var tpos := base + Vector3(-12, 0, 12)
	tpos.y = world.terrain.height_at(tpos.x, tpos.z) + truck.spawn_height()
	truck.global_position = tpos
	await _frames(60)
	truck.rig.set_operating(true)
	var frame := truck.global_transform
	p.global_position = frame * Vector3(3.6, 0.0, 1.0)
	await _frames(20)
	truck.rig._take_player(p)
	truck.rig.target = truck.rig.clamp_target(truck.rig.target + Vector3(0, 2.5, 0))
	for i in 150:
		await get_tree().physics_frame
	await _frames(10)
	await snap("slop_crane")
	truck.rig.drop()
	for i in 60 * 12:
		await get_tree().physics_frame
		if not p.knocked():
			break

## A blast close up, for judging the fireball.
func shot_blastfx() -> void:
	Settings.set_value(&"moving_sun", false, false)
	world.hud.visible = false
	var at := world.plot.global_position + Vector3(-10, 0, 20)
	at.y = world.terrain.height_at(at.x, at.z) + 0.3
	world.player.global_position = at + Vector3(0, 0, 40)
	await look(at + Vector3(0, 2.5, 7), at + Vector3(0, 1, 0))
	Blast._effects(get_tree().current_scene, at)
	for k in [2, 6, 14, 40]:
		await _frames(k)
		await snap("blast_%d" % k)

## A player going through the crusher, and what comes out.
func shot_crush() -> void:
	Settings.set_value(&"moving_sun", false, false)
	world.hud.visible = false
	var p: Player = world.player
	var base := world.plot.global_position + Vector3(-14, 0, 24)
	base.y = world.terrain.height_at(base.x, base.z)
	# Into the crusher.
	var m := InlineMachine.new()
	m.setup_machine(world.manager, PlayerState.def_at_tier(&"crusher", 1), 0)
	var mpos := base + Vector3(14, 0, 16)
	mpos.y = world.terrain.height_at(mpos.x, mpos.z) + 0.05
	m.position = mpos
	world.add_child(m)
	await _frames(20)
	p.global_position = m.global_transform * Vector3(0, InlineMachine.DECK_THICKNESS + m.canopy_height() + InlineMachine.HOPPER_DEPTH + 0.8, 0)
	for i in 60 * 3:
		await get_tree().physics_frame
		if p.crushed() and i > 140:
			break
	await _frames(5)
	await snap("slop_crusher")

## The TNT on the hardware store's shelf.
func shot_tntshelf() -> void:
	var s: Store = world.store
	for i in 120:
		await get_tree().process_frame
	for slot in s.slots:
		if slot.target == &"tnt_stick" and slot.item != null:
			var at: Vector3 = (slot.item as Node3D).global_position
			var out: Vector3 = (slot.item as Node3D).global_transform.basis.z
			await look(at + out * 2.2 + Vector3(0.6, 0.6, 0), at)
			await snap("tnt_shelf")
			await look(at + out * 5.5 + Vector3(2.0, 1.2, 0), at)
			await snap("tnt_shelf_wide")
			return
	print("no TNT on the shelf")
