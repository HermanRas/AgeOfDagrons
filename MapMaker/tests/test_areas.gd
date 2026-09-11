## PLAN.md 16.5: named regions — the field, the document's mutations, the palette tab, and the
## drag that authors one.
##
## ## WHAT THIS ROW COULD BE QUIETLY WRONG ABOUT
##
## A region is a magenta box on a canvas, so `dev/preview_editor.tscn` is what looks at it and
## `preview_saved_map` is what proves it reaches a match. **What a headless test can see is every
## place the row could be wrong without anything failing:**
##
##   - **the round trip.** A region the tool draws and `MapFile` drops is *work lost behind a
##     successful save*, which is the exact failure the Area tab was deferred for two rows ago.
##     Absent-means-none has to hold in both directions, or the five committed campaign maps stop
##     loading.
##   - **undo.** `MapEdit` snapshots three lists now, and a step that recorded areas without
##     recording entities would, on redo, assign an empty entity list — *every building on the
##     map deleted by pressing redo*, which is what `_closed` exists to prevent.
##   - **the drag's arithmetic.** A press and a release on one tile is a 1x1 region; off-by-one on
##     the size makes it empty, `MapData.add_area()` refuses an empty one, and a single click then
##     does nothing while looking exactly like a save that failed.
##   - **the eraser's precedence.** A region can cover a quarter of the map at a 10% fill, so it
##     is the easiest thing here to forget is under the pointer. If it were erased before the tree
##     the author was aiming at, that would be silent destruction of the thing they cannot see —
##     `MapDocument.remove_start()`'s ⛔ note is this tool's standing record of that class.
##   - **an unnamed region.** The Areas tab arms the tool before anything is typed, deliberately,
##     so the refusal has to be on the drag and it has to say which half is missing.
##
## Nothing here writes into repo-root `maps/` or `scenarios/` — `test_map_document`'s rule.
extends TestCase

## `Editor`'s script, for its `Tool` enum — `Editor.tscn`'s root has no `class_name`.
##
## ⚠️ **NAMED AND NEVER NUMBERED**, `test_cursors`' scar: it drove `set_tool(4)`/`set_tool(5)` by
## literal and `Tool.START`'s removal renumbered both, so those tests went on passing while
## exercising the wrong tools. 16.5 appends `Tool.AREA`, which is the fifth time that value has
## moved for somebody.
const EDITOR := preload("res://src/editor.gd")

var doc: MapDocument = null
var palette: ObjectPalette = null
var editor: Node = null


func before_each() -> void:
	GameDataRegistry.load_from(GameRoot.resolve())
	doc = MapDocument.create(Vector2i(96, 96), "Area Test")


func after_each() -> void:
	if palette != null:
		palette.free()
		palette = null
	if editor != null:
		editor.free()
		editor = null


# ── the format ──────────────────────────────────────────────────────────────

func test_a_region_is_the_union_of_every_entry_sharing_its_name() -> void:
	# ⚠️ **THE WHOLE REASON `areas` IS FLAT.** An L-shaped or split region needs no new shape in
	# the format, and `MapEdit._copied()` stays a one-level duplicate — a `{name, rects: [...]}`
	# record would have made that function's "no nested container to reach" claim false, silently.
	assert_true(doc.add_area(&"north_pass", Rect2i(4, 4, 6, 6)))
	assert_true(doc.add_area(&"north_pass", Rect2i(10, 4, 6, 6)))
	assert_true(doc.add_area(&"ford", Rect2i(40, 40, 3, 3)))

	assert_eq(doc.data.areas.size(), 3, "three rectangles")
	assert_eq(doc.area_names(), [&"north_pass", &"ford"] as Array[StringName],
			"two regions, in first-appearance order")
	assert_eq(doc.data.area_rects(&"north_pass").size(), 2)
	assert_eq(doc.data.area_rects(&"ford").size(), 1)


## ⚠️ **"NO SUCH REGION" AND "A REGION WITH NOTHING IN IT" ARE DIFFERENT ANSWERS, and this is
## the pair of functions that keeps them askable.** `ObjectiveSystem` returns its unmeasurable
## -1 for the first and a real 0 for the second, because **0 is a value that PASSES `== 0` and
## `<= n`** — so a scenario naming a misspelled region would announce victory on tick 1 if the
## two were conflated. Trap 3, arriving through a subject that is implemented.
func test_has_area_is_a_different_question_from_area_rects_being_empty() -> void:
	assert_false(doc.data.has_area(&"nowhere"))
	assert_true(doc.data.area_rects(&"nowhere").is_empty())
	doc.add_area(&"somewhere", Rect2i(1, 1, 2, 2))
	assert_true(doc.data.has_area(&"somewhere"))
	assert_false(doc.data.area_rects(&"somewhere").is_empty())


