## Phase 0.6: proves the full loop -- host_solo() stands up a real ENet
## server on loopback, submit_command() RPCs up to CommandSystem, and the
## resulting tick is RPCed back down as a snapshot (PLAN.md 5.1, 6.1).
##
## Net is a shared autoload, so every test must leave() in after_each --
## otherwise the next test (in this file or another) finds the loopback
## port already bound.
extends TestCase


func after_each() -> void:
	Net.leave()


func test_host_solo_starts_a_server_as_player_1() -> void:
	var err := Net.host_solo()
	assert_eq(err, OK)
	assert_true(Net.is_server())
	assert_eq(Net.local_player_id(), 1)


func test_leave_tears_down_cleanly_so_hosting_again_works() -> void:
	Net.host_solo()
	Net.leave()
	assert_false(Net.is_server())

	var err := Net.host_solo()
	assert_eq(err, OK, "the loopback port must be free again after leave()")
	assert_true(Net.is_server())


func test_submit_command_reaches_the_world_and_a_snapshot_comes_back() -> void:
	Net.host_solo()
	var v := Net.host().world.spawn_unit(&"unit.villager", 1, Vector2i(2, 2))

	var snapshots: Array[Dictionary] = []
	Net.snapshot_received.connect(func(s: Dictionary) -> void: snapshots.append(s))

	Net.submit_command(MoveCommand.new(1, [v.id], Vector2i(10, 2)))
	for i in 80:
		SimClock.advance(0.1)

	assert_eq(v.tile(), Vector2i(10, 2), "command travelled Net -> CommandSystem -> MovementSystem")
	assert_false(snapshots.is_empty(), "each tick should have broadcast a snapshot back down")

	var last: Dictionary = snapshots.back()
	assert_eq(int(last.get("tick", 0)), 80)
	var found := false
	for entry in last.get("updated", []):
		if int(entry.get("id", 0)) == v.id:
			found = true
			assert_eq(int(entry.get("pos", {}).get("x", 0)), 10 * SimWorld.SUBTILE + SimWorld.SUBTILE / 2)
	assert_true(found, "the moved unit must appear in its own snapshot")
