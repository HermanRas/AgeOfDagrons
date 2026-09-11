## Where a bot puts a building that exists to carry another one (card `14d-farm-placement`).
##
## ## THE DEFECT
##
## A `building.field` is **6x6** and declares `requires_adjacent: ["building.mill"]`; a
## `building.mill` is **5x4**. So a farm needs 36 clear tiles abutting the mill -- and the mill was
## sited by `_find_spot`'s plain "first legal ring position near the town centre", which on a
## wooded map is whatever gap happened to be nearest, with no thought for what it is FOR.
##
## Measured on 2026-09-11 across four seeds of `preview_ai_match --levels easy,easy`: **no field
## was placed at all on three of them.** Since the rule set builds exactly one mill
## (`fewer_than: {building.mill: 1}`) and never moves it, a bot that sites one badly has no
## renewable food for the rest of the match -- berries are stripped in the first minute -- and a
## villager costs 50 food while a swordsman costs 60. That is `14c`'s starvation, one layer down.
##
## ## ⚠️ WHY THE FALLBACK IS TESTED AS HARD AS THE FEATURE
##
## The obvious implementation refuses to build a mill at all when no roomy site exists, which is
## strictly worse than the defect: a bot with a cramped mill still mills, and a bot with no mill
## cannot even bank food. So *"prefer room, accept anything"* is the rule, and both halves have a
## test that fails on the other one.
extends TestCase

const MILL := &"building.mill"
const FIELD := &"building.field"

## ⚠️ **`WATER_DEEP`, BECAUSE THERE IS NO `Terrain.WATER`** -- the enum is GRASS, DIRT, SAND,
## WATER_SHALLOW, WATER_DEEP, ROCK, FOREST. Named once here so the seven uses below cannot drift.
const BLOCKED := SimMap.Terrain.WATER_DEEP


func _world() -> SimWorld:
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.teams = [0, 0]
	cfg.map_size = Vector2i(64, 64)
	cfg.ai_players = [true, false] as Array[bool]
	var w := SimWorld.new()
	w.setup(cfg)
	w.map.fill_terrain(SimMap.Terrain.GRASS)
	return w


func _ai(w: SimWorld) -> AISystem:
	for s in w._systems:
		if s is AISystem:
			return s as AISystem
	return null


func _footprint(def_id: StringName) -> Vector2i:
	return GameDataRegistry.building(def_id).footprint


# ── the derived index ───────────────────────────────────────────────────────

## ⚠️ **DERIVED FROM `requires_adjacent`, NEVER DECLARED TWICE.** A `carries: ["building.field"]`
## field on the mill would be the same fact written in two places, and the day they disagreed a
## mill would be sited with room for a farm that no longer wanted to be there.
func test_a_mill_knows_it_exists_to_carry_a_field() -> void:
	assert_true(GameDataRegistry.hosted_by(MILL).has(FIELD))
	assert_true(GameDataRegistry.building(FIELD).requires_adjacent.has(MILL),
			"and the fact it is derived from still says so")


func test_an_ordinary_building_carries_nothing() -> void:
	assert_true(GameDataRegistry.hosted_by(&"building.house").is_empty())
	assert_true(GameDataRegistry.hosted_by(&"building.town_center").is_empty())


## A def nobody has ever heard of is a question with an answer, not a crash: `_find_spot` asks this
## for every building it places.
func test_an_unknown_building_carries_nothing_rather_than_failing() -> void:
	assert_true(GameDataRegistry.hosted_by(&"building.nonsense").is_empty())


# ── is there room beside it ─────────────────────────────────────────────────

func test_open_ground_beside_a_mill_is_room_for_a_field() -> void:
	var w := _world()
	assert_true(_ai(w)._has_room_beside(w, Rect2i(20, 20, 5, 4), [FIELD]))


## ⛔ **THE CASE THE WHOLE CARD IS ABOUT.** The mill fits and the farm does not, which on a Forest
## map is the normal state of the ground beside a town centre.
func test_a_mill_in_a_pocket_has_no_room_for_a_field() -> void:
	var w := _world()
	# Everything is blocked except a pocket exactly big enough for the mill and one tile around
	# it, which is enough to ABUT and nowhere near enough for 36 tiles of crop.
	w.map.fill_terrain(BLOCKED)
	w.map.set_terrain_rect(Rect2i(19, 19, 7, 6), SimMap.Terrain.GRASS)
	assert_false(_ai(w)._has_room_beside(w, Rect2i(20, 20, 5, 4), [FIELD]))


