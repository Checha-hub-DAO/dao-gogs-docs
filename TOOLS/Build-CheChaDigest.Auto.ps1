<# =========================================================
 Build-CheChaDigest.Auto.ps1
 Автор: С.Ч. | DAO-GOGS Systemtled
 Призначення: згенерувати щоденний дайджест CheCha (MD + TXT)
   • Автоматично читає ключові логи/стан задач
   • Підставляє фактичні дати/статуси у контент
 Повертає: 0 — OK, 1 — помилка
 Виклик:
   pwsh -NoProfile -ExecutionPolicy Bypass -File .\Build-CheChaDigest.Auto.ps1 `
     -OutDir "D:\CHECHA_CORE\C03_LOG\digests" -Open
========================================================= #>

[CmdletBinding()]
param(
  [string]$OutDir = "D:\CHECHA_CORE\C03_LOG\digests",
  [string]$DateTag,                        # yyyy-MM-dd; якщо порожньо — поточна дата
  [int]$Tail = 40,                         # скільки рядків читати з кінця логів
  [switch]$Open,
  [switch]$Overwrite
)

function Die($msg){ Write-Host "[ERR] $msg" -ForegroundColor Red; exit 1 }

# --- 0) Дата/шляхи -----------------------------------------------------------
try {
  if (-not $DateTag) { $DateTag = (Get-Date).ToString('yyyy-MM-dd') }
  if (!(Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  }
  $MdFile  = Join-Path $OutDir "CheCha_Digest_${DateTag}.md"
  $TxtFile = Join-Path $OutDir "CheCha_Digest_${DateTag}.txt"

  if ((Test-Path $MdFile) -and -not $Overwrite) {
    Write-Host "[SKIP] Файл існує: $MdFile (вкажи -Overwrite для перезапису)" -ForegroundColor Yellow
  }
  if ((Test-Path $TxtFile) -and -not $Overwrite) {
    Write-Host "[SKIP] Файл існує: $TxtFile (вкажи -Overwrite для перезапису)" -ForegroundColor Yellow
  }

  # Відомі шляхи
  $RunAlertLog      = "D:\CHECHA_CORE\C07_ANALYTICS\Run-Alert.log"
  $RestoreLogPath   = "D:\CHECHA_CORE\C06_FOCUS\FOCUS_RestoreLog.md"
  $ChecksumsCsvGlob = "D:\CHECHA_CORE\C03_LOG\VerifyChecksums_*.csv"

  # Завдання Планувальника (імена можуть бути змінені за потреби)
  $Tasks = @(
    @{ Name="CHECHA_Weekly_Publish"; Path="\CHECHA\" },
    @{ Name="LeaderIntel-Daily";     Path="\" }
  )

  # --- helpers ---------------------------------------------------------------
  function TailSafe([string]$path, [int]$n=40){
    if (Test-Path -LiteralPath $path) {
      try { Get-Content -LiteralPath $path -Tail $n -ErrorAction Stop }
      catch { @("<read-error: $path> " + $_.Exception.Message) }
    } else { @("<missing: $path>") }
  }

  function GetTaskInfo([string]$name,[string]$taskPath="\") {
    try {
      $t = Get-ScheduledTask -TaskName $name -TaskPath $taskPath -ErrorAction Stop
      $i = $t | Get-ScheduledTaskInfo
      [pscustomobject]@{
        Name          = $name
        State         = $t.State
        LastRunTime   = $i.LastRunTime
        LastTaskResult= $i.LastTaskResult
        NextRunTime   = $i.NextRunTime
      }
    } catch {
      [pscustomobject]@{
        Name=$name; State="N/A"; LastRunTime=$null; LastTaskResult=$null; NextRunTime=$null
      }
    }
  }

  function DetectGhAuth(){
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh){ return "gh: not installed" }
    try {
      $status = (gh auth status 2>&1) -join "`n"
      if ($status -match "Logged in to"){
        return "OK"
      } else {
        return "needs login"
      }
    } catch { return "unknown" }
  }

  # --- 1) Збір даних із логів ------------------------------------------------
  $runAlertTail = TailSafe $RunAlertLog $Tail
  $runAlertStr  = $runAlertTail -join "`n"
  $runAlertErrors24h = 0
  $now = Get-Date
  # рахуємо помилки за останні 24 години
  foreach($line in $runAlertTail){
    if ($line -match '^\[(?<ts>[\d\-:\s]+)\].*(ERROR|failed|rc=1)'){
      $ts = $Matches.ts
      $dt = $null
      # спроби різних форматів
      if ([datetime]::TryParse($ts, [ref]$dt)) {
        if ($now - $dt -lt [timespan]::FromHours(24)) { $runAlertErrors24h++ }
      } else {
        # якщо не спарсилось — все одно рахуємо як помилку
        $runAlertErrors24h++
      }
    }
  }
  # ключові індикатори
  $runAlertLastError = ($runAlertTail | Where-Object { $_ -match '(ERROR|failed|rc=1)' } | Select-Object -Last 1)
  $runAlertLastStart = ($runAlertTail | Where-Object { $_ -match 'START Run-Alert' } | Select-Object -Last 1)
  $runAlertLastEnd   = ($runAlertTail | Where-Object { $_ -match 'END Run-Alert' }   | Select-Object -Last 1)

  # RestoreLog — беремо 5 останніх подій
  $restoreTail = TailSafe $RestoreLogPath 50
  $restoreEvents = $restoreTail | Where-Object { $_ -match '^\-\s*\[\d{4}\-\d{2}\-\d{2}\s' } | Select-Object -Last 5
  $restoreLast   = $restoreEvents | Select-Object -Last 1

  # Checksums — знаходимо найсвіжіший CSV
  $checksumsState = "N/A"
  $csvLatest = Get-ChildItem -Path $ChecksumsCsvGlob -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 1
  if ($csvLatest) {
    try {
      $row = Import-Csv -LiteralPath $csvLatest.FullName | Select-Object -First 1
      if ($row){
        $ok          = $row.Ok
        $mismatch    = $row.AnyMismatch
        $missing     = $row.AnyMissing
        $extras      = $row.AnyExtras
        $checksumsState = "Ok=$ok, Missing=$missing, Mismatch=$mismatch, Extras=$extras"
      }
    } catch { $checksumsState = "CSV parse error" }
  }

  # --- 2) Планувальник -------------------------------------------------------
  $taskInfos = foreach($t in $Tasks){ GetTaskInfo -name $t.Name -taskPath $t.Path }

  # --- 3) Git/GitHub (опційно) -----------------------------------------------
  $ghAuth = DetectGhAuth()

  # --- 4) Формування контенту ------------------------------------------------
  # компактні рядки стану задач
  $tasksMd = ($taskInfos | ForEach-Object {
    $n = $_.Name
    $state = $_.State
    $l = if ($_.LastRunTime) { $_.LastRunTime.ToString("dd.MM.yyyy HH:mm") } else { "—" }
    $rc = if ($_.LastTaskResult -ne $null) { $_.LastTaskResult } else { "—" }
    $nx = if ($_.NextRunTime) { $_.NextRunTime.ToString("dd.MM.yyyy HH:mm") } else { "—" }
    "- **$n** — *$state*, Last: $l (rc=$rc), Next: $nx"
  }) -join "`n"

  $runAlertSummary = @()
  if ($runAlertLastStart) { $runAlertSummary += "• $runAlertLastStart" }
  if ($runAlertLastEnd)   { $runAlertSummary += "• $runAlertLastEnd" }
  if ($runAlertLastError) { $runAlertSummary += "• ERROR: $runAlertLastError" }
  $runAlertSummary += "• Помилок за 24h: $runAlertErrors24h"

  $restoreSummary = if ($restoreEvents) { ($restoreEvents -join "`n") } else { "—" }

  $md = @"
