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
## The settings/pause overlay. REACHED FROM THE SETTINGS CORNER BUTTON beside the
## minimap since 2026-08-21, not from a pause button in the age header -- see
## `_build_hud`. Still a `PauseMenu`, because Resume/Resign/Quit is still what it
## holds and renaming the class would only move the mismatch somewhere else.
var _pause_menu: PauseMenu

## The three full-screen pages behind the minimap's other three corner buttons
## (PLAN.md 8.2b). One is a mechanism and two are wireframes; see each class.
var _chat: ChatPanel
var _tech_tree: TechTreePanel
var _market: MarketPanel

## The minimap's four corner buttons by name (`chat`/`trade`/`techtree`/`settings`),
## so a dev preview can press the real control instead of calling its handler. Public
## for the same reason `PauseMenu` holds its resign button: on this screen a button
## wired to nothing has twice looked exactly like a working one.
var corner_buttons: Dictionary = {}

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

## Whether the next world tap AIMS the selected unit's special ability (PLAN.md 4.10)
## rather than being read as an ordinary order.
##
## Shaped after `_placing_def_id` above and cleared the same way -- one tap, armed or
## not, never both. It carries no ability id: the ability is whatever the one selected
## unit has, re-read at the moment of firing (`_selected_ability_def`), so a selection
## that changed while the mode was armed cannot fire the previous unit's ability.
var _ability_pending: bool = false
var _ghost: PlacementGhost
## The flag on the selected building's rally point, or hidden. ONE node reused rather
## than one per building: only the selected building's flag is ever drawn, so there is
## never a second to show — see `_refresh_waypoint_flag`.
var _waypoint_flag: WaypointFlag

## WALL DRAGS (PLAN.md 5.8), which use the same one-finger gesture to mean something
## else: for an ordinary building a drag MOVES the ghost, and for a wall it stretches
## a run between where the finger went down and where it is now.
##
## `_wall_anchor` is the tile the finger landed on, `Vector2i(-1, -1)` when no run is
## in progress. Kept rather than re-derived because the anchor is the one point in the
## gesture that no later event carries -- an edge-pan moves the ground under a finger
## that has not moved, and the anchor has to stay on the tile it was pressed on.
var _wall_anchor: Vector2i = Vector2i(-1, -1)

## The last planned run, so `_on_placement_released` submits exactly what the ghost
## was showing rather than re-planning against a tile the finger has since left.
var _wall_plan: Dictionary = {}

## What the thing under the finger costs, in words, over CANCEL BUILD.
##
## "12 segments, 144 wood" for a wall drag, and that is where it started: a wall's cost
## depends on how the run segments, which a player cannot count under their own thumb,
## and `PlaceWallCommand` places what it can afford and stops -- so without this a run
## simply came out shorter than the ghost with no explanation.
##
## It carries ORDINARY buildings too as of 2026-08-22 ("House — 30 wood"), on the
## project owner's request for costs per building and per unit. The grid tile already
## shows a compact "30W"; this is the roomy version and the only one that can say WHICH
## resource you are short of. The ghost turns red for three different reasons and its
## colour never said which one.
var _placement_readout: Label

## Where the placing finger last was, in screen pixels. Kept because an edge-pan moves
## the ground under a finger that is not itself moving, so the ghost has to be
## re-previewed at a position no incoming event is carrying.
var _placing_screen_pos := Vector2.ZERO

## Whether the current placement drag has earned the right to edge-pan. See
## `_track_edge_push`.
var _edge_armed := false

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

## Touch only: a tap on empty ground with units selected MOVES them there, and a
## DOUBLE tap deselects (project owner, 2026-08-22).
##
## THIS IS A DELIBERATE REVERSAL and the reasoning it reverses was not wrong, so it is
## worth keeping. The two were the other way round -- tap to deselect, double tap to
## move -- because a small, quick pan clears `InputRouter`'s slop and time bounds and
## so registers as a tap, which sent the selection wandering off whenever a player
## tried to scroll the map. That was found on device and it was real.
##
## What it traded away is worse, and it took playing to see it: EVERY order cost two
## taps. Moving is the commonest thing anybody does in an RTS, and paying double for it
## to protect against an occasional misfire is the wrong side of that bargain -- a
## stray move is one tap to correct, where a doubled tap count is paid on every order
## for the whole match.
##
## So the misfire is back and is now the known cost. If it bites on device the fix is
## `InputRouter.TAP_SLOP` / `TAP_TIME_MS`, which is where the discrimination actually
## belongs: telling a pan from a tap is the router's job, and encoding the answer in
## the gesture VOCABULARY was always a workaround for the router being too generous.
##
## A mouse was never affected either way: it does not wobble, it moves on one click,
## and desktop players get right-click to clear (`_on_context_cancel`).
var _ground_tap := DoubleTapDetector.new()

## The ground, on a client that has no `SimWorld` (PLAN.md 12.1b). Built once from the
## config's `MapData` and never ticked; the placement ghost reads it for terrain and gets
## everything standing on that terrain from snapshot facts. Null in solo, where the host's
## own world is the better answer and is right there to ask.
var _client_map: SimMap = null

## Turns snapshots into sound (PLAN.md 7.5). Here rather than inside `GameView`
## because it is a consumer of the snapshot, not part of the view's model of the
## world -- the same reason the HUD signals go out through `EventBus` from here.
var _audio := MatchAudio.new()

