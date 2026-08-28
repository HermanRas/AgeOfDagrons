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


# ── animals (the 2026-08-28 wildlife bakes) ─────────────────────────────────

func test_a_settled_animal_grazes_rather_than_idling() -> void:
	# `feeding` only EXISTS on the cattle -- 0 A.D.'s boar and deer look like they
	# declare one and the name is a variant with no animation behind it -- and the sim
	# may not ask which clips were baked. So it sends `feeding` for every settled
	# animal and `AtlasEntry._ANIM_ALIAS` turns it back into `idle` for the five that
	# have none. Same rule the `attack` branch already documents for the villager.
	var cow := w.spawn_unit(&"unit.cattle", 0, Vector2i(30, 30))
	w.step()
	assert_eq(cow.anim, &"feeding")


func test_a_players_own_idle_unit_never_grazes() -> void:
	# The gate is gaia-plus-wildlife, and the gaia half is what keeps the cost off the
	# units there are thousands of. A villager standing still is idle, not feeding.
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	w.step()
	assert_eq(v.anim, &"idle")


## A deer that has been shot once and is bolting.
##
## THE STEP BEFORE THE DAMAGE IS LOAD-BEARING and cost this test its first run.
## `WildlifeSystem._check_flee` watches hp for a DROP rather than being told who hit
## what (it is handed a number and no attacker), so it needs a previous reading to
## compare against -- and `last_hp` starts at the -1 sentinel. Damage dealt before the
## animal has ever been looked at is the first reading, not a drop, and nothing bolts.
func _shot_deer() -> SimUnit:
	var deer := w.spawn_unit(&"unit.deer", 0, Vector2i(30, 30))
	w.step()
	deer.take_damage(1, 0)
	return deer


func test_a_bolting_animal_runs() -> void:
	# 6.1b: hurt an animal that flees and it bolts for FLEE_TICKS. Only the deer was
	# baked a run, which is why the sim sends one for all of them and the view resolves.
	var deer := _shot_deer()
	var ticks := _run_until(func(): return deer.flee_ticks > 0 and deer.has_waypoint())
	assert_true(ticks > 0, "it started a bolt and set off")
	assert_eq(deer.anim, &"run")


func test_an_animal_that_has_finished_its_bolt_stands_rather_than_running_on_the_spot() -> void:
	# `run` is gated on has_waypoint, not on flee_ticks: a burst that reaches the end
	# of its route leaves the animal standing with the counter still going down, and a
	# run clip playing under a stationary sprite is the classic sliding-feet artefact
	# in reverse.
	var deer := _shot_deer()
	var ticks := _run_until(func(): return deer.flee_ticks > 0 and not deer.has_waypoint() \
			and not deer.path_pending, 200)
	assert_true(ticks > 0, "the bolt reached the end of its route with the counter still running")
	assert_ne(deer.anim, &"run", "arrived, so it is standing")


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
