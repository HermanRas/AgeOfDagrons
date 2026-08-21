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
var _age_badge: AgeBadge
var _idle_badge: IdleVillagerBadge
var _minimap: Minimap
var _toast: NoticeToast
var _pause_menu: PauseMenu
var _result: ResultScreen
var _error_label: Label
var _error: String = ""

## True once the local player's match has been decided (PLAN.md 11.1) -- won,
## lost, or drawn. Kept beside `_error` and checked by the same guards, because it
## means the same thing to input handling: orders from here on would be orders into
## a match that has stopped. The `ResultScreen` overlay swallows GUI presses on its
## own; this catches the touch path, which reaches `InputRouter` through
## `_unhandled_input` and never asks a Control's `mouse_filter` anything.
var _match_over := false

## Last snapshot's control groups for the local player (PLAN.md 10.6):
## `Array[Array[int]]`, one entry per `SimPlayer.CONTROL_GROUP_COUNT` slot.
## Cached here because both `_refresh_hud()` (icon/count) and a slot tap
## (reselect) need "what does slot N currently hold" without re-reading the
## snapshot dict each time.
var _control_groups: Array = []

## The last idle villager the badge walked to, or 0 before the first tap. Kept
## here rather than in the badge because it is a fact about the WALK, not about
## the widget: the badge reports a count and asks for the next one, and this is
## where it got to. See `GameView.next_idle_villager()` for why it is an id and
## not an index into the list.
var _idle_cycle_id: int = 0

## Which building the next tap will try to place, or "" for ordinary tap
## handling. Set by the build buttons, cleared by a successful placement or
## the Cancel Build button.
var _placing_def_id: StringName = &""
var _ghost: PlacementGhost

## The way OUT of build mode on a touch screen (project owner, 2026-08-21, found on a
## real phone in a two-device match).
##
## Build mode locks the camera so one finger can drag the ghost rather than pan, and the
## only other ways out were Escape and right-click -- neither of which a phone has. With
## no legal spot on screen and no way to pan to one, a placement could be neither
## finished nor abandoned: the ghost stayed stuck to the finger for the rest of the
## match. Visible only while placing, so it is never in the way otherwise.
var _cancel_build: Button
var _flash: ActionFlash

## Touch only: a tap on empty ground with units selected DESELECTS, and only a
## double tap moves them there. Found on device -- a small, quick pan clears
## `InputRouter`'s slop and time bounds, so it registered as a tap and sent the
## selection wandering off whenever the player tried to scroll the map.
##
## A mouse keeps single-click-to-move: it does not wobble, and desktop players
## get right-click to clear instead (`_on_context_cancel`).
var _ground_tap := DoubleTapDetector.new()

## The ground, on a client that has no `SimWorld` (PLAN.md 12.1b). Built once from the
## config's `MapData` and never ticked; the placement ghost reads it for terrain and gets
## everything standing on that terrain from snapshot facts. Null in solo, where the host's
## own world is the better answer and is right there to ask.
var _client_map: SimMap = null

## Bumped by EVERY tap, so a deferred single-tap deselect can tell that some
## LATER tap has happened and stand down. `DoubleTapDetector.is_still_pending()`
## alone is not enough: it only knows about taps that went through it, and a tap
## that selected a unit never does -- without this, tapping the ground and then
## quickly picking a new unit would clear that new selection a moment later.
var _tap_token: int = 0


func _ready() -> void:
	# A full-rect Control defaults to MOUSE_FILTER_STOP and would swallow every
	# mouse event before the camera or the router saw it -- pan would work on the
	# phone and do nothing on the desktop.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_world_layers()
	_build_hud()

	Net.snapshot_received.connect(_on_snapshot)

	# ONLY HOST IF NOBODY HAS ALREADY SET A SESSION UP. Entering this scene used to mean
	# "host a solo match", which is right when the main menu's PLAY brought us here and
	# wrong for a client that has already joined one -- it would host over the top of
	# its own session and never draw the match it came for (PLAN.md 12.1b).
	if not Net.has_session():
		var err := Net.host_solo()
		if err != OK:
			# Made visible rather than logged: this is exactly how the missing Android
			# INTERNET permission presented at 0.7 -- no crash, just a game that never
			# started and never said why.
			_error = "host_solo() failed: %s" % error_string(err)
			_error_label.text = _error
			_error_label.visible = true
			return

	_hud.player_id = Net.local_player_id()
	_idle_badge.player_id = Net.local_player_id()
	# A client may arrive before the host has described the match. Connected rather than
	# waited on, and `_start_match()` is called anyway: on a host, and on a client whose
	# config beat the scene here, it has everything it needs already.
	if Net.match_config() == null:
		Net.match_configured.connect(_on_match_configured)
	_start_match()


