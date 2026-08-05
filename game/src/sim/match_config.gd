## What SimWorld.setup() needs to stand up a match: which players exist.
## Map, faction and win-condition fields join this once their phases land
## (2.x, lobby) -- kept minimal for now rather than guessing their shape.
class_name MatchConfig
extends RefCounted

var player_ids: Array[int] = []


## The MVP session model (PLAN.md 1.1): one human, hosted on loopback.
static func debug_single_player() -> MatchConfig:
	var c := MatchConfig.new()
	c.player_ids = [1]
	return c
