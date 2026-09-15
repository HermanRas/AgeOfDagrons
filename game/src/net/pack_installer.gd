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
## ## A DOWNLOAD RESUMES, AND THE SHAPE OF IT WAS DECIDED BY MEASUREMENT (0.3a)
##
## A pack arrives in **bounded chunks** -- `Range: bytes=N-M`, each completed chunk appended
## to `<id>.part` -- rather than in one request. `.part` survives a failure and a restart, so
## a dropped connection costs at most `CHUNK_BYTES` instead of the whole pack.
##
## ⚠️ **THE OBVIOUS CHEAPER DESIGN DOES NOT EXIST, AND THIS FILE USED TO CLAIM IT DID.**
## `_download()` carried the comment *"a leftover `.part` would be appended to, not
## replaced"*, and card 0.3a repeated it as the shape of the fix. **Both were wrong**, and
## `dev_preview/preview_resumable_download.tscn` is what settled it on 4.7.1:
##
##   1. **`set_download_file()` TRUNCATES.** Pointing it at a file holding 500 bytes and
##      fetching 20,000 leaves a 20,000-byte file, not 20,500. So the engine cannot be made
##      to continue a file for us, and the append has to be ours.
##   2. **A DROPPED CONNECTION DELETES ITS OWN PARTIAL FILE.** Not truncates -- removes.
##      After a cut at 4,096 of 20,000 bytes the download file is not there at all. So
##      whatever was in flight when the connection died is lost no matter what we do, and
##      **that is the entire reason the chunks are bounded**: the bound is how much one drop
##      is allowed to cost. A single-request resume would have resumed from wherever the
##      *last completed request* ended, which on a first attempt is zero -- exactly the
##      failure this card exists to fix.
##
## The body of each chunk is taken in memory (`set_download_file("")`) and appended with
## `FileAccess`, so there is no second file on disk to clean up and no byte written twice.
##
## ⚠️ **A `.part` IS CLAIMED, BECAUSE RESUMING INTO THE WRONG FILE IS SILENT.** `<id>.part`
## says nothing about WHICH bytes it is part of, and an `id` outlives its versions -- so a
## leftover from v1 resumed into v2 would download the remainder, fail the checksum, and
## throw the whole thing away. `<id>.part.json` records the sha256, size and version the
## part belongs to and a mismatch discards it BEFORE the fetch rather than after.
##
## What makes a resumed file safe to trust is unchanged and is the reason the order below is
## the order: **size, then hash, on the assembled file.** A resume that went wrong -- a
## server that quietly changed the bytes, a range that was not honoured -- is caught there,
## and `_accept()` deletes the part on any failure, so the next attempt starts clean rather
## than resuming forever into a file that can never verify.
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

## `bytes` counts the WHOLE pack, resumed bytes included, and `total` is the manifest's size.
##
## ⚠️ **THIS USED TO SAY `total` IS 0 UNTIL `Content-Length` ARRIVES.** Since 0.3a the pack
## is fetched in chunks, so `Content-Length` describes a 4 MB piece and a bar drawn from it
## would fill and reset twenty times; the figure now comes from the manifest and is right
## from the first byte. **A consumer must still cope with 0** -- that is the contract a
## progress UI is written against, and it costs one guard.
signal pack_progress(pack: PackDef, bytes: int, total: int)

signal pack_finished(pack: PackDef, ok: bool, message: String)

signal batch_finished(installed: int, failed: int)

## Where a download lands before it is verified. Under `user://` and NOT beside the
## installed content, so a rejected payload is never one rename away from being live.
const SCRATCH_DIR := "user://downloads/"

## Suffix for the half-unpacked copy. Hidden-ish and inside the install root, because the
## final step has to be a rename and a rename cannot cross a filesystem.
const STAGING_SUFFIX := ".installing"

## The half-downloaded pack, and the note saying which bytes it is half of.
const PART_SUFFIX := ".part"
const CLAIM_SUFFIX := ".part.json"