func test_a_region_needs_a_name_and_some_ground() -> void:
	assert_false(doc.add_area(&"", Rect2i(1, 1, 2, 2)), "nameless")
	assert_false(doc.add_area(&"   ", Rect2i(1, 1, 2, 2)), "whitespace is nameless")
	assert_false(doc.add_area(&"flat", Rect2i(1, 1, 0, 4)), "no width")
	assert_false(doc.add_area(&"flat", Rect2i(1, 1, 4, 0)), "no height")
	assert_true(doc.data.areas.is_empty(), "and none of them recorded anything")


## ⚠️ **THE BOUNDS CHECK IS THE TOOL'S AND NOT THE FORMAT'S, WHICH IS A DELIBERATE SPLIT.**
## `MapData.add_area()` accepts an off-map rect because a loaded file may carry a region hanging
## off the edge of a map somebody later shrank, and dropping it on load would silently change
## what a scenario counts. `MapDocument.add_area()` refuses it, because that is the layer with a
## person to tell. Same division `add_entity()` makes about a footprint.
func test_the_document_refuses_a_rectangle_that_runs_off_the_map() -> void:
	assert_false(doc.add_area(&"edge", Rect2i(94, 94, 6, 6)), "the far corner is off the map")
	assert_false(doc.add_area(&"edge", Rect2i(-2, 4, 6, 6)), "and so is the near one")
	assert_true(doc.data.areas.is_empty())
	# THE FORMAT ITSELF DOES NOT, and that is the half that keeps an opened map readable.
	assert_true(doc.data.add_area(&"edge", Rect2i(94, 94, 6, 6)),
			"MapData takes it, so a shrunk map does not silently lose its regions")


## The whole trailing-space argument in one assertion: an invisible character must not make two
## regions out of one, at either end. `ObjectiveDef._read_area` strips identically.
func test_a_name_is_stripped_so_a_trailing_space_is_not_a_second_region() -> void:
	assert_true(doc.add_area(&" the ford ", Rect2i(4, 4, 2, 2)))
	assert_true(doc.add_area(&"the ford", Rect2i(8, 8, 2, 2)))
	assert_eq(doc.area_names().size(), 1, "one region, not two: %s" % [doc.area_names()])
	assert_eq(doc.data.area_rects(&"the ford").size(), 2)


# ── the round trip ──────────────────────────────────────────────────────────

func test_regions_survive_to_dict_and_back() -> void:
	doc.add_area(&"north_pass", Rect2i(4, 5, 6, 7))
	doc.add_area(&"north_pass", Rect2i(20, 21, 2, 3))
	var back := MapData.from_dict(doc.data.to_dict())
	assert_eq(back.areas.size(), 2)
	assert_eq(back.area_rects(&"north_pass"), [Rect2i(4, 5, 6, 7), Rect2i(20, 21, 2, 3)]
			as Array[Rect2i])


## ⚠️ **ABSENT MEANS NO AREAS, WHICH IS THE ONE THING KEEPING THE SHIPPED CAMPAIGN LOADABLE.**
## Neither `FORMAT_VERSION` moved for 16.5 (PLAN.md §16 decision 7), so the five committed
## `scenarios/HowToPlay/*/map.json` files and everything inside the published `howtoplay` pack
## are read by this build unchanged — and they carry no `areas` key at all.
func test_a_sidecar_with_no_areas_key_reads_as_a_map_with_none() -> void:
	var old := {"w": 48, "h": 48, "entities": [], "starts": []}
	var back := MapData.from_dict(old)
	assert_true(back.areas.is_empty())
	assert_eq(back.area_names().size(), 0)
	assert_false(back.has_area(&"anything"))


## And the two constants really did stay put, asserted rather than described: a bump is a
## four-step checklist (decision 7) and the whole point of the optional field is to skip it.
func test_neither_format_version_moved_for_areas() -> void:
	assert_eq(MapData.FORMAT_VERSION, 1, "the wire form")
	assert_eq(MapFile.FORMAT_VERSION, 1, "the on-disk form")


