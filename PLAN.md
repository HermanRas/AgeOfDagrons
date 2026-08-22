# AOD — Implementation & Programming Plan

Companion to [IDEA.md](IDEA.md) (what we're building) and [UI_Design.md](UI_Design.md) (how it
looks). This document is **how we build it**: architecture, objects, scenes, and phase order.

Missing art is requested per need in [asset_request.md](asset_request.md).

> **Compacted 2026-08-17.** This file had grown to ~1900 lines, most of it the history of how
> each finished item was built — narratives that also live in the code comments and in git. The
> full pre-compaction text is commit **`b904b76`** (`git show b904b76:PLAN.md`); nothing was
> dropped that was not either recorded elsewhere or already settled. What survives here is
> **decisions, specifications and open questions**. Rule of thumb going forward: a DONE row
> says what exists, where it lives, and the one thing about it that is not obvious — the
> reasoning belongs in the file it describes.

---

## 0. How to read this document

- Phases tagged **`[MVP]`** were implemented first. **MVP is complete** (§10).
- Untagged items are full-scope scaffolding — they exist so we don't design ourselves into a corner.
- Phase numbers ≥1 mirror [IDEA.md](IDEA.md). Phase 0.x is engineering groundwork with no IDEA.md counterpart.
- §12 governs what gets built next.

---

## 1. Locked decisions

