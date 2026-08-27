# Render box prep

Bringing the render box from **powered off** to **baking**. Follow the steps in
order; each one names what breaks if it is skipped, because most of these fail
*silently* rather than loudly.

Two machines are involved and it matters which one you are typing on:

| | |
|---|---|
| **workstation** | where the art agent works. Holds the master toolchain |
| **render box** | i9 / 64 GB / NVMe. Bakes 4-wide. Off unless in use |

---

## 0. The paths, and why they cannot be changed

Everything below is machine-local and **none of it is on `PATH` by default**.
The two machines must use **identical absolute paths** — see step 2.

```
toolchain root   C:\Users\herman.ras\Downloads\AOD_game
  venv python    C:\Users\herman.ras\Downloads\AOD_game\tools_env\venv\Scripts\python.exe
  isobake CLI    C:\Users\herman.ras\Downloads\AOD_game\tools_env\venv\Scripts\isobake.exe
  Blender 4.5.12 C:\Users\herman.ras\Downloads\AOD_game\tools_env\blender-4.5.12-windows-x64\blender.exe
  isobake source C:\Users\herman.ras\Downloads\AOD_game\blender_3d_to_2d_isobake      (its own git repo)
  0 A.D. master  C:\Users\herman.ras\Downloads\AOD_game\art_source\0ad\binaries\data\mods\public
  art shards     C:\Users\herman.ras\Downloads\AOD_game\art_shards\slot<N>\public     (render box only)
  bake output    C:\Users\herman.ras\Downloads\AOD_game\art_work\out

MinGit            C:\Users\herman.ras\AppData\Roaming\MinGit      <- workstation
                  C:\Users\herman.ras\AppData\Local\MinGit        <- render box
  the PATH entry  ...\MinGit\cmd

  THE TWO MACHINES DIFFER, verified 2026-08-27: the workstation has it under
  Roaming (which is what provision_render_box.ps1 copies) and the render box
  resolves it from Local. Both work. Do not "correct" either to match the
  other -- ask Get-Command where git actually is, per step 2b, rather than
  trusting a path in this table.

repo (Drive)     C:\Users\herman.ras\GoogleDrive\DEV\Godot\DEV\AOD_Mobile
```

**The repo is synced by Google Drive and the toolchain is not.** `tools/`,
`game/` and the recipes are one folder shared two ways; everything under
`Downloads\AOD_game` is per-machine and is copied by `provision_render_box.ps1`.

---

## 1. Power on, and confirm the box is reachable

On the **workstation**:

```powershell
Test-Path "\\192.168.0.10\Users\herman.ras"      # LAN
Test-Path "\\100.96.0.1\Users\herman.ras"        # Tailscale
```

`False` on both usually means the box is simply off. Whichever answers, pass it
as `-Target`; the script's default is one of the two and may not be the live one.

---

## 2. ENV PATHS — set these on the render box before anything else

Two separate requirements. Both fail quietly.

### 2a. The toolchain path must be identical to the workstation's

The venv's base interpreter is **Blender's own bundled python inside the copied
tree** (`tools_env\venv\pyvenv.cfg`), and the isobake editable install resolves
through an **absolute `.pth`**. Both record
`C:\Users\herman.ras\Downloads\AOD_game\...`, so copying to the same path under
the same username makes the venv work untouched — and copying anywhere else
breaks it with no relocation step to fix it.

**So the render box's user profile must be `herman.ras`.**
`provision_render_box.ps1` refuses a target that is not, rather than producing a
venv that cannot import anything.

### 2b. `git` must be on the WINDOWS `PATH`

isobake shells out to `git` to stamp `isobake_commit` / `isobake_build` /
`isobake_dirty` into every atlas, **from a Blender Windows subprocess**. WSL's
git does not count. Without it every atlas the box bakes records *null*
provenance — which looks like nothing at a glance and is a permanent hole in the
record, since there is no true value to backfill later.

`render_box_bake.ps1` refuses to start without it, so this is the one env
failure that is loud. Set it **persistently**: an overnight run may be launched
from a fresh shell or a scheduled task, where a session-only variable is gone.

**Test whether it is already there before setting anything.** MinGit may sit in
either PATH scope — on the workstation it is in the **Machine** PATH, not the
User one — so checking a single scope for the string reports a false "missing"
and appends a redundant copy. `Get-Command` is the honest question, and it is
the same one the preflight asks:

```powershell
# On the RENDER BOX. Both locations are real -- see the table in step 0.
$mingit = "C:\Users\herman.ras\AppData\Local\MinGit\cmd"
if (-not (Test-Path $mingit)) { $mingit = "C:\Users\herman.ras\AppData\Roaming\MinGit\cmd" }

if (Get-Command git -ErrorAction SilentlyContinue) {
    "already resolves: " + (Get-Command git).Source
} else {
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    [Environment]::SetEnvironmentVariable("Path", ($user.TrimEnd(';') + ";" + $mingit), "User")
    $env:Path += ";$mingit"          # SetEnvironmentVariable only affects FUTURE processes
    "added to the User PATH"
}
```

Then **open a new PowerShell** and verify it resolves to MinGit rather than to a
`git.exe` shim or a WSL wrapper:

```powershell
(Get-Command git).Source        # -> C:\Users\herman.ras\AppData\Roaming\MinGit\cmd\git.exe
git --version
```

---

## 3. Provision from the workstation

Pushes the toolchain — **including the isobake source and its `.git`**, which is
what makes the stamp work over there.

```powershell
# ON THE WORKSTATION
powershell -File tools\provision_render_box.ps1 -WhatIf      # prints the plan and byte counts
powershell -File tools\provision_render_box.ps1
```

