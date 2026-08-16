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
const COLOURS_PATH := "res://data/colours.json"

## Keys starting with this are documentation inside the JSON, not entries.
const _COMMENT_PREFIX := "_"

## What every atlas JSON path ends in. The seam is the ONE place allowed to know
## this -- it is what lets a per-colour bake be derived from the base path instead
## of declared eight times per unit (see _atlas_path_for_skin).
const _ATLAS_SUFFIX := ".atlas.json"

var _visuals: Dictionary = {}                     # StringName -> Dictionary (raw)
var _audio: Dictionary = {}                       # StringName -> Dictionary (raw)
var _resolved: Dictionary = {}                    # StringName -> AtlasEntry
var _loaded := false

var _units: Dictionary = {}                       # StringName -> UnitDef
var _buildings: Dictionary = {}                   # StringName -> BuildingDef
var _resources: Dictionary = {}                   # StringName -> ResourceDef
var _techs: Dictionary = {}                       # StringName -> TechDef
var _factions: Dictionary = {}                    # StringName -> Dictionary (raw, 9.5).
                                                  # One entry, `faction.default`: v1 is one
                                                  # civilisation (PLAN.md 1) and this is the
                                                  # default skin key (2.7.1), not a roster.
var _ages: Array[AgeDef] = []
## Player-colour palette, index-ordered (PLAN.md 1). SimPlayer.colour indexes this.
## Kept as a plain Array[Color] rather than a *Def -- there is nothing to parse but
## a hex string, and order is the whole contract.
var _colours: Array[Color] = []
## The same palette as lowercase words (`colour.blue` -> `blue`), index-aligned
## with `_colours`. This is the half of the palette the ART is keyed by: isobake
## suffixes a tinted bake `vis.<id>.<colour>` (PLAN.md 1, the atlas contract), so
## resolving a player's atlas needs the word, not the Color.
var _colour_slugs: Array[StringName] = []

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
	_read_colours()

	_loaded = true
	validate()


## Resolve a visual ID to a real atlas or a placeholder. Never null.
##
## `age` and `colour` together are the SKIN (PLAN.md 2.7.1). Both are optional and
## both mean "no preference" at their defaults, so the one-argument call every
## pre-0.10 caller already makes keeps working and gets the base bake:
##
##     atlas_for(&"vis.town_center")            # base art
##     atlas_for(&"vis.town_center", 3)         # the age-3 skin
##     atlas_for(&"vis.villager", 0, 1)         # player 2's colour (red)
##
## `age` is 1-4 (SimPlayer.age); 0 or less takes the entry's base atlas.
## `colour` is an index into colours.json (SimPlayer.colour); negative is untinted.
##
## Results are cached per (id, age, colour), so the atlas JSON is parsed once per
## skin rather than per spawn -- EntityViewPool.acquire() calls this on every
## entity that comes into view.
func atlas_for(visual_id: StringName, age: int = 0, colour: int = -1) -> AtlasEntry:
	if not _loaded:
		load_all()

	var key := _skin_key(visual_id, age, colour)
	if _resolved.has(key):
		return _resolved[key]

	var entry := _resolve(visual_id, age, colour)
	_resolved[key] = entry
	return entry


## True when this ID has real baked art mounted. For the debug overlay and for
## tests -- gameplay code has no business branching on it.
func has_atlas(visual_id: StringName, age: int = 0, colour: int = -1) -> bool:
	return not atlas_for(visual_id, age, colour).is_placeholder


## The lowercase colour word isobake suffixes a tinted bake with -- `colour.blue`
## in colours.json is `vis.villager.blue` on disk. Wraps like colour(), for the
## same reason: an out-of-range index must not be what stops a match rendering.
## Empty palette -> &"".
func colour_slug(index: int) -> StringName:
	if not _loaded:
		load_all()
	if _colour_slugs.is_empty():
		return &""
	return _colour_slugs[posmod(index, _colour_slugs.size())]