## A nameless or empty region in a hand-edited file is dropped by the same rule that refuses one
## in the tool, rather than loaded as a region nothing can name.
func test_a_malformed_region_in_a_file_is_dropped_rather_than_loaded() -> void:
	var back := MapData.from_dict({"w": 48, "h": 48, "areas": [
		{"name": "", "x": 1, "y": 1, "w": 4, "h": 4},
		{"name": "flat", "x": 1, "y": 1, "w": 0, "h": 4},
		{"name": "good", "x": 2, "y": 3, "w": 4, "h": 5},
	]})
	assert_eq(back.areas.size(), 1, "%s" % [back.area_names()])
	assert_eq(back.area_rects(&"good"), [Rect2i(2, 3, 4, 5)] as Array[Rect2i])


# ── undo ────────────────────────────────────────────────────────────────────

func test_undo_takes_a_region_back_and_redo_puts_it_again() -> void:
	doc.add_area(&"ford", Rect2i(4, 4, 3, 3))
	assert_eq(doc.data.areas.size(), 1)
	assert_true(doc.undo().contains("ford"), "the step names the region")
	assert_true(doc.data.areas.is_empty(), "undo took it back")
	doc.redo()
	assert_eq(doc.data.areas.size(), 1)
	assert_eq(doc.data.area_rects(&"ford"), [Rect2i(4, 4, 3, 3)] as Array[Rect2i])


func test_undo_of_an_erased_rectangle_brings_that_one_back() -> void:
	doc.add_area(&"ford", Rect2i(4, 4, 3, 3))
	doc.add_area(&"ford", Rect2i(20, 20, 3, 3))
	assert_eq(doc.remove_area_at(Vector2i(5, 5)), 1)
	assert_eq(doc.data.areas.size(), 1, "the other rectangle stayed")
	doc.undo()
	assert_eq(doc.data.area_rects(&"ford").size(), 2)


## ⚠️ **A STEP THAT RECORDED AREAS AND NOT ENTITIES WOULD DELETE THE MAP ON REDO.** `MapEdit`
## gates all three snapshots on one `_lists` flag for exactly this reason, and this is the test
## that would notice a fourth list arriving with a flag of its own: an area act and an entity act
## joined into one stroke must both come back.
func test_a_stroke_holding_an_area_and_an_entity_undoes_both_together() -> void:
	doc.begin_stroke()
	doc.add_area(&"camp", Rect2i(4, 4, 4, 4))
	doc.add_entity(&"building.house", 1, Vector2i(40, 40))
	doc.end_stroke()
	assert_eq(doc.data.areas.size(), 1)
	assert_eq(doc.data.entities.size(), 1)

	doc.undo()
	assert_true(doc.data.areas.is_empty(), "the region went")
	assert_true(doc.data.entities.is_empty(), "and so did the house")
	doc.redo()
	assert_eq(doc.data.areas.size(), 1, "and both came back")
	assert_eq(doc.data.entities.size(), 1)


## A no-op is not a step — `MapEdit.changes_anything()`'s rule. An erase on ground no region
## covers is a real act with an invisible result, and a stack of them is a Ctrl+Z that appears
## not to work.
func test_an_erase_that_hit_no_region_is_not_a_step() -> void:
	doc.add_area(&"ford", Rect2i(4, 4, 3, 3))
	var depth := doc.history.depth()
	assert_eq(doc.remove_area_at(Vector2i(60, 60)), 0)
	assert_eq(doc.history.depth(), depth, "nothing was pushed")


# ── which rectangle is under the pointer ────────────────────────────────────

## **THE LAST MATCH WINS, WHICH IS THE ONE DRAWN ON TOP.** `MapCanvas` walks the list in order,
## so a later rectangle is painted over an earlier one and a picker returning the first would hand
## back the region underneath the one the author can see. Regions overlapping is NORMAL here
## rather than a fault — "the crossing" and "the north bank" genuinely share ground — which makes
## this matter more than it does for entities.
func test_the_topmost_rectangle_is_the_one_found() -> void:
	doc.add_area(&"under", Rect2i(4, 4, 10, 10))
	doc.add_area(&"over", Rect2i(6, 6, 4, 4))
	var at := doc.area_index_at(Vector2i(7, 7))
	assert_eq(String(doc.data.areas[at].get("name", &"")), "over")
	assert_eq(String(doc.data.areas[doc.area_index_at(Vector2i(5, 5))].get("name", &"")),
			"under", "and outside the overlap the lower one is found")
	assert_eq(doc.area_index_at(Vector2i(60, 60)), -1)


