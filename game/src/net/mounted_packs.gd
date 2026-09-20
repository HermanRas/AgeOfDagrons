## Mounts the packs already sitting in `user://packs/`, at every startup (PLAN.md 3.2).
##
## ## ⛔ WHY THIS FILE EXISTS: A MOUNT DID NOT SURVIVE A RESTART, AND NOTHING COULD SEE IT
##
## `ProjectSettings.load_resource_pack()` was called in exactly one place --
## `PackInstaller._mount()`, at INSTALL time -- from 0.3 (2026-09-03) until this landed
## (2026-09-12). That code's own comment says a mounted pack *"reads it for the file for the
## life of the process and on every boot after"*, and the second half of that sentence was
## true of nothing: a mount lasts exactly one process.
##
## ⚠️ **AND THE SECOND HALF IS WHAT MAKES IT UNRECOVERABLE RATHER THAN MERELY WRONG.**
## `PackIndex` records the install the moment it succeeds, and `needs_download()` is the only
## question the boot sequence asks. So after one restart the art is not mounted, the index
## says it is installed, and **nothing will ever fetch it again**. The player is on
## placeholders permanently, having downloaded 85 MB, with no button anywhere that retries.
##
## Nothing could have caught it before now: `campaign` and `map` packs are INSTALLED into
## `user://content/` and read off disk, so the only two kinds that have ever shipped do not
## mount at all. The bug was reachable only by the first art pack.
##
## ## THE ORDER, AND WHY IT IS `GameDataRegistry._ready()`
##
## `res://` wins over a mounted pack (`replace_files = false`, `PackInstaller._mount`'s rule),
## so mounting is additive and cannot shadow anything in the APK. But `GameDataRegistry`
## resolves atlas paths with `FileAccess.file_exists()` -- `_atlas_path_for_skin` asks that of
## every tinted path -- so a pack mounted after `load_all()` is a pack the seam has already
## decided is absent. It is the FIRST autoload for this reason and mounts before it reads.
##
## ## ON A DEVELOPER'S MACHINE THIS DOES ALMOST NOTHING, WHICH IS CORRECT
##
## The staged tree is in `res://assets/atlases/`, so every page resolves there and the pack's
## copy is never reached. That is the additive rule doing its job, and it means a workstation
## and a handset run the same code over different sources rather than different code.
class_name MountedPacks
extends RefCounted

## Where `PackInstaller._mount()` keeps a verified pack. Not `SCRATCH_DIR`, which is for
## payloads that have not been checked yet.
const KEPT_DIR := "user://packs/"

## What counts as a pack file here. **Both, and `.zip` is the one we publish** -- the art
## pack is a plain zip built by `tools/build_packs.py` in Python, because a `.pck` is Godot's
## own container and would need a Godot export step to produce (the owner's call, 2026-09-12:
## *"if pck is just a zip, rather leave it zip"*). `load_resource_pack()` takes either, which
## is measured rather than assumed -- see `AtlasEntry.page_texture()` for the four readings.
## `.pck` stays in the list so a pack built the other way still mounts.
const SUFFIXES := [".zip", ".pck"]

## Absolute paths mounted in THIS process. **A guard, not a log:** mounting the same file
## twice is not an error and not free, and `load_all(force = true)` is a thing that happens.
static var _mounted: Dictionary = {}


