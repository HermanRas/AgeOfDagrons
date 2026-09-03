## Phase 0.3: the two screens, and the boot's routing decision.
##
## ## WHAT IS TESTED HERE AND WHAT IS NOT
##
## Both screens build entirely in `_init()` and need no `SceneTree`, so their STATE rules
## are asserted directly. What is deliberately not tested:
##
##   - **the scene changes.** `get_tree().change_scene_to_file()` cannot be called without a
##     tree, which is `test_help_screen`'s and `test_pause_menu`'s reason too. What is tested
##     instead is `BootScreen.next_scene()` -- the DECISION, which is the half that can rot.
##   - **the network.** `dev_preview/preview_content_browser.tscn` owns that, against the
##     real server, and exits non-zero.
##   - **whether anything is legible.** `preview_menus` photographs the footer and asserts
##     both buttons are inside the window; a rect is not a picture.
##
## ## ⚠️ THE ROW-STATE RULE IS THE POINT OF THIS FILE
##
## `ContentBrowser` decides per row whether to offer GET, UPDATE, INSTALLED or DELETE, and
## that rule already produced a bug that looked like a failed download: installing the only
## published pack made its row VANISH under *"There is no new content to download right
## now"*, because a `required` pack that is installed is filtered out as clutter. Both halves
## were behaving as designed. **Every clause of that rule now has a test below.**
extends TestCase

const DIR := "user://test_content_delivery"
const PATH := "user://test_content_delivery/installed.json"


func before_each() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _entry(overrides: Dictionary = {}) -> Dictionary:
	var base := {
		"id": "pack",
		"kind": "campaign",
		"folder": "Folder",
		"version": 1,
		"required": false,
		"title": "A Campaign",
		"size": 100,
		"sha256": "b1885a72cf08850da32304d5c2dfa7f35400217e2f40f233f5917290a81008bd",
		"urls": ["https://example.invalid/a.zip"],
	}
	for k in overrides:
		base[k] = overrides[k]
	return base


func _manifest(entries: Array) -> PackManifest:
	return PackManifest.parse(JSON.stringify({
		"format_version": 1, "generated": "2026-09-03T00:00:00Z", "packs": entries,
	}))


func _browser(manifest: PackManifest) -> ContentBrowser:
	var b := ContentBrowser.new()
	b.index_path = PATH
	b.show_manifest(manifest)
	return b


# ── the boot's routing decision ──────────────────────────────────────────────

func test_a_missing_required_pack_sends_the_boot_to_the_download_screen() -> void:
	var m := _manifest([_entry({"required": true})])
	assert_true(PackIndex.any_required_missing(m, PATH))


func test_an_installed_required_pack_sends_the_boot_straight_to_the_menu() -> void:
	var m := _manifest([_entry({"required": true, "version": 2})])
	PackIndex.record("pack", 2, PATH)
	assert_false(PackIndex.any_required_missing(m, PATH))


func test_an_outdated_required_pack_still_needs_the_download_screen() -> void:
	var m := _manifest([_entry({"required": true, "version": 3})])
	PackIndex.record("pack", 2, PATH)
	assert_true(PackIndex.any_required_missing(m, PATH))


## An OPTIONAL pack, however missing, must never hold up the boot.
func test_a_missing_optional_pack_does_not_delay_the_front_door() -> void:
	var m := _manifest([_entry({"required": false})])
	assert_false(PackIndex.any_required_missing(m, PATH))


## The offline case, and it is the one that must not strand anybody: PLAN.md 3.2 says the
## game runs on placeholders rather than failing.
func test_no_manifest_at_all_goes_to_the_menu_rather_than_a_download_screen() -> void:
	assert_false(PackIndex.any_required_missing(null, PATH))
	assert_false(PackIndex.any_required_missing(_manifest([]), PATH))


func test_the_boot_routes_on_that_decision_and_nothing_else() -> void:
	var boot := BootScreen.new()
	boot.auto_advance = false
	boot.index_path = PATH

	# No manifest yet: the front door.
	assert_true(boot.next_scene().ends_with("MainMenu.tscn"))

	boot._on_manifest(_manifest([_entry({"required": true})]))
	assert_true(boot.next_scene().ends_with("Download.tscn"))

	PackIndex.record("pack", 1, PATH)
	assert_true(boot.next_scene().ends_with("MainMenu.tscn"))
	boot.free()


## ⚠️ A MANIFEST WITH ONE BAD ROW IS STILL USED. The first draft of `BootScreen` discarded
## any manifest carrying a warning, which would have meant a typo in some future community
## row silently stopping the tutorial from ever installing.
func test_one_malformed_row_does_not_stop_the_tutorial_installing() -> void:
	var boot := BootScreen.new()
	boot.auto_advance = false
	boot.index_path = PATH

	var m := _manifest([_entry({"id": "../escape"}), _entry({"required": true})])
	assert_false(m.warnings.is_empty(), "the fixture really is a warning")
	boot._on_manifest(m)
	assert_true(boot.next_scene().ends_with("Download.tscn"),
			"the good required pack is still seen")
	boot.free()


# ── the browser's row-state rule ─────────────────────────────────────────────

func test_an_optional_pack_is_always_listed_installed_or_not() -> void:
	var b := _browser(_manifest([_entry()]))
	assert_eq(b.offered_ids(), ["pack"] as Array[String])

	PackIndex.record("pack", 1, PATH)
	b.show_manifest(_manifest([_entry()]))
	assert_eq(b.offered_ids(), ["pack"] as Array[String],
			"a list that hid what you own could not offer you an update to it")
	b.free()


