## One `scenario.json` from a campaign folder (PLAN.md 15.1, schema in 11.7). Phase 15.1.
##
## ## A SCENARIO IS A `MatchConfig`, NOT A SECOND WAY TO START A MATCH
##
## Decision 1 of PLAN.md 15, and 1.6's precedent is exact: a screen collects settings,
## `build_config()` returns a `MatchConfig`, `Net.pending_match` carries it across the
## scene change and `host_solo()` consumes it. This class is one more producer of that
## object. Nothing in the boot path, the net layer or `SimWorld.setup()` needs to learn
## what a campaign is, and PLAN.md 1.1's rule 4 keeps holding -- a scenario is a solo
## match on loopback, so it exercises the networked path like everything else.
##
## **Turning one of these into a `MatchConfig` is 15.3 and is deliberately not here.**
## This class holds what the file said; 15.3 decides what that means for a match.
##
## ## A SCENARIO ONLY EVER DECLARES HOW IT IS *WON*
##
## Decision 5: elimination stays the loss on every map in this game, whatever a file
## says -- own no units and no buildings and you are out. So `mode` picks between the
## two ways of winning and there is no lose-condition field at all:
##
##   `last_man_standing`  leave the enemy nothing. The ordinary conquest rule, already
##                        built, needing no objective code -- which is why scenario 3 is
##                        the cheapest of the three and playable first
##   `scenario`           an authored objective list decides it. What 15.2 evaluates
##
## ⚠️ **`SCENARIO` MODE MUST SUPPRESS LAST-MAN-STANDING'S WIN AND KEEP ITS LOSS** (15.2's
## job, recorded here because this is where the mode is chosen). Wiping the passive
## opponent must NOT end scenario 1 in victory before the tenth villager exists, or the
## scenario teaches the opposite of its name.
##
## ## A PINNED SEED IS NOT A PINNED MAP
##
## PLAN.md 11.7's second trap. `MatchConfig` carries `seed` as provenance only and says
## so at length: `FastNoiseLite`'s float maths is not identical across CPUs, and any
## `MapGenerator` change makes the same seed produce something else. So a scenario pinned
## by seed **will silently play a different map** after any generator change.
##
## That is acceptable for these three and only these three, because their objectives
## count villagers and ages rather than describing a place. `"map": {"file": ...}` is
## refused until 2.4c's saved format exists, and 16.10 is the row that swaps the seeds
## for files and retires the trap.
class_name ScenarioDef
extends RefCounted

## The two ways a scenario can be won. **Not `MatchConfig.Mode`**, deliberately: that
## enum is the lobby's four (LAST_MAN_STANDING, TROPHY, KING_OF_THE_HILL, and SCENARIO
## when 15.2 adds it), and a scenario file may only ask for two of them. Keeping this
## separate is what lets 15.1 be complete and tested without touching `MatchConfig` --
## PLAN.md 15's build order asks every row to be a place you can stop. 15.3 maps it.
enum Mode { LAST_MAN_STANDING, SCENARIO }

const _MODES := {"last_man_standing": Mode.LAST_MAN_STANDING, "scenario": Mode.SCENARIO}

const ICON_FILE := "scenarioIcon.png"
const JSON_FILE := "scenario.json"

## Map types a scenario may name. All six of `MapGenerator.Type`, lowercased -- the
## generator is the authority on what exists, and this is only the spelling.
const _MAP_TYPES := {
	"random": MapGenerator.Type.RANDOM,
	"island": MapGenerator.Type.ISLAND,
	"river": MapGenerator.Type.RIVER,
	"desert": MapGenerator.Type.DESERT,
	"forest": MapGenerator.Type.FOREST,
	"archipelago": MapGenerator.Type.ARCHIPELAGO,
}

## The folder name (`scenario_1`), which is the scenario's identity. Not the display
## name: `campaign.json` names folders in play order, and a designer renaming the title
## must not silently reorder the campaign or orphan the player's progress.
var folder: String = ""

var name: String = ""
var description: String = ""

## Shown once when the scenario loads, dismissed by an X (15.6).
##
## **Shared with skirmish by the owner's spec**, so it belongs to the match HUD rather
## than to the campaign screens. Empty means no modal, which is every skirmish.
var message: String = ""

var mode: Mode = Mode.LAST_MAN_STANDING

var map_type: MapGenerator.Type = MapGenerator.Type.RIVER
var seed: int = 0