## TOUCH EMULATION IS OFF INSIDE THE MATCH AND ON EVERYWHERE ELSE (2026-08-22).
##
## The project setting is now `true`, and this is the one scene that turns it back off.
## The arrangement used to be the other way round -- off globally, because box select
## needs raw `InputEventScreenTouch` with real finger indices and emulation collapses
## them into one mouse (`InputRouter`'s header).
##
## That was right about the match and wrong about everything else. The MENUS are
## ordinary Godot UI, and Godot's `OptionButton` opens a `PopupMenu`, which is an
## embedded subwindow that never sees a raw touch: on the phone the lobby's Map, Seed,
## Players and Victory dropdowns opened and then would not accept a selection --
## reported from the device, reproduced over adb, and confirmed by the highlight never
## even moving off the first item, so the popup was getting no pointer input at all
## rather than mishandling it.
##
## Emulation cannot simply be left on for everyone: `InputRouter` handles
## `InputEventScreenTouch` AND `InputEventMouseButton` on separate paths, so with both
## arriving every tap would fire `tapped` twice and issue every order twice.
##
## So the special case now lives where the special input handling lives, which is also
## the honest place for it: exactly one scene does its own gesture recognition, and it
## is the only one that needs the raw events.
func _ready() -> void:
	Input.set_emulate_mouse_from_touch(false)

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
	# Whose fog the view computes (12.1f). The same id from the same place, so the fog and
	# the HUD can never end up describing two different players -- and set on BOTH paths,
	# because a client is named by the server after `_ready()` has already run.
	_view.local_player_id = Net.local_player_id()
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

	# BEFORE the flash, so a rally-point flash drawn on the same tile lands on top of
	# the flag rather than under it. Both are children of `_view`, so both pan and zoom
	# with the world.
	_waypoint_flag = WaypointFlag.new()
	_waypoint_flag.visible = false
	_view.add_child(_waypoint_flag)

	_flash = ActionFlash.new()
	_view.add_child(_flash)

	_camera = CameraRig.new()
	add_child(_camera)
	_camera.make_current()
	_camera.edge_scrolled.connect(_on_camera_edge_scrolled)

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
	_panel.research_requested.connect(_on_research_requested)
	_panel.cancel_requested.connect(_on_cancel_requested)
	_panel.ungarrison_requested.connect(_on_ungarrison_requested)
	_panel.debug_destroy_requested.connect(_on_debug_destroy_requested)
	_panel.place_requested.connect(_enter_placement)
	_panel.action_requested.connect(_on_action_requested)
	_panel.clear_requested.connect(_on_clear_pressed)
	hud.add_child(_panel)

	# Flush into the top-right corner, per the mockup -- it used to sit 64 px down,
	# which left a gap the dragon frame was never drawn to fill.
	_hud = ResourceHUD.new()
	_hud.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hud.offset_left = -ResourceHUD.PANEL_WIDTH
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
	minimap_area.position = Vector2(-Minimap.AREA_SIZE - _MINIMAP_MARGIN,
			-Minimap.AREA_SIZE - _MINIMAP_MARGIN)
	hud.add_child(minimap_area)

	# THE ORNATE DIAMOND FRAME, and it is drawn HERE rather than by `Minimap` itself.
	# That widget rotates its whole Control 45 degrees so it can draw terrain and
	# blips in plain unrotated coordinates; the frame art is already a diamond inside
	# a square, so a child of the minimap would come out at 45 degrees to the map it
	# frames. This area is the unrotated 200x200 the diamond sits in, which is the
	# frame's own shape.
	#
	# ITS FOUR CORNER BOSSES ARE WHERE THE FOUR CORNER BUTTONS GO, which is not luck:
	# the art was drawn from `UI_Design.jpg`'s frame, and that mockup is where the
	# chat/trade/tech-tree/settings arrangement came from in the first place. Added
	# FIRST so both the minimap and the buttons draw on top of it.
	if ResourceLoader.exists(_MINIMAP_FRAME_PATH):
		var frame := TextureRect.new()
		frame.texture = load(_MINIMAP_FRAME_PATH)
		frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_SCALE
		frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		minimap_area.add_child(frame)

	_minimap = Minimap.new()
	_minimap.position = Vector2(Minimap.AREA_SIZE - Minimap.SIZE, Minimap.AREA_SIZE - Minimap.SIZE) * 0.5
	_minimap.tapped.connect(_on_minimap_tapped)
	_minimap.double_tapped.connect(_on_minimap_double_tapped)
	minimap_area.add_child(_minimap)

	# PLAN.md 8.2b: FOUR REAL BUTTONS since 2026-08-21. They were disabled
	# placeholders while chat, trade and the tech tree had nothing behind them;
	# all four now open something. SETTINGS took over the pause menu from the
	# button that used to sit in the age header, which is what retired that one.
	# Added to minimap_area AFTER the minimap so they sit on top of the rotated
	# diamond's tips and stay clickable rather than being covered by them.
	#
	# EACH ON ITS OWN MEASURED BOSS (`_MINIMAP_BOSS_CENTRES`), placed absolutely.
	# This was a 3-column GridContainer spanning the whole area, with a flex spacer
	# in the middle column pushing each pair out to its corners and one shared inset
	# for all four. That arrangement could only ever express ONE position, mirrored,
	# and the art does not have one -- which is why the bottom pair sat low and splayed
	# outwards however the inset was tuned.
	#
	# Two hazards go away with the grid rather than being worked around. It covered the
	# WHOLE area and was added after the minimap, so Godot hit-tested it first and every
	# tap on the diamond died there until each piece of it was individually set to
	# MOUSE_FILTER_IGNORE; and its middle column began as stacked `VSeparator`s, which
	# draw a line -- that is what a separator is for -- straight down the middle of the
	# map (owner-reported 2026-08-21). Four 32 px buttons touching nothing between them
	# have neither problem to have.
	var corners := [
		[&"chat", "hud_chat.png", _on_chat_pressed],
		[&"trade", "hud_trade.png", _on_market_pressed],
		[&"techtree", "hud_techtree.png", _on_tech_tree_pressed],
		[&"settings", "hud_settings.png", _on_settings_pressed],
	]
	for i in range(corners.size()):
		var corner_btn := _corner_button(corners[i])
		corner_btn.position = _MINIMAP_BOSS_CENTRES[i] * Minimap.AREA_SIZE \
				- Vector2.ONE * CORNER_BUTTON_SIZE * 0.5
		minimap_area.add_child(corner_btn)

	_toast = NoticeToast.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	# Half its own width, so it stays centred when the banner's proportions decide the
	# width rather than a literal here. This was -160 against a hardcoded 320.
	_toast.position = Vector2(-NoticeToast.SIZE.x * 0.5, 409.0)
	hud.add_child(_toast)

	# In the gap BETWEEN the build grid and the minimap, which is the only part of the
	# bottom edge free while placing. Bottom centre looked empty and is not: the build
	# grid opens there, so a cancel button sat straight on top of the menu it belongs to
	# -- caught by `preview_match`'s screenshot, not by the code.
	#
	# SIZED AND ALIGNED TO THE ACTION TILES ON THE OTHER SIDE OF THE SCREEN (project
	# owner, 2026-08-30: *"cancel build needs to move left, its currently over the mini
	# map and 50% too big, match the size of the unit action icons row so left and right
	# side of screen line up"*). It was 280x80 at a fixed -512, which put its right edge
	# 20 px INSIDE the minimap area -- see `_CANCEL_RECT` for the arithmetic that is now
	# derived rather than typed.
	_cancel_build = Button.new()
	_cancel_build.text = "CANCEL BUILD"
	_cancel_build.add_theme_font_size_override("font_size", 16)
	# Two tiles' worth of width is not enough for "CANCEL BUILD" on one line at 16 pt
	# once the plate's 18 px content margins are taken off, so it breaks over two --
	# which is why the button is a whole tile TALL rather than the half it would need.
	_cancel_build.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_place_bottom_right(_cancel_build, _CANCEL_RECT)
	_cancel_build.visible = false
	_cancel_build.pressed.connect(_exit_placement)
	hud.add_child(_cancel_build)

	# Directly above CANCEL BUILD and exactly as wide, in the same gap between the build
	# grid and the minimap. TWO LINES' WORTH OF BOX, bottom-aligned: a wall drag's
	# "12 segments, 144 wood" does not fit one line at this width, and a label that grew
	# downward would push into the button rather than away from it.
	_placement_readout = Label.new()
	_placement_readout.add_theme_font_size_override("font_size", 16)
	_placement_readout.add_theme_color_override("font_color", HudStyle.GOLD)
	_placement_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placement_readout.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_placement_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_place_bottom_right(_placement_readout, Rect2(
			_CANCEL_RECT.position - Vector2(0.0, _READOUT_HEIGHT + 6.0),
			Vector2(_CANCEL_RECT.size.x, _READOUT_HEIGHT)))
	_placement_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placement_readout.visible = false
	hud.add_child(_placement_readout)

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

	# THE PAUSE BUTTON IS GONE FROM HERE (project owner, 2026-08-21). It began as
	# its own TextureButton pinned to the top-right corner, was folded into this
	# header by the ui_builder mockup so the top-of-screen chrome read as one panel,
	# and is now retired: its actions live behind the SETTINGS corner button beside
	# the minimap, which is where a player looks for them and where three sibling
	# pages already are. The badge column below is what is left of the pair.
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
	_age_badge.advance_unavailable.connect(_on_age_advance_unavailable)
	age_top_row.add_child(_age_badge)

	# The idle count, beside the age badge -- what is left of the mockup's
	# `VillagersIdle` VBox now that the pause button above it has gone. Added
	# straight to the row rather than kept in a one-child column: the column existed
	# to stack the two, and its minimum width is the badge's own.
	_idle_badge = IdleVillagerBadge.new()
	_idle_badge.cycle_requested.connect(_on_idle_cycle_requested)
	age_top_row.add_child(_idle_badge)

	_pause_menu = PauseMenu.new()
	hud.add_child(_pause_menu)

	# The three pages behind the other corner buttons (8.2b). Built here rather than
	# on first press so a preview and a test can reach them without a tap, which is
	# the same reason every widget on this screen is built up front.
	#
	# NONE OF THEM STOPS THE CLOCK, unlike the pause menu beside them: a market has
	# to show live stockpiles to be worth opening. See `HudPanel`'s header.
	_chat = ChatPanel.new()
	hud.add_child(_chat)

	_tech_tree = TechTreePanel.new()
	hud.add_child(_tech_tree)

	_market = MarketPanel.new()
	_market.tribute_requested.connect(_on_tribute_requested)
	_market.exchange_requested.connect(_on_exchange_requested)
	hud.add_child(_market)

	# ADDED AFTER ALL OF THEM, so it draws over the lot. If the match is decided
	# while the player happens to have a page open, the result is the thing that
	# outranks -- and the pause menu's Resume would otherwise restart a clock the
	# result screen has just stopped.
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
	_error_label.offset_right = -(ResourceHUD.PANEL_WIDTH + 24.0)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_error_label.visible = false
	hud.add_child(_error_label)


