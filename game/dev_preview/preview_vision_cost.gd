## What team vision costs, per team layout (PLAN.md 12.x, card `12.x-shared-vision`).
##
## THE MEASUREMENT THE CARD DEMANDS BEFORE THE ONE-LINE CHANGE LANDS. Shared vision is
## `Diplomacy.allied(e.owner_id, p.id, w.teams)` in place of `e.owner_id == p.id` in
## `VisionSystem._recompute`, and `_reveal` is the hottest loop in the sim -- so the
## question is not whether it works but what it costs a 4v4 on the biggest board.
##
## **THE EXISTING `test_tick_cost` CANNOT ANSWER IT, FOR TWO SEPARATE REASONS**, both
## found while trying to use it and both worth writing down:
##
##   `MatchConfig.debug_generated()` NEVER SETS `teams`, and an absent entry means team 0,
##     which means no team at all (see `MatchConfig.teams`). Every world that factory
##     builds is a free-for-all, so shared vision changes its cost by exactly nothing.
##     A baseline taken there would have "proved" the change is free.
##
##   AND ITS PER-SYSTEM TABLE CANNOT SEE `VisionSystem` AT ALL. `_per_system_ms` calls
##     `process_tick` repeatedly WITHOUT stepping, so `w.tick` is whatever the last step
##     left -- 5 settling + 20 sampled = **25, odd** -- and `VISION_INTERVAL := 2` makes
##     `due` false, so `_recompute` returns immediately and the row reads ~0.00 ms and is
##     dropped by the 0.05 cutoff. The `17.9 ms` in `VisionSystem`'s own header predates
##     the interval and no longer describes anything that test measures.
##
## So this harness forces an EVEN tick before timing vision, and reports what one
## recompute of every player costs.
##
## ── THE COLUMN THAT MATTERS IS `lit`, NOT THE MILLISECONDS ──
##
## `lit` is the total number of tile-writes one recompute of all players performs: the sum
## over players of the indices `_reveal` marks. It is **deterministic** -- same seed, same
## number, every run, on any machine -- and it is very nearly the whole cost of the system,
## since both the marking and the incremental decay are O(lit).
##
## That matters because this repo has measured, twice, that wall-clock here is not
## evidence: `test_tick_cost` reported 49.81 ms on a loaded workstation and passed
## comfortably on the same commit forty minutes later, and one seeded run took 41.3 s and
## then 161.0 s. **A ratio of `lit` between two team layouts is a fact; a ratio of ms is a
## rumour.** The ms columns are kept because the budget in PLAN.md 3.1 is in ms, and are
## reported as MIN over the reps rather than as a mean -- noise only ever adds, so the
## smallest reading is the closest to the truth.
##
## Run it BEFORE and AFTER the change and compare. Before the change every layout must
## report the same `lit` (teams do not enter vision yet); that identity is the harness
## proving itself, and if the rows differ before the change then this file is wrong rather
## than the code.
##
## Usage:
##   Godot --headless --path game res://dev_preview/preview_vision_cost.tscn
##       [-- --reps 3] [--seed 3] [--slots 8] [--ticks 20]
extends Node

## Team layouts on an 8-slot board, worst case last.
##
## `[]` IS THE CONTROL, and it is the shape every test fixture and every recorded config
## in the repo already has -- so it is also the row that must not move when the change
## lands. 4v4 is the realistic worst case a lobby can produce; all-eight-on-one-team is
## not a match anybody would play, and is here as the ceiling: it is the layout where
## every player lights every entity on the board.
const LAYOUTS := [
	{"name": "FFA (no teams)", "teams": []},
	{"name": "2v2v2v2", "teams": [1, 1, 2, 2, 3, 3, 4, 4]},
	{"name": "4v4", "teams": [1, 1, 1, 1, 2, 2, 2, 2]},
	{"name": "8 on one team", "teams": [1, 1, 1, 1, 1, 1, 1, 1]},
]

## Settling steps before measuring, so first-tick work (the fog's initial full sweep, the
## first path solves) is not charged to the steady state. `test_tick_cost` uses 5 and its
## reason applies unchanged. EVEN, so the world is left on a recompute tick.
const SETTLE := 6


