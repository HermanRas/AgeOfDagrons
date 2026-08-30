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
const _BANNER_PATH := "res://assets/ui/chrome/banner_alert.png"

## 320x96, which is the banner's OWN 1024x308 aspect rather than a box chosen first.
##
## It was 320x56 against Kibyra's 184x80 dialogue box drawn KEEP_ASPECT_CENTERED, so
## the art letterboxed inside the toast and the real banner was narrower than the rect
## that carried it. The replacement is a fixed composition -- a gold dragon's head at
## each end of a braided run -- and it is drawn WHOLE and to its own proportions,
## because scaling it to a different aspect stretches a dragon's face.
##
## GameScene positions this at x = -WIDTH / 2 from CENTER_TOP; changing the width here
## means changing that offset there.
const SIZE := Vector2(320.0, 96.0)

## THE SAME BANNER, BIG ENOUGH TO READ A PARAGRAPH IN (project owner, 2026-08-30:
## *"the current alert box can be reused in single player campaigns for long text"*).
##
## THE ASPECT IS IDENTICAL TO `SIZE` AND THAT IS THE WHOLE TRICK. The banner is a fixed
## composition -- a gold dragon's head at each end of a braided run -- so it cannot be
## made taller for more lines without stretching a dragon's face. Making it BIGGER
## instead keeps every proportion and buys the height, which is exactly what the owner's
## mock-up showed: five lines of text in the same picture, drawn larger.
const LONG_SIZE := Vector2(720.0, 216.0)

## Font size for each mode. The short one is left to the theme (a notice is one line and
## the default reads fine at 320 px wide); the long one is stated, because the dark
## field at `LONG_SIZE` is about 460 px and 16 px is what fits five lines in it.
const LONG_FONT_SIZE := 16

## How long a long message holds, per character, and the floor under it.
##
## SCALED TO READING TIME RATHER THAN FIXED, because `DISPLAY_SECONDS`' 2.5 is right for
## "Not enough resources" and absurd for a campaign briefing. Roughly 15 characters a
## second, which is a slow-but-unhurried read and errs towards leaving it up.
##
## IT STILL FADES ON ITS OWN, and it deliberately does not become dismissable. Every
## node in this widget is `MOUSE_FILTER_IGNORE` and the header above records what that
## cost to learn -- a toast that took presses was an invisible hole in the build grid
## for a week. A campaign screen that wants a "continue" button should own one; this
## widget stays something that cannot swallow a tap.
const LONG_SECONDS_PER_CHAR := 1.0 / 15.0
const LONG_MIN_SECONDS := 4.0

## The dark field between the two dragons, as fractions of the banner. Measured off
## the art: the heads occupy roughly the outer sixth at each end and the braided
## moulding takes a tenth top and bottom. Text outside this prints over gold.
const _TEXT_INSET_X := 0.18
const _TEXT_INSET_Y := 0.14

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
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0

	if ResourceLoader.exists(_BANNER_PATH):
		var banner := TextureRect.new()
		banner.texture = load(_BANNER_PATH)
		banner.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		# STRETCH_SCALE, not KEEP_ASPECT_CENTERED. The rect above IS the art's aspect,
		# so there is nothing to letterbox -- and `EXPAND_IGNORE_SIZE` is required or
		# the 1024 px source becomes this Control's minimum size, which is the same
		# trap `ResourceHUD._add_badge` records paying for.
		banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		banner.stretch_mode = TextureRect.STRETCH_SCALE
		banner.set_anchors_preset(Control.PRESET_FULL_RECT)
		banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(banner)

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_color_override("font_color", Color("#F5DDA0"))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	_resize(SIZE)


## Shown immediately and at full opacity every time, even mid-fade from a
## previous message -- a second notice arriving is more important than
## finishing the first one's fade.
func show_message(text: String) -> void:
	_resize(SIZE)
	_label.remove_theme_font_size_override("font_size")
	_show(text, DISPLAY_SECONDS)


## A PARAGRAPH, in the same banner drawn larger (project owner, 2026-08-30). For a
## campaign briefing or any other body of text that has to be read rather than noticed.
##
## NOTHING CALLS THIS YET, and that is recorded rather than hidden: 12.3 the campaign is
## unbuilt, so this is the widget being ready ahead of the screen instead of the screen
## waiting on the widget. It is exercised by `test_notice_toast` and by nothing else.
##
## The two modes share one node rather than being two widgets, because they are the same
## picture and the same fade, and a second class would be a second place for the inset
## arithmetic to drift.
func show_long_message(text: String) -> void:
	_resize(LONG_SIZE)
	_label.add_theme_font_size_override("font_size", LONG_FONT_SIZE)
	_show(text, maxf(LONG_MIN_SECONDS, text.length() * LONG_SECONDS_PER_CHAR))


func current_text() -> String:
	return _label.text


## Whether the banner is currently at its paragraph size. For a test, and for a caller
## that wants to know whether it is looking at a notice or a briefing.
func is_long() -> bool:
	return is_equal_approx(custom_minimum_size.y, LONG_SIZE.y)


func _show(text: String, hold: float) -> void:
	_label.text = text
	modulate.a = 1.0
	_show_token += 1
	# A widget not yet in the tree can still display the message; it just
	# cannot schedule the fade-out, same reasoning as ControlGroupsHud's
	# tree guard. Tests drive this synchronously and never see the fade.
	if is_inside_tree():
		get_tree().create_timer(hold).timeout.connect(_start_fade.bind(_show_token))


## Set the banner's box and put the label back inside the dark field for it.
##
## THE INSETS ARE FRACTIONS, so this is the only place that has to know them and both
## sizes get the same margins by construction. A notice is one short line, but "Not
## enough resources" at the default size is already 150 px -- the trim is what keeps a
## longer one off the dragons rather than a nicety, and at `LONG_SIZE` it is the
## difference between five lines and five lines printed over two dragons' faces.
func _resize(to: Vector2) -> void:
	custom_minimum_size = to
	size = to
	_label.offset_left = to.x * _TEXT_INSET_X
	_label.offset_right = -to.x * _TEXT_INSET_X
	_label.offset_top = to.y * _TEXT_INSET_Y
	_label.offset_bottom = -to.y * _TEXT_INSET_Y


func _start_fade(token: int) -> void:
	if is_instance_valid(self) and token == _show_token:
		create_tween().tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
