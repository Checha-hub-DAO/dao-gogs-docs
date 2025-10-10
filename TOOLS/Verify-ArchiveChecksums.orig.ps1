[CmdletBinding()]
param(
  [string]$ReportsRoot = "D:\CHECHA_CORE\REPORTS",
  [string]$WeekTag,                  # напр. 'weekly_YYYY-MM-DD_to_YYYY-MM-DD'; якщо не задано — перевірити все
  [switch]$ShowExtras,               # показувати «зайві» файли (не згадані у CHECKSUMS.txt)
  [switch]$FailOnWarning,            # ExitCode=1, якщо є попередження (EXTRA) при -ShowExtras
  [switch]$SummaryOnly,              # показати тільки підсумок
  [switch]$CsvReport,                # зберегти CSV у C03_LOG
  [string]$LogsDir = "D:\CHECHA_CORE\C03_LOG",
  [switch]$RebuildIfMissing          # авто-відновити CHECKSUMS.txt, якщо його немає
)

function Parse-ChecksumsFile([string]$path) {
  $lines = Get-Content -LiteralPath $path -ErrorAction Stop
  $entries = @()
  foreach ($line in $lines) {
    if ($line -match '^[0-9A-Fa-f]{64}\s{2}(.+)$') {
      $hash = $line.Substring(0,64).ToUpperInvariant()
      $file = $line.Substring(66)
      $entries += [pscustomobject]@{ Hash=$hash; File=$file }
    }
  }
  return $entries
}

function Rebuild-Checksums {
  param([Parameter(Mandatory)][string]$WeekDir)
  if (-not (Test-Path -LiteralPath $WeekDir)) { throw "Dir not found: $WeekDir" }

  $checksums = Join-Path -Path $WeekDir -ChildPath 'CHECKSUMS.txt'
  "SHA256 checksums for $([IO.Path]::GetFileName($WeekDir))" | Out-File -FilePath $checksums -Encoding UTF8

  Get-ChildItem -LiteralPath $WeekDir -File |
    Where-Object { $_.Name -notin @('CHECKSUMS.txt','LOG.txt') } |
    ForEach-Object {
      $h = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
      ("{0}  {1}" -f $h, $_.Name) | Add-Content -LiteralPath $checksums -Encoding UTF8
    }

  Write-Host "[rebuild] CHECKSUMS regenerated: $checksums"
  return $checksums
}

function Check-Week([string]$weekDir) {
  $result = [ordered]@{
    WeekPath      = $weekDir
    OkCount       = 0
    MissingCount  = 0
    MismatchCount = 0
    ExtraCount    = 0
    Items         = @()
    Rebuilt       = $false
  }

  $sumPath = Join-Path $weekDir "CHECKSUMS.txt"

  if (-not (Test-Path $sumPath)) {
    if ($RebuildIfMissing) {
      $sumPath = Rebuild-Checksums -WeekDir $weekDir
      $result.Rebuilt = $true
    } else {
      Write-Warning "[skip] CHECKSUMS.txt not found: $weekDir (use -RebuildIfMissing to auto-create)"
      return $result
    }
  }

  $entries = Parse-ChecksumsFile $sumPath
  $expectedFiles = @{}
  foreach ($e in $entries) { $expectedFiles[$e.File] = $e.Hash }

  foreach ($kv in $expectedFiles.GetEnumerator()) {
    $name = $kv.Key
    $exp  = $kv.Value
    $full = Join-Path $weekDir $name

    if (-not (Test-Path $full)) {
      $result.MissingCount++
      $result.Items += [pscustomobject]@{ Status='MISSING'; File=$name; Expected=$exp; Actual='-' }
      continue
    }

    try {
      $act = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToUpperInvariant()
      if ($act -eq $exp) {
        $result.OkCount++
        $result.Items += [pscustomobject]@{ Status='OK'; File=$name; Expected=$exp; Actual=$act }
      } else {
        $result.MismatchCount++
        $result.Items += [pscustomobject]@{ Status='MISMATCH'; File=$name; Expected=$exp; Actual=$act }
      }
    } catch {
      $result.MissingCount++
      $result.Items += [pscustomobject]@{ Status='ERROR'; File=$name; Expected=$exp; Actual=$_.Exception.Message }
    }
  }

  if ($ShowExtras) {
    $allFiles = Get-ChildItem -LiteralPath $weekDir -File | Select-Object -ExpandProperty Name
    $extra = $allFiles | Where-Object {
      -not $expectedFiles.ContainsKey($_) -and $_ -notin @('CHECKSUMS.txt','LOG.txt')
    }
    foreach ($name in $extra) {
      $result.ExtraCount++
      $result.Items += [pscustomobject]@{ Status='EXTRA'; File=$name; Expected='(none)'; Actual='(present)' }
    }
  }

  return $result
}

