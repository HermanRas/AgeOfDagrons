## What SimWorld.setup() needs to stand up a match: which players exist and how
## big the map is. Faction and win-condition fields join this at the lobby (1.6);
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


## The MVP session model (PLAN.md 1.1): one human, hosted on loopback.
static func debug_single_player() -> MatchConfig:
	var c := MatchConfig.new()
	c.player_ids = [1]
	c.map_size = DEBUG_MAP_SIZE
	return c