func _build_world_layers() -> void:
	_view = GameView.new()
	add_child(_view)

	_ghost = PlacementGhost.new()
	_ghost.visible = false
	_view.add_child(_ghost)

	_flash = ActionFlash.new()
	_view.add_child(_flash)

	_camera = CameraRig.new()
	add_child(_camera)
	_camera.make_current()

	_router = InputRouter.new()
	add_child(_router)
	_router.tapped.connect(_on_tapped)
	_router.box_changed.connect(_on_box_changed)
	_router.box_selected.connect(_on_box_selected)
	_router.box_cancelled.connect(_on_box_cancelled)
	_router.context_cancel.connect(_on_context_cancel)
	_router.single_pressed.connect(_on_placement_pressed)
	_router.single_drag_moved.connect(_on_placement_drag)
	_router.single_released.connect(_on_placement_released)
	_router.mouse_hover_moved.connect(_on_placement_hover)


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

	# ANCHORS AND OFFSETS BELOW ARE THE ui_builder MOCKUP'S, ported by hand.
	# `HUD.tscn` is where the project owner lays this out; setting offsets here
	# rather than `position` is what makes the two comparable, since `position`
	# on an anchored Control writes offset_left/offset_top only and leaves the
	# other two wherever they were.
	_panel = SelectionPanel.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.offset_left = 0.0
	_panel.offset_bottom = 0.0
	# Anchored to the bottom EDGE, so by default the panel would grow downward
	# off-screen as rows are added (found live at 4.6/5.5: the new Destroy button
	# pushed a building's panel, with its extra Train row, past the bottom edge).
	# Growing upward instead keeps its bottom edge fixed regardless of how many
	# rows the selected entity's panel shows.
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.train_requested.connect(_on_train_requested)
	_panel.cancel_requested.connect(_on_cancel_requested)
	_panel.debug_destroy_requested.connect(_on_debug_destroy_requested)
	_panel.place_requested.connect(_enter_placement)
	_panel.action_requested.connect(_on_action_requested)
	hud.add_child(_panel)

	# Flush into the top-right corner, per the mockup -- it used to sit 64 px down,
	# which left a gap the dragon frame was never drawn to fill.
	_hud = ResourceHUD.new()
	_hud.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hud.offset_left = -ResourceHUD.PANEL_SIZE.x
	_hud.offset_top = 0.0
	_hud.offset_right = 0.0
	_hud.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hud.add_child(_hud)

	_groups_hud = ControlGroupsHud.new()
	_groups_hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_groups_hud.position = Vector2(12, 12)
	_groups_hud.group_selected.connect(_on_group_selected)
	_groups_hud.group_assign_requested.connect(_on_group_assign_requested)
	hud.add_child(_groups_hud)

	# A fixed footprint a little larger than the rotated diamond's own bounding
	# box (SIZE * sqrt(2)) so its tips have room to reach almost to the edges
	# without the corner buttons around it being pushed out further still.
	var minimap_area := Control.new()
	minimap_area.custom_minimum_size = Vector2(Minimap.AREA_SIZE, Minimap.AREA_SIZE)
	minimap_area.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap_area.position = Vector2(-Minimap.AREA_SIZE - 12.0, -Minimap.AREA_SIZE - 12.0)
	hud.add_child(minimap_area)

	_minimap = Minimap.new()
	_minimap.position = Vector2(Minimap.AREA_SIZE - Minimap.SIZE, Minimap.AREA_SIZE - Minimap.SIZE) * 0.5
	_minimap.tapped.connect(_on_minimap_tapped)
	_minimap.double_tapped.connect(_on_minimap_double_tapped)
	minimap_area.add_child(_minimap)

	# PLAN.md 8.2b / ASSET_MISSING.md 240: a circular frame with 4 corner
	# buttons is sourced from the dragon pack but not integrated, and
	# chat/trade/tech-tree don't exist yet to give these something to do --
	# disabled placeholders so the corner reads as "coming soon" rather than
	# empty, not real buttons. Added to minimap_area AFTER the minimap so they
	# sit on top of the rotated diamond's tips and stay clickable rather than
	# being covered by them; the two VSeparators are flex spacers, not visible
	# lines, that push each pair of buttons out to the area's own corners.
	var minimap_buttons := GridContainer.new()
	minimap_buttons.columns = 3
	minimap_buttons.set_anchors_preset(Control.PRESET_FULL_RECT)
	# AND IT MUST NOT EAT THE MINIMAP'S INPUT. This grid covers the WHOLE area,
	# the flex spacers cover its middle, and it is added after the minimap, so
	# Godot hit-tests it first and every tap on the diamond died here -- the
	# camera never moved and the double-tap-to-centre never fired. The buttons
	# are disabled placeholders with nothing to do, so nothing in this subtree
	# wants the mouse; give it all back. **When these become real buttons they
	# need `MOUSE_FILTER_STOP` again** -- individually, never on the grid.
	minimap_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_area.add_child(minimap_buttons)

	for pair in [["hud_chat.png", "hud_trade.png"], ["hud_techtree.png", "hud_settings.png"]]:
		minimap_buttons.add_child(_corner_button(pair[0]))
		var sep := VSeparator.new()
		sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sep.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		minimap_buttons.add_child(sep)
		minimap_buttons.add_child(_corner_button(pair[1]))

	_toast = NoticeToast.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-160.0, 409.0)
	hud.add_child(_toast)

	# In the gap BETWEEN the build grid and the minimap, which is the only part of the
	# bottom edge free while placing. Bottom centre looked empty and is not: the build
	# grid opens there, so a cancel button sat straight on top of the menu it belongs to
	# -- caught by `preview_match`'s screenshot, not by the code.
	_cancel_build = Button.new()
	_cancel_build.text = "CANCEL BUILD"
	_cancel_build.add_theme_font_size_override("font_size", 24)
	_cancel_build.custom_minimum_size = Vector2(280.0, 80.0)
	_cancel_build.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_cancel_build.position = Vector2(-512.0, -120.0)
	_cancel_build.visible = false
	_cancel_build.pressed.connect(_exit_placement)
	hud.add_child(_cancel_build)

	# Phase 9.1's age indicator. Compacted to the mockup's 180x86 at the top
	# centre -- it was 240 wide when it carried a title and a straight progress
	# bar, and both are gone: the numeral says the age, and the advance progress
	# is now the ring around the badge itself rather than a separate bar. It
	# widened by 14 again when the idle badge joined the pause button beside it.
	var age_header := PanelContainer.new()
	HudStyle.add_panel_background(age_header)
	age_header.set_anchors_preset(Control.PRESET_CENTER_TOP)
	age_header.offset_left = -83.0
	age_header.offset_right = 97.0
	age_header.offset_top = 0.0
	age_header.offset_bottom = 86.0
	age_header.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud.add_child(age_header)

	var age_margin := MarginContainer.new()
	age_margin.add_theme_constant_override("margin_left", 35)
	age_margin.add_theme_constant_override("margin_right", 35)
	age_margin.add_theme_constant_override("margin_top", 20)
	age_margin.add_theme_constant_override("margin_bottom", 12)
	age_header.add_child(age_margin)

	var age_box := VBoxContainer.new()
	age_box.add_theme_constant_override("separation", 2)
	age_margin.add_child(age_box)

	# Title and pause button share a row -- the pause button used to be its
	# own top-level TextureButton pinned to the top-right corner, but the
	# ui_builder HUD mockup folded it into the age header instead so the two
	# pieces of top-of-screen chrome read as one panel rather than two.
	var age_top_row := HBoxContainer.new()
	# The mockup spaces the badge off the column with a 5 px spacer between two
	# default 4 px separations; one constant here is the same gap with two fewer
	# nodes.
	age_top_row.add_theme_constant_override("separation", 13)
	age_box.add_child(age_top_row)

	# The NUMERAL only. ages.json is explicit that the numeral is what the HUD
	# shows -- it needs no words and fits a 648 px canvas -- and that the NAME
	# belongs to the places with room for prose: the tech tree (9.4), the
	# advancement banner, the lobby. This header briefly showed the name too;
	# it read as a caption on a screen that has no room to spare, so it is gone
	# rather than shortened.
	_age_badge = AgeBadge.new()
	_age_badge.advance_requested.connect(_on_age_advance_requested)
	age_top_row.add_child(_age_badge)

	# Pause above, idle count below, in one narrow column beside the age badge --
	# the mockup's `VillagersIdle` VBox. The pause button halved (48 -> 22) to
	# make room: the header's content row is only as tall as the age badge, and
	# two stacked 48s would have grown the panel rather than fitting inside it.
	var badge_column := VBoxContainer.new()
	badge_column.custom_minimum_size = Vector2(IdleVillagerBadge.SIZE, 0.0)
	age_top_row.add_child(badge_column)

	var pause_btn := TextureButton.new()
	const pause_icon_path := "res://assets/ui/menu/pause_icon.png"
	if ResourceLoader.exists(pause_icon_path):
		pause_btn.texture_normal = load(pause_icon_path)
	pause_btn.ignore_texture_size = true
	# KEEP_CENTERED, not KEEP_ASPECT_CENTERED: the icon is 64x64 pixel art and
	# fitting it to a 22 px cell is a 0.34x non-integer downscale, which mushes it
	# whatever the filter does. Drawn at its own size, centred on the cell, it
	# overhangs the column and stays crisp -- the mockup's value, and what the
	# project owner asked for by name.
	pause_btn.stretch_mode = TextureButton.STRETCH_KEEP_CENTERED
	pause_btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pause_btn.custom_minimum_size = Vector2(IdleVillagerBadge.SIZE, IdleVillagerBadge.SIZE)
	pause_btn.pressed.connect(func() -> void: _pause_menu.open())
	badge_column.add_child(pause_btn)

	_idle_badge = IdleVillagerBadge.new()
	_idle_badge.cycle_requested.connect(_on_idle_cycle_requested)
	badge_column.add_child(_idle_badge)

	_pause_menu = PauseMenu.new()
	hud.add_child(_pause_menu)

	# ADDED AFTER THE PAUSE MENU, so it draws over it. If the match is decided while
	# the player happens to have the pause menu open, the result is the thing that
	# outranks -- and its Resume would otherwise restart a clock the result screen
	# has just stopped.
	_result = ResultScreen.new()
	hud.add_child(_result)

	# ERRORS ONLY. This used to carry the controls hint and the placement hint as
	# well, as one long line across the top -- which grew to whatever its text
	# needed and ran straight under the resource counters, obscuring the top row.
	# That was most of why the running HUD did not match the ui_builder mockup
	# even after the panel itself did: the panel was right, and something was
	# being drawn over it. The hints are gone for good; a How to Play section is
	# taking that job, and a permanent wall of text over the game was never the
	# right home for it.
	#
	# What is NOT gone is the boot error. It reads empty and invisible in an
	# ordinary match and only ever appears if `host_solo()` fails, which is
	# exactly how the missing Android INTERNET permission presented at 0.7 -- no
	# crash, just a game that never started and never said why. The toast is not
	# a substitute: it fades after 2.5 s, and this is something the player needs
	# to still be on screen when they come to report it.
	_error_label = Label.new()
	_error_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_error_label.offset_left = 96.0
	_error_label.offset_top = 92.0
	_error_label.offset_right = -(ResourceHUD.PANEL_SIZE.x + 24.0)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_error_label.visible = false
	hud.add_child(_error_label)


