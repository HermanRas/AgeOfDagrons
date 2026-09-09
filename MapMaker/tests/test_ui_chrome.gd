## PLAN.md 16.4f — the shared plate, and the width it quietly costs.
##
## ## THE ONE FAULT HERE THAT NO SCREENSHOT WOULD HAVE CAUGHT IN TIME
##
## The `panel_hud` plate adds 12 px of moulding to each side of every panel, and content has to
## clear it. `ObjectPalette.PANEL_WIDTH` was **measured** at 330 as three 96 px tiles plus two
## separations plus a scrollbar — so the moulding took the inner width from 314 to 290 and put a
## grid needing 296 **six pixels over**. `_grid.columns` is a fixed 3 and the container's
## horizontal scrolling is DISABLED, so the third column would have been **clipped rather than
## wrapped**: two and a half tiles per row, and nothing in the suite counts pixels.
##
## That is the same shape as §6's stretch-ratio row — *"a stretch ratio only divides what is left
## after every minimum is honoured"* — and the lesson it records is that a panel's width and its
## border are one sum. So `PANEL_WIDTH` is now derived from `UiChrome.MARGIN`, and the arithmetic
## is asserted here rather than left to a person noticing a narrow tile.
##
## ## WHAT IS NOT TESTED HERE
##
## **Whether the plate looks right**, and whether New Rocker survives at 11 px. Both are
## `preview_editor`'s and the owner's — §5. What is checkable is the arithmetic, the fallback, and
## that one file is now the only place a panel colour is decided.
extends TestCase


func before_each() -> void:
	UiChrome.ignore_art = false
	UiChrome.forget()


func after_each() -> void:
	UiChrome.ignore_art = false
	UiChrome.forget()


# ── the plate ───────────────────────────────────────────────────────────────

func test_the_plate_is_committed_and_loads() -> void:
	assert_true(UiChrome.has_plate(),
			"%s did not load — run: godot --headless --path MapMaker --import"
			% UiChrome.PANEL_PATH)


## ⚠️ THE PREPARED SIZE IS THE ONLY LEVER ON A NINE-PATCH BORDER, so this asserts the art is the
## PREPARED copy and not the master.
##
## Godot draws the border at 1:1 from source pixels. `prepare_ui_chrome.py` resized the 1024 px
## master to 267 so that its painted 46 px border comes out at 12. **Copying the master in here
## instead would give a 46 px border on a 200 px inspector row** — 92 of its pixels corner — and
## the only symptom is a panel that looks wrong at small sizes. A test can tell 267 from 1024.
func test_the_plate_is_the_prepared_copy_and_not_the_master() -> void:
	var tex := UiChrome.plate()
	assert_true(tex != null)
	assert_true(tex.get_width() < 512,
			"this looks like the 1024 px master — the border would draw at 46 px, not %d"
			% UiChrome.MARGIN)
	# AND THE MARGIN FITS INSIDE IT TWICE OVER, which is what makes a nine-patch of it meaningful
	# at all: two 12 px corners have to leave a stretchable middle.
	assert_true(UiChrome.MARGIN * 2 < tex.get_width())


## The gutter is ON TOP of the border, not inside it.
##
## Content clears the moulding first and only then starts having padding. Getting this backwards
## is what put the game's resource rows under their own frame — `ResourceHUD` had been padding to
## a painted bead rather than to the nine-patch margin, which is a different number.
func test_the_content_margin_clears_the_border_and_then_pads() -> void:
	var box := UiChrome.panel_style(8, 6) as StyleBoxTexture
	assert_true(box != null, "with art present this is a StyleBoxTexture")
	assert_eq(box.texture_margin_left, float(UiChrome.MARGIN))
	assert_eq(box.texture_margin_top, float(UiChrome.MARGIN))
	assert_eq(box.content_margin_left, float(UiChrome.MARGIN + 8))
	assert_eq(box.content_margin_top, float(UiChrome.MARGIN + 6))
	assert_true(box.content_margin_left > box.texture_margin_left,
			"content that does not clear the moulding is drawn under it")


## The fallback is a real second rendering, and `ignore_art` is what keeps it exercised.
##
## ⚠️ **THIS IS THE ONE PLACE 16.4d's NO-FALLBACK RULE IS DELIBERATELY REVERSED**, and the reason
## is what each absence costs: a button with no icon still has its word, but a panel with **no
## stylebox has no visible boundary at all** — every control floats on the canvas surround and the
## tool reads as broken rather than as unstyled. So there is a flat fallback here, and it is the
## look the tool had before today, which is a known-good state rather than a guess.
func test_with_no_art_the_panels_fall_back_to_a_flat_plate() -> void:
	UiChrome.ignore_art = true
	assert_false(UiChrome.has_plate())
	var box := UiChrome.panel_style(8, 6)
	assert_true(box is StyleBoxFlat, "a panel must never end up with no stylebox")
	assert_eq((box as StyleBoxFlat).bg_color, UiChrome.PANEL)
	# THE GUTTER IS THE BARE PAD, with no border to clear -- so the flat panel is not padded as if
	# it had moulding it has not got.
	assert_eq(box.content_margin_left, 8.0)
	assert_eq(box.content_margin_top, 6.0)


# ── the width the plate costs ───────────────────────────────────────────────

