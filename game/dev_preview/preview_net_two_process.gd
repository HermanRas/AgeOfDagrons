## Two Godot processes, one real ENet session, one real match (PLAN.md 12.1a + 12.1b).
##
## **This is the only honest test of the handshake.** A `multiplayer_peer` belongs to a
## SceneTree, so a host and a client inside one process are the same MultiplayerAPI and
## prove nothing -- which is why `tests/net/test_net_remote.gd` covers the state machine
## and the id arithmetic and stops there. PLAN.md 12.1 calls for exactly this: one
## process hosting on 0.0.0.0, one joining, both headless and scriptable.
##
## What it proves, in order:
##   12.1a  the host binds, the joiner is given player 2, and neither invents its own id
##   12.1b  the client receives the MAP as data and could draw it with no `SimWorld` at
##          all -- `Net.host()` is null on that side for the whole run
##          and snapshots arrive filtered for that player and carry its entities
##
## Usage -- start the host first, it waits:
##   Godot --headless --path game res://dev_preview/preview_net_two_process.tscn -- --role host
##   Godot --headless --path game res://dev_preview/preview_net_two_process.tscn -- --role client --ip 127.0.0.1
##
## Exits 0 when everything expected happened, 1 otherwise, so a script can chain the
## two and read the answer rather than eyeballing the log.
extends Node

## Long enough for a human to start the second process by hand, short enough that a
## failed run ends rather than hanging a terminal.
const WAIT_SECONDS := 25.0

## How many snapshots the client wants before it believes the match is really running.
const SNAPSHOTS_WANTED := 5

## How long the host keeps playing after the match starts, so the client has a match to
## watch. Comfortably longer than the client needs.
const HOST_PLAY_SECONDS := 8.0

var _role := "host"
var _done := false
var _waited := 0.0

var _joiner_player := 0
var _match_started := false
var _played := 0.0
var _snapshots := 0
var _entities_seen := 0


func _ready() -> void:
	_role = _string_arg("--role", "host")
	print("net two-process preview -- role %s, port %d" % [_role, Net.PORT])

	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.session_started.connect(_on_session_started)
	Net.session_ended.connect(_on_session_ended)
	Net.match_configured.connect(_on_match_configured)
	Net.match_begun.connect(_on_match_begun)
	Net.snapshot_received.connect(_on_snapshot)

	if _role == "host":
		var err := Net.host_open()
		if err != OK:
			_finish(false, "host_open failed: %d" % err)
			return
		print("  listening on 0.0.0.0:%d as player %d, no world yet (host() null: %s)"
				% [Net.PORT, Net.local_player_id(), Net.host() == null])
		print("  waiting for a peer...")
	else:
		# `--ip` so this can dial the machine's real LAN address rather than loopback,
		# which is the only way to prove the 0.0.0.0 bind and the firewall rule --
		# 127.0.0.1 would succeed even with the host bound to loopback only. Same
		# argument the phone will need in 12.1g.
		var ip := _string_arg("--ip", "127.0.0.1")
		var err := Net.join(ip)
		if err != OK:
			_finish(false, "join failed: %d" % err)
			return
		print("  dialled %s:%d -- player id so far %d (0 means not yet named)"
				% [ip, Net.PORT, Net.local_player_id()])


func _process(delta: float) -> void:
	if _done:
		return
	_waited += delta
	if _waited >= WAIT_SECONDS:
		_finish(false, "timed out after %.0f s (snapshots %d)" % [WAIT_SECONDS, _snapshots])
		return

	if _role == "host" and _match_started:
		_played += delta
		if _played >= HOST_PLAY_SECONDS:
			_finish(_snapshots > 0, "hosted %.0f s, tick %d, %d snapshots"
					% [_played, Net.host().world.tick, _snapshots])


