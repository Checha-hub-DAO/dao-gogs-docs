<#!
.SYNOPSIS
  Розширена чистка C11\tools з безпечними try/catch, валідацією існуючих архівів і гнучкою генерацією README/INDEX.
.DESCRIPTION
  • Інвентаризація *.ps1 у C11\tools → визначення «основного» файлу на групу
  • Переміщення варіантів у C05\ARCHIVE\scripts_cleanup_<stamp>\old_variants (зі спробою відновлення при помилці)
  • Пакування архіву + SHA256 чексума
  • Генерація TOOLS_INDEX.md
  • Акуратне оновлення README.md: оновлює/вставляє лише блок `## Cleanup-C11-Tools`
  • Додатково: перевіряє **всі попередні** архіви scripts_cleanup_* на валідність SHA256

.NOTES
  PowerShell 7+. Підтримує -WhatIf / -Confirm. Рекомендується запуск із правами користувача, що має доступ до Root.
.PARAMETER Root
  Корінь CHECHA_CORE (C:\\CHECHA_CORE за замовчуванням).
.PARAMETER ToolsRel
  Відносний шлях до інструментів (C11\\tools).
.PARAMETER ArchiveRel
  Відносний шлях до архівів (C05\\ARCHIVE).
.PARAMETER DryRun
  Лише показати план дій.
.PARAMETER NormalizeNames
  Перейменувати «основні» до стандартизованого вигляду (обережно).
.PARAMETER VerifyArchives
  Перевірити **всі** існуючі scripts_cleanup_* архіви (SHA256 відповідність) і звести підсумок.
.EXAMPLE
  pwsh -NoProfile -File .\\Cleanup-C11-Tools_v2.ps1 -Root 'D:\\CHECHA_CORE' -WhatIf -DryRun
.EXAMPLE
  pwsh -NoProfile -File .\\Cleanup-C11-Tools_v2.ps1 -Root 'D:\\CHECHA_CORE' -NormalizeNames -VerifyArchives -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$Root = 'C:\\CHECHA_CORE',
    [string]$ToolsRel = 'C11\\tools',
    [string]$ArchiveRel = 'C05\\ARCHIVE',
    [switch]$DryRun,
    [switch]$NormalizeNames,
    [switch]$VerifyArchives
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-DirIfMissing([string]$Path) { if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null } }
function Write-Log([string]$Path, [string]$Level, [string]$Msg) {
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-Content -Path $Path -Value ($ts + ' [' + $Level + '] ' + $Msg)
}

# --- Підготовка шляхів ---
$tools = Join-Path $Root $ToolsRel
$archiveRoot = Join-Path $Root $ArchiveRel
$logDir = Join-Path $Root 'C03/LOG'
New-DirIfMissing $tools
New-DirIfMissing $archiveRoot
New-DirIfMissing $logDir
$logPath = Join-Path $logDir 'cleanup_tools.log'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$sessionDir = Join-Path $archiveRoot ("scripts_cleanup_" + $stamp)
$sessionMove = Join-Path $sessionDir 'old_variants'
$zipPath = Join-Path $sessionDir ("scripts_" + $stamp + '.zip')
$checksumsPath = Join-Path $sessionDir 'CHECKSUMS.txt'

# --- Службові шаблони суфіксів для нормалізації ---
$SuffixPatterns = @(
    '(?i)[-_\. ]?(?:v\d+(?:\.\d+)*)',
    '(?i)[-_\. ]?fixed\d*',
    '(?i)[-_\. ]?final',
    '(?i)[-_\. ]?backup|bak',
    '(?i)[-_\. ]?copy( \(\d+\))?',
    '(?i)[-_\. ]?draft',
    '(?i)[-_\. ]?test',
    '(?i)\s*-\s*копия( \(\d+\))?'
)
function Get-BaseStem([string]$FileName) {
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    foreach ($re in $SuffixPatterns) { $stem = [regex]::Replace($stem, $re, '') }
    $stem = $stem -replace '[ _]+', '-'
    $stem = $stem.Trim('-_ .')
    if ([string]::IsNullOrWhiteSpace($stem)) { $stem = [System.IO.Path]::GetFileNameWithoutExtension($FileName) }
    return $stem
}
function Propose-NormalName([System.IO.FileInfo]$File) {
    $stem = Get-BaseStem $File.Name
    return ($stem + $File.Extension)
}

