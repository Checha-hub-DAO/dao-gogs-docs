<# 
.SYNOPSIS
  Додає/оновлює колонку Type у MAT_BALANCE.csv на основі колонки з напрямом (наприклад, "Напрям", "Category", "Тип" тощо).

.DESCRIPTION
  - Автоматично знаходить колонку-джерело (можна вказати через -SourceColumn).
  - Мапить значення на Strategic / Technical / Other.
  - Створює резервну копію в *.bak.csv (якщо не вимкнено).
  - Підтримує -DryRun (тільки показати зміни), -ForceOverwrite (перезапис Type).
  - Працює з UTF-8. Виводить зведення.

.PARAMETER InputPath
  Шлях до вхідного CSV.

.PARAMETER OutputPath
  Шлях до вихідного CSV (за замовчуванням — переписує InputPath).

.PARAMETER SourceColumn
  Назва колонки з напрямом (якщо не задано — авто-пошук).

.PARAMETER ForceOverwrite
  Якщо встановлено — перезаписує існуючу колонку Type.

.PARAMETER Backup
  Якщо встановлено (за замовчуванням) — робить .bak.csv біля вихідного файлу.

.PARAMETER DryRun
  Показує, що буде змінено, але не записує файл.

.PARAMETER CustomMap
  Додатковий мапінг: Hashtable, де ключ — Regex, значення — 'Strategic'/'Technical'/'Other'.

.EXAMPLE
  pwsh -File .\Add-TypeColumn.ps1 -InputPath D:\CHECHA_CORE\C07_ANALYTICS\MAT_BALANCE.csv

.EXAMPLE
  pwsh -File .\Add-TypeColumn.ps1 -InputPath D:\...\MAT_BALANCE.csv -SourceColumn "Напрям" -ForceOverwrite

.EXAMPLE
  pwsh -File .\Add-TypeColumn.ps1 -InputPath .\mat.csv -DryRun -CustomMap @{ '^\s*S\b'='Strategic'; '^\s*T\b'='Technical' }
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [string]$OutputPath,

    [string]$SourceColumn,

    [switch]$ForceOverwrite,

    [switch]$Backup = $true,

    [switch]$DryRun,

    [hashtable]$CustomMap
)

function Die($msg) { Write-Host "[ERR] $msg" -ForegroundColor Red; exit 2 }
function Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor DarkCyan }
function Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }

# Базова нормалізація -> Strategic/Technical/Other
function Map-Type([string]$raw, [hashtable]$custom) {
    if ($custom) {
        foreach ($k in $custom.Keys) {
            if ($raw -match $k) { return $custom[$k] }
        }
    }
    if (-not $raw) { return 'Other' }
    $t = $raw.Trim().ToLowerInvariant()

    # короткі шорткоди
    if ($t -match '^(s|str|strategy|strategic|стратег|стратегія|стр)$') { return 'Strategic' }
    if ($t -match '^(t|tech|technical|техн|техніка)$') { return 'Technical' }

    # підрядки
    if ($t -match 'strateg') { return 'Strategic' }
    if ($t -match 'тратег|тратегіч') { return 'Strategic' }
    if ($t -match 'tech') { return 'Technical' }
    if ($t -match 'техн') { return 'Technical' }

    return 'Other'
}

# --- 1) Перевірки та читання
if (!(Test-Path -LiteralPath $InputPath)) { Die "Не знайдено файл: $InputPath" }
if (-not $OutputPath) { $OutputPath = $InputPath }

$rows = Import-Csv -LiteralPath $InputPath
if (-not $rows -or $rows.Count -eq 0) { Die "CSV порожній або не містить рядків." }

$headers = $rows[0].PSObject.Properties.Name
Info ("Знайдені колонки: {0}" -f ($headers -join ', '))

