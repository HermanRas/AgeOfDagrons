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
const MARKET_PATH := "res://data/market.json"

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

## `market.json`, raw. Two blocks of integers -- tribute and exchange -- read by
## `TributeCommand` and `MarketExchangeCommand` through `SimWorld`, and by the
## market page to LABEL the buttons with the same figures the commands charge.
## Kept raw rather than parsed into a *Def because there is nothing to parse: the
## accessors below are the whole schema, and a class holding four ints would only
## make a second place for the defaults to disagree.
var _market: Dictionary = {}

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
	_market = _read_json(MARKET_PATH)
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


## One of `visual_id`'s interchangeable looks, chosen by `seed`, or `visual_id`
## itself when it declares no `variants` (visuals.json).
##
## THE THIRD AXIS, and the only one that is not a skin. `age` and `colour` change
## what a standing entity looks like; a variant is decided once, when the thing
## comes into existence, and never changes again. The project owner's four field
## plots are the first: four crops, not four ages.
##
## Takes a SEED rather than an index, and callers pass something derived from the
## entity -- `GameView` uses its tile. Two consequences, both wanted: the same plot
## always draws the same crop (so it does not shuffle as it leaves and re-enters
## the view, which a per-spawn `randi()` would do every time a pooled view was
## recycled), and every client picks the same one without the choice ever being
## sent, because it is a pure function of a fact they all already have.
##
## `posmod`, not `%`: a negative seed with `%` would index backwards off the front
## of the list. The seed's own mixing is the caller's business.
func variant_of(visual_id: StringName, seed: int) -> StringName:
	if not _loaded:
		load_all()
	var list: Variant = _visuals.get(visual_id, {}).get("variants")
	if not list is Array or (list as Array).is_empty():
		return visual_id
	return StringName((list as Array)[posmod(seed, (list as Array).size())])


## How many looks `visual_id` has. 1 for everything that declares no variants,
## so a caller can ask without special-casing.
func variant_count(visual_id: StringName) -> int:
	if not _loaded:
		load_all()
	var list: Variant = _visuals.get(visual_id, {}).get("variants")
	return (list as Array).size() if list is Array and not (list as Array).is_empty() else 1


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


## The palette INDEX of a colour named by id (`colour.yellow`) or by slug
## (`yellow`) -- the inverse of colour_slug(), and -1 for a name the palette does
## not have.
##
## Exists so code that means a particular colour can say which one. Index order
## is the load-bearing contract (colours.json's own note) and callers must keep
## storing the index, but a `2` written into a config file is a fact about
## colours.json that nothing checks and nobody reading it can verify. Does NOT
## wrap like colour()/colour_slug(): those answer for a player who already has an
## index and must render somehow, whereas an unknown NAME here is a typo, and
## quietly returning some other colour for it is how the wrong player ends up
## yellow.
func colour_index(id: StringName) -> int:
	if not _loaded:
		load_all()
	return _colour_slugs.find(StringName(String(id).trim_prefix("colour.")))


