# AGENT_ASSET.md — the asset-generation agent

Bootstrap for the **art-pipeline agent** on AOD_Mobile. Paste this at the start
of a session so the next one does not have to rediscover any of it.

Its counterpart is [AGENT_GAME_CODER.md](AGENT_GAME_CODER.md). **Read both.** The
two agents share one working tree and one repo, and each owns a side of the fence
described below.

Last updated 2026-08-17.

---

## 1. Who I am and what I do not touch

I own the **art pipeline**: 0 A.D. source art in, baked sprite atlases out.

| Mine | Not mine |
|---|---|
| `tools/` — recipes, bake scripts, generators | `game/` — the entire Godot project |
| `art_work/out/` — bake output | `game/data/*.json` — flag problems, do not edit |
| `art_source/0ad` — the 0 A.D. checkout | game scenes, sim, tests |
| the isobake source (its own repo, §2) | `AGENT_GAME_CODER.md` |
| `asset_request.md` (my replies) | |

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

Two agents commit to **one working tree**. `git log` interleaves our commits.
Always `git add` explicit paths — never `-A` — and check what you staged. Files
can also collide: this very document was overwritten by the other agent's stub
between my writing it and committing it. Re-read before you commit.

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

## 2. Machine layout

Nothing below is on `PATH`; all of it is machine-local and uncommitted.

```
isobake CLI     C:\Users\herman.ras\Downloads\AOD_game\tools_env\venv\Scripts\isobake.exe
python (venv)   C:\Users\herman.ras\Downloads\AOD_game\tools_env\venv\Scripts\python.exe
Blender 4.5.12  C:\Users\herman.ras\Downloads\AOD_game\tools_env\blender-4.5.12-windows-x64
0 A.D. art      C:\Users\herman.ras\Downloads\AOD_game\art_source\0ad\binaries\data\mods\public
bake output     C:\Users\herman.ras\Downloads\AOD_game\art_work\out
isobake source  C:\Users\herman.ras\Downloads\AOD_game\blender_3d_to_2d_isobake   (separate git repo)
importer        C:\Users\herman.ras\Downloads\AOD_game\tools_env\pyrogenesis_importer_src
```

Paths resolve from `tools/isobake.local.toml` (`paths.out`, `art_source`,
`pyrogenesis`). **isobake is an editable install** — editing its source changes
behaviour immediately, so never edit it while a batch runs.

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
`Age & Unit Planning.md` is `simulation/templates/<path>.xml`; the actor is one
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

## 5. State as of 2026-08-27

> ### ⏳ AN OVERNIGHT RUN IS PREPPED AND NOT YET LAUNCHED — 232 bakes
>
> **The render box was OFF when this was written.** Everything else is ready and
> verified; the run is waiting on the machine, not on a decision.
>
> **Why:** isobake `e6fc052` (build 37) fixes a REFLECTION that mirrored every 8-
> and 5-direction atlas in the project. See §4, "The compass ran backwards". Two
> probes are baked, staged and confirmed correct — `vis.scout_cavalry` with all
> eight colours, and `vis.wolf`.
>
> **The sequence, all three steps, in order:**
>
> ```powershell
> # 1. ON THE WORKSTATION, once the box is on. Pushes isobake e6fc052 to it.
> powershell -File tools\provision_render_box.ps1 -WhatIf     # check the target
> powershell -File tools\provision_render_box.ps1
>
> # 2. ON THE RENDER BOX, from the synced repo.
> powershell -File tools\render_box_bake.ps1 -PipelineStale -Directions "5,8" -WhatIf
> powershell -File tools\render_box_bake.ps1 -PipelineStale -Directions "5,8"
> ```
>
> **`-PipelineStale` IS NOT OPTIONAL AND THE RUN SILENTLY DOES NOTHING WITHOUT
> IT.** `stale_recipes.py` compares recipe bytes, and this fix changed no recipe —
> without the flag the box prints "nothing is out of date" and idles until morning.
> `-Directions "5,8"` keeps the 89 one-direction buildings, which the fix cannot
> reach, out of the night. Together they select **80 base + 152 colour = 232**;
> the scout and wolf are already at `e6fc052` and drop out on their own.
>
> **STEP 1 IS THE ONE THAT WILL BITE.** The box still holds isobake **build 36**.
> Bake before provisioning and it re-mirrors all 232 with the old code, reports
> `ok` for every one of them, and the only sign is the stamp. Worse, the box
> computes "current commit" from *its own* isobake: at build 36 it would either
> select nothing, or select the two probes and bake them BACKWARDS.
>
> **The repo reaches the box through Google Drive, the toolchain does not.**
> `tools/stale_recipes.py` and `tools/render_box_bake.ps1` both changed today
> (`7685fa0`) — let Drive settle on the box before launching, or it runs the old
> selection logic, which is the do-nothing case again.
>
> **Verify after, not just the summary** — a summary full of `ok` is exactly what
> the coloured-faces batch produced. `check_colour_consistency.py --pixels` before
> staging, then `preview_facing_chart` columns 0/2/4/6 on a chiral unit. The game
> side re-runs `preview_walls` to confirm the walls changed *harmlessly* rather
> than not at all.

