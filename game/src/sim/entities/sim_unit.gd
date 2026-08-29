## A controllable, moving entity. Task kinds beyond MOVE (GATHER, BUILD, ...)
## are wired up alongside the systems that give them meaning -- ResourceSystem
## (phase 2.3+), ProductionSystem, etc. -- rather than stubbed here ahead of time.
class_name SimUnit
extends SimEntity

enum Task { IDLE, MOVE, GATHER, RETURN, BUILD, ATTACK, GARRISON, STAND_GROUND, FLEE }

var task: Task = Task.IDLE
var task_target_id: int = 0
var task_target_tile: Vector2i = Vector2i.ZERO
var path: PackedVector2Array = PackedVector2Array()
var path_index: int = 0
var speed: int = 0                   # sub-units per tick
var facing: int = 0                  # 0-7
## Which surfaces this unit can cross -- a SimMap.Domain. Land for everything in
## MVP (PLAN.md 2.2); carried per-unit rather than looked up from the def on every
## passability query, which pathfinding does thousands of times per path.
var domain: int = SimMap.Domain.LAND
## What this unit costs against its owner's population cap (PLAN.md 4.11).
## Copied off the def at spawn, exactly as `SimBuilding.provides_pop` is, so
## PopulationSystem's per-tick recount is a scan over entities and never a
## registry lookup -- and so a unit's cost cannot change under it mid-match.
var pop_cost: int = 1
var carry_kind: StringName = &""
var carry_amount: int = 0
var gather_cooldown: int = 0
## The resource node a GATHER/RETURN cycle is working. `task_target_id` points at
## whichever entity is currently being WALKED TO -- the node while gathering, the
## drop-off building while returning -- so this is the one field that survives the
## switch between them (6.4).
var gather_node_id: int = 0
## Where that node STOOD. Kept because a spent one is despawned, and by the time
## a villager walks its last load home there is no entity left to ask where to
## look for the next tree (GatherSystem's re-scan, project owner 2026-08-16).
## `task_target_tile` cannot serve: during RETURN it is the drop-off building.
var gather_node_tile: Vector2i = Vector2i.ZERO
## WHERE THIS UNIT LAST BANKED A LOAD, or `(-1, -1)` if it never has (project owner,
## 2026-08-28: *"when the ai towncentre [is destroyed] have the villagers run back to
## its location"*).
##
## It is the town centre's tile for any villager who has been delivering to one, and it
## is the ANSWER TO A QUESTION THE WORLD CAN NO LONGER BE ASKED: once the drop-off is
## destroyed there is nothing left to look up, and its rubble clears itself away sixty
## seconds later (`SimBuilding.RUBBLE_TOTAL_TICKS`), so the ruins are not a durable
## anchor either. A tile remembered on the unit outlives both.
##
## Written on a successful deposit and never cleared. A villager who has changed drop-off
## three times remembers the third, which is the one worth walking back to.
##
## `(-1, -1)` and not `(0, 0)`: tile (0, 0) is a real tile on every map, the same reason
## `roam_home` uses that sentinel.
var deposit_tile: Vector2i = Vector2i(-1, -1)
var attack_cooldown: int = 0
var anim: StringName = &"idle"

## SIEGE ONLY (PLAN.md 4.13, 9.2.1) -- `SiegeSystem` writes all three and nothing else
## does. Here rather than on a subclass for the reason the wildlife block above gives:
## a trebuchet and a knight differ in DATA (`UnitDef.packs`), and splitting the class
## would make every system that walks units care which kind it had.
##
## Whether this unit HAS two states, copied off the def at spawn exactly as `pop_cost`
## and `domain` are -- so `can_move()` and `can_fire()` are answerable without a
## registry lookup, which `MovementSystem` and `AnimationSystem` would otherwise do for
## every unit on the map every tick.
var packs: bool = false

