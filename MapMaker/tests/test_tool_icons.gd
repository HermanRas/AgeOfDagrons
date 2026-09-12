## PLAN.md 16.4d — the committed glyphs (13 from the art side's cut, plus 16.6's), and the four
## ways wiring them can go wrong quietly.
##
## ## WHY THIS FILE EXISTS AT ALL: `ToolIcons` HAD NO TESTS AND THE ART CHANGED UNDER IT
##
## The drawn version was untested for its whole life, and that was defensible — a glyph made of
## `Image.set_pixel` calls either draws or raises an engine error per pixel, and `preview_editor`
## photographs the row. **Loading files is a different risk profile**, and three of the four
## faults below report success:
##
##   1. **a missing file or a skipped `--import`.** `.godot/` is gitignored, so a fresh clone has
##      the PNGs and none of the `.ctex` they import to. The button then shows its word, which is
##      the *designed* fallback and therefore looks deliberate. Only a count can tell.
##   2. **a theme tinting full-colour art.** A `Button` multiplies its icon by
##      `icon_normal_color`. The glyphs this replaced were monochrome near-white *because* one ink
##      survives any tint; these are gold, a keep, a plume and a grass tile. 16.4f is about to
##      give this tool a theme, and a recoloured icon is not something any other check looks at.
##   3. **an icon on the wrong tool.** `Tool.START` was removed on 2026-09-08 and renumbered every
##      member after it, and `test_cursors` was driving tools by literal at the time — so it went
##      on passing while exercising the wrong tools. `for_tool()` matches the enum for that
##      reason; this asserts it *through* the enum, never against a number.
##   4. **a fifth palette tab with no picture.** 16.5 adds Areas as one entry in `CATEGORIES`, and
##      `cat_areas` is already cut for it. A row without an `icon` key would be a blank tab.
##
## ## WHAT IT DELIBERATELY DOES NOT CHECK
##
## **Whether the pictures look right.** That is `preview_editor`'s and a person's — §5's rule.
## What is checkable here is that a texture arrived, at the size asked for, on the right control,
## with no tint. A test asserting pixels would be asserting Gemini's brush strokes.
extends TestCase

## `Editor`'s script, for its `Tool` enum — `Editor.tscn`'s root has no `class_name`. **Named and
## never numbered**, for the reason in the header.
const EDITOR := preload("res://src/editor.gd")


func before_each() -> void:
	# THE CACHE IS STATIC AND THEREFORE SHARED ACROSS TESTS IN ONE PROCESS. Cleared so a test
	# that asserts a load actually performs one, rather than reading whatever ran first.
	ToolIcons.forget()


func after_each() -> void:
	ToolIcons.forget()


# ── the files are there ─────────────────────────────────────────────────────

## The load-bearing one: every declared id resolves on this machine.
##
## ⚠️ **THIS IS THE TEST THAT FAILS ON A CLEAN CLONE THAT SKIPPED `--import`**, and that is what it
## is for. The message names the command, because the symptom otherwise is a toolbar of words that
## looks like a deliberate design.
func test_every_declared_glyph_has_a_file_that_loads() -> void:
	var gone := ToolIcons.missing()
	assert_true(gone.is_empty(),
			"missing glyphs %s — run: godot --headless --path MapMaker --import" % [gone])
	# ⚠️ **FOURTEEN, AND THE FOURTEENTH IS NOT FROM THE ART SIDE'S CUT.** Thirteen were cut and
	# committed for 16.4d; 16.6 added `lobby_victory`, which the owner picked out of the GAME's
	# icon set by name (2026-09-12) and which was copied into this project's tree beside them.
	# **The count is asserted rather than the list** so that adding an id without adding a file
	# fails on the line above rather than here.
	assert_eq(ToolIcons.IDS.size(), 14, "thirteen cut for 16.4d, plus 16.6's conditions glyph")
	assert_true(ToolIcons.IDS.has(ToolIcons.CONDITIONS), "%s" % [ToolIcons.IDS])


## Drawn at `SIZE`, square, and not at the source's 100 px.
##
## A `Button` draws its `icon` at the texture's own size unless `expand_icon` is set, so the
## resize in `_load()` IS the layout: hand it the 100 px original and every toolbar row becomes a
## hundred pixels tall. That is the one failure here that would be obvious on screen, and it is
## cheap to pin.
func test_a_glyph_is_resized_to_the_drawn_size() -> void:
	var tex := ToolIcons.texture(&"mm_brush")
	assert_true(tex != null)
	assert_eq(tex.get_width(), ToolIcons.SIZE)
	assert_eq(tex.get_height(), ToolIcons.SIZE)
	# THE SOURCE IS BIGGER, which is what makes the resize meaningful rather than a no-op. If the
	# art side ever cuts at 24 this assertion is the one that says the filter stopped mattering.
	assert_true(ToolIcons.SIZE < 100, "the art is authored at 100 px and reduced")


## 24 and not 16, and the reason is the art rather than the layout.
##
## The old 16 matched the label's font size deliberately. These carry a bevel, a gradient and a
## contact shadow, all sub-pixel at 16. **Asserted as an ordering and not as the number** — §6's
## rule about balance figures in assertions — so a later 28 or 32 is not a red suite.
func test_the_drawn_size_is_large_enough_for_a_bevel_to_read() -> void:
	assert_true(ToolIcons.SIZE >= 24,
			"below 24 the bevel and the contact shadow are sub-pixel and read as mud")


func test_an_unknown_id_is_null_rather_than_an_error() -> void:
	assert_eq(ToolIcons.texture(&"mm_does_not_exist"), null)
	# AND IT IS REMEMBERED AS NULL, so a palette redrawing on every keystroke does not retry a
	# missing file — and does not push a warning per redraw either.
	assert_eq(ToolIcons.texture(&"mm_does_not_exist"), null, "the miss is cached, not retried")


