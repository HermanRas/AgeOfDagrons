## Units hitting things (PLAN.md 4.13). Walk to the target, stand at reach, and
## strike on a cooldown until it is dead.
##
## Runs in the same slot as GatherSystem and BuildSystem, and for the same
## reason: an attacker that arrived last tick strikes THIS tick, and a chase that
## needs a fresh route starts it in time for MovementSystem to walk the first step
## of it before the tick is out. It runs before DeathSystem, so a kill landing
## here is turned into a corpse on the very tick it happens rather than living a
## tick past zero hp.
##
## It does NOT deal the damage itself in any special way -- it calls the same
## `SimEntity.take_damage()` the debug destroy command has used since 4.7, which
## is why DeathSystem needed no changes to handle a unit killed in battle.
##
## WHAT THIS PHASE DELIBERATELY DOES NOT DO:
##
## - **No auto-acquire OF ITS OWN, and still no retaliation.** This line used to end
##   "that is stances (4.12)", and 4.12 arrived on 2026-08-29 -- so read the split
##   carefully, because it is the same one that kept the promise cheap. `StanceSystem`
##   decides whether an IDLE unit starts a fight and hands it over as an ordinary
##   `Task.ATTACK`; everything in this file still only ever resolves a fight somebody
##   asked for. The villager the old text warned about is still safe, by data rather
##   than by omission: `SimUnit.default_stance_for` puts every worker on PASSIVE.
##   **Retaliation is genuinely still absent** -- a unit already busy gathering or
##   walking does not turn on whatever is hitting it, whatever its stance, because
##   noticing that would mean plumbing an attacker through `take_damage` and
##   `WildlifeSystem` records why it refused to (it watches hp instead).
## - **Projectiles are COSMETIC, and arrived on 2026-08-22.** A ranged hit still lands
##   the instant it is fired -- this line used to say "no projectiles" and predicted
##   that "nothing about the damage model below changes when it arrives", which is
##   exactly the shape the project owner chose. `SimProjectile` is spawned after the
##   damage and carries none of it. What that buys is the thing that was wrong: ranged
##   combat resolved with no visible cause. What it costs is that the health bar drops
##   about 400 ms before the arrow lands.
## - **No siege pack/unpack state machine and no hostile wolf**, both of which
##   PLAN.md files under 4.13. They are separate machines rather than the shape of
##   combat, and neither has a unit on the map to exercise it yet.
class_name CombatSystem
extends SimSystem

## The least any hit may land for, however heavily armoured the target. Armour
## SHOULD blunt an attack; it must never make a defender literally invulnerable
## to a whole class of unit, because there is no other way for the player to
## discover that their army is doing nothing -- the health bar simply never moves
## and nothing says why.
const MIN_DAMAGE := 1

## How far a unit looks for its next target when the one it was fighting dies,
## as a Chebyshev radius in tiles -- 2 is the 5x5 box the project owner asked
## for on 2026-08-20. Deliberately small: this is "finish what is in front of
## you", not an aggro range that pulls a unit across the map.
const REACQUIRE_RADIUS := 2


## How far a building looks for something to shoot at, as a multiplier on its own
## `attack_range`. 1 -- it shoots what it can reach and nothing further.
##
## Named rather than inlined because the temptation is to make it wider than the
## reach so a tower "notices" an enemy walking up. It must not be: a target chosen
## outside reach cannot be hit, and the tower would spend every tick holding a target
## it does nothing about, which is indistinguishable from being broken.
const BUILDING_SIGHT := 1

## How far apart two projectiles of one volley fly, in sub-tile units. 96 of a 256
## sub-tile, so a five-stone volley from a watch tower is spread about 1.5 tiles across
## -- wide enough to read as five at the zoom the game is played at, narrow enough that
## the outermost stone still plainly belongs to the same shot.
##
## The fan is measured in HALF steps (see `_loose_volley`), so this is the gap between
## neighbours and not the width of the whole thing.
const VOLLEY_SPREAD := 96


func process_tick(w: SimWorld) -> void:
	for entry in w.entities.values():
		if entry is SimUnit and entry.alive and entry.task == SimUnit.Task.ATTACK:
			_process(w, entry)
		elif entry is SimBuilding and entry.alive and entry.attack_damage > 0:
			_process_building(w, entry)


