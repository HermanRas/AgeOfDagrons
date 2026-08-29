## Special abilities and their cooldowns (PLAN.md 4.10, IDEA.md 4.10).
##
## Two units in the roster carry one and they are the two shapes the system supports:
## the MONK heals a friendly unit, and the DRAGON breathes fire over an area of ground.
## Everything that differs between them is in `data/units.json`; `AbilitySystem` reads
## `UnitDef.ability_effect` and `ability_target` and knows nothing about monks or dragons.
##
## THE SAME ORDER-THEN-ARRIVE SPLIT `BuildCommand`/`BuildSystem` USES. `AbilityCommand`
## puts the unit on `Task.ABILITY` and the unit walks; this system fires it once the unit
## is within `ability_range`. A monk told to heal somebody across the square walks over,
## which is what every other verb in the game does and what the player will expect.
##
## `ability_target_tile` IS THE AIM AND `task_target_tile` IS NOT. `SimUnit.set_path`
## rewrites the latter to wherever the route could actually end (4.1), so a dragon that
## stopped a tile short of an unreachable aim point would breathe fire on its own feet.
## The two are separate fields on `SimUnit` for exactly this, and the header there says so.
##
## WHAT IT DELIBERATELY DOES NOT DO:
##
## - **No resource cost.** IDEA.md 4.10 allows for one ("unable to perform ... due to
##   cooldown or lack of resources") and no ability in the roster has one, so nothing
##   here spends anything. The place it would go is `AbilityCommand.validate`, beside the
##   cooldown check, which is where `TrainCommand` pays for a unit.
## - **No auto-use.** Nothing casts an ability unasked, including the AI. That is the
##   same rule 4.13 sets for combat and 4.12 only relaxed for an IDLE unit picking a
##   fight; a dragon that breathed fire on its own judgement would be spending a
##   15-second cooldown the player was saving.
## - **No friendly fire.** The blast tests every entity in its radius against the
##   caster's own war predicate, so a dragon cannot burn its own army. That is a design
##   choice rather than a physical law and it is worth naming, because it is the reason
##   a breath weapon needs no aiming skill.
class_name AbilitySystem
extends SimSystem


func process_tick(w: SimWorld) -> void:
	for entry in w.entities.values():
		if not (entry is SimUnit):
			continue
		var u := entry as SimUnit
		if not u.alive:
			continue
		# Counts down whatever else the unit is doing, including while it walks, so
		# closing the distance is not paid on top of the cooldown -- the same call
		# `CombatSystem._process` makes for `attack_cooldown` and for the same reason.
		if u.ability_cooldown > 0:
			u.ability_cooldown -= 1
		if u.task == SimUnit.Task.ABILITY:
			_process(w, u)


func _process(w: SimWorld, u: SimUnit) -> void:
	var def := w.unit_def(u.def_id)
	if def == null or not def.has_ability():
		u.stop()
		return

	# A TARGETED ABILITY FOLLOWS ITS TARGET; a ground one aims at a tile that cannot
	# move. Re-read the entity every tick rather than trusting the tile the order was
	# issued against, so a monk sent after a wounded soldier who is still walking
	# arrives where the soldier IS.
	var aim := u.ability_target_tile
	var target: SimEntity = null
	if def.ability_target == &"friendly":
		target = w.get_entity(u.task_target_id)
		if target == null or not target.alive or not _may_help(u, target):
			u.stop()
			return
		if _is_finished_with(def, target):
			u.stop()
			return
		aim = target.tile()
		u.ability_target_tile = aim

	if CombatSystem.tile_gap(u.tile(), _rect_of_aim(target, aim)) > maxi(1, def.ability_range):
		_close_in(w, u, aim)
		return

	# In range: stop walking but stay on the order, exactly as an attacker does, and
	# turn to face what is being worked on. A monk healing over its own shoulder reads
	# as a bug even when the hp is right -- `CombatSystem._process`'s own note.
	if u.has_waypoint() or u.path_pending:
		if w.paths != null:
			w.paths.cancel(u.id)
		u.halt()
	if aim != u.tile():
		u.facing = SimUnit.facing_toward(SimUnit.centre_of_tile(aim) - u.pos)

	if u.ability_cooldown > 0:
		return
	_fire(w, u, def, target, aim)
	u.ability_cooldown = maxi(1, def.ability_cooldown_ticks)

	# A GROUND ABILITY IS ONE SHOT AND A TARGETED ONE REPEATS, and the difference is not
	# a flag -- it is that a ground ability has nothing left to re-evaluate. A tile does
	# not get healthier, so "am I done" is unanswerable and firing again would be a
	# dragon strafing a patch of grass forever. A targeted heal has a completion
	# condition (`_is_finished_with`) and keeps working until it is met, which is what
	# makes the monk one press rather than one press per six hp.
	if def.ability_target != &"friendly":
		u.stop()


## Apply the ability. Two effects, and `ability_effect` is the only field consulted --
## adding a third is an arm here and a JSON entry, not a new system.
func _fire(w: SimWorld, u: SimUnit, def: UnitDef, target: SimEntity, aim: Vector2i) -> void:
	match def.ability_effect:
		&"heal":
			if target != null:
				target.hp = mini(target.max_hp, target.hp + _amount(w, u, def))
		&"damage":
			_burn(w, u, def, aim)