## The size of one minimap corner button, and therefore the whole of its hit area.
const CORNER_BUTTON_SIZE := 32.0

## The minimap area's inset from the bottom-right corner of the screen. Named because
## CANCEL BUILD is now placed by measuring back from the minimap's outer edge, so the
## two have to agree.
const _MINIMAP_MARGIN := 12.0

## The ornate diamond around the minimap ([P8], 2026-08-30). `Minimap`'s own header
## used to record that no such art existed and that it approximated the frame with a
## double gold `draw_rect`; it exists now, and that approximation is gone.
const _MINIMAP_FRAME_PATH := "res://assets/ui/chrome/frame_minimap.png"

## The centre of each corner boss in the frame art, as a fraction of the frame's own
## size: top-left, top-right, bottom-left, bottom-right, matching `_MINIMAP_CORNERS`.
##
## FOUR POSITIONS RATHER THAN ONE INSET, AND THAT IS THE WHOLE OF THE SECOND FIX. The
## project owner reported these off twice. The first version took the centroid of every
## dark pixel per quadrant, which answers a different question -- the field between the
## diamond and the outer square is dark too -- and was ~14 px out. The second labelled
## the connected dark regions, kept the one in each quadrant that is actually ROUND, and
## then AVERAGED THE FOUR ANSWERS INTO ONE NUMBER (0.109). That last step is what was
## still wrong, and it threw away the finding: the four discs are not at one inset. The
## art is cleanly mirrored left-to-right, but its BOTTOM bosses are bigger than its top
## ones and sit further in -- 87 px against 75 px on a 512 px frame -- so one inset
## cannot put all four buttons on their recesses, and it put the bottom pair about 3 px
## low and splayed outwards. That is the tech-tree glyph overhanging its rim in the
## owner's screenshot.
##
## So each button is placed on its OWN measured disc. The general form is the lesson and
## it is the same one twice over: four samples that disagree are not one measurement,
## and averaging them is not how you resolve that -- it is how you hide it.
const _MINIMAP_BOSS_CENTRES: Array[Vector2] = [
	Vector2(0.1045, 0.1018), Vector2(0.8955, 0.1018),
	Vector2(0.1162, 0.8806), Vector2(0.8838, 0.8806),
]

## Space between CANCEL BUILD's right edge and the minimap area's left edge.
const _CANCEL_GAP := 24.0

## Room for two lines of placement readout at 16 pt.
const _READOUT_HEIGHT := 44.0

## CANCEL BUILD's box, as offsets back from the screen's bottom-right corner.
##
## EVERY NUMBER IS DERIVED, because the two that were typed were both wrong (project
## owner, 2026-08-30). It was 280x80 at a literal -512, which put its right edge at
## 20 px INSIDE the minimap area -- and a fixed offset could not know that, because the
## minimap's own left edge is `_MINIMAP_MARGIN + Minimap.AREA_SIZE` and neither of those
## is written down here.
##
## The SIZE is two action tiles by one. The owner asked for it to *"match the size of
## the unit action icons row so left and right side of screen line up"*, and the tile is
## the unit that row is built from, so the button is a whole number of them rather than
## a size that merely looks similar. Its BOTTOM sits on `SelectionPanel.EDGE_PAD`, which
## is where that row's bottom edge is -- that is the "line up".
const _CANCEL_RECT := Rect2(
	-(_MINIMAP_MARGIN + Minimap.AREA_SIZE + _CANCEL_GAP + ActionSlot.SIZE * 2.0),
	-(SelectionPanel.EDGE_PAD + ActionSlot.SIZE),
	ActionSlot.SIZE * 2.0, ActionSlot.SIZE)


## Put `control` in `rect`, where `rect` is measured back from the screen's bottom-right
## corner (so its position is negative).
##
## OFFSETS, NOT `position`, and this file's own HUD comment says why: `position` on an
## anchored Control writes offset_left/offset_top and leaves the other two wherever they
## were, so what you get is a rect whose size is whatever the layout pass decides. Both
## controls placed through here want a size that is pinned, not inferred.
static func _place_bottom_right(control: Control, rect: Rect2) -> void:
	control.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.position.x + rect.size.x
	control.offset_bottom = rect.position.y + rect.size.y


## One corner button (chat/trade/tech-tree/settings); shared by the two rows
## `_build_hud()` assembles around the minimap.
##
## THESE WERE DISABLED PLACEHOLDERS UNTIL 2026-08-21, dimmed and set to
## MOUSE_FILTER_IGNORE so they could not block the minimap taps that pass over the
## rotated diamond's tips. All four have somewhere to go now, so they are STOP -- and
## since they are no longer in a container spanning the whole area, STOP now covers
## 32x32 of boss and nothing else. The caller positions each one on its own recess.
func _corner_button(spec: Array) -> TextureButton:
	var corner_btn := TextureButton.new()
	var icon_path := "res://assets/ui/icons/%s" % String(spec[1])
	if ResourceLoader.exists(icon_path):
		corner_btn.texture_normal = load(icon_path)
	corner_btn.ignore_texture_size = true
	corner_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	# LINEAR: 100 px of painted glyph drawn at CORNER_BUTTON_SIZE, which is 32.
	corner_btn.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# SIZE, not just a minimum. Outside a container nothing else is going to decide it,
	# and the position the caller sets assumes exactly this box: it centres the button
	# on a measured disc by subtracting half of this.
	corner_btn.custom_minimum_size = Vector2(CORNER_BUTTON_SIZE, CORNER_BUTTON_SIZE)
	corner_btn.size = Vector2(CORNER_BUTTON_SIZE, CORNER_BUTTON_SIZE)
	corner_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	# Half-lit until the first snapshot says otherwise. Only TRADE ever comes back
	# lit-or-not (`_feed_pages`); the other three have no precondition, so they are
	# restored here rather than left dim by an ordering accident.
	corner_btn.modulate = Color.WHITE
	corner_btn.pressed.connect(spec[2] as Callable)
	# HELD BY NAME so a preview can press the REAL button rather than call the
	# handler behind it. That distinction has already earned its keep twice on this
	# screen -- the cancel-build button and the resign button were both wired to
	# nothing at one point, and calling the handler would have passed either way.
	corner_buttons[spec[0] as StringName] = corner_btn
	return corner_btn


# ── the minimap's four corners (PLAN.md 8.2b) ───────────────────────────────

## Settings, which is the pause menu: Resume, Resign, Quit. It moved here from a
## button in the age header (see `_build_hud`) and nothing about the menu changed.
func _on_settings_pressed() -> void:
	_close_pages()
	_pause_menu.open()


func _on_chat_pressed() -> void:
	_toggle_page(_chat)


func _on_tech_tree_pressed() -> void:
	_toggle_page(_tech_tree)


