## How many of one unit kind may exist at once, and **the answer depends on the match mode**
## (PLAN.md 13, project owner 2026-09-04).
##
## ## WHY THIS EXISTS: THE DRAGON HAS NO PLAYER COLOUR AND CANNOT BE GIVEN ONE
##
## `colours.json` states that player colour is the only thing distinguishing one player's
## units from another's in v1. The dragon has **no playercolour mask** — the art side measured
## it rather than assuming: white against blue at `directions = 1`, 5,567 opaque pixels, **0
## moved**, largest channel gap 0. Not "under the noise floor", *identical*. And
## `vis.dragon_rigged` could not take colour even if a mask appeared, because `player_colour`
## is a zeroad-adapter feature and the rigged bake goes through the generic one.
##
## So if two players can field a dragon at once, **nothing on screen says whose it is**. That
## is not fixable at any price on the art side, which is why it is fixed here.
##
## ## THE OWNER'S RULE, AND IT IS PER MODE RATHER THAN PER UNIT
##
## | Mode | Limit of 1 means |
## |---|---|
## | `LAST_MAN_STANDING`, `KING_OF_THE_HILL` | **one per MAP** — a single contested dragon, whoever gets it first |
## | `TROPHY` | **one per PLAYER** |
## | `SCENARIO` | **no limit** — see below |
##
## The ambiguity only arises where two can coexist, which is `TROPHY`, and there it is the
## price of the mode having been asked for that way. In the two conquest modes the question
## cannot come up: there is only ever one dragon in the world.
##
## ⚠️ **`SCENARIO` IS UNCAPPED ON PURPOSE, AND THIS IS AN ASSUMPTION I AM FLAGGING.** A
## scenario author places what the mission needs, and 15.x's "find a dragon and tame it" wants
## a gaia mother AND a baby alive at the same moment — a map-wide cap of one would make that
## mission unauthorable. The scenario's own objectives are its limit. If a campaign ever wants
## a cap, it belongs in `scenario.json` beside the objectives, not here.
##
## ## IT COUNTS QUEUED UNITS TOO, OR THE LIMIT IS TRIVIALLY BEATABLE
##
## Exactly `PopulationSystem.queued_pop`'s reasoning: a queue holds units that are coming
## whatever happens in the meantime, so a player with two castles could order a dragon at each
## in the same tick and `ProductionSystem` would spawn both. The gate has to count what has
## been ORDERED, not only what is standing.
class_name UnitLimitSystem
extends RefCounted

## Whose units a limit is counted across.
enum Scope {
	## No limit is enforced at all.
	NONE,
	## Every unit of the kind in the world, whoever owns it — including gaia.
	MAP,
	## Only the ordering player's own.
	PLAYER,
}


## What a `UnitDef.limit` is counted across, for this match's mode.
##
## Spelled out per mode rather than defaulted, with conquest as the fallback: a mode added
## later gets the strictest answer until somebody decides otherwise, which is the safe
## direction for a rule whose whole job is to stop an unidentifiable unit appearing twice.
static func scope_for(mode: MatchConfig.Mode) -> Scope:
	match mode:
		MatchConfig.Mode.TROPHY:
			return Scope.PLAYER
		MatchConfig.Mode.SCENARIO:
			return Scope.NONE
		_:
			return Scope.MAP


## Whether `player_id` may order one more `ud`.
##
## Called by `TrainCommand.validate()` — the server is the only trust boundary — and by
## `AiSystem` before it asks, so the AI does not spend its whole match re-issuing a command
## that will be refused. The same arrangement `PopulationSystem.has_room_for` has.
static func allows(w: SimWorld, player_id: int, ud: UnitDef) -> bool:
	if ud == null or not ud.is_limited():
		return true
	var scope := scope_for(w.mode)
	if scope == Scope.NONE:
		return true
	return existing(w, ud.id, player_id if scope == Scope.PLAYER else -1) < ud.limit


## How many of `def_id` exist or are on order.
##
## `owner_id` of **-1 means every owner**, which is what `Scope.MAP` asks. Gaia (0) is a real
## owner here and is counted: "one dragon per map" has to mean one, or a scenario's wild
## dragon would sit alongside a trained one and the mode's promise would be false.
static func existing(w: SimWorld, def_id: StringName, owner_id: int) -> int:
	return alive(w, def_id, owner_id) + queued(w, def_id, owner_id)


## The ones standing. Rubble and dead units are skipped — a limit is about what is in the
## world, and a dragon that died should let its owner train another.
static func alive(w: SimWorld, def_id: StringName, owner_id: int) -> int:
	var n := 0
	for e in w.entities.values():
		if not (e is SimUnit):
			continue
		var u := e as SimUnit
		if not u.alive or u.def_id != def_id:
			continue
		if owner_id >= 0 and u.owner_id != owner_id:
			continue
		n += 1
	return n


## The ones paid for and not yet standing. See the class comment: without this the limit is
## beaten by ordering at two buildings in one tick.
##
## A destroyed building's queue is skipped for the same reason `ProductionSystem` skips it —
## nothing is coming out of it, so reserving the limit for it would deny a unit forever.
static func queued(w: SimWorld, def_id: StringName, owner_id: int) -> int:
	var n := 0
	for e in w.entities.values():
		if not (e is SimBuilding):
			continue
		var b := e as SimBuilding
		if not b.alive:
			continue
		if owner_id >= 0 and b.owner_id != owner_id:
			continue
		for entry in b.queue:
			if StringName(entry.get("def_id", &"")) == def_id:
				n += 1
	return n