## A TOWER OR CASTLE SHOOTING WHATEVER COMES INTO RANGE (PLAN.md 4.9). New on
## 2026-08-27; before it, buildings could only ever be targets, and this file's own
## header said `armor` should be added to BuildingDef "the day buildings should
## resist arrows" -- that day is still not today, only the other half arrived.
##
## **THIS IS AUTO-ACQUIRE, AND THE HEADER'S RULE AGAINST IT DOES NOT APPLY.** That
## rule is about units: a unit fights what it was ORDERED to fight, because guessing
## means every villager charging the first enemy that walks past. A building cannot be
## ordered to attack anything -- there is no command that would name it as the
## attacker, and no player would ever issue one per tower per fight -- so for a
## building auto-acquire is not a shortcut past a decision, it is the only way the
## data on the def can ever mean anything. Nothing here relaxes 4.12's stances, and
## the two mechanisms share no code.
##
## THREE THINGS IT DELIBERATELY DOES NOT DO. It never chases, obviously. It never
## fires on a foundation's behalf (`is_complete`), because a tower you have not
## finished paying for should not defend you. And it does not pick BUILDINGS as
## targets: a building cannot walk into range, so the only way a tower could be
## shooting one is if somebody built next door, and a tower that opens fire on a
## newly placed house across the border is a border war nobody declared.
func _process_building(w: SimWorld, b: SimBuilding) -> void:
	if b.attack_cooldown > 0:
		b.attack_cooldown -= 1
	if not b.is_complete():
		return

	var target := _nearest_hostile_unit(w, b)
	if target == null:
		return
	if b.attack_cooldown > 0:
		return

	# THE GARRISON'S CONTRIBUTION IS ADDED HERE, once per shot (4.9). Fifteen archers
	# in a castle are one heavier arrow every two seconds, not sixteen arrows -- see
	# `SimBuilding.attack_bonus` for why that is the shape the owner asked for.
	var damage := b.attack_damage + b.attack_bonus(w)
	target.take_damage(_damage_after_armour(w, target, damage, b.attack_type), 0)
	# After the damage and carrying none of it, exactly as a unit's shot is. A tower
	# firing invisibly would be the "ranged combat resolved with no visible cause"
	# problem the header describes, and worse here: there is no archer sprite drawing
	# a bow to explain where the hit came from.
	_loose_volley(w, b, target.pos)
	b.attack_cooldown = maxi(1, b.attack_cooldown_ticks)


## Everything one shot DRAWS: `attack_volley` of the building's own projectile, plus one
## per garrisoned archer of that archer's own (project owner, 2026-08-28 -- *"watch tower
## is not showing 5x rocks when attacking + X x arrows for each archer in garrison"*).
##
## **NOT A DAMAGE CHANGE, and the separation is the point.** The blow above already
## landed, once, and already includes `attack_bonus`. `SimProjectile` carries no damage,
## so this is the shot being visible rather than the shot being bigger -- fifteen archers
## in a castle are still one heavier arrow every two seconds, now drawn as fifteen.
##
## FANNED, because five projectiles from one point to one point are one projectile. Each
## is offset perpendicular to the line of flight by a fixed step, symmetrically about the
## middle -- so an odd volley has a shot straight down the middle and an even one
## straddles it. The offset moves BOTH ends by the same amount rather than spreading the
## arrival: arrows converging on a single sub-tile look like they are being sucked in,
## and arrows spreading from one origin look like they were fired by one very confused
## archer. A parallel fan reads as a volley.
##
## Integer throughout, and the perpendicular is scaled by a Chebyshev norm rather than a
## real one -- `maxi(absi(x), absi(y))`, the same cheap measure `SimProjectile.flight_ticks`
## uses. It rides in `state_hash()` through the projectiles it spawns, so a float here
## would be free to round differently on an ARM phone than on an x86 host.
func _loose_volley(w: SimWorld, b: SimBuilding, at: Vector2i) -> void:
	var shots: Array[StringName] = []
	if b.attack_projectile != &"":
		for i in range(maxi(1, b.attack_volley)):
			shots.append(b.attack_projectile)
	shots.append_array(b.garrison_projectiles(w))
	_fan(w, shots, b.owner_id, b.pos, at)


