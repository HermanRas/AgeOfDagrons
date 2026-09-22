## PLAN.md 8.5. Resign/Quit both call get_tree() unconditionally (only ever
## pressed while actually on screen, i.e. actually in a tree), so -- like
## MainMenu's PLAY/CREDITS buttons -- they are verified live rather than
## headlessly; only the open/resume state machine is asserted here.
extends TestCase

var menu: PauseMenu


func before_each() -> void:
	menu = PauseMenu.new()


func after_each() -> void:
	menu.free()


func test_starts_closed() -> void:
	assert_false(menu.visible)


func test_open_shows_the_menu() -> void:
	menu.open()
	assert_true(menu.visible)


func test_resume_hides_the_menu_and_emits_resumed() -> void:
	# Array, not an int local: GDScript closures capture primitives by value,
	# so `count += 1` inside the lambda would mutate a copy (test_input_router.gd
	# hit the same thing first).
	var resumed_count: Array[int] = []
	menu.resumed.connect(func() -> void: resumed_count.append(1))
	menu.open()
	menu._on_resume_pressed()
	assert_false(menu.visible)
	assert_eq(resumed_count.size(), 1)

# -- the SAVE GAME button (12.4) ----------------------------------------------------------

## ⛔ EVERY BUTTON MUST FIT INSIDE THE PANEL, AND THIS IS THE ONLY CHECK THAT SAYS SO.
##
## `_panel_size` is derived, not measured: nothing lays this panel out at runtime, so a stack
## taller than its own background does not overflow, clip or scroll -- it draws the last
## button and the note THROUGH the frame, and the only way to find out is to look at it. The
## arithmetic is pure and needs no tree, so it is asserted here rather than left to a
## screenshot somebody has to remember to take.
##
## Asserted as a RELATION against `_panel_size`, so another button or a taller note fails
## here rather than on screen.
func test_every_button_and_the_note_fit_inside_the_panel() -> void:
	var stack_bottom := PauseMenu._buttons_top() \
			+ float(PauseMenu._BUTTONS) * PauseMenu._BUTTON_SIZE.y \
			+ float(PauseMenu._BUTTONS - 1) * 14.0
	var note_bottom := stack_bottom + PauseMenu._NOTE_GAP + PauseMenu._NOTE_H
	assert_true(note_bottom <= menu._panel_size.y,
			"the stack ends at %.0f in a panel %.0f tall" % [note_bottom, menu._panel_size.y])


## ⛔ AND THE PANEL ITSELF MUST FIT THE SCREEN, WHICH NOTHING CHECKED UNTIL 2.4c.
##
## The test above compares the stack against the panel, and it could never have failed on the
## change that actually broke this: growing the stack grows `_panel_size` with it, so the two
## stayed in step all the way past the edge of the viewport. At six buttons with the volume
## block still embedded the panel came to **721 px in a 648 px window** -- and because it is
## centred, that does not clip at the bottom, it hangs 36 px off the top AND the bottom, with
## the first control and QUIT both unreachable.
##
## 648 is the project's design height (`1152x648`, Godot's default with no override in
## `project.godot`, and the size `1.x-lobby-fit` was fought at). Asserted against the constant
## rather than a live viewport so it holds headlessly.
func test_the_panel_fits_the_design_viewport() -> void:
	const DESIGN_HEIGHT := 648.0
	assert_true(menu._panel_size.y <= DESIGN_HEIGHT,
			"a %.0f px panel centred in %.0f px hangs %.0f px off BOTH edges"
			% [menu._panel_size.y, DESIGN_HEIGHT,
			(menu._panel_size.y - DESIGN_HEIGHT) * 0.5])


## The count is written once. Two numbers that have to agree is how the panel was one button
## short in the first place.
func test_the_button_count_matches_the_buttons_actually_built() -> void:
	assert_eq(PauseMenu._BUTTONS, 6, "resume, sound, save map, save & exit, resign, quit")


## Pressing SAVE & EXIT reports it rather than doing the work: this panel owns no world.
##
## ⚠️ **THE MENU STAYS UP EVEN THOUGH SAVING NOW LEAVES**, and that is the assertion worth
## having. The leaving is `GameScene`'s and happens only on a SUCCESSFUL write -- so a panel
## that closed itself here would strand a failed save with nothing on screen and no clock
## running. The stopped clock also means the world cannot step between the press and
## `SaveGame.capture()` reading it.
func test_save_reports_the_press_and_leaves_the_menu_open() -> void:
	var presses: Array[int] = []
	menu.save_requested.connect(func() -> void: presses.append(1))
	menu.open()
	menu._on_save_pressed()
	assert_eq(presses.size(), 1)
	assert_true(menu.visible, "a failed save has to land back here")


## ⛔ THE WORD ON THE BUTTON IS THE HALF PLAYERS ACT ON.
##
## Saving ends the match for everybody (owner, 2026-09-20), so a button reading SAVE GAME
## beside one reading RESUME would promise a bookmark and take the match away. This file's
## own history is the argument: the resign button wore art saying MAIN MENU for a whole phase
## after it stopped going there. Pinned here because nothing else can see a label.
func test_the_save_button_says_that_it_exits() -> void:
	assert_eq(menu._save_button.text, "SAVE & EXIT")


