<#
Build-DAOAcademyDigest.ps1 — v1.4 (2025-11-06)
- Вбудований шаблон (fallback)
- Коректний Education Index за конкретний місяць
- SHA256 фікс
- Перевірки CSV
- ✅ Автозаповнення KPI-таблиці (Prev / Curr / Δ) для наставників, учнів, сертифікатів, Education Index
#>

[CmdletBinding()]
param(
    [string]$Root = "D:\CHECHA_CORE",
    [string]$Month = (Get-Date -Format "yyyy-MM"),
    [switch]$Hash
)

# ---------- Paths ----------
$Analytics = Join-Path $Root "C07_ANALYTICS"
$Reports   = Join-Path $Root "C03_LOG\reports\DAO_Academy"
$Template  = Join-Path $Root "dao-g\dao-gid\g29-dao-academy\digest\G29_Digest_Template.md"
$OutFile   = Join-Path $Reports "DAO_Academy_Digest_$Month.md"
foreach($p in @($Reports)){ if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }

# ---------- Input files ----------
$mentorshipCsv = Join-Path $Analytics "DAO_Mentorship_Registry.csv"
$certCsv       = Join-Path $Analytics "Cert_Registry.csv"
$metricsCsv1   = Join-Path $Analytics "Education_Metrics.csv"
$metricsCsv2   = Join-Path $Analytics "DAO_Education_Metrics.csv"
$metricsCsv    = if (Test-Path $metricsCsv1){$metricsCsv1} elseif (Test-Path $metricsCsv2){$metricsCsv2} else {$null}

# ---------- Helpers ----------
function Import-CsvSafe { param([string]$Path)
  if (-not (Test-Path $Path)) { return @() }
  try { Import-Csv -LiteralPath $Path } catch { Write-Warning "⚠️ Не вдалося прочитати CSV: $Path — $_"; @() }
}
function Get-Avg ($arr) {
  if (-not $arr -or $arr.Count -eq 0) { return 0 }
  [math]::Round(($arr | Measure-Object -Average | Select-Object -ExpandProperty Average),2)
}
function TryParseDate($obj, $fields) {
  foreach ($f in $fields) {
    $raw = $obj.$f
    if ($null -ne $raw -and "$raw".Trim() -ne "") {
      $d = $null
      try {
        # Універсальний варіант: використовує CultureInfo.InvariantCulture
        if ([System.DateTime]::TryParse($raw,
              [System.Globalization.CultureInfo]::InvariantCulture,
              [System.Globalization.DateTimeStyles]::None,
              [ref]$d)) {
          return $d
        }
      } catch {
        try {
          # fallback для старих версій
          if ([datetime]::TryParse("$raw", [ref]$d)) { return $d }
        } catch { }
      }
    }
  }
  return $null
}
function MonthStr($dt){ $dt.ToString('yyyy-MM') }

# ---------- Load analytics ----------
$mentorship = Import-CsvSafe $mentorshipCsv
$certs      = Import-CsvSafe $certCsv
$metrics    = if ($metricsCsv) { Import-CsvSafe $metricsCsv } else { @() }

# ---------- Health checks ----------
if ($mentorship.Count -eq 0) { Write-Warning "ℹ️ Mentorship CSV порожній або відсутній: $mentorshipCsv" }
if ($certs.Count -eq 0)      { Write-Warning "ℹ️ Cert CSV порожній або відсутній: $certCsv" }
if ($metrics.Count -eq 0)    { Write-Warning "ℹ️ Education Metrics CSV порожній або відсутній: $metricsCsv1 / $metricsCsv2" }

# ---------- Month math ----------
$currMonth = $Month
$prevMonth = ( [datetime]::ParseExact("$Month-01","yyyy-MM-dd",$null).AddMonths(-1) ).ToString("yyyy-MM")

# ---------- Mentors/Students (unique by month when Date exists) ----------
$hasMentor  = ($mentorship | Select-Object -First 1).PSObject.Properties.Name -contains 'Mentor'
$hasStudent = ($mentorship | Select-Object -First 1).PSObject.Properties.Name -contains 'Student'
$mentorDateFields = @('Date','Created','StartDate')

$mentorsCurr = 0; $mentorsPrev = $null
$studentsCurr = 0; $studentsPrev = $null

