## PLAN.md 16.6: the Map Conditions editor — the vocabulary, the storage, the round trip and the
## undo step.
##
## ## WHAT THIS ROW COULD BE QUIETLY WRONG ABOUT
##
## The panel itself is a picture and `dev/preview_editor.tscn` is what looks at it. **What a
## headless test can see is every place this row could be wrong with nothing failing:**
##
##   - ⛔ **THE WORDS-VERSUS-INTEGERS MISTAKE, which is the one that would not surface until
##     16.8.** `ObjectiveDef.to_dict()` is the WIRE form and every enum in it is an int; a
##     `scenario.json` holds the author's words. Storing parsed defs and writing `to_dict()` back
##     out would produce a file of integers that `ObjectiveDef.from_dict` cannot read at all —
##     and the tool would look perfect the whole time, because it never re-parses its own output.
##   - ⛔ **DELETING THE LAST CONDITION NOT REACHING THE FILE.** `_preserved_header()` filters by
##     what `MapData.to_dict()` derives, and it never derives `objectives` — so the OPENED file's
##     rows sit in the header waiting to be written straight back. This is 16.5's `areas` trap
##     arriving through the opposite door, and its symptom is a row that returns on reopen after a
##     save that reported success.
##   - ⚠️ **UNDO.** `MapEdit` snapshots four lists now and the fourth is not on `MapData`. A step
##     that recorded conditions without recording entities would, on redo, assign an empty entity
##     list — *every building on the map deleted by pressing redo*. And an EDIT is an in-place
##     change the size test cannot see, so without `mark_changed()` it is discarded as a no-op.
##   - ⚠️ **`dirty` LYING.** This is why conditions are in the history at all. A condition edit
##     kept outside the stack would be erased from `at_clean_point()`'s reckoning, and the tool
##     would report no unsaved work with an unsaved condition in it.
##   - ⚠️ **A SECOND DIALECT.** The panel's pickers are derived from `ObjectiveDef`'s own
##     constants, so a subject the loader refuses cannot be offered and a subject it gains appears
##     with no edit. A written-out list here would be the thing PLAN.md 11.8a forbids.
##
## Nothing here writes into repo-root `maps/` or `scenarios/` — `test_map_document`'s rule.
extends TestCase

const SCRATCH := "user://test_conditions"

var doc: MapDocument = null
var panel: ConditionPanel = null
var _n := 0


func before_each() -> void:
	GameDataRegistry.load_from(GameRoot.resolve())
	doc = MapDocument.create(Vector2i(96, 96), "Condition Test")


func after_each() -> void:
	if panel != null:
		panel.free()
		panel = null
	_scrub()


func _scrub() -> void:
	if DirAccess.dir_exists_absolute(SCRATCH):
		OS.move_to_trash(ProjectSettings.globalize_path(SCRATCH))


## A fresh directory per save, so one test's file cannot be read by the next.
func _dir() -> String:
	_n += 1
	var path := "%s/run_%d" % [SCRATCH, _n]
	DirAccess.make_dir_recursive_absolute(path)
	return path


## The shorthand every row here is built from. `>=` and `win` are `from_dict`'s own defaults.
func _row(d: Dictionary) -> Dictionary:
	var base: Dictionary = {"subject": "unit", "owner": "self", "compare": ">=", "output": "win",
			"value": 1}
	base.merge(d, true)
	return base


func _add(d: Dictionary) -> bool:
	var problems: Array[String] = []
	return doc.add_objective(_row(d), problems)


func _panel() -> ConditionPanel:
	panel = ConditionPanel.new()
	panel.set_document(doc)
	return panel


## Save `d` under a fresh scratch parent and hand back the directory it actually landed in.
##
## ⚠️ **`MapDocument.save()` TAKES THE PARENT AND APPENDS `slug()`, WHICH IS NOT WHAT IT LOOKS
## LIKE.** The map goes to `<maps_dir>/<slug>/`, not to `<maps_dir>/` — that is the whole reason
## `maps_dir` is named for a directory holding maps rather than for one map. The first version of
## this file opened the parent and got *"map.json does not exist"*, which reads as a save that
## silently failed. Saved once and the path returned, so no test can call `save()` twice by
## accident either — `%s % [doc.save(dir)]` in an assertion message does exactly that.
func _saved(d: MapDocument) -> String:
	var parent := _dir()
	var problems := d.save(parent)
	assert_true(problems.is_empty(), "the save has to succeed: %s" % [problems])
	return d.dir


