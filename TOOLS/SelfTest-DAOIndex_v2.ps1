# SelfTest-DAOIndex_v2.ps1
# Інтеграційний self-test для Build-DAOIndexPackage.ps1
# Запускає реальну збірку, перевіряє артефакти, ZIP-вміст, SHA, лог; робить негативний тест.
# PS 7+

[CmdletBinding()]
param(
  [string]$PackerPath      = "D:\CHECHA_CORE\TOOLS\Build-DAOIndexPackage.ps1",
  [string]$ArchitectureDir = "D:\CHECHA_CORE\DAO-GOGS\docs\architecture",
  [string]$OutDir          = "D:\CHECHA_CORE\C03_LOG\reports",
  [string]$Version         = "v2.0",
  [string]$ReleaseDate     = (Get-Date -Format 'yyyy-MM-dd'),
  [switch]$UseStaging      = $true,
  [switch]$NotifyPublic,                 # якщо вказати — self-test перевірить, що виклик не падає
  [switch]$RunNegativeCase = $true,      # тест з неіснуючим каталого́м
  [switch]$CheckZip        = $true,      # розпакувати ZIP і перевірити наявність файлів
  [switch]$VerboseSummary  = $true
)

$ErrorActionPreference = "Stop"

# ------------------ helpers ------------------
$global:_Pass = 0
$global:_Fail = 0
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'

function Say([string]$m,[string]$lvl='INFO'){
  $c = switch ($lvl) { 'OK' {'Green'} 'ERR' {'Red'} 'WARN' {'Yellow'} default {'Gray'} }
  Write-Host ("[{0}] {1}" -f $lvl,$m) -ForegroundColor $c
}

function Pass([string]$m){ $global:_Pass++; Say $m 'OK' }
function Fail([string]$m){ $global:_Fail++; Say $m 'ERR' }

function Assert-True($cond,[string]$msg){
  if ($cond) { Pass $msg } else { Fail $msg }
}

function Latest-Artifacts([string]$dir){
  $zip = Get-ChildItem -LiteralPath $dir -Filter "DAO-ARCHITECTURE_*.zip" | Sort-Object LastWriteTime -Desc | Select-Object -First 1
  if (-not $zip) { return $null }
  $base = $zip.FullName
  return [ordered]@{
    Zip = Get-Item $base
    Sha = Get-Item ($base + ".sha256.txt")
    Log = Get-Item ((Split-Path $base -Parent) + "\" + [IO.Path]::GetFileNameWithoutExtension($zip.Name) + ".log")
  }
}

# ------------------ preflight ------------------
Say "SelfTest v2 start: Version=$Version, Date=$ReleaseDate"
if (-not (Test-Path -LiteralPath $PackerPath)) { throw "Packer not found: $PackerPath" }
if (-not (Test-Path -LiteralPath $ArchitectureDir -PathType Container)) { throw "Architecture dir missing: $ArchitectureDir" }
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

$index = Join-Path $ArchitectureDir "DAO-GOGS_INDEX_${Version}_$($ReleaseDate.Substring(0,4))-10.md"
# індекс могла мати іншу назву (фіксовано в скрипті) — перевіримо через реальні імени:
$index = Join-Path $ArchitectureDir "DAO-GOGS_INDEX_v2.0_2025-10.md"
$readme = Join-Path $ArchitectureDir "README.md"
$changelog = Join-Path $ArchitectureDir "changelog\CHANGELOG_v2.0.md"

Assert-True (Test-Path -LiteralPath $index)   "INDEX present"
Assert-True (Test-Path -LiteralPath $readme)  "README present"
if (Test-Path -LiteralPath $changelog) { Pass "CHANGELOG present" } else { Say "CHANGELOG missing (WARN expected) 'optional'" 'WARN' }

# ------------------ 1) Positive build ------------------
try{
  & $PackerPath -Version $Version -ReleaseDate $ReleaseDate -OutDir $OutDir -UseStaging -VerboseSummary
  Pass "Build succeeded (positive)"
} catch {
  Fail "Build failed (positive): $($_.Exception.Message)"
  throw
}

# locate artifacts
$arts = Latest-Artifacts $OutDir
if (-not $arts) { Fail "No artifacts found in $OutDir"; throw "Artifacts missing" }

# 1a) Files exist
Assert-True (Test-Path -LiteralPath $arts.Zip.FullName) "ZIP exists: $($arts.Zip.Name)"
Assert-True (Test-Path -LiteralPath $arts.Sha.FullName) "SHA file exists: $($arts.Sha.Name)"
Assert-True (Test-Path -LiteralPath $arts.Log.FullName) "LOG exists: $($arts.Log.Name)"

# 1b) SHA matches
$shaInFile = (Get-Content -LiteralPath $arts.Sha.FullName -Raw).Split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)[0]
$shaActual = (Get-FileHash -Algorithm SHA256 -LiteralPath $arts.Zip.FullName).Hash.ToLower()
Assert-True ($shaActual -eq $shaInFile) "SHA256 matches"

