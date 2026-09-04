## PLAN.md §16 decision 3: **the copies check themselves, because a copy nobody diffs is a
## copy that has drifted.**
##
## MapMaker carries its own `format/` — the files that decide what a map file MEANS — because
## two Godot projects cannot share a `res://`. This reads the originals out of the game
## project as text, hashes them, and **refuses to save** if any has moved on. *A green tool
## that writes a stale format is worse than one that will not start.*
##
## ## WHAT IS CHECKED, AND WHY IT IS SIX FILES AND NOT THREE
##
## PLAN.md §16 decision 2 originally named a *"format-critical trio: `map_data.gd`, `iso.gd`
## and `atlas_entry.gd`, all three pure `RefCounted` maths with no dependencies"*. Every part
## of that sentence turned out to be wrong, and the review of 2026-09-04 replaced it with the
## measured table. What the tool actually needs:
##
##   - `map_data.gd` — the map itself. Calls `SimMap`, `GameDataRegistry`, `BuildingDef`,
##     `ResourceDef`. Not dependency-free.
##   - `map_file.gd` — the save/load code, **which the original list omitted entirely**.
##   - `sim_map.gd` — the `Terrain` enum and `DOMAIN_TERRAIN`, which the two above index.
##     Genuinely pure, so it is copied whole rather than trimmed.
##   - `building_def.gd`, `resource_def.gd` — footprints, which `MapData.footprint_rect_of()`
##     asks the registry for. **Neither is dependency-free either**: both parse their JSON
##     through `GameDefs`.
##   - `game_defs.gd` — `tile_size`, `int_map`, `name_list`, `int_list`. Pure static helpers,
##     and **found only when the project refused to compile**: nothing in decision 2's
##     "no dependencies" claim survived contact, and this was the fourth file it missed.
##     Copied rather than reimplemented, because `tile_size`'s fallback behaviour is what
##     turns `"footprint": []` into `Vector2i.ONE` and a second opinion about that is a
##     second opinion about how big a building is.
##   - `iso.gd` — tile-to-screen, for 16.2's canvas. **Also not dependency-free**: one line
##     reads `SimWorld.SUBTILE`, hence `format/sim_world.gd`.
##
##   - `map_validator.gd` — **the eighth, added 2026-09-04 for 16.4b, and the one that is not
##     about the FORMAT at all.** It is an opinion *about* a map: start-to-start connectivity,
##     resources within reach, overlapping entities and the sea-map rules. That is exactly why
##     `MapDocument.seats()`'s header records pulling this kind of arithmetic in here as
##     **rejected** — *"it is not part of the format, it is an opinion ABOUT a map, and putting
##     it there would mean a hash check failing whenever the lobby's rule changed."*
##
##     ⚠️ **THE OWNER OVERRULED THAT, AND THE TRADE IS WORTH STATING PLAINLY** (2026-09-04:
##     *"re-copying is fine"*). The alternative was a second validator written inside the tool,
##     and **a validator that disagrees with the game's is worse than one that occasionally
##     needs re-copying**: the tool would pass a map the lobby then refuses, which is 16.4b's
##     own failure mode with an extra step. The cost is real and it is a chore, not a risk —
##     when 2.4b's rules change, this guard says so, names the file, and `Boot`'s report says
##     what to copy. A drifted opinion says nothing at all.
##
## `atlas_entry.gd` is deliberately **absent**. It is not format-critical — it is ICON
## critical — it drags `PlaceholderSpec` behind it, and nothing before 16.3's palette needs
## it. It joins `COPIES` on the day the palette does, which is one row in the table below.
##
## ## HASHES FOR COPIES, DECLARATIONS FOR WHAT CANNOT BE COPIED
##
## `format/sim_world.gd` is a one-constant stand-in for a 1,500-line original, so a hash
## would be meaningless. It is checked by pulling the `const SUBTILE := ...` line out of the
## game's source and comparing it. Narrower, and exactly as loud when it breaks.
##
## `format/map_generator.gd` is the second, and it exists for the same reason one level down:
## the verbatim `map_validator.gd` reads `MapGenerator.Type.ARCHIPELAGO`, and the generator
## itself is 1,500 lines of noise fields this tool must never carry — **authoring a map by
## hand and generating one are opposite jobs.** So the `enum Type` line is checked instead.
##
## ⚠️ **LINE ENDINGS ARE NORMALISED BEFORE HASHING, AND THAT IS NOT A DETAIL.** This repo
## checks out with CRLF on Windows (`git` says so on every commit) while these files are
## written with LF, so a byte-for-byte hash would fail on **every** file on **every** machine
## the moment anything touched them. A check that cries wolf is a check somebody disables,
## which would leave the format unguarded — the failure mode decision 3 exists to prevent. So
## CRLF becomes LF and a trailing newline is stripped; anything that changes the CODE still
## changes the hash.
class_name FormatGuard
extends RefCounted

