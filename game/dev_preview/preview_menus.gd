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
##       -- writes user://menu_main.png and user://menu_campaign.png and quits.
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
			_show("res://scenes/menu/MainMenu.tscn")
		1:
			_report_menu_wiring()
			_shoot("menu_main")
		2:
			# SETTINGS, which is a real screen since 2026-08-23 -- it used to
			# answer with a toast saying settings did not exist. Built in code
			# rather than authored in MainMenu.tscn, so nothing but a photograph
			# says whether the overlay lands inside the window.
			_press_settings()
		3:
			_report_settings()
			_shoot("menu_settings")
		4:
			_show("res://scenes/menu/Campaign.tscn")
		5:
			_report_campaign()
			_shoot("menu_campaign")
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


func _report_campaign() -> void:
	var back: Button = _current.get_node_or_null("%BackButton")
	print("  campaign: back button %s, rect %s"
			% [back != null, back.get_global_rect() if back != null else "-"])
	if back == null:
		push_warning("preview_menus: the campaign screen has no way back")


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
