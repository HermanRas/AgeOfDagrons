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

## WHERE THE BUTTON STACK STARTS. 32 since 2026-08-30, down from 80 -- and the 80 is
## worth recording because it was not padding, it was a workaround. Kibyra's
## `panel_background.png` carried a large dragon ornament across its top and the first
## control drew BEHIND it with its label above the panel's own edge; the buttons never
## showed it because the first one starts lower down. `chrome/panel_hud.png` is a plain
## nine-patch with a 12 px border and no ornament, so the workaround is gone and this is
## simply a gutter.
const _STACK_TOP := 32.0

## Horizontal inset for the refusal line, 12 px tighter each side than the buttons. The
## buttons are textures with padding baked into the art, so a bare `Label` at the same x
## sits right on the frame's border and reads as overflowing it.
const _NOTE_WIDTH := 216.0

## How many buttons the stack holds. See `_panel_size` for why this is a number and not
## several literals that have to agree.
##
## ⚠️ **SIX SINCE 2026-09-22, AND THE SIXTH IS WHY THE SLIDERS LEFT.** See `SoundOverlay`:
## five buttons under the old embedded volume block came to 721 px in a 648 px viewport.
const _BUTTONS := 6

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

## SAVE MAP was pressed (2.4c). Carries nothing, for `save_requested`'s reasons: the panel
## does not own the config, the map or the toast.
##
## ⚠️ **A SEPARATE SIGNAL, NOT `save_requested` WITH AN ARGUMENT.** The two do different things
## to the match -- one ends it for every player, the other leaves it running -- and a single
## signal with a flag is one wiring slip away from the wrong one. `preview_destroy_confirm`'s
## header records that exact shape of bug: two buttons joined to one handler photograph
## perfectly and do the wrong thing.
signal save_map_requested()

## Between the button stack and the refusal line under it.
const _NOTE_GAP := 10.0
const _NOTE_H := 34.0

## Sized to fit the stack rather than guessed. It was 320 and had 24 px spare, which is
## exactly what PLAN.md 13.2 item 11 meant by the SETTINGS page having nowhere to put a
## slider.
##
## ⚠️ **THE COUNT IS WRITTEN ONCE.** It read `3.0 *` with `2.0 *` separations beside it --
## two numbers that have to move together, and a panel that is one button short does not
## overflow or clip, it draws the last button THROUGH its own frame. Derived from
## `_BUTTONS` now, so adding another is one row in that array.
##
## ⛔ **AND `_BUTTONS` IS NO LONGER THE ONLY THING THAT CAN OVERFLOW.** Until 2026-09-22 this
## panel also carried the volume sliders, and at six buttons the total would have been 721 px
## against a 648 px viewport -- a panel taller than the screen it centres on does not clip,
## it hangs off both edges at once. `test_pause_menu` now asserts the panel fits the
## VIEWPORT as well as the stack fitting the panel, because only the first of those two was
## ever checked and it is the one that was never going to fail.
var _panel_size := Vector2(300.0, _STACK_TOP
		+ float(_BUTTONS) * _BUTTON_SIZE.y + float(_BUTTONS - 1) * 14.0
		+ _NOTE_GAP + _NOTE_H + 24.0)
var _resign_button: Button
## Held so `open()` can re-ask whether saving is possible, and so a preview can press the
## REAL button rather than the handler behind it.
var _save_button: Button
## The same, for SAVE MAP (2.4c). A separate button with a separate rule -- see
## `_refresh_save`.
var _save_map_button: Button
## Why saving is refused, when it is. See `_refresh_save`.
var _save_note: Label
## The SOUND page, built on first press and kept. A `CanvasLayer`, so it draws over this
## overlay rather than under it -- see `SoundOverlay`, which is also the front door's.
var _sound: SoundOverlay


## Where the button stack begins. A function rather than the constant it now returns,
## because `test_pause_menu` and this file's own note arithmetic both call it and the
## indirection is what let the volume block come out from under the stack without touching
## either.
static func _buttons_top() -> float:
	return _STACK_TOP


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

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	buttons.position = Vector2((_panel_size.x - _BUTTON_SIZE.x) * 0.5, _buttons_top())
	panel_root.add_child(buttons)

	buttons.add_child(_menu_button("RESUME", _on_resume_pressed))
	# SOUND SECOND, because it is the only thing here that is actually a SETTING -- the four
	# below it save or leave the match. This is the settings page (it is reached from the
	# SETTINGS corner button, see GameScene), and until 2026-09-22 the sliders were embedded
	# here rather than behind this button. `SoundOverlay` has the whole argument; the short
	# version is that 2.4c's sixth button and a 185 px volume block do not both fit in 648 px,
	# and the owner chose to keep the 76 px thumb targets.
	buttons.add_child(_menu_button("SOUND", _on_sound_pressed))
	# SAVE MAP (2.4c), ABOVE SAVE & EXIT AND WELL ABOVE RESIGN, because it is the only button
	# on this panel that leaves the match STANDING: you press it, the menu closes, you get a
	# toast and you carry on playing. Its neighbour ends the match for everybody, which is why
	# the two are not adjacent in the way a "save something" pair would suggest -- the word
	# EXIT is doing the work, and this file's own history (a button reading MAIN MENU for a
	# whole phase after it stopped going there) is the argument for not relying on position.
	_save_map_button = _menu_button("SAVE MAP", _on_save_map_pressed)
	buttons.add_child(_save_map_button)
	# ABOVE RESIGN AND QUIT, because it is the only one of the three that lets you come back.
	# A player opening this menu because real life interrupted the match wants this button,
	# and putting it under the two that END a match is an invitation to press the wrong one.
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
	_save_note.size = Vector2(_NOTE_WIDTH, _NOTE_H)
	_save_note.position = Vector2((_panel_size.x - _NOTE_WIDTH) * 0.5,
			_buttons_top() + float(_BUTTONS) * _BUTTON_SIZE.y
			+ float(_BUTTONS - 1) * 14.0 + _NOTE_GAP)
	_save_note.visible = false
	panel_root.add_child(_save_note)

	_refresh_save()


