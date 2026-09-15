## 0.3a's proof: a pack download SURVIVES A DROPPED CONNECTION. EXIT CODE IS THE ANSWER.
##
##     Godot --headless --path game res://dev_preview/preview_resumable_download.tscn
##
## ## WHY THIS IS A PREVIEW AND NOT A TEST
##
## `tests/run_tests.gd` calls each test method with `instance.call(method)` and never awaits,
## so a test cannot wait for a frame -- and `HTTPRequest` needs frames to do anything at all.
## That is the same reason `test_pack_installer.gd` opens by saying the download is not tested
## and cannot be. Everything below the fetch is checked in the suite through
## `install_from_file()`; **a resume is a property of the fetch itself**, so it is checked
## here, where there is a scene tree.
##
## ## WHAT IT DOES NOT NEED, AND THAT IS THE POINT
##
## Not the internet. `LoopbackHttpServer` is a real socket on 127.0.0.1 speaking real HTTP
## and -- the part no live server will do on request -- **it drops the connection part way
## through the body on demand**, which is how `art_base_v1.zip` died at about 3 MB on a good
## wired connection on 2026-09-12. The failure is reproduced rather than waited for.
##
## ## ⚠️ THE FIXTURE IS A CAMPAIGN, WHICH INSTALLS. IT MUST NOT BE ART, WHICH MOUNTS
##
## A mounted pack cannot be un-mounted -- Godot has no `unload_resource_pack()` -- so an
## `art` fixture would land a few hundred KB of test bytes under `res://` for the life of
## the process, shadowing whatever paths it happened to contain. A `campaign` unpacks into
## `user://content/scenarios/`, which can be deleted afterwards and is. The download path
## under test is the same one either way; only the last step differs.
##
## ## WHAT EACH ROW CATCHES THAT THE OTHERS CANNOT
##
##   1. **clean**          -- a whole download over the chunked path. The regression guard:
##                            this is new machinery under an old feature.
##   2. **one drop**       -- a chunk lands, the next dies. The only row that can prove a
##                            RESUME, because a client whose first request dies has nothing
##                            banked and asks for byte 0 again -- which looks identical to
##                            not resuming at all.
##   3. **alternate drops**-- every other request dies. Proves `MAX_CONSECUTIVE_FAILURES`
##                            counts CONSECUTIVE failures: a bad link that still makes
##                            progress must not be given up on.
##   4. **every drop**     -- nothing ever completes. Proves the opposite half: it gives up
##                            after three rather than spinning forever.
##   5. **a fresh installer** -- the `.part` from a dead attempt, resumed by a different
##                            object, which is what a restarted game is. Measured in BYTES
##                            OVER THE WIRE, the only number that tells a resume from a
##                            re-download that happens to end well.
##   6. **a stale part**   -- a `.part` from another version must be discarded, not resumed
##                            into; resuming would buy a checksum failure at the end of a
##                            long download.
##   7. **no ranges**      -- a server that ignores `Range` and answers 200 with the whole
##                            file. Appending that to what we held would make a file of
##                            exactly the right LENGTH out of the wrong bytes.
extends Node

const WORK := "user://preview_resumable"

## Long, ugly and unmistakable -- `test_pack_installer.gd`'s rule. It names a directory under
## `user://content/scenarios/`, where a developer's real content lives.
const FIXTURE_ID := "ZZ_resume_fixture"
const TARGET := "user://content/scenarios/ZZ_resume_fixture"

## Big enough to need several chunks at the size below, small enough that the run is seconds.
const PAYLOAD_BYTES := 240000

## What the installer is driven with, instead of its 4 MB default. The fixture would be a
## single chunk otherwise and the resume would never be exercised -- see `chunk_bytes`.
const TEST_CHUNK := 30000

var _server: LoopbackHttpServer
var _zip: PackedByteArray
var _failures: Array[String] = []


