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
## ✅ **ALL FOUR MODES ARE BUILT** — `_trophy()` landed 2026-09-07 and `_king_of_the_hill()` on
## 2026-09-09, which was the last placeholder in this file. `MatchConfig.Mode` declares all four
## because the lobby (1.6/11.3) needs a list and because a mode axis with one value on it invites
## the next mode to be bolted on as a boolean.
##
## 📝 **THE "SAFE DIRECTION TO BE UNFINISHED IN" ARGUMENT DID NOT LEAVE WITH THE PLACEHOLDER**, it
## moved into the guards. `Mode.REGICIDE` is not declared at all yet (card 11.2), and when it is,
## this is the paragraph that applies to it.
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
##
## **NO LONGER PLACEHOLDERS** — `_king_of_the_hill()` reads the first and
## `MapGen._place_koth_zone()` reads the second. Here rather than in `MatchConfig` because they are
## rules, not per-match settings; the zone's PLACE on the map is the part that became map data
## (`SimWorld.koth_zone`), which is what this note used to be waiting for.
##
## ⚠️ **`KOTH_TARGET_SCORE` IS A DURATION IN DISGUISE AND IS WORTH READING AS ONE.** A point a tick
## at `SimClock`'s 10 Hz makes 1000 **a hundred seconds of uncontested control** — not a hundred
## seconds of match. Contested ticks pay nobody, so a hill that changes hands takes far longer, and
## that is the number to move if the mode plays too fast rather than the radius.
##
## ⚠️ **AND `KOTH_ZONE_RADIUS_TILES` IS A HALF-EXTENT, NOT A RADIUS, DESPITE THE NAME.** The zone is
## a `Rect2i` because its other source is an authored rectangle, so the generated hill is a square
## `2r+1` on a side. `MapGen._place_koth_zone()` carries the argument for one shape; the name is
## kept because it is what 11.2 declared and renaming it would lose the thread.
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
		# THROUGH `_side_of()` SINCE 11.x-koth, which is where this keying now lives. It was two
		# lines here and KotH needed the same answer in three more places; a second copy would be
		# free to drift about whether team 0 is a team everybody shares.
		var key := _side_of(w, pid)
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


## KING OF THE HILL (11.x-koth, built 2026-09-09): hold the zone, score every tick you lead it,
## and the first side to `KOTH_TARGET_SCORE` wins.
##
## All three things this function waited for exist. Its own list, and what answered it:
##
##   1. *"WHERE THE ZONE IS"* -- `SimWorld.koth_zone`, resolved once by `MapGen._place_koth_zone()`
##      from an authored `MapData.KOTH_AREA` region or, failing that, a square at the map's centre.
##      The owner's *"both"* ruling; that function carries the argument for two sources.
##   2. *"a per-player score"* -- `SimPlayer.score`, in `state_hash()` and on `player_state`. It
##      landed **with this rule**, which is what its own warning asked for: *"one field nothing
##      writes is how it starts."*
##   3. *"the minimap ring"* -- `Minimap.set_koth_zone()`, fed from the snapshot's `koth_zone` and
##      `koth_holder`. *"A scored zone the player cannot see is a rule they can only lose to."*
##
## ## THE SCORING RULE, WHICH WAS ALREADY DECIDED AND IS NOT RE-LITIGATED
##
## **MOST units in the zone scores, not merely presence** -- so a contested hill pays nobody and
## one unit is enough to hold an empty one. A tie pays nobody, which is what makes `koth_holder`
## drop to 0 in a real fight rather than alternating between two players.
##
## ## ⚠️ IT COUNTS SIDES, NOT PLAYERS, FOR `_last_man_standing`'s REASON
##
## Two allies each holding four units in the zone against one enemy's six hold it **between them**,
## and a rule that compared players would hand the tick to the enemy. So units are tallied by side
## -- team, or the negative of the player id for the unaligned, which is `_decide_by_sides`' own
## keying and cannot collide -- and every standing member of the leading side scores. That also
## means a 2v2's allies carry identical numbers, which is correct and is what lets `winner_id`
## name a player the way every other mode does.
##
## ## ⚠️ GARRISONED UNITS DO NOT HOLD GROUND
##
## `SimUnit.garrisoned_in` takes a unit off the map without despawning it -- it leaves `SpatialHash`
## and is skipped by `SnapshotSystem` entirely -- and its `pos` is deliberately stale, frozen
## wherever it stood when it entered. So a tower inside the zone stuffed with archers would
## otherwise hold the hill with five men nobody can see, target or shoot, which is the opposite of
## a contested zone. Buildings do not count either: this is a rule about who is STANDING there.
##
## ## AND CONQUEST STILL ENDS IT
##
## `_decide_by_sides` runs on the survivors as well, so wiping out the opposition wins a KotH match
## without waiting out the tally. That is not a fallback, it is both rules at once: `_trophy` does
## the same, and without it two players who annihilated each other would leave a match nobody can
## score and nobody can end.
func _king_of_the_hill(w: SimWorld) -> void:
	# ⚠️ **UNARMED FALLS BACK TO CONQUEST, `_trophy`'s RULING AND ITS EXACT WORDS.** Deciding
	# nothing makes a hill-less KotH match **unendable**: nobody can score, the elimination rule is
	# skipped with it, and two players can wipe each other out and stand in an empty world forever.
	# A hang is not the safe direction, it is a slower way of being broken -- and
	# `_place_koth_zone`'s own warning already promises out loud that the match is decided by
	# conquest, so the code saying otherwise would be the defect.
	if w.koth_zone.size.x <= 0 or w.koth_zone.size.y <= 0:
		_last_man_standing(w)
		return
	if w.players.size() < 2:
		return
	# A world with nothing in it is not a match nobody has won -- it is a match that has not been
	# stood up. Shared with conquest, trophy and `ObjectiveSystem` so the four cannot disagree
	# about it on the tick that matters.
	if not _world_is_populated(w):
		return

	var standing := _eliminate_the_bankrupt(w)

	# ONE PASS OVER THE ENTITY LIST FOR EVERY SIDE, not a `_units_in_zone(pid)` per player -- the
	# same O(players x entities) cost `_owners_with_anything` and `PopulationSystem.census` were
	# both rewritten to undo, and this one runs every tick of every KotH match.
	var by_side := _zone_strength(w)
	var leader := _leading_side(by_side)

	# WHO HOLDS IT, PUBLISHED BEFORE THE SCORING so the mirror is right even on a tick nobody
	# scores. 0 for an empty or contested zone -- see `SimWorld.koth_holder`.
	w.koth_holder = 0
	for pid in standing:
		if _side_of(w, pid) == leader and (w.koth_holder == 0 or pid < w.koth_holder):
			w.koth_holder = pid

	# ⚠️ **SCORED OFF `standing` AND NOT OFF THE ZONE TALLY.** A player eliminated this tick can
	# still have units standing on the hill -- their corpses are in `entities` for ten seconds and
	# `_zone_strength` counts only the living, but a player whose last BUILDING fell is bankrupt
	# with an army intact. Paying them would tick a defeated player towards a win.
	if leader != 0:
		for pid in standing:
			if _side_of(w, pid) != leader:
				continue
			var p := w.player_for(pid)
			if p != null:
				p.score += 1

	# THE TALLY DECIDES IT FIRST, and only then conquest. Both can be true on one tick -- a last
	# surviving side that also just reached the target -- and the score is the mode's own answer,
	# so it is the one that should be recorded.
	for pid in standing:
		var p := w.player_for(pid)
		if p != null and p.score >= KOTH_TARGET_SCORE:
			w.match_over = true
			# THE LOWEST-ID SURVIVOR OF THE WINNING SIDE, `_decide_by_sides`' own convention: a
			# real player rather than a sentinel, deterministic, and what two screens already read.
			w.winner_id = w.koth_holder if w.koth_holder > 0 else pid
			var winner := w.player_for(w.winner_id)
			w.winner_team = winner.team if winner != null and winner.team > 0 else 0
			return

	_decide_by_sides(w, standing)


