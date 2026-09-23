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
## ## 📌 A MERGED DIAGONAL BRINGS ITS OWN BLOCKERS
##
## The long `_diag` pieces are art only: `blocks_movement` false with a `[1, 1]` footprint,
## because the rectangle around a 1-tile-wide diagonal is the N x N box around it. So merging
## `n` one-tile diagonals emits the art piece **plus `n` blockers**, and the ART GOES FIRST --
## `SimMap.set_occupied` assigns the blocking byte rather than merging into it, so a
## non-blocking piece landing on a tile a blocker already holds would open it again.
class_name CliffPlan
extends RefCounted

## The blocker that claims the ground under a long diagonal. Draws nothing (`draws_nothing`).
const BLOCKER := &"building.cliff_blocker"

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


## Every piece a plateau of `high` tiles needs, as `{def_id, tile, axis}` records ready for
## `MapData.add_entity`.
##
## The order is load-bearing in one place and one only: a merged diagonal's art record comes
## immediately before the blockers that claim its tiles. See the class comment.
static func plan(high: Dictionary) -> Array[Dictionary]:
	return _merge(_drop_shadowed_runs(_classify(high)))


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
static func ladder_of(def_id: StringName) -> Dictionary:
	for ladder in [FACE, BACK, FACE_DIAG, BACK_DIAG]:
		if (ladder as Dictionary)[1] == def_id:
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


static func _merge(singles: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
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
			# The ART FIRST and its blockers after, so the non-blocking piece cannot clear a
			# blocking byte the blocker beneath it has already set.
			out.append(_rec(ladder[piece] if not ladder.is_empty() else def_id, tile, axis))
			if art_only and piece > 1:
				for i in range(piece):
					out.append(_rec(BLOCKER, tile + step * i, WallPlan.AXIS_X))
			offset += piece
	return out


## What `plan()` chose for each run. For a tool that wants to tell an author *"this edge is 8
## tiles, so it is laid in ones -- make it 9"*.
static func runs_of(high: Dictionary) -> Array[Dictionary]:
	return _runs(_drop_shadowed_runs(_classify(high)))