## One disabled placeholder corner button (chat/trade/tech-tree/settings);
## shared by the two rows `_build_hud()` assembles around the minimap.
func _corner_button(icon_file: String) -> TextureButton:
	var corner_btn := TextureButton.new()
	var icon_path := "res://assets/ui/icons/%s" % icon_file
	if ResourceLoader.exists(icon_path):
		corner_btn.texture_normal = load(icon_path)
	corner_btn.ignore_texture_size = true
	corner_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	corner_btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	corner_btn.custom_minimum_size = Vector2(32.0, 32.0)
	corner_btn.disabled = true
	corner_btn.modulate = Color(1.0, 1.0, 1.0, 0.5)
	# A disabled button still BLOCKS the mouse in Godot; these sit over the
	# minimap's tips (see `_build_hud`), so blocking is exactly what they must
	# not do. Restore STOP on whichever one gets a real action first.
	corner_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return corner_btn


## TERRAIN COMES FROM THE CONFIG, NOT FROM THE HOST'S WORLD (PLAN.md 12.1b).
##
## This used to read `Net.host().world` -- the documented solo-only exception -- and on
## a joining client `Net.host()` is null, so the scene died on entry. That was the whole
## of the plan's high-risk item.
##
## The config carries the map as DATA precisely so both sides can build from the same
## bytes (12.1b's 2026-08-17 correction: regenerating from a seed risks a host and a
## client disagreeing about where the water is). One path now serves host and client,
## which is better than the exception it replaces rather than merely equal to it.
##
## The FIXED debug map carries no `MapData` -- it is integer code, identical everywhere
## -- so solo on that map still reads the host's world. That branch is genuinely
## solo-only: a hosted match plays on a generated map.
func _start_match() -> void:
	var cfg := Net.match_config()
	if cfg != null and cfg.map_data != null:
		var md := cfg.map_data
		# The client's own copy of the GROUND, for the placement ghost. Terrain only --
		# it carries no occupancy and is never ticked, so it is not a second simulation:
		# what is standing on the ground comes from snapshot facts (`PlacementAdvice`).
		_client_map = _build_client_map(md)
		_view.build_terrain(md.size, md.terrain)
		_minimap.build_terrain(md.size, md.terrain)
		_camera.setup(md.size)
		_open_camera_on(cfg, md.size)
		# THE ACK (PLAN.md 12.1d). The host holds the clock until this arrives, so it
		# goes at the end of the one function that stands the view up -- the point where
		# a snapshot would actually mean something. A no-op on a host.
		Net.notify_ready()
		return

	var host := Net.host()
	if host == null:
		# A client with no config yet. Not an error -- `_ready()` has connected
		# `match_configured` and this runs again when it lands.
		return
	var world: SimWorld = host.world
	_view.build_terrain(world.map.size, world.map.terrain)
	_minimap.build_terrain(world.map.size, world.map.terrain)
	_camera.setup(world.map.size)
	for e in world.entities.values():
		if e is SimBuilding and e.owner_id == Net.local_player_id():
			_camera.centre_on(Iso.sub_to_world((e as SimBuilding).pos))
			return
	_camera.centre_on(Iso.tile_centre_to_world(world.map.size / 2))


