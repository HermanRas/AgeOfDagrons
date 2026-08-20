# BUGS.md

Playtest findings from the project owner, newest batch first. One line per item,
struck through when fixed with the commit that did it.

An item here is the owner's word on the behaviour they want — where that reverses
an earlier deliberate decision, the reversal is noted rather than argued.

---

## 2026-08-20 — first AI playtest

The AI gathered, built and raised a house, a tower and several other buildings.
These are what the owner saw while watching it.

### View / rendering

- [x] **Villagers face the wrong way when idle-walking north-east.** The sim's
      `facing` is a maths octant in tile space (0 = +x, anticlockwise);
      `AtlasEntry.FACINGS` is a sprite table starting at S and running the other
      way. `GameView` passed the sim's number straight in, drawing the mirror of
      the right sprite — 45° out walking south, **135° out walking north-east**,
      which is why NE is what got noticed. Both ends were pinned by their own
      tests; nothing tested that they agreed. Fixed with `Iso.sim_facing_to_sprite`
      plus a test that walks all eight directions through both conventions.
- [x] **Villagers randomly teleport from the outer edges of the screen.** A unit
      stepping into the sort band in front of a building gains
      `_ADJACENT_TO_BUILDING_BONUS` (100,000 px) on the position it *sorts* at,
      and `draw_offset` cancels it — but the position is interpolated and the
      offset is not, so for one window they did not cancel. Measured by the new
      test: drawn at y = **−99,520** where it should be y = 384. Fixed by snapping
      instead of gliding on the tick the offset changes.

### Input / HUD

- [x] **`CTRL+1`..`5` with nothing selected does not clear the group.** It was
      refused in two places, both deliberately. Now clears. **Watch for:** the
      same path serves mobile's double-tap on a group slot, so an accidental
      empty double-tap now wipes a group. Gate it at the callers if that bites.
- [x] **Clicking the minimap does not move the camera.** It was implemented all
      along — the placeholder chat/trade/tech-tree/settings buttons are a
      `PRESET_FULL_RECT` grid added *over* the minimap, so Godot hit-tested them
      first and they swallowed every tap. Double-tap-to-centre was dead too.
- [x] **Tapping the minimap with units selected issues a move command** (PLAN.md
      3.7). Selection decides: something movable selected → order; nothing
      selected → camera. The camera deliberately does not follow the order.

### Simulation

- [x] **A villager killed in mid-stride kept walking to its destination.** Death
      marked the unit but never cancelled the ORDER, and `MovementSystem` drives
      anything with a waypoint left — it did not ask whether the walker was alive,
      where combat, animation and separation all do. Measured by the new test:
      the corpse covered ~10 tiles after dying. Fixed at the root (`DeathSystem`
      calls `stop()` on a fresh death) plus an `alive` guard in `MovementSystem`,
      which is needed because Movement runs at slot 9, between the kill at 6 and
      the cleanup at 12. The same leftover task would have had a corpse gathering
      and building, so `GatherSystem`, `BuildSystem` and `TaskSystem` got the
      guard too — a unit destroyed by a *command* is already dead when those run.
- [x] **A unit whose target dies re-targets**: 5×5 box, units before buildings,
      ties by distance then lowest id. Gaia excluded.
      **Note:** this reverses a deliberate decision — PLAN.md 4.12 had
      `CombatSystem` explicitly *not* re-target, and `AISystem`'s standing order 3
      exists to paper over it for the AI. That standing order should be re-read
      now to see what it still needs to do.

---

## Open from the AI-vs-AI match run (not owner-reported)

Found by `dev_preview/preview_ai_match.tscn` on seed 3, forest, 12,000 ticks.
See the run log in that scene's output for the exact lines.

- [x] **The preview never quit** — `_ready()` returned into an idle headless main
      loop that Godot spins at max FPS, so the process kept burning a core long
      after printing its report. Fixed with `get_tree().quit()`.
- [x] **"could not be issued" named six different failures with one word.** The AI
      now records *why* each step failed, and every log line carries its tick.
- [ ] **`MAX_PLACEMENT_RADIUS` 26 → 14 blocks 6×6 placements.** p1 never built its
      field: `no legal 6x6 spot within 14 tiles of (48,23)`. The cut bought the
      tick budget; it needs to buy it some other way.
- [ ] **A build step gives up when short of resources.** p2 abandoned its barracks
      73 wood short of the 175 it cost, never built one, and died holding 950 wood
      and 1,190 food. A person waits for the wood; the timeout should not count
      affordability. **This is now the single biggest thing between the two AIs** —
      p1 won 8,282 to nothing largely because p2 never fielded a soldier.

- [ ] **Placement can choose legal-but-unreachable ground.** p1's watch tower at
      (46,13) reported `0 builder(s), NO ROUTE` for the entire match — the ring
      scan asks `can_place_building()` (are the tiles free) and never asks whether
      a villager can get there, so on a forest map it picks clearings walled in by
      trees. Distinct from entombment, and the remaining reason a foundation can
      sit at 0%.
- [x] **A placed foundation can sit at 0% forever** — and it was neither suspect.
      **Units are entombed by their own foundations.** `can_place_building()` asks
      the MAP whether the footprint is free, and units are not written into map
      occupancy, so a building goes up on top of them. `AStarGrid2D` will no more
      plan a route *out of* a solid cell than into one, so every path the unit
      asked for came back empty, `set_path([])` retired the task, and it stood
      there for the rest of the match. The diagnostic read
      `barracks at (49,25), 0 builder(s), NO ROUTE from (49,27)` — a tile squarely
      inside the 6×6. **Not an AI bug:** a player who drops a house on their own
      villagers seals them in exactly the same way. Fixed by stepping units aside
      in `SimWorld.spawn_building`, and it took two more fixes to land:
      - **`find_path()` conflated "nowhere to go" with "you are already there",**
        both returning an empty array that `set_path()` turns into `stop()` — so
        a unit standing on the tile its new order wanted was retired instead of
        getting on with the job. Its own header said empty meant the former.
        Split with `goal_for()` + `SimUnit.arrive()`.
      - **The first eviction invented a worse bug.** `find_free_adjacent` sweeps
        the rect's *top edge* first (it answers a different question — where to
        put a freshly trained unit), so a villager at a house's bottom-right
        corner was thrown clear across to the top-left, onto a tile that was
        passable but walled in by forest. It could never path again: 196 empty
        route requests in 1,000 ticks were all that one villager. Replaced with
        `_step_aside_tile`, nearest to where the unit already stood — which is
        connected to the map for the simplest reason, it just walked there.

**Result: the AI-vs-AI match now reaches a conclusion.** Seed 3, forest:
`MATCH OVER on tick 8282, winner player 1` (13.8 minutes of game time, 47.5 s of
wall clock). p1 completed its barracks, trained its swordsmen at t2770, and razed
p2 from 8 buildings to 0. The regression test works.
- [x] **Match wall-clock varies 4×** (41.3 s vs 161.0 s for the same seed). Not a
      regression: the test suite swung the same way on the same machine (34 s to
      110 s across four runs of identical code), so it is load on the workstation,
      not the sim. `test_tick_cost` is the number to trust — it reports 6.44
      ms/tick for a 2-player map with two AIs, of which `ai_system` is 2.15 ms.
