## Finds the saved maps a player can start a match on (PLAN.md 16.0, and §1.6's
## long-standing "still open" line).
##
## ## WHY THIS EXISTS
##
## `MapFile` could read a map from the day 2.4c landed, and for two days the only caller in
## `game/src` was `ScenarioDef` -- so the ONLY way to play an authored map was to hand-write
## a `scenario.json` beside it and reach it through the campaign screen. That is a fine
## route for campaign content and a useless one for "I made a map, let me play it", which is
## what `MapMaker/README.md` promises and what Phase 16 has to be able to answer by pressing
## PLAY rather than by editing JSON.
##
## ## THE ROOT LIST IS DATA, AND IT IS `Campaigns`' LIST WITH A DIFFERENT LEAF
##
## PLAN.md 3.3 gives content three roots and this is the same shape, deliberately -- a
## fourth root is a line here rather than a rewrite. First match wins **by folder name**, so
## a dev override shadows an installed copy of the same map instead of listing it twice.
##
##   1. the DEV OVERRIDE -- repo-root `maps/`, EDITOR RUNS ONLY. What the MapMaker writes.
##   2. `user://content/maps/` -- maps that arrived in a content pack (0.3). Shareable.
##   3. `user://maps/` -- **the player's own saves.** A SEPARATE directory from the one
##      above, and 11.3 is emphatic about why: installing or replacing authored content must
##      never be able to overwrite somebody's save, and uninstalling it must never delete
##      one.
##
## ⚠️ **ROOT 3 IS LISTED BEFORE ANYTHING WRITES TO IT.** The pause-menu Save Map button is
## parked (11.3, the owner's ruling of 2026-09-04), so today this root is always empty. It
## is here anyway because a picker that knows two of the three directories is a picker
## somebody has to come back and extend, and the cost of the third is one array entry.
##
## ## THE OVERRIDE NEEDS NO CONFIG FILE
##
## `Campaigns`' argument transfers exactly: `maps/` is a sibling of `game/`, which is the
## Godot project, so `res://../maps` finds it on every clone and a fresh checkout needs no
## setup step. `content.local.json` is still read first for anyone whose layout differs --
## the SAME file `Campaigns` reads, under a `maps_root` key, because two local config files
## for one repo layout is one more thing to keep in step.
##
## ⚠️ **THE OVERRIDE IS GATED ON `OS.has_feature("editor")`, and that gate is the whole
## safety argument.** True for editor runs, the headless suite and every `dev_preview`
## scene; false in an exported build -- so a dev path cannot reach a release even if the
## folder ships.
##
## ## LISTING IS CHEAP ON PURPOSE
##
## `discover()` reads `map.json` and **never decodes `map.png`** -- see
## `MapFile.read_header()`. Every figure a row needs (name, size, player count) is in the
## sidecar, so browsing a folder of fifty maps costs fifty small parses rather than fifty
## 192x192 decodes. The full `load_map()` happens once, when a map is actually chosen.
##
## **Therefore a listed map may still fail to load.** `read_header` deliberately does not
## check the PNG, so callers surface `load_map`'s problems rather than treating a row's
## presence as proof.
##
## Plain `RefCounted` and **not an autoload**, on `Campaigns`' precedent and
## `CampaignProgress`'s: §6.1's table is exactly four, and one screen reads this.
class_name SavedMaps
extends RefCounted

## Maps that arrived in a content pack. Installed, not mounted -- see `Campaigns.USER_ROOT`.
const CONTENT_ROOT := "user://content/maps/"

## The player's own saves (11.3). Never written by an install.
const SAVE_ROOT := "user://maps/"

## Optional, gitignored, editor-only, and SHARED WITH `Campaigns`:
## `{"scenarios_root": "...", "maps_root": "D:/somewhere/maps"}`.
const LOCAL_CONFIG := "res://content.local.json"

## Where a row came from, for a picker that wants to say so. Ordered like `roots()`.
enum Source { DEV, CONTENT, SAVE }

## Every complaint from the last `discover()`, in the order found.
##
## NEVER PRINTED FROM HERE, on `Campaigns`' rule: the one that fires on every developer run
## is a shadowed dev override doing its job, and a loader that warned about it would train
## the reader to ignore the line a real complaint appears on.
var warnings: Array[String] = []


## The roots to search, in priority order. Absent ones are NOT skipped here -- `discover()`
## skips them -- so a test can assert the order and the editor gate with no filesystem.
func roots() -> Array[String]:
	var out: Array[String] = []
	if OS.has_feature("editor"):
		var dev := _dev_root()
		if not dev.is_empty():
			out.append(dev)
	out.append(CONTENT_ROOT)
	out.append(SAVE_ROOT)
	return out


## Which `Source` the root at `index` in `roots()` is.
##
## Derived rather than stored beside each path, because the editor gate means `roots()[0]`
## is the dev override in an editor run and the content root in an exported one -- so a
## caller indexing a fixed enum would mislabel every row in a release build.
func source_of_root(index: int) -> Source:
	if OS.has_feature("editor") and not _dev_root().is_empty():
		return [Source.DEV, Source.CONTENT, Source.SAVE][clampi(index, 0, 2)] as Source
	return [Source.CONTENT, Source.SAVE][clampi(index, 0, 1)] as Source