## How much of a pack is asked for in one request -- and therefore **the most that one
## dropped connection can cost**, since the engine throws away the partial body of a request
## that dies (see the class comment).
##
## The figure is a trade between that loss and the number of round trips: 4 MB is 20 requests
## for the 80 MB base art pack and about four and a half minutes of a 125 kbps connection to
## lose, against nine hours for the whole pack today. Smaller would be safer on a bad mobile
## link and is a one-line change; there is no reason to tune it until somebody measures one.
const CHUNK_BYTES := 4 * 1024 * 1024

## ⚠️ **THE CEILING ON WHAT ONE RESPONSE MAY BUFFER, AND IT IS A CRASH GUARD.**
##
## A chunk's body is taken in MEMORY, which is safe only for as long as the server honours
## the `Range` -- a cache or proxy that ignores it answers `200` with the **whole pack**, and
## buffering 236 MB of colour atlases on a phone is not a download that fails, it is a
## process that dies. Twice the chunk is enough slack for any honest answer to a 4 MB range
## and far below anything that could hurt; a body over it aborts the request, which
## `_download()` recognises and answers by falling back to streaming the file to disk in one
## piece, exactly the way this class worked before 0.3a.
const BODY_LIMIT_FACTOR := 2

## Consecutive failed chunks before the pack is given up on. **Consecutive** is the load-
## bearing word: any chunk that lands resets it, so a long download over a flaky link retries
## forever as long as it is still making progress, while a dead server costs three attempts
## and not an infinite loop.
const MAX_CONSECUTIVE_FAILURES := 3

## The chunk size this installer actually uses. A field rather than the constant so a check
## can turn it down and drive a small fixture through the multi-chunk path -- otherwise
## every affordable fixture is one chunk and the resume is never exercised at all.
## Nothing in the game sets it; `CHUNK_BYTES` is the shipping value.
var chunk_bytes := CHUNK_BYTES

## The manifest is small and blocks the front door, so it gets a short leash. A DOWNLOAD
## gets none (see `_download`): a 400 MB pack on a phone legitimately takes minutes, and a
## timeout that fires mid-download would look exactly like a broken server.
const MANIFEST_TIMEOUT_SECONDS := 15.0

var _http: HTTPRequest
var _active: PackDef = null
var _cancelled := false

## Bytes already on disk when the current chunk started. Progress is reported against the
## WHOLE pack, so the bar does not restart at zero on every chunk.
var _part_base := 0

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


## ⚠️ PROGRESS IS THE WHOLE PACK'S, NOT THE CHUNK'S, and the total now comes from the
## MANIFEST rather than from `Content-Length`. Both follow from chunking: `get_body_size()`
## is the size of the 4 MB piece in flight, so a bar drawn from it would fill and reset
## twenty times over one download. `pack.size` is known before the first byte arrives, which
## also retires the divide-by-zero this signal's comment warns about -- `total` is 0 only if
## a caller hands us a pack with no size, which `PackDef` refuses.
func _process(_delta: float) -> void:
	if _active == null:
		return
	var got := _http.get_downloaded_bytes()
	if got < 0:
		got = 0
	pack_progress.emit(_active, _part_base + got, maxi(_active.size, 0))


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
	# One `HTTPRequest` is shared with the downloads, and a chunk leaves a body limit on it.
	# Cleared rather than inherited: the manifest's behaviour must not depend on whether a
	# pack happened to be fetched first.
	_http.body_size_limit = -1

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
	var scratch := SCRATCH_DIR.path_join("%s%s" % [pack.id, PART_SUFFIX])
	var claim := SCRATCH_DIR.path_join("%s%s" % [pack.id, CLAIM_SUFFIX])

	var problem := await _download(pack, scratch, claim)
	if not problem.is_empty():
		# ⚠️ **THE PART AND ITS CLAIM ARE KEPT ON PURPOSE.** This is the whole of 0.3a: a
		# failed download leaves exactly as much progress on disk as it made, so the retry
		# -- from DOWNLOAD MORE, or on the next boot -- starts from there. `_accept()`'s
		# failure paths are what clean up, because those are the ones that mean the bytes
		# can never be right.
		return _fail(pack, problem)

	var ok := _accept(pack, scratch, index_path, true)
	# The claim outlives neither outcome: `_accept` has either consumed the part (unpacked
	# it, or moved it to `user://packs/`) or deleted it as unusable.
	_delete_file(claim)
	return ok


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