func _ready() -> void:
	_scrub()
	DirAccess.make_dir_recursive_absolute(WORK)
	_zip = _build_fixture_zip()

	_server = LoopbackHttpServer.new()
	add_child(_server)
	_server.body = _zip
	var err := _server.start()
	if err != OK:
		printerr("cannot listen on loopback: %s" % error_string(err))
		get_tree().quit(1)
		return

	print("resumable download preview -- a %d-byte campaign zip in %d-byte chunks, port %d"
			% [_zip.size(), TEST_CHUNK, _server.port()])
	print("sha256 %s\n" % _sha_of(_zip))

	await _clean_download()
	await _one_drop()
	await _alternate_drops()
	await _every_attempt_drops()
	await _a_fresh_installer_resumes()
	await _a_stale_part_is_discarded()
	await _a_server_that_ignores_range()
	await _a_redirect_keeps_the_range()

	_server.stop()
	_scrub()

	if _failures.is_empty():
		print("\nOK -- a dropped connection costs one chunk, not the pack.")
		get_tree().quit(0)
	else:
		printerr("\n%d FAILURE(S):" % _failures.size())
		for f in _failures:
			printerr("  - %s" % f)
		get_tree().quit(1)


# ── the rows ────────────────────────────────────────────────────────────────

func _clean_download() -> void:
	print("--- 1. a clean download")
	var r := await _run({})
	_want(r["ok"], "a clean download must succeed: %s" % r["message"])
	_want(_installed_ok(), "the unpacked campaign is not what was served")
	print("    %d requests, %d bytes over the wire, campaign unpacked"
			% [r["requests"], r["moved"]])


func _one_drop() -> void:
	print("--- 2. one chunk lands, the next connection dies")
	var r := await _run({"cut_after": TEST_CHUNK / 2, "cut_on": [2] as Array[int]})
	_want(r["ok"], "a single drop must not fail the pack: %s" % r["message"])
	_want(_installed_ok(), "the file that survived a drop is not the served file")

	# THE LOAD-BEARING ASSERTION. A client that started again from zero would ALSO end up
	# with the right file -- and would be exactly the bug this card is about. What proves a
	# resume is that some request asked for a byte above zero.
	_want(_max_range() > 0,
			"every request asked for byte 0, so nothing was resumed (ranges: %s)" % _ranges())
	print("    resumed from byte %d; ranges asked for: %s" % [_max_range(), _ranges()])


func _alternate_drops() -> void:
	print("--- 3. every other connection dies, and it still finishes")
	# Requests 2, 4, 6, 8... die. The odd ones land, so the consecutive counter keeps being
	# reset and the download inches forward instead of being given up on.
	var doomed: Array[int] = []
	for i in range(2, 40, 2):
		doomed.append(i)
	var r := await _run({"cut_after": TEST_CHUNK / 2, "cut_on": doomed})
	_want(r["ok"], "a link that drops every other time must still finish: %s" % r["message"])
	_want(_installed_ok(), "the file assembled over many drops is wrong")
	print("    finished in %d requests" % r["requests"])


func _every_attempt_drops() -> void:
	print("--- 4. nothing ever completes, and it gives up rather than spinning")
	# Every response is cut, so no chunk ever lands and no progress is ever made. The honest
	# outcome is a clean failure after MAX_CONSECUTIVE_FAILURES, not an infinite loop.
	var r := await _run({"cut_after": TEST_CHUNK / 2})
	_want(not r["ok"], "a link where nothing completes must fail, not report success")
	_want(r["requests"] <= PackInstaller.MAX_CONSECUTIVE_FAILURES,
			"gave up after %d requests, wanted at most %d"
					% [r["requests"], PackInstaller.MAX_CONSECUTIVE_FAILURES])
	print("    gave up after %d requests: %s" % [r["requests"], r["message"]])


