## The `scenario.json` beside a map, for the one field the MapMaker owns: `objectives` (16.6).
##
## ## ⛔ WHY THIS EXISTS: A SCENARIO'S CONDITIONS ALREADY HAVE A HOME
##
## The first cut of 16.6 stored conditions in the map's own sidecar, full stop. That is right for
## a standalone map in `maps/` and **wrong for the five shipped campaign maps**, which is the case
## the owner tried first: `scenarios/HowToPlay/scenario_1/` holds `map.json` AND `scenario.json`
## side by side, and the conditions are in the second one.
##
## The panel therefore reported *"no conditions — this map is won by conquest"* for a scenario
## with two win rows in it, and a row added there would have landed in `map.json` where **nothing
## in `game/src` will ever read it** while `scenario.json`'s stayed authoritative. Two sources for
## one fact, which is the failure this whole row exists to prevent, created for the one case that
## matters most.
##
## ⚠️ **SO IT IS A FALLBACK CHAIN AND NOT TWO COPIES**, the shape the owner ruled for KotH's zone
## (*"both — region if authored, generated otherwise"*): a `scenario.json` beside the map wins, a
## map without one parks its conditions in its sidecar until 16.8 promotes it into a scenario.
## They never both apply, the resolution happens once at open, and each alternative fails visibly
## in the other's case.
##
## ## ⚠️ IT REPLACES ONE KEY AND PRESERVES EVERYTHING ELSE, INCLUDING WHAT IT CANNOT READ
##
## A `scenario.json` carries `name`, `description`, `message`, `mode`, `opponents`,
## `starting_age`, `map` — and a `_note` block that is frequently the longest and most valuable
## thing in the file. **None of that is the tool's**, and a writer that rebuilt the file from the
## fields it understands would delete the rest in a save that reported success. That is
## `MapDocument._preserved_header()`'s lesson one level up, with much more to lose.
##
## So: parse the whole file, assign `objectives`, write it back. Godot dictionaries preserve
## insertion order and `JSON.parse` builds in file order, so assigning an existing key leaves it
## where it was and the diff is the objectives array alone.
##
## ## ⛔ AND THE TRAP THAT MAKES A PLAIN ROUND TRIP UNACCEPTABLE ON SHIPPED CONTENT
##
## **JSON HAS ONE NUMBER TYPE AND GODOT PARSES IT AS A FLOAT.** So `"seed": 815101` comes back as
## `815101.0` and goes out as `815101.0`, and `"value": 14` becomes `14.0` — on every number in
## the file, not just the ones that were touched. `16.x-slow-place` found exactly this in the
## map sidecar's preserved `meta` block on 2026-09-08 and flagged it **for 16.10**, whose whole
## job is re-authoring these five files. Nothing breaks (`ScenarioDef` reads everything through
## `int()` and `str()`), but five noisy diffs across shipped campaign content is a real cost paid
## for nothing, and it makes a genuine change impossible to see in a review.
##
## `_ints_restored()` is the fix, and it is narrow on purpose: a float with no fractional part
## becomes an int. **The one thing it would get wrong is a field that genuinely wants `2.0` to be
## a float**, and the scenario schema has none — every number in it is a count, an age, a seed or
## a comparison value. Said out loud rather than assumed, because the day somebody adds a
## multiplier is the day this needs a carve-out.
class_name ScenarioFile
extends RefCounted

const FILE_NAME := "scenario.json"

## The key this class owns. Everything else in the file is read, carried and never touched.
const OBJECTIVES_KEY := "objectives"


## The `scenario.json` beside a map, or `""` when the map is not a scenario's.
##
## **EXISTENCE IS THE WHOLE TEST, AND IT IS DELIBERATELY NOT "IS THIS UNDER `scenarios/`".** A
## path test would be a second opinion about `MapSources.roots()` living in a different file, and
## it would be wrong in both directions: a scenario folder copied into `maps/` still has its
## conditions in its `scenario.json`, and a bare map dropped under `scenarios/` has none.
static func path_beside(map_dir: String) -> String:
	if map_dir.is_empty():
		return ""
	var path := map_dir.path_join(FILE_NAME)
	return path if FileAccess.file_exists(path) else ""