## Fetch `pack` into `scratch`, continuing whatever a previous attempt left there. Returns ""
## on success, or the complaint. See the class comment for why this is chunked.
##
## The urls are tried in turn as chunks fail, rather than one url being exhausted before the
## next is reached: a mirror that dies half way through is a reason to ask a different
## mirror for the NEXT chunk, not a reason to start the pack again.
func _download(pack: PackDef, scratch: String, claim: String) -> String:
	if _in_flight:
		return "a download is already in progress"
	if pack.urls.is_empty():
		return "no urls"

	var have := _resume_point(pack, scratch, claim)
	if have >= pack.size:
		# Already complete on disk -- an attempt that died between the last byte and the
		# verify. Nothing to fetch; `_accept()` is the judge of whether it is any good.
		return ""
	if have > 0:
		print("PackInstaller: resuming '%s' at %d of %d bytes" % [pack.id, have, pack.size])
	_write_claim(pack, claim)

	var attempt := 0
	var failures := 0
	var last_error := ""
	while have < pack.size:
		if _cancelled:
			return "cancelled"

		var url: String = pack.urls[attempt % pack.urls.size()]
		attempt += 1
		var want := mini(have + maxi(chunk_bytes, 1), pack.size)
		_part_base = have
		var piece := await _fetch_chunk(pack, url, have, want - 1)

		if not str(piece["error"]).is_empty():
			# A cancel makes the request in flight fail, so the error it produces would
			# otherwise be reported as the reason -- "did not answer (result 2)" for a
			# download the player stopped on purpose.
			if _cancelled:
				return "cancelled"
			# The server ignored the Range and started sending the whole pack, so the body
			# ran past what a chunk may buffer. Chunking is impossible against it; stream
			# the file instead of retrying a request that will always be too big.
			if int(piece["result"]) == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
				return await _download_whole(pack, url, scratch)
			last_error = str(piece["error"])
			failures += 1
			if failures >= MAX_CONSECUTIVE_FAILURES:
				return last_error
			continue

		var code := int(piece["code"])
		var body: PackedByteArray = piece["body"]

		# 416: the server says our part is already at or past the end of the file. Nothing
		# more to fetch, and the size check in `_accept()` is what decides whether that is
		# the finished pack or a stale part that lied about its claim.
		if code == 416:
			break

		# 200 to a ranged request means the server ignored the Range and sent the WHOLE file.
		# Appending that to what we had would make a file of plausible length out of the
		# wrong bytes, so the part is replaced outright. Caches and proxies really do this.
		if code == 200 and have > 0:
			push_warning("PackInstaller: %s ignored Range; restarting '%s' from zero"
					% [url, pack.id])
			_delete_file(scratch)
			have = 0
			_part_base = 0

		if body.is_empty():
			# A 206 that carried nothing. Counted as a failure rather than looped on, because
			# the alternative is a tight loop asking for a byte that never comes.
			last_error = "%s sent an empty range for '%s'" % [url, pack.id]
			failures += 1
			if failures >= MAX_CONSECUTIVE_FAILURES:
				return last_error
			continue

		var wrote := _append_bytes(scratch, body)
		if not wrote.is_empty():
			return wrote                  # a disk fault is not something a retry fixes
		have += body.size()
		failures = 0

		# A server sending more than the manifest describes is stopped here rather than at
		# the checksum, so a wrong or hostile length cannot fill the device first.
		if have > pack.size:
			return "the download is larger than the manifest says (%d of %d bytes)" \
					% [have, pack.size]

	return ""