- **171 base recipes**, **160 generated colour recipes** (20 units × 8).
- **Nothing is running** on the workstation.
- **10 atlases are at build 37 and the other 321 are not**, which is deliberate
  and temporary: `vis.scout_cavalry` + its 8 colours, and `vis.wolf`. Everything
  else is still mirrored until the run above lands.
- **Staging is complete and current: `331/331, RESULT: OK`.** All eight colours
  are correct for all 20 colourable units; the game agent is no longer restricted
  to red and yellow.
- `vis.ballista` is base-only because **its own** crew textures measure a 0% mask
  — *not* because siege engines are a class that cannot tint. The ram does, at
  6.8%; see §4. Every other unit has its eight. **Re-measured 2026-08-16 after
  the crew got their heads and helmets back: still 0.00%** (21,761 opaque pixels,
  0 moving >64, largest channel gap 14 — under the noise floor). The rescued kit
  carries no mask either, so `"colours": false` is confirmed rather than assumed.
- **Both siege engines animate.** `vis.ballista` since 2026-08-16 and
  `vis.onager` since 2026-08-17 — `idle`/`attack`/`die`/`decay`, 140 frames each.
  Each was static for a different wrong reason and the second outlived the fix for
  the first: the ballista's was a tool/bake disagreement about which armature the
  bake drives, the onager's was that its clip had nowhere correct to land (§4,
  "The subject armature of a subject with no rig").
- **Build identity is live.** Staged population, counted off disk 2026-08-17:

  ```
  (no keys)               298 atlases   predates the stamp
  780431d781f7  build 34   13 atlases   the fields, the farm, the ORE set   DIRTY
  e257ae83d53f  build 36    9 atlases   vis.onager + its 8 colours
  8aa37b04f718  build 33    2 atlases   vis.ballista                        DIRTY
  531a4bce4f14  build 28    2 atlases   the two food props
  ```

  Each unit's own set is internally uniform, which is what the game side's
  staleness rule keys on, so it should still read 0 stale.

  **Commit isobake BEFORE the bake you intend to stage.** 15 of the 26 stamped
  atlases say `dirty=True`, which means the code that made them is not recoverable
  from any commit — the stamp records that honestly and that is the whole point,
  but it is a hole, not a badge. I stopped a colour batch mid-flight on 2026-08-17
  to commit and rebake for exactly this reason; it cost 20 minutes and the nine
  onager atlases now name a real commit. Do the same.
- Verified beyond the batch summary, because a summary full of "ok" is exactly
  what the coloured-faces batch produced: 0 pixels move >64 between each unit's
  last `die` frame and first `decay` frame across 13 units × 8 colours, and the
  newly-tinted units all separate cleanly (closest pair ΔRGB 40–67).

> **Verification lesson worth keeping:** the first pass at that decay check
> reported false mismatches because the threshold was 2, which is *below* EEVEE's
> sampling noise (~44 in a channel at 24 samples). The tell was that `decay0` and
> `decay1` — the same sampled position — differed by the same amount. When
> comparing rendered frames, establish the noise floor from two frames that must
> be identical before choosing a threshold.

### Recently fixed in isobake (repo `blender_3d_to_2d_isobake`, HEAD `e257ae8`, build 36)

Newest first; the numbering is historical, not a ranking.

- **2026-08-17 — the all-anchored `subject_armature` tie-break ranked by bone
  count**, so a subject whose own mesh is unrigged and which carries several rigged
  props at the same depth — the onager, whose base plane holds an arm and three
  crew — handed the recipe's clip to a crew member. Ranks by props owned now, in
  both branches. §4 has the full lesson. This is what stood between `vis.onager`
  and an animated bake.

0. **`inspect` reported the wrong armature**, and **nested props of nested props
   were never anchored** — both landed 2026-08-16 and both are covered in §4.
   Between them they turned `vis.ballista` from a static, headless-crewed sprite
   into an animated one (idle/attack/die/decay, 140 frames) whose three
   operators have heads. `vis.onager` gains the same crew heads.

1. The tint was a MULTIPLY — white a no-op, dark colours crushed. Now mixes
   toward the colour, preserving texture shading with headroom scaling.
2. The importer builds its own player-colour chain with 0 A.D.'s **red
   hardcoded** and wires it into Base Color; isobake skipped those materials, so
   every `player_trans` surface baked red. Now walks back to the texture.
3. Alpha role was read per **actor** and applied per **material** — which put
   player-coloured faces on villagers, and hid colour entirely on composite
   actors (horse hides rider, hull hides sail). Now decided per material.
4. `AnimSpec.start` — `decay` reuses `Death`, and sampling from 0.0 made its
   first frame the unit still standing. Every corpse stood up for a frame.
