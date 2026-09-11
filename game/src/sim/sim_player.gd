## One player's persistent state within a match: stock, population, and (later)
## age/tech/control groups. Control groups persist here rather than client-side
## so they survive reconnect (PLAN.md 7.1).
class_name SimPlayer
extends RefCounted

## PLAN.md 10.1: fixed at 5, not configurable -- the HUD is a fixed vertical
## stack of 5 slots, not a scrollable list.
const CONTROL_GROUP_COUNT := 5

## What one tile of the fog of war is worth to this player (PLAN.md 2.5, and its
## 0/1/2 is the encoding PLAN.md 6.2 already specified for `vision`).
##
## Three states rather than two, and EXPLORED is the one that earns its place:
## terrain you have seen stays drawn because the ground does not move, while units
## standing on it do not, so "never seen" and "seen but not now" have to be told
## apart both by the renderer and by the snapshot filter. Named on SimPlayer rather
## than on VisionSystem because this is the meaning of the DATA below, and the
## renderer needs it as much as the system that writes it.
enum Fog { UNSEEN, EXPLORED, VISIBLE }

var id: int = 0
var peer_id: int = 0                 # 1 = host's own local player
## PLAN.md 2.7.1: half of the skin key. v1 ships one civilisation, so this is
## `faction.default` for every player and only `colour` below tells players apart.
## The field stays because civs return at 9.5 as a re-skin over this same roster,
## and it defaults to a real ID rather than &"" so no later check has to special-
## case an empty one -- which is what factions.json's own note always claimed.
var faction: StringName = &"faction.default"
## PLAN.md 1: the ONE thing that differs between players in v1. A palette index,
## not a Color -- the palette is data (colours.json, with the lobby at 1.6) and
## the tint itself is a view concern (A.6).
var colour: int = 0
var is_ai: bool = false

## How hard the bot in this chair plays (project owner, 2026-08-22). Meaningless when
## `is_ai` is false, and never read there.
##
## TWO FIELDS RATHER THAN ONE, and they answer genuinely different questions: `is_ai`
## is "is there a bot in this chair", which is what the wire, `AISystem`'s loop and
## every existing test ask, and this is "which bot". Collapsing them into one int with
## a HUMAN sentinel would have rewritten forty call sites to say the same thing.
##
## **ONLY PASSIVE AND EASY DO ANYTHING DIFFERENT TODAY.** Passive runs the whole
## economy and never attacks; Easy is the PlayTest AI exactly as it was. Normal, Hard
## and Unfair are declared and play as Easy -- they are in the lobby so the shape of
## the choice is visible and so the list does not renumber when they land, which is
## 12.2b's job. That is a deliberate placeholder and it is named as one on screen.
enum AILevel { PASSIVE, EASY, NORMAL, HARD, UNFAIR }
var ai_level: int = AILevel.EASY

## WHOSE SIDE THIS PLAYER IS ON (the lobby's team selector, 2026-08-31). Declared
## since 0.4 and read by nothing until now, which is the hole `garrison_cap` and
## `researched` were both in before something finally filled them.
##
## **0 IS NOT A TEAM, IT IS THE ABSENCE OF ONE**, and it is what a free-for-all
## carries -- so every match played before the selector existed plays exactly as it
## did, and a config that names no teams is still a config. `Diplomacy.allied` is the
## one place that rule is written down.
##
## Set once, by `SimWorld.setup` out of `MatchConfig.teams`, and never written again.
## That is why it stays out of `state_hash()`, the same reasoning `colour` and `mode`
## are given there -- a disagreement about it comes from the config and not from the
## simulation, and the config is broadcast whole.
var team: int = 0
var stock: Dictionary = {}           # StringName kind -> int amount
var pop_used: int = 0
var pop_cap: int = 0
var age: int = 1

## Age advancement in progress (PLAN.md 9.2), all three fields or none.
##
## `advancing_to` is 0 when idle, otherwise the age being researched -- which is
## always `age + 1`, but stored rather than derived so a snapshot says what is
## being advanced to without the reader having to know the rule.
##
## Progress is INT TICKS, not a float fraction. The sim carries no floats
## (PLAN.md 7.1); the view divides these two to draw the ring.
var advancing_to: int = 0
var advance_ticks: int = 0
var advance_total_ticks: int = 0

