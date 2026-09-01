# maps/

Authored maps — the MapMaker's output (`PLAN.md` Phase 16), and the authored source for anything
the game ships as a named map rather than generating.

**Empty until 16.2**, which is the row that first writes this format and then opens the result in
the game. This file exists so the folder survives a clone, and so the next reader knows which of
the four map directories this one is:

| | |
|---|---|
| **`./maps/`** (here, in git) | authored maps. Written by the MapMaker, read by the game when it is running from the editor |
| **`user://content/maps/`** | where the game reads **installed** maps on a device |
| **`user://maps/`** | the **player's** own saved maps, from the pause menu (`PLAN.md` 2.4c). Kept separate so installing content can never overwrite a save, and uninstalling it can never delete one |
| ~~`game/maps/`~~ | **does not exist and must not.** Anything under `game/` is Godot's `res://` — read-only once exported, and baked into the APK |

The file format is 2.4c's (`PLAN.md` §11.3): the map's own content is authoritative and the
generator seed beside it is provenance only, because the same seed through a changed generator
produces a different map.
