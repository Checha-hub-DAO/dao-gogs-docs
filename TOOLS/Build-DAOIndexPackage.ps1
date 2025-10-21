<# 
.SYNOPSIS
  Збирає DAO-ARCHITECTURE пакет (INDEX/README/CHANGELOG [+ ExtraInclude]) у ZIP, рахує SHA256, формує LOG.
  Опційно комітить/пушить у git та шле нотифікацію в Telegram.

.REQUIRES
  PowerShell 7+

.DEPENDS (опційно)
  D:\CHECHA_CORE\TOOLS\Telegram_AutoCore.ps1 (профілі public/alerts у telegram.env)

.EXAMPLES
  pwsh -NoProfile -File D:\CHECHA_CORE\TOOLS\Build-DAOIndexPackage.ps1 `
    -Version v2.0 -GitCommit -Push -VerboseSummary -NotifyPublic `
    -ExtraInclude @("D:\CHECHA_CORE\DAO-GOGS\docs\reports\DAO-GOGS_Weekly_Report_W43.md")
#>

,

  [string[]]  = @(),
  [string[]]  = @("*.tmp","*.log","*.zip","node_modules","bin","obj",".git"),

  [switch],
  [switch],
  [switch],

  [switch]True,
  [switch],
  [string]  = "D:\CHECHA_CORE\TOOLS\Telegram_AutoCore.ps1",
  [string]   = "public",
  [string]   = "alerts",

  [switch],

  # NEW
  [switch],
  [int] = 0,
  [switch],
  [switch]
)

  # додаткові файли (повні шляхи або маски)
  [string[]]$ExtraInclude  = @(),
  # глобальні виключення для ExtraInclude (маски)
  [string[]]$ExtraExclude  = @("*.tmp","*.log","*.zip","node_modules","bin","obj",".git"),

  # git
  [switch]$GitCommit,
  [switch]$Push,

  # зведення в кінці
  [switch]$VerboseSummary,

  # Telegram інтеграція (через Telegram_AutoCore.ps1)
  [switch]$NotifyPublic,
  [switch]$NotifyAlerts,
  [string]$TelegramScript  = "D:\CHECHA_CORE\TOOLS\Telegram_AutoCore.ps1",
  [string]$PublicProfile   = "public",
  [string]$AlertsProfile   = "alerts",

  # стабільний layout ZIP через staging-папку
  [switch]$UseStaging
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------- helpers --------------------
function Log([string]$m,[string]$lvl='INFO'){
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line = "[$lvl] $ts $m"
  Write-Host $line
  if ($script:__LogFile) { Add-Content -LiteralPath $script:__LogFile -Value $line }
}

