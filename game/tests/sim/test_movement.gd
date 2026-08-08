## Phase 4.1: a MoveCommand becomes a route, and the unit walks it.
##
## Driven through the real `SimWorld.step()` rather than by calling systems
## directly, because the ordering between them is the part most likely to be wrong
## -- plan, then retire, then move -- and calling them by hand would test an order
## the game does not use.
extends TestCase

var w: SimWorld
var unit: SimUnit


func before_each() -> void:
	w = SimWorld.new()
	w.setup(MatchConfig.debug_single_player())
	unit = w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))


func _order(to: Vector2i) -> void:
	w.queue_command(MoveCommand.new(1, [unit.id], to))


## Step until the unit goes idle, or give up. Returns the ticks taken, or -1.
func _run_until_idle(max_ticks: int = 400) -> int:
	for i in range(max_ticks):
		w.step()
		if unit.is_idle():
			return i + 1
	return -1


# ── the happy path ─────────────────────────────────────────────────────────

func test_an_ordered_unit_walks_to_the_tile_and_goes_idle() -> void:
	_order(Vector2i(26, 24))
	var ticks := _run_until_idle()
	assert_true(ticks > 0, "it arrived rather than walking forever")
	assert_eq(unit.tile(), Vector2i(26, 24))
	assert_eq(unit.pos, SimUnit.centre_of_tile(Vector2i(26, 24)),
			"exactly on the tile centre, where the view draws it")


func test_a_unit_is_planning_before_it_is_walking() -> void:
	# The order lands and the search is queued in the same tick; the unit must not
	# set off in the target's general direction while waiting for the route.
	_order(Vector2i(26, 24))
	assert_true(unit.is_idle(), "not ordered until the command is drained")

	var before := unit.pos
	w.step()
	assert_eq(unit.task, SimUnit.Task.MOVE)
	assert_false(unit.path.is_empty(), "planned within the same tick, budget permitting")
	assert_ne(unit.pos, before, "and moving in it too")


func test_the_route_is_walked_waypoint_by_waypoint_not_as_the_crow_flies() -> void:
	# Wall the unit in except for a gap, and check every tile it stands on is
	# walkable -- a straight-line mover would cross the rock.
	for y in range(14, 28):
		if y != 26:
			w.map.set_terrain(Vector2i(24, y), SimMap.Terrain.ROCK)
	w.paths.mark_dirty()

	_order(Vector2i(28, 20))
	for i in range(400):
		w.step()
		assert_true(w.map.is_terrain_passable(unit.tile()),
				"tick %d: standing on %s" % [i, unit.tile()])
		if unit.is_idle():
			break
	assert_eq(unit.tile(), Vector2i(28, 20), "and it got there the long way round")


func test_a_unit_ordered_where_it_already_stands_does_not_get_stuck() -> void:
	_order(unit.tile())
	assert_true(_run_until_idle(20) > 0, "it retires rather than sitting in MOVE forever")
	assert_eq(unit.tile(), Vector2i(20, 20))


# ── stopping at the nearest reachable tile (4.1) ───────────────────────────

func test_an_order_onto_an_occupied_tile_stops_beside_it() -> void:
	# Tapping a tree: the tile is claimed by a resource node, so it cannot be
	# stood on, but the order still means something.
	var tree := w.spawn_resource_node(&"res.tree", Vector2i(26, 24))
	assert_not_null(tree)

	_order(Vector2i(26, 24))
	assert_true(_run_until_idle() > 0)
	assert_ne(unit.tile(), Vector2i(26, 24), "not on top of the tree")
	assert_true((unit.tile() - Vector2i(26, 24)).length() < 2.0, "but next to it")
	assert_eq(unit.task_target_tile, unit.tile(),
			"the task's target is rewritten to where it could actually get to")


func test_an_unreachable_order_retires_instead_of_walking_forever() -> void:
	# Fence the unit in completely. The wrong behaviour is to stay in MOVE, which
	# looks like an ordered unit that never arrives and never gives up.
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		w.map.set_terrain(unit.tile() + d, SimMap.Terrain.ROCK)
	w.paths.mark_dirty()

	_order(Vector2i(40, 40))
	assert_true(_run_until_idle(20) > 0, "it accepts that it cannot get there")
	assert_eq(unit.tile(), Vector2i(20, 20), "and stays where it was")


# ── re-ordering and stopping ───────────────────────────────────────────────

func test_a_new_order_replaces_the_old_route() -> void:
	_order(Vector2i(30, 30))
	w.step()
	w.step()
	_order(Vector2i(12, 12))
	assert_true(_run_until_idle() > 0)
	assert_eq(unit.tile(), Vector2i(12, 12), "it obeys the newest order, not the first")


func test_stopping_drops_a_route_that_has_not_been_planned_yet() -> void:
	# The search is budgeted, so a stop can land while the route is still queued.
	# Solving it afterwards would hand a stopped unit somewhere to walk.
	_order(Vector2i(40, 40))
	w.queue_command(StopCommand.new(1, [unit.id]))
	w.step()
	w.step()
	assert_true(unit.is_idle())
	assert_true(unit.path.is_empty(), "no route was delivered after the stop")
	assert_eq(w.paths.queued(), 0)


# ── determinism (7.1) ──────────────────────────────────────────────────────

func test_two_worlds_given_the_same_orders_stay_identical() -> void:
	var other := SimWorld.new()
	other.setup(MatchConfig.debug_single_player())
	var other_unit := other.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))

	w.map.set_terrain(Vector2i(24, 21), SimMap.Terrain.ROCK)
	other.map.set_terrain(Vector2i(24, 21), SimMap.Terrain.ROCK)
	w.paths.mark_dirty()
	other.paths.mark_dirty()

	_order(Vector2i(30, 22))
	other.queue_command(MoveCommand.new(1, [other_unit.id], Vector2i(30, 22)))

	for i in range(60):
		w.step()
		other.step()
		assert_eq(w.state_hash(), other.state_hash(), "diverged on tick %d" % (i + 1))