func test_the_same_id_hands_back_the_same_texture() -> void:
	assert_eq(ToolIcons.texture(&"mm_undo"), ToolIcons.texture(&"mm_undo"),
			"cached, so a toolbar redraw does not re-decode and re-filter every PNG")


# ── the right glyph on the right tool ───────────────────────────────────────

## Each tool gets its own picture, and no two tools share one.
##
## ⚠️ **THE DISTINCTNESS IS THE HALF THAT MATTERS.** A `match` whose arms are all present but two
## of which name the same id is a toolbar where Erase and Move look identical — every assertion
## about non-null would pass. Same shape as `FACING_FOR_AXIS`'s two entries being swappable.
func test_every_tool_has_its_own_glyph() -> void:
	var seen: Array = []
	for t in [EDITOR.Tool.PAINT, EDITOR.Tool.PLACE, EDITOR.Tool.ERASE,
			EDITOR.Tool.SELECT, EDITOR.Tool.MOVE]:
		var tex := ToolIcons.for_tool(int(t))
		assert_true(tex != null, "tool %d has no glyph" % int(t))
		assert_false(seen.has(tex), "two tools share one picture")
		seen.append(tex)
	assert_eq(seen.size(), 5)


## PLACE has one NOW, and that is a reversal worth pinning.
##
## The drawn version returned null for it on the argument that *"the palette's own tile is the
## picture of what a place-click will do"*. The owner asked for a glyph anyway (16.4d). If this
## ever fails, somebody has restored the old reasoning without reading the card.
func test_place_has_a_glyph_because_the_owner_asked_for_one() -> void:
	assert_true(ToolIcons.for_tool(int(EDITOR.Tool.PLACE)) != null)


func test_a_value_that_is_not_a_tool_gets_no_glyph() -> void:
	assert_eq(ToolIcons.for_tool(9999), null)


# ── the tint ────────────────────────────────────────────────────────────────

## `apply()` writes the three overrides that stop a theme recolouring gold art.
##
## Fault 2 in the header. Asserted on the OVERRIDE rather than on a rendered pixel, because the
## tool has no theme yet — there is nothing to be tinted BY today, which is exactly why this would
## otherwise land untested and break on the day 16.4f arrives.
func test_apply_stops_a_theme_tinting_the_art() -> void:
	var b := Button.new()
	ToolIcons.apply(b, ToolIcons.texture(&"mm_brush"))
	assert_true(b.icon != null)
	for entry in ["icon_normal_color", "icon_pressed_color", "icon_hover_color"]:
		assert_true(b.has_theme_color_override(entry), "%s is not overridden" % entry)
		assert_eq(b.get_theme_color(entry), Color.WHITE, "%s is not opaque white" % entry)
	# ⚠️ **AND `icon_disabled_color` IS NOT SET, DELIBERATELY.** Undo and Redo spend most of their
	# life disabled and greying the picture with the word is right there. Pinned so a later
	# "set all four for consistency" tidy-up has to read the reason first.
	assert_false(b.has_theme_color_override("icon_disabled_color"),
			"greying a disabled button's icon is correct — see ToolIcons.apply")
	b.free()


## A null texture leaves the button alone rather than blanking its word.
##
## There is no drawn fallback on purpose (§5: the second rendering never gets looked at), so the
## word IS the fallback — and assigning a null icon plus a tint override would leave a button
## carrying overrides for a picture it has not got.
func test_apply_leaves_a_button_untouched_when_there_is_no_picture() -> void:
	var b := Button.new()
	b.text = "Brush"
	ToolIcons.apply(b, null)
	assert_eq(b.icon, null)
	assert_eq(b.text, "Brush", "the word is the fallback")
	assert_false(b.has_theme_color_override("icon_normal_color"))
	b.free()


# ── the palette's tabs ──────────────────────────────────────────────────────

## Every category row names an icon, and every named icon exists.
##
## Fault 4 in the header. This is the assertion that makes 16.5's *"one entry in `CATEGORIES`"*
## promise checkable: add the Areas row without an `icon` key and this fails, rather than shipping
## a blank fifth tab.
func test_every_category_names_a_glyph_that_exists() -> void:
	for entry in ObjectPalette.CATEGORIES:
		assert_true(entry.has("icon"), "category %s names no icon" % entry.get("label"))
		var id: StringName = entry["icon"]
		assert_true(ToolIcons.texture(id) != null,
				"category %s wants %s and it did not load" % [entry.get("label"), id])
		assert_true(ToolIcons.IDS.has(id), "%s is not in ToolIcons.IDS" % id)


## No two tabs share a picture, for `test_every_tool_has_its_own_glyph`'s reason.
func test_no_two_categories_share_a_glyph() -> void:
	var seen: Array[StringName] = []
	for entry in ObjectPalette.CATEGORIES:
		var id: StringName = entry["icon"]
		assert_false(seen.has(id), "%s is on two tabs" % id)
		seen.append(id)


## The spare is inventoried and wired to nothing.
##
## The art side cut two buildings; the house is the Buildings tab because a dwelling is what that
## word means, and the keep is kept because a fortification glyph in the same style cannot be
## re-rolled identically. **Asserted as unused** so that if 16.5 reaches for it, it does so
## knowingly — the alternative is a committed file nobody remembers is there.
func test_the_spare_keep_glyph_is_loadable_and_unused() -> void:
	assert_true(ToolIcons.texture(&"cat_buildings_keep") != null, "it is committed")
	for entry in ObjectPalette.CATEGORIES:
		assert_false(entry["icon"] == &"cat_buildings_keep", "the spare is on a tab")
