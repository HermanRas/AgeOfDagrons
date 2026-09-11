## The King of the Hill standings panel (card 11.x-koth-hud), and the two `GameView` readers
## behind it.
##
## **WHAT CAN GO WRONG HERE IS ARITHMETIC AND STATE, NOT PIXELS.** Whether the panel looks right
## is a screenshot question; what a test can settle is that a player with nobody on the hill is
## not told they are five minutes from winning, that the clock lengthens when the hill contests
## rather than staying optimistic, and that the row the panel golds is the same side the minimap
## rings. All three were decisions rather than accidents -- see `KothStandings`' header.
extends TestCase

var view: GameView
var panel: KothStandings


func before_each() -> void:
	view = GameView.new()
	panel = KothStandings.new()


func after_each() -> void:
	view.free()
	panel.free()


## A `player_state` block as `SnapshotSystem` builds one, carrying only the keys this panel and
## its two readers touch. `rates` and `scores` are keyed by player id.
func _snap(scores: Dictionary, rates: Dictionary, colours: Dictionary = {}) -> Dictionary:
	var state: Dictionary = {}
	for pid in scores:
		state[pid] = {
			"stock": {}, "age": 1, "colour": int(colours.get(pid, pid - 1)),
			"researched": [], "team": 0,
			"score": int(scores[pid]), "koth_rate": int(rates.get(pid, 0)),
		}
	return {"tick": 1, "updated": [], "removed": [], "player_state": state}


# ── the clock ───────────────────────────────────────────────────────────────

## ⚠️ **THE OWNER'S RULING, 2026-09-11: time at the CURRENT rate**, chosen over a best-rate
## reading that would have been stable and permanently optimistic. So the same tally reads three
## different clocks depending on which rung the player is on, and that movement is the whole of
## what §11.9's ladder does.
func test_the_clock_is_read_at_the_rate_the_player_is_actually_scoring() -> void:
	view.apply_snapshot(_snap({1: 0, 2: 0, 3: 0}, {1: 3, 2: 2, 3: 1}))
	# 9,000 at 3/tick and 10 Hz is 300 s; at 2, 450; at 1, 900. PLAN.md §11.9's own table.
	assert_eq(view.koth_seconds_remaining(1), 300.0, "alone on it")
	assert_eq(view.koth_seconds_remaining(2), 450.0, "leading, with company")
	assert_eq(view.koth_seconds_remaining(3), 900.0, "present or tied")


## ⚠️ **-1 IS "NEVER" AND IT IS NOT 0.** A player with nobody on the hill approaches nothing, and
## a naive `remaining / rate` would divide by zero. 0 means they have arrived, which is a
## completely different row.
func test_a_player_off_the_hill_has_no_finite_time() -> void:
	view.apply_snapshot(_snap({1: 4500}, {1: 0}))
	assert_eq(view.koth_seconds_remaining(1), -1.0)
	assert_eq(KothStandings.format_time(-1.0), KothStandings.NO_TIME)


func test_a_player_who_has_arrived_reads_zero_rather_than_never() -> void:
	view.apply_snapshot(_snap({1: WinConditionSystem.KOTH_TARGET_SCORE}, {1: 3}))
	assert_eq(view.koth_seconds_remaining(1), 0.0)
	assert_eq(KothStandings.format_time(0.0), "0:00")


func test_the_clock_counts_down_as_the_tally_climbs() -> void:
	view.apply_snapshot(_snap({1: 0}, {1: 3}))
	var far := view.koth_seconds_remaining(1)
	view.apply_snapshot(_snap({1: 4500}, {1: 3}))
	var near := view.koth_seconds_remaining(1)
	assert_true(near < far, "%f should be less than %f" % [near, far])
	assert_eq(near, 150.0, "halfway there at the same rate is half the time")


## Formatting, asserted directly because a `M:SS` that renders 65 seconds as "1:5" is the kind of
## defect that survives every other test in this file.
func test_the_clock_is_formatted_as_minutes_and_padded_seconds() -> void:
	assert_eq(KothStandings.format_time(195.0), "3:15")
	assert_eq(KothStandings.format_time(65.0), "1:05", "padded, not 1:5")
	assert_eq(KothStandings.format_time(900.0), "15:00", "and two-digit minutes fit")
	assert_eq(KothStandings.format_time(5.0), "0:05")


## ⚠️ **ASCII, DELIBERATELY.** §6: the shipped body face draws a glyph it lacks as a tofu box
## rather than failing, and an em dash is not on the measured list of what New Rocker HAS. A test
## cannot see a tofu box, so what it can do is pin that nothing here reaches for one.
func test_the_no_time_marker_is_plain_ascii() -> void:
	for c in KothStandings.NO_TIME:
		assert_true(c.unicode_at(0) < 128,
				"%s is not ASCII and a missing glyph draws as tofu, silently" % c)


