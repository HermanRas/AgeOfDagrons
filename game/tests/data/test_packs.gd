## Phase 0.3: the manifest, its entries, and the local record of what is installed.
##
## ## WHAT IS WORTH TESTING HERE, AND IT IS NOT THE HAPPY PATH
##
## Parsing a well-formed `packs.json` is four lines and `preview_content_browser` already
## proves it against the real server. The value is in everything this data is NOT allowed to
## do, because **it arrives over HTTP and then decides where bytes land on disk**:
##
##   - an `id` or `folder` that is not a plain name must be refused in the PARSE, long
##     before the installer sees it. `../../../project.godot` is the case that matters.
##   - a bad entry must cost ONE PACK and not the manifest. `CampaignDef` learned this the
##     hard way when a work-in-progress folder made a whole campaign unplayable.
##   - a future `format_version` must be refused rather than guessed, because guessing
##     fails SILENTLY: the client would offer packs whose meaning it had misread.
##
## ## ⚠️ NOTHING HERE TOUCHES `PackIndex.USER_FILE`
##
## `test_campaign_progress`'s first rule, for its reason: that file is real state on whoever
## runs the suite, so a test that wrote it would rewrite the developer's own installed
## versions, and one that read it would pass on a fresh checkout and fail on a machine that
## has downloaded anything. `USER_FILE` appears once below -- in the test asserting the
## default argument still points at it.
extends TestCase

const DIR := "user://test_packs"
const PATH := "user://test_packs/installed.json"


func before_each() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


## A complete, valid entry. Tests below copy it and break ONE field, so a failure names the
## field rather than "the fixture is wrong".
func _entry(overrides: Dictionary = {}) -> Dictionary:
	var base := {
		"id": "howtoplay",
		"kind": "campaign",
		"folder": "HowToPlay",
		"version": 2,
		"required": true,
		"title": "How To Play",
		"author": "Age of Dragons",
		"description": "Five short lessons.",
		"size": 2224376,
		"sha256": "b1885a72cf08850da32304d5c2dfa7f35400217e2f40f233f5917290a81008bd",
		"urls": ["https://aod.dragoon.co.za/downloads/campaign_howtoplay_v2.zip"],
	}
	for k in overrides:
		base[k] = overrides[k]
	return base


func _manifest_text(entries: Array, format_version: int = 1) -> String:
	return JSON.stringify({
		"format_version": format_version,
		"generated": "2026-09-03T00:00:00Z",
		"packs": entries,
	})


# ── PackDef: the fields that decide where bytes go ───────────────────────────

func test_a_complete_entry_parses_every_field() -> void:
	var p := PackDef.from_dict(_entry())
	assert_true(p.is_usable(), "problems: %s" % ", ".join(p.problems))
	assert_eq(p.id, "howtoplay")
	assert_eq(p.kind, PackDef.Kind.CAMPAIGN)
	assert_eq(p.folder, "HowToPlay")
	assert_eq(p.version, 2)
	assert_true(p.required)
	assert_eq(p.size, 2224376)
	assert_eq(p.urls.size(), 1)


## THE SECURITY TEST. Each of these would name a path outside the install root.
func test_an_id_that_is_not_a_plain_name_is_refused() -> void:
	for bad in ["../evil", "..", "a/b", "a\\b", "C:", ".hidden", "", "a b", "a:b"]:
		var p := PackDef.from_dict(_entry({"id": bad}))
		assert_false(p.is_usable(), "id '%s' should be refused" % bad)


func test_a_folder_that_escapes_the_install_root_is_refused() -> void:
	for bad in ["../../../project.godot", "..", "a/b", ".hidden", "with space"]:
		var p := PackDef.from_dict(_entry({"folder": bad}))
		assert_false(p.is_usable(), "folder '%s' should be refused" % bad)


func test_a_campaign_with_no_folder_has_nowhere_to_install_and_is_refused() -> void:
	var p := PackDef.from_dict(_entry({"folder": ""}))
	assert_false(p.is_usable())


## The mirror of the rule above: a mounted pack has no directory, so declaring one means
## whoever wrote the manifest believes it unpacks somewhere and it does not.
func test_a_mounted_pack_carrying_a_folder_is_refused() -> void:
	var p := PackDef.from_dict(_entry({"kind": "art", "folder": "Art"}))
	assert_false(p.is_usable())

	var ok := PackDef.from_dict(_entry({"kind": "art", "folder": ""}))
	assert_true(ok.is_usable(), "problems: %s" % ", ".join(ok.problems))
	assert_true(ok.mounts())
	assert_false(ok.installs())