| Decision | Choice |
|---|---|
| Engine | **Godot 4.7.1-stable** (`Godot_v4.7.1-stable_win64`) |
| Language | **GDScript** |
| Renderer | **Compatibility** (`gl_compatibility`), 2D — *not* Mobile. Vulkan-Mobile crashes cluster on older Mali/MediaTek/Adreno parts, and the Mobile renderer supports **fewer** Android devices ([godot#111729](https://github.com/godotengine/godot/issues/111729)) for no 2D benefit |
| Orientation | Landscape, locked |
| Licence | **Code MIT, art CC-BY-SA 3.0** (§2.3) — [LICENSE](LICENSE) · [LICENSE-ART.md](LICENSE-ART.md) |
| Session model | **Always client–server, even solo** (§1.1) |
| Simulation | Server-authoritative, fixed-tick, headless-capable |
| Sim tick rate | **10 Hz** (100 ms), render interpolated to display rate |
| Map topology | **Square grid**, rendered isometric |
| Civilisations | **One, shared by every player, for v1** — same buildings, units and upgrades; players are told apart by **colour only**. Deferred, not abandoned: civs return after v1 as a re-skin-plus-rename layer over this same roster (§2.7.1, 9.5) |
| Age skins | The civ axis is replaced by the **age** axis: four 0 A.D. civs, oldest-to-newest, are the four ages of our one civilisation (§2.7) |
| Units of measure | Integer sub-tile units, **1 tile = 256 sub-units** |
| Dev environment | **Native Windows** for editor + Android deploy; WSL/Docker for tooling (§1.2) |
| Asset delivery | **Downloadable packs**, not bundled in the APK (§3.2) |

### 1.1 Session model

One code path for single player, campaign, and multiplayer:

```
Single player / campaign:   host binds 127.0.0.1  ->  local client joins own server
Multiplayer (LAN/online):   host binds 0.0.0.0    ->  remote clients join
```

Rules this imposes:

1. **The simulation never touches the view.** It must run with no sprites, camera, or HUD.
2. **The player never mutates game state directly.** Input produces a `Command`, sent to the server (even in-process), validated, applied on a tick boundary.
3. **The client is a renderer plus an input device.**
4. **Solo play is not a special case.** If solo works, the networked path is already exercised.
5. Bit-exact determinism is not required. The sim/view split is.

> Rule 4 is load-bearing and was **only half true until 2.5**: solo exercises the path, but it
> cannot exercise a *second peer*. `Net._broadcast_snapshot()` sent every player's snapshot to
> everybody for months, harmlessly, because all players saw an identical world — and the moment
> fog filtering existed it handed the client the opponent's view of the map. **Latent breakage
> accumulates in the net layer silently.** See §12.1.

### 1.2 Development environment

**Native Windows** for the Godot editor and Android deploys (`adb` from WSL2 needs `usbipd-win`
passthrough and is unreliable). **WSL2 + Docker** for the Python asset pipeline (`tools/`), the
headless server, and running the checks.

> **There is no CI on this repo.** Nothing runs automatically on push. Every check here — the
> headless suite, the `sim/` boundary check, the licence audit — is a **local command run by
> hand**. Where this document says a check "fails", read "fails when you run it". They are all
> shaped as single commands with meaningful exit codes so adding CI is trivial, but it has not
> been done. Do not write "enforced by CI" anywhere until it is true.

Source lives on the Windows filesystem; containers bind-mount it. Never use Docker volumes for
source.

### 1.3 Machine setup

**Working root for anything outside Google sync:** `C:\Users\herman.ras\Downloads\AOD_game\`
holding `art_source\` (0 A.D. checkout), `art_work\`, `packs\`, `tools_env\`.

The Godot project still sits in the Drive folder (`AOD_Mobile\game\`) and **should move to a
local path** — a git repo inside Drive sync is what corrupted the last `.git`.

| Requirement | Version / notes |
|---|---|
| **Godot** | `4.7.1-stable_win64` ✅ |
| **Android export** | Godot's build template + JDK 17 + Android SDK. **`export_presets.cfg` is tracked** (it holds no secrets) so `permissions/internet=true` ships for everyone — it must stay `true` or `Net.host_solo()` fails silently on-device even for loopback (Android requires INTERNET for any socket) |
| **Python** | 3.11+ with `Pillow` + `numpy`, in a venv made from **Blender's own** Python (`tools_env\venv`) — nothing system-wide, and the venv cannot drift off the pinned Blender ✅ |
| **Blender** | **4.5.12 LTS — hard pin, do not use 5.x.** COLLADA import was *removed* in 5.0 and 0 A.D.'s meshes are `.dae`. Installed as a portable extract, deliberately not Steam/MS Store, so no auto-update can break the art track ✅ |
| **`isobake`** | [`HermanRas/blender_3d_to_2d_isobake`](https://github.com/HermanRas/blender_3d_to_2d_isobake) (GPL-2.0-or-later) — the render/bake/verify pipeline (§2.2). `pip install -e` into the venv ✅ |
| **Blender addon** | [`StanleySweet/blender_pyrogenesis_importer`](https://github.com/StanleySweet/blender_pyrogenesis_importer) (GPL-2.0) pinned at `b31b5c4`. Imports actor XML (mesh + props + textures) but **not animations** — isobake attaches those, and applies two Blender-4.5 shims at load time rather than forking ✅ |
| **0 A.D. art** | `git clone --depth 1` from gitea into `art_source\`. **Shallow matters** (full history ~8.3 GB) and **`git-lfs` is required** or the clone succeeds and the checkout fails. Scope with `git config lfs.fetchinclude "binaries/data/mods/public/art/**"` ✅ ~11 GB |
| **Test framework** | Custom `TestCase`/`run_tests.tscn` harness, kept instead of GdUnit4 — already covers headless tests, `state_hash()`, replays and the boundary check with zero dependencies ✅ |

Notes on the checkout: art is **in the main repo** at `binaries/data/mods/public/art/`; **clone
the repo, do not mine the installer** (releases ship compiled `.pmd`/`.psa`/`.dds` with no
maintained Blender importer); GitHub `0ad/0ad` is archived — gitea is upstream.

**Version policy: every version above is pinned.** Upgrading Godot or Blender is a deliberate
task at a phase boundary with the suite green before and after — never an "update available"
click.

---

## 2. Art & assets

### 2.1 The asset seam

**Every visual and audio asset sits behind a stable ID. No filename appears in gameplay code.**

```gdscript
var vis := GameDataRegistry.atlas_for(&"vis.villager")
AudioManager.play_sfx(&"villager.chop")
```

`data/visuals.json` and `data/audio.json` are the only files mapping an ID to a path. Each ID
resolves to a real atlas **or** a procedural placeholder (§2.4), so gameplay never blocks on art.
`atlas_for()` is **total** — atlas, else declared placeholder, else a loud magenta unknown, never
null.

### 2.2 Sources

| Domain | Source | Licence |
|---|---|---|
| Units, buildings, terrain, props, dragon | **0 A.D.** (`play0ad.com`) | CC-BY-SA 3.0 |
| Audio (starting point) | **0 A.D.** | CC-BY-SA 3.0 |
| UI chrome, fonts | **itch.io packs** in `assets/UI_Sprites/` — `UI_dragon-huds`, `uı-fonts`, `Free_Medieval_Fantasy_UI_Pack` | Per-pack; record in `LICENCES.md` |

0 A.D. is a 3D game. Pipeline shape: **actor XML → Blender (pyrogenesis importer) → attach
animation `.dae` → render N × 45° orthographic → trim/pack → atlas.** Terrain comes from the same
source, so palette and style stay coherent and attribution stays one entry. **The GUI stays the
dragon theme** and does not come from 0 A.D.

Two things `isobake` gets right that are unfixable-in-place later:

- **Camera elevation derived from tile size**, `asin(tile_h / tile_w)` = exactly **30°** for 64×32. The 35.264° isometric tutorials use is the cube body-diagonal angle and would make a 64px tile 37px tall.
- **One global `pixels_per_metre`** (22.627), never fit-to-frame. Framing each model to fill its canvas silently makes a villager and a town centre the same size.

0 A.D. specifics: their COLLADA declares metres but the conversion is tile-to-tile via their own
`TERRAIN_TILE_SIZE = 4`; base-texture alpha means transparency for `basic_trans_*` foliage but a
**faction-tint mask** for `player_*` units, and confusing the two makes a quarter of every unit
see-through.

Any additional source needs an explicit note from the project owner and must be recorded in
`LICENCES.md` and `CREDITS.md` in the same change.

### 2.3 Attribution obligations

0 A.D.'s licences require **three specific things, verbatim**:

1. A link to `http://creativecommons.org/licenses/by-sa/3.0/`
2. The original author named as **"Wildfire Games"**
3. A link to `http://www.wildfiregames.com/`

Plus: **derived sprite sheets are themselves CC-BY-SA 3.0** (only the art is copyleft — the
Godot code is MIT); `CREDITS.md` in-repo and on a Credits screen (1.4); `assets/LICENCES.md` for
per-asset provenance, checked by `tools/licence_audit.py` (exits non-zero; run by hand, §1.2);
each downloadable pack carries its own `LICENCE`/`CREDITS`. Note some of 0 A.D.'s `textures/`
derive from CGTextures under permission granted to *that* project — check before leaning on raw
texture files rather than rendered output.

### 2.4 Placeholder art

Procedurally generated: isometric diamonds for terrain, capsules with a facing marker for units,
sized boxes for buildings — drawn at runtime from `visuals.json`, no image files. Sizes are
authored in **metres**, so a placeholder occupies the space its real sprite will.

Every gameplay phase is therefore art-independent, and the seam is load-bearing from day one.
Placeholders stay in the build permanently as the no-pack-mounted fallback (§3.2).

> Measured at 2.6 and **backwards from the prediction**: 200 units cost **681** draw calls on
> placeholders and **14** on real atlases. Placeholders are the expensive path (polygon + outline
> + marker, none of it batching); real sprites all sample one page. The draw-call risk sits with
> the fallback, not with real art.

### 2.5 Normalised vocabulary

One villager, one gender. One civilisation, shared by every player. IDs read
`unit.villager`, `building.town_center`, `res.tree`. The **full v1 roster** is §9.2.

| Anim ID | Used when | MVP |
|---|---|---|
| `idle` | Task.IDLE | ✓ |
| `walk` | moving, carrying nothing | ✓ |
| `walk_carry_wood` / `_gold` / `_food` | moving, by `carry_kind` | ✓ |
| `walk_carry_stone` | | |
| `work_chop` | gathering wood | ✓ |
| `work_mine` | gathering gold or stone | ✓ |
| `work_hunt` | gathering from a carcass | ✓ |
| `work_build` | building or repairing | ✓ |
| `work_forage` / `work_farm` / `work_fish` / `work_herd` | later food sources | |
| `attack` | combat | |
| `die` / `decay` | death, corpse pre-removal | ✓ |

`EntityView.play_anim()` tries `walk_carry_<kind>` and falls back to `walk`, so carry variants
are always optional.

**5 stored directions mirrored to 8** halves art cost, and is decided **per recipe, not
globally**. Two preconditions: the key light must lie in the camera's vertical plane, and the
subject must be laterally symmetric. The villager holds an axe in `work_chop`, so `villager.toml`
renders all 8 — mirroring is per recipe, so `idle` and `walk` render at 8 too even though they
would be mirror-safe alone. **MVP villager budget:** 11 anims × ~15 frames × 8 dirs ≈ 1320.

### 2.6 Practical handling

- Raw source art lives on a **local, non-synced** path, pointed at by config, never a committed absolute path.
- **Baked atlases are not committed.** They are build output, reproducible from the committed recipes plus `isobake`, and they reach players through the pack (§3.2). `tools/stage_atlases.py` copies the atlas JSON and its declared pages — and only those, not `frames/` or `verify_*` sheets — into the gitignored `game/assets/atlases/`. Re-run after any rebake.
- Only placeholders ship inside the APK, so the export preset must **exclude `assets/atlases/`** or they ship twice.
- `.gdignore` in any raw-art folder under the project.

### 2.7 One civilisation, four age skins

**Locked (§1): v1 ships a single civilisation.** Colour is the only thing distinguishing players.
This is **deferred, not abandoned** — the roster is joined to its art through a map file, so a
civ is a **re-skin plus a rename** over the identical roster, which is why 9.5 is deferred rather
than dropped and why `factions.json` stays.

What takes the civ axis' place is the **age** axis.
[Age & Unit Planning.md](<Age & Unit Planning.md>) is the source of truth for roster content:

| Age | Name | Primary 0 A.D. civ | Also borrows from | Reads as |
|---|---|---|---|---|
| I | Age of Ash | Britons (`brit`) | Celts, Mauryas | timber, thatch, wicker |
| II | Age of Embers | Gauls (`gaul`) | Celts, Germans, Carthaginians | fortified timber |
| III | Age of Flame | Persians (`pers` → `achaemenids`) + Iberians | Athenians, Han, Carthaginians, Romans | cut stone |
| IV | Age of Dragons | Romans (`rome`) | Macedonians, Ptolemies, Han | dressed stone and brick |

**Buildings carry the age. Units do not.** A unit uses one hand-picked actor in all four ages;
only the *settlement* modernises. This is a **readability** decision, not a saving: a player must
recognise a spearman instantly at 44 px mid-fight, so a unit's silhouette must be the one thing
that never changes. Re-skinning units per age would mean learning the roster four times, and an
age-3 spearman fighting an age-2 one would look like two unit types. Buildings are stationary,
identified at leisure, and are what the player watches accumulate. (It also drops unit art from
~28 bakes to ~22, but that is the side effect.)

**The unit roster is deliberately mixed-civ**, chosen per unit for how each one *reads* —
Carthaginian archers, a Han crossbowman, a Mauryan scout, an Achaemenid horse archer, an Athenian
healer, a German champion. Civ consistency is the right default for **architecture** and the
wrong one for everything else (§13.2 item 2). A 2026-08-14 decision briefly made every unit
Celtic; retracted 2026-08-15. The lesson worth keeping: **a clarifying question can only catch a
misunderstanding if at least one of its options contradicts it** — the question was about
*voices*, the answer was read as being about *models*, and the follow-up offered two options both
phrased in terms of models.

Three consequences:

1. **Art volume moves, it does not vanish.** A building has up to four visuals, so §9.2's roster is roughly **70 building bakes** — no cheaper than four factions. The saving lands on units.
2. **Age is a visual dimension the seam did not have.** `visuals.json` keys a building by phase; it must also key by age. `SimPlayer.age` already rides `player_state`, so the view resolves this with **no new sim state and no new command**. A standing building **re-skins in place** as its owner advances (§13.2 item 10), which is why its footprint is locked at placement to the maximum across all four skins (§9.2).
3. **Player colour is baked into the atlas, and that blocks.** `isobake`'s zeroad adapter multiplies 0 A.D.'s player-colour mask in at bake time — one atlas is one colour. With colour the *only* difference between players, eight players cannot mean eight bakes of every unit. Fix: bake untinted, emit the mask (it is the source alpha), tint in a `canvas_item` shader. Tracked as **A.6, prerequisite not polish**.

#### 2.7.1 Age and faction are one mechanism, so build one

Faction is a **second skin dimension on the same lookup**, arriving later — which is exactly when
an age-only special case becomes expensive, because every call site has been written against it.
Resolve both through one key from the start:

```
skin = (faction, age)        # faction.default × age 1-4 for all of v1
```

1. **`atlas_for()` resolves a skin, not a bare visual ID.** The map is **dense** — four entries per building, always — while **bakes are shared**: two ages that look the same point at the same atlas. That is the lever on the ~70 figure. A missing entry falls back to `faction.default` as a **safety net, not the mechanism**, which is what lets a future civ ship partially.
2. **Display names are data, not `units.json` literals.** A civ renames the roster as much as it re-skins it, and this is the item that has to work with localisation later.

**Nothing in the sim changes for either dimension.** Costs and stats staying shared is what keeps
a re-skin civ free of balance work; the day a civ changes a *number*, `units.json` needs a
per-faction override layer and per-civ balance comes with it. That is 9.5's expensive half.

---

## 3. Target platforms & delivery

| Target | Priority | Notes |
|---|---|---|
| Android (mid-range) | **Primary** | The design constraint — §3.0 |
| Windows | Secondary | Dev/test, usual host |
| Linux | Secondary | Dedicated-host target |
| iOS | Later | Architecture compatible; not in MVP |

### 3.0 Reference device (measured, 0.1)

HONOR LNA-NX1 · Android 16 (SDK 36) · MediaTek MT6858 · **ARM Mali-G610 MC2**, OpenGL ES 3.2 ·
`arm64-v8a` **only** · 2600 × 1200, 520 dpi, 60 Hz · `gl_compatibility` confirmed active.

1. **MediaTek + Mali is exactly the hardware the Compatibility decision was made for** — known Godot Vulkan crashes cluster there. The renderer choice is empirically validated, not argued.
2. **2600 × 1200 is 2.17:1**, so with `stretch/aspect=expand` the design viewport is **1404 × 648**. UI is authored against a **648 px tall** canvas with variable width: generous horizontal room, tight vertically.

### 3.1 Performance budget

| Metric | Target |
|---|---|
| Frame time | 16.6 ms (60 fps); hard floor 33 ms (30 fps) |
| Sim tick cost | < 5 ms per 100 ms tick |
| Live units | 50 (MVP) → 200 per player, 8 players (full scope) |
| Draw calls | < 200 |
| Texture memory | < 256 MB |
| **APK size** | **< 300 MB** — code + placeholders only (an empty project exports to 54 MB) |
| Asset pack | art ~150–400 MB, audio ~50–100 MB, downloaded |
| **Snapshot wire size** | **< 64 KB/tick.** Measured 2026-08-17 on the real debug map: **12,092 bytes, 4,104 of it fog** = 118 KB/s per player. Pinned by `test_snapshot_system.gd` |

Checked by `StressTest.tscn` from early on, and it must run **on the phone**.

### 3.2 Asset delivery — downloadable packs

Art and audio ship as Godot `.pck` files mounted via `ProjectSettings.load_resource_pack()`.

```
APK  (< 60 MB)    = code + data JSON + procedural placeholders + fonts
pack_art_v1.pck   = atlases, terrain
pack_audio_v1.pck = sfx, music
pack_theme_*.pck  = optional community themes (later)
```

Primary source is the project website `https://aod.dragoon.co.za/` (website source in `web/`):

| URL | What |
|---|---|
| `/downloads/packs.json` | **Pack manifest — the client reads this.** Stable, unversioned URL; versions live *inside* it |
| `/downloads/pack_art_v1.pck` | Art pack, fetched by `AssetPacks` |
| `/downloads/AoD_v*.apk` / `.exe` | Game builds — human-facing, not fetched |

> **Pack versions are independent of game versions** — hence `pack_art_v1.pck`, not
> `AoD_v0.0.4.pck`. Naming it after the build would force a full art re-download on every code
> release. The manifest ties a game build to the pack versions it accepts, and carries a URL
> *list* per pack so adding a mirror is a manifest edit with no client change.

**Flow:** boot → check local versions against the manifest → download missing → verify checksum →
`load_resource_pack()` → assets resolve through the seam. If a pack is absent or fails
verification, **the game runs on placeholders** rather than failing.

---

## 4. Repository & project layout

```
AOD_Mobile/
  IDEA.md  PLAN.md  UI_Design.md  CREDITS.md  status_update.md
  assets/UI_Sprites/  assets/Icons/  assets/insperation_pictures/   (+ .gdignore)
  web/                        # project website source
  game_map_gen/               # map generator prototype (2.4b), standalone Godot project
  tools/                      # OFFLINE pipeline - Python, never shipped
    isobake.toml              # camera config; MUST match Iso.TILE_SIZE
    recipes/                  # AOD content: which 0 A.D. actor is our what
    build_packs.py            # atlases -> .pck + manifest + checksums
    licence_audit.py          # every asset must declare a licence
    stage_atlases.py
  game/                       # THE GODOT PROJECT
    project.godot
    data/                     # units, buildings, resources, techs, ages, factions,
                              # colours, visuals (SEAM), audio (SEAM)
    assets/                   # placeholders, ui, fonts, LICENCES.md, atlases/ (gitignored)
    src/
      sim/                    # NO Godot node types, NO rendering
        entities/ systems/ commands/ pathing/
      data/  net/  view/  autoload/
    scenes/                   # boot/ menu/ game/ ui/ ui_builder/
    dev_preview/              # screenshot-driven checks against the REAL scenes
    tests/                    # headless - see §7.7
      run_tests.tscn/.gd      # the one test command
      sim/ net/ view/ replays/
```

**The `game/src/sim/` boundary is the most important rule in this codebase.** Nothing in `sim/`
may `extends Node`, load a texture, read input, or reference `view/`. `test_sim_boundary.gd`
greps for violations inside the test suite.

Rendering, baking and verification live in the separate `isobake` repo (§2.2). Recipes stay here
because "0 A.D.'s female citizen is our villager" is a content decision, not a tool feature.

---

## 5. Architecture overview

```
+-----------------------------------------------------------+
|  VIEW (client)   scenes, sprites, camera, HUD, gestures   |
|  reads snapshots                    emits Commands        |
+-----------------------------------------------------------+
             snapshots (down)   |   commands (up)
+-----------------------------------------------------------+
|  NET             SceneMultiplayer / ENetMultiplayerPeer   |
|  host binds 127.0.0.1 (solo) or 0.0.0.0 (multiplayer)     |
+-----------------------------------------------------------+
+-----------------------------------------------------------+
|  SIM (server only, headless-capable, 10 Hz fixed tick)    |
|  SimWorld -> systems -> entities. Plain GDScript classes. |
+-----------------------------------------------------------+
```

### 5.1 One tick, end to end

```
1. Player drags a finger on the map.
2. InputRouter -> MoveCommand(unit_ids, target_tile).
3. Net.submit_command(cmd)  -> rpc_id(1, "_recv_command", cmd.to_dict())
4. [SERVER] validate ownership/legality, queue for tick N+1.
5. [SERVER] SimClock fires tick N+1 -> SimWorld.step(), systems in fixed order (§6.2)
6. [SERVER] SnapshotSystem builds a per-player fog-filtered snapshot, sends it to THAT peer.
7. [CLIENT] EntityViewPool applies it, interpolates over the next 100 ms.
```

Step 6's fog filtering is a **security property**: the server must not send a client entities it
cannot see. Step 6 sends **per peer**, not broadcast — see §1.1.

---

## 6. Core objects

**The code is authoritative.** This section is the map and the invariants, not a signature dump —
an out-of-date API listing is worse than none. Read the file headers; they carry the reasoning.

### 6.1 Autoloads (`src/autoload/`)

| Autoload | Job |
|---|---|
| `GameDataRegistry` (`game_data.gd`) | Loads `data/*.json` into typed `*Def` objects; `atlas_for()` (total, §2.1); `validate()` cross-checks every reference across files and the suite fails on any warning. Entity accessors return **null** for an unknown ID — the opposite of `atlas_for()`, deliberately: a missing sprite has a sensible stand-in, a missing unit definition does not. `colour(index)` **wraps** for the same reason |
| `Net` (`net.gd`) | Transport + RPC boundary. `host_solo()`, `submit_command()`, `_recv_command` (up, reliable), `_recv_snapshot` (down, unreliable_ordered). `host_open()`/`join()` are §12.1 |
| `SimClock` (`sim_clock.gd`) | 10 Hz pump; `advance()` holds the logic separately from `_process` so it runs headless |
| `EventBus` (`event_bus.gd`) | Decouples HUD widgets from whoever receives the snapshot |
| `AssetPacks` | §3.2 |

Three autoloads (`net.gd`, `sim_clock.gd`, `event_bus.gd`) deliberately carry **no `class_name`** —
it would shadow the singleton identifier.

### 6.2 Simulation (`src/sim/`)

`SimWorld` holds `tick`, `map`, `players`, `entities`, `spatial`, plus the match outcome
(`mode`, `match_over`, `winner_id`). `SUBTILE = 256`. `state_hash()` folds in the map, every
entity, and every per-player field that can diverge — including `vision` and the outcome.

`SimMap` keeps **four** parallel packed arrays indexed row-major: `terrain`, `move_cost`,
`occupancy`, `blocking`. Two rules with teeth:

- **Occupancy is for static footprints only** — buildings and resource nodes, never units (they live in `SpatialHash`). Otherwise every step rewrites the grid and a tile a unit merely crossed reads as unpathable.
- **`occupancy` and `blocking` are different questions.** "May something be built here" is not "may a unit walk here" — a field claims its 36 tiles so nothing is built on the crop, and lets villagers walk over it.

`find_free_adjacent()` scans a **fixed** ring order and is asserted against an exact tile, because
two clients spawning production must choose the same one.

Systems run in this fixed order by `SimWorld.step()`:

| System | Responsibility | State |
|---|---|---|
| `CommandSystem` | Validate + apply queued commands; reject anything the sender doesn't own | ✅ |
| `PathSystem` | Solve queued path requests against a per-tick budget | ✅ |
| `TaskSystem` | Per-unit task state machine | ✅ |
| `GatherSystem` / `BuildSystem` / `CombatSystem` | Arrival-time work: gather, build, fight | ✅ |
| `ProductionSystem` | Training queues; a finished order is not popped until it spawns | ✅ |
| `AgeSystem` | Age advancement timers | ✅ |
| `MovementSystem` | Path following, waypoint by waypoint | ✅ |
| `SeparationSystem` | Steering push-apart for overlapping units | ✅ |
| `AnimationSystem` | Sets the `anim` view hint | ✅ |
| `DeathSystem` | hp≤0 → corpse/rubble, free tiles, drop cargo, timers | ✅ |
| `PopulationSystem` | Recount `pop_used`/`pop_cap`; owns the cap rule | ✅ |
| `VisionSystem` | Recompute per-player fog | ✅ |
| `WinConditionSystem` | Evaluate the active mode's victory rule | ✅ |
| `TechSystem` | Research timers, stat modifiers | 9.3 |
| `AISystem` | Drive AI players (emits Commands like any player) | 12.2a |

`SnapshotSystem` is **not** in the list — it mutates nothing and crosses the sim/net boundary, so
`SimHost` calls it after each `step()`.

**Everything after `DeathSystem` recounts rather than adjusts.** Population, vision and the win
condition are all derived from what exists at the end of a tick. An incremental counter has to be
decremented from every path an entity can leave the world by, and one missed path is a permanent
drift with nothing on screen to explain it.

**Commands are the only way state changes.** Every one validates ownership server-side; a
`validate()` that fails drops the command silently, so anything the UI offers must be gated the
same way the command is. Built: move, stop, gather, build, place-building, train,
cancel-production, attack, advance-age, set-control-group, debug-destroy, debug-set-age. Later:
garrison, research, stance, special ability, trade, resign.

`PathService` wraps `AStarGrid2D` with a **per-tick budget** (`MAX_SOLVES_PER_TICK = 12`, measured:
32 → 9.48 ms, 16 → 5.09 ms, 12 → 4.30 ms against the <5 ms tick). Grid updates are incremental by
dirty rect; the one full 64×64 sweep (~12 ms) happens at map-gen time where it hides in load.

### 6.3 View layer (`src/view/`)

`GameView` owns three layers — `TerrainLayer`, the `EntityViewPool`, and `FogOverlay` — and turns
a snapshot into pooled, interpolated `EntityView`s. **It is handed raw bytes, never a `SimMap` or
a `SimPlayer`**: terrain bytes to draw ground, fog bytes to draw fog. That is the shape a
networked client receives, and it keeps the tests free of a world.

`Iso` is **the only place grid↔screen math lives**. Two distinctions that cost real debugging:
`tile_to_world()` is a tile **corner** while the sim stands entities at tile **centres**
(`tile_centre_to_world()`); and `world_to_tile()` **rounds** while `tile_at()` **floors** — the
first un-projects a corner, the second answers "which tile is this point inside".

Picking is **by tile, not sprite bounds** — a 10 m tree's sprite covers six tiles behind it.
Depth sorting moves a footprint's sort point to its **front tile** with `EntityView.draw_offset`
carrying the equal and opposite shift, so the art stays on the centre while the sort is correct.

UI widgets live in `src/view/` alongside it (there is no `src/ui/`): `SelectionPanel`,
`ResourceHUD`, `Minimap`, `ControlGroupsHud`, `AgeBadge`, `IdleVillagerBadge`, `NoticeToast`,
`PauseMenu`, `ResultScreen`, `PlacementGhost`, `SelectionBox`, `ActionFlash`. They read from
`EventBus` or from facts handed in, **never** from the sim, and they are built in `_init()` rather
than `_ready()` so a bare `.new()` is fully wired for a headless test.

---

## 7. Cross-cutting concerns

**7.1 Selection vs commands.** Selection is client-side UI state, never sent — it stays instant
regardless of latency, and a selection in the state hash would desync the moment one player
tapped. Only the resulting `Command`, with explicit `unit_ids`, crosses the wire. Control groups
are the exception: **persisted in `SimPlayer`** via `SetControlGroupCommand` so they survive
reconnect.

**7.2 Snapshots.** Per-player, fog-filtered, `{tick, spawned[], updated[], removed[],
player_state, vision, mode, match_over, winner_id}`. **Not yet a real delta** — everything a
player may see is sent every tick, so the client currently treats *absence* from `updated` as "I
can no longer see that". A true delta against the last acknowledged tick must add an explicit
per-entity "you have lost sight of X" signal, and it must **not** be a list of hidden ids, which
would let a client read enemy unit counts off the wire.

**7.3 Rendering.** `Sprite2D` in a Y-sorted container. If profiling at 200+ units shows Y-sort
dominating, switch to explicit depth keys via `Iso.depth_sort_key()`. Measure before changing.

**7.4 Mobile input.** All gestures funnel through `InputRouter`. Mouse emulation **disabled** —
multi-touch box select needs raw `InputEventScreenTouch`/`Drag`. Touch and mouse are handled
separately, because handling one would work on the phone and not on the desktop the work is done
on. Test on device.

**7.5 Audio.** `AudioManager` exists with a no-op implementation and a stable ID vocabulary, so
gameplay emits `play_sfx(&"villager.chop")` from day one and the pack lands later.

**7.6 Optimisation policy.** GDScript everywhere. Profile on the target Android device. Move a hot
loop to GDExtension only when profiling proves it dominates.

**7.7 Testing.** Five layers; most of the value is in the first.

1. **Headless sim tests.** `src/sim/` is plain GDScript, so it tests with no window and no rendering — the payoff of §1.1. One command, meaningful exit code:
   ```
   godot --headless --path game/ res://tests/run_tests.tscn
   ```
   The runner is a **Node under a real scene**, not a `--script` MainLoop override: a custom MainLoop skips the boot sequence that parents autoloads under the tree root, silently breaking anything needing `get_tree()`.
   Two runner rules that have each caught real breakage: **an empty suite is a FAILURE** (a renamed base script once collapsed discovery to zero while reporting PASS), and **a test that asserted nothing is a FAILURE** (GDScript reports a runtime error by printing and continuing, so an exploded test records no failures). A new `class_name` needs `--import` before the suite can see it.
2. **`state_hash()` regression.** Same config + command log twice, compare hashes. Catches non-determinism and anything the snapshot layer forgets.
3. **Replays.** `MatchConfig` + ordered command log = a few KB reproducing any bug exactly.
4. **`dev_preview/`.** Scripts that drive the *real* scenes and screenshot each step — `preview_match.tscn` (16 shots through a whole session), `preview_victory.tscn` (fights the debug map to a result; `--defeat` for the other branch). A preview that rebuilt any of the game could show a working feature while the game's own was broken.
5. **`StressTest.tscn`** — the only layer needing a real scene, and it must run **on the phone**.

---

## 8. Scene trees

```
Boot.tscn         [MVP]  title card, 2 s or tap -> MainMenu
MainMenu.tscn     [MVP]  PLAY / MULTIPLAYER / SETTINGS / HOW TO / CREDITS / QUIT
Game.tscn         [MVP]  the match - game_scene.gd
  GameView (Node2D)      TerrainLayer, EntityViewPool (Y-sorted), FogOverlay,
                         PlacementGhost, ActionFlash
  CameraRig, InputRouter
  CanvasLayer (backdrop, below the world)
  CanvasLayer (HUD, above): ControlGroupsHud (top-left), age header + pause +
                         IdleVillagerBadge (top-centre), ResourceHUD (top-right),
                         SelectionPanel (bottom-left), Minimap + 4 corner buttons
                         (bottom-right), SelectionBox, NoticeToast, PauseMenu,
                         ResultScreen
Credits.tscn      [MVP]
StressTest.tscn   [MVP]  perf harness
Skirmish.tscn            1.6 - skirmish settings, and the multiplayer lobby
DownloadScreen.tscn      3.2
Settings.tscn            1.5
```

The HUD **must** sit on `CanvasLayer`s or the camera pans it away with the ground. A full-rect
`Control` defaults to `MOUSE_FILTER_STOP` and will swallow every mouse event before the camera
sees it — `mouse_filter = IGNORE` on anything that is not meant to be pressed, **per node**,
since it does not inherit. An invisible display `TextureRect` left on the default once cost three
build buttons (they placed the villager on the ground under the icon instead).

---

## 9. Data schemas

Static data is JSON in `game/data/`, loaded once into typed `*Def` objects (`src/data/`, plain
`RefCounted` so `sim/` may read them). **All numbers are starting values, tuned by playtest.**

```jsonc
// units.json
"unit.villager": {
  "name": "Villager", "visual": "vis.villager",
  "hp": 30, "speed": 200, "los": 4, "domain": "land", "pop_cost": 1,
  "cost": { "food": 50 }, "build_time_ticks": 250,
  "attack": { "damage": 3, "type": "melee", "range": 0, "cooldown_ticks": 20 },
  "armor": { "melee": 0, "pierce": 0 },
  "carry_cap":   { "food": 10, "wood": 10, "gold": 10, "stone": 10 },
  "gather_rate": { "food": 25, "wood": 25, "gold": 25, "stone": 25 },  // per 100 ticks
  "trainable_at": ["building.town_center"], "age_required": 1
}

// buildings.json - footprint comes from the MEASURED art, not from a sketch
"building.town_center": {
  "hp": 2000, "footprint": [10, 10], "los": 8,
  "visual_foundation": "vis.foundation_8x8", "visual_rubble": "vis.rubble_town_center",
  "cost": { "wood": 275, "stone": 100 }, "build_time_ticks": 1500,
  "provides_pop": 10, "garrison_cap": 15,
  "trains": ["unit.villager"], "drop_off": ["food", "wood", "gold", "stone"]
}

// a gatherable building - the field
"building.field": {
  "requires_adjacent": ["building.mill"], "max_per_host_by_age": [0, 2, 3, 4],
  "blocks_movement": false,
  "gather": { "kind": "food", "amount": -1, "slots": 5,
              "yield_per_age": [0, 25, 28, 32] }   // food per 100 ticks per villager
}

// resources.json - `amounts` is indexed by size_class, and since 2026-08-17
// `visuals` is too, so a rich seam and a poor one are different pictures
"res.tree": { "kind": "wood", "amounts": [40, 100, 175], "gather_slots": 1 }
```

**`factions.json` stays** despite §1: one civilisation is a v1 *scope* decision, and a missing
file and an empty one are different states — only one is a bug. Its single entry is
`faction.default`, named for its job as *the default skin key*.

**`market.json`** (added 2026-08-21, §8.7) is the only data file whose numbers are spent *inside
a state transition* rather than read to describe an entity, so it carries a constraint the others
do not: **every value is an integer**. `TributeCommand` and `MarketExchangeCommand` run in the
sim, whose arithmetic must be bit-identical on an ARM phone and an x86 host, so the tax is
`tax_percent: 10` — a multiply and an integer divide — and never `0.1`. Same reason `ages.json`
counts advancement in ticks and not seconds. It also names the **building** that licenses trading,
so the two commands cannot end up gated on different things, and gets the age gate for free from
that building's own `age_required`.

```jsonc
// market.json - gold is the currency, so it has no price entry of its own
"building": "building.market",
"tribute":  { "increment": 100, "tax_percent": 10,
              "kinds": ["food", "wood", "stone", "gold"] },
"exchange": { "currency": "gold", "lot": 100,
              "prices": { "food":  { "buy": 130, "sell": 70 },
                          "wood":  { "buy": 130, "sell": 70 },
                          "stone": { "buy": 130, "sell": 70 } } }
```

**`colours.json`** is the v1 player palette, read by `GameDataRegistry.colour(index)` and indexed
by `SimPlayer.colour`. Eight hues cannot all be told apart by hue: red-green colour blindness
(~8% of men) collapses red, orange, green and yellow onto one axis, so **those four are separated
by lightness** on a CIE L\* ladder. `#0043D6` blue (L\* 36) · `#D50032` red (45) · `#FFEB00`
yellow (92) · `#00E5FF` cyan (84) · `#00A344` green (59) · `#B44DFF` violet (54) · `#FFAB00`
orange (76) · `#FFFFFF` white (100). Pairs close in L\* are always in **opposite** families, so
they separate on the blue-yellow axis every colour blindness preserves. **Slot order is part of
the design** — slots 1–4 are the four most separable, and green sits at 5 so it never meets
yellow before a 5-player game. Order is the contract and is pinned by tests, since reordering
repaints every existing save and replay. Depends on A.6's blend mode: a pure multiply compresses
the ladder and makes white a no-op.

### 9.1 Atlas format

Generated by `isobake` as `<id>.atlas.json` beside its PNG pages. A **generated** file — a rebake
rewrites it wholesale, so nothing is ever hand-merged into it.

```jsonc
{ "format": 1, "id": "vis.villager",
  "pages": ["vis.villager_0.png"], "page_sizes": [[1024, 1024]],
  "directions": { "stored": 5, "mirror_for_8": true, "order": ["S","SE","E","NE","N"],
                  "table": [ { "dir": "SW", "stored_index": 1, "flip_x": true } ] },
  "pixels_per_metre": 22.627431,
  "anims": { "idle": { "fps": 8, "loop": true, "frames": 12, "first": 0 } },
  // index = anims[name].first + stored_direction_index * frames + frame
  "frames": [ { "page": 0, "rect": [0,0,40,52], "anchor": [20.0, 50.0] } ],
  "generator": { "tool": "isobake", "blender": "4.5.12", "recipe_sha256": "..." } }
```

Two deliberate departures from a row-based sheet: **per-frame rects** (a row layout pads every
frame to the largest cell; the villager's 240 frames pack into 20% of a 1024² page as rects) and
**multi-page** from the start (mobile GL ES 3.0 only guarantees 4096², and carrying a `page` index
is cheaper than retrofitting one).

**Anchors are exact, not measured.** With a fixed orthographic camera and the subject rotating
about world Z through the origin, world (0,0,0) projects to one constant pixel; the per-frame
anchor is that constant minus the frame's trim offset. Bottom-centre-of-content-bbox moves
whenever a limb swings out, which was the cause of the anchor jitter that used to be on the risk
register.

Reading any atlas asserts its `pixels_per_metre` against `Iso`.

### 9.2 The v1 roster

Derived from [Age & Unit Planning.md](<Age & Unit Planning.md>), which stays the source of truth
for content decisions. `Age` is the age that **unlocks** an entity; it stays available afterwards.

**Footprints are locked to the maximum across all four age skins.** Buildings re-skin in place as
their owner advances, so a footprint cannot change with the skin: it claims the tiles its age-4
form needs from the moment it is placed. This is a real gameplay fact — an age-1 settlement is
spaced for age-4 buildings — and 0 A.D.'s civs do not agree on obstruction size, so it has teeth:

| Building | 1 `brit` | 2 `gaul` | 3 `achae` | 4 `rome` | Declare |
|---|---|---|---|---|---|
| House | 10×10 | 11×11 | 13×14 | 14×14 | `[4, 4]` |
| Barracks | 20×20 | 20×20 | — | 22×22 | `[6, 6]` |
| **Town centre** | 25×25 | 25×25 | **38.5×22.5** | **37×37** | **`[10, 10]`** |

The town centre was the one MVP footprint the age plan broke — its shipped `[8, 8]` came from the
Athenian actor, and the Roman age-4 civic centre is 37×37. Max is taken **per axis**, since
buildings do not rotate. `visual_foundation` still points at `vis.foundation_8x8` and so reads one
tile small until `vis.foundation_10x10` is baked.

**Composite entities are measured over their props**, not their core building — the lumber camp
with 3× `wood_lumber`, the mining camp with its stone piles, the age-3/4 farm with its food piles,
and the dragon nest, which is 22 bushes and 12 standing stones around a shrine with no core
building at all. Otherwise villagers path through the props and buildings are placeable on top of
them. **Walls and towers are exempt** — every wall piece in 0 A.D. shares one footprint and every
wall tower another, across all civs, so the max rule is a no-op for that set.

⚠️ **A naming trap:** the roster's age-3 `Pers/…` lines resolve to **`achaemenids/`**. There is no
`pers` directory. Every other civ keeps its obvious name.

**Buildings**

| Entity ID | Age | Function | Age skins |
|---|---|---|---|
| `building.town_center` | 1 | +10 pop, drop-off for all four, trains villager + militia. **Extra ones unlock at age 3** | `brit` · `gaul` · `iber` · `rome` `/civil_centre` |
| `building.house` | 1 | +5 pop | `brit` · `gaul` · `pers` · `rome` `/house` |
| `building.mill` | 1 | Food drop-off; fields attach from age 2 | `brit`/`gaul` `rotarymill` · `pers/storehouse` · `rome/farmstead`, age 3–4 + food piles |
| `building.field` | 2 | Adjacent to a mill; **2/3/4 per mill by age**; inexhaustible | `gaul/field` · `iber/field` |
| `building.mining_camp` | 1 | Gold + stone drop-off | `brit`/`gaul` `corral` · `iber`/`rome` `storehouse`, + 3× stone pile |
| `building.lumber_camp` | 1 | Wood drop-off | `brit/kennel` · `celt/longhouse` · `iber`/`rome` `corral`, + 3× wood lumber |
| `building.barracks` | 2 | Swordsman, spearman | `gaul` · `iber` · `rome` |
| `building.archery_range` | 2 | Archer; crossbowman from 3 | `gaul` · `iber` · `rome` `/range` |
| `building.stable` | 2 | Scout cavalry; sword cavalry + cavalry archer from 3 | `gaul` · `pers` · `rome` `/stable` |
| `building.blacksmith` | 2 | Upgrades | `gaul` · `pers` · `rome` `/forge` |
| `building.market` | 2 | Allied trading | `gaul` · `maur` · `rome` `/market` |
| `building.dock` | 2 | Fishing + transport ship; galley from 3, galleon from 4 | `gaul` · `pers` · `rome` `/dock` |
| `building.watch_tower` | 2 | Throws stones | `gaul`/`pers` `sentry_tower` · `rome/defense_tower` |
| `building.guard_tower` | 3 | Shoots arrows. **Is a wall tower**, so it tracks that age's newest wall tier | `pers` · `rome` `/wall_tower` |
| `building.castle` | 3 | **+40 pop.** Knight; elite swordsman + trebuchet from 4; the dragon | `iber/fortress` · `rome/fortress` |
| `building.monastery` | 3 | Monk | `pers` · `rome` `/temple` |
| `building.university` | 3 | Upgrades | `iber/temple` · `mace/temple` |
| `building.siege_workshop` | 3 | Ram, ballista, onager; trebuchet from 4 | `pers/arsenal` · `rome/arsenal` |
| `building.wall_wood` + `gate_wood` | 2 | Short/medium/long + gate | `germ/*` · `brit/*` — **all pieces of a tier from one civ** |
| `building.wall_stone` + `gate_stone` | 3 | | `pers/*` |
| `building.wall_reinforced` + `gate_reinforced` | 4 | | `rome/*` |
| `building.wonder` | 4 | Wonder victory (11.2) | `hellenic_epic_temple` |
| `building.dragon_nest` | — | **Not buildable** — a map POI (13.2). Footprint for occupancy only, never a placement ghost | 22× `bush_badlands`, 12× `standing_stone`, `shrine_celtic` |

**Units** — one hand-picked actor for all four ages, deliberately mixed-civ. Cavalry point at the
`_m` mount, which carries its `_r` rider as a nested prop.

> ⚠️ **READ THE ROSTER'S UNIT LINES AS ENTITY TEMPLATES, THEN RESOLVE ONE HOP TO THE ACTOR.**
> `units/germ/champion_cavalry` means
> `simulation/templates/units/germ/champion_cavalry.xml`, and the actor to bake is inside it:
> `<VisualActor><Actor>units/germans/cavalry_swordsman_c_m.xml</Actor></VisualActor>`.
> Four picks were reported as "actors that do not exist" purely because this step was skipped —
> `art/actors/` has no `champion_*` or `ship_*` files because champions and ships are
> template-level entities. **A recipe's `source.actor` must be the RESOLVED actor.**

| Entity ID | Age | Trained at | Actor to bake |
|---|---|---|---|
| `unit.villager` | 1 | Town Centre | `units/celts/female_citizen` — Britons and Gauls share one female citizen and it lives under `celts/`. Currently baked as `britons/citizen_female` (cosmetic: same mesh, different dress) |
| `unit.militia` | 1 | Town Centre | `units/britons/infantry_slinger_a` ✅ |
| `unit.scout_cavalry` | 1 | **Start-of-match spawn only**; Stable from 2 | `units/mauryas/cavalry_swordsman_a_m` ✅ |
| `unit.swordsman` | 2 | Barracks | `units/gauls/infantry_swordsman_a` ✅ |
| `unit.spearman` | 2 | Barracks | `units/gauls/infantry_spearman_a` ✅ |
| `unit.archer` | 2 | Archery Range | `units/carthaginians/infantry_archer_a` ✅ |
| `unit.fishing_ship` | 2 | Dock | `structures/celts/fishing_boat` ✅ |
| `unit.transport_ship` | 2 | Dock | `structures/celts/skiff` |
| `unit.sword_cavalry` | 3 | Stable | `units/gauls/cavalry_swordsman_a_m` ✅ |
| `unit.cavalry_archer` | 3 | Stable | `units/achaemenids/cavalry_archer_b_m` ✅ |
| `unit.crossbowman` | 3 | Archery Range | `units/han/infantry_crossbowman_a` ✅ |
| `unit.monk` | 3 | Monastery | `units/athenians/healer` ✅ |
| `unit.knight` | 3 | Castle | `units/germans/cavalry_swordsman_c_m` |
| `unit.galley` | 3 | Dock | `structures/athenians/trireme` |
| `unit.siege_ram` | 3 | Siege Workshop | `structures/iberians/siege_ram` — note the template says `cart` and the actor is `iberians`: **the civ in the template path need not match the civ in the actor path** |
| `unit.ballista` | 3 | Siege Workshop | `units/carthaginians/siege_rock_packed` + `_unpacked` |
| `unit.onager` | 3 | Siege Workshop | `units/romans/siege_onager_packed` + `_unpacked` ✅ |
| `unit.elite_swordsman` | 4 | Castle | `units/athenians/infantry_swordsman_c` — `_c`, not `_e`: 0 A.D. dresses its Athenian champion in the citizen-tier mesh, so this is a visibly *different soldier* from `unit.swordsman`, which is better for a Castle unit |
| `unit.galleon` | 4 | Dock | `structures/ptolemies/quinquereme` — recipe written, unbaked |
| `unit.trebuchet` | 4 | Siege Workshop **and** Castle | `units/han/siege_mangonel` + `siege_mangonel_pivot_packed`. The only entity exercising plural `trainable_at` |
| `unit.dragon` | — | Castle | `fauna/dragon` ✅ |
| `unit.dragon_baby` | — | Dragon Nest, 360 s timer | `fauna/dragon` at 10% scale. **Also what `Mode.TROPHY` needs** (11.2) |

**Resources** (`res.*`, gaia-owned): `res.gold_mine` · `res.stone` · `res.tree` ·
`res.berry_bush` · `res.sheep` (→ `fauna/sheep3`, **not** `sheep1` — sheep3's only material is
`animal_sheep_no_player_color_a.dds`, which is why it does not pick up the player tint) ·
`res.deer` · `res.cattle` (→ `fauna/zebu_wild`, **not** `cow` — `_wild` matters, 0 A.D. ships wild
*and* trainable variants of every herd animal) · `res.bear` (no recipe) · `res.wolf` (food 30 and
**attacks** — the only hostile gaia entity, so it needs `CombatSystem`, 4.13).

> Resolving gaia templates the same way as units **found three errors in six animals**. The
> template-resolution rule is not a units rule.

`buildings.json`'s `trains` array is authoritative and `units.json`'s `trainable_at` mirrors it;
`validate()` cross-checks the two. **Start-of-match spawn:** 1 town centre, 5 villagers, 1 scout
cavalry, 0 militia.

**Units with no roster slot, worth knowing about:** war dogs, chariots, a war-horn bearer, and
five named Celtic heroes — which are exactly what a **regicide** mode (11.2) would need. Not
scheduled; recorded because they are free.

#### 9.2.1 Settled content decisions

- **Resource amounts encode the visual size class**, with absolute values freely tunable. What is load-bearing is the ordering and rough ratio between classes, not the numbers. Stone gets three classes like gold; its third gets its own sprite for free by baking the same actor at `yaw_offset_deg = 180`.
- **Everything baked before the age plan is the wrong age skin** — ~36 assets, all Athenian/Hellenic. Cheap per asset (`source.actor` is one line; canvas sizes, `yaw_offset_deg`, `ground_clip` and prop findings all carry over), so read the existing set as **age-skin placeholder art plus ~36 proven recipe templates** for the age-1 Briton pass.
- **Wall civ mixing was copy-paste error**: every piece of a tier comes from one civ. One cosmetic loose end — a player holding age-2 `germ` walls in age 4 sees a `rome` guard tower embedded in them, since there is one guard tower per age rather than per tier.
- **Units do not re-skin per age**, so the roster's per-age unit lines are recorded and deliberately unused.
- **Three siege units are packed/unpacked actor pairs** (ballista, onager, trebuchet) — a deploy/undeploy state machine with its own timings that blocks movement in one state and attack in the other. Scope it **with** 4.13.
- **Age names:** numeral in the HUD, name where there is room for prose (tech tree, advancement banner, lobby). **I Age of Ash · II Age of Embers · III Age of Flame · IV Age of Dragons** — deliberately not AoE's Dark/Feudal/Castle/Imperial, which carries no legal risk but invites the comparison for nothing.
- **Voices: LATIN, one set for every unit in every age.** 0 A.D. ships `global`, `greek`, `latin`, `napatan`, `persian` and **no Celtic set exists**; `global` is four dog-bark files, so it is not a neutral fallback. Latin is literally correct for the age-4 Roman skin and carries a deliberate lorem-ipsum throwback — placeholder Latin is the oldest joke in typesetting. One consequence accepted knowingly: voices are the most expensive asset class to re-record per language, so this puts them on the localisation surface permanently. *One* set used in all four ages is internally consistent by construction; per-age voices were the problem, not voices.

> **The general lesson from nine wrong recipes:** `fishing_ship` was correct and
> `transport_ship` was not, both picked the same way — by reading an actor name and judging it
> suited the unit. **Confidence in the guess carried no information.** The villager is the same
> lesson one step worse: careful reasoning from a real clue (a Briton directory name) actively
> made the asset wrong. The mitigation has to be mechanical, not careful.

---

## 10. MVP definition — ✅ **ACHIEVED**

> One player, one small map, hosted on loopback, on a physical Android phone: starts with 1 Town
> Centre and 5 villagers, pans/zooms, selects by tap and two-finger box, assigns control groups,
> gathers wood/gold/food, watches counters rise, builds and trains, sees the idle-villager count
> work. Units die, corpses fade, buildings can be destroyed. Art is placeholder; the art pack
> downloads and mounts if present.

Everything on the original "not in MVP" list has since landed except AI opponents, remote
multiplayer, sound, campaign, trade, market and chat: combat, fog of war, ages, population
enforcement and win conditions are all in.

---

## 11. Phase plan

Rows are the item and its state. `✅` = done, the file named is where it lives. Blank tag = not
scheduled.

### Phase 0 — Foundation *(all ✅, all `[MVP]`)*

0.1 device-verified Godot project · 0.2a asset seam (`GameDataRegistry`, `atlas_for()` total,
parsing pinned against a verbatim shipped bake) · 0.2b procedural placeholder renderer, sizes in
metres · 0.2c `licence_audit.py` + `LICENCES.md` · 0.4 `GameDataRegistry` entity half + `validate()`
· 0.5 sim skeleton · 0.6 `Net.host_solo()` + `SnapshotSystem` + `SimHost` + view layer · 0.7
`state_hash()`, `Replay`, `sim/` boundary check, `StressTest.tscn` · 0.8 working roots and
`.gdignore` · 0.9 the render pipeline, built as `isobake` and proven on a grass tile, an oak and a
960-frame villager.
**0.3 `AssetPacks` (manifest/download/verify/mount + DownloadScreen) is the one Phase 0 item still open.** `[MVP]`

### Phase 1 — Main menu

| # | Item | Tag |
|---|---|---|
| 1.1 | ✅ `MainMenu.tscn`/`main_menu.gd`. Placeholder buttons answer with a `NoticeToast` rather than doing nothing | `[MVP]` |
| 1.2 | ✅ PLAY → `Game.tscn`; `Boot.tscn` is the main scene | `[MVP]` |
| 1.3 | ✅ `Boot.tscn`/`boot_screen.gd` — title card, 2 s or tap. Distinct from the engine's own sub-second `boot_splash/image` | `[MVP]` |
| 1.4 | ✅ `Credits.tscn` — a `RichTextLabel` mirroring CREDITS.md, hardcoded because CREDITS.md lives outside `res://` | `[MVP]` |
| 1.5 | Settings screen | |
| 1.6 | ✅ **DONE 2026-08-17** — `SkirmishScreen` (`src/view/skirmish_screen.gd`) + `scenes/menu/Skirmish.tscn`; PLAY now routes through it. See §11.1 | |

#### 11.1 Skirmish settings (1.6) — ✅ built 2026-08-17

A skirmish screen and a multiplayer lobby differ only in **what fills a player slot**, so build
one screen with one dropdown per slot: **Human (this device)** / **PlayTest AI** / **Open
(waiting for a peer)**. All-local is a skirmish; one Open slot plus a listening host is a
multiplayer match. This removes the separate lobby from §12.1's estimate, and means the flow
tested solo is the flow that runs on two devices rather than a second path that first executes on
the day it matters.

| Part | Spec |
|---|---|
| Map source | **Random (default)** with a type picker (Random/Island/River/Desert/Forest) and a **visible, editable seed** plus Re-generate; or a saved map (2.4c). A visible seed is what makes "I liked that map" answerable without a file |
| Preview | The generated or loaded map, start positions marked, and a **validation badge** from 2.4b's connectivity gate. **A map that fails validation disables Start** rather than being launched |
| Colour | Per slot, offering **all eight** — every colour bake has been current since the 2026-08-16 rebake, so restricting to two costs work rather than saving it. Default Yellow against Red |
| Players | Read from the generator's own 2–8 clamp, shown **disabled at 2** rather than hidden, so the limit is visible instead of invented |
| Win condition | 11.3 — Last Man Standing, with Trophy and King of the Hill greyed |

Everything it collects **is** a `MatchConfig` — `build_config()` returns one, so the
screen has no vocabulary of its own to translate out of and a test can assert what it
would start without a scene tree. `MatchConfig` gained `seed`, `map_type`, `map_data` and
`ai_players`; that last one finally writes `SimPlayer.is_ai`, a field that had existed
since 0.6 with nothing setting it.

**How the config survives the scene change:** `Net.pending_match`. The screen assembles
it and hands over to `Game.tscn`, whose own `_ready()` starts the session — by which
point the screen is gone, so the config has to wait somewhere that outlives both.
`host_solo()` **consumes** it (clears it after reading), so a match started any other way
afterwards still gets the debug map rather than whatever a screen left behind. That is
what keeps every dev preview working unchanged.

**Still open on this screen:** saved maps in the map-source picker, which waits on 2.4c's
file format; the OPEN slot role, which needs 12.1's listening host; and the art — it is
built from stock `OptionButton`/`SpinBox` controls, the `ResourceHUD`-at-7.1 stage where
the job is the wiring. Verified live end to end by `dev_preview/preview_skirmish.tscn`,
which photographs the screen, starts a match from what it built, and **compares the
running world's terrain against the preview tile by tile** — a settings screen that
previews one map and plays another is the worst failure available here and is invisible
from either picture alone.

### Phase 2 — Map

| # | Item | Tag |
|---|---|---|
| 2.1 | ✅ `SimMap` — four packed arrays, `Domain`, `TERRAIN_COST` on a base-10 scale so slower ground stays integral. Folded into `state_hash()`, without which clients disagreeing about terrain would hash identically | `[MVP]` |
| 2.2 | ✅ Land only, in practice as well as principle: `MapGen` paints only GRASS and DIRT, so WATER/AIR are unreachable in a match. Reopens the day a map has water or cliffs | `[MVP]` (land) |
| 2.3 | ✅ Footprints written into `occupancy`; `despawn()` frees tiles **before** dropping the entity, or occupancy keyed by id would leave tiles claimed forever. A building's `pos` is its footprint **centre** so the view draws every entity identically | `[MVP]` |
| 2.4a | ✅ `MapGen.build_debug_map()` — one start position, fully deterministic, asserted by building two worlds from one config and comparing hashes | `[MVP]` |
| 2.4b | ✅ **DONE 2026-08-17** — `MapData` / `MapGenerator` / `MapValidator` in `src/sim/`, all eight changes applied; see §11.2. The `game_map_gen/` prototype is left untouched | |
| 2.4c | **Save map.** See §11.3 | |
| 2.5 | ✅ Fog of war — `VisionSystem` + snapshot filtering + `FogOverlay`. See §11.4 | |
| 2.6 | ✅ Starting conditions: town centre, 5 villagers on distinct passable tiles, plus wood/gold/stone/food/livestock clusters placed **for the screen** as much as for the grid (iso sends `dx-dy` to screen x, so "below the town centre where the map is empty" is behind the HUD) | `[MVP]` |
| 2.7 | Real terrain tileset (art track A.1) | |

#### 11.2 Map generator (2.4b) — ✅ ported 2026-08-17

Lives in the game as three sim classes. **`MapData`** is the intermediate representation —
terrain bytes plus an entity list — and it exists so that one thing serves four: what a
generator produces, what a saved file holds (2.4c), what the skirmish screen previews (1.6),
and what `MapGen.build_from()` turns into a world. A generator writing straight into a
`SimWorld` can be none of those. **`MapGenerator`** produces one; **`MapValidator`** is the
gate, and it is built into `generate()` rather than offered beside it.

The owner's `game_map_gen/` prototype is **left untouched** — it is theirs, and the two can
diverge freely now.

Sizes: 2P 96×96, 4P 128×128, 8P 192×192. Generation takes 30–170 ms and every type validates
first try. Look at the output with `dev_preview/preview_mapgen.tscn`, which writes one PNG per
type — it is the only way to judge a map layout.

**Two assumptions in this plan turned out to be wrong, and both are corrected elsewhere in it.**
The map is now **sent** to joining clients rather than regenerated by them (see §12.1 step b),
because `FastNoiseLite`'s float maths is not guaranteed identical across CPUs. And **starting
resources are placed, not sampled**: the validator's first run caught a desert start with one
reachable tree and no food at all, which is exactly what it exists for.

The eight changes, all applied:

1. **SIZE IS THE LOAD-BEARING DECISION AND IT IS QUADRATICALLY WRONG.** The rule (`players * 150`, code `* 100`) grows the **side** linearly, so 8 players get 8× the side and **64× the area** of 2. A 300×300 map is 90,000 tiles against the debug map's 4,096 — and 2.4a's own note calls 64×64 a generous settlement's room for *one* player. The pathfinding rebuild goes ~12 ms → ~264 ms, and worse, **fog is one byte per tile per player**, so the snapshot's vision payload goes 4,104 → ~90,000 bytes, taking one tick from 12 KB to ~100 KB and one player's stream to ~1 MB/s. Use **area** per player: `side = 64 * sqrt(players)` → 2P 96, 4P 128, 8P 184.
2. **The pixel format is ambiguous.** Town centre, villager and scout are all `ff0000`, so a loader cannot tell them apart except by blob-size analysis, and nothing says *whose* base it is. Split it: the **PNG stays authoritative for terrain and resource veins** — spatial, numerous, the part you want to see by looking — and the handful of **entities** (2–8 town centres, five villagers each, scouts, the dragon: under 60 entries) move to a **sidecar JSON** as (role, player, tile). The PNG can still draw them for the human preview, with the loader ignoring those pixels.
3. **Footprints must come from `buildings.json`.** The plan reserves 5×5 for a town centre that is **10×10** in the data, and rings units at radius 4 — *inside* it — so every villager spawns inside its own town centre. Clear `footprint + 6`; ring units at radius 7+.
4. **`unit.scout` does not exist**; it is `unit.scout_cavalry`.
5. **Connectivity is not guaranteed** — only Forest carves paths, so island/river/desert can wall a player in, invisibly, until someone plays it. Flood-fill from every start: each must reach every other start and a minimum of wood/gold/stone, else regenerate. **A hard gate**, and what makes the generator headlessly testable.
6. **The river must divide the map — but keep the land bridges.** The bridges are the liked part and stay (owner, 2026-08-17). The defect was that both samples showed **three disjoint segments with 20-tile gaps**, so it read as three lakes and the opposite-sides rule meant nothing. Now: a **continuous** river with **1–3 five-tile bridges**, sides assigned by the sign of the perpendicular distance to the centre line, and the direction varying over four axes rather than hardcoded to `y = x`. A test asserts the straight line between two starts crosses water, and the validator asserts they can still reach each other — which together is what "divided but crossable" means.
7. **Determinism:** `rng.randomize()` has to go. The seed comes from `MatchConfig` so two peers generate byte-identical maps (§7.1) — which also makes "share a map by sharing a seed" free and generator tests reproducible.
8. **Bugs found reading it:** terrain is generated **twice** (the first pass is entirely overwritten, and it consumes rng draws so the passes disagree); `_place_resource_vein` **can spin forever**, since `placed` only increments when a pixel is actually written and a vein that walks off-map writes none — cap the iterations; veins have no guard against covering a town centre or water; `_place_dragon`'s centre fallback skips its own water check; `ShowMap.save_current_map()` writes to `res://maps/`, read-only in an exported build.

#### 11.3 Save map (2.4c)

A Save Map button on the pause menu, so a player who likes a random map — or one someone else made
and shared — can name it, keep it, and pick it again from 1.6. Three things it must get right:

- **It saves the MAP, not the MATCH.** By the time the button is pressed the world is full of buildings and rubble. What gets written is the terrain and start layout the match was **started** with, so `GameScene` must hold on to its map source rather than reading the live `SimMap`. Saving current state is a save *game* (12.4) — the button must not blur the two.
- **`user://maps/`, never `res://`**, which is read-only once exported. The picker lists bundled maps from `res://maps/` and saved ones from `user://maps/` together.
- **The PNG is authoritative; the seed is provenance.** A sidecar JSON carries {name, type, players, size, seed, format_version, created}. The seed alone cannot reproduce a map, because any generator change makes the same seed produce something else.

#### 11.4 Fog of war (2.5) — done 2026-08-17

`VisionSystem` writes `SimPlayer.vision`, one `Fog` byte per tile (UNSEEN/EXPLORED/VISIBLE),
recomputed from scratch every tick after `DeathSystem` so a scout killed this tick lights nothing.
Vision is a **Euclidean circle measured to the footprint**, not the centre tile — a 10×10 town
centre at los 8 measured from its middle would see barely three tiles past its own walls, putting
a blind spot exactly where the player's base is. EXPLORED is sticky.

**The filtering is the point** (§5.1 step 6, a security property). The line is **mobile vs
static**: your own entities always go; anything currently visible goes in full; an explored
**static** goes as `_remembered()`, stripped of hp, queue, amount, build_fraction and anim so a
memory cannot report live state; an enemy **unit** out of vision does not go at all, because its
position is exactly what would leak. Client-side, absence from `updated` means "no longer
visible", and `GameView` drops the **facts** as well as the node — a stale fact would still answer
`pick()` and still draw a minimap blip. An explicit hidden-list was rejected: it would let a client
read enemy unit **counts** off the wire.

`FogOverlay` draws it as a `TileMapLayer` **over** the entity pool, diffing against the last grid
so a tick costs tens of `set_cell`s rather than 4096. The fog tiles are proven to tessellate with
every boundary pixel claimed by exactly one diamond — that fill has been in `TerrainLayer` since
3.1 and an off-by-one was invisible there because those tiles are opaque, but blending a 45% wash
twice puts a darker diamond grid across every explored region.

**Known simplification:** a static destroyed behind the fog stops being sent rather than leaving
AoE's stale ghost, which would need a per-player last-seen copy of every static.

### Phase 3 — Camera & world view

| # | Item | Tag |
|---|---|---|
| 3.1 | ✅ `TerrainLayer` (a real `TileMapLayer`, built from raw bytes). `rendering_quadrant_size = 8` was **measured**, and the answer is backwards from the obvious reasoning: 8 gives 32 draw calls where the engine default 16 gives 165 and 32 gives 280, because a large isometric chunk is a diamond straddling a rectangular viewport. Also fixed a half-tile terrain offset — invisible on uniform grass, obvious at any boundary | `[MVP]` |
| 3.2 | ✅ Edge-swipe zoom on either strip, 0.6–2.0, **multiplied not added** — a fixed step per pixel would crawl at 2× and leap at 0.6×. The gesture is decided on touch-down and held until release | `[MVP]` |
| 3.3 | ✅ `CameraRig`. **Clamping is two rules**: the centre stays on the map DIAMOND (clamped in tile space, where it is an axis-aligned box) and then the viewport stays inside the projected box. Box-only clamping is what `Camera2D.limit_*` does, passed every unit test, and still left a screen ~85% void at the west corner | `[MVP]` |
| 3.4 | ✅ Double-tap minimap → centre on own town centre | `[MVP]` |
| 3.5 | Camera follow selected unit | |
| 3.6 | ✅ `Game.tscn`/`game_scene.gd` — the first thing in the project that is a game rather than a harness. Hosts through `Net.host_solo()` so local orders take the same route a remote player's would | `[MVP]` |
| 3.7 | Tap minimap to move selected units | |
| 3.8 | ✅ Tap minimap → centre camera there | `[MVP]` |

**Verified on the §3.0 device** driving real touch through `adb`: viewport **1404 × 648** exactly
as predicted; pan magnitude and direction correct against the 1.852× canvas ratio; zoom hit both
clamps; **zero cross-talk** (camera byte-identical across both edge swipes, zoom unchanged by a
mid-screen drag); 200 units + settlement at **60/58/60 fps**, 24–65 draw calls, sim tick 0.31–1.54
ms avg. One figure over budget: sim tick **max 7.63 ms** against <5 ms — it is the harness's own
200 individual `submit_command()` calls in one frame, where a real shared-destination order is one
`MoveCommand` with many `unit_ids`.

### Phase 4 — Units

| # | Item | Tag |
|---|---|---|
| 4.1 | ✅ `MovementSystem` walks the route waypoint by waypoint; a tick's budget carries across waypoints. **Stop at nearest reachable**: `set_path()` rewrites `task_target_tile` to where the route actually ends, or a unit sent to a tree stands beside it in MOVE forever | `[MVP]` |
| 4.2 | ✅ `PathService` on `AStarGrid2D` with a per-tick budget, plus `SeparationSystem` — pushes overlapping units apart by half the shortfall each, visiting units and pairs **sorted by id** so every client resolves the same overlaps in the same order. A push is capped under half a tile and dropped if it would land on impassable ground. Diagonals do not cut corners past a blocked tile | `[MVP]` |
| 4.3 | ✅ `Selection` (client-side; a selection in the state hash would desync the moment one player tapped), `InputRouter` taps, selection ring, panel from `units.json` | `[MVP]` |
| 4.4 | ✅ `GatherCommand`/`BuildCommand` reuse the walk-there machinery; `MovementSystem` advances **any** unit with a route left rather than only ones tasked MOVE, so GATHER/RETURN/BUILD travel for free | `[MVP]` |
| 4.5 | ✅ `GameView.tap_action()` decides what a tap means from pure facts; `ActionFlash` shows which order fired. This closed a real gap: gather and build existed sim-side and **nothing in the view had ever dispatched them** | `[MVP]` |
| 4.6 | ✅ Health dot, positioned off the visual's declared `height_m`, sharing thresholds with the panel through `HealthDot.color_for()` | `[MVP]` |
| 4.7 | ✅ `DeathSystem` — corpse for 70 s, `decay` for the last 10 s, then `despawn()`. `SnapshotSystem` gained a **real** `removed[]`, the first thing in MVP that despawns mid-match | `[MVP]` |
| 4.8 | Garrison | |
| 4.9 | Defensive garrison damage bonus | |
| 4.10 | Special abilities + cooldowns | |
| 4.11 | ✅ Population cap, **enforced**. See §11.5 | |
| 4.12 | Stances | |
| 4.13 | ✅ **mostly** — `CombatSystem`: walk to the target, stand at reach, strike on cooldown, damage after matching armour with a `MIN_DAMAGE` floor (armour must blunt an attack but never make a defender invulnerable to a whole class, because nothing on screen would explain it). Reach is measured to a **footprint**, not a centre, or melee could never touch an 8×8 building. Deliberately **no auto-acquire and no retaliation** — a unit fights what it was ordered to fight, since guessing means every villager charging the first enemy that walks past (that is 4.12). **Left in 4.13:** the packed/unpacked siege state machine, the hostile wolf, and arrow projectiles (`vis.projectile_arrow`/`_bolt`/`_stone` are staged and referenced by nothing) | |
| 4.14 | Formations | |

#### 11.5 Population cap (4.11)

`PopulationSystem` recounts `pop_used`/`pop_cap` from scratch every tick and, since 2026-08-17,
**owns the rule**: `has_room_for()` is called by `TrainCommand.validate()` (the server is the only
trust boundary) and by `GameScene` before it submits, so the toast the player reads and the
refusal the host makes are one implementation.

Two things that are not obvious. **The gate derives the population rather than reading
`pop_used`/`pop_cap`**, because `CommandSystem` runs first in the tick and this system runs last:
the report is a tick stale when the gate is asked, and 0/0 on tick 1, so a gate trusting it would
refuse the first villager of every match. And **queued units reserve their population**, without
which the cap is trivially beatable — a player one slot short could queue twenty villagers and get
all twenty. What it deliberately does not do is stop an already-paid-for unit from spawning.

### Phase 5 — Buildings

| # | Item | Tag |
|---|---|---|
| 5.1 | ✅ `PlaceBuildingCommand` + drag placement: entering build mode **locks the camera**, so the one finger that would pan drags `PlacementGhost` instead. Two-finger pan was ruled out — it collides with box-select's trigger and breaks one-handed play | `[MVP]` |
| 5.2 | ✅ Foundation → under construction → complete, reachable without a debug command | `[MVP]` |
| 5.3 | Building upgrades | |
| 5.4 | ✅ `TrainCommand` (pays up front), `CancelProductionCommand` (refunds exactly what was paid), `ProductionSystem` advancing only the queue front | `[MVP]` |
| 5.5 | ✅ Destruction → `DESTROYED` phase + `free_footprint()`, so the ground is buildable the instant it falls. Rubble stays opaque forever (no damaged art tier) | `[MVP]` |
| 5.6 | ✅ Building health on the shared dot | `[MVP]` |
| 5.7 | Full building roster — 23 buildings. Low code effort, ~70 bakes behind it | |
| 5.8 | ✅ **DONE 2026-08-22** — **Walls and gates**: drag placement, automatic short/medium/long segment choice, two orientations, and a gate that opens and shuts. Three tiers, twelve defs, three menu entries. The gate is an **upgrade of a long segment**, not a placement — tap-placing one could only ever lie east-west. See §5.8 | |

#### 5.8 Walls and gates — ✅ built 2026-08-22

The largest block of finished art the game could not reach: 22 wall pieces baked and
staged, and no way to put one on the map. Four things stood between them and the build
menu — drag placement, automatic segment choice, an orientation, and a gate that lets
your own people through — and all four are here.

**The art was staged but NOT declared**, which is worth recording because two documents
said otherwise. `buildings.json` claimed "all 24 wall pieces are baked and declared in
visuals.json"; only the tower's rubble and foundation were. Nothing failed and nothing
rendered, because an undeclared id is not an error — it resolves to the magenta
placeholder, and no building def pointed at one to make it appear. The lesson is the
same one the staged-atlas gotcha teaches: *staged* and *wired* are different states, and
only a def reaching for an id proves the second one.

**Every civ agrees on the segment lengths, and that is the whole reason this is
tractable.** Measured the usual way — `<Obstruction><Static>` at 4 units per tile,
rounded up, maxed per axis across each tier's ages:

| piece | germ | brit | achae | rome | tiles |
|---|---|---|---|---|---|
| short | 12×8 | 12×6 | 12×6 | 12×8 | **[3, 2]** |
| medium | 24×8 | 24×6 | 24×6 | 24×8 | **[6, 2]** |
| long | 36×8 | 36×6 | 36×6 | 36×8 | **[9, 2]** |
| gate | 37×6.5 | 36×7 | 36×6 | 36×6 | **[9, 2]** |

3 / 6 / 9 tiles long and 2 deep, universally — so one segmentation function is correct
for all three tiers, and a tier is nothing but a skin and a price. **The gate is forced
to a long segment's [9, 2]** even though the germ one measures 9.25 tiles: a gate has to
be substitutable for a long piece or it cannot sit in a run without leaving a gap (0
A.D. makes the gate an *upgrade* of a long wall for exactly this reason), and the cost is
a half-tile of art overhang — the same deliberate disagreement the house's roof makes.

**Three tiers, three menu entries, twelve defs.** The project owner's call: all three
stay available at age 4 rather than one re-skinning the other two away, so wood (age 2),
stone (3) and reinforced (4) are three ladders and not one. The tier's SHORT segment
carries `wall_lengths` and is the WALL entry — the drag reads that list to decide what
to lay — and the other nine pieces are `buildable: false`, a new flag meaning *the
system may place this, the menu may not offer it*. Without it the build grid would carry
all twelve pieces and eleven of them would each place one fixed-length block, which is
the outcome walls were held back over.

##### The gate is an upgrade, not a placement (2026-08-22)

It shipped as a menu entry placed by tapping, and the project owner found the hole
inside a day of playing: **"how do I rotate a gate?"** You could not. A gate is [9, 2]
and `PlaceBuildingCommand` carries no facing and never transposes a footprint, so every
tap-placed gate lay east-west — which meant **a north-south wall could not have a gate
in it at all**, and there was no rotate control to fix it with.

Three ways out were on the table: a rotate button on the ghost, folding the gate into
the wall drag, or inferring the axis from the ground. The owner picked the fourth —
**tap a finished long segment and upgrade it** — which does not answer the rotation
question so much as delete it: the wall already knows which axis it was dragged along,
and the gate inherits its origin, its footprint and its facing. There is nothing left to
rotate, on any screen size. It is also what 0 A.D. does, and this section had already
said so four paragraphs earlier without noticing it was the answer.

- **All three gates are now `buildable: false`.** Upgrading is the only way to get one,
  so the broken axis case cannot be reached rather than being worked around.
- **`BuildingDef.upgrades_to`** is the new field, on the three long segments only. The
  target must declare the SAME footprint and `UpgradeBuildingCommand.validate()`
  enforces it, because `SimWorld.convert_building` keeps the ground the building already
  holds and a target wanting more of it would silently occupy tiles nobody checked.
- **Converted in place, keeping the entity id.** A despawn-and-respawn would empty the
  panel the player pressed the button on, and would put the wall in `removed_this_tick`
  — telling every other client a building was *destroyed* when one was improved.
- **The price is the difference, floored per resource kind.** 36 wood paid for the wall,
  the gate lists 50, so the upgrade is 14. Floored per kind rather than in total, so a
  target cheaper in one resource cannot hand back a refund in it.
- **Health carries its fraction**, since the two defs have different maxima (1200 and
  1000). Full health is pinned exactly, so the commonest case cannot round to 999 and
  show a damage dot on a brand new gate.
- It turned the `upgrade` slot — a disabled placeholder on every building since the
  panel was written — into the first real upgrade in the game.

**A bug the screenshot found, not the suite:** the selection ring on a north-south wall
was drawn eighteen metres *east*, sprawling across open grass. Every other consumer
already read the transposed footprint; the ring read the visual's placeholder, which is
authored east-west because the art is. `EntityView.ground_m` now carries the claimed
ground, and `GameView` sets it only where the actual footprint disagrees with the def's
— narrow on purpose, since sizing every ring from the footprint would have doubled the
villager's and moved every building's off its measured mesh.

**`WallPlan` is one function with two callers**, and that is the design rather than a
convenience: the ghost draws what it returns and `PlaceWallCommand` places what it
returns. Two implementations of "which pieces fill this line" would differ by a segment
somewhere, and the player would only ever find out after letting go. It lives in
`src/sim/` because the server is what lays the wall down; it is integer arithmetic over
tiles, so the boundary rule is satisfied and the view reading it is the allowed
direction.

- **A sloppy diagonal becomes a straight wall.** The drag snaps to whichever axis it
  mostly ran along — the finger is on a phone and the grid is isometric, so nobody drags
  a clean line, and refusing an imperfect one would make the feature unusable on the
  device it is for.
- **The run is rounded to a whole number of short segments** and filled longest-first,
  which on a multiple of 3 always fills exactly: 12 → 9+3, 15 → 9+6, 18 → 9+9. Longest
  first because fewer pieces is fewer seams to attack, fewer vision circles and fewer
  snapshot entries.
- **Always laid in the +axis direction from the lower end**, so dragging backwards
  describes the same wall and the ghost does not reshuffle when a drag crosses its own
  anchor. The perpendicular coordinate comes from the anchor, so the wall stays on the
  row the drag started on rather than sliding onto the row it ended on.
- **A tap is one short segment.** A drag of zero length still means "put a wall here".

**Only two of the eight baked directions are reachable**, and that is the footprint
system rather than the art: a [9, 2] box rotated 45° does not tile a square grid. A
north-south wall is its def's footprint *transposed*, which is the whole of what "8
orientations" reduces to. `SimBuilding` gained a `facing` for it — buildings had none,
and its header says why every other one is baked at `directions: 1` and stays at 0
forever. **The view DERIVES the transposed footprint from `facing`** rather than being
sent it: sending it would be the first field 12.1f took off the wire coming straight
back, and `facing` already says which axis the piece lies on.

**A run is partial by design.** Blocked tiles are skipped, and when the money runs out
the last piece is **downgraded** to whatever the tier still affords before the run ends.
That downgrade was not in the first version and the suite is what found it: a player with
two shorts' worth of wood who drags thirty tiles cannot afford the leading nine-tile
piece, and was getting *nothing* — with wall they could plainly pay for on the table. It
buys the largest affordable piece that fits the segment's own span, so two shorts' worth
of wood becomes one medium: same ground, same money, one fewer seam.

**Builders are spread round-robin across the segments**, not all queued on the first.
Five villagers on the first of twelve foundations raise it in a fifth of the time and
then idle beside eleven untouched ones — the same "a foundation nobody returns to"
pattern that needed a standing order in the PlayTest AI.

##### Gates

**A gate starts OPEN and can be locked** (project owner, 2026-08-22). The alternative was
closed-by-default: a wall that defends the moment it is finished, at the price of
stranding your own villagers behind it before you have noticed there is a gate to open.
Open never strands anybody, and the price is that a new wall does nothing until somebody
shuts it.

The mechanism is three lines because `SimMap.set_occupied` already takes a `blocks`
flag — the one that makes a field claimed and walkable at once. `SimBuilding.blocks_now()`
is the whole rule. **Locking evicts whoever is in the doorway**, for the reason
`_evict_from_footprint` records at length: a unit inside a blocked cell is a unit
`AStarGrid2D` will not plan a route *out* of, and a gate swinging shut is the only thing
in the game that can create that situation on purpose.

`ToggleGateCommand` **names the target state rather than meaning "flip"**. A toggle
depends on when it lands: on a client the second tap goes out before the first one's
snapshot returns, so a double tap would be as likely to shut a gate as open it.

**AN OPEN GATE IS OPEN TO EVERYONE**, the besieging army included. Per-player passability
is the real fix and needs a pathfinding grid per player — `PathService` has exactly one
`AStarGrid2D` — so it is deliberately not attempted. What exists is 0 A.D.'s own model
("can be locked to prevent access") and it is one honest step short of AoE2's
allies-only gate.

**`gate_locked` and `facing` are both in `state_hash()`.** The lock moves the *movement
grid*, so two hosts disagreeing about a doorway would route the same army two different
ways and diverge in position a tick later — which `pos` reports long after the cause.

##### Not done, and why

- **No wall tower**, and none is needed: the roster's `Pers/wall_tower` and
  `rome/wall_tower` are exactly what `vis.guard_tower` is baked from, so
  `building.guard_tower` already *is* the wall turret. 0 A.D. auto-places towers at wall
  corners, which is a nicety that wants the wall system settled first.
- **No garrison.** 0 A.D.'s medium wall declares eight turret points; ours hold nobody.
  Garrison is 4.8 and unbuilt, and a wall is the wrong place to introduce it.
- **No diagonal walls.** Six of the eight baked directions are unused. It needs a
  footprint model that is not a box.
- **The Athenian bakes are unused** (`vis.wall_short/medium/long/gate`, no age suffix) —
  they predate the age ladder and the roster does not name Athens for walls. Left staged;
  they are the obvious stand-in for a fourth tier.

### Phase 6 — Resources & wildlife

| # | Item | Tag |
|---|---|---|
| 6.1a | ✅ superseded — `res.berry_bush` is the MVP food node: no hunt/kill/carcass machinery, gathers like a tree, and its art is fully delivered where the deer carcass is not | `[MVP]` |
| 6.1b | Wildlife roaming + flee-and-relocate | |
| 6.2/6.3 | ✅ Size classes are pure data. Since the 2026-08-17 ore/tree rebake the class picks the **sprite** as well as the amount, so a rich seam and a poor one are different pictures | `[MVP]` |
| 6.4 | ✅ `GatherSystem`: walk, extract on a whole-tick countdown (a float accumulator would round differently across machines and desync), fill `carry_cap`, walk to `nearest_drop_off()`, deposit, return or retire. `gather_slots` is enforced by **recomputing** which ids rank lowest among holders every tick rather than reserving a field — so a competitor stopping, dying or being re-tasked frees its spot with nothing to keep in sync. A short last take costs a **proportional** wait, not a full interval (see §12 field balance) | `[MVP]` |
| 6.5 | ✅ **mostly** — stone, berry bushes, livestock and farms/fields all land. `res.bear` and fishing remain | |

### Phase 7 — Resource HUD

7.1 ✅ `EventBus` decouples the HUD from whoever receives the snapshot. **Two counters, two
sources, deliberately**: population is sim state (`PopulationSystem` writes it, and the cap is a
rule a server must enforce) and rides `player_state`; the idle-villager count is a headcount over
what is in view and is derived client-side. They were one signal until the owner corrected it —
the resource panel's bottom row is the *population*, and idle villagers are the age header's
badge, which is a button that walks to them. `[MVP]`

### Phase 8 — Main game interface

| # | Item | Tag |
|---|---|---|
| 8.1a | ✅ `SelectionPanel` over `panel_background.png`, with an `EntityPortraitView` cropping the entity's own baked sprite through a Kibyra avatar ring, and a two-layer `HealthBarView` (a darkened copy under a value-clipped bright one, since the pack has no empty/full pair) | `[MVP]` |
| 8.1b | ✅ Train button + queue count + cancel, inside the framed panel. Per-slot queue **icons** deferred while there is one trainable unit — a row of near-identical icons says less than a count | `[MVP]` |
| 8.1c | ✅ Multi-select grid of portraits, capped at 20 (UI_Design.md's own figure) since the title's "(+N)" covers the rest. Per-portrait mini health overlays deferred as polish | `[MVP]` |
| 8.2a | ✅ `Minimap` — terrain baked once into an `Image`, blips redrawn per snapshot, fog painted **over** the blips (2.5) | `[MVP]` |
| 8.2b | ✅ **DONE 2026-08-21** — 4 corner buttons, all four real. `hud_settings` took over the pause menu from the button that used to sit in the age header; `hud_trade` opens a **working market**; `hud_chat` and `hud_techtree` open **wireframes**. See §8.2b below | |
| 8.6 | **Chat** — wireframe only (§8.2b). The transport is unbuilt and the design question is per-team versus all-players | |
| 8.7 | ✅ **DONE 2026-08-21** — **Market**: tribute with a tax, and buy/sell against gold. Two commands, one data file, one page. See §8.2b | |
| 8.3 | ✅ Two-finger box select, drawn in **screen** space (world space would slide it under the fingers holding it whenever the camera moved). Own units only; tested against each unit's ground point, not its sprite; returned in **id order**, because a box catching more than `MAX_SELECTED` must keep the same units on every machine | `[MVP]` |
| 8.4 | ✅ `NoticeToast` | `[MVP]` |
| 8.5 | ✅ `PauseMenu` — stops `SimClock`, so a real pause rather than a panel over a ticking match. **Reached from the SETTINGS corner button since 2026-08-21**, not from a pause button in the age header: that button was the project owner's call to retire, and its actions belong beside the three sibling pages rather than in the top-centre chrome. Still the same class — Resume/Resign/Quit is still what it holds | `[MVP]` |

#### 8.2b The minimap's four corner pages — ✅ built 2026-08-21

Four buttons that were dimmed placeholders for as long as there was nothing behind them.
They share `HudPanel`: a dimmed backdrop, a framed page, a title, a body and a button row.
**None of them stops the clock**, unlike the pause menu beside them — a market has to show
live stockpiles to be worth opening, and on a joined client a local pause was never a pause
anyway (the host keeps ticking; see `PauseMenu`'s header). One page at a time, and pressing
the corner you are already on closes it, which gives a phone a second way out of every page.

**Two mechanical details that cost real time and would cost it again.** The grid holding the
four buttons covers the whole 200×200 minimap area, so the buttons must be `MOUSE_FILTER_STOP`
**individually** and the grid `IGNORE` — the other way round and every tap on the diamond
dies in the grid. And each button must be *shrunk into its corner*: a container child fills
its cell by default, so all four came out 32 wide and **98 tall**, a full-height strip down
the side of the diamond. Harmless while they were `IGNORE` placeholders; a tap on the
diamond's upper-left edge opened the chat page the moment they became real.

**They do not use `panel_background.png`.** That texture is 160×192 — a small *portrait*
panel with a heavy gold dragon ornament, sized for the resource counter. Stretched across a
872×568 landscape page the dragon inflates into the middle of the content and reads as
damage (photographed). So these pages take the line `Minimap` already took when the pack had
nothing at its shape: a flat dark fill with a gold border, honest about being a stand-in.
When the arch art the mockups draw exists, it replaces the title and the fill and the layout
below does not move.

| Corner | Page | State |
|---|---|---|
| top-left | **Chat** (8.6) | **Wireframe.** The player tabs are the real players with their real colours off the snapshot, so the row is the right width; the messages are samples and the page says so. SEND and CLEAR are **disabled** — a wireframe whose buttons worked *locally* would be worse than one whose buttons do not, because a message appearing on your own screen and nowhere else is a bug report waiting to happen. **The real thing** is a reliable RPC pair on `Net` rebroadcast by the host (the `_recv_command` trick that makes `ResignCommand` unforgeable), **not** a `Command` — chat changes no sim state, so putting it through the tick would give it a 100 ms floor and put text in `state_hash()`. What is actually open is a design question: all-players or per-team |
| top-right | **Market** (8.7) | **Working.** Below |
| bottom-left | **Tech tree** (9.4) | **Wireframe, and a real renderer with no data.** It walks `GameDataRegistry.tech_ids()` and lays each tech out in its age's column with its prerequisites named, so the day 9.3 fills `techs.json` in this page fills in with it. `techs.json` is deliberately empty, so today it draws a placeholder lattice and says which it is. **Read-only by design, not by shortcut**: researching happens at the building that offers it, the way training does, so there is nothing to press and no command behind it. Two states only — reached ages lit, later ages locked. `RESEARCHED` is in the legend and never assigned, because `SimPlayer` has no researched-tech field and a field the HUD reads that nothing writes is exactly the hole 4.11's population counter was |
| bottom-right | **Settings** (8.5) | The pause menu, moved here |

##### 8.7 The market

Everything it needs already existed — `SimPlayer.stock`, `building.market` in `buildings.json`,
and every player's id and colour on the snapshot — so this is wired end to end rather than
drawn. `data/market.json` holds the numbers, and **every one of them is an integer**: this
arithmetic runs inside the sim, where a float is free to round differently on an ARM phone
than on an x86 host, so the tax is `10` percent and not `0.1`.

- **`TributeCommand`** — the sender pays `increment` (100) and the recipient receives
  `increment × (100 − tax) / 100` (90). **The tax is why this is one command and not two**: a
  tribute is not a transfer, the resources are destroyed in the middle, and splitting it
  would give a tick where they exist nowhere. Refuses a self-tribute, a defeated recipient,
  and a negative amount — that last one is the resource generator.
- **`MarketExchangeCommand`** — one command for both directions, distinguished by a bool,
  because every rule around them is shared. **The price is not on the wire**: a client says
  what it wants to trade and the server looks up what that costs, the same reason
  `TrainCommand` carries a unit id and not a cost.
- **Gold is the currency**, which is why it has no exchange entry: the market buys and sells
  food, wood and stone *for* gold. A market that traded any resource for any other would make
  three of the four interchangeable and the fourth pointless.
- **Buy 130, sell 70**, so a round trip loses 60% — an emergency valve for a shortage and
  never a substitute for gathering. AoE2's market opens at 100/100 and **drifts** with every
  trade, which is the better mechanism and is deliberately not this one: a drifting price is
  per-player mutable state, so it would have to live on `SimPlayer`, ride the snapshot and
  enter `state_hash()`. Worth doing once the market has been played with. Fixed prices are one
  data change away from being that mechanism's starting point.
- **`GameDataRegistry.validate()` fails the suite if buy ever drops to sell**, because that is
  infinite gold at the speed of a finger, and a test asserts the same thing against the
  transaction rather than the data.
- **The gate is a finished market**, named in `market.json` so the two commands cannot end up
  gated on different things — and because `building.market` is age 2, requiring the building
  requires the age without stating it twice. The corner icon is **dimmed, not disabled**,
  while none stands: a disabled icon teaches nobody what a market is for, and the page names
  the building and says the buttons stay refused until one is up.
- **What is deliberately not shown**: the other players' stockpiles. `player_state` carries
  every player's `stock` to every client, so this page *could* print an opponent's gold — and
  a fog of war that hides their buildings while the HUD prints their bank balance would be a
  strange kind of secrecy. That leak is `SnapshotSystem`'s to close; this page declines to be
  the thing that makes it matter.

### Phase 9 — Ages & tech

| # | Item | Tag |
|---|---|---|
| 9.1/9.2 | ✅ `AgeBadge` — the numeral in a gold circle, with advance progress as the **ring around the badge** rather than a separate bar. Progress rides the snapshot as **int ticks**; the view does the division, so the sim carries no floats | |
| 9.3 | `TechSystem`: research timers, stat modifiers, gating. **The field yield's per-age ladder is standing in for a mill tech until this lands** | |
| 9.4 | Tech tree screen — **the page exists as a wireframe** behind the minimap's bottom-left corner (§8.2b), and the renderer is real: it walks `techs.json` and will populate the day 9.3 fills it in. Read-only by design — research happens at the building | |
| 9.5 | Additional civilisations — the **re-skin tier** is pure content (a `visuals.json` skin set plus a name table, no sim change, partially shippable). Unique units and per-civ bonuses are the expensive tier and want a separate decision | |
| 9.6 | Age re-skin: visuals resolve through the owner's current age. Pure view work — `SimPlayer.age` already reaches the client | |

### Phase 10 — Control groups

Core mobile mechanic; needed testing under real thumb use, so it shipped in MVP.

| # | Item | Tag |
|---|---|---|
| 10.1 | ✅ `ControlGroupsHud` — 5 slots stacked top-left, each a dragon-ring frame around an icon cropped from the entity's own baked sprite (no portrait art exists yet). Reads **only** `EventBus.control_group_changed` | `[MVP]` |
| 10.2 | ✅ **Simplified**: double-tapping a slot assigns whatever is currently selected, regardless of how that selection was made (tap, box, or an existing group) | `[MVP]` |
| 10.3 | ⬜ **DROPPED** — double-tap-a-unit-to-select-its-type was an alternate way *into* an assignment that 10.2's one rule already covers. Revisit only if playtesting shows a gap | — |
| 10.4 | ✅ A slot's icon is the most-represented def_id among **currently-alive** members (deterministic tie-break on sorted def_id keys), and `&""` once all are dead, which the slot draws as an empty circle | `[MVP]` |
| 10.5 | ✅ **Merged**: a single tap both reselects the group **and** recentres the camera on it, rather than splitting the two across single/double tap. `DoubleTapDetector` disambiguates off pure timestamps, deferring the single-tap action by its own window so a completed double tap never also fires a reselect. PC mirrors it: 1–5 selects, Ctrl+1–5 assigns | `[MVP]` |
| 10.6 | ✅ `SimPlayer.control_groups` is mutated only by `SetControlGroupCommand`, validated like any command, folded into `state_hash()`, and rides `player_state` — the same channel stock/pop/age use, so a rejoining client picks it back up for free | `[MVP]` |

### Phase 11 — Win conditions

| # | Item | Tag |
|---|---|---|
| 11.1 | ✅ `WinConditionSystem`, last in the order so a loss lands on the tick it happens. `Mode.LAST_MAN_STANDING`: own no unit and no building and you are out (`defeated`, one-way); the last player left sets `winner_id`/`match_over`. **Alive-only**, so a corpse or rubble does not postpone the result — but a **foundation keeps you in**, since it holds ground and can still be raised. A one-player world is never decided, and neither is a world with no units or buildings at all (which is what every sim test skipping MapGen runs on) — without that guard an empty world reads as everyone eliminated on tick 1, and `match_over` latches. `ResultScreen` is `PauseMenu`'s sibling with **no Resume**, and stops `SimClock`. Verified against the real `debug_skirmish` map: killing the two-soldier enemy squad wins | |
| 11.2 | **Trophy** and **King of the Hill** are declared in `MatchConfig.Mode` and **decide nothing**. Trophy wants a `unit.dragon_baby` def, a MapGen that gives every player one, and an `is_trophy` flag rather than a hardcoded id; KotH wants the zone as **map** data, a per-player score (deliberately not added — an unwritten field that reaches the HUD is exactly the hole 4.11's counter was), and the minimap ring. **Inert is the safe direction to be unfinished in:** "you lose when your trophy dies", on a map with no trophies, defeats everybody on tick 1. Also unbuilt: regicide (the Celtic heroes would serve), capture the flag, wonder | |
| 11.3 | Mode shown in the skirmish screen and at match start. `MatchConfig.mode` is the field, and the snapshot already carries `mode` so the result screen can name the rule that decided it | |

### Phase 12 — Multiplayer & AI

| # | Item | Tag |
|---|---|---|
| 12.1a | `host_open()` on 0.0.0.0 + `join()`. See §12.1 | |
| 12.1b | LAN discovery, reconnect, lag compensation, desync detection | |
| 12.2a | **PlayTest AI.** See §12.2 | |
| 12.2b | AI difficulty levels and real decision flow — **the part deliberately parked** until the game's balance has been played | |
| 12.3 | Campaign: scripted triggers/objectives on the host-loopback path. **The screen exists as a placeholder since 2026-08-21** and PLAY on the main menu opens it — see §12.3 | |
| 12.4 | Save/load and replays *(replay record/play already exists as a test fixture, 0.7)* | |

#### 12.1 Multiplayer approach — ordered steps for two-device play

**What exists and is unvalidated:** ENet transport, commands up with a peer→player map and
server-side ownership validation, per-player fog-filtered snapshots down, deterministic `MapGen`,
a result screen driven purely by snapshot data, and a proven Android build with the INTERNET
permission. See §1.1 for why the unvalidated part is the argument for doing this before more
features stack on it.

| Step | Work | Est. | Risk |
|---|---|---|---|
| a | `Net.host_open()` on 0.0.0.0 + `join(ip)`, peer lifecycle, player-id assignment | 2–4 h | low |
| b | **The client has no world** (below) | 4–8 h | **high** |
| c | ✅ **DONE 2026-08-21** — 1.6's screen in lobby mode. Went beyond the row: the spec described a lobby that only worked one way (the host learns who arrived, the joiner learns nothing back), so it also gained a **lobby config broadcast and a READY gate** — a joining player sees the host's real map and settings and must agree before START unlocks, and changing any setting cancels every agreement. Slots also became 2–8 with a **CLOSED** role, so the player count and the map size are two numbers. Validated phone↔PC over WiFi. **Colour became a picker on 2026-08-21** (below) | 6–10 h | low, volume |
| d | Match-start handshake: host broadcasts the agreed `MatchConfig`, everyone builds, acks, then the clock starts | 2–3 h | medium |
| e | ✅ **DONE 2026-08-21** — resign is a `ResignCommand` through the ordinary command path, so the server overwrites the player id and it cannot be forged for somebody else; a vanished peer is issued the same command by the host. `WinConditionSystem` now excludes `defeated` players from the standing count, which is what makes either mean anything. Proven by killing a real joiner process mid-match (host showed VICTORY) and by pressing the real Resign button (DEFEAT, "Player 2 won") | 2–3 h | low |
| f | Wire size and packet reliability (below) | 3–6 h | medium |
| g | Two-device bring-up on real WiFi — firewall, IP entry, thumb testing | 2–3 h | medium |

**Order: a → b → d → g → c → e → f.** Front-loads the risk and puts a two-device match you can
see at roughly the halfway point, before the polish.

**(b) is the item with real design in it.** `GameScene._start_match()` and `_preview_placement()`
both read `Net.host().world`, documented as a solo-only exception; on a joining client
`Net.host()` is null, so the scene dies on entry.

**Terrain is a transfer, not a regeneration — corrected 2026-08-17.** This said each client runs
`MapGen` from the shared `MatchConfig` so nothing needs sending, which holds for the hand-built
debug map because it is integer code. 2.4b's generator uses `FastNoiseLite`, whose float maths is
not guaranteed identical between an ARM phone and an x86 desktop — and a host and client that
disagree about where the water is have desynced before the first order, in the one way
`state_hash()` cannot help with, because it reports the divergence without saying why. So
`MatchConfig` carries the `MapData` (20–40 KB via `to_dict()`) and it is sent once at match
start. Certainty for one small message.

The real question is the **placement ghost**, which colours itself by asking the authoritative
world about occupancy and adjacency: a client has the map but not what anyone has built since. It
must be driven from snapshot facts and be **advisory** — the server already validates, so a wrong
ghost costs a refusal, not a desync.

**(f) is measured.** The 2026-08-17 figure of 12,092 bytes was on the 64×64 debug map. Re-measured
2026-08-21 on generated boards with `dev_preview/preview_wire_size.tscn`, per player per tick:

| board | tiles | total | fog | entities | fragments |
|---|---|---|---|---|---|
| 96×96 | 9,216 | 28,768 | 9,224 | 18,512 | 21 |
| 128×128 | 16,384 | 31,768 | 16,392 | 14,368 | 23 |
| 192×192 | 36,864 | 53,928 | **36,872** | 16,024 | 39 |

**The fog half is done (2026-08-21).** It was 68% of the packet on the 8-player board the lobby now
offers, and a function of the MAP rather than the match, so no other saving would ever have shrunk
it — and half the grids were byte-for-byte repeats, since `VisionSystem.VISION_INTERVAL` recomputes
every second tick. Two options were considered, and the drawback of the one taken is worth keeping
written down:

- **Option 1, taken — the client computes its own fog** (`ClientFog`). Zero bytes on the wire,
  forever. Its cost: `EXPLORED` accumulates a tick at a time, and snapshots are
  `unreliable_ordered`, so a dropped snapshot means a thin rim of tiles the client believes it has
  never seen. It corrects itself when anything of yours passes there again. **Fog only** — entity
  filtering is the server's answer and arrives with the entities.
- **Option 2, not taken — the server sends fog CHANGES on a reliable channel.** Tens of bytes
  instead of tens of thousands, and it cannot drift, because reliable delivery means the client's
  grid *is* the server's. Its cost is a second channel with its own ordering and reconnect story.
  **If option 1's slivers ever become a complaint, this is the reinvestment**, and `ClientFog` is
  where it lands — everything above its `apply()` stays as it is.

**This does not move the security boundary**, which is the objection to answer first: the rule is
"the server must not send a client entities it cannot see" (§5.1 step 6), it lives in
`SnapshotSystem._entry_for`, and it still runs on the server. The server still computes every
player's vision, because it still decides what to send them. The grid was only ever a bitmap to
paint. Guarded by a test that compares the client's grid to the server's **tile by tile**, because
two implementations of one circle are two implementations that can drift.

After it: 19,528 / 15,384 / 17,040 bytes — and **snapshot size no longer depends on the board at
all**, so the 8-player map became the *cheapest* of the three.

**Then the entity payload, and it was not what anyone expected.** Only **36 entities are visible**
on the 8-player board and they cost 16,024 bytes — about **445 bytes each**. The problem was never
the entity count, so delta encoding was never the first answer. A field-by-field breakdown
(`preview_wire_size -- --fields`) found that **half of every entry is the names of its own fields**:
248 bytes of a town centre's 472, because `var_to_bytes` writes a dictionary key as a
length-prefixed string every time it appears. Three fixes, none of them a delta:

1. **`footprint` is not sent.** Static content the client derives from `def_id` — a building's off
   its def, a resource's from `footprint_for_size` with the `size_class` already on the wire. Same
   argument that took `vision_range` off it. 68 B per building and resource entry.
2. **`pos` is a `Vector2i`, not `{"x": .., "y": ..}`** — 48 bytes to carry two small integers,
   because the nested dictionary re-encodes "x" and "y" per entry. Twelve. Safe here and
   deliberately not in `MapData`, which notes the opposite: a saved map goes through JSON and a
   snapshot never does.
3. **Shape tables.** Entities come in a handful of shapes, so field names go **once per shape per
   snapshot** rather than once per entity: `updated` becomes `tables` of `{keys, rows}`. Done at
   the **transport boundary** (`Net._broadcast_snapshot` / `_recv_snapshot`), not in `build()`, so
   the simulation still produces readable dictionaries and every other reader is untouched.

| board | start of 12.1f | after fog | after 1 & 2 | after 3 | fragments |
|---|---|---|---|---|---|
| 96×96 | 28,768 | 19,528 | 14,840 | **7,528** | 21 → 6 |
| 128×128 | 31,768 | 15,384 | 11,840 | **6,328** | 23 → 5 |
| 192×192 | 53,928 | 17,040 | 13,080 | **6,824** | 39 → 5 |

Confirmed on the real transport: ENet's own warning went from **18,532 bytes to 4,360**.

**Colour is a PICKER, not a cycle — 2026-08-21.** A colour button used to step the slot to the
next colour nobody else held. Cheap to write, and it made choosing violet out of eight a matter
of pressing five times and watching — worse on a joined client, where every press was a round
trip to the host, so the player was cycling blind through a list they could never see.
`ColourPickerPopup` shows the list. **The rule has not changed, only where it is expressed:** a
colour somebody else holds is not on the grid at all, rather than being skipped by the step.
Active slots only — a closed slot holds no player, so its colour is nobody's, and counting it
would leave two players on an eight-slot board with six colours spoken for by empty chairs.

The wire message now **names a colour** where it used to name none, and the host still holds the
rule: it re-checks the index and **ignores** a collision rather than substituting something,
because a client's idea of what is free can be a moment stale and the re-broadcast that follows
every lobby change is what corrects it. Silently handing somebody a different colour than the one
they pressed would be worse than leaving them where they were.

**The transport mode is settled, and measured rather than argued — 2026-08-21.** `Net` counts
arriving snapshots and reports gaps (ticks are consecutive, so a jump is exactly what went
missing). Phone joined to a PC host over real WiFi, ~90 seconds of play:

    net: 300 of 312 snapshots arrived (3.85% lost) over 325 ticks
    net: 600 of 621 snapshots arrived (3.38% lost) over 634 ticks

**~3.4% lost, and every single loss was one snapshot — never a run.** A lost snapshot is one
100 ms frame of stale state, and the next one is complete, because a full snapshot supersedes its
predecessor and needs nothing from it. Under interpolation that is invisible, which matches the
owner's "snappy" verdict from (g).

**So `unreliable_ordered` stays**, and that is now a decision rather than an inheritance. The cheap
fix — `reliable_ordered` — would remove 3.4% of invisible 100 ms gaps and buy head-of-line
blocking: a retransmit stalls every snapshot queued behind it, turning a loss nobody can see into a
stutter everybody can. Worse, retransmitting a snapshot is *worthless by the time it lands*, since a
newer one describing the same world has already been sent. Reliability is right for a delta stream,
where a lost message corrupts everything after it, and wrong for this one.

That in turn is the argument against finishing §7.2's delta encoding here. The measured per-fragment
loss is ~0.7%, which is what makes the fragment count matter so much: **at this morning's 39
fragments the same link would have dropped ~24% of snapshots, roughly one in four.** Getting to 5
fragments is what made the unreliable choice viable, and a delta would trade that self-healing
property away — the remaining payload is mostly resource nodes, which barely change, so "send
statics only when they change" means replacing the absence-means-invisible rule the view depends on,
and then needing reliability after all. Deliberately **not** done: 6–10 h to make the transport more
fragile.

**Most of this needs no phone.** Steps a, b, d, e and f are verifiable with **two Godot processes
on one desktop** — one hosting on 0.0.0.0, one joining 127.0.0.1 — both scriptable and
screenshottable the way `dev_preview/preview_victory.tscn` drives the real game today. Only (g)
needs hardware and a second pair of thumbs.

**Deliberately not in this batch:** commands are queued for `tick + 1` with no input-delay buffer,
so a remote player's orders land whenever they arrive — fine on LAN, visibly rubber-bandy when
latency spikes. A fixed 2–3 tick input delay is the standard fix, about 2 h, but it changes how
the game **feels** and wants a decision rather than a default.

#### 12.3 The front door, and where PLAY goes — changed 2026-08-21

PLAY and MULTIPLAYER both opened the skirmish screen, and that was the honest consequence of
1.6's design: a lobby *is* that screen with a slot set to Open, so there was one screen and
PLAY had nowhere of its own to lead. What it cost was the front door — either button did the
same thing, and the campaign this table has always had a row for was reachable from nothing.

PLAY now opens a **campaign placeholder**, and MULTIPLAYER opens the skirmish/lobby screen. A
real screen rather than a `NoticeToast` — which is what SETTINGS and HOW TO get — because
those are features with no shape yet and a campaign is a list of missions: this is the frame
that list appears in, so when 12.3 lands it is a body replacing a placeholder.

**The wrinkle, and it is a label rather than a screen.** A solo skirmish is now behind a
button marked MULTIPLAYER. Nothing is unreachable — all-local slots is a skirmish, an Open
slot is a lobby, one screen — but a player wanting a game against the AI presses the wrong-
sounding button to get there. The project owner has the menu art in hand.

#### 12.2 PlayTest AI (12.2a) — ✅ built 2026-08-17

`AISystem` (`src/sim/systems/ai_system.gd`) drives every `SimPlayer.is_ai` player through
`AIPlaytest.SCRIPT` (`src/sim/ai_playtest.gd`). Last in the tick order, which is what makes
it fair: it reads the finished tick and its orders are queued for the next one, exactly like
a player reacting to what is on screen.

**The script turned out to be half of it.** A script is an opening — a sequence of one-off
decisions — and three things a player does *continuously* had to be added as standing
orders, each one found by running two AIs against each other and watching:

1. **Nobody stands around.** A berry bush holds 80 food and takes two gatherers, so a pair strips one in ~16 s and then **retires to idle**. By tick 600 all six villagers were idle and the AI had banked 80 food in a minute.
2. **Unfinished buildings get finished.** A build step reports done as soon as the foundation *exists*, so the script has already moved on — and a builder that dies or is pulled onto another job leaves a foundation nobody returns to. One run ended with an AI owning a foundation house, a foundation watch tower and no barracks, because `TrainCommand` quite rightly refuses a building that is a hole in the ground.
3. **Soldiers keep attacking.** The script's attack step fires **once**, with whatever army exists at that moment — which was the starting scout, because the train step completes when the queue fills and the five swordsmen were still in it. They stood in the barracks for 5,000 ticks. Any idle soldier now goes at the nearest enemy, which also gives the AI the retargeting `CombatSystem` deliberately does not do (4.12).

**And one deadlock, which only a full run could show.** With standing order 1 in place,
*nobody is ever idle* — so every later build and train step starved for labour, timed out and
was skipped. Both AIs finished their scripts having never trained a soldier and the match ran
20,000 ticks to no conclusion. A step may now **pull a villager off gathering**, which is what
a person does; a villager already *building* is never taken, since that is the one job that
does not survive being interrupted.

The original spec follows, and it holds: a deliberately dumb, predictable, rule-based
opponent — explicitly **not** the AI that was parked.
The owner's opening script: two villagers to berries, one to stone, one to lumber, the last builds
a house; then a mining camp by the stone and a lumber camp by the wood; the builder to gold; age
up; two more villagers; the first villager builds a mill and a field; the berry pair moves to the
field with its builder; the newest villager builds a tower near the town centre and then a
barracks a few tiles out; the last builder chops wood; five swordsmen at the barracks.

Design rules:

- **The script is DATA, not code** — a declarative list of steps, so the opening can be retuned without touching the system and a test can assert "by tick N the AI owns a mill".
- **Every step carries a precondition, a timeout and a skip rule.** On a generated map there may be no berry bush within reach, and a script that stalls takes the whole test with it.
- **It logs which step it is on** — the difference between a debuggable failed match and a mystery.
- **It is deterministic** (no `randi()`, no unordered iteration) or it breaks replay and the desync check.
- **It emits ordinary `Command`s only**, which is what makes it a real test of the command path rather than a puppet with privileged access.
- **It ends with an attack-move on the nearest enemy town centre.** Without an ending a headless match never exercises 11.1 or the result screen — and that is what turns this from "the AI plays" into an automated full-match regression test.

Two numbers to watch: 5 starting + 2 trained + 5 swordsmen is **12 population** against a town
centre's 10 plus one house's 5, so it fits with three to spare and a scout eats one — and the cap
is **enforced** now, so overrunning shows up as silent refusals. And the resource steps cannot
assume *where* anything is, since 2.4b puts veins nine tiles out in a random direction: they
resolve "nearest node of kind".

### Phase 13 — Dragons

13.1 Dragon unit: air domain, castle-tier stats, fire-breath AoE + cooldown.
13.2 Dragon Nest POI: guardian dragon, claim-on-defeat, 360 s baby-dragon timer, destructible.
*(The nest is composed entirely from existing gaia props; only the dragon needed bespoke art, and
it is baked.)*

---

## 12. Post-MVP prioritisation

| Candidate | Impact | Effort | Verdict |
|---|---|---|---|
| 4.13 Military units + combat | Very high | Medium | ✅ **mostly done** — siege pack/unpack, hostile wolf, arrow projectiles remain |
| 2.5 Fog of war | High | Medium | ✅ **DONE** 2026-08-17 |
| 4.11 Population cap | Medium | Low | ✅ **DONE** 2026-08-17 |
| 11.1 Win condition | High | Low | ✅ **DONE** 2026-08-17 (conquest; 11.2's two modes declared inert) |
| **Field yield balance** | Medium | Low | ✅ **DONE** 2026-08-17 — see below |
| 2.4b Map generator | High | Medium | ✅ **DONE** 2026-08-17 |
| 1.6 Skirmish screen | High | Medium | ✅ **DONE** 2026-08-17 |
| 12.2a PlayTest AI | High | Low-medium | ✅ **DONE** 2026-08-17 — and it bought an automated full-match test |
| 12.1 Real multiplayer (LAN, 2 devices) | High | Medium | ✅ **DONE** 2026-08-21, a–g, validated phone↔PC on real WiFi — §12.1 |
| 8.2b The minimap's four corner pages | Medium | Low-medium | ✅ **DONE** 2026-08-21 — market working, chat and tech tree as wireframes, settings absorbed the pause menu — §8.2b |
| 5.7 More buildings | High breadth | Low in code; ~70 bakes in art | Art track paces it |
| 9.x Ages & tech | High — the age axis now carries what factions would have | High: four age skins of every building | Batch later |
| **Walls** | Medium | Medium — drag placement, segment choice, 8 orientations, gate pass-through | ✅ **DONE** 2026-08-22 — 22 staged pieces reached the build menu; the art turned out to be staged but never *declared*. See §5.8 |
| 13.x Dragons | The differentiator | Medium (art exists; needs rigging) | Once the RTS is a game |

**Field yield, balanced against Age of Empires 2026-08-17.** It was 0/100/250/400 food per 100
ticks per farmer by age — 4× a berry bush per farmer at age 2 rising to **16×** at age 4, and four
age-4 plots came to 80 food a tick. What came across from AoE is the **ratio, not the numbers**:
AoE2 keeps every food source within a third of every other per villager (berries 0.31/s, sheep
0.33, farm 0.35, deer 0.41), so a farm is 1.13× a bush, and what separates food sources is total
amount, walking distance and safety — never a multiplier on the worker. The absolutes cannot
transfer, since this game's villager gathers 2.5 food/s against AoE2's 0.31. So **0/25/28/32**:
parity at age 2, AoE2's own farm-over-berries edge at age 3, 1.28× at age 4. The ladder is nearly
flat because **AoE's farm upgrades raise a farm's food AMOUNT and never its rate** — a farmer's
throughput is 0.35/s from the first farm to the last, those upgrades exist to stop you rebuilding
farms, and `amount: -1` (an inexhaustible field) had already spent that entire budget. Fields stay
the backbone regardless, being the only renewable food on a map whose whole larder is ~1120 food.

> The rebalance immediately found a real defect: a short last take was charged a **full**
> interval, so an age-4 plot paying 8 units every 25 ticks into a 10-unit basket cost 25 + 25 = 50
> ticks a load against age 2's 40 — **advancing two ages made farming 25% slower**. The old
> numbers hid it because 400 per 100 ticks is 4 units a tick, where a wasted interval is one tick.

---

## 12A. Art track (parallel, asynchronous)

Never blocks gameplay phases. Ordered by visual payoff per unit of effort.

| # | Item | State |
|---|---|---|
| A.1 | Terrain tile set from 0 A.D. ground textures — grass, dirt, sand, shallow + deep water, rock, forest floor, plus `vis.cliff`. All 64×32 exact, no fitting | ✅ — remaining are not tiles: transition/blend edges and shoreline |
| A.2 | Town centre + house, each with foundation and rubble. Foundations and generic rubble keyed by **footprint size** so the rest of the roster reuses them. No damaged tier — 0 A.D. has none, and health is the dot | ✅ |
| A.3 | Villager: 11 animations × **8** directions = 960 frames (8 not 5 — she holds an axe in one hand, so mirroring would swap it) | ✅ — one rebake owed (§13.2 item 9) |
| A.4 | Resource nodes: gold, stone, berry bush, deer + carcass, boar, sheep, wolf, fish, six extra tree species | Largely ✅. Open: tree **size-class variants** and palms (both need variant selection in isobake — no deterministic actor exists), and `vis.farm`, blocked on a 64-instance prop scatter the importer collapses to one |
| A.4a | **Animate the wildlife** — wolf, sheep, cattle. Every animal ships static, and every recipe justified it with "no clip attached, so the quadruped transfer bug never triggers" — **that bug is fixed**, so the justification outlived the problem. Wolf has the richest set and is the only animal needing an attack; cattle has a **Feeding** clip, the one idle that reads as an animal doing something. Deer and boar come free on the same path | Cost is the **per-clip measurement**, not the bake: `location_scale` is not a global constant (the deer death clip measured 0.0319) |
| A.4b | **Two gaia food nodes have no art at all** — `res.cattle` (`cattle.toml` written, unbaked) and `res.bear` (no recipe). Missing, not placeholder | |
| A.5 | UI chrome from the itch.io dragon packs | Largely in use |
| A.6 | **Player colour — prerequisite, not polish** (§2.7 consequence 3). Bake untinted, emit the source alpha as a mask page, tint in a `canvas_item` shader. **Blend mode decided:** neither obvious option works — *multiply* (0 A.D.'s) makes white a no-op and crushes dark colours, compressing the lightness ladder; *luminance-preserving hue transfer* destroys the ladder outright, since every colour inherits the texture's lightness and all eight end up equally light. The answer is the palette colour setting the **base** level with the texture contributing only its **local deviation**: `lit = pc + (lum(tex) - 0.5) * k`, `out = mix(tex, lit, mask)`, `k ≈ 0.8` scaled by remaining headroom so a light colour does not clip flat. **The mask needs its own greyscale page** (~+12% atlas bytes) — the sprite's alpha is already the silhouette cutout, and those are different questions about the same texel. Do not smuggle it into intermediate alpha values, which bilinear filtering will smear | **Must land before A.8** |
| A.7 | Audio: take `audio/{actor,attack,resource,interface,ambient,music}` whole, plus **`audio/voice/latin` and nothing else** (§9.2.1). Nothing baked depends on it | Unblocked, low priority |
| A.8 | Military unit art — ~22 bakes, one hand-picked actor per unit, no per-age variants. **A full re-bake is owed on two counts and they should be spent together:** the corrected actors (§9.2) and the ground-decal strip. `vis.trebuchet`/`vis.trade_cart` stay blocked on isobake's armature picking and its lack of particle support for impact VFX. ~22 against the ~88 four factions would have cost is where the single-civilisation decision actually pays | **After A.6** |
| A.9 | **Dragon + nest** — not bespoke after all: `fauna/dragon.xml` ships with 0 A.D., complete and textured, 9.2 m wingspan; the nest composes from existing gaia props | ✅ — **static**, the model has no armature |
| A.10 | **Building roster, age by age** — ~70 bakes. **The first batch is five buildings, not seventy**: age 1 unlocks only town centre, house, mill, mining camp and lumber camp, which is a complete playable settlement. Age 2 adds eight. Two free savings: composite props are the same gaia assets in all four ages, so bake once and reuse; the five age-3 buildings need only two skins each. Deliberately **not** taken: collapsing ages 1 and 2 (both Celtic, so similar) — it saves ~12 bakes at the cost of the first age transition any player ever sees, which is the entire payoff of the age axis. **Measure all four skins before declaring a footprint** — it is the max across ages and cannot be read off the age-1 bake | In progress |
| A.11 | **Walls and gates** — ~16 pieces across three tiers. Unblocked from the footprint side (all pieces share one footprint, all towers another, across every civ) | See the two findings below |

**Two art findings that cost real time and would cost it again.**

**The rotary mill's grinder assembly is mis-anchored** — wrong position, wrong rotation, wrong
scale, all from one cause. `structures/britons/special.xml` attaches `rotary_mill_grinder.xml` at
`attachpoint="root"`, and the Pyrogenesis importer resolves a nested root attachment against
whatever mesh it imported most recently, then falls through when there is none (already recorded
in `zeroad.py`'s `_KNOWN_MISROOTED_PROP_OBJECTS` for the Athenian shield). A failed attachment
loses position and rotation — and scale too, because `COPY_LOCATION`/`COPY_ROTATION` do not copy
it. **Leading hypothesis, not yet verified:** the scale is lost *one level down*. The grindstone
reads too small **next to the donkey**, which points at the donkeys — they are props-of-a-prop, and
`_normalise_scale` only scales objects with `parent is None`, so a bone-parented nested prop never
receives the ×0.5 while its parent does. An oversized donkey on the grinder's circle would look
both too big and pushed past the wall, which is exactly the reported picture. Needs a Blender
introspection run dumping world scale and constraint targets. **`Aspis_Back`'s fix does not
transfer** — there the mis-rooted object was deleted, because a shield's back is never seen; the
grinder is wanted, so it needs re-anchoring, not dropping.

**Every wall piece needs 8 directions, not 1 — a wall is not a building.** Buildings sit at one
fixed orientation; walls *run*, so every piece must place along either diagonal facing either way.
Applies to `wall_{short,medium,long}`, `wall_gate`, **and** `rubble_wall_*` and
`foundation_*_wall` — a destroyed or half-built segment has to line up with the run it sits in.
**8, not the 4 that seems obvious, because isobake rejects 4:** directions are screen compass
points at 45° steps, so a bare count of 4 does not say *which* four, and the atlas contract
promises all 8 facings resolve to a stored frame plus a flip. `5` would probably work for a
symmetric segment but waits for someone to look at a turntable. And a second claim made at the
same time was wrong: *"4× the frames but not a bigger canvas, since the two diagonals project to
mirror-image boxes"* is true of a **line** and false of a **wall** — rotating 90° **transposes**
the screen bounding box (wide-and-short at S, narrow-and-tall at W), so a wall canvas must clear
**width from the S view and height from the W view**. Ten recipes passed anyway, on generous
sizing rather than on the reasoning holding.

**Still unbaked:** the composite props — 3× `wood_lumber` (lumber camp), 3× `stone_pile_granite`
(mining camp) — need a `[source.extras]` feature in isobake to compose props onto a building. The
dragon nest needs the same one, so it is **one feature serving three entries**.

**Batches run 2-wide** (`-Parallel 2`), not 4 — the ceiling is RAM, since every slot holds a full
Blender scene, and 4 saturates the owner's workstation while they are using it.

⚠️ **Two pieces of shared mutable state while a batch runs.**

**The 0 A.D. checkout.** Baking rewrites source `.dae` files in place (the Pyrogenesis importer's
doing) and `isobake` restores them via `preserve_sources()` — including on failure, but **not if
the process is killed**. An interrupted batch leaves the checkout suspect; check it before the
next run.

**`isobake` itself, which is an *editable* install.** The batch launches a fresh `isobake.exe` per
recipe, so editing isobake source mid-run changes behaviour **partway through the batch**, with
nothing in the logs marking where. **Do not touch `isobake/` while a batch is in flight.**

---

## 13. Standing policies & open items

### 13.1 Standing policies (approved)

- **Third-party open-source code and addons may be used freely.** Requirement: credit only what is actually used, in `CREDITS.md` + `assets/LICENCES.md`, with a licence compatible with an open-source CC-BY-SA art release.
- **Reference engines may be studied for design** (`OpenRA`, `0 A.D.`, `Spring/Recoil`, `Widelands`) — netcode models, data formats, pathfinding. Credit when code or assets are actually taken, not for reading.

### 13.2 Genuinely open

| # | Item | Owner |
|---|---|---|
| 5 | **Second pack mirror.** Primary is settled (`aod.dragoon.co.za`); GitHub Releases is the obvious fallback. Costs nothing to defer — `packs.json` carries a URL *list*, so adding one is a manifest edit | before first public build |
| 7b | **Villager `work_mine` dress distortion** — a dress vertex weighted 100% to `hand_L` drags a fold when the mining pose diverges from the citizen's native ones. Fix is re-weighting or clamping the vertex group at import. Cosmetic, accepted, batched with the post-MVP art pass | post-MVP art pass |
| 9 | ⏸️ **Villager height, DEFERRED by the owner 2026-08-08.** She measures 2.178 m — taller than a stag, the wrong way round — and the fix is one line (`height_m` on the recipe) plus a 960-frame rebake. A `height_m = 1.93` attempt was reverted: the existing bake is confirmed good on device and a working pre-MVP asset is not worth disturbing. **The rebake becomes free** when §9.2.1's re-point to the Briton actor forces one anyway | polish |
| 4b | **`act_enter`/`act_garrison` and `act_exit`/`act_leave`** are two icon pairs covering one concept each — decide whether they are distinct actions (board transport vs garrison building) and reclaim the spares if not | with 4.8 |

**Retired open items**, kept as one-liners because they were expensive to answer: the render
pipeline produces usable sprites (0.9); actor→entity mapping is complete for all 23 buildings, 22
units and 9 resource nodes; icon volume answered by generating them; Compatibility renderer
confirmed on device; quadruped animation transfer **fixed** via a per-clip `location_scale`
correction (the two rigs describe one skeleton ~31× apart, and bone *length* is not a usable
metric — the importer fabricates near-zero lengths); buried geometry **fixed** via
`render.ground_clip`, which had to be a 3D cut at `z = 0` rather than a crop, since `z = 0`
projects to a diamond spanning most of the frame — and it unlocked 0 A.D.'s better ore sculpts,
which are authored up to 64% below the ground plane; buildings re-skin **in place**; the colour
palette is settled (§9).

---

## 14. Risk register

Live risks only. Retired ones are in `b904b76`.

| Risk | Severity | Mitigation |
|---|---|---|
| Art production is the long pole | **High** | Placeholders keep it off the critical path; art track runs async; cheap wins first |
| **Blender 5.x silently breaks the pipeline** — COLLADA import was removed in 5.0 | **High** | Hard-pin **4.5 LTS** (§1.3), supported to Jul 2027. Do not let an auto-update move it |
| **Player colour is baked into the atlas** — one atlas is one colour, and colour is the only thing distinguishing players | **High** | A.6, prerequisite not polish: bake untinted, emit the mask, tint in a shader. Cheap (the mask is the source alpha) but it invalidates every unit bake made before it, so it must land **before** A.8's ~28 military bakes |
| **Accidentally shipping an unlicensed asset** — ⚠ **has MATERIALISED**: a 2026-08-15 run reported **FAIL, 89 problems** across 86 recipes and 44 files | **High** | `licence_audit.py --write` regenerates the recipe table idempotently and clears most of it; the UI assets need provenance decided by hand. The lesson is not that the tool failed but that **a manual gate with no CI degrades silently** — schedule a run once per art batch |
| Scope creep | **High** | §12 governs what gets built |
| **The roster names entity templates and recipes want actors**, so a recipe can silently bake the wrong thing | **Medium** | Not hypothetical: one pass found **nine** wrong recipes plus the sheep and the cattle, every one a plausible-looking actor picked by NAME. Mitigation is the boxed rule in §9.2 — resolve the template to its `<VisualActor><Actor>` and paste **that**. The failure mode is quiet, so it needs a rule rather than care |
| **A 0 A.D. actor can carry art that is invisible in their engine and opaque in ours** | Medium | Ground `<decal>` actors were the proven case, on **413 structure actors**. The class is "art whose correctness depends on the engine compositing it" — expect anything leaning on terrain occlusion, alpha sorting or particles. Mitigation is always the same: bake it, **look at the contact sheet**, and never conclude it is fine because it looked fine in Atlas |
| **The age axis multiplies building art by four** | Medium | A.10 orders bakes **by age**, so a complete age 1 is always shippable rather than four half-skinned ages. Foundations and rubble stay shared by footprint |
| **The age skin lookup gets written as an age special case**, so widening it to factions at 9.5 touches every call site | Medium | §2.7.1: one `(faction, age)` key from the start. Costs nothing now — the field and the JSON entry both exist |
| **The snapshot is not a delta**, and the client currently reads absence as invisibility | Medium | §7.2. A real delta must add an explicit per-entity "lost sight of X" signal that does **not** enumerate hidden ids |
| **Map size drives fog cost linearly — in CPU as well as bandwidth** | Medium | Recorded here as a wire cost; the 2.4b port found it was a **tick** cost first. An 8-player 192×192 map ran at **39.7 ms a tick** against the 5 ms budget, 32 ms of it `VisionSystem` — a full-grid decay per player, a `SimMap.index_of()` call per tile, and a 10 Hz recompute fog does not need. Fixed to ~4–10 ms (see `test_tick_cost.gd`, which now prints the per-system table). Size still governs it: §11.2's `side = 64 * sqrt(players)`, plus the fog delta in §12.1 (f) for the wire half |
| **Per-player work in a system reads as cheap and is O(players × world)** | Medium | Three systems had it — vision's grid decay, and a full entity scan per player in both `PopulationSystem` and `WinConditionSystem`. At 2 players none of it shows; at 8 it was most of the tick. `test_tick_cost.gd` exists to make the next one visible, since the aggregate number never says which system to look at |
| Pathfinding stalls at scale | Medium | Per-tick budget from day one; flow fields in reserve |
| GDScript too slow at 200 units | Medium | Measure on device; targeted GDExtension only if proven |
| Mobile thermal throttling | Medium | 10 Hz sim, pooled views, draw-call budget, sustained-load testing |
| Asset pack download fails / user offline | Medium | Game runs on placeholders; packs are `required: false` |
| WSL/Docker fighting Android USB deploy | Low | §1.2 — native Windows for editor + deploy |

---

## 15. Immediate next actions

1. ✅ **Map generator in the game** (2.4b, §11.2). Still open from it: the **PNG + sidecar save format**, which 2.4c needs. It also found that `terrain.water_shallow`, `terrain.water_deep`, `terrain.rock` and the forest floor were **baked and staged but never declared in `visuals.json`** — the debug map only ever paints grass and dirt, so nothing had asked for them, and a generated map's water would have drawn as the magenta unknown. Four data entries, now wired: exactly the gap the asset seam's totality rule is meant to surface rather than hide.
2. ✅ **Skirmish settings screen** (1.6, §11.1), with PLAY routed through it. Open from it: saved maps (waits on 2.4c), the OPEN slot (waits on 12.1), and the skin.
3. ✅ **PlayTest AI** (12.2a) per §12.2 — including the closing attack-move, so a headless match ends and the win condition is exercised automatically.
4. ✅ **Multiplayer** (§12.1), the whole block a–g, validated on hardware.
5. ✅ **UI batch, 2026-08-21.** PLAY split off to a campaign placeholder (§12.3); the lobby's colour cycle became a picker (§12.1c); the age header's pause button retired into the SETTINGS corner button; and the minimap's four corner buttons became real — a working market, and chat and tech-tree wireframes (§8.2b).
6. ✅ **Walls** (5.8, 2026-08-22). Three tiers, drag placement, two orientations and a lockable gate. Found on the way: the wall art was staged but never **declared** in `visuals.json`, despite two documents saying it was — and the suite found that a run whose leading long piece was unaffordable placed *nothing*, which is why the last piece now downgrades.
7. **The rest of 4.13** — the packed/unpacked siege state machine, the hostile wolf, and arrow projectiles (`vis.projectile_arrow`/`_bolt`/`_stone` are staged and referenced by nothing, so ranged combat currently resolves with no visible cause). Same "staged art the game cannot reach" complaint the walls had, one size smaller.
8. **Then the balancing pass on unit speeds** (`BUGS.md`), which walls were deliberately done before: chokepoints and defence change what "too fast" even means.

**Retired from this list, because the architecture answered it rather than the work:** 12.1b's
*desync detection*. `Net` has no `SimWorld` on a client — it says so outright — and `state_hash()`
appears only in tests. With one authoritative simulation and full snapshots down there is no
second simulation to diverge from. What is still live in that row is **LAN discovery** (typing an
IP was the friction point on hardware in (g)) and **reconnect**; "lag compensation" is the parked
input-delay decision at the end of §12.1.
