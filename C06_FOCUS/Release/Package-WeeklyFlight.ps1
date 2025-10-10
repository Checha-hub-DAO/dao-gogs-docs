[CmdletBinding()]
param(
  [string]$Root = "D:\CHECHA_CORE",
  [string]$OutDir = "D:\CHECHA_CORE\C06_FOCUS\Release\out",
  [string]$TagPrefix = "flight-weekly"
)

$stamp = Get-Date -Format 'yyyyMMdd'
$zipName = "CheCha_${TagPrefix}_$stamp.zip"
$zipPath = Join-Path $OutDir $zipName
$null = New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$include = @(
  "C06_FOCUS\VISION_CheChaFlight_4.10.md",
  "C06_FOCUS\Flight_Dashboard_2.0.md",
  "C06_FOCUS\assets\reflex_badge.svg",
  "C06_FOCUS\FLIGHT_Stabilization_Checklist_2025-10-10.pdf",
  "C06_FOCUS\FOCUS_Analysis_2025-10-09.pdf",
  "C06_FOCUS\VISION_CheChaFlight_4.11.pdf",
  "C06_FOCUS\Flight_Status_Review_4.11.pdf",
  "C06_FOCUS\Flight_Nodes_Map_4.11.pdf",
  "C07_ANALYTICS\Reflex\ReflexReport_*.md"
)

$files = foreach ($rel in $include) {
  $full = Join-Path $Root $rel
  if (Test-Path -LiteralPath $full) { Get-Item -LiteralPath $full }
}
if (-not $files) { Write-Host "[WARN] Немає файлів для пакування."; exit 1 }

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $files.FullName -DestinationPath $zipPath
Write-Host "[OK] Пакет зібрано: $zipPath"

# (Опціонально) створення git-тега для історії
try {
  git add -A
  git commit -m "Weekly Flight Package $stamp" 2>$null
  $tag = "$TagPrefix-$stamp"
  git tag $tag
  Write-Host "[OK] Локальний git-тег створено: $tag"
} catch {
  Write-Host "[WARN] Git commit/tag пропущено: $($_.Exception.Message)"
}

# (Опціонально) GitHub release через gh CLI (якщо налаштовано `gh auth login`)
# gh release create $tag $zipPath --title "CheCha Flight Weekly ($stamp)" --notes "Автопакування CheCha CORE"