## The client's own copy of the GROUND, for the placement ghost.
##
## Terrain only. It carries no occupancy and is never ticked, so it is not a second
## simulation -- what is STANDING on the ground comes from snapshot facts, through
## `PlacementAdvice`. Built the same way `MapGen.build_from()` copies a map into a world,
## through `set_terrain` rather than a raw array write, so each tile's move cost is
## derived from its terrain and the two can never disagree (PLAN.md 2.1).
func _build_client_map(md: MapData) -> SimMap:
	var map := SimMap.create(md.size)
	for y in range(md.size.y):
		for x in range(md.size.x):
			var t := Vector2i(x, y)
			if md.in_bounds(t):
				map.set_terrain(t, md.terrain_at(t) as SimMap.Terrain)
	return map


## The config landed after the scene was already up, which is the ordinary case for a
## client: it joins, changes scene, and the host's description arrives a moment later.
##
## Also refreshes the HUD's player id: a client is named by the server (12.1a), and if
## that happened after `_ready()` the HUD would still be showing player 0's resources.
func _on_match_configured() -> void:
	_hud.player_id = Net.local_player_id()
	_idle_badge.player_id = Net.local_player_id()
	_start_match()


## Open the camera on this player's own corner of the map.
##
## From `MapData.starts` rather than by looking for the player's town centre, because a
## client has no entities yet -- the first snapshot has not arrived when the scene is
## built, and opening on the middle of the map and then jumping would be worse than
## opening in the right place straight away. The starts are the same list `MapGen` puts
## the town centres on, so this lands where the building will be.
func _open_camera_on(cfg: MatchConfig, size: Vector2i) -> void:
	var slot := cfg.player_ids.find(Net.local_player_id())
	if slot >= 0 and slot < cfg.map_data.starts.size():
		_camera.centre_on(Iso.tile_centre_to_world(cfg.map_data.starts[slot]))
		return
	_camera.centre_on(Iso.tile_centre_to_world(size / 2))


## The local player's fog, as the last snapshot carried it (PLAN.md 2.5). Cached
## here for the same reason `_control_groups` is: `_refresh_minimap()` needs it and
## does not receive the snapshot, and the alternative is asking `GameView` for its
## overlay's internals.
var _last_vision: PackedByteArray = PackedByteArray()


func _on_snapshot(snap: Dictionary) -> void:
	_last_vision = snap.get("vision", PackedByteArray())
	_view.apply_snapshot(snap)
	_refresh_panel()
	_refresh_hud(snap)
	_refresh_minimap()
	_refresh_result(snap)


