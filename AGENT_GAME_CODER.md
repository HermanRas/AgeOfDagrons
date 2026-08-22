# AGENT_GAME_CODER.md

Bootstrap for the **game-code agent** on AOD_Mobile. Paste this at the start of a
session so the next one does not have to rediscover any of it.

Its counterpart is [AGENT_ASSET.md](AGENT_ASSET.md) — the art-pipeline agent's
equivalent. **Read both before starting.** The two agents share one working tree
and one repo, and each owns a side of a fence described below.

---

## 1. Who I am and what I own

I am the game-code agent. **I own `game/`** — the Godot project: `src/`, `data/`,
`scenes/`, `tests/`, `dev_preview/`.

**I do NOT own, and must not edit:**

| Not mine | Why |
|---|---|
| `tools/` | isobake recipes + bake/stage scripts — the art agent's |
| `art_work/out/` | baked atlases; build output |
| the isobake source | its own repo, `Downloads\AOD_game\blender_3d_to_2d_isobake` |
| `ASSET_MISSING.md` | the art agent's tracker |

`game/assets/atlases/` is *staged* art. It is gitignored and normally written by
the art agent's `tools/stage_atlases.py`. I read it freely; I only ever write to
it when the project owner explicitly asks me to pull art across (has happened
once — see §6).

**How the two agents talk:** [asset_request.md](asset_request.md). I append a
request using the format at the bottom of that file; the art agent answers
inline under the same heading. It works well — treat it as a conversation, and
answer their questions there rather than only in chat.

---

## 2. Authoritative documents, in priority order

1. **[Age & Unit Planning.md](<Age & Unit Planning.md>)** — THE ROSTER. Every
   line is an entity *template path*, not a hint about what kind of unit is
   wanted; the actor to bake is one hop inside the file's `<VisualActor><Actor>`.
2. **[PLAN.md](PLAN.md)** — architecture and phase order. §1 locked decisions,
   §2.7/§2.7.1 the age+faction skin model, §9 the data schema.
3. **[IDEA.md](IDEA.md)** — what we're building. **[UI_Design.md](UI_Design.md)**
   — how it looks, plus the `.jpg` mockups beside it.
4. `game/data/*.json` `_note` blocks — these are long, and they are the real
   design record for the data. **Read them in full before editing that file.**
   Several encode measurements and decisions that are expensive to re-derive.

**PLAN.md used to be mojibake** (double-encoded UTF-8, so table rows could not be
matched by an exact-string edit). It is **clean as of 2026-08-21** — `grep -c 'â€'`
finds nothing — so ordinary exact-string edits work. Re-check before assuming
either way; whatever fixed it could recur.

---

## 3. Commands

Godot is **pinned at 4.7.1** and is not on PATH:

```
C:\Users\herman.ras\Downloads\Godot_v4.7.1\Godot_v4.7.1-stable_win64_console.exe
```

```powershell
# The test suite — the one check that matters. Run before declaring anything done.
& $godot --headless --path game res://tests/run_tests.tscn --quit

# Refresh the global class cache. REQUIRED after adding any new `class_name`,
# or the suite fails with "Identifier not declared in the current scope".
& $godot --headless --path game --import

# Run the real match, driven and screenshotted (see §5)
& $godot --path game res://dev_preview/preview_match.tscn
& $godot --path game res://dev_preview/preview_match.tscn -- --interactive   # play it

# The other driven previews, all screenshotting
& $godot --path game res://dev_preview/preview_skirmish.tscn   # lobby + colour picker
& $godot --path game res://dev_preview/preview_menus.tscn      # front door + campaign
& $godot --path game res://dev_preview/preview_walls.tscn      # both wall axes + gate
& $godot --path game res://dev_preview/preview_ai_match.tscn   # two AIs, full match
```

`preview_walls` exists for the one thing **no test can judge**: which way a wall's
art faces. A wall lying across its own footprint has the same footprint, the same
origin and the same hash as one lying along it — so both axes get a screenshot and
somebody looks. It also finishes the walls before shooting, because a wall
*foundation* at nine tiles reads as a row of disconnected stubs.

