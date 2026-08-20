## Dev check for the map generator (PLAN.md 2.4b): generate one map of each type and
## write it out as a PNG, one pixel per tile, so the layouts can be judged by eye.
##
## The same picture the `game_map_gen/` prototype's `ShowMap` produced, deliberately —
## it is the view the project owner designed the generator against, so keeping the
## output comparable is the point.
##
## Drawn by `MapPreview`, which is the same renderer the skirmish screen (1.6) shows
## in its panel. Two pictures of one map that could disagree about what it contains is
## how a preview stops being worth trusting.
##
## Prints what the picture cannot say — entity counts, wire size, which attempt passed
## validation, and any problems left — because a map that looks fine and has no gold
## within reach looks exactly like one that does.
##
## Usage:
##   Godot --path game res://dev_preview/preview_mapgen.tscn
##       -- writes user://mapgen_*.png and quits.
##   ... -- --seed 42        -- generate from a specific seed instead of 1.
extends Node

const SHOT_DIR := "user://"
## Each tile drawn this many pixels square, so a 96x96 map is a legible 288x288
## rather than a thumbnail. On screen the TextureRect scales instead.
const SCALE := 3


func _ready() -> void:
	var user_seed := _seed_argument()
	var jobs := [
		[MapGenerator.Type.ISLAND, 2], [MapGenerator.Type.RIVER, 2],
		[MapGenerator.Type.DESERT, 2], [MapGenerator.Type.FOREST, 2],
		[MapGenerator.Type.FOREST, 4], [MapGenerator.Type.ISLAND, 8],
	]
	for job in jobs:
		var type: MapGenerator.Type = job[0]
		var players: int = job[1]
		var started := Time.get_ticks_msec()
		var data := MapGenerator.generate(user_seed, type, players)
		var elapsed := Time.get_ticks_msec() - started
		_report(data, type, players, elapsed)
		_shoot(data, "mapgen_%s_%dp" % [MapGenerator.type_name(type).to_lower(), players])
	get_tree().quit()


func _seed_argument() -> int:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--seed":
			return int(args[i + 1])
	return 1


func _report(data: MapData, type: MapGenerator.Type, players: int, ms: int) -> void:
	var counts: Dictionary = {}
	for e in data.entities:
		var key := String(e["def_id"])
		counts[key] = int(counts.get(key, 0)) + 1
	var problems: Array = data.meta.get("problems", [])

	print("%s %dp  %dx%d  %d entities  wire %d B  attempt %d  %d ms"
			% [MapGenerator.type_name(type), players, data.size.x, data.size.y,
			data.entities.size(), var_to_bytes(data.to_dict()).size(),
			int(data.meta.get("attempt", 0)) + 1, ms])
	var keys := counts.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s x%d" % [k, counts[k]])
	print("    ", ", ".join(parts))
	if problems.is_empty():
		print("    validation OK")
	else:
		print("    PROBLEMS: ", problems)


func _shoot(data: MapData, name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	MapPreview.render(data, SCALE).get_image().save_png(path)
	print("    wrote ", ProjectSettings.globalize_path(path))
