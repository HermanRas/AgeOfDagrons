## A controllable, moving entity. Task kinds beyond MOVE (GATHER, BUILD, ...)
## are wired up alongside the systems that give them meaning -- ResourceSystem
## (phase 2.3+), ProductionSystem, etc. -- rather than stubbed here ahead of time.
class_name SimUnit
extends SimEntity

enum Task { IDLE, MOVE, GATHER, RETURN, BUILD, ATTACK, GARRISON, STAND_GROUND, FLEE }

var task: Task = Task.IDLE
var task_target_id: int = 0
var task_target_tile: Vector2i = Vector2i.ZERO
var path: PackedVector2Array = PackedVector2Array()
var path_index: int = 0
var speed: int = 0                   # sub-units per tick
var facing: int = 0                  # 0-7
## Which surfaces this unit can cross -- a SimMap.Domain. Land for everything in
## MVP (PLAN.md 2.2); carried per-unit rather than looked up from the def on every
## passability query, which pathfinding does thousands of times per path.
var domain: int = SimMap.Domain.LAND
## What this unit costs against its owner's population cap (PLAN.md 4.11).
## Copied off the def at spawn, exactly as `SimBuilding.provides_pop` is, so
## PopulationSystem's per-tick recount is a scan over entities and never a
## registry lookup -- and so a unit's cost cannot change under it mid-match.
var pop_cost: int = 1
var carry_kind: StringName = &""
var carry_amount: int = 0
var gather_cooldown: int = 0
## The resource node a GATHER/RETURN cycle is working. `task_target_id` points at
## whichever entity is currently being WALKED TO -- the node while gathering, the
## drop-off building while returning -- so this is the one field that survives the
## switch between them (6.4).
var gather_node_id: int = 0
## Where that node STOOD. Kept because a spent one is despawned, and by the time
## a villager walks its last load home there is no entity left to ask where to
## look for the next tree (GatherSystem's re-scan, project owner 2026-08-16).
## `task_target_tile` cannot serve: during RETURN it is the drop-off building.
var gather_node_tile: Vector2i = Vector2i.ZERO
var attack_cooldown: int = 0
var anim: StringName = &"idle"

## Ticks left as a corpse before DeathSystem despawns it (PLAN.md 4.7): 60 s of
## corpse plus a 10 s fade, at SimClock's 10 ticks/sec. -1 means "not dead" --
## DeathSystem reads that sentinel to tell a fresh death from one it has already
## set up, since `alive` alone cannot: it goes false exactly once, but the tick
## it does is the one tick DeathSystem must react to rather than just count down.
const CORPSE_TOTAL_TICKS := 700
const CORPSE_FADE_TICKS := 100
var corpse_ticks_left: int = -1


## True between asking PathService for a route and being given one (PLAN.md 4.2 --
## searches are budgeted, so the answer can be a few ticks late). A unit waits
## rather than setting off in the target's general direction: guessing would walk
## it into the wall the path was going to route around.
var path_pending: bool = false


## Units move, so the fog never sends one it cannot currently see. See
## `SimEntity.is_mobile`.
func is_mobile() -> bool:
	return true


func set_task_move(t: Vector2i) -> void:
	task = Task.MOVE
	task_target_tile = t
	path = PackedVector2Array()
	path_index = 0
	path_pending = true


## Walk toward a resource node and start working it on arrival (6.4). `tile` is
## the node's own tile -- it is occupied ground, so PathService substitutes the
## nearest tile that can actually be stood on, same as walking up to a tree (4.1).
func set_task_gather(node_id: int, tile: Vector2i) -> void:
	task = Task.GATHER
	task_target_id = node_id
	gather_node_id = node_id
	gather_node_tile = tile
	task_target_tile = tile
	path = PackedVector2Array()
	path_index = 0
	path_pending = true


## Walk a load back to a drop-off building. Kept separate from set_task_gather
## because `task_target_id` must point at the BUILDING while this is active --
## `gather_node_id` is what remembers the node to go back to once the load lands.
func set_task_return(building_id: int, tile: Vector2i) -> void:
	task = Task.RETURN
	task_target_id = building_id
	task_target_tile = tile
	path = PackedVector2Array()
	path_index = 0
	path_pending = true


## Walk toward a building under construction and add progress to it on arrival.
func set_task_build(building_id: int, tile: Vector2i) -> void:
	task = Task.BUILD
	task_target_id = building_id
	task_target_tile = tile
	path = PackedVector2Array()
	path_index = 0
	path_pending = true


## Walk toward an enemy and hit it on arrival (PLAN.md 4.13). `tile` is where the
## target is NOW -- a moving one is re-planned toward by CombatSystem once this
## route runs out, rather than re-pathed every tick, which is what keeps a chase
## inside PathService's per-tick budget (4.2).
func set_task_attack(target_id: int, tile: Vector2i) -> void:
	task = Task.ATTACK
	task_target_id = target_id
	task_target_tile = tile
	path = PackedVector2Array()
	path_index = 0
	path_pending = true


