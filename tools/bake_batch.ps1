<#
.SYNOPSIS
  Build (render + bake) many isobake recipes unattended, then report.

.DESCRIPTION
  Written for an overnight run. Every recipe is independent, so one failure must
  never stop the batch -- a wrong actor path or a too-small canvas should cost
  that one asset and nothing else. Each recipe gets its own log, and the summary
  at the end is the thing to read in the morning.

  Recipes run in PRIORITY ORDER, not alphabetically, because a long run may not
  finish: the batch is ordered so that whatever did complete is the most useful
  subset. The order lives in $Priority below.

  Also runs `isobake verify` per successful build, which writes the contact sheet
  with anchor crosshairs plus a turntable -- that is what you actually look at to
  judge a bake, so it is not optional here.

.PARAMETER Only
  Substring filter(s) on recipe name. Accepts a list or a comma-separated string.

.PARAMETER Except
  Substring filter(s) to EXCLUDE, same format as -Only, applied after it. This is
  the filter a full re-bake actually needs: the useful run is nearly always
  "everything except the handful that are known broken or waiting on a decision",
  and expressing that through -Only means listing eighty names.

.PARAMETER Parallel
  How many recipes to build at once. Each is its own Blender process.

.PARAMETER SkipVerify
  Build but do not write contact sheets. Faster; leaves nothing to look at.

.PARAMETER WhatIf
  Print the plan and exit without launching Blender.

