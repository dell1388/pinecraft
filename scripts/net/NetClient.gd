class_name NetClient
extends Node

## A co-op guest's end. This world is a picture of the host's: nothing here
## grows, falls or runs on its own. What the host sends is built and moved
## here; what the player presses is sent to the host, whose copy of this
## player does it.

const INPUT_RATE := 30.0
const WHEEL := NetHost.WHEEL

var world: Node
var _mirror: Node3D                    ## trees, rocks and vehicles live here
var _nodes: Dictionary = {}            ## id -> node (or plot record node)
var _kinds: Dictionary = {}            ## id -> kind
var _goal: Dictionary = {}             ## id -> Transform3D the host last said
var _me: int = -1
var _acc: float = 0.0
var _last_tick: int = -1
var _wheels: Dictionary = {}           ## wheel pose id -> RigidBody3D
var _last_veh: int = -2
## The last time the host moved this player itself; sent back with where we
## are, so the host knows we have caught up.
var _warp_seq: int = -1
var _rel: Dictionary = {}              ## id -> id of what it rides on
## The vehicle this player is driving here (its id), or -1.
var _local_veh: int = -1

func _ready() -> void:
	Net.client_side = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mirror = Node3D.new()
	_mirror.name = "Mirror"
	world.add_child(_mirror)
	# Built as the wrong map (the host's word came late): build it again.
	Net.map_known.connect(_check_map)
	# Now the world is built, connect (or, already connected, say hello).
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer \
			and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_hello()
		return
	Net.joined.connect(_hello, CONNECT_ONE_SHOT)
	Net.join_failed.connect(func(reason: String): _give_up(reason), CONNECT_ONE_SHOT)
	var err := Net.join(Net.address, Net.port)
	if err != "":
		_give_up(err)

## The world here has to be the host's map; if it is not, it is built again
## as that one (still connected) before saying hello.
func _check_map(id: StringName) -> bool:
	if id == &"" or id == WorldMap.current or _leaving:
		return false
	_leaving = true
	MainMenu.skip_once = true
	get_tree().call_deferred("change_scene_to_file", "res://scenes/boot.tscn")
	return true

func _hello() -> void:
	if _check_map(Net.host_map):
		return
	Net.rpc_id(1, "c_hello", Net.player_name)
	# You in the shirt the others see you in.
	var me: Variant = world.get("player") if world != null else null
	if me is Player and (me as Player).avatar != null:
		(me as Player).avatar.set_look("", Avatar.color_for(multiplayer.get_unique_id()))
	if OS.has_environment("NET_TRACE"):
		print("[guest] hello sent")

func _exit_tree() -> void:
	if Net.client_side == self:
		Net.client_side = null

func on_host_gone() -> void:
	_give_up("the host has gone")

func _give_up(reason: String) -> void:
	if _leaving:
		return
	_leaving = true
	world.call_deferred("host_gone", reason)

# --- Sending ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# Driving here: the player sits in the seat of the truck driven here.
	var lv := _nodes.get(_local_veh, null) as Hauler
	if lv != null and is_instance_valid(lv):
		var me: Player = world.get("player")
		if me != null:
			me.global_position = lv.seat_transform().origin
			me.velocity = Vector3.ZERO
	if not Net.is_client() or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_acc += delta
	if _acc < 1.0 / INPUT_RATE:
		return
	_acc = 0.0
	var p: Player = world.get("player")
	var state := PlayerInput.capture()
	if p != null:
		# Menus and the journal hold nothing down.
		if p._ui_blocking or not p._mouse_captured:
			state = {"a": [], "k": [], "b": []}
		state.yaw = p.rotation.y
		state.pitch = p.camera.rotation.x
		if not p.driving() and _warp_seq >= 0:
			var at := p.global_position
			state.pos = [at.x, at.y, at.z]
			state.ws = _warp_seq
		var v := _nodes.get(_local_veh, null) as Hauler
		if v != null and is_instance_valid(v):
			var vs := {"id": _local_veh, "x": NetHost._pose(v.global_transform)}
			var wheels: Array = []
			for body in v.wheel_bodies:
				wheels.append(NetHost._pose(body.global_transform))
			vs.w = wheels
			if v.rig != null and v.rig.has_crane():
				vs.tg = v.rig.target
				vs.ty = v.rig.target_yaw
			if v.loader != null:
				vs.ld = [v.loader.lift, v.loader.tilt]
			state.veh = vs
	Net.rpc_id(1, "c_input", state)

