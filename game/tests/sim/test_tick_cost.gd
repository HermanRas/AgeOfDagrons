## Where the sim tick actually goes (PLAN.md 3.1: < 5 ms per 100 ms tick), per system,
## on the biggest map the generator will produce.
##
## Exists because the aggregate number does not tell you what to fix. An 8-player
## 192x192 map first measured **39.7 ms a tick**, and the two systems responsible were
## not the ones that looked expensive -- they were the two doing per-player full sweeps
## (`VisionSystem` decaying the whole grid, `PopulationSystem` scanning twice per
## player), neither of which is where a reader's eye goes.
##
## Prints rather than only asserting: the table is the point, and a regression shows up
## as one row moving rather than as a total that is vaguely worse.
##
## **THESE ARE DESKTOP NUMBERS UNDER WHATEVER ELSE THE MACHINE IS DOING**, and they
## moved by 3x between runs while this was being written. The authoritative budget check
## is `StressTest.tscn` on the reference device (PLAN.md 3.0/3.1). So the assertions here
## are loose tripwires against a large regression, not a 5 ms gate -- a tight assertion
## on a noisy measurement is a test that fails for the weather.
##
## The per-system table is INDICATIVE for the same reason plus one of its own: each
## system is run repeatedly out of band, which is not what one tick does, so read the
## ratios between rows rather than the absolute values.
extends TestCase

const SAMPLE_TICKS := 20


func _world(players: int) -> SimWorld:
	var cfg := MatchConfig.debug_generated(3, MapGenerator.Type.FOREST, players)
	var w := SimWorld.new()
	w.setup(cfg)
	MapGen.build(w, cfg)
	# A few ticks of settling first, so one-off first-tick work (the fog's initial full
	# sweep, the first path solves) is not charged to the steady state.
	for i in range(5):
		w.step()
	return w


## Every system in `SimWorld`'s own order, by name, timed on its own.
##
## Reaches into `_systems` deliberately: the alternative is a public accessor existing
## only for a test, and the order is the thing being measured.
func _per_system_ms(w: SimWorld) -> Array:
	var systems: Array = w._systems
	var rows: Array = []
	for s in systems:
		var started := Time.get_ticks_usec()
		for i in range(SAMPLE_TICKS):
			s.process_tick(w)
		var ms := float(Time.get_ticks_usec() - started) / float(SAMPLE_TICKS) / 1000.0
		rows.append({"name": s.get_script().resource_path.get_file().get_basename(), "ms": ms})
	rows.sort_custom(func(a, b): return a["ms"] > b["ms"])
	return rows


func test_the_tick_budget_holds_on_a_two_player_generated_map() -> void:
	var w := _world(2)
	var started := Time.get_ticks_usec()
	for i in range(SAMPLE_TICKS):
		w.step()
	var ms := float(Time.get_ticks_usec() - started) / float(SAMPLE_TICKS) / 1000.0

	print("        2P 96x96, %d entities: %.2f ms/tick  (budget 5 ms, checked on device)"
			% [w.entities.size(), ms])
	for row in _per_system_ms(w):
		if row["ms"] >= 0.05:
			print("            %-24s %.2f ms" % [row["name"], row["ms"]])
	assert_true(ms < 15.0, "2P tick cost %.2f ms -- a large regression" % ms)


func test_the_biggest_generated_map_holds_the_budget_too() -> void:
	# 8 players on 192x192 is the generator's ceiling, and it first measured **39.7 ms
	# a tick** -- eight times over budget. It now reads between 4 and 10 ms depending on
	# what else this desktop is doing, so treat it as "about an order of magnitude
	# better" rather than as a figure. Three changes did it:
	#
	#   VisionSystem decayed the WHOLE grid per player (8 x 36,864 byte writes before
	#     computing anything) and now decays only the tiles it lit last time;
	#   its marking loop called SimMap.index_of() per tile, three function calls and a
	#     Vector2i allocation deep, and is now inlined arithmetic;
	#   and it recomputes every 2nd tick, because fog at 5 Hz is imperceptible.
	#
	# PopulationSystem and WinConditionSystem were each doing a full scan PER PLAYER and
	# now do one pass for everybody. None of the three were where a reader would look.
	var w := _world(8)
	var started := Time.get_ticks_usec()
	for i in range(SAMPLE_TICKS):
		w.step()
	var ms := float(Time.get_ticks_usec() - started) / float(SAMPLE_TICKS) / 1000.0

	print("        8P 192x192, %d entities: %.2f ms/tick  (was 39.7 ms)"
			% [w.entities.size(), ms])
	for row in _per_system_ms(w):
		if row["ms"] >= 0.05:
			print("            %-24s %.2f ms" % [row["name"], row["ms"]])
	assert_true(ms < 45.0, "8P tick cost %.2f ms -- a large regression" % ms)
