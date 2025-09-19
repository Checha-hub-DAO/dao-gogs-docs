<# 
.SYNOPSIS
  Коміт + пуш змін G46 до віддаленого репозиторію. Опційно створює PR з фіче-гілки.

.EXAMPLE
  .\Sync-GitBook_G46.ps1 -RepoPath "D:\CHECHA_CORE\G46-Podilsk.InfoHub" -Message "G46: init content" -Branch "main"
#>
param(
  [Parameter(Mandatory)][string]$RepoPath,
  [string]$Branch = "main",
  [string]$Message = "chore: update G46",
  [switch]$CreateFeaturePR,
  [string]$FeatureName = "feature/g46-update"
)

$ErrorActionPreference = "Stop"
function Info($m){ Write-Host "ℹ️  $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "✅ $m" -ForegroundColor Green }
function Warn($m){ Write-Host "⚠️  $m" -ForegroundColor Yellow }
function Err($m){ Write-Host "❌ $m" -ForegroundColor Red }

Push-Location $RepoPath
try{
  git rev-parse --is-inside-work-tree *>$null 2>&1 | Out-Null
} catch { Err "Не git-репозиторій: $RepoPath"; Pop-Location; exit 1 }

# Ensure branch exists
$on = (git rev-parse --abbrev-ref HEAD).Trim()
if($CreateFeaturePR){
  Info "Працюю у фіче-гілці: $FeatureName"
  git checkout -B $FeatureName | Out-Null
} else {
  Info "Мета-гілка: $Branch (поточна: $on)"
  if($on -ne $Branch){
    git checkout $Branch | Out-Null
  }
}

git add -A
# Коміт може зафейлитися, якщо немає змін — це норм
git commit -m $Message *>$null 2>&1

if($CreateFeaturePR){
  Info "Пушу фіче-гілку…"
  git push -u origin $FeatureName
  Warn "Створи PR вручну або через gh:
  gh pr create --base $Branch --head $FeatureName --title '$Message' --body 'Auto PR'"
} else {
  Info "Пушу в $Branch…"
  git push -u origin $Branch
}

Ok "Синхронізація завершена."
Pop-Location
