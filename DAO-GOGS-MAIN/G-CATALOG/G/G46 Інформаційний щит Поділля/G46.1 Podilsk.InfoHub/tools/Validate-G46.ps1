param(
  [Parameter(Mandatory)][string]$Root
)

$ErrorActionPreference = "Stop"

function OK   ($m){ Write-Host "OK    $m" -ForegroundColor Green }
function WARN ($m){ Write-Host "WARN  $m" -ForegroundColor Yellow }
function FAIL ($m){ Write-Host "FAIL  $m" -ForegroundColor Red }

$Root = (Resolve-Path -LiteralPath $Root).Path

$requiredFiles = @("README.md","CHANGELOG.md")
$requiredDirs  = @("media-kit","content","contacts","archive")

$allOk = $true
foreach($f in $requiredFiles){
  if(-not (Test-Path (Join-Path $Root $f))){ FAIL "Missing file: $f"; $allOk = $false } else { OK "Found: $f" }
}
foreach($d in $requiredDirs){
  if(-not (Test-Path (Join-Path $Root $d))){ FAIL "Missing directory: $d"; $allOk = $false } else { OK "Found dir: $d" }
}

# MediaKit minimal
$mk = Join-Path $Root "media-kit"
$need = @("logo.svg","banner-1200x400.png")
foreach($n in $need){
  if(-not (Test-Path (Join-Path $mk $n))){ WARN "MediaKit missing: $n" } else { OK "MediaKit: $n" }
}

# Content count (use -Filter, not -Include)
$contentDir = Join-Path $Root "content"
$contentCount = if(Test-Path $contentDir){ (Get-ChildItem -LiteralPath $contentDir -Filter *.md -File | Measure-Object).Count } else { 0 }
if($contentCount -lt 5){ WARN "content has $contentCount files (>=5 recommended)" } else { OK "content files: $contentCount" }

# Contacts CSV schema
$csvPath = Join-Path $Root "contacts\podillia_contacts.csv"
$reqCols = "Name","Org","Role","City","Phone","Email","Channel","Notes","Source","Verified","UpdatedUtc"

if(Test-Path -LiteralPath $csvPath){
  # Read header safely even if file has zero data rows
  $firstLine = (Get-Content -LiteralPath $csvPath -TotalCount 1)
  if([string]::IsNullOrWhiteSpace($firstLine)){
    WARN "contacts CSV is empty (no header): $csvPath"
  } else {
    $hdr = $firstLine.Split(',') | ForEach-Object { $_.Trim() }
    $missing = @()
    foreach($c in $reqCols){ if(-not ($hdr -contains $c)) { $missing += $c } }
    if($missing.Count -gt 0){ WARN ("contacts CSV: missing columns -> {0}" -f ($missing -join ", ")) } else { OK "contacts CSV: header schema OK" }
  }
} else {
  WARN "contacts CSV not found: $csvPath"
}

if($allOk){ OK "Validation finished with OK/WARN" } else { FAIL "Validation found critical errors" }
