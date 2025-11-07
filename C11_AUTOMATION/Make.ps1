<#
.SYNOPSIS
  CheCha Make.ps1 — простий таск-раннер для CHECHA_CORE

.DESCRIPTION
  Команди:
    - lint           : PSScriptAnalyzer по шляху (безпечно, лише *.ps1|*.psm1|*.psd1)
    - fmt            : Форматування одного файлу (Invoke-Formatter з EOL fallback)
    - fix            : Масове автоформатування *.ps1|*.psm1|*.psd1 (+ опція -SeedEmpty)
    - lint-report    : Звіт PSScriptAnalyzer у CSV/JSON
    - test           : Pester-тести (якщо є .\Tests)
    - manifest       : MANIFEST.md з SHA256 і розмірами (AutoGit за замовчуванням)
    - release-notes  : RELEASE_NOTES.md з git log (AutoGit + опційний tag; guard на clean tree)
    - help           : Довідка

.ПРИКЛАДИ
  pwsh -NoProfile -File .\C11_AUTOMATION\Make.ps1 lint -Path D:\CHECHA_CORE
  pwsh -NoProfile -File .\C11_AUTOMATION\Make.ps1 fmt -File .\TOOLS\Build-DriveAuditReport.ps1
  pwsh -NoProfile -File .\C11_AUTOMATION\Make.ps1 fix -Root D:\CHECHA_CORE -SeedEmpty
  pwsh -NoProfile -File .\C11_AUTOMATION\Make.ps1 lint-report -Path D:\CHECHA_CORE
  pwsh -NoProfile -File .\C11_AUTOMATION\Make.ps1 manifest -Root D:\CHECHA_CORE -Audit
  pwsh -NoProfile -File .\C11_AUTOMATION\Make.ps1 release-notes -Audit -Tag vNEXT
#>


## =========================
## UTF-8 Hardening (global)
## =========================
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
} catch {}

$Global:OutputEncoding = [System.Text.UTF8Encoding]::new($false)  # UTF-8 (no BOM)

$PSDefaultParameterValues['*:Encoding']           = 'utf8'
$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Export-Csv:Encoding']  = 'utf8'
$PSDefaultParameterValues['ConvertTo-Json:Depth'] = 10

function Write-Utf8 {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

$ArgList = @()
if ($Args) {
    $ArgList = @($Args | ForEach-Object {
        if ($_ -is [array]) { ($_.ForEach({ $_.ToString() })) -join ' ' }
        else { $_.ToString() }
    })
}
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Content)
    [System.IO.File]::WriteAllBytes($Path, $bytes)
}
[CmdletBinding()]
param(
  [Parameter(Position=0, Mandatory=$true)]
  [ValidateSet('lint','fmt','fix','lint-report','test','manifest','release-notes','help')]
  [string] $Target,

  # Спільні параметри
  [string] $Path = ".",
  [string] $File,

  # Для fix/manifest
  [string] $Root = ".",

  # Release notes
  [string] $FromTag,
  [string] $ToTag,

  # Lint severity
  [ValidateSet('Error','Warning','Information')]
  [string[]] $Severity = @('Error','Warning'),

  # Вихідні файли для lint-report
  [string] $OutCsv,
  [string] $OutJson,

  # --- DevOps ---
  [switch] $Audit,                       # писати аудит-лог
  [switch] $AutoGit,                     # авто git add/commit/push (додатково до дефолту)
  [string] $GitMessage = "",             # повідомлення коміту
  [string] $Tag,                         # git tag (опційно)
  [switch] $NoAutoGit,                   # вимкнути AutoGit для конкретного запуску
  [switch] $AllowDirty                   # дозволити tag при брудному дереві
)

$ErrorActionPreference = 'Stop'

# -------------------- Utility --------------------

function Ensure-Module {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Name)
  if (-not (Get-Module -ListAvailable -Name $Name)) {
    Install-Module $Name -Scope CurrentUser -Force -ErrorAction Stop | Out-Null
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
  $t = $t  -replace "`r",    "`n"
  return ($t -replace "`n", "`r`n")
}

function Get-PsFilesSafe {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Root
  )
  $rootPath = Resolve-Path $Root
  $skip = @('\.git\','\Windows\','\Program Files','\AppData\','\Application Data\')
  Get-ChildItem -Path $rootPath -Recurse -File -Include *.ps1,*.psm1,*.psd1 -ErrorAction SilentlyContinue |
    Where-Object {
      $p = $_.FullName
      -not ($skip | Where-Object { $p -like "*$_*" })
    }
}

