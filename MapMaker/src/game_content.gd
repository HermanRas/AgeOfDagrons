## The roster, read live out of the game's `data/*.json` (PLAN.md §16 decision 2).
##
## ⚠️ **THIS IS REGISTERED AS THE AUTOLOAD `GameDataRegistry`, AND THE NAME IS THE WHOLE
## TRICK.** `format/map_data.gd` is a verbatim copy of the game's, and it calls
## `GameDataRegistry.building(id)` and `GameDataRegistry.resource_def(id)` to find footprints.
## By answering to the same identifier, this tool's own object satisfies those calls — so the
## copy needs no edit, stays byte-identical to the original, and therefore stays HASHABLE by
## `FormatGuard`. An edited copy could never be checked against anything.
##
## It is a small fraction of the game's 1,600-line registry, on purpose: what MapMaker needs
## is *what is placeable and how big it is*, not validation, atlases, techs, ages or the
## market. Anything beyond that belongs on the game side of the fence.
##
## ## NOTHING IS DUPLICATED, SO THE PALETTE CANNOT DRIFT FROM THE ROSTER
##
## The files are read from the game project every time the tool starts. Add a building to
## `buildings.json` and it is in the palette next launch with no step in between — which is
## the argument in `MapMaker/README.md` (*"Nothing is duplicated, so the palette cannot drift
## out of step with the game's roster"*), and it is why the roster is READ rather than
## exported.
##
## ## WHAT IS TYPED AND WHAT IS NOT, AND WHY THAT IS NOT LAZINESS
##
## Buildings and resources become real `BuildingDef`/`ResourceDef` objects, because
## `map_data.gd` asks them for `footprint` and `footprint_for_size()` and those two are what
## decide whether a placement overlaps.
##
## **Units stay raw dictionaries.** `UnitDef` is a large file with a large dependency
## surface, and the format does not need it at all: a unit claims no tiles in the grid, so
## `MapData.footprint_rect_of()` falls through to 1x1 for anything that is neither a building
## nor a resource. The palette needs a name and an icon id, and both are fields in the JSON.
## **If 16.3 turns out to need something only `UnitDef` computes, the answer is to copy
## `unit_def.gd` into `format/` and add it to `FormatGuard.COPIES`** — not to re-derive that
## field here, which would be a second opinion about the roster.
##
## Not an autoload with a `class_name`: that would shadow the singleton identifier, which is
## the game's own rule for all five of its autoloads (PLAN.md §6.1).
extends Node

const UNITS_FILE := "units.json"
const BUILDINGS_FILE := "buildings.json"
const RESOURCES_FILE := "resources.json"

## ⚠️ **KEYS STARTING WITH THIS ARE DOCUMENTATION INSIDE THE JSON, NOT ENTRIES**, and
## skipping them is not optional. The game's `data/*.json` files carry long `_note` blocks
## that are *the real design record for the data* (AGENT_GAME_CODER.md §2) — several encode
## measurements that are expensive to re-derive. They are strings where an entry would be an
## object, so a reader that does not skip them reports two warnings on a perfectly good
## roster.
##
## **This was found by the test, not by reading the game first**, which is the argument for
## mirroring `GameDataRegistry._read_json` line for line rather than writing a fresh loader:
## the convention is invisible in the JSON's shape and obvious in the code that reads it.
const _COMMENT_PREFIX := "_"

## Every complaint from `load_from()`, in the order found. A tool that cannot read a roster
## must say which file and why -- the person running it has the file open in the next window.
var load_warnings: Array[String] = []

var _buildings: Dictionary = {}                   # StringName -> BuildingDef
var _resources: Dictionary = {}                   # StringName -> ResourceDef
var _units: Dictionary = {}                       # StringName -> Dictionary (raw)
var _loaded := false


## Read the roster out of `root`. False if nothing usable came back.
##
## Called explicitly rather than from `_ready()`, because the game root has to be resolved
## first and a failure there is a message for a person -- an autoload that silently loaded
## nothing at boot would leave every later count reading zero with no reason attached.
func load_from(root: GameRoot) -> bool:
	load_warnings.clear()
	_buildings.clear()
	_resources.clear()
	_units.clear()
	_read_raw_cache.clear()
	_loaded = false

	if root == null or root.path.is_empty():
		load_warnings.append("no game project to read")
		return false

	_buildings = _read_defs(root.data_path(BUILDINGS_FILE), BuildingDef.from_dict)
	_resources = _read_defs(root.data_path(RESOURCES_FILE), ResourceDef.from_dict)
	_units = _read_raw(root.data_path(UNITS_FILE))
	_loaded = not (_buildings.is_empty() and _resources.is_empty() and _units.is_empty())
	return _loaded


func is_loaded() -> bool:
	return _loaded


# ── what `format/map_data.gd` calls ─────────────────────────────────────────
#
# These two signatures are fixed by the copy and are not ours to rename. **Null for an
# unknown id**, which is the game registry's own rule and the opposite of `atlas_for()`: a
# missing sprite has a sensible stand-in, a missing definition does not.

