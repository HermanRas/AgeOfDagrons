## Drives every shipped scenario to its win, headless, through the REAL launch path
## (PLAN.md 15.9's first half).
##
## ## WHY THIS EXISTS AND WHY `test_objectives` IS NOT ENOUGH
##
## `test_objectives` builds its worlds by hand: two players, a fill of grass, and
## `spawn_unit` for whatever the case needs. That is right for testing the RULE, and it is
## blind to everything BETWEEN a `scenario.json` and a running match -- `Campaigns` finding
## the folder, `build_config` filling the config, `SimWorld.setup` copying it, `MapGen`
## laying out a real 96x96 map with a town centre and five villagers on it.
##
## **A rule that is correct and never reached looks exactly like a rule that is wrong**, and
## from the player's chair the two are the same bug: nothing happens. So this stands up the
## real thing and reports what the sim actually believes, tick by tick.
##
## Run it as:
##
##   godot --headless --path game res://dev_preview/PreviewScenarioWin.tscn
##
## It ends with `get_tree().quit()`. A headless scene does NOT end when `_ready()` returns
## -- `preview_vision_cost` printed its answer and then hung for ten minutes, which reads
## as a crash rather than as a finished run.
extends Node

## How many ticks to allow after the world is in a winning shape. Generous: the objective
## is judged on the finished tick and `ObjectiveSystem` runs once per tick, so one should
## do -- and if it takes more than one, that is worth seeing rather than hiding.
const GRACE_TICKS := 5


func _ready() -> void:
	print("\n=== scenario win driver (15.9) ===")
	var campaigns := Campaigns.new().discover()
	if campaigns.is_empty():
		print("NO CAMPAIGNS FOUND -- nothing to drive")
		get_tree().quit()
		return

	for c in campaigns:
		print("\ncampaign '%s' (%s)" % [c.name, c.folder])
		for s in c.scenarios:
			_drive(c, s)

	print("\n=== done ===")
	get_tree().quit()


