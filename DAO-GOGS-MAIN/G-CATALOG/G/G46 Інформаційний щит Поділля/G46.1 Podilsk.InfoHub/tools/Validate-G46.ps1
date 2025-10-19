param(
    [Parameter(Mandatory)][string]$Root,
    [switch]$Strict
)

$ErrorActionPreference = "Stop"
function OK   ($m) { Write-Host "OK    $m" -ForegroundColor Green }
function WARN ($m) { Write-Host "WARN  $m" -ForegroundColor Yellow }
function FAIL ($m) { Write-Host "FAIL  $m" -ForegroundColor Red }

$Root = (Resolve-Path -LiteralPath $Root).Path

$requiredFiles = @("README.md", "CHANGELOG.md")
$requiredDirs = @("media-kit", "content", "contacts", "archive")

$allOk = $true
foreach ($f in $requiredFiles) {
    if (-not (Test-Path (Join-Path $Root $f))) { FAIL "Missing file: $f"; $allOk = $false } else { OK "Found: $f" }
}
foreach ($d in $requiredDirs) {
    if (-not (Test-Path (Join-Path $Root $d))) { FAIL "Missing directory: $d"; $allOk = $false } else { OK "Found dir: $d" }
}

# MediaKit checks: mandatory vs optional
$mk = Join-Path $Root "media-kit"
$mandatory = @("logo.svg")
$optional = @("banner-1200x400.png")

foreach ($m in $mandatory) {
    if (-not (Test-Path (Join-Path $mk $m))) { FAIL "MediaKit missing (mandatory): $m"; $allOk = $false } else { OK "MediaKit: $m" }
}
foreach ($m in $optional) {
    if (-not (Test-Path (Join-Path $mk $m))) { WARN "MediaKit missing (optional): $m" } else { OK "MediaKit: $m" }
}

# Content count
$contentDir = Join-Path $Root "content"
$contentCount = if (Test-Path $contentDir) { (Get-ChildItem -LiteralPath $contentDir -Filter *.md -File | Measure-Object).Count } else { 0 }
if ($contentCount -lt 5) { WARN "content has $contentCount files (>=5 recommended)" } else { OK "content files: $contentCount" }

# Contacts CSV schema
$csvPath = Join-Path $Root "contacts\podillia_contacts.csv"
$reqCols = "Name", "Org", "Role", "City", "Phone", "Email", "Channel", "Notes", "Source", "Verified", "UpdatedUtc"

if (Test-Path -LiteralPath $csvPath) {
    $firstLine = (Get-Content -LiteralPath $csvPath -TotalCount 1)
    if ([string]::IsNullOrWhiteSpace($firstLine)) {
        WARN "contacts CSV is empty (no header): $csvPath"
    }
    else {
        $hdr = $firstLine.Split(',') | ForEach-Object { $_.Trim() }
        $missing = @()
        foreach ($c in $reqCols) { if (-not ($hdr -contains $c)) { $missing += $c } }
        if ($missing.Count -gt 0) { FAIL ("contacts CSV: missing columns -> {0}" -f ($missing -join ", ")); $allOk = $false }
        else { OK "contacts CSV: header schema OK" }
    }
}
else {
    WARN "contacts CSV not found: $csvPath"
}

if ($allOk) {
    OK "Validation finished with OK/WARN"
    exit 0
}
else {
    FAIL "Validation found critical errors"
    if ($Strict) { exit 1 } else { exit 0 }
}

