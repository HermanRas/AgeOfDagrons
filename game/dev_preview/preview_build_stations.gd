extends Node

## WHERE DO BUILDERS ACTUALLY STAND when several are sent to raise one building?
## Owner, playtest 2026-09-21: *"look at the villagers bunching up on one spot, trying
## to build the castle we need more spots where the villagers can construct it."*
## **THE EXIT CODE IS THE ANSWER** -- headless, no screenshots, no view.
##
##     godot --headless --path game res://dev_preview/preview_build_stations.tscn
##
## ## WHAT IT MEASURES, AND WHY THE OBVIOUS NUMBER IS THE WRONG ONE
##
## The obvious measure is "do they overlap", and `SeparationSystem` makes that look fine:
## it shoves co-located units apart every tick, so a pile always resolves into a blob of
## *distinct* tiles. Counting distinct tiles would therefore report a crowd as healthy.
##
## So this measures the two things a player is actually complaining about:
##
##   1. **SPREAD** -- the bounding box of where the builders ended up, against the
##      building's own footprint. Eight villagers on a 10x10 castle occupying a 3x3 patch
##      at one corner is the reported bug, whatever their individual tiles are.
##   2. **WORKING** -- how many are `_adjacent_to_rect` and therefore actually adding
##      progress. ⛔ **This is the half that is not cosmetic.** `BuildSystem` only counts a
##      villager touching the footprint, so a builder shoved out of the crowd by
##      separation is a villager the player paid for and is not getting.
##
## It prints both for a range of crowd sizes against a real castle.

const _MAX_TICKS := 600

var _problems: Array[String] = []


func _ready() -> void:
	print("=== build stations ===\n")
	for crowd in [2, 4, 8, 12]:
		_measure(crowd)
	_finish()


func _measure(crowd: int) -> void:
	var w := SimWorld.new()
	w.setup(MatchConfig.debug_single_player())

	# A CASTLE, because that is what the report is about and because it is the biggest
	# footprint in the roster -- the bug scales with the perimeter the builders are
	# ignoring. A 1x1 hut would hide it.
	var castle := w.spawn_building(&"building.castle", 1, Vector2i(20, 20),
			SimBuilding.Phase.FOUNDATION, true)
	var rect := castle.footprint_rect()

	# Stood off to one side, all together, which is how a player's selection arrives:
	# they box-select the villagers and tap the foundation.
	var ids: Array[int] = []
	for i in range(crowd):
		var u := w.spawn_unit(&"unit.villager", 1, Vector2i(10 + i % 4, 34 + i / 4))
		ids.append(u.id)

	w.queue_command(BuildCommand.new(1, ids, castle.id))

	# Run until they have all stopped moving, or the clock runs out. Not until the castle
	# is finished -- what is being measured is where they STAND, and a finished building
	# retires everybody.
	for i in range(_MAX_TICKS):
		w.step()
		if _all_settled(w, ids):
			break

	_report(crowd, w, ids, rect)


## Every builder has arrived: no path left to walk.
func _all_settled(w: SimWorld, ids: Array[int]) -> bool:
	for id in ids:
		var u := w.get_entity(id) as SimUnit
		if u == null or not u.alive:
			continue
		if u.path_pending or u.path_index < u.path.size():
			return false
	return true


func _report(crowd: int, w: SimWorld, ids: Array[int], rect: Rect2i) -> void:
	var tiles: Array[Vector2i] = []
	var working := 0
	var occupied := {}
	for id in ids:
		var u := w.get_entity(id) as SimUnit
		if u == null or not u.alive:
			continue
		var t := u.tile()
		tiles.append(t)
		occupied[t] = int(occupied.get(t, 0)) + 1
		if _adjacent_to_rect(t, rect):
			working += 1

	var spread := _bounds(tiles)
	var stacked := 0
	for t in occupied:
		if int(occupied[t]) > 1:
			stacked += int(occupied[t]) - 1

	print("  %2d builders on a %dx%d castle" % [crowd, rect.size.x, rect.size.y])
	print("      spread      %dx%d tiles" % [spread.size.x, spread.size.y])
	print("      touching    %d of %d are adjacent and adding progress" % [working, crowd])
	print("      stacked     %d sharing a tile with somebody" % stacked)

	# ⛔ THE ASSERTION IS "IS EVERYONE WORKING", not "are they tidy". A builder that is not
	# touching the footprint is one the player paid for and is not getting, and that is the
	# half of this that is not a matter of taste.
	if working < crowd:
		_problems.append("%d of %d builders on a castle are not touching it"
				% [crowd - working, crowd])
	# NOBODY SHARES A TILE while the ring still has room. `Formation`'s rule: two units on
	# one destination shove each other for the rest of the match.
	if stacked > 0 and crowd <= BuildStations.ring(rect, w.map).size():
		_problems.append("%d builders are sharing tiles on a castle with room for %d"
				% [stacked + 1, BuildStations.ring(rect, w.map).size()])

	# ⛔ **SPREAD IS PRINTED AND NOT ASSERTED, AND THE FIRST VERSION OF THIS FILE GOT THAT
	# WRONG.** It failed any crowd whose bounding box was smaller than the building, on the
	# reasoning that a 7x7 castle has 32 perimeter tiles and four builders have no excuse
	# to huddle. They do: they all walk in from the same side, and the four nearest
	# stations ARE on that side. Sending them round to the far wall to satisfy a bounding
	# box would be slower and would look deranged.
	#
	# The two assertions above are the actual complaint — everybody working, nobody
	# stacked — and neither can be satisfied by a heap. A regression that sent the whole
	# crowd back to one corner would trip both.


## `BuildSystem._adjacent_to_rect`, repeated rather than called: it is private to that
## system and this file must measure the SAME predicate the sim scores progress with.
## If the two ever disagree the number above is a lie, so it is worth the six lines.
func _adjacent_to_rect(from: Vector2i, rect: Rect2i) -> bool:
	var grown := rect.grow(1)
	return grown.has_point(from) and not rect.has_point(from)


func _bounds(tiles: Array[Vector2i]) -> Rect2i:
	if tiles.is_empty():
		return Rect2i()
	var lo := tiles[0]
	var hi := tiles[0]
	for t in tiles:
		lo.x = mini(lo.x, t.x)
		lo.y = mini(lo.y, t.y)
		hi.x = maxi(hi.x, t.x)
		hi.y = maxi(hi.y, t.y)
	return Rect2i(lo, hi - lo + Vector2i.ONE)


func _finish() -> void:
	print("")
	if _problems.is_empty():
		print("OK -- builders spread around what they are building.")
		get_tree().quit(0)
		return
	print("%d PROBLEM(S):" % _problems.size())
	for p in _problems:
		print("  - %s" % p)
	get_tree().quit(1)