func test_the_verb_comes_from_the_kind_and_nothing_else() -> void:
	assert_true(PackDef.from_dict(_entry({"kind": "campaign"})).installs())
	assert_true(PackDef.from_dict(_entry({"kind": "map", "folder": "River"})).installs())
	assert_true(PackDef.from_dict(_entry({"kind": "art", "folder": ""})).mounts())
	assert_true(PackDef.from_dict(_entry({"kind": "audio", "folder": ""})).mounts())


func test_an_unknown_kind_is_refused_rather_than_defaulted() -> void:
	var p := PackDef.from_dict(_entry({"kind": "theme"}))
	assert_false(p.is_usable())


func test_a_sha256_that_is_not_64_hex_characters_is_refused() -> void:
	for bad in ["", "abc", "g".repeat(64), "b1885a72cf08850da32304d5c2dfa7f35400217e2f40f233f5917290a81008b"]:
		var p := PackDef.from_dict(_entry({"sha256": bad}))
		assert_false(p.is_usable(), "sha256 '%s' should be refused" % bad)


## Upper case IS accepted and normalised, because a publisher's tooling may emit either and
## the comparison in `PackInstaller` is against the lowercased form.
func test_an_uppercase_sha256_is_accepted_and_lowercased() -> void:
	var p := PackDef.from_dict(_entry({
		"sha256": "B1885A72CF08850DA32304D5C2DFA7F35400217E2F40F233F5917290A81008BD"}))
	assert_true(p.is_usable(), "problems: %s" % ", ".join(p.problems))
	assert_eq(p.sha256, "b1885a72cf08850da32304d5c2dfa7f35400217e2f40f233f5917290a81008bd")


## https only. The checksum is the real defence, but a rewritten manifest must not be able
## to downgrade the transport for the part that lands on disk.
func test_a_url_that_is_not_https_is_refused() -> void:
	for bad in [["http://aod.dragoon.co.za/x.zip"], ["ftp://x/y.zip"], [""], []]:
		var p := PackDef.from_dict(_entry({"urls": bad}))
		assert_false(p.is_usable(), "urls %s should be refused" % str(bad))


func test_several_urls_are_kept_in_order_so_a_mirror_is_a_manifest_edit() -> void:
	var p := PackDef.from_dict(_entry({"urls": [
		"https://a.example/one.zip", "https://b.example/two.zip"]}))
	assert_true(p.is_usable())
	assert_eq(p.urls[0], "https://a.example/one.zip")
	assert_eq(p.urls[1], "https://b.example/two.zip")


func test_a_version_below_one_is_refused_because_zero_means_not_installed() -> void:
	for bad in [0, -1]:
		assert_false(PackDef.from_dict(_entry({"version": bad})).is_usable())


## JSON has one number type, so a publisher writing `2.0` must not be refused.
func test_a_version_arriving_as_a_json_float_becomes_an_int() -> void:
	var p := PackDef.from_dict(_entry({"version": 2.0, "size": 100.0}))
	assert_true(p.is_usable(), "problems: %s" % ", ".join(p.problems))
	assert_eq(p.version, 2)
	assert_eq(p.size, 100)


func test_an_entry_that_is_not_an_object_is_refused_without_crashing() -> void:
	for bad in ["a string", 7, [], null]:
		var p := PackDef.from_dict(bad)
		assert_false(p.is_usable())
		assert_false(p.problems.is_empty(), "a refusal is never silent")


func test_a_label_is_never_empty_even_with_no_title() -> void:
	assert_eq(PackDef.from_dict(_entry()).label(), "How To Play")
	assert_eq(PackDef.from_dict(_entry({"title": ""})).label(), "HowToPlay")
	assert_eq(PackDef.from_dict(_entry({"title": "", "folder": ""})).label(), "howtoplay")


func test_the_install_root_differs_by_kind_and_never_touches_the_players_own_maps() -> void:
	var campaign := PackDef.from_dict(_entry())
	assert_eq(campaign.install_dir(), "user://content/scenarios/HowToPlay")

	var map := PackDef.from_dict(_entry({"kind": "map", "folder": "River"}))
	assert_eq(map.install_dir(), "user://content/maps/River")

	# PLAN.md 2.4c keeps `user://maps/` separate so installing content cannot overwrite a
	# player's saved map, and uninstalling cannot delete one.
	assert_false(map.install_dir().begins_with("user://maps/"))


# ── PackManifest ─────────────────────────────────────────────────────────────

func test_a_manifest_reads_its_packs_in_declared_order() -> void:
	var m := PackManifest.parse(_manifest_text([
		_entry({"id": "second", "folder": "Second", "required": false}),
		_entry({"id": "first", "folder": "First"}),
	]))
	assert_true(m.warnings.is_empty(), "warnings: %s" % ", ".join(m.warnings))
	assert_eq(m.packs.size(), 2)
	assert_eq(m.packs[0].id, "second", "manifest order, not sorted")
	assert_eq(m.packs[1].id, "first")


