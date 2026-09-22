## ⚠️ **NOT THE GAME'S `WallPlan`. A THREE-CONSTANT STAND-IN, like `format/sim_world.gd` and
## `format/map_generator.gd` before it.**
##
## `format/map_data.gd` IS verbatim, and one line of it reads `WallPlan.AXIS_Y` — the key that
## decides whether an entity's footprint is transposed (16.4c). That is the whole dependency this
## tool has on the class.
##
## The game's real `wall_plan.gd` is the **drag logic**: `plan()` turns a gesture from one tile to
## another into a run of segments, choosing lengths greedily and normalising the direction. A
## map-authoring tool has no business carrying that, on `format/sim_world.gd`'s rule — *"something
## needing more of it than a constant means the tool is reaching into the simulation"* — and
## PLAN.md §16 decision 2 is what that rule serves. **The MapMaker offers two rotations as two
## palette rows; it does not plan runs.**
##
## ## THE THREE CONSTANTS, AND WHY THE FACING TABLE IS HERE AT ALL
##
## `AXIS_X` and `AXIS_Y` are what a saved `map.json` writes into its optional `axis` key, so they
## are **numbers in a file format** and not merely names in code.
##
## `FACING_FOR_AXIS` is not read anywhere in this project — `MapGen.build_from()` uses it on the
## game side — and it is declared here **so that `FormatGuard` has something to check it
## against.** ⚠️ Swapping its two entries would draw every authored wall on the wrong axis while
## every footprint stayed correct: the map would validate, the tool would look right, and the
## match would be ninety degrees out. That is the fault the owner reported on 2026-08-28 (*"i am
## dragging NE to SW, the walls look like NW to SE"*), which took six days and a regression of
## the mean opaque-pixel slope across twelve wall atlases to settle. A check that watched only
## `AXIS_X` would not see it, so all three are checked by declaration.
##
## ⚠️ **DO NOT GROW THIS FILE.** `plan()` and `lengths_of()` belong to the sim. If something here
## starts wanting them, raise it rather than adding another stub.
##
## 📝 **`diagonal_step()` ARRIVED 2026-09-22 AND IS NOT A BREACH OF THAT RULE, THOUGH IT LOOKS
## LIKE ONE.** The rule is about DRAG LOGIC — turning a gesture into a run is the sim's job. This
## is FOOTPRINT ARITHMETIC: it decides how many tiles an authored diagonal wall claims, and the
## verbatim `format/map_data.gd` needs it for the same reason it needs `AXIS_Y`. Three readers
## have to agree about that number — the game's `footprint_rect_of`, `MapGen.build_from` and this
## tool's collision test — and a second implementation of it here is the drift this whole
## mechanism exists to stop. ⚠️ **It is a FUNCTION, so `FormatGuard` cannot check it by
## declaration the way it checks the constants.** Keep it byte-identical to the game's by hand.
class_name WallPlan
extends RefCounted

## Axis 0 runs along +x in tile space, axis 1 along +y.
##
## **MUST MATCH the game's `src/sim/wall_plan.gd`.** Checked at startup by declaration, not by
## hash — see the class comment. On screen, `Iso._project` makes +x go right-and-down and +y
## left-and-down, so axis X spans **NW–SE** and axis Y spans **NE–SW**; that is where
## `ObjectPalette.AXIS_LABELS` gets its two names, and it derives them from the projection rather
## than restating them.
const AXIS_X := 0
const AXIS_Y := 1

## The two tile DIAGONALS (#98, 2026-09-22). `AXIS_D1` steps (+1, +1), `AXIS_D2` steps (+1, -1).
##
## ⚠️ **APPENDED, AND THAT IS THE FORMAT DECISION.** `axis` is an int in a saved `map.json` and
## every map written before today holds 0 or 1. Adding 2 and 3 on the end leaves all of them
## reading back as the wall they were; inserting would rotate them silently, which is `enum Type`'s
## trap one row up in `FormatGuard`.
const AXIS_D1 := 2
const AXIS_D2 := 3

## The sim facing for a wall lying along each axis. **A wall faces ACROSS its own length**, which
## is what makes this table look wrong and be right — the game's original has the measurement.
##
## ⚠️ **FOUR ENTRIES SINCE 2026-09-22.** The two new ones are sprite 2 (W) and sprite 0 (S) after
## `Iso.sim_facing_to_sprite`, which are two of the four FLAT frames — the diagonal bakes. They are
## told apart by ASPECT, not lean: the game's header measures S/N at 412x166 and W/E at 64x336.
##
## Unused here on purpose: see the class comment.
const FACING_FOR_AXIS := [6, 0, 5, 7]


## Whether `axis` is one of the two tile diagonals.
static func is_diagonal(axis: int) -> bool:
	return axis == AXIS_D1 or axis == AXIS_D2


## How far a piece `length` axis-tiles long reaches along a DIAGONAL, in tiles.
##
## `floor(length / sqrt(2))` as exact integers — the largest `k` with `2k² <= length²`. 3 -> 2,
## 6 -> 4, 9 -> 6. A diagonal tile step is 2.83 m against an axis step of 2.0, so a piece sized in
## axis tiles covers 41% fewer of them laid corner to corner. **Verbatim from the game's
## `wall_plan.gd`** — see the class comment on why it is here and why nothing checks it for you.
static func diagonal_step(length: int) -> int:
	var k := 0
	while 2 * (k + 1) * (k + 1) <= length * length:
		k += 1
	return maxi(1, k)
