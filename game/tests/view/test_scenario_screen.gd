## PLAN.md 15.5, the scenario screen.
##
## BACK is not exercised, for the reason `test_help_screen` and `test_pause_menu` both give:
## `_on_back_pressed` calls `get_tree()` unconditionally because it is only ever pressed by a
## screen that is on screen. The scene change in `launch()` is skipped the same way — the
## screen is never parented here, so `launch()` records the config it built and returns, and
## `launched()` is what these tests read.
##
## ⚠️ **PROGRESS COMES OUT OF `user://`, WHICH IS REAL STATE ON THE MACHINE RUNNING THE
## SUITE.** `CampaignProgress` reads `user://campaign_progress.json`, so a developer who has
## actually played the campaign would have a different lock pattern from a fresh checkout —
## which is a test that passes for one person and fails for the next. Every test that cares
## about locking therefore **sets `_progress` directly** and never relies on the file. The
## one test that does read the file asserts only that reading it cannot throw.
extends TestCase

var screen: ScenarioScreen
var campaign: CampaignDef


func before_each() -> void:
	campaign = _how_to_play()
	ScenarioScreen.pending = null
	screen = ScenarioScreen.new()
	screen.open(campaign)


func after_each() -> void:
	screen.free()
	ScenarioScreen.pending = null


func _how_to_play() -> CampaignDef:
	for c in Campaigns.new().discover():
		if c.folder == "HowToPlay":
			return c
	return null


## Re-open at a chosen progress, since the file on disk is not ours to set.
func _at_progress(completions: int) -> void:
	screen._progress = completions
	screen._rebuild_rows()
	screen.select(0)


func test_the_campaign_opens_with_a_row_per_scenario() -> void:
	assert_not_null(campaign, "scenarios/HowToPlay is on disk")
	assert_eq(screen.row_count(), 3)
	assert_eq(screen.campaign().folder, "HowToPlay")


func test_the_heading_is_the_campaign_and_the_panel_is_the_scenario() -> void:
	# The two are different strings and swapping them is the obvious wiring mistake.
	assert_eq(screen._heading.text, campaign.name)
	assert_true(screen.panel_title().ends_with(campaign.scenarios[0].name),
			"panel shows the SCENARIO name, got: " + screen.panel_title())


func test_rows_are_numbered_by_the_declared_order_not_the_folder_name() -> void:
	# `scenario_10` sorts before `scenario_2`, so a screen numbering by name would be wrong
	# the moment a campaign has ten missions. The number comes from the list index.
	_at_progress(2)
	for i in range(screen.row_count()):
		var labels := _labels_of(screen.row(i))
		assert_true(labels.has("%d. %s" % [i + 1, campaign.scenarios[i].name]),
				"row %d numbered from the list order, got %s" % [i, str(labels)])


func test_a_fresh_player_has_only_the_first_scenario_unlocked() -> void:
	# 0 completions unlocks scenario 1 ONLY -- progress is a count, so it is also the index
	# of the first locked scenario. An off-by-one here either locks the tutorial's first page
	# or unlocks the lot.
	_at_progress(0)
	assert_false(screen.row(0).disabled, "scenario 1 is always available")
	assert_true(screen.row(1).disabled, "scenario 2 waits on scenario 1")
	assert_true(screen.row(2).disabled)


func test_finishing_one_scenario_unlocks_exactly_the_next() -> void:
	_at_progress(1)
	assert_false(screen.row(0).disabled, "a beaten scenario stays open for a replay")
	assert_false(screen.row(1).disabled)
	assert_true(screen.row(2).disabled, "and no further")


func test_progress_past_the_end_does_not_unlock_more_than_there_is() -> void:
	# `user://campaign_progress.json` is player-writable and a truncated write can leave
	# anything in it. `unlocked_count` clamps; this is the screen honouring that.
	_at_progress(99)
	for i in range(screen.row_count()):
		assert_false(screen.row(i).disabled, "row %d open" % i)
	assert_eq(screen.row_count(), 3, "and no extra rows appeared")


func test_a_locked_scenario_cannot_be_played_and_says_why() -> void:
	_at_progress(0)
	screen.select(2)
	assert_false(screen.play_enabled())
	assert_true(screen.play_note().contains("Locked"), screen.play_note())


func test_an_objective_scenario_refuses_to_start_and_says_so() -> void:
	# THE HONEST GAP, and the reason this is a test rather than a surprise: scenario 1 and 2
	# are `"mode": "scenario"` and `ScenarioDef.build_config` returns null until 15.2 builds
	# the ObjectiveSystem. A PLAY button that simply did nothing would read as a broken game.
	_at_progress(2)
	screen.select(0)
	assert_eq(campaign.scenarios[0].mode, ScenarioDef.Mode.SCENARIO)
	assert_false(screen.play_enabled(), "objective scenarios wait on 15.2")
	assert_false(screen.play_note().is_empty(), "and the panel says why")


