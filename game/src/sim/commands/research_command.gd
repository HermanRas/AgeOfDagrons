## Enqueues a technology at the building that offers it (PLAN.md 9.3).
##
## THE SAME SHAPE AS `TrainCommand` AND FOR THE SAME REASON: a research is a thing a
## building spends time on, so it goes on that building's production queue and
## `ProductionSystem` counts it down. See `SimBuilding.queue`'s header for why research
## is not a second field beside it.
##
## The button is on the BUILDING, which is the project owner's ruling of 2026-08-29:
## *"upgrades are action tiles on buildings, tech tree on mini map is only a visual
## guide letting you know what buildings hold what upgrades."* So the tech-tree page
## issues no command at all -- it has nothing to press -- and this is the only verb
## behind the whole of phase 9.3.
class_name ResearchCommand
extends Command

var building_id: int = 0
var tech_id: StringName = &""


func _init(p_player_id: int = 0, p_building_id: int = 0, p_tech_id: StringName = &"",
		p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	building_id = p_building_id
	tech_id = p_tech_id
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "research"
	d["building_id"] = building_id
	d["tech_id"] = String(tech_id)
	return d


static func from_dict(d: Dictionary) -> ResearchCommand:
	var c := ResearchCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	c.building_id = int(d.get("building_id", 0))
	c.tech_id = StringName(d.get("tech_id", ""))
	return c


func validate(w: SimWorld) -> bool:
	var e := w.get_entity(building_id)
	if e == null or not e.alive or not (e is SimBuilding) or e.owner_id != player_id:
		return false
	var b := e as SimBuilding
	if not b.is_complete():
		return false

	var t: TechDef = w.tech_def(tech_id)
	# THIS BUILDING, not merely SOME building. `researched_at` is a list because a
	# tech could be offered in two places; asking whether this one is on it is what
	# stops a client researching Blast Furnace at a house.
	if t == null or not t.researched_at.has(b.def_id):
		return false

	var p := w.player_for(player_id)
	if p == null:
		return false
	# ALREADY BOUGHT, OR ALREADY BEING BOUGHT. The second half is the one that is easy
	# to leave out and expensive to leave out: research takes up to a minute, so a
	# double tap would queue a second copy that completes, finds the tech already held
	# and refunds nothing. `SimWorld.grant_tech` is idempotent, which makes that a
	# waste rather than a duplicate effect -- but a waste of 275 food and 225 gold.
	if p.has_tech(tech_id) or b.is_researching(tech_id):
		return false
	# PREREQUISITES, checked here and not only in the menu. The panel already omits a
	# tech whose predecessor is missing; this is what makes omitting it sufficient,
	# exactly as `TrainCommand`'s age check backs up a hidden train button.
	for required in t.requires:
		if not p.has_tech(required):
			return false
	if t.age_required > p.age:
		return false
	return p.can_afford(t.cost)


func apply(w: SimWorld) -> void:
	var b := w.get_entity(building_id) as SimBuilding
	var t: TechDef = w.tech_def(tech_id)
	var p := w.player_for(player_id)
	if b == null or t == null or p == null:
		return
	if not p.pay(t.cost):
		return
	b.enqueue_research(tech_id, t.research_time_ticks, t.cost)
