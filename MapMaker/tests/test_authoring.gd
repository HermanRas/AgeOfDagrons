## PLAN.md 16.7, the tool's half: naming an entity and overriding its health, attack and speed.
##
## ## WHAT THESE ARE ACTUALLY GUARDING
##
## The game side owns whether an override REACHES a match (`test_authored_entities`). What is new
## here is everything around editing one, and each has a way of failing quietly:
##
##   - ⛔ **an in-place edit is invisible to the undo stack.** `MapEdit.close()` compares list
##     SIZES, so a name typed onto an existing entity changes nothing it can see — the step is
##     discarded as a no-op and **the name cannot be taken back**. `MapEdit`'s own note predicted
##     every 16.7 path would owe `mark_changed()`, and there are two of them.
##   - **a sentinel that swallows a real answer.** 0 attack and 0 speed are things an author means;
##     0 hp is not. One shared "unset" value would silently discard the first two.
##   - **a key left behind as empty rather than erased.** `MapData.to_dict()` writes `name` only
##     when the record has it, so a cleared field that left `""` would put a hero called nothing
##     into the file — and `_unknown_named_units` would then declare one.
##   - **a condition about somebody the map does not name.** Unwinnable, and its only symptom is
##     that nothing happens.
extends TestCase

const HERO := &"unit.militia"

var doc: MapDocument = null


func before_each() -> void:
	GameDataRegistry.load_from(GameRoot.resolve())
	doc = MapDocument.create(Vector2i(48, 48), "Authoring")
	doc.add_entity(HERO, 1, Vector2i(10, 10))
	doc.selected = 0
	# THE HISTORY STARTS HERE, so every `undo()` below is taking back the act under test rather
	# than the placement that set the fixture up.
	doc.history = UndoStack.new()
	doc.dirty = false


func _record() -> Dictionary:
	return doc.data.entities[0]


# ── naming ──────────────────────────────────────────────────────────────────

func test_a_selected_entity_can_be_named() -> void:
	assert_true(doc.set_selected_name(&"Sir Roland"))
	assert_eq(StringName(_record().get("name", &"")), &"Sir Roland")
	assert_true(doc.dirty)


## ⚠️ **STRIPPED AT BOTH ENDS AND FOLDED NOWHERE**, which is `add_area()`'s rule: a trailing space
## is invisible in a text field and would otherwise be a different person, and lower-casing here
## and not in `ObjectiveSystem` would author a hero the scenario can never find.
func test_a_name_is_stripped_but_not_otherwise_normalised() -> void:
	doc.set_selected_name(&"  Sir Roland  ")
	assert_eq(StringName(_record().get("name", &"")), &"Sir Roland")
	doc.set_selected_name(&"SIR ROLAND")
	assert_eq(StringName(_record().get("name", &"")), &"SIR ROLAND", "case is the author's")


## ⛔ **ERASED AND NOT SET EMPTY.** `MapData.to_dict()` writes the key only when the record has it,
## so a `""` left behind would put `"name": ""` on every entity an author had ever typed into and
## then cleared — and the launch check would read that as a declared hero called nothing.
func test_clearing_a_name_removes_the_key_rather_than_emptying_it() -> void:
	doc.set_selected_name(&"Sir Roland")
	assert_true(doc.set_selected_name(&""))
	assert_false(_record().has("name"), "%s" % [_record()])


## ⛔ **THE ROW'S OWN TRAP, AND `MapEdit`'s NOTE PREDICTED IT.** A name is an in-place edit: same
## entity count, same starts, different fields. Without `mark_changed()` the step is discarded as a
## no-op and Ctrl+Z reaches past it to whatever came before.
func test_a_name_can_be_taken_back() -> void:
	doc.set_selected_name(&"Sir Roland")
	assert_ne(doc.undo(), "", "the step must be on the stack at all")
	assert_false(_record().has("name"), "undo puts the map back: %s" % [_record()])


func test_renaming_to_the_same_name_is_not_a_step() -> void:
	doc.set_selected_name(&"Sir Roland")
	var depth := doc.history.depth()
	# NOT A FAILURE EITHER: re-confirming a field must neither record nothing nor report an error.
	assert_true(doc.set_selected_name(&"Sir Roland"))
	assert_eq(doc.history.depth(), depth, "an unchanged name records nothing")


func test_naming_nothing_is_refused_rather_than_crashing() -> void:
	doc.clear_selection()
	assert_false(doc.set_selected_name(&"Sir Roland"))


# ── the three overrides ─────────────────────────────────────────────────────

func test_an_entity_can_be_given_its_own_health_attack_and_speed() -> void:
	assert_true(doc.set_selected_override("hp", 900))
	assert_true(doc.set_selected_override("attack", 60))
	assert_true(doc.set_selected_override("speed", 7))
	var overrides: Dictionary = _record().get("overrides", {})
	assert_eq(int(overrides.get("hp", 0)), 900)
	assert_eq(int(overrides.get("attack", -1)), 60)
	assert_eq(int(overrides.get("speed", -1)), 7)


