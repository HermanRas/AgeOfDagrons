## Undo and redo (PLAN.md 16.2a).
##
## ## WHAT THESE TESTS ARE ARRANGED AROUND
##
## Undo is the one feature whose bugs cost the author the work they were trying to save, so the
## assertions are about **the map afterwards**, not about the stack's bookkeeping. Three
## failures in particular are what the file is shaped by:
##
##   - **a step that restores the wrong bytes.** A stroke crossing varied terrain has to put
##     each tile back to its OWN previous kind, not to whatever the first one was — a bug that
##     looks like undo working, until you undo over a coastline.
##   - **a step that restores a half-finished state.** `place_start()` deletes a cluster and
##     builds another inside one act; if the two record separately, undoing leaves the map with
##     neither, which is worse than not undoing at all.
##   - **"no unsaved changes" being a lie.** `dirty` decides what a close-the-tool prompt says,
##     so it is asserted across save, undo past the save, redo back to it, and the branch that
##     throws the save point away.
##
## Everything is driven through `MapDocument`, because that is where the funnel is; the handful
## of editor tests at the end are about the two things only the screen can answer — that a
## canvas drag is one step, and that `Ctrl+Z` reaches this code at all.
extends TestCase

const SCRATCH := "user://test_undo"

## `Editor`'s script, for its `Tool` enum. `Editor.tscn`'s root has no `class_name` (nothing
## refers to it by type — see `test_map_validation.gd`), so the enum is reached through the
## script rather than by writing 0 and 1, which would quietly mean different tools the day one
## is inserted in the middle.
const EDITOR := preload("res://src/editor.gd")

var _n := 0
var doc: MapDocument = null
var _editors: Array[Node] = []


func before_each() -> void:
	_n += 1
	GameDataRegistry.load_from(GameRoot.resolve())
	doc = MapDocument.create(Vector2i(48, 48), "Undo Map")


func after_each() -> void:
	for e in _editors:
		e.free()
	_editors.clear()


func _dir() -> String:
	return ProjectSettings.globalize_path("%s/case_%d" % [SCRATCH, _n])


# ── painting ────────────────────────────────────────────────────────────────

func test_undo_puts_a_painted_tile_back() -> void:
	var at := Vector2i(4, 5)
	var before := doc.data.terrain_at(at)
	doc.paint(at, SimMap.Terrain.WATER_DEEP)
	assert_ne(doc.data.terrain_at(at), before)
	assert_ne(doc.undo(), "", "there was something to undo")
	assert_eq(doc.data.terrain_at(at), before)


func test_redo_paints_it_again() -> void:
	var at := Vector2i(4, 5)
	doc.paint(at, SimMap.Terrain.WATER_DEEP)
	doc.undo()
	assert_ne(doc.redo(), "")
	assert_eq(doc.data.terrain_at(at), SimMap.Terrain.WATER_DEEP)


func test_one_click_is_one_step() -> void:
	doc.paint(Vector2i(1, 1), SimMap.Terrain.SAND)
	assert_eq(doc.history.depth(), 1,
			"a call with no stroke around it opens and closes its own step")


## ⚠️ **THE ASSERTION 16.2a EXISTS FOR.** A stroke across a coastline is hundreds of `paint()`
## calls; one step each means the mis-drag the card describes takes hundreds of Ctrl+Z presses
## to undo and does not fit in the stack at all.
func test_a_stroke_is_one_step_however_many_tiles_it_touches() -> void:
	doc.begin_stroke()
	for x in range(4, 30):
		doc.paint(Vector2i(x, 9), SimMap.Terrain.WATER_SHALLOW)
	doc.end_stroke()
	assert_eq(doc.history.depth(), 1, "26 tiles, one gesture, one step")

	doc.undo()
	for x in range(4, 30):
		assert_eq(doc.data.terrain_at(Vector2i(x, 9)), MapDocument.DEFAULT_FILL,
				"tile %d,9 came back" % x)


