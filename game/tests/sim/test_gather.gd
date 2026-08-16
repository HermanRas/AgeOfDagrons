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


# ── gather slots (6.3) ──────────────────────────────────────────────────────

func test_a_node_only_lets_gather_slots_many_units_draw_from_it_at_once() -> void:
	# res.tree has gather_slots = 1. `villager` (spawned first, so the lower id)
	# wins the tree's one slot and keeps it for the whole run -- it never stops
	# holding the node, so there is never a tick where the slot is up for grabs.
	var second := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 21))
	w.queue_command(GatherCommand.new(1, [villager.id, second.id], tree.id))

	# Wait for the incumbent to retire, not just for the node to empty -- that
	# fires a tick before the last load it is still carrying home gets deposited.
	var ticks := _run_until(func(): return villager.is_idle(), 4000)
	assert_true(ticks > 0, "the tree still empties out eventually")
	assert_eq(second.carry_amount, 0, "the second villager never got a turn at a one-slot tree")
	assert_true(second.is_idle(),
			"nothing left in the tree for it to wait behind once the incumbent retired")
	assert_eq(w.players[0].stock.get(&"wood", 0), 40, "but the whole tree still ended up in stock")


func test_a_node_with_enough_slots_lets_multiple_units_gather_at_once() -> void:
	var mine := w.spawn_resource_node(&"res.gold_mine", Vector2i(9, 11), 0)   # slots = 4
	var second := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 21))
	w.queue_command(GatherCommand.new(1, [villager.id, second.id], mine.id))

	var ticks := _run_until(
			func(): return villager.carry_amount > 0 and second.carry_amount > 0, 200)
	assert_true(ticks > 0, "both drew from the mine at once -- four slots is room for two")


func test_a_freed_slot_is_picked_up_by_the_unit_waiting_behind_it() -> void:
	var second := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 21))
	w.queue_command(GatherCommand.new(1, [villager.id, second.id], tree.id))

	# Let the incumbent (lower id) claim the tree's one slot and the challenger
	# arrive and start waiting behind it.
	_run_until(func(): return villager.task == SimUnit.Task.GATHER and not villager.has_waypoint() \
			and second.task == SimUnit.Task.GATHER and not second.has_waypoint(), 200)
	assert_eq(second.carry_amount, 0, "still waiting, not gathering yet")

	# Pull the incumbent off the tree entirely -- its slot is now free.
	w.queue_command(StopCommand.new(1, [villager.id]))
	var ticks := _run_until(func(): return second.carry_amount > 0, 200)
	assert_true(ticks > 0, "the waiting villager picked the freed slot straight back up")


# ── an emptied node goes away (6.4) ─────────────────────────────────────────

func test_an_emptied_node_is_despawned_and_gives_its_tile_back() -> void:
	# Reported live 2026-08-16: chopped-out trees, mined-out rocks and picked
	# berry bushes all stayed on the map. A node claims occupancy, so leaving one
	# standing is not just a stale sprite -- it is an unwalkable, unbuildable hole
	# in the ground that looks exactly like a tree.
	var tile := tree.tile()
	var ticks := 0
	_order_gather()
	ticks = _run_until(func(): return villager.is_idle(), 4000)
	assert_true(ticks > 0, "the tree ran out")
	assert_null(w.get_entity(tree.id), "and is gone, not standing empty")
	assert_eq(w.map.occupant(tile), 0, "its tile is unclaimed")
	assert_true(w.map.is_passable(tile, SimMap.Domain.LAND), "walkable, not an invisible wall")
	assert_true(w.map.can_place_building(Rect2i(tile, Vector2i.ONE)), "and buildable")
	assert_eq(w.players[0].stock.get(&"wood", 0), 40,
			"the last load still landed -- the node went, the wood did not")


func test_a_node_emptied_with_nobody_working_it_still_goes() -> void:
	# The sweep is over NODES, not over the villagers tasked to them: a node
	# emptied by a worker that was then re-tasked away has nobody left to notice.
	tree.amount = 0
	w.step()
	assert_null(w.get_entity(tree.id))


func test_the_view_is_told_the_node_went_rather_than_left_to_notice() -> void:
	# `removed[]` is how a pooled EntityView is freed (7.2). Without this the
	# sprite would stay on screen with nothing behind it.
	tree.amount = 0
	w.step()
	assert_true(w.removed_this_tick.has(tree.id))


# ── re-scanning for the next node (project owner, 2026-08-16) ───────────────