## The end of the match (PLAN.md 11.1), read off the snapshot rather than worked
## out here -- `WinConditionSystem` decides it and the host sends it, so the screen
## cannot disagree with the sim about whether the game is over.
##
## THREE OUTCOMES, TWO OF THEM DEFEAT. `match_over` with our own id is the win;
## `match_over` with anybody else's (or 0, the mutual-destruction draw) is not.
## `defeated` without `match_over` is the third case and the reason the flag rides
## per player at all: in a match of three or more, being knocked out happens while
## the fighting goes on, and the player is owed the screen then rather than whenever
## the survivors finish.
##
## Runs LAST of the four refreshes on purpose: the HUD, panel and minimap should all
## show the final tick's state behind the overlay, rather than being frozen one tick
## short of the thing that ended it.
func _refresh_result(snap: Dictionary) -> void:
	if _result.is_shown():
		return

	var player_id := Net.local_player_id()
	var mine: Dictionary = (snap.get("player_state", {}) as Dictionary).get(player_id, {})
	var over := bool(snap.get("match_over", false))
	var defeated := bool(mine.get("defeated", false))
	if not over and not defeated:
		return

	# Short lines on purpose: the panel is 340 wide because a 240 px button and the
	# frame's border say so, and a sentence long enough to wrap onto three lines
	# would push the buttons down out of it.
	_match_over = true
	var winner := int(snap.get("winner_id", 0))
	if not over:
		_result.show_result(false, "You were eliminated")
	elif winner == player_id:
		_result.show_result(true, "All opponents eliminated")
	elif winner == 0:
		_result.show_result(false, "Nobody was left standing")
	else:
		_result.show_result(false, "Player %d won" % winner)


## Whether the player's input should be ignored outright: the match never started
## (`_error`) or it has finished (`_match_over`). One predicate for both because
## every guard in this file wanted both the moment the second one existed, and two
## separate checks is how one of them ends up missing from a handler.
func _orders_refused() -> bool:
	return _error != "" or _match_over


## Pushes 7.1's two counter signals, plus 10.1's per-slot control-group signal,
## out through EventBus. GameScene is what happens to receive the snapshot,
## but the HUDs do not need to know that -- see EventBus's own header for why
## that indirection is worth keeping.
func _refresh_hud(snap: Dictionary) -> void:
	var player_id := Net.local_player_id()
	var player_state: Dictionary = snap.get("player_state", {})
	var mine: Dictionary = player_state.get(player_id, {})
	EventBus.resources_changed.emit(player_id, mine.get("stock", {}))

	# Two counters, two sources, deliberately. The idle count is a headcount over
	# what is in view; population is state the SIM keeps (PopulationSystem writes
	# it, and the cap is a rule a server has to be able to enforce), so it comes
	# off `player_state` with the stock rather than being re-derived here.
	EventBus.idle_villagers_changed.emit(player_id, _view.idle_villager_count(player_id))
	EventBus.population_changed.emit(player_id,
			int(mine.get("pop_used", 0)), int(mine.get("pop_cap", 0)))

	_age_badge.age = _view.age_of(player_id)
	_age_badge.advancing = _view.is_advancing(player_id)
	_age_badge.progress = _view.age_progress_of(player_id)

	# A control group only ever holds the local player's units, so the whole
	# stack shares one skin. Set before the per-slot signals below so a slot
	# filling this tick crops in the right colour on its first draw.
	_groups_hud.set_skin(_view.age_of(player_id),
			int(_view.skin_for(player_id).get("colour", -1)))

	# SimPlayer.control_groups is the authoritative membership (10.6); icon and
	# live count are derived here each tick from GameView's facts, the same
	# division of labour as the idle count above.
	_control_groups = mine.get("control_groups", [])
	for slot in range(SimPlayer.CONTROL_GROUP_COUNT):
		var members: Array = _control_groups[slot] if slot < _control_groups.size() else []
		var summary := _view.control_group_summary(members)
		EventBus.control_group_changed.emit(slot, summary["icon"], summary["count"])


## Tap handling (PLAN.md 3.6, 4.3, 4.5): `GameView.tap_action()` decides what
## the tap means -- reselect, gather, build-assist, move, or clear -- from pure
## facts about what is under the finger and what is already selected; this
## just carries out whichever it names and, for the three orders, drops an
## `ActionFlash` on the target so the player sees which one fired without
## reading the panel.
func _on_tapped(screen_pos: Vector2, from_touch: bool = false) -> void:
	if _orders_refused():
		return
	# Any tap at all invalidates a deferred deselect still waiting to fire; see
	# `_tap_token`'s own header for why the detector cannot tell on its own.
	_tap_token += 1
	# In build mode this tap is handled by `single_released` instead, once it
	# fires right after this. `InputRouter` guarantees `tapped` is resolved and
	# emitted BEFORE `single_released` for the same gesture (see its own
	# header), so `_placing_def_id` here is still whatever it was for the tap
	# that just happened -- never something a placement handler already
	# changed it to for the gesture that is about to follow.
	if _placing_def_id != &"":
		return
	var local: Vector2 = _view.get_global_transform_with_canvas().affine_inverse() * screen_pos
	var tile := Iso.tile_at(local)
	var picked := _view.pick(local, 0)
	var movable := _view.movable_selection()
	var owner := Net.local_player_id()

	match _view.tap_action(picked, owner, not movable.is_empty()):
		GameView.TapAction.SELECT:
			_view.select([picked] as Array[int])
			_refresh_panel()
		GameView.TapAction.GATHER:
			Net.submit_command(GatherCommand.new(owner, movable, picked))
			_flash.play(ActionFlash.Kind.GATHER,
					Iso.tile_centre_to_world(_view.facts_for(picked)["tile"]))
		GameView.TapAction.BUILD:
			Net.submit_command(BuildCommand.new(owner, movable, picked))
			_flash.play(ActionFlash.Kind.BUILD,
					Iso.tile_centre_to_world(_view.facts_for(picked)["tile"]))
		GameView.TapAction.ATTACK:
			Net.submit_command(AttackCommand.new(owner, movable, picked))
			_flash.play(ActionFlash.Kind.ATTACK,
					Iso.tile_centre_to_world(_view.facts_for(picked)["tile"]))
		GameView.TapAction.MOVE:
			if from_touch and not _commit_ground_tap(tile):
				return                    # deselect instead, once the window closes
			Net.submit_command(MoveCommand.new(owner, movable, tile))
			_flash.play(ActionFlash.Kind.MOVE, Iso.tile_centre_to_world(tile))
		GameView.TapAction.NONE:
			_clear_selection()