# ── the palette tab ─────────────────────────────────────────────────────────

func _a_palette() -> ObjectPalette:
	palette = ObjectPalette.new()
	palette.setup(IconAtlas.new())
	return palette


## ⚠️ **THE ONLY TAB WHOSE ROWS COME FROM THE MAP.** Pushed in with `set_area_names()` rather
## than read off a `MapDocument` the palette holds: a palette that could reach the document would
## be a second writer to it, and `MapDocument`'s header is emphatic that there is one funnel for
## every mutation.
func test_the_areas_tab_lists_the_documents_regions_and_nothing_from_the_roster() -> void:
	var p := _a_palette()
	p.set_category(ObjectPalette.Category.AREA)
	assert_true(p.listed_ids().is_empty(), "a fresh map has no regions")

	p.set_area_names([&"north_pass", &"ford"] as Array[StringName])
	assert_eq(p.listed_ids(), [&"north_pass", &"ford"] as Array[StringName])
	# AND THE LABEL IS THE AUTHOR'S OWN STRING, not a prettified id: the name an objective has to
	# match is the one in the field, so showing "North Pass" would send somebody to type the tidy
	# version into `scenario.json`.
	assert_eq(p._label_for(&"north_pass"), "north_pass")


## Owner and tint mean nothing to a region — `MapData`'s area record is `{name, rect}` and has no
## `player` key, so an Owner box here would be a promise the format cannot keep. The question an
## author actually asks ("whose things are in it?") belongs to the OBJECTIVE, not to the region.
func test_the_areas_tab_hides_the_controls_a_region_has_no_field_for() -> void:
	var p := _a_palette()
	p.set_category(ObjectPalette.Category.AREA)
	assert_false(p._owner_row.visible, "a region has no owner")
	assert_false(p._tint_row.visible, "and no colour")
	assert_false(p._size_row.visible, "and no size class")
	assert_true(p._area_row.visible, "what it has instead is a name")
	# AND IT PLACES NO ENTITY. A `selection()` here would be a `def_id` `add_entity()` cannot
	# resolve, which `MapGen.build_from()` would spawn as nothing at all.
	assert_true(p.selection().is_empty())


func test_the_name_field_is_the_selection() -> void:
	var p := _a_palette()
	p.set_category(ObjectPalette.Category.AREA)
	assert_eq(p.area_name(), &"", "nothing typed yet")
	p.set_area_name(&"ford")
	assert_eq(p.area_name(), &"ford")
	assert_eq(p._area_field.text, "ford", "and the control moved with the field")
	# PICKING A ROW FILLS THE FIELD, which is the whole interaction: a row is a shortcut for
	# typing a name the author has already used.
	p.set_area_names([&"north_pass"] as Array[StringName])
	p.pick(&"north_pass")
	assert_eq(p.area_name(), &"north_pass")


## ⚠️ **AN EMPTY AREAS TAB MUST NOT BLAME THE ROSTER.** Every other tab's emptiness really is
## the game project's; this one's is the healthy state of a fresh map, and "is the game project
## readable?" would send an author to check a config file over a map they have not drawn on.
func test_an_empty_areas_tab_says_to_draw_one_rather_than_blaming_the_roster() -> void:
	var p := _a_palette()
	p.set_category(ObjectPalette.Category.AREA)
	var said := p._count_text(0)
	assert_true(said.contains("no areas yet"), said)
	assert_false(said.contains("roster"), said)


## ⚠️ **`CATEGORIES[int(c)]` WAS THE OLD LOOKUP AND IT WAS POSITIONAL COUPLING NOTHING DECLARED.**
## `label_of()` matches on the id instead. 16.5 appended `AREA` to both the enum and the array and
## would have got away with the old form; the next row to insert one in the middle would have
## labelled every tab after it with its neighbour's word — which is `AIProfile.IDS`-against-
## `SimPlayer.AILevel` exactly, and `Tool.START`'s removal is the standing record of it biting.
func test_every_category_finds_its_own_label_by_id_and_not_by_position() -> void:
	for entry in ObjectPalette.CATEGORIES:
		assert_eq(ObjectPalette.label_of(entry["id"] as ObjectPalette.Category),
				str(entry["label"]).to_lower())


# ── the drag, driven through the real editor ────────────────────────────────