## Drop the route but KEEP the task -- what an attacker does the moment its
## target comes into reach, so it stands and fights instead of walking the rest
## of a path it no longer needs. Distinct from stop(), which retires the order
## entirely; a unit that halted is still attacking.
func halt() -> void:
	task_target_tile = tile()
	path = PackedVector2Array()
	path_index = 0
	path_pending = false


## MOVE, GATHER, RETURN, BUILD and ATTACK all walk somewhere before doing
## anything else -- this is PathService's and MovementSystem's test for "does this
## unit want a route", so neither has to enumerate every task that happens to
## travel.
func is_travel_task() -> bool:
	return task == Task.MOVE or task == Task.GATHER or task == Task.RETURN \
			or task == Task.BUILD or task == Task.ATTACK


## The 8-way facing a delta points along. Shared by MovementSystem (which faces a
## unit the way it walks) and CombatSystem (which faces it at what it is hitting)
## -- one function because a unit that walked east and then turned to strike must
## not disagree with itself about which way east is.
static func facing_toward(delta: Vector2i) -> int:
	var angle := atan2(-float(delta.y), float(delta.x))
	var octant := int(round(angle / (PI / 4.0))) % 8
	return octant + 8 if octant < 0 else octant


## Take a solved route. An EMPTY path means PathService found nowhere to go, which
## retires the task -- the alternative, leaving the unit in MOVE forever, is a unit
## that looks ordered but never arrives and never accepts that it failed.
func set_path(p: PackedVector2Array) -> void:
	path = p
	path_index = 0
	path_pending = false
	if p.is_empty():
		stop()
	else:
		# The real destination is where the path ACTUALLY ends, which is not the
		# ordered tile when that tile was blocked and a substitute was chosen
		# (PLAN.md 4.1). Without this the unit arrives and TaskSystem still thinks
		# it is short of its target.
		task_target_tile = Vector2i(p[p.size() - 1])


## Throw the route away and ask for a new one, KEEPING the task.
##
## For a unit that has been moved without asking it -- today only
## `SimWorld._evict_from_footprint`, stepping it out from under a new building.
## Its old route was planned from where it used to stand, and walking that route
## from somewhere else lands it in the wrong place, where `GatherSystem` and
## `BuildSystem` retire it for not being adjacent to what it was sent to. That
## cost the AI a whole script step before this existed.
##
## Clearing `path` and raising `path_pending` is exactly what the `set_task_*`
## calls do, so the unit simply stands still for the tick or two the new search
## takes and then carries on with the job it already had.
## Already standing where the route would have ended, so there is nothing to walk.
##
## The other half of `set_path()`: an empty route means "nowhere to go" there and
## retires the task, which is right for an unreachable order and WRONG for a unit
## that has simply arrived already. Keeping the task and dropping `path_pending` is
## what lets GatherSystem, BuildSystem and CombatSystem -- all of which wait for the
## walking to finish before they act -- get on with the job on the next tick.
func arrive() -> void:
	path = PackedVector2Array()
	path_index = 0
	path_pending = false


func replan() -> void:
	path = PackedVector2Array()
	path_index = 0
	path_pending = true


func stop() -> void:
	task = Task.IDLE
	task_target_tile = tile()
	task_target_id = 0
	gather_node_id = 0
	gather_node_tile = Vector2i.ZERO
	path = PackedVector2Array()
	path_index = 0
	path_pending = false


func is_idle() -> bool:
	return task == Task.IDLE


func has_waypoint() -> bool:
	return path_index < path.size()


## Tile the unit is currently walking toward.
func waypoint() -> Vector2i:
	return Vector2i(path[path_index]) if has_waypoint() else tile()


## Sub-tile centre of the current waypoint. Centres, because that is where the sim
## stands an entity on a tile (2.3) and where the view draws it.
func waypoint_subpos() -> Vector2i:
	return centre_of_tile(waypoint())


## The sub-tile position MOVE is walking toward overall -- the tile's centre, so
## MovementSystem's arrival check lands exactly on the tile TaskSystem expects.
func move_target_subpos() -> Vector2i:
	return centre_of_tile(task_target_tile)


static func centre_of_tile(t: Vector2i) -> Vector2i:
	const HALF := SimWorld.SUBTILE / 2
	return t * SimWorld.SUBTILE + Vector2i(HALF, HALF)


## `task` joins the base snapshot so the view can count idle villagers (7.1)
## without reaching into SimWorld -- the same reason every other view-facing
## fact travels in the snapshot rather than being asked of the sim directly.
func to_snapshot() -> Dictionary:
	var d := super()
	d["task"] = int(task)
	d["anim"] = anim
	d["facing"] = facing
	d["corpse_ticks_left"] = corpse_ticks_left
	return d
