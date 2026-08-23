## Who may attack whom (PLAN.md 4.13). Pure predicate, no state, no world.
##
## THIS EXISTS BECAUSE THE ANSWER WAS WRITTEN OUT FOUR TIMES. `CombatSystem._reacquire`,
## `AISystem._nearest_enemy`, `AttackCommand.validate` and `GameView.tap_action` each
## carried their own copy of `owner_id != 0 and owner_id != mine`, and the hostile wolf
## needed exactly one of those clauses to stop being true -- which is the moment four
## copies becomes a bug waiting to be found in whichever one nobody remembered.
##
## GAIA IS NOT ONE THING, and that is the whole content of this file. Owner 0 owns the
## trees, the berry bushes, the sheep, the gold seams AND the wolf, and the wolf is the
## only one of them anybody may shoot. "Owner 0 is neutral" was a fair reading of the
## world right up until something neutral bit somebody.
##
## So the rule is by TYPE within gaia rather than by owner alone: a gaia UNIT is
## wildlife and is fair game; a gaia resource node is scenery and is not. That keeps a
## swordsman from being ordered to attack an oak -- which the old owner-0 clause was
## really guarding against, and which is still guarded, just for a stateable reason.
##
## Wildlife does not fight wildlife: a wolf asking about another wolf gets `owner_id ==
## player_id` and the answer is no. A pack does not turn on itself, and nothing has to
## say so specially.
class_name Diplomacy
extends RefCounted


## True when `player_id` is allowed to attack `e`, and when `e` is worth attacking.
##
## TOTAL ON PURPOSE -- null, dead, a resource node, a projectile and an arrow all get a
## plain false rather than a crash or a caller-side type test. Every call site used to
## carry its own `is SimUnit or is SimBuilding` line beside its own owner line; both
## belong to the same question and both live here now.
static func is_enemy(e: SimEntity, player_id: int) -> bool:
	if e == null or not e.alive:
		return false
	if not (e is SimUnit or e is SimBuilding):
		return false
	if e.owner_id == player_id:
		return false
	if e.owner_id != 0:
		return true
	# Gaia. Only its units are hostile -- see the header.
	return e is SimUnit


## The same question asked of a `GameView._facts` entry rather than a `SimEntity`, for
## the client, which has no entities to ask (PLAN.md 4).
##
## KEPT IN STEP BY LIVING HERE. The view's copy of this rule and the sim's used to be
## two unrelated lines in two layers, and the failure mode when they drift is the worst
## kind: the tap offers an attack the sim then refuses, so the player taps an enemy and
## the game does nothing at all with no explanation.
##
## `owner_id`, `is_unit` and `alive` are all the facts a snapshot carries about this,
## and they are exactly the three the sim form reads.
static func is_enemy_fact(f: Dictionary, player_id: int) -> bool:
	if f.is_empty() or not bool(f.get("alive", true)):
		return false
	var owner := int(f.get("owner_id", 0))
	if owner == player_id:
		return false
	if owner != 0:
		return true
	return bool(f.get("is_unit", false))
