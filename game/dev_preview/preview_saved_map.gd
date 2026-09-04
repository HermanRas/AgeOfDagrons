## Dev check for PLAN.md 16.0: pick a SAVED map in the skirmish picker and play it.
##
## ## WHY THIS EXISTS AND WHAT ONLY IT CAN SEE
##
## 16.0's whole justification is that *"does the tool's output work?"* should be answerable
## by pressing PLAY rather than by hand-writing a `scenario.json`. This is the thing that
## presses PLAY. The headless suite proves the seat arithmetic and the discovery rules; what
## it cannot prove is that a map read off disk **reaches the running world**, which is the
## one failure that would make the whole feature a lie while every test stayed green.
##
## So the load-bearing half is the last step: it starts a real match from the config the
## screen built and compares the world's town centres against the tiles the FILE named. A
## screen that previewed the saved map and handed the match a generated one would look
## perfect in both screenshots.
##
## ## IT AUTHORS THE SAMPLE MAP IT NEEDS, AND THAT OUTPUT IS COMMITTED
##
## `preview_author_maps`' arrangement, for its reason: a picker with nothing in it cannot be
## shown to work, and repo-root `maps/` is empty until the MapMaker exists. So this writes
## one two-player map there if it is missing, and **refuses to overwrite** — the file is
## authored content under version control and a silent re-roll would replace a map somebody
## may have balanced something against. `--force` is a deliberate re-roll.
##
## ⚠️ **THE SAMPLE IS A PLACEHOLDER AND 16.10 IS WHAT REPLACES IT.** It is generated, not
## authored, so it looks like every other River map; its job is to be a real file in the
## real directory so the picker, the seat gate and the match path have something to be
## tested against.
##
## ## IT ALSO PLAYS A MAP SOMEBODY ELSE AUTHORED — `--folder` (added 2026-09-04, 16.2)
##
## With `--folder <name>` it skips the authoring above entirely and drives the picker to that
## folder in `maps/` instead. **That is how the MapMaker's output gets played**, and it is the
## second half of a check no single process can make:
##
##     Godot --headless --path MapMaker res://dev/author_map.tscn
##     Godot --path game res://dev_preview/preview_saved_map.tscn -- --folder river_demo
##
## Two projects, one file between them, which is PLAN.md §16 decision 2 in one command each.
## The seat-gate step is skipped for a foreign map, because its seat count is whatever its
## author chose and this preview has no business asserting a number it did not pick.
##
## Usage:
##   Godot --path game res://dev_preview/preview_saved_map.tscn [-- --force]
##       [-- --folder <name>]
##       -- writes user://saved_map_picked.png and user://saved_map_match.png
extends Node

const SHOT_DIR := "user://"
const SETTLE_FRAMES := 30
const UI_FRAMES := 10
const MATCH_FRAMES := 45

## The sample map's folder in repo-root `maps/`, and the name that appears in the picker.
const SAMPLE_FOLDER := "sample_duel"
const SAMPLE_NAME := "Sample Duel"

## Two players, because the seat gate is only interesting when a lobby can exceed it.
const SAMPLE_PLAYERS := 2
const SAMPLE_SEED := 424242
const SAMPLE_TYPE := MapGenerator.Type.RIVER

var _screen: SkirmishScreen = null
var _game: Node = null
var _frames := 0
var _step := 0
var _resume_at := 0

## What the FILE says, kept to compare the running world against. Read back off disk rather
## than remembered from the generator, so a save that silently lost something is caught
## here instead of agreeing with itself.
var _from_file: MapData = null

## Which folder in `maps/` is under test. The sample by default; anything else came from
## `--folder` and was authored elsewhere.
var _folder := SAMPLE_FOLDER


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_folder = _arg(args, "--folder", SAMPLE_FOLDER)
	# A FOREIGN MAP IS NEVER AUTHORED HERE. `--folder` names somebody else's file -- the
	# MapMaker's, usually -- so this scene must not create, replace or re-roll it. It only
	# reads it back to compare the running world against.
	if _folder == SAMPLE_FOLDER:
		if not _ensure_sample(args.has("--force")):
			get_tree().quit(1)
			return
	elif not _load_foreign():
		get_tree().quit(1)
		return
	_screen = load("res://scenes/menu/Skirmish.tscn").instantiate()
	add_child(_screen)