func _a_fresh_installer_resumes() -> void:
	print("--- 5. a .part from a dead attempt, picked up by a FRESH installer")
	# Let two chunks land, then kill every request after them. The attempt dies with real
	# bytes banked -- which is what a player who lost their connection is left holding.
	var doomed: Array[int] = []
	for i in range(3, 40):
		doomed.append(i)
	var first := await _run({"cut_after": TEST_CHUNK / 2, "cut_on": doomed})
	_want(not first["ok"], "the interrupted attempt was supposed to fail")

	var banked := _size(_part_path())
	_want(banked > 0, "the interrupted attempt banked nothing, so there is nothing to resume")

	# A brand new PackInstaller, the way a restarted game would have one, and the part is
	# deliberately NOT scrubbed between the two.
	var second := await _run({"keep_part": true})
	_want(second["ok"], "the resumed download must succeed: %s" % second["message"])
	_want(_installed_ok(), "the resumed file is not the served file")

	# THE NUMBER THAT PROVES IT. A re-download moves the whole pack again; a resume moves
	# only what was missing.
	_want(int(second["moved"]) < _zip.size(),
			"the second run moved %d bytes of a %d-byte pack, so it started again"
					% [second["moved"], _zip.size()])
	print("    banked %d bytes, then moved only %d more (pack is %d)"
			% [banked, second["moved"], _zip.size()])


func _a_stale_part_is_discarded() -> void:
	print("--- 6. a .part belonging to another version is thrown away")
	_scrub_part()
	DirAccess.make_dir_recursive_absolute(PackInstaller.SCRATCH_DIR)

	# Bytes that are not this pack's, with a note claiming an older version.
	var junk := PackedByteArray()
	junk.resize(50000)
	junk.fill(0x5A)
	_write(_part_path(), junk)
	var pack := _pack()
	_write_text(_claim_path(), JSON.stringify({"id": pack.id, "version": pack.version - 1,
			"size": pack.size, "sha256": pack.sha256}))

	var r := await _run({"keep_part": true})
	_want(r["ok"], "a stale part must not break the download: %s" % r["message"])
	_want(_installed_ok(), "a stale part was resumed into and corrupted the pack")
	_want(int(r["moved"]) >= _zip.size(),
			"only %d bytes moved, so the junk was resumed into rather than discarded"
					% r["moved"])
	print("    discarded %d junk bytes and fetched all %d" % [junk.size(), r["moved"]])


func _a_server_that_ignores_range() -> void:
	print("--- 7a. ranges ignored on a pack BIGGER than a chunk: stream it, do not buffer it")
	_seed_valid_part(60000)

	# ⚠️ THE ROW THAT IS ABOUT MEMORY AND NOT ABOUT RESUMING. A chunk's body is held in RAM,
	# which is only safe while the server honours the Range -- one that does not answers with
	# the WHOLE pack, and buffering 236 MB of colour atlases on a phone is not a failed
	# download, it is a dead process. The body limit aborts that response and the installer
	# falls back to streaming the file to disk, which is how it worked before 0.3a.
	var r := await _run({"keep_part": true, "honour_range": false})
	_want(r["ok"], "a server without ranges must still deliver: %s" % r["message"])
	_want(_installed_ok(), "the streamed fallback did not produce the served file")
	print("    fell back to a streamed download and the checksum matched")

	print("--- 7b. ranges ignored on a pack that FITS in one chunk: replace the part inline")
	_seed_valid_part(60000)

	# Here the whole file is inside the body limit, so there is no fallback: the installer
	# sees a 200 where it asked for a range and must throw away what it had. Appending
	# instead would make a file of exactly the right LENGTH out of the wrong bytes -- caught
	# by the checksum, but only after paying for the download twice.
	var small := await _run({"keep_part": true, "honour_range": false, "chunk": _zip.size()})
	_want(small["ok"], "a one-chunk pack without ranges must deliver: %s" % small["message"])
	_want(_installed_ok(),
			"the 200 was appended to the part instead of replacing it: right length, wrong bytes")
	print("    discarded the part and took the 200 whole")