## An editor built and driven without a tree, `test_cursors._open_editor()`'s harness: `_ready()`
## is called by hand because `add_child` needs a tree this suite has not got.
func _an_editor() -> Node:
	editor = load("res://Editor.tscn").instantiate()
	editor._ready()
	editor.show_document(doc)
	return editor


## ⚠️ **A PRESS AND A RELEASE ON ONE TILE IS A 1x1 REGION, NOT AN EMPTY ONE.** Off-by-one on the
## size makes it empty, `MapData.add_area()` refuses an empty one, and a single click then does
## nothing at all while looking exactly like a save that failed.
func test_a_click_without_a_drag_authors_one_tile() -> void:
	var e := _an_editor()
	e._palette.set_category(ObjectPalette.Category.AREA)
	e._palette.set_area_name(&"dot")
	assert_eq(e._tool, EDITOR.Tool.AREA, "the tab arms the tool")

	doc.begin_stroke()
	e.apply_tool(Vector2i(10, 10))
	e._finish_area()
	doc.end_stroke()
	assert_eq(doc.data.area_rects(&"dot"), [Rect2i(10, 10, 1, 1)] as Array[Rect2i])


## Both directions, because a drag is not guaranteed to go down-and-right and a non-normalised
## rect has a negative size, which `add_area()` refuses — a legal gesture that does nothing.
func test_a_drag_normalises_whichever_way_it_goes() -> void:
	var e := _an_editor()
	e._palette.set_category(ObjectPalette.Category.AREA)
	e._palette.set_area_name(&"box")

	for pair in [[Vector2i(10, 10), Vector2i(14, 13)], [Vector2i(34, 33), Vector2i(30, 30)]]:
		doc.begin_stroke()
		e.apply_tool(pair[0])
		e.apply_tool(pair[1])
		e._finish_area()
		doc.end_stroke()
	assert_eq(doc.data.area_rects(&"box"),
			[Rect2i(10, 10, 5, 4), Rect2i(30, 30, 5, 4)] as Array[Rect2i])


## ⚠️ **THE DRAG WRITES ONCE, ON RELEASE.** Writing per sample would append a rectangle per
## mouse-move — dozens of one-tile regions all called the same thing, sealed into one undo step,
## so a single Ctrl+Z would take back a mess the author never asked to make.
func test_a_drag_writes_exactly_one_rectangle_however_many_samples_it_takes() -> void:
	var e := _an_editor()
	e._palette.set_category(ObjectPalette.Category.AREA)
	e._palette.set_area_name(&"long")

	doc.begin_stroke()
	for x in range(10, 30):
		e.apply_tool(Vector2i(x, 10))
		assert_true(doc.data.areas.is_empty(), "nothing is written mid-drag")
	e._finish_area()
	doc.end_stroke()
	assert_eq(doc.data.areas.size(), 1)
	assert_eq(doc.history.depth(), 1, "and it is one undo step")


## The likeliest first encounter with the feature: the tab arms the tool before anything has been
## typed (deliberately — there is no other door to it), so the refusal is on the drag and it has
## to name which half is missing.
func test_a_drag_with_no_name_says_so_rather_than_doing_nothing() -> void:
	var e := _an_editor()
	e._palette.set_category(ObjectPalette.Category.AREA)

	doc.begin_stroke()
	e.apply_tool(Vector2i(10, 10))
	e._finish_area()
	doc.end_stroke()
	assert_true(doc.data.areas.is_empty())
	assert_true(e._notice_label.text.contains("NEEDS A NAME"), e._notice_label.text)


func test_a_drag_off_the_map_is_refused_out_loud() -> void:
	var e := _an_editor()
	e._palette.set_category(ObjectPalette.Category.AREA)
	e._palette.set_area_name(&"edge")

	doc.begin_stroke()
	e.apply_tool(Vector2i(94, 94))
	# `MapCanvas` never reports a tile off the map, so this is reached by asking for one
	# directly -- which is what a future keyboard entry or a `dev/` script would do.
	e._area_last = Vector2i(120, 120)
	e._finish_area()
	doc.end_stroke()
	assert_true(doc.data.areas.is_empty())
	assert_true(e._notice_label.text.contains("WILL NOT FIT"), e._notice_label.text)


