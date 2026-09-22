## Writes a saved map that stands every cliff piece on the ground at once (#97/#99).
##
## ## WHY A MAP, AND WHY A PLATEAU RATHER THAN A ROW OF PIECES
##
## `preview_wall_variants` is the precedent and this is the same argument one step further
## on. A wall is judged piece by piece -- which way does the art face -- and a cliff is not:
## **a tile set's bugs all live BETWEEN tiles**, which is the lesson the art side re-learned
## three times over on this card. Every cliff piece was right on its own while the corner
## left a wedge of low ground showing, and no single frame could have said so.
##
## So the centrepiece is not a ladder of pieces, it is two PLATEAUS -- a closed ring of
## face, crest and corner -- because the questions worth asking are all about the joins.
##
## ## ⛔ THE ONE-ENTITY-PER-TILE PROBLEM, WHICH IS NEW AND IS THE OWNER'S TO LOOK AT
##
## The art's three placement rules were written for a TERRAIN model, where both tables are
## live at once and one tile can want an entry from each -- the corner tile draws a face on
## both its edges *and* the diagonal piece over its point. **A cliff is an entity now, and a
## tile holds one.** So at a corner the pieces have to be assigned rather than stacked, and
## the two plateaus below differ by exactly that one decision:
##
##   - **plateau A** gives the near corner to `cliff_face_diag` and stops the two face runs
##     one tile short of it
##   - **plateau B** runs the faces the full length and places no corner piece at all
##
## Same size, same lengths, same ground, one difference. Which of them reads is a question
## about a picture and is not answerable from here.
##
## ## THE LENGTH LADDERS ARE ABOUT THE REPEAT, NOT ABOUT COVERING GROUND
##
## Every piece is a window onto ONE 16 m strip of rock, so a 1-tile piece shows the same
## 2 m on every tile of a run -- one rock column stamped every 64 px, which is the fault the
## owner reported as *"the current repeat is too close"*. `long` is the only length that
## shows the whole strip. The ladders stand 1 / 3 / 6 / 9 side by side so that is visible
## rather than argued about.
##
## Usage:
##   Godot --headless --path game res://dev_preview/preview_cliff_variants.tscn
extends Node

const MAP_NAME := "Cliff Variants"

## ⛔ **96 AND NOT 128, BECAUSE FOG OF WAR IS WHAT MAKES A REVIEW MAP READABLE OR USELESS.**
##
## The first cut spread the showcase over a 128x128 board with the diagonal run at y 97 and
## player 1 starting at y 25. Every piece was on the map -- 13 face and 10 crest, confirmed in
## the sidecar -- and the owner could not see one of them: *"still no diagonal cliffs on test
## map?"* They were eighty tiles away in unexplored black.
##
## ⚠️ **THERE IS NO REVEAL FLAG TO REACH FOR.** `VisionSystem` lights tiles around ALLIED
## entities and nothing else, and a cliff is gaia with `los: 0`, so a showcase lights itself
## exactly nowhere. That is correct for the game and it means a dev map has to carry its own
## vision, which is what `WATCH_TOWERS` below is for.
const BOARD := Vector2i(96, 96)

## The two plateaus: the high ground each one encloses, in tiles.
##
## ⚠️ **THE GROUND INSIDE IS GRASS AND EVERYTHING ELSE IS SAND, WHICH IS NOT DECORATION.**
## The owner's composed samples are a grass plateau with sand around it, and that contrast
## is half of what makes a cliff read as a height boundary rather than as a rock fence. The
## flat drop-in model carries no top quad precisely so the plateau keeps its own surface --
## see visuals.json's `_note_cliffs` for why the terrain-byte plan could not.
## ⛔ **ONE LENGTH PER PLATEAU, AND EACH EDGE IS A WHOLE NUMBER OF IT** (the owner's rule of
## 2026-09-22: *"try only using medium with medium, small with small and large with large"*).
## Mixing lengths in one line steps the rock sideways at every seam -- buildings.json's
## `_note_cliffs` has why, and it is a property of a cliff that walls do not share. So the
## sizes are multiples: 12 = 4x3 = 2x6, and 18 = 2x9.
const PLATEAUS := [
	{"high": Rect2i(8, 24, 12, 12), "length": 3, "corner": true},
	{"high": Rect2i(28, 24, 12, 12), "length": 6, "corner": true},
	{"high": Rect2i(48, 24, 18, 18), "length": 9, "corner": true},
	# The control for the one decision this file has to make that the art never did. Same
	# ring, same ground, NO corner piece -- so the wedge of low ground at the near point is
	# visible beside a plateau that closes it.
	{"high": Rect2i(8, 44, 12, 12), "length": 6, "corner": false},
	# THE 1-TILE PIECE IN A RUN, which is the fault the owner already diagnosed rather than a
	# candidate: every tile shows the same 2 m of a 16 m strip, so it is one rock column
	# stamped every 64 px. It is here as the REFERENCE the other three are read against --
	# "the repeat is too close" is much easier to judge with the bad case on screen.
	{"high": Rect2i(28, 44, 8, 8), "length": 1, "corner": true},
]