func _ready() -> void:
	var p_seed := _int_arg("--seed", 3)
	var slots := _int_arg("--slots", 8)
	var reps := _int_arg("--reps", 3)
	var ticks := _int_arg("--ticks", 20)
	var with_ai := OS.get_cmdline_user_args().has("--ai")

	print("VISION COST BY TEAM LAYOUT — %d players on an %d-slot board, seed %d" % [
			slots, slots, p_seed])
	var ai_label := "ON" if with_ai else "off"
	print("AI %s, %d settling ticks, %d sampled ticks, %d reps (ms are MIN of reps)" % [
			ai_label, SETTLE, ticks, reps])
	print("")
	print("`lit` is deterministic and is the real answer; ms on this desktop are not.")
	print("")
	print("  layout            entities        lit    lit/player   vision ms   tick ms")

	var baseline := 0
	for layout in LAYOUTS:
		var row := _measure(p_seed, slots, layout["teams"], reps, ticks, with_ai)
		if baseline == 0:
			baseline = int(row["lit"])
		var factor := ""
		if baseline > 0:
			factor = "  (%.2fx FFA)" % (float(row["lit"]) / float(baseline))
		print("  %-16s  %8d  %9d  %12d  %9.2f  %8.2f%s" % [
				layout["name"], int(row["entities"]), int(row["lit"]),
				int(row["lit"]) / maxi(1, slots), float(row["vision_ms"]),
				float(row["tick_ms"]), factor])

	print("")
	print("PLAN.md 3.1's budget is 5 ms per 100 ms tick, CHECKED ON DEVICE via")
	print("StressTest.tscn -- not here. This harness compares layouts; it does not")
	print("decide whether the budget is met.")

	# A headless scene does NOT end when _ready() returns -- the tree keeps running with
	# nothing to do, and the harness reads as a hang after it has already printed its
	# answer. Every other preview here that is a one-shot report quits explicitly.
	get_tree().quit()


func _measure(p_seed: int, slots: int, teams: Array, reps: int, ticks: int,
		with_ai: bool) -> Dictionary:
	var lit := 0
	var entities := 0
	var vision_ms := INF
	var tick_ms := INF

	for r in range(maxi(1, reps)):
		var w := _world(p_seed, slots, teams, with_ai)
		entities = w.entities.size()
		lit = _lit_total(w)

		# The whole tick, stepped normally -- the only honest way to read a system that
		# runs on an interval, since half these steps recompute vision and half do not.
		var started := Time.get_ticks_usec()
		for i in range(ticks):
			w.step()
		tick_ms = minf(tick_ms, float(Time.get_ticks_usec() - started)
				/ float(ticks) / 1000.0)

		vision_ms = minf(vision_ms, _vision_ms(w, ticks))

	return {"entities": entities, "lit": lit, "vision_ms": vision_ms, "tick_ms": tick_ms}


func _world(p_seed: int, slots: int, teams: Array, with_ai: bool) -> SimWorld:
	var cfg := MatchConfig.new()
	cfg.player_ids = []
	cfg.ai_players = []
	cfg.teams = []
	for i in range(slots):
		cfg.player_ids.append(i + 1)
		cfg.ai_players.append(with_ai)
		cfg.teams.append(int(teams[i]) if i < teams.size() else 0)

	cfg.seed = p_seed
	cfg.map_type = MapGenerator.Type.FOREST
	cfg.map_data = MapGenerator.generate(p_seed, cfg.map_type, slots, slots)
	cfg.map_size = cfg.map_data.size

	var w := SimWorld.new()
	w.setup(cfg)
	MapGen.build(w, cfg)
	for i in range(SETTLE):
		w.step()
	return w


## Tile-writes one recompute of every player performs, read off `VisionSystem`'s own
## incremental-decay cache -- which holds exactly the indices the last recompute lit.
##
## Reaches into `_systems` and into `_visible_last` deliberately, the way
## `test_tick_cost._per_system_ms` already reaches into `_systems`: the alternative is a
## public accessor on a sim system existing only for a benchmark. Returns -1 rather than 0
## if the system or the cache is missing, so a harness that has stopped measuring anything
## says so instead of reporting a free lunch.
func _lit_total(w: SimWorld) -> int:
	var vs: SimSystem = _vision_system(w)
	if vs == null:
		return -1
	var cache: Dictionary = vs._visible_last
	if cache.is_empty():
		return -1
	var total := 0
	for p in w.players:
		if not cache.has(p.id):
			return -1
		var lit: PackedInt32Array = cache[p.id]
		total += lit.size()
	return total


## One recompute of all players, in isolation.
##
## FORCES AN EVEN TICK, which is the whole reason this is not `test_tick_cost`'s helper:
## `process_tick` on an odd tick returns without doing anything (see the header). The tick
## is restored afterwards, because `w.tick` is in `state_hash()` and a benchmark has no
## business leaving the world it measured in a state a later step would disagree about.
func _vision_ms(w: SimWorld, samples: int) -> float:
	var vs: SimSystem = _vision_system(w)
	if vs == null:
		return -1.0
	var was := w.tick
	w.tick = was - (was % VisionSystem.VISION_INTERVAL)
	var started := Time.get_ticks_usec()
	for i in range(samples):
		vs.process_tick(w)
	var ms := float(Time.get_ticks_usec() - started) / float(samples) / 1000.0
	w.tick = was
	return ms


func _vision_system(w: SimWorld) -> SimSystem:
	for s in w._systems:
		if s is VisionSystem:
			return s
	return null


func _int_arg(name: String, fallback: int) -> int:
	var args := OS.get_cmdline_user_args()
	var at := args.find(name)
	if at >= 0 and at + 1 < args.size():
		return int(args[at + 1])
	return fallback