## One ranged request, body kept in memory. Never throws; the complaint is in the result.
##
## Keys: `error` ("" on success), `code` (the HTTP status, 0 if there never was one), `body`.
func _fetch_chunk(pack: PackDef, url: String, first: int, last: int) -> Dictionary:
	# NO TIMEOUT on a payload -- see MANIFEST_TIMEOUT_SECONDS. Progress is on screen and
	# `cancel()` is the player's escape.
	_http.timeout = 0.0
	_http.set_download_file("")           # in memory; the chunk is bounded by `chunk_bytes`
	_http.body_size_limit = maxi(chunk_bytes, 1) * BODY_LIMIT_FACTOR

	var err := _http.request(url, PackedStringArray(["Range: bytes=%d-%d" % [first, last]]))
	if err != OK:
		return {"error": "cannot reach %s (error %d)" % [url, err], "code": 0,
				"result": -1, "body": PackedByteArray()}

	_in_flight = true
	_active = pack
	set_process(true)
	var result: Array = await _http.request_completed
	_active = null
	set_process(false)
	_in_flight = false

	var code := int(result[1])
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"error": "%s did not answer (result %d)" % [url, int(result[0])], "code": code,
				"result": int(result[0]), "body": PackedByteArray()}
	if code != 200 and code != 206 and code != 416:
		return {"error": "%s answered HTTP %d" % [url, code], "code": code,
				"result": int(result[0]), "body": PackedByteArray()}
	return {"error": "", "code": code, "result": int(result[0]),
			"body": result[3] as PackedByteArray}


## The pre-0.3a path: one request, streamed straight to disk, no resume. Kept for the one
## server that makes chunking impossible -- see `BODY_LIMIT_FACTOR`.
##
## ⚠️ **THIS OVERWRITES THE PART, AND MUST.** `set_download_file` truncates (measured), so
## there is no half-file to protect here: the server has already told us it will not serve a
## range, which means starting again is the only thing it can do.
func _download_whole(pack: PackDef, url: String, scratch: String) -> String:
	push_warning("PackInstaller: %s will not serve ranges; '%s' cannot be resumed"
			% [url, pack.id])
	_delete_file(scratch)
	_http.timeout = 0.0
	_http.body_size_limit = -1
	_http.set_download_file(scratch)

	var err := _http.request(url)
	if err != OK:
		return "cannot reach %s (error %d)" % [url, err]

	_in_flight = true
	_active = pack
	_part_base = 0
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


## How many bytes of `pack` are already on disk and may be built on. 0 means start clean, and
## anything that cannot be PROVEN to belong to this pack is deleted rather than trusted.
func _resume_point(pack: PackDef, scratch: String, claim: String) -> int:
	var have := _file_size(scratch)
	if have <= 0:
		_discard_part(scratch, claim)
		return 0
	if not _claim_matches(pack, claim):
		# A part from an earlier version of the same id, or one whose note is missing. Both
		# are unresumable for the same reason: nothing on disk says these bytes are this
		# pack's, so continuing would buy a checksum failure at the end of a long download.
		_discard_part(scratch, claim)
		return 0
	if have > pack.size:
		_discard_part(scratch, claim)
		return 0
	return have


## Write the note that says which bytes `<id>.part` is part of.
func _write_claim(pack: PackDef, claim: String) -> void:
	var f := FileAccess.open(claim, FileAccess.WRITE)
	if f == null:
		# Not fatal: the cost of losing the claim is a part that cannot be resumed next time,
		# which is exactly where this feature started.
		push_warning("PackInstaller: cannot write %s; this download will not be resumable"
				% claim)
		return
	f.store_string(JSON.stringify({
		"id": pack.id, "version": pack.version, "size": pack.size, "sha256": pack.sha256,
	}))
	f.close()


