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
## How often to check for foundations nobody is raising (see `_report_stuck_foundations`).
const STUCK_EVERY := 300


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
			_report_armies(w)
		# Finer than the timeline: a foundation can be placed and destroyed well
		# inside one 1,500-tick reporting gap, which is how the barracks slipped
		# through the first run entirely.
		if i % STUCK_EVERY == 0:
			_report_stuck_foundations(w)
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
	# WITHOUT THIS THE RUN NEVER ENDS. `_ready` returning just hands control back to a
	# headless main loop with nothing to do, which Godot then spins at max FPS forever:
	# the report is printed at ~40 s and the process was still burning a core minutes
	# later. A scene whose whole purpose is to run once and report has to quit itself.
	get_tree().quit()


## Both armies and what they are actually doing, plus what is left of each side.
##
## A STANDOFF LOOKS IDENTICAL TO A GRIND from the timeline: seed 6 sat at
## "p1 13 units (6 mil) vs p2 7 units, 1 bldg" for 24,000 ticks without one number
## moving, and the unit counts alone cannot say whether blows are landing slowly or
## not at all. Task and target can: a soldier reading IDLE with no target has
## nothing to walk to, and one reading ATTACK on the same target for thousands of
## ticks is swinging at something it cannot reach.
func _report_armies(w: SimWorld) -> void:
	var ids := w.entities.keys()
	ids.sort()
	for p in w.players:
		var army: Array[String] = []
		var left: Array[String] = []
		for id in ids:
			var e = w.entities[id]
			if not e.alive or e.owner_id != p.id:
				continue
			if e is SimUnit and e.def_id != &"unit.villager":
				army.append("#%d %v task %d->%d" % [id, e.tile(), e.task, e.task_target_id])
			elif e is SimBuilding:
				left.append("%s %v" % [String(e.def_id).trim_prefix("building."), e.tile()])
		if not army.is_empty():
			print("    ARMY p%d: %s" % [p.id, ", ".join(army)])
			_report_reach(w, p, ids)
		print("    HOLDS p%d: %s" % [p.id, ", ".join(left) if not left.is_empty() else "nothing"])


## Can this player's army actually GET to the enemy things it might be sent at?
##
## `AISystem._nearest_enemy` prefers a building over a unit unconditionally, so an
## enemy building nothing can walk to is worth checking against the units standing
## behind it.
func _report_reach(w: SimWorld, p: SimPlayer, ids: Array) -> void:
	var from := Vector2i(-1, -1)
	for id in ids:
		var u = w.entities[id]
		if u is SimUnit and u.alive and u.owner_id == p.id and u.def_id != &"unit.villager":
			from = (u as SimUnit).tile()
			break
	if from.x < 0 or w.paths == null:
		return
	for id in ids:
		var e = w.entities[id]
		if not e.alive or e.owner_id == 0 or e.owner_id == p.id:
			continue
		if not (e is SimUnit or e is SimBuilding):
			continue
		var route := w.paths.find_path(w.map, from, e.tile())
		print("      reach p%d %s at %v: %s" % [p.id,
				String(e.def_id).trim_prefix("building.").trim_prefix("unit."), e.tile(),
				"NO ROUTE" if route.is_empty() else "%d steps" % route.size()])


## Foundations taking no progress, and the three facts that tell WHY.
##
## The question the first 12.2a run could not answer: p1 placed a barracks, a
## builder rode the placement command, and 1,310 ticks later it stood at 0% -- so
## the train step had nothing to train at and the AI never fielded an army.
##
## Three candidates, and one line separates them:
##
##   builders 0        nobody was ever tasked to it -- the standing order is not
##                     reaching it (it only ever picks the LOWEST-id unfinished
##                     building, so one stuck site starves every newer one)
##   route none        the ring scan found a legal spot nothing can walk to;
##                     `can_place_building` asks whether the tiles are free, never
##                     whether a villager can get there
##   route ends gap>1  a route exists but stops short, and `BuildSystem` retires a
##                     builder that arrives non-adjacent -- so it walks over, gives
##                     up, goes idle, and is sent again forever
func _report_stuck_foundations(w: SimWorld) -> void:
	for id in w.entities.keys():
		var e = w.entities[id]
		if not (e is SimBuilding):
			continue
		var b := e as SimBuilding
		if not b.alive or b.is_complete() or b.build_fraction() > 0.0:
			continue

		var builders := 0
		for u in w.entities.values():
			if u is SimUnit and u.alive and u.task == SimUnit.Task.BUILD \
					and u.task_target_id == b.id:
				builders += 1

		# Probed from a real villager of the owner, not from an arbitrary tile: the
		# question is whether the people who must build it can get to it.
		var from := Vector2i(-1, -1)
		for u in w.entities.values():
			if u is SimUnit and u.alive and u.owner_id == b.owner_id \
					and u.def_id == &"unit.villager":
				from = (u as SimUnit).tile()
				break

		var route := "no villager to probe from"
		if from.x >= 0 and w.paths != null:
			var path := w.paths.find_path(w.map, from, b.tile())
			if path.is_empty():
				route = "NO ROUTE from %v" % from
			else:
				var ends := Vector2i(path[path.size() - 1])
				route = "route from %v ends %v, gap %d" % [from, ends,
						_gap_to(ends, b.footprint_rect())]

		print("    STUCK  p%d %s at %v, %d builder(s), %s"
				% [b.owner_id, String(b.def_id).trim_prefix("building."),
				b.origin_tile(), builders, route])


## Chebyshev gap in tiles from a tile to a rect: 1 means "standing against it",
## which is what BuildSystem requires of a builder before it will add progress.
static func _gap_to(from: Vector2i, rect: Rect2i) -> int:
	var cx := clampi(from.x, rect.position.x, rect.end.x - 1)
	var cy := clampi(from.y, rect.position.y, rect.end.y - 1)
	return maxi(absi(from.x - cx), absi(from.y - cy))


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
		parts.append("p%d %d acts: %d units (%d mil), %d bldg, pop %d/%d"
				% [p.id, ai.decisions_of(p.id), units, military, buildings,
				p.pop_used, p.pop_cap])
	print("  t%-6d %s" % [w.tick, "  |  ".join(parts)])


## The last thing each AI decided. What turns "it stopped" into "it stopped HERE".
func _report_ai_log(w: SimWorld) -> void:
	var ai := _ai(w)
	var lines := ai.log_lines()
	print("")
	print("  AI log (last 40):")
	for line in lines.slice(maxi(0, lines.size() - 40)):
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
