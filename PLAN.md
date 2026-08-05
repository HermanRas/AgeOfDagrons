# AOD — Implementation & Programming Plan

Companion to [IDEA.md](IDEA.md) (what we're building) and [UI_Design.md](UI_Design.md) (how it looks).
This document is **how we build it**: architecture, objects, functions, scenes, and phase order.

Missing-asset tracking lives in [ASSET_MISSING.md](ASSET_MISSING.md).

---

## 0. How to read this document

- Phases tagged **`[MVP]`** are implemented first. Nothing untagged is written until every `[MVP]` item is done, tested, and working on a physical Android device.
- Untagged items are full-scope scaffolding — they exist so we don't design ourselves into a corner.
- After MVP, phases are chosen by the impact/effort table in §12.
- Phase numbers ≥1 mirror [IDEA.md](IDEA.md). Phase 0.x is engineering groundwork with no IDEA.md counterpart.

---

## 1. Locked decisions

| Decision | Choice |
|---|---|
| Engine | **Godot 4.7.1-stable** (`Godot_v4.7.1-stable_win64`) |
| Language | **GDScript** |
| Renderer | **Compatibility** (`gl_compatibility`), 2D — *not* the Mobile renderer. Vulkan-Mobile driver crashes cluster on older Mali/MediaTek/Adreno parts, and the Mobile renderer supports **fewer** Android devices ([godot#111729](https://github.com/godotengine/godot/issues/111729)) for no 2D benefit |
| Orientation | Landscape, locked |
| Licence | **Open source. Art under CC-BY-SA 3.0** (§2.2) |
| Session model | **Always client–server, even solo** (§1.1) |
| Simulation | Server-authoritative, fixed-tick, headless-capable |
| Sim tick rate | **10 Hz** (100 ms), render interpolated to display rate |
| Map topology | **Square grid**, rendered isometric |
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

### 1.2 Development environment

**Native Windows** for the Godot editor and Android deploys. Android USB `adb` from WSL2 requires `usbipd-win` passthrough and is unreliable; one-tap deploy to a physical device is a core habit (§15).

**WSL2 + Docker** for:
1. The Python asset pipeline (`tools/`) — pinned dependencies, reproducible.
2. The headless dedicated server (Phase 12.1) — also verifies the `sim/` boundary held.
3. CI — headless sim tests, boundary check, `licence_audit.py`.

Source lives on the Windows filesystem. Containers bind-mount it; never use Docker volumes for source.

### 1.3 Machine setup

**Working root for anything outside Google sync:** `C:\Users\herman.ras\Downloads\AOD_game\`

```
C:\Users\herman.ras\Downloads\AOD_game\
├── art_source\        # 0 A.D. art repo/checkout — large, never synced, never committed
├── art_work\          # Blender scenes, render output, intermediate frames
├── packs\             # built .pck files staged for website upload
└── tools_env\         # Python venv for tools/
```

The Godot project stays in the Drive folder for now (`AOD_Mobile\game\`) but **should move to a local path at clean init** — a git repo inside Drive sync is what corrupted the last `.git`, and GitHub is the correct backup for an open-source project.

| Requirement | Version / notes | Status |
|---|---|---|
| **Godot** | `4.7.1-stable_win64` (current stable, released 14 Jul 2026) | ✅ installed |
| **Android export** | Godot's Android build template + JDK 17 + Android SDK (platform-tools for `adb`). The editor installs most of it — verify at 0.1 | needed for 0.1 |
| **Python** | 3.11+ with `Pillow` — venv in `tools_env\` | needed for 0.3 / 0.9 |
| **Blender** | **4.5 LTS — hard pin, do not use 5.x.** COLLADA (`.dae`) import was *removed* in Blender 5.0 and 0 A.D.'s meshes are `.dae`. 4.5 LTS is the last version with it (supported to Jul 2027) | needed for 0.9 |
| **Blender addon** | [`StanleySweet/blender_pyrogenesis_importer`](https://github.com/StanleySweet/blender_pyrogenesis_importer) (GPL-2.0) — imports 0 A.D. actor XML, resolving mesh + props + textures. **Does not import animations**; those load separately from `art/animation/*.dae` onto the armature | needed for 0.9 |
| **0 A.D. art** | `git clone --depth 1 https://gitea.wildfiregames.com/0ad/0ad.git` into `art_source\`. **Shallow clone matters** — full history is ~8.3 GB | needed for 0.9 |
| **git** | 2.47.1 | ✅ installed |
| **Test framework** | **Custom `TestCase`/`run_tests.tscn` harness** (built 0.1–0.7), kept instead of GdUnit4 — already covers headless tests, `state_hash()`, replays and the `sim/` boundary check with zero dependencies. GdUnit4 remains an option later if a real need (parallel execution, richer reporting) shows up | done at 0.7 |

Notes on the 0 A.D. checkout:

- Art lives **in the main repo** at `binaries/data/mods/public/art/` — there is no separate art repo to fetch.
- **Clone the repo; do not mine the game installer.** Releases ship a built `public.zip` where `.dae`→`.pmd`/`.psa` and `.png`→`.dds`. Those compiled formats have no maintained Blender importer.
- GitHub `0ad/0ad` is **archived** (Sept 2024) — browsable and useful for reference, but frozen. Gitea is upstream.

Nothing in this table blocks phases 0.1 or 0.5 — the Blender/0 A.D. items only gate the art track.

**Version policy: every version above is pinned.** Upgrading Godot or Blender is a deliberate task at a phase boundary with the test suite green before and after — never an "update available" click. Mid-project engine drift costs more debugging time than any newer release saves. If an upgrade is taken, record it here in the same change.

---

## 2. Art & assets

### 2.1 The asset seam

**Every visual and audio asset sits behind a stable ID. No filename appears in gameplay code.**

```gdscript
var vis := GameDataRegistry.atlas_for(&"vis.villager")
AudioManager.play_sfx(&"villager.chop")
```

`data/visuals.json` and `data/audio.json` are the only files mapping an ID to a path. Each ID resolves to a real atlas **or** a procedural placeholder (§2.4), so gameplay never blocks on art.

### 2.2 Sources

| Domain | Source | Licence |
|---|---|---|
| Units, buildings, terrain, props | **0 A.D.** (`play0ad.com`) | CC-BY-SA 3.0 |
| Audio (starting point) | **0 A.D.** | CC-BY-SA 3.0 |
| UI chrome, fonts | **itch.io packs** already in `UI_Sprites/` — `UI_dragon-huds`, `uı-fonts`, `Free_Medieval_Fantasy_UI_Pack` | Per-pack; record in `LICENCES.md` |
| Dragon + nest | **Bespoke** — commissioned or hand-drawn | Ours |

0 A.D. is a 3D game; `tools/render_3d_to_iso.py` renders its models to 8-direction sprite sheets. Terrain comes from the same source — its ground textures are tileable, so the same Blender scene renders them to isometric tiles at the project camera angle. Single source keeps palette and style coherent and keeps attribution to one entry.

Repo layout we consume (`binaries/data/mods/public/`):

| Path | Contents |
|---|---|
| `art/meshes/{skeletal,structural,props,gaia,flora}` | `.dae` COLLADA meshes |
| `art/animation/{biped/{citizen,infantry,gatherer,…},quadraped,mechanical}` | `.dae` animations — note `biped/gatherer`, directly relevant to the villager |
| `art/textures/skins/…` | mostly `.png`, some `.dds` |
| `art/actors/{units,structures,fauna,flora,props}` | XML tying mesh + textures + animations + props together, grouped into variants |
| `audio/{actor,ambient,attack,interface,music,resource,voice}` | `.ogg` + XML descriptors |

Pipeline shape: **actor XML → Blender (via the pyrogenesis importer) → attach animation `.dae` → render 8 × 45° orthographic → `bake_sprites.py`.** The importer resolves meshes/textures/props but not animations, so attaching animations is our script's job.

No prior art exists for 0 A.D.→2D sprite conversion. [`Maghwyn/blender_directional_spritesheets`](https://github.com/Maghwyn/blender_directional_spritesheets) (MIT) is the best reference for the rotation loop; expect to write our own ~150-line script rather than adopt one.

**The GUI stays the dragon theme** from the itch.io packs. It does not come from 0 A.D.

Any additional source is added only on an explicit note from the project owner, and must be recorded in `LICENCES.md` and `CREDITS.md` at the same time.

### 2.3 Attribution obligations

0 A.D.'s `art/LICENSE.txt` and `audio/LICENSE.txt` require **three specific things** in the attribution. All three, verbatim:

1. A link to `http://creativecommons.org/licenses/by-sa/3.0/`
2. The original author named as **"Wildfire Games"**
3. A link to `http://www.wildfiregames.com/`

Plus:

- **Derived sprite sheets are themselves CC-BY-SA 3.0.** Our rendered output ships under that licence. Our *Godot code* may keep its own licence — only the art is copyleft.
- **`CREDITS.md`** — in-repo and surfaced in-game on a Credits screen (phase 1.4).
- **`assets/LICENCES.md`** — per-asset provenance. `tools/licence_audit.py` fails CI on any shipped asset not listed.
- Downloadable asset packs (§3.2) each carry their own `LICENCE` and `CREDITS` file inside the pack.
- Note: some of 0 A.D.'s `textures/` derive from CGTextures under special permission granted to that project. Worth a check before leaning heavily on raw texture files rather than rendered output.

### 2.4 Placeholder art

MVP ships on procedurally generated placeholders: isometric diamonds for terrain, capsules with a facing marker for units, sized rectangles for buildings — drawn at runtime from `visuals.json`, no image files.

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
| `idle` | Task.IDLE | **✓** |
| `walk` | moving, carrying nothing | **✓** |
| `walk_carry_wood` | moving, `carry_kind == wood` | **✓** |
| `walk_carry_gold` | moving, `carry_kind == gold` | **✓** |
| `walk_carry_food` | moving, `carry_kind == food` | **✓** |
| `walk_carry_stone` | moving, `carry_kind == stone` | |
| `work_chop` | gathering wood | **✓** |
| `work_mine` | gathering gold or stone | **✓** |
| `work_hunt` | gathering from a carcass | **✓** |
| `work_build` | building or repairing | **✓** |
| `work_forage` / `work_farm` / `work_fish` / `work_herd` | later food sources | |
| `attack` | combat | |
| `die` | death | **✓** |
| `decay` | corpse, pre-removal | **✓** |

Convention: **5 stored directions, mirrored to 8.** Halves art cost.

`EntityView.play_anim()` tries `walk_carry_<kind>` and falls back to `walk`, so carry variants are always optional.

**MVP villager budget:** 11 animations × ~15 frames × 5 directions ≈ 825 frames.

### 2.6 Practical handling

- Raw source art lives on a **local, non-synced** path — never in this Drive-synced project folder. The bake manifest points at it via a config value, never a committed absolute path.
- Only baked atlases are committed, and only placeholders ship inside the APK (§3.2).
- `.gdignore` in any raw-art folder under the project.

---

## 3. Target platforms & delivery

| Target | Priority | Notes |
|---|---|---|
| Android (mid-range) | **Primary** | The design constraint — see §3.0 for the measured reference device |
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
| ABI | `arm64-v8a` **only** — no 32-bit target needed |
| Screen | 2600 × 1200, 520 dpi, 60 Hz |
| Renderer confirmed active | `gl_compatibility` / `opengl3` |
| Empty-scene FPS | 60 (capped by refresh rate) |

Two consequences worth designing around:

1. **MediaTek + Mali is exactly the hardware the Compatibility decision (§1) was made for.** Known Godot Vulkan crashes cluster on MediaTek and Mali parts, so this device would have been a poor Vulkan-Mobile target. The renderer choice is now empirically validated rather than argued.
2. **The screen is 2600 × 1200 — a 2.17:1 aspect, far wider than 16:9.** With `stretch/aspect=expand` the design viewport resolves to **1404 × 648**. So UI is authored against a **648 px tall** canvas with variable width. Both HUD edges have generous horizontal room but vertical space is tight — relevant to [UI_Design.md](UI_Design.md) and to IDEA 9.2's note about placing the age progress bar below the age indicator on narrow screens.

### 3.1 Performance budget

| Metric | Target |
|---|---|
| Frame time | 16.6 ms (60 fps); hard floor 33 ms (30 fps) |
| Sim tick cost | < 5 ms per 100 ms tick |
| Live units (MVP) | 50 |
| Live units (full scope) | 200 per player, 8 players |
| Draw calls | < 200 |
| Texture memory | < 256 MB |
| **APK size** | **< 300 MB** — code + placeholders only |
| Asset pack (art) | ~150–400 MB, downloaded |
| Asset pack (audio) | ~50–100 MB, downloaded |

Measured baseline: an **empty** project exports to **54 MB** (arm64-v8a), essentially all engine binary. The 300 MB ceiling leaves real headroom while art and audio still ship as downloadable packs (§3.2).

Checked by `StressTest.tscn` (0.7) from early on, not at the end.

### 3.2 Asset delivery — downloadable packs

Art and audio are **not bundled in the APK**. They ship as Godot `.pck` files mounted at runtime via `ProjectSettings.load_resource_pack()`, which is the engine-native mechanism for exactly this.

```
APK  (< 60 MB)   = code + data JSON + procedural placeholders + fonts
pack_art_v1.pck  = atlases, terrain
pack_audio_v1.pck = sfx, music
pack_theme_*.pck  = optional community themes (later)
```

**Sources, in priority order:**
1. **Project website (primary)** — no size limit, 100 Mbps
2. Additional mirror (to be chosen; GitHub Releases is one candidate)
3. Any user-added source URL (enables custom themes later)

The pack manifest carries a URL list per pack, so adding or reordering mirrors is a manifest edit with no client change.

**Flow:** boot → check local pack versions against a manifest → download missing/outdated → verify checksum → `load_resource_pack()` → assets resolve through the seam (§2.1). If a pack is absent or fails verification, **the game runs on placeholders** rather than failing. That fallback is the whole reason placeholders stay in the build permanently.

```jsonc
// packs.json — served from the project website, mirrored later
{
  "manifest_version": 1,
  "packs": [
    { "id": "art",   "version": "1.0.0", "size": 312000000,
      "sha256": "…", "required": false,
      "urls": ["https://<website>/packs/pack_art_v1.pck"] }
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
├── IDEA.md
├── PLAN.md
├── UI_Design.md
├── ASSET_MISSING.md            # every asset still needed, MVP + end state
├── CREDITS.md                  # CC-BY-SA attribution, surfaced in-game
├── UI_Sprites/                 # licensed UI packs (+ .gdignore)
├── insperation_pictures/       # reference (+ .gdignore)
├── tools/                      # OFFLINE pipeline — Python, never shipped
│   ├── render_3d_to_iso.py     # Blender: 0 A.D. model -> 8-dir sprite sheet
│   ├── bake_sprites.py         # frames -> trimmed, packed atlas + JSON
│   ├── bake_terrain.py         # tileable texture -> iso tile set
│   ├── verify_atlas.py         # contact sheet for eyeballing a bake
│   ├── build_packs.py          # atlases -> .pck + manifest + checksums
│   └── licence_audit.py        # every asset must declare a licence
└── game/                       # THE GODOT PROJECT
    ├── project.godot
    ├── data/
    │   ├── units.json
    │   ├── buildings.json
    │   ├── resources.json
    │   ├── techs.json
    │   ├── ages.json
    │   ├── factions.json
    │   ├── visuals.json        # ASSET SEAM — id -> atlas or placeholder
    │   └── audio.json          # ASSET SEAM — id -> sound
    ├── assets/
    │   ├── placeholders/       # ships in APK
    │   ├── ui/                 # ships in APK
    │   ├── fonts/              # ships in APK
    │   └── LICENCES.md         # per-asset provenance, enforced by CI
    ├── src/
    │   ├── sim/                # NO Godot node types, NO rendering
    │   │   ├── sim_world.gd
    │   │   ├── sim_map.gd
    │   │   ├── sim_player.gd
    │   │   ├── entities/
    │   │   ├── systems/
    │   │   ├── commands/
    │   │   └── pathing/
    │   ├── net/
    │   ├── view/
    │   ├── ui/
    │   ├── ai/
    │   └── autoload/
    ├── scenes/
    │   ├── boot/
    │   ├── menu/
    │   ├── game/
    │   └── ui/
    ├── tests/                  # headless — see §7.7
    │   ├── run_tests.tscn      # CI entry point
    │   ├── run_tests.gd        # discovers/runs test_*.gd, sets exit code
    │   ├── sim/                # SimWorld, systems, commands
    │   ├── net/                # Net, SimHost
    │   ├── view/               # Iso, EntityViewPool, GameView
    │   └── replays/            # recorded command logs used as regression fixtures
    └── addons/                 # GUT or GdUnit4
```

**The `game/src/sim/` boundary is the most important rule in this codebase.** Nothing in `sim/` may `extends Node`, load a texture, read input, or reference `view/`. CI greps for violations (0.7).

---

## 5. Architecture overview

```
┌────────────────────────────────────────────────────────────┐
│  VIEW (client)   scenes, sprites, camera, HUD, gestures    │
│  reads snapshots ──┐            ┌── emits Commands         │
└────────────────────┼────────────┼──────────────────────────┘
                     │            │
              snapshots (down)   commands (up)
                     │            │
┌────────────────────┼────────────┼──────────────────────────┐
│  NET             SceneMultiplayer / ENetMultiplayerPeer    │
│  host binds 127.0.0.1 (solo) or 0.0.0.0 (multiplayer)      │
└────────────────────┼────────────┼──────────────────────────┘
                     │            │
┌────────────────────▼────────────▼──────────────────────────┐
│  SIM (server only, headless-capable, 10 Hz fixed tick)     │
│  SimWorld -> systems -> entities. Plain GDScript classes.  │
└────────────────────────────────────────────────────────────┘
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

## 6. Core objects — API reference

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

# src/autoload/asset_packs.gd    — see §3.2                    [MVP]
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
| `DeathSystem` | HP≤0 → corpse, free tiles, drop cargo, corpse timer | **[MVP]** |
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
| `ResignCommand` | — | |

#### Pathfinding

```gdscript
# src/sim/pathing/path_service.gd                               [MVP]
class_name PathService
func rebuild(map: SimMap) -> void                                # [MVP]
func set_tile_blocked(t: Vector2i, blocked: bool) -> void         # [MVP]
func find_path(from: Vector2i, to: Vector2i, domain: int) -> PackedVector2Array  # [MVP]
func nearest_reachable(from: Vector2i, to: Vector2i, domain: int) -> Vector2i     # [MVP]
func request_async(from, to, domain, callback: Callable) -> int    # budgeted queue

# src/sim/pathing/flow_field.gd     — scale-up only
class_name FlowField
func build(goal: Vector2i, map: SimMap, domain: int) -> void
func direction_at(t: Vector2i) -> Vector2i
```

`AStarGrid2D` wrapped by `PathService`, with a **per-tick pathfinding budget** — at most N requests solved per tick, rest queued. Prevents the stall where dozens of units re-path on one frame. Local unit-vs-unit avoidance is steering-based off the spatial hash; the sim has no physics engine.

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

# src/view/selection.gd — client-side only, never sent           [MVP]
class_name Selection
func set_selection(ids: Array[int]) -> void                      # [MVP]
func add(ids: Array[int]) -> void                                # [MVP]
func select_in_rect(rect: Rect2i) -> void                        # [MVP]
func select_same_type_onscreen(id: int) -> void                  # [MVP]
func current() -> Array[int]                                     # [MVP]

# src/view/iso.gd — the ONLY place grid<->screen math lives      [MVP]
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
# children wire to EventBus signals — no polling

# src/ui/selection_panel.gd   [MVP]  SingleUnitView / BuildingView / MultiSelectView
# src/ui/action_panel.gd      [MVP]  context-sensitive actions
# src/ui/resource_bar.gd      [MVP]  5 counters incl. idle/total villagers
# src/ui/minimap.gd           [MVP]  circular, 4 corner buttons
# src/ui/control_groups.gd    [MVP]  5 slots, icon = most-represented type
# src/ui/download_screen.gd   [MVP]  asset pack progress (§3.2)
# src/ui/credits_screen.gd    [MVP]  CC-BY-SA attribution (§2.3)
# src/ui/age_header.gd
# src/ui/tech_tree_screen.gd
# src/ui/market_screen.gd
# src/ui/chat_overlay.gd
```

---

## 7. Cross-cutting concerns

### 7.1 Selection vs commands
Selection is client-side UI state, never sent to the server. Only the resulting `Command` (with explicit `unit_ids`) crosses the wire — selection stays instant regardless of latency.

Control groups are the exception: they're **persisted in `SimPlayer`** via `SetControlGroupCommand` so they survive reconnect and are available to a rejoining client.

### 7.2 Snapshots
Per-player, fog-filtered, delta-encoded against the last acknowledged tick. Full snapshot on join or after loss. Format `{tick, spawned[], updated[], removed[], player_state}`.

### 7.3 Rendering
`Sprite2D` in a Y-sorted container for MVP. If profiling at 200+ units shows Y-sort dominating, switch to explicit depth keys via `Iso.depth_sort_key()` and `RenderingServer` canvas items. Measure at 0.7 scale before changing anything.

### 7.4 Mobile input
All gestures funnel through `InputRouter`. Mouse emulation **disabled** — multi-touch box select needs raw `InputEventScreenTouch`/`Drag`. Test on device from 0.1.

### 7.5 Audio
`AudioManager` exists from MVP with a no-op implementation and a stable ID vocabulary, so gameplay emits `play_sfx(&"villager.chop")` from day one and the audio pack lands later.

### 7.6 Optimisation policy
GDScript everywhere. Profile on the target Android device. Move a hot loop to GDExtension only when profiling proves it dominates.

### 7.7 Testing

Four distinct layers, deliberately — most of the value is in the first one.

**1. Headless sim tests (the important layer).**
Because `src/sim/` is plain GDScript with no `Node`, no textures, and no input, it can be tested with no window and no rendering. This is the payoff of the §1.1 architecture and it's why the boundary rule is enforced by CI.

```
godot --headless --path game/ res://tests/run_tests.tscn
```

The runner (`run_tests.gd`) is a Node under that minimal scene, not a `--script`
`SceneTree` override. A custom `--script` MainLoop skips the normal main-scene
boot sequence that parents autoload singletons under the tree root, which
silently breaks anything needing `get_tree()`/`get_multiplayer()` -- discovered
building 0.6's `Net` autoload. A real scene, even headless, boots exactly like
the shipped game does.

Exit code 0 = pass, non-zero = fail, so CI needs nothing else. Test shape:

```gdscript
# spawn a world, queue commands, step N ticks, assert on state
var w := SimWorld.new()
w.setup(MatchConfig.debug_single_player())
var v := w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
w.queue_command(MoveCommand.new(1, [v.id], Vector2i(10, 5)))
for i in 60: w.step()
assert_eq(v.tile(), Vector2i(10, 5), "villager reached target in 60 ticks")
```

No scene required — which answers "what do I need to test?": for sim tests, **nothing but the script**.

**2. Framework — GdUnit4** (MIT). It lists explicit 4.7.1 compatibility and ships a first-party GitHub Action, which makes it the lower-risk pick on a brand-new engine release.

```
addons\gdUnit4\runtest.cmd -a res://tests -c -rd res://reports
```

Exit 0 = pass, 100 = failures, 101 = warnings. Linux CI additionally needs `xvfb-run --auto-servernum` and `--audio-driver Dummy`.

*(GUT is the alternative — also MIT, but take its 9.7.x line for 4.7; `main` tracks 4.6.)*

**3. `state_hash()` regression.** Run the same `MatchConfig` + command log twice, compare hashes. Catches accidental non-determinism and any state the snapshot layer forgets to serialise.

**4. Replays.** `MatchConfig` + ordered command log = a few KB that reproduces any bug exactly. Also the manual-testing tool: record a session on the phone, replay it headless on the desktop to debug.

**5. `StressTest.tscn`** — the only layer needing a real scene. Spawns N units, reports frame and tick timings against §3.1. This one must run **on the phone**, not the desktop.

**What is testable when:** nothing meaningful until 0.5 (`SimWorld` exists). Before that, tests have no subject — 0.1 is verified by a scene visibly running on a physical device, not by assertions.

---

## 8. Scene trees

```
Boot.tscn                    [MVP]
└── Boot (boot.gd)           # load data, check/mount asset packs, route to menu

MainMenu.tscn                [MVP]
└── MainMenu (Control)
    ├── Background (TextureRect)
    ├── Title
    └── VBox: PlayBtn, MultiplayerBtn, SettingsBtn, CreditsBtn, QuitBtn

Match.tscn                   [MVP]
└── Match (match.gd)
    ├── SimHost (sim_host.gd)         # server only; owns SimWorld
    ├── GameView (Node2D)
    │   ├── TerrainLayer (TileMapLayer)
    │   ├── StaticsLayer (Y-sorted)   # buildings, trees, mines
    │   ├── UnitsLayer (Y-sorted)     # units, wildlife
    │   ├── OverlayLayer              # selection rings, ghost, health dots
    │   ├── FogLayer
    │   └── CameraRig (Camera2D)
    ├── InputRouter
    └── HUD (CanvasLayer)
        ├── ControlGroups   (top-left)      [MVP]
        ├── AgeHeader       (top-centre)
        ├── ResourceBar     (top-right)     [MVP]
        ├── SelectionPanel  (bottom-left)   [MVP]
        │   ├── ActionSubPanel
        │   └── QueueSubPanel
        └── MinimapPanel    (bottom-right)  [MVP]

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
    "hp": 2000, "footprint": [4, 4], "los": 8,
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

```jsonc
// generated by tools/bake_sprites.py — the only place filenames appear
{
  "vis.villager": {
    "atlas": "res://assets/atlases/villager.png",
    "directions": 5, "mirror_for_8": true,
    "anims": {
      "idle":       { "row": 0,  "frames": 15, "fps": 8  },
      "walk":       { "row": 1,  "frames": 15, "fps": 15 },
      "work_chop":  { "row": 2,  "frames": 15, "fps": 12 },
      "work_mine":  { "row": 3,  "frames": 15, "fps": 12 },
      "work_build": { "row": 4,  "frames": 15, "fps": 12 },
      "die":        { "row": 5,  "frames": 15, "fps": 10 },
      "decay":      { "row": 6,  "frames": 5,  "fps": 2  },
      "walk_carry_wood": { "row": 7, "frames": 15, "fps": 15 },
      "walk_carry_gold": { "row": 8, "frames": 15, "fps": 15 },
      "walk_carry_food": { "row": 9, "frames": 15, "fps": 15 }
    },
    // anchors are PER FRAME — frames trim to varying sizes, so one anchor
    // per animation causes visible jitter. Bottom-centre of content bbox.
    "anchors": [[22,48],[22,48],[23,49]]   // one [x,y] per packed frame
  }
}
```

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

### Phase 0 — Foundation

| # | Item | Tag |
|---|---|---|
| 0.1 | ✅ **DONE** — Godot 4.7.1 project, Compatibility renderer, landscape lock, folder skeleton, Android export, **deployed and verified on a physical device**. Renderer, orientation, raw touch, touch→viewport coordinate mapping and 60 fps all confirmed on hardware (§3.0) | **[MVP]** |
| 0.2a | Asset seam: `data/visuals.json` + `data/audio.json`, `atlas_for()` resolving to atlas or placeholder | **[MVP]** |
| 0.2b | Procedural placeholder renderer (§2.4) | **[MVP]** |
| 0.2c | `licence_audit.py` + `assets/LICENCES.md` + `CREDITS.md`; CI fails on undeclared assets | **[MVP]** |
| 0.3 | `AssetPacks` autoload: manifest check, download, checksum verify, `load_resource_pack()`, `DownloadScreen` (§3.2) | **[MVP]** |
| 0.4 | `GameDataRegistry` + JSON schemas + `*Def` classes; hand-enter the ~6 MVP entities | **[MVP]** |
| 0.5 | ✅ **DONE** — Sim skeleton: `SimWorld`, `SimClock`, `SimEntity`/`SimUnit`, `SimSystem` (`CommandSystem`/`TaskSystem`/`MovementSystem`), `Command` (`MoveCommand`/`StopCommand`), `SpatialHash`. Straight-line movement only -- no map/pathfinding until 2.1. Verified headless: 9/9 tests, exit 0 | **[MVP]** |
| 0.6 | ✅ **DONE** — `Net` autoload: `host_solo()` (real ENet server bound to 127.0.0.1), `submit_command()`/`_recv_command` RPC up, `SnapshotSystem` + `_recv_snapshot` RPC down; `SimHost` owns the server-side `SimWorld`, driven by `SimClock`. View layer: `Iso`, `EntityView`/`EntityViewPool` (pooled, interpolated), `GameView.apply_snapshot()`. `host_open()`/`join()` (remote multiplayer) deferred -- out of MVP scope (§10). Verified headless: 22/22 tests, exit 0 | **[MVP]** |
| 0.7 | ✅ **DONE** — `SimWorld.state_hash()` + regression tests, `Replay` (record/play, JSON round trip), `sim/` boundary check (as a headless test, not a separate Python grep — one CI command), `StressTest.tscn` (50 units through the real `host_solo()` path; desktop run: 0.48/0.04/2.15 ms tick cost, 60/45/61 fps, 59 draw calls — on-device numbers still needed). GdUnit4 deliberately not adopted (see §1.3). 29/29 tests, exit 0 | **[MVP]** |
| 0.8 | `.gdignore` in raw-art folders; document the non-synced art_source path (§2.6) | **[MVP]** |
| 0.9 | `render_3d_to_iso.py` + `bake_sprites.py` + `verify_atlas.py` + `build_packs.py` — proven end-to-end on one unit | **[MVP]** |

### Phase 1 — Main menu *(IDEA phase 1)*

| # | Item | Tag |
|---|---|---|
| 1.1 | Placeholder buttons: PLAY, MULTIPLAYER, SETTINGS, CREDITS, QUIT; dragon-HUD skin + fonts | **[MVP]** |
| 1.2 | PLAY → `host_solo()` → `Match.tscn` | **[MVP]** |
| 1.3 | Splash/boot screen | **[MVP]** |
| 1.4 | Credits screen (§2.3) | **[MVP]** |
| 1.5 | Settings screen | |
| 1.6 | Lobby: host/join, map & faction & win-condition pick | |

### Phase 2 — Map *(IDEA phase 2)*

| # | Item | Tag |
|---|---|---|
| 2.1 | `SimMap` grid: terrain, move cost, occupancy, passability by domain | **[MVP]** |
| 2.2 | Domain rules — land only in MVP | **[MVP]** (land) |
| 2.3 | Resource-node and building placement into the grid | **[MVP]** |
| 2.4a | Small fixed debug map, one start position, placeholder terrain | **[MVP]** |
| 2.4b | Procedural generator, 2–8 players, size scales with player count | |
| 2.5 | Fog of war: `VisionSystem` + server-side snapshot filtering + `FogLayer` | |
| 2.6 | Starting conditions: 1 Town Centre + 5 villagers per player | **[MVP]** |
| 2.7 | Real terrain tileset (art track A.1) | |

### Phase 3 — Camera & world view *(IDEA phase 3)*

| # | Item | Tag |
|---|---|---|
| 3.1 | Isometric render of the grid; `Iso` math; Y-sorted layers | **[MVP]** |
| 3.2 | Zoom: edge swipe up/down | **[MVP]** |
| 3.3 | Pan: drag/swipe, clamped to map bounds | **[MVP]** |
| 3.4 | Double-tap minimap → centre on own Town Centre | **[MVP]** |
| 3.5 | Camera follow selected unit | |
| 3.6 | Tap world to move selected units | **[MVP]** |
| 3.7 | Tap minimap to move selected units | |
| 3.8 | Tap minimap (nothing selected) → move camera | **[MVP]** |

### Phase 4 — Units *(IDEA phase 4)*

| # | Item | Tag |
|---|---|---|
| 4.1 | `MoveCommand` → task/movement systems; stop at nearest reachable tile | **[MVP]** |
| 4.2 | `PathService` on `AStarGrid2D` + per-tick budget; steering local avoidance | **[MVP]** |
| 4.3 | Tap-select a unit; selection ring; panel populates | **[MVP]** |
| 4.4 | Actions: stop, move, gather, build | **[MVP]** |
| 4.5 | Context-sensitive action flash on tap target | **[MVP]** |
| 4.6 | Unit health + health dot (orange <50%, red <25%) | **[MVP]** |
| 4.7 | Death: die anim, drop cargo, 60 s corpse w/ 10 s fade, unselectable | **[MVP]** |
| 4.8 | Garrison | |
| 4.9 | Defensive garrison damage bonus | |
| 4.10 | Special abilities + cooldowns | |
| 4.11 | Population cap from houses/town centres | |
| 4.12 | Stances | |
| 4.13 | Military units + `CombatSystem` | |
| 4.14 | Formations | |

### Phase 5 — Buildings *(IDEA phase 5)*

| # | Item | Tag |
|---|---|---|
| 5.1 | Placement ghost: drag, snap to grid, validity colour, red flash on invalid | **[MVP]** |
| 5.2 | Construction phases (foundation → building → complete) | **[MVP]** |
| 5.3 | Building upgrades | |
| 5.4 | Production queue: enqueue, progress, cancel/refund, spawn on free adjacent tile | **[MVP]** |
| 5.5 | Destruction → rubble, frees tiles, unselectable | **[MVP]** |
| 5.6 | Building health + health dot | **[MVP]** |
| 5.7 | Full building roster | |

### Phase 6 — Resources & wildlife *(IDEA phase 6)*

| # | Item | Tag |
|---|---|---|
| 6.1a | Deer as a huntable food node (carcass gatherable) | **[MVP]** |
| 6.1b | Wildlife roaming + flee-and-relocate | |
| 6.2 | Gold mines, 3 size classes, `gather_slots` | **[MVP]** |
| 6.3 | Trees + forest clustering, 3 size classes | **[MVP]** |
| 6.4 | Gather loop: walk → cooldown → carry cap → return to drop-off → repeat | **[MVP]** |
| 6.5 | Stone, farms, fishing, berry bushes, boar | |

### Phase 7 — Resource HUD *(IDEA phase 7)*

| # | Item | Tag |
|---|---|---|
| 7.1 | 5 counters (stone, gold, wood, food, idle/total villagers) via `EventBus` | **[MVP]** |

### Phase 8 — Main game interface *(IDEA phase 8)*

| # | Item | Tag |
|---|---|---|
| 8.1a | Selection panel shell + single-unit view | **[MVP]** |
| 8.1b | Building view: queue slots + train buttons | **[MVP]** |
| 8.1c | Multi-select portrait grid | **[MVP]** |
| 8.2a | Circular minimap: terrain, entity blips, camera viewport rect | **[MVP]** |
| 8.2b | 4 corner buttons (menu, chat, minimize, trade — trade locked behind market) | |
| 8.3 | Two-finger box select | **[MVP]** |
| 8.4 | Notice/toast line | **[MVP]** |
| 8.5 | Pause/in-game menu, resign | **[MVP]** |

### Phase 9 — Ages & tech *(IDEA phase 9)*

| # | Item | Tag |
|---|---|---|
| 9.1 | Age header: roman numeral in gold circle | |
| 9.2 | Age advancement progress bar | |
| 9.3 | `TechSystem`: research timers, stat modifiers, gating | |
| 9.4 | Tech tree screen | |
| 9.5 | Faction unique units/bonuses | |

### Phase 10 — Control groups *(IDEA phase 10)* — **all MVP**

Core mobile mechanic; needs testing under real thumb use, so it ships in MVP.

| # | Item | Tag |
|---|---|---|
| 10.1 | 5 circular slots, empty state, `ControlGroups` UI wired to `EventBus` | **[MVP]** |
| 10.2 | Two-finger box select → double-tap a slot to assign (`SetControlGroupCommand`) | **[MVP]** |
| 10.3 | Double-tap a unit → select all of that type on screen; double-tap slot to assign | **[MVP]** |
| 10.4 | Slot icon = most-represented unit type; reverts to empty circle when emptied | **[MVP]** |
| 10.5 | Single tap selects the group; double tap centres camera on it | **[MVP]** |
| 10.6 | Groups persist in `SimPlayer`, survive reconnect (§7.1) | **[MVP]** |

### Phase 11 — Win conditions *(IDEA phase 11)*

| # | Item | Tag |
|---|---|---|
| 11.1 | `WinConditionSystem` + conquest mode; result screen | |
| 11.2 | Additional modes (regicide, king of the hill, capture the flag, wonder) | |
| 11.3 | Mode shown in lobby and match-start screen | |

### Phase 12 — Multiplayer & AI *(IDEA phase 12)*

| # | Item | Tag |
|---|---|---|
| 12.1a | `host_open()` on 0.0.0.0 + `join()` | |
| 12.1b | LAN discovery, reconnect, lag compensation, desync detection | |
| 12.2a | `AISystem` state machine emitting normal `Command`s | |
| 12.2b | AI difficulty levels | |
| 12.3 | Campaign: scripted triggers/objectives on the host-loopback path | |
| 12.4 | Save/load and replays | |

### Phase 13 — Dragons *(IDEA phase 13)*

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

**First post-MVP batch:** 11.1 + 4.11 + 4.13 + 2.5 + 12.2a — turns the economy demo into a winnable match.

---

## 12A. Art track (parallel, asynchronous)

Never blocks gameplay phases. Ordered by visual payoff per unit of effort.

| # | Item | Depends on |
|---|---|---|
| A.1 | Terrain tile set from 0 A.D. ground textures via `bake_terrain.py` | 0.9 |
| A.2 | Town centre + house, with construction/damage/rubble states | 0.9 |
| A.3 | Villager — 11 animations × 5 directions (~825 frames). Most expensive single asset | 0.9 |
| A.4 | Resource props: tree (3 sizes + stump), gold mine, deer | 0.9 |
| A.5 | UI chrome from the itch.io dragon packs | none |
| A.6 | Team-colour outline shader | A.3 |
| A.7 | Audio pass — 0 A.D. sfx/music into `audio.json` | 0.9 |
| A.8 | Military unit art | A.3 |
| A.9 | **Dragon + nest — bespoke** | A.3, A.8 |

A.1 and A.2 come first: cheap, transform the look, and validate the render pipeline before the expensive villager work.

---

## 13. Standing policies & open items

### 13.1 Standing policies (approved)

- **Third-party open-source code and addons may be used freely** — Godot RTS templates, pathfinding/flow-field addons, fog-of-war addons. Requirement: **credit only what is actually used**, recorded in `CREDITS.md` + `assets/LICENCES.md`, and the licence must be compatible with an open-source CC-BY-SA art release.
- **Reference engines may be studied for design** (`OpenRA`, `0 A.D.`, `Spring/Recoil`, `Widelands`) — netcode models, data formats, pathfinding approaches. Credit when code or assets are actually taken, not for reading.

### 13.2 Genuinely open

| # | Item | Owner |
|---|---|---|
| 1 | **Does the render pipeline produce usable sprites?** Formats and tooling are now known (§1.3, §2.2), but nobody has done 0 A.D.→2D before. Prove it on one unit at 0.9 before scheduling A.3 | 0.9 |
| 2 | **Which 0 A.D. actors map to our entities.** Their unit set is ancient-warfare, ours is medieval-fantasy — needs a hand-picked actor→`vis.*` mapping, and some entities may have no good match | 0.9 / A.2 |
| 3 | **Audio fit** — 0 A.D. audio exists and is licence-clean, but its voices are civilisation-specific (`greek`, `latin`, `napatan`, `persian`) and won't suit. Decide what's reusable vs newly sourced | [ASSET_MISSING.md](ASSET_MISSING.md) |
| 4 | **Icon volume** — tech/unit/resource icons are individually trivial but numerous; crop from sprites, generate, or commission | ASSET_MISSING.md |
| 5 | **Second pack mirror** — website is primary and unconstrained; pick a fallback later | before first public build |
| 6 | **Device reach on Compatibility** — confirm the target phone runs it cleanly at 0.1. Known Android driver issues cluster on Mali/MediaTek/Adreno under Vulkan, which is the reason for the §1 renderer choice | 0.1 |

---

## 14. Risk register

| Risk | Severity | Mitigation |
|---|---|---|
| Art production is the long pole | **High** | Placeholders (§2.4) keep it off the critical path; art track runs async; cheap wins first |
| 3D→iso render pipeline doesn't produce usable sprites | **High** | Nobody has done 0 A.D.→2D before; validate on one unit at 0.9 before committing to A.3. Fallbacks, both already 2D isometric and licence-compatible: **Unknown Horizons** for terrain/map art, **Widelands** for units/buildings |
| **Blender 5.x silently breaks the pipeline** — COLLADA import was removed in 5.0 and 0 A.D. ships `.dae` | **High** | Hard-pin **4.5 LTS** (§1.3), supported to Jul 2027. Do not let an auto-update move it. A community 5.x `.dae` importer exists but is unvetted |
| Animation import is a manual step — the pyrogenesis importer handles meshes/textures but not animations | Medium | Our render script attaches `art/animation/*.dae` to the armature itself; budget for it at 0.9 |
| 0 A.D. actors don't map cleanly to a medieval-fantasy roster | Medium | Hand-pick the actor→`vis.*` mapping (§13.2 item 2); some entities may need bespoke art |
| Accidentally shipping an unlicensed asset | Medium | `licence_audit.py` + `LICENCES.md` in CI from 0.2c |
| CC-BY-SA attribution missed | Medium | `CREDITS.md` + in-game Credits screen from 1.4; per-pack licence files |
| Pathfinding stalls at scale | Medium | Per-tick path budget from day one; flow fields in reserve |
| GDScript too slow at 200 units | Medium | Measure on device from 0.7; targeted GDExtension only if proven |
| Mobile thermal throttling | Medium | 10 Hz sim, pooled views, draw-call budget, sustained-load testing |
| Asset pack download fails / user offline | Medium | Game runs on placeholders; packs are `required: false` |
| Per-frame anchor jitter | Medium | Atlas stores an anchor per frame; contact-sheet check in 0.9 |
| WSL/Docker fighting Android USB deploy | Low | §1.2 — native Windows for editor + deploy |
| Scope creep | **High** | The `[MVP]` tag is a hard gate; §12 governs after |

---

## 15. Immediate next actions

1. **Create the Godot 4.x project at `game/` and deploy an empty landscape scene to a physical Android device** (0.1). Before any gameplay code, natively on Windows.
2. **Build the asset seam + placeholder renderer** (0.2a/0.2b) — makes every gameplay phase independent of art.
3. **Stand up `SimWorld` + `SimClock` headless** with a passing test that ticks an empty world (0.5).
4. **Wire `host_solo()` and get one placeholder villager moving on a tap**, end to end through the loopback network (0.6). Once that works the architecture is proven and the rest is content.
5. **Prove the 0 A.D. render pipeline on a single unit** (0.9) before scheduling A.3.
