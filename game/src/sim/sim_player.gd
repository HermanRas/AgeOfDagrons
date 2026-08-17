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

var researched: Dictionary = {}
var control_groups: Array = [[], [], [], [], []]          # Array[Array[int]], one per CONTROL_GROUP_COUNT slot
var defeated: bool = false

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
