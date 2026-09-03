## Dev check for the front door (PLAN.md 1.1/1.2/12.3): where PLAY and MULTIPLAYER
## go, and what the CAMPAIGN placeholder looks like when you get there.
##
## Exists because PLAY changed target on 2026-08-21. It used to open the skirmish
## screen, the same place MULTIPLAYER opens -- 1.6's one screen is both -- and now
## opens the campaign placeholder instead, so each front-door button leads somewhere
## only it leads. That is a one-line change and there is no headless test for it: what
## a `change_scene_to_file` opens cannot be asserted without letting it happen.
##
## SO IT DOES NOT LET IT HAPPEN. Following the scene change would replace this
## preview and take the script with it, so the two halves are checked separately:
## which scene each button is WIRED to (read off the real button's connection), and
## what the campaign screen LOOKS like (instantiated directly and photographed).
## Between them that is the whole change.
##
## Usage:
##   Godot --path game res://dev_preview/preview_menus.tscn
##       -- photographs every screen behind the front door in turn and quits:
##       menu_boot, menu_main, menu_settings, menu_campaign, menu_help,
##       menu_help_last and menu_lobby, all under user://.
extends Node

const SHOT_DIR := "user://"
const SETTLE_FRAMES := 30
const STEP_FRAMES := 20

var _frames := 0
var _step := 0
var _current: Node = null


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < SETTLE_FRAMES + _step * STEP_FRAMES:
		return
	match _step:
		0:
			# THE SPLASH, and it is safe to instantiate here only because it is thrown
			# away again two steps later. `boot_screen.gd` starts a 2 s timer that calls
			# `change_scene_to_file` -- which would replace the preview's own scene and
			# take this script with it. Forty frames is well inside that.
			_show("res://scenes/menu/Boot.tscn")
		1:
			_report_boot()
			_shoot("menu_boot")
		2:
			_show("res://scenes/menu/MainMenu.tscn")
		3:
			_report_menu_wiring()
			_shoot("menu_main")
		4:
			# SETTINGS, which is a real screen since 2026-08-23 -- it used to
			# answer with a toast saying settings did not exist. Built in code
			# rather than authored in MainMenu.tscn, so nothing but a photograph
			# says whether the overlay lands inside the window.
			_press_settings()
		5:
			_report_settings()
			_shoot("menu_settings")
		6:
			_show("res://scenes/menu/Campaign.tscn")
		7:
			_report_campaign()
			_shoot("menu_campaign")
		8:
			# HOW TO PLAY (1.8), which HOW TO opened for the first time on 2026-08-30.
			# Six annotated captures at up to 1476 px wide in a window a third of that:
			# whether the picture fits inside the page is exactly the sort of thing only
			# a photograph answers.
			_show("res://scenes/menu/Help.tscn")
		9:
			_report_help()
			_shoot("menu_help")
		10:
			# The last page, because it is the one where the picture is tallest relative
			# to the caption and where NEXT has to have gone grey.
			(_current as HelpScreen).show_page(HelpScreen.PAGES.size() - 1)
		11:
			_shoot("menu_help_last")
		12:
			# THE LOBBY, which had no photograph at all until 2026-08-30 -- it was only
			# ever covered by `test_skirmish_screen`, which asserts the CONFIG it would
			# build and can say nothing about whether the controls fit on the page. The
			# starting-age picker landed that day and added a row to the busiest column
			# on the screen, which is precisely the change a test like that cannot see.
			#
			# Instantiated directly, never navigated to: following a scene change would
			# replace this preview and take the script with it (see the header).
			_show("res://scenes/menu/Skirmish.tscn")
		13:
			_report_lobby()
			_shoot("menu_lobby")
		_:
			get_tree().quit()
			return
	_step += 1


## Put one screen on display, replacing whatever was there. A child of THIS node
## rather than the current scene, so nothing any of these screens does can unload the
## preview mid-run.
func _show(path: String) -> void:
	if _current != null:
		_current.queue_free()
	_current = load(path).instantiate()
	add_child(_current)


## WHICH SCENE EACH BUTTON IS WIRED TO, read off the real buttons.
##
## The handler names are the assertion: PLAY and MULTIPLAYER shared one for as long as
## there was one screen to share, and the whole of this change is that they no longer
## do. A connection list is what tells "PLAY opens the campaign" from "PLAY still
## opens the lobby" without following either.
func _report_menu_wiring() -> void:
	for name in ["PlayButton", "MultiplayerButton", "CreditsButton"]:
		var button: Button = _current.get_node_or_null("%" + name)
		if button == null:
			push_warning("preview_menus: no %s on the main menu" % name)
			continue
		var targets := _handlers(button)
		print("  %s -> %s" % [name, targets])
		if targets.is_empty():
			push_warning("preview_menus: %s is wired to nothing" % name)

	var play: Button = _current.get_node_or_null("%PlayButton")
	var multi: Button = _current.get_node_or_null("%MultiplayerButton")
	if play != null and multi != null:
		var play_targets := _handlers(play)
		var multi_targets := _handlers(multi)
		if not play_targets.is_empty() and play_targets == multi_targets:
			push_warning("preview_menus: PLAY and MULTIPLAYER still go to the same place")


