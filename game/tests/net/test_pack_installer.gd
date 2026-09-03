## Phase 0.3: verifying a pack and putting it on disk. Everything after the download.
##
## ## THE DOWNLOAD IS NOT TESTED HERE AND CANNOT BE
##
## `install()` needs a URL, and a test that needs the internet fails on a train. So these
## drive `install_from_file()`, which is the same pipeline with the fetch left out --
## `PackInstaller`'s header argues for that seam existing. What proves the network half is
## `dev_preview/preview_content_browser.tscn`, which pulls the really-published pack off the
## really-running server and exits non-zero if it cannot.
##
## Stated plainly because it is a real gap and not a covered one: **nothing below would
## notice if the server started serving `.zip` as `text/html`.** That is the preview's job.
##
## ## ⚠️ THE INSTALL ROOT IS NOT CONFIGURABLE, SO THE FOLDER NAME IS THE ONLY GUARD
##
## `PackDef.install_root()` is hardcoded to `user://content/scenarios/`, deliberately -- a
## pack does not get to choose where it lands. That leaves these tests writing into the same
## directory a developer's installed content lives in, so every fixture here uses a folder
## name **no real campaign will ever have** and deletes it before and after every test.
##
## Getting this wrong would not fail here; it would fail in `test_campaigns`, whose *"the
## real campaign has no problems at all"* would suddenly be looking at a leftover fixture.
extends TestCase

## Long, ugly and unmistakable. It must never collide with authored content, and it must be
## obvious what left it behind if a crash ever does strand one.
const FOLDER := "ZZ_test_pack_installer_fixture"
const TARGET := "user://content/scenarios/ZZ_test_pack_installer_fixture"

const WORK := "user://test_pack_installer"

var _installer: PackInstaller


func before_each() -> void:
	_installer = PackInstaller.new()
	_scrub()
	DirAccess.make_dir_recursive_absolute(WORK)


func after_each() -> void:
	_scrub()
	if _installer != null:
		_installer.free()
		_installer = null


func _scrub() -> void:
	for dir in [TARGET, TARGET + PackInstaller.STAGING_SUFFIX, WORK]:
		if DirAccess.dir_exists_absolute(dir):
			PackInstaller._remove_tree(dir)


func _index() -> String:
	return WORK.path_join("installed.json")


## The single message `pack_finished` reported, or a marker saying it never fired.
##
## Naming the empty case matters: "(nothing was emitted)" and an emitted-but-wrong message
## are different bugs, and a bare `""` reads as the second when it is usually the first.
func _only(said: Array[String]) -> String:
	if said.is_empty():
		return "(pack_finished never fired)"
	return said[0]


# ── fixtures ────────────────────────────────────────────────────────────────

## Build a zip at `path` from `{entry_name: text}`. `ZIPPacker` writes real archives, which
## is what makes the path-traversal test meaningful -- a hand-rolled fake would only prove
## the check against names this file chose to invent.
func _write_zip(path: String, members: Dictionary) -> void:
	var packer := ZIPPacker.new()
	assert_eq(packer.open(path), OK, "the fixture zip must open for writing")
	for name in members:
		packer.start_file(name)
		packer.write_file(str(members[name]).to_utf8_buffer())
		packer.close_file()
	packer.close()


## A valid campaign zip: `campaign.json` at the root, which is what `PackInstaller` insists
## on finding, plus one nested file so the directory-creating path is exercised.
func _write_campaign_zip(path: String) -> void:
	_write_zip(path, {
		"campaign.json": JSON.stringify({
			"name": "Fixture", "description": "A test campaign.",
			"scenarios": ["scenario_1"]}),
		"scenario_1/scenario.json": JSON.stringify({"name": "One"}),
	})


## A `PackDef` whose declared size and hash MATCH the file at `path`. Built from the real
## figures rather than from constants, so the fixture cannot drift from the file.
func _pack_for(path: String, overrides: Dictionary = {}) -> PackDef:
	var f := FileAccess.open(path, FileAccess.READ)
	var size := int(f.get_length())
	f.close()
	var raw := {
		"id": "fixture",
		"kind": "campaign",
		"folder": FOLDER,
		"version": 1,
		"size": size,
		"sha256": FileAccess.get_sha256(path),
		"urls": ["https://example.invalid/fixture.zip"],
	}
	for k in overrides:
		raw[k] = overrides[k]
	return PackDef.from_dict(raw)


