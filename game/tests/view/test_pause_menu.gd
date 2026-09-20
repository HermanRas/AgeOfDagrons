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

## ⛔ THE FOURTH BUTTON MUST FIT INSIDE THE PANEL, AND THIS IS THE ONLY CHECK THAT SAYS SO.
##
## `_panel_size` is derived, not measured: nothing lays this panel out at runtime, so a stack
## taller than its own background does not overflow, clip or scroll -- it draws the last
## button and the note THROUGH the frame, and the only way to find out is to look at it. The
## arithmetic is pure and needs no tree, so it is asserted here rather than left to a
## screenshot somebody has to remember to take.
##
## Asserted as a RELATION against `_panel_size`, so adding a fifth button or a taller note
## fails here rather than on screen.
func test_every_button_and_the_note_fit_inside_the_panel() -> void:
	var stack_bottom := PauseMenu._buttons_top() \
			+ float(PauseMenu._BUTTONS) * PauseMenu._BUTTON_SIZE.y \
			+ float(PauseMenu._BUTTONS - 1) * 14.0
	var note_bottom := stack_bottom + PauseMenu._NOTE_GAP + PauseMenu._NOTE_H
	assert_true(note_bottom <= menu._panel_size.y,
			"the stack ends at %.0f in a panel %.0f tall" % [note_bottom, menu._panel_size.y])


## The count is written once. Two numbers that have to agree is how the panel was one button
## short in the first place.
func test_the_button_count_matches_the_buttons_actually_built() -> void:
	assert_eq(PauseMenu._BUTTONS, 4, "resume, save, resign, quit")


## Pressing SAVE GAME reports it rather than doing the work: this panel owns no world.
func test_save_reports_the_press_and_leaves_the_menu_open() -> void:
	var presses: Array[int] = []
	menu.save_requested.connect(func() -> void: presses.append(1))
	menu.open()
	menu._on_save_pressed()
	assert_eq(presses.size(), 1)
	assert_true(menu.visible, "saving is not leaving -- the menu stays up")


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