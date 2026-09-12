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

## Whose blow last landed on this, or `NO_ATTACKER` if nothing traceable ever has
## (PLAN.md 13.2). Written only by `take_damage` and read, today, only by `NestSystem` --
## the dragon's claimant is whoever landed the killing blow.
##
## SIM-ONLY AND DELIBERATELY OFF THE WIRE. `SnapshotSystem`'s shape tables group `updated`
## by sorted field names (12.1f), so an extra int here is an extra int on every unit,
## building and tree in the game -- and nothing on the client has a use for it. If a kill
## feed or a claim countdown ever wants it, that is the row where the cost gets weighed.
var last_attacker_owner: int = NO_ATTACKER

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

## ── what a MAP said about THIS ONE entity (PLAN.md 16.7) ────────────────────
##
## ## ⛔ AUTHORED STATE, AND THAT IS WHY ALL FOUR ARE IN `state_hash()`
##
## Everything else on an entity is either derived from its def -- the same on every client,
## because the roster ships in the APK -- or changed by a system both hosts run. These four are
## neither: they come out of a `map.json` that one client may have read and another may not, and
## nothing recomputes them. **Two hosts disagreeing about how much hp a scripted hero has would
## agree about every other field until somebody hit him**, and `hp` reports that only after the
## fact. 16.7's card names this as the row's whole risk.
##
## ## ⚠️ THEY ARE THE OVERRIDE AND NOT THE RESULT, WHICH IS WHAT MAKES THE HASH CHEAP AND EXACT
##
## `max_hp` and `speed` are live fields that systems already move at runtime -- `SiegeSystem`
## rewrites `speed` on every pack and unpack -- so hashing THOSE would fold a derived value in
## beside the thing it is derived from. What can genuinely differ between two clients is what the
## FILE said, so that is what rides: the consequence is then a function of (def + override), which
## both hosts compute the same way.
##
## ## HERE RATHER THAN ON `SimUnit`, FOR `garrison_cap`'s REASON EXACTLY
##
## A building can be named and given hp (*"hold the Keep"*), a unit can be named and given all
## three, and everything that reads them is asking *"did the map say something about this one"*
## rather than *"what kind of thing is this"*. The cost is three ints and a StringName on five
## hundred trees, which is memory only -- `to_snapshot` is per subclass and a node sends none of
## it.
##
## ⚠️ **`speed_override` ON A BUILDING IS MEANINGLESS AND IS NOT REFUSED HERE.** `MapGen.build_from`
## applies it only to units; the tool offers it only for units. Same trade `garrison_cap` makes by
## sitting on every resource node in the game.

## This entity's own name, or `&""`. What `subject: "named_unit"` counts (16.7).
##
## ⛔ **SIM-ONLY AND DELIBERATELY OFF THE WIRE**, `last_attacker_owner`'s rule and its reasoning:
## `SnapshotSystem`'s shape tables group `updated` by sorted field names (12.1f), so a name here
## is a field on every unit, building and tree in the game to carry a string that one or two
## entities on an authored map actually have. **The objective that reads it is evaluated in the
## SIM**, on the host, so the wire never needs it.
##
## 📝 **THE CONSEQUENCE, SAID OUT LOUD RATHER THAN DISCOVERED: THE HUD CANNOT SHOW IT.** Selecting
## a named hero shows the def's display name, exactly as before. Putting it on the wire is a real
## row with a real cost and it is not this one -- 12.1f spent an optimisation pass removing
## per-entity field names, and a field present on two units and absent on four hundred splits
## every unit into two shape tables.
var entity_name: StringName = &""

## Full health as the MAP wrote it, or 0 for "the def decides".
##
## **0 AND NOT -1**, unlike the two below: nothing alive has 0 max hp, so the sentinel cannot
## collide with a value an author might mean. `MapGen.build_from()` sets `hp` to match, because a
## scripted hero arrives at full health and a map that wanted him wounded would be saying that
## with a different field.
var max_hp_override: int = 0

## Damage per blow as the MAP wrote it, or -1 for "the def decides".
##
## ⚠️ **-1 AND NOT 0, BECAUSE 0 IS A REAL ANSWER.** `CombatSystem` reads `attack_damage <= 0` as
## *"this cannot attack"*, which is what a villager is -- so an author disarming a unit deliberately
## is writing 0 and must not be read as writing nothing.
var attack_override: int = -1

## Sub-tile units per tick as the MAP wrote it, or -1 for "the def decides".
##
## ⚠️ **-1 AND NOT 0 FOR `attack_override`'s REASON, and the example is on the board**: every
## deployed siege engine declares `speed: 0` on purpose, so 0 means *"this does not move"* and is
## a thing an author may legitimately want.
var speed_override: int = -1


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


## Nobody in particular did this. A transport sinking with soldiers aboard, a garrison
## going down with its tower, a debug destroy -- damage that is a CONSEQUENCE rather than
## a blow, and there is no honest owner to name for it.
##
## NOT 0, which is gaia and is a real attacker: a wolf killing a villager is owner 0
## landing a hit, and a rule reading "unknown" as "gaia" would credit the dragon's death
## to the wilderness the moment anything untraceable finished her off.
const NO_ATTACKER := -1


## `attacker_owner` IS REQUIRED, WITH NO DEFAULT, AND THAT IS THE SAFETY PROPERTY -- the
## same argument `Diplomacy.is_enemy(e, player_id, teams)` makes about its team table. It
## could have defaulted to `NO_ATTACKER` and every one of the four existing damage sources
## would have compiled unchanged; the one that was never updated would then be a kill that
## quietly credits nobody, and the symptom is a dragon that cannot be claimed by whichever
## weapon you happened to use. GDScript reports a missing argument at parse time instead.
##
## WHY THIS EXISTS AT ALL, given `WildlifeSystem._check_flee` deliberately does not use it:
## that one needs to know it was hurt, and a drop in hp is the same information for the
## price of a field. 13.2's claim needs to know *by whom*, which no delta can answer.
##
## `last_attacker_owner` PERSISTS rather than being read and cleared. The killer is
## whoever landed the blow that took hp to 0, which is by definition the last write.
func take_damage(amount: int, _attack_type: int, attacker_owner: int) -> void:
	if attacker_owner != NO_ATTACKER:
		last_attacker_owner = attacker_owner
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
