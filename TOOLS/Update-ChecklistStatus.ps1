param(
  [ValidateSet('OPEN','IN-PROGRESS','DONE')][string]$Status = 'DONE',
  [string]$FocusDir = "D:\CHECHA_CORE\C06_FOCUS",

  # Статистика у кінці файлу чек-листа
  [switch]$Finalize = $true,

  # Автопозначення чекбоксів: None | AutoTagged | All
  [ValidateSet('None','AutoTagged','All')][string]$AutoCheck = 'None',

  # Нове: Лог у RestoreLog
  [switch]$WriteRestoreLog = $true,
  [string]$RestoreLogPath = "D:\CHECHA_CORE\C06_FOCUS\FOCUS_RestoreLog.md"
)
$ErrorActionPreference = "Stop"

function Set-ChecklistStatus-AndMaybeFinalize {
  param(
    [Parameter(Mandatory)][ValidateSet('OPEN','IN-PROGRESS','DONE')][string]$Status,
    [Parameter(Mandatory)][string]$Path
  )
  if (-not (Test-Path $Path)) { return @{ ok = $false } }

  $lines = Get-Content -Path $Path -Encoding UTF8

  # 1) Статус у верхівці
  $statusIdx = -1
  for ($i=0; $i -lt [Math]::Min(5, $lines.Count); $i++) {
    if ($lines[$i] -match '^\s*(?:>\s*)?Status:\s*(OPEN|IN-PROGRESS|DONE)\s*$') { $statusIdx = $i; break }
  }
  $newStatus = "Status: $Status"
  if ($statusIdx -ge 0) { $lines[$statusIdx] = $newStatus } else { $lines = @($newStatus) + $lines }

  # 2) Автопозначення чекбоксів
  if ($AutoCheck -ne 'None') {
    for ($i=0; $i -lt $lines.Count; $i++) {
      $line = $lines[$i]
      $isTaskUnchecked = ($line -match '^\s*-\s*\[\s\]\s+')
      if ($isTaskUnchecked) {
        $shouldMark = switch ($AutoCheck) {
          'All'        { $true }
          'AutoTagged' { ($line -match '\[auto\]\s*$') }
          default      { $false }
        }
        if ($shouldMark) { $lines[$i] = $line -replace '^\s*-\s*\[\s\]\s+','- [x] ' }
      }
    }
  }

  # 3) Підрахунок для статистики/логів
  $total = 0; $done = 0; $todo = 0
  foreach ($l in $lines) {
    if ($l -match '^\s*-\s*\[\s*\S?\s*\]\s+') {
      $total++
      if ($l -match '^\s*-\s*\[\s*x\s*\]\s+') { $done++ } else { $todo++ }
    }
  }
  $pct  = if ($total -gt 0) { [math]::Round(($done*100.0)/$total, 1) } else { 0 }

  # 4) (Опційно) фіналізація блоку статистики внизу
  if ($Finalize) {
    # Прибрати попередню статистику (останній блок)
    $statStart = ($lines | Select-String -Pattern '^\s*##\s*📊\s*Статистика виконання\s*$' -SimpleMatch | Select-Object -Last 1).LineNumber
    if ($statStart) {
      $endIdx = $lines.Count - 1
      for ($j=$statStart; $j -lt $lines.Count; $j++) {
        if ($lines[$j] -match '^\s*---\s*$') { $endIdx = $j - 1; break }
      }
      $lines = $lines[0..($statStart-2)] + $lines[($endIdx+1)..($lines.Count-1)]
    }
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $statBlock = @(
      "", "## 📊 Статистика виконання",
      "- Оновлено: $stamp",
      "- Всього пунктів: $total",
      "- Виконано: $done",
      "- Залишилось: $todo",
      "- Прогрес: $pct`%", ""
    )
    $lines = $lines + $statBlock
  }

  # 5) Запис назад
  $lines | Set-Content -Path $Path -Encoding utf8BOM

  return @{ ok = $true; total = $total; done = $done; todo = $todo; pct = $pct }
}

$today  = Get-Date -Format "yyyy-MM-dd"
$stamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$dated  = Join-Path $FocusDir ("CHECKLIST_{0}.md" -f $today)
$latest = Join-Path $FocusDir "TODAY_CHECKLIST.md"

$r1 = Set-ChecklistStatus-AndMaybeFinalize -Status $Status -Path $dated
$r2 = Set-ChecklistStatus-AndMaybeFinalize -Status $Status -Path $latest

# Консольний звіт (виправлена форма форматування -f)
$leaf = Split-Path $dated -Leaf
$report = "📊 {0}`n  Total: {1}`n  Done: {2}`n  Todo: {3}`n  Prog: {4}%" -f $leaf, $r1.total, $r1.done, $r1.todo, $r1.pct
Write-Host $report

# 6) Лог у RestoreLog (якщо увімкнено й є статистика)
if ($WriteRestoreLog -and $r1.ok) {
  try {
    if (-not (Test-Path $RestoreLogPath)) {
      "# Restore Log ($($today))`n" | Set-Content -Path $RestoreLogPath -Encoding utf8BOM
    }
    $line = "- [$stamp] Checklist status: $Status | $leaf | Total={0} | Done={1} | Todo={2} | Prog={3}%" -f $r1.total, $r1.done, $r1.todo, $r1.pct
    Add-Content -Path $RestoreLogPath -Value $line -Encoding utf8BOM
    Write-Host "🧭 RestoreLog оновлено"
  } catch {
    Write-Warning ("Не вдалось оновити RestoreLog: {0}" -f $_.Exception.Message)
  }
}

Write-Host ("✅ Status={0}, Finalize={1}, AutoCheck={2}" -f $Status,$Finalize,$AutoCheck)
Write-Host ("↳ Dated:  {0} ({1})" -f $dated, $(if($r1.ok){"OK"}else{"MISS"}))
Write-Host ("↳ Latest: {0} ({1})" -f $latest,$(if($r2.ok){"OK"}else{"MISS"}))
