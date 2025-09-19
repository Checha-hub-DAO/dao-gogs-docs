param(
  [Parameter(Mandatory)][string]$RepoPath,
  [string]$Branch = "main",
  [string]$Message = "G46: update",
  [string]$Remote = "origin",
  [switch]$CreateFeaturePR,
  [string]$FeatureName = "feature/g46-update",
  [switch]$NoFetch
)

$ErrorActionPreference = "Stop"

function I($m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function OK($m){ Write-Host "[ OK ] $m" -ForegroundColor Green }
function WR($m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function ER($m){ Write-Host "[ERR ] $m" -ForegroundColor Red }

function Test-GitRepo {
  param([string]$Path)
  Push-Location $Path
  git rev-parse --is-inside-work-tree *> $null 2>&1
  $ok = ($LASTEXITCODE -eq 0)
  Pop-Location
  return $ok
}

function Test-LocalBranch {
  param([string]$Branch)
  git show-ref --verify --quiet ("refs/heads/{0}" -f $Branch)
  return ($LASTEXITCODE -eq 0)
}

function Test-UpstreamSet {
  # returns $true if current branch has upstream
  git rev-parse --abbrev-ref --symbolic-full-name "@{u}" *> $null 2>&1
  return ($LASTEXITCODE -eq 0)
}

# Ensure git is available
try { git --version *> $null 2>&1 } catch { ER "git not found in PATH"; exit 1 }

Push-Location $RepoPath
try {
  if(-not (Test-GitRepo -Path $RepoPath)){ ER "Not a git repository: $RepoPath"; exit 1 }

  if(-not $NoFetch){
    I "Fetching from $Remote..."
    git fetch $Remote --prune
  }

  if($CreateFeaturePR){
    I "Preparing feature branch: $FeatureName (base: $Branch)"
    # Try to base feature on remote branch tip if exists, else on local, else create empty
    git checkout -B $FeatureName "$Remote/$Branch" *> $null 2>&1
    if($LASTEXITCODE -ne 0){
      if(Test-LocalBranch -Branch $Branch){
        git checkout -B $FeatureName $Branch
      } else {
        WR "Base branch '$Branch' not found locally or remotely; creating empty feature branch"
        git checkout -B $FeatureName
      }
    }
  } else {
    if(Test-LocalBranch -Branch $Branch){
      I "Checkout target branch: $Branch"
      git checkout $Branch
      if(Test-UpstreamSet){
        I "Pull --rebase"
        git pull --rebase
      }
    } else {
      WR "Local branch '$Branch' not found — trying to create from '$Remote/$Branch'"
      git checkout -b $Branch "$Remote/$Branch" *> $null 2>&1
      if($LASTEXITCODE -ne 0){
        I "Remote branch not found — creating empty local '$Branch'"
        git checkout -b $Branch
      }
    }
  }

  # Stage & commit if needed
  git add -A
  $dirty = git status --porcelain
  if([string]::IsNullOrWhiteSpace($dirty)){
    WR "No changes to commit — skipping commit step."
  } else {
    git commit -m $Message
    OK "Commit created."
  }

  if($CreateFeaturePR){
    I "Pushing feature branch '$FeatureName' -> $Remote"
    git push -u $Remote $FeatureName
    OK "Pushed feature branch."
    WR "To open a PR via GitHub CLI:
  gh pr create --base $Branch --head $FeatureName --title '$Message' --body 'Auto PR from Sync script'"
  } else {
    if(-not (Test-UpstreamSet)){
      I "Setting upstream: $Remote/$Branch"
      git push -u $Remote $Branch
    } else {
      I "Pushing '$Branch'"
      git push $Remote $Branch
    }
    OK "Sync done."
  }
}
finally {
  Pop-Location
}
