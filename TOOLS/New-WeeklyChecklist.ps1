<#
.SYNOPSIS
  Створює порожній щотижневий чекліст (Markdown) у REPORTS з датою у назві.

.DESCRIPTION
  - Обчислює період тижня (Пн–Нд) або приймає -WeekStart/-WeekEnd.
  - Створює файл: REPORTS\CHECHA_CHECKLIST_YYYY-MM-DD_to_YYYY-MM-DD.md
  - Вставляє табличний шаблон з чекбоксами.
  - (Опційно) додає запис у REPORTS\CHECKSUMS.txt

.PARAMETER WeekStart
  Дата початку тижня (локальний час). Якщо не задано — наступний понеділок.

.PARAMETER WeekEnd
  Дата кінця тижня. Якщо не задано — неділя відповідного тижня 23:59:59.

.PARAMETER RepoRoot
  Корінь CHECHA_CORE. За замовчуванням: D:\CHECHA_CORE

.PARAMETER UpdateChecksums
  Якщо вказано — оновлює REPORTS\CHECKSUMS.txt записом для нового файлу.

.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass -File "D:\CHECHA_CORE\TOOLS\New-WeeklyChecklist.ps1"

.EXAMPLE
  pwsh -NoProfile -File "D:\CHECHA_CORE\TOOLS\New-WeeklyChecklist.ps1" -WeekStart '2025-10-13' -WeekEnd '2025-10-19' -UpdateChecksums
#>

[CmdletBinding()]
param(
  [datetime]$WeekStart,
  [datetime]$WeekEnd,
  [string]  $RepoRoot = 'D:\CHECHA_CORE',
  [switch]  $UpdateChecksums
)

# ── Вирахувати наступний календарний тиждень (Пн–Нд), якщо не задано вручну
if (-not $WeekStart -or -not $WeekEnd) {
  $now = Get-Date
  $dow = [int]$now.DayOfWeek  # 0=Sun … 6=Sat
  $offsetToMonday = switch ($dow) { 0 {-6} 1 {0} default {1 - $dow} }
  $mondayThisWeek = ($now.Date).AddDays($offsetToMonday)
  $WeekStart = $mondayThisWeek.AddDays(7)               # наступний понеділок
  $WeekEnd   = $WeekStart.AddDays(6).Date.AddHours(23).AddMinutes(59).AddSeconds(59)
}

$reportsDir = Join-Path $RepoRoot 'REPORTS'
$null = New-Item -ItemType Directory -Force -Path $reportsDir

$ws = $WeekStart.ToString('yyyy-MM-dd')
$we = $WeekEnd.ToString('yyyy-MM-dd')
$outName = "CHECHA_CHECKLIST_${ws}_to_${we}.md"
$outPath = Join-Path $reportsDir $outName

# ── Шаблон чекліста (табличний)
$template = @"
# ✅ CHECHA CHECKLIST — BTD 1.0 (Щотижнева перевірка)
**Період:** ${ws} → ${we}  
**Відповідальний:** С.Ч.  

---

## 🔹 Таблиця перевірки

| № | Крок                     | Дія / Що перевірити | Статус |
|---|--------------------------|---------------------|--------|
| 1 | MANIFEST.md              | SHA256 ≠ `—`, статуси коректні (OK/Draft/Error/Planned) | ☐ |
| 2 | CHECKSUMS.txt (C11)      | Хеші збігаються з MANIFEST | ☐ |
| 3 | BTD_Manifest.json        | JSON цілісний, немає `null` | ☐ |
| 4 | C03_LOG                  | Останній коміт зафіксовано, немає `(missing)` | ☐ |
| 5 | REPORTS                  | Останній Digest існує, проблем = 0 | ☐ |
| 6 | Git локально             | `git status` чистий, `git log -1` актуальний | ☐ |
| 7 | GitHub Actions           | `BTD Weekly Digest` = ✅ Success, артефакт доступний | ☐ |

---

## 🔹 Якщо є проблеми
- Missing file → створити/відновити → запустити `Build-BTD-Manifest.ps1`  
- SHA mismatch → перевірити файл, оновити MANIFEST  
- Bad status → відкоригувати вручну  
- Digest errors → прогнати `Build-WeeklyBTD-Digest.ps1` повторно

— _С.Ч._
"@

# ── Створити файл (не перетираємо, якщо вже існує)
if (Test-Path -LiteralPath $outPath) {
  Write-Host "[INFO] Вже існує: $outPath"
} else {
  $template | Set-Content -LiteralPath $outPath -Encoding UTF8
  Write-Host "[OK] Створено: $outPath"
}

# ── Опційне оновлення REPORTS\CHECKSUMS.txt
if ($UpdateChecksums) {
  $checks = Join-Path $reportsDir 'CHECKSUMS.txt'
  $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $outPath).Hash
  $rel = "REPORTS/$outName"
  $line = "{0}  {1}" -f $sha, $rel

  if (Test-Path -LiteralPath $checks) {
    # приберемо старі рядки для цього файлу (якщо відтворюєш)
    $cur = Get-Content -LiteralPath $checks
    $cur = $cur | Where-Object { $_ -notmatch [regex]::Escape($outName) }
    $cur + $line | Set-Content -LiteralPath $checks -Encoding UTF8
  } else {
    $line | Set-Content -LiteralPath $checks -Encoding UTF8
  }
  Write-Host "[OK] CHECKSUMS оновлено: $checks"
}
