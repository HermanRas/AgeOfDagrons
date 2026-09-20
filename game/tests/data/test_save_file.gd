## Phase 12.4: a saved game on disk -- writing one, listing them, reading one back.
##
## What is NOT here is whether the match survives the round trip; that is
## `tests/sim/test_save_game.gd`, and the split is `MapData`/`MapFile`'s. These are about the
## FILES: that a save lands where no installer writes, that a picker can list twenty of them
## without parsing twenty matches, and that the failure modes a player can produce -- a name
## made entirely of punctuation, a half-deleted save, a corrupt sidecar -- cost a row rather
## than the list.
##
## ⚠️ **THESE WRITE INTO THE REAL `user://saves/`**, which is a directory a developer running
## the game will also have saves in. Every fixture is therefore named with a prefix no player
## would type, and every test cleans up after itself -- `test_pack_installer.gd`'s rule, for
## its reason: getting this wrong would not fail here, it would delete somebody's save.
extends TestCase

const PREFIX := "zz-test-save-fixture"

var _world: SimWorld
var _cfg: MatchConfig


func before_each() -> void:
	_scrub()
	_cfg = MatchConfig.debug_generated(7, MapGenerator.Type.FOREST, 2)
	_world = SimWorld.new()
	_world.setup(_cfg)
	MapGen.build(_world, _cfg)
	for i in 5:
		_world.step()


func after_each() -> void:
	_scrub()


## Only this fixture's files, never the directory: `user://saves/` is the player's.
func _scrub() -> void:
	var dir := DirAccess.open(SaveFile.ROOT)
	if dir == null:
		return
	for file in dir.get_files():
		if file.begins_with(PREFIX):
			DirAccess.remove_absolute(
					ProjectSettings.globalize_path(SaveFile.ROOT.path_join(file)))


func _rows() -> Array[Dictionary]:
	var mine: Array[Dictionary] = []
	for row in SaveFile.list():
		if str(row.get("slug", "")).begins_with(PREFIX):
			mine.append(row)
	return mine


# ── writing and reading ─────────────────────────────────────────────────────

func test_a_saved_match_lands_on_disk_and_reads_back() -> void:
	assert_eq(SaveFile.write(_world, _cfg, PREFIX), [] as Array[String])

	var problems: Array[String] = []
	var save := SaveFile.read(PREFIX, problems)
	assert_eq(problems, [] as Array[String])
	assert_false(save.is_empty(), "the body must come back")
	assert_eq(int((save["world"] as Dictionary)["tick"]), _world.tick)


## The other half of the file. A save is rebuilt from its config first and only then
## overwritten, so a file whose config cannot be read is a file that cannot be loaded.
func test_a_save_carries_the_config_its_world_is_rebuilt_from() -> void:
	SaveFile.write(_world, _cfg, PREFIX)
	var problems: Array[String] = []
	var cfg := SaveFile.config_of(SaveFile.read(PREFIX, problems))
	assert_not_null(cfg, "the config must survive the file")
	assert_eq(cfg.player_ids, _cfg.player_ids)
	assert_eq(int(cfg.mode), int(_cfg.mode))


func test_saving_the_same_name_twice_replaces_rather_than_multiplies() -> void:
	SaveFile.write(_world, _cfg, PREFIX)
	for i in 10:
		_world.step()
	SaveFile.write(_world, _cfg, PREFIX)

	assert_eq(_rows().size(), 1, "one slot, saved twice, is one row")
	var problems: Array[String] = []
	var save := SaveFile.read(PREFIX, problems)
	assert_eq(int((save["world"] as Dictionary)["tick"]), _world.tick,
			"and it is the LATER match, not the earlier one")


func test_reading_a_save_that_is_not_there_says_so_rather_than_returning_nothing() -> void:
	var problems: Array[String] = []
	assert_true(SaveFile.read(PREFIX + "-absent", problems).is_empty())
	assert_false(problems.is_empty(), "a missing save must complain, not read as empty")


# ── listing ─────────────────────────────────────────────────────────────────

## The point of the sidecar: a row is drawn from a few hundred bytes and never from the match.
func test_a_row_carries_what_a_picker_draws() -> void:
	SaveFile.write(_world, _cfg, "%s Anne's last stand!" % PREFIX)
	var rows := _rows()
	assert_eq(rows.size(), 1)
	var row := rows[0]
	assert_eq(str(row["name"]), "%s Anne's last stand!" % PREFIX,
			"the player's own words, punctuation and all")
	assert_eq(int(row["tick"]), _world.tick)
	assert_eq((row["players"] as Array).size(), 2)
	assert_true(int(row["saved_at"]) > 0, "and when it was saved")


## A body with no sidecar is invisible, and a sidecar with no body would be a row that cannot
## be played -- so the listing refuses to offer one.
func test_a_row_whose_match_is_gone_is_not_offered() -> void:
	SaveFile.write(_world, _cfg, PREFIX)
	assert_eq(_rows().size(), 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(
			SaveFile.ROOT.path_join(PREFIX + SaveFile.SAVE_SUFFIX)))
	assert_eq(_rows().size(), 0, "a row that cannot be played must not be listed")


## One unreadable sidecar costs its own row and nothing else -- `PackManifest`'s rule that a
## broken entry costs one pack rather than the manifest.
func test_a_corrupt_row_costs_one_row_and_not_the_list() -> void:
	SaveFile.write(_world, _cfg, PREFIX + "-good")
	DirAccess.make_dir_recursive_absolute(SaveFile.ROOT)
	var f := FileAccess.open(
			SaveFile.ROOT.path_join(PREFIX + "-broken" + SaveFile.META_SUFFIX), FileAccess.WRITE)
	f.store_string("{not json at all")
	f.close()

	var rows := _rows()
	assert_eq(rows.size(), 1, "the good save is still listed")
	assert_eq(str(rows[0]["slug"]), PREFIX + "-good")


