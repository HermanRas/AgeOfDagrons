## PLAN.md 16.8: scenario export — the `campaign.json` / `scenario.json` pair and the icon slots.
##
## ## WHAT THESE ARE ACTUALLY GUARDING
##
## This row makes the tool **the second consumer of 15.1's schema**, and a second writer is where a
## format grows a dialect. The dangerous failures here are all quiet:
##
##   - **a file the game's loader refuses.** The symptom is a greyed PLAY button on a screen in
##     another project, with the reason in a log nobody is reading. So the objectives written are
##     round-tripped back through `ObjectiveDef.from_dict` — the game's own parser, verbatim in
##     `format/` — rather than compared to what the test expected.
##   - **the wire form written into a file that wants words.** `to_dict()` turns `">="` into an
##     int; a `scenario.json` of integers is one the loader cannot read at all, and the tool looks
##     perfect throughout because it never re-parses its own output.
##   - **a `campaign.json` rebuilt instead of added to.** The shipped one's `_note` is eighteen
##     lines of reasoning, and a writer that kept only the fields it understands would delete it in
##     a save that reported success.
##   - **conditions in two places at once.** The first save of the map happens before the
##     `scenario.json` exists, so the rows land in the sidecar; the export has to move them.
##
## ⚠️ **EVERYTHING IS WRITTEN INTO `user://`, NEVER INTO REPO-ROOT `scenarios/`.** That directory
## holds the shipped campaign, and a test that wrote there would be a test that edits the game.
## `ScenarioExport.run()` takes a root for exactly this reason. Same rule `test_map_open` follows.
extends TestCase

const SCRATCH := "user://test_export"

## A record in the author's own words, which is the form `MapDocument.objectives` holds and the
## form a `scenario.json` carries. See `ScenarioExport._scenario_record`.
const WIN_ROW := {
	"subject": "unit", "id": "unit.villager", "owner": "self",
	"compare": ">=", "value": 14, "output": "win", "text": "Reach 14 villagers",
}

var _n := 0
var _nodes: Array[Node] = []


func before_each() -> void:
	_n += 1
	GameDataRegistry.load_from(GameRoot.resolve())


func after_each() -> void:
	for n in _nodes:
		n.free()
	_nodes.clear()
	_wipe(ProjectSettings.globalize_path(SCRATCH))


# ── fixtures ────────────────────────────────────────────────────────────────

func _root() -> String:
	var path := ProjectSettings.globalize_path("%s/case_%d" % [SCRATCH, _n])
	DirAccess.make_dir_recursive_absolute(path)
	return path


## A real two-player map: two starts with their bases, so `seats()` is 2.
##
## **ASYMMETRIC**, `dev/author_map.tscn`'s reasoning: a mirror-symmetric map cannot tell a correct
## round trip from one that transposed x and y.
func _map(map_name := "Test Map") -> MapDocument:
	var doc := MapDocument.create(Vector2i(48, 48), map_name)
	for x in range(6, 14):
		doc.paint(Vector2i(x, 20), SimMap.Terrain.ROCK)
	doc.place_start(1, Vector2i(12, 12))
	doc.place_start(2, Vector2i(34, 34))
	return doc


## The real guard, which is what `run()` demands. A drifted one is `_drifted_guard()`.
func _guard() -> FormatGuard:
	return FormatGuard.check(GameRoot.resolve())


## A guard reporting schema drift, for the one test that needs the refusal.
##
## **BUILT RATHER THAN PROVOKED**, because the alternative is editing a file in the GAME project
## from a test in this one — which is the thing `format/` exists to avoid doing by accident.
func _drifted_guard() -> FormatGuard:
	var g := FormatGuard.new()
	g.schema_results = [{
		"name": "src/data/scenario_def.gd :: const _MODES",
		"status": int(FormatGuard.Status.DRIFTED),
		"detail": "the game says something else",
	}]
	return g


func _request(overrides: Dictionary = {}) -> Dictionary:
	var r := {
		"campaign_folder": "TestCampaign",
		"campaign_name": "A Test Campaign",
		"campaign_description": "for the suite",
		"folder": "scenario_1",
		"name": "The First Lesson",
		"description": "learn a thing",
		"message": "Objective: do it.\n\nOverview: by doing it.",
		"opponents": ["passive"],
		"starting_age": 1,
		"icons": {},
	}
	for k in overrides:
		r[k] = overrides[k]
	return r


## Export and assert it worked, handing back the exporter so warnings can be read.
func _export(doc: MapDocument, root: String, overrides: Dictionary = {}) -> ScenarioExport:
	var x := ScenarioExport.new()
	var problems := x.run(doc, _request(overrides), _guard(), root)
	assert_true(problems.is_empty(), "export refused: %s" % [problems])
	return x


