## Phase 15.6 (second half): the live objective tracker, and the alert toast beside it.
##
## THE FIRST HALF -- the briefing modal -- IS IN `test_scenario_briefing.gd`, and the two
## halves answer different questions. The briefing is about CONSENT: the goal was put in
## front of the player once. This is about the rest of the match, and it exists because of
## what 15.2's play-test found: the owner stopped building on a scenario that was winnable
## throughout, because there was nothing on screen saying how far along they were. A rule
## that is correct but unreached and a rule that is wrong look identical from the player's
## chair -- both are *"nothing happens"*.
##
## ⚠️ **THE SIM HALF IS `test_objectives.gd` AND IS NOT REPEATED HERE.** Whether a row is
## satisfied is `ObjectiveSystem`'s question and is decided on the server; everything below
## takes `objective_progress`/`objective_done` as given and asks only what the player sees.
## That split is the point -- a tracker that counted villagers itself would be a second
## evaluator, and the tick it disagreed with the server would be a player watching
## "14 / 14" while the match refused to end.
##
## `GameScene` IS INSTANTIATED WITHOUT ENTERING THE TREE for the wiring cases, exactly as
## `test_defeat_notices.gd` does it: `_ready()` never runs, no match is hosted, and both
## functions under test are pure functions of a snapshot dictionary plus two widgets to
## write into.
extends TestCase

const GAME_SCENE := preload("res://src/view/game_scene.gd")


## A toast that keeps the list. `current_text()` cannot tell "said once" from "said ten
## times a second for the rest of the match", which is the exact failure a latched flag
## read on every snapshot invites.
class RecordingToast extends NoticeToast:
	var said: Array[String] = []

	func show_message(text: String) -> void:
		said.append(text)
		super.show_message(text)

	func show_long_message(text: String) -> void:
		said.append(text)
		super.show_long_message(text)


var tracker: ObjectiveTracker


func before_each() -> void:
	tracker = ObjectiveTracker.new()


func after_each() -> void:
	tracker.free()


## Through the real parser rather than by setting fields, so a row here is a row a
## `scenario.json` could actually contain -- and so a change to the vocabulary breaks this
## file rather than letting it test a shape that no longer loads.
func _objective(d: Dictionary) -> ObjectiveDef:
	var problems: Array[String] = []
	var o := ObjectiveDef.from_dict(d, problems)
	assert_true(o != null, "fixture must parse: %s" % ", ".join(problems))
	return o


func _house() -> ObjectiveDef:
	return _objective({"subject": "building", "id": "building.house", "owner": "self",
			"compare": ">=", "value": 1, "output": "win", "text": "Build a house"})


func _villagers() -> ObjectiveDef:
	return _objective({"subject": "unit", "id": "unit.villager", "owner": "self",
			"compare": ">=", "value": 14, "output": "win", "text": "Reach 14 villagers"})


# ── what gets a row ─────────────────────────────────────────────────────────

func test_it_lists_win_rows_and_leaves_the_other_two_outputs_alone() -> void:
	# An `alert` is a message and a `lose` is a failure condition -- "Lose your town centre
	# 1 / 1" is a checklist item nobody wants ticked. The author words both in `message`.
	var alert := _objective({"subject": "unit", "owner": "enemy", "compare": ">=",
			"value": 5, "output": "alert", "text": "Raiders are massing"})
	var lose := _objective({"subject": "building", "id": "building.town_center",
			"owner": "self", "compare": "<=", "value": 0, "output": "lose",
			"text": "Your town centre falls"})
	tracker.setup([alert, _house(), lose] as Array[ObjectiveDef])
	assert_eq(tracker.row_count(), 1)
	assert_true(tracker.visible)


func test_a_rows_index_is_its_place_in_the_FULL_list_and_not_its_place_on_the_panel() -> void:
	# ⚠️ THE ONE MISTAKE THAT WOULD LOOK PLAUSIBLE ON SCREEN. `objective_progress` is
	# indexed by position in the whole authored list, alerts and losses included, so a
	# tracker that numbered its own rows would show the house count against the villager
	# target -- two real numbers, wrongly paired, on a panel that looks fine.
	var alert := _objective({"subject": "age", "owner": "enemy", "compare": ">=",
			"value": 3, "output": "alert", "text": "The enemy has advanced"})
	tracker.setup([alert, _house(), _villagers()] as Array[ObjectiveDef])
	assert_eq(tracker.row_count(), 2)
	assert_eq(tracker.row_index(0), 1, "the house is objective 1, not objective 0")
	assert_eq(tracker.row_index(1), 2)
	tracker.show_progress([9, 0, 4], [0, 0, 0])
	assert_true(tracker.row_line(0).contains("0 / 1"), tracker.row_line(0))
	assert_true(tracker.row_line(1).contains("4 / 14"), tracker.row_line(1))


