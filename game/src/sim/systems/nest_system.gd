## The dragon claim (PLAN.md 13.2, this file is 13.2b). Kill the mother, hold the nest
## for six minutes, receive a dragon.
##
## 13.2a put the mother and her nest on every generated map and killing her dropped
## nothing. This is the rest of the rule, and it is four events:
##
##   1. the mother dies -> a `unit.dragon_baby` appears at the nest, GAIA'S
##   2. `GROW_TICKS` pass -> the hatchling is replaced by a `unit.dragon` owned by
##      whoever landed the killing blow
##   3. the nest is destroyed -> the hatchling dies with it and the claim is void
##   4. the hatchling is killed outright -> the same, by the shorter road
##
## ⚠️ **THE HATCHLING IS GAIA'S UNTIL IT GROWS, AND THAT IS THE WHOLE TENSION.**
## PLAN.md 13.2 says the GROWN dragon is "owned by the claimant", and handing the baby
## over at spawn instead would end the feature on the tick it started: the claimant would
## walk it out of reach and there would be nothing left to hold, nothing for a rival to
## deny, and no reason for the nest to be destructible. What the claimant owns during the
## window is a promise; what they have to defend is a place.
##
## ⚠️ **`claim_owner` IS NEVER CLEARED ONCE SET, AND THAT IS THE "ONE DRAGON PER MAP"
## GUARANTEE** (13.2a made the other half of it: MapGen places one nest and one mother).
## It is the flag saying this nest has already given up its dragon, so a mother's CORPSE
## -- which lies there for `SimUnit.CORPSE_TOTAL_TICKS` -- cannot start a second claim,
## and neither can anything else. `claim_ticks_left` is the countdown and returns to -1;
## `claim_owner` is the record and does not.
##
## ⚠️ **WHY THIS IS ITS OWN SYSTEM AND NOT THREE LINES IN `WildlifeSystem`.** It is the
## first rule in this game that changes who owns a gaia unit. `HerdSystem` is the nearest
## shape and its header rules the idea out by name -- *"herding is not owning"* -- because
## a herded sheep staying gaia's is what keeps `GatherSystem`, `WinConditionSystem` and
## `AttackCommand` out of it. Nothing there generalises; this needed writing.
##
## RUNS DIRECTLY BEFORE `DeathSystem`, and both halves of that matter. AFTER
## `CombatSystem`, so a mother or a nest killed on this tick is already `alive == false`
## and this sees the death on the tick it happened. BEFORE `DeathSystem`, because that is
## what retires the corpse and -- for a nest, which carries `leaves_rubble: false` --
## despawns the building outright on the tick it falls. A tick later there would be no
## nest in `entities` to read the claim off.
class_name NestSystem
extends SimSystem

const NEST_DEF := &"building.dragon_nest"
const BABY_DEF := &"unit.dragon_baby"
const GROWN_DEF := &"unit.dragon"

## 360 seconds at `SimClock`'s 10 ticks a second (PLAN.md 13.2's table).
##
## THE FIGURE WAS CONFIRMED RATHER THAN ASSUMED: conversation said "5 minutes", PLAN.md
## said 360 s in two separate places, and the owner settled on 360 on 2026-09-04. It is
## not a number about how long a dragon takes to grow -- it is how long a claim has to be
## defended, which is the only thing it controls.
const GROW_TICKS := 3600