## Read a map this preview did not write, so `_report_match` has something to compare against.
func _load_foreign() -> bool:
	var dir := ProjectSettings.globalize_path("res://").path_join("../maps").simplify_path() \
			.path_join(_folder)
	var problems: Array[String] = []
	_from_file = MapFile.load_map(dir, problems)
	if _from_file == null:
		push_error("cannot read maps/%s: %s"
				% [_folder, "; ".join(PackedStringArray(problems))])
		return false
	print("foreign map: %s" % dir)
	print("foreign map: %dx%d, %d entities, %d starts"
			% [_from_file.size.x, _from_file.size.y, _from_file.entities.size(),
			_from_file.starts.size()])
	return true


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var at := Array(args).find(key)
	return str(args[at + 1]) if at >= 0 and at + 1 < args.size() else fallback


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < _resume_at:
		return
	match _step:
		0:
			if _frames < SETTLE_FRAMES:
				return
			if not _report_listing():
				get_tree().quit(1)
				return
		1:
			_pick_saved_map()
		2:
			if not _report_picked():
				get_tree().quit(1)
				return
			_shoot("saved_map_picked")
		3:
			# THE SEAT GATE, driven through the REAL pickers. More PLAYERS than the map
			# seats, which `MapGen.build_from()` would answer by giving the surplus nothing
			# at all -- alive, owning nothing, defeated on the first tick anything looked.
			# Refused rather than started.
			#
			# SKIPPED FOR A FOREIGN MAP: its seat count is whatever its author chose, and
			# this preview has no business asserting a number it did not pick.
			if _folder == SAMPLE_FOLDER:
				_seat_players(_seats() + 2)
		4:
			if _folder == SAMPLE_FOLDER and not _report_seat_gate():
				get_tree().quit(1)
				return
		5:
			_seat_players(_seats())
		6:
			_start_the_match()
		7:
			if _frames < MATCH_FRAMES:
				return
			_shoot("saved_map_match")
			if not _report_match():
				get_tree().quit(1)
				return
			print("")
			print("OK — a saved map was listed, picked, gated and played.")
			get_tree().quit(0)
			return
	_step += 1


# ── authoring the sample ────────────────────────────────────────────────────

## Write `maps/sample_duel` if it is missing. False on anything that leaves us with no map.
func _ensure_sample(force: bool) -> bool:
	var dir := ProjectSettings.globalize_path("res://").path_join("../maps").simplify_path()
	var map_dir := dir.path_join(SAMPLE_FOLDER)
	var existed := MapFile.exists_in(map_dir)

	if existed and not force:
		print("sample map: keeping %s" % map_dir)
	else:
		DirAccess.make_dir_recursive_absolute(map_dir)
		var data := MapGenerator.generate(SAMPLE_SEED, SAMPLE_TYPE, SAMPLE_PLAYERS,
				SAMPLE_PLAYERS)
		# THE VALIDATOR'S VERDICT TRAVELS WITH THE MAP (`preview_author_maps`' rule): a map
		# authored past 2.4b's gate is one the lobby will refuse to start, found here rather
		# than by a player picking it.
		var map_problems: Array = data.meta.get("problems", [])
		if not map_problems.is_empty():
			push_error("sample map failed validation: %s"
					% "; ".join(PackedStringArray(map_problems)))
			return false
		var problems := MapFile.save(data, map_dir, {
			"name": SAMPLE_NAME,
			"map_type": MapGenerator.Type.keys()[SAMPLE_TYPE],
			"players": SAMPLE_PLAYERS,
			"seed": SAMPLE_SEED,
			"authored_by": "preview_saved_map",
		})
		if not problems.is_empty():
			push_error("sample map: %s" % "; ".join(PackedStringArray(problems)))
			return false
		print("sample map: %s %s" % ["REPLACED" if existed else "wrote", map_dir])

	# READ IT BACK BEFORE TRUSTING IT, `preview_author_maps`' rule: the point of this file is
	# that the game can read it, and only a read proves that.
	var read_problems: Array[String] = []
	_from_file = MapFile.load_map(map_dir, read_problems)
	if _from_file == null:
		push_error("sample map cannot be read back: %s"
				% "; ".join(PackedStringArray(read_problems)))
		return false
	print("sample map: %dx%d, %d entities, %d starts"
			% [_from_file.size.x, _from_file.size.y, _from_file.entities.size(),
			_from_file.starts.size()])
	return true


