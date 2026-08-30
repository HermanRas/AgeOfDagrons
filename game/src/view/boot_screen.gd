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
	# LINEAR. This is the one site where NEAREST was worst: the splash is scaled to
	# FILL a phone, so it is magnified rather than reduced, and nearest-neighbour
	# magnification of a painted plate is visible stair-stepping on every edge.
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# ⚠️ EXPAND_IGNORE_SIZE IS THE FIX, AND `stretch_mode` NEVER WAS.
	#
	# The owner reported the splash "cutting off" on 2026-08-30, and the mode it was
	# set to -- KEEP_ASPECT_CENTERED -- cannot cut anything: it fits inside the rect
	# and pillarboxes. What was cutting it off was the RECT.
	#
	# `TextureRect` defaults to `EXPAND_KEEP_SIZE`, whose MINIMUM SIZE is the
	# texture's own -- 1376x768 here. A minimum size wins over anchors, so
	# PRESET_FULL_RECT did not make this control the size of the screen; it made it
	# 1376x768 pinned at the top-left of a viewport that is 1152x648 in the preview
	# and narrower still on a handset. The plate drew at 1:1 and the right-hand and
	# bottom thirds hung off the window. The photograph in `preview_menus` shows the
	# strapline sliced in half by the bottom edge, which is a crop no stretch mode
	# on this list produces.
	#
	# So: IGNORE_SIZE first, which lets the control actually be the screen, and then
	# STRETCH_SCALE, which fills it exactly and cuts nothing on any aspect. The
	# alternative once the rect is right is KEEP_ASPECT_CENTERED, which is honest to
	# the art and leaves ~140 px of dead background down each side of a 2.2 phone;
	# the owner asked for it stretched to fit. A two-second title card with no
	# readable geometry in it is the cheapest possible place to spend the distortion.
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
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