## ⚠️ **EACH TILE GOES BACK TO ITS OWN KIND, NOT TO THE FIRST ONE'S.** A step records a
## before-and-after per tile precisely so a stroke over mixed ground is reversible; restoring
## one remembered kind across the run would look correct on a fresh map and destroy an
## author's terrain on a real one.
func test_undo_of_a_stroke_restores_the_kind_each_tile_actually_had() -> void:
	var kinds := [SimMap.Terrain.ROCK, SimMap.Terrain.SAND, SimMap.Terrain.DIRT,
			SimMap.Terrain.FOREST]
	for i in 12:
		doc.paint(Vector2i(i, 20), kinds[i % kinds.size()])
	var before: Array[int] = []
	for i in 12:
		before.append(doc.data.terrain_at(Vector2i(i, 20)))

	doc.begin_stroke()
	for i in 12:
		doc.paint(Vector2i(i, 20), SimMap.Terrain.WATER_DEEP)
	doc.end_stroke()
	doc.undo()

	for i in 12:
		assert_eq(doc.data.terrain_at(Vector2i(i, 20)), before[i],
				"tile %d,20 was %s" % [i, MapDocument.terrain_name(before[i])])


## The early return in `paint()` is what keeps a step from filling with no-ops -- a drag
## delivers the same tile dozens of times.
func test_repainting_the_same_kind_records_nothing() -> void:
	doc.paint(Vector2i(3, 3), SimMap.Terrain.SAND)
	doc.paint(Vector2i(3, 3), SimMap.Terrain.SAND)
	assert_eq(doc.history.depth(), 1, "the second call changed nothing to record")


func test_a_stroke_that_changed_nothing_pushes_no_step() -> void:
	doc.begin_stroke()
	doc.paint(Vector2i(0, 0), MapDocument.DEFAULT_FILL)   # already that kind
	doc.end_stroke()
	assert_eq(doc.history.depth(), 0,
			"a gesture that touched nothing is not an undo step")
	assert_eq(doc.undo(), "", "and there is nothing to take back")


## A mouse-release that never arrives -- the pointer leaving the window mid-drag -- must cost
## one over-large step, not a step that grows for the rest of the session.
func test_beginning_a_stroke_closes_one_left_open() -> void:
	doc.begin_stroke()
	doc.paint(Vector2i(1, 1), SimMap.Terrain.ROCK)
	doc.begin_stroke()
	doc.paint(Vector2i(2, 2), SimMap.Terrain.ROCK)
	doc.end_stroke()
	assert_eq(doc.history.depth(), 2, "the abandoned gesture was closed rather than extended")


func test_undo_at_the_bottom_of_the_stack_says_so_rather_than_wrapping() -> void:
	assert_eq(doc.undo(), "")
	assert_eq(doc.redo(), "")
	doc.paint(Vector2i(1, 1), SimMap.Terrain.ROCK)
	assert_ne(doc.undo(), "")
	assert_eq(doc.undo(), "", "one step, one undo")


# ── starts: two halves of one act ───────────────────────────────────────────

func test_undo_of_a_start_takes_the_whole_cluster_with_it() -> void:
	doc.place_start(1, Vector2i(24, 24))
	assert_true(doc.data.entities.size() > 1, "a start brings a base and an economy")
	assert_ne(doc.undo(), "")
	assert_eq(doc.data.entities.size(), 0, "the town centre, the units and the nodes all went")
	assert_eq(doc.data.starts.size(), 0)


## ⚠️ **THE NESTING TEST.** `place_start()` calls `remove_start()` inside its own step. If the
## two recorded separately, undoing a re-placed start would apply only the second half — the
## new cluster removed, the old one not restored — and the author would be left with a map
## that has neither, from a keystroke they pressed to get one back.
func test_undo_of_a_replaced_start_restores_the_first_one() -> void:
	doc.place_start(1, Vector2i(14, 14))
	var first := _signature(doc)
	doc.place_start(1, Vector2i(34, 34))
	assert_eq(doc.history.depth(), 2, "two placements, two steps")
	assert_ne(_signature(doc), first)

	doc.undo()
	assert_eq(doc.data.starts[0], Vector2i(14, 14), "back where it was")
	# ⚠️ **EXACT EQUALITY RATHER THAN "NOTHING NEAR THE SECOND START".** A distance check was
	# the first version of this and it fails on a small map for an innocent reason -- the two
	# clusters' economy rings legitimately overlap when the starts are 28 tiles apart -- so it
	# could not tell a leftover from a neighbour. The whole cluster, tile for tile, is both
	# stronger and independent of how far apart the starts happen to be.
	assert_eq(_signature(doc), first, "the map came back exactly as it was")


