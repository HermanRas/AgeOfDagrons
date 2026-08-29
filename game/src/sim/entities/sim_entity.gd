## Base for everything that exists in the sim: units, buildings, resource
## nodes. Plain GDScript, no Node -- the src/sim/ boundary rule (PLAN.md 4)
## is what makes headless testing and a rendering-free server possible.
class_name SimEntity
extends RefCounted

var id: int = 0
var def_id: StringName = &""
var owner_id: int = 0
var pos: Vector2i = Vector2i.ZERO          # sub-tile units, PLAN.md 1
var hp: int = 0
var max_hp: int = 0
var alive: bool = true
var vision_range: int = 0

## How many units this entity can hold, and who is in it (PLAN.md 4.8).
##
## **HERE RATHER THAN ON `SimBuilding`, AS OF 2026-08-29 AND THE TRANSPORT SHIP.** These
## lived on the building for two days and had to move the moment a second kind of thing
## could carry units, because everything that reads them -- `GarrisonCommand`,
## `UngarrisonCommand`, `GarrisonSystem`, `SimWorld.garrison_unit` and
## `DeathSystem._kill_garrison` -- is asking "what is inside this" and not "what kind of
## thing is this". Duplicating the pair onto `SimUnit` would have duplicated all five.
##
## `SimUnit.garrisoned_in` was ALREADY an entity id rather than a building id and its
## header already described exactly what a boat needs: still in `entities` so population
## keeps charging, out of `SpatialHash` so nothing can find it, and skipped by
## `SnapshotSystem` so the client releases the sprite. That is why this generalised in
## one sitting -- the hard half was written for towers and is domain-agnostic.
##
## The cost is two fields on every `SimResourceNode`, which is a `cap` of 0 and an empty
## array on five hundred trees. Memory only: `to_snapshot` is per subclass and a node
## never sends either.
var garrison_cap: int = 0

## Who is inside, in the order they entered. Each entry is `{id, def_id}` -- see
## `SimBuilding`'s note on why the def id is copied rather than looked up.
var garrison: Array[Dictionary] = []


func tile() -> Vector2i:
	return pos / SimWorld.SUBTILE


## The tiles this entity stands on. One for a unit, a node or an arrow; a footprint for
## a building, which overrides.
##
## What the garrison paths and adjacency checks measure against, so that "walk up to the
## thing and get in" is one implementation whether the thing is a 7x7 castle or a boat.
func occupied_rect() -> Rect2i:
	return Rect2i(tile(), Vector2i.ONE)


## Room for one more (PLAN.md 4.8). False for everything with `garrison_cap` 0, which is
## 28 of the 31 buildings and every unit but the transport -- so this single test covers
## "walls hold nobody", "a house is not a shelter" and "a knight is not a ferry" without
## any of them being spelled out anywhere.
##
## Subclasses ADD to it rather than replace it: a building must also be finished, and a
## carrier must not itself be inside something.
func has_garrison_room() -> bool:
	return alive and garrison.size() < garrison_cap


## Where `unit_id` sits in the garrison, or -1. Used by the eject path, which is given a
## unit and needs the slot, and by the tests.
func garrison_index(unit_id: int) -> int:
	for i in range(garrison.size()):
		if int(garrison[i]["id"]) == unit_id:
			return i
	return -1


## Every id inside, for callers that want to walk the occupants rather than price them.
## Sorted is not needed and not offered: `garrison` is already in a deterministic order
## and every caller either sums (which commutes) or indexes.
func garrison_ids() -> Array[int]:
	var out: Array[int] = []
	for entry in garrison:
		out.append(int(entry["id"]))
	return out


func take_damage(amount: int, _attack_type: int) -> void:
	hp = maxi(0, hp - amount)
	if hp == 0:
		alive = false


func on_tick(_w: SimWorld) -> void:
	pass


## Whether this entity's POSITION is the thing that would leak if it were sent
## through the fog (PLAN.md 2.5, and `SnapshotSystem._entry_for`'s four categories).
##
## The fog splits entities into mobile and static, and static ones are sent
## REMEMBERED once explored -- a building or a tree does not move, so telling you it
## is there gives away nothing that will have changed by the time you look again. A
## mobile entity is simply not sent, because where it is now is exactly the fact its
## owner is entitled to keep.
##
## A VIRTUAL RATHER THAN `e is SimUnit` AT THE CALL SITE, which is what it used to be.
## That read as "units move and nothing else does", which was true until 4.13 gave the
## world a second moving thing: an arrow in flight would have fallen through to the
## static branch and been sent as a REMEMBERED entity to anyone who had ever explored
## the tile it was over -- a running commentary on where somebody is fighting, drawn
## through the fog. Asking the entity means the next moving thing cannot repeat it.
func is_mobile() -> bool:
	return false


## A `Vector2i` FOR `pos`, NOT A PAIRED-INT DICTIONARY (12.1f). `{"x": .., "y": ..}` cost
## 48 bytes to carry two small integers, because `var_to_bytes` re-encodes the key names
## "x" and "y" inside every entry; the Vector2i is 12. Sixty bytes down to twenty-four,
## on every entity, every tick.
##
## Safe here and NOT in `MapData`, which notes the opposite ("Vector2i is not JSON") for a
## good reason: a saved map goes through JSON, and a snapshot never does. Snapshots cross
## by RPC, which encodes Variants in binary; the only thing this project puts through JSON
## is `Replay`, and that carries commands rather than snapshots.
func to_snapshot() -> Dictionary:
	return {
		"id": id,
		"def_id": def_id,
		"owner_id": owner_id,
		"pos": pos,
		"hp": hp,
		"max_hp": max_hp,
		"alive": alive,
	}
