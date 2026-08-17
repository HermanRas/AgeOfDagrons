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


func test_the_variant_ids_do_not_have_to_match_their_filenames() -> void:
	# vis.field_1 is baked as vis.field_age2 and vis.field_4 as vis.farm, because
	# the art side named them before either of us knew they were variants. The
	# whole purpose of this file is that ids outlive filenames, and renaming the
	# staged files would be undone by the art agent's next staging run anyway.
	var fourth: AtlasEntry = reg.atlas_for(&"vis.field_4")
	assert_false(fourth.is_placeholder)
	assert_eq(fourth.id, &"vis.field_4", "the atlas answers to the id, not the file")
