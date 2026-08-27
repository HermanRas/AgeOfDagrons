## A building (PLAN.md 6.2). Phase 2.3 -- enough to exist, be placed into the grid
## and be drawn; the behaviour that acts on it lands in phase 5.
##
## BUILDINGS HAD NO FACING UNTIL WALLS (PLAN.md 5.8, 2026-08-21). Placement snaps to
## the grid without rotation (5.1), which is why all nineteen ordinary buildings are
## baked at `directions = 1` and stay at facing 0 forever. A wall is the exception
## that forced the field: it has to run along whichever axis it was dragged on, so
## the wall bakes carry `directions = 8` and the sim has to say which one.
##
## `pos` is inherited from SimEntity and is in sub-tile units like everything
## else, but for a building it means **the centre of its footprint** rather than
## the centre of a tile. That keeps the view layer uniform -- it draws every
## entity at `Iso.sub_to_world(pos)` without asking what kind it is -- while
## `origin_tile()` recovers the top-left tile the footprint was placed at, which is
## what the grid cares about.
##
## Both of the things this header used to list as deliberately absent are here now:
## the production queue landed with 5.4 and the GARRISON with 4.8 (2026-08-27). What
## garrison brought with it is the pair of fields nobody expected on a building --
## `attack_damage` and `attack_cooldown` -- because a building that holds archers has
## to have something for them to add their damage TO (4.9). See `attack_bonus()`.
class_name SimBuilding
extends SimEntity

enum Phase { FOUNDATION, UNDER_CONSTRUCTION, COMPLETE, DESTROYED }

var phase: Phase = Phase.FOUNDATION
var footprint: Vector2i = Vector2i.ONE

## Which way this building is turned, in the SIM's facing convention (the same
## octant numbering `SimUnit.facing` uses -- 0 along +x, counting anticlockwise with
## the y axis flipped). 0 for every building but a wall; see this file's header.
##
## In the sim convention rather than the sprite one on purpose, and `SimUnit`'s own
## `facing` records why: `facing` is in `state_hash()`, so its meaning is frozen into
## every recorded replay, and `Iso.sim_facing_to_sprite` is the single place that
## knows the two tables run opposite ways.
var facing: int = 0

## GATES (PLAN.md 5.8). `is_gate` mirrors the def so the entity can answer for
## itself -- `blocks_now()` is asked once per occupancy change and going back to the
## registry for it would put a data lookup inside the movement grid.
##
## `gate_locked` STARTS FALSE, i.e. a new gate is OPEN, which was the project owner's
## call (2026-08-21). The alternative was closed-by-default: a wall that defends the
## moment it is finished, at the price of stranding your own villagers behind it
## before you have noticed there is a gate to open. Open-by-default never strands
## anybody, and the cost is that a wall does nothing until somebody locks it.
##
## OPEN IS OPEN TO EVERYONE, including the army outside. Per-player passability would
## need a pathfinding grid per player -- `PathService` has exactly one
## `AStarGrid2D` -- and that is the real fix, deliberately not attempted here.
var is_gate: bool = false
var gate_locked: bool = false

var build_progress: int = 0
var build_total: int = 0

## Ticks left as rubble before DeathSystem clears it away (project owner,
## 2026-08-16), at SimClock's 10 ticks/sec: a minute of wreckage, the last 10 s
## of it fading. -1 means "not destroyed" -- the same sentinel SimUnit's corpse
## uses, and for the same reason: `alive` goes false exactly once, but the tick
## it does is the one tick DeathSystem must react to rather than just count down.
##
## Rubble used to stay forever. That was PLAN.md 5.5 as written, and it was wrong
## in play: a razed settlement left permanent wreckage over ground that was
## already buildable again, so the map accumulated debris nothing could remove.
## A new building placed over it clears it early -- SimWorld.spawn_building() --
## and this timer is what gets rid of the rest.
const RUBBLE_TOTAL_TICKS := 600
const RUBBLE_FADE_TICKS := 100
var rubble_ticks_left: int = -1

## A FIELD IS A RESOURCE NODE WEARING A FOOTPRINT. It is placed, costed and
## built like a building and then harvested like a berry bush, so it needs the
## three things GatherSystem asks of anything gatherable: what kind, how much is
## left, and how many can work it. Named to match `SimResourceNode`'s own fields
## on purpose -- GatherSystem branches on the type once, in one place, and
## everything downstream reads the same words for the same idea.
##
## Zero for everything that is not a field, which is every other building.
var gather_kind: StringName = &""
var gather_amount: int = 0
var gather_slots: int = 0