# -------------------- Audit --------------------

$script:CheChaLogDir  = Join-Path $PSScriptRoot 'logs'
$script:CheChaLogFile = Join-Path $script:CheChaLogDir ('CheCha_Audit_{0}.log' -f (Get-Date -Format yyyyMMdd))

function Write-Log {
  param(
    [Parameter(Mandatory)][ValidateSet('INFO','OK','WARN','ERR')][string]$Level,
    [Parameter(Mandatory)][string]$Message,
    [string]$TargetName
  )
  if (-not $Audit) { return }
  if (-not (Test-Path $script:CheChaLogDir)) { New-Item -ItemType Directory -Path $script:CheChaLogDir | Out-Null }
  $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  $line = if ($TargetName) { "[{0}] [{1}] [{2}] {3}" -f $ts,$Level,$TargetName,$Message } else { "[{0}] [{1}] {2}" -f $ts,$Level,$Message }
  Add-Content -LiteralPath $script:CheChaLogFile -Value $line
}

function Start-Op  { param([string]$Name,[string]$ArgsText="") ; Write-Log -Level 'INFO' -Message ("start {0} {1}" -f $Name,$ArgsText) -TargetName $Name }
function End-OpOk  { param([string]$Name,[string]$Note="")     ; Write-Log -Level 'OK'   -Message ("done {0}" -f $Note)         -TargetName $Name }
function End-OpErr { param([string]$Name,[string]$Note="")     ; Write-Log -Level 'ERR'  -Message ("fail {0}" -f $Note)         -TargetName $Name }

# -------------------- Git --------------------

function Ensure-Git {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git не знайдено в PATH." }
  $repo = (git rev-parse --show-toplevel 2>$null)
  if (-not $repo) { throw "Поточна тека не є git-репозиторієм." }
  return $repo
}

function Git-EnsureClean {
  param([switch]$AllowDirty)
  $null = Ensure-Git
  if ($AllowDirty) { return }
  $st = git status --porcelain
  if (-not [string]::IsNullOrWhiteSpace($st)) {
    throw "Репозиторій має незакомічені зміни. Закоміть або використай -AllowDirty."
  }
}

function Git-CommitPush {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Message,
    [string]$Tag
  )
  $null = Ensure-Git
  git add -A | Out-Null

  $st = git status --porcelain
  if ([string]::IsNullOrWhiteSpace($st)) {
    Write-Host "[OK] AutoGit: немає змін" -ForegroundColor Green
    return
  }

  git commit -m $Message | Out-Null
  Write-Host "[OK] AutoGit: commit ✓" -ForegroundColor Green
  if ($Tag) {
    git tag -a $Tag -m $Message | Out-Null
    Write-Host "[OK] AutoGit: tag $Tag ✓" -ForegroundColor Green
  }
  git push | Out-Null
  if ($Tag) { git push origin $Tag | Out-Null }
  Write-Host "[OK] AutoGit: push ✓" -ForegroundColor Green
}

# -------------------- Targets --------------------

function Target-Lint {
  [CmdletBinding()]
  param(
    [string] $ScanPath = '.',
    [ValidateSet('Error','Warning','Information')]
    [string[]] $Severity = @('Error','Warning')
  )

  Ensure-Module -Name 'PSScriptAnalyzer'

  $repo = try { (git rev-parse --show-toplevel) 2>$null } catch { $null }
  $settings = $null
  if ($repo) {
    foreach ($p in @(
      (Join-Path $repo 'config\PSScriptAnalyzerSettings.psd1'),
      (Join-Path $repo 'PSScriptAnalyzerSettings.psd1')
    )) { if (Test-Path -LiteralPath $p) { $settings = $p; break } }
  }

  $files = Get-PsFilesSafe -Root $ScanPath
  if (-not $files) { Write-Host "[OK] Lint: no files to analyze" -ForegroundColor Green; return }

  $invokeParams = @{
    Path     = $files.FullName
    Severity = $Severity
  }
  if ($settings) { $invokeParams['Settings'] = $settings }

  $issues = Invoke-ScriptAnalyzer @invokeParams

  if ($issues) {
    $issues | Format-Table -AutoSize RuleName,Severity,ScriptName,Line,Message | Out-String | Write-Host
    throw "PSScriptAnalyzer reported issues."
  } else {
    Write-Host "[OK] Lint: no issues" -ForegroundColor Green
  }
}

