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


# -- facing (owner, 2026-08-27: "villager mining away from gold") ------------

func test_a_gathering_villager_turns_to_face_the_node() -> void:
	# Until 2026-08-27 `facing` was written in exactly two places -- MovementSystem
	# (the way you walk) and CombatSystem (the thing you are hitting) -- so a
	# villager kept whatever direction her last path step left her in and mined
	# over her shoulder. The tree is WEST of where she starts, so arriving from the
	# east and then turning is a real change of direction rather than a coincidence.
	_order_gather()
	var ticks := _run_until(func(): return villager.task == SimUnit.Task.GATHER \
			and not villager.has_waypoint() and not villager.path_pending, 200)
	assert_true(ticks > 0, "it arrived and started gathering")
	# ONE MORE TICK, and it is not padding. On the tick the walk ends, GatherSystem
	# has already run and returned early on `has_waypoint()`; MovementSystem clears
	# the waypoint afterwards. So the first tick that satisfies the predicate is the
	# tick BEFORE the first one that can turn her. Asserting without this reads the
	# state one tick early and fails on a fix that works.
	w.step()
	assert_eq(villager.facing, SimUnit.facing_toward(tree.pos - villager.pos),
			"turned at the node, not left pointing wherever it walked in from")


func test_it_faces_the_node_while_waiting_for_a_slot_too() -> void:
	# The turn is at the ADJACENCY check, ahead of the slot and cooldown gates, so
	# a villager queueing at a busy seam looks at it as well. Set to one slot and
	# send two: the loser holds its ground (GatherSystem's own rule) and must still
	# be facing the tree, or a queue is a row of villagers staring off the map.
	tree.gather_slots = 1
	var second := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 21))
	var ids: Array[int] = [villager.id, second.id]
	w.queue_command(GatherCommand.new(1, ids, tree.id))
	var ticks := _run_until(func(): return not second.has_waypoint() \
			and not second.path_pending \
			and (second.tile() - tree.tile()).length() < 2.0, 400)
	assert_true(ticks > 0, "the second villager reached the tree")
	w.step()          # see the note in the test above -- the arrival tick is too early
	assert_eq(second.facing, SimUnit.facing_toward(tree.pos - second.pos),
			"the one without a slot is facing the tree as well")


func test_the_turn_is_identical_on_two_hosts() -> void:
	# `facing` is part of state_hash(), so a turn computed any way that is not a
	# pure function of sim state is a desync rather than a cosmetic slip. This is
	# the same shape as the determinism test at the end of this file, narrowed to
	# the field the new lines write.
	var other := SimWorld.new()
	other.setup(MatchConfig.debug_single_player())
	other.spawn_building(&"building.town_center", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)
	var other_tree := other.spawn_resource_node(&"res.tree", Vector2i(9, 10), 0)
	var other_villager := other.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))

	_order_gather()
	other.queue_command(GatherCommand.new(1, [other_villager.id], other_tree.id))
	for i in range(200):
		w.step()
		other.step()
		assert_eq(villager.facing, other_villager.facing,
				"facing diverged on tick %d" % (i + 1))


# ── the drop-off has eight doors, not one (project owner, 2026-08-28) ────────

func test_the_drop_off_offers_four_corners_and_four_side_middles() -> void:
	var points := SimBuilding.drop_off_points(Rect2i(10, 10, 4, 4))
	assert_eq(points.size(), 8)
	# Every one is exactly one tile outside the footprint: Chebyshev 1 from the rect,
	# which is also what `_process_return`'s arrival check demands.
	for p in points:
		assert_eq(CombatSystem.tile_gap(p, Rect2i(10, 10, 4, 4)), 1, str(p))
	# The four corners and the four side middles, named.
	for expected in [Vector2i(12, 9), Vector2i(14, 12), Vector2i(12, 14), Vector2i(9, 12),
			Vector2i(9, 9), Vector2i(14, 9), Vector2i(14, 14), Vector2i(9, 14)]:
		assert_true(points.has(expected), "%s is offered" % expected)


func test_a_one_tile_building_still_answers_with_its_eight_neighbours() -> void:
	# The midpoint of a 1-wide span lands on the only column, so two of the eight
	# coincide with corners. Nearest-wins is indifferent to a duplicate, and the
	# alternative -- special-casing small footprints -- would be a second rule.
	var points := SimBuilding.drop_off_points(Rect2i(5, 5, 1, 1))
	assert_eq(points.size(), 8)
	for p in points:
		assert_eq(CombatSystem.tile_gap(p, Rect2i(5, 5, 1, 1)), 1, str(p))


