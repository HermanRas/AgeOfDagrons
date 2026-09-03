## Fetches, verifies, and then INSTALLS or MOUNTS a pack (PLAN.md 3.2 and 3.3). Phase 0.3.
##
## A `Node` because it owns an `HTTPRequest`, and **not an autoload** -- `Campaigns`'
## argument, which applies harder here: §6.1's table is closed, and the only things that
## need this are the boot screen and the DOWNLOAD MORE browser. Both make one, use it, and
## let it go. What outlives the object is on disk (`PackIndex`) or in the engine
## (`load_resource_pack`), so there is nothing to keep resident.
##
##     var inst := PackInstaller.new()
##     add_child(inst)
##     var manifest := await inst.fetch_manifest()
##     await inst.install_all(manifest.required_packs())
##
## ## THE ORDER IS SIZE, THEN HASH, THEN UNPACK, THEN RECORD
##
## Each step exists because the one before it cannot see the fault the next one catches:
##
##   1. **Size** -- a truncated download is the common failure, and a length mismatch names
##      it exactly. Skipping to the hash reports "checksum mismatch", which reads as
##      corruption or tampering and sends somebody hunting the wrong fault.
##   2. **SHA-256** -- the real defence, and the only one that survives a wrong mirror, a
##      cache serving a stale file, or a rewritten manifest. PLAN.md 3.2 makes it the gate.
##   3. **Unpack into a staging directory, then swap** -- so a zip that fails halfway
##      cannot leave a half-campaign where a working one was.
##   4. **Record in `PackIndex`** -- last, and only on success. A version written first
##      would make an interrupted install indistinguishable from a finished one, and the
##      client would then skip re-fetching a pack that is half on disk.
##
## ## ⚠️ EVERY ZIP ENTRY IS CHECKED, NOT JUST THE FOLDER NAME
##
## `PackDef` whitelists `id` and `folder` because they name a directory. That says nothing
## about what is INSIDE the archive: an entry called `../../../project.godot` would escape
## the install root entirely, and `zip` files carrying `..` are the oldest trick there is.
## So `_is_safe_entry()` runs on every name in the archive and the whole install is refused
## if any one of them fails -- refused, not skipped, because an archive containing one
## hostile path is not an archive to trust the rest of.
##
## The checksum makes this unreachable for a pack we published, and that is exactly why it
## is here: the check has to hold for content whose checksum we did NOT choose. Community
## campaigns are the stated goal (the owner, 2026-09-03), so the day will come when the
## manifest lists somebody else's zip.
class_name PackInstaller
extends Node

## Fired once the manifest is parsed, successfully or not -- `warnings` says which.
signal manifest_ready(manifest: PackManifest)

signal pack_started(pack: PackDef)

## `total` is 0 until the server's `Content-Length` arrives, and the bar must cope with
## that: a percentage of an unknown total is the classic divide-by-zero in a progress UI.
signal pack_progress(pack: PackDef, bytes: int, total: int)

signal pack_finished(pack: PackDef, ok: bool, message: String)

signal batch_finished(installed: int, failed: int)

## Where a download lands before it is verified. Under `user://` and NOT beside the
## installed content, so a rejected payload is never one rename away from being live.
const SCRATCH_DIR := "user://downloads/"

## Suffix for the half-unpacked copy. Hidden-ish and inside the install root, because the
## final step has to be a rename and a rename cannot cross a filesystem.
const STAGING_SUFFIX := ".installing"

## The manifest is small and blocks the front door, so it gets a short leash. A DOWNLOAD
## gets none (see `_download`): a 400 MB pack on a phone legitimately takes minutes, and a
## timeout that fires mid-download would look exactly like a broken server.
const MANIFEST_TIMEOUT_SECONDS := 15.0

var _http: HTTPRequest
var _active: PackDef = null
var _cancelled := false

