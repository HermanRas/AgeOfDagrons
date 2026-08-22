## One entry from data/buildings.json (PLAN.md 9). Phase 0.4.
##
## Carries all THREE visual IDs, not one: a building is a foundation, a completed
## structure or rubble (SimBuilding.Phase), and 0 A.D. models those as separate
## actors, so they are separate atlases keyed by footprint size --
## `vis.foundation_8x8` serves every 8x8 building added later
## (ASSET_MISSING.md 1.2). There is no under-construction art; the foundation
## covers that phase too.
class_name BuildingDef
extends RefCounted

var id: StringName = &""
var name: String = ""

## Phase.COMPLETE.
var visual: StringName = &""
## Phase.FOUNDATION and Phase.UNDER_CONSTRUCTION.
var visual_foundation: StringName = &""
## Phase.DESTROYED.
var visual_rubble: StringName = &""

var hp: int = 1

## Tiles occupied on the grid. This is GAMEPLAY footprint and it is not always
## the art's own extent -- see buildings.json for where the two differ and why.
var footprint: Vector2i = Vector2i.ONE
var los: int = 0

var cost: Dictionary = {}
var build_time_ticks: int = 0

var provides_pop: int = 0
var garrison_cap: int = 0

var trains: Array[StringName] = []
## Resource kinds a villager may return a load to here.
var drop_off: Array[StringName] = []
var age_required: int = 1

## Building ids this one's footprint must TOUCH to be placed at all, or empty for
## the usual "anywhere legal" (PLAN.md 5.1). A field must abut its mill: the
## roster line is `Farm[Mill] ... can add up to 4 field`, and a farm on the far
## side of the map from anything that could receive its crop is not a farm.
## Satisfied by ANY one of the listed ids, and only by a COMPLETE building of the
## placing player's own.
var requires_adjacent: Array[StringName] = []

## How many of THIS building may abut one host from `requires_adjacent`, or 0 for
## no limit. Four fields to a mill, per the roster.
var max_per_host: int = 0

## The same cap PER AGE, indexed 1-4 (so entry 0 is age 1), or empty to use the
## flat `max_per_host` at every age.
##
## The project owner asked whether age 2 should really allow all four fields
## (2026-08-17). It should not: four plots at the age-2 yield is most of a town's
## food from one building the moment the age lands, and the roster's four is where
## a farm ECONOMY ends up rather than where it starts. Two, three, four -- one more
## per age, the same shape as the yield's +1.5.
var max_per_host_by_age: Array[int] = []

## Whether this building's footprint closes its tiles to movement. TRUE for
## everything with walls; FALSE for a field, which claims the ground so nothing is
## built over the crop and lets villagers walk on and across it.
##
## A field had to be walkable for two reasons that turned out to be one
## (project owner, 2026-08-17): a 6x6 plot flush against a 5x4 mill leaves no free
## tile to stand on to drop food off, and there is no way onto the plot to spread
## the gatherers over it. Both are "the crop is a wall", and it should never have
## been one -- 0 A.D.'s own fields are walked over.
var blocks_movement: bool = true

## WALLS (PLAN.md 5.8), and the three fields that make one.
##
## `wall_lengths` is what turns a building into a DRAG TOOL. It lists the segment
## defs of one wall tier in ascending length order, including this def itself, and a
## non-empty list is the flag: `WallPlan` reads it to decide what to lay along a
## drag, and the build menu offers only the def that carries one. Length comes from
## each named def's own `footprint.x` -- there is no separate length number to fall
## out of step with the footprint it has to match.
##
## Empty for every ordinary building, which is placed one at a time.
var wall_lengths: Array[StringName] = []

## Whether the BUILD MENU may offer this. False for a wall's medium and long
## segments: the wall system places them, a player never picks them, and without
## this the grid would list all twelve wall pieces (see buildings.json).
##
## Deliberately NOT a substitute for `age_required` -- that gates by progress and is
## enforced on the server as well, where this is only ever about what the menu draws.
## `PlaceBuildingCommand` does not check it, because a segment placed by
## `PlaceWallCommand` is a perfectly legal placement of a def the menu will not show.
var buildable: bool = true

