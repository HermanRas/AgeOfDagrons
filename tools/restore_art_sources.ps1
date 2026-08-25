<#
.SYNOPSIS
  Restore 0 A.D. art sources that a bake rewrote in place. Windows-native.

.DESCRIPTION
  WHY THIS EXISTS ALONGSIDE restore_art_sources.sh. The bash version is exact and
  correct, but it forks `git show` once per mesh -- 5,525 forks across the
  WSL/Windows filesystem boundary -- which takes 30-45 minutes. This does the
  same comparison from Windows in about two minutes by reading every pointer out
  of ONE `git cat-file --batch` process. Both machines have WSL and git-lfs, so
  this is a speed tool, not a compatibility one; the bash script remains the
  reference implementation and either is safe to run.

  WHY IT IS SAFE, given that git-lfs is NOT installed on the Windows side. It
  never runs `git checkout`. A checkout would invoke the smudge filter -- absent
  on Windows -- and write a 136-byte LFS POINTER over 226 KB of real geometry,
  destroying the art. This reads the pointer TEXT with `git cat-file` (plumbing,
  which does no filtering) and copies the pristine bytes out of .git/lfs/objects
  by hand. No filter is involved at any point.

  THE COMPARISON IS EXACT, not a timestamp heuristic. An LFS pointer's `oid` IS
  the sha256 of the pristine content, so hashing the file on disk and comparing
  is a proof rather than a guess. The pristine bytes are already in
  .git/lfs/objects, so this needs no network.

  Restoring is a plain file copy, which deliberately leaves git's index alone:
  the checkout carries ~30k staged deletions from the LFS setup, and touching
  them is a separate problem and not this script's job.

  ---------------------------------------------------------------------------
  HOW THE FIRST VERSION OF THIS SCRIPT WAS WRONG, because the failure mode is
  worth knowing before writing anything else that pipes into a native command.

  It piped the path list into git with PowerShell's `|`. PowerShell 5.1 encodes
  that stream with a BOM, so git saw `<BOM>HEAD:...` for the FIRST line only and
  answered `missing`. That one lost record shifted the reply stream by one
  against the request list, and the results were then zipped back together BY
  POSITION -- so all 5,523 meshes were compared against their NEIGHBOUR's hash.

  The report was "5,517 of 5,525 modified", which reads exactly like a checkout
  badly in need of restoring. With -Apply it would have copied each mesh's
  neighbour over it, verified the copy against the same wrong hash, and reported
  5,517 successful restores while destroying the entire art checkout.

  Two changes make that class of bug impossible here, and both are load-bearing:
    - stdin is a FILE, via Start-Process, so PowerShell never encodes the stream;
    - the reply is SELF-DESCRIBING. `--batch=%(objectsize) %(rest)` echoes the
      path back in each header, so every hash is matched to a path git itself
      named. Nothing is zipped by position, and a dropped record can no longer
      silently shift anything.
  ---------------------------------------------------------------------------

.PARAMETER Apply
  Write the restores. Default is a dry run that only reports.

.PARAMETER Repo
  The 0 A.D. checkout. Defaults to the render box / workstation layout.

.PARAMETER Quiet
  Suppress the per-file lines; print only the tally.

.NOTES
  Run this AFTER a batch, never DURING one -- it would race the very bakes it is
  trying to clean up after.
#>

[CmdletBinding()]
param(
    [switch] $Apply,
    [string] $Repo = "C:\Users\herman.ras\Downloads\AOD_game\art_source\0ad",
    [switch] $Quiet
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path (Join-Path $Repo ".git"))) { throw "not a git checkout: $Repo" }
$git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $git) { throw "git not on PATH -- needed to read the LFS pointers" }

$ART = "binaries/data/mods/public/art"

Write-Host "listing tracked meshes..." -ForegroundColor DarkGray
$paths = @(& $git -C $Repo ls-tree -r --name-only HEAD -- $ART | Where-Object { $_ -like "*.dae" })
if ($paths.Count -eq 0) { throw "no .dae tracked under $ART -- wrong repo?" }
Write-Host ("  {0:n0} tracked .dae" -f $paths.Count)