## Every entity and every start as one comparable string, order-independent.
##
## `MapData` has no equality of its own and comparing entity dictionaries directly is the
## aliasing trap `_copied()` exists for, so this flattens what a map IS: which things, owned by
## whom, at what size, where.
static func _signature(d: MapDocument) -> String:
	var bits: Array[String] = []
	for e in d.data.entities:
		bits.append("%s@%s/p%d/s%d" % [e["def_id"], e["tile"], int(e["player"]),
				int(e.get("size_class", 0))])
	bits.sort()
	return "%s | %s" % [str(d.data.starts), "; ".join(PackedStringArray(bits))]


func test_undo_of_a_cleared_start_brings_it_back() -> void:
	doc.place_start(1, Vector2i(24, 24))
	var was := _signature(doc)
	doc.remove_start(1)
	assert_eq(doc.data.entities.size(), 0)
	doc.undo()
	assert_eq(_signature(doc), was)
	assert_eq(doc.seats(), 1, "and it is a seat again, which is what the lobby reads")


## `Clear start` runs every line of `remove_start()` whether or not the player had one, and a
## stack full of invisible steps is a Ctrl+Z that appears not to work.
func test_clearing_a_start_nobody_has_is_not_a_step() -> void:
	doc.remove_start(5)
	assert_eq(doc.history.depth(), 0)


# ── entities ────────────────────────────────────────────────────────────────

func _a_tree() -> StringName:
	return &"res.tree"


func test_undo_of_a_placement_removes_it() -> void:
	assert_true(doc.add_entity(_a_tree(), 0, Vector2i(10, 10)))
	assert_eq(doc.data.entities.size(), 1)
	assert_ne(doc.undo(), "")
	assert_eq(doc.data.entities.size(), 0)
	assert_ne(doc.redo(), "")
	assert_eq(doc.data.entities.size(), 1)


## A click on occupied ground records nothing at all, so the author's next Ctrl+Z reaches the
## last thing that LANDED rather than the last thing they tried.
func test_a_refused_placement_records_nothing() -> void:
	doc.add_entity(_a_tree(), 0, Vector2i(10, 10))
	assert_false(doc.add_entity(_a_tree(), 0, Vector2i(10, 10)), "occupied")
	assert_false(doc.add_entity(_a_tree(), 0, Vector2i(-3, 0)), "off the map")
	assert_eq(doc.history.depth(), 1)


func test_undo_of_an_erase_brings_the_entity_back_intact() -> void:
	doc.add_entity(_a_tree(), 0, Vector2i(12, 13), 2)
	var was: Dictionary = doc.data.entities[0].duplicate()
	assert_eq(doc.remove_entity_at(Vector2i(12, 13)), 1)
	assert_eq(doc.data.entities.size(), 0)

	doc.undo()
	assert_eq(doc.data.entities.size(), 1)
	var back: Dictionary = doc.data.entities[0]
	# EVERY FIELD, because a size class or an owner lost in the round trip is a resource node
	# that comes back as the wrong thing and looks like it was never gone.
	for key in was:
		assert_eq(back.get(key), was[key], "%s survived the undo" % key)


func test_an_erase_that_hit_nothing_is_not_a_step() -> void:
	assert_eq(doc.remove_entity_at(Vector2i(40, 40)), 0)
	assert_eq(doc.history.depth(), 0)


## ⚠️ **THE ALIASING GUARD, AND IT IS HERE FOR 16.4.** `Array.duplicate()` is shallow, so a
## snapshot that copied only the array would share its dictionaries with the live map — and the
## move cursor, which edits `e["tile"]` in place, would rewrite the snapshot along with the
## map. Undo would then restore the building to where it had just been dragged, which reads as
## undo being ignored rather than as two names for one dictionary.
##
## The in-place edit below reaches past `MapDocument` on purpose: it is what 16.4 will do
## through a proper mutation, and the point is that the recorded step is already immune.
func test_a_snapshot_cannot_be_rewritten_by_editing_the_live_map() -> void:
	doc.add_entity(_a_tree(), 0, Vector2i(12, 13))
	doc.paint(Vector2i(0, 0), SimMap.Terrain.ROCK)   # a second step, so undo #1 is not the tree

	doc.data.entities[0]["tile"] = Vector2i(40, 40)
	doc.undo()                                        # the paint
	doc.undo()                                        # the placement
	doc.redo()                                        # and back
	assert_eq(doc.data.entities[0]["tile"], Vector2i(12, 13),
			"the step held its own copy of the entry")


