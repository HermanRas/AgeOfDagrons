## PLAN.md 16.4: select, move and edit — the three cursors, and the four ways they lie.
##
## ## WHAT IS WORTH TESTING HERE IS NOT THAT A THING MOVES
##
## Dragging a building to a new tile is the visible half and the easy half; `preview_editor`
## photographs it. **The four faults below are all invisible**, and three of them are the kind
## that reports success:
##
##   1. **an undo step discarded as a no-op.** 16.2a's card says this row must call
##      `MapEdit.mark_changed()`, because a move is the first act that edits an entry IN PLACE —
##      same entity count, same starts, different tile — and `MapEdit.close()`'s size test is
##      blind to exactly that. Without it the step is thrown away and **a dragged building
##      cannot be dragged back**, with nothing failing anywhere.
##   2. **a shallow snapshot.** `Array.duplicate()` copies the array and not the dictionaries in
##      it, so a step and the live map would share the record a move edits — and undo would
##      restore the building to where it had just been dragged. `test_undo` performs the same
##      edit against `MapEdit._copied()`; this checks it through the real mutation.
##   3. **a stale selection index.** Entities are addressed by position, so an erase or an undo
##      can leave the index naming a different thing — and the author's next owner change lands
##      on it silently. See `MapDocument.selected`.
##   4. **a start left behind by its own town centre.** `MapData.starts` is a separate field and
##      `MapGen.build_from()` never derives a base from a start, so a town centre dragged off
##      its marker authors a player who opens the match owning nothing — 16.0's `can_start()`
##      rule 7, created by accident.
##
## The overlap rules get the same treatment as `add_entity`'s, because a move is a placement
## that happens to start somewhere: on the map, on clear ground, and **impassable ground is
## allowed** (a dock belongs on water).
extends TestCase

## `Editor`'s script, for its `Tool` enum — `Editor.tscn`'s root has no `class_name`.
##
## ⚠️ **NAMED AND NEVER NUMBERED.** The first version of this file drove `set_tool(4)` and
## `set_tool(5)` for SELECT and MOVE, and `Tool.START`'s removal on 2026-09-08 renumbered both —
## so the tests went on passing while driving the *wrong tools*. That is the exact failure the
## enum's own comment now warns about, and it took ten minutes to find because a raw int cannot
## be wrong in a way the compiler can see.
const EDITOR := preload("res://src/editor.gd")

var doc: MapDocument = null


func before_each() -> void:
	GameDataRegistry.load_from(GameRoot.resolve())
	doc = MapDocument.create(Vector2i(96, 96), "Cursor Test")


# ── select ──────────────────────────────────────────────────────────────────

## A click anywhere on a footprint picks the thing, not just its origin tile.
##
## `remove_entity_at()`'s rule, and the reason is the same: a 10x10 town centre clicked in the
## middle is being pointed at, and a picker that matched only the origin would do nothing
## ninety-nine times in a hundred and read as a broken tool.
func test_selecting_hits_anywhere_on_a_footprint() -> void:
	assert_true(doc.add_entity(StartLayout.TOWN_CENTRE, 1, Vector2i(30, 30)))
	var footprint: Vector2i = GameDataRegistry.building(StartLayout.TOWN_CENTRE).footprint
	assert_true(footprint.x >= 3, "this test assumes a town centre is bigger than a tile")

	assert_true(doc.select_at(Vector2i(30, 30)), "the origin tile selects it")
	assert_eq(doc.selected, 0)
	doc.clear_selection()
	# THE MIDDLE, which is where a person clicks.
	assert_true(doc.select_at(Vector2i(30, 30) + footprint / 2))
	assert_eq(doc.selected, 0, "a click inside the footprint is a click on the building")


func test_selecting_empty_ground_clears_the_selection() -> void:
	assert_true(doc.add_entity(StartLayout.TOWN_CENTRE, 1, Vector2i(30, 30)))
	doc.select_at(Vector2i(31, 31))
	assert_eq(doc.selected, 0)
	assert_true(doc.select_at(Vector2i(80, 80)), "the selection changed")
	assert_eq(doc.selected, -1, "empty ground is how an author gets out of a selection")