## Player 1's eyes on the showcase (`los: 10`, a 3x2 footprint), standing in the sand between
## the plateaus rather than on them.
##
## ⚠️ **SCAFFOLDING, AND IT IS IN THE MAP BECAUSE IT CANNOT BE ANYWHERE ELSE.** A review map
## whose subject is invisible until somebody walks a villager across it is a review map nobody
## completes. Towers rather than villagers because `los` is 10 against 4 -- six of these cover
## what forty villagers would -- and because they stand still.
## ⛔ **ON THE PLATEAU TOPS, NOT IN THE SAND BETWEEN THEM, AND THAT IS THE SECOND ATTEMPT.**
## Towers placed in the gaps left 13 cliffs dark -- a ring is lit from its far side only if
## the circle reaches all the way across, and at `los: 10` a tower outside a 12x12 plateau
## covers the near edge and loses the far one. Standing ON the high ground lights the whole
## ring from the middle, which is also the only place on this map guaranteed to be free of
## cliff footprints. The last two are for the diagonal runs, which have no interior.
const WATCH_TOWERS := [
	Vector2i(12, 28), Vector2i(32, 28), Vector2i(54, 30), Vector2i(60, 36),
	Vector2i(12, 48), Vector2i(30, 46),
	Vector2i(39, 65),
]

## The four lengths, for the ladders. A RUN uses exactly one of them -- see `_row`.
const LENGTHS := [1, 3, 6, 9]

const FACE := {
	1: &"building.cliff_face", 3: &"building.cliff_face_short",
	6: &"building.cliff_face_medium", 9: &"building.cliff_face_long",
}
const BACK := {
	1: &"building.cliff_back", 3: &"building.cliff_back_short",
	6: &"building.cliff_back_medium", 9: &"building.cliff_back_long",
}

## Where the ladders stand, and where the diagonal run does.
## THE SECOND PLATEAU SHAPE: a SCREEN-ALIGNED pedestal (owner, 2026-09-22).
##
## ## ⛔ THE FIRST CUT LAID THE TWO E-W RUNS AND NOTHING ELSE, WHICH IS HALF A SHAPE
##
## *"i am missing the 90 degree cliff going directly up and down to complete the second
## pedastal shape."* Correct: a screen-aligned plateau has four edges and only two of them
## run east-west. The other two go straight up and down the screen, and they had no pieces on
## them at all -- so the shape read as two disconnected horizontal walls.
##
## ✅ **AND THE MISSING EDGE IS NOT MISSING ART.** There is no north-south cliff face and
## there cannot be one: that face's normal is perpendicular to the view direction, so it is
## invisible at any span. What draws there is the **axis staircase** -- ordinary `cliff_face` /
## `cliff_back` pieces, one tile each, stepping (+1, +1) -- which the art side flagged as
## *"correct rather than a stopgap"*. `_pedestal` lays it.
##
## Defined in the DIAGONAL coordinates the shape is actually square in: `u = gx + gy` runs
## down the screen and `v = gx - gy` runs across it, so a screen-aligned rectangle is a box in
## (u, v) and a nightmare in (x, y).
const PEDESTAL_AT := Vector2i(40, 66)
const PEDESTAL_HALF_U := 10
const PEDESTAL_HALF_V := 6

