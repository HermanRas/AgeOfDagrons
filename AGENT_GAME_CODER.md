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
| `art_work/out/` | baked atlases; build output. **It is not in this repo** — the path is machine-local and declared in `tools/isobake.local.toml`, today `C:\Users\herman.ras\Downloads\AOD_game\art_work\out`. Read it to tell staged art from fresh |
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
5. **[PROGRESS.md](PROGRESS.md)** — the phase table, added 2026-08-23. Status only,
   no reasoning, and it says so itself: where it disagrees with PLAN.md, PLAN.md
   wins and PROGRESS.md is the one to fix. `asset_request.md`'s art priority
   ordering is derived from it, so the art agent reads it too. **It goes stale
   first** — its header figures (suite size, APK size) and its "the single item
   most worth doing is the unit-speed pass" line were both overtaken within hours
   of being written.
6. `game/data/*.json` `_note` blocks — these are long, and they are the real
   design record for the data. **Read them in full before editing that file.**
   Several encode measurements and decisions that are expensive to re-derive.

**PLAN.md used to be mojibake** (double-encoded UTF-8, so table rows could not be
matched by an exact-string edit). It is **clean, re-confirmed 2026-08-27** — that
grep now finds nothing in *any* `.md` in the repo, and `.gitignore`'s comment
banners, which this file recorded as still broken, are clean too. So ordinary
exact-string edits work everywhere. Re-check before assuming either way; whatever
fixed it could recur.

**A separate thing that looks identical and is not:** PowerShell's `Get-Content`
decodes these files as ANSI, so *reading PLAN.md through the shell prints mojibake
for a file that is fine on disk.* Use the Read/Grep tools to judge encoding; a
`Get-Content` dump is not evidence.

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
& $godot --path game res://dev_preview/preview_garrison.tscn   # 4.8/4.9, six screenshots

