## `scale` on a visuals.json entry (13.2b): the fourth axis of the asset seam, and the
## only one that is not about WHICH picture -- age, colour and variant all pick a file,
## and this one says how big to draw whatever was picked.
##
## It exists for one subject. `unit.dragon_baby` is the adult dragon at 20% (the owner's
## figure, settled 2026-09-04 against PLAN.md's stale 10% and a conversational 30%), and
## the alternative was a second 7.7 MB bake of frames identical to the first.
##
## ⚠️ **ALMOST NOTHING HERE CAN ASSERT ON PIXELS**, the same split `test_skins` draws:
## `game/assets/atlases/` is gitignored and a fresh clone has none of it. So the tests
## below assert on the SHIPPED DATA, which is always present, and the two that need a
## real atlas guard themselves on it being staged.
extends TestCase

const REGISTRY_SCRIPT := "res://src/autoload/game_data.gd"
const VISUALS_PATH := "res://data/visuals.json"

const BABY := &"vis.dragon_baby"
const ADULT := &"vis.dragon_rigged"

## The owner's number, and the one thing in this file that is a decision rather than a
## consequence of one.
const BABY_SCALE := 0.2

var reg: Node
var _visuals: Dictionary = {}


func before_each() -> void:
	reg = (load(REGISTRY_SCRIPT) as GDScript).new()
	reg.load_all()
	_visuals = JSON.parse_string(FileAccess.get_file_as_string(VISUALS_PATH))


func after_each() -> void:
	reg.free()


# ── the field reaches the resolved entry ───────────────────────────────────

func test_a_declared_scale_reaches_the_atlas_entry() -> void:
	var e: AtlasEntry = reg.atlas_for(BABY)
	assert_almost_eq(e.scale, BABY_SCALE)


func test_everything_that_declares_no_scale_is_drawn_at_one() -> void:
	# The default matters more than the value: `scale` is read by `EntityView._draw_frame`
	# on EVERY frame of EVERY entity, so a resolver that left it at 0.0 for the entries
	# that say nothing would collapse the whole game to a point.
	for id in _visuals:
		if id.begins_with("_") or (_visuals[id] as Dictionary).has("scale"):
			continue
		var e: AtlasEntry = reg.atlas_for(StringName(id))
		assert_almost_eq(e.scale, 1.0, 0.0001, id)


func test_exactly_one_entry_declares_a_scale_and_it_is_the_hatchling() -> void:
	# Not a rule that only one may -- a guard against `scale` spreading quietly. A second
	# one is a decision somebody should have to make on purpose, and it will land here.
	var scaled: Array[String] = []
	for id in _visuals:
		if not id.begins_with("_") and (_visuals[id] as Dictionary).has("scale"):
			scaled.append(id)
	assert_eq(scaled.size(), 1, str(scaled))
	assert_eq(scaled[0], "vis.dragon_baby")


# ── the two numbers that have to agree by hand ─────────────────────────────

func test_the_hatchlings_metres_match_its_scale() -> void:
	# ⚠️ THE ONE THING THIS FEATURE CANNOT DERIVE. `scale` moves the SPRITE; the selection
	# ring, the health dot's height and the placeholder box are all measured in METRES and
	# read `placeholder`, which is authored at the scaled size. visuals.json's
	# `_note_dragon_baby` argues why (deriving them would run the projection inversion on
	# numbers it was never measured for) -- and the cost of that choice is that the two
	# can drift, silently, into a 1.84 m dragon with a 9 m selection ring.
	#
	# This is the test that makes them agree. It is worth reading as the general form:
	# when a value is deliberately duplicated for a good reason, the good reason does not
	# keep the copies in step and something has to.
	var big: PlaceholderSpec = reg.placeholder_for(ADULT)
	var small: PlaceholderSpec = reg.placeholder_for(BABY)
	assert_almost_eq(small.footprint_m.x, big.footprint_m.x * BABY_SCALE, 0.01,
			"footprint x")
	assert_almost_eq(small.footprint_m.y, big.footprint_m.y * BABY_SCALE, 0.01,
			"footprint y")
	assert_almost_eq(small.height_m, big.height_m * BABY_SCALE, 0.01, "height")


