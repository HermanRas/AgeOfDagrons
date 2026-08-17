## Keeps every player's `pop_used`/`pop_cap` in step with what they own, and owns
## the rule those two numbers describe: whether there is room to train another
## unit (PLAN.md 4.11).
##
## The two fields, the snapshot channel that carries them (`SnapshotSystem`'s
## `player_state`) and the `state_hash()` entry that would catch them diverging
## have all existed since 0.6 -- nothing ever WROTE them, so both sat at 0 and
## the resource HUD showed a headcount instead of a population. This is the
## missing half.
##
## RECOUNTED FROM SCRATCH every tick rather than adjusted on spawn and death.
## An incremental counter has to be decremented from every place a unit can
## leave the world (trained, killed, despawned as a corpse, destroyed with its
## transport later on) and a single missed path leaks population permanently --
## a player who cannot train because of units that died ten minutes ago, with
## nothing on screen to explain it. A full recount cannot drift: it is a scan
## over `entities`, which is tens of items in MVP, on a 10 Hz clock.
##
## Runs LAST, after DeathSystem. A unit killed this tick is not occupying a
## population slot, and a building destroyed this tick is not providing one; both
## become `alive == false` in the systems above, and counting before them would
## report a population one tick stale in the direction that matters -- the one
## where the player is told they are full when they are not.
##
## ENFORCEMENT IS `has_room_for()`, called by `TrainCommand.validate()` -- the cap
## is a real rule now, not a caption. Until 2026-08-17 it was the caption: the
## counter read 5/10 and nothing acted on it, so a player could train straight
## past it. That is worse than showing nothing at all, because it teaches a rule
## the game does not have.
##
## THE COUNTING LIVES IN STATICS, not inside `process_tick`'s loop, and that is
## what makes enforcement possible. A command is validated by `CommandSystem`,
## which runs FIRST in the tick order -- so `pop_used`/`pop_cap` are still last
## tick's numbers when the gate is asked, and on the very first tick of a match
## they are the 0/0 they were initialised with, which would refuse every unit in
## the game. The gate therefore derives the population from what exists rather
## than reading the report, and `process_tick` writes the report from the same
## three functions. One implementation, so the counter and the rule cannot
## disagree -- the trap `SimWorld.adjacency_allows()` exists to avoid for
## placement.
class_name PopulationSystem
extends SimSystem


func process_tick(w: SimWorld) -> void:
	# Assigned per PLAYER, not per owner id found among the entities: a player whose
	# last house fell needs their cap written back down to 0, and one who owns
	# nothing at all must still be visited or they keep whatever they had last tick.
	for p in w.players:
		p.pop_used = used_of(w, p.id)
		p.pop_cap = cap_of(w, p.id)


## Population `player_id`'s standing units occupy.
##
## The sum of their `pop_cost`, never a headcount: two villagers at 1 apiece and a
## siege ram at 3 is 5, and a headcount agrees with the sum right up until the
## first unit that costs more than one -- which is every siege engine.
static func used_of(w: SimWorld, player_id: int) -> int:
	var used := 0
	for e in w.entities.values():
		# A corpse (4.7) counts for nothing: it is in `entities` for ten seconds
		# after the death and must not hold a slot open for a unit already lost.
		if e is SimUnit and e.alive and e.owner_id == player_id:
			used += (e as SimUnit).pop_cost
	return used


## Population `player_id`'s buildings provide.
##
## COMPLETE only: a house is worth its 5 pop when it is standing, not when its
## foundation is pegged out. Otherwise a player could peg out ten foundations they
## never intend to finish and train against them.
static func cap_of(w: SimWorld, player_id: int) -> int:
	var cap := 0
	for e in w.entities.values():
		if not (e is SimBuilding):
			continue
		var b := e as SimBuilding
		if b.owner_id == player_id and b.alive and b.is_complete():
			cap += b.provides_pop
	return cap


## Population already PAID FOR but not yet standing: every entry in every one of
## `player_id`'s training queues.
##
## WITHOUT THIS THE CAP IS TRIVIALLY BEATABLE. `used_of()` counts units that
## exist, and a queue holds units that are coming whatever happens to the cap in
## the meantime -- so a player at 9/10 could queue twenty villagers in one sitting
## and `ProductionSystem` would spawn every one of them. The gate has to count what
## has been ordered, the same way `_count_abutting()` counts field FOUNDATIONS
## against the four-per-mill limit rather than only finished fields.
##
## Rubble is skipped for the same reason `ProductionSystem` skips it: a destroyed
## building's queue never spawns anything, so reserving population for it would
## charge the player for units that are not coming.
##
## An unknown def_id falls back to 1 rather than 0 -- a typo should cost the player
## a population slot, not silently open a hole in the cap.
static func queued_pop(w: SimWorld, player_id: int) -> int:
	var pending := 0
	for e in w.entities.values():
		if not (e is SimBuilding):
			continue
		var b := e as SimBuilding
		if b.owner_id != player_id or not b.alive:
			continue
		for entry in b.queue:
			var ud: UnitDef = w.unit_def(StringName(entry.get("def_id", &"")))
			pending += ud.pop_cost if ud != null else 1
	return pending


## Whether `player_id` has room for one more unit costing `pop_cost`.
##
## Called by `TrainCommand.validate()` (the server is the only trust boundary) and
## by `GameScene` before it submits, so the toast the player reads and the refusal
## the host makes come from the same code -- exactly the arrangement the placement
## ghost and `PlaceBuildingCommand` share for adjacency.
##
## Note what this does NOT do: it never blocks a unit already queued from
## SPAWNING. A player whose houses are demolished while five villagers are in the
## oven gets all five, and ends up over their cap until the losses catch up. That
## is the same direction the recount already leans -- report the truth, refuse only
## the NEXT order -- and the alternative is a paid-for unit that never arrives and
## never explains itself.
static func has_room_for(w: SimWorld, player_id: int, pop_cost: int) -> bool:
	return used_of(w, player_id) + queued_pop(w, player_id) + pop_cost \
			<= cap_of(w, player_id)
