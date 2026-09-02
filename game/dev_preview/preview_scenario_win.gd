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
