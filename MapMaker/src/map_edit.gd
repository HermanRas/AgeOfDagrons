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
##   - **entities and starts as whole snapshots.** The list is tens to a few hundred small
##     dictionaries, and `place_start` rewrites an unpredictable slice of it — recording *which*
##     entries moved would be more code than copying the list, and the code would have to be
##     right about a slice nothing else in the tool computes.
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

# ── entities and starts, as snapshots ───────────────────────────────────────

## True once `lists_before()` has taken the "before"; `_closed` once `close()` has taken the
## "after". Both are needed: a step with a before and no after would, on REDO, assign an empty
## entity list — every building on the map deleted by pressing redo.
var _lists := false
var _closed := false
var _entities_was: Array[Dictionary] = []
var _entities_now: Array[Dictionary] = []
var _starts_was: Array[Vector2i] = []
var _starts_now: Array[Vector2i] = []

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
func lists_before(data: MapData) -> void:
	if _lists:
		return
	_lists = true
	_entities_was = _copied(data.entities)
	_starts_was = data.starts.duplicate()


## Seal the step: take the "after" of anything it took a "before" of.
##
## ⚠️ **CALLED BY `MapDocument._flush()` AND NOWHERE ELSE**, which is what makes the pair
## impossible to half-record. Leaving it to each mutation would mean six call sites, and the
## one that got forgotten would push a step whose redo erases the map (see `_closed`).
func close(data: MapData) -> void:
	if not _lists or _closed:
		return
	_closed = true
	_entities_now = _copied(data.entities)
	_starts_now = data.starts.duplicate()
	# ⚠️ **A CHANGE THE SIZES CANNOT SEE MUST SAY SO ITSELF.** This test catches everything
	# today: entities are only ever appended or dropped, and a start moving changes `starts`.
	# **16.4's move cursor is the first act that will edit an entry IN PLACE** -- same count,
	# same starts, different tile -- and it has to call `mark_changed()`, or its step is
	# discarded as a no-op and a dragged building cannot be dragged back.
	if _entities_now.size() != _entities_was.size() or _starts_now != _starts_was:
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

## Put the map back the way it was.
func undo_into(data: MapData) -> void:
	_write_terrain(data, _was, true)
	if _lists and _closed:
		data.entities = _copied(_entities_was)
		data.starts = _starts_was.duplicate()


## Do it again.
func redo_into(data: MapData) -> void:
	_write_terrain(data, _now, false)
	if _lists and _closed:
		data.entities = _copied(_entities_now)
		data.starts = _starts_now.duplicate()


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
## `tile` is a `Vector2i` and every other field is a scalar, so one level is enough; there is
## no nested container in an entity entry to reach.
static func _copied(list: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in list:
		out.append(e.duplicate())
	return out
