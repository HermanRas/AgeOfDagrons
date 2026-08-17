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
## `behind_tiles` is how far up-screen the thing's art actually reaches. 5 for a
## building, by the owner's choice, and MEASURED for a resource node -- see
## `reach_for()`. A flat 5 for nodes produced a false positive the moment they
## became occluders: the big gold seam is 102 px tall and rimmed an enemy knight
## standing four tiles behind it, in the clear, with nothing over him.
static func hides(rect: Rect2i, tile: Vector2i, column_pad: int = 1,
		behind_tiles: int = BEHIND_TILES) -> bool:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return false
	if rect.has_point(tile) or is_in_front(tile, rect):
		return false

	var front := rect.end - Vector2i.ONE
	if tile.x + tile.y >= front.x + front.y:
		return false
	if gap_to(tile, rect) > maxi(1, behind_tiles):
		return false

	# The band of (x - y) the footprint spans: widest at its west corner
	# (x0 - back y) and its east corner (front x - y0).
	var pad := maxi(1, column_pad)
	var span_min := rect.position.x - front.y - pad
	var span_max := front.x - rect.position.y + pad
	var column := tile.x - tile.y
	return column >= span_min and column <= span_max


## How far a sprite OVERHANGS the tiles it claims, in tiles of screen column, each
## side. `footprint_m` is the art's own measured diamond (visuals.json's
## placeholder, derived from the baked atlas) and `footprint_tiles` is what the
## entity actually occupies.
##
## The projection is the one visuals.json documents: a footprint of (fx, fy) metres
## draws a diamond (fx + fy) * 16 px wide, one tile of screen column is 32 px, and a
## claimed footprint of (Fx, Fy) tiles already spans (Fx + Fy) / 2 tiles of column
## each side of its centre. What is left over is the overhang, and only the overhang
## needs padding -- `hides()` is already testing against the claimed rect.
##
## So a 4x4 gold seam pads by 1 (its footprint covers its art, which is the point of
## giving it one) and a one-tile oak pads by 3 (232 px of canopy over a trunk that
## really does stand on a single tile). Rounded UP: half a tile short is a unit
## visibly under the sprite and not outlined, which is the bug this exists for.
static func column_pad_for(footprint_m: Vector2, footprint_tiles: Vector2i = Vector2i.ONE) -> int:
	var art_half := (footprint_m.x + footprint_m.y) / 4.0
	var claimed_half := float(maxi(1, footprint_tiles.x) + maxi(1, footprint_tiles.y)) / 2.0
	return maxi(1, int(ceil(art_half - claimed_half)))


## How far UP-SCREEN a sprite `height_m` metres tall reaches, in tiles -- i.e. how
## far behind itself it can hide something.
##
## A metre of height projects `Iso.VERTICAL_PX_PER_METRE` px up the screen, and one
## tile further back moves a unit half a tile height, 16 px, up. So the reach is
## height * 19.596 / 16 tiles: 10 for an oak, 2 for the quarry, and under 1 for the
## flat gold seam, which is 0.24 m of barely-raised quarry patch.
##
## Clamped to [1, BEHIND_TILES]. The floor keeps every occluder able to hide the
## tile directly behind it; the ceiling is the project owner's 5, chosen for
## buildings, and a tall tree covering nine tiles of ground would outline half a
## forest for a gain nobody asked for.
static func reach_for(height_m: float) -> int:
	return clampi(int(round(height_m * Iso.VERTICAL_PX_PER_METRE / 16.0)), 1, BEHIND_TILES)


## Chebyshev distance in tiles from `tile` to the nearest part of `rect`: 0
## inside, 1 touching.
static func gap_to(tile: Vector2i, rect: Rect2i) -> int:
	var cx := clampi(tile.x, rect.position.x, rect.end.x - 1)
	var cy := clampi(tile.y, rect.position.y, rect.end.y - 1)
	return maxi(absi(tile.x - cx), absi(tile.y - cy))
