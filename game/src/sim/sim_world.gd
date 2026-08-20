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

## How this match is won and how it ended (PLAN.md 11.1). `mode` comes from
## MatchConfig and never changes; the other two are written ONLY by
## WinConditionSystem, which stops evaluating once `match_over` is set.
##
## `winner_id` is 0 both before anybody has won and for the draw where the last
## players fall on the same tick -- `match_over` is what tells those two apart, and
## it is why this is two fields rather than one. A defeated player in a match still
## being fought is neither: they read their own `SimPlayer.defeated`.
var mode: MatchConfig.Mode = MatchConfig.Mode.LAST_MAN_STANDING
var match_over: bool = false
var winner_id: int = 0

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
	mode = cfg.mode
	match_over = false
	winner_id = 0
	# A carried map decides its own size; `cfg.map_size` is the debug-map default and
	# the fallback. Taking the map's own size means a config cannot be half-applied --
	# a 96x96 map into a 64x64 grid would silently crop a quarter of it off.
	map = SimMap.create(cfg.map_data.size if cfg.map_data != null else cfg.map_size)
	spatial = SpatialHash.new()
	paths = PathService.new()
	_next_id = 1
	_pending.clear()
	removed_this_tick.clear()
	# Order is load-bearing: a command lands, its path is planned, MOVE is retired
	# if it already finished, GATHER/RETURN/BUILD act if they have arrived -- and
	# only then does everyone move, so an action that starts a new route this tick
	# (a load handed off, a build finished, a chase re-planned) is walked the same
	# tick rather than costing an extra one of visible delay. CombatSystem (4.13)
	# sits with Gather and Build for exactly that reason, and before DeathSystem so
	# a kill becomes a corpse on the tick it lands. SeparationSystem (4.2) runs right
	# after MovementSystem, as a correction on top of this tick's step rather than
	# a second movement -- TaskSystem reads arrival on the NEXT tick, by which
	# point any push has already landed. AnimationSystem runs after everything
	# that can retire or advance a task this tick, so `anim` reflects where a
	# unit actually ended up rather than where it started. DeathSystem runs
	# last: it reacts to hp reaching 0 (a debug command, later combat), and
	# everything else this tick has already had its say about a unit or
	# building that is now gone.
	# AgeSystem sits beside ProductionSystem: both turn queued time into a thing
	# arriving, and both must run after CommandSystem has let this tick's orders
	# land so an advance started this tick is already counting.
	# PopulationSystem and VisionSystem are after DeathSystem: both recount what
	# EXISTS, so both must see the finished tick rather than the middle of one. Vision
	# specifically must not be lit by a scout that died this tick, in the very
	# snapshot that reports the death.
	# WinConditionSystem (11.1) is after those, for the same reason and one more: a
	# player whose last building fell THIS tick has lost as of this tick, and every
	# system that could still have saved them has already had its say.
	# AISystem (12.2a) is last of all, and that is what makes it fair: it looks at the
	# finished tick and its orders are queued for the next one, exactly like a player
	# reacting to what is on screen. Running it earlier would let it act on a
	# half-finished tick that no human can see.
	_systems = [CommandSystem.new(), PathSystem.new(), TaskSystem.new(),
			GatherSystem.new(), BuildSystem.new(), CombatSystem.new(),
			ProductionSystem.new(), AgeSystem.new(),
			MovementSystem.new(), SeparationSystem.new(), AnimationSystem.new(),
			DeathSystem.new(), PopulationSystem.new(), VisionSystem.new(),
			WinConditionSystem.new(), AISystem.new()]

	for i in range(cfg.player_ids.size()):
		var p := SimPlayer.new()
		p.id = cfg.player_ids[i]
		p.peer_id = p.id
		# PLAN.md 1: colour is the only thing that distinguishes players in v1, so
		# it is never left 0 for everyone. The config may name it (a debug factory
		# today, the lobby's picker at 1.6); when it does not, it falls back to the
		# JOIN ORDER, which is derived rather than chosen and so is the same answer
		# on every client -- and every client builds its own world (2.4a).
		var chosen: int = cfg.colours[i] if i < cfg.colours.size() else -1
		p.colour = chosen if chosen >= 0 else i
		# Who is a bot (PLAN.md 12.2a), picked per slot in the skirmish screen (1.6).
		# The FIELD has existed since 0.6 with nothing writing it; this is the config
		# side of it. `AISystem` is what will read it.
		p.is_ai = bool(cfg.ai_players[i]) if i < cfg.ai_players.size() else false
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
		u.pop_cost = d.pop_cost
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

	# Anything already built here is rubble, and rubble goes when it is built over
	# (project owner, 2026-08-16). It cannot BLOCK the placement -- a destroyed
	# building freed its tiles the tick it fell (5.5) -- so without this the new
	# building simply goes up on top of the wreckage and the debris shows through
	# around its edges for the rest of the minute.
	_clear_rubble_under(rect)

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
		# A field carries a crop; every other building carries nothing and these
		# stay at their zero defaults.
		b.gather_kind = d.gather_kind
		b.gather_amount = d.gather_amount
		b.gather_slots = d.gather_slots
	else:
		b.max_hp = 1

	# A completed building starts at full health; one still being built starts at a
	# sliver, so its health dot reads as damaged while it goes up (5.2/5.6).
	b.hp = b.max_hp if phase == SimBuilding.Phase.COMPLETE else maxi(1, b.max_hp / 10)
	if phase == SimBuilding.Phase.COMPLETE:
		b.build_progress = b.build_total

	entities[b.id] = b
	spatial.insert(b.id, b.tile())
	map.set_occupied(rect, b.id, d == null or d.blocks_movement)
	_occupancy_changed(rect)
	return b


