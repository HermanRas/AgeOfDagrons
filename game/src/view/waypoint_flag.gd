## The flag standing on a building's rally point (project owner, 2026-08-27: *"shows a
## flag as waypoint, use shape placeholder"*).
##
## **IT IS BAKED ART NOW, since 2026-08-28**, and the placeholder it shipped as did its
## job: the feature was playable for a day without waiting on a bake, and the swap was
## the small contained edit the old header promised — one `visuals.json` entry with
## `"colours": true`, an `EntityView` here, and the eight tints arrive for one boolean
## because `atlas_for` composes the colour suffix itself. `vis.waypoint_flag` is 12
## frames at 8 fps, so the pennant actually waves.
##
## Two parts, and only one of them is the sprite:
##
##   - **the tile it stands on**, still drawn here as the isometric diamond every ground
##     marker in the game uses (`PlaceholderRenderer`). **Kept deliberately when the art
##     landed** — a sprite says "a flag is near here", and the diamond is the only thing
##     that says *which tile*, which is the whole content of a rally point.
##   - **the flag**, an `EntityView` child pointed at `vis.waypoint_flag`. It is a child
##     rather than a hand-rolled `draw_texture_rect_region` so that the anchor, the
##     per-colour bake and the frame clock are the ones every other sprite in the game
##     uses, and so a re-cut atlas needs no arithmetic changed here.
##
## **A CLEAN CHECKOUT DRAWS THE PLACEHOLDER, NOT MAGENTA.** `game/assets/atlases` is
## gitignored build output, so the atlas may simply not be there; a *declared* id with no
## file on disk falls back to its own `placeholder` block, which `visuals.json` gives as a
## 0.66 x 2.96 m gold mast measured off the real frame. Magenta is what an *undeclared*
## id gets, and that is the state this is no longer in.
##
## Nothing spawns this and nothing pools it: `GameScene` owns one node and moves it to
## whichever of your own buildings is selected (`_refresh_waypoint_flag`), so it never
## goes through `EntityViewPool` and has to drive its own animation clock — see
## `_process`.
class_name WaypointFlag
extends Node2D

## The id the seam resolves. Named once here rather than at the call site, because
## `AGENT_GAME_CODER.md` §4's rule is that filenames live in `visuals.json` — this is
## the id, and the path behind it is the seam's business.
const VISUAL_ID := &"vis.waypoint_flag"

const _DIAMOND_ALPHA := 0.30

## Falls back to the same gold the HUD's chrome uses when no player colour has been
## handed over -- a flag drawn in the default 0 colour would claim to belong to player 1.
var _colour := Color(0.937, 0.769, 0.290)

var _sprite: EntityView


## Built in `_init()` so a bare `.new()` is fully wired for a headless test -- the
## convention `SelectionPanel` and `ResourceHUD` follow.
func _init() -> void:
	_sprite = EntityView.new()
	_sprite.visual_id = VISUAL_ID
	# `idle` is the only clip baked, and facing 0 is the only one stored: the flag is
	# `directions = 1`, so there is no compass to convert and `Iso.sim_facing_to_sprite`
	# has nothing to say about it.
	_sprite.play_anim(&"idle", 0)
	add_child(_sprite)


## Show the flag on `tile`, in `colour`. One call rather than a position setter plus a
## colour setter, because the two always change together: the only thing that moves this
## node is a new rally point arriving in a snapshot, and that snapshot names the owner.
##
## `colour_index` is the palette index the SPRITE needs (`colours.json`'s order is
## load-bearing) where `colour` is the `Color` the DIAMOND needs. Both, rather than one
## derived from the other, because the derivation only goes one way: an index picks a
## baked atlas, and no `Color` can be turned back into one. It is optional so a caller
## that only wants the marker still compiles -- -1 draws the untinted bake.
func show_on(tile: Vector2i, colour: Color, colour_index: int = -1) -> void:
	position = Iso.tile_centre_to_world(tile)
	set_colour(colour, colour_index)
	visible = true


func set_colour(colour: Color, colour_index: int = -1) -> void:
	_colour = colour
	if _sprite != null:
		_sprite.skin_colour = colour_index
	queue_redraw()


func current_colour() -> Color:
	return _colour


## The frame clock. `EntityViewPool` advances every pooled view once a frame; this node
## is not in the pool, so without this the flag resolves its atlas, draws frame 0 and
## never moves -- which looks exactly like a static bake and would have quietly wasted
## the twelve frames the art side rendered.
func _process(delta: float) -> void:
	if visible and _sprite != null:
		_sprite.advance(delta)


func _draw() -> void:
	# The tile, faint: it says WHERE without competing with the flag for attention, and
	# it is the only part of this that can. The sprite stands ON the tile; only the
	# diamond names it.
	var spec := PlaceholderSpec.new()
	spec.shape = PlaceholderSpec.Shape.DIAMOND
	spec.footprint_m = Vector2(Iso.METRES_PER_TILE, Iso.METRES_PER_TILE)
	spec.color = Color(_colour, _DIAMOND_ALPHA)
	PlaceholderRenderer.draw_into(self, spec, 0)
