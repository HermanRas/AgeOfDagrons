## The pause/resign overlay (PLAN.md 8.5). Stops `SimClock` while open -- a
## real pause, not just a panel obscuring a match that keeps ticking
## underneath -- and Resign tears the session down through `Net.leave()`
## before returning to the main menu, the same teardown a rejoin would need
## (PLAN.md 7.1) rather than leaving a stale host running behind the scene
## switch.
##
## MVP has no AI opponents or win conditions (PLAN.md 10's explicit "not in
## MVP" list), so "Resign" and "return to the main menu" are the same action
## today -- there is no opponent to concede to yet. Kept as one button rather
## than two that currently do the same thing.
class_name PauseMenu
extends Control

const _MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"
const _PANEL_BG_PATH := "res://assets/ui/hud/panel_background.png"
const _BUTTON_SIZE := Vector2(240.0, 76.0)

signal resumed()

var _panel_size := Vector2(300.0, 320.0)


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
		var bg := TextureRect.new()
		bg.texture = load(_PANEL_BG_PATH)
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		bg.size = _panel_size
		panel_root.add_child(bg)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	buttons.position = Vector2((_panel_size.x - _BUTTON_SIZE.x) * 0.5, 40.0)
	panel_root.add_child(buttons)

	buttons.add_child(_menu_button("resume_button.png", _on_resume_pressed))
	buttons.add_child(_menu_button("main_menu_button.png", _on_resign_pressed))
	buttons.add_child(_menu_button("quit_button.png", func() -> void: get_tree().quit()))


func open() -> void:
	visible = true
	SimClock.stop()


func _on_resume_pressed() -> void:
	visible = false
	SimClock.start()
	resumed.emit()


func _on_resign_pressed() -> void:
	Net.leave()
	get_tree().change_scene_to_file(_MAIN_MENU_SCENE)


func _menu_button(texture_file: String, on_pressed: Callable) -> TextureButton:
	var btn := TextureButton.new()
	var path := "res://assets/ui/menu/%s" % texture_file
	if ResourceLoader.exists(path):
		btn.texture_normal = load(path)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	btn.custom_minimum_size = _BUTTON_SIZE
	btn.pressed.connect(on_pressed)
	return btn
