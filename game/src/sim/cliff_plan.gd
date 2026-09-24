## Which cliff pieces a plateau's boundary is made of, derived from WHICH TILES ARE HIGH.
##
## ## ⛔ WHY THIS IS A CLASS AND NOT A HUNDRED LINES IN THE MAP EDITOR
##
## A plateau is roughly forty pieces chosen by three rules that are easy to state and easy to
## get subtly wrong -- the two that shipped wrong on 2026-09-22 and 2026-09-23 both looked
## right in code and were reported off a screenshot. There are now three callers who must
## agree about them: `preview_cliff_variants`, the MapMaker's plateau tool, and whatever the
## generator grows next. **Three implementations of a rule the owner checks by eye is how the
## corners went missing twice.** So the rules live here once and every caller asks.
##
## Takes a SET OF TILES rather than a `Rect2i`, which is what lets one function serve a
## grid-aligned plateau, a screen-aligned one and an arbitrary painted blob. The shape only
## ever enters through `high.has(t)`.
##
## ## 📐 THE THREE RULES, FROM THE ART SIDE, AND THE TWO CONDITIONS THEY DID NOT COME WITH
##
##   - a **LOW notch** tile -- one whose `-x` and `-y` are both high -- takes the diagonal
##     piece; the far version (`+x` and `+y` high) takes the crest diagonal;
##   - a **HIGH** tile with one low neighbour takes that side's axis piece;
##   - a **HIGH** tile with two low neighbours takes the diagonal instead: the outer corner.
##
## ⚠️ **THE FIRST EXTRA CONDITION: A CREST IS SUPPRESSED WHERE ITS OWN SCREEN SIDE ALREADY HAS
## A FACE.** `+x` and `-y` are BOTH the screen-right side of a tile -- its lower-right and
## upper-right edges -- and `+y` and `-x` are both the screen-left. A grid-aligned plateau
## never has a drop on both edges of one side, so the art side's rules could classify the two
## halves independently. A screen-aligned one has a drop on both, on every tile of both its
## N-S runs, and drew a face AND a crest from the same anchor. Measured off the atlas:
## `cliff_face` stored 3 is 54 px wide and reaches 103 px below its anchor while an N-S run
## advances 32 px a tile, so the faces alone overlap better than 3:1 and already cover the
## side solid. The crest over them was the owner's *"artifacts down the side"*.
##
## ⚠️ **THE SECOND: A CORNER IS STOOD DOWN ONLY WHEN BOTH ITS SIDES ARE NOTCHES.** A notch
## covers the gap on ITS OWN side alone. Along a run both sides have one and the corner piece
## really is redundant; at a run's END one side is off the plateau and has none, so testing
## either cancelled the whole corner over a single covered side. That was *"the corners are
## still missing"*.
##
## ## ⛔ ONE LENGTH PER RUN, AND IT IS NOT A GREEDY FILL
##
## `WallPlan` covers a wall run longest-first -- 12 tiles as 9 + 3. A cliff must not. **Every
## piece is a window onto ONE continuous 16 m strip of rock and every window opens at u = 0**,
## so two pieces of different lengths restart the rock at unrelated places and the silhouette
## steps sideways. The owner photographed that seam. `_length_for` therefore takes the largest
## rung that divides the run EXACTLY, and a run no rung divides is laid in 1-tile fillers --
## which is the stamped look, and is why `runs_of` reports the length it chose so a caller can
## tell an author to resize.
##
## ## 📌 TWO PIECES IN THREE BRING THEIR OWN BLOCKERS, FOR TWO UNRELATED REASONS
##
## A rectangular footprint cannot describe either of the shapes a cliff is actually drawn over,
## and `building.cliff_blocker` -- a 1x1 that blocks and draws nothing -- is how both are said.
## A **merged diagonal** claims too much and is therefore given none, laying blockers instead
## (below); a **face** claims a rectangle where its rock covers a SHEARED one, and is given the
## few tiles the shear leaves behind (`_shear_gap`). The crest needs neither: it is one tile
## deep, so its claim and its coverage are the same row.
##
## The long `_diag` pieces are art only: `blocks_movement` false with a `[1, 1]` footprint,
## because the rectangle around a 1-tile-wide diagonal is the N x N box around it. So merging
## `n` one-tile diagonals emits the art piece **plus `n` blockers**, and the ART GOES FIRST --
## `SimMap.set_occupied` assigns the blocking byte rather than merging into it, so a
## non-blocking piece landing on a tile a blocker already holds would open it again.
class_name CliffPlan
extends RefCounted