# ── the screen ──────────────────────────────────────────────────────────────

## Is the sample in the picker at all? Everything after this is meaningless if not.
func _report_listing() -> bool:
	print("")
	print("── the picker ──")
	var found := -1
	for i in _screen._type_picker.item_count:
		var id := _screen._type_picker.get_item_id(i)
		var saved := SkirmishScreen._saved_index_of(id)
		print("  %2d  id %-5d %-28s %s" % [i, id, _screen._type_picker.get_item_text(i),
				"SAVED" if saved >= 0 else ""])
		if saved >= 0 and _screen._saved_maps[saved].get("folder", "") == _folder:
			found = i
	if found < 0:
		push_error("the sample map is not in the picker -- discovery did not reach maps/")
		return false
	print("  the sample is item %d" % found)
	return true


func _pick_saved_map() -> void:
	for i in _screen._type_picker.item_count:
		var saved := SkirmishScreen._saved_index_of(_screen._type_picker.get_item_id(i))
		if saved >= 0 and _screen._saved_maps[saved].get("folder", "") == _folder:
			_screen._type_picker.select(i)
			_screen._type_picker.item_selected.emit(i)
			break
	_hold(UI_FRAMES)


## The map on screen must be the map on disk, and the seed controls must be dead.
func _report_picked() -> bool:
	print("")
	print("── picked ──")
	var shown := _screen.map_data()
	if shown == null:
		push_error("no map after picking the saved one")
		return false
	print("  status:      %s" % _screen.status_text())
	print("  can start:   %s" % _screen.can_start())
	print("  seed box:    %s" % ("editable" if _screen._seed_box.editable else "LOCKED"))
	print("  re-roll:     %s" % ("live" if not _screen._reroll_button.disabled else "LOCKED"))
	print("  shown map:   %dx%d, %d entities, %d starts"
			% [shown.size.x, shown.size.y, shown.entities.size(), shown.starts.size()])

	var ok := true
	# THE ASSERTION THAT MATTERS HERE: the screen is showing the FILE, not a fresh
	# generation that happens to be the same size.
	if shown.terrain != _from_file.terrain:
		push_error("the screen is not showing the file's terrain")
		ok = false
	if shown.starts != _from_file.starts:
		push_error("the screen's starts differ from the file's")
		ok = false
	# A SEED MEANS NOTHING TO A FILE, so leaving it live would invite a change that either
	# does nothing or throws the chosen map away.
	if _screen._seed_box.editable or not _screen._reroll_button.disabled:
		push_error("the seed controls are still live on a saved map")
		ok = false
	if not _screen.can_start():
		push_error("a two-player lobby on a two-player map should be startable: %s"
				% _screen.status_text())
		ok = false
	return ok


## How many players the map under test can seat, read off the FILE.
##
## The same arithmetic `SavedMaps._players_in()` does, and deliberately not read from the
## screen: this preview's job is to check the screen against the file, so taking the number
## from the screen would make the comparison circular.
func _seats() -> int:
	if _from_file == null:
		return SAMPLE_PLAYERS
	var starts := 0
	for s in _from_file.starts:
		if s.x >= 0:
			starts += 1
	var highest := 0
	for e in _from_file.entities:
		highest = maxi(highest, int(e.get("player", 0)))
	return mini(starts, highest) if starts > 0 and highest > 0 else 0


## More players than the map seats: refused, and it says which way out to take.
func _report_seat_gate() -> bool:
	print("")
	print("── %d players on a %d-seat map ──" % [_seats() + 2, _seats()])
	print("  status:    %s" % _screen.status_text())
	print("  can start: %s" % _screen.can_start())
	if _screen.can_start():
		push_error("more players started than the map seats -- the surplus would open the"
				+ " match owning nothing")
		return false
	# The message has to name the map and the number, or the fix is a guess.
	if not _screen.status_text().contains(SAMPLE_NAME):
		push_error("the refusal does not name the map")
		return false
	return true