## Take up to `requested` units, returning what was actually there. Same
## contract as SimResourceNode.gather(): credit the RETURN VALUE, never the
## request, or a nearly-spent field feeds a town forever.
##
## An INFINITE crop hands back the whole request and stays where it is, which is
## what a field does as of 2026-08-17. The finite path is still live and still
## tested: nothing else in the roster uses it today, and it is what a berry patch
## or a one-harvest crop would want tomorrow.
func gather(requested: int) -> int:
	if gather_amount == BuildingDef.INFINITE_CROP:
		return maxi(0, requested)
	var taken := clampi(requested, 0, gather_amount)
	gather_amount -= taken
	return taken


## True once there is nothing left to harvest -- which an infinite crop never is.
## Only ever true for a field: a building that was never gatherable has
## `gather_kind` empty and is not something GatherSystem looks at.
func is_spent() -> bool:
	if gather_kind == &"" or gather_amount == BuildingDef.INFINITE_CROP:
		return false
	return gather_amount <= 0

var provides_pop: int = 0
var garrison_cap: int = 0

## Who is inside, in the order they entered (PLAN.md 4.8). Each entry is
## `{id, def_id}`.
##
## SHAPED LIKE `queue` BELOW, and for the identical reason. Ids alone would have been
## the obvious choice -- and `to_snapshot()` cannot resolve one, because it is handed
## no `SimWorld` and a garrisoned unit is not in the snapshot for the client to look
## up either. The queue hit this exact wall in 5.4 (its own note records the panel
## drawing the word "Queued" twelve times for want of def ids) and answered it by
## carrying the def id in the entry. A unit's `def_id` never changes, so the copy
## cannot drift from the entity it names.
##
## Never a reference to the SimUnit itself, so nothing here can outlive
## `SimWorld.entities` -- the same reason `task_target_id` is an int.
##
## INSERTION ORDER, and it is in `state_hash()` as a list rather than a count, so
## two hosts that admitted the same units in a different order are caught here
## rather than several seconds later when a player ejects "the first one" and gets
## different units on the two machines.
var garrison: Array[Dictionary] = []

## What this building shoots with, copied off its def at spawn exactly as
## `provides_pop` and `garrison_cap` are -- so the building-attack loop is a scan
## over entities and never a registry lookup per shot. 0 damage for 28 of the 31
## defs, which is what keeps a house out of that loop entirely.
var attack_damage: int = 0
var attack_type: StringName = &"melee"
var attack_range: int = 0
var attack_cooldown_ticks: int = 0
var attack_projectile: StringName = &""

## Ticks until this building may fire again. The building-side twin of
## `SimUnit.attack_cooldown`, and hashed for the same reason: two hosts a single
## tick out of step on a castle's rate of fire would kill the same attacker on
## different ticks and then disagree about who died first.
var attack_cooldown: int = 0

## Training queue (5.4). Each entry is {def_id, progress, total, ready, cost}.
## `cost` is snapshotted at enqueue time rather than re-read from UnitDef later,
## so a cancel always refunds exactly what was paid, even though nothing in MVP
## (no techs, no age discounts) would currently make the two disagree. Only the
## FRONT entry ever progresses -- one production line per building, same as
## every RTS this is modelled on -- so entries behind it need no state of their
## own until they reach the front.
var queue: Array[Dictionary] = []


## Room for one more (PLAN.md 4.8). False for everything with `garrison_cap` 0,
## which is 28 of the 31 buildings, so this single test covers "walls hold nobody"
## and "a house is not a shelter" without either being spelled out anywhere.
##
## PHASE IS PART OF IT: a foundation is a hole in the ground. Without the check a
## player could garrison a tower they had not paid to finish, and the building would
## then be shooting at `attack_damage` before it existed.
func has_garrison_room() -> bool:
	return is_complete() and alive and garrison.size() < garrison_cap