# ── fill ────────────────────────────────────────────────────────────────────

func test_undo_of_a_fill_restores_the_map_it_replaced() -> void:
	doc.paint(Vector2i(5, 5), SimMap.Terrain.ROCK)
	doc.paint(Vector2i(6, 6), SimMap.Terrain.SAND)
	var before := doc.data.terrain.duplicate()

	doc.fill_all(SimMap.Terrain.WATER_DEEP)
	assert_ne(doc.data.terrain, before)
	doc.undo()
	assert_eq(doc.data.terrain, before, "every byte, not just the two that were painted")


# ── the stack itself ────────────────────────────────────────────────────────

## Every editor ever written works this way, and it is worth pinning because it is a deletion:
## a new act after an undo gives up the redo branch for good.
func test_a_new_act_discards_the_redo_branch() -> void:
	doc.paint(Vector2i(1, 1), SimMap.Terrain.ROCK)
	doc.paint(Vector2i(2, 2), SimMap.Terrain.SAND)
	doc.undo()
	assert_true(doc.history.can_redo())
	doc.paint(Vector2i(3, 3), SimMap.Terrain.DIRT)
	assert_false(doc.history.can_redo(), "the branch went when the map moved on")
	assert_eq(doc.history.redo_depth(), 0)


func test_the_stack_is_capped_and_the_oldest_step_is_the_one_that_goes() -> void:
	for i in UndoStack.LIMIT + 5:
		doc.paint(Vector2i(i % 48, i / 48), SimMap.Terrain.ROCK)
	assert_eq(doc.history.depth(), UndoStack.LIMIT)

	var undone := 0
	while doc.history.can_undo():
		doc.undo()
		undone += 1
	assert_eq(undone, UndoStack.LIMIT, "the cap is a cap, not a leak")
	# The five that fell off the front are baked in -- which is exactly why the save point has
	# to become unreachable when it falls off too (see the dirty tests).
	assert_eq(doc.data.terrain_at(Vector2i(0, 0)), SimMap.Terrain.ROCK)


func test_a_step_is_labelled_by_the_first_act_inside_it() -> void:
	doc.begin_stroke()
	doc.paint(Vector2i(1, 1), SimMap.Terrain.WATER_DEEP)
	doc.paint(Vector2i(2, 2), SimMap.Terrain.WATER_DEEP)
	doc.end_stroke()
	var label := doc.history.undo_label()
	assert_true(label.contains("paint"), label)
	assert_true(label.contains("Water Deep"), label)
	# THE TILE COUNT IS THE FIGURE AN AUTHOR CANNOT SEE FOR THEMSELVES: "paint Water Deep"
	# could be one tile or a whole coastline.
	assert_true(label.contains("2 tiles"), label)


func test_a_terrain_name_outside_the_enum_reads_as_a_number_rather_than_crashing() -> void:
	assert_eq(MapDocument.terrain_name(SimMap.Terrain.GRASS), "Grass")
	assert_eq(MapDocument.terrain_name(200), "terrain 200")
	assert_eq(MapDocument.terrain_name(-1), "terrain -1")


# ── "no unsaved changes" has to be true ─────────────────────────────────────

func test_undoing_back_to_the_last_save_clears_the_unsaved_flag() -> void:
	doc.place_start(1, Vector2i(12, 12))
	doc.place_start(2, Vector2i(36, 36))
	assert_eq(doc.save(_dir()), [] as Array[String])
	assert_false(doc.dirty)

	doc.paint(Vector2i(5, 5), SimMap.Terrain.ROCK)
	assert_true(doc.dirty)
	doc.undo()
	assert_false(doc.dirty, "the map matches the file again, so it is not unsaved work")
	doc.redo()
	assert_true(doc.dirty)


## Undo survives a save on purpose: an author saves, looks at the result, and changes their
## mind. Clearing the history there would make the save button a point of no return.
func test_saving_does_not_clear_the_history() -> void:
	doc.paint(Vector2i(5, 5), SimMap.Terrain.ROCK)
	assert_eq(doc.save(_dir()), [] as Array[String])
	assert_true(doc.history.can_undo(), "what was just saved can still be taken back")
	doc.undo()
	assert_eq(doc.data.terrain_at(Vector2i(5, 5)), MapDocument.DEFAULT_FILL)
	assert_true(doc.dirty, "and now the map differs from the file, the other way round")


