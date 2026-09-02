## Evaluates a scenario's authored win condition (PLAN.md 11.8, Phase 15.2).
##
## `ObjectiveDef` is the LANGUAGE and parses it; this is the only thing that reads it.
## The split is PLAN.md 4's invariant, which admits no exception for scripting: if the
## client decides it won, the client can decide it won. So the vocabulary lives in
## `src/data/` where the front door reads a file, and the verdict is reached here, in
## the sim, on the server.
##
## ## IT ONLY RUNS IN `SCENARIO` MODE
##
## `ScenarioDef` refuses both ways objectives and mode can contradict each other -- a
## `scenario` with no win row can never be won, a `last_man_standing` carrying
## objectives would have them silently ignored -- so a config where they disagree cannot
## come out of a scenario file. This system therefore does not need to guess: outside
## SCENARIO mode it does nothing at all, rather than being a second place that decides
## what a mode means.
##
## ## WHAT IT WRITES, WHICH IS THE SAME FOUR FIELDS EVERY OUTCOME USES
##
## `SimWorld.match_over`, `winner_id`, `winner_team` and `SimPlayer.defeat()` -- plus
## `SimPlayer.objective_progress`/`objective_done`, which are the tracker's channel
## (15.6). Nothing else, so `ResultScreen` needs no new reader: a scenario ends through
## exactly the fields a conquest match ends through.
##
## ## ⚠️ A WIN ROW LATCHES ONCE MET, AND WITHOUT THAT SCENARIO 2 IS UNWINNABLE
##
## Not a convenience. **Measured 2026-09-02, from the owner's own objectives for scenario
## 2: "gather 500 food" AND "advance to the Age of Embers".** Advancing to age 2 costs
## exactly 500 food (`ages.json`), and `AdvanceAgeCommand` deducts it when the advance
## STARTS. So the food row is true at the moment the player can afford the age, and false
## from the instant they buy it -- 100 ticks before the age they bought arrives. The two
## rows are ANDed and can never be true on the same tick. Evaluated live, that scenario
## would have shipped **unwinnable while looking completely correct**, which is precisely
## what the owner already caught in scenario 3's *"0 enemy units on map"*.
##
## So an objective list is a CHECKLIST and not a snapshot: a win row that has ever been
## satisfied stays satisfied, in `objective_done`, one-way, exactly as `SimPlayer.defeated`
## is one-way and for the same reason -- a tick that could flicker off would take the
## result with it. It is also what the player already believes is happening, because a
## ticked line on a goal list does not untick.
##
## LOSE ROWS DO NOT LATCH, and do not need to: a lose row ends the match on the tick it
## fires, so there is no later tick for a latch to matter on. ALERT rows latch so 15.6
## can fire a `NoticeToast` once rather than ten times a second.
##
## ## THE THREE TRAPS THAT ARE ACTUALLY DANGEROUS HERE
##
## **1. GAIA IS NOT AN ENEMY.** `{"subject": "unit", "owner": "enemy", "compare": "==",
## "value": 0}` is PLAN.md 11.8's own example of *leave the enemy nothing*. Owner 0 owns
## the trees, the sheep, the deer AND the wolves, so a rule that counted entities by
## "not mine" would make that objective mean **kill every animal on the map** -- an
## objective the author never wrote and the player cannot guess. The owner set is
## therefore resolved from `SimWorld.players` and never from the owner ids found on
## entities, so gaia is excluded by construction rather than by a clause somebody could
## delete. `Diplomacy`'s header is the longer version of this: *"gaia is not one thing"*.
##
## **2. AN UNPOPULATED WORLD MUST DECIDE NOTHING.** Same example, same rule: in a world
## with no entities in it, "the enemy has 0 units" is TRUE, so a naive evaluator declares
## victory on tick 1 of every world that has not been stood up yet -- which is most of
## the sim suite and any tool that inspects one. That is exactly the shape
## `WinConditionSystem._trophy()` refuses to be, and `_world_is_populated` is already the
## guard for it, so this reuses it rather than growing a second one.
##
## **3. `== 0` IS A COMPARISON AN UNIMPLEMENTED SUBJECT PASSES.** Which is why
## `ObjectiveDef.from_dict` REFUSES `area`, `named_unit` and `ticks` rather than letting
## them count as zero, and why nothing here has a default branch that returns 0 for a
## subject it does not know. `_count` returns **-1** for a subject it cannot measure and
## `_satisfied` fails every comparison against it -- so a fourth subject added to the
## enum without a case here makes its rules fail loudly instead of winning on tick 1.
class_name ObjectiveSystem
extends SimSystem


