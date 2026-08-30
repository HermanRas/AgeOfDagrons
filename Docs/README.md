# AOD documentation

Everything you need to clone, build, run, contribute to and re-skin **Age of Dragon**.

| | |
|---|---|
| [1. Building for desktop](#1-building-for-desktop) | Clone, open, run, test |
| [2. Building for Android](#2-building-for-android) | Full toolchain from scratch, no Android Studio |
| [3. Contributing](#3-contributing) | Rules that are actually enforced, and by what |
| [4. Licensing](#4-licensing) | Two licences, and which applies to what |
| [5. Issues and feature requests](#5-issues-and-feature-requests) | What to include so a bug is reproducible |
| [6. Adding assets and re-skinning](#6-adding-assets-and-re-skinning) | The asset seam, packs, and replacing all the art |

> **Where the project actually is:** phase 0.9 of 13. The engine foundation works and is
> device-verified; there is no playable game. Sections below say plainly when they
> describe something that doesn't exist yet.

---

## 1. Building for desktop

### 1.1 Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| **Godot** | **4.7.1-stable** — hard pin | Standard build, *not* .NET/Mono. The project is pure GDScript |
| **git** | 2.x | |

Every version in this project is pinned deliberately. Upgrading Godot is a planned task
at a phase boundary with the suite green before and after — never an "update available"
click. Mid-project engine drift costs more debugging time than any newer release saves.

Download Godot 4.7.1-stable from <https://godotengine.org/download> (or the
[GitHub releases](https://github.com/godotengine/godot/releases/tag/4.7.1-stable)).
It is a single portable executable — no installer, no PATH entry required. On Windows,
prefer the `_console.exe` variant for any command-line run so stdout is visible.

### 1.2 Clone

```bash
git clone https://github.com/HermanRas/AgeOfDagrons.git
cd AgeOfDagrons
```

> **⚠️ The Godot project root is `game/`, not the repository root.** The repo root holds
> design docs and offline tooling. Point Godot at `game/`, or it will offer to create a
> new project and you'll wonder why nothing is there.

### 1.3 Open in the editor

Godot → **Import** → select `game/project.godot` → **Import & Edit**.

First import takes a minute while the engine builds `game/.godot/` (gitignored, per-user,
safe to delete and regenerate).

Press **F5** to run. Today that launches `scenes/game/StressTest.tscn` — 200 villagers
as dots on a dark field with a performance report overlaid. That is the current main
scene, and it is deliberate: until the asset seam lands at 0.2a there is nothing else to
show, and the stress test exercises the full real path (`host_solo()` → `SimHost` →
`SnapshotSystem` → `Net` → `GameView`).

### 1.4 Run the test suite

This is the important command. It is one line and needs no framework. **Nothing runs it
for you** — there is no CI (§3.1), so this is a habit, not a safety net:

```bash
godot --headless --path game res://tests/run_tests.tscn
```

Exit code `0` = pass, `1` = fail. Expected output today:

```
  29 test(s), 496 assertion(s) in 184 ms
  29 passed, 0 failed
  RESULT: PASS
```

Windows, with the pinned binary and no PATH entry:

```powershell
& "C:\path\to\Godot_v4.7.1-stable_win64_console.exe" --headless --path game res://tests/run_tests.tscn
```

<details>
<summary><strong>Why it's a scene, not <code>--script</code></strong></summary>

The runner is a `Node` under `run_tests.tscn`, not a `SceneTree` override passed to
`--script`. A custom `--script` MainLoop skips the boot sequence that parents autoload
singletons under the tree root, silently breaking anything that needs `get_tree()` or
`get_multiplayer()`. That was discovered the hard way while building `Net` at phase 0.6.
A real scene, even headless, boots exactly like the shipped game does.

</details>

<details>
<summary><strong>If the suite reports zero tests</strong></summary>

Discovering **zero tests is a hard failure**, not a pass — deliberately. Renaming the
`TestCase` base script once invalidated `.godot/global_script_class_cache.cfg`, discovery
collapsed to nothing, and the suite cheerfully reported PASS. Now it fails loudly and
prints the recovery command:

```bash
godot --headless --path game --import --quit
```

</details>

### 1.5 Exporting a desktop build

There is currently **only an `Android` export preset** in `game/export_presets.cfg`.
Desktop is a development and test target, not a shipped one yet. To make a Windows or
Linux build, add a preset in **Project → Export** — you'll need the matching export
templates (**Editor → Manage Export Templates**).

---

## 2. Building for Android

Android is the **primary** target. This section is the full path from a clean machine,
and every command below was run and verified on this project.

### 2.1 What you actually need — and what you don't

**You do not need Android Studio.** The project sets
`gradle_build/use_gradle_build=false`, so Godot exports using its **prebuilt export
template** rather than compiling a custom Gradle build. That removes Gradle, the NDK and
the Android Gradle Plugin from the requirements entirely.

You still need a JDK and part of the Android SDK, because Godot shells out to
**`apksigner`** (from `build-tools`) to sign the APK, and you need **`adb`** (from
`platform-tools`) to install it.

| Requirement | Version used here | Why |
|---|---|---|
| **Godot** | 4.7.1-stable | Pinned |
| **Godot Android export templates** | 4.7.1.stable | The prebuilt APK skeleton |
| **JDK** | 17 recommended · **26 verified working** | Runs `apksigner` |
| **Android SDK `build-tools`** | 36.1.0 | `apksigner`, `zipalign` |
| **Android SDK `platform-tools`** | latest | `adb` |
| **Android SDK `platforms;android-36`** | android-36 | Only strictly needed if you enable the Gradle build |
| **A debug keystore** | — | Godot generates one for you |

> **On the JDK version:** Godot's documentation specifies **JDK 17**, and you must use 17
> if you ever set `use_gradle_build=true`. With the prebuilt template the JDK only runs
> `apksigner`, so newer JDKs work — this project's APK was built and signed with JDK
> 26.0.1. It prints harmless `WARNING: A restricted method in java.lang.System has been
> called` lines from `apksigner`; ignore them. If anything at all misbehaves, install 17
> and point Godot at it.

### 2.2 Install the JDK

Windows:

```powershell
winget install Microsoft.OpenJDK.17
```

Set `JAVA_HOME` to the install root, e.g.
`C:\Program Files\Microsoft\jdk-17.0.15.6-hotspot`, and add `%JAVA_HOME%\bin` to `PATH`.

Verify:

```powershell
java -version
```

### 2.3 Install the Android SDK (command-line tools only)

Download **"Command line tools only"** from
<https://developer.android.com/studio#command-line-tools-only> — not the full Studio
bundle.

Extract so the layout is exactly this. The nested `latest\` folder is required;
`sdkmanager` refuses to run if the tools sit directly under `cmdline-tools\`:

```
%LOCALAPPDATA%\Android\Sdk\
└── cmdline-tools\
    └── latest\
        ├── bin\
        └── lib\
```

Set the environment variables (both — different tools read different ones):

```powershell
[Environment]::SetEnvironmentVariable("ANDROID_HOME", "$env:LOCALAPPDATA\Android\Sdk", "User")
[Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", "$env:LOCALAPPDATA\Android\Sdk", "User")
```

Add to `PATH`: `%ANDROID_HOME%\cmdline-tools\latest\bin` and `%ANDROID_HOME%\platform-tools`.

**Open a new terminal**, then install the packages and accept the licences:

```powershell
sdkmanager "platform-tools" "build-tools;36.1.0" "platforms;android-36"
sdkmanager --licenses
```

Verify:

```powershell
adb version
```

### 2.4 Install the Godot Android export templates

In the Godot editor: **Editor → Manage Export Templates → Download and Install**.

They land in `%APPDATA%\Godot\export_templates\4.7.1.stable\` (Windows) or
`~/.local/share/godot/export_templates/4.7.1.stable/`. The version string must match your
editor exactly.

### 2.5 Point Godot at the toolchain

**Editor → Editor Settings → Export → Android**:

| Setting | Value on this machine |
|---|---|
| `Android Sdk Path` | `C:\Users\<you>\AppData\Local\Android\Sdk\` |
| `Java Sdk Path` | `C:\Users\<you>\...\jdk-17...\` (the JDK root, not `bin\`) |
| `Debug Keystore` | `C:\Users\<you>\AppData\Roaming\Godot\keystores\debug.keystore` |
| `Debug Keystore User` | `androiddebugkey` |
| `Debug Keystore Pass` | `android` |

**Godot generates the debug keystore for you** the first time it needs one, at
`%APPDATA%\Godot\keystores\debug.keystore`. Note it is *not* in the traditional
`~/.android/debug.keystore` location. If you need to create it by hand:

```bash
keytool -keyalg RSA -genkeypair -alias androiddebugkey \
  -keypass android -storepass android \
  -keystore debug.keystore -validity 10000 \
  -dname "CN=Android Debug,O=Android,C=US"
```

These are **editor settings, not project settings** — they are per-machine and are not in
the repo. Every developer sets them once.

> **Release builds** need your own keystore, configured under `Project → Export →
> Android → Keystore → Release`. Never commit a release keystore or its passwords.
> `game/.godot/export_credentials.cfg` holds them locally and `.godot/` is gitignored.

### 2.6 Export

From the editor: **Project → Export → Android → Export Project**.

From the command line — verified working, exit code 0:

```bash
godot --headless --path game --export-debug "Android" ../AgeOfDragons.apk
```

The preset already writes to `../AgeOfDragons.apk` (repo root), so the path argument is
optional. Use `--export-release` for a release build. Expected tail of the output:

```
Adding permission android.permission.INTERNET
[  98% ] export | Signing debug APK...
Signed
[  99% ] export | Verifying APK...
[ DONE ] export
```

Result: a **~59 MB** APK, `arm64-v8a` + `x86_64`.

> **`.apk` files are gitignored.** Build artifacts never go in the repo.

### 2.7 Deploy to a device

Enable **Developer options → USB debugging** on the phone, plug it in, accept the
"Allow USB debugging?" prompt, then:

```bash
adb devices          # confirm the device is listed and says "device", not "unauthorized"
adb install -r AgeOfDragons.apk
```

You can also use Godot's **one-click deploy** — the phone icon in the top-right of the
editor, once `adb` sees the device.

### 2.8 What's configured, and what still needs deciding

From `game/export_presets.cfg` (which **is** tracked in git — it contains no keystore
path or password):

| Setting | Value |
|---|---|
| `gradle_build/use_gradle_build` | `false` — prebuilt template |
| `gradle_build/export_format` | `0` (APK, not AAB) |
| Architectures | `arm64-v8a` ✅, `x86_64` ✅, `armeabi-v7a` ❌, `x86` ❌ |
| `screen/immersive_mode` | `true` |
| `permissions/internet` | **`true`** — load-bearing, see below |
| `package/unique_name` | `com.example.$genname` — ⚠️ **still the placeholder** |
| Launcher icons | ⚠️ **unset** — falls back to Godot's defaults |
| `version/code` | `1`; `version/name` empty |

The last three must be fixed before any store release. They're tracked as open items,
not oversights.

> #### Why `permissions/internet` must stay `true`
>
> It was originally `false`. That made `Net.host_solo()` **fail silently on-device** —
> Android requires the INTERNET permission to open *any* socket, including a loopback one
> to `127.0.0.1`. Since AOD runs a real server even for solo play, the whole game
> silently did nothing on the phone while working perfectly on desktop. Found while
> building the phase 0.7 stress test, fixed in commit `8dddd44`. `export_presets.cfg` is
> tracked in git precisely so this ships correctly for everyone.

### 2.9 Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `adb devices` shows nothing at all — not even "unauthorized" | **Reconnecting the USB cable can silently switch the "USB debugging" toggle back off.** Check developer options before blaming the cable or driver |
| Device shows `unauthorized` | Accept the RSA fingerprint prompt on the phone. If it never appears: `adb kill-server; adb start-server` |
| Export fails: "Android SDK path is invalid" | `Android Sdk Path` must be the SDK **root** (the folder containing `build-tools\`), not `cmdline-tools\` |
| Export fails at the signing step | `build-tools` isn't installed, or `Java Sdk Path` points at `bin\` instead of the JDK root |
| Export fails: "No export template found" | Templates missing or version-mismatched. **Editor → Manage Export Templates** |
| Game launches, black screen, nothing happens | Check `adb logcat`. If the sim never starts, verify INTERNET permission is on (§2.8) |
| `sdkmanager` won't start | The `cmdline-tools\latest\` nesting is wrong (§2.3), or `JAVA_HOME` isn't set |
| Performance looks wrong on desktop | **The stress test must be judged on the phone.** Desktop numbers mean nothing for a mobile budget |

---

## 3. Contributing

Contributions are welcome. The project has strong opinions about a small number of
things and no opinion at all about the rest.

### 3.1 The workflow

1. Fork, branch off `main`.
2. Make the change.
3. **Run the test suite.** `godot --headless --path game res://tests/run_tests.tscn` must
   exit `0`.
4. If you touched anything under `game/src/view/` or added units, **run the stress test
   on a physical Android device**, not on desktop.
5. Open a pull request describing what changed and which phase it belongs to.

There is **no CI on this repo** — no `.github/`, nothing runs on push, and no merge is
gated on anything. The test runner, the boundary check and the licence audit are all
shaped around single commands with meaningful exit codes precisely so CI is trivial to
add, but until someone adds it, running them before you push is entirely on you.

Note the sister repo differs: [`blender_3d_to_2d_isobake`](https://github.com/HermanRas/blender_3d_to_2d_isobake)
*does* have `.github/workflows/ci.yml` running pytest. Do not assume the same is true
here.

### 3.2 The rules that are actually enforced

**Nothing under `game/src/sim/` may extend `Node`, load a texture, read input, or touch
the view layer.** This is checked by
[`test_sim_boundary.gd`](../game/tests/sim/test_sim_boundary.gd) on every test run. It
rejects `extends Node/Node2D/Control/...` and forbidden substrings — `Input.`,
`get_tree(`, `add_child(`, `res://assets/`, `GameView`, `Iso.` — in any `src/sim/**.gd`.

It is a test rather than a lint script for one reason: the whole suite stays one command.

This boundary is the single most valuable constraint in the codebase. It is why the game
logic is testable headlessly in milliseconds, why `state_hash()` is meaningful, and why
replays work. If you find yourself wanting to break it, the answer is a snapshot field or
a command, not an exception.

**Determinism is not optional.** The simulation must produce identical `state_hash()`
output for identical input. Watch out for:

- Iterating a `Dictionary` and depending on the order — entity IDs are **sorted before
  folding** into the hash for exactly this reason.
- Floating-point where integers will do. Positions are integer sub-tile units,
  **1 tile = 256 sub-units**.
- Anything frame-rate dependent. The sim ticks at a fixed 10 Hz; rendering interpolates.

**Any third-party asset, addon or dependency must be credited in the same change that
introduces it** — in [CREDITS.md](../CREDITS.md), and (from phase 0.2c) in
`game/assets/LICENCES.md`. This is a licence obligation, not politeness. Only use
licences compatible with a CC-BY-SA art release.

### 3.3 Scope discipline

`PLAN.md` tags phases **`[MVP]`**. Nothing untagged gets written until every `[MVP]` item
is done, tested and working on a physical Android device. Scope creep is listed as the
project's highest-probability risk, and the tag is the hard gate against it.

If you want to build something outside the current phase, open an issue first and say so
— it may be welcome, but it may also be deliberately deferred.

### 3.4 Style

- **GDScript**, static typing where it's natural (`var x := 5`, typed params and returns).
- Follow the [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html).
- `snake_case` files and functions, `PascalCase` classes, `SCREAMING_SNAKE` constants.
- `.editorconfig` is in `game/` — respect it.
- **Match the surrounding code.** Comment density, naming and idiom are already
  consistent; keep them that way.
- Commit messages follow the existing log: imperative mood, and phase work reads
  `Complete phase 0.7: state_hash, replays, sim boundary check, StressTest`.

### 3.5 Optimisation policy

GDScript everywhere. Profile **on the target Android device**. Move a hot loop to
GDExtension only when profiling proves it dominates — not before.

Budgets to hold to: 16.6 ms frame (33 ms hard floor), 200 live units, under 200 draw
calls, under 256 MB texture memory, APK under 300 MB.

### 3.6 Reading the codebase

Start here, in order:

| File | What it tells you |
|---|---|
| [`PLAN.md`](../PLAN.md) | The architecture and why. §1 is the locked decisions |
| [`game/src/sim/sim_world.gd`](../game/src/sim/sim_world.gd) | `step()`, `spawn_unit()`, `state_hash()` — the heart |
| [`game/src/autoload/net.gd`](../game/src/autoload/net.gd) | `host_solo()`, and why solo isn't a special case |
| [`game/src/view/iso.gd`](../game/src/view/iso.gd) | Isometric projection. `Iso.TILE_SIZE` is the single source of truth |
| [`game/tests/run_tests.gd`](../game/tests/run_tests.gd) | How testing works here |

---

## 4. Licensing

**AOD is under two licences.** Which one applies depends on what you're taking.

| What | Licence | File |
|---|---|---|
| **Software** — GDScript, scenes, `project.godot`, `tools/`, docs | **MIT** | [`LICENSE`](../LICENSE) |
| **Art & audio** — sprites, atlases, terrain, animations, SFX, music | **CC-BY-SA 3.0** | [`LICENSE-ART.md`](../LICENSE-ART.md) |

### 4.1 Why they differ

The art is not originally ours. AOD's sprites are **rendered from
[0 A.D.](https://play0ad.com)'s 3D models**, released by Wildfire Games under Creative
Commons Attribution-ShareAlike 3.0. Share-alike means derived works carry the same
licence — so our 2D sprite sheets are CC-BY-SA 3.0 and there was never a choice.

The code is ours, so it stays permissive. The two licences do not merge.

### 4.2 Using AOD "as is"

| You want to… | You may | You must |
|---|---|---|
| Read, learn from, copy the code | ✅ | Keep the MIT copyright notice |
| Fork the whole game and ship it | ✅ | Code stays MIT; art stays CC-BY-SA 3.0 with attribution |
| Use AOD's art elsewhere | ✅ | Attribute Wildfire Games (exact wording below) and release your derived art CC-BY-SA 3.0 |
| Sell a game built on AOD's code | ✅ | Nothing beyond the MIT notice — MIT permits commercial use |
| Sell a game using AOD's art | ✅ | CC-BY-SA 3.0 permits commercial use, but requires attribution **and** share-alike on the art |
| Re-skin AOD with your own art | ✅ | Your art, your licence. See [§6](#6-adding-assets-and-re-skinning) |
| Redistribute the Kibyra UI packs | ❌ | Their licence forbids it. Moot since 2026-08-30 — the game no longer uses any of that art, and none of it is in this repo |

### 4.3 The required attribution

Reusing AOD art means reproducing all three elements **verbatim**. They are required by
`art/LICENSE.txt` and `audio/LICENSE.txt` in the 0 A.D. repository — do not abbreviate:

> Original author: **Wildfire Games** — <http://www.wildfiregames.com/>
> Licence: **Creative Commons Attribution-ShareAlike 3.0** — <http://creativecommons.org/licenses/by-sa/3.0/>

…plus a statement of modifications. Ours, in full, is in [CREDITS.md](../CREDITS.md).

### 4.4 Attribution inside the game

`CREDITS.md` is surfaced on an in-game Credits screen (phase 1.4). That is a **licence
obligation, not a courtesy** — shipping the art without visible attribution would breach
CC-BY-SA.

---

## 5. Issues and feature requests

Everything goes through **GitHub Issues**:
<https://github.com/HermanRas/AgeOfDagrons/issues>

There are no issue templates yet, so please include the following by hand.

### 5.1 Reporting a bug

```
**What happened / what you expected**

**Steps to reproduce**

**Platform**   Android 16 / Windows 11 / Linux
**Device**     HONOR LNA-NX1 (Mali-G610 MC2)   ← for Android
**Godot**      4.7.1-stable
**Commit**     ffa8537

**Test suite**  passes / fails  (`godot --headless --path game res://tests/run_tests.tscn`)
**Replay file** attached / not applicable
**Logs**        adb logcat output, or the editor console
```

**Attach a replay if you possibly can.** A replay is a `MatchConfig` plus an ordered
command log — a few kilobytes of JSON — and it reproduces a session exactly. It is the
single most useful thing you can send: it lets a bug found on your phone be replayed
headlessly on someone else's desktop.

If a `state_hash()` mismatch or a determinism problem is involved, say so prominently.
Those are the highest-priority class of bug in this project, because everything else —
networking, replays, the AI — is built on the simulation being deterministic.

### 5.2 Requesting a feature

Say what you want and **why** — the problem, not just the solution. Then check
[IDEA.md](../IDEA.md): the whole game is broken into 13 phases, and there's a good chance
your request is already planned. If so, say which phase; that helps far more than a new
issue does.

If it isn't in IDEA.md, expect the first question to be whether it belongs before or
after MVP (§3.3). "After" is not a rejection — it is how this project avoids drowning.

### 5.3 Security

For anything with a security dimension, don't open a public issue. Contact the maintainer
directly through GitHub.

---

## 6. Adding assets and re-skinning

AOD is designed to be re-skinned. That isn't an afterthought — it's the reason the asset
architecture looks the way it does.

> **⚠️ Status:** the asset *seam* is designed and documented, but `game/data/visuals.json`,
> `game/data/audio.json` and the `GameDataRegistry` land at **phases 0.2a and 0.4** and do
> not exist yet. This section describes the design you'll be working with, and is accurate
> to the plan. Check `PLAN.md` §2 for the current authoritative detail.

### 6.1 The one rule

**No filename ever appears in gameplay code.**

Every visual and every sound sits behind a stable ID, resolved at runtime:

```gdscript
var vis := GameDataRegistry.atlas_for(&"vis.villager")
AudioManager.play_sfx(&"villager.chop")
```

`vis.villager`, `terrain.grass`, `villager.chop` — gameplay code knows these and nothing
else. Swap what the IDs point at and the entire game changes appearance without a single
line of logic changing. That is the whole re-skinning story.

### 6.2 Adding a visual asset

1. **Pick or reuse an ID** from the vocabulary in `PLAN.md` §2.5 (`vis.*` for entities,
   `terrain.*` for tiles, and per-entity animation IDs like `idle`, `walk`, `work_chop`,
   `walk_carry_wood`).
2. **Produce the sprite sheet.** Either render it with the pipeline (§6.4) or author it
   directly. Format and atlas layout are specified in `PLAN.md` §9.1.
3. **Register it** in `game/data/visuals.json` against the ID.
4. **Credit it** in [CREDITS.md](../CREDITS.md) and `game/assets/LICENCES.md`, in the same
   change. Non-negotiable — see [§3.2](#32-the-rules-that-are-actually-enforced).
5. **Run the suite.**

Missing assets are not an error: an unresolved ID falls back to the procedural
placeholder renderer, so the game always runs. You can build a whole gameplay phase
before its art exists.

### 6.3 Adding audio

Same shape, via `game/data/audio.json`. `AudioManager` exists from MVP with a **no-op
implementation** and the full ID vocabulary, so gameplay emits `play_sfx(&"villager.chop")`
from day one and the audio pack lands whenever it lands.

### 6.4 Rendering new sprites from 3D

The 3D→2D isometric pipeline lives in its own repository:
**[HermanRas/blender_3d_to_2d_isobake](https://github.com/HermanRas/blender_3d_to_2d_isobake)**
(GPL-2.0-or-later). It was split out at phase 0.9 because it deliberately isn't
AOD-specific — 0 A.D. is one adapter, and glTF/FBX sources go through the same camera.

What stays in **this** repo is `tools/` — the recipes, because "0 A.D.'s female citizen is
our villager" is a content decision, not a tool feature.

| File | What |
|---|---|
| `tools/isobake.toml` | Camera config. `tile_px = [64, 32]`, `metres_per_tile = 2.0`, `azimuth_deg = 45.0` |
| `tools/isobake.local.toml.example` | Per-machine paths — copy to `isobake.local.toml` (gitignored) |
| `tools/recipes/*.toml` | One per asset: source actor, render settings, animation mapping, attribution |

```bash
cd tools
isobake build recipes/villager.toml
```

Toolchain, all hard-pinned (`PLAN.md` §1.3):

- **Blender 4.5.12 LTS — do not use 5.x.** COLLADA `.dae` import was *removed* in Blender
  5.0, and 0 A.D.'s meshes are `.dae`. Install as a **portable extract**, not Steam or MS
  Store, so an auto-update can't silently break the art track.
- **Python 3.11+** with Pillow and numpy — no system install needed; build the venv from
  Blender's own bundled Python.
- **`blender_pyrogenesis_importer`** pinned at `b31b5c4`. isobake applies two Blender-4.5
  shims at load time rather than forking it.
- **0 A.D. art**: `git clone --depth 1 https://gitea.wildfiregames.com/0ad/0ad.git`.
  Needs **git-lfs** — without it the clone succeeds but the checkout fails. Scope it with
  `git config lfs.fetchinclude "binaries/data/mods/public/art/**"`. ~11 GB shallow.
  Clone the repo; **don't** mine the game installer, which ships compiled `.pmd`/`.dds`
  formats with no maintained Blender importer. GitHub's `0ad/0ad` is archived — Gitea is
  upstream.

> `tools/isobake.toml`'s `tile_px` **must** match `Iso.TILE_SIZE` in
> [`game/src/view/iso.gd`](../game/src/view/iso.gd), which is the single source of truth.
> `elevation_deg` is deliberately absent from the config: it derives as `asin(32/64)` =
> exactly 30°. The 35.264° that isometric tutorials quote would make a 64 px tile 37 px
> tall.

### 6.5 UI art

**All of it is committed, and a clean clone runs with its chrome intact.** That was not
true until 2026-08-30: the UI was third-party itch.io art whose licence forbids
redistributing the originals, so `game/assets/ui/` was gitignored and every developer had
to download two packs by hand before the game had any panels at all. Replacing the lot
with project-owned art is what retired that, and it is the single biggest thing the UI
overhaul bought.

What is where:

| Directory | What |
|---|---|
| `game/assets/ui/icons/` | 103 icons at 100×100 RGBA — verbs, resources, technologies, formations, stances |
| `game/assets/ui/chrome/` | 27 panels, frames, bars, buttons and widgets. **Derived** — see below |
| `game/assets/ui/fonts/` | MedievalSharp and Cinzel Decorative, both SIL OFL, each beside its own licence text |

`chrome/` is generated, not copied. `tools/prepare_ui_chrome.py` rewrites the master art
in `assets/UI_Gen/sliced/chrome/` at the size that makes each piece's painted border draw
at the thickness its widget wants — because Godot draws a `NinePatchRect`'s border at 1:1,
so the source size is the only thing that controls it. Re-run the tool rather than
re-copying the masters.

Palette: `#2B1D14` fill, `#E5B842` gold (`HudStyle`). There is no layout spec document —
`UI_Design.md` was retired with the mockups on 2026-08-30 and nothing replaced it.

### 6.6 Asset packs

Art does **not** ship inside the APK. It ships as downloadable `.pck` files loaded at
runtime with `load_resource_pack()`, keeping the APK small and letting art update without
a store release. Packs are marked `required: false` — the game runs on placeholders if a
download fails or the player is offline.

Pack manifest format is `PLAN.md` §3.2. `tools/build_packs.py` lands at phase 0.3.

### 6.7 Re-skinning the whole game

Because of §6.1, a total conversion is a content job with no code in it:

1. Produce your own sprite sheets for every ID in `visuals.json`.
2. Repoint `visuals.json` and `audio.json` at them.
3. Build a pack (§6.6) and ship it.
4. Licence your art however you like — it's yours. Just don't claim the CC-BY-SA-derived
   originals as part of it, and keep [CREDITS.md](../CREDITS.md) honest about whatever
   0 A.D.-derived assets you retain.

---

## See also

| Document | What |
|---|---|
| [IDEA.md](../IDEA.md) | What we're building — phases 1–13, gameplay design |
| [PLAN.md](../PLAN.md) | How — architecture, API reference, phase plan, risks. 1300 lines, the authoritative source |
| [asset_request.md](../asset_request.md) | Art the game side needs, requested per need and answered in place |
| [CREDITS.md](../CREDITS.md) | Third-party attribution |
| [LICENSE](../LICENSE) · [LICENSE-ART.md](../LICENSE-ART.md) | The two licences |
