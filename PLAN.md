# AOD Ã¢â‚¬â€ Implementation & Programming Plan

Companion to [IDEA.md](IDEA.md) (what we're building) and [UI_Design.md](UI_Design.md) (how it looks).
This document is **how we build it**: architecture, objects, functions, scenes, and phase order.

Missing-asset tracking lives in [ASSET_MISSING.md](ASSET_MISSING.md).

---

## 0. How to read this document

- Phases tagged **`[MVP]`** are implemented first. Nothing untagged is written until every `[MVP]` item is done, tested, and working on a physical Android device.
- Untagged items are full-scope scaffolding Ã¢â‚¬â€ they exist so we don't design ourselves into a corner.
- After MVP, phases are chosen by the impact/effort table in Ã‚Â§12.
- Phase numbers Ã¢â€°Â¥1 mirror [IDEA.md](IDEA.md). Phase 0.x is engineering groundwork with no IDEA.md counterpart.

---

## 1. Locked decisions

| Decision | Choice |
|---|---|
| Engine | **Godot 4.7.1-stable** (`Godot_v4.7.1-stable_win64`) |
| Language | **GDScript** |
| Renderer | **Compatibility** (`gl_compatibility`), 2D Ã¢â‚¬â€ *not* the Mobile renderer. Vulkan-Mobile driver crashes cluster on older Mali/MediaTek/Adreno parts, and the Mobile renderer supports **fewer** Android devices ([godot#111729](https://github.com/godotengine/godot/issues/111729)) for no 2D benefit |
| Orientation | Landscape, locked |
| Licence | **Code MIT, art CC-BY-SA 3.0** (Ã‚Â§2.3) Ã¢â‚¬â€ [LICENSE](LICENSE) Ã‚Â· [LICENSE-ART.md](LICENSE-ART.md) |
| Session model | **Always clientÃ¢â‚¬â€œserver, even solo** (Ã‚Â§1.1) |
| Simulation | Server-authoritative, fixed-tick, headless-capable |
| Sim tick rate | **10 Hz** (100 ms), render interpolated to display rate |
| Map topology | **Square grid**, rendered isometric |
| Units of measure | Integer sub-tile units, **1 tile = 256 sub-units** |
| Dev environment | **Native Windows** for editor + Android deploy; WSL/Docker for tooling (Ã‚Â§1.2) |
| Asset delivery | **Downloadable packs**, not bundled in the APK (Ã‚Â§3.2) |

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

### 1.2 Development environment

**Native Windows** for the Godot editor and Android deploys. Android USB `adb` from WSL2 requires `usbipd-win` passthrough and is unreliable; one-tap deploy to a physical device is a core habit (Ã‚Â§15).

**WSL2 + Docker** for:
1. The Python asset pipeline (`tools/`) Ã¢â‚¬â€ pinned dependencies, reproducible.
2. The headless dedicated server (Phase 12.1) Ã¢â‚¬â€ also verifies the `sim/` boundary held.
3. Running the checks Ã¢â‚¬â€ headless sim tests, boundary check, `licence_audit.py`.

> **There is no CI on this repo.** No `.github/` exists and nothing runs automatically
> on push. Every check described in this document Ã¢â‚¬â€ the headless suite, the `sim/`
> boundary check, the licence audit Ã¢â‚¬â€ is a **local command a developer runs by hand**.
> Where this document says a check "fails", read "fails when you run it", not "blocks a
> merge". The checks are all deliberately shaped as single commands with meaningful exit
> codes so that adding CI later is trivial, but that has not been done. Do not write
> "enforced by CI" anywhere until it is true.

Source lives on the Windows filesystem. Containers bind-mount it; never use Docker volumes for source.

### 1.3 Machine setup

**Working root for anything outside Google sync:** `C:\Users\herman.ras\Downloads\AOD_game\`

```
C:\Users\herman.ras\Downloads\AOD_game\
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ art_source\        # 0 A.D. art repo/checkout Ã¢â‚¬â€ large, never synced, never committed
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ art_work\          # Blender scenes, render output, intermediate frames
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ packs\             # built .pck files staged for website upload
Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ tools_env\         # Python venv for tools/
```

The Godot project stays in the Drive folder for now (`AOD_Mobile\game\`) but **should move to a local path at clean init** Ã¢â‚¬â€ a git repo inside Drive sync is what corrupted the last `.git`, and GitHub is the correct backup for an open-source project.

| Requirement | Version / notes | Status |
|---|---|---|
| **Godot** | `4.7.1-stable_win64` (current stable, released 14 Jul 2026) | Ã¢Å“â€¦ installed |
| **Android export** | Godot's Android build template + JDK 17 + Android SDK (platform-tools for `adb`). The editor installs most of it Ã¢â‚¬â€ verify at 0.1. **`export_presets.cfg` is tracked in git** (it holds no secrets Ã¢â‚¬â€ no keystore path/password, those live elsewhere) so `permissions/internet=true` ships for everyone; it must stay `true` or `Net.host_solo()` fails silently on-device even for a loopback-only session (Android requires INTERNET for any socket, discovered building 0.7's `StressTest.tscn`) | needed for 0.1 |
| **Python** | 3.11+ with `Pillow` + `numpy`. **No system install needed** Ã¢â‚¬â€ Blender bundles Python 3.11 and a venv made from it is fully isolated (`tools_env\venv`, created from `tools_env\blender-4.5.12-windows-x64\4.5\python\bin\python.exe`). Nothing leaks into Blender's own site-packages, and the venv cannot drift off the pinned Blender | Ã¢Å“â€¦ done at 0.9 |
| **Blender** | **4.5.12 LTS Ã¢â‚¬â€ hard pin, do not use 5.x.** COLLADA (`.dae`) import was *removed* in Blender 5.0 and 0 A.D.'s meshes are `.dae`. 4.5 LTS is the last version with it (supported to Jul 2027). Installed as a **portable extract** in `tools_env\`, deliberately not Steam/MS Store Ã¢â‚¬â€ an auto-update to 5.x would silently break the whole art track | Ã¢Å“â€¦ done at 0.9 |
| **`isobake`** | [`HermanRas/blender_3d_to_2d_isobake`](https://github.com/HermanRas/blender_3d_to_2d_isobake) (GPL-2.0-or-later) Ã¢â‚¬â€ the render/bake/verify pipeline, Ã‚Â§2.2. `pip install -e` into the venv | Ã¢Å“â€¦ built at 0.9 |
| **Blender addon** | [`StanleySweet/blender_pyrogenesis_importer`](https://github.com/StanleySweet/blender_pyrogenesis_importer) (GPL-2.0), pinned at `b31b5c4`. Imports 0 A.D. actor XML, resolving mesh + props + textures. **Does not import animations** Ã¢â‚¬â€ isobake attaches those. Last updated Aug 2024, so it needs two Blender-4.5 compatibility shims, which isobake applies at load time rather than forking the checkout | Ã¢Å“â€¦ done at 0.9 |
| **0 A.D. art** | `git clone --depth 1 https://gitea.wildfiregames.com/0ad/0ad.git` into `art_source\`. **Shallow clone matters** Ã¢â‚¬â€ full history is ~8.3 GB. Also **needs `git-lfs`**: the art is LFS-backed, and without it the clone succeeds but the checkout fails. Scope the fetch with `git config lfs.fetchinclude "binaries/data/mods/public/art/**"` | Ã¢Å“â€¦ done at 0.9 (~11 GB) |
| **git** | 2.47.1 | Ã¢Å“â€¦ installed |
| **Test framework** | **Custom `TestCase`/`run_tests.tscn` harness** (built 0.1Ã¢â‚¬â€œ0.7), kept instead of GdUnit4 Ã¢â‚¬â€ already covers headless tests, `state_hash()`, replays and the `sim/` boundary check with zero dependencies. GdUnit4 remains an option later if a real need (parallel execution, richer reporting) shows up | done at 0.7 |

Notes on the 0 A.D. checkout:

- Art lives **in the main repo** at `binaries/data/mods/public/art/` Ã¢â‚¬â€ there is no separate art repo to fetch.
- **Clone the repo; do not mine the game installer.** Releases ship a built `public.zip` where `.dae`Ã¢â€ â€™`.pmd`/`.psa` and `.png`Ã¢â€ â€™`.dds`. Those compiled formats have no maintained Blender importer.
- GitHub `0ad/0ad` is **archived** (Sept 2024) Ã¢â‚¬â€ browsable and useful for reference, but frozen. Gitea is upstream.

Nothing in this table blocks phases 0.1 or 0.5 Ã¢â‚¬â€ the Blender/0 A.D. items only gate the art track.

**Version policy: every version above is pinned.** Upgrading Godot or Blender is a deliberate task at a phase boundary with the test suite green before and after Ã¢â‚¬â€ never an "update available" click. Mid-project engine drift costs more debugging time than any newer release saves. If an upgrade is taken, record it here in the same change.

---

## 2. Art & assets

### 2.1 The asset seam

**Every visual and audio asset sits behind a stable ID. No filename appears in gameplay code.**

```gdscript
var vis := GameDataRegistry.atlas_for(&"vis.villager")
AudioManager.play_sfx(&"villager.chop")
```

`data/visuals.json` and `data/audio.json` are the only files mapping an ID to a path. Each ID resolves to a real atlas **or** a procedural placeholder (Ã‚Â§2.4), so gameplay never blocks on art.

### 2.2 Sources

| Domain | Source | Licence |
|---|---|---|
| Units, buildings, terrain, props | **0 A.D.** (`play0ad.com`) | CC-BY-SA 3.0 |
| Audio (starting point) | **0 A.D.** | CC-BY-SA 3.0 |
| UI chrome, fonts | **itch.io packs** already in `UI_Sprites/` Ã¢â‚¬â€ `UI_dragon-huds`, `uÃ„Â±-fonts`, `Free_Medieval_Fantasy_UI_Pack` | Per-pack; record in `LICENCES.md` |
| Dragon + nest | **Bespoke** Ã¢â‚¬â€ commissioned or hand-drawn | Ours |

0 A.D. is a 3D game; `tools/render_3d_to_iso.py` renders its models to 8-direction sprite sheets. Terrain comes from the same source Ã¢â‚¬â€ its ground textures are tileable, so the same Blender scene renders them to isometric tiles at the project camera angle. Single source keeps palette and style coherent and keeps attribution to one entry.

Repo layout we consume (`binaries/data/mods/public/`):

| Path | Contents |
|---|---|
| `art/meshes/{skeletal,structural,props,gaia,flora}` | `.dae` COLLADA meshes |
| `art/animation/{biped/{citizen,infantry,gatherer,Ã¢â‚¬Â¦},quadraped,mechanical}` | `.dae` animations Ã¢â‚¬â€ note `biped/gatherer`, directly relevant to the villager |
| `art/textures/skins/Ã¢â‚¬Â¦` | mostly `.png`, some `.dds` |
| `art/actors/{units,structures,fauna,flora,props}` | XML tying mesh + textures + animations + props together, grouped into variants |
| `audio/{actor,ambient,attack,interface,music,resource,voice}` | `.ogg` + XML descriptors |

Pipeline shape: **actor XML Ã¢â€ â€™ Blender (via the pyrogenesis importer) Ã¢â€ â€™ attach animation `.dae` Ã¢â€ â€™ render N Ãƒâ€” 45Ã‚Â° orthographic Ã¢â€ â€™ trim/pack Ã¢â€ â€™ atlas.** The importer resolves meshes, textures and props but not animations, so attaching those is the tool's job.

**Built at 0.9 as [`blender_3d_to_2d_isobake`](https://github.com/HermanRas/blender_3d_to_2d_isobake)** Ã¢â‚¬â€ its own GPL-2.0-or-later repo, working root `Downloads\AOD_game\blender_3d_to_2d_isobake\`, published so other 3DÃ¢â€ â€™2D projects can use it. It is deliberately **not** AOD-specific: 0 A.D. is one adapter, and glTF/FBX sources (the dragon, ASSET_MISSING Ã‚Â§3) go through the same camera. Only the *recipes* Ã¢â‚¬â€ which actor is our villager Ã¢â‚¬â€ are AOD content and live in this repo.

Two things the tool gets right that most such scripts do not, both cheap now and unfixable-in-place later:

- **Camera elevation is derived from the tile size**, `asin(tile_h / tile_w)` = exactly **30Ã‚Â°** for 64Ãƒâ€”32. The 35.264Ã‚Â° that isometric tutorials use is the cube body-diagonal angle and would make a 64px tile 37px tall.
- **One global `pixels_per_metre`** (22.627 here), never fit-to-frame. Framing each model to fill its canvas is the obvious implementation and it silently makes a villager and a town centre the same size on screen.

0 A.D. specifics that had to be discovered (all now in the tool's README): their COLLADA declares metres but a citizen measures 3.85 Ã¢â‚¬â€ the conversion is tile-to-tile via their own `TERRAIN_TILE_SIZE = 4`; base-texture alpha means transparency for `basic_trans_*` foliage but a **faction-tint mask** for `player_*` units, and confusing the two makes a quarter of every unit see-through.

No prior art existed for 0 A.D.Ã¢â€ â€™2D conversion. [`Maghwyn/blender_directional_spritesheets`](https://github.com/Maghwyn/blender_directional_spritesheets) (MIT) was the reference for the rotation loop.

**The GUI stays the dragon theme** from the itch.io packs. It does not come from 0 A.D.

Any additional source is added only on an explicit note from the project owner, and must be recorded in `LICENCES.md` and `CREDITS.md` at the same time.

### 2.3 Attribution obligations

0 A.D.'s `art/LICENSE.txt` and `audio/LICENSE.txt` require **three specific things** in the attribution. All three, verbatim:

1. A link to `http://creativecommons.org/licenses/by-sa/3.0/`
2. The original author named as **"Wildfire Games"**
3. A link to `http://www.wildfiregames.com/`

Plus:

- **Derived sprite sheets are themselves CC-BY-SA 3.0.** Our rendered output ships under that licence. Only the art is copyleft Ã¢â‚¬â€ **the Godot code is MIT** ([LICENSE](LICENSE)), decided at 0.9 when the repo was published. The two licences do not merge; [LICENSE-ART.md](LICENSE-ART.md) states which applies to what.
- **`CREDITS.md`** Ã¢â‚¬â€ in-repo and surfaced in-game on a Credits screen (phase 1.4).
- **`assets/LICENCES.md`** Ã¢â‚¬â€ per-asset provenance. `tools/licence_audit.py` exits non-zero on any shipped asset not listed. Run by hand; there is no CI (Ã‚Â§1.2).
- Downloadable asset packs (Ã‚Â§3.2) each carry their own `LICENCE` and `CREDITS` file inside the pack.
- Note: some of 0 A.D.'s `textures/` derive from CGTextures under special permission granted to that project. Worth a check before leaning heavily on raw texture files rather than rendered output.

### 2.4 Placeholder art

MVP ships on procedurally generated placeholders: isometric diamonds for terrain, capsules with a facing marker for units, sized rectangles for buildings Ã¢â‚¬â€ drawn at runtime from `visuals.json`, no image files.

```jsonc
{
  "vis.villager": {
    "placeholder": { "shape": "capsule", "size": [12, 24],
                     "color": "#D8C08A", "facing_marker": true }
  }
}
```

Every gameplay phase is therefore art-independent, and the seam is load-bearing from day one.

### 2.5 Normalised vocabulary

One villager, one gender.

**Entity IDs**

```
unit.villager        building.town_center     res.tree
unit.militia         building.house           res.gold_mine
unit.archer          building.barracks        res.stone_mine
unit.dragon          building.dragon_nest     res.deer
```

**Animation IDs**

| Anim ID | Used when | MVP |
|---|---|---|
| `idle` | Task.IDLE | **Ã¢Å“â€œ** |
| `walk` | moving, carrying nothing | **Ã¢Å“â€œ** |
| `walk_carry_wood` | moving, `carry_kind == wood` | **Ã¢Å“â€œ** |
| `walk_carry_gold` | moving, `carry_kind == gold` | **Ã¢Å“â€œ** |
| `walk_carry_food` | moving, `carry_kind == food` | **Ã¢Å“â€œ** |
| `walk_carry_stone` | moving, `carry_kind == stone` | |
| `work_chop` | gathering wood | **Ã¢Å“â€œ** |
| `work_mine` | gathering gold or stone | **Ã¢Å“â€œ** |
| `work_hunt` | gathering from a carcass | **Ã¢Å“â€œ** |
| `work_build` | building or repairing | **Ã¢Å“â€œ** |
| `work_forage` / `work_farm` / `work_fish` / `work_herd` | later food sources | |
| `attack` | combat | |
| `die` | death | **Ã¢Å“â€œ** |
| `decay` | corpse, pre-removal | **Ã¢Å“â€œ** |

Convention: **5 stored directions, mirrored to 8.** Halves art cost. Decided **per asset**, not globally, and it has two preconditions:

- The key light must lie in the camera's vertical plane, or mirrored frames are lit from the wrong side. `isobake` rejects a mirrored recipe under a non-symmetric rig.
- The subject must be laterally symmetric. A villager holding an axe is not Ã¢â‚¬â€ mirroring swaps which hand holds it. Verified on the turntable, not assumed.

The villager holds an axe during `work_chop` and carries wood at her hip during `walk_carry_wood` (animation-variant props, wired up per Ã‚Â§14), so `villager.toml` renders the whole recipe at `directions = 8` Ã¢â‚¬â€ mirroring is decided per recipe, not per animation, so `idle` and `walk` render at 8 too even though they would be mirror-safe alone.

`EntityView.play_anim()` tries `walk_carry_<kind>` and falls back to `walk`, so carry variants are always optional.

**MVP villager budget:** 11 animations Ãƒâ€” ~15 frames Ãƒâ€” 8 directions Ã¢â€°Ë† 1320 frames.

### 2.6 Practical handling

- Raw source art lives on a **local, non-synced** path Ã¢â‚¬â€ never in this Drive-synced project folder. The bake manifest points at it via a config value, never a committed absolute path.
- **Baked atlases are not committed** Ã¢â‚¬â€ settled at 0.3 staging, and `.gitignore` already
  had it right. They are build output, fully reproducible from the committed recipes plus
  `isobake`, and they reach players through the downloadable pack (Ã‚Â§3.2), so putting 6.7 MB
  of PNG into a Drive-synced git repo would buy nothing. `tools/stage_atlases.py` copies
  the atlas JSON and its declared pages Ã¢â‚¬â€ and *only* those, not the `frames/` intermediates
  or `verify_*` sheets Ã¢â‚¬â€ from the art working root into `game/assets/atlases/`, which is
  gitignored. Re-run it after any rebake. An earlier version of this line said atlases
  *are* committed; that contradicted `.gitignore` and the pack architecture both.
- Only placeholders ship inside the APK (Ã‚Â§3.2) Ã¢â‚¬â€ the staged atlases are there for the
  packager to build a `.pck` from, so the APK export preset must exclude
  `assets/atlases/` or they end up inside the APK as well as the pack.
- `.gdignore` in any raw-art folder under the project.

---

## 3. Target platforms & delivery

| Target | Priority | Notes |
|---|---|---|
| Android (mid-range) | **Primary** | The design constraint Ã¢â‚¬â€ see Ã‚Â§3.0 for the measured reference device |
| Windows | Secondary | Dev/test, usual host |
| Linux | Secondary | Dedicated-host target |
| iOS | Later | Architecture compatible; not in MVP |

### 3.0 Reference device (measured, phase 0.1)

Verified by deploying `device_check.tscn` to hardware, not assumed:

| | |
|---|---|
| Device | HONOR LNA-NX1 |
| OS | Android 16 (SDK 36) |
| SoC | MediaTek MT6858 |
| GPU | **ARM Mali-G610 MC2**, OpenGL ES 3.2 |
| ABI | `arm64-v8a` **only** Ã¢â‚¬â€ no 32-bit target needed |
| Screen | 2600 Ãƒâ€” 1200, 520 dpi, 60 Hz |
| Renderer confirmed active | `gl_compatibility` / `opengl3` |
| Empty-scene FPS | 60 (capped by refresh rate) |

Two consequences worth designing around:

1. **MediaTek + Mali is exactly the hardware the Compatibility decision (Ã‚Â§1) was made for.** Known Godot Vulkan crashes cluster on MediaTek and Mali parts, so this device would have been a poor Vulkan-Mobile target. The renderer choice is now empirically validated rather than argued.
2. **The screen is 2600 Ãƒâ€” 1200 Ã¢â‚¬â€ a 2.17:1 aspect, far wider than 16:9.** With `stretch/aspect=expand` the design viewport resolves to **1404 Ãƒâ€” 648**. So UI is authored against a **648 px tall** canvas with variable width. Both HUD edges have generous horizontal room but vertical space is tight Ã¢â‚¬â€ relevant to [UI_Design.md](UI_Design.md) and to IDEA 9.2's note about placing the age progress bar below the age indicator on narrow screens.

### 3.1 Performance budget

| Metric | Target |
|---|---|
| Frame time | 16.6 ms (60 fps); hard floor 33 ms (30 fps) |
| Sim tick cost | < 5 ms per 100 ms tick |
| Live units (MVP) | 50 |
| Live units (full scope) | 200 per player, 8 players |
| Draw calls | < 200 |
| Texture memory | < 256 MB |
| **APK size** | **< 300 MB** Ã¢â‚¬â€ code + placeholders only |
| Asset pack (art) | ~150Ã¢â‚¬â€œ400 MB, downloaded |
| Asset pack (audio) | ~50Ã¢â‚¬â€œ100 MB, downloaded |

Measured baseline: an **empty** project exports to **54 MB** (arm64-v8a), essentially all engine binary. The 300 MB ceiling leaves real headroom while art and audio still ship as downloadable packs (Ã‚Â§3.2).

Checked by `StressTest.tscn` (0.7) from early on, not at the end.

### 3.2 Asset delivery Ã¢â‚¬â€ downloadable packs

Art and audio are **not bundled in the APK**. They ship as Godot `.pck` files mounted at runtime via `ProjectSettings.load_resource_pack()`, which is the engine-native mechanism for exactly this.

```
APK  (< 60 MB)   = code + data JSON + procedural placeholders + fonts
pack_art_v1.pck  = atlases, terrain
pack_audio_v1.pck = sfx, music
pack_theme_*.pck  = optional community themes (later)
```

**Sources, in priority order:**
1. **Project website (primary)** Ã¢â‚¬â€ `https://aod.dragoon.co.za/`, no size limit, 100 Mbps.
   Settled at 0.3. Layout, with the website source living in `web/` in this repo:
   | URL | What |
   |---|---|
   | `https://aod.dragoon.co.za/index.html` | Landing page |
   | `https://aod.dragoon.co.za/downloads/index.html` | Downloads page Ã¢â‚¬â€ human-facing |
   | `https://aod.dragoon.co.za/downloads/packs.json` | **Pack manifest Ã¢â‚¬â€ the client reads this.** Stable, unversioned URL; the versions live *inside* it |
   | `https://aod.dragoon.co.za/downloads/AoD_v0.0.4.apk` / `.exe` | Game builds Ã¢â‚¬â€ human-facing, not fetched by the client |
   | `https://aod.dragoon.co.za/downloads/pack_art_v1.pck` | Art pack Ã¢â‚¬â€ fetched by `AssetPacks` |
2. Additional mirror (to be chosen; GitHub Releases is one candidate)
3. Any user-added source URL (enables custom themes later)

> **Pack versions are independent of game versions**, which is why the pack is
> `pack_art_v1.pck` and not `AoD_v0.0.4.pck`. Naming it after the build would force every
> player to re-download the whole art pack on every code release, including releases that
> changed no art at all Ã¢â‚¬â€ and the art will grow well past its current 6.7 MB once audio
> (A.7) and the military roster (A.8) land. The APK and the `.pck` version on separate
> clocks; the manifest is what ties a game build to the pack versions it accepts.

The pack manifest carries a URL list per pack, so adding or reordering mirrors is a manifest edit with no client change.

**Flow:** boot Ã¢â€ â€™ check local pack versions against a manifest Ã¢â€ â€™ download missing/outdated Ã¢â€ â€™ verify checksum Ã¢â€ â€™ `load_resource_pack()` Ã¢â€ â€™ assets resolve through the seam (Ã‚Â§2.1). If a pack is absent or fails verification, **the game runs on placeholders** rather than failing. That fallback is the whole reason placeholders stay in the build permanently.

```jsonc
// packs.json Ã¢â‚¬â€ https://aod.dragoon.co.za/downloads/packs.json
{
  "manifest_version": 1,
  "packs": [
    { "id": "art", "version": "1.0.0", "size": 6710000,
      "sha256": "Ã¢â‚¬Â¦", "required": false,
      "urls": ["https://aod.dragoon.co.za/downloads/pack_art_v1.pck"] }
  ]
}
```

```gdscript
# src/autoload/asset_packs.gd                                  [MVP]
class_name AssetPacks
signal pack_progress(id: StringName, pct: float)
signal pack_ready(id: StringName)
signal pack_failed(id: StringName, reason: String)

func check_manifest() -> Array[PackInfo]                       # [MVP]
func is_installed(id: StringName) -> bool                      # [MVP]
func download(id: StringName) -> void                          # [MVP]
func mount(id: StringName) -> Error                            # [MVP] load_resource_pack
func remove(id: StringName) -> void
func add_source(url: String) -> void                           # custom themes, later
func installed_version(id: StringName) -> String               # [MVP]
```

MVP implements check / download / verify / mount for one art pack. Theme sources and multi-pack layering come later.

---

## 4. Repository & project layout

```
AOD_Mobile/
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ IDEA.md
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ PLAN.md
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ UI_Design.md
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ ASSET_MISSING.md            # every asset still needed, MVP + end state
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ CREDITS.md                  # CC-BY-SA attribution, surfaced in-game
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ UI_Sprites/                 # licensed UI packs (+ .gdignore)
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ insperation_pictures/       # reference (+ .gdignore)
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ tools/                      # OFFLINE pipeline Ã¢â‚¬â€ Python, never shipped
Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ isobake.toml            # camera config; MUST match Iso.TILE_SIZE
Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ recipes/                # AOD content: which 0 A.D. actor is our what
Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ terrain_grass.toml
Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ tree_oak.toml
Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ villager.toml
Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ town_center.toml    # buildings: one recipe per Phase visual,
Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ foundation_8x8.toml # foundations and generic rubble keyed by
Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ rubble_town_center.toml #  footprint size so they are shared
Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ house.toml
Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ foundation_4x4.toml
Ã¢â€â€š   Ã¢â€â€š   Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ rubble_3x3.toml
Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ build_packs.py          # atlases -> .pck + manifest + checksums
Ã¢â€â€š   Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ licence_audit.py        # every asset must declare a licence
Ã¢â€â€š
Ã¢â€â€š   # Rendering, baking and verification live in the separate isobake repo
Ã¢â€â€š   # (Ã‚Â§2.2). Recipes stay here because "0 A.D.'s female citizen is our
Ã¢â€â€š   # villager" is a content decision, not a tool feature.
Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ game/                       # THE GODOT PROJECT
    Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ project.godot
    Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ data/
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ units.json
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ buildings.json
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ resources.json
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ techs.json
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ ages.json
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ factions.json
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ visuals.json        # ASSET SEAM Ã¢â‚¬â€ id -> atlas or placeholder
    Ã¢â€â€š   Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ audio.json          # ASSET SEAM Ã¢â‚¬â€ id -> sound
    Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ assets/
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ placeholders/       # ships in APK
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ ui/                 # ships in APK
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ fonts/              # ships in APK
    Ã¢â€â€š   Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ LICENCES.md         # per-asset provenance, checked by licence_audit.py
    Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ src/
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ sim/                # NO Godot node types, NO rendering
    Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ sim_world.gd
    Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ sim_map.gd
    Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ sim_player.gd
    Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ entities/
    Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ systems/
    Ã¢â€â€š   Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ commands/
    Ã¢â€â€š   Ã¢â€â€š   Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ pathing/
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ net/
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ view/
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ ui/
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ ai/
    Ã¢â€â€š   Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ autoload/
    Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ scenes/
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ boot/
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ menu/
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ game/
    Ã¢â€â€š   Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ ui/
    Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ tests/                  # headless Ã¢â‚¬â€ see Ã‚Â§7.7
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ run_tests.tscn      # the one test command (Ã‚Â§7.7)
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ run_tests.gd        # discovers/runs test_*.gd, sets exit code
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ sim/                # SimWorld, systems, commands
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ net/                # Net, SimHost
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ view/               # Iso, EntityViewPool, GameView
    Ã¢â€â€š   Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ replays/            # recorded command logs used as regression fixtures
    Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ addons/                 # GUT or GdUnit4
```

**The `game/src/sim/` boundary is the most important rule in this codebase.** Nothing in `sim/` may `extends Node`, load a texture, read input, or reference `view/`. `test_sim_boundary.gd` greps for violations as part of the test suite (0.7) Ã¢â‚¬â€ which is a manual command, not CI (Ã‚Â§1.2).

---

## 5. Architecture overview

```
Ã¢â€Å’Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€Â
Ã¢â€â€š  VIEW (client)   scenes, sprites, camera, HUD, gestures    Ã¢â€â€š
Ã¢â€â€š  reads snapshots Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€Â            Ã¢â€Å’Ã¢â€â‚¬Ã¢â€â‚¬ emits Commands         Ã¢â€â€š
Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€Â¼Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€Â¼Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€Ëœ
                     Ã¢â€â€š            Ã¢â€â€š
              snapshots (down)   commands (up)
                     Ã¢â€â€š            Ã¢â€â€š
Ã¢â€Å’Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€Â¼Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€Â¼Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€Â
Ã¢â€â€š  NET             SceneMultiplayer / ENetMultiplayerPeer    Ã¢â€â€š
Ã¢â€â€š  host binds 127.0.0.1 (solo) or 0.0.0.0 (multiplayer)      Ã¢â€â€š
Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€Â¼Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€Â¼Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€Ëœ
                     Ã¢â€â€š            Ã¢â€â€š
Ã¢â€Å’Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€“Â¼Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€“Â¼Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€Â
Ã¢â€â€š  SIM (server only, headless-capable, 10 Hz fixed tick)     Ã¢â€â€š
Ã¢â€â€š  SimWorld -> systems -> entities. Plain GDScript classes.  Ã¢â€â€š
Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€Ëœ
```

### 5.1 One tick, end to end

```
1. Player drags a finger on the map.
2. InputRouter -> MoveCommand(unit_ids, target_tile).
3. Net.submit_command(cmd)  -> rpc_id(1, "_recv_command", cmd.to_dict())
4. [SERVER] validate ownership/legality, queue for tick N+1.
5. [SERVER] SimClock fires tick N+1 -> SimWorld.step():
      CommandSystem -> TaskSystem -> MovementSystem -> CombatSystem
      -> ProductionSystem -> ResourceSystem -> VisionSystem
      -> DeathSystem -> WinConditionSystem
6. [SERVER] SnapshotSystem builds a per-player fog-filtered delta, broadcasts.
7. [CLIENT] EntityViewPool applies the delta, interpolates over the next 100 ms.
```

Step 6's fog filtering is a **security property**: the server must not send a client entities it cannot see.

---

## 6. Core objects Ã¢â‚¬â€ API reference

`# [MVP]` marks what exists in the first build.

### 6.1 Autoloads

```gdscript
# src/autoload/game_data.gd                                   [MVP]
class_name GameDataRegistry
func load_all() -> void
func unit(id: StringName) -> UnitDef
func building(id: StringName) -> BuildingDef
func resource_def(id: StringName) -> ResourceDef
func tech(id: StringName) -> TechDef
func age(index: int) -> AgeDef
func atlas_for(visual_id: StringName) -> AtlasEntry   # real atlas OR placeholder

# src/autoload/net.gd                                          [MVP]
class_name Net
signal session_started(is_host: bool)
signal session_ended(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal snapshot_received(snap: Dictionary)

func host_solo() -> Error                                      # [MVP] 127.0.0.1
func host_open(port: int, max_players: int) -> Error            # 0.0.0.0
func join(address: String, port: int) -> Error
func leave() -> void
func is_server() -> bool                                       # [MVP]
func local_player_id() -> int                                  # [MVP]
func submit_command(cmd: Command) -> void                      # [MVP]
@rpc("any_peer", "call_local", "reliable")   func _recv_command(d: Dictionary) -> void
@rpc("authority", "call_local", "unreliable_ordered") func _recv_snapshot(d: Dictionary) -> void

# src/autoload/sim_clock.gd                                    [MVP]
class_name SimClock
const TICK_HZ := 10
const TICK_MS := 100
var tick: int
signal tick_advanced(tick: int)
func start() -> void
func stop() -> void
func _process(delta: float) -> void      # accumulates; may fire >1 tick to catch up

# src/autoload/event_bus.gd                                    [MVP]
class_name EventBus
signal selection_changed(entity_ids: Array[int])
signal resources_changed(player_id: int, stock: Dictionary)
signal entity_spawned(id: int, kind: StringName)
signal entity_died(id: int)
signal production_progress(building_id: int, pct: float)
signal control_group_changed(slot: int, icon: StringName, count: int)
signal age_advance_progress(player_id: int, pct: float)
signal notice(severity: int, message: String)

# src/autoload/asset_packs.gd    Ã¢â‚¬â€ see Ã‚Â§3.2                    [MVP]
# src/autoload/scene_router.gd                                 [MVP]
class_name SceneRouter
func goto_main_menu() -> void
func goto_match(config: MatchConfig) -> void
func quit_to_menu() -> void

# src/autoload/audio_manager.gd
class_name AudioManager
func play_sfx(id: StringName, world_pos: Vector2 = Vector2.ZERO) -> void
func play_music(id: StringName) -> void
func set_bus_volume(bus: StringName, db: float) -> void

# src/autoload/settings.gd
class_name Settings
func get_value(key: String, default: Variant) -> Variant
func set_value(key: String, value: Variant) -> void
func save() -> void
```

### 6.2 Simulation

```gdscript
# src/sim/sim_world.gd                                         [MVP]
class_name SimWorld
const SUBTILE := 256

var tick: int = 0
var map: SimMap
var players: Array[SimPlayer] = []
var entities: Dictionary = {}          # int id -> SimEntity
var spatial: SpatialHash
var _next_id: int = 1
var _pending: Array[Command] = []
var _systems: Array[SimSystem] = []

func setup(cfg: MatchConfig) -> void                            # [MVP]
func step() -> void                                             # [MVP]
func queue_command(cmd: Command) -> void                        # [MVP]
func spawn_unit(def_id: StringName, owner: int, pos: Vector2i) -> SimUnit          # [MVP]
func spawn_building(def_id: StringName, owner: int, origin: Vector2i) -> SimBuilding # [MVP]
func spawn_resource(def_id: StringName, pos: Vector2i, amount: int) -> SimResourceNode # [MVP]
func despawn(id: int) -> void                                   # [MVP]
func get_entity(id: int) -> SimEntity                           # [MVP]
func entities_in_radius(pos: Vector2i, r: int) -> Array[SimEntity]   # [MVP]
func entities_in_rect(rect: Rect2i) -> Array[SimEntity]          # [MVP]
func state_hash() -> int                                         # desync detection

# src/sim/sim_map.gd                                            [MVP]
class_name SimMap
enum Terrain { GRASS, DIRT, SAND, WATER_SHALLOW, WATER_DEEP, ROCK, FOREST }

var size: Vector2i
var terrain: PackedByteArray
var occupancy: PackedInt32Array             # entity id per tile, 0 = free
var move_cost: PackedByteArray              # 255 = impassable

func in_bounds(t: Vector2i) -> bool                             # [MVP]
func terrain_at(t: Vector2i) -> Terrain                         # [MVP]
func is_passable(t: Vector2i, domain: int) -> bool               # [MVP]
func occupant(t: Vector2i) -> int                               # [MVP]
func set_occupied(rect: Rect2i, id: int) -> void                 # [MVP]
func clear_occupied(rect: Rect2i) -> void                        # [MVP]
func can_place_building(rect: Rect2i) -> bool                    # [MVP]
func find_free_adjacent(rect: Rect2i, domain: int) -> Vector2i    # [MVP]

# src/sim/sim_player.gd                                         [MVP]
class_name SimPlayer
var id: int
var peer_id: int                    # 1 = host's own local player
var faction: StringName
var is_ai: bool
var team: int
var stock: Dictionary               # {food, wood, gold, stone} -> int   [MVP]
var pop_used: int
var pop_cap: int
var age: int = 1
var researched: Dictionary
var vision: PackedByteArray         # 0 unseen, 1 explored, 2 visible
var control_groups: Array           # 5 x Array[int]                     [MVP]
var defeated: bool

func can_afford(cost: Dictionary) -> bool                        # [MVP]
func pay(cost: Dictionary) -> bool                               # [MVP]
func refund(cost: Dictionary) -> void                            # [MVP]
func add_resource(kind: StringName, amount: int) -> void          # [MVP]
```

#### Entities

```gdscript
# src/sim/entities/sim_entity.gd                                [MVP]
class_name SimEntity
var id: int
var def_id: StringName
var owner_id: int
var pos: Vector2i                   # sub-tile units
var hp: int
var max_hp: int
var alive: bool = true
var vision_range: int

func tile() -> Vector2i                                          # [MVP]
func take_damage(amount: int, attack_type: int) -> void           # [MVP]
func on_tick(w: SimWorld) -> void                                 # [MVP] virtual
func to_snapshot() -> Dictionary                                  # [MVP]

# src/sim/entities/sim_unit.gd                                   [MVP]
class_name SimUnit extends SimEntity
enum Task { IDLE, MOVE, GATHER, RETURN, BUILD, ATTACK, GARRISON, STAND_GROUND, FLEE }

var task: Task = Task.IDLE
var task_target_id: int = 0
var task_target_tile: Vector2i
var path: PackedVector2Array
var path_index: int
var speed: int                       # sub-units per tick
var facing: int                      # 0-7
var carry_kind: StringName
var carry_amount: int
var gather_cooldown: int
var attack_cooldown: int
var anim: StringName                 # view hint

func set_task_move(t: Vector2i) -> void                          # [MVP]
func set_task_gather(node_id: int) -> void                       # [MVP]
func set_task_build(site_id: int) -> void                        # [MVP]
func set_task_attack(target_id: int) -> void
func stop() -> void                                              # [MVP]
func is_idle() -> bool                                           # [MVP]

# src/sim/entities/sim_building.gd                               [MVP]
class_name SimBuilding extends SimEntity
enum Phase { FOUNDATION, UNDER_CONSTRUCTION, COMPLETE, DESTROYED }

var phase: Phase = Phase.FOUNDATION
var footprint: Vector2i
var build_progress: int
var build_total: int
var queue: Array[ProductionOrder] = []
var garrison: Array[int] = []
var garrison_cap: int
var provides_pop: int

func origin_tile() -> Vector2i                                   # [MVP]
func footprint_rect() -> Rect2i                                  # [MVP]
func add_build_progress(amount: int) -> void                     # [MVP]
func enqueue(def_id: StringName) -> bool                         # [MVP]
func cancel_order(index: int) -> void                            # [MVP]
func garrison_unit(id: int) -> bool
func ungarrison_all() -> Array[int]

# src/sim/entities/sim_resource_node.gd                          [MVP]
class_name SimResourceNode extends SimEntity
var kind: StringName                 # food | wood | gold | stone
var amount: int                                                  # [MVP]
var size_class: int                  # 0 small, 1 medium, 2 large
var gather_slots: int

func gather(amount: int) -> int                                  # [MVP]
func is_depleted() -> bool                                       # [MVP]

# src/sim/entities/sim_wildlife.gd
class_name SimWildlife extends SimResourceNode
var home_tile: Vector2i
var roam_radius: int
var flee_from_id: int
var is_dead: bool                    # carcass = gatherable
```

#### Systems

```gdscript
# src/sim/systems/sim_system.gd                                 [MVP]
class_name SimSystem
func process_tick(w: SimWorld) -> void      # virtual
```

Run in this fixed order by `SimWorld.step()`:

| System | Responsibility | MVP |
|---|---|---|
| `CommandSystem` | Validate + apply queued commands; reject commands for entities the sender doesn't own | **[MVP]** |
| `TaskSystem` | Per-unit task state machine | **[MVP]** |
| `MovementSystem` | Path following, re-path on block, local avoidance | **[MVP]** |
| `ProductionSystem` | Build queues, training timers, construction progress | **[MVP]** |
| `ResourceSystem` | Gather ticks, carry caps, drop-off, depletion | **[MVP]** |
| `DeathSystem` | HPÃ¢â€°Â¤0 Ã¢â€ â€™ corpse, free tiles, drop cargo, corpse timer | **[MVP]** |
| `SnapshotSystem` | Per-player fog-filtered deltas; broadcast | **[MVP]** |
| `CombatSystem` | Target acquisition, cooldowns, damage w/ armour classes | |
| `VisionSystem` | Recompute per-player vision | |
| `TechSystem` | Research timers, stat modifiers, age advancement | |
| `PopulationSystem` | Recompute pop cap | |
| `WinConditionSystem` | Evaluate active game mode's victory rule | |
| `AISystem` | Drive AI players (emits Commands like any player) | |

#### Commands

The only way state changes.

```gdscript
# src/sim/commands/command.gd                                   [MVP]
class_name Command
var player_id: int
var issued_tick: int
func to_dict() -> Dictionary                                     # [MVP]
static func from_dict(d: Dictionary) -> Command                   # [MVP]
func validate(w: SimWorld) -> bool                                # [MVP] virtual
func apply(w: SimWorld) -> void                                   # [MVP] virtual
```

| Command | Payload | MVP |
|---|---|---|
| `MoveCommand` | `unit_ids`, `target_tile` | **[MVP]** |
| `GatherCommand` | `unit_ids`, `node_id` | **[MVP]** |
| `BuildCommand` | `unit_ids`, `building_def`, `origin_tile` | **[MVP]** |
| `TrainCommand` | `building_id`, `unit_def` | **[MVP]** |
| `StopCommand` | `unit_ids` | **[MVP]** |
| `CancelOrderCommand` | `building_id`, `index` | **[MVP]** |
| `SetControlGroupCommand` | `slot`, `unit_ids` | **[MVP]** |
| `AttackCommand` | `unit_ids`, `target_id` | |
| `GarrisonCommand` | `unit_ids`, `building_id` | |
| `ResearchCommand` | `building_id`, `tech_id` | |
| `AdvanceAgeCommand` | `building_id` | |
| `StanceCommand` | `unit_ids`, `stance` | |
| `SpecialAbilityCommand` | `unit_ids`, `ability_id`, `target` | |
| `TradeCommand` | `cart_id`, `market_id` | |
| `ResignCommand` | Ã¢â‚¬â€ | |

#### Pathfinding

```gdscript
# src/sim/pathing/path_service.gd                               [MVP]
class_name PathService
func rebuild(map: SimMap) -> void                                # [MVP]
func set_tile_blocked(t: Vector2i, blocked: bool) -> void         # [MVP]
func find_path(from: Vector2i, to: Vector2i, domain: int) -> PackedVector2Array  # [MVP]
func nearest_reachable(from: Vector2i, to: Vector2i, domain: int) -> Vector2i     # [MVP]
func request_async(from, to, domain, callback: Callable) -> int    # budgeted queue

# src/sim/pathing/flow_field.gd     Ã¢â‚¬â€ scale-up only
class_name FlowField
func build(goal: Vector2i, map: SimMap, domain: int) -> void
func direction_at(t: Vector2i) -> Vector2i
```

`AStarGrid2D` wrapped by `PathService`, with a **per-tick pathfinding budget** Ã¢â‚¬â€ at most N requests solved per tick, rest queued. Prevents the stall where dozens of units re-path on one frame. Local unit-vs-unit avoidance is steering-based off the spatial hash; the sim has no physics engine.

### 6.3 View layer

```gdscript
# src/view/game_view.gd                                        [MVP]
class_name GameView extends Node2D
func apply_snapshot(snap: Dictionary) -> void                    # [MVP]
func _process(delta) -> void                                     # [MVP] interpolate

# src/view/entity_view_pool.gd                                  [MVP]
class_name EntityViewPool
func acquire(id: int, visual_id: StringName) -> EntityView        # [MVP] pooled
func release(id: int) -> void                                    # [MVP]
func get_view(id: int) -> EntityView                             # [MVP]

# src/view/entity_view.gd                                       [MVP]
class_name EntityView extends Node2D
func set_target_transform(pos: Vector2, tick: int) -> void        # [MVP]
func play_anim(name: StringName, facing: int) -> void             # [MVP]
func set_health_dot(pct: float) -> void                          # [MVP]
func set_selected(on: bool) -> void                              # [MVP]
func set_team_color(c: Color) -> void                            # [MVP] outline shader

# src/view/camera_rig.gd                                        [MVP]
class_name CameraRig extends Camera2D
func pan(delta: Vector2) -> void                                 # [MVP]
func zoom_by(factor: float) -> void                              # [MVP]
func center_on(world_pos: Vector2, animated: bool) -> void        # [MVP]
func follow(entity_id: int) -> void
func clamp_to_map(bounds: Rect2) -> void                         # [MVP]

# src/view/input_router.gd                                      [MVP]
class_name InputRouter extends Node
# tap, double-tap, drag, two-finger box select, edge swipe zoom
func _unhandled_input(e: InputEvent) -> void                     # [MVP]
signal request_command(cmd: Command)                             # [MVP]

# src/view/selection.gd Ã¢â‚¬â€ client-side only, never sent           [MVP]
class_name Selection
func set_selection(ids: Array[int]) -> void                      # [MVP]
func add(ids: Array[int]) -> void                                # [MVP]
func select_in_rect(rect: Rect2i) -> void                        # [MVP]
func select_same_type_onscreen(id: int) -> void                  # [MVP]
func current() -> Array[int]                                     # [MVP]

# src/view/iso.gd Ã¢â‚¬â€ the ONLY place grid<->screen math lives      [MVP]
class_name Iso
static func tile_to_world(t: Vector2i) -> Vector2                 # [MVP]
static func world_to_tile(w: Vector2) -> Vector2i                 # [MVP]
static func sub_to_world(p: Vector2i) -> Vector2                   # [MVP]
static func depth_sort_key(p: Vector2i) -> float                    # [MVP]

# src/view/selection_overlay.gd                                  [MVP]
# src/view/placement_ghost.gd                                    [MVP]
# src/view/fog_overlay.gd
```

### 6.4 UI

```gdscript
# src/ui/hud.gd                                                 [MVP]
class_name HUD extends CanvasLayer
# children wire to EventBus signals Ã¢â‚¬â€ no polling

# src/ui/selection_panel.gd   [MVP]  SingleUnitView / BuildingView / MultiSelectView
# src/ui/action_panel.gd      [MVP]  context-sensitive actions
# src/ui/resource_bar.gd      [MVP]  5 counters incl. idle/total villagers
# src/ui/minimap.gd           [MVP]  circular, 4 corner buttons
# src/ui/control_groups.gd    [MVP]  5 slots, icon = most-represented type
# src/ui/download_screen.gd   [MVP]  asset pack progress (Ã‚Â§3.2)
# src/ui/credits_screen.gd    [MVP]  CC-BY-SA attribution (Ã‚Â§2.3)
# src/ui/age_header.gd
# src/ui/tech_tree_screen.gd
# src/ui/market_screen.gd
# src/ui/chat_overlay.gd
```

---

## 7. Cross-cutting concerns

### 7.1 Selection vs commands
Selection is client-side UI state, never sent to the server. Only the resulting `Command` (with explicit `unit_ids`) crosses the wire Ã¢â‚¬â€ selection stays instant regardless of latency.

Control groups are the exception: they're **persisted in `SimPlayer`** via `SetControlGroupCommand` so they survive reconnect and are available to a rejoining client.

### 7.2 Snapshots
Per-player, fog-filtered, delta-encoded against the last acknowledged tick. Full snapshot on join or after loss. Format `{tick, spawned[], updated[], removed[], player_state}`.

### 7.3 Rendering
`Sprite2D` in a Y-sorted container for MVP. If profiling at 200+ units shows Y-sort dominating, switch to explicit depth keys via `Iso.depth_sort_key()` and `RenderingServer` canvas items. Measure at 0.7 scale before changing anything.

### 7.4 Mobile input
All gestures funnel through `InputRouter`. Mouse emulation **disabled** Ã¢â‚¬â€ multi-touch box select needs raw `InputEventScreenTouch`/`Drag`. Test on device from 0.1.

### 7.5 Audio
`AudioManager` exists from MVP with a no-op implementation and a stable ID vocabulary, so gameplay emits `play_sfx(&"villager.chop")` from day one and the audio pack lands later.

### 7.6 Optimisation policy
GDScript everywhere. Profile on the target Android device. Move a hot loop to GDExtension only when profiling proves it dominates.

### 7.7 Testing

Four distinct layers, deliberately Ã¢â‚¬â€ most of the value is in the first one.

**1. Headless sim tests (the important layer).**
Because `src/sim/` is plain GDScript with no `Node`, no textures, and no input, it can be tested with no window and no rendering. This is the payoff of the Ã‚Â§1.1 architecture, and it is why the boundary rule can be checked by a test rather than by review Ã¢â‚¬â€ see the no-CI note in Ã‚Â§1.2: running it is a manual step.

```
godot --headless --path game/ res://tests/run_tests.tscn
```

The runner (`run_tests.gd`) is a Node under that minimal scene, not a `--script`
`SceneTree` override. A custom `--script` MainLoop skips the normal main-scene
boot sequence that parents autoload singletons under the tree root, which
silently breaks anything needing `get_tree()`/`get_multiplayer()` -- discovered
building 0.6's `Net` autoload. A real scene, even headless, boots exactly like
the shipped game does.

Exit code 0 = pass, non-zero = fail Ã¢â‚¬â€ so this one command is the whole check, and is all CI would need if it existed (Ã‚Â§1.2). Test shape:

```gdscript
# spawn a world, queue commands, step N ticks, assert on state
var w := SimWorld.new()
w.setup(MatchConfig.debug_single_player())
var v := w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
w.queue_command(MoveCommand.new(1, [v.id], Vector2i(10, 5)))
for i in 60: w.step()
assert_eq(v.tile(), Vector2i(10, 5), "villager reached target in 60 ticks")
```

No scene required Ã¢â‚¬â€ which answers "what do I need to test?": for sim tests, **nothing but the script**.

**2. Framework Ã¢â‚¬â€ GdUnit4** (MIT). It lists explicit 4.7.1 compatibility and ships a first-party GitHub Action, which makes it the lower-risk pick on a brand-new engine release.

```
addons\gdUnit4\runtest.cmd -a res://tests -c -rd res://reports
```

Exit 0 = pass, 100 = failures, 101 = warnings. Running it headless on Linux would additionally need `xvfb-run --auto-servernum` and `--audio-driver Dummy`. (Not adopted Ã¢â‚¬â€ see 0.7 in Ã‚Â§11.)

*(GUT is the alternative Ã¢â‚¬â€ also MIT, but take its 9.7.x line for 4.7; `main` tracks 4.6.)*

**3. `state_hash()` regression.** Run the same `MatchConfig` + command log twice, compare hashes. Catches accidental non-determinism and any state the snapshot layer forgets to serialise.

**4. Replays.** `MatchConfig` + ordered command log = a few KB that reproduces any bug exactly. Also the manual-testing tool: record a session on the phone, replay it headless on the desktop to debug.

**5. `StressTest.tscn`** Ã¢â‚¬â€ the only layer needing a real scene. Spawns N units, reports frame and tick timings against Ã‚Â§3.1. This one must run **on the phone**, not the desktop.

**What is testable when:** nothing meaningful until 0.5 (`SimWorld` exists). Before that, tests have no subject Ã¢â‚¬â€ 0.1 is verified by a scene visibly running on a physical device, not by assertions.

---

## 8. Scene trees

```
Boot.tscn                    [MVP]
Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ Boot (boot.gd)           # load data, check/mount asset packs, route to menu

MainMenu.tscn                [MVP]
Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ MainMenu (Control)
    Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ Background (TextureRect)
    Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ Title
    Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ VBox: PlayBtn, MultiplayerBtn, SettingsBtn, CreditsBtn, QuitBtn

Match.tscn                   [MVP]
Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ Match (match.gd)
    Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ SimHost (sim_host.gd)         # server only; owns SimWorld
    Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ GameView (Node2D)
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ TerrainLayer (TileMapLayer)
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ StaticsLayer (Y-sorted)   # buildings, trees, mines
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ UnitsLayer (Y-sorted)     # units, wildlife
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ OverlayLayer              # selection rings, ghost, health dots
    Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ FogLayer
    Ã¢â€â€š   Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ CameraRig (Camera2D)
    Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ InputRouter
    Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ HUD (CanvasLayer)
        Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ ControlGroups   (top-left)      [MVP]
        Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ AgeHeader       (top-centre)
        Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ ResourceBar     (top-right)     [MVP]
        Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ SelectionPanel  (bottom-left)   [MVP]
        Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ ActionSubPanel
        Ã¢â€â€š   Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ QueueSubPanel
        Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ MinimapPanel    (bottom-right)  [MVP]

DownloadScreen.tscn          [MVP]  asset pack fetch + progress
CreditsScreen.tscn           [MVP]  attribution
Lobby.tscn                          host/join, faction & map & win condition
Settings.tscn
MatchResult.tscn
StressTest.tscn              [MVP]  perf harness
```

---

## 9. Data schemas

Static data is JSON in `game/data/`, loaded once into typed `*Def` objects.

**All numbers below are starting values, tuned by playtest.** Balance is ours to design and iterate.

```jsonc
// units.json
{
  "unit.villager": {
    "name": "Villager",
    "visual": "vis.villager",
    "hp": 30, "speed": 200, "los": 4,
    "domain": "land", "pop_cost": 1,
    "cost": { "food": 50 },
    "build_time_ticks": 250,             // 25 s at 10 Hz
    "attack": { "damage": 3, "type": "melee", "range": 0, "cooldown_ticks": 20 },
    "armor": { "melee": 0, "pierce": 0 },
    "carry_cap": { "food": 10, "wood": 10, "gold": 10, "stone": 10 },
    "gather_rate": { "food": 25, "wood": 25, "gold": 25, "stone": 25 },  // per 100 ticks
    "trainable_at": ["building.town_center"]
  }
}

// buildings.json
{
  "building.town_center": {
    "name": "Town Center",
    "visual": "vis.town_center",
    // Footprint comes from the baked art, not from this sketch. SETTLED at 0.4:
    // the civic centre measures 15.53 x 15.00 m = 7.77 tiles, so [8, 8], which
    // also agrees with 0 A.D.'s own 30x30-unit obstruction and the fndn_8x8 it
    // pairs with. The house is measured at 10 x 10 m -- 5 tiles -- but is given
    // [4, 4] to match its 4x4 foundation, so its roof deliberately overhangs.
    // See data/buildings.json and ASSET_MISSING.md 1.2.
    "hp": 2000, "footprint": [8, 8], "los": 8,
    "visual_foundation": "vis.foundation_8x8",
    "visual_rubble": "vis.rubble_town_center",
    "cost": { "wood": 275, "stone": 100 },
    "build_time_ticks": 1500,
    "provides_pop": 10, "garrison_cap": 15,
    "trains": ["unit.villager"],
    "drop_off": ["food", "wood", "gold", "stone"],
    "age_required": 1
  }
}

// resources.json
{
  "res.tree":      { "kind": "wood", "visual": "vis.tree",
                     "amounts": [40, 100, 175], "gather_slots": 1 },
  "res.gold_mine": { "kind": "gold", "visual": "vis.gold_mine",
                     "amounts": [200, 500, 800], "gather_slots": 4 },
  "res.deer":      { "kind": "food", "visual": "vis.deer", "amounts": [140,140,140],
                     "wildlife": { "roam_radius": 6, "flees": true } }
}
```

`techs.json`, `ages.json`, `factions.json` follow the same shape, near-empty until their phases.

### 9.1 Atlas format

Generated by **`isobake`** (Ã‚Â§2.2) as `<id>.atlas.json` beside its PNG pages. It is a
*generated* file: a rebake rewrites it wholesale, so `visuals.json` points at it and
nothing is ever hand-merged into it.

```jsonc
{
  "format": 1,
  "id": "vis.villager",
  "pages": ["vis.villager_0.png"],          // multi-page from the start
  "page_sizes": [[1024, 1024]],
  "directions": {
    "stored": 5, "mirror_for_8": true,
    "order": ["S", "SE", "E", "NE", "N"],
    // every facing resolved to a stored frame + flip, so the view layer reads
    // the convention instead of re-deriving it
    "table": [ { "dir": "SW", "stored_index": 1, "flip_x": true }, Ã¢â‚¬Â¦ ]
  },
  "pixels_per_metre": 22.627431,
  "anims": {
    "idle": { "fps": 8, "loop": true, "frames": 12, "first": 0 },
    "walk": { "fps": 15, "loop": true, "frames": 12, "first": 60 }
  },
  // index = anims[name].first + stored_direction_index * frames + frame
  "frames": [ { "page": 0, "rect": [0, 0, 40, 52], "anchor": [20.0, 50.0] } ],
  "generator": { "tool": "isobake", "blender": "4.5.12", "recipe_sha256": "Ã¢â‚¬Â¦" }
}
```

Two deliberate departures from the row-based sketch this replaces:

- **Per-frame rects, not rows.** A row layout pads every frame to the largest cell.
  Trimmed frames vary a lot, and the villager's 240 frames pack into 20% of a
  1024Ã‚Â² page as rects.
- **Multi-page.** Mobile GL ES 3.0 only guarantees 4096Ã‚Â², and a full animation set
  will not fit one page. Cheaper to carry the `page` index from the start than to
  retrofit it.

**Anchors are exact, not measured.** With a fixed orthographic camera and the subject
rotating about the world Z axis through the origin, world (0,0,0) projects to one
constant pixel; the per-frame anchor is that constant minus the frame's trim offset.
The earlier plan here specified bottom-centre-of-content-bbox, which moves whenever a
limb swings out Ã¢â‚¬â€ that is the cause of the jitter Ã‚Â§14 used to list, not a separate
problem to mitigate.

---

## 10. MVP definition

> **One player, one small map, hosted on loopback, on a physical Android phone:**
> starts with **1 Town Centre and 5 villagers** (IDEA 2.6), pans/zooms the camera,
> selects villagers by tap and two-finger box, assigns them to **control groups**,
> sends them to chop wood / mine gold / hunt a deer, watches resource counters rise,
> builds a House and a second Town Centre, queues and trains villagers, and sees the
> idle-villager count work. Units die, corpses fade, buildings can be destroyed by a
> debug command. Art is placeholder; the art pack downloads and mounts if present.

**Not in MVP:** combat between players, AI opponents, fog of war, ages, techs, upgrades, garrison, win conditions, dragons, remote multiplayer, sound, campaign, trade, market, chat.

---

## 11. Phase plan

### Phase 0 Ã¢â‚¬â€ Foundation

| # | Item | Tag |
|---|---|---|
| 0.1 | Ã¢Å“â€¦ **DONE** Ã¢â‚¬â€ Godot 4.7.1 project, Compatibility renderer, landscape lock, folder skeleton, Android export, **deployed and verified on a physical device**. Renderer, orientation, raw touch, touchÃ¢â€ â€™viewport coordinate mapping and 60 fps all confirmed on hardware (Ã‚Â§3.0) | **[MVP]** |
| 0.2a | Ã¢Å“â€¦ **DONE** Ã¢â‚¬â€ Asset seam: `data/visuals.json` (11 IDs) + `data/audio.json` (9 IDs, all streams null Ã¢â‚¬â€ the vocabulary is the point, Ã‚Â§7.5), `GameDataRegistry` autoload with `atlas_for()`, `AtlasEntry`. `atlas_for()` is **total**: it returns a baked atlas, else the declared placeholder, else a magenta unknown Ã¢â‚¬â€ never null, which is what makes a phase buildable before its art exists and lets the game boot with no pack mounted (Ã‚Â§3.2). Every ID declares *both* an atlas path and a placeholder, so art lights up with no code change when the pack mounts. Atlas parsing is proven against a verbatim shipped bake (`tests/fixtures/gold_mine.atlas.json`) rather than a hand-written idea of the format, and reading any atlas asserts its `pixels_per_metre` against `Iso` Ã¢â‚¬â€ the guard for the 0.2b villager finding (13.2 item 9). No `class_name` on the autoload: it would shadow the singleton, same as `net.gd`/`sim_clock.gd` | **[MVP]** |
| 0.2b | Ã¢Å“â€¦ **DONE** Ã¢â‚¬â€ Procedural placeholder renderer (Ã‚Â§2.4): diamonds for terrain, capsules with a facing marker for units, extruded boxes for buildings, drawn at runtime with no image files. `EntityView` now actually renders Ã¢â‚¬â€ one `_draw()` handling both branches Ã¢â‚¬â€ and gained a frame clock driven by `advance()` (not `_process`, same single-driver reason as interpolation). Placeholder sizes are authored in **metres, not pixels** as Ã‚Â§2.4 sketched, from the measured recipe figures, so a placeholder occupies the space its real sprite will and stays correct if `TILE_SIZE` changes. `Iso` gained the metre-space projection (`metres_to_world`, `height_to_world`, the 8-facing table) with its derived constants re-checked against `TILE_SIZE` in tests. `StressTest.tscn`'s stand-in dots deleted Ã¢â‚¬â€ it now measures the production render path, so its 0.7 device figures need re-measuring. (Measured at 2.6, and the draw-call prediction was **backwards**: 200 units cost **681** draw calls on placeholders and **14** on real atlases. Placeholders are the expensive path -- polygon plus outline plus marker, none of it batching -- while real sprites all sample one page. The budget risk sits with the no-pack-mounted fallback, not with real art.) Visual check: `dev_preview/preview_placeholders.tscn`. 64/64 tests, exit 0 | **[MVP]** |
| 0.2c | Ã¢Å“â€¦ **DONE** Ã¢â‚¬â€ `tools/licence_audit.py` + `game/assets/LICENCES.md`, with `CREDITS.md` brought up to date. The audit checks four things: every recipe carries a complete `[attribution]` block, every recipe's atlas ID and every file under `game/assets/` is declared in `LICENCES.md`, no declared row is still marked `UNVERIFIED`, and the three verbatim 0 A.D. elements appear wherever their material is credited. `--write` regenerates the recipe table from the recipes themselves (idempotent, hash-verified) so it cannot drift from what is actually baked. Exits non-zero; **run by hand, there is no CI (Ã‚Â§1.2)**. Verified against a planted undeclared asset, an attribution-less recipe and a malformed TOML Ã¢â‚¬â€ all three reported in one run, no traceback. **It found a real gap on its first run:** the app icons and boot splash ship in the APK with no provenance recorded anywhere; now recorded as AI-generated (Google Gemini, paid account) with the copyrightability caveat noted | **[MVP]** |
| 0.3 | `AssetPacks` autoload: manifest check, download, checksum verify, `load_resource_pack()`, `DownloadScreen` (Ã‚Â§3.2) | **[MVP]** |
| 0.4 | Ã¢Å“â€¦ **DONE** Ã¢â‚¬â€ `GameDataRegistry`'s entity half over `units.json` / `buildings.json` / `resources.json` / `techs.json` / `ages.json` / `factions.json`, parsed into `UnitDef` / `BuildingDef` / `ResourceDef` / `TechDef` / `AgeDef` (`src/data/`, plain `RefCounted` so `sim/` may read them). The 6 MVP entities are entered: villager, town centre, house, tree, gold mine, deer. These accessors return **null** for an unknown ID Ã¢â‚¬â€ the opposite of `atlas_for()`, deliberately: a missing sprite has a sensible stand-in, a missing unit definition does not. `validate()` cross-checks every visual/unit/building/kind reference across the files and the suite fails on any warning, which is the only thing between a typo'd ID and a silent no-op at runtime (verified by breaking a reference and watching the suite go red). **Footprints are the measured ones** Ã¢â‚¬â€ town centre `[8, 8]` from 15.53 Ãƒâ€” 15.00 m, settling Ã‚Â§9's pre-measurement `[4, 4]` sketch. `techs.json` is empty and `factions.json` near-empty *on purpose*: a missing file and an empty one are different states and only one is a bug. 82/82 tests, exit 0 | **[MVP]** |
| 0.5 | Ã¢Å“â€¦ **DONE** Ã¢â‚¬â€ Sim skeleton: `SimWorld`, `SimClock`, `SimEntity`/`SimUnit`, `SimSystem` (`CommandSystem`/`TaskSystem`/`MovementSystem`), `Command` (`MoveCommand`/`StopCommand`), `SpatialHash`. Straight-line movement only -- no map/pathfinding until 2.1. Verified headless: 9/9 tests, exit 0 | **[MVP]** |
| 0.6 | Ã¢Å“â€¦ **DONE** Ã¢â‚¬â€ `Net` autoload: `host_solo()` (real ENet server bound to 127.0.0.1), `submit_command()`/`_recv_command` RPC up, `SnapshotSystem` + `_recv_snapshot` RPC down; `SimHost` owns the server-side `SimWorld`, driven by `SimClock`. View layer: `Iso`, `EntityView`/`EntityViewPool` (pooled, interpolated), `GameView.apply_snapshot()`. `host_open()`/`join()` (remote multiplayer) deferred -- out of MVP scope (Ã‚Â§10). Verified headless: 22/22 tests, exit 0 | **[MVP]** |
| 0.7 | Ã¢Å“â€¦ **DONE** Ã¢â‚¬â€ `SimWorld.state_hash()` + regression tests, `Replay` (record/play, JSON round trip), `sim/` boundary check (as a headless test, not a separate Python grep Ã¢â‚¬â€ so it runs inside the one test command), `StressTest.tscn` (verified on the Ã‚Â§3.0 reference device Ã¢â‚¬â€ HONOR LNA-NX1 Ã¢â‚¬â€ at 200 units: sim tick cost 0.39/0.23/6.28 ms avg/min/max, frame rate 60/26/61, 209 draw calls; the max/min outliers are the stress test's own 4-second retarget burst Ã¢â‚¬â€ 200 individual `submit_command()` calls in one frame Ã¢â‚¬â€ not a sim/net cost, since a real shared-destination move order is one `MoveCommand` with many `unit_ids`). GdUnit4 deliberately not adopted (see Ã‚Â§1.3). Also fixed on real hardware: `export_presets.cfg` shipped with `permissions/internet=false`, which silently broke `host_solo()` (Android requires INTERNET even for loopback sockets) Ã¢â‚¬â€ `StressTest.tscn` now surfaces a host_solo() failure in its own report instead of quietly spawning 0 units. 29/29 tests, exit 0 | **[MVP]** |
| 0.8 | Ã¢Å“â€¦ **DONE** Ã¢â‚¬â€ `.gdignore` added to `UI_Sprites/` and `insperation_pictures/` per Ã‚Â§4 (both sit at the repo root, outside `game/`, the actual Godot project root, so this has no functional effect on Godot's own scanning Ã¢â‚¬â€ added for consistency with the documented layout regardless). Non-synced working root created on this machine at `C:\Users\herman.ras\Downloads\AOD_game\{art_source,art_work,packs,tools_env}` (Ã‚Â§1.3), ready for 0.9. `.gitignore` fixed to allow tracking a `.gdignore` marker inside an otherwise-fully-ignored directory (a bare `dir/` pattern excludes the directory itself, so git never descends far enough to honour a per-file negation Ã¢â‚¬â€ needs `dir/*` instead). Also documented (Ã‚Â§1.3): `export_presets.cfg`'s `permissions/internet` requirement, found on real hardware at 0.7. (Superseded same day: `export_presets.cfg` turned out to hold no secrets, so it's now tracked in git rather than gitignored per-user state Ã¢â‚¬â€ see Ã‚Â§1.3.) | **[MVP]** |
| 0.9 | Ã¢Å“â€¦ **DONE** Ã¢â‚¬â€ render pipeline built as **[`blender_3d_to_2d_isobake`](https://github.com/HermanRas/blender_3d_to_2d_isobake)**, its own GPL-2.0-or-later repo (Ã‚Â§2.2), and proven end to end on **three real assets**: a grass tile (64Ãƒâ€”32 exactly), an oak (5 directions), and an animated villager (240 frames Ã¢â‚¬â€ idle/walk/work_chop/walk_carry_wood Ãƒâ€” 5 directions). Toolchain is fully portable: Blender 4.5.12 extract + a venv made from Blender's own Python, nothing installed system-wide. `isobake calibrate` verifies the camera three independent ways (configured / analytically projected / rendered) and all three agree at 64.00 Ãƒâ€” 32.00, area 1024.00 pxÃ‚Â². 62 unit tests, no Blender required, so the packer is testable on any machine. (isobake Ã¢â‚¬â€ a separate repo Ã¢â‚¬â€ is the one place a GitHub Actions workflow is actually committed, `.github/workflows/ci.yml`, running pytest on 3.11Ã¢â‚¬â€œ3.13. **This** repo has none; see Ã‚Â§1.2.) **Both High/Medium art risks retired** (Ã‚Â§14): the pipeline produces usable sprites, and animation transfer needs no retarget rig Ã¢â‚¬â€ a gatherer clip drives 83 of an actor's 102 bones by name. Atlas format revised (Ã‚Â§9.1) to per-frame rects + multi-page, and anchors now come from the projected world origin, eliminating jitter by construction. `build_packs.py` deferred to 0.3 where it belongs (it is a `.pck` concern, not a render one) | **[MVP]** |

### Phase 1 Ã¢â‚¬â€ Main menu *(IDEA phase 1)*

| # | Item | Tag |
|---|---|---|
| 1.1 | Placeholder buttons: PLAY, MULTIPLAYER, SETTINGS, CREDITS, QUIT; dragon-HUD skin + fonts | **[MVP]** |
| 1.2 | PLAY Ã¢â€ â€™ `host_solo()` Ã¢â€ â€™ `Match.tscn` | **[MVP]** |
| 1.3 | Splash/boot screen | **[MVP]** |
| 1.4 | Credits screen (Ã‚Â§2.3) | **[MVP]** |
| 1.5 | Settings screen | |
| 1.6 | Lobby: host/join, map & faction & win-condition pick | |

### Phase 2 Ã¢â‚¬â€ Map *(IDEA phase 2)*

| # | Item | Tag |
|---|---|---|
| 2.1 | Ã¢Å“â€¦ **DONE** Ã¢â‚¬â€ `SimMap`: `size`, `terrain`/`move_cost`/`occupancy` as three parallel packed arrays indexed row-major, `in_bounds`/`terrain_at`/`cost_at`/`occupant`/`is_passable`/`can_place_building`/`find_free_adjacent`, plus `Domain` (land/water/air, land-only in play per 2.2) and a `TERRAIN_COST` table on a base-10 scale so slower ground stays integral. Created by `SimWorld.setup()` from `MatchConfig.map_size` (64Ãƒâ€”64 debug default) and **folded into `state_hash()`** Ã¢â‚¬â€ without that, clients disagreeing about the terrain would hash identically and the 0.7 desync check would pass while they diverged. Two decisions worth knowing: **occupancy is for static footprints only** (buildings, resource nodes) and never units, which stay in `SpatialHash` Ã¢â‚¬â€ otherwise every step would rewrite the grid and a tile a unit merely crossed would read as unpathable; and `find_free_adjacent()` scans a **fixed** ring order, asserted against an exact tile rather than "any free tile", because two clients spawning production must choose the same one. `is_terrain_passable()` exists alongside `is_passable()` because placement asks "could anything ever stand here" and pathing asks "can it now" Ã¢â‚¬â€ a building's own tiles are occupied by definition. 113/113 tests | **[MVP]** |
| 2.2 | Domain rules Ã¢â‚¬â€ land only in MVP | **[MVP]** (land) |
| 2.3 | âœ… **DONE** â€” `SimWorld.spawn_building()` / `spawn_resource_node()` write footprints into `SimMap.occupancy` and refuse a placement that will not fit, so a building the grid does not know about cannot exist. `despawn()` frees tiles *before* dropping the entity â€” occupancy is keyed by id, so the other order would leave tiles claimed forever by something that no longer exists and 5.5 would punch unbuildable holes in the map. New: `SimBuilding` (phase, footprint, `origin_tile()`/`footprint_rect()`, build progress) and `SimResourceNode` (kind, amount, size class, gather slots). A building's `pos` is its footprint **centre** so the view draws every entity identically; `origin_tile()` derives the grid's top-left rather than storing it, so the two cannot disagree | **[MVP]** |
| 2.4a | âœ… **DONE** â€” `MapGen.build_debug_map()`: grass interior, dirt border so the map edge is visible before a camera clamp exists to prove itself against (3.3), one start position. Fully deterministic â€” no `randi()`, no `Time`, no unordered iteration â€” and asserted by building two worlds from one `MatchConfig` and comparing `state_hash()`, because host and client each build their own and a difference on tick 0 is a desync before any command is issued | **[MVP]** |
| 2.4b | Procedural generator, 2Ã¢â‚¬â€œ8 players, size scales with player count | |
| 2.5 | Fog of war: `VisionSystem` + server-side snapshot filtering + `FogLayer` | |
| 2.6 | âœ… **DONE** â€” 1 Town Centre (complete, full health, 8Ã—8 from the measured art) + 5 villagers ringed onto distinct passable tiles, plus a 12-tree wood, 3 gold, 4 deer. Stats come from `units.json`/`buildings.json`/`resources.json` via `GameDataRegistry`, which **replaced `SimWorld`'s hardcoded `_UNIT_DEFS` placeholder**. Verified by eye in `dev_preview/preview_world.tscn` â€” a real Athenian settlement with villagers, deer, gold and wood | **[MVP]** |
| 2.7 | Real terrain tileset (art track A.1) | |

### Phase 3 Ã¢â‚¬â€ Camera & world view *(IDEA phase 3)*

| # | Item | Tag |
|---|---|---|
| 3.1 | ✅ **DONE** — Terrain drawn by a real `TileMapLayer` (`src/view/terrain_layer.gd`), built from `size` plus raw terrain bytes rather than a `SimMap`, so the view holds no reference into the sim and its tests run on a literal `PackedByteArray`. Tiles resolve through the asset seam, so undeclared terrain (`terrain.dirt`, art track A.1) paints as the loud magenta placeholder rather than leaving holes in the ground. **Depth sorting fixed**: `Iso.footprint_sort_offset()` moves a footprint's sort point to its FRONT tile and `EntityView.draw_offset` carries the equal and opposite shift so the art stays on the centre — villagers behind the town centre are now occluded by its roof. Entities are Y-sorted by the engine, which keys off exactly that quantity. Also found and fixed a **half-tile terrain offset**: `tile_to_world()` is a tile CORNER (it equals `sub_to_world` at exact tile multiples) while the sim stands every entity at the tile CENTRE, so `tile_centre_to_world()` was added and the two pinned together by a test against the sim's own spawn convention — invisible on uniform grass, obvious at any terrain boundary. `rendering_quadrant_size` was measured rather than guessed, and the answer is backwards from the obvious reasoning: 8 gives 32 draw calls where the engine default of 16 gives 165 and 32 gives 280, because a large isometric chunk is a diamond straddling a rectangular viewport and must draw every tile inside it. New entities `snap_to()` their first position instead of gliding in from wherever their pooled view last sat. `dev_preview/preview_world.tscn` rewired onto the production path — it no longer draws its own ground or does its own sorting, which is the duplication that let it look correct while the real game rendered everything magenta | **[MVP]** |
| 3.2 | ✅ **DONE** — Edge swipe up/down on either side strip (both sides, per IDEA 3.2; 100 canvas units wide, ~10 mm on the reference device). Zoom range 0.6–2.0, multiplied not added per the `zoom_by(factor)` sketch above — a fixed step per pixel would crawl at 2× and leap at 0.6×. `ZOOM_PER_PIXEL` is derived so one full-height swipe of the 648-tall canvas crosses the range exactly once, and that is asserted rather than trusted to the arithmetic in its comment. The gesture is decided on touch-down and held until release, so a drag that wanders into the strip does not change meaning halfway through. Zooming out re-clamps the camera (a wider view can leave a legally parked camera looking past an edge), and the map itself sets the zoom-out floor once it is smaller than the screen. `begin_gesture()`/`apply_drag()` are public so 4.2's `InputRouter` can take over recognition without touching the rules | **[MVP]** |
| 3.3 | ✅ **DONE** — `src/view/camera_rig.gd`, a `Camera2D` replacing the per-scene "shove the world to the middle of the screen" hack each scene carried. Drag to pan; touch and mouse handled separately because `emulate_mouse_from_touch` is off and touch is not emulated from mouse either, so handling one would work on the phone but not on the desktop the work is done on. **Clamping is two rules, not one**: the camera's centre stays on the map DIAMOND (clamped in tile space, where the diamond is an axis-aligned box), and then the viewport stays inside the projected box. Box-only clamping is what `Camera2D.limit_*` does, passed every unit test, and still allowed a screen that was ~85% void at the west corner — the box extends half a map beyond the diamond's tip. The same corner now frames ~80% ground, pinned by a test written as what the player sees rather than as coordinates. Done by hand rather than with the engine's limits so the rule is reachable from a headless test and survives 3.2 changing the visible size. `view_size` is tracked via `size_changed`, because a device rotation invalidates the clamp margin, the zoom floor and the edge strips at once. Also fixed: `StressTest`'s root `Control` defaulted to `MOUSE_FILTER_STOP` and would have swallowed every mouse event before the camera saw it, and the HUD had to move onto CanvasLayers (two — backdrop below the world, readout above) or it pans away with the ground | **[MVP]** |
| 3.4 | Double-tap minimap Ã¢â€ â€™ centre on own Town Centre | **[MVP]** |
| 3.5 | Camera follow selected unit | |
| 3.6 | ✅ **DONE** — and with it the first thing in the project that is a game rather than a harness: `scenes/game/Game.tscn` + `src/view/game_scene.gd`, now the main scene. Hosts through `Net.host_solo()` so the local player's orders take the same route a remote player's would — command RPC up, snapshots back down — rather than reaching into `SimWorld` to make something happen. Tap priority is: my own unit → select it; something already selected → move order to the tapped tile; otherwise → clear. Own units win over the move order so re-selecting never accidentally sends the current selection walking onto the unit you were trying to pick; the cost is that you cannot order a unit onto a tile another of your units occupies, which is 4.5's problem. The selection is **filtered to units** before becoming a `MoveCommand`, because `validate()` rejects the whole command if any id is not a unit — selecting the town centre alongside villagers would otherwise silently cancel the move for the villagers too. Unit-ness is asked of the registry rather than inferred from the snapshot's shape, or a 1x1 resource node with no `phase` field reads as a unit and orders get sent naming trees. Verified end to end by driving the real scene: tap villager at (27,27) → selected → tap (38,38) → she routes around the 8×8 town centre and arrives. Terrain is still read from `Net.host()` (the documented solo-only exception); a remote client will need the map sent to it | **[MVP]** |
| 3.7 | Tap minimap to move selected units | |
| 3.8 | Tap minimap (nothing selected) Ã¢â€ â€™ move camera | **[MVP]** |

**Verified on hardware after 3.1/3.2/3.3** — the §3.0 reference device (HONOR LNA-NX1, 2600 × 1200, Mali-G610), driving real touch events through `adb shell input swipe` with the camera's live state on screen, so these are measurements rather than a reading of a screenshot:

| What | Result |
|---|---|
| Viewport | **1404 × 648** — exactly the figure §3.0 predicted for this device from `stretch/aspect=expand` |
| Pan | A −400, −200 physical-pixel drag moved the camera **+213, +107** canvas units. The device is 1.852× the canvas, so −400 px is −216 canvas: correct direction, correct magnitude |
| Zoom in | Left strip, swipe up → hit the **2.0** ceiling and clamped (`exp(378 × 0.0018566) = 2.017`) |
| Zoom out | Right strip, swipe down → **0.987** against **0.991** predicted; the gap is drag-event quantisation, not a maths error |
| Cross-talk | **None.** Camera position was byte-identical at 213,1131 across *both* edge swipes, and the mid-screen drag left zoom at 1.000. Zoom never pans; pan never zooms |
| 200 units + settlement | **60/58/60 fps**, **24–65 draw calls**, sim tick **0.31–1.54 ms** avg |

These supersede the 0.7 device figures recorded above, which predate terrain joining the render path.

**One figure is still over budget**: sim tick **max 7.63 ms** against the < 5 ms target. It is the stress harness's own behaviour — 200 individual `submit_command()` calls in a single frame every 4 seconds — and a real shared-destination order is one `MoveCommand` carrying many `unit_ids`. To be confirmed against real orders at 4.3 rather than assumed away.

### Phase 4 Ã¢â‚¬â€ Units *(IDEA phase 4)*

| # | Item | Tag |
|---|---|---|
| 4.1 | ✅ **DONE** — `MovementSystem` walks the route `PathService` returns, waypoint by waypoint; the old straight line survives only as the step between two adjacent tiles, where it is correct by construction. A tick's movement budget carries across waypoints rather than being spent at the first corner. **Stop at nearest reachable tile**: an order onto a blocked tile (tapping a tree) is honoured as far as it can be, and `set_path()` rewrites `task_target_tile` to where the route actually ends — comparing against the ORDER instead would leave the unit in MOVE forever, standing still beside the tree it was sent to. An unreachable order retires to IDLE rather than walking forever. A unit whose search is still queued waits rather than setting off in the target's general direction, since guessing walks it into the wall the route was going to avoid. System order is load-bearing and commented: command, plan, retire, move | **[MVP]** |
| 4.2 | ⚠️ **PARTIAL** — `PathService` on `AStarGrid2D` done; **steering local avoidance is not** (units still walk through each other). Requests are queued and solved against a per-tick budget rather than on the spot, since ordering 200 units is one command but 200 searches. `MAX_SOLVES_PER_TICK = 12` is measured against the < 5 ms tick budget on the 0.7 harness's worst case — 200 units all re-planning in one frame: budget 32 → 9.48 ms, 16 → 5.09 ms, 12 → **4.30 ms**, inside with headroom. Diagonals do not cut corners past a blocked tile, so a villager cannot slip between two buildings that touch. Grid updates are **incremental** by dirty rect: a full 64×64 sweep is 4096 `set_point_solid()` calls at ~12 ms, which would recur on every building placed, so the full sweep now happens once at map-gen time where it hides in load. Determinism is argued in the file header and pinned by tests: FIFO queue, fixed budget, and a substitute-tile search that scans the whole ring rather than returning on first hit — two clients picking different sides of the same tree is a desync | **[MVP]** |
| 4.3 | ✅ **DONE** — `Selection` (client-side, never sent — a selection in the state hash would desync the moment one player tapped), `InputRouter` recognising taps, a selection ring, and a panel that populates from `units.json`. Picking is **by tile, not by sprite bounds**: a 10 m tree's sprite covers the six tiles behind it, so bounds-picking selects the tree when the player clearly tapped the ground in front of it. Units win ties over buildings. Buildings are tappable anywhere on their footprint, not just their centre tile. Found and fixed on the way: `Iso.world_to_tile()` ROUNDS — correct for un-projecting a tile corner, wrong for "which tile is this point inside", which sent the near half of every tile to its neighbour and missed half of all taps. `Iso.tile_at()` floors, and the two are now documented as different questions. The ring is built in metre space and projected, so it lies flat as the right isometric ellipse, and is sized from the DECLARED footprint rather than sprite bounds. A dead entity drops out of the selection, or an order would name an entity the sim rejects and the player would see nothing happen | **[MVP]** |
| 4.4 | ✅ **DONE** -- `GatherCommand` and `BuildCommand` complete the command surface alongside `MoveCommand`/`StopCommand`. Both reuse the walk-there machinery MOVE already had: PathService substitutes the nearest walkable tile when the target itself is occupied ground (a resource node, a foundation), and MovementSystem now advances ANY unit with a route left to walk rather than only ones tasked MOVE, so GATHER/RETURN/BUILD travel for free off the existing pathing. `GatherSystem` and `BuildSystem` (6.4) are the new arrival-time systems that act once the walk is done -- TaskSystem still only ever retired MOVE. System order is `CommandSystem -> PathSystem -> TaskSystem -> GatherSystem -> BuildSystem -> MovementSystem`, so an action that starts a new route this tick (a load handed off, a build finished) is walked the same tick rather than costing a tick of visible delay | **[MVP]** |
| 4.5 | Context-sensitive action flash on tap target | **[MVP]** |
| 4.6 | ✅ **DONE** -- `EntityView` draws the dot: a small circle above the sprite, hidden at full health, coloured via the shared `HealthDot.color_for()` helper (`src/view/health_dot.gd`) so the dot and `SelectionPanel`'s hp text always agree on the same orange/red thresholds. Positioned off the visual's declared `height_m` through `Iso.height_to_world()`, the same convention the selection ring uses for footprint. `hp`/`max_hp`/`alive` were already in `SimEntity`/`SnapshotSystem`; this phase only had to draw them | **[MVP]** |
| 4.7 | ✅ **DONE** -- new `DeathSystem`, last in `SimWorld`'s system order, reacts once `alive` goes false: plays `die`, drops `carry_kind`/`carry_amount` (no pile to drop it into in MVP -- just lost), then counts `SimUnit.corpse_ticks_left` down from `CORPSE_TOTAL_TICKS` (700 ticks = 70 s), switching to `decay` for the final `CORPSE_FADE_TICKS` (100 ticks = 10 s) before `despawn()` removes it for good. `SnapshotSystem` now sends a corpse as `updated` for as long as it still exists and a REAL `removed[]` (`SimWorld.removed_this_tick`) instead of the always-empty stub it shipped with -- the first thing in MVP that actually despawns mid-match. `GameView` fades `modulate.a` over the last 10 s and treats `alive == false` as unselectable everywhere picking touches (`pick()`, `units_in_box()`, `villager_counts()`, `Selection.retain_only()`). MVP has no combat yet, so a debug-only `DebugDestroyCommand` (routes through the existing `SimEntity.take_damage()`, so it needs no changes the day real combat lands) is what brings hp to 0 -- wired to a "Destroy (debug)" button in `SelectionPanel`. Verified live on device: destroying a villager plays the fall, drops it from the villager count, and leaves an unselectable corpse | **[MVP]** |
| 4.8 | Garrison | |
| 4.9 | Defensive garrison damage bonus | |
| 4.10 | Special abilities + cooldowns | |
| 4.11 | Population cap from houses/town centres | |
| 4.12 | Stances | |
| 4.13 | Military units + `CombatSystem` | |
| 4.14 | Formations | |

### Phase 5 Ã¢â‚¬â€ Buildings *(IDEA phase 5)*

| # | Item | Tag |
|---|---|---|
| 5.1 | ✅ **DONE** -- `PlaceBuildingCommand` pays the cost and claims a FOUNDATION-phase footprint, validated the same way every other command is: `can_afford()` plus `SimMap.can_place_building()`, checked once in `validate()` and trusted in `apply()` since nothing else can run between them for the same command (CommandSystem is sequential). Placement is a real drag: entering build mode calls `CameraRig.set_locked(true)`, so the one finger that would otherwise pan (3.3) now drags `PlacementGhost` instead -- snapped to grid, coloured live by legality -- and releasing commits it if valid. `InputRouter` grew three signals for this (`single_pressed`/`single_drag_moved`/`single_released`), reported unconditionally rather than only for gestures that qualify as a tap; `tapped` is resolved and emitted BEFORE `single_released` for the same release, on purpose, so a placement handler clearing build-mode state on release cannot make `_on_tapped` see a different state than the one this gesture actually had. Two-finger pan was ruled out as the alternative -- it collides with box-select's own trigger (8.3) and breaks one-handed play -- so the lock, not a gesture swap, is what frees the finger. An invalid drop flashes the ghost red for 0.3s and stays in build mode; Cancel Build or a valid placement unlocks the camera again. Verified on device: dragging clear across the screen while placing produces ZERO camera movement (locked), and Cancel Build immediately restores ordinary one-finger panning | **[MVP]** |
| 5.2 | ✅ **DONE** -- `SimBuilding.Phase` (FOUNDATION/UNDER_CONSTRUCTION/COMPLETE/DESTROYED) and `add_build_progress()` landed at 4.4 alongside `BuildCommand`/`BuildSystem`; what 5.1 adds is a way to REACH a foundation without a debug command placing it directly. The view side was already wired before either: `GameDataRegistry.visual_for_phase()` and `test_visual_seam.gd`'s `test_building_phase_visuals_exist_for_every_phase_a_building_can_be_in` predate this session. Confirmed end to end on device this session: `Build House` -> tap -> foundation placed -> (blocked on affordability, per 5.1's note) | **[MVP]** |
| 5.3 | Building upgrades | |
| 5.4 | ✅ **DONE** -- `TrainCommand` enqueues (pays up front, same convention as `PlaceBuildingCommand`), `CancelProductionCommand` refunds exactly what was paid, `ProductionSystem` advances only the FRONT of the queue and spawns via `SimMap.find_free_adjacent()` on completion. **A finished order is not popped until it actually spawns** -- a packed town centre backs the order up and retries every tick rather than losing the villager who was paid for; test_a_full_town_centre_backs_up_production_rather_than_losing_the_unit proves it against a map walled off except one distant tile. `SelectionPanel` grew a `Train Villager` button + queue-count label, gated on `is_mine` so a future enemy building shows health, not a button to spend on ITS queue; it emits `train_requested`/`cancel_requested` rather than calling `Net.submit_command()` itself, so commands still leave the view layer only through `GameScene`. Verified on device: selecting the starting Town Center shows the button, and pressing it with 0 food correctly enqueues nothing, matching `test_training_is_rejected_when_the_player_cannot_afford_it` | **[MVP]** |
| 5.5 | ✅ **DONE** -- same `DeathSystem`: a building at hp 0 flips `SimBuilding.phase` to `DESTROYED` (`BuildingDef.visual_for_phase()` already pointed that at `visual_rubble`) and calls the new `SimWorld.free_footprint()` -- `despawn()`'s tile-freeing half, minus removing the entity -- so the ground is buildable again the instant it falls. Rubble has no fade timer: it stays in `entities` and renders opaque forever, matching A.2's "no damaged tier" art note. `ProductionSystem` now skips a dead building's queue so nothing trains out of the wreckage. Verified live on device: destroying the starting Town Centre via the debug button turns it to rubble, frees its tiles, and the tap panel no longer opens on it | **[MVP]** |
| 5.6 | ✅ **DONE** -- rides 4.6's dot: `SimBuilding` already carried `hp`/`max_hp` (2.6/5.1), so this phase was wiring, not new state. Hidden once destroyed -- rubble has no damage tiers to report (A.2) | **[MVP]** |
| 5.7 | Full building roster | |

### Phase 6 Ã¢â‚¬â€ Resources & wildlife *(IDEA phase 6)*

| # | Item | Tag |
|---|---|---|
| 6.1a | Deer as a huntable food node (carcass gatherable) | **[MVP]** |
| 6.1b | Wildlife roaming + flee-and-relocate | |
| 6.2 | Gold mines, 3 size classes, `gather_slots` | **[MVP]** |
| 6.3 | Trees + forest clustering, 3 size classes | **[MVP]** |
| 6.4 | ✅ **DONE** -- `GatherSystem` drives the loop: walk to the node (PathService substitutes an adjacent tile, since the node's own tile is occupied ground), gather 1 unit every `ceil(100 / gather_rate)` ticks -- kept as a whole-tick countdown rather than a float accumulator, since a float would round differently across machines and desync (7.1) -- up to `carry_cap`, then walk to `SimWorld.nearest_drop_off()` (the nearest complete building of the unit's own player that accepts the kind, ties broken by lowest entity id) and deposit into `SimPlayer.stock`, then either turn back for the same node or retire once it is empty. The final load is capped by what the node has left, not padded up to carry_cap. **Known gap**: `gather_slots` (6.2) is not enforced yet -- any number of villagers can work one node at once; the cap wants its own home now that something actually gathers | **[MVP]** |
| 6.5 | Stone, farms, fishing, berry bushes, boar | |

### Phase 7 Ã¢â‚¬â€ Resource HUD *(IDEA phase 7)*

| # | Item | Tag |
|---|---|---|
| 7.1 | ✅ **DONE** -- a new `EventBus` autoload (`resources_changed`, `villagers_changed`) decouples the HUD from whoever happens to receive a snapshot. `GameScene` emits both after every `apply_snapshot()`: `resources_changed` from the snapshot's existing `player_state.stock` (SnapshotSystem already carried it, unused until now), `villagers_changed` from a new `GameView.villager_counts()` headcount over units in view. That headcount needed `task` added to `SimUnit.to_snapshot()` -- it was not there, so the view had no way to tell an idle villager from a busy one without reaching into SimWorld. `ResourceHUD` is a deliberately plain text row, same stand-in spirit as `SelectionPanel` (4.3) -- real icons are ASSET_MISSING.md 1.5's TODO and this is thrown away once they land. Built in `_init()` rather than `_ready()` so a bare `.new()` is fully wired for testing, matching how `GameView.pool`/`terrain` are field initializers rather than `_ready()`-only setup | **[MVP]** |

### Phase 8 Ã¢â‚¬â€ Main game interface *(IDEA phase 8)*

| # | Item | Tag |
|---|---|---|
| 8.1a | Selection panel shell + single-unit view | **[MVP]** |
| 8.1b | Building view: queue slots + train buttons | **[MVP]** |
| 8.1c | Multi-select portrait grid | **[MVP]** |
| 8.2a | Circular minimap: terrain, entity blips, camera viewport rect | **[MVP]** |
| 8.2b | 4 corner buttons (menu, chat, minimize, trade Ã¢â‚¬â€ trade locked behind market) | |
| 8.3 | ✅ **DONE** — two fingers down opens a box spanned by them; spreading them sizes it, lifting either one commits it. `InputRouter` grew the gesture, `SelectionBox` draws it in SCREEN space (drawing it in world space would slide it around under the fingers holding it whenever the camera moved), and `GameView.units_in_box()` resolves it. **Own units only** — a box that also caught the town centre, four trees and a deer is not what anyone means by box select. Tested against each unit's ground point rather than its sprite, for the same reason picking goes by tile: a box over empty grass would otherwise catch whatever tall thing was leaning into it from behind. Results are returned in id order, because a box catching more than `MAX_SELECTED` has to keep the same units on every machine — the selection becomes a command, and two clients disagreeing about its contents is a desync. A box under `MIN_BOX` is discarded as a fumbled two-finger tap rather than clearing the selection. **The interaction fix this needed**: `CameraRig` now pans only while exactly ONE finger is down, or the map dragged out from under the box being drawn; and it does not adopt the remaining finger when the other lifts, which would snap the view by however far that finger had drifted. Verified by driving the real scene — four villagers ringed, camera byte-identical at (0, 1024) before and after | **[MVP]** |
| 8.4 | Notice/toast line | **[MVP]** |
| 8.5 | Pause/in-game menu, resign | **[MVP]** |

### Phase 9 Ã¢â‚¬â€ Ages & tech *(IDEA phase 9)*

| # | Item | Tag |
|---|---|---|
| 9.1 | Age header: roman numeral in gold circle | |
| 9.2 | Age advancement progress bar | |
| 9.3 | `TechSystem`: research timers, stat modifiers, gating | |
| 9.4 | Tech tree screen | |
| 9.5 | Faction unique units/bonuses | |

### Phase 10 Ã¢â‚¬â€ Control groups *(IDEA phase 10)* Ã¢â‚¬â€ **all MVP**

Core mobile mechanic; needs testing under real thumb use, so it ships in MVP.

| # | Item | Tag |
|---|---|---|
| 10.1 | 5 circular slots, empty state, `ControlGroups` UI wired to `EventBus` | **[MVP]** |
| 10.2 | Two-finger box select Ã¢â€ â€™ double-tap a slot to assign (`SetControlGroupCommand`) | **[MVP]** |
| 10.3 | Double-tap a unit Ã¢â€ â€™ select all of that type on screen; double-tap slot to assign | **[MVP]** |
| 10.4 | Slot icon = most-represented unit type; reverts to empty circle when emptied | **[MVP]** |
| 10.5 | Single tap selects the group; double tap centres camera on it | **[MVP]** |
| 10.6 | Groups persist in `SimPlayer`, survive reconnect (Ã‚Â§7.1) | **[MVP]** |

### Phase 11 Ã¢â‚¬â€ Win conditions *(IDEA phase 11)*

| # | Item | Tag |
|---|---|---|
| 11.1 | `WinConditionSystem` + conquest mode; result screen | |
| 11.2 | Additional modes (regicide, king of the hill, capture the flag, wonder) | |
| 11.3 | Mode shown in lobby and match-start screen | |

### Phase 12 Ã¢â‚¬â€ Multiplayer & AI *(IDEA phase 12)*

| # | Item | Tag |
|---|---|---|
| 12.1a | `host_open()` on 0.0.0.0 + `join()` | |
| 12.1b | LAN discovery, reconnect, lag compensation, desync detection | |
| 12.2a | `AISystem` state machine emitting normal `Command`s | |
| 12.2b | AI difficulty levels | |
| 12.3 | Campaign: scripted triggers/objectives on the host-loopback path | |
| 12.4 | Save/load and replays | |

### Phase 13 Ã¢â‚¬â€ Dragons *(IDEA phase 13)*

| # | Item | Tag |
|---|---|---|
| 13.1 | Dragon unit: air domain, castle-tier HP/damage, fire-breath AoE + cooldown | |
| 13.2 | Dragon Nest POI: guardian dragon, claim-on-defeat, 360 s baby-dragon timer, destructible | |

---

## 12. Post-MVP prioritisation

| Candidate | Impact | Effort | Verdict |
|---|---|---|---|
| 4.13 Military units + combat | Very high | Medium | **First** |
| 2.5 Fog of war | High | Medium | **Second** |
| 12.2a AI opponent | Very high | Medium-high | **Third** |
| 4.11 Population cap | Medium | Low | Quick win |
| 5.7 More buildings | High breadth | Low each (data-driven) | Quick win |
| 11.1 Win condition | High | Low | Quick win |
| 9.x Ages & tech | High but broad | High | Batch later |
| 12.1 Real multiplayer | High | Medium (socket only) | After AI |
| 13.x Dragons | The differentiator | High (bespoke art) | Once the RTS is a game |

**First post-MVP batch:** 11.1 + 4.11 + 4.13 + 2.5 + 12.2a Ã¢â‚¬â€ turns the economy demo into a winnable match.

---

## 12A. Art track (parallel, asynchronous)

Never blocks gameplay phases. Ordered by visual payoff per unit of effort.

| # | Item | Depends on |
|---|---|---|
| A.1 | Terrain tile set from 0 A.D. ground textures. **Grass done** (`terrain.grass`, 64×32 exactly, recipe `terrain_grass.toml`); dirt and sand are the same recipe with a different `terrain =` line, and the debug map already paints a dirt border it has no tile for. Water/rock only matter once `SimMap` uses them | 0.9 |
| A.2 | Ã¢Å“â€¦ **DONE** Ã¢â‚¬â€ Town centre + house, each with foundation and rubble (`SimBuilding.Phase`). Six single-frame atlases at `directions = 1`; foundations and generic rubble keyed by footprint size so the rest of the roster (5.7) reuses them. No damaged tier Ã¢â‚¬â€ 0 A.D. has none, and health is the health dot (5.6). ASSET_MISSING.md 1.2 | 0.9 |
| A.3 | ✅ **DONE** — Villager, all 11 animations × **8** directions = 960 frames (8 not 5: she holds an axe in one hand, so mirroring would swap it). Recipe `villager.toml`. **Needs one rebake** for the height override in §13.2 item 9, and carries the `work_mine` dress artefact in item 7 | 0.9 |
| A.4 | Resource props: tree (3 sizes + stump), gold mine, deer. **Gold mine Ã¢Å“â€¦ done** (`geology/metalmine_alpine.xml`, 5 directions, ~1.4 Ãƒâ€” 1.9 tiles); deer Ã¢Å“â€¦ done but **static** (item 8). Remaining: 2 more tree size classes + stump, and the deer carcass | 0.9 |
| A.5 | UI chrome from the itch.io dragon packs | none |
| A.6 | Team-colour outline shader | A.3 |
| A.7 | Audio pass Ã¢â‚¬â€ 0 A.D. sfx/music into `audio.json` | 0.9 |
| A.8 | Military unit art | A.3 |
| A.9 | **Dragon + nest Ã¢â‚¬â€ bespoke** | A.3, A.8 |

A.1 and A.2 come first: cheap, transform the look, and validate the render pipeline before the expensive villager work.

---

## 13. Standing policies & open items

### 13.1 Standing policies (approved)

- **Third-party open-source code and addons may be used freely** Ã¢â‚¬â€ Godot RTS templates, pathfinding/flow-field addons, fog-of-war addons. Requirement: **credit only what is actually used**, recorded in `CREDITS.md` + `assets/LICENCES.md`, and the licence must be compatible with an open-source CC-BY-SA art release.
- **Reference engines may be studied for design** (`OpenRA`, `0 A.D.`, `Spring/Recoil`, `Widelands`) Ã¢â‚¬â€ netcode models, data formats, pathfinding approaches. Credit when code or assets are actually taken, not for reading.

### 13.2 Genuinely open

| # | Item | Owner |
|---|---|---|
| 1 | ~~**Does the render pipeline produce usable sprites?**~~ Ã¢Å“â€¦ **ANSWERED at 0.9 Ã¢â‚¬â€ yes.** Proven on a grass tile, an oak and a 240-frame animated citizen. A.3 can be scheduled | Ã¢Å“â€¦ 0.9 |
| 2 | **Which 0 A.D. actors map to our entities.** Their unit set is ancient-warfare, ours is medieval-fantasy Ã¢â‚¬â€ needs a hand-picked actorÃ¢â€ â€™`vis.*` mapping, and some entities may have no good match. Three picked at 0.9 (`grass/grass1`, `flora/trees/oak`, `units/athenians/female_citizen`), six more at A.2 (the Athenian civic centre and Hellenic house plus their foundations and rubble Ã¢â‚¬â€ same civ as the villager, so the settlement reads as one architectural style); the mapping lives in `tools/recipes/`. `vis.deer` (`fauna/deer.xml`) and `vis.gold_mine` (`geology/metalmine_alpine.xml`) picked at A.4, so **every MVP entity now has an actor**. Two findings from the gold mine worth carrying to the rest of the roster: (a) civ consistency is the right default for *architecture* but not for scenery Ã¢â‚¬â€ the civ-matching `metalmine_granite_greek` lost to alpine purely because its texture reads as moss rather than ore, and all the old-generation ore actors share one mesh and differ only in texture; (b) 0 A.D.'s newer, better-sculpted asset generations are often authored sunk into terrain and so are *blocked behind the z=0 ground clip* (item 7a), which makes that fix an art-quality unlock and not just a cosmetic tidy-up | Ã¢Å“â€¦ A.4 |
| 3 | **Audio fit** Ã¢â‚¬â€ 0 A.D. audio exists and is licence-clean, but its voices are civilisation-specific (`greek`, `latin`, `napatan`, `persian`) and won't suit. Decide what's reusable vs newly sourced | [ASSET_MISSING.md](ASSET_MISSING.md) |
| 4 | ~~**Icon volume**~~ Ã¢Å“â€¦ **ANSWERED Ã¢â‚¬â€ generate.** 15 icons delivered at 0.3 staging, AI-generated (Google Gemini) at 100Ãƒâ€”100 RGBA from a 5Ãƒâ€”5 source sheet: 5 resource (`res_food/wood/gold/stone/villagers`) and 10 action (`res_`/`act_` prefixes group them by the panel that uses them). Live in `game/assets/ui/icons/`; the sheet stays in `Icons/` as the source, with **10 empty slots** for the rest. A further 5 HUD buttons landed the same way (`hud_techtree/score/trade/chat/settings`, from `MapIcons_500x100.png`) for the corners around the minimap panel Ã¢â‚¬â€ 20 icons total. Still to draw: unit/building portraits for the selection panel and control-group slots, and the trebuchet pack/unpack pair `icons.txt` lists but the sheet does not yet have. Their placement around the minimap panel is settled (`Icons/map_icons.txt`): **TechTree** top-left, **Score** top-right, **Trade** bottom-left (enabled once a market exists), **Chat** bottom-right. `hud_settings` is spare. Note `act_enter`/`act_garrison` and `act_exit`/`act_leave` are two pairs covering one concept each Ã¢â‚¬â€ decide whether they are distinct actions (board transport vs garrison building) or two takes on one, and reclaim the spares if the latter | mostly closed |
| 5 | **Second pack mirror** Ã¢â‚¬â€ primary is settled: `https://aod.dragoon.co.za/` (Ã‚Â§3.2), unconstrained. A fallback is still unpicked; GitHub Releases is the obvious candidate since the repo is already there. Costs nothing to defer Ã¢â‚¬â€ `packs.json` carries a URL *list* per pack, so adding a mirror is a manifest edit with no client change | before first public build |
| 6 | **Device reach on Compatibility** Ã¢â‚¬â€ confirm the target phone runs it cleanly at 0.1. Known Android driver issues cluster on Mali/MediaTek/Adreno under Vulkan, which is the reason for the Ã‚Â§1 renderer choice | 0.1 |
| 8 | **0 A.D.'s quadruped clips will not transfer onto their own mesh.** Found baking `vis.deer`, which therefore ships **static** for MVP (A.4). Bone names are not the problem Ã¢â‚¬â€ 36 of 37 transfer, 97%. The sizes are: `skeletal/deer_mesh.dae` imports through the Pyrogenesis importer at 0.82 Ãƒâ€” 4.36 Ãƒâ€” 3.70 units, while `quadraped/deer_walk_01.dae`'s own rigged figure imports through Blender's COLLADA importer at 418 Ãƒâ€” 383 Ãƒâ€” **116** units Ã¢â‚¬â€ roughly **31Ãƒâ€” apart**. Pose transforms are stored relative to rest, so every location curve is ~31Ãƒâ€” too large and the mesh tears into spikes; it reads as a broken rig rather than a units error. Both files declare `<unit meter="0.0254" name="inch"/>`, so the two import paths apply the *same* declaration differently. Bipeds are unaffected because their clips declare metres and their two rigs measure identically. **Two dead ends worth not repeating:** bone *length* is not a usable scale metric (the Pyrogenesis importer fabricates near-zero lengths Ã¢â‚¬â€ the actor's longest bone reads 0.050 on a 4-unit model), and comparing bone rest *positions* is swamped by where 0 A.D. parks a clip skeleton, whether measured from the armature origin or from the root bone. The one sound measurement found is the ratio of the two figures' **mesh bounding boxes**. Fix is either to make both import paths honour the declared unit identically, or to scale each action's location F-curves by that ratio Ã¢â‚¬â€ cheap once, and it unlocks every quadruped (deer, boar, sheep, and cavalry mounts later) | A.4 / post-MVP |
| 9 | **The villager is 2.18 m tall Ã¢â‚¬â€ too tall for a woman, and the fix is a recipe override, not a pipeline bug.** Measured directly with `isobake inspect`, which reports raw 0 A.D. units: `units/athenians/female_citizen` is 1.934 Ãƒâ€” 0.871 Ãƒâ€” **4.356** units, and at the pipeline's tile-to-tile factor of 0.5 that is **2.178 m**. The deer is 4.040 units Ã¢â€ â€™ **2.020 m**. So she stands 16 cm *taller than a stag*, which is the wrong way round and is exactly what was flagged by eye at A.4. Note Ã‚Â§2.2's "a citizen measures 3.85" does not match this actor Ã¢â‚¬â€ 3.85 is some other citizen or excludes props, and 4.356 is the measured figure for the one we actually use. `villager.toml` declares no `scale` and no `height_m`, so she simply inherits 0 A.D.'s own proportions, and 0 A.D. authors humans large relative to its tile scale. **The fix is one line:** `height_m` on the recipe, which exists precisely as "the escape hatch for a model that was authored off-scale", plus a rebake of her 960 frames. It does not touch the global `pixels_per_metre` and so cannot disturb any other asset. Open question is only what height to pick Ã¢â‚¬â€ 1.7 m makes her clearly shorter than the stag; 1.75Ã¢â‚¬â€œ1.8 keeps her readable at sprite size on a phone. **Correction:** an earlier version of this item claimed she was baked ~2Ãƒâ€” oversized (3.75 m) and blamed isobake's armature path. That was wrong. It came from back-solving height out of the trimmed sprite bounds, which does not work Ã¢â‚¬â€ a silhouette's topmost pixel sits at no predictable diamond offset, and the same arithmetic predicts 308 px above the anchor for the town centre against a measured 210. **That retraction was itself wrong, and is hereby withdrawn: there *was* an armature bug, and the original ~2x claim was right.** Fixed in `isobake` c540874. A 0 A.D. animation `.dae` is a whole rigged figure, so its imported action keys the armature *object's* `location`, `rotation_quaternion` and `scale` alongside the pose; assigning it reset the pipeline's x0.5 unit conversion to 1.0 and the villager baked at double size. Confirmed by dumping the armature's world scale under the pose (0.5 before the clip was assigned, 1.0 after) and by the re-bake: `idle` sprites went 88 px to 44 px tall, the atlas page 4.98 MB to 1.81 MB, and she now stands comparable to the 50x60 px deer instead of dwarfing the town centre. It stayed hidden because it was uniform -- `idle` runs first and resets the scale, nothing puts it back -- and it only ever manifested once the clips actually played, i.e. after the action-slot fix; before that the armature sat at rest pose and the curves never applied. So the lesson is the opposite of the one recorded here: **`inspect` was the wrong instrument and gave a false all-clear**, because it neither applies scale normalisation nor attaches a clip -- it can only ever report the raw rest pose. What it does measure correctly is the 4.356 raw units / 2.178 m above, so this item's real point stands: she is still 2.178 m and still taller than a stag, and that remains a recipe `height_m` decision | A.3 rebake |
| 7 | **Source-mesh defects carried into the bakes.** Two; (a) is now **FIXED**, (b) remains **accepted as-is for MVP** by explicit decision Ã¢â‚¬â€ they are recorded here so they are chosen rather than forgotten. (a) **Buried geometry, and it is not only buildings.** The town centre hangs 2.7 m of below-ground wall under its ground line, the 3Ãƒâ€”3 rubble 1.8 m, the house 0.7 m ([ASSET_MISSING.md](ASSET_MISSING.md) Ã‚Â§1.2). **DONE** — `isobake` gained `render.ground_clip`, which bisects every mesh at world `z = 0` and discards what is below; the three building recipes set it and were re-baked (town centre 383 to 329 px and 9.48 to 6.70 m, rubble 194 to 146 px, house 221 to 194 px, widths unchanged). Worth knowing it had to be a 3D cut, not a crop of the finished frame: `z = 0` projects to a diamond spanning most of the frame's height, so any horizontal cut deep enough to lose the skirt also loses the front of the building. Also, the burial ran **deeper than the pixel estimates** here suggested (2.53 m under the house, not 0.7) because a skirt directly under a building hides behind its own ground diamond and only the overhang shows. Per the note below this unblocks the better ore sculpts, so that upgrade is now purely an art choice. **A.4 found this is a whole-asset-set problem, not a building one, and that it now costs us art quality rather than just polish.** 0 A.D.'s newer ore sculpts are authored half-sunk into terrain Ã¢â‚¬â€ `gaia/stonemine_round_a_small_01.dae` spans z Ã¢Ë†â€™3.515 to +4.032, so **47%** of the rock is below the ground plane, and the square variants reach **64%**; on a baked sprite the anchor lands mid-pile with 54 of 94 px hanging below it. That set (`metal_<biome>_round|square|small`, 328 verts and a 2048 px texture) is strictly better art than the 68-vert, 128 px old generation we shipped `vis.gold_mine` from, and the *only* thing keeping us on the worse art is this clip. So the fix upgrades the mine, unblocks the better stone-mine and boulder sets, and squares the buildings Ã¢â‚¬â€ treat it as the first item of the post-MVP art pass, not the last. Their engine gets away with it via terrain occlusion plus `<Position><Anchor>pitch-roll</Anchor>`, which is why the source looks fine in-game. (b) **Villager `work_mine` dress distortion:** a dress vertex weighted 100% to `hand_L` in the source mesh drags a fold of fabric when the mining clip's hand pose diverges from the citizen's native poses. Fix is re-weighting that vertex or clamping the vertex group at import. Both are single-pass jobs on the art track and neither blocks a gameplay phase Ã¢â‚¬â€ schedule them together after MVP | post-MVP art pass |

---

## 14. Risk register

| Risk | Severity | Mitigation |
|---|---|---|
| Art production is the long pole | **High** | Placeholders (Ã‚Â§2.4) keep it off the critical path; art track runs async; cheap wins first |
| ~~3DÃ¢â€ â€™iso render pipeline doesn't produce usable sprites~~ | ~~**High**~~ | Ã¢Å“â€¦ **RETIRED.** Proven on a grass tile, an oak and an 11-animation, 960-frame citizen. (The 0.9 claim of a "240-frame animated citizen" was wrong in a way nothing caught until now: every clip was silently rendering rest pose, see the action-slot risk below.) The Widelands / Unknown Horizons fallbacks are no longer needed |
| **Blender 5.x silently breaks the pipeline** Ã¢â‚¬â€ COLLADA import was removed in 5.0 and 0 A.D. ships `.dae` | **High** | Hard-pin **4.5 LTS** (Ã‚Â§1.3), supported to Jul 2027. Do not let an auto-update move it. A community 5.x `.dae` importer exists but is unvetted |
| ~~Animation import is a manual step~~ | ~~Medium~~ | Ã¢Å“â€¦ **RETIRED at 0.9.** `isobake` attaches the clips itself, and transfer is by bone name with no retarget rig Ã¢â‚¬â€ a gatherer clip drives 83 of an actor's 102 bones; the 19 it misses are prop attach points that follow their parents |
| ~~Animation-variant props are not imported~~ | ~~Medium~~ | Ã¢Å“â€¦ **RETIRED.** `isobake`'s zeroad adapter now reads a variant's `<props>` alongside its `<animations>` and constrains the prop mesh to the armature's `prop_<attachpoint>` bone, visible only while that clip plays. The villager now chops holding her axe and carries wood at her hip; `villager.toml` moved to `directions = 8` accordingly (Ã‚Â§2.5) |
| ~~Every animation silently rendered rest pose~~ | ~~**High**~~ | Ã¢Å“â€¦ **RETIRED.** Blender Ã¢â€°Â¥4.4's layered-action system needs `animation_data.action_slot` set explicitly; `isobake` was only ever setting `.action`, so no curve in any clip drove anything, and it looked fine because nothing was checked against a moving reference. Fixed in `render_impl.py`. This is why villager frame counts and canvas size both changed after 0.9 Ã¢â‚¬â€ the frozen renders never exercised real motion range |
| **0 A.D. clips bake in absolute root-bone motion** Ã¢â‚¬â€ a gather clip's hip can drift over a metre from wherever the animator placed the character, well past what a fixed camera anchored on world (0,0,0) can frame | Medium | `render_impl.py` cancels the root bone's horizontal (X/Y) drift every frame, holding it at its rest-pose position; vertical motion (a fall, a crouch) is left alone since that is the real, wanted signal |
| **Quadruped animations do not transfer onto their own mesh** Ã¢â‚¬â€ the clip files and the mesh file describe one skeleton ~31Ãƒâ€” apart, so location curves overshoot and the mesh tears | Medium | Measured at A.4 (Ã‚Â§13.2 item 8). `vis.deer` ships **static** for MVP, which costs nothing on the MVP path Ã¢â‚¬â€ 6.1a only needs a huntable food node, and roaming is 6.1b Ã¢â‚¬â€ but leaves the gatherable carcass without art. Bipeds are unaffected and independently verified: the villager's two rigs measure identically |
| **0 A.D. building meshes carry a skirt below `z = 0`** for the terrain to hide, and a baked sprite has no terrain to hide it | Low | Measured at A.2 on three of six: the town centre buries **2.7 m** (52 px below the ground line), the 3Ãƒâ€”3 rubble 1.8 m, the house 0.7 m; both foundations and the civic-centre ruin are clean. Confirmed as buried geometry rather than an off-centre footprint by rendering at 0Ã‚Â° and 180Ã‚Â° and watching the excess stay below the anchor both times. Cosmetic, **accepted for MVP** Ã¢â‚¬â€ tracked as Ã‚Â§13.2 item 7, where one ground clip at `z = 0` in `isobake` fixes the whole class including every building added later |
| **A source-mesh vertex-weight quirk distorts `work_mine`** Ã¢â‚¬â€ a dress vertex is weighted 100% to `hand_L`, and the mining clip's hand pose is far enough from the citizen's native poses that it drags a fold of fabric with it | Low | Isolated to one clip, cosmetic, **accepted for MVP** Ã¢â‚¬â€ tracked as Ã‚Â§13.2 item 7 alongside the buried building skirts, since both are source-mesh defects fixed in one post-MVP art pass. Fix is either re-weighting that vertex or clamping the offending vertex group at import time |
| 0 A.D. actors don't map cleanly to a medieval-fantasy roster | Medium | Hand-pick the actorÃ¢â€ â€™`vis.*` mapping (Ã‚Â§13.2 item 2); some entities may need bespoke art |
| Accidentally shipping an unlicensed asset | Medium | `licence_audit.py` + `LICENCES.md` from 0.2c Ã¢â‚¬â€ but run manually, so the mitigation is only as good as the habit until CI exists (Ã‚Â§1.2) |
| CC-BY-SA attribution missed | Medium | `CREDITS.md` + in-game Credits screen from 1.4; per-pack licence files |
| Pathfinding stalls at scale | Medium | Per-tick path budget from day one; flow fields in reserve |
| GDScript too slow at 200 units | Medium | Measure on device from 0.7; targeted GDExtension only if proven |
| Mobile thermal throttling | Medium | 10 Hz sim, pooled views, draw-call budget, sustained-load testing |
| Asset pack download fails / user offline | Medium | Game runs on placeholders; packs are `required: false` |
| ~~Per-frame anchor jitter~~ | ~~Medium~~ | Ã¢Å“â€¦ **ELIMINATED at 0.9**, not mitigated. Anchors come from the projected world origin, which is a constant for a fixed camera and a subject rotating about world Z, so there is nothing left to jitter (Ã‚Â§9.1) |
| WSL/Docker fighting Android USB deploy | Low | Ã‚Â§1.2 Ã¢â‚¬â€ native Windows for editor + deploy |
| Scope creep | **High** | The `[MVP]` tag is a hard gate; Ã‚Â§12 governs after |

---

## 15. Immediate next actions

1. **Create the Godot 4.x project at `game/` and deploy an empty landscape scene to a physical Android device** (0.1). Before any gameplay code, natively on Windows.
2. **Build the asset seam + placeholder renderer** (0.2a/0.2b) Ã¢â‚¬â€ makes every gameplay phase independent of art.
3. **Stand up `SimWorld` + `SimClock` headless** with a passing test that ticks an empty world (0.5).
4. **Wire `host_solo()` and get one placeholder villager moving on a tap**, end to end through the loopback network (0.6). Once that works the architecture is proven and the rest is content.
5. **Prove the 0 A.D. render pipeline on a single unit** (0.9) before scheduling A.3.