func _on_market_pressed() -> void:
	_toggle_page(_market)


## ONE PAGE AT A TIME, and pressing the corner you are already on closes it.
##
## They are full-screen overlays, so two open at once means one invisibly on top of
## the other -- and the one underneath would still be taking the taps meant for the
## page the player can see. Toggling rather than only opening also gives a phone a
## second way out of every page, which matters because a phone has no Escape key.
func _toggle_page(page: HudPanel) -> void:
	var was_open := page.is_open()
	_close_pages()
	if not was_open:
		page.open()
		_feed_pages(_last_snapshot)


func _close_pages() -> void:
	for page in [_chat, _tech_tree, _market]:
		if page != null and page.is_open():
			page.close()


## DIMMED, NOT DISABLED, and the difference is the point.
##
## Trade needs a finished market, and the corner icon says so by going half-lit --
## the same "not yet" the build menu's age-gated entries use. It still OPENS, because
## a disabled icon teaches nobody what a market is for: the page itself names the
## building and says every button stays refused until one is standing, which is the
## only place that sentence can be read. The refusal that matters is in
## `TributeCommand`/`MarketExchangeCommand`, on the server, where it cannot be dimmed
## around.
func _set_corner_dimmed(name: StringName, dimmed: bool) -> void:
	var button: TextureButton = corner_buttons.get(name)
	if button == null:
		return
	button.modulate = Color(1.0, 1.0, 1.0, 0.5 if dimmed else 1.0)


## Push this tick's facts into whichever page is open, and only that one. A closed
## page is not refreshed at all: the market rebuilds a row per player and the chat
## rebuilds its tab row, and doing that ten times a second for three pages nobody is
## looking at is work with no reader.
func _feed_pages(snap: Dictionary) -> void:
	var player_state: Dictionary = snap.get("player_state", {})
	if player_state.is_empty():
		return
	var me := Net.local_player_id()

	if _chat.is_open():
		_chat.show_players(player_state, me)
	if _tech_tree.is_open():
		var mine: Dictionary = player_state.get(me, {})
		_tech_tree.set_age(int(mine.get("age", 0)))
		# The VIEWER's own set, not the selection's -- this page is a reference about
		# what you have, and there is nothing on it to press (9.3, 9.4).
		_tech_tree.set_researched(_view.researched_of(me))
	# ADVISORY, and computed from the client's own view rather than asked of the host:
	# your own buildings are always sent whatever the fog says, so this is reliable
	# for the one owner it is asked about -- and both market commands re-check it
	# against the authoritative world anyway. Same shape as the placement ghost, where
	# a wrong answer costs a refusal and not a desync.
	#
	# Read even when the page is CLOSED, because the corner icon is dimmed by it.
	var has_market := _view.has_completed_building(
			me, GameDataRegistry.market_building())
	_set_corner_dimmed(&"trade", not has_market)
	if _market.is_open():
		_market.show_state(player_state, me, has_market)


## Tribute (8.2b), through the ordinary command path like every other order. The
## page names a recipient and an amount; the server decides whether it may happen,
## and overwrites the sender with the id it knows this peer owns -- so this cannot
## be made to spend somebody else's stockpile.
func _on_tribute_requested(to_player_id: int, kind: StringName, amount: int) -> void:
	if _match_over:
		return
	Net.submit_command(TributeCommand.new(
			Net.local_player_id(), to_player_id, kind, amount))


## Buying or selling one lot at the market. The PRICE IS NOT SENT -- the command
## carries what to trade and which way, and the server looks up what that costs.
func _on_exchange_requested(kind: StringName, buying: bool) -> void:
	if _match_over:
		return
	Net.submit_command(MarketExchangeCommand.new(Net.local_player_id(), kind, buying))


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
		# Which tree species this map draws (visuals.json `variant_pools`). From the
		# map's OWN `meta.type` rather than from `cfg.map_type`, which records what the
		# lobby asked for -- and what it usually asked for is Random, which resolves
		# inside the generator and would leave every random match with no pool at all.
		_view.variant_pool = MapGenerator.pool_name(
				int(md.meta.get("type", cfg.map_type)) as MapGenerator.Type)
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
	# Whose fog the view computes (12.1f). The same id from the same place, so the fog and
	# the HUD can never end up describing two different players -- and set on BOTH paths,
	# because a client is named by the server after `_ready()` has already run.
	_view.local_player_id = Net.local_player_id()
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


## The local player's fog. **No longer cached from the snapshot** (12.1f): the grid is not
## sent any more, so the answer lives in `GameView.client_fog` and this reads it after
## `apply_snapshot()` has recomputed it. Kept as a field for the reason it always was --
## `_refresh_minimap()` needs the bytes and does not receive the snapshot.
var _last_vision: PackedByteArray = PackedByteArray()

## The last snapshot, kept whole for the three corner pages (8.2b).
##
## They are refreshed only while OPEN, so opening one has to draw it from something
## other than the next snapshot -- otherwise a page opened between ticks shows a
## blank market for up to 100 ms, which on a touch screen is long enough to press
## through. The other HUD widgets need no equivalent because they are always visible
## and are fed every tick.
var _last_snapshot: Dictionary = {}


func _on_snapshot(snap: Dictionary) -> void:
	_view.apply_snapshot(snap)
	# AFTER apply_snapshot, not before: that call is what recomputes the fog from this
	# tick's facts, and reading it first would put last tick's fog on the minimap.
	if _view.client_fog != null:
		_last_vision = _view.client_fog.cells
	_last_snapshot = snap
	_refresh_panel()
	_refresh_hud(snap)
	_refresh_minimap()
	_feed_pages(snap)
	_refresh_result(snap)
	# The camera's centre is the listener, so a battle off the edge of the screen
	# is not heard (`AudioManager._AUDIBLE_RADIUS_PX`). Passed in rather than
	# looked up, because the autoload has no business knowing this scene's shape.
	# A CameraRig's `position` IS the middle of the screen (`centre_on` sets it
	# through `clamped_centre`), so it is the listener with nothing to derive.
	_audio.observe(snap, Net.local_player_id(),
		_camera.position if _camera != null else Vector2.INF)


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

	# AN ARMED ABILITY EATS THIS TAP (4.10), before `tap_action` gets to read it as a
	# move or an attack. Checked after the placement guard above and before everything
	# else, which is the same slot in the same order for the same reason: a targeting
	# mode is the whole meaning of the tap while it is on.
	if _ability_pending:
		_fire_ability(picked, tile)
		return

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
		GameView.TapAction.GARRISON:
			# Sent WHOLE rather than trimmed to the free slots (4.8). The tower may fill
			# up while they walk and `GarrisonSystem` stands the latecomers down where
			# they arrive; deciding here how many will fit would be the client guessing
			# at a state several seconds in the future.
			Net.submit_command(GarrisonCommand.new(owner, movable, picked))
			_flash.play(ActionFlash.Kind.GARRISON,
					Iso.tile_centre_to_world(_view.facts_for(picked)["tile"]))
		GameView.TapAction.MOVE:
			# SINGLE TAP MOVES, DOUBLE TAP LETS GO. The two were the other way round
			# until 2026-08-22; see `_ground_tap`'s header for what that cost and why
			# the project owner swapped them back.
			#
			# The move goes out on the FIRST tap, so a double tap moves and then
			# deselects rather than doing nothing. That is the honest reading of "tap
			# to move, double tap to deselect" and it is also the only one that keeps
			# a single tap instant: waiting to find out whether a second tap is coming
			# would put `DOUBLE_TAP_MS` of lag on every order in the game.
			if from_touch and _ground_tap.register_tap(Time.get_ticks_msec()):
				_clear_selection()
				return
			# The formation rides out ON the order and is not stored anywhere in the sim
			# (4.14). `Formation.NONE` -- the usual case -- is exactly the behaviour this
			# line had before formations existed.
			Net.submit_command(MoveCommand.new(owner, movable, tile, 0,
					_panel.active_formation))
			_flash.play(ActionFlash.Kind.MOVE, Iso.tile_centre_to_world(tile))
		GameView.TapAction.WAYPOINT:
			# The rally point for the ONE selected building (4.8's follow-up).
			# `waypoint_target` is what decided this branch was reachable at all, so it
			# is asked again rather than a second rule being written here.
			var building := _view.waypoint_target(owner)
			if building != 0:
				Net.submit_command(SetWaypointCommand.new(owner, building, tile))
				# The flash fires NOW and the flag appears on the next snapshot, which is
				# the whole reason there is a flash: a command round-trips through the
				# sim, so without it a tap on grass would look like nothing happened for
				# a tick or two.
				_flash.play(ActionFlash.Kind.WAYPOINT, Iso.tile_centre_to_world(tile))
		GameView.TapAction.NONE:
			_clear_selection()


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