## Which technologies this player holds (PLAN.md 9.3): tech id -> true. Used as a
## SET rather than a list, because every reader asks "have I got this one" and none
## of them cares in what order they were bought.
##
## Declared since 0.4 and written by nothing until 2026-08-29, which is the hole
## 4.11's population counter was in before it was enforced -- a field the HUD reads
## and nothing fills. `SimWorld.grant_tech` is the only writer.
##
## IRREVERSIBLE. Nothing removes a tech, which is what lets `tech_mods` below be a
## running total rather than something that has to be recomputed against a shrinking
## set. If a tech ever becomes losable, `TechMods.sum` already rebuilds whole.
var researched: Dictionary = {}

## `researched` resolved into "stat.scope" -> int, by `TechMods.sum`. DERIVED STATE,
## kept because it is read on the hot path -- once per blow struck, once per gather
## take, once per builder per tick -- and re-summing 27 techs at each of those would
## put a dictionary walk inside `CombatSystem`.
##
## Deliberately NOT in `state_hash()`: `researched` is, and this is a pure function
## of it. Hashing both would report one divergence twice and hashing only this one
## would report a wrong SUM without saying which tech two hosts disagreed about.
var tech_mods: Dictionary = {}

var control_groups: Array = [[], [], [], [], []]          # Array[Array[int]], one per CONTROL_GROUP_COUNT slot

## KING OF THE HILL's tally (11.x-koth): per tick, **3 while this player's SIDE is the only one in
## the zone, 2 while it leads with company, 1 while it is merely present or tied** — PLAN.md
## §11.9's ladder. First to `WinConditionSystem.KOTH_TARGET_SCORE` wins. 0 in every other mode.
##
## ⛔ **THIS SAID "one point per tick this player's SIDE LEADS the zone" UNTIL 2026-09-11**, which
## was the flat rule PLAN.md had already reversed — under it a contested hill paid nobody and the
## mode's clock stopped during exactly the fights it exists to cause.
##
## ⚠️ **IT LANDED WITH THE RULE THAT WRITES IT, AND THAT IS WHY IT WAS NOT DECLARED EARLIER.**
## `_king_of_the_hill()`'s own placeholder note refused to add it ahead of time: *"an unwritten
## field that reaches the HUD is precisely the hole 4.11's counter was, and one field nothing
## writes is how it starts."* `garrison_cap` is the standing example — declared on all 31 buildings
## at 0.4 and read by nothing until 4.8.
##
## **PER PLAYER AND NOT PER TEAM, though a team scores together.** Every standing member of the
## leading side gets the same +1, so two allies hold identical numbers — which is correct and is
## what lets `winner_id` name a player the way every other mode does. A per-team tally would be a
## second place teams are recorded, beside `SimWorld.teams`.
##
## IN `state_hash()`, unlike `pop_used`: it is not derivable from anything else hashed. WHICH units
## are in the zone depends on positions that are hashed, but the running TOTAL is state nothing
## recomputes — so two hosts that disagreed for a single tick would agree about the whole world
## forever after and declare a winner on different ticks.
var score: int = 0

## WHAT THIS PLAYER EARNED ON THE MOST RECENT TICK — 0, 1, 2 or 3 (11.x-koth-hud). The rung of
## §11.9's ladder they are currently on, and therefore how fast their tally is moving.
##
## ⚠️ **IT EXISTS BECAUSE THE CLIENT CANNOT WORK IT OUT AND MUST NOT TRY.** The rate is
## `1 + unique leader + only side there`; a client has `koth_holder` for the middle term and
## **nothing for the other two** — it would have to count units in the zone, which
## `GameView.koth_holder`'s header forbids in as many words, because half a contested zone is in
## fog for every player but its owner. Two clients counting would show two different clocks for a
## rule the server has already decided. Same argument `koth_holder` and `score` both already won.
##
## 📝 **A RATE AND NOT A TIME.** The seconds a player reads off the HUD are
## `(target - score) / (rate * TICK_HZ)`, computed in the view where `SimClock.TICK_HZ` lives —
## `src/sim/` may not name a view class and a duration in the sim would be a second opinion about
## the tick rate. 0 means *no finite time*: they have nobody on the hill and are not approaching
## anything.
##
## **NOT IN `state_hash()`, ON `koth_holder`'s RULE.** It is a pure function of entity positions
## that are all hashed already, so folding it in would report one divergence twice. `score` is the
## hashed half, and it is hashed because it is a running TOTAL that nothing recomputes.
var koth_rate: int = 0

