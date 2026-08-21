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

## The clock has started and the match is really running (PLAN.md 12.1d). Emitted on the
## HOST, once every joined client has said it can draw the world -- or once the wait for
## a silent one has run out.
signal match_begun()

## The host has described the match it is SETTING UP, while everyone is still in the
## lobby (PLAN.md 12.1c). Emitted on a joined client.
##
## DELIBERATELY NOT `match_configured`, which is a different event wearing a similar
## name: that one means "the match is starting, build your world", and a screen listening
## to it changes scene. This one means "here is what you are being invited to", and the
## whole point is that it arrives with time left to look at it and refuse. Reusing the
## one signal for both would make every settings tweak in the lobby launch the match.
signal lobby_config_received()

## A joined player has said whether they are ready, or stopped being ready. Emitted on
## the HOST, which is the only side that needs to count them.
signal lobby_ready_changed(peer_id: int, ready: bool)

## A joined player wants the next free colour for their own slot. Emitted on the HOST.
##
## A REQUEST, not an instruction, and it names no colour. The rule that two players never
## share one is the host's to enforce -- colour is the only thing telling players apart
## (§1), so a duplicate is not a cosmetic slip but an unplayable match -- and a client
## that picked its own index could collide with a change the host made in the same breath.
## Asking to advance leaves the one authority holding the one rule.
signal lobby_colour_cycle_requested(peer_id: int)

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

## What the host says it is SETTING UP, on a joined client, while still in the lobby.
##
## Separate from `_match_config` on purpose. That one is the settled answer and the
## client's only description of the world once play starts; this one is a proposal a
## player is still entitled to look at and walk away from. Keeping them apart is what
## stops a lobby preview from being mistaken for a started match.
var _lobby_config: MatchConfig = null

## peer id -> whether that player has said they are ready. Server-side only, and cleared
## when they leave: a peer that has gone is not a peer still holding up a start.
var _lobby_ready: Dictionary = {}

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
	# BUILT, NOT STARTED (PLAN.md 12.1d). The clock is held until every joined client
	# has the map and says it is ready; see `_begin_when_ready`.
	_host.build(cfg, _broadcast_snapshot)

	# Every joined peer gets the config before it gets a snapshot. A client cannot make
	# sense of a snapshot without it -- it has no map to draw the entities on -- and
	# reliable delivery is the point: this is the one message a match cannot start
	# without, unlike a snapshot, of which another follows in a tenth of a second.
	var wire := cfg.to_dict()
	_awaiting_ready.clear()
	for peer in _peer_players:
		if int(peer) != 1:
			rpc_id(int(peer), "_recv_match_config", wire)
			_awaiting_ready[int(peer)] = true

	_ready_waited = 0.0
	_begin_when_ready()


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
	# Read BEFORE the erase below, because that is what knows which player this was.
	var pid := int(_peer_players[peer_id])
	_peer_players.erase(peer_id)
	# Same rule one stage earlier: a peer that has left the LOBBY is not one still owed a
	# ready, and leaving their flag behind would let a departed player's stale "yes" count
	# toward a start -- or their stale "no" block one forever.
	_lobby_ready.erase(peer_id)
	# A PEER THAT LEAVES IS NOT A PEER WE ARE STILL WAITING FOR. Without this, someone
	# who joins and quits during the handshake holds the match at tick 0 until the
	# timeout, for everybody -- which is the same freeze 12.1e is about, arriving early.
	if _awaiting_ready.erase(peer_id):
		_begin_when_ready()

	# A VANISHED PLAYER CONCEDES (PLAN.md 12.1e). Without this the match cannot resolve:
	# `WinConditionSystem` counts whoever still owns something, and a player whose phone
	# went into a tunnel still owns their whole base -- so the remaining player fights an
	# abandoned town forever with no way to win and no way to be told why.
	#
	# The same `ResignCommand` a player sends by hand, queued by the server on their
	# behalf, so there is one path to being out of a match rather than two that could
	# disagree. Queued rather than applied directly because the sim owns when things
	# happen: it lands on a tick boundary like every other command, and every client sees
	# it at the same tick.
	#
	# `validate()` refuses a second resign, so a peer who conceded and THEN dropped -- the
	# ordinary way of leaving -- is not defeated twice.
	if _host != null and _host.world != null and pid > 0:
		_host.world.queue_command(ResignCommand.new(pid, _host.world.tick))

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


# ── the match-start handshake (PLAN.md 12.1d) ───────────────────────────────

