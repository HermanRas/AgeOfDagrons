## Units starting fights nobody ordered, within the limits the player set (PLAN.md 4.12).
##
## `CombatSystem`'s header has refused auto-acquire since 4.13 and named this phase as
## where it would come from. This is that arriving, and the split is what kept it cheap:
## everything here does is DECIDE, and what it hands over is an ordinary `Task.ATTACK`
## that `CombatSystem` then resolves exactly as it resolves an `AttackCommand`. There is
## no second combat path, and a fight started here is indistinguishable from an ordered
## one once it has started -- which is the property that made the whole feature ~150
## lines instead of a parallel machine.
##
## Runs BEFORE CombatSystem in the tick, so a unit that acquires this tick closes in on
## the same tick rather than standing still for one -- the same reasoning `CombatSystem`
## gives for sharing GatherSystem's slot.
##
## ONLY AN IDLE UNIT ACQUIRES, and that is the whole safety property. A villager
## gathering, a soldier walking somewhere, a builder on a foundation -- none of them
## reconsider, whatever their stance, so no stance can ever countermand an order the
## player gave. It also means there is no retaliation: a unit being shot at while busy
## does not turn around. Both are deliberate, and the second is the one worth knowing
## about, because it is the half a player is most likely to expect.
##
## THREE THINGS IT MUST NOT DO, each of which was a live risk rather than a hypothetical:
##
##   - **Pick a different target on two hosts.** Every scan below is a strict minimum
##     over (is_building, gap, id) walked in whatever order `entities_in_rect` returns,
##     which is NOT sorted -- the id tie-break is what makes the answer independent of
##     it. Two hosts whose armies engaged different raiders would kill different units
##     and diverge. This is `CombatSystem._reacquire`'s shape and deliberately so.
##   - **Shoot the livestock.** `Diplomacy.is_enemy` answers *"may I attack that"*, and
##     for a sheep the answer is yes. Auto-acquire needs *"who am I at war with"*, which
##     is `CombatSystem._is_at_war_with` -- CALLED, not copied, because the copy is the
##     mistake 4.9 shipped and `preview_garrison` caught. Same reason the `Diplomacy`
##     header exists.
##   - **Make gaia think.** Owner 0 is skipped outright. `WildlifeSystem` already owns
##     every fight an animal picks, through `aggro_radius`, and two mechanisms answering
##     "does this thing attack unasked" is exactly the duplication above.
class_name StanceSystem
extends SimSystem

## How far a DEFENSIVE unit looks for a fight, AND how far it will chase before turning
## back, as a Chebyshev radius in tiles from its guard post.
##
## ONE NUMBER FOR BOTH ON PURPOSE, because the two questions have one honest answer: a
## defender may fight anything it could have noticed from where it was standing. Two
## constants would let them disagree, and every way they can disagree is a bug -- a
## leash shorter than the sight radius makes a unit acquire a target and abandon it on
## the next tick, and a leash longer than it lets a defender be walked away from its post
## by a target that steps back one tile at a time.
##
## 5 is a little over half a screen at the zoom the game is played at, and is measured
## against the range ladder rather than chosen: it is longer than every infantry reach
## (archer 4, crossbowman 5) and shorter than every tower's (6, 7, 8), so a defensive
## line in front of a tower does not walk out from under its cover.
const GUARD_RADIUS := 5


func process_tick(w: SimWorld) -> void:
	for entry in w.entities.values():
		if not (entry is SimUnit):
			continue
		var u := entry as SimUnit
		# Gaia is WildlifeSystem's, always -- see the header's third rule.
		if not u.alive or u.owner_id == 0 or u.garrisoned_in != 0:
			continue
		if u.stance == SimUnit.Stance.PASSIVE:
			continue
		if u.task == SimUnit.Task.ATTACK:
			_check_leash(w, u)
		elif u.task == SimUnit.Task.IDLE:
			_settle_or_acquire(w, u)


