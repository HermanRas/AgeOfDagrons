## PLAN.md 7.2's wire format, specifically the parts 4.7/5.5 depend on:
## `updated` must keep including a corpse/rubble while it still exists (so it
## can render and fade), and `removed` must now be a real list (SimWorld.
## removed_this_tick) rather than always empty, since DeathSystem gives
## despawn() something to actually report.
extends TestCase

var w: SimWorld


func before_each() -> void:
	w = SimWorld.new()
	w.setup(MatchConfig.debug_single_player())


func test_a_freshly_dead_unit_still_appears_in_updated() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	w.queue_command(DebugDestroyCommand.new(1, v.id))
	w.step()

	var snap := SnapshotSystem.build(w, 1)
	var ids: Array = []
	for e in snap["updated"]:
		ids.append(int(e["id"]))
	assert_true(ids.has(v.id), "a corpse still renders until its timer runs out")
	assert_true(snap["removed"].is_empty())


func test_a_fully_despawned_unit_is_reported_removed() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	w.despawn(v.id)

	var snap := SnapshotSystem.build(w, 1)
	assert_eq(snap["removed"], [v.id])
	for e in snap["updated"]:
		assert_ne(int(e["id"]), v.id, "gone, not just marked dead")


func test_removed_is_empty_again_the_following_tick() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	w.despawn(v.id)
	SnapshotSystem.build(w, 1)
	w.step()
	assert_true(SnapshotSystem.build(w, 1)["removed"].is_empty())
