[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Root,
    [string] $Version = "v1.0",
    [string[]] $ContactsCsv,
    [string[]] $UrlCsv,
    [string] $Branch = "main",
    [string] $Message = "G46.1: update",
    [switch] $SkipScaffold,
    [switch] $SkipContacts,
    [switch] $NoGitTag,
    [switch] $Force
)

$ErrorActionPreference = "Stop"

function TS { (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
function Info($m) { Write-Host "$(TS) | [INFO]  $m" -ForegroundColor Cyan }
function Ok  ($m) { Write-Host "$(TS) | [ OK ]  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "$(TS) | [WARN]  $m" -ForegroundColor Yellow }
function Err ($m) { Write-Host "$(TS) | [ERR ]  $m" -ForegroundColor Red }

# Normalize paths
$Root = (Resolve-Path -LiteralPath $Root).Path
$Tools = Join-Path $Root "tools"

# Required tool scripts
$required = @(
    "New-ContentScaffold.ps1",
    "Validate-G46.ps1",
    "Export-ContactsCsv.ps1",
    "Release-Finalize_PodilskInfoHub.ps1",
    "Sync-GitBook_G46.ps1"
) | ForEach-Object { Join-Path $Tools $_ }

foreach ($f in $required) {
    if (-not (Test-Path -LiteralPath $f)) {
        Err ("Required file not found: {0}" -f $f)
        throw "Missing tool script(s) in: $Tools"
    }
}

# Unblock potential downloaded files
Get-ChildItem -LiteralPath $Tools -Filter *.ps1 | Unblock-File

# 1) Scaffold (optional)
if (-not $SkipScaffold) {
    Info "Step 1: scaffold content (/content)"
    & (Join-Path $Tools "New-ContentScaffold.ps1") -Root $Root
    Ok  "Step 1 done"
}
else {
    Warn "Step 1 skipped (-SkipScaffold)"
}

# 2) Validate
Info "Step 2: validate structure"
& (Join-Path $Tools "Validate-G46.ps1") -Root $Root
Ok  "Step 2 done"

# 3) Contacts merge (optional)
if (-not $SkipContacts -and ($ContactsCsv -or $UrlCsv)) {
    Info "Step 3: merge contacts -> contacts\podillia_contacts.csv"
    $args = @{ Root = $Root }
    if ($ContactsCsv) { $args["InputCsv"] = $ContactsCsv }
    if ($UrlCsv) { $args["UrlCsv"] = $UrlCsv }
    & (Join-Path $Tools "Export-ContactsCsv.ps1") @args
    Ok  "Step 3 done"
}
elseif ($SkipContacts) {
    Warn "Step 3 skipped (-SkipContacts)"
}
else {
    Warn "Step 3 skipped (no -ContactsCsv/-UrlCsv provided)"
}

# 4) Release finalize
Info "Step 4: finalize release ($Version)"
$rel = @{ Root = $Root; Version = $Version }
if ($NoGitTag) { $rel["NoGitTag"] = $true }
if ($Force) { $rel["Force"] = $true }
& (Join-Path $Tools "Release-Finalize_PodilskInfoHub.ps1") @rel
Ok  "Step 4 done"

# 5) Git sync
Info "Step 5: git sync (branch: $Branch)"
& (Join-Path $Tools "Sync-GitBook_G46.ps1") -RepoPath $Root -Message $Message -Branch $Branch
Ok  "Step 5 done"

Ok "PIPELINE COMPLETED SUCCESSFULLY"

