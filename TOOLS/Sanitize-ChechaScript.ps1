param(
    [Parameter(Mandatory)]
    [string]$Path,

    [switch]$NoBackup,
    [switch]$DryRun,
    [switch]$ShowVerbose
)

function _Info([string]$m) { if ($ShowVerbose) { Write-Host "[SANITIZE] $m" } }

if (-not (Test-Path -LiteralPath $Path)) {
    throw "Файл не знайдено: $Path"
}

$raw = Get-Content -LiteralPath $Path -Raw

# 0) Бекап
if (-not $NoBackup) {
    Copy-Item -LiteralPath $Path -Destination ($Path + ".sanitize.bak") -Force
    _Info "Зроблено бекап: $Path.sanitize.bak"
}

# 1) Нормалізація перенесень рядків
$raw = $raw -replace "`r?`n", "`r`n"

# 2) Прибрати артефакти-коментарі без '#'
#   напр. "} тут: GroupInfo(Name=Date, Count=<int>)"
$raw = [regex]::Replace($raw, '^\s*.*тут:\s*GroupInfo\(.*$', '', 'Multiline')
$raw = [regex]::Replace($raw, '^\s*.*here:\s*GroupInfo\(.*$', '', 'Multiline')

# 3) Прибрати верхньорівневі begin/process/end-блоки (лише якщо вони окремими блоками)
$raw = [regex]::Replace($raw, '^\s*(begin|process|end)\s*\{.*?\}\s*$', '', 'Singleline, Multiline')

# 4) Прибрати дублікати [CmdletBinding()] (залишити лише найперший, якщо він є)
$matches = [regex]::Matches($raw, '^\s*\[CmdletBinding\(\)\]\s*$', 'Multiline')
if ($matches.Count -gt 1) {
    for ($i = 1; $i -lt $matches.Count; $i++) {
        $raw = $raw.Remove($matches[$i].Index, $matches[$i].Length)
    }
}

# 5) Залишити лише ПЕРШИЙ блок param(...) (решту видалити)
$paramRegex = [regex]::new('(?ms)^\s*param\s*\(.*?\r?\n\s*\)\s*')
$allParams = $paramRegex.Matches($raw)
if ($allParams.Count -gt 1) {
    for ($i = $allParams.Count - 1; $i -ge 1; $i--) {
        $m = $allParams[$i]
        $raw = $raw.Remove($m.Index, $m.Length)
    }
}

# 6) Прибрати осиротілі закриваючі дужки ')' на окремому рядку, якщо їх кілька поспіль (залишити не більше однієї)
$raw = [regex]::Replace($raw, '(?m)^(?:\s*\)\s*\r?\n){2,}', "`r`n")

# 7) Дрібне підчищення: зайві порожні рядки (>2 поспіль → 2)
$raw = [regex]::Replace($raw, '(\r?\n){3,}', "`r`n`r`n")

if ($DryRun) {
    _Info "DryRun: зміни НЕ записано."
    $raw
    exit 0
}

# 8) Запис назад (UTF-8 без BOM)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($Path, $raw, $enc)
_Info "Записано очищений файл."