# -------- MAIN --------

$archiveRoot = Join-Path $ReportsRoot "ARCHIVE"
$weekDirs = @()

if ($WeekTag) {
  if ($WeekTag -match '^weekly_(\d{4}-\d{2}-\d{2})_to_(\d{4}-\d{2}-\d{2})$') {
    $end = [datetime]::ParseExact($matches[2],'yyyy-MM-dd',$null)
    $year = $end.ToString('yyyy')
    $dir = Join-Path (Join-Path $archiveRoot $year) $WeekTag
    if (Test-Path $dir) { $weekDirs = ,$dir } else { Write-Warning "[not found] $dir"; exit 1 }
  } else {
    Write-Warning "WeekTag format invalid. Expected: weekly_YYYY-MM-DD_to_YYYY-MM-DD"
    exit 1
  }
} else {
  if (-not (Test-Path $archiveRoot)) { Write-Warning "ARCHIVE not found: $archiveRoot"; exit 1 }
  Get-ChildItem -LiteralPath $archiveRoot -Directory | ForEach-Object {
    if ($_.Name -match '^\d{4}$') {
      Get-ChildItem -LiteralPath $_.FullName -Directory | ForEach-Object {
        if ($_.Name -match '^weekly_(\d{4}-\d{2}-\d{2})_to_(\d{4}-\d{2}-\d{2})$') {
          $weekDirs += $_.FullName
        }
      }
    }
  }
}

if (-not $weekDirs) {
  Write-Warning "No weekly directories found."
  exit 1
}

$hasMismatch=$false; $hasMissing=$false; $hasExtras=$false
$all = @()

foreach ($wd in ($weekDirs | Sort-Object)) {
  $r = Check-Week $wd
  $all += $r.Items

  if (-not $SummaryOnly) {
    "{0}`n{1}" -f $wd, ('-' * $wd.Length) | Write-Host
    if ($r.Rebuilt) { Write-Host "[info] CHECKSUMS rebuilt before validation" }
    $r.Items | Sort-Object Status, File | ForEach-Object {
      "{0,-9}  {1}" -f $_.Status, $_.File | Write-Host
      if ($_.Status -eq 'MISMATCH') {
        "   expected: $($_.Expected)`n   actual:   $($_.Actual)" | Write-Host
      }
    }
    ""
  }

  if ($r.MismatchCount -gt 0) { $hasMismatch = $true }
  if ($r.MissingCount  -gt 0) { $hasMissing  = $true }
  if ($r.ExtraCount    -gt 0) { $hasExtras   = $true }
}

$summary = [pscustomobject]@{
  WeeksChecked = $weekDirs.Count
  Ok           = -not ($hasMismatch -or $hasMissing)
  AnyMismatch  = $hasMismatch
  AnyMissing   = $hasMissing
  AnyExtras    = $hasExtras
  Timestamp    = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
}

"SUMMARY:`n--------" | Write-Host
$summary | Format-List | Out-String | Write-Host

if ($CsvReport) {
  if (-not (Test-Path $LogsDir)) { New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null }
  $csv = Join-Path $LogsDir ("VerifyChecksums_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
  $all | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
  Write-Host "[report] CSV saved: $csv"
}

$exitCode = 0
if ($hasMismatch -or $hasMissing) { $exitCode = 1 }
elseif ($FailOnWarning -and $hasExtras) { $exitCode = 1 }

# … кінець Verify-ArchiveChecksums.ps1 …
try {
  $upd = "D:\CHECHA_CORE\TOOLS\Update-IntegrityScore.ps1"
  if(Test-Path $upd){
    pwsh -NoProfile -ExecutionPolicy Bypass `
      -File $upd `
      -ChecksumsGlob "D:\CHECHA_CORE\C03_LOG\VerifyChecksums_*.csv" `
      -OutCsv "D:\CHECHA_CORE\C07_ANALYTICS\C12_IntegrityScore.csv" `
      -LogPath "D:\CHECHA_CORE\C07_ANALYTICS\logs\Update-IntegrityScore.log" | Out-Null
  }
} catch {
  Write-Host "[WARN] Post-hook Update-IntegrityScore failed: $($_.Exception.Message)"
}
# exit <поточний код>

exit $exitCode