function Ensure-Dir([string]$p){
  if (-not (Test-Path -LiteralPath $p)) {
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function Get-Sha256([string]$path){
  if(-not (Test-Path -LiteralPath $path)){ throw "SHA: file not found $path" }
  (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower()
}

function Escape-Html([string]$s){
  $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;').Replace("'","&#39;")
}

function Resolve-ExtraFiles([string[]]$includes,[string[]]$excludes){
  $resolved = @()
  foreach($it in $includes){
    if([string]::IsNullOrWhiteSpace($it)){ continue }
    if (Test-Path -LiteralPath $it) {
      $item = Get-Item -LiteralPath $it -ErrorAction SilentlyContinue
      if ($item -and -not $item.PSIsContainer) { $resolved += $item.FullName }
    } else {
      $dir  = Split-Path -Path $it -Parent
      $mask = Split-Path -Path $it -Leaf
      if([string]::IsNullOrWhiteSpace($dir)){ $dir = $PWD.Path }
      if (Test-Path -LiteralPath $dir) {
        $expanded = Get-ChildItem -LiteralPath $dir -Filter $mask -File -Recurse -ErrorAction SilentlyContinue
        if ($expanded) { $resolved += $expanded.FullName }
      }
    }
  }
  if ($excludes -and $excludes.Count) {
    $resolved = $resolved | Where-Object {
      $f = $_; -not ($excludes | Where-Object { $f -like $_ })
    }
  }
  $resolved | Sort-Object -Unique
}

function Call-Telegram([string]$profile,[string]$text,[string]$mode='HTML'){
  if(-not $NotifyPublic -and $profile -eq $PublicProfile){ return }
  if(-not $NotifyAlerts -and $profile -eq $AlertsProfile){ return }
  if(-not (Test-Path -LiteralPath $TelegramScript)){
    Log "Telegram script not found: $TelegramScript" "ERR"; return
  }
  try{
    pwsh -NoProfile -ExecutionPolicy Bypass `
      -File $TelegramScript `
      -Profile $profile `
      -Text $text `
      -Mode $mode | Out-Null
    Log "Telegram [$profile] notified" "INFO"
  } catch {
    $rsp = $_.Exception.Response
    if ($rsp) {
      try { $json = $rsp.Content.ReadAsStringAsync().Result } catch { $json = $_.ErrorDetails.Message }
      Log "Telegram [$profile] failed: $json" "ERR"
    } else {
      Log "Telegram [$profile] failed: $($_.Exception.Message)" "ERR"
    }
  }
}

# -------------------- start --------------------
# Підготуємо лог-файл на самому початку
Ensure-Dir $OutDir
$zipName = "DAO-ARCHITECTURE_{0}_{1}.zip" -f $Version, $ReleaseDate
$zipPath = Join-Path $OutDir $zipName
$shaPath = "$zipPath.sha256.txt"
$logPath = Join-Path $OutDir ("DAO-ARCHITECTURE_{0}_{1}.log" -f $Version, $ReleaseDate)
$script:__LogFile = $logPath

Log ("Start Build-DAOIndexPackage ({0}, {1})" -f $Version, $ReleaseDate)


# --- FILE LOCK ---
$lock = Join-Path $OutDir ".dao-arch.lock"
if (Test-Path $lock) {
  Log "Another build is running (lock present: $lock)" "ERR"
  if ($Strict) { throw "Concurrent build lock" } else { return }
}
New-Item -ItemType File -Path $lock -Force | Out-Null

try {
# Якщо ArchitectureDir помилково вказує на ФАЙЛ — перенесемо до ExtraInclude і відкотимо каталог
if ($ArchitectureDir -and (Test-Path -LiteralPath $ArchitectureDir -PathType Leaf)) {
  if (-not $ExtraInclude) { $ExtraInclude = @() }
  $ExtraInclude += (Get-Item -LiteralPath $ArchitectureDir).FullName
  $ArchitectureDir = "D:\CHECHA_CORE\DAO-GOGS\docs\architecture"
  Log "ArchitectureDir pointed to a FILE; moved to ExtraInclude and restored default architecture dir" "WARN"
}

# Нормалізуємо імена файлів (лише leaf)
if ($IndexName)    { $IndexName    = Split-Path -Path $IndexName    -Leaf }
if ($ReadmeName)   { $ReadmeName   = Split-Path -Path $ReadmeName   -Leaf }
if ($ChangelogName){
  if ([System.IO.Path]::IsPathRooted($ChangelogName)) {
    $ChangelogName = Split-Path -Path $ChangelogName -Leaf
  }
}

# Перевіримо каталог архітектури
if (-not $ArchitectureDir -or -not (Test-Path -LiteralPath $ArchitectureDir -PathType Container)) {
  Log "Catalog not found: $ArchitectureDir" "ERR"
  throw "Catalog not found: $ArchitectureDir"
}

# Шляхи основних файлів
$ReadmePath    = Join-Path $ArchitectureDir $ReadmeName
$IndexPath     = Join-Path $ArchitectureDir $IndexName
$ChangelogPath = Join-Path $ArchitectureDir $ChangelogName

# Перевірка обовʼязкових
$missing = @()
if (-not (Test-Path -LiteralPath $IndexPath))  { $missing += $IndexPath }
if (-not (Test-Path -LiteralPath $ReadmePath)) { $missing += $ReadmePath }
if (-not (Test-Path -LiteralPath $ChangelogPath)) { Log "WARN: Changelog not found: $ChangelogPath" "WARN" }
if ($missing.Count -gt 0) {
  $msg = "Required file(s) not found:`n - " + ($missing -join "`n - ")
  Log $msg "ERR"; throw $msg
}

# Розгортаємо ExtraInclude
$extraFiles = Resolve-ExtraFiles -includes $ExtraInclude -excludes $ExtraExclude

# Формуємо список файлів
$files = @($IndexPath, $ReadmePath)
if (Test-Path -LiteralPath $ChangelogPath) { $files += $ChangelogPath }
if ($extraFiles) { $files += $extraFiles }
$files = $files | Where-Object { Test-Path -LiteralPath $_ } | Sort-Object -Unique

if ($files.Count -lt 2) {
  throw "Not enough files to package. At least INDEX and README are required."
}

# Пакування (стабільний layout через staging за бажанням)
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
if ($UseStaging) {
  $stage = Join-Path $env:TEMP ("dao-arch-stage_{0}_{1}" -f $Version,$ReleaseDate)
  if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
  Ensure-Dir $stage
  # кладемо у staging з плоскими іменами (без дерев)
  foreach($f in $files){
    Copy-Item -LiteralPath $f -Destination (Join-Path $stage (Split-Path $f -Leaf)) -Force
  }
  Log ("Packing (staged): {0}" -f $zipPath)
  Compress-Archive -LiteralPath (Get-ChildItem -LiteralPath $stage -File).FullName -DestinationPath $zipPath -Force
  Remove-Item $stage -Recurse -Force
} else {
  Log ("Packing: {0}" -f $zipPath)
  Compress-Archive -LiteralPath $files -DestinationPath $zipPath -Force
}

# SHA256
$sha = Get-Sha256 $zipPath
$shaLine = "{0}  {1}" -f $sha, (Split-Path -Leaf $zipPath)
Set-Content -LiteralPath $shaPath -Value $shaLine -Encoding ASCII
Log ("SHA256: {0}" -f $sha)

# LOG-артефакт зі списком файлів
$art = @()
$art += "[INFO] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Build-DAOIndexPackage (${Version}, ${ReleaseDate})"
$art += "ZIP: $zipPath"
$art += "SHA256: $sha"
$art += ""
$art += "FILES:"
foreach($f in $files){
  $fi = Get-Item -LiteralPath $f
  $art += (" - {0}  ({1} bytes)" -f $fi.FullName, $fi.Length)
}
$art | Set-Content -LiteralPath $logPath -Encoding UTF8
# дублюємо останні рядки у runtime-лог
Log "Artifact log written" "DBG"

# Git (опційно)
if ($GitCommit) {
  try {
    # корінь репо = три рівні вгору від ArchitectureDir (architecture -> docs -> DAO-GOGS -> CHECHA_CORE)
    $repo = Split-Path -Path (Split-Path -Path (Split-Path -Path $ArchitectureDir -Parent) -Parent) -Parent
    Log "Git add artifacts & docs in $repo"
    git -C $repo add -- "$IndexPath" "$ReadmePath" 2>$null
    if (Test-Path -LiteralPath $ChangelogPath) { git -C $repo add -- "$ChangelogPath" 2>$null }
    git -C $repo add -- "$zipPath" "$shaPath" "$logPath" 2>$null

    $st = git -C $repo status --porcelain
    if ([string]::IsNullOrWhiteSpace($st)) {
      Log "Git: nothing to commit" "DBG"
    } else {
      $msg = "dao-architecture: ${Version} packaged (ZIP+SHA+LOG)"
      Log "Git commit: $msg"
      git -C $repo commit -m $msg | Out-Host
      if ($Push) {
        Log "Git push origin main"
        git -C $repo push origin main | Out-Host
      }
    }
  } catch {
    Log "Git step failed: $($_.Exception.Message)" "ERR"
  }
}

# Rotation (optional)
if ($Keep -gt 0) {
  try {
    $zips = Get-ChildItem -LiteralPath $OutDir -Filter "DAO-ARCHITECTURE_*.zip" | Sort-Object LastWriteTime -Desc
    $old  = $zips | Select-Object -Skip $Keep
    foreach($z in $old){
      $base  = [IO.Path]::GetFileNameWithoutExtension($z.Name)
      $sha   = Join-Path $OutDir "$($z.Name).sha256.txt"
      $log   = Join-Path $OutDir "$base.log"
      $json  = Join-Path $OutDir "$($z.Name).json"
      foreach($p in @($z.FullName,$sha,$log,$json)){
        if (Test-Path -LiteralPath $p) {
          Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        }
      }
      Log "Rotated out: $($z.Name)" "DBG"
    }
  } catch { Log "Rotation failed: $(<# 
.SYNOPSIS
  Збирає DAO-ARCHITECTURE пакет (INDEX/README/CHANGELOG [+ ExtraInclude]) у ZIP, рахує SHA256, формує LOG.
  Опційно комітить/пушить у git та шле нотифікацію в Telegram.

.REQUIRES
  PowerShell 7+

.DEPENDS (опційно)
  D:\CHECHA_CORE\TOOLS\Telegram_AutoCore.ps1 (профілі public/alerts у telegram.env)

.EXAMPLES
  pwsh -NoProfile -File D:\CHECHA_CORE\TOOLS\Build-DAOIndexPackage.ps1 `
    -Version v2.0 -GitCommit -Push -VerboseSummary -NotifyPublic `
    -ExtraInclude @("D:\CHECHA_CORE\DAO-GOGS\docs\reports\DAO-GOGS_Weekly_Report_W43.md")
#>

,

  [string[]]  = @(),
  [string[]]  = @("*.tmp","*.log","*.zip","node_modules","bin","obj",".git"),

  [switch],
  [switch],
  [switch],

  [switch]True,
  [switch],
  [string]  = "D:\CHECHA_CORE\TOOLS\Telegram_AutoCore.ps1",
  [string]   = "public",
  [string]   = "alerts",

  [switch],

  # NEW
  [switch],
  [int] = 0,
  [switch],
  [switch]
),

  # додаткові файли (повні шляхи або маски)
  [string[]]$ExtraInclude  = @(),
  # глобальні виключення для ExtraInclude (маски)
  [string[]]$ExtraExclude  = @("*.tmp","*.log","*.zip","node_modules","bin","obj",".git"),

  # git
  [switch]$GitCommit,
  [switch]$Push,

  # зведення в кінці
  [switch]$VerboseSummary,

  # Telegram інтеграція (через Telegram_AutoCore.ps1)
  [switch]$NotifyPublic,
  [switch]$NotifyAlerts,
  [string]$TelegramScript  = "D:\CHECHA_CORE\TOOLS\Telegram_AutoCore.ps1",
  [string]$PublicProfile   = "public",
  [string]$AlertsProfile   = "alerts",

  # стабільний layout ZIP через staging-папку
  [switch]$UseStaging
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------- helpers --------------------
function Log([string]$m,[string]$lvl='INFO'){
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line = "[$lvl] $ts $m"
  Write-Host $line
  if ($script:__LogFile) { Add-Content -LiteralPath $script:__LogFile -Value $line }
}

function Ensure-Dir([string]$p){
  if (-not (Test-Path -LiteralPath $p)) {
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function Get-Sha256([string]$path){
  if(-not (Test-Path -LiteralPath $path)){ throw "SHA: file not found $path" }
  (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower()
}

function Escape-Html([string]$s){
  $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;').Replace("'","&#39;")
}

function Resolve-ExtraFiles([string[]]$includes,[string[]]$excludes){
  $resolved = @()
  foreach($it in $includes){
    if([string]::IsNullOrWhiteSpace($it)){ continue }
    if (Test-Path -LiteralPath $it) {
      $item = Get-Item -LiteralPath $it -ErrorAction SilentlyContinue
      if ($item -and -not $item.PSIsContainer) { $resolved += $item.FullName }
    } else {
      $dir  = Split-Path -Path $it -Parent
      $mask = Split-Path -Path $it -Leaf
      if([string]::IsNullOrWhiteSpace($dir)){ $dir = $PWD.Path }
      if (Test-Path -LiteralPath $dir) {
        $expanded = Get-ChildItem -LiteralPath $dir -Filter $mask -File -Recurse -ErrorAction SilentlyContinue
        if ($expanded) { $resolved += $expanded.FullName }
      }
    }
  }
  if ($excludes -and $excludes.Count) {
    $resolved = $resolved | Where-Object {
      $f = $_; -not ($excludes | Where-Object { $f -like $_ })
    }
  }
  $resolved | Sort-Object -Unique
}

function Call-Telegram([string]$profile,[string]$text,[string]$mode='HTML'){
  if(-not $NotifyPublic -and $profile -eq $PublicProfile){ return }
  if(-not $NotifyAlerts -and $profile -eq $AlertsProfile){ return }
  if(-not (Test-Path -LiteralPath $TelegramScript)){
    Log "Telegram script not found: $TelegramScript" "ERR"; return
  }
  try{
    pwsh -NoProfile -ExecutionPolicy Bypass `
      -File $TelegramScript `
      -Profile $profile `
      -Text $text `
      -Mode $mode | Out-Null
    Log "Telegram [$profile] notified" "INFO"
  } catch {
    $rsp = $_.Exception.Response
    if ($rsp) {
      try { $json = $rsp.Content.ReadAsStringAsync().Result } catch { $json = $_.ErrorDetails.Message }
      Log "Telegram [$profile] failed: $json" "ERR"
    } else {
      Log "Telegram [$profile] failed: $($_.Exception.Message)" "ERR"
    }
  }
}

# -------------------- start --------------------
# Підготуємо лог-файл на самому початку
Ensure-Dir $OutDir
$zipName = "DAO-ARCHITECTURE_{0}_{1}.zip" -f $Version, $ReleaseDate
$zipPath = Join-Path $OutDir $zipName
$shaPath = "$zipPath.sha256.txt"
$logPath = Join-Path $OutDir ("DAO-ARCHITECTURE_{0}_{1}.log" -f $Version, $ReleaseDate)
$script:__LogFile = $logPath

Log ("Start Build-DAOIndexPackage ({0}, {1})" -f $Version, $ReleaseDate)


# --- FILE LOCK ---
$lock = Join-Path $OutDir ".dao-arch.lock"
if (Test-Path $lock) {
  Log "Another build is running (lock present: $lock)" "ERR"
  if ($Strict) { throw "Concurrent build lock" } else { return }
}
New-Item -ItemType File -Path $lock -Force | Out-Null

try {
# Якщо ArchitectureDir помилково вказує на ФАЙЛ — перенесемо до ExtraInclude і відкотимо каталог
if ($ArchitectureDir -and (Test-Path -LiteralPath $ArchitectureDir -PathType Leaf)) {
  if (-not $ExtraInclude) { $ExtraInclude = @() }
  $ExtraInclude += (Get-Item -LiteralPath $ArchitectureDir).FullName
  $ArchitectureDir = "D:\CHECHA_CORE\DAO-GOGS\docs\architecture"
  Log "ArchitectureDir pointed to a FILE; moved to ExtraInclude and restored default architecture dir" "WARN"
}

# Нормалізуємо імена файлів (лише leaf)
if ($IndexName)    { $IndexName    = Split-Path -Path $IndexName    -Leaf }
if ($ReadmeName)   { $ReadmeName   = Split-Path -Path $ReadmeName   -Leaf }
if ($ChangelogName){
  if ([System.IO.Path]::IsPathRooted($ChangelogName)) {
    $ChangelogName = Split-Path -Path $ChangelogName -Leaf
  }
}

# Перевіримо каталог архітектури
if (-not $ArchitectureDir -or -not (Test-Path -LiteralPath $ArchitectureDir -PathType Container)) {
  Log "Catalog not found: $ArchitectureDir" "ERR"
  throw "Catalog not found: $ArchitectureDir"
}

# Шляхи основних файлів
$ReadmePath    = Join-Path $ArchitectureDir $ReadmeName
$IndexPath     = Join-Path $ArchitectureDir $IndexName
$ChangelogPath = Join-Path $ArchitectureDir $ChangelogName

# Перевірка обовʼязкових
$missing = @()
if (-not (Test-Path -LiteralPath $IndexPath))  { $missing += $IndexPath }
if (-not (Test-Path -LiteralPath $ReadmePath)) { $missing += $ReadmePath }
if (-not (Test-Path -LiteralPath $ChangelogPath)) { Log "WARN: Changelog not found: $ChangelogPath" "WARN" }
if ($missing.Count -gt 0) {
  $msg = "Required file(s) not found:`n - " + ($missing -join "`n - ")
  Log $msg "ERR"; throw $msg
}

# Розгортаємо ExtraInclude
$extraFiles = Resolve-ExtraFiles -includes $ExtraInclude -excludes $ExtraExclude

# Формуємо список файлів
$files = @($IndexPath, $ReadmePath)
if (Test-Path -LiteralPath $ChangelogPath) { $files += $ChangelogPath }
if ($extraFiles) { $files += $extraFiles }
$files = $files | Where-Object { Test-Path -LiteralPath $_ } | Sort-Object -Unique

if ($files.Count -lt 2) {
  throw "Not enough files to package. At least INDEX and README are required."
}

# Пакування (стабільний layout через staging за бажанням)
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
if ($UseStaging) {
  $stage = Join-Path $env:TEMP ("dao-arch-stage_{0}_{1}" -f $Version,$ReleaseDate)
  if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
  Ensure-Dir $stage
  # кладемо у staging з плоскими іменами (без дерев)
  foreach($f in $files){
    Copy-Item -LiteralPath $f -Destination (Join-Path $stage (Split-Path $f -Leaf)) -Force
  }
  Log ("Packing (staged): {0}" -f $zipPath)
  Compress-Archive -LiteralPath (Get-ChildItem -LiteralPath $stage -File).FullName -DestinationPath $zipPath -Force
  Remove-Item $stage -Recurse -Force
} else {
  Log ("Packing: {0}" -f $zipPath)
  Compress-Archive -LiteralPath $files -DestinationPath $zipPath -Force
}

# SHA256
$sha = Get-Sha256 $zipPath
$shaLine = "{0}  {1}" -f $sha, (Split-Path -Leaf $zipPath)
Set-Content -LiteralPath $shaPath -Value $shaLine -Encoding ASCII
Log ("SHA256: {0}" -f $sha)

# LOG-артефакт зі списком файлів
$art = @()
$art += "[INFO] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Build-DAOIndexPackage (${Version}, ${ReleaseDate})"
$art += "ZIP: $zipPath"
$art += "SHA256: $sha"
$art += ""
$art += "FILES:"
foreach($f in $files){
  $fi = Get-Item -LiteralPath $f
  $art += (" - {0}  ({1} bytes)" -f $fi.FullName, $fi.Length)
}
$art | Set-Content -LiteralPath $logPath -Encoding UTF8
# дублюємо останні рядки у runtime-лог
Log "Artifact log written" "DBG"

# Git (опційно)
if ($GitCommit) {
  try {
    # корінь репо = три рівні вгору від ArchitectureDir (architecture -> docs -> DAO-GOGS -> CHECHA_CORE)
    $repo = Split-Path -Path (Split-Path -Path (Split-Path -Path $ArchitectureDir -Parent) -Parent) -Parent
    Log "Git add artifacts & docs in $repo"
    git -C $repo add -- "$IndexPath" "$ReadmePath" 2>$null
    if (Test-Path -LiteralPath $ChangelogPath) { git -C $repo add -- "$ChangelogPath" 2>$null }
    git -C $repo add -- "$zipPath" "$shaPath" "$logPath" 2>$null

    $st = git -C $repo status --porcelain
    if ([string]::IsNullOrWhiteSpace($st)) {
      Log "Git: nothing to commit" "DBG"
    } else {
      $msg = "dao-architecture: ${Version} packaged (ZIP+SHA+LOG)"
      Log "Git commit: $msg"
      git -C $repo commit -m $msg | Out-Host
      if ($Push) {
        Log "Git push origin main"
        git -C $repo push origin main | Out-Host
      }
    }
  } catch {
    Log "Git step failed: $($_.Exception.Message)" "ERR"
  }
}

# Telegram
if ($NotifyPublic -or $NotifyAlerts) {
  $zipLeaf = Split-Path -Leaf $zipPath
  $msgOk = "<b>DAO-GOGS</b> ${Version} зібрано. $(Escape-Html $zipLeaf)`nSHA256: <code>$sha</code>"
  if ($NotifyPublic) { Call-Telegram -profile $PublicProfile -text $msgOk -mode 'HTML' }
  if ($NotifyAlerts) {
    $msgWarn = "⛔ DAO-ARCHITECTURE ${Version}: перевірка/діагностика. ZIP: $zipLeaf"
    Call-Telegram -profile $AlertsProfile -text $msgWarn -mode 'Text'
  }
}

# GitHub Release (optional)
if ($ReleaseToGitHub) {
  try {
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) { throw "gh not found" }
    $tag = "dao-architecture-$Version"
    & gh release view $tag --json tagName 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
      & gh release create $tag $zipPath ($zipPath + ".sha256.txt") --notes "Architecture $Version"
    } else {
      & gh release upload $tag $zipPath ($zipPath + ".sha256.txt") --clobber
    }
    if ($LASTEXITCODE -ne 0) { throw "gh release step failed (exit $LASTEXITCODE)" }
    Log "GitHub release done: $tag" "INFO"
  } catch {
    Log "GitHub release failed: $(<# 
.SYNOPSIS
  Збирає DAO-ARCHITECTURE пакет (INDEX/README/CHANGELOG [+ ExtraInclude]) у ZIP, рахує SHA256, формує LOG.
  Опційно комітить/пушить у git та шле нотифікацію в Telegram.

.REQUIRES
  PowerShell 7+

.DEPENDS (опційно)
  D:\CHECHA_CORE\TOOLS\Telegram_AutoCore.ps1 (профілі public/alerts у telegram.env)

.EXAMPLES
  pwsh -NoProfile -File D:\CHECHA_CORE\TOOLS\Build-DAOIndexPackage.ps1 `
    -Version v2.0 -GitCommit -Push -VerboseSummary -NotifyPublic `
    -ExtraInclude @("D:\CHECHA_CORE\DAO-GOGS\docs\reports\DAO-GOGS_Weekly_Report_W43.md")
#>

,

  [string[]]  = @(),
  [string[]]  = @("*.tmp","*.log","*.zip","node_modules","bin","obj",".git"),

  [switch],
  [switch],
  [switch],

  [switch]True,
  [switch],
  [string]  = "D:\CHECHA_CORE\TOOLS\Telegram_AutoCore.ps1",
  [string]   = "public",
  [string]   = "alerts",

  [switch],

  # NEW
  [switch],
  [int] = 0,
  [switch],
  [switch]
),

  # додаткові файли (повні шляхи або маски)
  [string[]]$ExtraInclude  = @(),
  # глобальні виключення для ExtraInclude (маски)
  [string[]]$ExtraExclude  = @("*.tmp","*.log","*.zip","node_modules","bin","obj",".git"),

  # git
  [switch]$GitCommit,
  [switch]$Push,

  # зведення в кінці
  [switch]$VerboseSummary,

  # Telegram інтеграція (через Telegram_AutoCore.ps1)
  [switch]$NotifyPublic,
  [switch]$NotifyAlerts,
  [string]$TelegramScript  = "D:\CHECHA_CORE\TOOLS\Telegram_AutoCore.ps1",
  [string]$PublicProfile   = "public",
  [string]$AlertsProfile   = "alerts",

  # стабільний layout ZIP через staging-папку
  [switch]$UseStaging
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------- helpers --------------------
function Log([string]$m,[string]$lvl='INFO'){
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line = "[$lvl] $ts $m"
  Write-Host $line
  if ($script:__LogFile) { Add-Content -LiteralPath $script:__LogFile -Value $line }
}

function Ensure-Dir([string]$p){
  if (-not (Test-Path -LiteralPath $p)) {
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function Get-Sha256([string]$path){
  if(-not (Test-Path -LiteralPath $path)){ throw "SHA: file not found $path" }
  (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower()
}

function Escape-Html([string]$s){
  $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;').Replace("'","&#39;")
}

function Resolve-ExtraFiles([string[]]$includes,[string[]]$excludes){
  $resolved = @()
  foreach($it in $includes){
    if([string]::IsNullOrWhiteSpace($it)){ continue }
    if (Test-Path -LiteralPath $it) {
      $item = Get-Item -LiteralPath $it -ErrorAction SilentlyContinue
      if ($item -and -not $item.PSIsContainer) { $resolved += $item.FullName }
    } else {
      $dir  = Split-Path -Path $it -Parent
      $mask = Split-Path -Path $it -Leaf
      if([string]::IsNullOrWhiteSpace($dir)){ $dir = $PWD.Path }
      if (Test-Path -LiteralPath $dir) {
        $expanded = Get-ChildItem -LiteralPath $dir -Filter $mask -File -Recurse -ErrorAction SilentlyContinue
        if ($expanded) { $resolved += $expanded.FullName }
      }
    }
  }
  if ($excludes -and $excludes.Count) {
    $resolved = $resolved | Where-Object {
      $f = $_; -not ($excludes | Where-Object { $f -like $_ })
    }
  }
  $resolved | Sort-Object -Unique
}

function Call-Telegram([string]$profile,[string]$text,[string]$mode='HTML'){
  if(-not $NotifyPublic -and $profile -eq $PublicProfile){ return }
  if(-not $NotifyAlerts -and $profile -eq $AlertsProfile){ return }
  if(-not (Test-Path -LiteralPath $TelegramScript)){
    Log "Telegram script not found: $TelegramScript" "ERR"; return
  }
  try{
    pwsh -NoProfile -ExecutionPolicy Bypass `
      -File $TelegramScript `
      -Profile $profile `
      -Text $text `
      -Mode $mode | Out-Null
    Log "Telegram [$profile] notified" "INFO"
  } catch {
    $rsp = $_.Exception.Response
    if ($rsp) {
      try { $json = $rsp.Content.ReadAsStringAsync().Result } catch { $json = $_.ErrorDetails.Message }
      Log "Telegram [$profile] failed: $json" "ERR"
    } else {
      Log "Telegram [$profile] failed: $($_.Exception.Message)" "ERR"
    }
  }
}

# -------------------- start --------------------
# Підготуємо лог-файл на самому початку
Ensure-Dir $OutDir
$zipName = "DAO-ARCHITECTURE_{0}_{1}.zip" -f $Version, $ReleaseDate
$zipPath = Join-Path $OutDir $zipName
$shaPath = "$zipPath.sha256.txt"
$logPath = Join-Path $OutDir ("DAO-ARCHITECTURE_{0}_{1}.log" -f $Version, $ReleaseDate)
$script:__LogFile = $logPath

Log ("Start Build-DAOIndexPackage ({0}, {1})" -f $Version, $ReleaseDate)


# --- FILE LOCK ---
$lock = Join-Path $OutDir ".dao-arch.lock"
if (Test-Path $lock) {
  Log "Another build is running (lock present: $lock)" "ERR"
  if ($Strict) { throw "Concurrent build lock" } else { return }
}
New-Item -ItemType File -Path $lock -Force | Out-Null

try {
# Якщо ArchitectureDir помилково вказує на ФАЙЛ — перенесемо до ExtraInclude і відкотимо каталог
if ($ArchitectureDir -and (Test-Path -LiteralPath $ArchitectureDir -PathType Leaf)) {
  if (-not $ExtraInclude) { $ExtraInclude = @() }
  $ExtraInclude += (Get-Item -LiteralPath $ArchitectureDir).FullName
  $ArchitectureDir = "D:\CHECHA_CORE\DAO-GOGS\docs\architecture"
  Log "ArchitectureDir pointed to a FILE; moved to ExtraInclude and restored default architecture dir" "WARN"
}

# Нормалізуємо імена файлів (лише leaf)
if ($IndexName)    { $IndexName    = Split-Path -Path $IndexName    -Leaf }
if ($ReadmeName)   { $ReadmeName   = Split-Path -Path $ReadmeName   -Leaf }
if ($ChangelogName){
  if ([System.IO.Path]::IsPathRooted($ChangelogName)) {
    $ChangelogName = Split-Path -Path $ChangelogName -Leaf
  }
}

# Перевіримо каталог архітектури
if (-not $ArchitectureDir -or -not (Test-Path -LiteralPath $ArchitectureDir -PathType Container)) {
  Log "Catalog not found: $ArchitectureDir" "ERR"
  throw "Catalog not found: $ArchitectureDir"
}

# Шляхи основних файлів
$ReadmePath    = Join-Path $ArchitectureDir $ReadmeName
$IndexPath     = Join-Path $ArchitectureDir $IndexName
$ChangelogPath = Join-Path $ArchitectureDir $ChangelogName

# Перевірка обовʼязкових
$missing = @()
if (-not (Test-Path -LiteralPath $IndexPath))  { $missing += $IndexPath }
if (-not (Test-Path -LiteralPath $ReadmePath)) { $missing += $ReadmePath }
if (-not (Test-Path -LiteralPath $ChangelogPath)) { Log "WARN: Changelog not found: $ChangelogPath" "WARN" }
if ($missing.Count -gt 0) {
  $msg = "Required file(s) not found:`n - " + ($missing -join "`n - ")
  Log $msg "ERR"; throw $msg
}

# Розгортаємо ExtraInclude
$extraFiles = Resolve-ExtraFiles -includes $ExtraInclude -excludes $ExtraExclude

# Формуємо список файлів
$files = @($IndexPath, $ReadmePath)
if (Test-Path -LiteralPath $ChangelogPath) { $files += $ChangelogPath }
if ($extraFiles) { $files += $extraFiles }
$files = $files | Where-Object { Test-Path -LiteralPath $_ } | Sort-Object -Unique

if ($files.Count -lt 2) {
  throw "Not enough files to package. At least INDEX and README are required."
}

# Пакування (стабільний layout через staging за бажанням)
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
if ($UseStaging) {
  $stage = Join-Path $env:TEMP ("dao-arch-stage_{0}_{1}" -f $Version,$ReleaseDate)
  if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
  Ensure-Dir $stage
  # кладемо у staging з плоскими іменами (без дерев)
  foreach($f in $files){
    Copy-Item -LiteralPath $f -Destination (Join-Path $stage (Split-Path $f -Leaf)) -Force
  }
  Log ("Packing (staged): {0}" -f $zipPath)
  Compress-Archive -LiteralPath (Get-ChildItem -LiteralPath $stage -File).FullName -DestinationPath $zipPath -Force
  Remove-Item $stage -Recurse -Force
} else {
  Log ("Packing: {0}" -f $zipPath)
  Compress-Archive -LiteralPath $files -DestinationPath $zipPath -Force
}

# SHA256
$sha = Get-Sha256 $zipPath
$shaLine = "{0}  {1}" -f $sha, (Split-Path -Leaf $zipPath)
Set-Content -LiteralPath $shaPath -Value $shaLine -Encoding ASCII
Log ("SHA256: {0}" -f $sha)

# LOG-артефакт зі списком файлів
$art = @()
$art += "[INFO] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Build-DAOIndexPackage (${Version}, ${ReleaseDate})"
$art += "ZIP: $zipPath"
$art += "SHA256: $sha"
$art += ""
$art += "FILES:"
foreach($f in $files){
  $fi = Get-Item -LiteralPath $f
  $art += (" - {0}  ({1} bytes)" -f $fi.FullName, $fi.Length)
}
$art | Set-Content -LiteralPath $logPath -Encoding UTF8
# дублюємо останні рядки у runtime-лог
Log "Artifact log written" "DBG"

# Git (опційно)
if ($GitCommit) {
  try {
    # корінь репо = три рівні вгору від ArchitectureDir (architecture -> docs -> DAO-GOGS -> CHECHA_CORE)
    $repo = Split-Path -Path (Split-Path -Path (Split-Path -Path $ArchitectureDir -Parent) -Parent) -Parent
    Log "Git add artifacts & docs in $repo"
    git -C $repo add -- "$IndexPath" "$ReadmePath" 2>$null
    if (Test-Path -LiteralPath $ChangelogPath) { git -C $repo add -- "$ChangelogPath" 2>$null }
    git -C $repo add -- "$zipPath" "$shaPath" "$logPath" 2>$null

    $st = git -C $repo status --porcelain
    if ([string]::IsNullOrWhiteSpace($st)) {
      Log "Git: nothing to commit" "DBG"
    } else {
      $msg = "dao-architecture: ${Version} packaged (ZIP+SHA+LOG)"
      Log "Git commit: $msg"
      git -C $repo commit -m $msg | Out-Host
      if ($Push) {
        Log "Git push origin main"
        git -C $repo push origin main | Out-Host
      }
    }
  } catch {
    Log "Git step failed: $($_.Exception.Message)" "ERR"
  }
}

# Rotation (optional)
if ($Keep -gt 0) {
  try {
    $zips = Get-ChildItem -LiteralPath $OutDir -Filter "DAO-ARCHITECTURE_*.zip" | Sort-Object LastWriteTime -Desc
    $old  = $zips | Select-Object -Skip $Keep
    foreach($z in $old){
      $base  = [IO.Path]::GetFileNameWithoutExtension($z.Name)
      $sha   = Join-Path $OutDir "$($z.Name).sha256.txt"
      $log   = Join-Path $OutDir "$base.log"
      $json  = Join-Path $OutDir "$($z.Name).json"
      foreach($p in @($z.FullName,$sha,$log,$json)){
        if (Test-Path -LiteralPath $p) {
          Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        }
      }
      Log "Rotated out: $($z.Name)" "DBG"
    }
  } catch { Log "Rotation failed: $(<# 
.SYNOPSIS
  Збирає DAO-ARCHITECTURE пакет (INDEX/README/CHANGELOG [+ ExtraInclude]) у ZIP, рахує SHA256, формує LOG.
  Опційно комітить/пушить у git та шле нотифікацію в Telegram.

.REQUIRES
  PowerShell 7+

.DEPENDS (опційно)
  D:\CHECHA_CORE\TOOLS\Telegram_AutoCore.ps1 (профілі public/alerts у telegram.env)

.EXAMPLES
  pwsh -NoProfile -File D:\CHECHA_CORE\TOOLS\Build-DAOIndexPackage.ps1 `
    -Version v2.0 -GitCommit -Push -VerboseSummary -NotifyPublic `
    -ExtraInclude @("D:\CHECHA_CORE\DAO-GOGS\docs\reports\DAO-GOGS_Weekly_Report_W43.md")
#>

,

  [string[]]  = @(),
  [string[]]  = @("*.tmp","*.log","*.zip","node_modules","bin","obj",".git"),

  [switch],
  [switch],
  [switch],

  [switch]True,
  [switch],
  [string]  = "D:\CHECHA_CORE\TOOLS\Telegram_AutoCore.ps1",
  [string]   = "public",
  [string]   = "alerts",

  [switch],

  # NEW
  [switch],
  [int] = 0,
  [switch],
  [switch]
),

  # додаткові файли (повні шляхи або маски)
  [string[]]$ExtraInclude  = @(),
  # глобальні виключення для ExtraInclude (маски)
  [string[]]$ExtraExclude  = @("*.tmp","*.log","*.zip","node_modules","bin","obj",".git"),

  # git
  [switch]$GitCommit,
  [switch]$Push,

  # зведення в кінці
  [switch]$VerboseSummary,

  # Telegram інтеграція (через Telegram_AutoCore.ps1)
  [switch]$NotifyPublic,
  [switch]$NotifyAlerts,
  [string]$TelegramScript  = "D:\CHECHA_CORE\TOOLS\Telegram_AutoCore.ps1",
  [string]$PublicProfile   = "public",
  [string]$AlertsProfile   = "alerts",

  # стабільний layout ZIP через staging-папку
  [switch]$UseStaging
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------- helpers --------------------
function Log([string]$m,[string]$lvl='INFO'){
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line = "[$lvl] $ts $m"
  Write-Host $line
  if ($script:__LogFile) { Add-Content -LiteralPath $script:__LogFile -Value $line }
}

function Ensure-Dir([string]$p){
  if (-not (Test-Path -LiteralPath $p)) {
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function Get-Sha256([string]$path){
  if(-not (Test-Path -LiteralPath $path)){ throw "SHA: file not found $path" }
  (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower()
}

function Escape-Html([string]$s){
  $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;').Replace("'","&#39;")
}

function Resolve-ExtraFiles([string[]]$includes,[string[]]$excludes){
  $resolved = @()
  foreach($it in $includes){
    if([string]::IsNullOrWhiteSpace($it)){ continue }
    if (Test-Path -LiteralPath $it) {
      $item = Get-Item -LiteralPath $it -ErrorAction SilentlyContinue
      if ($item -and -not $item.PSIsContainer) { $resolved += $item.FullName }
    } else {
      $dir  = Split-Path -Path $it -Parent
      $mask = Split-Path -Path $it -Leaf
      if([string]::IsNullOrWhiteSpace($dir)){ $dir = $PWD.Path }
      if (Test-Path -LiteralPath $dir) {
        $expanded = Get-ChildItem -LiteralPath $dir -Filter $mask -File -Recurse -ErrorAction SilentlyContinue
        if ($expanded) { $resolved += $expanded.FullName }
      }
    }
  }
  if ($excludes -and $excludes.Count) {
    $resolved = $resolved | Where-Object {
      $f = $_; -not ($excludes | Where-Object { $f -like $_ })
    }
  }
  $resolved | Sort-Object -Unique
}

function Call-Telegram([string]$profile,[string]$text,[string]$mode='HTML'){
  if(-not $NotifyPublic -and $profile -eq $PublicProfile){ return }
  if(-not $NotifyAlerts -and $profile -eq $AlertsProfile){ return }
  if(-not (Test-Path -LiteralPath $TelegramScript)){
    Log "Telegram script not found: $TelegramScript" "ERR"; return
  }
  try{
    pwsh -NoProfile -ExecutionPolicy Bypass `
      -File $TelegramScript `
      -Profile $profile `
      -Text $text `
      -Mode $mode | Out-Null
    Log "Telegram [$profile] notified" "INFO"
  } catch {
    $rsp = $_.Exception.Response
    if ($rsp) {
      try { $json = $rsp.Content.ReadAsStringAsync().Result } catch { $json = $_.ErrorDetails.Message }
      Log "Telegram [$profile] failed: $json" "ERR"
    } else {
      Log "Telegram [$profile] failed: $($_.Exception.Message)" "ERR"
    }
  }
}

# -------------------- start --------------------
# Підготуємо лог-файл на самому початку
Ensure-Dir $OutDir
$zipName = "DAO-ARCHITECTURE_{0}_{1}.zip" -f $Version, $ReleaseDate
$zipPath = Join-Path $OutDir $zipName
$shaPath = "$zipPath.sha256.txt"
$logPath = Join-Path $OutDir ("DAO-ARCHITECTURE_{0}_{1}.log" -f $Version, $ReleaseDate)
$script:__LogFile = $logPath

Log ("Start Build-DAOIndexPackage ({0}, {1})" -f $Version, $ReleaseDate)


# --- FILE LOCK ---
$lock = Join-Path $OutDir ".dao-arch.lock"
if (Test-Path $lock) {
  Log "Another build is running (lock present: $lock)" "ERR"
  if ($Strict) { throw "Concurrent build lock" } else { return }
}
New-Item -ItemType File -Path $lock -Force | Out-Null

try {
# Якщо ArchitectureDir помилково вказує на ФАЙЛ — перенесемо до ExtraInclude і відкотимо каталог
if ($ArchitectureDir -and (Test-Path -LiteralPath $ArchitectureDir -PathType Leaf)) {
  if (-not $ExtraInclude) { $ExtraInclude = @() }
  $ExtraInclude += (Get-Item -LiteralPath $ArchitectureDir).FullName
  $ArchitectureDir = "D:\CHECHA_CORE\DAO-GOGS\docs\architecture"
  Log "ArchitectureDir pointed to a FILE; moved to ExtraInclude and restored default architecture dir" "WARN"
}

# Нормалізуємо імена файлів (лише leaf)
if ($IndexName)    { $IndexName    = Split-Path -Path $IndexName    -Leaf }
if ($ReadmeName)   { $ReadmeName   = Split-Path -Path $ReadmeName   -Leaf }
if ($ChangelogName){
  if ([System.IO.Path]::IsPathRooted($ChangelogName)) {
    $ChangelogName = Split-Path -Path $ChangelogName -Leaf
  }
}

# Перевіримо каталог архітектури
if (-not $ArchitectureDir -or -not (Test-Path -LiteralPath $ArchitectureDir -PathType Container)) {
  Log "Catalog not found: $ArchitectureDir" "ERR"
  throw "Catalog not found: $ArchitectureDir"
}

# Шляхи основних файлів
$ReadmePath    = Join-Path $ArchitectureDir $ReadmeName
$IndexPath     = Join-Path $ArchitectureDir $IndexName
$ChangelogPath = Join-Path $ArchitectureDir $ChangelogName

# Перевірка обовʼязкових
$missing = @()
if (-not (Test-Path -LiteralPath $IndexPath))  { $missing += $IndexPath }
if (-not (Test-Path -LiteralPath $ReadmePath)) { $missing += $ReadmePath }
if (-not (Test-Path -LiteralPath $ChangelogPath)) { Log "WARN: Changelog not found: $ChangelogPath" "WARN" }
if ($missing.Count -gt 0) {
  $msg = "Required file(s) not found:`n - " + ($missing -join "`n - ")
  Log $msg "ERR"; throw $msg
}

# Розгортаємо ExtraInclude
$extraFiles = Resolve-ExtraFiles -includes $ExtraInclude -excludes $ExtraExclude

# Формуємо список файлів
$files = @($IndexPath, $ReadmePath)
if (Test-Path -LiteralPath $ChangelogPath) { $files += $ChangelogPath }
if ($extraFiles) { $files += $extraFiles }
$files = $files | Where-Object { Test-Path -LiteralPath $_ } | Sort-Object -Unique

if ($files.Count -lt 2) {
  throw "Not enough files to package. At least INDEX and README are required."
}

# Пакування (стабільний layout через staging за бажанням)
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
if ($UseStaging) {
  $stage = Join-Path $env:TEMP ("dao-arch-stage_{0}_{1}" -f $Version,$ReleaseDate)
  if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
  Ensure-Dir $stage
  # кладемо у staging з плоскими іменами (без дерев)
  foreach($f in $files){
    Copy-Item -LiteralPath $f -Destination (Join-Path $stage (Split-Path $f -Leaf)) -Force
  }
  Log ("Packing (staged): {0}" -f $zipPath)
  Compress-Archive -LiteralPath (Get-ChildItem -LiteralPath $stage -File).FullName -DestinationPath $zipPath -Force
  Remove-Item $stage -Recurse -Force
} else {
  Log ("Packing: {0}" -f $zipPath)
  Compress-Archive -LiteralPath $files -DestinationPath $zipPath -Force
}

# SHA256
$sha = Get-Sha256 $zipPath
$shaLine = "{0}  {1}" -f $sha, (Split-Path -Leaf $zipPath)
Set-Content -LiteralPath $shaPath -Value $shaLine -Encoding ASCII
Log ("SHA256: {0}" -f $sha)

# LOG-артефакт зі списком файлів
$art = @()
$art += "[INFO] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Build-DAOIndexPackage (${Version}, ${ReleaseDate})"
$art += "ZIP: $zipPath"
$art += "SHA256: $sha"
$art += ""
$art += "FILES:"
foreach($f in $files){
  $fi = Get-Item -LiteralPath $f
  $art += (" - {0}  ({1} bytes)" -f $fi.FullName, $fi.Length)
}
$art | Set-Content -LiteralPath $logPath -Encoding UTF8
# дублюємо останні рядки у runtime-лог
Log "Artifact log written" "DBG"

# Git (опційно)
if ($GitCommit) {
  try {
    # корінь репо = три рівні вгору від ArchitectureDir (architecture -> docs -> DAO-GOGS -> CHECHA_CORE)
    $repo = Split-Path -Path (Split-Path -Path (Split-Path -Path $ArchitectureDir -Parent) -Parent) -Parent
    Log "Git add artifacts & docs in $repo"
    git -C $repo add -- "$IndexPath" "$ReadmePath" 2>$null
    if (Test-Path -LiteralPath $ChangelogPath) { git -C $repo add -- "$ChangelogPath" 2>$null }
    git -C $repo add -- "$zipPath" "$shaPath" "$logPath" 2>$null

    $st = git -C $repo status --porcelain
    if ([string]::IsNullOrWhiteSpace($st)) {
      Log "Git: nothing to commit" "DBG"
    } else {
      $msg = "dao-architecture: ${Version} packaged (ZIP+SHA+LOG)"
      Log "Git commit: $msg"
      git -C $repo commit -m $msg | Out-Host
      if ($Push) {
        Log "Git push origin main"
        git -C $repo push origin main | Out-Host
      }
    }
  } catch {
    Log "Git step failed: $($_.Exception.Message)" "ERR"
  }
}

# Telegram
if ($NotifyPublic -or $NotifyAlerts) {
  $zipLeaf = Split-Path -Leaf $zipPath
  $msgOk = "<b>DAO-GOGS</b> ${Version} зібрано. $(Escape-Html $zipLeaf)`nSHA256: <code>$sha</code>"
  if ($NotifyPublic) { Call-Telegram -profile $PublicProfile -text $msgOk -mode 'HTML' }
  if ($NotifyAlerts) {
    $msgWarn = "⛔ DAO-ARCHITECTURE ${Version}: перевірка/діагностика. ZIP: $zipLeaf"
    Call-Telegram -profile $AlertsProfile -text $msgWarn -mode 'Text'
  }
}
# Summary
if () {
  Write-Host "=== SUMMARY ==="
  Write-Host ("ZIP:      {0}" -f )
  Write-Host ("SHA256:   {0}" -f )
  Write-Host ("SHA FILE: {0}" -f )
  Write-Host ("LOG:      {0}" -f )
}
} finally {
  if (Test-Path D:\CHECHA_CORE\C03_LOG\reports\.dao-arch.lock) { Remove-Item D:\CHECHA_CORE\C03_LOG\reports\.dao-arch.lock -Force -ErrorAction SilentlyContinue }
}
Log "Done Build-DAOIndexPackage"
exit 0