## A key or button pressed here, for the host to act on.
func send_press(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		send_event({"t": "key", "code": int(k.keycode), "phys": int(k.physical_keycode)})
	elif event is InputEventMouseButton:
		send_event({"t": "btn", "b": int((event as InputEventMouseButton).button_index)})

func send_event(ev: Dictionary) -> void:
	Net.rpc_id(1, "c_event", ev)

# --- Receiving -------------------------------------------------------------------------

func on_batch(batch: Array) -> void:
	if OS.has_environment("NET_TRACE") and batch.size() > 20:
		print("[guest] batch of ", batch.size())
	for e: Dictionary in batch:
		match String(e.t):
			"spawn":
				_spawn(e)
			"gone":
				_gone(int(e.id))
			"state":
				_state(int(e.id), e.s)
			"econ":
				var plot: Plot = world.get("plot")
				if e.has("land") and plot != null and plot.tier != int(e.land):
					plot._apply_expansion(int(e.land))
				Economy.apply_remote(e.e)
				PlayerState.from_dict(e.p)
				var quests: Variant = world.get("quests")
				if quests != null and not (e.q as Dictionary).is_empty():
					quests.call("from_dict", e.q)
			"you":
				_me = int(e.id)
				# Moves for this player that came before we knew it was us.
				_goal.erase(_me)
				var avatar: Variant = _nodes.get(_me, null)
				if avatar != null and avatar is Avatar:
					(avatar as Node).queue_free()
					_nodes[_me] = world.get("player")
			"view":
				_view(e)
			"recover":
				var rv := _nodes.get(int(e.id), null) as Hauler
				if rv != null and is_instance_valid(rv):
					rv.move_to(NetHost._unpose(e.x))
			"warp":
				var wp: Player = world.get("player")
				if wp != null:
					wp.stand_up()
					var x: Array = e.x
					wp.global_position = Vector3(float(x[0]), float(x[1]), float(x[2]))
					wp.velocity = Vector3.ZERO
				_warp_seq = int(e.s)
			"knock":
				var kp: Player = world.get("player")
				if kp != null:
					var v: Array = e.v
					kp.knock(Vector3(float(v[0]), float(v[1]), float(v[2])))
			"grind":
				var gp: Player = world.get("player")
				if gp != null:
					var gx: Array = e.x
					gp.grind(Vector3(float(gx[0]), float(gx[1]), float(gx[2])), float(e.get("s", 2.6)))
			"crush":
				var cp: Player = world.get("player")
				if cp != null:
					var cx: Array = e.x
					cp.crush(Vector3(float(cx[0]), float(cx[1]), float(cx[2])))
			"msg":
				var p: Player = world.get("player")
				if p != null:
					p.interacted.emit(String(e.m))

var _motion_count := 0
func on_motion(ids: PackedInt32Array, poses: PackedFloat32Array, carriers: PackedInt32Array, tick: int) -> void:
	_motion_count += ids.size()
	for i in ids.size():
		var id := ids[i]
		var t := Transform3D(Basis(Quaternion(poses[i * 7 + 3], poses[i * 7 + 4], poses[i * 7 + 5], poses[i * 7 + 6])),
			Vector3(poses[i * 7], poses[i * 7 + 1], poses[i * 7 + 2]))
		if id == _me:
			# This player walks here; in a truck it is where the host has it.
			var p: Player = world.get("player")
			if p != null and p.driving() and _local_veh < 0:
				p.global_position = t.origin
			continue
		var by := carriers[i] if i < carriers.size() else 0
		if by != 0:
			_rel[id] = by
		else:
			_rel.erase(id)
		_goal[id] = t
	_last_tick = tick

## Moving things glide to where the host last put them.
var _trace_t := 0.0
## How long to wait for the host's world before giving up on it, so a join
## that half-worked never leaves you standing in an empty copy.
const WORLD_WAIT := 40.0
var _waited: float = 0.0
var _leaving: bool = false

func _process(delta: float) -> void:
	if not _leaving:
		if not Net.is_client():
			_give_up("lost the host")
		elif _me < 0:
			_waited += delta
			if _waited > WORLD_WAIT:
				_give_up("the host did not send its world")
	if OS.has_environment("NET_TRACE"):
		_trace_t += delta
		if _trace_t > 2.0:
			_trace_t = 0.0
			print("[guest] alive frame=%d nodes=%d me=%d motion=%d pos=%s" % [Engine.get_process_frames(), _nodes.size(), _me, _motion_count, world.get("player").global_position])
	var k := clampf(delta * 18.0, 0.0, 1.0)
	# Things in the world first, then what rides on them - in a bed, on a
	# rack, behind a truck, a wheel on its axle - in the frame of what
	# carries it, so it goes with its carrier however that moves here.
	for pass_rel in [false, true]:
		for id in _goal:
			if id == _me or _rel.has(id) != pass_rel or _is_local(id):
				continue
			var node: Node3D = null
			if id >= WHEEL:
				node = _wheels.get(id, null)
			else:
				node = _nodes.get(id, null) as Node3D
			if node == null or not is_instance_valid(node):
				continue
			var goal: Transform3D = _goal[id]
			var now := node.global_transform
			if pass_rel:
				var carrier := _nodes.get(int(_rel[id]), null) as Node3D
				if carrier == null or not is_instance_valid(carrier):
					continue
				var frame := carrier.global_transform
				now = frame.affine_inverse() * now
				if now.origin.distance_to(goal.origin) > 6.0:
					node.global_transform = frame * goal
					continue
				var rq := now.basis.get_rotation_quaternion().slerp(goal.basis.get_rotation_quaternion(), k)
				node.global_transform = frame * Transform3D(Basis(rq), now.origin.lerp(goal.origin, k))
				continue
			if now.origin.distance_to(goal.origin) > 6.0:
				node.global_transform = goal
				continue
			var q := now.basis.get_rotation_quaternion().slerp(goal.basis.get_rotation_quaternion(), k)
			node.global_transform = Transform3D(Basis(q), now.origin.lerp(goal.origin, k))
	# Loader buckets and cranes follow their vehicle.
	for id in _kinds:
		if _kinds[id] == "v":
			var v := _nodes.get(id, null) as Hauler
			if v != null and is_instance_valid(v) and v.loader != null:
				v.loader._pose(true)

func _pose_of(e: Dictionary) -> Transform3D:
	var x: PackedFloat32Array = e.get("x", PackedFloat32Array([0, 0, 0, 0, 0, 0, 1]))
	return Transform3D(Basis(Quaternion(x[3], x[4], x[5], x[6])), Vector3(x[0], x[1], x[2]))

func _spawn(e: Dictionary) -> void:
	var id := int(e.id)
	if _nodes.has(id):
		return
	var kind := String(e.k)
	var node: Node = null
	match kind:
		"i":
			var manager: LooseItemManager = world.get("manager")
			var item := manager.mirror_spawn(StringName(e.item), _pose_of(e), Solid.from_dict(e.dims))
			if item != null:
				# A picture: nothing here - the truck driven here above all -
				# bumps into it. The host's copy is the one that is hit.
				item.collision_layer = 0
				item.collision_mask = 0
				for a in e.get("limbs", []):
					item.add_limb(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), float(a[6]), float(a[7]),
						[], Color(0.42, 0.3, 0.2), float(a[8]) if (a as Array).size() > 8 else -1.0)
			node = item
		"t":
			var tree: Node3D = world.call("_build_tree", e.entry, int(e.seed))
			_mirror.add_child(tree)
			tree.global_transform = _pose_of(e)
			node = tree
		"r":
			var rock: Node3D = world.call("_build_rock", e.entry, int(e.seed))
			_mirror.add_child(rock)
			rock.global_transform = _pose_of(e)
			node = rock
		"b":
			node = _build(e)
		"v":
			var v := Hauler.new()
			v.setup(world.get("manager"), 0, StringName(e.veh))
			if e.has("paint"):
				v.paint_override = Color(float(e.paint[0]), float(e.paint[1]), float(e.paint[2]))
			v.terrain = world.get("terrain")
			_mirror.add_child(v)
			_solid_picture(v)
			v.global_transform = _pose_of(e)
			_passive_wheels.call_deferred(v, id)
			node = v
		"p":
			if id == _me:
				node = world.get("player")
			else:
				var a := Avatar.new()
				a.setup(String(e.get("name", "Player")), Avatar.color_for(int(e.get("peer", 1))))
				_mirror.add_child(a)
				a.global_transform = _pose_of(e)
				node = a
	if node == null:
		return
	_nodes[id] = node
	_kinds[id] = kind