## Verbatim copies: `copy` in this project, `origin` relative to the game project.
const COPIES := [
	{"copy": "res://format/sim_map.gd", "origin": "src/sim/sim_map.gd"},
	{"copy": "res://format/map_data.gd", "origin": "src/sim/map_data.gd"},
	{"copy": "res://format/map_file.gd", "origin": "src/data/map_file.gd"},
	{"copy": "res://format/iso.gd", "origin": "src/view/iso.gd"},
	{"copy": "res://format/building_def.gd", "origin": "src/data/building_def.gd"},
	{"copy": "res://format/resource_def.gd", "origin": "src/data/resource_def.gd"},
	{"copy": "res://format/game_defs.gd", "origin": "src/data/game_defs.gd"},
	{"copy": "res://format/map_validator.gd", "origin": "src/sim/map_validator.gd"},
]

## Single declarations depended on from files too big to copy. `prefix` locates the line in
## the original; `expected` is what our own stand-in says, and the two must match verbatim
## once whitespace is squeezed.
const DECLARATIONS := [
	{
		"origin": "src/sim/sim_world.gd",
		"prefix": "const SUBTILE",
		"expected": "const SUBTILE := 256",
		"used_by": "res://format/sim_world.gd",
	},
	# THE WHOLE ENUM AND NOT JUST `ARCHIPELAGO`, which is the only name `map_validator.gd`
	# spells. A type INSERTED in the middle renumbers every one after it, and the game's own
	# header records what that costs: `meta.type` is a saved int, so it "would silently turn
	# every recorded Desert into a Forest". A check that watched only the name would keep
	# comparing against the wrong number and calling sea maps land maps.
	{
		"origin": "src/sim/map_generator.gd",
		"prefix": "enum Type",
		"expected": "enum Type { RANDOM, ISLAND, RIVER, DESERT, FOREST, ARCHIPELAGO }",
		"used_by": "res://format/map_generator.gd",
	},
]

enum Status { OK, DRIFTED, ORIGIN_MISSING, COPY_MISSING }

## One row per check: `{name, status, detail}`. `name` is the original's relative path, which
## is what a person would go and look at.
var results: Array[Dictionary] = []


## True when every copy matches. **The permission to save**, and the only question callers
## should ask -- see `refusal()` for the sentence to show when it is false.
func passed() -> bool:
	for r in results:
		if int(r["status"]) != int(Status.OK):
			return false
	return true


static func check(root: GameRoot) -> FormatGuard:
	var g := FormatGuard.new()
	for entry in COPIES:
		g.results.append(g._check_copy(root, str(entry["copy"]), str(entry["origin"])))
	for entry in DECLARATIONS:
		g.results.append(g._check_declaration(root, entry))
	return g