# ── the records are the AUTHOR'S WORDS ──────────────────────────────────────

## ⛔ **THE MOST IMPORTANT TEST IN THIS FILE, and the one whose failure would not show up until
## 16.8 tried to export.** What is stored has to be what a `scenario.json` holds — words — and
## not what the wire holds, which is integers. Asserted on the TYPE as well as the value, because
## `"subject": 0` and `"subject": "unit"` are both truthy things to find in a dictionary.
func test_a_stored_condition_is_the_authors_words_and_not_the_wire_form() -> void:
	assert_true(_add({"subject": "building", "id": "building.house", "compare": ">=",
			"value": 1, "output": "win"}))
	var stored: Dictionary = doc.objectives[0]
	assert_true(stored["subject"] is String, "a subject is a word: got %s" % [stored["subject"]])
	assert_eq(str(stored["subject"]), "building")
	assert_eq(str(stored["compare"]), ">=", "and a comparison is its symbol, not an enum index")
	assert_eq(str(stored["output"]), "win")
	# AND IT IS READABLE BY THE GAME'S OWN LOADER, which is the whole point of storing words.
	var problems: Array[String] = []
	assert_not_null(ObjectiveDef.from_dict(stored, problems),
			"the game must be able to read back what the tool wrote: %s" % [problems])


func test_a_row_the_loader_refuses_is_refused_here_in_the_loaders_own_words() -> void:
	# `add_entity()`'s rule applied to a condition: a record that cannot parse can never mean
	# anything to anybody, and there is a person standing right here to tell.
	var problems: Array[String] = []
	assert_false(doc.add_objective({"subject": "bulding", "compare": ">=", "value": 1}, problems))
	assert_true(doc.objectives.is_empty(), "and nothing is stored")
	assert_eq(problems.size(), 1, "%s" % [problems])
	assert_true(problems[0].contains("unknown subject"), problems[0])


func test_a_refused_row_records_no_undo_step() -> void:
	# `add_entity()`'s rule again: the step is opened AFTER the refusal, so the author's next
	# Ctrl+Z reaches the last thing that actually landed rather than an invisible failed attempt.
	assert_true(_add({"value": 3}))
	var problems: Array[String] = []
	doc.add_objective({"subject": "nonsense", "compare": ">=", "value": 1}, problems)
	assert_eq(doc.undo(), "add win condition", "the refusal is not on the stack")


# ── 16.6's own subject reaches the tool ─────────────────────────────────────

## The row's own deliverable, from the tool's end. A time limit is one more condition, in ticks.
func test_a_time_limit_is_one_more_row_and_it_is_in_ticks() -> void:
	assert_true(_add({"subject": "ticks", "compare": ">=", "value": 6000, "output": "lose",
			"text": "Ten minutes"}),
			"`ticks` stopped being refused at 16.6 and the tool is what authors it")
	assert_eq(str(doc.objectives[0]["subject"]), "ticks")


func test_the_subject_picker_offers_what_the_loader_accepts_and_nothing_it_refuses() -> void:
	# ⚠️ **DERIVED, NOT WRITTEN OUT** — see `ConditionPanel`'s header. A list typed into the panel
	# would be the second dialect PLAN.md 11.8a forbids, and it would go stale in the direction
	# nobody notices: offering a subject the loader rejects.
	var offered := ConditionPanel._subject_keys()
	assert_true(offered.has("unit"), "%s" % [offered])
	assert_true(offered.has("area"), "16.5's subject: %s" % [offered])
	assert_true(offered.has("ticks"), "16.6's own subject: %s" % [offered])
	# AND THE ONE STILL DEFERRED IS ABSENT. When 16.7 deletes that line from `_NOT_YET` this
	# assertion fails and names the row that has to change — which is the same mechanical reminder
	# `test_campaigns` runs on the game side.
	assert_false(offered.has("named_unit"),
			"`named_unit` is refused until 16.7, so offering it would be a row an author"
			+ " can fill in and be refused on: %s" % [offered])


# ── the round trip ──────────────────────────────────────────────────────────

