## The audio output side of the asset seam (PLAN.md 2.1, 7.5, 13.2 item 11).
##
## Gameplay says what happened, never what to load:
##
##     AudioManager.play_sfx(&"ui.click")
##     AudioManager.play_sfx_at(&"villager.chop", world_pos)
##
## THIS IS THE OBJECT PLAN.md 7.5 CLAIMED EXISTED FOR MONTHS AND DID NOT. The id
## vocabulary and `has_sfx()` were real; the player was never written, and there
## were zero call sites. Both halves are here now, so if this file is ever gutted
## again the plan entry has to come with it.
##
## FOUR PROPERTIES THAT ARE THE WHOLE DESIGN, and each is load-bearing:
##
## 1. **It is total, like `atlas_for()`.** No call ever has to be guarded. A
##    declared id with no staged streams plays nothing and returns false; the
##    audio pack is optional (PLAN.md 3.2) and a build without it must be silent
##    rather than broken. An UNDECLARED id is the one case that complains, once
##    per id, because that is a typo in gameplay code and silence would hide it.
##
## 2. **Nothing is loaded until it is first heard.** 490 staged oggs would be a
##    pointless boot cost, and the headless test suite would pay it on every run
##    for audio no one is listening to. Streams are cached after first play.
##
## 3. **It never queues and never blocks.** Every player in the pool busy means
##    the sound is DROPPED. A queue would replay a battle's worth of sword hits
##    after the battle ended, which is worse than missing one swing.
##
## 4. **`throttle_ms` per id.** Gather and melee sounds fire per sim tick, and a
##    dozen villagers on one forest is a hundred chops a second. The number lives
##    in `audio.json` per id (`tools/stage_audio.py` sets it) rather than being a
##    constant here, because "how often is too often" differs per sound.
##
## NO `class_name`, deliberately -- an autoload already registers `AudioManager`
## as a global and a matching `class_name` shadows it, breaking every call site.
## `game_data.gd`, `net.gd` and `sim_clock.gd` all omit theirs for the same
## reason. Tests that want an isolated instance load this script by path.
##
## THE SIM DOES NOT CALL THIS AND MUST NOT. `src/sim/` may not load assets or
## touch the tree (PLAN.md 4, enforced by `tests/sim/test_sim_boundary.gd`), and
## a sim that made noise would make it during a headless AI-vs-AI run too. Every
## sound is emitted from the VIEW, off the snapshot it already receives -- see
## `MatchAudio`, which diffs consecutive snapshots into events.
extends Node

const SCRIPT_PATH := "res://src/autoload/audio_manager.gd"

## Where the player's volume choices persist. Not `ProjectSettings` -- that is
## the shipped default, and a per-device preference belongs in `user://`.
const _CONFIG_PATH := "user://audio.cfg"

## The mixing buses (PLAN.md 13.2 item 11 named per-category volume as the one
## real design question left, and this is the answer). Created at runtime rather
## than shipped as a `default_bus_layout.tres`, because a binary bus layout is
## a resource nobody can review in a diff and Godot rewrites it on save --
## the same trap `project.godot` comments fall into (§6 of AGENT_GAME_CODER.md).
##
## NOT A FLAT LIST -- bus -> where it sends. UI, VOICE and AMBIENT feed into SFX
## rather than into Master, which is the answer to the design question PLAN.md
## 13.2 item 11 left open ("mixing buses and per-category volume, since the
## SETTINGS page has nowhere to put a slider yet").
##
## THE POINT IS THAT THREE SLIDERS CONTROL EVERYTHING. A player wants "quieter
## music", "quieter game", "quieter overall" -- six sliders is a mixing desk
## nobody asked for, and on a phone it is six things to miss with a thumb. Routing
## the three quiet categories through SFX means the settings page offers Master,
## Music and Effects, while per-category trim is still there in the data for
## whoever needs it (a voice line that has to cut through a battle).
##
## ORDER IS LOAD-BEARING: Godot requires a bus to send to one with a LOWER index,
## so SFX must be created before the three that feed it. Declared as an Array of
## pairs rather than a Dictionary for exactly that reason -- a Dictionary's
## iteration order is not something to bet a bus graph on.
const BUS_SENDS: Array = [
	[&"MUSIC", &"Master"],
	[&"SFX", &"Master"],
	[&"UI", &"SFX"],
	[&"VOICE", &"SFX"],
	[&"AMBIENT", &"SFX"],
]

## The three a settings page should show, Master first. The rest are trim.
const MIXER_SLIDERS: Array[StringName] = [&"Master", &"MUSIC", &"SFX"]

