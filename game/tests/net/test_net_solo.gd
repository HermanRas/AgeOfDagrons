## Phase 0.6: proves the full loop -- host_solo() stands up a real ENet
## server on loopback, submit_command() RPCs up to CommandSystem, and the
## resulting tick is RPCed back down as a snapshot (PLAN.md 5.1, 6.1).
##
## Net is a shared autoload, so every test must leave() in after_each --
## otherwise the next test (in this file or another) finds the loopback
## port already bound.
extends TestCase

## Not `Net.PORT`. The lobby test below binds 0.0.0.0 for real, and a suite on the game's own
## port fights a game the owner has open -- `test_skirmish_screen`'s reason, which cost that
## file a red run the first time it happened.
const _TEST_PORT := 47019


func after_each() -> void:
	Net.leave()


func test_host_solo_starts_a_server_as_player_1() -> void:
	var err := Net.host_solo()
	assert_eq(err, OK)
	assert_true(Net.is_server())
	assert_eq(Net.local_player_id(), 1)


func test_leave_tears_down_cleanly_so_hosting_again_works() -> void:
	Net.host_solo()
	Net.leave()
	assert_false(Net.is_server())

	var err := Net.host_solo()
	assert_eq(err, OK, "the loopback port must be free again after leave()")
	assert_true(Net.is_server())


func test_submit_command_reaches_the_world_and_a_snapshot_comes_back() -> void:
	Net.host_solo()
	var v := Net.host().world.spawn_unit(&"unit.villager", 1, Vector2i(2, 2))

	var snapshots: Array[Dictionary] = []
	Net.snapshot_received.connect(func(s: Dictionary) -> void: snapshots.append(s))

	Net.submit_command(MoveCommand.new(1, [v.id], Vector2i(10, 2)))
	for i in 80:
		SimClock.advance(0.1)

	assert_eq(v.tile(), Vector2i(10, 2), "command travelled Net -> CommandSystem -> MovementSystem")
	assert_false(snapshots.is_empty(), "each tick should have broadcast a snapshot back down")

	var last: Dictionary = snapshots.back()
	assert_eq(int(last.get("tick", 0)), 80)
	var found := false
	for entry in last.get("updated", []):
		if int(entry.get("id", 0)) == v.id:
			found = true
			# `pos` is a Vector2i on the wire since 12.1f, not {"x": .., "y": ..}: the
			# dictionary cost 48 bytes to carry two small integers.
			var pos: Vector2i = entry.get("pos", Vector2i.ZERO)
			assert_eq(pos.x, 10 * SimWorld.SUBTILE + SimWorld.SUBTILE / 2)
	assert_true(found, "the moved unit must appear in its own snapshot")


# -- saving ends the session, for everybody (12.4) -----------------------------------------

## ⛔ A SAVED MATCH IS OVER HERE TOO, NOT JUST ON THE OTHER DEVICES.
##
## The host is the one that pressed the button, and the failure this guards is the quiet one:
## a host that broadcast the ending and kept its own world would carry on ticking a match
## every other player had already left, writing snapshots to nobody.
func test_saving_ends_the_host_session_and_leaves_a_note() -> void:
	Net.host_solo()
	var reasons: Array[String] = []
	Net.session_ended.connect(func(r: String) -> void: reasons.append(r))

	Net.end_match_saved("Saved: Skirmish, 20 Sep 08:14 (tick 120)")

	assert_eq(reasons, ["saved"], "and the reason is not 'left' -- nobody walked out")
	assert_false(Net.has_session(), "the socket goes with the match")
	assert_null(Net.host(), "and so does the world")
	assert_eq(Net.take_parting_note(), "Saved: Skirmish, 20 Sep 08:14 (tick 120)")


## ⚠️ READ ONCE. A note left behind would reappear on the main menu after an unrelated match
## three screens later, attached to nothing that happened.
func test_the_parting_note_is_taken_rather_than_merely_read() -> void:
	Net.parting_note = "something happened"
	assert_eq(Net.take_parting_note(), "something happened")
	assert_eq(Net.take_parting_note(), "", "the second reader gets nothing")


## Only the authority may end everybody's match. A client calling this would tear down its own
## session while the host carried on -- which is `leave()`, wearing the wrong reason.
func test_only_the_server_can_end_a_saved_match() -> void:
	Net.parting_note = ""
	Net.end_match_saved("no session at all")
	assert_eq(Net.parting_note, "", "nothing to end, so nothing said")


# -- which seat a joiner gets (12.4 item 3 / 12.1b) -----------------------------------------

## The behaviour every path had before saves existed: the lowest id nobody holds.
func test_without_a_reservation_the_lowest_free_seat_is_handed_out() -> void:
	Net.host_solo()
	assert_eq(Net._next_free_player_id(), 2, "the host holds 1")


## ⛔ THE FILE NAMES THE SEAT, AND JOIN ORDER DOES NOT GET A VOTE.
##
## The friend who was player 3 has to come back as player 3. Without this they are handed 2 --
## perfectly legal, no error anywhere, and they resume in somebody else's town. It is also how
## a peer is kept out of a bot's seat: a roster of [1, 3] is a saved match whose player 2 was
## an AI, and 2 is never offered.
func test_a_reservation_decides_which_seat_the_next_joiner_takes() -> void:
	Net.reserve_seats([1, 3])
	Net.host_solo()
	assert_eq(Net._next_free_player_id(), 3, "2 belongs to the AI in this save")


