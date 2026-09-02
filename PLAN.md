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
- **Phases 15 (scenarios) and 16 (MapMaker) have no IDEA.md counterpart either**, and unlike Phase 0 that is a gap rather than a design: IDEA.md wants rows for both. Their specifications are [scenarios/README.md](scenarios/README.md) and [MapMaker/README.md](MapMaker/README.md), both the project owner's.
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
| UI chrome, fonts | **The project's own**, in `game/assets/ui/` — 103 icons, 27 chrome pieces, New Rocker + Cinzel Decorative. Was itch.io packs in `assets/UI_Sprites/` until 2026-08-30 | Project asset; the two typefaces are SIL OFL. Recorded in `LICENCES.md` |

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
| `work_hunt` | gathering **any food** — `AnimationSystem` maps the whole `food` kind here, berry bushes and carcasses alike, so the name is narrower than the behaviour | ✓ |
| `work_build` | building or repairing | ✓ |
| `work_forage` / `work_farm` / `work_fish` / `work_herd` | unused — food has one clip, above | |
| `attack` | combat | ✓ since 4.13 |
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
| **Snapshot wire size** | **< 64 KB/tick.** Current figures are **§12.1f's table** — 6,328–7,528 bytes across 2P/4P/8P boards, with **zero fog on the wire**. The 2026-08-17 figure that used to be quoted here (12,092 bytes, 4,104 of it fog) was the debug map before 12.1f and contradicted §12.1f in the same document. `test_snapshot_system.gd` pins only the 64 KB ceiling; the per-board numbers come from `dev_preview/preview_wire_size.tscn` |

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

### 3.3 Content delivery — scenarios and maps (new 2026-09-01)

**Campaigns and authored maps are content, not code, and they moved out of `game/` because of it**
(project owner, 2026-09-01: *"this will be downloadeble / shareable content and cannot live in
`res://`"*). The authored source is repo-root `scenarios/` and `maps/`; nothing about them is
inside the Godot project.

**Three roots, in priority order, and the list is data so a fourth is a config line rather than a
code change:**

| Root | When | Writable |
|---|---|---|
| the **dev override** — repo-root `scenarios/` / `maps/`, named in a gitignored local config | **editor runs only**, gated on `OS.has_feature("editor")`, which is true for the headless test and preview runs too | n/a — read in place, nothing is copied |
| **`user://content/`** | every platform, always | yes: install, update, share in, delete |
| **`user://maps/`** | the **player's** own saved maps (2.4c) — a separate directory, listed alongside | yes, and never written by an install |

**Why a dev override rather than a staging copy.** `game/assets/atlases/` is the precedent for
staging content into the project, and it is the wrong one here: a staged copy under `game/` is a
copy that ships in the APK, which is the thing being avoided. Reading the repo folder in place
costs one config file (`tools/isobake.local.toml`'s arrangement, §1.3) and **cannot leak into a
release build**, because an exported build has no editor feature and therefore no override.

⚠️ **THE PRICE OF THE MOVE, STATED PLAINLY: A CAMPAIGN CANNOT BE TESTED ON THE PHONE UNTIL 0.3
LANDS.** `user://` on Android is internal app storage and is not `adb push`-able, and the override
is editor-only — so the delivery path to a device is `AssetPacks`, **the one Phase 0 item still
open**. Everything in Phase 15 is fully exercisable on Windows and in the headless suite; the first
on-device run of a campaign waits on 0.3, and that is a real dependency rather than a footnote.
**Two escapes if it bites before then**, neither of which needs redesigning anything: turn on
Godot's external-data-dir setting for a debug build so `user://` becomes pushable, or add a
bundled root to the list above and seed it into `user://content/` on first run — the loader is a
root list precisely so that stays a one-line answer.

⚠️ **INSTALLED CONTENT IS DATA, SO `AssetPacks` GAINS A SECOND VERB.** Art and audio are **mounted**
(`load_resource_pack()`, which lands them under `res://` read-only, which is right for a texture).
A campaign must be **installed** — copied into `user://content/` after checksum verification — or
it could not be updated, removed or shared. Same manifest, same checksums, different final step,
and `packs.json` should say which of the two a pack wants rather than the client inferring it from
the name.

⚠️ **A PNG OUTSIDE `res://` IS NOT AN IMPORTED RESOURCE.** No `.import` sidecar exists, so `load()`
and `ResourceLoader` cannot open a campaign icon at all — `Image.load()` + `ImageTexture.create_from_image()`
is the route, the same one a saved map's PNG needs (11.3). It costs VRAM compression and mipmaps,
which is nothing at these sizes, and it costs a real decode for a 1920×1080 background — so
backgrounds load **when a campaign is opened**, never all at once behind a selection list. This
inverts a trap recorded on 2026-09-01 and now deleted: while the folder was inside `game/`, the
icons were *invisible until `--import` had seen them*. Out here they are never imported and
`--import` has nothing to do with them.

---

## 4. Repository & project layout

```
AOD_Mobile/
  IDEA.md  PLAN.md  UI_Design.md  CREDITS.md  status_update.md
  assets/UI_Sprites/  assets/Icons/  assets/insperation_pictures/   (+ .gdignore)
  web/                        # project website source
  game_map_gen/               # map generator prototype (2.4b), standalone Godot project
  MapMaker/                   # THE AUTHORING TOOL (Phase 16) - a SECOND Godot project,
                              # PC only, never shipped. Reads game/data + game/assets/
                              # atlases through a local config; writes the two folders
                              # below and nothing else. Spec: MapMaker/README.md
  scenarios/                  # AUTHORED CAMPAIGNS (Phase 15) - one folder per campaign,
  maps/                       # AUTHORED MAPS (16.2)
                              # OUTSIDE `game/` ON PURPOSE, moved out 2026-09-01: this is
                              # installable, shareable content, and anything under game/ is
                              # res:// - read-only once exported and baked into the APK.
                              # The game reads these two directly in an editor run and
                              # `user://content/` on a device. See 3.3 and 11.7
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
**That is all four.** `project.godot`'s `[autoload]` block lists exactly these. Two names this
document used to put in this table do **not** exist and were listed as though they did:
`AssetPacks` is 0.3 and unbuilt (§3.2 describes it; the Phase 0 table already says it is the one
Phase 0 item still open), and `AudioManager` never existed at all — see §7.5.

**None of the four carries a `class_name`**, which would shadow the singleton identifier. This
said "three autoloads", naming `net.gd`, `sim_clock.gd` and `event_bus.gd` as a special case;
`game_data.gd` is the same, so it is a universal rule for autoloads rather than a trio.

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
| `GatherSystem` / `BuildSystem` | Arrival-time work: gather, build | ✅ |
| `ProjectileSystem` | Advance arrows in flight | ✅ 4.13 |
| `WildlifeSystem` | Gaia animals: roam, flee, and the game's only auto-acquire | ✅ 4.13 / 6.1b |
| `HerdSystem` | Livestock changing hands by proximity (`herded_by`) | ✅ 6.5 |
| `CombatSystem` | Arrival-time work: fight | ✅ |
| `ProductionSystem` | Training queues; a finished order is not popped until it spawns | ✅ |
| `AgeSystem` | Age advancement timers | ✅ |
| `MovementSystem` | Path following, waypoint by waypoint | ✅ |
| `SeparationSystem` | Steering push-apart for overlapping units | ✅ |
| `AnimationSystem` | Sets the `anim` view hint | ✅ |
| `DeathSystem` | hp≤0 → corpse/rubble, free tiles, drop cargo, timers | ✅ |
| `PopulationSystem` | Recount `pop_used`/`pop_cap`; owns the cap rule | ✅ |
| `VisionSystem` | Recompute per-player fog — **an ally's entities included since 2026-09-01** (§11.4a) | ✅ |
| `WinConditionSystem` | Evaluate the active mode's victory rule | ✅ |
| `AISystem` | Drive AI players (emits Commands like any player) | ✅ 12.2a |
| ~~`TechSystem`~~ → `TechMods` | Research timers, stat modifiers | ✅ 9.3, **and it is not a `SimSystem`.** The timers turned out to be the production queue's — a research is an entry on it and `ProductionSystem` has counted those down since 5.4, so a second system ticking the same counter would be two owners of it. What was left is the modifiers, which are a pure function of which techs a player holds, so `TechMods` is a static resolver in the shape of `Formation` and `WallPlan` rather than a per-tick pass with nothing to do on 99.9% of ticks |

The State column means *built unless it says otherwise*. It used to carry a bare phase number for
both `TechSystem` and `AISystem`, which read as "scheduled" for one and was wrong for the other.

**The three new systems sit before `CombatSystem` on purpose**, and `wildlife_system.gd`'s header
argues it: a wolf that picks a target this tick bites on this tick rather than the next.

`SnapshotSystem` is **not** in the list — it mutates nothing and crosses the sim/net boundary, so
`SimHost` calls it after each `step()`.

**Everything after `DeathSystem` recounts rather than adjusts.** Population, vision and the win
condition are all derived from what exists at the end of a tick. An incremental counter has to be
decremented from every path an entity can leave the world by, and one missed path is a permanent
drift with nothing on screen to explain it.

**Commands are the only way state changes.** Every one validates ownership server-side; a
`validate()` that fails drops the command silently, so anything the UI offers must be gated the
same way the command is. **All 24 built:** move, stop, gather, build, place-building, place-wall,
upgrade-building, toggle-gate, train, cancel-production, attack, advance-age, set-control-group,
tribute, market-exchange, resign, debug-destroy, debug-set-age, garrison, ungarrison, set-waypoint,
set-stance, ability and **research**. **Later: nothing.** Research was the last name on the "later"
list and it shipped with 9.3 on 2026-08-29; the vocabulary is complete for the MVP as specified,
and the next verb added will be a new feature rather than a hole being filled.

*This paragraph has now twice listed as "later" something already shipped elsewhere in this
document — trade and resign once, then garrison — so it is worth recording what the sweep of
2026-08-29 found: the count read 18 against an actual 21, and stance and special ability came off
the later list the same day (4.12, 4.10). **The failure mode is a list of names with nothing that
reads it**, and the cheap guard is knowing that `Command.from_dict`'s match arms are the real
inventory. This prose is a summary of them and will drift again.*

**Two of these take a shape the others do not, and both are deliberate.** `MoveCommand` carries an
optional `formation` (4.14) — a property of the ORDER rather than of any unit, so nothing is stored
and nothing rides the snapshot. `AbilityCommand` names **one** unit where every other order-issuing
command carries a whole selection (4.10): an ability is aimed and costs a cooldown, so two monks
told to heal one soldier is one wasted monk.

`PathService` wraps `AStarGrid2D` with a **per-tick budget** (`MAX_SOLVES_PER_TICK = 12`, measured:
32 → 9.48 ms, 16 → 5.09 ms, 12 → 4.30 ms against the <5 ms tick). Grid updates are incremental by
dirty rect; the full sweep (~12 ms on 64×64) happens at map-gen time where it hides in load.

**ONE GRID PER `Domain` since 2026-08-23**, not one grid. It held a single land grid, and the note
where `_walkable` hard-coded `Domain.LAND` said why it would have to change: `AStarGrid2D` holds
solidity *in the grid*, not in the query, so a second domain needs a second grid rather than a
filter. Fishing made that real — a ship routed against the land grid sails up the beach. Grids are
built **lazily**, so a land-only map still pays for exactly one, and `rebuild()` pre-builds the
water grid only when the map has water, keeping the sweep in load time. `_sync` re-reads every grid
that exists, because a `mark_dirty` cannot know which domain a new building blocked.

### 6.3 View layer (`src/view/`)

`GameView` owns three layers — `TerrainLayer`, the `EntityViewPool`, and `FogOverlay` — and turns
a snapshot into pooled, interpolated `EntityView`s. **It is handed raw bytes, never a `SimMap` or
a `SimPlayer`**: terrain bytes to draw ground. That is the shape a networked client receives, and
it keeps the tests free of a world.

This used to say "and fog bytes to draw fog", which stopped being true at 12.1f: **fog is no longer
on the wire at all.** `GameView` owns a `ClientFog` and computes its own grid from the snapshot's
entity list, and `FogOverlay` paints that. The security boundary did not move — the server still
decides what to *send* (`SnapshotSystem._entry_for`) — the grid was only ever a bitmap to paint.
§12.1f has the argument and the cost.

`Iso` is **the only place grid↔screen math lives**. Two distinctions that cost real debugging:
`tile_to_world()` is a tile **corner** while the sim stands entities at tile **centres**
(`tile_centre_to_world()`); and `world_to_tile()` **rounds** while `tile_at()` **floors** — the
first un-projects a corner, the second answers "which tile is this point inside".

Picking is **by tile, not sprite bounds** — a 10 m tree's sprite covers six tiles behind it.
Depth sorting moves a footprint's sort point to its **front tile** with `EntityView.draw_offset`
carrying the equal and opposite shift, so the art stays on the centre while the sort is correct.

UI widgets live in `src/view/` alongside it (there is no `src/ui/`): `SelectionPanel`,
`ResourceHUD`, `Minimap`, `ControlGroupsHud`, `AgeBadge`, `IdleVillagerBadge`, `NoticeToast`,
`PauseMenu`, `ResultScreen`, `PlacementGhost`, `SelectionBox`, `ActionFlash` — **plus, and this
list had stopped keeping up:** `HudPanel`/`HudStyle`/`HudAction`/`ActionSlot` (8.2's shared
chrome), `ChatPanel`, `MarketPanel`, `TechTreePanel`, `ColourPickerPopup`, `MapPreview`,
`SkirmishScreen`, `SelectionActions`, `PlacementAdvice`, `Occlusion`, `ClientFog`, `HealthDot`,
`OutlineView`, `EntityPortrait`, `TouchLineEdit`, `DoubleTapDetector`. They read from `EventBus` or
from facts handed in, **never** from the sim, and they are built in `_init()` rather than `_ready()`
so a bare `.new()` is fully wired for a headless test.

Two of those are gameplay-visible and have no phase row of their own, which is why they went
unrecorded: **`Occlusion` + `OutlineView`** draw a player-coloured rim on a unit hidden behind a
building or a tree (owner-requested 2026-08-16, `BEHIND_TILES = 5`, headless-tested), and
**`PlacementAdvice`** is the advisory client-side ghost §12.1 predicted would be needed once a
client had the map but not what anyone had built on it.

---

## 7. Cross-cutting concerns

**7.1 Selection vs commands.** Selection is client-side UI state, never sent — it stays instant
regardless of latency, and a selection in the state hash would desync the moment one player
tapped. Only the resulting `Command`, with explicit `unit_ids`, crosses the wire. Control groups
are the exception: **persisted in `SimPlayer`** via `SetControlGroupCommand` so they survive
reconnect.

**7.2 Snapshots.** Per-player, fog-filtered: `{tick, spawned[], updated[], removed[],
player_state, mode, match_over, winner_id}`. Two corrections this entry had missed, both from
12.1f and both recorded only there: **`vision` is gone** — the client computes its own fog
(`ClientFog`) and no grid crosses the wire; and **`updated` becomes `tables`** at the transport
boundary, a `{keys, rows}` shape table per entity shape, so field names are written once per shape
rather than once per entity. The conversion is in `Net`, not in `build()`, so the simulation still
produces readable dictionaries and every other reader is untouched.

⚠️ **`player_state` IS WHAT A CLIENT KNOWS, AND IT IS RICHER THAN ANY OF THE CODE READING IT
ASSUMED.** Per player, every tick, to everybody: `stock`, `pop_used`/`pop_cap`, `age`, `colour`,
the three age-advance counters, `control_groups`, `researched` and `defeated` — plus
`defeat_reason` since 2026-08-30. **Three of `GameScene`'s polite refusals nevertheless asked
`Net.host().world` and were therefore dead on every joined client**, each with a comment saying
the fix was "a job for the multiplayer phase" (see BUGS.md, 2026-08-30). It was not: the answer
had been on the wire all along, which is exactly why the placement ghost — the one refusal built
on `GameView.stock_of` — already worked for players 2..8. **Before deciding a client cannot know
something, read this list.**

**Not yet a real delta** — everything a
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

**7.5 Audio — BUILT 2026-08-23, and this entry lied about that for months before it.** It used to
say "`AudioManager` exists with a no-op implementation … so gameplay emits
`play_sfx(&"villager.chop")` from day one". There was no `AudioManager` — not an autoload, not a
`class_name`, not a file — and **zero call sites**. The only traces were comments in `audio.json`
and `game_data.gd` citing *this very paragraph*: the code cited the plan and the plan cited
nothing. **Kept in full because it is the clearest example this document has of its own worst
failure mode**, and because the shape of it recurs: a claim survives by being referenced.

**What exists now.** `AudioManager` (`src/autoload/audio_manager.gd`) is a real autoload with a
bus graph, a voice pool, per-id throttling and persisted volume; `MatchAudio`
(`src/view/match_audio.gd`) turns snapshots into sound; `data/audio_map.json` says which sound each
of the 59 unit/building/resource defs makes; `tools/stage_audio.py` fetches the audio from 0 A.D.
and generates `data/audio.json`. 131 sound ids, mapped to 0 A.D. sound groups.

**Five decisions worth not re-litigating.**

1. **The SIM emits nothing.** §4's boundary forbids it loading assets or touching the tree, and a
   sim that made noise would make it during a headless AI-vs-AI run and inside a host's simulation
   of a client it is not rendering. `MatchAudio` **diffs consecutive snapshots** on the view side,
   which as a bonus works identically on host and joined client with no event forwarding.
2. **`task_target_id` stays off the wire.** A villager's work sound is found by *position* —
   nearest node or building within four tiles — because 12.1f's shape tables make a field that is
   present on working units and absent on idle ones cost *more* than the bytes it saves.
3. **`throttle_ms` per id, in the data.** Gather and melee sounds fire per tick; a dozen villagers
   on one forest is a hundred chops a second. 0 A.D.'s own `<Threshold>` does not answer this (it
   culls by gain, not by rate), so the number is ours.
4. **Three sliders, not six.** UI, VOICE and AMBIENT route into SFX, so Master/Music/Effects covers
   the whole mix. This is the answer to what §13.2 item 11 left open.
5. **Silence is legitimate; an undeclared id is not.** An empty `streams` list plays nothing, which
   is what lets the game ship before the audio pack (3.2) — and an id nobody declared calls
   `push_error` once. `GameDataRegistry.silent_sfx_ids()` reports the first case so it is never
   diagnosed by ear.

**What is NOT done:** the fetch is incomplete because 0 A.D.'s LFS endpoint rate-limits to roughly
one object per 20 seconds after an initial burst. Re-running `tools/stage_audio.py` costs only the
difference. Nothing in the code waits on it.

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
Help.tscn                1.8 - HOW TO PLAY, six annotated captures, one to a page
StressTest.tscn   [MVP]  perf harness
Skirmish.tscn            1.6 - skirmish settings, and the multiplayer lobby
DownloadScreen.tscn      3.2
Settings.tscn            never built - 1.5 is an overlay on MainMenu instead
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
  "provides_pop": 10, "garrison_cap": 0,
  "trains": ["unit.villager"], "drop_off": ["food", "wood", "gold", "stone"]
}

// A BUILDING THAT SHOOTS (4.9, added 2026-08-27). `attack` is units.json's block,
// key for key, so both files describe an attack the same way and CombatSystem can
// put both through one damage function. Only three defs carry one, and they are the
// only three with a `garrison_cap` -- not enforced, and it does not need to be: a
// garrisonable building with no attack gains nothing from its archers, and one with
// an attack and no garrison never gains anything.
"building.guard_tower": {
  "hp": 1500, "footprint": [3, 3], "los": 12,
  "garrison_cap": 5,                  // 0 on the other 28, including every wall
  "attack": { "damage": 8, "type": "pierce", "range": 7, "cooldown_ticks": 20,
              "projectile": "vis.projectile_arrow" }
}

// NOT IN THIS FILE, and worth saying so here because it is the obvious place to look
// for it: a building's RALLY POINT (`SimBuilding.waypoint`, 4.8b) is runtime state a
// PLAYER sets, not authored data. There is no `waypoint` key in buildings.json and
// there should not be -- a def cannot know where somebody will want their army to
// gather. It rides the snapshot and `state_hash()`; `SetWaypointCommand` writes it.

// a gatherable building - the field
"building.field": {
  "requires_adjacent": ["building.mill"], "max_per_host_by_age": [0, 2, 3, 4],
  "blocks_movement": false,
  "gather": { "kind": "food", "amount": -1, "slots": 5,
              "yield_per_age": [0, 25, 28, 32] }   // food per 100 ticks per villager
}

// a building that must touch shallow water (6.5). Only the dock.
"building.dock": { "requires_shore": true, "drop_off": ["food"], "age_required": 2 }

// resources.json - `amounts` is indexed by size_class, and since 2026-08-17
// `visuals` is too, so a rich seam and a poor one are different pictures
"res.tree": {
  "kind": "wood", "amounts": [40, 100, 175], "gather_slots": 1,
  "pick_footprints": [[2, 2]]        // TAP box only, never the ground it claims (4.3)
}

// the one node that is not on land (6.5)
"res.fish": { "kind": "food", "domain": "water", "amounts": [200, 200, 200] }