func test_a_scenario_with_no_objectives_shows_nothing_at_all() -> void:
	# Every skirmish, every debug factory, and the three How To Play missions won by
	# conquest -- `ScenarioDef` refuses objectives on a `last_man_standing` scenario, so
	# those carry none. An empty frame with a heading on it is worse than no frame.
	tracker.setup([] as Array[ObjectiveDef])
	assert_eq(tracker.row_count(), 0)
	assert_false(tracker.visible)


func test_setup_runs_twice_on_a_client_and_builds_one_list() -> void:
	# `GameScene._start_match()` runs from `_ready()` and again from `match_configured`
	# when a joining client's config lands. Same latch, same reason, as the briefing's.
	tracker.setup([_house(), _villagers()] as Array[ObjectiveDef])
	tracker.setup([_house(), _villagers()] as Array[ObjectiveDef])
	assert_eq(tracker.row_count(), 2)


# ── what a row says ─────────────────────────────────────────────────────────

func test_a_row_carries_the_authors_own_words_and_this_tick_s_count() -> void:
	tracker.setup([_villagers()] as Array[ObjectiveDef])
	tracker.show_progress([4], [0])
	assert_true(tracker.row_line(0).contains("Reach 14 villagers"), tracker.row_line(0))
	assert_true(tracker.row_line(0).contains("4 / 14"), tracker.row_line(0))
	assert_false(tracker.row_is_done(0))


func test_a_row_with_no_authored_text_still_reads_as_something() -> void:
	# `ObjectiveDef.describe()` is never empty, and 16.6's Map Conditions screen will author
	# rows before it authors labels for them. A row with no label is a line the player reads
	# as a bug.
	var bare := _objective({"subject": "unit", "id": "unit.villager", "owner": "self",
			"compare": ">=", "value": 3, "output": "win"})
	tracker.setup([bare] as Array[ObjectiveDef])
	assert_false(tracker.row_line(0).strip_edges().is_empty())
	assert_true(tracker.row_line(0).contains("unit.villager"), tracker.row_line(0))


func test_a_completed_row_is_ticked_AND_recoloured() -> void:
	# Two signals rather than one: "ticked and still grey" and "gold and unticked" are both
	# screenshots somebody would report as a bug.
	tracker.setup([_house()] as Array[ObjectiveDef])
	tracker.show_progress([1], [1])
	assert_true(tracker.row_is_done(0))
	assert_eq(tracker.row_colour(0), ObjectiveTracker.DONE_COLOR)
	assert_true(tracker.row_line(0).contains("1 / 1"))


func test_a_ticked_row_does_not_untick_when_the_count_falls() -> void:
	# ⚠️ THE LATCH IS THE SIM'S AND THIS RENDERS IT. `ObjectiveSystem` keeps
	# `objective_done` one-way precisely so a house burning down cannot take a completed
	# line off the checklist -- and a tracker that decided "done" by re-comparing the count
	# against the target would undo that decision on the client, which is where the player
	# is looking.
	tracker.setup([_house()] as Array[ObjectiveDef])
	tracker.show_progress([1], [1])
	tracker.show_progress([0], [1])
	assert_true(tracker.row_is_done(0), "the sim still says done, so the panel does")
	assert_true(tracker.row_line(0).contains("0 / 1"), "and the live count is honest")


func test_an_at_most_row_says_what_its_number_is_FOR() -> void:
	# A ceiling with room under it: "2 of at most 5" is a number to stay below, and drawing
	# it as "2 / 5" would tell a player to climb towards it.
	#
	# ⚠️ **THIS TEST USED TO USE `<= 0` AND ASSERT `"3 / max 0"`, AND THAT ASSERTION IS NOW
	# REVERSED** -- see the zero-target test below for why and by whom. The `max` form is
	# still right and is still tested; it is only the target of ZERO that left it.
	var few := _objective({"subject": "unit", "id": "unit.wolf", "owner": "gaia",
			"compare": "<=", "value": 5, "output": "win", "text": "Thin out the wolves"})
	tracker.setup([few] as Array[ObjectiveDef])
	tracker.show_progress([2], [1])
	assert_true(tracker.row_line(0).contains("2 / max 5"), tracker.row_line(0))


