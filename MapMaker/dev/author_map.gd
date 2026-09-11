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
	_place_walls(doc)
	_place_areas(doc)

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


## One wall on each axis, which is the only thing on this map that exercises 16.4c.
##
## ⚠️ **A WALL IS THE ONE BUILDING WHOSE FOOTPRINT DEPENDS ON THE AUTHOR'S CHOICE**, and until
## 2026-09-08 a map file could not say which. So `axis` is the newest thing in the format and it
## is the thing most worth carrying through the two-command round trip: this script writes the
## file and `preview_saved_map --folder river_demo` builds a real world from it and compares
## **every terrain tile and every building**. Neither process can check the other, which is
## decision 2's whole point — the FILE is the contract.
##
## ⚠️ **BOTH AXES, because one would not catch a transposition.** A tool that wrote `AXIS_X` for
## everything would pass a check that only ever looked at east-west walls, and the fault it hides
## is the ninety-degree one that cost six days in August.
##
## Placed on the ridge's own side of the river and clear of both starts' openings —
## `add_entity()` refuses an overlap, and a refused wall here would be a silent hole in the
## check rather than a failure.
func _place_walls(doc: MapDocument) -> void:
	var short_wall := &"building.wall_stone_short"
	if GameDataRegistry.building(short_wall) == null:
		printerr("no %s in the roster — the axis round trip is not being checked" % short_wall)
		return
	var placed := 0
	if doc.add_entity(short_wall, 1, Vector2i(8, 30), 0, WallPlan.AXIS_X):
		placed += 1
	if doc.add_entity(short_wall, 1, Vector2i(14, 30), 0, WallPlan.AXIS_Y):
		placed += 1
	if placed != 2:
		printerr("only %d of 2 walls went down — the axis round trip is incomplete" % placed)


## Two named regions, one of them in two pieces (PLAN.md 16.5).
##
## ⚠️ **THE MULTI-RECTANGLE ONE IS THE HALF WORTH CARRYING THROUGH THE ROUND TRIP.** A region of
## one rectangle survives any loader that reads a list at all; a region of two proves that
## `MapData.areas`' flat shape really does collapse back to one region by name on the other side,
## which is what `MapGen.build_from()` has to get right for `subject: "area"` to mean anything.
## A loader that keyed regions by name and kept only the last entry would pass a single-rect check.
##
## `crossing` sits on the river so it is over ground that is visibly not grass — a region drawn
## over a uniform field cannot show that the wash is in the right place — and `banks` takes a
## piece of each side, which is the L-shape case in its simplest form.
func _place_areas(doc: MapDocument) -> void:
	var side := doc.data.size.x
	var mid := side / 2
	var placed := 0
	if doc.add_area(&"crossing", Rect2i(mid - 6, side / 2 - 4, 13, 9)):
		placed += 1
	if doc.add_area(&"banks", Rect2i(mid - 14, 20, 6, 6)):
		placed += 1
	if doc.add_area(&"banks", Rect2i(mid + 9, 20, 6, 6)):
		placed += 1
	if placed != 3:
		printerr("only %d of 3 area rectangles went down — the region round trip is incomplete"
				% placed)


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

	# ⚠️ **THE AXIS KEY, READ BACK OFF THE FILE** (16.4c). This is the newest field in the format
	# and the one whose absence used to be invisible: a wall whose `axis` did not survive the
	# JSON comes back as an east-west footprint with a north-south sprite, and every other
	# assertion above would still pass.
	var axes: Array[int] = []
	for e in back.entities:
		if e.has("axis"):
			axes.append(int(e["axis"]))
	axes.sort()
	print("  wall axes in the file: %s" % [axes])
	# ⚠️ **PARENTHESISED, because `!=` BINDS TIGHTER THAN `as`.** Written as
	# `axes != [...] as Array[int]` this parses as `(axes != [...]) as Array[int]` — casting a
	# bool to a typed array — and GDScript rejects it at PARSE time. **The scene then fails to
	# load, `_ready()` never runs, nothing reaches `get_tree().quit()`, and a headless Godot
	# spins forever**: the first sign of it was a 300-second timeout with an empty stdout, which
	# reads as a hung map generation rather than as a syntax error.
	var wanted_axes: Array[int] = [WallPlan.AXIS_X, WallPlan.AXIS_Y]
	if axes != wanted_axes:
		printerr("expected one wall on each axis, got %s" % [axes])
		ok = false
	# AND NOTHING ELSE GAINED ONE. `add_entity` writes no key for an entity with no orientation,
	# which is what keeps a map with no walls byte-identical to one written before the field.
	var without := back.entities.size() - axes.size()
	if without != back.entities.size() - 2:
		printerr("%d entities carry an axis and only the two walls should" % axes.size())
		ok = false
	if doc.seats() != 2:
		printerr("expected a 2-seat map, got %d" % doc.seats())
		ok = false

	# ⚠️ **THE REGIONS, READ BACK OFF THE FILE** (16.5) — the newest field in the format, and the
	# one whose absence is invisible in exactly the way `axis`' was: a region that does not survive
	# the JSON leaves an `area` objective counting nothing forever, and every assertion above still
	# passes. **The two-rectangle region is the assertion that matters**: a loader keeping only the
	# last entry per name would satisfy a single-rect check and silently halve `banks`.
	var region_names := back.area_names()
	var shapes: Array[String] = []
	for name in region_names:
		shapes.append("%s x%d" % [name, back.area_rects(name).size()])
	print("  areas in the file: %s" % ", ".join(PackedStringArray(shapes)))
	if back.areas.size() != doc.data.areas.size():
		printerr("%d area rectangles written, %d read back"
				% [doc.data.areas.size(), back.areas.size()])
		ok = false
	if region_names.size() != 2:
		printerr("expected two regions, got %s" % [region_names])
		ok = false
	if back.area_rects(&"banks").size() != 2:
		printerr("'banks' is two rectangles and came back as %d — a loader keeping one entry"
				% back.area_rects(&"banks").size() + " per name would look exactly like this")
		ok = false
	if back.area_rects(&"crossing") != doc.data.area_rects(&"crossing"):
		printerr("'crossing' came back somewhere else: %s" % [back.area_rects(&"crossing")])
		ok = false

	print("")
	print("OK — authored and read back. Now play it:")
	print("  Godot --path game res://dev_preview/preview_saved_map.tscn -- --folder %s"
			% doc.dir.get_file())
	return ok


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var at := Array(args).find(key)
	return str(args[at + 1]) if at >= 0 and at + 1 < args.size() else fallback
