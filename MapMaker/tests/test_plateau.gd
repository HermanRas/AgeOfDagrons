## The plateau tool: a drag that raises high ground and lays the cliff ring around it (#97).
##
## ## WHAT A HEADLESS TEST CAN SEE HERE, AND IT IS NOT WHETHER THE CLIFF LOOKS RIGHT
##
## Whether the ring READS as a height boundary is a picture, and `preview_cliff_variants` plus
## the owner's eye are what settle it. The rules themselves are the game's — `CliffPlan`, a
## verbatim `format/` copy with its own eleven tests on that side, so nothing here re-asserts
## which piece goes where. **What this file guards is everything the TOOL could get wrong
## around them:**
##
##   - **all of it or none of it.** A plateau shares tiles on purpose, so it cannot go through
##     `add_entity()` one piece at a time. That means the refusal path is hand-written, and a
##     half-applied plateau is the one outcome with no honest report — the author sees a ring
##     with a gap and cannot tell a refusal from a bug in the rules.
##   - **undo.** Forty entities and a terrain fill in ONE step. A step that recorded the
##     entities and not the terrain would, on undo, leave the grass behind with no cliff on it.
##   - **the overlap exception is the game's and not a second one.** Two cliffs may share a
##     tile; a cliff may not land on a town centre.
##   - **the run length reaches the author.** A cliff run takes ONE rung of the ladder, so an
##     8-tile edge is eight 1-tile pieces — the same rock stamped every 64 px. Nothing on
##     screen says so and the fix is to resize by a tile, so the notice has to carry it.
extends TestCase

const EDITOR := preload("res://src/editor.gd")

var doc: MapDocument = null


func before_each() -> void:
	GameDataRegistry.load_from(GameRoot.resolve())
	doc = MapDocument.create(Vector2i(64, 64), "Plateau Test")


func _cliffs() -> int:
	var n := 0
	for e in doc.data.entities:
		if MapValidator.is_cliff(e):
			n += 1
	return n


# ── the write ───────────────────────────────────────────────────────────────


func test_a_plateau_raises_its_ground_and_rings_it_with_cliff() -> void:
	var result := doc.add_plateau(Rect2i(20, 20, 9, 9))
	assert_true(bool(result["ok"]), "the gesture landed: %s" % result["reason"])
	assert_true(int(result["pieces"]) > 0, "pieces were laid")
	assert_eq(_cliffs(), int(result["pieces"]), "and the count it reports is what is on the map")
	assert_eq(doc.data.terrain_at(Vector2i(24, 24)), SimMap.Terrain.GRASS,
			"the middle is high ground")
	assert_true(doc.dirty, "and the map now needs saving")


## ⛔ THE WHOLE GESTURE IS ONE UNDO STEP, TERRAIN AND ENTITIES TOGETHER. Recording the entities
## without the terrain would undo to grass with no cliff on it -- high ground that is not high,
## which reads as the tool half-working rather than as a bug.
func test_undo_takes_back_the_ring_and_the_ground_together() -> void:
	var before_terrain := doc.data.terrain_at(Vector2i(24, 24))
	var before_entities := doc.data.entities.size()

	doc.begin_stroke()
	doc.add_plateau(Rect2i(20, 20, 9, 9))
	doc.end_stroke()
	assert_true(_cliffs() > 0, "the fixture actually built something to undo")

	# `undo()` hands back WHAT it undid, not whether it did: "" is the empty stack. Asserting it
	# is non-empty says a step was really taken, where a bool would also pass on a no-op.
	assert_false(doc.undo().is_empty(), "there was a step to undo")
	assert_eq(doc.data.entities.size(), before_entities, "every piece went back")
	assert_eq(doc.data.terrain_at(Vector2i(24, 24)), before_terrain, "and so did the ground")


# ── the refusals ────────────────────────────────────────────────────────────


