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
| `tools/` | isobake recipes + bake/stage scripts — the art agent's. **Four things in it are MINE and that is by agreement, not by drift**: `stage_audio.py` and `licence_audit.py` (settled in `asset_request.md`, 2026-08-23 — *"leave it exactly where it is, and keep owning it"*, on the principle that ownership follows who can maintain a thing), `prepare_ui_chrome.py` (added 2026-08-30, same arrangement: it decides what size a WIDGET wants, which is a layout question), and **`build_packs.py` + `packs.source.json` (added 2026-09-03, phase 0.3)** — the owner was offered the narrower split, where I write only the content packer and request the art `.pck` packer from the art side, and chose *"Assign build_packs.py to me too"*. ⚠️ **THAT ONE IS THE EXCEPTION THAT IS NOT SELF-JUSTIFYING.** The other three are things only I can maintain; this one reads the art pipeline's bake output to build the art pack, which is the art side's business, so it is mine because the owner said so and not because the principle points here. ⚠️ **THE ART HALF LANDED 2026-09-12 AND THE OWNERSHIP QUESTION IT WAS FLAGGED FOR DID NOT ACTUALLY ARISE** — and the reason is worth keeping, because it is what would make it arise later. The packer reads **`game/data/visuals.json`**, which is mine, and never the staged directory: it resolves what the SEAM can ask for and takes the files that answer. So it knows nothing about how atlases are staged, named or baked. **If it ever needs to — if which atlas goes in which pack becomes a colour or staleness judgement rather than a path lookup — that is the moment to raise the fence again**, and the art side said the same thing in `asset_request.md`. Everything else in `tools/` I read and never edit |
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
- ⚠️ **FOUR API READINGS LOOK EXACTLY LIKE A FAILURE AND ARE NOT.**
  `GET /views/{v}/tasks` never populates `bucket_id`; `GET .../buckets` reports
  `count: 0` for every bucket; and PowerShell's console prints `campaign â scenario 3`
  for text the server stores correctly as an em dash. **`GET .../buckets/tasks` is the
  only authoritative bucket→task mapping**, and §2's "a `Get-Content` dump is not
  evidence" rule extends to `Invoke-RestMethod` piped to a terminal. All three cost a
  false alarm on the day the board was seeded.

  **THE FOURTH, 2026-09-06: A READ-BACK IN THE SAME PROCESS AS THE WRITE CAN RETURN THE
  OLD VALUE.** Adding the `next` label to `11.x-trophy` wrote correctly and then read
  back unchanged, so a verify-after-write reported the write as a silent no-op — and the
  diagnosis that followed (*"`labels/bulk` does not replace an existing set"*) was
  **wrong**; the very next run found the label already there. **The write had worked all
  along.** Verify in a SECOND invocation, or with `show`, and treat an immediate read-back
  as advisory. The general form is this section's own: *the failure mode of this API is a
  reading that looks broken, not a write that is.*

  📝 **Labels are still not a CLI verb, and this did not make them one.** `card_game.py`'s
  header explains why — a tag swap between the three sides is the owner's, done in the UI.
  A one-off scoped write for a card that stays `game-code` is a different thing, and the
  endpoint that is safe for it is **`PUT /tasks/{id}/labels` with `{"label_id": N}`**,
  which ADDS. `.../labels/bulk` REPLACES, so sending only the new label would strip
  `game-code` and leave the card unwritable from this tool — the exact clobber
  `vikunja_sync.py` was deleted for.
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
& $godot --path game res://dev_preview/preview_scenario_hud.tscn    # briefing + objective tracker
& $godot --path game res://dev_preview/preview_scenario_hud.tscn -- --scenario 2
& $godot --path game res://dev_preview/preview_campaign.tscn        # list -> scenarios -> PLAY -> match
# EVERY SHIPPED SCENARIO DRIVEN TO ITS WIN, headless, through the real launch path. The one
# check that can say an authored objective is both REACHABLE and not satisfied on tick 1 --
# it prints each row and the per-tick progress array. Settled 16.6's scenario-4 lose row in
# one run after a unit test had reported the opposite (see §6, the MapGen.build row).
& $godot --headless --path game res://dev_preview/PreviewScenarioWin.tscn
& $godot --path game res://dev_preview/preview_campaign.tscn -- --scenario 1
& $godot --path game res://dev_preview/preview_saved_map.tscn       # 16.0: pick a SAVED map, play it
& $godot --path game res://dev_preview/preview_saved_map.tscn -- --force   # re-roll the sample map
& $godot --path game res://dev_preview/preview_dragon_nest.tscn    # 13.2: the nest, and the 20% hatchling

# The FIRST BOOT, in its four states -- offline, downloading, skipped, failed. Four
# screenshots plus every control's rect measured against the viewport.
& $godot --path game res://dev_preview/preview_download_screen.tscn

# 0.3's ART PACK. EXIT CODE IS THE ANSWER. Headless, no screenshots -- it compares the
# built zips against what the SEAM can ask for, which is a question no picture answers.
& $godot --headless --path game res://dev_preview/preview_art_pack.tscn
& $godot --headless --path game res://dev_preview/preview_art_pack.tscn -- --pack <path>
# ⚠️ AND THE ONE RUN THAT PROVES THE PACK RATHER THAN THE STAGED TREE -- see §6:
& $godot --headless --path game --export-pack "Windows Desktop" out.pck   # atlases EXCLUDED
& $godot --headless --main-pack out.pck res://dev_preview/preview_art_pack.tscn -- --pack <abs zip>

# LAN discovery, TWO PROCESSES — the only thing that exercises the broadcast flag.
# Start the beacon first; it waits. The exit code is the answer.
& $godot --headless --path game res://dev_preview/preview_lan_discovery.tscn -- --role beacon
& $godot --headless --path game res://dev_preview/preview_lan_discovery.tscn -- --role browse

# The facing trio — how a re-baked atlas gets checked (see §6, the mirror item)
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

`preview_scenario_hud` launches a real campaign mission through the real path
(`Net.pending_match`, then `Game.tscn`) and photographs the two things 15.6 added: the
briefing modal, and the objective tracker with one row ticked. **It INJECTS an `alert`
objective**, because no shipped scenario has one and the banner half of the feature would
otherwise be photographed empty — the injected row is the script's and not the file's.
Three faults it can see that no headless test can: a tracker that overlaps the
control-group stack, one that runs off the viewport, and a banner that is not on the
screen's axis. All three are measured and warned about rather than left to the eye.

