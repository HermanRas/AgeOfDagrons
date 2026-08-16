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
## - **No auto-acquire and no retaliation.** A unit fights what it was ORDERED to
##   fight and nothing else; being shot at does not make it turn around. That is
##   stances (4.12), and guessing at it here would mean every villager in the
##   game charging the first enemy that walked past, since a villager carries
##   damage 3.
## - **No projectiles.** A ranged hit lands the instant it is fired. An arrow with
##   travel time is a real thing to want, but it needs its own entity in the sim
##   and a view that draws it; nothing about the damage model below changes when
##   it arrives.
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


func process_tick(w: SimWorld) -> void:
	for entry in w.entities.values():
		if entry is SimUnit and entry.alive and entry.task == SimUnit.Task.ATTACK:
			_process(w, entry)


func _process(w: SimWorld, u: SimUnit) -> void:
	# Counts down whatever else happens this tick, including while walking, so a
	# unit that closes the distance arrives ready to swing rather than paying its
	# cooldown twice over.
	if u.attack_cooldown > 0:
		u.attack_cooldown -= 1

	var target := w.get_entity(u.task_target_id)
	if target == null or not target.alive:
		# The order is over, not transferred to whatever is standing nearby --
		# picking a new target is 4.12's job, not this one's.
		u.stop()
		return

	var def := w.unit_def(u.def_id)
	if def == null or def.attack_damage <= 0:
		u.stop()
		return

	if not _within_reach(u, target, def.attack_range):
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
	target.take_damage(_damage_against(w, target, def), 0)
	u.attack_cooldown = maxi(1, def.attack_cooldown_ticks)
	# Retire on the killing blow rather than noticing next tick. A tick of
	# swinging at something already dead is a tick of the attack animation
	# playing over a corpse, and AnimationSystem runs later in this same tick --
	# so the difference is visible, not merely tidy.
	if not target.alive:
		u.stop()


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
func _close_in(w: SimWorld, u: SimUnit, target: SimEntity) -> void:
	if u.path_pending or u.has_waypoint():
		return          # already on the way
	if w.paths == null:
		u.stop()
		return
	u.set_task_attack(u.task_target_id, target.tile())
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
static func _damage_against(w: SimWorld, target: SimEntity, def: UnitDef) -> int:
	var armour := 0
	if target is SimUnit:
		var td := w.unit_def((target as SimUnit).def_id)
		if td != null:
			armour = td.armor_pierce if def.attack_type == &"pierce" else td.armor_melee
	return maxi(MIN_DAMAGE, def.attack_damage - armour)
