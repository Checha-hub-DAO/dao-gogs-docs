[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$AssetPath,
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(Mandatory)][string]$Title,
    [string]$Owner,
    [string]$RepoName = "checha-core",
    [switch]$Clobber
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $AssetPath)) {
    throw "Not found: $AssetPath"
}
if (-not $Owner) { $Owner = gh api user -q .login }
$repo = "$Owner/$RepoName"

$sha = (Get-FileHash -LiteralPath $AssetPath -Algorithm SHA256).Hash
$shaFile = "$AssetPath.sha256"
$sha | Out-File -Encoding ascii $shaFile

$notes = @"
SHA256: $sha

$(Split-Path -Leaf -Path $AssetPath)
"@

if ($PSCmdlet.ShouldProcess("$repo/$Tag", "Create or update release")) {
    if (-not (gh release view $Tag --repo $repo --json tagName -q .tagName 2>$null)) {
        gh release create $Tag --repo $repo --title $Title --notes $notes
    }
    else {
        gh release edit   $Tag --repo $repo --title $Title --notes $notes
    }
}

if ($PSCmdlet.ShouldProcess("$repo/$Tag", "Upload assets")) {
    $uploadArgs = @('release', 'upload', $Tag, $AssetPath, $shaFile, '--repo', $repo)
    if ($Clobber) { $uploadArgs += '--clobber' }
    gh @uploadArgs
}

Write-Information ("OK: {0} → {1}" -f $Tag, $repo) -InformationAction Continue


