class_name NetHost
extends Node

## The host's end of co-op. Each guest gets a real Player in this world,
## driven by the keys the guest presses; and everything in the world a guest
## has to see - loose pieces, trees, rocks, buildings, vehicles, players, the
## shared purse - is sent to them: what appears and goes and changes, reliably,
## and where the moving things are, many times a second.

const RATE := 20.0            ## motion updates a second
const STATE_EVERY := 4        ## state checks every this many motion updates
const ECON_EVERY := 20        ## money and unlocks, once a second
const VIEW_EVERY := 2         ## each guest's own prompt and hand
const WHEEL := 1 << 24        ## wheel poses ride on the vehicle's id plus this
const CHUNK := 32             ## poses per motion packet
## A resting thing's pose is sent again this often (in motion updates), so a
## lost packet never leaves it in the wrong place for good.
const REFRESH := 40

var world: Node

var _ready_peers: Dictionary = {}     ## peer -> true, once its world is built
var _next_id: int = 1
var _ids: Dictionary = {}             ## key -> id
var _nodes: Dictionary = {}           ## id -> [node, kind, key]
var _state_hash: Dictionary = {}      ## id -> hash of the last state sent
var _poses: Dictionary = {}           ## id -> last pose sent
var _sent_at: Dictionary = {}         ## id -> tick it was last sent
var _carrier_sent: Dictionary = {}    ## id -> the carrier its last pose was relative to
var _holder: Dictionary = {}          ## piece -> the player carrying it, this update
var _econ_hash: Dictionary = {}     ## peer -> hash of the last money and kit sent
var _tick: int = 0
var _acc: float = 0.0
var _outbox: Array = []               ## for every guest
var _mail: Dictionary = {}            ## peer -> [entries for them alone]

func _ready() -> void:
	Net.host_side = self
	# Guests keep being sent the world while the host sits in a menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 100    # after the world has moved

func _exit_tree() -> void:
	if Net.host_side == self:
		Net.host_side = null

# --- Guests coming and going ---------------------------------------------------------

func on_guest_ready(peer: int, display: String) -> void:
	if OS.has_environment("NET_TRACE"):
		print("[host] guest ready ", peer, " ", display)
	var p: Player = world.call("add_guest", peer, display)
	_ready_peers[peer] = true
	if not p.warped.is_connected(_on_warped):
		p.warped.connect(_on_warped.bind(peer, p))
	# Thrown about or crushed here: the guest's game acts it out.
	if not p.has_meta("net_event_hooked"):
		p.set_meta("net_event_hooked", true)
		p.net_event.connect(func(entry: Dictionary) -> void: _post(peer, entry))
	# Everything there is, as it is, then who they are.
	# Money, unlocks and the size of the land first: the buildings that follow
	# may stand on land bought since the game began.
	var batch: Array = []
	var econ := _econ_for(peer, _econ_entry())
	_econ_hash[peer] = _econ_sig(econ)
	batch.append(econ)
	for entry in _entities():
		var fresh := not _ids.has(entry[2])
		var id := _id_for(entry[0], entry[1], entry[2])
		_nodes[id] = entry
		var spawn := _spawn_entry(id, entry[0], entry[1])
		batch.append(spawn)
		if fresh:
			# New to everyone (this guest's own player, at least).
			_outbox.append(spawn)
		var st: Variant = _state_of(entry[0], entry[1])
		if st != null:
			batch.append({"t": "state", "id": id, "s": st})
	batch.append({"t": "you", "id": _ids.get(_key_of(p, "p"), -1)})
	if OS.has_environment("NET_TRACE"):
		print("[host] sending %d entries, %d bytes" % [batch.size(), var_to_bytes(batch).size()])
	Net.rpc_id(peer, "h_batch", batch)
	for q in _ready_peers:
		if q != peer:
			tell_peer(q, "%s joined" % display)
	world.call("_tell", world.get("player"), "%s joined" % display)

func on_guest_left(peer: int) -> void:
	_ready_peers.erase(peer)
	_mail.erase(peer)
	_econ_hash.erase(peer)
	world.call("remove_guest", peer)

