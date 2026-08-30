## HOW TO PLAY (PLAN.md 1.8): the six annotated screenshots that teach the touch
## controls, one to a page, reached from the main menu's HOW TO button.
##
## THAT BUTTON ANSWERED WITH A TOAST until 2026-08-30 -- "How-to guide is not
## available yet" -- because there was no walkthrough to open and a toast at least
## does not read as broken. The art arrived that day and this screen is the whole of
## what it needed: the images carry their own instructions, drawn onto real captures
## of this game's HUD, so nothing here writes tutorial prose that could drift out of
## step with the interface. If a control moves, the fix is a new capture in
## `assets/HELP_Gen/` and a re-stage, not an edit to this file.
##
## A PAGER, NOT A SCROLL, and that is the one design decision worth defending. The
## credits screen scrolls because credits are a column of text; these are six wide
## screenshots with baked-in captions sized to be read full-screen, and six of them
## stacked in a `ScrollContainer` on a handset gives every one of them a sixth of the
## height it was drawn for. One page at a time hands each image the whole window.
##
## BUILT IN CODE, unlike `Credits.tscn` next door, and deliberately: the page list is
## DATA, and six near-identical `TextureRect` nodes authored by hand in a `.tscn` is
## six places to forget when a seventh capture lands. `Help.tscn` is a three-line
## shell like `Boot.tscn`. It also sidesteps §6 of AGENT_GAME_CODER.md -- Godot
## rewrites a `.tscn`'s layout properties whenever the project is open in the editor.
class_name HelpScreen
extends Control

const _MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"
const _HELP_DIR := "res://assets/ui/help/"

## The reading order, which is not the order the files were delivered in: it is the
## order a new player needs them. Move the camera, then select, then command, then the
## shortcuts that make commanding fast, then the panels around the edge, then the age
## ladder that is the actual game.
##
## `file` is the staged name under `assets/ui/help/`; the owner's originals keep their
## own names in `assets/HELP_Gen/` and the mapping is:
##   zoom_and_pan          <- Zoom_and_Pan.jpg
##   drag_select           <- Drag_SelectBox.jpg
##   move_and_gather       <- Unit_Move_and_Gather_Command.jpg
##   control_groups        <- Control_groups_And_Unit_Actions.jpg
##   minimap_and_panels    <- Mini_MapFunctions.jpg
##   age_up                <- AgeUp.jpg
const PAGES: Array[Dictionary] = [
	{"file": "zoom_and_pan.jpg", "title": "MOVING THE CAMERA"},
	{"file": "drag_select.jpg", "title": "SELECTING SEVERAL UNITS"},
	{"file": "move_and_gather.jpg", "title": "MOVING AND GATHERING"},
	{"file": "control_groups.jpg", "title": "CONTROL GROUPS AND ACTIONS"},
	{"file": "minimap_and_panels.jpg", "title": "THE MINIMAP AND THE PANELS"},
	{"file": "age_up.jpg", "title": "ADVANCING AN AGE"},
]

var _page := 0
var _caption: Label
var _art: TextureRect
var _missing: Label
var _counter: Label
var _prev_button: Button
var _next_button: Button
var _back_button: Button


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# The credits screen's ground colour, so the two pages behind the front door
	# are recognisably the same room.
	var bg := ColorRect.new()
	bg.color = Color(0.16862746, 0.11372549, 0.078431375, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	margin.add_child(page)

	var heading := Label.new()
	heading.text = "HOW TO PLAY"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiFont.title(heading, 30, true)
	page.add_child(heading)

	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiFont.title(_caption, 20)
	page.add_child(_caption)

	# THE PICTURE IS THE ONLY THING THAT GROWS. Everything else on the page has the
	# height its text needs and nothing more.
	var stage := Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(stage)

	_art = TextureRect.new()
	# EXPAND_IGNORE_SIZE IS LOAD-BEARING. A `TextureRect` defaults to
	# `EXPAND_KEEP_SIZE`, whose minimum size is the texture's own -- and these are
	# up to 1476 px wide, which is wider than the whole handset viewport. The page
	# would have been laid out around a picture that could not shrink.
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# LINEAR, like the boot splash and for the same reason: these are photographs,
	# scaled by whatever ratio the device happens to want, and nearest-neighbour
	# resampling of a photograph is visible speckle on every edge.
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_art)

	# Shown only if a page's file is missing, which is a staging mistake rather than
	# a runtime state -- but an empty black rectangle says nothing about which one.
	_missing = Label.new()
	_missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_missing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_missing.set_anchors_preset(Control.PRESET_FULL_RECT)
	_missing.visible = false
	stage.add_child(_missing)

	page.add_child(_build_nav())
	show_page(0)


func _build_nav() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	_back_button = _nav_button("BACK")
	_back_button.pressed.connect(_on_back_pressed)
	row.add_child(_back_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_prev_button = _nav_button("< PREV")
	_prev_button.pressed.connect(previous_page)
	row.add_child(_prev_button)

	_counter = Label.new()
	_counter.custom_minimum_size = Vector2(72.0, 0.0)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_counter)

	_next_button = _nav_button("NEXT >")
	_next_button.pressed.connect(next_page)
	row.add_child(_next_button)

	return row


func _nav_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(132.0, 46.0)
	return button


func page_count() -> int:
	return PAGES.size()


func current_page() -> int:
	return _page


## Clamped rather than wrapped: PREV on page one and NEXT on page six are disabled,
## so the only way to ask for a page outside the range is a caller with a bad index,
## and silently landing on the far end of the guide would be a strange answer to that.
func show_page(index: int) -> void:
	_page = clampi(index, 0, PAGES.size() - 1)
	var entry := PAGES[_page]
	_caption.text = String(entry["title"])

	var path: String = _HELP_DIR + String(entry["file"])
	if ResourceLoader.exists(path):
		_art.texture = load(path)
		_art.visible = true
		_missing.visible = false
	else:
		_art.texture = null
		_art.visible = false
		_missing.text = "missing: " + path
		_missing.visible = true

	_counter.text = "%d / %d" % [_page + 1, PAGES.size()]
	_prev_button.disabled = _page == 0
	_next_button.disabled = _page == PAGES.size() - 1


func next_page() -> void:
	show_page(_page + 1)


func previous_page() -> void:
	show_page(_page - 1)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(_MAIN_MENU_SCENE)