## Mount every pack in `dir`. Returns what it mounted THIS call, in the order it mounted
## them. Missing directory is the normal first-run state and is silent.
##
## **Sorted, so the order is the filename's and not the filesystem's.** Two packs cannot
## currently collide -- `replace_files` is false throughout, so the first copy of a path wins
## and `res://` beats both -- but an order that varies between two devices is the kind of
## thing that is fine until the day it is not.
##
## ## ⛔ ONE VERSION PER PACK ID, THE NEWEST, AND THE REST ARE SWEPT
##
## Kept packs are named `<id>.v<n>.<suffix>` since 2026-09-20 (see `PackInstaller._mount`,
## which explains why the version had to get into the filename). A directory can therefore
## hold `base.v2.zip` beside `base.v3.zip` -- the old one is deliberately left on disk while
## it is mounted, because deleting it under a live mount is what broke the art on a phone.
##
## **Boot is the one moment it is safe to tidy up**, because nothing is mounted yet: this
## function mounts the highest version of each id and deletes every lower one. Mounting both
## would be worse than either -- `replace_files = false` means the first copy of a path wins,
## so a v2 sorted ahead of v3 would silently serve the OLD art out of a directory that
## contains the new.
static func mount_all(dir: String = KEPT_DIR) -> PackedStringArray:
	var done := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return done
	var d := DirAccess.open(dir)
	if d == null:
		push_warning("MountedPacks: cannot open %s" % dir)
		return done
	var plan := plan_mounts(d.get_files())
	var chosen: Array = plan["mount"]
	var superseded: Array = plan["superseded"]

	var mounted_ids := {}
	for name in chosen:
		if mount_one(dir.path_join(name)):
			done.append(dir.path_join(name))
			mounted_ids[pack_id_of(name)] = true

	# ⛔ **ONLY SWEEP BEHIND A PACK THAT ACTUALLY MOUNTED.** A corrupt or truncated v3 that the
	# engine refuses is a bad state; deleting the working v2 behind it turns that into a device
	# with NO art and nothing on disk to fall back to, and `PackIndex` already records v3 as
	# installed, so nothing would re-fetch it either. Keeping the old file costs 80 MB and
	# leaves the next boot a second chance.
	#
	# AFTER the mounts and never before: a sweep that ran first would be deleting files this
	# call is about to read, which is the bug this whole scheme exists to stop -- one process
	# earlier, and therefore harder to see.
	for name in superseded:
		if not mounted_ids.has(pack_id_of(name)):
			continue
		var path := dir.path_join(name)
		if is_mounted(path):
			continue                  # cannot happen at boot; cheap insurance if it ever can
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return done


## Which of the files in a kept directory to mount, and which are superseded.
##
## ⛔ **PURE, AND SPLIT OUT FOR EXACTLY THAT REASON.** `mount_all()` cannot be tested — it
## mounts, and a mount is irreversible for the life of the process, so the suite may never
## call it. **This is the half that decides what happens**, and it is the half a mistake
## would hide in: pick the wrong file and a device silently serves the OLD art out of a
## directory holding the new; mark the wrong one superseded and the sweep deletes the pack
## that works. Both are invisible until somebody looks at a phone.
##
## Returns `{"mount": [names], "superseded": [names]}`, both sorted, so the order is the
## filename's rather than the filesystem's or a Dictionary's insertion order.
static func plan_mounts(names: PackedStringArray) -> Dictionary:
	var sorted := PackedStringArray(names)
	sorted.sort()

	# pack id -> the best filename seen for it, and the version that made it best.
	var best := {}
	var superseded: Array[String] = []
	for name in sorted:
		if not _is_pack(name):
			continue
		var id := pack_id_of(name)
		var version := pack_version_of(name)
		if not best.has(id):
			best[id] = {"name": name, "version": version}
			continue
		if version > int((best[id] as Dictionary)["version"]):
			superseded.append(String((best[id] as Dictionary)["name"]))
			best[id] = {"name": name, "version": version}
		else:
			superseded.append(name)

	var chosen: Array[String] = []
	for id in best:
		chosen.append(String((best[id] as Dictionary)["name"]))
	chosen.sort()
	superseded.sort()
	return {"mount": chosen, "superseded": superseded}


## What a kept pack is called on disk. **The one writer, beside its two readers.**
##
## ⚠️ **IT IS HERE AND NOT IN `PackInstaller` BECAUSE THE WRITER AND THE PARSERS HAVE TO
## AGREE, AND ALMOST NOTHING ELSE ABOUT MOUNTING CAN BE TESTED.** `load_resource_pack()` is
## irreversible, so no test may mount a real pack and `PackInstaller._mount()` is exercised by
## nothing in the suite -- which is exactly where the bug that prompted this scheme lived
## until a phone found it. A name built in one file and taken apart in another, with no test
## able to see either, is the same shape of hole. Round-tripped by `test_mounted_packs`.
static func kept_name(id: String, version: int, suffix: String) -> String:
	return "%s.v%d%s" % [id, version, suffix]


