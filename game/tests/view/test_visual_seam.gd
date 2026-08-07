## Phase 0.2a: the asset seam itself (PLAN.md 2.1).
##
## The property under test is TOTALITY: atlas_for() must answer for every ID,
## including ones nobody declared, because that is what allows a gameplay phase
## to be built before its art exists and allows the game to boot with no asset
## pack mounted (PLAN.md 2.4, 3.2). A seam that returns null for a missing asset
## would push a null check into every call site and the guarantee would rot.
##
## These run against the real data/visuals.json rather than a fixture, on purpose:
## the shipped data being well-formed is itself worth failing the suite over.
extends TestCase

## Loaded by path rather than by class name: game_data.gd deliberately has no
## `class_name`, because one would shadow the autoload singleton of the same name.
const REGISTRY_SCRIPT := "res://src/autoload/game_data.gd"

var reg: Node


func before_each() -> void:
	# A fresh instance rather than the autoload singleton, so warnings collected
	# here cannot be polluted by whatever resolved during boot.
	reg = (load(REGISTRY_SCRIPT) as GDScript).new()
	reg.load_all()


func after_each() -> void:
	reg.free()


func test_the_shipped_data_files_load_without_warnings() -> void:
	assert_false(reg.visual_ids().is_empty(), "visuals.json declares at least one ID")
	assert_true(reg.load_warnings.is_empty(),
			"data files are not clean -- %s" % "; ".join(reg.load_warnings))


func test_every_id_declares_a_placeholder_so_the_pack_is_never_required() -> void:
	# The APK must be playable with no art pack (PLAN.md 3.2). That holds only if
	# every ID declares a placeholder, which is checked here rather than inferred
	# from what happens to be staged.
	for id in reg.visual_ids():
		var spec: PlaceholderSpec = reg.placeholder_for(id)
		assert_ne(spec.color, PlaceholderSpec.UNKNOWN_COLOR,
				"%s declares a real placeholder, not the magenta unknown" % id)
		assert_true(spec.footprint_m.x > 0.0 and spec.footprint_m.y > 0.0,
				"%s has a non-degenerate placeholder footprint" % id)


func test_every_declared_id_resolves_to_something_drawable() -> void:
	for id in reg.visual_ids():
		var entry: AtlasEntry = reg.atlas_for(id)
		assert_not_null(entry, "%s resolves" % id)
		if entry.is_placeholder:
			assert_not_null(entry.placeholder, "%s has a parsed placeholder spec" % id)
		else:
			assert_false(entry.frames.is_empty(), "%s resolved to an atlas with frames" % id)


func test_an_undeclared_id_resolves_to_a_loud_placeholder_not_to_null() -> void:
	var entry: AtlasEntry = reg.atlas_for(&"vis.does_not_exist")
	assert_not_null(entry, "atlas_for never returns null -- that is the whole contract")
	assert_true(entry.is_placeholder)
	assert_eq(entry.placeholder.color, PlaceholderSpec.UNKNOWN_COLOR,
			"an unknown visual is magenta so it reads as the bug it is")


func test_resolution_is_cached_so_spawning_does_not_reparse() -> void:
	# EntityViewPool.acquire() resolves on every entity entering view, so this is
	# a hot path, not a nicety.
	var a: AtlasEntry = reg.atlas_for(&"vis.villager")
	var b: AtlasEntry = reg.atlas_for(&"vis.villager")
	assert_eq(a, b, "the same ID hands back the same resolved instance")


func test_the_mvp_entity_visuals_are_all_declared() -> void:
	# PLAN.md 2.5's entity vocabulary, restricted to what the MVP in 10 needs.
	# Catches an ID renamed in one file and not the other.
	for id in [&"vis.villager", &"vis.town_center", &"vis.house", &"vis.tree",
			&"vis.gold_mine", &"vis.deer", &"terrain.grass"] as Array[StringName]:
		assert_true(reg.visual_ids().has(id), "%s is declared in visuals.json" % id)


func test_building_phase_visuals_exist_for_every_phase_a_building_can_be_in() -> void:
	# SimBuilding.Phase is foundation / complete / rubble (PLAN.md 6.2), and each
	# is a separate visual ID rather than a state of one atlas.
	for id in [&"vis.foundation_4x4", &"vis.foundation_8x8",
			&"vis.rubble_3x3", &"vis.rubble_town_center"] as Array[StringName]:
		assert_true(reg.visual_ids().has(id), "%s is declared" % id)


func test_placeholders_are_sized_from_measured_metres_not_left_at_defaults() -> void:
	# A placeholder's job is to occupy the space the real sprite will, so a
	# footprint left at the 1x1 default is a data bug. The town centre is the one
	# that matters most: PLAN.md 9 sketched 4x4 tiles before anything was measured
	# and the art came in at 7.75, so this pins the measured figure.
	# Read the DECLARED placeholder, not whatever atlas_for() resolved to. Once the
	# art pack is staged those IDs resolve to real atlases and carry no placeholder
	# at all -- and since game/assets/atlases/ is gitignored, whether that is true
	# differs between a fresh clone and a machine that has baked. A test that
	# changes its mind based on that is worse than no test.
	var tc := reg.placeholder_for(&"vis.town_center") as PlaceholderSpec
	assert_true(tc.footprint_m.x > 15.0,
			"town centre footprint is the measured ~15.5 m, not the pre-measurement 4 tiles")
	assert_true(tc.height_m > 1.0, "town centre has a real height")

	# 1.75 m is a deliberate INTENDED height, not the baked one. The atlas is 2.18 m
	# because she inherits 0 A.D.'s proportions, which makes her taller than a stag
	# (PLAN.md 13.2 item 9). The placeholder states what she should be, so the two
	# disagreeing is the tell that the rebake has not happened yet.
	var villager := reg.placeholder_for(&"vis.villager") as PlaceholderSpec
	assert_almost_eq(villager.height_m, 1.75, 0.01,
			"villager placeholder is her intended height, shorter than the 2.02 m deer")
	var deer := reg.placeholder_for(&"vis.deer") as PlaceholderSpec
	assert_true(villager.height_m < deer.height_m,
			"a villager must be shorter than a stag -- the whole point of item 9")


func test_declared_sound_ids_are_distinguishable_from_undeclared_ones() -> void:
	# Every stream is null in MVP (AudioManager is a no-op, PLAN.md 7.5), so the
	# only thing audio.json can be wrong about right now is its vocabulary.
	assert_true(reg.has_sfx(&"villager.chop"), "an ASSET_MISSING 1.6 ID is declared")
	assert_false(reg.has_sfx(&"villager.yodel"), "an undeclared ID is not silently accepted")
	assert_true(reg.has_music(&"menu.theme"))
