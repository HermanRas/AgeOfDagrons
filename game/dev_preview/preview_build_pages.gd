extends Node

## The three pages the detail grid moved onto: BUILD, RESEARCH and UNITS (board
## `8.x-build-menu-modal`). **EXIT CODE IS THE ANSWER**, plus a screenshot of each,
## because whether a page of building art reads well is a question for a person.
##
##     godot --path game res://dev_preview/preview_build_pages.tscn
##
## ## WHAT IT CHECKS THAT A TEST CANNOT
##
## `test_action_page` asserts the page's behaviour with `.new()` and no tree, which is
## where the paging and the swallowed arrows belong. What it cannot see is the thing this
## card was most likely to get wrong: **how many tiles actually fit**. The count is
## measured off `body.size` at runtime, so it is exactly the number no headless test has.
##
## So this prints, per page, the measured grid and the page count, and photographs it.
## Three faults it can see and nothing else can: a grid that overflows its frame, a grid
## so small the pager never goes away, and tiles drawn at the wrong size.
##
## ⚠️ **AND IT PRESSES THE REAL TILES -- THEN READS THE SIM.** `GameScene.corner_buttons`
## records why: on these screens a control wired to nothing has looked exactly like a
## working one more than once.
##
## The first version of this file only *pressed*, and that is not the same check. It
## passed on a build whose UNITS tiles were all dead, because a press that goes nowhere
## still returns cleanly. The queue length before and after is what separates the two.

const SHOT_DIR := "user://"
const SETTLE_FRAMES := 120
const STEP_FRAMES := 30

var _game: Node
var _frames := 0
var _step := 0
var _problems: Array[String] = []
var _queue_before := -1
var _pressed_tile := ""


func _ready() -> void:
	print("=== build pages ===\n")
	_game = load("res://scenes/game/Game.tscn").instantiate()
	add_child(_game)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < SETTLE_FRAMES + _step * STEP_FRAMES:
		return
	_advance()


func _advance() -> void:
	match _step:
		0:
			_select_a_villager()
			_press_action(&"build")
		1:
			_report("BUILD")
			_shoot("page_build")
		2:
			_page_forward()
		3:
			_report("BUILD page 2")
			_shoot("page_build_2")
		4:
			# AGE 2, because a town centre at age 1 teaches nothing and the research tile
			# is offered only by a building that actually has techs. The first run of this
			# preview reported "no research tile" and that was the preview's fault.
			_close()
			Net.submit_command(DebugSetAgeCommand.new(Net.local_player_id(), 2))
		5:
			_select_the_town_centre()
			_press_action(&"research")
		6:
			_report("RESEARCH")
			_shoot("page_research")
		7:
			_close()
			_press_action(&"units")
		8:
			_report("UNITS")
			_shoot("page_units")
			_queue_before = _town_centre_queue()
			_press_tile_on_the_page()
		9:
			# ⛔ **DID THE PRESS DO ANYTHING.** Everything above this line was true of the
			# build that shipped a UNITS page whose tiles were dead: it opened, it fit, it
			# paged, it photographed well, and every unit portrait on it queued nothing
			# (owner, playtest 2026-09-21). The tile was wired to a handler that did not
			# know its prefix, so the order left as an untyped action and was dropped
			# unmatched with no error.
			#
			# So the assertion is the QUEUE, read from the sim a beat after the press --
			# the far end of Net, the command and `apply()`. Nothing short of that can tell
			# a live button from one that merely depresses.
			_check_the_press_reached_the_sim()
			_close()
			_finish()
	_step += 1


func _page() -> ActionPage:
	return _game._action_page


func _panel() -> SelectionPanel:
	return _game._panel


func _world() -> SimWorld:
	var host := Net.host()
	return host.world if host != null else null


func _select_a_villager() -> void:
	_select_first(func(e) -> bool:
		return e is SimUnit and e.def_id == &"unit.villager")


func _select_the_town_centre() -> void:
	_select_first(func(e) -> bool:
		return e is SimBuilding and e.def_id == &"building.town_center")


func _select_first(pred: Callable) -> void:
	var w := _world()
	if w == null:
		_fail("no host world")
		return
	var me := Net.local_player_id()
	var ids: Array = []
	for id in w.entities:
		var e = w.entities[id]
		if e.alive and e.owner_id == me and pred.call(e):
			ids.append(int(id))
	if ids.is_empty():
		_fail("nothing to select")
		return
	ids.sort()
	_game._view.select([int(ids[0])] as Array[int])
	_game._refresh_panel()


## The REAL tile in the action column, which is what opens a page.
func _press_action(id: StringName) -> void:
	for slot in _panel()._action_slots:
		if slot.visible and slot.action != null and slot.action.id == id:
			slot._on_pressed()
			return
	_fail("no %s tile on the action column" % id)


