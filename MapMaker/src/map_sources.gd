## Every map the tool can OPEN, and where each one came from (PLAN.md 16.4a).
##
## ## WHY THIS EXISTS RATHER THAN A `FileDialog`
##
## Godot's `FileDialog` browses *files*, and a map is a **directory** — `map.png` plus a
## `map.json` sidecar. So a file browser would either show an author two files per map and ask
## them to pick the right one, or be pointed at directories and happily open any folder on the
## machine. Neither answers the question an author is actually asking, which is *"which of my
## maps do I want"*, and neither can put a name, a size and a player count on a row.
##
## It is also the seam that makes the dialog testable: `discover()` takes a `GameRoot` and
## touches nothing else, so a test can walk a scratch directory rather than the real machine.
##
## ## IT IS `SavedMaps` ON THE OTHER SIDE OF THE FENCE, AND THE SHAPE IS COPIED DELIBERATELY
##
## 16.0 built `game/src/data/saved_maps.gd` to answer the same question for the skirmish
## picker: several roots in priority order, first match wins by folder, one entry per map
## carrying every figure a row needs. This is that design applied one project over — **not
## that code**, because the two disagree about which roots exist and neither can call the other
## across two Godot projects (decision 2). Where they agree, they agree on purpose:
##
##   - **listing never decodes a PNG.** `MapFile.read_header()` reads the sidecar only, so a
##     folder of fifty maps costs fifty small JSON parses rather than fifty 192x192 decodes.
##     The full `load_map()` happens once, when a map is actually chosen.
##   - **therefore a listed map may still fail to open**, which is why `Editor` surfaces
##     `load_map`'s problems instead of treating a row's presence as proof.
##   - **an absent root is silent; an unreadable map in a present root is a warning.** A fresh
##     clone has no `scenarios/` on some layouts and nothing has ever written the player's
##     save directory, so complaining about either would train the reader to ignore the line a
##     real complaint appears on (`Campaigns`' rule).
##
## ## THREE ROOTS, AND THE THIRD IS THE ONE 16.10 ACTUALLY NEEDS
##
## ⚠️ **THE CARD FOR THIS ROW NAMED TWO — repo-root `maps/` and the player's `user://maps/` —
## AND NEITHER OF THEM HOLDS THE FIVE MAPS THIS ROW EXISTS TO REOPEN.** 16.4a's whole
## justification is that *"16.10's whole job is to re-author the five existing How To Play
## maps"*, and those five live in `scenarios/HowToPlay/scenario_1..5/`, beside their
## `scenario.json`. A tool that lists the other two directories would have shipped unable to
## open a single one of them. Same class of correction as 16.2's acceptance turning out to
## belong to 16.0.
##
## So `scenarios/` is walked **one level deeper** than the other two: a scenario map is
## `<campaign>/<scenario>/map.json`, where an authored map is `<map>/map.json`. That is the
## only reason `depth` is in the root table rather than assumed.
##
## ⚠️ **AND THE HAZARD THAT COMES WITH IT: SAVE WRITES BACK IN PLACE.** `MapDocument.save()`
## re-uses the directory a map was opened from, which is exactly what re-authoring means — and
## it means an author who opens shipped campaign content and presses Save has rewritten a
## tracked file. Three things make that acceptable rather than reckless: the round trip is
## lossless for terrain, entities and starts (`dev/author_map.tscn` proves it every run), the
## content is committed so `git` is the undo the tool does not have yet (16.2a), and
## `Editor`'s **Save As** exists precisely so "I opened it to look at it" has a way out that is
## not the Save button. The rule the tool teaches is one sentence: **Open then Save replaces;
## Save As creates.**
class_name MapSources
extends RefCounted

## Where a row came from. Ordered like `roots()`, and the label is what the dialog shows —
## an author choosing between "my map" and "the shipped campaign's map" is making a decision
## about what they are allowed to break.
enum Source { AUTHORED, SCENARIO, PLAYER }

## Repo-root `maps/`, relative to this project. PLAN.md §16 decision 4: what the tool writes.
const AUTHORED_SUBDIR := "../maps"

