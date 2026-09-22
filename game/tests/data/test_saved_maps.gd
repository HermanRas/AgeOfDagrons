## PLAN.md 16.0: finding the saved maps a player can start a match on.
##
## **THE INTERESTING ASSERTIONS ARE NOT ABOUT LISTING FILES.** They are about
## `_players_in()` -- how many players a map can actually seat -- because that figure is a
## correctness gate rather than a label. `MapGen.build_from()` gives a player a town centre
## and villagers only by spawning the entities the map LISTS for their index, and never
## falls back to `_start_origin()`, so a lobby that starts one player over a map's count
## opens with somebody alive and owning nothing.
##
## Everything here works in `user://`, never in `maps/` or `scenarios/`: the shipped maps are
## authored content under version control, and a test that wrote into them would be a test
## that edits the game. Same rule as `test_map_file`.
extends TestCase

const ROOT := "user://test_saved_maps"

var _n := 0


## ⛔ THE CASE DIRECTORY IS WIPED, AND IT HAS TO BE -- `case_N` IS A RUN-TO-RUN NAME.
##
## `_n` is a test INDEX, and `user://` survives between runs, so `case_3` is whatever the
## third test wrote *last time* until this run overwrites it. That is stable only while the
## file's test list never changes -- and the moment 2.4c added tests, the third test became a
## different test and inherited a stale map from the old one. It failed as
## *"expected From Meta, got Lopsided"*: a map from another test, in another run, read back as
## this one's.
##
## ⚠️ **A LEFTOVER DIRECTORY IS THEREFORE A FALSE PASS AS EASILY AS A FALSE FAILURE** -- a
## test asserting a map IS listed would have been handed one by its predecessor. Wiping first
## rather than cleaning up afterwards is what makes that independent of how the last run ended,
## including a crash.
func before_each() -> void:
	_n += 1
	_wipe(_root())


func _root() -> String:
	return "%s/case_%d" % [ROOT, _n]


