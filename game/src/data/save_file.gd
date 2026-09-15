## Saved GAMES on disk -- writing one, listing them, reading one back (PLAN.md 12.4).
##
## `SaveGame` decides WHAT a saved match is; this decides where it lives and how a picker
## finds it. The split is `MapData`/`MapFile`'s, one format further on.
##
## ## ⛔ `user://saves/`, AND IT IS A THIRD DIRECTORY ON PURPOSE
##
## Not `user://maps/` (the player's saved MAPS, 11.3) and not `user://content/` (things a pack
## installed, 0.3). Three roots, three owners, and the rule that separates them is 11.3's:
## **installing or replacing content must never overwrite somebody's save, and uninstalling it
## must never delete one.** A saved game is the most irreplaceable thing on the device -- it is
## the only one that cannot be re-downloaded or re-authored -- so it sits where no installer
## has any business writing.
##
## ## ⚠️ LISTING IS CHEAP, AND THAT IS WHY THERE IS A SIDECAR
##
## `SavedMaps`' argument, and it bites harder here: a saved match is a few hundred KB of JSON,
## and a picker that parsed every one to draw a row would stall a menu for a second on a phone
## with twenty saves on it. So each save is two files:
##
##   - `<slug>.save.json` -- the match, written by `SaveGame.capture()`;
##   - `<slug>.meta.json` -- a few hundred bytes: the name, the tick, who was playing.
##
## **Therefore a listed save may still fail to load**, exactly as a listed map may -- the
## header is not proof that the body parses, and callers surface `read()`'s problems rather
## than treating a row's presence as a guarantee. The sidecar is a second file and not a second
## source of truth: everything in it is a COPY of something in the save, written in the same
## call, and nothing ever reads it to decide anything about the match itself.
##
## Plain `RefCounted` and not an autoload -- `SavedMaps`' and `Campaigns`' precedent.
class_name SaveFile
extends RefCounted

## Where saved games live. See the class comment: deliberately its own root.
const ROOT := "user://saves/"

const SAVE_SUFFIX := ".save.json"
const META_SUFFIX := ".meta.json"

## Long enough to be a sentence, short enough to be a filename.
const MAX_NAME := 64


## Write `world` to `ROOT` under `name`. Returns the complaints; empty means it is on disk.
##
## An existing save of the same name is REPLACED, which is what a player pressing Save on a
## slot they have used before means. The body is written before the sidecar, so a crash
## between the two leaves a save that does not list rather than a row that cannot load -- the
## same ordering argument `PackInstaller` makes for recording an install last.
static func write(world: SimWorld, cfg: MatchConfig, name: String) -> Array[String]:
	var problems: Array[String] = []
	if world == null or cfg == null:
		problems.append("there is no match to save")
		return problems
	var slug := slugify(name)
	if slug.is_empty():
		problems.append("'%s' has no letters or digits in it to name a file with" % name)
		return problems

	DirAccess.make_dir_recursive_absolute(ROOT)
	var body := SaveGame.capture(world, cfg)
	var wrote := _write_json(ROOT.path_join(slug + SAVE_SUFFIX), body)
	if not wrote.is_empty():
		problems.append(wrote)
		return problems

	var meta := _header_of(body, world, cfg, name, slug)
	var meta_wrote := _write_json(ROOT.path_join(slug + META_SUFFIX), meta)
	if not meta_wrote.is_empty():
		# The match IS saved; only its row is missing. Said out loud rather than swallowed,
		# because the symptom is a save that exists and cannot be found.
		problems.append("the match was saved but its listing entry was not: %s" % meta_wrote)
	return problems