## How long the host will hold the clock for a client that has been sent the map and has
## not said it is ready.
##
## Bounded on purpose. A client that crashed between joining and building would otherwise
## hold the match at tick 0 for everybody, and a match that never starts is worse than a
## match one player joins late -- that player still gets every snapshot from the moment
## they arrive, because snapshots are whole-world and not deltas (7.2).
const READY_TIMEOUT := 8.0

## peer id -> true for every joined peer that has been sent the config and has not acked.
var _awaiting_ready: Dictionary = {}
var _ready_waited := 0.0


## Start the world if everyone is accounted for. Called when the last ack lands, when a
## peer we were waiting on disappears, and once up front for the solo case -- where the
## set is empty and the match begins immediately, exactly as it always did.
func _begin_when_ready() -> void:
	if _host == null or _host.is_running():
		return
	if not _awaiting_ready.is_empty():
		return
	_host.begin()
	match_begun.emit()


func _process(delta: float) -> void:
	# Only ever busy in the seconds between "match built" and "everyone ready".
	if _host == null or _host.is_running() or _awaiting_ready.is_empty():
		return
	_ready_waited += delta
	if _ready_waited < READY_TIMEOUT:
		return
	push_warning("Net: starting without %d peer(s) that never reported ready: %s"
			% [_awaiting_ready.size(), _awaiting_ready.keys()])
	_awaiting_ready.clear()
	_begin_when_ready()


## A client telling the host it has built its view and can make sense of a snapshot.
##
## `GameScene` calls this once its terrain is up. Reliable, because a dropped ack costs
## the whole match `READY_TIMEOUT` seconds of standing still.
func notify_ready() -> void:
	if _host != null:
		return                    # the host is its own audience; nothing to tell
	rpc_id(1, "_recv_ready")


@rpc("any_peer", "reliable")
func _recv_ready() -> void:
	if _host == null:
		return
	var sender := get_tree().get_multiplayer().get_remote_sender_id()
	if not _awaiting_ready.erase(sender):
		return                    # unknown, or already accounted for
	_begin_when_ready()


# ── the lobby, before anything starts (PLAN.md 12.1c) ───────────────────────
#
# The lobby used to be one-directional: the host learned who had arrived, and the joiner
# learned nothing at all until `start_match()` told it what it was already playing. A
# joining player could not see the map, the seed, the victory condition or the colours
# before being dropped into a match on someone else's terms, and had no way to say no.
# These four calls are the reply channel.

## Tell every joined peer what is being set up. The host calls this when somebody arrives
## and whenever a setting changes.
##
## Reliable, and it carries the whole config including the map -- 20-40 KB. Chatty by the
## standards of a lobby and nothing by the standards of the 18 KB snapshots this same
## transport pushes ten times a second once play starts. The map is the thing a player
## most wants to look at before agreeing to play on it, so it is sent rather than
## described.
## A CHANGED PROPOSAL CANCELS EVERY AGREEMENT. Whoever said yes said yes to the settings
## in front of them, so a host who swaps the map after they agreed no longer has their
## consent -- and a start gated on stale readiness is exactly the bug this whole channel
## exists to prevent. Cleared here, at the one place a new proposal is issued, rather than
## trusted to every caller that changes a setting.
func broadcast_lobby_config(cfg: MatchConfig) -> void:
	if not is_server() or cfg == null:
		return
	_lobby_ready.clear()
	var wire := cfg.to_dict()
	for peer in _peer_players:
		if int(peer) != 1:
			rpc_id(int(peer), "_recv_lobby_config", wire)


@rpc("authority", "reliable")
func _recv_lobby_config(d: Dictionary) -> void:
	if _host != null:
		return                    # the host is looking at the real object already
	_lobby_config = MatchConfig.from_dict(d)
	lobby_config_received.emit()


## What the host says it is setting up, or null if nothing has been described yet.
func lobby_config() -> MatchConfig:
	return _lobby_config


## A joined client saying whether it is ready to play. Reliable: a dropped "yes" would
## leave a host waiting on a player who is sitting there having already agreed.
func set_lobby_ready(ready: bool) -> void:
	if _host != null:
		return                    # the host readies by pressing START
	rpc_id(1, "_recv_lobby_ready", ready)


@rpc("any_peer", "reliable")
func _recv_lobby_ready(ready: bool) -> void:
	if not is_server():
		return
	var sender := get_tree().get_multiplayer().get_remote_sender_id()
	if not _peer_players.has(sender):
		return                    # not somebody this session knows
	_lobby_ready[sender] = ready
	lobby_ready_changed.emit(sender, ready)


