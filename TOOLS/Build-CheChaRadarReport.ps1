<# 
.SYNOPSIS
  Build-CheChaRadarReport.ps1 — інтеграційний сканер/збирач CheCha Radar.

.DESCRIPTION
  Читає INSTRUMENTS_MAP_v1.0.md та InfoField_Map_v1.0.md, парсить markdown-таблиці,
  рахує індикатори, формує Radar Index, створює:
    - CheCha_Radar_<date>_<version>.md
    - CheCha_Radar_<date>_<version>.html
    - CheCha_Radar_Summary_<date>.csv
    - SIG-MATRIX_<date>.csv
    - CHECKSUMS.txt (SHA256)
  Працює без зовнішніх модулів. Вихід за замовчуванням у C07_ANALYTICS.

.PARAMETER RepoRoot
  Корінь CHECHA_CORE. За замовчуванням: D:\CHECHA_CORE

.PARAMETER InstrumentsMap
  Шлях до INSTRUMENTS_MAP_v1.0.md. За замовчуванням: $RepoRoot\C12_KNOWLEDGE\MD_SYSTEM\INSTRUMENTS_MAP_v1.0.md
  (якщо відсутній — буде спроба знайти у C06_FOCUS)

.PARAMETER InfoFieldMap
  Шлях до InfoField_Map_v1.0.md. За замовчуванням: $RepoRoot\C12_KNOWLEDGE\MD_SYSTEM\InfoField_Map_v1.0.md
  (якщо відсутній — буде спроба знайти у C06_FOCUS)

.PARAMETER OutDir
  Тека для виводу. За замовчуванням: $RepoRoot\C07_ANALYTICS

.PARAMETER Version
  Версія дашборда. За замовчуванням: v1.0

.PARAMETER DateTag
  Дата у форматі yyyy-MM-dd. За замовчуванням: сьогодні (за локальним часом).

.PARAMETER DryRun
  Якщо вказано — показує обчислення без запису файлів.

.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass `
    -File D:\CHECHA_CORE\TOOLS\Build-CheChaRadarReport.ps1 `
    -Version v1.0

.NOTES
  Автор: С.Ч. | Контроль: ITETA / SKD-GOGS
#>

[CmdletBinding()]
param(
  [string]$RepoRoot     = "D:\CHECHA_CORE",
  [string]$InstrumentsMap = "",
  [string]$InfoFieldMap   = "",
  [string]$OutDir       = "",
  [string]$Version      = "v1.0",
  [string]$DateTag      = (Get-Date).ToString('yyyy-MM-dd'),
  [switch]$DryRun
)

# ---------- Helpers ----------
function New-Utf8BomWriter([string]$Path){
  $enc = New-Object System.Text.UTF8Encoding($false) # без BOM
  # Створимо файл і вручну додамо BOM, потім писатимемо в кінець
  [byte[]]$bom = 0xEF,0xBB,0xBF
  [System.IO.File]::WriteAllBytes($Path, $bom)
  $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
  return New-Object System.IO.StreamWriter($fs, $enc)
}

function Write-Log {
  param([string]$Message, [string]$Level = "INFO")
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Write-Host "[$Level] $ts $Message"
}

function Read-FileUtf8([string]$Path){
  if(!(Test-Path -LiteralPath $Path)){ throw "Файл не знайдено: $Path" }
  return [System.IO.File]::ReadAllText($Path,[System.Text.Encoding]::UTF8)
}

# Парсер markdown-таблиць: повертає список PSCustomObject
function Parse-MarkdownTables {
  param([string]$Markdown)
  # Знайдемо всі блоки таблиць між рядками з '|' (простий, але надійний для наших карт)
  $lines = $Markdown -split "`r?`n"
  $tables = @()
  $i = 0
  while($i -lt $lines.Count){
    if($lines[$i] -match '^\s*\|.*\|\s*$'){
      # хедер
      $header = $lines[$i].Trim()
      # наступний рядок повинен бути роздільником ---|---|---
      if($i+1 -lt $lines.Count -and $lines[$i+1] -match '^\s*\|\s*:?-{3,}.*\|\s*$'){
        $j = $i+2
        $rows = @()
        while($j -lt $lines.Count -and $lines[$j] -match '^\s*\|.*\|\s*$'){
          $rows += $lines[$j].Trim()
          $j++
        }
        # Розібрати заголовки
        $cols = ($header.Trim('|') -split '\|').ForEach({ $_.Trim() })
        $objects = @()
        foreach($r in $rows){
          $vals = ($r.Trim('|') -split '\|').ForEach({ $_.Trim() })
          if($vals.Count -lt $cols.Count){
            # доповнити порожніми
            $vals = $vals + (,@('') * ($cols.Count - $vals.Count))
          }
          $obj = [ordered]@{}
          for($k=0;$k -lt $cols.Count;$k++){
            $obj[$cols[$k]] = $vals[$k]
          }
          $objects += [pscustomobject]$obj
        }
        $tables += [pscustomobject]@{
          StartLine = $i
          EndLine   = $j-1
          Columns   = $cols
          Rows      = $objects
        }
        $i = $j
        continue
      }
    }
    $i++
  }
  return $tables
}

