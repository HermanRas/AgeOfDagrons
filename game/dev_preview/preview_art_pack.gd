extends Node

## Does the ART PACK actually carry the art, and does the game know how to open it?
## Phase 0.3's missing half (PLAN.md 3.2). **THE EXIT CODE IS THE ANSWER.**
##
##     godot --headless --path game res://dev_preview/preview_art_pack.tscn
##     godot --headless --path game res://dev_preview/preview_art_pack.tscn -- --pack <path>
##
## ## ⛔ THE HARD PART IS THAT THIS WORKSTATION CANNOT FAIL THE OBVIOUS TEST
##
## `game/assets/atlases/` is staged here, so `res://` already answers for every page and a
## mounted pack is never reached (`replace_files = false` -- see `MountedPacks`). **A preview
## that mounted the pack and then asked the seam to draw something would pass without the
## pack existing at all.** That is §5's rule about a check blind to the fault it is for, and
## it is the whole reason this file is shaped the way it is.
##
## So nothing here asks "did it draw". Three questions that a staged tree cannot answer for:
##
##   1. **COVERAGE.** Every path `GameDataRegistry` can ask for, across every visual id x age
##      x colour, checked against the zip's own member list read with `ZIPReader`. The wanted
##      set comes from `atlas_path_for()` -- the SEAM -- and the packer computes its set from
##      visuals.json in Python. Two independent derivations of one answer; if they ever
##      disagree, the pack ships art nothing renders and misses art everything asks for.
##   2. **SHAPE.** Member names are `res://`-relative with no scheme, no leading slash and no
##      `..`, because that is what decides where a mount lands them -- and `PackInstaller`
##      would refuse the pack on arrival otherwise.
##   3. **DECODE.** Pages go through `AtlasEntry.page_texture()`, the one function that opens
##      them now, and come back as textures with sizes the atlas agrees with.
##
## What this CANNOT see, said out loud: whether a phone with no staged tree renders the
## mounted pack. Nothing on a developer machine can -- the check for that is an APK.

## Where `tools/build_packs.py` writes. ⚠️ **NOT A `res://` PATH, AND IT CANNOT BE ONE** --
## Godot refuses `res://../`, so the first version of this file found no packs and reported
## the build as missing. `Campaigns._dev_root()`'s route is the one that works: globalize
## `res://` to the project directory and walk up to its sibling, which is the repo.
const _DOWNLOADS_REL := "../web/server/app/downloads"

var _problems: Array[String] = []
var _notes: Array[String] = []


func _ready() -> void:
	print("=== art pack check ===\n")

	var packs := _pack_paths()
	if packs.is_empty():
		_fail("no art pack found. Build one: python tools/build_packs.py")
		_finish()
		return

	# Every member of every art pack, pooled. The two packs are halves of one answer --
	# `base` carries the untinted bakes and `colours` the tints -- so a path is "covered"
	# if EITHER holds it. Checking them separately would report every tint as missing from
	# base, which is correct and useless.
	var members := {}
	for path in packs:
		var names := _members_of(path)
		if names.is_empty():
			_fail("%s has no members (is it a zip?)" % path.get_file())
			continue
		print("  %-24s %6d members  %s" % [path.get_file(), names.size(),
				String.humanize_size(_size_of(path))])
		for name in names:
			members[name] = path.get_file()
	print("")

	_check_shape(members)
	_check_coverage(members)
	_check_decode()
	_check_mounting(packs)
	_check_seam()
	_finish()


## 2. SHAPE -- what a mount will do with these names.
func _check_shape(members: Dictionary) -> void:
	var bad := 0
	for name in members:
		var s := str(name)
		# The same refusals `PackInstaller._is_safe_entry()` makes, asserted at BUILD time
		# rather than discovered on a player's phone. A pack we publish that our own
		# installer would reject is the cheapest possible failure to catch.
		if s.begins_with("/") or s.begins_with("res://") or s.contains("\\") \
				or s.contains(":") or ".." in s.split("/"):
			if bad < 5:
				_fail("member name is not installable: '%s'" % s)
			bad += 1
		elif not s.begins_with("assets/atlases/"):
			if bad < 5:
				_fail("member outside assets/atlases/: '%s'" % s)
			bad += 1
	if bad > 5:
		_fail("... and %d more badly shaped member names" % (bad - 5))
	print("shape:     %d member name(s), %s" % [members.size(),
			"all installable" if bad == 0 else "%d BAD" % bad])