## AI level ids, one per opponent, validated against `AIProfile.IDS`. These three
## campaigns each name exactly one `passive`.
##
## Stored as names rather than as `SimPlayer.AILevel` ints because a JSON file that says
## `"passive"` is a file a designer can read and correct; the two lists are index-for-index
## (`AILevel { PASSIVE, EASY, NORMAL, HARD, UNFAIR }` against `AIProfile.IDS`), and 15.3
## does that conversion in one place.
var opponents: Array[StringName] = []

## PLAN.md 15.3 pins this at 1 for the tutorial: the age ladder from the bottom is what
## scenario 2 is about teaching.
var starting_age: int = 1

var objectives: Array[ObjectiveDef] = []

## Absolute path to `scenarioIcon.png`, or "" if the folder has none.
##
## A PATH AND NOT A TEXTURE, because these PNGs are outside `res://` and are therefore
## not imported resources -- `load()` cannot open them at all (PLAN.md 3.3). The screens
## (15.4/15.5) go through `Image.load()` + `ImageTexture.create_from_image()`, and they
## do it when a row is shown rather than here, so opening a campaign list does not decode
## every icon in it.
var icon_path: String = ""

## Everything wrong with this file, in the author's terms. Empty means playable.
##
## Decision 4: **inert is the safe direction to be unfinished in.** A scenario that
## cannot be trusted must refuse to start rather than start and evaluate to true on tick
## 1, so 15.3 checks `is_playable()` and 15.5 greys the PLAY button rather than hiding
## the problem.
var problems: Array[String] = []


func is_playable() -> bool:
	return problems.is_empty()


static func from_dict(p_folder: String, d: Dictionary, dir_path: String) -> ScenarioDef:
	var s := ScenarioDef.new()
	s.folder = p_folder
	s.name = str(d.get("name", p_folder))
	s.description = str(d.get("description", ""))
	s.message = str(d.get("message", ""))

	var mode_key := str(d.get("mode", "last_man_standing")).to_lower()
	if _MODES.has(mode_key):
		s.mode = _MODES[mode_key]
	else:
		s.problems.append("unknown mode '%s' (expected last_man_standing or scenario)"
				% mode_key)

	s._read_map(d.get("map", {}))
	s._read_opponents(d.get("opponents", []))
	s.starting_age = clampi(int(d.get("starting_age", 1)), 1, 4)
	s._read_objectives(d.get("objectives", []))

	var icon := dir_path.path_join(ICON_FILE)
	if FileAccess.file_exists(icon):
		s.icon_path = icon
	return s


func _read_map(raw: Variant) -> void:
	if not raw is Dictionary:
		problems.append("'map' must be an object, e.g. {\"type\": \"river\", \"seed\": 7}")
		return
	var m: Dictionary = raw

	# 16.10's shape, refused rather than ignored. A scenario naming a file it cannot be
	# given would otherwise fall back to a generated map and play something the author
	# never authored -- the same silent-substitution failure the seed trap describes,
	# except that this one is fixable by saying so.
	if m.has("file"):
		problems.append("map.file needs 2.4c's saved map format, which does not exist yet"
				+ " -- pin a type and a seed until 16.10")
		return

	var type_key := str(m.get("type", "river")).to_lower()
	if _MAP_TYPES.has(type_key):
		map_type = _MAP_TYPES[type_key]
	else:
		problems.append("unknown map type '%s' (expected one of %s)"
				% [type_key, ", ".join(_MAP_TYPES.keys())])

	if not m.has("seed"):
		problems.append("map has no 'seed' -- a scenario that regenerates its map every"
				+ " run is not a scenario")
		return
	seed = int(m.get("seed", 0))


func _read_opponents(raw: Variant) -> void:
	if not raw is Array:
		problems.append("'opponents' must be a list of AI level names")
		return

	for entry in (raw as Array):
		# An object ({"ai": "passive"}) or a bare name ("passive"). The object form is
		# what 16.8 will write once an opponent carries more than a difficulty.
		var level := ""
		if entry is Dictionary:
			level = str((entry as Dictionary).get("ai", ""))
		else:
			level = str(entry)
		level = level.to_lower()

		if not AIProfile.IDS.has(level):
			problems.append("unknown opponent AI level '%s' (expected one of %s)"
					% [level, ", ".join(AIProfile.IDS)])
			continue
		opponents.append(StringName(level))

	# MapGenerator refuses to lay out fewer than two starts, so a scenario with no
	# opponent is a scenario with nowhere to stand. Caught here rather than at
	# generation, where the message would be about map sizes.
	if opponents.is_empty():
		problems.append("no opponents -- a match needs at least two players")
	elif opponents.size() + 1 > MapGenerator.MAX_PLAYERS:
		problems.append("%d opponents plus the player is more than the %d a map supports"
				% [opponents.size(), MapGenerator.MAX_PLAYERS])


