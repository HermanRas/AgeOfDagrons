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
## Launched from `MainMenu`'s PLAY button (1.1/1.2) via `change_scene_to_file()`;
## no longer the boot scene itself now that `Boot.tscn`/`MainMenu.tscn` exist.
extends Control

var _view: GameView
var _camera: CameraRig
var _router: InputRouter
var _panel: SelectionPanel
var _box: SelectionBox
var _hud: ResourceHUD
var _groups_hud: ControlGroupsHud
var _minimap: Minimap
var _toast: NoticeToast
var _pause_menu: PauseMenu
var _status: Label
var _error: String = ""

## Last snapshot's control groups for the local player (PLAN.md 10.6):
## `Array[Array[int]]`, one entry per `SimPlayer.CONTROL_GROUP_COUNT` slot.
## Cached here because both `_refresh_hud()` (icon/count) and a slot tap
## (reselect) need "what does slot N currently hold" without re-reading the
## snapshot dict each time.
var _control_groups: Array = []

## Which building the next tap will try to place, or "" for ordinary tap
## handling. Set by the build buttons, cleared by a successful placement or
## the Cancel Build button.
var _placing_def_id: StringName = &""
var _ghost: PlacementGhost


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
	_hud.player_id = Net.local_player_id()
	_start_match()


func _build_world_layers() -> void:
	_view = GameView.new()
	add_child(_view)

	_ghost = PlacementGhost.new()
	_ghost.visible = false
	_view.add_child(_ghost)

	_camera = CameraRig.new()
	add_child(_camera)
	_camera.make_current()

	_router = InputRouter.new()
	add_child(_router)
	_router.tapped.connect(_on_tapped)
	_router.box_changed.connect(_on_box_changed)
	_router.box_selected.connect(_on_box_selected)
	_router.box_cancelled.connect(_on_box_cancelled)
	_router.single_pressed.connect(_on_placement_pressed)
	_router.single_drag_moved.connect(_on_placement_drag)
	_router.single_released.connect(_on_placement_released)


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
	# Anchored at a bottom-left POINT, so by default the panel would grow
	# downward off-screen as rows are added (found live at 4.6/5.5: the new
	# Destroy button pushed a building's panel, with its extra Train row, past
	# the bottom edge). Growing upward instead keeps its bottom edge fixed
	# regardless of how many rows the selected entity's panel shows.
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.train_requested.connect(_on_train_requested)
	_panel.cancel_requested.connect(_on_cancel_requested)
	_panel.debug_destroy_requested.connect(_on_debug_destroy_requested)
	hud.add_child(_panel)

	_hud = ResourceHUD.new()
	_hud.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hud.position = Vector2(-320, 12)
	hud.add_child(_hud)

	_groups_hud = ControlGroupsHud.new()
	_groups_hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_groups_hud.position = Vector2(12, 12)
	_groups_hud.group_selected.connect(_on_group_selected)
	_groups_hud.group_assign_requested.connect(_on_group_assign_requested)
	hud.add_child(_groups_hud)

	_minimap = Minimap.new()
	_minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap.position = Vector2(-Minimap.SIZE - 12.0, -Minimap.SIZE - 12.0)
	_minimap.tapped.connect(_on_minimap_tapped)
	_minimap.double_tapped.connect(_on_minimap_double_tapped)
	hud.add_child(_minimap)

	_toast = NoticeToast.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-160.0, 90.0)
	hud.add_child(_toast)

	var pause_btn := TextureButton.new()
	const pause_icon_path := "res://assets/ui/menu/pause_icon.png"
	if ResourceLoader.exists(pause_icon_path):
		pause_btn.texture_normal = load(pause_icon_path)
	pause_btn.ignore_texture_size = true
	pause_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	pause_btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pause_btn.custom_minimum_size = Vector2(48.0, 48.0)
	pause_btn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pause_btn.position = Vector2(-24.0, 12.0)
	pause_btn.pressed.connect(func() -> void: _pause_menu.open())
	hud.add_child(pause_btn)

	_pause_menu = PauseMenu.new()
	hud.add_child(_pause_menu)

	# Past the control-group stack (12 + 64 px wide) rather than under it --
	# these are dev/debug controls, not part of UI_Design.md's layout, so they
	# just need to stay out of its way.
	var build_row := HBoxContainer.new()
	build_row.position = Vector2(96, 16)
	hud.add_child(build_row)

	var house_btn := Button.new()
	house_btn.text = "Build House"
	house_btn.pressed.connect(_enter_placement.bind(&"building.house"))
	build_row.add_child(house_btn)

	var tc_btn := Button.new()
	tc_btn.text = "Build Town Centre"
	tc_btn.pressed.connect(_enter_placement.bind(&"building.town_center"))
	build_row.add_child(tc_btn)

	var cancel_build_btn := Button.new()
	cancel_build_btn.text = "Cancel Build"
	cancel_build_btn.pressed.connect(_exit_placement)
	build_row.add_child(cancel_build_btn)

	_status = Label.new()
	_status.position = Vector2(96, 48)
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
	_minimap.build_terrain(world.map.size, world.map.terrain)
	_camera.setup(world.map.size)

	for e in world.entities.values():
		if e is SimBuilding and e.owner_id == Net.local_player_id():
			_camera.centre_on(Iso.sub_to_world((e as SimBuilding).pos))
			return
	_camera.centre_on(Iso.tile_centre_to_world(world.map.size / 2))


