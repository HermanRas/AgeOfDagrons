## Draws procedural placeholder art (PLAN.md 2.4). Phase 0.2b.
##
## Isometric diamonds for terrain, capsules with a facing marker for units, boxes
## for buildings -- generated at runtime from data/visuals.json, no image files.
## That is why placeholders cost nothing in APK size and why they can stay in the
## build permanently as the asset-pack fallback (PLAN.md 3.2).
##
## Stateless statics drawing into a caller's CanvasItem, rather than a node type.
## A placeholder is one of two things EntityView might draw, not a thing that owns
## a place in the scene tree -- making it a node would mean adding and removing
## children every time an atlas appeared or vanished.
##
## Every shape is anchored at the entity's ground point (the local origin), which
## is the same convention as a baked atlas frame's `anchor`, so swapping between
## placeholder and real art moves nothing.
class_name PlaceholderRenderer
extends RefCounted

## Flat top faces read as ambiguous in isometric, so side faces are darkened to
## give the box a light direction. Matches nothing in particular -- it just has to
## make a 3D reading obvious.
const _SIDE_SHADE := 0.72
const _DARK_SIDE_SHADE := 0.55
const _OUTLINE_ALPHA := 0.35

const _CAPSULE_SEGMENTS := 12


static func draw_into(ci: CanvasItem, spec: PlaceholderSpec, facing: int) -> void:
	match spec.shape:
		PlaceholderSpec.Shape.DIAMOND:
			_draw_diamond(ci, spec)
		PlaceholderSpec.Shape.BOX:
			_draw_box(ci, spec)
		_:
			_draw_capsule(ci, spec)

	if spec.facing_marker:
		_draw_facing_marker(ci, spec, facing)


## The four ground corners of a footprint, in draw order (screen top, right,
## bottom, left). Public because the selection ring and health dot will want the
## same outline later (PLAN.md 5.6).
static func footprint_points(footprint_m: Vector2, lift_m := 0.0) -> PackedVector2Array:
	var half := footprint_m * 0.5
	var lift := Iso.height_to_world(lift_m)
	return PackedVector2Array([
		Iso.metres_to_world(Vector2(-half.x, -half.y)) + lift,
		Iso.metres_to_world(Vector2(half.x, -half.y)) + lift,
		Iso.metres_to_world(Vector2(half.x, half.y)) + lift,
		Iso.metres_to_world(Vector2(-half.x, half.y)) + lift,
	])


static func _draw_diamond(ci: CanvasItem, spec: PlaceholderSpec) -> void:
	var pts := footprint_points(spec.footprint_m)
	ci.draw_colored_polygon(pts, spec.color)
	_outline(ci, pts, spec.color)


static func _draw_box(ci: CanvasItem, spec: PlaceholderSpec) -> void:
	var base := footprint_points(spec.footprint_m)
	var top := footprint_points(spec.footprint_m, spec.height_m)

	# Only the two faces nearer the camera are visible. footprint_points returns
	# screen top/right/bottom/left, so those are base[1]..base[2] (right) and
	# base[2]..base[3] (left).
	_quad(ci, base[1], base[2], top[2], top[1], spec.color.darkened(1.0 - _SIDE_SHADE))
	_quad(ci, base[2], base[3], top[3], top[2], spec.color.darkened(1.0 - _DARK_SIDE_SHADE))

	ci.draw_colored_polygon(top, spec.color)
	_outline(ci, top, spec.color)


static func _draw_capsule(ci: CanvasItem, spec: PlaceholderSpec) -> void:
	# Width is the footprint's screen width; height is real height, foreshortened
	# by the camera elevation the same way a sprite's would be.
	var width := absf(Iso.metres_to_world(Vector2(spec.footprint_m.x, 0.0)).x) * 2.0
	var radius := maxf(width * 0.5, 1.0)
	var height := absf(Iso.height_to_world(spec.height_m).y)

	# A capsule shorter than it is wide degenerates; clamp so it stays a lozenge
	# rather than inverting.
	var span := maxf(height - radius * 2.0, 0.0)
	var top_y := -(span + radius)
	var bottom_y := -radius

	var pts := PackedVector2Array()
	for i in range(_CAPSULE_SEGMENTS + 1):
		var a := PI + PI * float(i) / float(_CAPSULE_SEGMENTS)
		pts.append(Vector2(cos(a), sin(a)) * radius + Vector2(0.0, top_y))
	for i in range(_CAPSULE_SEGMENTS + 1):
		var a := PI * float(i) / float(_CAPSULE_SEGMENTS)
		pts.append(Vector2(cos(a), sin(a)) * radius + Vector2(0.0, bottom_y))

	ci.draw_colored_polygon(pts, spec.color)
	_outline(ci, pts, spec.color)


static func _draw_facing_marker(ci: CanvasItem, spec: PlaceholderSpec, facing: int) -> void:
	var dir := Iso.facing_to_screen_dir(facing)
	# Sized off the footprint so the marker stays readable on a deer and a
	# villager alike, and sits just clear of the body.
	var reach := maxf(absf(Iso.metres_to_world(Vector2(spec.footprint_m.x, 0.0)).x), 4.0)
	var tip := dir * reach * 1.6
	var side := dir.orthogonal() * reach * 0.5

	ci.draw_colored_polygon(
		PackedVector2Array([tip, side, -side]),
		spec.color.lightened(0.45)
	)


static func _quad(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, d: Vector2,
		color: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([a, b, c, d]), color)


static func _outline(ci: CanvasItem, pts: PackedVector2Array, color: Color) -> void:
	var closed := PackedVector2Array(pts)
	closed.append(pts[0])
	ci.draw_polyline(closed, Color(color.darkened(0.6), _OUTLINE_ALPHA), 1.0)