## Non-positional voices: UI clicks and match announcements, which have no place
## on the map and must be audible wherever the camera is.
const _FLAT_VOICES := 8
## Positional voices. 16 is a deliberate ceiling, not a guess at demand: a battle
## can want far more, and dropping the 17th is the point (property 3 above).
const _POSITIONAL_VOICES := 16

## Beyond this many pixels from the camera's centre a positional sound is not
## played at all. Cheaper than letting Godot attenuate it to inaudibility, and it
## is what keeps a 200-unit map from filling the pool with sounds off screen.
const _AUDIBLE_RADIUS_PX := 1400.0

var _flat: Array[AudioStreamPlayer] = []
var _positional: Array[AudioStreamPlayer2D] = []
var _music_player: AudioStreamPlayer
var _ambient_player: AudioStreamPlayer

## id -> Array[AudioStream], filled on first play (property 2).
var _cache: Dictionary = {}
## id -> the msec at which it last played, for `throttle_ms`.
var _last_played: Dictionary = {}
## id -> index of the variation played last, so a two-variation group alternates
## instead of repeating itself half the time.
var _last_variation: Dictionary = {}
## Undeclared ids already reported. One line per typo, not one per frame.
var _complained: Dictionary = {}

## Linear 0..1 per bus, mirrored into AudioServer. Kept here as well because
## reading a bus's dB back and converting gives rounding drift on a slider.
var _volume: Dictionary = {}

var _music_id: StringName = &""

## Coalesces volume writes -- see `set_bus_volume`. One-shot and restarted on each
## change, so a drag saves once when the thumb stops moving.
var _save_timer: Timer


## Nodes in this group get no automatic click sound. The escape hatch for a
## button that plays something of its own and would otherwise double up.
const NO_CLICK_GROUP := &"no_click_sound"


func _ready() -> void:
	_ensure_buses()
	_build_pool()

	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.5
	_save_timer.timeout.connect(_save_settings)
	add_child(_save_timer)

	_load_settings()
	# EVERY BUTTON IN THE GAME, from one connection.
	#
	# The alternative was `play_sfx(&"ui.click")` in each of the ~40 places a
	# button is made -- across six screens, four HUD pages, the build grid, the
	# train menu and five separate button factories -- and the failure mode of
	# that is not a crash, it is one silent button somebody notices in a month.
	# `node_added` fires for every node that enters the tree for the rest of the
	# process, so a button built dynamically (the paged build grid rebuilds its
	# slots on every page turn) is covered without anything remembering to ask.
	#
	# Autoloads enter the tree before the main scene, so nothing is missed at the
	# front either.
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if not node is BaseButton or node.is_in_group(NO_CLICK_GROUP):
		return
	var btn := node as BaseButton
	# A disabled button never emits `pressed`, so there is nothing to suppress
	# for the wireframe pages whose SEND/CLEAR buttons are deliberately dead.
	if not btn.pressed.is_connected(_on_any_button_pressed):
		btn.pressed.connect(_on_any_button_pressed)


func _on_any_button_pressed() -> void:
	play_sfx(&"ui.click")


# ── buses and pool ──────────────────────────────────────────────────────────

func _ensure_buses() -> void:
	for pair in BUS_SENDS:
		var bus: StringName = pair[0]
		var send_to: StringName = pair[1]
		var idx := AudioServer.get_bus_index(String(bus))
		if idx == -1:
			idx = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, String(bus))
		# Set the send even for a bus that already existed: a project that once
		# shipped a `default_bus_layout.tres` could have it pointing elsewhere,
		# and the routing is the part this class actually depends on.
		AudioServer.set_bus_send(idx, String(send_to))


func _build_pool() -> void:
	for i in _FLAT_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_flat.append(p)

	for i in _POSITIONAL_VOICES:
		var p := AudioStreamPlayer2D.new()
		p.bus = "SFX"
		# Attenuation is left at Godot's default and the hard cull above does the
		# real work. A positional player still needs a parent in the tree to have
		# a transform, which is why these hang off the autoload rather than being
		# reparented to whatever emitted the sound -- a unit that dies mid-sound
		# would take its own death cry with it.
		add_child(p)
		_positional.append(p)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "MUSIC"
	add_child(_music_player)

	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = "AMBIENT"
	add_child(_ambient_player)


# ── playing ─────────────────────────────────────────────────────────────────