## ⚠️ **A DEPTH IS NOT A STATE.** Save at depth 2, undo twice, then make two different edits:
## the stack is two deep again and the map has nothing to do with the file. Comparing depths
## alone would report "no unsaved changes" over work that has never been written.
func test_a_save_point_in_a_discarded_branch_stops_counting() -> void:
	doc.paint(Vector2i(1, 1), SimMap.Terrain.ROCK)
	doc.paint(Vector2i(2, 2), SimMap.Terrain.ROCK)
	assert_eq(doc.save(_dir()), [] as Array[String])
	doc.undo()
	doc.undo()
	assert_eq(doc.history.depth(), 0)

	doc.paint(Vector2i(20, 20), SimMap.Terrain.SAND)
	doc.paint(Vector2i(21, 21), SimMap.Terrain.SAND)
	assert_false(doc.history.at_clean_point(),
			"depth 2 is not the depth that was saved -- it is a different two")
	# Through the flag as well, since that is what a close-the-tool prompt will read: the
	# recompute happens on undo/redo, so drive one.
	doc.undo()
	doc.redo()
	assert_true(doc.dirty)


## The other way a save point stops being reachable: it falls off the front of a full stack,
## and the edit that was saved can no longer be undone away.
func test_a_save_point_that_falls_off_the_stack_stops_counting() -> void:
	assert_eq(doc.save(_dir()), [] as Array[String])
	assert_true(doc.history.at_clean_point(), "saved at depth zero")
	for i in UndoStack.LIMIT + 1:
		doc.paint(Vector2i(i % 48, i / 48), SimMap.Terrain.ROCK)
	while doc.history.can_undo():
		doc.undo()
	assert_false(doc.history.at_clean_point(),
			"one paint is baked in, so depth zero is no longer the file's state")
	assert_true(doc.dirty)


func test_an_opened_map_is_clean_before_anything_is_done_to_it() -> void:
	doc.place_start(1, Vector2i(12, 12))
	assert_eq(doc.save(_dir()), [] as Array[String])
	var problems: Array[String] = []
	var back := MapDocument.open(doc.dir, problems)
	assert_not_null(back)
	if back == null:
		return
	assert_false(back.dirty)
	assert_true(back.history.at_clean_point(), "the file it came from is the clean point")
	assert_false(back.history.can_undo(), "and there is nothing before it to undo to")


## ⚠️ **SAVE CAN ARRIVE MID-DRAG** — it is a button and it will be a shortcut — and the tiles
## painted so far are about to be in the file. A step left open would land on the stack AFTER
## the save point, so the first Ctrl+Z would take back changes that are already written while
## the tool reported no unsaved work.
func test_a_save_during_a_drag_closes_the_stroke_before_writing() -> void:
	doc.begin_stroke()
	doc.paint(Vector2i(7, 7), SimMap.Terrain.ROCK)
	assert_eq(doc.save(_dir()), [] as Array[String])
	assert_eq(doc.history.depth(), 1, "the gesture was sealed by the save")
	assert_false(doc.dirty)
	# And the file really holds it, which is the half that makes the flag honest.
	var problems: Array[String] = []
	var back := MapFile.load_map(doc.dir, problems)
	assert_not_null(back)
	if back == null:
		return
	assert_eq(back.terrain_at(Vector2i(7, 7)), SimMap.Terrain.ROCK)


## Ctrl+Z arriving with the button still down. Undoing the step before the one still
## accumulating would interleave them: the open step lands afterwards, on top of a map it was
## never recorded against.
func test_undo_during_a_drag_seals_the_gesture_first() -> void:
	doc.paint(Vector2i(1, 1), SimMap.Terrain.SAND)
	doc.begin_stroke()
	doc.paint(Vector2i(2, 2), SimMap.Terrain.ROCK)
	var what := doc.undo()
	assert_true(what.contains("Rock"), "the gesture in progress is what came back: %s" % what)
	assert_eq(doc.data.terrain_at(Vector2i(2, 2)), MapDocument.DEFAULT_FILL)
	assert_eq(doc.data.terrain_at(Vector2i(1, 1)), SimMap.Terrain.SAND,
			"and the step before it was left alone")