## The selection panel's [X] (PLAN.md 8.8) -- the touch answer to a double-tap that
## does not survive a thumb (BUGS.md 2026-08-23).
##
## It is the SAME VERB as right-click, so it is guarded the same way and it backs out
## of a placement the same way. Two differences from `_on_context_cancel`, both
## deliberate:
##
##   It clears in ONE press rather than two. Right-click is a general "not that" and
##   resolving one thing per press is right for a key that is always available; this
##   button says [X] on a panel, is only there while that panel is, and a player who
##   presses it has finished with the selection -- leaving the villager selected and
##   the ghost gone would look like a press that half worked.
##
##   `_exit_placement` still runs first. Placement belongs to the selection that
##   opened it, so clearing without it would leave a locked camera and a live
##   `_placing_def_id` with nothing selected to build it.
func _on_clear_pressed() -> void:
	if _orders_refused():
		return
	if _placing_def_id != &"":
		_exit_placement()
	_clear_selection()


func _clear_selection() -> void:
	# AN ARMED ABILITY GOES WITH THE SELECTION (4.10). It is aimed by whichever unit is
	# selected, so a mode outliving its caster is a mode that fires nothing and swallows
	# the next tap -- `_fire_ability` would find no def and return silently, which is a
	# tap the player made and the game ignored. Cleared here rather than only in
	# `_on_clear_pressed`, because this is the function every route to an empty selection
	# goes through: the [X], the double tap, and a unit that died.
	_ability_pending = false
	_view.select([] as Array[int])
	_refresh_panel()


## Enters placement mode for `def_id` (PLAN.md 5.1) and locks the camera: the
## same one finger that would otherwise pan now drags the ghost instead (see
## `CameraRig.locked`'s own header for why that trade beats swapping pan to two
## fingers). `_on_placement_pressed/_drag/_released` do the rest, and dragging the
## ghost into the edge strip pans the locked camera rather than dead-ending there
## (`_track_edge_push`).
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
	_wall_anchor = Vector2i(-1, -1)
	_wall_plan = {}
	if _cancel_build != null:
		_cancel_build.visible = false
	if _placement_readout != null:
		_placement_readout.visible = false
	_refresh_panel()


## Hand touch emulation back on the way out, or every menu the player returns to has
## dead dropdowns for the rest of the session. See `_ready`.
func _exit_tree() -> void:
	Input.set_emulate_mouse_from_touch(true)


## Whether the thing being placed is a wall tier rather than one building.
func _placing_a_wall() -> bool:
	var bd: BuildingDef = GameDataRegistry.building(_placing_def_id)
	return bd != null and bd.is_wall_run()


func _on_placement_pressed(screen_pos: Vector2) -> void:
	if _placing_def_id == &"":
		return
	# A new finger starts DISARMED: see `_track_edge_push`.
	_edge_armed = false
	# THE FINGER GOING DOWN IS WHAT ANCHORS A WALL RUN. Set before the preview, so
	# the first frame of the drag already has both ends -- a run anchored on the frame
	# after would flash a single segment at the origin.
	if _placing_a_wall():
		_wall_anchor = _tile_under(screen_pos)
	_track_edge_push(screen_pos)
	_preview_placement(screen_pos)


func _on_placement_drag(screen_pos: Vector2) -> void:
	if _placing_def_id != &"":
		_track_edge_push(screen_pos)
		_preview_placement(screen_pos)


## Points the camera's edge-pan at wherever the placing finger now is, and remembers
## the position so `_on_camera_edge_scrolled` can re-read the ground under it.
##
## ARMING. The strip cannot push until the finger has been seen outside it at least
## once during this drag. Without that, a placement that begins with a press inside a
## strip scrolls the instant it starts -- and the build grid opens along the bottom
## edge, so the tap that chooses a building leaves the finger exactly there. The
## player has to mean it.
func _track_edge_push(screen_pos: Vector2) -> void:
	_placing_screen_pos = screen_pos
	var push := _camera.edge_push_for(screen_pos)
	if push == Vector2.ZERO:
		_edge_armed = true
	_camera.edge_push = push if _edge_armed else Vector2.ZERO


## The map slid under a finger that is holding still, so the tile beneath it is a
## different tile now and the ghost has to be recoloured for it.
func _on_camera_edge_scrolled() -> void:
	if _placing_def_id != &"":
		_preview_placement(_placing_screen_pos)


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
	# The finger is up, so the map stops here -- including on a refused drop, which
	# stays in build mode and would otherwise keep sliding with nothing driving it.
	_camera.edge_push = Vector2.ZERO

	if _placing_a_wall():
		_release_wall(screen_pos)
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
## The tile under a screen point. One place, because the wall drag needs it for its
## anchor and `_preview_placement` needs it for the ghost, and two copies of the
## canvas-transform inverse is two chances to use the wrong one.
func _tile_under(screen_pos: Vector2) -> Vector2i:
	var local: Vector2 = _view.get_global_transform_with_canvas().affine_inverse() * screen_pos
	return Iso.tile_at(local)


# ── wall runs (PLAN.md 5.8) ─────────────────────────────────────────────────

## Plan the run from the anchor to the finger, draw every segment, and say what it
## costs. Called from press, drag, hover and release, so all four agree.
##
## PLANNED BY `WallPlan`, the same function `PlaceWallCommand` will use on the server.
## That is the whole reason the segmentation lives in `src/sim/`: a ghost drawn from
## one implementation and a wall built from another would differ by a segment
## somewhere, and the player would only ever see it after letting go.
##
## Legality is per segment and ADVISORY, exactly as for a single building -- a host
## asks its own world, a client asks `PlacementAdvice`. What it cannot show is the
## budget running out mid-run, because that depends on the order the server pays in;
## the readout gives the total instead.
func _preview_wall(screen_pos: Vector2) -> Dictionary:
	var bd: BuildingDef = GameDataRegistry.building(_placing_def_id)
	if bd == null:
		_exit_placement()
		return {}

	var head := _tile_under(screen_pos)
	# A hover before the finger has ever gone down has no anchor, so the run is the
	# single segment under the cursor -- which is also what a tap-and-release places.
	var anchor := _wall_anchor if _wall_anchor != Vector2i(-1, -1) else head

	var lengths := WallPlan.lengths_of(bd.wall_lengths, GameDataRegistry.building)
	_wall_plan = WallPlan.plan(anchor, head, lengths)
	var segments: Array = _wall_plan.get("segments", [])

	var me := Net.local_player_id()
	var host := Net.host()
	var facts := _view.all_facts() if host == null else {}
	var cost: Dictionary = {}
	var entries: Array[Dictionary] = []
	var legal := 0

	for seg in segments:
		var origin: Vector2i = seg["origin"]
		var footprint: Vector2i = seg["footprint"]
		var rect := SimMap.footprint_rect(origin, footprint)
		var ground := false
		if host != null:
			ground = (host.world as SimWorld).map.can_place_building(rect)
		else:
			ground = PlacementAdvice.can_place(_client_map, facts, rect)
		if ground:
			legal += 1
			var seg_def: BuildingDef = GameDataRegistry.building(seg["def_id"])
			if seg_def != null:
				for kind in seg_def.cost:
					cost[kind] = int(cost.get(kind, 0)) + int(seg_def.cost[kind])
		entries.append({
			"world": Iso.tile_to_world_f(Vector2(origin) + Vector2(footprint) * 0.5),
			"footprint_m": Vector2(footprint) * Iso.METRES_PER_TILE,
			"valid": ground,
		})

	# The node sits on the ANCHOR and every segment is drawn as an offset from it, so
	# the run moves as one object rather than each box being positioned absolutely.
	_ghost.position = Iso.tile_to_world_f(Vector2(anchor) + Vector2(0.5, 0.5))
	_ghost.set_run(entries)
	_ghost.visible = true

	_placement_readout.text = _wall_cost_text(legal, segments.size(), cost)
	_placement_readout.visible = true
	return {"segments": segments.size(), "legal": legal, "cost": cost}


