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
## Phase 0.4 added the entity half -- unit(), building(), resource_def(), tech(),
## age() over data/*.json, parsed into the *Def types in src/data/. Those follow
## the opposite convention to atlas_for() and return NULL for an unknown ID,
## deliberately: a missing sprite has a sensible stand-in and a missing unit
## definition does not, so the seam absorbs one and must not paper over the other.
##
## validate() cross-checks the files against each other and is asserted clean by
## the test suite, which is the only thing standing between a typo in a JSON ID
## and a silent no-op at runtime.
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
const UNITS_PATH := "res://data/units.json"
const BUILDINGS_PATH := "res://data/buildings.json"
const RESOURCES_PATH := "res://data/resources.json"
const TECHS_PATH := "res://data/techs.json"
const AGES_PATH := "res://data/ages.json"
const FACTIONS_PATH := "res://data/factions.json"

## Keys starting with this are documentation inside the JSON, not entries.
const _COMMENT_PREFIX := "_"

var _visuals: Dictionary = {}                     # StringName -> Dictionary (raw)
var _audio: Dictionary = {}                       # StringName -> Dictionary (raw)
var _resolved: Dictionary = {}                    # StringName -> AtlasEntry
var _loaded := false

var _units: Dictionary = {}                       # StringName -> UnitDef
var _buildings: Dictionary = {}                   # StringName -> BuildingDef
var _resources: Dictionary = {}                   # StringName -> ResourceDef
var _techs: Dictionary = {}                       # StringName -> TechDef
var _factions: Dictionary = {}                    # StringName -> Dictionary (raw, 9.5)
var _ages: Array[AgeDef] = []

## Non-fatal problems found while loading -- a malformed entry, an atlas whose
## pixels_per_metre disagrees with Iso. Surfaced for tests and the debug overlay
## instead of push_error() alone, so the test suite can assert the data is clean.
var load_warnings: Array[String] = []


func _ready() -> void:
	load_all()


## Idempotent: safe to call from a test before the autoload's own _ready().
func load_all(force := false) -> void:
	if _loaded and not force:
		return
	# Cleared here, not appended across reloads -- a forced reload that fixed the
	# data must not still be reporting the problems it fixed.
	load_warnings.clear()
	_visuals = _read_json(VISUALS_PATH)
	_audio = _read_json(AUDIO_PATH)
	_resolved.clear()

	_units = _read_defs(UNITS_PATH, UnitDef.from_dict)
	_buildings = _read_defs(BUILDINGS_PATH, BuildingDef.from_dict)
	_resources = _read_defs(RESOURCES_PATH, ResourceDef.from_dict)
	_techs = _read_defs(TECHS_PATH, TechDef.from_dict)
	_factions = _read_json(FACTIONS_PATH)
	_read_ages()

	_loaded = true
	validate()


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


# ── entity definitions (0.4) ───────────────────────────────────────────────
#
# These return null for an unknown ID, unlike atlas_for(). A missing sprite has a
# sensible stand-in; a missing unit definition does not, and inventing one would
# turn a typo into a unit that exists with nonsense stats.

func unit(id: StringName) -> UnitDef:
	if not _loaded:
		load_all()
	return _units.get(id)


func building(id: StringName) -> BuildingDef:
	if not _loaded:
		load_all()
	return _buildings.get(id)


func resource_def(id: StringName) -> ResourceDef:
	if not _loaded:
		load_all()
	return _resources.get(id)


func tech(id: StringName) -> TechDef:
	if not _loaded:
		load_all()
	return _techs.get(id)


## Ages are 1-indexed (SimPlayer.age starts at 1). Out of range returns null.
func age(index: int) -> AgeDef:
	if not _loaded:
		load_all()
	if index < 1 or index > _ages.size():
		return null
	return _ages[index - 1]


func age_count() -> int:
	if not _loaded:
		load_all()
	return _ages.size()


func unit_ids() -> Array[StringName]:
	return _sorted_keys(_units)


func building_ids() -> Array[StringName]:
	return _sorted_keys(_buildings)


func resource_ids() -> Array[StringName]:
	return _sorted_keys(_resources)


func faction_ids() -> Array[StringName]:
	return _sorted_keys(_factions)


