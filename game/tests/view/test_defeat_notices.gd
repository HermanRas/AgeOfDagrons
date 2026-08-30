## Telling the survivors somebody has gone (project owner, 2026-08-30: *"when a player
## disconnects or resigns the server does not notify other players"*), and BUGS.md's older
## *"a forfeit is announced as an elimination"*.
##
## THE SIM HALF IS IN `test_resign.gd` -- that the reason is set, kept and sent. This is
## the half that turns it into a sentence, and it is worth testing on its own because the
## sentence is the entire feature: `defeat_reason` changes nothing about the simulation,
## and a wrong one tells the winner something untrue about how they won.
##
## `GameScene` IS INSTANTIATED WITHOUT ENTERING THE TREE, so `_ready()` never runs and it
## never hosts a match. Everything under test is a pure function of a snapshot dictionary
## plus a toast to write into, which is what makes that possible -- and is a reason to
## keep them that way.
extends TestCase

const GAME_SCENE := preload("res://src/view/game_scene.gd")


## A real toast that also keeps the list. `current_text()` alone cannot tell "said once"
## from "said ten times" -- the banner has no way to be cleared between snapshots, and
## "said ten times a second for the rest of the match" is exactly the failure a one-way
## flag on every snapshot invites.
class RecordingToast extends NoticeToast:
	var said: Array[String] = []

	func show_message(text: String) -> void:
		said.append(text)
		super.show_message(text)


var scene: Node
var toast: RecordingToast


func before_each() -> void:
	scene = GAME_SCENE.new()
	toast = RecordingToast.new()
	scene._toast = toast


func after_each() -> void:
	toast.free()
	scene.free()


## One player's row of `player_state`, in the shape `SnapshotSystem.build` writes.
func _player(reason: int, defeated := true) -> Dictionary:
	return {"age": 1, "colour": 0, "stock": {}, "pop_used": 0, "pop_cap": 10,
			"defeated": defeated, "defeat_reason": reason}


func _snapshot(players: Dictionary, over := false, winner := 0) -> Dictionary:
	return {"tick": 1, "updated": [], "removed": [], "player_state": players,
			"match_over": over, "winner_id": winner}


# ── the mid-match notice ────────────────────────────────────────────────────

func test_a_resignation_is_announced_to_everybody_still_playing() -> void:
	# The gap this closes: in a three-player game one player could resign, a second be
	# wiped out, and the last play on for ten minutes having been told nothing. The result
	# screen only ever appears when the MATCH ends.
	scene._announce_defeats(_snapshot({1: _player(SimPlayer.Defeat.NONE, false),
			3: _player(SimPlayer.Defeat.NONE, false)}))
	scene._announce_defeats(_snapshot({1: _player(SimPlayer.Defeat.NONE, false),
			3: _player(SimPlayer.Defeat.RESIGNED)}))
	assert_eq(toast.current_text(), "Player 3 has resigned")


func test_a_dropped_player_is_not_called_a_quitter() -> void:
	scene._announce_defeats(_snapshot({1: _player(SimPlayer.Defeat.NONE, false)}))
	scene._announce_defeats(_snapshot({1: _player(SimPlayer.Defeat.NONE, false),
			2: _player(SimPlayer.Defeat.DISCONNECTED)}))
	assert_eq(toast.current_text(), "Player 2 has disconnected")


func test_being_wiped_out_still_reads_as_an_elimination() -> void:
	scene._announce_defeats(_snapshot({1: _player(SimPlayer.Defeat.NONE, false)}))
	scene._announce_defeats(_snapshot({1: _player(SimPlayer.Defeat.NONE, false),
			2: _player(SimPlayer.Defeat.ELIMINATED)}))
	assert_eq(toast.current_text(), "Player 2 has been eliminated")


func test_the_opening_snapshot_is_primed_and_not_announced() -> void:
	# ⚠️ A DEFEAT IS A STATE, NOT AN EVENT. A client joining (or reconnecting into) a match
	# where somebody already conceded reads a first snapshot full of `defeated: true`, and
	# would open with a toast about something that happened before it arrived. Same trap
	# `MatchAudio`'s header records for hp.
	scene._announce_defeats(_snapshot({1: _player(SimPlayer.Defeat.NONE, false),
			2: _player(SimPlayer.Defeat.RESIGNED)}))
	assert_true(toast.said.is_empty(), "nothing said about what was already true")


func test_a_defeat_is_announced_once_however_many_snapshots_carry_it() -> void:
	# `defeated` is one-way and rides EVERY snapshot afterwards, so without a record of
	# what has been said this would fire ten times a second for the rest of the match.
	scene._announce_defeats(_snapshot({1: _player(SimPlayer.Defeat.NONE, false)}))
	for i in range(6):
		scene._announce_defeats(_snapshot({1: _player(SimPlayer.Defeat.NONE, false),
				2: _player(SimPlayer.Defeat.RESIGNED)}))
	assert_eq(toast.said, ["Player 2 has resigned"] as Array[String],
			"said once and not again")


func test_the_first_defeat_of_the_match_is_not_swallowed_by_the_priming() -> void:
	# The other half of priming, and the one a sentinel is needed for: a match where nobody
	# is out yet must not stay in the priming state, or the first real defeat is the one
	# that gets eaten.
	for i in range(3):
		scene._announce_defeats(_snapshot({1: _player(SimPlayer.Defeat.NONE, false),
				2: _player(SimPlayer.Defeat.NONE, false)}))
	assert_true(toast.said.is_empty(), "nobody is out yet")
	scene._announce_defeats(_snapshot({1: _player(SimPlayer.Defeat.NONE, false),
			2: _player(SimPlayer.Defeat.DISCONNECTED)}))
	assert_eq(toast.current_text(), "Player 2 has disconnected")