## WHICH OF THE TWO IT IS RIGHT NOW: packed is the travelling wagon, unpacked is the
## engine set up to shoot. It flips the INSTANT a transition starts rather than when
## the timer runs out, and that is deliberate -- the art changes immediately so the
## player can see what the thing is becoming, while `pack_ticks_left` is what says it
## cannot do the new job yet. Neither field means two things.
##
## A siege engine is TRAINED PACKED, because the first thing it must do is leave the
## workshop and walk to a rally point.
var packed: bool = false

## Ticks until the state it is already showing becomes usable, or 0 for settled. While
## this is non-zero the unit can neither walk nor shoot: it is the cost of changing its
## mind, and it is the only thing stopping a trebuchet from being a mobile turret.
##
## There is no separate "which way am I transitioning" field, because there is no such
## question -- `packed` already says which state is being entered.
var pack_ticks_left: int = 0

## WILDLIFE ONLY (PLAN.md 6.1b), all three driven by `WildlifeSystem` and read by
## nothing else. They are here rather than on a subclass because a wolf and a villager
## differ in DATA -- `UnitDef.is_wildlife` -- and splitting the class would make every
## system that iterates units care which kind it had.
##
## Where this animal currently considers home, and what it wanders around. `(-1, -1)`
## means "not settled yet" and is claimed on the first think tick; tile (0, 0) is a
## real tile on every map, so it cannot be the sentinel.
var roam_home: Vector2i = Vector2i(-1, -1)
## Ticks until it will consider wandering again. Counts down whatever else happens, so
## an animal that spent a while being chased does not then stand still for the same
## while afterwards.
var roam_cooldown: int = 0
## Ticks of running left. Non-zero locks out roaming and re-targeting, which is what
## stops a frightened animal from stopping to graze mid-bolt.
var flee_ticks: int = 0
## Hp at the last think tick, so a drop can be noticed without plumbing an attacker
## through `take_damage` -- see `WildlifeSystem._check_flee`.
var last_hp: int = -1

## Which player may give this animal orders, or 0 for nobody (6.5's livestock).
##
## SEPARATE FROM `owner_id` ON PURPOSE, and it is the whole design. A herded sheep is
## still gaia's: `GatherSystem` never learns about units, `WinConditionSystem` cannot be
## kept alive by a flock, and the herder can still attack the animal, which is how it
## eventually becomes food. `MoveCommand` is the only thing that reads this.
##
## STICKY. Once claimed it stays claimed until somebody else walks closer -- walking
## away does not release it, which is what makes a flock something you can leave at home
## and come back to.
var herded_by: int = 0

## The building this unit is INSIDE, or 0 for on the map (PLAN.md 4.8).
##
## Shaped after `herded_by` above -- one int, written by one system, meaning nothing
## when zero -- but it does far more, because it is the first field in the project
## that takes an entity OFF the map without despawning it. What it means, exactly:
##
##   - the unit is still in `SimWorld.entities`, so it still counts against the
##     population cap. A garrisoned army is an army you have; hiding fifteen units
##     in a castle must not buy fifteen free villagers.
##   - it is NOT in `SpatialHash`, so nothing finds it: `CombatSystem._reacquire`
##     cannot target it, `WildlifeSystem` cannot see it, and `pick()` cannot tap it.
##     That is the whole "removed from the world map" of IDEA.md 4.8, and it is one
##     line -- `spatial.remove()` without `despawn()`.
##   - it is NOT in the snapshot at all (`SnapshotSystem.build` skips it), so the
##     client forgets it and releases its sprite. That is also what deselects it,
##     for free, via `GameView`'s `retain_only` pass.
##
## `pos` is left where it last stood rather than moved to the building, and nothing
## reads it while this is set. On the way OUT the unit is placed by
## `SimWorld._step_aside_tile` from the building's own footprint, so a stale `pos`
## can never leak into where it reappears.
var garrisoned_in: int = 0

