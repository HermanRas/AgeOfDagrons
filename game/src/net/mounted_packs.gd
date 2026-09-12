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
static func mount_all(dir: String = KEPT_DIR) -> PackedStringArray:
	var done := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return done
	var d := DirAccess.open(dir)
	if d == null:
		push_warning("MountedPacks: cannot open %s" % dir)
		return done
	var names := d.get_files()
	names.sort()
	for name in names:
		if not _is_pack(name):
			continue
		if mount_one(dir.path_join(name)):
			done.append(dir.path_join(name))
	return done


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