## Which (visual, colour) pairs DECLARE a per-player bake but have no file staged
## for it. Diagnostic only -- resolution silently falls back to the untinted bake,
## which renders a player in nobody's colour, and since colour is the only thing
## telling players apart (PLAN.md 1) that is a gap worth being able to enumerate
## rather than notice in a match. Returns [] when the art pack is not mounted at
## all, because then EVERY colour is missing and the list would say nothing.
##
## Which per-player bakes are PRESENT but do not belong with their siblings --
## the failure missing_colour_atlases() cannot see, because the file is there and
## parses and draws.
##
## Asked for by the art agent (asset_request.md, 2026-08-16) after three pipeline
## defects were fixed mid-roster: `decay` sampled from t=0 so every corpse sprang
## upright for a frame, two units baked as overlapping bodies, and player colour
## never reached actors with an opaque root. Only red and yellow were rebaked, so
## 60 of the 152 colour atlases rendered wrongly while looking perfectly healthy.
##
## UNIFORMITY OF BUILD IDENTITY IS THE SIGNAL: a unit's eight colours are one
## batch's output and must all name the same isobake build, so any that disagree
## with the majority are the odd ones out. The atlas carries
## `generator.isobake_build` (a monotonic commit count) and `isobake_commit`;
## EQUALITY is what is compared, not order, which stays correct even if a rebase
## ever makes two commits share a count.
##
## THIS REPLACED A MODIFICATION-TIME RULE, and the way that rule failed is the
## reason this one is written against identity instead. It flagged an atlas more
## than an hour older than its newest sibling, which worked only while the wrong
## files were also the old files. The moment the roster completed, the two
## known-GOOD colours -- red and yellow, rebaked in the morning, siblings landing
## that afternoon -- became the oldest of their set and the check named exactly
## them: 34 false positives, every one of them a file to trust.
##
## AN ABSENT IDENTITY IS A VALUE, NOT A GAP. The 323 atlases staged before
## isobake `531a4bc` carry no such key, and nothing unstamped can postdate the
## stamp, so "absent" compares equal to "absent" and a wholly-unstamped set is
## uniform and silent. A NULL identity is different and is always reported: it
## means the bake asked git and got no answer, so provenance broke rather than
## the art being old (the art agent made all three keys always-present for this,
## isobake `99a33cc`).
##
## DIAGNOSTIC ONLY. Nothing branches on this -- a stale atlas still resolves and
## still draws, and refusing to render it would be a worse outcome than rendering
## it wrongly. Each entry: {"visual", "colour", "slug", "identity", "expected"}.
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

		# Identity per staged colour, and how many share each one. The base bake
		# is deliberately NOT counted: it is one file against eight and a unit
		# whose base alone was rebaked would otherwise outvote nothing but still
		# muddy the tally.
		var ids: Array[String] = []
		var tally: Dictionary = {}
		ids.resize(_colour_slugs.size())
		for i in range(_colour_slugs.size()):
			var path := _tinted_path(base, _colour_slugs[i])
			if not FileAccess.file_exists(path):
				ids[i] = ""          # absent; missing_colour_atlases() reports it
				continue
			ids[i] = _build_identity(path)
			tally[ids[i]] = int(tally.get(ids[i], 0)) + 1

		if tally.is_empty():
			continue                 # nothing staged for this visual at all

		# The majority identity is what the set is SUPPOSED to be. Ties are broken
		# by string order rather than by whichever the Dictionary yielded first --
		# a diagnostic that names different files on two runs of the same data is
		# not one anybody can act on.
		var keys := tally.keys()
		keys.sort()
		var expected: String = keys[0]
		for k in keys:
			if int(tally[k]) > int(tally[expected]):
				expected = k

		for i in range(_colour_slugs.size()):
			if ids[i] == "":
				continue
			# A broken-provenance bake is reported even in a set that agrees on
			# it: null does not mean old, it means the pipeline could not say,
			# and that should never happen quietly.
			if ids[i] == expected and ids[i] != _IDENTITY_UNKNOWN:
				continue
			out.append({
				"visual": visual_id,
				"colour": i,
				"slug": _colour_slugs[i],
				"identity": ids[i],
				"expected": expected,
			})
	return out


## What an atlas says about the code that built it, as a comparable string.
##
## Three states, matching what isobake emits (`99a33cc`): the keys ABSENT means
## it predates build stamping, which is a real and orderable fact about the file
## rather than a gap; NULL means the bake asked git and got nothing, which is a
## broken pipeline and never compares equal to anything, including itself; and a
## real value identifies the commit.
const _IDENTITY_ABSENT := "unstamped"
const _IDENTITY_UNKNOWN := "unknown"


func _build_identity(path: String) -> String:
	var raw := _read_json(path)
	var gen: Variant = raw.get("generator")
	if not gen is Dictionary:
		return _IDENTITY_ABSENT
	var g: Dictionary = gen
	if not g.has("isobake_commit") and not g.has("isobake_build"):
		return _IDENTITY_ABSENT
	var commit: Variant = g.get("isobake_commit")
	var build: Variant = g.get("isobake_build")
	if commit == null and build == null:
		return _IDENTITY_UNKNOWN
	# Commit first -- it identifies the code exactly, where the build count is
	# only monotonic on linear history (the art agent's own caveat).
	return str(commit) if commit != null else "build:%d" % int(build)


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


