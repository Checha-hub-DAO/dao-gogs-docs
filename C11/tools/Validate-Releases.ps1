[CmdletBinding()]
param(
  [switch]$All,
  [string[]]$Module,
  [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Визначаємо C11 root з розташування скрипта
$C11Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$RepoRoot = (Resolve-Path (Join-Path $C11Root "..")).Path
$LogDir = Join-Path $RepoRoot "C03\LOG"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogPath = Join-Path $LogDir "releases_validate.log"

$script:hadWarn  = $false
$script:hadError = $false
$ts = { (Get-Date -Format "yyyy-MM-dd HH:mm:ss") }

function LogInfo([string]$m){
  $line = "{0} [INFO] {1}" -f (& $ts), $m
  $line | Tee-Object -FilePath $LogPath -Append | Out-Null
  Write-Host $line
}
function LogWarn([string]$m){
  $script:hadWarn = $true
  $line = "{0} [WARN] {1}" -f (& $ts), $m
  $line | Tee-Object -FilePath $LogPath -Append | Out-Null
  Write-Warning $m
}
function LogErr([string]$m){
  $script:hadError = $true
  $line = "{0} [ERROR] {1}" -f (& $ts), $m
  $line | Tee-Object -FilePath $LogPath -Append | Out-Null
  Write-Error $m
}

# Модулі для перевірки
$modules = @()
if ($All) {
  $modules = Get-ChildItem $C11Root -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'Release') } | Select-Object -ExpandProperty Name
}
elseif ($Module) { $modules = $Module }
else { LogErr "Specify -All or -Module"; exit 1 }

foreach ($m in $modules) {
  $modRoot   = Join-Path $C11Root $m
  $release   = Join-Path $modRoot "Release"
  $archive   = Join-Path $modRoot "Archive"
  $checksums = Join-Path $archive "CHECKSUMS.txt"

  LogInfo "Module: $m | ReleaseDir: $release"

  if (-not (Test-Path $release)) { LogWarn "No Release dir: $release"; continue }

  $zips = Get-ChildItem $release -Filter *.zip -File -ErrorAction SilentlyContinue
  if (-not $zips) { LogWarn "No ZIPs found in: $release"; continue }

  $map = @{}
  if (Test-Path $checksums) {
    $lines = Get-Content $checksums -ErrorAction SilentlyContinue | Where-Object { $_ -match '\S' }
    foreach ($ln in $lines) {
      if ($ln -match '^(?<hash>[A-Fa-f0-9]{64}) \*(?<name>.+)$') {
        $map[$matches.name] = $matches.hash.ToUpper()
      } else {
        LogWarn "Malformed line in CHECKSUMS: $ln"
      }
    }
  } else {
    LogWarn "No CHECKSUMS.txt: $checksums"
  }

  foreach ($z in $zips) {
    $h = (Get-FileHash $z.FullName -Algorithm SHA256).Hash.ToUpper()
    if ($map.ContainsKey($z.Name)) {
      if ($map[$z.Name] -ne $h) { LogErr "Hash mismatch for $($z.Name): expected $($map[$z.Name]), got $h" }
      else { LogInfo "OK: $($z.Name)" }
    } else {
      LogWarn "No entry in CHECKSUMS for: $($z.Name)"
      LogInfo "OK: $($z.Name)"
    }
  }
}

# Exit code логіка (CI «м’якший»)
$inCI = ($env:GITHUB_ACTIONS -eq 'true')
$rc =
  if     ($script:hadError)                                 { 1 }
  elseif ($script:hadWarn -and ($Strict -or -not $inCI))    { 1 }
  else                                                      { 0 }

exit $rc