## A `.part` holding real, correctly-claimed bytes, so the installer genuinely tries to
## resume before the row takes ranges away from underneath it.
func _seed_valid_part(bytes: int) -> void:
	_scrub_part()
	DirAccess.make_dir_recursive_absolute(PackInstaller.SCRATCH_DIR)
	var pack := _pack()
	_write(_part_path(), _zip.slice(0, bytes))
	_write_text(_claim_path(), JSON.stringify({"id": pack.id, "version": pack.version,
			"size": pack.size, "sha256": pack.sha256}))


func _a_redirect_keeps_the_range() -> void:
	print("--- 8. the first request is redirected, and the Range survives it")
	# A CDN's ordinary behaviour. What is under test is not the redirect -- `HTTPRequest`
	# follows those on its own -- but whether OUR `Range` header is still attached to the
	# request it makes afterwards. If it is not, a resume silently becomes a download from
	# byte zero that still ends with the right file: correct, and costing exactly what this
	# card exists to stop costing.
	var r := await _run({"redirect_first": 1})
	_want(r["ok"], "a redirected download must succeed: %s" % r["message"])
	_want(_installed_ok(), "the redirected download did not produce the served file")

	var rangeless := 0
	for q in _server.requests:
		if int(q["status"]) != 302 and int(q["range_start"]) < 0:
			rangeless += 1
	_want(rangeless == 0,
			"%d request(s) arrived with no Range header, so the redirect dropped it and "
			% rangeless + "every resume is secretly a fresh download")
	print("    %d requests (one a 302), all carrying a Range" % r["requests"])


# ── driving an install ──────────────────────────────────────────────────────

## One install against the loopback server. Options: `cut_after`, `cut_on`, `honour_range`,
## `keep_part` (do not scrub `<id>.part` first -- the resume rows need what is there).
##
## Returns `ok`, `message`, `requests`, `moved` (payload bytes the server actually wrote).
func _run(options: Dictionary) -> Dictionary:
	_scrub_installed()
	if not bool(options.get("keep_part", false)):
		_scrub_part()

	_server.requests.clear()
	_server.cut_after_bytes = int(options.get("cut_after", 0))
	_server.cut_on_requests = options.get("cut_on", [] as Array[int])
	_server.honour_range = bool(options.get("honour_range", true))
	_server.redirect_first = int(options.get("redirect_first", 0))

	var installer := PackInstaller.new()
	# The whole reason `chunk_bytes` is a field: at 4 MB this fixture is one request.
	installer.chunk_bytes = int(options.get("chunk", TEST_CHUNK))
	add_child(installer)

	# ⚠️ AN ARRAY AND NOT A `String`, BECAUSE A GDSCRIPT LAMBDA CAPTURES BY VALUE. The first
	# version assigned to a captured `message` and every complaint came back empty -- so a
	# failing row would have printed "must succeed: " and named no reason at all. An Array is
	# a reference, so appending to it reaches this scope.
	var said: Array[String] = []
	installer.pack_finished.connect(func(_p: PackDef, _good: bool, msg: String) -> void:
		said.append(msg))

	var ok: bool = await installer.install(_pack(), _index())

	installer.queue_free()
	_server.cut_after_bytes = 0
	_server.cut_on_requests = [] as Array[int]
	_server.honour_range = true
	_server.redirect_first = 0

	return {"ok": ok, "message": "(nothing was emitted)" if said.is_empty() else said[0],
			"requests": _server.requests.size(), "moved": _moved()}


## A manifest entry describing the served zip, pointed at the loopback server.
##
## ⚠️ `PackDef.from_dict` refuses a url that is not https, deliberately, so the url is set on
## the object AFTER the parse rather than through it. What is exercised here is
## `_download()`; `PackDef`'s url rules are checked in the suite, where they belong.
func _pack() -> PackDef:
	var pack := PackDef.from_dict({
		"id": FIXTURE_ID, "kind": "campaign", "version": 3, "required": false,
		"folder": FIXTURE_ID, "title": "Resume fixture",
		"size": _zip.size(), "sha256": _sha_of(_zip),
		"urls": ["https://example.invalid/placeholder.zip"],
	})
	if not pack.problems.is_empty():
		_want(false, "the fixture pack is unusable: %s" % ", ".join(pack.problems))
	pack.urls = ["%s" % _server.url_for("fixture.zip")] as Array[String]
	return pack