func test_a_target_of_ZERO_counts_what_you_KILLED_and_not_what_is_left() -> void:
	# ⚠️ **REPORTED BY THE OWNER OFF SCENARIO 4, 2026-09-06**: *"kill dragon 0/0 does not
	# read correctly, invert the count for units killed so the status reads 1/1."* The row
	# is `unit.dragon`, gaia's, `== 0`. Once the mother was dead the honest measurement was
	# 0 against a target of 0, so the panel drew **"0 / 0" beside a tick** -- which reads as
	# a bug rather than as a completed goal, in a screenshot of a scenario that had in fact
	# been won.
	#
	# **`_progress_text`'s own note had already named this failure and the `==` branch walked
	# past it.** It said *"3 / 0 reads as a bug"* -- about `<=` -- and then said AT_LEAST and
	# EXACTLY share a form because *"both are numbers to arrive AT"*. True of `== 1`. False
	# of `== 0`: **nothing counts up to zero.** So the rule is the TARGET and not the
	# comparison, and `<= 0` and `== 0` now draw the same because they ask the same thing.
	var mother := _objective({"subject": "unit", "id": "unit.dragon", "owner": "gaia",
			"compare": "==", "value": 0, "output": "win", "text": "Kill the mother dragon"})
	var none_left := _objective({"subject": "unit", "owner": "enemy", "compare": "<=",
			"value": 0, "output": "win", "text": "Leave the enemy nothing"})
	tracker.setup([mother, none_left] as Array[ObjectiveDef])

	# She is alive: one dragon on the map, and NEITHER row done. The old rendering put "1 / 0"
	# and "3 / max 0" here.
	tracker.show_progress([1, 3], [0, 0])
	assert_true(tracker.row_line(0).contains("0 / 1"), tracker.row_line(0))
	assert_true(tracker.row_line(1).contains("0 / 1"), tracker.row_line(1))

	# Dead. This is the line in the owner's screenshot.
	tracker.show_progress([0, 0], [1, 1])
	assert_true(tracker.row_line(0).contains("1 / 1"), tracker.row_line(0))
	assert_true(tracker.row_line(1).contains("1 / 1"), tracker.row_line(1))
	assert_false(tracker.row_line(0).contains("0 / 0"),
			"the reading that started this: %s" % tracker.row_line(0))


func test_a_zero_target_reads_the_sims_latch_and_never_the_count() -> void:
	# ⚠️ **THE TRACKER MUST NOT WORK OUT `done` FROM `measured == 0` ITSELF**, which for a
	# zero-target row is the one place it looks equivalent and is not. `objective_done` is
	# one-way in the sim precisely so a verdict cannot flicker off; deriving it here would
	# undo that on the client, which is where the player is looking. Nothing can raise gaia's
	# dragon count back today -- 16.7's named units will make a route -- so this pins the
	# rule while it is still cheap.
	var mother := _objective({"subject": "unit", "id": "unit.dragon", "owner": "gaia",
			"compare": "==", "value": 0, "output": "win", "text": "Kill the mother dragon"})
	tracker.setup([mother] as Array[ObjectiveDef])

	# Count says zero, the SIM says not done. The panel follows the sim.
	tracker.show_progress([0], [0])
	assert_true(tracker.row_line(0).contains("0 / 1"), tracker.row_line(0))
	assert_false(tracker.row_is_done(0))

	# And the other way: a count that came back up cannot untick a latched row.
	tracker.show_progress([0], [1])
	tracker.show_progress([1], [1])
	assert_true(tracker.row_line(0).contains("1 / 1"), tracker.row_line(0))
	assert_true(tracker.row_is_done(0))


func test_the_snapshot_before_the_first_evaluation_draws_no_zeros() -> void:
	# `ObjectiveSystem` sizes both arrays on its FIRST TICK -- empty means "nothing has been
	# evaluated", which is `VisionSystem`'s convention and not a list of zeros. The snapshot
	# that stands the match up carries neither, and a panel that printed "0 / 14" there
	# would be stating a measurement the sim never made.
	tracker.setup([_villagers()] as Array[ObjectiveDef])
	tracker.show_progress([], [])
	assert_true(tracker.row_line(0).contains("--"), tracker.row_line(0))
	assert_false(tracker.row_is_done(0))


