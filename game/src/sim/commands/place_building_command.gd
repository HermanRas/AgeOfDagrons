## Places a new building's FOUNDATION and sends the workers who ordered it
## (PLAN.md 5.1). Raising the foundation is still BuildSystem's job (4.4) -- this
## only pays the cost, claims the footprint, and puts the builders on the road.
##
## One building per command, unlike Move/Gather/Build: there is exactly one thing
## being placed and exactly one player paying for it. `builder_ids` is a list all
## the same, because a placement is issued BY a selection, and everyone in it
## should walk over.
##
## THE BUILDERS RIDE THIS COMMAND RATHER THAN A BUILDCOMMAND BEHIND IT. The client
## cannot send the second order: entity ids are assigned by the host inside
## spawn_building(), so at the moment the view submits the placement the
## foundation it wants to build has no id to name -- and the view only learns one
## a snapshot later. Placing and tasking in one apply() also makes the pair
## atomic; there is no tick in between where the foundation exists and the
## villager who asked for it is standing about idle, which is exactly what the
## project owner reported on 2026-08-16 (place a building, then have to reselect
## the villager and tap the foundation by hand).
class_name PlaceBuildingCommand
extends Command

var def_id: StringName = &""
## Top-left tile of the footprint (SimMap.footprint_rect's convention), not its
## centre -- centring is ambiguous for an even-sized footprint (PLAN.md 6.2).
var origin: Vector2i = Vector2i.ZERO
## Who walks over and raises it. May be empty -- a placement with nobody to build
## it is still a legal placement (it is how a test or a future queued build order
## would place one), and it simply leaves a foundation standing.
var builder_ids: Array[int] = []


func _init(p_player_id: int = 0, p_def_id: StringName = &"", p_origin: Vector2i = Vector2i.ZERO,
		p_builder_ids: Array[int] = [], p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	def_id = p_def_id
	origin = p_origin
	builder_ids = p_builder_ids
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "place_building"
	d["def_id"] = String(def_id)
	d["origin"] = {"x": origin.x, "y": origin.y}
	d["builder_ids"] = builder_ids
	return d


static func from_dict(d: Dictionary) -> PlaceBuildingCommand:
	var c := PlaceBuildingCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	c.def_id = StringName(d.get("def_id", ""))
	var o: Dictionary = d.get("origin", {})
	c.origin = Vector2i(int(o.get("x", 0)), int(o.get("y", 0)))
	var ids: Array[int] = []
	for v in d.get("builder_ids", []):
		ids.append(int(v))
	c.builder_ids = ids
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
	var b := w.spawn_building(def_id, player_id, origin, SimBuilding.Phase.FOUNDATION)
	if b != null:
		_send_builders(w, b)


## Task whatever is left of the ordering selection onto the new foundation, the
## same way BuildCommand would have.
##
## Filtered here rather than in validate(): a builder that died between the tap
## and the tick must not cancel the PLACEMENT -- the player asked for a building
## and can afford it, and refusing that because one of five villagers was killed
## on the way would be a strange thing to explain. A selection that is now empty
## of anything alive simply leaves the foundation standing.
func _send_builders(w: SimWorld, b: SimBuilding) -> void:
	for id in builder_ids:
		var e := w.get_entity(id)
		if e == null or not e.alive or not (e is SimUnit) or e.owner_id != player_id:
			continue
		(e as SimUnit).set_task_build(b.id, b.tile())
		if w.paths != null:
			w.paths.request(id, b.tile())