## Which (visual, colour) pairs DECLARE a per-player bake but have no file staged
## for it. Diagnostic only -- resolution silently falls back to the untinted bake,
## which renders a player in nobody's colour, and since colour is the only thing
## telling players apart (PLAN.md 1) that is a gap worth being able to enumerate
## rather than notice in a match. Returns [] when the art pack is not mounted at
## all, because then EVERY colour is missing and the list would say nothing.
##
## How far behind its unit's newest bake a colour atlas may be before it is
## called stale. See stale_colour_atlases() for why an hour.
const COLOUR_STALENESS_SECONDS := 3600


## Which per-player bakes are PRESENT but older than the newest bake of the same
## visual -- the failure missing_colour_atlases() cannot see, because the file is
## there and parses and draws.
##
## Asked for by the art agent (asset_request.md, 2026-08-16) after three pipeline
## defects were fixed mid-roster: `decay` sampled from t=0 so every corpse sprang
## upright for a frame, two units baked as overlapping bodies, and player colour
## never reached actors with an opaque root. Only red and yellow were rebaked, so
## 60 of the 152 colour atlases render wrongly while looking perfectly healthy.
##
## MODIFICATION TIME is the signal, for want of a better one: the fixes were in
## isobake's source, not in the recipes, so nothing inside the atlas JSON changed
## -- `generator.version` and `recipe_sha256` are identical across the boundary.
## The threshold is an hour because the measured separation is not close: within
## one colour batch the eight files land inside 25 minutes of each other (galley's
## eight span two), while across the fix boundary they are 12-15 hours apart. An
## order of magnitude of headroom either side.
##
## DIAGNOSTIC ONLY. Nothing branches on this -- a stale atlas still resolves and
## still draws, and refusing to render it would be a worse outcome than rendering
## it wrongly. Each entry: {"visual", "colour", "slug", "behind_seconds"}.
func stale_colour_atlases() -> Array[Dictionary]:
	if not _loaded:
		load_all()

	var out: Array[Dictionary] = []
	for visual_id in _visuals:
		var decl: Dictionary = _visuals[visual_id]
		if not bool(decl.get("colours", false)):
			continue
		var base := str(decl.get("atlas", ""))
		if base.is_empty():
			continue

		# Newest across the base bake AND every colour, so a unit whose base was
		# never rebaked does not make its own colours look current.
		var newest: int = 0
		var times: Array[int] = []
		times.resize(_colour_slugs.size())
		if FileAccess.file_exists(base):
			newest = FileAccess.get_modified_time(base)
		for i in range(_colour_slugs.size()):
			var path := _tinted_path(base, _colour_slugs[i])
			times[i] = FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0
			newest = maxi(newest, times[i])
		if newest == 0:
			continue          # nothing staged for this visual at all

		for i in range(_colour_slugs.size()):
			if times[i] == 0:
				continue      # absent, which missing_colour_atlases() reports instead
			var behind := newest - times[i]
			if behind > COLOUR_STALENESS_SECONDS:
				out.append({
					"visual": visual_id,
					"colour": i,
					"slug": _colour_slugs[i],
					"behind_seconds": behind,
				})
	return out


## Each entry: {"visual": StringName, "colour": int, "slug": StringName}.
func missing_colour_atlases() -> Array[Dictionary]:
	if not _loaded:
		load_all()
	var out: Array[Dictionary] = []
	for visual_id in _visuals:
		var decl: Dictionary = _visuals[visual_id]
		if not bool(decl.get("colours", false)):
			continue
		var base := str(decl.get("atlas", ""))
		if base.is_empty() or not FileAccess.file_exists(base):
			continue          # pack not mounted; nothing to report
		for i in range(_colour_slugs.size()):
			if not FileAccess.file_exists(_tinted_path(base, _colour_slugs[i])):
				out.append({"visual": visual_id, "colour": i, "slug": _colour_slugs[i]})
	return out