## Cross-file consistency. Appends to load_warnings; the test suite asserts it
## comes back empty, which is what catches an ID renamed in one file and not in
## the ones referring to it. Called automatically by load_all().
##
## Deliberately NOT fatal: a bad reference should fail the test suite, not stop a
## developer's game from booting mid-edit.
func validate() -> void:
	for id in _units:
		var u: UnitDef = _units[id]
		_require_visual(u.visual, "unit '%s'" % id)
		_require_kinds(u.cost, "unit '%s' cost" % id)
		_require_kinds(u.carry_cap, "unit '%s' carry_cap" % id)
		_require_kinds(u.gather_rate, "unit '%s' gather_rate" % id)
		for b in u.trainable_at:
			if not _buildings.has(b):
				load_warnings.append("unit '%s' is trainable_at unknown building '%s'" % [id, b])

	for id in _buildings:
		var b: BuildingDef = _buildings[id]
		_require_visual(b.visual, "building '%s'" % id)
		_require_visual(b.visual_foundation, "building '%s' foundation" % id)
		_require_visual(b.visual_rubble, "building '%s' rubble" % id)
		_require_kinds(b.cost, "building '%s' cost" % id)
		if b.footprint.x < 1 or b.footprint.y < 1:
			load_warnings.append("building '%s' has a degenerate footprint %s" % [id, b.footprint])
		for t in b.trains:
			if not _units.has(t):
				load_warnings.append("building '%s' trains unknown unit '%s'" % [id, t])
		for kind in b.drop_off:
			if not GameDefs.RESOURCE_KINDS.has(kind):
				load_warnings.append("building '%s' drops off unknown kind '%s'" % [id, kind])

	for id in _resources:
		var r: ResourceDef = _resources[id]
		_require_visual(r.visual, "resource '%s'" % id)
		if not GameDefs.RESOURCE_KINDS.has(r.kind):
			load_warnings.append("resource '%s' has unknown kind '%s'" % [id, r.kind])
		if r.amounts.is_empty():
			load_warnings.append("resource '%s' declares no amounts" % id)
		if r.gather_slots < 1:
			load_warnings.append("resource '%s' has %d gather slots" % [id, r.gather_slots])

	# Every unit must be trainable somewhere, or it can never enter a match. Not
	# true in reverse -- a building that trains nothing is fine.
	for id in _units:
		if (_units[id] as UnitDef).trainable_at.is_empty():
			load_warnings.append("unit '%s' is trainable at no building" % id)


func _require_visual(visual_id: StringName, who: String) -> void:
	if visual_id.is_empty():
		load_warnings.append("%s names no visual" % who)
	elif not _visuals.has(visual_id):
		load_warnings.append("%s references undeclared visual '%s'" % [who, visual_id])


func _require_kinds(d: Dictionary, who: String) -> void:
	for kind in GameDefs.unknown_kinds(d):
		load_warnings.append("%s uses unknown resource kind '%s'" % [who, kind])


# ── internals ──────────────────────────────────────────────────────────────

func _sorted_keys(d: Dictionary) -> Array[StringName]:
	if not _loaded:
		load_all()
	var ids: Array[StringName] = []
	for key in d:
		ids.append(key)
	ids.sort()
	return ids


## Read an ID-keyed data file and build one *Def per entry via its from_dict.
func _read_defs(path: String, factory: Callable) -> Dictionary:
	var out: Dictionary = {}
	var raw := _read_json(path)
	for id in raw:
		var entry: Variant = raw[id]
		if entry is Dictionary:
			out[id] = factory.call(id, entry)
		else:
			load_warnings.append("entry '%s' in %s is not an object" % [id, path])
	return out


func _read_ages() -> void:
	_ages.clear()
	var raw := _read_json(AGES_PATH)
	var list: Variant = raw.get(&"ages", [])
	if not list is Array:
		load_warnings.append("ages.json has no 'ages' list")
		return
	for i in range((list as Array).size()):
		var entry: Variant = list[i]
		if entry is Dictionary:
			_ages.append(AgeDef.from_dict(i + 1, entry))
		else:
			load_warnings.append("ages.json entry %d is not an object" % i)

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