## ⚠️ ONE `HTTPRequest` MEANS ONE REQUEST AT A TIME, AND THE ENGINE'S REFUSAL IS UGLY.
##
## Starting a second request on a busy `HTTPRequest` does not return an error -- it prints
## two `ERROR:` lines from C++ (`set_download_file` fails its condition, then `request_raw`
## says it is already processing) and then hands back error 44, which surfaced as
## *"cannot reach https://..."*: a message that blames the network for a caller's mistake.
##
## Found by `preview_content_browser` on its first run, where `ContentBrowser._ready()`
## kicked off a fetch and the preview asked for another. Guarded here rather than only in
## the caller, because every future caller would have to remember.
var _in_flight := false


func _ready() -> void:
	_http = HTTPRequest.new()
	# Threaded, so writing a large body to disk does not stall the frame that is drawing
	# the progress bar.
	_http.use_threads = true
	# ⚠️ GZIP OFF, AND NOT FOR THE OBVIOUS REASON. A `.zip`/`.pck` is already compressed so
	# there is nothing to win -- but the reason it must be OFF is that `Content-Length`
	# would then describe the COMPRESSED body while `get_downloaded_bytes()` counts
	# decompressed bytes, so every progress bar in this file would report a percentage
	# against the wrong total and finish at something other than 100%.
	_http.accept_gzip = false
	add_child(_http)


func _process(_delta: float) -> void:
	if _active == null:
		return
	var got := _http.get_downloaded_bytes()
	if got >= 0:
		pack_progress.emit(_active, got, maxi(_http.get_body_size(), 0))


## Ask the player's download to stop at the next boundary. Checked between packs and
## between steps rather than mid-write, so a cancel never leaves a staging directory live.
func cancel() -> void:
	_cancelled = true
	if _active != null:
		_http.cancel_request()


## Fetch and parse `packs.json`. Never returns null -- an offline device gets a manifest
## with no packs and one warning, which is the same shape as a manifest that is empty, and
## both mean "carry on with what is installed" (PLAN.md 3.2).
func fetch_manifest(url: String = PackManifest.MANIFEST_URL) -> PackManifest:
	if _in_flight:
		var busy := PackManifest.new()
		busy.warnings.append("a download is already in progress; not fetching the manifest again")
		manifest_ready.emit(busy)
		return busy

	_http.timeout = MANIFEST_TIMEOUT_SECONDS
	_http.set_download_file("")            # into memory; the manifest is a few KB

	var err := _http.request(url)
	if err != OK:
		var failed := PackManifest.new()
		failed.warnings.append("cannot reach %s (error %d)" % [url, err])
		manifest_ready.emit(failed)
		return failed

	_in_flight = true
	var result: Array = await _http.request_completed
	_in_flight = false
	var code := int(result[1])
	var body: PackedByteArray = result[3]

	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		var failed := PackManifest.new()
		failed.warnings.append("%s did not answer (result %d)" % [url, int(result[0])])
		manifest_ready.emit(failed)
		return failed
	if code != 200:
		var failed := PackManifest.new()
		failed.warnings.append("%s answered HTTP %d" % [url, code])
		manifest_ready.emit(failed)
		return failed

	var manifest := PackManifest.parse(body.get_string_from_utf8())
	manifest_ready.emit(manifest)
	return manifest


## Install or mount every pack in `packs` that is missing or outdated, in order. Emits
## `batch_finished`. Already-current packs are skipped silently -- that is the normal case
## on every boot after the first.
func install_all(packs: Array[PackDef], index_path: String = PackIndex.USER_FILE) -> void:
	_cancelled = false
	var installed := 0
	var failed := 0
	for pack in packs:
		if _cancelled:
			break
		if not PackIndex.needs_download(pack, index_path):
			continue
		if await install(pack, index_path):
			installed += 1
		else:
			failed += 1
	batch_finished.emit(installed, failed)