## The fan itself, shared by a building's volley and a UNIT's (project owner, 2026-08-30
## -- the galley). Extracted rather than copied: the arithmetic below is the only thing
## standing between "ten arrows" and "one arrow drawn ten times", and two copies of it
## would be two chances for a warship's fan to disagree with a tower's.
##
## `from` is a sub-tile position and not an entity, because that is the only thing the
## two callers have in common -- a `SimBuilding` shoots from its centre and a `SimUnit`
## from wherever it is standing.
##
## Integer throughout, and the perpendicular is scaled by a Chebyshev norm rather than a
## real one -- `maxi(absi(x), absi(y))`, the same cheap measure `SimProjectile.flight_ticks`
## uses. It rides in `state_hash()` through the projectiles it spawns, so a float here
## would be free to round differently on an ARM phone than on an x86 host.
static func _fan(w: SimWorld, shots: Array[StringName], owner_id: int,
		from: Vector2i, at: Vector2i) -> void:
	if shots.is_empty():
		return
	var d := at - from
	var norm := maxi(1, maxi(absi(d.x), absi(d.y)))
	# Perpendicular to the flight line, one VOLLEY_SPREAD long.
	var across := Vector2i(-d.y * VOLLEY_SPREAD / norm, d.x * VOLLEY_SPREAD / norm)
	for i in range(shots.size()):
		# Symmetric about the middle: -(n-1)/2 .. +(n-1)/2 in halves, doubled so it
		# stays in integers. `2 * i - (n - 1)` is that, scaled by VOLLEY_SPREAD / 2.
		var step := 2 * i - (shots.size() - 1)
		var offset := across * step / 2
		w.spawn_projectile(shots[i], owner_id, from + offset, at + offset)


## The nearest hostile UNIT within reach of `b`'s footprint, or null.
##
## Deterministic, and it has to be: a strict minimum over (distance, id) walked in
## the order `entities_in_rect` happens to return, which is NOT sorted -- so the id
## tie-break is what makes the answer independent of it. Two hosts whose towers shot
## different targets would kill different units and diverge. Same shape as
## `_reacquire` above, one field shorter because a building never prefers a unit over
## a building: it only ever considers units.
##
## Queried as a RECT around the footprint rather than a radius from the centre, so
## the box a castle scans matches the reach `tile_gap` then measures. A radius from
## `b.tile()` would under-reach on the far side of a 7x7 by three tiles.
func _nearest_hostile_unit(w: SimWorld, b: SimBuilding) -> SimEntity:
	var reach := maxi(1, b.attack_range) * BUILDING_SIGHT
	var rect := b.footprint_rect().grow(reach)

	var best: SimEntity = null
	var best_gap := 0
	for e in w.entities_in_rect(rect):
		if not (e is SimUnit):
			continue
		if not _is_at_war_with(w, e as SimUnit, b.owner_id):
			continue
		var gap := tile_gap(e.tile(), b.footprint_rect())
		if gap > reach:
			continue          # `grow` is a square; the reach test is the real bound
		if best != null:
			if gap > best_gap:
				continue
			if gap == best_gap and int(e.id) > best.id:
				continue
		best = e
		best_gap = gap
	return best


## Whether a tower should open fire on `u` unasked.
##
## **`Diplomacy.is_enemy` IS THE WRONG QUESTION HERE, AND THE PREVIEW CAUGHT IT.** That
## predicate answers *"may `player_id` attack this"* -- and the answer for a sheep is
## yes, because hunting is how a deer becomes food (6.1a). Auto-acquire needs the other
## question, *"who am I at war with"*, which is exactly the distinction
## `AISystem._nearest_enemy` records having kept its own copy for: routing the AI's
## target search through `Diplomacy` would march its army off to hunt bears.
##
## Using `is_enemy` here had a watch tower shooting the livestock. Worse, a HERDED sheep
## is still gaia's -- `SimUnit.herded_by` is deliberately separate from `owner_id`
## (6.5) -- so a player's own flock grazing past their own tower was slaughtered by it,
## and `preview_garrison` found it by a side effect: the tower spent every shot on an
## animal two tiles away and never touched the raider five tiles out, which is also how
## an archer standing outside ended up dead.
##
## So: an enemy PLAYER's units always, and a gaia animal only if it is a PREDATOR.
## `aggro_radius > 0` is the data already saying which animals pick fights (wolf, bear,
## boar carry one; sheep, cattle and deer are 0), so a bear wandering into a settlement
## is still shot -- which is what a watch tower is for -- and the flock is not.
static func _is_at_war_with(w: SimWorld, u: SimUnit, owner_id: int) -> bool:
	if not u.alive or u.owner_id == owner_id:
		return false
	if u.owner_id != 0:
		return true
	var d := w.unit_def(u.def_id)
	return d != null and d.aggro_radius > 0