func test_the_last_man_standing_scenario_is_playable_end_to_end() -> void:
	# 15.5's whole point: scenario 3 needs nothing 15.2 has not built, so 15.1 + 15.3 + this
	# is a campaign mission a player can actually start.
	_at_progress(2)
	screen.select(2)
	assert_eq(campaign.scenarios[2].mode, ScenarioDef.Mode.LAST_MAN_STANDING)
	assert_true(screen.play_enabled(), "scenario 3 plays: " + screen.play_note())
	assert_eq(screen.play_note(), "")

	assert_true(screen.launch(), "it builds a config")
	var cfg := screen.launched()
	assert_not_null(cfg)
	assert_eq(cfg.mode, MatchConfig.Mode.LAST_MAN_STANDING)
	# Solo always fills two slots: one human, one AI (owner, 2026-09-01).
	assert_eq(cfg.player_ids.size(), 2, "one human and the one passive opponent")
	assert_false(cfg.ai_players[0], "slot 0 is the player")
	assert_true(cfg.ai_players[1])
	assert_eq(cfg.seed, campaign.scenarios[2].seed, "the authored seed, not a fresh one")
	assert_not_null(cfg.map_data, "and a real map came with it")


func test_launching_a_locked_or_unbuildable_scenario_does_not_start_one() -> void:
	_at_progress(2)
	screen.select(0)
	assert_false(screen.launch(), "an objective scenario cannot build a config yet")
	assert_null(screen.launched(), "and nothing was handed to Net")


func test_selecting_out_of_range_is_ignored_rather_than_crashing() -> void:
	var before := screen.selected_index()
	screen.select(99)
	screen.select(-1)
	assert_eq(screen.selected_index(), before)


func test_selecting_swaps_the_panel_without_touching_the_rows() -> void:
	_at_progress(2)
	screen.select(1)
	assert_eq(screen.selected_index(), 1)
	assert_true(screen.panel_title().ends_with(campaign.scenarios[1].name))
	assert_eq(screen.panel_description(), campaign.scenarios[1].description)
	assert_eq(screen.row_count(), 3, "a selection is not a rebuild")
	assert_true(screen.row(1).button_pressed, "the chosen row reads as chosen")
	assert_false(screen.row(0).button_pressed, "and the others do not")


func test_the_campaign_background_is_loaded_once_when_the_campaign_opens() -> void:
	# `scenarios/README.md`: the background is 1920x1080 and costs a real decode, so it is
	# loaded when a campaign is OPENED and never per row. This asserts it arrived at all --
	# it is outside res:// and `load()` cannot open it, so a wrong route yields null.
	assert_false(campaign.background_path.is_empty(), "HowToPlay ships a background")
	assert_true(screen.has_background(), "ContentImage opened it")


func test_both_columns_scroll() -> void:
	# A VBoxContainer overflows; it does not clip, scroll or compress past its children's
	# minimums, and the lobby shipped with its nav strip off the bottom of the screen for
	# exactly that with every structural test passing. Three scenarios fit today.
	assert_true(screen._list.get_parent() is ScrollContainer, "the scenario column scrolls")
	assert_true(screen._blurb.get_parent() is ScrollContainer,
			"and so does the description, which is authored text of no fixed length")


func test_the_screen_opened_with_no_campaign_explains_itself() -> void:
	# Reachable by loading Scenario.tscn directly, from the editor or from a scene change
	# that forgot to park a campaign.
	var bare := ScenarioScreen.new()
	assert_null(bare.campaign())
	assert_eq(bare.row_count(), 0)
	assert_false(bare.play_enabled(), "and PLAY cannot be pressed")
	assert_false(bare.panel_description().is_empty(), "it says what happened")
	bare.free()


func test_the_pending_campaign_is_consumed_exactly_once() -> void:
	# One-shot, so a second visit with nothing parked shows the no-campaign notice rather
	# than silently reopening the last campaign.
	ScenarioScreen.pending = campaign
	var first := ScenarioScreen.new()
	assert_not_null(first.campaign(), "the parked campaign opened")
	assert_null(ScenarioScreen.pending, "and was taken off the hook")
	first.free()

	var second := ScenarioScreen.new()
	assert_null(second.campaign(), "the next visit starts empty")
	second.free()


func test_reading_progress_off_disk_cannot_throw() -> void:
	# The file belongs to the player, may not exist, and may be anything. Whatever this
	# machine happens to have, it must come back as a non-negative count.
	var n := CampaignProgress.completed("HowToPlay")
	assert_true(n >= 0, "never negative, whatever the file says")
	assert_eq(CampaignProgress.completed("NoSuchCampaign"), 0)


func _labels_of(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child in node.get_children():
		if child is Label:
			out.append((child as Label).text)
		out.append_array(_labels_of(child))
	return out