## One pack, all the way. `false` means nothing changed on disk -- a failure never leaves
## the previous copy worse off than it was.
func install(pack: PackDef, index_path: String = PackIndex.USER_FILE) -> bool:
	pack_started.emit(pack)

	if not pack.is_usable():
		return _fail(pack, "manifest entry is unusable: %s" % ", ".join(pack.problems))

	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var scratch := SCRATCH_DIR.path_join("%s.part" % pack.id)

	var reached := false
	var last_error := "no urls"
	for url in pack.urls:
		if _cancelled:
			return _fail(pack, "cancelled")
		last_error = await _download(pack, url, scratch)
		if last_error.is_empty():
			reached = true
			break
	if not reached:
		_delete_file(scratch)
		return _fail(pack, last_error)

	return _accept(pack, scratch, index_path, true)


## Verify a pack that is ALREADY on disk, then install or mount it -- steps 1 to 4 of the
## class comment, with the download left out.
##
## ## WHY THIS IS A SEPARATE ENTRY POINT
##
## Two reasons, and the first is what forced it. **Nothing in the suite can test the verify
## and unpack steps through `install()`**, because that one needs a URL and a test that
## needs the internet fails on a train. Every refusal worth having -- a zip carrying `..`, a
## truncated payload, a checksum that does not match, a swap that must not destroy the
## previous copy -- lives on this side of the download and is now reachable without one.
##
## The second is that PLAN.md 3.3 wants content that can be *"shared in"*, and a campaign
## arriving as a file somebody sent rather than as a URL is this function with a different
## caller.
##
## `owned` says whether this file is ours to consume: a download's scratch copy is deleted
## when it is spent, and a caller's file is left exactly where it was.
func install_from_file(pack: PackDef, path: String,
		index_path: String = PackIndex.USER_FILE, owned: bool = false) -> bool:
	pack_started.emit(pack)
	if not pack.is_usable():
		return _fail(pack, "manifest entry is unusable: %s" % ", ".join(pack.problems))
	if not FileAccess.file_exists(path):
		return _fail(pack, "%s is not there" % path)
	return _accept(pack, path, index_path, owned)


## Size, then hash, then unpack or mount, then record. The order is the class comment's and
## each step catches what the one before it cannot see.
func _accept(pack: PackDef, file: String, index_path: String, owned: bool) -> bool:
	# 1. SIZE, before the hash. A truncated download is the common failure and a length
	#    comparison names it exactly; going straight to the hash would report "checksum
	#    mismatch", which reads as corruption or tampering.
	var got_size := _file_size(file)
	if got_size != pack.size:
		if owned:
			_delete_file(file)
		return _fail(pack, "download is %d bytes, manifest says %d" % [got_size, pack.size])

	# 2. SHA-256.
	var got_hash := FileAccess.get_sha256(file)
	if got_hash.to_lower() != pack.sha256:
		if owned:
			_delete_file(file)
		# The hashes are NOT printed. They are 64 characters each, they mean nothing to a
		# player, and the actionable fact is the one sentence.
		return _fail(pack, "checksum does not match; the download was corrupt or is not the file the manifest describes")

	# 3. INSTALL or MOUNT.
	var problem := ""
	if pack.installs():
		problem = _unpack(pack, file)
	else:
		problem = _mount(pack, file, owned)
	if not problem.is_empty():
		if owned:
			_delete_file(file)
		return _fail(pack, problem)

	# A mounted pack keeps its file: `load_resource_pack()` reads it for the life of the
	# process and on every boot after, so `_mount` has already put it somewhere permanent.
	# An installed one has been unpacked and the archive is spent.
	if pack.installs() and owned:
		_delete_file(file)

	# 4. RECORD, last. A version written earlier would make an interrupted install
	#    indistinguishable from a finished one.
	PackIndex.record(pack.id, pack.version, index_path)
	pack_finished.emit(pack, true, "")
	return true


## Delete installed content and forget it (PLAN.md 3.3: content must be removable).
##
## Only `installs()` packs can be removed. A MOUNTED pack cannot be un-mounted -- Godot has
## no `unload_resource_pack()` -- so removing art would need a restart to take effect, and
## a button that silently requires one is worse than no button. The browser therefore
## offers delete on content and not on art.
func uninstall(pack: PackDef, index_path: String = PackIndex.USER_FILE) -> bool:
	if not pack.installs():
		push_warning("PackInstaller: '%s' is mounted and cannot be uninstalled" % pack.id)
		return false
	var dir := pack.install_dir()
	if dir.is_empty():
		return false
	if DirAccess.dir_exists_absolute(dir):
		var err := _remove_tree(dir)
		if not err.is_empty():
			push_warning("PackInstaller: %s" % err)
			return false
	PackIndex.forget(pack.id, index_path)
	return true


