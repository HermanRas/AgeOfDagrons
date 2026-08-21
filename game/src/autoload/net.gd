## Transport + RPC boundary between view and sim (PLAN.md 5, 6.1). The client
## never touches SimWorld directly -- it calls submit_command(), which is an
## RPC up to the server; the server calls back down via snapshot RPCs.
##
## Three session shapes, one set of endpoints (PLAN.md 1.1 rule 4): `host_solo()` binds
## loopback and starts playing at once, `host_open()` binds 0.0.0.0 and WAITS -- a host
## with no world yet, because the first joiner must not arrive mid-match -- and `join()`
## dials one. Solo has always gone through the same RPCs a remote peer uses, which is
## why 12.1a is a bind address and a peer lifecycle rather than a rewrite.
##
## **Peer ids and player ids are not the same thing and must never be conflated.** ENet
## numbers peers in join order; player ids are 1..N, the identity `colours.json` indexes
## and `MatchConfig` lists. The server maps one to the other and tells each client only
## its own, which is what lets `_recv_command` refuse an order for a player the sender
## does not own.
##
## No class_name, for the same reason as sim_clock.gd: this script IS the
## "Net" autoload singleton, and a class_name of the same name would collide
## with that global identifier.
extends Node

signal session_started(is_host: bool)
signal session_ended(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal snapshot_received(snap: Dictionary)

## The match config has arrived and a world can be built from it (PLAN.md 12.1b).
##
## Emitted on the CLIENT, where it is the first moment the scene knows what map it is
## playing on. The host never waits for it -- it had the config in its hand when it
## called `start_match()` -- so anything listening must cope with the config already
## being there, which is why `GameScene` checks `match_config()` before connecting.
signal match_configured()

## One port for every session shape. Solo binds it on loopback, an open host binds it
## on 0.0.0.0, and a client dials it -- so there is nothing to keep in sync and a
## player typing an address never has to think about a port number.
const PORT := 27015

## Player slots a session will hand out (PLAN.md 1: player ids are 1..N and index into
## `colours.json`). The map generator supports up to 8 starts, so this is the same
## ceiling from the other end.
const MAX_PLAYERS := 8


## Whether this process is a client that has been given its identity yet. A joined peer
## has a `multiplayer_peer` from the moment `join()` returns, but no player id until the
## server says so -- and until then it cannot legally do anything, because every command
## is keyed on that id.
func is_joined() -> bool:
	return _peer != null and _host == null and _local_player_id > 0

## The config the next `host_solo()` should use, or null for the debug skirmish.
##
## Lives here because a `MatchConfig` has to survive a SCENE CHANGE: the skirmish
## screen (1.6) assembles it and then hands over to `Game.tscn`, whose own `_ready()`
## is what starts the session -- by which point the screen that chose it is gone. An
## autoload already outliving both is the natural place to leave it, and `Net` is the
## one that owns the session.
##
## CONSUMED, not merely read: `host_solo()` clears it, so a match started any other way
## afterwards (the main menu's own PLAY, a dev preview) gets the debug map rather than
## whatever a screen left behind ten minutes ago.
var pending_match: MatchConfig = null

## The config THIS match is being played on, on both sides of the wire.
##
## Distinct from `pending_match`, which is what a screen wants to start next and is
## consumed by doing so. This is the settled answer, and on a client it is the only
## description of the world it will ever have -- there is no `SimWorld` here to ask.
var _match_config: MatchConfig = null

var _peer: MultiplayerPeer = null
var _host: SimHost = null
var _local_player_id: int = 0
var _peer_players: Dictionary = {}          # peer id -> player id, server-side only


## The transport signals, connected ONCE for the life of the process.
##
## They live on the MultiplayerAPI rather than on the peer, so they survive every
## `multiplayer_peer` swap -- which is what makes host, join, leave and host-again work
## without re-wiring anything. Connecting them per session instead would either double
## up the handlers or drop them, depending on which end tore down first.
func _ready() -> void:
	var mp := get_tree().get_multiplayer()
	mp.peer_connected.connect(_on_peer_connected)
	mp.peer_disconnected.connect(_on_peer_disconnected)
	mp.connected_to_server.connect(_on_connected_to_server)
	mp.connection_failed.connect(_on_connection_failed)
	mp.server_disconnected.connect(_on_server_disconnected)


## Solo play: a server on loopback that starts its match immediately, because the only
## player is already here (PLAN.md 1.1 rule 4 -- solo still goes through the same RPC
## endpoints a remote peer would).
func host_solo() -> Error:
	var err := _open_server("127.0.0.1")
	if err != OK:
		return err
	# Whatever the skirmish screen chose, else the debug skirmish. Either way only
	# player 1 has a peer: `_peer_players` maps peer 1 to player 1 and nothing to
	# anybody else, so no other player can be given an order -- not by us (every
	# command validates ownership) and not by a second client, because there isn't
	# one. They are scenery until an AI (12.2a) or a second peer drives them.
	start_match(pending_match if pending_match != null else MatchConfig.debug_skirmish())
	session_started.emit(true)
	return OK


## Open to the network (PLAN.md 12.1a). The SAME server as `host_solo()` bound on a
## different address -- and deliberately WITHOUT starting the match, which is the whole
## difference between the two: a host that is waiting for people cannot have a world
## running yet, or the first joiner arrives mid-game. The match starts from the lobby,
## through `start_match()`, once everyone is in (12.1d).
func host_open(port: int = PORT) -> Error:
	var err := _open_server("0.0.0.0", port)
	if err != OK:
		return err
	session_started.emit(true)
	return OK


## Dial a host. Returns as soon as the socket is opened, NOT when the session is
## usable: `connected_to_server` follows, and after it the server sends this peer its
## player id. `is_joined()` is the test for "may I act yet", and `session_started(false)`
## is emitted when the answer becomes yes.
func join(ip: String, port: int = PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	get_tree().get_multiplayer().multiplayer_peer = peer
	_peer = peer
	_local_player_id = 0          # the server names us; never assumed locally
	_peer_players.clear()
	return OK


func _open_server(bind_ip: String, port: int = PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(bind_ip)
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	get_tree().get_multiplayer().multiplayer_peer = peer
	_peer = peer
	_local_player_id = 1          # the host is always player 1
	_peer_players = {1: 1}
	return OK


## Stand a world up and start ticking it. Server-side only, and separate from opening
## the socket so a lobby can hold the session open while people arrive.
func start_match(cfg: MatchConfig) -> void:
	if _peer == null or _host != null:
		return
	pending_match = null
	_match_config = cfg
	_host = SimHost.new()
	add_child(_host)
	_host.start(cfg, _broadcast_snapshot)

	# Every joined peer gets the config before it gets a snapshot. A client cannot make
	# sense of a snapshot without it -- it has no map to draw the entities on -- and
	# reliable delivery is the point: this is the one message a match cannot start
	# without, unlike a snapshot, of which another follows in a tenth of a second.
	var wire := cfg.to_dict()
	for peer in _peer_players:
		if int(peer) != 1:
			rpc_id(int(peer), "_recv_match_config", wire)


## The config this match is being played on -- null before one has been settled.
##
## THE CLIENT'S ONLY DESCRIPTION OF THE WORLD. `host()` is null there, so this is where
## the map comes from: PLAN.md 12.1b's "terrain is a transfer, not a regeneration".
func match_config() -> MatchConfig:
	return _match_config


## Whether a session exists at all -- hosting or joined, world or no world. `GameScene`
## asks before hosting solo, because a client that has already joined must not host
## over the top of its own session.
func has_session() -> bool:
	return _peer != null


## Whether this process is the AUTHORITY -- the one that owns the world and validates
## every command.
##
## Asks the transport, not whether `_host` exists, because those two stopped being the
## same thing when `host_open()` landed: an open host holds the session while people
## arrive and has no world at all until the match starts. Use `host()` for "is there a
## world yet"; this one for "am I the one who decides".
func is_server() -> bool:
	if _peer == null:
		return false
	return get_tree().get_multiplayer().is_server()


## Null on a client. Exists for tools that need direct read access to the
## authoritative world -- StressTest.tscn's perf counters, tests -- without
## reaching into the underscore-prefixed field from outside.
func host() -> SimHost:
	return _host


func local_player_id() -> int:
	return _local_player_id


func submit_command(cmd: Command) -> void:
	rpc_id(1, "_recv_command", cmd.to_dict())


func leave() -> void:
	_teardown()
	session_ended.emit("left")


# ── peer lifecycle (PLAN.md 12.1a) ──────────────────────────────────────────

## A peer arrived. The SERVER decides who they are and tells them; they never claim it.
##
## Peer ids are whatever ENet hands out, and player ids are 1..N -- the identity
## `colours.json` indexes, `MatchConfig` lists and every command is validated against.
## Keeping the two apart is what lets `_recv_command` refuse an order for a player the
## sender does not own, which is the whole trust boundary (PLAN.md 1.1).
func _on_peer_connected(peer_id: int) -> void:
	if not is_server():
		return                    # a client does not assign anything
	if _peer_players.has(peer_id):
		return
	var pid := _next_free_player_id()
	if pid == 0:
		# Full. Refused rather than admitted as a spectator: a peer with no player id
		# can issue nothing, so letting it linger would be a connection that looks
		# joined and cannot play.
		if _peer is ENetMultiplayerPeer:
			(_peer as ENetMultiplayerPeer).disconnect_peer(peer_id)
		return
	_peer_players[peer_id] = pid
	rpc_id(peer_id, "_assign_player", pid)
	peer_joined.emit(peer_id)


## A peer went away -- quit, or the network dropped. Its slot goes back in the pool so
## the same seat can be taken again, which is what makes a reconnect possible at all
## (12.1b owns actually resuming one).
func _on_peer_disconnected(peer_id: int) -> void:
	if not _peer_players.has(peer_id):
		return
	_peer_players.erase(peer_id)
	peer_left.emit(peer_id)


## The socket is up. Still no identity: `_assign_player` is what makes this session
## usable, and it is on its way.
func _on_connected_to_server() -> void:
	pass


func _on_connection_failed() -> void:
	_teardown()
	session_ended.emit("connection failed")


## The host went away. Torn down rather than left holding a dead peer, so the next
## `join()` or `host_open()` starts from nothing.
func _on_server_disconnected() -> void:
	_teardown()
	session_ended.emit("host left")


## The lowest player id nobody holds, or 0 when the session is full.
##
## Deliberately not derived from the peer id: ENet numbers peers in join order and
## reuses nothing, so peer 1043 would be player 1043 and index off the end of every
## table keyed by player. The lowest free slot also means a player who drops and comes
## back finds their seat where they left it, as long as nobody took it first.
func _next_free_player_id() -> int:
	var taken := {}
	for peer in _peer_players:
		taken[int(_peer_players[peer])] = true
	for pid in range(1, MAX_PLAYERS + 1):
		if not taken.has(pid):
			return pid
	return 0


## Which player each connected peer is, as a copy -- for the lobby's peer list (12.1c)
## and for tests. Server-side; empty on a client, which is only ever told its own id.
func peer_players() -> Dictionary:
	return _peer_players.duplicate()


## The server naming this client. The one piece of session state a client cannot work
## out for itself, and the point at which it becomes able to act.
@rpc("authority", "reliable")
func _assign_player(pid: int) -> void:
	if _host != null:
		return                    # the host already knows; never let this overwrite it
	_local_player_id = pid
	session_started.emit(false)


## The host describing the match to a client. Reliable, and sent before any snapshot.
@rpc("authority", "reliable")
func _recv_match_config(d: Dictionary) -> void:
	if _host != null:
		return                    # the host already has the real object; never round-trip it
	_match_config = MatchConfig.from_dict(d)
	match_configured.emit()


func _teardown() -> void:
	_match_config = null
	if _host != null:
		_host.stop()
		_host.queue_free()
		_host = null
	if _peer != null:
		get_tree().get_multiplayer().multiplayer_peer = null
		_peer = null
	_local_player_id = 0
	_peer_players.clear()


@rpc("any_peer", "call_local", "reliable")
func _recv_command(d: Dictionary) -> void:
	if _host == null:
		return                                # not the server; nothing to apply to
	var sender := get_tree().get_multiplayer().get_remote_sender_id()
	# get_remote_sender_id() reports 0 for the call_local invocation on the
	# caller's own machine (there is no incoming packet, so no remote sender)
	# -- that's the host submitting its own command in solo play.
	var pid: int = _local_player_id if sender == 0 else _peer_players.get(sender, 0)
	if pid == 0:
		return                                 # unknown sender -- reject, never trust a claimed id
	var cmd := Command.from_dict(d)
	if cmd == null:
		return
	cmd.player_id = pid
	_host.world.queue_command(cmd)


@rpc("authority", "call_local", "unreliable_ordered")
func _recv_snapshot(d: Dictionary) -> void:
	snapshot_received.emit(d)


## One player's snapshot to THAT player's peer, and to nobody else.
##
## This used to `rpc()` the lot to everybody, which was invisible for as long as
## every player was sent an identical world -- and became a hole the moment fog of
## war landed (PLAN.md 2.5). `SimHost` calls this once per player per tick, so the
## LAST player's filtered snapshot arrived last and overwrote the local player's: in
## the debug skirmish that is the opponent's view of the map, which is both wrong on
## screen and precisely what the filter exists to withhold. `test_net_solo` caught it
## within a minute of the filter existing, by which time the fog had already made the
## local player's own villager disappear.
##
## Loops over `_peer_players` rather than reversing it into a lookup because a player
## may have NO peer: the skirmish opponent has none today and an AI (12.2a) never
## will, and their snapshot should go nowhere rather than to whoever is listening.
func _broadcast_snapshot(player_id: int, snap: Dictionary) -> void:
	for peer in _peer_players:
		if int(_peer_players[peer]) == player_id:
			rpc_id(int(peer), "_recv_snapshot", snap)
