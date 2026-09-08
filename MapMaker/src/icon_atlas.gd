## A palette icon: one def id cropped out of the entity's own baked battle sprite, read from
## the GAME's staged atlases (PLAN.md 16.3).
##
## ## `load()` CANNOT OPEN THESE FILES, AND THAT IS THE WHOLE REASON THIS CLASS EXISTS
##
## ⚠️ The game crops the same frames with `EntityPortrait.frame_for()`, which ends in
## `AtlasEntry.texture(page)` → `ResourceLoader.exists()` → `load()`. Neither of those works
## from here, and **the reason is not the one it is natural to assume.** Measured on 4.7.1
## against `game/assets/atlases/vis.villager_0.png`:
##
##     FileAccess.file_exists    true
##     ResourceLoader.exists     TRUE          <- not a usable guard
##     load()                    null, + THREE engine errors
##     Image.load_from_file      1024x2048     <- works
##
## Phase 15's note on campaign artwork says *"outside `res://` there is no `.import` sidecar and
## `load()` cannot open them at all"*, and that is **not what is happening here**: these PNGs
## live inside the GAME's `res://` and the game has imported them, so a sidecar exists. What
## the sidecar says is that the real resource is at `res://.godot/imported/vis.villager_0.png-<hash>.ctex`
## — and `res://` from this project is **MapMaker**, whose import cache has no such file. So
## `load()` follows a redirect into the wrong project and fails.
##
## **That is worse than a missing sidecar, not better.** A file with no loader fails quietly;
## this one pushes *"Unable to open file"*, *"Failed loading resource"* twice, and returns null
## — three engine errors **per page, per attempt**, which `ScriptErrorSpy` does not catch
## because they are ERRORs and not SCRIPT ERRORs. A palette redraws on every keystroke in the
## search box.
##
## Hence: `Image.load_from_file()` plus `ImageTexture.create_from_image()`, and
## **`AtlasEntry.texture()` is never called** — this class reads `AtlasEntry.pages`, which is a
## `PackedStringArray` of paths. `ResourceLoader.exists()` must not be used as a guard here
## either; it answers true for a file `load()` cannot open.
##
## The copy stays verbatim and therefore checkable, and the one method in it this tool must not
## use simply goes uncalled.
##
## ## WHAT IS A COPY AND WHAT IS A SECOND OPINION, STATED PLAINLY
##
## `format/atlas_entry.gd` is a verbatim copy: it knows the direction-major index formula
## (PLAN.md 9.1), the flip table, and `_ANIM_ALIAS`. Re-deriving that by hand is how a palette
## ends up showing frame 0 of `die`.
##
## **What IS re-implemented here is `GameDataRegistry._atlas_path_for_skin()`'s two steps** —
## age picks the base bake from a dense `ages` map, colour is a suffix transform gated by a
## `colours` flag (PLAN.md 2.7.1). That is a second opinion and it is worth naming as one. It
## is acceptable *here and nowhere else in this tool* because *the cost of getting it wrong is
## a wrong picture*: an author sees an age-1 house where an age-3 one was meant. Nothing this
## class computes reaches `map.json`. The alternative was copying the game's 1,600-line
## registry and its dependency surface to resolve an icon.
##
## ## A MISSING ATLAS IS THE NORMAL STATE AND MUST NOT LOOK LIKE A FAULT
##
## ⚠️ **`game/assets/atlases/` IS GITIGNORED STAGED ART.** It is on the owner's machine and
## absent from a clean clone, so *a tool that will not open without it is a tool that cannot be
## handed to anybody* (16.3's row). Every failure here therefore lands on the same answer:
## `crop_for()` returns `{}`, and the caller draws a **lettered plate** —
## `CampaignScreen`'s answer for a missing icon and `atlas_for()`'s totality rule applied one
## project over.
##
## Nothing is warned about twice: `warnings` collects one sentence per *visual id* that could
## not be resolved, so a palette of 32 buildings with no atlases at all reports 32 lines and
## not 32 per redraw.
class_name IconAtlas
extends RefCounted

## The game's own file. Read live, never copied — same rule as the roster.
const VISUALS_FILE := "visuals.json"
const COLOURS_FILE := "colours.json"

## `GameDataRegistry._ATLAS_SUFFIX`.
const _ATLAS_SUFFIX := ".atlas.json"

