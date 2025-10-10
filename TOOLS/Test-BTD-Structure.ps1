<#
.SYNOPSIS
  Перевірка структури BTD 1.0 за MANIFEST.md (SKD-валідація).

.DESCRIPTION
  - Парсить таблицю в секції "## 🔹 Складові (ключові файли)" MANIFEST.md
  - Для кожного запису:
      * Перевіряє існування файлу (відносно $RepoRoot)
      * Рахує SHA256 і порівнює з тим, що записано в MANIFEST (якщо там не '—')
      * Валідує поле Status проти дозволених: OK, Draft, Error, Planned
  - Шукає «зайві» файли у важливих директоріях (за бажанням)
  - Формує Markdown-звіт у REPORTS
  - Повертає exit code:
      0 = OK (критичних помилок немає)
      1 = Errors (відсутні файли / хибні SHA / недопустимі статуси)

.PARAMETER ManifestPath
  Шлях до MANIFEST.md (default: D:\CHECHA_CORE\C11\MANIFEST.md)

.PARAMETER RepoRoot
  Корінь репозиторію (default: D:\CHECHA_CORE)

.PARAMETER ScanExtra
  Сканувати «зайві» файли (C07_ANALYTICS, C11, C12_KNOWLEDGE, INBOX, REPORTS, EXPORTS, SKD)

.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass -File "D:\CHECHA_CORE\TOOLS\Test-BTD-Structure.ps1" -ScanExtra

.NOTES
  Нічого не модифікує — лише читає і звітує.
#>

[CmdletBinding()]
param(
  [string]$ManifestPath = 'D:\CHECHA_CORE\C11\MANIFEST.md',
  [string]$RepoRoot     = 'D:\CHECHA_CORE',
  [switch]$ScanExtra
)

$ErrorActionPreference = 'Stop'

# -------- helpers --------
function Join-RepoPath {
  param([string]$RelPath)
  if ([string]::IsNullOrWhiteSpace($RelPath)) { return $null }
  $rel = $RelPath -replace '[\\/]+','\' ; $rel = $rel.TrimStart('\')
  Join-Path -Path $RepoRoot -ChildPath $rel
}

function Parse-ManifestTable {
  param([string]$Markdown)
  $start = '## 🔹 Складові (ключові файли)'
  $end   = '## 🔹 Примітки'
  $sIdx = $Markdown.IndexOf($start)
  if ($sIdx -lt 0) { throw "Не знайдено секцію: $start" }
  $after = $Markdown.Substring($sIdx)
  $eRel = $after.IndexOf($end)
  $block = if ($eRel -lt 0) { $after } else { $after.Substring(0,$eRel) }

  $lines = $block -split "`r?`n"
  # знайти перший рядок таблиці (рядок заголовка з '|')
  $hdrLineNum = ($lines | Select-String -Pattern '^\s*\|.*\|\s*$' | Select-Object -First 1).LineNumber
  if (-not $hdrLineNum) { throw "Не знайдено таблицю MANIFEST у секції" }

  # тіло після рядка-розділювача
  $body = New-Object System.Collections.Generic.List[object]
  for ($i = $hdrLineNum + 1; $i -lt $lines.Count; $i++) {
    $ln = $lines[$i]
    if ($ln -notmatch '^\s*\|') { break }
    if ($ln -match '^\s*\|\s*-+') { continue } # пропустити лінію '-----'
    # розбити клітинки
    $cells = ($ln -split '\|') | ForEach-Object { $_.Trim() }
    $cells = $cells | Where-Object { $_ -ne '' }
    if ($cells.Count -lt 5) { continue }
    $body.Add([pscustomobject]@{
      Code   = $cells[0]
      Name   = $cells[1]
      Rel    = $cells[2]
      SHA    = $cells[3]
      Status = $cells[4]
      RawRow = $ln
    }) | Out-Null
  }
  return $body
}

function Compute-Sha256 {
  param([string]$FullPath)
  if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) { return $null }
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $FullPath).Hash
}

# -------- read manifest --------
if (-not (Test-Path -LiteralPath $ManifestPath)) {
  throw "MANIFEST.md не знайдено: $ManifestPath"
}
$md = Get-Content -LiteralPath $ManifestPath -Raw
$rows = Parse-ManifestTable -Markdown $md

$allowedStatuses = @('OK','Draft','Error','Planned')
$problems = New-Object System.Collections.Generic.List[object]
$summary  = New-Object System.Collections.Generic.List[object]