func test_your_own_defeat_gets_the_screen_and_not_a_toast_as_well() -> void:
	# `Net.local_player_id()` is 0 in a headless test, so player 0 stands in for "me".
	scene._announce_defeats(_snapshot({0: _player(SimPlayer.Defeat.NONE, false)}))
	scene._announce_defeats(_snapshot({0: _player(SimPlayer.Defeat.RESIGNED)}))
	assert_true(toast.said.is_empty(), "the result panel says it, once")


# ── the result screen's sentence ────────────────────────────────────────────

func test_a_duel_won_by_a_forfeit_says_so() -> void:
	# THE ORIGINAL BUG. The joiner's process was killed mid-match and the host read "All
	# opponents eliminated" -- true about the outcome, untrue about how it happened.
	assert_eq(scene._victory_subtitle(_snapshot({1: _player(SimPlayer.Defeat.NONE, false),
			2: _player(SimPlayer.Defeat.DISCONNECTED)}, true, 1), 1),
			"Player 2 has disconnected")
	assert_eq(scene._victory_subtitle(_snapshot({1: _player(SimPlayer.Defeat.NONE, false),
			2: _player(SimPlayer.Defeat.RESIGNED)}, true, 1), 1),
			"Player 2 has resigned")


func test_a_conquest_still_reads_as_a_conquest() -> void:
	# The wording every all-conquest match has always had, and the default.
	assert_eq(scene._victory_subtitle(_snapshot({1: _player(SimPlayer.Defeat.NONE, false),
			2: _player(SimPlayer.Defeat.ELIMINATED)}, true, 1), 1),
			"Player 2 has been eliminated")
	assert_eq(scene._victory_subtitle(_snapshot({1: _player(SimPlayer.Defeat.NONE, false),
			2: _player(SimPlayer.Defeat.ELIMINATED),
			3: _player(SimPlayer.Defeat.ELIMINATED)}, true, 1), 1),
			"All opponents eliminated")


func test_several_opponents_are_counted_rather_than_listed() -> void:
	# A 340 px panel cannot hold four names, and "two eliminated, one resigned" is a
	# sentence nobody needs.
	assert_eq(scene._victory_subtitle(_snapshot({1: _player(SimPlayer.Defeat.NONE, false),
			2: _player(SimPlayer.Defeat.RESIGNED),
			3: _player(SimPlayer.Defeat.DISCONNECTED)}, true, 1), 1),
			"Every opponent forfeited")
	assert_eq(scene._victory_subtitle(_snapshot({1: _player(SimPlayer.Defeat.NONE, false),
			2: _player(SimPlayer.Defeat.RESIGNED),
			3: _player(SimPlayer.Defeat.ELIMINATED)}, true, 1), 1),
			"1 opponent forfeited")


func test_resigning_a_duel_tells_you_that_you_resigned_and_not_who_won() -> void:
	# ⚠️ **THE FIRST VERSION OF THIS FIX MISSED THIS CASE AND `preview_match` SHOWED IT
	# WITHIN THE MINUTE.** Resigning a two-player match ENDS it, so `match_over` is true
	# and the winner is the other player -- and the own-reason branch was written under
	# `if not over`, which is only ever a knockout in a bigger game. The panel read
	# "DEFEAT / Player 2 won" at somebody who had just pressed Resign: true, and not an
	# answer to what they did. A forfeit is hoisted above the winner cases now.
	#
	# Player 0 is "me", as everywhere else in this file: `Net.local_player_id()` is 0 in a
	# headless test and no real match ever gives that id to anybody.
	scene._result = ResultScreen.new()
	scene._refresh_result(_snapshot({0: _player(SimPlayer.Defeat.RESIGNED),
			2: _player(SimPlayer.Defeat.NONE, false)}, true, 2))
	assert_eq(scene._result.title_text(), "DEFEAT")
	assert_eq(scene._result.subtitle_text(), "You resigned")
	scene._result.free()


func test_losing_a_duel_by_CONQUEST_still_names_the_winner() -> void:
	# The other side of that hoist: being wiped out is not a forfeit, and who beat you is
	# the useful thing to be told.
	scene._result = ResultScreen.new()
	scene._refresh_result(_snapshot({0: _player(SimPlayer.Defeat.ELIMINATED),
			2: _player(SimPlayer.Defeat.NONE, false)}, true, 2))
	assert_eq(scene._result.subtitle_text(), "Player 2 won")
	scene._result.free()


func test_your_own_defeat_is_worded_in_the_first_person() -> void:
	# "You has resigned" is what sharing one string with `_defeat_phrase` would produce,
	# and DISCONNECTED is not merely a person swap: a player reading this did not choose to
	# drop, so it says the connection went rather than accusing them of leaving.
	assert_eq(scene._own_defeat_text(SimPlayer.Defeat.RESIGNED), "You resigned")
	assert_eq(scene._own_defeat_text(SimPlayer.Defeat.DISCONNECTED),
			"You lost your connection")
	assert_eq(scene._own_defeat_text(SimPlayer.Defeat.ELIMINATED), "You were eliminated")


func test_an_absent_reason_reads_as_an_elimination_rather_than_as_nothing() -> void:
	# An old snapshot, a fixture, a preview. The field defaults to the wording this screen
	# used before it existed, so nothing ever prints an empty sentence.
	assert_eq(scene._defeat_phrase(SimPlayer.Defeat.NONE), "has been eliminated")
	assert_eq(scene._own_defeat_text(SimPlayer.Defeat.NONE), "You were eliminated")