## The clip to crop from, and the facing. **Facing 0 is S** (`AtlasEntry.FACINGS`), which is
## the pose a player sees a unit in most often — `EntityPortrait.frame_for()` picks the same
## one and for the same reason.
const _ICON_ANIM := &"idle"
const _ICON_FACING := 0

## One sentence per visual id that could not be resolved. **Never printed from here**: a clean
## clone has no atlases at all, so this list is 300 lines long in a perfectly good checkout and
## a class that printed it would be the noise nobody reads.
var warnings: Array[String] = []

## Pretend no atlas is staged, so every caller takes the lettered-plate path.
##
## ⚠️ **IT EXISTS BECAUSE THE PLATE PATH IS A REQUIREMENT THIS MACHINE NEVER TAKES.** 16.3's
## row is explicit — *"a palette that finds no atlases must draw lettered plates and carry
## on"*, because `game/assets/atlases/` is gitignored staged art and a clean clone has none.
## The owner's machine has all 139, so **the fallback that every other developer will see
## first is the one nobody here can look at**, and §5's rule is that a check blind to a fault
## is worse than no check: the plate arithmetic has tests, and whether a monogram is centred
## and legible on the colour `visuals.json` declares is a question for eyes.
##
## `LanBrowser.include_self` is the precedent and the wording transfers: this is for the
## preview and the tests and for nothing else. **Never set from the editor** — a palette that
## could be told to hide the art would be a setting somebody leaves on.
##
## **The setter drops the resolved-entry cache**, and it has to: `_entries` holds whichever
## branch the flag chose last time, so flipping it without clearing would leave the palette
## drawing the art it had already parsed and report that the fallback works when nothing had
## changed. Exactly the shape of §5's *"a green check on a fault it cannot express"*.
var ignore_atlases := false:
	set(value):
		ignore_atlases = value
		_entries.clear()

var _root: GameRoot = null
var _visuals: Dictionary = {}
var _colour_slugs: Array[StringName] = []

## visual id + skin -> `AtlasEntry`, so paging the palette does not re-parse a 960-frame atlas
## per redraw. Keyed exactly as the game keys it (`_skin_key`'s shape).
var _entries: Dictionary = {}

## `colours.json`'s list, verbatim, for `colours()`.
var _colours: Array = []

## Parsed files, so reading one twice costs one parse. Cleared with everything else in
## `load_from()`, which is the point at which the files may have changed.
var _raw_cache: Dictionary = {}

## Page path -> `ImageTexture`. **Separate from `_entries` and keyed by PATH**, because two
## visual ids routinely name the same atlas page (`vis.dragon_baby` and `vis.dragon_rigged` are
## the documented pair) and decoding a 4096² PNG twice is the one expensive thing here.
var _textures: Dictionary = {}


## Read `visuals.json` and `colours.json` out of the game project. False when neither could be
## read — which is not fatal to anything: the palette then draws lettered plates.
func load_from(root: GameRoot) -> bool:
	warnings.clear()
	_visuals.clear()
	_colour_slugs.clear()
	_colours.clear()
	_entries.clear()
	_textures.clear()
	_raw_cache.clear()
	_root = root
	if root == null or root.path.is_empty():
		warnings.append("no game project to read visuals from")
		return false

	_visuals = _read_json(root.data_path(VISUALS_FILE))
	_read_colours(root.data_path(COLOURS_FILE))
	return not _visuals.is_empty()


func is_loaded() -> bool:
	return not _visuals.is_empty()


## Every visual id `visuals.json` declares, sorted as text.
##
## **Sorted as TEXT and not with `Array[StringName].sort()`**, §6's rule: identity order is not
## stable between runs. Nothing draws from this list — it is here so a test can assert that the
## `_note` documentation keys were skipped, which is the trap that cost a red run when
## `game_content.gd` was written and would be invisible in the JSON's shape.
func declared_ids() -> Array[StringName]:
	var names: Array[String] = []
	for k in _visuals:
		names.append(String(k))
	names.sort()
	var out: Array[StringName] = []
	for n in names:
		out.append(StringName(n))
	return out


## How many visual ids the game declares, and how many of those have an atlas staged here.
##
## **16.1's rule one row later** — *"if that number is wrong, nothing built on top of it can be
## right"*. Two numbers rather than one, because they answer different questions: `declared`
## says whether `visuals.json` was read at all, and `staged` says whether this machine has the
## art. A clean clone is `{declared: 300, staged: 0}` and is working correctly.
func counts() -> Dictionary:
	var staged := 0
	for visual_id in _visuals:
		var path := _atlas_path_for_skin(_visuals[visual_id], 0, -1)
		if not path.is_empty() and FileAccess.file_exists(_absolute(path)):
			staged += 1
	return {"declared": _visuals.size(), "staged": staged}


