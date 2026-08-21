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