Screenshots land in `%APPDATA%\Godot\app_userdata\AgeOfDragons\`.

There is **no CI**. Every check is a local command someone runs by hand.

---

## 4. Architecture invariants — do not break these

- **The sim carries no view types and no floats.** `src/sim/` may not extend
  Node, read input, load assets, or name a `view/` class.
  `tests/sim/test_sim_boundary.gd` greps for this and will fail you.
- **Input never mutates state.** A tap becomes a `Command`, goes to the server
  (even in a solo match, which is hosted on loopback), is `validate()`d, and
  applies on a tick boundary.
- **The server is the only trust boundary.** If the HUD hides an option, the
  command must also refuse it. Age gating is enforced in *both* places for
  exactly this reason.
- **`colours.json` order is load-bearing.** Saves and replays index into it.
  Never reorder.
- **`atlas_for()` is total** — it never returns null. An unknown id resolves to
  a loud magenta placeholder. That is what lets gameplay ship before art.
- **The asset seam is the only place filenames live** (`data/visuals.json` +
  `game_data.gd`). No filename in gameplay code.
- **Prefer extending `data/*.json` over hardcoding.**

### The skin key (PLAN.md §2.7.1)

`GameDataRegistry.atlas_for(visual_id, age, colour)` composes two independent
axes:

- **age** picks the base bake from the entry's `ages` map. That map is **dense by
  contract** — all four ages named explicitly, two ages that look alike simply
  point at the same file. `_validate_skins()` fails the suite on a gap.
- **colour** is a suffix transform on whatever age chose, gated by a
  `"colours": true` flag. isobake names tinted bakes `vis.<id>.<colour>`, so
  eight players are one boolean rather than eight declared paths.

Buildings carry the age; **units do not** — one actor in all four ages. Units
carry `age_required`, which is a *gate*, not a skin.

---

## 5. Working style that has actually paid off

- **Run the game, don't just test it.** `dev_preview/preview_match.tscn` boots
  the real match scene and drives it — selects a villager, opens the build menu,
  pages it, advances the age, trains units, screenshots each step. It has caught
  several things no headless test could: a HUD badge landing on top of the
  resource counters, a panel whose background cropped wrong, text drawn over the
  counters. **Look at the screenshot.** Crop and 2× zoom it if the detail is
  small.
- **A screenshot taken in the same frame as an action shows the state before
  it.** Commands round-trip through a snapshot. Shoot on a later step.
- **Beware fixtures that agree with the bug.** This has bitten twice, both times
  the production queue: a test fixture described the shape the code *actually
  produced* rather than the shape it *should*, so the test stayed green while the
  game was visibly wrong. When a bug reaches the screen, check whether a fixture
  was covering for it.
- The project owner reviews by screenshot and gives precise UI feedback. Expect
  it and act on it directly — it is usually right and usually cheap.

---

## 6. Gotchas that cost real time

| Gotcha | What to do |
|---|---|
| **Godot deletes comments in `project.godot` and `.tscn` on save** — triggered by `--import` *and* by simply running the game | Never put durable knowledge there. The orientation explanation now lives in `src/view/device_check.gd`. Check `git diff game/project.godot` after any editor/game run. |
| **Godot silently rewrites `scenes/ui_builder/*.tscn` layout properties** when the project is open | Check `git status` before committing; those are authored mockups and should not drift. |
| **`Array[StringName].sort()` orders by StringName IDENTITY, not string content** — and identity order is not stable between runs | Never take `unit_ids()`/`building_ids()` order into UI. Re-sort explicitly (the build menu sorts by age, then name). |
| **`&"unit.villager" == "unit.villager"` is FALSE** | JSON has no StringName, so everything off the wire is a String. Convert at the boundary (`GameView._names()`). |
| **PS 5.1 splits a here-string into git pathspecs** | Write the commit message to a file, `git commit -F <file>`. Never pipe a here-string. |
| **`Set-Content -Encoding utf8` adds a BOM** and has corrupted `project.godot` | Use .NET `WriteAllText`/`WriteAllLines` with `UTF8Encoding($false)`. |
| **A new `class_name` is invisible until `--import`** | Run it, then the suite. |
| **Staged atlases lag `art_work/out` silently** | A stale-but-valid atlas renders fine and is simply the wrong actor. Read `attribution.actor` out of the staged `.atlas.json` to tell — filenames and mtimes will not show it. |
| **A building missing a prop it should have** | Blender's COLLADA importer used to drop prop-point transforms, so any actor with stranded attach points quietly rendered those props at its origin. Fixed in isobake 2026-08-17, but only the five actors touched then were rebaked. Report it rather than working around it. |
| **A visual id is not a filename** | `vis.field_1` is baked as `vis.field_age2`, `vis.field_4` as `vis.farm`. The seam maps ids to paths precisely so ids outlive the art side's naming — and never rename a staged file to match, because `stage_atlases.py` will put it back. |
| **Two agents, one working tree** | Commits interleave. Check `git log` and what you actually staged; the art agent may have already committed your shared file (`asset_request.md`). |

---

## 7. Where things stand

**Data is complete for the v1 roster:** 19 buildings with dense four-age skin
maps, 21 units, all footprints measured (each baked atlas resolved back through
`attribution.actor` to its 0 A.D. template, parent chain walked to
`<Obstruction><Static>`, max taken per axis across the four ages).

**293 atlases staged.** 68 test files, 1016 tests, all passing.

**Working end to end:** age skins (Briton → Gaulish → Iberian/Achaemenid →
Roman), per-player colour selection from eight baked atlases, age-gated train and
build menus, a paged build grid, captioned portraits, production queue, a real
timed age-advance, fog of war, an enforced population cap, conquest win
conditions, the PlayTest AI, **two-device LAN multiplayer validated on hardware**
(PLAN.md §12.1 a–g), and the minimap's four corner pages — a working market, chat
and tech-tree wireframes, and settings (§8.2b).

### Known gaps — do not work around these silently

- **Only `red` and `yellow` colour bakes are trustworthy.** 60 others are
  *stale, not absent* — present, parsing, drawing, and wrong, because three
  pipeline defects were fixed mid-roster. `GameDataRegistry.stale_colour_atlases()`
  enumerates them; `missing_colour_atlases()` finds absent ones. Develop against
  players 2 and 3.
- **Walls are DONE** (PLAN.md 5.8, 2026-08-22) — this entry used to say they had
  no defs, and also that all the pieces were "baked and declared in
  `visuals.json`". Half of that was wrong: they were **staged but never
  declared**, which is exactly the failure mode that reports nothing (an
  undeclared id resolves to the magenta placeholder, and no def was pointing at
  one). Worth remembering as a class: *staged* and *wired* are different states,
  and only a def reaching for an id proves the second.
  What remains unbuilt around them: **no diagonal walls** (six of the eight baked
  directions are unreachable — a [9,2] box does not tile a square grid at 45°),
  **no garrison on a wall** (4.8), and **an open gate is open to everyone**
  because per-player passability needs a pathfinding grid per player. There is no
  wall-tower def and none is needed: `building.guard_tower` already *is* the wall
  turret, baked from achaemenid/roman `wall_tower`.
- **`elite_swordsman` renders two overlapping bodies during death.** Known,
  diagnosed, importer-level. Do not try to fix it in the game layer.
- **Ships, dragon, ballista, onager and trebuchet are static** — no walk clip.
  Trebuchet, ballista, onager and dragon carry `speed: 0` deliberately, so a
  motionless sprite never slides across the map.
- **Chat and the tech-tree page are wireframes** (PLAN.md §8.2b) and say so on
  screen. The tech tree's *renderer* is real and walks `techs.json`, which is
  deliberately empty until 9.3; chat has no transport at all, and its SEND/CLEAR
  buttons are disabled rather than made to work locally.
- **HUD portraits, minimap and control groups** are wired for colour; nothing
  else tints, because colour is in the pixels — **there is no tint shader and
  must not be one.**

---

## 8. For the art agent

See **[AGENT_ASSET.md](AGENT_ASSET.md)** for their side: recipes, bake batches,
staging, the isobake pipeline, and what they consider stable versus in flux.
That file is theirs to write and maintain — I do not edit it, the same way they
do not edit this one.

If the two documents ever disagree about the fence between us, the disagreement
itself is the thing to fix — raise it in `asset_request.md` rather than quietly
picking a side.
