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


# ── the paragraph mode, 2026-08-30 ──────────────────────────────────────────
#
# The owner's ask: "the current alert box can be reused in single player
# campaigns for long text". IT HAS A CALLER AS OF 15.6 -- a scenario's `alert`
# objective, through `GameScene._announce_objective_alerts` -- and that first
# caller immediately found the defect the centring test below pins. This block
# used to say nothing called it, which is why it is worth noting what changed:
# a mode with no caller had never been positioned by anybody.


func test_a_long_message_grows_the_banner_and_a_short_one_shrinks_it_back() -> void:
	var t := NoticeToast.new()
	assert_false(t.is_long(), "a fresh toast is a notice, not a briefing")
	t.show_long_message("The dragon stirs beneath the mountain, and the old roads are closed.")
	assert_true(t.is_long())
	assert_eq(t.custom_minimum_size, NoticeToast.LONG_SIZE)
	t.show_message("Not enough resources")
	assert_false(t.is_long(), "and it must go back, or every later notice is huge")
	assert_eq(t.custom_minimum_size, NoticeToast.SIZE)
	t.free()


func test_growing_to_the_paragraph_size_keeps_the_banner_on_the_screen_s_axis() -> void:
	# ⚠️ **THE CALLER CANNOT DO THIS AND THAT IS WHY THE WIDGET DOES.** `GameScene` anchors
	# this at CENTER_TOP and writes `position.x = -SIZE.x / 2` ONCE; `show_long_message`
	# then changes the width underneath that offset. Left alone the 720 px banner keeps the
	# 320 px banner's left edge and hangs 200 px right of centre -- an alert visibly
	# off-axis, with nothing in `GameScene` to blame.
	#
	# Found by 15.6's alerts, which are `show_long_message`'s first caller of any kind.
	var t := NoticeToast.new()
	t.set_anchors_preset(Control.PRESET_CENTER_TOP)
	t.position = Vector2(-NoticeToast.SIZE.x * 0.5, 409.0)
	t.show_long_message("The enemy has crossed the river in force.")
	assert_almost_eq(t.position.x, -NoticeToast.LONG_SIZE.x * 0.5, 0.5)
	assert_almost_eq(t.position.x + t.custom_minimum_size.x * 0.5, 0.0, 0.5,
			"the banner's own centre is still the anchor")
	t.show_message("Not enough resources")
	assert_almost_eq(t.position.x, -NoticeToast.SIZE.x * 0.5, 0.5, "and back again")
	assert_almost_eq(t.position.y, 409.0, 0.5, "the vertical placement is the caller's")
	t.free()


func test_a_stretched_toast_is_left_where_its_layout_put_it() -> void:
	# The other half of the rule: "centred" is only a question this can answer when the two
	# horizontal anchors agree. Anchored between two edges, the offsets belong to whatever
	# laid it out and re-centring would fight it.
	#
	# ⚠️ THIS CASE PRINTS *"Nodes with non-equal opposite anchors will have their size
	# overridden"* INTO THE RUN, and the warning is the engine agreeing with the test:
	# `_resize`'s `size = to` cannot mean anything on a stretched Control. Left in rather
	# than worked around, so the next reader knows where that line comes from -- it is this
	# assertion, not a defect in the widget.
	var t := NoticeToast.new()
	t.set_anchors_preset(Control.PRESET_TOP_WIDE)
	t.position = Vector2(40.0, 10.0)
	t.show_long_message("Something long enough to change the width.")
	assert_almost_eq(t.position.x, 40.0, 0.5)
	t.free()


func test_both_sizes_are_the_banner_arts_own_aspect() -> void:
	# The banner is a fixed composition -- a dragon's head at each end -- so the two
	# sizes have to be the same shape or the big one stretches a face. This is the
	# assertion that stops someone making it taller for more lines.
	var short_aspect := NoticeToast.SIZE.x / NoticeToast.SIZE.y
	var long_aspect := NoticeToast.LONG_SIZE.x / NoticeToast.LONG_SIZE.y
	assert_almost_eq(short_aspect, long_aspect, 0.02)


func test_a_long_message_holds_for_longer_than_a_short_one() -> void:
	# Not a timing test -- it asserts the arithmetic, which is what decides whether a
	# briefing is readable. 2.5 s is right for three words and absurd for sixty.
	var brief := "x".repeat(300)
	var hold := maxf(NoticeToast.LONG_MIN_SECONDS,
			brief.length() * NoticeToast.LONG_SECONDS_PER_CHAR)
	assert_true(hold > NoticeToast.DISPLAY_SECONDS * 4.0,
			"300 characters at 15 a second is 20 s, not 2.5")
	assert_true(NoticeToast.LONG_MIN_SECONDS > NoticeToast.DISPLAY_SECONDS,
			"even a short briefing outstays a notice")


func test_the_text_stays_inside_the_dark_field_at_both_sizes() -> void:
	# The insets are fractions precisely so this holds without a second set of
	# numbers. A label at the banner's full width prints over two dragons.
	var t := NoticeToast.new()
	for call in [func() -> void: t.show_message("hi"),
			func() -> void: t.show_long_message("hello there")]:
		call.call()
		var label: Label = null
		for child in t.get_children():
			if child is Label:
				label = child
		assert_not_null(label)
		assert_true(label.offset_left > 0.0 and label.offset_right < 0.0,
				"inset on both sides at %s" % t.custom_minimum_size)
		assert_true(label.offset_left > t.custom_minimum_size.x * 0.15,
				"and by enough to clear a dragon")
	t.free()