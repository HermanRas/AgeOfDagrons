## Dev check for walls (PLAN.md 5.8): drag them in the real game and photograph them.
##
## THE THING NO TEST CAN JUDGE IS WHICH WAY THE ART FACES. `test_wall_plan` asserts
## that the two axes get different facings, and it cannot assert that either of them
## is the RIGHT one -- a wall lying across its own footprint has the same footprint,
## the same origin and the same hash as one lying along it. The art side has already
## been caught by a building baked 180 degrees out (`yaw_offset_deg`), so both axes
## get a screenshot and somebody looks.
##
## What else it covers, in the same run because a wall is cheap to place: that a drag
## lays several segments and mixes their lengths, that a run refuses the ground it
## cannot have, and that a gate is a hole in a wall until it is locked -- which is the
## only pathing change in the game a player can make on purpose.
##
## Usage:
##   Godot --path game res://dev_preview/preview_walls.tscn
##       -- writes user://wall_*.png and quits.
##   ... -- --interactive     -- leaves it running to drag walls by hand instead.
extends Node

const SHOT_DIR := "user://"
const SETTLE_FRAMES := 30
const STEP_FRAMES := 14

## The tier to drag. Wood is age 2, which is one debug age-jump away, and its
## palisade reads unmistakably as a wall in a screenshot.
const TIER := &"building.wall_wood_short"
const GATE := &"building.wall_wood_gate"

var _game: Node = null
var _frames := 0
var _step := 0
var _interactive := false

## Where the east-west and north-south runs went, so the reports can find them again.
var _across := Vector2i.ZERO
var _down := Vector2i.ZERO
var _gate_id := 0


func _ready() -> void:
	_interactive = OS.get_cmdline_user_args().has("--interactive")
	_game = load("res://scenes/game/Game.tscn").instantiate()
	add_child(_game)


func _process(_delta: float) -> void:
	if _interactive:
		return
	_frames += 1
	if _frames < SETTLE_FRAMES + _step * STEP_FRAMES:
		return
	match _step:
		0:
			# Age 2 and a full bank, so nothing here is refused for a reason that is
			# not what is being looked at.
			_jump_age(2)
			_fill_the_bank()
		1:
			# THE GHOST FIRST, held open, because the ghost is the half a player
			# steers by -- and it is drawn from `WallPlan`, the same function the
			# server lays the wall from. A ghost that disagreed with the wall would
			# show up here as two different pictures.
			_start_a_drag(_pick_ground(24), Vector2i(23, 0))
		2:
			_report_ghost()
			_shoot("wall_ghost")
		3:
			_finish_the_drag()
		4:
			# FINISHED, NOT LEFT AS FOUNDATIONS. A wall foundation is 0 A.D.'s flat pad
			# with corner posts, which at nine tiles reads as a row of disconnected
			# stubs -- the first run of this preview photographed exactly that and it
			# was impossible to tell a correctly-oriented wall from a broken one. What
			# a player looks at is the finished wall, so that is what gets shot.
			_finish_the_walls()
			_zoom_to(_across, 24, 0)
		5:
			_report_run("east-west", _across, 0)
			_shoot("wall_across")
		6:
			# THE OTHER AXIS, which is the whole reason this preview exists.
			_drag_wall(_pick_ground(24), Vector2i(0, 23))
		7:
			_finish_the_walls()
			_zoom_to(_down, 0, 24)
		8:
			_report_run("north-south", _down, 6)
			_shoot("wall_down")
		9:
			# A run into ground it cannot have. The segments that fit are placed and
			# the rest are skipped, so the picture is a wall with a hole in it.
			_drag_across_the_town_centre()
		10:
			_finish_the_walls()
			_report_partial()
			_shoot("wall_blocked")
		11:
			# A GATE, and the pathing question. Placed as an ordinary building (a gate
			# is not dragged) and photographed open, then shut.
			_place_a_gate()
		12:
			# Finished a STEP EARLIER than the press, and that gap is the point: the
			# panel's Open/Close button is drawn from SNAPSHOT facts, so a gate
			# completed and selected in the same frame still reads as a foundation and
			# offers no button at all. Found exactly that way.
			_finish_the_walls()
		13:
			_select_the_gate()
			_report_gate("open")
			_shoot("wall_gate_open")
		14:
			_lock_the_gate()
		15:
			_report_gate("locked")
			_shoot("wall_gate_locked")
		_:
			get_tree().quit()
			return
	_step += 1


# ── setting the scene ───────────────────────────────────────────────────────

func _jump_age(age: int) -> void:
	Net.submit_command(DebugSetAgeCommand.new(Net.local_player_id(), age))


func _fill_the_bank() -> void:
	var world: SimWorld = Net.host().world
	var p := world.player_for(Net.local_player_id())
	for kind in [&"wood", &"stone", &"food", &"gold"]:
		p.stock[kind] = 5000


