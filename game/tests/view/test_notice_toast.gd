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


## Every Control at or under `root`, so a widget's whole subtree can be checked
## rather than just the node someone remembered to set a filter on.
func _controls_under(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	if root is Control:
		out.append(root)
	for child in root.get_children():
		out.append_array(_controls_under(child))
	return out


func test_nothing_in_a_toast_takes_mouse_input() -> void:
	# The regression this file exists to prevent from recurring. `mouse_filter`
	# is PER NODE and does not inherit: the root was IGNORE and the banner
	# TextureRect underneath it kept Control's STOP default, so the toast was an
	# invisible 320x56 hole punched through the HUD -- it lives at modulate.a = 0
	# between messages rather than hidden, so it was eating presses while showing
	# nothing. It sat over the middle of the build grid, and the project owner
	# reported three of five build buttons doing nothing but walk the villager to
	# the ground under the icon (2026-08-16).
	#
	# Asserted over the whole subtree, because the next thing added here will
	# default to STOP too.
	# STOP is the thing being forbidden, not "anything but IGNORE". PASS -- the
	# default for every Container -- lets a press it does not handle carry on to
	# whatever is behind, so it blocks nothing; STOP swallows it whole.
	var found := _controls_under(toast)
	assert_true(found.size() >= 2, "the toast has children to check")
	for c in found:
		assert_ne(c.mouse_filter, Control.MOUSE_FILTER_STOP,
				"%s swallows presses in a widget that is pure notification" % c.get_class())


func test_the_health_bar_does_not_swallow_presses_either() -> void:
	# Same defect class, caught in the same sweep: a display TextureRect left on
	# Control's STOP default. It sits inside SelectionPanel, over nothing that
	# needs clicking today, so it cost nothing -- but the toast cost real play
	# time and this is the same mistake one panel over.
	var bar := HealthBarView.new()
	for c in _controls_under(bar):
		assert_ne(c.mouse_filter, Control.MOUSE_FILTER_STOP,
				"%s in a health bar swallows presses" % c.get_class())
	bar.free()


func test_an_opaque_hud_panel_deliberately_does_swallow_them() -> void:
	# The other half of the rule, so the sweep above is not read as "nothing in
	# the HUD may take input". A panel that occupies real estate SHOULD stop a
	# press: `InputRouter` turns anything no Control consumed into a world tap,
	# so a resource counter that passed presses through would order the selection
	# to walk to whatever ground is behind the counter. Transient overlays like
	# the toast are the exception, and only because they are invisible most of
	# the time and float over other controls.
	var hud := ResourceHUD.new()
	assert_eq(hud.mouse_filter, Control.MOUSE_FILTER_STOP,
			"a solid HUD panel absorbs the tap rather than passing it to the map")
	hud.free()


func test_not_in_a_tree_still_shows_the_message_without_crashing() -> void:
	# No fade can be scheduled without a tree (same reasoning as
	# ControlGroupsHud's timer guard) -- the message must still display.
	assert_false(toast.is_inside_tree())
	toast.show_message("Villager trained")
	assert_eq(toast.current_text(), "Villager trained")
	assert_almost_eq(toast.modulate.a, 1.0, 0.001)