## The pack id a kept filename belongs to -- `base.v3.zip` -> `base`, `base.zip` -> `base`.
##
## ⚠️ **THE UNVERSIONED FORM IS NOT LEGACY CRUFT, IT IS WHAT IS ON EVERY DEVICE TODAY.** Packs
## installed before 2026-09-20 are `<id>.<suffix>` with no version in the name at all, and
## they must keep mounting -- a player whose art stopped working because the naming scheme
## changed under them would be a worse bug than the one that caused the change.
static func pack_id_of(file_name: String) -> String:
	var base := file_name
	for suffix in SUFFIXES:
		if base.ends_with(suffix):
			base = base.substr(0, base.length() - suffix.length())
			break
	var mark := base.rfind(".v")
	if mark <= 0:
		return base
	if not base.substr(mark + 2).is_valid_int():
		return base                   # an id that happens to contain ".v", e.g. "my.van"
	return base.substr(0, mark)


## The version in a kept filename, or 0 when there is none.
##
## **0 SORTS BELOW EVERY REAL VERSION, WHICH IS THE POINT.** An unversioned `base.zip` from
## before this scheme is superseded by the first versioned pack that arrives, rather than
## competing with it on a name comparison.
static func pack_version_of(file_name: String) -> int:
	var base := file_name
	for suffix in SUFFIXES:
		if base.ends_with(suffix):
			base = base.substr(0, base.length() - suffix.length())
			break
	var mark := base.rfind(".v")
	if mark <= 0:
		return 0
	var tail := base.substr(mark + 2)
	return int(tail) if tail.is_valid_int() else 0


## One pack. `false` means it was already mounted, is not there, or the engine refused it.
##
## `replace_files = false`: a pack must never shadow what shipped in the APK. The seam
## resolves a real atlas over a placeholder BY NAME (`GameDataRegistry.atlas_for` is total),
## so a pack adds files rather than overwriting them.
static func mount_one(path: String) -> bool:
	if path.is_empty() or _mounted.has(path):
		return false
	if not FileAccess.file_exists(path):
		return false
	if not ProjectSettings.load_resource_pack(path, false):
		# A warning and not an error: a refused pack means placeholders, which PLAN.md 3.2
		# makes an explicitly supported state rather than a failure.
		push_warning("MountedPacks: the engine refused to mount %s" % path)
		return false
	_mounted[path] = true
	return true


## Has THIS process already mounted that file? The one thing `mount_one()`'s `false` cannot
## say on its own, and the two callers want opposite things from it: the boot sweep is happy
## to skip, while an installer replacing a live pack must report success (Godot cannot
## un-mount, so the new bytes wait for a restart) rather than a refusal that would leave the
## install unrecorded and re-downloading forever.
static func is_mounted(path: String) -> bool:
	return _mounted.has(path)


## What is mounted in this process, sorted. For the debug overlay and for
## `preview_art_pack`, which is the only thing that can say the art actually arrived.
static func mounted() -> PackedStringArray:
	var out := PackedStringArray(_mounted.keys())
	out.sort()
	return out


## Re-read the asset seam after a pack arrives MID-SESSION.
##
## ⚠️ **A MOUNT ALONE CHANGES NOTHING ON SCREEN, AND THAT IS A SECOND SILENT HALF.**
## `GameDataRegistry` caches a resolved `AtlasEntry` per skin and never drops one, so every
## id asked for before the download is pinned to the placeholder it resolved to then. The
## player finishes a download, returns to the menu, starts a match, and sees exactly what
## they saw before -- until they restart the game, at which point it works. A bug that a
## restart fixes is a bug nobody can report.
##
## Two clears, because there are two caches and they are in different files: the registry's
## resolved entries, and `AtlasEntry`'s decoded pages.
static func refresh_seam() -> void:
	AtlasEntry.forget_pages()
	GameDataRegistry.load_all(true)


static func _is_pack(name: String) -> bool:
	for suffix in SUFFIXES:
		if name.ends_with(suffix):
			return true
	return false