## Whether `def_id` may be placed at `origin` by `player_id` given what else is
## already standing -- the adjacency half of placement legality, on top of the
## grid's own "does the footprint fit".
##
## Lives on SimWorld rather than inside PlaceBuildingCommand because BOTH sides
## need the same answer from the same code: the command validates it (the server
## is the only trust boundary) and PlacementGhost colours the drag by it, so a
## player is never shown a green ghost for a placement the host will refuse. Two
## implementations of this rule would disagree the first time either changed.
##
## True for everything that declares no `requires_adjacent`, which is every
## building but the field.
func adjacency_allows(def_id: StringName, player_id: int, origin: Vector2i) -> bool:
	var d: BuildingDef = building_def(def_id)
	if d == null or d.requires_adjacent.is_empty():
		return true

	var rect := SimMap.footprint_rect(origin, d.footprint)
	var host := _adjacent_host(d, player_id, rect)
	if host == null:
		return false
	# The cap is per AGE (2026-08-17): two fields to a mill at age 2, three at 3,
	# four at 4. Read off the placing player, and a player who is not in this world
	# is treated as age 1, which caps at 0 and refuses -- the same direction every
	# other unknown is resolved in.
	var player := player_for(player_id)
	var cap := d.max_per_host_for_age(player.age if player != null else 1)
	if cap <= 0 and d.max_per_host_by_age.is_empty():
		return true          # no limit declared at all
	if cap <= 0:
		return false         # a limit that is zero at this age, e.g. fields in age 1
	return _count_abutting(d.id, player_id, host) < cap


## A COMPLETE building of `player`'s, of one of the kinds `d` must abut, whose
## own footprint touches `rect`. Ids are walked in sorted order and the first hit
## wins, so two mills equally close cannot make two clients pick different hosts
## and disagree about the four-field cap.
##
## Complete, not merely present: a field abutting a mill FOUNDATION would be a
## farm serving a building that does not exist yet, and the foundation may still
## be cancelled or destroyed under it.
func _adjacent_host(d: BuildingDef, player: int, rect: Rect2i) -> SimBuilding:
	var ids := entities.keys()
	ids.sort()
	for id in ids:
		var e: SimEntity = entities[id]
		if not (e is SimBuilding):
			continue
		var b: SimBuilding = e
		if b.owner_id != player or not b.alive or not b.is_complete():
			continue
		if not d.requires_adjacent.has(b.def_id):
			continue
		if b.footprint_rect().grow(1).intersects(rect):
			return b
	return null


## How many `def_id` buildings of `player`'s already touch `host`.
func _count_abutting(def_id: StringName, player: int, host: SimBuilding) -> int:
	var around := host.footprint_rect().grow(1)
	var n := 0
	for id in entities:
		var e: SimEntity = entities[id]
		if not (e is SimBuilding):
			continue
		var b: SimBuilding = e
		if b.def_id != def_id or b.owner_id != player or not b.alive:
			continue
		# Foundations count. A player who has queued four fields around a mill
		# has used it up, or the cap would be beatable by placing all four before
		# any of them finished.
		if b.phase == SimBuilding.Phase.DESTROYED:
			continue
		if b.footprint_rect().intersects(around):
			n += 1
	return n