foreach ($r in $rows) {
  $full = Join-RepoPath -RelPath $r.Rel
  $exists = if ($full) { Test-Path -LiteralPath $full -PathType Leaf } else { $false }
  $calcSha = if ($exists) { Compute-Sha256 -FullPath $full } else { $null }

  $statusOk = $allowedStatuses -contains $r.Status
  $shaOk = $true
  if ($exists -and $r.SHA -and $r.SHA -ne '—') {
    $shaOk = ($r.SHA.Trim().ToLower() -eq $calcSha.ToLower())
  }

  if (-not $exists) {
    $problems.Add([pscustomobject]@{
      Type='Missing'; Code=$r.Code; Name=$r.Name; Path=$r.Rel; Detail='Файл відсутній'
    }) | Out-Null
  }

  if ($exists -and -not $shaOk) {
    $problems.Add([pscustomobject]@{
      Type='SHA_Mismatch'; Code=$r.Code; Name=$r.Name; Path=$r.Rel; Detail="MANIFEST=$($r.SHA) <> CALC=$calcSha"
    }) | Out-Null
  }

  if (-not $statusOk) {
    $problems.Add([pscustomobject]@{
      Type='BadStatus'; Code=$r.Code; Name=$r.Name; Path=$r.Rel; Detail="Недопустимий Status: '$($r.Status)'"
    }) | Out-Null
  }

  $summary.Add([pscustomobject]@{
    Code=$r.Code; Name=$r.Name; Path=$r.Rel; Exists=$exists; Status=$r.Status; SHA_Manifest=$r.SHA; SHA_Calc=$calcSha
  }) | Out-Null
}

# -------- scan extra (optional) --------
$extraFindings = @()
if ($ScanExtra) {
  $watchDirs = @('C07_ANALYTICS','C11','C12_KNOWLEDGE','INBOX','SKD','REPORTS','EXPORTS')
  $manifestSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($r in $rows) { [void]$manifestSet.Add(($r.Rel -replace '[\\/]+','/')) }

  foreach ($wd in $watchDirs) {
    $root = Join-Path $RepoRoot $wd
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem $root -Recurse -File | ForEach-Object {
      $rel = $_.FullName.Substring($RepoRoot.Length).TrimStart('\','/').Replace('\','/')
      if (-not $manifestSet.Contains($rel)) {
        $extraFindings += $rel
      }
    }
  }
  $extraFindings = $extraFindings | Sort-Object -Unique
}

# -------- build report --------
$reportsDir = Join-Path $RepoRoot 'REPORTS'
$null = New-Item -ItemType Directory -Force -Path $reportsDir
$stamp = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
$outMd = Join-Path $reportsDir "BTD_Structure_Test_${stamp}.md"

$mdOut = @()
$mdOut += "# ✅/❌ SKD-валідація BTD 1.0"
$mdOut += ""
$mdOut += "- **Час перевірки:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
$mdOut += "- **MANIFEST:** $($ManifestPath.Substring($RepoRoot.Length).TrimStart('\'))"
$mdOut += "- **RepoRoot:** $RepoRoot"
$mdOut += ""
$mdOut += "## Підсумок"
$mdOut += "- Перевірено записів: **$($rows.Count)**"
$mdOut += "- Виявлено проблем: **$($problems.Count)**"
$mdOut += ""

$mdOut += "## Деталі перевірки"
$mdOut += "| Код | Назва | Шлях | Є файл | Status | SHA (MANIFEST) | SHA (calc) |"
$mdOut += "|---|---|---|---|---|---|---|"
foreach ($s in $summary) {
  $mdOut += "| $($s.Code) | $($s.Name.Replace('|','\|')) | $($s.Path.Replace('|','\|')) | $($s.Exists) | $($s.Status) | $($s.SHA_Manifest) | $($s.SHA_Calc) |"
}

if ($problems.Count -gt 0) {
  $mdOut += ""
  $mdOut += "## Проблеми"
  $mdOut += "| Тип | Код | Назва | Шлях | Деталі |"
  $mdOut += "|---|---|---|---|---|"
  foreach ($p in $problems) {
    $mdOut += "| $($p.Type) | $($p.Code) | $($p.Name.Replace('|','\|')) | $($p.Path.Replace('|','\|')) | $($p.Detail.Replace('|','\|')) |"
  }
}

if ($ScanExtra -and $extraFindings.Count -gt 0) {
  $mdOut += ""
  $mdOut += "## Зайві файли (не описані в MANIFEST)"
  foreach ($x in $extraFindings) { $mdOut += "- $x" }
}

$mdOut += ""
$mdOut += "— _С.Ч._"
$mdOut -join "`r`n" | Set-Content -LiteralPath $outMd -Encoding UTF8

Write-Host "[OK] Report: $outMd"

# exit code
if ($problems.Count -gt 0) { exit 1 } else { exit 0 }
