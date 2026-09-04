## Phase 2.1: SimMap -- terrain, move cost, occupancy, passability by domain
## (PLAN.md 6.2).
##
## Two things here carry more weight than the rest. `find_free_adjacent()` must
## scan in a fixed order, because two clients spawning a unit from a building have
## to choose the same tile or the simulations diverge (PLAN.md 7.1) -- so it is
## asserted against an exact expected tile, not merely "some free tile". And the
## map has to be inside `state_hash()`, or clients disagreeing about where the
## walls are would still hash identically.
extends TestCase

var m: SimMap


func before_each() -> void:
	m = SimMap.create(Vector2i(10, 8))


# ── construction ───────────────────────────────────────────────────────────

func test_a_new_map_is_uniform_passable_grass() -> void:
	assert_eq(m.size, Vector2i(10, 8))
	assert_eq(m.terrain.size(), 80, "one entry per tile")
	assert_eq(m.occupancy.size(), 80)
	for y in range(8):
		for x in range(10):
			var t := Vector2i(x, y)
			assert_eq(m.terrain_at(t), SimMap.Terrain.GRASS, "%s is grass" % t)
			assert_true(m.is_passable(t), "%s is walkable" % t)
			assert_eq(m.occupant(t), 0, "%s starts free" % t)


func test_a_zero_sized_map_does_not_crash() -> void:
	var empty := SimMap.create(Vector2i.ZERO)
	assert_eq(empty.terrain.size(), 0)
	assert_false(empty.in_bounds(Vector2i.ZERO))
	assert_false(empty.is_passable(Vector2i.ZERO))


# ── bounds ─────────────────────────────────────────────────────────────────

func test_bounds_exclude_the_far_edge() -> void:
	assert_true(m.in_bounds(Vector2i(0, 0)))
	assert_true(m.in_bounds(Vector2i(9, 7)), "last valid tile")
	assert_false(m.in_bounds(Vector2i(10, 7)), "size.x is one past the end")
	assert_false(m.in_bounds(Vector2i(9, 8)))
	assert_false(m.in_bounds(Vector2i(-1, 0)))


func test_out_of_bounds_reads_as_a_wall_not_as_grass() -> void:
	# A pathfinder that read off-map tiles as default grass would happily route
	# units off the edge of the world.
	var outside := Vector2i(-1, -1)
	assert_eq(m.terrain_at(outside), SimMap.Terrain.ROCK)
	assert_eq(m.cost_at(outside), SimMap.IMPASSABLE)
	assert_false(m.is_passable(outside))
	assert_false(m.is_terrain_passable(outside))


# ── terrain and cost ───────────────────────────────────────────────────────

func test_setting_terrain_also_sets_its_movement_cost() -> void:
	# The two must never disagree, so terrain owns the default.
	var t := Vector2i(3, 3)
	m.set_terrain(t, SimMap.Terrain.SAND)
	assert_eq(m.terrain_at(t), SimMap.Terrain.SAND)
	assert_eq(m.cost_at(t), SimMap.TERRAIN_COST[SimMap.Terrain.SAND])
	assert_true(m.cost_at(t) > m.cost_at(Vector2i(0, 0)), "sand is slower than grass")


## Renamed from `..._to_everything` on 2026-09-04: it only ever checked LAND and WATER, and
## once AIR genuinely crossed them the old name was a claim the body did not make. **AIR is
## excluded on purpose here** -- see `test_air_crosses_everything...` below for that half and
## for why the rule was reversed.
func test_rock_and_forest_are_impassable_to_both_ground_domains() -> void:
	m.set_terrain(Vector2i(1, 1), SimMap.Terrain.ROCK)
	m.set_terrain(Vector2i(2, 1), SimMap.Terrain.FOREST)
	for t in [Vector2i(1, 1), Vector2i(2, 1)] as Array[Vector2i]:
		assert_eq(m.cost_at(t), SimMap.IMPASSABLE)
		for domain in [SimMap.Domain.LAND, SimMap.Domain.WATER] as Array[int]:
			assert_false(m.is_passable(t, domain), "%s blocks domain %d" % [t, domain])


func test_a_move_cost_override_survives_until_terrain_is_set_again() -> void:
	var t := Vector2i(4, 4)
	m.set_move_cost(t, 40)
	assert_eq(m.cost_at(t), 40, "override applies")
	m.set_terrain(t, SimMap.Terrain.DIRT)
	assert_eq(m.cost_at(t), SimMap.TERRAIN_COST[SimMap.Terrain.DIRT],
			"setting terrain resets the cost rather than keeping a stale override")