func _on_snapshot(snap: Dictionary) -> void:
	_view.apply_snapshot(snap)
	_refresh_panel()
	_refresh_hud(snap)
	_refresh_minimap()


## Pushes 7.1's two counter signals, plus 10.1's per-slot control-group signal,
## out through EventBus. GameScene is what happens to receive the snapshot,
## but the HUDs do not need to know that -- see EventBus's own header for why
## that indirection is worth keeping.
func _refresh_hud(snap: Dictionary) -> void:
	var player_id := Net.local_player_id()
	var player_state: Dictionary = snap.get("player_state", {})
	var mine: Dictionary = player_state.get(player_id, {})
	EventBus.resources_changed.emit(player_id, mine.get("stock", {}))

	var counts := _view.villager_counts(player_id)
	EventBus.villagers_changed.emit(player_id, counts.x, counts.y)

	# SimPlayer.control_groups is the authoritative membership (10.6); icon and
	# live count are derived here each tick from GameView's facts, the same
	# division of labour as villager_counts() above.
	_control_groups = mine.get("control_groups", [])
	for slot in range(SimPlayer.CONTROL_GROUP_COUNT):
		var members: Array = _control_groups[slot] if slot < _control_groups.size() else []
		var summary := _view.control_group_summary(members)
		EventBus.control_group_changed.emit(slot, summary["icon"], summary["count"])


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
	# In build mode this tap is handled by `single_released` instead, once it
	# fires right after this. `InputRouter` guarantees `tapped` is resolved and
	# emitted BEFORE `single_released` for the same gesture (see its own
	# header), so `_placing_def_id` here is still whatever it was for the tap
	# that just happened -- never something a placement handler already
	# changed it to for the gesture that is about to follow.
	if _placing_def_id != &"":
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


## Enters placement mode for `def_id` (PLAN.md 5.1) and locks the camera: the
## same one finger that would otherwise pan now drags the ghost instead (see
## `CameraRig.locked`'s own header for why that trade beats swapping pan to two
## fingers). `_on_placement_pressed/_drag/_released` do the rest.
func _enter_placement(def_id: StringName) -> void:
	_placing_def_id = def_id
	_camera.set_locked(true)
	_status.text = "drag to place a %s, release to drop it  |  Cancel Build to stop" % \
			_display_name(def_id)


func _exit_placement() -> void:
	_placing_def_id = &""
	_camera.set_locked(false)
	_ghost.visible = false
	_refresh_panel()


func _on_placement_pressed(screen_pos: Vector2) -> void:
	if _placing_def_id != &"":
		_preview_placement(screen_pos)


func _on_placement_drag(screen_pos: Vector2) -> void:
	if _placing_def_id != &"":
		_preview_placement(screen_pos)


## The drag ends here, wherever it ends -- a stationary tap-and-release counts
## the same as a long drag, since both arrive through `single_released`
## (PLAN.md 5.1). Commits on a valid drop and leaves build mode; an invalid
## drop flashes the ghost red for a moment and stays in build mode so another
## attempt can start from the same finger-down.
func _on_placement_released(screen_pos: Vector2) -> void:
	if _placing_def_id == &"":
		return
	var result := _preview_placement(screen_pos)
	if result.is_empty():
		return
	if result["valid"]:
		Net.submit_command(PlaceBuildingCommand.new(
				Net.local_player_id(), _placing_def_id, result["origin"]))
		_exit_placement()
		return

	_toast.show_message("Not enough resources" if not result["can_afford"] else "Can't build there")

	# A flash, not a permanent red ghost: it stays long enough to read as "no",
	# then clears so the next attempt starts from a blank slate.
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		if _placing_def_id != &"":
			_ghost.visible = false)


## Moves the ghost to the tile under `screen_pos`, snapped to the grid, and
## colours it by legality. Shared by the press/drag/release handlers so all
## three agree on exactly the same tile for the same point.
##
## Reads `Net.host().world` directly -- the same documented solo-only exception
## `_start_match()` already uses, not a new hole in the view/sim boundary.
func _preview_placement(screen_pos: Vector2) -> Dictionary:
	var bd: BuildingDef = GameDataRegistry.building(_placing_def_id)
	if bd == null:
		_exit_placement()
		return {}

	var local: Vector2 = _view.get_global_transform_with_canvas().affine_inverse() * screen_pos
	var world: SimWorld = Net.host().world
	var player := world.player_for(Net.local_player_id())
	var origin := Iso.tile_at(local)
	var rect := SimMap.footprint_rect(origin, bd.footprint)
	var can_afford := player != null and player.can_afford(bd.cost)
	var valid := can_afford and world.map.can_place_building(rect)

	var centre := Vector2(origin) + Vector2(bd.footprint) * 0.5
	_ghost.position = Iso.tile_to_world_f(centre)
	_ghost.set_state(Vector2(bd.footprint) * Iso.METRES_PER_TILE, valid)
	_ghost.visible = true

	return {"origin": origin, "valid": valid, "can_afford": can_afford}