## Despawn every piece of rubble the new footprint covers -- ANY overlap, not
## just an exact match, since a small house going up on one corner of a fallen
## town centre still has to take the whole ruin with it. Half-cleared wreckage
## sticking out from under a new building would look worse than leaving all of
## it.
##
## Ids are collected before despawning: despawn() mutates `entities`, which
## cannot be done while iterating it. Sorted, because despawn order reaches
## `removed_this_tick` and two clients disagreeing about it is a difference in
## the wire format for no reason.
func _clear_rubble_under(rect: Rect2i) -> void:
	var doomed: Array[int] = []
	for id in entities:
		var e: SimEntity = entities[id]
		if not (e is SimBuilding):
			continue
		var b: SimBuilding = e
		if b.phase != SimBuilding.Phase.DESTROYED:
			continue
		if b.footprint_rect().intersects(rect):
			doomed.append(b.id)
	doomed.sort()
	for id in doomed:
		despawn(id)


## Place a resource node with its top-left tile at `origin`, claiming its whole
## footprint. Returns null if the ground is not free, so two trees can never occupy
## one tile and a 4x4 seam cannot go up half on top of a house.
##
## `origin` is the TOP-LEFT tile, matching `spawn_building` -- and for everything
## 1x1, which is every tree, bush and animal, that is the same tile it always was.
func spawn_resource_node(def_id: StringName, origin: Vector2i, size_class: int = 0) -> SimResourceNode:
	var d: ResourceDef = resource_def(def_id)
	var footprint := d.footprint_for_size(size_class) if d != null else Vector2i.ONE
	var rect := SimMap.footprint_rect(origin, footprint)
	if not map.can_place_building(rect):
		return null

	var n := SimResourceNode.new()
	n.id = _next_id
	_next_id += 1
	n.def_id = def_id
	n.owner_id = 0                    # gaia; nodes belong to nobody
	n.footprint = footprint
	n.pos = SimBuilding.centre_of(origin, footprint)
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
	if e is SimResourceNode:
		return (e as SimResourceNode).footprint_rect()
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
					e.task_target_id, e.gather_node_id, e.gather_node_tile.x,
					e.gather_node_tile.y, e.carry_kind, e.carry_amount,
					# Both cooldowns. Two clients whose attackers were a single tick
					# out of step would land their blows on different ticks and then
					# disagree about who died first -- `hp` reports that only once it
					# has already happened, and by then neither can say when they parted.
					e.gather_cooldown, e.attack_cooldown])
		elif e is SimBuilding:
			# BuildSystem (4.4) now advances build_progress at runtime rather than
			# only at spawn, and ProductionSystem (5.4) advances queue -- two
			# clients diverging in either would otherwise hash identically.
			var q: Array = []
			for entry in e.queue:
				q.append([entry.get("def_id", &""), entry.get("progress", 0), entry.get("ready", false)])
			# The rubble timer is in here because it ENDS IN A DESPAWN: two clients
			# a tick apart on it would clear the same wreckage on different ticks
			# and disagree about `removed[]`.
			# `gather_amount` is a field's crop, depleted at runtime exactly as a
			# tree's is -- two clients whose villagers farmed at different rates
			# would otherwise hash identically until one field ran out first.
			parts.append([e.phase, e.build_progress, q, e.rubble_ticks_left,
					e.gather_amount])
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
		#
		# The advancement fields are here for the same reason and NOT because the
		# age itself is: `age` only changes on the one tick the research lands, so
		# two worlds that started an advance at different ticks would agree on
		# every hash until it completed, and then disagree with nothing to say
		# when they parted. The in-flight counter is what makes that visible
		# immediately. `colour` stays out -- it is fixed at join and never mutates.
		# `defeated` (11.1) is in here because it is the one per-player fact that is
		# IRREVERSIBLE: two clients that eliminated a player on different ticks would
		# otherwise agree on every hash until one of them declared a winner.
		# `vision` (2.5) is in here because it decides WHAT EACH CLIENT IS SENT: two
		# hosts that disagreed about who can see what would disagree about the wire
		# contents while every entity in the world still matched, and the fog is the
		# one piece of per-player state that is never echoed back to be checked.
		parts.append([p.id, p.pop_used, p.pop_cap, p.age, stock, p.control_groups,
				p.advancing_to, p.advance_ticks, p.advance_total_ticks, p.defeated,
				p.vision])

	# The outcome itself, which is the single most important thing in the hash to get
	# right: two clients that disagree about who won have diverged about the only
	# question the match was asked. `mode` stays out -- it comes from MatchConfig and
	# never mutates, the same reason `colour` stays out above.
	parts.append([match_over, winner_id])

	return hash(parts)