func _process(w: SimWorld, u: SimUnit) -> void:
	# Counts down whatever else happens this tick, including while walking, so a
	# unit that closes the distance arrives ready to swing rather than paying its
	# cooldown twice over.
	if u.attack_cooldown > 0:
		u.attack_cooldown -= 1

	var def := w.unit_def(u.def_id)
	if def == null or def.attack_damage <= 0:
		u.stop()
		return

	var target := w.get_entity(u.task_target_id)
	if target == null or not target.alive:
		# Killed by somebody else while this one was still walking over. Look
		# around before standing down -- see `_reacquire`.
		if not _reacquire(w, u):
			u.stop()
		return

	if not _within_reach(u, target, reach_of(w, u, def)):
		_close_in(w, u, target)
		return

	# In reach: stop walking but stay on the order, and turn to face what is
	# being hit -- an archer loosing at something behind it reads as a bug even
	# though the damage is right.
	if u.has_waypoint() or u.path_pending:
		if w.paths != null:
			w.paths.cancel(u.id)
		u.halt()
	u.facing = SimUnit.facing_toward(target.pos - u.pos)

	if u.attack_cooldown > 0:
		return
	# A PACKED SIEGE ENGINE HOLDS ITS FIRE (4.13). It is in range, it is facing the
	# right way and it is on the order -- it simply has its arm folded onto a wagon.
	# `SiegeSystem` saw the same arrival a moment ago and started setting it up; this is
	# the few seconds in between, and it is the entire cost of having moved.
	#
	# Deliberately AFTER the cooldown tick-down and after the facing, so a trebuchet
	# spends its reload while deploying instead of paying both in series, and so it is
	# already pointed at the target when it comes up. True for every non-siege unit, so
	# nothing else in the roster notices.
	if not u.can_fire():
		return
	target.take_damage(_damage_against(w, u, target, def), 0)
	# THE ARROW IS LOOSED AFTER THE DAMAGE, and it carries none of it (4.13). The blow
	# has already landed; this is only what shows where it came from. `SimProjectile`'s
	# header has the argument for keeping those two apart, and the consequence: the
	# health bar drops about 400 ms before the arrow arrives.
	#
	# Aimed at where the target IS RIGHT NOW, captured here rather than followed --
	# see `SimProjectile.target_pos`. Nothing is spawned for a unit whose def names no
	# projectile, which is every melee unit and the dragon.
	#
	# A UNIT CAN VOLLEY TOO SINCE 2026-08-30, and one does: `unit.galley` at 10 (project
	# owner, *"Galley WarShip does not render arrows, it needs to do batchs of 10"*).
	# Everything else in the roster declares no `volley` and gets 1, which is the single
	# arrow this line has always spawned. See `UnitDef.attack_volley` for the wire price
	# and for why the damage above is untouched.
	if def.attack_projectile != &"":
		var shots: Array[StringName] = []
		for i in range(maxi(1, def.attack_volley)):
			shots.append(def.attack_projectile)
		_fan(w, shots, u.owner_id, u.pos, target.pos)
	u.attack_cooldown = maxi(1, def.attack_cooldown_ticks)
	# Retire on the killing blow rather than noticing next tick. A tick of
	# swinging at something already dead is a tick of the attack animation
	# playing over a corpse, and AnimationSystem runs later in this same tick --
	# so the difference is visible, not merely tidy.
	if not target.alive and not _reacquire(w, u):
		u.stop()