func process_tick(w: SimWorld) -> void:
	# Once decided, never re-decided. Same latch as `WinConditionSystem`: a result must
	# not be overwritten by the corpses and rubble settling in the seconds after it.
	if w.match_over:
		return
	if w.mode != MatchConfig.Mode.SCENARIO:
		return
	if w.objectives.is_empty():
		return
	var p := w.player_for(w.objective_player_id)
	if p == null:
		return
	# Trap 2. Reused from `WinConditionSystem` rather than reimplemented -- one answer to
	# "is there a match here to decide at all", so the two systems cannot disagree about
	# it on the tick that matters.
	if not WinConditionSystem._world_is_populated(w):
		return

	# A player already out of the match wins nothing. Reachable in one tick: the
	# elimination rule runs directly after this one, so a scenario player wiped out on
	# tick N is defeated on tick N and this is the guard on tick N+1.
	if p.defeated:
		return

	# Sized here rather than in `SimWorld.setup`, exactly as `VisionSystem` allocates the
	# fog on its first tick: empty means "nothing has been evaluated", so a world that was
	# never stepped reads as no tracker rather than as a list of zeros nothing maintains.
	var count := w.objectives.size()
	if p.objective_progress.size() != count:
		p.objective_progress.resize(count)
	if p.objective_done.size() != count:
		p.objective_done.resize(count)

	var census := _census(w)
	var wins_met := true
	var win_rows := 0
	var lost := false
	# EVERY ROW IS MEASURED, INCLUDING THE ONES THAT DECIDE NOTHING. An `alert` row's
	# count is written and acted on by nobody here -- 15.6 delivers the toast -- so the
	# tracker has the number it needs the moment it is built, without this system
	# learning what a toast is.
	for i in range(count):
		var o: ObjectiveDef = w.objectives[i]
		var measured := _count(w, o, census, _owners_for(w, p, o))
		p.objective_progress[i] = measured
		var met := _satisfied(o, measured)

		if o.output == ObjectiveDef.Output.LOSE:
			# Not latched -- see the header. A lose row ends the match on the tick it fires.
			if met:
				lost = true
			continue

		# THE LATCH, for win and alert rows. One-way: set on the first tick the row is
		# satisfied and never cleared, which is what makes scenario 2 winnable at all.
		if met:
			p.objective_done[i] = 1
		if o.output == ObjectiveDef.Output.WIN:
			win_rows += 1
			# ANDed, which is PLAN.md 11.8's rule and scenario 1's two halves: "a house and
			# fifteen villagers" is one objective the author wrote on two lines. An OR would
			# need grouping and no scenario wants one yet.
			#
			# Read off the LATCH rather than off `met`, so a row satisfied on an earlier
			# tick still counts on this one.
			if p.objective_done[i] == 0:
				wins_met = false

	if lost:
		# Elimination is not what happened -- a player can fail an authored condition with
		# an army still standing -- so the reason says so. `defeat()` keeps the FIRST
		# reason, which is what protects a player who resigned a tick earlier.
		p.defeat(SimPlayer.Defeat.OBJECTIVE_FAILED)
		w.match_over = true
		# NOBODY WON. A scenario's opponent is a teaching aid, not a rival with a win
		# condition of its own: the Passive AI in all three How To Play missions never
		# attacks and could not have caused this, and naming it the winner would put
		# "Player 2 won" on the screen of somebody who ran out of villagers. 0 is the same
		# value the mutual-annihilation draw carries, and `GameScene` tells the two apart
		# by `defeat_reason` -- which is the whole reason that field exists.
		w.winner_id = 0
		w.winner_team = 0
		return

	# A `scenario` with no win row can never be won and `ScenarioDef` refuses it at load,
	# so this guard covers a config built by hand -- a test, or a future editor. It is
	# here because `wins_met` starts TRUE: with no win rows to falsify it, a list of pure
	# alerts would be a match won on tick 1, which is the loudest version of trap 3.
	if win_rows == 0 or not wins_met:
		return

	w.match_over = true
	w.winner_id = p.id
	# `winner_team` beside it for the reason `WinConditionSystem` records: a teammate
	# knocked out earlier reads this to be told their side took it. 0 in a scenario, which
	# is one human against one bot in a free-for-all -- and 0 is also what a player on no
	# team carries, so the view's guard is its `> 0` rather than the comparison.
	w.winner_team = p.team if p.team > 0 else 0
	# THE OPPONENTS ARE NOT DEFEATED, and that is not an omission. `SimPlayer.defeat`
	# records a REASON, and there is no true one to record: the Passive AI that just lost
	# scenario 1 still owns its town centre and its villagers. Writing ELIMINATED would be
	# the forfeit bug again -- true about the outcome, false about how it happened -- and
	# `GameScene._victory_subtitle` reads exactly that field to write its sentence.


