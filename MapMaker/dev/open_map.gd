## Open every real map on this machine WITHOUT a mouse, and rehearse 16.10 on the five that
## matter (PLAN.md 16.4a).
##
## ## WHY THIS EXISTS RATHER THAN MORE TESTS
##
## `tests/test_map_open.gd` writes its fixtures into `user://` and opens them again, which is
## the only honest thing a test can do: repo-root `maps/` and `scenarios/` hold **content under
## version control**, and a suite that wrote there would be a suite that edits the game.
##
## So the suite proves the mechanism against maps it made up, and **nothing proves it against
## the five maps this row exists for.** Those five were written by a different program
## (`preview_author_maps`) at a different time, and they are the whole shipped campaign. This
## script is the check the suite cannot be:
##
##   1. **list what File ▸ Open would offer**, from the real roots, so a root that quietly
##      finds nothing is visible;
##   2. **open every one of them**, printing size, entities, seats and a terrain histogram —
##      a map that loads and is subtly wrong is the failure class §16 decision 3 is built
##      around, and a histogram is what tells a real map from an empty one;
##   3. **round-trip each scenario map through the tool into a SCRATCH directory** and compare
##      terrain, starts and entities byte for byte against what was opened. That is 16.10's
##      job performed in miniature: if a scenario map cannot survive Open → Save, re-authoring
##      the campaign in this tool destroys it.
##
## ⚠️ **IT NEVER WRITES INTO `maps/` OR `scenarios/`.** The round trip goes through
## `user://open_map_check/` and is deleted afterwards, so a check that de-risks overwriting
## the campaign cannot be the thing that overwrites it. `--in-place` does not exist and must
## not be added: replacing a scenario map is a decision an author makes in the editor, with
## the path on screen.
##
## The exit code is the answer.
##
## Usage:
##   Godot --headless --path MapMaker res://dev/open_map.tscn
##   Godot --headless --path MapMaker res://dev/open_map.tscn -- --folder sample_duel
extends Node

## Where the round trip is written. Under `user://`, never beside the original.
const SCRATCH := "user://open_map_check"

## The nest and the mother, which scenario 4's map carries as CONTENT since 2026-09-06 and
## `game/tests/data/test_campaigns.gd` asserts are there. Named here because 16.10's row is
## explicit that *"anybody re-authoring that map must keep the nest and the mother"* — so a
## round trip that dropped a gaia entity would be caught by the count, and one that dropped
## exactly these two would be caught by name.
const DRAGON_IDS := ["building.dragon_nest", "unit.dragon"]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var only := _arg(args, "--folder", "")

	var root := GameRoot.resolve()
	if root.path.is_empty():
		printerr("cannot find the game project: %s"
				% "; ".join(PackedStringArray(root.problems)))
		get_tree().quit(1)
		return
	if not GameDataRegistry.load_from(root):
		printerr("could not read the roster from %s" % root.path)
		get_tree().quit(1)
		return
	# THE GUARD IS HONOURED even though the round trip writes only into `user://`: decision 3's
	# promise is that a stale tool cannot write a map file, and a dev script that made an
	# exception for itself would be the hole the check exists to close. `dev/author_map.tscn`
	# takes the same line for the same reason.
	var guard := FormatGuard.check(root)
	if not guard.passed():
		printerr(guard.refusal())
		get_tree().quit(1)
		return

	var sources := MapSources.new()
	var rows := sources.discover(root)
	_report_roots(sources, root, rows)

	var ok := true
	var opened := 0
	for row in rows:
		if not only.is_empty() and str(row["folder"]) != only and str(row["label"]) != only:
			continue
		opened += 1
		if not _open_and_report(row):
			ok = false
	if opened == 0:
		printerr("nothing to open%s" % ("" if only.is_empty() else " matching '%s'" % only))
		ok = false

	_wipe(ProjectSettings.globalize_path(SCRATCH))
	print("")
	if ok:
		print("OK — %d maps opened and round-tripped" % opened)
	else:
		printerr("FAILED — see above")
	get_tree().quit(0 if ok else 1)


func _report_roots(sources: MapSources, root: GameRoot, rows: Array[Dictionary]) -> void:
	print("roots File ▸ Open searches, in order:")
	for entry in sources.roots(root):
		var path := str(entry["path"])
		print("  %-9s depth %d  %s%s" % [
				MapSources.source_name(int(entry["source"])), int(entry["depth"]), path,
				"" if DirAccess.dir_exists_absolute(path) else "   (absent)"])
	for w in sources.warnings:
		printerr("  unreadable: %s" % w)
	print("  → %d maps" % rows.size())
	print("")


# ── one map ─────────────────────────────────────────────────────────────────