const BASE_1 := Vector2i(6, 6)
const BASE_2 := Vector2i(70, 74)

const NEARBY := [
	[&"res.tree", 8], [&"res.gold_mine", 2], [&"res.stone", 2], [&"res.berry_bush", 3],
]


func _ready() -> void:
	# SAND IS THE BOARD AND GRASS IS THE EXCEPTION, which is the low ground / high ground
	# reading the samples use. The plateaus paint their own interiors back to grass.
	var data := MapData.create(BOARD, SimMap.Terrain.SAND)
	data.meta = {
		"format_version": MapData.FORMAT_VERSION,
		"name": MAP_NAME,
		"players": 2,
		"size_players": 2,
		"authored_by": "preview_cliff_variants",
		"note": "every cliff piece. Plateau A has a corner piece, plateau B has none.",
	}

	_bases(data)
	_scaffolding(data)

	var cliffs := 0
	for p in PLATEAUS:
		cliffs += _plateau(data, p["high"] as Rect2i, int(p["length"]), bool(p["corner"]))
	cliffs += _pedestal(data, PEDESTAL_AT, PEDESTAL_HALF_U, PEDESTAL_HALF_V)

	print("Cliff variants map: %dx%d, %d cliff entities, %d entities in all"
			% [data.size.x, data.size.y, cliffs, data.entities.size()])

	var problems := MapValidator.problems(data)
	for p in problems:
		print("  ! %s" % p)
	_report_overlaps(data)

	var dir := SavedMaps.SAVE_ROOT.path_join(SaveFile.slugify(MAP_NAME))
	var write := MapFile.save(data, dir, {
		"name": MAP_NAME,
		"saved_at": int(Time.get_unix_time_from_system()),
	})
	if not write.is_empty():
		print("  ! could not write it: %s" % "; ".join(write))
		get_tree().quit(1)
		return

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


# ── the plateaus ────────────────────────────────────────────────────────────


## One closed ring of cliff around `high`. Returns how many pieces it laid.
##
## ## 📐 WHICH EDGE GETS WHICH PIECE, AND IT IS THE ART SIDE'S TABLE READ THROUGH AN ENTITY
##
## Their rule is addressed by the HIGH tile and keyed on which NEIGHBOUR is low:
##
##     low neighbour  (0, +1) +y -> cliff_face  stored 5   |  the two NEAR edges: the face
##     low neighbour  (+1, 0) +x -> cliff_face  stored 3   |  falls down-screen onto the
##                                                         |  low ground in front, correctly
##     low neighbour  (0, -1) -y -> cliff_back  stored 1   |  the two FAR edges: the same
##     low neighbour  (-1, 0) -x -> cliff_back  stored 7   |  fall would land on the plateau
##                                                         |  itself, so no face, just crest
##
## ⛔ **NO YAW FIXES THE FAR EDGES AND IT IS NOT WORTH RE-OPENING.** It is gravity in screen
## space, not an orientation. Nor is there an N-S cliff face: that face's normal is
## perpendicular to the view direction, so it is invisible at any span -- which is why a
## north-south boundary is drawn as an axis run and that is CORRECT rather than a stopgap.
##
## ⛔ **EVERY EDGE RUNS ITS FULL LENGTH, AND THE CORNERS ARE SHARED RATHER THAN GIVEN AWAY.**
## The first version inset the columns by a tile at each end so that no tile held two
## entities, and the owner photographed the result: *"the east corner has a gap, i see single
## tile cliffs in that spot."* Both halves followed from the inset -- the gap is the tile the
## face column never reached, and the single-tile pieces are what a greedy cover leaves when
## a run is a tile short of a multiple.
##
## So a corner tile carries two pieces now. `MapValidator._overlapping_entities` allows it
## for cliffs specifically, and its comment has the argument: a cliff never despawns, so
## nothing depends on which of the two ids the occupancy cell ends up holding, and both of
## them block anyway.
func _plateau(data: MapData, high: Rect2i, length: int, corner_piece: bool) -> int:
	data.set_terrain_rect(high, SimMap.Terrain.GRASS)
	data.add_area(&"plateau_%d" % length, high)

	var x0 := high.position.x
	var y0 := high.position.y
	var x1 := high.end.x - 1
	var y1 := high.end.y - 1
	var laid := 0

	# The two FAR edges, crest only -- no face, because that fall would land on the plateau's
	# own tiles and no yaw fixes gravity in screen space.
	laid += _row(data, BACK, WallPlan.AXIS_X, Vector2i(x0, y0), high.size.x, length)
	laid += _col(data, BACK, WallPlan.AXIS_Y, Vector2i(x0, y0), high.size.y, length)

	# The two NEAR edges, the face.
	laid += _row(data, FACE, WallPlan.AXIS_X, Vector2i(x0, y1), high.size.x, length)
	laid += _col(data, FACE, WallPlan.AXIS_Y, Vector2i(x1, y0), high.size.y, length)

	if corner_piece:
		# THE NEAR-NEAR CORNER, ADDRESSED BY THE HIGH TILE. There is no notch tile here --
		# both diagonal neighbours are low -- so the low-tile rule that places a diagonal
		# piece along an E-W run finds nothing, and the art side's note is that the piece
		# was already right and only the OWNER of it was wrong. It stands 1.414 m toward
		# +x+y of its anchor, which is the tile's south vertex, which is where the wedge is.
		data.add_entity(&"building.cliff_face_diag", 0, Vector2i(x1, y1), 0, WallPlan.AXIS_X)
		laid += 1
	return laid