# ── the happy path, so the refusals below mean something ─────────────────────

func test_a_good_zip_installs_and_is_recorded() -> void:
	var zip := WORK.path_join("good.zip")
	_write_campaign_zip(zip)
	var pack := _pack_for(zip)

	assert_true(_installer.install_from_file(pack, zip, _index()))
	assert_true(DirAccess.dir_exists_absolute(TARGET))
	assert_true(FileAccess.file_exists(TARGET.path_join("campaign.json")))
	assert_true(FileAccess.file_exists(TARGET.path_join("scenario_1/scenario.json")),
			"a nested entry created its parent directory")
	assert_eq(PackIndex.version_of(pack.id, _index()), 1)


## The file a caller handed us is theirs. Only a download's scratch copy is consumed.
func test_a_caller_s_file_is_left_where_it_was() -> void:
	var zip := WORK.path_join("keep.zip")
	_write_campaign_zip(zip)
	var pack := _pack_for(zip)

	assert_true(_installer.install_from_file(pack, zip, _index()))
	assert_true(FileAccess.file_exists(zip), "install_from_file must not eat its input")


# ── ⚠️ THE SECURITY TEST ─────────────────────────────────────────────────────

## A zip entry naming `..` escapes the install root entirely. `PackDef` whitelists the
## FOLDER name, which says nothing about what is inside the archive.
##
## **Refused whole, not skipped per-entry**: an archive containing one hostile path is not
## an archive to trust the rest of.
func test_a_zip_containing_a_traversal_path_is_refused_whole() -> void:
	for evil in ["../escaped.txt", "a/../../escaped.txt", "/absolute.txt",
			"..\\windows.txt", "./sneaky.txt"]:
		_scrub()
		DirAccess.make_dir_recursive_absolute(WORK)
		var zip := WORK.path_join("evil.zip")
		_write_zip(zip, {
			"campaign.json": "{}",
			evil: "owned",
		})
		var pack := _pack_for(zip)

		assert_false(_installer.install_from_file(pack, zip, _index()),
				"entry '%s' must be refused" % evil)
		# NOTHING is written -- not even the good member that shared the archive.
		assert_false(DirAccess.dir_exists_absolute(TARGET),
				"entry '%s' must leave nothing behind" % evil)
		assert_false(PackIndex.is_installed(pack.id, _index()),
				"entry '%s' must not be recorded" % evil)


# ── the verify steps, in the order they run ──────────────────────────────────

## Size first, so a truncated download says so. The wrong message here sends somebody
## hunting corruption or tampering when the answer is "the connection dropped".
func test_a_size_that_does_not_match_is_refused_and_names_the_length() -> void:
	var zip := WORK.path_join("short.zip")
	_write_campaign_zip(zip)
	var pack := _pack_for(zip, {"size": 999999})

	# AN ARRAY, NOT A LOCAL STRING. GDScript lambdas capture locals BY VALUE, so
	# `message = m` inside one assigns to the closure's own copy and the test sees "" --
	# which cost three green-looking failures the first time this file ran. An Array is a
	# reference, so appending to it is visible out here.
	var said: Array[String] = []
	_installer.pack_finished.connect(func(_p: PackDef, _ok: bool, m: String) -> void:
		said.append(m))

	assert_false(_installer.install_from_file(pack, zip, _index()))
	assert_true(_only(said).contains("bytes"), "the complaint is about length: %s" % _only(said))
	assert_false(DirAccess.dir_exists_absolute(TARGET))


