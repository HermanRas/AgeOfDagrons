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
	# The 12.1e tests register a peer by hand, and `leave()` tears down the session
	# without clearing that map. Left behind, it would have the next test's host think
	# somebody is already in slot 2.
	Net._peer_players.clear()


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


# ── a match must not be left unresolvable (12.1e) ───────────────────────────
#
# A peer cannot really be connected in this process (see the header), so these register
# one in `_peer_players` the way `_on_peer_connected` would and then call the real
# handler. What is under test is what `Net` DOES about a departure, which is the part that
# was missing; the socket teardown around it is proven by two processes.

## ⛔ THE MATCH WAITS, AND THEN IT RESOLVES. BOTH HALVES ARE LOAD-BEARING.
##
## Without the concede the match cannot resolve at all: `WinConditionSystem` counts whoever
## still owns something, and a player whose phone went into a tunnel still owns their whole
## base, so the survivor fights an abandoned town forever with no way to win and no way to be
## told why. That is 12.1e and it has not changed.
##
## ⏳ **WHAT CHANGED ON 2026-09-20 IS THAT IT IS NO LONGER INSTANT** (owner: *"lets start with
## 10sec"*). This test used to step once and assert the defeat; it now asserts the WAIT first,
## because a grace period nobody checks is a grace period the next refactor deletes.
func test_a_peer_that_vanishes_mid_match_concedes_once_the_grace_runs_out() -> void:
	Net.host_open()
	Net.start_match(MatchConfig.debug_skirmish())
	var world := Net.host().world
	Net._peer_players[4242] = 2

	assert_false(world.player_for(2).defeated, "player 2 is in the match")
	Net._on_peer_disconnected(4242)

	# THE HELD BREATH. Stepping here used to be enough to defeat them.
	world.step()
	assert_false(world.player_for(2).defeated, "still waiting for them to come back")
	assert_false(world.match_over, "and the match is emphatically not over yet")

	# And the fuse burns out.
	Net._tick_concedes(Net.DISCONNECT_GRACE + 1.0)
	world.step()

	assert_true(world.player_for(2).defeated, "the departed player is out")
	assert_true(world.match_over, "so the match can end")
	assert_eq(world.winner_id, 1, "and the player still here won")


func test_a_peer_leaving_the_LOBBY_concedes_nothing() -> void:
	# There is no match to concede yet, and queueing a command against a world that does
	# not exist would be a crash rather than a forfeit.
	Net.host_open()
	Net._peer_players[4242] = 2
	Net._on_peer_disconnected(4242)
	assert_null(Net.host(), "still no world, and no crash reaching for one")


func test_a_peer_that_resigned_before_dropping_is_not_defeated_twice() -> void:
	# The ordinary way of leaving a match: concede, see the defeat screen, then close the
	# game. The resign and the disconnect both arrive, and the second must be a no-op.
	Net.host_open()
	Net.start_match(MatchConfig.debug_skirmish())
	var world := Net.host().world
	Net._peer_players[4242] = 2

	world.queue_command(ResignCommand.new(2, world.tick))
	world.step()
	assert_true(world.player_for(2).defeated)

	Net._on_peer_disconnected(4242)
	world.step()
	assert_true(world.player_for(2).defeated, "still out, once")


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


# ── how patient a link is ───────────────────────────────────────────────────
#
# ⛔ **AND SINCE 2026-09-21 THIS IS THE ENTIRE RECOVERY MECHANISM.** The owner ruled reconnect
# after a dead socket out of scope, so a match survives a few seconds of silence here or not at
# all: there is no second chance behind these constants. `Net.DISCONNECT_GRACE` is a notice
# period, not a fallback. **Weakening anything below therefore costs matches**, where before it
# only postponed a hole somebody else was going to fill.
#
# ⛔ **WHAT THESE CANNOT DO, SAID PLAINLY.** ENet exposes `set_timeout()` and NO getter, and
# a link needs two ends that this suite cannot have -- so **nothing here proves the timeout
# was applied, or that a real blip survives it.** Only two Godot processes can show that
# (`dev_preview/preview_net_two_process.gd`), and in the end only a phone in a real tunnel.
#
# What is left is still worth pinning: the call is reached on both paths, it is safe on the
# peer ids it will genuinely be handed during a teardown race, and the constants stand in the
# relation the comment claims. That is the same split as `MountedPacks.plan_mounts` -- test the
# decision where the act is untestable -- and it is recorded here so the next reader does not
# mistake a green suite for evidence that a real blip is survived.

func test_making_a_link_patient_is_safe_when_there_is_no_session() -> void:
	# Runs during teardown races and in every offline test double. A crash here would take
	# out the lobby, not the network.
	Net._set_link_timeout(1)
	assert_false(Net.is_server(), "no session, and still standing")