func process_tick(w: SimWorld) -> void:
	# ONE PASS, the shape `DeathSystem` and `PopulationSystem` already take. Three lists
	# come out of it and each is almost always empty: on a normal map there is exactly
	# one nest, no dead guardian and no hatchling.
	var nests: Array[SimBuilding] = []
	var fresh_kills: Array[SimUnit] = []
	var babies: Array[SimUnit] = []

	for e in w.entities.values():
		if e is SimBuilding:
			if e.def_id == NEST_DEF:
				nests.append(e as SimBuilding)
		elif e is SimUnit:
			var u: SimUnit = e
			# ⚠️ **GAIA'S HATCHLINGS ONLY, AND `owner_id == 0` IS LOAD-BEARING RATHER THAN
			# TIDY.** This header's own rule is that *the hatchling is gaia's until it
			# grows* -- `_start_claims` spawns it with owner 0 and `_advance_claims`
			# DESPAWNS it to pay out, so no claim of 13.2's ever produces a
			# player-owned `unit.dragon_baby`. One therefore cannot be this system's
			# business, and collecting it anyway is a live bug rather than a wasted check:
			# `_reap_orphans` kills every hatchling that is not some nest's recorded
			# `claim_baby_id`.
			#
			# **`Mode.TROPHY` IS EXACTLY THAT UNIT** (11.2). A trophy is a
			# `unit.dragon_baby` a PLAYER owns from the first tick and must protect all
			# match, standing at their base and recorded on no nest at all -- so without
			# this clause every trophy in the game would be killed on tick 1 and, since
			# losing your trophy is defeat, **every player would be eliminated
			# immediately**. That is the "on a map with no trophies, defeats everybody on
			# tick 1" failure PLAN.md 11.2 warns about, arriving through a door nobody was
			# watching: not the rule getting it wrong, but a different system reaping the
			# thing the rule is about. `11.x-trophy`'s card predicted the collision
			# (*"reaching for NestSystem is not [right] -- it would hand a player's trophy
			# to whoever killed something"*) and this is the line that prevents it.
			if u.def_id == BABY_DEF and u.owner_id == 0:
				babies.append(u)
			elif not u.alive and u.owner_id == 0 and u.last_attacker_owner > 0:
				fresh_kills.append(u)

	# ⚠️ **CLEARED BEFORE THE EARLY RETURN, NOT AFTER IT.** `SimWorld.claim_*` is the
	# HUD's mirror (13.2c) and the tick a nest is despawned is exactly the tick this
	# function stops having any nests to publish from -- so leaving the clear at the
	# bottom would freeze the last countdown on the badge forever, on the one event the
	# ring most needs to report. Clear, then republish from what is actually there.
	w.claim_owner = 0
	w.claim_ticks_left = -1
	w.claim_total_ticks = 0

	if nests.is_empty() and babies.is_empty():
		return

	# ⚠️ **ADVANCE BEFORE START, SO A CLAIM DOES NOT LOSE ITS FIRST TICK.** The other
	# order costs one: the hatchling is spawned, and the countdown that was just set to
	# `GROW_TICKS` is immediately decremented by the same call, so the window is
	# `GROW_TICKS - 1` ticks long. A tenth of a second out of six minutes is nothing to
	# play against and everything to a test that asserts the boundary -- which is how it
	# was found, by `test_it_is_still_a_hatchling_the_tick_before` reporting a hatchling
	# that had already grown. Nothing started this tick is advanced this tick.
	_advance_claims(w, nests)
	_start_claims(w, nests, fresh_kills)
	_reap_orphans(w, nests, babies)
	# LAST, so it reports the claim as it stands at the END of the tick -- a claim that
	# started, matured or was denied in the three calls above has already had its effect
	# and this publishes the result rather than the state it was found in.
	_publish_claim(w, nests)


## Copy the one running claim onto the world, for the HUD (13.2c).
##
## `SimWorld.claim_*`'s own header carries the reasoning: why the claim goes on the wire as
## a match-level fact rather than on the nest, and why this is a mirror that can only draw
## a wrong ring and never pay out a wrong dragon.
##
## LOWEST NEST ID WINS, which is `_nest_for`'s tie-break and is here for the same reason:
## `MapGenerator` places one nest, a hand-authored map (16.3) will be able to place two,
## and one ring cannot report two countdowns. Determinism rather than a judgement about
## which claim matters more -- and every nest keeps its own full state either way.
##
## ⚠️ **A SPENT CLAIM PUBLISHES NOTHING, WHICH IS NOT THE SAME AS AN UNCLAIMED NEST.**
## `claim_owner` is never cleared on the nest -- it is the "this nest has given up its
## dragon" record and the whole of the one-dragon-per-map guarantee -- so keying off it
## here would leave the badge showing a full ring for a claim that paid out four minutes
## ago. `claim_ticks_left >= 0` is the RUNNING test, and it is the nest's own.
func _publish_claim(w: SimWorld, nests: Array[SimBuilding]) -> void:
	var best: SimBuilding = null
	for n in nests:
		if n.claim_ticks_left < 0:
			continue
		# ALIVE, checked rather than assumed: `_advance_claims` abandons a dead nest's
		# claim above, so this is belt and braces on the one path where the two could
		# ever disagree -- and a razed nest advertising a countdown is precisely the
		# frame a rival needs to see end.
		if not n.alive:
			continue
		if best == null or n.id < best.id:
			best = n
	if best == null:
		return
	w.claim_owner = best.claim_owner
	w.claim_ticks_left = best.claim_ticks_left
	w.claim_total_ticks = GROW_TICKS


