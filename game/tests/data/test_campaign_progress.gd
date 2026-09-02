## Phase 15.7: `user://campaign_progress.json` — reading it, and now writing it.
##
## ## ⚠️ NOTHING HERE TOUCHES THE REAL FILE, AND THAT IS THE FIRST RULE OF THIS FILE
##
## `CampaignProgress.USER_FILE` is real state on whoever runs the suite. A test that WROTE
## it would rewrite the developer's own campaign progress; a test that READ it passes on a
## fresh checkout and fails on a machine that has played the game. **Both halves of that
## have already bitten this project on 2026-09-02** — a progress file written by hand to
## unlock all three missions for a play-test turned `test_scenario_screen`'s heading test
## into a failure with nothing to do with what it tested.
##
## So every function takes a `path` and every test below passes its own, under a directory
## named for this file. `USER_FILE` appears exactly once here: in the test that asserts the
## default argument still points at it.
##
## ## WHAT IS ACTUALLY WORTH TESTING
##
## The write is four lines. The value is in the properties around it: that progress is a
## MAXIMUM and never a rewind, that a replay of an early mission cannot re-lock the later
## ones, and that a file the player has edited into nonsense cannot crash or silently lose
## a campaign it could still read.
extends TestCase

const DIR := "user://test_campaign_progress"

## ONE PATH, DELETED BEFORE EVERY TEST, rather than a counter-per-test.
##
## ⚠️ **A `case_%d` COUNTER WAS THE FIRST VERSION AND IT WAS WRONG IN TWO WAYS.** The
## instance is created once per FILE and `before_each` runs per method, so the counter did
## give each test its own name -- but the files **survive between suite runs**, so a test
## reading one was reading whatever the last run left in it, and any change to the tests
## above it silently renumbered everything below. Deleting one known path is shorter and
## cannot drift.
const PATH := "user://test_campaign_progress/progress.json"


func before_each() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)
	# A missing file is the state most of these tests start from, so removing it IS the
	# setup rather than tidying up after the last one.
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _path() -> String:
	return PATH


func _write_raw(text: String) -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	f.store_string(text)
	f.close()


# ── the default, which is the one thing that must still name the real file ─────

func test_the_default_path_is_the_players_own_progress_file() -> void:
	# The `path` parameter exists for the tests; production calls take the default, and a
	# default that had drifted would mean the game wrote its progress somewhere nobody reads.
	assert_eq(CampaignProgress.USER_FILE, "user://campaign_progress.json")


# ── reading ───────────────────────────────────────────────────────────────────

func test_an_absent_file_is_every_campaign_unstarted() -> void:
	# Which is every player who has not finished a scenario, so it is not worth a warning
	# and certainly not worth an error.
	assert_eq(CampaignProgress.all(_path()), {})
	assert_eq(CampaignProgress.completed("HowToPlay", _path()), 0)


func test_a_recorded_count_reads_back() -> void:
	_write_raw('{"HowToPlay": 2}')
	assert_eq(CampaignProgress.completed("HowToPlay", _path()), 2)
	assert_eq(CampaignProgress.completed("SomeOtherCampaign", _path()), 0,
			"a campaign with no row is unstarted, not an error")


func test_a_number_arriving_as_a_json_float_still_reads_as_an_int() -> void:
	# JSON has one number type, so `1` may arrive either way depending on what wrote it --
	# and this file is written by the game AND edited by hand.
	_write_raw('{"HowToPlay": 2.0}')
	assert_eq(CampaignProgress.completed("HowToPlay", _path()), 2)


func test_a_negative_count_reads_as_zero_rather_than_locking_the_first_scenario() -> void:
	# ⚠️ A negative would pass into `CampaignDef.unlocked_count()`'s `clampi` and lock
	# scenario 1 -- a campaign the player cannot start and the game cannot explain.
	_write_raw('{"HowToPlay": -5}')
	assert_eq(CampaignProgress.completed("HowToPlay", _path()), 0)


