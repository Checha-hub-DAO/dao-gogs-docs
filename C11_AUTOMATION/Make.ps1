<#
.SYNOPSIS
  CheCha Make.ps1 — простий таск-раннер для CHECHA_CORE

.DESCRIPTION
  Команди:
    - lint           : PSScriptAnalyzer по репозиторію або шляху
    - fmt            : Форматування файлу (Invoke-Formatter)
    - fix            : Масове автоформатування *.ps1|*.psm1|*.psd1 (+ опція -SeedEmpty)
    - lint-report    : Звіт PSScriptAnalyzer у CSV/JSON
    - test           : Тести (Pester), якщо є папка .\Tests
    - manifest       : MANIFEST.md з SHA256 і розмірами
    - release-notes  : RELEASE_NOTES.md з git log
    - help           : Довідка

.ПРИКЛАДИ
  pwsh -NoProfile -File .\Make.ps1 lint -Path .
  pwsh -NoProfile -File .\Make.ps1 fmt -File .\TOOLS\Build-DriveAuditReport.ps1
  pwsh -NoProfile -File .\Make.ps1 fix -Root D:\CHECHA_CORE -SeedEmpty
  pwsh -NoProfile -File .\Make.ps1 lint-report -Path D:\CHECHA_CORE -OutCsv .\lint.csv -OutJson .\lint.json
  pwsh -NoProfile -File .\Make.ps1 manifest -Root D:\CHECHA_CORE
  pwsh -NoProfile -File .\Make.ps1 release-notes -FromTag v1.0.0 -ToTag v1.1.0
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('lint', 'fmt', 'fix', 'lint-report', 'test', 'manifest', 'release-notes', 'help')]
    [string] $Target,

    # Спільні
    [string] $Path = ".",
    [string] $File,

    # Для fix/manifest
    [string] $Root = ".",

    # Release notes
    [string] $FromTag,
    [string] $ToTag,

    # Lint severity (проброс на Target-Lint / Target-LintReport)
    [ValidateSet('Error', 'Warning', 'Information')]
    [string[]] $Severity = @('Error', 'Warning'),

    # Вихідні файли для lint-report (необов’язкові)
    [string] $OutCsv,
    [string] $OutJson,

    # NEW: прапорець для Target-Fix (автозасів шапки в порожні файли)
    [switch] $SeedEmpty
)

$ErrorActionPreference = 'Stop'

function Ensure-Module {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Write-Information "Installing module: $Name"
        Install-Module $Name -Scope CurrentUser -Force -ErrorAction Stop | Out-Null
    }
}

function Target-Lint {
    [CmdletBinding()]
    param(
        [string] $ScanPath = '.',
        [ValidateSet('Error', 'Warning', 'Information')]
        [string[]] $Severity = @('Error', 'Warning')
    )

    Ensure-Module -Name 'PSScriptAnalyzer'

    # Спроба знайти корінь git-репо
    $repo = try { (git rev-parse --show-toplevel) 2>$null } catch { $null }

    # Вибір PSScriptAnalyzerSettings.psd1, якщо існує
    $settings = $null
    if ($repo) {
        $candidates = @(
            (Join-Path $repo 'config\PSScriptAnalyzerSettings.psd1')
            (Join-Path $repo 'PSScriptAnalyzerSettings.psd1')
        )
        foreach ($p in $candidates) {
            if (Test-Path -LiteralPath $p) { $settings = $p; break }
        }
    }

    $invokeParams = @{
        Path     = $ScanPath
        Recurse  = $true
        Severity = $Severity
    }
    if ($settings) { $invokeParams['Settings'] = $settings }

    $issues = Invoke-ScriptAnalyzer @invokeParams

    if ($issues) {
        $issues | Format-Table -AutoSize RuleName, Severity, ScriptName, Line, Message | Out-String | Write-Host
        throw "PSScriptAnalyzer reported issues."
    }
    else {
        Write-Host "[OK] Lint: no issues" -ForegroundColor Green
    }
}

function Normalize-EOL {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )
    if ($null -eq $Text) { return "" }
    $t = $Text -replace "`r`n", "`n"
    $t = $t -replace "`r", "`n"
    return ($t -replace "`n", "`r`n")
}

