#requires -Version 7.0
<#
.SYNOPSIS
  Публікація щотижневого релізу GitHub з артефактами CHECHA_CORE.

.DESCRIPTION
  - Працює із заздалегідь сформованими файлами у D:\CHECHA_CORE\REPORTS (або вказаній теці).
  - Шукає артефакти за діапазоном дат у назві (формат WeeklyChecklist_YYYY-MM-DD_to_YYYY-MM-DD.*).
  - Якщо тег не заданий, бере останній найсвіжіший комплект.
  - Створює реліз із цим тегом (якщо відсутній) та завантажує активи.

.PARAMETER RepoRoot
  Корінь репо (де є .git). Викорується, щоб визначити owner/name з origin.

.PARAMETER ReportsRoot
  Тека з артефактами звітів.

.PARAMETER Repo
  Явне owner/name на GitHub (наприклад, Checha-hub-DAO/dao-gogs-docs). Якщо не задано — витягнеться з git origin.

.PARAMETER Tag
  Явний тег релізу (наприклад, weekly-2025-10-01_to_2025-10-07).
  Якщо не задано — буде взято з найсвіжішого WeeklyChecklist_* у ReportsRoot.

.PARAMETER DryRun
  Лише показує, що було б зроблено, без реальних змін.

.EXAMPLE
  pwsh -File D:\CHECHA_CORE\TOOLS\CHECHA_Weekly_Publish.ps1

.EXAMPLE
  pwsh -File D:\CHECHA_CORE\TOOLS\CHECHA_Weekly_Publish.ps1 -Repo "Checha-hub-DAO/dao-gogs-docs" -Tag "weekly-2025-10-01_to_2025-10-07"
#>

[CmdletBinding()]
param(
    [string]$RepoRoot = 'D:\CHECHA_CORE',
    [string]$ReportsRoot = 'D:\CHECHA_CORE\REPORTS',
    [string]$Repo,
    [string]$Tag,
    [switch]$DryRun
)

# ─────────────────────────────────────────────────────────────────────────────
# Глобальні налаштування і логи
# ─────────────────────────────────────────────────────────────────────────────
$ErrorActionPreference = 'Stop'
$PSStyle.OutputRendering = 'PlainText'

$LogDir = 'D:\CHECHA_CORE\C03_LOG\SCHED'
$StdLog = Join-Path $LogDir 'weekly_stdout.log'
$ErrLog = Join-Path $LogDir 'weekly_stderr.log'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Log([string]$msg) {
    ("[{0}] {1}" -f (Get-Date -Format u), $msg) | Add-Content $StdLog
}
function LogErr([string]$msg) {
    ("[{0}] {1}" -f (Get-Date -Format u), $msg) | Add-Content $ErrLog
}

Log "START pid=$PID user=$env:USERNAME pwsh=$($PSVersionTable.PSVersion)"
Log "RepoRoot=$RepoRoot; ReportsRoot=$ReportsRoot; Repo=$Repo; Tag=$Tag; DryRun=$($DryRun.IsPresent)"

# ─────────────────────────────────────────────────────────────────────────────
# Перевірки середовища
# ─────────────────────────────────────────────────────────────────────────────
if (-not (Test-Path -LiteralPath $RepoRoot)) { LogErr "RepoRoot не знайдено: $RepoRoot"; exit 2 }
if (-not (Test-Path -LiteralPath $ReportsRoot)) { LogErr "ReportsRoot не знайдено: $ReportsRoot"; exit 2 }

# gh на шляху?
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    LogErr "gh CLI не знайдено у PATH"
    exit 3
}

# Авторизація gh
try {
    $auth = gh auth status 2>&1 | Out-String
    Log "gh auth status:`n$auth"
}
catch {
    LogErr "gh auth status помилка: $($_.Exception.Message)"
    exit 3
}

if ($auth -match 'Failed to log in' -or $auth -match 'token is invalid') {
    LogErr "gh не авторизовано або токен невалідний"
    exit 3
}

# ─────────────────────────────────────────────────────────────────────────────
# Визначення репозиторію (owner/name)
# ─────────────────────────────────────────────────────────────────────────────
Set-Location $RepoRoot
if (-not $Repo) {
    $origin = (& git config --get remote.origin.url)
    if (-not $origin) { LogErr "Remote 'origin' не налаштовано у $RepoRoot"; exit 4 }
    try {
        $Repo = gh repo view $origin --json nameWithOwner --jq .nameWithOwner
    }
    catch {
        LogErr "Не вдалось визначити owner/name з origin=$origin : $($_.Exception.Message)"
        exit 4
    }
    if (-not $Repo) { LogErr "Порожній nameWithOwner після gh repo view"; exit 4 }
}
Log "Target Repo = $Repo"

