## Time the editor on a REAL map, so a slowness report is answerable with numbers
## (PLAN.md 16.x-slow-place).
##
## ## WHY THIS EXISTS: TWO SLOWNESS REPORTS AND NO WAY TO ANSWER EITHER
##
## The owner's playtests, six weeks apart:
##
##   - 2026-09-04 — *"the tool is very slow ... some tiles did not place due to lag"*. The
##     answer turned out to be the hover cursor sharing a `_draw` with the terrain, so every
##     mouse-move invalidated 9,216 tiles. **That was found by reasoning and the reasoning
##     happened to be right.**
##   - 2026-09-08 — *"the tool is very very slow.. like 3 sec between click and place of
##     buildings on sample map"*. The same approach **failed**: every candidate on the click
##     path is cheap on paper — `claimed_tiles()` is a few hundred dictionary writes,
##     `MapEdit`'s snapshot is a few hundred small dicts, `Startup.can_save()` is a field read,
##     the palette does not rebuild — and none of them is three seconds.
##
## ⚠️ **A THIRD REPORT MUST NOT COST ANOTHER READ THROUGH FOUR FILES.** So the tool takes a
## reading of itself: `MapCanvas` records what its last redraw cost by phase, and this script
## drives the real editor through the real map and prints the figures beside a budget. §5's
## rule about checks that cannot see the fault applies to performance exactly as it does to
## drawing — and this project has already paid once for optimising without a number, when
## reordering two checks in `SimMap.is_terrain_passable` blew the tick budget in three tests to
## fix one domain.
##
## ## FOUR THINGS ARE TIMED AND THEY FAIL IN DIFFERENT DIRECTIONS
##
##   1. **the idle frame** — the map sitting on screen with nothing happening. A `_draw` runs
##      only on a change, but the commands it leaves behind are re-rendered every frame, so a
##      canvas that is expensive to *present* makes the whole tool slow while every individual
##      operation measures fast. **This is the one a script that only timed the click would
##      miss**, and it is the one that would explain "3 seconds" — at 0.3 fps a click is three
##      seconds from being drawn however cheap it was.
##   2. **the redraw**, split into terrain and entities. They scale with different things — the
##      cull and the map's contents — and want opposite fixes.
##   3. **the document ops** — `claimed_tiles()` and `add_entity()`, timed with no drawing
##      involved at all, so a slow placement can be attributed to the map or to the picture.
##   4. **click to presented frame** — what the owner's stopwatch actually measures, vsync wait
##      and all. Reported beside the synchronous cost of the same call, because the difference
##      between them IS the frame the tool was waiting for.
##
## Three zooms, because the cull and the grid are the two things that change with the view:
## `MapCanvas._draw_terrain` skips the grid outlines below 0.5x, so the same map is two
## different amounts of work either side of that line.
##
## ⚠️ **IT OPENS AND NEVER WRITES.** `maps/` and `scenarios/` are content under version
## control (`dev/open_map.gd` takes the same line): the placements this makes are in memory,
## undone before it exits, and Save is never pressed.
##
## The exit code is the answer: non-zero when the click-to-drawn figure is over budget.
##
## Usage:
##   Godot --path MapMaker res://dev/profile_editor.tscn
##   Godot --path MapMaker res://dev/profile_editor.tscn -- --folder sample_duel
##   Godot --path MapMaker res://dev/profile_editor.tscn -- --budget 250
extends Node

## `Editor`'s script, for its `Tool` enum — `Editor.tscn`'s root has no `class_name`.
const EDITOR := preload("res://src/editor.gd")

## Which map, when `--folder` says nothing. **The one the report was about**, and the one map
## in the repo that is deliberately committed (`maps/sample_duel`), so this runs on a clean
## clone.
const DEFAULT_FOLDER := "sample_duel"

## What a click may cost, end to end, in milliseconds. Over this and the exit code is 1.
##
## **100 ms is not a round number, it is the threshold at which a control stops feeling
## attached to the finger** — the same figure `preview_touch_controls` is built around. The
## owner's report is 3,000.
const DEFAULT_BUDGET_MS := 100.0

## Frames to let the window settle before any measurement. The first frames of a Godot window
## include shader compilation and the palette's atlas decodes; timing those would report a
## startup cost as a per-click one.
const SETTLE_FRAMES := 45