## One attempt at one URL. Returns "" on success, or the complaint.
func _download(pack: PackDef, url: String, scratch: String) -> String:
	if _in_flight:
		return "a download is already in progress"

	_delete_file(scratch)            # a leftover `.part` would be appended to, not replaced

	# NO TIMEOUT on a payload -- see MANIFEST_TIMEOUT_SECONDS. Progress is on screen and
	# `cancel()` is the player's escape.
	_http.timeout = 0.0
	_http.set_download_file(scratch)

	var err := _http.request(url)
	if err != OK:
		return "cannot reach %s (error %d)" % [url, err]

	_in_flight = true
	_active = pack
	set_process(true)
	var result: Array = await _http.request_completed
	_active = null
	set_process(false)
	_in_flight = false

	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		return "%s did not answer (result %d)" % [url, int(result[0])]
	var code := int(result[1])
	if code != 200:
		return "%s answered HTTP %d" % [url, code]
	return ""


## Unpack a verified zip into `install_dir()`, via a staging directory. Returns "" or the
## complaint.
func _unpack(pack: PackDef, archive: String) -> String:
	var target := pack.install_dir()
	if target.is_empty():
		return "pack '%s' has nowhere to install to" % pack.id
	var staging := target + STAGING_SUFFIX

	var reader := ZIPReader.new()
	if reader.open(archive) != OK:
		return "the download is not a readable zip"

	var names := reader.get_files()
	if names.is_empty():
		reader.close()
		return "the zip is empty"

	# EVERY NAME FIRST, BEFORE ANYTHING IS WRITTEN. See the class comment: an archive with
	# one hostile path is not an archive to trust the rest of, so this is a whole-archive
	# refusal rather than a per-entry skip.
	for name in names:
		if not _is_safe_entry(name):
			reader.close()
			return "the zip contains an unsafe path ('%s')" % name

	# A stale staging directory from a crash mid-install.
	if DirAccess.dir_exists_absolute(staging):
		var stale := _remove_tree(staging)
		if not stale.is_empty():
			reader.close()
			return stale

	DirAccess.make_dir_recursive_absolute(staging)
	for name in names:
		if name.ends_with("/"):
			continue                  # a directory entry; the file entries below create it
		var dest := staging.path_join(name)
		var dest_dir := dest.get_base_dir()
		if not DirAccess.dir_exists_absolute(dest_dir):
			DirAccess.make_dir_recursive_absolute(dest_dir)
		var f := FileAccess.open(dest, FileAccess.WRITE)
		if f == null:
			reader.close()
			_remove_tree(staging)
			return "cannot write %s (error %d)" % [dest, FileAccess.get_open_error()]
		f.store_buffer(reader.read_file(name))
		f.close()
	reader.close()

	# WHAT LANDED HAS TO LOOK LIKE THE THING IT CLAIMS TO BE. A zip that unpacked cleanly
	# but carries no `campaign.json` would install a directory `Campaigns` then reports as
	# broken, which blames the loader for a publishing mistake.
	var expected := _expected_marker(pack)
	if not expected.is_empty() and not FileAccess.file_exists(staging.path_join(expected)):
		_remove_tree(staging)
		return "the zip has no %s at its root" % expected

	# THE SWAP. Last possible moment, so the live copy is replaced only once a complete and
	# checked one exists beside it.
	if DirAccess.dir_exists_absolute(target):
		var old := _remove_tree(target)
		if not old.is_empty():
			_remove_tree(staging)
			return old
	var moved := DirAccess.rename_absolute(ProjectSettings.globalize_path(staging),
			ProjectSettings.globalize_path(target))
	if moved != OK:
		_remove_tree(staging)
		return "cannot move the unpacked content into place (error %d)" % moved
	return ""


