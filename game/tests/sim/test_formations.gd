## Phase 4.14: a group ordered somewhere arranging itself instead of piling onto one tile.
##
## `Formation` is pure integer arithmetic over a list, so nearly all of this is assertable
## without a world -- the same property `SelectionActions`'s tests lean on. Three things
## carry the weight:
##
##   - **Distinct slots.** Two units sent to one tile is a pair that shoves each other
##     for the rest of the match. Every shape is swept for duplicates at every count from
##     1 to 24, because the integer-halving that centres a rank is exactly the sort of
##     arithmetic that collides on even numbers and looks fine on odd ones.
##   - **Determinism.** The tiles go into `PathService`, whose answers ride `state_hash`.
##     The assignment must not depend on the order `unit_ids` happens to arrive in, which
##     a client's selection genuinely can vary.
##   - **Nothing changed for anybody who did not ask.** Every existing caller -- the AI,
##     the minimap, `send_to_waypoint`, every other test in this suite -- issues a
##     `MoveCommand` with no formation, and must keep getting one destination for all.
extends TestCase

var w: SimWorld


func before_each() -> void:
	w = SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.map_size = Vector2i(64, 64)
	w.setup(cfg)
	w.map.fill_terrain(SimMap.Terrain.GRASS)


## `n` units in a row well to the west, so every shape is ordered along a clear axis.
func _squad(n: int, at: Vector2i = Vector2i(10, 30)) -> Array[int]:
	var ids: Array[int] = []
	for i in range(n):
		ids.append(w.spawn_unit(&"unit.militia", 1, at + Vector2i(0, i)).id)
	return ids


func _tiles_of(ids: Array[int]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for id in ids:
		out.append((w.get_entity(id) as SimUnit).tile())
	return out


# ── the shapes ──────────────────────────────────────────────────────────────

func test_no_formation_sends_everybody_to_the_one_tile() -> void:
	var tiles: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3)]
	var out := Formation.destinations(Formation.NONE, Vector2i(20, 20), tiles, [1, 2, 3])
	assert_eq(out, [Vector2i(20, 20), Vector2i(20, 20), Vector2i(20, 20)],
			"which is what a move order has always done, and what every existing "
			+ "caller gets by not saying anything")


func test_an_unknown_shape_behaves_as_none_rather_than_crashing() -> void:
	# `MoveCommand.validate` refuses one before it ever reaches here, so this is the
	# belt to that brace: the helper is public and static, and a caller that skipped
	# validation must not get a broken array back.
	var tiles: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 2)]
	var out := Formation.destinations(&"phalanx", Vector2i(20, 20), tiles, [1, 2])
	assert_eq(out.size(), 2)
	assert_eq(out[0], Vector2i(20, 20))


func test_one_unit_ignores_the_shape_it_was_given() -> void:
	var out := Formation.destinations(Formation.LINE, Vector2i(20, 20),
			[Vector2i(5, 5)] as Array[Vector2i], [7])
	assert_eq(out, [Vector2i(20, 20)],
			"a lone soldier in a line is a soldier, and the panel offering formations "
			+ "on a single military unit relies on this being harmless")


func test_every_shape_gives_every_unit_its_own_tile() -> void:
	# The sweep that catches integer-halving collisions. It runs every shape at every
	# count from 1 to 24 -- a formation of 24 is more than a player will usually select
	# and well past the point where the arithmetic stops being obvious.
	for shape in Formation.SHAPES:
		for n in range(1, 25):
			var tiles: Array[Vector2i] = []
			var ids: Array[int] = []
			for i in range(n):
				tiles.append(Vector2i(3, i))
				ids.append(i + 1)
			var out := Formation.destinations(shape, Vector2i(30, 30), tiles, ids)
			assert_eq(out.size(), n, "%s at n=%d lost somebody" % [shape, n])
			var seen := {}
			for t in out:
				assert_false(seen.has(t),
						"%s at n=%d put two units on %s" % [shape, n, t])
				seen[t] = true


func test_a_line_forms_across_the_direction_of_travel() -> void:
	# The whole point of a line: every unit reaches the enemy at the same moment, which
	# needs the rank perpendicular to the march and not strung out along it.
	var tiles: Array[Vector2i] = []
	var ids: Array[int] = []
	for i in range(5):
		tiles.append(Vector2i(10, 30))
		ids.append(i + 1)
	# Walking due EAST, so the rank must vary in y and share one x.
	var out := Formation.destinations(Formation.LINE, Vector2i(40, 30), tiles, ids)
	var xs := {}
	var ys := {}
	for t in out:
		xs[t.x] = true
		ys[t.y] = true
	assert_eq(xs.size(), 1, "one column of x -- the rank is across the march")
	assert_eq(ys.size(), 5)