func test_set_terrain_rect_covers_exactly_the_rect() -> void:
	m.set_terrain_rect(Rect2i(2, 2, 3, 2), SimMap.Terrain.DIRT)
	assert_eq(m.terrain_at(Vector2i(2, 2)), SimMap.Terrain.DIRT, "top-left included")
	assert_eq(m.terrain_at(Vector2i(4, 3)), SimMap.Terrain.DIRT, "bottom-right included")
	assert_eq(m.terrain_at(Vector2i(5, 3)), SimMap.Terrain.GRASS, "one past is untouched")
	assert_eq(m.terrain_at(Vector2i(2, 4)), SimMap.Terrain.GRASS)


# ── domains ────────────────────────────────────────────────────────────────

func test_land_and_water_domains_exclude_each_other() -> void:
	var land := Vector2i(0, 0)
	var sea := Vector2i(5, 5)
	m.set_terrain(sea, SimMap.Terrain.WATER_DEEP)

	assert_true(m.is_passable(land, SimMap.Domain.LAND))
	assert_false(m.is_passable(land, SimMap.Domain.WATER), "a boat cannot sail on grass")
	assert_true(m.is_passable(sea, SimMap.Domain.WATER))
	assert_false(m.is_passable(sea, SimMap.Domain.LAND), "a villager cannot walk on deep water")


## ⚠️ **THIS TEST WAS REVERSED ON 2026-09-04, AND THE REVERSAL IS THE POINT.**
##
## It used to assert that air is stopped by ROCK, on the reasoning that *"IMPASSABLE still
## means impassable -- it is not a domain preference"*. That reading was consistent and it
## made `DOMAIN_TERRAIN[AIR]`, which lists rock and forest, dead weight: `is_terrain_passable`
## tested `move_cost` first, so the table's air row could never be reached.
##
## Nothing noticed for months because **the only air unit had `speed: 0`** and no path was
## ever asked for. The dragon moves now (13.x), and the question became live: FOREST is
## IMPASSABLE too, and forest plus buildings is most of what obstructs a real map — so a
## flyer stopped by both is a land unit with extra steps, and "over" is the only thing air
## has that land and water do not.
##
## So the domain now wins over the cost array for AIR, and occupancy does not apply to it at
## all. IMPASSABLE still means impassable for **land and water**, which is every other unit in
## the game — see the test above.
func test_air_crosses_everything_including_what_stops_the_ground_domains() -> void:
	m.set_terrain(Vector2i(1, 1), SimMap.Terrain.WATER_DEEP)
	m.set_terrain(Vector2i(2, 2), SimMap.Terrain.ROCK)
	m.set_terrain(Vector2i(3, 3), SimMap.Terrain.FOREST)
	assert_true(m.is_passable(Vector2i(1, 1), SimMap.Domain.AIR), "air crosses water")
	assert_true(m.is_passable(Vector2i(2, 2), SimMap.Domain.AIR), "and rock")
	assert_true(m.is_passable(Vector2i(3, 3), SimMap.Domain.AIR),
			"and forest, which is most of what obstructs a map")


## And it flies OVER things, not just over ground. A dragon that could cross a forest but not
## a town centre would still be walled in by a building line.
func test_air_ignores_what_is_standing_on_the_ground() -> void:
	m.set_occupied(Rect2i(6, 6, 4, 4), 99, true)
	assert_false(m.is_passable(Vector2i(7, 7), SimMap.Domain.LAND),
			"the building blocks the ground")
	assert_true(m.is_passable(Vector2i(7, 7), SimMap.Domain.AIR),
			"nothing in this game occupies the sky")


func test_domain_names_from_unit_defs_map_onto_the_enum() -> void:
	# UnitDef.domain is the string form out of units.json.
	assert_eq(SimMap.from_domain_name(&"land"), SimMap.Domain.LAND)
	assert_eq(SimMap.from_domain_name(&"water"), SimMap.Domain.WATER)
	assert_eq(SimMap.from_domain_name(&"air"), SimMap.Domain.AIR)
	assert_eq(SimMap.from_domain_name(&"nonsense"), SimMap.Domain.LAND,
			"an unknown domain walks rather than becoming unplaceable")


# ── occupancy ──────────────────────────────────────────────────────────────

func test_occupying_a_footprint_blocks_exactly_those_tiles() -> void:
	m.set_occupied(Rect2i(3, 2, 2, 3), 42)
	assert_eq(m.occupant(Vector2i(3, 2)), 42)
	assert_eq(m.occupant(Vector2i(4, 4)), 42, "bottom-right of the footprint")
	assert_eq(m.occupant(Vector2i(5, 2)), 0, "one column past is free")
	assert_eq(m.occupant(Vector2i(3, 5)), 0, "one row past is free")
	assert_false(m.is_passable(Vector2i(3, 2)), "an occupied tile is not walkable")


