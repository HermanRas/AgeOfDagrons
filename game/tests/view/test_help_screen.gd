## PLAN.md 1.8, the HOW TO PLAY pager.
##
## BACK is not exercised here, for the reason `test_pause_menu.gd` gives about
## Resign/Quit: `_on_back_pressed` calls `get_tree()` unconditionally, because it is
## only ever pressed by a screen that is on screen. What IS asserted headlessly is
## everything a wrong page index would break -- and the one thing a screenshot could
## never catch, which is a page whose image was never staged into `game/assets/`.
extends TestCase

var screen: HelpScreen


func before_each() -> void:
	screen = HelpScreen.new()


func after_each() -> void:
	screen.free()


func test_opens_on_the_first_page() -> void:
	assert_eq(screen.current_page(), 0)
	assert_eq(screen._caption.text, "MOVING THE CAMERA")
	assert_eq(screen._counter.text, "1 / 6")


## THE FILES, NOT THE LIST. `PAGES` is a table of strings and stays true if every
## image is deleted; what makes it a guide is that `res://assets/ui/help/` holds the
## six files it names. A staged asset that never made it into the repository is
## invisible on the developer's own machine and blank on everybody else's.
func test_every_page_names_an_image_that_exists() -> void:
	for entry in HelpScreen.PAGES:
		var path: String = HelpScreen._HELP_DIR + String(entry["file"])
		assert_true(ResourceLoader.exists(path), "missing help image: " + path)


func test_every_page_has_a_title() -> void:
	for entry in HelpScreen.PAGES:
		assert_false(String(entry["title"]).is_empty())


func test_paging_forward_walks_the_whole_guide() -> void:
	for i in range(1, screen.page_count()):
		screen.next_page()
		assert_eq(screen.current_page(), i)
		assert_eq(screen._counter.text, "%d / %d" % [i + 1, screen.page_count()])
		assert_eq(screen._caption.text, String(HelpScreen.PAGES[i]["title"]))


func test_paging_stops_at_both_ends_rather_than_wrapping() -> void:
	screen.previous_page()
	assert_eq(screen.current_page(), 0)
	screen.show_page(screen.page_count() - 1)
	screen.next_page()
	assert_eq(screen.current_page(), screen.page_count() - 1)


## The disabled states are the only thing telling a player they have reached an end,
## since the pager does not wrap.
func test_the_end_buttons_are_disabled_at_the_ends() -> void:
	assert_true(screen._prev_button.disabled)
	assert_false(screen._next_button.disabled)
	screen.show_page(screen.page_count() - 1)
	assert_false(screen._prev_button.disabled)
	assert_true(screen._next_button.disabled)


func test_an_index_off_the_end_clamps_instead_of_crashing() -> void:
	screen.show_page(99)
	assert_eq(screen.current_page(), screen.page_count() - 1)
	screen.show_page(-99)
	assert_eq(screen.current_page(), 0)


## The picture is the page. A `TextureRect` left with no texture would draw an empty
## rectangle and look exactly like a screen that had not finished loading.
func test_each_page_actually_loads_its_picture() -> void:
	for i in range(screen.page_count()):
		screen.show_page(i)
		assert_true(screen._art.visible)
		assert_false(screen._missing.visible)
		assert_true(screen._art.texture != null)


## EXPAND_IGNORE_SIZE, asserted because the default is not it. `EXPAND_KEEP_SIZE`
## gives the rect a minimum size of the texture's own -- 1476 px here, wider than the
## viewport -- and the page would be laid out around a picture that cannot shrink.
func test_the_picture_is_allowed_to_shrink() -> void:
	assert_eq(screen._art.expand_mode, TextureRect.EXPAND_IGNORE_SIZE)
	assert_true(screen._art.get_combined_minimum_size().x < 1000.0)
