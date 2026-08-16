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
##      Widened by one tile, because a unit's sprite is wider than its tile.
static func hides(rect: Rect2i, tile: Vector2i) -> bool:
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
	var span_min := rect.position.x - front.y - 1
	var span_max := front.x - rect.position.y + 1
	var column := tile.x - tile.y
	return column >= span_min and column <= span_max


## Chebyshev distance in tiles from `tile` to the nearest part of `rect`: 0
## inside, 1 touching.
static func gap_to(tile: Vector2i, rect: Rect2i) -> int:
	var cx := clampi(tile.x, rect.position.x, rect.end.x - 1)
	var cy := clampi(tile.y, rect.position.y, rect.end.y - 1)
	return maxi(absi(tile.x - cx), absi(tile.y - cy))
