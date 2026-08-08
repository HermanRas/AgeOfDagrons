## Reacts to hp reaching 0 (PLAN.md 4.7, 5.5, 5.6). Nothing currently deals
## damage except the debug destroy command -- combat lands later and will drive
## the same `alive` flag SimEntity.take_damage() already sets, so this system
## needs no changes when it does.
##
## Runs last in SimWorld.setup()'s system order: everything else this tick has
## already acted on a unit or building while it still could.
class_name DeathSystem
extends SimSystem

func process_tick(w: SimWorld) -> void:
	var to_despawn: Array[int] = []
	for e in w.entities.values():
		if e is SimUnit:
			_process_unit(e as SimUnit, to_despawn)
		elif e is SimBuilding:
			_process_building(w, e as SimBuilding)

	for id in to_despawn:
		w.despawn(id)


## A unit's death plays out over time -- die anim, drop cargo, corpse, decay,
## then gone -- rather than vanishing the tick hp hits 0 (4.7). `corpse_ticks_left`
## starting at -1 is what tells a fresh death (set it up) from one already under
## way (just count it down); `alive` itself only ever goes false once and cannot
## carry that distinction.
func _process_unit(u: SimUnit, to_despawn: Array[int]) -> void:
	if u.alive:
		return

	if u.corpse_ticks_left < 0:
		u.anim = &"die"
		# A dead villager has nothing left to deliver -- MVP has no resource pile
		# to drop it into, so the load is simply lost rather than teleporting home.
		u.carry_amount = 0
		u.carry_kind = &""
		u.corpse_ticks_left = SimUnit.CORPSE_TOTAL_TICKS
		return

	u.corpse_ticks_left -= 1
	if u.corpse_ticks_left == SimUnit.CORPSE_FADE_TICKS:
		u.anim = &"decay"          # the last 10 s, fading out (4.7)
	if u.corpse_ticks_left <= 0:
		to_despawn.append(u.id)


## A destroyed building becomes rubble rather than despawning outright (5.5) --
## unlike a unit's corpse it has no fade timer, since 0 A.D.'s rubble art has no
## decay animation to play (A.2's building-art note) and PLAN.md never asks it to
## disappear. `free_footprint()` frees its tiles the same tick it falls, so a new
## building can go up on the ground it held without waiting for anything.
func _process_building(w: SimWorld, b: SimBuilding) -> void:
	if b.alive or b.phase == SimBuilding.Phase.DESTROYED:
		return
	b.phase = SimBuilding.Phase.DESTROYED
	w.free_footprint(b.id)
