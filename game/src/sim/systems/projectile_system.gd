## Flies whatever `CombatSystem` loosed and despawns it on arrival (PLAN.md 4.13).
##
## Runs immediately BEFORE CombatSystem, which is what looses what it flies, so **an
## arrow is never advanced on the tick it was created**. It ran after at first and that
## was wrong in a way no test noticed: a short shot came out at one tick of flight, was
## spawned by CombatSystem and finished by this on the same tick, and so was created
## and destroyed between two snapshots without ever reaching a screen. A projectile
## system that provably worked and visibly did nothing.
##
## The arrow therefore appears at the shooter on the tick of the shot and starts moving
## on the next one, which is also how it reads: a bow twangs and then the arrow leaves.
##
## It deals no damage and can hit nothing. `SimProjectile`'s header records why: the
## blow landed the instant it was fired, and this only shows where it came from.
class_name ProjectileSystem
extends SimSystem


func process_tick(w: SimWorld) -> void:
	# Collected before despawning: `despawn()` mutates `entities`, which cannot be done
	# while iterating it. Sorted, because despawn order reaches `removed_this_tick` and
	# two clients disagreeing about it is a difference in the wire format for nothing.
	var landed: Array[int] = []
	for e in w.entities.values():
		if not (e is SimProjectile):
			continue
		var p: SimProjectile = e
		p.advance()
		if p.has_landed():
			landed.append(p.id)
	landed.sort()
	for id in landed:
		w.despawn(id)
