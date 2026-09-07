## Decides when a match is over and who won (PLAN.md 11.1). Writes exactly four
## things and nothing else: `SimPlayer.defeated`, `SimWorld.match_over`,
## `SimWorld.winner_id` and `SimWorld.winner_team`. All of them ride the snapshot, so
## the result screen is a
## reader of sim state rather than a client-side guess -- the same division
## `ResourceHUD` keeps for the population.
##
## Runs LAST, after `PopulationSystem`, which is itself after `DeathSystem`. The
## whole tick has to have happened first: elimination is read off what is still
## alive, and a player whose last building fell THIS tick has lost as of this tick,
## not the next one. PLAN.md 5.1's tick diagram puts it in the same place.
##
## THREE OF THE FOUR MODES ARE BUILT (`_trophy()` landed 2026-09-07). `MatchConfig.Mode`
## declares all four because the lobby (1.6/11.3) needs a list and because a mode axis with
## one value on it invites the next mode to be bolted on as a boolean.
## `_king_of_the_hill()` still ends no matches at all and says what it is missing -- the
## safe direction to be unfinished in.
##
## ⚠️ **THE UNSAFE DIRECTION IS A HALF-BUILT RULE, AND TROPHY DID NOT STOP BEING EXPOSED TO
## IT BY BEING FINISHED.** This paragraph's own example was *"'you lose when your trophy is
## gone' evaluated on a map with no trophies on it defeats everybody on tick 1"*, and that
## is still precisely what would happen in a match where placement failed. What makes the
## mode safe is not that it is built -- it is `SimWorld.trophy_def_id`, which
## `MapGen._place_trophies` sets only once **every** player has one, and which `_trophy()`
## refuses to run without. The rule is finished; the guard is why it can be.
##
## SCENARIO (15.2) is the fourth, and it is the only mode whose WIN lives somewhere else:
## `ObjectiveSystem`, which runs directly before this one. What is here is the half of
## conquest a scenario keeps -- see `_scenario()`.
##
## Once `match_over` is set nothing here runs again, so a result cannot be
## overwritten by the corpses and rubble settling in the seconds after it.
class_name WinConditionSystem
extends SimSystem

## King of the Hill: the score to reach, and how big the contested zone is.
## PLACEHOLDER -- see `_king_of_the_hill()`. Here rather than in `MatchConfig`
## because they are rules, not per-match settings; the zone's PLACE on the map is
## the part that will have to become map data.
const KOTH_TARGET_SCORE := 1000
const KOTH_ZONE_RADIUS_TILES := 6

## ⚠️ **`TROPHY_DEF_ID` IS GONE, AND ITS ABSENCE IS THE FEATURE** (11.2, 2026-09-07). It
## was `&"unit.dragon"` -- *"the nearest thing that exists in units.json"* -- and PLAN.md
## 11.2 asked for exactly its removal: *"an `is_trophy` flag rather than a hardcoded id"*.
## The def now carries the flag, `GameDataRegistry.trophy_def_id()` answers which unit it
## is, and `SimWorld.trophy_def_id` records that a match actually placed them. So this
## system names no dragon at all, and regicide with one of §9.2's Celtic heroes is a line
## of JSON rather than a second win condition.


func process_tick(w: SimWorld) -> void:
	if w.match_over:
		return
	match w.mode:
		MatchConfig.Mode.LAST_MAN_STANDING:
			_last_man_standing(w)
		MatchConfig.Mode.TROPHY:
			_trophy(w)
		MatchConfig.Mode.KING_OF_THE_HILL:
			_king_of_the_hill(w)
		MatchConfig.Mode.SCENARIO:
			_scenario(w)