func on_guest_input(peer: int, state: Dictionary) -> void:
	var p := _guest(peer)
	if p == null:
		return
	p.input.apply(state)
	# Where the guest has walked, unless the host has moved them since.
	if state.has("pos") and int(state.get("ws", -1)) == p.net_warp_seq and not p.driving():
		var at: Array = state.pos
		p.net_target = Vector3(float(at[0]), float(at[1]), float(at[2]))
		p.net_has_target = true
	# Driving on their machine: the truck, its wheels and its arms go where
	# the guest has them. The hook, the winch and the loads stay ours.
	if state.has("veh") and p.driving() and p.vehicle is Hauler:
		var v := p.vehicle as Hauler
		var vs: Dictionary = state.veh
		if int(vs.get("id", -1)) == int(_ids.get(_key_of(v, "v"), -2)):
			var wheels: Array = []
			for w in vs.get("w", []):
				wheels.append(_unpose(w))
			v.net_follow_to(_unpose(vs.x), wheels)
			if v.rig != null and vs.has("tg") and v.rig.claw_state == &"":
				v.rig.target = vs.tg
				v.rig.target_yaw = float(vs.get("ty", 0.0))
			if v.loader != null and vs.has("ld"):
				v.loader.lift = clampf(float(vs.ld[0]), v.loader.lift_min, v.loader.lift_max)
				v.loader.tilt = clampf(float(vs.ld[1]), LoaderArm.TILT_MIN, LoaderArm.TILT_MAX)
				v.loader.homing = false
	if state.has("yaw"):
		p.rotation.y = float(state.yaw)
	if state.has("pitch"):
		p.camera.rotation.x = clampf(float(state.pitch), -1.45, 1.45)

func on_guest_event(peer: int, ev: Dictionary) -> void:
	var p := _guest(peer)
	if p == null:
		return
	match String(ev.get("t", "")):
		"key":
			var k := InputEventKey.new()
			k.keycode = int(ev.code) as Key
			k.physical_keycode = int(ev.get("phys", ev.code)) as Key
			k.pressed = true
			p.remote_press(k)
			world.call("handle_key", p, k)
		"btn":
			var b := InputEventMouseButton.new()
			b.button_index = int(ev.b) as MouseButton
			b.pressed = true
			p.remote_press(b)
		"base":
			world.call("return_to_base", p)
		"build":
			tell_peer(peer, _guest_build(ev))
		"pad":
			var pe: Variant = _nodes.get(int(ev.get("id", -1)), null)
			if pe != null and String(pe[1]) == "b":
				var pad := (pe[0] as Dictionary).node as VehiclePad
				if pad != null:
					if ev.has("paint"):
						var c: Array = ev.paint
						pad.paint = Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]))
					if ev.has("attachment"):
						pad.attachment = StringName(String(ev.attachment))
					if ev.has("fit"):
						var f: Array = ev.fit
						pad.fit(StringName(String(f[0])), int(f[1]))
					if ev.has("on"):
						var o: Array = ev.on
						pad.set_part_on(StringName(String(o[0])), bool(o[1]))
		"sign":
			var se: Variant = _nodes.get(int(ev.get("id", -1)), null)
			if se != null and String(se[1]) == "b":
				var sign := (se[0] as Dictionary).node as Schematic
				if sign != null and sign.is_sign():
					sign.set_text(String(ev.get("text", "")))
		"mcfg":
			var entry: Variant = _nodes.get(int(ev.get("id", -1)), null)
			if entry != null and String(entry[1]) == "b":
				var m := (entry[0] as Dictionary).node as InlineMachine
				if m != null:
					m.set_setting(StringName(String(ev.get("k", ""))), float(ev.get("v", 0.0)))
		"fcfg":
			var fe: Variant = _nodes.get(int(ev.get("id", -1)), null)
			if fe != null and String(fe[1]) == "b":
				# A filter's rules, or which ways a splitter has locked.
				var f: Node = (fe[0] as Dictionary).node
				if (f is Filter or f is Splitter) and ev.get("state") is Dictionary:
					f.call("from_dict", ev.state)
		"hotbar":
			if p.kit != null:
				p.kit.set_hotbar(int(ev.get("slot", -1)), StringName(String(ev.get("id", ""))))

