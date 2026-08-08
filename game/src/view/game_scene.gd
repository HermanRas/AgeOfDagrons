## The playable scene: a hosted match you can look at, select in, and give orders
## to (PLAN.md 3.6). Phase 3.6.
##
## This is the first thing in the project that is a GAME rather than a harness.
## `StressTest.tscn` measures the render path and `dev_preview/` checks it by
## screenshot; neither runs a live match you can touch. Everything here is
## assembled from pieces that already existed and were only ever exercised
## separately -- a hosted world, a camera, picking, and a command going back up
## the wire.
##
## Goes through `Net.host_solo()` rather than owning a `SimWorld`, so the local
## player's orders take the same route a remote player's would: a command RPC up,
## snapshots back down (PLAN.md 1.1 rule 4). Nothing here calls into the sim to
## make something happen.
##
## The main menu (1.1) eventually launches this; until then it is the main scene.
extends Control

var _view: GameView
var _camera: CameraRig
var _router: InputRouter
var _panel: SelectionPanel
var _box: SelectionBox
var _status: Label
var _error: String = ""


func _ready() -> void:
	# A full-rect Control defaults to MOUSE_FILTER_STOP and would swallow every
	# mouse event before the camera or the router saw it -- pan would work on the
	# phone and do nothing on the desktop.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_world_layers()
	_build_hud()

	Net.snapshot_received.connect(_on_snapshot)
	var err := Net.host_solo()
	if err != OK:
		# Made visible rather than logged: this is exactly how the missing Android
		# INTERNET permission presented at 0.7 -- no crash, just a game that never
		# started and never said why.
		_error = "host_solo() failed: %s" % error_string(err)
		_status.text = _error
		return
	_start_match()


func _build_world_layers() -> void:
	_view = GameView.new()
	add_child(_view)

	_camera = CameraRig.new()
	add_child(_camera)
	_camera.make_current()

	_router = InputRouter.new()
	add_child(_router)
	_router.tapped.connect(_on_tapped)
	_router.box_changed.connect(_on_box_changed)
	_router.box_selected.connect(_on_box_selected)
	_router.box_cancelled.connect(_on_box_cancelled)


func _build_hud() -> void:
	# Under the world: the void outside the map needs covering, and a full-rect
	# ColorRect on the HUD layer would paint over the game.
	var backdrop := CanvasLayer.new()
	backdrop.layer = -1
	add_child(backdrop)
	var bg := ColorRect.new()
	bg.color = Color("#2B1D14")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(bg)

	# Above it, and on a CanvasLayer so the camera does not pan the HUD away with
	# the ground.
	var hud := CanvasLayer.new()
	add_child(hud)

	_box = SelectionBox.new()
	hud.add_child(_box)

	_panel = SelectionPanel.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.position = Vector2(16, -104)
	hud.add_child(_panel)

	_status = Label.new()
	_status.position = Vector2(16, 12)
	hud.add_child(_status)


## Terrain is read from the host's map.
##
## The view layer does not otherwise touch `SimWorld`, and this is the documented
## exception `Net.host()` exists for. It holds only in solo play, where the client
## and the server are the same process: a remote client has no host to ask and
## will need the map sent to it, which is a job for the multiplayer phase rather
## than something to fake here.
func _start_match() -> void:
	var world: SimWorld = Net.host().world
	_view.build_terrain(world.map.size, world.map.terrain)
	_camera.setup(world.map.size)

	for e in world.entities.values():
		if e is SimBuilding and e.owner_id == Net.local_player_id():
			_camera.centre_on(Iso.sub_to_world((e as SimBuilding).pos))
			return
	_camera.centre_on(Iso.tile_centre_to_world(world.map.size / 2))


func _on_snapshot(snap: Dictionary) -> void:
	_view.apply_snapshot(snap)
	_refresh_panel()


## Tap handling, in priority order (PLAN.md 3.6, 4.3):
##
##   1. One of my own units -> select it.
##   2. Something already selected -> move order to the tapped tile.
##   3. Otherwise -> clear the selection.
##
## Own units win over a move order so that re-selecting never accidentally sends
## the current selection walking onto the unit you were trying to pick. The cost
## is that you cannot order a unit onto a tile another of your units is standing
## on, which 4.5's context actions are where that gets a better answer.
func _on_tapped(screen_pos: Vector2) -> void:
	if _error != "":
		return
	var local: Vector2 = _view.get_global_transform_with_canvas().affine_inverse() * screen_pos

	var mine := _view.pick(local, Net.local_player_id())
	if mine != 0:
		var picked: Array[int] = [mine]
		_view.select(picked)
		_refresh_panel()
		return

	var movable := _view.movable_selection()
	if not movable.is_empty():
		Net.submit_command(MoveCommand.new(Net.local_player_id(), movable, Iso.tile_at(local)))
		return

	_view.select([] as Array[int])
	_refresh_panel()


func _on_box_changed(screen_rect: Rect2) -> void:
	_box.show_box(screen_rect)


func _on_box_cancelled() -> void:
	_box.hide_box()


## Commit a box select (PLAN.md 8.3).
##
## The box arrives in SCREEN space and has to be converted whole, not corner by
## corner in isolation: the canvas transform includes the camera's zoom, so the
## rectangle changes size as well as position.
func _on_box_selected(screen_rect: Rect2) -> void:
	_box.hide_box()
	if _error != "":
		return

	var to_local := _view.get_global_transform_with_canvas().affine_inverse()
	var a: Vector2 = to_local * screen_rect.position
	var b: Vector2 = to_local * screen_rect.end
	var local := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())

	_view.select(_view.units_in_box(local, Net.local_player_id()))
	_refresh_panel()


func _refresh_panel() -> void:
	var primary := _view.selection.primary()
	if primary == 0:
		_panel.show_nothing()
	else:
		_panel.show_entity(_view.facts_for(primary), _view.selection.size())
	_status.text = "tap to select  |  two fingers apart to box-select  |  tap ground to move  |  drag to pan, edge-swipe to zoom"
