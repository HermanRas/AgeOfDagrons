## An arrow, bolt or stone in flight (PLAN.md 4.13).
##
## **IT CARRIES NO DAMAGE.** The hit lands the instant it is fired, exactly as it did
## before projectiles existed -- `CombatSystem` calls `take_damage()` and then spawns
## one of these to show where the blow came from. The project owner's call on
## 2026-08-22, and it is what `CombatSystem`'s header had already reserved: *"nothing
## about the damage model below changes when it arrives"*.
##
## So this is a piece of sim state whose only job is to be looked at, and that is worth
## being honest about rather than dressing up. What it buys is the thing that was
## actually wrong: ranged combat resolved with no visible cause, and a player watching
## an archer could not tell who it was shooting or whether it was shooting at all.
##
## What it costs is that the health bar drops about 400 ms before the arrow lands. The
## alternative -- damage on arrival -- was considered and refused: it makes every
## ranged DPS number in units.json wrong by the flight time, it needs an overkill rule
## for the N arrows already in the air when a target dies, and it raises the question
## of what happens when the SHOOTER dies mid-flight. None of that is a mystery, but all
## of it is balance work, and none of it was what the complaint was about.
##
## IT IS A REAL ENTITY rather than an event on the snapshot, and that is the cheap
## option rather than the thorough one. As an entity it inherits the whole existing
## pipeline for free: it is fog-filtered by the same `_entry_for` that filters
## everything else (so you do not see arrows over ground you cannot see), it despawns
## through `removed_this_tick`, and `EntityViewPool` gives it a pooled sprite with no
## new lifecycle to get wrong. An events channel would have needed its own copy of all
## three.
class_name SimProjectile
extends SimEntity

## Sub-units per tick. 384 is one and a half tiles a tick, so an archer's 4-tile shot
## is in the air for 2 ticks and a trebuchet's 12-tile lob for 8 -- long enough to read
## as travel at 10 Hz, short enough that the instant damage is not visibly early.
##
## It was 512 first, and that was too fast to see: at two tiles a tick an archer's shot
## came out at ONE tick of flight, which `ProjectileSystem` then finished on the very
## tick `CombatSystem` loosed it. The arrow was created and destroyed between two
## snapshots and never reached a screen -- a projectile system that provably worked and
## visibly did nothing, which is the exact complaint it was built to answer.
##
## ONE SPEED FOR EVERY PROJECTILE, deliberately. A stone should plainly fly slower than
## an arrow and the honest place for that is a number beside `projectile` in
## units.json; it is not here yet because nothing has looked at the three of them side
## by side to say what the numbers should be. When that happens this becomes a field
## and `SimWorld.spawn_projectile` takes it as an argument -- no other code changes.
const SPEED := 384

## No shot is ever in the air for less than this. One tick is a sprite that appears and
## vanishes with nothing in between; two is the shortest flight the eye reads as
## movement, because the view interpolates across each one.
const MIN_FLIGHT_TICKS := 2

## Where it was loosed from and where it is going, in sub-tile units. The destination
## is fixed AT SPAWN and never re-read: the target may be dead and despawned before
## this lands, and an arrow that curved to follow a corpse would be stranger than one
## that thuds into the ground where the enemy was standing.
var origin_pos: Vector2i = Vector2i.ZERO
var target_pos: Vector2i = Vector2i.ZERO

var total_ticks: int = 1
var elapsed_ticks: int = 0

## Which of the eight ways it is pointing, fixed at spawn like the destination is.
## The art is baked at five directions mirrored to eight, so an arrow that did not
## carry one would fly east whichever way it was actually going.
var facing: int = 0


## How many ticks a shot from `from` to `to` should take: the distance at `SPEED`,
## floored at `MIN_FLIGHT_TICKS` so a point-blank shot is still something the player
## can see rather than a sprite that exists between two snapshots.
static func flight_ticks(from: Vector2i, to: Vector2i) -> int:
	var span: int = maxi(absi(to.x - from.x), absi(to.y - from.y))
	return maxi(MIN_FLIGHT_TICKS, span / SPEED)


## Move one tick along the line. Integer throughout, like everything else in the sim --
## a float here would be free to round differently on an ARM phone than on an x86 host,
## and this rides in `state_hash()`.
func advance() -> void:
	elapsed_ticks += 1
	if has_landed():
		pos = target_pos
		return
	pos = origin_pos + (target_pos - origin_pos) * elapsed_ticks / total_ticks


func has_landed() -> bool:
	return elapsed_ticks >= total_ticks


## Projectiles move, so the fog never sends one over ground the viewer cannot see.
## See `SimEntity.is_mobile` for what that prevents.
func is_mobile() -> bool:
	return true


## `anim` and `facing` in the shape a UNIT sends them, because that is the branch
## `GameView` already takes to drive a sprite's animation and direction -- a projectile
## needs no new code on the view side at all.
##
## The literal `&"static"` rather than `AtlasEntry.STATIC_ANIM`: the sim may not name a
## `view/` class (PLAN.md 4, and `test_sim_boundary` greps for exactly that). The two
## agree by convention, and `AtlasEntry.resolve_anim` falls back rather than drawing
## nothing if they ever stop agreeing.
func to_snapshot() -> Dictionary:
	var d := super()
	d["anim"] = &"static"
	d["facing"] = facing
	return d