## A guest building on the host's land: put up, taken down, moved. Paid for
## like the host's own. Returns what to tell them ("" for nothing).
func _guest_build(ev: Dictionary) -> String:
	var plot: Plot = world.get("plot")
	match String(ev.get("op", "")):
		"place":
			var def := PlayerState.def_at_tier(StringName(String(ev.get("def", ""))), int(ev.get("tier", 1)))
			if def == null:
				return "unknown building"
			var sz: Array = ev.get("size", [])
			var tr: Array = ev.get("trim", [def.trim.x, def.trim.y, def.trim.z])
			var trim := Vector3i(int(tr[0]), int(tr[1]), int(tr[2]))
			if sz.size() == 3 and (Vector3i(int(sz[0]), int(sz[1]), int(sz[2])) != def.size or trim != def.trim):
				def = Plot.resized(def, Vector3i(int(sz[0]), int(sz[1]), int(sz[2])), trim)
			var c: Array = ev.cell
			var r: Array = ev.rot
			var cell := Vector2i(int(c[0]), int(c[1]))
			var rot := Vector3i(int(r[0]), int(r[1]), int(r[2]))
			var err := plot.placement_error(def, cell, rot)
			if err != "":
				return err
			return "" if plot.place(def, cell, rot) != null else "could not build that there"
		"remove", "edit":
			var entry: Variant = _nodes.get(int(ev.get("id", -1)), null)
			if entry == null or String(entry[1]) != "b":
				return "that building has gone"
			var rec: Dictionary = entry[0]
			if String(ev.op) == "remove":
				plot.remove(rec.node)
				return ""
			var c: Array = ev.cell
			var r: Array = ev.rot
			var sz: Array = ev.size
			var tr: Array = ev.get("trim", [0, 0, 0])
			return plot.edit(plot.placed.find(rec), Vector2i(int(c[0]), int(c[1])), Vector3i(int(r[0]), int(r[1]), int(r[2])),
				Vector3i(int(sz[0]), int(sz[1]), int(sz[2])), float(ev.get("lift", 0.0)), Vector3i(int(tr[0]), int(tr[1]), int(tr[2])))
	return ""

## A truck a guest is driving was recovered here: recover it on their machine,
## to the same place.
func recovered(v: Hauler) -> void:
	v.net_hold_at(v.global_transform)
	var guests: Dictionary = world.get("guests")
	for peer in guests:
		if guests[peer] == v.driver:
			_post(peer, {"t": "recover", "id": int(_ids.get(_key_of(v, "v"), -1)), "x": _pose(v.global_transform)})

## The host moved a guest's player: put the guest there too.
func _on_warped(peer: int, p: Player) -> void:
	if not is_instance_valid(p):
		return
	_post(peer, {"t": "warp", "s": p.net_warp_seq,
		"x": [p.global_position.x, p.global_position.y, p.global_position.z]})

func _post(peer: int, entry: Dictionary) -> void:
	if not _mail.has(peer):
		_mail[peer] = []
	(_mail[peer] as Array).append(entry)

func _guest(peer: int) -> Player:
	var guests: Dictionary = world.get("guests")
	var p: Variant = guests.get(peer, null)
	return p as Player if p != null and is_instance_valid(p) else null

## A message for one player: a guest's goes to their game.
func tell(p: Player, message: String) -> void:
	var guests: Dictionary = world.get("guests")
	for peer in guests:
		if guests[peer] == p:
			tell_peer(peer, message)
			return

func tell_peer(peer: int, message: String) -> void:
	if message == "":
		return
	if not _mail.has(peer):
		_mail[peer] = []
	(_mail[peer] as Array).append({"t": "msg", "m": message})

# --- What there is ---------------------------------------------------------------------

## Every replicated thing: [node, kind, key].
func _entities() -> Array:
	var out: Array = []
	var manager: LooseItemManager = world.get("manager")
	for item: LooseItem in manager._active:
		if is_instance_valid(item) and item.state != LooseItem.State.POOLED:
			out.append([item, "i", _key_of(item, "i")])
	for tree: ChoppableTree in world.call("trees"):
		if tree.has_meta("entry"):
			out.append([tree, "t", _key_of(tree, "t")])
	for rock: OreRock in world.call("rocks"):
		if rock.has_meta("entry") and not rock.consumed():
			out.append([rock, "r", _key_of(rock, "r")])
	var plot: Plot = world.get("plot")
	for rec in plot.placed:
		var node: Node3D = rec.node
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			out.append([rec, "b", _rec_key(rec)])
	for v: Hauler in world.call("vehicles"):
		if not v.is_queued_for_deletion():
			out.append([v, "v", _key_of(v, "v")])
	for p: Player in world.call("players"):
		out.append([p, "p", _key_of(p, "p")])
	return out