function Target-Fmt {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $File)

    $raw = Get-Content -LiteralPath $File -Raw -ErrorAction Stop

    try {
        $formatted = Invoke-Formatter -ScriptDefinition $raw
    }
    catch {
        # fallback: нормалізація EOL і друга спроба
        $norm = Normalize-EOL -Text $raw
        $formatted = Invoke-Formatter -ScriptDefinition $norm
    }

    if ($null -eq $formatted) {
        throw "Invoke-Formatter returned null. Перевір EOL/кодування."
    }

    $formatted | Set-Content -LiteralPath $File -Encoding UTF8
    Write-Host "[OK] Formatted: $File" -ForegroundColor Green
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Target-Manifest {
    [CmdletBinding()]
    param([string] $Root = '.')

    $rootPath = Resolve-Path $Root
    $manifest = Join-Path $rootPath 'MANIFEST.md'

    $items = Get-ChildItem -Path $rootPath -Recurse -File | Sort-Object FullName
    $lines = @('# MANIFEST', '', '| File | Size (bytes) | SHA256 |', '|------|--------------:|--------|')
    foreach ($it in $items) {
        $rel = Resolve-Path $it.FullName -Relative | ForEach-Object { $_ -replace '^\.\.\\', '' }
        $hash = Get-Sha256 -Path $it.FullName
        $lines += "| $rel | $($it.Length) | $hash |"
    }
    $lines | Set-Content -LiteralPath $manifest -Encoding UTF8
    Write-Host "[OK] MANIFEST written: $manifest" -ForegroundColor Green
}

function Target-ReleaseNotes {
    [CmdletBinding()]
    param([string] $FromTag, [string] $ToTag)

    $today = Get-Date -Format yyyy-MM-dd
    $out = Join-Path $PSScriptRoot 'RELEASE_NOTES.md'

    if (-not $FromTag) {
        $FromTag = (git describe --tags --abbrev=0 --always $(git rev-list --tags --max-count=1 2>$null) 2>$null)
    }
    if (-not $ToTag) {
        $ToTag = (git describe --tags --abbrev=0 2>$null)
    }

    if (-not $FromTag) { $range = '' }
    elseif (-not $ToTag) { $range = "$FromTag..HEAD" }
    else { $range = "$FromTag..$ToTag" }

    $log = git log --pretty=format:'* %s (%h)' $range 2>$null
    if (-not $log) { $log = '* No notable changes.' }

    $ver = if ($ToTag) { $ToTag } else { 'Unreleased' }
    $content = @(
        '# Release Notes',
        "## $ver ($today)",
        '',
        $log
    ) -join [Environment]::NewLine

    $content | Set-Content -LiteralPath $out -Encoding UTF8
    Write-Host "[OK] RELEASE_NOTES.md generated: $out" -ForegroundColor Green
}

function New-EmptyScriptHeader {
    param([string]$Name = 'Script', [string]$Synopsis = 'CheCha script')
    @"
[CmdletBinding()]
param()

<# .SYNOPSIS
  $Synopsis
#>

"@
}

function Target-Fix {
    [CmdletBinding()]
    param(
        [string]$Root = '.',
        [switch]$SeedEmpty
    )

    $rootPath = Resolve-Path $Root
    $files = Get-ChildItem -Path $rootPath -Recurse -File -Include *.ps1, *.psm1, *.psd1
    if (-not $files) {
        Write-Host "[SKIP] No PowerShell files found" -ForegroundColor Yellow
        return
    }

    $ok = 0; $changed = 0; $fail = 0
    foreach ($f in $files) {
        try {
            $raw = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop
            if ([string]::IsNullOrEmpty($raw)) {
                if ($SeedEmpty) {
                    New-EmptyScriptHeader -Name $f.BaseName -Synopsis "Placeholder for $($f.Name)" |
                        Set-Content -LiteralPath $f.FullName -Encoding UTF8
                    $changed++
                }
                else {
                    "" | Set-Content -LiteralPath $f.FullName -Encoding UTF8
                    $ok++
                }
                continue
            }

            try {
                $fmt = Invoke-Formatter -ScriptDefinition $raw
            }
            catch {
                $norm = Normalize-EOL -Text $raw
                $fmt = Invoke-Formatter -ScriptDefinition $norm
            }

            if ($fmt -and $fmt -ne $raw) {
                $fmt | Set-Content -LiteralPath $f.FullName -Encoding UTF8
                $changed++
            }
            else {
                $ok++
            }
        }
        catch {
            Write-Warning ("[FAIL] {0}: {1}" -f $f.FullName, $_.Exception.Message)
            $fail++
        }
    }
    Write-Host ("[FIX] ok:{0} changed:{1} fail:{2}" -f $ok, $changed, $fail) -ForegroundColor Cyan
}