`preview_saved_map` is 16.0's proof and it **authors the sample map it needs** — `maps/sample_duel`,
written once and committed, because a picker with nothing in it cannot be shown to work and
repo-root `maps/` is empty until the MapMaker exists. It refuses to overwrite without `--force`
(`preview_author_maps`' rule: the file is authored content under version control). The load-bearing
step is the last one: it starts a real match from the config and compares the world's buildings and
**every terrain tile** against the FILE, because a screen that previews a saved map and hands the
match a generated one looks perfect in both screenshots.

⚠️ **IT COST TWO RED RUNS AND BOTH ARE WORTH KNOWING.** (1) **Raising the slot count adds ROOM, not
players** — new slots default to `CLOSED`, which is the whole point of `_slots` versus
`_active_slots()`. The first version moved only the count picker and reported the seat gate as
broken; `can_start()` was right and the way of exercising it was not. Seating N players means
setting N-1 **roles** too, and `_seat_players()` in both the preview and `test_skirmish_screen` now
carries that. (2) **`SimBuilding` has `origin_tile()`, not `origin`** — `pos` is the footprint's
CENTRE in sub-tile units, so `pos / SUBTILE` is five tiles off the `MapData.tile` for a 10×10 town
centre: far enough to read as the map having been ignored entirely.

`preview_campaign` walks the whole campaign path pressing the REAL buttons — CAMPAIGN list
→ the scenario list with its locks → PLAY → a match with its briefing up — and prints the
unlock table, which is the same fact the owner reads off the screen by which rows are
bright. ⚠️ **It performs the two scene changes ITSELF**, because
`get_tree().change_scene_to_file` from a preview would replace the preview: each press is
made with the screen out of the tree (the branch the suite uses), and the next scene is
instantiated **from the constant the screen it just pressed names**, so a wrong constant
shows up as the wrong screen. What it covers is the two HANDOFFS — `ScenarioScreen.pending`
and the config `launch()` builds — which is where a live object crossing between screens
can be dropped. What it cannot cover is that the scene change is reached.

`preview_dragon_nest` is 13.2's eye. It stands the nest, a villager, the mother and the
**hatchling** on one patch of grass, because 20% of something is a number and whether it reads as
a juvenile dragon is a question for a person. It also prints the half a screenshot cannot settle:
**where the feet went.** A sprite scaled about its frame's corner and one scaled about its ANCHOR
are both small dragons in a picture and several metres apart on the ground — so it prints the
drawn rect and the anchor for both, and warns if the hatchling's `footprint_m` and its `scale`
have drifted apart (those two agree by hand, deliberately — see `visuals.json`'s note).

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

`preview_art_pack` is 0.3's art half and it exists because **this workstation cannot fail the
obvious test.** `game/assets/atlases/` is staged here and `res://` beats a mounted pack, so a
check that mounted the pack and asked the seam to draw would pass with no pack on disk at all.
So it asks three things a staged tree cannot answer for: every path `atlas_path_for()` can
produce is in a zip (the SEAM's derivation against the PACKER's, independently computed);
member names are shaped so `PackInstaller` would accept them; and pages decode. **The fourth
section, `seam:`, is the only end-to-end proof available without an APK** — run under
`--main-pack` off an export with `assets/atlases/` excluded, every id that comes back real
came out of the mounted zip.

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

### The MapMaker — a SECOND Godot project (Phase 16, started 2026-09-04)

`MapMaker/` is its own project on the same pinned 4.7.1, PC only, never shipped. **`--path`
points at it instead of at `game/`**, and it has its own suite:

```powershell
& $godot --path MapMaker                                     # the window -- opens straight into the editor
& $godot --headless --path MapMaker res://Boot.tscn --quit-after 2   # the startup report; EXIT CODE IS THE ANSWER
& $godot --headless --path MapMaker res://tests/run_tests.tscn
& $godot --headless --path MapMaker --import                 # its own class cache, separate from the game's

# 16.2's two checks. The first authors a map WITHOUT a mouse; the second plays it IN THE GAME.
& $godot --headless --path MapMaker res://dev/author_map.tscn            # writes maps/river_demo
& $godot --headless --path MapMaker res://dev/author_map.tscn -- --force # re-roll it
& $godot --path MapMaker res://dev/preview_editor.tscn                   # 21 screenshots
& $godot --path game res://dev_preview/preview_saved_map.tscn -- --folder river_demo
Remove-Item -Recurse -Force maps\river_demo                              # ⚠️ AND THEN DELETE IT

# 16.4a's check: open every REAL map on this machine and round-trip it. EXIT CODE IS THE ANSWER.
& $godot --headless --path MapMaker res://dev/open_map.tscn
& $godot --headless --path MapMaker res://dev/open_map.tscn -- --folder sample_duel

# 16.x-slow-place: HOW FAST IS IT? A window, not headless -- it measures frames. EXIT CODE IS THE ANSWER.
& $godot --path MapMaker res://dev/profile_editor.tscn
& $godot --path MapMaker res://dev/profile_editor.tscn -- --folder river_demo --budget 250
```

⚠️ **A SLOWNESS REPORT IS ANSWERED WITH `dev/profile_editor.tscn` AND NOT BY READING THE CODE.**
Two have now come off the owner's machine and **the second could not be diagnosed by reading**:
every candidate on the click path is cheap on paper (`claimed_tiles()` 0.6 ms, `add_entity()`
1.5 ms, `Startup.can_save()` a field read, the palette does not rebuild), and the cost was
somewhere nothing pointed. It prints four things that fail in different directions — the idle
frame, the redraw split into terrain and entities, the document ops with no drawing in them, and
click-to-a-drawn-frame — and exits non-zero over a 100 ms budget.

⚠️ **THE ONE IT WOULD BE NATURAL TO LEAVE OUT IS THE IDLE FRAME, AND IT IS HALF THE ANSWER.** A
`CanvasItem`'s draw commands are re-rendered **every frame**, not once per `_draw`, so 9,216
`draw_colored_polygon` calls ran the tool at **22 fps sitting still**. That is why the report
opens *"the tool is very very slow"* and only then names one operation: everything was queued
behind the same command list. A script that timed only the click would have called the click
fixed and left the tool slow.

📝 **AND THE PROFILER'S OWN TRAP, PAID FOR ON THE FIRST RUN:** it printed
`Performance.TIME_PROCESS` beside the frame time as *"of which N ms in script"* and reported
**276.9 ms against a 42.8 ms frame** — a figure that cannot be true of the thing beside it,
because the script spends its own frames inside `await`. Removed rather than explained. §6's rule
about the status line's stale zoom applies harder to a profiler: **a number that is quietly wrong
is worse than no number, because it gets believed.** Same shape a second time ten minutes later —
the geometry benchmark went on calling `_diamond()` per tile after `_draw_terrain` had stopped,
and reported 78 ms against a 28 ms whole redraw. It now times **both** routes and labels which is
which.

⚠️ **`maps/` IS AUTHORED CONTENT, NOT A SCRATCH DIRECTORY — DELETE YOUR TEST MAPS** (project
owner, 2026-09-04: *"don't commit random test maps to the repo, always delete test maps unless
deliberately created as demo content for people cloning the repo"*). `maps/river_demo` was
committed on the 16.2 round trip and should not have been: nothing depends on it existing and
`author_map.tscn` writes it again in seconds, so it is a build artefact that happened to land
in a tracked folder. Removed.

**THE ONE EXCEPTION IS `maps/sample_duel`, AND IT IS DELIBERATE.** It is committed so the suite
runs on a **clean clone** — `test_skirmish_screen.test_the_committed_sample_map_reaches_the_picker`
asserts it is discoverable, and a picker with nothing in it cannot be shown to work. The other
tests in that section skip rather than fail when it is missing; that one does not. **Do not
tidy it away.**

⚠️ **THE TWO-COMMAND ROUND TRIP IS THE ONLY THING THAT PROVES PHASE 16'S CONTRACT**, and it
needs both projects: `author_map` writes the file, `preview_saved_map --folder` plays it and
compares **every terrain tile** of the running world against the file. Neither process can
check the other, which is decision 2's whole point — the FILE is the contract, not the code.
MapMaker screenshots land in `%APPDATA%\Godot\app_userdata\AOD_MapMaker\`, NOT in the game's
`AgeOfDragons` folder. ⚠️ **THIS FILE SAID `AOD MapMaker`, "note the space", AND THAT WAS
WRONG** — measured 2026-09-08, the shots are written to `AOD_MapMaker`. Both folders exist on
the owner's machine, which is what makes the mistake survivable and worth naming: an old one
from before the project was renamed sits beside the live one, so a session looking in the
wrong place finds a directory with plausibly stale pictures in it rather than nothing.

### Working on the MapMaker — what is not in PLAN.md

**PLAN.md §11 Phase 16 carries every decision and every row's reasoning.** What belongs here is the
handful of facts that are about *working on the tool* rather than about what it is.

- ⛔ **NEVER EDIT `MapMaker/format/*`.** They are hash-checked verbatim copies of game files —
  re-copy from `game/` instead. Drift in `COPIES` **disables saving**; drift in `PRESENTATION` is
  only a status-line note. The test for which list a new copy belongs in is **does the drift reach
  the file?** A map written by a drifted *icon* reader is byte-identical.
- ⛔ **`--import` EACH PROJECT SEPARATELY.** Two Godot projects, two class caches, two `user://`
  directories, two suites. A new `class_name` in MapMaker is invisible until **MapMaker** is
  imported, and importing the game does not help.
- ⚠️ **MapMaker screenshots land in `%APPDATA%\Godot\app_userdata\AOD_MapMaker\`**, not the game's
  `AgeOfDragons` folder. An old `AOD MapMaker` directory — with a space — also exists on the
  owner's machine from before the rename, so a session looking in the wrong place finds a folder of
  plausibly stale pictures rather than nothing.
- ⛔ **`Editor.tscn`'s ROOT HAS NO `class_name`.** In the `dev/` preview scripts `_editor` is a bare
  `Node`, so its calls return untyped `Variant` and `:=` cannot infer — **declare the type**
  (`var panel: ConditionPanel = ...`). Get it wrong and the *whole file* fails to parse, the scene
  never loads and `_ready()` never runs: headless that is a silent hang, windowed it is a clean
  **exit 0 with no screenshots**, and neither looks like a parse error.
- ⚠️ **`MapDocument.save(dir)` TREATS ITS ARGUMENT AS THE PARENT** and appends `slug()`. A test
  that then reads `dir/map.json` is reading a path the save never wrote.

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
| **A staged tree is not a declared tree, and this file has claimed otherwise** | `vis.tree_cherry`, `_cypress`, `_cypress_tall`, `_snow_pine`, `_dead` and `_dead_branchy` are staged and referenced by nothing — an earlier session told the art side that the two dead ones were "staged and wired today" and they were not. They predate the per-map pools and carry no pool assignment, so they were left out of them deliberately rather than missed. **Only a def or a pool reaching for an id proves it is wired.** |
| **Compensating for a bake defect in the game** | Tried once — the 180° facing offset, 2026-08-22 — and reverted the next day on the owner's instruction. The rule they set: an art defect gets fixed in the recipe, and a patch that must be un-applied in step with a delivery is not worth carrying for a partial result. Report it in `asset_request.md` with a picture instead. |
| **A CONTROL DRIVEN BY MOUSE EVENTS IS INERT UNDER A THUMB INSIDE A MATCH — and `BaseButton` is the exception that hides it** | `emulate_mouse_from_touch` is off for exactly as long as a match lasts (`GameScene` turns it off on entry, `_exit_tree` hands it back), so Godot's `Slider`, which reads `InputEventMouseButton`/`InputEventMouseMotion` and nothing else, does nothing at all. **A button DOES answer a raw touch**, so every HUD control anybody had pressed worked and the three volume sliders — the only non-buttons in the game — were dead from the day they landed (owner, 2026-08-30). Measured on 4.7.1: an `HSlider` at 0.50 tapped at 95% of its track reads **0.50** with emulation off and **0.95** with it on. `TouchSlider` and `TouchLineEdit` are the pattern; **never the project setting**, because a flag toggled per screen has to be un-toggled on every path out and the failure is a silent double-pan for the rest of the match. |
| **A `Range` OUTSIDE THE TREE MOVES SILENTLY — `value_changed` is not emitted at all** | `Range::Shared::emit_value_changed()` skips every owner whose `is_inside_tree()` is false, so a detached slider's value changes and no listener hears it. Free in the game; a trap in a headless test, because *"the slider did not move"* and *"the signal is not wired"* then look identical. **Assert the VALUE.** Same family as the `PRESET_FULL_RECT` row below — a Control does a surprising amount of nothing until it is in a tree. |
| **Touch does NOT take keyboard focus, so every new text field needs `TouchLineEdit`** | `emulate_mouse_from_touch = false` ([project.godot:35](game/project.godot#L35)) is *required* — `CameraRig` handles both `InputEventScreenDrag` and `InputEventMouseMotion`, so a touch arriving as both pans twice per thumb. Godot still routes raw touches to controls, but the touch path takes no focus and `LineEdit` asks for the keyboard on focus-enter. Measured on 4.7.1: focus after a screen touch = false, after a mouse click = true. Flipping the setting fixes typing by breaking the camera. |
| **A `Control` laid over the minimap swallows every tap** | The four corner buttons were a `PRESET_FULL_RECT` grid added *over* it and Godot hit-tested them first — minimap click-to-move and double-tap-to-centre were both dead while looking implemented. Check hit-test order before concluding a minimap feature is missing. |
| **`JSON.stringify` encodes a `PackedByteArray` as a STRING** — `"[1, 2, 250]"`, verified on 4.7.1 | It bit `MapData.from_dict()`, which now reads bytes, JSON's string, or a plain list. Relevant to 2.4c's saved sidecar and 12.4's save/load — the next two places sim data goes through JSON. Everything else there was already defended with `int()` because JSON numbers come back as floats; `terrain` was the one field that looked like it needed no conversion. |
| **Wall-clock timings are worthless on this workstation** | The same seed ran 41.3 s and 161.0 s; the suite swung 34 s to 110 s across four runs of identical code. Do not conclude anything from how long a run took. ⚠️ **This row used to end "Trust `test_tick_cost`, which reports per-system milliseconds" — and on 2026-09-11 that test was itself the thing that was wrong.** It swung **6.72 → 22.38 ms** on one 2P fixture across a single day against a **fixed 20 ms tripwire**, failing three runs in a row and then passing at **3.71 ms** on the same commit. Its per-system numbers are still the right instrument for *comparing* systems; its threshold is not evidence on its own. |
| ⚠️ **THE OWNER PLAYING THE GAME WHILE THE SUITE RUNS FAILS IT, IN TWO SIGNATURES THAT BOTH LOOK LIKE CODE** | Both cost real time on 2026-09-11 and both are diagnosable in seconds once you know the shape. **(1) `test_net_solo` / `test_net_remote` fail with `expected 0, got 20`** — `ERR_CANT_CREATE` from `host()`, because the running game holds the loopback port. Everything after it cascades into `Nil` script errors on `Net.host()`, which reads like a broken refactor and is a busy socket. **(2) `test_tick_cost` fails with EVERY system 2–4× slower — uniformly.** That uniformity is the whole tell: `ai_system` 3.6×, `garrison_system` 4.5×, `projectile_system` 2.7× in one run. **No real regression makes twenty unrelated systems slower by the same ratio**, so if the system you actually changed moved by the same factor as the ones you did not, it is the machine. Ask what else is running before reading either as a defect — and note the owner may be mid-playtest without having said so. |
| **`run_tests.gd` HAS NO FILTER, so "re-run it alone" cannot be done** | the standing advice for a suspected `test_tick_cost` flake is to re-run it in isolation, and there is no way to: the runner discovers every `test_*.gd` under `res://tests/` and takes no arguments. The only instrument available is another full ~10-minute run, which is why the *shape* of the failure (the row above) matters more here than in a project where you could just re-run the one file. A `--only <file>` argument is about ten lines and has been proposed to the owner rather than added. |
| ⛔ **EVERY DIRECTORY IN THIS REPO IS WINDOWS READ-ONLY, AND WINDOWS WILL NOT REMOVE A READ-ONLY DIRECTORY EVEN WHEN IT IS EMPTY** | Google Drive sets the attribute on the whole tree — `game/`, `MapMaker/`, `tools/`, the repo root, all of it. Files delete normally; `RemoveDirectory` returns ACCESS DENIED (Godot `err=1`). So **any recursive delete in this project takes out the FILES and leaves the FOLDERS**, and both helpers that do it ignored or only warned about the failure. That is what left `user://content/scenarios/HowToPlay/scenario_1..5` as five empty directories after a `preview_content_browser` uninstall. `FileAccess.set_read_only_attribute(globalized, false)` clears it — **on a directory, verified on 4.7.1** — and `PackInstaller._cleared()` is now the one place that does it. ➡️ **Suspect this before suspecting the delete logic**: the `_rm_rf` in `test_campaigns` was correct code that could not work, and a replica built in-process deleted perfectly because the replica was not read-only. |
| ⛔ **THE "SHADOWED CAMPAIGN" SUITE FAILURE WAS A CODE BUG, AND THIS FILE CALLED IT ENVIRONMENTAL FOR TWO DAYS** | `test_campaign_screen::test_the_shipped_campaign_loads_without_complaint` failed with *"campaign 'HowToPlay' in `user://content/scenarios/` is shadowed by …"* and it was written off here as *"0.3's content-install path, the owner's data, ask rather than tidying it away"*. **Nothing was installed.** The folder held zero files — it was the read-only husk above — and `Campaigns.discover()` warned about it because **the shadow branch returned before ever asking whether the folder was a campaign**, a question `_read_campaign` has always asked and answered in silence. Two facts, one of them computed from a folder name alone: the `ServerBrowserPanel` JOIN-button row, four hundred lines up, in a different file. ➡️ **A failure explained as "the owner's data" is an explanation that ends the investigation — go and look at the data before writing that down.** Fixed 2026-09-12 by `Campaigns._is_campaign_dir()`. |
| ⚠️ **THE GAME SUITE DELETES AN INSTALLED `HowToPlay` PACK** | `test_campaigns.after_each` `_rm_rf`s `user://content/scenarios/HowToPlay` unconditionally, because the shadow test must use the real campaign's name to prove anything. It always did this; until the read-only fix it merely failed halfway and left the folders. **So a genuinely installed pack does not survive a test run** — worth saying out loud before the owner installs one to playtest and finds it gone. Not changed unilaterally: the alternative is backing the folder up around the run, which is more machinery than the trap deserves without the owner's say-so. |
| ⚠️ **AVERAGING FOUR DISAGREEING SAMPLES IS NOT HOW YOU RESOLVE THEM — IT IS HOW YOU HIDE THEM** | Four measurements that disagree are four answers to four slightly different questions, and the mean of them answers none. Find out why they differ first. The UI overhaul's three worst corrections were all one shape: **a number measured by a tool that was answering a slightly different question**, trusted because it was a number. |
| ⚠️ **A REMEMBERED ENTITY CARRIES NO `hp`** | Anything reconstructed from a client's memory of a snapshot rather than from the snapshot itself has the fields the memory kept, not the fields the type declares. A panel that reads `hp` off one shows an empty or zero bar on something that is perfectly healthy, and only for entities the fog has touched. |
| ⚠️ **`HudPanel.note_label` AUTOWRAPS, WHICH MAKES IT A VBox WIDGET** | Dropped into an HBox it reports a minimum width of its whole unwrapped text and shoves everything beside it off the panel. Autowrap only constrains height once something else has fixed the width. |
| ⛔ **`SimWorld.setup()` DOES NOT BUILD THE MAP — `MapGen.build(w, cfg)` DOES** | A fixture that forgets it gets an **empty world**, so every count is 0 and every `== 0` objective passes. Mine reported *"the lose row fires on tick 1"* — the exact catastrophe it was written to detect — and sent me looking for a bug in correct code. ➡️ **A fixture that MANUFACTURES a bug is worse than one that agrees with it.** `PreviewScenarioWin.tscn` drives the real launch path and is what settles this class of question; when a unit test and that preview disagree, the preview is right. |
| ⛔ **`== 0` IS A COMPARISON AN UNIMPLEMENTED OR UNMEASURABLE SUBJECT PASSES** | So a subject that silently counts nothing announces **victory on tick 1 of an unwinnable scenario**, and a `lose` row does the mirror. `ObjectiveDef._count` returns **−1, never 0**, for exactly this reason. The same trap has a content form: `unit.dragon_baby == 0` is true *before the hatchling exists*, so "kill the hatchling" is not expressible — a count that reads 0 because a thing has not happened yet is indistinguishable from 0 because it is over. |
| ⚠️ **A LOCAL APPENDED TO A LIST THAT IS REASSIGNED FURTHER DOWN THE FUNCTION IS SILENTLY DISCARDED** | `MapDocument.save()` does `warnings = StartLayout.audit(data)` partway through, so anything appended to `warnings` before that line is thrown away. **The only symptom is an absence** — no test fails, nothing logs. Found by reading the order of a function, which is the only thing that finds it. |
| **The 0 A.D. checkout's media files are git-LFS POINTERS, not content** | Every `.ogg`/`.dae`/`.png`/`.pmd` on disk is a ~130-byte pointer. Worse, that repo's **index is emptied** (30,114 staged deletions) and its `.gitattributes`/`.lfsconfig` are gone from the working tree, so `git lfs pull` exits 0 having done nothing. Do **not** repair it — it is the art agent's tree and memory records that git operations there have destroyed art. The route that works is documented in `tools/stage_audio.py`: read the oid out of the pointer, fetch through the LFS batch API, write the bytes into `game/` and never into the checkout. |
| **A FONT CANNOT BE IMPORTED WHILE `gui/theme/custom` REFERENCES IT** | Swapping the body face deadlocks `--import`: the project theme loads at startup, names the new `.ttf`, the `.ttf` has no `.import` yet, the load fails and the import never reaches it. The error reads "No loader found for resource". Comment `theme/custom` out of `project.godot`, `--import`, put it back, `--import` again. Same shape as the "a new `class_name` is invisible until `--import`" row, with a cycle in it. |
| **A NinePatchRect's BORDER IS DRAWN AT 1:1** | The `patch_margin` is in SOURCE pixels and does not scale with the rect, so a 1024 px plate with a measured 46 px border puts a 46 px border on a 152 px panel and clips the content behind its own frame. **Shrinking the margin makes it worse** — the margin says where the border ENDS, so the leftover bevel joins the stretched centre and smears across the panel. The only lever is the SOURCE SIZE; `tools/prepare_ui_chrome.py` is what turns "the border should draw at 12 px" into an output size. It is what turns a designer's "12 px border" into an output size at bake time. |
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
| **WIDENING A FIELD FROM ONE VALUE TO A LIST LEAVES `== &""` COMPILING AND ALWAYS FALSE** | `BuildingDef.upgrades_to` became an `Array[StringName]` in 5.3, and every `if bd.upgrades_to == &""` in the codebase kept compiling — GDScript compares an Array to a StringName quite happily and says no. So a guard that used to mean *"this building has no upgrade, skip it"* silently became *"never skip"*, which is a filter that stops filtering with no error anywhere near it. `preview_walls` had one and would have taken whichever building stood at the origin first. **The compiler cannot help with this class of change**: grep every reader of the field by NAME and read each one, rather than trusting the build. Related: `slot.action.id == &"upgrade"` in the same file became unreachable when the id gained a `:target` suffix, which at least announced itself as a warning. |
| **THE SHIPPED BODY FACE HAS NO CHECK MARK, AND A MISSING GLYPH IS SILENT** | New Rocker (`UiFont.BODY_PATH`) answers `Font.has_char` **false** for U+2713, U+2714 and U+2717 — and for every geometric substitute worth trying: ● ○ ■ ▪ ★ √. What it does have is `•`, `»`, `†`, `§`, `·` and ASCII. Measured with a throwaway probe, which is the only reason it is known: a glyph the face lacks does not fail, it draws a **tofu box**, and in a screenshot that reads as a broken icon rather than as a missing font. 15.6's first render put a literal `*` beside a completed objective (the fallback firing, correctly). **Draw a mark rather than typing one** — `ObjectiveTracker.TickMark` is twelve lines of `draw_polyline`, cannot be broken by a font swap, and is the mark the player expects. Same family as the `assets/UI_Gen/font_comparison.png` lesson: a face is chosen on the characters this game actually prints. |
| **A WIDGET THAT RESIZES ITSELF, UNDER AN OFFSET ITS CALLER WROTE ONCE** | `NoticeToast` is anchored CENTER_TOP at `-SIZE.x / 2` and `show_long_message` swaps a 320 px banner for a 720 px one — so the long banner kept the short one's left edge and hung **200 px right of centre**, with nothing in `GameScene` to blame. It survived from 2026-08-30 to 15.6 because `show_long_message` **had never had a caller**, and a mode nobody calls has never been positioned by anybody. The fix belongs in the widget (it holds its own centre across a resize, by the HALF-DELTA so it keeps wherever the caller put it) and not in the caller. **When a widget can change its own size, ask who owns its position** — and treat "nothing calls this yet" in a header as a warning that the first caller will find something. |
| **`set_process(false)` IN `_init` DOES NOT STICK, AND NO HEADLESS TEST CAN SEE THAT IT DID NOT** | Declaring `_process` at all is what makes Godot process a node, and it is **re-applied when the node enters a tree** — so a per-frame gate set in `_init` is off in a test and on in the game. `AgeBadge` gated its spark animation that way for 13.2c and every badge in the game redrew 60 times a second for the whole match, including the ~99% of it with no countdown running. **`test_the_claim_ring_is_animated_and_a_quiet_badge_is_not` passed throughout and could not have failed**: a bare `.new()` never enters a tree, so `_init` is the last word there. Re-assert the gate in `_ready`, and expect the PREVIEW to be what catches it — `preview_age_badge` prints `(animating)` per row and said it on the first run. The general form is §5's: **a gate whose two states are "in a tree" and "not in a tree" is untestable by a harness that has no tree**, so the test has to say which failure it is blind to. |
| **A `TextureRect` DEMANDS ITS TEXTURE'S FULL SIZE AS A MINIMUM, AND `STRETCH_KEEP_ASPECT_CENTERED` DOES NOT CHANGE THAT** | `expand_mode` defaults to `EXPAND_KEEP_SIZE`; the stretch mode says how to draw *inside* the rect and the expand mode says how big the rect may *be*. So a 96 px tile holding a baked battle sprite asked for several hundred pixels, the `VBoxContainer` round it overflowed (it does not clip, scroll or compress — see the row above), and 16.3's palette rendered with pictures spilling over each other and **every caption pushed clean out of its tile**: 32 buildings with one visible name between them. `EXPAND_IGNORE_SIZE` plus `custom_minimum_size` is the pair. **Only one of the two properties is the famous one**, which is why this looks like a container bug and is not. |
| **AN `OptionButton` NOBODY HAS SELECTED DISPLAYS ITEM 0, AND `add_item(text, -1)` MEANS "USE THE INDEX AS THE ID"** | Two traps in one control, both found by a screenshot on 16.3. (1) The palette's owner picker lists **Gaia first** (every resource node in the game is gaia's), so a picker left unselected showed *Gaia* while the field behind it said *player 1* — an author would place a building for a player they never chose, and no test could see it. **Assign the control from the field unconditionally, not only when the value changes**, and expose the control's reading so a test can compare the two. (2) The natural id for "no colour" is `-1` — the value `atlas_for()` itself takes — and `add_item("none", -1)` silently stores id **0** instead, so `get_item_index(-1)` finds nothing, `select(-1)` **deselects** and the dropdown draws **blank**. Keep every id non-negative (shift by one). The blank box also hid that `item_selected` had never been connected, so the control was inert as well as empty: two faults reading as one, which is §6's volume-slider row wearing a dropdown. |
| **`"%s" % some_array` TREATS THE ARRAY AS THE ARGUMENT LIST, NOT AS THE ARGUMENT** | So the single most natural way to put a problems list into an assertion message — `assert_true(problems.is_empty(), "%s" % problems)` — is **wrong in both directions and never in a way that mentions arrays**: an empty list raises *"not enough arguments for format string"* and a two-element list raises *"not all arguments converted"*. It cost a red suite on 16.4a with **eighteen engine errors** and one confusing formatting failure, all pointing at string formatting and none at the list. `% [problems]` is the fix (the array becomes one argument), and note the trap in the trap: the form is only wrong for the case that fires, so a message with exactly one element in the list passes and the same line fails the next time. **Any `%` whose right-hand side is a variable holding an `Array` wants brackets round it.** Same family as `some_array as Array[int]` silently failing on a variable — GDScript's `%` and `as` both behave differently for a literal than for a name. |
| **`Ctrl+Z` CANNOT BE CAUGHT AFTER THE GUI PASS, WHICH RULES OUT `_gui_input`, `_shortcut_input` AND `Button.shortcut` TOGETHER** | Godot's order is `_input` → `Control._gui_input` → `_shortcut_input` → `_unhandled_input`/`_unhandled_key_input`, and `LineEdit` consumes `Ctrl+Z` in the GUI pass as its own **text** undo. So a focused search box or name field eats it before `_shortcut_input` runs — and a `BaseButton.shortcut` is dispatched from `_shortcut_input`, so the obvious "just put the shortcut on the Undo button" is the same bug wearing a resource. **The working binding is `_input` on the screen**, which is first in the order and reached whatever has focus. 16.2a's card blamed the canvas; the canvas was incidental — being *after the GUI* was the fault. **And then hand the key back**: `get_viewport().gui_get_focus_owner() is LineEdit or TextEdit` (a `SpinBox`'s child `LineEdit` is what takes focus, so one test covers the number boxes too), or you undo the map while somebody is mid-word in the map's name. |
| **WRITING INTO ANOTHER OBJECT'S PACKED ARRAY THROUGH THE PROPERTY CAN VANISH WITH NO ERROR** | `data.terrain[i] = b` is the classic form: a packed array is a **value type**, so depending on how the access compiles the write can land on a temporary copy. Fine inside the class (`MapData.set_terrain` writes its own member); not something to rely on from outside. **Pull the buffer into a local, write it, assign it back once** — correct whichever way it compiles, and one copy-on-write per operation instead of per element. `MapEdit._write_terrain()` is the pattern, and it was written this way rather than probed because the failure is silent and the probe would only have answered for 4.7.1. |
| ⛔ **A FILE INSIDE A MOUNTED PACK IS NOT AN IMPORTED RESOURCE, SO `load()` CANNOT OPEN IT — AND THE FAILURE IS INVISIBLE ART, NOT A MAGENTA PLACEHOLDER** | Measured on 4.7.1 against a real mounted zip: `load_resource_pack()` returns **true**, `FileAccess` and `DirAccess` see the files, `Image` decodes them — and `ResourceLoader.exists()` is **false** while `load()` pushes an engine error, because a hand-built zip carries no `.import` sidecar. `AtlasEntry.texture()` was `if ResourceLoader.exists(p): load(p)` and would have returned null for every pack-delivered page. ⚠️ **The reason that is worse than it sounds:** `GameDataRegistry._resolve` chooses the placeholder branch on whether the **`.atlas.json` parsed**, and the JSON parses perfectly out of the zip — so the seam would have reported a real atlas and every unit in the game would have drawn *nothing at all*, with no warning anywhere. The route is `FileAccess.get_file_as_bytes` + `Image.load_png_from_buffer`. |
| ⚠️ **`Image.load_from_file()` ON A `res://` PATH WARNS *"this will not work on export"* — ON A DEVELOPER MACHINE ONLY** | The engine warns whenever `ResourceLoader::exists()` is true of the path, i.e. whenever an `.import` sits beside it. With the atlases staged that is **every page: 170 warnings a run**, each naming a hazard that does not apply, burying anything that does. On a device it never fires, because a zip member has no sidecar. **So the two environments disagreed about the log while agreeing about the pixels** — the worst place for a difference to live. `FileAccess` + a buffer decode has no such heuristic and reads a staged file and a packed one identically. |
| ⛔ **A COMMENT ASSERTING A BEHAVIOUR THAT NOTHING IMPLEMENTS, AND THE HALF THAT MAKES IT UNRECOVERABLE** | `PackInstaller._mount()` said a mounted pack *"reads it for the life of the process and on every boot after"*. `ProjectSettings.load_resource_pack()` was called in **exactly one place, at install time**, so a mount lasted one process. On its own that is "art disappears after a restart"; what makes it permanent is that `PackIndex` records the install the moment it succeeds and `needs_download()` is the only question boot asks — so the art is not mounted, is recorded as installed, and **is never fetched again**. Nothing could have caught it: `campaign` and `map` packs are INSTALLED, not mounted, and they were the only two kinds that had ever shipped. **A suite cannot find a hole in a code path nothing takes.** `MountedPacks.mount_all()` from `GameDataRegistry._ready()` is the boot half. Its sibling: a mount alone changes nothing on screen, because `_resolved` pins every id to the placeholder it resolved to before the download — `refresh_seam()`. |
| **`res://../anything` DOES NOT RESOLVE, AND `DirAccess.open` JUST RETURNS NULL** | So a preview reaching out of the Godot project into the repo reports "not found" for a directory that is plainly there. The route that works is `Campaigns._dev_root()`'s: `ProjectSettings.globalize_path("res://").path_join("../x").simplify_path()`. Cost one confused run against a freshly built pack. |
| ⚠️ **A CHANGE TO THE BUILD SCRIPT MOVED PUBLISHED BYTES, AND THE VERSION GUARD CANNOT TELL THAT FROM EDITED CONTENT** | Making `build_packs.py` **store** already-compressed formats instead of deflating them (PNG is deflated already; the art agent measured 99% of original, and deflating 320 MB for 1% costs minutes a build) changed the digest of both **campaign** zips, whose content had not moved at all. The guard refused the rebuild and was right to — it compares digests. **Bumping is the safe direction**; the alternative is freezing the old encoding for one kind of pack forever so two kinds get built two ways. Worth knowing as a class: *the guard protects the player, not your afternoon, and a packer refactor is a version bump for everything it touches.* |
| ⚠️ **AN ESCAPE HATCH THAT IS WRITTEN, DOCUMENTED, AND CALLED BY NOTHING** | `PackInstaller.cancel()` has been described in its own neighbour's comment as *"the player's escape"* since 0.3, and **no code ever called it**. It cost nothing while the whole `required` set was one 2.2 MB campaign — the download screen was over before anybody could want out of it — and became a first boot with no way back to the game the moment `art_base_v1.zip` (80 MB) was marked required. `DownloadScreen`'s own header even said *"there is deliberately no way to get stuck here"*, which was written about downloads that **fail** and silently did not cover one that merely takes an hour. ➡️ **When a size changes by 40×, re-read the sentences that were true at the old size** — the header, the timeout policy, and the absence of a resume are all the same assumption. Same family as the `MAX_PUSH` row: a comment that is true of the case it was written for. |
| **A TREE COUNT IS A CPU BUDGET AND A TREE AMOUNT IS FREE** | Both change how much wood a map holds and only one of them costs anything: `AISystem` searches the whole entity list per player per tick, which is what took the 2026-08-28 density work to 24.83 ms against a 20 ms ceiling. So **amount-per-tree is the lever to reach for first** and trees-per-map second. `MapGenerator.SPRINKLE_SPACING` is a dozen or two trees a board on purpose. |

---

## 7. Where things stand

### WHAT IS BUILT — the short version

**Phases 0–13 and 15 are closed; Phase 16 is at 16.6, with 16.7 next.** Suites **game 2508/0** and
**MapMaker 386/0**, tag `v0.9.8`. **PLAN.md §11 carries every decision and the board carries
status** — neither of them lives here.

*The per-phase build logs that used to sit in this section (the UI overhaul, the four-device
playtest, teams, LAN discovery, Phase 13, Phase 15 — about 1,900 lines) were history that PLAN.md
and `git log` already hold, and the durable half of each is a row in §6. They were removed
2026-09-12 on the owner's instruction to keep only core decisions and needed information.*

**THE OPEN ENDS THEY LEFT, which are recorded nowhere else:**

- **Committed chrome that nothing references.** `badge_round`, `checkbox_*`, `radio_*`,
  `tab_plate`, `bar_fill_health`, `banner_age` and the four `arrow_*`. ⚠️ **`bar_fill_health` is
  unused because the owner picked something else for the health bar** — worth knowing before
  "fixing" it back. ⚠️ **`badge_round` needs a DECISION rather than work**: `res_*` icons are drawn
  at 24 px, where a ring leaves almost no glyph, so either the icon grows or the ring does not
  happen. Raised in `asset_request.md`.
- **`scenes/ui_builder/*.tscn` are REPOINTED, NOT UPDATED.** They reference the current art so
  nothing dangles, but their layout is the pre-overhaul HUD and nothing instantiates them. Whether
  they survive is the owner's call — the same call that retired `UI_Design.md`.
- **`ART_PROMPT.md`'s upcoming set** is drawn and committed for features that do not exist — voice
  chat, the server browser, the lobby, save/load, replay. None of it can be wired and none of it
  should hold anything up.

### Owner-reported and open (BUGS.md is authoritative)

Listed here so this file does not read as though the game were finished. Do not
re-diagnose these from scratch — each already has a diagnosis.

- ~~**Double-tap to clear the selection is unreliable on the phone.**~~ **ANSWERED
  2026-08-28 by the [X] button**. `InputRouter.TAP_SLOP`/`TAP_TIME_MS` is still the
  root and is still a separate job. Awaiting the owner's device confirmation.
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
- **SHIPS are static** — no walk clip, so they slide rather than row. This entry used to name
  the three siege engines and the dragon too and can name neither now: the engines' **packed**
  actors carry `idle` and `walk` since 2026-08-28 (which is what made 4.13 possible, and
  `UnitDef.packing` is the second speed — a *deployed* engine still carries `speed: 0` and still
  should), and **`vis.dragon_rigged` bakes all five clips** as of 2026-09-04. ⚠️ **`unit.dragon`
  is NOT trainable at the castle** — that line was here for months and was one of the two
  contradictory routes 13.2 settled. There is one dragon per map, she is gaia's, and you claim
  one by killing her and holding the nest (13.2b).
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
- **Three gaps PLAN.md records rather than files**, all cheap to trip over: **a dock built
  inland before 2026-08-23 stays inland** (`requires_shore` gates new placement only, so an old
  dock trains ships that cannot deliver); **naval combat does not exist** — ships float and path,
  and transports have loaded and unloaded since 2026-08-29, but nothing has ever fought at sea,
  so a loaded transport crosses unopposed; and **a static destroyed behind the fog stops being
  sent** rather than leaving AoE's stale ghost, which would need a per-player last-seen copy of
  every static (§11.4).

### Where the queue points

**PLAN.md §15 is the authority and has been swept three times** — it grows back into a log of
everything shipped, which is the one section where a completed item actively costs a reader
something. **Do not re-grow it here either.** What follows is a pointer, not a copy:

1. **Phase 16, the MapMaker** — where the work is, and **the board is the status, not this list**
   (§2.1). 16.0 through 16.6 are done. What is left in the phase is **16.7** (per-entity overrides
   and named units — the expensive row, and the only one with real sim cost, since `state_hash()`
   must fold the overrides in), **16.8** (scenario export, where 15.1's schema gets its second
   consumer), **16.9** (the HOW-To, written last on purpose) and **16.10**.
   ⚠️ **`MapEdit.mark_changed()` HAS NOW BEEN OWED TWICE** — by 16.4's move cursor and 16.6's
   condition edit — and will be owed again. Any act that edits an entry **in place** (same list
   length, same starts) is invisible to `close()`'s size test, and a discarded step is a change
   that cannot be taken back. 16.7's whole job is in-place edits, so it owes it on every path.
2. **16.10** — re-author the five How To Play maps, then "The Dragon Born". **Scenarios 3 and 5
   share one map**, so one good duel map covers two rows. It was three until 2026-09-06, when
   scenario 4 got its own map with a nest on it — **and anybody re-authoring that map must keep
   the nest and the mother**, which `test_campaigns` asserts.

Then, in no forced order: Phase 14's AI enemy-blindness; the AI researching anything at all
(`9.x-ai-research`); `cliff-terrain`; `11.x-wonder-victory` and 11.2 Regicide; 12.1b reconnect;
12.4 save/load, which is where §11.3's parked Save Game button lives; naval combat; `0.3a`, a
resumable pack download; and `13.x-claim-dead-end`.

⛔ **TWO THINGS ARE WAITING ON THE OWNER AND MUST NOT BE PICKED UP UNPROMPTED.** `16.6` and
`13.4b-breath-damage` sit in **`Test`** — the first wants the owner authoring a real map's
conditions in the panel, the second wants somebody burned by 500 damage, and neither is a
judgement a test or a screenshot of mine can make. **`wall-facings-reachable` is `Blocked` and
tagged `owner-decision`**; its own description asks the owner to flip the tag to `game-code`, and
it needs an A/B/C ruling before anything can be done. **Never move or edit an `art` or
`owner-decision` card** (§2.1).

✅ **THE ART PACK IS BUILT AND PUBLISHED (2026-09-12), AND IT IS A `.zip`.** The owner's call —
*"if pck is just a zip, rather leave it zip"* — and a `.pck` is **not** a zip, but
`load_resource_pack()` takes either, measured on 4.7.1. So the packer stayed pure Python with no
Godot export step in it. **Two packs, on the split the art side's figures forced:**
`art_base_v1.zip` 80 MB `required`, `art_colours_v1.zip` 236 MB optional — the colour variants
are 74% of the bytes, and the split is only safe because `_atlas_path_for_skin` already falls
back to the untinted bake, which was verified before it was chosen. `exclude_filter` now keeps
`res://assets/atlases/*` out of both export presets, which is the half that actually shrinks the
APK: a measured export-pack went to **66 MB**.

**What it packs is `visuals.json`, not a directory** — the union of every declared `atlas`, every
`ages` value and every tinted sibling of those. That is the art side's own suggestion inverted
into the design it should have been: a retired bake leaves the pack the moment nothing points at
it, with no skip list to maintain (26 staged atlases are in no pack today, and the build says so
every run). ⚠️ **The packer's selection and `GameDataRegistry`'s resolution are two independent
derivations of one set, and `preview_art_pack` exists to compare them** — 1,535 paths, and if
they ever drift the pack ships art nothing renders while missing art everything asks for.

⚠️ **STILL OPEN, AND IT MATTERS MORE NOW THAN IT DID:** there is **no resumable download**.
`HTTPRequest.set_download_file` cannot append, so an interrupted pack restarts at zero — which
was irrelevant at 2.2 MB and is nine hours of 125 kbps for the colours pack. PLAN.md 0.3a.

---

## 8. For the art agent

See **[AGENT_ASSET.md](AGENT_ASSET.md)** for their side: recipes, bake batches,
staging, the isobake pipeline, and what they consider stable versus in flux.
That file is theirs to write and maintain — I do not edit it, the same way they
do not edit this one.

If the two documents ever disagree about the fence between us, the disagreement
itself is the thing to fix — raise it in `asset_request.md` rather than quietly
picking a side.