# ⚡️ CheCha | Щоденний дайджест — $DateTag

## 🧭 Стан системи
CheCha Core активна; робота стабільна.  
Аналітика й архіви функціонують.  
Перевірка архівів: **$checksumsState**.

---

## ⚙️ Технічний контур
**Run-Alert (tail):**
$($runAlertSummary -join "`n")

**Планувальник:**
$tasksMd

---

## 📊 Аналітика
- MAT_BALANCE — синтаксичне виправлення дужки (рядок 60) ще в роботі.
- MAT_RESTORE — активний, останні події:
$restoreSummary

---

## 🧩 Стратегічна лінія
- CheCha Flight 4.10 → курс на “Радар Свідомості”.
- ITETA (G43) → аналітика “Всесвіт — Людина — ШІ”.

---

## 📡 Синхронізація
- GitHub auth статус: **$ghAuth**.

---

## 💡 Рекомендації (авто-збір)
1. `Notify-If-Degraded.ps1` — перевірити джерело `-Path`, виправити прогін у Run-Alert.
2. Завершити правку `Build-MAT-BALANCE-Weekly.ps1` (незакрита `)`).
3. `LeaderIntel-Daily` — валідувати ініціалізацію змінної `$log`/шляхів.
4. GitHub — привести авторизацію до **OK** (`gh auth login --with-token`).
5. Підготувати `ToxicRadar.html` (перевірити тип `$rows` перед `.Count`).

---

## 🪶 Підсумок
Система в русі; **технічна стабільність + нарощення стратегічної аналітики**.  
Фокус — точність моніторингу та валідація ланцюга сповіщень.

_С.Ч._
"@

  $txt = @"
⚡️ CheCha | Щоденний дайджест — $DateTag

🧭 Стан
Стабільно; архіви: $checksumsState

⚙️ Технічний контур
$(($runAlertSummary -join "`n").Replace("• ","• "))

Планувальник
$($taskInfos | ForEach-Object {
  "$($_.Name): $($_.State); Last=" +
  "$(if ($_.LastRunTime){ $_.LastRunTime.ToString('dd.MM HH:mm') } else {'—'})" +
  "; rc=$($_.LastTaskResult); Next=" +
  "$(if ($_.NextRunTime){ $_.NextRunTime.ToString('dd.MM HH:mm') } else {'—'})"
} | Out-String).Trim()

📊 Аналітика
• MAT_BALANCE — фікс дужки (в роботі)
• MAT_RESTORE — активний (останні події ↓)
$restoreSummary

🧩 Стратегія
• Flight 4.10 → Радар Свідомості
• ITETA (G43) → Всесвіт—Людина—ШІ

📡 Синхронізація
• GitHub auth: $ghAuth

💡 To-Do
1) Notify-If-Degraded.ps1 (Path)
2) MAT_BALANCE — дужка
3) LeaderIntel — ініціалізація логу
4) gh auth login
5) ToxicRadar — тип $rows

_С.Ч._
"@

  # --- 5) Запис файлів -------------------------------------------------------
  Set-Content -LiteralPath $MdFile  -Value $md  -Encoding UTF8
  Set-Content -LiteralPath $TxtFile -Value $txt -Encoding UTF8

  Write-Host "[OK] Digest збережено:" -ForegroundColor Green
  Write-Host " - $MdFile"
  Write-Host " - $TxtFile"

  if ($Open) { Invoke-Item $OutDir }

  exit 0
}
catch {
  Die ("Не вдалося згенерувати дайджест: " + $_.Exception.Message)
}