function Target-LintReport {
    [CmdletBinding()]
    param(
        [string] $ScanPath = '.',
        [ValidateSet('Error', 'Warning', 'Information')]
        [string[]] $Severity = @('Error', 'Warning'),
        [string] $OutCsv,
        [string] $OutJson
    )

    Ensure-Module -Name 'PSScriptAnalyzer'

    # settings (як у Target-Lint)
    $repo = try { (git rev-parse --show-toplevel) 2>$null } catch { $null }
    $settings = $null
    if ($repo) {
        $candidates = @(
            (Join-Path $repo 'config\PSScriptAnalyzerSettings.psd1')
            (Join-Path $repo 'PSScriptAnalyzerSettings.psd1')
        )
        foreach ($p in $candidates) {
            if (Test-Path -LiteralPath $p) { $settings = $p; break }
        }
    }

    $invokeParams = @{
        Path     = $ScanPath
        Recurse  = $true
        Severity = $Severity
    }
    if ($settings) { $invokeParams['Settings'] = $settings }

    $issues = Invoke-ScriptAnalyzer @invokeParams

    # Вихідні файли за замовчуванням
    $outDir = Join-Path $PSScriptRoot 'lint_reports'
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'

    if (-not $OutCsv) { $OutCsv = Join-Path $outDir ("lint_{0}.csv" -f $stamp) }
    if (-not $OutJson) { $OutJson = Join-Path $outDir ("lint_{0}.json" -f $stamp) }

    if ($issues) {
        $issues | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8
        $issues | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutJson -Encoding UTF8
        Write-Host "[OK] Lint report saved: $OutCsv ; $OutJson" -ForegroundColor Green
    }
    else {
        ''  | Set-Content -LiteralPath $OutCsv  -Encoding UTF8
        '[]' | Set-Content -LiteralPath $OutJson -Encoding UTF8
        Write-Host "[OK] No issues. Empty reports written." -ForegroundColor Green
    }
}

function Show-Help {
    Write-Host "CheCha Make.ps1 targets:" -ForegroundColor Cyan
    Write-Host "  lint             Run PSScriptAnalyzer on repo (or -Path)" -ForegroundColor Yellow
    Write-Host "  fmt              Format a file: -File [path]" -ForegroundColor Yellow
    Write-Host "  fix              Format all *.ps1|*.psm1|*.psd1 under -Root (with EOL fallback, use -SeedEmpty to seed headers)" -ForegroundColor Yellow
    Write-Host "  lint-report      Export analyzer results to CSV/JSON (use -OutCsv/-OutJson)" -ForegroundColor Yellow
    Write-Host "  test             Run Pester tests if .\Tests exists" -ForegroundColor Yellow
    Write-Host "  manifest         Generate MANIFEST.md (use -Root)" -ForegroundColor Yellow
    Write-Host "  release-notes    Build RELEASE_NOTES.md (use -FromTag/-ToTag)" -ForegroundColor Yellow
}

switch ($Target) {
    'lint' { Target-Lint -ScanPath $Path -Severity $Severity }
    'fmt' { if (-not $File) { throw "Use: fmt -File [path]" }; Target-Fmt -File $File }
    'fix' { Target-Fix -Root $Root -SeedEmpty:$SeedEmpty }
    'lint-report' { Target-LintReport -ScanPath $Path -Severity $Severity -OutCsv $OutCsv -OutJson $OutJson }
    'test' {
        try {
            Ensure-Module -Name 'Pester'
            if (Test-Path "$PSScriptRoot\Tests") {
                Invoke-Pester -Path "$PSScriptRoot\Tests" -CI -Output Detailed
            }
            else {
                Write-Host "[SKIP] No .\Tests folder" -ForegroundColor Yellow
            }
        }
        catch {
            throw $_
        }
    }
    'manifest' { Target-Manifest -Root $Root }
    'release-notes' { Target-ReleaseNotes -FromTag $FromTag -ToTag $ToTag }
    default { Show-Help }
}