## A real campaign zip, built with `ZIPPacker` so what is downloaded is a file the installer
## genuinely has to unpack -- `test_pack_installer.gd`'s argument for the same choice.
##
## The bulk member is LCG noise rather than a pattern, because deflate would turn a
## repeating one into a few hundred bytes and the multi-chunk path would never be reached.
func _build_fixture_zip() -> PackedByteArray:
	var path := WORK.path_join("fixture.zip")
	var packer := ZIPPacker.new()
	packer.open(path)
	packer.start_file("campaign.json")
	packer.write_file(JSON.stringify({
		"name": "Resume fixture", "description": "0.3a", "scenarios": ["scenario_1"],
	}).to_utf8_buffer())
	packer.close_file()
	packer.start_file("scenario_1/scenario.json")
	packer.write_file(JSON.stringify({"name": "One"}).to_utf8_buffer())
	packer.close_file()
	packer.start_file("bulk.bin")
	packer.write_file(_noise(PAYLOAD_BYTES))
	packer.close_file()
	packer.close()

	var f := FileAccess.open(path, FileAccess.READ)
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return bytes


## Did the campaign land, and is the big member byte-for-byte what was served? The installer
## already refuses on a checksum mismatch, so this is the belt to that braces -- it would
## catch a swap that unpacked the wrong staging directory.
func _installed_ok() -> bool:
	if not FileAccess.file_exists(TARGET.path_join("campaign.json")):
		return false
	var f := FileAccess.open(TARGET.path_join("bulk.bin"), FileAccess.READ)
	if f == null:
		return false
	var got := f.get_buffer(f.get_length())
	f.close()
	return got == _noise(PAYLOAD_BYTES)


# ── helpers ─────────────────────────────────────────────────────────────────

func _want(condition: bool, complaint: String) -> void:
	if not condition:
		_failures.append(complaint)


func _moved() -> int:
	var total := 0
	for q in _server.requests:
		total += int(q["sent"])
	return total


func _max_range() -> int:
	var best := 0
	for q in _server.requests:
		best = maxi(best, int(q["range_start"]))
	return best


func _ranges() -> String:
	var out: Array[String] = []
	for q in _server.requests:
		out.append("%d%s" % [int(q["range_start"]), "!" if bool(q["cut"]) else ""])
	return ", ".join(out)


func _index() -> String:
	return WORK.path_join("installed.json")


func _part_path() -> String:
	return PackInstaller.SCRATCH_DIR.path_join("%s%s" % [FIXTURE_ID, PackInstaller.PART_SUFFIX])


func _claim_path() -> String:
	return PackInstaller.SCRATCH_DIR.path_join("%s%s" % [FIXTURE_ID, PackInstaller.CLAIM_SUFFIX])


func _scrub_part() -> void:
	for path in [_part_path(), _claim_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _scrub_installed() -> void:
	for dir in [TARGET, TARGET + PackInstaller.STAGING_SUFFIX]:
		if DirAccess.dir_exists_absolute(dir):
			PackInstaller._remove_tree(dir)
	if FileAccess.file_exists(_index()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_index()))


func _scrub() -> void:
	_scrub_part()
	_scrub_installed()
	if DirAccess.dir_exists_absolute(WORK):
		PackInstaller._remove_tree(WORK)


## Deterministic pseudo-random bytes. An LCG, so the stream does not compress -- a repeating
## pattern would deflate to nothing and the fixture would be one chunk again.
static func _noise(n: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(n)
	var state := 12345
	for i in n:
		state = (state * 1103515245 + 12345) & 0x7FFFFFFF
		out[i] = (state >> 16) & 255
	return out


static func _sha_of(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish().hex_encode()


static func _size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n := int(f.get_length())
	f.close()
	return n


static func _write(path: String, data: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


static func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
