## Phase 0.6: apply_snapshot() is the only thing standing between a wire
## Dictionary (PLAN.md 7.2) and pooled views -- test it directly rather than
## the JSON snapshot format.
extends TestCase

var view: GameView


func before_each() -> void:
	view = GameView.new()


func after_each() -> void:
	# _ready() (which parents pool under view) only runs once a node enters a
	# tree, which never happens for a bare .new() in a headless test -- so
	# pool is a separate orphan and must be freed on its own.
	view.pool.free()
	view.free()


func test_apply_snapshot_acquires_a_view_at_the_projected_position() -> void:
	var sub_pos := Vector2i(3, 3) * SimWorld.SUBTILE
	view.apply_snapshot({
		"tick": 1,
		"updated": [{"id": 7, "def_id": "unit.villager", "pos": {"x": sub_pos.x, "y": sub_pos.y},
				"hp": 30, "max_hp": 30}],
		"removed": [],
	})
	var v := view.pool.get_view(7)
	assert_not_null(v)
	v.advance(EntityView.INTERP_SECONDS)          # land on the target for a clean assert
	assert_eq(v.position, Iso.sub_to_world(sub_pos))
	assert_almost_eq(v.health_pct, 1.0, 0.001)


func test_apply_snapshot_removed_releases_the_view() -> void:
	view.apply_snapshot({"tick": 1, "updated": [{"id": 9, "pos": {"x": 0, "y": 0}}], "removed": []})
	assert_not_null(view.pool.get_view(9))

	view.apply_snapshot({"tick": 2, "updated": [], "removed": [9]})
	assert_null(view.pool.get_view(9))


func test_process_advances_the_pool() -> void:
	view.apply_snapshot({"tick": 1, "updated": [
		{"id": 1, "pos": {"x": 0, "y": 0}},
	], "removed": []})
	var v := view.pool.get_view(1)
	v.position = Vector2.ZERO
	v.set_target_transform(Vector2(40, 0), 2)

	view._process(EntityView.INTERP_SECONDS)
	assert_almost_eq(v.position.x, 40.0, 0.01)
