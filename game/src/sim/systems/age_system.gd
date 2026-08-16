## Ticks each player's age advancement (PLAN.md 9.2).
##
## The whole system is "add one tick to whoever is advancing, and promote them
## when they arrive". It is separate from ProductionSystem, which does the same
## shape of work for a building's training queue, because the two count entirely
## different things: production belongs to a BUILDING and dies with it, where an
## age belongs to the PLAYER and survives losing every building they own.
##
## Runs late, after everything that could cancel an advance. Nothing cancels one
## today -- there is no way to lose the research and no cost to be refunded -- but
## the order is the cheap half of that decision and the systems list is where it
## is legible.
class_name AgeSystem
extends SimSystem


func process_tick(w: SimWorld) -> void:
	for p in w.players:
		if p.tick_advance():
			# Nothing listens yet. When it does, this is the seam: an age landing
			# is exactly the moment the advancement banner (9.1) and the re-skin
			# of every standing building (2.7) both trigger from, and both read it
			# off the snapshot rather than from a signal, so there is nothing to
			# emit here that would not be a second source of truth.
			pass