func test_occupancy_does_not_change_the_ground_underneath() -> void:
	# Placement validation asks "could anything ever stand here"; pathfinding asks
	# "can something stand here now". A building must not make its own tiles
	# permanently unbuildable-looking after it is destroyed.
	var t := Vector2i(1, 1)
	m.set_occupied(Rect2i(1, 1, 1, 1), 7)
	assert_false(m.is_passable(t))
	assert_true(m.is_terrain_passable(t), "the grass is still grass")
	m.clear_occupied(Rect2i(1, 1, 1, 1))
	assert_true(m.is_passable(t), "clearing restores it")


func test_clearing_by_entity_id_frees_every_tile_it_held() -> void:
	# 5.5 destroys an entity and knows its id, not necessarily the rect it was
	# placed with. Clearing by a remembered rect would leak tiles if the footprint
	# ever changed.
	m.set_occupied(Rect2i(0, 0, 2, 2), 9)
	m.set_occupied(Rect2i(6, 6, 2, 2), 11)
	m.clear_occupant(9)
	assert_eq(m.occupant(Vector2i(0, 0)), 0, "9 is gone")
	assert_eq(m.occupant(Vector2i(1, 1)), 0)
	assert_eq(m.occupant(Vector2i(6, 6)), 11, "11 is untouched")


func test_clearing_occupant_zero_is_a_no_op() -> void:
	# 0 means "free", so clearing it must not wipe the whole grid.
	m.set_occupied(Rect2i(0, 0, 2, 2), 5)
	m.clear_occupant(0)
	assert_eq(m.occupant(Vector2i(0, 0)), 5, "a real occupant survives")


# ── placement ──────────────────────────────────────────────────────────────

func test_a_building_needs_every_tile_of_its_footprint() -> void:
	assert_true(m.can_place_building(Rect2i(2, 2, 4, 4)))

	m.set_terrain(Vector2i(4, 4), SimMap.Terrain.WATER_DEEP)
	assert_false(m.can_place_building(Rect2i(2, 2, 4, 4)),
			"one bad tile in the middle invalidates the whole footprint")


func test_a_building_cannot_overlap_another_or_hang_off_the_map() -> void:
	m.set_occupied(Rect2i(0, 0, 2, 2), 1)
	assert_false(m.can_place_building(Rect2i(1, 1, 3, 3)), "overlaps an existing footprint")
	assert_false(m.can_place_building(Rect2i(8, 6, 4, 4)), "hangs off the edge")
	assert_false(m.can_place_building(Rect2i(2, 2, 0, 4)), "a zero-width footprint is not valid")


func test_an_eight_by_eight_town_centre_fits_the_measured_footprint() -> void:
	# buildings.json gives the town centre [8, 8] from the measured art (0.4), so
	# the map has to be able to accept one.
	var big := SimMap.create(Vector2i(20, 20))
	var rect := SimMap.footprint_rect(Vector2i(5, 5), Vector2i(8, 8))
	assert_eq(rect, Rect2i(5, 5, 8, 8))
	assert_true(big.can_place_building(rect))
	big.set_occupied(rect, 1)
	assert_eq(big.occupant(Vector2i(12, 12)), 1, "the far corner is claimed")
	assert_eq(big.occupant(Vector2i(13, 13)), 0, "and nothing beyond it")


func test_footprint_rect_anchors_at_the_top_left_and_never_collapses() -> void:
	assert_eq(SimMap.footprint_rect(Vector2i(2, 3), Vector2i(4, 4)), Rect2i(2, 3, 4, 4))
	assert_eq(SimMap.footprint_rect(Vector2i(0, 0), Vector2i.ZERO), Rect2i(0, 0, 1, 1),
			"a degenerate footprint still occupies its own tile")


# ── find_free_adjacent: determinism ────────────────────────────────────────

func test_free_adjacent_returns_a_specific_tile_not_just_any_tile() -> void:
	# Asserted exactly, because two clients must agree. The scan is top edge
	# left-to-right first, so a 2x2 building at (4,4) spawns at the top-left of
	# its surrounding ring.
	m.set_occupied(Rect2i(4, 4, 2, 2), 1)
	assert_eq(m.find_free_adjacent(Rect2i(4, 4, 2, 2)), Vector2i(3, 3),
			"top edge of the first ring, leftmost tile")


func test_free_adjacent_is_stable_across_repeated_calls() -> void:
	m.set_occupied(Rect2i(4, 4, 2, 2), 1)
	var first := m.find_free_adjacent(Rect2i(4, 4, 2, 2))
	for _i in range(5):
		assert_eq(m.find_free_adjacent(Rect2i(4, 4, 2, 2)), first,
				"the same question gets the same answer every time")