## True when this ground tap is the SECOND of a double and the move should go
## through now; false for a first tap, which instead schedules a deselect that
## fires only if no second tap arrives inside `DoubleTapDetector.DOUBLE_TAP_MS`.
##
## Touch only -- see `_ground_tap`'s header for why a mouse skips all of this.
func _commit_ground_tap(_tile: Vector2i) -> bool:
	var now := Time.get_ticks_msec()
	if _ground_tap.register_tap(now):
		return true

	# A widget outside a tree cannot schedule the wait; the same guard
	# `ControlGroupsHud` and `Minimap` document for their own deferred singles.
	if is_inside_tree():
		var token := _tap_token
		get_tree().create_timer(DoubleTapDetector.DOUBLE_TAP_MS / 1000.0).timeout.connect(
				func() -> void:
					if is_instance_valid(self) and token == _tap_token \
							and _ground_tap.is_still_pending(now):
						_clear_selection())
	return false


## Right-click on desktop (PLAN.md input feedback): back out of build mode if
## it is running, otherwise drop the selection. One button for "not that", so
## an abandoned placement never needs the pause menu to escape -- the same
## order Escape resolves them in.
func _on_context_cancel() -> void:
	if _orders_refused():
		return
	if _placing_def_id != &"":
		_exit_placement()
		return
	_clear_selection()


func _clear_selection() -> void:
	_view.select([] as Array[int])
	_refresh_panel()


## Enters placement mode for `def_id` (PLAN.md 5.1) and locks the camera: the
## same one finger that would otherwise pan now drags the ghost instead (see
## `CameraRig.locked`'s own header for why that trade beats swapping pan to two
## fingers). `_on_placement_pressed/_drag/_released` do the rest.
func _enter_placement(def_id: StringName) -> void:
	_placing_def_id = def_id
	_camera.set_locked(true)
	# Offered the moment the camera is locked, because that is the moment a touch player
	# loses every other way out. See `_cancel_build`.
	if _cancel_build != null:
		_cancel_build.visible = true
	# Shows the ghost immediately under the cursor rather than leaving it
	# invisible until the mouse so much as twitches (desktop only -- a touch
	# has no position to preview before it first comes down).
	_preview_placement(get_viewport().get_mouse_position())


func _exit_placement() -> void:
	_placing_def_id = &""
	_camera.set_locked(false)
	_ghost.visible = false
	if _cancel_build != null:
		_cancel_build.visible = false
	_refresh_panel()


func _on_placement_pressed(screen_pos: Vector2) -> void:
	if _placing_def_id != &"":
		_preview_placement(screen_pos)


func _on_placement_drag(screen_pos: Vector2) -> void:
	if _placing_def_id != &"":
		_preview_placement(screen_pos)


## Desktop only: a touch drags the ghost into position and releases to drop
## it (see `_on_placement_drag`), but a mouse has no reason to hold a button
## down just to move the cursor -- without this the ghost would sit frozen
## wherever the initiating click landed until the player thought to drag it.
func _on_placement_hover(screen_pos: Vector2) -> void:
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
		# The current selection goes with the order: whoever was selected when the
		# build menu was opened is who walks over and raises it. Sent as part of the
		# placement because the foundation has no id until the host spawns it -- see
		# PlaceBuildingCommand's own header.
		Net.submit_command(PlaceBuildingCommand.new(
				Net.local_player_id(), _placing_def_id, result["origin"],
				_view.movable_selection()))
		_exit_placement()
		return

	# Three different refusals, three different messages. "Can't build there" for
	# a field the player has dragged away from its mill is technically true and
	# tells them nothing about the rule they just broke.
	if not result["can_afford"]:
		_toast.show_message("Not enough resources")
	elif not result.get("placeable", true):
		_toast.show_message(_adjacency_hint(_placing_def_id))
	else:
		_toast.show_message("Can't build there")

	# A flash, not a permanent red ghost: it stays long enough to read as "no",
	# then clears so the next attempt starts from a blank slate.
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		if _placing_def_id != &"":
			_ghost.visible = false)