func test_making_a_link_patient_is_safe_for_a_peer_that_is_already_gone() -> void:
	# THE CASE THAT ACTUALLY HAPPENS: `_on_peer_connected` sets this, and a peer can drop
	# between ENet reporting the arrival and the handler running. `get_peer()` returns null
	# there, which is a state to survive rather than an error.
	#
	# ⚠️ **THIS TEST PRINTS AN ENGINE ERROR AND PASSING IS STILL CORRECT.** `get_peer()` on an
	# id ENet does not hold emits `Condition "!peers.has(p_id)" is true. Returning: nullptr`
	# from `enet_multiplayer_peer.cpp` before handing back the null this code then checks. It
	# is not suppressible from GDScript and it is not a failure -- it is the engine narrating
	# the very lookup this test exists to survive. Left in rather than tested around, because
	# the alternative is guarding on `get_peers()` membership, and whether peer 1 is in that
	# list at `_on_connected_to_server` time is exactly the sort of thing that would silently
	# stop the timeout being applied at all. A stderr line is cheaper than an unset timeout.
	Net.host_open()
	Net._set_link_timeout(4242)
	assert_true(Net.is_server(), "an unknown peer id is a no-op, not a fault")


func test_a_link_is_given_longer_than_the_blip_that_prompted_it() -> void:
	# The owner's report was "a short few sec" of lost ping. ENet's own floor is about 5 s,
	# which is what made an ordinary blip fatal, so anything at or under that changes nothing.
	assert_true(Net.LINK_TIMEOUT_MIN_MS > 5000,
			"below ENet's own floor this constant would do nothing at all")
	assert_true(Net.LINK_TIMEOUT_MAX_MS >= Net.LINK_TIMEOUT_MIN_MS,
			"the ceiling cannot sit under the floor")
	assert_true(Net.LINK_TIMEOUT_LIMIT > 0)


# ── the host noticing a quiet peer (8.4b / 12.1b) ───────────────────────────

func test_the_host_reports_a_quiet_peer_long_before_enet_gives_up() -> void:
	# ⛔ THE BUG THIS FIXES, FROM A SIDE-BY-SIDE PLAYTEST: "the host/server is delayed ... the
	# client was printing no word from host when the host started printing the client is
	# disconnecting 9s." The host's only signal WAS ENet giving up, which LINK_TIMEOUT_MIN_MS
	# deliberately delays — so patience made the notice late as a side effect. Noticing and
	# giving up are different decisions and now have different clocks.
	Net.host_open()
	Net.start_match(MatchConfig.debug_skirmish())
	Net._peer_players[1041] = 2
	var heard: Array = []
	Net.peer_quiet.connect(func(pid: int, s: int) -> void: heard.append([pid, s]))

	Net._tick_heartbeats(2.0)
	assert_eq(heard, [[2, 2]], "named by PLAYER, and reported at two seconds")
	assert_true(2.0 < float(Net.LINK_TIMEOUT_MIN_MS) / 1000.0,
			"the whole point: this lands long before the link is declared dead")


func test_a_heartbeat_puts_the_silence_back_to_nothing() -> void:
	Net.host_open()
	Net.start_match(MatchConfig.debug_skirmish())
	Net._peer_players[1041] = 2
	var heard: Array = []
	Net.peer_quiet.connect(func(_pid: int, s: int) -> void: heard.append(s))

	Net._tick_heartbeats(3.0)
	Net._note_peer_alive(1041)
	Net._tick_heartbeats(1.5)
	assert_eq(heard, [3, 1], "the count restarts rather than resuming where it left off")


func test_a_quiet_peer_is_reported_once_per_whole_second() -> void:
	Net.host_open()
	Net.start_match(MatchConfig.debug_skirmish())
	Net._peer_players[1041] = 2
	var heard: Array = []
	Net.peer_quiet.connect(func(_pid: int, s: int) -> void: heard.append(s))

	for i in range(9):
		Net._tick_heartbeats(0.34)
	assert_eq(heard, [1, 2, 3], "three whole seconds crossed in nine frames, not nine reports")


func test_a_peer_that_has_gone_stops_being_reported_quiet() -> void:
	# ⚠️ THE HANDOVER. Once ENet gives up, `_on_peer_disconnected` lights the grace fuse and
	# the COUNTDOWN takes over the narration. Leaving the silence watch running would print
	# "No word from Player 2 — 16s" alongside "Player 2 will be disconnected in 9s", two lines
	# about the same thing disagreeing about what is happening.
	Net.host_open()
	Net.start_match(MatchConfig.debug_skirmish())
	Net._peer_players[1041] = 2
	Net._tick_heartbeats(2.0)

	Net._on_peer_disconnected(1041)
	var heard: Array = []
	Net.peer_quiet.connect(func(_pid: int, s: int) -> void: heard.append(s))
	Net._tick_heartbeats(5.0)
	assert_eq(heard, [], "the grace countdown owns the story from here")


