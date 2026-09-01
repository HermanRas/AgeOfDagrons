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

var screen: CampaignScreen


func before_each() -> void:
	screen = CampaignScreen.new()


func after_each() -> void:
	screen.free()


## The repo's own `scenarios/` folder, which the editor and the headless suite both read
## through `Campaigns`' dev override. One campaign, "How To Play", three scenarios.
func test_the_shipped_campaign_is_found_and_listed() -> void:
	assert_eq(screen.campaign_count(), 1, "scenarios/ holds exactly HowToPlay")
	assert_false(screen.showing_empty_notice(), "something was found, so no empty notice")
	var c: CampaignDef = screen.campaigns()[0]
	assert_eq(c.folder, "HowToPlay")
	assert_eq(c.scenarios.size(), 3)


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