## A vehicle's wheels, once it has built them: moved by the host too.
func _passive_wheels(v: Hauler, id: int) -> void:
	await get_tree().process_frame
	if not is_instance_valid(v):
		return
	for w in v.wheel_bodies.size():
		var body := v.wheel_bodies[w]
		if id != _local_veh:
			_solid_picture(body)
		_wheels[id + WHEEL * (w + 1)] = body

func _build(e: Dictionary) -> Node:
	var plot: Plot = world.get("plot")
	var def := PlayerState.def_at_tier(StringName(e.def), int(e.get("tier", 1)))
	if def == null:
		return null
	var size := Vector3i(int(e.size[0]), int(e.size[1]), int(e.size[2]))
	var tr: Array = e.get("trim", [def.trim.x, def.trim.y, def.trim.z])
	var trim := Vector3i(int(tr[0]), int(tr[1]), int(tr[2]))
	if size != def.size or trim != def.trim:
		def = Plot.resized(def, size, trim)
	var r: Array = e.rot
	var node := plot.place(def, Vector2i(int(e.cell[0]), int(e.cell[1])), Vector3i(int(r[0]), int(r[1]), int(r[2])),
		false, float(e.get("lift", 0.0)))
	if node != null:
		# Only a picture: the host's machines do the work. Still solid.
		_solid_picture(node)
	return node

