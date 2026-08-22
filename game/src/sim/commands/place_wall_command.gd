## Placing a RUN of wall segments from one drag (PLAN.md 5.8).
##
## ONE COMMAND FOR THE WHOLE WALL, and the server does the segmentation. The client
## could have sent one `PlaceBuildingCommand` per segment -- it has `WallPlan` too, it
## draws the ghost from it -- and that would have put the client in charge of how many
## buildings it gets and where, which is exactly what the trust boundary is for
## (PLAN.md 5.1 step 4). This carries the two tiles the finger touched. Everything
## else is decided here.
##
## IT PLACES WHAT IT CAN AND STOPS, rather than refusing the run. A forty-tile drag
## with sixty wood in the bank should give you the wall you can afford, laid from the
## anchor outwards, and not a toast saying no -- that is what a player means by
## dragging, and `MarketPanel`'s buttons are the place for "you cannot afford this".
## Blocked tiles are skipped the same way: a run crossing a tree lays the segments
## that fit and leaves the gap. 0 A.D. does both.
##
## And when the money runs out mid-run the LAST PIECE IS DOWNGRADED to whatever the
## tier still affords -- see `apply()`. Without that, "as much wall as you can afford"
## was false in the most ordinary case there is: a player who cannot afford the first
## nine-tile piece got nothing at all, with two short ones within reach.
##
## The alternative -- all or nothing -- was rejected because the failure is invisible
## in advance: a run's cost depends on how it segments, and a player cannot count
## nine-tile pieces under their own thumb.
class_name PlaceWallCommand
extends Command

## The tier's representative def -- the one carrying `wall_lengths`. Not a segment
## length: which lengths get used is this command's decision, not the caller's.
var def_id: StringName = &""

## The tiles the drag started and ended on. `from` is the anchor: the run stays on
## its row or column, and segments are laid from whichever end is lower.
var from: Vector2i = Vector2i.ZERO
var to: Vector2i = Vector2i.ZERO

## Who walks over and raises it, distributed across the segments actually placed.
var builder_ids: Array[int] = []


