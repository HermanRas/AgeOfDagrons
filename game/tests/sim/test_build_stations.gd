## Where several builders stand to raise one building (owner, playtest 2026-09-21:
## *"the villagers bunching up on one spot, trying to build the castle"*).
##
## `dev_preview/preview_build_stations.tscn` measures the OUTCOME -- it runs a real world
## and counts who ends up touching the footprint. This file asserts the ALLOCATOR, which is
## pure and can be asked questions a running sim cannot: determinism against a shuffled
## input, and what happens when the ring is full.
extends TestCase

var w: SimWorld


func before_each() -> void:
	w = SimWorld.new()
	w.setup(MatchConfig.debug_single_player())


func _rect(origin: Vector2i = Vector2i(20, 20), span: int = 7) -> Rect2i:
	return Rect2i(origin, Vector2i(span, span))


func _tiles(n: int, from: Vector2i = Vector2i(10, 10)) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in range(n):
		out.append(from + Vector2i(i % 4, i / 4))
	return out


func _ids(n: int, first: int = 1) -> Array[int]:
	var out: Array[int] = []
	for i in range(n):
		out.append(first + i)
	return out


## The predicate `BuildSystem` scores progress with. A station outside it is a villager
## standing where it cannot work, which is the bug rather than the fix.
func _adjacent(t: Vector2i, rect: Rect2i) -> bool:
	return rect.grow(1).has_point(t) and not rect.has_point(t)


# ── the shape of the answer ─────────────────────────────────────────────────

func test_one_station_per_builder() -> void:
	var out := BuildStations.around(_rect(), w.map, _tiles(8), _ids(8))
	assert_eq(out.size(), 8, "never returns fewer than it was given")


func test_no_builders_no_stations() -> void:
	var out := BuildStations.around(_rect(), w.map, [] as Array[Vector2i], [] as Array[int])
	assert_true(out.is_empty())


func test_every_station_touches_the_footprint() -> void:
	# THE LOAD-BEARING ONE. `BuildSystem` only counts a villager adjacent to the rect, so a
	# station one tile further out is a builder the player paid for and is not getting.
	var rect := _rect()
	var out := BuildStations.around(rect, w.map, _tiles(12), _ids(12))
	for i in range(out.size()):
		assert_true(_adjacent(out[i], rect),
				"builder %d at %s touches %s" % [i, out[i], rect])


func test_a_crowd_that_fits_gets_distinct_tiles() -> void:
	# `Formation`'s rule, one order over: two units sharing a destination tile is a pair
	# that shoves each other for the rest of the match. A 7x7 has 32 stations.
	var rect := _rect()
	var out := BuildStations.around(rect, w.map, _tiles(12), _ids(12))
	var seen := {}
	for t in out:
		assert_false(seen.has(t), "%s was handed out twice" % t)
		seen[t] = true


func test_the_old_behaviour_was_one_tile_for_everybody() -> void:
	# Pinned as the thing that CHANGED, so a revert is loud. Before 2026-09-21 every
	# builder got `b.tile()` -- the footprint's top-left -- and this is what that looked
	# like: one distinct destination for any crowd.
	var rect := _rect()
	var out := BuildStations.around(rect, w.map, _tiles(12), _ids(12))
	var distinct := {}
	for t in out:
		distinct[t] = true
	assert_true(distinct.size() > 1,
			"twelve builders no longer share one destination (was 1, now %d)"
			% distinct.size())


# ── determinism, which is a desync if it fails ──────────────────────────────

func test_the_same_question_gets_the_same_answer() -> void:
	var rect := _rect()
	var a := BuildStations.around(rect, w.map, _tiles(9), _ids(9))
	var b := BuildStations.around(rect, w.map, _tiles(9), _ids(9))
	assert_eq(a, b)


func test_the_answer_follows_the_ID_and_not_the_list_order() -> void:
	# ⛔ THIS IS THE DESYNC TEST. Two hosts can hold the same builders in a different list
	# order -- a selection is a client-side thing -- and if the allocator ranked by
	# position in the array they would send the same villager to two different tiles and
	# the simulations would part company. It sorts by id for exactly this.
	var rect := _rect()
	var tiles := _tiles(6)
	var ids := _ids(6)

	var forward := BuildStations.around(rect, w.map, tiles, ids)

	var rev_tiles: Array[Vector2i] = []
	var rev_ids: Array[int] = []
	for i in range(ids.size() - 1, -1, -1):
		rev_tiles.append(tiles[i])
		rev_ids.append(ids[i])
	var backward := BuildStations.around(rect, w.map, rev_tiles, rev_ids)

	for i in range(ids.size()):
		var mirrored: int = ids.size() - 1 - i
		assert_eq(forward[i], backward[mirrored],
				"builder %d gets the same station whichever end of the list it is at"
				% ids[i])


# ── the awkward cases ───────────────────────────────────────────────────────

func test_more_builders_than_stations_doubles_up_rather_than_refusing() -> void:
	# A 1x1 offers eight stations. Twelve villagers sent to a house must all still be
	# given somewhere to stand and something to do -- leaving four idle beside a building
	# they were told to raise is a worse bug than the one being fixed.
	var rect := Rect2i(Vector2i(20, 20), Vector2i.ONE)
	var out := BuildStations.around(rect, w.map, _tiles(12), _ids(12))
	assert_eq(out.size(), 12)
	for i in range(out.size()):
		assert_true(_adjacent(out[i], rect),
				"the %dth builder is still touching the house" % i)


func test_an_overfull_ring_is_filled_evenly_rather_than_stacked() -> void:
	# The second pass picks the LEAST-CROWDED station, so twelve builders on eight tiles
	# go 2,2,2,2,1,1,1,1 rather than putting five on whichever tile is nearest.
	var rect := Rect2i(Vector2i(20, 20), Vector2i.ONE)
	var out := BuildStations.around(rect, w.map, _tiles(12), _ids(12))
	var count := {}
	for t in out:
		count[t] = int(count.get(t, 0)) + 1
	var most := 0
	for t in count:
		most = maxi(most, int(count[t]))
	assert_true(most <= 2, "no tile takes more than its share (worst was %d)" % most)


func test_a_footprint_with_nowhere_free_beside_it_still_answers() -> void:
	# Walled in on every side by the map edge: there is no legal station, and the caller
	# must still get a destination per builder rather than a short list it has to
	# interpret. `PathService` then puts them as close as the ground allows.
	var rect := Rect2i(Vector2i(0, 0), Vector2i(2, 2))
	var out := BuildStations.around(rect, null, _tiles(3), _ids(3))
	assert_eq(out.size(), 3, "a null map is the degenerate case and is answered, not crashed")


func test_the_ring_is_only_one_tile_deep() -> void:
	# Widening it -- which `SimMap.find_free_adjacent` does, answering a different question
	# -- would put builders where they cannot reach the footprint.
	var rect := _rect()
	for t in BuildStations.ring(rect, w.map):
		assert_true(_adjacent(t, rect), "%s is on the first ring" % t)


func test_a_builder_is_sent_to_the_near_side_rather_than_around_the_building() -> void:
	# Nearest-first, not "fill the scan order". A villager standing south of a castle must
	# not be marched round to the north wall because that tile came first in the list.
	var rect := _rect(Vector2i(20, 20), 7)
	var below: Array[Vector2i] = [Vector2i(23, 30)]
	var out := BuildStations.around(rect, w.map, below, [1] as Array[int])
	assert_true(out[0].y >= rect.end.y - 1,
			"sent to the near (south) edge, not %s" % out[0])
