## One procedural placeholder, parsed from a `placeholder` block in
## data/visuals.json (PLAN.md 2.4). Phase 0.2b.
##
## Sizes are in METRES, not pixels, which is a deliberate departure from the
## sketch in PLAN.md 2.4 (`"size": [12, 24]`). Two reasons:
##
##   1. A pixel size silently encodes TILE_SIZE. Change the tile and every
##      placeholder is wrong, with nothing to tell you.
##   2. A placeholder's job is to occupy the space the real sprite will, so it
##      has to be expressed in the same units the atlas was baked from. Metres
##      go through Iso and land on the same footprint the art does.
##
## It also makes the placeholder an independent statement of intended size, which
## is worth having: comparing a placeholder against its atlas is how you catch a
## mis-scaled bake, and there is currently one to catch (`vis.villager` renders
## about 2x too tall -- PLAN.md 13.2).
class_name PlaceholderSpec
extends RefCounted

enum Shape {
	DIAMOND,          ## Terrain and flat ground props: the tile diamond itself.
	CAPSULE,          ## Units: an upright body with an optional facing marker.
	BOX,              ## Buildings: a footprint diamond extruded to a height.
}

const _SHAPE_NAMES := {
	"diamond": Shape.DIAMOND,
	"capsule": Shape.CAPSULE,
	"box": Shape.BOX,
}

## Fallback for an ID with no entry at all, so atlas_for() never returns null and
## an unknown visual draws as something visible rather than nothing. Magenta is
## deliberate: it should look like a bug, because it is one.
const UNKNOWN_COLOR := Color(1.0, 0.0, 1.0)

var shape: Shape = Shape.CAPSULE

## Ground footprint in metres (world x, world y). Drives the diamond for DIAMOND
## and BOX, and the body width for CAPSULE.
var footprint_m := Vector2(1.0, 1.0)

## Height above ground in metres. Ignored by DIAMOND, which is flat.
var height_m := 1.0

var color := UNKNOWN_COLOR

## Units get a wedge showing which way they face, so turning is visible before
## any directional art exists.
var facing_marker := false


static func from_dict(d: Dictionary) -> PlaceholderSpec:
	var spec := PlaceholderSpec.new()
	spec.shape = _SHAPE_NAMES.get(str(d.get("shape", "capsule")).to_lower(), Shape.CAPSULE)

	var fp: Array = d.get("footprint_m", [1.0, 1.0])
	if fp.size() >= 2:
		spec.footprint_m = Vector2(float(fp[0]), float(fp[1]))

	spec.height_m = float(d.get("height_m", 1.0))
	spec.facing_marker = bool(d.get("facing_marker", false))

	# Godot's Color("#rrggbb") constructor accepts the hex form visuals.json uses.
	var raw_color: Variant = d.get("color")
	spec.color = Color(str(raw_color)) if raw_color != null else UNKNOWN_COLOR
	return spec


## The unresolvable case: no visuals.json entry for this ID.
static func unknown() -> PlaceholderSpec:
	var spec := PlaceholderSpec.new()
	spec.shape = Shape.CAPSULE
	spec.footprint_m = Vector2(0.6, 0.6)
	spec.height_m = 1.8
	spec.color = UNKNOWN_COLOR
	spec.facing_marker = true
	return spec
