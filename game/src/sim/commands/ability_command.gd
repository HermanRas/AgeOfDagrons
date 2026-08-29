## Use a unit's special ability (PLAN.md 4.10) -- the monk's heal, the dragon's breath.
##
## ONE UNIT, NOT MANY, and it is the only order-issuing command in the game shaped that
## way. `MoveCommand` and `AttackCommand` carry a whole selection because a shared
## destination is one order however many walk to it; an ability is aimed, it costs a
## cooldown, and two monks told to heal the same soldier is one wasted monk. The client
## issues one of these per unit if it ever wants to.
##
## `target_id` names an entity for a `friendly` ability and `target_tile` names the
## ground for a `ground` one. Both are sent regardless -- for a targeted ability the tile
## is where the target stood when the order was given, which is what the unit starts
## walking toward before `AbilitySystem` begins following the target properly.
class_name AbilityCommand
extends Command

var unit_id: int = 0
var target_id: int = 0
var target_tile: Vector2i = Vector2i.ZERO


func _init(p_player_id: int = 0, p_unit_id: int = 0, p_target_id: int = 0,
		p_target_tile: Vector2i = Vector2i.ZERO, p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	unit_id = p_unit_id
	target_id = p_target_id
	target_tile = p_target_tile
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "ability"
	d["unit_id"] = unit_id
	d["target_id"] = target_id
	d["target_tile"] = {"x": target_tile.x, "y": target_tile.y}
	return d


static func from_dict(d: Dictionary) -> AbilityCommand:
	var c := AbilityCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	c.unit_id = int(d.get("unit_id", 0))
	c.target_id = int(d.get("target_id", 0))
	var t: Dictionary = d.get("target_tile", {})
	c.target_tile = Vector2i(int(t.get("x", 0)), int(t.get("y", 0)))
	return c


## EVERY GATE THE HUD APPLIES IS APPLIED AGAIN HERE, because the server is the only trust
## boundary (§4) and the panel greying a slot is a courtesy rather than a rule. Four of
## them, and each one is a way the button could be pressed when it should not be:
##
##   the unit has an ability at all   -- otherwise this is a no-op task the unit sits in
##   the cooldown has run             -- the whole point of a cooldown
##   the aim matches the ability      -- a `friendly` ability with no entity named, or a
##                                       `ground` one with one, is a client that has
##                                       mixed up which tap it was waiting for
##   the target is one of your OWN    -- a heal is the one effect in the game that would
##                                       be worth aiming at an enemy
##
## RANGE IS DELIBERATELY NOT CHECKED. The unit walks there (`Task.ABILITY` is a travel
## task), so a distance test here would refuse orders that are perfectly good the moment
## the unit takes a step -- the same reason no other order-then-arrive command checks it.
func validate(w: SimWorld) -> bool:
	var e := w.get_entity(unit_id)
	if e == null or not e.alive or not (e is SimUnit):
		return false
	if e.owner_id != player_id:
		return false
	var u := e as SimUnit
	if u.garrisoned_in != 0 or u.ability_cooldown > 0:
		return false

	var def := w.unit_def(u.def_id)
	if def == null or not def.has_ability():
		return false

	if def.ability_target == &"friendly":
		var target := w.get_entity(target_id)
		if target == null or not target.alive or not (target is SimUnit):
			return false
		if target.owner_id != player_id:
			return false
		return true
	# A ground ability. The tile must be on the map -- an aim point off the edge would
	# put the unit on a walk PathService cannot solve, which retires the task and looks
	# from the outside exactly like a button that does nothing.
	if target_id != 0:
		return false
	return w.map != null and w.map.in_bounds(target_tile)


func apply(w: SimWorld) -> void:
	var u := w.get_entity(unit_id) as SimUnit
	var def := w.unit_def(u.def_id)
	var aim := target_tile
	if def != null and def.ability_target == &"friendly":
		aim = w.get_entity(target_id).tile()
	u.set_task_ability(target_id, aim)
	if w.paths != null:
		w.paths.request(u.id, aim)