func test_conditions_survive_a_save_and_an_open() -> void:
	assert_true(_add({"id": "unit.villager", "value": 10, "text": "Reach 10 villagers"}))
	assert_true(_add({"subject": "ticks", "value": 6000, "output": "lose"}))
	var dir := _saved(doc)

	var problems: Array[String] = []
	var back := MapDocument.open(dir, problems)
	assert_not_null(back, "%s" % [problems])
	assert_eq(back.objectives.size(), 2)
	assert_eq(str(back.objectives[0]["id"]), "unit.villager")
	assert_eq(str(back.objectives[0]["text"]), "Reach 10 villagers")
	assert_eq(str(back.objectives[1]["subject"]), "ticks")
	assert_eq(str(back.objectives[1]["output"]), "lose")


## ⛔ **THE `_preserved_header()` TRAP, AND IT IS THE REASON `save()` WRITES THE KEY WHEN THE LIST
## IS EMPTY.** The filter drops what `MapData.to_dict()` derives and `objectives` is not among
## them, so the opened file's rows are sitting in `header` at save time. A conditional write would
## put them straight back — the author's deletion silently undone, on reopen, after a save that
## said it worked. `MapData.to_dict()` writes `areas` unconditionally for the mirror image of this.
func test_deleting_the_last_condition_reaches_the_file() -> void:
	assert_true(_add({"value": 5}))
	var dir := _saved(doc)

	var problems: Array[String] = []
	var back := MapDocument.open(dir, problems)
	assert_not_null(back, "%s" % [problems])
	assert_eq(back.objectives.size(), 1)
	assert_eq(back.remove_objective(0), 1)
	# ⚠️ **OPEN-THEN-SAVE REPLACES IN PLACE** (16.4a's rule), so this writes back over `dir`
	# itself rather than into a slug beneath it — `back.dir` is set and `save()` re-uses it. That
	# is exactly the path an author re-authoring a map takes, which is the path this trap lives on.
	assert_true(back.save(dir).is_empty())

	var again: Array[String] = []
	var third := MapDocument.open(dir, again)
	assert_not_null(third, "%s" % [again])
	assert_true(third.objectives.is_empty(),
			"the deletion has to reach the file, or the row returns on reopen: %s"
			% [third.objectives])


## A map written before 16.6 has no `objectives` key at all, and must open as a map with none
## rather than as a map that will not open. Same absent-means-none rule 16.5's areas follow.
func test_a_map_with_no_conditions_key_opens_as_a_map_with_none() -> void:
	var dir := _dir()
	assert_true(MapFile.save(doc.data, dir, {"name": "Older Map"}).is_empty())
	var problems: Array[String] = []
	var back := MapDocument.open(dir, problems)
	assert_not_null(back, "%s" % [problems])
	assert_true(back.objectives.is_empty())
	assert_true(back.objective_problems().is_empty(), "and it is a healthy map, not a broken one")


## ⚠️ **AN UNREADABLE ROW IS KEPT AND REPORTED, NEVER DROPPED.** Opening a hand-written scenario's
## map, saving it, and finding the condition gone is 16.4a's *"every change silently discarded in
## a save that reports success"* running backwards. The panel's list is where it is announced.
func test_a_row_this_build_cannot_read_survives_being_opened() -> void:
	var dir := _dir()
	assert_true(MapFile.save(doc.data, dir, {"name": "Odd Map", "objectives": [
		{"subject": "from_a_later_build", "compare": ">=", "value": 1},
	]}).is_empty())
	var problems: Array[String] = []
	var back := MapDocument.open(dir, problems)
	assert_eq(back.objectives.size(), 1, "the row is kept")

	panel = ConditionPanel.new()
	panel.set_document(back)
	assert_eq(panel.rows().size(), 1)
	assert_true(panel.rows()[0].begins_with("⚠ unreadable"),
			"and it is announced rather than drawn as a condition: %s" % panel.rows()[0])


# ── undo (PLAN.md 16.2a, one row on) ────────────────────────────────────────

func test_adding_a_condition_is_one_undo_step() -> void:
	assert_true(_add({"value": 4}))
	assert_eq(doc.objectives.size(), 1)
	doc.undo()
	assert_true(doc.objectives.is_empty(), "undo takes the condition back")
	doc.redo()
	assert_eq(doc.objectives.size(), 1, "and redo puts it back")
	assert_eq(int(doc.objectives[0]["value"]), 4)


