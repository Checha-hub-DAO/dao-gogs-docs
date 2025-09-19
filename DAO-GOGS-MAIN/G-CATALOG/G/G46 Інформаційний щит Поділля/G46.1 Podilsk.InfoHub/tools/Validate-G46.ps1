<# 
.SYNOPSIS
  Валідація структури G46 (README, MediaKit, контент ≥5, CSV контактів, мінімальні поля).

.EXAMPLE
  .\Validate-G46.ps1 -Root "D:\CHECHA_CORE\G46-Podilsk.InfoHub"
#>
param(
  [Parameter(Mandatory)][string]$Root
)

$ErrorActionPreference = "Stop"
function OK($m){ Write-Host "✅ $m" -ForegroundColor Green }
function WARN($m){ Write-Host "⚠️  $m" -ForegroundColor Yellow }
function FAIL($m){ Write-Host "❌ $m" -ForegroundColor Red }

$Root = (Resolve-Path $Root).Path

$requiredFiles = @("README.md","CHANGELOG.md")
$requiredDirs  = @("media-kit","content","contacts","archive")

$ok = $true
foreach($f in $requiredFiles){
  if(-not (Test-Path (Join-Path $Root $f))){ FAIL "Немає $f"; $ok=$false } else { OK "$f" }
}
foreach($d in $requiredDirs){
  if(-not (Test-Path (Join-Path $Root $d))){ FAIL "Немає теки $d"; $ok=$false } else { OK "$d" }
}

# MediaKit files
$mk = Join-Path $Root "media-kit"
$need = @("logo.svg","banner-1200x400.png")
foreach($n in $need){
  if(-not (Test-Path (Join-Path $mk $n))){ WARN "MediaKit: відсутній $n" } else { OK "MediaKit: $n" }
}

# Content count
$contentCount = (Get-ChildItem (Join-Path $Root "content") -File -Include *.md | Measure-Object).Count
if($contentCount -lt 5){ WARN "content: лише $contentCount (рекомендовано ≥5)" } else { OK "content: $contentCount" }

# Contacts CSV schema
$csvPath = Join-Path $Root "contacts\podillia_contacts.csv"
if(Test-Path $csvPath){
  $csv = Import-Csv $csvPath
  $cols = "Name","Org","Role","City","Phone","Email","Channel","Notes","Source","Verified","UpdatedUtc"
  $miss = @()
  foreach($c in $cols){ if(-not ($csv | Get-Member -Name $c -MemberType NoteProperty)){ $miss += $c } }
  if($miss.Count -gt 0){ WARN "contacts CSV: бракує колонок: $($miss -join ', ')" } else { OK "contacts CSV: схема OK" }
} else {
  WARN "contacts CSV не знайдено ($csvPath)"
}

if($ok){ OK "Валідація завершена з OK/попередженнями" } else { FAIL "Є критичні помилки" }
