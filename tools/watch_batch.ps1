<#
.SYNOPSIS
  Watch a bake batch that is already running. Read-only; safe at any time.

.DESCRIPTION
  Run this in a SECOND shell while render_box_bake.ps1 works. It touches nothing
  -- it reads the newest batch log directory and the Blender processes.

  WHY IT DOES NOT COUNT PROGRESS FROM THE LOGS, which was this script's first
  design and was wrong within two minutes of its first real run. isobake's
  console output is REDIRECTED into each recipe's log, and that redirect BUFFERS:
  four bakes into a healthy batch, all four logs were still 0 bytes. Grepping
  them for a completion marker reported one recipe finished one second after the
  batch started, while the bake output directory showed nothing had finished at
  all.

  So completion is read from the ARTEFACT instead: a recipe is done when
  out\<its id>\atlas.json has been written since the batch began. That cannot be
  faked by buffering, it is what the bake exists to produce, and it stays correct
  for a rebake of an atlas that already existed.

  Liveness is still a blender.exe burning CPU. A log that is not growing means
  nothing either way, so the logs are used only for detail after a failure.

.PARAMETER Seconds
  Refresh interval. 0 prints one snapshot and exits -- use that from a phone or
  over SSH, where a repainting screen is a nuisance.

.PARAMETER Total
  Expected recipe count, for the percentage. Defaults to reading it from the
  run's own list files if they can be found.
#>

[CmdletBinding()]
param(
    [int] $Seconds = 60,
    [int] $Total = 0
)

$OutRoot  = "C:\Users\herman.ras\Downloads\AOD_game\art_work\out"
$BatchDir = "$OutRoot\_batch"

if (-not (Test-Path $BatchDir)) { throw "no batch directory at $BatchDir" }

# recipe name -> atlas id. The log is named for the recipe; the output directory
# is named for the recipe's `id`, and the two differ (swordsman -> vis.swordsman,
# and the colour variants more so). Read once: 331 small files.
$Repo = Split-Path $PSScriptRoot -Parent
$idOf = @{}
foreach ($dir in @("$Repo\tools\recipes", "$Repo\tools\recipes\player")) {
    if (-not (Test-Path $dir)) { continue }
    foreach ($f in Get-ChildItem $dir -Filter "*.toml") {
        $m = [regex]::Match([IO.File]::ReadAllText($f.FullName), '(?m)^\s*id\s*=\s*"([^"]+)"')
        if ($m.Success) { $idOf[$f.BaseName] = $m.Groups[1].Value }
    }
}