## A full roster refuses the next arrival rather than seating them somewhere. `_on_peer_connected`
## disconnects on 0, which is the existing "session is full" path -- so an extra friend is turned
## away instead of given a town the file says is somebody else's.
func test_a_full_roster_has_no_seat_left_to_give() -> void:
	Net.reserve_seats([1])
	Net.host_solo()
	assert_eq(Net._next_free_player_id(), 0)


## The seats go with the session. A reservation still standing would cap the NEXT ordinary
## lobby at whatever the old save's roster was and refuse everybody past it.
func test_leaving_clears_the_reservation() -> void:
	Net.reserve_seats([1, 2, 3])
	Net.host_solo()
	Net.leave()
	assert_true(Net.reserved_seats().is_empty())


# -- how long a match waits for a phone in a tunnel (12.1b) ---------------------------------

## Pretend player 2 was here and their socket died. `_on_peer_disconnected` is the real entry
## point and takes a PEER id, so the mapping has to exist first — this is the same white-box
## poke `test_skirmish_screen` uses to stand up a peer without a second process.
func _drop_a_fake_peer(peer_id: int, player_id: int) -> void:
	Net._peer_players[peer_id] = player_id
	Net._on_peer_disconnected(peer_id)


## ⛔ THE CONCEDE IS DELAYED, NOT CANCELLED, AND BOTH HALVES OF THAT MATTER.
##
## Delayed, because a phone that loses signal at a traffic light should not lose the match.
## Not cancelled, because `WinConditionSystem` counts whoever still owns something — so a
## player who never comes back must eventually be counted out, or the survivors fight an
## abandoned town forever with no way to win and no way to be told why (12.1e).
func test_a_dropped_player_gets_ten_seconds_before_the_match_gives_up() -> void:
	Net.host_solo()
	_drop_a_fake_peer(77, 2)
	# A RELATION, NOT AN EQUALITY. `Net._process` burns this fuse on real frames, so a test
	# that pinned the exact remaining seconds would be asserting that no frame elapsed
	# between two of its own lines -- true today and not a property worth depending on.
	assert_true(Net.conceding_in(2) > Net.DISCONNECT_GRACE - 1.0, "the fuse is lit")

	# Half way there, and still nothing queued.
	Net._tick_concedes(Net.DISCONNECT_GRACE * 0.5)
	assert_true(Net.conceding_in(2) > 0.0, "still holding its breath")
	assert_eq(Net.host().world.player_for(2).defeat_reason, SimPlayer.Defeat.NONE)

	# And well over the line.
	Net._tick_concedes(Net.DISCONNECT_GRACE)
	assert_eq(Net.conceding_in(2), 0.0, "the fuse is spent")
	for i in 3:
		SimClock.advance(0.1)
	assert_eq(Net.host().world.player_for(2).defeat_reason, SimPlayer.Defeat.DISCONNECTED,
			"and it is DISCONNECTED, not a hand-sent resign")


## ⛳ THE ACK IS WHAT PUTS IT OUT — connecting is not proof anybody can play. Asserted on the
## seam directly, because the client half that would send it after a drop is not built.
func test_the_ready_ack_puts_the_fuse_out() -> void:
	Net.host_solo()
	_drop_a_fake_peer(77, 2)
	assert_true(Net.conceding_in(2) > 0.0)

	# The seat comes back to the same peer id, then that peer says it can draw the world.
	Net._peer_players[78] = 2
	Net._conceding.erase(2)
	assert_eq(Net.conceding_in(2), 0.0)
	Net._tick_concedes(Net.DISCONNECT_GRACE + 1.0)
	assert_eq(Net.host().world.player_for(2).defeat_reason, SimPlayer.Defeat.NONE,
			"a player who came back is not conceded for")


## A seat the match is still holding open is offered before any other, because whoever is
## knocking is overwhelmingly likely to be the player it is being held for.
func test_a_seat_in_its_grace_period_is_offered_back_first() -> void:
	Net.host_solo()
	_drop_a_fake_peer(77, 4)
	assert_eq(Net._next_free_player_id(), 4, "not 2, which is merely the lowest free")


## ⚠️ THE LOBBY HAS NOTHING TO CONCEDE, and arming a timer there would fire a `ResignCommand`
## into a world that does not exist. `host_open()` is a session with no world at all.
func test_a_peer_leaving_the_lobby_lights_no_fuse() -> void:
	Net.host_open(_TEST_PORT)
	_drop_a_fake_peer(77, 2)
	assert_eq(Net.conceding_in(2), 0.0)


## A fuse is a promise about THIS match. One left burning would fire into whatever world
## happened to exist ten seconds later.
func test_leaving_puts_out_every_fuse() -> void:
	Net.host_solo()
	_drop_a_fake_peer(77, 2)
	Net.leave()
	assert_eq(Net.conceding_in(2), 0.0)
