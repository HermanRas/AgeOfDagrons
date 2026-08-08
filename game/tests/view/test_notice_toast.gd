## PLAN.md 8.4: a fading text line, generic enough for both the main menu and
## the match HUD to drive directly.
extends TestCase

var toast: NoticeToast


func before_each() -> void:
	toast = NoticeToast.new()


func after_each() -> void:
	toast.free()


func test_show_message_sets_the_text_and_shows_it() -> void:
	toast.show_message("Not enough resources")
	assert_eq(toast.current_text(), "Not enough resources")
	assert_almost_eq(toast.modulate.a, 1.0, 0.001)


func test_a_later_message_replaces_an_earlier_one() -> void:
	toast.show_message("First")
	toast.show_message("Second")
	assert_eq(toast.current_text(), "Second")


func test_not_in_a_tree_still_shows_the_message_without_crashing() -> void:
	# No fade can be scheduled without a tree (same reasoning as
	# ControlGroupsHud's timer guard) -- the message must still display.
	assert_false(toast.is_inside_tree())
	toast.show_message("Villager trained")
	assert_eq(toast.current_text(), "Villager trained")
	assert_almost_eq(toast.modulate.a, 1.0, 0.001)
