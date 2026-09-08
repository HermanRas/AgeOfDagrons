## The toolbar's cursor glyphs, drawn rather than loaded (PLAN.md 16.4).
##
## ## WHY THESE ARE CODE AND NOT FOUR PNGs
##
## The owner supplied four placeholder icons on 2026-09-08 — a marquee for Select, a four-way
## arrow for Move, a cursor with a minus for Erase and a cursor with a ring for Brush. They
## arrived as pictures in a message rather than as files in the repo, and the shapes are simple
## line art, so they are reproduced here as `Image` drawing.
##
## **Three reasons that is the right call for this tool rather than a shortcut:**
##
##   - **no import step.** A PNG under `MapMaker/res://` needs `--import` before `load()` can
##     open it, and 16.3's row records what the alternative costs from the other direction:
##     `ResourceLoader.exists()` answers TRUE for a staged file `load()` cannot open, so a
##     missing import is a null with three engine errors rather than an honest failure;
##   - **no second path to test.** A file-or-fallback loader is two renderings of every button,
##     and §5's rule is that the second one never gets looked at. `game/assets/atlases/` is the
##     standing example — the lettered-plate path is a requirement the owner's machine never
##     takes, so it needed `IconAtlas.ignore_atlases` to be exercised at all;
##   - **it scales with the button.** The glyphs are drawn at the size asked for.
##
## ⚠️ **IF THE OWNER WANTS THEIR OWN FILES USED, THIS IS THE ONE PLACE TO CHANGE** — `for_tool()`
## is the whole seam, and nothing else in the tool knows how a button gets its picture.
##
## ## THEY ARE MONOCHROME ON PURPOSE
##
## A `Button`'s icon is tinted by the theme's `icon_normal_color` in some themes and left alone in
## others, and this tool sets neither. So the glyphs are drawn in one near-white ink that reads on
## the toolbar's `#212129` panel whether or not anything tints them — a two-colour icon would
## come out with one of its colours invisible on exactly the machine nobody checked.
class_name ToolIcons
extends RefCounted

## The drawn size. **16 px, matching the label's font size** rather than the button's height: an
## icon taller than the text makes the row grow, and the toolbar is already four rows of chrome
## above a canvas that wants every pixel.
const SIZE := 16

## The ink. Near-white rather than white so it does not out-shout the button's own text.
const INK := Color(0.86, 0.86, 0.90)

## Built once per tool and kept, because `_tool_row()` asks for each of them exactly once today
## and a redraw of the toolbar would otherwise re-rasterise four images.
static var _cache: Dictionary = {}


## The glyph for one `Editor.Tool` value, or null when that tool has none.
##
## ⚠️ **KEYED BY THE ENUM'S INT AND NOT BY A NAME**, which is a hazard worth naming: `Tool.START`
## was removed on 2026-09-08 and renumbered every member after it. This file must never grow a
## written-out list of tool numbers — it takes whatever `_tool_row()` passes and matches on the
## enum through it, so a renumbering cannot silently put the eraser's icon on the brush.
static func for_tool(tool_value: int) -> Texture2D:
	if _cache.has(tool_value):
		return _cache[tool_value]
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var drawn := false
	# THE MATCH IS AGAINST THE ENUM, so this file has no opinion about the numbers. `Editor` is
	# reached through its script rather than a `class_name` because `Editor.tscn`'s root has none.
	var tools = load("res://src/editor.gd").Tool
	match tool_value:
		tools.PAINT:
			drawn = _brush(img)
		tools.SELECT:
			drawn = _marquee(img)
		tools.MOVE:
			drawn = _four_way(img)
		tools.ERASE:
			drawn = _minus_cursor(img)
		_:
			# PLACE HAS NO GLYPH and that is not an omission: the palette's own tile is the
			# picture of what a place-click will do, and a generic icon beside it would say less
			# than the town centre already showing in the panel.
			drawn = false
	if not drawn:
		_cache[tool_value] = null
		return null
	var tex := ImageTexture.create_from_image(img)
	_cache[tool_value] = tex
	return tex


# ── the four glyphs ─────────────────────────────────────────────────────────

