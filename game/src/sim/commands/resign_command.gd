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


func _init(p_player_id: int = 0, p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "resign"
	return d


static func from_dict(d: Dictionary) -> ResignCommand:
	var c := ResignCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
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
	p.defeated = true
