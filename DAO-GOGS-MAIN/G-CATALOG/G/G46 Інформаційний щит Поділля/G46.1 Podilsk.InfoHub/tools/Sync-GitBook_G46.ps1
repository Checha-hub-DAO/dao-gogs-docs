param(
  [Parameter(Mandatory)][string]$RepoPath,
  [string]$Branch = "main",
  [string]$Message = "G46: update",
  [switch]$CreateFeaturePR,
  [string]$FeatureName = "feature/g46-update"
)

$ErrorActionPreference = "Stop"
function I($m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function OK($m){ Write-Host "[ OK ] $m" -ForegroundColor Green }
function WR($m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function ER($m){ Write-Host "[ERR ] $m" -ForegroundColor Red }

Push-Location $RepoPath
try{
  git rev-parse --is-inside-work-tree *> $null 2>&1 | Out-Null
} catch { ER "Not a git repository: $RepoPath"; Pop-Location; exit 1 }

if($CreateFeaturePR){
  I "Checkout feature branch: $FeatureName"
  git checkout -B $FeatureName | Out-Null
} else {
  $cur = (git rev-parse --abbrev-ref HEAD).Trim()
  if($cur -ne $Branch){
    I "Checkout target branch: $Branch (current: $cur)"
    git checkout $Branch | Out-Null
  }
}

git add -A
git commit -m $Message *> $null 2>&1

if($CreateFeaturePR){
  I "Push feature branch"
  git push -u origin $FeatureName
  WR "Create PR: gh pr create --base $Branch --head $FeatureName --title '$Message' --body 'Auto PR'"
} else {
  I "Push branch $Branch"
  git push -u origin $Branch
}
OK "Sync done"
Pop-Location