var defeated: bool = false

## WHY they are out (project owner, 2026-08-30: *"when a player disconnects or resigns
## the server does not notify other players"*), and BUGS.md's older *"a forfeit is
## announced as an elimination"*.
##
## The snapshot has carried the FACT of a defeat since 11.1 and never the reason, so a
## host whose opponent's phone went into a tunnel read **"All opponents eliminated"** --
## true about the outcome and untrue about how it happened, and with nothing said at the
## moment it happened either. Five reasons is the whole list the game can tell apart:
## `WinConditionSystem` sets ELIMINATED, a player's own press sets RESIGNED, `Net` sets
## DISCONNECTED for the `ResignCommand` it queues on a vanished peer's behalf (12.1e),
## `ObjectiveSystem` sets OBJECTIVE_FAILED for a scenario's authored `lose` row (15.2),
## and `WinConditionSystem._trophy` sets TROPHY_LOST (11.2). Anything else would be a
## distinction nothing can make.
##
## ⚠️ **OBJECTIVE_FAILED IS APPENDED, NOT INSERTED.** It travels as an int in
## `player_state.defeat_reason` and is folded into `state_hash()`, so inserting a member
## would renumber the other three and relabel every recorded and in-flight defeat.
##
## ⚠️ **AND SO IS TROPHY_LOST** (11.2, 2026-09-07), for the identical reason -- it went on
## the end even though it reads better beside ELIMINATED. **It is a reason of its own on
## exactly OBJECTIVE_FAILED's argument**: a player whose trophy dies may still own a town
## centre, an army and half the map, so *"eliminated"* would be a true statement about the
## outcome and a false one about how it happened, which is the forfeit defect BUGS.md
## recorded. It is the only defeat in the game that says nothing about what you still hold.
##
## IT IS A REASON OF ITS OWN AND NOT ELIMINATED WEARING A LABEL. A player who fails
## *"do not lose your town centre"* may still own an army, so calling that an
## elimination would be exactly the failure BUGS.md recorded for the forfeit -- a true
## statement about the outcome and a false one about how it happened.
##
## SET WITH `defeated` AND ONE-WAY LIKE IT. It is written in the same statement, so the
## two can never disagree about whether somebody is out, and never cleared for the same
## reason `defeated` is not -- a reason that could flicker would take the result screen's
## sentence with it.
enum Defeat { NONE, ELIMINATED, RESIGNED, DISCONNECTED, OBJECTIVE_FAILED, TROPHY_LOST }

var defeat_reason: int = Defeat.NONE

## HOW FAR ALONG EACH AUTHORED OBJECTIVE IS (PLAN.md 11.8, 15.2), position for position
## with `MatchConfig.objectives`. The COUNT the rule measured, not whether it passed:
## 15.6's tracker draws "Villagers 4 / 10" by pairing this with the def's own `value`,
## so the number the player reads is the number the sim compared.
##
## `ObjectiveSystem` is the only writer.
##
## **EMPTY MEANS NO OBJECTIVES HAVE BEEN EVALUATED**, and that is load-bearing rather
## than merely an initial state -- exactly as `vision` below documents. `SimWorld.setup`
## leaves it empty and `ObjectiveSystem` sizes it on its first tick, so a world that has
## never been stepped (most of the sim suite, and any tool that stands one up) reads as
## "no tracker" rather than as an objective list of zeros that nothing is maintaining.
##
## ONLY `MatchConfig.objective_player_id`'s ROW IS EVER FILLED, and the others stay
## empty on purpose. Progress is measured from ONE viewpoint -- `self`, `enemy` and
## `ally` are relative terms -- so another player's array could only hold the same
## objectives re-counted from a viewpoint nobody authored them for. 15.6's tracker reads
## the LOCAL player's, which is empty and draws nothing for a spectator.
##
## An `Array[int]` rather than a Dictionary because the objectives are an ORDERED list
## and the wire carries them in that order; a keyed form would need ids the author never
## wrote.
var objective_progress: Array[int] = []