## Whether `measured` passes `o`'s comparison. The comparison was decided at PARSE time
## and is an enum here, so nothing in the sim ever compares the author's `">="` as a
## string -- a comparison that arrived as text is one two builds could disagree about.
static func _satisfied(o: ObjectiveDef, measured: int) -> bool:
	# A subject that could not be measured (see `_count`) fails every comparison,
	# `<=` and `==` included, which is the safe direction: an unmeasurable rule must not
	# pass. This is the clause that makes the -1 sentinel worth having.
	if measured < 0:
		return false
	match o.compare:
		ObjectiveDef.Compare.AT_MOST:
			return measured <= o.value
		ObjectiveDef.Compare.EXACTLY:
			return measured == o.value
		_:
			return measured >= o.value


## What `o` measures right now, or -1 when it cannot be measured at all.
##
## -1 RATHER THAN 0, and `_satisfied` refuses it, because 0 is a value that PASSES `== 0`
## and `<= n`. `ObjectiveDef` already refuses the unevaluable subjects at load, so this
## is the second line of the same defence and it is what makes adding a subject to the
## enum safe: forget the case here and every rule using it fails, loudly, instead of
## quietly winning the match on tick 1.
static func _count(w: SimWorld, o: ObjectiveDef, census: Dictionary,
		ids: Array[int]) -> int:
	match o.subject:
		ObjectiveDef.Subject.UNIT:
			return _sum(census, ids, "units", "unit_total", o.id)
		ObjectiveDef.Subject.BUILDING:
			return _sum(census, ids, "buildings", "building_total", o.id)
		ObjectiveDef.Subject.AGE:
			return _age_of(w, ids)
		ObjectiveDef.Subject.RESOURCE:
			return _stock_of(w, ids, o.id)
		_:
			return -1