## Selecting is not an edit, so it must not dirty the map or reach the undo stack.
##
## ⚠️ **IF IT DID, `Ctrl+Z` WOULD TAKE BACK A HIGHLIGHT.** An author who selected a thing and
## then pressed undo expects their last real act back — and a stack of selections is 16.2a's
## *"a Ctrl+Z that appears not to work"* with a different cause.
func test_selecting_is_not_an_undo_step_and_does_not_dirty_the_map() -> void:
	assert_true(doc.add_entity(StartLayout.TOWN_CENTRE, 1, Vector2i(30, 30)))
	var depth := doc.history.depth()
	# CLEARED BY HAND, because `add_entity` above legitimately set it. The question is whether
	# SELECTING sets it, and a fixture that arrived here already dirty could not tell.
	doc.dirty = false
	doc.select_at(Vector2i(31, 31))
	doc.select_at(Vector2i(80, 80))
	assert_eq(doc.history.depth(), depth, "selecting is not a step")
	assert_false(doc.dirty, "selecting changed nothing about the map")


## The thing an author can SEE is the thing that gets picked.
##
## `_draw_entities` walks the list in order, so a later entry is drawn over an earlier one. A
## picker returning the first match would hand back what is underneath. Overlaps cannot be
## created by `add_entity` — they can arrive in an opened map, which 16.4b's rule allows to
## save — so the fixture builds one by hand.
func test_the_topmost_entity_wins_when_two_share_ground() -> void:
	doc.data.add_entity(&"unit.villager", 1, Vector2i(20, 20))
	doc.data.add_entity(&"unit.scout", 2, Vector2i(20, 20))
	assert_eq(doc.entity_index_at(Vector2i(20, 20)), 1,
			"the one drawn on top is the one selected")


# ── move ────────────────────────────────────────────────────────────────────

func test_moving_puts_the_entity_on_the_new_tile() -> void:
	assert_true(doc.add_entity(&"unit.villager", 1, Vector2i(10, 10)))
	doc.select_at(Vector2i(10, 10))
	assert_true(doc.move_selected(Vector2i(12, 14)))
	assert_eq(doc.data.entities[0]["tile"], Vector2i(12, 14))
	assert_eq(doc.data.entities.size(), 1, "a move is not a copy")


## ⚠️ **THE ONE 16.2a's ROW DEMANDS, AND THE WHOLE REASON THIS FILE EXISTS.**
##
## A move changes neither the entity count nor the starts array, so `MapEdit.close()`'s test
## cannot see it. Without `mark_changed()` the step is discarded as a no-op and the drag cannot
## be taken back — and nothing anywhere reports a problem.
func test_a_move_is_an_undo_step_that_can_be_taken_back() -> void:
	assert_true(doc.add_entity(&"unit.villager", 1, Vector2i(10, 10)))
	doc.select_at(Vector2i(10, 10))
	var depth := doc.history.depth()
	assert_true(doc.move_selected(Vector2i(40, 40)))
	assert_eq(doc.history.depth(), depth + 1,
			"a move that is not on the stack is a drag that cannot be undone")
	# THE LABEL IS CHECKED FOR ITS VERB AND NOT SPELLED OUT: the rest of it is
	# `GameDataRegistry.display_name`, which reads a `name` out of the game's `units.json` --
	# so asserting the whole string would make this test fail the day somebody renames a
	# villager, which is not what it is about.
	assert_true(doc.undo().begins_with("move "), "the step names what it undid")
	assert_eq(doc.data.entities[0]["tile"], Vector2i(10, 10), "back where it started")
	# AND FORWARD AGAIN, because a redo of an in-place edit has the same blind spot.
	doc.redo()
	assert_eq(doc.data.entities[0]["tile"], Vector2i(40, 40))


## The snapshot must not be sharing the dictionary the move edits.
##
## ⚠️ **A SHALLOW `Array.duplicate()` WOULD PASS EVERY OTHER TEST IN THIS FILE.** The step and
## the map would hold the same record, so `e["tile"] = to` would rewrite the "before" as well —
## and undo would restore the building to where it had just been dragged, which looks like undo
## being broken rather than like a copy being shallow.
func test_undoing_a_move_is_not_defeated_by_a_shared_dictionary() -> void:
	assert_true(doc.add_entity(StartLayout.TOWN_CENTRE, 1, Vector2i(20, 20)))
	doc.select_at(Vector2i(20, 20))
	doc.move_selected(Vector2i(60, 60))
	doc.move_selected(Vector2i(61, 61))
	doc.undo()
	# ONE STEP EACH, because these are two separate calls with no stroke open -- so the undo
	# above takes back only the second.
	assert_eq(doc.data.entities[0]["tile"], Vector2i(60, 60))
	doc.undo()
	assert_eq(doc.data.entities[0]["tile"], Vector2i(20, 20),
			"the first move's 'before' survived the second move")