## "9 segments — 108 wood", or what is missing. Reads the same stock the resource
## counter shows, so a player can tell "the run is too long" from "I am short".
func _wall_cost_text(legal: int, total: int, cost: Dictionary) -> String:
	if total == 0:
		return ""
	var parts: Array[String] = []
	# In the resource counter's order, so the two read the same way round -- the same
	# reason the market page reorders its rows.
	for kind in ResourceHUD.DISPLAY_ORDER:
		if cost.has(kind):
			parts.append("%d %s" % [int(cost[kind]), kind])
	var head := "%d segment%s" % [legal, "" if legal == 1 else "s"]
	if legal < total:
		head += " of %d" % total
	if parts.is_empty():
		return head
	var line := "%s — %s" % [head, ", ".join(parts)]
	# AFFORDABILITY IS ADVISORY AND SAID PLAINLY. `PlaceWallCommand` places what it
	# can and stops, so a player who drags past their budget gets a shorter wall; this
	# is the only warning before that happens.
	var stock := _view.stock_of(Net.local_player_id())
	for kind in cost:
		if int(stock.get(kind, 0)) < int(cost[kind]):
			return "%s (short on %s)" % [line, kind]
	return line


## Let go of a wall drag: submit the run and leave build mode.
##
## Submitted even when some segments are illegal, because a run is partial by design
## and the server skips what it cannot place -- refusing the whole thing because a
## drag clipped one tree would be the opposite of what dragging means. Refused only
## when NOTHING can be placed, which is the case worth a message.
func _release_wall(screen_pos: Vector2) -> void:
	var result := _preview_wall(screen_pos)
	if result.is_empty():
		return
	if int(result.get("legal", 0)) == 0:
		_toast.show_message("No room for a wall there")
		get_tree().create_timer(0.3).timeout.connect(func() -> void:
			if _placing_def_id != &"":
				_ghost.visible = false)
		return

	# The selection that opened the build menu is who walks over, spread across the
	# segments by the command -- see `PlaceWallCommand._send_builders`.
	Net.submit_command(PlaceWallCommand.new(
			Net.local_player_id(), _placing_def_id,
			_wall_anchor if _wall_anchor != Vector2i(-1, -1) else _tile_under(screen_pos),
			_tile_under(screen_pos), _view.movable_selection()))
	_exit_placement()


func _preview_placement(screen_pos: Vector2) -> Dictionary:
	if _placing_a_wall():
		return _preview_wall(screen_pos)

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

	# THE PRICE, over CANCEL BUILD, for an ordinary placement as well as for a wall
	# drag (project owner, 2026-08-22). The tile in the grid already carries a compact
	# "30W"; this is the roomy version, and it is the one that can say you cannot
	# afford it -- the ghost turns red for three different reasons and the colour
	# alone never said which.
	_placement_readout.text = _building_cost_text(bd, can_afford)
	_placement_readout.visible = true

	return {"origin": origin, "valid": valid, "can_afford": can_afford,
			"placeable": placeable}


## "House — 30 wood", plus what is missing. The single-building twin of
## `_wall_cost_text`, kept separate because the two say genuinely different things: a
## wall's total depends on how the run segments and is not known until the drag, where
## a house costs what its def says before the finger goes down.
func _building_cost_text(bd: BuildingDef, can_afford: bool) -> String:
	var parts: Array[String] = []
	# The resource counter's order, so the two read the same way round -- the same
	# reason the market page and the wall readout order theirs.
	for kind in ResourceHUD.DISPLAY_ORDER:
		if bd.cost.has(kind) and int(bd.cost[kind]) > 0:
			parts.append("%d %s" % [int(bd.cost[kind]), kind])
	var name := bd.name if not bd.name.is_empty() else String(bd.id)
	if parts.is_empty():
		return name
	var line := "%s — %s" % [name, ", ".join(parts)]
	if can_afford:
		return line
	# WHICH resource, not just "you cannot afford it". A player short on stone for a
	# blacksmith needs to know it is the stone, since the fix is a different one.
	var stock := _view.stock_of(Net.local_player_id())
	var short: Array[String] = []
	for kind in ResourceHUD.DISPLAY_ORDER:
		if bd.cost.has(kind) and int(stock.get(kind, 0)) < int(bd.cost[kind]):
			short.append(String(kind))
	if short.is_empty():
		return line
	return "%s (short on %s)" % [line, ", ".join(short)]


## Open or shut the selected gate (PLAN.md 5.8).
##
## SENDS THE TARGET STATE, not "flip it" -- see `ToggleGateCommand`'s header for why
## a toggle is the wrong shape for something that round-trips through a snapshot. The
## state is read from the same facts the button's own label was drawn from, so the
## button and the command can never disagree about which way it is about to go.
func _toggle_selected_gate() -> void:
	var id := _view.selection.primary()
	if id == 0:
		return
	var facts := _view.facts_for(id)
	var locked := bool(facts.get("gate_locked", false))
	Net.submit_command(ToggleGateCommand.new(Net.local_player_id(), id, not locked))
	_toast.show_message("Opening the gate" if locked else "Closing the gate")