func test_a_villager_moves_to_the_next_tree_instead_of_going_idle() -> void:
	# Watched live: a villager finished its tree and stopped dead beside a wood
	# full of untouched ones. It now looks around where the last one stood.
	var neighbour := w.spawn_resource_node(&"res.tree", Vector2i(8, 10), 0)
	assert_not_null(neighbour, "there is a second tree one tile over")
	_order_gather()

	var ticks := _run_until(func(): return villager.gather_node_id == neighbour.id, 4000)
	assert_true(ticks > 0, "it carried on with the tree next door")
	assert_true(tree.is_depleted() or w.get_entity(tree.id) == null,
			"having actually finished the first one")


func test_the_search_is_tight_rather_than_map_wide() -> void:
	# RESCAN_RADIUS is 1 on purpose: a worker should carry on with the wood it is
	# already standing in, not set off across the map on an order the player
	# never gave and cannot see coming.
	var far := w.spawn_resource_node(&"res.tree", Vector2i(30, 30), 0)
	assert_not_null(far)
	_order_gather()

	var ticks := _run_until(func(): return villager.is_idle(), 4000)
	assert_true(ticks > 0, "it retired rather than walking twenty tiles")
	assert_eq(far.amount, far.starting_amount, "the distant tree was never touched")


func test_a_villager_shut_out_of_a_full_node_takes_the_one_beside_it() -> void:
	# The second trigger. res.tree has one slot, so the challenger used to stand
	# in a queue behind the incumbent while an identical tree sat untouched one
	# tile away.
	var neighbour := w.spawn_resource_node(&"res.tree", Vector2i(8, 10), 0)
	var second := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 21))
	w.queue_command(GatherCommand.new(1, [villager.id, second.id], tree.id))

	var ticks := _run_until(func(): return second.gather_node_id == neighbour.id, 600)
	assert_true(ticks > 0, "the shut-out villager went next door")
	assert_eq(villager.gather_node_id, tree.id, "and the incumbent kept its own tree")


func test_it_will_not_swap_one_full_node_for_another() -> void:
	# Both trees are one-slot and both are taken, so there is nothing to gain by
	# moving -- and a villager that hopped between them would look like it was
	# malfunctioning rather than waiting.
	var neighbour := w.spawn_resource_node(&"res.tree", Vector2i(8, 10), 0)
	var b := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 21))
	var c := w.spawn_unit(&"unit.villager", 1, Vector2i(21, 20))
	w.queue_command(GatherCommand.new(1, [villager.id], tree.id))
	w.queue_command(GatherCommand.new(1, [b.id], neighbour.id))
	_run_until(func(): return villager.carry_amount > 0 and b.carry_amount > 0, 400)

	w.queue_command(GatherCommand.new(1, [c.id], tree.id))
	for i in range(60):
		w.step()
	assert_true(c.gather_node_id == tree.id or c.gather_node_id == neighbour.id,
			"it holds station at one of them rather than ping-ponging")
	assert_eq(c.carry_amount, 0, "and gathers from neither, both being full")


func test_a_villager_only_re_scans_for_the_kind_it_was_working() -> void:
	# A gold mine beside a spent tree is not "another tree". Swapping kinds
	# mid-order would quietly change what the player asked for.
	var mine := w.spawn_resource_node(&"res.gold_mine", Vector2i(8, 10), 0)
	_order_gather()
	var ticks := _run_until(func(): return villager.is_idle(), 4000)
	assert_true(ticks > 0)
	assert_eq(mine.amount, mine.starting_amount, "the gold was left alone")


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


func test_two_worlds_with_units_competing_for_the_same_slot_stay_identical() -> void:
	# The scenario the slot cap itself is riskiest for: three units chasing a
	# one-slot tree, only one of them ever actually extracting.
	var other := SimWorld.new()
	other.setup(MatchConfig.debug_single_player())
	other.spawn_building(&"building.town_center", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)
	var other_tree := other.spawn_resource_node(&"res.tree", Vector2i(9, 10), 0)
	other.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))               # id 3, same as w
	var other_ids: Array[int] = [3]
	for pos in [Vector2i(20, 21), Vector2i(21, 20)]:
		other_ids.append(other.spawn_unit(&"unit.villager", 1, pos).id)

	var ids: Array[int] = [villager.id]
	for pos in [Vector2i(20, 21), Vector2i(21, 20)]:
		ids.append(w.spawn_unit(&"unit.villager", 1, pos).id)

	w.queue_command(GatherCommand.new(1, ids, tree.id))
	other.queue_command(GatherCommand.new(1, other_ids, other_tree.id))

	for i in range(400):
		w.step()
		other.step()
		assert_eq(w.state_hash(), other.state_hash(), "diverged on tick %d" % (i + 1))
