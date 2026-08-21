## Phase 12.1a: an OPEN host -- bound to the network, holding a session with no world
## yet -- plus the player-id assignment a joining peer depends on.
##
## What can honestly be tested in one process is the session state machine and the id
## arithmetic. **Two peers cannot be stood up here:** a `multiplayer_peer` belongs to a
## SceneTree, and this suite has exactly one, so a host and a client in the same process
## would be the same MultiplayerAPI. The real handshake is proven by two Godot processes
## (`dev_preview/preview_net_two_process.gd`), which is what PLAN.md 12.1 means by
## "verifiable with two Godot processes on one desktop".
##
## Net is a shared autoload, so every test must leave() in after_each -- otherwise the
## next test finds the port already bound.
extends TestCase


func after_each() -> void:
	Net.leave()


# ── opening and joining ─────────────────────────────────────────────────────

func test_an_open_host_is_the_authority_before_it_has_a_world() -> void:
	# The distinction `host_open` exists for: a lobby holds the session while people
	# arrive, so "am I the server" cannot mean "is there a world".
	assert_eq(Net.host_open(), OK)
	assert_true(Net.is_server(), "bound and authoritative")
	assert_null(Net.host(), "and deliberately has no world yet")
	assert_eq(Net.local_player_id(), 1, "the host is always player 1")


func test_the_match_starts_separately_and_only_once() -> void:
	Net.host_open()
	Net.start_match(MatchConfig.debug_skirmish())
	assert_not_null(Net.host(), "the world stands up when the lobby says so")

	var world := Net.host().world
	Net.start_match(MatchConfig.debug_skirmish())
	assert_eq(Net.host().world, world, "a second start must not replace a running match")


func test_leaving_an_open_host_frees_the_port() -> void:
	assert_eq(Net.host_open(), OK)
	Net.leave()
	assert_false(Net.is_server())
	assert_eq(Net.host_open(), OK, "the port must be free again")


func test_a_solo_host_still_starts_its_match_immediately() -> void:
	# The regression that splitting host_solo() into open + start could have caused.
	assert_eq(Net.host_solo(), OK)
	assert_not_null(Net.host(), "solo has nobody to wait for")
	assert_true(Net.is_server())


func test_a_client_has_no_identity_until_the_server_names_it() -> void:
	# Dialling an address nobody is listening on: ENet opens the socket regardless, so
	# `join()` returning OK is not the same as being in a session.
	assert_eq(Net.join("127.0.0.1", Net.PORT), OK)
	assert_eq(Net.local_player_id(), 0, "a client never assumes its own player id")
	assert_false(Net.is_joined(), "and is not usable until told")
	assert_false(Net.is_server())
	assert_null(Net.host(), "a client has no authoritative world")


# ── the match-start handshake (12.1d) ───────────────────────────────────────

func test_a_match_with_nobody_to_wait_for_starts_at_once() -> void:
	# Solo, and the host's own match before anyone joins: an empty wait set must not
	# hold the clock, or single player would never tick.
	Net.host_open()
	Net.start_match(MatchConfig.debug_skirmish())
	assert_true(Net.host().is_running(), "no peers means nothing to wait for")


func test_the_clock_is_held_until_a_joined_client_reports_ready() -> void:
	Net.host_open()
	# Stand in for a joined peer. `start_match` takes its wait set from `_peer_players`,
	# which is what a real `_on_peer_connected` would have filled in.
	Net._peer_players[1041] = 2

	Net.start_match(MatchConfig.debug_skirmish())
	assert_not_null(Net.host(), "the world is BUILT")
	assert_false(Net.host().is_running(),
			"and deliberately not ticking -- the client has no map to draw yet")
	assert_eq(Net.host().world.tick, 0)

	Net._awaiting_ready.erase(1041)          # what `_recv_ready` does for that sender
	Net._begin_when_ready()
	assert_true(Net.host().is_running(), "the last ack starts the match")
	assert_eq(Net.host().world.tick, 0, "and it starts from the beginning, not partway")


func test_a_peer_that_leaves_during_the_handshake_does_not_freeze_the_match() -> void:
	# Somebody joins, the match is built for them, and they quit before acking. Without
	# releasing the wait this holds the match at tick 0 for everyone until the timeout.
	Net.host_open()
	Net._peer_players[1041] = 2
	Net.start_match(MatchConfig.debug_skirmish())
	assert_false(Net.host().is_running())

	Net._on_peer_disconnected(1041)
	assert_true(Net.host().is_running(), "their leaving is an answer too")


func test_the_wait_is_bounded_so_a_silent_client_cannot_stall_it() -> void:
	# A client that crashed between joining and building never acks. A match that never
	# starts is worse than one a player joins late.
	Net.host_open()
	Net._peer_players[1041] = 2
	Net.start_match(MatchConfig.debug_skirmish())
	assert_false(Net.host().is_running())

	Net._ready_waited = Net.READY_TIMEOUT
	Net._process(0.1)
	assert_true(Net.host().is_running(), "the wait ran out and the match went ahead")
	assert_true(Net._awaiting_ready.is_empty())


func test_two_acks_do_not_restart_a_running_clock() -> void:
	# `begin()` is reachable twice -- the last ack, and the timeout -- and `SimClock.start()`
	# resets the accumulator, so a second call mid-match would drop a fraction of a tick.
	Net.host_solo()
	assert_true(Net.host().is_running())
	SimClock.advance(0.05)          # part-way to the next tick
	Net.host().begin()
	SimClock.advance(0.05)
	assert_eq(Net.host().world.tick, 1, "the half-accumulated tick still landed")


# ── player-id assignment ────────────────────────────────────────────────────

func test_the_host_holds_player_1_and_the_next_peer_gets_2() -> void:
	Net.host_open()
	assert_eq(Net._next_free_player_id(), 2,
			"player 1 is the host's, so the first joiner is player 2")


func test_slots_are_handed_out_lowest_first_and_reused_after_a_drop() -> void:
	Net.host_open()
	# Stand in for three joined peers. Peer ids are deliberately nothing like the
	# player ids -- ENet numbers peers in join order and would index off the end of
	# every table keyed by player.
	Net._peer_players[1041] = 2
	Net._peer_players[1042] = 3
	assert_eq(Net._next_free_player_id(), 4)

	Net._peer_players.erase(1041)
	assert_eq(Net._next_free_player_id(), 2,
			"a dropped player's seat goes back in the pool, lowest first")


func test_a_full_session_hands_out_nothing() -> void:
	Net.host_open()
	for i in range(2, Net.MAX_PLAYERS + 1):
		Net._peer_players[1000 + i] = i
	assert_eq(Net._next_free_player_id(), 0,
			"full means refused, not admitted as a spectator who cannot play")


func test_peer_players_is_a_copy_so_a_caller_cannot_rewrite_the_map() -> void:
	# The lobby's peer list reads this. It must not be able to hand somebody a player
	# id, because that map is the whole of who-owns-what.
	Net.host_open()
	var view := Net.peer_players()
	view[999] = 7
	assert_false(Net.peer_players().has(999))
