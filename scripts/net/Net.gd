extends Node

## Autoload. Co-op networking: one player hosts the game on their own PC and
## friends join it. The host runs the whole world - physics, machines, money -
## and every guest is a player on the host driven by the keys that guest
## presses; guests draw what the host sends them. So everything is shared:
## one purse, one set of unlocks, one world.
##
## ENet over UDP. The host needs PORT open (or forwarded) for guests from
## outside their network.

enum Mode { OFFLINE, HOST, CLIENT }

const PORT := 24565
const MAX_GUESTS := 7

signal hosting_started()
signal peer_joined(id: int)
signal peer_left(id: int)
signal joined()
signal join_failed(reason: String)
signal left()

var mode: Mode = Mode.OFFLINE
var player_name: String = "Player"
## Where a guest is joining (or has joined).
var address: String = ""
var port: int = PORT

## The world-side ends: NetHost on the host, NetClient on a guest.
var host_side: Object = null
var client_side: Object = null
## The world on screen is a copy of a host's. Sticks when the connection goes,
## so that copy is never saved over the guest's own game.
var guest_world: bool = false
## The map the host is playing (WorldMap), told to a guest the moment it
## connects, so it builds the same one. Empty until then.
var host_map: StringName = &""
signal map_known(id: StringName)

func _ready() -> void:
	# The name you played under and the host you joined last time.
	var saved_name := String(Settings.value(&"player_name")).strip_edges()
	player_name = saved_name if saved_name != "" else "Player"
	address = String(Settings.value(&"last_address"))
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)

func is_host() -> bool:
	return mode == Mode.HOST

func is_client() -> bool:
	return mode == Mode.CLIENT

func online() -> bool:
	return mode != Mode.OFFLINE

## Opens this game to guests. Returns "" or why not.
func host(p_port: int = PORT) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(p_port, MAX_GUESTS)
	if err != OK:
		return "could not open port %d (%s)" % [p_port, error_string(err)]
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	port = p_port
	hosting_started.emit()
	return ""

## Sets up to join a host: the world is loaded as a guest's first (a long,
## blocking build that would time a live connection out), and then connects.
func prepare_join(p_address: String, p_port: int = PORT) -> void:
	leave()
	mode = Mode.CLIENT
	var at := split_address(p_address, p_port)
	address = at[0]
	port = at[1]

## "1.2.3.4", "1.2.3.4:24565" or " host.example.com " -> [host, port].
static func split_address(text: String, default_port: int = PORT) -> Array:
	var t := text.strip_edges()
	var p := default_port
	# One colon is host:port; more than one is an IPv6 address, left alone.
	if t.count(":") == 1:
		var tail := t.get_slice(":", 1).strip_edges()
		t = t.get_slice(":", 0).strip_edges()
		if tail.is_valid_int() and int(tail) > 0 and int(tail) < 65536:
			p = int(tail)
	return [t, p]

## Starts joining a host. `joined` or `join_failed` follows.
func join(p_address: String, p_port: int = PORT) -> String:
	leave()
	var at := split_address(p_address, p_port)
	var host_name: String = at[0]
	var host_port: int = at[1]
	if host_name == "":
		return "type the host's IP address"
	var peer := ENetMultiplayerPeer.new()
	host_map = &""
	var err := peer.create_client(host_name, host_port)
	if err != OK:
		return "could not reach %s:%d (%s) - check the address" % [host_name, host_port, error_string(err)]
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	address = host_name
	port = host_port
	return ""

func leave() -> void:
	var was := mode
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	if was != Mode.OFFLINE:
		left.emit()

func guests() -> PackedInt32Array:
	return multiplayer.get_peers() if is_host() else PackedInt32Array()

func _on_peer_connected(id: int) -> void:
	if is_host():
		_patient(multiplayer.multiplayer_peer as ENetMultiplayerPeer, id)
	if OS.has_environment("NET_TRACE"):
		print("[net] peer connected ", id, " mode ", mode)
	if is_host():
		# First thing a guest hears: which map to build.
		h_map.rpc_id(id, String(WorldMap.current))
		peer_joined.emit(id)

func _on_peer_disconnected(id: int) -> void:
	if is_host():
		if host_side != null:
			host_side.call("on_guest_left", id)
		peer_left.emit(id)

func _on_connected() -> void:
	_patient(multiplayer.multiplayer_peer as ENetMultiplayerPeer, 1)
	joined.emit()

## A hitch on either machine - a world being built, a save - must not drop
## the connection: allow a long silence before giving up on a peer.
static func _patient(peer: ENetMultiplayerPeer, id: int) -> void:
	if peer == null:
		return
	var p := peer.get_peer(id)
	if p != null:
		p.set_timeout(64, 45000, 90000)

func _on_failed() -> void:
	mode = Mode.OFFLINE
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	join_failed.emit("no answer from %s:%d" % [address, port])

func _on_server_gone() -> void:
	mode = Mode.OFFLINE
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if client_side != null:
		client_side.call("on_host_gone")
	left.emit()

# --- Host -> guest, before anything else ---------------------------------------

@rpc("authority", "reliable")
func h_map(id: String) -> void:
	host_map = WorldMap.valid(id)
	map_known.emit(host_map)

# --- Guest -> host ---------------------------------------------------------------

## The guest's world is built and it wants the state of the world.
@rpc("any_peer", "reliable")
func c_hello(name: String) -> void:
	if OS.has_environment("NET_TRACE"):
		print("[net] hello from ", multiplayer.get_remote_sender_id(), " host_side ", host_side)
	if is_host() and host_side != null:
		host_side.call("on_guest_ready", multiplayer.get_remote_sender_id(), name)

## What the guest is holding down, and where it is looking. Many a second.
@rpc("any_peer", "unreliable_ordered")
func c_input(state: Dictionary) -> void:
	if is_host() and host_side != null:
		host_side.call("on_guest_input", multiplayer.get_remote_sender_id(), state)

## A key or button press.
@rpc("any_peer", "reliable")
func c_event(ev: Dictionary) -> void:
	if is_host() and host_side != null:
		host_side.call("on_guest_event", multiplayer.get_remote_sender_id(), ev)

# --- Host -> guest ---------------------------------------------------------------

## Things appearing, going, changing; money; messages. In order, never lost.
@rpc("authority", "reliable")
func h_batch(batch: Array) -> void:
	if client_side != null:
		client_side.call("on_batch", batch)

## Where everything that moves is now. The latest wins; a lost one is replaced.
@rpc("authority", "unreliable_ordered")
func h_motion(ids: PackedInt32Array, poses: PackedFloat32Array, carriers: PackedInt32Array, tick: int) -> void:
	if client_side != null:
		client_side.call("on_motion", ids, poses, carriers, tick)