func test_a_plateau_that_runs_off_the_map_is_refused_whole() -> void:
	var before := doc.data.entities.size()
	var result := doc.add_plateau(Rect2i(60, 60, 9, 9))
	assert_false(bool(result["ok"]), "it will not fit")
	assert_false(String(result["reason"]).is_empty(), "and it says why")
	assert_eq(doc.data.entities.size(), before,
			"nothing at all was written -- a half plateau is the one outcome with no report")


## ⚠️ **THE EXCEPTION IS `MapValidator.is_cliff`'s AND NOT A SECOND OPINION.** A cliff may share
## a tile with a cliff -- the ring's own corners rely on it -- and with nothing else.
func test_a_plateau_will_not_be_dropped_over_a_building() -> void:
	assert_true(doc.add_entity(&"building.town_center", 1, Vector2i(22, 22)),
			"the fixture's building went down")
	var before := doc.data.entities.size()
	var result := doc.add_plateau(Rect2i(20, 20, 9, 9))
	assert_false(bool(result["ok"]), "the town centre is in the way")
	assert_eq(doc.data.entities.size(), before, "and the map is untouched")


## The other half of that exception: the ring's own shared tiles must NOT read as a collision,
## or the tool would refuse every plateau it was asked to build.
func test_the_rings_own_shared_tiles_are_not_treated_as_a_collision() -> void:
	var result := doc.add_plateau(Rect2i(20, 20, 9, 9))
	assert_true(bool(result["ok"]),
			"a plateau's corners share tiles by design and that is not an overlap")

	# A SECOND plateau, well clear of the first, still lands -- so the exception is about what
	# is on the tile and not about the map having any cliff on it at all.
	assert_true(bool(doc.add_plateau(Rect2i(40, 40, 9, 9))["ok"]), "and a second one is fine")


# ── what the author is told ─────────────────────────────────────────────────


## ⛔ THE RUN LENGTH IS THE ONE THING AN AUTHOR CANNOT SEE. A 9-tile edge is one long piece; an
## 8-tile edge is eight fillers showing the same 2 m of rock. `runs_of` is reported so the
## editor can say which happened and what to change.
func test_the_result_reports_the_rung_each_run_was_laid_on() -> void:
	var good := doc.add_plateau(Rect2i(20, 20, 9, 9))
	var stamped := 0
	for run in good["runs"] as Array:
		if int(run["piece"]) == 1 and int(run["span"]) > 1:
			stamped += 1
	assert_eq(stamped, 0, "a 9x9 plateau divides cleanly, so no edge falls to fillers")

	var awkward := doc.add_plateau(Rect2i(40, 40, 8, 8))
	assert_true(bool(awkward["ok"]), "an 8x8 is still a legal plateau")
	var fillers := 0
	for run in awkward["runs"] as Array:
		if int(run["piece"]) == 1 and int(run["span"]) > 1:
			fillers += 1
	assert_true(fillers > 0,
			"an 8-tile edge has no rung, and the result says so rather than hiding it")


# ── the tool is reachable ───────────────────────────────────────────────────


## ⚠️ **NAMED AND NEVER NUMBERED**, `test_cursors`' scar: `Tool.START`'s removal renumbered every
## member after it and tests driving tools by literal went on passing while exercising the wrong
## ones. `Tool.PLATEAU` is the seventh member and the sixth time that class of value has moved.
func test_the_plateau_tool_exists_and_is_its_own_member() -> void:
	assert_true(EDITOR.Tool.has("PLATEAU"), "the enum carries it")
	assert_true(int(EDITOR.Tool.PLATEAU) != int(EDITOR.Tool.AREA),
			"it is not an alias of the region tool it sits beside")


## It shares AREA's rectangle gesture, so it must share AREA's cursor answer too: no custom
## cursor, which is what makes the canvas fall back to the system crosshair every editor uses
## for dragging out a rectangle.
func test_the_plateau_tool_drags_with_the_crosshair_like_the_region_tool() -> void:
	assert_eq(ToolCursors.for_tool(int(EDITOR.Tool.PLATEAU)),
			ToolCursors.for_tool(int(EDITOR.Tool.AREA)),
			"the same gesture gets the same cursor")