## The next thing to hit, within `REACQUIRE_RADIUS` of where the unit is standing
## (project owner, 2026-08-20). True if one was found and the unit is now on it.
##
## **This is not the auto-acquire the header rules out, and the difference is what
## makes it safe.** A unit only reaches here because it was ORDERED to attack and
## that order just ended with its target dead. An idle villager still never picks
## a fight, and being shot at still does not make anybody turn around -- that is
## still stances (4.12). What this removes is only the bit where an army kills one
## unit of a group and then stands among the rest doing nothing.
##
## Units before buildings, as asked: a building cannot run away and will still be
## there afterwards, whereas whatever just killed your target is next to you now.
## Ties break by distance and then by lowest id, and the winner is a strict
## minimum over that triple -- so the choice does not depend on the order
## `entities_in_rect` happens to return, which is not sorted and must not be
## trusted to be. Two hosts pick the same next target or the match desyncs.
##
## The path request at the end is NOT optional, however close the new target is.
## `set_task_attack` raises `path_pending`, and `_close_in` reads that as "already
## on the way" and returns -- so a re-acquire that skipped the request left the
## unit standing beside its new target forever, planning a route nobody had asked
## for. It cost a test to find and it would have looked exactly like the AI's
## villagers freezing. If the target turns out to be within reach anyway, the next
## tick cancels this and halts, the same self-correction an ordinary attack gets.
func _reacquire(w: SimWorld, u: SimUnit) -> bool:
	if w.paths == null:
		return false
	var here := u.tile()
	var span := REACQUIRE_RADIUS * 2 + 1
	var rect := Rect2i(here - Vector2i(REACQUIRE_RADIUS, REACQUIRE_RADIUS),
			Vector2i(span, span))

	var best_id := 0
	var best_is_building := 0
	var best_gap := 0
	for e in w.entities_in_rect(rect):
		# Trees are not belligerents and wolves are -- both are gaia, so the test
		# cannot be about owner 0 alone. `Diplomacy` owns that distinction; before
		# it, this line was one of four copies of the same clause.
		if not Diplomacy.is_enemy(e, u.owner_id):
			continue
		var is_building := 1 if e is SimBuilding else 0
		var gap := tile_gap(here, _rect_of(e))
		if best_id != 0:
			if is_building > best_is_building:
				continue
			if is_building == best_is_building:
				if gap > best_gap:
					continue
				if gap == best_gap and int(e.id) > best_id:
					continue
		best_id = int(e.id)
		best_is_building = is_building
		best_gap = gap

	if best_id == 0:
		return false
	var next_tile: Vector2i = w.get_entity(best_id).tile()
	# `keep_post`: this is the same fight carrying on, so a DEFENSIVE unit that killed
	# one raider and turned on the next still owes its guard post a return (4.12).
	# Without it, finishing off a pair would silently release the leash.
	u.set_task_attack(best_id, next_tile, true)
	w.paths.request(u.id, next_tile)
	return true


## Walk toward the target, re-planning only when the current route RUNS OUT.
##
## Not every tick, which is the obvious alternative and the wrong one:
## PathService solves a budgeted handful of searches per tick (4.2), and a dozen
## attackers each asking for a fresh path every tick would starve that queue for
## everyone else on the map -- including the villagers, whose orders would then
## visibly stall whenever a fight started somewhere they could not see.
##
## The cost of re-planning on arrival instead is that a fleeing target is chased
## in legs rather than smoothly. Chasing still converges, because each leg starts
## from where the target actually was; it just looks stepped when the quarry is
## faster than the pursuer, which is the case that is meant to get away.
## STAND_GROUND IS ENFORCED HERE AND NOWHERE ELSE (4.12), which is why it costs three
## lines rather than a system: the stance is entirely "never take a step to fight", and
## this function is the only place a fight ever takes one. A unit holding the line whose
## target walks out of reach stands down rather than following it -- which is the stance
## behaving correctly and not a failure to chase.
##
## It applies to an ORDERED attack too, deliberately. A player who has set a unit to hold
## its ground and then tells it to attack something across the map has asked for two
## contradictory things, and the stance is the standing instruction; the way to send that
## unit anywhere is to move it, or to take it off Stand Ground.
func _close_in(w: SimWorld, u: SimUnit, target: SimEntity) -> void:
	if u.stance == SimUnit.Stance.STAND_GROUND:
		u.stop()
		return
	if u.path_pending or u.has_waypoint():
		return          # already on the way
	if w.paths == null:
		u.stop()
		return
	# `keep_post`: re-planning toward a target that has moved is the same fight, not a
	# new order, so a DEFENSIVE unit keeps the post it owes a return to (4.12). This is
	# the call site that made `keep_post` necessary -- it fires every time a chase's
	# route runs out, so without it a leash would be released within a few tiles.
	u.set_task_attack(u.task_target_id, target.tile(), true)
	w.paths.request(u.id, target.tile())


## Chebyshev gap in TILES between a unit and its target's footprint: 0 standing
## on it, 1 adjacent, and so on. A footprint, not a centre -- an 8x8 town centre
## attacked from its own doorstep is at reach 1, where a centre-to-centre
## measurement would call it 4 away and leave every melee unit in the game unable
## to touch a building it is standing against.
static func tile_gap(from: Vector2i, rect: Rect2i) -> int:
	var cx := clampi(from.x, rect.position.x, rect.end.x - 1)
	var cy := clampi(from.y, rect.position.y, rect.end.y - 1)
	return maxi(absi(from.x - cx), absi(from.y - cy))


