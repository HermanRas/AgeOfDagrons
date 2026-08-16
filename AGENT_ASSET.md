# AGENT_ASSET.md — the asset-generation agent

Bootstrap for the **art-pipeline agent** on AOD_Mobile. Paste this at the start
of a session so the next one does not have to rediscover any of it.

Its counterpart is [AGENT_GAME_CODER.md](AGENT_GAME_CODER.md). **Read both.** The
two agents share one working tree and one repo, and each owns a side of the fence
described below.

Last updated 2026-08-16.

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
`tools/restore_art_sources.sh --apply` after a batch, **never during one**.

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
figures: `siege_ram` 6.8%, `onager` 7.1%, `transport_ship` 10.1% (its sail only;
the skiff hull is opaque), `ballista` 0.0% and so correctly has no colour
variants.

> An earlier version of this file asserted "no siege engine in 0 A.D. carries
> player colour". That was **wrong** — generalised from a scan covering only the
> lithobolos/ballista family, and disproved by the ram, which the owner spotted
> in a contact sheet. A measurement on three actors is not a rule about a class.

**Probe before committing to a long batch — but probe what you will judge.** A
`directions = 1`, clips-stripped recipe bakes in ~12 s against ~15 min. A
white-vs-blue pair proves the tint lands on the right pixels; it will **not**
show you what eight players look like side by side. That mistake cost a 3.7 h
batch that finished 112/112 "ok" with player-coloured faces.

**`-Parallel`**: 2 while the owner is using the machine, 3 when idle, 4 saturates
it. The ceiling is RAM — a full Blender scene per slot.

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

## 5. State as of 2026-08-16

- **163 base recipes**, **160 generated colour recipes** (20 units × 8).
- **Nothing is running.** The colour backlog is finished: batch
  `20260816-122118`, 90/90, 0 failures, 5.1 h at 3-wide.
- **Staging is complete and current: `325/325, RESULT: OK`** — the first fully
  complete staging this project has had, plus the two food props of 2026-08-16.
  All eight colours are correct for all 20 colourable units; the game agent is no
  longer restricted to red and yellow.
- `vis.ballista` is base-only because **its own** crew textures measure a 0% mask
  — *not* because siege engines are a class that cannot tint. The ram does, at
  6.8%; see §4. Every other unit has its eight.
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

### Recently fixed in isobake (repo `blender_3d_to_2d_isobake`, HEAD `99a33cc`, build 29)

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

- **`vis.ballista`'s crew are headless — NEXT PIECE OF WORK.** The bake does
  include the three operators, but every head, helmet and tool sits at the world
  origin buried inside the engine. The crew are props of the engine and their
  heads are props **of the crew**; the pinned importer resolves one level of
  nesting and drops anchoring on the second. Same defect class as the mis-rooted
  shields that isobake already works around by name
  (`_drop_misrooted_nested_props`), one level deeper. Fixing it may also unlock
  colour: the **packed** variant (`units/carthaginians/siege_rock_packed`) uses
  `player_trans_norm_spec` on the hull itself and mounts horses, so it should
  tint even though the deployed lithobolos does not. Until then `vis.ballista`
  is static, colourless and headless-crewed — usable, but not final.
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
- **The bone-less mesh defect**: `m_armor_tunic_short.dae` and both siege engines
  import with a 0-bone armature, so no clip attaches. Root cause never found;
  worked around by picking another actor or baking static.

## 6. Two things the game side cannot see — tell them

- **Staged is not baked.** Bakes land in `art_work/out`; the game reads
  `game/assets/atlases`. Staging is a separate step and it is mine. If a batch
  finished and their counts have not moved, staging is what is missing.
- **Stale is not missing.** An atlas can be present and wrong, because a pipeline
  fix landed after it was baked. A file-existence check cannot see that; they
  built `stale_colour_atlases()` after I flagged it.