## Seat `n` players: the slot count AND the roles.
##
## ⚠️ **RAISING THE SLOT COUNT ADDS ROOM, NOT PLAYERS.** New slots default to CLOSED, which
## is exactly what `_slots` versus `_active_slots()` is for -- eight slots with six closed is
## two players on a big board. The first version of this preview moved only the count picker
## and reported the seat gate as broken; `can_start()` was right and the way of exercising it
## was not. **That red run is why this function exists**, and it is the same trap
## `test_skirmish_screen._seat_players` now documents.
func _seat_players(n: int) -> void:
	var item := _screen._count_picker.get_item_index(n)
	_screen._count_picker.select(item)
	_screen._count_picker.item_selected.emit(item)
	for i in range(1, n):
		var picker: OptionButton = _screen._slot_rows[i]["role"]
		var role_item := picker.get_item_index(int(SkirmishScreen.Role.AI_PASSIVE))
		picker.select(role_item)
		picker.item_selected.emit(role_item)
	print("  seated %d player(s): %d active of %d slots"
			% [n, _screen.build_config().player_ids.size(), _screen._slots])
	_hold(UI_FRAMES)


# ── the match ───────────────────────────────────────────────────────────────

## Through the REAL config path -- `Net.pending_match`, consumed by `host_solo()`. Only the
## scene swap is done by hand, because the screen's own START would replace this preview.
func _start_the_match() -> void:
	print("")
	print("── starting the match ──")
	var cfg := _screen.build_config()
	print("  config: %dx%d, %d players, map_type %s (provenance), seed %d"
			% [cfg.map_size.x, cfg.map_size.y, cfg.player_ids.size(),
			MapGenerator.type_name(cfg.map_type), cfg.seed])
	Net.pending_match = cfg
	_screen.queue_free()
	_screen = null
	_frames = 0
	_game = load("res://scenes/game/Game.tscn").instantiate()
	add_child(_game)


## What the running world got, against what the FILE said. This is the step no screenshot
## and no headless test replaces.
func _report_match() -> bool:
	var host := Net.host()
	if host == null or host.world == null:
		push_error("no host -- the match never started")
		return false
	var world: SimWorld = host.world
	print("")
	print("── the running world ──")
	print("  map:      %dx%d" % [world.map.size.x, world.map.size.y])
	print("  players:  %d" % world.players.size())

	# Every town centre the file named, by the tile it named -- and the world must have one
	# standing on each. A generated map would put them somewhere else entirely.
	var want: Dictionary = {}
	for e in _from_file.entities:
		if int(e.get("player", 0)) > 0 and GameDataRegistry.building(e["def_id"]) != null:
			want[e["tile"]] = String(e["def_id"])

	# `origin_tile()`, NOT a `pos` divided by anything: a building's `pos` is its CENTRE in
	# sub-tile units, so `pos / SUBTILE` is the middle of the footprint and `MapData.tile` is
	# the top-left. The two differ by half a footprint, which for a 10x10 town centre is five
	# tiles -- far enough to look like the map having been ignored entirely.
	var got: Dictionary = {}
	for e in world.entities.values():
		if e is SimBuilding:
			got[(e as SimBuilding).origin_tile()] = String(e.def_id)

	var ok := true
	for tile in want:
		if not got.has(tile):
			push_error("the file puts %s at %s and the world has nothing there"
					% [want[tile], tile])
			ok = false
		elif got[tile] != want[tile]:
			push_error("the file puts %s at %s and the world has %s"
					% [want[tile], tile, got[tile]])
			ok = false
	print("  buildings the file named: %d, all present: %s" % [want.size(), ok])

	# And the terrain, which is the other half of a map and the half a building test would
	# not notice was wrong.
	var mismatched := 0
	for y in range(world.map.size.y):
		for x in range(world.map.size.x):
			var t := Vector2i(x, y)
			if world.map.terrain_at(t) != _from_file.terrain_at(t):
				mismatched += 1
	print("  terrain tiles differing from the file: %d" % mismatched)
	if mismatched != 0:
		push_error("the world's terrain is not the file's")
		ok = false
	return ok


# ── plumbing ────────────────────────────────────────────────────────────────

func _hold(frames: int) -> void:
	_resume_at = _frames + frames


func _shoot(shot_name: String) -> void:
	var path := SHOT_DIR + shot_name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
