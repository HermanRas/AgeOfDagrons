## The pause/resign overlay (PLAN.md 8.5). Stops `SimClock` while open -- a
## real pause, not just a panel obscuring a match that keeps ticking underneath.
##
## RESIGN IS A COMMAND NOW (12.1e), not a scene change. The old note here said "Resign"
## and "return to the main menu" were the same action because MVP had no win conditions to
## concede against; there are win conditions now, so conceding is a real act with a real
## outcome and it goes to the simulation like every other one. See `_on_resign_pressed`.
##
## **A CLIENT'S PAUSE IS LOCAL AND THE HOST KEEPS TICKING**, which is worth knowing and is
## not fixed here. `SimClock.stop()` stops this device's clock; on a joined client that
## clock is not what steps the world, so the match carries on without them and snapshots
## keep arriving. Pausing a networked match needs the host's agreement -- a pause request,
## and a rule about who may pause -- which is a design question rather than a defect, and
## a bigger one than 12.1e.
class_name PauseMenu
extends Control

const _MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"
const _PANEL_BG_PATH := "res://assets/ui/chrome/panel_hud.png"
const _BUTTON_SIZE := Vector2(240.0, 76.0)

## WHERE THE VOLUME BLOCK STARTS. 32 since 2026-08-30, down from 80 -- and the 80 is
## worth recording because it was not padding, it was a workaround. Kibyra's
## `panel_background.png` carried a large dragon ornament across its top and the first
## slider drew BEHIND it with its label above the panel's own edge; the buttons never
## showed it because the first one starts lower down. `chrome/panel_hud.png` is a plain
## nine-patch with a 12 px border and no ornament, so the workaround is gone and this is
## simply a gutter.
const _VOLUME_TOP := 32.0

## Horizontal inset for the volume block, 12 px tighter each side than the
## buttons. The buttons are textures with padding baked into the art, so a
## bare `Label` at the same x sits right on the frame's border and reads as
## overflowing it.
const _VOLUME_WIDTH := 216.0

## Between the last slider and the first button.
const _VOLUME_GAP := 20.0

signal resumed()

## Sized to fit BOTH stacks rather than guessed: the volume block above (measured
## by `VolumePanel.height()`, not restated here) and the three 76 px buttons below.
## It was 320 and had 24 px spare, which is exactly what PLAN.md 13.2 item 11 meant
## by the SETTINGS page having nowhere to put a slider.
var _panel_size := Vector2(300.0, _buttons_top() + 3.0 * _BUTTON_SIZE.y + 2.0 * 14.0 + 24.0)
var _resign_button: Button
## Shared with the front door's SETTINGS button rather than built twice here --
## see `VolumePanel`.
var _volume: VolumePanel


## Where the button stack begins: below the volume block. A function, not a
## constant, because `_panel_size` is derived from it and a constant would have to
## restate `VolumePanel.height()` -- which is the drift this is avoiding.
static func _buttons_top() -> float:
	return _VOLUME_TOP + VolumePanel.height() + _VOLUME_GAP


func _init() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel_root := Control.new()
	panel_root.set_anchors_preset(Control.PRESET_CENTER)
	panel_root.position = -_panel_size * 0.5
	add_child(panel_root)

	if ResourceLoader.exists(_PANEL_BG_PATH):
		var bg := NinePatchRect.new()
		bg.texture = load(_PANEL_BG_PATH)
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		bg.patch_margin_left = HudStyle.PANEL_MARGIN
		bg.patch_margin_right = HudStyle.PANEL_MARGIN
		bg.patch_margin_top = HudStyle.PANEL_MARGIN
		bg.patch_margin_bottom = HudStyle.PANEL_MARGIN
		bg.size = _panel_size
		panel_root.add_child(bg)

	# SOUND FIRST, because it is the only thing here that is actually a SETTING --
	# the three below it leave the match. This is the settings page (it is reached
	# from the SETTINGS corner button, see GameScene) and until now it held no
	# settings at all.
	_volume = VolumePanel.new(_VOLUME_WIDTH)
	_volume.position = Vector2((_panel_size.x - _VOLUME_WIDTH) * 0.5, _VOLUME_TOP)
	panel_root.add_child(_volume)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	buttons.position = Vector2((_panel_size.x - _BUTTON_SIZE.x) * 0.5, _buttons_top())
	panel_root.add_child(buttons)

	buttons.add_child(_menu_button("RESUME", _on_resume_pressed))
	# Held rather than added anonymously, so a preview can press the REAL button. What this
	# one does changed completely in 12.1e -- it used to leave the match, it now concedes
	# one -- and calling the handler directly would prove the handler and not the wiring.
	#
	# ITS LABEL WAS `main_menu_button.png` AND SAID "MAIN MENU", which was a lie about what
	# pressing it does and had been since 12.1e: it concedes the match and STAYS, and the
	# way back to the menu is on the defeat screen that follows. The word was painted into
	# a third-party file nobody was going to re-render; a `Button` with text costs nothing
	# to correct, which is most of the argument for this whole change.
	_resign_button = _menu_button("RESIGN", _on_resign_pressed)
	buttons.add_child(_resign_button)
	buttons.add_child(_menu_button("QUIT", func() -> void: get_tree().quit()))


func open() -> void:
	visible = true
	# Re-read rather than trust what the sliders were built with: the front door
	# has its own copy of this panel, and whichever was touched last is the truth.
	if _volume != null:
		_volume.refresh()
	SimClock.stop()


func _on_resume_pressed() -> void:
	visible = false
	SimClock.start()
	resumed.emit()


## CONCEDE, rather than quietly leave (PLAN.md 12.1e).
##
## This used to call `Net.leave()` and change scene, which told the simulation nothing. On
## a client the host kept the resigning player alive with all their buildings, so the match
## could never resolve; on a HOST it tore the session down and ended everybody's match.
##
## Now it submits a `ResignCommand` and STAYS. The player is marked defeated by the sim,
## the next snapshot says so, and `GameScene._refresh_result` shows the defeat screen --
## which is the same screen that already carries the way back to the menu, so this is not a
## dead end. It also means the loser sees they lost instead of being dropped at the main
## menu with no account of it.
##
## THE CLOCK IS RESUMED FIRST, and the order matters: opening this menu stops `SimClock`,
## and a command queued against a stopped clock is a command that is never stepped. It
## would sit there while the player waited for a defeat screen that could not arrive.
func _on_resign_pressed() -> void:
	visible = false
	SimClock.start()
	resumed.emit()
	Net.submit_command(ResignCommand.new(Net.local_player_id()))


## A menu button. TAKES THE WORD, where it used to take a FILENAME.
##
## The three files it named -- resume/main_menu/quit_button.png -- differed from each
## other only in which word was printed on them, and from `assets/ui/menu/`'s other six
## in the same way. One plate in three states now lives in `assets/ui/aod_theme.tres`
## and reaches every Button in the project, so this function has nothing to load: the
## look comes from the theme and the word comes from the argument.
##
## No `texture_filter` line either, and that is the point of the theme rather than an
## omission -- the plate is a nine-patch StyleBoxTexture and the engine filters it.
func _menu_button(label: String, on_pressed: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 22)
	btn.custom_minimum_size = _BUTTON_SIZE
	btn.pressed.connect(on_pressed)
	return btn
