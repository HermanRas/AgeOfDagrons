<#
.SYNOPSIS
  The unattended render-box job: rebake everything out of date, 4-wide, safely.

.DESCRIPTION
  Run this ON the render box, from the synced repo. It does the whole thing:
  refresh the per-slot art shards, bake every recipe whose staged atlas no longer
  matches it, verify, and stage.

  WHY IT SHARDS THE ART CHECKOUT, which is the only clever thing here. The
  Pyrogenesis importer rewrites every .dae it loads, in place. isobake restores
  that per bake -- but the restore is the one piece of state SHARED between
  parallel slots, and different actors are not different FILES: cavalry and
  infantry both pull horse_celtic.dae, and all eight colour variants of one unit
  load an identical mesh set, so they collide on every file they touch.

  The consequence is not a merge conflict. A slot reading a mesh while another
  rewrites it SILENTLY IMPORTS FEWER OBJECTS, reports `ok`, packs cleanly, tints
  correctly and passes every check the pipeline had. It is why onager__blue came
  out with 5 armatures against red's 7, and why three of vis.archer's eight
  colours are still short by 5-6% of their pixels today.

  Giving each slot its own copy of the art removes the shared state rather than
  scheduling around it, so the race cannot occur at any width. That is what makes
  -Parallel 4 safe here when the standing rule on the workstation was -Parallel 1
  for colour variants. It also means the MASTER checkout is never written by a
  bake at all -- so a sharded run needs no restore afterwards, only a shard
  refresh before the next one. The master is verified at the end anyway, because
  an assumption that is never checked is just a hope.

.PARAMETER Setup
  Create the shards and run the preflight, then stop. Needed once, after
  provision_render_box.ps1. Costs ~5.7 GB per slot.

.PARAMETER Parallel
  Slots, and therefore shards. 4 on the i9 / 64 GB box. The ceiling is RAM: one
  full Blender scene per slot.

.PARAMETER NoStage
  Bake and verify, but do not copy atlases into game/assets/atlases.

.PARAMETER PipelineStale
  Also rebake recipes whose atlas is fine against its RECIPE but was baked by a
  different isobake commit than the one installed. Off by default, because most
  pipeline fixes touch a knowable subset and re-rendering the rest burns hours
  producing identical bytes.

  You need this whenever the reason for the run is a change to isobake rather
  than to a recipe, and without it such a run does NOTHING: `stale_recipes.py`
  compares recipe hashes, and a pipeline fix changes no recipe. That is not
  hypothetical -- the direction-sweep fix of 2026-08-27 mirrored every 8- and
  5-direction atlas in the project and left all 331 recipe hashes untouched.

.PARAMETER Directions
  Restrict the run to recipes whose `[render].directions` is in this set, e.g.
  "5,8". The blast radius of a change to the direction sweep, and the natural
  partner to -PipelineStale: it keeps the 89 one-direction buildings, which no
  such change can reach, out of the night.

.PARAMETER WhatIf
  Print the plan -- including exactly which recipes are out of date -- and stop.

.NOTES
  BOTH MACHINES SHARE THE REPO THROUGH GOOGLE DRIVE. The toolchain under
  Downloads is per-machine, but tools/, game/ and everything else is one folder
  synced two ways. Staging from here writes ~330 atlases into that folder; let
  Drive settle before editing the same files on the workstation, and do not run
  a batch on both machines at once.
#>

[CmdletBinding()]
param(
    [switch] $Setup,
    [int]    $Parallel = 4,
    [switch] $NoStage,
    # NOT -Isobake: $Isobake is already this script's path to isobake.exe, and a
    # param of that name is silently overwritten by it a few lines below.
    [switch] $PipelineStale,
    [string] $Directions,
    [switch] $WhatIf
)

$ErrorActionPreference = "Stop"

$Tools     = $PSScriptRoot
$Repo      = Split-Path $Tools -Parent
$Game      = "C:\Users\herman.ras\Downloads\AOD_game"
$Master    = "$Game\art_source\0ad\binaries\data\mods\public"
$ShardRoot = "$Game\art_shards"
$Python    = "$Game\tools_env\venv\Scripts\python.exe"
$Isobake   = "$Game\tools_env\venv\Scripts\isobake.exe"
$Blender   = "$Game\tools_env\blender-4.5.12-windows-x64\blender.exe"

function Step($text) { Write-Host ""; Write-Host "== $text" -ForegroundColor Cyan }
function Fail($text) { throw $text }

# ---------------------------------------------------------------- preflight --
Step "preflight"

foreach ($p in @($Master, $Python, $Isobake, $Blender)) {
    if (-not (Test-Path $p)) { Fail "missing: $p  (run provision_render_box.ps1 from the workstation)" }
}
Write-Host "  toolchain present"