## A DEFENSIVE unit that has been drawn too far from its post breaks off and walks back
## (project owner, 2026-08-29: "attacks, chases a little, RETURNS").
##
## Measured from the POST rather than from the target, which is the only measurement that
## cannot be walked: a fleeing enemy that keeps exactly four tiles ahead would lead a
## unit across the map under any target-relative rule, and that is precisely the "wolf
## chased a villager into the town centre" failure of 2026-08-28 with the roles swapped.
##
## Only DEFENSIVE has a leash. AGGRESSIVE deliberately has none -- it is the stance for
## an army you have decided to spend -- and STAND_GROUND can never be more than its own
## attack range from anywhere, because `CombatSystem._close_in` refuses to move it.
##
## `guard_post` being set is what says this fight was the unit's own idea; a player's
## `AttackCommand` clears it (`SimUnit.set_task_attack`), so an ordered assault is never
## recalled by a leash it did not opt into.
func _check_leash(w: SimWorld, u: SimUnit) -> void:
	if u.stance != SimUnit.Stance.DEFENSIVE or u.guard_post == SimUnit.NO_POST:
		return
	if _gap(u.tile(), u.guard_post) <= GUARD_RADIUS:
		return
	if w.paths != null:
		w.paths.cancel(u.id)
	u.return_to_post()
	if w.paths != null:
		w.paths.request(u.id, u.guard_post)


## An idle unit either finishes walking home, settles where it is, or picks a fight.
##
## The order matters: a unit still owing a return walks back FIRST and only considers a
## new target once it is home. Without that, a defender that killed something at the end
## of its leash would acquire the next raider from where it happened to stop, and its
## post would ratchet forward one fight at a time until it was somewhere else entirely.
func _settle_or_acquire(w: SimWorld, u: SimUnit) -> void:
	if u.guard_post != SimUnit.NO_POST:
		if _gap(u.tile(), u.guard_post) > 1:
			u.return_to_post()
			if w.paths != null:
				w.paths.request(u.id, u.guard_post)
			return
		# Home, or near enough that another step would be fussing. The post is
		# released here and NOT on arrival, because an unreachable post retires the
		# walk (`SimUnit.set_path` on an empty route) and leaves the unit idle
		# somewhere else -- so arrival is not a signal that can be relied on, and
		# "idle and close enough" is.
		u.guard_post = SimUnit.NO_POST

	var def := w.unit_def(u.def_id)
	# Nothing to fight WITH. `CombatSystem._process` would retire the order on the very
	# tick it saw it, so acquiring here would be a unit that twitches once a tick
	# forever. `default_stance_for` already puts these on PASSIVE, so this only catches
	# a player who set a stance on one deliberately.
	if def == null or def.attack_damage <= 0:
		return
	# A PACKED ENGINE DOES NOT VOLUNTEER (4.13). It cannot fire, and acquiring would set
	# `SiegeSystem` deploying -- 3 to 8 seconds of folding out -- for a target that is
	# free to keep walking. Again only reachable if a player chose this stance for it.
	if not u.can_fire():
		return

	var radius := _sight_of(u, def)
	if radius <= 0:
		return
	var target := _nearest_target(w, u, radius)
	if target == null:
		return

	var post := u.tile()
	var at := target.tile()
	u.set_task_attack(int(target.id), at)
	# STAND_GROUND NEVER ASKS FOR A ROUTE. Anything it can acquire is already inside its
	# own attack range, so `CombatSystem._process` finds it in reach on the next tick and
	# strikes without moving. Requesting a path anyway would spend a slot of
	# PathService's per-tick budget on a route the unit is forbidden to walk.
	if u.stance == SimUnit.Stance.STAND_GROUND:
		u.arrive()
	else:
		if w.paths != null:
			w.paths.request(u.id, at)
	if u.stance == SimUnit.Stance.DEFENSIVE:
		u.guard_post = post


