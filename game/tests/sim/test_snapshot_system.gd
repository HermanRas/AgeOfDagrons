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


## What one tick actually costs on the wire, for the real debug map rather than a
## two-entity fixture. Measured through `var_to_bytes`, which is what Godot's RPC
## layer encodes a Dictionary with.
##
## THIS IS A BUDGET, not a fact about correctness, and it exists because 12.1a is
## about to put this on a phone's WiFi. `updated` is still every visible entity every
## tick rather than a delta against the last acknowledged one (7.2), so the number
## below is the whole world -- and since 2.5 it also carries the full 4096-byte fog
## grid, every tick, whether or not a single tile of it changed.
##
## 64 KB per tick is 640 KB/s at 10 Hz, which no phone link should be asked for. The
## ceiling is deliberately loose: what this catches is a field being added to
## `to_snapshot()` that multiplies the whole thing, not a byte here or there.
func test_one_tick_of_wire_traffic_stays_within_budget() -> void:
	var real := SimWorld.new()
	real.setup(MatchConfig.debug_skirmish())
	MapGen.build_debug_map(real)
	real.step()

	var size := var_to_bytes(SnapshotSystem.build(real, 1)).size()
	var vision := var_to_bytes(real.player_for(1).vision).size()
	print("        snapshot %d bytes/tick (%d of it fog) = %d KB/s at 10 Hz"
			% [size, vision, size * 10 / 1024])
	assert_true(size < 65536, "one tick is %d bytes" % size)