# ── the crop ────────────────────────────────────────────────────────────────

## `{texture, rect}` for `def_id`, or `{}` when there is nothing to crop.
##
## `age` and `colour` take `GameDataRegistry.atlas_for()`'s order and defaults, so a caller
## never has to remember which way round this one goes. `size_class` is the resource axis —
## `ResourceDef.visual_for_size()` — and is ignored by everything else.
##
## `{}` is a legitimate, expected answer: see the class comment.
func crop_for(def_id: StringName, age := 0, colour := -1, size_class := 0) -> Dictionary:
	var visual_id := visual_for(def_id, size_class)
	if visual_id.is_empty():
		return {}
	var entry := entry_for(visual_id, age, colour)
	if entry == null or entry.is_placeholder:
		return {}

	var f := entry.frame_at(_ICON_ANIM, _ICON_FACING, 0)
	if f.is_empty():
		return {}
	var tex := _texture_for(entry, int(f["page"]))
	if tex == null:
		return {}
	var rect: Rect2i = f["rect"]
	return {"texture": tex, "rect": Rect2(rect.position, rect.size)}


## The colour a lettered plate should be for `def_id`. **Total — it always answers**, which is
## `atlas_for()`'s own rule one project over: a caller that has to branch on a missing answer
## is a caller with two drawing paths, and the second one never gets looked at.
##
## ⚠️ **THE LETTERED PLATE IS TINTED FROM THE ART'S OWN PLACEHOLDER, NOT FROM A PALETTE OF
## GUESSES.** `visuals.json` already states what colour each thing roughly is — that is what
## `PlaceholderSpec.color` is for, and the game draws it when a bake is missing. So a clean
## clone's palette comes out green for trees and pale for houses instead of a wall of identical
## grey squares, with no second opinion about what a tree looks like. **`UNKNOWN_COLOR` is
## magenta and stays magenta**: an id with no entry at all should look like a bug.
func plate_colour(def_id: StringName, size_class := 0) -> Color:
	var visual_id := visual_for(def_id, size_class)
	# ⚠️ **READ STRAIGHT OFF THE DECLARATION, NOT THROUGH `entry_for()`.** The first version
	# asked for the resolved `AtlasEntry` and read `entry.placeholder` — which is **null
	# whenever a real atlas was found**, because the two are the resolver's either/or branches.
	# So it answered `{}` for every subject that HAS art and a colour for every subject that
	# does not, which is backwards from useful: the caller needs it in the one case a resolved
	# atlas still yields no crop (an atlas with no `idle` clip), and the plate would then have
	# come out the default grey. Caught by a test whose premise was that the villager — the
	# best-baked thing in the game — has a declared colour. It does.
	var decl: Variant = _visuals.get(visual_id) if not visual_id.is_empty() else null
	if decl is Dictionary:
		var ph: Variant = (decl as Dictionary).get("placeholder")
		if ph is Dictionary:
			return PlaceholderSpec.from_dict(ph).color
	# ⚠️ **NO VISUAL, NO ENTRY, OR AN ENTRY WITH NO PLACEHOLDER BLOCK: THE LOUD MAGENTA.**
	# `PlaceholderSpec.unknown()`'s comment says why — it should look like a bug, because it is
	# one — and the game reaches the same answer by the same route: `visual_for()` returns `&""`
	# for an id that is neither a def nor a declared visual, `atlas_for(&"")` finds no entry,
	# and the magenta placeholder is what draws. **Grey would have been the wrong answer here**
	# and was the first one: it is indistinguishable from "declared, with no placeholder", so a
	# typo'd def id would have sat in the palette looking like ordinary missing art.
	return PlaceholderSpec.UNKNOWN_COLOR


