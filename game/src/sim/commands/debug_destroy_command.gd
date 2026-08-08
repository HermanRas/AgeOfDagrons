## Test/debug-only command that instantly destroys one of the caller's own
## entities (PLAN.md 5.5: "buildings can be destroyed by a debug command";
## extended to units too, since MVP's 4.7 death/corpse path otherwise has no
## way to trigger without real combat).
##
## Routes through take_damage() rather than setting `alive` directly, so
## DeathSystem's corpse/rubble handling reacts exactly the way it will the day
## combat is a real source of damage -- this command needs no changes then.
class_name DebugDestroyCommand
extends Command

var target_id: int = 0


func _init(p_player_id: int = 0, p_target_id: int = 0, p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	target_id = p_target_id
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "debug_destroy"
	d["target_id"] = target_id
	return d


static func from_dict(d: Dictionary) -> DebugDestroyCommand:
	var c := DebugDestroyCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	c.target_id = int(d.get("target_id", 0))
	return c


func validate(w: SimWorld) -> bool:
	var e := w.get_entity(target_id)
	return e != null and e.alive and e.owner_id == player_id


func apply(w: SimWorld) -> void:
	var e := w.get_entity(target_id)
	if e != null:
		e.take_damage(e.hp, 0)
