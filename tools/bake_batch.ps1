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

  That restore is also the one piece of shared state between parallel slots. Two
  recipes that load the SAME .dae at the same time could race; in practice
  concurrent recipes are different actors, so keep it in mind rather than fear it.
#>

[CmdletBinding()]
param(
    [string[]] $Only,
    [string[]] $Except,
    [switch]   $SkipVerify,
    [switch]   $WhatIf,
    # 4 measured comfortable on this machine. The ceiling is RAM: every slot holds
    # a full Blender scene.
    [int]      $Parallel = 4
)

$ErrorActionPreference = "Continue"

$ToolsDir  = $PSScriptRoot
$RecipeDir = Join-Path $ToolsDir "recipes"
$Isobake   = "C:\Users\herman.ras\Downloads\AOD_game\tools_env\venv\Scripts\isobake.exe"

if (-not (Test-Path $Isobake))   { throw "isobake not found at $Isobake" }
if (-not (Test-Path $RecipeDir)) { throw "recipes not found at $RecipeDir" }

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
foreach ($name in $Priority)          { if ($all -contains $name)     { $ordered += $name } }
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
    param($Isobake, $Recipe, $Log, $OutRoot, $SkipVerify, $WorkDir)

    # A job starts in a FRESH runspace whose working directory is the user's
    # Documents folder, not this script's. isobake finds isobake.toml by walking up
    # from the CWD, so without this every job dies with "no isobake.toml found".
    Set-Location $WorkDir

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

while ($queue.Count -gt 0 -or $running.Count -gt 0) {

    while ($running.Count -lt $Parallel -and $queue.Count -gt 0) {
        $name = $queue.Dequeue()
        $recipe = Join-Path $RecipeDir "$name.toml"
        $log = Join-Path $LogDir "$name.log"
        $job = Start-Job -ScriptBlock $work `
            -ArgumentList $Isobake, $recipe, $log, $OutRoot, [bool]$SkipVerify, $ToolsDir
        $running[$name] = @{ Job = $job; Log = $log; Started = (Get-Date) }
    }

    Start-Sleep -Milliseconds 700

    foreach ($name in @($running.Keys)) {
        $slot = $running[$name]
        if ($slot.Job.State -eq "Running") { continue }

        $code = Receive-Job $slot.Job -ErrorAction SilentlyContinue | Select-Object -Last 1
        Remove-Job $slot.Job -Force -ErrorAction SilentlyContinue
        $running.Remove($name)
        $done++

        $text = ""
        if (Test-Path $slot.Log) { $text = (Get-Content $slot.Log -Raw) }

        # A re-pointed recipe can succeed while quietly losing an animation the new
        # actor does not declare, so a missing NAMED clip is a warning.
        #
        # But not the unnamed one. Every static recipe has no [anims] block, which
        # the adapter reports as `declares no animation named ''`; treating that as
        # a problem flagged 8 of 10 "failures" in the first overnight run when only
        # 2 were real. A warning that cries wolf trains you to skim the list.
        $warn = "canvas is too small|exceeds|rest pose|declares no animation named '[^']"
        $flagged = ($text -match $warn)

        $frames = ""
        $m = [regex]::Match($text, "bake \S+: (\d+) frames -> (\d+) page")
        if ($m.Success) { $frames = "$($m.Groups[1].Value)f/$($m.Groups[2].Value)p" }
        $fill = ""
        $m2 = [regex]::Match($text, "([\d.]+)% filled")
        if ($m2.Success) { $fill = "$($m2.Groups[1].Value)%" }

        $ok = ($code -eq 0)
        $status = "FAIL"; $colour = "Red"
        if ($ok -and $flagged) { $status = "CLIPPED"; $colour = "Yellow" }
        elseif ($ok)           { $status = "ok";      $colour = "Green" }

        $elapsed = (Get-Date) - $slot.Started
        Write-Host ("[{0,3}/{1}] {2,-24} {3,-8} {4,-10} {5,-6} {6,5:n1}m" -f `
            $done, $total, $name, $status, $frames, $fill, $elapsed.TotalMinutes) -ForegroundColor $colour

        $results += [pscustomobject]@{
            Recipe  = $name
            Status  = $status
            Frames  = $frames
            Fill    = $fill
            Minutes = [math]::Round($elapsed.TotalMinutes, 1)
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
