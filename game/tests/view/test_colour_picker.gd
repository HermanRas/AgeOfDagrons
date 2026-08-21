## The player-colour palette grid (PLAN.md 1.6/12.1c), which replaced the cycle.
##
## `test_skirmish_screen` covers how the screen USES it -- who may open it, what the
## host does with the answer. What is asserted here is the one property the control
## itself owns: that a colour somebody else holds is not on the grid at all. That is
## the no-duplicates rule (§1) expressed as an offer rather than as a refusal, and it
## is the whole reason this control exists instead of a plain palette.
extends TestCase

var picker: ColourPickerPopup


func before_each() -> void:
	picker = ColourPickerPopup.new()


func after_each() -> void:
	picker.free()


func test_it_starts_closed() -> void:
	assert_false(picker.is_open())


func test_it_offers_the_whole_palette_when_nothing_is_taken() -> void:
	picker.open_for("Player 1", 0, [] as Array[int])
	assert_true(picker.is_open())
	assert_eq(picker.offered().size(), GameDataRegistry.colour_count())


func test_a_taken_colour_is_not_on_the_grid() -> void:
	picker.open_for("Player 1", 0, [3, 5] as Array[int])
	assert_false(picker.offered().has(3))
	assert_false(picker.offered().has(5))
	assert_eq(picker.offered().size(), GameDataRegistry.colour_count() - 2)


func test_your_own_colour_is_always_on_the_grid() -> void:
	# The one exception to "free colours only". A grid that omitted it would have no
	# answer to "which one am I", and pressing it -- a no-op -- is a reasonable way to
	# close a picker you opened by accident.
	picker.open_for("Player 2", 4, [4, 1] as Array[int])
	assert_true(picker.offered().has(4), "yours, even though it reads as taken")
	assert_false(picker.offered().has(1), "somebody else's, still not")


func test_pressing_a_swatch_names_that_colour_and_closes() -> void:
	picker.open_for("Player 1", 0, [] as Array[int])
	var chosen: Array[int] = []
	picker.colour_chosen.connect(func(index: int) -> void: chosen.append(index))

	picker.swatch_for(6).pressed.emit()
	assert_eq(chosen, [6] as Array[int])
	assert_false(picker.is_open(), "and gets out of the way")


func test_cancel_closes_without_choosing() -> void:
	picker.open_for("Player 1", 0, [] as Array[int])
	var chosen: Array[int] = []
	picker.colour_chosen.connect(func(index: int) -> void: chosen.append(index))
	picker._on_cancel()
	assert_true(chosen.is_empty())
	assert_false(picker.is_open())


func test_reopening_re_reads_what_is_taken() -> void:
	# One picker serves every slot on the screen (`SkirmishScreen._colour_picker`), so
	# a grid that remembered the previous slot's free list would offer a colour the
	# player it is now open for cannot have.
	picker.open_for("Player 1", 0, [] as Array[int])
	assert_true(picker.offered().has(2))
	picker.open_for("Player 2", 0, [2] as Array[int])
	assert_false(picker.offered().has(2))


func test_a_swatch_is_drawn_in_its_own_colour() -> void:
	# The mockup is flat blocks of colour, and the name written across a swatch is
	# what keeps the grid usable for somebody who cannot separate two of the hues --
	# which is the whole reason colours.json chose these eight on a lightness ladder.
	picker.open_for("Player 1", 0, [] as Array[int])
	for index in picker.offered():
		var button := picker.swatch_for(index)
		var style := button.get_theme_stylebox("normal") as StyleBoxFlat
		assert_not_null(style, "colour %d has a flat fill" % index)
		if style != null:
			assert_eq(style.bg_color, GameDataRegistry.colour(index))
		assert_false(button.text.is_empty(), "and is named")


func test_the_current_colour_is_the_one_marked() -> void:
	picker.open_for("Player 1", 3, [] as Array[int])
	var current := picker.swatch_for(3).get_theme_stylebox("normal") as StyleBoxFlat
	var other := picker.swatch_for(4).get_theme_stylebox("normal") as StyleBoxFlat
	assert_true(current.border_width_top > other.border_width_top,
			"the gold border says which one you have")
	assert_eq(current.border_color, HudStyle.GOLD)


func test_ink_flips_so_the_name_is_legible_on_every_swatch() -> void:
	# The palette deliberately spans L* 36 to 100, so one fixed font colour is
	# illegible at one end of it whichever end it is picked for.
	picker.open_for("Player 1", 0, [] as Array[int])
	for index in picker.offered():
		var colour := GameDataRegistry.colour(index)
		var ink: Color = picker.swatch_for(index).get_theme_color("font_color")
		var wanted := Color.BLACK if colour.get_luminance() > 0.5 else Color.WHITE
		assert_eq(ink, wanted, "%s on %s" % [ink, colour])
