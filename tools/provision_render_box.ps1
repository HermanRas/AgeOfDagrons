<#
.SYNOPSIS
  Copy the bake toolchain from this workstation to the render box. Run HERE.

.DESCRIPTION
  Everything the pipeline needs lives in two places, and only one of them is
  synced by Google Drive:

    GoogleDrive\...\AOD_Mobile   the repo -- recipes, scripts, game/. SYNCED
                                already. Nothing to do, and nothing this script
                                should touch: writing into a Drive folder from
                                two machines is how conflict copies happen.

    Downloads\AOD_game           the toolchain -- art checkout, venv, Blender,
                                isobake source. NOT synced. This script.

  WHY THE PATHS MUST MATCH EXACTLY. The venv's base interpreter is Blender's own
  bundled python INSIDE this tree (see tools_env\venv\pyvenv.cfg), and the
  isobake editable install resolves through an absolute .pth. Both are recorded
  as C:\Users\herman.ras\Downloads\AOD_game\... , so copying to the identical
  path on a machine with the same username makes the venv work untouched -- and
  copying anywhere else silently breaks it. There is no relocation step here
  because there does not need to be one; it is luck, but it is checkable luck,
  and the script checks it.

  WHAT IS DELIBERATELY NOT COPIED:
    art_work\        9.1 GB of bake output and batch logs, all regenerated. Only
                     an empty art_work\out is needed.
    art_shards\      built ON the render box from its own local master -- see
                     render_box_bake.ps1. Copying 23 GB over the wire to save a
                     local NVMe copy would be a poor trade.

  MinGit IS copied, and it is easy to forget because it is not under AOD_game at
  all. isobake shells out to git for the atlas's isobake_commit / isobake_build /
  isobake_dirty stamp. Without git on the WINDOWS PATH -- WSL's git does not
  count, the Blender subprocess is a Windows process -- every atlas the render
  box bakes stamps null provenance, which is indistinguishable from nothing at a
  glance and is a permanent hole in the record.

.PARAMETER Target
  The render box's user profile over SMB.

.PARAMETER WhatIf
  Print the plan and the byte counts; copy nothing.

.PARAMETER SkipPristineCheck
  Skip verifying the art checkout before copying it. Do not.
#>

[CmdletBinding()]
param(
    [string] $Target = "\\100.96.0.1\Users\herman.ras",
    [switch] $WhatIf,
    [switch] $SkipPristineCheck
)

$ErrorActionPreference = "Stop"

$Local   = "C:\Users\herman.ras\Downloads\AOD_game"
$MinGit  = "C:\Users\herman.ras\AppData\Roaming\MinGit"
$Tools   = $PSScriptRoot

if (-not (Test-Path $Target)) { throw "render box not reachable: $Target" }

# The whole scheme rests on the destination path being identical to the source.
# If the remote profile is not herman.ras, the venv will not run there.
if ($Target -notmatch 'herman\.ras\\?$') {
    throw "target profile must be herman.ras for the venv's absolute paths to resolve; got $Target"
}

$jobs = @(
    @{ Name = "art_source";              From = "$Local\art_source";              To = "$Target\Downloads\AOD_game\art_source" }
    @{ Name = "tools_env";               From = "$Local\tools_env";               To = "$Target\Downloads\AOD_game\tools_env" }
    @{ Name = "blender_3d_to_2d_isobake";From = "$Local\blender_3d_to_2d_isobake";To = "$Target\Downloads\AOD_game\blender_3d_to_2d_isobake" }
    @{ Name = "MinGit";                  From = $MinGit;                          To = "$Target\AppData\Roaming\MinGit" }
)

foreach ($j in $jobs) { if (-not (Test-Path $j.From)) { throw "missing locally: $($j.From)" } }

Write-Host ""
Write-Host "provision render box -> $Target" -ForegroundColor Cyan
Write-Host ""

# THE CHECKOUT MUST BE PRISTINE BEFORE IT IS COPIED. A bake rewrites .dae files
# in place; copying a checkout that a killed or raced batch left dirty would
# reproduce that damage on the render box, where it would then be baked into
# every atlas the box produces and be indistinguishable from a source-art
# problem. -Force is not offered; run the restore instead.
if (-not $SkipPristineCheck) {
    Write-Host "verifying the art checkout is pristine before copying it..." -ForegroundColor DarkGray
    & (Join-Path $Tools "restore_art_sources.ps1") -Quiet
    if ($LASTEXITCODE -ne 0) { throw "art checkout is not clean -- run restore_art_sources.ps1 -Apply first" }
    Write-Host ""
}

foreach ($j in $jobs) {
    $size = (Get-ChildItem $j.From -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum)
    Write-Host ("{0,-26} {1,8:n0} files  {2,7:n2} GB" -f $j.Name, $size.Count, ($size.Sum / 1GB)) -ForegroundColor White
    Write-Host ("  -> {0}" -f $j.To) -ForegroundColor DarkGray

    if ($WhatIf) { continue }

    # /E all subdirs incl. empty, /MT parallel streams (SMB over Tailscale is
    # latency-bound, so threads help far more than they do locally). /R:2
    # because a hung retry loop overnight is worse than a reported failure.
    #
    # No /XO. Robocopy already skips files matching on size AND timestamp, so a
    # dropped 12 GB transfer resumes on its own; /XO would additionally skip any
    # file whose destination copy is NEWER, which is the one case where a re-run
    # actually needs to overwrite.
    robocopy $j.From $j.To /E /MT:24 /R:2 /W:5 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed for $($j.Name) (exit $LASTEXITCODE)" }
    Write-Host ("  done (robocopy {0})" -f $LASTEXITCODE) -ForegroundColor Green
}

if (-not $WhatIf) {
    New-Item -ItemType Directory -Force -Path "$Target\Downloads\AOD_game\art_work\out" | Out-Null
    Write-Host ""
    Write-Host "art_work\out created (empty -- bake output is not copied)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "next, ON the render box:" -ForegroundColor Cyan
Write-Host "  powershell -File <repo>\tools\render_box_bake.ps1 -Setup"
Write-Host ""
