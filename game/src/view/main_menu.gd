## The literal front door of the product (PLAN.md 1.1/1.2). Built entirely in
## code on a bare Control, same convention `GameScene` uses for its HUD --
## no `.tscn` content beyond the root node and this script.
##
## PLAY is the only button with real behaviour in MVP; MULTIPLAYER and
## SETTINGS are placeholders per 1.1's own wording (their screens are 1.5/1.6,
## explicitly not `[MVP]`) and answer a tap with a `NoticeToast` rather than
## doing nothing, so the button does not read as broken.
extends Control

const _PANEL_PATH := "res://assets/ui/main_menu_panel.png"
const _GAME_SCENE := "res://scenes/game/Game.tscn"
const _CREDITS_SCENE := "res://scenes/menu/Credits.tscn"

const _PANEL_SIZE := Vector2(640.0, 634.0)
## The art's narrow top bar is ~160px at this scale (source 356x353, top bar
## ~90px); buttons start below it, in the larger lower region, rather than
## straddling the seam between the two.
const _BUTTONS_TOP := 190.0
const _BUTTON_SIZE := Vector2(220.0, 70.0)
const _BUTTON_SPACING := 12.0

var _toast: NoticeToast


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#2B1D14")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel_root := Control.new()
	panel_root.set_anchors_preset(Control.PRESET_CENTER)
	panel_root.position = _PANEL_SIZE * -0.5
	add_child(panel_root)

	if ResourceLoader.exists(_PANEL_PATH):
		var frame := TextureRect.new()
		frame.texture = load(_PANEL_PATH)
		frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		frame.custom_minimum_size = _PANEL_SIZE
		frame.size = frame.custom_minimum_size
		panel_root.add_child(frame)

	var title := Label.new()
	title.text = "AGE OF DRAGON"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("#E5B842"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.position = Vector2(0.0, 20.0)
	title.size = Vector2(_PANEL_SIZE.x, 90.0)
	panel_root.add_child(title)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", int(_BUTTON_SPACING))
	buttons.position = Vector2((_PANEL_SIZE.x - _BUTTON_SIZE.x) * 0.5, _BUTTONS_TOP)
	panel_root.add_child(buttons)

	buttons.add_child(_menu_button("play_button.png", _on_play_pressed))
	buttons.add_child(_menu_button("multiplayer_button.png",
			func() -> void: _toast.show_message("Multiplayer is not available in this build")))
	buttons.add_child(_menu_button("settings_button.png",
			func() -> void: _toast.show_message("Settings are not available in this build")))
	buttons.add_child(_menu_button("credits_button.png", _on_credits_pressed))
	buttons.add_child(_menu_button("quit_button.png", func() -> void: get_tree().quit()))

	_toast = NoticeToast.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position = Vector2(-160.0, -120.0)
	add_child(_toast)


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


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(_GAME_SCENE)


func _on_credits_pressed() -> void:
	get_tree().change_scene_to_file(_CREDITS_SCENE)