## 1. COVERAGE -- the seam's own question, asked of the pack.
func _check_coverage(members: Dictionary) -> void:
	var wanted := 0
	var missing: Array[String] = []
	var tints_absent := 0

	for visual_id in GameDataRegistry.visual_ids():
		# age 0 is "no preference" and takes the base atlas; 1..N are the skins. Both are
		# asked for because `_atlas_path_for_skin` composes them independently and a
		# building resolves through the age branch on every redraw.
		for age in range(0, GameDataRegistry.age_count() + 1):
			var untinted := GameDataRegistry.atlas_path_for(visual_id, age)
			if untinted.is_empty():
				continue
			wanted += 1
			if not _covered(members, untinted):
				missing.append("%s age %d -> %s" % [visual_id, age, untinted])

			for colour in range(GameDataRegistry.colour_count()):
				var tinted := GameDataRegistry.atlas_path_for(visual_id, age, colour)
				if tinted == untinted:
					# ⚠️ NOT A GAP. `_atlas_path_for_skin` returns the UNTINTED path when
					# the entry carries no `colours` flag or the tint is not staged, and
					# that fallback is exactly what makes the colours pack optional. An
					# equal path here means "this skin has no tint", not "the tint is
					# missing from the pack".
					tints_absent += 1
					continue
				wanted += 1
				if not _covered(members, tinted):
					missing.append("%s age %d colour %d -> %s"
							% [visual_id, age, colour, tinted])

	print("coverage:  %d path(s) the seam can ask for, %d absent tint(s) (fallback, fine)"
			% [wanted, tints_absent])
	if missing.is_empty():
		print("           every one of them is in a pack")
		return
	for m in missing.slice(0, 8):
		_fail("the seam can ask for a path no pack carries: %s" % m)
	if missing.size() > 8:
		_fail("... and %d more uncovered path(s)" % (missing.size() - 8))


## Is that `res://` path -- and every page it names -- inside a pack?
func _covered(members: Dictionary, res_path: String) -> bool:
	var name := res_path.trim_prefix("res://")
	if not members.has(name):
		return false
	# AND ITS PAGES. An atlas JSON with no pages beside it is the failure that would draw
	# nothing while every path check passed -- the JSON parses, so `_resolve` takes the
	# atlas branch rather than the placeholder one and the unit is simply invisible.
	var dir := name.get_base_dir()
	for page in _pages_of(res_path):
		if not members.has(dir.path_join(page)):
			return false
	return true


func _pages_of(res_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not FileAccess.file_exists(res_path):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(res_path))
	if not parsed is Dictionary:
		return out
	for page in (parsed as Dictionary).get("pages", []):
		out.append(str(page))
	return out


## 3. DECODE -- the route every page takes now that `load()` cannot open one.
func _check_decode() -> void:
	var tried := 0
	var ok := 0
	for visual_id in GameDataRegistry.visual_ids():
		if tried >= 12:
			break
		var entry := GameDataRegistry.atlas_for(visual_id)
		if entry.is_placeholder or entry.pages.is_empty():
			continue
		tried += 1
		var tex := entry.texture(0)
		if tex == null:
			_fail("%s: page 0 did not decode (%s)" % [visual_id, entry.pages[0]])
			continue
		if tex.get_width() <= 0 or tex.get_height() <= 0:
			_fail("%s: page 0 decoded to %dx%d" % [visual_id, tex.get_width(), tex.get_height()])
			continue
		ok += 1
	print("decode:    %d of %d sampled page(s) became a texture" % [ok, tried])
	if tried == 0:
		# Not a pass. A clean checkout has no staged atlases, so every entry is a
		# placeholder and this check silently measures nothing -- §6's `== 0` rule.
		_note("no real atlas was resolvable, so DECODE checked nothing."
				+ " That is a clean checkout (game/assets/atlases/ is gitignored)")


## Mount them, and say what the engine did with them.
func _check_mounting(packs: PackedStringArray) -> void:
	for path in packs:
		# ⚠️ ALREADY-MOUNTED IS NOT A REFUSAL, and under `--main-pack` it is the NORMAL
		# case: `GameDataRegistry._ready()` sweeps `user://packs/` before this runs, so a
		# pack the player has downloaded is up before the preview asks. Conflating the two
		# would fail the one configuration that actually proves anything.
		if MountedPacks.is_mounted(path):
			continue
		if not MountedPacks.mount_one(path):
			_fail("the engine refused to mount %s" % path.get_file())
	var mounted := MountedPacks.mounted()
	print("mount:     %d pack(s) mounted" % mounted.size())
	for m in mounted:
		print("           %s" % m)
	# ⚠️ AND THIS PROVES LESS THAN IT LOOKS LIKE IT DOES, which is why it says so. `res://`
	# wins over a mounted pack, and the staged tree is `res://` -- so on this machine the
	# mount is real and the files it added are unreachable behind the ones already there.
	if _staged_tree_present():
		_note("the staged tree exists here, so the mounted copies are shadowed by it."
				+ " Only a build with assets/atlases/ excluded exercises the pack for real")


