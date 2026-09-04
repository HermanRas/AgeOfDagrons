## A map on disk (PLAN.md 11.3 / 2.4c): `map.png` plus a `map.json` sidecar.
##
## ⚠️ **THIS IS THE FORMAT PHASE 16'S MapMaker WRITES.** 11.3 was promoted for that reason —
## the tool's whole output is a map file, and building the tool first means inventing a
## second format and then reconciling two. The owner's ruling of 2026-09-01: *"2.4c will
## guide tool"*, so what is decided here is what MapMaker inherits, and we come back to it
## only if the tool finds a shortfall.
##
## ## THE PNG IS AUTHORITATIVE. THE SEED IS PROVENANCE.
##
## 11.3's third rule, and it is not a style preference — **a seed cannot reproduce a map.**
## `MapGenerator` uses `FastNoiseLite`, whose float maths is not guaranteed identical
## between an ARM phone and an x86 desktop, and any generator change makes the same seed
## produce something else. `MatchConfig` already sends the map and not the seed over the wire
## for exactly this reason. So the terrain is STORED, and `seed` is kept only to record how
## the map was originally made.
##
## ## WHY A PNG AND NOT JUST `MapData.to_dict()`
##
## `to_dict()` is the **wire** form and stays that: Godot's RPC layer encodes Variants in
## binary, so `terrain` rides as raw bytes and costs 20–40 KB. Through **JSON** the same
## field becomes the *text* `"[1, 2, 250]"` — a 192×192 map is 36,864 numbers, roughly 150 KB
## of digits and commas, for content that ships in packs and sits in git. A PNG of the same
## terrain is a few KB and lossless. **One encoding of entities, two encodings of terrain,
## each where it belongs.**
##
## The sidecar is therefore `to_dict()` MINUS `terrain`, plus 11.3's header — which works
## because `MapData.from_dict()` already treats an absent `terrain` as an empty one.
##
## ## HOW THE BYTES SIT IN THE IMAGE
##
## **`R` IS THE TERRAIN KIND AND IS THE ONLY CHANNEL THAT IS DATA.** `SimMap.Terrain` is
## seven values, so a kind fits a byte with room to spare, and reading one channel is exact
## and independent of any palette.
##
## `G` and `B` carry a cosmetic tint so the file still reads as a map when somebody opens it
## in an image viewer — 11.3's picker lists saved maps and a folder of near-black squares is
## unhelpable. **NEVER READ G OR B.** They are decoration, they may be restyled freely, and a
## loader that trusted them would silently reinterpret every map already saved the first time
## the palette changed. That is the trap `directions_reversed` was reverted twice to avoid:
## nothing in `game/` compensates for how art happens to look today.
##
## Bytes are read from `Image.get_data()` and never `get_pixel()`: a `Color` is floats, and
## `6 / 255.0` and back is an off-by-one waiting to happen on a value that indexes an enum.
class_name MapFile
extends RefCounted

## Bumped when the on-disk shape changes in a way an older reader would get wrong.
## Independent of `MapData.FORMAT_VERSION`, which versions the WIRE form.
const FORMAT_VERSION := 1

const TERRAIN_FILE := "map.png"
const META_FILE := "map.json"

## Cosmetic only — see the class comment. Green and blue per terrain kind, chosen so the
## saved image is recognisable rather than accurate.
const _TINT := {
	SimMap.Terrain.GRASS: [140, 60],
	SimMap.Terrain.DIRT: [110, 70],
	SimMap.Terrain.SAND: [205, 150],
	SimMap.Terrain.WATER_SHALLOW: [150, 210],
	SimMap.Terrain.WATER_DEEP: [80, 180],
	SimMap.Terrain.ROCK: [120, 120],
	SimMap.Terrain.FOREST: [80, 45],
}


static func exists_in(dir_path: String) -> bool:
	return FileAccess.file_exists(dir_path.path_join(TERRAIN_FILE)) \
			and FileAccess.file_exists(dir_path.path_join(META_FILE))


