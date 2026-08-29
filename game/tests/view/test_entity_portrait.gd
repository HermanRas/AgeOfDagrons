## PLAN.md 8.1a/8.1c/10.4: the shared "crop a battle sprite as a portrait"
## helper. Must never depend on real baked art being staged --
## game/assets/atlases/ is gitignored, so a fresh clone resolves every
## visual_id to a placeholder.
extends TestCase


func test_an_undeclared_def_id_yields_no_frame() -> void:
	assert_eq(EntityPortrait.frame_for(&"unit.nonexistent"), {})


func test_empty_def_id_yields_no_frame() -> void:
	assert_eq(EntityPortrait.frame_for(&""), {})


# -- the portrait carries the owner's skin -----------------------------------

func test_the_skin_arguments_default_to_what_the_old_one_argument_call_drew() -> void:
	# frame_for() gained (age, colour) in the same order and with the same
	# defaults as GameDataRegistry.atlas_for(), so one convention covers both and
	# no caller has to check which way round this one goes.
	assert_eq(EntityPortrait.frame_for(&"unit.villager"),
			EntityPortrait.frame_for(&"unit.villager", 0, -1))


func test_two_players_get_different_portraits_when_their_colours_are_staged() -> void:
	# The point: a portrait is how the player identifies something they are NOT
	# looking at on the map, and colour is the only thing saying whose it is.
	# Guarded on the art, like every other staged-only assertion here --
	# game/assets/atlases/ is gitignored and a fresh clone has none of it.
	var untinted := EntityPortrait.frame_for(&"unit.villager")
	if untinted.is_empty():
		assert_true(true, "no villager bake staged -- nothing to crop, let alone compare")
		return

	var p1 := EntityPortrait.frame_for(&"unit.villager", 0, 0)
	var p2 := EntityPortrait.frame_for(&"unit.villager", 0, 1)
	assert_false(p1.is_empty())
	assert_false(p2.is_empty())
	assert_ne(p1["texture"], p2["texture"],
			"player 1 and player 2 crop from different atlases, or they look identical")


func test_a_colour_with_no_bake_still_yields_a_portrait() -> void:
	# Falling back to the untinted crop is the right answer for a missing tint:
	# a portrait in nobody's colour beats an empty circle, and
	# GameDataRegistry.missing_colour_atlases() is what makes the gap findable.
	var untinted := EntityPortrait.frame_for(&"unit.villager")
	if untinted.is_empty():
		assert_true(true, "no villager bake staged")
		return
	assert_false(EntityPortrait.frame_for(&"unit.villager", 0, 99).is_empty(),
			"an absurd colour index still draws something")


func test_a_building_portrait_takes_the_age_skin() -> void:
	# Cheap consistency rather than a requirement: the portrait shows the same
	# building the player can see on the map after they advance an age.
	var age1 := EntityPortrait.frame_for(&"building.town_center", 1, -1)
	if age1.is_empty():
		assert_true(true, "no town centre bake staged")
		return
	var age4 := EntityPortrait.frame_for(&"building.town_center", 4, -1)
	assert_false(age4.is_empty())
	assert_ne(age1["rect"], age4["rect"],
			"the Briton and Roman civic centres are not the same crop")

# ── EntityPortrait.fit, 2026-08-30 ──────────────────────────────────────────
#
# Reported by the project owner off a screenshot: "villager select icon is
# stretched". A baked idle frame is taller than it is wide and both hand-drawn
# slots painted it into a square.


func test_a_tall_crop_keeps_its_proportions_and_centres_horizontally() -> void:
	var crop := {"rect": Rect2(0, 0, 40, 70)}
	var fitted := EntityPortrait.fit(crop, Rect2(0, 0, 58, 58))
	assert_almost_eq(fitted.size.y, 58.0, 0.01, "the long axis fills the box")
	assert_almost_eq(fitted.size.x, 58.0 * 40.0 / 70.0, 0.01, "and the short one follows")
	assert_almost_eq(fitted.position.x, (58.0 - fitted.size.x) * 0.5, 0.01)
	assert_almost_eq(fitted.position.y, 0.0, 0.01)


func test_a_wide_crop_fills_the_width_instead() -> void:
	var fitted := EntityPortrait.fit({"rect": Rect2(0, 0, 120, 40)}, Rect2(0, 0, 58, 58))
	assert_almost_eq(fitted.size.x, 58.0, 0.01)
	assert_almost_eq(fitted.size.y, 58.0 / 3.0, 0.01)
	assert_almost_eq(fitted.position.y, (58.0 - fitted.size.y) * 0.5, 0.01)


func test_the_fit_is_offset_by_the_boxs_own_position() -> void:
	# Both callers pass an INSET rect, not one at the origin, so a fit that ignored
	# `box.position` would draw every portrait in the widget's top-left corner.
	var fitted := EntityPortrait.fit({"rect": Rect2(0, 0, 50, 50)}, Rect2(7, 11, 58, 58))
	assert_almost_eq(fitted.position.x, 7.0, 0.01)
	assert_almost_eq(fitted.position.y, 11.0, 0.01)


func test_a_square_crop_is_left_exactly_where_it_was() -> void:
	var box := Rect2(7, 7, 58, 58)
	assert_true(EntityPortrait.fit({"rect": Rect2(0, 0, 64, 64)}, box).is_equal_approx(box))


func test_an_empty_crop_returns_the_box_rather_than_dividing_by_zero() -> void:
	var box := Rect2(0, 0, 58, 58)
	assert_true(EntityPortrait.fit({}, box).is_equal_approx(box))
	assert_true(EntityPortrait.fit({"rect": Rect2(0, 0, 0, 40)}, box).is_equal_approx(box))