## A whole drag is ONE step, which is `begin_stroke()`'s job and is checked here because a move
## is the act most likely to produce hundreds of samples.
func test_a_move_drag_is_one_undo_step() -> void:
	assert_true(doc.add_entity(&"unit.villager", 1, Vector2i(10, 10)))
	doc.select_at(Vector2i(10, 10))
	var depth := doc.history.depth()
	doc.begin_stroke()
	for x in range(11, 40):
		doc.move_selected(Vector2i(x, 10))
	doc.end_stroke()
	assert_eq(doc.history.depth(), depth + 1, "29 samples, one gesture, one step")
	doc.undo()
	assert_eq(doc.data.entities[0]["tile"], Vector2i(10, 10),
			"undoing the gesture returns it to where the drag began")


## Moving onto the same tile is not a change and not a step.
##
## A drag delivers the same tile many times over; a step for each is 16.2a's *"Ctrl+Z that
## appears not to work"*.
func test_moving_nowhere_changes_nothing() -> void:
	assert_true(doc.add_entity(&"unit.villager", 1, Vector2i(10, 10)))
	doc.select_at(Vector2i(10, 10))
	var depth := doc.history.depth()
	assert_false(doc.move_selected(Vector2i(10, 10)))
	assert_eq(doc.history.depth(), depth)


## A move is refused where a placement would be refused, and for the same two reasons.
func test_a_move_is_refused_off_the_map_and_onto_something_else() -> void:
	assert_true(doc.add_entity(StartLayout.TOWN_CENTRE, 1, Vector2i(20, 20)))
	assert_true(doc.add_entity(StartLayout.TOWN_CENTRE, 2, Vector2i(60, 60)))
	doc.select_at(Vector2i(20, 20))

	assert_false(doc.move_selected(Vector2i(-1, 20)), "off the map")
	assert_false(doc.move_selected(Vector2i(60, 60)), "on top of the other town centre")
	# ⚠️ **THE FOOTPRINT, NOT THE ORIGIN.** A 10x10 building whose origin is on the map and
	# whose far corner is not would be placed half in the void by `MapGen.build_from()`.
	var far := doc.data.size - Vector2i(2, 2)
	assert_false(doc.move_selected(far), "the whole footprint has to fit")
	assert_eq(doc.data.entities[0]["tile"], Vector2i(20, 20), "a refused move moved nothing")


## ⚠️ **A BUILDING MUST BE ABLE TO MOVE ONE TILE, and the obvious overlap check makes that
## impossible.** `claimed_tiles()` includes the mover's own footprint, so asking it directly
## means every nudge collides with where the thing already is. This is the test that fails if
## somebody simplifies `_fits()` back to it.
func test_a_building_can_be_nudged_onto_ground_it_already_overlaps() -> void:
	assert_true(doc.add_entity(StartLayout.TOWN_CENTRE, 1, Vector2i(20, 20)))
	doc.select_at(Vector2i(20, 20))
	assert_true(doc.move_selected(Vector2i(21, 20)),
			"a one-tile nudge overlaps its own old footprint and must be allowed")


## Impassable ground is not refused — `add_entity()`'s deliberate rule, seen from the move side.
func test_a_move_onto_water_is_allowed() -> void:
	doc.paint(Vector2i(50, 50), SimMap.Terrain.WATER_DEEP)
	assert_true(doc.add_entity(&"building.dock", 1, Vector2i(10, 10)))
	doc.select_at(Vector2i(10, 10))
	assert_true(doc.move_selected(Vector2i(50, 50)),
			"a dock belongs on water; the tool must not second-guess the author")


## ⚠️ **THE START FOLLOWS ITS OWN TOWN CENTRE, or the map authors a player who owns nothing.**
##
## `MapData.starts` is a separate field from the entity list and `MapGen.build_from()` gives a
## player their base purely from the entities the map LISTS — it never derives one from a start.
## So a town centre dragged off its marker leaves the marker on bare ground, which is exactly
## the map 16.0's `can_start()` rule 7 refuses.
func test_dragging_a_town_centre_takes_its_start_with_it() -> void:
	assert_true(doc.place_start(1, Vector2i(30, 30)))
	assert_eq(doc.data.starts[0], Vector2i(30, 30))
	var at := doc.entity_index_at(Vector2i(30, 30))
	assert_true(at >= 0, "place_start puts a town centre on the marker")
	doc.selected = at
	assert_eq(StringName(doc.selected_entity()["def_id"]), StartLayout.TOWN_CENTRE,
			"the thing on the marker tile is the town centre")

	# ⚠️ **THE ASSERTION IS THE DELTA AND NOT THE DESTINATION, and that is the bug this test
	# found.** A start is the footprint's CENTRE and `tile` is its ORIGIN, five tiles apart for a
	# 10x10 town centre — so "the start is now where the building's origin is" is wrong by five
	# tiles, and the first version of `move_selected` compared the two directly and could never
	# match at all. Far enough from (30, 30) to clear the opening's own resource ring, which
	# would otherwise refuse the move and look like this rule failing.
	var origin: Vector2i = doc.selected_entity()["tile"]
	var to := Vector2i(70, 70)
	assert_true(doc.move_selected(to), "there is clear ground at 70,70")
	assert_eq(doc.data.starts[0], Vector2i(30, 30) + (to - origin),
			"the marker kept its place inside the building that carried it")
	# AND IT IS STILL INSIDE THE BUILDING, which is the fact the game cares about: a marker that
	# drifted outside its own town centre is 16.0's rule 7 waiting to fire.
	assert_true(MapData.footprint_rect_of(doc.selected_entity()).has(doc.data.starts[0]),
			"the start is still standing on its own base")