## ⚠️ **THE `mark_changed()` TEST, AND IT IS THE ONE THE SIZE COMPARISON CANNOT SEE.** An edit is
## an in-place change: same list length, same starts, same entities. `MapEdit.close()` would
## discard the step as a no-op, and an edited condition could not be taken back — which is exactly
## the fault 16.2a predicted for 16.4's move cursor, arriving a second time.
func test_editing_a_condition_in_place_is_still_an_undo_step() -> void:
	assert_true(_add({"value": 5}))
	var problems: Array[String] = []
	assert_true(doc.set_objective(0, _row({"value": 10}), problems), "%s" % [problems])
	assert_eq(int(doc.objectives[0]["value"]), 10)

	doc.undo()
	assert_eq(doc.objectives.size(), 1, "the row is still there")
	assert_eq(int(doc.objectives[0]["value"]), 5,
			"and its value came back -- without `mark_changed()` this step is discarded")


func test_removing_a_condition_is_one_undo_step() -> void:
	assert_true(_add({"value": 2}))
	assert_true(_add({"value": 3}))
	assert_eq(doc.remove_objective(0), 1)
	assert_eq(doc.objectives.size(), 1)
	doc.undo()
	assert_eq(doc.objectives.size(), 2, "both are back")
	assert_eq(int(doc.objectives[0]["value"]), 2, "and in the order they were in")


## ⚠️ **A STEP THAT TOOK NO LIST SNAPSHOT MUST LEAVE THE CONDITIONS ALONE.** `undo_into()` returns
## the caller's own list when it never recorded one — without that gate a paint step would hand
## back the empty default and undoing a brush stroke would delete every condition on the map.
## This is the conditions half of the hazard `MapEdit._closed` exists for.
func test_undoing_a_paint_stroke_leaves_the_conditions_alone() -> void:
	assert_true(_add({"value": 7}))
	doc.paint(Vector2i(4, 4), SimMap.Terrain.WATER_DEEP)
	doc.undo()
	assert_eq(doc.data.terrain_at(Vector2i(4, 4)), SimMap.Terrain.GRASS, "the tile came back")
	assert_eq(doc.objectives.size(), 1, "and the condition is untouched")


## ⛔ **THE REASON CONDITIONS ARE IN THE HISTORY AT ALL.** `MapDocument.undo()` recomputes `dirty`
## from `at_clean_point()`, so a condition edit kept outside the stack would vanish from that
## reckoning: edit a row, paint a tile, undo the tile, and the tool would report no unsaved work
## with an unsaved condition sitting in it. An invisible undo step is a confusion; a `dirty` flag
## that says "saved" about unsaved work is lost work.
func test_a_condition_edit_keeps_the_map_dirty_after_an_unrelated_undo() -> void:
	var dir := _dir()
	assert_true(doc.save(dir).is_empty())
	assert_false(doc.dirty, "a freshly saved map is clean")

	assert_true(_add({"value": 9}))
	doc.paint(Vector2i(5, 5), SimMap.Terrain.SAND)
	doc.undo()
	assert_true(doc.dirty,
			"the paint came back but the condition did not -- this map differs from its file")


# ── what the tool warns about, and what it must not ─────────────────────────

## ⚠️ **PLAN.md 16.6's OWN RULING: no conditions at all is a HEALTHY map**, because owning nothing
## is defeat on every map in this game whatever it declares. A tool that nagged about an empty
## list would be nagging about every skirmish map there is.
func test_a_map_with_no_conditions_is_not_complained_about() -> void:
	assert_true(doc.objective_problems().is_empty(), "%s" % [doc.objective_problems()])