## Cover `span` tiles along +x from `at`, using `piece`-tile pieces and nothing else.
##
## ⛔ **NO GREEDY COVER, AND THAT IS THE FIX RATHER THAN A SIMPLIFICATION.** This used to fill
## longest-first the way `WallPlan` does -- 12 tiles as 9 + 3 -- and the owner photographed
## the seam. A cliff piece is a WINDOW onto one continuous strip of rock and every piece
## opens its window at u = 0, so two pieces of different lengths restart the rock at
## unrelated places and the silhouette steps sideways. Same length throughout, or slits.
##
## ⚠️ A span that is not a multiple of `piece` would leave a short tail, which is exactly
## what is being avoided -- so it is REFUSED OUT LOUD rather than quietly filled. Getting a
## plateau size wrong in this file must not produce the artefact this file exists to show.
func _row(data: MapData, family: Dictionary, axis: int, at: Vector2i, span: int,
		piece: int) -> int:
	if span % piece != 0:
		print("  ! a %d-tile edge cannot be covered by %d-tile pieces" % [span, piece])
		return 0
	var laid := 0
	var offset := 0
	while offset < span:
		var tile := at + Vector2i(offset, 0) if axis == WallPlan.AXIS_X \
				else at + Vector2i(0, offset)
		data.add_entity(family[piece] as StringName, 0, tile, 0, axis)
		offset += piece
		laid += 1
	return laid


## The same along +y. Split from `_row` only so each call site reads as the edge it is.
func _col(data: MapData, family: Dictionary, axis: int, at: Vector2i, span: int,
		piece: int) -> int:
	if span % piece != 0:
		print("  ! a %d-tile edge cannot be covered by %d-tile pieces" % [span, piece])
		return 0
	var laid := 0
	var offset := 0
	while offset < span:
		data.add_entity(family[piece] as StringName, 0, at + Vector2i(0, offset), 0, axis)
		offset += piece
		laid += 1
	return laid


# ── the pedestal: a plateau square on the SCREEN rather than on the grid ────


## Is this tile inside the pedestal's high ground?
##
## In `(u, v) = (gx + gy, gx - gy)`, where the shape is a box. `u` counts steps DOWN the
## screen and `v` steps ACROSS it -- `Iso._project` halves y, so a step of (+1, +1) is
## (0, +32) px and one of (+1, -1) is (+64, 0).
func _high(t: Vector2i, c: Vector2i, hu: int, hv: int) -> bool:
	return absi((t.x + t.y) - (c.x + c.y)) <= hu \
			and absi((t.x - t.y) - (c.x - c.y)) <= hv


