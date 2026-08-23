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
4. **[BUGS.md](BUGS.md)** — the owner's playtest findings, and **the authority on
   behaviour they want**. Where a finding reverses an earlier deliberate decision
   the reversal is noted rather than argued; treat it as settled. It also carries a
   "standing hazards" section of traps left behind by *fixed* bugs, each of which
   can bite again. Cleaned 2026-08-23 from 424 lines to 170 with nothing open lost.
5. `game/data/*.json` `_note` blocks — these are long, and they are the real
   design record for the data. **Read them in full before editing that file.**
   Several encode measurements and decisions that are expensive to re-derive.

**PLAN.md used to be mojibake** (double-encoded UTF-8, so table rows could not be
matched by an exact-string edit). It is **clean, re-confirmed 2026-08-23** —
`grep -c 'â€'` finds nothing in PLAN.md or BUGS.md — so ordinary exact-string
edits work. Re-check before assuming either way; whatever fixed it could recur.
`.gitignore` is *still* mojibake in its comment banners, so the repo has not been
swept as a whole and the recurrence risk is real.

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
& $godot --path game res://dev_preview/preview_projectiles.tscn # arrow/bolt/stone in flight
```

`preview_walls` exists for the one thing **no test can judge**: which way a wall's
art faces. A wall lying across its own footprint has the same footprint, the same
origin and the same hash as one lying along it — so both axes get a screenshot and
somebody looks. It also finishes the walls before shooting, because a wall
*foundation* at nine tiles reads as a row of disconnected stubs.

`preview_projectiles` is there for the same reason, harder: a projectile carries no
damage, so its **entire** job is to be looked at and a green suite proves nothing about
it. Two things it does that are worth copying:

- **It freezes the sim before shooting** (`SimClock.stop()`). The viewport texture lags
  a frame and the step cadence lets another tick or two slip by, so a screenshot
  chasing a live 2-tick arrow lands wherever it lands — the first version could not
  tell the arrow apart from the bow in the archer's hands.
- **It prints each projectile's screen position.** They are 2–8 px; at 1:1 you cannot
  see one and cannot tell "not drawn" from "too small to notice". Crop to the printed
  coordinate at 8× and the question answers itself.

Screenshots land in `%APPDATA%\Godot\app_userdata\AgeOfDragons\`.

Two tools that are not Godot, both needing the project's Python
(`C:\Users\herman.ras\Downloads\AOD_game\tools_env\venv\Scripts\python.exe` —
Windows has no `python` on PATH, only the Microsoft Store stub):

```powershell
# Fetch 0 A.D. audio and regenerate the audio seam. Incremental and idempotent.
& $py tools\stage_audio.py --dry-run          # what it would fetch
& $py tools\stage_audio.py                    # fetch + write data/audio.json
& $py tools\stage_audio.py --manifest-only    # rewrite audio.json from what is staged
& $py tools\stage_audio.py --prune            # drop files no sound id names any more

# Attribution. A licence obligation, not a warning, and nothing runs it for you.
& $py tools\licence_audit.py

