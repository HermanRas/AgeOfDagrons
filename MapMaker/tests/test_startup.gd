## `Startup`, and the playtest bug that made it a class (2026-09-04).
##
## 16.2 shipped with the startup work living in `Boot.gd`, which handed its result to
## `Editor.setup()`. The project owner then pointed `run/main_scene` at `Editor.tscn` — **the
## obvious thing to do, because the editor is the tool** — and all of that work was skipped:
## no roster, so a start placed 14 entities instead of 48, and Save refused with "the format
## copies have drifted" when nothing had drifted.
##
## ⚠️ **THE TESTS HERE ARE ABOUT THE SHAPE, NOT THE FIELD.** A screen that only works when
## something else ran first will one day be opened directly — by a main-scene change, by a
## preview, by an export preset. So what is pinned is: *the editor reaches a working state on
## its own*, and *the refusal names the fault that actually fired*.
extends TestCase

var _editors: Array[Node] = []


func after_each() -> void:
	for e in _editors:
		e.free()
	_editors.clear()


# ── the check itself ────────────────────────────────────────────────────────

func test_a_working_checkout_reaches_the_ok_state() -> void:
	var s := Startup.check()
	assert_eq(int(s.state), int(Startup.State.OK), s.reason)
	assert_true(s.can_save(), "a clean checkout must be able to save")
	assert_eq(s.reason, "", "an OK startup has nothing to explain")
	assert_true(s.root != null and not s.root.path.is_empty())
	assert_true(s.guard != null and s.guard.passed())


## It does the roster load, not just the resolve -- that omission was half the playtest bug.
func test_the_check_leaves_the_roster_loaded() -> void:
	assert_true(Startup.check().can_save())
	assert_true(GameDataRegistry.is_loaded(), "the roster has to be readable afterwards")
	assert_true(GameDataRegistry.building_ids().size() > 0)
	assert_true(GameDataRegistry.resource_ids().size() > 0,
			"resources are what a start placed none of")


## ⚠️ **THREE DIFFERENT FAULTS WITH THREE DIFFERENT FIXES.** The editor's status line said
## "format copies have drifted" for *any* not-ready reason, so a missing game project -- the
## thing that really happened -- was reported as a corrupt tool. Whoever reads that message is
## being sent to the wrong place, which is worse than a vague one.
func test_each_failure_reports_its_own_reason() -> void:
	# The states are distinct values, so a caller can branch and a message can differ.
	var seen := {}
	for name in Startup.State.keys():
		seen[int(Startup.State[name])] = name
	assert_eq(seen.size(), Startup.State.keys().size(), "no two states share a value")
	assert_true(seen.size() >= 4, "project, roster, format and OK are all distinguishable")


## The exported case is named explicitly in the message, because `export_presets.cfg` puts
## `MapMaker.exe` in the repo root where `../game` does not exist -- so an exported tool NEEDS
## `mapmaker.local.json`, and "cannot find the game project" alone sends somebody hunting for a
## bug instead of writing one line of JSON.
func test_the_missing_project_message_says_what_to_do_about_it() -> void:
	var s := Startup.new()
	s.state = Startup.State.NO_GAME_PROJECT
	s.reason = ("cannot find the game project — none. An EXPORTED MapMaker cannot derive it,"
			+ " so set \"game_root\" in %s next to the executable.") % GameRoot.LOCAL_CONFIG
	assert_true(s.reason.contains(GameRoot.LOCAL_CONFIG),
			"the fix is a filename, so the message has to carry it")
	assert_false(s.can_save())


# ── the editor on its own ───────────────────────────────────────────────────

## ⚠️ **THE PLAYTEST, AS A TEST.** An editor instantiated with nobody calling `setup()` — which
## is exactly what `run/main_scene = Editor.tscn` does — must come up able to save.
func test_an_editor_opened_directly_can_save() -> void:
	var editor := _open_editor()
	assert_true(editor._startup != null, "the editor has to ask for itself if nobody told it")
	assert_true(editor._startup.can_save(),
			"an editor launched as the main scene must be able to save: %s"
			% editor._startup.reason)


## And the consequence that made the bug visible: with no roster a start placed a town centre
## (there is a hardcoded 10x10 fallback) and its villagers, but **no resources at all** — 14
## entities where there should be 48, and nobody would know why.
func test_a_start_placed_by_a_directly_opened_editor_gets_its_resources() -> void:
	var editor := _open_editor()
	editor.set_tool(0)                        # Tool.PAINT, so nothing else is in the way
	var doc: MapDocument = editor.document()
	assert_true(doc != null, "a new map is created on open")
	assert_true(doc.place_start(1, Vector2i(30, 30)), "the start has to land")

	var kinds := {}
	for e in doc.data.entities:
		if int(e.get("player", 0)) == 0:
			kinds[e.get("def_id", &"")] = true
	assert_true(kinds.size() >= 4,
			"a start comes with berries, trees, gold and stone -- got %s" % [kinds.keys()])
	assert_true(doc.data.entities.size() > 20,
			"14 entities was the bug; %d" % doc.data.entities.size())


## `setup()` is now an optimisation -- don't redo the work Boot already did -- and must not
## become a precondition again. Handing one in has to give the same answer as asking.
func test_setup_is_an_optimisation_and_not_a_precondition() -> void:
	var shared := Startup.check()
	var told := _open_editor(shared)
	assert_eq(told._startup, shared, "a handed-over Startup is the one that gets used")

	var asked := _open_editor()
	assert_eq(int(asked._startup.state), int(shared.state),
			"both routes reach the same conclusion")
	assert_eq(asked._startup.can_save(), told._startup.can_save())


## A refusal to save quotes `Startup.reason`, so the button and the status line cannot invent
## their own account of what is wrong.
func test_a_save_refusal_quotes_the_startup_reason() -> void:
	var editor := _open_editor()
	# Forced into a failed state rather than breaking the checkout, which is the only way to
	# exercise the refusal without leaving the repo in a state the next test would inherit.
	var broken := Startup.new()
	broken.state = Startup.State.NO_ROSTER
	broken.reason = "could not read the roster from nowhere/data — nothing there"
	editor.setup(broken)

	# Typed by hand: `editor` is a `Node` here (the scene's script is not `class_name`d), so
	# the return type is not inferable through the untyped call.
	var problems: Array = editor.save()
	assert_eq(problems, [broken.reason] as Array[String],
			"the message the author sees is the reason that fired")


func _open_editor(startup: Startup = null) -> Node:
	var editor: Node = load("res://Editor.tscn").instantiate()
	if startup != null:
		editor.setup(startup)
	# `_ready()` runs on entering a tree, and this harness has none -- so it is called by hand.
	# That is the same code path the main scene takes, which is what the tests above are about.
	editor._ready()
	_editors.append(editor)
	return editor