## And nothing else drags the start.
##
## An author moving a villager out of the opening is doing something completely ordinary, and a
## start that followed it would relocate the player's whole beginning by accident.
func test_dragging_a_villager_off_the_marker_leaves_the_start_alone() -> void:
	assert_true(doc.place_start(1, Vector2i(30, 30)))
	# A VILLAGER STANDING ON THE MARKER TILE, which is the case that would trip a rule written
	# as "whatever is on the start tile moves the start".
	doc.data.add_entity(&"unit.villager", 1, Vector2i(30, 30))
	doc.selected = doc.data.entities.size() - 1
	assert_true(doc.move_selected(Vector2i(70, 70)))
	assert_eq(doc.data.starts[0], Vector2i(30, 30), "the start stayed where it was")


# ── edit (the inspector's two fields) ───────────────────────────────────────

func test_changing_the_owner_changes_it_and_is_undoable() -> void:
	assert_true(doc.add_entity(&"unit.villager", 1, Vector2i(10, 10)))
	doc.select_at(Vector2i(10, 10))
	var depth := doc.history.depth()
	assert_true(doc.set_selected_owner(3))
	assert_eq(int(doc.data.entities[0]["player"]), 3)
	assert_eq(doc.history.depth(), depth + 1, "an in-place field edit is still a step")
	doc.undo()
	assert_eq(int(doc.data.entities[0]["player"]), 1)


## Gaia is an owner and not a clear.
##
## Every resource node on every map is `player: 0`, and so are the dragon and her nest, so an
## owner edit that treated 0 as "no owner" could not author half of what a map needs.
func test_gaia_is_a_real_owner() -> void:
	assert_true(doc.add_entity(&"unit.villager", 1, Vector2i(10, 10)))
	doc.select_at(Vector2i(10, 10))
	assert_true(doc.set_selected_owner(0))
	assert_eq(int(doc.data.entities[0]["player"]), 0)


func test_an_owner_outside_the_eight_players_is_refused() -> void:
	assert_true(doc.add_entity(&"unit.villager", 1, Vector2i(10, 10)))
	doc.select_at(Vector2i(10, 10))
	assert_false(doc.set_selected_owner(9), "there is no ninth player in the lobby")
	assert_false(doc.set_selected_owner(-1))
	assert_eq(int(doc.data.entities[0]["player"]), 1)


## ⚠️ **A SIZE CHANGE IS A FOOTPRINT CHANGE, so it can be refused like a placement.**
##
## `ResourceDef.footprint_for_size` makes a large node bigger than a small one, so growing one
## can run into a neighbour — and a size edit that silently overlapped would author exactly the
## map `MapValidator` reports.
func test_a_size_change_that_would_overlap_is_refused() -> void:
	var res_id := _a_resource_that_grows()
	if res_id.is_empty():
		return                            # no resource in the roster changes size; nothing to test
	var rd: ResourceDef = GameDataRegistry.resource_def(res_id)
	var big := rd.footprint_for_size(rd.size_class_count() - 1)
	assert_true(doc.add_entity(res_id, 0, Vector2i(10, 10), 0))
	# A NEIGHBOUR EXACTLY WHERE THE GROWN FOOTPRINT WOULD REACH, so the refusal is about the new
	# size and not about the old one.
	assert_true(doc.add_entity(&"unit.villager", 1, Vector2i(10 + big.x - 1, 10 + big.y - 1)))
	doc.select_at(Vector2i(10, 10))
	assert_false(doc.set_selected_size_class(rd.size_class_count() - 1))
	assert_eq(int(doc.data.entities[0]["size_class"]), 0, "a refused edit changed nothing")