## The decorative props that stand AROUND a visual -- the plank stacks at a
## lumber camp, the cut stone at a mining camp, the produce crates at a mill.
## Each entry is `{"visual": StringName, "offset_m": Vector2}`, in the declared
## order, and `[]` for the overwhelming majority of ids that have none.
##
## PROPS ARE SEPARATE ATLASES COMPOSED AT DRAW TIME, not baked into the building
## (project owner, 2026-08-15). Baking them in would freeze one arrangement into
## all four age skins and would need a compose step in isobake that drawing them
## here makes unnecessary. The cost is this function and the draw loop in
## EntityView; the gain is that the same plank stack serves every age of every
## building that wants one.
##
## `offset_m` is a GROUND-PLANE offset in metres from the building's own origin,
## the same units placeholders are authored in, so it stays meaningful if
## `Iso.TILE_SIZE` ever changes. It must keep the prop inside the footprint the
## building already reserves -- `buildings.json` sizes a footprint as the max
## across all four age skins, so ages 1 and 2 are holding ground their art does
## not fill, and that slack is where these go. Props block nothing and are pure
## view; they are decoration standing on open ground.
##
## `age` gates an entry that declares an `ages` list -- the mill only gains its
## food crates at age 3, when the Persian storehouse and Roman farmstead replace
## the Briton rotary mill. An entry with no `ages` shows in every age. 0 or less
## means "no age known" and is read as age 1, so a caller with no skin yet gets
## the age-1 dressing rather than all of it at once.
func props_for(visual_id: StringName, age: int = 0) -> Array[Dictionary]:
	if not _loaded:
		load_all()

	var out: Array[Dictionary] = []
	var declared: Variant = _visuals.get(visual_id, {}).get("props")
	if not declared is Array:
		return out

	var want := maxi(1, age)
	for entry in declared as Array:
		if not entry is Dictionary:
			continue
		var d: Dictionary = entry
		var ages: Variant = d.get("ages")
		if ages is Array and not _lists_age(ages as Array, want):
			continue
		var off: Variant = d.get("offset_m", [0.0, 0.0])
		var v := Vector2.ZERO
		if off is Array and (off as Array).size() >= 2:
			v = Vector2(float(off[0]), float(off[1]))
		out.append({"visual": StringName(d.get("visual", "")), "offset_m": v})
	return out


## Whether an `ages` list names this age. Compared as INTEGERS one at a time
## rather than with `Array.has()`: JSON has no integer type, so `[3, 4]` parses
## as floats, and `has()` does not match an int against a float. The mill's food
## crates were declared for ages 3 and 4 and appeared in none.
func _lists_age(ages: Array, age: int) -> bool:
	for a in ages:
		if int(a) == age:
			return true
	return false


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
##
## `size_class` is the same idea for RESOURCE NODES, which have one visual per size
## since 2026-08-17 (three gold actors, two stone). -1 means "no preference" and
## gets the kind's plain visual -- what a portrait or a menu icon wants, and what
## every caller that predates the size classes keeps getting.
##
## Two optional arguments for two entity kinds rather than one general "state"
## argument: a phase and a size class are not the same question, and a single
## parameter meaning different things per branch would be a trap for whoever passed
## the wrong one.
func visual_for(def_id: StringName, phase: int = -1, size_class: int = -1) -> StringName:
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
		return r.visual_for_size(size_class)

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


## Every declared tech, sorted. EMPTY TODAY and that is the correct answer, not a
## failure: `techs.json` is deliberately empty until 9.3 (its own note says so).
## Exists so the tech-tree page can render the real set the day there is one,
## rather than being written twice.
func tech_ids() -> Array[StringName]:
	return _sorted_keys(_techs)


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


# ── the market (data/market.json) ────────────────────────────────────────────
#
# Read by the two market commands through `SimWorld`, and by `MarketPanel` to put
# the same figures on the buttons that the commands will charge. ONE source, so a
# button cannot advertise a price the server refuses -- the trust-boundary rule
# (PLAN.md 5.1 step 4) says the server must re-check everything, and it says
# nothing about the two being allowed to disagree about the number.
#
# Every accessor returns an INTEGER. See market.json's own note: this arithmetic
# runs inside the simulation, where a float would be free to round differently on
# an ARM phone than on an x86 host.

