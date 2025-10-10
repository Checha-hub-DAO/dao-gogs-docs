# Verify-ArmyHub-Package.ps1
# Скрипт перевірки відповідності файлів у Officer Package до MANIFEST.md

param(
  [string]$RootDir = "."
)

$manifestPath = Join-Path $RootDir "MANIFEST.md"
if (-not (Test-Path $manifestPath)) {
    Write-Host "[ERR] MANIFEST.md не знайдено" -ForegroundColor Red
    exit 1
}

$lines = Get-Content $manifestPath | Where-Object {$_ -match "^\|"}
$errors = 0

foreach ($line in $lines) {
    if ($line -match "^\| (?<file>.+?) \| (?<size>\d+) \| (?<hash>[a-f0-9]{64}) \|$") {
        $file = $matches.file.Trim()
        $size = [int64]$matches.size
        $hash = $matches.hash.Trim()

        $path = Join-Path $RootDir $file
        if (-not (Test-Path $path)) {
            Write-Host "[MISS] $file відсутній" -ForegroundColor Yellow
            $errors++
            continue
        }

        $actHash = (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLower()
        $actSize = (Get-Item $path).Length

        if ($actHash -ne $hash -or $actSize -ne $size) {
            Write-Host "[FAIL] $file невідповідність (очікувалось {size=$size;hash=$hash})" -ForegroundColor Red
            $errors++
        } else {
            Write-Host "[OK]   $file" -ForegroundColor Green
        }
    }
}

if ($errors -eq 0) {
    Write-Host "`nПеревірка пройдена успішно ✅" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nВиявлено помилки: $errors ⚠️" -ForegroundColor Red
    exit 2
}
