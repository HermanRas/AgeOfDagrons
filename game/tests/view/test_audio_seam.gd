## The audio seam (PLAN.md 2.1, 7.5, 13.2 item 11).
##
## THE PROPERTY UNDER TEST IS THE SAME ONE `test_visual_seam.gd` guards, one
## layer over: TOTALITY. Every caller must be able to ask for a sound without a
## guard, and the two ways a sound can fail to play must stay distinguishable --
## a declared id with no staged file is SILENCE (legitimate; the audio pack is
## optional, PLAN.md 3.2), and an undeclared id is a CALLER BUG (reported).
## Collapsing those two into "nothing happened" is exactly how a typo in a sound
## id survives for months, which is the failure PLAN.md 7.5 already suffered once
## in a bigger way: the plan claimed an AudioManager existed, it did not, and
## nothing failed because nothing was calling it.
##
## Run against the real data/audio.json and data/audio_map.json rather than
## fixtures, deliberately -- the shipped data being coherent is itself worth
## failing the suite over, and a fixture here would be a fixture that agrees with
## whatever the staging tool last produced (AGENT_GAME_CODER.md §5's "beware
## fixtures that agree with the bug").
extends TestCase

const REGISTRY_SCRIPT := "res://src/autoload/game_data.gd"
const AUDIO_SCRIPT := "res://src/autoload/audio_manager.gd"

var reg: Node


func before_each() -> void:
	reg = (load(REGISTRY_SCRIPT) as GDScript).new()
	reg.load_all()


func after_each() -> void:
	reg.free()


# ── the vocabulary ──────────────────────────────────────────────────────────

func test_the_shipped_audio_files_load_without_warnings() -> void:
	assert_false(reg.sfx_ids().is_empty(), "audio.json declares at least one sfx id")
	assert_false(reg.music_ids().is_empty(), "audio.json declares at least one track")
	assert_true(reg.load_warnings.is_empty(),
			"data files are not clean -- %s" % "; ".join(reg.load_warnings))


func test_a_declared_silent_id_is_distinguishable_from_an_undeclared_one() -> void:
	# The whole contract in one test. `ui.click` is declared; `ui.yodel` is not.
	# Note this passes whether or not the audio pack is staged -- being declared
	# is not the same as having bytes, and that is the point.
	assert_true(reg.has_sfx(&"ui.click"), "a declared id reports as declared")
	assert_false(reg.has_sfx(&"ui.yodel"), "an undeclared id is not silently accepted")
	assert_true(reg.sfx(&"ui.yodel").is_empty(),
			"an undeclared id yields an empty entry rather than null")


func test_every_declared_sfx_entry_has_the_fields_audio_manager_reads() -> void:
	# AudioManager reads these with defaults, so a missing one is not a crash --
	# it is a sound at the wrong volume or pitch, which nobody would trace back
	# to the data. Asserting the shape here is cheaper than hearing it.
	for id in reg.sfx_ids():
		var entry: Dictionary = reg.sfx(id)
		assert_true(entry.has("streams"), "%s declares streams" % id)
		assert_true(entry["streams"] is Array, "%s streams is an Array" % id)
		assert_true(entry.has("bus"), "%s declares a bus" % id)
		assert_true(entry.has("gain_db"), "%s declares gain_db" % id)
		assert_true(float(entry.get("pitch_min", 0.0)) > 0.0,
				"%s pitch_min is positive -- Godot rejects a zero pitch_scale" % id)
		assert_true(float(entry.get("pitch_max", 0.0)) >= float(entry.get("pitch_min", 0.0)),
				"%s pitch range is not inverted" % id)
		assert_true(int(entry.get("throttle_ms", -1)) >= 0,
				"%s throttle_ms is not negative" % id)
		assert_true(int(entry.get("crowd_ms", -1)) >= 0,
				"%s crowd_ms is not negative" % id)
		# The crowd gap must not exceed a source's own gap, or the second limit
		# would be the binding one and per-source pacing would do nothing --
		# which is exactly the single-global-number behaviour the two limits
		# exist to replace.
		var throttle := int(entry.get("throttle_ms", 0))
		var crowd := int(entry.get("crowd_ms", 0))
		if throttle > 0 and crowd > 0:
			assert_true(crowd <= throttle,
					"%s crowd_ms (%d) does not exceed throttle_ms (%d)"
					% [id, crowd, throttle])


func test_every_declared_bus_is_one_the_audio_manager_creates() -> void:
	# A typo'd bus name is silent in the worst way: `AudioStreamPlayer.bus` set to
	# a bus that does not exist falls back to Master, so the sound PLAYS and the
	# volume slider for its category does nothing.
	var known := {}
	for pair in load(AUDIO_SCRIPT).BUS_SENDS:
		known[String(pair[0])] = true
	known["Master"] = true
	for id in reg.sfx_ids():
		assert_true(known.has(String(reg.sfx(id).get("bus", ""))),
				"%s uses a bus AudioManager creates (got %s)"
				% [id, reg.sfx(id).get("bus", "")])
	for id in reg.music_ids():
		assert_true(known.has(String(reg.music(id).get("bus", ""))),
				"%s uses a known bus" % id)


