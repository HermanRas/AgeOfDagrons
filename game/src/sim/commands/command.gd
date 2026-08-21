## Base type for every player action. Commands are the only way sim state
## changes (PLAN.md 5.1, 6.2) -- input never mutates SimWorld directly.
##
## Flow: client builds a Command -> Net RPCs its to_dict() to the server ->
## server rebuilds it with from_dict() -> SimWorld.queue_command() holds it
## for the next tick boundary -> CommandSystem validates then applies it.
class_name Command
extends RefCounted

var player_id: int = 0
var issued_tick: int = 0


func to_dict() -> Dictionary:
	return {"player_id": player_id, "issued_tick": issued_tick}


## Dispatches to the right subclass based on d.type. Extend the match arm
## whenever a new Command subclass is added.
static func from_dict(d: Dictionary) -> Command:
	match str(d.get("type", "")):
		"move":
			return MoveCommand.from_dict(d)
		"stop":
			return StopCommand.from_dict(d)
		"gather":
			return GatherCommand.from_dict(d)
		"build":
			return BuildCommand.from_dict(d)
		"attack":
			return AttackCommand.from_dict(d)
		"place_building":
			return PlaceBuildingCommand.from_dict(d)
		"train":
			return TrainCommand.from_dict(d)
		"cancel_production":
			return CancelProductionCommand.from_dict(d)
		"resign":
			return ResignCommand.from_dict(d)
		"debug_destroy":
			return DebugDestroyCommand.from_dict(d)
		"advance_age":
			return AdvanceAgeCommand.from_dict(d)
		"debug_set_age":
			return DebugSetAgeCommand.from_dict(d)
		"set_control_group":
			return SetControlGroupCommand.from_dict(d)
		_:
			push_error("Command.from_dict: unknown type %s" % d.get("type"))
			return null


## Must reject anything the sender doesn't own or that no longer exists --
## the server is the only trust boundary (PLAN.md 5.1 step 4).
func validate(_w: SimWorld) -> bool:
	return false


func apply(_w: SimWorld) -> void:
	pass
