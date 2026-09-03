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
| `tools/` | isobake recipes + bake/stage scripts — the art agent's. **Four things in it are MINE and that is by agreement, not by drift**: `stage_audio.py` and `licence_audit.py` (settled in `asset_request.md`, 2026-08-23 — *"leave it exactly where it is, and keep owning it"*, on the principle that ownership follows who can maintain a thing), `prepare_ui_chrome.py` (added 2026-08-30, same arrangement: it decides what size a WIDGET wants, which is a layout question), and **`build_packs.py` + `packs.source.json` (added 2026-09-03, phase 0.3)** — the owner was offered the narrower split, where I write only the content packer and request the art `.pck` packer from the art side, and chose *"Assign build_packs.py to me too"*. ⚠️ **THAT ONE IS THE EXCEPTION THAT IS NOT SELF-JUSTIFYING.** The other three are things only I can maintain; this one will eventually read the art pipeline's bake output to build `pack_art_v1.pck`, which is the art side's business, so it is mine because the owner said so and not because the principle points here. **It only builds `campaign` and `map` packs today** — the `.pck` half is unwritten, and if it starts needing to know how atlases are staged, raise the ownership again rather than quietly learning. Everything else in `tools/` I read and never edit |
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
answer their questions there rather than only in chat. **That file is still the
conversation; it is no longer the status** — see §2.1.

`kanban/` is **shared and belongs to neither side of the fence.** It is not `game/`
and not `tools/`, and it was added at the owner's request on 2026-09-01. Both agents
write to it: I keep the `game-code` cards, the art agent keeps the `art` ones.
**`AGENT_ASSET.md` §1.1 was written from here**, by that same instruction, and is
flagged there as agreement rather than drift — the arrangement that already puts
`stage_audio.py` and two others in `tools/`. Do not edit the rest of that file.

---

## 2. Authoritative documents, in priority order

1. **[Age & Unit Planning.md](<Age & Unit Planning.md>)** — THE ROSTER. Every
   line is an entity *template path*, not a hint about what kind of unit is
   wanted; the actor to bake is one hop inside the file's `<VisualActor><Actor>`.
2. **[PLAN.md](PLAN.md)** — architecture and phase order. §1 locked decisions,
   §2.7/§2.7.1 the age+faction skin model, §9 the data schema. ⚠️ **DO NOT WRITE
   PROGRESS INTO IT ANY MORE.** As of 2026-09-01 the owner asks for PLAN.md updates
   **themselves, at a major commit** — *"i will manually request updates to plan.md
   when we commit major changes"*. It remains the authority for architecture and
   reasoning, and it still wins every disagreement; what left it is the running
   commentary. Status goes on the board (§2.1). **Do not edit it unprompted**, and
   when you are asked to, update it in one pass rather than a line at a time.
3. **[IDEA.md](IDEA.md)** — what we're building. ⚠️ **`UI_Design.md` AND ITS SIX
   MOCKUPS ARE DELETED** (owner, 2026-08-30: *"they are all out dated now"*), and this
   file listed them as authoritative until then. They are in git; **43 citations across
   23 files now point at nothing** and are to be read as history, the way `ASSET_MISSING
   §n` is. There is no replacement document — the UI is what the code and the art say it
   is. `ART_PROMPT.md` is the nearest thing, and it is a prompt sheet, not a design.
4. **[BUGS.md](BUGS.md)** — the owner's playtest findings, and **the authority on
   behaviour they want**. Where a finding reverses an earlier deliberate decision
   the reversal is noted rather than argued; treat it as settled. It also carries a
   "standing hazards" section of traps left behind by *fixed* bugs, each of which
   can bite again. Cleaned 2026-08-23 from 424 lines to 170 with nothing open lost.
