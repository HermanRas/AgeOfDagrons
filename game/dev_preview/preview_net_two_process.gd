## Two Godot processes, one real ENet session (PLAN.md 12.1a).
##
## **This is the only honest test of the handshake.** A `multiplayer_peer` belongs to a
## SceneTree, so a host and a client inside one process are the same MultiplayerAPI and
## prove nothing -- which is why `tests/net/test_net_remote.gd` covers the state machine
## and the id arithmetic and stops there. PLAN.md 12.1 calls for exactly this: one
## process hosting on 0.0.0.0, one joining 127.0.0.1, both headless and scriptable.
##
## Usage -- start the host first, it waits:
##   Godot --headless --path game res://dev_preview/preview_net_two_process.tscn -- --role host
##   Godot --headless --path game res://dev_preview/preview_net_two_process.tscn -- --role client
##
## Exits 0 when the session came up as expected, 1 when it did not, so a script can
## chain the two and read the answer rather than eyeballing the log.
extends Node

## Long enough for a human to start the second process by hand, short enough that a
## failed run ends rather than hanging a terminal.
const WAIT_SECONDS := 20.0

var _role := "host"
var _done := false
var _waited := 0.0


func _ready() -> void:
	_role = _string_arg("--role", "host")
	print("net two-process preview -- role %s, port %d" % [_role, Net.PORT])

	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.session_started.connect(_on_session_started)
	Net.session_ended.connect(_on_session_ended)

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
		_finish(false, "timed out after %.0f s" % WAIT_SECONDS)


## Server side: a peer arrived and has been given a player id.
func _on_peer_joined(peer_id: int) -> void:
	var assigned: int = int(Net.peer_players().get(peer_id, 0))
	print("  PEER %d joined -> player %d" % [peer_id, assigned])
	print("  peer_players now %s" % Net.peer_players())
	if assigned == 2:
		_finish(true, "host assigned the joiner player 2")
	else:
		_finish(false, "expected the joiner to be player 2, got %d" % assigned)


func _on_peer_left(peer_id: int) -> void:
	print("  PEER %d left, peer_players now %s" % [peer_id, Net.peer_players()])


## Client side: `session_started(false)` is emitted once the server has named us, which
## is the moment the session becomes usable (`Net.is_joined()`).
func _on_session_started(is_host: bool) -> void:
	if is_host:
		return
	print("  NAMED by the server: player %d (is_joined: %s)"
			% [Net.local_player_id(), Net.is_joined()])
	if Net.local_player_id() == 2 and Net.is_joined():
		_finish(true, "client was named player 2 by the host")
	else:
		_finish(false, "client got player %d" % Net.local_player_id())


func _on_session_ended(reason: String) -> void:
	print("  session ended: %s" % reason)
	if not _done:
		_finish(false, "session ended before the handshake finished (%s)" % reason)


func _finish(ok: bool, why: String) -> void:
	_done = true
	print("%s -- %s" % ["OK" if ok else "FAILED", why])
	Net.leave()
	# Deferred so the leave() RPC/teardown gets a frame before the process goes; and
	# quitting at all because a headless main loop with nothing to do spins a core
	# forever, which is how the AI preview left processes running.
	get_tree().quit(0 if ok else 1)


func _string_arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == name:
			return String(args[i + 1])
	return fallback