# ── the rows ────────────────────────────────────────────────────────────────

func test_it_builds_one_row_per_player_in_player_order() -> void:
	panel.setup([1, 2, 3], 1)
	assert_eq(panel.row_count(), 3)
	assert_eq(panel.row_player(0), 1)
	assert_eq(panel.row_player(1), 2)
	assert_eq(panel.row_player(2), 3)
	assert_true(panel.visible)


## An empty list is every non-KotH match. A heading with no rows under it is worse than no panel.
func test_no_players_means_no_panel() -> void:
	panel.setup([], 1)
	assert_eq(panel.row_count(), 0)
	assert_false(panel.visible)


## `setup()` latches, because both paths into `GameScene._start_match()` run it and a client
## whose config arrived late runs it twice. Without this the table doubles.
func test_setting_it_up_twice_does_not_double_the_table() -> void:
	panel.setup([1, 2], 1)
	panel.setup([1, 2], 1)
	assert_eq(panel.row_count(), 2)


func test_a_row_shows_the_tally_and_the_clock() -> void:
	panel.setup([1, 2], 1)
	view.apply_snapshot(_snap({1: 2730, 2: 480}, {1: 3, 2: 0}))
	panel.show_standings(view, 1)
	assert_eq(panel.row_score(0), "2,730", "grouped, because the target is five figures")
	# (9000 - 2730) / (3 * 10) = 209 s. ⚠️ **THIS LITERAL WAS 1:30 AND THE CODE WAS RIGHT** --
	# worked from the wrong target while writing the test. Left as a note because the whole
	# family of mistakes this file exists to catch is arithmetic done once and believed.
	assert_eq(panel.row_time(0), "3:29")
	assert_eq(panel.row_time(1), KothStandings.NO_TIME, "player 2 has nobody on it")


# ── the panel and the ring must agree ───────────────────────────────────────

## ⚠️ **THE GOLD ROW IS THE SIDE THE MINIMAP RINGS**, and both are fed from one `holder` read in
## one function for exactly this reason — two reads in two places is how they come apart.
func test_the_holder_is_gold_and_a_present_rival_is_not() -> void:
	panel.setup([1, 2, 3], 1)
	view.apply_snapshot(_snap({1: 100, 2: 100, 3: 0}, {1: 2, 2: 1, 3: 0}))
	panel.show_standings(view, 1)
	assert_eq(panel.row_colour(0), KothStandings.LEADER_COLOR, "the holder")
	assert_eq(panel.row_colour(1), KothStandings.PRESENT_COLOR, "on it, and losing")
	assert_eq(panel.row_colour(2), KothStandings.IDLE_COLOR, "not on it at all")


## ⚠️ **A CONTESTED HILL HAS NO HOLDER AND THEREFORE NO GOLD ROW** — `koth_holder` is 0 on a tie.
## Both sides are still SCORING through it, which is what the ladder changed on 2026-09-11, so
## the panel must show two live clocks and no leader rather than freezing or blanking.
func test_a_contested_hill_golds_nobody_and_still_runs_two_clocks() -> void:
	panel.setup([1, 2], 1)
	view.apply_snapshot(_snap({1: 300, 2: 300}, {1: 1, 2: 1}))
	panel.show_standings(view, 0)
	assert_eq(panel.row_colour(0), KothStandings.PRESENT_COLOR)
	assert_eq(panel.row_colour(1), KothStandings.PRESENT_COLOR)
	assert_ne(panel.row_time(0), KothStandings.NO_TIME,
			"contested is slower, never stopped -- that is the whole point of the ladder")
	assert_eq(panel.row_time(0), panel.row_time(1), "and evenly matched, identical")


## A row must not vanish when its player leaves the hill: a missing row reads as eliminated.
## It dims instead, and keeps its banked tally on show.
func test_a_player_who_leaves_the_hill_keeps_their_row_and_their_tally() -> void:
	panel.setup([1], 1)
	view.apply_snapshot(_snap({1: 600}, {1: 3}))
	panel.show_standings(view, 1)
	assert_eq(panel.row_time(0), "4:40")

	view.apply_snapshot(_snap({1: 600}, {1: 0}))
	panel.show_standings(view, 0)
	assert_eq(panel.row_count(), 1, "still there")
	assert_eq(panel.row_score(0), "600", "and the progress is not lost")
	assert_eq(panel.row_time(0), KothStandings.NO_TIME)
	assert_eq(panel.row_colour(0), KothStandings.IDLE_COLOR)
