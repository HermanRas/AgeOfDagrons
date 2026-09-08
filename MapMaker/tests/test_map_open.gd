## PLAN.md 16.4a: File ▸ Open — reading a map back into the tool.
##
## ## WHAT THESE ARE ACTUALLY GUARDING
##
## The round trip itself is already pinned on the game side (`test_map_file`, eleven tests) and
## exercised end to end every time `dev/author_map.tscn` runs. **What is new in this row is
## everything that happens AROUND a successful load**, and each of the three has a way of
## failing silently:
##
##   - **the listing** — three roots at two depths, and a scenario map is two levels down. A
##     root that quietly finds nothing looks exactly like a root with nothing in it.
##   - **a failed load must change nothing.** 16.4a's card names the fault: *"a partial load
##     that silently shows an empty canvas over somebody's authored map is how a file gets
##     overwritten with nothing."*
##   - **a re-save must not write the OPENED file's entities over the edited ones.**
##     `MapFile.save()` merges its header argument *over* the derived fields, so handing the
##     loaded sidecar back unfiltered discards every edit in a save that reports success. That
##     is the one bug in this row that no screenshot could ever show.
##
## Everything is written into `user://`, never into repo-root `maps/` or `scenarios/`: those
## hold content under version control and a test that wrote there would be a test that edits
## the game. Same rule `test_map_document` follows.
extends TestCase

const SCRATCH := "user://test_map_open"

var _n := 0
var sources: MapSources = null


func before_each() -> void:
	_n += 1
	GameDataRegistry.load_from(GameRoot.resolve())
	sources = MapSources.new()


func after_each() -> void:
	_wipe(ProjectSettings.globalize_path(SCRATCH))


func _root() -> String:
	var path := ProjectSettings.globalize_path("%s/case_%d" % [SCRATCH, _n])
	DirAccess.make_dir_recursive_absolute(path)
	return path


## A small, ASYMMETRIC, two-player map. Asymmetric on `dev/author_map.tscn`'s reasoning: a
## mirror-symmetric map cannot tell a correct round trip from one that transposed x and y.
func _map(map_name: String) -> MapDocument:
	var doc := MapDocument.create(Vector2i(48, 48), map_name)
	for y in range(10, 20):
		for x in range(4, 30):
			doc.paint(Vector2i(x, y), SimMap.Terrain.WATER_DEEP)
	for x in range(6, 12):
		doc.paint(Vector2i(x, 40), SimMap.Terrain.ROCK)
	doc.place_start(1, Vector2i(10, 30))
	doc.place_start(2, Vector2i(36, 12))
	return doc


## Write a map into `<root>/<folder>` and hand back the directory.
func _write(root: String, folder: String, map_name := "Written Map") -> String:
	var doc := _map(map_name)
	var dir := root.path_join(folder)
	var problems := MapFile.save(doc.data, dir, {
		"name": map_name, "players": doc.seats(), "map_type": "RIVER", "seed": 4242,
		"authored_by": "the test",
	})
	assert_true(problems.is_empty(), "fixture failed to write: %s" % [problems])
	return dir


