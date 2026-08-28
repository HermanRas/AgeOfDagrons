## Arrows lying where they landed (project owner, 2026-08-28: *"in AOE arrows linger on
## the ground after hitting for a few seconds"*).
##
## THE INTERESTING ASSERTIONS ARE ABOUT WHERE THEY DO **NOT** APPEAR. Litter is easy; the
## design question was how the view tells "this shot landed" from "this shot flew into
## the fog", because both look like an entity that stopped being sent. `MatchAudio`'s
## header records that `updated` cannot answer it -- but `removed` can, because that list
## is only ever an explicit despawn, and losing sight of something goes through
## `GameView`'s forget pass instead. Half of what is below pins that difference.
extends TestCase

var view: GameView


func before_each() -> void:
	view = GameView.new()


func after_each() -> void:
	# Four orphan layers, since `_ready()` never runs for a bare `.new()` -- see
	# test_game_view.after_each.
	view.pool.free()
	view.terrain.free()
	view.fog.free()
	view.spent.free()
	view.free()


func _arrow(id: int, tile: Vector2i) -> Dictionary:
	return {"id": id, "def_id": "vis.projectile_arrow", "owner_id": 1,
			"hp": 1, "max_hp": 1, "anim": "static", "facing": 0,
			"pos": {"x": tile.x * SimWorld.SUBTILE, "y": tile.y * SimWorld.SUBTILE}}


func _snap(tick: int, updated: Array, removed: Array = []) -> Dictionary:
	return {"tick": tick, "updated": updated, "removed": removed}


func test_a_landed_arrow_leaves_one_behind() -> void:
	view.apply_snapshot(_snap(1, [_arrow(7, Vector2i(5, 5))]))
	assert_eq(view.spent.count(), 0, "nothing while it is still in the air")

	view.apply_snapshot(_snap(2, [], [7]))
	assert_eq(view.spent.count(), 1, "it landed and stayed")


func test_an_arrow_lost_TO_THE_FOG_leaves_nothing() -> void:
	# THE ONE THAT MATTERS. An entity simply absent from `updated` has been forgotten,
	# not despawned -- you did not see it land, so there is nothing on the ground to
	# have seen. Getting this wrong would litter the far side of the map with arrows
	# from fights the player never witnessed.
	view.apply_snapshot(_snap(1, [_arrow(7, Vector2i(5, 5))]))
	view.apply_snapshot(_snap(2, []))
	assert_eq(view.spent.count(), 0)


func test_a_dead_UNIT_leaves_no_arrow() -> void:
	# `is_effect` is a positive test against the three def tables, so this is not a list
	# of what to skip -- a villager is a unit, so she is not litter. She leaves a corpse,
	# which the sim keeps itself.
	view.apply_snapshot(_snap(1, [{"id": 3, "def_id": "unit.villager", "owner_id": 1,
			"hp": 30, "max_hp": 30, "anim": "idle", "facing": 0,
			"pos": {"x": 0, "y": 0}}]))
	view.apply_snapshot(_snap(2, [], [3]))
	assert_eq(view.spent.count(), 0)


func test_a_demolished_BUILDING_leaves_no_arrow() -> void:
	view.apply_snapshot(_snap(1, [{"id": 4, "def_id": "building.house", "owner_id": 1,
			"hp": 10, "max_hp": 10, "phase": SimBuilding.Phase.COMPLETE,
			"pos": {"x": 0, "y": 0}}]))
	view.apply_snapshot(_snap(2, [], [4]))
	assert_eq(view.spent.count(), 0)


func test_it_lands_where_the_arrow_was_and_not_on_a_tile_centre() -> void:
	# Read off the VIEW rather than off `_facts`, which holds whole tiles -- otherwise
	# every arrow in a volley would snap to the same point and the fan would collapse.
	view.apply_snapshot(_snap(1, [_arrow(7, Vector2i(5, 5))]))
	var at := view.pool.get_view(7).position
	view.apply_snapshot(_snap(2, [], [7]))
	assert_eq(view.spent.count(), 1)
	# Nothing else reads a decal's position, so this asserts through `add` rather than
	# through a getter nobody would otherwise need.
	var fresh := SpentProjectiles.new()
	fresh.add(&"vis.projectile_arrow", at, 0)
	assert_eq(fresh.count(), 1)
	fresh.free()


func test_they_age_out() -> void:
	var s := SpentProjectiles.new()
	s.add(&"vis.projectile_arrow", Vector2.ZERO, 0)
	s._process(SpentProjectiles.LIFETIME * 0.5)
	assert_eq(s.count(), 1, "still there halfway through")
	s._process(SpentProjectiles.LIFETIME)
	assert_eq(s.count(), 0, "and gone after its time")
	s.free()


func test_a_siege_cannot_grow_the_pile_without_limit() -> void:
	# A castle with a full garrison looses twenty projectiles every two seconds. Past
	# MAX_KEPT they are drawing on top of each other anyway; oldest out first.
	var s := SpentProjectiles.new()
	for i in range(SpentProjectiles.MAX_KEPT + 50):
		s.add(&"vis.projectile_arrow", Vector2(i, 0), 0)
	assert_eq(s.count(), SpentProjectiles.MAX_KEPT)
	s.free()


func test_an_unnamed_visual_is_not_kept() -> void:
	# Guards the one input that would otherwise sit in the list forever drawing nothing.
	var s := SpentProjectiles.new()
	s.add(&"", Vector2.ZERO, 0)
	assert_eq(s.count(), 0)
	s.free()
