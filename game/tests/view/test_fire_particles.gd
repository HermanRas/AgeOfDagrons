## The two fires (PLAN.md 13.4, owner's ask 2026-09-06): the dragon's breath landing on a
## patch of ground, and a building burning while it is badly hurt.
##
## ## WHAT IS WORTH TESTING ABOUT A DECORATION, WHICH IS NOT "DOES IT LOOK NICE"
##
## Nothing here asserts a colour or a particle count -- those are taste and they will be
## retuned. What it asserts is the three things that are not taste:
##
##   1. **WHEN.** A fire that appears at the wrong moment is a bug report. The building case
##      has a genuine trap in it -- a FOUNDATION starts at a few hit points and climbs, so
##      the naive rule sets every building site in the game alight -- and the blast case has
##      a subtler one, since the only signal that an ability fired is a number going UP.
##   2. **WHERE.** The blast is drawn over the ground `AbilitySystem._burn` actually
##      damaged. A picture at a size or a place the VIEW chose would be the client telling
##      the player something untrue about a fight (PLAN.md 4, which admits no exception for
##      effects).
##   3. **THAT IT STOPS.** These nodes are pooled and recycled; a fire that outlives its
##      building ends up on somebody's villager.
extends TestCase

var view: GameView


func before_each() -> void:
	view = GameView.new()


func after_each() -> void:
	# The layers `_ready()` would have parented, orphaned by a bare `.new()` -- see
	# `test_game_view.after_each`, whose list this follows.
	view.pool.free()
	view.terrain.free()
	view.fog.free()
	view.spent.free()
	view.blasts.free()
	view.free()


func _snap(tick: int, updated: Array, removed: Array = []) -> Dictionary:
	return {"tick": tick, "updated": updated, "removed": removed}


## A building entry. `phase` defaults to COMPLETE because that is the interesting case;
## the foundation test passes its own.
func _house(id: int, hp: int, max_hp := 100,
		phase := SimBuilding.Phase.COMPLETE, alive := true) -> Dictionary:
	return {"id": id, "def_id": "building.house", "owner_id": 1,
			"hp": hp, "max_hp": max_hp, "phase": int(phase), "alive": alive,
			"pos": {"x": 8 * SimWorld.SUBTILE, "y": 8 * SimWorld.SUBTILE}}


## The mother, mid-cooldown. `cooldown` of 0 means "send neither field", which is what a
## unit that has not used its ability looks like on the wire.
func _dragon(id: int, cooldown: int, aim := Vector2i(20, 20)) -> Dictionary:
	var d := {"id": id, "def_id": "unit.dragon", "owner_id": 1,
			"hp": 600, "max_hp": 600, "anim": "idle", "facing": 0, "alive": true,
			"pos": {"x": 18 * SimWorld.SUBTILE, "y": 18 * SimWorld.SUBTILE}}
	if cooldown > 0:
		d["ability_cooldown"] = cooldown
		d["ability_aim"] = {"x": aim.x, "y": aim.y}
	return d


# ── a building on fire ──────────────────────────────────────────────────────────

func test_a_badly_hurt_building_burns_and_a_healthy_one_does_not() -> void:
	view.apply_snapshot(_snap(1, [_house(4, 100)]))
	assert_false(view.pool.get_view(4).is_burning(), "an untouched house is not on fire")

	view.apply_snapshot(_snap(2, [_house(4, 20)]))
	assert_true(view.pool.get_view(4).is_burning(), "a fifth of its health left")


func test_it_goes_out_when_the_building_is_repaired() -> void:
	# Repair is a real verb in this game (5.3), so this is not a hypothetical: a building
	# that stayed alight after being mended would tell the player their repair did nothing.
	view.apply_snapshot(_snap(1, [_house(4, 20)]))
	assert_true(view.pool.get_view(4).is_burning())
	view.apply_snapshot(_snap(2, [_house(4, 90)]))
	assert_false(view.pool.get_view(4).is_burning())


func test_a_FOUNDATION_never_burns_however_little_health_it_has() -> void:
	# ⚠️ **THE TRAP THIS FEATURE WAS MOST LIKELY TO SHIP WITH.** A building under
	# construction starts at a few hit points and climbs (5.2), so "below a third" is TRUE
	# for nearly every foundation for most of its build time. Without the phase clause,
	# every house a player pegs out is instantly ablaze -- which is not a subtle defect, it
	# is most of what the screen shows during an opening.
	view.apply_snapshot(_snap(1, [_house(4, 5, 100, SimBuilding.Phase.FOUNDATION)]))
	assert_false(view.pool.get_view(4).is_burning(), "a building site is not a fire")

	view.apply_snapshot(_snap(2, [_house(4, 40, 100, SimBuilding.Phase.UNDER_CONSTRUCTION)]))
	assert_false(view.pool.get_view(4).is_burning())

	# And it catches the moment it is finished and still hurt, which is the same house.
	view.apply_snapshot(_snap(3, [_house(4, 20, 100, SimBuilding.Phase.COMPLETE)]))
	assert_true(view.pool.get_view(4).is_burning())


