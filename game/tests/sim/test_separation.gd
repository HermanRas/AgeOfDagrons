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