## ⛔ NO WORLD MEANS THE BUTTON IS OFF **AND** SAYS WHY.
##
## Two facts, computed separately -- `ServerBrowserPanel`'s JOIN button is the worked example
## of deriving one from the other and coming out enabled in the state that needed no sentence.
## Outside a match there is no host, so this is the state a bare `PauseMenu.new()` is in.
func test_with_no_match_saving_is_refused_out_loud() -> void:
	menu.open()
	assert_true(menu._save_button.disabled, "there is no world to capture")
	assert_true(menu._save_note.visible, "and the reason is on screen")
	assert_false(menu._save_note.text.is_empty())

# -- the SAVE MAP button (2.4c) ------------------------------------------------------------

## The word, pinned for `test_the_save_button_says_that_it_exits`' reason. These two sit two
## rows apart on one panel and one of them ends the match for every player in it.
func test_the_save_map_button_says_map() -> void:
	assert_eq(menu._save_map_button.text, "SAVE MAP")


## ⛔ PRESSING IT CLOSES THE MENU, AND THE CONFIRMATION IS UNREADABLE OTHERWISE.
##
## This asserted the opposite until the owner playtested it: *"after clicking save map the menu
## remains open covering the message behind it showing the map saved."* `GameScene` adds
## `_toast` to the HUD long before it adds the pause menu, so a banner raised under an open
## menu draws behind its full-rect dim -- and a toast is the only feedback this feature has.
##
## ⚠️ **PINNED HERE BECAUSE THE OLD BEHAVIOUR WAS DEFENSIBLE IN PROSE.** "Saving a map is not
## leaving the match, so the menu stays" reads perfectly and produced a button that looked
## broken in the hand. Nothing headless can see a covered banner, so what this file can check
## is the panel getting out of its way.
func test_save_map_closes_the_menu_so_the_toast_is_visible() -> void:
	var presses: Array[int] = []
	menu.save_map_requested.connect(func() -> void: presses.append(1))
	menu.open()
	menu._on_save_map_pressed()
	assert_eq(presses.size(), 1)
	assert_false(menu.visible, "the menu must not cover the banner that reports the save")


## The clock has to come back with it. `open()` stopped it, and a menu that hides itself
## without restarting the clock leaves the player looking at a frozen match with no menu on it
## -- which is the same class of dead end `_on_resign_pressed`'s comment describes.
func test_save_map_resumes_the_match_it_did_not_end() -> void:
	menu.open()
	menu._on_save_map_pressed()
	assert_true(SimClock.is_running(), "the match carries on after a map is saved")


## ⛔ THE TWO SAVE BUTTONS MUST NOT SHARE A SIGNAL.
##
## `preview_destroy_confirm`'s header records what this shape of slip costs: two buttons
## joined to one handler photograph perfectly and do the wrong thing. Here the wrong thing is
## ending a match for eight people because somebody wanted to keep a map.
func test_the_two_save_buttons_are_wired_to_different_signals() -> void:
	var saves: Array[int] = []
	var maps: Array[int] = []
	menu.save_requested.connect(func() -> void: saves.append(1))
	menu.save_map_requested.connect(func() -> void: maps.append(1))

	menu._on_save_map_pressed()
	assert_eq(maps.size(), 1, "SAVE MAP raised save_map_requested")
	assert_eq(saves.size(), 0, "and must not have raised save_requested")

	menu._on_save_pressed()
	assert_eq(saves.size(), 1, "SAVE & EXIT raised save_requested")
	assert_eq(maps.size(), 1, "and must not have raised save_map_requested")


## Outside a match there is no config, so there is no map either -- and the note covers both
## buttons with one sentence, which is the only state where one sentence is the whole truth.
func test_with_no_match_saving_a_map_is_refused_too() -> void:
	menu.open()
	assert_true(menu._save_map_button.disabled, "there is no map to write")
	assert_true(menu._save_note.visible)


## ⛔ THE SOUND PAGE IS BUILT ON FIRST PRESS, NOT IN `_init`.
##
## Two reasons and both are load-bearing. A `PauseMenu.new()` in a headless test would
## otherwise construct three sliders it never shows; and the sliders are only here at all
## because 2.4c's sixth button pushed them out of the panel, so a version that built them
## eagerly would be paying the old cost for the new layout.
func test_the_sound_page_is_lazy_and_opens_on_press() -> void:
	assert_null(menu._sound, "nothing builds the sliders until somebody asks")
	menu._on_sound_pressed()
	assert_not_null(menu._sound)
	assert_true(menu._sound.visible)


## The page has to clear the screen too, and it is a second panel with its own arithmetic.
## `SoundOverlay.height()` is derived from `VolumePanel.height()`, so a fourth slider row
## fails here rather than off the bottom of a phone.
func test_the_sound_page_fits_the_design_viewport() -> void:
	assert_true(SoundOverlay.height() <= 648.0,
			"the SOUND page is %.0f px tall" % SoundOverlay.height())