## And it goes through when there is room.
func test_a_size_change_with_room_is_applied() -> void:
	var res_id := _a_resource_that_grows()
	if res_id.is_empty():
		return
	var rd: ResourceDef = GameDataRegistry.resource_def(res_id)
	assert_true(doc.add_entity(res_id, 0, Vector2i(40, 40), 0))
	doc.select_at(Vector2i(40, 40))
	assert_true(doc.set_selected_size_class(rd.size_class_count() - 1))
	assert_eq(int(doc.data.entities[0]["size_class"]), rd.size_class_count() - 1)


## A resource whose footprint actually differs between its smallest and largest class.
##
## **Found rather than named**, so the two tests above do not depend on `res.gold_mine` still
## being the one that grows: a hardcoded id turns into a vacuous test the day the data changes,
## which is §5's *"a behaviour test tied to whichever piece of data happens to be widest has an
## expiry date"*.
func _a_resource_that_grows() -> StringName:
	for id in GameDataRegistry.resource_ids():
		var rd: ResourceDef = GameDataRegistry.resource_def(id)
		if rd == null or rd.size_class_count() < 2:
			continue
		if rd.footprint_for_size(0) != rd.footprint_for_size(rd.size_class_count() - 1):
			return id
	return &""


# ── the selection index, which is the silent one ────────────────────────────

## ⚠️ **AN ERASE REBUILDS THE LIST, SO AN INDEX INTO IT NAMES SOMETHING ELSE AFTERWARDS.**
##
## Without the clear, the inspector would go on describing position 1 — which is now a different
## entity — and the author's next owner change would land on it with nothing to show that it
## had. See `MapDocument.selected`.
func test_an_erase_clears_the_selection_rather_than_leaving_it_stale() -> void:
	doc.add_entity(&"unit.villager", 1, Vector2i(10, 10))
	doc.add_entity(&"unit.scout", 1, Vector2i(20, 20))
	doc.select_at(Vector2i(20, 20))
	assert_eq(doc.selected, 1)
	assert_eq(doc.remove_entity_at(Vector2i(10, 10)), 1, "the FIRST one goes")
	assert_eq(doc.selected, -1,
			"index 1 now names nothing; a stale index is the invisible failure")


## Undo replaces the entity list from a snapshot, which may be a different shape entirely.
func test_undo_clears_the_selection() -> void:
	doc.add_entity(&"unit.villager", 1, Vector2i(10, 10))
	doc.select_at(Vector2i(10, 10))
	assert_eq(doc.selected, 0)
	doc.undo()
	assert_eq(doc.selected, -1)


## Clearing a start filters the whole list by owner, so every index past the first removal moves.
func test_clearing_a_start_clears_the_selection() -> void:
	doc.place_start(1, Vector2i(30, 30))
	doc.select_at(Vector2i(30, 30))
	assert_true(doc.selected >= 0)
	doc.remove_start(1)
	assert_eq(doc.selected, -1)


## ⚠️ **PLACING IS THE ONE THAT MUST *NOT* CLEAR IT, and it looks like an oversight beside the
## other three.** `add_entity` appends, so every existing index still names what it named —
## and an author who selects a thing, places three more and then edits the first one is doing
## something completely ordinary.
func test_placing_something_leaves_the_selection_alone() -> void:
	doc.add_entity(&"unit.villager", 1, Vector2i(10, 10))
	doc.select_at(Vector2i(10, 10))
	doc.add_entity(&"unit.scout", 1, Vector2i(20, 20))
	doc.add_entity(&"unit.scout", 1, Vector2i(22, 22))
	assert_eq(doc.selected, 0, "an append cannot invalidate an earlier index")
	assert_eq(StringName(doc.selected_entity()["def_id"]), &"unit.villager")


## ⚠️ **A DRAG IS JUDGED ON WHERE IT ENDS, NOT ON WHAT IT CROSSED**, and the naive version of a
## move drag gets this wrong in a way that reads as a broken tool.
##
## Found by `dev/preview_editor.tscn`: a nine-tile drag of a town centre advanced **two tiles**
## and stopped, because the villagers of its own start stood in the path. Every intermediate
## sample was legitimately refused and the clear ground beyond them could not be reached at all.
## `Editor._grab_intent` remembers what the pointer asked for and `_finish_move()` retries it on
## release — which is why this test drives the editor rather than the document: the retry is the
## editor's, and it has to happen **before** the stroke seals its undo step or one drag becomes
## two Ctrl+Z presses.
func test_a_drag_can_cross_an_obstacle_to_reach_clear_ground() -> void:
	var editor := _open_editor()
	editor.show_document(doc)
	assert_true(doc.add_entity(StartLayout.TOWN_CENTRE, 1, Vector2i(10, 10)))
	# A WALL OF VILLAGERS ACROSS THE PATH, four tiles along the diagonal.
	for i in range(0, 4):
		doc.data.add_entity(&"unit.villager", 1, Vector2i(22 + i, 22 + i))
	doc.select_at(Vector2i(10, 10))
	var before := doc.history.depth()

	editor.set_tool(EDITOR.Tool.SELECT)
	editor.set_tool(EDITOR.Tool.MOVE)
	var canvas: MapCanvas = editor._canvas
	canvas.stroke_began.emit()
	for step in range(0, 30):
		editor.apply_tool(Vector2i(10 + step, 10 + step))
	canvas.stroke_ended.emit()

	assert_eq(doc.data.entities[0]["tile"], Vector2i(39, 39),
			"the drag ended on clear ground and must have got there")
	assert_eq(doc.history.depth(), before + 1,
			"the retry happens inside the gesture, so it is still ONE undo step")
	editor.free()


