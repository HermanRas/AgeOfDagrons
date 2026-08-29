## Shared "crop a portrait out of the entity's own baked battle sprite"
## helper (ASSET_MISSING.md 1.5: no separate portrait art exists yet). Used by
## `ControlGroupSlot` (10.1/10.4) and `EntityPortraitView` (8.1a/8.1c) so the
## one place this trick lives doesn't drift into two slightly different crops.
class_name EntityPortrait
extends RefCounted


## The def's own S-facing static/idle frame, or {} for a placeholder visual
## (nothing baked to crop) or an undeclared def_id.
##
## `age` and `colour` are the owner's skin, in the same order and with the same
## defaults `GameDataRegistry.atlas_for()` takes -- one convention, so a caller
## never has to check which way round this one goes.
##
## Colour matters more here than anywhere else the crop is used: a portrait is
## how the player identifies something they are NOT looking at on the map -- an
## enemy unit in a control group, a member of a mixed selection -- and colour is
## the only thing that says whose it is (PLAN.md 1). An untinted portrait beside
## a tinted sprite is worse than either alone, because the two disagree.
##
## Age matters less but costs nothing: it keeps a town centre's portrait showing
## the same building the player can see on the map after they advance.
static func frame_for(def_id: StringName, age: int = 0, colour: int = -1) -> Dictionary:
	var visual_id := GameDataRegistry.visual_for(def_id)
	var vis := GameDataRegistry.atlas_for(visual_id, age, colour)
	if vis.is_placeholder:
		return {}
	var f := vis.frame_at(&"idle", 0, 0)          # facing 0 = S (AtlasEntry.FACINGS)
	if f.is_empty():
		return {}
	var tex := vis.texture(int(f["page"]))
	if tex == null:
		return {}
	var rect: Rect2i = f["rect"]
	return {"texture": tex, "rect": Rect2(rect.position, rect.size)}


## Where to draw `crop["rect"]` inside `box` so the sprite keeps its proportions,
## centred, touching whichever pair of edges it reaches first.
##
## THIS EXISTS BECAUSE A CROP IS NOT SQUARE AND THE SLOTS ARE. A villager's idle frame
## is roughly 40x70; painted straight into a 58 px square she is a third wider than she
## should be, and the project owner reported exactly that on 2026-08-30 ("villager
## select icon is stretched"). `draw_texture_rect_region` has no keep-aspect mode --
## it fills the rect it is given -- so the fitting has to happen before the call.
##
## WHY THE ACTION TILES NEVER HAD THE BUG, which is the useful half: `ActionSlot` wraps
## the same crop in an `AtlasTexture` inside a `TextureRect` and gets
## STRETCH_KEEP_ASPECT_CENTERED from the engine. The two hand-drawn slots
## (`EntityPortraitView`, `ControlGroupSlot`) are the ones that had to do it
## themselves, and neither did. Sharing the arithmetic here is what stops the next
## hand-drawn slot making it a third time.
##
## A crop with no area returns `box` unchanged rather than dividing by zero; the caller
## then draws a degenerate rect, which is what it would have done anyway.
static func fit(crop: Dictionary, box: Rect2) -> Rect2:
	var src: Rect2 = crop.get("rect", Rect2())
	if src.size.x <= 0.0 or src.size.y <= 0.0:
		return box
	var scale := minf(box.size.x / src.size.x, box.size.y / src.size.y)
	var drawn := src.size * scale
	return Rect2(box.position + (box.size - drawn) * 0.5, drawn)
