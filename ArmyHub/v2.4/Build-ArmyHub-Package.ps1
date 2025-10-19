param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir,
    [Parameter(Mandatory = $true)]
    [string]$OutDir,
    [string]$Version = "v2.4",
    [string]$PackageName = "ArmyHub_Officer_Package",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function New-CleanDir($Path) {
    if (Test-Path $Path) { Remove-Item -Recurse -Force $Path }
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Write-Info($msg) { Write-Information "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Information "[WARN] $msg" -ForegroundColor Yellow }
function Write-Ok($msg) { Write-Information "[OK]   $msg" -ForegroundColor Green }
function Sha256($path) { (Get-FileHash -Algorithm SHA256 -Path $path).Hash.ToLower() }

# Validate input
if (-not (Test-Path $SourceDir)) { throw "SourceDir not found: $SourceDir" }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

# Staging layout
$Stage = Join-Path $env:TEMP ("ArmyHub_pkg_" + [guid]::NewGuid())
$RootDir = Join-Path $Stage "root"
$Extras = Join-Path $RootDir "extras"
New-CleanDir $RootDir
New-CleanDir $Extras

# Expected files (relative names inside package -> candidate paths at SourceDir)
$expected = @{
    "README.md"                          = @("README.md")
    "MANIFEST.md"                        = @("MANIFEST.md")
    "CHANGELOG.md"                       = @("CHANGELOG.md")
    "Officer_Package_Overview.md"        = @("Officer_Package_Overview.md")
    "Strategic_Analysis_Report_v1.0.pdf" = @("ArmyHub_Strategic_Analysis_Report_v1.0.pdf", "Strategic_Analysis_Report_v1.0.pdf")
    "Tech_Map_ARMY.png"                  = @("ArmyHub_TechMap_Infographic.png", "Tech_Map_ARMY.png")
    "Roadmap_ARMY.png"                   = @("ArmyHub_Roadmap_Infographic.png", "Roadmap_ARMY.png")
    "Implementation_Guide.pdf"           = @("ArmyHub_Implementation_Guide_MVP_v1.0.pdf", "Implementation_Guide.pdf")
    "extras\Structure_ARMY.png"          = @("ArmyHub_Structure_Infographic.png", "Structure_ARMY.png")
}

# Copy files (generate defaults where needed)
foreach ($kv in $expected.GetEnumerator()) {
    $arcName = $kv.Key
    $candidates = $kv.Value | ForEach-Object { Join-Path $SourceDir $_ }
    $destPath = Join-Path $RootDir $arcName
    $destDir = Split-Path $destPath -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

    $found = $false
    foreach ($cand in $candidates) {
        if (Test-Path $cand) {
            Copy-Item $cand $destPath -Force
            Write-Info "Added: $arcName  (from: $(Split-Path $cand -Leaf))"
            $found = $true
            break
        }
        if (-not $found) {
        }
    }
}
switch ($arcName) {
    "CHANGELOG.md" {
        $today = Get-Date -Format yyyy-MM-dd
        @"
                    # CHANGELOG
                    ## $Version ($today)
                    
                    - Initial release of Officer Package $Version (Overview, Strategic Report, Tech/ Roadmap infographics, Implementation Guide).
                    "@ | Set-Content -Path $destPath -Encoding UTF8
                    Write-Warning "Generated default CHANGELOG.md"
                    break
                }
                "MANIFEST.md" {
                    # placeholder; real manifest will be generated later
                    "" | Set-Content -Path $destPath -Encoding UTF8
                    break
                }
                Default {
                    Write-Warning "Missing optional: $arcName (no source file found)"
                    break
                }
            }

            # Generate MANIFEST.md with SHA256 + sizes
            $manifestPath = Join-Path $RootDir "MANIFEST.md"
            $items = Get-ChildItem -Recurse -File $RootDir | Sort-Object FullName
            $lines = @("# MANIFEST", "", "| File | Size (bytes) | SHA256 |", "|------|--------------:|--------|")
            foreach ($it in $items) {
                $rel = Resolve-Path $it.FullName -Relative | ForEach-Object { $_ -replace "^\.\.\\", "" }
                $hash = Sha256 $it.FullName
                $lines += "| $rel | $($it.Length) | $hash |"
            }
            $lines | Set-Content -Path $manifestPath -Encoding UTF8

            # Compress to ZIP
            $zipName = "${PackageName}_${Version}_FINAL.zip"
            $zipPath = Join-Path $OutDir $zipName
            if ((Test-Path $zipPath) -and -not $Force) {
                throw "Destination already exists: $zipPath (use -Force to overwrite)"
            }

            if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
            Compress-Archive -Path (Join-Path $RootDir "*") -DestinationPath $zipPath -Force

            # Write checksum of ZIP
            $zipSha = Sha256 $zipPath
            $shaFile = "$zipPath.sha256"
            "$zipSha  $(Split-Path $zipPath -Leaf)" | Set-Content -Path $shaFile -Encoding ASCII

            Write-Ok "Built package: $zipPath"
            Write-Ok "SHA256: $zipSha"
            Write-Info "Staging: $Stage"








