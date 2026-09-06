## The "are you sure" modal, built for the scenario screen's RESET PROGRESS button (owner
## request, 2026-09-06; no PLAN.md row).
##
## THE POINT OF THIS FILE IS THAT THE MODAL CANNOT BE SKIPPED AND CANNOT FIRE BY ITSELF.
## The widget is twenty lines of layout; what is worth asserting is the guard — that it
## starts closed, that opening it emits nothing, that cancelling emits nothing destructive,
## and that the confirm signal comes from the confirm button and from nowhere else.
##
## Built with `.new()` and never parented, which is `test_campaign_screen`'s pattern and the
## reason this is an in-scene Control rather than a `ConfirmationDialog`: a `Window` needs a
## tree to `popup_centered()` at all, so none of the presses below would be reachable.
extends TestCase

var overlay: ConfirmOverlay
var confirmed_count: int
var cancelled_count: int


func before_each() -> void:
	overlay = ConfirmOverlay.new()
	confirmed_count = 0
	cancelled_count = 0
	overlay.confirmed.connect(func() -> void: confirmed_count += 1)
	overlay.cancelled.connect(func() -> void: cancelled_count += 1)


func after_each() -> void:
	overlay.free()


func test_it_starts_closed_and_silent() -> void:
	# A modal visible at construction would be a modal over whatever screen built it, before
	# anybody asked a question.
	assert_false(overlay.is_open())
	assert_false(overlay.visible)
	assert_eq(confirmed_count, 0)
	assert_eq(cancelled_count, 0)


func test_opening_asks_and_decides_nothing() -> void:
	overlay.open("RESET PROGRESS", "Are you sure?", "RESET")
	assert_true(overlay.is_open())
	assert_eq(overlay.title_text(), "RESET PROGRESS")
	assert_eq(overlay.body_text(), "Are you sure?")
	assert_eq(confirmed_count, 0, "opening the question is not answering it")
	assert_eq(cancelled_count, 0)


func test_the_confirm_button_carries_the_verb_not_yes() -> void:
	# A button that says what it does is still readable by somebody who tapped past the
	# paragraph, which on a destructive action is most people.
	overlay.open("RESET PROGRESS", "body", "RESET")
	assert_eq(overlay.confirm_button().text, "RESET")
	assert_eq(overlay.cancel_button().text, "CANCEL", "the default for the safe half")


func test_confirming_emits_once_and_closes() -> void:
	overlay.open("t", "b", "RESET")
	overlay.confirm_button().pressed.emit()
	assert_eq(confirmed_count, 1)
	assert_eq(cancelled_count, 0)
	assert_false(overlay.is_open(), "closed before the handler runs, so a handler that"
			+ " changes scene is not fighting a modal that is still up")


func test_cancelling_emits_cancelled_and_never_confirmed() -> void:
	# THE ONE THAT MATTERS. A wiring slip that connected both buttons to the same handler
	# would pass every layout assertion above and delete the player's progress when they
	# pressed CANCEL.
	overlay.open("t", "b", "RESET")
	overlay.cancel_button().pressed.emit()
	assert_eq(confirmed_count, 0, "CANCEL must never confirm")
	assert_eq(cancelled_count, 1)
	assert_false(overlay.is_open())


func test_reopening_replaces_the_question_rather_than_stacking_one() -> void:
	overlay.open("FIRST", "one", "A")
	overlay.open("SECOND", "two", "B")
	assert_eq(overlay.title_text(), "SECOND")
	assert_eq(overlay.body_text(), "two")
	assert_eq(overlay.confirm_button().text, "B")


func test_the_backdrop_swallows_presses() -> void:
	# While this is open, a press that misses the frame must not reach the screen
	# underneath -- which on the scenario screen is a column of rows that swap the panel.
	# `mouse_filter` is per-node and does not inherit; `NoticeToast`'s header records a week
	# of an invisible hole in the build grid learned from exactly that.
	assert_eq(overlay.mouse_filter, Control.MOUSE_FILTER_STOP)
	var dim: ColorRect = null
	for child in overlay.get_children():
		if child is ColorRect:
			dim = child
			break
	assert_not_null(dim, "there is a dimming backdrop")
	assert_eq(dim.mouse_filter, Control.MOUSE_FILTER_STOP,
			"and it stops presses rather than letting them through to the list")


func test_it_covers_the_whole_screen() -> void:
	# Full-rect under `canvas_items` stretch is what makes this lay out identically on a
	# phone. A modal anchored to a corner is one that leaves half the screen live.
	assert_eq(overlay.anchor_right, 1.0)
	assert_eq(overlay.anchor_bottom, 1.0)


func test_both_buttons_are_the_same_size() -> void:
	# So neither option is physically easier to hit than the other -- the confirm half is
	# told apart by its colour and its word, not by being bigger or nearer.
	assert_eq(overlay.confirm_button().custom_minimum_size,
			overlay.cancel_button().custom_minimum_size)
	assert_true(overlay.cancel_button().custom_minimum_size.y >= 44.0,
			"and both are a thumb tall")
