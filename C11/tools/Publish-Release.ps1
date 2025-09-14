param(
  [Parameter(Mandatory)][string]$AssetPath,   # шлях до ZIP
  [Parameter(Mandatory)][string]$Tag,         # напр. g43-iteta-v1.0
  [Parameter(Mandatory)][string]$Title,       # заголовок релізу
  [string]$Owner,                              # якщо порожньо — візьме з gh
  [string]$RepoName = 'checha-core',
  [switch]$Clobber                             # перезапис ассетів
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path $AssetPath)) { throw "Not found: $AssetPath" }

if (-not $Owner) { $Owner = gh api user -q .login }
$repo = "$Owner/$RepoName"

# Порахуємо SHA та файл .sha256
$sha = (Get-FileHash $AssetPath -Algorithm SHA256).Hash
$shaFile = "$AssetPath.sha256"
$sha | Out-File -Encoding ascii $shaFile

$notes = @"
SHA256: $sha

$(Split-Path $AssetPath -Leaf)
"@

# Створити реліз, якщо не існує; інакше — оновити
if (-not (gh release view $Tag --repo $repo --json tagName -q .tagName 2>$null)) {
  gh release create $Tag --repo $repo --title $Title --notes $notes
} else {
  gh release edit   $Tag --repo $repo --title $Title --notes $notes
}

# Завантажити ассети (з опц. перезаписом)
$uploadArgs = @('release','upload',$Tag,$AssetPath,$shaFile,'--repo',$repo)
if ($Clobber) { $uploadArgs += '--clobber' }
gh @uploadArgs

Write-Host ("OK: {0} → {1}" -f $Tag,$repo)