## The whole file as a dictionary, or `{}` with the reason appended.
##
## `JSON.new().parse()` rather than the static `JSON.parse_string()`: authored content is a file a
## person edits by hand, so a malformed one is expected rather than exceptional, and the static
## helper pushes an engine error per failure — `MapFile._parse_sidecar` draws the same line for
## the same reason.
static func read(path: String, out_problems: Array[String]) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		out_problems.append("%s is empty or unreadable" % path)
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		out_problems.append("%s: line %d: %s"
				% [path, json.get_error_line(), json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		out_problems.append("%s is not a JSON object" % path)
		return {}
	return json.data


## The scenario's condition rows, as the author's own records.
##
## ⚠️ **A ROW THIS BUILD CANNOT READ IS KEPT AND REPORTED, NEVER DROPPED** — `MapDocument`'s rule
## for the sidecar, and it matters more here: these are hand-written files under version control,
## and silently discarding a row would mean opening a scenario, saving it, and finding an
## objective gone. Only a non-object entry is dropped, because everything downstream indexes it.
static func objectives_in(d: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = d.get(OBJECTIVES_KEY, [])
	if not raw is Array:
		return out
	for entry in (raw as Array):
		if entry is Dictionary:
			out.append((entry as Dictionary).duplicate())
	return out


## What the scenario says decides it: `"scenario"`, `"last_man_standing"`, or `""` for a file that
## does not say. Read so `MapDocument` can warn about the one combination `ScenarioDef` refuses.
static func mode_in(d: Dictionary) -> String:
	return str(d.get("mode", "")).to_lower()


## Write `objectives` into the file at `path`, leaving every other key exactly as it was.
##
## Returns true when written; the reason goes in `out_problems`. **Never pushes an engine error**:
## a save can fail for ordinary reasons and the caller is a UI that has to say so.
##
## ⚠️ **IT RE-READS THE FILE RATHER THAN WRITING A DICTIONARY IT WAS HANDED AT OPEN TIME.** The
## tool can sit open for an hour and this is shipped content in a repo two agents commit to — so
## the copy read at open may be stale, and writing it back would silently revert somebody else's
## edit to the briefing text. Only the objectives array is this tool's to decide.
static func write_objectives(path: String, objectives: Array[Dictionary],
		out_problems: Array[String]) -> bool:
	var d := read(path, out_problems)
	if d.is_empty():
		if out_problems.is_empty():
			out_problems.append("%s could not be read, so it was not written" % path)
		return false

	# ⚠️ **ASSIGNED RATHER THAN ERASED-AND-ADDED.** Assigning an existing key keeps its POSITION
	# in the dictionary, and Godot preserves insertion order — so `objectives` stays at the bottom
	# of the file where it was and the diff is the array alone. Erasing first would move it to the
	# end, which on scenario 1 means re-ordering a file nobody changed.
	d[OBJECTIVES_KEY] = objectives

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		out_problems.append("could not write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(_ints_restored(d), "  ", false) + "\n")
	f.close()
	return true


## Every integral float in `value`, recursively, back to an int. See the class comment.
##
## **THE RECURSION IS NOT DECORATION**: the numbers that matter are nested two deep
## (`map.seed`, and `value` inside each objective), so a top-level-only pass would leave exactly
## the fields this exists to protect.
static func _ints_restored(value: Variant) -> Variant:
	if value is float:
		var f: float = value
		# `is_equal_approx` is the wrong test here and `f == floor(f)` is the right one: this is
		# asking whether JSON widened an INTEGER, not whether a float is nearly whole. A genuine
		# 2.0000001 must stay a float. The range guard keeps a value too large for an int64 from
		# wrapping — unreachable in this schema and free to defend against.
		if f == floor(f) and absf(f) < 9.0e15:
			return int(f)
		return f
	if value is Array:
		var list: Array = []
		for item in (value as Array):
			list.append(_ints_restored(item))
		return list
	if value is Dictionary:
		var out: Dictionary = {}
		for k in (value as Dictionary):
			out[k] = _ints_restored((value as Dictionary)[k])
		return out
	return value