.NOTES
  Baking rewrites source .dae files in the 0 A.D. checkout in place (the
  Pyrogenesis importer's doing). isobake restores them via preserve_sources(),
  including on failure -- but NOT if the process is killed. If a run is
  interrupted, check the checkout before trusting it.

  That restore is also the one piece of shared state between parallel slots, and
  the race is NOT hypothetical -- "concurrent recipes are different actors" was
  the reasoning here until 2026-08-17, and it is wrong: different actors share
  meshes. A slot reading a .dae while another rewrites it silently imports fewer
  objects and still reports ok. It cost three of vis.archer's eight colours 5-6%
  of their pixels, and one of onager__blue's three crew.

  -ShardRoot removes the shared state entirely by giving each slot its own art
  checkout. Use it for anything above -Parallel 1, and ALWAYS for colour
  variants, where all eight of a unit's bakes load an identical mesh set and so
  collide on every file.
#>

[CmdletBinding()]
param(
    [string[]] $Only,
    [string[]] $Except,
    [switch]   $SkipVerify,
    [switch]   $WhatIf,
    # 2, set by the project owner 2026-08-15 after watching a 4-wide run: 4 is
    # technically fine -- it completed 81 recipes -- but it saturates the machine
    # and makes it unpleasant to use while a batch is going. The ceiling is RAM
    # (every slot holds a full Blender scene); the LIMIT is that this is somebody's
    # workstation, not a render farm. Raise it explicitly with -Parallel if the
    # machine is free.
    [int]      $Parallel = 2,

    # Where to read recipes from, relative to tools/ (or absolute). Defaults to
    # recipes/. The player-colour variants live in recipes/player/ so that this
    # script's non-recursive glob does not pull 112 generated files into every
    # ordinary batch; point at them with -RecipeDir recipes/player.
    [string]   $RecipeDir,

    # A file of recipe names, one per line, as an exact set rather than a
    # substring filter. This is what `python tools/stale_recipes.py --names`
    # writes, so a batch can be "bake exactly what is out of date" without
    # anyone maintaining the list by hand. Blank lines and #-comments ignored.
    #
    # Exact, not substring, on purpose: -Only "galley" also matches "galleon",
    # and an 89-name -Only string is both unreadable and quietly wrong.
    [string]   $RecipeList,

    # ONE ART CHECKOUT PER PARALLEL SLOT. Point this at a directory holding
    # slot1\public, slot2\public, ... and each Blender process gets its own copy
    # of the 0 A.D. art via $ISOBAKE_ART_SOURCE.
    #
    # WHY IT EXISTS. The Pyrogenesis importer rewrites every .dae it loads, in
    # place. isobake undoes that per bake, but the restore is the one piece of
    # state SHARED between parallel slots -- and cavalry, infantry and every
    # colour variant of one unit all pull the SAME horse_celtic.dae and
    # m_armor_tunic_short.dae. Two slots reading and rewriting one file do not
    # merely leave it dirty: the reader SILENTLY IMPORTS FEWER OBJECTS. That is
    # what left onager__blue with 5 armatures against red's 7, and what left
    # vis.archer short by 4.9-6.4% in three of its eight colours. Every one of
    # those bakes reported `ok`.
    #
    # Sharding removes the shared state instead of avoiding it, so the race
    # cannot happen at any width. It also means the MASTER checkout is never
    # written by a bake at all, which is what restore_art_sources.* exists to
    # repair -- a sharded run needs no restore, only a shard refresh.
    #
    # Costs one full copy of binaries/data/mods/public (5.7 GB) per slot.
    [string]   $ShardRoot
)

$ErrorActionPreference = "Continue"

$ToolsDir  = $PSScriptRoot
if (-not $RecipeDir)                 { $RecipeDir = Join-Path $ToolsDir "recipes" }
elseif (-not [IO.Path]::IsPathRooted($RecipeDir)) { $RecipeDir = Join-Path $ToolsDir $RecipeDir }
$Isobake   = "C:\Users\herman.ras\Downloads\AOD_game\tools_env\venv\Scripts\isobake.exe"

if (-not (Test-Path $Isobake))   { throw "isobake not found at $Isobake" }
if (-not (Test-Path $RecipeDir)) { throw "recipes not found at $RecipeDir" }

# Fail here rather than three hours in. A missing shard would not error -- the
# slot would silently fall back to the shared checkout from isobake.local.toml
# and re-open the very race the shards exist to close, while still reporting ok.
$ShardPath = @{}
if ($ShardRoot) {
    for ($s = 1; $s -le $Parallel; $s++) {
        $p = Join-Path $ShardRoot "slot$s\public"
        if (-not (Test-Path (Join-Path $p "art"))) {
            throw "shard $s incomplete: expected an art\ directory under $p (run render_box_bake.ps1 -Setup)"
        }
        $ShardPath[$s] = $p
    }
    Write-Host ("  sharded: {0} art checkouts under {1}" -f $Parallel, $ShardRoot) -ForegroundColor DarkCyan
}

# Highest value first. Anything not listed runs afterwards in alphabetical order,
# so adding a recipe never silently drops it from the batch.
$Priority = @(
    # Age 1 is the first shippable settlement (PLAN.md A.10) -- five buildings.
    "town_center", "house", "mill", "lumber_camp", "mining_camp",
    # Units, which carry the roster's hand-picked actors.
    "villager", "militia", "spearman", "archer", "monk",
    # Mounted units, bakeable since the composite-unit fixes.
    "scout_cavalry", "sword_cavalry", "cavalry_archer", "knight",
    # Composite units the same fixes unblocked, previously un-bakeable.
    "trebuchet_deployed", "trade_cart",
    "swordsman", "elite_swordsman", "crossbowman",
    "galley", "fishing_ship", "transport_ship"
)

$all = Get-ChildItem $RecipeDir -Filter "*.toml" | Select-Object -ExpandProperty BaseName

if ($RecipeList) {
    if (-not (Test-Path $RecipeList)) { throw "recipe list not found: $RecipeList" }
    $wanted = Get-Content $RecipeList |
        ForEach-Object { ($_ -split '#')[0].Trim() } |
        Where-Object { $_ }
    # A name in the list with no recipe on disk is a typo or a deleted recipe,
    # and silently baking 88 of 89 is exactly the kind of near-miss that reads as
    # success in the morning.
    $absent = @($wanted | Where-Object { $all -notcontains $_ })
    if ($absent) { throw "recipe list names $($absent.Count) recipe(s) not in ${RecipeDir}: $($absent -join ', ')" }
    $all = $all | Where-Object { $wanted -contains $_ }
    Write-Host ("  -RecipeList selected {0} recipe(s) from {1}" -f @($all).Count, (Split-Path $RecipeList -Leaf)) -ForegroundColor DarkGray
}

if ($Only) {
    # Split on commas too: -File passes `-Only a,b,c` through as a single string
    # rather than as an array.
    $patterns = @($Only) -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    $all = $all | Where-Object {
        $name = $_
        ($patterns | ForEach-Object { $name -like "*$_*" }) -contains $true
    }
}

if ($Except) {
    $skip = @($Except) -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    $before = @($all).Count
    $all = $all | Where-Object {
        $name = $_
        -not (($skip | ForEach-Object { $name -like "*$_*" }) -contains $true)
    }
    Write-Host ("  -Except dropped {0} recipe(s)" -f ($before - @($all).Count)) -ForegroundColor DarkGray
}

$ordered = @()
foreach ($name in $Priority) {
    if ($all -contains $name) { $ordered += $name }
    # Player-colour variants are "<recipe>__<colour>", so an exact match alone
    # would leave all 112 of them to the alphabetical fallback and bake the
    # roster's least important unit first. Sorted, so an interrupted run has
    # finished whole units rather than a scatter.
    foreach ($variant in ($all | Sort-Object)) {
        if ($variant -like "$name`__*" -and $ordered -notcontains $variant) { $ordered += $variant }
    }
}
foreach ($name in ($all | Sort-Object)) { if ($ordered -notcontains $name) { $ordered += $name } }

if ($ordered.Count -eq 0) { throw "no recipes matched" }

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"

# Logs go beside the atlases, so a batch's output and its explanation stay
# together. The out root is read from the same place isobake reads it -- deriving
# it by walking up from tools/ was wrong and silently wrote logs into Drive.
$OutRoot = $env:ISOBAKE_OUT
if (-not $OutRoot) {
    $localCfg = Join-Path $ToolsDir "isobake.local.toml"
    if (Test-Path $localCfg) {
        $m = [regex]::Match((Get-Content $localCfg -Raw), '(?m)^\s*out\s*=\s*"([^"]+)"')
        if ($m.Success) { $OutRoot = $m.Groups[1].Value }
    }
}
if (-not $OutRoot) { throw "cannot find paths.out -- set ISOBAKE_OUT or tools/isobake.local.toml" }

$LogDir = Join-Path $OutRoot "_batch\$stamp"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

Write-Host ""
Write-Host "isobake batch $stamp" -ForegroundColor Cyan
Write-Host "  $($ordered.Count) recipe(s), $Parallel at a time, logs -> $LogDir"
Write-Host ""

if ($WhatIf) {
    $n = 0
    foreach ($name in $ordered) { $n++; "  {0,3}. {1}" -f $n, $name }
    Write-Host ""
    Write-Host "WhatIf: nothing launched."
    exit 0
}

# One job per recipe: build, then verify. Jobs rather than Start-Process because a
# job carries its own exit status and output back without a temp file dance, and
# the per-job overhead is irrelevant against a multi-minute Blender run.
$work = {
    param($Isobake, $Recipe, $Log, $OutRoot, $SkipVerify, $WorkDir, $ArtSource)

    # A job starts in a FRESH runspace whose working directory is the user's
    # Documents folder, not this script's. isobake finds isobake.toml by walking up
    # from the CWD, so without this every job dies with "no isobake.toml found".
    Set-Location $WorkDir

    # This slot's private art checkout. The env var overrides paths.art_source
    # from isobake.local.toml, and a fresh runspace means it cannot leak between
    # slots. Unset when not sharding, so the shared checkout is used as before.
    if ($ArtSource) { $env:ISOBAKE_ART_SOURCE = $ArtSource }

    # stderr folded into stdout on purpose: Blender writes progress there, and a
    # split log is unreadable when the interesting line is a warning.
    & $Isobake build $Recipe *> $Log
    $code = $LASTEXITCODE

    # `verify` takes a bake OUTPUT DIRECTORY, not a recipe -- passing the recipe
    # makes it parse the .toml as JSON and die. The directory is named for the
    # recipe's id, which is the one thing to read out of the file.
    if ($code -eq 0 -and -not $SkipVerify) {
        $idMatch = [regex]::Match((Get-Content $Recipe -Raw), '(?m)^\s*id\s*=\s*"([^"]+)"')
        if ($idMatch.Success) {
            $bakeDir = Join-Path $OutRoot $idMatch.Groups[1].Value
            if (Test-Path $bakeDir) { & $Isobake verify $bakeDir *>> $Log }
        }
    }
    return $code
}

$queue = New-Object System.Collections.Queue
foreach ($name in $ordered) { $queue.Enqueue($name) | Out-Null }

$results    = @()
$batchStart = Get-Date
$running    = @{}
$done       = 0
$total      = $ordered.Count

# Slot numbers are handed out and given back, so at most one job ever holds a
# given shard. Without this a recipe could be assigned a shard another slot is
# still writing to, which is the race again wearing a different hat.
$freeSlots = New-Object System.Collections.Stack
for ($s = $Parallel; $s -ge 1; $s--) { $freeSlots.Push($s) }

while ($queue.Count -gt 0 -or $running.Count -gt 0) {

    while ($running.Count -lt $Parallel -and $queue.Count -gt 0 -and $freeSlots.Count -gt 0) {
        $name = $queue.Dequeue()
        $slotNo = $freeSlots.Pop()
        $recipe = Join-Path $RecipeDir "$name.toml"
        $log = Join-Path $LogDir "$name.log"
        $art = if ($ShardRoot) { $ShardPath[$slotNo] } else { $null }
        $job = Start-Job -ScriptBlock $work `
            -ArgumentList $Isobake, $recipe, $log, $OutRoot, [bool]$SkipVerify, $ToolsDir, $art
        $running[$name] = @{ Job = $job; Log = $log; Started = (Get-Date); Slot = $slotNo }
    }

    Start-Sleep -Milliseconds 700

    foreach ($name in @($running.Keys)) {
        $slot = $running[$name]
        if ($slot.Job.State -eq "Running") { continue }

        $code = Receive-Job $slot.Job -ErrorAction SilentlyContinue | Select-Object -Last 1
        Remove-Job $slot.Job -Force -ErrorAction SilentlyContinue
        $running.Remove($name)
        $freeSlots.Push($slot.Slot)
        $done++

        $text = ""
        if (Test-Path $slot.Log) { $text = (Get-Content $slot.Log -Raw) }

        # Two different problems, kept apart on purpose -- they were one status
        # until 2026-08-15 and it made the summary useless.
        #
        # CLIPPED means the canvas lost content: real, always actionable, raise
        # the canvas and rebake.
        $clipped = ($text -match "canvas is too small|exceeds")

        # WARN means something worth a look that is often fine. A re-pointed
        # recipe can succeed while quietly losing an animation the new actor does
        # not declare, so a missing NAMED clip belongs here.
        #
        # `rest pose` is the noisiest member and cannot simply be dropped, because
        # it covers two opposite cases:
        #   - EXPECTED. A weapon prop that only declares attack clips is in rest
        #     pose for every other clip, which is correct -- an archer's bow is not
        #     drawn while walking. vis.archer warns on Idle/Walk/Death for exactly
        #     this reason and is perfectly fine.
        #   - A REAL DEFECT. A nested FIGURE in rest pose is broken: that is the
        #     bug that made the knight's rider stand upright on his horse instead
        #     of sitting (knight.toml).
        # Both emit the same note, so the distinction is "is the prop a weapon or a
        # person", which the note does not say. Left as WARN rather than guessed at.
        #
        # Not warned on: the unnamed clip. Every static recipe has no [anims]
        # block, which the adapter reports as `declares no animation named ''`;
        # treating that as a problem flagged 8 of 10 "failures" in the first
        # overnight run when only 2 were real. A warning that cries wolf trains you
        # to skim the list -- and then a real one goes past unread.
        $warned = ($text -match "rest pose|declares no animation named '[^']")

        $frames = ""
        $m = [regex]::Match($text, "bake \S+: (\d+) frames -> (\d+) page")
        if ($m.Success) { $frames = "$($m.Groups[1].Value)f/$($m.Groups[2].Value)p" }
        $fill = ""
        $m2 = [regex]::Match($text, "([\d.]+)% filled")
        if ($m2.Success) { $fill = "$($m2.Groups[1].Value)%" }

        $ok = ($code -eq 0)
        $status = "FAIL"; $colour = "Red"
        if     ($ok -and $clipped) { $status = "CLIPPED"; $colour = "Yellow" }
        elseif ($ok -and $warned)  { $status = "WARN";    $colour = "DarkYellow" }
        elseif ($ok)               { $status = "ok";      $colour = "Green" }

        $elapsed = (Get-Date) - $slot.Started
        Write-Host ("[{0,3}/{1}] {2,-24} {3,-8} {4,-10} {5,-6} {6,5:n1}m" -f `
            $done, $total, $name, $status, $frames, $fill, $elapsed.TotalMinutes) -ForegroundColor $colour

        $results += [pscustomobject]@{
            Recipe  = $name
            Status  = $status
            Frames  = $frames
            Fill    = $fill
            Minutes = [math]::Round($elapsed.TotalMinutes, 1)
            # Which shard ran it. Recorded so that if a bake ever does come out
            # short again, the summary says whether one slot is implicated --
            # a shard with a corrupt mesh would otherwise look like random damage.
            Slot    = $slot.Slot
            Log     = $slot.Log
        }
    }
}

$summary = Join-Path $LogDir "_summary.csv"
$results | Sort-Object Recipe | Export-Csv -Path $summary -NoTypeInformation -Encoding UTF8

$totalTime = (Get-Date) - $batchStart
Write-Host ""
Write-Host ("done in {0:n1} min" -f $totalTime.TotalMinutes) -ForegroundColor Cyan
$results | Group-Object Status | ForEach-Object { "  {0,-8} {1}" -f $_.Name, $_.Count }
Write-Host ""
Write-Host "summary: $summary"

$bad = $results | Where-Object { $_.Status -ne "ok" }
if ($bad) {
    Write-Host ""
    Write-Host "needs attention:" -ForegroundColor Yellow
    $bad | ForEach-Object { "  {0,-24} {1,-8} {2}" -f $_.Recipe, $_.Status, $_.Log }
}
