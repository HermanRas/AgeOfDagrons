## Two PlayTest AIs, one map, no humans — run to a conclusion (PLAN.md 12.2a).
##
## **This is the automated full-match regression test**, and it is the reason the AI
## came before multiplayer. It exercises the economy, placement, training, combat, the
## win condition and the result path in one run, headlessly, with nobody holding two
## phones. If something breaks in the middle of a match, this is what notices.
##
## Lives in `dev_preview/` rather than in the suite because a full match is thousands of
## ticks: at 10 Hz of simulated time it is minutes of game and seconds of wall clock,
## which is too slow to pay on every test run and exactly right to run on demand.
##
## Usage:
##   Godot --headless --path game res://dev_preview/preview_ai_match.tscn
##   ... -- --seed 7 --type forest --ticks 20000
extends Node

## Ceiling on the run. A match that has not resolved by here has stalled, and saying so
## is more useful than waiting: 20,000 ticks is over half an hour of game time.
const DEFAULT_TICKS := 20000
## How often to print a line of the timeline.
const REPORT_EVERY := 1500


func _ready() -> void:
	var p_seed := _int_arg("--seed", 3)
	var ticks := _int_arg("--ticks", DEFAULT_TICKS)
	var type := _type_arg()

	var cfg := MatchConfig.debug_generated(p_seed, type, 2)
	cfg.ai_players = [true, true] as Array[bool]
	var w := SimWorld.new()
	w.setup(cfg)
	MapGen.build(w, cfg)

	print("AI vs AI -- %s %dx%d, seed %d, %s"
			% [MapGenerator.type_name(type), w.map.size.x, w.map.size.y, p_seed,
			MatchConfig.mode_name(cfg.mode)])

	var started := Time.get_ticks_msec()
	var resolved_at := -1
	for i in range(ticks):
		w.step()
		if i % REPORT_EVERY == 0:
			_report_line(w)
		if w.match_over:
			resolved_at = w.tick
			break
	var elapsed := Time.get_ticks_msec() - started

	_report_line(w)
	print("")
	if resolved_at > 0:
		print("MATCH OVER on tick %d (%.1f minutes of game time, %.1f s of wall clock)"
				% [resolved_at, float(resolved_at) / 600.0, float(elapsed) / 1000.0])
		print("  winner: %s" % ("player %d" % w.winner_id if w.winner_id > 0 else "nobody (draw)"))
	else:
		# Not a pass or a fail on its own: two AIs that never find each other on a big
		# map is a real outcome, and the point is that it SAYS so rather than looking
		# like a hang.
		print("UNRESOLVED after %d ticks (%.1f s) -- neither side finished the other"
				% [ticks, float(elapsed) / 1000.0])
	for p in w.players:
		print("  player %d: defeated %s, age %d, stock %s"
				% [p.id, p.defeated, p.age, p.stock])
		_report_buildings(w, p)
	_report_ai_log(w)


## Every building with its PHASE, which is the thing a step count cannot tell you.
##
## Added after a run where both AIs reported "build barracks done" and then failed to
## train anything: `_is_done` for a build step is satisfied by a FOUNDATION existing,
## and `TrainCommand` quite rightly refuses a building that is not finished. A step log
## saying "done" and a barracks that is a hole in the ground look identical from
## outside.
func _report_buildings(w: SimWorld, p: SimPlayer) -> void:
	var parts: Array[String] = []
	var ids := w.entities.keys()
	ids.sort()
	for id in ids:
		var b = w.entities[id]
		if not (b is SimBuilding) or b.owner_id != p.id or not b.alive:
			continue
		var phase := "complete"
		match (b as SimBuilding).phase:
			SimBuilding.Phase.FOUNDATION: phase = "FOUNDATION"
			SimBuilding.Phase.UNDER_CONSTRUCTION: phase = "building %d%%" \
					% int((b as SimBuilding).build_fraction() * 100.0)
			SimBuilding.Phase.DESTROYED: phase = "rubble"
		parts.append("%s (%s)" % [String(b.def_id).trim_prefix("building."), phase])
	print("    ", ", ".join(parts))


func _report_line(w: SimWorld) -> void:
	var ai := _ai(w)
	var parts: Array[String] = []
	for p in w.players:
		var units := 0
		var buildings := 0
		var military := 0
		for e in w.entities.values():
			if not e.alive or e.owner_id != p.id:
				continue
			if e is SimUnit:
				units += 1
				if e.def_id != &"unit.villager":
					military += 1
			elif e is SimBuilding:
				buildings += 1
		parts.append("p%d step %d: %d units (%d mil), %d bldg, pop %d/%d"
				% [p.id, ai.step_of(p.id), units, military, buildings, p.pop_used, p.pop_cap])
	print("  t%-6d %s" % [w.tick, "  |  ".join(parts)])


## The last thing each AI decided. What turns "it stopped" into "it stopped HERE".
func _report_ai_log(w: SimWorld) -> void:
	var ai := _ai(w)
	var lines := ai.log_lines()
	print("")
	print("  AI log (last 24):")
	for line in lines.slice(maxi(0, lines.size() - 24)):
		print("    ", line)


func _ai(w: SimWorld) -> AISystem:
	for s in w._systems:
		if s is AISystem:
			return s
	return null


func _int_arg(name: String, fallback: int) -> int:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == name:
			return int(args[i + 1])
	return fallback


func _type_arg() -> MapGenerator.Type:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] != "--type":
			continue
		match String(args[i + 1]).to_lower():
			"island": return MapGenerator.Type.ISLAND
			"river": return MapGenerator.Type.RIVER
			"desert": return MapGenerator.Type.DESERT
			"forest": return MapGenerator.Type.FOREST
	return MapGenerator.Type.FOREST
