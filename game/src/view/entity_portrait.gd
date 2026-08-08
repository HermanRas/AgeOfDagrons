## Shared "crop a portrait out of the entity's own baked battle sprite"
## helper (ASSET_MISSING.md 1.5: no separate portrait art exists yet). Used by
## `ControlGroupSlot` (10.1/10.4) and `EntityPortraitView` (8.1a/8.1c) so the
## one place this trick lives doesn't drift into two slightly different crops.
class_name EntityPortrait
extends RefCounted


## The def's own S-facing static/idle frame, or {} for a placeholder visual
## (nothing baked to crop) or an undeclared def_id.
static func frame_for(def_id: StringName) -> Dictionary:
	var visual_id := GameDataRegistry.visual_for(def_id)
	var vis := GameDataRegistry.atlas_for(visual_id)
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