# 1c) Log contains Index/Readme lines
$logText = Get-Content -LiteralPath $arts.Log.FullName -Raw
Assert-True ($logText -match [regex]::Escape((Split-Path -Leaf $index)))  "LOG lists INDEX"
Assert-True ($logText -match [regex]::Escape((Split-Path -Leaf $readme))) "LOG lists README"

# 1d) Optional: check ZIP contents
if ($CheckZip) {
  $dst = Join-Path $env:TEMP "_dao_arch_check_$stamp"
  if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $dst | Out-Null
  Expand-Archive -LiteralPath $arts.Zip.FullName -DestinationPath $dst -Force
  $unzipped = Get-ChildItem -LiteralPath $dst -File | Select-Object -Expand Name
  Assert-True ($unzipped -match 'DAO-GOGS_INDEX_.*\.md') "ZIP contains INDEX"
  Assert-True ($unzipped -contains 'README.md')          "ZIP contains README"
  if ($unzipped -contains 'CHANGELOG_v2.0.md') { Pass "ZIP contains CHANGELOG" } else { Say "ZIP missing CHANGELOG (optional)" 'WARN' }
  Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue
}

# ------------------ 2) Notify (optional) ------------------
if ($NotifyPublic) {
  try{
    & $PackerPath -Version $Version -ReleaseDate $ReleaseDate -OutDir $OutDir -UseStaging -NotifyPublic
    Pass "NotifyPublic call returned OK"
  } catch {
    Fail "NotifyPublic failed: $($_.Exception.Message)"
  }
}

# ------------------ 3) Negative build ------------------
if ($RunNegativeCase) {
  try{
    & $PackerPath -ArchitectureDir "D:\__NOPE__" -ReleaseDate $ReleaseDate -OutDir $OutDir -UseStaging
    Fail "Negative case unexpectedly succeeded"
  } catch {
    if ($_.Exception.Message -match 'Catalog not found') {
      Pass "Negative case failed as expected (Catalog not found)"
    } else {
      Fail "Negative case wrong error: $($_.Exception.Message)"
    }
  }
}

# ------------------ Summary ------------------
$tot = $global:_Pass + $global:_Fail
Write-Host ""
Write-Host "===== SELFTEST SUMMARY ====="
Write-Host ("Total: {0}  PASS: {1}  FAIL: {2}" -f $tot,$global:_Pass,$global:_Fail) -ForegroundColor Cyan
if ($VerboseSummary) {
  Write-Host ("ZIP: {0}" -f $arts.Zip.FullName)
  Write-Host ("SHA: {0}" -f $shaActual)
  Write-Host ("LOG: {0}" -f $arts.Log.FullName)
}
if ($global:_Fail -gt 0) { exit 2 } else { exit 0 }
