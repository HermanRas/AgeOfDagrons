## Author a map WITHOUT a mouse, so the round trip can be checked by two commands
## (PLAN.md 16.2).
##
## ## WHY THIS EXISTS
##
## 16.2's claim is *paint → save → open it in the game → play it*, and the middle two steps
## are the ones a screenshot cannot judge. This drives the real `MapDocument` and the real
## `StartLayout` — the same objects the editor's buttons drive — writes the result into
## repo-root `maps/`, and reads it back before claiming anything. Then the GAME's
## `preview_saved_map --folder <name>` plays it:
##
##     Godot --headless --path MapMaker res://dev/author_map.tscn
##     Godot --path game res://dev_preview/preview_saved_map.tscn -- --folder river_demo
##
## **Two processes and two projects, which is the point.** Nothing inside one of them can
## prove the contract between them, and PLAN.md §16 decision 2 is that the FILE is the
## contract rather than the code.
##
## ## IT PAINTS SOMETHING RECOGNISABLE ON PURPOSE
##
## A uniformly grass map round-trips perfectly and proves almost nothing: every terrain byte
## is 0, so a loader that dropped the channel entirely would pass. A river, banks and a
## rocky ridge use five of the seven kinds, are asymmetric, and are **visible** — so the
## owner opening it in the game sees the shape the tool drew rather than a green field they
## have to take on trust.
##
## Usage:
##   Godot --headless --path MapMaker res://dev/author_map.tscn
##       [-- --name "River Demo"] [--size 96] [--force]
extends Node

const DEFAULT_NAME := "River Demo"
const DEFAULT_SIZE := 96

## Where the map goes. PLAN.md §16 decision 4: repo-root `maps/` and nothing else.
const MAPS_SUBDIR := "../maps"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var map_name := _arg(args, "--name", DEFAULT_NAME)
	var side := int(_arg(args, "--size", str(DEFAULT_SIZE)))
	var force := args.has("--force")

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

	# ⚠️ THE GUARD IS HONOURED HERE TOO, and that is not ceremony: this script writes a file,
	# and decision 3's whole promise is that a stale tool cannot write one. A dev script that
	# bypassed the check would be the hole the check exists to close.
	var guard := FormatGuard.check(root)
	if not guard.passed():
		printerr(guard.refusal())
		get_tree().quit(1)
		return

	var maps_dir := ProjectSettings.globalize_path("res://").path_join(MAPS_SUBDIR).simplify_path()
	var doc := MapDocument.create(Vector2i(side, side), map_name)
	var target := maps_dir.path_join(doc.slug())
	if MapFile.exists_in(target) and not force:
		# REFUSES TO OVERWRITE, `preview_author_maps`' rule on the game side: an authored map
		# is content under version control, and a silent re-roll would replace something
		# somebody may have balanced a scenario against.
		print("keeping the existing %s — pass --force to replace it" % target)
		get_tree().quit(0)
		return

	_paint(doc)
	_place_starts(doc)

	var problems := doc.save(maps_dir)
	if not problems.is_empty():
		printerr("save failed: %s" % "; ".join(PackedStringArray(problems)))
		get_tree().quit(1)
		return
	print("wrote %s" % doc.dir)

	get_tree().quit(0 if _verify(doc) else 1)


# ── the map ─────────────────────────────────────────────────────────────────

## A river down the middle with sandy banks, a rocky ridge and two forests.
##
## Every stroke goes through `MapDocument.paint()` — the same call the canvas makes — so this
## exercises the editor's real mutation path and not a shortcut into `MapData`.
func _paint(doc: MapDocument) -> void:
	var side := doc.data.size.x
	var mid := side / 2
	for y in range(doc.data.size.y):
		# A river that WANDERS, so the map is not mirror-symmetric: a symmetric map cannot
		# tell a correct save from one that transposed x and y.
		var drift := int(round(sin(float(y) / 9.0) * 5.0))
		var centre := mid + drift
		for x in range(doc.data.size.x):
			var d := absi(x - centre)
			if d <= 2:
				doc.paint(Vector2i(x, y), SimMap.Terrain.WATER_DEEP)
			elif d <= 4:
				doc.paint(Vector2i(x, y), SimMap.Terrain.WATER_SHALLOW)
			elif d <= 6:
				doc.paint(Vector2i(x, y), SimMap.Terrain.SAND)

	# A ridge across the top-left quarter only, so the two halves differ.
	for y in range(6, 14):
		for x in range(6, mid - 10):
			doc.paint(Vector2i(x, y), SimMap.Terrain.ROCK)
	# And a forest in the bottom-right, which is neither.
	for y in range(side - 20, side - 6):
		for x in range(mid + 12, side - 6):
			doc.paint(Vector2i(x, y), SimMap.Terrain.FOREST)


## Two starts, one either side of the river.
##
## ⚠️ **PLACED AWAY FROM THE WATER AND FROM THE RIDGE ON PURPOSE.** `StartLayout` refuses to
## put a unit on impassable ground, so a start dropped in the river would quietly come out
## with fewer villagers than it should — a map that loads, plays, and is wrong in a way only
## a count would reveal.
func _place_starts(doc: MapDocument) -> void:
	var side := doc.data.size.x
	doc.place_start(1, Vector2i(side / 5, side * 3 / 5))
	doc.place_start(2, Vector2i(side * 4 / 5, side * 2 / 5))


# ── verification ────────────────────────────────────────────────────────────

## Read it back and say whether it is the map we wrote. **The point of the file is that the
## GAME can read it, and only a read proves that** — `preview_author_maps`' rule.
func _verify(doc: MapDocument) -> bool:
	var problems: Array[String] = []
	var back := MapFile.load_map(doc.dir, problems)
	if back == null:
		printerr("cannot read it back: %s" % "; ".join(PackedStringArray(problems)))
		return false

	var ok := true
	if back.terrain != doc.data.terrain:
		printerr("the terrain did not survive the round trip")
		ok = false
	if back.starts != doc.data.starts:
		printerr("the starts did not survive the round trip")
		ok = false
	if back.entities.size() != doc.data.entities.size():
		printerr("%d entities written, %d read back"
				% [doc.data.entities.size(), back.entities.size()])
		ok = false

	# HOW MANY OF EACH TERRAIN KIND, because "the bytes match" is true of a uniformly grass
	# map too. This is what says the paint actually painted.
	var counts: Dictionary = {}
	for i in back.terrain.size():
		var kind := int(back.terrain[i])
		counts[kind] = int(counts.get(kind, 0)) + 1
	var used: Array[String] = []
	for kind in counts:
		used.append("%s %d" % [SimMap.Terrain.keys()[kind], counts[kind]])
	used.sort()
	print("  %d x %d, %d entities, %d starts, seats %d"
			% [back.size.x, back.size.y, back.entities.size(), back.starts.size(),
			doc.seats()])
	print("  terrain: %s" % ", ".join(PackedStringArray(used)))

	if counts.size() < 4:
		printerr("only %d terrain kinds in the file — the paint did not reach it"
				% counts.size())
		ok = false
	if doc.seats() != 2:
		printerr("expected a 2-seat map, got %d" % doc.seats())
		ok = false

	print("")
	print("OK — authored and read back. Now play it:")
	print("  Godot --path game res://dev_preview/preview_saved_map.tscn -- --folder %s"
			% doc.dir.get_file())
	return ok


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var at := Array(args).find(key)
	return str(args[at + 1]) if at >= 0 and at + 1 < args.size() else fallback
