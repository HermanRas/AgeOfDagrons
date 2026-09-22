## Writes a saved map that stands every wall variant on the ground at once (#98).
##
## ## WHY A MAP AND NOT A SCREENSHOT
##
## `preview_walls` photographs walls from a fixed camera and its own header says what it is
## for: *"the one thing no test can judge -- which way a wall's art faces."* It answers that
## in four PNGs. It cannot answer the questions the owner actually has about a diagonal run --
## does the staircase read as one wall, do the joins gap, does it look like a wall you would
## build -- because those are questions about a wall seen from wherever you happen to be
## standing, at whatever zoom, next to the axis walls you already know.
##
## So this writes a **map**, and the review is a match. It goes into `SavedMaps.SAVE_ROOT`,
## which the skirmish screen's map picker lists, so opening it is picking it in the lobby and
## pressing START.
##
## ## ⛔ IT IS NOT REPO CONTENT AND IT IS NOT AUTHORED CONTENT
##
## `preview_author_maps` writes into the scenario's own directory under version control and
## refuses to overwrite, because what it writes IS the map from then on. This writes into
## `user://maps/` and overwrites without asking, because what it writes is a **test fixture
## that can be regenerated from this file at any time**. Deleting the folder loses nothing.
## The two roots are different directories for exactly this reason (PLAN.md 11.3) and this is
## the case that shows why.
##
## ## WHAT IS ON IT
##
## Three tier plots -- wood, stone, reinforced -- each carrying the same six things, so a
## difference between two plots is a difference between two tiers and nothing else:
##
##   - an EAST-WEST row: short, medium, long, gate, spaced a tile apart
##   - a NORTH-SOUTH column: the same four, laid the other way
##   - a `AXIS_D1` staircase and a `AXIS_D2` staircase, **laid by `WallPlan.plan()` itself**
##     rather than by arithmetic written here, so what stands on the ground is exactly what a
##     drag produces and cannot drift from it
##
## Then a fourth plot of the pieces the planner REFUSES on a diagonal -- medium and long --
## which is the owner's call to make and is the one thing on this map that no drag can build.
##
## ## ⚠️ THE SAND IS THE FOOTPRINT, AND IT IS THE POINT OF THE FOURTH PLOT
##
## Every tile any wall entity CLAIMS is painted `SAND` over the plot's `DIRT`. Occupancy is
## invisible in a screenshot, so the argument in `WallPlan._plan_diagonal` -- that a long
## diagonal piece claims a 36-tile square for a band of roughly 17, and the spare tiles are
## the triangular corners outside the wall line -- cannot be SEEN, and a demo that only showed
## the art would argue the opposite of the truth: the long piece butts beautifully.
## Painting the claim puts both on screen at once. The short staircase's sand hugs its wall;
## the long one's bulges a long way off it, onto ground you would want to build on.
##
## Usage:
##   Godot --headless --path game res://dev_preview/preview_wall_variants.tscn
extends Node

## The folder inside `user://maps/`, and therefore the name the picker shows.
const MAP_NAME := "Wall Variants"

const BOARD := Vector2i(128, 128)

## One tier's plot, and every plot is the same shape so the three read as three copies.
const PLOT := Vector2i(34, 34)
const PLOT_Y := 46
const PLOT_X := [6, 44, 82]

## The refused-pieces plot, below the three tiers and out of both bases' way.
const DEMO := Vector2i(6, 86)

## The four pieces of each tier, in the order they are laid left to right and top to bottom.
## Read as a table rather than derived from the tier name by string surgery: a def id is data
## and `"building.wall_%s_short" % tier` is the kind of cleverness that survives until
## somebody adds a tier that is not spelled that way.
const TIERS := [
	{
		"name": &"wood",
		"pieces": [&"building.wall_wood_short", &"building.wall_wood_medium",
				&"building.wall_wood_long", &"building.wall_wood_gate"],
	},
	{
		"name": &"stone",
		"pieces": [&"building.wall_stone_short", &"building.wall_stone_medium",
				&"building.wall_stone_long", &"building.wall_stone_gate"],
	},
	{
		"name": &"reinforced",
		"pieces": [&"building.wall_reinforced_short", &"building.wall_reinforced_medium",
				&"building.wall_reinforced_long", &"building.wall_reinforced_gate"],
	},
]

## Where each piece starts along the row, leaving one clear tile between neighbours. The
## widths are 3, 6, 9, 9 (buildings.json) and the gaps are what make four pieces read as four
## pieces instead of as one wall 30 tiles long.
const ROW_AT := [0, 4, 11, 21]