## And the shape that genuinely cannot be won. `ScenarioDef` refuses a `scenario` with no win row
## at load; this is the same fact said to the author while they can still fix it.
func test_conditions_with_no_win_row_are_warned_about() -> void:
	assert_true(_add({"value": 1, "output": "lose"}))
	var problems := doc.objective_problems()
	assert_eq(problems.size(), 1, "%s" % [problems])
	assert_true(problems[0].contains("none of them is a win"), problems[0])
	# ⚠️ **AND IT IS A WARNING, NOT A REFUSAL.** 16.4b's rule: the tool must not refuse to WRITE
	# over an opinion about the map. An author who adds their lose row first is mid-thought.
	var dir := _dir()
	assert_true(doc.save(dir).is_empty(), "an unfinished list still saves")
	assert_true(_summarised(doc.warnings).contains("none of them is a win"),
			"and the save says so: %s" % [doc.warnings])


func test_adding_a_win_row_clears_the_complaint() -> void:
	assert_true(_add({"value": 1, "output": "lose"}))
	assert_true(_add({"value": 5, "output": "win"}))
	assert_true(doc.objective_problems().is_empty(), "%s" % [doc.objective_problems()])
	assert_eq(doc.win_count(), 1)


## ⚠️ **THE CHECK ONLY THIS TOOL CAN MAKE EARLY.** An `area` row naming a region the map has not
## got counts 0 forever — an unwinnable scenario whose only symptom is that nothing happens.
## `ScenarioDef.build_config()` refuses it at launch, which reaches a player; this reaches the
## AUTHOR, and it is possible here for the one reason it is impossible in `ObjectiveDef`: this is
## the only place in either project where the conditions and the map are open together.
func test_an_area_row_naming_a_region_the_map_has_not_got_is_warned_about() -> void:
	assert_true(_add({"subject": "area", "area": "north_pass", "value": 1}))
	var problems := doc.objective_problems()
	assert_eq(problems.size(), 1, "%s" % [problems])
	assert_true(problems[0].contains("north_pass"), problems[0])
	assert_true(problems[0].contains("no regions at all"),
			"and it says what the map DOES declare, which is what sends somebody to the right"
			+ " place: %s" % problems[0])

	# AND IT CLEARS WHEN THE REGION IS DRAWN. The two halves are separate acts and an author may
	# legitimately do them in either order, which is why this is a warning and not a refusal.
	assert_true(doc.add_area(&"north_pass", Rect2i(10, 10, 4, 4)))
	assert_true(doc.objective_problems().is_empty(), "%s" % [doc.objective_problems()])


func test_the_complaint_names_the_regions_the_map_really_has() -> void:
	assert_true(doc.add_area(&"the_ford", Rect2i(20, 20, 3, 3)))
	assert_true(_add({"subject": "area", "area": "teh_ford", "value": 1}))
	var problems := doc.objective_problems()
	assert_eq(problems.size(), 1, "%s" % [problems])
	assert_true(problems[0].contains("the_ford"),
			"a typo has to be sent to the author's own spelling: %s" % problems[0])


# ── the panel ───────────────────────────────────────────────────────────────

func test_the_form_round_trips_a_record_through_its_controls() -> void:
	# The panel's two halves are inverses, and a mismatch between them is how an author edits a
	# row and silently changes a field they never touched.
	var record := _row({"subject": "resource", "id": "food", "compare": "<=", "value": 250,
			"output": "alert", "text": "Careful"})
	var p := _panel()
	p.fill_form(record)
	var back := p.form_record()
	for key in record:
		assert_eq(str(back.get(key, "")), str(record[key]),
				"'%s' did not survive the form" % key)


## ⚠️ **AN OWNER IS A WORD OR A NUMBER AND THE TYPE IS LOAD-BEARING** — `_read_owner` branches on
## it. An index sent as the string "3" falls through to the word lookup and is refused as an
## unknown owner, which is a baffling message for an ordinary intention.
func test_a_player_index_survives_the_form_as_a_number() -> void:
	var p := _panel()
	p.fill_form(_row({"owner": 3}))
	var back := p.form_record()
	assert_true(back["owner"] is int, "got %s" % [back["owner"]])
	assert_eq(int(back["owner"]), 3)

	p.fill_form(_row({"owner": "enemy"}))
	assert_true(p.form_record()["owner"] is String)
	assert_eq(str(p.form_record()["owner"]), "enemy")


