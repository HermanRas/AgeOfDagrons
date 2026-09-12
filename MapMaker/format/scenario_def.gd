## ⚠️ **NOT THE GAME'S `ScenarioDef`. A THREE-DECLARATION STAND-IN** — `format/sim_world.gd`'s
## trick, for 16.8's schema instead of for the sim's sub-tile.
##
## 16.8 writes a `scenario.json`, which makes this tool **the second consumer of 15.1's schema**
## and the schema the one thing that must not move. The natural answer would be a verbatim copy of
## the game's `scenario_def.gd`, the way 16.6 copied `objective_def.gd` — and it cannot be done.
##
## ## WHY A COPY IS IMPOSSIBLE HERE AND WAS EASY FOR `objective_def.gd`
##
## `ObjectiveDef` is genuinely dependency-free and its own header says so. `ScenarioDef` is the
## opposite: `build_config()` reaches for **`MatchConfig`, `SimPlayer.AILevel` and `AIProfile`**,
## and GDScript compiles a whole file or none of it — so a verbatim copy would drag the net layer's
## config object and the sim's player enum into `format/`. That is `format/sim_world.gd`'s line
## exactly (*"a signal the tool is reaching into the simulation"*), and `MatchConfig` is worse than
## `SimWorld`: it is what a match is STARTED with, and a map-authoring tool has no business
## carrying one.
##
## ## SO WHAT IS ACTUALLY AT RISK IS THE SPELLINGS, AND THOSE ARE DECLARATIONS
##
## The export writes words into a file the game's loader reads back. What can drift between the
## two is not behaviour, it is **vocabulary**: the two mode names, the two filenames. A tool one
## rename behind would author a `scenario.json` whose `mode` the loader reports as *"unknown mode"*
## — a scenario that will not start, produced by a tool that reported success.
##
## `FormatGuard.DECLARATIONS` is the mechanism that already exists for exactly this, and the three
## lines below are copied out of `src/data/scenario_def.gd` **verbatim** so the comparison is a
## comparison rather than a translation.
##
## ⚠️ **ONE PART OF THE SCHEMA IS NOT GUARDED AND IT IS SAID OUT LOUD RATHER THAN LEFT TO BE
## DISCOVERED: `ScenarioDef._MAP_TYPES` SPANS SEVEN LINES**, so `_check_declaration`'s
## prefix match cannot see it. What it maps is `MapGenerator.Type`'s names lowercased, and that
## enum **is** checked (`format/map_generator.gd`), so a type added, removed or reordered is
## caught. What would slip through is somebody re-spelling one of the keys in that dictionary
## without touching the enum. `map_type_key()` derives the word from the enum for that reason —
## one opinion, taken from the half that is guarded.
##
## ⚠️ **DO NOT GROW THIS FILE.** Anything here needing `ScenarioDef`'s *behaviour* — reading a
## file, building a config — is the tool trying to start a match. The check that a written
## scenario is loadable is the game's, run by the game: `dev_preview/preview_exported_campaign.tscn`.
class_name ScenarioDef
extends RefCounted

## The two ways a scenario can be won.
##
## **MUST MATCH the game's `src/data/scenario_def.gd`.** Both lines below are checked at startup
## by declaration, not by hash — see the class comment. The enum is carried only so that `_MODES`
## can be written the way the game writes it; nothing here reads its values.
enum Mode { LAST_MAN_STANDING, SCENARIO }

const _MODES := {"last_man_standing": Mode.LAST_MAN_STANDING, "scenario": Mode.SCENARIO}

const ICON_FILE := "scenarioIcon.png"
const JSON_FILE := "scenario.json"


## The mode words an author may write, in the game's own order.
##
## Derived from `_MODES` rather than written out a second time — `ConditionPanel`'s rule for the
## objective vocabulary, one level up: a written-out list here would be the second dialect, in the
## one place nobody would think to diff.
static func modes() -> Array[String]:
	var out: Array[String] = []
	for key in _MODES:
		out.append(str(key))
	return out


## `"last_man_standing"`. Named rather than spelled at every call site, because the two mode words
## are the difference between a scenario decided by conquest and one decided by its objectives.
static func mode_conquest() -> String:
	return str(_MODES.keys()[Mode.LAST_MAN_STANDING])


## `"scenario"`.
static func mode_objectives() -> String:
	return str(_MODES.keys()[Mode.SCENARIO])


## How a `MapGenerator.Type` is spelled in a `scenario.json`'s `map.type`.
##
## **DERIVED FROM THE ENUM, WHICH IS THE GUARDED HALF.** `ScenarioDef._MAP_TYPES` is a hand-written
## dictionary of the same names lowercased; it is too many lines for the declaration check, and the
## enum it mirrors is not. See the class comment.
static func map_type_key(type: int) -> String:
	var keys := MapGenerator.Type.keys()
	if type < 0 or type >= keys.size():
		return str(keys[MapGenerator.Type.RIVER]).to_lower()
	return str(keys[type]).to_lower()