## A gesture that ends somewhere illegal leaves the entity where it legally got to, and says so.
##
## The alternative — snapping back to the start of the drag — throws away a move the author can
## see happened, and is worse than stopping short.
func test_a_drag_that_ends_on_something_leaves_the_entity_where_it_reached() -> void:
	var editor := _open_editor()
	editor.show_document(doc)
	assert_true(doc.add_entity(&"unit.villager", 1, Vector2i(10, 10)))
	assert_true(doc.add_entity(&"unit.scout", 2, Vector2i(14, 10)))
	doc.select_at(Vector2i(10, 10))
	editor.set_tool(EDITOR.Tool.MOVE)
	var canvas: MapCanvas = editor._canvas
	canvas.stroke_began.emit()
	for x in range(10, 15):
		editor.apply_tool(Vector2i(x, 10))
	canvas.stroke_ended.emit()
	assert_eq(doc.data.entities[0]["tile"], Vector2i(13, 10),
			"it stopped beside the scout rather than snapping home")
	editor.free()


## An editor built and driven without a tree, `test_startup`'s harness.
##
## `_ready()` is called by hand because `add_child` needs a tree this suite has not got — the
## same code path the main scene takes, which is what makes driving it here honest.
func _open_editor() -> Node:
	var editor: Node = load("res://Editor.tscn").instantiate()
	editor._ready()
	return editor


# ── the start as a palette entry (owner's ruling, 2026-09-08) ───────────────
#
# *"can we add the start location as a building option ... we can use the same select and erase
# as normal buildings and remove duplicates."* So `Tool.START`, the toolbar's P1..P8 dropdown and
# the `Clear start` button are gone, and PLACE and ERASE do the work. These tests drive the
# EDITOR rather than the document, because the branch that makes it work is `apply_tool`'s and
# `MapDocument.place_start`/`remove_start` did not change at all.

## Placing the palette's start entry lays down a real start, not an entity called "start".
##
## ⚠️ **THE FAILURE THIS RULES OUT IS THE QUIET ONE.** `START_ID` is not a def, so if
## `apply_tool` ever stopped branching on it the click would fall through to `add_entity()` —
## which would happily append `{def_id: "start.player", ...}` to the entity list. It would save,
## it would reload, and `MapGen.build_from()` would spawn **nothing** for it: a map with a start
## the game does not know about and a player who owns the ground and no town centre.
func test_placing_the_palette_start_creates_a_real_start() -> void:
	var editor := _open_editor()
	editor.show_document(doc)
	editor._palette.set_player(2)
	editor._palette.pick(ObjectPalette.START_ID)
	editor.set_tool(EDITOR.Tool.PLACE)
	editor.apply_tool(Vector2i(30, 30))

	assert_eq(doc.data.starts.size(), 2, "P2 means two slots, P1's empty")
	assert_eq(doc.data.starts[1], Vector2i(30, 30), "the marker is in the starts field")
	# AND THE CLUSTER, which is what `place_start` is for -- a bare marker authors a player who
	# owns nothing (16.0's `can_start()` rule 7).
	assert_true(doc.data.entities.size() > 5,
			"a start brings a base and an opening: got %d entities" % doc.data.entities.size())
	# NOT AN ENTITY, asserted directly: this is the fall-through the branch prevents.
	for e in doc.data.entities:
		assert_true(StringName(e.get("def_id", &"")) != ObjectPalette.START_ID,
				"the start id must never reach the entity list")
	editor.free()