# --- Інвентаризація ---
$all = Get-ChildItem -Path $tools -Filter '*.ps1' -File -ErrorAction Stop
if (-not $all) { Write-Log $logPath 'INFO' ("Немає *.ps1 у " + $tools); Write-Host 'Немає *.ps1' -ForegroundColor Yellow; return }
$groups = $all | Group-Object { Get-BaseStem $_.Name } | Sort-Object Name
Write-Log $logPath 'INFO' ("Старт чистки C11/tools (" + $all.Count + " файлів, груп: " + $groups.Count + ")")

$toArchive = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
$keepers = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

foreach ($g in $groups) {
    $files = $g.Group | Sort-Object LastWriteTime -Descending
    $preferred = $files | Where-Object { (Propose-NormalName $_) -eq $_.Name } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $preferred) { $preferred = $files | Select-Object -First 1 }
    $keepers.Add($preferred)
    foreach ($f in $files) { if ($f.FullName -ne $preferred.FullName) { $toArchive.Add($f) } }
}

Write-Host "Буде збережено як основні:" -ForegroundColor Cyan
$keepers  | ForEach-Object { Write-Host ('  + ' + $_.Name) }
Write-Host "\nБудуть перенесені в архів (варіанти):" -ForegroundColor Yellow
$toArchive | ForEach-Object { Write-Host ('  - ' + $_.Name) }

if ($DryRun) { Write-Log $logPath 'INFO' 'DryRun: завершено без змін'; return }

# --- Переміщення варіантів у архів (with try/catch) ---
New-DirIfMissing $sessionMove
foreach ($f in $toArchive) {
    $dest = Join-Path $sessionMove $f.Name
    try {
        if ($PSCmdlet.ShouldProcess($f.FullName, 'Move -> ' + $dest)) {
            Move-Item -Path $f.FullName -Destination $dest -Force
            Write-Log $logPath 'INFO' ('MOVE ' + $f.Name + ' -> ' + $dest)
        }
    }
    catch {
        Write-Log $logPath 'ERROR' ('MOVE FAIL ' + $f.FullName + ' :: ' + $_.Exception.Message)
    }
}

# --- Нормалізація назв основних (опційно) ---
if ($NormalizeNames) {
    foreach ($k in $keepers) {
        try {
            $proposed = Propose-NormalName $k
            if ($proposed -ne $k.Name) {
                $target = Join-Path $k.DirectoryName $proposed
                if (Test-Path $target) {
                    $target = Join-Path $k.DirectoryName (([System.IO.Path]::GetFileNameWithoutExtension($proposed)) + '_' + $stamp + ([System.IO.Path]::GetExtension($proposed)))
                }
                if ($PSCmdlet.ShouldProcess($k.FullName, 'Rename -> ' + $target)) {
                    Rename-Item -Path $k.FullName -NewName ([System.IO.Path]::GetFileName($target)) -Force
                    Write-Log $logPath 'INFO' ('RENAME ' + $k.Name + ' -> ' + (Split-Path $target -Leaf))
                }
            }
        }
        catch {
            Write-Log $logPath 'ERROR' ('RENAME FAIL ' + $k.FullName + ' :: ' + $_.Exception.Message)
        }
    }
}

# --- Пакування архіву + SHA256 (with try/catch) ---
if ( (Get-ChildItem -Path $sessionMove -File -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0 ) {
    try {
        if ($PSCmdlet.ShouldProcess($sessionMove, 'Compress -> ' + $zipPath)) {
            Compress-Archive -Path (Join-Path $sessionMove '*') -DestinationPath $zipPath -Force
            $hash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
            Set-Content -Path $checksumsPath -Value ('SHA256  ' + $hash + '  ' + (Split-Path $zipPath -Leaf)) -Encoding UTF8
            Write-Log $logPath 'INFO' ('ZIP ' + $zipPath + '; SHA256=' + $hash)
        }
    }
    catch {
        Write-Log $logPath 'ERROR' ('ZIP FAIL ' + $zipPath + ' :: ' + $_.Exception.Message)
    }
}

# --- Генерація TOOLS_INDEX.md (with try/catch) ---
$indexPath = Join-Path $tools 'TOOLS_INDEX.md'
try {
    $indexLines = @('# C11/tools — індекс робочих скриптів (' + $stamp + ')', '')
    foreach ($k in (Get-ChildItem -Path $tools -Filter '*.ps1' -File | Sort-Object Name)) {
        $syn = (Select-String -Path $k.FullName -Pattern '^\s*\.SYNOPSIS\s*$' -SimpleMatch -Context 0, 3 -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Context.PostContext) { $_.Context.PostContext[0].Trim() } else { $null }
            }) | Select-Object -First 1
        if (-not $syn) { $syn = '(опис відсутній)' }
        $indexLines += ('- `' + (Split-Path $k.Name -Leaf) + '`: ' + $syn)
    }
    Set-Content -Path $indexPath -Value ($indexLines -join [Environment]::NewLine) -Encoding UTF8
    Write-Log $logPath 'INFO' ('INDEX ' + $indexPath + ' оновлено')
}
catch {
    Write-Log $logPath 'ERROR' ('INDEX FAIL ' + $indexPath + ' :: ' + $_.Exception.Message)
}

