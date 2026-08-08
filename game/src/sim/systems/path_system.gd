## Drains PathService's request queue against its per-tick budget (PLAN.md 4.2).
## Phase 4.2.
##
## Runs after CommandSystem and before MovementSystem, so an order issued this
## tick is planned this tick (budget permitting) and walked the same tick. The
## other order -- moving first -- would cost every order a tick of visible delay.
class_name PathSystem
extends SimSystem

func process_tick(w: SimWorld) -> void:
	if w.paths != null:
		w.paths.process(w)
