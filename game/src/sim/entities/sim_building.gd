## A building (PLAN.md 6.2). Phase 2.3 -- enough to exist, be placed into the grid
## and be drawn; the behaviour that acts on it lands in phase 5.
##
## Buildings have no facing. Placement snaps to the grid without rotation
## (PLAN.md 5.1), which is why every building atlas is a single frame at
## `directions = 1` (ASSET_MISSING.md 1.2) and why there is no `facing` field here.
##
## `pos` is inherited from SimEntity and is in sub-tile units like everything
## else, but for a building it means **the centre of its footprint** rather than
## the centre of a tile. That keeps the view layer uniform -- it draws every
## entity at `Iso.sub_to_world(pos)` without asking what kind it is -- while
## `origin_tile()` recovers the top-left tile the footprint was placed at, which is
## what the grid cares about.
##
## Deliberately absent until their phases: the production queue (5.4) and garrison
## (4.8). Stubbing them now would mean inventing `ProductionOrder`'s shape before
## anything uses it.
class_name SimBuilding
extends SimEntity

enum Phase { FOUNDATION, UNDER_CONSTRUCTION, COMPLETE, DESTROYED }

var phase: Phase = Phase.FOUNDATION
var footprint: Vector2i = Vector2i.ONE

var build_progress: int = 0
var build_total: int = 0

var provides_pop: int = 0
var garrison_cap: int = 0

## Training queue (5.4). Each entry is {def_id, progress, total, ready, cost}.
## `cost` is snapshotted at enqueue time rather than re-read from UnitDef later,
## so a cancel always refunds exactly what was paid, even though nothing in MVP
## (no techs, no age discounts) would currently make the two disagree. Only the
## FRONT entry ever progresses -- one production line per building, same as
## every RTS this is modelled on -- so entries behind it need no state of their
## own until they reach the front.
var queue: Array[Dictionary] = []


## The top-left tile of the footprint. Derived from `pos` rather than stored, so
## the two can never disagree.
func origin_tile() -> Vector2i:
	var half := Vector2i(footprint.x * SimWorld.SUBTILE, footprint.y * SimWorld.SUBTILE) / 2
	return (pos - half) / SimWorld.SUBTILE


func footprint_rect() -> Rect2i:
	return SimMap.footprint_rect(origin_tile(), footprint)


## Sub-tile centre of the footprint whose top-left tile is `origin`. Static
## because SimWorld needs it to position a building before one exists.
static func centre_of(origin: Vector2i, p_footprint: Vector2i) -> Vector2i:
	var size := Vector2i(maxi(1, p_footprint.x), maxi(1, p_footprint.y))
	return origin * SimWorld.SUBTILE + Vector2i(size.x * SimWorld.SUBTILE, size.y * SimWorld.SUBTILE) / 2


## Advance construction. Returns true on the tick it completes, so 5.2 can fire
## `building.complete` audio and flip the visual without polling for the change.
##
## `hp` rises WITH build_fraction() rather than sitting at spawn_building()'s
## starting sliver for the whole construction -- found live (a session
## playtest) reporting a house stuck at 55/550 the entire time it was being
## built, only jumping to full at completion. The health bar is the only
## build-progress indicator SelectionPanel currently draws (5.6), so it has
## to actually move for a foundation to read as "under way" rather than
## "damaged and static". Forced to exactly max_hp on completion rather than
## trusting the fraction's rounding, so a finished building is never left one
## hp short of full by an integer-division remainder.
func add_build_progress(amount: int) -> bool:
	if phase == Phase.COMPLETE or phase == Phase.DESTROYED:
		return false
	build_progress = clampi(build_progress + amount, 0, maxi(build_total, 0))
	if phase == Phase.FOUNDATION and build_progress > 0:
		phase = Phase.UNDER_CONSTRUCTION
	if build_total > 0 and build_progress >= build_total:
		phase = Phase.COMPLETE
		hp = max_hp
		return true
	hp = maxi(1, int(float(max_hp) * build_fraction()))
	return false


func is_complete() -> bool:
	return phase == Phase.COMPLETE


## Construction progress as 0..1, for the build bar. Guards `build_total == 0`,
## which is what a building placed straight into COMPLETE has (2.6's starting
## town centre) -- dividing by it would be a crash on the very first frame.
func build_fraction() -> float:
	if build_total <= 0:
		return 1.0
	return clampf(float(build_progress) / float(build_total), 0.0, 1.0)


func to_snapshot() -> Dictionary:
	var d := super()
	d["phase"] = int(phase)
	d["footprint"] = {"x": footprint.x, "y": footprint.y}
	d["build_fraction"] = build_fraction()
	d["queue_len"] = queue.size()
	d["queue_fraction"] = training_fraction()
	return d


## Adds a training order to the back of the queue.
func enqueue_training(def_id: StringName, build_time_ticks: int, cost: Dictionary) -> void:
	queue.append({
		"def_id": def_id,
		"progress": 0,
		"total": maxi(1, build_time_ticks),
		"ready": false,
		"cost": cost,
	})


## Removes and returns the entry at `index`, or {} if out of range. The caller
## (CancelProductionCommand) is what refunds its cost -- this only owns the
## queue itself.
func cancel_training(index: int) -> Dictionary:
	if index < 0 or index >= queue.size():
		return {}
	return queue.pop_at(index)


## The front entry's progress as 0..1, for a queue progress bar. 0 with nothing
## queued, matching build_fraction()'s "nothing to show" convention rather than
## a divide-by-zero.
func training_fraction() -> float:
	if queue.is_empty():
		return 0.0
	var front: Dictionary = queue[0]
	return clampf(float(front.get("progress", 0)) / float(front.get("total", 1)), 0.0, 1.0)