func _drive(c: CampaignDef, s: ScenarioDef) -> void:
	print("\n--- %s/%s : %s" % [c.folder, s.folder, s.name])

	var problems: Array[String] = []
	var cfg := s.build_config(problems)
	if cfg == null:
		print("    REFUSED TO LAUNCH: %s" % " | ".join(problems))
		return

	print("    mode=%s  objectives=%d  objective_player_id=%d"
			% [MatchConfig.mode_name(cfg.mode), cfg.objectives.size(),
			cfg.objective_player_id])

	# ⚠️ **WHO THE OPPONENT ACTUALLY IS, READ OFF THE CONFIG AND NOT OFF THE FILE.**
	# `scenario.json` names a level as a STRING and `ScenarioDef._ai_level_of` converts it
	# with `AIProfile.IDS.find()` -- a lookup coupled to `SimPlayer.AILevel` BY POSITION,
	# which nothing at either end says. So "the file says easy" and "an easy bot is in this
	# match" are two different facts, and only the second one decides whether the mission
	# fights back. Printed per bot with the profile's own `attacks` flag beside it, because
	# *passive versus anything else* is the distinction a play-test actually feels.
	for i in range(cfg.ai_players.size()):
		if not cfg.ai_players[i]:
			continue
		var level: int = cfg.ai_levels[i]
		var id_name: String = AIProfile.IDS[level] if level >= 0 \
				and level < AIProfile.IDS.size() else "?"
		# `ai_profile()` FALLS BACK TO EASY for an out-of-range level rather than handing
		# back null, so `id_name` above is the honest reading of what the config SAYS and
		# this is what the match will actually run. They agree here; if they ever did not,
		# printing both is what would show it.
		var profile := GameDataRegistry.ai_profile(level)
		print("      player %d: AI level %d = '%s'  ->  profile '%s', attacks=%s"
				% [cfg.player_ids[i], level, id_name, profile.id, profile.attacks])
	for o in cfg.objectives:
		print("      row: %s" % _describe_row(o))

	# THE REAL WORLD, not a bare one: `setup` then `MapGen.build`, which is exactly what
	# `SimHost.build` does. Without MapGen there is no town centre and no starting
	# villagers, and the counts below would be measuring a different match.
	var w := SimWorld.new()
	w.setup(cfg)
	MapGen.build(w, cfg)
	w.step()

	# WHOSE CHAIR THIS DRIVER SITS IN. `objective_player_id` is 0 in a conquest scenario --
	# 0 means "nobody", because there are no objectives to have a viewpoint on -- so a
	# conquest scenario has to fall back to the human, which `build_config` numbers 1. The
	# first version of this file asked for `player_for(0)`, got null and reported "NO
	# OBJECTIVE PLAYER" for scenario 3, which reads as a broken scenario rather than as a
	# driver that did not know what mode it was in.
	var hero_id := cfg.objective_player_id
	if hero_id <= 0:
		hero_id = cfg.player_ids[0] if not cfg.player_ids.is_empty() else 0
	var p := w.player_for(hero_id)
	if p == null:
		print("    NO PLAYER TO DRIVE -- player_for(%d) is null" % hero_id)
		return

	print("    after 1 tick: %s" % _state(w, p))
	if cfg.mode != MatchConfig.Mode.SCENARIO:
		print("    conquest scenario -- driven by killing the opponent, not by objectives")
		_drive_conquest(w, hero_id)
		return

	# ── put the world into the shape each row asks for ────────────────────────────
	#
	# ONE ROW AT A TIME, printing after each, so a row that never ticks off is named
	# rather than leaving "the match did not end" as the whole diagnosis.
	for i in range(w.objectives.size()):
		var o: ObjectiveDef = w.objectives[i]
		if o.output != ObjectiveDef.Output.WIN:
			continue
		_satisfy(w, p, o)
		for t in range(GRACE_TICKS):
			w.step()
			if w.match_over:
				break
		# A CLAIM IN FLIGHT IS SOMETHING THE WORLD OWES THE PLAYER, so it is waited out
		# rather than shortcut. See `_settle`.
		if not w.match_over:
			_settle(w)
		print("    after row %d (%s): %s" % [i, _describe_row(o), _state(w, p)])
		if w.match_over:
			break

	if w.match_over:
		print("    WON on tick %d, winner_id=%d" % [w.tick, w.winner_id])
	else:
		print("    !!! NOT WON. %s" % _state(w, p))
		print("    !!! every win row's latch above is what to read: a 0 there is the row")
		print("    !!! that did not tick, and its live count says why")


## Make `o` true for `p`, by the crudest means that is still the real mechanism.
##
## SPAWNS RATHER THAN PLAYS. Training fifteen villagers properly means gathering food for
## several minutes of simulated time, and what is being checked here is the RULE and the
## wiring, not the economy -- `preview_ai_match` is what plays a match out. A spawned
## villager is the same entity a trained one is, which is the only property that matters
## to `_census`.
func _satisfy(w: SimWorld, p: SimPlayer, o: ObjectiveDef) -> void:
	# GAIA'S SIDE OF THE ROW IS KILLED, NOT SPAWNED, and it is checked before `subject`
	# because it is the OWNER that decides the verb here. `_spawn_up_to` would count the
	# hero's dragons against a row about the mother's, find 0, decide the row was already
	# satisfied, and report a scenario that never ticked -- which is scenario 4's first row
	# exactly.
	if o.owner == ObjectiveDef.Owner.GAIA:
		_kill_gaia_down_to(w, p, o)
		return
	# ⚠️ **AN `enemy` ROW IS THE SAME TRAP AS THE GAIA ONE AND IT ARRIVED WITH SCENARIO 5.**
	# `_spawn_up_to` counts and spawns for the HERO, so *"the enemy has 0 units"* would find
	# the hero's own count, compare it against a `value` of 0, decide the row was already
	# satisfied and print "already N of" -- then the row would never tick and the driver
	# would report a scenario that cannot be won. It is the OWNER that decides the verb
	# here: your own things get spawned, somebody else's get killed.
	if o.owner == ObjectiveDef.Owner.ENEMY:
		_kill_enemy_down_to(w, p, o)
		return
	match o.subject:
		ObjectiveDef.Subject.UNIT:
			_spawn_up_to(w, p, o, true)
		ObjectiveDef.Subject.BUILDING:
			_spawn_up_to(w, p, o, false)
		ObjectiveDef.Subject.AGE:
			# Straight to the age rather than through `AdvanceAgeCommand`, which would need
			# the cost paid and 100 ticks of advance -- both real, neither this scene's
			# subject. `DebugSetAgeCommand` exists for exactly this kind of jump.
			p.age = maxi(p.age, o.value)
			print("      set age to %d" % p.age)
		ObjectiveDef.Subject.RESOURCE:
			p.add_resource(o.id, maxi(0, o.value - int(p.stock.get(o.id, 0))))
			print("      topped %s up to %d" % [o.id, int(p.stock.get(o.id, 0))])
		_:
			print("      CANNOT SATISFY subject %s from here"
					% ObjectiveDef.Subject.keys()[o.subject])


