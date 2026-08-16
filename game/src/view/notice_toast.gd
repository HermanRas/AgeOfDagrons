## A single fading text line (PLAN.md 8.4), styled with the dragon toast
## banner. Generic and reusable rather than match-only: the main menu uses it
## directly for "not available yet" feedback, and `GameScene` wires it to real
## match events (a failed placement, a group assigned).
##
## No queue: the newest message simply replaces whatever was showing. MVP has
## nothing that fires two notices close enough together to need one, and
## building it before anything needs it would be guessing at the shape.
class_name NoticeToast
extends Control

const DISPLAY_SECONDS := 2.5
const FADE_SECONDS := 0.5
const _BANNER_PATH := "res://assets/ui/hud/toast_banner.png"

var _label: Label

## Bumped on every show_message() so a message replaced before its own timer
## fires cannot have its STALE timer fade out whatever replaced it early.
var _show_token: int = 0


## MOUSE_FILTER_IGNORE ON EVERY NODE HERE, NOT JUST THE ROOT.
##
## A toast is pure notification -- it has nothing to click and must never take a
## press. Setting it on the root alone is not enough and cost real play time:
## `mouse_filter` is per-node and does not inherit, so the banner `TextureRect`
## kept the Control default of STOP and swallowed every press inside the toast's
## rect. Because the toast lives at `modulate.a = 0` rather than `visible =
## false` between messages, it was an INVISIBLE 320x56 hole in the HUD, sitting
## over the middle of the build grid: the project owner reported (2026-08-16)
## that House and Town Center placed fine and Lumber Camp, Mill and Mining Camp
## did nothing but walk the villager to the ground under the icon -- which is
## exactly what happens when no Control consumes the press and `InputRouter`
## picks it up as a world tap. The two that worked were the only two slots left
## of the toast's left edge.
##
## Anything added here later needs the same treatment.
func _init() -> void:
	custom_minimum_size = Vector2(320.0, 56.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0

	if ResourceLoader.exists(_BANNER_PATH):
		var banner := TextureRect.new()
		banner.texture = load(_BANNER_PATH)
		banner.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		banner.set_anchors_preset(Control.PRESET_FULL_RECT)
		banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(banner)

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color("#F5DDA0"))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


## Shown immediately and at full opacity every time, even mid-fade from a
## previous message -- a second notice arriving is more important than
## finishing the first one's fade.
func show_message(text: String) -> void:
	_label.text = text
	modulate.a = 1.0
	_show_token += 1
	# A widget not yet in the tree can still display the message; it just
	# cannot schedule the fade-out, same reasoning as ControlGroupsHud's
	# tree guard. Tests drive this synchronously and never see the fade.
	if is_inside_tree():
		get_tree().create_timer(DISPLAY_SECONDS).timeout.connect(_start_fade.bind(_show_token))


func current_text() -> String:
	return _label.text


func _start_fade(token: int) -> void:
	if is_instance_valid(self) and token == _show_token:
		create_tween().tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
