## Who is standing behind what (PLAN.md 3.1's depth sorting, revisited).
##
## Pure tile geometry, static, no nodes -- so the rule that decides whether a
## villager is hidden can be asserted in a headless test rather than judged from
## a screenshot.
##
## THE PROBLEM THIS EXISTS FOR. Godot's Y-sort gives each sprite ONE scalar, and
## one scalar cannot describe a 10x10 footprint's depth range. A building sorts
## by its front corner (`Iso.footprint_sort_offset`), so a worker standing beside
## the MIDDLE of its long south edge measures several tiles short of that corner
## and sorts behind the whole building despite plainly standing in front of it.
##
## The first fix was a blanket one: any unit touching a building's footprint drew
## in front of it, full stop. That cured the drop-off clipping and caused
## something worse -- villagers on the far side stood ON the town centre's roof,
## which the project owner reported with a screenshot (2026-08-16).
##
## So the rule is now directional. A unit draws in front only if it is genuinely
## on the camera-facing side; anything behind sorts naturally, is hidden, and is
## reported by `hides()` so the view can outline it instead. Being hidden is no
## longer a bug to paper over -- it is a state with its own presentation.
class_name Occlusion
extends RefCounted

## How far behind a building a unit is still worth outlining, in tiles. Beyond
## this it is not plausibly under the sprite: buildings are tall but not endless,
## and outlining half the map behind a wonder would be noise. The project owner
## asked for 5 (2026-08-16), measuring from the footprint's upper edges.
const BEHIND_TILES := 5


## True when `tile` is on the camera-facing side of `rect` -- past its east or
## south extent, the two directions that project DOWN-screen. Such a unit is
## drawn in front of the building whatever the single-scalar sort would say.
##
## Deliberately not "is adjacent": a unit touching the NORTH edge is adjacent and
## is behind, and treating it as in front is exactly the roof-standing bug.
static func is_in_front(tile: Vector2i, rect: Rect2i) -> bool:
	return tile.x >= rect.end.x or tile.y >= rect.end.y


## True when the building at `rect` plausibly hides a unit standing on `tile`.
##
## Three conditions, all needed:
##
##   1. BEHIND IT. The unit sorts before the building's front tile, which is the
##      same comparison the depth sort itself makes, so this can never disagree
##      with what was actually drawn.
##   2. NEAR IT. Within BEHIND_TILES of the footprint, measured to the RECT and
##      not to its centre -- the same footprint-not-centre rule CombatSystem and
##      GatherSystem both keep.
##   3. IN ITS SCREEN COLUMN. Iso sends (x - y) to screen x, so the building
##      covers a band of that quantity; a unit outside the band is beside the
##      building on screen rather than behind it, however close it is in tiles.
##
## `column_pad` widens that band, in tiles, each side. It is 1 for a building,
## whose footprint already spans most of what its art covers -- and much more for a
## RESOURCE NODE, which holds one tile and can draw far wider than it: the large
## gold seam is 244 px, nearly 8 tiles of column, so the default band of 3 missed
## almost everything standing behind it. That was the project owner's second bug
## report of 2026-08-17 -- units walking behind a rock simply vanished, with no
## outline, because nothing but buildings was ever considered an occluder and the
## band would have been far too narrow even if it had been.
static func hides(rect: Rect2i, tile: Vector2i, column_pad: int = 1) -> bool:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return false
	if rect.has_point(tile) or is_in_front(tile, rect):
		return false

	var front := rect.end - Vector2i.ONE
	if tile.x + tile.y >= front.x + front.y:
		return false
	if gap_to(tile, rect) > BEHIND_TILES:
		return false

	# The band of (x - y) the footprint spans: widest at its west corner
	# (x0 - back y) and its east corner (front x - y0).
	var pad := maxi(1, column_pad)
	var span_min := rect.position.x - front.y - pad
	var span_max := front.x - rect.position.y + pad
	var column := tile.x - tile.y
	return column >= span_min and column <= span_max


## How many tiles of screen column a sprite covers each side of its own tile, for
## art whose footprint diamond measures `footprint_m` (visuals.json's placeholder,
## which is derived from the baked atlas).
##
## The projection is the one visuals.json documents: a footprint of (fx, fy) metres
## draws a diamond (fx + fy) * 16 px wide, and one tile of screen column is 32 px.
## So the half-width is (fx + fy) / 4 tiles -- 3.8 for the 244 px gold seam, 4.2 for
## the big quarry, 3.6 for an oak, and 1 for anything small enough not to matter.
##
## Rounded UP: half a tile of column short is a unit that is visibly under the
## sprite and not outlined, which is the bug being fixed.
static func column_pad_for(footprint_m: Vector2) -> int:
	return maxi(1, int(ceil((footprint_m.x + footprint_m.y) / 4.0)))


## Chebyshev distance in tiles from `tile` to the nearest part of `rect`: 0
## inside, 1 touching.
static func gap_to(tile: Vector2i, rect: Rect2i) -> int:
	var cx := clampi(tile.x, rect.position.x, rect.end.x - 1)
	var cy := clampi(tile.y, rect.position.y, rect.end.y - 1)
	return maxi(absi(tile.x - cx), absi(tile.y - cy))
