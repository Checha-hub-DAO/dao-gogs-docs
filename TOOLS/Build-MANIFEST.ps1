# D:\CHECHA_CORE\TOOLS\Build-MANIFEST.ps1
[CmdletBinding()]
param(
  [string]$ManifestPath     = "D:\CHECHA_CORE\MANIFEST.md",
  [string]$WeeklyRoot       = "D:\CHECHA_CORE\REPORTS\WEEKLY",
  [string]$ScoreCsv         = "D:\CHECHA_CORE\C07_ANALYTICS\C12_IntegrityScore.csv",
  [string]$C13LatestMd      = "D:\CHECHA_CORE\C13_LEARNING_FEEDBACK\LATEST.md",
  [int]$ScoreHistory        = 3,
  [int]$C13Lines            = 6,
  [int]$ShowLatestArchives  = 5,
  [switch]$NoHash,    # якщо не потрібно створювати MANIFEST.md.sha256
  [switch]$NoGit,     # якщо не потрібно git add/commit
  [string]$LogPath    = "D:\CHECHA_CORE\C03_LOG\control\Build-MANIFEST.log"
)

# --- helpers ---
function Ensure-Dir([string]$p){ if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Log([string]$m){
  $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
  $line
  try { $null = $line | Tee-Object -FilePath $LogPath -Append } catch {}
}

Ensure-Dir (Split-Path -Parent $ManifestPath)
Ensure-Dir (Split-Path -Parent $LogPath)

Log "START Build-MANIFEST"
Log "Manifest=$ManifestPath"

# --- paths to tools ---
$UpdateMetrics = "D:\CHECHA_CORE\TOOLS\Update-MANIFEST-Metrics.ps1"
$UpdatePaths   = "D:\CHECHA_CORE\TOOLS\Update-MANIFEST-SystemPaths.ps1"

# --- 1) Ensure base file exists (header stub) ---
if(-not (Test-Path -LiteralPath $ManifestPath)){
  "# MANIFEST`r`n" | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  Log "[NEW] Created base MANIFEST.md"
}

# --- 2) Update METRICS section ---
if(Test-Path -LiteralPath $UpdateMetrics){
  try{
    Log "Step: Update-MANIFEST-Metrics.ps1 …"
    pwsh -NoProfile -ExecutionPolicy Bypass `
      -File $UpdateMetrics `
      -ManifestPath $ManifestPath `
      -ScoreCsv     $ScoreCsv `
      -C13LatestMd  $C13LatestMd `
      -ScoreHistory $ScoreHistory `
      -C13Lines     $C13Lines `
      -LogPath      (Join-Path (Split-Path $LogPath -Parent) "Update-MANIFEST-Metrics.log")
  } catch { Log "[WARN] Metrics updater failed: $($_.Exception.Message)" }
} else {
  Log "[WARN] Not found: $UpdateMetrics"
}

# --- 3) Update SYSTEM PATHS section ---
if(Test-Path -LiteralPath $UpdatePaths){
  try{
    Log "Step: Update-MANIFEST-SystemPaths.ps1 …"
    pwsh -NoProfile -ExecutionPolicy Bypass `
      -File $UpdatePaths `
      -ManifestPath $ManifestPath `
      -WeeklyRoot   $WeeklyRoot `
      -ShowLatestArchives $ShowLatestArchives `
      -LogPath      (Join-Path (Split-Path $LogPath -Parent) "Update-MANIFEST-SystemPaths.log")
  } catch { Log "[WARN] SystemPaths updater failed: $($_.Exception.Message)" }
} else {
  Log "[WARN] Not found: $UpdatePaths"
}

# --- 3.5) Update SCHEDULER section ---
$UpdateScheduler = "D:\CHECHA_CORE\TOOLS\Update-MANIFEST-Scheduler.ps1"
if(Test-Path -LiteralPath $UpdateScheduler){
  try{
    Log "Step: Update-MANIFEST-Scheduler.ps1 …"
    pwsh -NoProfile -ExecutionPolicy Bypass `
      -File $UpdateScheduler `
      -ManifestPath $ManifestPath `
      -TaskPath     "\CHECHA\" `
      -MaxRows      12 `
      -LogPath      (Join-Path (Split-Path $LogPath -Parent) "Update-MANIFEST-Scheduler.log")
  } catch { Log "[WARN] Scheduler updater failed: $($_.Exception.Message)" }
} else {
  Log "[WARN] Not found: $UpdateScheduler"
}

# --- 4) Hash MANIFEST (optional) ---
if(-not $NoHash){
  try{
    if(Test-Path -LiteralPath $ManifestPath){
      $h = Get-FileHash -Algorithm SHA256 -LiteralPath $ManifestPath
      $shaFile = "$ManifestPath.sha256"
      "{0}  {1}" -f $h.Hash,(Split-Path $ManifestPath -Leaf) | Set-Content -LiteralPath $shaFile -Encoding ASCII
      Log "[OK] SHA256 created: $shaFile"
    } else {
      Log "[WARN] Manifest not found for hashing."
    }
  } catch { Log "[WARN] Hashing failed: $($_.Exception.Message)" }
}

# --- 5) Optional git add/commit ---
if(-not $NoGit){
  try{
    $repoRoot = Split-Path -Parent $ManifestPath
    Push-Location $repoRoot
    # обережна перевірка: git може бути відсутнім або поза PATH
    $gitOk = $false
    try { git --version | Out-Null; $gitOk = $true } catch {}
    if($gitOk){
      git add $ManifestPath 2>$null
      if(Test-Path -LiteralPath "$ManifestPath.sha256"){ git add "$ManifestPath.sha256" 2>$null }
      # додатково — лог апдейтерів, якщо лежать у репо
      if(Test-Path -LiteralPath $UpdateMetrics){ git add $UpdateMetrics 2>$null }
      if(Test-Path -LiteralPath $UpdatePaths){   git add $UpdatePaths   2>$null }
      $msg = "manifest: refresh (Metrics + Paths) and sha256"
      git commit -m $msg 2>$null | Out-Null
      Log "[OK] git add/commit done."
    } else {
      Log "[INFO] git not available in PATH — skipping commit."
    }
  } catch { Log "[WARN] git stage/commit failed: $($_.Exception.Message)" }
  finally { Pop-Location }
}

Log "END Build-MANIFEST"