## `CampaignDef`'s rule: one bad entry costs one pack, never the manifest.
func test_one_broken_entry_does_not_hide_the_rest_of_the_manifest() -> void:
	var m := PackManifest.parse(_manifest_text([
		_entry({"id": "../escape"}),
		_entry({"id": "good", "folder": "Good"}),
	]))
	assert_eq(m.packs.size(), 1, "the good pack survives")
	assert_eq(m.packs[0].id, "good")
	assert_false(m.warnings.is_empty(), "and the bad one is reported")
	assert_true(m.warnings[0].contains("packs[0]"), "the warning says WHICH row: %s" % m.warnings[0])


func test_a_duplicate_id_keeps_the_first_and_says_so() -> void:
	var m := PackManifest.parse(_manifest_text([
		_entry({"id": "dup", "folder": "One", "version": 1}),
		_entry({"id": "dup", "folder": "Two", "version": 9}),
	]))
	assert_eq(m.packs.size(), 1)
	assert_eq(m.packs[0].folder, "One", "first wins")
	assert_false(m.warnings.is_empty())


## A future shape is refused, not guessed -- `MapFile`'s rule.
func test_a_future_format_version_is_refused_and_no_packs_are_offered() -> void:
	var m := PackManifest.parse(_manifest_text([_entry()], PackManifest.FORMAT_VERSION + 1))
	assert_true(m.packs.is_empty())
	assert_false(m.warnings.is_empty())
	assert_true(m.warnings[0].contains("update the game"),
			"the message tells the player what to do: %s" % m.warnings[0])


func test_a_manifest_with_no_format_version_is_refused() -> void:
	var m := PackManifest.parse(JSON.stringify({"packs": [_entry()]}))
	assert_true(m.packs.is_empty())
	assert_false(m.warnings.is_empty())


func test_malformed_json_is_refused_with_a_line_number_rather_than_crashing() -> void:
	var m := PackManifest.parse("{\"format_version\": 1, \"packs\": [")
	assert_true(m.packs.is_empty())
	assert_false(m.warnings.is_empty())
	assert_true(m.warnings[0].contains("line"), "says where: %s" % m.warnings[0])


func test_json_that_is_not_an_object_is_refused() -> void:
	for bad in ["[]", "7", "\"a\"", "null", ""]:
		var m := PackManifest.parse(bad)
		assert_true(m.packs.is_empty(), "%s should offer nothing" % bad)
		assert_false(m.warnings.is_empty(), "%s should say why" % bad)


## Unknown fields are IGNORED, which is what lets the server publish a `licence` or
## `screenshots` field tomorrow without stranding today's build.
func test_an_unknown_field_is_ignored_rather_than_refused() -> void:
	var m := PackManifest.parse(_manifest_text([
		_entry({"licence": "CC-BY-4.0", "screenshots": ["a.png"]})]))
	assert_true(m.warnings.is_empty(), "warnings: %s" % ", ".join(m.warnings))
	assert_eq(m.packs.size(), 1)


func test_required_and_optional_are_split_because_they_differ_in_who_decides() -> void:
	var m := PackManifest.parse(_manifest_text([
		_entry({"id": "tutorial", "folder": "Tutorial", "required": true}),
		_entry({"id": "extra", "folder": "Extra", "required": false}),
	]))
	assert_eq(m.required_packs().size(), 1)
	assert_eq(m.required_packs()[0].id, "tutorial")
	assert_eq(m.optional_packs().size(), 1)
	assert_eq(m.optional_packs()[0].id, "extra")


func test_required_defaults_to_false_so_a_forgotten_flag_cannot_force_a_download() -> void:
	var raw := _entry()
	raw.erase("required")
	assert_false(PackDef.from_dict(raw).required)


func test_by_id_finds_a_pack_and_returns_null_for_one_that_is_not_there() -> void:
	var m := PackManifest.parse(_manifest_text([_entry()]))
	assert_not_null(m.by_id("howtoplay"))
	assert_null(m.by_id("nothing"))


func test_the_manifest_url_is_unversioned_because_a_shipped_apk_bakes_it_in() -> void:
	# Moving or renaming it strands every copy already installed -- there is no second
	# channel to tell them where it went.
	assert_true(PackManifest.MANIFEST_URL.begins_with("https://"))
	assert_true(PackManifest.MANIFEST_URL.ends_with("/packs.json"))
	assert_false(PackManifest.MANIFEST_URL.contains("_v"))


# ── PackIndex ────────────────────────────────────────────────────────────────

func test_the_default_path_is_the_players_own_installed_record() -> void:
	assert_eq(PackIndex.USER_FILE, "user://packs_installed.json")


