## What the local player currently has selected (PLAN.md 4.3). Phase 4.3.
##
## **Client-side only, and never sent.** Selection is not simulation state: two
## players looking at the same match select different things, and a selection that
## went over the wire would have to be in the state hash and would desync the
## moment one player tapped (PLAN.md 7.1). What crosses the wire is the COMMAND a
## selection produces -- `MoveCommand` carrying unit ids -- not the selection.
##
## Plain RefCounted with no Node and no signals of its own; `GameView` owns one and
## is what tells the views to draw a ring.
class_name Selection
extends RefCounted

## Selecting more than this at once is refused rather than truncated silently.
## Guards the box select at 4.x from handing a single command every unit on the
## map, which is a command that would not fit a snapshot and an order nobody meant.
const MAX_SELECTED := 60

var _ids: Array[int] = []


## The selected ids, in the order they were added. A copy, so a caller building a
## command cannot mutate the selection by holding onto it.
func current() -> Array[int]:
	return _ids.duplicate()


func size() -> int:
	return _ids.size()


func is_empty() -> bool:
	return _ids.is_empty()


func contains(id: int) -> bool:
	return _ids.has(id)


## The single selected entity, or 0. What the detail panel reads: a panel showing
## one unit's stats has nothing to say about twelve.
func primary() -> int:
	return _ids[0] if not _ids.is_empty() else 0


## Replace the selection. Returns the ids actually taken.
func set_selection(ids: Array[int]) -> Array[int]:
	_ids = []
	return add(ids)


func add(ids: Array[int]) -> Array[int]:
	for id in ids:
		if id != 0 and not _ids.has(id) and _ids.size() < MAX_SELECTED:
			_ids.append(id)
	return current()


func remove(id: int) -> void:
	_ids.erase(id)


func clear() -> void:
	_ids = []


## Drop anything no longer present -- a unit that died, or walked out of view and
## was released from the pool. Without this, an order built from a stale selection
## names entities the sim will reject, and the player sees nothing happen.
func retain_only(live_ids: Array) -> void:
	var kept: Array[int] = []
	for id in _ids:
		if live_ids.has(id):
			kept.append(id)
	_ids = kept