## The same offsets down the column, which needs more room because the gate is 9 tall there.
const COL_AT := [4, 8, 15, 25]

## Player 1's town centre, and player 2's well away from it.
##
## ⚠️ **PLAYER 1 SITS DIRECTLY NORTH OF THE FIRST PLOT ON PURPOSE.** The camera opens on
## player 1's start, so a base in the far corner would open the review on empty grass with the
## thing being reviewed somewhere off screen -- a scroll on a desktop and a chore on a phone.
## Fifteen tiles is close enough to see the wood plot from the opening frame and far enough
## that the base is not standing in the shot.
const BASE_1 := Vector2i(8, 28)

## The opposite corner, because slot 2 is an AI in a two-player lobby and a review is not a
## fight. Nothing about the map stops one -- it is a real match -- but the walk is long.
const BASE_2 := Vector2i(100, 108)

## What each start gets standing next to it. Enough for `MapValidator.MIN_NEARBY` (4 wood,
## 1 gold, 1 stone, 1 food) with room to spare, so the map is a playable match and not just a
## diorama -- the review is walking around it, and a villager is how you walk.
const NEARBY := [
	[&"res.tree", 8], [&"res.gold_mine", 2], [&"res.stone", 2], [&"res.berry_bush", 3],
]


func _ready() -> void:
	var data := MapData.create(BOARD, SimMap.Terrain.GRASS)
	data.meta = {
		"format_version": MapData.FORMAT_VERSION,
		"name": MAP_NAME,
		"players": 2,
		"size_players": 2,
		"authored_by": "preview_wall_variants",
		"note": "every wall variant, for review. Sand marks what each piece CLAIMS.",
	}

	_bases(data)

	var walls := 0
	for i in TIERS.size():
		walls += _tier_plot(data, Vector2i(int(PLOT_X[i]), PLOT_Y), TIERS[i])
	walls += _refused_plot(data, DEMO)

	# PAINTED LAST, over every plot floor, because the claim is what the eye is meant to
	# follow and a floor laid afterwards would bury it.
	_paint_claims(data)

	print("Wall variants map: %dx%d, %d wall entities, %d entities in all, %d starts"
			% [data.size.x, data.size.y, walls, data.entities.size(), data.starts.size()])

	# THE VALIDATOR RUNS EVEN THOUGH NOTHING GATES ON IT. A hand-built map is exactly where an
	# overlap hides -- two pieces written onto one tile spawn forced, one over the other, and
	# the only symptom is a wall that is quietly missing from a row of four.
	var problems := MapValidator.problems(data)
	for p in problems:
		print("  ! %s" % p)

	var dir := SavedMaps.SAVE_ROOT.path_join(SaveFile.slugify(MAP_NAME))
	var write := MapFile.save(data, dir, {
		"name": MAP_NAME,
		"saved_at": int(Time.get_unix_time_from_system()),
	})
	if not write.is_empty():
		print("  ! could not write it: %s" % "; ".join(write))
		get_tree().quit(1)
		return

	# READ IT BACK, on `preview_author_maps`' rule: the product is a file the game can load,
	# and a round trip is the only thing that proves the PNG and the sidecar agree.
	var check: Array[String] = []
	var reloaded := MapFile.load_map(dir, check)
	if reloaded == null:
		print("  ! wrote it and cannot read it back: %s" % "; ".join(check))
		get_tree().quit(1)
		return

	var stood := _check_world(reloaded)

	print("")
	print("Written to %s" % ProjectSettings.globalize_path(dir))
	print("Pick it in Skirmish -> Map, 2 players, and press START.")
	get_tree().quit(1 if not problems.is_empty() or not stood else 0)


