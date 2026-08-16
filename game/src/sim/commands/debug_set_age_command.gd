## Test/debug-only command that moves the caller's own age (PLAN.md 9.2's real
## advancement -- a cost, a build time, and a town centre to research it at --
## does not exist yet).
##
## It exists because the age axis became load-bearing before the mechanism that
## drives it did: buildings re-skin per age (2.7), the train and build menus gate
## on age, and the sim now refuses an order above the caller's age. All of that
## is unreachable in a running game without a way to advance, so this is what
## makes ages 2-4 testable on a device at all.
##
## Modelled on DebugDestroyCommand, and for the same reasons: it is a real
## command through the real command path rather than a poke at SimWorld, so the
## sim/view split and the server-authoritative rule (PLAN.md 1.1) both still
## hold, and 9.2 replaces it with an AdvanceAgeCommand that charges for the same
## state change rather than having to introduce one.
##
## OWN AGE ONLY. `player_id` is the caller and there is no target field, so this
## cannot be used to age someone else -- the same ownership rule
## DebugDestroyCommand enforces with `e.owner_id == player_id`.
class_name DebugSetAgeCommand
extends Command

## Absolute, not a delta. A delta would compound if a command were ever applied
## twice (a replay seam, a resend), where setting 3 twice still means 3 --
## the same reason snapshots carry state and not diffs.
var age: int = 1


func _init(p_player_id: int = 0, p_age: int = 1, p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	age = p_age
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "debug_set_age"
	d["age"] = age
	return d


static func from_dict(d: Dictionary) -> DebugSetAgeCommand:
	var c := DebugSetAgeCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	c.age = int(d.get("age", 1))
	return c


## Rejects an age outside the declared ladder rather than clamping it. Clamping
## would make "advance past the last age" silently succeed, and the HUD button
## that sends this decides whether there IS a next age by asking the same
## `age_count()` -- so a rejection here means the two disagree, which is worth
## seeing rather than smoothing over.
func validate(w: SimWorld) -> bool:
	if age < 1 or age > GameDataRegistry.age_count():
		return false
	return w.player_for(player_id) != null


func apply(w: SimWorld) -> void:
	var p := w.player_for(player_id)
	if p != null:
		p.age = age