## How many frames the idle measurement averages over. Long enough that one hitch does not
## dominate, short enough that the whole run stays under a few seconds.
const IDLE_FRAMES := 90

## How many times each document op is repeated. `claimed_tiles()` is microseconds on a small
## map, and one reading of it is mostly noise.
const REPEATS := 20

var _editor: Control = null
var _budget_ms := DEFAULT_BUDGET_MS
var _failures: Array[String] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var folder := _arg(args, "--folder", DEFAULT_FOLDER)
	_budget_ms = float(_arg(args, "--budget", str(DEFAULT_BUDGET_MS)))

	# REFUSED UP FRONT RATHER THAN PROFILED. Timing an editor with no roster would measure a
	# canvas drawing a hardcoded fallback, which is not the tool anybody is complaining about.
	var startup := Startup.check()
	if not startup.can_save():
		printerr("cannot profile the editor: %s" % startup.reason)
		get_tree().quit(1)
		return

	_editor = load("res://Editor.tscn").instantiate()
	add_child(_editor)
	await _frames(SETTLE_FRAMES)

	if not await _open(folder):
		get_tree().quit(1)
		return

	_report_subject()
	await _profile_idle()
	await _profile_views()
	_profile_document_ops()
	await _profile_click()
	_verdict()


# ── the subject ─────────────────────────────────────────────────────────────

## Open `folder` through the editor's own Open path.
func _open(folder: String) -> bool:
	var row := _find(folder)
	if row.is_empty():
		printerr("no map called '%s' in any of File ▸ Open's roots" % folder)
		return false
	# ⚠️ **TYPED EXPLICITLY.** `_editor` is a `Control` — `Editor.tscn`'s root has no
	# `class_name` — so every call through it answers `Variant` and inference has nothing to
	# work with. The same is true of `document()` and `listed_maps()` below.
	var problems: Array[String] = _editor.open_map(str(row["dir"]))
	if not problems.is_empty():
		printerr("cannot open %s — %s" % [folder, "; ".join(PackedStringArray(problems))])
		return false
	await _frames(8)
	return true


func _find(folder: String) -> Dictionary:
	# THE LIST IS READ OFF DISK BY `refresh_open_list()` AND NOT BEFORE. `listed_maps()` returns
	# what the dialog last found, which is nothing until the dialog has been opened — so a
	# script that only asked gets an empty list and reports the map as missing.
	_editor.refresh_open_list()
	for row in _editor.listed_maps():
		if str(row["folder"]) == folder or str(row["label"]) == folder:
			return row
	return {}


func _report_subject() -> void:
	var doc: MapDocument = _editor.document()
	var canvas: MapCanvas = _editor._canvas
	print("profiling the editor")
	print("  map        \"%s\"  %d x %d, %d entities, seats %d"
			% [doc.map_name, doc.data.size.x, doc.data.size.y,
			doc.data.entities.size(), doc.seats()])
	print("  window     %s" % str(canvas.size))
	# THE VSYNC MODE IS PART OF EVERY FIGURE BELOW and is the first thing that makes a reading
	# look wrong: with it enabled no latency can measure under a frame however fast the tool is,
	# so a 17 ms click is the floor and not a finding.
	print("  vsync      %s" % ("on" if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED else "off"))
	print("")


# ── 1. the idle frame ───────────────────────────────────────────────────────