## Build the reloaded map into a real world and report what actually stood up.
##
## ## ⛔ THE FILE HAVING A WALL IN IT IS NECESSARY AND NOT SUFFICIENT
##
## `test_campaigns` learned this about a dragon nest and the lesson is the same shape here:
## the entities are spawned FORCED, so two pieces written onto one tile are placed one over
## the other and the only symptom is a wall quietly missing from a row of four -- on a map
## the validator passed, in a review the owner would carry out believing they were looking at
## everything. Counting the buildings that are actually standing is the only thing that says
## otherwise, and it costs one world.
##
## It also re-derives each wall's FOOTPRINT through the running world rather than through
## `MapData`, which is the other half: the axis key is read in two places (`footprint_rect_of`
## and `build_from`) and the whole point of #98's square is that both agree.
func _check_world(data: MapData) -> bool:
	var cfg := MatchConfig.debug_skirmish()
	cfg.map_size = data.size
	cfg.map_data = data
	var w := SimWorld.new()
	w.setup(cfg)
	# `setup()` configures the players and CLEARS the board; `MapGen.build` is what copies the
	# map into it. Leaving this out gives an empty world that reports the catastrophe it was
	# written to detect -- `test_campaigns` has the full note.
	MapGen.build(w, cfg)
	w.step()

	var wanted := 0
	for e in data.entities:
		if String(e["def_id"]).begins_with("building.wall"):
			wanted += 1

	var standing := 0
	var by_axis := {}
	for e in w.entities.values():
		if not (e is SimBuilding) or not String(e.def_id).begins_with("building.wall"):
			continue
		var b: SimBuilding = e
		if not b.alive or not b.is_complete():
			continue
		standing += 1
		var key := "%dx%d f%d" % [b.footprint.x, b.footprint.y, b.facing]
		by_axis[key] = int(by_axis.get(key, 0)) + 1

	var keys := by_axis.keys()
	keys.sort()
	for k in keys:
		print("    %-12s %d" % [k, by_axis[k]])
	if standing != wanted:
		print("  ! %d walls in the file and %d standing -- pieces are overlapping"
				% [wanted, standing])
		return false
	print("  all %d walls stood up complete" % standing)
	return true


# ── the plots ───────────────────────────────────────────────────────────────


## One tier: the two axis lines and the two staircases. Returns how many segments it laid.
func _tier_plot(data: MapData, at: Vector2i, tier: Dictionary) -> int:
	data.set_terrain_rect(Rect2i(at, PLOT), SimMap.Terrain.DIRT)
	data.add_area(StringName(tier["name"]), Rect2i(at, PLOT))

	var pieces: Array = tier["pieces"]
	var laid := 0

	# EAST-WEST, then NORTH-SOUTH, from one table of offsets each. The axis is written into
	# the entity because that key is the only thing that tells `MapGen.build_from` which way
	# to lay a wall -- see `MapData.AXIS_NONE`, and the ninety degrees it cost to learn.
	for i in pieces.size():
		data.add_entity(pieces[i], 1, at + Vector2i(int(ROW_AT[i]), 0), 0, WallPlan.AXIS_X)
		laid += 1
	for i in pieces.size():
		data.add_entity(pieces[i], 1, at + Vector2i(0, int(COL_AT[i])), 0, WallPlan.AXIS_Y)
		laid += 1

	# ⛔ **THE STAIRCASES COME OUT OF `WallPlan.plan()` AND NOT OUT OF THIS FILE.** A diagonal
	# run laid by arithmetic written here would be a picture of what this file thinks the
	# planner does, which is precisely the thing that cannot be allowed to drift -- the review
	# is worthless if the map is not what a drag builds. The two drags below are the gesture,
	# and the segments are whatever the shipped code returns for it.
	laid += _run(data, pieces[0], at + Vector2i(6, 6), at + Vector2i(17, 17))
	laid += _run(data, pieces[0], at + Vector2i(22, 29), at + Vector2i(33, 18))
	return laid


## Lay whatever `WallPlan.plan()` says a drag from `from` to `to` lays, using `tier_def`'s own
## declared lengths. Returns the segment count.
func _run(data: MapData, tier_def: StringName, from: Vector2i, to: Vector2i) -> int:
	var tier: BuildingDef = GameDataRegistry.building(tier_def)
	if tier == null:
		print("  ! no such wall as '%s'" % tier_def)
		return 0
	var lengths := WallPlan.lengths_of(tier.wall_lengths, GameDataRegistry.building)
	var plan := WallPlan.plan(from, to, lengths)
	var axis := int(plan["axis"])
	for s in plan["segments"]:
		data.add_entity(StringName(s["def_id"]), 1, s["origin"] as Vector2i, 0, axis)
	return (plan["segments"] as Array).size()