func _spawn_up_to(w: SimWorld, p: SimPlayer, o: ObjectiveDef, units: bool) -> void:
	var have := _count_of(w, p.id, o.id, units)
	var want := o.value
	if have >= want:
		print("      already %d of %s" % [have, o.id])
		return
	# Somewhere clear of the base. `force` is on, because placement rules are not what is
	# being checked and a refused placement would read as a failed objective.
	var origin := _clear_tile(w)
	for i in range(want - have):
		if units:
			w.spawn_unit(o.id if not o.id.is_empty() else &"unit.villager", p.id,
					origin + Vector2i(i % 8, i / 8))
		else:
			w.spawn_building(o.id if not o.id.is_empty() else &"building.house", p.id,
					origin + Vector2i(i * 6, 0), SimBuilding.Phase.COMPLETE, true)
	print("      spawned %d more %s (had %d, wanted %d)"
			% [want - have, o.id, have, want])


## Bring gaia's count of `o.id` down to `o.value` by killing them, credited to the hero.
##
## ⚠️ **`take_damage` WITH THE HERO'S OWNER ID, AND THAT ARGUMENT IS THE WHOLE POINT.**
## Scenario 4's win does not come from the mother being dead -- it comes from
## `NestSystem._start_claims` reading `last_attacker_owner` and hatching a claim for
## whoever landed the blow. `alive = false`, which is what `_drive_conquest` does two
## functions down, would kill her and drop **nothing**: `last_attacker_owner` stays
## `NO_ATTACKER`, the nest never hatches, and the second row could never be satisfied. So
## this is the crudest means that is still the REAL mechanism, which is this file's rule.
##
## AT_LEAST IS NOT SATISFIABLE FROM HERE and says so rather than doing nothing. *"Gaia must
## have at least one dragon"* is a row about the map being right, not about anything a
## driver can arrange, and silently leaving it would print a scenario that did not win with
## no line explaining which step was skipped.
func _kill_gaia_down_to(w: SimWorld, p: SimPlayer, o: ObjectiveDef) -> void:
	if o.compare == ObjectiveDef.Compare.AT_LEAST and o.value > 0:
		print("      CANNOT SATISFY '%s >= %d' for gaia -- that is a fact about the map"
				% [o.id, o.value])
		return
	var victims: Array[SimUnit] = []
	for e in w.entities.values():
		if not (e is SimUnit) or not e.alive or e.owner_id != 0:
			continue
		if o.id.is_empty() or e.def_id == o.id:
			victims.append(e as SimUnit)
	# Determinism is not required of a dev_preview, but a stable order makes two runs
	# comparable, which is the only reason anybody reads this scene's output twice.
	victims.sort_custom(func(a: SimUnit, b: SimUnit) -> bool: return a.id < b.id)

	var killed := 0
	while victims.size() - killed > o.value and killed < victims.size():
		var v := victims[killed]
		v.take_damage(v.hp, 0, p.id)
		killed += 1
	print("      killed %d of gaia's %s, credited to player %d (had %d, row wants %d)"
			% [killed, o.id if not o.id.is_empty() else &"units", p.id, victims.size(),
			o.value])