## A building keeps its identity when it is moved, turned or resized (which
## puts up a new node in its place).
var _next_rec: int = 1
func _rec_key(rec: Dictionary) -> String:
	if not rec.has("net"):
		rec["net"] = _next_rec
		_next_rec += 1
	return "b#%d" % int(rec.net)

## An identity that changes when a pooled piece is reused for a new one.
func _key_of(node: Object, kind: String) -> String:
	var n: Object = node
	var k := "%s%d" % [kind, n.get_instance_id()]
	if n is LooseItem:
		k += ":%d" % (n as LooseItem).spawn_index
	return k

func _id_for(_node: Variant, _kind: String, key: String) -> int:
	if _ids.has(key):
		return int(_ids[key])
	var id := _next_id
	_next_id += 1
	_ids[key] = id
	return id

func _spawn_entry(id: int, thing: Variant, kind: String) -> Dictionary:
	var e := {"t": "spawn", "id": id, "k": kind}
	match kind:
		"i":
			var item := thing as LooseItem
			e.item = String(item.item_id)
			e.dims = Solid.to_dict(item.dims)
			e.limbs = item.limbs_to_array()
			e.x = _pose(item.global_transform)
		"t", "r":
			var node := thing as Node3D
			e.entry = node.get_meta("entry")
			e.seed = int(node.get_meta("form_seed"))
			e.x = _pose(node.global_transform)
		"b":
			var rec: Dictionary = thing
			var def: BuildingDef = rec.def
			e.def = String(def.id)
			e.tier = def.tier
			e.size = [def.size.x, def.size.y, def.size.z]
			e.trim = [def.trim.x, def.trim.y, def.trim.z]
			e.cell = [rec.cell.x, rec.cell.y]
			var r: Vector3i = rec.rot
			e.rot = [r.x, r.y, r.z]
			e.lift = float(rec.get("lift", 0.0))
		"v":
			var v := thing as Hauler
			e.veh = String(v.vehicle_id)
			e.x = _pose(v.global_transform)
			e.paint = [v.paint.r, v.paint.g, v.paint.b]
		"p":
			var p := thing as Player
			var peer := _peer_of(p)
			e.peer = peer
			e.name = String(world.call("guest_name", peer)) if peer != 1 else Net.player_name
			e.x = _pose(p.global_transform)
	return e

func _peer_of(p: Player) -> int:
	var guests: Dictionary = world.get("guests")
	for peer in guests:
		if guests[peer] == p:
			return peer
	return 1

## What changes on a thing without it moving. Null for things with none.
func _state_of(thing: Variant, kind: String) -> Variant:
	match kind:
		"i":
			var item := thing as LooseItem
			return {"l": item.limbs_to_array()} if not item.limbs.is_empty() else {"l": []}
		"t":
			return (thing as ChoppableTree).net_state()
		"r":
			return (thing as OreRock).net_state()
		"b":
			var rec: Dictionary = thing
			var node: Node = rec.node
			var def: BuildingDef = rec.def
			var r: Vector3i = rec.rot
			# Where it stands and how big: a move or resize shows up here.
			var s := {"g": [rec.cell.x, rec.cell.y, r.x, r.y, r.z, def.size.x, def.size.y, def.size.z,
				float(rec.get("lift", 0.0)), def.trim.x, def.trim.y, def.trim.z]}
			var run: Variant = node.get("running")
			if run != null:
				s.run = bool(run)
			# What is inside it: a bin's stock, a mould's fill, a machine's
			# queue. Not a pad's truck, which is sent as a vehicle.
			if node.has_method("to_dict") and not node is VehiclePad:
				s.d = node.call("to_dict")
			return s
		"v":
			var v := thing as Hauler
			var s := {"tub": v._tub_angle, "held": v.held, "ramps": v.ramp_pose}
			if v.rig != null:
				var r := v.rig
				s.rig = {"j": r.joints.duplicate(), "op": r.operating, "out": r.outriggers_down, "cs": String(r.claw_state),
					"fold": r.folding, "anch": r.anchored, "ty": r.target_yaw, "tg": r.target}
			if v.loader != null:
				var l := v.loader
				s.ld = [l.lift, l.tilt, l.locked, l.thumb_angle, String(l.attachment)]
			return s
		"p":
			var p := thing as Player
			var veh := -1
			if p.driving() and is_instance_valid(p.vehicle):
				veh = int(_ids.get(_key_of(p.vehicle, "v"), -1))
			var st := {"pitch": snappedf(p.camera.rotation.x, 0.05), "veh": veh, "tool": String(p.selected_tool()),
				"held": p.held.size(), "build": p.build_system != null and p.build_system.active}
			# What the lumberjack is doing, so every machine draws him the same.
			if p.dragged != null and is_instance_valid(p.dragged):
				var at := p.drag_point()
				st.drag = [snappedf(at.x, 0.05), snappedf(at.y, 0.05), snappedf(at.z, 0.05), snappedf(p.dragged.mass, 1.0)]
			if p.avatar != null:
				st.g = [p.avatar.gesture_count, String(p.avatar.last_gesture)]
			return st
	return null