## Turn the selected building into what its def upgrades to (PLAN.md 5.8) -- a long
## wall segment into its tier's gate, which is the only upgrade that exists.
##
## The affordability check here is the POLITE half, exactly as `_on_train_requested`'s
## population check is: `UpgradeBuildingCommand.validate()` is what actually refuses,
## and a failed command is dropped silently, so without this the button would simply
## do nothing and say nothing. The price is read through the command's own
## `cost_delta`, so the message cannot quote a figure the server would not charge.
func _upgrade_selected_building() -> void:
	var id := _view.selection.primary()
	if id == 0:
		return
	var from: BuildingDef = GameDataRegistry.building(_view.facts_for(id).get("def_id", &""))
	if from == null or from.upgrades_to == &"":
		return
	var to: BuildingDef = GameDataRegistry.building(from.upgrades_to)
	if to == null:
		return

	var price := UpgradeBuildingCommand.cost_delta(from, to)
	if not PlacementAdvice.can_afford(price, _view.stock_of(Net.local_player_id())):
		_toast.show_message("Not enough resources")
		return
	Net.submit_command(UpgradeBuildingCommand.new(Net.local_player_id(), id))
	_toast.show_message("Building %s" % to.name.to_lower())


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
	# The two parameterised verbs, checked before the match because GDScript's `match`
	# has no prefix arm. Both arrive from the DETAIL grid rather than the action column
	# -- see `SelectionPanel._on_detail_pressed`'s fall-through.
	var id := String(action_id)
	if id.begins_with("stance:"):
		_set_selected_stance(movable, int(id.trim_prefix("stance:")))
		return
	if id.begins_with("formation:"):
		_pick_formation(StringName(id.trim_prefix("formation:")))
		return

	match action_id:
		&"stop":
			# STOP MEANS TWO THINGS AND WHICH ONE DEPENDS ON THE SELECTION (project
			# owner, 2026-08-27: *"resuse stop action button to clear waypoint with
			# building selected"*). With units in hand it halts them, as it always
			# has; with one of your own buildings selected it takes that building's
			# rally point down.
			#
			# **They cannot both fire**, and that is the selection's own doing rather
			# than an ordering here: `movable_selection()` is units only and
			# `waypoint_target()` demands a selection of exactly one building, so at
			# most one of the two is ever non-empty. The `elif` is belt to that brace.
			#
			# It reuses the existing button rather than adding a ninth verb, which is
			# the whole reason it fits: the castle's action row is already at its
			# eight-slot cap (`SelectionActions.MAX_ACTIONS`).
			if not movable.is_empty():
				Net.submit_command(StopCommand.new(Net.local_player_id(), movable))
				_toast.show_message("Holding position")
			elif _view.waypoint_target(Net.local_player_id()) != 0:
				_clear_selected_waypoint()
		&"move":
			_toast.show_message("Tap where to move")
		&"harvest":
			_toast.show_message("Tap a tree or resource to gather")
		&"attack":
			# Same hint-not-mode treatment as Move and Harvest: tapping an enemy
			# already attacks it, so a second targeting mode would be a parallel
			# way to issue an order the map already accepts.
			_toast.show_message("Tap an enemy to attack")
		&"ability":
			_arm_ability()
		&"gate":
			_toggle_selected_gate()
		&"upgrade":
			_upgrade_selected_building()


## Set the whole movable selection's stance (PLAN.md 4.12).
##
## Sent for the WHOLE selection, not for the primary alone: `SetStanceCommand` carries
## many ids because nobody sets a stance one soldier at a time, and the panel offers the
## verb on a group for the same reason.
##
## Members that cannot fight are left in rather than filtered out here. The command
## accepts them, `StanceSystem` never acquires for them, and filtering would mean this
## side re-deriving a rule the sim already owns -- the duplication `Diplomacy`'s header
## is a standing warning about.
func _set_selected_stance(movable: Array[int], stance: int) -> void:
	if movable.is_empty():
		return
	Net.submit_command(SetStanceCommand.new(Net.local_player_id(), movable, stance))
	_toast.show_message("Stance: %s" % SelectionActions.STANCE_LABELS.get(stance, "?"))


## Choose (or clear) the formation this player's move orders use (PLAN.md 4.14).
##
## A TOGGLE, because pressing the ringed one is the only way back to a plain move order.
## Nothing is sent: a formation is a property of the ORDER and rides out on the next
## `MoveCommand`, so this writes one client-side field and re-rings a slot.
##
## IT DOES NOT MOVE ANYBODY. Picking a shape while an army stands around is a statement
## about the next order, not an order itself -- forming up on the spot would be a move
## the player did not ask for, and the units are already where they are.
func _pick_formation(shape: StringName) -> void:
	var next := Formation.NONE if _panel.active_formation == shape else shape
	_panel.active_formation = next
	if next == Formation.NONE:
		_toast.show_message("Formation off")
	else:
		_toast.show_message("%s -- tap where to move" % String(next).capitalize())


## Arm the ability's targeting mode (PLAN.md 4.10). The NEXT world tap uses it.
##
## A MODE, unlike Move, Harvest and Attack, which answer with a hint because tapping the
## world already issues those orders. There is no tap that means "heal that" or "burn
## there" -- both would otherwise read as a move order -- so this is the placement
## gesture's shape rather than the hint's: press, then aim.
##
## Armed for the PRIMARY selection only. An ability costs a cooldown and is aimed, so two
## monks told to heal one soldier is one wasted monk -- `AbilityCommand` carries a single
## unit id for that reason and this is the other half of it.
func _arm_ability() -> void:
	var def := _selected_ability_def()
	if def == null:
		return
	_ability_pending = true
	if def.ability_target == &"friendly":
		_toast.show_message("Tap one of your units to %s" % def.ability_name.to_lower())
	else:
		_toast.show_message("Tap where to %s" % def.ability_name.to_lower())


## Aim the armed ability at what the player just tapped (PLAN.md 4.10).
##
## THE MODE IS DISARMED WHATEVER HAPPENS, including on a tap that turns out to be an
## illegal target. A targeting mode that survives a bad tap is a mode the player cannot
## tell they are still in -- the next tap would then heal somebody instead of moving, and
## nothing on screen would have said so. Getting out of it costs one more tap, which is
## the same bargain a refused placement makes.
##
## `friendly` demands a tapped ENTITY and `ground` demands a TILE, and the two are
## refused rather than substituted: a heal aimed at bare ground and a breath aimed at a
## unit are both the player having missed, and firing something adjacent to what they
## meant would spend the cooldown on it.
func _fire_ability(picked: int, tile: Vector2i) -> void:
	_ability_pending = false
	var def := _selected_ability_def()
	if def == null:
		return
	var unit_id := _view.movable_selection()[0]
	var owner := Net.local_player_id()

	if def.ability_target == &"friendly":
		var facts := _view.facts_for(picked)
		if picked == 0 or facts.is_empty() or int(facts.get("owner_id", 0)) != owner \
				or GameDataRegistry.unit(facts.get("def_id", &"")) == null:
			_toast.show_message("Tap one of your own units")
			return
		Net.submit_command(AbilityCommand.new(owner, unit_id, picked, Vector2i.ZERO))
		_flash.play(ActionFlash.Kind.GATHER, Iso.tile_centre_to_world(facts["tile"]))
		return

	Net.submit_command(AbilityCommand.new(owner, unit_id, 0, tile))
	_flash.play(ActionFlash.Kind.ATTACK, Iso.tile_centre_to_world(tile))


## The def of the single selected unit's ability, or null if the selection is not one
## unit of yours that has one. The gate for both arming and firing, so the two can never
## disagree about what is selected.
func _selected_ability_def() -> UnitDef:
	var movable := _view.movable_selection()
	if movable.size() != 1:
		return null
	var facts := _view.facts_for(movable[0])
	if facts.is_empty():
		return null
	var ud: UnitDef = GameDataRegistry.unit(facts.get("def_id", &""))
	return ud if ud != null and ud.has_ability() else null


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


## Start a technology at the building offering it (PLAN.md 9.3).
##
## THE POLITE HALF IS AFFORDABILITY, which is the same one `_on_train_requested` and
## `_on_age_advance_requested` were both given and for the identical reason: a command
## that fails `validate()` is dropped in silence, so the tile would go dead with
## nothing said. The panel already handles the other two ways this can be refused --
## a researched tech is ringed and a gated one names its prerequisite -- so cost is
## the only refusal a player can walk into blind.
##
## The shortfall is NAMED rather than the rule, following the age badge: "Need 120
## gold" tells you what to go and get where "You cannot afford that" does not.
func _on_research_requested(building_id: int, tech_id: StringName) -> void:
	var t: TechDef = GameDataRegistry.tech(tech_id)
	if t == null:
		return
	var world: SimWorld = Net.host().world if Net.host() != null else null
	var player: SimPlayer = world.player_for(Net.local_player_id()) if world != null else null
	if player != null and not player.can_afford(t.cost):
		_toast.show_message("Need %s to research %s"
				% [_shortfall_text(player, t.cost), t.name])
		return
	Net.submit_command(ResearchCommand.new(Net.local_player_id(), building_id, tech_id))
	_toast.show_message("Researching %s" % t.name)