## A LOW tile whose `-x` and `-y` neighbours are both high: the notch along a NEAR E-W edge.
##
## ⚠️ **ONE PER TILE, THE WHOLE LENGTH OF THE RIDGE -- NOT ONCE PER PLATEAU.** On an E-W run
## the boundary tiles touch only at their CORNERS, so between every consecutive pair there is
## a tile with two faces hanging from its upper edges and nothing covering the triangle
## between them. That is why it first looked like a corner bug.
func _near_notch(t: Vector2i, c: Vector2i, hu: int, hv: int) -> bool:
	return not _high(t, c, hu, hv) \
			and _high(t + Vector2i(-1, 0), c, hu, hv) \
			and _high(t + Vector2i(0, -1), c, hu, hv)


## The same on a FAR E-W edge, where the crest goes.
func _far_notch(t: Vector2i, c: Vector2i, hu: int, hv: int) -> bool:
	return not _high(t, c, hu, hv) \
			and _high(t + Vector2i(1, 0), c, hu, hv) \
			and _high(t + Vector2i(0, 1), c, hu, hv)


## The screen-aligned plateau, built by CLASSIFYING EVERY TILE rather than by walking edges.
##
## ## ⛔ WHY THIS IS NOT `_plateau` WITH DIFFERENT NUMBERS
##
## `_plateau` walks four straight runs because a grid-aligned plateau HAS four straight runs
## and wants long pieces along them. This shape has none: its two E-W edges are chains of
## notch tiles stepping (+1, -1), and its two N-S edges are staircases stepping (+1, +1). Every
## edge is one tile at a time, so the art's three placement rules are applied per tile and the
## shape falls out of them instead of being drawn by hand.
##
## ## 📐 THE THREE RULES, AND THE ONE THAT IS EASY TO GET BACKWARDS
##
##   - a **LOW notch** tile gets the diagonal piece -- `face_diag` near, `back_diag` far;
##   - a **HIGH** tile with exactly one low neighbour gets that side's axis piece;
##   - a **HIGH** tile with two low neighbours and NO notch beside it gets the diagonal piece
##     instead, addressed by the high tile. That is the outer-corner rule.
##
## ⚠️ **THE THIRD IS GUARDED ON THERE BEING NO NOTCH, AND WITHOUT THAT GUARD EVERY TILE OF
## THIS SHAPE'S NEAR EDGE WOULD DRAW TWICE.** On a screen-aligned plateau a near-edge tile has
## BOTH its +x and +y neighbours low -- it looks exactly like an outer corner -- and the notch
## beside it is already covering the gap. A grid-aligned plateau's near corner has no such
## notch, which is the case the rule exists for.
##
## ## ⚠️ THE N-S SIDES ARE THE AXIS PIECES, WHICH IS THE WHOLE POINT OF THIS FUNCTION
##
## A tile on the screen-right edge has its **+x** neighbour low, so it takes `cliff_face` on
## `AXIS_Y` (stored 3); the screen-left edge has **-x** low and takes `cliff_back` on `AXIS_Y`
## (stored 7). Consecutive tiles step (+1, +1), which is straight down the screen, so a
## one-tile piece per step is the staircase. **There is no north-south cliff face to use
## instead and there never will be** -- its normal is perpendicular to the view direction, so
## it is invisible at any span.
func _pedestal(data: MapData, c: Vector2i, hu: int, hv: int) -> int:
	var reach := hu + hv + 3
	# GROUND FIRST, so the faces are not overdrawn -- the art side's constraint, and it binds
	# here because a cliff piece lives entirely outside its own cell.
	for y in range(c.y - reach, c.y + reach + 1):
		for x in range(c.x - reach, c.x + reach + 1):
			var t := Vector2i(x, y)
			if data.in_bounds(t) and _high(t, c, hu, hv):
				data.set_terrain(t, SimMap.Terrain.GRASS)
	data.add_area(&"pedestal", Rect2i(c - Vector2i(reach, reach),
			Vector2i(reach * 2 + 1, reach * 2 + 1)))

	var laid := 0
	for y in range(c.y - reach, c.y + reach + 1):
		for x in range(c.x - reach, c.x + reach + 1):
			var t := Vector2i(x, y)
			if not data.in_bounds(t):
				continue
			if _near_notch(t, c, hu, hv):
				data.add_entity(&"building.cliff_face_diag", 0, t, 0, WallPlan.AXIS_D2)
				laid += 1
			if _far_notch(t, c, hu, hv):
				data.add_entity(&"building.cliff_back_diag", 0, t, 0, WallPlan.AXIS_D2)
				laid += 1
			if not _high(t, c, hu, hv):
				continue

			var hx := _high(t + Vector2i(1, 0), c, hu, hv)
			var hy := _high(t + Vector2i(0, 1), c, hu, hv)
			var hnx := _high(t + Vector2i(-1, 0), c, hu, hv)
			var hny := _high(t + Vector2i(0, -1), c, hu, hv)

			# WHICH SCREEN SIDE ACTUALLY GOT A FACE. `+x` and `-y` are BOTH the screen-right
			# side of a tile -- its lower-right and upper-right edges -- and `+y` and `-x` are
			# both the screen-left. A grid-aligned plateau never has a drop on both edges of
			# one side, so the two halves can be classified independently there. This shape
			# does, on every tile of both N-S runs, which is the artifact the owner reported.
			#
			# ⚠️ **SET BY THE BRANCH THAT RUNS, NOT BY THE NEIGHBOUR TEST.** Reading them off
			# `hx`/`hy` says "this side would have taken a face", which is a different claim at
			# a near corner: there both neighbours are low, so the corner branch runs and lays
			# a DIAGONAL or nothing at all -- and suppressing the crest on the strength of a
			# face that was never laid is what emptied the two near corners.
			var faced_right := false
			var faced_left := false

			if not hx and not hy:
				# ⛔ **SUPPRESSED ONLY WHEN BOTH SIDES ARE NOTCHES, NOT EITHER.** A notch beside
				# this tile covers the gap on THAT side alone. Along the near run both sides
				# have one and the corner piece really is redundant; at the run's END one side
				# is off the plateau and has none, so the old `and` of two `not`s stood the
				# whole corner down over a single covered side. That is the missing corner.
				if not (_near_notch(t + Vector2i(1, 0), c, hu, hv) \
						and _near_notch(t + Vector2i(0, 1), c, hu, hv)):
					data.add_entity(&"building.cliff_face_diag", 0, t, 0, WallPlan.AXIS_D2)
					laid += 1
			elif not hx:
				data.add_entity(&"building.cliff_face", 0, t, 0, WallPlan.AXIS_Y)
				faced_right = true
				laid += 1
			elif not hy:
				data.add_entity(&"building.cliff_face", 0, t, 0, WallPlan.AXIS_X)
				faced_left = true
				laid += 1

			if not hnx and not hny:
				# The crest's own corner, and the same `both` rule for the same reason.
				if not (_far_notch(t + Vector2i(-1, 0), c, hu, hv) \
						and _far_notch(t + Vector2i(0, -1), c, hu, hv)):
					data.add_entity(&"building.cliff_back_diag", 0, t, 0, WallPlan.AXIS_D2)
					laid += 1
			# ⛔ **A CREST IS SUPPRESSED WHERE ITS OWN SCREEN SIDE ALREADY CARRIES A FACE**, and
			# without this every tile of an N-S run draws both, from the same anchor. Measured
			# off the atlas: `cliff_face` stored 3 is 54 px wide and reaches 103 px below its
			# anchor while the run advances only 32 px a tile, so the faces alone overlap more
			# than 3:1 and already cover the side solid. The crest laid over them is the
			# repeating rubble seam down the middle of the owner's red boxes -- it was never a
			# gap being filled, it is a second piece on top of a finished wall.
			elif not hnx and not faced_left:
				data.add_entity(&"building.cliff_back", 0, t, 0, WallPlan.AXIS_Y)
				laid += 1
			elif not hny and not faced_right:
				data.add_entity(&"building.cliff_back", 0, t, 0, WallPlan.AXIS_X)
				laid += 1
	return laid


