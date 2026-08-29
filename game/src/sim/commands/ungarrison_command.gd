## Turn a garrison out of a building (PLAN.md 4.8) -- one occupant, or all of them.
##
## `index` names a slot in `SimBuilding.garrison`, or **-1 for everybody**, which is
## the button the HUD actually offers. Both in one command rather than two, because
## they are one verb with a scope and the wire cost of the distinction is an int that
## was going to be there anyway.
##
## AN INDEX AND NOT A UNIT ID, which is the same choice `CancelProductionCommand`
## made about the production queue and for the same reason: the panel is drawing a
## list of slots and the thing the player taps is the third one, not entity 41. It
## also means the client never has to know the ids of units it is not being told
## about -- a garrisoned unit is not in the snapshot at all (`SnapshotSystem.build`
## skips it), so `garrison` on the wire carries def ids for the portraits and no ids.
##
## A STALE INDEX EJECTS THE WRONG UNIT AND THAT IS ACCEPTED. Two taps in one tick, or
## a tap on a tick where the building's garrison shifted, ejects whoever is in that
## slot now. The alternative -- sending ids so the command could name exactly who --
## is the leak above, and the cost is one wrong archer walking out of a tower, which
## is recoverable by tapping again. `CancelProductionCommand` carries the identical
## risk against the queue and has done since 5.4.
class_name UngarrisonCommand
extends Command

## -1 means "all of them", which is what the panel's Ungarrison button sends.
const ALL := -1

## The CARRIER's id, which since 2026-08-29 may be a transport ship as well as a
## building (2.4d). The field keeps its name: renaming it would rewrite the wire format
## (`to_dict`/`from_dict`) and every replay recorded against it, to say something the
## header can say instead.
var building_id: int = 0
var index: int = ALL


func _init(p_player_id: int = 0, p_building_id: int = 0, p_index: int = ALL,
		p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	building_id = p_building_id
	index = p_index
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "ungarrison"
	d["building_id"] = building_id
	d["index"] = index
	return d


static func from_dict(d: Dictionary) -> UngarrisonCommand:
	var c := UngarrisonCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	c.building_id = int(d.get("building_id", 0))
	c.index = int(d.get("index", ALL))
	return c


## Refuses: a building that is gone, dead or not the caller's, an EMPTY garrison, and
## an `index` outside the list. A building that is merely rubble is refused by
## `alive`; a garrison inside a building that has fallen is already dead
## (DeathSystem), so there is nothing to let out.
##
## Deliberately does NOT check that there is anywhere to stand. That answer changes
## between validate and apply -- and it is per unit, not per command -- so
## `SimWorld.ungarrison_unit` refuses individually and a walled-in tower simply keeps
## whoever it cannot let out.
func validate(w: SimWorld) -> bool:
	var b := w.get_entity(building_id)
	if b == null or not b.alive or b.owner_id != player_id:
		return false
	if b.garrison.is_empty():
		return false
	if index != ALL and (index < 0 or index >= b.garrison.size()):
		return false
	return true


## Walks the list BACKWARDS for the eject-all case, because `ungarrison_unit`
## removes the entry it is given and a forward walk over a shrinking array skips
## every other occupant. Backwards, each removal is behind the cursor.
##
## The order units come out in therefore reverses the order they went in, which
## nothing depends on and which is deterministic either way -- the point of naming it
## is that it is a fixed order rather than an incidental one.
func apply(w: SimWorld) -> void:
	var b := w.get_entity(building_id)
	if b == null:
		return

	if index != ALL:
		if index < 0 or index >= b.garrison.size():
			return
		var one := w.get_entity(int(b.garrison[index]["id"])) as SimUnit
		if one != null:
			w.ungarrison_unit(b, one)
		return

	for i in range(b.garrison.size() - 1, -1, -1):
		var u := w.get_entity(int(b.garrison[i]["id"])) as SimUnit
		if u == null:
			continue
		w.ungarrison_unit(b, u)