func _on_cancel_requested(building_id: int, index: int) -> void:
	Net.submit_command(CancelProductionCommand.new(Net.local_player_id(), building_id, index))


## Take the selected building's rally point down (project owner, 2026-08-27), which is
## the gesture BUGS.md recorded as the one thing 4.8b was missing: setting a waypoint
## moved it, and nothing took it away.
##
## Reuses the STOP button rather than adding a verb, and reusing it is what made it
## affordable — the castle's action row already sits on its eighth and last slot. It
## also reads correctly: "stop" on a building is exactly "stop sending things over
## there", which is the same word doing the same work it does on a unit.
##
## Sends the sentinel through the ordinary command, so the clear is server-authoritative
## and replayable like any other order. `SetWaypointCommand.validate` accepts
## `NO_WAYPOINT` unconditionally, so this can never be refused for a building the player
## owns.
func _clear_selected_waypoint() -> void:
	var building := _view.waypoint_target(Net.local_player_id())
	if building == 0:
		return
	Net.submit_command(SetWaypointCommand.new(Net.local_player_id(), building,
			SimBuilding.NO_WAYPOINT))
	_toast.show_message("Rally point cleared")


## Turn a garrison out (PLAN.md 4.8). `index` is a slot, or `UngarrisonCommand.ALL`
## for the lot -- passed straight through, because the panel and the command agree on
## what -1 means and nothing here needs to interpret it.
##
## No toast on refusal, matching `_on_cancel_requested`: the only way this is refused
## is an empty building or a stale index, and both are already invisible in the panel
## the player is looking at. A unit that cannot be let out because the tower has been
## walled in DOES deserve one, and does not get it -- the sim refuses per unit inside
## `apply()` and the command has no way to report back. Logged as the known gap it is.
func _on_ungarrison_requested(building_id: int, index: int) -> void:
	Net.submit_command(UngarrisonCommand.new(Net.local_player_id(), building_id, index))


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
## THE POLITE HALF OF THE AGE LADDER (project owner, 2026-08-28: *"age up, does not
## tell you why its failing when clicked"*). `AdvanceAgeCommand.validate()` is the
## enforcing half and it refuses SILENTLY -- a command that fails validation is simply
## dropped -- so before this the badge went dead with no explanation the moment you
## were short of resources. Exactly the failure mode `_on_train_requested` was given
## this same treatment for, and the same reason a full town centre and a broken button
## look identical.
##
## Asks the host the same question the server will, through `Net.host()` -- the
## documented solo-only exception `_preview_placement` and `_on_train_requested`
## already use. A second copy of the affordability rule here would disagree with the
## server the first time either changed. A remote client has no host to ask, so it
## submits and takes the silence; sending the refusal back is a multiplayer job.
func _on_age_advance_requested(next_age: int) -> void:
	var world: SimWorld = Net.host().world if Net.host() != null else null
	var player: SimPlayer = world.player_for(Net.local_player_id()) if world != null else null
	var def: AgeDef = GameDataRegistry.age(next_age)
	if player != null and def != null and not player.can_afford(def.cost):
		# NAMES WHAT IS SHORT, not just that something is. "Not enough resources" leaves
		# the player counting five stockpiles by eye; the population toast beside this
		# one sets the standard by naming the fix rather than the rule.
		_toast.show_message("Need %s to reach the %s" % [
				_shortfall_text(player, def.cost), def.name if def.name != "" else "next age"])
		return
	Net.submit_command(AdvanceAgeCommand.new(Net.local_player_id()))


## The two silent presses `AgeBadge` swallows on its own. Both are drawn on the badge
## already -- "MAX" and "..." under the numeral -- and neither reads as an answer to a
## press, which is what the owner's report was about.
func _on_age_advance_unavailable(reason: StringName) -> void:
	match reason:
		&"advancing":
			_toast.show_message("Already advancing -- the ring shows how far")
		&"maxed":
			_toast.show_message("This is the last age")


## What is MISSING from `cost`, as "120 food, 30 gold" -- never what it costs. Ordered
## by `ResourceHUD.DISPLAY_ORDER` so the list reads in the same order as the counters
## the player is about to look at.
func _shortfall_text(player: SimPlayer, cost: Dictionary) -> String:
	var parts: Array[String] = []
	for kind in ResourceHUD.DISPLAY_ORDER:
		var short := int(cost.get(kind, 0)) - int(player.stock.get(kind, 0))
		if short > 0:
			# A resource kind is bare in the data -- `&"wood"`, not `&"res.wood"`, which
			# is the RESOURCE NODE namespace. No prefix to strip.
			parts.append("%d %s" % [short, kind])
	# Belt to the caller's brace: this is only reached when `can_afford` said no, so
	# something is always short -- but a cost naming a kind DISPLAY_ORDER does not
	# would otherwise produce "Need  to reach...".
	return " and ".join(parts) if not parts.is_empty() else "more resources"


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
		# ONE THING AT A TIME, OUTERMOST FIRST. Escape backs out of build mode
		# before anything else -- the Cancel Build button that used to do this went
		# away with the dev row, and leaving a menu as the only way out of a
		# half-started placement would be worse than no way at all. Then a corner
		# page, if one is open, because closing the thing covering the screen is
		# what Escape means to whoever is looking at it. Only then the settings menu.
		if _placing_def_id != &"":
			_exit_placement()
		elif _chat.is_open() or _tech_tree.is_open() or _market.is_open():
			_close_pages()
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
				_view.age_of(owner_id), int(_view.skin_for(owner_id).get("colour", -1)),
				_view.researched_of(owner_id))
	_refresh_waypoint_flag()


## Show the selected building's rally point, or nothing.
##
## Called from here rather than from a `_process`, which gets it both cases for free:
## `_on_snapshot` calls `_refresh_panel` every tick, so a rally point somebody's command
## just set appears as soon as the sim reports it, and a selection change redraws
## immediately because that also comes through here.
##
## ONLY WHILE ITS BUILDING IS SELECTED, which is a deliberate limit and not laziness. A
## player with eight rally points set would otherwise have eight flags standing in their
## base permanently, and the one thing a marker must not become is scenery. The cost is
## that you cannot see them all at once; the mitigation is that you cannot set one
## without the building being selected either, so the flag is always visible exactly when
## you are working on it.
##
## `waypoint_target` gates it, so this can never draw a flag on somebody ELSE'S building
## — which matters because the server blanks an enemy's rally point anyway
## (`SnapshotSystem._without_the_rally_point`) and two independent guards on an
## information leak is the right number.
func _refresh_waypoint_flag() -> void:
	if _waypoint_flag == null:
		return
	var building := _view.waypoint_target(Net.local_player_id())
	if building == 0:
		_waypoint_flag.visible = false
		return
	var facts := _view.facts_for(building)
	var tile: Vector2i = facts.get("waypoint", SimBuilding.NO_WAYPOINT)
	if tile == SimBuilding.NO_WAYPOINT:
		_waypoint_flag.visible = false
		return
	# Index -> Color through the registry, the same two-step `_refresh_panel` above makes:
	# `SimPlayer.colour` is an INDEX into colours.json (its own note says why the palette
	# is data and not a Color), and `GameDataRegistry.colour` wraps rather than failing.
	# The INDEX goes through as well as the Color, since the flag became baked art on
	# 2026-08-28: the diamond wants a Color and the sprite wants the index that picks
	# one of the eight bakes, and only the index can produce both.
	var index := int(_view.skin_for(Net.local_player_id()).get("colour", -1))
	_waypoint_flag.show_on(tile, GameDataRegistry.colour(index), index)
