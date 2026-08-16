## Places a new building's FOUNDATION (PLAN.md 5.1). Raising it is BuildCommand's
## job (4.4) -- placement only pays the cost and claims the footprint.
##
## One building per command, unlike Move/Gather/Build, because a placement order
## does not have a "which of my units" list to share -- there is exactly one
## thing being placed and exactly one player paying for it.
class_name PlaceBuildingCommand
extends Command

var def_id: StringName = &""
## Top-left tile of the footprint (SimMap.footprint_rect's convention), not its
## centre -- centring is ambiguous for an even-sized footprint (PLAN.md 6.2).
var origin: Vector2i = Vector2i.ZERO


func _init(p_player_id: int = 0, p_def_id: StringName = &"", p_origin: Vector2i = Vector2i.ZERO,
		p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	def_id = p_def_id
	origin = p_origin
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "place_building"
	d["def_id"] = String(def_id)
	d["origin"] = {"x": origin.x, "y": origin.y}
	return d


static func from_dict(d: Dictionary) -> PlaceBuildingCommand:
	var c := PlaceBuildingCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	c.def_id = StringName(d.get("def_id", ""))
	var o: Dictionary = d.get("origin", {})
	c.origin = Vector2i(int(o.get("x", 0)), int(o.get("y", 0)))
	return c


func validate(w: SimWorld) -> bool:
	var bd: BuildingDef = w.building_def(def_id)
	if bd == null:
		return false
	var p := w.player_for(player_id)
	if p == null or not p.can_afford(bd.cost):
		return false
	# The age gate is enforced HERE as well as in the build menu, because the menu
	# is a client and the server is the only trust boundary (PLAN.md 5.1 step 4).
	# SelectionActions omitting a wonder in age 1 keeps an honest player from
	# ordering one; this is what keeps a modified client from placing it.
	if bd.age_required > p.age:
		return false
	return w.map.can_place_building(SimMap.footprint_rect(origin, bd.footprint))


func apply(w: SimWorld) -> void:
	var bd: BuildingDef = w.building_def(def_id)
	var p := w.player_for(player_id)
	if bd == null or p == null:
		return
	# pay() before spawn_building(): the footprint was already checked in
	# validate() against state nothing else has touched since (CommandSystem runs
	# validate and apply back to back for the same command), so this never spends
	# a cost that fails to place.
	if not p.pay(bd.cost):
		return
	w.spawn_building(def_id, player_id, origin, SimBuilding.Phase.FOUNDATION)