func test_a_value_that_is_not_a_number_reads_as_unstarted() -> void:
	# A hand-edited or half-written file, not a number to coerce quietly.
	for junk: String in ['{"HowToPlay": "two"}', '{"HowToPlay": {}}',
			'{"HowToPlay": null}', '{"HowToPlay": [1]}']:
		# Overwritten rather than a file per case: each `_write_raw` replaces the last, so
		# the case under test is the only thing in it.
		_write_raw(junk)
		assert_eq(CampaignProgress.completed("HowToPlay", _path()), 0, junk)


func test_malformed_json_reads_as_unstarted_rather_than_crashing() -> void:
	# `user://` is a directory the player can open, and a half-finished write can truncate
	# the file mid-object.
	_write_raw('{"HowToPlay": 1')
	assert_eq(CampaignProgress.all(_path()), {})


func test_a_json_file_that_is_not_an_object_reads_as_unstarted() -> void:
	_write_raw('[1, 2, 3]')
	assert_eq(CampaignProgress.all(_path()), {})


# ── writing (15.7) ────────────────────────────────────────────────────────────

func test_finishing_the_first_scenario_records_one_completion() -> void:
	# **PROGRESS IS A COUNT, so it is also the index of the first LOCKED scenario.**
	# Finishing `scenarios[0]` is one completion, which unlocks `scenarios[1]`.
	assert_true(CampaignProgress.record_completed("HowToPlay", 0, _path()))
	assert_eq(CampaignProgress.completed("HowToPlay", _path()), 1)


func test_the_recorded_count_is_the_index_plus_one() -> void:
	assert_true(CampaignProgress.record_completed("HowToPlay", 2, _path()))
	assert_eq(CampaignProgress.completed("HowToPlay", _path()), 3,
			"finishing the third of three is three completions, which unlocks nothing"
			+ " further and is what `unlocked_count` clamps")


func test_recording_the_same_win_twice_changes_nothing() -> void:
	# A result screen can be reached twice, and a player may replay a mission they have
	# already beaten. `maxi` makes both a no-op rather than a rewind.
	CampaignProgress.record_completed("HowToPlay", 1, _path())
	assert_eq(CampaignProgress.completed("HowToPlay", _path()), 2)
	assert_true(CampaignProgress.record_completed("HowToPlay", 1, _path()),
			"already recorded still counts as recorded")
	assert_eq(CampaignProgress.completed("HowToPlay", _path()), 2)


func test_replaying_an_early_scenario_cannot_relock_the_later_ones() -> void:
	# ⚠️ **THE FAILURE A PLAIN ASSIGNMENT WOULD CAUSE, and it would look like the game
	# forgetting the whole campaign.** Beat all three, go back and replay the tutorial's
	# first page for fun, and a `data[folder] = index + 1` would drop progress to 1 and
	# lock scenarios 2 and 3 again.
	CampaignProgress.record_completed("HowToPlay", 2, _path())
	assert_eq(CampaignProgress.completed("HowToPlay", _path()), 3)
	CampaignProgress.record_completed("HowToPlay", 0, _path())
	assert_eq(CampaignProgress.completed("HowToPlay", _path()), 3,
			"progress is a maximum and is never decremented")


func test_a_win_out_of_order_jumps_the_count_and_keeps_it() -> void:
	# Not reachable through the screen, which locks ahead of the count -- but it is the
	# other half of "one-way", and the safe direction: a skipped scenario is not un-skipped.
	CampaignProgress.record_completed("HowToPlay", 0, _path())
	CampaignProgress.record_completed("HowToPlay", 2, _path())
	assert_eq(CampaignProgress.completed("HowToPlay", _path()), 3)


func test_recording_one_campaign_leaves_the_others_alone() -> void:
	# The file is one object for every campaign installed, so a write that rebuilt it from
	# scratch would forget every campaign but the one just played.
	_write_raw('{"Other": 4, "Third": 1}')
	assert_true(CampaignProgress.record_completed("HowToPlay", 0, _path()))
	assert_eq(CampaignProgress.completed("HowToPlay", _path()), 1)
	assert_eq(CampaignProgress.completed("Other", _path()), 4)
	assert_eq(CampaignProgress.completed("Third", _path()), 1)


