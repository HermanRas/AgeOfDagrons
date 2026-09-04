## PLAN.md 16.1's deliverable: the tool reads the game's roster, and the numbers are right.
##
## *"If that number is wrong, nothing built on top of it can be right."* So the assertions
## here are about the roster being REAL — read out of the game's own `data/*.json` — and
## about the two calls `format/map_data.gd` makes into it, which are what decide whether a
## placement overlaps.
##
## ⚠️ **COUNTS ARE ASSERTED AS FLOORS, NOT AS EXACT NUMBERS.** The roster is content the
## owner and the art side add to — buildings went 23 → 31 inside a fortnight — and a test
## pinning the exact figure is a test that goes red for a reason nobody wants to hear about.
## `test_campaign_screen` learned the same thing about scenario counts, and 15.8's own note
## records a constant that broke six tests the day content was added. A floor still catches
## the failure that matters: a roster that came back empty.
extends TestCase

var _root: GameRoot = null


func before_each() -> void:
	_root = GameRoot.resolve()
	# The autoload is a singleton, so every test in this file shares one loaded roster.
	# Reloaded per test anyway: it is a few JSON parses, and a test that mutated it would
	# otherwise poison whichever ran next.
	GameDataRegistry.load_from(_root)


func test_the_game_project_is_found_without_any_setup() -> void:
	# `game/` is a sibling of `MapMaker/`, so a fresh clone needs no config file -- which is
	# the whole argument in `GameRoot`. A setup step nobody performs is why the game's UI
	# folder was gitignored for months.
	assert_false(_root.path.is_empty(),
			"; ".join(PackedStringArray(_root.problems)))
	assert_true(_root.path.ends_with("game"), "resolved to: " + _root.path)


func test_the_roster_loads_from_the_real_game_data() -> void:
	assert_true(GameDataRegistry.is_loaded(),
			"; ".join(PackedStringArray(GameDataRegistry.load_warnings)))
	assert_eq(GameDataRegistry.load_warnings, [] as Array[String],
			"reading the roster should produce no complaints")


## ⚠️ **THE `_note` BLOCKS IN `data/*.json` ARE DOCUMENTATION AND MUST NOT BE READ AS
## ENTRIES.** They are the real design record for the data (AGENT_GAME_CODER.md §2) and they
## are strings where an entry would be an object -- so a loader that does not skip them
## reports two warnings on a perfectly good roster and puts a `_note` in the palette.
##
## **This test is why the loader is right.** The first version of it did not skip them and
## the failure was the only reason the convention was found; the fix was to mirror
## `GameDataRegistry._read_json` rather than to widen this assertion.
func test_the_documentation_blocks_are_not_roster_entries() -> void:
	for id in GameDataRegistry.building_ids():
		assert_false(String(id).begins_with("_"), "%s is a comment key, not a building" % id)
	for id in GameDataRegistry.resource_ids():
		assert_false(String(id).begins_with("_"), String(id))
	for id in GameDataRegistry.unit_ids():
		assert_false(String(id).begins_with("_"), String(id))
	# And the file really does contain one, or the loop above proves nothing.
	var raw := FileAccess.get_file_as_string(_root.data_path("buildings.json"))
	assert_true(raw.contains("\"_note\""),
			"buildings.json should still carry its design notes")


## Floors, per the class comment. Each is well under the count at the time of writing
## (units 30+, buildings 31, resources 20+) and well over zero.
func test_every_category_comes_back_populated() -> void:
	assert_true(GameDataRegistry.unit_ids().size() >= 10,
			"units: %d" % GameDataRegistry.unit_ids().size())
	assert_true(GameDataRegistry.building_ids().size() >= 10,
			"buildings: %d" % GameDataRegistry.building_ids().size())
	assert_true(GameDataRegistry.resource_ids().size() >= 5,
			"resources: %d" % GameDataRegistry.resource_ids().size())


## ⚠️ **THE TERRAIN COUNT IS THE ONE EXACT NUMBER WORTH PINNING**, and it is not content: it
## is the byte written into `map.png`'s red channel, so an eighth kind is a format change and
## `MapFile` would reject every existing map. Seven, from the enum in the guarded copy.
func test_terrain_comes_off_the_enum_and_there_are_seven_kinds() -> void:
	var kinds := GameDataRegistry.terrain_kinds()
	assert_eq(kinds.size(), 7)
	assert_eq(kinds.size(), SimMap.Terrain.size(), "read off the enum, not a written list")
	assert_eq(String(kinds[0]), "GRASS", "and in enum order, which is the on-disk order")


# ── the two calls the verbatim copy makes ───────────────────────────────────

## `MapData.footprint_rect_of()` calls exactly these two, and this is what makes the copy
## work unedited. If either name or return type changes, the copy stops resolving.
func test_a_building_comes_back_typed_with_a_footprint() -> void:
	var ids := GameDataRegistry.building_ids()
	assert_true(ids.size() > 0)
	if ids.is_empty():
		return
	var b := GameDataRegistry.building(ids[0])
	assert_not_null(b)
	if b == null:
		return
	assert_true(b.footprint.x >= 1 and b.footprint.y >= 1,
			"%s footprint %s" % [ids[0], b.footprint])