## How far this unit looks, per stance, in tiles.
##
## AGGRESSIVE uses the unit's own LINE OF SIGHT, which is the honest bound: it is exactly
## what that unit can see, it is already declared per unit in units.json, and it is
## already what the fog lets its owner see. A separate aggression radius would be a
## second number meaning the same thing and drifting from it.
##
## ⚠️ **BUT NEVER LESS THAN A DEFENSIVE UNIT SEES, and that floor is not tidiness.**
## `unit.militia` declares `los: 4` against `GUARD_RADIUS`'s 5 -- so without the `maxi`
## an aggressive militia notices LESS than a defensive one, and the stance a player picks
## to make a unit start more fights makes it start fewer. Six of the roster's `los`
## values sit at or below 5, so this is the common case rather than a corner. Found by
## `test_an_aggressive_soldier_reaches_further_than_a_defensive_one`, which was written
## to pin the ordering and did exactly that on its first run.
##
## STAND_GROUND uses its ATTACK RANGE and the `maxi(1, ...)` is the same "melee is range
## 0 in the data and reach 1 on the map" rule `CombatSystem._within_reach` documents --
## without it every melee unit on Stand Ground would be unable to acquire anything,
## including the enemy standing next to it.
static func _sight_of(u: SimUnit, def: UnitDef) -> int:
	match u.stance:
		SimUnit.Stance.AGGRESSIVE:
			return maxi(def.los, GUARD_RADIUS)
		SimUnit.Stance.DEFENSIVE:
			return GUARD_RADIUS
		SimUnit.Stance.STAND_GROUND:
			return maxi(1, def.attack_range)
	return 0


## The nearest thing this unit may start a fight with, or null.
##
## Units before buildings, then distance, then lowest id -- `CombatSystem._reacquire`'s
## ordering, and for its reasons: a building cannot run away and will still be there
## afterwards, and the triple is a strict minimum so the answer does not depend on the
## unsorted order `entities_in_rect` returns.
##
## BUILDINGS ARE INCLUDED AND THAT IS A REAL CHOICE. An AGGRESSIVE army walking past an
## enemy house will stop and knock it down, which is what aggressive means in the genre.
## For DEFENSIVE it is nearly unreachable in practice -- an enemy building within five
## tiles of where your soldier is standing is a border you have already lost -- and for
## STAND_GROUND it is what lets a line hold against something built on top of it.
func _nearest_target(w: SimWorld, u: SimUnit, radius: int) -> SimEntity:
	var here := u.tile()
	var span := radius * 2 + 1
	var rect := Rect2i(here - Vector2i(radius, radius), Vector2i(span, span))

	var best: SimEntity = null
	var best_is_building := 0
	var best_gap := 0
	for e in w.entities_in_rect(rect):
		if not _may_start_on(w, e, u.owner_id):
			continue
		var is_building := 1 if e is SimBuilding else 0
		var gap := CombatSystem.tile_gap(here, CombatSystem._rect_of(e))
		if gap > radius:
			continue          # the scan rect is a square; the radius is the real bound
		if best != null:
			if is_building > best_is_building:
				continue
			if is_building == best_is_building:
				if gap > best_gap:
					continue
				if gap == best_gap and int(e.id) > best.id:
					continue
		best = e
		best_is_building = is_building
		best_gap = gap
	return best


## Whether `e` is something `owner_id` may open fire on unasked.
##
## The unit half is `CombatSystem._is_at_war_with`, CALLED rather than reimplemented --
## see the header. It is what keeps a sheep, and a player's own herded flock, out of an
## auto-acquired fight while leaving a wolf or a bear in one.
##
## A BUILDING IS ONLY EVER AN ENEMY PLAYER'S, and never gaia's, so the two halves cannot
## share a predicate: gaia owns the trees and the mines, `Diplomacy.is_enemy` correctly
## says a resource node is scenery, and a rule that asked it about buildings would be
## asking a question with no wrong answer and no useful one. A foundation is excluded
## because shooting one is a border war nobody declared, which is `_process_building`'s
## reasoning for the same exclusion.
static func _may_start_on(w: SimWorld, e: SimEntity, owner_id: int) -> bool:
	if e is SimUnit:
		return CombatSystem._is_at_war_with(w, e as SimUnit, owner_id)
	if e is SimBuilding:
		var b := e as SimBuilding
		return b.alive and b.owner_id != 0 and b.owner_id != owner_id and b.is_complete()
	return false


## Chebyshev gap between two tiles. `CombatSystem.tile_gap` measures to a Rect2i and a
## post is a bare tile, so wrapping it in a 1x1 rect would be the longer way to say this.
static func _gap(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
