## The authoritative simulation. No Node, no textures, no input -- runs
## identically whether hosted for a solo player or a dedicated server
## (PLAN.md 1.1, 5). Advances only when step() is called; real-time pacing
## is SimClock's job, not this class's.
class_name SimWorld
extends RefCounted

const SUBTILE := 256

## Fallback unit stats for when no definition can be found. 0.4 replaced the
## hardcoded table with GameDataRegistry lookups, so this is now only reached by a
## typo'd def_id -- and it exists so that a bad id spawns something visible and
## obviously wrong rather than crashing the host mid-match. `validate()` in the
## registry is what is meant to catch the typo, on the ground, before this does.
const _FALLBACK_UNIT := {"hp": 1, "speed": 100, "vision_range": 2, "domain": &"land"}

var tick: int = 0
var map: SimMap = null
var players: Array[SimPlayer] = []
var entities: Dictionary = {}          # int id -> SimEntity
var spatial: SpatialHash = null
var paths: PathService = null
var _next_id: int = 1
var _pending: Array[Command] = []
var _systems: Array[SimSystem] = []

## Ids despawned THIS tick, for SnapshotSystem's `removed[]` (PLAN.md 7.2).
## Cleared at the top of step() rather than drained by the first reader, so
## every player's snapshot this tick sees the same list (SimHost calls
## SnapshotSystem.build() once per player per tick).
var removed_this_tick: Array[int] = []


func setup(cfg: MatchConfig) -> void:
	tick = 0
	entities.clear()
	players.clear()
	map = SimMap.create(cfg.map_size)
	spatial = SpatialHash.new()
	paths = PathService.new()
	_next_id = 1
	_pending.clear()
	removed_this_tick.clear()
	# Order is load-bearing: a command lands, its path is planned, MOVE is retired
	# if it already finished, GATHER/RETURN/BUILD act if they have arrived -- and
	# only then does everyone move, so an action that starts a new route this tick
	# (a load handed off, a build finished) is walked the same tick rather than
	# costing an extra one of visible delay. SeparationSystem (4.2) runs right
	# after MovementSystem, as a correction on top of this tick's step rather than
	# a second movement -- TaskSystem reads arrival on the NEXT tick, by which
	# point any push has already landed. AnimationSystem runs after everything
	# that can retire or advance a task this tick, so `anim` reflects where a
	# unit actually ended up rather than where it started. DeathSystem runs
	# last: it reacts to hp reaching 0 (a debug command, later combat), and
	# everything else this tick has already had its say about a unit or
	# building that is now gone.
	_systems = [CommandSystem.new(), PathSystem.new(), TaskSystem.new(),
			GatherSystem.new(), BuildSystem.new(), ProductionSystem.new(), MovementSystem.new(),
			SeparationSystem.new(), AnimationSystem.new(), DeathSystem.new()]

	for pid in cfg.player_ids:
		var p := SimPlayer.new()
		p.id = pid
		p.peer_id = pid
		players.append(p)


func step() -> void:
	tick += 1
	removed_this_tick.clear()
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
	var u := SimUnit.new()
	u.id = _next_id
	_next_id += 1
	u.def_id = def_id
	u.owner_id = owner
	u.pos = pos * SUBTILE + Vector2i(SUBTILE / 2, SUBTILE / 2)
	u.task_target_tile = pos

	var d: UnitDef = unit_def(def_id)
	if d != null:
		u.hp = d.hp
		u.max_hp = d.hp
		u.vision_range = d.los
		u.speed = d.speed
		u.domain = SimMap.from_domain_name(d.domain)
	else:
		u.hp = int(_FALLBACK_UNIT["hp"])
		u.max_hp = u.hp
		u.vision_range = int(_FALLBACK_UNIT["vision_range"])
		u.speed = int(_FALLBACK_UNIT["speed"])

	entities[u.id] = u
	spatial.insert(u.id, u.tile())
	return u


