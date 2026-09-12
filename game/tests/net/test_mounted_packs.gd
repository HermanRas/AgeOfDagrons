## Phase 0.3's missing half: a mounted pack that survives a restart, and an atlas page that
## can be opened out of one.
##
## ## WHAT THESE CAN AND CANNOT SEE
##
## `ProjectSettings.load_resource_pack()` is **irreversible** -- Godot has no
## `unload_resource_pack()` -- so no test may mount a real pack: whatever it added would stay
## in `res://` for the rest of the suite, in an order that depends on which tests ran. So the
## engine call itself is exercised by `dev_preview/preview_art_pack.tscn` (which mounts the
## really-built packs and exits non-zero) and NOT here.
##
## What is here is everything around it that a mistake would hide in: which filenames count
## as packs, that a second mount of one path is refused rather than repeated, that the kept
## filename follows the container it actually is, and that a page decodes from bytes.
##
## ⚠️ **AND THE BUG THAT MADE THIS FILE EXIST IS ONE NO TEST FOUND.** From 0.3 until
## 2026-09-12 `load_resource_pack()` was called only at install time, so a mount lasted one
## process while `PackIndex` recorded the pack as installed forever. It was unreachable
## because `campaign` and `map` packs are INSTALLED rather than mounted -- the only two kinds
## that had ever shipped. A suite cannot find a hole in a code path nothing takes; the first
## art pack is what found it.
extends TestCase


# ── which files are packs ───────────────────────────────────────────────────

func test_the_two_container_suffixes_are_recognised() -> void:
	assert_true(MountedPacks._is_pack("art_base_v1.zip"))
	assert_true(MountedPacks._is_pack("pack_art_v1.pck"))


func test_anything_else_in_the_directory_is_left_alone() -> void:
	# `user://packs/` is ours, but a `.part` is a download in flight and a `.building` is
	# the packer's temporary. Mounting either would mount a truncated file.
	for name in ["base.part", "art_base_v1.zip.building", "notes.txt", "packs", ""]:
		assert_false(MountedPacks._is_pack(name), "'%s' must not be mounted" % name)


func test_zip_is_listed_before_pck_because_that_is_what_we_publish() -> void:
	# Not a behaviour, a statement of intent that would otherwise live in a comment only:
	# the art pack is a zip (the owner's call, 2026-09-12) and `.pck` is kept so a pack
	# built the other way still mounts.
	assert_eq(MountedPacks.SUFFIXES[0], ".zip")
	assert_true(MountedPacks.SUFFIXES.has(".pck"))


# ── the sweep ───────────────────────────────────────────────────────────────

func test_no_packs_directory_is_silent_and_normal() -> void:
	# The first-run state on every device: nothing downloaded, nothing to mount. It must
	# not warn, because a warning here would fire for every player who has not downloaded
	# anything yet.
	var got := MountedPacks.mount_all("user://test_mounted_packs_absent/")
	assert_eq(got.size(), 0)


