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