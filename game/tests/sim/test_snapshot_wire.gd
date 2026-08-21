## The packed wire form of a snapshot (PLAN.md 12.1f).
##
## Half of every entity entry was the names of its own fields, re-encoded per entity per
## tick -- 248 bytes of a town centre's 472. Entities come in a handful of shapes, so the
## names go once per shape instead of once per entity.
##
## THE PROPERTY THAT MATTERS IS THAT NOTHING IS LOST. A packing that dropped a field, or
## mixed two entities' values, would show up as a unit drawn with somebody else's hp or a
## building with no phase -- and it would show up on the client only, which is the hardest
## place to look. So the round trip is asserted whole, against real snapshots, rather than
## by checking that the packed form is smaller.
extends TestCase

var world: SimWorld


func before_each() -> void:
	var cfg := MatchConfig.debug_skirmish()
	world = SimWorld.new()
	world.setup(cfg)
	MapGen.build(world, cfg)
	world.step()


func test_the_round_trip_returns_exactly_what_went_in() -> void:
	var snap := SnapshotSystem.build(world, 1)
	var back := SnapshotSystem.from_wire(SnapshotSystem.to_wire(snap))

	assert_eq(back.get("tick"), snap.get("tick"))
	assert_eq(back.get("removed"), snap.get("removed"))
	assert_eq(back.get("player_state"), snap.get("player_state"))
	assert_eq(back.get("match_over"), snap.get("match_over"))
	assert_eq(back.get("winner_id"), snap.get("winner_id"))
	assert_eq(back.get("mode"), snap.get("mode"))

	var before: Array = snap["updated"]
	var after: Array = back["updated"]
	assert_eq(after.size(), before.size(), "every entity came back")
	assert_true(before.size() > 0, "there were entities to lose")

	# BY ID, not by position: the packing groups entries by shape, so their order changes
	# and nothing downstream should care -- but every entity must come back with exactly
	# its own fields and values.
	var by_id: Dictionary = {}
	for e in after:
		by_id[int(e["id"])] = e
	for original in before:
		var id := int(original["id"])
		assert_true(by_id.has(id), "entity %d survived" % id)
		var copy: Dictionary = by_id[id]
		assert_eq(copy.size(), (original as Dictionary).size(),
				"entity %d kept all %d fields" % [id, (original as Dictionary).size()])
		for k in original:
			assert_eq(copy.get(k), original[k], "entity %d field %s" % [id, k])


func test_entities_of_one_shape_share_one_table() -> void:
	# The saving itself: the field names are paid per TABLE. If every entity landed in its
	# own table this would encode the same bytes as before, only less readably.
	var wire := SnapshotSystem.to_wire(SnapshotSystem.build(world, 1))
	var tables: Array = wire["tables"]
	var rows := 0
	for t in tables:
		rows += (t["rows"] as Array).size()

	assert_true(tables.size() >= 1, "there is at least one shape")
	assert_true(rows > tables.size(),
			"%d entities packed into %d tables, so names are shared" % [rows, tables.size()])


func test_the_packed_form_is_smaller_than_the_readable_one() -> void:
	var snap := SnapshotSystem.build(world, 1)
	var loose := var_to_bytes(snap).size()
	var packed := var_to_bytes(SnapshotSystem.to_wire(snap)).size()
	assert_true(packed < loose, "packed %d vs loose %d bytes" % [packed, loose])


func test_a_snapshot_that_was_never_packed_passes_through() -> void:
	# A test or a preview handing a snapshot straight to `snapshot_received`, without the
	# transport in between.
	var plain := {"tick": 5, "updated": [{"id": 1, "def_id": &"unit.villager"}], "removed": []}
	var out := SnapshotSystem.from_wire(plain)
	assert_eq(out, plain, "unchanged, not emptied")


func test_packing_something_already_packed_leaves_it_alone() -> void:
	var wire := SnapshotSystem.to_wire(SnapshotSystem.build(world, 1))
	assert_eq(SnapshotSystem.to_wire(wire), wire)


func test_an_empty_snapshot_survives_both_ways() -> void:
	# Reachable on the first tick of a world nobody can see anything in.
	var empty := {"tick": 1, "updated": [] as Array[Dictionary], "removed": []}
	var wire := SnapshotSystem.to_wire(empty)
	assert_eq((wire["tables"] as Array).size(), 0, "no shapes, no tables")
	assert_eq((SnapshotSystem.from_wire(wire)["updated"] as Array).size(), 0)


func test_two_shapes_do_not_bleed_into_each_other() -> void:
	# The failure this would cause is a unit drawn with a building's fields. Built by hand
	# so the two shapes are unmistakable.
	var snap := {"tick": 1, "removed": [], "updated": [
		{"id": 1, "hp": 10},
		{"id": 2, "hp": 20, "phase": 2},
		{"id": 3, "hp": 30},
	]}
	var back := SnapshotSystem.from_wire(SnapshotSystem.to_wire(snap))
	var by_id: Dictionary = {}
	for e in back["updated"]:
		by_id[int(e["id"])] = e

	assert_false((by_id[1] as Dictionary).has("phase"), "a shape without phase gained none")
	assert_eq(int((by_id[2] as Dictionary)["phase"]), 2)
	assert_eq(int((by_id[3] as Dictionary)["hp"]), 30)
	assert_eq((by_id[1] as Dictionary).size(), 2)