## Switched off - nothing in it runs - but still there to walk into, stand
## on and aim at.
static func _solid_picture(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	_keep_solid(node)

static func _keep_solid(node: Node) -> void:
	if node is CollisionObject3D:
		(node as CollisionObject3D).disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	if node is RigidBody3D:
		(node as RigidBody3D).freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		(node as RigidBody3D).freeze = true
	for child in node.get_children():
		_keep_solid(child)

## The id the host knows a building (or anything) here by, or -1.
func id_of(node: Node) -> int:
	for id in _nodes:
		if _nodes[id] == node:
			return id
	return -1

## Asks the host to build, take down or change a building.
func send_build(ev: Dictionary) -> void:
	ev.t = "build"
	send_event(ev)

func _gone(id: int) -> void:
	var node: Variant = _nodes.get(id, null)
	var kind: String = _kinds.get(id, "")
	_nodes.erase(id)
	_kinds.erase(id)
	_goal.erase(id)
	_rel.erase(id)
	if id == _local_veh:
		_local_veh = -1
	if node == null or not is_instance_valid(node):
		return
	# A tree or rock gone on the host came down or broke up.
	if kind == "t":
		Sfx.play(&"fall", (node as Node3D).global_position + Vector3.UP * 2.0)
	elif kind == "r":
		Sfx.play(&"crack", (node as Node3D).global_position)
	match kind:
		"i":
			(world.get("manager") as LooseItemManager).despawn(node as LooseItem)
		"b":
			(world.get("plot") as Plot).drop_record(node as Node3D)
		"p":
			if id != _me:
				(node as Node).queue_free()
		"v":
			var v := node as Hauler
			for w in v.wheel_bodies.size():
				_wheels.erase(id + WHEEL * (w + 1))
				if is_instance_valid(v.wheel_bodies[w]):
					v.wheel_bodies[w].queue_free()
			v.queue_free()
		_:
			(node as Node).queue_free()

func _state(id: int, s: Variant) -> void:
	var node: Variant = _nodes.get(id, null)
	if node == null or not is_instance_valid(node) or s == null:
		return
	match String(_kinds.get(id, "")):
		"t":
			(node as ChoppableTree).net_apply(s)
			# Cut on the host: heard here too.
			Sfx.play(&"chop", (node as Node3D).global_position + Vector3.UP)
		"r":
			(node as OreRock).net_apply(s)
			Sfx.play(&"clink", (node as Node3D).global_position)
		"i":
			var item := node as LooseItem
			var want: Array = s.get("l", [])
			if want.size() != item.limbs.size() or item.limbs_to_array() != want:
				item.clear_limbs()
				for a in want:
					item.add_limb(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), float(a[6]), float(a[7]),
						[], Color(0.42, 0.3, 0.2), float(a[8]) if (a as Array).size() > 8 else -1.0)
		"b":
			if s.has("g"):
				node = _reshape(id, node as Node3D, s.g)
			if s.has("run") and (node as Node).get("running") != null:
				(node as Node).set("running", bool(s.run))
			if s.has("d") and (node as Node).has_method("from_dict") and not node is VehiclePad:
				(node as Node).call("from_dict", s.d)
				# Whatever that built (a finished plan's door) stays solid too.
				_keep_solid(node as Node)
		"v":
			_vehicle_state(node as Hauler, s)
		"p":
			var a := node as Avatar
			var veh: Node3D = _nodes.get(int(s.get("veh", -1)), null) as Node3D
			if a != null:
				a.apply_state(s, veh)
			elif node is Player and (node as Player).avatar != null:
				# You: what you carry and drag is the host's to say, so the
				# lumberjack you see in third person takes it from there too.
				(node as Player).avatar.apply_net_state(s)