## ⚠️ **GAIA IS THE MOST LIKELY WAY TO MEET THIS FEATURE FOR THE FIRST TIME, AND IT CANNOT OWN A
## START.** The palette defaults to Gaia on the Resource tab and every node on every map is
## gaia's, so an author who lays out some trees and then picks the start tile arrives with owner
## 0 — `place_start()` refuses `player < 1`. Without the notice the click does nothing at all and
## reads as the new palette entry being broken.
func test_a_start_owned_by_gaia_is_refused_with_a_sentence() -> void:
	var editor := _open_editor()
	editor.show_document(doc)
	editor._palette.set_player(ObjectPalette.GAIA)
	editor._palette.pick(ObjectPalette.START_ID)
	editor.set_tool(EDITOR.Tool.PLACE)
	editor.apply_tool(Vector2i(30, 30))
	assert_true(doc.data.starts.is_empty(), "gaia has no start to place")
	assert_true(editor._notice_label.text.to_lower().contains("needs a player"),
			"the refusal has to say what to do about it: %s" % editor._notice_label.text)
	editor.free()


## The eraser clears a start, which is what retired the `Clear start` button.
##
## ⚠️ **AND IT HAS TO BE CHECKED BEFORE `remove_entity_at()`, because that function REFUSES a
## start's cluster** — deliberately, so an author cannot pick one villager out of a start and
## leave an `ORIGIN_KEY` tag describing something that is no longer there. Without the branch,
## erasing a base would do nothing and there would be no way to clear a start at all.
func test_erasing_a_base_clears_the_whole_start() -> void:
	var editor := _open_editor()
	editor.show_document(doc)
	assert_true(doc.place_start(1, Vector2i(30, 30)))
	var with_start := doc.data.entities.size()
	assert_true(with_start > 5)

	editor.set_tool(EDITOR.Tool.ERASE)
	# A CLICK IN THE MIDDLE OF THE TOWN CENTRE, which is what an author does -- not the marker
	# tile, which they cannot see the coordinates of.
	editor.apply_tool(Vector2i(30, 30))
	assert_true(doc.data.starts.is_empty(), "the marker went")
	assert_true(doc.data.entities.size() < with_start,
			"and the cluster with it: %d -> %d" % [with_start, doc.data.entities.size()])
	# ⚠️ **SAID LOUDLY, because one click removed a town centre, five villagers, a scout and a
	# ring of resources.** That is not a result an author should have to infer from a count.
	assert_true(editor._notice_label.text.to_upper().contains("CLEARED"),
			editor._notice_label.text)
	editor.free()


## An ordinary building is still erased by the eraser, and the start branch does not swallow it.
##
## The regression this rules out: `start_owner_at()` answering "yes" too eagerly and turning
## every erase into a clear-start.
func test_erasing_an_ordinary_building_still_just_erases_it() -> void:
	var editor := _open_editor()
	editor.show_document(doc)
	assert_true(doc.add_entity(&"building.house", 1, Vector2i(40, 40)))
	assert_true(doc.place_start(1, Vector2i(20, 20)))
	var starts_before := doc.data.starts.duplicate()
	editor.set_tool(EDITOR.Tool.ERASE)
	editor.apply_tool(Vector2i(40, 40))
	assert_eq(doc.data.starts, starts_before, "the start was nowhere near it")
	for e in doc.data.entities:
		assert_true(StringName(e.get("def_id", &"")) != &"building.house", "the house went")
	editor.free()


## `start_owner_at()` finds a start from anywhere on the base that carries it.
##
## ⚠️ **A START IS A CENTRE AND AN ENTITY'S `tile` IS AN ORIGIN**, so neither the marker tile nor
## the town centre's origin is where an author clicks — they click the middle of a 10x10
## building. This is the same centre/origin distinction that broke the move's start-following
## rule, asked of the eraser.
func test_a_start_is_found_from_any_tile_of_its_base() -> void:
	assert_true(doc.place_start(1, Vector2i(30, 30)))
	assert_eq(doc.start_owner_at(Vector2i(30, 30)), 1, "the marker tile")
	var at := doc.entity_index_at(Vector2i(30, 30))
	var origin: Vector2i = doc.data.entities[at]["tile"]
	assert_eq(doc.start_owner_at(origin), 1, "the base's origin corner")
	assert_true(origin != Vector2i(30, 30),
			"if these are equal the test proves nothing -- a town centre is not 1x1")
	# AND SOMEWHERE IN THE MIDDLE that is neither.
	assert_eq(doc.start_owner_at(origin + Vector2i(1, 1)), 1)
	# NOT ANYWHERE ELSE.
	assert_eq(doc.start_owner_at(Vector2i(80, 80)), 0)