## The building a player must have STANDING AND FINISHED to trade at all -- both
## market commands ask for this one, so they cannot drift onto different gates, and
## its own `age_required` is how the age gate is inherited without being restated.
func market_building() -> StringName:
	if not _loaded:
		load_all()
	return StringName(str(_market.get(&"building", "")))


## What one press of a Tribute button sends, before tax.
func tribute_increment() -> int:
	return maxi(0, int(_market_block(&"tribute").get("increment", 0)))


## The cut the sender loses in transit, as whole percent. 0 makes tribute free.
func tribute_tax_percent() -> int:
	return clampi(int(_market_block(&"tribute").get("tax_percent", 0)), 0, 100)


## What arrives when `amount` is sent. The one place the tax is arithmetic, so the
## command that charges it and the label that advertises it cannot round
## differently -- integer division, floor, and the sender always pays in full.
func tribute_received(amount: int) -> int:
	if amount <= 0:
		return 0
	return amount * (100 - tribute_tax_percent()) / 100


## Whether `kind` may be tributed at all. Declared rather than derived from the
## stock dictionary, which is whatever anybody has happened to gather.
func can_tribute(kind: StringName) -> bool:
	return _name_list(_market_block(&"tribute").get("kinds", [])).has(kind)


## The resource the market prices everything in. Never itself tradeable.
func market_currency() -> StringName:
	return StringName(str(_market_block(&"exchange").get("currency", "gold")))


## How much one buy or sell moves.
func market_lot() -> int:
	return maxi(0, int(_market_block(&"exchange").get("lot", 0)))


## The tradeable kinds in DECLARED order, which is the order the market page draws
## its rows in -- so re-ordering the data re-orders the UI and nothing else has to
## know.
func market_kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	var prices: Variant = _market_block(&"exchange").get("prices", {})
	if prices is Dictionary:
		for key in (prices as Dictionary):
			out.append(StringName(str(key)))
	return out


## Gold to receive one lot of `kind`. 0 means "not for sale", which is also the
## honest answer for the currency itself and for an unknown kind.
func market_buy_price(kind: StringName) -> int:
	return _market_price(kind, "buy")


## Gold paid for one lot of `kind`. 0 means the market will not take it.
func market_sell_price(kind: StringName) -> int:
	return _market_price(kind, "sell")


func _market_price(kind: StringName, direction: String) -> int:
	if kind == market_currency():
		return 0
	var prices: Variant = _market_block(&"exchange").get("prices", {})
	if not prices is Dictionary:
		return 0
	var entry: Variant = (prices as Dictionary).get(String(kind), null)
	if not entry is Dictionary:
		return 0
	return maxi(0, int((entry as Dictionary).get(direction, 0)))


func _market_block(key: StringName) -> Dictionary:
	if not _loaded:
		load_all()
	var block: Variant = _market.get(key, {})
	return block if block is Dictionary else {}