## Does the note beside the part describe THIS pack? Anything unreadable, unparseable or
## disagreeing is a no -- a missing claim is not a reason to guess.
func _claim_matches(pack: PackDef, claim: String) -> bool:
	if not FileAccess.file_exists(claim):
		return false
	var f := FileAccess.open(claim, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var raw: Variant = JSON.parse_string(text)
	if not raw is Dictionary:
		return false
	var d: Dictionary = raw
	# `sha256` is the real identity; `size` and `version` are checked too so a republished
	# pack that kept its checksum by accident still cannot be confused for another version.
	return str(d.get("sha256", "")).to_lower() == pack.sha256 \
			and int(d.get("size", -1)) == pack.size \
			and int(d.get("version", -1)) == pack.version


func _discard_part(scratch: String, claim: String) -> void:
	_delete_file(scratch)
	_delete_file(claim)


## Append `data` to `path`, creating it if this is the first chunk. Returns "" or the
## complaint.
##
## `READ_WRITE` and then `seek_end()`, because `WRITE` truncates -- which is the same engine
## behaviour that made this whole feature necessary, one layer down.
static func _append_bytes(path: String, data: PackedByteArray) -> String:
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE
	var f := FileAccess.open(path, mode)
	if f == null:
		return "cannot write %s (error %d)" % [path, FileAccess.get_open_error()]
	f.seek_end()
	f.store_buffer(data)
	f.close()
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


## Mount a verified pack. Returns "" or the complaint.
##
## The scratch file becomes the pack's permanent home, because a mount READS the file for
## as long as the process lives and again on every boot -- so it is moved out of
## `SCRATCH_DIR` (which is for unverified payloads) into a kept directory first.
##
## ⚠️ **"AND AGAIN ON EVERY BOOT" WAS NOT TRUE OF ANYTHING UNTIL 2026-09-12.** This function
## was the only `load_resource_pack()` call in the project, so a mount lasted exactly one
## process while `PackIndex` recorded the pack as installed forever -- art that vanished on
## the first restart and was never re-fetched. `MountedPacks.mount_all()`, from
## `GameDataRegistry._ready()`, is the boot half; its header has the full account. Nothing
## could have found it before an art pack existed, because `campaign` and `map` packs do not
## mount.
##
## ⚠️ **THE EXTENSION IS THE SOURCE'S, NOT `.pck`.** It was hardcoded `%s.pck` and the art
## pack is a **zip** (the owner's call, and the engine takes either). A zip named `.pck`
## still mounts -- `load_resource_pack` sniffs the container rather than trusting the name --
## so this is not a bug that was fixed but a lie that was removed: `user://packs/` is a
## directory somebody will one day list while diagnosing a device.
func _mount(pack: PackDef, archive: String, owned: bool) -> String:
	var kept_dir := MountedPacks.KEPT_DIR
	DirAccess.make_dir_recursive_absolute(kept_dir)
	var kept := kept_dir.path_join("%s%s" % [pack.id, _container_suffix(pack, archive)])

	# EVERY suffix, not just the one about to be written. An upgrade that changes container --
	# `art_base.pck` replaced by `art_base.zip` -- would otherwise leave the old file behind,
	# and `MountedPacks.mount_all()` mounts whatever it finds: the previous version of the art
	# would be mounted at every boot alongside the new one, first-wins, silently.
	for suffix in MountedPacks.SUFFIXES:
		_delete_file(kept_dir.path_join("%s%s" % [pack.id, suffix]))
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

	# ⚠️ REPLACING A PACK THAT IS ALREADY MOUNTED IS A SUCCESS, NOT A REFUSAL. Godot has no
	# `unload_resource_pack()`, so a second version of the same pack downloaded in one session
	# cannot take effect until a restart -- the bytes are on disk and `mount_all()` will find
	# them next boot. Treating it as a failure would leave `PackIndex` un-recorded and the
	# client re-downloading the pack on every visit to the browser, forever.
	if MountedPacks.is_mounted(kept):
		push_warning("PackInstaller: '%s' is already mounted; the new version takes effect"
				% pack.id + " on the next start")
		return ""

	# `replace_files = false` lives in `MountedPacks.mount_one()` now -- ONE call site for the
	# engine call, shared with the boot-time mount, so the two cannot disagree about whether a
	# pack may shadow the APK.
	if not MountedPacks.mount_one(kept):
		return "the pack downloaded but the engine refused to mount it"

	# AND THEN MAKE IT VISIBLE. A mount adds files under `res://`; it does not tell the asset
	# seam to look again, and `GameDataRegistry` caches a resolved entry per skin forever.
	# Without this the player finishes an 85 MB download, plays a match, sees the same
	# placeholders, and it comes right only after restarting the game.
	MountedPacks.refresh_seam()
	return ""


## `.zip` or `.pck`, from whichever of the two names actually carries one.
##
## The downloaded payload is `<id>.part`, so the container is named by the URL; a sideloaded
## file (`install_from_file`) names itself. Neither is trusted beyond the two words we
## publish -- anything else keeps `.pck`, because the checksum has already passed and the
## ENGINE is the judge of the format, not the filename.
func _container_suffix(pack: PackDef, archive: String) -> String:
	var candidates := PackedStringArray([archive])
	candidates.append_array(pack.urls)
	for candidate in candidates:
		var suffix := "." + candidate.get_file().get_extension().to_lower()
		if MountedPacks.SUFFIXES.has(suffix):
			return suffix
	return ".pck"


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
	# ⚠️ **THERE IS DELIBERATELY NO NUL CHECK HERE, AND THERE USED TO BE A BROKEN ONE.**
	#
	# This line was `if name.contains(char(0)): return false`, on the argument that a NUL
	# truncates a path in every C API underneath `FileAccess`. The argument is sound and the
	# code was wrong twice over. Owner-reported 2026-09-07 as an error on EVERY editor
	# startup, and both halves came out of chasing it:
	#
	#   1. **IT PRINTED AN ENGINE ERROR AT COMPILE TIME.** `char(0)` is a constant
	#      expression, so GDScript folds it while compiling THIS FILE -- and building that
	#      string is what complains:
	#          Unicode parsing error, some characters were replaced with <?> (U+FFFD):
	#          Unexpected NUL character
	#      Nothing was running an install. The message named no file and pointed at nothing
	#      a reader could find; it took a line-bisect of the compile to land here.
	#
	#   2. **AND IT WAS NEVER CHECKING FOR A NUL.** `String.chr(0)` cannot return one. It
	#      returns U+FFFD -- code point 65533, the replacement character -- which is what
	#      that error is telling you. So the needle was a REPLACEMENT CHARACTER, and the
	#      check refused any entry name carrying one (an old zip with CP437 names, say)
	#      while catching exactly none of what it was written for.
	#
	# ⚠️ **AND A NUL CANNOT REACH THIS FUNCTION IN THE FIRST PLACE.** `ZIPReader` hands out
	# entry names as `String`s, and Godot's UTF-8 decode TRUNCATES at a NUL:
	# `PackedByteArray([97, 0, 98]).get_string_from_utf8()` is `"a"`, length 1, not three
	# characters with a hole in the middle. A GDScript `String` cannot hold code point 0, so
	# a scan for one -- `unicode_at(i) == 0`, which was the first fix -- is dead code that
	# reads like a live rule.
	#
	# NOTHING IS LOST BY DROPPING IT: truncation makes a name SHORTER, and none of the shapes
	# below become reachable by cutting characters off the end. `../` is still `../`.
	# `test_a_replacement_character_in_a_name_is_not_a_reason_to_refuse_it` pins the removal.
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
##
## ⚠️ **A READ-ONLY DIRECTORY CANNOT BE REMOVED ON WINDOWS**, and that is not a theoretical
## case here: this whole repo lives on Google Drive, which sets the read-only attribute on
## EVERY directory in the tree, so any copy of `scenarios/` made with a tool that preserves
## attributes arrives read-only. `RemoveDirectory` then fails with ACCESS DENIED on a
## directory that is completely empty -- so the FILES of an uninstalled pack go and the
## FOLDERS stay, which is exactly the leftover that made `Campaigns.discover()` warn about
## a campaign nobody had installed. `_cleared()` is the one line that stops it recurring.
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
		var err := DirAccess.remove_absolute(_cleared(path.path_join(name)))
		if err != OK:
			return "cannot delete %s (error %d)" % [path.path_join(name), err]
	var last := DirAccess.remove_absolute(_cleared(path))
	if last != OK:
		return "cannot delete %s (error %d)" % [path, last]
	return ""


## The globalized path, with any read-only attribute taken off it first. Returns the path
## either way: a platform that cannot clear the attribute still gets its delete attempted,
## and the error it returns is the honest one.
static func _cleared(path: String) -> String:
	var global := ProjectSettings.globalize_path(path)
	FileAccess.set_read_only_attribute(global, false)
	return global
