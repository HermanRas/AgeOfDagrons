## One undoable step (PLAN.md 16.2a): what a single act changed, and enough to put it back.
##
## ## WHY IT IS A BEFORE/AFTER RECORD AND NOT AN INVERTED COMMAND
##
## 16.2a's card describes undo as *"a list of those acts inverted"*, and for `paint` that is
## literally true — the inverse of painting a tile is painting it back. **It stops being true
## one row up.** `place_start` removes whatever the player had, then places a town centre, five
## villagers, a scout and a ring of resource nodes whose positions `StartLayout` chooses; its
## inverse is not an act the tool has, and re-deriving it would mean a second copy of
## `StartLayout`'s layout rules that had to stay in step with the first. `remove_start` is the
## same shape backwards.
##
## So a step records **state**, not intent: the bytes that changed and the lists that were
## rewritten. That also makes undo indifferent to what 16.4 and 16.5 add — a move cursor, an
## area brush, a wall drag are all "some tiles and some entities are different now".
##
## ## THE TWO HALVES ARE STORED DIFFERENTLY, AND THE ASYMMETRY IS MEASURED
##
##   - **terrain as a diff.** A 96x96 map is 9,216 bytes and a paint stroke touches maybe 200
##     of them, so a whole-buffer snapshot would be 9 KB per step of which 200 bytes matter.
##     Three parallel packed arrays cost 6 bytes per changed tile and nothing per unchanged one.
##   - **entities, starts, areas and conditions as whole snapshots.** The lists are tens to a few
##     hundred small dictionaries, and `place_start` rewrites an unpredictable slice of the
##     entities — recording *which* entries moved would be more code than copying the list, and
##     the code would have to be right about a slice nothing else in the tool computes.
##
## ✅ **AREAS (16.5) ARRIVED AS A THIRD SNAPSHOT AND NEEDED NOTHING ELSE**, which is what the
## claim above was written to predict: *"a move cursor, an area brush, a wall drag are all 'some
## tiles and some entities are different now'"*. It held. The one thing it did NOT cover is the
## `_copied()` note at the bottom of this file — see the ⚠️ there, and see why `MapData.areas` is
## a flat list of `{name, rect}` rather than a name with a list of rects.
##
## ⚠️ **CONDITIONS (16.6) ARRIVED AS A FOURTH AND ARE THE FIRST THAT IS NOT ON `MapData`**, which
## is the one place the claim above needed widening rather than merely holding: `undo_into()` and
## `redo_into()` now RETURN the condition list instead of assigning it, because a `MapData` is not
## where it lives. See `_objectives_was` for why it is in the history at all — the short version
## is that `dirty` would otherwise report unsaved work as saved.
##
## ⚠️ **UNDO WALKS THE TERRAIN DIFFS BACKWARDS, AND THAT IS LOAD-BEARING RATHER THAN TIDY.**
## Nothing today can record the same tile twice in one step — `MapDocument.paint()` returns
## early when the tile already holds the wanted kind, and the brush cannot change mid-stroke —
## but the day something can (a fill inside a stroke, a rect brush over a painted line), the
## earliest `before` is the one that has to win. Applying in reverse order gives that for free.
## Redo walks forwards for the mirror reason: the last `after` wins. **The alternative was a
## dictionary of seen indices**, which costs a hash entry per tile — 65,536 of them for a fill
## on the largest map — to buy what the loop direction already guarantees.
class_name MapEdit
extends RefCounted

## What this step did, in the author's words, for the Undo button and the notice line.
##
## **SET BY THE FIRST MUTATION IN THE STEP, not by whoever opened it** — see
## `MapDocument._open()`. A stroke is opened by a mouse-press, which does not yet know whether
## the author is about to paint sand or place a dock, so naming it there would mean a second
## copy of the labelling living next to the tool enum.
var label := ""

# ── terrain, as a diff ──────────────────────────────────────────────────────

## Row-major indices into `MapData.terrain`, in the order they were painted.
var _index := PackedInt32Array()
var _was := PackedByteArray()
var _now := PackedByteArray()

# ── entities, starts and areas, as snapshots ────────────────────────────────

## True once `lists_before()` has taken the "before"; `_closed` once `close()` has taken the
## "after". Both are needed: a step with a before and no after would, on REDO, assign an empty
## entity list — every building on the map deleted by pressing redo.
var _lists := false
var _closed := false
var _entities_was: Array[Dictionary] = []
var _entities_now: Array[Dictionary] = []
var _starts_was: Array[Vector2i] = []
var _starts_now: Array[Vector2i] = []

## The named regions (16.5), snapshotted with the other two.
##
## ⚠️ **THEY RIDE `lists_before()`/`close()` RATHER THAN A FLAG OF THEIR OWN, AND THAT IS WHAT
## MAKES A MIXED STEP CORRECT.** One act can touch two of the three — erasing a region and
## erasing an entity are separate acts today, but `_open()` joins whatever step is already open,
## so a stroke can hold both. Three parallel `_lists`-style flags would mean a step that recorded
## areas and not entities, and undoing it would assign an empty entity list. One gate, three
## snapshots, taken and sealed together.
var _areas_was: Array[Dictionary] = []
var _areas_now: Array[Dictionary] = []