## What a frame costs with the map on screen and nothing happening.
##
## ⚠️ **THIS IS THE MEASUREMENT THE OBVIOUS SCRIPT LEAVES OUT.** Godot re-renders a
## `CanvasItem`'s stored commands every frame whether or not `_draw` ran, so ~9,000
## `draw_colored_polygon` calls are a cost paid **per frame, forever**, not per redraw. A tool
## running at a few frames a second makes every click look slow while each click measures fast,
## which is exactly the shape of a report that says *"the tool is very very slow"* and then
## names one operation.
##
## 📝 **`Performance.TIME_PROCESS` WAS PRINTED HERE AND WAS REMOVED, which is worth recording
## rather than quietly dropping.** It reported 276.9 ms against a 42.8 ms frame — a figure that
## cannot be true of the thing it sits beside, because this script spends its own frames inside
## `await` and the monitor is not measuring what the label claimed. §6's rule about the status
## line reading a stale zoom applies to a profiler with more force than to a tool: **a number
## that is quietly wrong is worse than no number, because it gets believed** — and this one
## would have sent the next reader hunting for script time that was not there.
func _profile_idle() -> void:
	var canvas: MapCanvas = _editor._canvas
	var draws_before := canvas.draws
	var worst := 0.0
	var total := 0.0
	for _i in IDLE_FRAMES:
		var dt := await _frame_delta()
		total += dt
		worst = maxf(worst, dt)
	var mean := total / float(IDLE_FRAMES)
	print("1. IDLE — the map on screen, nothing happening")
	print("   frame      mean %.1f ms (%.0f fps), worst %.1f ms" % [mean, 1000.0 / maxf(mean, 0.001), worst])
	# ⚠️ **A REDRAW DURING THE IDLE WINDOW INVALIDATES THE READING**, and it is worth saying so
	# rather than quietly averaging it in: nothing should be invalidating the canvas while the
	# mouse is still. If this ever fires it is a finding in itself.
	if canvas.draws != draws_before:
		_fail("the canvas redrew %d times while IDLE — something is invalidating it per frame"
				% (canvas.draws - draws_before))
	if mean > 20.0:
		_fail("an idle frame costs %.1f ms — the tool is slow before anything is clicked" % mean)
	print("")


# ── 2. the redraw, at three views ───────────────────────────────────────────

## The cost of one full `_draw`, at fit-to-view and either side of the grid threshold.
##
## The zooms are not arbitrary: `_draw_terrain` draws grid outlines only at 0.5x and above, so
## **the same map is two different amounts of work either side of that line** and a single
## reading cannot say which one an author is looking at.
func _profile_views() -> void:
	print("2. REDRAW — one full _draw(), by phase")
	var doc: MapDocument = _editor.document()
	var middle := doc.data.size / 2
	for view in [
		{"label": "fit to view", "zoom": 0.0},
		{"label": "0.45x (no grid)", "zoom": 0.45},
		{"label": "1.00x (grid on)", "zoom": 1.0},
		{"label": "2.00x (grid on)", "zoom": 2.0},
	]:
		var zoom := float(view["zoom"])
		if zoom <= 0.0:
			(_editor._canvas as MapCanvas).fit_to_view()
		else:
			(_editor._canvas as MapCanvas).center_on(middle, zoom)
		await _frames(2)
		var m := await _redraw_once()
		print("   %-16s %6.1f ms   terrain %6.1f   entities %5.2f   cull %d tiles at %.2fx"
				% [view["label"], m["draw"], m["terrain"], m["entities"],
				m["tiles"], m["zoom"]])
	# BACK TO FIT-TO-VIEW, so the click measurement below happens on the view an author opens a
	# map in rather than on whichever zoom this loop ended at.
	(_editor._canvas as MapCanvas).fit_to_view()
	await _frames(4)
	_profile_geometry()
	print("")