## Whether this is a GATE: a wall piece that can be opened and closed.
##
## The mechanism is `SimBuilding.gate_locked` plus `blocks_now()`, and it is cheap
## because `SimMap.set_occupied` already takes a `blocks` flag -- the same one that
## makes a field walkable. What it is NOT is per-player passability: an OPEN gate is
## open to everybody, including whoever is besieging it. See `ToggleGateCommand`.
var is_gate: bool = false

## What this building can be turned into where it stands, or `&""` for the
## overwhelming majority that cannot be upgraded at all (PLAN.md 5.8).
##
## Only the three LONG wall segments carry one today, and each names its own tier's
## gate. That is what makes a gate placeable at all on a north-south wall: a gate is
## 9x2 and `PlaceBuildingCommand` has no facing and never transposes a footprint, so
## a tap-placed gate could only ever lie east-west. Upgrading in place sidesteps the
## whole question -- the segment already knows its axis, and the gate inherits it.
##
## THE TARGET MUST HAVE THE SAME FOOTPRINT, which is why this sits on the long piece
## and not on the short one: a 3x2 segment has nowhere to put a 9x2 gate, and growing
## the footprint would mean re-checking ground the player cannot see is needed.
## `UpgradeBuildingCommand.validate()` enforces the match rather than trusting it,
## since it is a fact about two separate JSON entries that nothing else pins.
var upgrades_to: StringName = &""

## `amount: -1` in the JSON: this building's crop never runs out. A FIELD IS
## INEXHAUSTIBLE (project owner, 2026-08-17), which reverses the call recorded
## here before -- the balancing lever is the per-age YIELD below, not a total, and
## a field that had to be rebuilt every few minutes made a mill's four plots into
## upkeep rather than an economy.
##
## A sentinel rather than a separate `infinite` flag because `gather_amount` is
## also the RUNTIME crop on SimBuilding, rides the snapshot, and is in
## `state_hash()`. One field with three states (positive, spent at 0, infinite at
## -1) keeps all of that in one place; a parallel bool would have to be threaded
## through every one of them and could contradict the number beside it.
const INFINITE_CROP := -1

## What a villager can harvest from this building, for the buildings that are
## really resource nodes wearing a footprint -- a field. `&""` for the
## overwhelming majority, which are not gatherable at all.
var gather_kind: StringName = &""
## Total yield before the building is spent and removed, or INFINITE_CROP.
var gather_amount: int = 0
## How many villagers can work it at once, mirroring ResourceDef.gather_slots.
## Five for a field, per the owner: it is 36 tiles of ground and the cap is what
## decides how much of a town's labour one plot can absorb.
var gather_slots: int = 1

## FIELDS ONLY: food per 100 ticks per villager, indexed by age 1-4 (so entry 0 is
## age 1). Empty for everything else, which falls back to the gatherer's own
## `UnitDef.gather_rate` the way a tree does.
##
## The yield is the FIELD's, not the villager's, and that is the whole reason this
## exists: a farm's output is a property of the farm and of how far the owner has
## researched, where a tree gives up wood at whatever rate the axe swings. Per 100
## ticks to match `UnitDef.gather_rate`'s unit exactly, so GatherSystem can put
## both through the same schedule and there is one unit of "gather rate" in the
## project rather than two.
##
## Keyed on AGE as an approximation of the real trigger. The owner's rule is "as
## research is completed at the mill the field yield increases": that is a mill
## TECH (techs.json exists, nothing researches yet), and age is what stands in for
## it until 9.3. When techs land this becomes a lookup on what the player has
## researched and the numbers move here rather than into new code.
var gather_yield_per_age: Array[int] = []