## Place a building with its top-left tile at `origin`, claiming its footprint in
## the grid. Returns null if the footprint will not fit, so callers cannot end up
## with a building the map does not know about.
##
## `force` skips the placement check for 2.6's starting town centres, which are
## put down before any legality rules apply to the player.
func spawn_building(def_id: StringName, owner: int, origin: Vector2i,
		phase: SimBuilding.Phase = SimBuilding.Phase.COMPLETE,
		force := false) -> SimBuilding:
	var d: BuildingDef = building_def(def_id)
	var footprint := d.footprint if d != null else Vector2i.ONE
	var rect := SimMap.footprint_rect(origin, footprint)

	if not force and not map.can_place_building(rect):
		return null

	var b := SimBuilding.new()
	b.id = _next_id
	_next_id += 1
	b.def_id = def_id
	b.owner_id = owner
	b.footprint = footprint
	b.pos = SimBuilding.centre_of(origin, footprint)
	b.phase = phase

	if d != null:
		b.max_hp = d.hp
		b.vision_range = d.los
		b.provides_pop = d.provides_pop
		b.garrison_cap = d.garrison_cap
		b.build_total = d.build_time_ticks
	else:
		b.max_hp = 1

	# A completed building starts at full health; one still being built starts at a
	# sliver, so its health dot reads as damaged while it goes up (5.2/5.6).
	b.hp = b.max_hp if phase == SimBuilding.Phase.COMPLETE else maxi(1, b.max_hp / 10)
	if phase == SimBuilding.Phase.COMPLETE:
		b.build_progress = b.build_total

	entities[b.id] = b
	spatial.insert(b.id, b.tile())
	map.set_occupied(rect, b.id)
	_occupancy_changed(rect)
	return b


## Place a resource node on a single tile, claiming it. Returns null if the tile is
## not free, so two trees can never occupy one tile.
func spawn_resource_node(def_id: StringName, tile: Vector2i, size_class: int = 0) -> SimResourceNode:
	var rect := Rect2i(tile, Vector2i.ONE)
	if not map.can_place_building(rect):
		return null

	var d: ResourceDef = resource_def(def_id)
	var n := SimResourceNode.new()
	n.id = _next_id
	_next_id += 1
	n.def_id = def_id
	n.owner_id = 0                    # gaia; nodes belong to nobody
	n.pos = tile * SUBTILE + Vector2i(SUBTILE / 2, SUBTILE / 2)
	n.size_class = size_class

	if d != null:
		n.kind = d.kind
		n.amount = d.amount_for(size_class)
		n.gather_slots = d.gather_slots
		n.is_wildlife = d.is_wildlife
	n.starting_amount = n.amount
	n.hp = maxi(1, n.amount)
	n.max_hp = n.hp

	entities[n.id] = n
	spatial.insert(n.id, n.tile())
	map.set_occupied(rect, n.id)
	_occupancy_changed(rect)
	return n


func despawn(id: int) -> void:
	if not entities.has(id):
		return
	# Free the grid before dropping the entity: occupancy is keyed by id, so once
	# it is out of `entities` there is nothing left to look its footprint up from
	# and the tiles would stay claimed forever by a building that no longer exists.
	free_footprint(id)
	spatial.remove(id)
	entities.erase(id)
	if paths != null:
		paths.cancel(id)          # a queued search for a dead unit is wasted work
	removed_this_tick.append(id)


## Frees the tiles an entity holds in the occupancy grid without removing the
## entity itself. A destroyed building (5.5) keeps existing as rubble -- still in
## `entities`, still drawn -- but must stop blocking placement and pathing the
## instant it falls, same as despawn() would free them for a building that is
## gone entirely.
func free_footprint(id: int) -> void:
	if not entities.has(id):
		return
	var freed := _footprint_of(entities[id])
	if map != null:
		map.clear_occupant(id)
	_occupancy_changed(freed)


## The tiles an entity holds in the occupancy grid. Units hold none -- they are in
## SpatialHash, not the grid (SimMap's static-footprint rule) -- so removing one
## changes nothing the pathfinder cares about.
func _footprint_of(e: SimEntity) -> Rect2i:
	if e is SimUnit:
		return Rect2i()
	if e is SimBuilding:
		return (e as SimBuilding).footprint_rect()
	return Rect2i(e.tile(), Vector2i.ONE)


## Tell the pathfinder which tiles went stale. Deferred rather than applied here,
## so placing or destroying several things in one tick costs one update.
func _occupancy_changed(rect: Rect2i) -> void:
	if paths != null and rect.size.x > 0 and rect.size.y > 0:
		paths.mark_dirty(rect)