## Select: a dashed box with a handle at each corner and midpoint.
static func _marquee(img: Image) -> bool:
	var lo := 2
	var hi := SIZE - 3
	# THE DASHED OUTLINE, every other pixel -- which is what makes it read as a selection
	# rectangle rather than as a plain box (the Place tool's palette tile is a filled square).
	for x in range(lo, hi + 1):
		if x % 2 == 0:
			_dot(img, x, lo)
			_dot(img, x, hi)
	for y in range(lo, hi + 1):
		if y % 2 == 0:
			_dot(img, lo, y)
			_dot(img, hi, y)
	# THE EIGHT HANDLES, as 2x2 blocks: corners and edge midpoints, which is the shape every
	# editor uses for "this is selected and can be resized".
	var mid := (lo + hi) / 2
	for spot in [Vector2i(lo, lo), Vector2i(mid, lo), Vector2i(hi - 1, lo),
			Vector2i(lo, mid), Vector2i(hi - 1, mid),
			Vector2i(lo, hi - 1), Vector2i(mid, hi - 1), Vector2i(hi - 1, hi - 1)]:
		_block(img, spot.x, spot.y, 2)
	return true


## Move: a four-way arrow.
static func _four_way(img: Image) -> bool:
	var c := SIZE / 2
	for i in range(1, SIZE - 1):
		_dot(img, i, c)
		_dot(img, c, i)
	# FOUR HEADS. Two pixels of chevron each, which is all that fits at 16 px and is enough --
	# an arrow without heads is a plus sign, which means something else entirely.
	for d in range(1, 4):
		_dot(img, 1 + d, c - d)
		_dot(img, 1 + d, c + d)
		_dot(img, SIZE - 2 - d, c - d)
		_dot(img, SIZE - 2 - d, c + d)
		_dot(img, c - d, 1 + d)
		_dot(img, c + d, 1 + d)
		_dot(img, c - d, SIZE - 2 - d)
		_dot(img, c + d, SIZE - 2 - d)
	return true


## Erase: a pointer with a minus badge.
##
## **A MINUS AND NOT AN X**, because an X on a cursor means "cannot" in every other tool an
## author has used, and this button removes rather than refuses.
static func _minus_cursor(img: Image) -> bool:
	_pointer(img)
	# THE BADGE, top right, clear of the arrow: a ring with a bar through it.
	var cx := SIZE - 5
	var cy := 4
	for d in range(-2, 3):
		_dot(img, cx + d, cy - 3)
		_dot(img, cx + d, cy + 3)
		_dot(img, cx - 3, cy + d)
		_dot(img, cx + 3, cy + d)
		_dot(img, cx + d, cy)
	return true


## Brush: a pointer with a soft ring, which is the shape a paint radius has.
static func _pointer_ring(img: Image) -> bool:
	_pointer(img)
	var cx := SIZE - 5
	var cy := 4
	# A DOTTED RING rather than a solid one, so it does not read as the eraser's badge with the
	# bar missing.
	for d in range(-2, 3):
		if d % 2 == 0:
			_dot(img, cx + d, cy - 3)
			_dot(img, cx + d, cy + 3)
			_dot(img, cx - 3, cy + d)
			_dot(img, cx + 3, cy + d)
	return true


## Brush, the tool the map is painted with.
static func _brush(img: Image) -> bool:
	return _pointer_ring(img)


## The arrow shared by Erase and Brush: a filled pointer in the lower left.
##
## Drawn from the top-left corner down, the way a mouse cursor is, so the two badged icons and
## the system pointer lean the same way. An arrow leaning the other way reads as a "back" glyph.
static func _pointer(img: Image) -> void:
	var ox := 2
	var oy := 3
	for row in range(0, 9):
		for col in range(0, maxi(1, 8 - row)):
			# THE TRIANGLE, narrowing as it goes down, then the tail.
			if col <= row:
				_dot(img, ox + col, oy + row)
	for t in range(0, 4):
		_dot(img, ox + 3 + t, oy + 8 + t)
		_dot(img, ox + 4 + t, oy + 8 + t)


static func _dot(img: Image, x: int, y: int) -> void:
	# CLIPPED HERE RATHER THAN BY EVERY CALLER. `Image.set_pixel` outside the rect is an engine
	# error per pixel, and these shapes are written in terms of the size -- so one off-by-one in
	# a glyph would fill the log rather than draw slightly wrong.
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, INK)


static func _block(img: Image, x: int, y: int, size: int) -> void:
	for dy in size:
		for dx in size:
			_dot(img, x + dx, y + dy)
