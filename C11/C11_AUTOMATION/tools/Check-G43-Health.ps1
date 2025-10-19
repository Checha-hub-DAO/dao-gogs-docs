param(
    [string]$Root = "D:\CHECHA_CORE",
    [switch]$WriteChecksums
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$errors = @()

# 1) G43 структура
$g43 = Join-Path $Root 'C12\Vault\DAO\G43'
if (!(Test-Path $g43)) { $errors += "Missing: $g43" }
else {
    $files = (Get-ChildItem $g43 -Recurse -File -ea SilentlyContinue).Count
    if ($files -lt 3) { $errors += "Too few files in G43: $files" }
}

# 2) Індекс
$index = Join-Path $Root 'C12\INDEX.md'
$hasRef = (Test-Path $index) -and (Select-String -Path $index -SimpleMatch -Pattern 'G43' -Quiet -ea SilentlyContinue)
if (-not $hasRef) { $errors += "INDEX.md has no 'G43' entry" }

# 3) Останній G43*.zip у Vault
$vault = Join-Path $Root 'C12\Vault\DAO'
$zip = Get-ChildItem $vault -Filter 'G43*.zip' -File -ea SilentlyContinue |
    Sort-Object LastWriteTime -Desc | Select-Object -First 1
if ($zip) {
    $sha = (Get-FileHash -LiteralPath $zip.FullName -Algorithm SHA256).Hash
    Write-Host ("ZIP: {0} | SHA256: {1}" -f $zip.Name, $sha)
    if ($WriteChecksums) {
        $chk = Join-Path $vault 'CHECKSUMS.txt'
        Add-Content -LiteralPath $chk -Value ("{0}  {1}" -f $sha, $zip.Name)
        Write-Host "Checksums appended → $chk"
    }
}
else { $errors += "No G43*.zip found in $vault" }

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}
else {
    Write-Host "G43 health: OK"
    exit 0
}