## The placeholder an ID DECLARES, whether or not an atlas is currently mounted.
##
## atlas_for() deliberately hides which branch you got, but two callers need the
## declared fallback specifically: a debug toggle that draws placeholders over real
## art, and the tests -- which must assert the declared sizes are sane without
## depending on whether the art pack happens to be staged on this machine, since
## game/assets/atlases/ is gitignored and a fresh clone has none of it.
func placeholder_for(visual_id: StringName) -> PlaceholderSpec:
	if not _loaded:
		load_all()
	var ph: Variant = _visuals.get(visual_id, {}).get("placeholder")
	if ph is Dictionary:
		return PlaceholderSpec.from_dict(ph)
	return PlaceholderSpec.unknown()


## The visual ID for an ENTITY DEFINITION id -- `unit.villager` -> `vis.villager`.
##
## Two separate namespaces, and conflating them is a silent failure rather than a
## loud one: `atlas_for(&"unit.villager")` finds no entry and cheerfully returns the
## magenta unknown, so the game renders in placeholder colours and nothing reports
## an error. That is exactly what happened at 2.6 -- `GameView` was passing
## `def_id` straight through and every entity on screen was magenta.
##
## `phase` is a SimBuilding.Phase for buildings, which have three visuals rather
## than one (foundation / complete / rubble). Leave it at -1 for anything else, or
## for a building whose completed look is wanted regardless of state.
func visual_for(def_id: StringName, phase: int = -1) -> StringName:
	if not _loaded:
		load_all()

	var b: BuildingDef = _buildings.get(def_id)
	if b != null:
		return b.visual_for_phase(phase) if phase >= 0 else b.visual

	var u: UnitDef = _units.get(def_id)
	if u != null:
		return u.visual

	var r: ResourceDef = _resources.get(def_id)
	if r != null:
		return r.visual

	return &""


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


## Player colour by SimPlayer.colour index (PLAN.md 1). WRAPS rather than failing:
## colour is cosmetic and an out-of-range index must not be the thing that stops a
## match rendering -- the opposite call from unit()/building(), which return null
## because a missing definition has no sensible stand-in. Empty palette -> WHITE.
func colour(index: int) -> Color:
	if not _loaded:
		load_all()
	if _colours.is_empty():
		return Color.WHITE
	return _colours[posmod(index, _colours.size())]


func colour_count() -> int:
	if not _loaded:
		load_all()
	return _colours.size()


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

	_validate_skins()


## The `ages` map is DENSE by contract (PLAN.md 2.7.1): every age names a skin
## explicitly, and two ages that look the same point at the same file. A sparse
## map would still resolve -- a missing age falls through to the base atlas -- so
## nothing would go visibly wrong, which is exactly why it is worth failing the
## suite over rather than discovering in age 3 that a building never modernised.
func _validate_skins() -> void:
	var last_age := _ages.size()
	for visual_id in _visuals:
		var decl: Variant = _visuals[visual_id]
		if not decl is Dictionary:
			load_warnings.append("visuals.json entry '%s' is not an object" % visual_id)
			continue

		var ages: Variant = (decl as Dictionary).get("ages")
		if ages == null:
			continue
		if not ages is Dictionary:
			load_warnings.append("visual '%s' has an 'ages' that is not an object" % visual_id)
			continue

		var m: Dictionary = ages
		for age in range(1, last_age + 1):
			if not m.has(str(age)):
				load_warnings.append(
						"visual '%s' names no age-%d skin -- the map is dense by contract"
						% [visual_id, age])
		for key in m:
			var n := int(str(key))
			if n < 1 or n > last_age:
				load_warnings.append("visual '%s' names an age '%s' outside 1-%d"
						% [visual_id, key, last_age])


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