## JSON strings to StringNames. `GameDefs.name_list` does this for the *Defs; the
## market has no Def to hang it off, and re-parsing raw JSON in three accessors is
## how the three come to disagree about a malformed entry.
func _name_list(raw: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if raw is Array:
		for v in (raw as Array):
			out.append(StringName(str(v)))
	return out


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

	# A prop naming a visual that does not exist would draw the magenta unknown
	# beside an otherwise perfect building -- loud, but only once someone looks.
	# Checked across EVERY age, not just the current one, so a mill's age-3 crates
	# are validated on a machine that never leaves age 1.
	for visual_id in _visuals:
		for age in range(1, maxi(1, _ages.size()) + 1):
			for p in props_for(visual_id, age):
				_require_visual(p["visual"], "visual '%s' prop" % visual_id)

	for id in _resources:
		var r: ResourceDef = _resources[id]
		_require_visual(r.visual, "resource '%s'" % id)
		if not GameDefs.RESOURCE_KINDS.has(r.kind):
			load_warnings.append("resource '%s' has unknown kind '%s'" % [id, r.kind])
		if r.amounts.is_empty():
			load_warnings.append("resource '%s' declares no amounts" % id)
		if r.gather_slots < 1:
			load_warnings.append("resource '%s' has %d gather slots" % [id, r.gather_slots])
		# Per-size art. More sprites than amounts would mean a size class that can
		# be drawn and never spawned, which is a typo rather than a decision --
		# FEWER is allowed and clamps (stone has two actors for three classes).
		for i in range(r.visuals.size()):
			_require_visual(r.visuals[i], "resource '%s' size %d" % [id, i])
		if r.visuals.size() > r.amounts.size():
			load_warnings.append("resource '%s' declares %d size visuals but only %d amounts"
					% [id, r.visuals.size(), r.amounts.size()])

	# Every unit must be trainable somewhere, or it can never enter a match. Not
	# true in reverse -- a building that trains nothing is fine.
	for id in _units:
		if (_units[id] as UnitDef).trainable_at.is_empty():
			load_warnings.append("unit '%s' is trainable at no building" % id)

	_validate_skins()
	_validate_market()


## `market.json`'s two blocks, checked against the rest of the data rather than
## against themselves. Every one of these is a typo that would present as a button
## the server silently refuses -- the market page reads its labels from the same
## accessors, so a misspelled kind draws a perfectly convincing row that can never
## be pressed successfully.
func _validate_market() -> void:
	if _market.is_empty():
		load_warnings.append("market.json is empty -- the trade page has no prices")
		return

	for kind in _name_list(_market_block(&"tribute").get("kinds", [])):
		if not GameDefs.RESOURCE_KINDS.has(kind):
			load_warnings.append("market tribute names unknown kind '%s'" % kind)
	if tribute_increment() <= 0:
		load_warnings.append("market tribute increment is %d -- nothing to send"
				% tribute_increment())

	# A market gated on a building that does not exist is a market nobody can ever
	# reach, and it would present as two silent pages of dead buttons.
	if not _buildings.has(market_building()):
		load_warnings.append("market is gated on unknown building '%s'" % market_building())

	var currency := market_currency()
	if not GameDefs.RESOURCE_KINDS.has(currency):
		load_warnings.append("market currency '%s' is not a resource kind" % currency)
	if market_lot() <= 0:
		load_warnings.append("market lot is %d -- nothing to trade" % market_lot())

	for kind in market_kinds():
		if not GameDefs.RESOURCE_KINDS.has(kind):
			load_warnings.append("market prices unknown kind '%s'" % kind)
		# The currency cannot be traded for itself, and `_market_price` already
		# returns 0 for it -- so an entry here is a row that draws two dead buttons.
		if kind == currency:
			load_warnings.append("market prices its own currency '%s'" % kind)
		# BUY BELOW SELL IS FREE GOLD, in a loop, as fast as a finger can move. The
		# spread is the whole cost of trading (market.json's note), and inverting it
		# turns the market into an infinite resource generator.
		if market_buy_price(kind) <= market_sell_price(kind):
			load_warnings.append("market buys '%s' back for at least what it sells it for (%d/%d)"
					% [kind, market_buy_price(kind), market_sell_price(kind)])


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

		_validate_variants(visual_id, decl as Dictionary)

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


## `variants` (visuals.json) is a list of other visual IDS that are interchangeable
## looks for the same thing -- four field plots, not four ages.
##
## Three things are worth failing over. A variant naming an UNDECLARED id would
## resolve to the magenta unknown, which is loud but arrives at draw time rather
## than at load. A variant naming ITSELF-plus-nothing is a list that says nothing.
## And carrying both `ages` and `variants` is a contradiction: an age skin changes
## under a standing building, a variant is chosen once when it is built, and a
## thing cannot be both without a rule for which wins.
func _validate_variants(visual_id: StringName, decl: Dictionary) -> void:
	var variants: Variant = decl.get("variants")
	if variants == null:
		return
	if not variants is Array:
		load_warnings.append("visual '%s' has a 'variants' that is not a list" % visual_id)
		return

	var list: Array = variants
	if list.size() < 2:
		load_warnings.append("visual '%s' declares %d variant(s) -- a list of one is not a choice"
				% [visual_id, list.size()])
	if decl.has("ages"):
		load_warnings.append(("visual '%s' declares both 'ages' and 'variants' -- a skin and"
				+ " a variant are different axes and cannot both apply") % visual_id)
	for v in list:
		if not _visuals.has(StringName(v)):
			load_warnings.append("visual '%s' names undeclared variant '%s'" % [visual_id, v])


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
