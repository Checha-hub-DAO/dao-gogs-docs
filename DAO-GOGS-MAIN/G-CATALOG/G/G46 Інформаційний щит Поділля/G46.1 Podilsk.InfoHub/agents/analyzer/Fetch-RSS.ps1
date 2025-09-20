param([Parameter(Mandatory)][string]$Root)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $Root).Path
$config = Get-Content -Raw -LiteralPath (Join-Path $root "agents\analyzer\config\sources.json") | ConvertFrom-Json
$rawDir = Join-Path $root ("data\raw\" + (Get-Date -Format "yyyy-MM-dd"))
New-Item -ItemType Directory -Force -Path $rawDir | Out-Null
foreach($feed in $config.rss){
  try{
    $resp = Invoke-WebRequest -Uri $feed.url -UseBasicParsing -TimeoutSec 20
    $fn = Join-Path $rawDir ("rss_" + $feed.name + ".xml")
    $resp.Content | Set-Content -LiteralPath $fn -Encoding UTF8
    Write-Host "[ OK ] $($feed.name)" -ForegroundColor Green
  } catch {
    Write-Host "[WARN] $($feed.name): $($_.Exception.Message)" -ForegroundColor Yellow
  }
}