function Target-Fmt {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string] $File)

  $raw = Get-Content -LiteralPath $File -Raw -ErrorAction Stop

  try {
    $formatted = Invoke-Formatter -ScriptDefinition $raw
  } catch {
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

  Start-Op -Name 'manifest' -ArgsText ("Root={0}" -f $Root)
  try {
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

    $doAutoGit = $AutoGit -or (-not $NoAutoGit)  # за замовчуванням УВІМКНЕНО
    if ($doAutoGit) {
      $msg = if ($GitMessage) { $GitMessage } else { "chore(manifest): update MANIFEST.md" }
      Git-CommitPush -Message $msg
    }
    End-OpOk -Name 'manifest' -Note "wrote MANIFEST.md"
  } catch {
    End-OpErr -Name 'manifest' -Note $_.Exception.Message
    throw
  }
}

function Target-ReleaseNotes {
  [CmdletBinding()]
  param([string] $FromTag, [string] $ToTag)

  Start-Op -Name 'release-notes' -ArgsText ("FromTag={0} ToTag={1}" -f $FromTag,$ToTag)
  try {
    $today = Get-Date -Format yyyy-MM-dd
    $out   = Join-Path $PSScriptRoot 'RELEASE_NOTES.md'

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

    $doAutoGit = $AutoGit -or (-not $NoAutoGit)  # за замовчуванням УВІМКНЕНО
    if ($doAutoGit) {
      $msg = if ($GitMessage) { $GitMessage } else { "docs(release-notes): update $ver $today" }
      if ($Tag) { Git-EnsureClean -AllowDirty:$AllowDirty }  # guard перед тегом
      Git-CommitPush -Message $msg -Tag $Tag
    }
    End-OpOk -Name 'release-notes' -Note "wrote RELEASE_NOTES.md"
  } catch {
    End-OpErr -Name 'release-notes' -Note $_.Exception.Message
    throw
  }
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
  $files = Get-ChildItem -Path $rootPath -Recurse -File -Include *.ps1,*.psm1,*.psd1
  if (-not $files) {
    Write-Host "[SKIP] No PowerShell files found" -ForegroundColor Yellow
    return
  }

  $ok=0; $changed=0; $fail=0
  foreach($f in $files){
    try {
      $raw = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop
      if ([string]::IsNullOrEmpty($raw)) {
        if ($SeedEmpty) {
          New-EmptyScriptHeader -Name $f.BaseName -Synopsis "Placeholder for $($f.Name)" |
            Set-Content -LiteralPath $f.FullName -Encoding UTF8
          $changed++
        } else {
          "" | Set-Content -LiteralPath $f.FullName -Encoding UTF8
          $ok++
        }
        continue
      }

      try {
        $fmt = Invoke-Formatter -ScriptDefinition $raw
      } catch {
        $norm = Normalize-EOL -Text $raw
        $fmt  = Invoke-Formatter -ScriptDefinition $norm
      }

      if ($fmt -and $fmt -ne $raw) {
        $fmt | Set-Content -LiteralPath $f.FullName -Encoding UTF8
        $changed++
      } else {
        $ok++
      }
    } catch {
      Write-Warning ("[FAIL] {0}: {1}" -f $f.FullName, $_.Exception.Message)
      $fail++
    }
  }
  Write-Host ("[FIX] ok:{0} changed:{1} fail:{2}" -f $ok,$changed,$fail) -ForegroundColor Cyan
}

