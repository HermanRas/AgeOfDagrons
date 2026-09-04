## PLAN.md §16 decision 3: the format copies check themselves.
##
## **THIS IS THE MOST IMPORTANT FILE IN THE TOOL'S SUITE**, because the guard is the only
## thing standing between a stale copy and a map file the game refuses to load — and a guard
## that silently passes is indistinguishable from one that works. So the tests here do not
## merely assert that the real copies match: they **build a fake game project, drift a file
## on purpose, and assert the guard notices.** A check verified only against the happy path
## is the facing bug (§12A) waiting to happen: that one passed twice while the bug was there.
extends TestCase

const SCRATCH := "user://test_format_guard"

var _n := 0


func before_each() -> void:
	_n += 1


func _dir() -> String:
	return "%s/case_%d" % [SCRATCH, _n]


## A directory that looks enough like the game project for `GameRoot` to accept it, with
## every file `FormatGuard` reads present and identical to this project's copies.
func _fake_game(overrides: Dictionary = {}) -> GameRoot:
	var dir := _dir()
	for marker in GameRoot.MARKERS:
		_write(dir.path_join(marker), "placeholder")
	# The originals, taken FROM OUR OWN COPIES so a fresh fake starts in the passing state
	# and each test drifts exactly one thing. Copying the real game's files instead would
	# make these tests fail the day the game changes, which is the guard's job and not
	# theirs.
	for entry in FormatGuard.COPIES:
		var origin := str(entry["origin"])
		var text: String = overrides.get(origin,
				FileAccess.get_file_as_string(str(entry["copy"])))
		_write(dir.path_join(origin), text)
	for entry in FormatGuard.DECLARATIONS:
		var origin := str(entry["origin"])
		var text: String = overrides.get(origin,
				"extends RefCounted\n\n%s\n" % entry["expected"])
		_write(dir.path_join(origin), text)

	var root := GameRoot.new()
	root.path = ProjectSettings.globalize_path(dir)
	return root


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(f, "could not write %s" % path)
	if f == null:
		return
	f.store_string(text)
	f.close()


# ── against the REAL game project ───────────────────────────────────────────

## The one that matters on any given day: are the committed copies current?
##
## **A FAILURE HERE IS NOT A BROKEN TEST.** It means the game's format has moved and this
## tool's `format/` has not, which is precisely what decision 3 exists to announce — the fix
## is to re-copy the named file, not to touch this assertion.
func test_the_committed_copies_match_the_real_game() -> void:
	var root := GameRoot.resolve()
	assert_false(root.path.is_empty(),
			"the game project should be a sibling: " + "; ".join(PackedStringArray(root.problems)))
	if root.path.is_empty():
		return
	var guard := FormatGuard.check(root)
	assert_true(guard.passed(), "format copies have drifted:\n" + guard.report())
	assert_eq(guard.refusal(), "", "a passing guard refuses nothing")


## Every file the guard names must actually be checked -- a table row that silently matched
## nothing would be a file nobody is guarding.
func test_every_copy_and_declaration_produces_a_result() -> void:
	var guard := FormatGuard.check(_fake_game())
	assert_eq(guard.results.size(), FormatGuard.COPIES.size() + FormatGuard.DECLARATIONS.size())
	assert_true(guard.passed(), guard.report())


## `map_file.gd` was MISSING from decision 2's original list, and it is the actual save/load
## code. Pinned by name so it cannot quietly fall out of the table again.
func test_the_save_load_code_is_one_of_the_guarded_files() -> void:
	var origins: Array[String] = []
	for entry in FormatGuard.COPIES:
		origins.append(str(entry["origin"]))
	assert_true(origins.has("src/data/map_file.gd"),
			"map_file.gd decides what is written to disk and must be guarded")
	assert_true(origins.has("src/sim/map_data.gd"))
	assert_true(origins.has("src/sim/sim_map.gd"),
			"the Terrain enum is the byte written into map.png")


# ── drift is DETECTED, which is the whole point ─────────────────────────────

## One changed line in one original, and the guard must refuse.
func test_a_changed_original_is_caught_and_named() -> void:
	var text := FileAccess.get_file_as_string("res://format/map_data.gd")
	var guard := FormatGuard.check(_fake_game({
		"src/sim/map_data.gd": text + "\n\nfunc something_new() -> void:\n\tpass\n",
	}))
	assert_false(guard.passed(), "an appended function must count as drift")
	assert_true(guard.refusal().contains("map_data.gd"),
			"the refusal names the file: " + guard.refusal())
	# The refusal has to say what to DO, or it is an error message that stops somebody
	# without helping them.
	assert_true(guard.refusal().contains("Copy each file"))


