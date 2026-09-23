## Load a SAVED map, build it into a real world, and report what is actually standing on it.
##
## ## ⛔ WHY THIS EXISTS RATHER THAN A CAREFUL READ OF `map.json`
##
## Every cliff fault so far has been reported off a screenshot and diagnosed by reasoning about
## rules -- and three times the reasoning was right about the rule and wrong about the map. What
## settles it is the same question the game asks: build the file, then walk every tile a cliff
## claims and ask `is_passable`. **A map that reports itself clean and lets a scout onto a cliff
## is exactly the shape of failure this answers**, and it is the one the owner found twice.
##
## It answers three questions a screenshot raises and cannot settle:
##
##   - **which tiles a cliff claims are still walkable** -- the collision report;
##   - **what is sharing a tile with what** -- a tree standing in a cliff is visible here and
##     invisible in `MapValidator`, which allows cliff-on-cliff and says nothing about the rest;
##   - **which piece and which STORED frame each cliff resolved to** -- the only automatic
##     evidence that the sim facings resolve to the frames the art side measured.
##
## Run it with the map's folder name:
##
##     godot --headless --path game res://dev_preview/probe_saved_map.tscn -- platotest
##
## ## 📌 `-- plateau` PROBES A PLAN THAT WAS NEVER SAVED
##
## A saved map is a photograph of the rules **on the day it was written**, so it cannot answer
## whether a fix works -- only whether the file predates it. `plateau` builds both plateau shapes
## from `CliffPlan` into a fresh `MapData`, builds that, and asks the same questions:
##
##     godot --headless --path game res://dev_preview/probe_saved_map.tscn -- plateau
extends Node

const DEFAULT_MAP := "platotest"

## The word that means "do not read a file, lay a plateau and probe that instead".
const FRESH := "plateau"


## Where a map saved by the tool or by a preview lands. Both are tried, because the MapMaker
## writes into the REPO's `maps/` and the previews write into `user://maps/`.
##
## ⚠️ **THE REPO ROOT IS GLOBALISED RATHER THAN SPELT `res://../maps/`.** `res://` does not
## reliably climb out of the project, and the failure is silent -- the directory check simply
## says no and the probe reports "no such map" for one that is plainly there.
static func roots() -> Array[String]:
	var repo := ProjectSettings.globalize_path("res://").path_join("../maps/").simplify_path()
	return [repo, "user://maps/"] as Array[String]


func _ready() -> void:
	var name := DEFAULT_MAP
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		name = args[0]

	if name == FRESH:
		get_tree().quit(0 if _report_fresh() else 1)
		return

	var data := _load(name)
	if data == null:
		print("  ! no map called '%s' under %s" % [name, String(", ").join(roots())])
		get_tree().quit(1)
		return

	print("\n=== %s: %dx%d, %d entities ===" % [name, data.size.x, data.size.y,
			data.entities.size()])
	_report_sharers(data)
	var ok := _report_world(data)
	get_tree().quit(0 if ok else 1)


## Lay both plateau shapes from `CliffPlan` into a fresh map and probe THAT.
##
## ⛔ **THE QUESTION A SAVED MAP CANNOT ANSWER.** `maps/platotest` was written on 2026-09-23 by
## the rules of that morning; re-probing it after a fix reports the file, not the fix. This
## builds from `CliffPlan.plan` at the version that is compiled in.
##
## ⚠️ **IT ASKS ABOUT THE ROCK AND NOT ABOUT THE FOOTPRINTS.** `_report_world` walks the tiles
## each piece CLAIMS, and on the owner's map every one of 362 came back blocked while a scout
## walked up the cliff anyway -- because the claim is a rectangle and a face's rock is that
## rectangle sheared `(+1, +1)` down the screen. So this walks the rock.
func _report_fresh() -> bool:
	var data := MapData.create(Vector2i(96, 96))
	var shapes := {
		# ⚠️ **THE TWO ENDS MUST DIFFER IN BOTH `u` AND `v`.** `(20,20)-(34,34)` looks like a
		# generous drag and is a `v` span of ZERO: a 1-tile-wide diagonal ridge whose rock falls
		# on its own high ground, so it lays no blockers and proves nothing. These give
		# `u = 40..60`, `v = 0..12`.
		"screen-aligned (Plato N<->S)": CliffPlan.screen_aligned_tiles(
				Vector2i(20, 20), Vector2i(36, 24)),
		"grid-aligned (Plato NE<->SW)": CliffPlan.grid_aligned_tiles(
				Vector2i(60, 20), Vector2i(68, 28)),
	}
	var high: Dictionary = {}
	for label in shapes:
		var tiles: Dictionary = shapes[label]
		var plan := CliffPlan.plan(tiles)
		print("  %s: %d tiles -> %d pieces" % [label, tiles.size(), plan.size()])
		for r in plan:
			data.add_entity(r["def_id"], 0, r["tile"], 0, int(r["axis"]))
		for t in tiles:
			high[t] = true

	print("\n=== a plateau laid by the CliffPlan in this build: %d entities ===" %
			data.entities.size())
	_report_sharers(data)
	var ok := _report_world(data)

	var w := SimWorld.new()
	var cfg := MatchConfig.debug_skirmish()
	cfg.map_size = data.size
	cfg.map_data = data
	w.setup(cfg)
	MapGen.build(w, cfg)
	w.step()

	var walkable := 0
	var under := 0
	for t in _rock_tiles(data):
		# The plateau TOP is walkable on purpose; only the ground the rock falls ONTO is asked
		# about. A face's own lip is high and is blocked, which is the documented price.
		if high.has(t):
			continue
		under += 1
		if w.map.is_passable(t, SimMap.Domain.LAND):
			walkable += 1
			if walkable <= 20:
				print("  ! %v has rock over it and a unit can stand there" % [t])
	if walkable > 0:
		print("  ! %d of %d tiles under a cliff face are walkable" % [walkable, under])
		return false
	print("  all %d tiles a cliff face is DRAWN over are blocked too" % under)
	return ok