function Target-LintReport {
  [CmdletBinding()]
  param(
    [string] $ScanPath = '.',
    [ValidateSet('Error','Warning','Information')]
    [string[]] $Severity = @('Error','Warning'),
    [string] $OutCsv,
    [string] $OutJson
  )

  Ensure-Module -Name 'PSScriptAnalyzer'

  $repo = try { (git rev-parse --show-toplevel) 2>$null } catch { $null }
  $settings = $null
  if ($repo) {
    foreach ($p in @(
      (Join-Path $repo 'config\PSScriptAnalyzerSettings.psd1'),
      (Join-Path $repo 'PSScriptAnalyzerSettings.psd1')
    )) { if (Test-Path -LiteralPath $p) { $settings = $p; break } }
  }

  $files = Get-PsFilesSafe -Root $ScanPath
  # Вихідні файли за замовчуванням
  $outDir = Join-Path $PSScriptRoot 'lint_reports'
  if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  if (-not $OutCsv)  { $OutCsv  = Join-Path $outDir ("lint_{0}.csv"  -f $stamp) }
  if (-not $OutJson) { $OutJson = Join-Path $outDir ("lint_{0}.json" -f $stamp) }

  if (-not $files) {
    ''  | Set-Content -LiteralPath $OutCsv  -Encoding UTF8
    '[]'| Set-Content -LiteralPath $OutJson -Encoding UTF8
    Write-Host "[OK] No issues. Empty reports written." -ForegroundColor Green
    return
  }

  $invokeParams = @{
    Path     = $files.FullName
    Severity = $Severity
  }
  if ($settings) { $invokeParams['Settings'] = $settings }

  $issues = Invoke-ScriptAnalyzer @invokeParams

  if ($issues) {
    $issues | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8
    $issues | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutJson -Encoding UTF8
    Write-Host "[OK] Lint report saved: $OutCsv ; $OutJson" -ForegroundColor Green
  } else {
    ''  | Set-Content -LiteralPath $OutCsv  -Encoding UTF8
    '[]'| Set-Content -LiteralPath $OutJson -Encoding UTF8
    Write-Host "[OK] No issues. Empty reports written." -ForegroundColor Green
  }
}

function Show-Help {
  Write-Host "CheCha Make.ps1 targets:" -ForegroundColor Cyan
  Write-Host "  lint             Run PSScriptAnalyzer on path (safe file-filter)" -ForegroundColor Yellow
  Write-Host "  fmt              Format a file: -File [path]" -ForegroundColor Yellow
  Write-Host "  fix              Format all *.ps1|*.psm1|*.psd1 under -Root (EOL fallback, -SeedEmpty)" -ForegroundColor Yellow
  Write-Host "  lint-report      Export analyzer results to CSV/JSON (use -OutCsv/-OutJson)" -ForegroundColor Yellow
  Write-Host "  test             Run Pester tests if .\Tests exists" -ForegroundColor Yellow
  Write-Host "  manifest         Generate MANIFEST.md (AutoGit on by default; -NoAutoGit to skip)" -ForegroundColor Yellow
  Write-Host "  release-notes    Build RELEASE_NOTES.md (AutoGit on by default; -Tag; -AllowDirty; -NoAutoGit)" -ForegroundColor Yellow
}

# -------------------- Dispatch --------------------

switch ($Target) {
  'lint'          { Target-Lint -ScanPath $Path -Severity $Severity }
  'fmt'           { if (-not $File) { throw "Use: fmt -File [path]" }; Target-Fmt -File $File }
  'fix'           { Target-Fix -Root $Root -SeedEmpty:$SeedEmpty }
  'lint-report'   { Target-LintReport -ScanPath $Path -Severity $Severity -OutCsv $OutCsv -OutJson $OutJson }
  'test'          {
                    try {
                      Ensure-Module -Name 'Pester'
                      if (Test-Path "$PSScriptRoot\Tests") {
                        Invoke-Pester -Path "$PSScriptRoot\Tests" -CI -Output Detailed
                      } else {
                        Write-Host "[SKIP] No .\Tests folder" -ForegroundColor Yellow
                      }
                    } catch {
                      throw $_
                    }
                  }
  'manifest'      { Target-Manifest -Root $Root }
  'release-notes' { Target-ReleaseNotes -FromTag $FromTag -ToTag $ToTag }
    'iteta:register' {
        Write-Host "[STEP] iteta:register — старт" -ForegroundColor Cyan

        $script = Join-Path $env:CHECHA_ROOT 'TOOLS\Build-ITETA_UkraineMatrix.ps1'
        if (-not (Test-Path -LiteralPath $script)) {
            throw "Не знайдено скрипт: $script"
        }

        $RegisterArgs = @()
        if ($ArgList.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($ArgList[0])) {
            $inputPath = $ArgList[0].Trim('"').Trim()
            $RegisterArgs += @('-RegisterPath', $inputPath)
        } else {
            $RegisterArgs += @('-Register')
        }

        $psi = @{
            FilePath        = 'pwsh'
            ArgumentList    = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $script) + $RegisterArgs
            WorkingDirectory= (Get-Location)
            NoNewWindow     = $true
            Wait            = $true
        }

        Write-Host "[INFO] Виклик: pwsh $($psi.ArgumentList -join ' ')" -ForegroundColor DarkGray
        $proc = Start-Process @psi -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "iteta:register завершився з кодом $($proc.ExitCode)"
        }
        Write-Host "[OK] iteta:register — завершено" -ForegroundColor Green
        break
    }

  default         { Show-Help }
}
