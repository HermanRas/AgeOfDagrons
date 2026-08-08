## Splash/boot screen (PLAN.md 1.3): the title card, shown briefly before the
## main menu. Separate from `project.godot`'s own `boot_splash/image` --
## that one is the engine's native flicker-frame before ANY scene runs, too
## brief to control; this is a real scene with a timed hold and a tap to
## skip it, the same title art reused for a deliberate first impression.
extends Control

const HOLD_SECONDS := 2.0
const _SPLASH_PATH := "res://assets/ui/boot_splash.png"
const _MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"

var _advanced := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Color("#0E0A06")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var art := TextureRect.new()
	art.texture = load(_SPLASH_PATH)
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)

	get_tree().create_timer(HOLD_SECONDS).timeout.connect(_advance)


func _gui_input(event: InputEvent) -> void:
	var tapped := (event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed) \
			or (event is InputEventMouseButton and not (event as InputEventMouseButton).pressed)
	if tapped:
		_advance()


func _advance() -> void:
	if _advanced:
		return          # the hold timer and a tap can both arrive; only the first counts
	_advanced = true
	get_tree().change_scene_to_file(_MAIN_MENU_SCENE)