## Bring the ENEMY's count of `o`'s subject down to `o.value` by killing them.
##
## SCENARIO 5's SHAPE, and PLAN.md 11.8's own worked example -- *leave the enemy nothing* --
## which no shipped scenario used until 2026-09-07. It is conquest expressed as objectives,
## so the driver has to be able to express it too.
##
## ## ONE SUBJECT AT A TIME, WHICH IS WHAT MAKES THE TWO ROWS INDEPENDENT
##
## Scenario 5 is two ANDed rows -- no units, no buildings -- and killing both on the first
## row would tick the second one before the loop reached it, which is a driver that proves
## the pair rather than each. So a `unit` row kills units and leaves the base standing.
##
## ⚠️ **THE LATCH IS WHY THIS WORKS AGAINST A LIVE AI.** An Easy opponent trains again the
## moment its units are gone, so the enemy's live count is back above zero within a few
## ticks -- and the row stays satisfied because `ObjectiveSystem` latches a win row one-way.
## That is not the driver getting away with something; it is the rule a real player relies
## on, and this is the one place it is exercised against an opponent that fights back.
##
## THROUGH `Diplomacy` RATHER THAN `owner_id != p.id`, which is what `_drive_conquest` two
## functions down can afford to do because it is killing EVERYTHING. This has to agree with
## `ObjectiveSystem._owners_for`, and that resolves the enemy set through `Diplomacy.allied`
## with the team table -- so a future co-op scenario cannot have the driver killing an ally
## to satisfy a row about an enemy.
##
## GAIA IS NOT IN THE SET, for `ObjectiveSystem`'s trap 1: the mother dragon, the deer and
## the trees belong to owner 0 and *leave the enemy nothing* must never come to mean *shoot
## every animal on the map*. `owner_id > 0` is the whole guard, and it is the same one the
## system's own resolver gets for free by reading `w.players`.
func _kill_enemy_down_to(w: SimWorld, p: SimPlayer, o: ObjectiveDef) -> void:
	if o.compare == ObjectiveDef.Compare.AT_LEAST and o.value > 0:
		print("      CANNOT SATISFY '%s >= %d' for the enemy -- that is a fact about the"
				% [o.id, o.value] + " match, not something a driver arranges")
		return
	if o.subject != ObjectiveDef.Subject.UNIT \
			and o.subject != ObjectiveDef.Subject.BUILDING:
		print("      CANNOT SATISFY an enemy row about %s from here"
				% ObjectiveDef.Subject.keys()[o.subject])
		return

	var want_units := o.subject == ObjectiveDef.Subject.UNIT
	var victims: Array[SimEntity] = []
	for e in w.entities.values():
		if not e.alive or e.owner_id <= 0:
			continue
		if Diplomacy.allied(p.id, e.owner_id, w.teams):
			continue
		if want_units:
			if not (e is SimUnit):
				continue
		elif not (e is SimBuilding):
			continue
		if o.id.is_empty() or e.def_id == o.id:
			victims.append(e as SimEntity)
	# A stable order for the same reason `_kill_gaia_down_to` sorts: two runs of this scene
	# are only worth comparing if they killed the same things in the same order.
	victims.sort_custom(func(a: SimEntity, b: SimEntity) -> bool: return a.id < b.id)

	var killed := 0
	while victims.size() - killed > o.value and killed < victims.size():
		var v := victims[killed]
		# `take_damage` and not `alive = false`, which is this file's rule -- the crudest
		# means that is still the real mechanism. It costs nothing here (no claim reads the
		# attacker off an enemy building) and it keeps one way of killing things in the file.
		v.take_damage(v.hp, 0, p.id)
		killed += 1
	print("      killed %d of the enemy's %s (had %d, row wants %d)"
			% [killed, "units" if want_units else "buildings", victims.size(), o.value])