func _read_objectives(raw: Variant) -> void:
	# Absent is legal and arrives here as [] from the caller's `get` default, which is
	# what a `last_man_standing` scenario carries. Anything else that is not a list is
	# an author error.
	if not raw is Array:
		problems.append("'objectives' must be a list")
		return

	for entry in (raw as Array):
		if not entry is Dictionary:
			problems.append("objective entries must be objects")
			continue
		var o := ObjectiveDef.from_dict(entry as Dictionary, problems)
		if o != null:
			objectives.append(o)

	# ── the two ways mode and objectives can contradict each other ──────────────
	#
	# Both are refusals rather than warnings, and the reason is the same in both
	# directions: silently ignoring an authored win condition loses the author's intent
	# without telling anybody, and a scenario is content somebody hand-wrote. A wrong
	# scenario that refuses to start costs a minute; one that plays the wrong rule costs
	# a playtest and reads as a game bug.
	var wins := 0
	for o in objectives:
		if o.output == ObjectiveDef.Output.WIN:
			wins += 1

	if mode == Mode.SCENARIO and wins == 0:
		problems.append("mode 'scenario' with no win objective can never be won"
				+ " -- add one, or use mode 'last_man_standing'")
	elif mode == Mode.LAST_MAN_STANDING and not objectives.is_empty():
		problems.append("mode 'last_man_standing' is decided by conquest, so its %d"
				% objectives.size()
				+ " objective(s) would never be read -- use mode 'scenario' to have them count")


## Multiple `win` rows are ANDed, so this is the whole objective in as many halves as
## the author wrote. PLAN.md 11.8 says an OR would need grouping and no scenario wants
## one yet -- said here rather than left for the reader to guess.
func win_objectives() -> Array[ObjectiveDef]:
	var out: Array[ObjectiveDef] = []
	for o in objectives:
		if o.output == ObjectiveDef.Output.WIN:
			out.append(o)
	return out