## Every tile a face's rock is painted over, from the run geometry rather than the footprint.
##
## ⚠️ **BOTH FACE FAMILIES.** Asking only about `FACE` is what let the first round of this report
## "all clear" while the owner rode a scout along a screen-horizontal run: that run is constant
## `x + y`, so it is `AXIS_D2` and every piece of it is a `_diag`.
func _rock_tiles(data: MapData) -> Dictionary:
	var out: Dictionary = {}
	for e in data.entities:
		var ladder := CliffPlan.ladder_of(e.get("def_id", &""))
		if ladder != CliffPlan.FACE and ladder != CliffPlan.FACE_DIAG:
			continue
		var length := 1
		for rung in ladder:
			if ladder[rung] == e["def_id"]:
				length = int(rung)
		var step := CliffPlan.step_of(int(e.get("axis", 0)))
		for i in range(length):
			for d in range(CliffPlan.DEPTH):
				out[(e["tile"] as Vector2i) + step * i + Vector2i.ONE * d] = true
	return out


func _load(name: String) -> MapData:
	for root in roots():
		var dir: String = root.path_join(name)
		if not MapFile.exists_in(dir):
			continue
		# THE PROBLEM LIST IS PRINTED AND NOT SWALLOWED: a map that loads with complaints is a
		# different answer from one that loads clean, and this probe exists to report exactly
		# the things nothing else says out loud.
		var problems: Array[String] = []
		var loaded := MapFile.load_map(dir, problems)
		for p in problems:
			print("  ? %s" % p)
		if loaded != null:
			print("  read %s" % dir)
			return loaded
	return null


## Tiles held by more than one entity, and what is on them.
##
## ⚠️ **CLIFF-ON-CLIFF IS EXPECTED AND IS STILL PRINTED**, because the interesting line is the
## one where a cliff shares with something else -- and a report that hid the ordinary case would
## make the odd one look like a different kind of event.
func _report_sharers(data: MapData) -> void:
	var at: Dictionary = {}
	for e in data.entities:
		for t in MapData.footprint_rect_of(e):
			if not at.has(t):
				at[t] = []
			(at[t] as Array).append(String(e.get("def_id", "")))

	var mixed := 0
	var cliffy := 0
	for t in at:
		var who: Array = at[t]
		if who.size() < 2:
			continue
		var all_cliff := true
		for id in who:
			if not String(id).begins_with("building.cliff"):
				all_cliff = false
		if all_cliff:
			cliffy += 1
			continue
		mixed += 1
		if mixed <= 20:
			print("  ! %v is shared by %s" % [t, String(", ").join(who)])
	print("  %d tiles hold two cliffs (expected); %d hold a cliff and something else" %
			[cliffy, mixed])


## Build it and walk every tile every cliff claims.
func _report_world(data: MapData) -> bool:
	var cfg := MatchConfig.debug_skirmish()
	cfg.map_size = data.size
	cfg.map_data = data
	var w := SimWorld.new()
	w.setup(cfg)
	MapGen.build(w, cfg)
	w.step()

	var by_frame: Dictionary = {}
	var standing := 0
	var open_pieces := 0
	var open_tiles := 0
	for e in w.entities.values():
		if not (e is SimBuilding) or not String(e.def_id).begins_with("building.cliff"):
			continue
		var b: SimBuilding = e
		if not b.alive or not b.is_complete():
			continue
		standing += 1
		var sprite := posmod(7 - b.facing, 8)
		var key := "%s stored %d" % [String(b.def_id).trim_prefix("building."), sprite]
		by_frame[key] = int(by_frame.get(key, 0)) + 1

		var open := 0
		for t in _tiles_of(b):
			if w.map != null and w.map.is_passable(t, SimMap.Domain.LAND):
				open += 1
		if open > 0:
			open_pieces += 1
			open_tiles += open
			if open_pieces <= 20:
				print("  ! %s at %v leaves %d of %d tiles walkable"
						% [b.def_id, b.origin_tile(), open, _tiles_of(b).size()])

	var keys := by_frame.keys()
	keys.sort()
	for k in keys:
		print("    %-34s %d" % [k, by_frame[k]])

	if open_pieces == 0:
		print("  all %d cliffs stand and block every tile they claim" % standing)
		return true
	print("  ! %d of %d cliffs leave %d tiles walkable" % [open_pieces, standing, open_tiles])
	return false


func _tiles_of(b: SimBuilding) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var origin := b.origin_tile()
	for y in range(b.footprint.y):
		for x in range(b.footprint.x):
			out.append(origin + Vector2i(x, y))
	return out
