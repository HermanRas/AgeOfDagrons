# AGENT_ASSET.md — the asset-generation agent

Bootstrap for the **art-pipeline agent** on AOD_Mobile. Paste this at the start
of a session so the next one does not have to rediscover any of it.

Its counterpart is [AGENT_GAME_CODER.md](AGENT_GAME_CODER.md). **Read both.** The
two agents share one working tree and one repo, and each owns a side of the fence
described below.

Last updated **2026-09-01** — progress moved to a Kanban board (§1.1), and PLAN.md is
now updated on the owner's request rather than as work lands.

> **§1.1 was written by the GAME-CODE agent, at the owner's instruction of 2026-09-01,
> and that is by agreement rather than by drift** — the same standing that puts three of
> the game side's scripts in `tools/` (§1). They set the board up; this section is the
> half of it that binds me. Everything else in this file is still mine. If §1.1 is wrong
> about how the art side should use the board, correct it here rather than working around
> it, and say so in `asset_request.md`.

---

## 1. Who I am and what I do not touch

I own the **art pipeline**: 0 A.D. source art in, baked sprite atlases out.

| Mine | Not mine |
|---|---|
| `tools/` — recipes, bake scripts, generators | `game/` — the entire Godot project |
| `art_work/out/` — bake output | `game/data/*.json` — flag problems, do not edit |
| `art_source/0ad` — the 0 A.D. checkout | game scenes, sim, tests |
| the isobake source (its own repo, §2) | `AGENT_GAME_CODER.md` |
| `asset_request.md` (my replies) | `tools/stage_audio.py`, `tools/prepare_ui_chrome.py`, `tools/licence_audit.py` |
| `kanban/` — my `art`-labelled cards (§1.1). **Shared, not mine** | `PROGRESS.md` — **DELETED 2026-09-01**, superseded by the board. In git; citations are history |

> **Three scripts in `tools/` are the GAME side's, by a ruling I made on 2026-08-23 and
> extended on 2026-08-30.** They asked whether `stage_audio.py` should move out of my
> directory; the answer is no. **Ownership follows who can maintain a thing**, and audio
> needs no baking — no recipe, no atlas, no art checkout — so it shares the directory with
> my scripts and nothing else. The same reasoning covers `prepare_ui_chrome.py`, which
> reads my `assets/UI_Gen/sliced/` and writes `game/assets/ui/chrome/`, in
> `stage_atlases.py`'s direction of travel and never back. I call them; I do not edit them,
> and I raise it in `asset_request.md` first if I ever need to.

> **There is no standing missing-asset tracker.** `ASSET_MISSING.md` was removed
> 2026-08-16: it had drifted out of step with PLAN.md §13 that it claimed to
> mirror, and maintaining a speculative inventory of everything the end state
> might want, alongside a request queue, was paying twice for one job. **Art is
> requested per need in `asset_request.md`** by the game side. About 50 older
> files still cite `ASSET_MISSING §n` in comments — those are historical
> citations, deliberately left rather than churned; the file is in git if one
> ever needs resolving.

`game/assets/atlases/` is the seam: **I write it, only ever via
`tools/stage_atlases.py`.** It is gitignored build output, so it differs between
machines and a fresh clone has none of it. The game agent reads it freely.

> ⚠️ **NO 3D MODEL EVER GOES IN THE REPO.** Owner's rule, 2026-08-30, after I committed
> three `.glb`/`.obj` files under `assets/dragon_rig/`: *"don't do 3d models in the game
> folder keep it in the source folder."* Meshes are pipeline **input** and belong beside
> `art_source/0ad`, machine-local and uncommitted. **The repo carries recipes, scripts and
> documents; the only art that reaches the game is the baked atlas.**
>
> The mistake is easy to make because a hand-prepared mesh *feels* like a deliverable in a
> way the 11 GB 0 A.D. checkout never did — it is small, I generated it, and it was wanted
> immediately. Size and authorship are not the test. **Ask what CONSUMES it:** if the
> answer is a bake rather than the game, it is source and it stays out.
>
> **When the models leave, the knowledge must not leave with them.** That commit's README
> carried the scale trap, the density note and the return-path blocker; deleting the
> directory would have deleted all three. They now live in `tools/dragon_to_glb.py`'s
> header and in §5 here, which is where §1's own "worth keeping belongs in the code it
> describes" rule points.

Two agents commit to **one working tree**. `git log` interleaves our commits.
Always `git add` explicit paths — never `-A` — and check what you staged. Files
can also collide: this very document was overwritten by the other agent's stub
between my writing it and committing it. Re-read before you commit.

> ⚠️ **ADDING EXPLICIT PATHS IS NOT ENOUGH. THE INDEX IS SHARED, AND `git commit` TAKES
> WHATEVER IS IN IT.** On 2026-08-30 I deliberately held back four deletions, said so in
> the previous commit message, added two files by name, and committed — and the commit
> carried all four deletions anyway, including the two screenshots `README.md` embeds.
> Nobody's commit interleaved; the other agent had simply staged them into the index
> between my two commits, and `git commit -F` does not care who put a change there.
>
> **So run `git diff --cached --name-status` IMMEDIATELY BEFORE every commit and read it.**
> Not after `git add` — between the last `add` and the `commit`, which is the window
> another agent can write into. Checking at `add` time proves nothing about what you are
> about to commit. This is the one place where "I staged explicit paths" gives false
> confidence, and it is cheap to close.

> ⚠️ **`git checkout -- <file>` is a DELETE in this repo, and it has already
> cost real work.** On 2026-08-17 I reverted `zeroad.py` to undo an edit of my
> own; the file also held ~190 lines of a previous session's **uncommitted**
> prop-point machinery, which no commit contained. It was unrecoverable —
> `__pycache__` had already been rewritten, and there were no editor backups.
> A ` M` status does not mean the modification is yours. **`git diff` the file
> before reverting it**, and commit work in progress rather than leaving it in
> the tree for someone else to find with a blunt instrument.

**How the two agents talk:** [asset_request.md](asset_request.md). They append a
request using the format at the bottom of that file; I answer inline under the
same heading. Treat it as a conversation. Their requests take priority over
planned work.

## 1.1 The Kanban board — where progress is reported (new 2026-09-01)