## A building the host has moved, turned or resized: the same here.
func _reshape(id: int, node: Node3D, g: Array) -> Node3D:
	var plot: Plot = world.get("plot")
	var index := -1
	for i in plot.placed.size():
		if plot.placed[i].node == node:
			index = i
			break
	if index < 0:
		return node
	var rec: Dictionary = plot.placed[index]
	var cell := Vector2i(int(g[0]), int(g[1]))
	var rot := Vector3i(int(g[2]), int(g[3]), int(g[4]))
	var size := Vector3i(int(g[5]), int(g[6]), int(g[7]))
	var lift := float(g[8])
	var trim := Vector3i(int(g[9]), int(g[10]), int(g[11])) if g.size() > 11 else Vector3i.ZERO
	if rec.cell == cell and rec.rot == rot and (rec.def as BuildingDef).size == size \
			and (rec.def as BuildingDef).trim == trim and is_equal_approx(float(rec.get("lift", 0.0)), lift):
		return node
	plot.edit(index, cell, rot, size, lift, trim)
	var fresh: Node3D = plot.placed[index].node
	if fresh != null and fresh != node:
		_solid_picture(fresh)
		_nodes[id] = fresh
	return fresh

## Whether this is the vehicle driven here, or one of its wheels.
func _is_local(id: int) -> bool:
	return _local_veh >= 0 and (id == _local_veh or (id >= WHEEL and id % WHEEL == _local_veh))

