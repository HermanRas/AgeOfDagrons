## The skin axis of the asset seam (PLAN.md 2.7.1): one visual ID resolved
## through an AGE (which building skin) and a COLOUR (which player's bake).
##
## Two things make this worth its own file rather than more of test_visual_seam.
## The first is that colour is not decoration here -- it is the ONLY thing
## distinguishing one player from another (PLAN.md 1), so resolving it to the
## wrong atlas is a gameplay defect, not a cosmetic one. The second is that
## almost nothing here can assert on pixels: `game/assets/atlases/` is gitignored
## and a fresh clone has none of it, so every test below either asserts on the
## SHIPPED DATA (always present) or guards itself on the art being staged, the
## same split test_visual_seam already draws.
extends TestCase

const REGISTRY_SCRIPT := "res://src/autoload/game_data.gd"
const VISUALS_PATH := "res://data/visuals.json"

var reg: Node
var _visuals: Dictionary = {}


func before_each() -> void:
	reg = (load(REGISTRY_SCRIPT) as GDScript).new()
	reg.load_all()
	_visuals = JSON.parse_string(FileAccess.get_file_as_string(VISUALS_PATH))


func after_each() -> void:
	reg.free()


## The entries carrying a skin axis, read straight from the file. The registry
## deliberately does not expose the raw declarations -- callers get a resolved
## AtlasEntry -- but asserting the shipped data is well-formed means reading what
## was shipped, and these tests are the only thing that should.
func _entries_with(key: String) -> Array[String]:
	var out: Array[String] = []
	for id in _visuals:
		if id.begins_with("_"):
			continue
		if (_visuals[id] as Dictionary).has(key):
			out.append(id)
	out.sort()
	return out


# ── totality survives both axes ─────────────────────────────────────────────

func test_every_id_still_resolves_under_every_age_and_colour() -> void:
	# atlas_for()'s contract is TOTALITY (test_visual_seam), and adding two
	# optional axes is exactly the change that could quietly break it for the
	# combinations nobody happened to try -- an entry with a sparse `ages` map,
	# or a colour whose bake is not staged, must still hand back something
	# drawable rather than null.
	for id in reg.visual_ids():
		for age in [0, 1, 2, 3, 4]:
			for colour in [-1, 0, 3, 7]:
				var entry: AtlasEntry = reg.atlas_for(id, age, colour)
				assert_not_null(entry, "%s resolves at age %d colour %d" % [id, age, colour])
				if entry.is_placeholder:
					assert_not_null(entry.placeholder,
							"%s has a parsed placeholder at age %d" % [id, age])
				else:
					assert_false(entry.frames.is_empty(),
							"%s resolved to an atlas with frames" % id)


func test_an_out_of_range_age_or_colour_falls_back_rather_than_failing() -> void:
	# Age 9 and colour 99 are nonsense, and the answer to nonsense is the base
	# bake, not a crash and not the magenta unknown -- the same call
	# GameDataRegistry.colour() already makes for an out-of-range palette index.
	var absurd: AtlasEntry = reg.atlas_for(&"vis.villager", 9, 99)
	assert_not_null(absurd)
	assert_eq(absurd.id, &"vis.villager")


func test_resolution_is_cached_per_skin_not_per_id() -> void:
	# EntityViewPool resolves on every entity entering view, so re-parsing an
	# atlas per spawn is the thing this cache exists to prevent. Adding the skin
	# axes must not have turned the cache into a single-entry one that thrashes
	# between two players' units.
	var a: AtlasEntry = reg.atlas_for(&"vis.villager", 0, 1)
	var b: AtlasEntry = reg.atlas_for(&"vis.villager", 0, 1)
	assert_eq(a, b, "the same skin hands back the same resolved instance")

	var bare_a: AtlasEntry = reg.atlas_for(&"vis.villager")
	var bare_b: AtlasEntry = reg.atlas_for(&"vis.villager")
	assert_eq(bare_a, bare_b, "the no-skin call is still cached")


# ── the colour palette and its slugs ────────────────────────────────────────

