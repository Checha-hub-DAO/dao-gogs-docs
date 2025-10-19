param(
    [Parameter(Mandatory)][string]$Path
)

Write-Host "[PATCH] Processing $Path"

# Зчитуємо всі рядки
$lines = Get-Content -LiteralPath $Path

# Патчимо рядки з "тут:"
$patched = for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line -match '\bтут:') {
        "# PATCHED: $line"
    }
    else {
        $line
    }
}

# Резервна копія
$backup = "$Path.bak"
Copy-Item -LiteralPath $Path -Destination $backup -Force
Write-Host "[PATCH] Backup saved -> $backup"

# Записуємо нову версію
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($Path, $patched, $utf8)
Write-Host "[PATCH] Finished. All 'тут:' рядки закоментовані."