## The blocker that claims the ground a piece is drawn over but its footprint cannot reach.
## Draws nothing (`draws_nothing`).
const BLOCKER := &"building.cliff_blocker"

## ## ⛔ WHERE A PIECE'S ROCK ACTUALLY FALLS, MEASURED AND NOT DERIVED
##
## Every tile a 1-tile piece is drawn over, as offsets from the tile it stands on. A run covers
## the union of these over its own tiles, which is exact rather than approximate: a longer piece
## is the same 16 m strip of rock through a wider window, so its art is the union of the 1-tile
## windows it replaces. See `rock_tiles`.
##
## ⚠️ **THESE NUMBERS CAME OUT OF THE ATLAS AND THE PROJECTION, AND THREE HAND-DERIVATIONS
## BEFORE THEM WERE WRONG.** "3 tiles straight down" shipped twice and neither the tests nor the
## probe caught it, because all three carried the same premises. The premises that were wrong:
##
##   - **a sprite is anchored at its footprint's CENTRE**, not at the tile it stands on, so an
##     offset counted from the origin tile is already shifted before any projection;
##   - **the rock is two tiles wide, and a diagonal's is three** -- it was modelled as the single
##     `(1, 1)` line, which is where the horse was standing beside;
##   - **`AXIS_Y` is not `AXIS_X` mirrored.** Its band starts a tile to the `+x` side, so the
##     blockers for an N-S run were laid on tiles the rock never touched while the tiles it did
##     touch stayed open. That is the one the owner rode along after the first two fixes.
##
## ⛔ **`test_the_cover_tables_are_what_the_atlas_says` RE-MEASURES ALL OF THIS FROM THE STAGED
## ART** and is what keeps the table honest; this comment is only the reason it exists. Re-read
## them any time with `probe_saved_map.tscn -- coverage`.
const COVER_DEPTH := 4

## How deep a face def's own footprint reaches, from `buildings.json`. Named here because
## `_merge` has to know what a piece already holds before it can say what is still open.
const FOOTPRINT_DEPTH := 3

## The near face, by the axis it is laid on. Two columns, each `COVER_DEPTH` steps of `(1, 1)`.
const COVER_FACE := {
	WallPlan.AXIS_X: [Vector2i(-1, 1), Vector2i(0, 1)],
	WallPlan.AXIS_Y: [Vector2i(1, -1), Vector2i(1, 0)],
}

## The diagonal, which draws the same frame on every axis and is a column wider than a face.
const COVER_FACE_DIAG := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]

## The near side: 4 m of rock hanging down the screen. Keyed by run length in tiles.
const FACE := {
	1: &"building.cliff_face",
	3: &"building.cliff_face_short",
	6: &"building.cliff_face_medium",
	9: &"building.cliff_face_long",
}

## The far side, where the same fall would land on the high ground: a 1.88 m crest, no face.
const BACK := {
	1: &"building.cliff_back",
	3: &"building.cliff_back_short",
	6: &"building.cliff_back_medium",
	9: &"building.cliff_back_long",
}

## The E-W run and the outer corner, counted in DIAGONAL steps of 2.83 m.
##
## ⚠️ **NO 6, AND IT IS AN ART FACT RATHER THAN AN OMISSION.** An even-step run centres BETWEEN
## tiles, and `vis.cliff_*_diag_medium` is baked with its anchor at the sprite's centre -- 160 px
## along a run whose tiles sit every 64 px. No footprint can shift it back: `centre_of` offers
## only `size / 2`, and a +32 px screen-x shift needs a negative y size. A 6-run lays as 3 + 3.
const FACE_DIAG := {
	1: &"building.cliff_face_diag",
	3: &"building.cliff_face_diag_short",
	9: &"building.cliff_face_diag_long",
}

