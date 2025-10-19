<#
.SYNOPSIS
  Автооновлення SHA256 і статусів у MANIFEST.md (BTD 1.0) + генерація CHECKSUMS.txt та JSON-маніфесту.

.DESCRIPTION
  - Знаходить markdown-таблицю між розділом "Складові (ключові файли)" і "Примітки" (або кінцем файлу).
  - Парсить рядки таблиці (pipe-separated), вираховує SHA256 для наявних файлів.
  - Оновлює колонку SHA256; за потреби коригує Status:
      * якщо файл існує — не чіпає статус, окрім випадку "Error" → ставить "OK"
      * якщо файл відсутній — ставить "Error"
  - Пише назад у MANIFEST.md (UTF-8), створює C11\CHECKSUMS.txt і C11\BTD_Manifest.json

.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass -File "D:\CHECHA_CORE\TOOLS\Build-BTD-Manifest.ps1"

.PARAMETER ManifestPath
  Шлях до MANIFEST.md (за замовчуванням D:\CHECHA_CORE\C11\MANIFEST.md)

.PARAMETER RepoRoot
  Корінь для відносних шляхів у таблиці (за замовчуванням D:\CHECHA_CORE)

.PARAMETER OutDir
  Куди класти CHECKSUMS.txt та JSON (за замовчуванням D:\CHECHA_CORE\C11)

.NOTES
  Автор: С.Ч. / ЧеЧа-система
#>

[CmdletBinding()]
param(
    [string]$ManifestPath = 'D:\CHECHA_CORE\C11\MANIFEST.md',
    [string]$RepoRoot = 'D:\CHECHA_CORE',
    [string]$OutDir = 'D:\CHECHA_CORE\C11'
)

function Join-RepoPath {
    param([string]$RelPath)
    if (-not $RelPath) { return $null }
    # У маніфесті шляхи в стилі "C11/tools/INDEX/TOOLS_INDEX.md"
    $p = $RelPath -replace '[\\/]+', '\'            # нормалізуємо слеші
    $p = $p.TrimStart('\')                         # прибираємо лідинг
    return (Join-Path -Path $RepoRoot -ChildPath $p)
}

function Compute-Sha256 {
    param([string]$FullPath)
    try {
        if (Test-Path -LiteralPath $FullPath -PathType Leaf) {
            return (Get-FileHash -Algorithm SHA256 -LiteralPath $FullPath).Hash
        }
        return $null
    }
    catch {
        return $null
    }
}

# --- читання MANIFEST.md ---
if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "MANIFEST.md не знайдено: $ManifestPath"
}
$md = Get-Content -LiteralPath $ManifestPath -Raw

# межі таблиці
$startMarker = '## 🔹 Складові (ключові файли)'
$endMarker = '## 🔹 Примітки'

$startIdx = $md.IndexOf($startMarker)
if ($startIdx -lt 0) { throw "Не знайдено секцію: $startMarker" }

# вирізаємо частину з таблицею
$afterStart = $md.Substring($startIdx)
$endIdxRel = $afterStart.IndexOf($endMarker)
if ($endIdxRel -lt 0) {
    # таблиця до кінця файлу
    $tableBlock = $afterStart
    $restTail = ''
}
else {
    $tableBlock = $afterStart.Substring(0, $endIdxRel)
    $restTail = $afterStart.Substring($endIdxRel)  # включно з маркером Приміток
}

# знайти саму таблицю (рядки, що починаються з '|')
$lines = ($tableBlock -split "`r?`n")
$tableStart = ($lines | Select-String -SimpleMatch '|' | Select-Object -First 1).LineNumber
if (-not $tableStart) { throw "Таблиця зі '|' у секції не знайдена." }

# зберемо заголовок + розділювач + тіло
$header = $lines[$tableStart - 1]
$separator = $lines[$tableStart]
$bodyLines = @()
for ($i = $tableStart + 1; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if (-not ($line -match '^\s*\|')) { break }
    if ($line.Trim() -eq '') { break }
    $bodyLines += $line
}

# парсимо рядки тіла
$updatedBody = New-Object System.Collections.Generic.List[string]
$recordsJson = New-Object System.Collections.Generic.List[object]
$checksums = New-Object System.Collections.Generic.List[string]

foreach ($row in $bodyLines) {
    # розбиваємо по '|' і тримаємо 6 колонок: | Код | Назва | Шлях | SHA256 | Статус |
    $cells = ($row -split '\|') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    # іноді перший/останній елемент порожній через крайні |
    # гарантовано візьмемо 5 перших значущих полів
    if ($cells.Count -lt 5) {
        $updatedBody.Add($row) | Out-Null
        continue
    }
    $Code = $cells[0]
    $Name = $cells[1]
    $Rel = $cells[2]
    $Sha = $cells[3]
    $Status = $cells[4]

    $full = Join-RepoPath -RelPath $Rel
    $newSha = if ($full) { Compute-Sha256 -FullPath $full } else { $null }

    if ($newSha) {
        # файл існує — оновимо SHA; якщо статус був Error — піднімемо до OK
        $Sha = $newSha
        if ($Status -match 'Error') { $Status = 'OK' }
    }
    else {
        # файла немає — відзначимо помилку
        $Sha = '—'
        $Status = 'Error'
    }

    # реконструюємо рядок таблиці
    $newRow = "| $Code | $Name | $Rel | `$Sha$($null) | $Status |"
    # але `$Sha$($null)` виглядає дивно — сформуємо акуратно:
    $newRow = "| $Code | $Name | $Rel | $Sha | $Status |"
    $updatedBody.Add($newRow) | Out-Null

    # колекції вихідних артефактів
    if ($newSha) {
        $checksums.Add("{0}  {1}" -f $newSha, $Rel) | Out-Null
    }
    else {
        $checksums.Add("MISSING  {0}" -f $Rel) | Out-Null
    }

    $recordsJson.Add([pscustomobject]@{
            code   = $Code
            name   = $Name
            path   = $Rel
            full   = $full
            sha256 = if ($newSha) { $newSha } else { $null }
            status = $Status
        }) | Out-Null
}

# збирання оновленого блоку секції
$rebuiltTable = @()
$rebuiltTable += ($lines[0..($tableStart - 2)])        # все до шапки таблиці
$rebuiltTable += $header
$rebuiltTable += $separator
$rebuiltTable += $updatedBody
# додаємо хвіст (Примітки або кінець секції)
$rebuiltSection = ($rebuiltTable -join "`r`n")
if ($restTail) { $rebuiltSection += "`r`n" + $restTail }

# збирання усього файлу: все до початку секції + оновлена секція + все після секції (якщо було)
$prefix = $md.Substring(0, $startIdx)
$updatedMd = $prefix + $rebuiltSection

# запис назад MANIFEST.md
$updatedMd | Set-Content -LiteralPath $ManifestPath -Encoding UTF8

# виводи (допоміжні)
$null = New-Item -ItemType Directory -Force -Path $OutDir
$checksPath = Join-Path $OutDir 'CHECKSUMS.txt'
$checksums | Set-Content -LiteralPath $checksPath -Encoding UTF8

$jsonPath = Join-Path $OutDir 'BTD_Manifest.json'
$recordsJson | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

Write-Host "[OK] MANIFEST.md оновлено: $ManifestPath"
Write-Host "[OK] CHECKSUMS: $checksPath"
Write-Host "[OK] JSON:      $jsonPath"

