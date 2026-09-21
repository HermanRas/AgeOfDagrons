extends Node

## WHAT THE BUNCHING ACTUALLY LOOKS LIKE — a castle foundation, a dozen villagers, and a
## photograph. The eye half of `preview_build_stations`, which measures the same thing
## headlessly and cannot show it.
##
##     godot --path game res://dev_preview/preview_build_crowd.tscn
##
## ## ⚠️ IT EXISTS BECAUSE THE REPORT WAS A PICTURE
##
## The owner's 2026-09-21 report is a screenshot of villagers piled on one spot with the
## castle beside them. The numbers in `preview_build_stations` are the honest measure —
## twelve builders, three not touching the footprint — but *"they are in a heap"* is a
## judgement about a picture, and the fix has to be checked the way the bug was found.
##
## It shoots twice: once as the order goes out, and once after they have arrived. The
## second is the one to look at; the first is there so a reader can tell "spread out" from
## "never moved".
##
## 📝 It drives the REAL `Game.tscn`, like `preview_match` and `preview_destroy_confirm`,
## so what is photographed is the game and not a diagram of it.

const SHOT_DIR := "user://"
const SETTLE_FRAMES := 120
const STEP_FRAMES := 40
const ARRIVAL_FRAMES := 260
const CASTLE := &"building.castle"
## Twelve, because that is roughly the crowd in the owner's report and because a 7x7
## castle offers 32 stations -- enough that every builder gets its own and the picture
## shows a ring rather than a queue.
const CROWD := 12

var _game: Node
var _frames := 0
var _step := 0
var _castle_id := 0
var _builders: Array[int] = []
var _problems: Array[String] = []


func _ready() -> void:
	print("=== build crowd ===\n")
	_game = load("res://scenes/game/Game.tscn").instantiate()
	add_child(_game)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < SETTLE_FRAMES + _step * STEP_FRAMES:
		return
	_advance()


func _advance() -> void:
	match _step:
		0:
			_stand_a_castle()
			_send_everybody()
		1:
			_shoot("build_crowd_ordered")
			_frames -= ARRIVAL_FRAMES          # let them walk
		2:
			_look_at_them()
			_shoot("build_crowd_arrived")
			_finish()
	_step += 1


func _world() -> SimWorld:
	var host := Net.host()
	return host.world if host != null else null


## A castle foundation on clear ground near home, and the camera put on it.
func _stand_a_castle() -> void:
	var w := _world()
	if w == null:
		_fail("no host world -- the match never started")
		return
	var me := Net.local_player_id()
	var origin := _clear_ground(w, Vector2i(7, 7))
	if origin.x < 0:
		_fail("nowhere to stand a castle")
		return
	var castle := w.spawn_building(CASTLE, me, origin, SimBuilding.Phase.FOUNDATION, true)
	if castle == null:
		_fail("could not place the castle foundation")
		return
	_castle_id = castle.id
	print("  castle foundation at %s, footprint %s" % [origin, castle.footprint_rect().size])

	# THE CAMERA, or the photograph is of whatever the match happened to be looking at.
	var centre := castle.footprint_rect().position + castle.footprint_rect().size / 2
	if _game.has_method("_centre_camera_on"):
		_game._centre_camera_on(centre)
	elif _game._camera != null:
		_game._camera.position = Iso.tile_centre_to_world(centre)


## Every villager this player owns, sent to build it. Through the REAL command, so what is
## exercised is the path a player's tap takes.
##
## ⚠️ **THE CROWD IS TOPPED UP TO `CROWD` FIRST, AND WITHOUT IT THE PICTURE PROVES NOTHING.**
## A match opens with five villagers, and five spread along one edge look much the same
## whether or not this fix exists — the report was about a dozen of them on a castle. Spawned
## straight into the world rather than trained, so the preview does not spend two minutes and
## the population cap on scenery.
func _send_everybody() -> void:
	var w := _world()
	if w == null or _castle_id == 0:
		return
	var me := Net.local_player_id()
	_top_up_villagers(w, me)
	var ids: Array[int] = []
	for id in w.entities:
		var e = w.entities[id]
		if e is SimUnit and e.alive and e.owner_id == me \
				and e.def_id == &"unit.villager":
			ids.append(int(id))
	ids.sort()
	_builders = ids
	if ids.is_empty():
		_fail("this player owns no villagers")
		return
	print("  sending %d villagers" % ids.size())
	Net.submit_command(BuildCommand.new(me, ids, _castle_id))


## Stand extra villagers together, off to one side, which is how the reported crowd arrives:
## a box-select of idle workers and one tap on the foundation.
func _top_up_villagers(w: SimWorld, me: int) -> void:
	var have := 0
	for id in w.entities:
		var e = w.entities[id]
		if e is SimUnit and e.alive and e.owner_id == me and e.def_id == &"unit.villager":
			have += 1
	if have >= CROWD:
		return
	var from := _home_tile(w)
	var placed := 0
	for ring in range(2, 12):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if have + placed >= CROWD:
					return
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var t := from + Vector2i(dx, dy)
				if not w.map.is_passable(t, SimMap.Domain.LAND):
					continue
				if w.spawn_unit(&"unit.villager", me, t) != null:
					placed += 1


## The same two numbers `preview_build_stations` asserts, printed beside the picture so the
## screenshot can be read rather than admired.
func _look_at_them() -> void:
	var w := _world()
	var castle := w.get_entity(_castle_id) as SimBuilding if w != null else null
	if castle == null:
		_fail("the castle is gone")
		return
	var rect := castle.footprint_rect()
	var touching := 0
	var seen := {}
	var stacked := 0
	for id in _builders:
		var u := w.get_entity(id) as SimUnit
		if u == null or not u.alive:
			continue
		var t := u.tile()
		if rect.grow(1).has_point(t) and not rect.has_point(t):
			touching += 1
		if seen.has(t):
			stacked += 1
		seen[t] = true

	print("  touching  %d of %d" % [touching, _builders.size()])
	print("  stacked   %d sharing a tile" % stacked)
	if touching < _builders.size():
		_fail("%d builder(s) are not touching the castle"
				% [_builders.size() - touching])
	if stacked > 0:
		_fail("%d builder(s) are standing on somebody else" % stacked)


## `preview_garrison`'s helper, same shape: clear ground a few rings out from home.
func _clear_ground(w: SimWorld, span: Vector2i) -> Vector2i:
	var anchor := _home_tile(w)
	for ring in range(5, 24):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var origin := anchor + Vector2i(dx, dy)
				if origin.x < 2 or origin.y < 2:
					continue
				if origin.x + span.x >= w.map.size.x - 2 \
						or origin.y + span.y >= w.map.size.y - 2:
					continue
				if w.map.can_place_building(SimMap.footprint_rect(origin, span)):
					return origin
	return Vector2i(-1, -1)


func _home_tile(w: SimWorld) -> Vector2i:
	var me := Net.local_player_id()
	for id in w.entities:
		var e = w.entities[id]
		if e is SimBuilding and e.alive and e.owner_id == me:
			return (e as SimBuilding).origin_tile()
	return w.map.size / 2


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("  wrote ", ProjectSettings.globalize_path(path))


func _fail(message: String) -> void:
	_problems.append(message)


func _finish() -> void:
	print("")
	if _problems.is_empty():
		print("OK -- they spread around the castle.")
		get_tree().quit(0)
		return
	print("%d PROBLEM(S):" % _problems.size())
	for p in _problems:
		print("  - %s" % p)
	get_tree().quit(1)