func test_a_grid_is_as_square_as_the_count_allows() -> void:
	var tiles: Array[Vector2i] = []
	var ids: Array[int] = []
	for i in range(12):
		tiles.append(Vector2i(10, 30 + i))
		ids.append(i + 1)
	var out := Formation.destinations(Formation.GRID, Vector2i(40, 30), tiles, ids)
	var xs := {}
	var ys := {}
	for t in out:
		xs[t.x] = true
		ys[t.y] = true
	# 12 units want 4 columns (ceil(sqrt(12)) == 4) and therefore 3 rows.
	assert_eq(ys.size(), 4, "four across")
	assert_eq(xs.size(), 3, "three deep")


func test_a_box_is_hollow() -> void:
	# The shape for escorting something: the middle is deliberately empty, so a trebuchet
	# ordered to the same tile ends up inside the ring rather than displacing a soldier.
	var tiles: Array[Vector2i] = []
	var ids: Array[int] = []
	for i in range(12):
		tiles.append(Vector2i(10, 30 + i))
		ids.append(i + 1)
	var out := Formation.destinations(Formation.BOX, Vector2i(40, 30), tiles, ids)
	assert_eq(out.size(), 12)
	# 12 units make a 4x4 ring, whose perimeter is exactly 12 -- so the two interior
	# tiles of each axis must be unoccupied.
	var occupied := {}
	for t in out:
		occupied[t] = true
	var minx := 1 << 30
	var maxx := -(1 << 30)
	var miny := 1 << 30
	var maxy := -(1 << 30)
	for t in out:
		minx = mini(minx, t.x)
		maxx = maxi(maxx, t.x)
		miny = mini(miny, t.y)
		maxy = maxi(maxy, t.y)
	var interior := 0
	for x in range(minx + 1, maxx):
		for y in range(miny + 1, maxy):
			if occupied.has(Vector2i(x, y)):
				interior += 1
	assert_eq(interior, 0, "a box with somebody standing in it is a grid")


func test_a_box_of_three_falls_back_to_a_line() -> void:
	var tiles: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3)]
	var box := Formation.destinations(Formation.BOX, Vector2i(30, 30), tiles, [1, 2, 3])
	var line := Formation.destinations(Formation.LINE, Vector2i(30, 30), tiles, [1, 2, 3])
	assert_eq(box, line, "three soldiers in a 'box' is three soldiers standing in a corner")


func test_a_vee_puts_one_unit_at_the_point() -> void:
	var tiles: Array[Vector2i] = []
	var ids: Array[int] = []
	for i in range(7):
		tiles.append(Vector2i(10, 30 + i))
		ids.append(i + 1)
	var out := Formation.destinations(Formation.VEE, Vector2i(40, 30), tiles, ids)
	# Marching east, the apex is the easternmost tile and there is exactly one of it.
	var furthest := -(1 << 30)
	for t in out:
		furthest = maxi(furthest, t.x)
	var at_point := 0
	for t in out:
		if t.x == furthest:
			at_point += 1
	assert_eq(at_point, 1, "a wedge has a point")


func test_the_anchor_tile_is_inside_the_shape() -> void:
	# The formation forms ON the order rather than short of it: a player who taps a spot
	# expects the group to arrive there, not near there.
	for shape in Formation.SHAPES:
		var tiles: Array[Vector2i] = []
		var ids: Array[int] = []
		for i in range(6):
			tiles.append(Vector2i(10, 30 + i))
			ids.append(i + 1)
		var out := Formation.destinations(shape, Vector2i(40, 30), tiles, ids)
		var near := 1 << 30
		for t in out:
			near = mini(near, maxi(absi(t.x - 40), absi(t.y - 30)))
		assert_true(near <= 2, "%s formed up %d tiles from where it was told" % [shape, near])


# ── determinism ─────────────────────────────────────────────────────────────

func test_the_assignment_does_not_depend_on_the_order_the_ids_arrive_in() -> void:
	# A client's selection is built from `units_in_box` and a tap history, so two hosts
	# can legitimately hold the same SET in a different order. If that changed who walked
	# where, the two would path differently and the match would diverge on the first
	# group move.
	var tiles_a: Array[Vector2i] = [Vector2i(10, 30), Vector2i(10, 31), Vector2i(10, 32)]
	var ids_a: Array[int] = [5, 9, 2]
	var out_a := Formation.destinations(Formation.GRID, Vector2i(40, 30), tiles_a, ids_a)

	var tiles_b: Array[Vector2i] = [Vector2i(10, 32), Vector2i(10, 30), Vector2i(10, 31)]
	var ids_b: Array[int] = [2, 5, 9]
	var out_b := Formation.destinations(Formation.GRID, Vector2i(40, 30), tiles_b, ids_b)

	# Same unit, same destination, whichever position it held in the array.
	assert_eq(out_a[0], out_b[1], "unit 5")
	assert_eq(out_a[1], out_b[2], "unit 9")
	assert_eq(out_a[2], out_b[0], "unit 2")


