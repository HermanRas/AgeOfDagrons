## The building-placement preview (PLAN.md 5.1): flat, tinted footprint outlines
## drawn wherever the player last tapped while in placement mode.
##
## Always drawn as placeholder DIAMONDS, even once real art exists for the building
## being placed -- a ghost's job is to show LEGALITY (green/red), not to preview the
## sprite, and tinting a real atlas frame convincingly is a separate rendering
## problem this does not need to solve to answer "can I put it here". Reuses
## `PlaceholderRenderer` rather than duplicating its geometry.
##
## ONE OR MANY (PLAN.md 5.8). An ordinary placement is one box under the finger; a
## wall drag is a whole run of them, each with its own position, its own footprint --
## a run mixes 9-, 6- and 3-tile pieces -- and its own legality, because a run across
## a tree is partly placeable and the player needs to see which part. `set_state()` is
## the single-box case expressed in terms of the many, so there is one `_draw`.
class_name PlacementGhost
extends Node2D

const VALID_COLOR := Color(0.35, 0.95, 0.35, 0.5)
const INVALID_COLOR := Color(0.95, 0.25, 0.25, 0.6)

## What to draw. Each entry is `{offset: Vector2, footprint_m: Vector2, valid: bool}`,
## where `offset` is in WORLD pixels RELATIVE TO THIS NODE -- so the single-box case
## is one entry at zero and keeps using `position`, and a run sets `position` to the
## anchor and offsets each segment from it.
var boxes: Array[Dictionary] = []


## One box, centred on this node. The overwhelmingly common case, and the shape
## every caller before walls used.
func set_state(p_footprint_m: Vector2, p_valid: bool) -> void:
	boxes = [{"offset": Vector2.ZERO, "footprint_m": p_footprint_m, "valid": p_valid}]
	queue_redraw()


## A whole run. Positions are absolute world coordinates; this re-bases them onto its
## own `position` so the node can still be moved as one thing.
func set_run(entries: Array[Dictionary]) -> void:
	boxes.clear()
	for e in entries:
		boxes.append({
			"offset": (e["world"] as Vector2) - position,
			"footprint_m": e["footprint_m"],
			"valid": e["valid"],
		})
	queue_redraw()


## How many boxes are showing, and how many of those are legal. For a preview and for
## the readout that tells a player what a drag is about to cost them.
func box_count() -> int:
	return boxes.size()


func valid_count() -> int:
	var n := 0
	for b in boxes:
		if bool(b["valid"]):
			n += 1
	return n


func _draw() -> void:
	for b in boxes:
		var spec := PlaceholderSpec.new()
		spec.shape = PlaceholderSpec.Shape.DIAMOND
		spec.footprint_m = b["footprint_m"]
		spec.color = VALID_COLOR if bool(b["valid"]) else INVALID_COLOR
		# Drawn through a translated transform rather than by offsetting the geometry:
		# `PlaceholderRenderer.footprint_points` builds its polygon around the origin
		# and is shared with the selection ring, so it must not learn about offsets.
		draw_set_transform(b["offset"] as Vector2)
		PlaceholderRenderer.draw_into(self, spec, 0)
	draw_set_transform(Vector2.ZERO)