func test_villagers_coming_from_opposite_sides_deliver_to_opposite_sides() -> void:
	# THE BUG ITSELF. Every returning villager used to be sent to `bld.tile()` -- the
	# solid centre -- so `PathService.goal_for` substituted ONE fixed tile for all of
	# them, which is what "dropoff only in front of building" was. Two villagers
	# approaching from north and south must now pick different doors.
	var north := w.spawn_unit(&"unit.villager", 1, Vector2i(11, 5))
	var south := w.spawn_unit(&"unit.villager", 1, Vector2i(11, 17))
	for u in [north, south]:
		u.carry_kind = &"wood"
		u.carry_amount = 10

	var sys := GatherSystem.new()
	sys._start_return(w, north)
	sys._start_return(w, south)

	assert_eq(north.task, SimUnit.Task.RETURN)
	assert_eq(south.task, SimUnit.Task.RETURN)
	assert_ne(north.task_target_tile, south.task_target_tile,
			"two villagers from opposite sides must not queue on one tile")
	assert_true(north.task_target_tile.y < south.task_target_tile.y,
			"and each takes the side it came from")


# ── the drop-off is destroyed under a loaded villager (owner, 2026-08-28) ───
#
# "at the end of a round, i destroyed the towncentre, the ai villagers where bugging
# out, trying to complete their task but not doing anything. when the ai towncentre
# [is destroyed] have the villagers run back to its location."

## Gather until the first load has been banked, so `deposit_tile` is set the way a real
## villager sets it -- by actually delivering somewhere, not by a fixture writing the
## field. That is the whole mechanism under test.
func _deliver_one_load() -> void:
	_order_gather()
	var ticks := _run_until(func(): return w.players[0].stock.get(&"wood", 0) > 0, 1000)
	assert_true(ticks > 0, "the first load landed")


func test_a_villager_remembers_where_she_banked() -> void:
	_deliver_one_load()
	assert_eq(villager.deposit_tile, tc.tile(),
			"the town centre's tile, learned by delivering to it")


func test_a_villager_who_never_banked_anywhere_remembers_nothing() -> void:
	# The sentinel has to be a tile no map has, since (0, 0) is a real one.
	assert_eq(villager.deposit_tile, Vector2i(-1, -1))


func test_a_loaded_villager_walks_home_when_the_drop_off_is_destroyed() -> void:
	_deliver_one_load()
	var home := villager.deposit_tile
	# Load her up and take the town centre away, which is the moment being tested.
	villager.carry_kind = &"wood"
	villager.carry_amount = 10
	w.queue_command(DebugDestroyCommand.new(1, tc.id))
	w.step()

	var sys := GatherSystem.new()
	sys._start_return(w, villager)
	assert_eq(villager.task, SimUnit.Task.MOVE,
			"walking somewhere rather than downing tools where she stands")
	assert_eq(villager.task_target_tile, home, "back to where the town centre was")


func test_she_still_prefers_a_SURVIVING_drop_off_to_the_ruins() -> void:
	# Walking home is the last resort, not the first. A player who loses a town centre
	# but still owns a mill must have her deliver to the mill.
	_deliver_one_load()
	var mill := w.spawn_building(&"building.mill", 1, Vector2i(24, 10),
			SimBuilding.Phase.COMPLETE, true)
	villager.carry_kind = &"food"
	villager.carry_amount = 10
	w.queue_command(DebugDestroyCommand.new(1, tc.id))
	w.step()

	var sys := GatherSystem.new()
	sys._start_return(w, villager)
	assert_eq(villager.task, SimUnit.Task.RETURN, "a real delivery, not a walk home")
	assert_eq(villager.task_target_id, mill.id)


func test_a_villager_already_standing_on_the_ruins_stops_rather_than_pathing_to_herself() -> void:
	_deliver_one_load()
	villager.carry_kind = &"wood"
	villager.carry_amount = 10
	w.queue_command(DebugDestroyCommand.new(1, tc.id))
	w.step()
	# Stand her exactly where the town centre was.
	var home := villager.deposit_tile
	villager.pos = home * SimWorld.SUBTILE + Vector2i(SimWorld.SUBTILE, SimWorld.SUBTILE) / 2

	var sys := GatherSystem.new()
	sys._start_return(w, villager)
	assert_eq(villager.task, SimUnit.Task.IDLE, "she is home; there is nowhere to walk")


func test_the_AI_stops_ordering_gathers_it_cannot_bank() -> void:
	# THE OTHER HALF OF THE LOOP, and the half that made it look like a bug. Walking
	# home is legible, but `AISystem._keep_busy` hands every idle villager a fresh
	# GatherCommand a few ticks later -- so she walks back to the tree, is already
	# full, is retired again, forever. A person does not keep chopping wood they
	# cannot store.
	var ai := AISystem.new()
	var p := w.players[0]
	assert_ne(ai._bankable_kind(w, p, villager.id), &"",
			"with a town centre standing, something is bankable")

	w.queue_command(DebugDestroyCommand.new(1, tc.id))
	w.step()
	assert_eq(ai._bankable_kind(w, p, villager.id), &"",
			"with every drop-off gone, nothing is -- and no order is issued")


