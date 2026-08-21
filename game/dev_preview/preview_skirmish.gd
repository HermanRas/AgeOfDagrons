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

## Frames to let the UI redraw between changing a lobby state and photographing it. A
## shot taken on the same frame as the change catches the screen as it was before.
const LOBBY_FRAMES := 10

var _screen: SkirmishScreen = null
var _game: Node = null
var _frames := 0
var _step := 0
var _resume_at := 0
var _expected: MapData = null


func _ready() -> void:
	_screen = load("res://scenes/menu/Skirmish.tscn").instantiate()
	add_child(_screen)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < _resume_at:
		return
	match _step:
		0:
			if _frames < SETTLE_FRAMES:
				return
			_report_screen()
			_shoot("skirmish_screen")
		1:
			# THE LOBBY (12.1c). Setting a slot to Open is what opens the socket, so this
			# is the hosting path and not a simulation of it.
			_open_a_slot()
		2:
			_report_lobby()
			_shoot("skirmish_lobby_waiting")
		3:
			# A peer arriving. The connection itself is (g)'s ground already proven on two
			# devices; what is unproven is that this SCREEN shows the chair being taken
			# and lets START go ahead once it is.
			_screen._on_peer_joined(7777)
			_hold(LOBBY_FRAMES)
		4:
			_report_lobby()
			_shoot("skirmish_lobby_filled")
		5:
			# The JOINING device's view of the same screen -- the one state that cannot be
			# reached from here honestly, since a real one needs a second process dialling
			# in. FORCED, and labelled as forced: what it is worth is the LOOK of a screen
			# that configures nothing, which no test can judge. The control states
			# themselves are asserted in test_skirmish_screen.
			_join_someone_elses_match()
		6:
			_shoot("skirmish_lobby_joined")
		7:
			Net._lobby_config = null
			_screen._lobby = SkirmishScreen.Lobby.HOSTING
			# Back to a plain skirmish, so the solo path below is exercised exactly as it
			# was before this screen learned to host -- the regression that would matter
			# most here is the one where adding multiplayer broke playing alone.
			_close_the_slot()
		8:
			_start_the_match()
		9:
			if _frames < SETTLE_FRAMES + MATCH_FRAMES:
				return
			_report_match()
			_shoot("skirmish_match")
		_:
			get_tree().quit()
			return
	_step += 1


## Hold the script for `frames` before the next step, so a UI change has actually been
## drawn by the time it is photographed.
func _hold(frames: int) -> void:
	_resume_at = _frames + frames


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


## Pick a role on slot `index` the way a finger does: move the dropdown, then let its own
## signal carry the change.
##
## `select()` AND `item_selected.emit()`, not the handler on its own. Calling the handler
## directly leaves the OptionButton still showing its old choice, so the first version of
## this photographed a lobby whose Player 2 row read "PlayTest AI" while the peer list
## below it said somebody had joined that slot -- and it would have passed just as
## happily with the signal unconnected. Same reason `preview_match` presses the real
## cancel Button rather than calling `_exit_placement`.
func _pick_role(index: int, role: SkirmishScreen.Role) -> void:
	var picker: OptionButton = _screen._slot_rows[index]["role"]
	var item := picker.get_item_index(int(role))
	picker.select(item)
	picker.item_selected.emit(item)


func _open_a_slot() -> void:
	_pick_role(1, SkirmishScreen.Role.OPEN)
	_hold(LOBBY_FRAMES)


func _close_the_slot() -> void:
	# Through _on_peer_left first: a slot with somebody in it cannot be un-opened, which
	# is the rule, so the peer has to go before the chair can.
	_screen._on_peer_left(7777)
	_pick_role(1, SkirmishScreen.Role.PLAYTEST_AI)
	print("lobby: closed -- state %d, session %s, startable %s"
			% [_screen.lobby_state(), Net.has_session(), _screen.can_start()])
	_hold(LOBBY_FRAMES)


## The joining device's screen, holding a real proposal from a host.
##
## A DIFFERENT SEED ON PURPOSE. The point of the lobby channel is that the joiner reviews
## the HOST'S map rather than one of its own, and the two are only distinguishable in a
## picture if they are different maps -- a shot where both sides generated seed 1 would
## look identical whether the channel worked or not.
##
## The lobby state is forced, since a real one needs a second process dialling in (that
## part is verified by running two of them). What the picture is worth is the LOOK of a
## screen being asked to agree to something, which no test can judge.
func _join_someone_elses_match() -> void:
	var host_side := SkirmishScreen.new()
	host_side._on_seed_changed(4242.0)
	var proposal := host_side.build_config()
	host_side.free()

	Net._lobby_config = proposal
	_screen._lobby = SkirmishScreen.Lobby.JOINED
	_screen._on_lobby_config_received()
	print("joined: reviewing seed %d, %dx%d, %s — ready %s, can start %s"
			% [proposal.seed, proposal.map_size.x, proposal.map_size.y,
			MatchConfig.mode_name(proposal.mode), _screen._am_ready, _screen.can_start()])
	if _screen.map_data() != proposal.map_data:
		push_warning("preview_skirmish: the joiner is not showing the host's map")
	_hold(LOBBY_FRAMES)


func _report_lobby() -> void:
	print("lobby: state %d, session %s, unfilled %d, startable %s"
			% [_screen.lobby_state(), Net.has_session(), _screen.unfilled_slots(),
			_screen.can_start()])
	for line in _screen.lobby_text().split("\n"):
		print("    %s" % line)
	if _screen.lobby_state() != SkirmishScreen.Lobby.HOSTING:
		push_warning("preview_skirmish: setting a slot to Open did not start hosting")


## Exactly what START does, minus the scene change.
func _start_the_match() -> void:
	_resume_at = 0                   # the match step re-bases _frames; drop any stale hold
	# Re-read what the screen is showing AT THE MOMENT OF COMMIT, which is what this
	# comparison is actually about: a config that builds a different world than the screen
	# previewed. Captured at step 0 originally, and that broke the moment the lobby steps
	# were added -- the JOINED excursion adopts a host's map into this same screen, so the
	# shot from six steps ago is no longer what is being started.
	_expected = _screen.map_data()
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
