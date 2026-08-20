## Transport + RPC boundary between view and sim (PLAN.md 5, 6.1). The client
## never touches SimWorld directly -- it calls submit_command(), which is an
## RPC up to the server; the server calls back down via snapshot RPCs.
##
## host_open()/join() (remote multiplayer) are explicitly out of MVP scope
## (PLAN.md 10) and land with that phase -- only the solo path is built here,
## even though solo still goes through the same RPC endpoints a remote peer
## would use, per PLAN.md 1.1 rule 4.
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

const _SOLO_PORT := 27015

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

var _peer: MultiplayerPeer = null
var _host: SimHost = null
var _local_player_id: int = 0
var _peer_players: Dictionary = {}          # peer id -> player id, server-side only


func host_solo() -> Error:
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip("127.0.0.1")
	var err := peer.create_server(_SOLO_PORT)
	if err != OK:
		return err

	get_tree().get_multiplayer().multiplayer_peer = peer
	_peer = peer
	_local_player_id = 1
	_peer_players = {1: 1}

	_host = SimHost.new()
	add_child(_host)
	# Whatever the skirmish screen chose, else the debug skirmish. Either way only
	# player 1 has a peer: `_peer_players` maps peer 1 to player 1 and nothing to
	# anybody else, so no other player can be given an order -- not by us (every
	# command validates ownership) and not by a second client, because there isn't
	# one. They are scenery until an AI (12.2a) or a second peer (12.1) drives them.
	var cfg := pending_match if pending_match != null else MatchConfig.debug_skirmish()
	pending_match = null
	_host.start(cfg, _broadcast_snapshot)

	session_started.emit(true)
	return OK


func is_server() -> bool:
	return _host != null


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
	if _host != null:
		_host.stop()
		_host.queue_free()
		_host = null
	if _peer != null:
		get_tree().get_multiplayer().multiplayer_peer = null
		_peer = null
	_local_player_id = 0
	_peer_players.clear()
	session_ended.emit("left")


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