## Own nothing and you are out; the last player left wins (PLAN.md 11.1's
## conquest mode). The only mode that decides anything today, and the one the
## debug map is set up for: the skirmish opponent owns two soldiers, so killing
## both of them wins the match.
##
## A ONE-PLAYER WORLD IS NEVER DECIDED. "Last man standing" is trivially true of
## somebody with no opponents, and `MatchConfig.debug_single_player()` plus most of
## the test suite is exactly that -- declaring victory on tick 1 of a solo sandbox
## would be technically correct and useless. Two players is the floor for a match
## that can be won.
##
## ⚠️ **IT COUNTS SIDES, NOT PLAYERS, AND THAT IS NOT AN ENHANCEMENT** (2026-08-31). The
## moment allies stopped being able to attack each other, the old rule stopped being able
## to END A 2v2 AT ALL: two teammates both standing is `standing.size() == 2`, nothing
## remains that can reduce it to one, and the match runs forever with both survivors
## wandering an empty map. A team game needs this in the same commit as the team, or the
## feature is a hang.
func _last_man_standing(w: SimWorld) -> void:
	if w.players.size() < 2:
		return
	if not _world_is_populated(w):
		return

	_decide_by_sides(w, _eliminate_the_bankrupt(w))


## End the match if `standing` holds one side or none.
##
## SHARED BY CONQUEST AND BY TROPHY (11.2), which is why it is a function rather than two
## copies -- the same argument `_eliminate_the_bankrupt` makes one line below its own
## header. The two modes differ ONLY in who they eliminate; what "one side left has won"
## means is identical, and a second copy of it would be free to drift about draws, about
## which survivor `winner_id` names, or about whether a team number can be negative.
func _decide_by_sides(w: SimWorld, standing: Array[int]) -> void:
	# STANDING SIDES, which is what actually decides the match. A player on no team is
	# their own side -- keyed by the NEGATIVE of their id, so it can never collide with a
	# real team number and two unaligned players stay two sides. That is what makes this
	# identical to the old rule for every free-for-all: one side per standing player.
	var sides: Dictionary = {}          # side key -> lowest standing player id on it
	for pid in standing:
		var p := w.player_for(pid)
		var key: int = p.team if p != null and p.team > 0 else -pid
		if not sides.has(key) or pid < int(sides[key]):
			sides[key] = pid

	if sides.size() > 1:
		return

	w.match_over = true
	# 0 when the last two fell on the SAME tick: a draw. Barely reachable in play
	# (it needs simultaneous mutual annihilation) but reachable instantly in a test
	# that steps a world with no entities in it, and the alternative is a match
	# flagged as over with a winner nobody can name.
	#
	# WHICH TEAM WON IS THE ANSWER; `winner_id` IS STILL A PLAYER because it is on the
	# wire, in the hash, and read by two screens. It names the LOWEST-id survivor of the
	# winning side -- deterministic, and a real player rather than a sentinel -- and
	# `winner_team` beside it is what a teammate who was knocked out earlier reads to be
	# told they won. Same shape as `defeat_reason`: one more field on a block that is
	# already carried, rather than a second channel.
	var keys := sides.keys()
	w.winner_id = int(sides[keys[0]]) if sides.size() == 1 else 0
	w.winner_team = keys[0] if sides.size() == 1 and int(keys[0]) > 0 else 0