## One entity census for the whole tick: `owner_id -> {units, unit_total, buildings,
## building_total}`, where the two dictionaries are `def_id -> count`.
##
## ONE PASS REGARDLESS OF HOW MANY OBJECTIVES THERE ARE. Counting per objective would be
## O(objectives x entities), which is the shape of cost `PopulationSystem.census` and
## `WinConditionSystem._owners_with_anything` were both rewritten to undo -- and it is
## the same measurement that caught `VisionSystem`'s full-grid decay. Four rows on a
## thousand-entity map at 10 Hz is forty thousand tests a second for an answer one walk
## produces.
##
## ⚠️ **A BUILDING COUNTS ONLY WHEN IT IS COMPLETE, AND A UNIT AS SOON AS IT EXISTS.**
## Scenario 1's objective is *"Build 1 house"*, and a pegged-out foundation is not a
## house -- it provides no population, shelters nobody, and can be cancelled. This is
## deliberately the population cap's rule (`PopulationSystem.census`) and deliberately
## NOT `WinConditionSystem._owns_anything`'s, which counts a foundation because it is
## answering a different question: whether its owner is still in the game. Both are
## right; they are not the same test.
##
## Dead entities count for nothing. A corpse (4.7) lingers ten seconds and rubble (5.5) a
## minute, so counting them would let an objective read as satisfied for a minute after
## it stopped being true -- and, for an `at_most` rule, make the player wait out the
## wreckage.
static func _census(w: SimWorld) -> Dictionary:
	var out: Dictionary = {}
	for e in w.entities.values():
		if not e.alive:
			continue
		var is_unit := e is SimUnit
		if not is_unit and not (e is SimBuilding):
			continue
		if not is_unit and not (e as SimBuilding).is_complete():
			continue
		var entry: Dictionary = out.get(e.owner_id, {})
		if entry.is_empty():
			entry = {"units": {}, "unit_total": 0, "buildings": {}, "building_total": 0}
			out[e.owner_id] = entry
		var bucket: Dictionary = entry["units"] if is_unit else entry["buildings"]
		bucket[e.def_id] = int(bucket.get(e.def_id, 0)) + 1
		var total_key := "unit_total" if is_unit else "building_total"
		entry[total_key] = int(entry[total_key]) + 1
	return out


## `ids`' total for one subject, by def id or across all of them.
##
## An EMPTY `id` means "any of that subject", which is legal and load bearing: PLAN.md
## 11.8's *leave the enemy nothing* is `{"subject": "unit", "owner": "enemy", "compare":
## "==", "value": 0}` with no id at all. That is why the totals are kept beside the
## per-def buckets rather than summed from them here -- a walk of a dictionary per
## objective per tick is the cost `_census` exists to avoid.
static func _sum(census: Dictionary, ids: Array[int], bucket_key: String,
		total_key: String, id: StringName) -> int:
	var total := 0
	for owner_id in ids:
		var entry: Dictionary = census.get(owner_id, {})
		if entry.is_empty():
			continue
		if id.is_empty():
			total += int(entry[total_key])
		else:
			total += int((entry[bucket_key] as Dictionary).get(id, 0))
	return total


## What `ids` are holding of one resource kind, added together.
##
## ⚠️ **IT IS WHAT THEY HOLD NOW, NOT WHAT THEY HAVE EVER GATHERED**, and the difference
## is the whole reason a win row latches. `SimPlayer.stock` is a balance: it goes DOWN
## when the player builds a house or buys an age. *"Gather 500 food"* is therefore
## measured as *"hold 500 food at some point"*, which is exactly what the scenario's own
## overview tells the player to watch for -- *"watch the food icon until it ticks up to
## 500"* -- and it is the header's worked example of why the latch is not optional.
##
## Cumulative gathering was the alternative and is deliberately not built: it needs a
## new per-player running total, written by `GatherSystem`, folded into `state_hash()`
## and carried on the wire -- a whole new piece of simulation state for a distinction no
## authored scenario has asked for. If one ever does, that is where it goes, and this
## comment is what says the current answer is a choice.
static func _stock_of(w: SimWorld, ids: Array[int], kind: StringName) -> int:
	# An empty kind cannot be answered: "500 of any resource" would add food to stone,
	# which measures nothing a player could aim at. `ObjectiveDef` refuses it at load;
	# -1 here is the second line of that defence.
	if kind.is_empty():
		return -1
	var total := 0
	for id in ids:
		var p := w.player_for(id)
		if p != null:
			total += int(p.stock.get(kind, 0))
	return total