## Extra damage per shot from the archers inside (PLAN.md 4.9, project owner
## 2026-08-27): **half of each garrisoned archer's own damage, floored**.
##
## "Archer" IS `attack_range > 0` AND NOT A LIST OF IDS. The owner named the two ends
## of it -- archers add, pikemen and swordsmen do not -- and every melee unit in the
## roster declares `range: 0`, so the data already separates them and nobody has to
## maintain a list that a new unit could be left off. Archer 4 -> +2, crossbowman
## 5 -> +2, cavalry archer 6 -> +3, all twelve melee units -> +0.
##
## INTEGER DIVISION, deliberately, and this is the market.json rule applied to
## combat: the number is spent inside a state transition whose result has to be
## bit-identical on an ARM phone and an x86 host, so 5 / 2 is 2 and never 2.5.
##
## ONE SHOT, NOT SIXTEEN. This is added to the building's own `attack_damage` once
## per swing, so fifteen archers in a castle are one heavier arrow every two seconds
## rather than fifteen separate attackers -- which is also why a garrisoned archer's
## own `attack_cooldown_ticks` is never read.
##
## Walks `garrison` in stored order and sums, so it needs no sort: addition
## commutes, unlike the target choice in `CombatSystem._reacquire`.
## Read off the entry's own `def_id` rather than the live entity, so it is the same
## answer whether or not the unit is still resolvable -- and one fewer `entities`
## lookup per shot. Through `w.unit_def()` rather than the registry directly, which
## is how every other read of a def inside `sim/` goes.
func attack_bonus(w: SimWorld) -> int:
	var bonus := 0
	for entry in garrison:
		var ud := w.unit_def(entry["def_id"])
		if ud == null or ud.attack_range <= 0:
			continue
		bonus += ud.attack_damage / 2
	return bonus


## Where `unit_id` sits in the garrison, or -1. Used by the eject path, which is
## given a unit and needs the slot, and by the tests.
func garrison_index(unit_id: int) -> int:
	for i in range(garrison.size()):
		if int(garrison[i]["id"]) == unit_id:
			return i
	return -1


## Every id inside, for the callers that want to walk the occupants rather than
## price them. Sorted is not needed and not offered: `garrison` is already in a
## deterministic order and every caller either sums (which commutes) or indexes.
func garrison_ids() -> Array[int]:
	var out: Array[int] = []
	for entry in garrison:
		out.append(int(entry["id"]))
	return out


## The top-left tile of the footprint. Derived from `pos` rather than stored, so
## the two can never disagree.
func origin_tile() -> Vector2i:
	var half := Vector2i(footprint.x * SimWorld.SUBTILE, footprint.y * SimWorld.SUBTILE) / 2
	return (pos - half) / SimWorld.SUBTILE


func footprint_rect() -> Rect2i:
	return SimMap.footprint_rect(origin_tile(), footprint)


## Sub-tile centre of the footprint whose top-left tile is `origin`. Static
## because SimWorld needs it to position a building before one exists.
static func centre_of(origin: Vector2i, p_footprint: Vector2i) -> Vector2i:
	var size := Vector2i(maxi(1, p_footprint.x), maxi(1, p_footprint.y))
	return origin * SimWorld.SUBTILE + Vector2i(size.x * SimWorld.SUBTILE, size.y * SimWorld.SUBTILE) / 2


## Advance construction. Returns true on the tick it completes, so 5.2 can fire
## `building.complete` audio and flip the visual without polling for the change.
##
## `hp` rises WITH build_fraction() rather than sitting at spawn_building()'s
## starting sliver for the whole construction -- found live (a session
## playtest) reporting a house stuck at 55/550 the entire time it was being
## built, only jumping to full at completion. The health bar is the only
## build-progress indicator SelectionPanel currently draws (5.6), so it has
## to actually move for a foundation to read as "under way" rather than
## "damaged and static". Forced to exactly max_hp on completion rather than
## trusting the fraction's rounding, so a finished building is never left one
## hp short of full by an integer-division remainder.
func add_build_progress(amount: int) -> bool:
	if phase == Phase.COMPLETE or phase == Phase.DESTROYED:
		return false
	build_progress = clampi(build_progress + amount, 0, maxi(build_total, 0))
	if phase == Phase.FOUNDATION and build_progress > 0:
		phase = Phase.UNDER_CONSTRUCTION
	if build_total > 0 and build_progress >= build_total:
		phase = Phase.COMPLETE
		hp = max_hp
		return true
	hp = maxi(1, int(float(max_hp) * build_fraction()))
	return false


func is_complete() -> bool:
	return phase == Phase.COMPLETE


