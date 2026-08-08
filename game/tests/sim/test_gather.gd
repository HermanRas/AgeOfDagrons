## Phase 6.4: walk to a node, gather on a cooldown, carry up to cap, walk a load
## home, deposit, and either resume the same node or retire once it is empty.
##
## The tree sits one tile off the town centre's own footprint so the villager's
## walk-there and walk-home legs are both short -- the loop's LOGIC is under
## test, not its pathfinding, which test_movement.gd already covers on its own.
extends TestCase

var w: SimWorld
var villager: SimUnit
var tree: SimResourceNode
var tc: SimBuilding


func before_each() -> void:
	w = SimWorld.new()
	w.setup(MatchConfig.debug_single_player())
	tc = w.spawn_building(&"building.town_center", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)
	tree = w.spawn_resource_node(&"res.tree", Vector2i(9, 10), 0)   # size 0 -> amount 40
	villager = w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))


func _order_gather() -> void:
	w.queue_command(GatherCommand.new(1, [villager.id], tree.id))


func _run_until(pred: Callable, max_ticks: int) -> int:
	for i in range(max_ticks):
		w.step()
		if pred.call():
			return i + 1
	return -1


# ── the happy path ─────────────────────────────────────────────────────────

func test_a_villager_walks_to_the_tree_and_starts_gathering() -> void:
	_order_gather()
	var ticks := _run_until(func(): return villager.task == SimUnit.Task.GATHER \
			and not villager.has_waypoint() and not villager.path_pending, 200)
	assert_true(ticks > 0, "it arrived rather than never starting")
	assert_true((villager.tile() - tree.tile()).length() < 2.0, "standing next to the tree")


func test_a_full_load_is_deposited_and_the_villager_goes_back_for_more() -> void:
	_order_gather()
	var ticks := _run_until(func(): return w.players[0].stock.get(&"wood", 0) >= 10, 1000)
	assert_true(ticks > 0, "the first load landed in the stockpile")
	assert_eq(villager.carry_amount, 0, "handed off, not held")
	assert_true(villager.task == SimUnit.Task.GATHER or villager.task == SimUnit.Task.RETURN,
			"it turned right back around for the tree rather than going idle with wood left")


func test_the_tree_is_fully_gathered_and_the_villager_retires() -> void:
	_order_gather()
	var ticks := _run_until(func(): return villager.is_idle(), 4000)
	assert_true(ticks > 0, "it eventually ran the tree out and stopped")
	assert_true(tree.is_depleted())
	assert_eq(w.players[0].stock.get(&"wood", 0), 40, "the whole tree ended up in stock")
	assert_eq(villager.carry_amount, 0)


# ── the last, partial load ─────────────────────────────────────────────────

func test_the_final_load_is_capped_by_what_remains_not_by_carry_capacity() -> void:
	tree.amount = 5
	tree.starting_amount = 5
	_order_gather()
	var ticks := _run_until(func(): return villager.is_idle(), 2000)
	assert_true(ticks > 0)
	assert_eq(w.players[0].stock.get(&"wood", 0), 5, "5 units, not padded up to carry_cap's 10")


# ── rejection ───────────────────────────────────────────────────────────────

func test_gather_command_rejects_an_already_depleted_node() -> void:
	tree.amount = 0
	var cmd := GatherCommand.new(1, [villager.id], tree.id)
	assert_false(cmd.validate(w))


func test_gather_command_rejects_a_unit_that_does_not_belong_to_the_player() -> void:
	var cmd := GatherCommand.new(2, [villager.id], tree.id)
	assert_false(cmd.validate(w), "villager belongs to player 1, not 2")


# ── determinism (7.1) ──────────────────────────────────────────────────────

func test_two_worlds_given_the_same_gather_order_stay_identical() -> void:
	var other := SimWorld.new()
	other.setup(MatchConfig.debug_single_player())
	other.spawn_building(&"building.town_center", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)
	var other_tree := other.spawn_resource_node(&"res.tree", Vector2i(9, 10), 0)
	var other_villager := other.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))

	_order_gather()
	other.queue_command(GatherCommand.new(1, [other_villager.id], other_tree.id))

	for i in range(400):
		w.step()
		other.step()
		assert_eq(w.state_hash(), other.state_hash(), "diverged on tick %d" % (i + 1))
