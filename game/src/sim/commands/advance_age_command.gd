## Starts researching the next age (PLAN.md 9.2). The real mechanism, as against
## `DebugSetAgeCommand`, which jumps instantly and exists for tests and for
## setting up a scenario quickly.
##
## Takes TIME rather than applying at once: `AgeDef.advance_time_ticks` says how
## long, `AgeSystem` counts it down, and the HUD draws the count as the ring
## around the age badge. That is why this is a command that starts something
## rather than one that does something -- the sim owns the clock, so every client
## sees the same ring at the same tick and the progress cannot be a local
## animation that drifts.
##
## NO TARGET AGE. It always advances to `age + 1`, so a client cannot ask to skip
## one, and there is no field for it to lie in. Where DebugSetAgeCommand takes an
## absolute age precisely so a resend cannot compound, this needs no such guard:
## `validate()` refuses a second start while one is already running, so the
## command is not repeatable in the first place.
class_name AdvanceAgeCommand
extends Command


func _init(p_player_id: int = 0, p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "advance_age"
	return d


static func from_dict(d: Dictionary) -> AdvanceAgeCommand:
	var c := AdvanceAgeCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	return c


func validate(w: SimWorld) -> bool:
	var p := w.player_for(player_id)
	if p == null or p.is_advancing():
		return false
	var next := _next_def(p)
	# Refuses at the last age rather than clamping, the same call
	# DebugSetAgeCommand makes: the badge decides whether to offer an advance from
	# the same age_count(), so a rejection here means the two disagree.
	return next != null and p.can_afford(next.cost)


func apply(w: SimWorld) -> void:
	var p := w.player_for(player_id)
	if p == null or p.is_advancing():
		return
	var next := _next_def(p)
	if next == null or not p.pay(next.cost):
		return
	p.begin_advance(next.index, next.advance_time_ticks)


## The age being advanced INTO, or null at the top of the ladder. Its
## `advance_time_ticks` and `cost` are the ones that apply -- the cost of
## reaching an age belongs to the age reached, not the one left behind.
func _next_def(p: SimPlayer) -> AgeDef:
	return GameDataRegistry.age(p.age + 1)
