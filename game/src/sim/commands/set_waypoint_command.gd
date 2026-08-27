## Set (or clear) a building's rally point -- where everything leaving it walks to
## (project owner, 2026-08-27). See `SimBuilding.waypoint`.
##
## **A STATE, NOT A TOGGLE**, which is the same shape `ToggleGateCommand` settled on and
## for the same reason: the command names the tile it wants rather than saying "change
## it", so a repeat is harmless and two clients that both sent one cannot end up with the
## flag in different places. A dropped packet costs the player one tap, not a mystery.
##
## Clearing is `SimBuilding.NO_WAYPOINT` rather than a second command or a bool, so
## "where should this be" has exactly one answer on the wire.
##
## `{x, y}` AND NOT A `Vector2i`, unlike the snapshot's copy of the same tile: a command
## dict is JSON-stringified into the replay log (`Replay`), and JSON has no Vector2i.
## `MoveCommand` carries its target the same way for the same reason.
class_name SetWaypointCommand
extends Command

var building_id: int = 0
var tile: Vector2i = SimBuilding.NO_WAYPOINT


func _init(p_player_id: int = 0, p_building_id: int = 0,
		p_tile: Vector2i = SimBuilding.NO_WAYPOINT, p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	building_id = p_building_id
	tile = p_tile
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "set_waypoint"
	d["building_id"] = building_id
	d["tile"] = {"x": tile.x, "y": tile.y}
	return d


static func from_dict(d: Dictionary) -> SetWaypointCommand:
	var c := SetWaypointCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	c.building_id = int(d.get("building_id", 0))
	var t: Dictionary = d.get("tile", {})
	c.tile = Vector2i(int(t.get("x", -1)), int(t.get("y", -1)))
	return c


## Refuses: a building that is gone, dead or not the caller's, and a tile that is off the
## map. Anything else is legal, including a tile the building's own units cannot reach --
## see `SimWorld.send_to_waypoint` for why an unreachable rally point is self-correcting
## rather than something to validate against here.
##
## PASSABILITY IS NOT CHECKED, deliberately. It is a *per-domain* question with no single
## answer for a building that trains both -- and it changes: a rally point behind a gate
## is reachable or not depending on whether the gate is shut this minute. Validating it
## once, at the moment of the tap, would refuse points that will be fine and accept ones
## that will not.
##
## ANY OWNED BUILDING, not only the ones that hold or train anything. A rally point on a
## house does nothing, and refusing it would mean a tap that is silently ignored -- which
## is worse than a flag that turns out to be pointless, because the flag at least says
## what the game thought you meant.
func validate(w: SimWorld) -> bool:
	var b := w.get_entity(building_id) as SimBuilding
	if b == null or not b.alive or b.owner_id != player_id:
		return false
	if tile == SimBuilding.NO_WAYPOINT:
		return true          # clearing is always legal
	return w.map != null and w.map.in_bounds(tile)


func apply(w: SimWorld) -> void:
	var b := w.get_entity(building_id) as SimBuilding
	if b == null:
		return
	b.waypoint = tile