# What actually resolved, and a listen through the roster (PLAN.md 7.7 layer 4).
& $godot --path game res://dev_preview/preview_audio.tscn -- --report-only
& $godot --path game res://dev_preview/preview_audio.tscn   # plays them, with sound on
```

**A NEWLY STAGED `.ogg` IS NOT LOADABLE UNTIL `--import` HAS SEEN IT.** Godot
imports audio the same way it imports textures, so `ResourceLoader.exists()`
answers **false** for a file that is sitting right there on disk — which means
`stage_audio.py` can report 71 ids with streams while the game finds 67. The
sequence is always **stage → `--import` → run**, and skipping the middle step
looks exactly like a failed fetch.

`stage_audio.py` is **slow and that is the server, not the script** — the 0 A.D.
LFS endpoint serves a fast burst and then rate-limits to roughly one object per
20 seconds, dropping connections rather than answering 429. It retries with
backoff and skips what is already staged, so re-running it after an interruption
costs only the difference. Run it in the background and get on with something
else.

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
| **EVERY button now has an extra `pressed` connection, and it is FIRST** | `AudioManager` listens on `SceneTree.node_added` and gives every `BaseButton` in the game a click sound from one place, rather than 40 call sites each able to be forgotten. The cost: anything reading `button.pressed.get_connections()` sees `_on_any_button_pressed` at index 0. It already caused one false alarm — `preview_menus` read `[0]` and reported that PLAY and MULTIPLAYER went to the same place. **Filter it** (see `preview_menus._handlers`). Opt a button out with the `no_click_sound` group. |
| **A newly staged `.ogg` is invisible until `--import` too** | Godot imports audio like it imports textures, so `ResourceLoader.exists()` says false for a file plainly on disk. `stage_audio.py` reporting more ids with streams than `preview_audio` finds is this, every time — not a failed fetch. Always **stage → `--import` → run**. |
| **Staged atlases lag `art_work/out` silently** | A stale-but-valid atlas renders fine and is simply the wrong actor. Read `attribution.actor` out of the staged `.atlas.json` to tell — filenames and mtimes will not show it. |
| **A building missing a prop it should have** | Blender's COLLADA importer used to drop prop-point transforms, so any actor with stranded attach points quietly rendered those props at its origin. Fixed in isobake 2026-08-17, but only the five actors touched then were rebaked. Report it rather than working around it. |
| **A visual id is not a filename** | `vis.field_1` is baked as `vis.field_age2`, `vis.field_4` as `vis.farm`. The seam maps ids to paths precisely so ids outlive the art side's naming — and never rename a staged file to match, because `stage_atlases.py` will put it back. |
| **Two agents, one working tree** | Commits interleave. Check `git log` and what you actually staged; the art agent may have already committed your shared file (`asset_request.md`). |
| **Compensating for a bake defect in the game** | Tried once — the 180° facing offset, 2026-08-22 — and reverted the next day on the owner's instruction. The rule they set: an art defect gets fixed in the recipe, and a patch that must be un-applied in step with a delivery is not worth carrying for a partial result. Report it in `asset_request.md` with a picture instead. |
| **Touch does NOT take keyboard focus, so every new text field needs `TouchLineEdit`** | `emulate_mouse_from_touch = false` ([project.godot:35](game/project.godot#L35)) is *required* — `CameraRig` handles both `InputEventScreenDrag` and `InputEventMouseMotion`, so a touch arriving as both pans twice per thumb. Godot still routes raw touches to controls, but the touch path takes no focus and `LineEdit` asks for the keyboard on focus-enter. Measured on 4.7.1: focus after a screen touch = false, after a mouse click = true. Flipping the setting fixes typing by breaking the camera. |
| **A `Control` laid over the minimap swallows every tap** | The four corner buttons were a `PRESET_FULL_RECT` grid added *over* it and Godot hit-tested them first — minimap click-to-move and double-tap-to-centre were both dead while looking implemented. Check hit-test order before concluding a minimap feature is missing. |
| **`JSON.stringify` encodes a `PackedByteArray` as a STRING** — `"[1, 2, 250]"`, verified on 4.7.1 | It bit `MapData.from_dict()`, which now reads bytes, JSON's string, or a plain list. Relevant to 2.4c's saved sidecar and 12.4's save/load — the next two places sim data goes through JSON. Everything else there was already defended with `int()` because JSON numbers come back as floats; `terrain` was the one field that looked like it needed no conversion. |
| **Wall-clock timings are worthless on this workstation** | The same seed ran 41.3 s and 161.0 s; the suite swung 34 s to 110 s across four runs of identical code. Trust `test_tick_cost`, which reports per-system milliseconds. Do not conclude anything from how long a run took. |
| **The 0 A.D. checkout's media files are git-LFS POINTERS, not content** | Every `.ogg`/`.dae`/`.png`/`.pmd` on disk is a ~130-byte pointer. Worse, that repo's **index is emptied** (30,114 staged deletions) and its `.gitattributes`/`.lfsconfig` are gone from the working tree, so `git lfs pull` exits 0 having done nothing. Do **not** repair it — it is the art agent's tree and memory records that git operations there have destroyed art. The route that works is documented in `tools/stage_audio.py`: read the oid out of the pointer, fetch through the LFS batch API, write the bytes into `game/` and never into the checkout. |
| **`gitea.wildfiregames.com` is behind an Anubis proof-of-work bot wall** | A plain HTTP client gets an HTML "Making sure you're not a bot!" challenge instead of JSON, which is easy to misread as a broken endpoint. A **`git-lfs/...` User-Agent is allowed through** — that one header is the whole difference. |

---

## 7. Where things stand

**Data is complete for the v1 roster:** 31 building defs (19 non-wall plus the
twelve wall/gate pieces) with dense four-age skin maps, 28 unit defs (21 military
and civilian plus seven fauna), all footprints measured (each baked atlas resolved
back through `attribution.actor` to its 0 A.D. template, parent chain walked to
`<Obstruction><Static>`, max taken per axis across the four ages).

**331 atlases staged.** 76 test files, **1232 tests, 199,129 assertions, all
passing** — measured 2026-08-23, not quoted. The previous figures here (293/71/1163)
were stale; re-measure rather than trusting this line, it is the first thing to rot.

**Working end to end:** age skins (Briton → Gaulish → Iberian/Achaemenid →
Roman), per-player colour selection from eight baked atlases, age-gated train and
build menus, a paged build grid, captioned portraits, production queue, a real
timed age-advance, fog of war, an enforced population cap, conquest win
conditions, the PlayTest AI, **two-device LAN multiplayer validated on hardware**
(PLAN.md §12.1 a–g), and the minimap's four corner pages — a working market, chat
and tech-tree wireframes, and settings (§8.2b).

### The one standing order that outranks other tuning

**"Every unit feels too fast"** (BUGS.md, owner-reported 2026-08-21 from a real
two-device phone match) is the most valuable open item and it is **parked
deliberately**. It is a balancing number, not a defect, and it wants doing as one
pass over every unit's `speed` in the data — so **nothing gets tuned piecemeal
before it**, and a nudge to whichever unit is on screen is the wrong move even
when it looks obviously right. Only the owner can judge it, and the queue behind
it (walls, chokepoints, three hostile predators, fleeing deer, driven livestock)
keeps changing what "too fast" means.

### Owner-reported and open (BUGS.md is authoritative)

Listed here so this file does not read as though the game were finished. Do not
re-diagnose these from scratch — each already has a diagnosis.

- **Double-tap to clear the selection is unreliable on the phone**, and the call is
  **not** to keep tuning the gesture: the fix chosen is an **[X] button** at the top
  of `SelectionPanel`, visible only while something is selected (PLAN.md 8.8). The
  root cause is `InputRouter.TAP_SLOP`/`TAP_TIME_MS` — a thumb wobbles where a mouse
  does not, so a second tap the router scores as a small drag never reaches the
  detector — and improving the router is a separate job. **The gesture stays.**
  Desktop was never affected: right-click clears.
- **A forfeit is announced as an elimination.** The snapshot carries the fact of a
  defeat but no *reason*, so a resign and a disconnect both read "All opponents
  eliminated". Needs a reason field beside `winner_id` and a decision about how many
  reasons are worth naming.
- **The soft keyboard covers the address field** and **a tap cannot place the caret**
  in a text field. Both are consequences of there finally being a keyboard, both are
  survivable in the debug screen, and both bite the moment a real lobby lays out a
  field. See the `TouchLineEdit` row in §6.
- **The AI's biggest gap: a build step gives up when short of resources.** p2 abandoned
  a barracks 73 wood short, never built one, and died holding 950 wood — a person waits
  for the wood, and the timeout should not count affordability. Also open:
  `MAX_PLACEMENT_RADIUS` 26 → 14 now blocks 6×6 placements, and **nobody has checked
  what `AISystem`'s standing order 3 still needs to do** now that `CombatSystem`
  re-targets (which itself reversed PLAN.md 4.13 — see BUGS.md "Reversed decisions").
  The AI-vs-AI baseline table in BUGS.md exists so a regression is visible; keep it.
- **No wall corner piece** — 0 A.D. has none either, it puts a `wall_tower` at every
  corner and we already have that art as `building.guard_tower`. What is missing is
  anything that *detects* a corner.

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
  **A GATE IS AN UPGRADE, NOT A PLACEMENT** (2026-08-22). It shipped as a menu
  entry placed by tapping and the owner found the hole in a day: a gate is [9,2],
  `PlaceBuildingCommand` carries no facing and never transposes a footprint, so
  every tap-placed gate lay east-west and **a north-south wall could not have one
  at all**. Now all three gates are `buildable: false` and you tap a finished long
  segment and press its upgrade button — the wall already knows its axis and the
  gate inherits it, so there is nothing to rotate. `BuildingDef.upgrades_to` +
  `UpgradeBuildingCommand` + `SimWorld.convert_building`, which mutates in place
  and keeps the entity id (a respawn would empty the panel the player just pressed
  and report a *destruction* to every other client).
  Worth remembering as a class: **the placement path has exactly one orientation**,
  so anything non-square that needs a second one cannot be tap-placed. Walls get
  theirs from the drag; the gate now gets it by inheriting.
  **FINISHED SHORT PIECES MERGE** (2026-08-22, the owner's design): on completion a
  segment looks along its axis, and a contiguous stretch of same-tier neighbours that
  adds up to a declared length becomes that one piece — `WallMerge`, called from
  `BuildSystem._finished`. Only COMPLETE pieces (absorbing a foundation would delete
  what a builder is walking to), the survivor is the piece at the low end of the run so
  nothing moves a corner backwards, health is the exact sum, and it is silent and free.
  Most of its 21 tests are about what must *not* be merged, because every one of those
  mistakes presents as a building that vanished. A merged long can then be upgraded to a
  gate, which is how a wall built in short pieces gets a door at all.
  What remains unbuilt around them: **no corner piece** (0 A.D. has none either — it
  puts a `wall_tower` at every corner, which is art we already have as
  `building.guard_tower`; what is missing is anything that detects a corner), **no
  diagonal walls** (six of the eight baked directions are unreachable — a [9,2] box does
  not tile a square grid at 45°),
  **no garrison on a wall** (4.8), and **an open gate is open to everyone**
  because per-player passability needs a pathfinding grid per player. There is no
  wall-tower def and none is needed: `building.guard_tower` already *is* the wall
  turret, baked from achaemenid/roman `wall_tower`.
- **EVERY UNIT, SHIP, ANIMAL AND SIEGE ENGINE IS BAKED 180° BACKWARDS, and this is
  the art side's, not ours. Do not patch it again.** The zeroad adapter turns every
  subject 180° from the direction the atlas labels it; 81 of 171 recipes cancel it with
  `yaw_offset_deg = 180.0` and 36 do not. **A game-side compensation was written and
  reverted inside a day** (2026-08-22 → 23) — `directions_reversed` in `visuals.json`
  setting a half-turn offset per atlas. It fixed idle and walk; the owner still saw an
  attacking unit facing the wrong way and called it: *"undo the reverse changes… i dont
  want to waist any more time on patching a known root cause."* It is out, and the
  standing instruction is that the fix is a re-bake (PLAN.md §13.2 item 10,
  `asset_request.md` for the request and the 36-recipe list). If you find yourself
  reaching for `Iso.sim_facing_to_sprite` or a per-atlas offset, this is the paragraph
  saying somebody already did and it was not wanted. What the exercise established and
  is worth keeping: the `unit.knight` chart is 180° out **uniformly across idle, walk
  and attack**, so one recipe line per actor covers the attack clip too. The sim side
  is fine — `CombatSystem` sets `facing` toward the target every tick it swings.
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
- **AUDIO IS BUILT (2026-08-23), and the gap left is BYTES, not code.** PLAN.md
  §7.5 claimed an `AudioManager` existed for months when there was no such file
  and zero call sites; that is now real — `src/autoload/audio_manager.gd`,
  `src/view/match_audio.gd`, `data/audio_map.json`, `tools/stage_audio.py`, and
  131 sound ids mapped to 0 A.D. sound groups. Four things worth knowing before
  touching it:
  - **The sim does not and must not make sound.** `src/sim/` cannot load an asset
    or touch the tree, and a sim that made noise would make it during a headless
    AI-vs-AI run. `MatchAudio` **diffs consecutive snapshots** instead, which also
    means it works identically on a host and a joined client with no event
    forwarding. Its header documents the three traps in doing that (the first
    snapshot must be swallowed, absence from `updated` is ambiguous between death
    and fog, and a remembered entity carries no live fields).
  - **`task_target_id` is NOT on the wire**, so the sound a villager makes is
    found by *position* — nearest resource node or building within four tiles.
    Do not add the field for audio: 12.1f spent an optimisation pass removing
    per-entity field names, and a field present on working units and absent on
    idle ones splits every unit into two shape tables.
  - **Silence is a legitimate state and is reported.** An empty `streams` list
    plays nothing; an *undeclared* id calls `push_error` once. Keeping those
    apart is the whole contract, and `GameDataRegistry.silent_sfx_ids()` names
    the first case so nobody has to diagnose it by ear.
  - **`game/assets/audio/` is gitignored build output** like the atlases, and the
    fetch is rate-limited by 0 A.D.'s server (see §3). A clean checkout has no
    audio and the game is expected to run silently — the suite asserts the seam,
    never that bytes are present.

---

## 8. For the art agent

See **[AGENT_ASSET.md](AGENT_ASSET.md)** for their side: recipes, bake batches,
staging, the isobake pipeline, and what they consider stable versus in flux.
That file is theirs to write and maintain — I do not edit it, the same way they
do not edit this one.

If the two documents ever disagree about the fence between us, the disagreement
itself is the thing to fix — raise it in `asset_request.md` rather than quietly
picking a side.