# ── the checks ──────────────────────────────────────────────────────────────


## Build the reloaded map into a real world and report what actually stood up.
##
## `preview_wall_variants`' check, and it earns its place here twice over: the pieces are
## spawned FORCED, so two written onto one tile stack silently -- and a plateau is a ring of
## near-identical entities where a missing one is invisible. It also reports the FACING
## histogram, which is the only automatic evidence that the sim facings in buildings.json
## resolve to the stored frames the art side measured.
func _check_world(data: MapData) -> bool:
	var cfg := MatchConfig.debug_skirmish()
	cfg.map_size = data.size
	cfg.map_data = data
	var w := SimWorld.new()
	w.setup(cfg)
	MapGen.build(w, cfg)
	w.step()

	var wanted := 0
	for e in data.entities:
		if String(e["def_id"]).begins_with("building.cliff"):
			wanted += 1

	var standing := 0
	var by_frame := {}
	var blocked := 0
	for e in w.entities.values():
		if not (e is SimBuilding) or not String(e.def_id).begins_with("building.cliff"):
			continue
		var b: SimBuilding = e
		if not b.alive or not b.is_complete():
			continue
		standing += 1
		# The SPRITE index, not the sim facing -- that is the number the art side's table is
		# written in, so printing the sim facing here would be the one thing guaranteed not
		# to be comparable with what they measured.
		var sprite := posmod(7 - b.facing, 8)
		var key := "%s stored %d" % [String(b.def_id).trim_prefix("building."), sprite]
		by_frame[key] = int(by_frame.get(key, 0)) + 1
		# ⛔ **EVERY TILE OF THE FOOTPRINT, NOT THE ORIGIN.** The first version of this check
		# asked about `origin_tile()` alone and reported all 60 cliffs blocking while a nine
		# tile piece could have been open on eight of them -- a green check over a hole, which
		# is the exact shape of failure the rest of this file is written against. The owner
		# found it by walking a villager onto one.
		var open_tiles := 0
		for t in _tiles_of(b):
			if w.map != null and w.map.is_passable(t, SimMap.Domain.LAND):
				open_tiles += 1
		if open_tiles == 0:
			blocked += 1
		else:
			print("    ! %s at %v leaves %d of %d tiles walkable"
					% [b.def_id, b.origin_tile(), open_tiles, _tiles_of(b).size()])

	var keys := by_frame.keys()
	keys.sort()
	for k in keys:
		print("    %-28s %d" % [k, by_frame[k]])

	var ok := true
	if standing != wanted:
		print("  ! %d cliffs in the file and %d standing -- pieces are overlapping"
				% [wanted, standing])
		ok = false
	if blocked != standing:
		print("  ! %d of %d cliffs do not block land movement" % [standing - blocked, standing])
		ok = false
	# THE DRAGON HAS TO GET OVER THEM, which is the owner's rule and the only half of the
	# passability story a land check cannot see. Asked of the same grid, one domain apart.
	var air_blocked := 0
	for e in w.entities.values():
		if e is SimBuilding and String(e.def_id).begins_with("building.cliff"):
			if w.map != null and not w.map.is_passable(
					(e as SimBuilding).origin_tile(), SimMap.Domain.AIR):
				air_blocked += 1
	if air_blocked > 0:
		print("  ! %d cliffs block AIR -- the dragon cannot fly over them" % air_blocked)
		ok = false
	if not _all_visible(w):
		ok = false
	if ok:
		print("  all %d cliffs stood up, block land, pass air, and are lit" % standing)
	return ok