func test_the_panel_lists_rows_the_way_the_game_will_draw_them() -> void:
	# Through `ObjectiveDef.describe()`, which is what 15.6's tracker draws when an author wrote
	# no `text`. A second phrasing here would let an author lay out a list that reads differently
	# in the game.
	assert_true(_add({"id": "unit.villager", "value": 10}))
	var p := _panel()
	assert_eq(p.rows().size(), 1)
	assert_true(p.rows()[0].contains("WIN"), p.rows()[0])
	assert_true(p.rows()[0].contains("unit.villager"), p.rows()[0])
	assert_true(p.rows()[0].contains("10"), p.rows()[0])


func test_the_panel_adds_edits_and_removes_through_the_document() -> void:
	var p := _panel()
	p.fill_form(_row({"value": 3}))
	assert_true(p.press_add())
	assert_eq(doc.objectives.size(), 1)

	assert_true(p.press_edit(0))
	p.fill_form(_row({"value": 8}))
	assert_true(p.press_add(), "the same button updates the row it is editing")
	assert_eq(doc.objectives.size(), 1, "an update does not append")
	assert_eq(int(doc.objectives[0]["value"]), 8)

	assert_true(p.press_remove(0))
	assert_true(doc.objectives.is_empty())


## ⚠️ **THE FORM STOPS EDITING WHEN THE LIST SHIFTS UNDER IT.** `MapDocument.selected`'s hazard,
## wearing a condition: removing row 0 while editing row 1 would leave the index pointing at what
## is now row 0, and the author's next Update would rewrite the wrong condition silently.
func test_removing_a_row_stops_the_form_editing_a_stale_index() -> void:
	assert_true(_add({"value": 1}))
	assert_true(_add({"value": 2}))
	var p := _panel()
	assert_true(p.press_edit(1))
	assert_true(p.press_remove(0))

	p.fill_form(_row({"value": 99}))
	assert_true(p.press_add())
	assert_eq(doc.objectives.size(), 2, "it appended rather than overwriting row 0")
	assert_eq(int(doc.objectives[0]["value"]), 2, "and row 0 is untouched")


func test_a_refused_row_leaves_the_form_alone_and_says_why() -> void:
	var p := _panel()
	# `resource` REQUIRES an id, so this is a real refusal from the game's own loader.
	p.fill_form(_row({"subject": "resource", "value": 500}))
	assert_false(p.press_add())
	assert_true(doc.objectives.is_empty())
	assert_true(p.message().contains("resource"), p.message())
	# ⚠️ **THE FORM IS NOT CLEARED ON A REFUSAL**, or an author fixing one typo has to retype the
	# whole condition.
	assert_eq(str(p.form_record()["subject"]), "resource")
	assert_eq(int(p.form_record()["value"]), 500)


# ── the guard ───────────────────────────────────────────────────────────────

## ⚠️ **`objective_def.gd` IS IN `COPIES`, NOT IN `PRESENTATION`, AND THE TEST IS WHETHER DRIFT
## REACHES THE FILE.** A drifted icon reader costs a wrong picture; a drifted objective parser
## decides which rows the tool accepts, and those rows are written into `map.json` and exported
## into a `scenario.json`. A tool one revision behind the game's vocabulary would author
## conditions the game then refuses — *"the tool can author maps the game misreads"* exactly.
func test_the_objective_vocabulary_is_a_guarded_copy() -> void:
	var named := false
	for entry in FormatGuard.COPIES:
		if str(entry["origin"]).ends_with("objective_def.gd"):
			named = true
	assert_true(named, "the condition vocabulary has to be hash-checked like the format is")

	for entry in FormatGuard.PRESENTATION:
		assert_false(str(entry["origin"]).ends_with("objective_def.gd"),
				"and it must not be a mere note -- drift here reaches the file")


func test_the_copy_matches_the_game() -> void:
	# The guard's own report, narrowed to this row. A failure here means the game's vocabulary
	# moved and `MapMaker/format/objective_def.gd` was not re-copied.
	var guard := FormatGuard.check(GameRoot.resolve())
	for r in guard.results:
		if str(r["name"]).ends_with("objective_def.gd"):
			assert_eq(int(r["status"]), int(FormatGuard.Status.OK), str(r["detail"]))


## Joined so a `contains` can be asserted against the whole list at once. `"%s" % array` treats
## the array as the ARGUMENT LIST and raises rather than formatting — §6's row.
static func _summarised(lines: Array[String]) -> String:
	return " | ".join(PackedStringArray(lines))
