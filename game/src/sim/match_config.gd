## What SimWorld.setup() needs to stand up a match: which players exist, what
## colour each of them is, and how big the map is. Colour, not faction: v1 is one
## shared civilisation (PLAN.md 1), and a faction picker only arrives with 9.5.
## Win conditions join this at the lobby (1.6), which is also what will fill
## `colours` from a picker rather than from a debug factory below;
## the actual terrain layout is 2.4a's job, not this class's -- `map_size` only
## says how much grid to allocate.
class_name MatchConfig
extends RefCounted

## How the match is won (PLAN.md 11.1/11.2). Chosen in the lobby once 1.6/11.3
## exist; until then every match is the default.
##
## ONLY LAST_MAN_STANDING IS IMPLEMENTED. The other two are declared here so the
## mode is a real axis rather than a boolean, and so the lobby has a list to show
## -- `WinConditionSystem` documents exactly what each of them still needs, and
## deliberately never ends a match in either. A mode that half-works would end
## matches for reasons the player cannot see; one that does nothing leaves a
## sandbox, which is what the debug map already is.
##
##   LAST_MAN_STANDING  own no units and no buildings and you are out; last
##                      player left wins. The classic conquest rule.
##   TROPHY             every player starts with a baby dragon; lose it and you
##                      are out.
##   KING_OF_THE_HILL   hold a zone on the map with more units than anybody else
##                      to score; first to WinConditionSystem.KOTH_TARGET_SCORE
##                      wins.
enum Mode { LAST_MAN_STANDING, TROPHY, KING_OF_THE_HILL }


## A mode's name for a player to read (the skirmish screen, 1.6/11.3). Spelled out
## rather than derived from the enum name, so renaming a member is a change you make
## here too, in front of you, instead of silently retitling a menu entry.
static func mode_name(mode: Mode) -> String:
	match mode:
		Mode.TROPHY: return "Trophy"
		Mode.KING_OF_THE_HILL: return "King of the Hill"
		_: return "Last Man Standing"

## Deliberately small. PLAN.md 10's MVP is "one small map on a phone", and an 8x8
## town centre plus 5 villagers on 64x64 tiles is already a generous settlement's
## worth of room. 2.4b scales size with player count.
const DEBUG_MAP_SIZE := Vector2i(64, 64)

var player_ids: Array[int] = []
var map_size: Vector2i = DEBUG_MAP_SIZE

## PLAN.md 11.1. Part of the config for the same reason `colours` is: every
## client builds its own world (2.4a), and two of them running different victory
## rules would disagree about whether the match is over -- which `state_hash()`
## now catches, because the outcome is folded into it.
var mode: Mode = Mode.LAST_MAN_STANDING

## The map to play on (PLAN.md 2.4b), or null for the fixed debug map.
##
## Carried as DATA rather than as a seed plus a type, and that is deliberate. A seed
## only reproduces a map through the exact generator that made it, so a config holding
## one would silently mean a different map after any generator change -- and, worse,
## host and client would each run `FastNoiseLite` on different CPUs. The map travels
## as the map. `seed`/`map_type` below are kept alongside it as PROVENANCE, for the
## skirmish screen to display and for Re-generate to work from.
var map_data: MapData = null
var seed: int = 0
var map_type: MapGenerator.Type = MapGenerator.Type.RANDOM

## Which slots are bots, position for position with `player_ids` (PLAN.md 12.2a).
## EMPTY means every player is human, which is what every debug factory here wants.
## Read by `SimWorld.setup()` into `SimPlayer.is_ai`.
var ai_players: Array[bool] = []


## A generated skirmish: two players, yellow against red, on a real procedural map.
##
## The config a `Skirmish.tscn` (1.6) will build once it exists, and what the tests and
## `dev_preview` use to exercise a generated map today.
static func debug_generated(p_seed: int = 1,
		type: MapGenerator.Type = MapGenerator.Type.RANDOM, players: int = 2) -> MatchConfig:
	var c := MatchConfig.new()
	c.player_ids = []
	c.colours = []
	var palette := [&"colour.yellow", &"colour.red", &"colour.blue", &"colour.cyan",
			&"colour.green", &"colour.violet", &"colour.orange", &"colour.white"]
	for i in range(clampi(players, MapGenerator.MIN_PLAYERS, MapGenerator.MAX_PLAYERS)):
		c.player_ids.append(i + 1)
		c.colours.append(_colour(palette[i % palette.size()]))

	c.seed = p_seed
	c.map_type = type
	c.map_data = MapGenerator.generate(p_seed, type, c.player_ids.size())
	c.map_size = c.map_data.size
	return c

## Palette index (colours.json) per entry in `player_ids`, position for position.
## EMPTY means "derive from join order", which is what every player got before
## anything wanted to name its own colour, and what the lobby (1.6) will replace
## by filling this in from the picker.
##
## Part of the config rather than of SimWorld because it must be identical on
## every client: each builds its own world (2.4a), and two of them disagreeing
## about who is yellow is not a desync the state hash would ever catch -- colour
## does not enter it -- but it is the one difference players read the board by.
var colours: Array[int] = []


## The MVP session model (PLAN.md 1.1): one human, hosted on loopback.
static func debug_single_player() -> MatchConfig:
	var c := MatchConfig.new()
	c.player_ids = [1]
	c.colours = [_colour(&"colour.yellow")]
	c.map_size = DEBUG_MAP_SIZE
	return c


## The debug map with a hostile on it: the local player's usual start, plus a
## second player who owns nothing but MapGen.DEBUG_ENEMY_SQUAD -- a couple of
## soldiers a short way to the right of the town centre. What it buys is
## something on screen that is not ours: enemy tint, an enemy selection panel,
## and the target combat will need once it exists (there is no AttackCommand
## yet, so today they simply stand there).
##
## Not a second BASE. Both starts would land on the same tile -- `_start_origin`
## takes no player into account and 2.4b is where real start positions live --
## and a forced overlapping town centre is a worse lie than an army with no home.
##
## YELLOW against RED because the project owner picked them, and they are the two
## the palette separates furthest by lightness after blue (colours.json's L*
## ladder). It was originally a workaround -- for a day, red and yellow were the
## only two colour bakes that were current, the other six being stale rather than
## absent and rendering perfectly happily in the wrong shape. All eight are
## correct as of the 2026-08-16 rebake, so this is now a choice rather than a
## constraint, and any pair would work.
##
## THIS IS THE ONLY CONFIG 11.1 CAN ACTUALLY DECIDE, and that is what makes the
## win condition demoable at all: two players, so Last Man Standing has somebody
## to outlast. The opponent owns two soldiers and nothing else, so killing both of
## them ENDS THE MATCH in victory -- the intended demo, and also the thing to
## remember before wondering why a long sandbox session stopped. Nothing can
## attack the local player back yet (no AI, 12.2a), so defeat is only reachable by
## debug-destroying your own town centre and villagers.
static func debug_skirmish() -> MatchConfig:
	var c := MatchConfig.new()
	c.player_ids = [1, 2]
	c.colours = [_colour(&"colour.yellow"), _colour(&"colour.red")]
	c.map_size = DEBUG_MAP_SIZE
	return c


## A palette index by name, falling back to join order (-1 is what
## SimWorld.setup reads as "no preference") if the palette has no such colour.
## The fallback is never expected to fire -- test_match_config pins both names --
## and exists so a mistyped colour costs a debug match its tint rather than its
## players.
static func _colour(id: StringName) -> int:
	return GameDataRegistry.colour_index(id) if GameDataRegistry != null else -1
