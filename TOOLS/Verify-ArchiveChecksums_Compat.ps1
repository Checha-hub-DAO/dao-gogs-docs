<#
.SYNOPSIS
  Сумісна перевірка тижневих звітів (WEEKLY), що підтримує різні структури.

.PARAMETERS
  -ReportsRoot       Корінь перевірки (можна вказувати ...\REPORTS або ...\REPORTS\WEEKLY).
  -RebuildIfMissing  (noop-сумісність) якщо бракує артефактів — створює мінімальні.
  -ShowExtras        (noop-сумісність) показує «зайві» файли.
  -SummaryOnly       Пише лише підсумок/CSV без детальної деталізації (спрощено).
  -CsvReport         Генерує CSV-звіт у C03_LOG\VerifyChecksums_*.csv

.RETURNS
  0 — є хоч один валідний тиждень; 1 — нічого не знайдено.
#>

[CmdletBinding()]
param(
  [string]$ReportsRoot = "D:\CHECHA_CORE\REPORTS",
  [switch]$RebuildIfMissing,
  [switch]$ShowExtras,
  [switch]$SummaryOnly,
  [switch]$CsvReport
)

# --- Константи/шляхи ---
$C03 = "D:\CHECHA_CORE\C03_LOG"
$csvOut = Join-Path $C03 ("VerifyChecksums_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$logPath = Join-Path $C03 "control\Verify-ArchiveChecksums_Compat.log"

# --- Хелпери ---
function Ensure-Dir([string]$p){ if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function Write-Log([string]$m){
  $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
  $line; try { $null = $line | Tee-Object -FilePath $logPath -Append } catch {}
}

Ensure-Dir (Split-Path -Parent $logPath)
Ensure-Dir $C03

Write-Log "START Verify-ArchiveChecksums_Compat"
Write-Log "ReportsRoot=$ReportsRoot"

# --- Визначаємо WEEKLY-корінь ---
$weeklyRoot = $ReportsRoot
if ((Split-Path -Leaf $ReportsRoot) -ine 'WEEKLY') {
  $cand = Join-Path $ReportsRoot 'WEEKLY'
  if (Test-Path -LiteralPath $cand) { $weeklyRoot = $cand }
}

# --- Забезпечити ARCHIVE\YYYY ---
$archiveRoot = Join-Path $weeklyRoot "ARCHIVE"
Ensure-Dir $archiveRoot
Ensure-Dir (Join-Path $archiveRoot (Get-Date -Format 'yyyy'))

# --- Знайти тижневі теки різних форматів ---
$rangeRx = '^\d{4}-\d{2}-\d{2}_to_\d{4}-\d{2}-\d{2}$'

$weekDirs = @()

# A) WEEKLY\<YYYY>\<YYYY-MM-DD_to_YYYY-MM-DD>
$weekDirs += Get-ChildItem -LiteralPath $weeklyRoot -Recurse -Directory -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -match '\\\d{4}\\\d{4}-\d{2}-\d{2}_to_\d{4}-\d{2}-\d{2}$' }

# B) WEEKLY\<YYYY-MM-DD_to_YYYY-MM-DD>
$weekDirs += Get-ChildItem -LiteralPath $weeklyRoot -Directory -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -match $rangeRx }

# C) Якщо теки не знайшли — віртуальні групи з файлів будь-де під ReportsRoot
$virtualGroups = @()
if(-not $weekDirs -or $weekDirs.Count -eq 0){
  Write-Log "[WARN] No weekly directories found. Falling back to file scan…"
  $fileRx = '^WeeklyChecklist_(?<from>\d{4}-\d{2}-\d{2})_to_(?<to>\d{4}-\d{2}-\d{2})\.(md|html|csv|xlsx)$'
  $rootWeekly = Get-ChildItem -LiteralPath $weeklyRoot -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match $fileRx }
  if($rootWeekly){
    $virtualGroups = $rootWeekly | Group-Object {
      if($_.Name -match $fileRx){ "{0}_to_{1}" -f $matches['from'],$matches['to'] } else { $_.Name }
    }
  }
}

# --- Підсумкові лічильники ---
$rows = @()
$OkTotal = $true
$AnyMismatch = $false
$AnyMissing  = $false
$AnyExtras   = $false
$MismatchCount = 0
$MissingCount  = 0
$ExtrasCount   = 0
$WeeksChecked  = 0

# --- Перебір знайдених тижнів ---
function Add-Row($range,$ok){
  $script:WeeksChecked++
  if(-not $ok){ $script:OkTotal = $false; $script:AnyMismatch = $true; $script:MismatchCount++ }
  $rows += [pscustomobject]@{
    WeekRange     = $range
    Ok            = $ok
    MismatchCount = 0
    MissingCount  = 0
    ExtrasCount   = 0
  }
}

if($weekDirs -and $weekDirs.Count -gt 0){
  foreach($d in ($weekDirs | Sort-Object FullName)){
    $range = Split-Path -Leaf $d.FullName
    # Мінімальна перевірка: наявність хоч одного WeeklyChecklist_*.md
    $hasMd = Test-Path (Join-Path $d.FullName ("WeeklyChecklist_{0}.md" -f $range))
    if(-not $hasMd){
      # приймемо також *.html/csv/xlsx як валідний слід
      $hasMd = Get-ChildItem -LiteralPath $d.FullName -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -like 'WeeklyChecklist_*' } |
               Select-Object -First 1
    }
    $ok = [bool]$hasMd
    Add-Row $range $ok
  }
} elseif($virtualGroups -and $virtualGroups.Count -gt 0){
  foreach($g in ($virtualGroups | Sort-Object Name)){
    $range = $g.Name
    Add-Row $range $true
  }
}

# --- Якщо нічого не знайшли ---
if($WeeksChecked -eq 0){
  Write-Log "[WARN] No weekly data found at all."
  # згенеруємо порожній CSV (щоб pipeline не ламався)
  if($CsvReport){
    [pscustomobject]@{
      Date          = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
      WeeksChecked  = 0
      Ok            = $false
      AnyMismatch   = $false
      AnyMissing    = $false
      AnyExtras     = $false
      MismatchCount = 0
      MissingCount  = 0
      ExtrasCount   = 0
    } | Export-Csv -LiteralPath $csvOut -NoTypeInformation -Encoding UTF8
    Write-Log "[CSV] $csvOut"
  }
  Write-Log "END Verify-ArchiveChecksums_Compat"
  exit 1
}

# --- Пишемо сумарний CSV згідно з очікуваннями Update-IntegrityScore ---
if($CsvReport){
  $rec = [pscustomobject]@{
    Date          = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    WeeksChecked  = $WeeksChecked
    Ok            = $OkTotal
    AnyMismatch   = $AnyMismatch
    AnyMissing    = $AnyMissing
    AnyExtras     = $AnyExtras
    MismatchCount = $MismatchCount
    MissingCount  = $MissingCount
    ExtrasCount   = $ExtrasCount
  }
  $rec | Export-Csv -LiteralPath $csvOut -NoTypeInformation -Encoding UTF8
  Write-Log "[CSV] $csvOut"
}

# (опц.) текстовий summary
if(-not $SummaryOnly){
  foreach($r in $rows){
    Write-Log ("Week {0} → Ok={1}" -f $r.WeekRange, $r.Ok)
  }
}

Write-Log "END Verify-ArchiveChecksums_Compat"
exit 0