## WHICH OBJECTIVES HAVE BEEN MET AT LEAST ONCE (15.2), position for position with
## `objective_progress`. 1 is met, 0 is not.
##
## ⚠️ **ONE-WAY, LIKE `defeated`, AND FOR THE SAME REASON.** An objective list is a
## CHECKLIST, and a ticked line does not untick; a verdict that could flicker off would
## take the result screen with it.
##
## The failure that proved it necessary was an ANDed pair where satisfying one row SPENT
## what satisfied the other -- 500 food and an age advance that costs exactly 500 food --
## which could never be true on the same tick. That particular pair was withdrawn by the
## owner within hours, so nothing shipped depends on this today; the SHAPE is general
## (units die, buildings fall, resources are spent), which is why it stays.
## `ObjectiveSystem`'s header carries the full worked example.
##
## A `PackedByteArray` rather than `Array[bool]`: it is one byte per row on the wire and
## in the hash, and it is the encoding `vision` already uses for the same reason.
##
## LOSE ROWS ARE NEVER LATCHED HERE -- a lose row ends the match on the tick it fires,
## so there is no later tick for a latch to matter on. Their slot stays 0.
var objective_done: PackedByteArray = PackedByteArray()

## Fog of war (PLAN.md 2.5): one `Fog` byte per tile, row-major over SimMap's grid
## and indexed by `SimMap.index_of()`. `VisionSystem` is the only writer.
##
## EMPTY MEANS "NO FOG", and that is load-bearing rather than merely an initial
## state. `SimWorld.setup()` leaves it empty and VisionSystem allocates it on its
## first tick, so a world that has never been stepped -- most of the sim test suite,
## and any tool that stands one up to inspect it -- has no fog rather than a grid
## that reads as entirely unseen. The alternative hides the whole map from everyone
## until something ticks, which is indistinguishable from a broken filter.
var vision: PackedByteArray = PackedByteArray()


## Put this player out of the match, and say why. THE ONLY WRITER of either field.
##
## ⚠️ **THE FIRST REASON IS THE TRUE ONE AND LATER ONES ARE IGNORED**, which is not
## tidiness -- it is the whole reason this is a function. `WinConditionSystem` re-tests
## every player every tick and defeats anyone owning nothing, so a player who RESIGNS and
## then loses their last building a tick later would have their reason quietly rewritten
## to ELIMINATED, and the winner would be told the opposite of what happened. The same
## ordering protects a DISCONNECTED player, whose base is still standing at the moment
## `Net` concedes for them and is knocked down some minutes later.
func defeat(reason: int) -> void:
	if defeated:
		return
	defeated = true
	defeat_reason = reason


func can_afford(cost: Dictionary) -> bool:
	for kind in cost:
		if int(stock.get(kind, 0)) < int(cost[kind]):
			return false
	return true


func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for kind in cost:
		stock[kind] = int(stock.get(kind, 0)) - int(cost[kind])
	return true


func refund(cost: Dictionary) -> void:
	for kind in cost:
		add_resource(kind, int(cost[kind]))


func add_resource(kind: StringName, amount: int) -> void:
	stock[kind] = int(stock.get(kind, 0)) + amount


func has_tech(tech_id: StringName) -> bool:
	return bool(researched.get(tech_id, false))


## The techs this player holds, sorted, as plain Strings.
##
## `Array[String]` and NOT `Array[StringName]`, and that is not a style choice:
## `Array[StringName].sort()` orders by StringName IDENTITY rather than by content,
## which is arbitrary and not stable between runs (AGENT_GAME_CODER.md §6, and
## `test_game_data` pins it). Both callers -- the snapshot and `state_hash()` -- need
## a stable order, and one of them would desync without it.
func researched_ids() -> Array[String]:
	var out: Array[String] = []
	for id in researched:
		if bool(researched[id]):
			out.append(String(id))
	out.sort()
	return out


func is_advancing() -> bool:
	return advancing_to > 0


## Begin advancing. The caller has already checked it is allowed
## (AdvanceAgeCommand.validate); this only records the state.
func begin_advance(to_age: int, total_ticks: int) -> void:
	advancing_to = to_age
	advance_ticks = 0
	# At least one tick, so a zero-time age still shows one frame of progress
	# rather than dividing by zero in the view.
	advance_total_ticks = maxi(1, total_ticks)


## One tick of progress. Returns true on the tick the age actually changes, so
## AgeSystem can announce it without re-deriving completion.
func tick_advance() -> bool:
	if not is_advancing():
		return false
	advance_ticks += 1
	if advance_ticks < advance_total_ticks:
		return false
	age = advancing_to
	cancel_advance()
	return true


func cancel_advance() -> void:
	advancing_to = 0
	advance_ticks = 0
	advance_total_ticks = 0
