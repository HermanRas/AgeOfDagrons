## The end-of-match overlay (PLAN.md 11.1's "result screen"): who won, why, and
## the way out. Styled as `PauseMenu` is, and deliberately its sibling rather than
## a mode of it -- the two look alike and behave oppositely. A pause is something
## the player opens and closes; this is something the MATCH does to them, and it
## has no Resume, because there is nothing left to resume.
##
## Reads NOTHING itself. `GameScene` hands it the outcome off the snapshot, the
## same way it feeds `ResourceHUD` through `EventBus` -- the sim decided this
## (`WinConditionSystem`), and a client that worked out its own result could show
## VICTORY over a match the host thinks is still running.
##
## Stops `SimClock` when it opens, like `PauseMenu`: without that the world keeps
## ticking behind a screen that says it is over, and every snapshot after it is
## bandwidth spent on a match nobody is playing.
##
## Built in `_init()` rather than `_ready()`, the convention every widget here
## follows, so a bare `.new()` is fully wired for a headless test.
class_name ResultScreen
extends Control

const _MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"
const _BUTTON_SIZE := Vector2(240.0, 76.0)

## Bigger than any other text in the game on purpose: it is the one line the
## player is meant to read from across the room, and the panel exists to carry it.
const _TITLE_FONT_SIZE := 40
const _SUBTITLE_FONT_SIZE := 16

## Roughly `PauseMenu`'s 300x320 proportions, and deliberately not wider. The frame
## art is 160x192 -- portrait -- and STRETCH_SCALE distorts it to whatever box it is
## given, so a landscape panel thins the top and bottom borders visibly. The width
## is set by the buttons (240) plus the border, not by the text; the text is written
## short enough to fit that instead (see `GameScene._refresh_result`).
const PANEL_SIZE := Vector2(340.0, 360.0)

## The frame's gold border eats this much of the panel on each side. Found the way
## the resource HUD's margins were: the first attempt gave the column the whole panel
## rect, and both lines of text were drawn across the border and the dragon rather
## than inside the brown.
const _MARGINS := {"left": 40, "right": 40, "top": 34, "bottom": 26}

var _title: Label
var _subtitle: Label
var _panel: PanelContainer

## Latched, not derived from `visible`. The outcome arrives in EVERY snapshot from
## the moment it is decided, so without this the screen would be rebuilt ten times
## a second -- and a player who somehow dismissed it would have it thrown back up
## on the next tick.
var _shown := false


func _init() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP, unlike a toast: this one is meant to swallow presses. It covers the
	# whole viewport, so the selection panel and the build grid underneath it are
	# unreachable while it is up -- which is the point, and is why `GameScene` also
	# gates its own tap handling on `_match_over` for the touch path that never
	# goes through GUI input at all.
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# A PanelContainer with HudStyle's frame, laid out the way `ResourceHUD` and the
	# age header are -- panel, margin, column -- rather than by hand-positioning
	# children inside a bare Control. Anchored to the centre with explicit offsets on
	# all four sides so the box is exactly PANEL_SIZE wherever the viewport ends up:
	# `position` alone writes offset_left/offset_top and leaves the other two behind,
	# the trap GameScene's own header records for the HUD ports.
	var panel := PanelContainer.new()
	_panel = panel
	HudStyle.add_panel_background(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -PANEL_SIZE.x * 0.5
	panel.offset_top = -PANEL_SIZE.y * 0.5
	panel.offset_right = PANEL_SIZE.x * 0.5
	panel.offset_bottom = PANEL_SIZE.y * 0.5
	panel.custom_minimum_size = PANEL_SIZE
	add_child(panel)

	var margin := MarginContainer.new()
	for side in _MARGINS:
		margin.add_theme_constant_override("margin_%s" % side, int(_MARGINS[side]))
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(column)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", _TITLE_FONT_SIZE)
	_title.add_theme_color_override("font_color", HudStyle.GOLD)
	column.add_child(_title)

	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Wraps rather than widening the panel: a Label left to itself reports its whole
	# line as its minimum width, and a PanelContainer would grow to fit it -- so one
	# long result line would stretch the frame instead of running onto two lines.
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.custom_minimum_size = Vector2(
			PANEL_SIZE.x - float(int(_MARGINS["left"]) + int(_MARGINS["right"])), 0.0)
	_subtitle.add_theme_font_size_override("font_size", _SUBTITLE_FONT_SIZE)
	column.add_child(_subtitle)

	# No Resume. See the header: the match is over, and a button that returned the
	# player to a decided match would be a lie about what the sim will do next.
	column.add_child(_menu_button("main_menu_button.png", _on_main_menu_pressed))
	column.add_child(_menu_button("quit_button.png", func() -> void: get_tree().quit()))


## Show the outcome. Idempotent: the first call wins and later ones are ignored,
## so the ten snapshots a second that follow a victory cannot restyle it.
##
## `won` is deliberately not a three-way "won/lost/drew": a draw is a match the
## local player did not win, and calling that a defeat is closer to the truth than
## calling it a victory. `subtitle` is where the distinction is spelled out, since
## GameScene knows which of the three it was.
func show_result(won: bool, subtitle: String = "") -> void:
	if _shown:
		return
	_shown = true
	_title.text = "VICTORY" if won else "DEFEAT"
	_subtitle.text = subtitle
	visible = true
	SimClock.stop()


func is_shown() -> bool:
	return _shown


func title_text() -> String:
	return _title.text


func subtitle_text() -> String:
	return _subtitle.text


## The framed box, for whoever wants to check it came out PANEL_SIZE rather than
## however wide its longest line made it (`dev_preview/preview_victory.gd`).
func panel_rect() -> Rect2:
	return _panel.get_global_rect()


## Same teardown as `PauseMenu`'s Resign: `Net.leave()` before the scene change, so
## no host is left running behind the main menu.
func _on_main_menu_pressed() -> void:
	Net.leave()
	get_tree().change_scene_to_file(_MAIN_MENU_SCENE)


func _menu_button(texture_file: String, on_pressed: Callable) -> TextureButton:
	var btn := TextureButton.new()
	var path := "res://assets/ui/menu/%s" % texture_file
	if ResourceLoader.exists(path):
		btn.texture_normal = load(path)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	btn.custom_minimum_size = _BUTTON_SIZE
	# SHRINK_CENTER, or the VBox would stretch each button to the column's full width
	# -- which is the subtitle's width, not the button art's, and 94x31 art pulled
	# wider than it is tall by a different factor per row reads as two different
	# buttons.
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(on_pressed)
	return btn