## ⛔ IS EVERY CLIFF ACTUALLY VISIBLE TO PLAYER 1 ON THE FIRST TICK?
##
## **THE CHECK THAT WAS MISSING, AND ITS ABSENCE IS THE WHOLE OF THE LAST BUG.** Every
## previous check here asked whether a piece EXISTED -- it stood up, it blocked, it faced the
## right way -- and all of them passed while the owner could not see a single diagonal cliff,
## because they were eighty tiles into unexplored fog. *A review map that reports itself
## correct and shows the reviewer nothing is worse than one that fails.*
##
## Asked of `SimPlayer`'s own vision grid rather than of tile distances, so it measures what
## the renderer will actually draw and moves automatically if `VisionSystem`'s radius rule
## ever changes.
func _all_visible(w: SimWorld) -> bool:
	var p := w.player_for(1)
	if p == null:
		print("  ! there is no player 1 to see anything")
		return false
	# ⚠️ **AN EMPTY GRID MEANS "NO FOG" AND NOT "ALL DARK"** -- `SimPlayer.vision`'s own rule,
	# and it is exactly the trap this check exists to avoid falling into from the other side.
	# `VisionSystem` allocates on its first tick, so a world that has never been stepped would
	# report every cliff lit. The caller steps first; this refuses to answer if it did not.
	if p.vision.is_empty() or w.map == null:
		print("  ! no fog grid yet -- step the world before asking what is lit")
		return false
	var dark := 0
	var first := Vector2i.ZERO
	for e in w.entities.values():
		if not (e is SimBuilding) or not String(e.def_id).begins_with("building.cliff"):
			continue
		var b: SimBuilding = e
		var lit := false
		for t in _tiles_of(b):
			var i := w.map.index_of(t)
			if i >= 0 and i < p.vision.size() and p.vision[i] != SimPlayer.Fog.UNSEEN:
				lit = true
				break
		if not lit:
			if dark == 0:
				first = b.origin_tile()
			dark += 1
	if dark > 0:
		print("  ! %d cliffs are in the dark, the first at %v -- move a tower or the showcase"
				% [dark, first])
		return false
	return true