# Витяг статус-емодзі → нормалізований стан
function Normalize-Status([string]$s){
  if(-not $s){ return "unknown" }
  if($s -match '🟢|Active|Stable'){ return "active" }
  if($s -match '🟡|Testing|In\s*progress'){ return "testing" }
  if($s -match '🔵|Planned|Design'){ return "planned" }
  if($s -match '🟠'){ return "progress" }
  if($s -match '🔴'){ return "blocked" }
  return $s.ToLower()
}

# Обчислення простих метрик по таблиці інструментів
function Compute-InstrumentsMetrics($tables){
  $all = @()
  foreach($t in $tables){
    foreach($r in $t.Rows){
      # шукатимемо колонку "Статус" або подібні
      $statusVal = $null
      foreach($c in $t.Columns){
        if($c -match 'Статус|Status'){ $statusVal = $r.$c; break }
      }
      if($statusVal){
        $all += Normalize-Status $statusVal
      }
    }
  }
  if($all.Count -eq 0){
    return @{
      ActiveShare  = 0.0
      CleanShare   = 0.0
      TestingShare = 0.0
      PlannedShare = 0.0
      Total        = 0
    }
  }
  $total   = [double]$all.Count
  $active  = ($all | Where-Object {$_ -eq 'active'}).Count / $total
  $testing = ($all | Where-Object {$_ -eq 'testing'}).Count / $total
  $planned = ($all | Where-Object {$_ -eq 'planned'}).Count / $total
  # "чистота" як 1 - частка blocked/progress/unknown
  $dirty   = ($all | Where-Object {$_ -in @('blocked','unknown')}).Count / $total
  $clean   = [math]::Max(0.0, 1.0 - $dirty)

  return @{
    ActiveShare  = [math]::Round($active, 4)
    CleanShare   = [math]::Round($clean, 4)
    TestingShare = [math]::Round($testing, 4)
    PlannedShare = [math]::Round($planned, 4)
    Total        = [int]$total
  }
}

# Витяг таблиці "КАРТА СИГНАЛІВ" з InfoField_Map для SIG-MATRIX.csv
function Extract-Signals($infoTables){
  # шукати таблицю, яка містить колонки "Категорія", "Приклад сигналу", "Джерело", "Рівень пріоритету"
  foreach($t in $infoTables){
    $names = ($t.Columns | ForEach-Object {$_.ToLower()})
    if($names -contains 'категорія' -and $names -contains 'джерело' -and ($names -contains 'приклад сигналу' -or $names -contains 'приклад') ){
      return $t.Rows
    }
  }
  return @()
}