func building(id: StringName) -> BuildingDef:
	return _buildings.get(id)


func resource_def(id: StringName) -> ResourceDef:
	return _resources.get(id)


# ── what the palette will ask (16.3) ────────────────────────────────────────

## ⚠️ **SORTED AS TEXT, EXPLICITLY.** `Array[StringName].sort()` orders by identity rather
## than by spelling, and not stably between runs -- PLAN.md 16.3 carries the warning, and a
## palette that reshuffles itself between launches looks broken. So keys are cast to String
## before sorting, and every one of these three goes through the same helper.
func building_ids() -> Array[StringName]:
	return _sorted_keys(_buildings)


func resource_ids() -> Array[StringName]:
	return _sorted_keys(_resources)


func unit_ids() -> Array[StringName]:
	return _sorted_keys(_units)


## A unit's raw JSON, or `{}`. See the class comment for why these are not typed.
func unit_raw(id: StringName) -> Dictionary:
	var entry: Variant = _units.get(id, {})
	return entry if entry is Dictionary else {}


## What to show in a list: the roster's `name`, falling back to the id.
##
## One function for all three categories, because a palette row does not care which file an
## entry came from -- and because a label falling back to "" is a row nobody can pick, which
## is the same trap `SavedMaps._name_in` covers on the game side.
##
## ⚠️ **READ OFF THE RAW JSON AND NOT OFF THE DEF, BECAUSE `ResourceDef` HAS NO `name`
## FIELD.** `BuildingDef` does; `ResourceDef` does not, and reaching for `.name` on it
## compiles and returns the *Object* name at runtime rather than failing, which would have
## put "RefCounted" in the palette next to every tree. Going through the JSON is the one
## route that is true for all three files, and it costs nothing -- the parse is cached.
func display_name(id: StringName) -> String:
	for path in _read_raw_cache:
		var entry: Variant = (_read_raw_cache[path] as Dictionary).get(id)
		if entry is Dictionary:
			var label := str((entry as Dictionary).get("name", "")).strip_edges()
			if not label.is_empty():
				return label
	return String(id)


## The terrain kinds a brush can paint, in `SimMap.Terrain` order.
##
## FROM THE ENUM, never a written-out list: `sim_map.gd` is the authority on its own terrain
## and a second copy here is the drift `FormatGuard` exists to prevent. The order is the enum
## order, which is also the byte written into `map.png`'s red channel.
func terrain_kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for key in SimMap.Terrain.keys():
		out.append(StringName(key))
	return out


# ── reading ─────────────────────────────────────────────────────────────────

## `GameDataRegistry._read_defs`' shape, deliberately: one factory per file, an entry that is
## not an object is a named warning rather than a crash.
func _read_defs(path: String, factory: Callable) -> Dictionary:
	var out: Dictionary = {}
	var raw := _read_raw(path)
	for id in raw:
		var entry: Variant = raw[id]
		if entry is Dictionary:
			out[id] = factory.call(id, entry)
		else:
			load_warnings.append("entry '%s' in %s is not an object" % [id, path])
	return out


## Parsed files, so reading the same one twice costs one parse. Cleared with everything else
## in `load_from()`, since a reload is the point at which the files may have changed.
var _read_raw_cache: Dictionary = {}


## A JSON object keyed by id, or `{}` with a warning.
##
## **A MAP-MAKER READS THE GAME'S FILES AS UNTRUSTED INPUT** for the same reason `MapFile`
## does: they are edited by hand, by two agents and by the owner, and a parse error must name
## the file and the line rather than take the tool down. `JSON.new().parse()` and not the
## static helper, which pushes an engine error per failure.
func _read_raw(path: String) -> Dictionary:
	if _read_raw_cache.has(path):
		return _read_raw_cache[path]
	var out: Dictionary = {}
	if not FileAccess.file_exists(path):
		load_warnings.append("%s does not exist" % path)
	else:
		var text := FileAccess.get_file_as_string(path)
		var json := JSON.new()
		if json.parse(text) != OK:
			load_warnings.append("%s: line %d: %s"
					% [path, json.get_error_line(), json.get_error_message()])
		elif not json.data is Dictionary:
			load_warnings.append("%s is not a JSON object" % path)
		else:
			# `GameDataRegistry._read_json`'s two steps, mirrored rather than reinvented:
			# drop the `_note` documentation keys, and key the result by `StringName`, which
			# is what every id in this project and in the game is. JSON hands back String
			# keys; a Dictionary will match a StringName against one, so this is about being
			# the same shape as the game rather than about lookups failing.
			for key in json.data:
				var k := str(key)
				if k.begins_with(_COMMENT_PREFIX):
					continue
				out[StringName(k)] = (json.data as Dictionary)[key]
	_read_raw_cache[path] = out
	return out


func _sorted_keys(d: Dictionary) -> Array[StringName]:
	var names: Array[String] = []
	for k in d:
		names.append(String(k))
	names.sort()
	var out: Array[StringName] = []
	for n in names:
		out.append(StringName(n))
	return out