## Ask the host for the next free colour for this device's own slot. See
## `lobby_colour_cycle_requested` for why it names no colour.
func request_colour_cycle() -> void:
	if _host != null:
		return                    # the host changes its own colours directly
	rpc_id(1, "_recv_colour_cycle_request")


@rpc("any_peer", "reliable")
func _recv_colour_cycle_request() -> void:
	if not is_server():
		return
	var sender := get_tree().get_multiplayer().get_remote_sender_id()
	if not _peer_players.has(sender):
		return                    # not somebody this session knows
	lobby_colour_cycle_requested.emit(sender)


## Whether one joined peer has said it is ready. Absent means no, never means yes: a
## player who has not answered has not agreed.
func is_peer_ready(peer_id: int) -> bool:
	return bool(_lobby_ready.get(peer_id, false))


## Whether every joined peer has agreed. True with nobody joined, because then there is
## nobody left to wait for -- the caller decides whether an empty lobby may start.
func all_peers_ready() -> bool:
	for peer in _peer_players:
		if int(peer) != 1 and not is_peer_ready(int(peer)):
			return false
	return true


## The host describing the match to a client. Reliable, and sent before any snapshot.
@rpc("authority", "reliable")
func _recv_match_config(d: Dictionary) -> void:
	if _host != null:
		return                    # the host already has the real object; never round-trip it
	_match_config = MatchConfig.from_dict(d)
	match_configured.emit()


func _teardown() -> void:
	_match_config = null
	# The lobby goes with the session. A stale proposal outliving the host that made it
	# would have the next screen previewing a match nobody is offering.
	_lobby_config = null
	_lobby_ready.clear()
	# And the delivery counters, so the next match's loss figure is its own.
	_snapshots_seen = 0
	_snapshots_missed = 0
	_last_snapshot_tick = -1
	_awaiting_ready.clear()
	_ready_waited = 0.0
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
	_count_snapshot(int(d.get("tick", 0)))
	# Unpacked HERE, at the one point a snapshot arrives, so everything downstream keeps
	# reading the readable dictionary form (12.1f). A snapshot that was never packed --
	# a test's, a preview's -- passes through untouched.
	snapshot_received.emit(SnapshotSystem.from_wire(d))


## HOW MANY SNAPSHOTS ACTUALLY ARRIVE (PLAN.md 12.1f).
##
## The one number the packing work could not produce for itself: snapshots are
## `unreliable_ordered` and still exceed the MTU, so a dropped fragment drops the whole
## snapshot -- and loopback has no loss, so every measurement so far has been arithmetic.
## Ticks are consecutive (`SimHost` builds one per tick), so a jump is exactly the count
## that went missing, whether ENet dropped a fragment or discarded a packet that arrived
## out of order.
##
## Logged only when something is LOST, plus a summary every `_STATS_EVERY`. A phone is
## launched by an intent with no command line to put a flag on, so there is nothing to
## switch this on with -- and a line that only appears when the news is bad is cheap
## enough to leave in.
const _STATS_EVERY := 300

var _snapshots_seen := 0
var _snapshots_missed := 0
var _last_snapshot_tick := -1


func _count_snapshot(tick: int) -> void:
	_snapshots_seen += 1
	if _last_snapshot_tick >= 0 and tick > _last_snapshot_tick + 1:
		var lost := tick - _last_snapshot_tick - 1
		_snapshots_missed += lost
		print("net: lost %d snapshot(s) before tick %d" % [lost, tick])
	# Assigned either way. A tick that goes BACKWARDS is a new match on an old counter, not
	# a loss, and the comparison above already declines to count it as one.
	_last_snapshot_tick = tick

	if _snapshots_seen % _STATS_EVERY == 0:
		var sent := _snapshots_seen + _snapshots_missed
		print("net: %d of %d snapshots arrived (%.2f%% lost) over %d ticks"
				% [_snapshots_seen, sent,
				100.0 * float(_snapshots_missed) / maxf(1.0, float(sent)),
				_last_snapshot_tick])


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
	# Packed ONCE per player rather than per peer, and only here: the transport is what
	# cares how a snapshot is encoded, not the simulation that produced it (12.1f).
	var wire := SnapshotSystem.to_wire(snap)
	for peer in _peer_players:
		if int(_peer_players[peer]) == player_id:
			rpc_id(int(peer), "_recv_snapshot", wire)