func test_a_row_this_class_cannot_read_is_written_back_untouched() -> void:
	# Preserving something unreadable is kinder than deleting it -- the player may have been
	# mid-edit, and `completed()` already clamps it to 0 on the way out. Asserted on the
	# FILE rather than through `completed()`, which would report 0 either way and so could
	# not tell "kept" from "deleted".
	_write_raw('{"Other": "hand edited", "HowToPlay": 0}')
	assert_true(CampaignProgress.record_completed("HowToPlay", 0, _path()))
	var back := CampaignProgress.all(_path())
	assert_true(back.has("Other"), "the unreadable row survived the write")
	assert_eq(str(back["Other"]), "hand edited")
	assert_eq(int(back["HowToPlay"]), 1)


func test_a_corrupt_file_is_replaced_rather_than_leaving_a_campaign_unrecordable() -> void:
	# ⚠️ **A DELIBERATE LOSS, and the lesser of the two.** `all()` already treats an
	# unparseable file as "every campaign unstarted", so from the player's chair that
	# progress is gone before this is called; refusing to write would mean a campaign that
	# can never record anything again. `all()` has pushed a warning naming the line.
	_write_raw('{"Other": 9, "HowToPlay": tru')
	assert_true(CampaignProgress.record_completed("HowToPlay", 1, _path()))
	assert_eq(CampaignProgress.completed("HowToPlay", _path()), 2,
			"the win is recorded")
	assert_eq(CampaignProgress.completed("Other", _path()), 0,
			"and the row that could not be parsed is gone with the file that held it")


func test_a_write_with_no_campaign_or_no_scenario_is_refused() -> void:
	# Every skirmish carries an empty folder -- `GameScene` checks before calling, and this
	# is the belt to that braces. -1 is what `MatchConfig.scenario_index` defaults to.
	assert_false(CampaignProgress.record_completed("", 0, _path()))
	assert_false(CampaignProgress.record_completed("HowToPlay", -1, _path()))
	assert_eq(CampaignProgress.all(_path()), {}, "and nothing was written")


func test_the_file_it_writes_is_the_file_it_reads() -> void:
	# The round trip, asserted through the FILE rather than through the API, because the
	# owner edits this by hand: it has to be an object of plain numbers that a person can
	# read and correct.
	CampaignProgress.record_completed("HowToPlay", 1, _path())
	var text := FileAccess.get_file_as_string(_path())
	var json := JSON.new()
	assert_eq(json.parse(text), OK, "what was written parses: %s" % text)
	assert_true(json.data is Dictionary)
	assert_eq(int((json.data as Dictionary)["HowToPlay"]), 2)
	assert_true(text.begins_with("{"), "no BOM in front of it: PowerShell's Set-Content adds one and it corrupted project.godot here once")


# ── the shape of the whole loop, which is what the owner reported broken ──────

func test_the_unlock_arithmetic_matches_what_the_screen_will_ask() -> void:
	# ⚠️ **THE BUG THE OWNER FOUND, AS A TEST.** They reset the file to 0, won scenario 1,
	# and scenario 2 stayed locked -- because nothing wrote the file. This drives the same
	# sequence through the two classes that actually decide it: record a win, then ask
	# `CampaignDef` what is unlocked, exactly as `ScenarioScreen.open()` does.
	var campaign: CampaignDef = null
	for c in Campaigns.new().discover():
		if c.folder == "HowToPlay":
			campaign = c
	assert_not_null(campaign, "scenarios/HowToPlay is on disk")
	if campaign == null:
		return

	assert_eq(campaign.unlocked_count(CampaignProgress.completed("HowToPlay", _path())), 1,
			"a fresh player has scenario 1 and nothing else")
	assert_false(campaign.is_unlocked(1, CampaignProgress.completed("HowToPlay", _path())))

	CampaignProgress.record_completed("HowToPlay", 0, _path())
	var after := CampaignProgress.completed("HowToPlay", _path())
	assert_eq(after, 1)
	assert_true(campaign.is_unlocked(1, after), "winning scenario 1 unlocks scenario 2")
	assert_false(campaign.is_unlocked(2, after), "and no further")

	CampaignProgress.record_completed("HowToPlay", 1, _path())
	var after_two := CampaignProgress.completed("HowToPlay", _path())
	assert_true(campaign.is_unlocked(2, after_two), "and then scenario 3")
	assert_eq(campaign.unlocked_count(after_two), 3)
