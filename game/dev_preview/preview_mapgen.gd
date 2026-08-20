## Dev check for the map generator (PLAN.md 2.4b): generate one map of each type and
## write it out as a PNG, one pixel per tile, so the layouts can be judged by eye.
##
## The same picture the `game_map_gen/` prototype's `ShowMap` produced, deliberately —
## it is the view the project owner designed the generator against, so keeping the
## output comparable is the point. **The palette is not the map format**, though: since
## 11.2 fix 2 the entity list is data and these pixels are a rendering of it, so a
## town centre and a villager can finally be different colours instead of both being
## `ff0000` with a blob-size guess between them.
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
## rather than a thumbnail.
const SCALE := 3

const C_GRASS := Color("4caf50")
const C_SAND := Color("fff8e7")
const C_WATER := Color("0288d1")
const C_DEEP := Color("01579b")
const C_ROCK := Color("6d4c41")
const C_TREE := Color("1b5e20")
const C_GOLD := Color("ffd700")
const C_STONE := Color("9e9e9e")
const C_FOOD := Color("e91e63")
const C_TOWN := Color("d50000")
const C_UNIT := Color("ffffff")
const C_START := Color("00e5ff")


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
	var img := Image.create(data.size.x * SCALE, data.size.y * SCALE, false, Image.FORMAT_RGBA8)

	for y in range(data.size.y):
		for x in range(data.size.x):
			_blot(img, Vector2i(x, y), _terrain_colour(data.terrain_at(Vector2i(x, y))))

	# Entities over the ground, in list order, so a base drawn after its clearing wins.
	for e in data.entities:
		var colour := _entity_colour(e["def_id"])
		for t in MapData.footprint_rect_of(e):
			_blot(img, t, colour)

	# Start markers last: a ring the eye can find, since a town centre is only 10 px
	# across at this scale and there is no other way to see WHERE a player begins.
	for s in data.starts:
		for d in range(6, 9):
			for a in range(0, 360, 12):
				var t := s + Vector2i(Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a))) * float(d))
				_blot(img, t, C_START)

	var path := SHOT_DIR + name + ".png"
	img.save_png(path)
	print("    wrote ", ProjectSettings.globalize_path(path))


func _blot(img: Image, tile: Vector2i, colour: Color) -> void:
	for dy in range(SCALE):
		for dx in range(SCALE):
			var px := tile.x * SCALE + dx
			var py := tile.y * SCALE + dy
			if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
				img.set_pixel(px, py, colour)


func _terrain_colour(kind: int) -> Color:
	match kind:
		SimMap.Terrain.SAND: return C_SAND
		SimMap.Terrain.WATER_SHALLOW: return C_WATER
		SimMap.Terrain.WATER_DEEP: return C_DEEP
		SimMap.Terrain.ROCK: return C_ROCK
		SimMap.Terrain.DIRT: return C_SAND.darkened(0.25)
		_: return C_GRASS


func _entity_colour(def_id: StringName) -> Color:
	match def_id:
		&"res.tree": return C_TREE
		&"res.gold_mine": return C_GOLD
		&"res.stone": return C_STONE
		&"res.berry_bush": return C_FOOD
		&"building.town_center": return C_TOWN
		_: return C_UNIT
