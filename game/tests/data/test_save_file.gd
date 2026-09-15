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
