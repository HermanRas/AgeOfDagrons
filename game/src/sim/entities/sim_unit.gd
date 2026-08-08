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
var carry_kind: StringName = &""
var carry_amount: int = 0
var gather_cooldown: int = 0
## The resource node a GATHER/RETURN cycle is working. `task_target_id` points at
## whichever entity is currently being WALKED TO -- the node while gathering, the
## drop-off building while returning -- so this is the one field that survives the
## switch between them (6.4).
var gather_node_id: int = 0
var attack_cooldown: int = 0
var anim: StringName = &"idle"


## True between asking PathService for a route and being given one (PLAN.md 4.2 --
## searches are budgeted, so the answer can be a few ticks late). A unit waits
## rather than setting off in the target's general direction: guessing would walk
## it into the wall the path was going to route around.
var path_pending: bool = false


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


## MOVE, GATHER, RETURN and BUILD all walk somewhere before doing anything else --
## this is PathService's and MovementSystem's test for "does this unit want a
## route", so neither has to enumerate every task that happens to travel.
func is_travel_task() -> bool:
	return task == Task.MOVE or task == Task.GATHER or task == Task.RETURN or task == Task.BUILD


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


func stop() -> void:
	task = Task.IDLE
	task_target_tile = tile()
	task_target_id = 0
	gather_node_id = 0
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