func test_the_hatchling_is_bigger_than_a_villager_and_far_smaller_than_its_mother() -> void:
	# What 20% was chosen to BE, rather than what it computes to: obviously a juvenile,
	# obviously not vermin, and still findable at the zoom a phone plays at.
	var baby: PlaceholderSpec = reg.placeholder_for(BABY)
	var villager: PlaceholderSpec = reg.placeholder_for(&"vis.villager")
	var adult: PlaceholderSpec = reg.placeholder_for(ADULT)
	assert_true(baby.footprint_m.x > villager.footprint_m.x,
			"a hatchling is not smaller than the woman who finds it")
	assert_true(baby.footprint_m.x < adult.footprint_m.x * 0.5,
			"and unmistakably not its mother")


# ── it shares the adult's atlas and stays its own entry ────────────────────

func test_the_hatchling_names_the_adults_atlas_and_no_bake_of_its_own() -> void:
	# The saving this whole mechanism exists for. `vis.dragon_rigged` is the single
	# largest visual in the game at 7.7 MB; a 20% copy of it would be 7.7 MB of the same
	# frames drawn smaller.
	assert_eq(String((_visuals[String(BABY)] as Dictionary)["atlas"]),
			String((_visuals[String(ADULT)] as Dictionary)["atlas"]))


func test_sharing_an_atlas_does_not_share_a_scale() -> void:
	# ⚠️ THE FAILURE THIS GUARDS IS A CACHE ONE AND IT WOULD BE INVISIBLE. `_resolve`
	# writes `scale` onto the entry it hands back, and `atlas_for` caches per (id, age,
	# colour) -- so the two entries are two objects despite parsing the same file. Had the
	# cache been keyed on the atlas PATH instead, resolving the hatchling would have
	# shrunk every adult dragon on the map, and only the second one drawn.
	var baby: AtlasEntry = reg.atlas_for(BABY)
	var adult: AtlasEntry = reg.atlas_for(ADULT)
	assert_ne(baby, adult, "two entries, not one")
	assert_almost_eq(baby.scale, BABY_SCALE)
	assert_almost_eq(adult.scale, 1.0)
	# Asked again, in the other order, because a cache that was going to be poisoned
	# would be poisoned by now.
	var adult_again: AtlasEntry = reg.atlas_for(ADULT)
	var baby_again: AtlasEntry = reg.atlas_for(BABY)
	assert_almost_eq(adult_again.scale, 1.0)
	assert_almost_eq(baby_again.scale, BABY_SCALE)


func test_the_two_resolve_to_the_same_frames_when_the_art_is_staged() -> void:
	# Guarded on the art being present, `test_skins`' own split. When it is, the two
	# entries must be the SAME PICTURE -- that is the claim "no new bake" makes, and it is
	# checkable rather than assumed.
	var baby: AtlasEntry = reg.atlas_for(BABY)
	var adult: AtlasEntry = reg.atlas_for(ADULT)
	if baby.is_placeholder or adult.is_placeholder:
		return
	assert_eq(baby.pages, adult.pages, "same pages")
	for clip in [&"idle", &"walk", &"attack", &"die"]:
		assert_eq(baby.frame_count(clip), adult.frame_count(clip), String(clip))


# ── the unit points at it ──────────────────────────────────────────────────

func test_the_hatchling_unit_uses_the_scaled_visual_and_the_mother_does_not() -> void:
	# The seam's other half: a unit names a visual id, and the id is where the size
	# lives. Swapping these two would give the mother a 1.84 m body and the hatchling a
	# 9 m one, with every test above still green.
	assert_eq(reg.unit(&"unit.dragon_baby").visual, BABY)
	assert_eq(reg.unit(&"unit.dragon").visual, ADULT)


func test_the_data_still_loads_clean() -> void:
	# Four separate tests elsewhere assert `load_warnings.is_empty()`, so a new unit that
	# is trainable nowhere and not flagged wildlife reds all four with a message naming
	# the wrong culprit. Asserted here too, beside the change that could cause it.
	assert_true(reg.load_warnings.is_empty(), str(reg.load_warnings))