# git must be on the WINDOWS PATH, not just inside WSL: isobake shells out to it
# for the atlas's isobake_commit / isobake_build / isobake_dirty stamp, from a
# Windows subprocess. Without it every atlas this box bakes records null
# provenance, which is a permanent hole and is silent at bake time.
$git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $git) {
    Fail "git is not on PATH. Add C:\Users\herman.ras\AppData\Roaming\MinGit\cmd -- WSL's git does not count, the stamp is written from a Windows process."
}
Write-Host "  git: $git"

# Commit isobake BEFORE a bake intended for staging. 15 of the 26 stamped
# atlases on disk say dirty=True, which means the code that produced them is not
# recoverable from any commit. The stamp records that honestly, and that is the
# point -- but it is a hole, not a badge.
Push-Location "$Game\blender_3d_to_2d_isobake"
$isoDirty  = @(& $git status --porcelain)
$isoCommit = (& $git rev-parse --short HEAD)
$isoBuild  = (& $git rev-list --count HEAD)
Pop-Location
if ($isoDirty.Count -gt 0) {
    Write-Host "  WARNING: isobake has $($isoDirty.Count) uncommitted change(s)." -ForegroundColor Yellow
    Write-Host "           Every atlas from this run will stamp dirty=True and name no recoverable commit." -ForegroundColor Yellow
    Write-Host "           Commit it first unless you mean to throw this batch away." -ForegroundColor Yellow
} else {
    Write-Host "  isobake: $isoCommit (build $isoBuild), clean"
}

# ------------------------------------------------------------------ shards ---
Step "art shards ($Parallel x 5.7 GB)"

$free = (Get-PSDrive C).Free / 1GB
Write-Host ("  free on C: {0:n1} GB" -f $free)
if ($Setup -and $free -lt ($Parallel * 6.5)) {
    Fail ("need about {0:n0} GB free for {1} shards, have {2:n1}" -f ($Parallel * 6.5), $Parallel, $free)
}

for ($s = 1; $s -le $Parallel; $s++) {
    $dest = "$ShardRoot\slot$s\public"
    $exists = Test-Path (Join-Path $dest "art")
    if ($WhatIf) { Write-Host ("  slot{0}: {1}" -f $s, $(if ($exists) { "present, would refresh" } else { "MISSING -- needs -Setup" })); continue }
    if (-not $exists -and -not $Setup) {
        Fail "shard $s missing. Run this script once with -Setup."
    }

    Write-Host ("  slot{0}: {1}..." -f $s, $(if ($exists) { "refreshing" } else { "creating" })) -NoNewline
    # NO /XO here, deliberately. /XO skips a source file older than the
    # destination -- and after a bake the SHARD's .dae are newer than the
    # master's, so /XO would skip exactly the rewritten files this refresh
    # exists to replace. Plain /E copies whenever size or timestamp differ,
    # which restores the dirty ones and skips the ~5,500 untouched.
    robocopy $Master $dest /E /MT:32 /R:2 /W:5 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Fail "robocopy failed building shard $s (exit $LASTEXITCODE)" }
    Write-Host " ok" -ForegroundColor Green
}

if ($Setup) {
    Write-Host ""
    Write-Host "setup done. Now run without -Setup." -ForegroundColor Cyan
    exit 0
}

# ------------------------------------------------------------- what to bake --
Step "work out what is out of date"

$stamp  = Get-Date -Format "yyyyMMdd-HHmmss"
$RunDir = "$Game\art_work\out\_run\$stamp"
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

$baseList   = "$RunDir\base.txt"
$playerList = "$RunDir\player.txt"

# Both lists must be computed with the SAME flags, or a run rebakes a base
# recipe and leaves its eight colour variants behind at the old code -- which is
# precisely the non-uniform build id the game side's staleness rule reports.
$staleArgs = @()
if ($PipelineStale) { $staleArgs += "--isobake" }
if ($Directions)    { $staleArgs += @("--directions", $Directions) }
if ($staleArgs.Count) { Write-Host ("  selecting with: {0}" -f ($staleArgs -join " ")) -ForegroundColor DarkGray }

Push-Location $Repo
$baseNames   = @(& $Python "tools\stale_recipes.py" --names @staleArgs)
$playerNames = @(& $Python "tools\stale_recipes.py" --player --names @staleArgs)
Pop-Location

# .NET, not Set-Content -Encoding utf8: PS 5.1 writes a BOM, and bake_batch reads
# this file line by line -- a BOM would corrupt the FIRST recipe name only, which
# is the kind of off-by-one that looks like a missing recipe rather than a bug.
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllLines($baseList,   $baseNames,   $utf8)
[IO.File]::WriteAllLines($playerList, $playerNames, $utf8)