## ⛔ **THE SENTINELS ARE PER KEY AND COLLAPSING THEM WOULD LOSE A REAL ANSWER.** 0 attack is a
## unit an author disarmed on purpose and 0 speed is a deployed siege engine; 0 hp is not a thing
## anything alive has, which is why `hp` alone uses it as "unset".
func test_zero_attack_and_zero_speed_are_stored_and_zero_health_is_not() -> void:
	doc.set_selected_override("attack", 0)
	doc.set_selected_override("speed", 0)
	doc.set_selected_override("hp", 0)
	var overrides: Dictionary = _record().get("overrides", {})
	assert_true(overrides.has("attack"), "0 attack means disarmed: %s" % [overrides])
	assert_true(overrides.has("speed"), "0 speed means it does not move: %s" % [overrides])
	assert_false(overrides.has("hp"), "0 hp is the sentinel: %s" % [overrides])


func test_clearing_the_last_override_removes_the_whole_key() -> void:
	doc.set_selected_override("hp", 900)
	assert_true(_record().has("overrides"))
	assert_true(doc.set_selected_override("hp", MapDocument.unset_override("hp")))
	# ⚠️ **WHICH IS WHAT KEEPS A MAP WITH NOTHING AUTHORED BYTE-IDENTICAL** to one written before
	# this row existed, and therefore what keeps `FORMAT_VERSION` at 1.
	assert_false(_record().has("overrides"), "%s" % [_record()])


func test_an_override_can_be_taken_back() -> void:
	doc.set_selected_override("hp", 900)
	assert_ne(doc.undo(), "", "an in-place edit needs mark_changed() to be a step at all")
	assert_false(_record().has("overrides"), "%s" % [_record()])


func test_an_override_key_the_format_does_not_know_is_refused() -> void:
	assert_false(doc.set_selected_override("helth", 900))
	assert_false(_record().has("overrides"))


func test_setting_an_override_to_what_it_already_says_is_not_a_step() -> void:
	doc.set_selected_override("hp", 900)
	var depth := doc.history.depth()
	assert_true(doc.set_selected_override("hp", 900))
	assert_eq(doc.history.depth(), depth)


## The reading the inspector fills its boxes from, and it has to answer for an entity with nothing
## authored — 16.3's rule is that a control is assigned unconditionally, so this is asked every
## time the selection changes.
func test_an_unset_override_reads_back_as_its_own_sentinel() -> void:
	assert_eq(doc.selected_override("hp"), 0)
	assert_eq(doc.selected_override("attack"), -1)
	assert_eq(doc.selected_override("speed"), -1)
	doc.set_selected_override("attack", 60)
	assert_eq(doc.selected_override("attack"), 60)


# ── the names a map declares ────────────────────────────────────────────────

## ⚠️ **SORTED AND DEDUPED.** The entity list is in placement order, so a dropdown built from it
## would reshuffle when an author moved a hero — and two entities may legitimately share a name
## (*"the Twins"*), which is one hero to a condition and two rows to a naive list.
func test_the_names_a_map_declares_are_sorted_and_listed_once() -> void:
	doc.set_selected_name(&"Roland")
	doc.add_entity(HERO, 1, Vector2i(20, 20))
	doc.selected = 1
	doc.set_selected_name(&"Aliénor")
	doc.add_entity(HERO, 1, Vector2i(24, 24))
	doc.selected = 2
	doc.set_selected_name(&"Roland")
	assert_eq(doc.entity_names(), [&"Aliénor", &"Roland"] as Array[StringName])


func test_a_map_that_names_nobody_lists_nobody() -> void:
	assert_true(doc.entity_names().is_empty())


# ── a condition about somebody who is not there ─────────────────────────────

func _add_named_condition(name: String) -> void:
	var problems: Array[String] = []
	assert_true(doc.add_objective({
		"subject": "named_unit", "name": name, "owner": "self",
		"compare": ">=", "value": 1, "output": "win",
	}, problems), "fixture: %s" % [problems])


## ⛔ **THE ONE CHECK ONLY THIS TOOL CAN MAKE EARLY.** `ScenarioDef.build_config()` refuses it at
## LAUNCH, which is the defence that reaches a player; this is the one that reaches the AUTHOR,
## while the map and the conditions are open in front of the same person.
func test_a_condition_about_an_unnamed_hero_is_reported() -> void:
	doc.set_selected_name(&"Sir Roland")
	_add_named_condition("Sir Rolande")
	var problems := doc.unknown_name_problems()
	assert_eq(problems.size(), 1, "%s" % [problems])
	# ⚠️ **IT NAMES WHO THE MAP DOES HAVE**, because the fault is almost always a spelling and the
	# fix is almost always in the other field. `_unknown_areas`' rule.
	assert_true(problems[0].contains("Sir Roland"), problems[0])


func test_a_condition_about_a_hero_who_is_there_is_silent() -> void:
	doc.set_selected_name(&"Sir Roland")
	_add_named_condition("Sir Roland")
	assert_true(doc.unknown_name_problems().is_empty(), "%s" % [doc.unknown_name_problems()])