func test_colour_slugs_are_index_aligned_with_the_palette() -> void:
	# The slug picks the ATLAS and the Color paints the HUD, and they are read
	# from the same colours.json entry. Drifting apart by one would tint a
	# player's minimap blip one colour and draw their units in another -- which,
	# colour being the only player difference, is unplayable rather than untidy.
	assert_eq(reg.colour_count(), 8, "eight players, eight slots (PLAN.md 3.1)")
	var expected := [&"blue", &"red", &"yellow", &"cyan",
			&"green", &"violet", &"orange", &"white"]
	for i in range(expected.size()):
		assert_eq(reg.colour_slug(i), expected[i],
				"slot %d is %s -- ORDER IS LOAD-BEARING, saves index into it" % [i, expected[i]])


func test_colour_slug_wraps_rather_than_returning_nothing() -> void:
	assert_eq(reg.colour_slug(8), reg.colour_slug(0), "wraps like colour() does")
	assert_eq(reg.colour_slug(-1), reg.colour_slug(7), "including downwards")


# ── the shipped skin declarations ───────────────────────────────────────────

func test_every_age_map_names_all_four_ages() -> void:
	# Density is the contract (PLAN.md 2.7.1) and it is enforced in validate(),
	# which the suite already asserts comes back clean -- but only for entries
	# that HAVE an `ages` map. This is the other half: that the entries which
	# should have one, do.
	var aged := _entries_with("ages")
	assert_false(aged.is_empty(), "some visuals carry an age map")
	for id in aged:
		var m: Dictionary = (_visuals[id] as Dictionary)["ages"]
		for age in range(1, reg.age_count() + 1):
			assert_true(m.has(str(age)), "%s names an age-%d skin" % [id, age])


func test_every_building_with_a_baked_age_variant_declares_the_age_map() -> void:
	# The failure this catches is a building wired to its age-1 bake and left
	# there: it renders correctly, never reports anything, and simply never
	# modernises as its owner advances -- which is the whole of PLAN.md 2.7.
	#
	# THE FIELD IS EXEMPT, and named rather than inferred so a second exemption has
	# to be a deliberate edit. Its four bakes are still FILED as vis.field_age2/3/4
	# and vis.farm, but the project owner's reading of them (2026-08-17) is that
	# they are four crops rather than four ages -- a plot does not re-sow itself
	# when Rome arrives. It carries `variants` instead, and the two are mutually
	# exclusive by _validate_variants().
	const NOT_AGE_SKINNED := [&"building.field"]

	## ⚠️ **NOBODY OWNS A DRAGON NEST, SO NOBODY ADVANCES IT** (added 2026-09-04, PLAN.md
	## 13.2). This is the deliberate second exemption the comment above asks for, and it is a
	## different KIND from the field's: the field has four bakes that are not ages, whereas the
	## nest is a gaia map POI (`buildable: false`) with **one** bake and no owner. The rule
	## this test enforces is "it must modernise as its owner advances", and a henge of standing
	## stones has no owner to advance — it is not going to be rebuilt in brick when Rome
	## arrives. So it carries neither an age map nor variants, and both absences are asserted
	## rather than merely skipped.
	const UNOWNED_POI := [&"building.dragon_nest"]

	var aged := _entries_with("ages")
	var varied := _entries_with("variants")
	for building_id in reg.building_ids():
		var bd: BuildingDef = reg.building(building_id)
		if UNOWNED_POI.has(building_id):
			assert_false(bd.buildable,
					"%s is exempt because nobody owns it, so it must not be buildable"
					% building_id)
			assert_false(aged.has(String(bd.visual)),
					"%s's visual %s has no owner to age with" % [building_id, bd.visual])
			assert_false(varied.has(String(bd.visual)),
					"%s's visual %s has one bake, not a set" % [building_id, bd.visual])
			continue
		if NOT_AGE_SKINNED.has(building_id):
			assert_true(varied.has(String(bd.visual)),
					"%s's visual %s offers interchangeable variants" % [building_id, bd.visual])
			assert_false(aged.has(String(bd.visual)),
					"%s's visual %s is not age-skinned as well" % [building_id, bd.visual])
			continue
		assert_true(aged.has(String(bd.visual)),
				"%s's visual %s carries an age map" % [building_id, bd.visual])


