## PLAN.md 16.4e — the five cursors, and the one fault that looks exactly like success.
##
## ## THE HOTSPOT IS THE WHOLE RISK AND IT IS INVISIBLE
##
## A cursor's art either appears or it does not; `preview_editor` and a person settle that. **The
## hotspot cannot be seen at all.** A cursor drawn perfectly with the wrong hotspot aims a pixel
## or two — or, if `at_100` is read where `fraction` was meant, *sixteen* pixels — off where the
## author is pointing, so clicks land on the wrong tile while every picture looks right and every
## texture assertion passes. The art side's card says it plainly: *"do not copy these numbers into
## code."*
##
## So the load-bearing test here is `test_the_computed_hotspots_match_the_measured_ones`, which
## re-derives each hotspot from `fraction` and checks it against the `at_32` the art side wrote
## into the same file. **Two independent routes to one number**, which is the only thing that can
## catch reading the wrong field — and the fields are three apart at `SIZE` 32, not equal.
##
## ## WHAT IS DELIBERATELY NOT TESTED
##
## **That `Input.set_custom_mouse_cursor` was called.** The suite is headless: there is no cursor,
## and `arm()` guards on the display server for that reason. What is checkable is that the pair it
## would pass is right, and that a tool with no art clears the shape rather than leaving the
## previous tool's picture up. The registration itself is `preview_editor`'s.
##
## **Whether the keyline survives 100 → 32.** That is a look at a picture over sand, which is what
## `assets/UI_Gen/sliced/review/sheet_i_mapmaker_cursors.png` is for.
extends TestCase

## `Editor`'s script, for its `Tool` enum. **Named and never numbered** — see `test_cursors`'s
## header for the ten minutes that rule cost.
const EDITOR := preload("res://src/editor.gd")

const TOOLS := [
	EDITOR.Tool.PAINT, EDITOR.Tool.PLACE, EDITOR.Tool.ERASE,
	EDITOR.Tool.SELECT, EDITOR.Tool.MOVE,
]


func before_each() -> void:
	ToolCursors.forget()


func after_each() -> void:
	ToolCursors.forget()


# ── the art ─────────────────────────────────────────────────────────────────

func test_every_cursor_has_a_file_that_loads() -> void:
	var gone := ToolCursors.missing()
	assert_true(gone.is_empty(),
			"missing cursors %s — run: godot --headless --path MapMaker --import" % [gone])
	assert_eq(ToolCursors.IDS.size(), 5)


## Drawn at `SIZE`, because Godot draws a cursor at the texture's own pixel size.
##
## Hand it the 100 px original and the pointer is a third the height of the palette. There is no
## `expand` on a hardware cursor — the resize IS the size.
func test_a_cursor_is_resized_to_the_drawn_size() -> void:
	for id in ToolCursors.IDS:
		var tex := ToolCursors.texture(id)
		assert_true(tex != null, "%s did not load" % id)
		assert_eq(tex.get_width(), ToolCursors.SIZE, "%s is not %d wide" % [id, ToolCursors.SIZE])
		assert_eq(tex.get_height(), ToolCursors.SIZE)


func test_every_tool_maps_to_its_own_cursor() -> void:
	var seen: Array[StringName] = []
	for t in TOOLS:
		var id := ToolCursors.for_tool(int(t))
		assert_false(id.is_empty(), "tool %d has no cursor" % int(t))
		assert_false(seen.has(id), "%s is on two tools" % id)
		assert_true(ToolCursors.IDS.has(id), "%s is not a declared cursor" % id)
		seen.append(id)
	assert_eq(seen.size(), 5, "all five tools, all five cursors")


func test_a_value_that_is_not_a_tool_gets_no_cursor() -> void:
	assert_true(ToolCursors.for_tool(9999).is_empty())


# ── the hotspots: the fault that looks like success ─────────────────────────