if ($hasMentor) {
  # Якщо є дати — рахуємо по місяцях; інакше — весь реєстр як поточне, prev = ''
  $haveDates = ($mentorship | ForEach-Object { TryParseDate $_ $mentorDateFields }) -ne $null
  if ($haveDates) {
    $mentorsCurr = ($mentorship | Where-Object { (TryParseDate $_ $mentorDateFields | ForEach-Object { if($_){ MonthStr $_ } }) -contains $currMonth } | Select-Object -ExpandProperty Mentor -Unique | Where-Object {$_}).Count
    $studentsCurr= ($mentorship | Where-Object { (TryParseDate $_ $mentorDateFields | ForEach-Object { if($_){ MonthStr $_ } }) -contains $currMonth } | Select-Object -ExpandProperty Student -Unique | Where-Object {$_}).Count
    $mentorsPrev = ($mentorship | Where-Object { (TryParseDate $_ $mentorDateFields | ForEach-Object { if($_){ MonthStr $_ } }) -contains $prevMonth } | Select-Object -ExpandProperty Mentor -Unique | Where-Object {$_}).Count
    $studentsPrev= ($mentorship | Where-Object { (TryParseDate $_ $mentorDateFields | ForEach-Object { if($_){ MonthStr $_ } }) -contains $prevMonth } | Select-Object -ExpandProperty Student -Unique | Where-Object {$_}).Count
  } else {
    $mentorsCurr  = ($mentorship | Select-Object -ExpandProperty Mentor -Unique | Where-Object {$_}).Count
    $studentsCurr = ($mentorship | Select-Object -ExpandProperty Student -Unique | Where-Object {$_}).Count
    $mentorsPrev  = $null
    $studentsPrev = $null
  }
}

# ---------- Certificates (robust count by month prefix) ----------
function CountCertsByMonth($m){
  if ($certs.Count -eq 0) { return 0 }
  $props = ($certs | Select-Object -First 1).PSObject.Properties.Name
  $dateField = $null
  foreach($f in @('Issued','Date')){ if($props -contains $f){ $dateField = $f; break } }
  if (-not $dateField) { 
    Write-Warning "⚠️ Cert_Registry.csv не має колонок Issued/Date — сертифікати не будуть пораховані."
    return 0
  }
  ($certs | Where-Object {
      $v = $_.$dateField
      $v -and ($v.ToString().Trim().Substring(0, [Math]::Min(7, $v.ToString().Trim().Length)) -eq $m)
    }).Count
}
$certCurr = CountCertsByMonth $currMonth
$certPrev = CountCertsByMonth $prevMonth
# ---------- Education Index (month-aware) ----------
$educationIndexCurr = 0; $educationIndexPrev = $null
if ($metrics.Count -gt 0) {
  $props = ($metrics | Select-Object -First 1).PSObject.Properties.Name
  if ($props -contains 'Metric' -and $props -contains 'Value') {
    $eiCurrVals = $metrics | Where-Object { $_.Metric -eq 'EducationIndex' -and $_.Value -ne '' -and ($_.Date -match [regex]::Escape($currMonth)) } |
      ForEach-Object { $v=$null; [double]::TryParse(("$($_.Value)" -replace ',','.'),[ref]$v)|Out-Null; $v }
    $eiPrevVals = $metrics | Where-Object { $_.Metric -eq 'EducationIndex' -and $_.Value -ne '' -and ($_.Date -match [regex]::Escape($prevMonth)) } |
      ForEach-Object { $v=$null; [double]::TryParse(("$($_.Value)" -replace ',','.'),[ref]$v)|Out-Null; $v }
    $educationIndexCurr = Get-Avg ($eiCurrVals | Where-Object {$_ -ne $null})
    if ($eiPrevVals){ $educationIndexPrev = Get-Avg ($eiPrevVals | Where-Object {$_ -ne $null}) }
  } elseif ($props -contains 'EducationIndex' -and $props -contains 'Date') {
    $eiCurrVals = $metrics | Where-Object { ($_.Date -match [regex]::Escape($currMonth)) -and $_.EducationIndex -ne '' } |
      ForEach-Object { $v=$null; [double]::TryParse(("$($_.EducationIndex)" -replace ',','.'),[ref]$v)|Out-Null; $v }
    $eiPrevVals = $metrics | Where-Object { ($_.Date -match [regex]::Escape($prevMonth)) -and $_.EducationIndex -ne '' } |
      ForEach-Object { $v=$null; [double]::TryParse(("$($_.EducationIndex)" -replace ',','.'),[ref]$v)|Out-Null; $v }
    $educationIndexCurr = Get-Avg ($eiCurrVals | Where-Object {$_ -ne $null})
    if ($eiPrevVals){ $educationIndexPrev = Get-Avg ($eiPrevVals | Where-Object {$_ -ne $null}) }
  }
}

# ---------- Summary counters for console ----------
$mentorsTotal  = if ($hasMentor)  { ($mentorship | Select-Object -ExpandProperty Mentor -Unique | Where-Object {$_}).Count } else { 0 }
$studentsTotal = if ($hasStudent) { ($mentorship | Select-Object -ExpandProperty Student -Unique | Where-Object {$_}).Count } else { 0 }

# ---------- Top mentors (by count) ----------
$topMentors = @()
if ($hasMentor) {
  $topMentors = $mentorship | Group-Object Mentor | Sort-Object Count -Descending | Select-Object -First 3
}