## Ticks left as a corpse before DeathSystem despawns it (PLAN.md 4.7): 60 s of
## corpse plus a 10 s fade, at SimClock's 10 ticks/sec. -1 means "not dead" --
## DeathSystem reads that sentinel to tell a fresh death from one it has already
## set up, since `alive` alone cannot: it goes false exactly once, but the tick
## it does is the one tick DeathSystem must react to rather than just count down.
const CORPSE_TOTAL_TICKS := 700
const CORPSE_FADE_TICKS := 100
var corpse_ticks_left: int = -1


## True between asking PathService for a route and being given one (PLAN.md 4.2 --
## searches are budgeted, so the answer can be a few ticks late). A unit waits
## rather than setting off in the target's general direction: guessing would walk
## it into the wall the path was going to route around.
var path_pending: bool = false


## Units move, so the fog never sends one it cannot currently see. See
## `SimEntity.is_mobile`.
func is_mobile() -> bool:
	return true


## A CARRIER MUST NOT ITSELF BE CARGO, which is this class's own addition to
## `SimEntity.has_garrison_room()` (PLAN.md 4.8, 2.4d). Only the transport ship has a
## cap at all, so in practice this asks whether a boat is inside something -- which it
## cannot be today, since nothing carries ships. It is here because the alternative is a
## rule nobody wrote: a carrier whose own `pos` is stale and which is out of the spatial
## index cannot be walked up to, so units ordered aboard would walk to nowhere forever.
func has_garrison_room() -> bool:
	return garrisoned_in == 0 and super()


## Whether this unit may take a step this tick (PLAN.md 4.13).
##
## TRUE FOR EVERYTHING THAT DOES NOT PACK, which is every unit in the game but three,
## so this is not a gate the rest of the roster pays for. `MovementSystem` is not asked
## to check it: `SiegeSystem` drives `speed` off exactly this, so a deployed engine has
## speed 0 and the walker needs no special case at all.
func can_move() -> bool:
	return not packs or (packed and pack_ticks_left == 0)


## Whether this unit may land a blow this tick. The mirror of `can_move()`, and the two
## are never both true for a siege engine -- which is the whole feature.
func can_fire() -> bool:
	return not packs or (not packed and pack_ticks_left == 0)


## Begin folding up (`want_packed`) or setting up. Idempotent: asking for the state it
## is already in and settled in does nothing, so a system may call this every tick
## without restarting the timer under itself.
func begin_packing(want_packed: bool, ticks: int) -> void:
	if packed == want_packed:
		return
	packed = want_packed
	pack_ticks_left = maxi(0, ticks)


func set_task_move(t: Vector2i) -> void:
	task = Task.MOVE
	task_target_tile = t
	path = PackedVector2Array()
	path_index = 0
	path_pending = true


## Walk toward a resource node and start working it on arrival (6.4). `tile` is
## the node's own tile -- it is occupied ground, so PathService substitutes the
## nearest tile that can actually be stood on, same as walking up to a tree (4.1).
func set_task_gather(node_id: int, tile: Vector2i) -> void:
	task = Task.GATHER
	task_target_id = node_id
	gather_node_id = node_id
	gather_node_tile = tile
	task_target_tile = tile
	path = PackedVector2Array()
	path_index = 0
	path_pending = true


## Walk a load back to a drop-off building. Kept separate from set_task_gather
## because `task_target_id` must point at the BUILDING while this is active --
## `gather_node_id` is what remembers the node to go back to once the load lands.
func set_task_return(building_id: int, tile: Vector2i) -> void:
	task = Task.RETURN
	task_target_id = building_id
	task_target_tile = tile
	path = PackedVector2Array()
	path_index = 0
	path_pending = true


## Walk toward a building under construction and add progress to it on arrival.
func set_task_build(building_id: int, tile: Vector2i) -> void:
	task = Task.BUILD
	task_target_id = building_id
	task_target_tile = tile
	path = PackedVector2Array()
	path_index = 0
	path_pending = true


## Walk toward an enemy and hit it on arrival (PLAN.md 4.13). `tile` is where the
## target is NOW -- a moving one is re-planned toward by CombatSystem once this
## route runs out, rather than re-pathed every tick, which is what keeps a chase
## inside PathService's per-tick budget (4.2).
func set_task_attack(target_id: int, tile: Vector2i) -> void:
	task = Task.ATTACK
	task_target_id = target_id
	task_target_tile = tile
	path = PackedVector2Array()
	path_index = 0
	path_pending = true


