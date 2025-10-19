<#
.SYNOPSIS
  Архівує звіти у ZIP та генерує .sha256.

.DESCRIPTION
  Збирає файли за масками/часом із ReportsRoot (і, за потреби, додаткових шляхів),
  пакує у ZIP в ARCHIVE\<year>, створює ASCII-файл з SHA256. Веде лог.

.PARAMETERS
  -ReportsRoot   Базова тека звітів (наприклад, D:\CHECHA_CORE\REPORTS).
  -ExtraPaths    Додаткові теки (ITETA\reports тощо).
  -Include       Перелік масок (за замовч. *.md,*.html,*.csv,*.xlsx).
  -SinceHours    За скільки годин назад брати файли (за замовч. 48).
  -OutDir        Куди класти архів (за замовч. ARCHIVE\<year>).
  -NamePrefix    Префікс імені архіву.
  -LogPath       Куди писати лог.

.EXAMPLE
  pwsh -NoProfile -File D:\CHECHA_CORE\TOOLS\Archive-Reports.ps1 `
    -ReportsRoot D:\CHECHA_CORE\REPORTS `
    -ExtraPaths D:\CHECHA_CORE\ITETA\reports `
    -SinceHours 72 -Include *.md,*.html,*.csv
#>

[CmdletBinding()]
param(
    [string]$ReportsRoot = "D:\CHECHA_CORE\REPORTS",
    [string[]]$ExtraPaths = @(),
    [string[]]$Include = @("*.md", "*.html", "*.csv", "*.xlsx"),
    [int]$SinceHours = 48,
    [string]$OutDir = ("D:\CHECHA_CORE\REPORTS\ARCHIVE\{0}" -f (Get-Date -Format 'yyyy')),
    [string]$NamePrefix = "CheCha_Reports",
    [string]$LogPath = "D:\CHECHA_CORE\REPORTS\ARCHIVE\Archive-Reports.log"
)

function Ensure-Dir([string]$p) { if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function Write-Log([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    $line; try { $null = $line | Tee-Object -FilePath $LogPath -Append }catch {}
}

Ensure-Dir $OutDir
Ensure-Dir (Split-Path -Parent $LogPath)

Write-Log "START Archive-Reports"
Write-Log "ReportsRoot=$ReportsRoot; SinceHours=$SinceHours; OutDir=$OutDir"

$since = (Get-Date).AddHours( - [math]::Abs($SinceHours))
$srcRoots = @()
if (Test-Path -LiteralPath $ReportsRoot) { $srcRoots += $ReportsRoot } else { Write-Log "[WARN] ReportsRoot not found." }
foreach ($p in $ExtraPaths) { if (Test-Path -LiteralPath $p) { $srcRoots += $p } else { Write-Log "[WARN] Extra path not found: $p" } }

$files = @()
foreach ($root in $srcRoots) {
    foreach ($mask in $Include) {
        $files += Get-ChildItem -LiteralPath $root -Recurse -File -Filter $mask -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $since }
    }
}

if (-not $files -or $files.Count -eq 0) {
    Write-Log "[WARN] No files matched selection. Abort."
    Write-Log "END Archive-Reports"; exit 0
}

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$zip = Join-Path $OutDir ("{0}_{1}.zip" -f $NamePrefix, $stamp)
$sum = "$zip.sha256"

# Пакуємо напряму (без проміжної копії) — шляхи збережуться відносно коренів
try {
    Compress-Archive -Path ($files | Select-Object -ExpandProperty FullName) -DestinationPath $zip -Force
    Write-Log ("[OK] ZIP: {0}" -f $zip)
}
catch {
    Write-Log ("[ERR] ZIP failed: {0}" -f $_.Exception.Message)
    exit 1
}

try {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLower()
    # Формат: "<hash> *filename.zip" — зручно для перевіряльників
    "$hash *$(Split-Path $zip -Leaf)" | Out-File -FilePath $sum -Encoding ASCII
    Write-Log ("[OK] SHA256: {0}" -f $sum)
}
catch {
    Write-Log ("[ERR] SHA256 failed: {0}" -f $_.Exception.Message)
    exit 1
}

Write-Log "END Archive-Reports"
exit 0