## Write `data` into `dir_path` as the pair. `header` carries 11.3's metadata — name, type,
## players, seed — and is merged over the derived fields, so a caller can label a map
## without this function knowing what a scenario or a skirmish is.
##
## Returns the problems; empty means written. Never pushes an error: a save can fail for
## ordinary reasons (a full disk, a read-only directory) and the caller is a UI that has to
## say so.
static func save(data: MapData, dir_path: String, header: Dictionary = {}) -> Array[String]:
	var problems: Array[String] = []
	if data == null or data.size.x <= 0 or data.size.y <= 0:
		problems.append("refusing to save an empty map")
		return problems
	var expected := data.size.x * data.size.y
	if data.terrain.size() != expected:
		problems.append("terrain is %d bytes for a %dx%d map, expected %d"
				% [data.terrain.size(), data.size.x, data.size.y, expected])
		return problems

	if DirAccess.make_dir_recursive_absolute(dir_path) != OK \
			and not DirAccess.dir_exists_absolute(dir_path):
		problems.append("cannot create %s" % dir_path)
		return problems

	var bytes := PackedByteArray()
	bytes.resize(expected * 3)
	for i in range(expected):
		var kind := int(data.terrain[i])
		var tint: Array = _TINT.get(kind, [0, 0])
		bytes[i * 3] = kind
		bytes[i * 3 + 1] = int(tint[0])
		bytes[i * 3 + 2] = int(tint[1])
	var img := Image.create_from_data(data.size.x, data.size.y, false,
			Image.FORMAT_RGB8, bytes)

	var png_path := dir_path.path_join(TERRAIN_FILE)
	if img.save_png(png_path) != OK:
		problems.append("could not write %s" % png_path)
		return problems

	# The sidecar is the wire form with terrain taken out -- see the class comment. Built
	# from `to_dict()` rather than re-listing the fields, so entities and starts have ONE
	# encoding and a change to either cannot leave the two out of step.
	# Named `side` and not `meta`: `to_dict()` already has a `meta` KEY (the map's own
	# metadata) and two things called meta in six lines is how the wrong one gets written.
	var side := data.to_dict()
	side.erase("terrain")
	side["format_version"] = FORMAT_VERSION
	side["created"] = Time.get_datetime_string_from_system(true)
	for k in header:
		side[k] = header[k]

	var json_path := dir_path.path_join(META_FILE)
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	if f == null:
		problems.append("could not write %s (error %d)" % [json_path, FileAccess.get_open_error()])
		return problems
	f.store_string(JSON.stringify(side, "  ", false))
	f.close()
	return problems


## Read the pair back out of `dir_path`. Null on anything it cannot trust, with the reason
## appended to `out_problems`.
##
## **A MAP FILE IS UNTRUSTED INPUT.** Authored maps arrive in content packs and saved ones
## sit in a `user://` directory the player can open, so this is as untrusted as a network
## packet — hence `JSON.new().parse()` rather than `JSON.parse_string()` (the static helper
## pushes an engine error per failure, which is a log somebody else can fill), and hence the
## size cross-check below rather than trusting either file about the other.
## The sidecar alone, parsed and version-checked, WITHOUT decoding the PNG (16.0).
##
## ## WHY THIS EXISTS RATHER THAN CALLING `load_map()` AND READING `.meta`
##
## A picker listing saved maps needs a name, a size and a player count per row, and
## `load_map()` would charge a **192x192 PNG decode per entry** to get them. The sidecar is
## `to_dict()` with terrain taken out, so it already carries `w`, `h`, `starts`, `entities`
## and `meta` -- every figure a list needs, in a file measured in kilobytes. So a folder of
## fifty maps costs fifty small JSON parses instead of fifty decodes, and the full load
## happens once, when one of them is actually chosen.
##
## Same reasoning as `ScenarioScreen._why_not_playable()` declining to call `build_config()`
## for a row the player is merely looking at: browsing must not cost what committing costs.
##
## ⚠️ **THE PNG IS STILL THE AUTHORITY ON THE MAP** (see the class comment) and this function
## never contradicts that -- it answers questions ABOUT a map, never hands one back. It
## deliberately does NOT check that the PNG exists or that its dimensions agree with `w`/`h`;
## `load_map()` owns both, and duplicating them here would be a second opinion to keep in
## step. **A row this returns may therefore still fail to load**, which is why every caller
## surfaces `load_map`'s problems rather than assuming a listed map is a loadable one.
static func read_header(dir_path: String, out_problems: Array[String]) -> Dictionary:
	var json_path := dir_path.path_join(META_FILE)
	if not FileAccess.file_exists(json_path):
		out_problems.append("%s does not exist" % json_path)
		return {}
	return _parse_sidecar(json_path, out_problems)