const BACK_DIAG := {
	1: &"building.cliff_back_diag",
	3: &"building.cliff_back_diag_short",
	9: &"building.cliff_back_diag_long",
}

## Whether a family's pieces claim the ground they are drawn over. Only the diagonals do not.
const ART_ONLY := [FACE_DIAG, BACK_DIAG]


## The plateau that is a box ON THE GRID, from the two tiles a drag ran between.
##
## ⚠️ **THIS IS THE ONE THAT LOOKS LIKE A DIAMOND**, because `Iso._project` turns the tile axes
## into the screen's NE-SW and NW-SE. An author dragging it is describing the ground in tile
## terms and watching a diamond grow, which is why the editor labels it by what it DRAWS
## ("Plato NE<->SW") rather than by what it is.
static func grid_aligned_tiles(a: Vector2i, b: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			out[Vector2i(x, y)] = true
	return out


## The `(u, v)` box two dragged tiles describe, as a `Rect2i` over tile ORIGINS: `position` is
## `(u0, v0)` and `end` is one past `(u1, v1)`, the way a `Rect2i` always reads.
##
## ⛔ **PUBLIC BECAUSE THE EDITOR DRAWS THE DRAG PREVIEW FROM IT AND MUST NOT WORK IT OUT
## SEPARATELY.** The owner reported the first version of exactly that fault -- *"the drag display
## does not match the area it generates"* -- when the preview was the normalised TILE rectangle
## and the write was this box. Two derivations of one shape is the same class of bug one level
## down, and this is the function that makes it impossible: the rectangle an author sees and the
## tiles they get are the same four numbers.
##
## ⚠️ **FROM THE RAW DRAG ENDS.** Normalising into a tile `Rect2i` first loses it: the corners of
## that box are not the corners the finger went between.
static func screen_box_of(a: Vector2i, b: Vector2i) -> Rect2i:
	var u0 := mini(a.x + a.y, b.x + b.y)
	var u1 := maxi(a.x + a.y, b.x + b.y)
	var v0 := mini(a.x - a.y, b.x - b.y)
	var v1 := maxi(a.x - a.y, b.x - b.y)
	return Rect2i(Vector2i(u0, v0), Vector2i(u1 - u0 + 1, v1 - v0 + 1))


## The plateau that is a box ON SCREEN: a rectangle in `(u, v) = (x + y, x - y)`, where `u` runs
## down the screen and `v` across it.
##
## ⚠️ **THIS IS THE ONE THAT LOOKS LIKE A SQUARE**, and it is the shape the owner's reference
## pedestal is. Its N-S sides are the axis staircase and its E-W sides are chains of notches, so
## it exercises every rule in this file at once -- which is also why it was where both placement
## faults showed up.
##
## ⛔ **`u` AND `v` ALWAYS SHARE A PARITY** (`u + v = 2x`), so half the pairs in the box are not
## tiles at all. Iterated in tile space and filtered rather than walked in `(u, v)`, which is
## what makes that impossible to get wrong; the range is widened by one because integer division
## truncates toward zero and the corners can be negative.
static func screen_aligned_tiles(a: Vector2i, b: Vector2i) -> Dictionary:
	var box := screen_box_of(a, b)
	var u0 := box.position.x
	var u1 := box.end.x - 1
	var v0 := box.position.y
	var v1 := box.end.y - 1
	var out: Dictionary = {}
	for y in range((u0 - v1) / 2 - 1, (u1 - v0) / 2 + 2):
		for x in range((u0 + v0) / 2 - 1, (u1 + v1) / 2 + 2):
			var u := x + y
			var v := x - y
			if u >= u0 and u <= u1 and v >= v0 and v <= v1:
				out[Vector2i(x, y)] = true
	return out


## Every piece a plateau of `high` tiles needs, as `{def_id, tile, axis}` records ready for
## `MapData.add_entity`.
##
## The order is load-bearing in one place and one only: a merged diagonal's art record comes
## immediately before the blockers that claim its tiles. See the class comment.
static func plan(high: Dictionary) -> Array[Dictionary]:
	return _merge(_drop_shadowed_runs(_classify(high)), high)


## One record per boundary tile, before any run is merged. Split out so a caller that wants
## the unmerged truth -- a test, or a tool drawing a preview overlay -- can have it.
static func _classify(high: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in _search_box(high):
		var hx := high.has(t + Vector2i(1, 0))
		var hy := high.has(t + Vector2i(0, 1))
		var hnx := high.has(t + Vector2i(-1, 0))
		var hny := high.has(t + Vector2i(0, -1))

		if not high.has(t):
			# A LOW tile: the notch between two high ones, addressed by the low tile because
			# on an E-W run the boundary tiles touch only at their corners and the triangle
			# between them belongs to neither.
			if hnx and hny:
				out.append(_rec(FACE_DIAG[1], t, WallPlan.AXIS_D2))
			if hx and hy:
				out.append(_rec(BACK_DIAG[1], t, WallPlan.AXIS_D2))
			continue

		# ⛔ **THREE INDEPENDENT RULES, NOT A CHAIN, AND A CORNER TAKES ITS EDGES' PIECES TOO.**
		# An `if/elif` here reads naturally and quietly shortens both near edges by a tile,
		# because a corner matches the first branch and never reaches the axis ones. That is
		# not a missing sprite -- the diagonal covers the wedge -- it is a RUN LENGTH fault: a
		# 9-tile edge becomes 8, 8 divides by no rung, and the whole edge reverts to 1-tile
		# fillers. The stamped repeat, arriving from the one direction nothing was watching.
		#
		# The art side's own note says so in as many words: *"both tables are live at once and
		# a tile can want entries from each."*
		#
		# ⚠️ **A SIDE IS SKIPPED WHEN THE LOW TILE ON IT IS A NOTCH**, because the notch's own
		# diagonal already covers that side. This is the single condition that makes one rule
		# serve both plateau shapes: a grid-aligned edge has no notches, so every tile takes
		# its face; a screen-aligned E-W edge is nothing BUT notches, so the high tiles take
		# none and the chain of diagonals is the edge.
		var near_x := _near_notch(t + Vector2i(1, 0), high)
		var near_y := _near_notch(t + Vector2i(0, 1), high)
		var far_x := _far_notch(t + Vector2i(-1, 0), high)
		var far_y := _far_notch(t + Vector2i(0, -1), high)

		# `+x` and `-y` are both the screen-RIGHT side of this tile; `+y` and `-x` the screen
		# LEFT. A drop on the side at all means something covers it -- this tile's face or the
		# neighbouring notch's diagonal -- and either way the crest must not go over it.
		var faced_right := not hx
		var faced_left := not hy

		if not hx and not near_x:
			out.append(_rec(FACE[1], t, WallPlan.AXIS_Y))
		if not hy and not near_y:
			out.append(_rec(FACE[1], t, WallPlan.AXIS_X))
		if not hx and not hy and not (near_x and near_y):
			out.append(_rec(FACE_DIAG[1], t, WallPlan.AXIS_D2))

		# ⚠️ **SHADOWING IS RECORDED HERE AND ACTED ON PER RUN, NOT PER TILE** -- see
		# `_drop_shadowed_runs`. Dropping a crest the moment its own tile carries a face is
		# locally correct and globally wrong.
		if not hnx and not far_x:
			out.append(_rec(BACK[1], t, WallPlan.AXIS_Y, faced_left))
		if not hny and not far_y:
			out.append(_rec(BACK[1], t, WallPlan.AXIS_X, faced_right))
		if not hnx and not hny and not (far_x and far_y):
			out.append(_rec(BACK_DIAG[1], t, WallPlan.AXIS_D2))
	return out


static func _rec(def_id: StringName, tile: Vector2i, axis: int,
		shadowed: bool = false) -> Dictionary:
	return {"def_id": def_id, "tile": tile, "axis": axis, "shadowed": shadowed}


## Drop a crest run only when EVERY tile of it stands behind a face on the same screen side.
##
## ## ⛔ WHY THIS IS A RUN QUESTION AND NOT A TILE QUESTION
##
## `+x` and `-y` are both a tile's screen-right side, so a tile can want a face and a crest at
## once. Suppressing the crest per tile is right on a SCREEN-ALIGNED plateau, where it happens
## on every tile of both N-S runs and the faces -- 54 px wide, 103 px of reach, 32 px of
## advance -- overlap better than 3:1 and cover the side solid. It is what fixed the owner's
## *"artifacts down the side"*.
##
## ⚠️ **AND IT IS WRONG AT A GRID-ALIGNED CORNER, WHERE THE TWO ARE LOCALLY IDENTICAL.** The
## shared corner of a 9x9 plateau has the same four neighbours as a staircase tile, so a
## per-tile rule cannot tell them apart -- and dropping that one crest takes the far row from
## 9 tiles to 8. 8 divides by no rung, so the whole row reverts to 1-tile fillers while the
## near edges opposite it stay one long piece. The stamped repeat again, on half the plateau.
##
## The runs tell them apart even though the tiles cannot. A staircase crest is shadowed on
## every tile of its run -- in fact each is a run of ONE, because consecutive staircase tiles
## step (+1, +1) and an `AXIS_X` run steps (1, 0). A far row is shadowed only at the corner
## where it meets the near column. So: all shadowed, drop; any clear, keep the run whole.
static func _drop_shadowed_runs(singles: Array[Dictionary]) -> Array[Dictionary]:
	var shadowed: Dictionary = {}
	for r in singles:
		shadowed[[r["def_id"], r["axis"], r["tile"]]] = bool(r.get("shadowed", false))

	var drop: Dictionary = {}
	for run in _runs(singles):
		var step := step_of(int(run["axis"]))
		var every := true
		for i in range(int(run["span"])):
			if not bool(shadowed.get([run["def_id"], run["axis"], run["start"] + step * i], false)):
				every = false
				break
		if not every:
			continue
		for i in range(int(run["span"])):
			drop[[run["def_id"], run["axis"], run["start"] + step * i]] = true

	var out: Array[Dictionary] = []
	for r in singles:
		if not drop.has([r["def_id"], r["axis"], r["tile"]]):
			out.append(r)
	return out


## A LOW tile whose `-x` and `-y` are both high: the notch along a NEAR E-W edge.
static func _near_notch(t: Vector2i, high: Dictionary) -> bool:
	return not high.has(t) and high.has(t + Vector2i(-1, 0)) and high.has(t + Vector2i(0, -1))


## The same on a FAR E-W edge, where the crest goes.
static func _far_notch(t: Vector2i, high: Dictionary) -> bool:
	return not high.has(t) and high.has(t + Vector2i(1, 0)) and high.has(t + Vector2i(0, 1))


## Every tile that could carry a piece: the plateau, plus one ring, because a notch stands on
## LOW ground outside it. Sorted, so a plan is reproducible and two runs of it compare equal.
static func _search_box(high: Dictionary) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if high.is_empty():
		return tiles
	var seen: Dictionary = {}
	for t in high:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				seen[(t as Vector2i) + Vector2i(dx, dy)] = true
	for t in seen:
		tiles.append(t)
	tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)
	return tiles


## The step between consecutive pieces of a run on each axis. A face laid on `AXIS_Y` runs
## along +y, and the diagonals run along the anti-diagonal (+1, -1), which is the screen E-W.
static func step_of(axis: int) -> Vector2i:
	match axis:
		WallPlan.AXIS_X: return Vector2i(1, 0)
		WallPlan.AXIS_Y: return Vector2i(0, 1)
		WallPlan.AXIS_D1: return Vector2i(1, 1)
		WallPlan.AXIS_D2: return Vector2i(1, -1)
	return Vector2i.ZERO


## The ladder a def belongs to, or `{}` for one that is not a cliff piece.
##
## ⚠️ **EVERY RUNG, NOT JUST THE 1-TILE ONE.** It matched `ladder[1]` alone for as long as its
## only callers were `_runs` and `_merge`, which ask before anything is merged and therefore
## never hold a `_long` or `_short` id. That is invisible until something asks about a FINISHED
## plan -- a test, a validator, an editor's overlay -- and then it answers `{}` for a real cliff
## piece, which reads as "not a cliff" rather than as a question it cannot answer. It cost a
## false failure the first time a test walked a merged plan.
static func ladder_of(def_id: StringName) -> Dictionary:
	for ladder in [FACE, BACK, FACE_DIAG, BACK_DIAG]:
		if (ladder as Dictionary).values().has(def_id):
			return ladder
	return {}


## The longest rung that divides `span` EXACTLY. Never a greedy fill -- see the class comment.
static func length_for(ladder: Dictionary, span: int) -> int:
	var rungs := ladder.keys()
	rungs.sort()
	rungs.reverse()
	for rung in rungs:
		if span % int(rung) == 0:
			return int(rung)
	return 1


## Maximal straight runs of identical 1-tile pieces, as `{def_id, axis, start, span, piece}`.
##
## ⚠️ **EACH RUN IS WALKED BACK TO ITS OWN START RATHER THAN TRUSTED TO ARRIVE IN ORDER.** The
## obvious version leans on `_search_box`'s sort and is wrong for exactly one axis: an
## `AXIS_D2` run steps (+1, -1), so in a list ordered by y the first record of it is its LAST
## tile, walking forward from there finds nothing, and every diagonal collapses to a run of
## one. That is the whole E-W edge silently reverting to 1-tile pieces -- the stamped look
## this ladder exists to avoid, and invisible in any test that only counted entities.
static func _runs(singles: Array[Dictionary]) -> Array[Dictionary]:
	var at: Dictionary = {}
	for r in singles:
		at[[r["def_id"], r["axis"], r["tile"]]] = true

	var used: Dictionary = {}
	var out: Array[Dictionary] = []
	for r in singles:
		var def_id: StringName = r["def_id"]
		var axis := int(r["axis"])
		if used.has([def_id, axis, r["tile"]]):
			continue
		var step := step_of(axis)

		var start: Vector2i = r["tile"]
		while at.has([def_id, axis, start - step]):
			start -= step

		var span := 0
		var cursor := start
		while at.has([def_id, axis, cursor]):
			used[[def_id, axis, cursor]] = true
			span += 1
			cursor += step

		var ladder := ladder_of(def_id)
		out.append({
			"def_id": def_id, "axis": axis, "start": start, "span": span,
			"piece": length_for(ladder, span) if not ladder.is_empty() else 1,
		})
	return out


## ⛔ **EVERY ART-ONLY PIECE IS EMITTED BEFORE EVERY BLOCKING ONE, ACROSS THE WHOLE PLATEAU.**
##
## `SimMap.set_occupied` ASSIGNS the blocking byte rather than merging into it, so a
## non-blocking entity spawned onto a tile something already blocks re-OPENS that tile. The
## first version of this only ordered art before blockers *within a run*, which is not enough
## and shipped: a plateau's runs share tiles at every corner, so one run's art landed on the
## previous run's blockers and quietly unblocked them. The owner walked a scout up a cliff.
##
## A global split is the whole fix and costs one extra array: after it, no non-blocking piece
## can ever follow a blocking one, whatever order the runs come out in. Draw order is unaffected
## because the pieces that move are the ones that draw nothing.
static func _merge(singles: Array[Dictionary], high: Dictionary) -> Array[Dictionary]:
	var art: Array[Dictionary] = []
	var out: Array[Dictionary] = []
	# Blockers are deduplicated because two sources now lay them -- a merged diagonal and a
	# face's shear -- and both reach the tiles around a corner. A second blocker on a tile is
	# harmless to collision and is still an entity the map carries and the view iterates.
	var blocked: Dictionary = {}
	for run in _runs(singles):
		var def_id: StringName = run["def_id"]
		var axis := int(run["axis"])
		var step := step_of(axis)
		var ladder := ladder_of(def_id)
		var piece := int(run["piece"])
		var art_only := ART_ONLY.has(ladder)
		var offset := 0
		while offset < int(run["span"]):
			var tile: Vector2i = run["start"] + step * offset
			var rec := _rec(ladder[piece] if not ladder.is_empty() else def_id, tile, axis)
			# A MERGED diagonal is the only piece that draws without claiming: the 1-tile one
			# blocks on its own and must not be given blockers as well.
			# WHAT THIS PIECE ALREADY CLAIMS, which is what decides where its rock still falls
			# unheld. A diagonal claims its LINE and only its line -- `[1, 1]` standing alone,
			# one blocker a tile when merged -- while an axis piece claims a `[length, DEPTH]`
			# rectangle, `perp` being the direction `MapData.footprint_rect_of` transposes into.
			var claimed: Dictionary = {}
			var perp := Vector2i.ONE - step
			for i in range(piece):
				if art_only:
					claimed[tile + step * i] = true
				else:
					for j in range(FOOTPRINT_DEPTH):
						claimed[tile + step * i + perp * j] = true

			if art_only and piece > 1:
				art.append(rec)
				for i in range(piece):
					_block(out, blocked, tile + step * i)
			else:
				out.append(rec)

			# ⛔ **BOTH FACE FAMILIES SHEAR, AND THE DIAGONAL IS THE WORSE OF THE TWO.** Its art
			# is `height_m` 4.0, the same wall of rock as an axis face, but its claim is a single
			# tile per step rather than a 3-deep rectangle -- so EVERY diagonal piece left two
			# tiles of rock walkable, the whole length of every screen-horizontal run. The owner
			# rode along one. The crests shear too and do not care: 1.88 m of rim covers the tile
			# it stands on and nothing below it.
			if ladder == FACE or ladder == FACE_DIAG:
				for t in rock_tiles(tile, axis, ladder, piece):
					if not claimed.has(t) and not high.has(t):
						_block(out, blocked, t)
			offset += piece
	return art + out


## Every tile a run of `length` pieces is DRAWN over, from `COVER_FACE` / `COVER_FACE_DIAG`.
##
## ## ⛔ WHY A RUN IS THE UNION OF ITS 1-TILE WINDOWS
##
## A merged piece is not different art: it is the same continuous 16 m strip of rock seen through
## a wider window, opened at the same `u = 0`. So a 9-tile face covers exactly what nine 1-tile
## faces laid along it would, and one measured table serves every rung. That also side-steps the
## trap in measuring a long frame directly -- a long diagonal's frame RECT is a huge box that is
## mostly transparent, and taking the rect for the rock would deny a quarter of the map.
##
## 📌 **THE OVER-CLAIM IS LEFT ALONE.** A face's `[length, 3]` footprint holds tiles with no rock
## over them -- its own lip among them -- and un-claiming those would mean taking the footprints
## off the defs and laying every piece on blockers. Much larger change, invisible reward: nobody
## can tell that a tile beside a cliff is denied for a slightly wrong reason, and anybody can tell
## that a horse is standing inside a rock.
##
## ⚠️ **A HIGH TILE IS NEVER BLOCKED** by the caller. On any plateau we lay, down-screen of a near
## face is off the plateau, so it never fires; on a painted concave blob it would, and walling off
## the top of someone's own plateau is not a thing this should be able to do.
static func rock_tiles(tile: Vector2i, axis: int, ladder: Dictionary,
		length: int = 1) -> Array[Vector2i]:
	var bases: Array = COVER_FACE_DIAG if ladder == FACE_DIAG else COVER_FACE.get(axis, [])
	var step := step_of(axis)
	var out: Array[Vector2i] = []
	for i in range(length):
		for b in bases:
			for d in range(COVER_DEPTH):
				out.append(tile + step * i + (b as Vector2i) + Vector2i.ONE * d)
	return out


## One blocker on `t`, unless something already put one there.
static func _block(out: Array[Dictionary], blocked: Dictionary, t: Vector2i) -> void:
	if blocked.has(t):
		return
	blocked[t] = true
	out.append(_rec(BLOCKER, t, WallPlan.AXIS_X))


## What `plan()` chose for each run. For a tool that wants to tell an author *"this edge is 8
## tiles, so it is laid in ones -- make it 9"*.
static func runs_of(high: Dictionary) -> Array[Dictionary]:
	return _runs(_drop_shadowed_runs(_classify(high)))