## A button's OWN handlers, with `AudioManager`'s click hook filtered out.
##
## THIS FILTER IS LOAD-BEARING AND WAS ADDED AFTER A FALSE ALARM. `AudioManager`
## connects to `SceneTree.node_added` and gives every `BaseButton` in the game a
## click sound, so `pressed.get_connections()` now has one extra entry on
## everything -- and because the autoload is in the tree before any menu, that
## entry comes FIRST. This function used to read `get_connections()[0]`, which
## after that change reported `_on_any_button_pressed` for both PLAY and
## MULTIPLAYER and warned that they went to the same place. They do not.
##
## Anything else that inspects a button's connections needs the same filter.
func _handlers(button: BaseButton) -> Array[String]:
	var out: Array[String] = []
	for c in button.pressed.get_connections():
		var method := String((c["callable"] as Callable).get_method())
		if method == "_on_any_button_pressed":
			continue
		out.append(method)
	return out


## Press the REAL settings button, not its handler -- the point is the wiring as
## much as the layout, and calling the handler would prove only the handler.
func _press_settings() -> void:
	var button: Button = _current.get_node_or_null("%SettingsButton")
	if button == null:
		push_warning("preview_menus: no SettingsButton on the main menu")
		return
	button.pressed.emit()


## The three sliders, and whether the overlay is actually on screen. A panel laid
## out off the window edge looks identical to one that never opened, which is the
## thing a print cannot tell you and a rect can.
func _report_settings() -> void:
	var sliders: Array[Node] = _current.find_children("*", "HSlider", true, false)
	print("  settings: %d slider(s)" % sliders.size())
	if sliders.size() != 3:
		push_warning("preview_menus: expected 3 volume sliders, got %d" % sliders.size())
	var window := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	for s in sliders:
		var slider: HSlider = s
		var rect := slider.get_global_rect()
		print("    %s at %s value %.2f" % [slider.name, rect, slider.value])
		if not window.encloses(rect):
			push_warning("preview_menus: a volume slider is outside the window: %s" % rect)


## THE SPLASH, AND WHETHER IT FILLS THE WINDOW.
##
## The owner reported it "cutting off" on 2026-08-30 and the mode it was set to,
## `KEEP_ASPECT_CENTERED`, cannot cut anything -- it pillarboxes.
##
## ⚠️ **TWO SEPARATE THINGS DECIDE WHERE THE PAINT LANDS, and the first version of
## this function only looked at one of them.** It assumed a `PRESET_FULL_RECT` control
## is the size of the window and derived the painted region from `stretch_mode` alone.
## It reported a perfect fill on the very run whose screenshot showed the strapline
## sliced off by the bottom edge -- because the control was 1376x768 in a 1152x648
## window, `EXPAND_KEEP_SIZE` having made the texture's own size a MINIMUM that
## anchors cannot override.
##
## So both are printed: the control's real rect, and the region the texture is painted
## into inside it, which is not a property any node exposes and has to be derived.
## Smaller than the window is letterboxing, larger is a crop, equal is what the owner
## asked for.
func _report_boot() -> void:
	var art: TextureRect = null
	for node in _current.find_children("*", "TextureRect", true, false):
		art = node
		break
	if art == null or art.texture == null:
		push_warning("preview_menus: the boot screen has no art on it")
		return
	var window := get_viewport().get_visible_rect().size
	var plate := art.texture.get_size()
	var rect := art.get_global_rect()
	var drawn := rect.size
	match art.stretch_mode:
		TextureRect.STRETCH_SCALE:
			drawn = rect.size
		TextureRect.STRETCH_KEEP_ASPECT_COVERED:
			drawn = plate * maxf(rect.size.x / plate.x, rect.size.y / plate.y)
		_:
			# Every remaining mode either fits inside the rect or ignores it; the
			# two KEEP_ASPECT fits are the ones this screen has actually worn.
			drawn = plate * minf(rect.size.x / plate.x, rect.size.y / plate.y)
	print("  boot: expand %d stretch %d, plate %s, rect %s, window %s, painted %s"
			% [art.expand_mode, art.stretch_mode, plate, rect, window, drawn])
	# The painted region is measured from the control's own top-left, which is where
	# an oversized control puts it -- so this covers both failures at once.
	var painted := Rect2(rect.position + (rect.size - drawn) * 0.5, drawn)
	if painted.position.x > 1.0 or painted.position.y > 1.0 \
			or painted.end.x < window.x - 1.0 or painted.end.y < window.y - 1.0:
		push_warning("preview_menus: the splash letterboxes -- painted %s in %s"
				% [painted, window])
	if painted.position.x < -1.0 or painted.position.y < -1.0 \
			or painted.end.x > window.x + 1.0 or painted.end.y > window.y + 1.0:
		push_warning("preview_menus: the splash is cropped -- painted %s in %s"
				% [painted, window])