## 4. THE SEAM, after mounting: how many ids resolve to real art rather than a placeholder.
##
## ⚠️ **THIS IS THE ONE SECTION THAT MEANS SOMETHING DIFFERENT DEPENDING ON HOW IT IS RUN,
## AND THAT IS THE POINT OF IT.**
##
##   - `--path game`, here, with the staged tree: every id is real because `res://` answers.
##     It proves nothing about the pack and says so.
##   - `--main-pack <an exported pck>`, built with `assets/atlases/` excluded: `res://` has
##     NO atlases, so every id that comes back real came out of the mounted zip. **That is
##     the end-to-end proof**, and it is the only configuration on a developer machine that
##     has one, short of installing an APK.
##
## So the number is printed either way and judged against what is on disk. A run with no
## staged tree and no mounted pack is a clean checkout and is allowed to be all placeholder.
func _check_seam() -> void:
	MountedPacks.refresh_seam()
	var real := 0
	var placeholder := 0
	for visual_id in GameDataRegistry.visual_ids():
		if GameDataRegistry.atlas_for(visual_id).is_placeholder:
			placeholder += 1
		else:
			real += 1

	print("seam:      %d id(s) resolve to real art, %d to a placeholder" % [real, placeholder])
	if _staged_tree_present():
		print("           (staged tree present -- this says nothing about the pack)")
		return
	if real == 0:
		_fail("no staged tree AND nothing resolved from the mounted pack."
				+ " The pack is not reaching the seam")
		return
	print("           ⇒ NO STAGED TREE: all %d came out of the mounted pack." % real)
	if placeholder > 0:
		_note("%d id(s) still resolve to a placeholder with the pack mounted."
				% placeholder + " Declared with no atlas, or an atlas no pack carries")


## Is the STAGED tree here -- the real `game/assets/atlases/` that shadows a mounted pack?
##
## ⛔ **`DirAccess.dir_exists_absolute("res://assets/atlases")` CANNOT ANSWER THIS, AND IT IS
## THE FIRST THING ANYBODY WOULD REACH FOR.** It was, and it was wrong in the one run that
## mattered: **mounting the pack CREATES that directory** in the virtual filesystem, so the
## test is true whenever a pack is up, which is always by the time this is asked. The
## `--main-pack` run reported *"staged tree present -- this says nothing about the pack"*
## while proving exactly the opposite, and would have gone on reporting it forever.
##
## The signal that actually separates them is **`.import` sidecars**. A staged page is a real
## file that Godot imported, so `vis.x_0.png.import` sits beside it; a packed page was zipped
## by Python and no Godot ever saw it, so the pack contains no `.import` at all (and the
## export excludes them with everything else under `assets/atlases/`). It is the same fact
## `AtlasEntry.page_texture()` is built around, read from the other end.
func _staged_tree_present() -> bool:
	var d := DirAccess.open("res://assets/atlases")
	if d == null:
		return false
	for name in d.get_files():
		if name.ends_with(".import"):
			return true
	return false


func _finish() -> void:
	print("")
	for n in _notes:
		print("NOTE: %s" % n)
	if _problems.is_empty():
		print("\nOK -- the packs carry everything the seam can ask for.")
		get_tree().quit(0)
		return
	print("\n%d PROBLEM(S):" % _problems.size())
	for p in _problems:
		print("  - %s" % p)
	get_tree().quit(1)


## The art packs to check: `--pack <path>` if given, else every `art_*.zip` built into
## `web/server/app/downloads/`. Highest version per id, because the directory keeps the old
## ones and a stale v1 beside a live v2 would be checked as though both shipped.
func _pack_paths() -> PackedStringArray:
	var args := OS.get_cmdline_user_args()
	var named := PackedStringArray()
	for i in args.size():
		if args[i] == "--pack" and i + 1 < args.size():
			named.append(args[i + 1])          # repeatable: the packs are halves of one set
	if not named.is_empty():
		return named

	# ⚠️ **`user://packs/` IS CHECKED TOO, AND IT IS THE ONLY ONE THAT WORKS UNDER
	# `--main-pack`.** Globalizing `res://` gives the pck's own directory in an exported
	# run, so the repo's `downloads/` is unreachable from the one configuration that
	# actually proves the pack is being read. It is also simply where a device keeps them.
	var downloads := _downloads_dir()
	if not DirAccess.dir_exists_absolute(downloads):
		return _installed_packs()
	var best := {}
	var d := DirAccess.open(downloads)
	if d == null:
		return PackedStringArray()
	for name in d.get_files():
		if not name.begins_with("art_") or not name.ends_with(".zip"):
			continue
		var stem := name.get_basename()
		var version := int(stem.rsplit("_v", true, 1)[-1])
		var id := stem.rsplit("_v", true, 1)[0]
		if not best.has(id) or best[id]["v"] < version:
			best[id] = {"v": version, "name": name}
	var out := PackedStringArray()
	for id in best:
		out.append(downloads.path_join(best[id]["name"]))
	out.sort()
	if out.is_empty():
		return _installed_packs()
	return out


## What is actually installed on this machine -- `MountedPacks.KEPT_DIR`. No version in the
## filename here: `PackInstaller` keeps one file per pack id, so whatever is there is current.
func _installed_packs() -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(MountedPacks.KEPT_DIR)
	if d == null:
		return out
	for name in d.get_files():
		if MountedPacks._is_pack(name):
			out.append(MountedPacks.KEPT_DIR.path_join(name))
	out.sort()
	return out


func _downloads_dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join(_DOWNLOADS_REL).simplify_path()


func _members_of(path: String) -> PackedStringArray:
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return PackedStringArray()
	var names := reader.get_files()
	reader.close()
	return names


static func _size_of(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return int(n)


func _fail(message: String) -> void:
	_problems.append(message)


func _note(message: String) -> void:
	_notes.append(message)
