## One player's persistent state within a match: stock, population, and (later)
## age/tech/control groups. Control groups persist here rather than client-side
## so they survive reconnect (PLAN.md 7.1).
class_name SimPlayer
extends RefCounted

## PLAN.md 10.1: fixed at 5, not configurable -- the HUD is a fixed vertical
## stack of 5 slots, not a scrollable list.
const CONTROL_GROUP_COUNT := 5

var id: int = 0
var peer_id: int = 0                 # 1 = host's own local player
## PLAN.md 2.7.1: half of the skin key. v1 ships one civilisation, so this is
## `faction.default` for every player and only `colour` below tells players apart.
## The field stays because civs return at 9.5 as a re-skin over this same roster,
## and it defaults to a real ID rather than &"" so no later check has to special-
## case an empty one -- which is what factions.json's own note always claimed.
var faction: StringName = &"faction.default"
## PLAN.md 1: the ONE thing that differs between players in v1. A palette index,
## not a Color -- the palette is data (colours.json, with the lobby at 1.6) and
## the tint itself is a view concern (A.6).
var colour: int = 0
var is_ai: bool = false
var team: int = 0
var stock: Dictionary = {}           # StringName kind -> int amount
var pop_used: int = 0
var pop_cap: int = 0
var age: int = 1
var researched: Dictionary = {}
var control_groups: Array = [[], [], [], [], []]          # Array[Array[int]], one per CONTROL_GROUP_COUNT slot
var defeated: bool = false


func can_afford(cost: Dictionary) -> bool:
	for kind in cost:
		if int(stock.get(kind, 0)) < int(cost[kind]):
			return false
	return true


func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for kind in cost:
		stock[kind] = int(stock.get(kind, 0)) - int(cost[kind])
	return true


func refund(cost: Dictionary) -> void:
	for kind in cost:
		add_resource(kind, int(cost[kind]))


func add_resource(kind: StringName, amount: int) -> void:
	stock[kind] = int(stock.get(kind, 0)) + amount
