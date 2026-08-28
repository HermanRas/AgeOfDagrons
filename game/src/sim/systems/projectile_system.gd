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


## ONE TICK OF ARRIVAL BEFORE IT GOES (2026-08-28), which is a one-word change with two
## jobs. `advance()` clamps `pos` to `target_pos` on the tick a shot lands, and despawning
## on that same tick threw that position away before any snapshot carried it -- so every
## arrow in the game visibly vanished about one and a half tiles SHORT of what it was
## fired at, which is the distance `SimProjectile.SPEED` covers in a tick. Nobody had
## reported it because an arrow is on screen for two ticks and it is hard to see what a
## sprite failed to do.
##
## It is also what makes the project owner's spent-arrow decals possible at all
## (`SpentProjectiles`): the view learns where a shot ended from the last snapshot that
## carried it, so that snapshot has to be the one where it arrived.
##
## `elapsed_ticks > total_ticks` rather than `has_landed()`, therefore -- landed stays
## "it is there", and this is "it has been there for a tick".
func process_tick(w: SimWorld) -> void:
	# Collected before despawning: `despawn()` mutates `entities`, which cannot be done
	# while iterating it. Sorted, because despawn order reaches `removed_this_tick` and
	# two clients disagreeing about it is a difference in the wire format for nothing.
	var spent: Array[int] = []
	for e in w.entities.values():
		if not (e is SimProjectile):
			continue
		var p: SimProjectile = e
		p.advance()
		if p.elapsed_ticks > p.total_ticks:
			spent.append(p.id)
	spent.sort()
	for id in spent:
		w.despawn(id)