## What to put in front of a person, naming every file that is wrong.
##
## NAMES THE FILES, because "the format has changed" is not actionable and this is the one
## message that stands between a stale tool and a corrupted map. Empty when everything
## matches, so it doubles as a check.
func refusal() -> String:
	var bad: Array[String] = []
	for r in results:
		if int(r["status"]) != int(Status.OK):
			bad.append("  %s — %s" % [r["name"], r["detail"]])
	if bad.is_empty():
		return ""
	return ("The game's map format has moved on and this tool's copies have not.\n"
			+ "Saving is disabled until they are brought back into step.\n\n"
			+ "\n".join(PackedStringArray(bad))
			+ "\n\nCopy each file listed above out of the game project, re-run, and check"
			+ " that\nnothing in the tool depended on the old shape.")


## A one-line-per-file report for the console.
func report() -> String:
	var lines: Array[String] = []
	for r in results:
		var mark := "ok  " if int(r["status"]) == int(Status.OK) else "FAIL"
		lines.append("  [%s] %-28s %s" % [mark, r["name"], r["detail"]])
	return "\n".join(PackedStringArray(lines))


func _check_copy(root: GameRoot, copy_path: String, origin: String) -> Dictionary:
	var origin_path := root.source_path(origin)
	if not FileAccess.file_exists(origin_path):
		return _row(origin, Status.ORIGIN_MISSING, "not found at %s" % origin_path)
	if not FileAccess.file_exists(copy_path):
		return _row(origin, Status.COPY_MISSING, "this project has no %s" % copy_path)

	var theirs := _normalised(origin_path)
	var ours := _normalised(copy_path)
	if theirs == ours:
		return _row(origin, Status.OK, "matches %s" % copy_path)
	return _row(origin, Status.DRIFTED,
			"differs from %s (theirs %s, ours %s)"
			% [copy_path, _digest(theirs).substr(0, 12), _digest(ours).substr(0, 12)])


## Pull one declaration out of the original and compare it to what our stand-in says.
##
## Matched on a PREFIX rather than on the whole line so a comment change beside it does not
## fire, and compared with whitespace squeezed so reformatting does not either. What is left
## is the thing that matters: the value.
func _check_declaration(root: GameRoot, entry: Dictionary) -> Dictionary:
	var origin := str(entry["origin"])
	var name := "%s :: %s" % [origin, entry["prefix"]]
	var origin_path := root.source_path(origin)
	if not FileAccess.file_exists(origin_path):
		return _row(name, Status.ORIGIN_MISSING, "not found at %s" % origin_path)

	var prefix := str(entry["prefix"])
	var want := _squeezed(str(entry["expected"]))
	for line in FileAccess.get_file_as_string(origin_path).split("\n"):
		var trimmed := (line as String).strip_edges()
		if not trimmed.begins_with(prefix):
			continue
		# Trailing comment dropped: `const SUBTILE := 256  # sub-tile units` is the same
		# declaration, and a tool that refused to start over a comment would be turned off.
		var code := trimmed.split("#")[0]
		if _squeezed(code) == want:
			return _row(name, Status.OK, "matches %s" % entry["used_by"])
		return _row(name, Status.DRIFTED,
				"the game says `%s`, %s says `%s`"
				% [_squeezed(code), entry["used_by"], want])
	# ABSENT IS A FAILURE, NOT A PASS. A declaration that has been renamed or moved is
	# exactly the change this check exists to catch, and "I could not find it" must never
	# read as "it is fine" -- that is the shape of the facing bug (§12A) in one line.
	return _row(name, Status.DRIFTED, "no line starting `%s` in %s" % [prefix, origin])


func _row(name: String, status: Status, detail: String) -> Dictionary:
	return {"name": name, "status": int(status), "detail": detail}


## File text with line endings normalised and any trailing newline dropped. See the class
## comment: without this, every hash fails on every Windows checkout.
static func _normalised(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	return text.replace("\r\n", "\n").replace("\r", "\n").rstrip("\n")


## Whitespace runs collapsed to one space, for comparing a single declaration.
static func _squeezed(text: String) -> String:
	var out := text.strip_edges()
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out


static func _digest(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()
