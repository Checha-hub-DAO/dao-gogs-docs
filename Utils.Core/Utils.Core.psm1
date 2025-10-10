# Utils.Core.psm1  (CHECHA)
  Import-Module "D:\CHECHA_CORE\TOOLS\Checha.Reports\Checha.Reports.psm1" -Force -ErrorAction SilentlyContinue


function Get-KyivDate {
    param([datetime]$Base = (Get-Date))
    $ids = @('FLE Standard Time','Europe/Kyiv')
    foreach($id in $ids){
        try {
            $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($id)
            return [System.TimeZoneInfo]::ConvertTime($Base, $tz)
        } catch {}
    }
    return $Base
}

function Info([string]$m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Warn([string]$m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Err ([string]$m){ Write-Host "[ERR]  $m" -ForegroundColor Red }
function Die ([string]$m){ Err $m; throw $m }

Set-Alias _Info Info -ErrorAction SilentlyContinue
Set-Alias _Warn Warn -ErrorAction SilentlyContinue
Set-Alias _Err  Err  -ErrorAction SilentlyContinue
Set-Alias _Die  Die  -ErrorAction SilentlyContinue

function Start-Op([string]$Name){
    $t = [pscustomobject]@{
        Name  = $Name
        Start = (Get-KyivDate)
    }
    Info ("start: {0} @ {1}" -f $t.Name, $t.Start.ToString('HH:mm:ss'))
    return $t
}

function Stop-Op($Op){
    $end = Get-KyivDate
    $dur = [timespan]::FromSeconds([math]::Round(($end - $Op.Start).TotalSeconds,2))
    Info ("done : {0} (+{1})" -f $Op.Name, $dur)
    [pscustomobject]@{ Name=$Op.Name; Start=$Op.Start; End=$end; Duration=$dur }
}

function Write-AuditLog {
    param([string]$Path, [string]$Message)
    $stamp = (Get-KyivDate).ToString('yyyy-MM-dd HH:mm:ss')
    $dir = Split-Path -Parent $Path
    if ($dir) { $null = New-Item -ItemType Directory -Force -Path $dir }
    Add-Content -LiteralPath $Path -Value ("{0} | {1}" -f $stamp, $Message)
}

function Ensure-GitRepo {
    param([string]$RepoRoot = (Get-Location).Path)
    if (!(Test-Path -LiteralPath $RepoRoot)) { Die "RepoRoot не знайдено: $RepoRoot" }
    git -C $RepoRoot rev-parse --is-inside-work-tree *>$null
    if ($LASTEXITCODE -ne 0) { Die "Не git-репозиторій: $RepoRoot" }
}
function Get-RepoSlug {
    param([string]$RepoRoot = (Get-Location).Path)
    Ensure-GitRepo $RepoRoot
    $url = (git -C $RepoRoot config --get remote.origin.url)
    if ($url -notmatch 'github\.com[:/](?<o>[^/]+)/(?<r>[^/\.]+)(?:\.git)?') {
        Die "remote 'origin' не github.com: $url"
    }
    "{0}/{1}" -f $Matches['o'],$Matches['r']
}

function Disable-GhPager { try { & gh config set pager cat *> $null } catch {} }
function Invoke-Gh {
    param([string[]]$Args,[switch]$ThrowOnError)
    Disable-GhPager
    $null = & gh @Args
    $code = $LASTEXITCODE
    if ($code -ne 0 -and $ThrowOnError) {
        Err ("gh exit={0}, cmd: gh {1}" -f $code, ($Args -join ' '))
        Die "gh помилка (код $code)"
    }
    return $code
}

function Compute-WeekBlock {
    param([datetime]$WeekEnd = (Get-KyivDate).Date)

    # Нормалізація в TZ Києва + опівніч
    $WeekEnd = (Get-KyivDate -Base $WeekEnd).Date

    $startDay  = [math]::Floor(($WeekEnd.Day - 1) / 7) * 7 + 1
    $WeekStart = Get-Date -Year $WeekEnd.Year -Month $WeekEnd.Month -Day $startDay -Hour 0 -Minute 0 -Second 0
    $WeekEnd   = $WeekStart.AddDays(6).Date

    $eom = (Get-Date -Year $WeekStart.Year -Month $WeekStart.Month -Day 1 -Hour 0 -Minute 0 -Second 0).AddMonths(1).AddDays(-1).Date
    if ($WeekEnd -gt $eom) { $WeekEnd = $eom }

    [pscustomobject]@{
        Start = $WeekStart
        End   = $WeekEnd
        Tag   = 'weekly-{0}_to_{1}' -f $WeekStart.ToString('yyyy-MM-dd'), $WeekEnd.ToString('yyyy-MM-dd')
        Name  = 'WeeklyChecklist_{0}_to_{1}.md' -f $WeekStart.ToString('yyyy-MM-dd'), $WeekEnd.ToString('yyyy-MM-dd')
    }
}