func _display_name(def_id: StringName) -> String:
	var bd: BuildingDef = GameDataRegistry.building(def_id)
	return bd.name if bd != null and not bd.name.is_empty() else String(def_id)


func _on_train_requested(building_id: int, unit_def_id: StringName) -> void:
	Net.submit_command(TrainCommand.new(Net.local_player_id(), building_id, unit_def_id))


func _on_cancel_requested(building_id: int, index: int) -> void:
	Net.submit_command(CancelProductionCommand.new(Net.local_player_id(), building_id, index))


func _on_debug_destroy_requested(target_id: int) -> void:
	Net.submit_command(DebugDestroyCommand.new(Net.local_player_id(), target_id))


## Blips and the camera-viewport rectangle (PLAN.md 8.2a). Separate from
## _refresh_hud() -- that one drains once per snapshot into EventBus signals
## other widgets read; the minimap is driven directly since nothing else
## needs "every entity's facts" broadcast for its sake.
func _refresh_minimap() -> void:
	_minimap.update_entities(_view.all_facts(), Net.local_player_id())

	var half := _camera.visible_size() * 0.5
	var top_left := Iso.world_to_tile_f(_camera.position - half)
	var bottom_right := Iso.world_to_tile_f(_camera.position + half)
	_minimap.update_camera_rect(Rect2(top_left, bottom_right - top_left))


## Tap the minimap to move the camera there (PLAN.md 3.8). MVP has no 3.7
## ("tap minimap to move SELECTED units there") to compete with a plain tap,
## so this fires regardless of what is selected.
func _on_minimap_tapped(tile: Vector2i) -> void:
	_camera.centre_on(Iso.tile_centre_to_world(tile))


## Double-tap the minimap to centre on the player's own Town Centre
## (PLAN.md 3.4). Silently does nothing if they have none in view -- true
## the instant a match starts and before the first snapshot has landed.
func _on_minimap_double_tapped() -> void:
	var centre = _view.owned_entity_position(Net.local_player_id(), &"building.town_center")
	if centre != null:
		_camera.centre_on(centre)


## Single tap (mobile) or a plain digit key (desktop): reselect the group and
## recentre the camera on wherever most of it currently is (PLAN.md 10.5).
## Silently does nothing for an empty/all-dead group -- there is nothing to
## select or centre on.
func _on_group_selected(slot: int) -> void:
	if slot < 0 or slot >= _control_groups.size():
		return
	var alive := _view.control_group_alive_members(_control_groups[slot])
	if alive.is_empty():
		return
	_view.select(alive)
	_refresh_panel()
	var centre = _view.control_group_centre(_control_groups[slot])
	if centre != null:
		_camera.centre_on(centre)


## Double tap (mobile) or Ctrl+digit (desktop): assign whatever is currently
## selected to the slot (PLAN.md 10.2). A no-op with nothing selected --
## `SetControlGroupCommand.validate()` rejects an empty assignment rather than
## clearing the slot, see that command's own header.
func _on_group_assign_requested(slot: int) -> void:
	var current := _view.selection.current()
	if current.is_empty():
		return
	Net.submit_command(SetControlGroupCommand.new(Net.local_player_id(), slot, current))
	_toast.show_message("Assigned to group %d" % (slot + 1))


## PC control-group hotkeys (PLAN.md 10 session note): plain 1-5 reselects,
## Ctrl+1-5 assigns -- mobile's single/double-tap on the HUD icon are the same
## two actions under different input, so both paths end at the same handlers.
func _unhandled_key_input(event: InputEvent) -> void:
	if _error != "" or not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key := event as InputEventKey

	if key.keycode == KEY_ESCAPE:
		if not _pause_menu.visible:
			_pause_menu.open()
		return

	if key.keycode < KEY_1 or key.keycode > KEY_5:
		return
	var slot := int(key.keycode) - int(KEY_1)
	if key.ctrl_pressed:
		_on_group_assign_requested(slot)
	else:
		_on_group_selected(slot)


func _on_box_changed(screen_rect: Rect2) -> void:
	# A second finger landing mid-drag turns the gesture into a box (8.3) and
	# abandons the single-finger tracking placement was riding -- no
	# `single_released` will follow for it, so the ghost is left stuck showing
	# wherever it last was unless cleared here. Build mode itself stays active;
	# only the half-finished drag is abandoned.
	if _placing_def_id != &"":
		_ghost.visible = false
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
		var facts := _view.facts_for(primary)
		var is_mine := int(facts.get("owner_id", 0)) == Net.local_player_id()
		var all_def_ids: Array = []
		for id in _view.selection.current():
			all_def_ids.append(_view.facts_for(id).get("def_id", &""))
		_panel.show_entity(facts, _view.selection.size(), is_mine, all_def_ids)

	if _placing_def_id == &"":
		_status.text = "tap to select  |  two fingers apart to box-select  |  tap ground to move  |  drag to pan, edge-swipe to zoom"