## A guardian has fallen to somebody: begin the claim on the nest she was standing over.
##
## ⚠️ **`last_attacker_owner > 0` IS THE WHOLE OF "SOMEBODY", AND `> 0` RATHER THAN
## `!= NO_ATTACKER` IS DELIBERATE.** Owner 0 is gaia, which is a perfectly real attacker
## everywhere else in the sim -- a wolf killing a villager is owner 0 landing a blow --
## and gaia claiming a dragon from itself is not a thing that should be expressible. The
## filter is applied in the caller's pass so a mother killed by a debug destroy or by a
## falling building drops nothing, which is the honest answer: nobody killed her.
func _start_claims(w: SimWorld, nests: Array[SimBuilding], fresh_kills: Array[SimUnit]) -> void:
	if fresh_kills.is_empty():
		return
	for u in fresh_kills:
		var def := w.unit_def(u.def_id)
		if def == null or not def.guards_post:
			continue
		var nest := _nest_for(nests, u)
		if nest == null:
			continue
		# ALREADY GIVEN UP ITS DRAGON, once and for all. See the header.
		if nest.claim_owner != 0:
			continue
		if not nest.alive:
			continue
		var baby := w.spawn_unit(BABY_DEF, 0, nest.tile())
		if baby == null:
			continue
		nest.claim_owner = u.last_attacker_owner
		nest.claim_ticks_left = GROW_TICKS
		nest.claim_baby_id = baby.id


## The nest this guardian was guarding.
##
## `roam_home` FIRST, BECAUSE THAT IS THE POST ITSELF. `WildlifeSystem._post_for` sets it
## to the centre of the nearest gaia building on a `guards_post` animal's first tick, so
## it is the exact answer and not an approximation -- and it is still the right answer for
## a mother who was killed a long way from home, which her own tile would not be.
##
## FALLING BACK TO WHERE SHE DIED covers the one case `roam_home` cannot: a guardian
## killed before `WildlifeSystem` has ever looked at her still carries the (-1, -1)
## sentinel. Reachable only in a test that spawns and kills in the same tick, and cheap
## enough to answer properly rather than leave as a null.
##
## NEAREST WINS AND THE LOWEST ID BREAKS A TIE -- determinism, not fairness, the same
## rule every scan in `WildlifeSystem` follows. A map with two nests is not something
## `MapGenerator` can produce, but a hand-authored one (16.3) will be able to.
func _nest_for(nests: Array[SimBuilding], u: SimUnit) -> SimBuilding:
	var from := u.roam_home if u.roam_home != Vector2i(-1, -1) else u.tile()
	var best: SimBuilding = null
	var best_gap := 1 << 30
	for n in nests:
		var gap := CombatSystem.tile_gap(from, n.footprint_rect())
		if best != null and (gap > best_gap or (gap == best_gap and n.id > best.id)):
			continue
		best_gap = gap
		best = n
	return best