func get_entity(id: int) -> SimEntity:
	return entities.get(id)


func player_for(owner: int) -> SimPlayer:
	for p in players:
		if p.id == owner:
			return p
	return null


## The nearest complete building of `owner`'s that accepts `kind`, for a loaded
## villager heading home (6.4). Entity ids are walked in SORTED order and ties
## broken by strict `<`, never "first found" over `entities`' own iteration order
## -- two clients disagreeing about which of two equidistant town centres a
## villager returns to is a desync (PLAN.md 7.1).
func nearest_drop_off(owner: int, kind: StringName, from: Vector2i) -> SimBuilding:
	var ids := entities.keys()
	ids.sort()
	var best: SimBuilding = null
	var best_d := -1
	for id in ids:
		var e: SimEntity = entities[id]
		if not (e is SimBuilding):
			continue
		var b: SimBuilding = e
		if b.owner_id != owner or not b.alive or not b.is_complete():
			continue
		var d: BuildingDef = building_def(b.def_id)
		if d == null or not d.accepts_drop_off(kind):
			continue
		var dist := (b.tile() - from).length_squared()
		if best == null or dist < best_d:
			best = b
			best_d = dist
	return best


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


# â”€â”€ definition lookups â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
#
# The sim reads static data from the GameDataRegistry autoload. That is a Node,
# which sits close to the src/sim/ boundary rule (PLAN.md 4), so the reasoning is
# worth stating: the rule exists so the sim needs no window, no rendering and no
# input, and a pure-data registry costs it none of those -- these calls touch no
# tree, no texture and no signal, and the headless suite exercises them every run.
#
# What it does cost is the ability to run two worlds on different data sets in one
# process. Nothing wants that today. If a replay ever has to be validated against
# the data it was recorded with, this becomes a `defs` reference injected by
# setup() rather than a global, and these three functions are the only call sites
# that change.
#
# All three return null for an unknown id rather than inventing stats, matching
# GameDataRegistry's own convention.

func unit_def(def_id: StringName) -> UnitDef:
	return GameDataRegistry.unit(def_id) if GameDataRegistry != null else null


func building_def(def_id: StringName) -> BuildingDef:
	return GameDataRegistry.building(def_id) if GameDataRegistry != null else null


func resource_def(def_id: StringName) -> ResourceDef:
	return GameDataRegistry.resource_def(def_id) if GameDataRegistry != null else null


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
			# Path PROGRESS, not the route itself: two clients that planned
			# differently diverge in position within a few ticks anyway, but
			# hashing where each unit is along its route catches it on the tick it
			# happens rather than after it has been walked out (4.2).
			parts.append([e.task, e.task_target_tile.x, e.task_target_tile.y, e.facing,
					e.path.size(), e.path_index, e.path_pending,
					e.task_target_id, e.gather_node_id, e.carry_kind, e.carry_amount,
					e.gather_cooldown])
		elif e is SimBuilding:
			# BuildSystem (4.4) now advances build_progress at runtime rather than
			# only at spawn, and ProductionSystem (5.4) advances queue -- two
			# clients diverging in either would otherwise hash identically.
			var q: Array = []
			for entry in e.queue:
				q.append([entry.get("def_id", &""), entry.get("progress", 0), entry.get("ready", false)])
			parts.append([e.phase, e.build_progress, q])
		elif e is SimResourceNode:
			# GatherSystem (6.4) depletes this at runtime; without it two clients
			# whose villagers gathered at different rates would hash identically
			# right up until the node ran out on one of them and not the other.
			parts.append([e.amount])

	for p in players:
		var stock_keys := p.stock.keys()
		stock_keys.sort()
		var stock: Array = []
		for k in stock_keys:
			stock.append([k, p.stock[k]])
		# SetControlGroupCommand (10.2) mutates SimPlayer state -- two clients
		# applying it differently would otherwise hash identically right up until
		# a reselect or reconnect (10.6) exposed the divergence.
		parts.append([p.id, p.pop_used, p.pop_cap, p.age, stock, p.control_groups])

	return hash(parts)