// units.json - a gaia animal. Nobody trains it, so `trainable_at` is empty and
// `validate()` exempts wildlife from the "trainable somewhere" rule (4.13, 6.1b, 6.5)
"unit.wolf": {
  "hp": 40, "speed": 330, "pop_cost": 0, "trainable_at": [],
  "attack": { "damage": 4, "type": "melee", "range": 0, "cooldown_ticks": 15 },
  "wildlife": { "aggro_radius": 6, "roam_radius": 9, "carcass": "res.wolf_carcass" }
}
"unit.sheep": {
  "wildlife": { "aggro_radius": 0, "roam_radius": 0, "flees": false,
                "herdable": true, "carcass": "res.sheep_carcass" }
}
```

The four fields above the `unit.wolf` sample were all added on 2026-08-23 and **none of them
was in this section until 2026-08-23's audit** — `requires_shore`, `ResourceDef.domain`,
`pick_footprints` and the whole `wildlife` block. This is the schema of record; a field that
ships without a line here is a field the next reader has to find by grepping.

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
| `building.wall_wood` + `gate_wood` | 2 | Short/medium/long + gate | `germ/*` · `rome/siege_wall_*` — **all pieces of a tier from one civ**. Age-3 skin re-pointed off `brit/*` on 2026-08-27: the Briton gate declares no animations at all, so it could never open, and every other gate in the game ships `gate_closed`/`opening`/`open`/`closing` |
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
| `unit.trade_cart` | 3 | Market | `units/brit/support_trader` → `units/britons/trader`. **Missing from this table until 2026-08-23** — the def has been in `units.json` all along and only `vis.trade_cart` appeared in the plan, over in A.8 as blocked art, so the entity read as though it did not exist. It has no trade route mechanic yet; the market (8.7) is tribute and buy/sell only |
| `unit.siege_ram` | 3 | Siege Workshop | `structures/iberians/siege_ram` — note the template says `cart` and the actor is `iberians`: **the civ in the template path need not match the civ in the actor path** |
| `unit.ballista` | 3 | Siege Workshop | `units/carthaginians/siege_rock_packed` + `_unpacked` |
| `unit.onager` | 3 | Siege Workshop | `units/romans/siege_onager_packed` + `_unpacked` ✅ |
| `unit.elite_swordsman` | 4 | Castle | `units/athenians/infantry_swordsman_c` — `_c`, not `_e`: 0 A.D. dresses its Athenian champion in the citizen-tier mesh, so this is a visibly *different soldier* from `unit.swordsman`, which is better for a Castle unit |
| `unit.galleon` | 4 | Dock | `structures/ptolemies/quinquereme` — recipe written, unbaked |
| `unit.trebuchet` | 4 | Siege Workshop **and** Castle | `units/han/siege_mangonel` + `siege_mangonel_pivot_packed`. The only entity exercising plural `trainable_at` |
| `unit.dragon` | — | Castle | `fauna/dragon` ✅ |
| `unit.dragon_baby` | — | Dragon Nest, 360 s timer | `fauna/dragon` at 10% scale. **Also what `Mode.TROPHY` needs** (11.2) |

**GAIA — and the split matters, because it moved on 2026-08-23.** This paragraph listed every
animal as a `res.*` resource node and was the last place in the document still describing the world
that way; 4.13, 6.1a, 6.1b and 6.5 had all moved on without it.

**Resource nodes** (`res.*`, gaia-owned, cannot move): `res.tree` · `res.gold_mine` · `res.stone` ·
`res.berry_bush` · `res.fish` (the only node not on LAND — see `ResourceDef.domain`) · and five
**carcasses**, `res.deer_carcass` / `res.wolf_carcass` / `res.boar_carcass` / `res.sheep_carcass` /
`res.cattle_carcass`, which MapGen never places — `DeathSystem` spawns one where an animal dies.

**Gaia units** (`unit.*`, owner 0, nobody trains them): every animal that has to *move* is one,
because a task, a path and a facing all live on `SimUnit` and a node has none of them.

| Unit | Behaviour | Actor note |
|---|---|---|
| `unit.wolf` | hostile, aggro 6, roams 9 → 30 food | `fauna/wolf` |
| `unit.boar` | hostile, aggro 4, roams 5 → 150 food | `fauna/boar` |
| `unit.bear` | hostile, aggro 5, roams 6 → 300 food | `fauna/bear_brown` |
| `unit.deer` | flees, roams 6, no attack → 140 food | `fauna/deer` |
| `unit.sheep` | **herdable**, stands still → 100 food | `fauna/sheep3`, **not** `sheep1` — sheep3's only material is `animal_sheep_no_player_color_a.dds`, which is why it takes no player tint |
| `unit.cattle` | **herdable**, stands still → 500 food | `fauna/zebu_wild`, **not** `cow` — `_wild` matters, 0 A.D. ships wild *and* trainable variants of every herd animal |

Three claims this paragraph used to make are now wrong and worth naming so they are not re-derived:
the wolf is **not** "the only hostile gaia entity" (three are); `res.bear` does **not** lack a
recipe (`bear.toml` exists and `vis.bear` is baked, staged and declared); and none of these needs
`CombatSystem` *added* — `WildlifeSystem` writes the same `set_task_attack` an `AttackCommand`
would, and `Diplomacy` is what let gaia be split by type so a wolf is a target and a tree is not.

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
⚠️ **AND IT STOPPED BEING ONLY AN ART ERRAND ON 2026-09-01.** Campaigns and authored maps moved out
of `game/` (§3.3), so this is now the **only route by which a campaign can reach a phone** — and it
gains a second verb while it is being built: art and audio are *mounted*, a campaign must be
*installed* into `user://content/`, because content that cannot be updated, removed or shared is
not the feature that was asked for.

### Phase 1 — Main menu

| # | Item | Tag |
|---|---|---|
| 1.1 | ✅ `MainMenu.tscn`/`main_menu.gd`. Placeholder buttons answer with a `NoticeToast` rather than doing nothing | `[MVP]` |
| 1.2 | ✅ PLAY → `Game.tscn`; `Boot.tscn` is the main scene | `[MVP]` |
| 1.3 | ✅ `Boot.tscn`/`boot_screen.gd` — title card, 2 s or tap. Distinct from the engine's own sub-second `boot_splash/image`.<br><br>**It was cropped on a phone from the day the new plate landed until 2026-08-30, and the cause was not the stretch mode.** A `TextureRect` defaults to `EXPAND_KEEP_SIZE`, which makes the texture's own size the control's MINIMUM — and a minimum size beats anchors, so `PRESET_FULL_RECT` gave a 1376×768 control pinned to the top-left of a 1152×648 viewport. The plate drew at 1:1 and hung off the right and bottom edges. `expand_mode = EXPAND_IGNORE_SIZE` is the fix; `STRETCH_SCALE` on top of it is the owner's call to fill rather than letterbox. `preview_menus` photographs it and derives the painted region, since no node exposes it | `[MVP]` |
| 1.4 | ✅ `Credits.tscn` — a `RichTextLabel` mirroring CREDITS.md, hardcoded because CREDITS.md lives outside `res://` | `[MVP]` |
| 1.5 | ✅ **DONE 2026-08-23** — settings, as an overlay on the menu rather than a scene of its own: it holds one thing (volume, 8.2b) and a whole screen to get back from is a poor trade for three sliders. Built in code in `main_menu.gd`, not authored into `MainMenu.tscn`, so the editor cannot silently reformat it. `Settings.tscn` in §8 stays unbuilt and this row is why | |
| 1.6 | ✅ **DONE 2026-08-17** — `SkirmishScreen` (`src/view/skirmish_screen.gd`) + `scenes/menu/Skirmish.tscn`; PLAY now routes through it. See §11.1 | |
| 1.7 | **Lobby and multiplayer UI — design references, committed 2026-08-23. Two of the things they show are now built; the rest is not.** Three artefacts, and they are ahead of the systems rather than behind them, which is the useful thing about them.<br><br>**`UI_Design_Lobby.png`** — the hosting lobby. What it shows that still does not exist: a **Faction** column (one civilisation is a locked v1 decision, §1 — this is 9.5 territory), a **Game Type** and **Victory Conditions** picker offering Conquest and **Regicide** (declared and inert, 11.2), a **Map Size** choice (size is currently derived from the player count, §11.2's area rule), and **in-lobby chat** (8.6 is a wireframe with no transport). What it confirms as already right: eight slots, per-slot AI difficulty, the map preview, and the four minimap corner buttons.<br><br>⚠️ **THE TEAM COLUMN IS BUILT, 2026-08-31**, and this row said for eight days that *"there is no team or diplomacy concept at all"*. There is: a one-character `–`/1/2/3/4 dropdown beside each colour swatch under a COLOUR/TEAM/TYPE heading, `MatchConfig.teams` → `SimPlayer.team` → `SimWorld.teams`, read by `Diplomacy.allied` and through it by every hostility predicate (§4.13), with `WinConditionSystem` counting **sides** rather than players (§11.1) and the minimap tinting an ally sky blue (§8.2a). **`–` is on that list because four numbers cannot give eight slots a side each**, so every slot opens unaligned and a free-for-all is what the game plays unless somebody deliberately makes a team. ⚠️ **SHARED VISION LANDED 2026-09-01 AND IS NOW THE ONE EXCEPTION TO THIS LIST** — an ally's eyes are your eyes, in the grid and in the snapshot both. See §11.4a for the one line it took and what it costs, and note that the owner reserved the keep-or-drop decision on it pending play. **Shared control, ally repair/garrison/healing and an ally-aware AI remain deliberately OUT** — the owner's call, 2026-08-31, not an unfinished edge: *"we will not be interacting with any other player units or buildings, no garrison, no repair, no healing… happy with AI attacking opposing teams but not team members."* So an ally's entity taps to SELECT and to nothing else, and every owner-gated command stays owner-gated.<br><br>**`UI_Design_Hosting.png`** — a **server browser**: filters by map type and game type, a game-**version** filter, and a list of named servers with player counts and Playing/Lobby status. **12.1b LAN discovery is the subset of this that is planned**; the rest implies a master server, server naming and version negotiation, none of which is scoped. Worth reading before 12.1b is designed, so that LAN discovery does not paint itself into a corner this cannot grow out of. **A WIREFRAME OF IT EXISTS AS OF 2026-08-31** — `ServerBrowserPanel`, behind the lobby's SERVERS button, disabled throughout and saying so on its own face. Its header is where the four things a real one needs are written down in order, and the one that is genuinely missing from the systems is a host **NAME**: `MatchConfig` carries everything else the columns show, and a list of four IP addresses is a list nobody can choose from.<br><br>**`web/player-colour-ladder.html`** — the research behind the eight-colour palette: CIE `L*` spread so four of the eight separate by **lightness** rather than hue, dichromacy safety per pair, and the argument that A.6's tint must not be a multiply (against white it is a no-op and the player looks untinted). Cross-referenced from §9's palette and §12A A.6, which is where the shader decision lives | |
| 1.8 | ✅ **DONE 2026-08-30 — HOW TO PLAY.** `Help.tscn`/`help_screen.gd`, six annotated captures behind the front door's HOW TO button, which had answered with a "not available yet" toast since 1.1. **The pages carry their own instructions**, painted onto real captures of this game's HUD (`assets/HELP_Gen/` → `game/assets/ui/help/`), so this screen writes no tutorial prose that could drift out of step with the interface — when a control moves, the fix is a new capture.<br><br>**A pager, not a scroll**, which is the one decision worth defending: `Credits.tscn` scrolls because credits are a column of text, and six wide screenshots stacked in a `ScrollContainer` on a handset give each one a sixth of the height it was drawn for. **Built in code rather than authored as a `.tscn`** — the page list is data, and six near-identical `TextureRect` nodes by hand is six places to forget when a seventh capture lands. `test_help_screen` asserts, among the paging, that every page's file is actually staged under `res://`: a `PAGES` table of strings stays true when the images are missing. Order is the reading order, not the delivery order: camera, selection, commands, control groups, panels, ages | |

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

**The preview stands the map on its corner** (project owner, 2026-08-22: *"can we rotate the
map to match the in-game minimap?"*). It used to be a square with north-west top-left, and
then the match opened on `Iso`'s projection with tile (0, 0) at the *top* — so the layout a
player had just picked a start position on arrived turned 45°, and the minimap they would
read for the rest of the match disagreed with the picture they chose it from. The turn is
baked into the **pixels** (`MapPreview.to_diamond`) rather than done with `rotation` on the
Control, which is how `Minimap` does it: that widget owns its own area and centres a square
inside a footprint sized for the rotated bounding box, where this one is a row in a
`VBoxContainer` — and a container lays a child out by its *unrotated* rect, so a rotated
TextureRect would keep its 320×320 slot and spill its tips over the Map and Seed rows. The
dev tool's PNG stays square on purpose: judging whether a river cuts a map in two is a
question about tile space, and both pictures still come from one `image()` so they cannot
disagree about what the map *contains*.

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
| 2.2 | ✅ **Land and water both real, as of 2026-08-23.** This said "land only, in practice as well as principle" and was true only of the debug map — `MapGenerator` has painted rivers, island rims, lakes and oases since 2.4b. Two things closed the gap: `PathService` holds **one A\* grid per `Domain`** (it held one, land's, and a ship routed against it sailed up the beach), and `ProductionSystem` asks for a spawn tile in the **trained unit's** domain rather than always LAND. AIR is still unreachable — the dragon has no rig and `speed: 0` | `[MVP]` |
| 2.3 | ✅ Footprints written into `occupancy`; `despawn()` frees tiles **before** dropping the entity, or occupancy keyed by id would leave tiles claimed forever. A building's `pos` is its footprint **centre** so the view draws every entity identically | `[MVP]` |
| 2.4a | ✅ `MapGen.build_debug_map()` — one start position, fully deterministic, asserted by building two worlds from one config and comparing hashes | `[MVP]` |
| 2.4b | ✅ **DONE 2026-08-17** — `MapData` / `MapGenerator` / `MapValidator` in `src/sim/`, all eight changes applied; see §11.2. The `game_map_gen/` prototype is left untouched | |
| 2.4c | ✅ **FORMAT DONE 2026-09-01** — `MapFile`: `map.png` (terrain, kind in the R channel) + `map.json` (the header and the entity list). **This is what Phase 16's MapMaker writes**, which is why it was promoted ahead of it. Scenarios read it and no longer generate at launch. See §11.3.<br><br>**Still open on this row: the Save Map BUTTON** on the pause menu, and the picker that lists `user://maps/` beside `user://content/maps/`. The format was the blocker and the format is settled; the UI is not built | |
| 2.4d | **Archipelago map type** — one island per player, a few sheep, no predators. See §11.6 | |
| 2.5 | ✅ Fog of war — `VisionSystem` + snapshot filtering + `FogOverlay`. See §11.4, and §11.4a for shared vision (2026-09-01) | |
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

Sizes: 2P 96×96, 4P 128×128, 8P 192×192. *(`map_generator.gd`'s own header still says 184 for 8P;
the code computes 192 and this document is the correct one — the reverse of the usual direction.)*
Generation takes 30–170 ms and every type validates first try. Look at the output with
`dev_preview/preview_mapgen.tscn`, which writes one PNG per type — it is the only way to judge a
map layout.

**It also places wildlife, per START rather than per map (2026-08-23).** Sheep herds, deer herds
and one predator species chosen by map type (`PREDATORS`, keyed by `Type` and read with
`.get(type, {})`, so an unlisted type gets none). Per-start is a fairness choice, not a literal
reading of "two per player": scattering 2n animals over the board hands them all to whoever the
noise favours, where hanging them off each start makes the count exact and identical for everyone
and still lands them at a random angle. Every placer here is **best-effort** — it skips claimed and
unwalkable ground and gives up after a bounded number of tries, because a start hemmed in by water
should yield fewer sheep rather than fail the whole map. Herds are anchored then clumped, with the
anchor retried, because one bad angle loses a herd of seven where it would cost one berry bush.

**Two assumptions in this plan turned out to be wrong, and both are corrected elsewhere in it.**
The map is now **sent** to joining clients rather than regenerated by them (see §12.1 step b),
because `FastNoiseLite`'s float maths is not guaranteed identical across CPUs. And **starting
resources are placed, not sampled**: the validator's first run caught a desert start with one
reachable tree and no food at all, which is exactly what it exists for.

Eight changes were applied on the way in. Six were prototype bugs and are dead history now
that the two codebases have diverged — they live in the code and its tests. **Three of them
were rules rather than fixes, and those still bind anything that touches this generator:**

1. **SIZE IS BY AREA, NEVER BY SIDE.** `side = 64 * sqrt(players)`. Growing the side
   linearly gives 8 players 64× the area of 2, and **fog is one byte per tile per player** —
   a 300×300 map takes one tick from 12 KB to ~100 KB and one player's stream to ~1 MB/s.
   This is a wire-format constraint wearing a level-design costume.
2. **STARTING RESOURCES ARE PLACED, NOT SAMPLED.** The validator's first run caught a
   desert start with one reachable tree and no food at all. Every real generator guarantees
   an opening; hoping the noise put a wood nearby is how a player gets a start they cannot
   play.
3. **CONNECTIVITY IS A HARD GATE, not a warning.** Flood-fill from every start: each must
   reach every other start and a minimum of each resource, else regenerate. It is also what
   makes the generator headlessly testable — "does it look right" needs eyes, "can everyone
   reach everyone" is an assertion. *Being revisited for Archipelago, where the claim has to
   change rather than relax — see §11.6.*

#### 11.3 Save map (2.4c)

⚠️ **THIS IS NOW A BLOCKER FOR PHASE 16 AND WAS PROMOTED BY IT (2026-09-01).** MapMaker's entire
output is a map file, so this section is where the format it writes gets decided — and the tool
cannot be built first without inventing a second format and then reconciling two. §12's table used
to call this "medium impact, no strong ordering"; it is now the first thing Phase 16 waits on.

A Save Map button on the pause menu, so a player who likes a random map — or one someone else made
and shared — can name it, keep it, and pick it again from 1.6. Three things it must get right:

- **It saves the MAP, not the MATCH.** By the time the button is pressed the world is full of buildings and rubble. What gets written is the terrain and start layout the match was **started** with, so `GameScene` must hold on to its map source rather than reading the live `SimMap`. Saving current state is a save *game* (12.4) — the button must not blur the two.
- **`user://maps/`, never `res://`**, which is read-only once exported. The picker lists **authored** maps and **saved** ones together — and as of 2026-09-01 that is `user://content/maps/` and `user://maps/`, not `res://maps/` and `user://maps/`: authored maps left `game/` with the campaigns (§3.3), so both halves of the list are now under `user://`. **They stay two directories**, so installing or replacing authored content cannot overwrite somebody's save and uninstalling it cannot delete one.
- **The PNG is authoritative; the seed is provenance.** A sidecar JSON carries {name, type, players, size, seed, format_version, created}. The seed alone cannot reproduce a map, because any generator change makes the same seed produce something else.

##### ✅ The format, built 2026-09-01, CONFIRMED IN PLAY 2026-09-02 — `MapFile` (`src/data/map_file.gd`)

⚠️ **THE FORMAT IS FIXED BY USE NOW, NOT ONLY BY TESTS, AND THE CHEAP MOMENT TO CHANGE IT
HAS PASSED.** The owner played scenario 3 off a saved map and confirmed it starts, is
*identical across runs* where it used to be re-rolled, and is winnable. Eleven tests said
the round trip is exact; only a played match says the file describes a map the game can
build a world from. Before that confirmation, changing this format cost three committed maps
and one `--force` run — from here it costs that plus whatever MapMaker has been built
against, which is precisely why this section was promoted ahead of Phase 16 instead of
written after it.

**`map.png` + `map.json` in one directory**, written and read by `MapFile.save()` /
`MapFile.load_map()`. The owner's ruling of 2026-09-01 — *"2.4c will guide tool"* — so **this
is what Phase 16's MapMaker writes**, and we revisit it only if the tool finds a shortfall.

⚠️ **`R` IS THE TERRAIN KIND AND IS THE ONLY CHANNEL THAT IS DATA.** `SimMap.Terrain` is seven
values, so a kind fits a byte with room to spare, and reading one channel is exact and
independent of any palette. **`G` and `B` are a cosmetic tint so the file still reads as a map
in an image viewer, and a loader must never read them** — they may be restyled freely, and a
palette-based decode would silently reinterpret every map already saved the first time
somebody changed a colour. That is the trap `directions_reversed` was reverted twice to avoid.
Bytes come from `Image.get_data()` and never `get_pixel()`: a `Color` is floats, and
`6 / 255.0` and back is an off-by-one on a value that indexes an enum.

**Why a PNG rather than `MapData.to_dict()`.** `to_dict()` is the **wire** form and stays
that — Godot's RPC layer encodes Variants in binary, so `terrain` rides as raw bytes. Through
*JSON* the same field becomes the text `"[1, 2, 250]"`, and a 192×192 map is 36,864 numbers:
roughly 150 KB of digits for content that ships in packs and sits in git. **Measured on the
shipped scenarios: 96×96 terrain is ~900 bytes as a PNG.** So the sidecar is `to_dict()` minus
`terrain` plus the header — which works because `from_dict()` already treats an absent
`terrain` as empty, and it means **one encoding of entities, two of terrain, each where it
belongs**.

**The pair must agree about size or the load is refused** — disagreeing means the two files
have been edited apart, and picking one would put every entity on the wrong tile. A
`format_version` that is not this build's is refused rather than guessed, for the same reason.
A map file is untrusted input (packs and a player-writable `user://`), so parsing goes through
`JSON.new().parse()`.

##### ✅ Scenarios stopped generating at launch, 2026-09-01

**The owner's correction:** *"just generate a map and save it for the scenario, not gen one
every time you click the scenario.. it is just a way to get a map once off while i have no
tool to provide you with a valid map."* `MapGenerator` is an **authoring tool**, not a runtime
step.

`ScenarioDef.build_config()` now reads `MapFile` and **never calls the generator**, and a
scenario with no saved map **refuses to launch** rather than falling back — a fallback is how
an unpinned scenario would ship looking exactly like a pinned one. `dev_preview/preview_author_maps.tscn`
is the tool that writes them; it refuses to overwrite without `--force` (a saved map is
authored content under version control) and reads every map back before claiming it wrote one.
The three How To Play maps are committed.

**This closed a live defect, not a tidiness.** Card 15.1 already recorded *"a pinned seed is
not a pinned map"*: `FastNoiseLite`'s float maths is not guaranteed identical between an ARM
phone and an x86 desktop, so a scenario generating at launch could be a **different map on the
player's phone than on the designer's desktop**. `test_the_same_scenario_builds_the_same_map_twice`
used to assert the weaker "same seed and generator give the same map"; it now holds across
machines, architectures and every future generator change.

#### 11.6 Archipelago (2.4d) — a map type where the sea is the map

**One island per player, a few sheep on it, and nothing that bites.** A quiet opening and
a naval midgame: you cannot be attacked until somebody crosses, so the pressure is
economic and the first fight is a landing.

Most of it is cheap, because the machinery landed with fishing and wildlife. Three things
carry the work, and the first is the only hard one.

**1. THE VALIDATOR REFUSES IT BY DEFINITION, and that is the whole design problem.**
`MapValidator` floods once from player 1 and requires every other start to be in that
component (`map_validator.gd:60-68`) — a hard gate, retried `MAX_ATTEMPTS` times and then
surfaced as `meta.problems`, which 1.6 uses to grey out Start. An archipelago fails it
every time, correctly by the rule as written and wrongly by intent.

So the rule has to become **per type**, and the honest replacement is not "skip the
check" — it is *a different connectivity claim*:

- every start reaches **its own** resources by land (the existing `MIN_NEARBY` sweep,
  unchanged, and the thing that actually keeps a start playable);
- every start touches **shallow water**, or a dock can never be built and the player is
  sealed in for the whole match;
- the **water is one body**, so a ship can get from any island to any other. That is the
  archipelago's version of "everybody can reach everybody", and it is a flood fill over
  the water domain rather than the land one — which `PathService` can now answer, since
  it holds a grid per domain.

Nothing else may relax. A player who cannot reach their own gold is broken on any map.

**2. Islands are painted around the starts, not the centre.** `_paint_island` fills deep
water and carves one landmass in the middle; this needs the inverse — `_start_positions`
first, then an island per start. Radius is the constraint and it is set by the validator,
not by taste: `MIN_NEARBY` wants 4 wood, 1 gold, 1 stone and 1 food within 34 tiles of
walking, plus a 22×22 clearing for the base, so an island materially smaller than about
30 tiles across cannot pass its own opening. ~~Bigger than that and the sea stops
mattering.~~

⚠️ **THAT LAST SENTENCE IS REVERSED, project owner 2026-08-30:** *"the archipelago map
type is so small you cannot fit half of the building from age 2 on it."* The validator's
floor is a floor and it is not enough to PLAY on — a disc of radius 18 is ~1,020 tiles, of
which the base clearing takes ~380 and the guaranteed opening's veins most of the rest,
against ~600 tiles of age-2 footprint before a single gap between buildings.
`ISLAND_RADIUS` is **26** (~2,120 tiles) and `MapGenerator.archipelago_side` now derives
the BOARD from it — 128 / 160 / 240 at 2 / 4 / 8 players, against `side_for`'s 96 / 128 /
192.

⚠️ **RAISING THE RADIUS ON ITS OWN MAKES THE ISLANDS SMALLER**, which is the thing to know
before touching either number. `_archipelago_ring_radius` is `side/2 - ISLAND_RADIUS -
SEA_MARGIN`, so a bigger island pulls the start ring inward, which shortens the chord
between neighbours, which is exactly what `_island_radius` caps against: at 26 on the old
96-tile two-player board the cap lands at **12**. The dependency had to be inverted — the
island is the constant and the side falls out of the same relation solved the other way —
not re-tuned. `_island_radius`'s cap is kept as a backstop and should never bind again.

**3. Content is per-type, which the code half-supports already.** `PREDATORS` is keyed by
`Type` and read with `.get(type, {})`, so an unlisted type gets **no predators for free** —
this is the one requirement that needs no code at all. Sheep want a per-type count (the
owner asked for "a few", against the current 2 herds of 3), and deer probably want to be
absent: a herd of seven on a one-base island is most of an opening's food standing still.
Fish should go **up**, since the sea is the point.

**AND ITS WOOD, which was the fourth and was found by COUNTING rather than by playing.**
The 2026-08-30 wood pass (doubled tree amounts plus `_sprinkle_trees`) could not reach
this type from either end — the copse mask is nearly empty on an island, and the sprinkle
lattice is laid over a board that is 92% sea, so it placed **one** tree on a two-player
map. The count came back at **1,971 wood per player at eight players** against a desert's
4,025, on the map whose whole point is a fleet: a galley is 90 wood, a galleon 200, a town
centre 275 and a mill 100. `CONTENT` gained `start_wood` 20 (from `START_WOOD_COUNT`'s 8)
out to 22 tiles, through the guaranteed-opening mechanism rather than a fourth lever, and
the figures are now 5,300 and 4,562. **The lesson is the method: count what you changed,
per map type, before believing a balance pass reached everywhere.**

**Also needed, and small:** `Type.ARCHIPELAGO` appended to the enum (appended, so saved
`MatchConfig.map_type` ints keep meaning what they meant); the literal in `generate()`'s
RANDOM branch, which indexes `[ISLAND, RIVER, DESERT, FOREST]` by hand and silently will
not roll a fifth type; `type_name()`; and the picker list at `skirmish_screen.gd:291`.

**What it exposed that no current map did — and the half of it that is now written.** Every
naval path in the game was untested by play. **Transport load/unload landed WITH the map
type on 2026-08-29**, because an archipelago nobody can cross is four peaceful economies and
no win condition: `unit.transport_ship` carries six, boarding is a tap on your own boat, and
unloading is the same Ungarrison button a castle has.

**It is a second reader of 4.8's garrison rather than a second feature**, and that was
knowable in advance — `SimUnit.garrisoned_in` already held an ENTITY id, already took a unit
off the map without despawning it, already kept population charging for it, and already
refused to place somebody where there was nowhere legal to stand. `garrison_cap` and
`garrison` moved from `SimBuilding` up to `SimEntity`, and the five things that read them
(both commands, `GarrisonSystem`, `SimWorld.garrison_unit`, `DeathSystem._kill_garrison`)
turned out to be asking "what is inside this" and never "what kind of thing is this".

**Two rules a building never had to state.** A carrier may not be cargo, refused in
`GarrisonCommand.validate` so the recursion is impossible rather than merely unusual. And a
landing needs a shore — which is `find_free_adjacent` searching in the PASSENGER's domain,
so infantry come off onto land or do not come off at all. That second one had a trap in it:
the search widens ring by ring **to the whole map**, which is right for a building standing
on the ground its occupants are going onto and catastrophic for a boat, because a transport
in mid-ocean finds a beach somewhere else entirely and teleports the landing party onto it.
It takes a `max_ring` now, and an amphibious landing passes 1.

**Still not written: naval COMBAT.** `unit.galley` and `unit.galleon` have attacks and
nothing has ever fought at sea, so a loaded transport crosses unopposed. That is the next
thing an archipelago will ask for, and it is not what makes the map playable.

⚠️ **AND HERE IS WHAT WHOEVER WRITES IT WILL HIT FIRST, found 2026-08-30 while giving the
galley a volley:** a water unit standing on LAND cannot be ordered to do anything and
reports nothing about it. `AttackCommand.validate()` returns true, `PathService` hands back
an empty route because there is no start node in its domain, the task is retired on tick 1,
and the log says the order was accepted. **The debug map has ZERO water tiles**, measured,
so every ship fixture in the suite and in `dev_preview` has to paint a channel and then
call `PathService.rebuild` — `AStarGrid2D` holds solidity IN THE GRID rather than in the
query, so terrain written behind its back does not exist to pathing.
`test_transport._make_a_coast` is the pattern; `preview_projectiles._flood` is the second
copy of it and also repaints the view's terrain layer, which is built once at match start.

#### 11.4 Fog of war (2.5) — done 2026-08-17

`VisionSystem` writes `SimPlayer.vision`, one `Fog` byte per tile (UNSEEN/EXPLORED/VISIBLE),
recomputed from scratch after `DeathSystem` so a scout killed this tick lights nothing — **every
second tick, not every tick** (`VisionSystem.VISION_INTERVAL = 2`). This said "every tick" and
§12.1f said otherwise; the code's own header was wrong the same way, which is how the two got out
of step without either looking wrong on its own.

**Half of this is now client-side.** The server keeps `VisionSystem` because it decides what to
*send*, and that is the security property. The **grid** is computed on the client by `ClientFog`
and painted by `FogOverlay` — see §12.1f for why, what it costs, and what the reinvestment is if
the cost ever shows.
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

#### 11.4a Shared vision (12.x) — landed 2026-09-01, kept or dropped at the owner's call

**An ally's eyes are your eyes.** One line in `VisionSystem._recompute` —
`Diplomacy.allied(e.owner_id, p.id, w.teams)` where it used to read `e.owner_id != p.id`. It is
the whole change because `allied` answers true for `a == b`, so it *subsumes* the owner check it
replaces, and refuses any id ≤ 0, so gaia grants nobody vision. §1.7 listed this as deliberately
out until today.

**THE COST IS LINEAR IN TEAM SIZE, NOT "ROUGHLY DOUBLE"** — a team of N lights every member's
entities N times, because each member computes the same answer independently. 8 players on
192×192, seed 3, measured by `dev_preview/preview_vision_cost.tscn`:

| layout | tile-writes per recompute | vs free-for-all |
|---|---|---|
| free-for-all (control) | 9,168 | 1.00× |
| 2v2v2v2 | 18,336 | 2.00× |
| 4v4 | 36,672 | **4.00×** |
| 8 on one team | 73,344 | 8.00× |

Free-for-all is **unchanged**, so every existing fixture, every recorded config and every solo
match is provably unaffected — `–` on the team dropdown means team 0, and `allied` refuses it.

**THE METRIC IS TILE-WRITES, NOT MILLISECONDS, AND THAT IS THE POINT.** `lit` is the count of
indices `_reveal` marks, read off the incremental-decay cache; it is deterministic — same seed,
same number, any machine. Wall-clock here is not evidence and this measurement re-proved it: the
free-for-all row timed 3.27 ms before the change and 4.91 ms after, on **provably identical
work**. A ratio of `lit` between two layouts is a fact; a ratio of ms is a rumour.

⚠️ **`test_tick_cost` CANNOT MEASURE ANY OF THIS, FOR TWO SEPARATE REASONS**, both found by
trying, and both of which would have reported the change as free:

1. **`MatchConfig.debug_generated()` never sets `teams`**, and an absent entry means team 0, which
   means no team (see `MatchConfig.teams`). **Every world that factory builds is a free-for-all**
   — so is every fixture in `test_vision.gd` — and shared vision changes a free-for-all by
   nothing at all.
2. **Its per-system table cannot see `VisionSystem`.** `_per_system_ms` calls `process_tick`
   without stepping, so `w.tick` is whatever the last step left — 5 settling + 20 sampled = **25,
   odd** — and `VISION_INTERVAL = 2` makes `due` false, so `_recompute` returns at once, the row
   reads ~0.00 ms and the 0.05 ms cutoff drops it. **The 17.9 ms figure in `VisionSystem`'s own
   header predates the interval and describes nothing that test measures today.**

**THE FIX IF 4× IS TOO EXPENSIVE, designed and deliberately not built: one grid per TEAM rather
than per player.** Allied grids are identical *by construction* — same tiles, same entities, every
tick — so a team of 4 computes the same answer four times. Per-team collapses 4.00× back to
**1.00×**, making shared vision free rather than 4×, and each member's `p.vision` becomes an
assignment of the shared `PackedByteArray`, which is copy-on-write and so costs nothing until
something writes it. Equivalent rather than approximate: teams are fixed at `setup()` and allies
light identical tiles from tick 1, so their EXPLORED sets converge immediately anyway. Not built
because it restructures the sim's hottest system and the feature may yet be dropped — **if the
answer is keep, do this before anything else touches the file.**

Six tests in `test_vision.gd`'s `shared vision (12.x)` section, with a `_with_teams()` fixture
because `before_each` there sets no teams either. The one worth naming is **gaia grants nobody
vision**: a naive `teams.get(a) == teams.get(b)` would fail it, since gaia's absent entry and an
unallied player's entry are both 0, and a wildlife herd revealing the map to everyone on team 0 is
a bug nobody would look for. The other five cover both directions of the sharing, the free-for-all
control, different teams sharing nothing, an ally **receiving** the enemy only your scout can see
(the snapshot half — §5.1 step 6, the security property, not just the grid), and a never-scouted
enemy still being withheld from a whole team.

**Still unmeasured: the on-device figure.** §3.1's 5 ms budget is checked by `StressTest.tscn` on
the reference device; everything above is desktop.

### Phase 3 — Camera & world view

| # | Item | Tag |
|---|---|---|
| 3.1 | ✅ `TerrainLayer` (a real `TileMapLayer`, built from raw bytes). `rendering_quadrant_size = 8` was **measured**, and the answer is backwards from the obvious reasoning: 8 gives 32 draw calls where the engine default 16 gives 165 and 32 gives 280, because a large isometric chunk is a diamond straddling a rectangular viewport. Also fixed a half-tile terrain offset — invisible on uniform grass, obvious at any boundary.<br><br>**Transition blending, 2026-08-23, and generated rather than drawn.** Grass meeting water was a pixel-crisp zigzag of 64×32 diamonds. The owner chose a runtime mask over baked corner art for a reason worth keeping: *"adding more sprites will make theme packs harder later on"* — a theme pack still ships **one diamond per terrain** and gets every transition free. A second `TileMapLayer`, a child of this one so it draws above without touching `GameView`, redraws each tile's higher-priority neighbour through an alpha ramp opaque at the shared edge. `BLEND_ORDER` decides which way the reach goes and it is the natural one: sand washes over a waterline, grass grows down onto sand; reversed, the sea climbs the beach. **47 canonical masks** — four edges plus four corners, with a corner dropped whenever either adjacent edge carries the same terrain, since an edge ramp is already opaque to both its endpoints. That is the classic blob set, and it keeps a strip at 47 columns rather than 256. Two edges take the **stronger** ramp rather than the sum, or a corner is brighter than either edge and draws a wedge where two coastlines meet. Corners were the second pass: a tile meeting another terrain only at a **vertex** got nothing, so every staircase step kept one hard point — and the softened edges around it made that point *more* conspicuous, not less. Known limit: **one neighbour per tile**, since a `TileMapLayer` holds one cell per coordinate, so where three terrains meet the strongest wins and the third join stays crisp | `[MVP]` |
| 3.2 | ✅ Edge-swipe zoom on either strip, 0.6–2.0, **multiplied not added** — a fixed step per pixel would crawl at 2× and leap at 0.6×. The gesture is decided on touch-down and held until release | `[MVP]` |
| 3.3 | ✅ `CameraRig`. **Clamping is two rules**: the centre stays on the map DIAMOND (clamped in tile space, where it is an axis-aligned box) and then the viewport stays inside the projected box. Box-only clamping is what `Camera2D.limit_*` does, passed every unit test, and still left a screen ~85% void at the west corner | `[MVP]` |
| 3.4 | ✅ Double-tap minimap → centre on own town centre | `[MVP]` |
| 3.5 | Camera follow selected unit | |
| 3.9 | ✅ **Occlusion outlines** (`Occlusion` + `OutlineView`, owner-requested 2026-08-16). A unit hidden behind a building or a tree draws as a player-coloured rim instead of vanishing. **Recorded late** — it shipped with no phase row of its own, which is why the §6.3 widget list and §7.3 both described the depth sort as though nothing had been added on top. Three conditions, all needed: behind it by the same comparison the depth sort itself makes, within `BEHIND_TILES` of the footprint, and inside its **screen column** — a unit outside the `(x − y)` band is beside the thing on screen rather than behind it, however close in tiles. `column_pad_for` and `reach_for` derive the band from the art's own measured metres, which is why a one-tile oak pads by 3 and a fitted 4×4 seam by 1 | |
| 3.10 | ✅ **`PlacementAdvice`** — the advisory client-side ghost §12.1 predicted would be needed once a client had the map but not what anyone had built on it. Also recorded late, and its own header cites 12.1b back | |
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
| 4.2 | ✅ `PathService` on `AStarGrid2D` with a per-tick budget, plus `SeparationSystem` — pushes overlapping units apart, visiting units and pairs **sorted by id** so every client resolves the same overlaps in the same order. A push is capped under half a tile and dropped if it would land on impassable ground. Diagonals do not cut corners past a blocked tile. **A walker owes the whole push and a stander none of it** (2026-08-29), sideways across the walker's heading and capped at its own `speed`, so a passer-by steps around a working villager instead of barging her off her node; two walkers and two standers still split evenly. ⚠️ **Routes are still planned as though the map were empty** — units are not in the grid, and true local avoidance is short of RVO by design (BUGS.md) | `[MVP]` |
| 4.3 | ✅ `Selection` (client-side; a selection in the state hash would desync the moment one player tapped), `InputRouter` taps, selection ring, panel from `units.json`.<br><br>**Tap targets, 2026-08-23.** Picking goes by the tile under the finger and still does — but the *art* is not drawn on that tile, which is the whole complaint. Two mechanisms, and they are what SHIPPED after a false start (below):<br>1. **`ResourceDef.pick_footprints`** — a tap box separate from the ground footprint, read by `GameView._covers` and nothing else. `res.tree` sets 2×2 and still **claims one tile**, so a forest stays walkable; `centre - footprint / 2` floors, so an even box leans up-screen where the art is.<br>2. **`TAP_REACH_PX` (24 px)** — a tap landing on **bare ground** falls back to the nearest one-tile *resource node*'s **artwork**, measured to the ground point lifted by half the visual's `height_m`. Never units: a mis-tap near a fight must not turn a retreat into an attack. 24 px is measured against the tile — adjacent centres are 35.8 px apart, so the reach can never cross into a neighbour's.<br>Ranked **unit > standing on ground it holds > merely reaching**, which is what stops two trees a tile apart answering for each other.<br><br>⚠️ **A third mechanism was built and reverted the same morning, and the reason is worth keeping.** It replaced both of the above with `Occlusion.hides()` — *"if the art hides that tile, tapping it is tapping the art"* — reusing the outline band's own `{rect, pad, reach}`. It reads well and it was worse: `hides()` answers *"what do I obscure **behind** me"*, which excludes the node's own rect and everything `is_in_front` of it, so **a tree could not be picked from its own roots** — and a different tree further down the slope had that tile squarely in its canopy column and won it. Tapping one tree gathered another. Reverted in `5de8d12`; do not reach for it again without solving the roots case first.<br><br>**The ring is two shapes, 2026-08-29** (owner: *"the green circle when selecting units don't look good on buildings"*). A **building** traces its footprint SQUARE — the same four corners `PlacementGhost` draws, sized from the SIM's rect — so what was ghosted is what comes back selected; everything else keeps the ellipse, sized from the VISUAL's measured extent, because a villager occupies 0.6 m and not the tile she stands on. The two rects genuinely disagree and `GameView._ring_ground_m` is where the split is written | `[MVP]` |
| 4.4 | ✅ `GatherCommand`/`BuildCommand` reuse the walk-there machinery; `MovementSystem` advances **any** unit with a route left rather than only ones tasked MOVE, so GATHER/RETURN/BUILD travel for free | `[MVP]` |
| 4.5 | ✅ `GameView.tap_action()` decides what a tap means from pure facts; `ActionFlash` shows which order fired. This closed a real gap: gather and build existed sim-side and **nothing in the view had ever dispatched them** | `[MVP]` |
| 4.6 | ✅ Health dot, positioned off the visual's declared `height_m`, sharing thresholds with the panel through `HealthDot.color_for()` | `[MVP]` |
| 4.7 | ✅ `DeathSystem` — corpse for 70 s, `decay` for the last 10 s, then `despawn()`. `SnapshotSystem` gained a **real** `removed[]`, the first thing in MVP that despawns mid-match | `[MVP]` |
| 4.8 | ✅ **Garrison** (2026-08-27). Tap your own tower or castle with units in hand and they walk in: `GarrisonCommand` → `Task.GARRISON` → `GarrisonSystem` admits each one as it reaches the footprint, the same order-then-arrive split `BuildCommand`/`BuildSystem` uses. `UngarrisonCommand` names a **slot** or `ALL`.<br><br>**`SimUnit.garrisoned_in` is the first field in the project that takes an entity off the map without despawning it**, and what that means is worth stating exactly: it stays in `entities`, so `PopulationSystem` keeps charging for it (hiding fifteen units in a castle must not buy fifteen free villagers); it leaves `SpatialHash`, so nothing can find, target or tap it; and it is **skipped by `SnapshotSystem.build` entirely**, which is where "removed from the world map" actually happens. That last one buys three things for one line — the client releases the sprite, `retain_only` drops it from the selection, and `ClientFog` stops lighting a circle around a unit that is indoors. A view-side "draw it invisibly" would have had to do all three by hand and would have left it tappable.<br><br>**Who: only the two towers (5) and the castle (15)**, on the owner's ruling. `garrison_cap` had been declared on all 31 buildings since 0.4 and **read by nothing**, carrying IDEA.md 4.9's sketch (town centre 5, tower 10, castle 50) — so town centre, barracks and monastery went to **0** alongside the walls. A villager under attack therefore has nowhere to hide; that is deliberate.<br><br>**Heal 1 hp per 5 ticks** while inside, as `w.tick % 5` rather than a per-unit counter — cheaper, and one less field two hosts could disagree about. **The garrison dies with the building** (no auto-eject), and `DeathSystem._kill_garrison` puts each unit OUT before killing it, because a corpse has to be somewhere and a garrisoned unit's `pos` is stale by design.<br><br>Wire: `garrison_count` + `garrison` (def ids) on **every** building, empty for the 28 that hold nobody, because a field present on some and absent on others splits every building into two wire shapes (12.1f). Both are in `_remembered`'s strip list — how full an enemy castle is prices its shot. | |
| 4.8b | ✅ **RALLY POINTS** (project owner, 2026-08-27, immediately after 4.8: *"happy for current ejection if no waypoint is set, if a way point is set the ejected units will queue a walk to destination"*). `SimBuilding.waypoint`, sentinel `(-1, -1)` because tile (0, 0) is real. Set by **selecting one of your own buildings and tapping bare ground** — the genre-standard gesture, and it cost nothing because that tap previously did nothing but clear the selection. Shown as a `WaypointFlag`: a procedural pole-and-pennant in the player's colour, drawn only while its building is selected, so eight rally points never become eight permanent flags. No art request — the owner's call was *"use shape placeholder"*, the same one `ActionFlash` and `PlacementGhost` already make.<br><br>**IT COVERS TRAINED UNITS TOO, on the owner's call**, and that is the half that makes it worth having: a new archer appearing behind the archery range is the identical defect for the identical reason (`find_free_adjacent` sweeps the footprint's top edge, so anything leaving a building appears *up-screen of it*, behind the art). `ProductionSystem`'s header had been calling that spot "a full rally point" since 5.4 without there being one. **`SimWorld.send_to_waypoint` is one implementation with two callers** — `ungarrison_unit` and `ProductionSystem` — for the reason `diplomacy.gd`'s header exists.<br><br>**The sweep order itself was NOT changed.** It affects every building in the game; a rally point makes it opt-out per building instead, which is much the cheaper fix.<br><br>Three things that fall out rather than being special-cased. **An unreachable rally point is self-correcting**: `PathService` answers with an empty route, `set_path([])` retires the task, the unit stands where it came out — which is exactly the old behaviour, and it is what stops a **dock** with a landward flag walking its fishing ships onto the beach (a real bug once, 2026-08-23: *"boats spawn and sail on land, its very funny"*). **A garrison killed with its building is not sent anywhere** — `ungarrison_unit(…, send = false)` from `DeathSystem`, because those units are put out so their corpses have somewhere to be. And **the gesture cannot fire with any unit selected**, since the movable-selection test comes first, so no mixed selection can turn a move order into a rally point.<br><br>**An enemy's rally point is the only piece of pure INTENTION on the wire**, and it is the one thing `_entry_for` filters per-owner: `_without_the_rally_point` **blanks** it rather than erasing it, because erasing would give own and enemy buildings different field sets and split every building into two wire shapes (12.1f). `_remembered` erases it outright, being already its own shape. **CLEARED WITH THE STOP BUTTON** (owner, same day: *"resuse stop action button to clear waypoint with building selected"*). Stop means two things now, chosen by the selection — halt these units, or take this building's rally point down — and they cannot collide, since `movable_selection()` is units-only and `waypoint_target()` demands exactly one building. Reusing the verb is what made it affordable: the castle's row was already on its eighth and last slot. The cost, recorded because it is now a standing trap: **`repair` moved to LAST in `_building_actions`**, so a castle with a rally point (9 against `MAX_ACTIONS`' 8) sheds the disabled placeholder rather than `destroy`. The next verb added there drops a real command. | |
| 4.9 | ✅ **Defensive garrison damage bonus** (2026-08-27) — and it required giving buildings an attack at all, which nothing had. `BuildingDef` gained UnitDef's five attack fields *name for name*, reading the same nested `"attack"` object, and `CombatSystem.process_tick` gained a second branch. `_damage_against(w, target, def: UnitDef)` was split so `_damage_after_armour(w, target, damage, type)` serves both.<br><br>**Half of each garrisoned archer's damage, floored, added to the building's own shot once per swing** — so fifteen archers in a castle are one heavier arrow every two seconds, not sixteen arrows. **"Archer" is `attack.range > 0`, not a list of ids**: the owner named archers as adding and pikemen/swordsmen as not, and every melee unit in the roster declares `range: 0`, so the data separates them and nobody maintains a list. Integer division, for market.json's reason.<br><br>**An empty tower still defends** (owner's choice between the two readings). Numbers: watch 6/range 6, guard 8/range 7, castle 12/range 8, all cooldown 20 and all firing `vis.projectile_arrow`. **The range ladder is the design content**: infantry (archer 4, crossbowman 5) is out-ranged by every tower, and **siege (ballista 9, onager 10, trebuchet 12) out-ranges every tower**, which is the only counter to a loaded castle that does not cost an army. Ranges are set against our own roster, not converted from 0 A.D., whose archer reaches 18 tiles against our 4.<br><br>**A BUILDING MUST AUTO-ACQUIRE, and 4.13's rule against it does not apply.** That rule is about units guessing their own fights; a building cannot be ordered to attack anything, so auto-acquire is the only way the data on the def can ever mean something. The two mechanisms share no code.<br><br>⚠️ **`Diplomacy.is_enemy` IS THE WRONG PREDICATE HERE and shipping it was a real bug**, caught by `preview_garrison` and not by 60 green tests. It answers *"may I attack this"* — and for a sheep the answer is yes, because hunting is how a deer becomes food (6.1a). So a watch tower shot the livestock, and since a **herded** sheep is still gaia's (`herded_by` is deliberately separate from `owner_id`, 6.5), a player's own flock grazing past their own tower was slaughtered by it. It presented as something else entirely: nearest-target-wins meant the tower spent every shot on an animal two tiles away and never touched the raider five tiles out, so it read as a tower that did not work. `CombatSystem._is_at_war_with` is the fix — an enemy player's units always, a gaia animal only if `aggro_radius > 0` (wolf, bear, boar carry one; sheep, cattle, deer are 0), so a bear in the settlement is still shot and the flock is not. **This is exactly the distinction `AISystem._nearest_enemy` records having kept its own copy for.** | |
| 4.10 | ✅ **Special abilities + cooldowns** (2026-08-29). `AbilitySystem`, `AbilityCommand`, and an `ability` block on `UnitDef`. **Two units carry one, and both were promised before they existed**: the MONK heals (IDEA.md 4.6's *"healed by a friendly healing unit"*) and the DRAGON breathes fire (13.1's *"area damage"*). So this is two sentences arriving rather than new design, which is also why it is these two and not a set invented to fill a system.<br><br>**THE MONK HAD NO VERB AT ALL BEFORE THIS**, and that is the strongest argument for the shape it took: 100 gold, `attack.damage 0`, no `gather_rate` — the one unit in the roster that could be trained and then only walked about. 6 hp per 20 ticks, range 4, and it **keeps working until the target is full** rather than needing a press per tick.<br><br>**`id` IS THE SWITCH AND `effect` IS THE BEHAVIOUR**, kept apart deliberately. One `amount` field cannot mean "hp restored" for one and "damage dealt" for the other unless something says which, and keying that off the id would make every future ability an arm in `AbilitySystem` instead of a JSON entry. There are exactly two effects, `heal` and `damage`.<br><br>**The same order-then-arrive split `BuildCommand`/`BuildSystem` uses**: `Task.ABILITY` is a travel task, so a monk told to heal somebody across the square walks over. Leaving it out of `is_travel_task()` is the exact failure `set_task_garrison` hit in 4.8 — PathService drops the route and the unit stands in that task forever — so there is a test on the predicate itself.<br><br>⚠️ **`ability_target_tile` IS THE AIM AND `task_target_tile` IS NOT.** `set_path` rewrites the latter to wherever the route could actually end (4.1), so a breath weapon reading it lands on the dragon's own feet. Two fields, and the second exists only for this.<br><br>**Not built, and named so nobody looks for them:** no resource cost (IDEA.md 4.10 allows one; nothing in the roster has one, and the place it goes is `AbilityCommand.validate`), no auto-use by anything including the AI, and **no friendly fire** — the blast tests the caster's own war predicate, so a dragon cannot burn its own army *or* a herded flock (4.9's bug, at a third mechanism). **There is no fire-breath ART**: `vis.dragon` has one clip, `static`, and `asset_request.md` [P7] carries the ask | |
| 4.11 | ✅ Population cap, **enforced**. See §11.5 | |
| 4.12 | ✅ **Stances** (2026-08-29). `StanceSystem`, `SetStanceCommand`, `SimUnit.Stance` and `guard_post`. **`CombatSystem`'s header refused auto-acquire for four phases and named this row as where it would come from** — so read the split carefully, because it is what kept the promise cheap: `StanceSystem` decides whether an IDLE unit starts a fight and hands it over as an ordinary `Task.ATTACK`, and everything in `CombatSystem` still only ever *resolves* a fight somebody asked for. There is no second combat path.<br><br>**Four stances.** AGGRESSIVE takes anything hostile inside its own `los` and chases without a leash. DEFENSIVE takes anything within `GUARD_RADIUS` of the spot it was standing on, chases exactly that far, and **walks back to that spot**. STAND_GROUND takes anything inside its own attack range and never takes a step. PASSIVE is today's behaviour.<br><br>**THE DEFAULT IS DERIVED, NOT AUTHORED** (project owner, 2026-08-29: *"fight back, chase a little"*). No unit in `units.json` declares a stance; `SimUnit.default_stance_for` reads three fields already there. DEFENSIVE for a fighter, PASSIVE for **a worker** (`is_worker()` — a villager who downs tools to chase a scout has abandoned an economy, and at damage 3 against 30 hp she loses), **a packing siege engine** (`packs()` — 4.13 prices a deploy at 3–8 seconds each way, so one that volunteered would spend the match folding and unfolding) and **anything with no attack** (the monk, the trade cart — a stance would send them to stand next to something they cannot hurt).<br><br>**`GUARD_RADIUS` IS ONE NUMBER FOR BOTH THE SIGHT AND THE LEASH**, and that is a decision rather than a saving: a defender may fight anything it could have noticed from its post. Two constants would let them disagree, and every way they can disagree is a bug — a shorter leash makes a unit acquire and abandon on consecutive ticks, a longer one lets a target back a defender off its post one tile at a time. 5, measured against the range ladder: longer than every infantry reach and shorter than every tower's, so a defensive line does not walk out from under its own cover.<br><br>**`guard_post` DOES TWO JOBS AND THAT IS WHAT KEEPS IT TO ONE FIELD** — it is both the tile owed a return and the flag saying "this fight was my own idea". `set_task_attack` grew a `keep_post` parameter, **false for every ORDER and true for every CONTINUATION**: an `AttackCommand` drops the post so a soldier sent across the map is never recalled, while `_close_in` and `_reacquire` keep it so a chase does not forget where it came from.<br><br>⚠️ **ONLY AN IDLE UNIT ACQUIRES, so there is still NO RETALIATION.** A unit gathering, walking or building does not reconsider, whatever its stance — which is what guarantees no stance can countermand an order the player gave, and is also the half a player is most likely to expect and not get. Noticing being hit would mean plumbing an attacker through `take_damage`, which `WildlifeSystem` records refusing to do (it watches hp instead).<br><br>**Gaia is skipped outright.** `WildlifeSystem` already owns every fight an animal picks through `aggro_radius`, and two mechanisms answering "does this thing attack unasked" is the duplication `Diplomacy`'s header is a standing warning about. `_is_at_war_with` is **called** from `StanceSystem`, not copied, so no stance can shoot the livestock | |
| 4.13 | ✅ **mostly** — `CombatSystem`: walk to the target, stand at reach, strike on cooldown, damage after matching armour with a `MIN_DAMAGE` floor (armour must blunt an attack but never make a defender invulnerable to a whole class, because nothing on screen would explain it). Reach is measured to a **footprint**, not a centre, or melee could never touch an 8×8 building. Deliberately **no auto-acquire and no retaliation** — a unit fights what it was ordered to fight, since guessing means every villager charging the first enemy that walks past (that is 4.12). **Projectiles landed 2026-08-22** — `SimProjectile`, `ProjectileSystem`, three atlases wired: the shot spawns at the attacker, flies, points one of eight ways and despawns on arrival, and it carries **no damage** (the blow has already landed; this is only what shows where it came from). What it looks like is a fence post, because both shafts are baked standing on end — art side, `asset_request.md`.<br><br>**Hostile wildlife closed this out on 2026-08-23** and needed no new combat code, only a new way in: `WildlifeSystem` writes the same `set_task_attack` an `AttackCommand` would and CombatSystem never learns that nobody ordered it. What it did need was `Diplomacy`, because "owner 0 is neutral" was a fair reading of the world until something neutral bit somebody — gaia owns the trees *and* the wolf, so hostility had to split gaia by **type**: a gaia unit is fair game, a gaia node is scenery. That predicate replaced four separately-written copies of `owner_id != 0 && owner_id != mine`. **`AISystem._nearest_enemy` deliberately kept its own copy** — it asks "who am I at war with", not "may I attack that", and `_issue_attack` sends the whole army at the answer, so routing it through `Diplomacy` would march the AI off to hunt bears.<br><br>**TEAMS (2026-08-31) ARE THE SECOND THING THAT REACHES ALL OF THESE**, and `Diplomacy.allied(a, b, teams)` is the one place the rule is written; every predicate above now folds its `owner_id == mine` clause into a call to it. Two things about that are worth carrying. The team table is a **required argument with no default** — a call site that was not updated is a parse error rather than a hostility rule silently off in one place, which is §12A's `if Net.host() != null and <rule>` failure in another costume. And **0 is the ABSENCE of a team, not a team everybody shares**: two unaligned players both read 0, so a rule written as "equal teams are allies" turns the entire back catalogue of fixtures into one alliance that can never resolve a match; gaia is guarded separately for the same reason, having no row at all. ⚠️ **The two predicates that are deliberately SPLIT — `StanceSystem._may_start_on` and `AbilitySystem._is_hostile_to` — each keep their own owner clause for BUILDINGS**, correctly, since a building is never gaia's. Both were missed on the first pass, and the symptom is precise: an aggressive soldier opening fire on an ally's barracks while doing exactly the right thing about their soldiers. A predicate split in two for a good reason has two places to change, and the half carrying the good reason is the half you read.<br><br>**CLOSED 2026-08-28 by the packed/unpacked siege machine.** `SiegeSystem`, `SimUnit.packed` / `pack_ticks_left`, and `UnitDef.packing` -- the ballista, onager and trebuchet travel as a wagon and fight as an engine, and can never do both. **`packed` flips the instant a transition starts and `pack_ticks_left` says it is not usable yet**, which is two fields each meaning one thing: the art changes at once so the player sees what it is becoming, and the 3/5/8 seconds is the cost. **Speed is DERIVED every tick** rather than gated in the walker, so `MovementSystem` needed no change at all -- and that also fixed something quietly broken since 4.13: all three carried `speed: 0`, nothing refused them a move order, so one sent across the map took a route and held it unwalked forever.<br><br>**AUTOMATIC, AND THAT IS A DESIGN CALL.** AoE2 makes the trebuchet's pack a button; here an order implies its own state. This is a phone, `SelectionActions` is already at `MAX_ACTIONS` on the castle, and with no auto-acquire (above) a deployed engine with nothing ordered would just be a wagon standing in a field with its legs out. The cost is still paid at both ends, which is the point: shifting a trebuchet two tiles is sixteen seconds of not shooting.<br><br>It waited on art from 2026-08-22 and the wait was right. Every siege atlas staged was the *unpacked* pose, so the machine could have been written at any time and there would have been nothing to see -- two ids resolving to the same picture prove the transition happened without proving it happened the right way round. `preview_siege` is what settles it, and its first run photographed the wrong place: `get_viewport().get_texture()` returns the frame already drawn, so a camera move and a screenshot in one step photograph where the camera used to be. | |
| 4.14 | ✅ **Formations** (2026-08-29). `Formation` — pure static integer arithmetic over a list — plus one field on `MoveCommand`. Line, grid, vee and box, which is **not a choice made today**: `SelectionActions.FORMATIONS` has listed those four as disabled placeholders since 4.3, and the constant is now literally `Formation.SHAPES` so the menu and the sim cannot come to disagree about which exist.<br><br>**A FORMATION IS A PROPERTY OF THE ORDER, NOT OF THE UNIT**, and that is the decision the whole phase rests on. Nothing is stored on `SimUnit`, nothing rides the snapshot, and a formation cannot be left half-applied after a unit dies — the shape exists only for as long as it takes to turn one tapped tile into one destination each. Which shape is *selected* is a client-side preference living in `SelectionPanel.active_formation`, exactly as the selection itself is.<br><br>**Two halves, and the second is what makes it look right.** The shapes are the easy part; handing slots out in id order marches the army through itself. Units and slots are both ranked along the formation's own ACROSS axis, so whoever starts leftmost ends leftmost, **with a unit-id tie-break** — which is also the determinism: these tiles go into `PathService`, whose answers ride `state_hash()`, and a client's selection can legitimately hold the same SET in a different order on two hosts.<br><br>**Integers throughout, including the compass.** `_DIRS` is an exact eight-entry table rather than a rotation, because `cos(PI/4)` is irrational and a float here would be free to round differently on an ARM phone than on an x86 host. `_facing_of` defers to `SimUnit.facing_toward` rather than defining a second compass.<br><br>**An unreachable slot needs no handling and that is worth knowing before somebody adds some**: a formation spread across a treeline puts slots inside the trees, `PathService` substitutes the nearest standable tile and `set_path` rewrites the destination (4.1) — so the shape degrades into "as close as the ground allows", which is what every other order already does.<br><br>**Absence is the default**: `Formation.NONE` is `&""`, omitted from the wire, and means every unit walks to the one tile. Every existing caller — the AI, the minimap, `send_to_waypoint`, every test — gets the old behaviour by saying nothing. An UNKNOWN shape is **refused** rather than falling back, because a client and a server disagreeing about where an army is walking is a desync dressed as a cosmetic difference | |

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
| 5.7 | ✅ **DONE 2026-09-01** — full building roster, **23 reachable kinds, and no code was written to close it.** This row's "low code effort, ~70 bakes behind it" was accurate for its whole life: it was paced by §12A A.10 on the art side and by nothing here, and it closed when A.10 did.<br><br>**Two counts appear in this repo and both are right.** There are **31 defs** in `buildings.json`; **22 are `buildable`** and reach the build menu (19 non-wall + the three wall SHORT pieces, one per tier); the other **9 are `buildable: false`** — wall medium/long/gate at each tier — which is §5.8 by design rather than a gap, since drag placement picks segment length automatically and the gate is an *upgrade* of a long segment (a tap-placed gate could only ever lie east–west). So **22 placeable + the gate by upgrade = the 23** this row and the retired-items line both count. Age gating spans all four: `age_required` is 1 for 5 buildings, 2 for 12, 3 for 9, 4 for 5, with nothing out of reach.<br><br>⚠️ **The field is `age_required`** — not `min_age`, `age` or `requires_age`. A check looking for those finds nothing and reports every building as age 1, which looks exactly like an ungated roster rather than like a bad query.<br><br>**A.10 was closed on the owner having PLAYED it, not on a facing/colour/clip check**, so a bug found in a building reopens A.10 and does not contradict this row. The dragon and the packed siege pair are excluded and tracked as A.10's P7 and P6; neither is a building | |
| 5.8 | ✅ **DONE 2026-08-22** — **Walls and gates**: drag placement, automatic short/medium/long segment choice, two orientations, and a gate that opens and shuts. Three tiers, twelve defs, three menu entries. The gate is an **upgrade of a long segment**, not a placement — tap-placing one could only ever lie east-west. Finished short pieces that meet **merge into one longer piece**, so a wall built in stages ends up the shape one drag would have laid. See §5.8 | |

#### 5.8 Walls and gates — ✅ built 2026-08-22

22 baked wall pieces the game could not reach. Four things stood between them and the
build menu — drag placement, automatic segment choice, an orientation, and a gate that
lets your own people through — and all four shipped. *Compressed 2026-08-23; the
how-we-found-it narrative now lives in the code and in git.*

**Every civ agrees on the segment lengths, which is the whole reason this is tractable.**
Measured from `<Obstruction><Static>` at 4 units per tile, rounded up, maxed per axis
across each tier's ages:

| piece | tiles |
|---|---|
| short | **[3, 2]** |
| medium | **[6, 2]** |
| long | **[9, 2]** |
| gate | **[9, 2]** (forced) |

3 / 6 / 9 long and 2 deep universally, so one segmentation function serves all three tiers
and a tier is nothing but a skin and a price. **The gate is forced to [9, 2]** even though
the germanic one measures 9.25: a gate must be substitutable for a long piece or it leaves
a gap in a run. The cost is half a tile of art overhang.

**Three tiers stay available at age 4** (owner's call) — wood (2), stone (3), reinforced
(4) are three ladders, not one re-skinning the others away. The tier's SHORT segment
carries `wall_lengths` and is the menu entry; the other nine pieces are
**`buildable: false`**, meaning *the system may place this, the menu may not offer it*.
Without that flag the build grid carries twelve pieces, eleven of which place one fixed
block each — the outcome walls were held back over.

**`WallPlan` is one function with two callers**, and that is the design: the ghost draws
what it returns and `PlaceWallCommand` places what it returns. Two implementations of
"which pieces fill this line" would differ somewhere, and the player would find out only
after letting go.

- **A sloppy diagonal becomes a straight wall** — snapped to whichever axis it mostly ran
  along. The finger is on a phone and the grid is isometric; refusing an imperfect drag
  would make the feature unusable on the device it is for.
- **Rounded to whole short segments, filled longest-first.** Fewer pieces is fewer seams,
  vision circles and snapshot rows.
- **Always laid in the +axis direction from the lower end**, so dragging backwards
  describes the same wall and the ghost does not reshuffle when a drag crosses its anchor.
- **A tap is one short segment.**
- **A partial run downgrades its last piece** to whatever the tier still affords. Without
  it, a player with two shorts' worth of wood who drags thirty tiles got *nothing*.

**Only two of the eight baked directions are reachable**, and that is the footprint system
rather than the art: a [9, 2] box rotated 45° does not tile a square grid. A north-south
wall is its def's footprint **transposed**, which is all "8 orientations" reduces to.
`SimBuilding.facing` exists for this, and the view **derives** the transpose from it rather
than being sent it.

**A builder carries on to the next foundation.** `BuildSystem` re-scans within
`SimSystem.SAME_WORK_RADIUS` — **10 tiles**, the owner's number — which also raised
`GatherSystem.RESCAN_RADIUS` from 1. That reversed an earlier 3×3 call, and the earlier
reasoning was answering a different question: it guarded against a worker setting off
across the map unasked, and *a wall drag is an order the player gave*. Combat's
`REACQUIRE_RADIUS` stays at 2 — ten tiles of "next thing to hit" is an aggro range.
Measured from the segment just finished, not from the unit, and prefers a foundation
nobody is on. Builders spread round-robin rather than all queuing on the first.

##### The gate is an upgrade, not a placement

It shipped as a menu entry and the owner found the hole in a day: **"how do I rotate a
gate?"** You could not — `PlaceBuildingCommand` carries no facing, so every tap-placed
gate lay east-west and a north-south wall could not have one at all.

The fix deletes the question rather than answering it: **tap a finished long segment and
upgrade it.** The wall already knows its axis, and the gate inherits its origin, footprint
and facing. It is also what 0 A.D. does.

- **All three gates are `buildable: false`** — upgrading is the only route, so the broken
  axis case cannot be reached rather than being worked around.
- **`BuildingDef.upgrades_to`**, on the three long segments only. The target must declare
  the SAME footprint and `UpgradeBuildingCommand.validate()` enforces it, because
  `convert_building` keeps the ground already held and a bigger target would silently
  occupy unchecked tiles.
- **Converted in place, keeping the entity id.** A despawn/respawn would empty the panel
  the player just pressed, and would report a *destroyed* building to every other client.
- **The price is the difference, floored per resource kind**, so a target cheaper in one
  resource cannot hand back a refund in it.
- **Health carries its fraction**, with full health pinned exactly so a brand new gate
  cannot show a damage dot.

##### Gates

**A gate starts OPEN and can be locked** (owner, 2026-08-22). Closed-by-default defends
the moment it is finished, at the price of stranding your own villagers behind it before
you have noticed there is a gate to open.

`SimMap.set_occupied` already takes a `blocks` flag, so `SimBuilding.blocks_now()` is the
whole rule. **Locking evicts whoever is in the doorway** — a unit inside a blocked cell is
one `AStarGrid2D` will not plan a route *out* of, and a closing gate is the only thing in
the game that creates that on purpose.

`ToggleGateCommand` **names the target state rather than meaning "flip"**: on a client the
second tap goes out before the first one's snapshot returns, so a double tap would be as
likely to shut a gate as open it.

**AN OPEN GATE IS OPEN TO EVERYONE**, besiegers included. Per-player passability is the
real fix and needs a pathfinding grid **per player** — and note that `PathService` now
holds one grid per *domain* (2026-08-23), which is the same shape of change and evidence
it is affordable, but per-player multiplies by player count rather than by two. Deliberately
not attempted. What exists is 0 A.D.'s own model, one honest step short of AoE2's
allies-only gate.

**`gate_locked` and `facing` are both in `state_hash()`.** The lock moves the movement
grid, so two hosts disagreeing about a doorway route the same army two different ways.

##### Short pieces that meet become one long piece

A wall built over several drags ends as a row of shorts where one drag would have laid
longs: same ground, same cost, three times the entities. `WallMerge` closes that — on
completion a segment looks along its axis and, if a contiguous stretch of same-tier
neighbours sums to a length the tier declares, they become that one piece.

- **Only complete pieces merge** (the owner's amendment, and the load-bearing one):
  absorbing a foundation would delete the building a villager is walking towards.
- **The survivor is the piece at the LOW end**, not the one that just finished — it keeps
  its origin and only grows, and the outcome cannot depend on completion order, which is
  what stops two hosts producing different entities.
- **Health is the sum, exactly.** Wall hp is authored strictly per tile (400/800/1200 for
  3/6/9), so three undamaged shorts are one undamaged long. Deliberately *not* the
  fraction rule the gate upgrade uses: an upgrade is one building becoming another, a
  merge is several becoming one.
- **Silent and free** — no toast, no cost, no refund.
- **Longest-first, then leftmost**, matching `WallPlan`. The tie-break is not cosmetic: a
  run of six contains four different stretches of three.
- **A merged long can then be upgraded to a gate**, which is the payoff: until this, a
  player who walled a gap in short pieces could never put a door in their own wall.
- **A gate is never merged away**, and that falls out of the data — no tier's
  `wall_lengths` names a gate. Nor is anything merged across an owner, tier, axis, gap or
  parallel row; 21 tests, most about exactly that, because every way this could eat
  something presents as *a building vanished*.
- Absorbed pieces go through `despawn`, the **silent** removal, where the destruction path
  (5.5) would leave rubble and report a kill.

##### Not done, and why

- **No wall corner piece, and 0 A.D. has none either.** Two drags meeting at 90° overlap
  or leave a notch. 0 A.D. puts a `wall_tower` at every corner instead — art we already
  have. What is missing is anything that *detects* a corner and places one.
- **No wall tower needed**: `building.guard_tower` is baked from `Pers/wall_tower` and
  `rome/wall_tower`, so it already *is* the wall turret. Auto-placing at corners wants the
  wall system settled first.
- **No garrison, and that is now a DECISION rather than a gap.** 0 A.D.'s medium wall
  declares eight turret points; ours hold nobody. 4.8 landed on 2026-08-27 and the owner
  ruled walls out by name — *"walls will not be garrisoned"* — so all twelve wall and gate
  pieces keep `garrison_cap: 0` and those eight turret points stay unused. The wall turret
  you *can* garrison is `building.guard_tower`, immediately above.
- **No diagonal walls.** Six of the eight baked directions are unused. Needs a footprint
  model that is not a box.
- **The Athenian bakes are unused** (`vis.wall_short/medium/long/gate`, no age suffix) —
  they predate the age ladder and the roster does not name Athens for walls. Left staged;
  the obvious stand-in for a fourth tier.

### Phase 6 — Resources & wildlife

| # | Item | Tag |
|---|---|---|
| 6.1a | ✅ `res.berry_bush` is the MVP food node and **stays** the easy opening one — it gathers like a tree, so nothing forces a player to hunt before they want to. The hunt/kill/carcass machinery this item was deferred to avoid now exists anyway, arriving with the hostile wolf (4.13) rather than with the deer: a predator has to be killed before it can be harvested, and `DeathSystem` is the seam where a hunted thing becomes a harvested one | `[MVP]` |
| 6.1b | ✅ **Roaming + flee-and-relocate**, 2026-08-23. `WildlifeSystem` wanders any gaia animal within `roam_radius` of where it last settled; anything with `flees` bolts for 4 s when its hp drops and makes wherever it stopped its new home. **The deer had to become a unit to get either** — it declared `roam_radius: 6` in `resources.json` for months and nothing read it, and nothing could have: `MovementSystem` moves `SimUnit` and skips nodes, so the data sat on a class physically unable to act on it. So a deer is now **hunted** (`unit.deer` → `res.deer_carcass`, 140 food) where it used to be harvested standing still, and `vis.deer_carcass` finally draws the thing it was baked for. Fleeing is detected by **watching hp**, not by plumbing an attacker through `take_damage` — same information, one field, and it catches damage that will never have an attacker. Roam targets are hashed from `(id, tick)` rather than drawn from a shared rng, which has no draw order to get out of step | |
| 6.2/6.3 | ✅ Size classes are pure data. Since the 2026-08-17 ore/tree rebake the class picks the **sprite** as well as the amount, so a rich seam and a poor one are different pictures | `[MVP]` |
| 6.4 | ✅ `GatherSystem`: walk, extract on a whole-tick countdown (a float accumulator would round differently across machines and desync), fill `carry_cap`, walk to `nearest_drop_off()`, deposit, return or retire. `gather_slots` is enforced by **recomputing** which ids rank lowest among holders every tick rather than reserving a field — so a competitor stopping, dying or being re-tasked frees its spot with nothing to keep in sync. A short last take costs a **proportional** wait, not a full interval (see §12 field balance) | `[MVP]` |
| 6.5 | ✅ **mostly** — stone, berry bushes, livestock, farms/fields and (2026-08-23) **herding** all land. Walk any unit within 4 tiles of a sheep or cow and it takes your orders; walk somebody else's closer and it takes theirs. **Herding is not owning:** the animal stays gaia's and only `SimUnit.herded_by` moves, which is what kept `GatherSystem`, `WinConditionSystem` and `AttackCommand` entirely out of it — and is why you can still attack the animal you are herding, which is how it becomes food. Claim is sticky, so a penned flock stays yours.<br><br>**Fishing landed the same day**, which closes this item. `res.fish` in shallow water, and two real blockers behind it: `spawn_resource_node` asked `can_place_building`, which is land-only by design and refused a fish every tile of the sea — `ResourceDef.domain` and `SimMap.can_place(rect, domain)` split that apart — and `unit.fishing_ship` carried empty `gather_rate`/`carry_cap`, so it would have sailed to the shoal and quietly given up. **`building.dock` now `requires_shore`**, enforced through `adjacency_allows` so the placement ghost cannot show green for a spot the host refuses: a ship is domain water and must reach a tile adjacent to its drop-off, so an inland dock trains ships that can never deliver | |

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
| 8.2a | ✅ `Minimap` — terrain baked once into an `Image`, blips redrawn per snapshot, fog painted **over** the blips (2.5).<br><br>**FOUR BLIP COLOURS SINCE 2026-08-31, not three**: green for your own, **sky blue `#87CEEB` for an ALLY**, red for an enemy, khaki for gaia, plus white for the damage flash. It drew an ally as an enemy until teams landed, so in a 2v2 your partner's army crossing the board read as an incoming attack. The owner's question about the colour — *"if its not to close to the water colour"* — is the one worth recording, because **hue is not what separates them**: sky blue is six degrees off `terrain.water_shallow`, and what does the work is CIE `L*` at 79 against water's 51 and deep water's 30. That is the same measure `web/player-colour-ladder.html` chose the eight-player palette on. It is **capped** at 79 rather than pushed lighter, because `DAMAGE_FLASH_COLOR`'s "no blip ever sits near white" is what reserves the flash — **a fifth blip colour has to be checked against that as well as against the terrain**. `dev_preview/preview_minimap_teams.tscn` prints every figure and saves a 6× nearest-neighbour crop, since a blip is two pixels and at 1:1 "I cannot see it" and "it is not drawn" look identical | `[MVP]` |
| 8.2b | ✅ **DONE 2026-08-21** — 4 corner buttons, all four real. `hud_settings` took over the pause menu from the button that used to sit in the age header; `hud_trade` opens a **working market**; `hud_chat` and `hud_techtree` open **wireframes**. See §8.2b below | |
| 8.6 | **Chat** — wireframe only (§8.2b). The transport is unbuilt and the design question is per-team versus all-players | |
| 8.8 | ✅ **DONE 2026-08-28** — **A [X] clear-selection button** — owner's call from the 2026-08-23 mobile playtest. Top of the `SelectionPanel`, **hugging the left edge of the screen, below the five control-group icons**, visible only while something is selected. It replaces a gesture that does not survive a thumb: double-tap on empty ground clears the selection ([game_scene.gd:927](game/src/view/game_scene.gd#L927)) and misfires on the phone, because a second tap the router scores as a small drag never reaches the detector. **The gesture stays** — it is in nobody's way and it is faster once learned — and desktop keeps right-click. Three reasons the button is the answer rather than a patch: clearing is a *discoverable* action on a touch screen where a gesture is not; it costs desktop nothing; and it does not wait on `InputRouter`'s tap/pan discrimination getting better, which is the real root and a separate job. `BUGS.md` 2026-08-23. **Built as `ClearSelectionButton`, a 40 px drawn disc in a zero-separation row above the portrait, emitting `SelectionPanel.clear_requested` into `GameScene._on_clear_pressed`. THE 40 IS THE ONLY SIZE THAT FITS AND IT FITS EXACTLY**: the control-group stack ends at y 364 (`12 + 5×64 + 4×8`) and the panel's ceiling is 244 (`20 margin + 72 portrait + 4 + 2 rows × 72 + 4`, two rows being what `MAX_ACTIONS` 8 caps it at), so on the 648 px canvas there are precisely 40 px between them. Anything taller — or any separation added below the button — slides it under the fifth group slot, which is added to the HUD *later* and therefore hit-tested *first*, so the overlap would go **silently dead** rather than visibly wrong. `test_the_tallest_panel_still_clears_the_control_group_stack` fills both grids to their caps and asserts the arithmetic, and it has no slack in it on purpose. One press also exits placement first, unlike right-click's two — see `_on_clear_pressed` | |
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
| bottom-left | **Tech tree** (9.4) | **Working since 2026-08-29**, and it filled itself in: the renderer was written a phase ahead of the data, so 9.3 declaring 27 technologies was the whole of what this page needed. Four age columns scrolling both ways, each node naming its technology, **the building that sells it** and its prerequisite — which is what makes it the owner's *"visual guide letting you know what buildings hold what upgrades"* rather than a list of names. **Read-only by design, not by shortcut**: researching happens at the building that offers it, the way training does, so there is nothing to press and no command behind it — and therefore nothing this page can disagree with the server about. All three states are real now; `RESEARCHED` was in the legend and never assigned for as long as `SimPlayer.researched` was a field the HUD read and nothing wrote, which is the hole 4.11's population counter was in. The placeholder lattice survives for an EMPTY `techs.json` only, so an age with no technologies of its own draws nothing rather than promising four |
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
| 9.3 | ✅ **DONE 2026-08-29.** 27 technologies at seven buildings, on the owner's ruling that *"upgrades are action tiles on buildings"*. **A research is an entry on the building's own production queue** — so the timer, the progress bar, the cancel slot and the refund all already existed, and `TechSystem` became `TechMods`, a static modifier resolver (see the systems table). An effect key is `stat.scope` and **every stat names a lookup the sim already makes PER USE**, which is what means no tech ever has to reach back and rewrite units that exist: attack damage, attack range, both armours, gather rate, carry cap and ability amount. `unit_hp`, `building_hp`, `speed`, `los` and `build_rate` are deliberately absent and `techs.json` records a different reason for each. **The field's per-age ladder was NOT replaced** — it is the base and Horse Collar multiplies it, through the one function that reads either | |
| 9.4 | ✅ **DONE 2026-08-29** — it stopped being a wireframe when 9.3 filled `techs.json` in, which is what its renderer was written ahead of the data for. Four age columns, scrolling both ways, each node naming its technology, **the building that sells it** and its prerequisite. Read-only by design and by the owner's ruling: *"tech tree on mini map is only a visual guide letting you know what buildings hold what upgrades"* — research happens at the building, so this page issues no command and can never disagree with the server. Its third state, RESEARCHED, was drawn by the legend and never assigned while `SimPlayer.researched` was a field nothing wrote; `player_state` carries it now | |
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
| 11.1 | ✅ `WinConditionSystem`, last in the order so a loss lands on the tick it happens. `Mode.LAST_MAN_STANDING`: own no unit and no building and you are out (`defeated`, one-way); the last player left sets `winner_id`/`match_over`. **Alive-only**, so a corpse or rubble does not postpone the result — but a **foundation keeps you in**, since it holds ground and can still be raised. A one-player world is never decided, and neither is a world with no units or buildings at all (which is what every sim test skipping MapGen runs on) — without that guard an empty world reads as everyone eliminated on tick 1, and `match_over` latches. `ResultScreen` is `PauseMenu`'s sibling with **no Resume**, and stops `SimClock`. Verified against the real `debug_skirmish` map: killing the two-soldier enemy squad wins.<br><br>⚠️ **IT COUNTS SIDES, NOT PLAYERS, SINCE TEAMS LANDED (2026-08-31), and that was not an enhancement — the old rule could not end a 2v2 at all.** Two allies standing is two standing players, and once they cannot attack each other nothing remains that can reduce it to one, so the match ran forever with both survivors wandering an empty map. Standing players are grouped into sides — their team, or **the negative of their player id** for anyone unaligned, so it can never collide with a real team number and a free-for-all is still one side per player. `winner_id` is unchanged in meaning and **still names a player**, because it is on the wire, in `state_hash()` and read by two screens; it is now the lowest-id survivor of the winning side. **`SimWorld.winner_team` rides beside it** (0 in a free-for-all) and is what tells a teammate knocked out on tick 400 that their side went on to take it — `GameScene._refresh_result` and `MatchAudio` both read it, and both exclude a player who **forfeited**, since resigning used to make the victory branch unreachable by construction and a team puts it back in reach through somebody else's survival. `SkirmishScreen` refuses to start a lobby whose players are all on one side, which is two presses away from the default | |
| 11.2 | **Trophy** and **King of the Hill** are declared in `MatchConfig.Mode` and **decide nothing**. Trophy wants a `unit.dragon_baby` def, a MapGen that gives every player one, and an `is_trophy` flag rather than a hardcoded id; KotH wants the zone as **map** data, a per-player score (deliberately not added — an unwritten field that reaches the HUD is exactly the hole 4.11's counter was), and the minimap ring. **Inert is the safe direction to be unfinished in:** "you lose when your trophy dies", on a map with no trophies, defeats everybody on tick 1. Also unbuilt: regicide (the Celtic heroes would serve), capture the flag, wonder.<br><br>⚠️ **KotH'S RULES ARE SETTLED — the owner's scoring ladder AND its target, 2026-09-01, in §11.9.** Scored **per side**, and the target is worked back from **five minutes uncontested** to `KOTH_TARGET_SCORE = 9000` (the shipped 1000 is 33 seconds). It **reverses** what `_king_of_the_hill()`'s header says the rule is. The zone, the score field and the ring are still the three missing pieces; what is no longer missing is any design question | |
| 11.3 | Mode shown in the skirmish screen and at match start. `MatchConfig.mode` is the field, and the snapshot already carries `mode` so the result screen can name the rule that decided it | |

#### 11.9 King of the Hill scoring (11.2) — the owner's rules, 2026-09-01

The four rules as given, per tick, for a side standing in the zone:

| Situation | Points |
|---|---|
| **the only side in the zone** | **3** |
| the side with the **most** units in it, others present | **2** |
| any **other** side in it | **1** |
| every side **tied** for the most | **1 each** |
| nobody in it | **0** — nobody scores |

**Write it as one formula, not four arms.** The rules overlap, so a `match` has to pick an order
and the order is where the bug goes. Instead: **1 point for presence, +1 for being the *unique*
leader, +1 more for being the *only* side there.** Every row above falls out of that — alone is
1+1+1 = 3 (a sole occupant is trivially the unique leader), leader-with-company is 1+1 = 2, a tie
at the top means there is no unique leader so nobody takes the bonus and everyone present keeps
their 1, and an empty hill pays nothing because nobody is present to earn the base point.

⚠️ **THIS REVERSES A DOCUMENTED DECISION, AND THE REVERSAL IS NOTED RATHER THAN ARGUED.**
`_king_of_the_hill()`'s header says the rule is *"MOST units in the zone scores, not merely
presence, so a contested hill pays nobody and one unit is enough to hold an empty one."* Half of
that survives — an empty hill is still had for one unit, and holding it alone is still worth the
most — and half is now wrong: **a contested hill pays everybody standing on it.** ⚠️ **That comment
is currently the only place in the repo that contradicts this section**, and it is a placeholder's
rationale rather than live behaviour, so it wants correcting in the same change that builds this.

**What the reversal buys, which is why it is the better rule.** Presence paying means the hill can
never *stall*: under the old rule two evenly matched armies standing on it advanced nobody, so the
mode's clock stopped and the winner was decided somewhere else entirely. Now a contested hill still
runs, just three times slower than an uncontested one — and **that 3× ratio is the whole design**:
taking the hill alone is worth more than crowding it, so the incentive is to *clear* it rather than
to garrison a stalemate.

✅ **SCORE BY SIDE, NOT BY PLAYER — settled by the owner, 2026-09-01** (*"you are correct per side
not player"*). Read literally per player, two allies alone on the hill are each not *"the only
player in area"*, so each would take 1 or 2 instead of their side's 3 and a 2v2 would be
**penalised for cooperating**. Count units by side and pay by side, a side being the team or **the
negative of the player id** for the unaligned: exactly the key `_last_man_standing` already builds,
and for the reason §11.1 records at length. It is the same class of miss as the four hostility
predicates teams had to widen together — a rule written before teams existed that reads as a bug
once they do.

**A consequence of scoring by side, and it is the right one:** a side of two holding the hill scores
at the same rate as a side of one, because the ladder pays for *occupancy*, not for headcount.
Numbers still matter, and they matter where they should — through *"most units"*, which is how a
side takes the leader bonus off somebody and how it clears the hill to reach 3.

**Where the score lives.** `SimPlayer.score`, an int, **written the same value for every member of a
side** — so it rides `player_state` beside stock, population, age and control groups, folds into
`state_hash()` through the per-player loop that is already there, and your HUD and your teammate's
cannot disagree without a second channel to disagree through. **Add the field in the same commit as
the writer**: 11.2's own text is why it was not added earlier — *"an unwritten field that reaches
the HUD is exactly the hole 4.11's counter was"* — and that objection expires the moment something
writes it.

#### `KOTH_TARGET_SCORE = 9000`, worked back from five minutes (owner, 2026-09-01)

**The design figure is the DURATION and the constant is derived from it** — *"total time required in
the area is 5 min.. we can work it back"* — so the number is written down here with its arithmetic
attached, and anybody re-tuning it changes the minutes and re-derives rather than nudging a
constant and guessing what it means:

```
5 minutes = 300 s ÷ 0.1 s per tick = 3,000 ticks × 3 points (uncontested) = 9,000
```

| Held as | Points/tick | Ticks | Time to 9,000 |
|---|---|---|---|
| the only side there | 3 | 3,000 | **5:00** — the design figure |
| leader, with company | 2 | 4,500 | 7:30 |
| present, not leading (or tied) | 1 | 9,000 | 15:00 |

⚠️ **The shipped `KOTH_TARGET_SCORE = 1000` is thirty-three seconds** and is a placeholder that
happens to look like a plausible number, which is the worst kind: 3 points a tick is 30 a second, so
nothing about it reads as wrong until somebody plays it.

**"TOTAL" IS LOAD-BEARING AND MEANS CUMULATIVE.** The score accumulates and **never decays**, so the
five minutes need not be consecutive: a side that takes the hill, is pushed off, and comes back
resumes from where it stopped. Losing the hill costs you the *rate*, not the progress. The
alternative — resetting or bleeding a side's score when it leaves — is **not** the rule, and it is
worth naming as rejected because it is the obvious thing to reach for and it would make the mode
punish the one thing it is trying to encourage: contesting a hill somebody else holds.

⚠️ **THE WIN CHECK IS `>=`, NEVER `==`.** A side's score steps by 1, 2 or 3 depending on who else is
standing there, so it can step **over** an exact target: 8,998 → 9,001 never equals 9,000, and the
match would run forever with a side sitting on the hill past the line. 9,000 divides cleanly by all
three rates, which makes an exact landing *likely* and therefore makes the bug rare rather than
absent — which is exactly the shape that ships. Same family as `ProjectileSystem`'s
`elapsed_ticks > total_ticks` fix (§6's gotcha table): a threshold crossed by a variable step is a
comparison, not an equality.

**Which units count.** Any **living unit** a side owns whose tile is inside the zone, **workers
included** — "units" is what the rule says, and a villager standing on the hill is a villager
somebody chose not to have gathering. **Buildings do not count**, so a town centre on the hill
claims nothing. **A garrisoned unit does not count either, and that is a fact rather than a
ruling**: `garrison_system.gd` records that a garrisoned unit is *out of the spatial index*, so it
has no presence on the map for anything else in the game — a tower full of archers would otherwise
hold the hill invisibly.

**The zone is still the missing half, and Phase 16 is where it stops being missing.**
`KOTH_ZONE_RADIUS_TILES` is the shape and nothing anywhere declares a centre. Two sources, arriving
at different times: `MapGenerator` can place one per map type, which is a tile and a line of code;
and **16.5's authored AREAS are literally this** — a MapMaker area *is* a hill — which turns KotH
from "hardcode a centre" into the map data 11.2 always said it wanted. So the mode is buildable now
against generated maps and inherits authored hills for free later.

**Two rules the owner's list does not cover, and the implementer cannot duck either:**

1. **Who wins when two sides cross the target on the same tick.** Reachable rather than
   theoretical: two sides that walked in together both score 1 a tick and arrive together. **Higher
   score wins; equal scores go to the lowest player id of the winning side**, which is
   `winner_id`'s existing convention and is deterministic. Do not leave it to whichever key a
   `Dictionary` happens to yield first.
2. **Elimination still applies, and one side left still wins outright.** KotH keeps **both** halves
   of the conquest rule rather than replacing them — own nothing and you are out, and being the
   last side standing wins without a five-minute sit on a hill. Worth stating because it is the
   **opposite** of Phase 15's `SCENARIO` mode, which keeps the loss and suppresses the win: both
   modes are "last man standing plus something", and they resolve that overlap in opposite
   directions on purpose.

**The minimap ring stays a requirement, not polish** — 11.2 says so and it holds: a scored zone the
player cannot see is a rule they can only lose to. The scores need somewhere on screen too, and
`AgeBadge`'s precedent (progress drawn as the ring around the thing it belongs to, rather than as a
separate bar) is the one to reach for before inventing a scoreboard.

### Phase 12 — Multiplayer & AI

| # | Item | Tag |
|---|---|---|
| 12.1a | ✅ `host_open()` on 0.0.0.0 + `join()`, peer lifecycle, player-id assignment — validated phone↔PC on real WiFi with the rest of a–g. See §12.1 | |
| 12.1b | 🟡 **LAN discovery ✅ 2026-08-31** — `LanBeacon` broadcasts on `Net.PORT + 1`, `LanBrowser` holds a rolling window over it, `ServerBrowserPanel` lists and dials. **Reconnect is still open.** *Desync detection retired* (one authoritative sim, nothing to diverge from) and *lag compensation* is the parked input-delay decision at the end of §12.1 | |
| 12.2a | ✅ **PlayTest AI**, 2026-08-17, plus the **difficulty list** on 2026-08-22. See §12.2 | |
| 12.2b | AI difficulty levels and real decision flow — **the list exists, the behaviour behind it does not.** Human / Passive / Easy / Normal / Hard / Unfair / Open / Closed are selectable; Passive is real and Easy is the PlayTest AI unchanged, and Normal / Hard / Unfair are wired to Easy and **say so on screen** ("AI (Normal) — as Easy") rather than being three names for one opponent. The decision flow behind them is still deliberately parked until the game's balance has been played.<br><br>**The spec now exists: `AI_Player_difficulty.md`**, committed 2026-08-23. It is the owner's, and it settles what each tier does rather than leaving it to be invented later — five tiers, separated along four axes that are all data or existing systems rather than new cleverness: **when it attacks** (never / 10 min / 7 min / once its economy is up), **how far it ages up** (2 / 2 / 3 / 4 / 4), **how many towers it may build** (0 / 1 / 5 / unlimited + castles), and **what it starts with** (Unfair opens with 8 villagers, 2 swordsmen and a scout).<br><br>Two things to know before building it. **The phase-9 gate LIFTED on 2026-08-29:** every tier from Easy up says "can use tech tree upgrades", and 9.3 built them — 27 technologies and a `ResearchCommand` waiting to be emitted. So a tier's tech behaviour is now a rule to write rather than a system to build, and ⚠️ **the first rule that researches invalidates every row of BUGS.md's ladder table**, which was measured with neither side researching. And **Passive is already real**, so the spec's cheapest win is `Normal`, which differs from the shipped Easy only in an attack timer, an age cap and a tower count | |
| 12.3 | Campaign: scripted triggers/objectives on the host-loopback path. **The screen exists as a placeholder since 2026-08-21** and PLAY on the main menu opens it — see §12.3 for the front-door decision. ➡️ **GROWN INTO PHASE 15, 2026-09-01**, on the owner's two new specs (`scenarios/README.md`, `MapMaker/README.md`): this row is one line and the work is nine. Read Phase 15 instead of this row; what stays here is only the fact that PLAY already leads to the frame | |
| 12.4 | Save/load and replays *(replay record/play already exists as a test fixture, 0.7)* | |

#### 12.1 Multiplayer — ✅ steps a–g all built and validated phone↔PC on real WiFi

*Compressed 2026-08-23. The step table carried est/risk columns and an ordering plan for
work that finished on 2026-08-21; §15 had recorded a–g as done while this table still
showed five of them pending. What survives is the decisions that still bind.*

**All seven shipped:** `host_open()`/`join()` with peer lifecycle and player ids (a); the
client's world (b); the lobby with a config broadcast and a READY gate, 2–8 slots with a
CLOSED role (c); the match-start handshake (d); resign and peer-drop, both through the
ordinary command path so neither can be forged (e); wire size (f); two-device bring-up (g).

**Terrain is a transfer, not a regeneration.** This originally said each client runs
`MapGen` from the shared `MatchConfig`, which holds for the integer-only debug map and
**not** for 2.4b's generator: `FastNoiseLite`'s float maths is not guaranteed identical
between an ARM phone and an x86 desktop, and a host and client that disagree about where
the water is have desynced before the first order — in the one way `state_hash()` cannot
help with, since it reports the divergence without saying why. So `MatchConfig` carries the
`MapData` (20–40 KB) and it is sent once. Certainty for one small message.

**The placement ghost is advisory.** A client has the map but not what anyone has built
since, so the ghost is driven from snapshot facts. The server validates, so a wrong ghost
costs a refusal rather than a desync.

##### Wire size (12.1f) — measured, per player per tick

| board | start | after fog | after 1 & 2 | after shape tables | fragments |
|---|---|---|---|---|---|
| 96×96 | 28,768 | 19,528 | 14,840 | **7,528** | 21 → 6 |
| 128×128 | 31,768 | 15,384 | 11,840 | **6,328** | 23 → 5 |
| 192×192 | 53,928 | 17,040 | 13,080 | **6,824** | 39 → 5 |

Confirmed on the real transport: ENet's own warning went from 18,532 bytes to 4,360. Two
findings, both counter-intuitive enough to keep:

**Fog was 68% of the packet** on the 8-player board, and a function of the MAP rather than
the match — so no other saving would ever have shrunk it. `ClientFog` computes it on the
client instead: zero bytes, forever. Its cost is that `EXPLORED` accumulates a tick at a
time over an unreliable channel, so a dropped snapshot leaves a thin rim of tiles the
client believes it never saw; it self-corrects when anything of yours passes there again.
**If those slivers ever become a complaint, the reinvestment is sending fog CHANGES on a
reliable channel** — tens of bytes, cannot drift — and it lands in `ClientFog`, with
everything above its `apply()` unchanged. This did **not** move the security boundary: the
rule is "the server must not send a client entities it cannot see", it lives in
`SnapshotSystem._entry_for`, and it still runs on the server. The grid was only ever a
bitmap to paint. A test compares client grid to server grid tile by tile, because two
implementations of one circle are two that can drift.

**Half of every entity entry was the names of its own fields** — 248 bytes of a town
centre's 472, because `var_to_bytes` writes a dictionary key as a length-prefixed string
every time it appears. Only 36 entities are visible on the 8-player board, so the count was
never the problem and a delta was never the first answer. Three fixes: `footprint` is not
sent (derived from `def_id`, same argument that took `vision_range` off); `pos` is a
`Vector2i` rather than `{"x": .., "y": ..}` (48 bytes for two small integers) — safe here
and deliberately **not** in `MapData`, which goes through JSON where a snapshot never does;
and **shape tables**, so field names go once per shape per snapshot, done at the transport
boundary so the simulation still produces readable dictionaries.

##### Transport mode — settled by measurement

Phone joined to a PC host over real WiFi, ~90 s of play: **~3.4% of snapshots lost, and
every single loss was one snapshot — never a run.** A lost snapshot is one 100 ms frame of
stale state and the next is complete, because a full snapshot supersedes its predecessor
and needs nothing from it.

**So `unreliable_ordered` stays, as a decision rather than an inheritance.**
`reliable_ordered` would remove 3.4% of invisible gaps and buy head-of-line blocking — a
retransmit stalls every snapshot behind it, turning a loss nobody can see into a stutter
everybody can — and retransmitting a snapshot is worthless by the time it lands.

**That is also the argument against finishing §7.2's delta encoding.** Per-fragment loss is
~0.7%, so at the pre-fix 39 fragments this link would have dropped ~24% of snapshots.
Getting to 5 fragments is what made the unreliable choice viable, and a delta trades that
self-healing property away: the remaining payload is mostly resource nodes, which barely
change, so "send statics only when they change" means replacing the absence-means-invisible
rule the view depends on — and then needing reliability after all. Deliberately not done.

##### Still open

- ✅ **LAN discovery is DONE, 2026-08-31.** Typing an IP was the friction point on
  hardware and it is now optional: a lobby with an advertised slot broadcasts a small
  `LanBeacon` datagram on `Net.PORT + 1` once a second, and the lobby's SERVERS button
  opens a `ServerBrowserPanel` that lists whoever answers and dials one. **No master
  server, and the beacon's header argues why there must not quietly become one** — an
  internet browser is a service somebody has to run and pay for, and this phase's
  multiplayer is two devices on a sofa. Four things worth knowing before touching it:
  a host stays listed for four beacons' worth of silence, because a datagram is allowed
  to go missing and a row that blinks reads as a host dropping out; JOIN goes through
  `SkirmishScreen._on_join_pressed` rather than a second call into `Net.join`, so the
  refusals the lobby already words are worded once; `MatchConfig.host_name` is the one
  field the format needed that nothing had, and it is provenance rather than simulation;
  and a browser refuses beacons from its own process, because `Net.has_session()` is true
  for a host the moment a slot is opened and this page is reached from that very screen.
- **12.1b's other half, RECONNECT, is still open.** A dropped peer concedes
  (`SimPlayer.defeat_reason`, 12.1e) and there is no way back into a match.
  *Desync detection is retired* — `Net` has no `SimWorld` on a client and `state_hash()`
  appears only in tests, so with one authoritative sim and full snapshots there is no
  second simulation to diverge from.
- **Input delay is parked.** Commands queue for `tick + 1` with no buffer, so a remote
  player's orders land whenever they arrive — fine on LAN, visibly rubber-bandy when
  latency spikes. A fixed 2–3 tick delay is the standard fix, about 2 h, but it changes how
  the game **feels** and wants a decision rather than a default.

**Colour is a picker, not a cycle** (2026-08-21). Stepping to the next free colour made
choosing violet out of eight a matter of pressing five times and watching — worse on a
joined client, where every press was a round trip. The rule did not change, only where it
is expressed: a colour somebody else holds is not on the grid at all. Active slots only, or
two players on an eight-slot board would find six colours spoken for by empty chairs. The
host still holds the rule and **ignores** a collision rather than substituting, because
silently handing somebody a different colour than the one they pressed is worse than
leaving them where they were.

#### 12.3 The front door, and where PLAY goes — changed 2026-08-21

PLAY and MULTIPLAYER both opened the skirmish screen, and that was the honest consequence of
1.6's design: a lobby *is* that screen with a slot set to Open, so there was one screen and
PLAY had nowhere of its own to lead. What it cost was the front door — either button did the
same thing, and the campaign this table has always had a row for was reachable from nothing.

PLAY now opens a **campaign placeholder**, and MULTIPLAYER opens the skirmish/lobby screen. A
real screen rather than a `NoticeToast` — which is what SETTINGS and HOW TO got at the time —
because those were features with no shape yet and a campaign is a list of missions: this is
the frame that list appears in, so when 12.3 lands it is a body replacing a placeholder.

*Both of those have since grown screens of their own — SETTINGS an overlay on 2026-08-23,
HOW TO the six-page guide of 1.8 on 2026-08-30 — so the campaign placeholder is the last
front-door destination that is a frame rather than a feature, and QUIT is the only button
left that opens nothing.*

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

##### Eight slot roles, and only two of them are opponents (2026-08-22)

The lobby's per-slot picker now offers **Human / Passive / Easy / Normal / Hard / Unfair / Open /
Closed**, with Easy the default. Two of the five AI entries do something distinct:

- **Easy** is the PlayTest AI above, unchanged.
- **Passive** builds its economy and never attacks — the sparring partner for testing anything
  that is not combat. It took two changes, and the second is the one worth knowing:
  **skipping the script's attack step completes the script, and a completed script is precisely
  what switches the standing attack order on**, so the first version built its whole economy and
  then attacked anyway.
- **Normal / Hard / Unfair** resolve to Easy and label themselves "as Easy" on screen. A
  placeholder that admits what it is costs nothing; three names for one opponent would make the
  first balance report unreadable.

**The test for Passive did not work the first time**, and how it failed is the lesson: it ran
1,200 ticks and passed even with the gate removed, because the script does not *finish* inside
1,200 ticks and the branch was never reached. It now fast-forwards the AI to the end of its
script, and sabotaged it reports "passive attacked on tick 6". It ships with a **control** — an
Easy bot in the identical fixture that does attack — because otherwise "the passive one did not
attack" is indistinguishable from "nothing in this fixture would have".

### Phase 13 — Dragons

13.1 Dragon unit: air domain, castle-tier stats, fire-breath AoE + cooldown.
13.2 Dragon Nest POI: guardian dragon, claim-on-defeat, 360 s baby-dragon timer, destructible.
*(The nest is composed entirely from existing gaia props; only the dragon needed bespoke art, and
it is baked.)*

### Phase 14 — **NEEDS UPGRADE**: the AI cannot see what it is fighting

**Opened 2026-08-27, the moment 12.2b shipped, and by the person who built it.** Not a defect —
a **declared ceiling** of the rule design, written down while the reason is fresh rather than
rediscovered as a mystery later. Nothing here is required for v1; the levels play, they ladder,
and the owner has judged a stalemate between evenly matched bots a correct result.

**What the ceiling is.** Every condition a rule can ask is about the bot's OWN world: its age,
its stock, how many of a thing it owns, how many villagers are on a resource. **There is no
condition that can see the opponent.** So an army is a target number — `fewer_than:
{unit.swordsman: 20}` — and never a response. The consequences are all the same shape:

- It builds 20 swordsmen into a wall of towers and keeps sending them, because "the last
  fifteen died" is not a fact any rule can read.
- It cannot counter. Archers against cavalry, spearmen against knights — the whole
  rock-paper-scissors the roster is built around is invisible to it.
- It cannot defend a place. It has no notion of *where* it is being attacked, only that it owns
  fewer things than it did.
- It cannot judge whether an attack worked. `attack` fires once and the standing orders keep
  soldiers walking at the nearest enemy forever, win or lose.

**Why not simply add more rules.** Because this is a vocabulary limit, not a coverage one. More
rules in the same language produce more precise blindness. What it wants is a second class of
condition — *what the enemy has, what I have lost recently, where the fighting is* — and the
moment those exist, "first match wins over a flat list" stops being the right evaluator too,
because two rules can both be urgent for different reasons.

**What is worth keeping when it is rebuilt.** The parts of 12.2b that are not implicated:
conditions rather than timers; costs read from the defs; reservation for saving up; a
deterministic hashed reaction delay; and one file per difficulty in `data/`, which is what makes
a modded AI possible at all.

**Where it would start.** `AISystem._census()` is the one function that reads the world into
conditions. An enemy census beside the player's own is the smallest honest first step, and
`SimPlayer` already carries what a "what did I lose" window would need.

### Phase 15 — Scenarios & campaigns

**This is 12.3 grown into a phase.** That row has said "campaign: scripted triggers/objectives on
the host-loopback path" since before there was a screen for it; `Campaign.tscn` has been a frame
with a BACK button since 2026-08-21 and is the last front-door destination that is a placeholder
rather than a feature (§12.3). The spec is [scenarios/README.md](scenarios/README.md),
the project owner's, and it is the authority on the two screens and the folder layout.

**Phases 15 and 16 have no IDEA.md counterpart yet** — §0's numbering rule says phases ≥1 mirror
IDEA.md, and these two do not. IDEA.md wants rows for both; until it has them, this section and
the two READMEs are the whole specification.

**What ships first is deliberately thin content on a real mechanism.** One campaign, **"How To
Play"**, three scenarios, each on a **generated River map** (`MapGenerator.Type.RIVER`), each
against a **Passive** opponent (`SimPlayer.AILevel.PASSIVE`, which is real — 12.2b):

| Scenario | Teaches | Mode | Won by |
|---|---|---|---|
| 1 · How To Gather and Build | the economy | `SCENARIO` | own ≥ 1 `building.house` **and** ≥ 10 `unit.villager` |
| 2 · How To Age Up | the age ladder | `SCENARIO` | own age ≥ 2 (Age of Embers) |
| 3 · How To Find Opponent and Attack | fighting | **`LAST_MAN_STANDING`** | leave the enemy nothing — no units, no buildings |

**So a scenario picks between two win rules** and `ScenarioDef` carries which: the ordinary
conquest rule for anything whose goal is to beat somebody, and `SCENARIO`'s authored objective list
for goals that are not a fight. **Every scenario loses the same way** — own nothing and you are out
— so a scenario only ever declares how it is *won*.

The art is already on disk — `scenarios/HowToPlay/` holds `campaignIcon.png`,
`CampaignBackground.png` and a `scenarioIcon.png` per scenario. **No `campaign.json` or
`scenario.json` exists yet**, so 15.1 is writing the first ones rather than reading them.

✅ **SCENARIO 3 IS `LAST_MAN_STANDING`, SETTLED BY THE OWNER 2026-09-01**, and the reasoning is
kept because it is the expensive half to re-derive. It was specified as *"0 enemy units on map"*,
which **is not reachable against a Passive AI**: that level *"runs the whole economy and never
attacks"*, so it keeps training villagers from its town centre and the count refills faster than
an early army empties it. Widening it to units **and** buildings — *leave the enemy nothing* — is
the game's ordinary conquest rule wearing the words a player reads as *destroy the enemy*. It
needs **no new rule at all**, it keeps the Passive opponent, and it teaches the lesson the scenario
is named for: you cannot finish an enemy by chasing their villagers.

**Which makes scenario 3 the cheapest of the three and the one to build first** — an ordinary win
condition on an ordinary map, playable before a line of objective code exists. **15.2 is therefore
not a blocker for a playable campaign**, which is the opposite of how it read yesterday: 15.1 +
15.3 + a screen is a shippable scenario 3, and 15.2 is what unlocks scenarios 1 and 2.

✅ **All three launch as of 2026-09-02**, and the sequencing above paid off exactly as written:
scenario 3 was playable and play-confirmed a day before the evaluator existed. What it also
exposed is the cost of that order — **a FRESH player could not reach scenario 3 at all**, because
progress 0 unlocks scenario 1 only and scenario 1 could not start, so the one working mission was
locked behind two that were not. ⚠️ **And that is still half-true until 15.7**: nothing writes
`user://campaign_progress.json` yet, so finishing scenario 1 unlocks nothing. 15.7 is what closes
the loop, and it is now the only row between here and a campaign a player can play through.

*Two alternatives were considered and are recorded so they are not re-proposed: an inert AI level
(`data/ai_inert.json` with an empty rule list — cheap, but it adds a rung to a ladder 12.2b already
calls half-placeholder), and an unowned slot (`ai_players[i] = false` on a player no peer joins,
which `MatchConfig.debug_skirmish()` already produces — free, but it makes the opponent a target
dummy rather than an opponent).*

#### Five decisions that bind everything below

1. **A SCENARIO IS A `MatchConfig`, NOT A SECOND WAY TO START A MATCH.** 1.6's precedent is exact:
   the screen collects settings, `build_config()` returns a `MatchConfig`, `Net.pending_match`
   carries it across the scene change and `host_solo()` **consumes** it. A scenario screen is one
   more producer of that object. Nothing in the boot path, the net layer or `SimWorld.setup()`
   needs to learn what a campaign is, and §1.1's rule 4 keeps holding — a scenario is a solo
   match on loopback, so it exercises the networked path like everything else.
2. ⚠️ **NOTHING HERE IS INSIDE `res://` AT ALL, AND THAT IS WHY THE FOLDER MOVED.** The first draft
   put campaigns in `game/scenarios/` and progress in `campaign.json`; **both were wrong for the
   same reason** — `res://` is read-only once exported and baked into the APK, so a campaign there
   can be neither downloaded, shared, updated nor removed, and progress cannot be written at all.
   The owner's call, 2026-09-01: authored content is repo-root `scenarios/`, read from
   `user://content/scenarios/` on a device (§3.3); **player progress is
   `user://campaign_progress.json`**, keyed by campaign folder name. The two are separate files
   because they have separate lifetimes — an update is allowed to replace a campaign's folder
   wholesale and must not take the player's place in it with them. **The failure mode this avoids
   is silent on Windows**, which is where every check in this project runs.
3. **THE OBJECTIVE RULE RUNS IN THE SIM, ON THE SERVER.** §4's invariant admits no exception for
   scripting: if the client decides it won, the client can decide it won. So the objective list
   travels in `MatchConfig`, is evaluated by a sim system, writes only what `WinConditionSystem`
   already writes, and is folded into `state_hash()`. **Integer-only**, `market.json`'s rule
   (§9): a percentage or a float in a victory rule is a rule two CPUs can disagree about.
4. **INERT IS THE SAFE DIRECTION TO BE UNFINISHED IN** — 11.2's rule, and it has teeth here for a
   new reason. A malformed objective list must make the scenario **refuse to start**, not start
   and evaluate to true on tick 1. `_trophy()`'s note is the precedent: *"you lose when your
   trophy dies"* on a map with no trophies defeats everybody immediately.
5. **ELIMINATION STAYS THE LOSS, AND IN `SCENARIO` MODE OUTLIVING THE OPPONENT IS NOT A WIN.**
   MapMaker's README asked the designer to declare at least one lose condition; **they never have
   to**, because owning no units and no buildings is defeat in this game whatever a map says. So a
   scenario declares only how it is won, and a scenario whose answer is "beat them" declares
   nothing at all — it is `LAST_MAN_STANDING`, which is scenario 3. What `SCENARIO` mode must
   change is the *other* half of that rule: wiping out the passive opponent must **not** end
   scenario 1 in victory before the tenth villager exists. There, only the authored objective wins,
   and only elimination or resignation loses.

| # | Item | Tag |
|---|---|---|
| 15.1 | **Scenario and campaign data, and the loader.** `campaign.json` + `scenario.json`, typed into `CampaignDef`/`ScenarioDef` (`src/data/`, plain `RefCounted` like every other def) and read by a `Campaigns` loader that walks §3.3's **root list** — the editor-only dev override first, then `user://content/scenarios/`. **Not an autoload** — §6.1's table is exactly four and the front door is the only thing that reads this. See §11.7 for the schema and the traps | |
| 15.2 | ✅ **The objective vocabulary, in the sim** (2026-09-02). `MatchConfig.Mode.SCENARIO` + `objectives` + `objective_player_id`, an `ObjectiveSystem` immediately **before** `WinConditionSystem`, and per-player progress on `player_state`. **All three How To Play scenarios launch and all three can be driven to their win** (`dev_preview/PreviewScenarioWin.tscn`), so the campaign is finishable rather than a dead end behind two greyed rows. Three things the row did not predict, all in §11.8: a win row must **latch**; the vocabulary needed a sixth subject, `resource`; and **the reachability of an authored target is not obvious from the roster** — see §11.8's note on the scout | |
| 15.3 | **The launch path.** `ScenarioDef` → `MatchConfig`: two players, the human plus one Passive AI, `map_type = RIVER`, the seed pinned in `scenario.json`, `starting_age = 1`, and the scenario's own `mode` — `LAST_MAN_STANDING` with no objectives, or `SCENARIO` with them. One function, tested by asserting the config rather than by starting a match. ⚠️ **A pinned seed is not a pinned map** — §11.7's second trap | |
| 15.4 | ✅ **DONE 2026-09-01** — campaign selection. `CampaignScreen` builds a row per campaign found on disk: icon left, title top, description right, BACK at the bottom. **The last front-door destination that was a placeholder rather than a feature.**<br><br>**`Campaign.tscn` is now a three-line shell**, `Help.tscn`'s shape, and the screen is built in `_init()` — `HelpScreen`'s pattern, and it applies harder here because **the row list is data discovered at runtime**: a player may have one campaign installed or nine, so a `.tscn` could not hold this list even in principle. `_init()` rather than `_ready()` is also what makes it testable headlessly — `CampaignScreen.new()` is a whole screen with no `SceneTree` near it.<br><br>⚠️ **THE LIST IS INSIDE A `ScrollContainer` FROM THE FIRST LINE, AND THAT IS NOT DECORATION.** A `VBoxContainer` overflows — it does not clip, scroll or compress past its children's minimums — and the lobby shipped with its bottom nav strip off the screen for exactly this while every structural test passed, because a node asked for its rect returns that rect whether or not the window contains it. One campaign fits today; the ninth would not, and the failure only appears on the machine that has the content. `test_campaign_screen` asserts the parent is a `ScrollContainer` and deliberately asserts no measurement.<br><br>**New: `ContentImage.load_texture()`** — the one place that opens a PNG outside `res://`. `load()` and `ResourceLoader` **cannot open these at all** (no `.import` sidecar), so the route is `Image.load_from_file` + `ImageTexture.create_from_image`, per `scenarios/README.md`. Null is the only failure mode, because a campaign is shareable content and a malformed icon should cost a placeholder rather than a crash. 15.5 uses the same function for scenario icons and the background. A row with no icon draws a lettered plate.<br><br>**`open_campaign()` is the whole of what 15.5 replaces.** The row, the press and the campaign handed over are in place; the body currently answers with a `NoticeToast`, which is 1.1's rule for the front door — a button that visibly does nothing reads as a bug, one that says why reads as a plan. The screen owns its own toast rather than borrowing `MainMenu.tscn`'s `%Toast`, which is gone the moment this scene loads.<br><br>A campaign whose `campaign.json` is broken, or which has no playable scenario, is **shown and disabled with its first complaint as the blurb** — never hidden. A campaign that silently vanishes is indistinguishable from one the game failed to find, and the player has a folder on disk they can see. The empty-list notice distinguishes the two genuinely different cases: in the editor the dev override is live so an empty list means `scenarios/` is missing, while an exported build has no override at all and an empty list is normal until a pack is installed | |
| 15.5 | ✅ **DONE 2026-09-01** — `ScenarioScreen` + `Scenario.tscn` (a shell). Campaign title at the top, a scrolling column of scenario rows with everything past `progress` locked, the campaign background plus title/description/PLAY in the main panel, and selecting a row **swaps the panel without a scene change** — the background is a 1920×1080 decode and re-entering a scene to read a different paragraph would pay for it again.<br><br>**SCENARIO 3 IS NOW PLAYABLE END TO END** (15.1 + 15.3 + this), which was this row's whole point. PLAY parks the config on `Net.pending_match` and changes scene — the SOLO path `SkirmishScreen` already proves, where `GameScene._ready()` calls `host_solo()` and consumes it. Deliberately **not** `Net.start_match()`, which is for a lobby whose socket is already open.<br><br>**The campaign travels on `ScenarioScreen.pending`, a static**, on `Net.pending_match`'s precedent: a `CampaignDef` is a live object, not a path, so it cannot go through `change_scene_to_file`. One-shot — taken and cleared in `_init()`, so a second visit with nothing parked shows the no-campaign notice rather than silently reopening the last one. **A fifth autoload was the other option and was rejected**: 6.1's table is exactly four, and a global to save a field between two adjacent screens is a poor trade.<br><br>**New: `CampaignProgress`, READ-ONLY.** `user://campaign_progress.json`, keyed by `CampaignDef.folder`. 15.5 needs it to know what is locked; **15.7 adds the write.** Left read-only rather than stubbed with a `record()` that does nothing, because a write that silently fails is worse than one that does not exist. Every value is clamped and type-checked — the file is player-writable, so a negative would otherwise reach `unlocked_count()`'s `clampi` and lock the first scenario, giving a campaign that cannot be started and cannot be explained.<br><br>⚠️ **`_why_not_playable()` DELIBERATELY DOES NOT CALL `build_config()`.** That is the authority on whether a scenario can start and it is also the function that **generates the map** — a 192×192 `MapGenerator.generate` per row selection would cost a map every time the player browsed. So the panel uses a cheap predicate (locked / not playable / `mode == SCENARIO`) and `launch()` still asks the real one; if the two ever disagree, `launch()` wins, says so in a toast and pushes a warning rather than starting something broken. There is a test for that path.<br><br>**Objective scenarios refuse to start and say why in the panel** — scenario 1 and 2 are `"mode": "scenario"` and wait on 15.2. A disabled PLAY with its reason on a line of its own, not a tooltip: a disabled button on a touch screen has nowhere to hover, and one that simply did nothing would read as a broken game.<br><br>⚠️ **`test_scenario_screen` NEVER TRUSTS `user://` FOR LOCK STATE.** Progress is real state on the machine running the suite, so a developer who has played the campaign would get a different lock pattern from a fresh checkout — a test that passes for one person and fails for the next. Every locking test sets `_progress` directly; only one reads the file, and it asserts merely that reading cannot throw or go negative | |
| 15.6 | **The scenario message ✅ and the objective tracker.** ⚠️ **THE MESSAGE HALF LANDED EARLY, WITH 15.2, BECAUSE THE OWNER HIT IT IN PLAY** (2026-09-02): *"the map message did not show during play test… a scenario message is required and the user needs to tap the X to close it, interactive consent of the goal"*. `message` had existed in `scenario.json` and `ScenarioDef` since 15.1 with **nothing drawing it**, so all three missions launched with their goal invisible — the same hole `pop_used` and `garrison_cap` were in, a field the data fills and no reader reads. `ScenarioBriefing` is the modal; it rides `MatchConfig.scenario_message` as provenance (the HUD has never heard of a campaign) and **does not stop `SimClock`**, because on a host that clock is everybody's and the field is shared with skirmish. **Still to do: the tracker** — a live panel listing each objective with its progress ("Villagers 4 / 15"), read off `player_state.objective_progress`/`objective_done`, which 15.2 already writes and sends. The labels are **already on the client**: every client builds its own world from the same `MatchConfig` (2.4a), so only the numbers travel | |
| 15.7 | ✅ **Completion and unlock** (2026-09-02). On `match_over` with the local player winning, raise `user://campaign_progress.json`'s counter for that campaign. **One-way, a maximum, never decremented** — the same property that makes `SimPlayer.defeated` safe to read anywhere — and idempotent, because a result screen can be reached twice. **Found by the owner playing for it**: they reset the file to 0, won scenario 1 outright, and scenario 2 stayed locked, because until this row *nothing in the game had ever written that file*. `CampaignProgress.record_completed()` is the write; `MatchConfig` carries `campaign_folder`/`scenario_index` as provenance so `GameScene` can record a win without the HUD learning what a campaign is. Every function in `CampaignProgress` now takes a `path`, defaulted to `USER_FILE`, **so the tests never touch the developer's own progress** — a lesson that cost a false failure the same day | |
| 15.8 | ✅ **The "How To Play" scenarios** — content only, and it *was* only data, which is the row doing its job. **The owner wrote them, and there are FIVE rather than three** (2026-09-02, *"i added the final 2 scenarios, this completes HowToPlay"*): the economy, the age ladder, finding an opponent, the dragon, and a real duel against an **Easy** AI — the only mission in the campaign that can be lost to an enemy, since the first four face a Passive one that never attacks. All five load, launch and can be driven to their win (`PreviewScenarioWin.tscn`). ⚠️ **Two content gaps stand and are the owner's call, not defects in 15.1–15.7:** `scenario_4`'s briefing promises *"Destroy The Dragon AND Tame the baby"* but its map carries **no dragon and no nest** — it is byte-identical to scenario 3's, and 13.2's baby dragon has no def, no bake and no taming mechanic, so it is won by conquest like scenario 3; and scenarios 3, 4 and 5 all share **the same map** (seed 815103, 170 entities). ⚠️ **A test must never hardcode how many scenarios there are** — that constant broke six tests the day content was added, and `_at_progress(2)` silently stopped meaning "all unlocked" | |
| 15.9 | **`dev_preview/preview_campaign.tscn` + tests.** The preview photographs selection → scenario → launch. The tests are the load-bearing half, and there are four cases rather than three: **drive the sim to each of the two objectives and assert it fires**; assert that wiping the opponent in `SCENARIO` mode does **not** win (decision 5, and the one no screenshot can see); and drive scenario 3's conquest to a real `LAST_MAN_STANDING` result. A win condition that never fires is invisible from every screenshot. **Half done: `dev_preview/PreviewScenarioWin.tscn` drives EVERY shipped scenario to its win** through the real path — `Campaigns` → `build_config` → `SimWorld.setup` → `MapGen` — and prints mode, rows, progress, latches and **population** as it goes. It was built to diagnose a play-test failure and earned its place immediately: the population line is what exposed the scout. The four cases above live in `test_objectives`/`test_campaigns`; what 15.9 still owes is the SCREEN half, `preview_campaign.tscn` | |

**Build order is the numbering**, and every row above is meant to be a place you can stop — with
one licence: **scenario 3 alone is playable at 15.1 + 15.3 + 15.5**, since `LAST_MAN_STANDING`
needs no objective code, so 15.2 may trail the screens if seeing the campaign sooner is worth
more.

#### 11.7 Scenario and campaign data (15.1)

Layout is the owner's, from [scenarios/README.md](scenarios/README.md), with progress moved out of
it and the whole folder moved out of `game/` (§3.3):

```
scenarios/HowToPlay/                 # repo root, in git. NOT inside res://
  campaign.json                      # name, description, order of scenario folders
  campaignIcon.png                   # 256x256   ✅ on disk
  CampaignBackground.png             # 1920x1080 ✅ on disk
  scenario_1/scenario.json           # name, description, message, map, mode, objectives, opponents
  scenario_1/scenarioIcon.png        # 256x256   ✅ on disk

user://content/scenarios/HowToPlay/  # the same folder, installed - what a DEVICE reads
user://campaign_progress.json        # {"HowToPlay": 1}  -- how far the PLAYER has got
```

**The loader takes a root list, not a path** (§3.3): the editor-only dev override pointing at the
repo folder, then `user://content/scenarios/`, first match wins by campaign folder name. That is
what makes a bundled root — should the tutorial ever want to be present offline on first run — a
config line rather than a rewrite.

⚠️ **THESE PNGs ARE NOT IMPORTED RESOURCES AND `load()` CANNOT OPEN THEM.** Outside `res://` there
is no `.import` sidecar and no `--import` step that would make one; `Image.load()` +
`ImageTexture.create_from_image()` is the route, as it is for a saved map's PNG (11.3). §3.3 has
the cost: no VRAM compression, no mipmaps — irrelevant at these sizes — and a real decode for a
1920×1080 background, so **load a background when its campaign is opened, never all of them behind
the selection list.** *(This replaces a trap recorded here on 2026-09-01 and now false: while the
folder was under `game/`, the icons were invisible until `--import` had seen them. The move
inverted it — they are never imported at all.)*

⚠️ **A PINNED SEED IS NOT A PINNED MAP.** `MatchConfig` carries `seed` as *provenance only* and
says so at length — 12.1's terrain-is-a-transfer decision exists because `FastNoiseLite`'s float
maths is not identical across CPUs, and 11.3 makes the same point for saved maps: *"the seed alone
cannot reproduce a map, because any generator change makes the same seed produce something else."*
So a scenario pinned by seed **will silently play a different map** after any `MapGenerator`
change. That is acceptable for these three and only these three, because their objectives are
about counting villagers and ages rather than about a place — and it is precisely why the second
half of the owner's plan (a hand-built look, and "The Dragon Born") needs **2.4c's saved map
format** underneath it. When a scenario names a *file*, this trap is gone.

Progress is a single integer per campaign, and `campaign.json` declares its scenario order
explicitly rather than sorting folder names — `scenario_10` sorts before `scenario_2`, and a
campaign's order is a design decision anyway.

#### 11.8 The objective vocabulary — ✅ BUILT 2026-09-02 (15.2), and 16.6 also writes it

##### ⚠️ A WIN ROW LATCHES ONCE MET, AND THE FAILURE THAT PROVED IT NECESSARY

An objective list is a **checklist, not a snapshot**: a win row that has ever been satisfied
stays satisfied, in `SimPlayer.objective_done`, one-way exactly as `SimPlayer.defeated` is
one-way and for the same reason — a verdict that could flicker off would take the result
with it. It is also what the player already believes is happening, because a ticked line on
a goal list does not untick.

**The concrete case has since been withdrawn, and is recorded anyway, because the trap it
demonstrated is real and cheap to walk back into.** For a few hours on 2026-09-02 scenario
2 asked for *"gather 500 food"* AND *"advance to the Age of Embers"*. Advancing to age 2
costs **exactly 500 food** (`ages.json`) and `AdvanceAgeCommand` deducts it when the advance
**starts** — so the food row was true at the moment the age became affordable and false from
the instant it was bought, 100 ticks before the age arrived. ANDed, the two could never be
true on the same tick, and that scenario would have shipped **unwinnable while looking
completely correct**. The owner then clarified that the 500 food was *"purely user
guidance"* and it is no longer an objective.

So **nothing shipped depends on the latch today.** It stays because *any* ANDed pair where
satisfying one row SPENDS what satisfied the other has the same shape, and a resource is
only the most obvious such thing: units die, buildings fall, an age is bought. Evaluating
live would make every one of those a scenario that has to be won on a single tick.
`test_objectives` keeps the withdrawn pair as its own case, so the rule that would break
first if the latch were ever removed as "unused" is the one under test.

`lose` rows do **not** latch and do not need to: a lose row ends the match on the tick it
fires. `alert` rows latch so 15.6 can fire a toast once rather than ten times a second.

##### The sixth subject: `resource` (2026-09-02), currently used by nothing

`unit` · `building` · `age` · `area` · `named_unit` · `ticks` could not express *"gather 500
food"* at all, so `resource` was added, reading `SimPlayer.stock` with the kind in `id`
(`food`/`wood`/`gold`/`stone`, pinned in `ObjectiveDef.RESOURCE_KINDS` and cross-checked
against `MapGen.STARTING_STOCK` by a test — `stock.get(&"foood", 0)` is 0, so a typo would
be an unwinnable scenario whose only symptom is that nothing happens).

**It is authored by no shipped scenario**, the row it was built for having been withdrawn
the same day. Kept rather than reverted: 16.6's Map Conditions screen is the obvious author
of one, and `subject` travels as an int, so removing and re-adding it means getting the
enum position right a second time. Declared-ahead-of-use is this vocabulary's existing
shape (`area`, `named_unit`, `ticks`) — with the difference that this one is fully
evaluated and tested rather than refused, so it cannot rot silently.

**It is appended to the enum, not inserted beside `age` where it reads better**, because
`subject` travels as an int: inserting would renumber `area`/`named_unit`/`ticks` and
silently reinterpret every objective already recorded or in flight. Same rule applied to
`MatchConfig.Mode.SCENARIO` and to `SimPlayer.Defeat.OBJECTIVE_FAILED`, both appended.

**It measures what is HELD, not what has ever been gathered** — `stock` is a balance, and
it goes down. Cumulative gathering would need a new per-player running total written by
`GatherSystem`, folded into `state_hash()` and carried on the wire; no authored scenario
has asked for it, and the latch makes *"hold 500 at some point"* mean what the scenario's
own overview tells the player to watch for.

##### ⚠️ AN AUTHORED TARGET'S REACHABILITY IS A PROPERTY OF THE MAP, NOT OF THE ROSTER

**The one that got through to a playtest, 2026-09-02.** Scenario 1 asks for *1 house and 15
villagers*. The arithmetic looked settled and was written into the scenario's note, into
the briefing text and into a passing test: a town centre provides 10 population and a house
5, so 15 villagers needs exactly one house, which makes the two win rows depend on each
other. **Every one of those three said the same wrong thing**, because all three were
derived from `buildings.json` and `MapGen.STARTING_VILLAGERS`.

The saved map hands each player **5 villagers *and* one `unit.scout_cavalry`**. Opening
population is 6/10, not 5/10. Fifteen villagers plus that scout is **16** against a cap of
15, so the owner played to 15/15 with fourteen villagers and a scout and could not train
the fifteenth. The scenario was still winnable — a second house is 30 wood — so what was
actually broken was the **briefing**, which claimed one house was enough.

**The owner then fixed it in the content rather than in the text** — *"i did not account for
the scout in the pop cap, resuting in the player needing a second house"* — moving the
target to **14**: fourteen villagers plus that scout against a cap of exactly 15. So one
house is exactly enough after all, this time for a reason that is checked rather than
assumed.

Three things follow, and the third is the general one:

- A test that asserts an objective is reachable must read the **map's own starting
  entities**, not the roster's constants — and must **derive** the answer rather than
  assert a number. That test has now claimed one house, then two, then one again; only the
  third version could not be wrong quietly, because it computes the house count from what
  the map grants and fails if the target or the starting units move.
- `dev_preview/PreviewScenarioWin.tscn` exists because of this: it drives every shipped
  scenario to its win through the real path — `Campaigns` → `build_config` →
  `SimWorld.setup` → `MapGen` — and **prints the population as it goes**, which is the line
  that made the scout visible. `test_objectives` could not have caught it: it builds its
  worlds by hand and so never sees what the map grants.
- **A rule that is correct and never reached looks exactly like a rule that is wrong.** From
  the player's chair both are "nothing happens", and 15.2's whole test suite passed while
  scenario 1 was, in practice, unfinishable without a hint nobody had given.

##### What was decided that the spec left open

- **`ally` includes the viewer.** It means YOUR SIDE. The only reason the owner axis has an
  `ally` is a co-op scenario, and a rule counting your teammate's houses while ignoring
  your own is a rule nobody would author; `self` is already there for the narrower question.
- **`age` over a set of players is the MAXIMUM**, which is the reading that works in both
  directions: *"an enemy has reached the Age of Embers"* is `>= 2` against the most
  advanced, and *"every enemy is still in the Age of Ash"* is `<= 1` against that same
  number. Minimum would invert the second; a sum would compare an age against a total.
- **Multiple `lose` rows are ORed**, unlike `win`'s AND. Two failure conditions that had to
  be true *simultaneously* would be a scenario you can only lose by bad luck.
- **`objective_player_id` is carried, never derived.** The obvious derivation — "the first
  player who is not an AI" — hands the economy lesson to the Passive bot, which trains
  villagers of its own. One int rather than a list: a co-op scenario wants one verdict
  about a SIDE, which `ally` already expresses, not one verdict per protagonist.
- **A building counts only when COMPLETE**, which is the population cap's rule and
  deliberately not the elimination rule's (that one counts a foundation, because it is
  answering whether the owner is still in the game). *"Build a house"* is not satisfied by
  pegging one out and walking away.
- **The winning scenario does NOT defeat its opponent.** `SimPlayer.defeat` records a
  reason and there is no true one — the Passive bot that just lost scenario 1 still owns
  its town centre. Writing `ELIMINATED` would be the forfeit bug again, and
  `GameScene._victory_subtitle` reads exactly that field, so it branches on the mode and
  says *"Objectives complete"* instead.

##### The two traps that would each have shipped a broken campaign

**GAIA IS NOT AN ENEMY.** `{"subject": "unit", "owner": "enemy", "==": 0}` is this
section's own example of *leave the enemy nothing*, and owner 0 owns the trees, the sheep,
the deer AND the wolves — so an evaluator counting "entities not mine" would make that row
mean **kill every animal on the map**. The owner set is resolved from `SimWorld.players`
and never from entity owner ids, so gaia is excluded by construction rather than by a
clause somebody could delete.

**AN UNPOPULATED WORLD MUST DECIDE NOTHING.** Same row: in a world with no entities, "the
enemy has 0 units" is TRUE, so a naive evaluator declares victory on tick 1 of every world
that has not been stood up — which is most of the sim suite — and `match_over` latches, so
the verdict sticks for the whole run. That is `_trophy()`'s shape exactly, and
`WinConditionSystem._world_is_populated` is reused rather than reimplemented. Relatedly,
`_count` returns **-1** for a subject it cannot measure and `_satisfied` fails every
comparison against it: 0 is a value that PASSES `== 0` and `<= n`.

#### 11.8a The vocabulary as specified (15.1's parse, 15.2's evaluation)

**One language, written down once.** MapMaker's Map Conditions screen and a hand-written
`scenario.json` must emit the same records or there are two dialects and the tool can author maps
the game misreads. The vocabulary is the union of what the two READMEs ask for and what the sim
can answer *without new state*:

```jsonc
// scenario.json / a MapMaker map's conditions
"objectives": [
  { "subject": "building", "id": "building.house", "owner": "self",
    "compare": ">=", "value": 1,  "output": "win", "text": "Build a house" },
  { "subject": "unit",     "id": "unit.villager",  "owner": "self",
    "compare": ">=", "value": 10, "output": "win", "text": "Reach 10 villagers" },
  { "subject": "age",      "owner": "self", "compare": ">=", "value": 2, "output": "win" },
  { "subject": "unit",     "owner": "enemy", "compare": "==", "value": 0, "output": "win" }
]
```

- **`subject`** ∈ `unit` · `building` · `age` · `area` · `named_unit`. The first three are pure
  counting over `w.entities` and `SimPlayer.age` and need nothing new. **`area` and `named_unit`
  are 16.5 and 16.7's** — they need map data and per-entity overrides that do not exist yet, and
  they must be **rejected at load** until they do rather than silently evaluating as zero.
- **`owner`** ∈ `self` · `enemy` · `ally` · a player index. This is the axis the AI famously does
  **not** have (Phase 14) and a win condition may have freely: the rule runs on the server, which
  can see the whole world. Route it through `Diplomacy` and pass the team table — the argument is
  **required with no default** for §4.13's reason.
- **`compare`** ∈ `>=` · `<=` · `==`, integer only.
- **`output`** ∈ `win` · `lose` · `alert`. `alert` fires a `NoticeToast` and is what makes a
  scenario able to *say something* mid-match without ending it.
- **Multiple `win` rows are ANDed** — scenario 1 is two rows, and "a house and ten villagers" is
  one objective in two halves. An OR would need grouping and no scenario wants it yet; say so in
  the loader rather than leaving the reader to guess.

**Where it runs and what it may write.** `ObjectiveSystem` goes immediately **before**
`WinConditionSystem`, for `wildlife_system`'s reason inverted: the objective must be judged on the
finished tick, and the win system must see its verdict on the same tick rather than the next.
It writes `SimWorld.match_over`/`winner_id` and `SimPlayer.defeat()` and **nothing else** — the
same four fields, so `ResultScreen` needs no new reader.

**Two things it must carry that do not exist yet.** Objective **progress** per player, as a small
array of integers on `player_state` (the channel stock, population, age and control groups already
use, so a rejoining client picks it up for free — and it is what 15.6's tracker draws). And
`SCENARIO` in `state_hash()`'s outcome fold, which it gets free by being the same fields.

⚠️ **`SCENARIO` MODE MUST SUPPRESS LAST-MAN-STANDING'S WIN AND KEEP ITS LOSS.** Half of
`_last_man_standing` is wanted and half is not: owning nothing is still defeat, and outlasting the
opponent is **not** victory — otherwise killing the passive AI's five villagers and its town
centre wins scenario 1 with two villagers and no house, and the scenario teaches the opposite of
its name. This is a genuine fork in a function whose header currently argues it counts sides; do
it by calling the elimination half and skipping the sides half, not by copying the function.

✅ **Built as specified**: `_eliminate_the_bankrupt()` is the shared half and
`WinConditionSystem._scenario()` calls it without the sides rule. Two consequences worth
naming, both tested: wiping out the opponent eliminates *them* and ends *nothing* (the human
plays on until the objectives are met, which looks like a hang and is not), and the `< 2`
player guard does **not** carry over — it exists upstairs because "last man standing" is
trivially true of somebody with no opponents, whereas a lone player who loses everything has
genuinely lost a scenario.

### Phase 16 — MapMaker (the PC authoring tool)

**A separate Godot project in `MapMaker/`, PC only**, spec'd by
[MapMaker/README.md](MapMaker/README.md) (the owner's). It authors maps and scenarios for the
game; it is never shipped to a player and never runs on a phone. `MapMaker/README.md` is the only
thing in that folder today.

**Its purpose in the plan's order is the SECOND half of the owner's sequence:** Phase 15 ships
three placeholder scenarios on generated maps, then this tool re-authors those three maps for a
custom look, and then a second campaign — **"The Dragon Born"** — is built with it. So Phase 16 is
what turns scenarios from a mechanism into content, and nothing in Phase 15 waits on it.

#### Six decisions that bind everything below

1. ⚠️ **2.4c IS A PREREQUISITE, NOT A NEIGHBOUR.** MapMaker's whole output is a map file, and
   §11.3 is where that file's format is decided. Building the tool first means inventing a second
   format and then reconciling two. **2.4c moves up the queue because of this**, and its own
   section already carries the three rules the format must satisfy.
2. **THE FILE FORMAT IS THE CONTRACT, NOT THE CODE.** Two Godot projects cannot share a `res://`.
   So MapMaker **reads the game's data live** — `data/*.json` for the placeable roster and its
   footprints, `assets/atlases/` for the icons — from a path in a local, gitignored config file,
   which is `tools/isobake.local.toml`'s precedent for exactly this problem. It carries its **own
   copy of the format-critical trio**: `map_data.gd`, `iso.gd` and `atlas_entry.gd`, all three
   pure `RefCounted` maths with no dependencies. **A junction or symlink into `game/` is
   rejected**: this repo sits inside Google Drive sync, and a link there is one more way to
   corrupt a `.git` that has been corrupted once already (§1.3).
3. **THE COPIES CHECK THEMSELVES, because a copy nobody diffs is a copy that has drifted.**
   MapMaker reads the three originals **as text** from the configured game root at startup, hashes
   them, and **refuses to save** — loudly, naming the file — if they no longer match its own. That
   is the "make the check impossible to skip" shape the facing bug (§12A) was expensive for
   lacking: a green tool that writes a stale format is worse than one that will not start.
4. **`./maps` RESOLVED, AND THE ANSWER IS NOT UNDER `game/`.** The README said maps save to
   `./maps`, which was ambiguous between three directories. The tool writes **repo-root `maps/` and
   `scenarios/`** — the authored source, in git, outside the Godot project — and **nothing else**:
   not inside `game/`, which is `res://` and read-only once exported (§3.3), and not into `user://`,
   because installing content is the game's job. The game reads those folders in place during an
   editor run and `user://content/` on a device, and `user://maps/` stays the *player's* own saves
   so an install can never overwrite one.
5. **SAVING A MAP IS NOT SAVING A MATCH** — 11.3's rule, and the README brushes against it:
   *"maps played in the game can be saved to ./maps for later editing"*. What can come back is the
   **map the match was started with**, which is `GameScene`'s held map source. Round-tripping a
   half-built settlement with rubble in it is a save *game* and is 12.4.
6. **NO TOUCH, NO MOBILE, AND THAT IS A SIMPLIFICATION WORTH NAMING.** Mouse and keyboard only, so
   `TouchSlider`/`TouchLineEdit` and the whole `emulate_mouse_from_touch` hazard do not apply and
   `preview_touch_controls` is not a gate here. Stock `Slider` and `LineEdit` are fine in this
   project and nowhere else.

| # | Item | Tag |
|---|---|---|
| 16.1 | **Project skeleton.** `MapMaker/project.godot` on the pinned 4.7.1, windowed desktop, plus the local config naming the game root and the startup hash check of decision 3. Deliverable is deliberately tiny: it launches, reads the game's `data/*.json`, and prints how many unit, building, resource and terrain entries it found. If that number is wrong, nothing built on top of it can be right | |
| 16.2 | **The vertical slice: iso canvas, terrain painting, save, and LOAD IN THE GAME.** Grid overlay, paint each `SimMap.Terrain`, write 2.4c's format into repo-root `maps/`, then open it from the skirmish screen's map-source picker and play it. **This is the row that proves the contract**, and it is worth doing before a single object can be placed. It also exercises §3.3's dev override in the direction that matters — the tool writes a folder the game reads without either of them going through `res://` | |
| 16.3 | **The object palette.** Player 1–8 + Gaia dropdown, colour picker, category dropdown (Unit / Building / Area / Terrain), search filter, icons cropped from the staged atlases the way `ControlGroupSlot` already does it. ⚠️ **Never take `unit_ids()`/`building_ids()` order into the list** — `Array[StringName].sort()` orders by identity, not text, and not stably between runs; sort explicitly | |
| 16.4 | **Placement and the three cursors.** Select / move / edit, click to place, **drag to place walls** the way the game does — and the wall art's facing is settled and measured (§12A's third wall finding), so mirror `WallPlan`'s axis rule rather than re-deriving it. Footprint collision uses the **sim's** footprint, not the visual's measured extent; the two are different rects and both are right (§6's gotcha) | |
| 16.5 | **Areas** — named regions, which is a **new `MapData` field and therefore a `FORMAT_VERSION` bump** and a matching reader on the game side. They are what unlocks `subject: "area"` in §11.8's vocabulary, and until both ends exist the loader rejects it | |
| 16.6 | **The Map Conditions editor.** Writes §11.8's vocabulary and invents nothing: the same `subject`/`owner`/`compare`/`value`/`output` records. **It validates that there is at least one WIN and does not ask for a lose** — the README's "at least one lose condition" requirement is dropped, because owning nothing is defeat on every map in this game whatever it declares (Phase 15 decision 5), and a map whose answer is "beat them" therefore needs **no conditions at all**. A time limit is one more row with `subject: "ticks"` — and it must be **ticks**, not seconds, for `ages.json`'s reason | |
| 16.7 | **Per-entity overrides and named units** — the expensive row, and the only one with real sim cost. Health, attack, speed and a NAME on an individual placed entity means `SimUnit`/`SimBuilding` carry overrides, `MapGen.build_from()` applies them, and **`state_hash()` must fold them in** or two clients disagree about how much hp a scripted hero has. Named units are also what `subject: "named_unit"` needs. **Do not start here**; 16.2–16.6 are usable without it | |
| 16.8 | **Scenario export** — write a `campaign.json` / `scenario.json` pair and the icon slots beside the map, so a campaign is authored in the tool rather than by hand-editing JSON. This is where 15.1's schema gets its second consumer, and the schema is the one that must not move | |
| 16.9 | **`MapMaker/HOW-To.md`** — the owner's ask, and it is written last on purpose: a guide to an interface still being built is a guide that will be wrong | |
| 16.10 | **Content: re-author the three "How To Play" maps** for a custom look and feel, which also swaps their pinned seeds for pinned **files** and retires §11.7's seed trap; then **"The Dragon Born"**, the second campaign, built entirely in the tool | |

---

## 12. Post-MVP prioritisation

**Shipped since MVP**, one line each — the detail is in the phase item each names.
2026-08-17: fog of war (2.5), population cap (4.11), conquest win condition (11.1), field
yield balance (below), map generator (2.4b), skirmish screen (1.6), PlayTest AI (12.2a).
2026-08-21: real multiplayer a–g validated phone↔PC (12.1), the minimap's four corner
pages (8.2b), the UI batch. 2026-08-22: walls and gates (5.8), arrow projectiles (4.13),
the AI difficulty list (12.2b's list only), wall merging. 2026-08-23: tap targets for tall
and small art (4.3), terrain transition blending (3.1), hostile wildlife and the carcass
flow (4.13), roaming and fleeing (6.1b), herding (6.5), fishing (6.5).

**Still open, in the order it makes sense to take it:**

| Candidate | Impact | Effort | Notes |
|---|---|---|---|
| **Unit-speed balancing pass** | High — it is how the game *feels* | Low in code, playing time | `BUGS.md`. Walls, wildlife and three predators have all changed what "too fast" means since it was raised. **Only the owner can judge it** |
| ~~4.8 Garrison → 4.9 defensive bonus~~ | — | — | ✅ **DONE 2026-08-27.** It was billed as the largest hole in walls and it was not: the owner ruled walls out of garrison, so 0 A.D.'s eight turret points per medium wall stay unused by decision. It did close `garrison_cap` (declared on all 31 buildings since 0.4, read by nothing) and it gave buildings an **attack**, which nothing had |
| 2.4d Archipelago | Medium | Medium | New map type; the validator's connectivity claim has to change rather than relax. §11.6 |
| 12.2b AI decision flow | High | Medium-high | The difficulty *list* ships and the opponents behind it do not — Normal/Hard/Unfair are Easy wearing three names and say so on screen. Parked until the balancing pass has been played, because tuning an AI against unbalanced speeds tunes it against the wrong game |
| 9.x Ages & tech | High — the age axis carries what factions would have | High: four age skins of every building | **9.3 and 9.4 done 2026-08-29.** What is left is 9.5 (civilisations) and 9.6 (the age re-skin), and both are art-paced rather than code-paced |
| 5.7 More buildings | High breadth | Low in code; ~70 bakes in art | Art track paces it |
| **2.4c Save map** | **High, promoted** | Low-medium | §11.3. **It is the file format Phase 16 writes**, so it blocks the MapMaker and is no longer an optional convenience |
| **Phase 15 Scenarios & campaigns** | High — it is what PLAY leads to | Medium, in nine shippable steps | 12.3 grown into a phase. One campaign, three placeholder scenarios on generated River maps against a Passive AI, then a real objective vocabulary underneath them. **Owner's stated priority, 2026-09-01** |
| **Phase 16 MapMaker** | High — it turns scenarios into content | High; a second Godot project | **After Phase 15 and after 2.4c**, both by the owner's sequence and by dependency. 16.2 is the row that proves the format contract; 16.7 (per-entity overrides) is the only row with real sim cost |
| 12.1b reconnect | Medium | Medium | LAN **discovery** landed 2026-08-31 and closed the friction point (typing an IP). Getting back INTO a match after a drop is what is left, and it is the harder half: a returning peer needs the config, a full snapshot and its old player id |
| ~~12.3 Campaign~~ | — | — | ➡️ **Now Phase 15, above.** The one-line row was hiding nine steps |
| 12.4 Save/load and replays | Medium | Medium | Replay record/play already exists as a test fixture (0.7) |
| **11.2 King of the Hill** | Medium — a second win condition is a second way to play | Low-medium, and lower than it was | **Both open design questions were settled by the owner on 2026-09-01 (§11.9)**: the scoring ladder, and the target as a *duration* — five minutes uncontested, worked back to `KOTH_TARGET_SCORE = 9000`. What is left is three known pieces of work: a zone centre (a line in `MapGenerator`, or 16.5's authored areas), `SimPlayer.score` written **by side**, and the minimap ring. Trophy stays blocked on a `unit.dragon_baby` with no def and no bake |
| 4.12 Stances, 4.14 formations, 4.10 abilities, 5.3 upgrades | Medium | Medium each | 5.3 is half-built: the gate upgrade is the first real one |
| 13.x Dragons | The differentiator | Medium (art exists; needs rigging) | Once the RTS is a game |
| **Naval combat** | Medium | Medium | Newly *reachable* rather than newly wanted: ships float and path since 2026-08-23. Transports have no load/unload, and nothing has ever fought at sea. Archipelago is what would demand it |

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
| A.1 | Terrain tile set from 0 A.D. ground textures — grass, dirt, sand, shallow + deep water, rock, forest floor, plus `vis.cliff`. All 64×32 exact, no fitting | ✅ **and closed 2026-08-23.** The "remaining" here was transition and shoreline edges, and they are no longer art at all: `TerrainLayer` generates all 47 transitions per terrain from the one diamond each already ships (3.1), and the shoreline is a sand band the generator paints. Deliberate — the owner's call was that more sprites make theme packs harder |
| A.2 | Town centre + house, each with foundation and rubble. Foundations and generic rubble keyed by **footprint size** so the rest of the roster reuses them. No damaged tier — 0 A.D. has none, and health is the dot | ✅ |
| A.3 | Villager: 11 animations × **8** directions = 960 frames (8 not 5 — she holds an axe in one hand, so mirroring would swap it) | ✅ — one rebake owed (§13.2 item 9) |
| A.4 | Resource nodes: gold, stone, berry bush, deer + carcass, boar, sheep, wolf, fish, six extra tree species | ✅ except `vis.farm`. **The palms landed 2026-08-28**, and not as isobake variant selection: twelve new tree species were baked as separate ids and the GAME side picks between them, so the "no deterministic actor exists" problem was answered on the other side of the seam. `visuals.json` gained `variant_pools` — a per-map-type list keyed off the same tile seed the existing `variants` axis uses — and five palms now serve Island and River. Tree **size-class variants** stay open for the reason they always were. **`vis.farm` is NOT blocked** — corrected 2026-09-01, its recipe header had said so falsely since 2026-08-08. It was baked and staged on 2026-08-25 and the owner confirmed it in game. **0 A.D.'s "farm" is our "field"**, it attaches to the mill, and **fields do not age**: the game picks one of four at placement, `vis.field_1..4` → `field_age2` / `field_age3` / `field_age4` / `farm`. The 64-instance prop scatter really does collapse to one clump, and that is **accepted rather than open** — one clump reads fine at this camera and the four variants cover the variety it would have bought |
| A.4a | **Animate the wildlife — now the single most visible gap in the game.** Every fauna atlas is one static rest pose, and as of 2026-08-23 **six species move**: wolf, boar and bear chase and bite, deer roam and bolt, sheep and cattle are driven home by hand. All six slide. This project's own convention is that anything without a walk clip carries `speed: 0` precisely so nothing slides (ships, dragon, all three siege engines) — wildlife is the first thing to break it, knowingly, on the owner's call. Wolf needs the richest set and the only attack; cattle has a **Feeding** clip, the one idle that reads as an animal doing something | ✅ **Delivered 2026-08-28.** All six species now carry `walk`, plus `attack` on the three that bite, `run` on the deer and `feeding` on the cattle. Nothing slides any more. Two clips arrived on one species and not its siblings, so `AtlasEntry._ANIM_ALIAS` rewords the request rather than guessing — `run` falls back to `walk` and `feeding` to `idle`, both synonyms rather than second guesses. **The deer was distorted and was fixed the same day** (`d0d14af`): 52 px wide head-on against a sheep's 14, and 41 to 83 px of height inside one standing clip. The cause was not `location_scale`'s VALUE but that any non-zero value is wrong — it multiplies pose-bone *location* curves, and between two rigs that merely share bone NAMES (the deer's clips carry 40 bones against its actor's 37) rotations transfer and locations do not, at any scale. **0.0 is the answer, and the original 0.0319 was found by probing 0.022 to 0.045 and eyeballing, so the search range never contained it** — judged at `directions = 1`, where a rigidly tilted animal looks fine, because the defect only shows as the silhouette changes with turning. 24 px head-on now. **The per-direction height spread is the check that catches this class** and is worth keeping as the standard one for fauna: healthy is x1.33–x1.48 (wolf x1.40, sheep x1.48), the deer was x2.09 and is now x1.51 |
| A.4b | ✅ **Closed 2026-08-23** — this said `res.cattle` and `res.bear` had no art at all. Both are baked, staged and now declared; every fauna atlas the game names exists. What replaced it is a **carcass** gap: only `vis.deer_carcass` is baked, and five defs draw it (`res.deer_carcass` plus wolf / boar / bear / sheep). A dead deer where a dead bear should be is the wrong animal, and it beats the magenta unknown, but four bakes are owed. `asset_request.md` | ✅ **Closed again 2026-08-28.** All six carcasses are baked, staged and declared; every animal dies as itself. What is owed now is **measurement, not art**: the projection inversion returns NEGATIVE heights for a carcass — structural, and no choice of frame fixes it, because a body lying flat has no vertical extent to invert — so all five new `footprint_m`/`height_m` figures are the deer carcass's proportions scaled onto each animal's measured live figure. Filed as [P5] |
| A.5 | UI chrome from the itch.io dragon packs | Largely in use |
| A.6 | **Player colour — prerequisite, not polish** (§2.7 consequence 3). Bake untinted, emit the source alpha as a mask page, tint in a `canvas_item` shader. **Blend mode decided:** neither obvious option works — *multiply* (0 A.D.'s) makes white a no-op and crushes dark colours, compressing the lightness ladder; *luminance-preserving hue transfer* destroys the ladder outright, since every colour inherits the texture's lightness and all eight end up equally light. The answer is the palette colour setting the **base** level with the texture contributing only its **local deviation**: `lit = pc + (lum(tex) - 0.5) * k`, `out = mix(tex, lit, mask)`, `k ≈ 0.8` scaled by remaining headroom so a light colour does not clip flat. **The mask needs its own greyscale page** (~+12% atlas bytes) — the sprite's alpha is already the silhouette cutout, and those are different questions about the same texel. Do not smuggle it into intermediate alpha values, which bilinear filtering will smear | ⚠️ **DELIVERED, BUT NOT BY THIS MECHANISM — read the row above as history.** No mask page and no `canvas_item` shader was ever written. **Colour is baked in, one atlas per colour**: `vis.<id>.<colour>` from the eight words in `colours.json`, 21 colourable units × 8 = 168 generated recipes, and the game derives the path from a `"colours": true` flag. So §2.7's *"eight players cannot mean eight bakes of every unit"* was overruled in practice, and the cost it warned about is real and paid — a colour set is 16 sequential bakes, because the parallel-slot race (§4) makes them the worst case. **Not every actor can take colour and it cannot be read off the material** — always measure |
| A.7 | Audio: take `audio/{actor,attack,resource,interface,ambient,music}` whole, plus **`audio/voice/latin` and nothing else** (§9.2.1). Nothing baked depends on it | ✅ **Done 2026-08-23, with two deliberate departures from "whole".** (1) **Five variations per sound group, not all of them** — `lumbering` ships 22 chop samples and `gathering` 66; the ear is listening for "not the same twice" and five is past that, so taking every one spent the audio pack's 50–100 MB budget (§3.2) on chopping noises. `--max-variations` raises it and re-fetches only the difference. (2) **8 of 62 music tracks**, chosen against the age ladder — the other 54 are 219 MB nothing selects. **And a hazard worth knowing:** the .ogg files in the 0 A.D. checkout are git-LFS *pointers*, that repo's index carries ~30k staged deletions so `git lfs pull` exits 0 having done nothing, and the host is behind an Anubis bot wall that a `git-lfs` User-Agent passes. `tools/stage_audio.py` goes round all three and **writes nothing into the art checkout** |
| A.8 | Military unit art — ~22 bakes, one hand-picked actor per unit, no per-age variants. **A full re-bake is owed on two counts and they should be spent together:** the corrected actors (§9.2) and the ground-decal strip. `vis.trebuchet`/`vis.trade_cart` stay blocked on isobake's armature picking and its lack of particle support for impact VFX. ~22 against the ~88 four factions would have cost is where the single-civilisation decision actually pays | ✅ **DELIVERED.** The roster is baked, staged and colourable. **The two blockers named in this row are resolved and the note is out of date**: `vis.trebuchet` animates (the fix was one line of `[source].actor`, not the pipeline change the recipe predicted), and `vis.trade_cart` with it. Particle VFX for impacts was never needed — projectiles are their own atlases. **What is still open on siege is cosmetic**: the two packed engines carry no player colour ([P6]) and the owner has reported them as not looking right (board card `P9-packed-siege`) |
| A.9 | **Dragon + nest** — not bespoke after all: `fauna/dragon.xml` ships with 0 A.D., complete and textured, 9.2 m wingspan; the nest composes from existing gaia props | ⚠️ **RIGGED 2026-08-30, still static in game.** The mesh had no armature; it was sent to an auto-rigger and came back with a 43-bone skinned rig and the full clip set (walk, idle, attack, die, fire-breath). **Two things stand between that and a sprite** and both are on board card `P7`: `adapters/generic.py` is still a `NotImplementedError` stub, so isobake cannot bake a non-0 A.D. source at all; and the rigger stood the dragon **upright on two legs** (biped bone names, 5.44 m tall against a 3.76 m source), which is an owner decision rather than a defect. **The clips are in `Untitled.blend` only — the `.glb` named after them contains none of them.** `footprint_m` is settled at the wingspan, `[9.19, 8.11] / 3.76` |
| A.10 | **Building roster, age by age** — ~70 bakes. **The first batch is five buildings, not seventy**: age 1 unlocks only town centre, house, mill, mining camp and lumber camp, which is a complete playable settlement. Age 2 adds eight. Two free savings: composite props are the same gaia assets in all four ages, so bake once and reuse; the five age-3 buildings need only two skins each. Deliberately **not** taken: collapsing ages 1 and 2 (both Celtic, so similar) — it saves ~12 bakes at the cost of the first age transition any player ever sees, which is the entire payoff of the age axis. **Measure all four skins before declaring a footprint** — it is the max across ages and cannot be read off the age-1 bake | ✅ **CLOSED 2026-09-01** on the owner having played it: *"all assets excluding dragon, packed engines looks good."* Every declared building carries a staged atlas and a four-age map. **It had been finished for some time while its card said "running in the background"**, which is what blocked 5.7 and 9.6 for longer than the art did. **Not closed by the facing/colour/clip pass**, so a building bug reopens it rather than contradicting the closure. Fields turned out NOT to age — one of four picked at placement, and `field_age2.toml` records why those three must never be given a `variant_seed` |
| A.11 | **Walls and gates** — ~16 pieces across three tiers. Unblocked from the footprint side (all pieces share one footprint, all towers another, across every civ) | See the two findings below |

**Three art findings that cost real time and would cost it again.**

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

**A wall faces ACROSS its own length, not along it — and the game assumed the opposite for a
week.** Baking 8 directions is only half the contract; the other half is knowing which of the 8 a
given run wants, and `WallPlan.FACING_FOR_AXIS` was derived from `Iso.FACING_TILE_DIRS` on the
reading that a wall runs *in* the direction it is baked facing. It does not. Measured off the
staged pixels (regress mean opaque-pixel y against x over each frame; one screen tile is (32, 16)
px, so an axis-X wall must lean +0.5 and an axis-Y wall −0.5), the sprite baked **SW is the wall
lying along tile axis X and SE is the one lying along axis Y**. Every wall, gate, foundation and
rubble atlas agrees, bakes from before and after the gate batch alike, so this was never a rebake
regression — the code had never agreed with any staged art. It took **ninety degrees of visible
error and three screenshots** to find, because nothing else can feel it: a wall lying across its
own footprint has the same footprint, the same origin and the same `state_hash` as one lying along
it, and the frame sizes are identical too. `tests/view/test_wall_facing.gd` now re-measures the
staged pixels every run. **The general lesson, and it generalises past walls:** an art convention
that only a human eye can check is a convention that will be wrong for as long as nobody looks —
`WallPlan`'s header said "VERIFY THESE BY LOOKING" and `preview_walls` took the photographs, and
that was not enough. Atlas frames are pixels; measure them.

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
| **14** | 🪓 **A FINISHED RESOURCE BUILDING PUTS ITS BUILDERS TO WORK ON WHAT IT COLLECTS** (owner, 2026-08-23): *"after constructing a lumber yard everyone building the building automatically scans for nearby trees, same as units building a farm; units building a mining camp auto scans for gold or stone to mine."*<br><br>**THE FARM HALF ALREADY WORKS AND IS THE PRECEDENT BEING CITED** — [build_system.gd:74](game/src/sim/systems/build_system.gd#L74) has put a field's builder straight to farming since 2026-08-17, on the owner's call, with the reasoning "standing idle beside a finished crop is the wrong default: farming it is the only reason the plot was paid for". So this is **extending a rule that already exists**, not inventing one, and the same sentence justifies it: a lumber camp exists *only* to receive wood.<br><br>**Which resource needs NO new data.** `BuildingDef.drop_off` already declares exactly this, per building: `building.lumber_camp` → `wood`, `building.mining_camp` → `gold, stone`, `building.mill` / `building.dock` → `food`. So the rule is "find the nearest live node whose `kind` is in the finished building's `drop_off`" and the mining camp's "gold or stone" falls out of the data for free.<br><br>**The pieces to assemble, all of which exist:** the hook is `BuildSystem._finished`; the search is `AISystem._nearest_node(w, kind, from_unit)` ([ai_system.gd:587](game/src/sim/systems/ai_system.gd#L587)); the assignment is `SimUnit.set_task_gather(node_id, tile)` followed by `w.paths.request`, exactly as the field branch does it. **Lift the search rather than copying it** — `diplomacy.gd`'s header is a standing warning about precisely this, having been written after the same predicate was found in four places.<br><br>**It MUST be deterministic or it is a desync**, not a cosmetic bug: two hosts sending one villager to different trees diverges the sim. `_next_foundation`'s comment spells out the required shape — a strict minimum over (already-claimed, distance, id) walked in sorted id order, the same shape `CombatSystem._reacquire` uses.<br><br>**Three decisions the implementer does not get to duck:**<br>1. **Priority against `_next_foundation`.** Today the field branch wins over looking for another foundation. If the resource scan also wins, then finishing a lumber camp *during a wall drag* pulls that builder off the wall — which is the "builder stops after 1" complaint of 2026-08-22 coming back wearing a different hat. Foundation-first is probably right, and it is the opposite of how the field behaves.<br>2. **A radius bound.** `_next_foundation` is bounded by `SimSystem.SAME_WORK_RADIUS` (10) precisely so it means "the site I am on"; `_nearest_node` searches the WHOLE MAP and would happily walk a villager across it. Needs the same bound or a deliberate reason not to.<br>3. **`building.town_center` declares all four kinds** and is not a resource camp, so it would auto-task builders at every one. Exclude it, or key the behaviour off something narrower than "has a non-empty `drop_off`".<br><br>**Not in tension with §4.13's no-auto-acquire rule**, and worth saying so before someone raises it: that rule is about *combat* — a unit must not pick its own fights. This is economy, the relaxation has already been made twice on the owner's call (the field in August, foundations a week later), and every target it can find is a resource the player paid to build a camp next to | game side; small, well-precedented |
| **12** | 🖱️ **DOUBLE-CLICK A UNIT TO SELECT EVERY UNIT OF THAT TYPE ON SCREEN** (owner, 2026-08-23, from the session that also produced item 13 — *"the game feels amazing, and sounds great"*, so this is a want and not a defect). The genre-standard gesture, and the fastest way to gather an army without dragging a box across the HUD.<br><br>**Both halves already exist; only the filter does not.** `DoubleTapDetector` is real and already drives the ground tap and the minimap centre (`GameScene._ground_tap`, `_on_minimap_double_tapped`). And **the "on screen" query is exactly `GameView.units_in_box()`**, which box select already uses at [game_scene.gd:1640](game/src/view/game_scene.gd#L1640) — hand it the viewport's own rect in `_view`'s local space instead of a dragged rect and it returns every visible unit the player owns. So this is: double-tap a unit → `units_in_box(whole viewport)` → keep those whose `def_id` matches the one tapped → `_view.select(...)`.<br><br>**"On screen" is the load-bearing half of the spec**, and it is why the viewport rect matters rather than the whole map: every RTS scopes this to what you can see, or one double-click hands you every villager including the twelve mining on the far side of the map, which is worse than useless mid-fight.<br><br>**Do not build it on the ground-tap detector.** That one is entangled with the open double-tap-to-clear bug (BUGS.md, §8.8): a thumb wobbles, the router scores the second tap as a small drag, and the tap never reaches the detector. **The same root cause will bite this feature on a phone**, so `InputRouter.TAP_SLOP`/`TAP_TIME_MS` is arguably a prerequisite rather than a separate job — which is the opposite of the call made for 8.8, where a button sidestepped the router entirely. There is no button that sidesteps *this*. Desktop would work first and the phone would follow | game side; wants 8.8's router fix under it |
| **13** | 🏹 **AN ARROW SHOULD LEAVE THE BOW WHEN THE FIRE ANIMATION FINISHES** (owner, 2026-08-23). *"arrow particle or flying through the air does not match attack played animation, damage feels good, just bump the arrow fly to match attack sprite play speed so every time the fire animation is done an arrow leaves the archer."*<br><br>**Damage is explicitly NOT in scope** — the owner says it feels good, so `attack_cooldown_ticks` and `attack_damage` stay exactly as they are. This is a *presentation* fix: the release should land on the animation's last frame.<br><br>**Which makes it awkward, because the two live on opposite sides of §4's boundary.** The swing is `CombatSystem` counting `attack_cooldown_ticks` and calling `spawn_projectile` on the tick the cooldown hits zero ([combat_system.gd:100](game/src/sim/systems/combat_system.gd#L100)); the animation is `EntityView` advancing frames at `vis.fps(anim)`, the rate the atlas declares ([entity_view.gd:268](game/src/view/entity_view.gd#L268)). **The arrow therefore leaves on a tick boundary and the clip runs on its own clock, so the two drift apart by design** — nothing was ever synchronising them. Neither knows the other's timing, and the sim **may not** ask the view how long a clip is (`tests/sim/test_sim_boundary.gd` forbids it, and it would make combat depend on which art happened to be staged). So the fix is one of:<br>1. **Make the ART match the DATA** — set the attack clip's playback rate from `attack_cooldown_ticks` when the view starts it, so a 20-tick cooldown plays the clip over 2 s exactly. Keeps the sim authoritative and is almost certainly the right answer. **It is one line**: `entity_view.gd:268` advances frames with `var fps := vis.fps(anim)`, so for `anim == &"attack"` that becomes `frame_count / (cooldown_ticks * 0.1)` instead of whatever the atlas declares. The view already knows the unit's `def_id`, so it can ask `GameDataRegistry.unit()` for the cooldown without the sim being involved at all.<br>2. **Make the DATA match the art** — author cooldowns from clip lengths. Rejected on sight: it makes balance a function of the bake.<br>3. **Have the sim emit the projectile on a declared sub-tick offset.** Most accurate, most machinery, and needs a number per unit that nobody wants to maintain.<br><br>**Related and already known:** arrows carry no pitch (§13.2 item 5's sibling in `asset_request.md` [P5]) and read as fence posts, and `preview_projectiles.tscn` exists precisely because a projectile's entire job is to be looked at and a green suite proves nothing about it. Whoever takes this should shoot that preview before and after | game side; presentation only |
| **11** | ✅ **CLOSED 2026-08-23 — audio is built.** This said "AUDIO IS NOT BUILT, and this document said it was", which was the finding that started it: §7.5 had claimed an `AudioManager` existed for months when there was no such file and zero call sites, and it survived because the only references to it were comments in the code citing this plan. Now real — `AudioManager`, `MatchAudio`, `data/audio_map.json`, `tools/stage_audio.py`, 131 sound ids mapped to 0 A.D. sound groups, mapped per unit and per menu item. **The design question this row named as the only one left — "mixing buses and per-category volume, since the SETTINGS page (8.2b) has nowhere to put a slider yet" — is answered:** UI, VOICE and AMBIENT route into SFX so three sliders (Master/Music/Effects) cover the whole mix, and they live in a shared `VolumePanel` used by both the in-match SETTINGS page and the front door's SETTINGS button, which until now answered with a toast saying settings did not exist. See §7.5 for the five decisions not worth re-litigating. **Remaining is bytes, not code:** 0 A.D.'s LFS endpoint rate-limits to ~1 object/20 s, so the fetch is incremental and unfinished; nothing waits on it, because an id with no stream is silence by contract | ✅ done; fetch is incremental |
| **15** | 🎙️ **VOICE CHAT — owner-named 2026-08-30 and this is its first record anywhere.** *"microphone and speaker for voice chat still planned later."* It is in no phase, has no section of its own, and nothing in `game/` anticipates it; the buttons are queued with the UI art set (`asset_request.md` [P8] §5) so the overhaul draws them in the same pass, and **drawing them commits nobody to building it**.<br><br>**The one design constraint worth writing down now, because it is the one that would be got wrong:** voice must **not** ride the command channel. `Net.submit_command` is RPC'd to the server and applied on a tick boundary, so audio through it would inherit `SimClock`'s 100 ms floor, arrive in lockstep chunks, and — if it ever touched `SimWorld` — land in `state_hash()` and desync the match. It wants its own unreliable channel beside the snapshot RPCs, the same way `ChatPanel`'s real implementation is specified as a reliable RPC pair on `Net` rather than a `Command` (§8.2b, and for the identical reason). The rest is real work with no precedent here: a capture device, a codec, mixing against the three existing buses (§7.5 routes UI/VOICE/AMBIENT into SFX, so a VOICE bus already exists in name), push-to-talk on a touch screen with no spare corner, and an Android microphone permission prompt | unscheduled; art queued, code not |
| 5 | **Second pack mirror.** Primary is settled (`aod.dragoon.co.za`); GitHub Releases is the obvious fallback. Costs nothing to defer — `packs.json` carries a URL *list*, so adding one is a manifest edit | before first public build |
| 7b | **Villager `work_mine` dress distortion** — a dress vertex weighted 100% to `hand_L` drags a fold when the mining pose diverges from the citizen's native ones. Fix is re-weighting or clamping the vertex group at import. Cosmetic, accepted, batched with the post-MVP art pass | post-MVP art pass |
| 9 | ⏸️ **Villager height, DEFERRED by the owner 2026-08-08.** She measures 2.178 m — taller than a stag, the wrong way round — and the fix is one line (`height_m` on the recipe) plus a 960-frame rebake. A `height_m = 1.93` attempt was reverted: the existing bake is confirmed good on device and a working pre-MVP asset is not worth disturbing. **The rebake becomes free** when §9.2.1's re-point to the Briton actor forces one anyway | polish |
| 4b | ✅ **CLOSED with 4.8 (2026-08-27): they are ONE concept, and both halves are now spoken for.** The question was whether `act_enter`/`act_garrison` and `act_exit`/`act_leave` are two distinct actions (board a transport vs garrison a building) or one with spare art. One. Garrison uses `act_garrison` for the building's action slot and `act_exit` for the roster's Empty button; the gate already borrowed `act_enter`/`act_exit` for its two states in 5.8. **`act_leave` is the only one of the four still unused and it stays as the spare** rather than being reclaimed — `unit.transport_ship` is in the roster and boarding one is the obvious second consumer. Nothing to bake, nothing to delete |
| 10 | ✅ **CLOSED 2026-08-29 — THE ATLASES WERE MIRRORED, NOT ROTATED, and it took two deliveries and a wrong specification to find that out.** Root cause was one sign in isobake's shared render path: `directions.py` documents `ORDER_8` as clockwise from screen-down and then turned the subject by `index * 45°` about +Z, which is counter-clockwise — **so the render walked the compass the opposite way to the labels it wrote**, and every `directions.stored = 8` atlas ever produced was reversed. Fixed in the pipeline as `isobake e6fc052`, with **no recipe changes at all**. *Four things survive the bug and are why this row is kept:* **(1) `yaw_offset_deg = 180.0` MUST STAY.** Index 0 is a fixed point of the sign flip, so the half-turn added on 2026-08-25 is *half* the correction; removing it puts every unit back to showing its back, which is what the game side's first request wrongly asked for. **(2) THE VERIFICATION WAS BLIND TO THE FAULT BY CONSTRUCTION.** The agreed check was "column 0 draws a face, column 4 a back" — and those are exactly the two columns a mirror about N–S leaves alone. It passed twice, and 242 atlases were re-baked against a `yaw_offset_deg` theory that could never have worked, because **no rotation undoes a reflection.** Any facing check reads columns **2 and 6** as well. `test_wall_facing` is the automated half; `preview_work_facing` is the half that wants an eye, and BUGS.md records how the close was confirmed — the riders east and west of a house both look at it, which a N–S mirror makes impossible. **(3) SCOPE WAS 171 ATLASES, NOT THE 82 UNITS.** Walls, gates, wall foundations and rubble are `stored = 8` and were reversed too. They passed `preview_walls` because the swap is *invisible on that art* rather than absent — each swapped pair has the same silhouette — so a green check on symmetric art says nothing about asymmetric art. **(4) NOTHING IN `game/` COMPENSATES, and that is the owner's standing rule.** A `directions_reversed` flag in `visuals.json` was built and reverted inside a day, twice: *"undo the reverse changes… i dont want to waist any more time on patching a known root cause."* A corrected bake was correct the moment it was staged, with no flag to remove and nothing to keep in step | ✅ done |

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
| **A SECOND GODOT PROJECT MEANS A SECOND COPY OF THE MAP FORMAT, AND COPIES DRIFT** | **High** | Phase 16 decision 2/3: the tool reads the game's *data* live from a configured path, carries only three pure-maths files as copies, and **hashes the originals as text at startup, refusing to save when they have moved on**. A tool that happily writes a stale format is the expensive failure — a map that loads and is subtly wrong, which is the class §12A's facing bug belongs to |
| **A SCENARIO PINNED BY SEED PLAYS A DIFFERENT MAP AFTER ANY GENERATOR CHANGE** | Medium | §11.7. Provenance is not reproduction — 11.3 and 12.1 both already say so. Tolerated for the three "How To Play" placeholders because their objectives count villagers and ages rather than places; retired for good the moment 16.10 swaps their seeds for saved **files** |
| **ANYTHING INSTALLABLE THAT LIVES IN `res://` WORKS ON A DESKTOP AND CANNOT WORK ON A PHONE** | Medium | ⚠ **CAUGHT BEFORE IT WAS BUILT, 2026-09-01**: the first draft of Phase 15 put campaigns in `game/scenarios/` and progress in `campaign.json`. `res://` is read-only once exported and baked into the APK, so that is unwritable *and* undownloadable *and* unshareable — three features lost to one directory choice. Both moved out (§3.3, owner's call). The general form: **ask whether content can arrive after the build ships**, and if it can, it never lives under `game/` |
| **A CAMPAIGN CANNOT REACH A PHONE UNTIL 0.3 DOES** | Medium | The consequence of the move above, and §3.3 states it rather than burying it: `user://` on Android is not `adb push`-able and the dev override is editor-only, so `AssetPacks` — **the one Phase 0 item still open** — is the only delivery route to a device. All of Phase 15 is exercisable on Windows and headless; the first on-device campaign run is what waits. Two escapes that need no redesign: Godot's external-data-dir setting for a debug build, or a bundled root seeded into `user://content/` on first run, which stays one config line because the loader is a root **list** |
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

*Rewritten 2026-08-23. This had grown into a numbered log of everything shipped since the
MVP, with the actual next actions at the bottom — and the numbering had been renumbered
twice, so cross-references inside it were drifting. The shipped list now lives in §12 as
prose; what is left here is only what has not been done.*

*This list's item 1 has been the AI twice running and is now **done both times**: the
unit-speed pass (2026-08-23, `962b1c5`) and then the AI re-tune it damaged, which turned into
**12.2b's rule engine** on 2026-08-27 rather than the piecemeal lever it was scoped as. The
owner: *"i am happy with the results"*, and *"the update system support customization and
supports random maps, thats the big win from this update."* What is left below is features.*

*Item 1 was 4.8 garrison and it is **done, with 4.9, on 2026-08-27** — see the Phase 4
table. It settled §13.2 item 4b (one concept, `act_leave` left as the spare) and it did
NOT close the wall hole it was billed as closing: the owner ruled walls out of garrison by
name, so 0 A.D.'s eight turret points per medium wall stay unused on purpose. What it did
close was `garrison_cap`, declared on all 31 buildings since 0.4 and read by nothing.*

*It also left the AI ladder's tick counts stale — the AI builds towers and castles, so
every rung now has to fight through one. Winners all held; `easy v normal` went from
t11366 to t18351. BUGS.md carries the new table.*

*Nothing on the numbered list moved 2026-08-27/28 and a great deal else did, which is worth
saying plainly: two days went on the art deliveries and on what the owner found by PLAYING.
Wired: twelve trees behind `variant_pools`, six carcasses, the wildlife walk clips, and the
packed engines' last blocker. Fixed from playtest reports: tower volleys (a garrisoned archer
now adds an arrow to the salvo), predators retreating from a settlement so early villagers can
be run home, spent projectiles lingering on the ground, villagers walking back to where the
town centre stood after it falls, a Forest map you can actually walk through, and — over two
attempts and three screenshots — **every wall being drawn ninety degrees across the run it was
dragged on**. Two of those were mine to have caught: the forest hung the owner's session
because I measured bandwidth and shipped without running the suite, and the wall report I
explained away as a presentation problem was a real geometry bug. The counterweight is in §12A's
third wall finding.*

**1. 2.4d Archipelago** (§11.6). One island per player, a few sheep, nothing hostile. The
content side is nearly free — `PREDATORS` is keyed by map type and read with `.get(type,
{})`, so an unlisted type gets no predators without a line of code. The work is that
`MapValidator` requires every start to reach every other by land, which an archipelago fails
by definition, so that claim has to *change* rather than relax.

*It also had a hole the other two do not: transports had no load/unload, so **an archipelago
was a map on which no player could reach another** and no win condition could fire. **Both
shipped together on 2026-08-29** rather than the type going out as a sandbox — see 11.6.
What is still missing is naval COMBAT: a loaded transport crosses unopposed, which is what
an archipelago will ask for next and not what makes it playable.*

*~~2. 8.8, the [X] clear-selection button.~~ **Built 2026-08-28.** It was the only thing on
this list the owner reported from actually playing a build, and it turned out to be a layout
problem rather than a UI one: the HUD's left edge had exactly 40 px of unspent height between
the control-group stack and the selection panel's own ceiling, so the button's size was
decided by arithmetic rather than chosen. The gesture and right-click both stay.*

*2026-08-29 moved a great deal and moved it OUT OF ORDER, which is the honest way to record
it. **PHASE 4 CLOSED** — 4.10 abilities, 4.12 stances and 4.14 formations, on the owner's
instruction to "close out the open steps". All three had sat open since 4.3 as UI placeholders,
which turned out to be why they were cheap: the formations menu had named its four shapes for
months, and 4.12 was a decision `CombatSystem`'s header had written down twice. **The dragon went
to the art side the same day** (`asset_request.md` [P7]) — one clip, `static`, so PLAN.md 13
cannot start until that changes. **Then item 2 below shipped ahead of item 1**, on a second
instruction the same day: the tech tree is wired (9.3 + 9.4) while Phase 5 is still open.*

**1. PHASE 5, BUILDINGS — up next, the owner's call on 2026-08-29.** Two rows were open and they
were very different jobs. **5.7, the full roster, CLOSED 2026-09-01 with no code written** (see
its own row): it was only ever paced by A.10 on the art side, and A.10 had in fact been finished
for some time behind a card that still said otherwise. **5.3, building upgrades, is the code half
and is already half-built**:
`BuildingDef.upgrades_to`, `UpgradeBuildingCommand` and `SimWorld.convert_building` all exist and
have shipped a real upgrade since 5.8 — the wall-to-gate conversion, which mutates in place and
keeps the entity id rather than respawning. What is missing is everything an upgrade that is not a
gate needs: a COST (the gate inherits the wall's), a TIME (it is instantaneous), and a decision
about whether an upgrade is a per-building action or a player-wide tech, which is the same
question 9.3 asks and is the reason the two are worth sequencing together. **9.3 shipped first
and answered it** — see the note under item 2: they are two mechanisms and an upgrade is the
per-building one. A cost and a time are what is left.

*~~**2. 9.3 `TechSystem`.**~~ **BUILT 2026-08-29**, on the owner's instruction to "wire up tech
tree 9" — and it went in ahead of Phase 5 above, which is still open. See the 9.3 and 9.4 rows.
Two things it left behind rather than closed:*

  - **THE AI DOES NOT RESEARCH.** Every `ai_profile` has declared `techs: true` against nothing
    since 12.2b, and it still does: `ResearchCommand` exists and no rule emits one. That is the
    same shape as the hole 4.11's population counter was in — a field read by something that
    nothing writes — and it is now a *balance* hole as well, because a human who buys Blast
    Furnace is fighting an army that never will. **The AI ladder's tick table in BUGS.md was
    measured before this and is not invalidated by it** (neither side researches), but the first
    rule that does research invalidates every row.
  - **5.3, building upgrades, is still open and its open question is now ANSWERED.** §15's item 1
    asked "per-building action or player-wide tech", and the owner's ruling settles it: an upgrade
    is an action tile on a building, and a *technology* is the player-wide thing bought there.
    They are two mechanisms, not one — the wall-to-gate conversion changes one building and stays
    `UpgradeBuildingCommand`. What 5.3 still needs is a COST and a TIME for a non-gate upgrade,
    and the queue that 9.3 just taught to hold a research is the obvious place to put the time.

*~~3. 4.13's pack/unpack state machine.~~ **Built 2026-08-28** — see the Phase 4 table's 4.13
row. All three engines travel packed and fight deployed, automatically, on an order rather than
on a button. The one thing left is cosmetic and is with the art side: the packed onager and
trebuchet have no colour bakes, so a blue player's engine turns plain while it is rolling
([P6] in `asset_request.md`). The original text is kept below because its reasoning about WHY
it waited on art is the part worth re-reading.*

**~~3.~~ 4.13's pack/unpack state machine — and it moved because the ART LANDED, 2026-08-28.**
This was the last open item in 4.13 and it had been waiting on one thing since 2026-08-22:
every siege atlas staged was the *unpacked* pose, so the machine had no way to show its two
states apart and building it against a magenta placeholder would have proved the transition
happened without proving it was the right way round. **All THREE packed atlases are now
staged** — `vis.onager_packed`, `vis.trebuchet_packed` and `vis.ballista_packed`, which this
item said was unbaked. **They are deliberately NOT declared in `visuals.json`** — an id
referenced by nothing reads a year later as art that failed to land — so the declaration goes
in with the machine, in one commit. Three things already known: the onager's packed actor
**animates** (`idle`/`walk`, 120 frames) so it must not get `speed: 0`, the trebuchet's does
too as of `c64ccef` (its wagon was rebaked one level down so the ox-cart rig wins the pick,
at the cost of its four engineers), and colour is UNMEASURED on all three, so all start
`"colours": false`. **Nothing is waiting on art here any more.**

**AND THEN, THE SECOND STANDING ITEM: PHASES 15 AND 16 — SCENARIOS, THEN THE MAPMAKER.** *(No
number, deliberately: the numbers on this list have been renumbered twice and this file's own
header says the cross-references drifted both times. It sits after item 1 above.)* **The owner's
call, 2026-09-01**, and the two
new specs are theirs: [scenarios/README.md](scenarios/README.md) and
[MapMaker/README.md](MapMaker/README.md). The sequence they asked for, which is also the
dependency order:

1. **Phase 15, in its numbered order** — one campaign, "How To Play", three scenarios on
   **generated River maps** against a **Passive** opponent, with the objective vocabulary built in
   the sim underneath them. 15.1 (data + loader) → 15.2 (the rule, headless-testable with no
   screen in existence) → 15.3 (the launch path) → 15.4/15.5 (the two screens) → 15.6 (message +
   tracker) → 15.7 (progress) → 15.8 (the three, content only) → 15.9 (preview + tests that
   **drive the sim to each win**). **Scenario 3 is playable at 15.1 + 15.3 + 15.5** and 15.2 is
   what unlocks the other two, so there is a working campaign in the middle of that list rather
   than only at the end.
2. **2.4c, the map save format** — which stopped being optional the moment a tool exists to write
   it. §11.3 carries the promotion note.
3. **Phase 16, in its numbered order**, with 16.2 (paint → save → open it in the game) as the row
   that proves the format contract before anything is built on top of it.
4. **16.10** — re-author the three placeholder maps for a custom look, which retires §11.7's seed
   trap by giving each scenario a **file** rather than a seed, and then **"The Dragon Born"**, the
   second campaign, authored entirely in the tool.

**Two things settled on the owner's ruling the same day, both recorded where they bind rather than
only here.** ✅ **Scenario 3 is `LAST_MAN_STANDING`** — *leave the enemy nothing* — because "0
enemy units" is unreachable against an AI that never stops training villagers; Phase 15's opening
keeps the reasoning. ✅ **`scenarios/` and `maps/` moved out of `game/`** to the repo root, because
installable, shareable content cannot live in `res://`; §3.3 is the new content-delivery section
and it names the one real cost — **a campaign cannot reach a phone until 0.3 `AssetPacks` does**,
which promotes the last open Phase 0 item from "still open" to "on the path".

**Then, in no strongly forced order:** 12.1b reconnect (discovery landed 2026-08-31); **Phase 14,
the AI's enemy-blindness** (which is a rebuild of 12.2b's condition vocabulary, not a bug fix, and
wants a game whose balance is settled first); and 13.x dragons once the RTS is a game.

### What is waiting on art, not on code

*Swept again 2026-08-29 and it is now the SHORT version of `asset_request.md`, which is the
authoritative queue — a second full list is a second thing to keep in step, and it did not
get kept: the six delivered items that used to be spelled out here at length were all crossed
off on 2026-08-28 and none of them said so. They are one line each below.*

**Delivered, and every one of them wired:** the six wildlife walk clips and their `attack`,
`run` and `feeding` companions (A.4a); six carcasses, so every animal dies as itself; the
`vis.tree_teak` replacement, which came back as **twelve species** wired through
`variant_pools` (`vis.tree_banyan` was rejected on the teak's own grounds — the owner tested
it in a live grove and confirmed the tap problem); the deer's per-direction distortion; the
arrow and bolt pitch; and the packed siege actors. All 2026-08-28. **Nothing in `game/`
changed for any of them** — a corrected bake is correct the moment it is staged, which is the
whole point of never compensating for a bake defect in the game.

**~~The facing re-bake~~ (§13.2 item 10) — CLOSED 2026-08-29, and it took two goes and a
wrong diagnosis.** The first delivery (2026-08-27) re-baked 242 atlases against a
`yaw_offset_deg` specification that was **wrong**: the atlases were never 180° out, they were
MIRRORED, and a half-turn only moved the mirror's axis. The pipeline fix was `isobake
e6fc052`; the confirmation is in BUGS.md, and so is the lesson — **the agreed check read
columns 0 and 4, which are exactly the two a mirror about N–S leaves alone.** It passed
twice while the bug was there.

Still outstanding, in `asset_request.md`'s own priority order:

- **[P7] `vis.dragon` cannot move** — one clip, `static`. **The only art gap that blocks a
  phase**: 13.x is unstartable while the unit is a statue. It trains, fights and breathes
  fire today, so nothing is blocked now.
- **A.10, the building roster age by age** — running in the background rather than queued.
  It paces **5.7** (23 buildings, ~70 bakes) and every age skin **9.6** will want.
- **[P8] 27 technology icons** — backlog by the owner's instruction, filed with 9.3. Every
  research tile draws its name; the wiring when they land is data, not code.
- **[P5] Ten estimated `footprint_m` figures** — five animals and five carcasses, because a
  carcass cannot be measured by the usual inversion at all (§12A A.4b). They feed the
  selection ring and the occlusion band, not gameplay.
- **[P6] Player colour on two packed siege actors** — a blue player's onager turns plain while
  it is rolling. 16 bakes, and the only thing 4.13 left behind.

### Known gaps worth writing down rather than filing

- **A dock built inland before 2026-08-23 stays inland.** `requires_shore` gates new
  placement only; an existing dock will train ships that cannot deliver.
- **Naval combat does not exist.** Ships float and path since 2026-08-23, but transports
  have no load/unload and nothing has ever fought at sea. Archipelago is what would demand
  it, and it is not a prerequisite for the map type to be playable.
- **An open gate is open to everyone**, besiegers included. Per-player passability needs a
  pathfinding grid per player. §5.8 argues it, and the per-domain split of 2026-08-23 is
  evidence the shape is affordable — but per player multiplies by player count, not by two.
- **A static destroyed behind the fog stops being sent** rather than leaving AoE's stale
  ghost, which would need a per-player last-seen copy of every static (§11.4).