static func from_dict(p_id: StringName, d: Dictionary) -> BuildingDef:
	var b := BuildingDef.new()
	b.id = p_id
	b.name = str(d.get("name", String(p_id)))
	b.visual = StringName(d.get("visual", ""))
	b.visual_foundation = StringName(d.get("visual_foundation", ""))
	b.visual_rubble = StringName(d.get("visual_rubble", ""))

	b.hp = int(d.get("hp", 1))
	b.footprint = GameDefs.tile_size(d.get("footprint", []), Vector2i.ONE)
	b.los = int(d.get("los", 0))

	b.cost = GameDefs.int_map(d.get("cost", {}))
	b.build_time_ticks = int(d.get("build_time_ticks", 0))

	b.provides_pop = int(d.get("provides_pop", 0))
	b.garrison_cap = int(d.get("garrison_cap", 0))

	b.trains = GameDefs.name_list(d.get("trains", []))
	b.drop_off = GameDefs.name_list(d.get("drop_off", []))
	b.age_required = int(d.get("age_required", 1))

	b.requires_adjacent = GameDefs.name_list(d.get("requires_adjacent", []))
	b.max_per_host = int(d.get("max_per_host", 0))
	b.max_per_host_by_age = GameDefs.int_list(d.get("max_per_host_by_age", []))
	b.blocks_movement = bool(d.get("blocks_movement", true))

	b.wall_lengths = GameDefs.name_list(d.get("wall_lengths", []))
	b.buildable = bool(d.get("buildable", true))
	b.is_gate = bool(d.get("is_gate", false))
	b.upgrades_to = StringName(d.get("upgrades_to", ""))

	var g: Dictionary = d.get("gather", {})
	b.gather_kind = StringName(g.get("kind", ""))
	b.gather_amount = int(g.get("amount", 0))
	b.gather_slots = int(g.get("slots", 1))
	b.gather_yield_per_age = GameDefs.int_list(g.get("yield_per_age", []))
	return b


func accepts_drop_off(kind: StringName) -> bool:
	return drop_off.has(kind)


## Whether a drag lays this down as a run of segments rather than placing one.
func is_wall_run() -> bool:
	return not wall_lengths.is_empty()


## Whether a villager can harvest this building at all -- true for a field and
## nothing else today. `!= 0` rather than `> 0`, so INFINITE_CROP counts: a spent
## crop is exactly 0 and nothing else.
func is_gatherable() -> bool:
	return gather_kind != &"" and gather_amount != 0


## How many of this building may abut one host at `age`. Falls back to the flat
## `max_per_host` when no per-age list is declared, and clamps at both ends for the
## same reason `gather_yield_for_age()` does.
func max_per_host_for_age(age: int) -> int:
	if max_per_host_by_age.is_empty():
		return max_per_host
	return max_per_host_by_age[clampi(age - 1, 0, max_per_host_by_age.size() - 1)]


## Food per 100 ticks per villager working this building at `age`, or 0 if it
## yields nothing there. Clamped rather than out-of-range: an age past the end of
## the list gets the last entry, which is what a fifth age should inherit, and age
## 1 with no list at all gets 0.
##
## 0 is a real answer and not a fallback -- age 1 declares 0 because a field cannot
## be built until age 2, and a villager sent to farm at a yield of 0 stops rather
## than standing in a crop forever.
func gather_yield_for_age(age: int) -> int:
	if gather_yield_per_age.is_empty():
		return 0
	return gather_yield_per_age[clampi(age - 1, 0, gather_yield_per_age.size() - 1)]


## The visual for a given SimBuilding.Phase, by its integer value. Taken as an
## int rather than the enum because SimBuilding does not exist until phase 5.2
## and this must not wait for it.
func visual_for_phase(phase: int) -> StringName:
	match phase:
		0, 1:  # FOUNDATION, UNDER_CONSTRUCTION
			return visual_foundation
		3:     # DESTROYED
			return visual_rubble
		_:     # COMPLETE
			return visual