## Step until nothing is mid-claim, up to the length of one claim plus the usual grace.
##
## ## WHY THE DRIVER WAITS SIX MINUTES INSTEAD OF SPAWNING A DRAGON
##
## `_spawn_up_to` would satisfy scenario 4's second row in one line, and it would prove
## nothing: the row is *"you own a dragon"*, and handing the player one skips the entire
## feature the scenario exists to teach. What is being checked here is the wiring between a
## `scenario.json` and a running match, and for this scenario the wiring runs **through
## `NestSystem`** -- the hatch, the countdown, the handover. So the claim is played out at
## the real rate, 3600 ticks of it, and the row satisfies itself.
##
## GENERIC RATHER THAN KEYED TO SCENARIO 4. Any scenario whose goal is a thing the world
## hands over on a timer wants this, and the condition is read off the world (*is a claim
## running?*) rather than off a folder name.
##
## BOUNDED, because a driver that cannot finish is worse than one that reports a failure: a
## claim abandoned mid-count (the nest razed, the claimant defeated) clears
## `claim_ticks_left` and this returns immediately, but a bug that left it counting forever
## would otherwise hang the run.
func _settle(w: SimWorld) -> void:
	if not _claim_running(w):
		return
	var limit := NestSystem.GROW_TICKS + GRACE_TICKS
	print("      a claim is running -- stepping up to %d ticks for it to mature" % limit)
	for t in range(limit):
		w.step()
		if w.match_over or not _claim_running(w):
			break
	if _claim_running(w):
		print("      !!! still mid-claim after %d ticks" % limit)


func _claim_running(w: SimWorld) -> bool:
	for e in w.entities.values():
		if e is SimBuilding and (e as SimBuilding).claim_ticks_left >= 0:
			return true
	return false


## Kill everything the opponents own, which is how a `last_man_standing` scenario ends.
func _drive_conquest(w: SimWorld, hero_id: int) -> void:
	for e in w.entities.values():
		if (e is SimUnit or e is SimBuilding) and e.owner_id > 0 \
				and e.owner_id != hero_id:
			e.alive = false
	for t in range(GRACE_TICKS):
		w.step()
		if w.match_over:
			break
	if w.match_over:
		print("    WON by conquest on tick %d, winner_id=%d" % [w.tick, w.winner_id])
	else:
		print("    !!! NOT WON by conquest, which 11.1 says it should be")


func _count_of(w: SimWorld, owner_id: int, def_id: StringName, units: bool) -> int:
	var n := 0
	for e in w.entities.values():
		if not e.alive or e.owner_id != owner_id:
			continue
		if units and not (e is SimUnit):
			continue
		if not units:
			if not (e is SimBuilding) or not (e as SimBuilding).is_complete():
				continue
		if def_id.is_empty() or e.def_id == def_id:
			n += 1
	return n


## A tile with nothing on it, a good way from the middle. Walks outward rather than
## trusting one spot: a generated map has water on it and the town centre is 10x10.
##
## `is_passable(tile, Domain.LAND)` and not `is_walkable`, which does not exist -- the
## first version of this file called it and threw twice per run, which is also the reason
## the driver reported a win anyway: `spawn_unit` with `force` never needed the tile.
func _clear_tile(w: SimWorld) -> Vector2i:
	var size := w.map.size
	for radius in range(4, maxi(size.x, size.y)):
		var t := Vector2i(radius, radius)
		if w.map.in_bounds(t) and w.map.is_passable(t, SimMap.Domain.LAND):
			return t
	return Vector2i(2, 2)


func _state(w: SimWorld, p: SimPlayer) -> String:
	var bits := PackedStringArray()
	bits.append("tick=%d" % w.tick)
	bits.append("over=%s" % w.match_over)
	bits.append("winner=%d" % w.winner_id)
	bits.append("pop=%d/%d" % [p.pop_used, p.pop_cap])
	bits.append("progress=%s" % str(p.objective_progress))
	bits.append("done=%s" % str(Array(p.objective_done)))
	bits.append("defeated=%s" % p.defeated)
	return "  ".join(bits)


func _describe_row(o: ObjectiveDef) -> String:
	var compare := ">="
	match o.compare:
		ObjectiveDef.Compare.AT_MOST:
			compare = "<="
		ObjectiveDef.Compare.EXACTLY:
			compare = "=="
	return "%s '%s' owner=%s %s %d -> %s" % [
		ObjectiveDef.Subject.keys()[o.subject], o.id,
		ObjectiveDef.Owner.keys()[o.owner], compare, o.value,
		ObjectiveDef.Output.keys()[o.output]]