## Driving here: the copy of the truck comes alive and is driven by this
## player's own keys; the host's copy follows it.
func _drive_here(id: int, v: Hauler) -> void:
	_let_go()
	_local_veh = id
	v.net_mirror = true
	v.driver = world.get("player")
	if v.rig != null:
		v.rig.net_mirror = true
	v.process_mode = Node.PROCESS_MODE_INHERIT
	for body in v.wheel_bodies:
		body.process_mode = Node.PROCESS_MODE_INHERIT
		body.freeze = false
	v.freeze = v.planted
	v.linear_velocity = Vector3.ZERO
	v.angular_velocity = Vector3.ZERO

## Out of the truck: it is only a picture again, moved by the host.
func _let_go() -> void:
	var v := _nodes.get(_local_veh, null) as Hauler
	_local_veh = -1
	if v == null or not is_instance_valid(v):
		return
	v.driver = null
	v.net_mirror = false
	if v.rig != null:
		v.rig.net_mirror = false
	_solid_picture(v)
	for body in v.wheel_bodies:
		_solid_picture(body)

func _vehicle_state(v: Hauler, s: Dictionary) -> void:
	var here: bool = _local_veh >= 0 and _nodes.get(_local_veh, null) == v
	if s.has("ramps") and v.has_ramps() and not is_equal_approx(float(s.ramps), v.ramp_pose):
		v.set_ramp_pose(float(s.ramps))
	if s.has("tub") and v.bed_kind == &"tub":
		v._tub_angle = float(s.tub)
		v._pose_tub(v._tub_angle)
	if s.has("rig") and v.rig != null:
		var r := v.rig
		var rs: Dictionary = s.rig
		var was := r.planted()
		r.operating = bool(rs.op)
		r.outriggers_down = bool(rs.out)
		r.folding = bool(rs.fold)
		r.anchored = bool(rs.anch)
		r.claw_state = StringName(String(rs.get("cs", "")))
		# Worked here, the arm is ours - except while the claw drops, which
		# the host does.
		if not here or r.claw_state != &"":
			r.target_yaw = float(rs.get("ty", 0.0))
			r.target = rs.get("tg", r.target)
		if not here:
			r.joints = (rs.j as Dictionary).duplicate()
		if r.planted() != was:
			r._apply_plant()
		r._draw()
	if s.has("ld") and v.loader != null:
		var l := v.loader
		if not here:
			l.lift = float(s.ld[0])
			l.tilt = float(s.ld[1])
		l.locked = bool(s.ld[2])
		l.thumb_angle = float(s.ld[3])
		if (s.ld as Array).size() > 4 and StringName(String(s.ld[4])) != l.attachment:
			l.set_attachment(StringName(String(s.ld[4])))
			NetClient._keep_solid(l)
		if l._thumb != null:
			l._thumb.rotation = Vector3(l.thumb_angle, 0, 0)
		l._pose(true)

## This player's own state on the host: what the HUD shows.
func _view(e: Dictionary) -> void:
	var p: Player = world.get("player")
	if p == null:
		return
	p.last_prompt = String(e.get("prompt", ""))
	p.selected_slot = int(e.get("slot", -1))
	p.net_carry = e.get("carry", [0, 0.0])
	var veh := int(e.get("veh", -1))
	var pas := bool(e.get("pas", false))
	if veh == _last_veh and pas == p.passenger:
		return
	_last_veh = veh
	if veh < 0:
		_let_go()
		p.passenger = false
		if p.vehicle != null:
			p.vehicle = null
			p.camera.position = Vector3(0, 1.65, 0)
			p.camera.rotation.z = 0.0
	else:
		var v: Variant = _nodes.get(veh, null)
		p.vehicle = v as Node3D if v != null and is_instance_valid(v) else null
		p.passenger = pas
		# Riding along: the host's driver drives; this is only a seat.
		if p.vehicle is Hauler and not (p.vehicle as Hauler).is_trailer and not pas:
			_drive_here(veh, p.vehicle as Hauler)