func test_the_message_says_so_when_the_map_names_nobody_at_all() -> void:
	_add_named_condition("Sir Roland")
	var problems := doc.unknown_name_problems()
	assert_eq(problems.size(), 1)
	# WORDED APART FROM THE OTHER CASE for `_unknown_areas`' reason: "names nobody at all" sends an
	# author to the inspector, and a list of names sends them to their own typo.
	assert_true(problems[0].contains("nobody at all"), problems[0])


## And it reaches the panel's own summary, which is what an author actually reads.
func test_the_warning_reaches_the_condition_lists_problems() -> void:
	_add_named_condition("Nobody")
	var said := " | ".join(PackedStringArray(doc.objective_problems()))
	assert_true(said.contains("Nobody"), said)


# ── the export refuses it, because the game would ───────────────────────────

func test_exporting_a_condition_about_an_unnamed_hero_is_refused() -> void:
	var root := ProjectSettings.globalize_path("user://test_authoring_export")
	DirAccess.make_dir_recursive_absolute(root)
	doc.place_start(1, Vector2i(12, 12))
	doc.place_start(2, Vector2i(34, 34))
	_add_named_condition("Sir Roland")

	var refused := ScenarioExport.new().run(doc, {
		"campaign_folder": "C", "campaign_name": "C", "folder": "scenario_1",
		"name": "S", "opponents": ["passive"], "starting_age": 1,
	}, FormatGuard.check(GameRoot.resolve()), root)
	assert_false(refused.is_empty(), "the game would refuse to launch it")
	assert_true(" | ".join(PackedStringArray(refused)).contains("Sir Roland"), "%s" % [refused])

	# THE SCRATCH DIRECTORY GOES, and only its files: a recursive delete in this repo takes out
	# the files and leaves the folders anyway (every directory is read-only).
	var d := DirAccess.open(root)
	if d != null:
		for f in d.get_files():
			d.remove(f)


# ── the inspector, driven the way a person drives it ────────────────────────

func _editor() -> Node:
	var editor: Node = load("res://Editor.tscn").instantiate()
	editor._ready()
	return editor


## ⚠️ **THE CONTROLS ARE FILLED FROM THE RECORD UNCONDITIONALLY**, 16.3's rule: a box filled only
## when the record HAS the field goes on showing the previous entity's value, and the author then
## reads one hero's 900 hp off a villager.
func test_the_inspector_shows_what_the_selected_entity_carries() -> void:
	var editor := _editor()
	var document := MapDocument.create(Vector2i(48, 48), "Inspected")
	document.add_entity(HERO, 1, Vector2i(10, 10))
	document.add_entity(HERO, 1, Vector2i(20, 20))
	document.selected = 0
	document.set_selected_name(&"Sir Roland")
	document.set_selected_override("hp", 900)
	editor.show_document(document)
	editor._refresh_inspector()
	assert_eq(editor._entity_name.text, "Sir Roland")
	assert_eq(int((editor._entity_overrides["hp"] as SpinBox).value), 900)

	# AND THE ORDINARY ONE BESIDE IT CLEARS THEM, which is the half that would fail silently.
	document.selected = 1
	editor._refresh_inspector()
	assert_eq(editor._entity_name.text, "", "the last hero's name must not linger")
	assert_eq(int((editor._entity_overrides["hp"] as SpinBox).value), 0)
	editor.free()


func test_the_inspector_row_is_dead_with_nothing_selected() -> void:
	var editor := _editor()
	var document := MapDocument.create(Vector2i(48, 48), "Empty")
	editor.show_document(document)
	editor._refresh_inspector()
	assert_false(editor._entity_name.editable)
	assert_false((editor._entity_overrides["attack"] as SpinBox).editable)
	editor.free()


## ⚠️ **SPEED IS FOR UNITS**, which is what `MapGen._apply_authoring` does with it — a castle's
## speed means nothing. Disabled rather than hidden, so the row does not move as the selection
## changes.
func test_the_speed_box_is_dead_for_a_building() -> void:
	var editor := _editor()
	var document := MapDocument.create(Vector2i(48, 48), "Mixed")
	document.add_entity(&"building.house", 1, Vector2i(10, 10))
	document.selected = 0
	editor.show_document(document)
	editor._refresh_inspector()
	assert_false((editor._entity_overrides["speed"] as SpinBox).editable)
	assert_true((editor._entity_overrides["hp"] as SpinBox).editable,
			"a building can still be given health -- 'hold the Keep'")
	editor.free()


## Typing a name and leaving the field is what commits it, and it reaches the document.
func test_committing_the_name_field_writes_it_to_the_map() -> void:
	var editor := _editor()
	var document := MapDocument.create(Vector2i(48, 48), "Typed")
	document.add_entity(HERO, 1, Vector2i(10, 10))
	document.selected = 0
	editor.show_document(document)
	editor._refresh_inspector()
	editor._entity_name.text = "Sir Roland"
	editor._commit_entity_name()
	assert_eq(StringName(document.data.entities[0].get("name", &"")), &"Sir Roland")
	editor.free()