## A file that has gone entirely, which is a different fault from one that changed and wants
## a different message.
func test_a_missing_original_is_caught() -> void:
	var root := _fake_game()
	DirAccess.remove_absolute(root.path.path_join("src/view/iso.gd"))
	var guard := FormatGuard.check(root)
	assert_false(guard.passed())
	assert_true(guard.refusal().contains("iso.gd"))


## ⚠️ **THE CHECK MUST SURVIVE A LINE-ENDING CHANGE.** This repo checks out with CRLF on
## Windows while these files are written with LF, so a byte-for-byte hash would fail on every
## file on every machine -- and **a check that cries wolf is a check somebody disables**,
## which leaves the format unguarded. That is a worse outcome than the drift itself, so this
## is asserted rather than assumed.
func test_crlf_line_endings_are_not_drift() -> void:
	var text := FileAccess.get_file_as_string("res://format/map_file.gd")
	var guard := FormatGuard.check(_fake_game({
		"src/data/map_file.gd": text.replace("\n", "\r\n"),
	}))
	assert_true(guard.passed(), "CRLF must not read as a changed file:\n" + guard.report())


## And a trailing newline must not either, for the same reason: editors add and remove them
## without anybody deciding to.
func test_a_trailing_newline_is_not_drift() -> void:
	var text := FileAccess.get_file_as_string("res://format/sim_map.gd")
	var guard := FormatGuard.check(_fake_game({
		"src/sim/sim_map.gd": text.rstrip("\n") + "\n\n\n",
	}))
	assert_true(guard.passed(), guard.report())


## ...but a change INSIDE the code still is. The pair of tests above could be satisfied by a
## guard that compares nothing at all, so this is the one that gives them meaning.
func test_a_whitespace_tolerant_guard_still_catches_a_real_change() -> void:
	var text := FileAccess.get_file_as_string("res://format/sim_map.gd")
	var guard := FormatGuard.check(_fake_game({
		"src/sim/sim_map.gd": text.replace(
				"enum Terrain { GRASS, DIRT, SAND, WATER_SHALLOW, WATER_DEEP, ROCK, FOREST }",
				"enum Terrain { GRASS, DIRT, SAND, WATER_SHALLOW, WATER_DEEP, ROCK, FOREST, LAVA }"),
	}))
	assert_false(guard.passed(), "an eighth terrain kind is exactly what must be caught")
	assert_true(guard.refusal().contains("sim_map.gd"))


# ── the declaration check, for what cannot be copied ────────────────────────

## `format/sim_world.gd` stands in for a 1,500-line original, so it is checked by declaration
## rather than by hash. A changed sub-tile resolution must still stop the tool.
func test_a_changed_declaration_is_caught() -> void:
	var guard := FormatGuard.check(_fake_game({
		"src/sim/sim_world.gd": "extends RefCounted\n\nconst SUBTILE := 512\n",
	}))
	assert_false(guard.passed(), "SUBTILE moving must refuse")
	assert_true(guard.refusal().contains("SUBTILE"), guard.refusal())


## A comment beside the declaration is not a change. Nothing would be gained by refusing over
## one, and a tool that did would be turned off.
func test_a_trailing_comment_on_the_declaration_is_not_drift() -> void:
	var guard := FormatGuard.check(_fake_game({
		"src/sim/sim_world.gd":
			"extends RefCounted\n\nconst SUBTILE := 256  # sub-tile units per tile\n",
	}))
	assert_true(guard.passed(), guard.report())


## ⚠️ **A DECLARATION THAT HAS VANISHED IS A FAILURE, NEVER A PASS.** A renamed or moved
## constant is exactly what this check is for, and "I could not find it" must not read as
## "it is fine" -- that is the shape of the facing bug in one line.
func test_a_vanished_declaration_is_a_failure() -> void:
	var guard := FormatGuard.check(_fake_game({
		"src/sim/sim_world.gd": "extends RefCounted\n\nconst SUB_TILE := 256\n",
	}))
	assert_false(guard.passed(), "a renamed constant must not read as absent-and-fine")
	assert_true(guard.refusal().contains("no line starting"), guard.refusal())


## The shim and the check must agree with each other, or the check is testing itself.
func test_the_shim_says_what_the_guard_expects() -> void:
	for entry in FormatGuard.DECLARATIONS:
		if str(entry["prefix"]) == "const SUBTILE":
			assert_eq(str(entry["expected"]), "const SUBTILE := %d" % SimWorld.SUBTILE)
			return
	fail("no SUBTILE declaration in the guard's table")
