## PLAN.md 15.4, the campaign selection screen.
##
## BACK is not exercised, for the reason `test_help_screen` and `test_pause_menu` both
## give: `_on_back_pressed` calls `get_tree()` unconditionally because it is only ever
## pressed by a screen that is on screen.
##
## THE SCREEN IS BUILT WITH `.new()` AND NEVER PARENTED, which is `HelpScreen`'s pattern and
## is the whole reason the layout is built in `_init()`. It also means the toast cannot fade
## (a tween needs a `SceneTree`), which is why `open_campaign` guards on `is_inside_tree()`
## and why these tests read `last_opened()` rather than a message.
##
## WHAT THESE TESTS DO **NOT** COVER, said out loud because it is the failure this screen
## was written against: **a `VBoxContainer` overflows rather than scrolling, and asking a
## node for its rect returns the rect whether or not the window contains it.** The lobby
## shipped with its nav strip off the bottom of the screen with every structural test
## passing. The guard here is that the list is inside a `ScrollContainer` at all — asserted
## below — not that any measurement came out right.
extends TestCase

## ## ⚠️ NOTHING HERE MAY TOUCH THE REAL PROGRESS FILE
##
## RESET PROGRESS (2026-09-06) put a button on this screen that **deletes**
## `user://campaign_progress.json`, so
## `before_each` repoints the screen at a path under this directory before any test can
## press it. Left on its default, one run of the suite would silently wipe the campaign
## progress of whoever ran it. `CampaignProgress`' own header records the milder version of
## this biting once already — a test that merely READ the real file passed on a fresh
## checkout and failed on a machine that had played the game.
const DIR := "user://test_campaign_screen"
const PROGRESS := "user://test_campaign_screen/progress.json"

var screen: CampaignScreen


func before_each() -> void:
	screen = CampaignScreen.new()
	screen.progress_path = PROGRESS
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)
	if FileAccess.file_exists(PROGRESS):
		DirAccess.remove_absolute(PROGRESS)


func after_each() -> void:
	screen.free()
	# `open_campaign` parks the campaign on a STATIC for the next scene to consume, so a
	# test that presses a row leaves it set. Cleared here rather than in the screen, because
	# consuming it is `ScenarioScreen._init()`'s job and a test is not that.
	ScenarioScreen.pending = null


## The repo's own `scenarios/` folder, which the editor and the headless suite both read
## through `Campaigns`' dev override. One campaign, "How To Play".
##
## HOW MANY SCENARIOS IT HOLDS IS NOT ASSERTED, deliberately: this screen lists CAMPAIGNS,
## and the count inside one is content the owner adds to (three on 2026-09-01, five the day
## after). A floor is kept so an empty campaign cannot pass by listing nothing.
func test_the_shipped_campaign_is_found_and_listed() -> void:
	assert_eq(screen.campaign_count(), 1, "scenarios/ holds exactly HowToPlay")
	assert_false(screen.showing_empty_notice(), "something was found, so no empty notice")
	var c: CampaignDef = screen.campaigns()[0]
	assert_eq(c.folder, "HowToPlay")
	assert_true(c.scenarios.size() >= 3, "and it has missions in it")


func test_every_campaign_gets_a_row() -> void:
	for i in range(screen.campaign_count()):
		assert_not_null(screen.row(i), "row %d exists" % i)
	assert_null(screen.row(screen.campaign_count()), "and no row past the end")
	assert_null(screen.row(-1))


func test_the_shipped_campaign_is_playable_so_its_row_is_pressable() -> void:
	# Scenario 3 is `last_man_standing` and needs nothing 15.2 has not built, so the
	# campaign has at least one playable scenario and the row must not be greyed.
	var c: CampaignDef = screen.campaigns()[0]
	assert_true(c.is_playable(), "HowToPlay is playable: " + "; ".join(c.all_problems()))
	assert_false(screen.row(0).disabled)


func test_a_row_carries_the_campaigns_name_and_description() -> void:
	# THE TEXT, not the layout. What a wrong wiring looks like is a row showing the folder
	# name, or every row showing the first campaign's blurb.
	var c: CampaignDef = screen.campaigns()[0]
	var found := _labels_of(screen.row(0))
	assert_true(found.has(c.name), "the row shows the campaign name, not the folder")
	assert_false(c.description.is_empty(), "campaign.json carries a description")
	assert_true(found.has(c.description))


func test_pressing_a_row_opens_that_campaign() -> void:
	assert_null(screen.last_opened(), "nothing opened before a press")
	screen.row(0).pressed.emit()
	assert_not_null(screen.last_opened())
	assert_eq(screen.last_opened().folder, "HowToPlay")


func test_pressing_a_row_parks_the_campaign_for_the_scenario_screen() -> void:
	# THE HANDOFF, which is `Net.pending_match`'s pattern: a CampaignDef is a live object and
	# cannot travel through `change_scene_to_file`. The scene change itself needs a tree and
	# is not exercised here; parking the campaign is the half that can be.
	assert_null(ScenarioScreen.pending)
	screen.row(0).pressed.emit()
	assert_not_null(ScenarioScreen.pending, "the scenario screen has something to open")
	assert_eq(ScenarioScreen.pending.folder, "HowToPlay")


func test_opening_out_of_range_is_ignored_rather_than_crashing() -> void:
	# `_on_row_pressed` is bound to an index, and a reload between the bind and the press
	# would leave a stale one. Reachable rather than theoretical once 0.3 can install a
	# campaign while this screen is open.
	screen._on_row_pressed(99)
	screen._on_row_pressed(-1)
	assert_null(screen.last_opened())


