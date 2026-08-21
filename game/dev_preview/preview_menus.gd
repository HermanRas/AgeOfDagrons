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
			_show("res://scenes/menu/Campaign.tscn")
		3:
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
		var button: TextureButton = _current.get_node_or_null("%" + name)
		if button == null:
			push_warning("preview_menus: no %s on the main menu" % name)
			continue
		var targets: Array[String] = []
		for c in button.pressed.get_connections():
			targets.append(String((c["callable"] as Callable).get_method()))
		print("  %s -> %s" % [name, targets])
		if targets.is_empty():
			push_warning("preview_menus: %s is wired to nothing" % name)

	var play: TextureButton = _current.get_node_or_null("%PlayButton")
	var multi: TextureButton = _current.get_node_or_null("%MultiplayerButton")
	if play != null and multi != null:
		var play_target := String((play.pressed.get_connections()[0]["callable"]
				as Callable).get_method())
		var multi_target := String((multi.pressed.get_connections()[0]["callable"]
				as Callable).get_method())
		if play_target == multi_target:
			push_warning("preview_menus: PLAY and MULTIPLAYER still go to the same place")


func _report_campaign() -> void:
	var back: TextureButton = _current.get_node_or_null("%BackButton")
	print("  campaign: back button %s, rect %s"
			% [back != null, back.get_global_rect() if back != null else "-"])
	if back == null:
		push_warning("preview_menus: the campaign screen has no way back")


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
