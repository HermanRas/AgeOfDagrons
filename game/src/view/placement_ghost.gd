## The building-placement preview (PLAN.md 5.1): a flat, tinted footprint
## outline drawn wherever the player last tapped while in placement mode.
##
## Always drawn as a placeholder DIAMOND, even once real art exists for the
## building being placed -- a ghost's job is to show LEGALITY (green/red), not
## to preview the sprite, and tinting a real atlas frame convincingly is a
## separate rendering problem this does not need to solve to answer "can I put
## it here". Reuses `PlaceholderRenderer` rather than duplicating its geometry.
class_name PlacementGhost
extends Node2D

const VALID_COLOR := Color(0.35, 0.95, 0.35, 0.5)
const INVALID_COLOR := Color(0.95, 0.25, 0.25, 0.6)

var footprint_m := Vector2(2.0, 2.0)
var is_valid := true


func set_state(p_footprint_m: Vector2, p_valid: bool) -> void:
	footprint_m = p_footprint_m
	is_valid = p_valid
	queue_redraw()


func _draw() -> void:
	var spec := PlaceholderSpec.new()
	spec.shape = PlaceholderSpec.Shape.DIAMOND
	spec.footprint_m = footprint_m
	spec.color = VALID_COLOR if is_valid else INVALID_COLOR
	PlaceholderRenderer.draw_into(self, spec, 0)