static func load_map(dir_path: String, out_problems: Array[String]) -> MapData:
	var png_path := dir_path.path_join(TERRAIN_FILE)
	var json_path := dir_path.path_join(META_FILE)
	if not FileAccess.file_exists(json_path):
		out_problems.append("%s does not exist" % json_path)
		return null
	if not FileAccess.file_exists(png_path):
		out_problems.append("%s does not exist" % png_path)
		return null

	var d := _parse_sidecar(json_path, out_problems)
	if d.is_empty():
		return null

	var img := Image.load_from_file(png_path)
	if img == null or img.is_empty():
		out_problems.append("%s is not a readable image" % png_path)
		return null
	# Converted explicitly: a PNG may load as RGBA8 or as an indexed form, and the stride
	# below is only right for RGB8.
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)

	var data := MapData.from_dict(d)
	# The sidecar carries `w`/`h` and the image carries its own dimensions. THEY MUST AGREE:
	# disagreeing means the pair has been edited apart, and picking one would silently place
	# every entity on the wrong tile.
	if data.size != Vector2i(img.get_width(), img.get_height()):
		out_problems.append("%s is %dx%d but %s says %dx%d"
				% [TERRAIN_FILE, img.get_width(), img.get_height(), META_FILE,
				data.size.x, data.size.y])
		return null

	var count := img.get_width() * img.get_height()
	var raw := img.get_data()
	if raw.size() < count * 3:
		out_problems.append("%s holds %d bytes for %d pixels" % [png_path, raw.size(), count])
		return null

	var terrain := PackedByteArray()
	terrain.resize(count)
	var highest := SimMap.Terrain.size() - 1
	for i in range(count):
		# R ONLY. G and B are decoration -- see the class comment.
		var kind := int(raw[i * 3])
		if kind > highest:
			out_problems.append("%s pixel %d is terrain %d; this build knows 0..%d"
					% [TERRAIN_FILE, i, kind, highest])
			return null
		terrain[i] = kind
	data.terrain = terrain
	return data


## Read, parse and version-check `map.json`. `{}` on anything untrustworthy, with the
## reason appended.
##
## Shared by `load_map()` and `read_header()` so the two cannot come to disagree about what
## a readable sidecar is -- and in particular so that **a version this build cannot read is
## refused in both directions.** A picker that listed a version-2 map because only the full
## loader checked would offer a row that fails the moment it is pressed.
##
## **`{}` UNAMBIGUOUSLY MEANS FAILURE**, and that is a property of the format rather than a
## convention: `save()` always writes `format_version`, and the check below rejects a
## sidecar without one (absent reads as 0, which is never `FORMAT_VERSION`). So there is no
## such thing as a valid empty sidecar for this to be confused with.
static func _parse_sidecar(json_path: String, out_problems: Array[String]) -> Dictionary:
	var text := FileAccess.get_file_as_string(json_path)
	if text.is_empty():
		out_problems.append("%s is empty or unreadable" % json_path)
		return {}
	# `JSON.new().parse()` rather than the static `JSON.parse_string()`: a map file is
	# untrusted input (see the class comment) and the static helper pushes an engine error
	# per failure, which is a log somebody else gets to fill.
	var json := JSON.new()
	if json.parse(text) != OK:
		out_problems.append("%s: line %d: %s"
				% [json_path, json.get_error_line(), json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		out_problems.append("%s is not a JSON object" % json_path)
		return {}
	var d: Dictionary = json.data

	# REFUSED RATHER THAN GUESSED. A future format may move terrain, change the channel or
	# add a layer, and a reader that pressed on regardless would produce a map that is wrong
	# in a way nothing on screen explains.
	var version := int(d.get("format_version", 0))
	if version != FORMAT_VERSION:
		out_problems.append("%s is format_version %d; this build reads %d"
				% [json_path, version, FORMAT_VERSION])
		return {}
	return d