## SCENARIO MODE (PLAN.md 11.8, 15.2): **conquest's LOSS without conquest's WIN.**
##
## ⚠️ **HALF OF `_last_man_standing` IS WANTED HERE AND HALF IS NOT, AND THAT IS THE
## WHOLE POINT OF THE FORK.** Owning nothing is still defeat -- true on every map in this
## game whatever a file declares, which is why `ScenarioDef` has no lose-condition field
## at all. Outlasting the opponent is NOT victory: killing the Passive AI's five
## villagers and its town centre would otherwise win scenario 1 with two villagers and no
## house, and the scenario would teach the opposite of its name.
##
## PLAN.md 11.8 asks for it *"by calling the elimination half and skipping the sides
## half, not by copying the function"*, which is why `_eliminate_the_bankrupt` exists.
## Copying it would leave two rules that both eliminate players and could drift about
## what a foundation is worth.
##
## THE `< 2` PLAYER GUARD DOES NOT APPLY, and leaving it out is deliberate. It exists
## above because "last man standing" is TRIVIALLY TRUE of somebody with no opponents, so
## a solo sandbox would declare victory on tick 1. A scenario's loss is not a comparison
## between players: a lone player who loses everything has genuinely lost, and there is
## nothing trivial about it. `_world_is_populated` is still needed and still here.
##
## THE OPPONENT BEING WIPED OUT ENDS NOTHING, which is the case worth stating because it
## looks like a hang and is not: the bot is defeated, the human plays on, and the match
## ends when `ObjectiveSystem` says the objectives are met. A player who destroys the
## enemy and then never reaches ten villagers has not finished the lesson.
func _scenario(w: SimWorld) -> void:
	if not _world_is_populated(w):
		return
	_eliminate_the_bankrupt(w)

	# KEEPING THE LOSS MEANS ENDING THE MATCH ON IT. `ObjectiveSystem` runs directly
	# before this and returns early for a defeated player, so it cannot have declared a
	# win on this tick -- the two cannot both fire.
	var p := w.player_for(w.objective_player_id)
	if p == null or not p.defeated:
		return
	w.match_over = true
	# NOBODY WON: the teaching opponent has no win condition of its own, so naming it the
	# winner would print "Player 2 won" at somebody who lost a tutorial to a bot that
	# never attacked. `GameScene` tells this apart from the mutual-annihilation draw --
	# which carries the same 0 -- by the player's own `defeat_reason`.
	w.winner_id = 0
	w.winner_team = 0


## Defeat everybody who owns nothing, and return the ids still standing.
##
## SHARED BY CONQUEST AND BY SCENARIO MODE (11.8), which is the reason it is a function:
## owning nothing is defeat on every map in this game, and two copies of that rule could
## drift about what a foundation is worth or whether a corpse counts.
func _eliminate_the_bankrupt(w: SimWorld) -> Array[int]:
	# ONE pass for every player, not `_owns_anything()` per player. Per-player was
	# O(players x entities), which on an 8-player generated map is eight walks of a
	# thousand entities every tick -- part of the same measurement that caught
	# VisionSystem's full-grid decay.
	var owners := _owners_with_anything(w)
	var standing: Array[int] = []
	for p in w.players:
		# `not p.defeated` is what makes RESIGNING mean anything (12.1e). Owning something
		# used to be the whole test, so a player who conceded -- or whose device vanished,
		# which `Net` turns into the same command -- went on counting as standing while
		# their abandoned base sat there, and the match could never resolve. Safe to read
		# here precisely because the flag is one-way: it is set below and by
		# `ResignCommand`, and never cleared by anything.
		if owners.has(p.id) and not p.defeated:
			standing.append(p.id)
		else:
			# ONE WAY ONLY, never cleared. A player with no units and no buildings
			# cannot build, train or gather, so there is no path back -- and a flag
			# that could flicker off would take the defeat screen with it.
			#
			# THROUGH `defeat()` RATHER THAN THE FLAG, so the reason is recorded with it.
			# This runs for every player every tick, including one who has ALREADY
			# conceded -- `SimPlayer.defeat` keeps the first reason for exactly that, or
			# a resignation would be relabelled an elimination the moment the abandoned
			# base fell. It is also what keeps a scenario's OBJECTIVE_FAILED from being
			# rewritten to ELIMINATED a tick later.
			p.defeat(SimPlayer.Defeat.ELIMINATED)
	return standing


## Whether there is a match here to decide at all: does the world hold anybody's
## unit or building, ALIVE OR DEAD.
##
## `SimWorld.setup()` allocates an empty grid and `MapGen` fills it afterwards, so
## an empty world is one that has not been stood up yet -- which is also what every
## sim test and harness that skips MapGen is working with. Read literally, an empty
## world is every player eliminated on tick 1 and a match drawn before the first
## order, and `match_over` latching means that verdict would then stick for the rest
## of the run.
##
## DEAD COUNTS, and that is what keeps the guard from swallowing a real result. When
## the last two players annihilate each other, their corpses (4.7) and rubble (5.5)
## are still in `entities` for up to a minute -- so on the tick it happens this is
## still true, the draw below is recorded, and nothing after it is evaluated. The
## only way past this guard is entities leaving the world without dying first, which
## is `despawn()` called by hand.
static func _world_is_populated(w: SimWorld) -> bool:
	for e in w.entities.values():
		if e is SimUnit or e is SimBuilding:
			return true
	return false