It verifies the art checkout is **pristine** first and aborts if it is not: a
bake rewrites `.dae` in place, and copying a dirty checkout reproduces that
damage on the box, where it bakes into every atlas and is indistinguishable from
a source-art problem. Fix with `restore_art_sources.ps1 -Apply`, do not skip the
check.

Robocopy skips files matching on size and timestamp, so a re-provision after a
code change moves only what changed — usually just isobake.

> **THE STEP THAT IS EASIEST TO SKIP AND MOST EXPENSIVE TO SKIP.** If the reason
> for the run is an isobake fix, provisioning is what carries the fix. Bake first
> and the box happily re-renders everything with the **old** code, reports `ok`
> for every recipe, and the only evidence is the stamp. It also poisons the
> selection: the box computes "the current commit" from *its own* isobake, so an
> un-provisioned box either selects nothing or selects the already-correct
> atlases and bakes them backwards.

**Confirm on the box** that it received what you meant to send:

```powershell
git -C C:\Users\herman.ras\Downloads\AOD_game\blender_3d_to_2d_isobake rev-parse --short HEAD
git -C C:\Users\herman.ras\Downloads\AOD_game\blender_3d_to_2d_isobake status --porcelain   # expect empty
```

---

## 4. Shards — once per box

Each parallel slot gets its **own copy of the art**, ~5.7 GB apiece. That
removes the shared state the Pyrogenesis-importer race needs rather than
scheduling around it, which is what makes `-Parallel 4` safe here when the
standing rule on the workstation is `-Parallel 1` for colour variants.

```powershell
# ON THE RENDER BOX, from the synced repo. ~23 GB for 4 slots.
powershell -File tools\render_box_bake.ps1 -Setup
```

Already-present shards are refreshed automatically at the start of every run, so
`-Setup` is only for the first time or after they have been cleared.

---

## 5. Let Google Drive settle

The box runs `tools\*` **from the Drive-synced repo**. If the run depends on a
script you changed on the workstation minutes ago, confirm the box has it before
launching — otherwise it executes the old logic, and the usual symptom is a run
that selects nothing and exits looking successful.

---

## 6. Bake

```powershell
# ON THE RENDER BOX
powershell -File tools\render_box_bake.ps1 -WhatIf
powershell -File tools\render_box_bake.ps1
```

**If the run exists because the PIPELINE changed rather than a recipe, add
`-PipelineStale`, or it will do nothing at all.** `stale_recipes.py` compares
recipe bytes against the hash the atlas records, and a fix inside isobake changes
no recipe. Bound it with `-Directions` to the recipes the change can actually
reach — `"5,8"` for anything touching the direction sweep, which excludes the 89
one-direction buildings.

```powershell
powershell -File tools\render_box_bake.ps1 -PipelineStale -Directions "5,8" -WhatIf
```

`-WhatIf` prints the exact recipe list and launches nothing. Always read it: the
count is the cheapest possible check that the selection means what you think.

---

## 7. Verify before trusting, and before staging

A summary full of `ok` is exactly what the batch with player-coloured faces
produced.

**`python` is not on `PATH` on either machine** — bare `python` opens the
Microsoft Store alias and exits. Call the venv interpreter by full path, which is
also the only one that can import isobake:

```powershell
$py = "C:\Users\herman.ras\Downloads\AOD_game\tools_env\venv\Scripts\python.exe"

& $py tools\check_colour_consistency.py --pixels    # BEFORE staging
& $py tools\stage_atlases.py --dry-run
& $py tools\stage_atlases.py
```

`stage_atlases.py` has **no per-id filter** — it copies everything in
`art_work\out`, so anything baked as a one-off probe is staged along with the
batch whether you meant it or not.

**THE COLOUR CHECK IS A GATE ON STAGING, AND AN OLD ACCEPTED DEFECT WILL HOLD
THE WHOLE RUN.** `render_box_bake.ps1` skips staging entirely when
`check_colour_consistency.py` reports anything, and that check looks at **every**
colourable unit in `art_work\out`, not just the ones this run baked. On
2026-08-27 a four-recipe run baked cleanly and staged nothing, because
`vis.fishing_ship` blue and orange have been 0.84% short since a 3-wide batch in
August and the project owner had chosen to leave them.

Two ways out, and prefer the first:

1. **Re-bake the flagged unit's eight colours here.** The shards make that safe
   at width, so the shortfall is repaired rather than tolerated, and the gate
   then passes honestly. A full `-PipelineStale` run does it as a side effect.
2. Stage by hand once you have *read* the shortfall and accepted it:
   `& $py tools\stage_atlases.py`. Do not do this without reading it — the check
   exists because a short bake reports `ok`, packs cleanly and tints correctly.

The master art checkout is never written by a sharded run, so **no restore is
needed afterwards**. It is verified at the end of every run anyway, because an
assumption that is never checked is only a hope.

---

## Quick reference

| symptom | cause |
|---|---|
| `nothing is out of date` on a pipeline fix | missing `-PipelineStale` |
| a **handful** of bakes when you expected hundreds | also missing `-PipelineStale` — it selected only the recipes someone edited |
| `staging SKIPPED -- colour consistency failed` | a colourable unit is short **anywhere** in `out`, not necessarily one this run baked (step 7) |
| atlases stamp `isobake_commit: null` | git not on the **Windows** PATH (step 2b) |
| venv cannot import anything | toolchain copied to a different path or user (step 2a) |
| `shard N missing` | needs `-Setup` once (step 4) |
| art renders the way it did before the fix | box was not provisioned (step 3) |
| provisioning aborts | art checkout dirty — `restore_art_sources.ps1 -Apply` |
