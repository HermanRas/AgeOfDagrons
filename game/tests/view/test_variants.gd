## Interchangeable looks (visuals.json `variants`), the third axis of the asset
## seam and the only one that is not a skin.
##
## The project owner's four field plots are the first and so far only user: four
## crops, not four ages (2026-08-17). `age` and `colour` change what a STANDING
## entity looks like; a variant is decided when the thing comes into existence and
## never revisited.
extends TestCase

var reg: Node = GameDataRegistry


func test_a_visual_with_no_variants_resolves_to_itself() -> void:
	# Which is what lets GameView call variant_of() unconditionally instead of
	# holding a list of which visuals have them.
	for seed in [0, 1, 7, 1000, -3]:
		assert_eq(reg.variant_of(&"vis.villager", seed), &"vis.villager")
	assert_eq(reg.variant_count(&"vis.villager"), 1)


func test_an_undeclared_visual_resolves_to_itself_rather_than_failing() -> void:
	# atlas_for() is total and turns an unknown id into the loud magenta
	# placeholder; this must hand it that id rather than crash on the way.
	assert_eq(reg.variant_of(&"vis.nonesuch", 3), &"vis.nonesuch")
	assert_eq(reg.variant_count(&"vis.nonesuch"), 1)


func test_the_field_offers_four_plots() -> void:
	assert_eq(reg.variant_count(&"vis.field"), 4)


func test_every_variant_is_a_declared_visual_with_real_art() -> void:
	# A variant naming an id nobody declared would resolve to the magenta unknown
	# -- loud, but at draw time rather than at load. _validate_variants() catches it
	# as a load warning; this is the positive half.
	for i in range(reg.variant_count(&"vis.field")):
		var id: StringName = reg.variant_of(&"vis.field", i)
		assert_not_null(reg.placeholder_for(id), "%s is declared" % id)
		assert_true(reg.has_atlas(id), "%s has a staged atlas behind it" % id)


func test_all_four_plots_are_actually_reachable() -> void:
	# A pick that could only ever land on one of them would be worse than no
	# variants at all: it would look wired and never vary.
	var seen: Array[String] = []
	for seed in range(64):
		var id := String(reg.variant_of(&"vis.field", seed) as StringName)
		if not seen.has(id):
			seen.append(id)
	seen.sort()
	assert_eq(seen, ["vis.field_1", "vis.field_2", "vis.field_3", "vis.field_4"])


func test_the_four_plots_are_four_different_atlases() -> void:
	# They are four different crops. Four ids pointing at one file would render as
	# one plot four times and nothing would report it.
	var paths: Array[String] = []
	for i in range(4):
		var entry: AtlasEntry = reg.atlas_for(reg.variant_of(&"vis.field", i))
		assert_false(entry.is_placeholder)
		assert_false(paths.has(entry.id), "%s is its own atlas" % entry.id)
		paths.append(entry.id)


func test_a_negative_seed_does_not_index_off_the_front() -> void:
	# posmod, not %. A seed is caller-derived and nothing promises it is positive.
	for seed in [-1, -4, -7, -100]:
		var id: StringName = reg.variant_of(&"vis.field", seed)
		assert_true(String(id).begins_with("vis.field_"), "%s is a real plot" % id)


# ── variant pools: one species set per map type (2026-08-28) ────────────────

## The project owner's assignment, recorded on line 1 of each recipe in
## tools/recipes/tree_*.toml. Pinned here rather than read back out of visuals.json,
## because a test that asks the data what the data says cannot fail.
const POOLS := {
	&"island": ["vis.tree_palm_cretan_patch", "vis.tree_palm_date", "vis.tree_palm_fan",
		"vis.tree_palm_tropical", "vis.tree_palm_tropical_tall"],
	# ARCHIPELAGO TAKES THE ISLAND'S PALMS, written out rather than aliased. The owner's
	# assignment is per map type and this is a second tropical type, so the same five are
	# the right answer -- but they are the right answer by agreement and not by
	# construction, and an alias would quietly move the archipelago the day somebody
	# retuned the island. Two lists that happen to match today.
	&"archipelago": ["vis.tree_palm_cretan_patch", "vis.tree_palm_date", "vis.tree_palm_fan",
		"vis.tree_palm_tropical", "vis.tree_palm_tropical_tall"],
	&"forest": ["vis.tree_beech", "vis.tree_birch", "vis.tree_fir", "vis.tree_oak_new"],
	&"river": ["vis.tree_bamboo", "vis.tree_palm_date"],
	&"desert": ["vis.tree_elm_dead", "vis.tree_oak_dead"],
}


func test_each_map_type_draws_its_own_assigned_species() -> void:
	for pool in POOLS:
		var seen: Array[String] = []
		for seed in range(64):
			var id := String(reg.variant_of(&"vis.tree", seed, pool) as StringName)
			if not seen.has(id):
				seen.append(id)
		seen.sort()
		assert_eq(seen, POOLS[pool], "the %s pool" % pool)