func test_losing_one_drop_off_of_several_changes_nothing() -> void:
	# The bound. An AI whose mill burns down but whose town centre stands carries on.
	var ai := AISystem.new()
	var p := w.players[0]
	var mill := w.spawn_building(&"building.mill", 1, Vector2i(24, 10),
			SimBuilding.Phase.COMPLETE, true)
	w.queue_command(DebugDestroyCommand.new(1, mill.id))
	w.step()
	assert_ne(ai._bankable_kind(w, p, villager.id), &"", "the town centre still takes it")


# ── a shoved worker walks back instead of going idle (owner, 2026-08-28) ─────

func test_a_gatherer_pushed_off_the_ring_walks_back_rather_than_going_idle() -> void:
	# THE REPORT: "villager push each other out of the way, when they are pushed too
	# far from build site for mining rock or tree for chopping it stops their work and
	# leaves them idle." `SeparationSystem` CAN carry a unit across a tile boundary --
	# MAX_PUSH is 120 of a 256 sub-tile, which only stays inside the tile from its
	# centre -- and the adjacency check then read that as "the order cannot be honoured".
	_order_gather()
	var ticks := _run_until(func() -> bool: return villager.task == SimUnit.Task.GATHER \
			and not villager.path_pending, 200)
	assert_true(ticks > 0, "the villager reached the tree")

	# Shove it two tiles clear, the way a crowd would.
	var away := villager.tile() + Vector2i(2, 2)
	villager.pos = away * SimWorld.SUBTILE + Vector2i(SimWorld.SUBTILE, SimWorld.SUBTILE) / 2
	w.spatial.move(villager.id, away)

	w.step()
	assert_ne(villager.task, SimUnit.Task.IDLE, "it does not down tools")
	assert_eq(villager.task, SimUnit.Task.GATHER, "it is still on the same job")

	# And it actually gets back to work rather than standing there re-deciding.
	var back := _run_until(func() -> bool: return villager.task == SimUnit.Task.GATHER \
			and not villager.path_pending and villager.gather_cooldown > 0, 200)
	assert_true(back > 0, "it resumed gathering")


func test_a_gatherer_carried_right_across_the_map_still_retires() -> void:
	# The bound matters as much as the rescue: `rejoin_work` is for a SHOVE, and
	# anything past SAME_WORK_RADIUS was moved by something else. Without the bound a
	# unit teleported anywhere would walk back across the map on an order nobody gave.
	_order_gather()
	assert_true(_run_until(func() -> bool: return villager.task == SimUnit.Task.GATHER \
			and not villager.path_pending, 200) > 0)

	var far := villager.tile() + Vector2i(SimSystem.SAME_WORK_RADIUS + 5, 0)
	villager.pos = far * SimWorld.SUBTILE + Vector2i(SimWorld.SUBTILE, SimWorld.SUBTILE) / 2
	w.spatial.move(villager.id, far)
	# AND THE PATH GOES WITH IT, which is what a shove looks like: a unit that has
	# ARRIVED holds no route. Leaving the old one in place made the first version of
	# this test measure nothing at all -- `_process_gather` returns at its very first
	# line while `has_waypoint()` is true, so the villager quietly walked back and the
	# distance check was never reached.
	villager.path = PackedVector2Array()
	villager.path_index = 0
	villager.path_pending = false

	var idled := _run_until(func() -> bool: return villager.task == SimUnit.Task.IDLE, 10)
	assert_true(idled > 0, "too far to be a shove -- it retires")


func test_a_returning_villager_pushed_off_the_doorstep_still_banks_its_load() -> void:
	# Worse than the gather case: a villager retired on the doorstep is holding a full
	# load that never reaches the stockpile.
	#
	# THE RETURN IS SET UP DIRECTLY rather than waited for. With this fixture's tree
	# next door to the town centre the whole journey now takes no ticks at all -- the
	# villager is already standing on a drop-off point -- so RETURN is entered and left
	# inside one `step()` and cannot be caught by polling for it.
	var sys := GatherSystem.new()
	villager.carry_kind = &"wood"
	villager.carry_amount = 10
	sys._start_return(w, villager)
	assert_eq(villager.task, SimUnit.Task.RETURN)

	# Shoved two tiles clear of the doorstep, holding the load.
	var away := villager.tile() + Vector2i(0, 3)
	villager.pos = away * SimWorld.SUBTILE + Vector2i(SimWorld.SUBTILE, SimWorld.SUBTILE) / 2
	w.spatial.move(villager.id, away)
	villager.path_pending = false
	villager.path = PackedVector2Array()

	sys._process_return(w, villager)
	assert_ne(villager.task, SimUnit.Task.IDLE, "it does not drop the job on the doorstep")
	assert_eq(villager.carry_amount, 10, "and has not banked from out there either")

	var banked := _run_until(func() -> bool: return villager.carry_amount == 0, 200)
	assert_true(banked > 0, "the load was delivered")
	assert_true(w.player_for(1).stock.get(&"wood", 0) >= 10, "and banked")