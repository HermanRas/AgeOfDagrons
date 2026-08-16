## Decorative props standing around a building (`GameDataRegistry.props_for`).
##
## The plank stacks at a lumber camp, the cut stone at a mining camp and the
## produce crates at a mill are SEPARATE atlases composed at draw time rather
## than baked into the building (project owner, 2026-08-15). That decision is
## what these tests defend: seven prop atlases sat complete on disk for a day
## doing nothing, because `visuals.json` declared none of them and an undeclared
## id is unreachable -- `atlas_for()` had never been asked for one. Nothing
## reported it, which is the same silent-failure shape as the stale skins.
##
## Like test_skins, most of this asserts the SHIPPED DATA rather than pixels:
## `game/assets/atlases/` is gitignored and a fresh clone has none of it.
extends TestCase

const REGISTRY_SCRIPT := "res://src/autoload/game_data.gd"

## Every dropsite that should stand among its own resource, and what it stands
## among. The mill's are age-gated; the two camps' are not.
const DRESSED := {
	&"vis.lumber_camp": &"vis.prop_wood_lumber",
	&"vis.mining_camp": &"vis.prop_stone_pile_granite",
}

var reg: Node


func before_each() -> void:
	reg = (load(REGISTRY_SCRIPT) as GDScript).new()
	reg.load_all()


func after_each() -> void:
	reg.free()


# ── the declarations ────────────────────────────────────────────────────────

func test_the_dropsites_carry_their_own_resource_as_props() -> void:
	for visual_id in DRESSED:
		var props: Array = reg.props_for(visual_id, 1)
		assert_eq(props.size(), 3, "%s stands among three piles" % visual_id)
		for p in props:
			assert_eq(p["visual"], DRESSED[visual_id],
					"%s is dressed with its own resource" % visual_id)


func test_every_prop_names_a_visual_that_actually_exists() -> void:
	# A prop naming a missing id would draw the magenta unknown beside an
	# otherwise perfect building -- loud, but only once somebody looks at it.
	# Asserted against the shipped file rather than through the registry, so it
	# holds on a fresh clone where no atlas is staged and everything resolves to
	# a placeholder.
	var declared: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/visuals.json"))
	for age in [1, 2, 3, 4]:
		for visual_id in [&"vis.mill", &"vis.lumber_camp", &"vis.mining_camp"]:
			for p in reg.props_for(visual_id, age):
				assert_true(declared.has(String(p["visual"])),
						"%s prop %s is a declared visual" % [visual_id, p["visual"]])


func test_the_shipped_data_still_loads_without_warnings() -> void:
	# props_for() is read by validate(), so a malformed entry surfaces here
	# rather than as a silently undrawn pile.
	assert_eq(reg.load_warnings, [] as Array[String],
			"; ".join(reg.load_warnings))


# ── the age gate ────────────────────────────────────────────────────────────

func test_the_mill_gains_its_food_props_only_at_age_three() -> void:
	# The Briton rotary mill has no produce to stand among; the Persian
	# storehouse and Roman farmstead that replace it at ages 3 and 4 do.
	assert_eq(reg.props_for(&"vis.mill", 1).size(), 0, "age 1 is a bare rotary mill")
	assert_eq(reg.props_for(&"vis.mill", 2).size(), 0, "and so is age 2")
	assert_eq(reg.props_for(&"vis.mill", 3).size(), 3, "age 3 lays out the crates")
	assert_eq(reg.props_for(&"vis.mill", 4).size(), 3)


func test_an_ungated_prop_shows_in_every_age() -> void:
	for age in [1, 2, 3, 4]:
		assert_eq(reg.props_for(&"vis.lumber_camp", age).size(), 3,
				"a lumber camp has timber in age %d" % age)


func test_no_age_is_read_as_age_one_rather_than_showing_everything() -> void:
	# A caller with no skin yet -- a view drawn before its first snapshot --
	# must get the age-1 dressing, not the union of all four.
	assert_eq(reg.props_for(&"vis.mill", 0).size(), 0)
	assert_eq(reg.props_for(&"vis.mill", -1).size(), 0)


# ── the offsets ─────────────────────────────────────────────────────────────

func test_props_stay_inside_the_ground_the_building_already_reserves() -> void:
	# The project owner's rule (2026-08-16): props must not grow the footprint.
	# They can afford not to, because `buildings.json` sizes a footprint as the
	# max across all four age skins, so ages 1 and 2 are holding ground their art
	# does not fill. Asserted against the REAL footprint of the building that
	# uses each visual, in metres.
	for building_id in [&"building.mill", &"building.lumber_camp", &"building.mining_camp"]:
		var bd: BuildingDef = reg.building(building_id)
		assert_not_null(bd, "%s exists" % building_id)
		var half := Vector2(bd.footprint) * Iso.METRES_PER_TILE * 0.5
		for age in [1, 2, 3, 4]:
			for p in reg.props_for(bd.visual, age):
				var off: Vector2 = p["offset_m"]
				assert_true(absf(off.x) <= half.x and absf(off.y) <= half.y,
						"%s prop at %s is inside its %s m half-footprint" % [building_id, off, half])


func test_the_props_are_spread_out_rather_than_stacked_on_one_spot() -> void:
	# Three piles at the same offset would render as one and look like a bug in
	# the count rather than in the placement.
	for visual_id in [&"vis.lumber_camp", &"vis.mining_camp", &"vis.mill"]:
		var seen: Array[Vector2] = []
		for p in reg.props_for(visual_id, 4):
			var off: Vector2 = p["offset_m"]
			assert_false(seen.has(off), "%s has two props at %s" % [visual_id, off])
			seen.append(off)


# ── everything else is unaffected ───────────────────────────────────────────

func test_almost_nothing_has_props_and_asking_is_cheap() -> void:
	# The empty list is the answer for every unit, every resource node and most
	# buildings; EntityView calls this once per view, so it must be total and
	# quiet rather than warn about an id that simply has none.
	for visual_id in [&"vis.villager", &"vis.knight", &"vis.tree", &"vis.town_center",
			&"vis.house", &"vis.nothing_at_all"]:
		assert_eq(reg.props_for(visual_id, 4).size(), 0, "%s has no props" % visual_id)