## The age to compare for `ids`: the HIGHEST any of them has reached.
##
## ⚠️ **MAX, AND IT IS THE READING THAT WORKS IN BOTH DIRECTIONS.** For `self` the set is
## one player and the question does not arise. For a set it does, and max is what makes
## the two natural sentences both true: *"an enemy has reached the Age of Embers"* is
## `>= 2` against the most advanced of them, and *"every enemy is still in the Age of
## Ash"* is `<= 1` against that same number. Taking the minimum would invert the second,
## and taking a sum would compare an age against a total, which is meaningless.
##
## AN EMPTY SET IS 0, which is no age at all -- 0 is below every real age, since
## `SimPlayer.age` starts at 1. So `>= 2` against no allies fails, which is right, and
## `<= 1` passes vacuously, which is the ordinary meaning of "every one of none".
static func _age_of(w: SimWorld, ids: Array[int]) -> int:
	var best := 0
	for id in ids:
		var p := w.player_for(id)
		if p != null:
			best = maxi(best, p.age)
	return best


## The player ids `o.owner` names, from `viewer`'s point of view.
##
## RESOLVED FROM `w.players` AND NEVER FROM ENTITY OWNER IDS -- trap 1 in the header, and
## the reason *leave the enemy nothing* does not mean *shoot every deer*. Gaia has no row
## in `players`, so it is in none of these sets and no clause has to say so.
##
## THROUGH `Diplomacy` WITH THE TEAM TABLE PASSED IN, which PLAN.md 11.8 asks for by
## name. It is the one place the three rules of an alliance are written down: you are
## always your own ally, team 0 is the ABSENCE of a team rather than one everybody
## shares, and gaia allies with nobody.
##
## ⚠️ **`ALLY` INCLUDES THE VIEWER, AND THAT IS A DECISION RATHER THAN A CONSEQUENCE OF
## `Diplomacy.allied(a, a)` BEING TRUE.** `ALLY` means YOUR SIDE. The only reason the
## owner axis has an `ally` at all is a co-op scenario -- *"your side must build ten
## houses"* -- and a rule that counted your teammate's houses while ignoring your own is
## a rule nobody would author. `SELF` is already there for the narrower question, so
## excluding the viewer here would cost an extra clause to implement the less useful of
## the two meanings.
##
## `INDEX` names one player outright and is the axis that does not move when the
## alliances do -- *"player 3 must survive"*, which is an escort mission's shape. It is
## per-OBJECTIVE, which is why this takes `o` and is not one table built per tick.
##
## An index nobody occupies resolves to a player who owns nothing and has no age, so its
## counts come back 0 -- the same answer as a player who lost everything. That ambiguity
## is left alone on purpose: refusing an unoccupied index belongs at LOAD, where the
## scenario knows how many opponents it declared, and not here, where the only options
## are to guess or to end the match.
static func _owners_for(w: SimWorld, viewer: SimPlayer, o: ObjectiveDef) -> Array[int]:
	match o.owner:
		ObjectiveDef.Owner.INDEX:
			return [o.owner_index] as Array[int]
		ObjectiveDef.Owner.ALLY:
			return _side_of(w, viewer, true)
		ObjectiveDef.Owner.ENEMY:
			return _side_of(w, viewer, false)
		_:
			return [viewer.id] as Array[int]


## Everybody allied with `viewer` (`want_allies`), or everybody not (`not want_allies`).
static func _side_of(w: SimWorld, viewer: SimPlayer, want_allies: bool) -> Array[int]:
	var out: Array[int] = []
	for other in w.players:
		if Diplomacy.allied(viewer.id, other.id, w.teams) == want_allies:
			out.append(other.id)
	return out