## Repo-root `scenarios/`. Campaign content, and the source of 16.10's five maps.
const SCENARIOS_SUBDIR := "../scenarios"

## The leaf inside the GAME's user directory. `SavedMaps.SAVE_ROOT` is `user://maps/`, and
## `user://` means something different in each project — see `GameRoot.game_user_dir()`.
const PLAYER_LEAF := "maps"

## Every complaint from the last `discover()`, in the order found.
##
## **NOT PRINTED FROM HERE**, `SavedMaps`' rule: the dialog shows them, because a folder that
## is on disk and missing from the list is the one thing an author cannot diagnose by looking.
var warnings: Array[String] = []


## The directories to search, in priority order: `{path, source, depth}`.
##
## Absent ones are NOT skipped here — `discover()` skips them — so a test can assert the order
## and the derivation with no filesystem at all. Same seam `SavedMaps.roots()` keeps.
func roots(root: GameRoot) -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{"path": _repo_dir(AUTHORED_SUBDIR), "source": Source.AUTHORED, "depth": 1},
		{"path": _repo_dir(SCENARIOS_SUBDIR), "source": Source.SCENARIO, "depth": 2},
	]
	# LAST, AND ONLY WHEN THE GAME PROJECT IS RESOLVED. Its path is derived from the game's
	# project name, so without a game root there is nothing to derive it from -- and a tool
	# with no game root cannot save anyway (`Startup`).
	if root != null and not root.path.is_empty():
		var user_dir := root.game_user_dir()
		if not user_dir.is_empty():
			out.append({"path": user_dir.path_join(PLAYER_LEAF),
					"source": Source.PLAYER, "depth": 1})
	return out


## Every openable map, in root order then alphabetical within a root.
##
## One entry per map: `{name, dir, folder, label, players, size, source}`.
##
## - `name` is the sidecar's, falling back to the folder — see `map_name_in()`.
## - `label` is the path an author recognises: the folder for an authored map,
##   `HowToPlay/scenario_4` for a scenario. **It is not the key** — `dir` is.
## - `players` is what the map can really seat, which is not `starts.size()`; see
##   `players_in()`.
##
## **First match wins by `dir`, not by folder**, and that is the one place this deliberately
## departs from `SavedMaps`. There, a folder name is the identity because a dev override
## SHADOWING an installed copy of the same map is the feature. Here the roots hold different
## things, and two campaigns may perfectly reasonably both contain a `scenario_1` — keying on
## the folder would hide the second one with nothing on screen to explain it.
func discover(root: GameRoot) -> Array[Dictionary]:
	warnings.clear()
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for entry in roots(root):
		for row in maps_in(str(entry["path"]), int(entry["source"]), int(entry["depth"])):
			var key := str(row["dir"])
			if seen.has(key):
				continue
			seen[key] = true
			out.append(row)
	return out


