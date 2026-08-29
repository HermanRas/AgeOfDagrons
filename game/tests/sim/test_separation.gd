## Phase 4.2: units no longer stack on or walk through each other.
##
## Driven through the real `SimWorld.step()`, same reasoning as test_movement.gd
## -- the part worth testing is SeparationSystem's place in the tick order
## relative to MovementSystem and TaskSystem, not the push maths in isolation.
extends TestCase

var w: SimWorld


func before_each() -> void:
	w = SimWorld.new()
	w.setup(MatchConfig.debug_single_player())


func _dist(a: SimUnit, b: SimUnit) -> float:
	return Vector2(a.pos - b.pos).length()


# ── overlap is resolved ────────────────────────────────────────────────────

func test_two_units_spawned_on_the_same_tile_are_pushed_apart() -> void:
	var a := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	var b := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	assert_eq(a.pos, b.pos, "start exactly coincident")

	w.step()
	assert_true(_dist(a, b) > 0.0, "no longer sharing the same spot")


func test_pushed_apart_units_settle_rather_than_oscillating_forever() -> void:
	var a := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	var b := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))

	for i in range(20):
		w.step()
	var settled := _dist(a, b)
	w.step()
	assert_almost_eq(_dist(a, b), settled, 1.0, "separated and staying separated")
	assert_true(settled >= SeparationSystem.MIN_SEPARATION - 1.0,
			"pushed at least to the minimum separation")


# ── units crossing paths do not end up sharing a tile ──────────────────────

func test_two_units_swapping_places_never_end_up_exactly_coincident() -> void:
	var a := w.spawn_unit(&"unit.villager", 1, Vector2i(10, 20))
	var b := w.spawn_unit(&"unit.villager", 1, Vector2i(30, 20))
	w.queue_command(MoveCommand.new(1, [a.id], Vector2i(30, 20)))
	w.queue_command(MoveCommand.new(1, [b.id], Vector2i(10, 20)))

	for i in range(200):
		w.step()
		if a.alive and b.alive:
			assert_false(a.pos == b.pos and a.tile() == b.tile(),
					"tick %d: standing in the exact same spot" % i)
		if a.is_idle() and b.is_idle():
			break


# ── does not strand an arrival (task_system.gd's tile-based check) ─────────

func test_a_unit_still_goes_idle_when_a_push_lands_on_its_arrival_tick() -> void:
	# A neighbour parked exactly on the destination tile guarantees a push the
	# instant the ordered unit arrives -- the case that would starve forever
	# under an exact sub-position arrival check.
	var mover := w.spawn_unit(&"unit.villager", 1, Vector2i(10, 10))
	w.spawn_unit(&"unit.villager", 1, Vector2i(15, 15))
	w.queue_command(MoveCommand.new(1, [mover.id], Vector2i(15, 15)))

	var arrived := false
	for i in range(200):
		w.step()
		if mover.is_idle():
			arrived = true
			break
	assert_true(arrived, "retired instead of sitting in MOVE forever")


# ── never pushed into an obstacle ───────────────────────────────────────────

func test_a_push_never_shoves_a_unit_onto_impassable_ground() -> void:
	w.map.set_terrain(Vector2i(21, 20), SimMap.Terrain.ROCK)
	w.paths.mark_dirty()
	var a := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	var b := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))

	for i in range(20):
		w.step()
		assert_true(w.map.is_terrain_passable(a.tile()), "tick %d: a on solid ground" % i)
		assert_true(w.map.is_terrain_passable(b.tile()), "tick %d: b on solid ground" % i)


# ── who yields (owner report, 2026-08-29) ──────────────────────────────────

## "units path find through each other, pushing each other out of the way."
##
## The pushing half of that. A gatherer standing on her node is not moved by a
## soldier crossing the base: the walker owes the whole correction, because it is
## the one that chose to be there.
func test_a_walker_does_not_shove_a_unit_that_is_standing_still() -> void:
	var stander := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	var mover := w.spawn_unit(&"unit.villager", 1, Vector2i(14, 20))
	var stood_at := stander.pos
	w.queue_command(MoveCommand.new(1, [mover.id], Vector2i(26, 20)))

	for i in range(200):
		w.step()
		assert_eq(stander.pos, stood_at, "tick %d: shoved off the spot it was on" % i)
		if mover.is_idle():
			break
	assert_true(mover.is_idle(), "and the walker still got where it was sent")


## The walker goes AROUND, not backwards. A push straight down the line between the
## two would shove it back along the path it is about to re-walk, and it would jitter
## against the stander for as long as the order stood.
func test_a_walker_makes_ground_past_a_unit_parked_on_its_route() -> void:
	var mover := w.spawn_unit(&"unit.villager", 1, Vector2i(14, 20))
	w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	w.queue_command(MoveCommand.new(1, [mover.id], Vector2i(26, 20)))

	# Nowhere near the tick count the walk itself needs -- a bounce would spend all
	# of them oscillating at x = 19.
	var reached := 0
	for i in range(200):
		w.step()
		reached = maxi(reached, mover.tile().x)
		if mover.is_idle():
			break
	assert_true(reached >= 26, "got past, reaching x = %d" % reached)


## And the both-standing case is still symmetric, which is load-bearing: a barracks
## emptying its queue puts several units on one tile (`SimWorld.find_free_adjacent`)
## and nothing else would ever part them.
func test_two_units_standing_on_one_tile_both_give_way() -> void:
	var a := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	var b := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	var a_was := a.pos
	var b_was := b.pos

	w.step()
	assert_ne(a.pos, a_was, "neither of two standers is the immovable one")
	assert_ne(b.pos, b_was, "and nor is the other")


## A garrisoned unit is not on the map (4.8) and its `pos` is a ghost of wherever it
## last stood. It must not push what is standing there now.
func test_a_garrisoned_unit_pushes_nobody() -> void:
	var inside := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	var outside := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	# Straight onto the field rather than through GarrisonCommand: what is under test
	# is that this system reads it, not how a unit comes to be inside something.
	inside.garrisoned_in = 999
	var stood_at := outside.pos

	for i in range(10):
		w.step()
	assert_eq(outside.pos, stood_at, "left exactly where it was standing")


# ── determinism (7.1) ───────────────────────────────────────────────────────

func test_two_worlds_with_overlapping_units_stay_identical() -> void:
	var other := SimWorld.new()
	other.setup(MatchConfig.debug_single_player())

	var tiles := [Vector2i(20, 20), Vector2i(20, 20), Vector2i(21, 20), Vector2i(20, 21)]
	var ids: Array[int] = []
	for t in tiles:
		ids.append(w.spawn_unit(&"unit.villager", 1, t).id)
	for t in tiles:
		other.spawn_unit(&"unit.villager", 1, t)

	w.queue_command(MoveCommand.new(1, ids, Vector2i(25, 25)))
	other.queue_command(MoveCommand.new(1, ids, Vector2i(25, 25)))

	for i in range(60):
		w.step()
		other.step()
		assert_eq(w.state_hash(), other.state_hash(), "diverged on tick %d" % (i + 1))