func _read_colours() -> void:
	_colours.clear()
	_colour_slugs.clear()
	var raw := _read_json(COLOURS_PATH)
	var list: Variant = raw.get(&"colours", [])
	if not list is Array:
		load_warnings.append("colours.json has no 'colours' list")
		return
	for i in range((list as Array).size()):
		var entry: Variant = list[i]
		if not entry is Dictionary:
			load_warnings.append("colours.json entry %d is not an object" % i)
			continue
		var hex := str((entry as Dictionary).get("hex", ""))
		# Godot's html_is_valid() rejects the malformed rather than silently
		# returning black, which would be a live player colour nobody chose.
		if not Color.html_is_valid(hex):
			load_warnings.append("colours.json entry %d has an invalid hex '%s'" % [i, hex])
			continue
		# Appended together so the two arrays cannot drift out of alignment -- a
		# slug at a different index than its Color would tint a player one colour
		# and give them another one's sprites.
		_colours.append(Color.html(hex))
		_colour_slugs.append(
				StringName(str((entry as Dictionary).get("id", "")).trim_prefix("colour.")))


## Cache key for one resolved skin. The bare visual_id for the no-skin case, so
## the overwhelmingly common lookup allocates nothing and the cache stays a plain
## StringName dictionary.
func _skin_key(visual_id: StringName, age: int, colour: int) -> StringName:
	if age <= 0 and colour < 0:
		return visual_id
	return StringName("%s|%d|%d" % [visual_id, age, colour])


## The atlas path for one skin, resolved in two independent steps so the two axes
## COMPOSE rather than needing an entry per combination (PLAN.md 2.7.1):
##
##   1. AGE picks the base bake, from the entry's dense `ages` map. Dense on
##      purpose -- every age names a skin explicitly and two ages that look the
##      same point at the same file, so the map answers "what does this look like
##      in age 3?" by being read, with no inheritance chain to trace.
##   2. COLOUR is a SUFFIX TRANSFORM on whatever step 1 chose, gated by the
##      entry's `colours` flag. isobake names a tinted bake `vis.<id>.<colour>`
##      (the atlas contract), so eight players are one boolean here rather than
##      eight declared paths per unit -- and the day buildings get tinted bakes
##      too, `vis.town_center_age3.blue` falls out of the same two steps with no
##      change to this function.
##
## A tint whose file is not staged falls back to the untinted bake rather than to
## the magenta unknown: an untinted unit is still playable, and
## missing_colour_atlases() is what makes the gap findable.
func _atlas_path_for_skin(decl: Dictionary, age: int, colour: int) -> String:
	var path := str(decl.get("atlas", ""))

	var ages: Variant = decl.get("ages")
	if age >= 1 and ages is Dictionary:
		var per_age := str((ages as Dictionary).get(str(age), ""))
		if not per_age.is_empty():
			path = per_age

	if colour >= 0 and bool(decl.get("colours", false)) and not path.is_empty():
		var tinted := _tinted_path(path, colour_slug(colour))
		if FileAccess.file_exists(tinted):
			return tinted

	return path


## `.../vis.villager.atlas.json` + `blue` -> `.../vis.villager.blue.atlas.json`.
func _tinted_path(path: String, slug: StringName) -> String:
	if slug.is_empty() or not path.ends_with(_ATLAS_SUFFIX):
		return path
	return path.substr(0, path.length() - _ATLAS_SUFFIX.length()) + ".%s%s" % [slug, _ATLAS_SUFFIX]


func _resolve(visual_id: StringName, age: int = 0, colour: int = -1) -> AtlasEntry:
	var decl: Dictionary = _visuals.get(visual_id, {})
	if decl.is_empty():
		load_warnings.append("no visuals.json entry for '%s'" % visual_id)
		return AtlasEntry.from_placeholder(visual_id, PlaceholderSpec.unknown())

	var atlas := _load_atlas(visual_id, _atlas_path_for_skin(decl, age, colour))
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