func test_RUBBLE_does_not_burn() -> void:
	# A destroyed building stands as wreckage for a minute (5.5). Fire on it would read as
	# something still burning down long after the fight moved on -- and its hp is 0, which
	# is the deepest possible "low health".
	view.apply_snapshot(_snap(1, [_house(4, 0, 100, SimBuilding.Phase.COMPLETE, false)]))
	assert_false(view.pool.get_view(4).is_burning())


func test_a_wounded_UNIT_does_not_burn() -> void:
	# The owner asked for buildings. A unit sends no `phase`, which is the test, and a
	# villager on fire for the last quarter of her health would be a different feature
	# nobody asked for.
	view.apply_snapshot(_snap(1, [{"id": 3, "def_id": "unit.villager", "owner_id": 1,
			"hp": 3, "max_hp": 30, "anim": "idle", "facing": 0, "alive": true,
			"pos": {"x": 0, "y": 0}}]))
	assert_false(view.pool.get_view(3).is_burning())


func test_a_recycled_view_does_not_arrive_already_on_fire() -> void:
	# ⚠️ `EntityViewPool` REUSES THESE NODES. A burning house released and handed to the
	# next entity that needs a view would arrive alight -- and the next entity is most
	# likely a unit or a tree, which `GameView` never calls `set_burning` on at all, so
	# nothing downstream would ever put it out.
	# Through the POOL directly rather than through two snapshots, so the assertion is
	# unambiguous: `_free.pop_back()` hands back the very node that was released, and a test
	# that merely watched a fresh view not be on fire would pass without proving anything.
	var pool := EntityViewPool.new()
	var house := pool.acquire(4, &"vis.house")
	house.set_burning(true)
	assert_true(house.is_burning())

	pool.release(4)
	var reused := pool.acquire(9, &"vis.villager")
	assert_eq(reused, house, "the pool hands the same node back -- which is what makes"
			+ " this a real case rather than a hypothetical one")
	assert_false(reused.is_burning(), "and `release` put the fire out")
	pool.free()


# ── the dragon's breath landing ─────────────────────────────────────────────────

func test_a_rising_ability_cooldown_is_what_draws_the_blast() -> void:
	# The ONLY signal that a ground ability fired. `AbilitySystem` sets the cooldown to its
	# full value on the tick the breath lands and counts it down by one every tick after, so
	# a rise cannot mean anything else.
	view.apply_snapshot(_snap(1, [_dragon(7, 0)]))
	assert_eq(view.blasts.alive_count(), 0, "nothing has been used yet")

	view.apply_snapshot(_snap(2, [_dragon(7, 1200)]))
	assert_eq(view.blasts.alive_count(), 1, "she breathed")


func test_a_cooldown_TICKING_DOWN_draws_nothing() -> void:
	# The other 1,199 ticks of a 120 s cooldown. A blast per tick would be 1,200 emitters
	# for one breath, which is the failure a level test ("is it at maximum") would not have
	# had and an edge test could still have, backwards.
	view.apply_snapshot(_snap(1, [_dragon(7, 1200)]))
	assert_eq(view.blasts.alive_count(), 1)
	for tick in range(2, 8):
		view.apply_snapshot(_snap(tick, [_dragon(7, 1202 - tick)]))
	assert_eq(view.blasts.alive_count(), 1, "still the one, six ticks later")


func test_a_second_breath_draws_a_second_blast() -> void:
	# Down to nothing and fired again. An edge test has to survive the cooldown reaching 0
	# and coming back, which is the whole point of it over "is it at maximum".
	view.apply_snapshot(_snap(1, [_dragon(7, 1200)]))
	view.apply_snapshot(_snap(2, [_dragon(7, 0)]))
	assert_eq(view.blasts.alive_count(), 1)
	view.apply_snapshot(_snap(3, [_dragon(7, 1200)]))
	assert_eq(view.blasts.alive_count(), 2)


func test_a_dragon_that_was_never_seen_before_still_draws_its_blast() -> void:
	# She flies, and 12 tiles of line of sight means she is often seen for the first time
	# in the same snapshot that carries a fire. `_facts` has no entry for her, so the
	# comparison is against a default of 0 -- which is the reading that makes this work.
	view.apply_snapshot(_snap(1, [_dragon(7, 1200)]))
	assert_eq(view.blasts.alive_count(), 1)


