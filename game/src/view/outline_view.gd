## The player-coloured rim drawn over a building when a unit is hidden behind it
## (PLAN.md 3.1). One of these hangs off an `EntityView` and is shown only while
## `Occlusion.hides()` says somebody is back there.
##
## A CHILD NODE RATHER THAN A SECOND DRAW CALL IN ENTITYVIEW, because the whole
## point is to be drawn somewhere else in the order: `z_index` lifts it above
## every building in the world layer, while the sprite it belongs to stays
## correctly sorted and correctly hidden. One CanvasItem cannot be in two places
## in the paint order, so this is a separate one.
##
## It owns its own ShaderMaterial rather than sharing one, because the frame
## bounds are a uniform and every unit is drawing a different frame. Canvas items
## have no per-instance shader parameters in Godot 4, so a shared material would
## have every outline in the game rendering with whichever frame's bounds were
## written last.
class_name OutlineView
extends Node2D

const SHADER_PATH := "res://src/view/unit_outline.gdshader"

## Rim thickness in texture pixels. Two, not one: at the zoom a phone plays at, a
## single pixel disappears against a busy building roof.
const WIDTH_PX := 2.0

## Above everything the world layer draws. Godot orders by `z_index` before it
## Y-sorts, so this beats every building whatever their projected depth.
const Z := 60

var _tex: Texture2D = null
var _src := Rect2()
var _dest := Rect2()
var _flip_x := false
var _colour := Color.WHITE


func _init() -> void:
	z_index = Z
	visible = false
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists(SHADER_PATH):
		mat.shader = load(SHADER_PATH)
	material = mat


## Point this at the frame its owner is drawing. `src` and `dest` are the
## UNEXPANDED frame; the margin the rim needs is added here so callers do not
## have to know the width.
func set_frame(tex: Texture2D, src: Rect2, dest: Rect2, flip_x: bool, colour: Color) -> void:
	_tex = tex
	_src = src
	_dest = dest
	_flip_x = flip_x
	_colour = colour
	queue_redraw()


func _draw() -> void:
	if _tex == null or not visible or _src.size.x <= 0.0:
		return
	var mat := material as ShaderMaterial
	if mat == null or mat.shader == null:
		return

	# The frame's own bounds in UV, so the shader can refuse to sample the
	# neighbouring frame on the same atlas page.
	var size := Vector2(_tex.get_size())
	if size.x <= 0.0 or size.y <= 0.0:
		return
	mat.set_shader_parameter("region_min", _src.position / size)
	mat.set_shader_parameter("region_max", (_src.position + _src.size) / size)
	mat.set_shader_parameter("line_color", _colour)
	mat.set_shader_parameter("width_px", WIDTH_PX)

	# Both rects grow by the rim width: the destination so there is somewhere to
	# put the rim, and the source so the UVs actually reach past the frame. What
	# lies out there on the page is irrelevant -- the shader clamps to the region
	# above and reads 0 beyond it.
	var m := Vector2(WIDTH_PX, WIDTH_PX)
	var src := Rect2(_src.position - m, _src.size + m * 2.0)
	var dest := Rect2(_dest.position - m, _dest.size + m * 2.0)

	if _flip_x:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect_region(_tex,
				Rect2(-dest.position.x - dest.size.x, dest.position.y, dest.size.x, dest.size.y),
				src)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect_region(_tex, dest, src)