## A building that is not a town centre never carries a start, even standing on the marker.
##
## `_is_town_centre` is the identity test rather than "a big building near the marker", because
## `StartLayout.place()` is what put the two on the same tile and that constant is the only fact
## tying them together. A castle dropped on a start is not the start's base.
func test_another_building_on_the_marker_does_not_count_as_the_start() -> void:
	assert_true(doc.place_start(1, Vector2i(30, 30)))
	var at := doc.entity_index_at(Vector2i(30, 30))
	# THE TOWN CENTRE REMOVED FROM THE LIST BY HAND, leaving the marker with no base -- which is
	# a state `MapFile` can load even though `place_start` never creates it.
	doc.data.entities.remove_at(at)
	doc.data.add_entity(&"building.castle", 1, Vector2i(28, 28))
	assert_eq(doc.start_owner_at(Vector2i(28, 28)), 0, "a castle is not a start's base")
	# THE MARKER TILE ITSELF STILL ANSWERS, which is the first of `start_owner_at`'s two lookups
	# and the reason it has two.
	assert_eq(doc.start_owner_at(Vector2i(30, 30)), 1)


# ── the wall drag, and why it is not here (PLAN.md 16.4) ────────────────────

## ⚠️ **DRAG-TO-PLACE-WALLS IS THE HALF OF 16.4 THE FORMAT CANNOT EXPRESS YET, AND THIS TEST IS
## THE MECHANICAL REMINDER.** `test_object_palette`'s Area test is the model: it fails the day
## `MapData` gains the field, which is the day the feature may follow.
##
## **What is missing.** A wall is the one building whose footprint is not a property of its def.
## `WallPlan` snaps a drag to an axis and hands `spawn_building` two things a map file has
## nowhere to put:
##
##   - a **`footprint_override`** — `[9, 2]` lying east-west, `[2, 9]` north-south. `MapData`'s
##     own header rules footprints out on purpose: *"they are a property of the def, and a map
##     that recorded them would go stale the day a building is resized"*, which is right for
##     every other building in the game and wrong for this one;
##   - a **`facing`**, from `WallPlan.FACING_FOR_AXIS`.
##
## **What would happen without them.** `MapGen.build_from()` calls
## `spawn_building(def_id, owner, tile, COMPLETE, true)` — no override, no facing — so both
## default: the def's own east-west footprint, and facing 0, which `FACING_FOR_AXIS` says is the
## **north-south** wall. So every wall on every authored map would come out with an east-west
## footprint and a north-south sprite: **ninety degrees wrong, and wrong in both directions at
## once.** That is the exact error the owner reported on 2026-08-28 (*"i am dragging NE to SW,
## the walls look like NW to SE"*) and it took six days and a re-measurement of twelve atlases
## to settle; reintroducing it through the file would cost that again.
##
## **Why a test rather than a fix.** Adding the two keys is a FORMAT change, and §16 decision 7
## has a checklist for one — optional field, absent means the old behaviour, the version does
## not move — plus a game-side reader in `MapGen.build_from()` and a re-copy of the hash-checked
## `map_data.gd`. That is a deliberate change with the owner's name on it, not a slice of a
## cursor row. **No shipped map has a wall today** (checked across `maps/sample_duel` and all
## five campaign maps), so nothing is broken while this waits — and a drag that authored one
## would break it silently, which is 16.3's Area argument exactly: *work lost behind a
## successful save*.
func test_the_format_still_cannot_express_a_walls_axis() -> void:
	doc.add_entity(&"building.wall_stone_short", 1, Vector2i(10, 10))
	var written: Dictionary = doc.data.to_dict()
	var entity: Dictionary = (written["entities"] as Array)[0]
	for key in ["facing", "footprint", "axis"]:
		assert_false(entity.has(key),
				("`%s` is in the entity record now — the format can carry a wall's axis, so"
				+ " 16.4's drag can be built. Read this test's comment first: `MapGen.build_from`"
				+ " has to pass it to `spawn_building` too, or nothing changes on screen.") % key)


## Nothing selected is answered rather than crashed on, from every entry point.
##
## The editor calls these on whatever the author last did, and "nothing" is the state the tool
## opens in — so an unguarded `data.entities[-1]` here would be a crash on the first click.
func test_every_cursor_op_is_safe_with_nothing_selected() -> void:
	assert_true(doc.selected_entity().is_empty())
	assert_false(doc.move_selected(Vector2i(10, 10)))
	assert_false(doc.set_selected_owner(2))
	assert_false(doc.set_selected_size_class(1))
	# AND WITH AN INDEX PAST THE END, which is what a stale one looks like if any of the clears
	# above is ever removed.
	doc.selected = 99
	assert_true(doc.selected_entity().is_empty())
	assert_false(doc.move_selected(Vector2i(10, 10)))