## Walk toward a friendly building and step inside it on arrival (PLAN.md 4.8).
##
## `tile` is the building's own tile, which is occupied ground -- PathService
## substitutes the nearest tile that can be stood on, exactly as walking up to a
## tree or a foundation does, and `GarrisonSystem` then accepts anything adjacent to
## the footprint. So a unit sent to a [7, 7] castle stops at its wall and goes in
## from wherever it happened to reach, rather than needing a door.
func set_task_garrison(building_id: int, tile: Vector2i) -> void:
	task = Task.GARRISON
	task_target_id = building_id
	task_target_tile = tile
	path = PackedVector2Array()
	path_index = 0
	path_pending = true


## Drop the route but KEEP the task -- what an attacker does the moment its
## target comes into reach, so it stands and fights instead of walking the rest
## of a path it no longer needs. Distinct from stop(), which retires the order
## entirely; a unit that halted is still attacking.
func halt() -> void:
	task_target_tile = tile()
	path = PackedVector2Array()
	path_index = 0
	path_pending = false


## MOVE, GATHER, RETURN, BUILD, ATTACK and GARRISON all walk somewhere before doing
## anything else -- this is PathService's and MovementSystem's test for "does this
## unit want a route", so neither has to enumerate every task that happens to
## travel.
##
## GARRISON JOINED IT ON 2026-08-27 AND HAD TO. `Task.GARRISON` had been declared
## and unassigned since 4.3, and this function's omission of it was load-bearing
## while that was true; the moment something set the task, `PathService.process()`
## (which drops any request whose unit is not on a travel task) would have thrown
## the route away and left the unit standing where it was ordered from, in GARRISON,
## forever. That is the same failure the header of `SimUnit.replan()` describes.
func is_travel_task() -> bool:
	return task == Task.MOVE or task == Task.GATHER or task == Task.RETURN \
			or task == Task.BUILD or task == Task.ATTACK or task == Task.GARRISON


## The 8-way facing a delta points along. Shared by MovementSystem (which faces a
## unit the way it walks) and CombatSystem (which faces it at what it is hitting)
## -- one function because a unit that walked east and then turned to strike must
## not disagree with itself about which way east is.
static func facing_toward(delta: Vector2i) -> int:
	var angle := atan2(-float(delta.y), float(delta.x))
	var octant := int(round(angle / (PI / 4.0))) % 8
	return octant + 8 if octant < 0 else octant


## Take a solved route. An EMPTY path means PathService found nowhere to go, which
## retires the task -- the alternative, leaving the unit in MOVE forever, is a unit
## that looks ordered but never arrives and never accepts that it failed.
func set_path(p: PackedVector2Array) -> void:
	path = p
	path_index = 0
	path_pending = false
	if p.is_empty():
		stop()
	else:
		# The real destination is where the path ACTUALLY ends, which is not the
		# ordered tile when that tile was blocked and a substitute was chosen
		# (PLAN.md 4.1). Without this the unit arrives and TaskSystem still thinks
		# it is short of its target.
		task_target_tile = Vector2i(p[p.size() - 1])


## Throw the route away and ask for a new one, KEEPING the task.
##
## For a unit that has been moved without asking it -- today only
## `SimWorld._evict_from_footprint`, stepping it out from under a new building.
## Its old route was planned from where it used to stand, and walking that route
## from somewhere else lands it in the wrong place, where `GatherSystem` and
## `BuildSystem` retire it for not being adjacent to what it was sent to. That
## cost the AI a whole script step before this existed.
##
## Clearing `path` and raising `path_pending` is exactly what the `set_task_*`
## calls do, so the unit simply stands still for the tick or two the new search
## takes and then carries on with the job it already had.
## Already standing where the route would have ended, so there is nothing to walk.
##
## The other half of `set_path()`: an empty route means "nowhere to go" there and
## retires the task, which is right for an unreachable order and WRONG for a unit
## that has simply arrived already. Keeping the task and dropping `path_pending` is
## what lets GatherSystem, BuildSystem and CombatSystem -- all of which wait for the
## walking to finish before they act -- get on with the job on the next tick.
func arrive() -> void:
	path = PackedVector2Array()
	path_index = 0
	path_pending = false


