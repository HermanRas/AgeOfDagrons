## The full-screen page of action tiles (board `8.x-build-menu-modal`): BUILD, UPGRADES
## and UNITS on one chassis.
##
## Built with `.new()` and never parented, which is every `tests/view/` file's pattern and
## the reason `HudPanel` is an in-scene `Control` rather than a `Window`. An unparented
## page has no size, so `_remeasure` returns early and the fallback grid stands -- which
## makes the slot count deterministic here and is exactly what the tests below want.
extends TestCase

var page: ActionPage
var pressed: Array[StringName]


func before_each() -> void:
	page = ActionPage.new()
	pressed = []
	page.action_pressed.connect(func(a: HudAction) -> void: pressed.append(a.id))


func after_each() -> void:
	page.free()


func _actions(n: int) -> Array[HudAction]:
	var out: Array[HudAction] = []
	for i in range(n):
		out.append(HudAction.new(&"thing:%d" % i, "Thing %d" % i))
	return out


## The CONTENT tiles on the open page. The two arrows are excluded, because they are
## navigation and not items -- counting them made `test_every_action_is_reachable_by_paging`
## report 25 of 23, which is the same mistake as counting the page numbers in a book's
## index.
func _shown_ids() -> Array:
	var out: Array = []
	for slot in page.slots():
		if slot.visible and slot.action != null \
				and slot.action.id != SelectionActions.PAGE_NEXT \
				and slot.action.id != SelectionActions.PAGE_PREV:
			out.append(slot.action.id)
	return out


# ── the chrome ──────────────────────────────────────────────────────────────

func test_it_starts_closed() -> void:
	# A page visible at construction is a page over the match before anybody opened it.
	assert_false(page.is_open())


func test_the_title_says_which_grid_you_got() -> void:
	# `HudPanel.set_title` is not optional in the chrome, and with three pages on one
	# class the title is how a player knows which of them is up.
	page.show_actions("UPGRADES", _actions(3))
	assert_eq(page.title(), "UPGRADES")
	page.show_actions("UNITS", _actions(3))
	assert_eq(page.title(), "UNITS")


func test_the_grid_is_the_strips_shape_one_row_taller() -> void:
	# Owner, 2026-09-21: *"the same layout, 4x4 grid, not the same in size"*. The COUNT is
	# fixed and the TILE is what grows -- the first version had that backwards and shipped
	# five 72 px tiles adrift in a field of brown.
	assert_eq(ActionPage.COLUMNS, 4)
	assert_eq(page.slot_count(), ActionPage.COLUMNS * ActionPage.ROWS)
	assert_true(page.slot_count() >= SelectionActions.MAX_DETAILS,
			"a page never holds FEWER than the strip it replaced")


func test_the_tile_never_starts_smaller_than_the_strips() -> void:
	# A Control added to a tree has size (0,0) for the rest of that frame, so the tile
	# cannot be measured in `_init`. Unparented here, so this is that fallback: the
	# strip's own size, which is legible rather than collapsed.
	assert_eq(page.tile_size(), ActionSlot.SIZE)


# ── what it draws ───────────────────────────────────────────────────────────

func test_a_short_list_fills_only_what_it_needs() -> void:
	page.show_actions("BUILD", _actions(3))
	assert_eq(_shown_ids().size(), 3, "no empty frames padding the page out")


func test_a_long_list_pages_rather_than_dropping_the_tail() -> void:
	# The failure a cap already had once: 19 buildings in 12 slots, and the town centre
	# silently off the end of the list.
	page.show_actions("BUILD", _actions(23))
	assert_true(page.page_count() > 1)
	assert_true(_shown_ids().size() <= page.slot_count())


func test_every_action_is_reachable_by_paging() -> void:
	var total := 23
	page.show_actions("BUILD", _actions(total))
	var seen: Array = []
	for i in range(page.page_count()):
		for id in _shown_ids():
			if not seen.has(id):
				seen.append(id)
		_press(SelectionActions.PAGE_NEXT)
	assert_eq(seen.size(), total, "all %d are reachable" % total)


func test_opening_a_different_list_goes_back_to_page_one() -> void:
	# A caller swapping BUILD for UPGRADES while holding page 2 would otherwise land
	# part-way through a list it has never seen.
	page.show_actions("BUILD", _actions(23))
	_press(SelectionActions.PAGE_NEXT)
	assert_eq(page.current_page(), 1)
	page.show_actions("UPGRADES", _actions(23))
	assert_eq(page.current_page(), 0)


# ── pressing ────────────────────────────────────────────────────────────────

func test_a_real_tile_reaches_the_listener() -> void:
	page.show_actions("BUILD", _actions(3))
	_press(&"thing:1")
	assert_eq(pressed, [&"thing:1"] as Array[StringName])


func test_the_arrows_turn_the_page_and_are_swallowed() -> void:
	# ⛔ THE ONE THAT MATTERS. An arrow that reached `GameScene` would be dispatched as
	# a verb with no command behind it -- and a nav slot carries no payload, so it would
	# fail somewhere else entirely.
	page.show_actions("BUILD", _actions(23))
	_press(SelectionActions.PAGE_NEXT)
	assert_eq(page.current_page(), 1)
	assert_true(pressed.is_empty(), "the arrow is not an action")
	_press(SelectionActions.PAGE_PREV)
	assert_eq(page.current_page(), 0)
	assert_true(pressed.is_empty())


func test_paging_past_the_end_stays_on_the_last_page() -> void:
	page.show_actions("BUILD", _actions(23))
	for i in range(10):
		_press(SelectionActions.PAGE_NEXT)
	assert_eq(page.current_page(), page.page_count() - 1)
	assert_false(_shown_ids().is_empty(), "and the last page is not empty")


func test_a_disabled_tile_sends_nothing() -> void:
	# `ActionSlot` guards this twice -- `disabled` on the Button and an `enabled` check in
	# `_on_pressed` -- and the page must not undo either. A greyed train tile on a
	# foundation (`8.x-train-on-foundation`) is the live case.
	var greyed: Array[HudAction] = [HudAction.new(&"thing:0", "Thing", "", false)]
	page.show_actions("BUILD", greyed)
	for slot in page.slots():
		if slot.action != null and slot.action.id == &"thing:0":
			slot._on_pressed()
	assert_true(pressed.is_empty(), "a greyed tile is not a route to a command")


## Press whichever visible slot carries `id`, through `ActionSlot`'s own handler rather
## than by calling the page's private one -- `GameScene.corner_buttons` records why: on
## these screens a control wired to nothing has looked exactly like a working one.
func _press(id: StringName) -> void:
	for slot in page.slots():
		if slot.visible and slot.action != null and slot.action.id == id:
			slot._on_pressed()
			return