# ── the screen (PLAN.md 16.2a's other half) ─────────────────────────────────

func _open_editor() -> Node:
	var editor: Node = load("res://Editor.tscn").instantiate()
	# `_ready()` runs on entering a tree and this harness has none, so it is called by hand --
	# the same path `run/main_scene` takes. See `test_startup.gd`.
	editor._ready()
	_editors.append(editor)
	return editor


func test_the_undo_button_is_off_until_there_is_something_to_undo() -> void:
	var editor := _open_editor()
	assert_true(editor._undo_button.disabled, "a fresh map has no history")
	assert_true(editor._redo_button.disabled)
	assert_true(editor._undo_button.tooltip_text.contains("nothing to undo"),
			editor._undo_button.tooltip_text)

	editor.set_brush(SimMap.Terrain.ROCK)
	editor.set_tool(EDITOR.Tool.PAINT)
	editor.apply_tool(Vector2i(3, 3))
	assert_false(editor._undo_button.disabled, "and now there is")
	assert_true(editor._undo_button.tooltip_text.contains("paint Rock"),
			editor._undo_button.tooltip_text)

	editor.undo()
	assert_true(editor._undo_button.disabled)
	assert_false(editor._redo_button.disabled, "which is where redo comes from")


## ⚠️ **THE BUTTON'S STATE AND ITS TOOLTIP ARE TWO FACTS.** §6: the server browser's JOIN
## shipped enabled with nothing to join because `disabled` was set from "is there a sentence to
## print". Pinned by asserting the states independently, in the one place they could be
## conflated.
func test_the_button_state_does_not_come_from_the_tooltip() -> void:
	var editor := _open_editor()
	editor.set_tool(EDITOR.Tool.PAINT)
	editor.set_brush(SimMap.Terrain.SAND)
	editor.apply_tool(Vector2i(4, 4))
	editor.undo()
	assert_true(editor._undo_button.disabled)
	assert_true(editor._undo_button.tooltip_text.contains("nothing to undo"))
	assert_false(editor._redo_button.disabled)
	assert_true(editor._redo_button.tooltip_text.contains("redo paint Sand"),
			editor._redo_button.tooltip_text)


## ⚠️ **THE PLAYER PICKER IS WHAT AN UNDO LEAVES STALE.** The ✓ marks are the only place an
## author can see which players have a start, so a redraw without `_refresh_players()` shows
## P1 ticked over a map with no P1 start — and the next `Place start` then looks inert.
func test_undoing_a_start_untick_the_player_picker() -> void:
	var editor := _open_editor()
	editor.set_tool(EDITOR.Tool.START)
	editor.apply_tool(Vector2i(24, 24))
	assert_true(editor._player_picker.get_item_text(0).contains("✓"),
			editor._player_picker.get_item_text(0))
	editor.undo()
	assert_false(editor._player_picker.get_item_text(0).contains("✓"),
			"the tick has to go with the start: %s" % editor._player_picker.get_item_text(0))


## The canvas is the only thing that knows where a gesture begins and ends, which is why undo
## needed two more signals rather than working it out from the run of `painted`.
func test_a_canvas_drag_becomes_one_undo_step() -> void:
	var editor := _open_editor()
	editor.set_tool(EDITOR.Tool.PAINT)
	editor.set_brush(SimMap.Terrain.WATER_SHALLOW)
	editor._canvas.stroke_began.emit()
	for x in range(6, 20):
		editor.apply_tool(Vector2i(x, 11))
	editor._canvas.stroke_ended.emit()
	assert_eq(editor.document().history.depth(), 1, "14 tiles, one gesture")
	editor.undo()
	for x in range(6, 20):
		assert_eq(editor.document().data.terrain_at(Vector2i(x, 11)),
				MapDocument.DEFAULT_FILL, "tile %d,11" % x)


