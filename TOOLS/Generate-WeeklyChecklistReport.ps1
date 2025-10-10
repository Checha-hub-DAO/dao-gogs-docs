param(
    # Дата завершення тижня (за замовчуванням — сьогодні, локальний час)
    [datetime] $WeekEnd = (Get-Date).Date,

    # Шлях до RestoreLog (залишено для сумісності; використовуй за потреби)
    [string]  $RestoreLogPath = "D:\CHECHA_CORE\C06_FOCUS\FOCUS_RestoreLog.md",

    # Авто-створення тега після генерації та коміту звіту
    [switch]  $AutoTag,

    # Віддалений репозиторій для пушу тегів
    [string]  $Remote = "origin"
)

# ===== Helpers =====
function Info([string]$m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Warn([string]$m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Err ([string]$m){ Write-Host "[ERR]  $m" -ForegroundColor Red }
function Die ([string]$m){ Err $m; exit 1 }

# ===== Константи/шляхи =====
$RepoRoot   = "D:\CHECHA_CORE"
$ReportsDir = Join-Path $RepoRoot "REPORTS"
$TagScript  = "D:\CHECHA_CORE\TOOLS\New-WeeklyTag.ps1"
$ExpectedBranch = "reports"   # за потреби зміни або зроби '' щоб вимкнути перевірку

# ===== Preflight: repo, гілка =====
if (!(Test-Path -LiteralPath $RepoRoot)) { Die "RepoRoot не знайдено: $RepoRoot" }
Push-Location $RepoRoot
try {
    git rev-parse --is-inside-work-tree *>$null
    if ($LASTEXITCODE -ne 0) { Die "Тека не є git-репозиторієм: $RepoRoot" }

    $curBranch = (git rev-parse --abbrev-ref HEAD).Trim()
    if ($ExpectedBranch -and $curBranch -ne $ExpectedBranch) {
        Die "Очікувалась гілка '$ExpectedBranch', поточна — '$curBranch'."
    }

    # ===== Обчислення інтервалу за схемою 1–7, 8–14, 15–21, 22–кінець =====
    $WeekEnd   = $WeekEnd.Date
    $blockStartDay = [math]::Floor(($WeekEnd.Day - 1) / 7) * 7 + 1
    $WeekStart = Get-Date -Year $WeekEnd.Year -Month $WeekEnd.Month -Day $blockStartDay
    $WeekEnd   = $WeekStart.AddDays(6)
    $endOfMonth = (Get-Date -Year $WeekStart.Year -Month $WeekStart.Month -Day 1).AddMonths(1).AddDays(-1)
    if ($WeekEnd -gt $endOfMonth) { $WeekEnd = $endOfMonth }

    $startStr = $WeekStart.ToString('yyyy-MM-dd')
    $endStr   = $WeekEnd.ToString('yyyy-MM-dd')

    # ===== Імена файлів звіту =====
    $reportName = "WeeklyChecklist_{0}_to_{1}.md" -f $startStr, $endStr
    $reportRel  = "REPORTS/$reportName"
    $reportAbs  = Join-Path $ReportsDir $reportName

    # ===== Підготовка каталогу REPORTS =====
    $null = New-Item -ItemType Directory -Force -Path $ReportsDir

   # ===== Генерація/оновлення вмісту звіту (повніший варіант) =====

# Шляхи джерел (за потреби підкоригуй)
$MatRestoreCsv   = "D:\CHECHA_CORE\C07_ANALYTICS\MAT_RESTORE.csv"
$ItetaCsv        = "D:\CHECHA_CORE\ITETA\reports\ITETA_Dashboard.csv"
$ChecksumList    = "D:\CHECHA_CORE\REPORTS\CHECKSUMS.txt"   # формат: "<sha256>  <relpath>"
$TopN            = 5

function TryReadCsv($path){
  if (!(Test-Path -LiteralPath $path)) { return @() }
  try {
    Import-Csv -LiteralPath $path
  } catch { @() }
}

function TopN-ByScore($rows, [int]$n, [string]$scoreCol='score', [string]$titleCol='title'){
  if (-not $rows -or -not $rows.Count) { return @() }
  $rows |
    Where-Object { $_.$scoreCol -as [double] } |
    Sort-Object { [double]($_.$scoreCol) } -Descending |
    Select-Object -First $n
}

function Get-FileSha256Hex($absPath){
  if (!(Test-Path -LiteralPath $absPath)) { return $null }
  (Get-FileHash -Algorithm SHA256 -LiteralPath $absPath).Hash.ToLower()
}

# 1) Дані: MAT_RESTORE (Top-N)
$matRows = TryReadCsv $MatRestoreCsv
$topMat  = TopN-ByScore $matRows $TopN 'score' 'name'  # очікується колонка 'score' і 'name'

# 2) Дані: ITETA KPI (простий підсумок)
$itetaRows = TryReadCsv $ItetaCsv
$kpiSummary = @()
if ($itetaRows.Count -gt 0) {
  # приклад: шукаємо кілька метрик якщо є
  $kpiMap = @{
    'AI_Efficiency' = 'AI_Efficiency'
    'Info_Fatigue'  = 'Info_Fatigue'
    'Synergy_Index' = 'Synergy_Index'
  }
  foreach($k in $kpiMap.Keys){
    $col = $kpiMap[$k]
    $val = ($itetaRows[-1].$col)  # беремо останній рядок як «свіжий»
    if ($val){ $kpiSummary += ("- **{0}:** {1}" -f $k, $val) }
  }
}

# 3) Хвіст RestoreLog
$restoreTail = @()
if (Test-Path -LiteralPath $RestoreLogPath) {
  $restoreTail = Get-Content -LiteralPath $RestoreLogPath -Tail 20
}

# 4) Контроль цілісності (SHA-256) для файлів звіту за тиждень (опційно)
$checksumSection = @()
if (Test-Path -LiteralPath $ChecksumList) {
  $lines = Get-Content -LiteralPath $ChecksumList
  foreach($ln in $lines){
    if ($ln -match '^(?<sha>[0-9a-fA-F]{64})\s+\*?(?<rel>.+)$'){
      $sha = $Matches['sha'].ToLower()
      $rel = $Matches['rel']
      # Перевіряємо тільки файли, що відносяться до цього тижня
      if ($rel -like ("REPORTS/WeeklyChecklist_{0}_to_{1}*" -f $startStr,$endStr)) {
        $abs = Join-Path $RepoRoot $rel
        $calc = Get-FileSha256Hex $abs
        $ok = ($calc -eq $sha)
        $checksumSection += ("- `{0}` · SHA256 {1}" -f $rel, ($(if($ok){"OK"}else{"MISMATCH: $calc vs $sha"})))
      }
    }
  }
}

# 5) Монтаж Markdown
$md = @()
$md += "# Weekly Checklist ($startStr → $endStr)"
$md += ""
$md += "- Згенеровано: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$md += "- Гілка: $curBranch"
$md += "- Звіт-файл: $reportRel"
$md += ""

# KPI (ITETA)
$md += "## KPI (ITETA)"
if ($kpiSummary.Count) { $md += $kpiSummary } else { $md += "_немає даних_" }
$md += ""

# Матриця відновлення — Top-$TopN
$md += "## Матриця відновлення — Top-$TopN"
if ($topMat.Count) {
  $md += "| Позиція | Оцінка | Назва/Елемент |"
  $md += "|---:|---:|---|"
  $i = 1
  foreach($r in $topMat){
    $score = [string]$r.score
    $name  = $r.name ?? $r.title ?? "(без назви)"
    $md += ("| {0} | {1} | {2} |" -f $i, $score, $name)
    $i++
  }
} else {
  $md += "_немає даних або невірні колонки (очікуються `score`, `name`)_"
}
$md += ""

# Restore Log (tail)
$md += "## Restore Log (останні 20)"
$md += '```text'
$md += ($(if($restoreTail.Count){$restoreTail}else{"(порожньо)" }))
$md += '```'
$md += ""

# Контроль цілісності
$md += "## Контроль цілісності (SHA-256)"
if ($checksumSection.Count) { $md += $checksumSection } else { $md += "_немає записів для цього інтервалу_" }
$md += ""

# Записуємо
$md -join "`r`n" | Set-Content -LiteralPath $reportAbs -Encoding UTF8
Info "Звіт сформовано: $reportRel"

    # ===== Коміт змін (якщо є) =====
    git add -A *>$null
    $hasChanges = -not [string]::IsNullOrWhiteSpace((git status --porcelain))
    if ($hasChanges) {
        $msg = "WeeklyChecklist update: {0} → {1}" -f $startStr, $endStr
        git commit -m $msg *>$null
        Info "Коміт виконано: $msg"
    } else {
        Info "Змін для коміту немає."
    }

    # ===== Опційний авто-тег =====
    if ($AutoTag) {
        if (!(Test-Path -LiteralPath $TagScript)) {
            Warn "Не знайдено $TagScript — пропускаю авто-тег."
        } else {
            Info "Авто-тег: запускаю $TagScript…"
            & pwsh -NoProfile -ExecutionPolicy Bypass -File $TagScript `
                -RepoRoot $RepoRoot `
                -Remote   $Remote  | Write-Host
        }
    }

    # ===== Фінальна довідка =====
    Info ("Готово: {0}" -f $reportRel)
}
finally {
    Pop-Location
}
