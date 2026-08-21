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
const _PANEL_BG_PATH := "res://assets/ui/hud/panel_background.png"
const _BUTTON_SIZE := Vector2(240.0, 76.0)

signal resumed()

var _panel_size := Vector2(300.0, 320.0)
var _resign_button: TextureButton


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
	# Held rather than added anonymously, so a preview can press the REAL button. What this
	# one does changed completely in 12.1e -- it used to leave the match, it now concedes
	# one -- and calling the handler directly would prove the handler and not the wiring.
	_resign_button = _menu_button("main_menu_button.png", _on_resign_pressed)
	buttons.add_child(_resign_button)
	buttons.add_child(_menu_button("quit_button.png", func() -> void: get_tree().quit()))


func open() -> void:
	visible = true
	SimClock.stop()


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