## ⚠️ **ROOM MEANS ROOM THAT TOUCHES.** A clearing one tile clear of the mill would be refused by
## `adjacency_allows` at placement time, so counting it here would site the mill for a farm that
## can never be built -- the defect back again, wearing a fix.
func test_a_clearing_that_does_not_touch_the_mill_is_not_room() -> void:
	var w := _world()
	w.map.fill_terrain(BLOCKED)
	var host := Rect2i(20, 20, 5, 4)
	w.map.set_terrain_rect(host, SimMap.Terrain.GRASS)
	# A 6x6 clearing starting one tile PAST the mill's grown edge: near, ample, and useless.
	w.map.set_terrain_rect(Rect2i(host.end.x + 1, 20, 6, 6), SimMap.Terrain.GRASS)
	assert_false(_ai(w)._has_room_beside(w, host, [FIELD]))


## ⚠️ **AND IT SLIDES, WHICH A FIRST CUT DID NOT.** Three offsets a side -- flush at each end and
## centred -- looked like enough and left two bots with a mill and no field on seed 11. A farm
## fitting at exactly one offset between two trees is the normal case, not a pathological one.
func test_room_at_an_offset_no_neat_alignment_would_find_still_counts() -> void:
	var w := _world()
	var host := Rect2i(20, 20, 5, 4)
	w.map.fill_terrain(BLOCKED)
	w.map.set_terrain_rect(host, SimMap.Terrain.GRASS)
	# Flush to the mill's right edge, but slid three tiles up: not either end, not centred.
	w.map.set_terrain_rect(Rect2i(host.end.x, host.position.y - 3, 6, 6), SimMap.Terrain.GRASS)
	assert_true(_ai(w)._has_room_beside(w, host, [FIELD]))


func test_a_building_that_carries_nothing_is_never_asked_for_room() -> void:
	var w := _world()
	w.map.fill_terrain(BLOCKED)
	assert_false(_ai(w)._has_room_beside(w, Rect2i(20, 20, 5, 4), []),
			"nothing to fit means nothing fits, and `_find_spot` never asks")


# ── the two passes ─────────────────────────────────────────────────────────

## The whole feature in one assertion: the nearest legal mill site is a pocket, the roomy one is
## further out, and the bot walks past the near one.
func test_a_mill_is_sited_where_its_farm_will_fit_even_if_that_is_further() -> void:
	var w := _world()
	var anchor := Vector2i(10, 10)
	w.map.fill_terrain(BLOCKED)
	# A pocket close to the anchor that takes a mill and nothing else...
	w.map.set_terrain_rect(Rect2i(11, 11, 7, 6), SimMap.Terrain.GRASS)
	# ...and open country further out, well inside MAX_PLACEMENT_RADIUS.
	w.map.set_terrain_rect(Rect2i(16, 16, 20, 20), SimMap.Terrain.GRASS)

	var origin := _ai(w)._find_spot(w, w.player_for(1), MILL, anchor)
	assert_true(origin.x >= 0, "it found somewhere")
	var rect := SimMap.footprint_rect(origin, _footprint(MILL))
	assert_true(_ai(w)._has_room_beside(w, rect, [FIELD]),
			"and the somewhere it found has room for the farm the mill is for")


## ⛔ **A MILL SOMEWHERE BEATS NO MILL.** Refusing to build when nothing is roomy would be worse
## than the defect being fixed: a cramped mill still banks food, and no mill banks none.
func test_a_mill_still_goes_up_when_nowhere_has_room_for_a_farm() -> void:
	var w := _world()
	var anchor := Vector2i(20, 20)
	w.map.fill_terrain(BLOCKED)
	w.map.set_terrain_rect(Rect2i(21, 21, 7, 6), SimMap.Terrain.GRASS)   # the pocket, and only it

	var origin := _ai(w)._find_spot(w, w.player_for(1), MILL, anchor)
	assert_true(origin.x >= 0, "it settled for the pocket rather than going without")
	assert_true(w.map.can_place_building(SimMap.footprint_rect(origin, _footprint(MILL))),
			"and what it settled for is legal")


## The regression guard on every other building in the game: nothing carries a house, so a house
## must still take the first legal ring position exactly as it always did.
func test_a_building_that_carries_nothing_takes_the_nearest_legal_spot() -> void:
	var w := _world()
	var anchor := Vector2i(30, 30)
	var origin := _ai(w)._find_spot(w, w.player_for(1), &"building.house", anchor)
	# Ring 2 is where the scan starts, so on open ground the answer is exactly ring 2.
	assert_eq(maxi(absi(origin.x - anchor.x), absi(origin.y - anchor.y)), 2)
