## The flag standing on a building's rally point (project owner, 2026-08-27: *"shows a
## flag as waypoint, use shape placeholder"*).
##
## A PROCEDURAL SHAPE AND NOT AN ASSET REQUEST, which is what "use shape placeholder"
## settles. It is the same call `ActionFlash` and `PlacementGhost` already make and for
## the same reason: this is feedback about a TILE, not a picture of a thing in the world,
## so there is nothing for real art to add. It also means the feature does not wait on a
## bake — and the art agent's queue is the reason that matters.
##
## Drawn as three parts, because a flat marker on the ground reads as terrain decoration
## at this camera angle and the whole point is to be spotted:
##
##   - the tile it stands on, as the isometric diamond every ground marker in the game
##     uses (`PlaceholderRenderer`), so the exact tile is unambiguous
##   - a vertical pole, whose height goes through `Iso.height_to_world` rather than being
##     a pixel count — so it is foreshortened by the camera elevation exactly as a
##     sprite's height is, and it stays right if that elevation ever changes
##   - a pennant, hanging screen-RIGHT of the pole. Right rather than left because the
##     isometric light in this project comes from the upper left (`PlaceholderRenderer`'s
##     `_SIDE_SHADE`), so the lit face of a building is its left one and a pennant on
##     that side is the one that disappears against it.
##
## **A BAKE MAY BE COMING AND THIS DOES NOT WAIT FOR IT.** As of 2026-08-27 the art side
## has `tools/recipes/waypoint_flag.toml` plus eight per-colour variants in progress. If
## `vis.waypoint_flag` lands, swapping is a small, contained job: declare it in
## `visuals.json` with `"colours": true` (the eight variants are exactly the suffix
## transform `atlas_for` already applies) and draw an `EntityView` here instead of the
## pole and pennant. **Do not pre-empt it** by pointing at the id early — an undeclared
## or unstaged id resolves to the loud magenta placeholder, which is worse than this.
## Keep the tile diamond either way; it is what says which tile, and no sprite will.
##
## IN THE PLAYER'S COLOUR, via `set_colour`. Colour is the only thing that distinguishes
## players in v1 (PLAN.md 1), and this is a marker rather than baked art, so it is one of
## the few things that CAN be tinted -- see the HUD portraits and minimap, which are the
## others. There is no tint shader and must not be one; this is a `draw_*` call.
class_name WaypointFlag
extends Node2D

## Pole height in METRES, so it goes through the same projection a unit's height does.
## 3.0 puts the pennant above a villager's head (she measures 2.178 m) without reaching
## the eaves of a house, which is the range in which it is legible against both.
const POLE_METRES := 3.0

## Pennant size as a fraction of the pole, tuned to read at the minimum zoom rather than
## to be proportionate: below about a fifth it vanishes on a phone.
const PENNANT_DROP := 0.28
const PENNANT_REACH := 0.34

const _POLE_WIDTH := 2.0
const _DIAMOND_ALPHA := 0.30
const _OUTLINE_ALPHA := 0.75

## Falls back to the same gold the HUD's chrome uses when no player colour has been
## handed over -- a flag drawn in the default 0 colour would claim to belong to player 1.
var _colour := Color(0.937, 0.769, 0.290)


## Show the flag on `tile`, in `colour`. One call rather than a position setter plus a
## colour setter, because the two always change together: the only thing that moves this
## node is a new rally point arriving in a snapshot, and that snapshot names the owner.
func show_on(tile: Vector2i, colour: Color) -> void:
	position = Iso.tile_centre_to_world(tile)
	_colour = colour
	visible = true
	queue_redraw()


func set_colour(colour: Color) -> void:
	_colour = colour
	queue_redraw()


func current_colour() -> Color:
	return _colour


func _draw() -> void:
	# The tile, faint: it says WHERE without competing with the pole for attention.
	var spec := PlaceholderSpec.new()
	spec.shape = PlaceholderSpec.Shape.DIAMOND
	spec.footprint_m = Vector2(Iso.METRES_PER_TILE, Iso.METRES_PER_TILE)
	spec.color = Color(_colour, _DIAMOND_ALPHA)
	PlaceholderRenderer.draw_into(self, spec, 0)

	# `height_to_world` returns a screen OFFSET for a height in metres, which is
	# negative-y here -- so `top` is above the origin and the arithmetic below stays in
	# screen space without a sign of its own.
	var top := Iso.height_to_world(POLE_METRES)
	draw_line(Vector2.ZERO, top, Color(_colour.darkened(0.45), _OUTLINE_ALPHA),
			_POLE_WIDTH)

	# The pennant, hanging from the top of the pole toward screen right.
	var drop := -top.y * PENNANT_DROP
	var reach := -top.y * PENNANT_REACH
	draw_colored_polygon(PackedVector2Array([
		top,
		top + Vector2(reach, drop * 0.5),
		top + Vector2(0.0, drop),
	]), _colour)