## An origin with `tiles` x DEPTH of clear ground, found rather than assumed -- the
## same lesson `test_walls._clear_run` records, and for the same reason: a run that
## quietly lands on occupied ground photographs as a shorter wall and says nothing.
func _pick_ground(tiles: int) -> Vector2i:
	var world: SimWorld = Net.host().world
	for y in range(4, world.map.size.y - WallPlan.DEPTH - 2):
		for x in range(4, world.map.size.x - tiles - 2):
			var origin := Vector2i(x, y)
			if world.map.can_place_building(
					SimMap.footprint_rect(origin, Vector2i(tiles, WallPlan.DEPTH))) \
					and world.map.can_place_building(
					SimMap.footprint_rect(origin, Vector2i(WallPlan.DEPTH, tiles))):
				return origin
	push_warning("preview_walls: no clear %d-tile ground" % tiles)
	return Vector2i(8, 8)


## Where a tile is on screen, so a drag can be driven through the real placement
## handlers rather than by calling the command.
func _screen_of(tile: Vector2i) -> Vector2:
	var view: GameView = _game._view
	var world_pos := Iso.tile_to_world_f(Vector2(tile) + Vector2(0.5, 0.5))
	return view.get_global_transform_with_canvas() * world_pos


## Raise every wall foundation to COMPLETE at once.
##
## Reached into the world directly rather than by sending villagers, because a wall
## takes 120-360 ticks a segment to build and what is being photographed is the
## finished art, not `BuildSystem` -- which steps 16-17 of `preview_match` already
## prove end to end.
func _finish_the_walls() -> void:
	var world: SimWorld = Net.host().world
	for e in world.entities.values():
		if not (e is SimBuilding) or not String(e.def_id).begins_with("building.wall_"):
			continue
		var b := e as SimBuilding
		if b.is_complete():
			continue
		b.phase = SimBuilding.Phase.COMPLETE
		b.build_progress = b.build_total
		b.hp = b.max_hp


## Frame a run: centre on its middle and zoom in far enough to judge whether the art
## runs ALONG the footprint or across it, which is the whole question.
func _zoom_to(origin: Vector2i, across: int, down: int) -> void:
	_game._camera.centre_on(Iso.tile_centre_to_world(
			origin + Vector2i(across / 2, down / 2)))
	_game._camera.zoom = Vector2(CameraRig.MAX_ZOOM, CameraRig.MAX_ZOOM)


# ── dragging ────────────────────────────────────────────────────────────────

## Enter the tier's placement mode, put a finger down at `origin` and drag it
## `extent` tiles away -- WITHOUT releasing. Leaves the ghost showing.
##
## Through `_on_placement_pressed`/`_drag`, the handlers `InputRouter` calls, because
## what is in doubt is the whole gesture: a wall drag reuses the one-finger gesture
## that MOVES an ordinary building's ghost, and the branch between the two is exactly
## the thing that could be wrong.
func _start_a_drag(origin: Vector2i, extent: Vector2i) -> void:
	_across = origin
	_game._camera.centre_on(Iso.tile_centre_to_world(origin + extent / 2))
	_game._enter_placement(TIER)
	_game._on_placement_pressed(_screen_of(origin))
	_game._on_placement_drag(_screen_of(origin + extent))


func _finish_the_drag() -> void:
	_game._on_placement_released(_screen_of(_across + Vector2i(23, 0)))


## Press, drag and release in one step, for the runs whose ghost is not the subject.
func _drag_wall(origin: Vector2i, extent: Vector2i) -> void:
	_down = origin
	_game._camera.centre_on(Iso.tile_centre_to_world(origin + extent / 2))
	_game._enter_placement(TIER)
	_game._on_placement_pressed(_screen_of(origin))
	_game._on_placement_drag(_screen_of(origin + extent))
	_game._on_placement_released(_screen_of(origin + extent))


## Straight through the player's own town centre, which cannot be built over.
func _drag_across_the_town_centre() -> void:
	var view: GameView = _game._view
	var centre = view.owned_entity_position(Net.local_player_id(), &"building.town_center")
	if centre == null:
		push_warning("preview_walls: no town centre to drag across")
		return
	var tile := Iso.world_to_tile(centre as Vector2)
	_down = tile - Vector2i(15, 0)
	_game._camera.centre_on(centre as Vector2)
	_game._enter_placement(TIER)
	_game._on_placement_pressed(_screen_of(_down))
	_game._on_placement_drag(_screen_of(tile + Vector2i(15, 0)))
	_game._on_placement_released(_screen_of(tile + Vector2i(15, 0)))


# ── gates ───────────────────────────────────────────────────────────────────