## def id -> visual id. `GameDataRegistry.visual_for()`'s three branches, against this tool's
## roster: a building's `visual`, a resource's `visual_for_size`, a unit's raw `visual` field.
##
## **The unit branch reads raw JSON because units are raw dictionaries here** — `game_content.gd`
## explains why, and the day something needs more than a field lookup the answer is to copy
## `unit_def.gd` in properly rather than re-derive it.
##
## An id that is ALREADY a visual resolves to itself, which is the game's own fallthrough and
## costs one line.
func visual_for(def_id: StringName, size_class := 0) -> StringName:
	var bd: BuildingDef = GameDataRegistry.building(def_id)
	if bd != null:
		return bd.visual
	var rd: ResourceDef = GameDataRegistry.resource_def(def_id)
	if rd != null:
		return rd.visual_for_size(size_class)
	var raw := GameDataRegistry.unit_raw(def_id)
	if not raw.is_empty():
		return StringName(str(raw.get("visual", "")))
	return def_id if _visuals.has(def_id) else &""


## The parsed atlas for one visual id and skin, or null. Cached.
##
## Returns an `AtlasEntry` on the PLACEHOLDER branch too, rather than null, so `plate_colour()`
## has something to read — the game's `_resolve()` does the same and for the same reason:
## callers should branch on `is_placeholder` when *drawing* and nowhere else.
func entry_for(visual_id: StringName, age := 0, colour := -1) -> AtlasEntry:
	var key := _skin_key(visual_id, age, colour)
	if _entries.has(key):
		return _entries[key]

	var decl: Variant = _visuals.get(visual_id)
	if not decl is Dictionary:
		warnings.append("no visuals.json entry for '%s'" % visual_id)
		var unknown := AtlasEntry.from_placeholder(visual_id, PlaceholderSpec.unknown())
		_entries[key] = unknown
		return unknown

	var entry := _load_atlas(visual_id, _atlas_path_for_skin(decl, age, colour))
	if entry == null:
		var ph: Variant = (decl as Dictionary).get("placeholder")
		entry = AtlasEntry.from_placeholder(visual_id,
				PlaceholderSpec.from_dict(ph) if ph is Dictionary else PlaceholderSpec.unknown())
	entry.scale = float((decl as Dictionary).get("scale", 1.0))
	_entries[key] = entry
	return entry


# ── paths, skins and pixels ─────────────────────────────────────────────────

## `GameDataRegistry._atlas_path_for_skin()`'s two independent steps, mirrored. See the class
## comment on why this one re-implementation is allowed and the rest are copies.
func _atlas_path_for_skin(decl: Variant, age: int, colour: int) -> String:
	if not decl is Dictionary:
		return ""
	var d: Dictionary = decl
	var path := str(d.get("atlas", ""))

	# 1. AGE picks the base bake, from the entry's dense `ages` map.
	var ages: Variant = d.get("ages")
	if age >= 1 and ages is Dictionary:
		var per_age := str((ages as Dictionary).get(str(age), ""))
		if not per_age.is_empty():
			path = per_age

	# 2. COLOUR is a suffix transform on whatever step 1 chose, gated by the `colours` flag.
	# A tint whose file is not staged falls back to the untinted bake rather than to the
	# magenta unknown -- the game's rule, and an untinted icon is still a usable icon.
	if colour >= 0 and bool(d.get("colours", false)) and not path.is_empty():
		var tinted := _tinted_path(path, colour_slug(colour))
		if FileAccess.file_exists(_absolute(tinted)):
			return tinted
	return path


func _tinted_path(path: String, slug: StringName) -> String:
	if slug.is_empty() or not path.ends_with(_ATLAS_SUFFIX):
		return path
	return path.substr(0, path.length() - _ATLAS_SUFFIX.length()) + ".%s%s" % [slug, _ATLAS_SUFFIX]


## `colours.json`'s slug for a colour index, or `&""`.
##
## ⚠️ **THE ORDER OF THAT FILE IS LOAD-BEARING** (§4's invariant: saves and replays index into
## it), so this reads the list and never a name-keyed map. Out of range is empty rather than
## clamped: an untinted icon is honest, and index 9 of eight colours is a caller bug that
## should not silently draw blue.
func colour_slug(colour: int) -> StringName:
	if colour < 0 or colour >= _colour_slugs.size():
		return &""
	return _colour_slugs[colour]


## The eight colours, as `{name, colour}` in `colours.json` order — what a picker lists.
func colours() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _colours:
		out.append({
			"name": str(entry.get("name", "")),
			"colour": Color(str(entry.get("hex", "#ffffff"))),
		})
	return out


