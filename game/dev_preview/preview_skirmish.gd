## Dev check for the skirmish screen (PLAN.md 1.6): photograph the real screen, then
## start a real match from the config it built and photograph THAT.
##
## The second half is the point. A settings screen that looks right and hands the match
## a different map than it previewed is the worst failure available here, and it is
## invisible from either picture alone -- so this prints what the running world actually
## contains and compares it against what the screen was showing.
##
## Instantiates `Game.tscn` directly rather than letting the screen's own START call
## `change_scene_to_file()`, because that would replace THIS scene and take the preview
## with it. The config path -- `Net.pending_match`, consumed by `host_solo()` -- is
## exercised exactly as the button does it; only the scene swap is done by hand.
##
## Usage:
##   Godot --path game res://dev_preview/preview_skirmish.tscn
##       -- writes user://skirmish_screen.png and user://skirmish_match.png.
extends Node

const SHOT_DIR := "user://"
const SETTLE_FRAMES := 30
const MATCH_FRAMES := 45

var _screen: SkirmishScreen = null
var _game: Node = null
var _frames := 0
var _step := 0
var _expected: MapData = null


func _ready() -> void:
	_screen = load("res://scenes/menu/Skirmish.tscn").instantiate()
	add_child(_screen)


func _process(_delta: float) -> void:
	_frames += 1
	match _step:
		0:
			if _frames < SETTLE_FRAMES:
				return
			_report_screen()
			_shoot("skirmish_screen")
		1:
			_start_the_match()
		2:
			if _frames < SETTLE_FRAMES + MATCH_FRAMES:
				return
			_report_match()
			_shoot("skirmish_match")
		_:
			get_tree().quit()
			return
	_step += 1


func _report_screen() -> void:
	var cfg := _screen.build_config()
	var data := _screen.map_data()
	_expected = data
	print("screen: %s %dx%d seed %d, %d players, mode %s, startable %s"
			% [MapGenerator.type_name(data.meta.get("type", 0) as MapGenerator.Type),
			data.size.x, data.size.y, int(cfg.seed), cfg.player_ids.size(),
			MatchConfig.mode_name(cfg.mode), _screen.can_start()])
	print("    status: %s" % _screen.status_text())
	for i in range(cfg.player_ids.size()):
		print("    player %d: colour %d, ai %s"
				% [cfg.player_ids[i], cfg.colours[i], cfg.ai_players[i]])


## Exactly what START does, minus the scene change.
func _start_the_match() -> void:
	Net.pending_match = _screen.build_config()
	_screen.queue_free()
	_screen = null
	_frames = SETTLE_FRAMES          # re-base the frame gate for the match's own settle
	_game = load("res://scenes/game/Game.tscn").instantiate()
	add_child(_game)


## What the match ACTUALLY got, against what the screen was showing.
func _report_match() -> void:
	var host := Net.host()
	if host == null or host.world == null:
		push_warning("preview_skirmish: no host -- the match never started")
		return
	var world: SimWorld = host.world

	var counts: Dictionary = {}
	for e in world.entities.values():
		var key := String(e.def_id)
		counts[key] = int(counts.get(key, 0)) + 1

	print("match:  %dx%d, %d entities, tick %d"
			% [world.map.size.x, world.map.size.y, world.entities.size(), world.tick])
	for p in world.players:
		print("    player %d: colour %d, ai %s, stock %s"
				% [p.id, p.colour, p.is_ai, p.stock])

	# The comparison this preview exists for.
	if _expected != null:
		var same_size := world.map.size == _expected.size
		var same_terrain := true
		for y in range(world.map.size.y):
			for x in range(world.map.size.x):
				var t := Vector2i(x, y)
				if world.map.terrain_at(t) != _expected.terrain_at(t):
					same_terrain = false
					break
			if not same_terrain:
				break
		print("    matches the preview: size %s, terrain %s" % [same_size, same_terrain])

	var keys := counts.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s x%d" % [k, counts[k]])
	print("    ", ", ".join(parts))
	print("    pending_match cleared: %s" % (Net.pending_match == null))


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