## THE HELP PAGER: that every page found its picture, and that the picture is inside
## the page rather than laid out through it.
##
## The pictures are up to 1476x720 and the window is 1152x648, so a `TextureRect` left
## on the default `EXPAND_KEEP_SIZE` would give the page a minimum size wider than the
## window and push the nav row off the bottom. `test_help_screen` asserts the property;
## this asserts the consequence.
func _report_help() -> void:
	var screen := _current as HelpScreen
	if screen == null:
		push_warning("preview_menus: Help.tscn has no HelpScreen on it")
		return
	var window := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	for i in range(screen.page_count()):
		screen.show_page(i)
		var picture: String = "-" if screen._art.texture == null \
				else str(screen._art.texture.get_size())
		print("  help %d/%d  %s  picture %s" % [
				i + 1, screen.page_count(), screen._caption.text, picture])
		if screen._art.texture == null:
			push_warning("preview_menus: help page %d has no picture" % (i + 1))
	screen.show_page(0)
	for name in ["_art", "_prev_button", "_next_button", "_back_button", "_counter"]:
		var control: Control = screen.get(name)
		var rect := control.get_global_rect()
		print("    %s at %s" % [name, rect])
		if not window.encloses(rect):
			push_warning("preview_menus: help %s is off the page: %s" % [name, rect])


## THE CAMPAIGN SCREEN'S FOOTER, AND WHETHER BOTH BUTTONS ARE ON THE PAGE.
##
## ⚠️ **THIS CHECK USED TO BE INCAPABLE OF PASSING.** It looked for `%BackButton`, and
## `CampaignScreen` builds its footer in code without ever setting `unique_name_in_owner` --
## so the lookup was always null and the warning *"the campaign screen has no way back"*
## fired on every single run of this preview. A warning that is always wrong is worse than
## no warning, because it teaches whoever reads the log to skip that line.
##
## Fixed to read the fields directly, which is what `_report_help` next door already does.
##
## The rect check is the half that earns its place now that there are TWO buttons: the
## phone's design viewport is 1404x648 (PLAN.md 3), DOWNLOAD MORE is 280 px wide with BACK
## at 180, and a footer that fits on a desktop preview can still push a button off the edge
## on a handset. That is the lobby's bug (§3's nav strip), and it passes every structural
## test because a node asked for its rect returns that rect whether or not the window
## contains it.
func _report_campaign() -> void:
	var window := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	for name in ["_back_button", "_download_button"]:
		var control: Control = _current.get(name)
		if control == null:
			push_warning("preview_menus: the campaign screen has no %s" % name)
			continue
		var rect := control.get_global_rect()
		print("  campaign: %s '%s' at %s" % [name, control.text, rect])
		if not window.encloses(rect):
			push_warning("preview_menus: campaign %s is off the page: %s" % [name, rect])


## THE LOBBY'S CONTROLS, AND WHETHER THEY ARE ALL ON THE PAGE.
##
## The starting-age picker (2026-08-30) went into the match column, which already
## carried the player count, up to eight slot rows, the victory mode and the buttons --
## so the thing worth checking is not that the picker works, which a test does, but that
## adding a row did not push the START button off the bottom at eight slots.
##
## Every OptionButton is listed with its rect, and any that falls outside the window is
## a warning: a control laid out past the edge looks identical to one that is simply not
## there, which is the failure `_report_settings` already exists to catch.
func _report_lobby() -> void:
	# The ROOT of Skirmish.tscn is the screen itself -- `find_children` only walks
	# descendants, so looking for it would come back empty.
	var screen := _current as SkirmishScreen
	if screen == null:
		push_warning("preview_menus: Skirmish.tscn has no SkirmishScreen on it")
		return
	print("  lobby: starting age %d of %d" % [
			screen.build_config().starting_age, screen._age_picker.item_count])
	for i in range(screen._age_picker.item_count):
		print("    age item %d: %s" % [i, screen._age_picker.get_item_text(i)])

	var window := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	for node in _current.find_children("*", "OptionButton", true, false):
		var picker: OptionButton = node
		var rect := picker.get_global_rect()
		if not window.encloses(rect):
			push_warning("preview_menus: a lobby dropdown is off the page: %s" % rect)
	var start: Button = screen._start_button
	if not window.encloses(start.get_global_rect()):
		push_warning("preview_menus: START is off the page at %s" % start.get_global_rect())


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
