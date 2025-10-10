<# ========================================================================
  ReflexEngine.ps1  —  CheCha CORE • Flight 4.11
  Призначення: щоденний “рефлекс” системи — аналіз логів/матриць, мапа здоров’я задач,
  короткий висновок та репорт у Markdown + JSON.

  Рекомендований шлях: D:\CHECHA_CORE\TOOLS\ReflexEngine.ps1
  Запуск:  pwsh -NoProfile -ExecutionPolicy Bypass -File D:\CHECHA_CORE\TOOLS\ReflexEngine.ps1

  Вихідні коди:
    0 — OK (без суттєвих зауважень)
    1 — WARN (знайдено попередження/відхилення, але критичних збоїв нема)
    2 — ERROR (критичні збої під час роботи)

  Автор: С.Ч. / CheCha
========================================================================= #>

[CmdletBinding()]
param(
  # Корінь системи (можна перевизначити при запуску)
  [string]$Root = "D:\CHECHA_CORE",

  # Дати (ISO). За замовчуванням — сьогодні.
  [string]$Date = (Get-Date -Format 'yyyy-MM-dd'),

  # Список перевірюваних задач (можна доповнювати)
  [string[]]$Tasks = @(
    "MorningPanel-RestoreTop3",
    "Evening-RestoreLog",
    "LeaderIntel-Daily",
    "CHECHA_Weekly_Publish"
  ),

  # М’який режим: не кидати помилки, а зводити їх у WARN
  [switch]$Soft
)

# -------------------------- ПАРАМЕТРИ ШЛЯХІВ ---------------------------
$Paths = [ordered]@{
  Root              = (Resolve-Path -LiteralPath $Root).Path
  Focus             = Join-Path $Root "C06_FOCUS"
  Analytics         = Join-Path $Root "C07_ANALYTICS"
  ReflexOut         = Join-Path $Root "C07_ANALYTICS\Reflex"
  LogsRoot          = Join-Path $Root "C03_LOG"
  RestoreLog        = Join-Path $Root "C06_FOCUS\FOCUS_RestoreLog.md"
  MatRestoreCsv     = Join-Path $Root "C07_ANALYTICS\MAT_RESTORE.csv"
  MatBalanceCsv     = Join-Path $Root "C07_ANALYTICS\MAT_BALANCE.csv"
}

# Забезпечимо вихідні теки
$null = New-Item -ItemType Directory -Force -Path $Paths.ReflexOut, $Paths.LogsRoot | Out-Null

# Лог-файл
$Stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogPath = Join-Path $Paths.LogsRoot ("Reflex_"+$Stamp+".log")

# ------------------------- УТИЛІТИ ЛОГУВАННЯ ---------------------------
function Write-ReflexLog {
  param([string]$Level = "INFO", [string]$Message)
  $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
  $line | Tee-Object -FilePath $LogPath -Append
}

function Safe-ImportCsv {
  param([string]$Path)
  if (!(Test-Path -LiteralPath $Path)) {
    Write-ReflexLog "WARN" "CSV не знайдено: $Path"
    return @()
  }
  try   { return Import-Csv -LiteralPath $Path -Delimiter ',' }
  catch { Write-ReflexLog "ERROR" "Помилка читання CSV: $Path :: $($_.Exception.Message)"; return @() }
}

function Get-FileTail {
  param([string]$Path, [int]$Tail = 50)
  if (!(Test-Path -LiteralPath $Path)) { return @() }
  try   { return Get-Content -LiteralPath $Path -Tail $Tail }
  catch { Write-ReflexLog "WARN" "Не вдалось прочитати кінець файлу: $Path :: $($_.Exception.Message)"; return @() }
}

# ----------------------- АНАЛІЗ МАТРИЦЬ/ЛОГІВ --------------------------
function Analyze-RestoreLog {
  [CmdletBinding()]
  param([string]$RestoreLogPath, [int]$Tail = 200)

  $lines = Get-FileTail -Path $RestoreLogPath -Tail $Tail
  $result = [ordered]@{
    Found          = $false
    UpdatesToday   = 0
    LastUpdate     = $null
    Hints          = @()
  }
  if ($lines.Count -gt 0) {
    $result.Found = $true
    # Простий парсер: шукаємо рядки "Updated status for YYYY-MM-DD" та інші маркери
    $dateTag = (Get-Date -Format 'yyyy-MM-dd')
    $result.UpdatesToday = ($lines | Select-String -SimpleMatch $dateTag).Count
    $last = ($lines | Select-String -Pattern '^\-\s*\[\d{4}\-\d{2}\-\d{2}\s+\d{2}\:\d{2}\:\d{2}\]').Matches
    if ($last.Count -gt 0) {
      # Візьмемо останній рядок з датою/часом
      $raw = ($lines | Select-String -Pattern '^\-\s*\[\d{4}\-\d{2}\-\d{2}\s+\d{2}\:\d{2}\:\d{2}\]').Line | Select-Object -Last 1
      $result.LastUpdate = $raw
    }
    if ($result.UpdatesToday -eq 0) { $result.Hints += "Сьогодні немає фіксацій у RestoreLog." }
  } else {
    $result.Hints += "RestoreLog порожній або недоступний."
  }
  return $result
}