# ---------- Load template (fallback if missing) ----------
if (Test-Path $Template) {
  $templateText = Get-Content -Raw -LiteralPath $Template
} else {
  Write-Warning "❌ Template not found at $Template — using embedded fallback."
  $templateText = @"
# 🗞️ G29 — DAO-Academy Digest  
## Щомісячний звіт Академії Свідомого Лідерства

**Місяць:** [__________]

## 🧭 Підсумки місяця
| Напрям | Події | Статус |
|---|---|---|
| Курси | [ ] | |
| Наставництво | [ ] | |
| Сертифікація | [ ] | |

## 📊 Ключові показники
| Показник | Попередній | Поточний | Δ |
|---|---:|---:|---:|
| Курсів активних | [ ] | [ ] | [ ] |
| Наставників у реєстрі | [ ] | [ ] | [ ] |
| Учнів у програмі | [ ] | [ ] | [ ] |
| Сертифікатів видано | [ ] | [ ] | [ ] |
| Education Index | [ ] | [ ] | [ ] |

## 💬 Цитата місяця
> [ ... ]

**С.Ч. / DAO-GOGS**
"@
}

# ---------- Replace placeholders ----------
$monthName = (Get-Culture).DateTimeFormat.GetMonthName((Get-Date $Month).Month)
$filled = $templateText `
  -replace '\[__________\]', $monthName `
  -replace '\[опис\]', "Автоматичний звіт з DAO-Академії ($monthName)" `
  -replace '\[аналіз тенденції\]', ("Education Index: {0}" -f $educationIndexCurr) `
  -replace '\[короткий опис подій, що відбулись\]', "Автоматично згенерований дайджест за $monthName." `
  -replace '\[акценти на головних досягненнях\]', "Активна робота G29: курси, наставництво, сертифікація." `
  -replace '\[план переходу у наступну фазу\]', "Інтеграція з ITETA і CheCha University."

# ---------- KPI table autofill ----------
function Fmt($x, [int]$dec=0){
  if ($null -eq $x -or "$x" -eq "") { return "" }
  if ($dec -gt 0) { return ("{0:N$dec}" -f [double]$x).Replace(",","." ) }
  return [string]([int]([double]$x))
}
function Delta($curr,$prev,[int]$dec=0){
  if ($null -eq $curr -or $null -eq $prev -or "$prev" -eq "") { return "" }
  $d = [double]$curr - [double]$prev
  if ($dec -gt 0) { return ("{0:+0.$('0'*$dec);-0.$('0'*$dec)}" -f $d).Replace(",",".") }
  return ("{0:+#;-#;0}" -f [int][math]::Round($d,0))
}
function ReplaceRow([string]$text,[string]$label,[string]$prev,[string]$curr,[string]$delta){
  $pattern = "(?m)^\|\s*$([regex]::Escape($label))\s*\|.*$"
  $replacement = "| $label | $prev | $curr | $delta |"
  return [regex]::Replace($text, $pattern, $replacement)
}

$filled = ReplaceRow $filled "Наставників у реєстрі" (Fmt $mentorsPrev) (Fmt $mentorsCurr) (Delta $mentorsCurr $mentorsPrev)
$filled = ReplaceRow $filled "Учнів у програмі"      (Fmt $studentsPrev) (Fmt $studentsCurr) (Delta $studentsCurr $studentsPrev)
$filled = ReplaceRow $filled "Сертифікатів видано"   (Fmt $certPrev)     (Fmt $certCurr)     (Delta $certCurr $certPrev)
$filled = ReplaceRow $filled "Education Index"       (Fmt $educationIndexPrev 2) (Fmt $educationIndexCurr 2) (Delta $educationIndexCurr $educationIndexPrev 2)
# Примітка: "Курсів активних" лишаємо як у шаблоні (немає джерела даних)

# ---------- Optional: Top mentors block if present ----------
if ($topMentors -and ($filled -match '\| \[_____\] \| L2 \| \[ \] \| \[_____\] \| \[_____\] \|')) {
  $mentorBlock = $topMentors | ForEach-Object {
    "| $($_.Name) | L2 | $($_.Count) | Активний наставник | DAO Mentorship |"
  }
  $filled = $filled -replace '\| \[_____\] \| L2 \| \[ \] \| \[_____\] \| \[_____\] \|', ($mentorBlock -join "`n")
}

# ---------- Write output ----------
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutFile, $filled, $utf8)
Write-Host "✅ DAO-Academy Digest створено: $OutFile" -ForegroundColor Green

# ---------- Hash ----------
if ($Hash) {
  $fileHashInfo = Get-FileHash -Algorithm SHA256 -LiteralPath $OutFile
  $hashFile = "$OutFile.sha256.txt"
  "$($fileHashInfo.Hash)  $(Split-Path $OutFile -Leaf)" | Set-Content -LiteralPath $hashFile -Encoding UTF8
  Write-Host "🔐 SHA256: $($fileHashInfo.Hash)"
}

# ---------- Summary ----------
Write-Host "`n=== DAO-Academy Digest Summary ==="
Write-Host ("Mentors: {0} | Students: {1} | Certificates (month): {2} | Education Index: {3}" -f $mentorsTotal, $studentsTotal, $certCurr, $educationIndexCurr)
Write-Host "====================================="
