## Dev check for the siege pack/unpack machine (PLAN.md 4.13): watch one engine change
## state in the real game and photograph both halves.
##
## WHY A PICTURE IS THE POINT HERE, and it is the reason 4.13 sat open from 2026-08-22
## to 2026-08-28. Every siege atlas staged was the UNPACKED pose, so the machine could
## have been written at any time and there would have been nothing to see: a state
## machine driving two ids that resolve to the same art proves the transition happened
## without proving it happened the right way round. `test_siege` asserts the timings,
## the exclusivity and the wire; what it cannot assert is that the packed id draws a
## wagon and the deployed one draws an engine.
##
## It also catches the cheapest possible mistake in this feature, which is a `_packed`
## id that resolves to the loud magenta unknown because it was never declared -- a
## thing that costs nothing to check with eyes and cannot be checked without them.
##
## Usage:
##   Godot --path game res://dev_preview/preview_siege.tscn
##       -- writes user://siege_*.png and quits.
##   ... -- --interactive     -- leaves it running to order the engine about by hand.
extends Node

const SHOT_DIR := "user://"
const SETTLE_FRAMES := 30
const STEP_FRAMES := 20

## The trebuchet, because it is the extreme case of every number in the feature: the
## slowest packed speed (40), the longest transition (80 ticks) and the longest reach
## (12), so a picture of it deploying is a picture of the design decision.
const ENGINE := &"unit.trebuchet"

## How long the lane is. Short enough that the walk is a few seconds at the trebuchet's
## packed 40, long enough that it starts well outside its own range of 12.
const LANE := 22

## Frames one step may spend waiting before it gives up and says so. Generous: the walk
## alone is about 60 ticks at SimClock's 10 a second.
const WAIT_LIMIT_FRAMES := 2400

var _game: Node = null
var _frames := 0
var _step := 0
var _waited := 0
var _interactive := false

var _engine_id := 0
var _home := Vector2i.ZERO
var _away := Vector2i.ZERO
var _target_id := 0


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
	# AIMING AND SHOOTING ARE ALWAYS SEPARATE STEPS, and this is the trap this preview
	# fell into on its first run: `get_viewport().get_texture()` hands back the frame
	# that has already been drawn, so a camera move and a screenshot in the same step
	# photograph where the camera USED to be. Four pictures of the wrong place, with a
	# printout beside them saying everything was fine.
	match _step:
		0:
			_pick_ground()
			_spawn()
		1:
			_look_at(_home)
		2:
			# PACKED AND STANDING, which is how it leaves the workshop. If this shows
			# the assembled engine rather than the wagon, the two ids are the wrong way
			# round -- and nothing in the sim could tell.
			_report("just trained")
			_shoot("siege_packed")
		3:
			_order_attack()
		4:
			# ROLLING. The packed actor is the one carrying the walk clip, so this is
			# the only state either actor can show movement in at all.
			if not _waiting(func(): return _engine_tile() != _home):
				return
			_look_at(_engine_tile())
		5:
			_report("on the road")
			_shoot("siege_travelling")
		6:
			if not _waiting(_is_deployed):
				return
			_look_at(_engine_tile())
		7:
			_report("in range")
			_shoot("siege_deployed")
		8:
			if not _waiting(func(): return _house_hp() < _house_max()):
				return
			_look_at(_engine_tile())
		9:
			_report("shooting")
			_shoot("siege_firing")
		_:
			get_tree().quit()
	_step += 1
	_waited = 0


## Whether the thing this step is waiting for has happened, letting the game run at its
## own tick rate until it does. The caller RETURNS on false, which is what holds the
## step -- `_step` is only advanced past the bottom of `_process`.
##
## RUN, NOT STEPPED. The first version drove `world.step()` in a tight loop to skip the
## walk, which advanced the HOST and left the client's snapshot behind -- so the sim was
## in one place and the thing being photographed was somewhere else entirely. The walk
## is what is being looked at; it has to happen at the speed a player sees it.
func _waiting(pred: Callable) -> bool:
	if pred.call():
		return true
	_waited += 1
	if _waited > WAIT_LIMIT_FRAMES:
		push_warning("preview_siege: gave up waiting at step %d" % _step)
		return true
	return false


# ── setting up ──────────────────────────────────────────────────────────────

## A clear east-west lane with the engine at one end and something to shoot at the
## other. Found rather than assumed, the same lesson `preview_walls._pick_ground`
## records: a fixture that quietly lands on occupied ground photographs as something
## subtly wrong and says nothing about why.
func _pick_ground() -> void:
	var world: SimWorld = Net.host().world
	for y in range(4, world.map.size.y - 12):
		for x in range(4, world.map.size.x - LANE - 6):
			if world.map.can_place_building(
					SimMap.footprint_rect(Vector2i(x, y), Vector2i(LANE, 8))):
				_home = Vector2i(x + 1, y + 2)
				_away = Vector2i(x + LANE - 5, y + 2)
				return
	push_warning("preview_siege: no clear %dx8 lane" % LANE)
	_home = Vector2i(8, 8)
	_away = Vector2i(8 + LANE - 6, 8)


func _spawn() -> void:
	var world: SimWorld = Net.host().world
	var me := Net.local_player_id()
	_engine_id = world.spawn_unit(ENGINE, me, _home).id
	# An enemy house at the far end. A BUILDING rather than a unit, because a siege
	# engine's whole purpose is out-ranging one and because it will stand still to be
	# photographed being hit.
	var enemy := 2 if me != 2 else 1
	_target_id = world.spawn_building(&"building.house", enemy, _away,
			SimBuilding.Phase.COMPLETE, true).id


func _order_attack() -> void:
	var world: SimWorld = Net.host().world
	world.queue_command(AttackCommand.new(Net.local_player_id(),
			[_engine_id] as Array[int], _target_id))


# ── running it forward ──────────────────────────────────────────────────────

# ── looking ─────────────────────────────────────────────────────────────────

## Set up and ready to shoot. A named function rather than a lambda because a lambda
## body cannot be wrapped across lines in GDScript, and this is two conditions.
func _is_deployed() -> bool:
	var u := _engine()
	return u != null and not u.packed and u.pack_ticks_left == 0


func _house_hp() -> int:
	var h := Net.host().world.get_entity(_target_id)
	return h.hp if h != null else 0


func _house_max() -> int:
	var h := Net.host().world.get_entity(_target_id)
	return h.max_hp if h != null else 0



func _engine() -> SimUnit:
	return Net.host().world.get_entity(_engine_id) as SimUnit


func _engine_tile() -> Vector2i:
	var u := _engine()
	return u.tile() if u != null else _home


func _look_at(tile: Vector2i) -> void:
	_game._camera.centre_on(Iso.tile_centre_to_world(tile))
	_game._camera.zoom = Vector2(CameraRig.MAX_ZOOM, CameraRig.MAX_ZOOM)


## The three facts that say which picture this is, printed beside it so a screenshot
## that looks wrong can be read against what the sim believed at the time.
func _report(label: String) -> void:
	var u := _engine()
	if u == null:
		push_warning("preview_siege: the engine is gone")
		return
	var house := Net.host().world.get_entity(_target_id)
	print("  %-12s packed %s, %d ticks left, speed %d, at %s, house %d hp"
			% [label, u.packed, u.pack_ticks_left, u.speed, u.tile(),
			house.hp if house != null else -1])
	# The art the client will actually draw for it, which is the whole question this
	# preview exists to answer and the one thing the printout can settle without eyes.
	print("               draws %s" % GameDataRegistry.visual_for(ENGINE, -1, -1, u.packed))


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