static func _unpose(x: PackedFloat32Array) -> Transform3D:
	return Transform3D(Basis(Quaternion(x[3], x[4], x[5], x[6]).normalized()), Vector3(x[0], x[1], x[2]))

static func _pose(t: Transform3D) -> PackedFloat32Array:
	var q := t.basis.orthonormalized().get_rotation_quaternion()
	return PackedFloat32Array([t.origin.x, t.origin.y, t.origin.z, q.x, q.y, q.z, q.w])

func _econ_entry() -> Dictionary:
	var quests: Variant = world.get("quests")
	var plot: Plot = world.get("plot")
	return {"t": "econ", "e": Economy.to_dict(), "p": PlayerState.to_dict(), "land": plot.tier,
		"q": quests.call("to_dict") if quests != null else {}}

## What decides whether a guest needs telling again. The clock ticks all the
## time and runs on the guest's side too, so it only counts every ten seconds.
static func _econ_sig(econ: Dictionary) -> int:
	var e: Dictionary = (econ.e as Dictionary).duplicate()
	var clock := int(float(e.get("day_time", 0.0)) / 10.0)
	e.erase("day_time")
	return hash([e, econ.p, econ.q, econ.land, clock])

## The shared state as one guest sees it: their own tools and gear in place
## of the host's.
func _econ_for(peer: int, econ: Dictionary) -> Dictionary:
	var p := _guest(peer)
	if p == null or p.kit == null:
		return econ
	var out := econ.duplicate()
	out["p"] = p.kit.over(econ.p)
	return out

# --- Sending -------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _ready_peers.is_empty():
		return
	_acc += delta
	if _acc < 1.0 / RATE:
		return
	_acc = 0.0
	_tick += 1
	var ents := _entities()
	var seen: Dictionary = {}
	var ids := PackedInt32Array()
	var poses := PackedFloat32Array()
	var carriers := PackedInt32Array()
	_holder.clear()
	for pl: Player in world.call("players"):
		for item in pl.held:
			if is_instance_valid(item):
				_holder[item] = pl
	var check_state := _tick % STATE_EVERY == 0
	for entry in ents:
		var key: String = entry[2]
		var fresh := not _ids.has(key)
		var id := _id_for(entry[0], entry[1], key)
		seen[id] = true
		if fresh:
			_nodes[id] = entry
			_outbox.append(_spawn_entry(id, entry[0], entry[1]))
		else:
			_nodes[id] = entry
		if fresh or check_state:
			var st: Variant = _state_of(entry[0], entry[1])
			if st != null:
				var h := hash(st)
				if fresh or int(_state_hash.get(id, 0)) != h:
					_state_hash[id] = h
					_outbox.append({"t": "state", "id": id, "s": st})
		_collect_motion(id, entry[0], entry[1], ids, poses, carriers)
	# Gone since last time.
	for id in _nodes.keys():
		if not seen.has(id):
			var key: String = _nodes[id][2]
			_nodes.erase(id)
			_ids.erase(key)
			_state_hash.erase(id)
			_poses.erase(id)
			_sent_at.erase(id)
			_carrier_sent.erase(id)
			_outbox.append({"t": "gone", "id": id})
	if _tick % ECON_EVERY == 0:
		var econ := _econ_entry()
		for peer in _ready_peers:
			var mine := _econ_for(peer, econ)
			var h := _econ_sig(mine)
			if h != int(_econ_hash.get(peer, 0)):
				_econ_hash[peer] = h
				if not _mail.has(peer):
					_mail[peer] = []
				(_mail[peer] as Array).append(mine)
	if _tick % VIEW_EVERY == 0:
		for peer in _ready_peers:
			var p := _guest(peer)
			if p != null:
				if not _mail.has(peer):
					_mail[peer] = []
				(_mail[peer] as Array).append(_view_of(p))
	for peer in _ready_peers:
		var batch: Array = _outbox.duplicate()
		if _mail.has(peer):
			batch.append_array(_mail[peer])
		if not batch.is_empty():
			Net.rpc_id(peer, "h_batch", batch)
		# Motion in packets small enough never to be split.
		if OS.has_environment("NET_TRACE") and _tick % 200 == 0:
			print("[host] tick %d motion %d outbox %d guest at %s" % [_tick, ids.size(), batch.size(), _guest(peer).global_position if _guest(peer) != null else Vector3.ZERO])
		var i := 0
		while i < ids.size():
			var n := mini(CHUNK, ids.size() - i)
			Net.rpc_id(peer, "h_motion", ids.slice(i, i + n), poses.slice(i * 7, (i + n) * 7),
				carriers.slice(i, i + n), _tick)
			i += n
	_outbox.clear()
	_mail.clear()