func test_a_MONK_healing_sets_nobody_alight() -> void:
	# The other unit with an ability. `ability_effect` is the same axis `AbilitySystem._fire`
	# branches on, so a heal draws no fire rather than igniting its patient -- and the monk
	# is the reason `_play_blast` reads the effect at all instead of assuming a cooldown
	# means a blast.
	view.apply_snapshot(_snap(1, [{"id": 5, "def_id": "unit.monk", "owner_id": 1,
			"hp": 45, "max_hp": 45, "anim": "idle", "facing": 0, "alive": true,
			"ability_cooldown": 100, "ability_aim": {"x": 4, "y": 4},
			"pos": {"x": 0, "y": 0}}]))
	assert_eq(view.blasts.alive_count(), 0)


func test_the_blast_is_drawn_where_the_AIM_was_and_not_where_the_dragon_stood() -> void:
	# ⚠️ **THE REASON `ability_aim` IS ON THE WIRE AT ALL.** `SimUnit.set_path` rewrites
	# `task_target_tile` to wherever the route could actually end, which is why
	# `ability_target_tile` exists as a separate field -- and a fireball drawn at the
	# caster's own position is a dragon breathing on her own feet. She stands at (18, 18)
	# here and aims at (30, 24).
	view.apply_snapshot(_snap(1, [_dragon(7, 1200, Vector2i(30, 24))]))
	assert_eq(view.blasts.alive_count(), 1)
	var at := (view.blasts.get_child(0) as Node2D).position
	assert_eq(at, Iso.tile_centre_to_world(Vector2i(30, 24)))
	assert_ne(at, view.pool.get_view(7).position)


func test_the_blast_is_the_size_the_SIM_burns_and_not_a_size_the_view_chose() -> void:
	# `AbilitySystem._burn` damages a square `radius * 2 + 1` tiles across. Reading it off
	# the def rather than hardcoding it means retuning the dragon in `units.json` moves the
	# picture with the damage -- and a mismatch here is the client telling the player the
	# wrong thing about where a fight happened.
	var def: UnitDef = GameDataRegistry.unit(&"unit.dragon")
	assert_not_null(def)
	if def == null:
		return
	view.apply_snapshot(_snap(1, [_dragon(7, 1200)]))
	var emitter := view.blasts.get_child(0) as GPUParticles2D
	var mat: ParticleProcessMaterial = emitter.process_material
	var span := float(def.ability_radius * 2 + 1)
	assert_eq(mat.emission_box_extents.x, span * Iso.TILE_SIZE.x * 0.5)
	assert_eq(mat.emission_box_extents.y, span * Iso.TILE_SIZE.y * 0.5)


func test_a_dragon_lost_to_the_fog_draws_nothing() -> void:
	# ⚠️ **NO FOG CLAUSE EXISTS IN `GameView` FOR THIS AND NONE SHOULD.** An entity the
	# client cannot see is simply absent from `updated`, so no rise is ever observed. This
	# pins the property rather than the implementation: a breath weapon fired across the map
	# in the dark must leave nothing on screen, exactly as an arrow lost to the fog leaves
	# no litter.
	view.apply_snapshot(_snap(1, [_dragon(7, 0)]))
	view.apply_snapshot(_snap(2, []))
	view.apply_snapshot(_snap(3, []))
	assert_eq(view.blasts.alive_count(), 0)


func test_the_aim_survives_a_JSON_ROUND_TRIP() -> void:
	# `Vector2i` over Godot's binary RPC, `{"x": .., "y": ..}` through JSON -- which is
	# every fixture here and every replay when 12.4 lands. `_as_tile` reads both, and a
	# reader that only knew the binary form would fail SILENTLY at (0, 0), drawing every
	# fireball in the map's north corner.
	var binary := _dragon(7, 1200)
	binary["ability_aim"] = Vector2i(30, 24)
	view.apply_snapshot(_snap(1, [binary]))
	assert_eq(view.blasts.alive_count(), 1)
	assert_eq((view.blasts.get_child(0) as Node2D).position,
			Iso.tile_centre_to_world(Vector2i(30, 24)))


# ── the shared factory ──────────────────────────────────────────────────────────

func test_the_spark_is_generated_rather_than_loaded_and_is_shared() -> void:
	# It must not become an asset: a `res://assets/` PNG would put this behind the art
	# queue, add a licence row for a blurred dot, and -- worst -- resolve to a magenta
	# placeholder box if it ever went missing, which is a hundred magenta squares
	# fountaining out of a burning house.
	var a := FlameParticles.spark_texture()
	assert_not_null(a)
	assert_eq(a.get_width(), 32)
	assert_eq(a.get_height(), 32)
	assert_true(a == FlameParticles.spark_texture(), "cached, one per process")