func test_a_checksum_that_does_not_match_is_refused() -> void:
	var zip := WORK.path_join("tampered.zip")
	_write_campaign_zip(zip)
	var pack := _pack_for(zip, {
		"sha256": "0000000000000000000000000000000000000000000000000000000000000000"})

	# AN ARRAY, NOT A LOCAL STRING. GDScript lambdas capture locals BY VALUE, so
	# `message = m` inside one assigns to the closure's own copy and the test sees "" --
	# which cost three green-looking failures the first time this file ran. An Array is a
	# reference, so appending to it is visible out here.
	var said: Array[String] = []
	_installer.pack_finished.connect(func(_p: PackDef, _ok: bool, m: String) -> void:
		said.append(m))

	assert_false(_installer.install_from_file(pack, zip, _index()))
	assert_true(_only(said).contains("checksum"), "the complaint names the checksum: %s" % _only(said))
	assert_false(DirAccess.dir_exists_absolute(TARGET))
	assert_false(PackIndex.is_installed(pack.id, _index()))


func test_a_file_that_is_not_a_zip_is_refused() -> void:
	var path := WORK.path_join("not_a_zip.bin")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("this is not a zip archive")
	f.close()
	var pack := _pack_for(path)

	assert_false(_installer.install_from_file(pack, path, _index()))
	assert_false(DirAccess.dir_exists_absolute(TARGET))


func test_an_empty_zip_is_refused() -> void:
	var zip := WORK.path_join("empty.zip")
	_write_zip(zip, {})
	var pack := _pack_for(zip)
	assert_false(_installer.install_from_file(pack, zip, _index()))


## A zip that unpacks cleanly but is not a campaign would install a directory that
## `Campaigns` then reports as broken -- which blames the loader for a publishing mistake.
func test_a_campaign_zip_with_no_campaign_json_is_refused() -> void:
	var zip := WORK.path_join("nomarker.zip")
	_write_zip(zip, {"readme.txt": "no campaign here"})
	var pack := _pack_for(zip)

	# AN ARRAY, NOT A LOCAL STRING. GDScript lambdas capture locals BY VALUE, so
	# `message = m` inside one assigns to the closure's own copy and the test sees "" --
	# which cost three green-looking failures the first time this file ran. An Array is a
	# reference, so appending to it is visible out here.
	var said: Array[String] = []
	_installer.pack_finished.connect(func(_p: PackDef, _ok: bool, m: String) -> void:
		said.append(m))

	assert_false(_installer.install_from_file(pack, zip, _index()))
	assert_true(_only(said).contains(CampaignDef.JSON_FILE), "says what was missing: %s" % _only(said))
	assert_false(DirAccess.dir_exists_absolute(TARGET), "and the staging copy is gone")


func test_an_unusable_manifest_entry_never_reaches_the_disk() -> void:
	var zip := WORK.path_join("good.zip")
	_write_campaign_zip(zip)
	var pack := _pack_for(zip, {"folder": "../escape"})

	assert_false(pack.is_usable(), "the fixture is the refusal we want")
	assert_false(_installer.install_from_file(pack, zip, _index()))


func test_a_missing_file_is_refused_rather_than_crashing() -> void:
	var zip := WORK.path_join("good.zip")
	_write_campaign_zip(zip)
	var pack := _pack_for(zip)

	assert_false(_installer.install_from_file(pack, WORK.path_join("gone.zip"), _index()))


# ── ⚠️ THE SWAP: A FAILED UPDATE MUST NOT DESTROY WHAT WAS WORKING ───────────

## The reason `_unpack` stages and then renames. A player with a working campaign who takes
## a corrupt update must still have the working campaign.
func test_a_failed_update_leaves_the_previous_copy_intact() -> void:
	var zip := WORK.path_join("v1.zip")
	_write_campaign_zip(zip)
	var v1 := _pack_for(zip)
	assert_true(_installer.install_from_file(v1, zip, _index()))
	assert_true(FileAccess.file_exists(TARGET.path_join("campaign.json")))

	# v2 arrives corrupt: the bytes are fine but the manifest's hash is not.
	var v2 := _pack_for(zip, {
		"version": 2,
		"sha256": "1111111111111111111111111111111111111111111111111111111111111111"})
	assert_false(_installer.install_from_file(v2, zip, _index()))

	assert_true(FileAccess.file_exists(TARGET.path_join("campaign.json")),
			"the working copy survives a rejected update")
	assert_eq(PackIndex.version_of(v1.id, _index()), 1, "and is still recorded at v1")


