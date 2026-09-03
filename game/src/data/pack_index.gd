## What is installed locally, and at which version (PLAN.md 3.2's *"check local versions
## against the manifest"*). Phase 0.3.
##
## `user://packs_installed.json`, keyed by `PackDef.id`:
##
##     {"format_version": 1, "packs": {"howtoplay": 2, "thedragonborn": 1}}
##
## ## ⚠️ THIS IS A RECORD, NOT A MAXIMUM -- THE OPPOSITE OF `CampaignProgress`
##
## Its sibling file next door is one-way on purpose: progress *"only ever goes up"*, so
## replaying scenario 1 cannot re-lock scenario 2. **This one assigns.** A publisher who
## rolls a pack back from v3 to v2 has decided v3 was wrong, and a client that clamped to
## the highest number it had ever seen would refuse the fix and keep the bad art forever,
## with no way to say so.
##
## The two files sit beside each other and behave differently, which is why this paragraph
## exists: the reflex learned from `CampaignProgress.record_completed()` is wrong here, and
## `maxi()` would look like the careful choice.
##
## ## IT RECORDS WHAT LANDED, WRITTEN AFTER THE FACT
##
## The row goes in **once the install or mount has succeeded**, never before. A version
## written first and installed second would make an interrupted download indistinguishable
## from a finished one -- the client would skip re-fetching a pack that is half on disk.
## `PackInstaller` owns that ordering; this file only refuses to make it easy to get wrong,
## by having no verb that means "about to".
##
## ## EVERY FUNCTION TAKES A `path`
##
## `CampaignProgress`'s lesson, and it cost a false failure the day it was learned: the
## tests must never touch the developer's own installed state. Defaulted to `USER_FILE`, so
## production callers say nothing and a test says everything.
class_name PackIndex
extends RefCounted

const FORMAT_VERSION := 1

const USER_FILE := "user://packs_installed.json"


## Every installed pack as `{id: version}`. An absent, malformed or non-object file reads as
## NOTHING INSTALLED.
##
## That is the safe direction and it is worth saying why: reading a broken index as "empty"
## makes the client re-download and re-verify, which is slow and correct. Reading it as
## "everything is fine" would leave a player stuck with content the game believes it has
## and cannot find.
static func all(path: String = USER_FILE) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("PackIndex: cannot open %s (error %d)" % [path, FileAccess.get_open_error()])
		return {}
	var text := f.get_as_text()
	f.close()

	var j := JSON.new()
	if j.parse(text) != OK:
		push_warning("PackIndex: %s: line %d: %s" % [path, j.get_error_line(), j.get_error_message()])
		return {}
	var parsed: Variant = j.data
	if not parsed is Dictionary:
		push_warning("PackIndex: %s is not a JSON object; treating nothing as installed" % path)
		return {}
	var root: Dictionary = parsed

	var fv := _as_int(root.get("format_version", 0))
	if fv > FORMAT_VERSION:
		# A newer client wrote this. Refusing to READ it would re-download everything;
		# refusing to WRITE it is what `record()` does. So: read what we can understand.
		push_warning("PackIndex: %s is format_version %d and this build knows %d"
				% [path, fv, FORMAT_VERSION])

	var raw: Variant = root.get("packs", {})
	if not raw is Dictionary:
		push_warning("PackIndex: %s has no `packs` object; treating nothing as installed" % path)
		return {}

	var out: Dictionary = {}
	for key in (raw as Dictionary):
		var v: Variant = (raw as Dictionary)[key]
		# A row this class cannot read is DROPPED here and PRESERVED by `record()` --
		# `CampaignProgress` does exactly this, and the argument is the same: a value we
		# cannot interpret must not be reported as a version, and deleting somebody's file
		# content because we did not understand one line of it is the worse mistake.
		if v is int or v is float:
			out[str(key)] = int(v)
	return out


## The installed version of one pack, or 0 for "not installed". Negative and unreadable
## values read as 0, because they come from a file a player can edit.
static func version_of(pack_id: String, path: String = USER_FILE) -> int:
	var v: Variant = all(path).get(pack_id, 0)
	var n := _as_int(v)
	return n if n > 0 else 0


## Is this pack missing, outdated, or already here? The whole of PLAN.md 3.2's *"check
## local versions against the manifest"*, in one place so the boot path and the browser
## cannot disagree about what "needs downloading" means.
static func needs_download(pack: PackDef, path: String = USER_FILE) -> bool:
	return version_of(pack.id, path) < pack.version


static func is_installed(pack_id: String, path: String = USER_FILE) -> bool:
	return version_of(pack_id, path) > 0


## Is any `required` pack missing or outdated? **The boot's whole routing decision** --
## `BootScreen` shows the download screen when this is true and goes straight to the front
## door when it is false.
##
## A static taking both inputs, rather than a method on the screen, so the rule can be
## tested without a `SceneTree`: `BootScreen` cannot call `change_scene_to_file` in the
## suite, which would otherwise leave the one branch that matters unexercised.
##
## A null or empty manifest answers FALSE. An offline device must reach the main menu, not a
## download screen with nothing to download -- PLAN.md 3.2's placeholder rule.
static func any_required_missing(manifest: PackManifest, path: String = USER_FILE) -> bool:
	if manifest == null:
		return false
	for pack in manifest.required_packs():
		if needs_download(pack, path):
			return true
	return false


## Record a pack as installed at `version`. Call this AFTER the install or mount succeeded
## -- see the class comment.
##
## Rows this class cannot interpret are written back untouched, so a file half-written by a
## newer build loses nothing it did not have to.
static func record(pack_id: String, version: int, path: String = USER_FILE) -> bool:
	if pack_id.is_empty():
		push_warning("PackIndex: refusing to record a pack with no id")
		return false
	if version < 1:
		push_warning("PackIndex: refusing to record '%s' at version %d" % [pack_id, version])
		return false
	return _rewrite(path, func(packs: Dictionary) -> void:
		packs[pack_id] = version)


## Forget a pack, for uninstall. PLAN.md 3.3 requires installed content be removable, and a
## row left behind would make the game believe a deleted campaign is still there and skip
## re-downloading it.
static func forget(pack_id: String, path: String = USER_FILE) -> bool:
	return _rewrite(path, func(packs: Dictionary) -> void:
		packs.erase(pack_id))


## Read, mutate, write. One place, because a read-modify-write done twice is done
## differently twice.
static func _rewrite(path: String, mutate: Callable) -> bool:
	var packs: Dictionary = {}

	# Start from the RAW rows rather than from `all()`, so entries this build cannot read
	# survive the round trip. `all()` drops them by design; a writer must not.
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var j := JSON.new()
			if j.parse(f.get_as_text()) == OK and j.data is Dictionary:
				var existing: Variant = (j.data as Dictionary).get("packs", {})
				if existing is Dictionary:
					packs = (existing as Dictionary).duplicate()
			f.close()

	mutate.call(packs)

	var dir := path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		push_warning("PackIndex: cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	out.store_string(JSON.stringify({
		"format_version": FORMAT_VERSION,
		"packs": packs,
	}, "\t"))
	out.close()
	return true


static func _as_int(v: Variant) -> int:
	if v is int or v is float:
		return int(v)
	return 0
