# =========================
# CheCha PowerShell Profile
# =========================

# Базова тека профілю (щоб стабільно знаходити Make.ps1 поруч)
$script:ProfileDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Show-CheChaBanner {
    Write-Host ''
    Write-Host '╔═══════════════════════════════════════╗'
    Write-Host '║   🚀 CHECHA_CORE :: Dev Environment   ║'
    Write-Host '║   Super Deploy 2025 (IDE-ENV-2025-10)║'
    Write-Host '╚═══════════════════════════════════════╝'
    Write-Host ''
}

# Універсальна обгортка: прокидає ВСІ аргументи до Make.ps1
function make {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args = @())

    $makePath = Join-Path $script:ProfileDir 'Make.ps1'
    if (-not (Test-Path -LiteralPath $makePath)) {
        Write-Host '⚠️  Make.ps1 не знайдено поруч із профілем' -ForegroundColor Yellow
        Write-Host ("   Очікувалось: {0}" -f $makePath) -ForegroundColor Yellow
        return
    }

    pwsh -NoProfile -ExecutionPolicy Bypass -File $makePath @Args
}

# Прибрати можливі старі alias-и, щоб не заважали функціям
foreach ($a in 'ml', 'mf', 'mt', 'mm', 'mr', 'mx', 'mlr') {
    if (Get-Alias $a -ErrorAction SilentlyContinue) { Remove-Item "alias:$a" -ErrorAction SilentlyContinue }
}

# Скорочення: перший аргумент — target, решта передається як є (БЕЗ будь-яких '+')
function ml { param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args = @()) make 'lint'          @Args }
function mf { param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args = @()) make 'fmt'           @Args }
function mt { param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args = @()) make 'test'          @Args }
function mm { param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args = @()) make 'manifest'      @Args }
function mr { param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args = @()) make 'release-notes' @Args }
function mx { param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args = @()) make 'fix'           @Args }
function mlr { param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args = @()) make 'lint-report'   @Args }

function help-make {
    Write-Host ''
    Write-Host '💡 CheCha Make Targets:'
    Write-Host '  ml  -Path [dir]                         →  PSScriptAnalyzer перевірка'
    Write-Host '  mf  -File [path]                        →  форматування Invoke-Formatter'
    Write-Host '  mt                                      →  тести (Pester, якщо є .\Tests)'
    Write-Host '  mm  -Root [dir]                         →  згенерувати MANIFEST.md'
    Write-Host '  mr  -FromTag vX -ToTag vY               →  зібрати RELEASE_NOTES.md'
    Write-Host '  mx  -Root [dir]                         →  масове автоформатування *.ps1|*.psm1|*.psd1'
    Write-Host '  mlr -Path [dir] [-OutCsv file] [-OutJson file] →  звіт PSScriptAnalyzer у CSV/JSON'
    Write-Host ''
}

Show-CheChaBanner
Write-Host 'Введи "help-make" для короткої довідки або "make" щоб запустити Make.ps1' -ForegroundColor DarkGray