func test_an_absent_file_means_nothing_is_installed() -> void:
	assert_true(PackIndex.all(PATH).is_empty())
	assert_eq(PackIndex.version_of("howtoplay", PATH), 0)
	assert_false(PackIndex.is_installed("howtoplay", PATH))


func test_a_recorded_version_reads_back() -> void:
	assert_true(PackIndex.record("howtoplay", 2, PATH))
	assert_eq(PackIndex.version_of("howtoplay", PATH), 2)
	assert_true(PackIndex.is_installed("howtoplay", PATH))


## ⚠️ THE OPPOSITE OF `CampaignProgress`, WHICH IS ONE-WAY. A publisher rolling a pack back
## from v3 to v2 has decided v3 was wrong, and a client that clamped to the highest number
## it had ever seen would refuse the fix and keep the bad content forever.
func test_a_version_is_assigned_and_not_maxed_so_a_rollback_can_be_published() -> void:
	PackIndex.record("howtoplay", 3, PATH)
	PackIndex.record("howtoplay", 2, PATH)
	assert_eq(PackIndex.version_of("howtoplay", PATH), 2, "a rollback sticks")


func test_needs_download_is_the_one_place_missing_and_outdated_are_decided() -> void:
	var pack := PackDef.from_dict(_entry({"version": 2}))

	assert_true(PackIndex.needs_download(pack, PATH), "not installed at all")

	PackIndex.record(pack.id, 1, PATH)
	assert_true(PackIndex.needs_download(pack, PATH), "installed but older")

	PackIndex.record(pack.id, 2, PATH)
	assert_false(PackIndex.needs_download(pack, PATH), "current")

	PackIndex.record(pack.id, 3, PATH)
	assert_false(PackIndex.needs_download(pack, PATH), "newer than the manifest is not a download")


func test_recording_one_pack_leaves_the_others_alone() -> void:
	PackIndex.record("a", 1, PATH)
	PackIndex.record("b", 5, PATH)
	assert_eq(PackIndex.version_of("a", PATH), 1)
	assert_eq(PackIndex.version_of("b", PATH), 5)


func test_forget_removes_a_pack_so_a_deleted_campaign_is_re_downloadable() -> void:
	PackIndex.record("a", 1, PATH)
	assert_true(PackIndex.forget("a", PATH))
	assert_false(PackIndex.is_installed("a", PATH))
	# The whole point: a row left behind would make the game believe a deleted campaign is
	# still there and skip re-downloading it.
	assert_true(PackIndex.needs_download(PackDef.from_dict(_entry({"id": "a"})), PATH))


func test_a_refusal_to_record_is_never_silent() -> void:
	assert_false(PackIndex.record("", 1, PATH), "no id")
	assert_false(PackIndex.record("a", 0, PATH), "version 0 means not installed")
	assert_true(PackIndex.all(PATH).is_empty())


## Read as NOTHING INSTALLED, which is the safe direction: it costs a re-download and a
## re-verify. Reading a broken file as "everything is fine" would leave a player stuck with
## content the game believes it has and cannot find.
func test_a_broken_file_reads_as_nothing_installed() -> void:
	for bad in ["{", "[]", "7", "", "{\"packs\": 7}"]:
		_write_raw(bad)
		assert_true(PackIndex.all(PATH).is_empty(), "%s should read as empty" % bad)
		assert_eq(PackIndex.version_of("howtoplay", PATH), 0)


func test_a_value_that_is_not_a_number_reads_as_not_installed() -> void:
	_write_raw(JSON.stringify({"format_version": 1, "packs": {"a": "two", "b": 3}}))
	assert_eq(PackIndex.version_of("a", PATH), 0)
	assert_eq(PackIndex.version_of("b", PATH), 3)


func test_a_negative_version_reads_as_not_installed() -> void:
	_write_raw(JSON.stringify({"format_version": 1, "packs": {"a": -5}}))
	assert_eq(PackIndex.version_of("a", PATH), 0)


## `CampaignProgress` does the same, for the same reason: a value we cannot interpret must
## not be reported as a version, and deleting somebody's file content because one line of it
## was unreadable is the worse mistake.
func test_a_row_this_build_cannot_read_survives_a_write() -> void:
	_write_raw(JSON.stringify({"format_version": 1, "packs": {"future": {"v": 1}, "a": 1}}))
	PackIndex.record("b", 2, PATH)

	var f := FileAccess.open(PATH, FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	assert_true((raw["packs"] as Dictionary).has("future"), "the unreadable row is still there")
	assert_eq(int((raw["packs"] as Dictionary)["b"]), 2)


func test_the_file_it_writes_is_the_file_it_reads() -> void:
	PackIndex.record("a", 4, PATH)
	assert_true(FileAccess.file_exists(PATH))
	assert_eq(PackIndex.all(PATH), {"a": 4})


func _write_raw(text: String) -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()