## Moves the ghost to the tile under `screen_pos`, snapped to the grid, and
## colours it by legality. Shared by the press/drag/release handlers so all
## three agree on exactly the same tile for the same point.
##
## A HOST ASKS ITS WORLD; A CLIENT ASKS WHAT IT CAN SEE (PLAN.md 12.1b).
##
## The host keeps the exact answer -- `Net.host().world` is right there, and the ghost
## then turns red in precisely the places `PlaceBuildingCommand.validate()` will refuse.
## A client has no world at all, so it falls back to `PlacementAdvice`: the map from the
## config, occupancy and adjacency from snapshot facts, affordability from the stock the
## snapshot reported.
##
## Two paths for one rule is normally the thing this codebase refuses to do -- and the
## reason it is right here is that only one of them is ever authoritative. The server
## validates every placement from either side, so the advisory path being wrong costs a
## refusal and a toast, never a divergence. See `PlacementAdvice` for where it is
## deliberately looser and which way it errs.
func _preview_placement(screen_pos: Vector2) -> Dictionary:
	var bd: BuildingDef = GameDataRegistry.building(_placing_def_id)
	if bd == null:
		_exit_placement()
		return {}

	var local: Vector2 = _view.get_global_transform_with_canvas().affine_inverse() * screen_pos
	var origin := Iso.tile_at(local)
	var rect := SimMap.footprint_rect(origin, bd.footprint)
	var me := Net.local_player_id()

	var can_afford := false
	var placeable := false
	var ground := false
	var host := Net.host()
	if host != null:
		var world: SimWorld = host.world
		var player := world.player_for(me)
		can_afford = player != null and player.can_afford(bd.cost)
		# Same adjacency call PlaceBuildingCommand.validate() makes, so the ghost
		# turns red exactly where the host would refuse -- a field dragged away from
		# its mill reads as illegal while it is being dragged, rather than being
		# accepted by the UI and silently dropped by the server.
		placeable = world.adjacency_allows(_placing_def_id, me, origin)
		ground = world.map.can_place_building(rect)
	else:
		var facts := _view.all_facts()
		can_afford = PlacementAdvice.can_afford(bd.cost, _view.stock_of(me))
		placeable = PlacementAdvice.adjacency_allows(_placing_def_id, me, origin, facts)
		ground = PlacementAdvice.can_place(_client_map, facts, rect)
	var valid := can_afford and placeable and ground

	var centre := Vector2(origin) + Vector2(bd.footprint) * 0.5
	_ghost.position = Iso.tile_to_world_f(centre)
	_ghost.set_state(Vector2(bd.footprint) * Iso.METRES_PER_TILE, valid)
	_ghost.visible = true

	return {"origin": origin, "valid": valid, "can_afford": can_afford,
			"placeable": placeable}


## Why an adjacency-gated placement was refused, in the player's words. Built
## from the def rather than hardcoded for the field, so the day a second building
## needs a host it says the right thing without being edited.
func _adjacency_hint(def_id: StringName) -> String:
	var bd: BuildingDef = GameDataRegistry.building(def_id)
	if bd == null or bd.requires_adjacent.is_empty():
		return "Can't build there"
	var hosts: Array[String] = []
	for host_id in bd.requires_adjacent:
		hosts.append(_display_name(host_id))
	var where := " or ".join(hosts)
	if bd.max_per_host > 0:
		return "%s must touch a %s (max %d)" % [_display_name(def_id), where, bd.max_per_host]
	return "%s must touch a %s" % [_display_name(def_id), where]


func _display_name(def_id: StringName) -> String:
	var bd: BuildingDef = GameDataRegistry.building(def_id)
	return bd.name if bd != null and not bd.name.is_empty() else String(def_id)


## The selection panel's plain verbs (UI_Design.md redesign). Only actions with
## a real command reach here -- `ActionSlot` swallows the disabled placeholders
## -- so this never has to re-check what MVP implements.
##
## Move and Harvest have no button-then-target flow of their own: tapping the
## ground already moves and tapping a tree already gathers (`_on_tapped`), so
## they answer with the hint that says so rather than adding a second, parallel
## way to issue the same order. Stop is the one that acts immediately, having
## no target to wait for.
func _on_action_requested(action_id: StringName) -> void:
	var movable := _view.movable_selection()
	match action_id:
		&"stop":
			if not movable.is_empty():
				Net.submit_command(StopCommand.new(Net.local_player_id(), movable))
				_toast.show_message("Holding position")
		&"move":
			_toast.show_message("Tap where to move")
		&"harvest":
			_toast.show_message("Tap a tree or resource to gather")
		&"attack":
			# Same hint-not-mode treatment as Move and Harvest: tapping an enemy
			# already attacks it, so a second targeting mode would be a parallel
			# way to issue an order the map already accepts.
			_toast.show_message("Tap an enemy to attack")


## The polite half of the population cap (PLAN.md 4.11). `TrainCommand.validate()`
## is what actually refuses, and it does so silently -- a command that fails
## validation is simply dropped, so without this the Train button would go dead at
## the cap with no explanation, which is the failure mode a full town centre and a
## broken button have in common.
##
## Asks `PopulationSystem` the same question the host will, through `Net.host()` --
## the documented solo-only exception `_preview_placement()` already uses to colour
## the placement ghost by the host's own adjacency rule, and for the same reason: a
## second implementation of the rule on this side would disagree with the server the
## first time either one changed. A remote client has no host to ask and will need
## the refusal sent back to it, which is a job for the multiplayer phase.
func _on_train_requested(building_id: int, unit_def_id: StringName) -> void:
	var ud: UnitDef = GameDataRegistry.unit(unit_def_id)
	var world: SimWorld = Net.host().world if Net.host() != null else null
	if ud != null and world != null \
			and not PopulationSystem.has_room_for(world, Net.local_player_id(), ud.pop_cost):
		# Names the fix, not just the rule: "Population limit reached" alone leaves a
		# new player looking for a setting, and the answer is always another house.
		_toast.show_message("Population limit reached -- build a house")
		return
	Net.submit_command(TrainCommand.new(Net.local_player_id(), building_id, unit_def_id))