func open() -> void:
	visible = true
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
##
## ## ⛔ SAVE MAP IS NOT HOST-ONLY, AND THAT IS THE WHOLE REASON IT IS A SECOND RULE (2.4c)
##
## The paragraph above is about the WORLD, which only the host has. A MAP is not the world:
## it is `MatchConfig.map_data`, which travels to every client in the config -- `GameScene`
## centres a joined player's camera on `cfg.map_data.starts` on exactly that basis. So a
## client can save the map it is playing, and gating this button on `Net.host()` would be the
## §6 trap in its original form: a refusal that is dead for players 2..8.
##
## What it IS gated on is the map existing. `cfg.map_data` is null for the FIXED DEBUG MAP
## (`Game.tscn` reached with no `Net.pending_match`), which is integer code rather than data
## and has no file to write -- so the button is off there and says why, rather than writing a
## map nobody could load back.
##
## ## ⚠️ ONE NOTE, AND IT NAMES THE BUTTON IT IS ABOUT
##
## Two disabled buttons with two rules could want two sentences, and a second label costs
## another 44 px of a panel that has just been rebuilt to fit. So there is still one line and
## it is chosen by priority -- no session first, because that disables both and is the only
## state where a single sentence is the whole truth.
##
## ⛔ **"Only the host can save & exit" NAMES THE BUTTON DELIBERATELY.** It used to read "save
## this match", which was unambiguous while there was one save button; with SAVE MAP enabled
## directly above it, an unqualified "you cannot save" sitting under an enabled Save button is
## a line that contradicts the screen.
func _refresh_save() -> void:
	if _save_button == null:
		return
	var host := Net.host()
	var can_save := host != null and host.world != null
	_save_button.disabled = not can_save

	var cfg := Net.match_config()
	var can_save_map := cfg != null and cfg.map_data != null
	if _save_map_button != null:
		_save_map_button.disabled = not can_save_map

	var why := ""
	if not Net.has_session():
		why = "There is no match to save."
	elif not can_save_map and not can_save:
		why = "This match has no map file, and only the host can save & exit."
	elif not can_save_map:
		why = "This match was not built from a map file, so there is none to save."
	elif not can_save:
		why = "Only the host can save & exit."
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


## SAVE MAP (2.4c). Closes the menu, resumes the match, and asks `GameScene` for the write.
##
## It does not END the match the way SAVE & EXIT does, and the owner's framing of the split is
## why: Save Map is *"a map layout you liked while you were playing it"*, something you do in
## passing and then carry on with. A button that ended a match to bookmark its terrain would be
## the SAVE GAME/SAVE & EXIT naming mistake again, one panel later.
##
## ## ⛔ IT CLOSES THE MENU, AND THAT IS A BUG FIX RATHER THAN A PREFERENCE (owner, playtest)
##
## This shipped leaving the menu open, on the argument that saving a map is not leaving. The
## argument was sound and the result was unusable: *"after clicking save map the menu remains
## open covering the message behind it showing the map saved."*
##
## ⚠️ **THE TOAST DRAWS UNDERNEATH THIS PANEL, IN EVERY STATE.** `GameScene` adds `_toast` to
## the HUD a hundred lines before it adds the pause menu, and later siblings draw on top -- so
## the one sentence telling the player the press worked appears behind a full-rect 55% dim.
## There is no arrangement in which that is readable, which makes the confirmation useless
## exactly where it is the feature's ONLY feedback. `ScenarioScreen` records the same ordering
## trap from the other side: *"an alert raised after an overlay is drawn BEHIND it"*.
##
## ## ⚠️ WHY CLOSING IS SAFE HERE AND WOULD NOT BE ON THE BUTTON ABOVE
##
## Closing restarts `SimClock`, so the world steps again at once -- harmless *only* because
## what gets written is `MatchConfig.map_data`, immutable config the match was built FROM.
## `SAVE & EXIT` captures the live `SimWorld`, which must not step between the press and
## `SaveGame.capture()` reading it, and must stay open so a FAILED save leaves the player
## somewhere rather than nowhere. Same panel, two buttons, opposite rules.
func _on_save_map_pressed() -> void:
	# CLOSED BEFORE THE SIGNAL rather than after, so the toast `GameScene` raises has nothing
	# over it by the time it is drawn. `_on_resign_pressed` sets the same order for its own
	# reason, and the shape is worth copying: leave the screen, then do the thing.
	visible = false
	SimClock.start()
	resumed.emit()
	save_map_requested.emit()


## SOUND. Built on first press and kept, `MainMenu`'s rule: a page authored in code cannot be
## silently reformatted by the editor, and building it lazily keeps a `PauseMenu.new()` in a
## headless test from constructing three sliders it will never show.
##
## ⚠️ **ADDED TO THIS PANEL, NOT TO THE SCENE ROOT.** It is a `CanvasLayer` at layer 10, so it
## draws above this overlay wherever it sits in the tree -- and parenting it here means it goes
## away with the pause menu rather than outliving the match on some HUD node.
func _on_sound_pressed() -> void:
	if _sound == null:
		_sound = SoundOverlay.new()
		add_child(_sound)
	_sound.open()


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