## True while `player_id` still has a unit or a building.
##
## ALIVE, not merely present: a corpse (4.7) and rubble (5.5) stay in `entities`
## for up to a minute after they fall, and a player whose last building is
## smouldering has lost -- the same `alive` filter `PopulationSystem` counts by.
##
## A FOUNDATION COUNTS. It is a building the player owns, it holds ground, and any
## villager they have left can still raise it. `PopulationSystem` excludes
## foundations from the pop CAP, which is a different question -- what a building
## provides, versus whether the player is still in the game.
##
## Resource nodes are excluded by TYPE rather than by owner. They carry owner_id 0
## today, so an owner check would happen to work; keying off the type instead means
## a mode that ever gives nodes a real owner (a claimed dragon nest, 13.2) cannot
## accidentally keep a wiped-out player alive on the strength of a berry bush.
static func _owns_anything(w: SimWorld, player_id: int) -> bool:
	return _owners_with_anything(w).has(player_id)


## The set of owner ids with at least one living unit or building, in one pass. See
## `_owns_anything()` above for what counts and why.
static func _owners_with_anything(w: SimWorld) -> Dictionary:
	var owners: Dictionary = {}
	for e in w.entities.values():
		if not e.alive:
			continue
		if e is SimUnit or e is SimBuilding:
			owners[e.owner_id] = true
	return owners


## TROPHY (11.2, built 2026-09-07): every player starts with a dragon hatchling and is out
## the moment it dies. Conquest's rule with one more way to lose.
##
## All three things this function waited for exist. Its own list, and what answered it:
##
##   1. *"a `unit.dragon_baby` def"* -- landed with 13.2b, and 20% sprite scaling with it,
##      which PLAN.md 11.2 correctly identified as the last genuinely missing piece;
##   2. *"MapGen giving one to every player"* -- `MapGen._place_trophies`, which is a
##      post-build spawn pass beside `_place_ai_handicaps` and not, as 11.2 expected,
##      `MapGenerator` placement arithmetic. A trophy wants to be NEAR its owner's base,
##      which is the opposite problem from a nest wanting to be far from everybody's;
##   3. *"an `is_trophy` flag rather than a hardcoded id"* -- `UnitDef.is_trophy`. This
##      function names no dragon, and `TROPHY_DEF_ID` is deleted.
##
## ## ⚠️ INERT UNLESS EVERY PLAYER WAS ACTUALLY GIVEN ONE, WHICH IS THE OLD WARNING KEPT
##
## This header used to say: *"running those four lines today would defeat every player on
## tick 1, since nobody has a dragon to lose."* That is still exactly true of a match where
## the trophies did not get placed -- a roster with no `is_trophy` unit, or ground too tight
## to seat one -- so the guard is `w.trophy_def_id`, which `_place_trophies` writes **only
## after every player has one**. Reading the roster flag here instead would arm the rule on
## any map, and the failure would be total, instant and identical for everybody.
##
## ## LOSING YOUR TROPHY IS NOT ELIMINATION AND IS NOT SCORED AS IT
##
## `Defeat.TROPHY_LOST` on OBJECTIVE_FAILED's argument: a player whose hatchling dies may
## still own a town centre, an army and half the map, so ELIMINATED would be true about the
## outcome and false about how it happened -- the forfeit defect BUGS.md recorded.
##
## ## OWNING NOTHING IS STILL DEFEAT, AND BOTH RULES APPLY AT ONCE
##
## `_eliminate_the_bankrupt` runs first and unchanged, so a player wiped out entirely is
## ELIMINATED rather than credited with losing a trophy they no longer had. `defeat()`
## keeps the FIRST reason, so the ordering of these two is the whole of that distinction.
func _trophy(w: SimWorld) -> void:
	# ⚠️ **UNARMED FALLS BACK TO CONQUEST RATHER THAN DECIDING NOTHING**, and the
	# difference matters more than it looks. Deciding nothing was the first version and it
	# makes a misconfigured trophy match **unendable**: with no trophy to lose and the
	# elimination rule skipped along with it, two players can wipe each other out entirely
	# and go on standing in an empty world forever. That is a hang, and a hang is not the
	# safe direction -- it is just a slower way of being broken.
	#
	# Conquest is the honest fallback: it defeats nobody for a trophy they were never
	# given, it ends the match the ordinary way, and it is what
	# `MapGen._place_trophies`' own warning already promises out loud ("the trophy rule
	# stays inert and the match is decided by conquest"). The code saying something
	# different from the warning beside it was the actual defect.
	if w.trophy_def_id.is_empty():
		_last_man_standing(w)
		return
	if w.players.size() < 2:
		return
	# A world with nothing in it is not a match nobody has won -- it is a match that has
	# not been stood up. Shared with conquest and with `ObjectiveSystem` so the three
	# cannot disagree about it on the tick that matters.
	if not _world_is_populated(w):
		return

	var standing := _eliminate_the_bankrupt(w)

	# ONE PASS FOR EVERY TROPHY IN THE WORLD, not `_owns_none_of()` per player -- the same
	# O(players x entities) cost `_owners_with_anything` and `PopulationSystem.census`
	# were both rewritten to undo.
	var holders := _trophy_holders(w)
	var left: Array[int] = []
	for pid in standing:
		if holders.has(pid):
			left.append(pid)
			continue
		var p := w.player_for(pid)
		if p != null:
			p.defeat(SimPlayer.Defeat.TROPHY_LOST)

	_decide_by_sides(w, left)