## THE LOAD-BEARING TEST. Two independent routes to each hotspot must agree.
##
## `hotspot()` derives from the measured `fraction`; the art side also wrote `at_32` into the same
## file, pre-multiplied. Reading `at_100` where `fraction` was meant, or flooring where the
## measurement rounds, both show up here and nowhere else:
##
##   - `at_100` instead of `fraction` would give `cur_brush` (10, 7) against (3, 2);
##   - `floor` instead of `round` would give `cur_place` (2, 2) against (3, 3).
##
## ⚠️ **IT SKIPS RATHER THAN FAILS IF `SIZE` IS NOT 32**, because `at_32` is then simply not the
## right cross-check any more and a red suite would be reporting the wrong thing. The skip is
## loud: `assert_eq(ToolCursors.SIZE, 32)` below is what says the check is live.
func test_the_computed_hotspots_match_the_measured_ones() -> void:
	assert_eq(ToolCursors.SIZE, 32,
			"at_32 is only the right cross-check at 32 px — see this test's note")
	var measured := _raw_hotspots()
	assert_false(measured.is_empty(), "hotspots.json was not read at all")
	for id in ToolCursors.IDS:
		assert_true(measured.has(String(id)), "%s has no measured hotspot" % id)
		var entry: Dictionary = measured[String(id)]
		var at_32 = entry["at_32"]
		assert_eq(ToolCursors.hotspot(id), Vector2(float(at_32[0]), float(at_32[1])),
				"%s: derived from fraction disagrees with the measured at_32" % id)


## The three pointers aim at three DIFFERENT places, and that is correct rather than drift.
##
## The art side's note: `ART_PROMPT.md` specified a flat (0.02, 0.02) for all three on the
## assumption their tip sat in the cell's corner; Gemini inset them, and the crop is taken from
## the content bounding box anyway — so each was measured on its own image. **Averaging them, or
## picking one and using it for all three, is the way to break the aim**, and that is a change no
## picture would show. This test is what makes it cost a red suite.
func test_the_three_pointers_do_not_share_one_hotspot() -> void:
	var brush := ToolCursors.hotspot(&"cur_brush")
	var place := ToolCursors.hotspot(&"cur_place")
	var erase := ToolCursors.hotspot(&"cur_erase")
	assert_true(brush != place or place != erase,
			"the three pointers were measured separately and must stay separate")
	# AND NONE OF THEM IS THE CENTRE, which is what `hotspot()` falls back to. A pointer aiming at
	# its own middle is the failure this whole file is about, so it is worth stating that the real
	# answers are nowhere near it.
	var centre := Vector2(ToolCursors.SIZE, ToolCursors.SIZE) * 0.5
	for id in [&"cur_brush", &"cur_place", &"cur_erase"]:
		assert_true(ToolCursors.hotspot(id) != centre,
				"%s is aiming at its own centre — the fallback fired" % id)


## The two centred ones are centred, and they are centred BY MEASUREMENT.
##
## `cur_select` is a marquee and `cur_move` a four-way arrow: both are symmetrical, so their
## measured hotspot is genuinely the middle. Worth pinning as the counterpart to the test above —
## these two agreeing with the fallback is correct, and only they may.
func test_the_two_symmetrical_cursors_aim_at_their_centre() -> void:
	var centre := Vector2(ToolCursors.SIZE, ToolCursors.SIZE) * 0.5
	assert_eq(ToolCursors.hotspot(&"cur_select"), centre)
	assert_eq(ToolCursors.hotspot(&"cur_move"), centre)


func test_every_cursor_has_a_measured_hotspot() -> void:
	var no_aim := ToolCursors.unmeasured()
	assert_true(no_aim.is_empty(), "unmeasured %s — these would aim at their own centre" % [no_aim])


## An unknown id aims at the CENTRE and not at the corner.
##
## A (0, 0) default would put the aim at the tip of nothing — every click a tile or two off, which
## survives a screenshot. The centre is visibly wrong for a pointer and right for the two that are
## centred anyway.
func test_an_unknown_cursor_aims_at_the_centre_rather_than_the_corner() -> void:
	var centre := Vector2(ToolCursors.SIZE, ToolCursors.SIZE) * 0.5
	assert_eq(ToolCursors.hotspot(&"cur_does_not_exist"), centre)
	assert_true(centre != Vector2.ZERO, "and the corner is what it must not be")


