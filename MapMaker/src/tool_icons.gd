## The tool's icon art: 13 pieces, loaded from files (PLAN.md 16.4d).
##
## ## THIS FILE USED TO *DRAW* ITS GLYPHS AND NOW LOADS THEM. THE THREE ARGUMENTS FOR DRAWING
## ARE WORTH KEEPING, BECAUSE ONE OF THEM STILL BINDS.
##
## Until 2026-09-09 the four toolbar glyphs were `Image` drawing in this file — the owner had
## supplied them as pictures in a chat message rather than as files, and line art at 16 px is
## cheap to reproduce. `git show 82aeeab:MapMaker/src/tool_icons.gd` has that version. The art
## side then cut 13 real pieces (`sheet_h_mapmaker_tools`, repo `e901b98`) and the owner ruled
## they be committed into this project's own tree, so the drawn version is gone rather than kept
## as a fallback. Its three arguments, and what became of each:
##
##   - **no import step.** Still true and still the hazard: a PNG under `MapMaker/res://` needs
##     `--import` before `load()` can open it. It is now PAID rather than avoided — the sidecars
##     are committed beside the art — and `_load()` below reports a missing one as one warning
##     naming the fix, not as three engine errors per redraw;
##   - **no second path to test.** ⚠️ **THIS ONE IS WHY THERE IS NO DRAWN FALLBACK.** A
##     file-or-drawn loader is two renderings of every button and §5's rule is that the second
##     one never gets looked at — `IconAtlas.ignore_atlases` exists only because the lettered
##     plate path is one this machine never takes. A missing file here shows the button's WORD,
##     which is a state a person can see;
##   - **it scales with the button.** Replaced by `SIZE` and one LANCZOS resize. The art is
##     authored at 100 px for a 24 px tile, so the downscale is real work and the filter is
##     not a matter of taste — see below.
##
## ## THE SIZE WENT 16 → 24, AND THE OLD 16 WAS RIGHT FOR THE OLD ART
##
## The drawn version's note read: *"16 px, matching the label's font size — an icon taller than
## the text makes the row grow, and the toolbar is already four rows of chrome above a canvas
## that wants every pixel."* That reasoning is still sound; **what changed is the art.** These
## are painted at 256 and cut to 100 with a bevel, a gradient and a contact shadow, and at 16 px
## all three are sub-pixel: they do not become subtle, they become mud. 24 px is the smallest
## size at which the bevel reads, and it costs the toolbar rows about eight pixels each.
##
## ⚠️ **LANCZOS, NOT THE DEFAULT.** `Image.resize` defaults to `INTERPOLATE_BILINEAR`, which
## turns a 100 → 24 reduction into a soft smear — at that ratio each output pixel covers ~17
## input pixels and bilinear samples four of them. The art side took 236 → 100 through LANCZOS
## for the same reason and said so.
##
## ## ⚠️ THE THEME MUST NOT TINT THESE, AND THAT IS THE CALLER'S JOB
##
## The drawn glyphs were monochrome near-white **on purpose**, because a `Button`'s icon is
## multiplied by the theme's `icon_normal_color` in some themes and left alone in others, and a
## two-colour icon would come out with one colour invisible on exactly the machine nobody
## checked. These are full-colour gold, so that defence is gone: a tint would recolour the keep,
## the plume and the grass tile alike. **Every caller sets `icon_normal_color` to opaque white
## explicitly** — `Editor._icon_button()` and `ObjectPalette._build()` are the two, and
## `test_tool_icons` asserts both, because the tool is about to gain a real theme (16.4f) and
## the failure is silent.
class_name ToolIcons
extends RefCounted

## Where the committed art lives. **Inside this project**, not in `game/` and not in the
## gitignored `assets/UI_Gen/sliced/` the art side cuts into — the owner's ruling, 2026-09-09,
## on the grounds that a gitignored path is not a place to load from on a clean checkout.
const DIR := "res://assets/ui/icons"

## The drawn size, in screen pixels. See the class comment on why it is not 16 any more.
const SIZE := 24

## The five tool glyphs, and the two toolbar actions that are not tools.
const UNDO := &"mm_undo"
const REDO := &"mm_redo"

## Every id this file will answer for, so a typo is a failed test rather than a blank button.
## ⚠️ **`cat_buildings_keep` IS IN THE LIST AND IS WIRED TO NOTHING.** The art side's note: Gemini
## drew two buildings, the house became `cat_buildings` because a dwelling is what a Buildings tab
## means, and the keep is kept because a fortification glyph in the house style cannot be re-rolled
## identically. It is listed here so it is inventoried rather than forgotten — 16.5 may want it.
const IDS: Array[StringName] = [
	UNDO, REDO, &"mm_brush", &"mm_place", &"mm_erase", &"mm_select", &"mm_move",
	&"cat_buildings", &"cat_units", &"cat_resources", &"cat_terrain", &"cat_areas",
	&"cat_buildings_keep",
]

## Resized textures, keyed by id. Built once: `_tool_row()` and the palette each ask for their
## own exactly once today, and a toolbar redraw would otherwise re-decode and re-filter 13 PNGs.
## **A miss is cached as `null` too**, so a missing file warns once rather than once per redraw.
static var _cache: Dictionary = {}

