## What SimWorld.setup() needs to stand up a match: which players exist, what
## colour each of them is, and how big the map is. Colour, not faction: v1 is one
## shared civilisation (PLAN.md 1), and a faction picker only arrives with 9.5.
## Win conditions join this at the lobby (1.6), which is also what will fill
## `colours` from a picker rather than from a debug factory below;
## the actual terrain layout is 2.4a's job, not this class's -- `map_size` only
## says how much grid to allocate.
class_name MatchConfig
extends RefCounted

## Deliberately small. PLAN.md 10's MVP is "one small map on a phone", and an 8x8
## town centre plus 5 villagers on 64x64 tiles is already a generous settlement's
## worth of room. 2.4b scales size with player count.
const DEBUG_MAP_SIZE := Vector2i(64, 64)

var player_ids: Array[int] = []
var map_size: Vector2i = DEBUG_MAP_SIZE

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
## YELLOW against RED, not the join-order blue/red, because those two are the
## only player-colour bakes known to be current: the other six are stale rather
## than absent, and render perfectly happily in the wrong shape
## (GameDataRegistry.stale_colour_atlases()). A debug match should be looking at
## art that is right.
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