## Every saved map found, in root order then alphabetical by folder within a root.
##
## Alphabetical WITHIN a root rather than in directory order, for `Campaigns`' reason:
## `DirAccess` order is a filesystem detail and a list that reshuffles between runs looks
## broken.
##
## One entry per map: `{name, dir, folder, players, size, source}`.
##
## - `name` is the sidecar's, falling back to the folder. A map authored by hand may have no
##   `name`, and a row labelled "" is a row nobody can pick.
## - `players` is what the map SUPPORTS, and it is the figure `can_start()` gates on -- see
##   `_players_in()` for why it is not simply `starts.size()`.
func discover() -> Array[Dictionary]:
	warnings.clear()
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	var list := roots()

	for index in list.size():
		for entry in maps_in(list[index], source_of_root(index)):
			var folder := str(entry["folder"])
			if seen.has(folder):
				# The dev override shadowing an installed copy. NOT a warning -- it is the
				# override working. Recorded nowhere on purpose: `Campaigns` learned that a
				# line printed on every developer run is a line nobody reads.
				continue
			seen[folder] = true
			out.append(entry)
	return out


## Every readable map directly inside ONE root, alphabetical by folder.
##
## Split out of `discover()` rather than inlined, and the reason is a test: `discover()`
## walks `roots()`, which points at the real machine, so a test of the seat arithmetic and
## the naming would otherwise have to re-implement this loop over a scratch directory --
## and a duplicated loop is a loop that drifts from the one that ships. `Campaigns` has no
## equivalent seam and its tests pay exactly that price.
##
## **Appends to `warnings` and does NOT clear it**, because `discover()` walks several roots
## and clearing per root would leave only the last one's complaints.
func maps_in(root: String, source: Source = Source.SAVE) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(root)
	if dir == null:
		# ABSENT IS NORMAL AND NOT A WARNING: a fresh clone has no `user://maps/` until
		# something saves one, `user://content/maps/` waits on a pack that carries maps, and
		# a machine with no checkout has no dev root. Only a root that exists and cannot be
		# read would be worth saying anything about, and `DirAccess` cannot tell us the
		# difference -- so this stays silent, exactly as `Campaigns` does.
		return out

	var folders := dir.get_directories()
	folders.sort()
	for folder in folders:
		var map_dir := root.path_join(folder)
		var problems: Array[String] = []
		var header := MapFile.read_header(map_dir, problems)
		if header.is_empty():
			# WORTH A WARNING, unlike a missing root: a directory sitting in `maps/` with a
			# sidecar this build cannot read is either a corrupt save or a map from a newer
			# format, and both are things the player should be told about rather than have
			# silently vanish from a list they can see on disk.
			for p in problems:
				warnings.append(p)
			continue

		out.append({
			"name": _name_in(header, folder),
			"dir": map_dir,
			"folder": folder,
			"players": _players_in(header),
			"size": Vector2i(int(header.get("w", 0)), int(header.get("h", 0))),
			"source": source,
		})
	return out


## How many players this map can actually field.
##
## ⚠️ **NOT `starts.size()`, AND THE DIFFERENCE IS THE WHOLE REASON THIS FUNCTION EXISTS.**
## `MapGen.build_from()` gives a player a town centre and villagers **only** by spawning the
## entities the map lists for their index; it never falls back to `_start_origin()` the way
## the debug map does. So a player beyond the highest index in `entities` starts with **no
## town centre and no units** -- alive, owning nothing, and defeated on the first tick the
## win condition looks. `starts` is what the validator measures connectivity between and
## what a preview marks; `entities` is what a player is actually GIVEN.
##
## Taking the smaller of the two is therefore the honest answer: a map with three starts and
## two players' worth of buildings supports two, and a map with two starts whose author
## listed a third player's base supports two, because the third has nowhere the validator
## has ever checked a path to.
static func _players_in(header: Dictionary) -> int:
	var starts: int = (header.get("starts", []) as Array).size()
	var highest := 0
	for e in header.get("entities", []):
		if e is Dictionary:
			highest = maxi(highest, int((e as Dictionary).get("player", 0)))
	return mini(starts, highest) if starts > 0 and highest > 0 else 0


## The sidecar's `name`, else `meta.name`, else the folder.
##
## Two places because `MapFile.save()` merges its `header` argument into the sidecar's TOP
## level while a `MapData` carries its own `meta` dictionary -- so a map saved with
## `{"name": ...}` has it at the top and one whose `MapData.meta` held it has it nested.
## Both are legitimate and a picker should not care which.
static func _name_in(header: Dictionary, folder: String) -> String:
	var top := str(header.get("name", "")).strip_edges()
	if not top.is_empty():
		return top
	var meta: Dictionary = header.get("meta", {}) if header.get("meta") is Dictionary else {}
	var nested := str(meta.get("name", "")).strip_edges()
	return nested if not nested.is_empty() else folder


## Repo-root `maps/`: the configured path if `content.local.json` names one, else the
## sibling of the Godot project. Editor only -- `roots()` owns that gate.
func _dev_root() -> String:
	var configured := _configured_dev_root()
	if not configured.is_empty():
		return configured
	# `res://` globalizes to the project directory (`.../AOD_Mobile/game`), whose sibling is
	# the authored content. `simplify_path` resolves the `..` so a path a warning prints is
	# one somebody can paste.
	return ProjectSettings.globalize_path("res://").path_join("../maps").simplify_path()


func _configured_dev_root() -> String:
	if not FileAccess.file_exists(LOCAL_CONFIG):
		return ""
	var text := FileAccess.get_file_as_string(LOCAL_CONFIG)
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		warnings.append("%s is not a JSON object; ignoring it" % LOCAL_CONFIG)
		return ""
	return str((json.data as Dictionary).get("maps_root", ""))
