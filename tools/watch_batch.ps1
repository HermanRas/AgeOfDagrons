<#
.SYNOPSIS
  Watch a bake batch that is already running. Read-only; safe at any time.

.DESCRIPTION
  Run this in a SECOND shell while render_box_bake.ps1 works. It touches nothing
  -- it reads the newest batch log directory and the Blender processes.

  WHY YOU CANNOT JUST READ THE LOGS. isobake's console output is REDIRECTED into
  each recipe's log, and that redirect BUFFERS. A log that is empty, or that
  stops growing for several minutes, does not mean the bake died -- it usually
  means Blender is mid-render and has not flushed. The reliable liveness signal
  is a blender.exe burning CPU, which is why that is reported here alongside the
  log counts rather than instead of them.

  "done" counts logs carrying the line isobake prints when it has packed an
  atlas. A log without it is either still rendering or has failed; the two are
  told apart by whether Blender is still running, not by the log.

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

# The finished-bake marker, matching what bake_batch.ps1 itself greps for.
$DONE = "bake \S+: \d+ frames -> \d+ page"

while ($true) {
    $batch = Get-ChildItem $BatchDir -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $batch) { throw "no batches yet" }

    $logs  = @(Get-ChildItem $batch.FullName -Filter "*.log" -ErrorAction SilentlyContinue)
    $done  = @(); $busy = @()
    foreach ($l in $logs) {
        $text = ""
        try { $text = [IO.File]::ReadAllText($l.FullName) } catch { }
        if ($text -match $DONE) { $done += $l.BaseName } else { $busy += $l.BaseName }
    }

    $blender = @(Get-Process blender -ErrorAction SilentlyContinue)
    $ram = if ($blender) { ($blender | Measure-Object WorkingSet64 -Sum).Sum / 1GB } else { 0 }
    $started = $batch.CreationTime
    $elapsed = (Get-Date) - $started

    $expect = $Total
    if ($expect -le 0) {
        $summary = Join-Path $batch.FullName "_summary.csv"
        if (Test-Path $summary) { $expect = @(Import-Csv $summary).Count } else { $expect = $logs.Count }
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
        $recent = $logs | Where-Object { $done -contains $_.BaseName } |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 5
        Write-Host ""
        Write-Host "  most recently finished:" -ForegroundColor DarkGray
        foreach ($r in $recent) { Write-Host ("    {0,-28} {1:HH:mm:ss}" -f $r.BaseName, $r.LastWriteTime) }
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