## Whether this building's tiles are closed to movement RIGHT NOW.
##
## Two independent reasons a footprint might be walkable, and they are different
## questions: `blocks` is the def's standing answer (false for a field, whose crop is
## claimed ground rather than a wall), and an unlocked gate is a doorway in something
## that otherwise blocks. A gate is the only thing in the game whose answer changes
## during a match, which is why this is a function and the field is not.
##
## AN UNFINISHED GATE IS A HOLE, and that falls out rather than being special-cased:
## `ToggleGateCommand` refuses a gate that is not complete, so a foundation gate is
## still unlocked and still passable. A wall foundation, by contrast, blocks from the
## moment it is placed -- which is the same rule as every other building and is what
## lets a player wall a gap before the wall is built.
func blocks_now(blocks: bool) -> bool:
	if is_gate:
		return blocks and gate_locked
	return blocks


## Construction progress as 0..1, for the build bar. Guards `build_total == 0`,
## which is what a building placed straight into COMPLETE has (2.6's starting
## town centre) -- dividing by it would be a crash on the very first frame.
func build_fraction() -> float:
	if build_total <= 0:
		return 1.0
	return clampf(float(build_progress) / float(build_total), 0.0, 1.0)


func to_snapshot() -> Dictionary:
	var d := super()
	d["phase"] = int(phase)
	# WALLS ONLY IN PRACTICE, sent for every building all the same. The wire cost is
	# one int and one field NAME per shape per snapshot (12.1f's shape tables), and a
	# field present on some buildings and absent on others would split every building
	# into two shapes -- which costs more than the int it was saving.
	d["facing"] = facing
	# Whether the doorway is shut, which is the one piece of building state that
	# changes without any construction or damage happening.
	d["gate_locked"] = gate_locked
	# Named for what it is rather than sharing SimUnit's `corpse_ticks_left`:
	# GameView keys the fade off whichever of the two an entry carries, so the
	# wire format stays honest about which kind of remains is counting down.
	d["rubble_ticks_left"] = rubble_ticks_left
	d["build_fraction"] = build_fraction()
	d["queue_len"] = queue.size()
	d["queue_fraction"] = training_fraction()
	# WHAT is queued, not just how much. The panel crops each queue slot's
	# portrait from the unit's own baked sprite, and without this it had a count
	# and no def ids -- so every entry drew as the word "Queued" rather than as
	# the thing being trained. Def ids only: `progress`, `total` and `cost` are
	# the sim's own bookkeeping, and `queue_fraction` above is the only part of
	# it the view has any use for.
	var queued: Array[String] = []
	for entry in queue:
		queued.append(String(entry["def_id"]))
	d["queue"] = queued
	# WHO IS INSIDE (4.8), and both halves for the same reason `queue_len` sits beside
	# `queue`: the count is what the action button's badge reads and it must be right
	# even for a fogged building whose roster has been stripped, while the def ids are
	# what let the detail grid crop each occupant's own portrait instead of drawing
	# twelve identical cells.
	#
	# SENT ON EVERY BUILDING, empty for the 28 that can hold nobody, exactly as
	# `facing` is sent for every building when only walls use it. A field present on
	# some buildings and absent on others splits every building into two wire shapes
	# (12.1f), which costs more than the two fields it would save.
	d["garrison_count"] = garrison.size()
	var inside: Array[String] = []
	for entry in garrison:
		inside.append(String(entry["def_id"]))
	d["garrison"] = inside
	return d


## Adds a training order to the back of the queue.
func enqueue_training(def_id: StringName, build_time_ticks: int, cost: Dictionary) -> void:
	queue.append({
		"def_id": def_id,
		"progress": 0,
		"total": maxi(1, build_time_ticks),
		"ready": false,
		"cost": cost,
	})


## Removes and returns the entry at `index`, or {} if out of range. The caller
## (CancelProductionCommand) is what refunds its cost -- this only owns the
## queue itself.
func cancel_training(index: int) -> Dictionary:
	if index < 0 or index >= queue.size():
		return {}
	return queue.pop_at(index)


## The front entry's progress as 0..1, for a queue progress bar. 0 with nothing
## queued, matching build_fraction()'s "nothing to show" convention rather than
## a divide-by-zero.
func training_fraction() -> float:
	if queue.is_empty():
		return 0.0
	var front: Dictionary = queue[0]
	return clampf(float(front.get("progress", 0)) / float(front.get("total", 1)), 0.0, 1.0)