func replan() -> void:
	path = PackedVector2Array()
	path_index = 0
	path_pending = true


func stop() -> void:
	task = Task.IDLE
	task_target_tile = tile()
	task_target_id = 0
	gather_node_id = 0
	gather_node_tile = Vector2i.ZERO
	path = PackedVector2Array()
	path_index = 0
	path_pending = false


func is_idle() -> bool:
	return task == Task.IDLE


func has_waypoint() -> bool:
	return path_index < path.size()


## Tile the unit is currently walking toward.
func waypoint() -> Vector2i:
	return Vector2i(path[path_index]) if has_waypoint() else tile()


## Sub-tile centre of the current waypoint. Centres, because that is where the sim
## stands an entity on a tile (2.3) and where the view draws it.
func waypoint_subpos() -> Vector2i:
	return centre_of_tile(waypoint())


## The sub-tile position MOVE is walking toward overall -- the tile's centre, so
## MovementSystem's arrival check lands exactly on the tile TaskSystem expects.
func move_target_subpos() -> Vector2i:
	return centre_of_tile(task_target_tile)


static func centre_of_tile(t: Vector2i) -> Vector2i:
	const HALF := SimWorld.SUBTILE / 2
	return t * SimWorld.SUBTILE + Vector2i(HALF, HALF)


## `task` joins the base snapshot so the view can count idle villagers (7.1)
## without reaching into SimWorld -- the same reason every other view-facing
## fact travels in the snapshot rather than being asked of the sim directly.
func to_snapshot() -> Dictionary:
	var d := super()
	d["task"] = int(task)
	d["anim"] = anim
	d["facing"] = facing
	d["corpse_ticks_left"] = corpse_ticks_left
	# ON THE WIRE, unlike every other wildlife field, because the CLIENT has to know:
	# `GameView.movable_selection` uses it to decide whether tapping the ground with a
	# sheep selected is an order or nothing at all. Without it the client would offer
	# moves the sim silently refused, which is the worst of both -- the player taps and
	# nothing happens and nothing says why. Only sent when non-zero.
	if herded_by != 0:
		d["herded_by"] = herded_by
	# WHICH SIEGE ART TO DRAW (4.13). Sent only when true, exactly as `herded_by` is
	# sent only when non-zero, and for the same reason it is safe to: the client reads
	# `entry.get("packed", false)` and absence is a correct reading of the default. The
	# alternative -- one more int on every unit on the wire, always 0 -- is what 12.1f
	# spent the whole snapshot audit removing.
	#
	# `pack_ticks_left` deliberately does NOT ride along. Nothing on the client needs it:
	# the art has already changed, and a progress bar over a trebuchet is a readout of a
	# thing the player can see happening.
	if packed:
		d["packed"] = true
	# WHO IS ABOARD (2.4d), in exactly the shape `SimBuilding` sends -- a count for the
	# badge and def ids for the portraits, never entity ids, because a garrisoned unit is
	# not in the snapshot for the client to look one up and `UngarrisonCommand` therefore
	# names a SLOT. `GarrisonUI` reads both without learning that a boat exists.
	#
	# ONLY FOR A CARRIER, which is the transport and nothing else. `herded_by` and
	# `packed` above set the precedent: 12.1f's rule against splitting the wire shape is
	# about fields that vary per INSTANCE, and this varies per def -- every transport
	# sends it and nothing else ever does.
	if garrison_cap > 0:
		d["garrison_count"] = garrison.size()
		var inside: Array[String] = []
		for entry in garrison:
			inside.append(String(entry["def_id"]))
		d["garrison"] = inside
	return d