func _on_cancel_requested(building_id: int, index: int) -> void:
	Net.submit_command(CancelProductionCommand.new(Net.local_player_id(), building_id, index))


func _on_debug_destroy_requested(target_id: int) -> void:
	Net.submit_command(DebugDestroyCommand.new(Net.local_player_id(), target_id))


## Starts the research; `AgeSystem` finishes it some seconds later. The badge's
## `next_age` is ignored -- AdvanceAgeCommand always advances to `age + 1` and
## has no field to be told otherwise, so a client cannot ask to skip one. The
## argument stays in the signal because the badge computing it is what proves
## there IS a next age before it emits.
##
## Goes through the ordinary command path rather than reaching into the world, so
## the ring fills from the next snapshot's `player_state` like everything else --
## there is no local clock to drift from the sim's.
func _on_age_advance_requested(_next_age: int) -> void:
	Net.submit_command(AdvanceAgeCommand.new(Net.local_player_id()))


## Blips (PLAN.md 8.2a). Separate from _refresh_hud() -- that one drains once
## per snapshot into EventBus signals other widgets read; the minimap is
## driven directly since nothing else needs "every entity's facts" broadcast
## for its sake.
func _refresh_minimap() -> void:
	_minimap.update_entities(_view.all_facts(), Net.local_player_id())
	_minimap.set_fog(_last_vision)


## Tap the minimap to move the camera there (PLAN.md 3.8) -- or, with units
## selected, to ORDER THEM THERE (3.7, asked for by the project owner
## 2026-08-20 once the tap reached this widget at all).
##
## The selection decides which of the two a tap means, exactly as it does for a
## tap on the ground in `_on_tapped`: with something movable selected a tap is
## an order, with nothing selected it is a camera move. That keeps one gesture
## from needing a modifier, and matches what the same tap already does out on
## the map.
##
## The camera deliberately does NOT follow the order. Sending troops across the
## map is not a reason to stop watching what is in front of you, and a player
## who wants to look can tap again with nothing selected.
func _on_minimap_tapped(tile: Vector2i) -> void:
	var movable := _view.movable_selection()
	if movable.is_empty():
		_camera.centre_on(Iso.tile_centre_to_world(tile))
		return
	if _orders_refused():
		return
	Net.submit_command(MoveCommand.new(Net.local_player_id(), movable, tile))
	_flash.play(ActionFlash.Kind.MOVE, Iso.tile_centre_to_world(tile))


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


## Tap the idle badge: select the next idle villager and bring the camera to it
## (PLAN.md 7.1). Five taps with five idle villagers visit all five, one per tap,
## then wrap round to the first.
##
## Selecting a unit does not give it a job, so the walk is stable: the same five
## are still idle after the fifth tap. What DOES change the list is the player
## then ordering one somewhere, which is the whole point of the badge -- and
## because the walk remembers an id rather than a position, the unit dropping
## out of the list leaves the next tap continuing from where it was rather than
## jumping back to the top.
##
## Silently does nothing with none left. The badge greys out at zero and never
## emits, and this stays defensive anyway: the count arrives with the snapshot,
## so between one landing and the tap being handled the last idle villager may
## already have been given a job by something else.
func _on_idle_cycle_requested() -> void:
	if _orders_refused():
		return
	var next := _view.next_idle_villager(Net.local_player_id(), _idle_cycle_id)
	if next == 0:
		return
	_idle_cycle_id = next
	_view.select([next] as Array[int])
	_refresh_panel()
	var facts := _view.facts_for(next)
	if facts.has("tile"):
		_camera.centre_on(Iso.tile_centre_to_world(facts["tile"]))


## Double tap (mobile) or Ctrl+digit (desktop): assign whatever is currently
## selected to the slot (PLAN.md 10.2). A no-op with nothing selected --
## `SetControlGroupCommand.validate()` rejects an empty assignment rather than
## clearing the slot, see that command's own header.
func _on_group_assign_requested(slot: int) -> void:
	var current := _view.selection.current()
	# An EMPTY selection clears the group rather than being ignored -- see
	# `SetControlGroupCommand.validate()` for why that changed.
	Net.submit_command(SetControlGroupCommand.new(Net.local_player_id(), slot, current))
	_toast.show_message(("Assigned to group %d" if not current.is_empty()
			else "Cleared group %d") % (slot + 1))


## PC control-group hotkeys (PLAN.md 10 session note): plain 1-5 reselects,
## Ctrl+1-5 assigns -- mobile's single/double-tap on the HUD icon are the same
## two actions under different input, so both paths end at the same handlers.
func _unhandled_key_input(event: InputEvent) -> void:
	if _orders_refused() or not (event is InputEventKey) or not event.is_pressed() \
			or event.is_echo():
		return
	var key := event as InputEventKey

	if key.keycode == KEY_ESCAPE:
		# Escape backs out of build mode first -- the Cancel Build button that
		# used to do this went away with the dev row, and leaving the pause menu
		# as the only way out of a half-started placement would be worse than
		# no way at all.
		if _placing_def_id != &"":
			_exit_placement()
		elif not _pause_menu.visible:
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
	if _orders_refused():
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
		# The skin gating the menus and tinting the portraits is the SELECTION
		# OWNER's, not the local player's: a selected enemy building shows what
		# THEY can train in THEIR colour, and reading our own would misreport
		# both the moment the two differ.
		var owner_id := int(facts.get("owner_id", 0))
		_panel.show_entity(facts, _view.selection.size(), is_mine, all_def_ids,
				_view.age_of(owner_id), int(_view.skin_for(owner_id).get("colour", -1)))
