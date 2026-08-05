## One player's persistent state within a match: stock, population, and (later)
## age/tech/control groups. Control groups persist here rather than client-side
## so they survive reconnect (PLAN.md 7.1).
class_name SimPlayer
extends RefCounted

var id: int = 0
var peer_id: int = 0                 # 1 = host's own local player
var faction: StringName = &""
var is_ai: bool = false
var team: int = 0
var stock: Dictionary = {}           # StringName kind -> int amount
var pop_used: int = 0
var pop_cap: int = 0
var age: int = 1
var researched: Dictionary = {}
var control_groups: Array = [[], [], [], [], []]
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