## Owner ids with at least one living trophy, in one pass.
##
## ALIVE, like every other census in this file: a trophy's corpse lies there for
## `SimUnit.CORPSE_TOTAL_TICKS` and a player whose hatchling is cooling on the grass has
## lost. Counting the body would give them ten more seconds for no reason anybody could
## explain from the screen.
##
## ⚠️ **GAIA'S HATCHLINGS ARE EXCLUDED BY `owner_id > 0`, AND THIS IS THE SECOND HALF OF
## THE 13.2 COLLISION.** The claim hatchling at a dragon nest is the same def, owned by
## gaia -- so without this clause owner 0 would appear in `holders`, which is harmless
## today only because gaia is never in `standing`. It is written anyway, because the day
## something puts gaia in a side this would be a rule keeping the wildlife in the match.
## `NestSystem`'s matching `owner_id == 0` filter is the other half.
func _trophy_holders(w: SimWorld) -> Dictionary:
	var holders: Dictionary = {}
	for e in w.entities.values():
		if not e.alive or e.owner_id <= 0:
			continue
		if e is SimUnit and e.def_id == w.trophy_def_id:
			holders[e.owner_id] = true
	return holders


## PLACEHOLDER (11.2). A zone on the map, ringed on the minimap; whoever has the
## most units inside it scores each tick, and the first to KOTH_TARGET_SCORE wins.
##
## Deliberately decides nothing. What it needs, in the order it needs it:
##
##   1. WHERE THE ZONE IS. That is map data, not a rule -- it belongs beside the
##      start positions in `MapGen`/`SimMap`, and a hill hardcoded at the centre of
##      the debug map would be a promise this system cannot keep for any other map.
##      `KOTH_ZONE_RADIUS_TILES` is the shape; the centre is the missing half.
##   2. A per-player score on `SimPlayer`, in `state_hash()` and the snapshot. NOT
##      added yet, on purpose: an unwritten field that reaches the HUD is precisely
##      the hole 4.11's counter was, and one field nothing writes is how it starts.
##   3. The minimap ring (view side, `Minimap`). A scored zone the player cannot see
##      is a rule they can only lose to.
##
## The scoring rule itself is the easy part and is worth stating so it is not
## re-litigated: MOST units in the zone scores, not merely presence, so a contested
## hill pays nobody and one unit is enough to hold an empty one.
func _king_of_the_hill(_w: SimWorld) -> void:
	pass