func _wipe(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_wipe(path.path_join(sub))
	DirAccess.remove_absolute(path)


# ── opening ─────────────────────────────────────────────────────────────────

func test_a_written_map_comes_back_the_same_map() -> void:
	var root := _root()
	var original := _map("Round Trip")
	MapFile.save(original.data, root.path_join("rt"), {"name": "Round Trip"})

	var problems: Array[String] = []
	var doc := MapDocument.open(root.path_join("rt"), problems)
	assert_not_null(doc, "did not open: %s" % [problems])
	assert_true(problems.is_empty(), "%s" % [problems])
	assert_eq(doc.data.size, original.data.size)
	assert_eq(doc.data.terrain, original.data.terrain, "the terrain did not survive")
	assert_eq(doc.data.starts, original.data.starts)
	assert_eq(doc.data.entities.size(), original.data.entities.size())


## ⚠️ **THE OPPOSITE OF `create()`, WHICH IS DIRTY FROM THE FIRST FRAME.** An opened map is
## byte-for-byte what is on disk, so "unsaved changes" would be a lie — and the flag is what
## an "you have unsaved work" prompt will read the day one exists.
func test_an_opened_map_is_clean_and_knows_where_it_came_from() -> void:
	var root := _root()
	var dir := _write(root, "clean_map", "Clean Map")
	var problems: Array[String] = []
	var doc := MapDocument.open(dir, problems)
	assert_not_null(doc)
	assert_false(doc.dirty, "an opened map has no unsaved changes")
	assert_eq(doc.dir, dir)
	assert_eq(doc.map_name, "Clean Map", "the name comes off the sidecar, not the folder")


## A hand-written map may have no `name`. A row labelled "" is a row nobody can pick, and an
## editor whose Name field is empty would save it as `untitled_map`.
func test_a_sidecar_with_no_name_falls_back_to_the_folder() -> void:
	var root := _root()
	var doc := _map("")
	MapFile.save(doc.data, root.path_join("nameless"), {})
	var problems: Array[String] = []
	var back := MapDocument.open(root.path_join("nameless"), problems)
	assert_not_null(back, "%s" % [problems])
	assert_eq(back.map_name, "nameless")


# ── a failed load must change nothing ───────────────────────────────────────

## ⚠️ **16.4a's NAMED FAULT.** A version this build cannot read must come back as null with a
## sentence, not as an empty map — because the next thing the author presses is Save.
func test_a_future_format_version_is_refused_with_a_reason() -> void:
	var root := _root()
	var dir := _write(root, "from_the_future")
	var side: Dictionary = MapFile.read_header(dir, [] as Array[String])
	side["format_version"] = MapFile.FORMAT_VERSION + 1
	var f := FileAccess.open(dir.path_join(MapFile.META_FILE), FileAccess.WRITE)
	f.store_string(JSON.stringify(side))
	f.close()

	var problems: Array[String] = []
	assert_null(MapDocument.open(dir, problems), "a version we cannot read must not open")
	assert_false(problems.is_empty(), "and it must say why")
	assert_true("format_version" in problems[0], "got %s" % problems[0])


func test_a_map_with_no_png_is_refused_rather_than_opened_empty() -> void:
	var root := _root()
	var dir := _write(root, "half_a_map")
	DirAccess.open(dir).remove(MapFile.TERRAIN_FILE)
	var problems: Array[String] = []
	assert_null(MapDocument.open(dir, problems))
	assert_false(problems.is_empty())


func test_a_missing_directory_is_refused_rather_than_crashing() -> void:
	var problems: Array[String] = []
	assert_null(MapDocument.open(_root().path_join("not_here"), problems))
	assert_false(problems.is_empty())


## Two functions read the sidecar (`load_map` and `read_header`) and `MapDocument.open` calls
## both. **A reader that reported the same fault twice** would put "…; …" on the notice line
## and read as two problems with one file.
func test_a_bad_sidecar_is_reported_once_and_not_twice() -> void:
	var root := _root()
	var dir := _write(root, "broken_json")
	var f := FileAccess.open(dir.path_join(MapFile.META_FILE), FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	var problems: Array[String] = []
	assert_null(MapDocument.open(dir, problems))
	assert_eq(problems.size(), 1, "got %s" % [problems])


# ── re-saving what was opened ───────────────────────────────────────────────

## ⚠️ **THE ONE BUG IN THIS ROW NOTHING ON SCREEN WOULD SHOW.** `MapFile.save()` merges its
## `header` argument OVER the fields it derives from the map, so a re-save that handed the
## opened sidecar back unfiltered would write the FILE's entities, starts and size on top of
## the edited ones — every change in the session discarded, and the save reporting success.
func test_editing_an_opened_map_and_saving_writes_the_edits_not_the_old_file() -> void:
	var root := _root()
	var dir := _write(root, "edit_me")
	var problems: Array[String] = []
	var doc := MapDocument.open(dir, problems)
	assert_not_null(doc, "%s" % [problems])

	var before := doc.data.entities.size()
	doc.paint(Vector2i(2, 2), SimMap.Terrain.SAND)
	doc.place_start(3, Vector2i(24, 40))
	assert_true(doc.data.entities.size() > before, "the fixture edit did nothing")

	assert_true(doc.save(root).is_empty(), "save failed")
	var reread: Array[String] = []
	var back := MapDocument.open(dir, reread)
	assert_not_null(back, "%s" % [reread])
	assert_eq(back.data.terrain_at(Vector2i(2, 2)), SimMap.Terrain.SAND,
			"the paint was overwritten by the header of the file we opened")
	assert_eq(back.data.starts.size(), 3, "the third start did not survive the save")
	assert_eq(back.data.entities.size(), doc.data.entities.size())


## `map_type` and `seed` are read by nothing in `game/src` and written for a person: 2.4c's
## rule is that the PNG is authoritative and **the seed is provenance**. Re-authoring the five
## How To Play maps (16.10) through a tool that dropped them would erase the only note saying
## where each map came from, one map at a time, with nothing failing.
func test_provenance_survives_a_re_save_and_the_derived_fields_do_not() -> void:
	var root := _root()
	var dir := _write(root, "provenance")
	var problems: Array[String] = []
	var doc := MapDocument.open(dir, problems)
	assert_not_null(doc, "%s" % [problems])
	assert_true(doc.save(root).is_empty())

	var side := MapFile.read_header(dir, problems)
	assert_eq(str(side.get("map_type", "")), "RIVER", "the map type was dropped")
	assert_eq(int(side.get("seed", 0)), 4242, "the seed was dropped")
	assert_eq(str(side.get("authored_by", "")), MapDocument.AUTHORED_BY,
			"whoever last wrote the file is the tool, not the fixture")
	assert_eq(int(side.get("format_version", 0)), MapFile.FORMAT_VERSION,
			"a stale format_version carried forward would label a new shape with an old number")


## ⚠️ **THE FILTER IS COMPUTED FROM `to_dict()` RATHER THAN FROM A WRITTEN-OUT LIST**, so a
## field added to the wire form (16.5's areas are next) is dropped from a stale header with no
## edit. This asserts the mechanism and not today's five names.
func test_every_key_the_map_itself_decides_is_dropped_from_a_stale_header() -> void:
	var root := _root()
	var dir := _write(root, "stale")
	var problems: Array[String] = []
	var doc := MapDocument.open(dir, problems)
	assert_not_null(doc, "%s" % [problems])
	var kept := doc._preserved_header()
	for key in doc.data.to_dict():
		assert_false(kept.has(key),
				"%s is derived from the map and must not be carried over" % key)
	assert_false(kept.has("created"), "created is stamped fresh on every save")


# ── Save As ─────────────────────────────────────────────────────────────────

## **Open then Save replaces; Save As creates.** Without the second button the tool could not
## be pointed at the shipped campaign's maps at all without the Save button being a way to
## overwrite them.
func test_save_as_writes_a_new_map_and_leaves_the_original_alone() -> void:
	var root := _root()
	var dir := _write(root, "original", "Original")
	var problems: Array[String] = []
	var doc := MapDocument.open(dir, problems)
	assert_not_null(doc, "%s" % [problems])

	doc.paint(Vector2i(3, 3), SimMap.Terrain.DIRT)
	doc.map_name = "A Copy"
	assert_true(doc.save_as(root).is_empty(), "save as failed")
	assert_eq(doc.dir, root.path_join("a_copy"), "it did not move to the new folder")

	var reread: Array[String] = []
	var untouched := MapDocument.open(dir, reread)
	assert_not_null(untouched, "%s" % [reread])
	assert_eq(untouched.data.terrain_at(Vector2i(3, 3)), SimMap.Terrain.GRASS,
			"Save As wrote into the map it was opened from")


## ⚠️ **THE NAME FIELD MUST NOT BE A DELETE BUTTON.** `dev/author_map.tscn` already refuses to
## overwrite an authored map without `--force`, and a GUI has no `--force` to offer — so a name
## that is taken is reported and nothing is written. Replacing a map on purpose is Open, then
## Save.
func test_save_as_onto_an_existing_map_is_refused_and_writes_nothing() -> void:
	var root := _root()
	_write(root, "taken", "Taken")
	var doc := _map("Taken")
	var problems := doc.save_as(root)
	assert_false(problems.is_empty(), "it must refuse")
	assert_true("already a map" in problems[0], "got %s" % problems[0])
	assert_eq(doc.dir, "", "a refused Save As must not have claimed the directory")

	# AND THE MAP THAT WAS ALREADY THERE IS THE ONE THAT IS STILL THERE.
	var reread: Array[String] = []
	var back := MapDocument.open(root.path_join("taken"), reread)
	assert_not_null(back, "%s" % [reread])
	assert_eq(str(MapFile.read_header(root.path_join("taken"), reread)
			.get("authored_by", "")), "the test")


## Saving a map back to the folder it is already in through Save As is the ordinary "I renamed
## nothing" case and must not be mistaken for a collision with itself.
func test_save_as_over_its_own_directory_is_allowed() -> void:
	var root := _root()
	var dir := _write(root, "same_name", "Same Name")
	var problems: Array[String] = []
	var doc := MapDocument.open(dir, problems)
	assert_not_null(doc, "%s" % [problems])
	assert_eq(doc.slug(), "same_name", "fixture: the slug must match the folder")
	var again := doc.save_as(root)
	assert_true(again.is_empty(), "%s" % [again])


# ── the listing ─────────────────────────────────────────────────────────────

func test_maps_in_a_root_are_listed_alphabetically_with_their_figures() -> void:
	var root := _root()
	_write(root, "zulu", "Zulu")
	_write(root, "alpha", "Alpha")
	var rows := sources.maps_in(root, MapSources.Source.AUTHORED, 1)
	assert_eq(rows.size(), 2)
	assert_eq(str(rows[0]["folder"]), "alpha", "directory order is a filesystem detail")
	assert_eq(str(rows[1]["folder"]), "zulu")
	assert_eq(rows[0]["size"], Vector2i(48, 48))
	assert_eq(int(rows[0]["players"]), 2, "seats, not starts -- see MapSources.players_in")


## ⚠️ **THE ROW THIS WHOLE FILE EXISTS FOR.** 16.4a's justification is 16.10 — *"re-author the
## five existing How To Play maps"* — and those five are at
## `scenarios/<campaign>/<scenario>/map.json`, **one level deeper than an authored map.** A
## listing that only walked depth 1 would have shipped unable to open a single one of them.
func test_a_scenario_map_is_found_one_level_deeper_and_labelled_with_its_campaign() -> void:
	var root := _root()
	var campaign := root.path_join("HowToPlay")
	_write(campaign, "scenario_1", "First Steps")
	_write(campaign, "scenario_2", "Second Steps")
	# A campaign folder is NOT a map: it holds `campaign.json` and no `map.png`.
	FileAccess.open(campaign.path_join("campaign.json"), FileAccess.WRITE).store_string("{}")

	var rows := sources.maps_in(root, MapSources.Source.SCENARIO, 2)
	assert_eq(rows.size(), 2, "got %s" % [rows])
	assert_eq(str(rows[0]["label"]), "HowToPlay/scenario_1",
			"a bare 'scenario_1' cannot be chosen between two campaigns")
	assert_eq(str(rows[0]["name"]), "First Steps")


## A depth-2 walk must not list a map at depth 1 twice, nor miss it. The rule is "does THIS
## level hold a map", never "how deep am I".
func test_a_map_at_the_top_of_a_deep_root_is_listed_once() -> void:
	var root := _root()
	_write(root, "loose_map", "Loose")
	var rows := sources.maps_in(root, MapSources.Source.SCENARIO, 2)
	assert_eq(rows.size(), 1, "got %s" % [rows])
	assert_eq(str(rows[0]["label"]), "loose_map")


## ⚠️ **A FOLDER THE AUTHOR CAN SEE ON DISK AND CANNOT SEE IN THE LIST IS THE ONE FAULT THEY
## CANNOT DIAGNOSE BY LOOKING**, which is 16.4a's third requirement. So an unreadable pair is
## a warning rather than a shorter list.
func test_an_unreadable_map_is_a_warning_rather_than_a_silently_shorter_list() -> void:
	var root := _root()
	_write(root, "good_one", "Good")
	var bad := _write(root, "bad_one", "Bad")
	FileAccess.open(bad.path_join(MapFile.META_FILE), FileAccess.WRITE).store_string("nope")

	var rows := sources.maps_in(root, MapSources.Source.AUTHORED, 1)
	assert_eq(rows.size(), 1, "the unreadable one must not be offered")
	assert_eq(sources.warnings.size(), 1, "and it must be complained about: %s"
			% [sources.warnings])


## An absent root is normal and silent: nothing has ever written the game's `user://maps/`
## (the pause-menu Save Map button is parked), and a complaint on every run is a complaint
## nobody reads.
func test_an_absent_root_is_silent() -> void:
	var rows := sources.maps_in(_root().path_join("nowhere"), MapSources.Source.PLAYER, 1)
	assert_true(rows.is_empty())
	assert_true(sources.warnings.is_empty(), "got %s" % [sources.warnings])


# ── the roots, and where the game's user:// is ──────────────────────────────

## The order is what the dialog shows and what `discover()`'s de-duplication depends on.
## Scenarios are walked deeper than the other two; that is the only reason `depth` is data.
func test_the_roots_are_the_three_in_order_with_scenarios_walked_deeper() -> void:
	var root := GameRoot.resolve()
	var list := sources.roots(root)
	assert_eq(int(list[0]["source"]), MapSources.Source.AUTHORED)
	assert_eq(int(list[0]["depth"]), 1)
	assert_eq(int(list[1]["source"]), MapSources.Source.SCENARIO)
	assert_eq(int(list[1]["depth"]), 2,
			"a scenario map is <campaign>/<scenario>/map.json")
	assert_true(str(list[0]["path"]).ends_with("maps"), "got %s" % list[0]["path"])
	assert_true(str(list[1]["path"]).ends_with("scenarios"), "got %s" % list[1]["path"])


## ⚠️ **`user://` MEANS A DIFFERENT DIRECTORY IN EACH GODOT PROJECT.** This tool's own is
## `.../AOD MapMaker`; the game's is `.../AgeOfDragons`. A tool that listed its OWN
## `user://maps/` would have shipped a root that is empty by construction and looks, from the
## outside, exactly like the root that is empty because nothing has written to it yet.
func test_the_players_root_is_the_games_user_directory_and_not_this_tools() -> void:
	var root := GameRoot.resolve()
	if root.path.is_empty():
		return  # no game project on this machine; `test_startup` is where that is reported
	var mine := OS.get_user_data_dir()
	var theirs := root.game_user_dir()
	assert_false(theirs.is_empty(), "could not derive the game's user directory")
	assert_ne(theirs, mine, "the tool would be listing its own empty directory")
	assert_eq(theirs.get_file(), root.game_project_name(),
			"the leaf is the game's config/name")


func test_the_game_project_name_is_read_out_of_its_project_godot() -> void:
	var root := GameRoot.resolve()
	if root.path.is_empty():
		return
	assert_eq(root.game_project_name(), "AgeOfDragons")


## With no game project there is nothing to derive a user directory from, so the third root is
## absent rather than guessed. A tool in that state cannot save anyway (`Startup`).
func test_with_no_game_project_there_are_only_two_roots() -> void:
	assert_eq(sources.roots(GameRoot.new()).size(), 2)
	assert_eq(sources.roots(null).size(), 2, "null must not crash the dialog")


## ⚠️ **THE SUMMARY LINE UNDER THE DIALOG'S LIST, AND IT IS HERE BECAUSE OF HOW THIS ROW
## FAILED FIRST.** Every branch of it is a `%` over a variable holding an `Array`, which is the
## one construction that raises *"not enough arguments for format string"* on an empty list and
## *"not all arguments converted"* on a full one — eighteen engine errors on the first suite run
## of this file, none of them mentioning arrays. `preview_editor` only ever renders the healthy
## branch, so the two that say something is wrong would otherwise be prose nothing has run.
func test_the_dialogs_summary_line_says_something_in_all_three_states() -> void:
	# THE SCRIPT, not a `class_name`: `editor.gd` deliberately has none -- it is reached as a
	# scene (`Editor.tscn`) everywhere else, and a static is callable straight off the script.
	var ed: GDScript = load("res://src/editor.gd")
	var roots: Array[String] = ["/a/maps", "/a/scenarios"]
	var none: Array[String] = []
	var found: String = ed._open_summary_for(7, none, roots)
	assert_true(found.contains("7"), "got '%s'" % found)

	var empty: String = ed._open_summary_for(0, none, roots)
	assert_true(empty.contains("/a/maps") and empty.contains("/a/scenarios"),
			"'no maps found' is a sentence nobody can act on; got '%s'" % empty)

	var broken: Array[String] = ["x/map.json is format_version 2", "y/map.json is empty"]
	var bad: String = ed._open_summary_for(1, broken, roots)
	assert_true(bad.contains("2 unreadable"), "got '%s'" % bad)
	assert_true(bad.contains("format_version 2"), "and it must name one; got '%s'" % bad)


## `discover()` keys on the DIRECTORY and not on the folder name, which is where it departs
## from `SavedMaps` on purpose: two campaigns may each hold a `scenario_1`, and keying on the
## folder would hide the second with nothing on screen to explain it.
func test_two_campaigns_with_the_same_scenario_folder_are_both_listed() -> void:
	var root := _root()
	_write(root.path_join("HowToPlay"), "scenario_1", "Theirs")
	_write(root.path_join("TheDragonBorn"), "scenario_1", "Mine")
	var rows := sources.maps_in(root, MapSources.Source.SCENARIO, 2)
	assert_eq(rows.size(), 2, "got %s" % [rows])
