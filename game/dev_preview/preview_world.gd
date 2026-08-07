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

	# On its own CanvasLayer, or the camera pans the caption off the screen along
	# with the ground.
	var hud := CanvasLayer.new()
	add_child(hud)
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
