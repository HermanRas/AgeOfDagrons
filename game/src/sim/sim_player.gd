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
var defeated: bool = false

## WHY they are out (project owner, 2026-08-30: *"when a player disconnects or resigns
## the server does not notify other players"*), and BUGS.md's older *"a forfeit is
## announced as an elimination"*.
##
## The snapshot has carried the FACT of a defeat since 11.1 and never the reason, so a
## host whose opponent's phone went into a tunnel read **"All opponents eliminated"** --
## true about the outcome and untrue about how it happened, and with nothing said at the
## moment it happened either. Three reasons is the whole list the game can tell apart:
## `WinConditionSystem` sets ELIMINATED, a player's own press sets RESIGNED, and `Net`
## sets DISCONNECTED for the `ResignCommand` it queues on a vanished peer's behalf
## (12.1e). Anything else would be a distinction nothing can make.
##
## SET WITH `defeated` AND ONE-WAY LIKE IT. It is written in the same statement, so the
## two can never disagree about whether somebody is out, and never cleared for the same
## reason `defeated` is not -- a reason that could flicker would take the result screen's
## sentence with it.
enum Defeat { NONE, ELIMINATED, RESIGNED, DISCONNECTED }

var defeat_reason: int = Defeat.NONE

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