func _init(p_player_id: int = 0, p_def_id: StringName = &"",
		p_from: Vector2i = Vector2i.ZERO, p_to: Vector2i = Vector2i.ZERO,
		p_builder_ids: Array[int] = [], p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	def_id = p_def_id
	from = p_from
	to = p_to
	builder_ids = p_builder_ids
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "place_wall"
	d["def_id"] = String(def_id)
	d["from"] = from
	d["to"] = to
	d["builder_ids"] = builder_ids
	return d


static func from_dict(d: Dictionary) -> PlaceWallCommand:
	var c := PlaceWallCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	c.def_id = StringName(d.get("def_id", ""))
	# Vector2i straight off the wire, like `SimEntity.pos` and for the same reason
	# (12.1f): a snapshot never goes through JSON, and a paired-int dictionary pays
	# for the key names "x" and "y" twice per command.
	c.from = d.get("from", Vector2i.ZERO)
	c.to = d.get("to", Vector2i.ZERO)
	var ids: Array[int] = []
	for v in d.get("builder_ids", []):
		ids.append(int(v))
	c.builder_ids = ids
	return c


## Deliberately loose, and this is the one command where that is the right shape.
##
## Affordability and clear ground are decided PER SEGMENT in `apply()`, because a run
## is partial by design -- so validating them here would refuse a wall that is going
## to be placed, just shorter. What is checked is the things that make the whole
## command meaningless: an unknown def, a def that is not a wall tier, and the age
## gate, which is enforced here for the same reason `PlaceBuildingCommand` enforces it
## (the menu is a client).
func validate(w: SimWorld) -> bool:
	var bd: BuildingDef = w.building_def(def_id)
	if bd == null or not bd.is_wall_run():
		return false
	var p := w.player_for(player_id)
	if p == null or p.defeated:
		return false
	if bd.age_required > p.age:
		return false
	# The plan has to describe something. A `wall_lengths` naming only defs that do
	# not exist would otherwise be a command that validates and does nothing.
	return not _segments(w).is_empty()


func apply(w: SimWorld) -> void:
	var p := w.player_for(player_id)
	if p == null:
		return

	var axis := int(_plan(w).get("axis", WallPlan.AXIS_X))
	var placed: Array[SimBuilding] = []
	for seg in _segments(w):
		var origin: Vector2i = seg["origin"]
		var footprint: Vector2i = seg["footprint"]
		# GROUND FIRST, THEN MONEY. Checked in this order so a run across a tree does
		# not charge for the segment it then fails to place -- and re-checked per
		# segment rather than once, because the segments placed earlier in this same
		# loop have themselves changed what is free.
		if not w.map.can_place_building(SimMap.footprint_rect(origin, footprint)):
			continue

		var seg_def: StringName = seg["def_id"]
		var bd: BuildingDef = w.building_def(seg_def)
		if bd == null:
			continue

		# OUT OF MONEY DOWNGRADES THE LAST PIECE, then ends the run.
		#
		# This used to simply stop, and the reasoning was that a shorter piece only
		# ever comes last so the next segment is never cheaper. True of the PLAN and
		# beside the point: a player with 24 wood who drags thirty tiles cannot afford
		# the first nine-tile piece and was getting NOTHING, when two short pieces
		# were within reach the whole time. A drag promises "as much wall as you can
		# afford", and the readout under the finger has already said the run is longer
		# than the budget -- laying none of it makes a liar of both.
		#
		# The downgrade stays inside the segment's OWN span, so the origins the plan
		# chose still hold and the wall cannot grow past where the finger stopped.
		if not p.can_afford(bd.cost):
			var shorter := _largest_affordable(w, p, int(seg["length"]))
			if shorter == &"":
				break                 # nothing in the tier is affordable; the run ends
			seg_def = shorter
			bd = w.building_def(seg_def)
			footprint = WallPlan.footprint_for(bd.footprint.x, axis)
			if not w.map.can_place_building(SimMap.footprint_rect(origin, footprint)):
				break

		if not p.pay(bd.cost):
			break                     # unreachable: can_afford was just checked
		var b := w.spawn_building(seg_def, player_id, origin,
				SimBuilding.Phase.FOUNDATION, false, footprint, int(seg["facing"]))
		if b != null:
			placed.append(b)
		# A DOWNGRADED PIECE IS THE LAST ONE. What follows it in the plan starts where
		# the full-length piece would have ended, so placing it would leave a gap --
		# and the money has run out anyway.
		if bd.footprint.x < int(seg["length"]):
			break

	_send_builders(w, placed)


## The longest piece in this tier that fits inside `span` and that the player can
## still pay for, or `&""` if none can. Longest-first, like the plan itself.
func _largest_affordable(w: SimWorld, p: SimPlayer, span: int) -> StringName:
	var bd: BuildingDef = w.building_def(def_id)
	if bd == null:
		return &""
	var best: StringName = &""
	var best_len := 0
	for candidate in bd.wall_lengths:
		var cd: BuildingDef = w.building_def(candidate)
		if cd == null or cd.footprint.x > span or cd.footprint.x <= best_len:
			continue
		if p.can_afford(cd.cost):
			best = candidate
			best_len = cd.footprint.x
	return best


## The plan, from the same function the ghost drew. Recomputed rather than carried on
## the wire so the client cannot choose its own segmentation -- see the header.
func _plan(w: SimWorld) -> Dictionary:
	var bd: BuildingDef = w.building_def(def_id)
	if bd == null:
		return {}
	var lengths := WallPlan.lengths_of(bd.wall_lengths, w.building_def)
	return WallPlan.plan(from, to, lengths)


func _segments(w: SimWorld) -> Array:
	return _plan(w).get("segments", [])


## Spread the ordering selection across the segments, one villager per segment,
## wrapping when there are more segments than villagers.
##
## ROUND-ROBIN RATHER THAN ALL-ON-THE-FIRST, which is what `PlaceBuildingCommand`
## does and is right for one building. Five villagers all queued on the first of
## twelve segments would raise it in a fifth of the time and then stand idle while
## eleven foundations sat untouched -- and the AI's standing order 2 exists because
## exactly that pattern (a foundation nobody returns to) had already been found once.
## Spread out, the wall goes up along its whole length at once, which is also what it
## looks like a player asked for.
func _send_builders(w: SimWorld, placed: Array[SimBuilding]) -> void:
	if placed.is_empty():
		return
	var index := 0
	for id in builder_ids:
		var e := w.get_entity(id)
		# Filtered here rather than in validate(), the same call
		# `PlaceBuildingCommand._send_builders` records: a builder that died between
		# the drag and the tick must not cancel the WALL.
		if e == null or not e.alive or not (e is SimUnit) or e.owner_id != player_id:
			continue
		var target := placed[index % placed.size()]
		index += 1
		(e as SimUnit).set_task_build(target.id, target.tile())
		if w.paths != null:
			w.paths.request(id, target.tile())