## The map's authored win/lose conditions (16.6), snapshotted with the other three.
##
## ⚠️ **THE ONLY ONE OF THE FOUR THAT IS NOT ON `MapData`**, which is why `undo_into()` and
## `redo_into()` RETURN a list rather than assigning one: conditions live on `MapDocument` and
## reach the file through the sidecar header, because they are not part of what a map IS --
## `MapGen.build_from()` never reads them and `MapFile` never derives them. See
## `MapDocument.objectives`.
##
## ⛔ **THEY ARE IN THE HISTORY BECAUSE `dirty` WOULD OTHERWISE LIE, AND THAT IS THE WHOLE
## ARGUMENT.** The case against was real: undoing a condition edit changes nothing on the canvas,
## and `changes_anything()`'s header is about exactly that — *"a stack full of invisible acts is a
## Ctrl+Z that appears not to work"*. What settles it is `UndoStack._clean_at`. `MapDocument.undo()`
## recomputes `dirty` from `at_clean_point()`, so a condition edit kept OUTSIDE the stack would be
## erased from that reckoning: edit a row, paint a tile, undo the tile, and the tool would report
## no unsaved work with an unsaved condition sitting in it. **An invisible undo step is a
## confusion; a `dirty` flag that says "saved" about unsaved work is lost work.** The notice line
## naming the step (*"undo: add win condition"*) is what keeps the first from being silent.
##
## 📝 **AND `_copied()`'s ONE-LEVEL RULE STILL HOLDS FOR THESE** — checked against its ⛔
## paragraph rather than assumed. An objective record is `{subject, id, area, owner, owner_index,
## compare, value, output, text}`: every field is a string or an int, and there is no nested
## container to share with the live list.
var _objectives_was: Array[Dictionary] = []
var _objectives_now: Array[Dictionary] = []

## Whether anything actually happened. See `changes_anything()`.
var _changed := false


func _init(p_label: String) -> void:
	label = p_label


# ── recording ───────────────────────────────────────────────────────────────

## One tile went from `was` to `now`.
func terrain_change(index: int, was: int, now: int) -> void:
	# OUT-OF-RANGE INDICES ARE DROPPED RATHER THAN STORED. `MapData.index_of()` returns -1 off
	# the map, and a -1 in here would be an out-of-bounds write on undo -- a crash at the moment
	# the author is trying to recover work, which is the worst possible time for one.
	if index < 0:
		return
	_index.append(index)
	_was.append(was)
	_now.append(now)
	_changed = true


## Take the "before" of the entity list and the start list.
##
## **GUARDED, AND THE GUARD IS WHAT MAKES A STROKE WORK.** `place_start()` calls
## `remove_start()` inside its own step and both call this; a second snapshot would overwrite
## the original with a half-mutated state, so undoing a start placement would restore the map
## to the middle of it — the old cluster gone and the new one not yet there.
## ⚠️ **`objectives` IS A PARAMETER RATHER THAN A SECOND ENTRY POINT, AND THE ⚠️ ON
## `_areas_was` IS WHY.** One gate for all four snapshots: a `_lists`-style flag of its own
## would allow a step that recorded conditions and not entities, and undoing that step would
## assign an empty entity list -- every building on the map deleted by pressing Ctrl+Z.
func lists_before(data: MapData, objectives: Array[Dictionary]) -> void:
	if _lists:
		return
	_lists = true
	_entities_was = _copied(data.entities)
	_starts_was = data.starts.duplicate()
	_areas_was = _copied(data.areas)
	_objectives_was = _copied(objectives)


## Seal the step: take the "after" of anything it took a "before" of.
##
## ⚠️ **CALLED BY `MapDocument._flush()` AND NOWHERE ELSE**, which is what makes the pair
## impossible to half-record. Leaving it to each mutation would mean six call sites, and the
## one that got forgotten would push a step whose redo erases the map (see `_closed`).
func close(data: MapData, objectives: Array[Dictionary]) -> void:
	if not _lists or _closed:
		return
	_closed = true
	_entities_now = _copied(data.entities)
	_starts_now = data.starts.duplicate()
	_areas_now = _copied(data.areas)
	_objectives_now = _copied(objectives)
	# ⚠️ **A CHANGE THE SIZES CANNOT SEE MUST SAY SO ITSELF.** This test catches everything
	# today: entities and areas are only ever appended or dropped, and a start moving changes
	# `starts`. **16.4's move cursor is the first act that edits an entry IN PLACE** -- same
	# count, same starts, different tile -- and it has to call `mark_changed()`, or its step is
	# discarded as a no-op and a dragged building cannot be dragged back.
	#
	# 📝 **AREAS ARE COUNTED HERE AND NOTHING RENAMES ONE IN PLACE YET.** A rename would be the
	# same trap as the move -- same count, different name -- so if the Map Conditions screen
	# ever grows one, it owes `mark_changed()` exactly as the move does.
	#
	# ✅ **AND 16.6 ARRIVED AND OWED IT.** `MapDocument.set_objective()` edits a condition row in
	# place: same list length, different fields, invisible to the line below. It calls
	# `mark_changed()` for the move cursor's reason exactly -- without it, editing a win row from
	# `>= 5` to `>= 10` is a step discarded as a no-op, and the change cannot be taken back.
	if _entities_now.size() != _entities_was.size() or _starts_now != _starts_was \
			or _areas_now.size() != _areas_was.size() \
			or _objectives_now.size() != _objectives_was.size():
		_changed = true