## ⚠️ **A TOOL CHANGE MID-DRAG ABANDONS THE ANCHOR.** `_finish_area()` is reached only while
## `Tool.AREA` is armed, so without this the next area drag would anchor on the tile the author
## pressed several gestures ago — and the preview rectangle would still be painted.
func test_changing_tool_mid_drag_abandons_the_half_drawn_region() -> void:
	var e := _an_editor()
	e._palette.set_category(ObjectPalette.Category.AREA)
	e._palette.set_area_name(&"abandoned")

	doc.begin_stroke()
	e.apply_tool(Vector2i(10, 10))
	assert_true(e._area_from.x >= 0, "the anchor is set")
	e.set_tool(EDITOR.Tool.PAINT)
	assert_eq(e._area_from, Vector2i(-1, -1), "and the tool change threw it away")
	assert_eq(e._canvas.pending_area, Rect2i(), "with the preview")
	doc.end_stroke()
	assert_true(doc.data.areas.is_empty())


# ── the eraser's precedence ─────────────────────────────────────────────────

## ⚠️ **A REGION IS ERASED LAST AND ONLY OVER GROUND THAT IS OTHERWISE EMPTY.** A region can
## cover a quarter of the map at a 10% fill, so it is by far the easiest thing here to forget is
## under the pointer — if it went first, every erase inside a big region would delete the region
## instead of the tree the author was aiming at. That is silent destruction of the thing they
## cannot see, and `remove_start()`'s ⛔ note is this tool's record of what it costs.
func test_erasing_inside_a_region_takes_the_entity_and_leaves_the_region() -> void:
	var e := _an_editor()
	doc.add_area(&"camp", Rect2i(30, 30, 20, 20))
	doc.add_entity(&"res.tree", 0, Vector2i(35, 35))
	e.set_tool(EDITOR.Tool.ERASE)

	e.apply_tool(Vector2i(35, 35))
	assert_true(doc.data.entities.is_empty(), "the tree went")
	assert_eq(doc.data.areas.size(), 1, "and the region did not")


func test_erasing_empty_ground_inside_a_region_takes_the_rectangle_and_says_so() -> void:
	var e := _an_editor()
	doc.add_area(&"camp", Rect2i(30, 30, 20, 20))
	e.set_tool(EDITOR.Tool.ERASE)

	e.apply_tool(Vector2i(35, 35))
	assert_true(doc.data.areas.is_empty())
	assert_true(e._notice_label.text.contains("camp"), e._notice_label.text)


## The status line names all three things the eraser can take. It named two for an hour after the
## `Clear start` button was deleted and sent people hunting the toolbar for it, which is why this
## is asserted rather than left to the eye.
func test_the_status_line_says_the_eraser_can_take_a_region() -> void:
	var e := _an_editor()
	e.set_tool(EDITOR.Tool.ERASE)
	e._refresh_status()
	assert_true(e._status.text.contains("area"), e._status.text)


# ── the status line's own count ─────────────────────────────────────────────

## ⚠️ **TWO NUMBERS, BECAUSE "3 AREAS" IS AMBIGUOUS BETWEEN THREE REGIONS AND THREE RECTANGLES OF
## ONE** — and which of those an author has just made is precisely the thing the screen cannot
## tell them: two magenta boxes with the same label look exactly like two regions sharing a name.
func test_the_status_line_counts_regions_and_rectangles_apart() -> void:
	var e := _an_editor()
	e._refresh_status()
	assert_false(e._status.text.contains("area"), "nothing said on a map with none")

	doc.add_area(&"ford", Rect2i(4, 4, 2, 2))
	doc.add_area(&"ford", Rect2i(8, 8, 2, 2))
	doc.add_area(&"pass", Rect2i(20, 20, 2, 2))
	e._refresh_status()
	assert_true(e._status.text.contains("2 areas in 3 rects"), e._status.text)


## The palette's rows are fed from `_refresh_status()`, which is the one place every mutation
## path already ends up — the alternative is a push per call site and the tenth one gets
## forgotten (`_refresh_undo()`'s argument).
func test_the_palette_tab_follows_the_document_without_being_told_twice() -> void:
	var e := _an_editor()
	e._palette.set_category(ObjectPalette.Category.AREA)
	e._palette.set_area_name(&"ford")

	doc.begin_stroke()
	e.apply_tool(Vector2i(10, 10))
	e._finish_area()
	doc.end_stroke()
	assert_eq(e._palette.listed_ids(), [&"ford"] as Array[StringName],
			"the row appeared with no separate refresh call")

	e.undo()
	assert_true(e._palette.listed_ids().is_empty(), "and went again on undo")
