param(
  [string]$Repo    = "D:\CHECHA_CORE",
  [string]$OutDir  = "D:\CHECHA_CORE\C03_LOG\reports",
  [string]$Branch  = "main",
  [string]$Version = "v1.0",                # e.g. v1.0, v2.1.3
  [string]$TagPrefix = "devops-v",          # final tag = "<TagPrefix><Version-without-v>" => devops-v1.0
  [switch]$ForceTag,
  [switch]$DryRun
)

# --- Config / helpers ---
$ErrorActionPreference = "Stop"

function Log([string]$m,[string]$lvl="INFO"){
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Write-Host "[$lvl] $ts $m"
}

function Get-RelPath([string]$Full, [string]$Root){
  $u = (Resolve-Path -LiteralPath $Full).ProviderPath
  $r = (Resolve-Path -LiteralPath $Root).ProviderPath
  $uriU = [Uri]::new($u)
  $uriR = [Uri]::new(($r[-1] -ne '\') ? ($r+'\') : ($r))
  return [System.Uri]::UnescapeDataString($uriR.MakeRelativeUri($uriU).ToString()).Replace('/','\')
}

function Normalize-Version([string]$v){
  if ([string]::IsNullOrWhiteSpace($v)) { return "v1.0" }
  $v = $v.Trim()
  if ($v -notmatch '^[Vv]') { $v = "v$($v)" }
  return $v
}

# --- Derive names from version ---
$Version = Normalize-Version $Version
$VersionNoV = $Version.TrimStart('v','V')

# Files pattern (keep CHANGELOG unversioned as у v1.0)
$ReleaseFiles = @(
  "README_DevOps_${Version}_GitBook.zip",
  "README_DevOps_${Version}_GitBook.zip.sha256.txt",
  "CHANGELOG_DevOps.md",
  "CHANGELOG_DevOps.md.sha256.txt",
  "RELEASE_NOTE_DevOps_${Version}.md",
  "RELEASE_NOTE_DevOps_${Version}.md.sha256.txt"
)

# --- Preflight checks ---
if (-not (Test-Path -LiteralPath $Repo)) { throw "Repo not found: $Repo" }
if (-not (Test-Path -LiteralPath (Join-Path $Repo ".git"))) { throw "Not a git repo: $Repo" }
if (-not (Test-Path -LiteralPath $OutDir)) { throw "OutDir not found: $OutDir" }

# Collect existing files
$existing = @()
foreach($name in $ReleaseFiles){
  $p = Join-Path $OutDir $name
  if (Test-Path -LiteralPath $p) { $existing += $p } else { Log "Missing: $p" "WARN" }
}

if ($existing.Count -eq 0) { throw "No release files found in $OutDir for version $Version" }

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
$commitMsg = "devops: ${Version} release finalized (README+CHANGELOG+RELEASE_NOTE+SHA)"

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
$finalTag = "$TagPrefix$VersionNoV"    # e.g. devops-v1.0
$tagExists = (& git -C $Repo tag --list $finalTag) -ne $null -and (& git -C $Repo tag --list $finalTag).Trim().Length -gt 0

if ($tagExists -and -not $ForceTag){
  Log "Tag '$finalTag' already exists. Use -ForceTag to move it." "WARN"
} else {
  if ($DryRun){
    Log "[DRY] git tag " + ($(if($ForceTag){"-f "}else{""}) + "-a '$finalTag' -m 'DevOps Layer ${Version} — Stable release'")
  } else {
    $tagArgs = @("tag")
    if ($ForceTag){ $tagArgs += "-f" }
    $tagArgs += @("-a", $finalTag, "-m", "DevOps Layer ${Version} — Stable release")
    & git -C $Repo @tagArgs | Out-Null
    Log "Tag set: $finalTag"
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