## THE LOAD-BEARING TEST — see this file's header.
##
## Three tiles, two separations and a scrollbar must still fit inside the palette's content box
## now that the plate takes 12 px off each side. Asserted against `TILE.x` and the margin rather
## than against 354, so the check survives a change to either.
func test_three_palette_tiles_still_fit_inside_the_plate() -> void:
	var inner := ObjectPalette.PANEL_WIDTH - 2 * UiChrome.MARGIN - 2 * 8
	var tiles := 3 * ObjectPalette.TILE.x
	assert_true(inner >= tiles,
			"three %d px tiles need %d px and the plate leaves %d — the third column would be"
			% [ObjectPalette.TILE.x, tiles, inner]
			+ " clipped, not wrapped, because horizontal scrolling is disabled")
	# AND THE SLACK IS THE SEPARATIONS PLUS THE SCROLLBAR, which is what 330 was measured to
	# leave. Asserted as a floor rather than a figure: the point is that it did not go negative.
	assert_true(inner - tiles >= 8, "no room left for the grid separations")


## The width is DERIVED from the margin, not re-typed.
##
## Writing 354 would have worked today and lied tomorrow: change `UiChrome.MARGIN` and a typed
## width silently goes back to clipping. This asserts the relationship, which is the thing that
## was actually decided.
func test_the_palette_width_is_derived_from_the_plates_margin() -> void:
	assert_eq(ObjectPalette.PANEL_WIDTH, 330 + 2 * UiChrome.MARGIN,
			"the panel's width and its border are one sum")


# ── one place for a colour ──────────────────────────────────────────────────

## ⚠️ SIX CONSTANTS WERE DECLARED TWICE BEFORE TODAY and this is what stops them drifting back.
##
## `_TEXT`, `_DIM` and `_PANEL` were in both `editor.gd` and `object_palette.gd`. The failure is
## not dramatic — it is one panel going brown while the other two stay grey, each correct
## according to its own file. §6's *"mirroring a layout is not sharing one"*, with colours.
func test_the_two_screens_agree_about_what_a_panel_and_its_text_look_like() -> void:
	# READ OFF THE SCRIPTS' CONSTANT MAPS, which is what makes this a check on both files rather
	# than on one. `get_script_constant_map()` sees `const` members; a plain `get()` does not
	# reliably.
	var screens := {
		"editor.gd": (load("res://src/editor.gd") as GDScript).get_script_constant_map(),
		"object_palette.gd":
				(load("res://src/object_palette.gd") as GDScript).get_script_constant_map(),
	}
	for name in screens:
		var consts: Dictionary = screens[name]
		for entry in [["_PANEL", UiChrome.PANEL], ["_TEXT", UiChrome.TEXT], ["_DIM", UiChrome.DIM]]:
			assert_true(consts.has(entry[0]), "%s no longer declares %s" % [name, entry[0]])
			assert_eq(consts[entry[0]], entry[1],
					"%s's %s has drifted from UiChrome" % [name, entry[0]])


## ⚠️ THE THEME COLOURS THE CONTROLS THE FONT SETTING CANNOT REACH.
##
## `gui/theme/custom_font` changes the FACE and not the COLOUR, so `Button`s, `LineEdit`s and
## `SpinBox`es were drawing in the engine default's cold `#DFDFDF` beside cream `Label`s —
## measured off the first render as 223,223,223 against 232,222,199. Invisible on the flat greys
## the tool had before; on a brown plate it reads as two families.
##
## Asserted per type, because Godot's theme lookup walks the class hierarchy and it is easy to
## believe `Button` covers a `SpinBox` — it does not, a `SpinBox` is a `Range`.
func test_the_theme_colours_every_control_the_font_setting_cannot() -> void:
	var t := UiChrome.theme()
	for type in ["Button", "LineEdit", "SpinBox", "ItemList", "Label"]:
		assert_true(t.has_color("font_color", type), "%s has no font colour" % type)
		assert_eq(t.get_color("font_color", type), UiChrome.TEXT, "%s is not the tool's text" % type)
	# HOVER AND PRESSED, or a button goes cold grey under the pointer -- worse than being cold all
	# the time, because it only appears while somebody is using it.
	for entry in ["font_hover_color", "font_pressed_color"]:
		assert_eq(t.get_color(entry, "Button"), UiChrome.TEXT)
	# ⚠️ **AND THE PLACEHOLDER MUST NOT BE `TEXT`.** "search" and "New Map" would read as typed
	# content, and an author would clear a field that was already empty.
	assert_eq(t.get_color("font_placeholder_color", "LineEdit"), UiChrome.DIM)
	assert_false(t.get_color("font_placeholder_color", "LineEdit") == UiChrome.TEXT)


## ⚠️ THE CANVAS SURROUND IS NOT THE PANEL COLOUR, AND THAT IS A DESIGN DECISION.
##
## Every panel goes brown and gold; the ground behind the map stays neutral. An author judges
## terrain against what surrounds it, and a warm surround shifts the apparent hue of grass, sand
## and shallow water. Same reasoning as the minimap's ally tint being settled on CIE L* rather
## than hue: what matters is what a colour is judged NEXT TO. Pinned so a later "make it all
## match" tidy-up has to read the argument first.
func test_the_canvas_surround_stays_neutral() -> void:
	var bg := UiChrome.BG
	# NEUTRAL MEANS ITS THREE CHANNELS ARE CLOSE TOGETHER. Asserted as a spread rather than as a
	# literal colour, so the grey may be retuned and may not become brown.
	var spread: float = maxf(maxf(bg.r, bg.g), bg.b) - minf(minf(bg.r, bg.g), bg.b)
	assert_true(spread < 0.05,
			"the map's surround has taken on a hue (%.3f spread) — see this test's note" % spread)
	assert_false(bg == UiChrome.PANEL, "the surround and the plates are different surfaces")