# --- 2) Визначаємо колонку-джерело
$src = $SourceColumn
if (-not $src) {
    # Популярні кандидати
    $candidates = @(
        'Напрям', 'Тип', 'Type', 'Category', 'Категорія', 'Катег', 'Class', 'Клас', 'Group', 'Група',
        'Mode', 'Режим', 'Channel', 'Канал', 'Kind', 'Вид', 'Track', 'Трек', 'Area', 'Сфера', 'Domain', 'Домен'
    )
    $src = ($headers | Where-Object { $candidates -contains $_ } | Select-Object -First 1)

    if (-not $src) {
        # якщо не знайшли по назві — виберемо колонку, де найчастіше розпізнається Strategic/Technical
        $scored = @()
        foreach ($h in $headers) {
            $vals = $rows | Select-Object -ExpandProperty $h -ErrorAction SilentlyContinue | Where-Object { $_ } | Select-Object -First 200
            if (-not $vals) { continue }
            $score = 0
            foreach ($v in $vals) {
                $m = Map-Type ($v -as [string]) $CustomMap
                if ($m -ne 'Other') { $score++ }
            }
            if ($score -gt 0) { $scored += [PSCustomObject]@{ Header = $h; Score = $score } }
        }
        $src = ($scored | Sort-Object Score -Descending | Select-Object -First 1).Header
    }
}

if (-not $src) {
    Warn "Не вдалося авто-визначити колонку-джерело. Приклади значень по колонках:"
    foreach ($h in $headers) {
        $samples = $rows | Select-Object -ExpandProperty $h -ErrorAction SilentlyContinue | Where-Object { $_ } | Select-Object -Unique -First 5
        if ($samples) { Write-Host ("  {0}: {1}" -f $h, ($samples -join ', ')) }
    }
    Die "Вкажи -SourceColumn або перейменуй колонку у щось на кшталт 'Напрям'/'Category'."
}

Info "Колонка-джерело: $src"
$hasType = $headers -contains 'Type'
if ($hasType -and -not $ForceOverwrite) {
    Info "Колонка 'Type' вже існує. Використай -ForceOverwrite, щоб перезаписати."
}

# --- 3) Трансформація
$changed = 0
$newRows = foreach ($r in $rows) {
    $mapped = Map-Type ($r.$src -as [string]) $CustomMap

    # Збираємо новий об'єкт, щоб гарантовано мати 'Type' наприкінці
    $new = [ordered]@{}
    foreach ($h in $headers) { $new[$h] = $r.$h }
    if ($hasType) {
        if ($ForceOverwrite) {
            if ($new['Type'] -ne $mapped) { $changed++ }
            $new['Type'] = $mapped
        }
        else {
            # якщо пусто — доповнимо
            if (-not $new['Type'] -or "$($new['Type'])".Trim() -eq '') {
                $new['Type'] = $mapped
                $changed++
            }
        }
    }
    else {
        $new['Type'] = $mapped
        $changed++
    }
    [PSCustomObject]$new
}

# --- 4) Підсумок
$tot = $newRows.Count
$preview = $newRows | Select-Object -First 6
$dist = $newRows | Group-Object Type | Select-Object Name, Count

Write-Host "------ PREVIEW ------" -ForegroundColor Cyan
$preview | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "------ DISTRIBUTION ------" -ForegroundColor Cyan
$dist | Format-Table -AutoSize | Out-String | Write-Host
Info ("Змінено/додано значень Type: {0} із {1}" -f $changed, $tot)

# --- 5) Запис
if ($DryRun) {
    Warn "DryRun: файл НЕ перезаписано."
    exit 0
}

if ($Backup -and (Test-Path -LiteralPath $OutputPath)) {
    $bak = [IO.Path]::ChangeExtension($OutputPath, ".bak.csv")
    Copy-Item -LiteralPath $OutputPath -Destination $bak -Force
    Info "Зроблено резервну копію: $bak"
}

$newRows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
Info "Готово. Записано: $OutputPath"
exit 0