## Every save on disk, newest first. Reads only the sidecars -- see the class comment.
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(ROOT)
	if dir == null:
		return out                      # nothing saved yet is not a problem
	for file in dir.get_files():
		if not file.ends_with(META_SUFFIX):
			continue
		var slug := file.substr(0, file.length() - META_SUFFIX.length())
		var raw: Variant = _read_json(ROOT.path_join(file))
		if not raw is Dictionary:
			continue                    # a corrupt sidecar costs one row, not the list
		var row: Dictionary = raw
		row["slug"] = slug
		# A row whose body is gone is not offered at all: the picker's whole job is to list
		# things that can be played.
		if not FileAccess.file_exists(ROOT.path_join(slug + SAVE_SUFFIX)):
			continue
		out.append(row)
	# Newest first, which is the order a player wants: the save they just made is the one they
	# are most likely to want back.
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("saved_at", 0)) > int(b.get("saved_at", 0)))
	return out


## The saved match itself, ready for `SaveGame.apply()`. Empty on failure, with the complaint
## in `out_problems` -- `MapFile.load_map`'s shape.
static func read(slug: String, out_problems: Array[String]) -> Dictionary:
	var path := ROOT.path_join(slug + SAVE_SUFFIX)
	if not FileAccess.file_exists(path):
		out_problems.append("there is no save called '%s'" % slug)
		return {}
	var raw: Variant = _read_json(path)
	if not raw is Dictionary:
		out_problems.append("'%s' is not a saved match this build can read" % slug)
		return {}
	return raw


## The `MatchConfig` a save was made under -- the half of the file the world is REBUILT from,
## before `SaveGame.apply()` overwrites what mutated. Null if the file does not carry one.
static func config_of(save: Dictionary) -> MatchConfig:
	var raw: Variant = save.get("config", {})
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return null
	return MatchConfig.from_dict(raw)


## Remove a save and its row. Both files, because a body with no sidecar is invisible and a
## sidecar with no body is a row that cannot be played.
static func erase(slug: String) -> bool:
	var gone := false
	for suffix in [SAVE_SUFFIX, META_SUFFIX]:
		var path := ROOT.path_join(slug + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			gone = true
	return gone


## A filename from a player's words. Lowercase, letters digits and dashes, nothing that can
## climb out of `ROOT` -- `PackDef._is_safe_segment()`'s whitelist argument: naming what IS
## allowed is the only version of this check that an encoding nobody thought of cannot get
## past. A name that survives to nothing is refused by the caller rather than guessed at.
static func slugify(name: String) -> String:
	var out := ""
	var previous_dash := false
	for i in name.strip_edges().to_lower().length():
		var c := name.strip_edges().to_lower()[i]
		var ok := (c >= "a" and c <= "z") or (c >= "0" and c <= "9")
		if ok:
			out += c
			previous_dash = false
		elif not previous_dash and not out.is_empty():
			out += "-"
			previous_dash = true
		if out.length() >= MAX_NAME:
			break
	while out.ends_with("-"):
		out = out.substr(0, out.length() - 1)
	return out


## What a picker's row needs, and nothing a row does not: a copy, never consulted about the
## match itself. See the class comment.
static func _header_of(body: Dictionary, world: SimWorld, cfg: MatchConfig,
		name: String, slug: String) -> Dictionary:
	var names: Array[String] = []
	for p in world.players:
		names.append("%s%s" % [("AI " if p.is_ai else ""), str(p.id)])
	return {
		"format_version": int(body.get("format_version", SaveGame.FORMAT_VERSION)),
		"name": name.strip_edges(), "slug": slug,
		# `Time` is fine here and would not be in `src/sim`: this is a fact about the DEVICE,
		# not about the match, and nothing in the simulation may read a clock.
		"saved_at": int(Time.get_unix_time_from_system()),
		"tick": world.tick,
		"mode": int(cfg.mode),
		"players": names,
		"map_size": [world.map.size.x, world.map.size.y] if world.map != null else [0, 0],
	}


static func _write_json(path: String, value: Dictionary) -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "cannot write %s (error %d)" % [path, FileAccess.get_open_error()]
	f.store_string(JSON.stringify(value))
	f.close()
	return ""


static func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	return JSON.parse_string(text)