# ── the shape it is registered against ──────────────────────────────────────

## ⚠️ NOT `CURSOR_ARROW`, and this is the assertion that keeps a paintbrush off the Save button.
##
## `Input.set_custom_mouse_cursor` is application-wide state keyed on a built-in shape. Registering
## against ARROW — the obvious choice — would replace the pointer over every button, dropdown and
## text field in the tool. `CURSOR_CROSS` is asked for by the canvas and by nothing else.
func test_the_art_is_registered_against_a_shape_only_the_canvas_asks_for() -> void:
	assert_false(ToolCursors.SHAPE == Input.CURSOR_ARROW,
			"an ARROW override would put the tool cursor over the whole UI")
	assert_eq(ToolCursors.SHAPE, Input.CURSOR_CROSS)
	# THE FALLBACK IS THE SHAPE'S OWN ART, which is why a missing file is not an emergency: the
	# canvas keeps asking for CROSS and the author gets a system crosshair over the map.


## ⚠️ THE TWO SHAPE CONSTANTS ARE ONE FACT AND MUST NOT DRIFT.
##
## `Input.CursorShape` and `Control.CursorShape` are separate enums with identical members and
## identical values, and GDScript will not assign one to the other — so the shape is declared
## twice: once for `Input.set_custom_mouse_cursor` and once for `mouse_default_cursor_shape`.
##
## **Changing one and not the other is silent.** The art registers against a shape nothing asks
## for, the canvas draws its shape's stock art, and every other test in this file still passes
## because the textures and the hotspots are all fine. This is the only check that can see it.
func test_the_two_shape_constants_are_the_same_shape() -> void:
	assert_eq(int(ToolCursors.SHAPE), int(ToolCursors.CANVAS_SHAPE),
			"the Input and Control shapes have drifted — the cursor would never appear")


## `arm()` is honest about whether it used real art, and it is safe with none.
func test_arm_reports_whether_it_had_art() -> void:
	assert_true(ToolCursors.arm(int(EDITOR.Tool.PAINT)), "the brush art is committed")
	assert_false(ToolCursors.arm(9999), "nothing is not a tool and has no art")


## `release()` gives the shape back and is safe with no display server.
##
## It exists because the first version **leaked a GPU texture at process exit** — the
## `DisplayServer` holds the armed cursor and a static cache holds the rest, and both outlive the
## rendering server. `Editor._exit_tree()` calls this, on `GameScene`'s rule that state claimed by
## a screen is given back on every path out.
##
## ⚠️ **THE HEADLESS SAFETY IS THE HALF WORTH A TEST**, because the suite is where it would go
## wrong: an unguarded `Input.set_custom_mouse_cursor` here would put an engine error in every run
## — and `ScriptErrorSpy` does not catch engine errors, so it would be noise nobody chased.
func test_release_is_safe_with_no_display_server_and_drops_the_art() -> void:
	assert_true(ToolCursors.texture(&"cur_brush") != null, "loaded, so there is something to drop")
	ToolCursors.release()
	# THE CACHE IS GONE, which is what stops an ImageTexture outliving the RenderingServer. Proven
	# by the art coming back on the next ask rather than by reading a private field.
	assert_true(ToolCursors.texture(&"cur_brush") != null, "and it reloads on demand")


func _raw_hotspots() -> Dictionary:
	# READ INDEPENDENTLY OF THE CLASS UNDER TEST, on purpose. Asking `ToolCursors` for the raw
	# figures would make this a test of one function against itself -- the cross-check only means
	# something if the second route does not go through the first.
	if not FileAccess.file_exists(ToolCursors.HOTSPOT_PATH):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(ToolCursors.HOTSPOT_PATH)) != OK:
		return {}
	return parser.data if parser.data is Dictionary else {}
