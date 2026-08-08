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
