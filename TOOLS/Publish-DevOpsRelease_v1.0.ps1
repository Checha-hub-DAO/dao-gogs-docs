param(
  [string]$Repo    = "D:\CHECHA_CORE",
  [string]$OutDir  = "D:\CHECHA_CORE\C03_LOG\reports",
  [string]$Branch  = "main",
  [string]$Tag     = "devops-v1.0",
  [switch]$ForceTag,
  [switch]$DryRun
)

# --- Config ---
$ErrorActionPreference = "Stop"
$ReleaseFiles = @(
  "README_DevOps_v1.0_GitBook.zip",
  "README_DevOps_v1.0_GitBook.zip.sha256.txt",
  "CHANGELOG_DevOps.md",
  "CHANGELOG_DevOps.md.sha256.txt",
  "RELEASE_NOTE_DevOps_v1.0.md",
  "RELEASE_NOTE_DevOps_v1.0.md.sha256.txt"
)

function Log([string]$m,[string]$lvl="INFO"){
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Write-Host "[$lvl] $ts $m"
}

function Get-RelPath([string]$Full, [string]$Root){
  $u = (Resolve-Path -LiteralPath $Full).ProviderPath
  $r = (Resolve-Path -LiteralPath $Root).ProviderPath
  $uriU = New-Object System.Uri($u)
  $uriR = New-Object System.Uri((if($r[-1] -ne '\'){$r+'\'} else {$r}))
  return [System.Uri]::UnescapeDataString($uriR.MakeRelativeUri($uriU).ToString()).Replace('/','\')
}

# --- Checks ---
if (-not (Test-Path -LiteralPath $Repo)) { throw "Repo not found: $Repo" }
if (-not (Test-Path -LiteralPath (Join-Path $Repo ".git"))) { throw "Not a git repo: $Repo" }
if (-not (Test-Path -LiteralPath $OutDir)) { throw "OutDir not found: $OutDir" }

# Collect existing files
$existing = @()
foreach($name in $ReleaseFiles){
  $p = Join-Path $OutDir $name
  if (Test-Path -LiteralPath $p) { $existing += $p } else { Log "Missing: $p" "WARN" }
}

if ($existing.Count -eq 0) { throw "No release files found in $OutDir" }

# Build list of repo-relative paths for git add
$toAdd = @()
foreach($p in $existing){
  $rel = Get-RelPath -Full $p -Root $Repo
  if ($rel -match '^\.\.') {
    throw "Output path $p is not inside repo root $Repo"
  }
  $toAdd += $rel
}

Log ("Files to commit:`n - " + ($toAdd -join "`n - "))

# --- Git add/commit ---
$commitMsg = "devops: v1.0 release finalized (README+CHANGELOG+RELEASE_NOTE+SHA)"

if ($DryRun){
  Log "[DRY] git add -> $($toAdd -join ', ')"
  Log "[DRY] git commit -m '$commitMsg'"
} else {
  & git -C $Repo add -- $toAdd | Out-Null
  $status = & git -C $Repo status --porcelain
  if ([string]::IsNullOrWhiteSpace($status)){
    Log "Nothing to commit — working tree clean" "INFO"
  } else {
    & git -C $Repo commit -m $commitMsg | Write-Host
  }
}

# --- Tag ---
$tagExists = (& git -C $Repo tag --list $Tag) -ne $null -and (& git -C $Repo tag --list $Tag).Trim().Length -gt 0

if ($tagExists -and -not $ForceTag){
  Log "Tag '$Tag' already exists. Use -ForceTag to move it." "WARN"
} else {
  if ($DryRun){
    Log "[DRY] git tag " + ($(if($ForceTag){"-f "}else{""}) + "-a '$Tag' -m 'DevOps Layer v1.0 — Stable release'")
  } else {
    $tagArgs = @("tag")
    if ($ForceTag){ $tagArgs += "-f" }
    $tagArgs += @("-a", $Tag, "-m", "DevOps Layer v1.0 — Stable release")
    & git -C $Repo @tagArgs | Out-Null
    Log "Tag set: $Tag"
  }
}

# --- Push ---
if ($DryRun){
  Log "[DRY] git push origin $Branch --tags"
} else {
  & git -C $Repo push origin $Branch --tags | Write-Host
  Log "Pushed to origin/$Branch with tags"
}

Log "Done."