Write-Host ("  base recipes  : {0}" -f $baseNames.Count)
Write-Host ("  colour variants: {0}" -f $playerNames.Count)
Write-Host ("  total          : {0} bakes" -f ($baseNames.Count + $playerNames.Count))
Write-Host ("  lists written to {0}" -f $RunDir) -ForegroundColor DarkGray

# Warn whenever the pipeline dimension was not asked for, NOT only when the
# selection came out empty. A partial selection is the more dangerous case: on
# 2026-08-27 this ran without -PipelineStale, found the 4 recipes that happened
# to have been edited that day, baked them, and reported a successful run -- while
# leaving 240 mirrored atlases untouched. A zero would at least have looked odd.
if (-not $PipelineStale) {
    Write-Host ""
    Write-Host "  NOTE: this selection is recipe-hash only. It says NOTHING about whether the" -ForegroundColor Yellow
    Write-Host "  isobake code that baked an atlas has changed since. If you are here because" -ForegroundColor Yellow
    Write-Host "  the PIPELINE changed, stop and re-run with -PipelineStale (and -Directions" -ForegroundColor Yellow
    Write-Host "  to bound it) -- otherwise this run does only the recipes someone edited." -ForegroundColor Yellow
}

if (($baseNames.Count + $playerNames.Count) -eq 0) {
    Write-Host ""
    Write-Host "nothing is out of date. Done." -ForegroundColor Green
    exit 0
}

if ($WhatIf) {
    Write-Host ""
    Write-Host "base:"   -ForegroundColor DarkGray; $baseNames   | ForEach-Object { "    $_" }
    Write-Host "colour:" -ForegroundColor DarkGray; $playerNames | ForEach-Object { "    $_" }
    Write-Host ""
    Write-Host "WhatIf: nothing launched."
    exit 0
}

# ------------------------------------------------------------------- bake ----
$runStart = Get-Date

if ($baseNames.Count) {
    Step "bake $($baseNames.Count) base recipes, $Parallel-wide"
    & (Join-Path $Tools "bake_batch.ps1") -RecipeList $baseList -Parallel $Parallel -ShardRoot $ShardRoot
}

if ($playerNames.Count) {
    Step "bake $($playerNames.Count) colour variants, $Parallel-wide"
    # Sharded, so this is safe at width. Unsharded it would be the worst case in
    # the whole pipeline: all eight colours of a unit load an IDENTICAL mesh set.
    & (Join-Path $Tools "bake_batch.ps1") -RecipeDir "recipes\player" -RecipeList $playerList -Parallel $Parallel -ShardRoot $ShardRoot
}

# ------------------------------------------------------------------ verify ---
Step "verify"

# The invariant that catches a short bake and nothing else does: a unit's eight
# colours differ only in tint, so their opaque pixel counts must be equal. Read
# the header of check_colour_consistency.py before trusting a run of it -- the
# reference is the MAXIMUM over the colours, not the base bake, because the base
# is usually older and made by different code.
Push-Location $Repo
& $Python "tools\check_colour_consistency.py" --pixels
$colourOk = ($LASTEXITCODE -eq 0)
Pop-Location
if (-not $colourOk) { Write-Host "  colour consistency reported problems" -ForegroundColor Yellow }

# The master should be untouched -- nothing baked against it. Checking anyway:
# if this ever reports dirt, a slot was NOT reading its shard, and every atlas in
# the run is suspect.
Step "confirm the master art checkout was never written"
& (Join-Path $Tools "restore_art_sources.ps1") -Quiet
if ($LASTEXITCODE -ne 0) {
    Write-Host "  MASTER IS DIRTY -- sharding did not hold. Treat this run as suspect." -ForegroundColor Red
}

# ------------------------------------------------------------------- stage ---
if ($NoStage) {
    Step "staging skipped (-NoStage)"
    Write-Host "  when ready:  python tools\stage_atlases.py"
} elseif (-not $colourOk) {
    Step "staging SKIPPED -- colour consistency failed"
    Write-Host "  Fix or accept the shortfalls first, then: python tools\stage_atlases.py" -ForegroundColor Yellow
} else {
    Step "stage"
    Push-Location $Repo
    & $Python "tools\stage_atlases.py"
    Pop-Location
}

$elapsed = (Get-Date) - $runStart
Write-Host ""
Write-Host ("run finished in {0:n1} h" -f $elapsed.TotalHours) -ForegroundColor Cyan
Write-Host "  batch logs and lists: $RunDir"
Write-Host ""
Write-Host "Tell the game side: the yaw_offset_deg batch has landed, re-run" -ForegroundColor DarkCyan
Write-Host "  preview_facing_chart -- --units unit.swordsman,unit.knight" -ForegroundColor DarkCyan
Write-Host "column 0 (S) must show a FACE and column 4 (N) a BACK." -ForegroundColor DarkCyan
