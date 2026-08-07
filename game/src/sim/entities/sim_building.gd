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
func add_build_progress(amount: int) -> bool:
	if phase == Phase.COMPLETE or phase == Phase.DESTROYED:
		return false
	build_progress = clampi(build_progress + amount, 0, maxi(build_total, 0))
	if phase == Phase.FOUNDATION and build_progress > 0:
		phase = Phase.UNDER_CONSTRUCTION
	if build_total > 0 and build_progress >= build_total:
		phase = Phase.COMPLETE
		return true
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
	return d