func test_the_newest_save_is_listed_first() -> void:
	SaveFile.write(_world, _cfg, PREFIX + "-older")
	var older := SaveFile.ROOT.path_join(PREFIX + "-older" + SaveFile.META_SUFFIX)
	# Backdated by hand: two saves written in the same second would otherwise tie, and a tie
	# would make this test pass or fail on how fast the machine is.
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(older))
	(raw as Dictionary)["saved_at"] = 1000
	var f := FileAccess.open(older, FileAccess.WRITE)
	f.store_string(JSON.stringify(raw))
	f.close()

	SaveFile.write(_world, _cfg, PREFIX + "-newer")
	var rows := _rows()
	assert_eq(rows.size(), 2)
	assert_eq(str(rows[0]["slug"]), PREFIX + "-newer", "newest first")


# ── names, and what a player can type ───────────────────────────────────────

## The security check, and it is a whitelist for `PackDef._is_safe_segment()`'s reason: a
## blacklist of `..` and `/` still passes a backslash, a drive letter or an encoded separator,
## and `FileAccess`/`DirAccess` disagree about which of those they normalise.
func test_a_name_cannot_climb_out_of_the_saves_directory() -> void:
	for hostile in ["../../project", "..\\..\\project", "C:/windows/system32",
			"a/../../b", "....//"]:
		var slug := SaveFile.slugify(hostile)
		assert_false(slug.contains("/"), "'%s' -> '%s' must carry no separator" % [hostile, slug])
		assert_false(slug.contains("\\"), "nor a backslash")
		assert_false(slug.contains(".."), "nor a climb")
		assert_false(slug.contains(":"), "nor a drive")


func test_a_name_becomes_a_readable_file_name() -> void:
	assert_eq(SaveFile.slugify("Anne's Last Stand!"), "anne-s-last-stand")
	assert_eq(SaveFile.slugify("  spaced   out  "), "spaced-out")
	assert_eq(SaveFile.slugify("Tuesday 3pm"), "tuesday-3pm")


## A name with nothing usable in it is refused rather than turned into a file called
## something arbitrary -- the player gets told, and no file appears.
func test_a_name_with_no_letters_or_digits_is_refused() -> void:
	var problems := SaveFile.write(_world, _cfg, "!!! ...")
	assert_false(problems.is_empty(), "there is no sensible filename in that")
	assert_true(str(problems[0]).contains("!!!"), "and the complaint quotes what was typed")


func test_erasing_a_save_takes_its_row_with_it() -> void:
	SaveFile.write(_world, _cfg, PREFIX)
	assert_eq(_rows().size(), 1)
	assert_true(SaveFile.erase(PREFIX))
	assert_eq(_rows().size(), 0)
	assert_false(FileAccess.file_exists(SaveFile.ROOT.path_join(PREFIX + SaveFile.SAVE_SUFFIX)),
			"the match goes too, not just the row")
	assert_false(SaveFile.erase(PREFIX), "and erasing what is gone is false, not a crash")

# -- the generated name (12.4, owner's call 2026-09-20: auto-named, no typing) ------------

## THE TICK IS THE PART THAT MAKES IT UNIQUE, and this is the test that says so.
##
## `write()` REPLACES a save of the same name, which is right for a name a player typed and
## is a silent data loss for one nobody did. A name built from the wall clock alone collides
## for every save made inside the same minute -- press Save, change your mind, press Save
## again, and the first file is gone. So the tick is in the name, and two DIFFERENT ticks
## must produce two different names even when the clock has not moved between them.
func test_two_saves_of_one_match_get_different_names() -> void:
	var first := SaveFile.auto_name(_world, _cfg)
	for i in 30:
		_world.step()
	var second := SaveFile.auto_name(_world, _cfg)
	assert_true(first != second,
			"a later tick is a different save -- '%s' vs '%s'" % [first, second])
	assert_true(first.contains(str(5)), "the first carries its own tick")


## It must survive `slugify` with the tick INTACT: the tick is at the end, so a name long
## enough to be cut loses exactly the part that makes it unique. Asserted as a relation
## rather than as a length, so a longer mode name is caught rather than silently truncated.
func test_the_generated_name_is_short_enough_to_keep_its_tick() -> void:
	for mode in [MatchConfig.Mode.LAST_MAN_STANDING, MatchConfig.Mode.TROPHY,
			MatchConfig.Mode.KING_OF_THE_HILL, MatchConfig.Mode.SCENARIO]:
		_cfg.mode = mode
		var slug := SaveFile.slugify(SaveFile.auto_name(_world, _cfg))
		assert_true(slug.length() < SaveFile.MAX_NAME,
				"%s slugs to %d chars, at the %d limit" % [
					MatchConfig.mode_name(mode), slug.length(), SaveFile.MAX_NAME])
		assert_true(slug.ends_with("-5"), "and the tick survives: %s" % slug)


## The name says which match it was, so a picker row is readable without opening anything.
func test_the_generated_name_says_what_the_match_was() -> void:
	_cfg.mode = MatchConfig.Mode.KING_OF_THE_HILL
	assert_true(SaveFile.auto_name(_world, _cfg).begins_with("King of the Hill"))


## A save made with no world and no config is still NAMEABLE rather than a crash. Reached by
## nothing today; written because `auto_name` reads two things a caller can hand it null.
func test_a_nameless_match_still_produces_a_name() -> void:
	assert_false(SaveFile.auto_name(null, null).is_empty())