# ─────────────────────────────────────────────────────────────────────────────
# Визначення тега і набору файлів
# ─────────────────────────────────────────────────────────────────────────────
function Parse-RangeFromFilename([string]$name) {
    # Очікуємо вигляд: WeeklyChecklist_YYYY-MM-DD_to_YYYY-MM-DD.ext
    if ($name -match 'WeeklyChecklist_(\d{4}-\d{2}-\d{2})_to_(\d{4}-\d{2}-\d{2})') {
        return @{ Start = $Matches[1]; End = $Matches[2] }
    }
    return $null
}

if (-not $Tag) {
    $latest = Get-ChildItem -LiteralPath $ReportsRoot -Filter 'WeeklyChecklist_*.md' |
        Sort-Object LastWriteTime -Desc | Select-Object -First 1
    if (-not $latest) {
        LogErr "Не знайдено WeeklyChecklist_*.md у $ReportsRoot — не можу вивести діапазон дат."
        exit 5
    }

    $rng = Parse-RangeFromFilename $latest.Name
    if (-not $rng) { LogErr "Не вдалось розпарсити діапазон з імені: $($latest.Name)"; exit 5 }

    $Tag = "weekly-{0}_to_{1}" -f $rng.Start, $rng.End
    Log "Авто-визначено Tag = $Tag (з $($latest.Name))"
}
else {
    Log "Використовую наданий Tag = $Tag"
}

# Підбір активів з ReportsRoot за діапазоном
$start, $end = $null, $null
if ($Tag -match 'weekly-(\d{4}-\d{2}-\d{2})_to_(\d{4}-\d{2}-\d{2})') {
    $start = $Matches[1]; $end = $Matches[2]
}
else {
    LogErr "Тег не відповідає шаблону weekly-YYYY-MM-DD_to_YYYY-MM-DD: $Tag"
    exit 5
}

# Маски для добору файлів, що містять той самий діапазон дат
$masks = @(
    "*$start*_to_$end*",
    "*$start*to*$end*",
    "*$start*",
    "*$end*"
)

$assets = New-Object System.Collections.Generic.List[string]
foreach ($mask in $masks) {
    Get-ChildItem -LiteralPath $ReportsRoot -File -Filter $mask -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.md', '.zip', '.csv', '.xlsx', '.html', '.json', '.txt' } |
        ForEach-Object { if (-not $assets.Contains($_.FullName)) { $assets.Add($_.FullName) } }
}

if ($assets.Count -eq 0) {
    LogErr "Не знайдено активів у $ReportsRoot для інтервалу $start → $end"
    exit 6
}
Log ("Знайдено активів: {0}`n{1}" -f $assets.Count, ($assets -join "`n"))

# ─────────────────────────────────────────────────────────────────────────────
# Перевірка/створення релізу
# ─────────────────────────────────────────────────────────────────────────────
$releaseExists = $false
try {
    $relJson = gh release view $Tag --repo $Repo --json tagName, name 2>$null
    if ($LASTEXITCODE -eq 0 -and $relJson) { $releaseExists = $true }
}
catch { }

if (-not $releaseExists) {
    $title = "Weekly report $start → $end"
    $createCmd = @('release', 'create', $Tag, '--repo', $Repo, '--title', $title, '--notes', "Automated weekly publish for $start → $end")
    if ($DryRun) {
        Log "[DryRun] gh $($createCmd -join ' ')"
    }
    else {
        try {
            Log "Створюю реліз $Tag ($title)…"
            gh @createCmd | Out-Null
        }
        catch {
            LogErr ("Помилка створення релізу {0}: {1}" -f $Tag, $_.Exception.Message)
            exit 7
        }
    }
}
else {
    Log "Реліз $Tag уже існує."
}

# ─────────────────────────────────────────────────────────────────────────────
# Завантаження активів
# ─────────────────────────────────────────────────────────────────────────────
# gh release upload <tag> <files...> --clobber --repo <repo>
try {
    if ($DryRun) {
        Log "[DryRun] gh release upload $Tag (файлів: $($assets.Count)) --clobber --repo $Repo"
    }
    else {
        # Пакетно вантажимо (gh приймає список файлів)
        Log "Виконую upload активів…"
        gh release upload $Tag --repo $Repo --clobber -- $assets | Out-Null
        Log "Upload завершився"
    }
}
catch {
    LogErr "Помилка upload активів: $($_.Exception.Message)"
    exit 8
}

Log "OK"
exit 0

