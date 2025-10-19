param([Parameter(Mandatory)][string]$Root)
$ErrorActionPreference = "Stop"
function I($m) { Write-Host "[INFO] $m" -ForegroundColor Cyan }
function OK($m) { Write-Host "[ OK ] $m" -ForegroundColor Green }
function WR($m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }
$root = (Resolve-Path -LiteralPath $Root).Path
I "Step 1: fetch RSS"
& (Join-Path $root "agents\analyzer\Fetch-RSS.ps1") -Root $root
I "Step 2: analyze"
& (Join-Path $root "agents\analyzer\Analyze-Items.ps1") -Root $root
try {
    $date = Get-Date -Format "yyyy-MM-dd"
    $beacons = Join-Path $root "data\normalized\beacons_$date.csv"
    $inc = Join-Path $root "data\incidents\incidents_$date.csv"
    $outMd = Join-Path $root ("content\brief-" + $date + ".md")
    $lines = @("# Daily Brief ($date)", "", "## Beacons", "")
    if (Test-Path $beacons) { $lines += (Get-Content $beacons) }
    $lines += "", "## Incidents (top 10)", ""
    if (Test-Path $inc) { $lines += ((Get-Content $inc | Select-Object -Skip 1) | Select-Object -First 10) }
    $lines | Set-Content -LiteralPath $outMd -Encoding UTF8
    OK "brief generated: content\brief-$date.md"
}
catch { WR "brief generation skipped: $($_.Exception.Message)" }
OK "Agent run finished."