func test_every_stream_path_points_inside_the_staged_audio_tree() -> void:
	# The seam is the only place filenames live, so this is where a path that
	# escaped the staged tree would be caught. A stream under res://src/ or an
	# absolute user:// path would load in the editor and vanish from an export.
	for id in reg.sfx_ids() + reg.music_ids():
		var entry: Dictionary = reg.sfx(id)
		if entry.is_empty():
			entry = reg.music(id)
		for path in entry.get("streams", []):
			assert_true(String(path).begins_with("res://assets/audio/"),
					"%s stream is inside the staged tree: %s" % [id, path])
			assert_true(String(path).ends_with(".ogg"),
					"%s stream is an ogg: %s" % [id, path])


# ── the entity map ──────────────────────────────────────────────────────────

func test_every_sound_the_entity_map_names_is_declared() -> void:
	# THE TEST THAT ACTUALLY EARNS ITS PLACE. audio_map.json is hand-authored and
	# audio.json is generated, so the two drift in exactly one direction: a
	# rename in the staging tool's mapping leaves audio_map.json pointing at an id
	# that no longer exists, and the symptom is one silent unit nobody notices.
	var events: Array[StringName] = [
		&"death", &"attack", &"trained", &"idle", &"complete", &"select",
		&"build", &"work",
	]
	for def_id in reg.audio_mapped_ids():
		for event in events:
			# Explicitly typed: `reg` is the untyped script instance (game_data.gd
			# has no class_name, deliberately), so its returns are Variant and
			# `:=` cannot infer.
			var sound: StringName = reg.entity_sfx(def_id, event)
			if sound == &"":
				continue          # absence is silence, not an error
			assert_true(reg.has_sfx(sound),
					"%s.%s names a declared sound (got %s)" % [def_id, event, sound])


func test_every_voice_line_the_map_implies_is_declared() -> void:
	# `voice` is not a sound id but half of one -- `male` becomes
	# `voice.male.select`. A voice set naming a line that does not exist would be
	# a unit that answers some orders and not others.
	var lines: Array[StringName] = [&"select", &"move", &"attack", &"build", &"gather"]
	for def_id in reg.audio_mapped_ids():
		for line in lines:
			var sound: StringName = reg.entity_voice(def_id, line)
			if sound == &"":
				continue
			assert_true(reg.has_sfx(sound),
					"%s voice line %s is declared (got %s)" % [def_id, line, sound])


func test_the_entity_map_only_names_defs_that_exist() -> void:
	# The other direction of the same drift: a sound mapped to a def that was
	# renamed or removed is dead weight that reads as coverage.
	for def_id in reg.audio_mapped_ids():
		var known := (reg.unit(def_id) != null
				or reg.building(def_id) != null
				or reg.resource_def(def_id) != null)
		assert_true(known, "%s in audio_map.json is a real def" % def_id)


func test_every_unit_and_building_in_the_roster_has_a_sound() -> void:
	# Coverage, stated as a test rather than as a claim in a document -- which is
	# the specific mistake PLAN.md 7.5 made about this very feature.
	for id in reg.unit_ids():
		assert_ne(reg.entity_sfx(id, &"death"), &"",
				"%s has a death sound" % id)
	for id in reg.building_ids():
		assert_ne(reg.entity_sfx(id, &"complete"), &"",
				"%s has a completion sound" % id)
		assert_ne(reg.entity_sfx(id, &"select"), &"",
				"%s has a selection sound" % id)


func test_an_unmapped_entity_is_silent_rather_than_an_error() -> void:
	assert_eq(reg.entity_sfx(&"unit.does_not_exist", &"death"), &"",
			"an unknown def is silent")
	assert_eq(reg.entity_sfx(&"unit.villager", &"nonsense_event"), &"",
			"an unknown event is silent")
	assert_eq(reg.entity_voice(&"unit.wolf", &"select"), &"",
			"an entity with no voice set has no voice line")


# ── what is staged ──────────────────────────────────────────────────────────

func test_silence_is_reported_rather_than_merely_happening() -> void:
	# Does not assert that anything IS staged: `game/assets/audio/` is gitignored
	# build output (tools/stage_audio.py) and a clean checkout has none of it, so
	# a test requiring bytes would fail for everyone who had not run the tool.
	# What it does assert is that the registry can SAY which ids are silent --
	# without that, "no audio pack" and "wrong id" look identical at runtime.
	var silent: Array[StringName] = reg.silent_sfx_ids()
	var declared: Array[StringName] = reg.sfx_ids()
	assert_true(silent.size() <= declared.size(),
			"the silent list is a subset of the declared list")
	for id in silent:
		assert_true(reg.has_sfx(id), "%s is silent but still declared" % id)
