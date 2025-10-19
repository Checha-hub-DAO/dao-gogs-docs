[CmdletBinding()]
param(
    [string]$ReportsRoot = "D:\CHECHA_CORE\REPORTS",
    [string]$ArchiveRel = "ARCHIVE",
    [string]$IndexFile = "ARCHIVE_INDEX.md",
    [switch]$ComputeHash,         # Додати SHA-256 поруч із кожним ZIP
    [switch]$RelativeLinks,       # Посилання на файли відносно $ReportsRoot
    [switch]$GitAdd,              # Зробити git add REPORTS/ARCHIVE_INDEX.md
    [switch]$DryRun               # Показати, що буде записано, без збереження
)

function Fail($m) { Write-Error $m; exit 1 }
function HashSHA256([string]$Path) {
    try {
        $h = Get-FileHash -LiteralPath $Path -Algorithm SHA256
        return $h.Hash
    }
    catch { return $null }
}

# 1) Шляхи
$archivePath = Join-Path $ReportsRoot $ArchiveRel
$indexPath = Join-Path $ReportsRoot $IndexFile

if (-not (Test-Path -LiteralPath $archivePath)) {
    Fail "Папку архівів не знайдено: $archivePath"
}

# 2) Збір ZIP-файлів
$zips = Get-ChildItem -LiteralPath $archivePath -Recurse -File -Include *.zip |
    Sort-Object FullName

if (-not $zips) {
    Write-Warning "ZIP-файлів не знайдено у $archivePath"
}

# 3) Групування за роком (спробуємо витягнути рік з імені; якщо ні — беремо LastWriteTime.Year)
function Get-YearFromNameOrTime($fi) {
    $name = $fi.Name
    $m = [regex]::Match($name, '\b(20\d{2})[-_\.]')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return $fi.LastWriteTime.Year
}

$grouped = $zips | Group-Object { Get-YearFromNameOrTime $_ } | Sort-Object Name

# 4) Побудова Markdown
$lines = @()
$lines += "# 📦 Архів звітів DAO-GOGS"
$lines += ""
$lines += "Цей файл є індексом усіх ZIP-архівів у папці `REPORTS/$ArchiveRel`."
$lines += "Оновлено: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += ""
$lines += "---"
$lines += ""
$lines += "## 📂 Структура збереження"
$lines += ""
$lines += "- **Рік/Місяць** → ZIP-архіви у форматі (рекомендовано):"
$lines += "  - `WeeklyChecklist_YYYY-MM-DD_to_YYYY-MM-DD.zip`"
$lines += "  - `BTD_Structure_Test_YYYY-MM-DD_HH-mm-ss.zip`"
$lines += "- `CHECKSUMS.txt` у корені підтверджує цілісність."
$lines += ""
$lines += "---"
$lines += ""
$lines += "## 📑 Індекс архівів"
$lines += ""

foreach ($g in $grouped) {
    $year = $g.Name
    $lines += "### $year"
    foreach ($fi in ($g.Group | Sort-Object Name)) {
        $relPath = if ($RelativeLinks) {
            # Відносно $ReportsRoot
            [IO.Path]::GetRelativePath($ReportsRoot, $fi.FullName) -replace '\\', '/'
        }
        else {
            $fi.FullName
        }
        $display = $fi.Name
        if ($ComputeHash) {
            $sha = HashSHA256 $fi.FullName
            if ($sha) {
                $lines += "- [$display]($relPath) — `SHA256:$($sha.Substring(0,12))…`"
      } else {
        $lines += "- [$display]($relPath)"
      }
    } else {
      $lines += "- [$display]($relPath)"
    }
  }
  $lines += ""  # порожній рядок після року
}

if (-not $zips) {
  $lines += "_Наразі ZIP-архівів не знайдено._"
  $lines += ""
}

$lines += "> 🔄 Список формується автоматично скриптом `TOOLS/Update-ArchiveIndex.ps1`."
$lines += ""
$lines += "---"
$lines += ""
$lines += "## 🚀 Наступні кроки"
$lines += ""
$lines += "- [ ] Автозаливка архівів у релізи GitHub або GitHub Pages."
$lines += "- [ ] Повний SHA256 (не лише префікс) у окремій таблиці."
$lines += "- [ ] Перевірка відповідності іменування шаблонам."
$lines += ""
$md = $lines -join "`r`n"

# 5) Запис або DryRun
if ($DryRun) {
  Write-Host "---- DRY RUN: $indexPath ----" -ForegroundColor Yellow
  Write-Host $md
  Write-Host "---- END ----" -ForegroundColor Yellow
} else {
  $md | Set-Content -LiteralPath $indexPath -Encoding UTF8
  Write-Host "[OK] Оновлено $indexPath"
  if ($GitAdd) {
    & git add $indexPath 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "[OK] git add $IndexFile" }
    else { Write-Warning "git add завершився з помилкою (перевір доступ/робочу теку)." }
  }
}