## ⚠️ **THE CARD'S ONE HARD CONSTRAINT.** `Ctrl+Z` is handled in `Editor._input`, which runs
## BEFORE the GUI pass — so it works while the palette's search `LineEdit` has focus, where
## `_gui_input`, `_shortcut_input` and a `Button.shortcut` all get nothing because `LineEdit`
## consumes the key as its own text undo. This drives the handler directly; the ordering
## itself is Godot's and the thing pinned here is that the shortcut is bound where it can win.
func test_ctrl_z_undoes_and_ctrl_shift_z_and_ctrl_y_redo() -> void:
	var editor := _open_editor()
	editor.set_tool(EDITOR.Tool.PAINT)
	editor.set_brush(SimMap.Terrain.ROCK)
	editor.apply_tool(Vector2i(8, 8))

	editor._input(_key(KEY_Z, true, false, false))
	assert_eq(editor.document().data.terrain_at(Vector2i(8, 8)), MapDocument.DEFAULT_FILL)
	editor._input(_key(KEY_Z, true, true, false))
	assert_eq(editor.document().data.terrain_at(Vector2i(8, 8)), SimMap.Terrain.ROCK,
			"Ctrl+Shift+Z is redo")
	editor._input(_key(KEY_Z, true, false, false))
	editor._input(_key(KEY_Y, true, false, false))
	assert_eq(editor.document().data.terrain_at(Vector2i(8, 8)), SimMap.Terrain.ROCK,
			"and so is Ctrl+Y")


## A held Ctrl+Z would unwind the whole stack in a second otherwise -- a keyboard repeat rate
## deciding how much of the author's work comes back.
func test_the_shortcut_ignores_key_repeats_and_a_bare_z() -> void:
	var editor := _open_editor()
	editor.set_tool(EDITOR.Tool.PAINT)
	editor.set_brush(SimMap.Terrain.ROCK)
	editor.apply_tool(Vector2i(8, 8))

	editor._input(_key(KEY_Z, true, false, true))    # echo
	assert_eq(editor.document().data.terrain_at(Vector2i(8, 8)), SimMap.Terrain.ROCK)
	editor._input(_key(KEY_Z, false, false, false))  # no ctrl
	assert_eq(editor.document().data.terrain_at(Vector2i(8, 8)), SimMap.Terrain.ROCK)


## The Open dialog is modal, and that has to include the keyboard: undoing behind it would
## change the map the author is about to replace with a different one.
func test_the_shortcut_is_ignored_while_the_open_dialog_is_up() -> void:
	var editor := _open_editor()
	editor.set_tool(EDITOR.Tool.PAINT)
	editor.set_brush(SimMap.Terrain.ROCK)
	editor.apply_tool(Vector2i(8, 8))
	editor.open_dialog()
	editor._input(_key(KEY_Z, true, false, false))
	assert_eq(editor.document().data.terrain_at(Vector2i(8, 8)), SimMap.Terrain.ROCK)
	editor.close_dialog()
	editor._input(_key(KEY_Z, true, false, false))
	assert_eq(editor.document().data.terrain_at(Vector2i(8, 8)), MapDocument.DEFAULT_FILL,
			"and it works again once the dialog is gone")


## ⚠️ **FOUND BY A SCREENSHOT TAKEN FOR SOMETHING ELSE** (`undo_ready.png`, which armed the
## brush and the palette independently for the first time). The status line asked
## `ObjectPalette.describe()` what the next click would do, and that answers "brush: …" only
## while the palette is on its Terrain tab — so picking a building and then pressing `Brush`
## produced *"place: Town Center (P1)"* over a tool that paints grass. A sentence on screen that
## gets believed and is wrong is worse than no sentence.
func test_the_status_line_describes_the_brush_and_not_a_leftover_palette_pick() -> void:
	var editor := _open_editor()
	editor._palette.set_category(ObjectPalette.Category.BUILDING)
	editor._palette.pick(StartLayout.TOWN_CENTRE)
	assert_true(editor._palette.describe().contains("Town Center"),
			"the palette still holds the pick, which is what made this reachable")

	editor.set_brush(SimMap.Terrain.WATER_DEEP)
	editor.set_tool(EDITOR.Tool.PAINT)
	var line: String = editor._status.text
	# `String.capitalize()` capitalises every word, so `WATER_DEEP` reads "Water Deep".
	assert_true(line.contains("brush: Water Deep"), line)
	assert_false(line.contains("place:"), "the palette does not describe a tool it is not driving")


static func _key(code: Key, ctrl: bool, shift: bool, echo: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	e.echo = echo
	return e
