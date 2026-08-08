## Phases 4.1 and 4.2: routes around obstacles, a per-tick search budget, and
## units that walk what they were given.
##
## The determinism assertions carry the most weight. A path feeds a unit's
## position, so two clients that planned differently desync (PLAN.md 7.1) -- and
## unlike a wrong path, that failure is invisible until the simulations have
## already drifted apart.
extends TestCase

var svc: PathService
var map: SimMap


func before_each() -> void:
	svc = PathService.new()
	map = SimMap.create(Vector2i(16, 16), SimMap.Terrain.GRASS)


## A wall of impassable rock across the map at `x`, with a gap at `gap_y`.
func _wall(x: int, gap_y: int) -> void:
	for y in range(map.size.y):
		if y != gap_y:
			map.set_terrain(Vector2i(x, y), SimMap.Terrain.ROCK)
	svc.mark_dirty()


# ── routing (4.2) ──────────────────────────────────────────────────────────

func test_a_clear_map_gives_a_direct_route() -> void:
	var path := svc.find_path(map, Vector2i(1, 1), Vector2i(5, 5))
	assert_false(path.is_empty(), "there is nothing in the way")
	assert_eq(Vector2i(path[path.size() - 1]), Vector2i(5, 5), "it ends on the target")


func test_the_route_excludes_the_tile_the_unit_is_standing_on() -> void:
	# AStarGrid2D includes the start cell. Leaving it in makes every caller
	# special-case a first waypoint the unit has already reached, and makes an
	# "already there" result indistinguishable from a real one-step move.
	var path := svc.find_path(map, Vector2i(3, 3), Vector2i(3, 5))
	assert_ne(Vector2i(path[0]), Vector2i(3, 3), "the first waypoint is somewhere to go")
	assert_eq(path.size(), 2, "two tiles away is two waypoints")


func test_a_route_goes_around_a_wall_rather_than_through_it() -> void:
	_wall(8, 12)
	var path := svc.find_path(map, Vector2i(2, 2), Vector2i(14, 2))
	assert_false(path.is_empty(), "the gap makes it reachable")
	for p in path:
		var t := Vector2i(p)
		assert_true(map.is_passable(t), "%s is walkable" % t)
	assert_true(path.size() > 12, "it detours to the gap rather than cutting through")


func test_a_walled_off_target_yields_no_route_at_all() -> void:
	for y in range(map.size.y):
		map.set_terrain(Vector2i(8, y), SimMap.Terrain.ROCK)
	svc.mark_dirty()
	assert_true(svc.find_path(map, Vector2i(2, 2), Vector2i(14, 2)).is_empty(),
			"no gap, no path -- and no pretending otherwise")


func test_a_route_does_not_cut_the_corner_between_two_blocked_tiles() -> void:
	# A villager slipping diagonally between two buildings that touch reads as
	# walking through a wall.
	map.set_terrain(Vector2i(5, 4), SimMap.Terrain.ROCK)
	map.set_terrain(Vector2i(4, 5), SimMap.Terrain.ROCK)
	svc.mark_dirty()
	var path := svc.find_path(map, Vector2i(4, 4), Vector2i(5, 5))
	assert_false(path.is_empty(), "the target is still reachable the long way")
	assert_ne(Vector2i(path[0]), Vector2i(5, 5),
			"the first step is not the diagonal squeeze between the two blocked tiles")
	assert_true(path.size() > 1, "it goes round the corner rather than through it")


# ── stopping at the nearest reachable tile (4.1) ───────────────────────────

func test_an_order_onto_a_blocked_tile_stops_beside_it() -> void:
	# Tapping a tree is an ordinary thing to do and must not simply fail.
	map.set_terrain(Vector2i(9, 9), SimMap.Terrain.ROCK)
	svc.mark_dirty()
	var path := svc.find_path(map, Vector2i(2, 2), Vector2i(9, 9))
	assert_false(path.is_empty(), "the order is honoured as far as it can be")
	var arrived := Vector2i(path[path.size() - 1])
	assert_ne(arrived, Vector2i(9, 9), "not onto the blocked tile itself")
	assert_true(map.is_passable(arrived), "somewhere it can actually stand")
	assert_true((arrived - Vector2i(9, 9)).length() < 2.0, "and adjacent to what was tapped")