## THE LAUNCH PATH (PLAN.md 15.3): this scenario as a `MatchConfig`, or null with the
## reasons in `problems`.
##
## ## WHY IT IS HERE AND NOT ON A SCREEN
##
## Decision 1 says a scenario screen is one more producer of a `MatchConfig`, exactly as
## `SkirmishScreen.build_config()` is. But 15.3 asks to be *"tested by asserting the config
## rather than by starting a match"*, and a function on a `Control` cannot be, so it lives
## on the data. 15.5 calls this and puts the result in `Net.pending_match`; nothing in the
## boot path, the net layer or `SimWorld.setup()` learns what a campaign is.
##
## ## IT REFUSES `SCENARIO` MODE TODAY, AND THAT REFUSAL IS THREE LINES TO DELETE
##
## `MatchConfig.Mode` has no `SCENARIO` member yet -- PLAN.md assigns it, and
## `MatchConfig.objectives`, to **15.2**. Two wrong ways to paper over that, and it is
## worth naming both because either would look like it worked:
##
## - **Map `SCENARIO` onto `LAST_MAN_STANDING`.** Scenario 1 would then be won by killing
##   the passive AI's five villagers, with two villagers and no house, which is decision 5's
##   named failure and teaches the opposite of the scenario's name.
## - **Add an inert `SCENARIO` member here.** `WinConditionSystem` deliberately never ends
##   a match in an unimplemented mode, so scenario 1 would launch into a match that can
##   never be won OR lost. A player would sit in it forever. "Inert" is the safe direction
##   for a mode nobody has selected yet; it is the wrong direction for the mode a PLAY
##   button is about to select.
##
## So a `SCENARIO` scenario refuses to launch and says which row it is waiting for. **This
## is exactly what PLAN.md 15 predicts**: scenario 3 is playable at 15.1 + 15.3 + 15.5, and
## 15.2 is what unlocks scenarios 1 and 2. When 15.2 lands, delete the guard below and set
## `cfg.mode` from `mode`.
##
## ## A PINNED SEED IS NOT A PINNED MAP
##
## PLAN.md 11.7's second trap, and it is the reason the map is GENERATED here and then
## carried as data. `MatchConfig.map_data` travels as the map because `FastNoiseLite`'s
## float maths is not identical between an ARM phone and an x86 desktop, so a host and a
## client regenerating from a shared seed can disagree about where the water is. `seed` and
## `map_type` ride along as provenance only.
##
## What the trap costs is separate and unfixed: **any `MapGenerator` change makes this seed
## produce a different map.** Acceptable for these three, whose objectives count villagers
## and ages rather than describing a place. 16.10 pins a FILE instead.
## `out_problems` is named apart from this class's own `problems` deliberately: a parameter
## called `problems` would SHADOW the field, and the two mean different things here -- one
## is what the loader found, the other is what this call is reporting.
func build_config(out_problems: Array[String]) -> MatchConfig:
	# Decision 4: a scenario that cannot be trusted must refuse to start rather than start
	# and evaluate to true on tick 1. Every complaint the loader already found comes along,
	# so a caller has one place to look.
	if not is_playable():
		for p in problems_or_self():
			out_problems.append(p)
		return null

	if mode == Mode.SCENARIO:
		out_problems.append("mode 'scenario' needs 15.2's ObjectiveSystem before it can be"
				+ " launched -- MatchConfig has no SCENARIO mode yet, and mapping it onto"
				+ " last_man_standing would let conquest win an economy lesson")
		return null

	var cfg := MatchConfig.new()

	# PLAYER 1 IS THE HUMAN and the opponents follow, numbered 1..N with no gaps.
	# `SkirmishScreen.build_config` compacts for a reason that binds here too: `Net` hands
	# out the lowest free id to a joining peer and `MapGen.build_from` resolves a map's
	# player index BY POSITION in `world.players`, so a match whose ids skipped one would
	# hand somebody else's base to the wrong player.
	cfg.player_ids = [1]
	cfg.ai_players = [false]
	# Position for position with `ai_players`. The human gets a level too and it is never
	# read -- a hole here would misalign every bot after it.
	cfg.ai_levels = [int(SimPlayer.AILevel.EASY)]
	# A FREE-FOR-ALL. 0 is the ABSENCE of a team rather than a team everybody shares, which
	# is what makes "the human against one bot" the right shape here: two players both
	# reading 0 are not allies. Written out per row rather than left empty -- both are legal
	# and mean the same thing, and the explicit form is one less thing to check when a
	# future campaign wants 2v2.
	cfg.teams = [0]

	for level in opponents:
		cfg.player_ids.append(cfg.player_ids.size() + 1)
		cfg.ai_players.append(true)
		cfg.ai_levels.append(_ai_level_of(level))
		cfg.teams.append(0)

	# LEFT EMPTY ON PURPOSE, which `MatchConfig.colours` documents as "derive from join
	# order". The alternative is a palette list here, and a second copy of `colours.json`'s
	# order is a second thing to keep in step with a file whose ORDER IS LOAD-BEARING --
	# saves and replays index into it. Join order gives player 1 the first entry.
	cfg.colours = []

	cfg.seed = seed
	cfg.map_type = map_type
	cfg.map_data = MapGenerator.generate(seed, map_type, cfg.player_ids.size())
	# The map is the authority on its own size; a config disagreeing with the map it
	# carries would build a world the wrong shape.
	cfg.map_size = cfg.map_data.size if cfg.map_data != null else MatchConfig.DEBUG_MAP_SIZE
	cfg.mode = MatchConfig.Mode.LAST_MAN_STANDING
	cfg.starting_age = starting_age
	# "Nobody typed one", which is what a scenario is: it is a solo match on loopback and
	# there is no host name field anywhere near it. `LanBeacon.default_host_name()` is the
	# lobby's fallback and does not belong here.
	cfg.host_name = ""
	return cfg


## `problems`, or a single generic line if something refused without saying why. Never
## empty for an unplayable scenario, because "it will not start and I do not know why" is
## the one outcome that costs an afternoon.
func problems_or_self() -> Array[String]:
	if not problems.is_empty():
		return problems
	return ["scenario '%s' is not playable and did not say why" % folder] as Array[String]


## An AI level name to `SimPlayer.AILevel`.
##
## ⚠️ **`AIProfile.IDS` AND `SimPlayer.AILevel` ARE COUPLED BY POSITION AND NOTHING SAYS SO
## AT EITHER END.** `IDS` is `["passive", "easy", "normal", "hard", "unfair"]` and the enum
## is `{ PASSIVE, EASY, NORMAL, HARD, UNFAIR }`, so `find()` is the conversion -- and it is
## a conversion that would keep working, silently and wrongly, if either list were reordered
## or a level were inserted in the middle. `test_scenario_launch` asserts the pairing by
## NAME for exactly that reason; this comment is not the guard, that test is.
func _ai_level_of(level: StringName) -> int:
	var index := AIProfile.IDS.find(String(level))
	# Unreachable through `from_dict`, which refuses an unknown level -- so this guards a
	# def built by hand in a test or by a future editor, and Easy is what every older
	# config that named no level already gets.
	return index if index >= 0 else int(SimPlayer.AILevel.EASY)
