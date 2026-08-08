## A dragon-framed HP bar (PLAN.md 8.1a/8.1b) that fills proportionally to
## `fraction`. Two layers of the SAME art rather than a separate empty/full
## pair -- no such pair exists in the pack: a darkened copy underneath reads
## as "empty", and a full-brightness copy on top is clipped by `fraction` to
## read as "how much is left". One asset, still a real fill rather than a
## static picture of a full bar.
class_name HealthBarView
extends Control

const _BAR_PATH := "res://assets/ui/hud/health_bar.png"
const _EMPTY_TINT := Color(0.35, 0.32, 0.3, 1.0)

var fraction: float = 1.0:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if fraction == value:
			return
		fraction = value
		if _fill != null:
			_fill.value = fraction * 100.0

var _fill: TextureProgressBar = null


func _init() -> void:
	if not ResourceLoader.exists(_BAR_PATH):
		return
	var tex: Texture2D = load(_BAR_PATH)
	custom_minimum_size = tex.get_size()

	var empty := TextureRect.new()
	empty.texture = tex
	empty.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	empty.modulate = _EMPTY_TINT
	empty.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(empty)

	_fill = TextureProgressBar.new()
	_fill.texture_progress = tex
	_fill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fill.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	_fill.min_value = 0.0
	_fill.max_value = 100.0
	_fill.value = fraction * 100.0
	_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fill)
