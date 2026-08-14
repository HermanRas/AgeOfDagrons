<#
.SYNOPSIS
  Build (render + bake) many isobake recipes unattended, then report.

.DESCRIPTION
  Written for an overnight run. Every recipe is independent, so one failure must
  never stop the batch -- a wrong actor path or a too-small canvas should cost
  that one asset and nothing else. Each recipe gets its own log, and the summary
  at the end is the thing to read in the morning.

  Recipes run in PRIORITY ORDER, not alphabetically, because an overnight run
  may not finish: the batch is ordered so that whatever did complete is the most
  useful subset. The order lives in $Priority below.

  Also runs `isobake verify` per successful build, which writes the contact sheet
  with anchor crosshairs plus a turntable -- that is what you actually look at to
  judge a bake, so it is not optional here.

.PARAMETER Only
  Substring filter on recipe id/filename. Runs just the matches.

.PARAMETER SkipVerify
  Build but do not write contact sheets. Faster; leaves nothing to look at.

.PARAMETER WhatIf
  Print the plan and exit without launching Blender.

.NOTES
  Baking rewrites source .dae files in the 0 A.D. checkout in place (the
  Pyrogenesis importer's doing). isobake restores them via preserve_sources(),
  including on failure -- but NOT if the process is killed. If this run is
  interrupted, check `git -C <art_source> status` before trusting the checkout.
#>

[CmdletBinding()]
param(
    [string] $Only,
    [switch] $SkipVerify,
    [switch] $WhatIf
)

$ErrorActionPreference = "Continue"

$ToolsDir = $PSScriptRoot
$RecipeDir = Join-Path $ToolsDir "recipes"
$Isobake = "C:\Users\herman.ras\Downloads\AOD_game\tools_env\venv\Scripts\isobake.exe"

if (-not (Test-Path $Isobake)) { throw "isobake not found at $Isobake" }
if (-not (Test-Path $RecipeDir)) { throw "recipes not found at $RecipeDir" }

# Highest value first. Anything not listed runs afterwards in alphabetical order,
# so adding a recipe never silently drops it from the batch.
$Priority = @(
    # Age 1 is the first shippable settlement (PLAN.md A.10) -- five buildings,
    # re-pointed to Briton actors. Highest value in the batch.
    "town_center", "house", "mill", "lumber_camp", "mining_camp",
    # Units re-pointed to Celtic actors (PLAN.md 2.7): proven recipes, new actors.
    "villager", "militia", "spearman", "archer", "monk",
    # New capability from the nested-prop clip fix (2026-08-14): mounted units.
    "scout_cavalry", "sword_cavalry", "cavalry_archer",
    # Composite units the same fix unblocked, previously un-bakeable.
    "trebuchet_deployed", "trade_cart",
    # New Celtic units with no prior recipe.
    "swordsman", "elite_swordsman", "crossbowman",
    "galley", "fishing_ship", "transport_ship"
)

$all = Get-ChildItem $RecipeDir -Filter "*.toml" | Select-Object -ExpandProperty BaseName
if ($Only) { $all = $all | Where-Object { $_ -like "*$Only*" } }

$ordered = @()
foreach ($name in $Priority) { if ($all -contains $name) { $ordered += $name } }
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
Write-Host "  $($ordered.Count) recipe(s), logs -> $LogDir"
Write-Host ""

if ($WhatIf) {
    $i = 0
    foreach ($name in $ordered) { $i++; "  {0,3}. {1}" -f $i, $name }
    Write-Host ""
    Write-Host "WhatIf: nothing launched."
    exit 0
}

$results = @()
$batchStart = Get-Date
$i = 0

foreach ($name in $ordered) {
    $i++
    $recipe = Join-Path $RecipeDir "$name.toml"
    $log = Join-Path $LogDir "$name.log"
    $started = Get-Date

    Write-Host ("[{0,3}/{1}] {2} ..." -f $i, $ordered.Count, $name) -NoNewline

    # stderr folded into stdout on purpose: Blender writes progress there, and a
    # split log is unreadable when the interesting line is a warning.
    & $Isobake build $recipe *> $log
    $ok = ($LASTEXITCODE -eq 0)

    $text = ""
    if (Test-Path $log) { $text = (Get-Content $log -Raw) }

    # The things worth knowing without opening the log. A re-pointed recipe can
    # succeed while quietly losing an animation -- the new actor may not declare a
    # clip the old one did -- so "declares no animation" and a frozen nested prop
    # count as warnings, not as success.
    $warn = "canvas|too small|exceeds|declares no animation|rest pose"
    $clipped = ($text -match $warn)
    $frames = ""
    $m = [regex]::Match($text, "bake \S+: (\d+) frames -> (\d+) page")
    if ($m.Success) { $frames = "$($m.Groups[1].Value)f/$($m.Groups[2].Value)p" }
    $fill = ""
    $m2 = [regex]::Match($text, "([\d.]+)% filled")
    if ($m2.Success) { $fill = "$($m2.Groups[1].Value)%" }

    $elapsed = (Get-Date) - $started

    # `verify` takes a bake OUTPUT DIRECTORY, not a recipe -- passing the recipe
    # makes it try to parse the .toml as JSON and die. The directory is named for
    # the recipe's id, which is the one thing that has to be read out of the file.
    if ($ok -and -not $SkipVerify) {
        $idMatch = [regex]::Match((Get-Content $recipe -Raw), '(?m)^\s*id\s*=\s*"([^"]+)"')
        if ($idMatch.Success) {
            $bakeDir = Join-Path $OutRoot $idMatch.Groups[1].Value
            if (Test-Path $bakeDir) { & $Isobake verify $bakeDir *>> $log }
        }
    }

    $status = "FAIL"
    $colour = "Red"
    if ($ok -and $clipped) { $status = "CLIPPED"; $colour = "Yellow" }
    elseif ($ok) { $status = "ok"; $colour = "Green" }

    Write-Host ("`r[{0,3}/{1}] {2,-24} {3,-8} {4,-10} {5,-6} {6,5:n1}m" -f `
        $i, $ordered.Count, $name, $status, $frames, $fill, $elapsed.TotalMinutes) -ForegroundColor $colour

    $results += [pscustomobject]@{
        Recipe  = $name
        Status  = $status
        Frames  = $frames
        Fill    = $fill
        Minutes = [math]::Round($elapsed.TotalMinutes, 1)
        Log     = $log
    }
}

$summary = Join-Path $LogDir "_summary.csv"
$results | Export-Csv -Path $summary -NoTypeInformation -Encoding UTF8

$total = (Get-Date) - $batchStart
Write-Host ""
Write-Host ("done in {0:n1} min" -f $total.TotalMinutes) -ForegroundColor Cyan
$results | Group-Object Status | ForEach-Object { "  {0,-8} {1}" -f $_.Name, $_.Count }
Write-Host ""
Write-Host "summary: $summary"

$bad = $results | Where-Object { $_.Status -ne "ok" }
if ($bad) {
    Write-Host ""
    Write-Host "needs attention:" -ForegroundColor Yellow
    $bad | ForEach-Object { "  {0,-24} {1,-8} {2}" -f $_.Recipe, $_.Status, $_.Log }
}