## A `res://` path inside the GAME's project, made absolute for this one.
##
## ⚠️ **THE ONE-LINE HEART OF THIS FILE.** `visuals.json` states its atlas paths as
## `res://assets/atlases/...` because the game reads them; from here `res://` is
## `MapMaker/`, so an unrewritten path silently resolves to a file inside the wrong project
## and every icon comes back missing with nothing to explain it.
func _absolute(res_path: String) -> String:
	if _root == null or _root.path.is_empty():
		return res_path
	if not res_path.begins_with("res://"):
		return res_path
	return _root.path.path_join(res_path.trim_prefix("res://"))


## `GameDataRegistry._skin_key`'s shape: the bare id for the no-skin case, so the common
## lookup allocates nothing.
static func _skin_key(visual_id: StringName, age: int, colour: int) -> StringName:
	if age <= 0 and colour < 0:
		return visual_id
	return StringName("%s|%d|%d" % [visual_id, age, colour])


## Parse one atlas, or null. **Null for a file that is simply not there is not a warning**, the
## game's rule: that is the normal state before the art is staged.
func _load_atlas(visual_id: StringName, res_path: String) -> AtlasEntry:
	if res_path.is_empty() or ignore_atlases:
		# THE ONE PLACE THE FLAG IS READ, so it cannot diverge from what a genuinely
		# unstaged machine does: this is the same `null` a missing file returns, and every
		# caller above already handles it because that case is the normal one.
		return null
	var path := _absolute(res_path)
	if not FileAccess.file_exists(path):
		return null

	var text := FileAccess.get_file_as_string(path)
	# `JSON.new().parse()` and not the static helper: these files are written by the art
	# pipeline and re-staged by a script, so a half-written one is a real possibility and an
	# engine error per failure is a log somebody else gets to fill.
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		warnings.append("atlas for '%s' is not valid JSON: %s" % [visual_id, path])
		return null
	var d: Dictionary = json.data
	if (d.get("frames", []) as Array).is_empty():
		warnings.append("atlas for '%s' declares no frames: %s" % [visual_id, path])
		return null
	# The DIRECTORY the pages sit in, which is where the game passes `path.get_base_dir()`
	# too -- and here it is already absolute, so `AtlasEntry.pages` comes out as real paths
	# `Image.load_from_file` can open.
	return AtlasEntry.from_atlas_dict(visual_id, d, path.get_base_dir())


## One atlas page as a texture. **`Image.load_from_file`, never `load()`** — see the class
## comment. Cached by path across every visual id that names the page.
func _texture_for(entry: AtlasEntry, page: int) -> Texture2D:
	if page < 0 or page >= entry.pages.size():
		return null
	var path := entry.pages[page]
	if _textures.has(path):
		return _textures[path]

	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		# Cached as null so a missing page is not re-attempted once per redraw. A palette
		# redraws on every keystroke in the search box.
		_textures[path] = null
		warnings.append("cannot read atlas page %s" % path)
		return null
	var tex := ImageTexture.create_from_image(img)
	_textures[path] = tex
	return tex


# ── reading ─────────────────────────────────────────────────────────────────

func _read_colours(path: String) -> void:
	var d := _read_json_raw(path)
	var list: Variant = d.get("colours", [])
	if not list is Array:
		return
	_colours = list
	for entry in _colours:
		if entry is Dictionary:
			_colour_slugs.append(
					StringName(str((entry as Dictionary).get("id", "")).trim_prefix("colour.")))


## A JSON object keyed by id, with `_note` documentation keys dropped and keys as `StringName`.
##
## ⚠️ **THE `_` PREFIX RULE AGAIN** — `game_content.gd`'s header has the full argument, and it
## cost a red test the first time it was missed. `visuals.json` carries `_note` blocks like
## every other file in `game/data/`, including `_note_dragon_baby`, which would otherwise
## become a visual entry whose atlas path is an array of sentences.
func _read_json(path: String) -> Dictionary:
	var raw := _read_json_raw(path)
	var out: Dictionary = {}
	for key in raw:
		var k := str(key)
		if k.begins_with("_"):
			continue
		out[StringName(k)] = raw[key]
	return out


func _read_json_raw(path: String) -> Dictionary:
	if _raw_cache.has(path):
		return _raw_cache[path]
	var out: Dictionary = {}
	if not FileAccess.file_exists(path):
		warnings.append("%s does not exist" % path)
	else:
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK:
			warnings.append("%s: line %d: %s"
					% [path, json.get_error_line(), json.get_error_message()])
		elif not json.data is Dictionary:
			warnings.append("%s is not a JSON object" % path)
		else:
			out = json.data
	_raw_cache[path] = out
	return out