func test_free_adjacent_widens_past_a_blocked_ring() -> void:
	var big := SimMap.create(Vector2i(20, 20))
	big.set_occupied(Rect2i(9, 9, 2, 2), 1)
	# Wall in the entire first ring.
	big.set_terrain_rect(Rect2i(8, 8, 4, 4), SimMap.Terrain.ROCK)
	big.set_terrain_rect(Rect2i(9, 9, 2, 2), SimMap.Terrain.GRASS)
	var found := big.find_free_adjacent(Rect2i(9, 9, 2, 2))
	assert_true(found.x >= 0, "found something in a wider ring")
	assert_true(big.is_passable(found), "and it is actually free")
	assert_true(found.x < 8 or found.x > 11 or found.y < 8 or found.y > 11,
			"outside the walled first ring")


func test_free_adjacent_reports_failure_when_walled_in() -> void:
	var tiny := SimMap.create(Vector2i(3, 3), SimMap.Terrain.ROCK)
	assert_eq(tiny.find_free_adjacent(Rect2i(1, 1, 1, 1)), Vector2i(-1, -1),
			"no free tile anywhere returns (-1, -1) rather than a bogus tile")


func test_free_adjacent_respects_domain() -> void:
	# Open ocean with no land at all -- note the search widens over the WHOLE map,
	# so a single grass tile anywhere would legitimately be found and this would
	# be testing nothing.
	var sea := SimMap.create(Vector2i(10, 10), SimMap.Terrain.WATER_DEEP)
	assert_eq(sea.find_free_adjacent(Rect2i(4, 4, 2, 2), SimMap.Domain.LAND),
			Vector2i(-1, -1), "no land anywhere means no land tile is returned")

	var afloat := sea.find_free_adjacent(Rect2i(4, 4, 2, 2), SimMap.Domain.WATER)
	assert_true(afloat.x >= 0, "but a boat finds water immediately")
	assert_true(sea.is_passable(afloat, SimMap.Domain.WATER))


func test_free_adjacent_finds_a_distant_island_because_it_searches_the_map() -> void:
	# The flip side, made explicit so the widening behaviour is not a surprise: the
	# search is not limited to nearby rings. 5.4 spawns production onto it, so a
	# unit can appear a long way from its building on a mostly-blocked map. If that
	# ever reads badly in play, cap the ring count -- but cap it deliberately.
	var sea := SimMap.create(Vector2i(10, 10), SimMap.Terrain.WATER_DEEP)
	sea.set_terrain(Vector2i(0, 0), SimMap.Terrain.GRASS)
	assert_eq(sea.find_free_adjacent(Rect2i(4, 4, 2, 2), SimMap.Domain.LAND),
			Vector2i(0, 0), "the one land tile on the map, five rings out")


# ── determinism ────────────────────────────────────────────────────────────

func test_identical_maps_hash_identically_and_different_ones_do_not() -> void:
	var a := SimMap.create(Vector2i(6, 6))
	var b := SimMap.create(Vector2i(6, 6))
	assert_eq(a.state_hash(), b.state_hash(), "same map, same hash")

	b.set_terrain(Vector2i(2, 2), SimMap.Terrain.WATER_DEEP)
	assert_ne(a.state_hash(), b.state_hash(), "terrain is in the hash")

	var c := SimMap.create(Vector2i(6, 6))
	c.set_occupied(Rect2i(1, 1, 2, 2), 3)
	assert_ne(a.state_hash(), c.state_hash(), "occupancy is in the hash")

	assert_ne(a.state_hash(), SimMap.create(Vector2i(7, 6)).state_hash(),
			"size is in the hash")


func test_the_world_hash_includes_the_map() -> void:
	# Without this, two clients that disagreed about the terrain would still hash
	# identically and the 0.7 desync check would pass while they diverged.
	var w := SimWorld.new()
	w.setup(MatchConfig.debug_single_player())
	var before := w.state_hash()
	w.map.set_terrain(Vector2i(3, 3), SimMap.Terrain.WATER_DEEP)
	assert_ne(w.state_hash(), before, "changing the map changes the world hash")


func test_setup_creates_a_map_at_the_configured_size() -> void:
	var cfg := MatchConfig.debug_single_player()
	var w := SimWorld.new()
	w.setup(cfg)
	assert_not_null(w.map, "the world has a map from 2.1 on")
	assert_eq(w.map.size, cfg.map_size)
	assert_true(w.map.is_passable(Vector2i(0, 0)), "and it is usable straight away")