func _collect_motion(id: int, thing: Variant, kind: String, ids: PackedInt32Array, poses: PackedFloat32Array,
		carriers: PackedInt32Array) -> void:
	match kind:
		"i":
			var item := thing as LooseItem
			# In a bed or on a rack, a piece goes where what carries it goes:
			# sent in its frame, it stays put on the guest's screen however
			# that moves there.
			var by: Node3D = _holder.get(item, null)
			if by == null and item.carrier != null and is_instance_valid(item.carrier):
				by = item.carrier
			_moved(id, item.global_transform, ids, poses, carriers, by)
		"p":
			_moved(id, (thing as Node3D).global_transform, ids, poses, carriers, null)
		"v":
			var v := thing as Hauler
			var tug: Node3D = v.towed_by if v.towed_by != null and is_instance_valid(v.towed_by) else null
			_moved(id, v.global_transform, ids, poses, carriers, tug)
			for w in v.wheel_bodies.size():
				_moved(id + WHEEL * (w + 1), v.wheel_bodies[w].global_transform, ids, poses, carriers, v)

## Adds a pose if it has changed since it was last sent (or has not been sent
## for a while). With a carrier, the pose is in the carrier's frame.
func _moved(id: int, t: Transform3D, ids: PackedInt32Array, poses: PackedFloat32Array,
		carriers: PackedInt32Array, by: Node3D) -> void:
	var cid := 0
	if by != null:
		cid = int(_ids.get(_key_of(by, "v" if by is Hauler else "p"), 0))
		if cid != 0:
			t = by.global_transform.affine_inverse() * t
	var p := _pose(t)
	var last: Variant = _poses.get(id, null)
	if last != null and int(_carrier_sent.get(id, 0)) == cid \
			and _tick - int(_sent_at.get(id, 0)) < REFRESH + id % 20:
		var l: PackedFloat32Array = last
		var dp := Vector3(p[0] - l[0], p[1] - l[1], p[2] - l[2]).length()
		var dq := absf(p[3] * l[3] + p[4] * l[4] + p[5] * l[5] + p[6] * l[6])
		if dp < 0.004 and dq > 0.99995:
			return
	_poses[id] = p
	_sent_at[id] = _tick
	_carrier_sent[id] = cid
	ids.append(id)
	poses.append_array(p)
	carriers.append(cid)

## A guest's own player: what their HUD shows.
func _view_of(p: Player) -> Dictionary:
	var veh := -1
	if p.driving() and is_instance_valid(p.vehicle):
		veh = int(_ids.get(_key_of(p.vehicle, "v"), -1))
	return {"t": "view", "prompt": p.last_prompt, "slot": p.selected_slot, "veh": veh, "pas": p.passenger,
		"carry": [p.carried_count(), p.carried_volume()], "drag": p.dragged != null}
