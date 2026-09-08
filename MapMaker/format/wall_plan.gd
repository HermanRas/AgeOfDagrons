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
## ⚠️ **DO NOT GROW THIS FILE.** `plan()`, `footprint_for()` and `lengths_of()` belong to the
## sim. If something here starts wanting them, raise it rather than adding a fourth stub.
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

## The sim facing for a wall lying along each axis. **A wall faces ACROSS its own length**, which
## is what makes this table look wrong and be right — the game's original has the measurement.
##
## Unused here on purpose: see the class comment.
const FACING_FOR_AXIS := [6, 0]