## Count a running claim down, and pay it out when it matures.
func _advance_claims(w: SimWorld, nests: Array[SimBuilding]) -> void:
	for nest in nests:
		if nest.claim_ticks_left < 0:
			continue

		# THE NEST IS DOWN: the claim dies with it, and so does the hatchling (PLAN.md
		# 13.2 -- "killing it kills the baby, so the claim must be HELD and a rival can
		# deny it"). This is the one branch that makes 1200 hp of stone a target rather
		# than scenery. `claim_owner` is deliberately left set: the nest has had its
		# dragon claimed and denied, and neither is a thing that happens twice.
		if not nest.alive:
			_kill_baby(w, nest)
			nest.claim_ticks_left = -1
			continue

		# THE HATCHLING IS DOWN: a rival went straight at it instead. Same outcome by a
		# different road, and it needs no rule of its own -- the claim simply has nothing
		# left to mature. `get_entity` answers null for a hatchling already despawned.
		var baby := w.get_entity(nest.claim_baby_id) as SimUnit
		if baby == null or not baby.alive:
			nest.claim_baby_id = 0
			nest.claim_ticks_left = -1
			continue

		# ⚠️ **A DEFEATED CLAIMANT IS PAID NOTHING, AND THIS IS NOT TIDINESS.**
		# `SimPlayer.defeated` is a one-way latch and `WinConditionSystem` decides who is
		# standing by counting what a player still OWNS -- so a dragon handed to a player
		# knocked out four minutes ago puts them back on the board, un-ends a match that
		# had already been won, and does it 360 s after anybody was still watching that
		# corner of the map. Perfectly reachable: kill the mother, get wiped out inside
		# six minutes. `PlaceWallCommand` and `MarketExchangeCommand` guard on the same
		# flag for the smaller version of the same reason.
		#
		# THE CLAIM IS ABANDONED RATHER THAN HELD OPEN. There is nobody left to hold the
		# nest, and re-opening it to the next player who wanders past would be a second
		# rule nobody asked for.
		var claimant := w.player_for(nest.claim_owner)
		if claimant == null or claimant.defeated:
			_kill_baby(w, nest)
			nest.claim_ticks_left = -1
			continue

		nest.claim_ticks_left -= 1
		if nest.claim_ticks_left > 0:
			continue

		# GROWN. The hatchling is REPLACED rather than re-owned, and the two are not the
		# same operation: it is a different def with different hp, armour, speed, domain
		# behaviour and pop cost, and `spawn_unit` is the one place that copies all of
		# those off a def. Mutating `def_id` and `owner_id` in place would leave a 300 hp
		# dragon that cannot fly.
		#
		# AT THE HATCHLING'S OWN TILE, which is the nest: `blocks_movement: false` means
		# the ground inside a henge is walkable, so there is nothing to displace and no
		# placement to fail.
		var at := baby.tile()
		w.despawn(baby.id)
		nest.claim_baby_id = 0
		nest.claim_ticks_left = -1
		w.spawn_unit(GROWN_DEF, nest.claim_owner, at)


## Kill any hatchling that no live claim is looking after.
##
## THE DEFENCE IS AGAINST A LINK BREAKING, not against a rule. Every hatchling in the game
## is spawned by `_start_claims` and recorded on a nest; if a nest is ever removed by some
## route other than falling -- `SimWorld.despawn` called directly, a map edit, a load --
## its hatchling would otherwise sit at the nest forever, gaia's, growing into nothing.
## Cheaper and more honest to sweep for it than to add a back-pointer to `SimUnit` that
## exists for one unit and has to be kept in step from two directions.
func _reap_orphans(w: SimWorld, nests: Array[SimBuilding], babies: Array[SimUnit]) -> void:
	if babies.is_empty():
		return
	var kept := {}
	for n in nests:
		if n.alive and n.claim_baby_id != 0:
			kept[n.claim_baby_id] = true
	for b in babies:
		# STILL IN THE WORLD, checked rather than assumed: `babies` was collected at the
		# top of the tick and `_advance_claims` may have despawned one since, by growing
		# it. A `RefCounted` that has left `entities` is still a perfectly usable object,
		# so killing it would succeed, do nothing, and read as a rule that fires on every
		# claim that matures.
		if w.get_entity(b.id) == null:
			continue
		if b.alive and not kept.has(b.id):
			b.take_damage(b.hp, 0, SimEntity.NO_ATTACKER)


## `take_damage`, not `alive = false`, so the hatchling goes through `DeathSystem`'s
## ordinary corpse path on the next tick and dies, decays and despawns exactly like
## anything else -- the same argument `DeathSystem._kill_garrison` makes about a tower's
## occupants, and reached here for the same reason: it is a death caused by a building
## falling.
##
## `NO_ATTACKER` because nobody attacked the hatchling. Whoever razed the nest killed it,
## and that is already recorded on the nest; crediting them here would say a blow landed
## on the baby that never did.
func _kill_baby(w: SimWorld, nest: SimBuilding) -> void:
	var baby := w.get_entity(nest.claim_baby_id) as SimUnit
	nest.claim_baby_id = 0
	if baby != null and baby.alive:
		baby.take_damage(baby.hp, 0, SimEntity.NO_ATTACKER)