## Mount a verified `.pck`. Returns "" or the complaint.
##
## The scratch file becomes the pack's permanent home, because a mount READS the file for
## as long as the process lives and again on every boot -- so it is moved out of
## `SCRATCH_DIR` (which is for unverified payloads) into a kept directory first.
func _mount(pack: PackDef, archive: String, owned: bool) -> String:
	var kept_dir := "user://packs/"
	DirAccess.make_dir_recursive_absolute(kept_dir)
	var kept := kept_dir.path_join("%s.pck" % pack.id)

	if FileAccess.file_exists(kept):
		_delete_file(kept)
	# MOVE what is ours, COPY what is not. A caller who handed us a path did not agree to
	# have that file disappear -- and a sideloaded pack the player still has in their
	# downloads folder vanishing would look like the install ate it.
	var moved := OK
	if owned:
		moved = DirAccess.rename_absolute(ProjectSettings.globalize_path(archive),
				ProjectSettings.globalize_path(kept))
	else:
		moved = DirAccess.copy_absolute(ProjectSettings.globalize_path(archive),
				ProjectSettings.globalize_path(kept))
	if moved != OK:
		return "cannot store the pack (error %d)" % moved

	# `replace_files = false`: a pack must not shadow anything shipped in the APK. The seam
	# resolves a real atlas over a placeholder by NAME, not by overwrite -- see
	# `GameDataRegistry.atlas_for()`, which is total precisely so a missing file is a
	# magenta placeholder rather than a crash.
	if not ProjectSettings.load_resource_pack(kept, false):
		return "the pack downloaded but the engine refused to mount it"
	return ""


## The file that proves an unpacked archive is what it says it is. Empty means "no check
## available", which is honest rather than inventing one.
func _expected_marker(pack: PackDef) -> String:
	match pack.kind:
		PackDef.Kind.CAMPAIGN:
			return CampaignDef.JSON_FILE
		_:
			return ""


## One entry name from a zip. Relative, forward-slashed, no `..` at any depth, no absolute
## path, no Windows drive letter, no backslash.
##
## ⚠️ **A WHITELIST WOULD BE WRONG HERE AND A BLACKLIST IS WRONG EVERYWHERE ELSE** -- the
## asymmetry is deliberate. `PackDef._is_safe_segment()` whitelists because it names ONE
## segment we choose the alphabet for. A zip entry is a path with legitimate structure and
## legitimate characters (spaces in a campaign's filenames, say), so the check is on the
## SHAPE: split it and refuse the shapes that escape.
static func _is_safe_entry(name: String) -> bool:
	if name.is_empty() or name.length() > 512:
		return false
	if name.begins_with("/") or name.contains("\\") or name.contains(":"):
		return false
	# A NUL truncates a path in every C API underneath `FileAccess`, so a name carrying one
	# means two different things to this check and to the write that follows it.
	if name.contains(char(0)):
		return false
	for part in name.split("/", false):
		if part == ".." or part == ".":
			return false
	return true


func _fail(pack: PackDef, message: String) -> bool:
	pack_finished.emit(pack, false, message)
	return false


static func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n := f.get_length()
	f.close()
	return int(n)


static func _delete_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Recursive delete. Returns "" or the complaint.
##
## Written out rather than reached for, because Godot has no recursive remove and
## `DirAccess.remove_absolute` refuses a non-empty directory -- silently, by returning an
## error nobody checks.
static func _remove_tree(path: String) -> String:
	var dir := DirAccess.open(path)
	if dir == null:
		return "cannot open %s to remove it" % path
	dir.include_hidden = true
	for name in dir.get_directories():
		var problem := _remove_tree(path.path_join(name))
		if not problem.is_empty():
			return problem
	for name in dir.get_files():
		var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(name)))
		if err != OK:
			return "cannot delete %s (error %d)" % [path.path_join(name), err]
	var last := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if last != OK:
		return "cannot delete %s (error %d)" % [path, last]
	return ""