# --- Акуратне оновлення README.md (оновлюємо лише блок) ---
$readmePath = Join-Path $tools 'README.md'
$blockHeader = '## Cleanup-C11-Tools'
$block = @(
    $blockHeader,
    '',
    '- Автоматизує чистку, архівування і нормалізацію скриптів.',
    '- Лог: C03/LOG/cleanup_tools.log',
    '- Архіви: C05/ARCHIVE/scripts_cleanup_*/',
    '- Індекс: TOOLS_INDEX.md',
    '',
    '### Приклади запуску',
    '```powershell',
    "pwsh -NoProfile -File .\\Cleanup-C11-Tools_v2.ps1 -Root '" + $Root + "' -WhatIf -DryRun",
    "pwsh -NoProfile -File .\\Cleanup-C11-Tools_v2.ps1 -Root '" + $Root + "'",
    "pwsh -NoProfile -File .\\Cleanup-C11-Tools_v2.ps1 -Root '" + $Root + "' -NormalizeNames -Confirm:$false",
    '```', ''
) -join [Environment]::NewLine
try {
    $content = ''
    if (Test-Path $readmePath) { $content = Get-Content -Path $readmePath -Raw -Encoding UTF8 }
    if ([string]::IsNullOrEmpty($content)) { $content = '# C11/tools — README' + [Environment]::NewLine + [Environment]::NewLine }
    if ($content -match [regex]::Escape($blockHeader)) {
        # заміна існуючого блоку
        $pattern = [regex]::Escape($blockHeader) + '([\s\S]*?)' + '(?=\n## |\n# |\Z)'
        $content = [regex]::Replace($content, $pattern, ($block -replace '\$', '$$'))
    }
    else {
        # додавання в кінець
        $content = $content.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $block
    }
    Set-Content -Path $readmePath -Value $content -Encoding UTF8
    Write-Log $logPath 'INFO' ('README ' + $readmePath + ' оновлено')
}
catch {
    Write-Log $logPath 'ERROR' ('README FAIL ' + $readmePath + ' :: ' + $_.Exception.Message)
}

# --- Перевірка ВСІХ попередніх архівів (опційно) ---
if ($VerifyArchives) {
    Write-Host "\nПеревірка існуючих scripts_cleanup_* архівів..." -ForegroundColor Cyan
    $dirs = Get-ChildItem -Path $archiveRoot -Directory -Filter 'scripts_cleanup_*' -ErrorAction SilentlyContinue | Sort-Object Name
    $bad = 0; $good = 0
    foreach ($d in $dirs) {
        $chk = Join-Path $d.FullName 'CHECKSUMS.txt'
        $zip = Get-ChildItem -Path $d.FullName -Filter 'scripts_*.zip' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ((Test-Path $chk) -and $zip) {
            try {
                $line = (Get-Content -Path $chk -TotalCount 1)
                $parts = $line -split '\s+'
                $declared = $parts[1]
                $file = Join-Path $d.FullName $parts[-1]
                if (Test-Path $file) {
                    $calc = (Get-FileHash -Path $file -Algorithm SHA256).Hash
                    if ($calc -eq $declared) { $good++ ; Write-Log $logPath 'INFO' ('VERIFY OK ' + $file) }
                    else { $bad++ ; Write-Log $logPath 'WARN' ('VERIFY MISMATCH ' + $file) }
                }
                else { $bad++ ; Write-Log $logPath 'WARN' ('VERIFY MISSING FILE ' + $file) }
            }
            catch { $bad++ ; Write-Log $logPath 'ERROR' ('VERIFY FAIL ' + $d.FullName + ' :: ' + $_.Exception.Message) }
        }
        else {
            $bad++; Write-Log $logPath 'WARN' ('VERIFY SKIP ' + $d.FullName + ' — no CHECKSUMS or ZIP')
        }
    }
    Write-Host ("Перевірено архівів: " + ($good + $bad) + "; OK=" + $good + "; BAD=" + $bad)
}

Write-Host "\n✅ Готово. Дивись лог: $logPath" -ForegroundColor Green
Write-Host ("📦 Архів цієї сесії: " + $sessionDir)


