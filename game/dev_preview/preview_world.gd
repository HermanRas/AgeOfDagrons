## Dev check for 3.1/3.3: build the real debug world through MapGen, render it
## through the real GameView, and look at it through the real CameraRig.
##
## It draws nothing of its own. Up to 2.6 it had its own ground loop and its own
## painter's-order sort, which meant it was checking a copy of the render path
## rather than the render path -- the same mistake that let the actual game render
## every entity magenta while this preview looked correct.
##
## Runs interactively (drag to pan) as well as screenshotting itself, so `--quit`
## is what separates "take a picture" from "have a look around".
extends Node2D

const SHOT_PATH := "user://world_preview.png"

## Nudges the camera up so the settlement sits a little below the middle. The
## art grows UPWARD from its ground anchor -- a 10 m tree, the town centre roof --
## so a dead-centre camera wastes the bottom of the frame.
const HEADROOM_PX := 40.0

var _frames := 0
var _shoot := true
var _world: SimWorld
var _view: GameView
var _camera: CameraRig
var _router: InputRouter
var _panel: SelectionPanel


func _ready() -> void:
	_shoot = not OS.get_cmdline_user_args().has("--interactive")

	_world = SimWorld.new()
	_world.setup(MatchConfig.debug_single_player())
	MapGen.build_debug_map(_world)

	_view = GameView.new()
	add_child(_view)
	_view.build_terrain(_world.map.size, _world.map.terrain)
	_view.apply_snapshot(_full_snapshot())

	_camera = CameraRig.new()
	add_child(_camera)
	_camera.make_current()
	_camera.setup(_world.map.size)
	_camera.centre_on(_start_position() - Vector2(0.0, HEADROOM_PX))

	# Tap to select (4.3). The router only recognises taps; the camera keeps its
	# own pan/zoom handling, and the two do not fight because a tap is defined as
	# a press that ended without any drag.
	_router = InputRouter.new()
	add_child(_router)
	_router.tapped.connect(_on_tapped)

	# On its own CanvasLayer, or the camera pans the caption off the screen along
	# with the ground.
	var hud := CanvasLayer.new()
	add_child(hud)

	_panel = SelectionPanel.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.position = Vector2(12, -96)
	hud.add_child(_panel)

	var label := Label.new()
	label.text = "%d entities  |  map %dx%d  |  hash %d" % [
		_world.entities.size(), _world.map.size.x, _world.map.size.y, _world.state_hash()]
	label.position = Vector2(12, 12)
	hud.add_child(label)


## Every entity as one "updated" batch, in the snapshot format the network path
## produces (PLAN.md 7.2). Built from the entities' own to_snapshot() rather than
## hand-rolled, so this cannot describe them differently from a real match.
func _full_snapshot() -> Dictionary:
	var updated: Array = []
	for e in _world.entities.values():
		updated.append((e as SimEntity).to_snapshot())
	return {"tick": 0, "updated": updated, "removed": []}


## Tap position is in SCREEN space; the world is under a camera, so it has to be
## put back through the canvas transform before it means anything to the view.
func _on_tapped(screen_pos: Vector2) -> void:
	var local: Vector2 = _view.get_global_transform_with_canvas().affine_inverse() * screen_pos
	var id := _view.pick(local)

	# Built explicitly rather than inline: a conditional expression loses the
	# element type and `select()` takes an Array[int], so the ternary form fails at
	# runtime rather than at parse time.
	var picked: Array[int] = []
	if id != 0:
		picked.append(id)

	_view.select(picked)
	if id != 0:
		_panel.show_entity(_view.facts_for(id), _view.selection.size())
	else:
		_panel.show_nothing()


func _start_position() -> Vector2:
	for e in _world.entities.values():
		if e is SimBuilding:
			return Iso.sub_to_world((e as SimBuilding).pos)
	return Iso.tile_centre_to_world(_world.map.size / 2)


func _process(_delta: float) -> void:
	if not _shoot:
		return
	_frames += 1
	if _frames < 6:
		return
	get_viewport().get_texture().get_image().save_png(SHOT_PATH)
	print("wrote ", ProjectSettings.globalize_path(SHOT_PATH))
	get_tree().quit()