func test_a_lobby_reports_nobody_quiet() -> void:
	# No world means no match to be missing from. A lobby counting silence would announce a
	# countdown about somebody sitting in a chair looking at the map settings.
	Net.host_open()
	Net._peer_players[1041] = 2
	var heard: Array = []
	Net.peer_quiet.connect(func(_pid: int, s: int) -> void: heard.append(s))
	Net._tick_heartbeats(30.0)
	assert_eq(heard, [])


# ── saying the silence out loud (8.4b / 12.1b) ──────────────────────────────

func test_a_held_seat_is_announced_once_per_whole_second_and_not_once_per_frame() -> void:
	# ⛔ THE WHOLE POINT OF THE CEILING CHECK. `_tick_concedes` runs every frame, so a naive
	# announcement would be sixty identical lines a second in the log and sixty RPCs on the
	# wire. Stepping in thirds here: three calls, one crossing.
	Net.host_open()
	Net.start_match(MatchConfig.debug_skirmish())
	var heard: Array[int] = []
	Net.grace_tick.connect(func(_pid: int, left: int) -> void: heard.append(left))

	Net._conceding[2] = 10.0
	Net._tick_concedes(0.34)
	Net._tick_concedes(0.34)
	Net._tick_concedes(0.34)
	assert_eq(heard, [9], "one crossing of a whole second, not three frames' worth")


func test_the_countdown_reads_down_the_way_a_person_would_say_it() -> void:
	Net.host_open()
	Net.start_match(MatchConfig.debug_skirmish())
	var heard: Array[int] = []
	Net.grace_tick.connect(func(_pid: int, left: int) -> void: heard.append(left))

	Net._conceding[2] = 5.0
	for i in range(5):
		Net._tick_concedes(1.0)
	# The ceiling, so it opens on 4 rather than 5 and never announces a 0 -- zero is the
	# concede itself, which is a `ResignCommand` and a result screen, not a countdown tick.
	assert_eq(heard, [4, 3, 2, 1], "counts down, and stops before zero")


func test_the_fuse_going_out_stops_the_countdown() -> void:
	# The reconnect seam: `_recv_ready` clears the fuse. Nothing should still be counting
	# down for a player who came back.
	Net.host_open()
	Net.start_match(MatchConfig.debug_skirmish())
	var heard: Array[int] = []
	Net.grace_tick.connect(func(_pid: int, left: int) -> void: heard.append(left))

	Net._conceding[2] = 10.0
	Net._tick_concedes(1.0)
	Net._conceding.erase(2)
	Net._tick_concedes(1.0)
	assert_eq(heard, [9], "nothing is still counting for somebody who is back")


func test_a_host_never_reports_itself_as_out_of_touch() -> void:
	# `_tick_link_quiet` is a client's inference about the host. A host running it against
	# itself would post "no word from the host" in a match that is perfectly healthy.
	Net.host_open()
	Net.start_match(MatchConfig.debug_skirmish())
	var heard: Array[int] = []
	Net.link_quiet.connect(func(s: int) -> void: heard.append(s))
	Net._tick_link_quiet(30.0)
	assert_eq(heard, [], "a host cannot lose touch with itself")


func test_silence_before_the_first_snapshot_is_not_reported() -> void:
	# ⚠️ THE START HANDSHAKE IS SILENT BY DESIGN. A client sits without snapshots between
	# joining and the match beginning, and announcing that would open every joined match with
	# a countdown about a connection that is fine.
	Net._last_snapshot_tick = -1
	var heard: Array[int] = []
	Net.link_quiet.connect(func(s: int) -> void: heard.append(s))
	Net._tick_link_quiet(10.0)
	assert_eq(heard, [], "no snapshot has ever arrived; there is nothing to have stopped")


func test_a_departed_player_is_noticed_before_the_match_could_reasonably_end() -> void:
	# ⚠️ THE NUMBER A PLAYTEST ACTUALLY JUDGES IS THE SUM. Patience runs BEFORE the grace
	# fuse rather than instead of it, so a player who has genuinely gone leaves an undefended
	# town for link-timeout PLUS grace. Neither constant means anything read on its own, and
	# this is the assertion that will fail if somebody raises one without looking at the other.
	var worst := float(Net.LINK_TIMEOUT_MAX_MS) / 1000.0 + Net.DISCONNECT_GRACE
	assert_true(worst <= 45.0,
			"a town that cannot fight back for %.0f s is a lost fight, not a held seat" % worst)
