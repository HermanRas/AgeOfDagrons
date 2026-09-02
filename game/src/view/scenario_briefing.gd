## The scenario briefing (PLAN.md 15.6): what the mission asks, shown once before the
## first order and dismissed by an X.
##
## ## WHY IT IS AN X AND NOT A TIMER OR A TAP-ANYWHERE
##
## The project owner's spec, 2026-09-02: *"a scenario message is required and the user
## needs to tap the X to close it, interactive consent of the goal"*. The point is the
## consent -- a briefing that faded on its own, or that a stray tap on the map dismissed,
## would leave a player who never read the objective wondering what the match wanted. So
## the ONLY way out is the button, and `mouse_filter` is STOP for the same reason
## `ResultScreen`'s is: everything under it is unreachable while it is up.
##
## ⚠️ **IT DOES NOT STOP `SimClock`, UNLIKE `PauseMenu` AND `ResultScreen`.** That is a
## decision and not an omission. On a host the clock drives the simulation for EVERYBODY,
## so a briefing that stopped it would freeze a hosted skirmish for every joined player
## while one of them read a paragraph -- and `ScenarioDef.message` is shared with skirmish
## by the owner's own spec, so this class cannot assume it is solo. What it costs is a few
## seconds of a Passive opponent gathering, on a map where nothing can attack the player
## while they read.
##
## ## SHOWN ONCE, LATCHED
##
## `GameScene._start_match()` runs on two paths -- once from `_ready()` and again from
## `match_configured` on a client whose config arrived late -- so `show_message` has to be
## idempotent or a client would get the briefing thrown back up after dismissing it. Same
## `_shown` latch, same reason, as `ResultScreen`.
##
## Built in `_init()` rather than `_ready()`, the convention every widget here follows, so
## a bare `.new()` is fully wired for a headless test.
class_name ScenarioBriefing
extends Control

## Taller and wider than `ResultScreen`'s 340x360, because this one carries PROSE rather
## than a verdict: the owner's scenario 1 briefing is five sentences, and the panel that
## fits "VICTORY" in 40 px does not fit them. Still portrait, because the frame art is
## 160x192 and STRETCH_SCALE thins the top and bottom borders visibly on a landscape box.
const PANEL_SIZE := Vector2(420.0, 520.0)

const _TITLE_FONT_SIZE := 24
const _BODY_FONT_SIZE := 16

## The frame's gold border eats this much on each side -- `ResultScreen`'s figures, found
## the same way: the first attempt gave the column the whole rect and drew the text across
## the border and the dragon rather than inside the brown.
const _MARGINS := {"left": 34, "right": 34, "top": 30, "bottom": 24}

## The X, top right of the panel. Square, and big enough to hit with a thumb -- PLAN.md
## 10's minimum touch target, which is the only reason this is not the 24 px an X wants
## to be visually.
const _CLOSE_SIZE := Vector2(52.0, 52.0)

var _title: Label
var _body: Label
var _panel: PanelContainer
var _close: Button

## Latched, not derived from `visible` -- see the header. Also what makes "has the player
## been shown the goal" a question a test can ask after the briefing was dismissed.
var _shown := false


func _init() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP, so nothing underneath is reachable while the briefing is up. `GameScene` also
	# gates its own tap handling for the touch path that never goes through GUI input at
	# all, which is why `is_open()` below is public.
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# Panel, margin, column -- `ResourceHUD`'s and `ResultScreen`'s layout rather than
	# hand-positioned children inside a bare Control. Anchored to the centre with explicit
	# offsets on all four sides so the box is exactly PANEL_SIZE wherever the viewport ends
	# up: `position` alone writes offset_left/offset_top and leaves the other two behind.
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
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	# The heading row: the title, and the X pushed to the far end of it.
	var header := HBoxContainer.new()
	column.add_child(header)

	_title = Label.new()
	_title.text = "OBJECTIVE"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiFont.title(_title, _TITLE_FONT_SIZE, true)
	_title.add_theme_color_override("font_color", HudStyle.GOLD)
	header.add_child(_title)

	_close = Button.new()
	_close.text = "X"
	_close.custom_minimum_size = _CLOSE_SIZE
	_close.add_theme_font_size_override("font_size", 22)
	# SHRINK_CENTER, or the HBox stretches it to whatever room the title leaves -- which
	# is the trap `ResultScreen._menu_button` records for its own two buttons.
	_close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_close.pressed.connect(close)
	header.add_child(_close)

	# INSIDE A SCROLLER, and this is the difference from `ResultScreen` that matters. The
	# owner writes these briefings as prose with `\n` in them and is free to write a longer
	# one tomorrow; a Label left to grow would push the X off the top of a 520 px panel and
	# there would be no way to dismiss the thing. The panel is a fixed size and the text
	# scrolls inside it.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", _BODY_FONT_SIZE)
	# EXPAND_FILL horizontally so the wrap happens at the scroller's width. Without it the
	# Label reports its whole unwrapped line as its minimum width and the ScrollContainer
	# obliges by scrolling sideways instead of wrapping -- with horizontal scrolling
	# disabled above, that reads as a briefing with its right-hand half missing.
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(
			PANEL_SIZE.x - float(int(_MARGINS["left"]) + int(_MARGINS["right"])), 0.0)
	scroll.add_child(_body)


## Raise the briefing. Returns whether it actually opened.
##
## AN EMPTY MESSAGE OPENS NOTHING, which is what every skirmish and every debug factory
## carries -- an empty modal with an X in it is worse than no modal, because the player
## has to dismiss it to find out it said nothing. `MatchConfig.scenario_message` documents
## empty as "no modal" for exactly this.
func show_message(text: String) -> bool:
	if _shown or text.strip_edges().is_empty():
		return false
	_shown = true
	_body.text = text
	visible = true
	return true


func close() -> void:
	visible = false


## Whether the briefing has EVER been raised, which is not the same question as whether it
## is on screen right now -- `is_open()` is that one. `GameScene` needs both: this one to
## know it has already done its job, that one to know whether to swallow a tap.
func is_shown() -> bool:
	return _shown


func is_open() -> bool:
	return _shown and visible


func message_text() -> String:
	return _body.text


## The real button, so a preview and a test press the control the player presses rather
## than calling the handler behind it. Public for the reason `PauseMenu` holds its resign
## button and `GameScene` its corner buttons: on this project a button wired to nothing
## has twice looked exactly like a working one.
func close_button() -> Button:
	return _close


func panel_rect() -> Rect2:
	return _panel.get_global_rect()