func test_an_empty_packs_directory_mounts_nothing() -> void:
	var dir := "user://test_mounted_packs_empty/"
	DirAccess.make_dir_recursive_absolute(dir)
	var got := MountedPacks.mount_all(dir)
	assert_eq(got.size(), 0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func test_a_file_that_is_not_there_is_not_mounted() -> void:
	assert_false(MountedPacks.mount_one("user://test_mounted_packs_absent/nothing.zip"))


func test_an_empty_path_is_refused_rather_than_reaching_the_engine() -> void:
	assert_false(MountedPacks.mount_one(""))


# ── is_mounted, and why it is not just `mount_one` returning false ──────────

func test_a_path_this_process_has_not_mounted_reports_false() -> void:
	assert_false(MountedPacks.is_mounted("user://packs/never_touched.zip"))


func test_mounted_is_sorted_so_two_devices_report_in_one_order() -> void:
	var got := MountedPacks.mounted()
	var sorted := PackedStringArray(got)
	sorted.sort()
	assert_eq("|".join(got), "|".join(sorted))


# ── the kept filename follows the container ────────────────────────────────

## `_mount()` hardcoded `<id>.pck` until 2026-09-12, which would have named every art pack
## after a container it is not. The file still MOUNTS under a wrong name -- the engine
## sniffs rather than trusting the extension -- so nothing would have broken and
## `user://packs/` would simply have lied to whoever listed it while diagnosing a device.
func test_the_kept_name_takes_its_suffix_from_the_url() -> void:
	var installer := PackInstaller.new()
	var pack := _art_pack("https://example.test/downloads/art_base_v1.zip")
	# The downloaded payload is always `<id>.part`, so the URL is the only thing that knows.
	assert_eq(installer._container_suffix(pack, "user://downloads/base.part"), ".zip")
	installer.free()


func test_a_sideloaded_file_names_its_own_container() -> void:
	var installer := PackInstaller.new()
	var pack := _art_pack("https://example.test/downloads/art_base_v1.zip")
	assert_eq(installer._container_suffix(pack, "user://shared/handed_to_us.pck"), ".pck")
	installer.free()


func test_an_unrecognised_container_keeps_pck_rather_than_being_refused() -> void:
	# The checksum has already passed by the time this is asked, and the ENGINE is the judge
	# of the format. Refusing on a filename would reject a good pack over its name.
	var installer := PackInstaller.new()
	var pack := _art_pack("https://example.test/downloads/art_base_v1.bin")
	assert_eq(installer._container_suffix(pack, "user://downloads/base.part"), ".pck")
	installer.free()


func _art_pack(url: String) -> PackDef:
	return PackDef.from_dict({
		"id": "base", "kind": "art", "version": 1,
		"size": 10, "sha256": "0".repeat(64), "urls": [url],
	})


# ── an art entry in the manifest ───────────────────────────────────────────

func test_an_art_pack_mounts_and_has_no_install_directory() -> void:
	var pack := _art_pack("https://example.test/downloads/art_base_v1.zip")
	assert_true(pack.is_usable(), "problems: %s" % [pack.problems])
	assert_true(pack.mounts())
	assert_false(pack.installs())
	assert_eq(pack.install_dir(), "", "a mounted pack unpacks nowhere")


func test_an_art_pack_carrying_a_folder_is_refused() -> void:
	# The publishing mistake this catches: `folder` on a mounted pack means whoever wrote
	# the manifest believes it unpacks somewhere. `build_packs.py` refuses to BUILD one and
	# `PackDef` refuses to accept one, deliberately at both ends.
	var pack := PackDef.from_dict({
		"id": "base", "kind": "art", "version": 1, "folder": "Art",
		"size": 10, "sha256": "0".repeat(64),
		"urls": ["https://example.test/art_base_v1.zip"],
	})
	assert_false(pack.is_usable())
	assert_true(", ".join(pack.problems).contains("mounted"),
			"the complaint says why: %s" % [pack.problems])


# ── decoding a page ────────────────────────────────────────────────────────

## ⚠️ **`page_texture()` REPLACED A `load()` AND THE OLD CALL CANNOT OPEN A PACKED PAGE.**
## Measured on 4.7.1: for a file inside a mounted zip `ResourceLoader.exists()` is **false**
## and `load()` pushes an engine error, because a hand-built zip carries no `.import`.
##
## The failure that would have shipped is worth naming: it is NOT the magenta placeholder.
## `GameDataRegistry._resolve` picks the placeholder branch on whether the `.atlas.json`
## PARSED, and the JSON parses fine out of the zip -- so every unit would have drawn nothing
## at all, silently.
func test_a_page_that_is_not_there_is_null_and_not_an_error() -> void:
	# The clean-checkout state: `game/assets/atlases/` is gitignored, so this is what a
	# fresh clone does on every page of every atlas. It must be quiet.
	assert_eq(AtlasEntry.page_texture("res://assets/atlases/ZZ_no_such_page_0.png"), null)


func test_an_empty_path_decodes_to_null() -> void:
	assert_eq(AtlasEntry.page_texture(""), null)


func test_a_real_page_decodes_to_a_texture_and_is_cached_by_path() -> void:
	var path := _any_staged_page()
	if path.is_empty():
		# A clean checkout has no atlases. Skipped rather than failed -- and SAID, because
		# a test that silently measures nothing is §6's `== 0` trap.
		print("      (skipped: no staged atlas on this machine)")
		return
	var first := AtlasEntry.page_texture(path)
	assert_true(first != null, "a staged page must decode: %s" % path)
	assert_true(first.get_width() > 0 and first.get_height() > 0)

	# THE SAME OBJECT, not an equal one. `load()` used to get this dedupe free from Godot's
	# resource cache; the raw route has to do it, and two entries naming one page is not a
	# curiosity -- `vis.dragon_baby` and `vis.dragon_rigged` are the same 7.7 MB atlas.
	var second := AtlasEntry.page_texture(path)
	assert_true(first == second, "a second call must not decode the page again")


func test_forgetting_pages_drops_the_cache() -> void:
	var path := _any_staged_page()
	if path.is_empty():
		print("      (skipped: no staged atlas on this machine)")
		return
	var first := AtlasEntry.page_texture(path)
	AtlasEntry.forget_pages()
	var second := AtlasEntry.page_texture(path)
	assert_true(first != null and second != null)
	# Not the same object any more: a mid-session mount has to be able to replace what a
	# pre-download resolve cached, or the art arrives and nothing on screen changes.
	assert_true(first != second, "forget_pages() must actually drop it")


## Any atlas page staged on this machine, or "" on a clean checkout.
func _any_staged_page() -> String:
	var d := DirAccess.open("res://assets/atlases")
	if d == null:
		return ""
	var names := d.get_files()
	names.sort()
	for name in names:
		if name.ends_with(".png"):
			return "res://assets/atlases/".path_join(name)
	return ""