func _read(path: String) -> Dictionary:
	var problems: Array[String] = []
	var d := ScenarioFile.read(path, problems)
	assert_true(problems.is_empty(), "%s did not parse: %s" % [path, problems])
	return d


func _scenario_dir(root: String, campaign := "TestCampaign", folder := "scenario_1") -> String:
	return root.path_join(campaign).path_join(folder)


func _wipe(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_wipe(path.path_join(sub))
	DirAccess.remove_absolute(path)


# ── the pair lands ──────────────────────────────────────────────────────────

## Every file the row promises, in one place, so *"it exported"* means something specific.
func test_an_export_writes_the_map_the_scenario_and_the_campaign() -> void:
	var root := _root()
	var doc := _map()
	var x := _export(doc, root)

	var dir := _scenario_dir(root)
	assert_true(MapFile.exists_in(dir), "no map in %s" % dir)
	assert_true(FileAccess.file_exists(dir.path_join(ScenarioDef.JSON_FILE)), "no scenario.json")
	assert_true(FileAccess.file_exists(root.path_join("TestCampaign")
			.path_join(CampaignDef.JSON_FILE)), "no campaign.json")
	assert_eq(x.written.size(), 4, "map.json, map.png, scenario.json, campaign.json — got %s"
			% [x.written])


func test_the_scenario_carries_the_fields_the_author_typed() -> void:
	var root := _root()
	var doc := _map()
	_export(doc, root, {"starting_age": 3, "opponents": ["easy"]})

	var s := _read(_scenario_dir(root).path_join(ScenarioDef.JSON_FILE))
	assert_eq(str(s.get("name", "")), "The First Lesson")
	assert_eq(str(s.get("description", "")), "learn a thing")
	assert_true(str(s.get("message", "")).contains("Overview:"), "the briefing is carried whole")
	assert_eq(int(s.get("starting_age", 0)), 3)
	assert_eq(s.get("opponents", []), ["easy"])


# ── the mode, which is derived and not asked ────────────────────────────────

## ⛔ **THE ONE DECISION THIS ROW MAKES FOR THE AUTHOR.** `ScenarioDef` refuses three of the four
## combinations of mode and condition list, so a picker would be a control whose wrong setting
## authors a mission that will not start.
func test_a_map_with_no_conditions_is_won_by_conquest() -> void:
	var root := _root()
	var doc := _map()
	_export(doc, root)

	var s := _read(_scenario_dir(root).path_join(ScenarioDef.JSON_FILE))
	assert_eq(str(s.get("mode", "")), "last_man_standing")
	assert_eq(s.get("objectives", null), [], "written even when empty")


func test_a_map_with_a_win_condition_is_decided_by_its_objectives() -> void:
	var root := _root()
	var doc := _map()
	var problems: Array[String] = []
	assert_true(doc.add_objective(WIN_ROW, problems), "fixture: %s" % [problems])
	_export(doc, root)

	var s := _read(_scenario_dir(root).path_join(ScenarioDef.JSON_FILE))
	assert_eq(str(s.get("mode", "")), "scenario")
	assert_eq((s.get("objectives", []) as Array).size(), 1)


## ⛔ **ROWS WITH NO WIN ROW CAN BE SPELLED IN NEITHER MODE.** `last_man_standing` carrying
## objectives is refused (*"would never be read"*) and `scenario` with no win row is refused
## (*"can never be won"*), so this is the one condition list with no legal export — and 16.6 only
## *warns* about it, correctly, because it is an ordinary half-finished state to be working in.
func test_conditions_with_no_win_row_are_refused() -> void:
	var root := _root()
	var doc := _map()
	var lose_row := WIN_ROW.duplicate()
	lose_row["output"] = "lose"
	var problems: Array[String] = []
	assert_true(doc.add_objective(lose_row, problems), "fixture: %s" % [problems])

	var refused := ScenarioExport.new().run(doc, _request(), _guard(), root)
	assert_eq(refused.size(), 1, "%s" % [refused])
	assert_true(refused[0].contains("none of them is a win"), refused[0])
	assert_false(MapFile.exists_in(_scenario_dir(root)), "nothing is written on a refusal")


# ── the objectives are the author's WORDS ───────────────────────────────────

## ⛔ **`to_dict()` IS THE WIRE FORM AND A `scenario.json` IS THE OPPOSITE.** Storing parsed defs
## and writing them back emits a file of integers the game's own loader cannot read — and the tool
## looks perfect throughout, because it never re-parses its own output.
func test_the_objectives_are_written_as_words_and_not_as_the_wire_form() -> void:
	var root := _root()
	var doc := _map()
	var problems: Array[String] = []
	doc.add_objective(WIN_ROW, problems)
	_export(doc, root)

	var rows: Array = _read(_scenario_dir(root).path_join(ScenarioDef.JSON_FILE)).get(
			"objectives", [])
	var row: Dictionary = rows[0]
	assert_eq(str(row.get("subject", "")), "unit", "a word, not an enum index")
	assert_eq(str(row.get("compare", "")), ">=", "a word, not an enum index")
	assert_eq(str(row.get("output", "")), "win")
	assert_eq(int(row.get("value", 0)), 14)


## ⚠️ **THE GAME'S OWN PARSER, NOT AN EXPECTATION WRITTEN HERE.** `format/objective_def.gd` is
## hash-checked against the game's, so a row this accepts is a row the shipped loader accepts —
## which is the only version of this assertion that is worth anything. A test comparing the written
## record to the record it supplied would round-trip perfectly by construction and prove nothing
## (§5: beware fixtures that agree with the bug).
func test_every_exported_objective_is_readable_by_the_games_own_loader() -> void:
	var root := _root()
	var doc := _map()
	var problems: Array[String] = []
	doc.add_objective(WIN_ROW, problems)
	var second := WIN_ROW.duplicate()
	second["subject"] = "building"
	second["id"] = "building.house"
	second["value"] = 1
	doc.add_objective(second, problems)
	assert_true(problems.is_empty(), "fixture: %s" % [problems])
	_export(doc, root)

	var rows: Array = _read(_scenario_dir(root).path_join(ScenarioDef.JSON_FILE)).get(
			"objectives", [])
	assert_eq(rows.size(), 2)
	for entry in rows:
		var row_problems: Array[String] = []
		var parsed := ObjectiveDef.from_dict(entry as Dictionary, row_problems)
		assert_not_null(parsed, "the game's loader refused a row we wrote: %s" % [row_problems])


## ⚠️ **A ROW `MapDocument` KEPT BECAUSE IT COULD NOT PARSE IT MUST NOT BE EXPORTED.**
## `_objectives_in()` deliberately keeps an unreadable row rather than dropping it — a map opened
## from a hand-written scenario can carry one — and writing it would produce a `scenario.json` the
## loader refuses in full. The export is the last moment anybody is looking.
func test_a_row_the_loader_cannot_read_refuses_the_export() -> void:
	var root := _root()
	var doc := _map()
	# ASSIGNED PAST `add_objective()`, which would have refused it -- this is the state an OPENED
	# map arrives in, not one the panel can create.
	doc.objectives = [{"subject": "nonsense", "output": "win"}] as Array[Dictionary]

	var refused := ScenarioExport.new().run(doc, _request(), _guard(), root)
	assert_false(refused.is_empty(), "an unreadable row must refuse")
	var said := " | ".join(PackedStringArray(refused))
	assert_true(said.contains("condition 1"), said)


# ── the campaign file is added to, never rebuilt ────────────────────────────

func test_a_new_campaign_gets_a_file_naming_the_scenario_in_play_order() -> void:
	var root := _root()
	_export(_map(), root)

	var c := _read(root.path_join("TestCampaign").path_join(CampaignDef.JSON_FILE))
	assert_eq(str(c.get("name", "")), "A Test Campaign")
	assert_eq(c.get(CampaignDef.ORDER_KEY, []), ["scenario_1"])


## ⛔ **THE SHIPPED `campaign.json`'s `_note` IS EIGHTEEN LINES OF REASONING**, and a writer that
## rebuilt the file from the fields it understands would delete it in a save that reported success.
## `ScenarioFile`'s rule one level up, tested against a file with something in it to lose.
func test_a_second_export_appends_and_keeps_everything_it_does_not_understand() -> void:
	var root := _root()
	var campaign_dir := root.path_join("TestCampaign")
	DirAccess.make_dir_recursive_absolute(campaign_dir)
	var seeded := {
		"_note": ["a hand-written note", "on two lines"],
		"name": "The Hand-Written Name",
		"description": "hand-written too",
		"something_the_tool_has_never_heard_of": {"nested": 7},
		CampaignDef.ORDER_KEY: ["scenario_1"],
	}
	var f := FileAccess.open(campaign_dir.path_join(CampaignDef.JSON_FILE), FileAccess.WRITE)
	f.store_string(JSON.stringify(seeded, "  ", false))
	f.close()

	_export(_map("Second"), root, {"folder": "scenario_2", "name": "The Second Lesson"})

	var c := _read(campaign_dir.path_join(CampaignDef.JSON_FILE))
	assert_eq(c.get("_note", []), ["a hand-written note", "on two lines"], "the note survives")
	assert_eq(str(c.get("name", "")), "The Hand-Written Name",
			"adding a scenario must not rename the campaign")
	assert_eq(str(c.get("description", "")), "hand-written too")
	# ⚠️ **COMPARED FIELD BY FIELD AND NOT AS A DICTIONARY, BECAUSE THIS TEST READS THE FILE BACK
	# THROUGH `JSON.parse` AND THAT WIDENS EVERY INTEGER TO A FLOAT.** `{"nested": 7}` comes back
	# as `{"nested": 7.0}` and the two dictionaries are not equal — which says nothing at all about
	# what is in the file. What is actually on disk is asserted on the raw text by
	# `test_the_written_numbers_are_integers_rather_than_widened_floats`.
	var carried: Dictionary = c.get("something_the_tool_has_never_heard_of", {})
	assert_eq(int(carried.get("nested", 0)), 7,
			"a key the tool cannot read is carried through untouched")
	assert_eq(c.get(CampaignDef.ORDER_KEY, []), ["scenario_1", "scenario_2"],
			"appended, and appended LAST")


## ⚠️ **RE-EXPORTING A SCENARIO IS THE ORDINARY WAY TO FIX ONE.** A duplicate order entry would
## make the campaign play it twice and shift every index after it — and the index is what
## `CampaignProgress` records a win against.
func test_re_exporting_the_same_folder_does_not_name_it_twice() -> void:
	var root := _root()
	var doc := _map()
	_export(doc, root)
	# THE SAME DOCUMENT, which is now pointed at the scenario folder -- so this is the exact gesture
	# an author makes when they notice the description was wrong.
	_export(doc, root, {"description": "corrected"})

	var c := _read(root.path_join("TestCampaign").path_join(CampaignDef.JSON_FILE))
	assert_eq(c.get(CampaignDef.ORDER_KEY, []), ["scenario_1"])
	var s := _read(_scenario_dir(root).path_join(ScenarioDef.JSON_FILE))
	assert_eq(str(s.get("description", "")), "corrected", "the second export did land")


# ── refusals ────────────────────────────────────────────────────────────────

## ⛔ **EXPORT CREATES; OPEN-THEN-SAVE REPLACES.** The target is a campaign folder under version
## control and the five How To Play maps live in one, so a mistyped folder must not overwrite
## shipped content in a save that reports success. `save_as()`'s rule, with more to lose.
func test_export_refuses_to_land_on_a_scenario_that_already_has_a_map() -> void:
	var root := _root()
	_export(_map("First"), root)

	var other := _map("Different")
	var refused := ScenarioExport.new().run(other, _request(), _guard(), root)
	assert_eq(refused.size(), 1, "%s" % [refused])
	assert_true(refused[0].contains("already a map"), refused[0])
	assert_true(refused[0].contains("Save"), "it names the gesture that DOES replace one")

	# AND THE FILE IS UNTOUCHED, which is the half that matters.
	var s := _read(_scenario_dir(root).path_join(ScenarioDef.JSON_FILE))
	assert_eq(str(s.get("name", "")), "The First Lesson")


## ⛔ **THE GAME'S OWN GATE, COPIED RATHER THAN INVENTED.** `SkirmishScreen` refuses to start a
## saved map with more active slots than it seats, because `MapGen.build_from()` gives a player a
## base only by spawning the entities the map LISTS for their index — so a player beyond the map's
## count starts alive, owning nothing, and is defeated on the first tick anything looks.
func test_export_refuses_more_players_than_the_map_seats() -> void:
	var root := _root()
	var refused := ScenarioExport.new().run(_map(), _request({
		"opponents": ["passive", "easy", "normal"],
	}), _guard(), root)
	assert_false(refused.is_empty(), "a 4-player scenario on a 2-seat map must refuse")
	var said := " | ".join(PackedStringArray(refused))
	assert_true(said.contains("seats 2"), said)
	assert_true(said.contains("names 4"), said)


## ⚠️ **AND THE SAME RULE READ THE OTHER WAY.** The skirmish screen allows fewer players than
## seats, so refusing it here would make the tool stricter than the game about a map that plays
## perfectly well with a spare start on it.
func test_fewer_players_than_seats_is_a_warning_and_still_exports() -> void:
	var root := _root()
	var doc := MapDocument.create(Vector2i(96, 96), "Four Seats")
	doc.place_start(1, Vector2i(14, 14))
	doc.place_start(2, Vector2i(80, 14))
	doc.place_start(3, Vector2i(14, 80))
	doc.place_start(4, Vector2i(80, 80))
	assert_eq(doc.seats(), 4, "fixture")

	var x := _export(doc, root)
	var said := " | ".join(PackedStringArray(x.warnings))
	assert_true(said.contains("stand"), "the spare starts are mentioned: %s" % said)
	assert_true(MapFile.exists_in(_scenario_dir(root)), "and it exported anyway")


func test_export_refuses_a_scenario_with_no_opponent() -> void:
	var refused := ScenarioExport.new().run(_map(), _request({"opponents": []}),
			_guard(), _root())
	assert_false(refused.is_empty())
	assert_true(" | ".join(PackedStringArray(refused)).contains("at least one opponent"),
			"%s" % [refused])


## ⛔ **AN UNKNOWN LEVEL IS A SCENARIO THAT WILL NOT START**, refused by
## `ScenarioDef._read_opponents` against `AIProfile.IDS`. Checked here because the only other place
## it would surface is a greyed PLAY button in another project.
func test_export_refuses_an_ai_level_the_game_does_not_have() -> void:
	var refused := ScenarioExport.new().run(_map(), _request({"opponents": ["brutal"]}),
			_guard(), _root())
	assert_false(refused.is_empty())
	assert_true(" | ".join(PackedStringArray(refused)).contains("brutal"), "%s" % [refused])


func test_export_refuses_a_folder_name_a_directory_cannot_carry() -> void:
	for bad in ["", "has spaces", "slash/es"]:
		var refused := ScenarioExport.new().run(_map(), _request({"folder": bad}),
				_guard(), _root())
		assert_false(refused.is_empty(), "'%s' should be refused as a folder name" % bad)


## ⚠️ **CLAMPED IN THE GAME MEANS SILENT IN THE GAME.** `ScenarioDef.from_dict` does
## `clampi(..., 1, 4)`, so an author who meant age 3 and typed 30 gets age 4 and no complaint
## anywhere. The tool is where there is somebody to tell.
func test_export_refuses_a_starting_age_the_game_would_silently_clamp() -> void:
	var refused := ScenarioExport.new().run(_map(), _request({"starting_age": 30}),
			_guard(), _root())
	assert_false(refused.is_empty())
	assert_true(" | ".join(PackedStringArray(refused)).contains("clamp"), "%s" % [refused])


## ⛔ **THE PERMISSION TO EXPORT IS ITS OWN QUESTION.** Schema drift reaches no map file at all, so
## it must not disable Save — and it must not be a note somebody scrolls past either, because what
## it costs is a campaign mission that will not start.
func test_a_drifted_schema_refuses_the_export_and_names_the_declaration() -> void:
	var root := _root()
	var refused := ScenarioExport.new().run(_map(), _request(), _drifted_guard(), root)
	assert_eq(refused.size(), 1)
	assert_true(refused[0].contains("_MODES"), refused[0])
	assert_true(refused[0].contains("Saving a map is"), "it says what is NOT affected")
	assert_false(MapFile.exists_in(_scenario_dir(root)), "nothing is written")


func test_a_null_guard_refuses_rather_than_skipping_the_check() -> void:
	var refused := ScenarioExport.new().run(_map(), _request(), null, _root())
	assert_eq(refused.size(), 1, "%s" % [refused])


# ── the map block, which is provenance ──────────────────────────────────────

## ⛔ **A MAP AUTHORED IN THIS TOOL WAS NEVER GENERATED, SO IT HAS NO SEED.** Writing `"seed": 0`
## would be a field that reads as provenance and is not. `ScenarioDef._read_map` accepts the
## absence as of 16.8, because the saved `map.png` has been the map since 2026-09-01.
func test_an_authored_map_writes_no_map_block_at_all() -> void:
	var root := _root()
	_export(_map(), root)
	var s := _read(_scenario_dir(root).path_join(ScenarioDef.JSON_FILE))
	assert_false(s.has(ScenarioExport.MAP_KEY),
			"an authored map has no seed and no type to record")


## And the other direction: a map opened from generated output carries its provenance forward.
func test_a_generated_maps_provenance_is_carried_into_the_scenario() -> void:
	var root := _root()
	var source := root.path_join("source_map")
	var built := _map("Generated")
	MapFile.save(built.data, source, {
		"name": "Generated", "map_type": "RIVER", "seed": 815101, "authored_by": "the test",
	})
	var problems: Array[String] = []
	var doc := MapDocument.open(source, problems)
	assert_not_null(doc, "fixture: %s" % [problems])

	_export(doc, root)
	var s := _read(_scenario_dir(root).path_join(ScenarioDef.JSON_FILE))
	var block: Dictionary = s.get(ScenarioExport.MAP_KEY, {})
	assert_eq(str(block.get("type", "")), "river", "lower-cased, the way the schema spells it")
	assert_eq(int(block.get("seed", 0)), 815101)


# ── the document moves, and so do its conditions ────────────────────────────

## ⛔ **THE FIRST SAVE PUTS THE ROWS IN THE SIDECAR, BECAUSE AT THAT MOMENT THERE IS NO SCENARIO.**
## If the export stopped there the conditions would exist in two files, and the one the game reads
## would not be the one the tool writes to next. This is the single most load-bearing assertion in
## the file.
func test_the_conditions_end_up_in_the_scenario_and_not_in_the_map_sidecar() -> void:
	var root := _root()
	var doc := _map()
	var problems: Array[String] = []
	doc.add_objective(WIN_ROW, problems)
	_export(doc, root)

	var dir := _scenario_dir(root)
	var sidecar := _read(dir.path_join(MapFile.META_FILE))
	assert_false(sidecar.has("objectives"),
			"the map sidecar must not keep a stale second copy: %s" % [sidecar.get("objectives")])
	var s := _read(dir.path_join(ScenarioDef.JSON_FILE))
	assert_eq((s.get("objectives", []) as Array).size(), 1)


## ⚠️ **AND THE DOCUMENT KNOWS WHERE IT LIVES NOW**, which is what makes the Conditions panel edit
## the file the game reads. `scenario_mode` is read back separately because `MapDocument.save()`
## resolves the path and not the mode — only `open()` ever set the second.
func test_the_document_is_re_pointed_at_what_it_just_wrote() -> void:
	var root := _root()
	var doc := _map()
	var problems: Array[String] = []
	doc.add_objective(WIN_ROW, problems)
	_export(doc, root)

	assert_eq(doc.dir, _scenario_dir(root), "Save now writes to the scenario folder")
	assert_eq(doc.scenario_path, _scenario_dir(root).path_join(ScenarioDef.JSON_FILE))
	assert_eq(doc.scenario_mode, "scenario", "and it knows what that file says decides it")
	assert_false(doc.dirty, "an exported map has just been saved")


# ── the icon slots ──────────────────────────────────────────────────────────

func _write_png(path: String) -> String:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	image.save_png(path)
	return path


func test_a_chosen_picture_is_copied_into_its_slot_under_the_games_own_name() -> void:
	var root := _root()
	var art := root.path_join("art")
	DirAccess.make_dir_recursive_absolute(art)
	var x := ScenarioExport.new()
	var problems := x.run(_map(), _request({"icons": {
		"scenario": _write_png(art.path_join("anything.png")),
		"campaign": _write_png(art.path_join("whatever.png")),
		"background": _write_png(art.path_join("backdrop.png")),
	}}), _guard(), root)
	assert_true(problems.is_empty(), "%s" % [problems])

	var campaign_dir := root.path_join("TestCampaign")
	assert_true(FileAccess.file_exists(_scenario_dir(root).path_join(ScenarioDef.ICON_FILE)))
	assert_true(FileAccess.file_exists(campaign_dir.path_join(CampaignDef.ICON_FILE)))
	assert_true(FileAccess.file_exists(campaign_dir.path_join(CampaignDef.BACKGROUND_FILE)))
	# ⚠️ **COPIED, NEVER MOVED**: the source is somebody's art directory.
	assert_true(FileAccess.file_exists(art.path_join("anything.png")), "the source survives")


## ⚠️ **AN EMPTY SLOT IS A WARNING THAT NAMES THE PATH, NOT THE PROBLEM.** *"No campaign icon"*
## sends an author looking for a setting; a full path is something they can drag a file onto.
func test_an_empty_slot_is_a_warning_naming_the_file_to_drop_in() -> void:
	var root := _root()
	var x := _export(_map(), root)
	assert_eq(x.warnings.size(), 3, "three slots, all empty: %s" % [x.warnings])
	var said := " | ".join(PackedStringArray(x.warnings))
	assert_true(said.contains(ScenarioDef.ICON_FILE), said)
	assert_true(said.contains(CampaignDef.BACKGROUND_FILE), said)


## And it asks the DISK rather than the request, so the second mission in a campaign that already
## has its tile is not nagged about it every time.
func test_a_slot_already_filled_is_not_reported_as_missing() -> void:
	var root := _root()
	var art := root.path_join("art")
	DirAccess.make_dir_recursive_absolute(art)
	ScenarioExport.new().run(_map(), _request({"icons": {
		"campaign": _write_png(art.path_join("tile.png")),
	}}), _guard(), root)

	var x := _export(_map("Second"), root, {"folder": "scenario_2", "name": "Second"})
	var said := " | ".join(PackedStringArray(x.warnings))
	assert_false(said.contains(CampaignDef.ICON_FILE),
			"the campaign tile is already there: %s" % said)


# ── the numbers ─────────────────────────────────────────────────────────────

## ⛔ **JSON HAS ONE NUMBER TYPE AND GODOT PARSES IT AS A FLOAT**, so a plain round trip turns
## every integer in a file into `n.0`. Harmless to the loader and a real cost on content under
## version control: it makes a genuine change impossible to see in a review.
##
## **THE RAW TEXT IS READ**, because `JSON.parse` would give back floats either way and the test
## would pass on a file full of them.
func test_the_written_numbers_are_integers_rather_than_widened_floats() -> void:
	var root := _root()
	var doc := _map()
	var problems: Array[String] = []
	doc.add_objective(WIN_ROW, problems)
	_export(doc, root, {"starting_age": 2})

	var text := FileAccess.get_file_as_string(
			_scenario_dir(root).path_join(ScenarioDef.JSON_FILE))
	assert_true(text.contains("\"starting_age\": 2"), "got: %s" % text.substr(0, 400))
	assert_true(text.contains("\"value\": 14"), "the objective's value too")
	assert_false(text.contains(".0"), "nothing in this schema wants a float")


# ── the guard ───────────────────────────────────────────────────────────────

## ⛔ **THE ROW THAT SAYS THE TOOL AND THE GAME STILL SPEAK THE SAME LANGUAGE.** If this fails, the
## game's scenario schema has moved and the stand-ins in `format/` have not — the export is refused
## in the tool, and this is the message that says which declaration to bring into line.
func test_the_scenario_schema_still_matches_the_game() -> void:
	var guard := _guard()
	for r in guard.schema_results:
		assert_eq(int(r["status"]), int(FormatGuard.Status.OK),
				"%s — %s" % [r["name"], r["detail"]])
	assert_true(guard.schema_ok(), guard.schema_refusal())


## ⚠️ **AND THE THREE QUESTIONS ARE SEPARATE.** Schema drift must not disable saving a map, and
## map-format drift must not be reported as an export problem — each list answers for the files it
## actually decides.
func test_the_three_guard_questions_are_independent() -> void:
	var drifted := _drifted_guard()
	assert_false(drifted.schema_ok(), "the schema is the one that is wrong")
	assert_true(drifted.passed(), "a drifted schema does not stop a map being saved")


func test_startups_export_permission_is_narrower_than_its_save_permission() -> void:
	var s := Startup.new()
	s.state = Startup.State.OK
	s.guard = _drifted_guard()
	assert_true(s.can_save(), "a drifted schema reaches no map file")
	assert_false(s.can_export(), "and it reaches every scenario file")


# ── the panel ───────────────────────────────────────────────────────────────

func _panel(doc: MapDocument, root: String) -> ExportPanel:
	var panel := ExportPanel.new()
	_nodes.append(panel)
	panel.set_document(doc)
	panel.set_startup(_ok_startup())
	panel.set_root(root)
	panel.open()
	return panel


func _ok_startup() -> Startup:
	var s := Startup.new()
	s.state = Startup.State.OK
	s.guard = _guard()
	return s


## ⚠️ **THE DEFAULTS COME OFF THE MAP**, because they are the ones that cannot be wrong: a scenario
## is the human plus bots, and the map decides how many can stand on it.
func test_the_panel_defaults_the_opponents_to_what_the_map_seats() -> void:
	var doc := MapDocument.create(Vector2i(96, 96), "Three Seats")
	doc.place_start(1, Vector2i(14, 14))
	doc.place_start(2, Vector2i(80, 14))
	doc.place_start(3, Vector2i(14, 80))
	var panel := _panel(doc, _root())

	var r := panel.request()
	assert_eq((r["opponents"] as Array).size(), 2, "three seats, one of them the human")
	assert_eq(str(r["name"]), "Three Seats", "the map's name is the scenario's first guess")


func test_the_panel_lists_the_campaigns_on_disk_and_offers_a_new_one() -> void:
	var root := _root()
	_export(_map(), root)

	var panel := _panel(_map("Another"), root)
	assert_eq(panel.campaign_rows().size(), 1)
	assert_eq(str(panel.campaign_rows()[0]["folder"]), "TestCampaign")
	# THE NEW ROW IS ALWAYS THERE, and is what a repo with no campaigns at all preselects.
	var labels: Array[String] = []
	for i in panel._campaign.item_count:
		labels.append(panel._campaign.get_item_text(i))
	assert_true(labels.has("new campaign…"), "%s" % [labels])


## ⚠️ **THE NEXT FREE FOLDER ON DISK, NOT THE ORDER LIST'S LENGTH + 1.** A campaign whose order
## names three folders may hold a fourth the list forgot — `Campaigns` reports exactly that — and
## handing that number back would aim the export at somebody's work in progress.
func test_choosing_a_campaign_defaults_the_scenario_to_the_next_free_folder() -> void:
	var root := _root()
	_export(_map(), root)

	var panel := _panel(_map("Another"), root)
	panel._select_key(panel._campaign, "TestCampaign")
	panel._on_campaign_chosen()
	assert_eq(str(panel.request()["folder"]), "scenario_2")


## ⛔ **ADDING A MISSION MUST NOT RENAME THE CAMPAIGN**, so the identity fields are disabled and
## `request()` reads the PICKER rather than the field. A disabled `LineEdit` still holds text, so
## the two can disagree.
func test_picking_an_existing_campaign_greys_its_identity_fields() -> void:
	var root := _root()
	_export(_map(), root)

	var panel := _panel(_map("Another"), root)
	panel._select_key(panel._campaign, "TestCampaign")
	panel._on_campaign_chosen()
	assert_false(panel._campaign_folder.editable, "the folder is the progress key")
	assert_false(panel._campaign_name.editable)
	assert_eq(str(panel.request()["campaign_folder"]), "TestCampaign")


## ⛔ **THE DERIVED MODE IS ON SCREEN**, because it is the one field of the schema with no control —
## and *"why is my scenario won by conquest"* is not a question anything else here can answer.
func test_the_summary_says_which_mode_will_be_written_and_why() -> void:
	var doc := _map()
	var panel := _panel(doc, _root())
	assert_true(panel.summary_text().contains("last_man_standing"), panel.summary_text())
	assert_true(panel.summary_text().contains("conquest"), panel.summary_text())

	var problems: Array[String] = []
	doc.add_objective(WIN_ROW, problems)
	panel.refresh()
	assert_true(panel.summary_text().contains("\"scenario\""), panel.summary_text())
	# TWO OF TWO: the panel's default is the map's seats minus one opponent, plus the human.
	assert_true(panel.summary_text().contains("2 of 2 seat(s)"), panel.summary_text())


func test_the_panel_exports_through_the_same_path_the_suite_does() -> void:
	var root := _root()
	var doc := _map("Panel Map")
	var panel := _panel(doc, root)
	panel.fill_request(_request())
	assert_true(panel.press_export(), "refused: %s" % panel.message())

	assert_true(MapFile.exists_in(_scenario_dir(root)))
	var s := _read(_scenario_dir(root).path_join(ScenarioDef.JSON_FILE))
	assert_eq(str(s.get("name", "")), "The First Lesson")
	# THE WARNINGS ARE SHOWN ON SUCCESS and are not a failure -- three empty icon slots.
	assert_true(panel.message().contains("exported"), panel.message())


func test_the_panel_puts_every_refusal_in_front_of_the_author() -> void:
	var root := _root()
	var panel := _panel(_map(), root)
	panel.fill_request(_request({"folder": "has spaces", "opponents": []}))
	assert_false(panel.press_export())
	assert_true(panel.message().contains("has spaces"), panel.message())
	assert_true(panel.message().contains("opponent"),
			"both refusals, not the first one: %s" % panel.message())


## §6's row: *"a disabled control's reason for being disabled is not the same fact as its being
## disabled"*. The grey is the visible half; the message line is the fact.
func test_the_export_button_goes_dead_and_says_why_on_a_drifted_schema() -> void:
	var panel := ExportPanel.new()
	_nodes.append(panel)
	var s := Startup.new()
	s.state = Startup.State.OK
	s.guard = _drifted_guard()
	panel.set_document(_map())
	panel.set_startup(s)
	assert_true(panel._export_button.disabled)
	assert_true(panel.message().contains("_MODES"), panel.message())


## ⛔ **THE 2026-09-04 MAIN-SCENE BUG, IN A PANEL.** A screen that only works when something else
## ran first is a screen that will one day be opened directly, so a missing `Startup` refuses
## rather than being quietly treated as fine.
func test_a_panel_with_no_startup_refuses_rather_than_exporting_unchecked() -> void:
	var root := _root()
	var panel := ExportPanel.new()
	_nodes.append(panel)
	panel.set_document(_map())
	panel.set_root(root)
	panel.fill_request(_request())
	assert_false(panel.press_export(), "no guard means no export")
	assert_false(MapFile.exists_in(_scenario_dir(root)))
