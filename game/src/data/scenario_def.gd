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
