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
	# ProjectileSystem (4.13) sits directly BEFORE CombatSystem, which is what looses
	# what it flies, so an arrow is never advanced on the tick it was created. Putting
	# it after was the first attempt and it was wrong: the arrow was spawned, stepped
	# and -- for any shot at the low end of the range -- landed and despawned inside a
	# single tick, so it never appeared in a snapshot at all. Every test passed and
	# nothing was ever drawn.
	# GarrisonSystem (4.8) sits with Gather and Build because it is the same kind of
	# thing: a unit that walked somewhere and acts on arrival. It is BEFORE
	# CombatSystem on purpose -- an archer admitted this tick is already adding its
	# damage to the tower's shot on this tick, which is the difference between "the
	# reinforcements arrived" and "the reinforcements arrived a moment ago".
	_systems = [CommandSystem.new(), PathSystem.new(), TaskSystem.new(),
			GatherSystem.new(), BuildSystem.new(), GarrisonSystem.new(),
			# WildlifeSystem BEFORE CombatSystem, so a wolf that picks a target this
			# tick bites on this tick. It only ever writes the same task an
			# AttackCommand would, which is why nothing in combat knows it exists.
			# HerdSystem beside WildlifeSystem and before the commands act, so a sheep
			# claimed this tick can be ordered on the next one.
			ProjectileSystem.new(), WildlifeSystem.new(), HerdSystem.new(),
			CombatSystem.new(),
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
		# And how hard it plays. A short or absent `ai_levels` leaves the default, so a
		# config from before difficulty existed still produces the AI it always did.
		p.ai_level = int(cfg.ai_levels[i]) if i < cfg.ai_levels.size() \
				else SimPlayer.AILevel.EASY
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
## `facing` is in the SIM convention and matters only to walls (SimBuilding's
## header): every other building is baked at one direction and stays at 0. It does
## NOT rotate the footprint -- `PlaceWallCommand` transposes that itself, because a
## footprint is grid arithmetic and a facing is which of eight sprites to draw, and
## conflating them would mean a diagonal wall silently claiming an axis-aligned box.
func spawn_building(def_id: StringName, owner: int, origin: Vector2i,
		phase: SimBuilding.Phase = SimBuilding.Phase.COMPLETE,
		force := false, footprint_override: Vector2i = Vector2i.ZERO,
		facing: int = 0) -> SimBuilding:
	var d: BuildingDef = building_def(def_id)
	var footprint := d.footprint if d != null else Vector2i.ONE
	# A WALL RUNNING NORTH-SOUTH IS ITS DEF'S FOOTPRINT TRANSPOSED. Passed in rather
	# than derived from `facing` here, so this function stays ignorant of what a wall
	# is: the caller that decided the axis is the caller that knows.
	if footprint_override != Vector2i.ZERO:
		footprint = footprint_override
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
	b.facing = facing

	if d != null:
		b.is_gate = d.is_gate
		b.max_hp = d.hp
		b.vision_range = d.los
		b.provides_pop = d.provides_pop
		b.garrison_cap = d.garrison_cap
		b.attack_damage = d.attack_damage
		b.attack_type = d.attack_type
		b.attack_range = d.attack_range
		b.attack_cooldown_ticks = d.attack_cooldown_ticks
		b.attack_projectile = d.attack_projectile
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
	# THROUGH `blocks_now()`, not off the def directly. A gate is placed OPEN (see
	# SimBuilding.gate_locked), so its footprint is claimed without being closed --
	# which also means nobody standing in the doorway is evicted, exactly as with a
	# field. Locking it later is what shoves them out, in `set_gate_locked()`.
	var blocks := b.blocks_now(d == null or d.blocks_movement)
	map.set_occupied(rect, b.id, blocks)
	if blocks:
		_evict_from_footprint(rect)
	_occupancy_changed(rect)
	return b


## Open or shut a gate, and move the movement grid with it (PLAN.md 5.8).
##
## The whole mechanism, and it is three lines because `SimMap.set_occupied` already
## takes a `blocks` flag -- the one a field uses to be claimed and walkable at once.
## A gate is the only thing in the game that changes its answer mid-match.
##
## LOCKING EVICTS WHOEVER IS IN THE DOORWAY, for the reason `_evict_from_footprint`
## records at length: a unit inside a blocked cell is a unit `AStarGrid2D` will not
## plan a route out of, so it stands there for the rest of the match. A gate swinging
## shut on a villager has to push them clear, and which side it pushes them to is
## whatever the fixed ring scan finds first -- deterministic, and not necessarily the
## side they were heading for.
func set_gate_locked(b: SimBuilding, locked: bool) -> void:
	b.gate_locked = locked
	var d: BuildingDef = building_def(b.def_id)
	var rect := b.footprint_rect()
	var blocks := b.blocks_now(d == null or d.blocks_movement)
	map.set_occupied(rect, b.id, blocks)
	if blocks:
		_evict_from_footprint(rect)
	_occupancy_changed(rect)


## Put `u` inside `b` (PLAN.md 4.8). True if it went in.
##
## THE WHOLE MECHANISM IS `spatial.remove()` WITHOUT `despawn()`, and that is worth
## saying plainly because it is the first time anything in the project takes an
## entity off the map without deleting it. The unit stays in `entities` -- so
## `PopulationSystem`, which recounts from scratch every tick, keeps charging for it,
## and hiding fifteen units in a castle does not buy fifteen free villagers -- while
## dropping out of `SpatialHash` makes it invisible to every query that matters:
## `CombatSystem._reacquire` cannot target it, `WildlifeSystem` cannot pick it as
## prey, and `GameView.pick()` cannot tap it.
##
## THE ROUTE IS CANCELLED AND THE TASK RETIRED. `stop()` rather than `halt()`: a unit
## that has arrived is done, and leaving GARRISON set would have `GarrisonSystem`
## re-admitting it every tick for as long as it stood there. It also matters that
## `paths.cancel` runs -- a queued search whose unit is no longer on the map would be
## written onto a route nobody can walk.
##
## Refused rather than clamped when there is no room, so the caller can say so. Both
## callers (`GarrisonCommand.validate` and `GarrisonSystem`) ask `has_garrison_room()`
## first; this asks again because it is the last gate before the state changes and
## the two callers run several ticks apart -- a fifth unit walking to a tower that
## filled up while it was walking is the ordinary case, not an edge one.
func garrison_unit(b: SimBuilding, u: SimUnit) -> bool:
	if b == null or u == null or not u.alive:
		return false
	if u.garrisoned_in != 0 or not b.has_garrison_room():
		return false

	u.garrisoned_in = b.id
	b.garrison.append({"id": u.id, "def_id": u.def_id})
	u.stop()
	if paths != null:
		paths.cancel(u.id)
	# The one line that takes it off the map. After `stop()`, so nothing can queue a
	# fresh search between the two.
	spatial.remove(u.id)
	# Idle rather than whatever it walked in playing. Nothing draws a garrisoned unit,
	# but it is drawn again the moment it comes out and a soldier that reappears
	# mid-stride reads as a teleport.
	u.anim = &"idle"
	return true


## Take `u` out of whatever it is inside and stand it beside the building. True if it
## came out.
##
## PLACED BY `find_free_adjacent`, NOT `_step_aside_tile`, and the two are not
## interchangeable -- `_step_aside_tile`'s own header draws the distinction. It
## answers "nearest tile to where this unit already is", which a garrisoned unit does
## not have: its `pos` is wherever it stood when it walked in, possibly minutes ago
## and possibly under somebody's house by now. `find_free_adjacent` answers "somewhere
## to put a unit coming out of this building", which is the same question
## `ProductionSystem` asks of every unit it trains, and it means a unit always
## reappears touching the building it was inside.
##
## SEVERAL UNITS CAN LAND ON ONE TILE, and that is not a bug here for the same reason
## it is not one in `ProductionSystem`: units are not written into map occupancy
## (SimMap's static-footprint rule), so `find_free_adjacent` reports free *terrain*
## and hands the same tile to each. `SeparationSystem` pushes them apart on the same
## tick, sorted by id, which is exactly how a barracks emptying its queue already
## behaves.
##
## SEALED IN IS A REAL OUTCOME AND IT REFUSES RATHER THAN TELEPORTING. If the scan
## finds nowhere legal at all -- a tower whose owner walled it in afterwards -- the
## unit stays inside and the command does nothing. The alternative, dropping it on an
## impassable tile, is the entombment `_evict_from_footprint`'s header spent a
## paragraph on: `AStarGrid2D` will not plan a route out of a solid cell, so the unit
## would be stuck for the rest of the match with nothing to say why.
## `send` is false for the one caller that does not want the rally point honoured:
## `DeathSystem._kill_garrison`, which puts the occupants out only so their corpses have
## somewhere to be. Walking a unit toward a flag on the tick it dies would queue a route
## search for a corpse -- harmless, since `PathService` drops requests for the dead, and
## still a lie about what happened.
func ungarrison_unit(b: SimBuilding, u: SimUnit, send := true) -> bool:
	if b == null or u == null:
		return false
	var index := b.garrison_index(u.id)
	if index < 0:
		return false

	var to := map.find_free_adjacent(b.footprint_rect(), u.domain)
	if to.x < 0:
		return false

	b.garrison.remove_at(index)
	u.garrisoned_in = 0
	u.pos = to * SUBTILE + Vector2i(SUBTILE / 2, SUBTILE / 2)
	u.task_target_tile = to
	spatial.insert(u.id, to)
	# PLACED FIRST, THEN SENT. The route has to be planned from where the unit actually
	# is, and until the two lines above it was nowhere -- out of the spatial index with
	# a `pos` from whenever it walked in.
	if send:
		send_to_waypoint(b, u)
	return true


## Walk `u` to `b`'s rally point, if it has one. True if an order was given.
##
## ONE IMPLEMENTATION, TWO CALLERS -- `ungarrison_unit` above and `ProductionSystem` --
## because they are the same rule ("anything leaving this building goes there") and
## `diplomacy.gd`'s header is a standing warning about what happens to a predicate
## written out twice. It also means the two can never disagree about whether a rally
## point survives, which is the sort of difference nobody would notice for weeks.
##
## AN UNREACHABLE RALLY POINT IS SELF-CORRECTING AND THAT IS DELIBERATE. `PathService`
## answers an impossible route with an empty path, `SimUnit.set_path([])` retires the
## task, and the unit simply stands where it came out -- which is exactly the old
## behaviour. The case that matters is a **dock**: its fishing ships are domain water
## and a rally point dropped on grass is unreachable for them, so a dock with a landward
## waypoint launches its boats and they stay put rather than being walked onto the beach.
## That was a real bug once (2026-08-23, "boats spawn and sail on land, its very funny"),
## and this is the shape that cannot reintroduce it.
func send_to_waypoint(b: SimBuilding, u: SimUnit) -> bool:
	if b == null or u == null or not u.alive or not b.waypoint_set():
		return false
	u.set_task_move(b.waypoint)
	if paths != null:
		paths.request(u.id, b.waypoint)
	return true


## Turn a standing building into a different one WHERE IT STANDS, keeping its id
## (PLAN.md 5.8). Today: a finished long wall segment becoming its tier's gate.
##
## IN PLACE, NOT DESPAWN-AND-RESPAWN, and the id is the reason. A respawn would hand
## the player's own selection a dead id the tick their upgrade landed, so the panel
## they pressed the button on would empty itself -- and it would file the wall under
## `removed_this_tick`, telling every other player's client that a building was
## destroyed when one was improved. Mutating keeps the selection, the view node and
## the pooled sprite; `GameView._visual_id_of` re-points the art off the new `def_id`
## on the next snapshot with nothing else to do.
##
## For an UPGRADE the footprint does not change -- `UpgradeBuildingCommand` refuses a
## target whose footprint differs, so the ground it holds is the ground it already
## held and no placement check is needed. Every def-derived field is re-read rather
## than patched selectively: a field left over from the old def is exactly the kind of
## thing that stays wrong quietly.
##
## `footprint_override` is the second caller, `WallMerge`: three short wall segments
## become one long one, and the survivor GROWS along its own axis. It keeps its
## ORIGIN -- the merge always survives the piece at the low end of the run -- so the
## new footprint extends over ground the absorbed pieces are giving up in the same
## tick, and there is still nothing to place-check. The old claim is cleared first
## regardless, because occupancy is keyed by id over a rect and a shrink would
## otherwise leave tiles held by a building that no longer covers them.
##
## HEALTH CARRIES ITS FRACTION, not its absolute value. A wall at 1200/1200 becoming
## a 1000 hp gate is undamaged, and a wall at half health becoming one at half health
## is the only rule that neither heals nor hurts as a side effect of upgrading. Full
## health is pinned exactly, so the commonest case cannot round to 999.
## `hp_override` is again for the merge, which adds its pieces' health together
## instead -- see `WallMerge` for why that is the honest sum there and a fraction is
## the honest one here.
func convert_building(b: SimBuilding, new_def_id: StringName,
		footprint_override: Vector2i = Vector2i.ZERO, hp_override: int = -1) -> void:
	var d: BuildingDef = building_def(new_def_id)
	if d == null:
		return

	var was_full := b.hp >= b.max_hp
	var old_max := maxi(1, b.max_hp)

	# BEFORE the footprint moves: `origin_tile()` derives the corner from `pos` and
	# the footprint together, so reading it after either changes reads a corner the
	# building never stood on.
	var origin := b.origin_tile()
	if footprint_override != Vector2i.ZERO and footprint_override != b.footprint:
		if map != null:
			map.clear_occupant(b.id)
		_occupancy_changed(b.footprint_rect())
		b.footprint = footprint_override
		b.pos = SimBuilding.centre_of(origin, b.footprint)
		spatial.move(b.id, b.tile())

	b.def_id = new_def_id
	b.is_gate = d.is_gate
	b.max_hp = d.hp
	b.vision_range = d.los
	b.provides_pop = d.provides_pop
	b.garrison_cap = d.garrison_cap
	b.attack_damage = d.attack_damage
	b.attack_type = d.attack_type
	b.attack_range = d.attack_range
	b.attack_cooldown_ticks = d.attack_cooldown_ticks
	b.attack_projectile = d.attack_projectile
	b.build_total = d.build_time_ticks
	b.gather_kind = d.gather_kind
	b.gather_amount = d.gather_amount
	b.gather_slots = d.gather_slots
	if hp_override >= 0:
		b.hp = clampi(hp_override, 1, b.max_hp)
	else:
		b.hp = b.max_hp if was_full else clampi(b.hp * b.max_hp / old_max, 1, b.max_hp)
	# A COMPLETE building stays complete. `build_progress` is compared against
	# `build_total`, and the new def's build time is a different number, so leaving the
	# old progress behind would make a finished gate read as a part-built one.
	if b.phase == SimBuilding.Phase.COMPLETE:
		b.build_progress = b.build_total

	# Through `blocks_now()` for the same reason `spawn_building` is: a wall blocks and
	# an unlocked gate does not, so this is the tick the hole appears. No eviction --
	# the only direction this can go today is solid-to-open, and `set_gate_locked` is
	# what handles the other one.
	var rect := b.footprint_rect()
	map.set_occupied(rect, b.id, b.blocks_now(d.blocks_movement))
	_occupancy_changed(rect)


## Nothing may be left standing INSIDE ground that has just become solid.
##
## `can_place_building()` asks the MAP whether the footprint is free, and units are
## not written into map occupancy -- they live in the spatial index -- so a building
## could be dropped straight on top of them. The unit was then inside a blocked
## region, and `AStarGrid2D` will no more plan a route OUT of a solid cell than into
## one: every path it asked for came back empty, `set_path([])` retired the task, and
## it stood there for the rest of the match unable to walk, gather or build.
##
## **This is what left the AI's barracks at 0% in the 12.2a run** (2026-08-20): the
## villager sent to raise it was sealed inside its own foundation, and the diagnostic
## read `barracks at (49,25), 0 builder(s), NO ROUTE from (49,27)` -- a tile squarely
## within the 6x6. It is not an AI bug; a player who drops a house on their own
## villagers entombs them exactly the same way.
##
## Evicted rather than refused, because refusing would mean a player cannot build
## where their own villagers happen to be standing, which is most of their base.
## Only for footprints that BLOCK movement: a field is walked over (4.14), and
## shoving its farmers off the crop would be a bug in its own right.
##
## Ids are walked in sorted order and `find_free_adjacent` scans a fixed ring, so
## two hosts evict the same units to the same tiles -- this runs inside a command's
## apply() and a divergence here is a desync.
func _evict_from_footprint(rect: Rect2i) -> void:
	var ids := entities.keys()
	ids.sort()
	for id in ids:
		var e = entities[id]
		if not (e is SimUnit) or not e.alive:
			continue
		var u: SimUnit = e
		if not rect.has_point(u.tile()):
			continue
		var to := _step_aside_tile(rect, u.tile(), u.domain)
		if to.x < 0:
			continue          # walled in on every side; nothing better to offer
		u.pos = to * SUBTILE + Vector2i(SUBTILE / 2, SUBTILE / 2)
		spatial.move(u.id, to)
		# Its route started from where it used to stand, so it must be thrown away
		# rather than walked from somewhere else -- see `SimUnit.replan()`. The TASK
		# survives, so a villager stepped aside by somebody's new house carries on
		# with the job it was already doing.
		if paths != null and u.is_travel_task():
			u.replan()
			paths.request(u.id, u.task_target_tile)


## Where a unit standing inside `rect` should step to: the nearest tile to WHERE IT
## ALREADY IS that is outside the footprint and passable.
##
## Nearest to the UNIT, emphatically not `SimMap.find_free_adjacent` -- which answers
## a different question (somewhere to put a freshly trained unit) by sweeping the
## rect's top edge first. Used here it threw a villager standing at a house's
## bottom-right corner clear across to the top-left one, and on a forest map that
## tile was passable but walled in by trees: the villager could not path anywhere
## ever again, and 196 empty route requests in 1,000 ticks were all the same one.
## A tile beside where the unit was already standing is connected to the rest of the
## map for the simplest possible reason -- it just walked there.
##
## Rings are swept in a fixed order and the whole ring is scanned before widening,
## so two hosts choose the same tile; this runs inside a command's apply().
func _step_aside_tile(rect: Rect2i, from: Vector2i, domain: int) -> Vector2i:
	# Generous enough to clear any footprint in the game from its middle, bounded so
	# a unit sealed in by terrain gives up rather than scanning the map.
	for ring in range(1, 16):
		var best := Vector2i(-1, -1)
		var best_d := 1 << 30
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue          # only the new ring; inner ones were scanned
				var t := from + Vector2i(dx, dy)
				if rect.has_point(t) or not map.is_passable(t, domain):
					continue
				# Squared euclidean picks the tile that LOOKS nearest within the
				# ring, with the sweep order breaking exact ties the same way twice.
				var d := (t - from).length_squared()
				if d < best_d:
					best_d = d
					best = t
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


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
	if d == null:
		return true

	# A DOCK MUST TOUCH WATER (project owner, 2026-08-23: "dock needs to touch water").
	# It goes here rather than in the command for this function's own stated reason --
	# the ghost colours the drag by this, so a rule the command enforced alone would
	# show green and then be refused.
	#
	# It is not a cosmetic rule. A fishing ship is domain water and has to reach a tile
	# adjacent to its drop-off, so a dock in the middle of a meadow trains ships that
	# can never deliver and has no way to say so.
	if d.requires_shore \
			and not _touches_water(SimMap.footprint_rect(origin, d.footprint)):
		return false

	if d.requires_adjacent.is_empty():
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


## Whether any tile orthogonally touching `rect` is water a ship could float on.
##
## SHALLOW ONLY, matching where fish are placed and where a ship can actually be: deep
## water is passable to the water domain too, but a dock whose only water is a deep
## channel is a dock on a cliff edge as far as fishing is concerned.
##
## Orthogonal, not diagonal: a corner touch is not a berth. A ship parked diagonally off
## the dock's corner is not adjacent to its footprint by `CombatSystem.tile_gap`'s
## reckoning either, so allowing it here would let a dock pass placement and still fail
## to take a delivery.
func _touches_water(rect: Rect2i) -> bool:
	for x in range(rect.position.x - 1, rect.end.x + 1):
		for y in range(rect.position.y - 1, rect.end.y + 1):
			var t := Vector2i(x, y)
			if rect.has_point(t):
				continue
			# Skip the four diagonal corners of the grown ring.
			var dx := 0 if t.x >= rect.position.x and t.x < rect.end.x else 1
			var dy := 0 if t.y >= rect.position.y and t.y < rect.end.y else 1
			if dx + dy > 1:
				continue
			if map.in_bounds(t) and map.terrain_at(t) == SimMap.Terrain.WATER_SHALLOW:
				return true
	return false


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
	# THE NODE'S OWN DOMAIN, not the building one. This called `can_place_building` for
	# months, which is land-only by design and correct for every node there was -- and
	# refused `res.fish` every tile of the sea it is supposed to live in (6.5).
	var domain := SimMap.from_domain_name(d.domain) if d != null else SimMap.Domain.LAND
	if not map.can_place(rect, domain):
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


## Loose a projectile from `from` toward `to`, both in sub-tile units (PLAN.md 4.13).
##
## `visual_id` is BOTH the def id and the visual: a projectile has no entry in any
## data file because there is nothing to say about one beyond which sprite it is, and
## `GameDataRegistry.visual_for` resolves an id that is already a declared visual to
## itself. The shooter's `UnitDef.attack_projectile` is where the choice actually
## lives, so arrow/bolt/stone is a data decision like everything else.
##
## NOT in the spatial hash and NOT in the occupancy grid. Nothing ever asks what is
## near an arrow, and putting one in the grid would mean `despawn()` marking its tile
## dirty for the pathfinder every time a shot landed -- a full-rate path invalidation
## driven by archery. `_footprint_of` returns an empty rect for it, which is what keeps
## that from happening.
func spawn_projectile(visual_id: StringName, owner: int, from: Vector2i,
		to: Vector2i) -> SimProjectile:
	var p := SimProjectile.new()
	p.id = _next_id
	_next_id += 1
	p.def_id = visual_id
	p.owner_id = owner
	p.pos = from
	p.origin_pos = from
	p.target_pos = to
	p.total_ticks = SimProjectile.flight_ticks(from, to)
	# The RAW sub-tile delta, not one divided down to tiles: `facing_toward` only wants
	# a direction, and dividing first collapses every shot shorter than a tile to
	# (0, 0), which is due east whichever way the archer was actually aiming.
	p.facing = SimUnit.facing_toward(to - from)
	entities[p.id] = p
	return p


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
## changes nothing the pathfinder cares about. Nor do projectiles, which are in
## neither: an empty rect here is what stops every landing arrow marking a tile dirty
## and invalidating paths at the rate the archers are firing.
func _footprint_of(e: SimEntity) -> Rect2i:
	if e is SimUnit or e is SimProjectile:
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


## Whether `owner` has a FINISHED building of `def_id` standing somewhere.
##
## The gate the two market commands need: trading is a thing a market lets you do,
## the same way training is a thing a barracks lets you do, and without this the
## market page would be a free ability every player has from tick 1. A foundation
## does not count -- `is_complete()` is the same test `TrainCommand` applies to the
## building it is queueing at.
##
## A LINEAR SCAN, and deliberately not an index. This runs once per market command,
## which is once per deliberate button press by a person; the per-tick systems are
## where a scan over every entity is worth caring about (PLAN.md 14's "per-player
## work reads as cheap and is O(players x world)"), and adding a per-player,
## per-def index to keep in sync would be a new thing that can silently go stale.
func has_completed_building(owner: int, def_id: StringName) -> bool:
	for e in entities.values():
		if e.owner_id != owner or not e.alive or not (e is SimBuilding):
			continue
		if e.def_id == def_id and (e as SimBuilding).is_complete():
			return true
	return false


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


## The wall tier a segment def belongs to, or null if it is not a wall segment.
## `WallMerge` asks it of every wall piece that finishes; the reverse index behind it
## is the registry's, since it is a fact about buildings.json.
func wall_tier(def_id: StringName) -> BuildingDef:
	return GameDataRegistry.wall_tier(def_id) if GameDataRegistry != null else null


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
					e.gather_cooldown, e.attack_cooldown,
					# WHICH BUILDING IT IS INSIDE (4.8). This is the one field that takes
					# a unit off the map without despawning it, so two hosts disagreeing
					# about it disagree about the population count, about what the
					# spatial index can find, and about how hard a tower shoots -- and
					# `pos` cannot report any of that, because a garrisoned unit's `pos`
					# is deliberately stale and never moves.
					e.garrisoned_in])
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
			# `gate_locked` is the only building field a player can flip at will
			# (5.8), and it moves the MOVEMENT GRID -- two hosts disagreeing about
			# whether a doorway is shut would route the same army two different ways
			# and diverge in position a tick later, which `pos` reports long after the
			# cause. `facing` rides along for the reason `SimUnit.facing` does: it is
			# placement state that nothing recomputes, so a wrong one stays wrong.
			# WHO IS INSIDE, as a list and not a count (4.8). A count would catch two
			# hosts that admitted a different NUMBER of units and miss two that admitted
			# a different SET -- and the set is what prices the tower's shot
			# (`attack_bonus` is half of each occupant's damage), so two clients holding
			# the same five slots filled by different units would hash identically while
			# their towers dealt different damage. Ids and def ids both, in insertion
			# order, because the eject-by-index command makes the order load-bearing too.
			var g: Array = []
			for entry in e.garrison:
				g.append([entry.get("id", 0), entry.get("def_id", &"")])
			# The building's own firing cooldown (4.9), for the reason SimUnit's is
			# hashed: a tick's difference in rate of fire decides who dies first.
			# The rally point (4.8's follow-up): a player-set tile that decides where
			# every unit leaving this building walks to, so two hosts disagreeing about
			# it send the same trained army to two different places. `pos` reports that
			# several seconds later, as a divergence with no visible cause.
			parts.append([e.phase, e.build_progress, q, e.rubble_ticks_left,
					e.gather_amount, e.facing, e.gate_locked, g, e.attack_cooldown,
					e.waypoint.x, e.waypoint.y])
		elif e is SimResourceNode:
			# GatherSystem (6.4) depletes this at runtime; without it two clients
			# whose villagers gathered at different rates would hash identically
			# right up until the node ran out on one of them and not the other.
			parts.append([e.amount])
		elif e is SimProjectile:
			# A projectile carries no damage (4.13), so nothing it does can change the
			# outcome of the match -- and it is hashed anyway, because it is still SIM
			# state and it still DESPAWNS. Two hosts a tick apart on a flight would
			# disagree about `removed[]` on the tick it landed, which is a real wire
			# difference over a purely cosmetic entity. Cheaper to include than to
			# explain away, and `pos` above already rides on every entity.
			parts.append([e.elapsed_ticks, e.total_ticks, e.facing])

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
