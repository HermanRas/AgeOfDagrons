## Opening and shutting a gate (PLAN.md 5.8).
##
## THE TARGET STATE, NOT A TOGGLE, which is why this carries a bool rather than
## meaning "flip it". A toggle is a command whose outcome depends on when it lands:
## two taps in one tick would cancel out, and on a client the second tap goes out
## before the first one's snapshot has come back, so a player double-tapping a gate
## would be as likely to close it as open it. Naming the state makes a repeat
## harmless.
##
## GATES START OPEN (SimBuilding.gate_locked), which was the project owner's call: a
## wall never strands its own villagers, and the price is that it does nothing until
## somebody locks it. **An open gate is open to everyone**, the besieging army
## included -- per-player passability would need a pathfinding grid per player and is
## the real fix, deliberately not attempted.
##
## The interesting part is not here but in `SimWorld.set_gate_locked`, which is what
## moves the movement grid and shoves whoever is standing in the doorway clear.
class_name ToggleGateCommand
extends Command

var building_id: int = 0
var locked: bool = false


func _init(p_player_id: int = 0, p_building_id: int = 0, p_locked: bool = false,
		p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	building_id = p_building_id
	locked = p_locked
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "toggle_gate"
	d["building_id"] = building_id
	d["locked"] = locked
	return d


static func from_dict(d: Dictionary) -> ToggleGateCommand:
	var c := ToggleGateCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	c.building_id = int(d.get("building_id", 0))
	c.locked = bool(d.get("locked", false))
	return c


func validate(w: SimWorld) -> bool:
	var e := w.get_entity(building_id)
	if e == null or not e.alive or not (e is SimBuilding):
		return false
	# YOURS ONLY. Without this an attacker could open the gate they are standing
	# outside, which is not a siege, and `Net` overwriting `player_id` with the peer's
	# real id is what makes the check mean something.
	if e.owner_id != player_id:
		return false
	var b := e as SimBuilding
	if not b.is_gate:
		return false
	# A GATE UNDER CONSTRUCTION CANNOT BE LOCKED. It is a hole in the ground with a
	# frame around it, and letting it be shut would mean a player could seal a gap
	# with something nobody has built yet. It stays unlocked and passable until
	# `BuildSystem` finishes it -- see `SimBuilding.blocks_now`.
	return b.is_complete()


func apply(w: SimWorld) -> void:
	var b := w.get_entity(building_id) as SimBuilding
	if b == null:
		return
	# Idempotent by construction: setting the state it already has re-sets the same
	# occupancy and evicts nobody, which is what makes a repeated tap harmless.
	w.set_gate_locked(b, locked)