5. `_subject_armature` ranked rigs by bone count and picked a duplicate inflated
   to 202 bones by Blender datablock reuse. Now ranks by props anchored **to** it.

### Known open items

- **Canvas sizes are now under-provisioned wherever crew got their heads back.**
  `_rescue_orphaned_props` makes a sprite BIGGER, and a canvas calibrated against
  a headless bake can no longer hold it: `vis.onager` clipped on S/SE/E at its
  old 384 and went to 512. `vis.ballista` at 384 was fine (46.4% fill). **Every
  other composite actor with nested crew is unverified** — the clip-check will
  catch it at bake time, so the rule is simply to read the batch summary rather
  than assume, and to expect a canvas bump or two on the next full rebake. The
  staged atlases predate the fix and are internally consistent, so nothing is
  broken today.
- **Seven staged colour atlases are missing geometry**, from the parallel-slot race
  in the 3-wide colour batch of 2026-08-16. `python tools/check_colour_consistency.py
  --pixels` names them, and the project owner chose on 2026-08-17 to leave them
  rather than spend the machine time; the repair is a rebake at `-Parallel 1` and a
  re-run of that command.

  ```
  vis.archer   orange 5.62%  violet 6.39%  white 4.92%   short
  vis.galley   cyan 0.79%  orange 0.82%  white 0.86%  yellow 1.49%
  ```

  `vis.fishing_ship` (blue, orange) is WARN not SHORT: two objects fewer, pages
  identical — a 0-bone armature shell and a coincident duplicate mesh, invisible.
  Leave it. The other 17 units are clean, and the nine onager atlases were baked
  under this rule and verified against it.
- **`swordsman`/`elite_swordsman`** actors declare a mesh in two groups and the
  importer imports both. Worked around per recipe with `drop_objects`; a general
  fix belongs in the importer's variant resolution. The owner has seen the
  current output in-game and is content to leave it — do not re-open unprompted.

### Done since

- **Build identity in the atlas `generator` block** — `isobake_commit`,
  `isobake_build` (a `git rev-list --count`, so it orders without a clock) and
  `isobake_dirty`. Landed as isobake `531a4bc`, amended by `99a33cc` so that all
  three keys are **always present and null when git could not answer**. That
  gives three states, and the middle one is the point:

  ```
  keys absent    built before 531a4bc      <- the 323 staged before it
  keys null      current code, git failed  <- provenance broke; should never happen
  real values    a known commit            <- the 2 food props, build 28
  ```

  Without it, a bake where git was missing from the Blender subprocess's `PATH`
  would have been indistinguishable from genuinely older art, and the consumer
  reads "no keys" as "old". `99a33cc` also stopped `isobake_dirty` reporting a
  tree **clean** when `git status` itself had failed.

  **Do not backfill the 323**, and I refused it on 2026-08-16 when the game side
  offered to take it: the pass is cheap (JSON rewrite, seconds) but there is no
  true value to write. Today's build would assert code that did not run, and
  would erase the only honest signal on disk — the two food props really are
  build 28. Absence already *is* the sentinel.

  **Tell the consumer to compare by uniformity, not ordering:** "these eight do
  not all carry the same identity" works today with a wholly unstamped set,
  where "older than the newest sibling" does not. Prefer commit *equality* to
  `isobake_build` ordering where possible — the count is monotonic only while
  history stays linear.
- **`vis.siege_ram` colour** — I had it wrong, see the measurement note in §4.
  It tints at 6.8% and is fine.
- **`vis.field` / `vis.farm` prop points** — fixed 2026-08-17 and both delivered.
  The mechanism was not the Pyrogenesis importer at all, which is what the open
  item here used to claim: 0 A.D. writes `<matrix sid="parentinverse">` ahead of the
  real `<translate>`, and **Blender's own COLLADA importer** keeps the leading
  matrix, so all 65 patch points collapsed onto the origin. isobake places the
  empties itself now, from the COLLADA.
- **`vis.onager` animation** — 2026-08-17, and it closes out the "both siege
  engines are static" story entirely. See §4 and `tools/recipes/onager.toml`.
- **The bone-less mesh defect was never real for the siege engines.**
  `m_armor_tunic_short.dae` does import with a 0-bone armature. Both siege engines
  were said to as well, and that was a misreading of `inspect` reporting a crew
  shell (§4): the lithobolos has a 36-bone rig and the onager arm an 8-bone one,
  and both animate. **Do not cite this as a reason to bake anything static without
  re-measuring** — it is the false premise that kept two engines frozen, one of
  them for a year.

## 6. Two things the game side cannot see — tell them

- **Staged is not baked.** Bakes land in `art_work/out`; the game reads
  `game/assets/atlases`. Staging is a separate step and it is mine. If a batch
  finished and their counts have not moved, staging is what is missing.
- **Stale is not missing.** An atlas can be present and wrong, because a pipeline
  fix landed after it was baked. A file-existence check cannot see that; they
  built `stale_colour_atlases()` after I flagged it.