5. **THE KANBAN BOARD** — status, and the only place it lives. See §2.1.
   ⚠️ **`PROGRESS.md` IS DELETED** (2026-09-01, the owner's call), the same way
   `ASSET_MISSING.md` and `UI_Design.md` went: superseded, removed, and left in git
   rather than kept as a second thing to maintain. **Citations to it across the repo
   are history**, read like `ASSET_MISSING §n`. Its own header made the case for
   its removal and was right about itself — it admitted the file *"goes stale
   first"*, and its two headline figures and its "the single item most worth doing
   is the unit-speed pass" line were all overtaken within hours of being written.
   That is the failure the board removes: **a card cannot go stale that way,
   because moving it IS the act of changing its status.** What was worth keeping
   out of it is on the cards; **`git show ff141cd^:PROGRESS.md`** has the rest — named by
   the commit that removed it rather than by `HEAD~1`, which was right for about ten
   minutes.
6. `game/data/*.json` `_note` blocks — these are long, and they are the real
   design record for the data. **Read them in full before editing that file.**
   Several encode measurements and decisions that are expensive to re-derive.

### 2.1 The Kanban board — where progress is reported (new 2026-09-01)

**Status lives on a Vikunja board and nowhere else**, on the owner's instruction:
[projects.dragoon.co.za/projects/2](https://projects.dragoon.co.za/projects/2). Seeded
2026-09-01 with 64 cards derived from PLAN.md's numbered rows and `asset_request.md`'s
P-numbers. `kanban/README.md` is the full contract; what a session needs is here.

**Five buckets: `To-Do` → `Doing` → `Test` → `Blocked` → `Done`.** Note two shapes that
are the board's and not a typo — **`To-Do` carries a hyphen**, and **`Test` sits before
`Blocked`**. Both were read off the owner's existing board rather than chosen.

| bucket | what it means here |
|---|---|
| `To-Do` | not started |
| `Doing` | being worked on right now. **Move the card before you start**, not after |
| `Test` | written, and waiting on the one check that can judge it — the suite, a preview screenshot, or the owner playing it. §5's whole argument is that these are different |
| `Blocked` | cannot proceed. Say what on, in the card |
| `Done` | verified. Not "the code is written" |

### ⛔ NOTHING IN THE REPO MIRRORS THE BOARD — the online-only tool (2026-09-01)

**The owner's ruling:** *"nothing lives in repo, everything lives online, no board.json
for sync"*. **`kanban/board.json` and `kanban/vikunja_sync.py` are DELETED.** There is no
local manifest, nothing to re-seed from, and no whole-board write. `git show` has both if
the seed text is ever wanted.

**My tool is `kanban/card_game.py`.** One card at a time, and the server is the truth.

```powershell
$py = "C:\Users\herman.ras\Downloads\AOD_game\tools_env\venv\Scripts\python.exe"

& $py kanban\card_game.py list --label game-code   # mine
& $py kanban\card_game.py show 15.5                # READ IT BEFORE YOU START
& $py kanban\card_game.py move 15.5 Doing          # scoped: this card, nothing else
& $py kanban\card_game.py append 15.5 notes.md     # ADD to a description, clobber nothing
& $py kanban\card_game.py new 17.1 "Title"         # create
```

- **The cycle the owner asked for:** *"ready the card. do the work, check the card for
  updated, add your updated."* So `show` **before** starting, `show` **again** when you
  finish — somebody may have written to the card while you worked — then `append`. Both
  agents write to this board, neither can see the other do it, and **Vikunja shows no
  history**, so a card that changed on its own is far more likely to be a colleague than a
  bug.
- **`append`, not `set`.** `append` stamps `[game-code <date>]` and adds to the end, so a
  read-then-write cannot race into a clobber. `set` replaces a description outright and
  demands `--replace` spelled out, because a card is a shared document and losing
  somebody's note is silent.
- ⚠️ **`kanban/card_game.py` IS TEN LINES WRAPPING `kanban/card.py`, WHICH IS THE ART
  AGENT'S FILE AND NOT MINE TO EDIT.** It imports the module and swaps the two constants
  that name the fence, so there is one implementation and one place to fix a bug rather
  than two 400-line copies that must agree about a shared board. **It asserts what those
  constants say before overriding them**, because setting an attribute on a module always
  succeeds — a silent failure there would leave me running under the *art* side's fence:
  refused on my own cards and free on theirs. If that assertion fires, fix the wrapper and
  raise it in `asset_request.md`; do not edit `card.py`.
- **A refusal from my own tool prints "The art agent updates and moves 'game-code' cards
  only".** That sentence is `card.py`'s template with my constant interpolated into it, so
  it reads oddly and is not a bug — the card name and the offending label above it are
  correct. Not worth reaching into their file for.
- **Why the sync went, in one line each:** a bare run PATCHed the title, description,
  priority, labels and done flag of **every** card, both agents' alike, so every edit was
  a whole-board write; `board.json` was a second source of truth and drifted, which is the
  fourth time this project has paid for one; and the manifest still said `game-code` for
  card `9.5` after the owner had deliberately stripped that label, so the next run would
  have silently undone their decision as one line of a 64-card write.
- **A new work item is `new`, not a manifest edit.** The key becomes the title prefix and
  both tools match on it, so **renaming a card is free and renumbering a key makes it a
  different card.** PLAN.md's §15 header records that its own numbering has been renumbered
  twice and that cross-references drifted both times — which is why the keys are the
  board's and not PLAN.md's.
- 🚫 **I TOUCH ONLY `game-code` CARDS. I NEVER TOUCH AN `art` CARD — NOT TO MOVE IT, NOT
  TO EDIT IT, NOT TO CLOSE IT.** The owner's instruction, 2026-09-01, and it was given
  because the two of us were **updating over each other**: one board, two agents, and
  both of us reading the whole thing as ours to keep current. I had also been reporting
  the art side's progress in my own summaries, which is the same mistake one step
  earlier — **their cards are not mine to describe either.**

  **The label is the fence, and it is the WHOLE fence. THERE ARE THREE SIDES, NOT TWO**
  (owner, 2026-09-01):

  | label | whose | means |
  |---|---|---|
  | `game-code` | mine | I move it, I write it, I close it |
  | `art` | the art agent's | I read it and touch nothing |
  | **`owner-decision`** | **the owner's** | **it cannot move until they rule. Not mine, not the art side's** |

  `blocked-on-art` is the one genuinely cross-cutting label and says nothing about who
  may write a card — read the side label beside it.

  ⚠️ **A CARD THAT CHANGES HANDS IS THE OWNER'S TAG SWAP TO MAKE, NOT MINE**, and there
  are now **two places to hand one to**. When my work on a card ends, say so and stop:

  - *"card X is now the art side's — please swap the tag to `art`"*, when the next step
    is a bake, a measurement or anything only the pipeline can do.
  - *"card X needs your review — please swap the tag to `owner-decision`"*, when the next
    step is a **judgement call, a cost, or a look at a screenshot**. **This is the one to
    reach for by default when I am blocked on a person rather than on a tool.** Before
    2026-09-01 the only handover I had was `art`, which meant a card waiting on the owner
    got parked in the art side's queue where nothing about it was theirs to do.

  In both cases: do not relabel it and do not move it into a bucket on anybody's behalf.
  Same in reverse — a card labelled `art` or `owner-decision` is not mine to pick up even
  when the work is plainly code, until the owner has swapped it back.

  **`9.5` is the worked example.** The owner stripped its `game-code` label on
  2026-09-01 to mean *"mine, and when we work on it is my call"*, leaving it
  `owner-decision` + `blocked-on-art`. That is not a card missing a label; it is a card
  correctly assigned to the third side. **Do not add `game-code` back to it.**

  ⚠️ **A DUAL-LABELLED CARD IS AMBIGUOUS UNDER THIS RULE AND MUST BE REPORTED, NOT
  GUESSED AT.** Both tools refuse a card carrying the other side's label, so a card with
  BOTH is unwritable from either end — which is correct, because two labels means two
  agents each with a defensible claim. **A tag swap is the owner's, done in the Vikunja
  UI**, and neither tool has a command for it on purpose. `P7-footprint` was the one such
  card, seeded with both because it is a question one side owes the other; **the owner
  resolved it to `game-code` on 2026-09-01** and it is mine.

  One board rather than two projects is still right — *"5.7 is blocked on the art side's
  A.10"* is the single most useful thing either agent can read here, and two projects
  would hide it. **Read the whole board; write only your own half of it.**
- **Do not add a status narrative to PLAN.md or to this file.** A card that has moved is
  the report. Four trackers have now been deleted rather than kept in step —
  `ASSET_MISSING.md`, `UI_Design.md`, `PROGRESS.md` and `board.json` — and every one of
  them was a copy of something that had already moved on.
- **`asset_request.md` IS THE CHANNEL TO THE ART AGENT AND THE OWNER READS IT TOO.** The
  owner asked the art agent to read my notes there on 2026-09-01, so a reply written only
  in chat reaches nobody. **Anything the other side needs to act on goes in that file**,
  under a `[game-code]` heading, and anything I move that is not mine gets said there —
  neither of us can tell the other's card move from a tool bug, and **Vikunja keeps no
  history**.
- ⚠️ **THREE API READINGS LOOK EXACTLY LIKE A FAILURE AND ARE NOT.**
  `GET /views/{v}/tasks` never populates `bucket_id`; `GET .../buckets` reports
  `count: 0` for every bucket; and PowerShell's console prints `campaign â scenario 3`
  for text the server stores correctly as an em dash. **`GET .../buckets/tasks` is the
  only authoritative bucket→task mapping**, and §2's "a `Get-Content` dump is not
  evidence" rule extends to `Invoke-RestMethod` piped to a terminal. All three cost a
  false alarm on the day the board was seeded.
- **The token in `.env` expires.** Vikunja API tokens carry a mandatory expiry, so a 401
  from `list` is routine maintenance and not a broken board; the tool prints the
  re-minting steps rather than a stack trace. `.env` is gitignored as of 2026-09-01 — it
  was not before, and `origin` is a public GitHub repo.

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
& $godot --path game res://dev_preview/preview_menus.tscn      # splash, front door, settings,
                                                               # campaign, HOW TO, lobby
& $godot --path game res://dev_preview/preview_walls.tscn      # both wall axes + gate
& $godot --path game res://dev_preview/preview_ai_match.tscn   # two AIs, full match
& $godot --path game res://dev_preview/preview_projectiles.tscn # arrow/bolt/stone in flight
& $godot --path game res://dev_preview/preview_garrison.tscn   # 4.8/4.9, six screenshots
& $godot --path game res://dev_preview/preview_touch_controls.tscn  # can a THUMB use it?

# LAN discovery, TWO PROCESSES — the only thing that exercises the broadcast flag (§7).
# Start the beacon first; it waits. The exit code is the answer.
& $godot --headless --path game res://dev_preview/preview_lan_discovery.tscn -- --role beacon
& $godot --headless --path game res://dev_preview/preview_lan_discovery.tscn -- --role browse

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

⚠️ **`preview_touch_controls` IS THE ONLY THING IN THE REPO THAT EXERCISES A FINGER**, and
it exists because nothing did: the three volume sliders were completely inert on the phone
inside a match from the day they landed (owner, 2026-08-30), with every test green and
every screenshot right. It pushes real `InputEventScreenTouch`/`Drag` at the REAL
`VolumePanel` through both input routes under both emulation settings, prints a table, and
**exits non-zero if a control does not answer a finger with emulation off** — which is the
setting a match runs under. It was verified against the bug it is for rather than assumed
to catch it: swapping the panel back to a plain `HSlider` makes it report NOTHING on three
of its four rows. **Run it after adding any control that is not a `BaseButton`** — a button
answers a raw touch and, in this project, nothing else does.

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
- **`Test` is a real column, not a formality, and this file is 1,600 lines of why.**
  Move a card to `Test` when the code is written and pull it to `Done` only once the
  check that *can see the fault* has run — which is rarely the suite. Three things
  shipped green and broken because nothing looked: every unit's atlas was MIRRORED
  past a check blind to reflections, three HUD refusals were dead for players 2..8
  because `Net.host()` is never null in solo play, and the volume sliders were inert
  under a thumb from the day they landed. 1,779 tests ran past all three. **Ask which
  failures your check is blind to before moving a card out of `Test`** — a green check
  on a fault it cannot express is worse than no check, because it ends the
  investigation.

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
| **A FIXTURE THAT PUTS TWO HOSTILE UNITS NEAR EACH OTHER AND EXPECTS NOTHING TO HAPPEN** | Was safe for the whole life of the project and stopped being safe on 2026-08-29, when 4.12 gave military units a DEFENSIVE default. Six tests broke, and **not one of them was about stances**: `test_projectiles`' shooting range is an archer three tiles from an enemy militia, so the pair started fighting on its own and a five-arrow tower volley counted six — and the fan stopped being parallel, because the militia had closed the distance while the tower aimed. `test_garrison`'s "a foundation does not defend you" was answered by the archer standing next to the foundation. **The fix is to say what the fixture means** (`u.stance = SimUnit.Stance.PASSIVE`), never to reach for the default. Worth remembering as a class: a test whose premise is "nobody acts unless I say so" is resting on an absence, and absences get filled in. |
| **AN AGGRESSIVE STANCE THAT SEES LESS THAN A DEFENSIVE ONE** | `unit.militia` declares `los: 4` against `StanceSystem.GUARD_RADIUS`'s 5, so reading `def.los` straight for AGGRESSIVE made the stance a player picks to start MORE fights start fewer — on six of the roster's units, not a corner case. `_sight_of` floors it at `GUARD_RADIUS`. The general form: **when one setting is meant to be strictly stronger than another, the ordering is the rule and the numbers are inputs** — assert the ordering, not the numbers. It was caught by a test written to pin exactly that, on its first run, and only because the assertion was a comparison rather than a literal. |
| **Two agents, one working tree** | Commits interleave. Check `git log` and what you actually staged; the art agent may have already committed your shared file (`asset_request.md`). |
| **TWO ROWS BUILT FROM THE SAME MINIMUMS STILL DRIFT APART, because the ONE EXPANDING CHILD absorbs whatever their totals differ by** | The lobby's COLOUR/TEAM/TYPE headings were an `HBoxContainer` mirroring `_build_slot_row`'s widths out of the same three constants, and its own comment claimed that was "the only reason it stays lined up". The slot row's identity block is a shade wider than the 96 px floor the heading's spacer copied, so every control started further left than its heading — **by a different amount per column**, which is what makes it read as broken rather than as offset. The fix is a `GridContainer`: columns shared by construction, no second list of widths. **Mirroring a layout is not sharing one.** `preview_skirmish._report_headings` now prints the drift per column. |
| **A PREDICATE DELIBERATELY SPLIT IN TWO HAS TWO PLACES TO CHANGE, and the half carrying the good reason is the half you read** | `StanceSystem._may_start_on` and `AbilitySystem._is_hostile_to` both route the UNIT half through `CombatSystem._is_at_war_with` and both keep their own `owner_id != owner_id` for BUILDINGS — correctly, since a building is never gaia's. Teams widened the owner clause in *both* halves and both were missed on the first pass: an aggressive soldier would have opened fire on an ally's barracks while doing exactly the right thing about their soldiers. The comment explaining why the split exists is what makes the second half invisible. |
| **A RULE THAT CAN BE LEFT OUT IS A RULE THAT IS OFF SOMEWHERE** | `Diplomacy.is_enemy(e, player_id, teams)` takes the team table as a REQUIRED argument with no default, so a call site that was not updated is a parse error rather than a silently permissive predicate. Same family as `if Net.host() != null and <rule>` below. When widening a predicate every system reaches through, make the new argument mandatory and update the call sites; a default is how you ship the old behaviour in the one place nobody looked. |
| **A GUARD THAT INFERS AN ENTITY'S KIND FROM WHICH SNAPSHOT FIELDS IT CARRIES** | Wrong the moment the wire format is optimised, and 12.1f already did that once — it took `footprint` off the wire, so `not entry.has("footprint")` (meaning "is a unit") became true for **everything**. It bit `GameView` twice in the same file: the occluder loop was fixed for it in 4.13 and its comment says so, and the sort-bonus guard twenty lines below was missed until 2026-08-28. **Ask `GameDataRegistry`** — `unit(def_id) != null`, the way `_facts`'s own `is_unit` does. |
| **TWO DEAD GUARDS CAN CANCEL OUT, so fixing one breaks what looked unrelated** | `_in_front_of_any` had `if r.has_point(tile): return true` sitting below a check that was false for every tile inside the rect — unreachable. Making it reachable instantly failed three sort tests, because the caller's kind-guard was *also* dead and every building had been asking the function about itself; a building's own tile is inside its own rect, so the unreachable branch was the only thing keeping that harmless. **When a one-line fix breaks distant tests, look for a second dead guard rather than reverting** — the tests were right and both bugs were real. |
| **A comment that says a bound cannot be exceeded, when it bounds a DELTA and not a RESULT** | `SeparationSystem.MAX_PUSH` is 120 of a 256 sub-tile and its note argues a push "can never carry a unit out of the tile MovementSystem just placed it in". True only from the tile's centre: from sub-position 250 a +120 push crosses the boundary, and the code under that comment already calls `spatial.move()` when it does. Three systems trusted the comment and retired any worker that lost adjacency, which is the owner's 2026-08-28 "pushed villagers go idle". |
| **A POSITIONAL CORRECTION THAT IS LARGER THAN A TICK'S MOVEMENT IS NOT A NUDGE, IT IS A THROW** | `SeparationSystem.MAX_PUSH` is 120 sub-units and a villager covers **~26** in a tick, so the correction outweighs the step `MovementSystem` just took by five to one. Making the walker take the whole push (2026-08-29, so a passer-by stops shoving standing gatherers) deadlocked three tests instantly: the unit was thrown clear, spent several ticks walking back to the line it was thrown off, and got thrown again — **forward progress zero, for as long as the order stood**, and it looks like a hang rather than like a push. Capping at the mover's own `speed` is what makes it steering. **Anything that writes `pos` outside `MovementSystem` owes the same comparison**, and the number to compare against is `UnitDef.speed`, which was halved across the roster on 2026-08-23. |
| **A PERCENTAGE MODIFIER ON A BASE RATE OF 1 IS A MODIFIER OF ZERO** | `TechMods.scaled(1, 25)` is `1 * 125 / 100` = **1**. An "Architecture, +25% build speed" tech was written, given a cost and a research time, and removed the same hour: `BuildSystem.BUILD_RATE` is 1 progress per builder per tick, so a percentage has nothing to round to below +100%. **Ask what the BASE is before choosing between a flat bonus and a percentage** — the gather rates are per 100 ticks and take a percentage happily; anything expressed per tick does not. Rounding up would have been worse than doing nothing, since it makes the tech worth +100% on a single villager. |
| **A FOOTPRINT AND A MEASURED EXTENT ARE TWO DIFFERENT RECTS AND BOTH ARE RIGHT** | The sim's footprint is the tiles a building holds and refuses to be built over; the visual's `footprint_m` is the ground its MESH covers, measured off the bake. They disagree by metres — an age-4 town centre overhangs its 8×8 — and which one a feature wants depends on what it is claiming. The selection ring needs both at once: a building's square traces the SIM's rect (2026-08-29, owner's ask), a unit's ellipse is drawn from the VISUAL's, and swapping either would be visibly wrong in the opposite direction. `GameView._ring_ground_m` is where that split is written down. |
| **A verification that cannot see the fault it is for** | The facing check was "column 0 a face, column 4 a back" — **the two columns a mirror about N–S leaves alone**. A mirrored roster passed it twice and a 242-atlas re-bake was spent on the wrong diagnosis. Before trusting any check, ask which failures it is *blind* to; a green check on a fault it cannot express is worse than no check, because it ends the investigation. |
| **A facing that is drawn wrong is not necessarily set wrong** | Two different faults, two different owners. `preview_work_facing` prints the sim's `facing` beside what `SimUnit.facing_toward` would pick now: **STALE means nothing turned the unit** (a sim gap — until 2026-08-27 only `MovementSystem` and `CombatSystem` ever wrote `facing`, so gathering and building never turned anybody), while numbers that agree with a picture that disagrees is the atlas. Settle which one before writing anything. |
| **A CLIP ONLY ONE SPECIES HAS, sent by the sim for all of them** | The sim may not ask which clips were baked, so `AnimationSystem` sends `run` for every bolting animal and `feeding` for every settled one — and only the deer has a run, only the cattle a feed. **The generic fallback chain is `static` → `idle`, and for `run` that is the WRONG answer**: five of the six would stand perfectly still while sliding at flee speed, which is worse than the walk they played before the clip existed. `AtlasEntry._ANIM_ALIAS` (`run` → `walk`, `feeding` → `idle`) is tried ahead of that chain. **The test for whether an alias belongs there: it must fall back to a clip every subject HAS** — a rewording of the request, not a second guess at it. |
| **The projection inversion RETURNS A NEGATIVE HEIGHT for anything lying down** | visuals.json's documented `height = (anchor.y - rect.w / 4) / 19.596` assumes the sprite's top is the subject's top. A carcass lies below its own anchor, so four of the five 2026-08-28 bakes derive a negative height and `vis.deer_carcass` derives 2.47 m — taller than the standing deer. **No choice of frame fixes it; the failure is structural.** The five ship as the deer carcass's own proportions scaled off each animal's measured live figures, and `asset_request.md` [P5] carries the ask for real ones. |
| **TWO LISTS BOTH MEAN "GONE" AND ONLY ONE OF THEM IS A DESPAWN** | `GameView` drops an entity two ways: `snap.removed` (an explicit despawn) and the forget pass (anything `updated` did not mention, i.e. it walked into the fog). They were run forget-first, so a despawned entity had its facts erased by the forget pass before the `removed` loop saw it — and anything wanting to act *on* a despawn had nothing left to read. That is what `SpentProjectiles` needs and what `MatchAudio`'s header records as unresolvable from `updated` alone. **`removed` now runs first**, and the distinction is real: an arrow that flies into the fog leaves no litter, because you did not see it land. |
| **A SYSTEM THAT ACTS ON THE TICK A STATE IS REACHED, BEFORE ANY SNAPSHOT CARRIES IT** | `ProjectileSystem` despawned a shot on the very tick `advance()` clamped its position to the target — so the arrival position never reached a client and **every arrow in the game vanished a tile and a half short of what it was fired at**, `SPEED` being 384 of a 256 sub-tile. Nobody reported it in six days: an arrow is on screen for two ticks, and *a sprite failing to appear somewhere* is far harder to see than one appearing wrongly. The fix is one word (`elapsed_ticks > total_ticks`) and the general form is worth keeping: **if the last thing an entity does is the thing you want drawn, it has to survive one snapshot after doing it.** |
| **A staged tree is not a declared tree, and this file has claimed otherwise** | `vis.tree_cherry`, `_cypress`, `_cypress_tall`, `_snow_pine`, `_dead` and `_dead_branchy` are staged and referenced by nothing — an earlier session told the art side that the two dead ones were "staged and wired today" and they were not. They predate the per-map pools and carry no pool assignment, so they were left out of them deliberately rather than missed. Same class as the walls in §7: **only a def or a pool reaching for an id proves it is wired.** |
| **Compensating for a bake defect in the game** | Tried once — the 180° facing offset, 2026-08-22 — and reverted the next day on the owner's instruction. The rule they set: an art defect gets fixed in the recipe, and a patch that must be un-applied in step with a delivery is not worth carrying for a partial result. Report it in `asset_request.md` with a picture instead. |
| **A CONTROL DRIVEN BY MOUSE EVENTS IS INERT UNDER A THUMB INSIDE A MATCH — and `BaseButton` is the exception that hides it** | `emulate_mouse_from_touch` is off for exactly as long as a match lasts (`GameScene` turns it off on entry, `_exit_tree` hands it back), so Godot's `Slider`, which reads `InputEventMouseButton`/`InputEventMouseMotion` and nothing else, does nothing at all. **A button DOES answer a raw touch**, so every HUD control anybody had pressed worked and the three volume sliders — the only non-buttons in the game — were dead from the day they landed (owner, 2026-08-30). Measured on 4.7.1: an `HSlider` at 0.50 tapped at 95% of its track reads **0.50** with emulation off and **0.95** with it on. `TouchSlider` and `TouchLineEdit` are the pattern; **never the project setting**, because a flag toggled per screen has to be un-toggled on every path out and the failure is a silent double-pan for the rest of the match. |
| **A `Range` OUTSIDE THE TREE MOVES SILENTLY — `value_changed` is not emitted at all** | `Range::Shared::emit_value_changed()` skips every owner whose `is_inside_tree()` is false, so a detached slider's value changes and no listener hears it. Free in the game; a trap in a headless test, because *"the slider did not move"* and *"the signal is not wired"* then look identical. **Assert the VALUE.** Same family as the `PRESET_FULL_RECT` row below — a Control does a surprising amount of nothing until it is in a tree. |
| **Touch does NOT take keyboard focus, so every new text field needs `TouchLineEdit`** | `emulate_mouse_from_touch = false` ([project.godot:35](game/project.godot#L35)) is *required* — `CameraRig` handles both `InputEventScreenDrag` and `InputEventMouseMotion`, so a touch arriving as both pans twice per thumb. Godot still routes raw touches to controls, but the touch path takes no focus and `LineEdit` asks for the keyboard on focus-enter. Measured on 4.7.1: focus after a screen touch = false, after a mouse click = true. Flipping the setting fixes typing by breaking the camera. |
| **A `Control` laid over the minimap swallows every tap** | The four corner buttons were a `PRESET_FULL_RECT` grid added *over* it and Godot hit-tested them first — minimap click-to-move and double-tap-to-centre were both dead while looking implemented. Check hit-test order before concluding a minimap feature is missing. |
| **`JSON.stringify` encodes a `PackedByteArray` as a STRING** — `"[1, 2, 250]"`, verified on 4.7.1 | It bit `MapData.from_dict()`, which now reads bytes, JSON's string, or a plain list. Relevant to 2.4c's saved sidecar and 12.4's save/load — the next two places sim data goes through JSON. Everything else there was already defended with `int()` because JSON numbers come back as floats; `terrain` was the one field that looked like it needed no conversion. |
| **Wall-clock timings are worthless on this workstation** | The same seed ran 41.3 s and 161.0 s; the suite swung 34 s to 110 s across four runs of identical code. Trust `test_tick_cost`, which reports per-system milliseconds. Do not conclude anything from how long a run took. |
| **The 0 A.D. checkout's media files are git-LFS POINTERS, not content** | Every `.ogg`/`.dae`/`.png`/`.pmd` on disk is a ~130-byte pointer. Worse, that repo's **index is emptied** (30,114 staged deletions) and its `.gitattributes`/`.lfsconfig` are gone from the working tree, so `git lfs pull` exits 0 having done nothing. Do **not** repair it — it is the art agent's tree and memory records that git operations there have destroyed art. The route that works is documented in `tools/stage_audio.py`: read the oid out of the pointer, fetch through the LFS batch API, write the bytes into `game/` and never into the checkout. |
| **A FONT CANNOT BE IMPORTED WHILE `gui/theme/custom` REFERENCES IT** | Swapping the body face deadlocks `--import`: the project theme loads at startup, names the new `.ttf`, the `.ttf` has no `.import` yet, the load fails and the import never reaches it. The error reads "No loader found for resource". Comment `theme/custom` out of `project.godot`, `--import`, put it back, `--import` again. Same shape as the "a new `class_name` is invisible until `--import`" row, with a cycle in it. |
| **A NinePatchRect's BORDER IS DRAWN AT 1:1** | The `patch_margin` is in SOURCE pixels and does not scale with the rect, so a 1024 px plate with a measured 46 px border puts a 46 px border on a 152 px panel and clips the content behind its own frame. **Shrinking the margin makes it worse** — the margin says where the border ENDS, so the leftover bevel joins the stretched centre and smears across the panel. The only lever is the SOURCE SIZE; `tools/prepare_ui_chrome.py` is what turns "the border should draw at 12 px" into an output size. See §7's UI-overhaul block. |
| **SWAPPING ONE FRAME FOR ANOTHER CAN INVERT THE DRAW ORDER** | A frame with a TRANSPARENT middle is drawn on top of what it frames; a frame with a FILLED recess must be drawn under, or it covers the picture entirely. Both replaced frames flipped on 2026-08-30 and a filename says nothing about which kind you have. Found by `preview_match` — a selected town centre with an empty brown square where its portrait goes — not by any test. |
| **`draw_texture_rect_region` HAS NO KEEP-ASPECT MODE** | It fills the rect it is given, so a non-square crop in a square slot is stretched. `EntityPortrait.fit` is the arithmetic and lives beside the crop helper, because two hand-drawn slots made the identical mistake independently. A `TextureRect` with `STRETCH_KEEP_ASPECT_CENTERED` does not have the problem, which is why the action tiles never showed it. |
| **A `VBoxContainer` OVERFLOWS — it does not clip, scroll or compress past its children's minimum sizes** | So any column whose child count the player controls needs a `ScrollContainer` round it. The lobby offers up to eight player slots; at eight, the GAME SETUP panel alone is taller than a 648 px viewport, and the first render had the map panel and the entire bottom nav strip off the screen with nothing to indicate they existed. **Every structural test passed.** Related: shrinking something INSIDE the overflowing column does not move the fold — the fold is wherever the preceding sibling ends. |
| **A number nobody compares across time can be wrong for months** | `SimBuilding.add_build_progress` set `hp` from `build_fraction()` and took every new foundation from `max_hp/10` to ~0 on the first tick a villager worked on it. It shipped, unnoticed, until `DamageAlert` started diffing hp between snapshots and blew the under-attack horn on every building placed. **The alarm was right and the sim was wrong.** When a new feature starts reading an old value, expect it to find something. |
| **A `PRESET_FULL_RECT` CONTROL CANNOT BE GIVEN A SIZE, AND SAYS SO ONLY AT RUNTIME** | Assigning `size` warns *"nodes with non-equal opposite anchors will have their size overridden after `_ready()`"* — and **outside a tree it raises no `NOTIFICATION_RESIZED` at all** (probed on 4.7.1). That makes it a bad lever for a headless test of anything layout-shaped: `test_market_panel` drove the new page-width cap through `panel.size`, the notification never fired, and the test asserted the *default* offsets while reading like it had asserted the cap. It failed loudly here only because the arithmetic was also being asserted. **Give the function the width instead of having it read `size`** — one untested line in the notification handler, verified in a render, beats a test that exercises nothing. Note also that a Control added to a tree has size `(0, 0)` for the rest of that frame, so `_init`/`_ready` are both too early to read it. |
| **`gitea.wildfiregames.com` is behind an Anubis proof-of-work bot wall** | A plain HTTP client gets an HTML "Making sure you're not a bot!" challenge instead of JSON, which is easy to misread as a broken endpoint. A **`git-lfs/...` User-Agent is allowed through** — that one header is the whole difference. |
| **A GUARD OF THE SHAPE `if Net.host() != null and <rule>` IS A RULE THAT IS OFF ON EVERY CLIENT** | And it survives review because solo play, where every test and every preview lives, has the local player AS the host — so the wrong branch is the one nobody takes. Three of `GameScene`'s polite refusals shipped that way and were dead for players 2..8 (owner, 2026-08-30). **Whatever a client needs is almost certainly already in `player_state`**: stock, population, age, researched techs, and now `defeat_reason`. `GameView.stock_of` and `_my_stock`/`_has_pop_room` are the client-safe readers. |
| **A WATER UNIT ON LAND CANNOT BE ORDERED TO DO ANYTHING, and reports nothing** | `validate()` passes, `PathService` returns an empty route because there is no start node for its domain, the task is retired on tick 1, and the log reads "order accepted" while the ship stands still. **The debug map has ZERO water tiles** — measured, 64×64 — so any fixture with a ship paints a channel and then calls `PathService.rebuild`. `AStarGrid2D` holds solidity IN THE GRID, not in the query, so terrain written behind its back does not exist to pathing. `test_transport._make_a_coast` is the pattern. |
| **A BALANCE NUMBER WRITTEN INTO AN ASSERTION IS A TEST THAT FAILS WHEN THE OWNER ASKS FOR A BALANCE CHANGE** | Doubling `res.tree` broke five tests and **not one was about wood**: two literal `40`s and a tick budget in `test_gather` (generous at four round trips, short at eight) and two in `test_game_data`. Derive from the def — `tree.starting_amount`, `amount_for(size_class_count() - 1)` — and assert the SHAPE (three classes, bigger holds more) rather than the figures. |
| **`JSON.parse_string()` PUSHES AN ENGINE ERROR PER FAILURE and `JSON.new().parse()` does not** | Irrelevant on a config file and a hole on a socket: `LanBeacon.decode` reads whatever the network sends it, so the static helper turns one malformed datagram a millisecond into a log somebody can fill from across the room. Found by a single deliberately malformed test fixture printing "Parse JSON failed" into an otherwise clean run. **Wherever untrusted bytes meet a parser, check which form of it talks.** |
| **A DISABLED CONTROL'S REASON FOR BEING DISABLED IS NOT THE SAME FACT AS ITS BEING DISABLED** | `ServerBrowserPanel` set JOIN's `disabled` from "is there a sentence to print", which is right in three of its four states and wrong in the one it lives in: an empty list needs no sentence — the page already says so at length in the middle of itself — so JOIN came out **enabled with nothing to join**. Only one of the two facts is always expressible; compute them separately. |
| **A BACKTICK IN A POWERSHELL DOUBLE-QUOTED STRING IS AN ESCAPE CHARACTER, so every markdown code span passed through the shell LOSES ITS FIRST LETTER** | Writing a Kanban note containing `` `blocked-on-art` `` reached Vikunja as `locked-on-art` — the backtick ate the `b`, silently, and the text was otherwise perfect so it read as a typo rather than as shell mangling. Same family as `Set-Content -Encoding utf8`'s BOM and the here-string-into-pathspecs row: **the shell is a lossy channel for prose.** The fix is the one this file already uses for commit messages — **write the text to a FILE and pass the path** (`card_game.py append KEY notes.md` takes one, as does `git commit -F`). A single-quoted PowerShell string also works, but then you cannot interpolate, and the habit that survives contact is "prose goes through a file". |
| **GDScript WILL NOT COMPILE `{...}[key]` — subscripting a dictionary LITERAL inline — and the error points at a different file** | It is a whole-FILE compilation error, so every `static func` on the class vanishes and the symptom is `Nonexistent function 'from_dict' in base 'GDScript'` raised from whichever file *calls* it. Cost a full suite run on 15.1: the real fault was one line in `objective_def.gd` and four files reported it. A `match` is the fix. **The general form: when a static on a class is suddenly "nonexistent", the class did not compile — read the FIRST error in the run, not the loudest one.** A const dictionary at class scope is fine; it is only the inline literal subscript that fails. |
| **A TREE COUNT IS A CPU BUDGET AND A TREE AMOUNT IS FREE** | Both change how much wood a map holds and only one of them costs anything: `AISystem` searches the whole entity list per player per tick, which is what took the 2026-08-28 density work to 24.83 ms against a 20 ms ceiling. So **amount-per-tree is the lever to reach for first** and trees-per-map second. `MapGenerator.SPRINKLE_SPACING` is a dozen or two trees a board on purpose. |

---

## 7. Where things stand

### PHASE 15, SCENARIOS — 15.1 and 15.3 landed 2026-09-01

Campaigns are read off disk and a scenario can produce a `MatchConfig`. **Scenario 3 is
launchable and needs only 15.5's screen to call it**; scenarios 1 and 2 refuse until 15.2.
Suite **1926 passed, 0 failed**. Commits `3b01530` (15.1) and `afba341` (15.3).

| | |
|---|---|
| the defs | `ObjectiveDef`, `ScenarioDef`, `CampaignDef` in `src/data/`, plain `RefCounted` like every other def |
| the loader | `Campaigns` — **not an autoload**; §6.1's table is exactly four and only the front door reads this |
| the content | `scenarios/HowToPlay/` — one `campaign.json`, three `scenario.json`, outside `res://` |
| the launch | `ScenarioDef.build_config()`, tested by asserting the config rather than by starting a match |

- ⚠️ **`== 0` IS A COMPARISON AN UNIMPLEMENTED SUBJECT PASSES**, which is why `area`,
  `named_unit` and `ticks` are refused **at load** rather than defaulted. A subject that
  silently counted zero would announce victory on tick 1 of a scenario nobody could win.
  The refusal says *"not evaluable yet"* rather than *"unknown"* on purpose — "not built"
  and "you misspelled it" want different reactions from whoever reads the log.
- ⚠️ **`SCENARIO` MODE IS REFUSED AT LAUNCH, AND THAT IS THREE LINES TO DELETE WHEN 15.2
  LANDS.** `MatchConfig.Mode` has no `SCENARIO` member; PLAN.md assigns it, and
  `MatchConfig.objectives`, to 15.2. Both shortcuts are traps and both look like they
  work: **mapping it onto `LAST_MAN_STANDING`** lets conquest win an economy lesson with
  two villagers and no house (decision 5's named failure), and **adding an inert member**
  launches scenario 1 into a match that can never be won *or* lost, because
  `WinConditionSystem` deliberately never ends a match in an unimplemented mode. *Inert*
  is the safe direction for a mode nobody has selected; it is the wrong direction for the
  mode a PLAY button is about to select.
- **`ScenarioDef.Mode` is its own two-member enum and NOT `MatchConfig.Mode`.** That is
  what let 15.1 be complete and tested without touching `MatchConfig` at all — PLAN.md
  15's build order asks every row to be a place you can stop.
- ⚠️ **`AIProfile.IDS` AND `SimPlayer.AILevel` ARE COUPLED BY POSITION AND NEITHER FILE
  SAYS SO.** The conversion is `IDS.find(name)`. Reordering either list, or inserting a
  difficulty in the middle, would keep working while silently giving every scenario the
  wrong opponent. `test_scenario_launch` pins the pairing **by name**; same family as
  `colours.json`'s load-bearing order.
- **The dev override needs no config file, which departs from PLAN.md 3.3** — it describes
  one, on `tools/isobake.local.toml`'s precedent, and that precedent does not transfer.
  The art root is genuinely machine-specific; `scenarios/` is the **sibling of the Godot
  project on every clone**, so `res://../scenarios` finds it unaided. A fresh checkout runs
  the campaign with no setup step, and a setup step nobody performs is why
  `game/assets/ui/` was gitignored for months and a clean clone had no HUD.
  `game/content.local.json` is still read first for a differing layout. **The
  `OS.has_feature("editor")` gate is the whole safety argument** and is unchanged: true for
  editor runs, the headless suite and every `dev_preview`, false in an export.
- **The loader uses `JSON.new().parse()`, never `JSON.parse_string()`** — the static form
  pushes an engine error *per failure*, and **a campaign is downloadable, shareable
  content**, so these bytes are as untrusted as a network packet. `GameDataRegistry` is
  right to use the static form; its files ship in the APK.
- **Icons and backgrounds are held as PATHS, not textures.** Outside `res://` there is no
  `.import` sidecar and `load()` cannot open them at all. 15.5 goes through `Image.load()`
  when a campaign is **opened** — the background is 1920×1080 and costs a real decode.
- **`progress` is a completion count, so it is also the index of the first LOCKED
  scenario**: 0 unlocks scenario 1 only. Clamped rather than trusted, because it comes from
  a writable file in `user://` a player can edit and a half-finished write can truncate.
- **A campaign cannot reach a phone until 0.3 `AssetPacks` lands.** `user://` on Android is
  internal app storage and is not `adb push`-able, and the override is editor-only.
  Everything in Phase 15 is exercisable on Windows and in the suite; the first on-device
  run waits on 0.3. A real dependency, not a footnote.
- **Settled by the owner and needing no action: a scenario does not leak into the server
  browser.** Solo always fills both slots (one human, one AI) and the browser filters to
  hosts with open space by default, so a tutorial is not advertised.
- **Still owed to the art side:** the dragon footprint answer — wingspan or standing
  ground. `P7-footprint` is a `game-code` card as of the owner's 2026-09-01 swap, so it is
  mine to answer, and `GameView._ring_ground_m` is where the sim-rect / visual-rect split
  is already written down.

### TEAMS — 2026-08-31

`SimPlayer.team` was declared at 0.4 and read by **nothing** for the life of the project.
It means something now: a one-character dropdown beside each slot's colour swatch in the
lobby, `MatchConfig.teams` on the wire, and four hostility predicates that had to be
widened together.

| | |
|---|---|
| the lobby | a `–`/1/2/3/4 picker per slot under a COLOUR/TEAM/TYPE heading row, and the two columns are 50/50 (measured: 544/544 at 1152) |
| the minimap | `ALLY_COLOR` sky blue, measured against both water colours |
| the sim | `Diplomacy.allied` + `MatchConfig.teams` → `SimPlayer.team` → `SimWorld.teams` |
| the four predicates | `Diplomacy.is_enemy`, `.is_enemy_fact`, `CombatSystem._is_at_war_with`, `AISystem._nearest_enemy` |
| the win condition | counts SIDES, and `SimWorld.winner_team` beside `winner_id` |
| the server browser | `ServerBrowserPanel`, behind the lobby's SERVERS button — a wireframe that day, **live the same day** (see below) |

- ⚠️ **THE TEAM ARGUMENT IS REQUIRED, WITH NO DEFAULT, AND THAT IS THE SAFETY PROPERTY.**
  `Diplomacy.is_enemy(e, player_id, teams)` could have taken `teams := {}` and every
  existing call site would have compiled — and every one that was not updated would have
  been a rule silently off in one place, which is §6's `if Net.host() != null and <rule>`
  row wearing a different hat. GDScript reports a missing argument at parse time. An FFA
  caller passes `{}` and says so.
- ⚠️ **0 IS THE ABSENCE OF A TEAM, NOT A TEAM EVERYBODY SHARES.** Two unaligned players
  both read 0, so a rule written as "equal teams are allies" makes the entire back
  catalogue of fixtures one enormous alliance. `Diplomacy.allied` guards it and
  `test_teams` asserts it by name. Gaia is guarded separately for the same reason —
  owner 0 has no row at all, so it would read as 0 too.
- ⚠️ **A TEAM GAME WITHOUT A TEAM WIN CONDITION IS A HANG, NOT A MISSING FEATURE.** The
  moment allies could not attack each other, `_last_man_standing`'s "one player left"
  became unreachable in a 2v2: two teammates standing is two standing players and nothing
  remains that can reduce it to one. `WinConditionSystem` groups standing players into
  SIDES (team, or the negative of the player id for the unaligned), and `winner_id` still
  names the lowest-id survivor of the winning side because it is on the wire and in the
  hash. `winner_team` is what a teammate knocked out on tick 400 reads to be told they won.
- **THE RING OF STARTS IS ALREADY TEAM-SHAPED AND NOTHING WAS DONE TO IT.**
  `_start_positions` spreads players evenly by index, so teams 1,1,2,2 land at 0°/90°
  against 180°/270° — allies adjacent, enemies opposite, for free. **The river is the
  exception and is NOT fixed**: `_river_start_positions` alternates banks by `i % 2` and
  so splits a pair. Fixing it means threading teams through `MapGenerator.generate` for
  one map type; flagged rather than done. The archipelago separates allies by design (one
  island each) and that is a question for the owner, not a bug.
- **WHAT PLAYERS WILL EXPECT AND NOT GET.** No shared vision (one line in `VisionSystem`,
  deliberately skipped — `_reveal` is 32 of 55 ms on an 8-player map and team vision
  roughly doubles the tiles each player lights; measure `test_tick_cost` either side
  before landing it). No shared unit control, no repairing an ally's building, no
  garrisoning in an ally's tower — all owner-gated in the sim, which is why an ally's
  entity taps to SELECT and to nothing else. **And the AI does not cooperate**: no rule
  in `data/ai_*.json` knows what an ally is, so a bot teammate fights in the same
  direction as you by coincidence. It does at least no longer attack you.
- ⚠️ **TWO OWNER CLAUSES DID NOT GO THROUGH `Diplomacy` AND BOTH WERE MISSED FIRST TIME.**
  `StanceSystem._may_start_on` and `AbilitySystem._is_hostile_to` each call
  `_is_at_war_with` for the UNIT half — and each keeps its own `owner_id != owner_id` for
  the BUILDING half, because a building is never gaia's and the shared predicate would be
  answering a question with no useful answer. Both comments say so and both were right;
  what neither could know is that teams widen the owner clause in *both* halves. An
  aggressive soldier would have shot an ally's barracks while quietly doing the right
  thing about their soldiers. **The general form: a predicate split in two for a good
  reason has two places to change, and the half with the good reason attached is the half
  you read.** `test_teams` pins both, and they failed on the run before the fix.
- **THE MINIMAP TINTS ALLIES SKY BLUE** (owner, 2026-08-31, answering the design question
  this pass opened: *"minimap is a problem, lets use your idea and tint allies.. a diffrent
  color maybe sky blue if its not to close to the water colour"*). `Minimap.ALLY_COLOR` is
  `#87CEEB`, and the owner's question is the one worth recording because it was **measured
  rather than eyeballed**: sky blue and `terrain.water_shallow` are **six degrees apart in
  hue**, so hue is not what separates them — CIE `L*` is, at 79 against water's 51 and deep
  water's 30. The pairing that has to work is a SHIP, since an ally in the water is a boat
  and the archipelago is the map built around a fleet. It came out **better separated than
  the enemy red already was** (that is L* 61, only 10 from shallow water). Capped at 79
  rather than pushed lighter, because `DAMAGE_FLASH_COLOR`'s "no blip ever sits near white"
  argument is what reserves the flash. `dev_preview/preview_minimap_teams.tscn` prints
  every figure and saves a **6× nearest-neighbour crop** — a blip is two pixels, and
  `preview_projectiles`' lesson is that "I cannot see it" and "it is not drawn" look
  identical at 1:1. Own and ally stay two colours: you still have to find YOUR units.
- **Colour ASSIGNMENT is still untouched** — every player gets their own of eight, in join
  order, and team-ordered assignment (warm colours one side, cool the other) and an allied
  selection ring are the two ideas left on the table. Neither is needed now that the
  minimap reads correctly.
- **NO INTERACTION WITH AN ALLY'S ANYTHING, CONFIRMED BY THE OWNER** (2026-08-31: *"we will
  not be interacting with any other player units or buildings, no garrison, no repair, no
  healing"*). So `GameView.tap_action`'s ally branch returning SELECT and nothing else is
  the settled behaviour rather than a placeholder, and the owner-gated commands stay
  owner-gated. **The AI's brief is settled too**: *"happy with AI attacking opposing teams
  but not team members thats more than enough for now"* — which is exactly what
  `AISystem._nearest_enemy` does. Do not read the absence of ally co-operation as a gap.
- **`SkirmishScreen` REFUSES A LOBBY WITH ONE SIDE**, and says which team everybody is on
  rather than greying START. It is two presses from the default.
- ⚠️ **A STRETCH RATIO ONLY DIVIDES WHAT IS LEFT AFTER EVERY MINIMUM IS HONOURED**, so
  "50/50" was not two constants — it was three width bugs the split surfaced, none of
  which any test could see. `ChatBoard`'s tab row is 150 px per PLAYER, so four tabs made
  the chat column 670 px of a 1104 px body and ran the setup panels **off the right edge
  of the screen** (eight tabs would have done it to the full-page chat too); the voice
  row's three `CheckButton`s were 545 px more. The tabs now scroll sideways, the voice row
  is an `HFlowContainer` — its minimum is the widest single child rather than the sum —
  and the split measures 544/544. **`clip_text` was the wrong lever for both** and this
  file's own header explains why: it is unconditional, not "shrink if crowded".
  `preview_skirmish._report_columns` prints both rects, at two and at four players,
  and warns on anything past the edge.
- ⚠️ **`clip_text` TAKES A `Label`'s OR `Button`'s MINIMUM WIDTH TO ZERO**, which is the
  point of it and is also two of the defects in this pass's first render: the server
  browser's column headings came out as **a row of icons with no words**, and the team
  picker at a 46 px minimum came out as **an empty red box** — the theme's painted
  nine-patch margins plus the dropdown arrow ate the whole control and the digit was
  clipped away rather than overflowing where it could be seen. A clipped control needs
  its own `custom_minimum_size`, or no `clip_text` at all where every item is one
  character. **Both were invisible to the suite and obvious in the screenshot.**
- **THE SERVER BROWSER WAS A WIREFRAME FOR ABOUT AN HOUR AND IS NOW LIVE** — see the next
  section. The wireframe's own header listed four things a real one needed, in order, and
  all four landed; that list is worth copying as a habit, because writing it down while
  the page was still a picture is what made the wiring pass a matter of following it.

### LAN DISCOVERY — 2026-08-31, PLAN.md 12.1b's discovery half

Typing an IP was the friction point on the hardware playtests and it is now optional.
Owner: *"we built out the wireframe for server browser, lets wire it up and make it live"*.

| | |
|---|---|
| the shout | `LanBeacon` — a JSON datagram at `255.255.255.255:27016` (`Net.PORT + 1`) once a second, while a slot is advertised |
| the listen | `LanBrowser` — binds the same port, holds a **rolling window** over what it hears |
| the page | `ServerBrowserPanel` — six columns, a free-slot filter, REFRESH and JOIN |
| the new field | `MatchConfig.host_name`, a GAME SETUP row, `LanBeacon.default_host_name()` for the default |
| the proof | `tests/net/test_lan_discovery.gd` (two real sockets, one process) and `dev_preview/preview_lan_discovery.tscn` (two processes, real broadcast) |

- ⚠️ **THERE IS NO MASTER SERVER AND THERE MUST NOT QUIETLY BECOME ONE.** An internet
  browser is a service somebody has to run and pay for; this phase's multiplayer is two
  devices on a sofa. `LanBeacon`'s header says so in the file, deliberately, because the
  next person asked for "servers on the internet" will start in that file.
- ⚠️ **A BEACON IS A DATAGRAM AND DATAGRAMS ARE LOST**, which is why a host stays listed
  for `WINDOW_MSEC` (4 s, four beacons) after its last one and why **REFRESH starts the
  window again rather than clearing the list**. A list that cleared and repopulated would
  read as a flicker, and a row that vanished the one second a packet went missing reads as
  a host dropping out — which is the exact thing a player opens this page to learn.
- ⚠️ **THE ADDRESS IS THE TRANSPORT'S, NEVER THE PAYLOAD'S.** `LanBrowser` dials
  `PacketPeerUDP.get_packet_ip()`, so a beacon cannot name somebody else's machine and
  have a stranger's browser dial it. Same shape as `Net._recv_colour_request` resolving
  the asker's slot from the peer id rather than from what the packet claims. Everything
  else in a beacon is a string a stranger wrote: `LanBeacon._clean` caps it and strips
  control characters, and **ids travel while labels do not** — `map`, `mode` and `age` are
  the integers `MatchConfig` holds and the browser resolves them with its own tables, so
  a host cannot put arbitrary text in a column.
- ⚠️ **`JSON.parse_string()` PUSHES AN ENGINE ERROR FOR EVERY PACKET IT CANNOT READ**, and
  this socket is open to whatever the network sends it — so one malformed datagram a
  millisecond is a log somebody can fill from across the room. `JSON.new().parse()`
  returns the error and says nothing. Caught by a single deliberately malformed fixture
  printing "Parse JSON failed" into an otherwise clean suite run. **Anywhere untrusted
  bytes meet a parser, check which form of it talks.**
- **A BROWSER REFUSES ITS OWN PROCESS**, keyed on `LanBeacon.origin()` (process id plus a
  microsecond stamp). `Net.has_session()` is true for a host the moment a slot is opened
  and this page is reached FROM that screen, so a host's own broadcast comes straight back
  on every platform that loops broadcast to local sockets — and a browser listing the
  machine it is running on has already lost the player's trust. `include_self` exists for
  the one-process test and for nothing else.
- ⚠️ **JOIN'S BEING OFF AND ITS REASON FOR BEING OFF ARE TWO FACTS, AND ONLY ONE OF THEM
  IS ALWAYS EXPRESSIBLE.** The first version set `disabled` from "is there a sentence to
  print", which is wrong in the state the page spends most of its life in: an empty list
  needs no sentence — the list says so itself, at length, in the middle of the page — so
  JOIN came out **enabled with nothing to join**. The suite caught it on the first run.
- **THE JOIN IS THE LOBBY'S JOIN.** The page emits `join_requested` and stops;
  `SkirmishScreen` fills its own field and presses its own button. A browser with its own
  copy of `Net.join` would rediscover every failure the lobby already words — already in a
  session, a refused socket, the missing Android INTERNET permission. `_on_join_pressed`
  grew an optional `:port` for this, and **a colon is not a port separator in an IPv6
  literal**: `fe80::1` would otherwise be torn into host `fe80:` on port 1.
- **THE BEACON'S LIFE IS THE ADVERTISED SLOT'S LIFE, AND BOTH ENDS MATTER.** It starts
  when the lobby starts listening (one act, exactly as opening the socket is one act — no
  separate "make me visible" button to forget) and **stops at `_on_start_pressed`**,
  because a match in progress cannot be joined: `Net.start_match` builds the world and a
  peer arriving after it has no map. A beacon outliving its lobby is a row that fails when
  pressed, **and nothing on the hosting machine would ever show it** — the fault appears
  only on the other player's screen. `preview_skirmish._report_beacon` warns on both ends.
- **`taken` IS CHAIRS, NOT HEADS.** A CLOSED slot is in neither the numerator nor the
  denominator: it is room on the map and not a seat, so eight slots with six closed
  advertises "1 / 2".
- **THE LAST COLUMN IS "SEEN", AND IT WAS "PING" IN THE WIREFRAME.** A beacon is one-way,
  so there is no round trip to time and a latency figure would have to be invented — on a
  page whose entire history is about not inventing things. Seconds since the last beacon
  is real, is the number the rolling window turns on, and answers what a ping column is
  actually asked: *is this host still there*.
- **THE PREVIEW SENDS THREE REAL DATAGRAMS RATHER THAN DRAWING THREE FIXTURE ROWS**
  (`preview_skirmish._send_sample_beacons`), which is what the wireframe's `SAMPLE_ROWS`
  constant said had to happen the day discovery landed. The origins are rewritten so the
  page's own refuse-my-own-process rule stays ON in the photograph — turning it off for a
  screenshot would be photographing the page with its safety catch off.
- ⚠️ **THE ONE LINE NO TEST IN THE SUITE REACHES IS `set_broadcast_enabled(true)`.** Two
  `PacketPeerUDP`s in one process are two real sockets (unlike two ENet peers — see
  `test_net_remote`'s header), so the suite's round trip is genuine; it just goes over
  127.0.0.1. Without the flag the OS refuses a datagram to 255.255.255.255 outright and
  **both machines see a browser that finds nothing with no error anywhere near it**.
  `preview_lan_discovery.tscn --role beacon|browse` is the two-process check, and it is
  also the two-machine bring-up.
- 📝 **THE HOST NAME ROW MADE THE LOBBY'S KNOWN FOLD ONE ROW WORSE.** GAME SETUP and MAP
  SETUP already wanted ~700 px in a ~545 px column and already scrolled; this adds ~40.
  Flagged rather than fixed, the same way the fold itself is — see `_PREVIEW_HEIGHT`, and
  note that shrinking the map picture is not the lever.
- 📝 **NOT DONE, DELIBERATELY:** the joined client's invitation line still says
  *"from I. Age of Ash"* and does not name the host, even though `host_name` now travels
  on the lobby config. It is a one-line format change on an already-long line and the
  browser shows the name before you dial; worth doing next to the line, not to the field.

### THE FOUR-DEVICE PLAYTEST — 2026-08-30, six findings, all six closed

**Two Windows machines, an Android handset and an AI**, and the device count is the whole
story of four of them. Read BUGS.md's 2026-08-30 section for the findings; what belongs
here is the three lessons that outlive them.

⚠️ **THREE OF THE SIX WERE THINGS THE DEVELOPMENT SETUP CANNOT SEE, and they share one
shape.** Two were visible only to a joined CLIENT and one only to a FINGER; all three had
been in the code since the feature was written. Everything here is developed solo, on a
desktop, with a mouse — so `Net.host()` is never null and `emulate_mouse_from_touch` is
never the setting a match runs under, and **the branch that is wrong is the branch nobody
takes**. Neither is exotic; both are one grep away (`Net.host()`, and any control that is
not a `BaseButton`). The suite cannot help: 1,779 green tests ran past all three.

⚠️ **`if Net.host() != null and <the rule>` IS NOT A GUARD. IT IS A RULE THAT IS OFF ON
EVERY CLIENT.** Three of `GameScene`'s polite refusals — age advance, train, research —
were written in that shape and were dead for players 2..8 from the day each was added.
The owner reported it as *"player 2 and player 3 does not get alert for not enough
resources"*. **Each one's comment claimed the fix was "a job for the multiplayer phase",
and all three were wrong when they were written**: `SnapshotSystem` has sent every player
their own `stock` for as long as `player_state` has existed, which is exactly why the
**placement ghost was the one refusal that already worked for a joined player**. The rule
is now the ghost's rule everywhere — `PlacementAdvice.can_afford` over
`GameView.stock_of`, one path, both sides. It survives because everything is tested and
played SOLO, where the local player IS the host, so the branch that is wrong is the branch
nobody takes. **Grep `Net.host()` before writing another.**

⚠️ **A MEASUREMENT ANSWERED A QUESTION NOBODY HAD ASKED, AND IT WAS THE MOST USEFUL THING
IN THE ROUND.** The owner asked for wood to be doubled and for a sprinkle; a throwaway
probe that counted wood per map type per player afterwards found the **archipelago at
1,971 per player** against a desert's 4,025 — on the map whose whole point is a fleet, and
in the same session the owner reported that map as too small. Neither half of the wood
pass can reach it (the copse mask is nearly empty on an island; the sprinkle lattice is
laid over a board that is 92% sea and landed **one** tree). It cost ten minutes and turned
two separate reports into one underlying problem. **Count the thing you just changed.**

- **`SimPlayer.defeat_reason`** and `GameScene._announce_defeats` closed the owner's
  *"the server does not notify other players"* and BUGS.md's older *"a forfeit is
  announced as an elimination"* together — they wanted the same field. `SimPlayer.defeat()`
  **keeps the first reason**, because `WinConditionSystem` retests every player every tick
  and would relabel a resignation as an elimination the moment the abandoned base fell. A
  two-player world cannot catch that: `match_over` latches on the first concession.
- **The archipelago's board is now derived from its ISLAND** (`archipelago_side`), where
  the island used to be capped by the board. `ISLAND_RADIUS` 18 → 26, sides 128 / 160 /
  240. **Raising the radius alone makes the islands SMALLER** and that is written down in
  its note: the ring radius subtracts the island from the half-side, so at 26 on the old
  96-tile board the cap lands at 12. The dependency had to be inverted, not re-tuned.
- **`UnitDef.attack_volley`** — the two WARSHIPS and nothing else: `unit.galley` at 10 and
  `unit.galleon` at 15 (the second on the owner's word the same day, *"agreed, lets set it
  to 15 arrows"*). The arrow was never missing: one every 30 ticks, airborne for 2–8 of
  them. `CombatSystem._fan` is shared with the tower's volley so the two cannot fan
  differently. **The pair is asserted as an ORDERING, not as 15 against 10** — the galleon
  leads at every number in its row and the volley is the only one a player reads at a
  glance, so the rule is "the bigger ship throws more" and the figures are inputs.
- **A WATER UNIT STANDING ON LAND CANNOT BE ORDERED TO DO ANYTHING and says nothing about
  it** — `validate()` passes, `PathService` has no start node for its domain, the task is
  retired on tick 1. **The debug map has ZERO water tiles**, so any ship fixture paints a
  channel and calls `PathService.rebuild` (`test_transport._make_a_coast`'s trick).
- **`TouchSlider`** — the volume sliders were **completely inert** on the phone inside a
  match, and worked on the front door's copy of the same panel. See the gotcha table; the
  short version is that a `Slider` reads mouse events only and a match runs with mouse
  emulation off. Measured with a throwaway probe rather than reasoned about, which is what
  ruled out the four likelier suspects (hit-test order, target size, the panel's
  `MOUSE_FILTER`, the ornament that `_VOLUME_TOP` used to work around).
- **`preview_projectiles` had never once caught the trebuchet**, warning every run since
  siege packing landed: 240 catch frames is 40 ticks against an 80-tick deploy. And it was
  photographing the **auto-acquired** volley rather than the ordered one, invisible while
  every shooter loosed a single projectile. Both fixed; all five shooters land a picture.

**Data is complete for the v1 roster:** 31 building defs (19 non-wall plus the
twelve wall/gate pieces) with dense four-age skin maps, 28 unit defs (21 military
and civilian plus seven fauna), all footprints measured (each baked atlas resolved
back through `attribution.actor` to its 0 A.D. template, parent chain walked to
`<Obstruction><Static>`, max taken per axis across the four ages).

**361 atlases staged.** 96 test files (`test_*.gd` under `game/tests/`, counted on disk),
**1877 tests, 210,647 assertions, all passing** — measured 2026-08-31 after LAN discovery
landed, not quoted.
`tools/licence_audit.py`: **PASS, 361 recipes and 150 shipped asset files.**
**RE-MEASURE RATHER THAN TRUSTING THIS LINE**; it is the first thing in the file to rot,
and every previous figure here (1474/83, 1417/82, 1395/82, 1353/80, 1272/78, 1232/76,
293/71/1163) was stale within days — the 342 in an earlier version lasted about six hours.

⚠️ **`test_tick_cost` CAN FAIL FOR REASONS THAT ARE NOT THE CODE, and it did on
2026-08-29.** A baseline run of untouched code reported the 8-player tick at 49.81 ms and
the 2-player at 20.33 ms, both over budget, in a suite that took **594 s**; the same
commit passed both forty minutes later in **350 s**. §6's row says wall-clock timings are
worthless on this workstation and points at `test_tick_cost` as the trustworthy
instrument — that is still true of what it MEASURES, and it is not true of when it is
measured. **Re-run it alone before believing a regression**, and never take a baseline
while another Godot run is still finishing.

**Working end to end:** age skins (Briton → Gaulish → Iberian/Achaemenid →
Roman), per-player colour selection from eight baked atlases, age-gated train and
build menus, a paged build grid, captioned portraits, production queue, a real
timed age-advance, fog of war, an enforced population cap, conquest win
conditions, the PlayTest AI, **two-device LAN multiplayer validated on hardware**
(PLAN.md §12.1 a–g), and the minimap's four corner pages — a working market, a real
tech tree, a chat wireframe, and settings (§8.2b).

### THE UI OVERHAUL — DONE, 2026-08-30, in twelve commits

`asset_request.md` [P8] delivered 130 pieces of project-owned UI art plus two OFL font
families, and this was the game-side landing of it. **It is the largest single change to
`game/` in the project's history**, and the one line worth carrying forward is the one it
was opened for:

> **`game/assets/ui/` is committed in full, and a clean clone runs with its chrome
> intact.** For the whole life of the project until this day it did not: the UI was
> third-party itch.io art whose licence forbids redistributing the originals, so three
> directories under it were gitignored and every developer had to download two packs by
> hand before the game had any panels at all. `tools/licence_audit.py` went from **129
> problems to PASS**, and a good many comments around the codebase still say "the UI art
> is gitignored". They are wrong now.

**WHAT LANDED, `9b0ae14`..`d0cbc9d`, each commit green when it went in:**

| | |
|---|---|
| the art as files | 103 icons at 100×100, 27 chrome pieces into a new tracked `assets/ui/chrome/`, both OFL families with their licence texts |
| icons wired | `SelectionActions.ICONS` 12 entries → 46 plus `STANCE_ICONS`; all five stand-ins retired; `act_guard.png` deleted |
| the action tile | `_FRAME_PATH` → `chrome/tile_frame.png`, in three states, so tiles stopped being double-framed |
| in-match chrome | panel plate, portrait frame, group ring, health bar, toast — plus `tools/prepare_ui_chrome.py` |
| the typeface | which the game had never had at all |
| the menus | nine painted word-buttons → one themed plate plus a label, killing `assets/ui/menu/` |
| the minimap | its ornate frame, and the four corner buttons moved into its bosses |
| the licence retirement | the three directories, the ignore rules, the README, the LICENCES rows, six broken doc links |
| the title card | `splash_screen_c` as both the boot art and the README banner |
| **the owner's first review** | six corrections in one pass — see below |

**WHAT IS LEFT, and none of it blocks anything:**

- **The unused chrome.** `badge_round`, `checkbox_*`, `radio_*`, `tab_plate`,
  `bar_fill_health`, `bar_fill_progress`, `banner_age` and the four `arrow_*` are
  committed and referenced by nothing. Deliberate for the arrows (see `ICONS`' header)
  and simply not-yet-done for the rest — `bar_fill_progress` wants the production queue,
  `banner_age` wants the age-advance notice. **`bar_fill_health` is unused because the
  owner picked something else for the health bar**, which is worth knowing before
  "fixing" it back: see `HealthBarView`. **`badge_round` is the one that needs a DECISION
  rather than work**: [P8] says `res_*` stay circular and get it, and `ResourceHUD` draws
  them at 24 px, where a ring leaves almost no glyph. Either the icon grows or the ring
  does not happen. Raised in `asset_request.md`.
- **`ART_PROMPT.md`'s upcoming set** (§5 of [P8]) is drawn and committed for features
  that do not exist — voice chat, the server browser, the lobby, save/load, replay. None
  of it can be wired and none of it should hold anything up.
- **The `ui_builder` mockups are REPOINTED, NOT UPDATED.** Seven `.tscn` under
  `scenes/ui_builder/` referenced the old art and now reference the new, so nothing
  dangles — but their LAYOUT is the pre-overhaul HUD and is out of step with the running
  game. Nothing instantiates them. Whether they survive is the owner's call, the same
  call that retired `UI_Design.md`.
**THE OWNER'S FIRST REVIEW OF THE FINISHED UI — SIX CORRECTIONS, ALL LANDED, and three
of them were the same mistake:**

⚠️ **A NUMBER MEASURED BY A TOOL THAT WAS ANSWERING A SLIGHTLY DIFFERENT QUESTION.**
That is the shape of three of the six, and it is worth more than any of the individual
fixes. `measure_ninepatch.py` looks for a STRETCHABLE RUN; I wanted the CORNER EXTENT,
and on `panel_ornate` those differ by 70 px, so the margin cut through a dragon's neck
and the neck was in the stretched region. The boss-centre measurement took the centroid
of every dark pixel in a corner quadrant when I wanted the centre of a DISC, and the
four answers disagreed by 18 % — **a measurement whose samples disagree is not a
measurement of one thing**, and I shipped it anyway.

- **`panel_ornate`'s margins are 300 and its edges TILE.** A bead run stretched to three
  times its length is a row of ellipses; `AXIS_STRETCH_MODE_TILE_FIT` repeats it and
  nudges the repeat to a whole bead.
- **`_MINIMAP_BOSS_CENTRE` is 0.109**, from labelling the dark blobs and keeping the
  round one in each quadrant. The four now agree left-to-right, as mirrored art should.
  ~~and that is the fix~~ — **it was still wrong, and the second review below says how.**
- **ONE PREPARED SIZE CANNOT SERVE TWO DRAW SIZES**, which is the 1:1 border trap's
  second consequence and needed a new mechanism rather than a new number.
  `prepare_ui_chrome.py` grew `EXTRA_SIZES`, and `panel_ornate_small` is the resource
  counter's own copy of the menu's artwork at a tenth scale.
- **The health bar is `field_input` + `button_normal`**, not the two pieces named for it.
  Owner's eye, and the reason is shape rather than colour — see `HealthBarView`.
- **The body face is New Rocker and it was chosen on its DIGITS.** MedievalSharp lasted a
  day: *"the numbers on all 3 read hard"*. **That is the right test for this game and it
  is not the obvious one** — an RTS HUD is mostly numbers, and a specimen sheet set in
  words will sell you a face whose 0, 6 and 8 are one shape at 16 px.
  `assets/UI_Gen/font_comparison.png` now leads with `0123456789` and with the strings
  the HUD actually prints. Every rejected face is deleted, source archives included.
- **`NoticeToast` has a paragraph mode** for campaign text (`show_long_message`).
  `LONG_SIZE` is the same ASPECT as `SIZE` and larger, never taller — the banner is a
  fixed composition with a dragon at each end, and a taller box stretches a face. There
  is a test pinning that. **Nothing calls it yet**; 12.3 is unbuilt.

**THE OWNER'S SECOND REVIEW — THREE FIXES AND ONE NOTED, 2026-08-30:**

⚠️ **AVERAGING FOUR DISAGREEING SAMPLES IS NOT HOW YOU RESOLVE THEM — IT IS HOW YOU HIDE
THEM.** The first review's boss-centre fix found the right thing and then threw it away:
having measured four discs individually, it took their MEAN. The minimap art is cleanly
mirrored left-to-right, but its bottom bosses are genuinely bigger and further in than
its top ones — 87 px against 75 on a 512 px frame — so **no single inset can put all
four buttons on their recesses**, and 0.109 left the bottom pair ~3 px low and splayed
outwards. That is the tech-tree glyph overhanging its rim in the owner's screenshot.
`_MINIMAP_BOSS_CENTRES` is now four `Vector2`s and each button is placed on its own disc.
The `GridContainer` went with it, and **two hazards went away rather than being worked
around**: it spanned the whole area, so every piece of it needed `MOUSE_FILTER_IGNORE`
or it ate the minimap's taps, and its middle column began as `VSeparator`s that drew a
line down the map. Four 32 px buttons touching nothing have neither problem to have.

- **CANCEL BUILD is two action tiles by one, bottom-aligned to `SelectionPanel.EDGE_PAD`.**
  It was 280×80 at a literal `-512`, which put its right edge **20 px inside the minimap
  area** — and a typed offset could not know that, because the minimap's left edge is
  `_MINIMAP_MARGIN + Minimap.AREA_SIZE` and neither number was written down there. Every
  figure in `_CANCEL_RECT` is now derived. Owner's ask was to *"match the size of the unit
  action icons row so left and right side of screen line up"*, so it is a whole number of
  `ActionSlot.SIZE` rather than a size that merely looks similar. `SelectionPanel._SLOT_SIZE`
  was deleted on the way past: a second copy of `ActionSlot.SIZE`, referenced by nothing.
- ⚠️ **A NINE-PATCH MARGIN AND A PAINTED MOULDING ARE NOT THE SAME THING**, and
  `ResourceHUD` had been padding to the wrong one. `PANEL_ORNATE_MARGIN` is 30 because
  that is what clears the corner DRAGON; the bead moulding along the edges is 9 px of a
  102 px plate. Content inset at `margin + 4` was therefore clearing a dragon that is not
  there along the middle of a side, and the other 25 px was a gutter nobody chose. Owner:
  *"half the padding inside resource panel"*.
- **HALVING THAT PADDING ALONE WOULD HAVE MADE IT LOOK WORSE**, which is the part worth
  keeping. The rows are left-aligned in a fixed-width box, so the slack is all on the
  right: at 152 wide it was 50 px and a 17 px inset would have grown it to 67. The panel
  narrowed by the same 34 px it stopped padding. Then **a floor that had never bound
  started binding** — `PANEL_SIZE.y` was 196 against a natural 204, so the plate had been
  hugging its rows by accident, and at 167 the 196 reappeared as an empty band under the
  population row. `PANEL_SIZE` is now `PANEL_WIDTH` and the height comes from the content.
- 📝 **THE AGE PANEL NEEDS A REDESIGN AND IS NOT STARTED.** Owner, verbatim: *"i dont like
  the age panel but dont know how to fix it, just note that it needs to be updated."* No
  change was made. What is concretely wrong with it, from the render, so whoever picks it
  up is not starting from "the owner dislikes it": it is the **only chrome left on screen
  using the plain `panel_hud` plate with square corner studs**, beside an ornate resource
  panel and a dragon minimap frame, so it reads as a different family; its two badges are
  **unrelated to each other and to the palette** — a grey ring captioned MAX and a crimson
  ring captioned Idle, in a HUD that is otherwise gold on dark brown — and they differ in
  diameter and caption treatment; and the plate is **deliberately asymmetric**
  (`offset_left -83`, `offset_right 97`), a 14 px shift left from when the pause button
  still lived in it, which nothing now justifies. `banner_age` is committed and unused and
  may be the intended plate. **This is a design decision, not a bug — do not guess at it.**

**THE OWNER'S THIRD PASS — FIVE POLISH ITEMS, ALL LANDED, 2026-08-30:**

| | |
|---|---|
| the under-attack alarm | `DamageAlert` — a 30 s horn and a 2 s white flash on the minimap |
| control groups | separation 8 → 2 |
| the lobby | a starting-age selector for the whole match |
| the chat page | voice toggles on top, a composer at the bottom, all stubbed |
| the tech tree | ages top-to-bottom, techs left-to-right, and a description box on a tap |

⚠️ **`HudPanel.note_label` AUTOWRAPS, WHICH MAKES IT A VBox WIDGET.** Dropped into an
`HBoxContainer` with nothing setting its width, a wrapping Label collapses to its
narrowest possible box and Godot wraps it to **one character per line** — a 300 px
column of single letters that then stretches every sibling in the row to match. **It
shipped into a render twice on the same day**: the tech tree's empty age-1 row (which
pushed ages 2–4 off the page) and the chat page's "no voice channel" note (which
stretched three toggles into playing cards and crushed the message log to nothing).
Neither was visible to a test — both pass every structural assertion. In a row, set
`custom_minimum_size.x` or `AUTOWRAP_OFF`. The helper's own docstring now says so.

- ⚠️ **A REMEMBERED ENTITY CARRIES NO `hp`**, and that is the whole hazard in
  `DamageAlert`. `SnapshotSystem` strips the live fields from anything the player can no
  longer see, so a unit walking into fog arrives with its hp absent — read naively that
  is a fall to zero, and **every scouting villager would blow the horn**. A missing `hp`
  is skipped, never defaulted. `MatchAudio`'s header lists the same three consequences of
  diffing; this is the one that bites harder here than there.
- **THE HORN AND THE FLASH ARE ON DIFFERENT CLOCKS ON PURPOSE.** 30 s global cooldown on
  the sound, none at all on the flash. The sound is a summons and one that fires per hit
  teaches you to ignore it; the flash is what you look at once summoned, so it must show
  *everything* currently being hit or you see one blip out of six. A tidy-up folding them
  into one cooldown would pass every structural check and break the feature — there is a
  test named after exactly that.
- **`starting_age` IS IN `MatchConfig` FOR `mode` AND `colours`' REASON.** Every client
  builds its own world (2.4a), and `age` is folded into `state_hash()` — so two sides
  disagreeing about it is a desync at tick 1 with no explanation attached. `SimWorld.setup`
  **clamps** rather than trusts: it arrives off the wire, and an age past the ladder puts
  every sprite on a skin that does not exist. It unlocks the ladder and nothing else —
  `MapGen` still places one town centre, because starting buildings are the MAP's business.
- **A TECH NODE IS A FRAMED ICON WITH ITS NAME UNDERNEATH** (owner's follow-up: *"we
  are missing the icons ... 9 patch with tab_plate for border, tech icon inside, name
  below outside of the frame"*). The subtitle naming the building and the prerequisites
  had already moved into `TechDetailBox`, which is what left the room for a picture.
  `tab_plate_small` is a second `EXTRA_SIZES` output — same trap as `panel_ornate_small`,
  since a tab's 10 px gold edge is 20 of a 48 px frame's pixels. **The node height is a
  BUDGET, not a preference**: four rows must fit or the bottom age is clipped by the
  horizontal scrollbar, which is what the first render with icons did. `_NODE_SIZE`,
  `_ROW_SEPARATION`, the 11 pt label and the one-line legend are all paying for that.
  Icons come from `SelectionActions.ICONS` — the same map the blacksmith's action tiles
  read, so a tech cannot have one icon on the building and another on the tree.
- **`TechTreePanel.node_for(id)` EXISTS BECAUSE TWO CALLERS WALKED THE TREE FOR A NAME.**
  A node used to be a Button whose `text` was the tech's name; when it became a framed
  icon with a child Label, `text` went empty and both the test and `preview_match`
  silently found nothing. The preview at least warned. Ask by ID.
- **THE TECH TREE'S NODES SHRANK BECAUSE THE BOX PAID FOR IT.** 120×76 → 104×58: the
  subtitle naming the building and the prerequisites moved into `TechDetailBox`. A locked
  node still opens — *"what is Plate Mail and should I plan for it"* is a question about a
  tech you do not have, and nothing is bought on this page anyway. `techs.json` gained a
  `description` for all 27, deliberately **prose and not the numbers**: `effects` already
  carries the arithmetic and the box renders it, so a description saying "+1 melee attack"
  would be a second copy that can disagree with the data.
- **A BOX SIZED "ROUGHLY LIKE THIS TEXT" DROPPED THE TEXT.** `TechDetailBox`'s fixed rows
  — title, state, building, three fact lines, button — come to ~230 px before the
  description gets a line, so trimming the box to look tidy squeezed the scrolling
  paragraph to zero and silently removed the one thing it exists to show. Found in the
  render, not in a test.
- **Everything in the chat page is disabled, and the microphone raises the stakes.** A
  mic that appears live and is heard by nobody is worse than a message that goes nowhere.
  `CheckButton`s rather than buttons so a disabled control still shows its STATE.

**THE OWNER'S FOURTH PASS — FOUR ITEMS, ALL LANDED, 2026-08-30** (`9087a29`, `bad03a4`):

| | |
|---|---|
| the market page | capped at its widest row; the two paragraphs wrap and the title recentres |
| the selected-units roster | tapping a portrait now selects that one unit in the world |
| the production queue | a queued technology draws its icon instead of a bare word |
| buying a technology | the research menu closes, so the queue it went into is what you see |

- **THE ROSTER WAS INERT FOR THE WHOLE PROJECT AND LOOKED FINISHED.** Twelve portraits,
  each a pressable `ActionSlot` emitting `member:<n>`, and `SelectionPanel`'s own comment
  recorded the other end: *"reaches here too and is harmlessly unmatched"*. It drew right,
  took the tap, played the click sound and did nothing. **A control that is wired to
  nothing is invisible to every test and to every screenshot** — the same class as the
  minimap corner buttons, and worth assuming about any grid nobody has pressed on purpose.
- **THE ROSTER IDS ARE SNAPSHOTTED AT DRAW TIME, NOT RE-READ AT PRESS TIME.**
  `GameScene._roster_ids`. If a member dies in the ~100 ms between the two, the live
  selection has closed up around the gap and index n names the unit *after* the one under
  the thumb — and this feature is for fights, which is when members die. Held, the tap
  names what was drawn; if that one died the selection comes back empty, which is true.
  `_garrison_details` indexes for a different reason (a garrisoned unit has no id on the
  wire at all) and cannot do this.
- **A RESEARCH PRESS CLOSES ITS MENU; A PLACE PRESS DOES NOT.** Four lines apart in
  `_on_detail_pressed` and deliberately opposite: placement is a repeated gesture, a
  technology is bought once and its tile comes back greyed with a "…". Staying put read
  as *"the action did not work"*, which is the owner's own wording. **The queue it lands
  on is one snapshot stale and is not made optimistic** — a refused research would have to
  be un-drawn.
- **A CAP IS NOT A WIDTH.** `HudPanel.max_page_width` floors at the screen margin, so a
  screen too narrow to grant it lays out exactly as it did before. `MarketPanel` measures
  its own cap off the row arithmetic rather than naming a number, and the button count
  comes from `market.json` — a fifth tributable resource widens the page instead of
  falling off it. See §6 for why the test drives `_apply_page_width(width)` and not `size`.

**THE LOBBY REWORK — 2026-08-30** (`68a1c6b`, `5b4cb93`), plus two bugs the fourth pass
left behind (`cd5596c`, `0c8d446`):

| | |
|---|---|
| the lobby | chat left ⅔, GAME SETUP + MAP SETUP right ⅓, a three-column nav strip along the bottom |
| the chat page | split into `ChatBoard` (the widget) and `ChatPanel` (the chrome), so the lobby holds the same one |
| the market page | centred, not pinned to the left margin |
| construction | no longer reads as damage — it was blowing the under-attack horn |

- ⚠️ **CONSTRUCTION WAS TAKING NINE TENTHS OF EVERY NEW FOUNDATION'S HEALTH, invisibly,
  for as long as the line existed.** `spawn_building` starts a foundation at `max_hp/10`
  so its dot reads as damaged; `add_build_progress` then set `hp` from
  `build_fraction()`, which on the first tick of work is a few thousandths — 55/550 down
  to 2/550. Nothing could see it until `DamageAlert` began diffing hp, and then it
  correctly reported a fall of 52 as a building being hit. **The general form: a number
  nobody compares across time can be wrong for months.** The fix is `maxi(hp, ...)` —
  construction may only ever raise it.
- ⚠️ **A `VBoxContainer` DOES NOT CLIP OR COMPRESS PAST ITS CHILDREN'S MINIMUMS — IT
  OVERFLOWS.** Eight slots make the lobby's GAME SETUP panel taller than a 648 px
  viewport on its own, so the first render put MAP SETUP and the whole nav strip off the
  bottom of the screen with nothing to say they were there. **Any column whose child
  count is user-controlled needs a `ScrollContainer`, not a hope.** Every structural test
  passed; only the render showed it.
- **AND THE TWO SETUP PANELS STILL DO NOT BOTH FIT.** They want ~700 px at 1152x648 and
  the column is given ~435. **Shrinking the map picture does not move the fold** — the
  fold is where GAME SETUP ends, and that is fixed by its five rows — so 190 → 140 → 112
  changed nothing but how much empty panel sat under the picture. Left scrolling and
  flagged to the owner rather than guessed at.
- **A FOLD CAN MOVE A CONSENT LINE OFF THE SCREEN.** The joined client's invitation terms
  ("Forest, 96 x 96 — seed 4242 — Last Man Standing — from I. Age of Ash") lived only in
  MAP SETUP, which the rework put in the scrolling column. A joining player was being
  asked to press READY to terms that were off the bottom. They are now on the nav line
  beside READY as well.
- **THE JOIN FIELD MOVED TO THE BOTTOM AND THAT OVERRIDES A MEASURED CONSTRAINT.** A
  landscape Android keyboard covers roughly the bottom two thirds (BUGS.md), which is why
  the field was the first row on the page. The owner asked for it in the nav strip. **Needs
  re-checking on the device**; if the keyboard buries it, the fix is to scroll the page or
  lift the strip on focus, not to move the field back.

**THE FIFTH PASS — THE SPLASH, AND HOW TO PLAY, 2026-08-30:**

| | |
|---|---|
| the boot splash | fills the screen instead of hanging off the right and bottom edges |
| HOW TO | `Help.tscn`/`help_screen.gd` — six annotated captures, one to a page (PLAN 1.8) |
| `preview_menus` | photographs the splash and both ends of the guide, and derives what a stretch mode actually paints |

⚠️ **A MINIMUM SIZE BEATS ANCHORS, AND `TextureRect` GIVES ITSELF ONE BY DEFAULT.** The
owner reported the splash "cutting off" on a phone. The obvious suspect is
`stretch_mode`, and it was set to `KEEP_ASPECT_CENTERED`, **which cannot crop anything**
— it fits inside the rect and letterboxes. What was cropping it was the RECT:
`EXPAND_KEEP_SIZE` (the default `expand_mode`) makes the texture's own size the
control's minimum, so `PRESET_FULL_RECT` produced a **1376×768 control pinned to the
top-left of a 1152×648 viewport** and the plate drew at 1:1 with its right and bottom
thirds off the window. `EXPAND_IGNORE_SIZE` is the fix; the stretch mode was never the
bug. **Any `TextureRect` holding art bigger than the box it is dropped into needs
`EXPAND_IGNORE_SIZE`, and the symptom is a crop that no stretch mode on the list
produces.** `HelpScreen` sets it for the same reason (its pages run to 1476 px wide) and
`test_help_screen` asserts it, because the default is not it.

- ⚠️ **A `PRESET_FULL_RECT` CONTROL IS NOT NECESSARILY THE SIZE OF THE WINDOW, and my
  first instrument assumed it was.** `preview_menus._report_boot` derived the painted
  region from `stretch_mode` and the viewport size and **reported a perfect fill on the
  very run whose screenshot showed the strapline sliced in half by the bottom edge.** It
  now reads the control's real rect first and derives the paint inside that, which
  catches both failures with one number. The general form is §6's: *an instrument that
  answers a slightly different question is worse than no instrument, because it is
  believed.* This is the second time in three days — see `measure_ninepatch.py`.
- **THE HELP PAGES ARE A PAGER, NOT A SCROLL, AND THE REASON IS THE ART.** Each capture
  is a full-screen shot of this game with instructions painted over it at a size meant to
  be read full-screen. `Credits.tscn` scrolls because credits are a column of text; six of
  these stacked in a `ScrollContainer` on a handset give each one a sixth of the height it
  was drawn for. One page at a time hands each image the whole window.
- **BUILT IN CODE, UNLIKE `Credits.tscn` NEXT DOOR.** The page list is DATA — six
  near-identical `TextureRect` nodes authored by hand in a `.tscn` is six places to forget
  when a seventh capture lands — and it sidesteps §6's rule that Godot rewrites a
  `.tscn`'s layout properties whenever the project is open. `Help.tscn` is a three-line
  shell like `Boot.tscn`.
- **A TABLE OF FILENAMES STAYS TRUE WHEN THE FILES ARE MISSING.** `HelpScreen.PAGES` is
  six strings; what makes it a guide is six files under `res://assets/ui/help/`, and a
  staged asset that never got committed is invisible on the machine that staged it.
  `test_help_screen` walks the table and asserts `ResourceLoader.exists` on every entry.
- **THE ONE THING NO SCREEN OWNS: THE ENGINE'S OWN BOOT SPLASH.** `boot_splash/image` in
  `project.godot` draws before any scene runs and its scaling is the engine's, not
  ours. What *is* ours is `boot_splash/bg_color`, which defaulted to a light grey that
  flashed either side of the title card; it is now `boot_screen.gd`'s backdrop. **The
  comment explaining that did not survive the next `--import`** — §6's row about Godot
  rewriting `project.godot` and stripping every comment from it, arriving on schedule
  again. The setting survived; the reasoning lives here.

⚠️ **A FONT CANNOT BE IMPORTED WHILE THE PROJECT THEME REFERENCES IT.** Swapping the body
face deadlocks `--import`: `gui/theme/custom` loads at startup, the theme names the new
`.ttf`, the `.ttf` has no `.import` yet, so the load fails and the import never reaches
it. **Comment `theme/custom` out of `project.godot`, run `--import`, put it back, import
again.** Nothing says this; the error is "No loader found for resource".

**FIVE THINGS THIS PASS LEARNED THAT ARE NOT OBVIOUS FROM THE DIFF:**

- ⚠️ **GODOT DRAWS A NinePatchRect's BORDER AT 1:1.** The margin is in SOURCE pixels and
  does not scale with the rect, so `panel_hud`'s measured 46 px border put 92 of the
  resource panel's 152 pixels inside its own frame and clipped every counter.
  **Shrinking the margin is worse than leaving it** — the margin says where the border
  *ends*, so 12 against a painted 46 leaves 34 px of bevel inside the stretched region,
  smeared across the panel. The only lever that moves the drawn border is the SOURCE
  SIZE, which is why `tools/prepare_ui_chrome.py` exists: it rewrites `sliced/chrome/`
  into `game/assets/ui/chrome/` at the size that makes each painted border come out at
  the thickness its widget wants, and prints the per-side margins the `.gd` constants
  then hold. **`game/assets/ui/chrome/` is DERIVED, not a copy** — re-run the tool, do
  not re-copy the masters.
- ⚠️ **SWAPPING ONE FRAME FOR ANOTHER CAN INVERT THE DRAW ORDER, and a filename cannot
  tell you.** Kibyra's avatar frame and slot ring were transparent through the middle
  and were drawn ON TOP; every replacement in this set is a plate with a filled dark
  recess and must be drawn UNDER. Drawn last they cover the picture completely — which
  is exactly what the first `preview_match` after the swap showed, a selected town
  centre with an empty brown square where its portrait goes. **The question to ask of
  any replacement frame is whether its middle is transparent.**
- **A BADGE IS SIZED FOR "84%" AND A PREREQUISITE IS A NAME.** Giving every technology
  an icon gave it a caption, the caption and the badge share the bottom edge, and the
  blacksmith's locked ladder printed each tech's name and its prerequisite's name on top
  of each other. `HudAction.requirement` draws in the COST strip instead, which is free
  by construction: a tech you cannot buy yet is shown no price.
- **`draw_texture_rect_region` HAS NO KEEP-ASPECT MODE**, and both hand-drawn portrait
  slots painted a ~40×70 idle frame into a square. The owner caught it from a screenshot
  ("villager select icon is stretched"). `EntityPortrait.fit` is the arithmetic, and it
  lives beside the crop helper both slots already share so a third hand-drawn slot
  cannot make it again. **The action tiles never had the bug** because they wrap the
  crop in an `AtlasTexture` and get `STRETCH_KEEP_ASPECT_CENTERED` from the engine.
- **TWO MEASUREMENTS IN THE MENUS WERE WORKAROUNDS, NOT PADDING**, and both are gone:
  `PauseMenu._VOLUME_TOP` was 80 because the old plate had a dragon across its top and
  the first slider drew behind it, and `MainMenu`'s bottom margin was 72 because that
  art carried transparent padding so its visible border sat ~36 px inside its own rect.
  Both old comments are KEPT beside the new numbers, because the traps are real and come
  back the day anything goes back to a stretched bitmap.

⚠️ **THE GAME IS CALLED "AGE OF DRAGON", SINGULAR.** `README.md`'s `<h1>` and IDEA.md
line 1 both say so; `config/name="AgeOfDragons"` is the Godot app name and the userdata
folder, and PLAN.md's "Age of Dragons" is the name of AGE IV. **I asked the owner about
the three splash candidates on the premise that their painted title was misspelled, and
it is not** — so their answer ("use C, set the title in engine") was given against a
reason that does not exist. `splash_screen_c`'s title is part of its composition and an
engine label over it would be worse; **use C as it is unless the owner says otherwise**,
and put this correction to them when the splash is landed.

**THE ui_builder MOCKUPS ARE REPOINTED, NOT UPDATED.** Seven `.tscn` under
`scenes/ui_builder/` referenced the old art and now reference the new, so nothing
dangles — but their LAYOUT is the pre-overhaul HUD and is now out of step with the
running game. Nothing instantiates them. Whether they survive is the owner's call, the
same call that retired `UI_Design.md`.

**THE TECH TREE IS WIRED, 2026-08-29 (9.3 + 9.4)** — on the owner's instruction, and it went in
ahead of Phase 5, which is still open. Five things to know before touching it:

- **`TechSystem` DOES NOT EXIST AND SHOULD NOT.** PLAN.md promised one for "research timers,
  stat modifiers". The timers turned out to belong to the production queue -- a research is an
  entry on it and `ProductionSystem` has counted those down since 5.4 -- so a second system
  ticking the same counter would be two owners of it. What was left is the modifiers, and those
  are a pure function of which techs a player holds. `TechMods` is a **static resolver** in the
  shape of `Formation`, `WallPlan` and `Diplomacy`, and the systems table in PLAN says so now.
- **AN EFFECT KEY IS `stat.scope`, AND EVERY STAT NAMES A PER-USE LOOKUP.** That is not a style
  choice, it is the whole design: it means no tech ever has to reach back and rewrite units that
  already exist. The four stats deliberately NOT offered -- `unit_hp`, `building_hp`, `speed`,
  `los` -- and the fifth that was tried and pulled -- `build_rate` -- each have a different
  reason recorded in `techs.json`. **Read those before adding an effect**; `build_rate` in
  particular was written, committed to a tech and removed the same hour, because
  `BuildSystem.BUILD_RATE` is 1 per builder per tick and a percentage has nothing to round to
  below +100%.
- **`TechMods.KNOWN_EFFECTS` IS A CLOSED LIST AND `validate()` CHECKS IT.** An effect nobody
  reads is a tech that silently does nothing, which is indistinguishable from a tech nobody has
  got round to. Same for a mistyped `researched_at` (no button anywhere) and a mistyped
  `requires` (unbuyable forever). All three now fail the suite.
- **COMBAT TECHS SKIP WORKERS AND ARMOUR TECHS DO NOT**, resolved in `TechMods.for_unit` versus
  `for_all` rather than declared per tech. A villager's `attack_type` is melee, so an unscoped
  Blast Furnace takes her from 3 damage to 7 and makes twenty villagers an army.
- ⚠️ **THE AI RESEARCHES NOTHING.** `techs: true` has been in every `ai_profile` since 12.2b
  against nothing, and it still is -- `ResearchCommand` exists and no rule emits one. The AI
  ladder's table in BUGS.md is not invalidated (neither side researches), and **the first rule
  that does research invalidates every row of it**.

**PHASE 4 CLOSED 2026-08-29** — 4.10 abilities, 4.12 stances and 4.14 formations, on the owner's
instruction to close out its open steps. All three had been UI placeholders since 4.3, and that
is most of why they were affordable: the shapes and the slots were already decided, and 4.12 was a
decision `CombatSystem`'s header had written down twice while refusing to act on it. Six things
worth knowing before touching any of them:

- **`StanceSystem` DECIDES AND `CombatSystem` STILL ONLY RESOLVES.** A unit that acquires for
  itself is handed over as an ordinary `Task.ATTACK`, so there is no second combat path and a
  self-started fight is indistinguishable from an ordered one once it has started. That split is
  the whole reason 4.12 is ~150 lines rather than a parallel machine.
- **ONLY AN IDLE UNIT ACQUIRES, so there is STILL NO RETALIATION.** A unit gathering, walking or
  building never reconsiders, whatever its stance — which guarantees no stance can countermand a
  player's order, and is also the half a player is most likely to expect and not get. Noticing
  being hit needs an attacker plumbed through `take_damage`, which `WildlifeSystem` records
  refusing to do.
- **THE DEFAULT STANCE IS DERIVED FROM THREE EXISTING FIELDS AND NOT AUTHORED.** `units.json` has
  no stance in it. `SimUnit.default_stance_for` puts a worker (`is_worker()`), a packing siege
  engine (`packs()`) and anything at `attack_damage <= 0` on PASSIVE, and everyone else on
  DEFENSIVE. **So editing any of those three fields changes what a class of unit does when left
  alone**, and nothing but `test_stances.gd` would report it.
- **`guard_post` DOES TWO JOBS**: the tile a defender owes a return to, AND the flag saying the
  current fight was its own idea. That is why `set_task_attack` grew `keep_post` — **false for
  every order, true for every continuation** (`_close_in`, `_reacquire`). Get that backwards and
  either an ordered assault gets recalled by a leash it never opted into, or a defender wanders
  off after the first re-acquire.
- **A FORMATION IS A PROPERTY OF THE ORDER.** Nothing on `SimUnit`, nothing on the wire — one
  optional field on `MoveCommand`, and `SelectionPanel.active_formation` is a client preference
  like the selection itself. `Formation` is pure integer arithmetic and `SelectionActions.FORMATIONS`
  **is** `Formation.SHAPES` rather than a second list.
- **`ability_target_tile` IS THE AIM AND `task_target_tile` IS NOT.** `set_path` rewrites the
  latter to wherever the route could actually end (4.1), so a dragon that stopped two tiles short
  would breathe fire on its own feet. Two fields, and the second exists only for that.

**AND THE DRAGON WENT TO THE ART SIDE THE SAME DAY** (`asset_request.md` [P7]). Measured, not
assumed: `vis.dragon.atlas.json` carries exactly one clip — `static`, one frame, eight directions
— so it cannot walk, attack, die or decay, and **PLAN.md 13 is blocked on art rather than on
sequencing**. `units.json` has said why since the roster landed (no armature in the source), and
its `speed: 0` is that rather than a balance number. It is also bespoke art rather than 0 A.D.'s,
so rigging it may be real modelling work; the request says to stop and report if so.

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

**THE SECOND PLAYTEST ROUND OF 2026-08-28 — three findings, all three closed.** BUGS.md
has them in full; what is worth carrying here is that **none of the three was a wrong
number**. The tower's damage was right and invisible, the wolf's damage was right and
inescapable, and the arrow's flight was right and left nothing behind.

- **TOWERS VOLLEY NOW.** `attack.volley` (5 for both towers and the castle) plus one more
  projectile per garrisoned archer, **drawn with that archer's own** — a crossbowman in a
  guard tower throws a bolt. The watch tower throws stones; its garrison still shoots
  arrows, because the arrows come from the archers. **The damage is untouched and that is
  what makes it safe**: a projectile carries no damage, so twenty arrows out of a full
  castle are the one 42-damage hit `attack_bonus` already priced. There is a test pinning
  that, because the day a projectile carries a hit the volley silently becomes five
  attacks.
- **A SETTLEMENT DRIVES PREDATORS OFF** — `WildlifeSystem.SETTLEMENT_RADIUS` 15, measured
  from the footprint. The owner's diagnosis is the one to keep: a wolf deals 20 to a 30 hp
  villager who deals 3, so she loses in two bites and needs ten to win — which is *fine*,
  and what was missing was the OUT. `_hunt` re-acquires the moment `CombatSystem` drops
  the task, so a wolf chased a fleeing villager into the town centre and kept eating. The
  retreat **rides `flee_ticks`**, which already means "do not think, you are running", and
  that buys the ignore-`_hunt`, the `run` clip and the relocate for one line each.
- **SPENT SHOTS LIE ON THE GROUND** for four seconds (`SpentProjectiles`), and **none of
  it is in the sim** — see the two §6 rows it produced, both of which are about telling a
  despawn apart from a fog loss and about surviving one snapshot after arriving.

**THE SECOND 2026-08-28 ART DELIVERY ([P1]–[P4]), WIRED THE SAME DAY.** 361 atlases staged.
Most of it was one-line data, and the two places it was not are the ones worth reading:

- **TREE SPECIES ARE NOW PER MAP TYPE**, which is the project owner's own assignment —
  recorded on **line 1 of each `tools/recipes/tree_*.toml`** ("`-- forest pool`"), not
  derived from how a tree looks, and not to be re-derived. `visuals.json` grew
  `variant_pools` beside `variants`: island five palms, forest beech/birch/fir/oak_new,
  river bamboo+palm_date, desert oak_dead+elm_dead. Four things worth knowing:
  **`MapGenerator.pool_name()` is the one place the spelling is decided** and
  `pool_names()` is what `_validate_variant_pools` checks against, so a pool keyed
  "islands" fails the suite instead of silently drawing the general mix forever — the
  failure a data-driven lookup gives you for free is *no* failure at all. **The pool comes
  from `md.meta.type`, NOT `cfg.map_type`**: the latter records what the lobby asked for
  and what it usually asked for is Random, which resolves inside the generator. **An empty
  pool is a real and common state** — the fixed debug map, every preview, every test — and
  falls back to the oak/elm/toona `variants`, which is why those stay declared there.
  **Nothing rides the wire**: the tile seed was already a pure function of position, so the
  pool only decides which list it indexes into, and two clients still agree for free.
- **A CLIP ONLY ONE SPECIES HAS** — see the §6 row. `run` (deer only) and `feeding`
  (cattle only) are sent by `AnimationSystem` for every animal, and `AtlasEntry._ANIM_ALIAS`
  resolves them for the five that have neither. The alternative was a sim asking which
  clips got baked, which it may not do.
- **The five carcasses stopped being deer**: five `visuals.json` entries and five one-line
  changes in `resources.json`. Each atlas is one `carcass` clip of **two** frames at 1 fps
  and does not loop — frame 0 is the animal still standing, frame 1 the body — so a fresh
  corpse falls once and holds. **`vis.tree_banyan` is declared and in NO pool**, awaiting
  the owner's judgement from `dev_preview/preview_banyan.tscn`.

**THE FIRST 2026-08-28 ART DELIVERY, WIRED THE SAME DAY.** 342 atlases staged, and three of
the four pieces needed game-side work:

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
  `EntityView.play_anim`'s per-clip fallback is for. The wolf was 1 of the 6 species in
  [P1]; the other five landed in the second delivery above and animate too.
- ~~**ALL THREE PACKED ENGINES are staged and DELIBERATELY NOT DECLARED.**~~ **STALE, and
  it was already stale when this file was last swept.** `SiegeSystem` landed 2026-08-28
  (`935cc8a`), all three `vis.*_packed` ids are declared in `visuals.json`, and 4.13 is
  closed. Kept as a correction rather than deleted, because the prediction it made was
  right and is worth reusing: the ids went in **with the machine, in one commit**, exactly
  as this said they would. What is still open is cosmetic and is with the art side — the
  packed onager and trebuchet have no colour bakes, so a blue player's engine turns plain
  while it rolls (`asset_request.md` [P6]).

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
and confirmed it: *"sound and speed is much better."*** PLAN.md §15 has been rewritten
around what it left behind. *(This paragraph used to add that PROGRESS.md still listed it
as the top open item and was stale — which it was, and that file was deleted on
2026-09-01 for exactly that habit.)*

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
- **Ships and the DRAGON are static** — no walk clip. This entry used to name the three
  siege engines too and no longer can: their **packed** actors carry `idle` and `walk`
  since 2026-08-28, which is what made 4.13 possible, and `UnitDef.packing` is the second
  speed. A deployed engine still carries `speed: 0` and still should.
  **The dragon is the one left, and it is the worst case**: `vis.dragon.atlas.json` has
  exactly ONE clip — `static`, one frame, eight directions — so it cannot walk, attack,
  die or decay, and `speed: 0` on it means "there is no armature in the source", not
  "slow". **It blocks PLAN.md 13 outright** and went to the art side on 2026-08-29 as
  `asset_request.md` [P7]. Everything else about the unit is real: trainable at the
  castle from age 4, 600 hp, and since 4.10 it has a fire breath.
- **Chat is a wireframe** (PLAN.md §8.2b) and says so on screen: no transport at all,
  and its SEND/CLEAR buttons are disabled rather than made to work locally. **The
  tech-tree page stopped being one on 2026-08-29** — its renderer was always real and
  9.3 gave it 27 technologies to render.
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

0. **PHASE 5, BUILDINGS — the owner's call on 2026-08-29, immediately after phase 4 closed.**
   Two open rows and they are very different jobs. **5.7, the full roster**, is 23 buildings
   and its own line has always said "low code effort, ~70 bakes behind it" — so it is paced by
   the art side's A.10 and not by anything here. **5.3, building upgrades, is the code half and
   is already half-built**: `BuildingDef.upgrades_to`, `UpgradeBuildingCommand` and
   `SimWorld.convert_building` have shipped a real upgrade since 5.8 — the wall-to-gate
   conversion, which mutates in place and keeps the entity id rather than respawning, because a
   respawn would empty the panel the player just pressed. What is missing is everything a
   non-gate upgrade needs: a **cost** (the gate inherits the wall's) and a **time** (it is
   instantaneous). The third thing it needed — a decision about whether an upgrade is a
   per-building action or a player-wide tech — **is answered.** 9.3 shipped first, on the owner's
   ruling that *"upgrades are action tiles on buildings"*, so the two are two mechanisms: an
   upgrade changes ONE building and stays `UpgradeBuildingCommand`; a technology is the
   player-wide thing bought at one. And the queue 9.3 taught to hold a research is the obvious
   place to put an upgrade's time.

*The three items below predate 2026-08-29. Item 1 is stale in one direction (the AI table was
re-measured on 2026-08-27 and every winner held) and item 2 is DONE — 2.4d Archipelago shipped
2026-08-29 with transports, which had to go with it.*

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
2. ~~**2.4d Archipelago** (§11.6).~~ **DONE 2026-08-29** (`6d277da`, `bb15cbc`), and it did not
   ship alone: transports had no load/unload, so **an archipelago was a map on which no player
   could reach another** and no win condition could fire. The two went together rather than the
   map type going out as a sandbox. The connectivity claim did *change* rather than relax, as
   predicted. **What is still missing is naval COMBAT** — a loaded transport crosses unopposed,
   which is what an archipelago will ask for next and is not what makes it playable.
3. ~~**9.3 `TechSystem`**~~ — **BUILT 2026-08-29**, ahead of item 0, on the owner's instruction.
   See §7's opening block. What it did NOT close: the AI still researches nothing, and the
   `TechSystem` this item named turned out not to want to be a system at all.

**Closed off this list rather than deleted, because each says something about how the
list moves:** 4.8 garrison and 4.9 (2026-08-27) did **not** close the wall hole they were
billed as closing — the owner ruled walls out — and 8.8's [X] button (2026-08-28) turned
out to be a layout problem rather than a UI one.

Then, in no forced order: 2.4c the map save format, 12.1b LAN discovery, 12.3 campaign, naval
combat, Phase 14's AI enemy-blindness, and **13.x dragons — which is now blocked on ART rather
than on sequencing**: `vis.dragon` carries one clip, `static`, so the unit cannot walk, attack
or die. `asset_request.md` [P7].

*This paragraph used to list 12.2b's AI decision flow and 4.13's pack/unpack machine. Both
shipped (2026-08-27 and 2026-08-28) and this line did not notice for two days, which is the
same rot the suite figures above carry a warning about. Check `git log` against it.*

---

## 8. For the art agent

See **[AGENT_ASSET.md](AGENT_ASSET.md)** for their side: recipes, bake batches,
staging, the isobake pipeline, and what they consider stable versus in flux.
That file is theirs to write and maintain — I do not edit it, the same way they
do not edit this one.

If the two documents ever disagree about the fence between us, the disagreement
itself is the thing to fix — raise it in `asset_request.md` rather than quietly
picking a side.
