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