func test_two_units_on_the_same_tile_are_ordered_by_id() -> void:
	# Position alone cannot rank them, and something must: without the id tie-break the
	# sort's behaviour on equal keys is what decides, and that is not documented.
	var tiles: Array[Vector2i] = [Vector2i(10, 30), Vector2i(10, 30)]
	var first := Formation.destinations(Formation.LINE, Vector2i(40, 30), tiles, [4, 8])
	var second := Formation.destinations(Formation.LINE, Vector2i(40, 30), tiles, [4, 8])
	assert_eq(first, second)
	assert_ne(first[0], first[1])


func test_the_left_of_the_group_ends_up_on_the_left() -> void:
	# The half that makes it look right rather than merely be correct: handing out slots
	# in id order marches the army through itself.
	var tiles: Array[Vector2i] = [Vector2i(10, 34), Vector2i(10, 30)]
	# The unit at y 30 has the HIGHER id, so id order and position order disagree.
	var out := Formation.destinations(Formation.LINE, Vector2i(40, 32), tiles, [1, 9])
	assert_true(out[0].y > out[1].y,
			"whoever started further along the rank stays further along it")


# ── the command ─────────────────────────────────────────────────────────────

func test_a_formation_move_gives_each_unit_its_own_destination() -> void:
	var ids := _squad(4)
	var c := MoveCommand.new(1, ids, Vector2i(40, 30), 0, Formation.LINE)
	assert_true(c.validate(w))
	c.apply(w)

	var seen := {}
	for id in ids:
		var t := (w.get_entity(id) as SimUnit).task_target_tile
		assert_false(seen.has(t))
		seen[t] = true
	assert_eq(seen.size(), 4)


func test_a_plain_move_still_sends_everybody_to_one_tile() -> void:
	var ids := _squad(4)
	MoveCommand.new(1, ids, Vector2i(40, 30)).apply(w)
	for id in ids:
		assert_eq((w.get_entity(id) as SimUnit).task_target_tile, Vector2i(40, 30))


func test_the_command_refuses_a_shape_it_does_not_know() -> void:
	var ids := _squad(2)
	assert_false(MoveCommand.new(1, ids, Vector2i(40, 30), 0, &"phalanx").validate(w),
			"falling back to NONE would leave a client and a server disagreeing about "
			+ "where an army is walking, and would hide the version skew that caused it")


func test_every_named_shape_is_accepted() -> void:
	var ids := _squad(2)
	for shape in Formation.SHAPES:
		assert_true(MoveCommand.new(1, ids, Vector2i(40, 30), 0, shape).validate(w),
				"%s is offered by the panel and must be accepted by the server" % shape)


func test_the_panel_and_the_sim_cannot_disagree_about_which_shapes_exist() -> void:
	# `SelectionActions.FORMATIONS` IS `Formation.SHAPES` rather than a second list. This
	# pins that they are the same object, because a menu offering a fifth shape the
	# server refuses is a button that silently does nothing.
	assert_eq(SelectionActions.FORMATIONS, Formation.SHAPES)


func test_the_wire_form_round_trips_and_omits_the_common_case() -> void:
	var plain := MoveCommand.new(1, [4], Vector2i(3, 3)).to_dict()
	assert_false(plain.has("formation"),
			"every AI order and every minimap tap is formationless -- the key is not "
			+ "worth a byte on any of them")

	var c := MoveCommand.new(1, [4, 5], Vector2i(3, 3), 9, Formation.VEE)
	var back := Command.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	assert_true(back is MoveCommand)
	assert_eq((back as MoveCommand).formation, Formation.VEE)
	assert_eq((back as MoveCommand).target_tile, Vector2i(3, 3))


func test_a_squad_ordered_in_formation_actually_walks_there() -> void:
	# The end-to-end one. Everything above is arithmetic; this is the check that the
	# tiles are reachable ground and that `PathService` accepts them.
	var ids := _squad(5, Vector2i(12, 30))
	w.queue_command(MoveCommand.new(1, ids, Vector2i(30, 30), 0, Formation.LINE))
	for i in range(400):
		w.step()

	var seen := {}
	for id in ids:
		var u := w.get_entity(id) as SimUnit
		assert_eq(u.task, SimUnit.Task.IDLE, "everybody arrived and stood down")
		seen[u.tile()] = true
	assert_eq(seen.size(), 5, "and no two ended up on the same tile")