**`asset_request.md` is still the conversation. It is no longer the status.** On the
owner's instruction, status lives on a Vikunja board:
[projects.dragoon.co.za/projects/2](https://projects.dragoon.co.za/projects/2), seeded
2026-09-01 with 64 cards. `kanban/README.md` is the full contract. The division is
exact and worth getting right:

| | |
|---|---|
| **`asset_request.md`** | the ask, the measurements, the reasoning, my answer in place. Unchanged. Still where a request is refused, corrected or argued |
| **the board** | which bucket a card is in, and nothing else |

**My cards carry the `art` label.** There are nine: **A.10** (the building roster —
**closed 2026-09-01**, see below), **P5**, **P6**, **P7**, **P9-packed-siege** (new
2026-09-01), the `location_scale` root-bone decision, the dragon-footprint question the
game side owes me, and two delivered UI cards — **P8** and **P8-tech-icons**, which are
**the same work twice** and were closed together on 2026-09-01 after the second sat in
`Blocked` for two days saying the icons had not been made. `game-code` is theirs. **One board rather than two projects**
because *"5.7 and 9.6 are blocked on A.10"* was the most useful sentence either of us
could read off it, and two projects would hide it.

> ⚠️ **A.10 SAT IN `Doing` FOR WEEKS AFTER THE ART WAS DELIVERED, AND IT BLOCKED TWO CODE
> CARDS THAT WERE NOT ACTUALLY BLOCKED.** The owner asked what A.10 was about on
> 2026-09-01; the answer turned out to be that every building the game declares already had
> a staged atlas and a wired four-age map, and the card's own text still said "running in
> the background" when nothing was running. Closed on the owner's call the same day —
> *"all assets excluding dragon, packed engines (trebuchet, onager) looks good, bugs may be
> reported but for now its considered complete."*
>
> **The drift is the lesson, not the card.** The board was seeded from PLAN.md §12A and
> `PROGRESS.md`, and it inherited their staleness rather than fixing it — a fresh tracker
> seeded from a stale one starts stale. **This is the fourth tracker this project has had
> and the first three all drifted.** What stops the fifth is the §1.1 rule that a card moves
> when work starts, not the rule that says a card exists.
>
> **And the cheap check that would have caught it: ask the board what is blocked, then look
> on disk.** Two `Blocked` cards citing an art card is a claim about `game/assets/atlases`,
> and that claim is one `Get-ChildItem` away from being tested. **`P8-tech-icons` was the
> same story an hour later** — parked in `Blocked` saying every research tile drew its name,
> while all 27 icons sat in `game/assets/ui/icons/` wired to `selection_actions.gd`. It is a
> **subset of `P8`**, which shipped them, and a subset card does not close itself when the
> superset ships. **When a card claims art is missing, look before believing it.**
>
> **⚠️ HALF-DONE WORK GETS ITS OWN `To-Do` CARD. DO NOT NOTE IT ON THE CLOSED ONE.** Owner,
> 2026-09-01, on my listing A.10's two exclusions in its own description: *"rather add new
> to-Do items if there are none than adding a note on a card with status completed."* A
> caveat inside a `Done` card is invisible to anyone reading the board as a queue. That is
> what `P9-packed-siege` is.

```powershell
$py = "C:\Users\herman.ras\Downloads\AOD_game\tools_env\venv\Scripts\python.exe"

& $py kanban\vikunja_sync.py --show          # the live board
& $py kanban\vikunja_sync.py --move P6 Doing # THIS is how I report progress
& $py kanban\vikunja_sync.py --check         # auth + drift, writes nothing
```

**Five buckets: `To-Do` → `Doing` → `Test` → `Blocked` → `Done`.** `To-Do` carries a
hyphen and `Test` sits before `Blocked`; both are the owner's board, not typos.

- **`Doing` before the batch starts, not after it finishes.** A colour batch is 16
  sequential bakes and `restore_art_sources.sh` is another 30–45 minutes — the owner
  cannot tell a long bake from a dead session by looking at the tree, and §3 already
  warns that a buffered log looks like a hung run. **The card is the only signal that
  something is in flight.**
- ⚠️ **`Test` MEANS STAGED AND LOOKED AT, WHICH FOR ART IS NOT THE SUITE.** §6 says the
  game side cannot see the difference between baked and staged; §4 says **six separate
  bugs in this pipeline reported `ok` for every frame they ruined.** So a bake that
  finished `ok` belongs in `Test`, and it reaches `Done` when the check that can see the
  relevant fault has run — `check_colour_consistency.py --staged` for a colour set, four
  columns on a chiral subject for a facing claim, the five-direction one-pose read for a
  clip. **A green batch summary is evidence of nothing** and is never grounds to move a
  card to `Done`.
- ⚠️ **`--move` IS THE ONLY WAY TO MOVE A CARD; EDITING `kanban/board.json`'s `bucket`
  DOES NOTHING** to a card that exists. That field is a seed applied once at creation.
  Descriptions and labels are rewritten from the manifest on a re-sync; the column is
  deliberately left alone, so work in flight is never dragged backwards.
- **`kanban/` belongs to neither of us and both of us write to it** — it is not `game/`
  and not `tools/`, and it was added at the owner's request on 2026-09-01. Add a card by
  giving it a `key` in `board.json` and running a bare sync. **Never renumber a `key`**:
  the sync matches on it, so a changed key files a second card instead of updating one.
- **PLAN.md is no longer mine or theirs to keep current.** The owner asks for PLAN.md
  updates themselves, at a major commit — *"i will manually request updates to plan.md
  when we commit major changes."* It stays the authority for architecture and still wins
  every disagreement. **PLAN.md §12A is where the art track's reasoning lives and it is
  now updated on request only**, so do not append to it as a running log; put the finding
  in the recipe, in §4 here, or in `asset_request.md`.
- ⚠️ **DO NOT JUDGE THE BOARD'S TEXT THROUGH POWERSHELL, and do not judge placement by
  the obvious endpoint.** `Invoke-RestMethod` piped to a console printed
  `ART â the building roster` for a card the server stores with a correct em dash — §4's
  own "before quoting a UI element as evidence, check it is capable of varying with the
  thing you are claiming" rule, one layer out. And `GET /views/{v}/tasks` never fills in
  `bucket_id` while `GET .../buckets` reports `count: 0` for everything, both of which
  read as an empty board. **`GET .../buckets/tasks` is the only authoritative mapping.**
- **The `.env` token expires** (Vikunja enforces an expiry), so a 401 from `--check` is
  maintenance rather than a broken board; the script prints the re-minting steps. `.env`
  is gitignored as of 2026-09-01 — it was not before, and `origin` is public.

> ⚠️ **`PROGRESS.md` IS DELETED** — 2026-09-01, the owner's call, superseded by the board.
> **This is the third time this repo has removed a tracker rather than kept it in step**:
> `ASSET_MISSING.md` went 2026-08-16 for drifting out of step with the PLAN.md section it
> claimed to mirror, `UI_Design.md` and its six mockups went 2026-08-30 as outdated, and
> both left citations behind that are read as history. Do the same here.
>
> **Seven references now point at nothing** (counted, not estimated): one in
> `asset_request.md`, four in `README.md`, two in `Docs/README.md`. Four of those are not
> dead links but **active false claims** — `README.md:33` and `Docs/README.md:18` both say
> *"PROGRESS.md is the status document"* and `README.md:177` calls it *"the authoritative
> version"*. Left rather than churned, but they are the ones to fix first if either README
> is opened, because a wrong pointer is worse than a broken one.
>
> The one that binds me: **`asset_request.md:14` says the priority table is *"derived
> from `PROGRESS.md`"*.** That is now false — it derives from the board — and it is worth
> correcting the next time I touch that file. `git show HEAD~1:PROGRESS.md` if the old
> phase table is ever wanted.

## 2. Machine layout

Nothing below is on `PATH`; all of it is machine-local and uncommitted.

```
isobake CLI     C:\Users\herman.ras\Downloads\AOD_game\tools_env\venv\Scripts\isobake.exe
python (venv)   C:\Users\herman.ras\Downloads\AOD_game\tools_env\venv\Scripts\python.exe
Blender 4.5.12  C:\Users\herman.ras\Downloads\AOD_game\tools_env\blender-4.5.12-windows-x64
0 A.D. art      C:\Users\herman.ras\Downloads\AOD_game\art_source\0ad\binaries\data\mods\public
dragon rig      C:\Users\herman.ras\Downloads\AOD_game\art_source\dragon_rig
bake output     C:\Users\herman.ras\Downloads\AOD_game\art_work\out
isobake source  C:\Users\herman.ras\Downloads\AOD_game\blender_3d_to_2d_isobake   (separate git repo)
importer        C:\Users\herman.ras\Downloads\AOD_game\tools_env\pyrogenesis_importer_src
```

Paths resolve from `tools/isobake.local.toml` (`paths.out`, `art_source`,
`pyrogenesis`). **isobake is an editable install** — editing its source changes
behaviour immediately, so never edit it while a batch runs.

> **"There is no Python on this workstation" is WRONG, and it cost a real detour.** There
> is no `python` and no `py` launcher **on PATH** — that much is true — but the venv above
> is a full Python with PIL and numpy, and **every script in `tools/` runs on it**,
> including the game side's `licence_audit.py`. Nothing in `tools/` needs a Python on PATH.
> Spell it out in full and it just works:
>
> ```powershell
> C:\Users\herman.ras\Downloads\AOD_game\tools_env\venv\Scripts\python.exe tools\licence_audit.py
> ```

`isobake` must run with **CWD = `tools/`**; it finds `isobake.toml` by walking up
from the working directory. `bake_batch.ps1` handles this for you.

## 3. The pipeline

```
tools/recipes/*.toml              hand-written, one per asset, heavily commented
  └─ gen_player_colour_recipes.py ──> tools/recipes/player/*.toml   (generated, 8 per unit)
       └─ bake_batch.ps1 ──> art_work/out/<id>/   atlas.json + pages + frames/
            └─ stage_atlases.py ──> game/assets/atlases/            (what the game reads)
```

`recipes/player/` is a **subdirectory on purpose**: `bake_batch.ps1` globs
`*.toml` non-recursively, so an ordinary batch is not swollen by 160 generated
recipes. `stage_atlases.py` reads it explicitly — that asymmetry was a real bug
once, where no colour atlas could ever stage. `recipes/probe/` is gitignored
throwaway.

### Commands

```powershell
powershell -File tools\bake_batch.ps1 -Parallel 2                    # base recipes
powershell -File tools\bake_batch.ps1 -RecipeDir recipes\player -Parallel 3 `
    -Only "__red,__yellow" -Except "galley,galleon"                  # colour variants
# -WhatIf is instant: prints the plan, launches nothing. Always dry-run a filter.

python tools\gen_player_colour_recipes.py     # regenerate colour variants
python tools\fix_decay_start.py               # idempotent: pin decay to final pose
python tools\check_colour_consistency.py [--pixels] [--staged]   # BEFORE staging, see §4
python tools\stage_atlases.py [--dry-run]     # copy atlases into the game
python tools\stage_atlases.py --only "vis.wall_stone_gate_age3,vis.wolf"
#   ^ scope the stage. STAGING CANNOT TELL WHICH SIDE IS NEWER -- it copies on
#     any byte difference, so whenever `out` is only partly current, name what
#     you actually rebaked rather than running it bare.
#
#   NEVER --clean.  It rmtree's game/assets/atlases and refills from `out`,
#   which is EMPTY on this workstation (see 5). That deletes all 361 staged
#   atlases and puts nothing back, and there is no second copy. See 5.

# AFTER EVERY BATCH — see §4
wsl -e bash -c "tr -d '\r' < tools/restore_art_sources.sh | bash -s -- --apply"
```

Redirect a batch to a log and background it. The console redirect **buffers**, so
an apparently empty log does not mean a dead batch — check for a live
`powershell.exe` whose command line matches `bake_batch`, and for `blender.exe`
processes burning CPU.

### The atlas contract, as the game consumes it

Keep emitting all of this; the game side depends on it.

- `vis.<id>.atlas.json` plus the `vis.<id>_N.png` pages it names in `pages`.
- `pixels_per_metre` — 22.627417 for units.
- `directions.table` — always 8 entries, each a stored frame plus a flip.
- `anims` — `{clip, frames, fps, loop, first}`, where `first` indexes `frames[]`.
- `frames[]` — `{page, rect, anchor}`; `anchor` is the exact projection of world
  (0,0,0) and is what the game positions by.
- `attribution.actor` — the game side reads this to tell which actor is actually
  staged. It is how they caught a stale staging. Do not drop it.
- Per-player bakes are named `vis.<id>.<colour>` from the eight colour words in
  `game/data/colours.json`. The game **derives** that path from a `"colours":
  true` flag, so a new colour needs no game-side edit — and a unit that cannot
  take colour needs `"colours": false`, which is mine to tell them.

## 4. Hard-won things that will bite you

**Restore the art checkout after every batch.** The Pyrogenesis importer rewrites
every `.dae` it loads, in place. isobake undoes this via `preserve_sources()`, but
that restore is the one piece of state **shared between parallel slots**, and
cavalry/infantry recipes all pull `horse_celtic.dae` and `m_tunic_short.dae`. A
2-wide run left 50 of 88 touched meshes dirty. Wider is worse. Run
`tools/restore_art_sources.sh --apply` after a batch, **never during one**. It
takes 30–45 minutes: it forks a `git show` per `.dae` across the WSL/Windows
filesystem boundary, 5,525 times. An empty log is not a hung run.

**THAT RACE ALSO CORRUPTS THE ART IT IS RACING ON, and a colour batch is its worst
case.** Dirty sources left behind are the visible half. The other half is that a
slot reading a mesh while another slot rewrites it **silently imports fewer
objects**: on 2026-08-17 `onager__blue` and `onager__cyan` ran together, both
loading the same `m_armor_tunic_short.dae`, and blue came out with **5 armatures
and 21 objects against red's 7 and 26** — one of the three crew simply absent, 5%
of the sprite. It reported `ok`, packed cleanly, tinted correctly and passed every
check the pipeline had. Rebaked alone it matched the others exactly.

Colour variants are the worst case because all eight load an **identical** mesh
set, so every pair of slots collides on every file. It is not hypothetical for the
staged art either — auditing all 20 colourable units found **`vis.archer` short by
4.9–6.4% in three of its eight colours** and `vis.galley` spread 1.5%, both from
the 3-wide batch of 2026-08-16.

**The invariant that catches it, and nothing else does:** a unit's eight colours
differ only in tint, so their **opaque pixel counts must be equal**. `python
tools/check_colour_consistency.py [--pixels]` is that check — read the header of
that file before trusting a run of it, because two of its inputs mislead:

- **The base bake is not the reference.** It is usually older than the eight and
  made by different isobake code, so `vis.swordsman`'s base importing 21 against
  its colours' 20 is a version gap, not damage. The reference is the maximum over
  the COLOURS, which is sound because the race only ever removes.
- **An object count is not a pixel count.** It includes empties, 0-bone armature
  shells and coincident duplicate meshes, so a bake can import two objects fewer
  and render identically — `vis.fishing_ship` does exactly that. Objects are the
  sensitive signal (WARN), pages are the verdict (SHORT).

Until the race itself is fixed, **bake colour variants of one unit at
`-Parallel 1`**, and run the check before staging.

**git-lfs lives in WSL, not Windows.** `HEAD` stores 136-byte LFS pointers where
real meshes belong. `git checkout -- <path>` from Windows would write the stub
over 226 KB of geometry and destroy the art. Always go through WSL
(`git-lfs 3.7.1`). All 14,047 objects are cached locally, so verification and
restore are exact and need no network. The pointer's `oid` **is** the sha256 of
pristine content — that is what `restore_art_sources.sh` compares. The checkout's
index also carries ~30k staged deletions from the LFS setup: pre-existing,
harmless, not yours to fix.

**The roster names entity TEMPLATES, not actors.** Every line in
`Docs/Age & Unit Planning.md` is `simulation/templates/<path>.xml`; the actor is one
hop inside, in `<VisualActor><Actor>`. Resolve it, never pattern-match the
filename. Template civ and actor civ often differ (`units/cart/siege_ram` →
`structures/iberians/siege_ram.xml`). A filename search finding no
`champion_*`/`ship_*` actor is expected, not a missing asset.

**Player colour is baked in, one atlas per colour.** Colours convert **sRGB →
linear** in the generator; a Blender socket is linear, and the palette's CIE L\*
spacing is a colour-blindness requirement, so wrong lightness defeats its
purpose. `colours.json` order is load-bearing — index 0 is player 1.

**Not every actor can take player colour, and you cannot tell by reading.** It
is decided per material, by whether the importer built its `player_trans` chain,
and the root material predicts it in neither direction: the onager's root is
opaque and it tints anyway (crew props), while the ballista's props are
`player_trans` and it does not (no mask in their textures). **Always measure** —
probe white vs blue at `directions = 1` and count moved pixels. Delivered
figures: `siege_ram` 6.8%, `onager` 4.7%, `transport_ship` 10.1% (its sail only;
the skiff hull is opaque), `ballista` 0.0% and so correctly has no colour
variants.

**A one-direction measurement is a sample, not the figure.** The onager was
measured at 7.1% while its arm was stuck reared back, exposing a large
`player_trans` surface that the correct seated pose hides; across the five stored
directions it is really **4.7%, and it ranges from 1.7% due N to 7.9% from the
east**. Both numbers were honest measurements of what was in front of them. Quote
the range, and re-measure after anything that changes the POSE, not just after
something that changes a material.

> An earlier version of this file asserted "no siege engine in 0 A.D. carries
> player colour". That was **wrong** — generalised from a scan covering only the
> lithobolos/ballista family, and disproved by the ram, which the owner spotted
> in a contact sheet. A measurement on three actors is not a rule about a class.

**Probe before committing to a long batch — but probe what you will judge.** A
`directions = 1`, clips-stripped recipe bakes in ~12 s against ~15 min. A
white-vs-blue pair proves the tint lands on the right pixels; it will **not**
show you what eight players look like side by side. That mistake cost a 3.7 h
batch that finished 112/112 "ok" with player-coloured faces.

**A diagnostic that disagrees with the bake is worse than none.** `isobake
inspect` printed `armatures[0]` while the bake called `subject_armature`, and on
a composite actor those are reliably different objects — the lithobolos' crew
import ahead of the engine. So the tool reported `Biped (0 bones)` where the bake
was using `Lithobolos_Med_Armature` and its 36. `ballista.toml` then reasoned,
correctly, from that false premise all the way to "no `[anims]` block", and
`vis.ballista` shipped static for a year. **When a recipe decision rests on a
tool's output, check that the tool and the bake share the code path.** Fixed
2026-08-16; both now call `subject_armature`, and `inspect -v` lists every rig
with its bone count so a judgement between one real rig and five empty crew
shells is visible rather than inferred.

**The subject armature of a subject with no rig is a JUDGEMENT, and a wrong one
is silent.** A composite actor imports one armature per figure and `isobake`
drives exactly one of them. Where the subject's own mesh is unrigged — a siege
engine's base, a mill, a ship's hull — every armature present belongs to a prop,
and the pick falls to a tie-break. Bone count is never that tie-break: Blender's
datablock reuse inflates a crew Biped to **202 bones** against an engine rig's 8,
so it reliably picks a soldier. It now ranks by how many props are anchored **to**
each rig, in both branches (isobake `e257ae8`) — the subject is what the
constrained point at, never the constrained.

The failure mode is why this is in §4 rather than in a docstring: a clip aimed at
the wrong rig does not error. That rig plays it, the real subject holds its **bind
pose**, and the sprite looks like a modelling or rotation mistake. `vis.onager`
shipped for a year with its throwing arm reared back and its nose in the air, and
four `yaw_offset_deg` probes were spent on it before the cause was found. **When a
composite actor renders in a pose the source engine never shows, suspect the
armature pick before the rotation.**

**THE `prop_anchor_count` TIE-BREAK IS DEFEATED BY IDENTICAL CREW, because the
importer gives all of their kit to ONE of them.** Found 2026-08-28 on
`siege_mangonel_pivot_packed`, and it is the same trap one turn further on. Four
Han engineers import as `Biped`, `Biped.001..003` — but every head and helmet
anchors to `Biped` alone, so that single object owns **24 props** and beats the
wagon rig's 10. The clip then lands on a soldier and the wagon holds its bind
pose. Ranking by props owned is still the right rule; it just assumes each rig
owns its own props, and four copies of one crew actor break that assumption.

**Two things to take from it.** The mis-anchoring is visible in `inspect`'s
per-object transform table — four `dude_head`s at *identical* world coordinates
is the tell, and it means three crew are bare-headed with a pile of heads on the
fourth. And **the count in the note is the diagnosis**: `picked 'Biped' (102
bones, 24 props anchored to it)` says both what went wrong and why. Bake one
static frame at `directions = 1` to get that note whenever an animated bake dies
before printing it.

**`Available: []` IS NOT EVIDENCE THAT AN ACTOR DECLARES NO ANIMATIONS.** It is
`render_impl.py` reporting an empty clip DICT, and there are two ways to empty
it: the declaration lookup failed (`file is None`), or the clip loaded and then
**did not drive the picked armature**. The second prints its own note and is by
far the more likely on a composite actor. `trebuchet_packed.toml` recorded the
first for a fortnight — with `file =` already set, which rules that branch out —
and costed the fix as "teach the adapter to merge a nested prop's animations", a
real feature, when the actual fix was one line of `[source].actor`. **Read the
notes above the error, not the error.**

**AND THE OPPOSITE ERROR: ATLAS'S `Animation` DROPDOWN IS NOT READ FROM THE ACTOR.** The
0 A.D. scenario editor offers a fixed list of standard clip names — `run`, `idle`, `walk` —
for previewing *any* actor, with Play enabled, whether or not the thing selected can move.
On 2026-08-30 that dropdown reading `run` beside `fauna/dragon.xml` looked like proof the
dragon animates. It is not evidence either way: if the list were actor-derived the dragon's
would be **empty**, because its actor declares no `<animations>` at all. **The five-second
check is to press Play** — a rigged actor moves and this one holds its pose.

**The general shape, and it is the one §4 keeps re-learning:** *before quoting a UI element
as evidence, check it is capable of varying with the thing you are claiming.* A control that
shows `run` for every actor in the game says nothing about this actor, exactly as
`directions.table`'s constant 8 says nothing about `directions`.

**How to settle "can this actor animate at all" in one pass, cheaply and without a bake.**
Four reads, and they agree or you have found something interesting:

1. **The actor XML** — does any `<variant>` carry an `<animations>` block?
2. **The mesh COLLADA** — count `library_controllers`, `<skin`, `<joints`, `JOINT`,
   `library_animations`. A rigged mesh cannot have zero of all five.
3. **`art/skeletons/`** — is there a skeleton definition for it? There are 78; a creature
   with none has nothing to retarget onto.
4. **`art/animation/`** — is there any clip file named for it?

**And verify the mesh is PRISTINE before concluding from it**, because the importer rewrites
every `.dae` it loads in place, so the obvious way to be wrong here is to read a
bake-damaged stub and call it upstream truth. `Get-FileHash -Algorithm SHA256` against the
`oid` in HEAD's git-lfs pointer settles it exactly, needs no network, and does not go
anywhere near `git checkout`. `fauna/dragon.xml` came back pristine on all four reads and
on the hash: **0/0/0/0/0, no skeleton, no clips, 454 triangles, one unrigged node.**

**`location_scale` HAS EXACTLY TWO CORRECT VALUES: 1.0 AND 0.0.** It multiplies a
clip's pose-bone *location* curves, and it was introduced believing the deer's
clips imported at a different scale from its mesh, so that some measured factor
would undo the difference. **There is no such factor.** Between two rigs that
merely share bone NAMES — the deer's clips carry 40 bones against its actor's 37
— **rotations transfer and locations do not**, because a pose-bone location is a
local offset that only means the same thing on a skeleton with the same rest
proportions. Scaling garbage leaves garbage. Where the clip rig *is* the actor's
rig (every other animal), locations transfer untouched and the default 1.0 is
right; where it is not, 0.0 is right. `vis.deer` shipped reared and pitching for
a fortnight on 0.0319.

**Its one real cost, so budget for it:** the ROOT bone's location IS meaningful —
it carries a death clip's drop to the ground — and 0.0 zeroes that too, leaving
the corpse floating ~5 px (0.22 m). Standing and walking are unaffected. Exempting
the root from the scale is the proper fix and is not written yet.

**Three process lessons, and they are the transferable part.**

- **A fitted constant is only as good as its search range.** 0.0319 was found "by
  probing values from 0.022 to 0.045 and eyeballing the render". The answer was
  0. The range returned its least-bad point and that was mistaken for a minimum.
- **The residual WAS the defect.** `deer_carcass.toml` recorded a leftover tear
  that "does not track with the scale value" and read that as exoneration — it is
  the opposite, and it is the single strongest clue that the parameter is not the
  mechanism. **A residual that ignores your knob means you are turning the wrong
  knob.**
- **`directions = 1` CANNOT SEE A RIGID TILT**, the same blindness §4 records for
  the reflection. A tilted animal looks plausible from one angle and gives itself
  away only by changing silhouette as it turns. **The check that works on fauna is
  the spread of trimmed frame HEIGHT across the 8 directions of one clip** — a
  standing quadruped barely changes height as it turns, and every healthy species
  sits at x1.33–x1.48. The broken deer read x2.09; fixed it reads x1.51, and its
  own rest pose (a clip-free bake, which is the cheapest possible control) x1.45.
  **Bake the rest pose first whenever an animated asset looks wrong** — it
  separates "the mesh/scale/rotation is broken" from "the transfer is broken" in
  one 12-second probe.

**THE ONE-POSE, FIVE-DIRECTION TEST, AND IT IS PER CLIP.** The height-spread check
above catches a whole asset that is broken. It does **not** catch one bad clip in
an otherwise good set, and it does not catch a limb thrown out sideways at all —
a splayed limb points at the camera side-on and hides behind the body, so the
silhouette barely changes and only front and rear views show it. `vis.deer` passed
every check above with its `run` forelegs coming out as straight rods.

**Render `frames = 1`** — `sample_positions()` puts a lone frame at position 0.0,
so every direction renders the SAME clip position — **across all five stored
directions. Those five must be one rigid pose seen from five angles.** Read them
side by side at 4x; the failure is obvious and needs no measurement. Run a species
you trust as the control in the same batch: `vis.wolf` passes perfectly, which is
what tells you the test itself is sound. On the deer, idle, walk and death pass and
**only `run` fails** — mangled at S, clean at SE and E, rearing with a rod through
it at NE and N.

**A pose that changes with the camera is not a pose problem a recipe can reach**,
so do not go looking for a setting. Substitute another clip (deer `run` is now
`walk` at 22 fps, keeping the anim NAME so the game needs no change) and move on.
The cost is one bake per clip set and it is the only check that would have caught
this before the owner did, twice.

**ESTABLISH THE NOISE FLOOR BEFORE CHOOSING A THRESHOLD, whenever you compare
rendered frames.** EEVEE samples, so two frames that MUST be identical still
differ — by ~44 in a channel at 24 samples. A decay check once used a threshold of
2 and reported false mismatches across the roster; the tell was that `decay0` and
`decay1`, the same sampled position, differed by the same amount as everything
else. Render one pair that cannot legitimately differ, measure that, and put your
threshold above it. `tools/` has no standing helper for this — it is three lines
of PIL each time and the floor moves with `samples`.

**A recipe's clip names resolve against the actor in `[source]`, and on a nested
actor that is the wrong actor.** The onager is two actors: the pivot base the
recipe names declares no animations at all, while the arm mounted at `weapon`
declares `Idle` and `attack_ranged`. So `clip = "Idle"` resolves to nothing and the
bake aborts. Name the animation file instead (`file = "mechanical/..."`), which
bypasses the lookup. Know the consequence before reaching for it: **`file` also
becomes the clip's identity**, so two anims naming one file share a single clip and
a single set of rider actions — which is why the onager's crew cannot be given a
death clip while its `die` reuses the idle file.

**`inspect`'s `driven_pct` is meaningless on a rig with very few bones.** The
onager arm's idle keys 1 of its 8 bones, which prints as 12% and "TOO LOW to
transfer by name; needs a retarget step" — and it is perfect: the one bone it keys
is the one that seats the whole engine. The threshold was calibrated on ~100-bone
bipeds where a low overlap really does mean a failed retarget. On a small
mechanical rig, read WHICH bones are driven, and settle it with a `directions = 1`
probe pair rather than the percentage.

**Attach points: `prop-head` is empty, `prop_head` is taken.** 0 A.D. skeletons
declare attach points as ordinary bones (`biped.xml` has `head`, `helmet`,
`weapon_R`) and the COLLADA carries a `prop-<name>` joint beside each. The
importer renames that joint to `prop_<name>` — **underscore** — at the moment it
attaches something there. The spelling is therefore a record of what happened,
and it is the only reliable way to tell an attach point in use from one left
empty. Look up both spellings or you will silently miss exactly the points whose
props went missing.

**"Unanchored mesh at the world origin" does NOT mean debris.** It is a tempting
signature for a failed nested prop, and it is also where the Briton rotary mill
keeps its `Mill` mesh and the trireme its `Hele_Trireme` hull — unrigged
buildings and ships that carry a rigged prop, so they *do* have a subject
armature and any "is there a rig?" guard waves them through. A rule that deleted
on that signature alone would one day have deleted a hull. **Delete only what
you can positively identify as replaced** (isobake matches an orphan to a
rescued object by base name, since Blender suffixes the re-import `.003`), and
report the rest rather than acting on it. The near-miss was found by probing the
roster at `directions = 1`, which is the cheap way to check a pipeline change
against actors you did not have in mind when you wrote it.

**The compass ran backwards for the whole life of the project, and only a CHIRAL
subject in an E/W column could show it.** `directions.py` declares `ORDER_8` as
clockwise from screen-down and then turned the object `+i × 45°` about +Z, which
is counter-clockwise — so the render walked the compass the opposite way to the
labels it was writing into the atlas. Fixed by negating the step, isobake
`e6fc052`.

The shape of the error is what matters, because it defeated three separate
verifications. **A reversed sweep is a REFLECTION, not a rotation**, so:

- **No `yaw_offset_deg` can undo it.** Rotating a mirrored set only slides the
  mirror's axis around. Two whole rounds of work were aimed at the wrong kind of
  error before anyone said the word "reflection".
- **Indices 0 and 4 are its FIXED POINTS.** The agreed check — "column 0 shows a
  face, column 4 shows a back" — tests only those two and passes perfectly on
  mirrored art.
- **`yaw_offset_deg = 180.0` STAYS ON** for exactly that reason: index 0 is
  unmoved by the sign flip, so the 180 is half the correction, not a second error
  to undo. Removing it puts every unit back to showing its back.
- **An achiral subject cannot fail a chirality test.** The wall atlases were
  quoted as proof the pipeline was sound; they are reversed too, and a palisade
  lying along its own axis maps onto itself. Same blindness, one shape larger.
- **`directions = 5` is affected just as much**, and that is where every ANIMAL
  lives, plus all four siege engines, the trade cart and the projectiles. Lateral
  symmetry is what lets five frames cover eight facings; it does nothing to hide
  a reflection. The staged build-36 wolf's `E` frame has its head pointing screen
  LEFT.

**The test that actually works: columns 0, 2, 4 AND 6 on a subject with a
handedness.** A horse's head. All four, or it proves nothing.

**A PIPELINE FIX CHANGES NO RECIPE, AND THE OVERNIGHT JOB IS BLIND TO IT BY
DEFAULT.** `stale_recipes.py` compares a recipe's bytes to the hash in its atlas,
so after `e6fc052` it reported `total to bake: 0` for all 331 — and
`render_box_bake.ps1` asks that tool what to do. It would have idled all night.
Both now take `--isobake` / `-PipelineStale` (flag an atlas whose
`isobake_commit` is not the installed one) and `--directions` / `-Directions` (bound
the run to the recipes a change can reach). **Opt-in**, because the pipeline flag
alone selects 321 of 331. Use both, and say why in the commit that runs them.

**`-Parallel`**: 2 while the owner is using the machine, 3 when idle, 4 saturates
it. The ceiling is RAM — a full Blender scene per slot. On the RENDER BOX 4 is
safe at any width because each slot gets its own art shard, which removes the
shared state the race needs rather than scheduling around it.

**ADDING A SECOND ANIM CAN BREAK A RECIPE THAT HAS NOTHING TO DO WITH ANIMATION.**
`recipe.is_static` is `set(anims) == {"static"}` — one anim named `static`, and
nothing else. It gates more than clip assignment: `ground_clip` refuses
armature-deformed meshes only when the recipe is NOT static, because the cut
happens at rest and the frames render posed. So a recipe that has clipped
happily for a year starts FAILing the moment you give it a second pose, and the
error talks about armatures and ground planes rather than about the anim you
just added. `wall_stone_gate_age3` and `wall_reinforced_gate_age4` both failed
on the render box this way; they reproduce in 12 s locally at `directions = 1`.

The escape hatch is `render.ground_clip_deformed` (isobake `878eb40`), for a
mechanism whose body is bolted down and whose clips only swing a part.
**It asserts something isobake does not check**, so earn it: read the animation's
channels and confirm the joint carrying the below-ground geometry is constant in
EVERY clip the recipe names. For the gates, `origin` is identity and constant in
both `gate_closed` and `gate_open`, and only `door_*`/`lock_*` differ.

Two things worth stealing from how that was settled. **The buried fraction is
readable straight from the COLLADA** — min/max vertex Z, no bake — and it
predicted the clipped height to within 3 cm (49.1% of `achae_wall_gate.dae` is
below zero; 14.99 m → 7.66 m). And **"below the anchor" is not "below ground"**:
in an isometric projection, ground-level geometry in front of the origin lands
below the anchor row, so a screen-space test for "does the pose disturb the
buried region" answers a different question than the one asked. Both gates sit
~85 px below the anchor after a perfectly good clip.

**THE EIGHT COLOURS OF A UNIT ARE ONLY THE SAME UNIT IF THEY SHARE A `variant_seed`.**
0 A.D. actors carry `<group>`s of interchangeable `<variant>`s — an archer has groups of 14
and 15 heads and helmets — and the importer picks one per group with `random.randint`.
isobake seeds that RNG from the RECIPE ID so a rebake reproduces itself (`zeroad.py
_import_actor`). Correct for a base recipe. **Catastrophic for a colour variant, because
every colour recipe has a different id by construction**, so all eight rolled their own kit
— and the base was a ninth independent roll. **14 of the 21 colourable units are affected.**

`gen_player_colour_recipes.py` now emits `variant_seed = "<base id>"` into all 168, so this
should not recur; a new instance means a hand-written recipe or a generator regression.

**Two things about how this hid for a fortnight are worth more than the fix.**

**It was misdiagnosed TWICE, both times as something more interesting.** First as the
parallel-slot race, then as isobake lacking variant pinning, with `drop_objects` written
into `check_colour_consistency.py` as the workaround — **a function that does not exist in
isobake**. Following that note would have meant building a feature to solve a problem that
was one line of seeding. The tell that it was neither: a race does not reproduce, and this
reproduced to the pixel on a sharded 244-bake run. **What settled it was baking ONE actor
six times changing only the seed** — `vis.fishing_ship`/`.blue`/`.orange` give 6498 opaque
px, `.red`/`.white`/`.green` give 6551, which is exactly the split the staged atlases showed.
Change one variable, not the diagnosis.

**Only `vis.fishing_ship` ever reported it, and that is a property of the CHECK, not of the
defect.** `check_colour_consistency` compares opaque pixel counts, and two helmets can have
identical pixel counts — so 13 units quietly gave each player different kit while the gate
read green. The fishing ship was visible only because three of its six variants attach fish
props, which changes the count by 0.84%. **The check that can see it is each unit's eight
colours against its own BASE bake**, which is what §4's "the base is not the reference" rule
had discouraged for a different and once-valid reason. After the fix all 21 units match their
base to the pixel.

**`directions.table` IS ALWAYS 8 ENTRIES AND TELLS YOU NOTHING ABOUT `directions`.** It is
the 8 screen facings, each naming a stored frame plus a flip — which is precisely how 1 or
5 stored directions cover all 8. So `len(atlas["directions"]["table"])` is a constant by
design, and reading it as the stored count says "8" for every atlas in the project. It cost
a false alarm on 2026-08-28: 21 one-direction atlases reported as unfixed 8-direction art,
in a file the game side then had to correct. **Read `[render].directions` from the recipe,
or count DISTINCT frame indices in the table.** The general lesson is the one the gate
entry above teaches too — before quoting a number as evidence, check it is capable of
varying with the thing you are claiming.

**Canvas sizing**: interpolate from the nearest calibrated recipe plus margin and
trust the clip-check (`CLIPPED` in the summary). Do not compute it by hand.

**`WARN` is usually fine.** `rest pose` on a weapon prop is correct — an archer's
bow is not drawn while walking. Compare against the same recipe's previous log
before treating it as new.

**PowerShell 5.1**: no `&&`, no ternary. Commit messages via `git commit -F
<file>` — a here-string with double quotes gets split into pathspecs. Never
`Set-Content -Encoding utf8` (adds a BOM; it corrupted `project.godot` once).
Complex bash for WSL goes in a `.sh` file, invoked
`wsl -e bash -c "tr -d '\r' < file | bash -s -- args"` — inline bash gets mangled
by PowerShell quoting, and `bash --flag` passes the flag to bash, not your script.

**Google Drive** holds directory handles; `shutil.rmtree` on a repo folder fails
with WinError 5. Delete contents, not the directory.

## 5. State as of 2026-08-30

> ### ⚠️ `art_work/out` IS EMPTY. `game/assets/atlases` IS NOW THE ONLY COPY OF THE ART.
>
> Cleared on the owner's instruction 2026-08-30, after checking the one condition that
> made it safe: **every one of the 288 real bakes in `out` was already staged.** The 35
> directories with no staged counterpart were all throwaway — 32 `vis.probe_*` and the
> `_batch` / `_inspect` / `_run` logs. **9.46 GB → 1.04 MB**, and the logs were kept
> deliberately, because §4's "compare a WARN against the same recipe's previous log" needs
> them and they cost 1 MB.
>
> **THE HAZARD HAS INVERTED, so unlearn the old rule.** It used to be that a bare
> `stage_atlases.py` was the dangerous command, because `out` held bakes older than staged
> and staging copies on any byte difference without knowing which side is newer. That is
> now harmless: `out` is empty, so a bare run copies nothing.
>
> **`stage_atlases.py --clean` is the dangerous command now, and it is unrecoverable.**
> `--clean` does `shutil.rmtree(DEST)` first and then refills from `out` — which would
> delete all 361 staged atlases and put nothing back. There is no second copy on this
> machine. Recovery would be a full rebake of the entire roster, hours of it, or Google
> Drive version history. **Never pass `--clean` again until `out` is whole.**
>
> **Nothing is lost that cannot be rebuilt**, which is why this was safe: `out` is derived
> from committed recipes plus isobake, and `isobake inspect` reads the SOURCE actor, so
> measuring an actor still needs no bake. Only re-reading a baked FRAME now costs a bake
> first.
>
> **`stale_recipes.py` reads the STAGED atlas, not `out`**, so it is unaffected and still
> right about what the game can see.

> **The render-box run recipe lives in [tools/render_box_prep.md](tools/render_box_prep.md)**
> — env paths, shards, and what each skipped step breaks. The two flags that job
> needs are in §4 under "A PIPELINE FIX CHANGES NO RECIPE".

- **A.10, the building roster, is CLOSED** — owner, 2026-09-01. Every declared building has
  its staged atlas and its four-age map, with two excluded assets that are not buildings and
  are tracked as [P7] and [P6]. Closed on the owner having played it rather than on a check,
  so a building bug **reopens A.10**; it does not contradict the closure.
- **`vis.farm` IS NOT BLOCKED, whatever PLAN.md §12A A.4 still says.** It was baked and
  staged 2026-08-25 and the owner confirmed it in game. **0 A.D.'s "farm" is our "field"**,
  it attaches to the mill, and **fields do not age**: the game picks one of four at
  placement time, `vis.field_1..4` → `field_age2` / `field_age3` / `field_age4` / `farm`.
  The 64-attachpoint scatter collapse is real, unfixed and **not worth fixing** — one crop
  clump reads fine at this camera. `tools/recipes/farm.toml` and `field_age2.toml` carry it.
  > ⚠️ **THE THREE `field_ageN` RECIPES NAME ONE ACTOR AND DIFFER ONLY BY THE RECIPE-ID
  > VARIANT SEED.** That is the same mechanism §4 calls catastrophic for player colour, and
  > here it is the *feature* — it is what makes three different-looking fields. Giving them
  > a `variant_seed`, or merging age3 and age4 as their own headers once suggested, would
  > silently cost the game three quarters of its field variety. **The fix that is right for
  > a colour set is wrong here; read what the ids are FOR before generating over them.**
- **193 base recipes**, **168 generated colour recipes** (21 units × 8).
- **Nothing is running** on the workstation.
- **Staging is complete and current: 361 atlases.** All eight colours are correct
  for all 21 colourable units — `check_colour_consistency.py --staged` reports
  **0 of 21 with pages that disagree and 0 where only the import counts did**.
- `vis.ballista` is base-only because **its own** crew textures measure a 0% mask
  — *not* because siege engines are a class that cannot tint. The ram does, at
  6.8%; see §4. Every other unit has its eight. **Re-measured 2026-08-16 after
  the crew got their heads and helmets back: still 0.00%** (21,761 opaque pixels,
  0 moving >64, largest channel gap 14 — under the noise floor). The rescued kit
  carries no mask either, so `"colours": false` is confirmed rather than assumed.
- **All four siege engines animate**, deployed and packed. Each was static for a
  different wrong reason and each fix outlived the last: the ballista's was a
  tool/bake disagreement about which armature the bake drives, the onager's was
  that its clip had nowhere correct to land, the packed trebuchet's was the crew
  stealing the subject-armature pick. All three lessons are in §4.
- **Build identity is live.** Staged population, counted off disk 2026-08-29:

  ```
  878eb40e4d3b  build 39  197 atlases   the current pipeline
  db9dc8e71cd9  build 38   76 atlases   the reflection re-bake
  (no keys)                67 atlases   predates the stamp
  e257ae83d53f  build 36   20 atlases
  780431d781f7  build 34    1 atlas     DIRTY
  ```

  Each unit's own set is internally uniform, which is what the game side's
  staleness rule keys on, so it reads 0 stale. **Compare by uniformity, not
  ordering** — "these eight do not all carry the same identity" works on a wholly
  unstamped set where "older than the newest sibling" does not, and
  `isobake_build` is monotonic only while history stays linear.

  **Commit isobake BEFORE the bake you intend to stage.** Exactly one staged atlas
  now says `dirty=True`, down from 15, which means the code that made it is not
  recoverable from any commit. The stamp records that honestly and that is the
  whole point, but it is a hole, not a badge. I stopped a colour batch mid-flight
  on 2026-08-17 to commit and rebake for exactly this reason; it cost 20 minutes.
  Do the same.

  **Do not backfill the 67 unstamped ones.** The pass is cheap but there is no true
  value to write: today's build would assert code that did not run, and would erase
  the only honest signal on disk. Absence already *is* the sentinel.

### isobake: repo `blender_3d_to_2d_isobake`, HEAD `878eb40`, build 39, clean

Its history is a list of silent defects, and every lesson worth re-reading is
already in §4 rather than here. What that history is FOR is calibration: **six
separate bugs in this pipeline reported `ok` for every frame they ruined**, so a
green batch summary is evidence of nothing. The reflection, the coloured faces,
the variant seed, two wrong armature picks and the deer's location curves all
shipped past it.

The one-line index, so a symptom can be matched to a known shape:

| what it looked like | what it was |
|---|---|
| units facing the wrong way, unfixable by rotation | the compass ran backwards — a REFLECTION |
| villagers with player-coloured faces | alpha role read per actor, applied per material |
| every `player_trans` surface baked red | the importer hardcodes 0 A.D.'s red |
| white a no-op, dark colours crushed | the tint was a MULTIPLY |
| each player's archer wearing different kit | variant RNG seeded from the recipe id |
| a corpse standing up for one frame | `decay` sampled `Death` from position 0.0 |
| a siege engine frozen in its bind pose | the clip landed on a crew member's rig |
| a deer reared and pitching | pose-bone locations transferred between unlike rigs |

### Known open items

- **`vis.dragon` is out for rigging, and the blocker has MOVED from the art to isobake.**
  The mesh has no rig at all — verified pristine against HEAD's git-lfs `oid`, then read
  four ways (§4). The art is 0 A.D.'s own and CC-BY-SA 3.0, **not** bespoke as PLAN.md A.9
  and `asset_request.md` [P7] both assumed, so it can be rigged and the rig redistributed;
  `tools/recipes/dragon.toml` has led with that correction since 2026-08-25 and it went
  unread twice. `tools/dragon_to_glb.py` prepares the upload; outputs live in
  `art_source/dragon_rig`, never in the repo.
- **`adapters/generic.py` IS THE ONLY THING BETWEEN A RIGGED DRAGON AND AN ATLAS, and it is
  a stub that raises `NotImplementedError`.** Only `zeroad`, `terrain` and `smoke` are real.
  Its own docstring scopes the job and it is bounded rather than a rewrite: camera, rotation
  loop, projection, packing and atlas format are all source-agnostic and already work, so
  the adapter only has to stand a subject at the origin at the right scale with its clips
  resolved — enable the bundled importers, remap axes to `directions.CANONICAL_FORWARD`,
  fit to the recipe's `height_m`, and map action names onto clip names.
  **`isobake inspect` ALREADY reads glTF and FBX**, so judge a rigged file — armature,
  actions, bounding box, real-world size — *before* writing the adapter that consumes it.
  That ordering is the point: it costs nothing and tells you whether the rig is worth the
  work.
- **The root bone is exempt from nothing, and `location_scale = 0.0` therefore
  drops a death clip's fall.** The deer's carcass floats ~5 px (0.22 m) — its
  lowest pixel sits 4–8 px above the anchor where the wolf's sits 17–35 px below.
  §4 has the mechanism. **The fix is to exempt the root bone from
  `location_scale`**, which is a small, well-defined isobake change and the only
  open pipeline item. It affects one asset today; it would affect any future
  species whose clips come from an unlike rig.
- **`vis.deer`'s `run` clip is a substitution, not a bake.** `deer_run_01.dae`
  does not transfer to this rig at all, so `run` is the walk clip at 22 fps under
  its own anim name. If anyone ever writes a real retarget step, this is the asset
  that would get its gallop back. §4 has the test that found it.
- **`swordsman`/`elite_swordsman`** actors declare a mesh in two groups and the
  importer imports both. Worked around per recipe with `drop_objects`; a general
  fix belongs in the importer's variant resolution. The owner has seen the
  current output in-game and is content to leave it — do not re-open unprompted.
- **Canvas sizes are calibrated, not computed, so expect a bump after any fix
  that makes a sprite BIGGER.** `_rescue_orphaned_props` did exactly that and
  `vis.onager` went 384 → 512. The clip-check catches it at bake time, so the rule
  is only to read the batch summary for `CLIPPED` rather than assume.

## 6. Two things the game side cannot see — tell them

- **Staged is not baked.** Bakes land in `art_work/out`; the game reads
  `game/assets/atlases`. Staging is a separate step and it is mine. If a batch
  finished and their counts have not moved, staging is what is missing.
- **Stale is not missing.** An atlas can be present and wrong, because a pipeline
  fix landed after it was baked. A file-existence check cannot see that; they
  built `stale_colour_atlases()` after I flagged it.