## The same tiles PROJECTED, with nothing drawn. **This is the reading that chose the fix, and
## it is kept because it is the reading that would notice the fix being lost.**
##
## `_draw_terrain` does two things per tile: it works out the diamond's four screen points, and
## it hands them to the renderer. Those have completely different remedies — a slow projection
## loop is fixed by computing less, and slow draw commands are fixed by issuing ONE of them
## instead of nine thousand — and a single milliseconds-per-redraw figure cannot tell them
## apart. On 2026-09-08 it separated them decisively: 9,216 tiles cost **54 ms to project and
## 439 ms to draw**, so the draw commands were 88% of a redraw and batching was the answer.
##
## ⚠️ **BOTH PROJECTION ROUTES ARE TIMED, and printing only one of them was actively
## misleading for about ten minutes.** After the batching landed this section still called
## `_diamond()` per tile — the route `_draw_terrain` no longer takes — and reported 78 ms
## against a 28 ms *whole redraw*, which reads as the arithmetic being impossible rather than
## as the benchmark measuring the wrong path. So the per-tile route is labelled as the old one
## and kept as the standing "before", and the basis route is the one to compare the redraw
## against.
func _profile_geometry() -> void:
	var canvas: MapCanvas = _editor._canvas
	var doc: MapDocument = _editor.document()
	var bounds := canvas._visible_tile_bounds()
	var tiles := 0

	# 1. FOUR `Iso` CALLS AND AN ALLOCATION PER TILE — what the canvas did before 16.x-slow-place.
	var t0 := Time.get_ticks_usec()
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var t := Vector2i(x, y)
			var poly := canvas._diamond(t)
			var _c: Color = MapCanvas.TERRAIN_COLOURS.get(doc.data.terrain_at(t), Color.MAGENTA)
			tiles += poly.size() / 4
	var per_tile_ms := (Time.get_ticks_usec() - t0) / 1000.0

	# 2. FROM THE BASIS — three `Iso` calls for the whole map and four additions a tile, which is
	# what `_draw_terrain` does now.
	var basis := canvas.projection_basis()
	var o: Vector2 = basis[0]
	var ex: Vector2 = basis[1]
	var ey: Vector2 = basis[2]
	t0 = Time.get_ticks_usec()
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var a := o + ex * float(x) + ey * float(y)
			var _b := a + ex
			var _c2 := a + ex + ey
			var _d := a + ey
			var _col: Color = MapCanvas.TERRAIN_COLOURS.get(
					doc.data.terrain_at(Vector2i(x, y)), Color.MAGENTA)
	var basis_ms := (Time.get_ticks_usec() - t0) / 1000.0

	print("   %-16s %6.1f ms   projection only, %d tiles (%.1f us each) — THE OLD PER-TILE ROUTE"
			% ["geometry, Iso", per_tile_ms, tiles,
			per_tile_ms * 1000.0 / maxf(float(tiles), 1.0)])
	print("   %-16s %6.1f ms   projection only, %d tiles (%.1f us each) — what _draw_terrain does"
			% ["geometry, basis", basis_ms, tiles,
			basis_ms * 1000.0 / maxf(float(tiles), 1.0)])


## Force one redraw and read what it cost off the canvas.
func _redraw_once() -> Dictionary:
	var canvas: MapCanvas = _editor._canvas
	var before := canvas.draws
	canvas.queue_redraw()
	# WAIT FOR THE DRAW ITSELF, not for a fixed number of frames: `queue_redraw` schedules and a
	# frame count would sometimes read the previous reading and report it as this view's.
	while canvas.draws == before:
		await get_tree().process_frame
	return {
		"draw": canvas.last_draw_usec / 1000.0,
		"terrain": canvas.last_terrain_usec / 1000.0,
		"entities": canvas.last_entities_usec / 1000.0,
		"tiles": canvas.last_tiles_culled,
		"zoom": canvas.zoom(),
	}


# ── 3. the document, with no drawing in it ──────────────────────────────────

## `claimed_tiles()` and `add_entity()` timed on their own.
##
## **NO FRAMES AND NO DRAWING**, which is the point: if a placement is slow and these two are
## fast, the cost is in the picture and not in the map — and the fix is in a different file.
func _profile_document_ops() -> void:
	var doc: MapDocument = _editor.document()
	print("3. DOCUMENT — the same work with no drawing in it")

	var t0 := Time.get_ticks_usec()
	for _i in REPEATS:
		doc.data.claimed_tiles()
	print("   claimed_tiles()   %.2f ms  (%d entities)"
			% [(Time.get_ticks_usec() - t0) / 1000.0 / float(REPEATS),
			doc.data.entities.size()])

	# ON GROUND THAT IS ACTUALLY CLEAR. A refused placement returns before the snapshot is even
	# opened, so timing one would report the refusal path and call it a placement.
	var spots := _clear_ground(REPEATS)
	if spots.is_empty():
		print("   add_entity()      no clear ground on this map to time it on")
		print("")
		return
	var placed := 0
	t0 = Time.get_ticks_usec()
	for tile in spots:
		if doc.add_entity(StartLayout.TOWN_CENTRE, 1, tile):
			placed += 1
	var per := (Time.get_ticks_usec() - t0) / 1000.0 / float(maxi(placed, 1))
	print("   add_entity()      %.2f ms  (%d town centres placed)" % [per, placed])
	for _i in placed:
		doc.undo()
	print("")


