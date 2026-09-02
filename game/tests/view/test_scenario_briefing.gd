## Phase 15.6 (first half): the scenario briefing modal.
##
## The owner's spec, 2026-09-02: *"when a scenario is played a scenario message is
## required and the user needs to tap the X to close it, interactive consent of the
## goal"*. So the tests here are mostly about the CONSENT -- that it appears, that only
## the button dismisses it, and that it cannot come back afterwards.
##
## It was found by PLAY-TESTING and not by a test, which is worth recording: the
## message field has existed in `scenario.json` and `ScenarioDef` since 15.1 and nothing
## ever drew it, so all three shipped scenarios launched with their goal invisible. That
## is the same hole `pop_used` and `garrison_cap` were both in -- a field a screen reads
## and nothing fills, or here, a field a file fills and nothing reads.
extends TestCase

var briefing: ScenarioBriefing


func before_each() -> void:
	briefing = ScenarioBriefing.new()


func after_each() -> void:
	briefing.free()


func test_a_message_raises_the_modal() -> void:
	assert_false(briefing.visible, "nothing is shown before there is anything to say")
	assert_true(briefing.show_message("Objective: build a house."))
	assert_true(briefing.visible)
	assert_true(briefing.is_shown())
	assert_true(briefing.is_open())
	assert_eq(briefing.message_text(), "Objective: build a house.")


func test_an_empty_message_opens_nothing() -> void:
	# Every skirmish and every debug factory carries an empty message. An empty modal with
	# an X in it is worse than no modal at all, because the player has to dismiss it to
	# find out it said nothing.
	assert_false(briefing.show_message(""))
	assert_false(briefing.visible)
	assert_false(briefing.is_shown())
	assert_false(briefing.show_message("   \n  "), "and whitespace is not a message")
	assert_false(briefing.visible)


func test_the_x_is_the_way_out_and_it_is_a_real_button() -> void:
	# Pressed through the CONTROL rather than by calling the handler: on this project a
	# button wired to nothing has twice looked exactly like a working one.
	briefing.show_message("Objective: reach 15 villagers.")
	assert_true(briefing.is_open())
	briefing.close_button().pressed.emit()
	assert_false(briefing.visible)
	assert_false(briefing.is_open())


func test_it_cannot_be_raised_a_second_time_after_being_dismissed() -> void:
	# ⚠️ `GameScene._start_match()` RUNS TWICE ON A CLIENT -- once from `_ready()` and again
	# when the host's config lands (`match_configured`). Without the latch a client would
	# have the briefing thrown back up after dismissing it, which is the same trap
	# `ResultScreen._shown` exists for.
	briefing.show_message("Objective: gather 500 food.")
	briefing.close()
	assert_false(briefing.show_message("Objective: gather 500 food."))
	assert_false(briefing.visible)
	assert_true(briefing.is_shown(), "it HAS been shown, which is the fact that latched")
	assert_false(briefing.is_open(), "but it is not on screen")


func test_a_second_different_message_cannot_replace_the_first() -> void:
	briefing.show_message("The real objective")
	assert_false(briefing.show_message("Something else entirely"))
	assert_eq(briefing.message_text(), "The real objective")


func test_it_swallows_presses_while_it_is_up() -> void:
	# `MOUSE_FILTER_STOP`, like `ResultScreen` and unlike a toast: everything under it --
	# the build grid, the selection panel, the minimap -- must be unreachable, or a tap
	# "on the X" also orders a villager somewhere behind it.
	assert_eq(briefing.mouse_filter, Control.MOUSE_FILTER_STOP)


func test_the_panel_is_the_size_it_declares_rather_than_the_size_of_its_longest_line() -> void:
	# The trap `ResultScreen` records: a Label left to itself reports its whole unwrapped
	# line as its minimum width and a PanelContainer grows to fit it, so one long briefing
	# would stretch the frame instead of wrapping -- and the frame art is portrait, so a
	# stretched box visibly thins the border.
	#
	# Asserted on `custom_minimum_size` rather than on the laid-out rect, because nothing
	# here is inside a tree and a size flow has therefore never run.
	briefing.show_message("Objective: ".repeat(80))
	assert_eq(briefing.get_child(1).custom_minimum_size, ScenarioBriefing.PANEL_SIZE)


func test_the_owners_real_briefings_all_fit_the_shape_the_modal_expects() -> void:
	# THE CONTENT CHECK. These are prose the owner writes by hand, and the modal is a fixed
	# 420x520 with a scroller in it -- so what actually matters is that every shipped
	# scenario HAS one and that it is not so short as to be useless.
	var found := 0
	var declared := 0
	for c in Campaigns.new().discover():
		declared += c.scenarios.size()
		for s in c.scenarios:
			found += 1
			assert_false(s.message.strip_edges().is_empty(),
					"%s/%s has no briefing" % [c.folder, s.folder])
			# Every one of the three names its goal in the first line, which is the owner's
			# own shape ("Objective: ... Overview: ..."). Asserted because the modal's title
			# says OBJECTIVE and a briefing that opened with setup prose would read oddly
			# under it.
			assert_true(s.message.begins_with("Objective:"),
					"%s/%s should lead with its objective: %s"
					% [c.folder, s.folder, s.message.substr(0, 40)])
			var fresh := ScenarioBriefing.new()
			assert_true(fresh.show_message(s.message),
					"%s/%s must actually raise the modal" % [c.folder, s.folder])
			fresh.free()
	# Derived, not hardcoded: HowToPlay grew from three to five on 2026-09-02 and a count
	# here would only have been asserting how much content exists.
	assert_eq(found, declared, "every scenario the campaign declares has a briefing")
	assert_true(found >= 3, "and there are at least the original three")