func test_units_carry_the_colour_flag_and_buildings_do_not_yet() -> void:
	# Player colour is baked into the atlas, not shaded at runtime, so a unit
	# without this flag silently draws every player's copy identical -- the exact
	# failure PLAN.md 1 says the game cannot have. Buildings have no per-colour
	# bake yet, and claiming otherwise would make every one of them fall back to
	# untinted through a path that looks like it worked.
	# Two units genuinely cannot be tinted, and the exemptions are named rather
	# than inferred so adding a third is a deliberate edit here:
	#   unit.dragon   -- MEASURED, not assumed: white against blue moved 0 of 5,567 opaque
	#                    pixels. 0 A.D.'s dragon carries no playercolour mask, and the rigged
	#                    bake goes through an adapter with no `player_colour` path at all, so
	#                    a mask appearing tomorrow would still not be enough. (The comment
	#                    here said "bespoke art", which was wrong twice over -- it is 0 A.D.'s
	#                    own fauna/dragon.xml.)
	#   unit.ballista -- 0 A.D. puts NO player colour on any siege engine; its
	#                    eight tint passes measured 0.0%, i.e. eight copies of one
	#                    picture. unit.onager only escapes this because its actor
	#                    mounts crew props that do carry a mask.
	const UNTINTABLE := [&"unit.dragon", &"unit.ballista"]

	var tinted := _entries_with("colours")
	for unit_id in reg.unit_ids():
		var ud: UnitDef = reg.unit(unit_id)
		# ⚠️ **THE NAMED EXEMPTIONS ARE TESTED FIRST, AND THE ORDER STOPPED BEING COSMETIC
		# ON 2026-09-04.** The dragon became `is_wildlife` that day (she is gaia's guardian
		# at the nest, PLAN.md 13.2), so the wildlife branch below would have swallowed her
		# -- and its reason does not apply to her. Wildlife is exempt because *"there is no
		# player whose colour it could wear"*, and **a dragon CAN come to be owned**: killing
		# the mother and holding the nest hands the grown baby to a player. She is exempt for
		# the other reason entirely, which is that the art has no mask. Same assertion, wrong
		# explanation, and the explanation is the part a reader acts on.
		if UNTINTABLE.has(unit_id):
			assert_false(tinted.has(String(ud.visual)),
					"%s claims no colour bake it has not got" % unit_id)
			continue
		# WILDLIFE IS SKIPPED BY RULE, not added to the list above, and the difference
		# matters. The two exemptions are facts about particular art -- somebody could
		# bake the dragon a mask tomorrow. A wolf is owner 0's and stays owner 0's: there is
		# no player whose colour it could wear, so there is nothing to bake and never will be.
		if ud.is_wildlife:
			assert_false(tinted.has(String(ud.visual)),
					"%s is gaia's and has no colour to wear" % unit_id)
			continue
		assert_true(tinted.has(String(ud.visual)),
				"%s's visual %s declares per-colour bakes" % [unit_id, ud.visual])

	for building_id in reg.building_ids():
		var bd: BuildingDef = reg.building(building_id)
		assert_false(tinted.has(String(bd.visual)),
				"%s does not claim a colour bake it has not got" % building_id)


# ── behaviour that needs the art pack staged ────────────────────────────────

func test_two_players_draw_different_atlases_when_the_colours_are_staged() -> void:
	# The point of the whole mechanism, and the one thing only real files can
	# show. Guarded on the COLOUR bakes specifically, not on the pack as a whole:
	# as of writing, `assets/atlases/` holds the phase-0.4 staging, which has
	# `vis.villager` but none of `vis.villager.<colour>`, so guarding on "is the
	# base atlas staged" would have made this fail for a reason that is not a
	# defect in this code. `game/assets/atlases/` is gitignored, so what is on
	# disk differs between a fresh clone and a machine that has baked, and a test
	# must not change its mind based on that.
	var gaps: Array = reg.missing_colour_atlases()
	var villager_incomplete: bool = (reg.atlas_for(&"vis.villager") as AtlasEntry).is_placeholder
	for gap in gaps:
		if StringName((gap as Dictionary)["visual"]) == &"vis.villager":
			villager_incomplete = true
	if villager_incomplete:
		assert_true(true, "villager colour bakes not staged -- nothing to compare")
		return

	var p1: AtlasEntry = reg.atlas_for(&"vis.villager", 0, 0)
	var p2: AtlasEntry = reg.atlas_for(&"vis.villager", 0, 1)
	assert_false(p1.is_placeholder)
	assert_false(p2.is_placeholder)
	assert_ne(p1.pages[0], p2.pages[0],
			"player 1 and player 2 draw from different pages, or they are the same player")