## `count` origins with room for a town centre, spread across the map.
##
## Through `claimed_tiles()` and `footprint_rect_of()` — the same two functions the placement
## itself asks, because a spot this script thought was clear and `add_entity` refuses would
## time the refusal.
func _clear_ground(count: int) -> Array[Vector2i]:
	var doc: MapDocument = _editor.document()
	var claimed := doc.data.claimed_tiles()
	var footprint: Vector2i = GameDataRegistry.building(StartLayout.TOWN_CENTRE).footprint
	var out: Array[Vector2i] = []
	var step := maxi(footprint.x, footprint.y) + 1
	var y := 1
	while y + footprint.y < doc.data.size.y and out.size() < count:
		var x := 1
		while x + footprint.x < doc.data.size.x and out.size() < count:
			if _is_clear(Vector2i(x, y), footprint, claimed):
				out.append(Vector2i(x, y))
				# THE SPOTS MUST NOT OVERLAP EACH OTHER EITHER: they are all placed before any is
				# undone, so a second origin inside the first's footprint would be refused and
				# the average would be over fewer placements than it says.
				for dy in footprint.y:
					for dx in footprint.x:
						claimed[Vector2i(x + dx, y + dy)] = true
			x += step
		y += step
	return out


static func _is_clear(origin: Vector2i, footprint: Vector2i, claimed: Dictionary) -> bool:
	for dy in footprint.y:
		for dx in footprint.x:
			if claimed.has(origin + Vector2i(dx, dy)):
				return false
	return true


# ── 4. click to presented frame ─────────────────────────────────────────────

## What the owner's stopwatch measures: a click through the real tool, to a frame on screen.
##
## Both halves are reported, because they fail differently and the difference between them is
## the whole diagnosis. **The synchronous half** is `apply_tool()` returning — the map changed,
## the redraw is queued, nothing is on screen yet. **The end-to-end half** waits for the draw
## and then for the frame to be presented, so it carries the vsync wait and the render of every
## command the canvas holds. A big gap between the two means the tool is waiting for its own
## picture rather than computing anything.
func _profile_click() -> void:
	var doc: MapDocument = _editor.document()
	var canvas: MapCanvas = _editor._canvas
	print("4. CLICK — through the palette and the real tool, to a frame on screen")

	# THE REAL ARMING PATH: pick off the palette, which is what arms PLACE, rather than setting
	# the tool by hand. `_on_entry_picked` is part of what a click costs.
	(_editor._palette as ObjectPalette).pick(StartLayout.TOWN_CENTRE)
	_editor.set_tool(EDITOR.Tool.PLACE)
	await _frames(4)

	var spots := _clear_ground(5)
	if spots.is_empty():
		printerr("   no clear ground to click on")
		return
	var worst := 0.0
	var placed := 0
	for tile in spots:
		var before_draws := canvas.draws
		var before_count: int = doc.data.entities.size()
		var t0 := Time.get_ticks_usec()
		_editor.apply_tool(tile)
		var sync_ms := (Time.get_ticks_usec() - t0) / 1000.0
		if doc.data.entities.size() == before_count:
			printerr("   %s was REFUSED — not a timing" % tile)
			continue
		placed += 1
		while canvas.draws == before_draws:
			await get_tree().process_frame
		# AND THEN THE FRAME ITSELF. `_draw` having run means the commands exist, not that
		# anybody has seen them.
		await RenderingServer.frame_post_draw
		var total_ms := (Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, total_ms)
		print("   at %-9s apply_tool %6.2f ms   to a drawn frame %7.2f ms   (redraw %.1f ms)"
				% [tile, sync_ms, total_ms, canvas.last_draw_usec / 1000.0])
	for _i in placed:
		doc.undo()
	if worst > _budget_ms:
		_fail("the worst click took %.0f ms, against a %.0f ms budget" % [worst, _budget_ms])
	print("")


# ── plumbing ────────────────────────────────────────────────────────────────

func _verdict() -> void:
	if _failures.is_empty():
		print("OK — nothing over budget")
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("SLOW — %s" % f)
	get_tree().quit(1)


func _fail(sentence: String) -> void:
	_failures.append(sentence)


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


## One frame, in milliseconds of wall clock.
##
## Measured across `process_frame` rather than read off `get_process_delta_time()`, because the
## delta the engine reports is the one it *intends* and this is the one that happened.
func _frame_delta() -> float:
	var t0 := Time.get_ticks_usec()
	await get_tree().process_frame
	return (Time.get_ticks_usec() - t0) / 1000.0


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var at := Array(args).find(key)
	return str(args[at + 1]) if at >= 0 and at + 1 < args.size() else fallback