## Remove a directory and everything under it. `DirAccess.remove_absolute` refuses a
## non-empty directory, so the files go first and the walk is depth-first.
func _wipe(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for sub in dir.get_directories():
		_wipe(path.path_join(sub))
	DirAccess.remove_absolute(path)


## Write a map into `<root>/<folder>`, with `header` merged into its sidecar.
func _write(folder: String, data: MapData, header: Dictionary = {}) -> String:
	var dir := _root().path_join(folder)
	DirAccess.make_dir_recursive_absolute(dir)
	var problems := MapFile.save(data, dir, header)
	assert_eq(problems, [] as Array[String])
	return dir


## A two-player map: two starts, and entities naming players 1 and 2.
func _two_player_map() -> MapData:
	var m := MapData.create(Vector2i(12, 10), SimMap.Terrain.GRASS)
	m.add_entity(&"building.town_center", 1, Vector2i(1, 1))
	m.add_entity(&"building.town_center", 2, Vector2i(8, 6))
	m.add_entity(&"res.tree", 0, Vector2i(4, 4))
	m.starts.append(Vector2i(1, 1))
	m.starts.append(Vector2i(8, 6))
	return m


# ── the seat count, which is the load-bearing part ──────────────────────────

func test_a_two_player_map_seats_two() -> void:
	_write("duel", _two_player_map(), {"name": "Duel Valley"})
	var rows := _discover_in(_root())
	assert_eq(rows.size(), 1)
	assert_eq(int(rows[0]["players"]), 2)
	assert_eq(str(rows[0]["name"]), "Duel Valley")


## THE CASE THE SEAT COUNT EXISTS FOR, and the one `starts.size()` alone gets wrong.
##
## A map with three starts but only two players' worth of buildings seats TWO: the third
## player would be handed nothing by `MapGen.build_from()`. Asserting the smaller of the two
## figures rather than either one on its own is the whole rule.
func test_a_third_start_with_no_base_behind_it_does_not_add_a_seat() -> void:
	var m := _two_player_map()
	m.starts.append(Vector2i(10, 2))     # a start nobody is given a base at
	_write("lopsided", m, {"name": "Lopsided"})
	var rows := _discover_in(_root())
	assert_eq(rows.size(), 1)
	assert_eq(int(rows[0]["players"]), 2)


## And the mirror of it: a base for a player the map never gave a start to. The validator
## measures connectivity BETWEEN STARTS, so a player with no start has nowhere anybody has
## checked a path to -- and counting them would seat a player onto an unreachable corner.
func test_a_base_with_no_start_behind_it_does_not_add_a_seat() -> void:
	var m := _two_player_map()
	m.add_entity(&"building.town_center", 3, Vector2i(10, 2))
	_write("phantom", m, {"name": "Phantom"})
	var rows := _discover_in(_root())
	assert_eq(int(rows[0]["players"]), 2)


## A map with starts and no player-owned entities at all seats NOBODY, and is still listed.
##
## Listed rather than hidden, on `CampaignScreen`'s rule: a map that vanishes from a list is
## indistinguishable from a map the game failed to find, and the player has a folder on disk
## they can see. `can_start()` is what refuses it.
func test_a_map_with_no_bases_seats_nobody_and_is_still_listed() -> void:
	var m := MapData.create(Vector2i(8, 8), SimMap.Terrain.GRASS)
	m.starts.append(Vector2i(1, 1))
	m.starts.append(Vector2i(6, 6))
	_write("empty", m, {"name": "Bare"})
	var rows := _discover_in(_root())
	assert_eq(rows.size(), 1)
	assert_eq(int(rows[0]["players"]), 0)


# ── naming ──────────────────────────────────────────────────────────────────

## The folder stands in for a missing name, because a row labelled "" cannot be picked.
func test_a_map_with_no_name_is_labelled_by_its_folder() -> void:
	_write("nameless_valley", _two_player_map())
	var rows := _discover_in(_root())
	assert_eq(str(rows[0]["name"]), "nameless_valley")


## `MapFile.save()` merges its header into the sidecar's TOP level, while a `MapData` carries
## its own `meta`. Both are legitimate places for a name and a picker must not care which.
func test_a_name_nested_in_meta_is_found_too() -> void:
	var m := _two_player_map()
	m.meta = {"name": "From Meta"}
	_write("nested", m)
	var rows := _discover_in(_root())
	assert_eq(str(rows[0]["name"]), "From Meta")


# ── listing rules ───────────────────────────────────────────────────────────

## Alphabetical within a root, because `DirAccess` order is a filesystem detail and a list
## that reshuffles between runs looks broken.
func test_maps_are_listed_alphabetically_by_folder() -> void:
	_write("zulu", _two_player_map(), {"name": "Zulu"})
	_write("alpha", _two_player_map(), {"name": "Alpha"})
	_write("mike", _two_player_map(), {"name": "Mike"})
	var rows := _discover_in(_root())
	var names: Array[String] = []
	for r in rows:
		names.append(str(r["name"]))
	assert_eq(names, ["Alpha", "Mike", "Zulu"] as Array[String])


## An unreadable sidecar is a WARNING and the row is dropped -- not a crash, and not a
## silently missing map. A directory sitting in `maps/` that the game says nothing about is
## the failure this avoids.
func test_an_unreadable_map_warns_and_is_skipped() -> void:
	_write("good", _two_player_map(), {"name": "Good"})
	var broken := _root().path_join("broken")
	DirAccess.make_dir_recursive_absolute(broken)
	var f := FileAccess.open(broken.path_join(MapFile.META_FILE), FileAccess.WRITE)
	assert_not_null(f)
	if f == null:
		return
	f.store_string("{ this is not json")
	f.close()

	var loader := SavedMaps.new()
	var rows := _rows_from(loader, _root())
	assert_eq(rows.size(), 1)
	assert_eq(str(rows[0]["name"]), "Good")
	assert_true(loader.warnings.size() >= 1,
			"an unreadable sidecar should be reported, not silently dropped")


## A map from a newer format is refused by the LISTING and not only by the loader.
##
## `MapFile._parse_sidecar` version-checks in both directions on purpose: a picker that
## listed a version-2 map because only the full loader checked would offer a row that fails
## the moment it is pressed.
func test_a_future_format_version_is_not_listed() -> void:
	var dir := _write("future", _two_player_map(), {"name": "Future"})
	var path := dir.path_join(MapFile.META_FILE)
	var text := FileAccess.get_file_as_string(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(f)
	if f == null:
		return
	f.store_string(text.replace('"format_version": %d' % MapFile.FORMAT_VERSION,
			'"format_version": %d' % (MapFile.FORMAT_VERSION + 1)))
	f.close()

	var loader := SavedMaps.new()
	assert_eq(_rows_from(loader, _root()).size(), 0)
	assert_true(loader.warnings.size() >= 1)


## A root that does not exist is NORMAL and must not warn: a fresh clone has no
## `user://maps/`, and a warning on every developer run is a warning nobody reads.
func test_a_missing_root_is_silent() -> void:
	var loader := SavedMaps.new()
	assert_eq(_rows_from(loader, "user://test_saved_maps/does_not_exist").size(), 0)
	assert_eq(loader.warnings, [] as Array[String])


## The dev override shadows an installed copy of the same folder rather than listing it
## twice -- `Campaigns`' first-match-wins rule, by folder name.
func test_the_first_root_wins_by_folder_name() -> void:
	var first := _root().path_join("root_a")
	var second := _root().path_join("root_b")
	DirAccess.make_dir_recursive_absolute(first.path_join("duel"))
	DirAccess.make_dir_recursive_absolute(second.path_join("duel"))
	assert_eq(MapFile.save(_two_player_map(), first.path_join("duel"),
			{"name": "Override"}), [] as Array[String])
	assert_eq(MapFile.save(_two_player_map(), second.path_join("duel"),
			{"name": "Installed"}), [] as Array[String])

	var loader := SavedMaps.new()
	var rows := _rows_from(loader, first, second)
	assert_eq(rows.size(), 1)
	assert_eq(str(rows[0]["name"]), "Override")


# ── roots ───────────────────────────────────────────────────────────────────

## The order IS the rule, so it is asserted rather than the paths.
##
## Under the headless suite `OS.has_feature("editor")` is TRUE, so the dev override is
## present -- which is what makes this assertion worth making: it is the ordering an editor
## run gets, and the two `user://` roots keep their relative order behind it.
func test_the_roots_are_ordered_dev_then_content_then_saves() -> void:
	var list := SavedMaps.new().roots()
	assert_true(list.size() >= 2)
	var content := list.find(SavedMaps.CONTENT_ROOT)
	var saves := list.find(SavedMaps.SAVE_ROOT)
	assert_true(content >= 0, "the installed-content root must be searched")
	assert_true(saves > content, "a player's own saves are searched after installed content")
	if OS.has_feature("editor"):
		assert_eq(content, 1, "the dev override comes first in an editor run")


## `user://maps/` is a SEPARATE directory from `user://content/maps/`, and 11.3 is emphatic
## about why: installing or replacing authored content must never overwrite somebody's save,
## and uninstalling it must never delete one. Pinned by name so a "tidy-up" cannot merge
## them.
func test_the_save_root_is_not_inside_the_content_root() -> void:
	assert_false(SavedMaps.SAVE_ROOT.begins_with(SavedMaps.CONTENT_ROOT),
			"a player's saves must not live under installed content -- see PLAN.md 11.3")


# ── writing one (2.4c) ──────────────────────────────────────────────────────

## ⚠️ **THESE ARE THE ONLY TESTS HERE THAT TOUCH A REAL SHIPPING DIRECTORY.** Everything above
## works in a scratch root, because `maps_in()` takes one; `save()` deliberately does not --
## its whole job is to put a file where the game will find it, and a version that took a root
## could be pointed at `res://` by a caller and would prove nothing about the rule it exists
## to keep. So these write into `user://maps/` for real and `after_each` removes what they
## wrote. The names are prefixed so a leftover is obvious rather than mistaken for a map the
## developer saved while playing.
const _TEST_MAP_NAME := "ZZ Test Fixture"

func after_each() -> void:
	var slug := SaveFile.slugify(_TEST_MAP_NAME)
	if not slug.is_empty():
		_wipe(SavedMaps.SAVE_ROOT.path_join(slug))


## The round trip the button is for: save a map, and find it in the picker's own listing.
##
## ⛔ **`maps_in(SAVE_ROOT)` AND NOT A `FileAccess.file_exists`.** The claim worth testing is
## not "two files appeared", it is "the picker will offer this" -- and those differ, because a
## listing version-checks the sidecar and drops anything it cannot read. A map written in a
## shape `read_header` rejects would pass a file-exists check and be invisible in the game.
func test_a_saved_map_is_listed_by_the_loader_that_feeds_the_picker() -> void:
	assert_eq(SavedMaps.save(_two_player_map(), _TEST_MAP_NAME), [] as Array[String])
	var rows := SavedMaps.new().maps_in(SavedMaps.SAVE_ROOT)
	var found := rows.filter(func(r: Dictionary) -> bool:
		return str(r["name"]) == _TEST_MAP_NAME)
	assert_eq(found.size(), 1, "the saved map should be offered exactly once")
	assert_eq(int(found[0]["players"]), 2, "and with the seat count it can actually field")


## What was written is the map that went in, terrain and all.
##
## `preview_saved_map`'s load-bearing step in miniature: a saver that wrote a DIFFERENT map
## and a picker that listed it look identical from outside, and the only way to tell is to
## read the file back and compare it to what was handed over.
func test_the_written_map_reads_back_as_the_map_that_was_saved() -> void:
	var original := _two_player_map()
	assert_eq(SavedMaps.save(original, _TEST_MAP_NAME), [] as Array[String])

	var problems: Array[String] = []
	var back := MapFile.load_map(
			SavedMaps.SAVE_ROOT.path_join(SaveFile.slugify(_TEST_MAP_NAME)), problems)
	assert_eq(problems, [] as Array[String])
	assert_not_null(back)
	if back == null:
		return
	assert_eq(back.size, original.size)
	assert_eq(back.terrain, original.terrain)
	assert_eq(back.starts, original.starts)


## ⛔ IT WRITES `user://maps/` AND NOTHING ELSE, WHICH IS 11.3's RULE AND NOT A DEFAULT.
##
## The dev override is repo-root `maps/` -- authored content under version control, and
## editor-only. A save landing there would be a player's file in somebody's git status, and in
## an exported build that root does not exist at all.
func test_a_saved_map_lands_in_the_save_root() -> void:
	assert_eq(SavedMaps.save(_two_player_map(), _TEST_MAP_NAME), [] as Array[String])
	var dir := SavedMaps.SAVE_ROOT.path_join(SaveFile.slugify(_TEST_MAP_NAME))
	assert_true(MapFile.exists_in(dir), "expected the pair in %s" % dir)


## Saving twice REPLACES, and that is the point of naming a map after itself.
##
## `SaveFile.auto_name` puts the tick in a saved GAME's name so two presses cannot overwrite
## each other; this does the opposite deliberately. A map does not change while the match runs,
## so a second press describes the same map -- and a tick here would fill the picker with
## identical rows the player then has to tell apart.
func test_saving_the_same_map_twice_leaves_one_row() -> void:
	assert_eq(SavedMaps.save(_two_player_map(), _TEST_MAP_NAME), [] as Array[String])
	assert_eq(SavedMaps.save(_two_player_map(), _TEST_MAP_NAME), [] as Array[String])
	var rows := SavedMaps.new().maps_in(SavedMaps.SAVE_ROOT).filter(
			func(r: Dictionary) -> bool: return str(r["name"]) == _TEST_MAP_NAME)
	assert_eq(rows.size(), 1, "the same map saved twice is one map")


## A name with nothing to build a folder out of is REFUSED, not guessed at. `SaveFile.slugify`
## is a whitelist, so this is also the test that a name of pure punctuation cannot reach the
## filesystem at all.
func test_a_name_with_no_letters_or_digits_is_refused() -> void:
	var problems := SavedMaps.save(_two_player_map(), "...///...")
	assert_eq(problems.size(), 1)
	assert_true(problems[0].contains("no letters or digits"), problems[0])


func test_saving_nothing_is_refused_rather_than_crashing() -> void:
	var problems := SavedMaps.save(null, _TEST_MAP_NAME)
	assert_eq(problems.size(), 1)


# ── the automatic name (2.4c) ───────────────────────────────────────────────

## ⛔ THE NAME DESCRIBES THE MAP, NOT THE MOMENT -- so it is STABLE across calls.
##
## This is the assertion that would fail if somebody added a timestamp or a tick to make names
## unique, which is `SaveFile.auto_name`'s rule and is the wrong one here. Two presses in one
## match must produce one name, or `test_saving_the_same_map_twice_leaves_one_row` becomes a
## lie the moment the clock ticks over.
func test_the_automatic_name_is_the_same_for_the_same_map() -> void:
	var m := _two_player_map()
	m.meta = {"type": int(MapGenerator.Type.RIVER), "players": 2, "seed": 4821}
	assert_eq(SavedMaps.auto_name(m), SavedMaps.auto_name(m))


## Everything a player needs to tell two saved maps apart, in one line: what kind of map, how
## many seats, how big, and which seed made it.
func test_the_automatic_name_carries_the_type_seats_size_and_seed() -> void:
	var m := _two_player_map()
	m.meta = {"type": int(MapGenerator.Type.RIVER), "players": 2, "seed": 4821}
	var name := SavedMaps.auto_name(m)
	assert_eq(name, "River 2p 12x10 (seed 4821)", name)


## A map with no generator metadata -- one authored in the MapMaker, say -- still gets a
## usable name rather than an empty one or a crash. "Random" is what `MapGenerator.type_name`
## calls an unknown type and there is no point inventing a second word for it here.
func test_a_map_with_no_metadata_still_gets_a_name() -> void:
	var m := _two_player_map()
	m.meta = {}
	var name := SavedMaps.auto_name(m)
	assert_false(name.strip_edges().is_empty())
	assert_false(name.contains("seed"), "no seed is not a seed of zero: " + name)
	assert_false(SaveFile.slugify(name).is_empty(), "and it must survive to a folder name")


# ── helpers ─────────────────────────────────────────────────────────────────

## `discover()` walks `roots()`, which points at the real machine. `maps_in()` is the same
## walk over one root somebody supplies, and it exists precisely so these tests exercise the
## SHIPPING loop over a scratch directory rather than a copy of it.
##
## The split of responsibility: the root ORDER and the editor gate are tested against the
## real `roots()` above, and the seat arithmetic, the naming and the per-root rules against
## these.
func _rows_from(loader: SavedMaps, root_a: String, root_b: String = "") -> Array[Dictionary]:
	loader.warnings.clear()
	var out := loader.maps_in(root_a)
	if root_b.is_empty():
		return out
	# First match wins BY FOLDER NAME, which is `discover()`'s dedupe rule and the only part
	# of it not inside `maps_in()`.
	var seen: Dictionary = {}
	for entry in out:
		seen[str(entry["folder"])] = true
	for entry in loader.maps_in(root_b):
		if not seen.has(str(entry["folder"])):
			out.append(entry)
	return out


func _discover_in(root: String) -> Array[Dictionary]:
	return _rows_from(SavedMaps.new(), root)