func _page_forward() -> void:
	for slot in _page().slots():
		if slot.visible and slot.action != null \
				and slot.action.id == SelectionActions.PAGE_NEXT:
			slot._on_pressed()
			return


func _close() -> void:
	_page().close()


## ⛔ **THE MEASURED GRID IS THE POINT.** `MAX_DETAILS` stopped being the answer when the
## tile size was fixed and the page size was not, so the number printed here is the one no
## headless test can produce -- and the one that decides whether the pager is still needed.
func _report(what: String) -> void:
	var page := _page()
	if not page.is_open():
		_fail("%s: the page did not open" % what)
		return

	var shown := 0
	var widest := 0.0
	var lowest := 0.0
	for slot in page.slots():
		if slot.visible and slot.action != null:
			shown += 1
			var r := slot.get_global_rect()
			widest = maxf(widest, r.end.x)
			lowest = maxf(lowest, r.end.y)

	print("  %s: %d slots, %d drawn, page %d of %d"
			% [what, page.slot_count(), shown, page.current_page() + 1, page.page_count()])
	print("      title %s, grid %dx%d, tile %.0f px (%.2fx the strip's %.0f)"
			% [page.title(), ActionPage.COLUMNS, ActionPage.ROWS, page.tile_size(),
			page.tile_size() / ActionSlot.SIZE, ActionSlot.SIZE])

	# ⛔ **THE TILE MUST ACTUALLY BE BIGGER, AND THIS IS THE ASSERTION THE FIRST VERSION
	# DID NOT HAVE.** It shipped a page of 72 px tiles adrift in a field of brown and every
	# check passed, because nothing was measuring the one thing the modal exists for:
	# *"better readability on cost to build and bigger buttons to tap"* (owner, 2026-09-21).
	if page.tile_size() <= ActionSlot.SIZE:
		_fail("%s: tiles are %.0f px, no bigger than the strip they replaced"
				% [what, page.tile_size()])

	# THE GRID MUST FIT INSIDE ITS OWN FRAME. A page that measured more columns than it has
	# room for draws the last one under the gold border, which is the failure this
	# measurement exists for and which a screenshot at a glance would forgive.
	var frame := page.body.get_global_rect()
	if widest > frame.end.x + 1.0 or lowest > frame.end.y + 1.0:
		_fail("%s: the grid runs outside the frame (%.0f,%.0f past %.0f,%.0f)"
				% [what, widest, lowest, frame.end.x, frame.end.y])
	if page.slot_count() < SelectionActions.MAX_DETAILS:
		_fail("%s: the page holds %d, FEWER than the strip's %d"
				% [what, page.slot_count(), SelectionActions.MAX_DETAILS])


## The selected town centre's production queue length, straight off the sim.
##
## Read from the HOST world rather than from the panel's `_facts`, deliberately: `_facts`
## is a snapshot the view was handed, so a press that only updated the view would still
## move it. The sim is the one witness that cannot be fooled by the thing under test.
func _town_centre_queue() -> int:
	var w := _world()
	if w == null:
		return -1
	var me := Net.local_player_id()
	for id in w.entities:
		var e = w.entities[id]
		if e is SimBuilding and e.alive and e.owner_id == me \
				and e.def_id == &"building.town_center":
			return e.queue.size()
	return -1


## Press the first real tile on the open page, by the same route a thumb does.
func _press_tile_on_the_page() -> void:
	for slot in _page().slots():
		if slot.visible and slot.action != null \
				and slot.action.id != SelectionActions.PAGE_NEXT \
				and slot.action.id != SelectionActions.PAGE_PREV:
			if not slot.action.enabled:
				continue
			_pressed_tile = String(slot.action.id)
			slot._on_pressed()
			return
	_fail("UNITS: no live tile to press")


func _check_the_press_reached_the_sim() -> void:
	if _pressed_tile.is_empty():
		return
	var after := _town_centre_queue()
	print("      pressed %s -- queue %d -> %d" % [_pressed_tile, _queue_before, after])
	if after <= _queue_before:
		_fail("UNITS: pressing %s queued nothing (still %d) -- the tile is dead"
				% [_pressed_tile, after])


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("      wrote ", ProjectSettings.globalize_path(path))


func _fail(message: String) -> void:
	_problems.append(message)


func _finish() -> void:
	print("")
	if _problems.is_empty():
		print("OK -- all three pages open, fit their frame, and page.")
		get_tree().quit(0)
		return
	print("%d PROBLEM(S):" % _problems.size())
	for p in _problems:
		print("  - %s" % p)
	get_tree().quit(1)
