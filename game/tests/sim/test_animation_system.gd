## PLAN.md 6.2/13.2: `SimUnit.anim` now reflects task and movement state
## instead of sitting on its "idle" default forever -- the villager anim set
## (idle/walk/walk_carry_*/work_chop/work_mine/work_hunt/work_build) was fully
## baked (ASSET_MISSING.md 1.1) with nothing on the sim side ever choosing
## among them. Found and reproduced live via dev_preview/debug_render_check.gd
## while confirming a builder rendered behind its house (the Y-sort fix
## alongside this one): every unit's anim printed "idle" regardless of task.
##
## Driven through SimWorld.step() rather than calling AnimationSystem
## directly, same reasoning as test_movement.gd -- its place in the system
## order (after Gather/Build/Movement, before DeathSystem) is exactly what
## makes "arrived this tick" and "died this tick" both read correctly.
extends TestCase

var w: SimWorld
var tc: SimBuilding


func before_each() -> void:
	w = SimWorld.new()
	w.setup(MatchConfig.debug_single_player())
	tc = w.spawn_building(&"building.town_center", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)


func _run_until(pred: Callable, max_ticks: int = 400) -> int:
	for i in range(max_ticks):
		w.step()
		if pred.call():
			return i + 1
	return -1


# ── idle and walking ────────────────────────────────────────────────────────

func test_a_freshly_spawned_unit_is_idle() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	w.step()
	assert_eq(v.anim, &"idle")


func test_a_unit_whose_search_is_still_queued_is_idle_not_walking() -> void:
	# Exhaust the per-tick solve budget (4.2) so the last one queued is
	# guaranteed still path_pending after one step, rather than depending on
	# how many ticks a single request happens to take to resolve.
	var units: Array[SimUnit] = []
	for i in range(PathService.MAX_SOLVES_PER_TICK + 1):
		units.append(w.spawn_unit(&"unit.villager", 1, Vector2i(20 + i, 20)))
	var ids: Array[int] = []
	for u in units:
		ids.append(u.id)
	w.queue_command(MoveCommand.new(1, ids, Vector2i(26, 24)))
	w.step()

	var last := units[units.size() - 1]
	assert_true(last.path_pending, "the budget could not reach the last one queued")
	assert_eq(last.anim, &"idle", "the search has not come back yet (4.2)")


func test_a_moving_unit_plays_walk() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	w.queue_command(MoveCommand.new(1, [v.id], Vector2i(30, 30)))
	var ticks := _run_until(func(): return v.has_waypoint())
	assert_true(ticks > 0)
	assert_eq(v.anim, &"walk")


func test_an_arrived_unit_with_no_task_returns_to_idle() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	w.queue_command(MoveCommand.new(1, [v.id], Vector2i(22, 22)))
	_run_until(func(): return v.is_idle())
	assert_eq(v.anim, &"idle")


# ── gathering, keyed by the node's kind ─────────────────────────────────────

func test_gathering_wood_plays_work_chop() -> void:
	var tree := w.spawn_resource_node(&"res.tree", Vector2i(9, 10))
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	w.queue_command(GatherCommand.new(1, [v.id], tree.id))
	var ticks := _run_until(func(): return v.task == SimUnit.Task.GATHER \
			and not v.has_waypoint() and not v.path_pending)
	assert_true(ticks > 0)
	assert_eq(v.anim, &"work_chop")


func test_gathering_gold_plays_work_mine() -> void:
	var mine := w.spawn_resource_node(&"res.gold_mine", Vector2i(9, 10))
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	w.queue_command(GatherCommand.new(1, [v.id], mine.id))
	var ticks := _run_until(func(): return v.task == SimUnit.Task.GATHER \
			and not v.has_waypoint() and not v.path_pending)
	assert_true(ticks > 0)
	assert_eq(v.anim, &"work_mine")


func test_gathering_food_plays_work_hunt() -> void:
	var bush := w.spawn_resource_node(&"res.berry_bush", Vector2i(9, 10))
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	w.queue_command(GatherCommand.new(1, [v.id], bush.id))
	var ticks := _run_until(func(): return v.task == SimUnit.Task.GATHER \
			and not v.has_waypoint() and not v.path_pending)
	assert_true(ticks > 0)
	assert_eq(v.anim, &"work_hunt")


## THE TREE IS FAR FROM THE TOWN CENTRE ON PURPOSE, since 2026-08-28. It used to be
## at (9, 10), which is touching the 4x4 town centre at (10, 10) -- and once
## `GatherSystem` learned to deliver to the NEAREST of eight drop-off points rather
## than to one substituted tile, a villager chopping there was already standing on a
## drop-off point. The walk home became zero-length, `has_waypoint()` never became
## true, and this test could not observe the state it names. That is the fix working:
## the old code walked the villager to a fixed tile and back for nothing. Moved out to
## (30, 30) so there is a real journey to carry a load along, which is what this test
## is actually about.
func test_carrying_a_load_home_plays_walk_carry_matching_the_kind() -> void:
	var tree := w.spawn_resource_node(&"res.tree", Vector2i(30, 30))
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	w.queue_command(GatherCommand.new(1, [v.id], tree.id))
	var ticks := _run_until(func(): return v.task == SimUnit.Task.RETURN and v.has_waypoint())
	assert_true(ticks > 0, "carried a load and set off for home")
	assert_eq(v.anim, &"walk_carry_wood")


# ── building ────────────────────────────────────────────────────────────────

func test_building_plays_work_build() -> void:
	var house := w.spawn_building(&"building.house", 1, Vector2i(20, 20), SimBuilding.Phase.FOUNDATION)
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(26, 26))
	w.queue_command(BuildCommand.new(1, [v.id], house.id))
	var ticks := _run_until(func(): return v.task == SimUnit.Task.BUILD \
			and not v.has_waypoint() and not v.path_pending)
	assert_true(ticks > 0)
	assert_eq(v.anim, &"work_build")


# ── death still wins (4.7) ──────────────────────────────────────────────────

func test_a_dying_unit_is_left_alone_by_animationsystem() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	w.queue_command(DebugDestroyCommand.new(1, v.id))
	w.step()
	assert_eq(v.anim, &"die", "DeathSystem's anim, not overwritten back to idle")

	for i in range(20):
		w.step()
	assert_true(v.anim == &"die" or v.anim == &"decay",
			"still one of DeathSystem's own anims, never idle/walk again")