## Every readable map under ONE root, alphabetical by folder.
##
## `depth` is how far down a map directory sits: 1 for `<root>/<map>/map.json`, 2 for
## `<root>/<campaign>/<scenario>/map.json`.
##
## ⚠️ **A DIRECTORY THAT IS A MAP IS NOT WALKED FURTHER**, which is what keeps depth 2 honest:
## a campaign folder holds `campaign.json` and no `map.png`, so the check is "does this level
## hold a map", not "how deep am I". Without that rule a future layout with a map at the top
## of a campaign folder would be listed twice, or not at all.
##
## **Appends to `warnings` and does not clear it**, because `discover()` walks several roots
## and clearing per root would leave only the last one's complaints.
func maps_in(root_path: String, source: int, depth: int = 1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(root_path)
	if dir == null:
		# ABSENT IS NORMAL AND SILENT. Nothing has ever written the player's save directory
		# (the pause-menu Save Map button is parked -- 11.3, the owner's ruling of
		# 2026-09-04), and a checkout without `scenarios/` is somebody's valid layout.
		return out

	var folders := dir.get_directories()
	folders.sort()
	for folder in folders:
		var path := root_path.path_join(folder)
		if MapFile.exists_in(path):
			# `{}` MEANS THE SIDECAR COULD NOT BE READ and `_row` has already said why. Skipped
			# rather than listed: a row with no name, no size and no player count is a row that
			# fails the moment it is pressed, and the warning is what tells the author instead.
			var row := _row(path, folder, source)
			if not row.is_empty():
				out.append(row)
			continue
		if depth > 1:
			for row in maps_in(path, source, depth - 1):
				# RELABELLED WITH THE CAMPAIGN IN FRONT OF IT. `scenario_1` alone is a row
				# nobody can choose between two campaigns; `HowToPlay/scenario_1` is.
				row["label"] = "%s/%s" % [folder, row["label"]]
				out.append(row)
	return out


func _row(path: String, folder: String, source: int) -> Dictionary:
	var problems: Array[String] = []
	var header := MapFile.read_header(path, problems)
	if header.is_empty():
		# WORTH A WARNING, unlike a missing root: a folder holding both files with a sidecar
		# this build cannot read is either a corrupt map or one from a newer format, and both
		# are things the author should be told about rather than have silently vanish from a
		# list they can see on disk. `SavedMaps` draws the same line in the same place.
		for p in problems:
			warnings.append(p)
		return {}
	return {
		"name": map_name_in(header, folder),
		"dir": path,
		"folder": folder,
		"label": folder,
		"players": players_in(header),
		"size": Vector2i(int(header.get("w", 0)), int(header.get("h", 0))),
		"source": source,
	}


## The sidecar's `name`, else `meta.name`, else the folder.
##
## Two places to look because `MapFile.save()` merges its `header` argument into the sidecar's
## TOP level while a `MapData` carries its own `meta` dictionary — so a map saved with
## `{"name": ...}` has it at the top and one whose `MapData.meta` held it has it nested. Both
## are legitimate and neither a picker nor an editor should care which.
##
## **Shared with `MapDocument.open()` rather than written twice**, which is the whole reason it
## is `static` and lives here: the name on the dialog's row and the name in the editor's Name
## field must be the same string, or an author renames a map by opening it.
static func map_name_in(header: Dictionary, folder: String) -> String:
	var top := str(header.get("name", "")).strip_edges()
	if not top.is_empty():
		return top
	var meta: Dictionary = header.get("meta", {}) if header.get("meta") is Dictionary else {}
	var nested := str(meta.get("name", "")).strip_edges()
	return nested if not nested.is_empty() else folder


## How many players this map can actually field.
##
## ⚠️ **NOT `starts.size()`**, and `SavedMaps._players_in()` carries the full argument: a
## player beyond the highest index in `entities` gets no town centre and no units from
## `MapGen.build_from()`, so they open the match owning nothing. The smaller of the two is the
## honest answer.
##
## 📝 **THE SECOND OF THE TWO DUPLICATIONS IN THIS TOOL, AND IT IS THE SAME ONE.**
## `MapDocument.seats()` does this arithmetic on a live `MapData` and says why it is not in
## `format/`: it is an opinion ABOUT a map, so hashing it would break the guard every time the
## lobby's rule changed. This does it on a *header dict*, which is the only thing a listing
## has. **If the three ever disagree, the GAME's is right** — it is the one that refuses to
## start a match.
static func players_in(header: Dictionary) -> int:
	var starts: int = (header.get("starts", []) as Array).size()
	var highest := 0
	for e in header.get("entities", []):
		if e is Dictionary:
			highest = maxi(highest, int((e as Dictionary).get("player", 0)))
	return mini(starts, highest) if starts > 0 and highest > 0 else 0


## What the dialog calls a root, in words an author can act on.
static func source_name(source: int) -> String:
	match source:
		Source.AUTHORED: return "authored"
		Source.SCENARIO: return "campaign"
		Source.PLAYER: return "played"
	return "?"


## A sibling of this Godot project. `simplify_path` resolves the `..` so a path printed in a
## warning is one somebody can paste.
func _repo_dir(subdir: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(subdir).simplify_path()