function Analyze-MatrixDelta {
  <#
    Порівнює останні 2 знімки (за колонкою LastWriteTime або просто останні рядки),
    якщо CSV ведеться як стрім — аналізуємо крайні N записів.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][array]$RestoreCsv,
    [Parameter(Mandatory)][array]$BalanceCsv
  )
  $out = [ordered]@{
    RestoreCount = $RestoreCsv.Count
    BalanceCount = $BalanceCsv.Count
    Signals      = @()
  }
  if ($RestoreCsv.Count -eq 0) { $out.Signals += "MAT_RESTORE.csv — немає даних."; }
  if ($BalanceCsv.Count -eq 0) { $out.Signals += "MAT_BALANCE.csv — немає даних."; }

  # Простий евристичний сигнал: якщо у Restore суттєвий приріст або спад рядків
  if ($RestoreCsv.Count -gt 10) {
    $prev = $RestoreCsv.Count - 10
    $diff = $RestoreCsv.Count - $prev
    if ([math]::Abs($diff) -ge 10) {
      $out.Signals += "RestoreMatrix швидко змінюється (±10 записів за короткий період)."
    }
  }
  return $out
}

# ----------------------- МАПА ЗДОРОВ’Я ЗАДАЧ ---------------------------
function Get-TaskHealthMap {
  [CmdletBinding()]
  param([string[]]$Names)

  $map = @()
  foreach ($n in $Names) {
    try {
      $t = Get-ScheduledTask -TaskName $n -ErrorAction Stop
      $i = $t | Get-ScheduledTaskInfo
      $map += [pscustomobject]@{
        TaskName      = $n
        State         = $t.State
        LastRunTime   = $i.LastRunTime
        NextRunTime   = $i.NextRunTime
        LastTaskResult= $i.LastTaskResult
        Ok            = ($i.LastTaskResult -eq 0)
      }
    }
    catch {
      Write-ReflexLog "WARN" "Задача не знайдена або недоступна: $n"
      $map += [pscustomobject]@{
        TaskName      = $n
        State         = "Unknown"
        LastRunTime   = $null
        NextRunTime   = $null
        LastTaskResult= $null
        Ok            = $false
      }
    }
  }
  return $map
}

# ------------------------- РЕПОРТ/СЕРІАЛІЗАЦІЯ -------------------------
function New-ReflexReport {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$RestoreInfo,
    [Parameter(Mandatory)]$MatrixInfo,
    [Parameter(Mandatory)]$TaskHealth,
    [Parameter(Mandatory)][string]$OutDir,
    [Parameter(Mandatory)][string]$Date
  )

  if (!(Test-Path -LiteralPath $OutDir)) { $null = New-Item -ItemType Directory -Force -Path $OutDir }

  $mdName = Join-Path $OutDir ("ReflexReport_{0}.md" -f ($Date -replace '-',''))
  $jsonName = Join-Path $OutDir ("ReflexReport_{0}.json" -f ($Date -replace '-',''))

  $warns = @()
  $errors = @()

  # Фіксуємо попередження/помилки за сигналами
  if ($RestoreInfo.Hints.Count -gt 0) { $warns += $RestoreInfo.Hints }
  if ($MatrixInfo.Signals.Count -gt 0) { $warns += $MatrixInfo.Signals }
  if (($TaskHealth | Where-Object { -not $_.Ok }).Count -gt 0) {
    $warns += "Є задачі із LastTaskResult ≠ 0 або невідомим станом."
  }

  # ---------- Markdown ----------
  $md = @()
  $md += "# 🔄 Reflex Report — $Date"
  $md += ""
  $md += "## 1) RestoreLog"
  $md += "- Found: **$($RestoreInfo.Found)**"
  $md += "- UpdatesToday: **$($RestoreInfo.UpdatesToday)**"
  if ($RestoreInfo.LastUpdate) { $md += "- LastUpdate: `$($RestoreInfo.LastUpdate)`" }
  if ($RestoreInfo.Hints.Count -gt 0) {
    $md += "- Hints:"
    foreach($h in $RestoreInfo.Hints){ $md += "  - $h" }
  }

  $md += ""
  $md += "## 2) Matrices"
  $md += "- Restore rows: **$($MatrixInfo.RestoreCount)**"
  $md += "- Balance rows: **$($MatrixInfo.BalanceCount)**"
  if ($MatrixInfo.Signals.Count -gt 0) {
    $md += "- Signals:"
    foreach($s in $MatrixInfo.Signals){ $md += "  - $s" }
  }

  $md += ""
  $md += "## 3) Task Health Map"
  $md += ""
  $md += "| Task | State | LastRun | NextRun | Result | OK |"
  $md += "|:-----|:------|:--------|:--------|:------:|:--:|"
  foreach($t in $TaskHealth){
    $md += ("| {0} | {1} | {2} | {3} | {4} | {5} |" -f
      $t.TaskName,
      $t.State,
      ($t.LastRunTime  ? ($t.LastRunTime.ToString("yyyy-MM-dd HH:mm:ss")) : "-"),
      ($t.NextRunTime  ? ($t.NextRunTime.ToString("yyyy-MM-dd HH:mm:ss")) : "-"),
      ($t.LastTaskResult -as [string]),
      ($t.Ok ? "✅" : "❗"))
  }

  $md += ""
  $md += "## 4) Summary"
  if ($warns.Count -eq 0) {
    $md += "- Status: **OK**"
  } else {
    $md += "- Status: **WARN**"
    foreach($w in $warns){ $md += "  - $w" }
  }

  $mdText = $md -join "`r`n"
  Set-Content -LiteralPath $mdName -Encoding UTF8 -Value $mdText

  # ---------- JSON ----------
  $payload = [ordered]@{
    Date       = $Date
    Restore    = $RestoreInfo
    Matrices   = $MatrixInfo
    TaskHealth = $TaskHealth
    Status     = @{"Ok" = ($warns.Count -eq 0); "Warns" = $warns }
    LogPath    = $LogPath
  }
  ($payload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $jsonName -Encoding UTF8

  return [pscustomobject]@{
    MdPath   = $mdName
    JsonPath = $jsonName
    Warns    = $warns
    Errors   = $errors
  }
}