## Every tile a standing building claims, read off the entity rather than off the def --
## the whole point being that a cliff's footprint is OVERRIDDEN at spawn by the map's axis,
## so asking the def would ask the wrong question.
func _tiles_of(b: SimBuilding) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var origin := b.origin_tile()
	for y in range(origin.y, origin.y + maxi(1, b.footprint.y)):
		for x in range(origin.x, origin.x + maxi(1, b.footprint.x)):
			out.append(Vector2i(x, y))
	return out


## Name the tiles two entities both claim, and who is on them.
##
## ⚠️ **`MapValidator` COUNTS THEM AND A COUNT IS USELESS HERE.** *"1 entity tiles overlap
## another entity"* on a map of 144 entities is a sentence you cannot act on -- and this file
## is exactly where it happens, because the plateau geometry is arithmetic in constants at the
## top and a tower an author nudges by two tiles lands on a cliff footprint that extends three
## tiles past the plateau it belongs to. The validator is right to stay terse; a dev tool that
## generates the map is the place to say which tile.
func _report_overlaps(data: MapData) -> void:
	var owner_of: Dictionary = {}
	for e in data.entities:
		for t in MapData.footprint_rect_of(e):
			if owner_of.has(t):
				print("  ! %v is claimed by both %s and %s"
						% [t, owner_of[t], e["def_id"]])
			else:
				owner_of[t] = e["def_id"]


## Player 1's watch towers over the showcase, and one dragon.
##
## ## ⛔ WITHOUT THIS THE MAP IS BLACK, AND THAT IS WHAT THE OWNER SAW
##
## *"still no diagonal cliffs on test map?"* -- every piece was there and none of it was
## lit. `VisionSystem` lights tiles around ALLIED entities only, a cliff is gaia with
## `los: 0`, so a showcase of gaia scenery reveals nothing about itself however close you
## stand. There is no reveal flag in `MatchConfig` to reach for instead.
##
## THE DRAGON IS NOT DECORATION EITHER. It flies (`domain: air`) at speed 220 with `los: 12`,
## so it is the fastest way to look along a run -- and flying it AT a cliff is the live test
## of the two air rules this card added: `SimMap.is_passable` answers AIR before it reads
## occupancy, so it crosses; and `GameView._refresh_occlusion` exempts fliers, so it is never
## haloed behind the rock it is passing over.
func _scaffolding(data: MapData) -> void:
	for at in WATCH_TOWERS:
		data.add_entity(&"building.watch_tower", 1, at)
	data.add_entity(&"unit.dragon", 1, BASE_1 + Vector2i(12, 2))


func _bases(data: MapData) -> void:
	for player in [1, 2]:
		var tc: Vector2i = BASE_1 if player == 1 else BASE_2
		data.add_entity(&"building.town_center", player, tc)
		data.starts.append(tc + Vector2i(5, 5))
		for i in 3:
			data.add_entity(&"unit.villager", player, tc + Vector2i(10 + i, 4))

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