## Play `sound_id` with no position: UI, and announcements about the match.
## Returns whether a voice actually started, which tests assert on and callers
## are free to ignore.
func play_sfx(sound_id: StringName) -> bool:
	var entry := _entry(sound_id)
	if entry.is_empty():
		return false
	if _throttled(sound_id, entry):
		return false

	var stream := _pick(sound_id, entry)
	if stream == null:
		return false

	var player := _free_flat()
	if player == null:
		return false

	player.bus = String(entry.get("bus", "SFX"))
	player.stream = stream
	player.volume_db = float(entry.get("gain_db", 0.0))
	player.pitch_scale = _pitch(entry)
	player.play()
	_last_played[sound_id] = Time.get_ticks_msec()
	return true


## Play `sound_id` at a world position, culled beyond `_AUDIBLE_RADIUS_PX` of the
## camera centre. `listener` is where the camera is looking; callers that do not
## have it handy pass nothing and get an uncalled sound, which is why GameScene
## feeds it from the rig rather than this reaching for the camera itself (the
## autoload has no business knowing the scene tree's shape).
func play_sfx_at(sound_id: StringName, world_pos: Vector2, listener: Vector2 = Vector2.INF) -> bool:
	var entry := _entry(sound_id)
	if entry.is_empty():
		return false
	if listener != Vector2.INF and world_pos.distance_to(listener) > _AUDIBLE_RADIUS_PX:
		return false
	if _throttled(sound_id, entry):
		return false

	var stream := _pick(sound_id, entry)
	if stream == null:
		return false

	var player := _free_positional()
	if player == null:
		return false

	player.bus = String(entry.get("bus", "SFX"))
	player.stream = stream
	player.global_position = world_pos
	player.volume_db = float(entry.get("gain_db", 0.0))
	player.pitch_scale = _pitch(entry)
	player.play()
	_last_played[sound_id] = Time.get_ticks_msec()
	return true


## Start a music track, looping. Re-calling with the id already playing is a
## no-op, so a per-age call every snapshot does not restart the track every tick.
func play_music(music_id: StringName) -> bool:
	if music_id == _music_id and _music_player != null and _music_player.playing:
		return true
	var entry := GameDataRegistry.music(music_id)
	if entry.is_empty():
		if not GameDataRegistry.has_music(music_id):
			_complain(music_id, "music")
		return false

	var streams := _streams_for(music_id, entry)
	if streams.is_empty():
		_music_id = music_id     # declared, simply silent -- do not retry every tick
		return false

	var stream: AudioStream = streams[0]
	# Ogg and WAV both carry their own loop flag and it is off by default for a
	# file exported from an editor. Set it on the stream rather than reacting to
	# `finished`, which would leave an audible seam at the loop point.
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD

	_music_player.stream = stream
	_music_player.volume_db = float(entry.get("gain_db", 0.0))
	_music_player.play()
	_music_id = music_id
	return true


func stop_music() -> void:
	_music_id = &""
	if _music_player != null:
		_music_player.stop()


## The one looping map bed. Same no-op-if-unchanged rule as music.
func play_ambient(sound_id: StringName) -> bool:
	var entry := _entry(sound_id)
	if entry.is_empty():
		return false
	var streams := _streams_for(sound_id, entry)
	if streams.is_empty():
		return false
	var stream: AudioStream = streams[0]
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	if _ambient_player.stream == stream and _ambient_player.playing:
		return true
	_ambient_player.stream = stream
	_ambient_player.volume_db = float(entry.get("gain_db", 0.0))
	_ambient_player.play()
	return true


func stop_ambient() -> void:
	if _ambient_player != null:
		_ambient_player.stop()


## Stop everything at once -- leaving a match, or the app losing focus. Does not
## clear the stream cache: coming back should not re-read 50 files from disk.
func stop_all() -> void:
	for p in _flat:
		p.stop()
	for p in _positional:
		p.stop()
	stop_music()
	stop_ambient()


# ── volume (the SETTINGS page, PLAN.md 8.2b) ────────────────────────────────

## Linear 0..1. `Master` is accepted alongside the five declared buses so one
## slider can carry the whole mix.
func set_bus_volume(bus: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(String(bus))
	if idx == -1:
		return
	var clamped := clampf(linear, 0.0, 1.0)
	_volume[bus] = clamped
	# `linear_to_db(0)` is -inf, which Godot handles but which serialises badly
	# and reads as a bug in a config file. Mute explicitly instead.
	AudioServer.set_bus_mute(idx, clamped <= 0.0)
	if clamped > 0.0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clamped))
	# DEBOUNCED, not written here. An HSlider at 0.05 steps fires ~20 times
	# across one thumb drag, and each one would be a full read-modify-write of a
	# file on the device's flash. The bus is already at the new level, so the only
	# thing waiting is persistence, and half a second of it is nobody's problem.
	if _save_timer != null:
		_save_timer.start()


