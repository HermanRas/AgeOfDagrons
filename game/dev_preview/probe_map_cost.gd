## How much a SAVED map costs to build and to tick, and which entities are paying for it.
##
## ## ⛔ WHY A SEPARATE PROBE AND NOT `test_tick_cost`
##
## `test_tick_cost` asks whether a SYNTHETIC world of N units ticks fast enough. It cannot see a
## cost that arrives with a MAP -- the owner's cliff fix multiplied the entities on a plateau by
## three and the suite stayed green, because the suite never loads a hand-drawn map. This loads
## the real file and reports where the milliseconds go.
##
##     godot --headless --path game res://dev_preview/probe_map_cost.tscn -- platotest3
##
## ⚠️ **IT REPORTS A DIFFERENCE, NOT A NUMBER.** Wall-clock on a workstation the owner is using
## is noise; what survives is "the same map without its blockers ticks X% faster", because both
## halves ran on the same machine in the same second. Build cost is measured the same way.
extends Node

const DEFAULT_MAP := "platotest3"

## Enough ticks to swamp the one-off cost of the first step without making the probe a wait.
const TICKS := 300


func _ready() -> void:
	var name := DEFAULT_MAP
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		name = args[0]

	var data := _load(name)
	if data == null:
		print("  ! no map called '%s'" % name)
		get_tree().quit(1)
		return

	print("\n=== %s: %dx%d, %d entities ===" % [name, data.size.x, data.size.y,
			data.entities.size()])
	_report_counts(data)

	var full := _time(data, "as saved")
	var stripped := _time(_without(data, CliffPlan.BLOCKER), "without the cliff blockers")

	print("\n  build   %7.1f ms -> %7.1f ms   (%+.0f%%)" % [full["build"], stripped["build"],
			_delta(full["build"], stripped["build"])])
	print("  %d ticks %6.1f ms -> %7.1f ms   (%+.0f%%)" % [TICKS, full["tick"], stripped["tick"],
			_delta(full["tick"], stripped["tick"])])
	print("  per tick %6.3f ms -> %7.3f ms" % [full["tick"] / TICKS, stripped["tick"] / TICKS])
	_by_system(data)
	get_tree().quit(0)


## WHICH SYSTEM IS PAYING. A total says the map is slow; this says what to change.
func _by_system(data: MapData) -> void:
	var cfg := MatchConfig.debug_skirmish()
	cfg.map_size = data.size
	cfg.map_data = data
	var w := SimWorld.new()
	w.setup(cfg)
	MapGen.build(w, cfg)

	var cost: Dictionary = {}
	for i in range(TICKS):
		w.tick += 1
		w.removed_this_tick.clear()
		for s in w._systems:
			var t0 := Time.get_ticks_usec()
			s.process_tick(w)
			var key: String = str((s as Object).get_script().resource_path.get_file())
			cost[key] = float(cost.get(key, 0.0)) + (Time.get_ticks_usec() - t0) / 1000.0

	var keys := cost.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return float(cost[a]) > float(cost[b]))
	print("\n  per tick, by system:")
	for k in keys:
		var ms: float = float(cost[k]) / TICKS
		if ms >= 0.05:
			print("    %-34s %6.3f ms" % [k, ms])


## Build the world and step it, reporting both halves in milliseconds.
func _time(data: MapData, label: String) -> Dictionary:
	var cfg := MatchConfig.debug_skirmish()
	cfg.map_size = data.size
	cfg.map_data = data
	var w := SimWorld.new()

	var t0 := Time.get_ticks_usec()
	w.setup(cfg)
	MapGen.build(w, cfg)
	var t1 := Time.get_ticks_usec()
	for i in range(TICKS):
		w.step()
	var t2 := Time.get_ticks_usec()

	var out := {"build": (t1 - t0) / 1000.0, "tick": (t2 - t1) / 1000.0}
	print("  %-32s build %7.1f ms, %d ticks %7.1f ms" % [label, out["build"], TICKS, out["tick"]])
	return out


func _delta(from: float, to: float) -> float:
	return 0.0 if from <= 0.0 else (to - from) / from * 100.0


## The same map with every entity of one def taken out. A COPY -- the caller times the original
## afterwards and a shared entity list would make the second run measure the first one's edits.
func _without(data: MapData, def_id: StringName) -> MapData:
	var out := MapData.create(data.size)
	out.terrain = data.terrain.duplicate()
	out.starts = data.starts.duplicate()
	out.meta = data.meta.duplicate(true)
	for e in data.entities:
		if e.get("def_id", &"") != def_id:
			out.entities.append((e as Dictionary).duplicate(true))
	return out


func _report_counts(data: MapData) -> void:
	var by_def: Dictionary = {}
	for e in data.entities:
		var id: StringName = e.get("def_id", &"")
		by_def[id] = int(by_def.get(id, 0)) + 1
	var keys := by_def.keys()
	keys.sort_custom(func(a: StringName, b: StringName) -> bool:
		return int(by_def[a]) > int(by_def[b]))
	for k in keys:
		if int(by_def[k]) >= 10:
			print("  %-34s %4d" % [k, by_def[k]])


func _load(name: String) -> MapData:
	var repo := ProjectSettings.globalize_path("res://").path_join("../maps/").simplify_path()
	for root in [repo, "user://maps/"]:
		var dir: String = root.path_join(name)
		if not MapFile.exists_in(dir):
			continue
		var problems: Array[String] = []
		var loaded := MapFile.load_map(dir, problems)
		for p in problems:
			print("  ? %s" % p)
		if loaded != null:
			return loaded
	return null