func test_the_list_lives_inside_a_scroll_container() -> void:
	# THE ONE STRUCTURAL THING WORTH ASSERTING. A VBoxContainer overflows; it does not
	# clip, scroll or compress past its children's minimums, and the lobby shipped with
	# its bottom strip off the screen for exactly that. One campaign fits today, so this
	# is the guard for the ninth.
	assert_true(screen._list.get_parent() is ScrollContainer,
			"the campaign list must be scrollable before it is long")


func test_reloading_does_not_double_the_list() -> void:
	# `reload()` detaches before freeing and frees immediately rather than deferring,
	# because a deferred free needs a tree this screen does not have in the suite. Get that
	# wrong and the list grows by one campaign per reload.
	var before := screen.campaign_count()
	screen.reload()
	screen.reload()
	assert_eq(screen.campaign_count(), before)
	assert_eq(_rows_in_list(), before, "one row per campaign, not three per campaign")


func test_the_shipped_campaign_loads_without_complaint() -> void:
	# The loader's warnings are a developer-facing channel and an empty list is the
	# shipped-content contract: a shadowed or malformed campaign in the repo's own folder is
	# a broken commit, not a runtime state.
	assert_eq(screen.warnings(), [] as Array[String],
			"scenarios/ loads clean: " + "; ".join(screen.warnings()))


# ── RESET PROGRESS (2026-09-06) ───────────────────────────────────────────────

func test_the_reset_button_is_on_the_screen_and_says_what_it_does() -> void:
	# The half that can rot silently, which is `test_the_download_button`'s argument: a
	# button wired to nothing still looks right on the screen.
	assert_not_null(screen.reset_button())
	assert_eq(screen.reset_button().text, "RESET PROGRESS")
	assert_false(screen.reset_button().disabled,
			"never gated on there being progress -- reading the real file to decide would"
			+ " make this screen's construction depend on user:// state")


func test_pressing_reset_only_asks() -> void:
	# ⚠️ THE WHOLE POINT OF THE MODAL. There must be no path from a single tap to a wiped
	# campaign. `record_completed` is written to it first, so the file has something in it
	# to lose.
	CampaignProgress.record_completed("HowToPlay", 2, PROGRESS)
	assert_eq(CampaignProgress.completed("HowToPlay", PROGRESS), 3)

	assert_false(screen.confirm_overlay().is_open(), "no modal before the press")
	screen.reset_button().pressed.emit()
	assert_true(screen.confirm_overlay().is_open(), "the press opens the question")
	assert_eq(CampaignProgress.completed("HowToPlay", PROGRESS), 3,
			"and changes nothing until it is answered")


func test_the_alert_says_what_is_lost_in_the_players_terms() -> void:
	# "Progress" is a number in a JSON file; what the player has is unlocked missions, and
	# what they need told is that those lock again. The word "undone" is the one that stops
	# a reflexive yes.
	screen.reset_button().pressed.emit()
	var body := screen.confirm_overlay().body_text().to_lower()
	assert_true(body.contains("lock"), "it says the scenarios lock again: " + body)
	assert_true(body.contains("undone"), "and that it cannot be undone: " + body)
	assert_true(body.contains("campaign"), "and that it is every campaign, not this one")


func test_cancelling_the_alert_keeps_every_scenario_unlocked() -> void:
	CampaignProgress.record_completed("HowToPlay", 1, PROGRESS)
	screen.reset_button().pressed.emit()
	screen.confirm_overlay().cancel_button().pressed.emit()
	assert_false(screen.confirm_overlay().is_open())
	assert_eq(CampaignProgress.completed("HowToPlay", PROGRESS), 2,
			"CANCEL must leave the file exactly as it was")


func test_confirming_the_alert_sets_progress_back_to_zero() -> void:
	CampaignProgress.record_completed("HowToPlay", 3, PROGRESS)
	assert_eq(CampaignProgress.completed("HowToPlay", PROGRESS), 4)

	screen.reset_button().pressed.emit()
	screen.confirm_overlay().confirm_button().pressed.emit()

	assert_eq(CampaignProgress.completed("HowToPlay", PROGRESS), 0)
	assert_false(screen.confirm_overlay().is_open(), "and the modal is gone")


func test_a_reset_takes_every_campaign_not_just_the_listed_one() -> void:
	# The button is on the screen that lists campaigns rather than inside one, and the modal
	# says so. A future second campaign must not survive a reset the player was told cleared
	# everything.
	CampaignProgress.record_completed("HowToPlay", 0, PROGRESS)
	CampaignProgress.record_completed("SomeOtherCampaign", 4, PROGRESS)
	screen.reset_button().pressed.emit()
	screen.confirm_overlay().confirm_button().pressed.emit()
	assert_eq(CampaignProgress.all(PROGRESS), {}, "nothing is left behind")


func test_resetting_with_nothing_to_reset_is_a_no_op_and_not_an_error() -> void:
	# The button is deliberately never disabled, so this is the ordinary state of a player
	# who has just installed the game and pressed it out of curiosity.
	assert_eq(CampaignProgress.all(PROGRESS), {})
	screen.reset_button().pressed.emit()
	screen.confirm_overlay().confirm_button().pressed.emit()
	assert_eq(CampaignProgress.all(PROGRESS), {})


## Every `Label` text under `node`, recursively — the row's own children are nested in a
## margin and a box, and a test that walked one level would pass on an empty row.
func _labels_of(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child in node.get_children():
		if child is Label:
			out.append((child as Label).text)
		out.append_array(_labels_of(child))
	return out


func _rows_in_list() -> int:
	var n := 0
	for child in screen._list.get_children():
		if child is Button:
			n += 1
	return n