## Server side: a peer arrived and has been given a player id. THEN the match starts --
## which is the ordering `host_open` exists for, and the lobby (12.1c) will drive.
func _on_peer_joined(peer_id: int) -> void:
	_joiner_player = int(Net.peer_players().get(peer_id, 0))
	print("  PEER %d joined -> player %d" % [peer_id, _joiner_player])
	print("  peer_players now %s" % Net.peer_players())
	if _joiner_player != 2:
		_finish(false, "expected the joiner to be player 2, got %d" % _joiner_player)
		return

	var cfg := MatchConfig.debug_generated(3, MapGenerator.Type.FOREST, 2)
	print("  starting the match: %dx%d, %d players, map carried as %d terrain bytes"
			% [cfg.map_data.size.x, cfg.map_data.size.y, cfg.player_ids.size(),
			cfg.map_data.terrain.size()])
	Net.start_match(cfg)
	if Net.host() == null:
		_finish(false, "start_match did not stand a world up")
		return
	# 12.1d: the world exists but the clock does NOT run yet. If it did, the client
	# would be sent snapshots for ticks it has no map to draw.
	print("  world built at tick %d, clock running: %s (waiting for the client)"
			% [Net.host().world.tick, Net.host().is_running()])
	if Net.host().is_running():
		_finish(false, "the clock started before the client was ready")


## Host side: every client has acked, so the clock is running. The tick it starts on is
## the assertion that matters -- a match that began before the client was ready would
## have run on without it.
func _on_match_begun() -> void:
	_match_started = true
	print("  MATCH BEGUN at tick %d, clock running: %s"
			% [Net.host().world.tick, Net.host().is_running()])
	if Net.host().world.tick != 0:
		_finish(false, "the world had already ticked %d times" % Net.host().world.tick)


func _on_peer_left(peer_id: int) -> void:
	print("  PEER %d left, peer_players now %s" % [peer_id, Net.peer_players()])


## Client side: `session_started(false)` is emitted once the server has named us, which
## is the moment the session becomes usable (`Net.is_joined()`).
func _on_session_started(is_host: bool) -> void:
	if is_host:
		return
	print("  NAMED by the server: player %d (is_joined: %s)"
			% [Net.local_player_id(), Net.is_joined()])
	if Net.local_player_id() != 2 or not Net.is_joined():
		_finish(false, "client got player %d" % Net.local_player_id())


## Client side, and the whole point of 12.1b: the map arrived as DATA, with no
## `SimWorld` on this side to have asked.
func _on_match_configured() -> void:
	var cfg := Net.match_config()
	if cfg == null or cfg.map_data == null:
		_finish(false, "config arrived with no map data")
		return
	print("  MAP received: %dx%d, %d terrain bytes, %d starts, host() null: %s"
			% [cfg.map_data.size.x, cfg.map_data.size.y, cfg.map_data.terrain.size(),
			cfg.map_data.starts.size(), Net.host() == null])
	if Net.host() != null:
		_finish(false, "a client must not have an authoritative world")
		return
	# Standing in for `GameScene._start_match()`: the view is up, so tell the host it
	# can start the clock (12.1d). Without this the match waits out READY_TIMEOUT.
	print("  built the view; reporting ready")
	Net.notify_ready()


func _on_snapshot(snap: Dictionary) -> void:
	_snapshots += 1
	var updated: Array = snap.get("updated", [])
	_entities_seen = maxi(_entities_seen, updated.size())
	if _role != "client" or _snapshots < SNAPSHOTS_WANTED:
		return
	if _done:
		return
	# A client with the map and a stream of snapshots has everything the view needs;
	# what remains of (b) is the placement ghost, which is advisory.
	var cfg := Net.match_config()
	var ok := cfg != null and cfg.map_data != null and _entities_seen > 0
	_finish(ok, "client held the map (%dx%d) and %d snapshots, up to %d entities in one"
			% [cfg.map_data.size.x if cfg != null and cfg.map_data != null else 0,
			cfg.map_data.size.y if cfg != null and cfg.map_data != null else 0,
			_snapshots, _entities_seen])


func _on_session_ended(reason: String) -> void:
	print("  session ended: %s" % reason)
	if not _done:
		_finish(false, "session ended before the run finished (%s)" % reason)


func _finish(ok: bool, why: String) -> void:
	_done = true
	print("%s -- %s" % ["OK" if ok else "FAILED", why])
	Net.leave()
	# Quitting at all because a headless main loop with nothing to do spins a core
	# forever, which is how the AI preview left processes running.
	get_tree().quit(0 if ok else 1)


func _string_arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == name:
			return String(args[i + 1])
	return fallback