# Дуже проста "конвертація" markdown → html (мінімально)
function Convert-MarkdownToHtml([string]$md){
  # Проста заміна заголовків і код-блоків. Для наших цілей вистачить.
  $html = $md
  $html = $html -replace '```mermaid','<pre class="mermaid">'
  $html = $html -replace '```','</pre>'
  $html = $html -replace '^\#\#\#\#\#\# (.*)$','<h6>$1</h6>' -replace '^\#\#\#\#\# (.*)$','<h5>$1</h5>' -replace '^\#\#\#\# (.*)$','<h4>$1</h4>' -replace '^\#\#\# (.*)$','<h3>$1</h3>' -replace '^\#\# (.*)$','<h2>$1</h2>' -replace '^\# (.*)$','<h1>$1</h1>'
  $html = $html -replace '\*\*(.*?)\*\*','<strong>$1</strong>'
  $html = $html -replace '\*(.*?)\*','<em>$1</em>'
  $html = $html -replace "`r?`n","`n"
  # Обгорнемо в базовий шаблон
  return @"
<!DOCTYPE html>
<html lang="uk">
<head>
<meta charset="utf-8"/>
<title>CheCha Radar Report</title>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<style>
  body{font-family: -apple-system, Segoe UI, Roboto, Arial, sans-serif; margin:24px; line-height:1.5}
  table{border-collapse:collapse; width:100%; margin:16px 0}
  th,td{border:1px solid #ddd; padding:8px}
  th{background:#f7f7f7; text-align:left}
  code, pre{background:#0f172a; color:#e2e8f0; padding:8px; border-radius:8px; display:block; overflow:auto}
  .muted{color:#666}
</style>
</head>
<body>
$html
</body>
</html>
"@
}

# Обчислення Radar Index (простий, прозорий агрегат)
function Compute-RadarIndex($instMetrics, $sigRows){
  # Стабільність системи ≈ частка active серед інструментів + 0.5*planned (нормовано)
  $stability = [math]::Min(1.0, $instMetrics.ActiveShare + 0.5*$instMetrics.PlannedShare)
  # Чистота поля ≈ CleanShare
  $clean     = $instMetrics.CleanShare
  # Комунікаційна синхронізація: приблизно за кількістю ненизьких пріоритетів у SIG-MATRIX (🔹/високий, 🔸/середній)
  $sync = 0.8
  if($sigRows.Count -gt 0){
    $high = ($sigRows | Where-Object { $_.'Рівень пріоритету' -match 'Висок' -or $_.'Рівень пріоритету' -match '🔹' }).Count
    $mid  = ($sigRows | Where-Object { $_.'Рівень пріоритету' -match 'Середн' -or $_.'Рівень пріоритету' -match '🔸' }).Count
    $sync = [math]::Min(1.0, ($high*1.0 + $mid*0.7) / [math]::Max(1.0, $sigRows.Count))
  }
  # Освітня активність — приблизно від planned+active (припущення: освіта зростає з планами та активами)
  $edu  = [math]::Min(1.0, 0.6*$instMetrics.ActiveShare + 0.4*$instMetrics.PlannedShare + 0.1)
  # Аналітична інтеграція — близько до (active + testing), бо інтеграція росте з експериментами
  $anal = [math]::Min(1.0, $instMetrics.ActiveShare + 0.5*$instMetrics.TestingShare)

  return [pscustomobject]@{
    SystemStability   = [math]::Round($stability,2)
    InfoCleanliness   = [math]::Round($clean,2)
    CommSync          = [math]::Round($sync,2)
    EducationActivity = [math]::Round($edu,2)
    AnalyticIntegration = [math]::Round($anal,2)
  }
}

# --- Prepare SIG-MATRIX block for Markdown (no $() inside here-string) ---
if ($sigRows.Count -gt 0) {
  $exportName = Split-Path -Leaf $outSig
  $sigBlock = "**Експорт:** " + ('`' + $exportName + '`')
} else {
  $sigBlock = "_Дані не виявлено в InfoField_Map (секція КАРТА СИГНАЛІВ)._"
}

# ---------- Locate inputs ----------
if(-not $OutDir){ $OutDir = Join-Path $RepoRoot 'C07_ANALYTICS' }
if(!(Test-Path -LiteralPath $OutDir)){ New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

if(-not $InstrumentsMap){
  $p1 = Join-Path $RepoRoot 'C12_KNOWLEDGE\MD_SYSTEM\INSTRUMENTS_MAP_v1.0.md'
  $p2 = Join-Path $RepoRoot 'C06_FOCUS\INSTRUMENTS_MAP_v1.0.md'
  $InstrumentsMap = (Test-Path $p1) ? $p1 : $p2
}
if(-not $InfoFieldMap){
  $p1 = Join-Path $RepoRoot 'C12_KNOWLEDGE\MD_SYSTEM\InfoField_Map_v1.0.md'
  $p2 = Join-Path $RepoRoot 'C06_FOCUS\InfoField_Map_v1.0.md'
  $InfoFieldMap = (Test-Path $p1) ? $p1 : $p2
}

Write-Log "RepoRoot      : $RepoRoot"
Write-Log "InstrumentsMap: $InstrumentsMap"
Write-Log "InfoFieldMap  : $InfoFieldMap"
Write-Log "OutDir        : $OutDir"
Write-Log "Version/Date  : $Version / $DateTag"

# ---------- Read & parse ----------
$instMd = Read-FileUtf8 $InstrumentsMap
$infoMd = Read-FileUtf8 $InfoFieldMap

$instTables = Parse-MarkdownTables $instMd
$infoTables = Parse-MarkdownTables $infoMd

$instMetrics = Compute-InstrumentsMetrics $instTables
$sigRows     = Extract-Signals $infoTables
$index       = Compute-RadarIndex $instMetrics $sigRows

Write-Log ("Instruments total rows: {0}" -f $instMetrics.Total)
Write-Log ("Signals rows          : {0}" -f $sigRows.Count)
Write-Log ("Index: Stability={0} Clean={1} Sync={2} Edu={3} Anal={4}" -f `
  $index.SystemStability,$index.InfoCleanliness,$index.CommSync,$index.EducationActivity,$index.AnalyticIntegration)

# ---------- Compose outputs ----------
$baseName = "CheCha_Radar_{0}_{1}" -f $DateTag, $Version
$outMd    = Join-Path $OutDir ($baseName + ".md")
$outHtml  = Join-Path $OutDir ($baseName + ".html")
$outCsv   = Join-Path $OutDir ("CheCha_Radar_Summary_{0}.csv" -f $DateTag)
$outSig   = Join-Path $OutDir ("SIG-MATRIX_{0}.csv" -f $DateTag)
$outSha   = Join-Path $OutDir "CHECKSUMS.txt"

# Summary CSV
$summaryRows = @(
  [pscustomobject]@{ Metric="SystemStability";   Value=$index.SystemStability }
  [pscustomobject]@{ Metric="InfoCleanliness";   Value=$index.InfoCleanliness }
  [pscustomobject]@{ Metric="CommSync";          Value=$index.CommSync }
  [pscustomobject]@{ Metric="EducationActivity"; Value=$index.EducationActivity }
  [pscustomobject]@{ Metric="AnalyticIntegration"; Value=$index.AnalyticIntegration }
  [pscustomobject]@{ Metric="ActiveShare";       Value=$instMetrics.ActiveShare }
  [pscustomobject]@{ Metric="TestingShare";      Value=$instMetrics.TestingShare }
  [pscustomobject]@{ Metric="PlannedShare";      Value=$instMetrics.PlannedShare }
  [pscustomobject]@{ Metric="ToolsTotal";        Value=$instMetrics.Total }
)

# SIG-MATRIX CSV (якщо є)
if($sigRows.Count -gt 0){
  $sigRows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $outSig
}

# Markdown Dashboard
$mdContent = @"
# 🛰️ CHECHA_RADAR_${Version}
**Дата:** ${DateTag}  
**Автор:** С.Ч.  
**Контроль:** ITETA / SKD-GOGS

---

## 📊 Radar Index
| Параметр | Значення |
|---|---:|
| Стабільність системи | ${($index.SystemStability).ToString("0.00")} |
| Інформаційна чистота | ${($index.InfoCleanliness).ToString("0.00")} |
| Комунікаційна синхронізація | ${($index.CommSync).ToString("0.00")} |
| Освітня активність | ${($index.EducationActivity).ToString("0.00")} |
| Аналітична інтеграція | ${($index.AnalyticIntegration).ToString("0.00")} |

> *Формується з INSTRUMENTS_MAP та InfoField_Map (таблиці статусів і SIG-MATRIX).*

---

## ⚙️ Метрики інструментів
| Показник | Значення |
|---|---:|
| Частка Active/Stable | ${($instMetrics.ActiveShare).ToString("0.00")} |
| Частка Testing | ${($instMetrics.TestingShare).ToString("0.00")} |
| Частка Planned | ${($instMetrics.PlannedShare).ToString("0.00")} |
| Інструментів у вибірці | ${$instMetrics.Total} |

---

## 🔁 Джерела сигналів (SIG-MATRIX)
$sigBlock

## 🧭 Примітки
- Розрахунки прості та прозорі: **active/stable/testing/planned** зчитуються з колонок **Статус/Status** у markdown-таблицях.
- Значення можна уточнювати, підключивши додаткові джерела (Looker, CSV з матриць).
- Для HTML-версії використовується базова конвертація (без зовнішніх модулів).

**Підпис:** С.Ч.
"@

# ---------- Write files ----------
if($DryRun){
  Write-Log "[DRYRUN] ${outMd}"
  Write-Log "[DRYRUN] ${outHtml}"
  Write-Log "[DRYRUN] ${outCsv}"
  if($sigRows.Count -gt 0){ Write-Log "[DRYRUN] ${outSig}" }
  exit 0
}

# Markdown (UTF-8 BOM)
$sw = New-Utf8BomWriter $outMd
$sw.Write($mdContent)
$sw.Flush(); $sw.Dispose()

# HTML
$html = Convert-MarkdownToHtml $mdContent
[System.IO.File]::WriteAllText($outHtml, $html, [System.Text.Encoding]::UTF8)

# Summary CSV
$summaryRows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $outCsv

# CHECKSUMS
$hashes = @()
foreach($f in @($outMd,$outHtml,$outCsv)){
  if(Test-Path $f){
    $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $f).Hash
    $hashes += "{0}  {1}" -f $h, (Split-Path -Leaf $f)
  }
}
if(Test-Path $outSig){
  $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $outSig).Hash
  $hashes += "{0}  {1}" -f $h, (Split-Path -Leaf $outSig)
}
$sw2 = New-Utf8BomWriter $outSha
$sw2.WriteLine("# CHECKSUMS (SHA-256)")
$sw2.WriteLine("# Date: $DateTag  Version: $Version")
$hashes | ForEach-Object { $sw2.WriteLine($_) }
$sw2.Flush(); $sw2.Dispose()

Write-Log "DONE. Radar files:"
Write-Log " - $outMd"
Write-Log " - $outHtml"
Write-Log " - $outCsv"
if(Test-Path $outSig){ Write-Log " - $outSig" }
Write-Log " - $outSha"

try {
  & "D:\CHECHA_CORE\TOOLS\Write-MetaLayerEntry.ps1" `
    -Event "CheCha_Radar $Version" `
    -Intent "Добовий зріз Radar Index" `
    -Observation "Згенеровано md/html/csv; перевірено SHA256." `
    -Insight "Коливання індексів пов'язане з Testing→Active." `
    -EmotionalTone "глибина" `
    -BalanceShift 0.15 `
    -MetaIndex $index.SystemStability `
    -Tags Analytic,Tech,Balance
} catch {
  Write-Host "[WARN] MetaLayer log append failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- [META LAYER LOG APPEND] --------------------------------------------
try {
    $metaScript = "D:\CHECHA_CORE\TOOLS\Write-MetaLayerEntry.ps1"
    if (Test-Path $metaScript) {
        & $metaScript `
          -Event ("CheCha_Radar " + $Version) `
          -Intent "Добовий зріз Radar Index" `
          -Observation "Згенеровано md/html/csv; перевірено SHA256." `
          -Insight "Коливання індексів пов'язане з Testing->Active." `
          -EmotionalTone "глибина" `
          -BalanceShift 0.15 `
          -MetaIndex 0.78 `
          -Tags Analytic,Tech,Balance
    } else {
        Write-Host "[WARN] META script not found: $metaScript" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "[WARN] Failed to append META entry: $($_.Exception.Message)" -ForegroundColor Yellow
}
# -------------------------------------------------------------------------

# --- ДО ДОДАВАННЯ $mdContent: підготуй $sigBlock ---
if ($sigRows.Count -gt 0) {
  $exportName = Split-Path -Leaf $outSig
  # робимо markdown-обрамлення ім’я файлу у зворотні лапки без небезпечної інтерполяції
  $sigBlock = "**Експорт:** " + ('`' + $exportName + '`')
} else {
  $sigBlock = "_Дані не виявлено в InfoField_Map (секція КАРТА СИГНАЛІВ)._"
}

# --- ТЕПЕР ФОРМУЄМО $mdContent (без умов усередині here-string) ---
$mdContent = @"
# 🛰️ CHECHA_RADAR_${Version}
**Дата:** ${DateTag}  
**Автор:** С.Ч.  
**Контроль:** ITETA / SKD-GOGS

---

## 📊 Radar Index
| Параметр | Значення |
|---|---:|
| Стабільність системи | ${($index.SystemStability).ToString("0.00")} |
| Інформаційна чистота | ${($index.InfoCleanliness).ToString("0.00")} |
| Комунікаційна синхронізація | ${($index.CommSync).ToString("0.00")} |
| Освітня активність | ${($index.EducationActivity).ToString("0.00")} |
| Аналітична інтеграція | ${($index.AnalyticIntegration).ToString("0.00")} |

> *Формується з INSTRUMENTS_MAP та InfoField_Map (таблиці статусів і SIG-MATRIX).*

---

## ⚙️ Метрики інструментів
| Показник | Значення |
|---|---:|
| Частка Active/Stable | ${($instMetrics.ActiveShare).ToString("0.00")} |
| Частка Testing | ${($instMetrics.TestingShare).ToString("0.00")} |
| Частка Planned | ${($instMetrics.PlannedShare).ToString("0.00")} |
| Інструментів у вибірці | ${$instMetrics.Total} |

---

## 🔁 Джерела сигналів (SIG-MATRIX)
$sigBlock

---

## 🧭 Примітки
- Розрахунки прості та прозорі: **active/stable/testing/planned** зчитуються з колонок **Статус/Status** у markdown-таблицях.
- Значення можна уточнювати, підключивши додаткові джерела (Looker, CSV з матриць).
- Для HTML-версії використовується базова конвертація (без зовнішніх модулів).

**Підпис:** С.Ч.
"@

