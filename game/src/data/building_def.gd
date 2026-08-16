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

## What a villager can harvest from this building, for the buildings that are
## really resource nodes wearing a footprint -- a field. `&""` for the
## overwhelming majority, which are not gatherable at all.
var gather_kind: StringName = &""
## Total yield before the building is spent and removed. A field is not
## inexhaustible: it costs wood, and a farm that fed a town forever would make
## every other food source pointless.
var gather_amount: int = 0
## How many villagers can work it at once, mirroring ResourceDef.gather_slots.
var gather_slots: int = 1


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

	var g: Dictionary = d.get("gather", {})
	b.gather_kind = StringName(g.get("kind", ""))
	b.gather_amount = int(g.get("amount", 0))
	b.gather_slots = int(g.get("slots", 1))
	return b


func accepts_drop_off(kind: StringName) -> bool:
	return drop_off.has(kind)


## Whether a villager can harvest this building at all -- true for a field and
## nothing else today.
func is_gatherable() -> bool:
	return gather_kind != &"" and gather_amount > 0


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
