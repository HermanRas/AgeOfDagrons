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
##
## TEAMS (2026-08-31) ARE THE SECOND THING THAT MAKES A NON-ENEMY, and every predicate
## here takes the team table as an argument rather than reading one from anywhere. It
## is a REQUIRED argument, with no default, and that is the whole safety property:
## §6's standing lesson is that a rule which can be left out is a rule that is off
## somewhere nobody looks, and GDScript reports a missing argument at parse time. An
## FFA caller passes `{}` and says so.
class_name Diplomacy
extends RefCounted


## Whether two player ids are on the same side. `teams` is `player_id -> team number`,
## which is `SimWorld.teams` in the sim and `GameView.teams()` on a client.
##
## THREE RULES AND ALL THREE ARE LOAD-BEARING:
##
##   - A player is always allied with themselves, which is the clause every caller used
##     to write as `owner_id == player_id`.
##   - **Team 0 IS NOT A TEAM.** It is the absence of one, and it is what every player
##     in a free-for-all carries -- so two teamless players are enemies, which is what
##     keeps every match played before this existed playing exactly as it did. An
##     unlisted player reads as 0 for the same reason.
##   - **Gaia allies with nobody.** Owner 0 is not a player, has no row in `teams`, and
##     a wolf on "team 0" alongside every FFA player would make the whole roster its
##     friends. Guarded explicitly rather than left to fall out of the rule above.
static func allied(a: int, b: int, teams: Dictionary) -> bool:
	if a == b:
		return true
	if a <= 0 or b <= 0:
		return false
	var team := int(teams.get(a, 0))
	return team > 0 and team == int(teams.get(b, 0))


## True when `player_id` is allowed to attack `e`, and when `e` is worth attacking.
##
## TOTAL ON PURPOSE -- null, dead, a resource node, a projectile and an arrow all get a
## plain false rather than a crash or a caller-side type test. Every call site used to
## carry its own `is SimUnit or is SimBuilding` line beside its own owner line; both
## belong to the same question and both live here now.
static func is_enemy(e: SimEntity, player_id: int, teams: Dictionary) -> bool:
	if e == null or not e.alive:
		return false
	if not (e is SimUnit or e is SimBuilding):
		return false
	# YOUR OWN AND YOUR ALLY'S, in one question. `allied` folds in the `owner_id ==
	# player_id` clause this line used to be, so a teammate's tower is exactly as
	# unattackable as your own.
	if allied(player_id, e.owner_id, teams):
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
##
## THE CLIENT'S TEAM TABLE COMES OFF THE WIRE, from `player_state.team` by way of
## `GameView.teams()` -- so the tap and the sim are reading the same numbers, which is
## the only thing that keeps the tap from offering an attack `AttackCommand` then
## refuses.
static func is_enemy_fact(f: Dictionary, player_id: int, teams: Dictionary) -> bool:
	if f.is_empty() or not bool(f.get("alive", true)):
		return false
	var owner := int(f.get("owner_id", 0))
	if allied(player_id, owner, teams):
		return false
	if owner != 0:
		return true
	return bool(f.get("is_unit", false))