## Living, ungarrisoned units in the zone, tallied by side. Side key -> count.
##
## See `_king_of_the_hill()` for why garrisoned units and buildings are both excluded, and why the
## key is the side rather than the player.
func _zone_strength(w: SimWorld) -> Dictionary:
	var by_side: Dictionary = {}
	for e in w.entities.values():
		if not e.alive or not (e is SimUnit):
			continue
		var u := e as SimUnit
		# GAIA'S WILDLIFE HOLDS NOTHING. A herd of deer standing on the hill would otherwise be a
		# side -- `_side_of` would key them at 0, which is not a player's side at all -- and a wolf
		# could deny the zone to everybody. Same clause `_trophy_holders` carries, for the same
		# reason: gaia is not in the match.
		if u.owner_id <= 0 or u.garrisoned_in != 0:
			continue
		if not w.koth_zone.has_point(u.tile()):
			continue
		var key := _side_of(w, u.owner_id)
		by_side[key] = int(by_side.get(key, 0)) + 1
	return by_side


## The side with strictly the most units, or 0 for an empty or tied zone.
##
## **STRICTLY, WHICH IS THE WHOLE RULE.** A draw pays nobody: two sides with four units each are
## contesting the hill, not sharing it, and paying both would make a stalemate the fastest way to
## the target. 0 is safe as "nobody" because `_side_of` never returns it — a team is positive and
## an unaligned player is the negative of an id that starts at 1.
func _leading_side(by_side: Dictionary) -> int:
	var best := 0
	var best_count := 0
	var tied := false
	for key in by_side:
		var n := int(by_side[key])
		if n > best_count:
			best_count = n
			best = int(key)
			tied = false
		elif n == best_count:
			tied = true
	return 0 if tied or best_count <= 0 else best


## Which side a player is on: their team, or the negative of their id when they have none.
##
## `_decide_by_sides`' keying, pulled out because three places in this file now need it and a
## second copy would be free to drift about whether team 0 is a team everybody shares. It is not —
## 0 is the ABSENCE of a team, which is why an unaligned player is keyed by `-id` and two of them
## stay two sides.
func _side_of(w: SimWorld, player_id: int) -> int:
	var p := w.player_for(player_id)
	return p.team if p != null and p.team > 0 else -player_id