func test_a_reinstall_replaces_rather_than_merges() -> void:
	var first := WORK.path_join("first.zip")
	_write_zip(first, {
		"campaign.json": "{}",
		"scenario_9/scenario.json": "{}",
	})
	assert_true(_installer.install_from_file(_pack_for(first), first, _index()))
	assert_true(FileAccess.file_exists(TARGET.path_join("scenario_9/scenario.json")))

	var second := WORK.path_join("second.zip")
	_write_campaign_zip(second)
	assert_true(_installer.install_from_file(_pack_for(second, {"version": 2}), second, _index()))

	# A merge would leave scenario_9 behind, and `campaign.json`'s order list would then
	# report a folder it does not name -- a phantom the player could not explain.
	assert_false(FileAccess.file_exists(TARGET.path_join("scenario_9/scenario.json")),
			"the old content is gone, not merged")
	assert_true(FileAccess.file_exists(TARGET.path_join("scenario_1/scenario.json")))


func test_a_stale_staging_directory_from_a_crash_does_not_block_an_install() -> void:
	var staging := TARGET + PackInstaller.STAGING_SUFFIX
	DirAccess.make_dir_recursive_absolute(staging)
	var f := FileAccess.open(staging.path_join("leftover.txt"), FileAccess.WRITE)
	f.store_string("from a crash")
	f.close()

	var zip := WORK.path_join("good.zip")
	_write_campaign_zip(zip)
	assert_true(_installer.install_from_file(_pack_for(zip), zip, _index()))
	assert_false(DirAccess.dir_exists_absolute(staging), "the staging directory is consumed")
	assert_false(FileAccess.file_exists(TARGET.path_join("leftover.txt")))


# ── uninstall ────────────────────────────────────────────────────────────────

func test_uninstall_removes_the_content_and_forgets_it() -> void:
	var zip := WORK.path_join("good.zip")
	_write_campaign_zip(zip)
	var pack := _pack_for(zip)
	assert_true(_installer.install_from_file(pack, zip, _index()))

	assert_true(_installer.uninstall(pack, _index()))
	assert_false(DirAccess.dir_exists_absolute(TARGET))
	assert_false(PackIndex.is_installed(pack.id, _index()))
	# PLAN.md 3.3 wants content removable AND re-installable.
	assert_true(PackIndex.needs_download(pack, _index()))


func test_uninstalling_something_that_is_not_there_is_not_a_crash() -> void:
	var zip := WORK.path_join("good.zip")
	_write_campaign_zip(zip)
	assert_true(_installer.uninstall(_pack_for(zip), _index()))


## Godot has no `unload_resource_pack()`, so removing art would need a restart to take
## effect -- and a button that silently requires one is worse than no button.
func test_a_mounted_pack_refuses_to_be_uninstalled() -> void:
	var art := PackDef.from_dict({
		"id": "art", "kind": "art", "version": 1, "size": 10,
		"sha256": "2222222222222222222222222222222222222222222222222222222222222222",
		"urls": ["https://example.invalid/art.pck"],
	})
	assert_true(art.is_usable(), "problems: %s" % ", ".join(art.problems))
	assert_false(_installer.uninstall(art, _index()))


# ── the entry-name check, directly ───────────────────────────────────────────

## The shapes that escape, and the ones that legitimately do not. A campaign's filenames may
## contain spaces and dots; what they may not do is climb.
func test_the_entry_name_check_refuses_what_climbs_and_allows_what_does_not() -> void:
	for bad in ["../x", "a/../../x", "/x", "a\\b", "C:/x", "..", ".", "a/./b", ""]:
		assert_false(PackInstaller._is_safe_entry(bad), "'%s' must be refused" % bad)
	for good in ["campaign.json", "scenario_1/map.png", "a b/c d.png",
			"CampaignBackground.png", "deep/a/b/c/d.json"]:
		assert_true(PackInstaller._is_safe_entry(good), "'%s' must be allowed" % good)