## Say this step changed something the size test cannot see. See `close()`.
func mark_changed() -> void:
	_changed = true


## Whether this is worth putting on the stack at all.
##
## **A CLICK THAT CHANGED NOTHING IS NOT AN UNDO STEP.** `Clear start` on a player who has
## none, an erase on empty ground, a paint of the colour already there — each is a real act by
## the author and a no-op on the map, and a stack full of them is a Ctrl+Z that appears not to
## work because the thing it undid was invisible.
func changes_anything() -> bool:
	return _changed


func tile_count() -> int:
	return _index.size()


# ── applying ────────────────────────────────────────────────────────────────

## Put the map back the way it was. Returns the condition list as it was.
##
## ⚠️ **THE FOURTH LIST IS RETURNED RATHER THAN ASSIGNED, BECAUSE IT IS NOT ON `MapData`** --
## see `_objectives_was`. **`current` comes straight back when this step recorded no lists at
## all**, which is the same gate the other three sit behind: a paint step must leave the
## conditions alone rather than assign the empty list it never took a snapshot of.
func undo_into(data: MapData, current: Array[Dictionary]) -> Array[Dictionary]:
	_write_terrain(data, _was, true)
	if not (_lists and _closed):
		return current
	data.entities = _copied(_entities_was)
	data.starts = _starts_was.duplicate()
	data.areas = _copied(_areas_was)
	return _copied(_objectives_was)


## Do it again.
func redo_into(data: MapData, current: Array[Dictionary]) -> Array[Dictionary]:
	_write_terrain(data, _now, false)
	if not (_lists and _closed):
		return current
	data.entities = _copied(_entities_now)
	data.starts = _starts_now.duplicate()
	data.areas = _copied(_areas_now)
	return _copied(_objectives_now)


## Apply one side of the diff.
##
## ⚠️ **THE BUFFER IS PULLED OUT, WRITTEN, AND ASSIGNED BACK — never indexed through the
## property.** `data.terrain[i] = b` on another object's packed array is the classic Godot
## pitfall: a packed array is a value type, so depending on how the access compiles the write
## can land on a temporary copy and vanish, with no error. Doing it through a local and one
## assignment is correct whichever way that goes, and costs one copy-on-write of the buffer
## per undo rather than per tile.
##
## `backwards` is not a style choice — see the class comment.
func _write_terrain(data: MapData, values: PackedByteArray, backwards: bool) -> void:
	if _index.is_empty():
		return
	var terrain := data.terrain
	if backwards:
		for i in range(_index.size() - 1, -1, -1):
			terrain[_index[i]] = values[i]
	else:
		for i in _index.size():
			terrain[_index[i]] = values[i]
	data.terrain = terrain


## What the Undo button says it will take back.
##
## The tile count is on the paint steps and only there, because it is the one figure an author
## cannot see for themselves: "paint Water Deep" could be one tile or a whole coastline, and
## which of the two is about to come back is the question they are asking.
func describe() -> String:
	if _index.size() > 1:
		return "%s (%d tiles)" % [label, _index.size()]
	return label


## Each dictionary copied, not just the array.
##
## ⚠️ **`Array.duplicate()` IS SHALLOW**, so without this the snapshot and the live list would
## hold the same dictionaries — and 16.4's move cursor, which edits `e["tile"]` in place, would
## rewrite the snapshot along with the map. Undo would then restore the building to where it
## had just been dragged, which reads as undo being ignored rather than as aliasing.
##
## ⚠️ **ONE LEVEL IS ENOUGH AND THAT IS A PROPERTY OF THE FORMAT, NOT AN ASSUMPTION.** An
## entity's `tile` is a `Vector2i` and an area's `rect` is a `Rect2i` — both value types — and
## every other field in either record is a scalar. So there is **no nested container to reach**
## in anything this copies.
##
## ⛔ **THAT SENTENCE IS LOAD-BEARING AND 16.5 WAS ABLE TO BREAK IT.** The natural shape for a
## named region is `{name, rects: [...]}`, and one of those inside a snapshot would share its
## `rects` array with the live map: `data.areas` is a flat list of `{name, rect}` **partly for
## this reason**, and its own header says so. Anything added to either list from here on has to
## be checked against this paragraph — a nested array would make undo restore a region to
## wherever it had just been re-dragged, with nothing failing and no error anywhere near it.
static func _copied(list: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in list:
		out.append(e.duplicate())
	return out
