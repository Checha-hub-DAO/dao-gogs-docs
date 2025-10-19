param(
    [Parameter(Mandatory)]
    [string]$Path,
    [switch]$NoBackup
)

if (-not (Test-Path -LiteralPath $Path)) { throw "Файл не знайдено: $Path" }

# Бекап
if (-not $NoBackup) {
    Copy-Item -LiteralPath $Path -Destination ($Path + ".bracesfix.bak") -Force
}

# 1) Зчитуємо файл
$raw = Get-Content -LiteralPath $Path -Raw

# 2) Прибираємо блок-коментарі <# ... #> (акуратно, багаторядково)
$rawNoBlock = [regex]::Replace($raw, '<#.*?#>', '', 'Singleline')

# 3) Розбиваємо на рядки
$lines = $rawNoBlock -split "`r?`n", 0, 'None'

# Хелпер: видалити зміст у лапках (щоб не рахувати дужки всередині рядків/строк)
function Remove-QuotedParts([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return $s }
    # here-strings @'...'@ / @"..."@
    $s = [regex]::Replace($s, "@'(.|\r|\n)*?'@", '', 'Singleline')
    $s = [regex]::Replace($s, '@"(.|\r|\n)*?"@', '', 'Singleline')
    # звичайні рядки '...' і "..."
    $s = [regex]::Replace($s, "('[^']*')", "''")
    $s = [regex]::Replace($s, '("[^"]*")', '""')
    return $s
}

# Хелпер: обрізати коментар з # (лише поза рядками)
function Strip-LineComment([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return $s }
    $tmp = $s
    # замінюємо вміст у лапках на плейсхолдери, щоб # усередині рядків не вважався коментарем
    $mask = Remove-QuotedParts $tmp
    $idx = $mask.IndexOf('#')
    if ($idx -ge 0) { return $s.Substring(0, $idx) }
    return $s
}

# 4) Прохід із підрахунком глибини та видаленням «осиротілих» }
$depth = 0
$kept = New-Object System.Collections.Generic.List[string]

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]

    # Робоча копія без рядків і без однорядкового коментаря
    $work = Strip-LineComment $line
    $work = Remove-QuotedParts $work

    # Рядок — лише закриваюча дужка?
    $onlyClose = $work -match '^\s*\}\s*;$' -or $work -match '^\s*\}\s*$'
    if ($onlyClose -and $depth -le 0) {
        # цю } на верхньому рівні викидаємо
        continue
    }

    # Оновлюємо глибину (рахуємо лише у «робочій» частині)
    $opens = ([regex]::Matches($work, '\{')).Count
    $closes = ([regex]::Matches($work, '\}')).Count
    $depth += ($opens - $closes)
    if ($depth -lt 0) { $depth = 0 } # захист від мінуса

    $kept.Add($line)
}

# 5) Збираємо назад: зберігаємо початкові переноси
$fixed = ($kept -join "`r`n")

# 6) Запис у UTF-8 без BOM
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($Path, $fixed, $enc)

# 7) Діагностика: порахуємо баланс у вже виправленому коді
$diag = Remove-QuotedParts ([regex]::Replace($fixed, '<#.*?#>', '', 'Singleline'))
$opens = ([regex]::Matches($diag, '\{')).Count
$closes = ([regex]::Matches($diag, '\}')).Count
$balance = $opens - $closes

if ($balance -gt 0) {
    Write-Warning "Залишилось $balance незакритих '{'. Додай потрібні '}' наприкінці відповідних блоків."
}
elseif ($balance -lt 0) {
    Write-Warning "Зайвих '}' після чистки: $(-$balance). Перевір оточення рядків біля останніх функцій."
}
else {
    Write-Host "✅ Дужки збалансовано."
}