## What this ability is worth, after its owner's technologies (PLAN.md 9.3 -- Sanctity
## and Fervour are `ability_amount.heal`).
##
## SCOPED BY THE ABILITY'S OWN `ability_effect`, not by the unit. A monastery tech that
## said `ability_amount.all` would also make the dragon's fire breath hotter, which is
## not what "Sanctity" means and not what the player paid for -- and the effect name is
## already the right axis, because it is what tells a heal from a blast everywhere else
## in this file.
static func _amount(w: SimWorld, u: SimUnit, def: UnitDef) -> int:
	return def.ability_amount + TechMods.of(w.mods_of(u.owner_id), &"ability_amount",
			def.ability_effect)


## Everything hostile within `ability_radius` of `aim` takes `ability_amount`, blunted by
## its own armour of the matching type.
##
## `CombatSystem._damage_after_armour` is CALLED rather than reimplemented -- a second
## copy of the armour rule is the duplication `Diplomacy`'s header is a standing warning
## about, and it is also what keeps `MIN_DAMAGE`'s floor true of every hit in the game.
##
## Radius 0 is a single tile and is a legitimate value, not a disabled ability: the rect
## below is 1x1 and the blast lands on exactly what is standing there.
func _burn(w: SimWorld, u: SimUnit, def: UnitDef, aim: Vector2i) -> void:
	var r := def.ability_radius
	var span := r * 2 + 1
	var rect := Rect2i(aim - Vector2i(r, r), Vector2i(span, span))
	# COLLECTED BEFORE ANYTHING IS DAMAGED, and sorted by id. `entities_in_rect` returns
	# an unsorted view of a structure the damage may change -- a kill despawns and would
	# be a mutation during iteration -- and two hosts applying the same blast in a
	# different order would run different armour lookups against the same total. Neither
	# is hypothetical: it is `CombatSystem._reacquire`'s determinism rule applied to a
	# hit that lands on many things at once.
	var ids: Array[int] = []
	for e in w.entities_in_rect(rect):
		if _is_hostile_to(w, e, u.owner_id):
			ids.append(int(e.id))
	ids.sort()
	for id in ids:
		var e := w.get_entity(id)
		if e == null or not e.alive:
			continue
		e.take_damage(CombatSystem._damage_after_armour(w, e, _amount(w, u, def),
				def.ability_damage_type), 0)


## Whether `e` may be caught in `owner_id`'s blast.
##
## The unit half is `CombatSystem._is_at_war_with` -- called, not copied, so a dragon can
## no more burn a flock of sheep than a watch tower can shoot one (4.9's bug).
##
## THE BUILDING HALF DELIBERATELY DIFFERS FROM `StanceSystem._may_start_on`, which
## excludes foundations. That exclusion is about a tower or an aggressive soldier
## STARTING something nobody asked for: a border war declared by a house going up next
## door. This is a weapon a player aimed at a tile, and refusing to burn the foundation
## squarely inside the blast would be the game overruling a deliberate order. Two rules
## because the two questions differ, and each says so.
static func _is_hostile_to(w: SimWorld, e: SimEntity, owner_id: int) -> bool:
	if e is SimUnit:
		return CombatSystem._is_at_war_with(w, e as SimUnit, owner_id)
	if e is SimBuilding:
		return e.alive and e.owner_id != 0 and e.owner_id != owner_id
	return false


## Whether `u` may use a `friendly` ability on `target`: one of its owner's own living
## units. Not buildings -- a monk mending a wall is repair (5.3), a different verb with a
## different cost -- and not an ally's, since the game has no alliances to be one of.
static func _may_help(u: SimUnit, target: SimEntity) -> bool:
	return target is SimUnit and target.owner_id == u.owner_id


## Whether a targeted ability has nothing left to do. Only `heal` has such a condition
## today; anything else keeps going until the player orders otherwise, which is the
## honest default for an effect whose completion this system cannot see.
static func _is_finished_with(def: UnitDef, target: SimEntity) -> bool:
	if def.ability_effect == &"heal":
		return target.hp >= target.max_hp
	return false


## What the range is measured to: the target's own footprint when there is one, or the
## aim tile. Same shape as `CombatSystem._within_reach`, so "in range" means the same
## thing for a heal as it does for a sword.
static func _rect_of_aim(target: SimEntity, aim: Vector2i) -> Rect2i:
	if target != null:
		return CombatSystem._rect_of(target)
	return Rect2i(aim, Vector2i.ONE)


## Walk toward the aim point, re-planning only when the current route RUNS OUT -- the
## budget argument in `CombatSystem._close_in`'s header applies here unchanged, and a
## monk chasing a retreating soldier is exactly the case it describes.
func _close_in(w: SimWorld, u: SimUnit, aim: Vector2i) -> void:
	if u.path_pending or u.has_waypoint():
		return          # already on the way
	if w.paths == null:
		u.stop()
		return
	u.set_task_ability(u.task_target_id, aim)
	w.paths.request(u.id, aim)
