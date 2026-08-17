# AOD — Status

**As of 2026-08-17.** High-level only; [PLAN.md](PLAN.md) is the detail and the authority.

---

## Where the project is

**It is a game.** One player on a phone can start a match, gather four resources, build, train,
fight, and win or lose. 777 headless tests pass. The MVP definition was met and then overtaken —
combat, fog of war, ages, a population cap and a win condition have all landed since.

**What it is not yet:** there is no opponent that acts. The win condition works, but nothing can
beat you except a debug command aimed at your own town centre. That is the gap the next batch
closes.

```
Foundation ####################  done      engine, seam, sim, net, tests, bake pipeline
Economy    ####################  done      gather, build, train, drop-off, farms
Combat     ################----  mostly    fights and kills; no siege pack, wolf, projectiles
Presentation ##################-  mostly    HUD, minimap, fog, ages, control groups
Opponent   ----------------------  none      no AI, no second device
Content    ######--------------  early     6 of 23 buildings, 6 of 22 units baked
```

---

## Done

| Area | State |
|---|---|
| **Engine & platform** | Godot 4.7.1, Compatibility renderer, landscape. Deployed and measured on a real phone (HONOR LNA-NX1, Mali-G610): 60 fps with 200 units and a settlement, sim tick 0.31–1.54 ms against a 5 ms budget |
| **Architecture** | Client–server even in solo. The sim is plain GDScript with no Node types, so the whole simulation tests headless — which is why there are 777 tests rather than a handful of integration checks |
| **Economy** | Four resources, size-classed nodes, carry caps, drop-off, gather slots, inexhaustible fields with an age-scaled yield, population cap **enforced** |
| **Combat** | Units fight, chase, kill, leave corpses. Buildings fall to rubble and free their ground |
| **Win conditions** | Last Man Standing works end to end on the test map, with a result screen. Trophy and King of the Hill are declared and deliberately inert |
| **Fog of war** | Per-player vision, and the snapshot is filtered **server-side** — an enemy unit you cannot see is not sent to your client at all |
| **Interface** | Selection panel, resource HUD, minimap with fog, control groups, age badge, pause, toasts, drag-to-place buildings, box select, idle-villager walk |
| **Art pipeline** | `isobake` (its own repo) renders 0 A.D.'s 3D actors to isometric sprite sheets. Proven on terrain, trees, ore, animals, buildings, six military units, a 960-frame villager and the dragon |

---

## Not done, in the order it matters

1. **Map generator** — the owner is building it in `game_map_gen/`. Reviewed; eight changes needed before the game can use it, the biggest being that map size currently grows the *side* with player count rather than the *area*, which would make an 8-player map 64× the area of a 2-player one.
2. **Skirmish settings screen** — map source, seed, preview, colours, players, AI, win condition. Built as the multiplayer lobby from the start, since the two differ only in what fills a player slot.
3. **PlayTest AI** — a deliberately dumb scripted opponent. Cheap, and it buys an automated full-match regression test that ends in a real victory.
4. **LAN multiplayer, two devices** — the transport exists and has never met a second peer. ~21–37 h, ordered so a two-device match you can see arrives at the halfway point. Most of it needs no phone: two Godot processes on one desktop cover everything but the final bring-up.
5. **Content** — 17 more buildings and 16 more units, which is an art-track question (~70 building bakes) rather than a code one.
6. **Walls** — 24 baked, declared, unbuildable wall pieces. The largest block of finished art the game cannot reach; needs drag placement, segment choice, 8 orientations and gate pass-through.
7. **Then**: ages and tech as a batch, dragons, real AI difficulty.

---

## The five things worth knowing

**The sim/view split is load-bearing and it has paid for itself.** Nothing in `src/sim/` may touch
a Godot node. That single rule is why the entire simulation is testable with no window, and why
the 777 tests run in 15 seconds.

**The architecture has been multiplayer-shaped since day one, and that was only half-validated.**
Every order already goes through the network path in solo play. But solo cannot exercise a *second
peer*: the snapshot broadcast sent every player's data to everybody for months, harmlessly,
because all players saw an identical world — and became a serious leak the moment fog filtering
existed. Latent breakage accumulates in that layer silently, which is the argument for doing the
multiplayer work before stacking more features on it.

**Balance is now measured against Age of Empires, not invented.** The field yield was 16× a berry
bush per farmer at age 4; AoE keeps every food source within a third of every other, and what
separates them is amount, distance and safety — never a multiplier on the worker. Fixing the ratio
immediately exposed a real bug where advancing two ages made farming 25% *slower*.

**Art is the long pole, and it is off the critical path by design.** Every asset sits behind an ID
that resolves to a real atlas or a procedural placeholder, so no gameplay phase ever waits for a
bake. One prerequisite is outstanding: player colour is currently baked *into* each atlas, and with
colour the only thing distinguishing players, that has to become a shader before the ~22 military
bakes happen — or they are all invalidated.

**There is no CI.** Every check — the test suite, the sim-boundary grep, the licence audit — is a
command someone runs by hand. The licence audit has already drifted once and reported 89 problems.

---

## Verifying it yourself

```
godot --headless --path game res://tests/run_tests.tscn      # 777 tests, exit code is the answer
godot --path game res://dev_preview/preview_match.tscn       # drives a real match, 16 screenshots
godot --path game res://dev_preview/preview_victory.tscn     # fights the map to a win (--defeat for the other branch)
```
