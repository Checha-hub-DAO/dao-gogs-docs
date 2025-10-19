# D:\CHECHA_CORE\TOOLS\Install-CheChaProfile.ps1
[CmdletBinding()]
param(
    [string]$CoreRoot = "D:\CHECHA_CORE",
    [string]$ToolsDir = "D:\CHECHA_CORE\TOOLS",
    [string]$DashPath = "D:\CHECHA_CORE\Dashboard.md",
    [switch]$NoAutoOpen,          # не відкривати Dashboard при старті
    [switch]$NoAliases,           # не створювати аліаси/функції
    [switch]$AddToolsToModulePath # додати TOOLS в PSModulePath поточного користувача
)

function Add-Once($Path, [string]$Marker, [string]$Snippet) {
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType File -Path $Path -Force | Out-Null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    if ($raw -notmatch [regex]::Escape($Marker)) {
        Add-Content -LiteralPath $Path -Value "`r`n# $Marker`r`n$Snippet`r`n"
        return $true
    }
    return $false
}

$profilePath = $PROFILE
$changed = $false
Write-Host "[CHECHA] Installing profile → $profilePath"

# 1) Автовідкриття Dashboard (один раз на сесію)
if (-not $NoAutoOpen) {
    $marker1 = "CheCha: auto-open dashboard"
    $snippet1 = @"
`$dash = "$DashPath"
try {
  if (Test-Path -LiteralPath `$dash) {
    if (-not (Get-Variable -Name CheChaDashOpened -Scope Global -ErrorAction SilentlyContinue)) {
      `$global:CheChaDashOpened = `$true
      Start-Process -FilePath `$dash
    }
  }
} catch {}
"@
    if (Add-Once -Path $profilePath -Marker $marker1 -Snippet $snippet1) { $changed = $true; Write-Host "[OK] Auto-open dashboard added" }
    else { Write-Host "[OK] Auto-open dashboard already present" }
}

# 2) Аліаси/утиліти
if (-not $NoAliases) {
    $marker2 = "CheCha: aliases & helpers"
    $snippet2 = @"
function Invoke-CheChaDashboard {
  pwsh -NoProfile -ExecutionPolicy Bypass -File "$ToolsDir\Build-Dashboard.ps1"
  if (Test-Path "$DashPath") { Invoke-Item "$DashPath" }
}
function Invoke-CheChaManifest {
  pwsh -NoProfile -ExecutionPolicy Bypass -File "$ToolsDir\Build-MANIFEST.ps1"
  if (Test-Path "$CoreRoot\MANIFEST.md") { Invoke-Item "$CoreRoot\MANIFEST.md" }
}
Set-Alias checha-dash Invoke-CheChaDashboard -ErrorAction SilentlyContinue
Set-Alias checha-man  Invoke-CheChaManifest  -ErrorAction SilentlyContinue
"@
    if (Add-Once -Path $profilePath -Marker $marker2 -Snippet $snippet2) { $changed = $true; Write-Host "[OK] Aliases added (checha-dash / checha-man)" }
    else { Write-Host "[OK] Aliases already present" }
}

# 3) (опц.) Додати TOOLS у PSModulePath (User scope)
if ($AddToolsToModulePath) {
    $marker3 = "CheCha: PSModulePath (TOOLS)"
    $snippet3 = @"
try {
  if (-not (`$env:PSModulePath -split ';' | Where-Object { `$_ -ieq "$ToolsDir" })) {
    `$env:PSModulePath = "$ToolsDir;" + `$env:PSModulePath
  }
} catch {}
"@
    if (Add-Once -Path $profilePath -Marker $marker3 -Snippet $snippet3) { $changed = $true; Write-Host "[OK] TOOLS added to PSModulePath" }
    else { Write-Host "[OK] PSModulePath snippet already present" }
}

# 4) Завантажити профіль у поточну сесію
. $profilePath
Write-Host "[CHECHA] Profile reloaded."
if ($changed) { Write-Host "[CHECHA] Installed/updated successfully." } else { Write-Host "[CHECHA] No changes (already up-to-date)." }