func test_the_unmeasurable_sentinel_is_never_printed_as_a_number() -> void:
	# `ObjectiveSystem._count` returns -1 for a subject it cannot measure, and `_satisfied`
	# fails every comparison against it. No shipped row can produce one; printing "-1 / 14"
	# in a HUD is how a sentinel becomes a bug report about arithmetic.
	tracker.setup([_villagers()] as Array[ObjectiveDef])
	tracker.show_progress([-1], [0])
	assert_true(tracker.row_line(0).contains("--"), tracker.row_line(0))


func test_it_cannot_swallow_a_tap() -> void:
	# `mouse_filter` DOES NOT INHERIT, and `NoticeToast`'s header records what that cost to
	# learn: a widget over the HUD that quietly took presses read as three build-menu tiles
	# being broken for a week. This panel sits over the map and has nothing to press.
	tracker.setup([_house(), _villagers()] as Array[ObjectiveDef])
	var stack: Array[Node] = [tracker]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Control:
			assert_eq((node as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE,
					"%s takes presses" % node.get_class())
		for child in node.get_children():
			stack.append(child)


# ── the shipped content ─────────────────────────────────────────────────────

func test_every_shipped_scenario_that_has_objectives_produces_a_readable_tracker() -> void:
	# DERIVED FROM THE CONTENT, not counted against a constant. That lesson cost three false
	# failures in one day on 2026-09-02, the last of them a stale `3` after the campaign
	# grew to five scenarios -- which failed reading "scenario_4: Locked" and looked like a
	# broken scenario rather than a stale number.
	var checked := 0
	for c in Campaigns.new().discover():
		for s in c.scenarios:
			if s.objectives.is_empty():
				continue
			checked += 1
			var fresh := ObjectiveTracker.new()
			fresh.setup(s.objectives)
			assert_true(fresh.row_count() > 0,
					"%s/%s has objectives but no win row to show" % [c.folder, s.folder])
			for row in range(fresh.row_count()):
				assert_false(fresh.row_line(row).strip_edges().is_empty(),
						"%s/%s row %d is blank" % [c.folder, s.folder, row])
			fresh.free()
	assert_true(checked >= 2,
			"scenarios 1 and 2 are the authored-objective missions; found %d" % checked)


# ── the GameScene wiring ────────────────────────────────────────────────────

var scene: Node
var toast: RecordingToast


func _scene_with(objectives: Array[ObjectiveDef], objective_player := 1) -> void:
	scene = GAME_SCENE.new()
	toast = RecordingToast.new()
	scene._toast = toast
	scene._tracker = tracker
	scene._scenario_objectives = objectives
	scene._objective_player_id = objective_player
	tracker.setup(objectives)


func _free_scene() -> void:
	toast.free()
	scene.free()


func _snapshot(progress: Array, done: Variant, player := 1) -> Dictionary:
	return {"tick": 1, "updated": [], "removed": [], "match_over": false,
			"player_state": {player: {"age": 1, "stock": {}, "pop_used": 0, "pop_cap": 10,
					"objective_progress": progress, "objective_done": done}}}


func test_the_progress_is_read_from_the_OBJECTIVE_PLAYER_and_not_from_the_viewer() -> void:
	# ⚠️ `ObjectiveSystem` FILLS ONE PLAYER'S ARRAYS AND NOBODY ELSE'S. Reading the local
	# player's row would draw an empty tracker for anybody who is not the protagonist --
	# which is nobody today and is a co-op scenario tomorrow. `Net.local_player_id()` is 0
	# in a headless test, so player 2 here is emphatically not the viewer.
	_scene_with([_villagers()] as Array[ObjectiveDef], 2)
	scene._refresh_objectives(_snapshot([7], [0], 2))
	assert_true(tracker.row_line(0).contains("7 / 14"), tracker.row_line(0))
	_free_scene()


func test_objective_done_arrives_as_a_packed_byte_array_and_is_read_as_one() -> void:
	# It is a `PackedByteArray` in `SimPlayer` and rides the snapshot as one. Worth pinning:
	# `JSON.stringify` encodes a PackedByteArray as the STRING "[1, 0]" (verified on 4.7.1,
	# and `MapData.from_dict` carries the scar), so the day anything puts a snapshot through
	# JSON this is where it surfaces.
	_scene_with([_house()] as Array[ObjectiveDef])
	scene._refresh_objectives(_snapshot([1], PackedByteArray([1])))
	assert_true(tracker.row_is_done(0))
	_free_scene()


func test_a_snapshot_that_carries_no_objective_fields_changes_nothing() -> void:
	# An older host, a fixture, the tick before `ObjectiveSystem` first ran.
	_scene_with([_house()] as Array[ObjectiveDef])
	scene._refresh_objectives({"tick": 1, "player_state": {1: {"age": 1}}})
	assert_false(tracker.row_is_done(0))
	assert_true(tracker.row_line(0).contains("--"))
	_free_scene()


func test_a_non_scenario_config_carrying_objectives_stands_nothing_up() -> void:
	# ⚠️ GATED ON THE MODE, WHICH IS `ObjectiveSystem`'s OWN GUARD COPIED. Outside SCENARIO
	# nothing in the sim ever measures a row, so a panel here would read "0 / 14" for the
	# whole match with no tick able to move it -- a goal the player appears to be failing.
	# `ScenarioDef` refuses this combination; a hand-built config or 16.6 could still make it.
	scene = GAME_SCENE.new()
	scene._tracker = tracker
	var cfg := MatchConfig.new()
	cfg.mode = MatchConfig.Mode.LAST_MAN_STANDING
	cfg.objectives = [_house()] as Array[ObjectiveDef]
	cfg.objective_player_id = 1
	scene._setup_objectives(cfg)
	assert_eq(tracker.row_count(), 0)
	assert_false(tracker.visible)
	assert_true(scene._scenario_objectives.is_empty())
	scene.free()


# ── the alert toast ─────────────────────────────────────────────────────────

func _alert(text: String) -> ObjectiveDef:
	return _objective({"subject": "unit", "owner": "enemy", "compare": ">=", "value": 5,
			"output": "alert", "text": text})


func test_an_alert_row_speaks_once_however_many_snapshots_carry_it() -> void:
	# THE LATCH IS WHY THIS CAN BE A LEVEL RATHER THAN AN EDGE. `ObjectiveSystem` sets
	# `objective_done` for an alert row and never clears it, and the row rides every
	# snapshot afterwards -- so without a record of what has been said this is ten banners
	# a second for the rest of the match.
	_scene_with([_alert("Raiders")] as Array[ObjectiveDef])
	scene._refresh_objectives(_snapshot([0], [0]))
	for i in range(6):
		scene._refresh_objectives(_snapshot([9], [1]))
	assert_eq(toast.said, ["Raiders"] as Array[String])
	_free_scene()


func test_the_opening_snapshot_primes_alerts_rather_than_announcing_them() -> void:
	# A latched alert is a STATE. A client joining or reconnecting into a scenario mid-way
	# reads a first snapshot with the row already done and would open with a banner about
	# something that fired before it arrived -- `_announce_defeats`' trap in the same coat.
	_scene_with([_alert("Raiders")] as Array[ObjectiveDef])
	scene._refresh_objectives(_snapshot([9], [1]))
	assert_true(toast.said.is_empty())
	_free_scene()


func test_the_first_alert_of_the_match_is_not_swallowed_by_the_priming() -> void:
	# The other half of priming, and what the sentinel is for: a scenario whose alert has
	# not fired yet must not stay primed forever.
	_scene_with([_alert("Raiders")] as Array[ObjectiveDef])
	for i in range(3):
		scene._refresh_objectives(_snapshot([0], [0]))
	assert_true(toast.said.is_empty(), "nothing has fired yet")
	scene._refresh_objectives(_snapshot([9], [1]))
	assert_eq(toast.current_text(), "Raiders")
	_free_scene()


func test_a_long_alert_gets_the_paragraph_banner_and_a_short_one_does_not() -> void:
	# `show_long_message` was built on 2026-08-30 for exactly this (*"the current alert box
	# can be reused in single player campaigns for long text"*) and had never had a caller.
	var long_text := "The enemy has crossed the river in force and is moving on your town."
	_scene_with([_alert("Raiders"), _alert(long_text)] as Array[ObjectiveDef])
	scene._refresh_objectives(_snapshot([0, 0], [0, 0]))
	scene._refresh_objectives(_snapshot([9, 0], [1, 0]))
	assert_false(toast.is_long(), "a label-length alert stays in the small banner")
	scene._refresh_objectives(_snapshot([9, 9], [1, 1]))
	assert_true(toast.is_long(), "a sentence gets the one that can hold one")
	_free_scene()


func test_a_win_row_completing_says_nothing_at_all() -> void:
	# The tracker ticks it. A banner as well would be the same news twice, and a scenario
	# with four win rows would be four banners in a match that is about to end anyway.
	_scene_with([_house()] as Array[ObjectiveDef])
	scene._refresh_objectives(_snapshot([0], [0]))
	scene._refresh_objectives(_snapshot([1], [1]))
	assert_true(toast.said.is_empty())
	assert_true(tracker.row_is_done(0))
	_free_scene()