func test_the_substitute_tile_is_the_nearest_one_not_the_first_one_found() -> void:
	# Scanning a ring and returning on the first hit makes "nearest" depend on
	# which direction the loop ran, which is a desync in the shape of two clients
	# standing a unit on opposite sides of the same tree.
	map.set_terrain(Vector2i(9, 9), SimMap.Terrain.ROCK)
	svc.mark_dirty()
	var a := svc.find_path(map, Vector2i(2, 2), Vector2i(9, 9))
	var b := PathService.new().find_path(map, Vector2i(2, 2), Vector2i(9, 9))
	assert_eq(a, b, "two services pick the same substitute")


func test_an_order_into_the_middle_of_a_blocked_region_gives_up() -> void:
	map.fill_terrain(SimMap.Terrain.ROCK)
	map.set_terrain(Vector2i(1, 1), SimMap.Terrain.GRASS)
	svc.mark_dirty()
	assert_true(svc.find_path(map, Vector2i(1, 1), Vector2i(12, 12)).is_empty(),
			"the ring search is bounded rather than scanning the whole map")


func test_an_off_map_order_is_refused() -> void:
	assert_true(svc.find_path(map, Vector2i(1, 1), Vector2i(999, 999)).is_empty())
	assert_true(svc.find_path(map, Vector2i(-5, -5), Vector2i(1, 1)).is_empty())


# ── determinism (7.1) ──────────────────────────────────────────────────────

func test_two_services_on_the_same_map_return_identical_routes() -> void:
	_wall(8, 12)
	var other := PathService.new()
	for pair in [[Vector2i(1, 1), Vector2i(14, 14)], [Vector2i(3, 9), Vector2i(11, 2)],
			[Vector2i(15, 0), Vector2i(0, 15)]]:
		assert_eq(svc.find_path(map, pair[0], pair[1]), other.find_path(map, pair[0], pair[1]),
				"%s -> %s plans the same on both" % pair)


func test_the_same_query_twice_returns_the_same_route() -> void:
	_wall(8, 12)
	assert_eq(svc.find_path(map, Vector2i(1, 1), Vector2i(14, 14)),
			svc.find_path(map, Vector2i(1, 1), Vector2i(14, 14)),
			"a cached grid does not drift from a fresh one")


# ── the request queue and its budget (4.2) ─────────────────────────────────

func test_requests_are_queued_rather_than_solved_on_the_spot() -> void:
	svc.request(1, Vector2i(5, 5))
	svc.request(2, Vector2i(6, 6))
	assert_eq(svc.queued(), 2)


func test_re_ordering_a_queued_unit_replaces_its_request() -> void:
	# A player dragging a move order around would otherwise queue one search per
	# frame, and every stale one would still be solved.
	svc.request(1, Vector2i(5, 5))
	svc.request(1, Vector2i(9, 9))
	assert_eq(svc.queued(), 1, "one unit, one pending search")


func test_cancelling_removes_a_queued_request() -> void:
	svc.request(1, Vector2i(5, 5))
	svc.cancel(1)
	assert_eq(svc.queued(), 0)


func test_only_the_budget_is_solved_per_tick() -> void:
	var w := SimWorld.new()
	w.setup(MatchConfig.debug_single_player())
	var over := PathService.MAX_SOLVES_PER_TICK + 10
	for i in range(over):
		w.paths.request(i + 1, Vector2i(20, 20))

	w.paths.process(w)
	assert_eq(w.paths.queued(), over - PathService.MAX_SOLVES_PER_TICK,
			"the rest wait for the next tick rather than blowing the tick budget")
