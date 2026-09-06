## "Are you sure?" — a yes/no modal for an action that cannot be undone (owner request,
## 2026-09-06; no PLAN.md row, see `CampaignProgress.reset_all`).
##
## Built for the campaign screen's RESET PROGRESS button and deliberately generic, because
## it is the first of a shape this game will want again: quit-to-menu with a match running,
## deleting an installed pack, overwriting a save.
##
## ## AN IN-SCENE OVERLAY, NOT A `ConfirmationDialog`
##
## `ColourPickerPopup`'s reasoning, and it is worth repeating because Godot offers a
## built-in for exactly this job and the built-in is the wrong tool here. `AcceptDialog` and
## its subclasses are `Window`s: they position themselves in **screen** coordinates, they
## can become a real OS window on desktop, and their buttons are laid out by the engine at
## sizes chosen for a mouse. This project's screens are all full-rect `Control`s under
## `canvas_items` stretch, so a `Window` is the one thing in the UI that does *not* scale
## with everything else — on a phone it lands wherever it likes at whatever size it likes.
##
## The other half is testability: a full-rect Control modal can be built with `.new()`,
## opened, and have its buttons pressed **with no `SceneTree`, no window and no mouse**,
## which is how every other screen in this suite is exercised. A `ConfirmationDialog`
## needs a tree to `popup_centered()` at all.
##
## ## ⚠️ IT DECIDES NOTHING, AND CANCEL IS THE ONE THE FINGER LANDS ON
##
## It emits `confirmed` or `cancelled` and the caller does the work — `ColourPickerPopup`'s
## split, and the reason is the same: the consequence belongs to whoever can see the state
## it consumes. This widget knows nothing about progress files.
##
## **CANCEL takes the focus, not the confirm button.** A modal that appears with the
## destructive option under a return key -- or under a finger that was already travelling
## towards the button that opened it -- is a modal that will eventually be dismissed *into*
## the thing it was guarding against. The confirm button is also the one wearing the warning
## colour, so the two options are told apart by more than their position.
##
## The root is `MOUSE_FILTER_STOP` and so is the dim behind it: while this is open, a press
## that misses the frame must not reach the screen underneath. On the campaign screen that
## screen is a list of rows that each change scene.
class_name ConfirmOverlay
extends Control

## The player pressed the confirm button. The caller does the deed.
signal confirmed()
signal cancelled()

const _DIM := Color(0.0, 0.0, 0.0, 0.72)
const _PANEL := Color(0.16862746, 0.11372549, 0.078431375, 1.0)
const _PARCHMENT := Color(0.9372549, 0.8784314, 0.7529412, 1.0)
const _GOLD := Color(0.8980392, 0.7215686, 0.25882354, 1.0)

## The confirm button's ink, and the same colour `CampaignScreen` puts on the button that
## opens this — so the control and the modal are visibly one action.
##
## Not a red FILL: a solid red block reads as an error that has already happened rather than
## as a choice about to be made. And a LIGHT coral rather than a saturated red, because the
## theme's button plate is itself dark red and a mid red on it reads as greyed out —
## `CampaignScreen._DANGER` records what that looked like.
const _DANGER := Color(1.0, 0.61960787, 0.5176471, 1.0)

## Wide enough for a sentence of body text at 16 px without the panel becoming a column of
## three-word lines, and narrow enough to sit inside the 1152-wide base viewport with the
## dimmed screen still visible around it — which is what tells the player it is a modal.
const PANEL_WIDTH := 560.0

## Big enough to hit with a thumb (`ScenarioScreen` and the footer buttons use the same
## 58 px height), and equal for both, so neither option is physically easier than the other.
const BUTTON_SIZE := Vector2(200.0, 58.0)

var _title: Label
var _body: Label
var _confirm: Button
var _cancel: Button


func _init() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = _DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP rather than IGNORE, unlike every other backdrop in this project. This one is a
	# modal's backdrop: swallowing the press IS its job.
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _panel_style())
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.grow_horizontal = Control.GROW_DIRECTION_BOTH
	frame.grow_vertical = Control.GROW_DIRECTION_BOTH
	frame.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	add_child(frame)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 28)
	pad.add_theme_constant_override("margin_right", 28)
	pad.add_theme_constant_override("margin_top", 24)
	pad.add_theme_constant_override("margin_bottom", 24)
	frame.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	pad.add_child(column)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", _GOLD)
	UiFont.title(_title, 24, true)
	column.add_child(_title)

	_body = Label.new()
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_color_override("font_color", _PARCHMENT)
	_body.add_theme_font_size_override("font_size", 16)
	column.add_child(_body)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	column.add_child(row)

	# CANCEL FIRST, on the left, and it is the one that gets the focus. See the header.
	_cancel = Button.new()
	_cancel.custom_minimum_size = BUTTON_SIZE
	UiFont.title(_cancel, 20)
	_cancel.pressed.connect(_on_cancel)
	row.add_child(_cancel)

	_confirm = Button.new()
	_confirm.custom_minimum_size = BUTTON_SIZE
	UiFont.title(_confirm, 20)
	_confirm.add_theme_color_override("font_color", _DANGER)
	_confirm.add_theme_color_override("font_hover_color", _DANGER)
	_confirm.add_theme_color_override("font_pressed_color", _DANGER)
	_confirm.add_theme_color_override("font_focus_color", _DANGER)
	_confirm.pressed.connect(_on_confirm)
	row.add_child(_confirm)


## Ask the question. `confirm_text` is the VERB, not "YES": a button that says what it does
## is still readable by somebody who tapped past the paragraph, which on a destructive
## action is most people.
func open(title: String, body: String, confirm_text: String = "CONFIRM",
		cancel_text: String = "CANCEL") -> void:
	_title.text = title
	_body.text = body
	_confirm.text = confirm_text
	_cancel.text = cancel_text
	visible = true
	# A widget with no tree cannot take focus and does not need to -- the suite presses
	# buttons directly. Guarded rather than assumed, because `grab_focus` on an unparented
	# Control pushes an engine error, and this class is built with `.new()` all through the
	# tests.
	if is_inside_tree():
		_cancel.grab_focus()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


# ── readers, for the caller and for the suite ────────────────────────────────

func confirm_button() -> Button:
	return _confirm


func cancel_button() -> Button:
	return _cancel


func title_text() -> String:
	return _title.text


func body_text() -> String:
	return _body.text


## The panel: the campaign screen's own ground colour with a gold edge, so the modal is
## recognisably part of the room it opened in rather than Godot's default grey.
##
## OPAQUE, deliberately. A translucent panel over a dimmed list is a paragraph with a
## campaign row showing through the middle of it, and this is the one piece of text in the
## game that has to be read before it is answered.
func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = _PANEL
	style.border_color = _GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style


## Closed BEFORE the signal, both here and in `_on_cancel`, so a handler that changes scene
## or reopens this cannot be fighting a modal that is still up. `ColourPickerPopup` closes
## in the same order for the same reason.
func _on_confirm() -> void:
	close()
	confirmed.emit()


func _on_cancel() -> void:
	close()
	cancelled.emit()