## A gate is placed one at a time like an ordinary building, so this goes through
## `_enter_placement` and a single tap rather than a drag.
func _place_a_gate() -> void:
	var origin := _pick_ground(12)
	_game._camera.centre_on(Iso.tile_centre_to_world(origin + Vector2i(4, 1)))
	_game._enter_placement(GATE)
	var at := _screen_of(origin)
	_game._on_placement_pressed(at)
	_game._on_placement_released(at)


## Find the gate and select it, so its panel is up and its Open/Close button exists.
func _select_the_gate() -> void:
	var world: SimWorld = Net.host().world
	var ids := world.entities.keys()
	ids.sort()
	for id in ids:
		var e = world.entities[id]
		if e is SimBuilding and e.is_gate and e.owner_id == Net.local_player_id():
			_gate_id = int(id)
			break
	if _gate_id == 0:
		push_warning("preview_walls: no gate was placed")
		return
	var gate := world.get_entity(_gate_id) as SimBuilding
	_zoom_to(gate.origin_tile(), gate.footprint.x, gate.footprint.y)
	_game._view.select([_gate_id] as Array[int])
	_game._refresh_panel()


## Through the panel's own action, not by submitting the command: the button's label
## flips between Open and Close off the snapshot, and a preview that called the
## handler would pass with the button unwired.
func _lock_the_gate() -> void:
	var panel: SelectionPanel = _game._panel
	for slot in panel._action_slots:
		if slot.visible and slot.action != null and slot.action.id == &"gate":
			print("  gate: pressing '%s'" % slot.action.label)
			panel._on_action_pressed(slot.action)
			return
	push_warning("preview_walls: no gate action on the panel")


# ── reports ─────────────────────────────────────────────────────────────────

func _report_ghost() -> void:
	var ghost: PlacementGhost = _game._ghost
	print("  ghost: %d boxes, %d legal, visible %s, readout '%s'"
			% [ghost.box_count(), ghost.valid_count(), ghost.visible,
			_game._wall_readout.text])
	if ghost.box_count() < 2:
		push_warning("preview_walls: a 24-tile drag drew %d box(es)" % ghost.box_count())
	if not _game._wall_readout.visible:
		push_warning("preview_walls: no cost readout under the drag")


## What one run came out as. SCOPED TO ITS OWN FACING, because by the time the second
## run is photographed the first one is still standing -- the first version of this
## counted every wall on the map and reported "one run came out with 2 facings", which
## was a bug in the report and not in the wall.
func _report_run(label: String, origin: Vector2i, facing: int) -> void:
	var world: SimWorld = Net.host().world
	var pieces: Array[String] = []
	var lengths := {}
	var ids := world.entities.keys()
	ids.sort()
	for id in ids:
		var e = world.entities[id]
		if not (e is SimBuilding) or not String(e.def_id).begins_with("building.wall_"):
			continue
		if e.facing != facing:
			continue
		pieces.append("%s@%s%s" % [String(e.def_id).trim_prefix("building.wall_wood_"),
				e.origin_tile(), e.footprint])
		lengths[maxi(e.footprint.x, e.footprint.y)] = true
	print("  %s from %s (facing %d): %d pieces %s"
			% [label, origin, facing, pieces.size(), pieces])
	if pieces.is_empty():
		push_warning("preview_walls: the %s drag placed nothing" % label)
	# MIXED LENGTHS ARE THE POINT of a 24-tile run: it is a long, a long and a medium.
	# A run of nothing but shorts would mean the greedy fill is not filling.
	if pieces.size() > 1 and lengths.size() < 2:
		push_warning("preview_walls: the %s run used only one length %s"
				% [label, lengths.keys()])


func _report_partial() -> void:
	var world: SimWorld = Net.host().world
	var walls := 0
	for e in world.entities.values():
		if e is SimBuilding and String(e.def_id).begins_with("building.wall_"):
			walls += 1
	print("  blocked run: %d wall pieces standing in total" % walls)


func _report_gate(state: String) -> void:
	var world: SimWorld = Net.host().world
	if _gate_id == 0:
		push_warning("preview_walls: no gate")
		return
	var gate := world.get_entity(_gate_id) as SimBuilding
	if gate == null:
		push_warning("preview_walls: the gate is gone")
		return
	var doorway := gate.origin_tile() + Vector2i(gate.footprint.x / 2, 0)
	print("  gate %s: locked %s, phase %d, doorway %s passable %s"
			% [state, gate.gate_locked, gate.phase, doorway,
			world.map.is_passable(doorway)])
	# THE ASSERTION THAT MATTERS, and it is about the movement grid rather than the
	# picture: an open gate has to be walkable and a locked one must not be.
	if gate.gate_locked and world.map.is_passable(doorway):
		push_warning("preview_walls: a locked gate is still walkable")
	if not gate.gate_locked and gate.is_complete() \
			and not world.map.is_passable(doorway):
		push_warning("preview_walls: an open gate is not walkable")


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
