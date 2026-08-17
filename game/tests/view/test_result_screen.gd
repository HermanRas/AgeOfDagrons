## PLAN.md 11.1's result screen. Like `test_pause_menu.gd`, only the state machine
## is asserted here: Main Menu and Quit both call `get_tree()` unconditionally (they
## are only ever pressed while on screen, i.e. while in a tree), so those two are
## verified live rather than headlessly.
extends TestCase

var screen: ResultScreen


func before_each() -> void:
	screen = ResultScreen.new()


func after_each() -> void:
	screen.free()


func test_starts_hidden_and_unshown() -> void:
	assert_false(screen.visible)
	assert_false(screen.is_shown())


func test_a_win_reads_as_victory() -> void:
	screen.show_result(true, "Every opponent has been eliminated.")
	assert_true(screen.visible)
	assert_true(screen.is_shown())
	assert_eq(screen.title_text(), "VICTORY")
	assert_eq(screen.subtitle_text(), "Every opponent has been eliminated.")


func test_a_loss_reads_as_defeat() -> void:
	screen.show_result(false, "You have been eliminated.")
	assert_eq(screen.title_text(), "DEFEAT")
	assert_eq(screen.subtitle_text(), "You have been eliminated.")


func test_the_first_result_is_the_one_that_sticks() -> void:
	# The outcome arrives in EVERY snapshot from the tick it is decided, ten a
	# second, so a screen that took the latest one would be rebuilt continuously --
	# and any later call is describing the same match anyway.
	screen.show_result(false, "You have been eliminated.")
	screen.show_result(true, "Every opponent has been eliminated.")
	assert_eq(screen.title_text(), "DEFEAT", "the first call won")
	assert_eq(screen.subtitle_text(), "You have been eliminated.")


func test_it_stops_the_clock() -> void:
	# Without this the world keeps ticking behind a screen that says it is over,
	# and every snapshot after it is spent on a match nobody is playing.
	# Reads SimClock's own `_running`, the way `test_selection_panel` reads the
	# panel's slots: the autoload exposes start/stop and no getter, and adding one
	# for a test to look at would be API nothing in the game asks for.
	SimClock.start()
	assert_true(SimClock._running, "running before the match ends")
	screen.show_result(true)
	assert_false(SimClock._running)
