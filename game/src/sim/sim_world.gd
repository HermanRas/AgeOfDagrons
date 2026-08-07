## The authoritative simulation. No Node, no textures, no input -- runs
## identically whether hosted for a solo player or a dedicated server
## (PLAN.md 1.1, 5). Advances only when step() is called; real-time pacing
## is SimClock's job, not this class's.
class_name SimWorld
extends RefCounted

const SUBTILE := 256

## Placeholder unit stats until GameDataRegistry (phase 0.4) loads units.json.
## Every def_id spawned before then falls back to these defaults.
const _UNIT_DEFS := {
	&"unit.villager": {"hp": 30, "speed": 200, "vision_range": 4},
}

var tick: int = 0
var map: SimMap = null
var players: Array[SimPlayer] = []
var entities: Dictionary = {}          # int id -> SimEntity
var spatial: SpatialHash = null
var _next_id: int = 1
var _pending: Array[Command] = []
var _systems: Array[SimSystem] = []


func setup(cfg: MatchConfig) -> void:
	tick = 0
	entities.clear()
	players.clear()
	map = SimMap.create(cfg.map_size)
	spatial = SpatialHash.new()
	_next_id = 1
	_pending.clear()
	_systems = [CommandSystem.new(), TaskSystem.new(), MovementSystem.new()]

	for pid in cfg.player_ids:
		var p := SimPlayer.new()
		p.id = pid
		p.peer_id = pid
		players.append(p)


func step() -> void:
	tick += 1
	for s in _systems:
		s.process_tick(self)


func queue_command(cmd: Command) -> void:
	cmd.issued_tick = tick + 1
	_pending.append(cmd)


## Consumed once per tick by CommandSystem; not for other callers.
func drain_pending_commands() -> Array[Command]:
	var due := _pending
	_pending = []
	return due


func spawn_unit(def_id: StringName, owner: int, pos: Vector2i) -> SimUnit:
	var stats: Dictionary = _UNIT_DEFS.get(def_id, {})
	var u := SimUnit.new()
	u.id = _next_id
	_next_id += 1
	u.def_id = def_id
	u.owner_id = owner
	u.pos = pos * SUBTILE + Vector2i(SUBTILE / 2, SUBTILE / 2)
	u.hp = int(stats.get("hp", 30))
	u.max_hp = u.hp
	u.vision_range = int(stats.get("vision_range", 4))
	u.speed = int(stats.get("speed", 200))
	u.task_target_tile = pos

	entities[u.id] = u
	spatial.insert(u.id, u.tile())
	return u


func despawn(id: int) -> void:
	if not entities.has(id):
		return
	spatial.remove(id)
	entities.erase(id)


func get_entity(id: int) -> SimEntity:
	return entities.get(id)


func entities_in_radius(tile: Vector2i, r: int) -> Array[SimEntity]:
	var found: Array[SimEntity] = []
	for id in spatial.query_radius(tile, r):
		var e: SimEntity = entities.get(id)
		if e != null and e.alive:
			found.append(e)
	return found


func entities_in_rect(rect: Rect2i) -> Array[SimEntity]:
	var found: Array[SimEntity] = []
	for id in spatial.query_rect(rect):
		var e: SimEntity = entities.get(id)
		if e != null and e.alive:
			found.append(e)
	return found


## Desync/regression detection (PLAN.md 7.7 layer 3): the same MatchConfig +
## command log run twice must hash identically. Dictionary iteration order in
## `entities` isn't guaranteed, so entity ids are sorted before folding them
## in -- without that, two identically-behaving runs could still hash
## differently for no reason but map insertion order.
func state_hash() -> int:
	var ids := entities.keys()
	ids.sort()

	# The map is in the hash from 2.1 on. Without it, two clients that disagreed
	# about where the walls are would still hash identically and the desync check
	# would pass while the simulations diverged.
	var parts: Array = [tick, map.state_hash() if map != null else 0]
	for id in ids:
		var e: SimEntity = entities[id]
		parts.append([e.id, e.def_id, e.owner_id, e.pos.x, e.pos.y, e.hp, e.alive])
		if e is SimUnit:
			parts.append([e.task, e.task_target_tile.x, e.task_target_tile.y, e.facing])

	for p in players:
		var stock_keys := p.stock.keys()
		stock_keys.sort()
		var stock: Array = []
		for k in stock_keys:
			stock.append([k, p.stock[k]])
		parts.append([p.id, p.pop_used, p.pop_cap, p.age, stock])

	return hash(parts)