func test_a_resource_comes_back_typed_and_sizes_its_footprint() -> void:
	var ids := GameDataRegistry.resource_ids()
	assert_true(ids.size() > 0)
	if ids.is_empty():
		return
	var r := GameDataRegistry.resource_def(ids[0])
	assert_not_null(r)
	if r == null:
		return
	# `size_class` is the fourth argument to `MapData.add_entity` and the input to this --
	# 16.3's palette needs a selector for it, and an out-of-range class must clamp rather
	# than fail, because a hand-edited map file can carry any integer.
	assert_true(r.footprint_for_size(0).x >= 1)
	assert_eq(r.footprint_for_size(99), r.footprint_for_size(0),
			"an out-of-range size class clamps, it does not explode")


## **NULL FOR AN UNKNOWN ID**, which is the game registry's own rule and the opposite of
## `atlas_for()`: a missing sprite has a sensible stand-in, a missing definition does not.
## `MapData` relies on it -- `footprint_rect_of` falls through to 1x1 for a unit precisely
## because both lookups return null.
func test_an_unknown_id_is_null_rather_than_a_stand_in() -> void:
	assert_null(GameDataRegistry.building(&"building.does_not_exist"))
	assert_null(GameDataRegistry.resource_def(&"res.does_not_exist"))


## THE PAYOFF OF THE STAND-IN, in one assertion: a verbatim copy of the game's `MapData`
## computes a real footprint inside this project, with no edit and no game autoload.
func test_map_data_resolves_footprints_through_the_stand_in() -> void:
	var ids := GameDataRegistry.building_ids()
	if ids.is_empty():
		fail("no buildings to place")
		return
	var id := ids[0]
	var footprint := GameDataRegistry.building(id).footprint
	var m := MapData.create(Vector2i(20, 20), SimMap.Terrain.GRASS)
	m.add_entity(id, 1, Vector2i(3, 4))
	assert_eq(m.claimed_tiles().size(), footprint.x * footprint.y,
			"a %s claims %s tiles" % [id, footprint])


# ── listing rules the palette depends on ────────────────────────────────────

## ⚠️ `Array[StringName].sort()` orders by IDENTITY, not by spelling, and not stably between
## runs -- PLAN.md 16.3 carries the warning. A palette that reshuffles itself between
## launches looks broken, so the ids are sorted as text explicitly.
func test_ids_are_sorted_as_text_and_stably() -> void:
	var ids := GameDataRegistry.building_ids()
	var as_text: Array[String] = []
	for id in ids:
		as_text.append(String(id))
	var expected := as_text.duplicate()
	expected.sort()
	assert_eq(as_text, expected, "building ids are in text order")

	# Stable across a reload, which is the half a single sorted read cannot show.
	GameDataRegistry.load_from(_root)
	var again: Array[String] = []
	for id in GameDataRegistry.building_ids():
		again.append(String(id))
	assert_eq(again, as_text)


## A row labelled "" is a row nobody can pick, so the id stands in for a missing name.
func test_a_label_never_comes_back_empty() -> void:
	for id in GameDataRegistry.building_ids():
		assert_false(GameDataRegistry.display_name(id).is_empty(), String(id))
	for id in GameDataRegistry.resource_ids():
		assert_false(GameDataRegistry.display_name(id).is_empty(), String(id))


## ⚠️ **`ResourceDef` HAS NO `name` FIELD**, and reaching for `.name` on one compiles and
## returns the Object's class name at runtime rather than failing -- which would have put
## "RefCounted" in the palette beside every tree. So labels are read off the raw JSON, and
## this asserts none of them came back as a class name.
func test_a_resource_label_is_not_an_object_name() -> void:
	for id in GameDataRegistry.resource_ids():
		var label := GameDataRegistry.display_name(id)
		assert_ne(label, "RefCounted", String(id))
		assert_ne(label, "ResourceDef", String(id))


func test_an_unknown_id_is_labelled_by_itself() -> void:
	assert_eq(GameDataRegistry.display_name(&"nothing.at.all"), "nothing.at.all")


# ── failure modes, because this reads somebody else's machine ───────────────

## A path that is not the game project is REPORTED, not guessed at. Every marker is named,
## so pointing at the repo root instead of at `game/` says so rather than coming back as an
## empty palette.
func test_a_wrong_path_is_refused_with_a_reason() -> void:
	var root := GameRoot.new()
	root.path = ""
	assert_false(GameDataRegistry.load_from(root))
	assert_true(GameDataRegistry.load_warnings.size() >= 1)

	var resolved := GameRoot.resolve()
	assert_false(resolved.path.is_empty())
	# And the marker list has to be able to tell the repo root apart from `game/`, which is
	# the mistake somebody setting `mapmaker.local.json` will actually make.
	var repo_root := resolved.path.path_join("..").simplify_path()
	var missing := GameRoot.new()._missing_markers(repo_root)
	assert_true(missing.size() >= 1, "the repo root must not pass as the game project")