## The pieces a diagonal drag will NOT lay, standing beside the run that it will.
##
## ## ⚠️ THIS PLOT IS THE ONLY THING ON THE MAP NO DRAG CAN BUILD, AND IT IS HERE TO BE RULED ON
##
## `WallPlan._plan_diagonal` takes the shortest piece only, and the reason is the footprint
## rather than the art: the medium and long pieces butt perfectly corner to corner -- the art
## side measured all three -- so the restriction reads like an art limit and is not one. It is
## that a diagonal segment has to claim a SQUARE of its own step, and a square stops being a
## fair likeness of a two-tile wall band as the step grows.
##
## **Which is invisible unless the claim is drawn**, so `_paint_claims` draws it. Three runs
## side by side, same gesture, same direction, different piece: the sand under the short run
## hugs the wall, the sand under the long run bulges six tiles off it in both directions.
func _refused_plot(data: MapData, at: Vector2i) -> int:
	var size := Vector2i(46, 22)
	data.set_terrain_rect(Rect2i(at, size), SimMap.Terrain.DIRT)
	data.add_area(&"refused", Rect2i(at, size))

	var laid := 0
	# The shipped one first, as the thing the other two are read against.
	laid += _run(data, &"building.wall_stone_short", at + Vector2i(2, 2), at + Vector2i(13, 13))
	# ⚠️ **BY HAND, AND IT HAS TO BE:** `plan()` refuses these, so there is no call that
	# produces them. The STEP and the DIRECTION still come from `WallPlan`, so only the choice
	# of def is this file's -- which is the one thing being demonstrated.
	laid += _by_hand(data, &"building.wall_stone_medium", 6, WallPlan.AXIS_D1,
			at + Vector2i(17, 2), 4)
	laid += _by_hand(data, &"building.wall_stone_long", 9, WallPlan.AXIS_D1,
			at + Vector2i(34, 2), 3)
	return laid


## `count` diagonal segments of a piece `length` tiles long, stepping from `start`.
##
## The arithmetic is `_plan_diagonal`'s, reduced to the case it refuses: the origin is the
## min corner of the square the piece spans, because a `AXIS_D2` run travels UP the grid and
## the lead tile is then the box's bottom-left rather than its top-left.
func _by_hand(data: MapData, def_id: StringName, length: int, axis: int,
		start: Vector2i, count: int) -> int:
	var step := WallPlan.diagonal_step(length)
	var dir := WallPlan.step_dir(axis)
	for i in count:
		var lead := start + Vector2i(i * step * dir.x, i * step * dir.y)
		var tail := lead + Vector2i((step - 1) * dir.x, (step - 1) * dir.y)
		data.add_entity(def_id, 1, Vector2i(mini(lead.x, tail.x), mini(lead.y, tail.y)),
				0, axis)
	return count


# ── the ground ──────────────────────────────────────────────────────────────


## Paint every tile any wall claims, so the footprint is a thing on screen.
##
## `MapData.footprint_rect_of` is asked rather than the footprints being recomputed here, for
## its own stated reason: it, `MapGen.build_from` and the MapMaker's collision test all have
## to agree, and a fourth opinion written in a preview would be a preview that draws a claim
## the match does not make.
func _paint_claims(data: MapData) -> void:
	for e in data.entities:
		if GameDataRegistry.building(StringName(e["def_id"])) == null:
			continue
		if not String(e["def_id"]).begins_with("building.wall"):
			continue
		for t in MapData.footprint_rect_of(e):
			data.set_terrain(t, SimMap.Terrain.SAND)


## A town centre, three villagers and a resource patch for each player.
func _bases(data: MapData) -> void:
	for player in [1, 2]:
		var tc: Vector2i = BASE_1 if player == 1 else BASE_2
		data.add_entity(&"building.town_center", player, tc)
		data.starts.append(tc + Vector2i(5, 5))
		for i in 3:
			data.add_entity(&"unit.villager", player, tc + Vector2i(10 + i, 4))

		# Laid in a block beside the base rather than scattered: this is a review board, and
		# where the trees are is the least interesting thing on it.
		#
		# ⛔ **BOUNDS-CHECKED, AND THAT IS NOT DEFENSIVE.** The first draft put player 2 in the
		# far corner and this block ran two tiles off the east edge: `MapValidator` passed it,
		# because it has no bounds rule for entities, and the nodes simply never spawned. So
		# player 2 was quietly one gold short on a map that reported itself clean -- the exact
		# failure `_check_world` exists to catch, arriving through the half of the map nobody
		# was looking at. A refusal that says so is what turns it back into something visible.
		var at := tc + Vector2i(13, 8)
		var offset := 0
		for row in NEARBY:
			for i in int(row[1]):
				var t := at + Vector2i((offset % 6) * 2, (offset / 6) * 2)
				if not data.in_bounds(t):
					print("  ! player %d's %s at %v is off the board" % [player, row[0], t])
				else:
					data.add_entity(row[0] as StringName, 0, t)
				offset += 1
