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

## How many buttons the stack holds. See `_panel_size` for why this is a number and not
## three literals that have to agree.
const _BUTTONS := 4

signal resumed()

## SAVE GAME was pressed (12.4). Carries nothing: this panel does not own the world, the
## config or the toast, and `GameScene` owns all three.
##
## ⚠️ **A SIGNAL RATHER THAN A `SaveFile.write()` CALL HERE**, on the same argument
## `_on_resign_pressed` makes for submitting a command instead of changing scene: the panel's
## job is to say a button was pressed. It also keeps `Net.host().world` -- which is null on a
## joined client and is the trap this file would otherwise have to re-learn -- inside the one
## file that already handles it everywhere.
signal save_requested()

## Between the button stack and the refusal line under it.
const _NOTE_GAP := 10.0
const _NOTE_H := 34.0

## Sized to fit BOTH stacks rather than guessed: the volume block above (measured
## by `VolumePanel.height()`, not restated here) and the four 76 px buttons below.
## It was 320 and had 24 px spare, which is exactly what PLAN.md 13.2 item 11 meant
## by the SETTINGS page having nowhere to put a slider.
##
## ⚠️ **FOUR BUTTONS SINCE 12.4, AND THE COUNT IS WRITTEN ONCE.** It read `3.0 *` with `2.0 *`
## separations beside it -- two numbers that have to move together, and a panel that is one
## button short does not overflow or clip, it draws the last button THROUGH its own frame.
## Derived from `_BUTTONS` now, so adding a fifth is one row in that array.
var _panel_size := Vector2(300.0, _buttons_top()
		+ float(_BUTTONS) * _BUTTON_SIZE.y + float(_BUTTONS - 1) * 14.0
		+ _NOTE_GAP + _NOTE_H + 24.0)
var _resign_button: Button
## Held so `open()` can re-ask whether saving is possible, and so a preview can press the
## REAL button rather than the handler behind it.
var _save_button: Button
## Why saving is refused, when it is. See `_refresh_save`.
var _save_note: Label
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
	# SECOND, above RESIGN and QUIT, because it is the only one of the three that lets you
	# come back. A player opening this menu because real life interrupted the match wants
	# this button, and putting it under the two that END a match is an invitation to press
	# the wrong one.
	#
	# ⚠️ **"SAVE & EXIT", NOT "SAVE GAME", SINCE 2026-09-20.** Saving now ends the match for
	# every player in it (owner's ruling; `Net.end_match_saved` has the argument), and a button
	# saying SAVE GAME beside one saying RESUME promises a bookmark you keep playing past.
	# This file already records what that mistake costs three comments down: the resign button
	# wore `main_menu_button.png` and said MAIN MENU for a whole phase after it stopped doing
	# that. The word is the cheap half of a feature and it is the half players act on.
	_save_button = _menu_button("SAVE & EXIT", _on_save_pressed)
	buttons.add_child(_save_button)
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

	# THE REFUSAL LINE. Autowrapped, so it is sized by the panel rather than by its own text
	# -- `HudPanel.note_label`'s row in AGENT_GAME_CODER §6 is the same widget making the
	# opposite mistake in an HBox, and the reason it is safe here is that nothing sits beside
	# it. Width is given, height follows.
	_save_note = Label.new()
	_save_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_save_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_note.add_theme_font_size_override("font_size", 14)
	_save_note.size = Vector2(_VOLUME_WIDTH, _NOTE_H)
	_save_note.position = Vector2((_panel_size.x - _VOLUME_WIDTH) * 0.5,
			_buttons_top() + float(_BUTTONS) * _BUTTON_SIZE.y
			+ float(_BUTTONS - 1) * 14.0 + _NOTE_GAP)
	_save_note.visible = false
	panel_root.add_child(_save_note)

	_refresh_save()


func open() -> void:
	visible = true
	# Re-read rather than trust what the sliders were built with: the front door
	# has its own copy of this panel, and whichever was touched last is the truth.
	if _volume != null:
		_volume.refresh()
	# RE-ASKED ON EVERY OPEN, not answered once in `_init`. This panel is built before the
	# session settles -- the front door builds its own copy with no match at all -- so a
	# state read at construction describes a moment that has nothing to do with whether the
	# match now running can be saved.
	_refresh_save()
	SimClock.stop()


## Whether SAVE GAME may be pressed, and what to say when it may not.
##
## ## ⛔ TWO FACTS, COMPUTED SEPARATELY, BECAUSE ONLY ONE OF THEM IS ALWAYS EXPRESSIBLE
##
## `ServerBrowserPanel`'s JOIN button is the worked example in AGENT_GAME_CODER §6: it set
## `disabled` from *"is there a sentence to print"* and came out enabled in the one state that
## needed no sentence. So "can this be saved" and "what do I tell you" are answered one at a
## time here, and the button's state never depends on whether a message exists.
##
## ## ⛔ A JOINED CLIENT HAS NO WORLD TO SAVE, AND THIS IS THE ONE PLACE THAT IS NOT A BUG
##
## `Net.host()` is null on every joined client -- the trap §6 records, where `if Net.host()
## != null and <rule>` shipped three refusals that were dead for players 2..8. This is the
## inverse and it is genuine: `SaveGame.capture()` needs the authoritative `SimWorld`, and a
## client holds snapshots of what it can see, not the match. Saving from one would write a
## file of the fog.
##
## ⚠️ So it is REFUSED OUT LOUD rather than hidden. A missing button reads as a build that
## does not have the feature; a disabled one with a line under it reads as the truth, which is
## that the host has to do it. The multiplayer half of 12.4 is what changes this.
func _refresh_save() -> void:
	if _save_button == null:
		return
	var host := Net.host()
	var can_save := host != null and host.world != null
	_save_button.disabled = not can_save

	var why := ""
	if not can_save:
		why = "Only the host can save this match."
		if not Net.has_session():
			why = "There is no match to save."
	if _save_note != null:
		_save_note.text = why
		_save_note.visible = not why.is_empty()


## SAVE & EXIT. The panel reports the press and `GameScene` does the work -- see the signal.
##
## ⚠️ **THE MENU STAYS OPEN AND THE CLOCK STAYS STOPPED, AND THAT IS STILL RIGHT EVEN THOUGH
## SAVING NOW LEAVES.** It used to read *"saving is not leaving"*, which stopped being true on
## 2026-09-20. The behaviour does not change with it, for the other reason the old note gave:
## the world must not step between this press and `SaveGame.capture()` reading it. And if the
## save FAILS, `GameScene` leaves the player exactly here -- on a stopped clock with the menu
## up -- which is only possible because this function did not close anything.
func _on_save_pressed() -> void:
	save_requested.emit()


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
