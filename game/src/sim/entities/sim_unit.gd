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
var carry_kind: StringName = &""
var carry_amount: int = 0
var gather_cooldown: int = 0
var attack_cooldown: int = 0
var anim: StringName = &"idle"


func set_task_move(t: Vector2i) -> void:
	task = Task.MOVE
	task_target_tile = t


func stop() -> void:
	task = Task.IDLE
	task_target_tile = tile()
	path = PackedVector2Array()
	path_index = 0


func is_idle() -> bool:
	return task == Task.IDLE


## The sub-tile position MOVE is walking toward -- the tile's centre, so
## MovementSystem's arrival check lands exactly on the tile TaskSystem expects.
func move_target_subpos() -> Vector2i:
	const HALF := SimWorld.SUBTILE / 2
	return task_target_tile * SimWorld.SUBTILE + Vector2i(HALF, HALF)
