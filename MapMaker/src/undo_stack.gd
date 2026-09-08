## The undo and redo stacks (PLAN.md 16.2a), and where the last save sits between them.
##
## Two lists of `MapEdit`s. Undo moves one from `_done` to `_undone`; redo moves it back; a new
## act discards `_undone` entirely. That last rule is the universal one and is worth naming
## because it is a deletion: an author who undoes three placements and then paints a tile has
## given up those three, and every editor ever written works this way — a redo stack that
## survived a new act would offer to re-apply changes to a map that has since moved on.
##
## ## WHY IT IS ITS OWN CLASS AND NOT TWO ARRAYS ON `MapDocument`
##
## The save point. `MapDocument.dirty` is read by the status line and will be read by a
## "you have unsaved work" prompt, and **the honest answer is not "has anything been done" but
## "is the map different from the file"** — which changes when you undo back past your last
## save as well as when you edit. That needs one more piece of state than a bool, it has three
## edge cases (below), and none of them belongs in the middle of a document.
class_name UndoStack
extends RefCounted

## How many steps are kept.
##
## **A DRAG IS ONE STEP** (`MapDocument.begin_stroke()`), so this is 100 deliberate acts and
## not 100 tiles — a session's worth of mistakes with room over. The cost is bounded by the
## entity snapshots rather than by the terrain diffs: a full eight-player map carries a few
## hundred entity entries, so a step that touches them holds two copies of that (call it 150 KB
## on a busy map) while a paint step holds 6 bytes per tile it changed. A hundred
## entity-touching steps back to back is therefore the worst case and is a few megabytes on a
## PC-only tool — but if this ever needs raising, that arithmetic is the thing to redo, not
## this number in isolation.
const LIMIT := 100

var _done: Array[MapEdit] = []
var _undone: Array[MapEdit] = []

## `_done.size()` at the moment the map last matched its file, or -1 when that state can no
## longer be reached. See `mark_clean()` and `push()`.
var _clean_at := -1


func can_undo() -> bool:
	return not _done.is_empty()


func can_redo() -> bool:
	return not _undone.is_empty()


func undo_label() -> String:
	return _done[_done.size() - 1].describe() if can_undo() else ""


func redo_label() -> String:
	return _undone[_undone.size() - 1].describe() if can_redo() else ""


func depth() -> int:
	return _done.size()


func redo_depth() -> int:
	return _undone.size()


## Record a step that has just been applied.
func push(step: MapEdit) -> void:
	# ⚠️ **THE SAVE POINT CAN BE IN THE BRANCH THIS ACT DISCARDS.** Save, undo twice, then paint:
	# the state that matched the file is two redos away and those redos are about to be thrown
	# out, so it is unreachable and the map must read as dirty from here on. Without this the
	# tool would go on claiming "no unsaved changes" at a depth that happens to match a number
	# describing a state nobody can get back to.
	if _clean_at > _done.size():
		_clean_at = -1
	_undone.clear()
	_done.append(step)
	while _done.size() > LIMIT:
		# THE OLDEST GOES, AND THE SAVE POINT SHIFTS WITH IT -- the depths are positions in this
		# list, so dropping the front renumbers every one of them. Falling off the front means
		# the file's state is no longer on the stack, which is exactly what -1 means.
		_done.remove_at(0)
		_clean_at = maxi(-1, _clean_at - 1)


## Take the most recent step off the undo stack, ready to be applied backwards.
##
## **THE STACK MOVES THE STEP AND THE CALLER APPLIES IT**, rather than this class taking a
## `MapData` and doing both. `MapDocument` owns the map and the dirty flag and is the only
## writer of either (its class comment is emphatic about it); handing the map in here would
## make this a second writer for no gain.
func take_undo() -> MapEdit:
	if not can_undo():
		return null
	var step: MapEdit = _done.pop_back()
	_undone.append(step)
	return step


func take_redo() -> MapEdit:
	if not can_redo():
		return null
	var step: MapEdit = _undone.pop_back()
	_done.append(step)
	return step


## The map now matches its file.
func mark_clean() -> void:
	_clean_at = _done.size()


## Whether the map matches the file. False when there has never been one.
func at_clean_point() -> bool:
	return _clean_at >= 0 and _done.size() == _clean_at


## Forget everything. For a new or freshly opened map — you cannot undo past "this is a
## different map", and offering to would apply a diff computed against a buffer that is gone.
func clear() -> void:
	_done.clear()
	_undone.clear()
	_clean_at = -1