## Ids already complained about, so the warning in `_load()` is one line and not a stream.
static var _warned: Dictionary = {}


## The glyph for one id, at `SIZE`, or null when the file is missing.
static func texture(id: StringName) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var tex := _load(id)
	_cache[id] = tex
	return tex


## The glyph for one `Editor.Tool` value, or null when that tool has none.
##
## ⚠️ **MATCHED AGAINST THE ENUM AND NEVER AGAINST A NUMBER**, which is the hazard this function
## has carried since it was drawn code: `Tool.START` was removed on 2026-09-08 and renumbered
## every member after it, and `test_cursors` was driving tools by literal at the time — so its
## tests went on passing while exercising the wrong tools. This file must never grow a written-out
## list of tool numbers. `Editor` is reached through its script rather than a `class_name` because
## `Editor.tscn`'s root has none.
static func for_tool(tool_value: int) -> Texture2D:
	var tools = load("res://src/editor.gd").Tool
	match tool_value:
		tools.PAINT:
			return texture(&"mm_brush")
		tools.PLACE:
			# 📝 **PLACE HAS A GLYPH NOW, WHICH OVERRIDES A DECISION RATHER THAN FILLING A GAP.**
			# The drawn version left it deliberately blank: *"the palette's own tile is the picture
			# of what a place-click will do, and a generic icon beside it would say less than the
			# town centre already showing in the panel."* The owner asked for one anyway. That
			# argument is still the reason `mm_place` is the first icon to drop if the row ever
			# looks busy.
			return texture(&"mm_place")
		tools.ERASE:
			return texture(&"mm_erase")
		tools.SELECT:
			return texture(&"mm_select")
		tools.MOVE:
			return texture(&"mm_move")
	return null


## Put one of these pictures on a button, untinted.
##
## ⚠️ **THE THREE OVERRIDES ARE THE WHOLE POINT OF THIS FUNCTION, AND IT LIVES HERE SO THAT
## NEITHER CALLER CAN FORGET THEM.** A `Button` multiplies its icon by the theme's
## `icon_normal_color`, and the drawn glyphs this file used to produce were monochrome near-white
## partly *because* of that — one ink survives any tint. These are full-colour gold, so that
## defence is gone: a theme that tints icons would recolour the keep, the plume and the grass tile
## alike. The tool sets no theme **today**, and 16.4f is about to give it one, so this guards a
## change that has not landed yet rather than fixing a fault on screen. `test_tool_icons` pins it
## on both callers, because the failure is a wrong colour and no test would otherwise look.
##
## ⚠️ **`icon_disabled_color` IS DELIBERATELY NOT SET.** Undo and Redo spend most of their life
## disabled, and greying the picture with the word is exactly right there — 16.2a's argument is
## that a disabled button is the only *visible* statement that there is nothing to take back.
##
## A null texture is left alone rather than assigned, so a missing file shows the button's WORD —
## a state a person can see, which is the reason there is no drawn fallback.
static func apply(b: Button, tex: Texture2D) -> void:
	if tex == null:
		return
	b.icon = tex
	b.add_theme_color_override("icon_normal_color", Color.WHITE)
	b.add_theme_color_override("icon_pressed_color", Color.WHITE)
	b.add_theme_color_override("icon_hover_color", Color.WHITE)


## Every id whose file is missing. Empty is the healthy answer; `Boot` prints it, so a forgotten
## `--import` is visible on the startup report rather than only in a blank button.
static func missing() -> Array[StringName]:
	var gone: Array[StringName] = []
	for id in IDS:
		if texture(id) == null:
			gone.append(id)
	return gone


## Drop the cache. For the tests, which need to load twice to prove the caching, and for nothing
## else — `IconAtlas.ignore_atlases`' precedent about a lever that exists for a check.
static func forget() -> void:
	_cache.clear()
	_warned.clear()


static func _load(id: StringName) -> Texture2D:
	var path := "%s/%s.png" % [DIR, id]
	# ⚠️ **`FileAccess.file_exists` AND NOT `ResourceLoader.exists`.** 16.3 measured the second one
	# answering TRUE for a file `load()` returns null for, and the guard has to be able to tell a
	# missing PNG (somebody deleted the art) from a missing import (somebody skipped `--import`) —
	# they want different sentences, and only the first is answerable before the load.
	if not FileAccess.file_exists(path):
		_warn(id, "no file at %s" % path)
		return null
	var res := load(path)
	if res == null or not (res is Texture2D):
		_warn(id, "%s did not load — run: godot --headless --path MapMaker --import" % path)
		return null
	var img := (res as Texture2D).get_image()
	if img == null:
		_warn(id, "%s loaded but carries no image" % path)
		return null
	# A LOSSLESS IMPORT GIVES RGBA8 AND `resize` REFUSES A COMPRESSED IMAGE, so this is a
	# precaution against an import preset changing under us rather than a case seen today.
	if img.is_compressed():
		img.decompress()
	img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


static func _warn(id: StringName, why: String) -> void:
	if _warned.has(id):
		return
	_warned[id] = true
	push_warning("ToolIcons: %s unavailable — %s" % [id, why])