## MELEE IS RANGE 0 IN THE DATA AND REACH 1 ON THE MAP. units.json gives the
## knight `range: 0`, meaning "no reach at all, must be touching" -- but nothing
## can ever share a tile with its target, so a literal 0 would be unsatisfiable
## and every melee unit would walk up and stand there forever. The floor of 1 is
## what turns the data's "no range" into the map's "adjacent".
static func _within_reach(u: SimUnit, target: SimEntity, attack_range: int) -> bool:
	return tile_gap(u.tile(), _rect_of(target)) <= maxi(1, attack_range)


## How far `u` can actually reach, which is its def's range plus whatever its owner has
## researched (PLAN.md 9.3 -- Ballistics is `attack_range.pierce`).
##
## PUBLIC AND CALLED RATHER THAN INLINED, because `SiegeSystem` asks the same question
## when it decides an engine is close enough to set up. Two places reading `attack_range`
## and only one of them adding the tech is a siege engine that deploys a tile short of
## where it can shoot from -- the class of bug `Diplomacy`'s header is a standing warning
## about, arriving through a number instead of a predicate.
static func reach_of(w: SimWorld, u: SimUnit, def: UnitDef) -> int:
	if def == null:
		return 0
	return def.attack_range + TechMods.for_unit(w.mods_of(u.owner_id), def,
			&"attack_range")


static func _rect_of(e: SimEntity) -> Rect2i:
	if e is SimBuilding:
		return (e as SimBuilding).footprint_rect()
	return Rect2i(e.tile(), Vector2i.ONE)


## Damage after the target's armour of the MATCHING type, never below MIN_DAMAGE.
##
## Buildings take the attack whole: buildings.json declares no armour, so there
## is nothing to subtract, and inventing a default here would be a balance number
## hidden in a system rather than a value in the data where it can be tuned. Add
## `armor` to BuildingDef the day buildings should resist arrows.
## THE ATTACKER'S OWN UPGRADES ARE ADDED HERE (9.3), before armour, so a Blast Furnace
## swing is blunted by the defender's Plate Mail exactly as the base swing is -- which
## is what makes the two ladders trade against each other rather than one always winning.
##
## Units only. A tower's shot goes through `_damage_after_armour` below and picks up no
## smithing bonus, which is AoE's rule and also the honest one here: the blacksmith
## upgrades are about blades and bows, and `SimBuilding.attack_damage` is copied off the
## def at spawn, so a building bonus would have wanted a retroactivity pass this
## deliberately does not have.
static func _damage_against(w: SimWorld, attacker: SimUnit, target: SimEntity,
		def: UnitDef) -> int:
	var damage := def.attack_damage + TechMods.for_unit(
			w.mods_of(attacker.owner_id), def, &"attack_damage")
	return _damage_after_armour(w, target, damage, def.attack_type)


## The same rule with the attacker's def unpacked into two plain values, so a
## BUILDING's shot can go through it too (4.9).
##
## Split out rather than overloading `_damage_against`, which took a `UnitDef` and
## could not have taken a `BuildingDef` without either a union type GDScript does not
## have or a duplicate of the armour lookup. A duplicate is what the `Diplomacy`
## header is a standing warning about: the same predicate written twice diverges the
## first time either is corrected. One rule, two callers, and the garrison bonus is
## added by the caller before it gets here -- armour applies to the total, so a
## castle's 42 is blunted once rather than once per archer inside it.
##
## THE DEFENDER'S ARMOUR UPGRADES ARE ADDED HERE (9.3), which puts them on every blow
## in the game from one place: a unit's swing, a tower's volley and a dragon's breath
## all come through this one function, and Scale Mail has to blunt all three. It is
## also why the armour half went here rather than beside the attack half above --
## `AbilitySystem` calls this and does not call that.
##
## Armour applies to UNITS and workers are not excluded from it, unlike the attack
## bonus: `TechMods.for_all` is the "everyone your player owns" scope, and Padded
## Armour protecting the villagers is both what a player expects and what stops a
## smithing race making raids on an economy strictly better over time.
static func _damage_after_armour(w: SimWorld, target: SimEntity, damage: int,
		attack_type: StringName) -> int:
	var armour := 0
	if target is SimUnit:
		var td := w.unit_def((target as SimUnit).def_id)
		if td != null:
			armour = td.armor_pierce if attack_type == &"pierce" else td.armor_melee
			armour += TechMods.for_all(w.mods_of(target.owner_id),
					&"armor_pierce" if attack_type == &"pierce" else &"armor_melee")
	return maxi(MIN_DAMAGE, damage - armour)
