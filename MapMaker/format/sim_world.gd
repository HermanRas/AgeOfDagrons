## ⚠️ **NOT THE GAME'S `SimWorld`. A ONE-CONSTANT STAND-IN, AND THE ONLY FILE IN `format/`
## THAT IS NOT A VERBATIM COPY.**
##
## `format/iso.gd` IS verbatim, and one line of it reads `SimWorld.SUBTILE`
## (`Iso.from_sim_pos`). That is the whole dependency. The game's real `sim_world.gd` is
## ~1,500 lines of spawning, systems and pathfinding that this tool has no use for and could
## not carry, so the choice was between copying `iso.gd` verbatim plus this shim, or editing
## `iso.gd` to drop one function.
##
## **The shim wins because it keeps `iso.gd` HASHABLE.** An edited copy can never be checked
## against its original — the check would fail by design and therefore be turned off — and
## `iso.gd` is the file that decides where a tile appears on screen. Getting that wrong by a
## fraction is 16.2's whole risk surface.
##
## ## HOW THIS FILE IS KEPT HONEST, SINCE IT CANNOT BE HASHED
##
## `FormatGuard` checks it by **declaration**: it reads the game's `sim_world.gd` as text,
## extracts the `const SUBTILE := ...` line, and compares it to the constant below. So the
## day somebody changes the sub-tile resolution, this tool says so and refuses to save,
## exactly as a changed hash would. That is a narrower promise than a hash — it says nothing
## about the rest of `SimWorld` — and it is the right one, because one constant is the entire
## surface `format/` touches.
##
## ⚠️ **DO NOT GROW THIS FILE.** If something here starts needing more of `SimWorld` than a
## constant, that is a signal the tool is reaching into the simulation, which is what
## PLAN.md §16 decision 2 exists to prevent. Raise it rather than adding a second stub.
class_name SimWorld
extends RefCounted

## Sub-tile resolution: how many units of `SimEntity.pos` make one tile.
##
## **MUST MATCH the game's `src/sim/sim_world.gd`.** Checked at startup by declaration, not
## by hash — see the class comment.
const SUBTILE := 256