func test_a_missing_required_pack_is_listed_so_a_failed_boot_can_be_retried() -> void:
	# Without this there would be no button anywhere in the game to try again, and the
	# campaign list would stay empty forever.
	var b := _browser(_manifest([_entry({"required": true})]))
	assert_eq(b.offered_ids(), ["pack"] as Array[String])
	b.free()


func test_an_installed_required_pack_is_hidden_as_clutter() -> void:
	PackIndex.record("pack", 1, PATH)
	var b := _browser(_manifest([_entry({"required": true})]))
	assert_true(b.offered_ids().is_empty())
	b.free()


## ⚠️ THE VANISHING ROW. Installing during this visit keeps the row on screen, so a
## successful press cannot turn "here is a thing" into "there is nothing".
func test_a_pack_installed_during_this_visit_stays_on_screen() -> void:
	var b := _browser(_manifest([_entry({"required": true})]))
	assert_eq(b.offered_ids(), ["pack"] as Array[String], "offered before")

	# What `_on_get_pressed` does on success, without the download.
	PackIndex.record("pack", 1, PATH)
	b._installed_here["pack"] = true
	b.show_manifest(_manifest([_entry({"required": true})]))

	assert_eq(b.offered_ids(), ["pack"] as Array[String],
			"still on screen, now reading INSTALLED")
	b.free()


func test_manifest_order_is_the_publishers_and_is_preserved() -> void:
	var b := _browser(_manifest([
		_entry({"id": "second", "folder": "B"}),
		_entry({"id": "first", "folder": "A"}),
	]))
	assert_eq(b.offered_ids(), ["second", "first"] as Array[String])
	b.free()


func test_an_unreadable_manifest_says_so_rather_than_saying_there_is_nothing() -> void:
	# The two are genuinely different: "offline" and "the server is serving something
	# wrong" want different responses from whoever is reading the screen.
	var broken := PackManifest.parse("{")
	var b := _browser(broken)
	assert_true(b.offered_ids().is_empty())
	assert_true(b.status_text().contains("Could not read"),
			"status was: %s" % b.status_text())
	b.free()


func test_an_empty_manifest_reports_nothing_new_rather_than_an_error() -> void:
	var b := _browser(_manifest([]))
	assert_true(b.status_text().contains("no new content"),
			"status was: %s" % b.status_text())
	b.free()


# ── the download screen's reporting ──────────────────────────────────────────

## A failed required pack must be REPORTED and then let past. PLAN.md 3.2: the game runs on
## placeholders rather than failing, so there is deliberately no way to get stuck here.
func test_a_failed_pack_is_named_and_the_player_is_let_through() -> void:
	var screen := DownloadScreen.new()
	screen.auto_advance = false
	screen.index_path = PATH

	var pack := PackDef.from_dict(_entry({"title": "The Tutorial"}))
	screen._on_finished(pack, false, "checksum does not match")
	screen._finish()

	assert_eq(screen.failures().size(), 1)
	assert_true(screen.status_text().contains("The Tutorial"),
			"the player is told WHICH: %s" % screen.status_text())
	assert_true(screen.status_text().contains("checksum"), "and why")
	assert_true(screen.status_text().contains("DOWNLOAD MORE"), "and where to retry")
	assert_true(screen.showing_continue(), "and there is a way out")
	screen.free()


func test_a_clean_run_offers_no_button_because_it_advances_on_its_own() -> void:
	var screen := DownloadScreen.new()
	screen.auto_advance = false
	screen.index_path = PATH

	screen._on_finished(PackDef.from_dict(_entry()), true, "")
	screen._finish()

	assert_true(screen.failures().is_empty())
	assert_false(screen.showing_continue(),
			"a CONTINUE on a screen about to advance invites a player to wonder what they interrupted")
	screen.free()


## `total` is 0 until `Content-Length` arrives, and a percentage of an unknown total is the
## classic divide-by-zero in a progress UI.
func test_progress_before_a_content_length_reports_megabytes_and_not_zero_percent() -> void:
	var screen := DownloadScreen.new()
	screen.auto_advance = false
	var pack := PackDef.from_dict(_entry({"title": "Big"}))

	screen._on_progress(pack, 1048576, 0)
	assert_true(screen.status_text().contains("MB"), "status was: %s" % screen.status_text())
	assert_false(screen.status_text().contains("%"), "no percentage without a total")

	screen._on_progress(pack, 50, 100)
	assert_true(screen.status_text().contains("50%"), "status was: %s" % screen.status_text())
	screen.free()


## The static handover is one-shot, on `ScenarioScreen.pending`'s precedent: a second visit
## with nothing parked must fetch rather than silently reopening the last manifest.
func test_the_parked_manifest_is_taken_once() -> void:
	DownloadScreen.pending = _manifest([_entry({"required": true})])

	var first := DownloadScreen.new()
	first.auto_advance = false
	assert_null(DownloadScreen.pending, "taken and cleared in _init()")
	first.free()

	var second := DownloadScreen.new()
	second.auto_advance = false
	# Nothing parked, so it would fetch its own -- which is what `run()` does when the
	# manifest is null. Asserted as "did not inherit the first one's".
	assert_null(DownloadScreen.pending)
	second.free()