# `<spec> <rest>`: git echoes %(rest) back in the header, which is what makes the
# reply self-describing. See the note in the header comment -- this is the whole
# defence against a positional zip going wrong.
$inFile  = [IO.Path]::GetTempFileName()
$outFile = [IO.Path]::GetTempFileName()
$errFile = [IO.Path]::GetTempFileName()
try {
    # .NET, not Set-Content -Encoding utf8: the latter writes a BOM on PS 5.1,
    # which is the exact bug described above.
    [IO.File]::WriteAllLines($inFile, ($paths | ForEach-Object { "HEAD:$_ $_" }), (New-Object Text.UTF8Encoding($false)))

    Write-Host "reading LFS pointers..." -ForegroundColor DarkGray
    $p = Start-Process -FilePath $git -WorkingDirectory $Repo -NoNewWindow -Wait -PassThru `
        -ArgumentList @("cat-file", "--batch=%(objectsize)|%(rest)") `
        -RedirectStandardInput $inFile -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    if ($p.ExitCode -ne 0) { throw "git cat-file failed ($($p.ExitCode)): $(Get-Content $errFile -Raw)" }

    # Header lines are `<size>|<path>`; everything between headers is the blob's
    # own content. A pointer is ~130 bytes of ASCII, so anything >= 1024 is stored
    # inline rather than in LFS and has no pristine copy to compare against.
    #
    # The separator is `|` and not a space because Start-Process -ArgumentList
    # splits an argument containing a space into two, and git then rejects the
    # remainder with "batch modes take no arguments".
    $want = @{}
    $cur  = $null
    foreach ($line in [IO.File]::ReadLines($outFile)) {
        $h = [regex]::Match($line, '^(\d+)\|(binaries/.+\.dae)$')
        if ($h.Success) {
            $cur = if ([int]$h.Groups[1].Value -lt 1024) { $h.Groups[2].Value } else { $null }
            continue
        }
        if ($cur -and $line -match '^oid sha256:([0-9a-f]{64})$') { $want[$cur] = $Matches[1]; $cur = $null }
    }
}
finally { Remove-Item $inFile, $outFile, $errFile -Force -ErrorAction SilentlyContinue }

Write-Host ("  {0:n0} pointers parsed" -f $want.Count)
if ($want.Count -lt $paths.Count * 0.9) {
    # A big shortfall means the parse lost records, not that the art changed.
    # Refusing here rather than reporting a plausible-looking tally is the point.
    throw "only $($want.Count) of $($paths.Count) pointers parsed -- parse is unreliable, refusing to continue"
}
Write-Host ""

# One reused SHA256 instance rather than Get-FileHash per file: the cmdlet's
# per-call overhead dominates at five thousand files.
$sha = [Security.Cryptography.SHA256]::Create()
function Get-Sha256([string]$file) {
    $fs = [IO.File]::OpenRead($file)
    try { return [BitConverter]::ToString($sha.ComputeHash($fs)).Replace("-", "").ToLowerInvariant() }
    finally { $fs.Dispose() }
}

$clean = 0; $dirty = 0; $fixed = 0; $nocache = 0; $failed = 0; $absent = 0
$n = 0
foreach ($rel in $want.Keys) {
    $n++
    if ($n % 1000 -eq 0) { Write-Host ("  ...{0:n0}/{1:n0}" -f $n, $want.Count) -ForegroundColor DarkGray }

    $oid  = $want[$rel]
    $file = Join-Path $Repo ($rel -replace '/', '\')
    if (-not (Test-Path $file)) { $absent++; continue }

    if ((Get-Sha256 $file) -eq $oid) { $clean++; continue }
    $dirty++

    $obj = Join-Path $Repo (".git\lfs\objects\{0}\{1}\{2}" -f $oid.Substring(0,2), $oid.Substring(2,2), $oid)
    if (-not (Test-Path $obj)) {
        if (-not $Quiet) { Write-Host "  NO CACHED OBJECT  $rel" -ForegroundColor Red }
        $nocache++
        continue
    }
    # Guard against a corrupt cache: the object must hash to its own name.
    if ((Get-Sha256 $obj) -ne $oid) {
        if (-not $Quiet) { Write-Host "  CACHE CORRUPT     $rel" -ForegroundColor Red }
        $failed++
        continue
    }

    if ($Apply) {
        Copy-Item -LiteralPath $obj -Destination $file -Force
        if ((Get-Sha256 $file) -eq $oid) {
            $fixed++
        } else {
            if (-not $Quiet) { Write-Host "  RESTORE FAILED    $rel" -ForegroundColor Red }
            $failed++
        }
    } elseif (-not $Quiet) {
        Write-Host "  would restore     $rel"
    }
}
$sha.Dispose()

Write-Host ""
Write-Host ("already pristine : {0:n0}" -f $clean)
Write-Host ("modified         : {0:n0}" -f $dirty) -ForegroundColor $(if ($dirty) { "Yellow" } else { "Green" })
if ($Apply) { Write-Host ("restored         : {0:n0}" -f $fixed) -ForegroundColor Cyan }
else        { Write-Host "(dry run -- pass -Apply to restore)" -ForegroundColor DarkGray }
if ($absent)  { Write-Host ("not on disk      : {0:n0}" -f $absent) -ForegroundColor DarkGray }
if ($nocache) { Write-Host ("no cached object : {0:n0}  (needs: git lfs pull, from WSL)" -f $nocache) -ForegroundColor Red }
if ($failed)  { Write-Host ("FAILED           : {0:n0}" -f $failed) -ForegroundColor Red }

# A non-zero exit only for things a human must act on. Dirty-but-restored is the
# normal, expected outcome of a batch and is not a failure.
if ($nocache -or $failed) { exit 1 }
exit 0
