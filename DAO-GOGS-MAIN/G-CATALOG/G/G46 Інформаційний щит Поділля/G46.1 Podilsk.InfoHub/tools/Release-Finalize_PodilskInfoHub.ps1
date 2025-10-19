param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Version,
    [string]$OutDir,
    [switch]$NoGitTag,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
function I($m) { Write-Host "[INFO] $m" -ForegroundColor Cyan }
function OK($m) { Write-Host "[ OK ] $m" -ForegroundColor Green }
function WR($m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }
function ER($m) { Write-Host "[ERR ] $m" -ForegroundColor Red }

# Normalize
$Root = (Resolve-Path -LiteralPath $Root).Path
$OutDir = if ($OutDir) { $OutDir } else { Join-Path $Root "Release" }
$stamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")

# Required files/dirs
$mustFiles = @("README.md", "CHANGELOG.md")
$mustDirs = @("media-kit", "content", "contacts", "archive")
foreach ($f in $mustFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $f))) { ER "Missing file: $f"; throw "missing $f" }
}
foreach ($d in $mustDirs) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $d))) { ER "Missing directory: $d"; throw "missing dir $d" }
}

# Minimal media warnings (non-blocking)
$mediaReq = @("logo.svg", "banner-1200x400.png")
foreach ($m in $mediaReq) {
    $p = Join-Path $Root ("media-kit\" + $m)
    if (-not (Test-Path -LiteralPath $p)) { WR "MediaKit missing: $m" }
}

# Content count (block unless -Force)
$contentDir = Join-Path $Root "content"
$contentCount = (Get-ChildItem -LiteralPath $contentDir -Filter *.md -File | Measure-Object).Count
if ($contentCount -lt 5) {
    $msg = "content has $contentCount files (<5)."
    if ($Force) { WR $msg } else { ER $msg; throw "not enough content" }
}

# Prepare stage
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stage = Join-Path $OutDir ("stage_" + $stamp)
New-Item -ItemType Directory -Force -Path $stage | Out-Null

# Copy payload
I "Copying files to stage..."
$include = @("README.md", "CHANGELOG.md", "media-kit", "content", "contacts", "archive")
foreach ($i in $include) {
    $src = Join-Path $Root $i
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination $stage -Recurse -Force
    }
}

# CHECKSUMS.txt (SHA256)
I "Building CHECKSUMS.txt"
$checksums = Join-Path $stage "CHECKSUMS.txt"
if (Test-Path -LiteralPath $checksums) { Remove-Item -LiteralPath $checksums -Force }
Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object {
    $h = Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName
    "{0} *{1}" -f $h.Hash, ($_.FullName.Substring($stage.Length + 1)) | Out-File -FilePath $checksums -Append -Encoding UTF8
}

# ZIP artifact
$zipName = ("G46_Podilsk.InfoHub_{0}_{1}.zip" -f $Version, $stamp)
$zipPath = Join-Path $OutDir $zipName
I "Creating ZIP: $zipPath"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath -Force

# SHA256 file
$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash
$shaPath = "$zipPath.sha256"
$sha | Out-File -LiteralPath $shaPath -Encoding ASCII
OK ("ZIP ready. SHA256={0}" -f $sha)

# CHANGELOG append
$changelog = Join-Path $Root "CHANGELOG.md"
$dateStr = (Get-Date).ToString('yyyy-MM-dd')
("`n{0} — {1} — release package ({2})`n" -f $dateStr, $Version, $zipName) | Add-Content -LiteralPath $changelog -Encoding UTF8
OK "CHANGELOG updated"

# Optional git commit+tag
function IsGitRepo([string]$p) {
    try { Push-Location $p; git rev-parse --is-inside-work-tree *> $null 2>&1; $rc = $LASTEXITCODE; Pop-Location; return ($rc -eq 0) } catch { return $false }
}
if (-not $NoGitTag) {
    if (IsGitRepo $Root) {
        I "Git: commit + tag $Version"
        Push-Location $Root
        git add -A
        git commit -m ("chore(release): {0} (build {1})" -f $Version, $stamp) *> $null 2>&1
        git tag -a $Version -m ("Podilsk.InfoHub {0} ({1})" -f $Version, $dateStr) *> $null 2>&1
        Pop-Location
        OK "Git tag created"
    }
    else {
        WR "Not a git repository; skipping tag"
    }
}

# Cleanup
Remove-Item -LiteralPath $stage -Recurse -Force

OK ("Release completed:
  ZIP:      {0}
  SHA256:   {1}
  CHANGELOG:{2}
" -f $zipPath, $shaPath, $changelog)

