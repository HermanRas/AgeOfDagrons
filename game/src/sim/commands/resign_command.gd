## Conceding the match (PLAN.md 12.1e). A COMMAND, which is the whole point.
##
## Resign used to be `Net.leave()` and a scene change: a local act that dropped the
## socket and told the simulation nothing. On a client that meant the host kept the
## resigning player alive with every building they owned, so `WinConditionSystem` never
## found a last man standing and the other player fought an abandoned base forever. On a
## HOST it was worse -- `leave()` tore down the session, so one player conceding ended
## everybody's match.
##
## Going through the command path fixes both by reusing what is already there. `Net`
## overwrites `player_id` with the id it knows the sender owns (`_recv_command`), so this
## cannot be forged to resign somebody else, and it needs no field for the target: the
## only player you may concede for is yourself, and there is nothing here to lie in.
##
## NO COST, NO PRECONDITION BEYOND NOT ALREADY BEING OUT. `validate()` refuses a second
## resign so a double tap, or a resign racing the disconnect that follows it, cannot
## re-defeat somebody -- which matters because `Net` issues one of these itself when a
## peer vanishes, and that can arrive after the player's own.
class_name ResignCommand
extends Command

## WHY, as a `SimPlayer.Defeat` (project owner, 2026-08-30: *"when a player disconnects
## or resigns the server does not notify other players"*). RESIGNED for the pause menu's
## button; DISCONNECTED for the one `Net._on_peer_disconnected` queues on a vanished
## peer's behalf, which is the only difference between the two events as far as the sim
## can tell -- both end with the same flag set on the same tick.
##
## ⚠️ **IT RIDES THE WIRE AND IT IS COSMETIC, AND BOTH HALVES OF THAT ARE DELIBERATE.**
## It is on the wire so a REPLAY (`Replay` serialises commands through `to_dict`) shows a
## dropped player as dropped rather than as a quitter. It is safe to trust off the wire
## because the worst a client can do with it is mislabel its OWN forfeit -- `Net`
## overwrites `player_id` with the id it knows the sender owns, so nobody can concede for
## anybody else, and the label changes one sentence on a result screen and nothing in the
## simulation.
var reason: int = SimPlayer.Defeat.RESIGNED


func _init(p_player_id: int = 0, p_issued_tick: int = 0,
		p_reason: int = SimPlayer.Defeat.RESIGNED) -> void:
	player_id = p_player_id
	issued_tick = p_issued_tick
	reason = p_reason


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "resign"
	d["reason"] = reason
	return d


static func from_dict(d: Dictionary) -> ResignCommand:
	var c := ResignCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	# Clamped to the two a resignation can legitimately be. An absent field is the old
	# wire form and reads as RESIGNED, which is what every command sent before today was.
	var r := int(d.get("reason", SimPlayer.Defeat.RESIGNED))
	c.reason = r if r == SimPlayer.Defeat.DISCONNECTED else SimPlayer.Defeat.RESIGNED
	return c


func validate(w: SimWorld) -> bool:
	var p := w.player_for(player_id)
	return p != null and not p.defeated


## Sets the flag and nothing else. The entities are deliberately LEFT STANDING: killing
## them would be a second mechanism for the same outcome, and it would mean deciding on
## the spot what happens to a half-built barracks and to units mid-order. `WinConditionSystem`
## reads `defeated` when it counts who is standing, so a conceded player is out whatever
## they still own.
##
## `defeated` is one-way there too ("never cleared", and for the same reason): a flag that
## could flicker off would take the defeat screen with it.
func apply(w: SimWorld) -> void:
	var p := w.player_for(player_id)
	if p == null:
		return
	p.defeat(reason)