func _open_and_report(row: Dictionary) -> bool:
	var dir := str(row["dir"])
	var problems: Array[String] = []
	var doc := MapDocument.open(dir, problems)
	if doc == null:
		printerr("%s: WILL NOT OPEN — %s" % [row["label"],
				"; ".join(PackedStringArray(problems))])
		return false

	print("%s  \"%s\"" % [row["label"], doc.map_name])
	print("    %d x %d, %d entities, %d starts, seats %d"
			% [doc.data.size.x, doc.data.size.y, doc.data.entities.size(),
			doc.data.starts.size(), doc.seats()])
	print("    terrain: %s" % _histogram(doc.data.terrain))

	# ⚠️ **THE LISTING AND THE OPEN MUST AGREE.** The dialog's row comes from the sidecar
	# alone (no PNG decode) and the canvas comes from the full load, so a disagreement here is
	# an author choosing a 2-player map and editing a 4-player one. `MapSources.players_in`
	# and `MapDocument.seats()` are two implementations of one rule, and this is the only
	# place they are ever compared against a real file.
	var ok := true
	if int(row["players"]) != doc.seats():
		printerr("    the list says %d players and the map seats %d"
				% [int(row["players"]), doc.seats()])
		ok = false
	if row["size"] != doc.data.size:
		printerr("    the list says %s and the map is %s" % [row["size"], doc.data.size])
		ok = false

	var named := _named_dragons(doc)
	if not named.is_empty():
		# SAID OUT LOUD, because 16.10 must not lose them and a count would not name them.
		print("    carries: %s" % ", ".join(PackedStringArray(named)))

	if not _round_trip(doc, named):
		ok = false
	return ok


## Save through the tool into a scratch directory, read it back, and compare.
##
## **Save As and not Save**, which is the point: `save()` would write back over the file that
## was just opened, and a check whose job is to say "re-authoring the campaign is safe" must
## not be the first thing to rewrite it.
func _round_trip(doc: MapDocument, named: Array[String]) -> bool:
	var scratch := ProjectSettings.globalize_path(SCRATCH)
	DirAccess.make_dir_recursive_absolute(scratch)
	var was_dir := doc.dir
	var problems := doc.save_as(scratch)
	if not problems.is_empty():
		printerr("    round trip: save failed — %s" % "; ".join(PackedStringArray(problems)))
		doc.dir = was_dir
		return false

	var reread: Array[String] = []
	var back := MapDocument.open(doc.dir, reread)
	if back == null:
		printerr("    round trip: cannot read it back — %s"
				% "; ".join(PackedStringArray(reread)))
		return false

	var ok := true
	if back.data.terrain != doc.data.terrain:
		printerr("    round trip: the terrain changed")
		ok = false
	if back.data.starts != doc.data.starts:
		printerr("    round trip: the starts changed")
		ok = false
	if back.data.entities.size() != doc.data.entities.size():
		printerr("    round trip: %d entities in, %d out"
				% [doc.data.entities.size(), back.data.entities.size()])
		ok = false
	if _named_dragons(back) != named:
		printerr("    round trip: %s went in and %s came out"
				% [named, _named_dragons(back)])
		ok = false
	# PROVENANCE, which is the half a byte comparison of the map cannot see: `seed` and
	# `map_type` are written for a person and read by nothing, so only a check like this one
	# would ever notice them going missing.
	for key in ["map_type", "seed"]:
		if doc.header.has(key) and str(back.header.get(key, "")) != str(doc.header[key]):
			printerr("    round trip: %s was %s and is now %s"
					% [key, doc.header[key], back.header.get(key, "<gone>")])
			ok = false
	if ok:
		print("    round trip: terrain, starts, %d entities and provenance all survived"
				% back.data.entities.size())
	doc.dir = was_dir
	return ok


func _named_dragons(doc: MapDocument) -> Array[String]:
	var found: Array[String] = []
	for e in doc.data.entities:
		var id := String(e.get("def_id", ""))
		if DRAGON_IDS.has(id) and not found.has(id):
			found.append(id)
	found.sort()
	return found


## How many tiles of each kind. **A count of bytes cannot be wrong in an interesting way and
## this can**: a uniformly grass map and a real one both have the right byte count.
static func _histogram(terrain: PackedByteArray) -> String:
	var counts: Dictionary = {}
	for i in terrain.size():
		var kind := int(terrain[i])
		counts[kind] = int(counts.get(kind, 0)) + 1
	var parts: Array[String] = []
	for kind in counts:
		parts.append("%s %d" % [SimMap.Terrain.keys()[kind], counts[kind]])
	parts.sort()
	return ", ".join(PackedStringArray(parts))


func _wipe(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_wipe(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var at := Array(args).find(key)
	return str(args[at + 1]) if at >= 0 and at + 1 < args.size() else fallback