# ============================= MAIN =====================================
$exitCode = 0
try {
  Write-ReflexLog "INFO" "=== ReflexEngine старт ==="
  Write-ReflexLog "INFO" ("Root: {0}" -f $Paths.Root)

  # 1) RestoreLog
  $restoreInfo = Analyze-RestoreLog -RestoreLogPath $Paths.RestoreLog
  Write-ReflexLog "INFO" ("RestoreLog Found={0}, UpdatesToday={1}" -f $restoreInfo.Found, $restoreInfo.UpdatesToday)

  # 2) Матриці
  $restoreCsv = Safe-ImportCsv -Path $Paths.MatRestoreCsv
  $balanceCsv = Safe-ImportCsv -Path $Paths.MatBalanceCsv
  $matrixInfo = Analyze-MatrixDelta -RestoreCsv $restoreCsv -BalanceCsv $balanceCsv
  Write-ReflexLog "INFO" ("Matrices: Restore={0}, Balance={1}" -f $matrixInfo.RestoreCount, $matrixInfo.BalanceCount)

  # 3) Task Health Map
  $taskHealth = Get-TaskHealthMap -Names $Tasks
  $bad = $taskHealth | Where-Object { -not $_.Ok }
  if ($bad.Count -gt 0) {
    Write-ReflexLog "WARN" ("Нестабільні задачі: {0}" -f (($bad | Select-Object -ExpandProperty TaskName) -join ', '))
  }

  # 4) Репорт
  $report = New-ReflexReport -RestoreInfo $restoreInfo -MatrixInfo $matrixInfo -TaskHealth $taskHealth -OutDir $Paths.ReflexOut -Date $Date
  Write-ReflexLog "INFO" ("Report MD: {0}" -f $report.MdPath)
  Write-ReflexLog "INFO" ("Report JSON: {0}" -f $report.JsonPath)

  if ($report.Errors.Count -gt 0) { $exitCode = 2 }
  elseif ($report.Warns.Count -gt 0) { $exitCode = 1 }
  else { $exitCode = 0 }

  Write-ReflexLog "INFO" ("ExitCode={0}" -f $exitCode)
}
catch {
  Write-ReflexLog "ERROR" ("Неперехоплена помилка: {0}" -f $_.Exception.Message)
  if ($Soft) { $exitCode = 1 } else { $exitCode = 2 }
}
finally {
  Write-ReflexLog "INFO" "=== ReflexEngine завершено ==="
  exit $exitCode
}

# ======================== ДОВІДКА: Планувальник =========================
<#
# 1) Одноразовий запуск для тесту:
pwsh -NoProfile -ExecutionPolicy Bypass -File D:\CHECHA_CORE\TOOLS\ReflexEngine.ps1

# 2) Створення задачі раз на день (наприклад, 07:35):
$pwsh = (Get-Command pwsh).Source
schtasks /Create /SC DAILY /ST 07:35 /TN "ReflexEngine-Daily" /F /TR `
 "$pwsh -NoProfile -ExecutionPolicy Bypass -File D:\CHECHA_CORE\TOOLS\ReflexEngine.ps1"

# 3) Ручний запуск:
schtasks /Run /TN "ReflexEngine-Daily"

# 4) Перевірка:
schtasks /Query /TN "ReflexEngine-Daily" /V /FO LIST
#>