func test_missing_colour_bakes_are_enumerable_rather_than_silent() -> void:
	# A tint with no file falls back to the untinted bake, which renders a unit
	# belonging to nobody. That is the right runtime behaviour -- the match still
	# plays -- but it must be findable, so this asserts the diagnostic answers
	# rather than asserting any particular gap is or is not present.
	var missing: Array = reg.missing_colour_atlases()
	assert_not_null(missing)
	for entry in missing:
		assert_true((entry as Dictionary).has("visual"))
		assert_true((entry as Dictionary).has("colour"))
		assert_eq(reg.colour_slug(int(entry["colour"])), entry["slug"],
				"the reported slug matches the reported index")


func test_stale_colour_bakes_are_enumerable_too() -> void:
	# The harder half, and the one the art agent asked for: a colour atlas that is
	# PRESENT and parses and draws, but predates a pipeline fix, so it renders
	# wrongly while looking healthy. Absence is loud; staleness is not.
	#
	# Asserts the contract, not a count -- what is stale on disk changes with
	# every bake run, and `game/assets/atlases/` is gitignored, so a pinned number
	# would fail on a fresh clone and again after the next batch.
	var stale: Array = reg.stale_colour_atlases()
	assert_not_null(stale)
	for entry in stale:
		var e: Dictionary = entry
		assert_true(e.has("visual") and e.has("colour") and e.has("slug"))
		assert_eq(reg.colour_slug(int(e["colour"])), e["slug"])
		# Every report names what the file says and what its siblings say, so it
		# can be acted on without re-deriving the comparison by hand.
		assert_true(e.has("identity") and e.has("expected"))
		assert_true(String(e["identity"]) != String(e["expected"])
						or String(e["identity"]) == "unknown",
				"only reported for disagreeing with its set, or for broken provenance")


func test_a_uniformly_unstamped_set_is_not_stale() -> void:
	# The rule that replaced the modification-time one, and the reason it had to.
	# The old rule flagged anything more than an hour older than its newest
	# sibling, which held only while the wrong files were also the old files. Once
	# the roster completed it named red and yellow -- the two known-GOOD colours,
	# rebaked first -- for 14 units: 34 reports, every one a file to trust.
	#
	# Under uniformity, a set that agrees is silent however old it is, so the 323
	# atlases staged before isobake began stamping a build id report nothing.
	# Nothing unstamped can postdate the stamp, so "absent" is a comparable value
	# rather than a gap.
	#
	# The unconditional assertion is load-bearing to the HARNESS, not to the
	# claim: with the art currently staged this list is empty, and a test whose
	# every assertion is inside a loop over an empty list runs none at all and is
	# reported as a failure rather than a pass.
	var stale: Array = reg.stale_colour_atlases()
	assert_not_null(stale)
	for e in stale:
		assert_ne(String((e as Dictionary)["identity"]), "unstamped",
				"%s is unstamped and so are its siblings; that is uniform, not stale"
						% (e as Dictionary)["visual"])


func test_stale_and_missing_are_disjoint() -> void:
	# A file cannot be both absent and out of date, and reporting one twice would
	# make the two counts impossible to reconcile against a bake queue.
	var absent: Array = []
	for e in reg.missing_colour_atlases():
		absent.append("%s|%d" % [(e as Dictionary)["visual"], int((e as Dictionary)["colour"])])
	# Both lists are empty with the art as currently staged, so without this the
	# test would run no assertions at all and be reported as a failure.
	assert_not_null(absent)
	for e in reg.stale_colour_atlases():
		var key := "%s|%d" % [(e as Dictionary)["visual"], int((e as Dictionary)["colour"])]
		assert_false(absent.has(key), "%s is reported as stale OR missing, never both" % key)