# The facing trio — how a re-baked atlas gets checked (see §7, the mirror item)
& $godot --path game res://dev_preview/preview_facing_chart.tscn -- --units unit.swordsman,unit.knight
& $godot --path game res://dev_preview/preview_combat_facing.tscn  # eight attackers in a ring
& $godot --path game res://dev_preview/preview_work_facing.tscn    # gathering, and hitting a building
```

`preview_facing_chart` draws one actor at all 8 sprite directions × 3 clips with no
simulation involved — just `EntityView` and the atlas. `--units` takes any id, so nothing
needs editing to chart a new one.

**READ COLUMNS 2 AND 6, NOT ONLY 0 AND 4.** The agreed check used to be "column 0 (S)
shows a face, column 4 (N) a back", and that check **cannot detect a mirror** — S and N
are exactly the two columns a reflection about the N–S axis leaves alone. It passed a
mirrored roster on 2026-08-27 and cost a re-bake. **Column 2 (W) must face screen LEFT and
column 6 (E) screen RIGHT**, and all four have to hold.

`preview_work_facing` covers the two cases nothing else did: a ring of villagers mining one
node, and a ring of cavalry hitting one building. It prints, per unit, the facing the sim
holds against the one `SimUnit.facing_toward` would pick right now — so **a unit nothing
ever turned is reported as STALE**, which is a different fault from a unit turned the wrong
way and wants a different fix.

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

`preview_garrison` earns its place the way `preview_projectiles` does, and it proved it on
the first run: **it found a bug 60 green tests had missed** (a tower shooting the
livestock — see §6) purely because the log said what the tower was aiming at. Three things
worth copying out of it:

- **It refuses ground that has a STRANGER standing near it**, not just ground that is
  unoccupied. `can_place_building` asks the *map*, and units are not in map occupancy — so
  the first version put the tower one tile from a **bear**, which has 130 hp, and
  nearest-target-wins meant the raider five tiles out was never touched. The measurement
  was worthless and every assertion in it was true.
- **It prints the declared damage AND the landed damage.** A guard tower with three archers
  declares 14 and lands 13, because the target is a militia and militia carry pierce
  armour. Printing one number would have read as the bonus arithmetic being wrong.
- **It shoots the panel one phase AFTER pressing the button.** §5's rule is not only about
  commands: pressing an `expands` action and photographing the same frame produced a panel
  with an **empty detail grid** while the log correctly listed four slots in it.

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
| **`some_array as Array[int]` SILENTLY FAILS on a variable — it only works on a literal** | `[picked] as Array[int]` is fine and is what `GameScene` does; `ids as Array[int]` where `ids: Array` is an untyped parameter produces an untyped array, and the *callee* then rejects it at runtime with "the array of argument 1 does not have the same element type". Nine tests died on one helper this way. Build it element by element, the same conversion every `Command.from_dict` does. Worth knowing that the harness's **script-error spy** is what caught it — the tests reported FAIL rather than passing with zero assertions, which is exactly the case that guard exists for. |
| **PS 5.1 splits a here-string into git pathspecs** | Write the commit message to a file, `git commit -F <file>`. Never pipe a here-string. |
| **`Set-Content -Encoding utf8` adds a BOM** and has corrupted `project.godot` | Use .NET `WriteAllText`/`WriteAllLines` with `UTF8Encoding($false)`. |
| **A new `class_name` is invisible until `--import`** | Run it, then the suite. |
| **EVERY button now has an extra `pressed` connection, and it is FIRST** | `AudioManager` listens on `SceneTree.node_added` and gives every `BaseButton` in the game a click sound from one place, rather than 40 call sites each able to be forgotten. The cost: anything reading `button.pressed.get_connections()` sees `_on_any_button_pressed` at index 0. It already caused one false alarm — `preview_menus` read `[0]` and reported that PLAY and MULTIPLAYER went to the same place. **Filter it** (see `preview_menus._handlers`). Opt a button out with the `no_click_sound` group. |
| **A newly staged `.ogg` is invisible until `--import` too** | Godot imports audio like it imports textures, so `ResourceLoader.exists()` says false for a file plainly on disk. `stage_audio.py` reporting more ids with streams than `preview_audio` finds is this, every time — not a failed fetch. Always **stage → `--import` → run**. |
| **Staged atlases lag `art_work/out` silently** | A stale-but-valid atlas renders fine and is simply the wrong actor. Read `attribution.actor` out of the staged `.atlas.json` to tell — filenames and mtimes will not show it. |
| **A building missing a prop it should have** | Blender's COLLADA importer used to drop prop-point transforms, so any actor with stranded attach points quietly rendered those props at its origin. Fixed in isobake 2026-08-17, but only the five actors touched then were rebaked. Report it rather than working around it. |
| **A visual id is not a filename** | `vis.field_1` is baked as `vis.field_age2`, `vis.field_4` as `vis.farm`. The seam maps ids to paths precisely so ids outlive the art side's naming — and never rename a staged file to match, because `stage_atlases.py` will put it back. |
| **`Diplomacy.is_enemy` is "MAY I attack that", NOT "am I at war with that"** | The two differ on gaia, and anything that acquires a target **unasked** needs the second question. A sheep *may* be attacked — hunting is how a deer becomes food — so 4.9's tower auto-acquire shipped shooting the livestock, including a player's own herd (a herded sheep is still gaia's; `herded_by` is separate from `owner_id` by design). It presented as a tower that did not work: nearest-target-wins spent every shot on an animal two tiles away and never reached the raider five out. `CombatSystem._is_at_war_with` is the predicate now, and **`AISystem._nearest_enemy` has kept its own copy for exactly this reason all along** — its comment says so and it was right. |
| **Two agents, one working tree** | Commits interleave. Check `git log` and what you actually staged; the art agent may have already committed your shared file (`asset_request.md`). |
| **A verification that cannot see the fault it is for** | The facing check was "column 0 a face, column 4 a back" — **the two columns a mirror about N–S leaves alone**. A mirrored roster passed it twice and a 242-atlas re-bake was spent on the wrong diagnosis. Before trusting any check, ask which failures it is *blind* to; a green check on a fault it cannot express is worse than no check, because it ends the investigation. |
| **A facing that is drawn wrong is not necessarily set wrong** | Two different faults, two different owners. `preview_work_facing` prints the sim's `facing` beside what `SimUnit.facing_toward` would pick now: **STALE means nothing turned the unit** (a sim gap — until 2026-08-27 only `MovementSystem` and `CombatSystem` ever wrote `facing`, so gathering and building never turned anybody), while numbers that agree with a picture that disagrees is the atlas. Settle which one before writing anything. |
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

**342 atlases staged.** 82 test files, **1417 tests, 202,627 assertions, all passing** —
measured 2026-08-28 after the art delivery was wired, not quoted. **RE-MEASURE RATHER THAN
TRUSTING THIS LINE**; it is the first thing in the file to rot, and every previous figure
here (1395/82, 1353/80, 1272/78, 1232/76, 293/71/1163) was stale within days.

**Working end to end:** age skins (Briton → Gaulish → Iberian/Achaemenid →
Roman), per-player colour selection from eight baked atlases, age-gated train and
build menus, a paged build grid, captioned portraits, production queue, a real
timed age-advance, fog of war, an enforced population cap, conquest win
conditions, the PlayTest AI, **two-device LAN multiplayer validated on hardware**
(PLAN.md §12.1 a–g), and the minimap's four corner pages — a working market, chat
and tech-tree wireframes, and settings (§8.2b).

**4.8 GARRISON AND 4.9 CLOSED 2026-08-27.** Tap your own tower or castle with units in hand
and they walk in; `garrison_cap` finally means something after being declared on all 31
buildings since 0.4 and read by nothing. Five things worth knowing before touching it:

- **Who: the two towers (5) and the castle (15), and nothing else.** The owner ruled walls
  out by name and the "only" was exclusive, so town centre 15, barracks 10 and monastery 10
  all went to **0** — IDEA.md 4.9's sketch numbers, which nothing had ever read. **A
  villager under attack has nowhere to hide, deliberately**: garrison here makes a tower
  shoot harder, it is not a bunker.
- **`SimUnit.garrisoned_in` is the first field that takes an entity OFF THE MAP without
  despawning it.** It stays in `entities` (so population still charges for it), leaves
  `SpatialHash` (so nothing can find, target or tap it), and is **skipped by
  `SnapshotSystem.build` entirely** — which is where "removed from the world map" actually
  happens, and it buys the sprite release, the deselection and the fog circle for one line.
- **BUILDINGS CAN ATTACK NOW**, which nothing could before: `BuildingDef` carries UnitDef's
  five attack fields under the same JSON keys, and `CombatSystem.process_tick` has a second
  branch. Only three defs have one (watch 6/6, guard 8/7, castle 12/8, all cooldown 20).
  The garrison bonus is **half each archer's damage, floored, added once per shot** —
  `attack.range > 0` is the "is an archer" test, so every melee unit gives 0 for free.
- **The range ladder is design content, not tuning.** Infantry is out-ranged by every tower;
  **siege out-ranges every tower**, which is the only answer to a loaded castle that does
  not cost an army. `unit.galleon` at 7 is the one deliberate exception and it is a ship.
- **A building MUST auto-acquire** — nothing can order one to attack — so §4.13's
  no-auto-acquire rule does not apply and the two share no code. That is also where the one
  real bug was: see the `Diplomacy.is_enemy` row in §6, found by `preview_garrison` and not
  by any of the 60 tests written alongside it.

**RALLY POINTS followed the same day** (owner: *"happy for current ejection if no waypoint
is set, if a way point is set the ejected units will queue a walk to destination"*).
`SimBuilding.waypoint`, set by **selecting one of your own buildings and tapping bare
ground** — a gesture that previously did nothing but clear the selection — and shown as a
`WaypointFlag`, a procedural pole-and-pennant in the player's colour (*"use shape
placeholder"*, so no bake is waiting on it). Four things worth knowing:

- **It covers TRAINED units too, on the owner's call**, and that is the half that makes it
  useful: a new archer appearing behind the archery range is the identical defect for the
  identical reason. `SimWorld.send_to_waypoint` is one function with two callers
  (`ungarrison_unit`, `ProductionSystem`) so the two can never drift.
- **`find_free_adjacent`'s top-edge sweep was NOT changed**, and that was the decision:
  everything leaving any building appears up-screen of it, and a rally point makes that
  opt-out per building rather than altering a function every building shares.
- **An unreachable rally point is self-correcting, and that is load-bearing.** An empty
  route retires the task and the unit stands where it came out — which is what stops a
  **dock** with a landward flag walking its fishing ships onto the beach, the exact bug
  reported on 2026-08-23 as *"boats spawn and sail on land, its very funny"*.
- **An enemy's rally point is the only pure INTENTION on the wire**, and the only field
  `_entry_for` filters by owner. It is **blanked, not erased** — erasing would split every
  building into two wire shapes (12.1f).
- **STOP CLEARS IT** (owner, same day): the verb means two things now, chosen by the
  selection — halt these units, or take this building's rally point down. They cannot
  collide, since `movable_selection()` is units-only and `waypoint_target()` demands exactly
  one building. **Reusing the button is what made it affordable**, and it cost something
  anyway: **`repair` is now LAST in a building's action row**, so a castle with a rally
  point (9 verbs against `MAX_ACTIONS`' 8) sheds the disabled placeholder instead of
  `destroy`. **The next verb added to `_building_actions` drops a real command** — that
  slot is spent.

**8.8'S [X] CLEAR-SELECTION BUTTON, 2026-08-28.** `ClearSelectionButton` — a drawn disc
at the top-left of `SelectionPanel`, emitting `clear_requested` into
`GameScene._on_clear_pressed`. It closes the oldest open owner-reported bug without
touching the thing that caused it: the double-tap gesture and desktop's right-click both
stay, and this is a third route to the same verb that a thumb cannot miss. Three things
worth knowing:

- **ITS SIZE WAS DERIVED, NOT CHOSEN, AND THE HUD'S LEFT EDGE NOW HAS ZERO SLACK.** The
  control-group stack runs to y 364 (`12 + 5×64 + 4×8`) and the selection panel is
  bottom-anchored with a ceiling of 244 (`20 margin + 72 portrait + 4 + 2 grid rows`,
  two rows being `MAX_ACTIONS` 8 in four columns) — so on the 648 px canvas there are
  **exactly 40 px** between them, and `SIZE` is 40 with the row's separation pinned at 0.
  The `aspect = "expand"` stretch keeps 648 as the vertical base on a phone too, so this
  is the real budget on hardware, not a desktop artefact.
- **Overflowing it fails SILENTLY, which is why there is a test.** The control-group stack
  is added to the HUD *after* the panel, so Godot hit-tests it first: a button pushed under
  the fifth slot keeps drawing and stops taking taps in the overlap. That is the minimap
  corner-button trap in §6 exactly. `test_the_tallest_panel_still_clears_the_control_group_stack`
  fills **both** grids to their caps rather than measuring whatever def has the most verbs
  today — a fixture producing seven actions would measure one grid row and pass.
- **One press exits a placement first, where right-click takes two.** Right-click is a
  general "not that" and resolving one thing per press suits a key that is always there; a
  button marked [X] on a panel means the player is finished with the selection, so leaving
  the villager selected with the ghost gone would read as a half press.

**THE 2026-08-28 ART DELIVERY, WIRED THE SAME DAY.** 342 atlases staged, and three of the
four pieces needed game-side work:

- **GATES HAVE AN OPEN POSE** (owner, 2026-08-27). `AtlasEntry.OPEN_ANIM`, chosen in
  `GameView._building_anim()`. **`static` IS the closed pose** — the art side's design, and
  the reason this was five lines: a gate at rest is shut, so an atlas with no `open` clip
  draws what it always drew and `resolve_anim` falls back with no special case. Two traps
  worth knowing: **`gate_locked` rides EVERY building entry and defaults false**, so
  `not gate_locked` alone asks every house in the game for a clip it has not got —
  `is_gate` comes off the DEF (`def_id` is on the wire, and 12.1f spent a pass *removing*
  per-entity fields). And **`vis.wall_wood_gate` is the one gate whose four ages are not
  one file** — 1–2 German palisade, 3–4 Roman siege works, after the art side re-pointed
  the age-3 tier — so a check that reads `def.visual` alone sees one file and misses the
  other. There are **three gate defs, not five**: age 1 has no gate, so `vis.wall_gate` is
  staged and referenced by nothing, deliberately.
- **THE WAYPOINT FLAG IS BAKED ART NOW** and the procedural pole is gone. One
  `visuals.json` entry with `"colours": true` buys all eight tints; `WaypointFlag` draws
  an `EntityView` and **keeps the tile diamond**, because a sprite says a flag is near here
  and only the diamond says *which tile*. It drives its own frame clock — it is not in
  `EntityViewPool`, so without `_process` calling `advance()` it would sit on frame 0 and
  look exactly like a static bake.
- **The wolf and the arrow needed nothing at all** — re-skinned in place, which is what
  `EntityView.play_anim`'s per-clip fallback is for. The wolf is 1 of the 6 species in
  [P1]; the other five are still one static pose apiece and still slide.
- **`vis.onager_packed` / `vis.trebuchet_packed` are staged and DELIBERATELY NOT DECLARED.**
  4.13's pack/unpack state machine does not exist — `SimUnit` carries no deploy state — so
  a declared id would be referenced by nothing and read later as art that failed to land.
  They go in with the machine, in one commit.

**Phase 6 closed 2026-08-23** and this list never said so: wildlife roams
and **flees** (`WildlifeSystem`, hp-watched rather than plumbed through an attacker),
**a deer is hunted rather than harvested** — it had to become a `SimUnit` to move at
all, since `MovementSystem` skips nodes — **herding** (walk within 4 tiles of a sheep
or cow and it takes your orders; the animal stays gaia's and only `SimUnit.herded_by`
moves, which is what kept `GatherSystem` and `WinConditionSystem` out of it), and
**fishing**: `res.fish` in shallow water, `ResourceDef.domain` + `SimMap.can_place(rect,
domain)` splitting sea placement away from `can_place_building`, and
`building.dock` now `requires_shore`. **Audio landed the same week** (§7.5, below).

### The speed pass is DONE — and it left two things behind (2026-08-23, `962b1c5`)

**"Every unit feels too fast" is closed.** It was the oldest and most valuable
open item, parked from 2026-08-21 until the owner could judge it, and they did:
*"if we reduce the unit speed by 50%…"*. **Every unit's `speed` was halved in one
pass** — villager 200 → 100 and everything else by the same factor, so the
relative pacing `units.json` describes is untouched; the four `speed: 0` units
stayed 0 and odd values rounded away from zero. **The owner playtested it on 2026-08-27
and confirmed it: *"sound and speed is much better."*** PROGRESS.md still lists this as
the top open item and is stale; PLAN.md §15 has been rewritten around what it left behind.

Two consequences were recorded in BUGS.md rather than smoothed over, and neither
is a reason to undo it:

1. **It cut the ECONOMY, not just the walking.** A gather trip is walk-out,
   extract, walk-home, deposit, so halving speed roughly halves resource income,
   and worse the further the node. **If the game now feels slow rather than
   calmer, `gather_rate` is the lever, not `speed`.** Owner's call, not ours.
2. **It broke the AI-vs-AI baseline** by amplifying the already-open "a build step
   gives up when short of resources" bug until *both* AIs reach their attack step
   with no army. Seeds 3 and 5 got ~6% longer with the same winners; **seed 4 went
   from "p2 wins at t7776" to unresolved**, and not because of the 12,000-tick
   window — it does not resolve at 20,000 either. Seed 4 was the only seed p2 ever
   won, which is exactly what made that table evidence rather than an artefact of
   the script favouring player 1. Keep the table; the tick log is in BUGS.md.

**The sound repetition reported in the same breath was NOT caused by speed** and
would not have been fixed by halving it. While a unit holds a work or attack
animation the repeat rate is set by the audio throttle and by nothing else — a
stationary villager chopping does not care how fast she walks. See the audio
bullet below for the two-limit fix that did answer it.

### Owner-reported and open (BUGS.md is authoritative)

Listed here so this file does not read as though the game were finished. Do not
re-diagnose these from scratch — each already has a diagnosis.

- ~~**Double-tap to clear the selection is unreliable on the phone.**~~ **ANSWERED
  2026-08-28 by the [X] button**, §7. `InputRouter.TAP_SLOP`/`TAP_TIME_MS` is still the
  root and is still a separate job. Awaiting the owner's device confirmation.
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
  for the wood, and the timeout should not count affordability. **The speed halving
  amplified this into the baseline's worst result** (seed 4 no longer resolves), so it
  has gone from a known flaw to the thing standing between the AI table and being
  evidence again. Also open: `MAX_PLACEMENT_RADIUS` 26 → 14 now blocks 6×6 placements,
  and **nobody has checked what `AISystem`'s standing order 3 still needs to do** now
  that `CombatSystem` re-targets (which itself reversed PLAN.md 4.13 — see BUGS.md
  "Reversed decisions"). The AI-vs-AI baseline table in BUGS.md exists so a regression
  is visible; keep it.
- **No wall corner piece** — 0 A.D. has none either, it puts a `wall_tower` at every
  corner and we already have that art as `building.guard_tower`. What is missing is
  anything that *detects* a corner.

**Three owner requests filed 2026-08-23 and deliberately NOT built** — PLAN.md §13.2
items 12, 13 and 14. Each was researched before filing, so the entry names where it
plugs in; read the row rather than re-deriving it:

- **12 — double-tap a unit selects every unit of that type ON SCREEN.** Both halves
  exist: `DoubleTapDetector` is real, and "on screen" is literally
  `GameView.units_in_box()` handed the viewport's rect instead of a dragged one
  ([game_scene.gd:1640](game/src/view/game_scene.gd#L1640)). Only the `def_id` filter is
  missing. **Do not build it on the ground-tap detector** — that one is entangled with
  the open double-tap-to-clear bug, so `InputRouter.TAP_SLOP` is arguably a prerequisite
  here. That is the *opposite* of the call made for 8.8, where a button sidesteps the
  router; nothing sidesteps this.
- **13 — an arrow should leave the bow when the fire animation finishes.** Damage is
  explicitly out of scope. `CombatSystem` spawns on the tick its cooldown hits zero
  while `EntityView` advances frames at the atlas' declared fps — two clocks, drifting
  by design. Recommended fix is one line in the *view*: drive the attack clip's rate
  from `attack_cooldown_ticks`. Rejected: authoring cooldowns from clip lengths, which
  would make balance a function of the bake.
- **14 — a finished resource building puts its builders to work on what it collects.**
  The farm half already does this ([build_system.gd:74](game/src/sim/systems/build_system.gd#L74),
  since 2026-08-17), and `BuildingDef.drop_off` already declares which kinds each
  building serves, so "gold or stone" needs no new data. Four traps recorded in the
  row: it **must be deterministic or it is a desync**; its priority against
  `_next_foundation` is a real decision (if the resource scan wins, finishing a lumber
  camp mid-wall-drag pulls that builder off the wall); `_nearest_node` searches the
  whole map where `_next_foundation` is bounded by `SAME_WORK_RADIUS` (10) and wants the
  same bound; and `building.town_center` declares all four kinds without being a camp,
  so keying off "has a `drop_off`" would auto-task builders at every town centre.

### Known gaps — do not work around these silently

- ~~**Only `red` and `yellow` colour bakes are trustworthy.**~~ **CLOSED 2026-08-27** —
  **develop against any player.** What is worth keeping is the failure shape: for months
  60 colour atlases were *stale, not absent* — present, parsing, drawing, and wrong,
  because pipeline defects were fixed mid-roster. `stale_colour_atlases()` and
  `missing_colour_atlases()` are the queries that catch it and both are empty; a
  mid-roster pipeline fix is not a rare event, so keep them. **Their known blind spot:
  `stale_colour_atlases()` compares the eight colours against each other and ignores the
  base**, so eight agreeing at build 36 look healthy under a base at 37. A
  base-ahead-of-its-colours check is game-side work that has not been written.
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
  **no garrison on a wall — now a DECISION, not a gap** (the owner ruled walls out of 4.8
  by name on 2026-08-27, so 0 A.D.'s eight turret points per medium wall stay unused; the
  wall turret you *can* garrison is `building.guard_tower`), and **an open gate is open to everyone**
  because per-player passability needs a pathfinding grid per player. There is no
  wall-tower def and none is needed: `building.guard_tower` already *is* the wall
  turret, baked from achaemenid/roman `wall_tower`.
- ~~**THE UNIT ATLASES ARE MIRRORED, NOT ROTATED.**~~ **CLOSED 2026-08-28**, in the
  pipeline and not in any recipe: isobake `e6fc052` negated the compass step in
  `directions.py:yaw_deg()`. `ORDER_8` is documented clockwise from screen-down and
  `+i * 45°` about +Z walks it counter-clockwise, so the render swept the opposite way to
  the labels it was writing. 252 atlases at build 38, staged and verified. **Nothing in
  `game/` changed**, which was the whole point of the 2026-08-22 revert.

  Three things outlived it and are the reason this entry is still here at all:

  - **A reflection is not a rotation, so no `yaw_offset_deg` could ever have fixed it** —
    a half-turn only slides the mirror's axis from E–W (reads as "faces backwards") to
    N–S (reads as "left and right swapped"). The 180° on the 82 recipes **stayed on** and
    is half the correction, because index 0 is a fixed point of the sign flip. I asked
    for its removal twice and was wrong both times.
  - **The walls were mirrored all along**, and `preview_walls` passing was not evidence
    they were not: each swapped pair has the same silhouette, so the swap changes which
    face of the palisade is lit and never the direction it lies. An achiral subject
    cannot fail a chirality test.
  - **`directions = 1` atlases cannot be reached by any of this**, and that is worth
    knowing because it was nearly forgotten: `yaw_deg` returns the offset alone at index
    0. The 89 buildings were correctly excluded from the 242, and when 21 ground pieces
    were later reported as "still mirrored, all `directions = 8`" they turned out to be
    `stored = 1` to a file — a batch that was proposed and did not need running.

  The check that can see this fault is in §3 and is **all four columns**. Two of them
  cannot see it, which is the §6 row about verifications that are blind to what they are
  for; this is where that row came from.
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
  - **THE REPEAT RATE IS TWO LIMITS, NOT ONE** (added `962b1c5`, and PLAN.md §7.5
    decision 3 still describes only the first — it predates this). `throttle_ms` is
    the gap for **one source**, a unit's own cadence, and `MatchAudio` passes the
    entity id so it has something to key on; `crowd_ms` is the gap for the sound
    **at all**, however many units are making it. One global number cannot do both
    jobs: small, it lets a single unit fire eleven times a second; raised to 2000 ms,
    it reduces a battle of ten swordsmen to one clang every two seconds while ten men
    visibly swing. The rates now come from `units.json`'s real `cooldown_ticks`.
  - **Music defaults to 0.5**, on the owner's report that they had to drop it ~80% to
    hear anything else. A saved value still wins, so anyone who has moved the slider
    keeps theirs.
  - **`game/assets/audio/` is gitignored build output** like the atlases, and the
    fetch is rate-limited by 0 A.D.'s server (see §3). A clean checkout has no
    audio and the game is expected to run silently — the suite asserts the seam,
    never that bytes are present.
- **Three gaps PLAN.md §15 records rather than files**, all from the 2026-08-23 naval
  work and all cheap to trip over: **a dock built inland before that day stays inland**
  (`requires_shore` gates new placement only, so an old dock trains ships that cannot
  deliver); **naval combat does not exist at all** — ships float and path, transports
  have no load/unload, and nothing has ever fought at sea; and **a static destroyed
  behind the fog stops being sent** rather than leaving AoE's stale ghost, which would
  need a per-player last-seen copy of every static (§11.4).

### What PLAN.md §15 says is next

1. **RE-TUNE THE AI FOR THE HALVED SPEED — up next, the owner's call on 2026-08-27**
   after playing the change: *"sound and speed is much better. We may need to revisit the
   AI actions to adjust after the speed fix to get consistent game resolutions or identify
   why its not completing."* The symptom is a match that does not finish; the cause is
   already diagnosed and is **not** the speed itself — halving it doubled both legs of
   every gather trip, which amplified the open "a build step gives up when short of
   resources" bug until both AIs reach their attack step with no army. **The first
   question is which lever**: the build step (a person waits for the wood, and the
   timeout should not count affordability), `gather_rate` (the economy, the owner's
   call), or the AI's step budget. **Do not move two of them at once** or neither is
   measurable — the BUGS.md baseline table is the instrument, and all five seeds want
   re-measuring either side of the change.
   *(This item is also now stale on one point: the AI ladder was re-measured on
   2026-08-27 after buildings gained an attack, since the AI builds towers. Every winner
   held; `easy v normal` went t11366 → t18351. The new table is in BUGS.md, and it is the
   baseline any AI change is measured against.)*
2. **2.4d Archipelago** (§11.6). The content is nearly free — `PREDATORS` is keyed by
   map type and read with `.get(type, {})`, so an unlisted type gets no predators
   without a line of code. The work is that `MapValidator` requires every start to
   reach every other **by land**, which an archipelago fails by definition, so that
   claim has to *change* rather than relax.
3. **9.3 `TechSystem`** — the biggest genuinely unstarted phase, and it moved up because
   ages now cost resources (2026-08-27), which makes the tech tree what the age ladder is
   *for*. `techs.json` is deliberately empty, the tech-tree page already renders whatever
   is in it, every AI profile declares `techs: true` against nothing, and the field
   yield's per-age ladder is standing in for a mill upgrade that does not exist.

**Closed off this list rather than deleted, because each says something about how the
list moves:** 4.8 garrison and 4.9 (2026-08-27) did **not** close the wall hole they were
billed as closing — the owner ruled walls out — and 8.8's [X] button (2026-08-28) turned
out to be a layout problem rather than a UI one.

Then, in no forced order: 12.2b's real AI decision flow, 4.13's pack/unpack state machine
(the art is staged and waiting — see §7), 2.4c the map save format, 12.1b LAN discovery,
12.3 campaign, and 13.x dragons once the RTS is a game.

---

## 8. For the art agent

See **[AGENT_ASSET.md](AGENT_ASSET.md)** for their side: recipes, bake batches,
staging, the isobake pipeline, and what they consider stable versus in flux.
That file is theirs to write and maintain — I do not edit it, the same way they
do not edit this one.

If the two documents ever disagree about the fence between us, the disagreement
itself is the thing to fix — raise it in `asset_request.md` rather than quietly
picking a side.