while ($true) {
    $batch = Get-ChildItem $BatchDir -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $batch) { throw "no batches yet" }

    $started = $batch.CreationTime
    $logs    = @(Get-ChildItem $batch.FullName -Filter "*.log" -ErrorAction SilentlyContinue)

    # Done means the ATLAS exists and postdates the batch. Not "the log says so":
    # the log is buffered and lies by omission for minutes at a time.
    $done = @(); $busy = @(); $doneAt = @{}
    foreach ($l in $logs) {
        $id = $idOf[$l.BaseName]
        $atlas = if ($id) { Join-Path $OutRoot "$id\atlas.json" } else { $null }
        if ($atlas -and (Test-Path $atlas) -and ((Get-Item $atlas).LastWriteTime -gt $started)) {
            $done += $l.BaseName
            $doneAt[$l.BaseName] = (Get-Item $atlas).LastWriteTime
        } else {
            $busy += $l.BaseName
        }
    }

    $blender = @(Get-Process blender -ErrorAction SilentlyContinue)
    $ram = if ($blender) { ($blender | Measure-Object WorkingSet64 -Sum).Sum / 1GB } else { 0 }
    $elapsed = (Get-Date) - $started

    # How many this batch will eventually run. bake_batch does not record it
    # until _summary.csv exists at the very end, so until then it is taken from
    # the list files render_box_bake wrote for the run -- choosing base or colour
    # by whether this batch's recipes are colour variants, which are the only
    # ones whose names carry the `__<colour>` suffix.
    $expect = $Total
    if ($expect -le 0) {
        $summary = Join-Path $batch.FullName "_summary.csv"
        if (Test-Path $summary) {
            $expect = @(Import-Csv $summary).Count
        } else {
            $expect = $logs.Count
            $run = Get-ChildItem "$OutRoot\_run" -Directory -ErrorAction SilentlyContinue |
                   Sort-Object Name -Descending | Select-Object -First 1
            if ($run) {
                $isColour = @($logs | Where-Object { $_.BaseName -like "*__*" }).Count -gt 0
                $listFile = Join-Path $run.FullName $(if ($isColour) { "player.txt" } else { "base.txt" })
                if (Test-Path $listFile) { $expect = @(Get-Content $listFile | Where-Object { $_.Trim() }).Count }
            }
        }
    }

    if ($Seconds -gt 0) { Clear-Host }
    Write-Host ""
    Write-Host "batch $($batch.Name)" -ForegroundColor Cyan
    Write-Host ("  elapsed   {0:hh\:mm\:ss}" -f $elapsed)
    Write-Host ("  done      {0} of {1} started{2}" -f $done.Count, $logs.Count,
        $(if ($expect -gt $logs.Count) { " (queue: $expect)" } else { "" }))
    Write-Host ("  in flight {0}  {1}" -f $busy.Count, ($busy -join ", ")) -ForegroundColor Yellow

    if ($blender.Count) {
        $cpu = ($blender | Measure-Object CPU -Sum).Sum
        Write-Host ("  blender   {0} process(es), {1:n1} GB, {2:n0}s CPU total" -f $blender.Count, $ram, $cpu) -ForegroundColor Green
    } else {
        # No Blender and unfinished logs is the one combination worth alarming on.
        if ($busy.Count) {
            Write-Host "  blender   NONE RUNNING while $($busy.Count) log(s) are unfinished -- batch has stopped" -ForegroundColor Red
        } else {
            Write-Host "  blender   none running" -ForegroundColor DarkGray
        }
    }

    if ($done.Count) {
        # Throughput measured over the whole batch, not per bake: the slots run
        # concurrently, so wall-clock divided by completions is the number that
        # actually predicts the finish.
        $perBake = $elapsed.TotalMinutes / $done.Count
        if ($expect -gt $done.Count) {
            $eta = [TimeSpan]::FromMinutes($perBake * ($expect - $done.Count))
            Write-Host ("  rate      {0:n1} min/bake overall -> about {1:hh\:mm} left, finishing ~{2:HH:mm}" -f `
                $perBake, $eta, ((Get-Date) + $eta)) -ForegroundColor DarkCyan
        }

        Write-Host ""
        Write-Host "  most recently finished:" -ForegroundColor DarkGray
        foreach ($r in ($doneAt.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5)) {
            Write-Host ("    {0,-28} {1:HH:mm:ss}" -f $r.Key, $r.Value)
        }
    }

    $summary = Join-Path $batch.FullName "_summary.csv"
    if (Test-Path $summary) {
        Write-Host ""
        Write-Host "  BATCH COMPLETE -- summary:" -ForegroundColor Cyan
        Import-Csv $summary | Group-Object Status | ForEach-Object {
            Write-Host ("    {0,-8} {1}" -f $_.Name, $_.Count)
        }
        $bad = Import-Csv $summary | Where-Object { $_.Status -ne "ok" }
        if ($bad) {
            Write-Host "  needs attention:" -ForegroundColor Yellow
            $bad | ForEach-Object { Write-Host ("    {0,-26} {1,-8} slot {2}" -f $_.Recipe, $_.Status, $_.Slot) }
        }
    }

    Write-Host ""
    if ($Seconds -le 0) { break }
    Start-Sleep -Seconds $Seconds
}
