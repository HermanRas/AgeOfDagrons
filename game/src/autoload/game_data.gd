## The asset seam (PLAN.md 2.1, 6.1). Phase 0.2a.
##
## Every visual and audio asset sits behind a stable ID and no filename appears
## in gameplay code:
##
##     var vis := GameDataRegistry.atlas_for(&"vis.villager")
##
## `atlas_for()` NEVER returns null. An ID resolves to a real baked atlas, or to
## its declared procedural placeholder, or -- if the ID is not in visuals.json at
## all -- to a loud magenta unknown. That total-ness is the load-bearing property:
## it is what lets a gameplay phase be built and shipped before its art exists
## (PLAN.md 2.4), and what lets the game run when an asset pack is missing or
## fails checksum verification rather than failing to boot (PLAN.md 3.2).
##
## The unit()/building()/resource_def()/tech()/age() half of this autoload is
## phase 0.4 and deliberately absent -- 0.2a is the asset seam only.
##
## NO `class_name`, deliberately, and despite PLAN.md 6.1 writing one: an autoload
## already registers `GameDataRegistry` as a global, and a matching class_name
## shadows it ("Class X hides an autoload singleton"), which breaks every
## `GameDataRegistry.atlas_for()` call site. net.gd and sim_clock.gd omit theirs
## for the same reason. Code that needs its own instance instead of the singleton
## -- the tests, for isolation -- loads this script by path.
extends Node

const SCRIPT_PATH := "res://src/autoload/game_data.gd"

const VISUALS_PATH := "res://data/visuals.json"
const AUDIO_PATH := "res://data/audio.json"

## Keys starting with this are documentation inside the JSON, not entries.
const _COMMENT_PREFIX := "_"

var _visuals: Dictionary = {}                     # StringName -> Dictionary (raw)
var _audio: Dictionary = {}                       # StringName -> Dictionary (raw)
var _resolved: Dictionary = {}                    # StringName -> AtlasEntry
var _loaded := false

## Non-fatal problems found while loading -- a malformed entry, an atlas whose
## pixels_per_metre disagrees with Iso. Surfaced for tests and the debug overlay
## instead of push_error() alone, so CI can assert the data is clean.
var load_warnings: Array[String] = []


func _ready() -> void:
	load_all()


## Idempotent: safe to call from a test before the autoload's own _ready().
func load_all(force := false) -> void:
	if _loaded and not force:
		return
	_visuals = _read_json(VISUALS_PATH)
	_audio = _read_json(AUDIO_PATH)
	_resolved.clear()
	_loaded = true


## Resolve a visual ID to a real atlas or a placeholder. Never null.
##
## Results are cached, so the atlas JSON is parsed once per ID rather than per
## spawn -- EntityViewPool.acquire() calls this on every entity that comes into
## view.
func atlas_for(visual_id: StringName) -> AtlasEntry:
	if not _loaded:
		load_all()
	if _resolved.has(visual_id):
		return _resolved[visual_id]

	var entry := _resolve(visual_id)
	_resolved[visual_id] = entry
	return entry


## True when this ID has real baked art mounted. For the debug overlay and for
## tests -- gameplay code has no business branching on it.
func has_atlas(visual_id: StringName) -> bool:
	return not atlas_for(visual_id).is_placeholder


func visual_ids() -> Array[StringName]:
	if not _loaded:
		load_all()
	var ids: Array[StringName] = []
	for key in _visuals:
		ids.append(key)
	ids.sort()
	return ids


## Declared sound IDs. The stream is null for every one of them in MVP
## (AudioManager is a no-op, PLAN.md 7.5) -- this exists so a caller passing an
## ID that was never declared is distinguishable from one that is simply silent.
func has_sfx(sound_id: StringName) -> bool:
	if not _loaded:
		load_all()
	return _audio.get(&"sfx", {}).has(String(sound_id))


func has_music(sound_id: StringName) -> bool:
	if not _loaded:
		load_all()
	return _audio.get(&"music", {}).has(String(sound_id))


# ── internals ──────────────────────────────────────────────────────────────

func _resolve(visual_id: StringName) -> AtlasEntry:
	var decl: Dictionary = _visuals.get(visual_id, {})
	if decl.is_empty():
		load_warnings.append("no visuals.json entry for '%s'" % visual_id)
		return AtlasEntry.from_placeholder(visual_id, PlaceholderSpec.unknown())

	var atlas := _load_atlas(visual_id, str(decl.get("atlas", "")))
	if atlas != null:
		return atlas

	var ph: Variant = decl.get("placeholder")
	if ph is Dictionary:
		return AtlasEntry.from_placeholder(visual_id, PlaceholderSpec.from_dict(ph))

	load_warnings.append("'%s' has neither a usable atlas nor a placeholder" % visual_id)
	return AtlasEntry.from_placeholder(visual_id, PlaceholderSpec.unknown())


## Returns null -- not a warning -- when the atlas is simply not present. That is
## the normal, expected state before the art pack is mounted, so it must not look
## like an error. A path that exists but does not parse IS a warning.
func _load_atlas(visual_id: StringName, path: String) -> AtlasEntry:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null

	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		load_warnings.append("atlas for '%s' is not valid JSON: %s" % [visual_id, path])
		return null

	var d: Dictionary = parsed
	if d.get("frames", []).is_empty():
		load_warnings.append("atlas for '%s' declares no frames: %s" % [visual_id, path])
		return null

	var entry := AtlasEntry.from_atlas_dict(visual_id, d, path.get_base_dir())

	# Guard the failure mode that has already bitten this project once: an atlas
	# baked at a different scale than the game projects at renders the wrong size
	# with nothing to warn you (PLAN.md 13.2 -- vis.villager). isobake's
	# metres_per_tile and Iso.TILE_SIZE are two copies of one number, so check
	# they still agree every time an atlas is read.
	if absf(entry.pixels_per_metre - Iso.PIXELS_PER_METRE) > 0.01:
		load_warnings.append(
			"atlas for '%s' was baked at %.3f px/m but Iso projects at %.3f -- "
			% [visual_id, entry.pixels_per_metre, Iso.PIXELS_PER_METRE]
			+ "tools/isobake.toml and Iso.TILE_SIZE disagree"
		)

	return entry


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		load_warnings.append("missing data file: %s" % path)
		return {}

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		load_warnings.append("not a JSON object: %s" % path)
		return {}

	var out: Dictionary = {}
	for key in parsed:
		var k := str(key)
		if k.begins_with(_COMMENT_PREFIX):
			continue
		out[StringName(k)] = parsed[key]
	return out