func test_a_view_that_names_no_pool_gets_the_general_mix() -> void:
	# The fixed debug map, every preview and every test stand a view up without ever
	# being told a map type. They must draw SOMETHING sensible rather than resolving to
	# a biome nobody picked for them -- which is why oak/elm/toona stay in `variants`
	# instead of being folded into the forest pool.
	for seed in range(32):
		var id := String(reg.variant_of(&"vis.tree", seed) as StringName)
		assert_true(["vis.tree", "vis.tree_elm", "vis.tree_toona"].has(id),
				"%s is one of the general three" % id)


func test_an_unknown_pool_falls_back_rather_than_drawing_nothing() -> void:
	# `variant_of` is total the same way `atlas_for` is. A pool nobody declares must
	# not resolve to the base id -- on a tree that would be the oak on every tile of an
	# archipelago, which reads as a wiring bug rather than as a missing pool.
	for seed in range(16):
		var id := String(reg.variant_of(&"vis.tree", seed, &"tundra") as StringName)
		assert_true(["vis.tree", "vis.tree_elm", "vis.tree_toona"].has(id),
				"%s came from the general list" % id)


func test_every_pooled_species_is_declared_and_staged() -> void:
	for pool in POOLS:
		for id in POOLS[pool]:
			var vid := StringName(id)
			assert_not_null(reg.placeholder_for(vid), "%s is declared" % vid)
			assert_true(reg.has_atlas(vid), "%s has a staged atlas behind it" % vid)


func test_the_banyan_is_declared_and_in_no_pool() -> void:
	# JUDGED AND EXCLUDED, 2026-08-28: "the test scene confirms the warning, the tree
	# will not work, please exclude it". The owner reproduced the teak's actual defect
	# with it in `preview_banyan` -- a playable grove, not a picture -- so this is a
	# settled decision and not a pending question. It stays DECLARED so the preview can
	# still draw it and judge the next candidate; a pool is the only thing that would
	# put it on a map.
	assert_true(reg.has_atlas(&"vis.tree_banyan"), "declared and staged")
	for pool in POOLS:
		assert_false(POOLS[pool].has("vis.tree_banyan"), "not in the %s pool" % pool)
	for pool in MapGenerator.pool_names():
		for seed in range(64):
			assert_ne(reg.variant_of(&"vis.tree", seed, pool), &"vis.tree_banyan",
					"no seed reaches it on a %s map" % pool)


func test_the_teak_stays_out_of_every_pool_too() -> void:
	# Pulled 2026-08-23 and it must not come back through the new axis. This is the
	# one thing the pools could quietly undo: the teak is a perfectly good forest tree
	# to anyone reading the list without the history.
	for pool in MapGenerator.pool_names():
		for seed in range(64):
			assert_ne(reg.variant_of(&"vis.tree", seed, pool), &"vis.tree_teak",
					"no seed reaches the teak on a %s map" % pool)


func test_a_pool_choice_is_stable_for_a_given_seed() -> void:
	# Same argument as the tile seed itself: every client picks the same tree without
	# the choice being sent, so the function has to be pure.
	for pool in MapGenerator.pool_names():
		for seed in [0, 3, 17, -5, 900]:
			assert_eq(reg.variant_of(&"vis.tree", seed, pool),
					reg.variant_of(&"vis.tree", seed, pool))


func test_variant_count_answers_per_pool() -> void:
	assert_eq(reg.variant_count(&"vis.tree", &"island"), 5)
	assert_eq(reg.variant_count(&"vis.tree", &"desert"), 2)
	assert_eq(reg.variant_count(&"vis.tree"), 3, "the general mix, unchanged")
	assert_eq(reg.variant_count(&"vis.villager", &"island"), 1,
			"an entry with no pools ignores one it is handed")


func test_pool_names_are_the_map_types_and_nothing_else() -> void:
	# The two halves of the seam agreeing. `MapGenerator.pool_name()` is what GameScene
	# passes down and what _validate_variant_pools checks against; a rename on either
	# side that missed the other would silently draw the general mix forever.
	var names := MapGenerator.pool_names()
	assert_eq(names.size(), POOLS.size())
	for pool in POOLS:
		assert_true(names.has(pool), "%s is a real map type" % pool)


func test_the_variant_ids_do_not_have_to_match_their_filenames() -> void:
	# vis.field_1 is baked as vis.field_age2 and vis.field_4 as vis.farm, because
	# the art side named them before either of us knew they were variants. The
	# whole purpose of this file is that ids outlive filenames, and renaming the
	# staged files would be undone by the art agent's next staging run anyway.
	var fourth: AtlasEntry = reg.atlas_for(&"vis.field_4")
	assert_false(fourth.is_placeholder)
	assert_eq(fourth.id, &"vis.field_4", "the atlas answers to the id, not the file")
