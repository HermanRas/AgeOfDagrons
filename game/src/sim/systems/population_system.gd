## Keeps every player's `pop_used`/`pop_cap` in step with what they own
## (PLAN.md 4.11).
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
## Does NOT enforce the cap. Training over it is still allowed (`TrainCommand`
## has no population check), so this is a true report of a rule nothing applies
## yet. 4.11's other half.
class_name PopulationSystem
extends SimSystem


func process_tick(w: SimWorld) -> void:
	var used: Dictionary = {}          # player id -> int
	var cap: Dictionary = {}

	for e in w.entities.values():
		if not e.alive:
			continue          # a corpse (4.7) or rubble (5.5) counts for nothing
		if e is SimUnit:
			used[e.owner_id] = int(used.get(e.owner_id, 0)) + (e as SimUnit).pop_cost
		elif e is SimBuilding:
			# COMPLETE only: a house is worth its 5 pop when it is standing, not
			# when its foundation is pegged out. Otherwise a player could place
			# ten foundations they never intend to finish and train against them.
			var b := e as SimBuilding
			if b.is_complete():
				cap[b.owner_id] = int(cap.get(b.owner_id, 0)) + b.provides_pop

	# Assigned per PLAYER, not per id seen above: a player whose last house fell
	# needs their cap written back down to 0, and one who owns nothing at all must
	# still be visited or they keep whatever they had last tick.
	for p in w.players:
		p.pop_used = int(used.get(p.id, 0))
		p.pop_cap = int(cap.get(p.id, 0))
