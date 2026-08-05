## Phase 0.6: pooling and interpolation, tested without a live scene tree --
## advance() and advance_all() are called directly rather than relying on a
## running _process, same pattern as SimClock (PLAN.md 7.7).
extends TestCase

var pool: EntityViewPool


func before_each() -> void:
	pool = EntityViewPool.new()


func after_each() -> void:
	pool.free()


func test_acquire_creates_a_view_and_is_idempotent_for_the_same_id() -> void:
	var a := pool.acquire(1, &"vis.villager")
	var b := pool.acquire(1, &"vis.villager")
	assert_eq(a, b, "acquiring the same id twice returns the same view")
	assert_eq(pool.get_view(1), a)


func test_release_then_acquire_reuses_the_freed_node_instead_of_making_a_new_one() -> void:
	var first := pool.acquire(1, &"vis.villager")
	pool.release(1)
	assert_null(pool.get_view(1))
	var second := pool.acquire(2, &"vis.villager")
	assert_eq(first, second, "released view is recycled for the next acquire")
	assert_true(second.visible)


func test_advance_all_interpolates_toward_the_target_over_one_tick() -> void:
	var view := pool.acquire(1, &"vis.villager")
	view.position = Vector2.ZERO
	view.set_target_transform(Vector2(100, 0), 1)

	pool.advance_all(EntityView.INTERP_SECONDS / 2.0)
	assert_almost_eq(view.position.x, 50.0, 0.5, "halfway through the tick, halfway to the target")

	pool.advance_all(EntityView.INTERP_SECONDS / 2.0)
	assert_almost_eq(view.position.x, 100.0, 0.01, "fully arrived by the end of the tick")

	pool.advance_all(1.0)
	assert_almost_eq(view.position.x, 100.0, 0.01, "does not overshoot once arrived")