func bus_volume(bus: StringName) -> float:
	return float(_volume.get(bus, 1.0))


## Every bus that exists, Master first -- for `_load_settings`/`_save_settings`,
## which must round-trip the trim buses too even though no slider shows them.
func all_buses() -> Array[StringName]:
	var out: Array[StringName] = [&"Master"]
	for pair in BUS_SENDS:
		out.append(pair[0])
	return out


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	var loaded := cfg.load(_CONFIG_PATH) == OK
	for bus in all_buses():
		var linear := 1.0
		if loaded:
			linear = float(cfg.get_value("volume", String(bus), 1.0))
		# Straight to the server, NOT through set_bus_volume() -- that saves, and
		# saving while loading would write the defaults back over a config we are
		# in the middle of reading.
		var idx := AudioServer.get_bus_index(String(bus))
		_volume[bus] = clampf(linear, 0.0, 1.0)
		if idx == -1:
			continue
		AudioServer.set_bus_mute(idx, _volume[bus] <= 0.0)
		if _volume[bus] > 0.0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(_volume[bus]))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_CONFIG_PATH)          # keep anything else already in the file
	for bus in _volume:
		cfg.set_value("volume", String(bus), _volume[bus])
	cfg.save(_CONFIG_PATH)


# ── internals ───────────────────────────────────────────────────────────────

## The seam entry, or `{}` if this id must not play. Complains exactly once for an
## id that was never declared -- the only case that is a bug rather than a state.
func _entry(sound_id: StringName) -> Dictionary:
	# THE EMPTY ID IS A DELIBERATE NO-OP, not a typo. `entity_sfx()` returns &""
	# for anything audio_map.json does not map -- the monk has no weapon, an
	# animal has no voice -- so callers pass its result straight in without a
	# guard, and complaining here would fire on every swing of a unit that is
	# correctly silent.
	if sound_id == &"":
		return {}
	var entry := GameDataRegistry.sfx(sound_id)
	if entry.is_empty() and not GameDataRegistry.has_sfx(sound_id):
		_complain(sound_id, "sfx")
	return entry


func _complain(sound_id: StringName, kind: String) -> void:
	if _complained.has(sound_id):
		return
	_complained[sound_id] = true
	push_error("AudioManager: no such %s id %s (data/audio.json)" % [kind, sound_id])


func _throttled(sound_id: StringName, entry: Dictionary) -> bool:
	var gap := int(entry.get("throttle_ms", 0))
	if gap <= 0:
		return false
	var last := int(_last_played.get(sound_id, -1_000_000))
	return Time.get_ticks_msec() - last < gap


## Load and cache the streams for an id. Only paths that actually exist are
## returned, so a partial audio pack degrades to fewer variations rather than to
## a load error -- `ResourceLoader.exists` is the check, and `load()` is only
## reached for a path that passed it.
func _streams_for(sound_id: StringName, entry: Dictionary) -> Array:
	if _cache.has(sound_id):
		return _cache[sound_id]
	var out: Array = []
	for path in entry.get("streams", []):
		var p := String(path)
		if not ResourceLoader.exists(p):
			continue
		var res := load(p)
		if res is AudioStream:
			out.append(res)
	_cache[sound_id] = out
	return out


## One variation, avoiding an immediate repeat when there is a choice.
func _pick(sound_id: StringName, entry: Dictionary) -> AudioStream:
	var streams := _streams_for(sound_id, entry)
	if streams.is_empty():
		return null
	if streams.size() == 1:
		return streams[0]
	var last := int(_last_variation.get(sound_id, -1))
	var idx := randi() % streams.size()
	if idx == last:
		idx = (idx + 1) % streams.size()
	_last_variation[sound_id] = idx
	return streams[idx]


func _pitch(entry: Dictionary) -> float:
	var lo := float(entry.get("pitch_min", 1.0))
	var hi := float(entry.get("pitch_max", 1.0))
	if hi <= lo:
		# A group that asked for no jitter serialises as 1..1; guard against a
		# zero or negative too, which Godot rejects outright.
		return maxf(lo, 0.01)
	return randf_range(lo, hi)


func _free_flat() -> AudioStreamPlayer:
	for p in _flat:
		if not p.playing:
			return p
	return null


func _free_positional() -> AudioStreamPlayer2D:
	for p in _positional:
		if not p.playing:
			return p
	return null
