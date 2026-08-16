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
| `ASSET_MISSING.md` | |

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

**Not every actor can take player colour.** It is decided per material, by
whether the importer built its `player_trans` chain. Measure before baking eight
of anything: probe white vs blue at `directions = 1` and count moved pixels.
Established: **no siege engine** in 0 A.D. carries colour (it lives on separate
crew actors); `structures/celts/skiff` is opaque and only its sail tints;
`vis.ballista` measured 0.0% and correctly has no colour variants.

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
- **Staging is complete and current: `323/323, RESULT: OK`** — the first fully
  complete staging this project has had. All eight colours are correct for all
  20 colourable units; the game agent is no longer restricted to red and yellow.
- `vis.ballista` is base-only by design (no siege engine in 0 A.D. carries player
  colour); every other unit has its eight.
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

### Recently fixed in isobake (repo `blender_3d_to_2d_isobake`, HEAD `ea396c4`)

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

- **A build serial (or isobake commit) in the atlas `generator` block.** Offered
  by me, accepted by the game side, not yet done, and cheap. They currently
  detect stale colour bakes by mtime with a one-hour threshold, and a 3-wide
  batch narrows the real margin to ~40 min. A serial orders without a clock. No
  backfill needed — absent means "fall back to mtime".
- **`vis.siege_ram`** was baked before it was understood that siege engines carry
  no player colour. Its eight colours are probably identical — measure it.
- **`swordsman`/`elite_swordsman`** actors declare a mesh in two groups and the
  importer imports both. Worked around per recipe with `drop_objects`; a general
  fix belongs in the importer's variant resolution.
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
