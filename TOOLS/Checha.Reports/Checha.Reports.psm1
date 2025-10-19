#region helpers (log, fail, env)
function _Info([string]$m) { Write-Host "[INFO] $m" -ForegroundColor Cyan }
function _Warn([string]$m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }
function _Err ([string]$m) { Write-Host "[ERR]  $m" -ForegroundColor Red }
function _Die ([string]$m) { _Err $m; throw $m }

Import-Module "D:\CHECHA_CORE\TOOLS\Utils.Core\Utils.Core.psd1" -Force
Set-Alias _Ensure-GitRepo Ensure-GitRepo -ErrorAction SilentlyContinue
Set-Alias _Info           Info           -ErrorAction SilentlyContinue
Set-Alias _Warn           Warn           -ErrorAction SilentlyContinue
Set-Alias _Err            Err            -ErrorAction SilentlyContinue
Set-Alias _Die            Die            -ErrorAction SilentlyContinue


# TZ helper: Europe/Kyiv (Windows: FLE Standard Time; fallback: Europe/Kyiv)
function Get-KyivDate {
    param([datetime]$Base = (Get-Date))
    $ids = @('FLE Standard Time', 'Europe/Kyiv')
    foreach ($id in $ids) {
        try {
            $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($id)
            return [System.TimeZoneInfo]::ConvertTime($Base, $tz)
        }
        catch {}
    }
    return $Base
}

# One-time: disable gh pager so Windows doesn’t need `less`
try { & gh config set pager cat 1>$null 2>$null } catch {}

function _Ensure-GitRepo([string]$RepoRoot) {
    if (!(Test-Path -LiteralPath $RepoRoot)) { _Die "RepoRoot не знайдено: $RepoRoot" }
    Push-Location $RepoRoot
    git rev-parse --is-inside-work-tree *>$null
    if ($LASTEXITCODE -ne 0) { Pop-Location; _Die "Не git-репозиторій: $RepoRoot" }
}

# Обчислення блоку (1–7, 8–14, 15–21, 22–кінець) у TZ Києва
function _Compute-WeekBlock {
    param([datetime]$WeekEnd = (Get-KyivDate).Date)

    # Нормалізація в TZ Києва + опівніч
    $WeekEnd = (Get-KyivDate -Base $WeekEnd).Date
    $startDay = [math]::Floor(($WeekEnd.Day - 1) / 7) * 7 + 1
    $WeekStart = Get-Date -Year $WeekEnd.Year -Month $WeekEnd.Month -Day $startDay -Hour 0 -Minute 0 -Second 0
    $WeekEnd = $WeekStart.AddDays(6).Date

    $eom = (Get-Date -Year $WeekStart.Year -Month $WeekStart.Month -Day 1 -Hour 0 -Minute 0 -Second 0).AddMonths(1).AddDays(-1).Date
    if ($WeekEnd -gt $eom) { $WeekEnd = $eom }

    [pscustomobject]@{
        Start = $WeekStart
        End   = $WeekEnd
        Tag   = 'weekly-{0}_to_{1}' -f $WeekStart.ToString('yyyy-MM-dd'), $WeekEnd.ToString('yyyy-MM-dd')
        Name  = 'WeeklyChecklist_{0}_to_{1}.md' -f $WeekStart.ToString('yyyy-MM-dd'), $WeekEnd.ToString('yyyy-MM-dd')
    }
}

function _Get-ReportPaths([string]$RepoRoot, [string]$ReportName) {
    $reports = Join-Path $RepoRoot 'REPORTS'
    $abs = Join-Path $reports $ReportName
    [pscustomobject]@{
        ReportsDir = $reports
        AbsPath    = $abs
        RelPath    = "REPORTS/$ReportName"
    }
}
#endregion

#region New-WeeklyReport
function New-WeeklyReport {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]  $RepoRoot = 'D:\CHECHA_CORE',
        [datetime]$WeekEnd = (Get-KyivDate).Date,
        [string]  $ExpectedBranch = 'reports',
        [string]  $RestoreLogPath = 'D:\CHECHA_CORE\C06_FOCUS\FOCUS_RestoreLog.md',
        [string]  $MatRestoreCsv = 'D:\CHECHA_CORE\C07_ANALYTICS\MAT_RESTORE.csv',
        [string]  $ItetaCsv = 'D:\CHECHA_CORE\ITETA\reports\ITETA_Dashboard.csv',
        [int]     $TopN = 5,
        [switch]  $NoCommit
    )

    _Ensure-GitRepo $RepoRoot
    try {
        $curBranch = (git rev-parse --abbrev-ref HEAD).Trim()
        if ($ExpectedBranch -and $curBranch -ne $ExpectedBranch) { _Die "Очікувалась гілка '$ExpectedBranch', поточна — '$curBranch'." }

        $blk = _Compute-WeekBlock $WeekEnd
        $paths = _Get-ReportPaths $RepoRoot $blk.Name
        $null = New-Item -ItemType Directory -Force -Path $paths.ReportsDir

        function _TryReadCsv($p) { if (Test-Path -LiteralPath $p) { try { Import-Csv -LiteralPath $p } catch { @() } } else { @() } }
        function _TopN($rows, [int]$n, [string]$score = 'score', [string]$name = 'name') {
            if (-not $rows) { return @() }
            $rows | Where-Object { $_.$score -as [double] } |
                Sort-Object { [double]($_.$score) } -Descending |
                Select-Object -First $n
        }

        $mat = _TryReadCsv $MatRestoreCsv
        $top = _TopN $mat $TopN 'score' 'name'
        $iteta = _TryReadCsv $ItetaCsv

        $kpi = @()
        if ($iteta.Count -gt 0) {
            $last = $iteta[-1]
            foreach ($p in 'AI_Efficiency', 'Info_Fatigue', 'Synergy_Index') {
                $v = $last.$p; if ($v) { $kpi += ("- **{0}:** {1}" -f $p, $v) }
            }
        }

        $nowKyiv = Get-KyivDate
        $md = @()
        $md += "# Weekly Checklist ($($blk.Start.ToString('yyyy-MM-dd')) → $($blk.End.ToString('yyyy-MM-dd')))"
        $md += ""
        $md += "- Згенеровано: {0}" -f $nowKyiv.ToString('yyyy-MM-dd HH:mm:ss')
        $md += "- Гілка: $curBranch"
        $md += "- Звіт-файл: $($paths.RelPath)"
        $md += ""
        $md += "## KPI (ITETA)"
        if ($kpi.Count) { $md += $kpi } else { $md += "_немає даних_" }
        $md += ""
        $md += "## Матриця відновлення — Top-$TopN"
        if ($top.Count) {
            $md += "| Позиція | Оцінка | Елемент |"
            $md += "|---:|---:|---|"
            $i = 1; foreach ($r in $top) { $md += ("| {0} | {1} | {2} |" -f $i, [string]$r.score, ($r.name ?? $r.title ?? '(без назви)')); $i++ }
        }
        else { $md += "_немає даних або невірні колонки (очікуються `score`, `name`)_" }
        $md += ""
        $md += "## Restore Log (останні 20)"
        $md += '```text'
        if (Test-Path -LiteralPath $RestoreLogPath) { $md += (Get-Content -LiteralPath $RestoreLogPath -Tail 20) } else { $md += "(порожньо)" }
        $md += '```'
        $md += ""

        $md -join "`r`n" | Set-Content -LiteralPath $paths.AbsPath -Encoding UTF8
        _Info "Звіт сформовано: $($paths.RelPath)"

        if (-not $NoCommit) {
            git add -A *>$null
            $has = -not [string]::IsNullOrWhiteSpace((git status --porcelain))
            if ($has) {
                $msg = "WeeklyChecklist update: {0} → {1}" -f $blk.Start.ToString('yyyy-MM-dd'), $blk.End.ToString('yyyy-MM-dd')
                if ($PSCmdlet.ShouldProcess($RepoRoot, "commit: $msg")) {
                    git commit -m $msg *>$null
                    _Info "Коміт виконано: $msg"
                }
            }
            else { _Info "Змін для коміту немає." }
        }

        [pscustomobject]@{
            ReportPath = $paths.AbsPath
            ReportRel  = $paths.RelPath
            Tag        = $blk.Tag
            Start      = $blk.Start
            End        = $blk.End
        }
    }
    finally { Pop-Location }
}
#endregion

#region Publish-WeeklyTag
function Publish-WeeklyTag {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]  $RepoRoot = 'D:\CHECHA_CORE',
        [datetime]$WeekEnd = (Get-KyivDate).Date,
        [string]  $Remote = 'origin',
        [string]  $ExpectedBranch = 'reports'
    )
    _Ensure-GitRepo $RepoRoot
    try {
        $curBranch = (git rev-parse --abbrev-ref HEAD).Trim()
        if ($ExpectedBranch -and $curBranch -ne $ExpectedBranch) { _Die "Очікувалась гілка '$ExpectedBranch', поточна — '$curBranch'." }

        $blk = _Compute-WeekBlock $WeekEnd
        $paths = _Get-ReportPaths $RepoRoot $blk.Name
        if (!(Test-Path -LiteralPath $paths.AbsPath)) { _Die "Немає файла звіту: $($paths.AbsPath)" }

        _Info ("Цільовий інтервал: {0} → {1}" -f $blk.Start.ToString('yyyy-MM-dd'), $blk.End.ToString('yyyy-MM-dd'))
        _Info "Тег: $($blk.Tag)"
        _Info "Файл звіту: $($paths.RelPath)"

        $localHas = (git tag -l $blk.Tag) -join ''
        if ([string]::IsNullOrWhiteSpace($localHas)) {
            if ($PSCmdlet.ShouldProcess($RepoRoot, "tag $($blk.Tag)")) {
                git tag -a $blk.Tag -m ("Weekly checklist {0} → {1}" -f $blk.Start.ToString('yyyy-MM-dd'), $blk.End.ToString('yyyy-MM-dd')) || _Die "Не вдалося створити тег."
                _Info "Локальний тег створено."
            }
        }
        else { _Info "Локальний тег вже існує." }

        $remoteHas = (git ls-remote --tags $Remote "refs/tags/$($blk.Tag)") -join ''
        if ([string]::IsNullOrWhiteSpace($remoteHas)) {
            if ($PSCmdlet.ShouldProcess($RepoRoot, "push tag $($blk.Tag) to $Remote")) {
                git push $Remote $blk.Tag || _Die "Не вдалося запушити тег."
                _Info "Тег запушено на $Remote."
            }
        }
        else { _Info "Віддалений тег вже існує." }

        $present = (git ls-tree -r --name-only $blk.Tag | Select-String -SimpleMatch $paths.RelPath)
        if (-not $present) { _Die "Аномалія: у знімку $($blk.Tag) немає $($paths.RelPath)" }
        _Info "Перевірка пройдена: $($paths.RelPath) присутній у $($blk.Tag)."

        $logDir = Join-Path $RepoRoot 'C03_LOG\AUDIT'
        $null = New-Item -ItemType Directory -Force -Path $logDir
        $stamp = (Get-KyivDate).ToString('yyyy-MM-dd HH:mm:ss')
        $logPath = Join-Path $logDir ("WEEKLY_TAG_{0}.log" -f ((Get-KyivDate).ToString('yyyy-MM-dd')))
        $entry = "{0} | repo={1} | branch={2} | tag={3} | report={4}" -f $stamp, $RepoRoot, $curBranch, $blk.Tag, $paths.RelPath
        Add-Content -Path $logPath -Value $entry
        _Info "Запис у лог: $logPath"

        $blk.Tag
    }
    finally { Pop-Location }
}
#endregion

#region New-WeeklyRelease
function New-WeeklyRelease {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]  $RepoRoot = 'D:\CHECHA_CORE',
        [datetime]$WeekEnd = (Get-KyivDate).Date,
        [string]  $Title,
        [string]  $Notes = "Автоматичний тижневий звіт",
        [string[]]$AdditionalAssets
    )
    _Ensure-GitRepo $RepoRoot
    try {
        $blk = _Compute-WeekBlock $WeekEnd
        $paths = _Get-ReportPaths $RepoRoot $blk.Name
        if (!(Test-Path -LiteralPath $paths.AbsPath)) { _Die "Немає файла звіту: $($paths.AbsPath)" }

        $originUrl = (git config --get remote.origin.url)
        if ($originUrl -notmatch 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/\.]+)(?:\.git)?') { _Die "remote 'origin' не github.com: $originUrl" }
        $repoSlug = "$($Matches.owner)/$($Matches.repo)"

        $hasRemoteTag = (git ls-remote --tags origin "refs/tags/$($blk.Tag)") -join ''
        if (-not $hasRemoteTag) { _Die "Тег $($blk.Tag) не запушено на origin. Виконай: git push origin $($blk.Tag)" }

        if (-not $Title) { $Title = "Weekly {0} → {1}" -f $blk.Start.ToString('yyyy-MM-dd'), $blk.End.ToString('yyyy-MM-dd') }

        $assetAbs = (Resolve-Path $paths.AbsPath).Path
        $toUpload = @($assetAbs)
        if ($AdditionalAssets) {
            foreach ($p in $AdditionalAssets) {
                if (Test-Path $p) { $toUpload += (Resolve-Path $p).Path }
            }
        }

        & gh release view $blk.Tag --repo $repoSlug 1>$null 2>$null
        if ($LASTEXITCODE -eq 0) {
            _Info "Реліз вже існує. Оновлюю активи…"
            $uploadArgs = @('release', 'upload', $blk.Tag) + $toUpload + @('--repo', $repoSlug, '--clobber')
            $null = & gh @uploadArgs
            if ($LASTEXITCODE -ne 0) { _Err ("cmd: gh {0}" -f ($uploadArgs -join ' ')); _Die "gh release upload завершився з кодом $LASTEXITCODE" }
            _Info "Активи оновлено."
        }
        else {
            $createArgs = @('release', 'create', $blk.Tag, '--repo', $repoSlug, '--title', $Title, '--notes', $Notes) + $toUpload
            $null = & gh @createArgs
            if ($LASTEXITCODE -ne 0) { _Err ("cmd: gh {0}" -f ($createArgs -join ' ')); _Die "gh release create завершився з кодом $LASTEXITCODE" }
            _Info "Реліз створено: $($blk.Tag)"
        }
    }
    finally { Pop-Location }
}
#endregion

#region Publish-WeeklyAll
function Publish-WeeklyAll {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]  $RepoRoot = 'D:\CHECHA_CORE',
        [datetime]$WeekEnd = (Get-KyivDate).Date,
        [string]  $ExpectedBranch = 'reports',
        [string]  $RestoreLogPath = 'D:\CHECHA_CORE\C06_FOCUS\FOCUS_RestoreLog.md',
        [string]  $MatRestoreCsv = 'D:\CHECHA_CORE\C07_ANALYTICS\MAT_RESTORE.csv',
        [string]  $ItetaCsv = 'D:\CHECHA_CORE\ITETA\reports\ITETA_Dashboard.csv',
        [int]     $TopN = 5,
        [string]  $Remote = 'origin',
        [switch]  $NoRelease,
        [string]  $Title,
        [string]  $Notes = "Автоматичний тижневий звіт",
        [switch]  $Prune,
        [switch]  $ZipAssets
    )

    # 1) Звіт + коміт
    $r = New-WeeklyReport -RepoRoot $RepoRoot -WeekEnd $WeekEnd -ExpectedBranch $ExpectedBranch `
        -RestoreLogPath $RestoreLogPath -MatRestoreCsv $MatRestoreCsv -ItetaCsv $ItetaCsv -TopN $TopN `
        -WhatIf:$WhatIfPreference

    # 2) Тег (ідемпотентно)
    $tag = Publish-WeeklyTag -RepoRoot $RepoRoot -WeekEnd $WeekEnd -Remote $Remote -ExpectedBranch $ExpectedBranch `
        -WhatIf:$WhatIfPreference

    # (опційно) підготовка додаткових активів
    $extraAssets = @()
    if ($ZipAssets) {
        $blk = _Compute-WeekBlock $WeekEnd
        $paths = _Get-ReportPaths $RepoRoot $blk.Name
        $zip = Join-Path (Split-Path $paths.AbsPath) ("WeeklyChecklist_{0}_to_{1}.zip" -f $blk.Start.ToString('yyyy-MM-dd'), $blk.End.ToString('yyyy-MM-dd'))
        if (Test-Path $zip) { Remove-Item $zip -Force }
        Compress-Archive -LiteralPath $paths.AbsPath -DestinationPath $zip
        $extraAssets += $zip
    }

    # 3) (опційно) чистка активів перед аплоудом
    if ($Prune) {
        Remove-WeeklyReleaseAsset -RepoRoot $RepoRoot -WeekEnd $WeekEnd -Match '^(WeeklyChecklist_.*\.(md|zip))$' -WhatIf:$WhatIfPreference
    }

    # 4) Реліз
    if (-not $NoRelease) {
        New-WeeklyRelease -RepoRoot $RepoRoot -WeekEnd $WeekEnd -Title $Title -Notes $Notes -AdditionalAssets $extraAssets `
            -WhatIf:$WhatIfPreference
    }
}
#endregion

#region Show-WeeklyReleaseAssets
function Show-WeeklyReleaseAssets {
    [CmdletBinding()]
    param(
        [string]  $RepoRoot = 'D:\CHECHA_CORE',
        [datetime]$WeekEnd = (Get-KyivDate).Date,
        [string]  $Tag,
        [switch]  $Open,
        [string]  $DownloadTo
    )
    _Ensure-GitRepo $RepoRoot
    try {
        $originUrl = (git config --get remote.origin.url)
        if ($originUrl -notmatch 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/\.]+)(?:\.git)?') { _Die "remote 'origin' не github.com: $originUrl" }
        $repoSlug = "$($Matches.owner)/$($Matches.repo)"
        if (-not $Tag) { $Tag = (_Compute-WeekBlock $WeekEnd).Tag }

        $json = gh release view $Tag --repo $repoSlug --json tagName, name, assets 2>$null
        if (-not $json) { _Die "Реліз '$Tag' не знайдено у $repoSlug" }
        $rel = $json | ConvertFrom-Json

        $rows = $rel.assets | ForEach-Object {
            [pscustomobject]@{
                Name        = $_.name
                SizeBytes   = $_.size
                Downloaded  = $_.downloadCount
                ContentType = $_.contentType
                CreatedAt   = $_.createdAt
                Url         = $_.url
            }
        }

        if (-not $rows) { _Info "У релізі '$($rel.tagName)' немає активів."; return }
        $rows | Sort-Object Name | Format-Table -AutoSize

        if ($Open) { foreach ($u in ($rows.Url)) { Start-Process $u }; _Info "Відкрив посилання у браузері." }
        if ($DownloadTo) {
            $dest = Resolve-Path (New-Item -ItemType Directory -Force -Path $DownloadTo) | Select-Object -ExpandProperty Path
            foreach ($a in $rows) { Invoke-WebRequest -Uri $a.Url -OutFile (Join-Path $dest $a.Name) -UseBasicParsing }
            _Info "Завантажено до: $dest"
        }
    }
    finally { Pop-Location }
}
#endregion

#region Show-WeeklyRelease
function Show-WeeklyRelease {
    [CmdletBinding()]
    param(
        [string]  $RepoRoot = 'D:\CHECHA_CORE',
        [datetime]$WeekEnd = (Get-KyivDate).Date,
        [string]  $Tag
    )
    _Ensure-GitRepo $RepoRoot
    try {
        $originUrl = (git config --get remote.origin.url)
        if ($originUrl -notmatch 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/\.]+)(?:\.git)?') { _Die "remote 'origin' не github.com: $originUrl" }
        $repoSlug = "$($Matches.owner)/$($Matches.repo)"
        if (-not $Tag) { $Tag = (_Compute-WeekBlock $WeekEnd).Tag }

        $json = gh release view $Tag --repo $repoSlug --json tagName, name, createdAt, publishedAt, body, assets 2>$null
        if (-not $json) { _Die "Реліз '$Tag' не знайдено у $repoSlug" }
        $r = $json | ConvertFrom-Json

        Write-Host ("`n{Name}     : {0}" -f ($r.name ?? '(без назви)'))
        Write-Host ("Tag        : {0}" -f $r.tagName)
        Write-Host ("CreatedAt  : {0}" -f ($r.createdAt ?? '(невідомо)'))
        Write-Host ("PublishedAt: {0}" -f ($r.publishedAt ?? '(не опубліковано)'))
        Write-Host ("Assets     : {0}" -f ($r.assets.Count))
        if ($r.body) { Write-Host "Notes:"; Write-Host ($r.body -replace "`r?`n", "`n  ") } else { Write-Host "Notes      : (порожньо)" }
    }
    finally { Pop-Location }
}
#endregion

#region Remove-WeeklyReleaseAsset
function Remove-WeeklyReleaseAsset {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]  $RepoRoot = 'D:\CHECHA_CORE',
        [datetime]$WeekEnd = (Get-KyivDate).Date,
        [string]  $Tag,
        [string[]]$Name,
        [string]  $Like,
        [string]  $Match
    )
    _Ensure-GitRepo $RepoRoot
    try {
        $originUrl = (git config --get remote.origin.url)
        if ($originUrl -notmatch 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/\.]+)(?:\.git)?') { _Die "remote 'origin' не github.com: $originUrl" }
        $repoSlug = "$($Matches.owner)/$($Matches.repo)"
        if (-not $Tag) { $Tag = (_Compute-WeekBlock $WeekEnd).Tag }

        $json = gh release view $Tag --repo $repoSlug --json assets 2>$null
        if (-not $json) { _Die "Реліз '$Tag' не знайдено у $repoSlug" }
        $assets = ($json | ConvertFrom-Json).assets
        if (-not $assets -or $assets.Count -eq 0) { _Info "У релізі немає активів."; return }

        $toRemove = @()
        if ($Name) { foreach ($n in $Name) { $toRemove += $assets | Where-Object { $_.name -eq $n } } }
        if ($Like) { $toRemove += $assets | Where-Object { $_.name -like $Like } }
        if ($Match) { $toRemove += $assets | Where-Object { $_.name -match $Match } }
        if (-not $Name -and -not $Like -and -not $Match) { _Die "Задай -Name, -Like або -Match для вибору активів." }

        $toRemove = $toRemove | Sort-Object name -Unique
        if (-not $toRemove -or $toRemove.Count -eq 0) { _Info "За критеріями файли не знайдено."; return }

        Write-Host "Видаляю активи:"; $toRemove | ForEach-Object { Write-Host " - $($_.name)" }
        foreach ($a in $toRemove) {
            $args = @('release', 'delete-asset', $Tag, $a.name, '--repo', $repoSlug, '--yes')
            if ($PSCmdlet.ShouldProcess("$repoSlug/$Tag", "delete asset '$($a.name)'")) {
                $null = & gh @args
                if ($LASTEXITCODE -ne 0) { _Err ("Помилка видалення: {0}" -f $a.name) } else { _Info ("Видалено: {0}" -f $a.name) }
            }
        }
    }
    finally { Pop-Location }
}
#endregion

#region Test-WeeklyEnv
function Test-WeeklyEnv {
    [CmdletBinding()]
    param([string]$RepoRoot = 'D:\CHECHA_CORE')
    _Ensure-GitRepo $RepoRoot
    try {
        $ok = $true; $out = @()
        $branch = (git rev-parse --abbrev-ref HEAD).Trim()
        $out += "git: branch=$branch"

        $originUrl = (git config --get remote.origin.url)
        if ($originUrl -notmatch 'github\.com[:/](?<o>[^/]+)/(?<r>[^/\.]+)(?:\.git)?') { $ok = $false; $out += "origin: NOT GITHUB ($originUrl)" }
        else { $repoSlug = "$($Matches.o)/$($Matches.r)"; $out += "origin: $repoSlug" }

        & gh auth status 1>$null 2>$null
        if ($LASTEXITCODE -ne 0) { $ok = $false; $out += "gh: NOT AUTHENTICATED" } else { $out += "gh: ok" }

        $out += "tz: $(Get-KyivDate).ToString('yyyy-MM-dd HH:mm:ss') (Europe/Kyiv)"
        [pscustomobject]@{ Success = $ok; Details = $out }
    }
    finally { Pop-Location }
}
#endregion

#region Download-WeeklyReleaseAssets
function Download-WeeklyReleaseAssets {
    [CmdletBinding()]
    param(
        [string]  $RepoRoot = 'D:\CHECHA_CORE',
        [datetime]$WeekEnd = (Get-KyivDate).Date,
        [string]  $Tag,
        [string]  $Destination = 'D:\CHECHA_CORE\RELEASES',
        [switch]  $Overwrite
    )
    _Ensure-GitRepo $RepoRoot
    try {
        $originUrl = (git config --get remote.origin.url)
        if ($originUrl -notmatch 'github\.com[:/](?<o>[^/]+)/(?<r>[^/\.]+)(?:\.git)?') { _Die "origin не github.com: $originUrl" }
        $repoSlug = "$($Matches.o)/$($Matches.r)"
        if (-not $Tag) { $Tag = (_Compute-WeekBlock $WeekEnd).Tag }

        $json = gh release view $Tag --repo $repoSlug --json assets 2>$null
        if (-not $json) { _Die "Реліз '$Tag' не знайдено у $repoSlug" }
        $assets = ($json | ConvertFrom-Json).assets
        if (-not $assets) { _Info "Немає активів"; return }

        $dest = (Resolve-Path (New-Item -ItemType Directory -Force -Path $Destination)).Path
        foreach ($a in $assets) {
            $out = Join-Path $dest $a.name
            if ((Test-Path $out) -and -not $Overwrite) { _Info "skip: $($a.name) існує"; continue }
            Invoke-WebRequest -Uri $a.url -OutFile $out -UseBasicParsing
            _Info "ok: $($a.name) → $out"
        }
    }
    finally { Pop-Location }
}
#endregion

function New-WeeklyReport {
    [CmdletBinding()]
    param(
        [string]  $RepoRoot = 'D:\CHECHA_CORE',
        [datetime]$WeekEnd = (Get-KyivDate).Date,
        [string]  $ExpectedBranch = 'reports'
    )
    Ensure-GitRepo $RepoRoot
    $blk = Compute-WeekBlock -WeekEnd $WeekEnd
    Info ("Weekly block: {0} → {1}" -f $blk.Start.ToString('yyyy-MM-dd'), $blk.End.ToString('yyyy-MM-dd'))
    Push-Location $RepoRoot
    try {
        & pwsh -File "D:\CHECHA_CORE\TOOLS\Generate-WeeklyChecklistReport.ps1" -WeekEnd $blk.End 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) { Die "Generate-WeeklyChecklistReport.ps1 failed with exit $LASTEXITCODE" }
    }
    finally { Pop-Location }
    [pscustomobject]@{ Start = $blk.Start; End = $blk.End; Tag = $blk.Tag; ReportRel = "REPORTS/$($blk.Name)" }
}

function Publish-WeeklyTag {
    [CmdletBinding()]
    param(
        [string]  $RepoRoot = 'D:\CHECHA_CORE',
        [datetime]$WeekEnd = (Get-KyivDate).Date,
        [string]  $Remote = 'origin',
        [string]  $ExpectedBranch = 'reports'
    )
    Ensure-GitRepo $RepoRoot
    $blk = Compute-WeekBlock -WeekEnd $WeekEnd
    Push-Location $RepoRoot
    try {
        & pwsh -File "D:\CHECHA_CORE\TOOLS\New-WeeklyTag.ps1" -RepoRoot $RepoRoot -WeekEnd $blk.End -Remote $Remote 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) { Die "New-WeeklyTag.ps1 failed with exit $LASTEXITCODE" }
    }
    finally { Pop-Location }
    $blk.Tag
}

function New-WeeklyRelease {
    [CmdletBinding()]
    param(
        [string]  $RepoRoot = 'D:\CHECHA_CORE',
        [datetime]$WeekEnd = (Get-KyivDate).Date
    )
    Ensure-GitRepo $RepoRoot
    $repoSlug = Get-RepoSlug -RepoRoot $RepoRoot
    $blk = Compute-WeekBlock -WeekEnd $WeekEnd
    $assetAbs = Join-Path $RepoRoot (Join-Path "REPORTS" $blk.Name)
    if (-not (Test-Path -LiteralPath $assetAbs)) { Die "Asset not found: $assetAbs" }
    Disable-GhPager
    $code = Invoke-Gh -Args @('release', 'view', $blk.Tag, '--repo', $repoSlug, '--json', 'tagName')
    if ($code -eq 0) {
        Info "Release exists. Uploading asset…"
        Invoke-Gh -Args @('release', 'upload', $blk.Tag, $assetAbs, '--repo', $repoSlug, '--clobber') -ThrowOnError | Out-Null
        Info "Asset updated."
    }
    else {
        $title = "Weekly {0} → {1}" -f $blk.Start.ToString('yyyy-MM-dd'), $blk.End.ToString('yyyy-MM-dd')
        Info "Creating release $($blk.Tag)…"
        Invoke-Gh -Args @('release', 'create', $blk.Tag, '--repo', $repoSlug, '--title', $title, '--notes', 'Auto-generated weekly report', $assetAbs) -ThrowOnError | Out-Null
        Info "Release created."
    }
    [pscustomobject]@{ Repo = $repoSlug; Tag = $blk.Tag; Asset = ("REPORTS/{0}" -f $blk.Name) }
}

function Publish-WeeklyAll {
    [CmdletBinding()]
    param(
        [string]  $RepoRoot = 'D:\CHECHA_CORE',
        [datetime]$WeekEnd = (Get-KyivDate).Date,
        [string]  $ExpectedBranch = 'reports',
        [string]  $Remote = 'origin',
        [switch]  $NoRelease
    )
    $op = Start-Op "Weekly pipeline"
    try {
        $rep = New-WeeklyReport  -RepoRoot $RepoRoot -WeekEnd $WeekEnd -ExpectedBranch $ExpectedBranch
        $tag = Publish-WeeklyTag -RepoRoot $RepoRoot -WeekEnd $WeekEnd -Remote $Remote -ExpectedBranch $ExpectedBranch
        if (-not $NoRelease) { New-WeeklyRelease -RepoRoot $RepoRoot -WeekEnd $WeekEnd | Out-Null }
        Info ("Done: {0}" -f $tag)
    }
    finally { Stop-Op $op | Out-Null }
}

# === CHECHA: persisted wrappers (session → module) ===


[CmdletBinding()]
param(
    [string]  $RepoRoot = 'D:\CHECHA_CORE',
    [datetime]$WeekEnd = (Get-KyivDate).Date,
    [string]  $ExpectedBranch = 'reports'
)
Ensure-GitRepo $RepoRoot
$blk = Compute-WeekBlock -WeekEnd $WeekEnd
Info ("Weekly block: {0} → {1}" -f $blk.Start.ToString('yyyy-MM-dd'), $blk.End.ToString('yyyy-MM-dd'))
Push-Location $RepoRoot
try {
    & pwsh -File "D:\CHECHA_CORE\TOOLS\Generate-WeeklyChecklistReport.ps1" -WeekEnd $blk.End 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { Die "Generate-WeeklyChecklistReport.ps1 failed with exit $LASTEXITCODE" }
}
finally { Pop-Location }
[pscustomobject]@{ Start = $blk.Start; End = $blk.End; Tag = $blk.Tag; ReportRel = "REPORTS/$($blk.Name)" }


[CmdletBinding()]
param(
    [string]  $RepoRoot = 'D:\CHECHA_CORE',
    [datetime]$WeekEnd = (Get-KyivDate).Date,
    [string]  $Remote = 'origin',
    [string]  $ExpectedBranch = 'reports'
)
Ensure-GitRepo $RepoRoot
$blk = Compute-WeekBlock -WeekEnd $WeekEnd
Push-Location $RepoRoot
try {
    & pwsh -File "D:\CHECHA_CORE\TOOLS\New-WeeklyTag.ps1" -RepoRoot $RepoRoot -WeekEnd $blk.End -Remote $Remote 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { Die "New-WeeklyTag.ps1 failed with exit $LASTEXITCODE" }
}
finally { Pop-Location }
$blk.Tag


[CmdletBinding()]
param(
    [string]  $RepoRoot = 'D:\CHECHA_CORE',
    [datetime]$WeekEnd = (Get-KyivDate).Date
)
Ensure-GitRepo $RepoRoot
$repoSlug = Get-RepoSlug -RepoRoot $RepoRoot
$blk = Compute-WeekBlock -WeekEnd $WeekEnd
$assetAbs = Join-Path $RepoRoot (Join-Path "REPORTS" $blk.Name)
if (-not (Test-Path -LiteralPath $assetAbs)) { Die "Asset not found: $assetAbs" }
Disable-GhPager
$code = Invoke-Gh -Args @('release', 'view', $blk.Tag, '--repo', $repoSlug, '--json', 'tagName')
if ($code -eq 0) {
    Info "Release exists. Uploading asset…"
    Invoke-Gh -Args @('release', 'upload', $blk.Tag, $assetAbs, '--repo', $repoSlug, '--clobber') -ThrowOnError | Out-Null
    Info "Asset updated."
}
else {
    $title = "Weekly {0} → {1}" -f $blk.Start.ToString('yyyy-MM-dd'), $blk.End.ToString('yyyy-MM-dd')
    Info "Creating release $($blk.Tag)…"
    Invoke-Gh -Args @('release', 'create', $blk.Tag, '--repo', $repoSlug, '--title', $title, '--notes', 'Auto-generated weekly report', $assetAbs) -ThrowOnError | Out-Null
    Info "Release created."
}
[pscustomobject]@{ Repo = $repoSlug; Tag = $blk.Tag; Asset = ("REPORTS/{0}" -f $blk.Name) }


[CmdletBinding()]
param(
    [string]  $RepoRoot = 'D:\CHECHA_CORE',
    [datetime]$WeekEnd = (Get-KyivDate).Date,
    [string]  $ExpectedBranch = 'reports',
    [string]  $Remote = 'origin',
    [switch]  $NoRelease
)
$op = Start-Op "Weekly pipeline"
try {
    $rep = New-WeeklyReport  -RepoRoot $RepoRoot -WeekEnd $WeekEnd -ExpectedBranch $ExpectedBranch
    $tag = Publish-WeeklyTag -RepoRoot $RepoRoot -WeekEnd $WeekEnd -Remote $Remote -ExpectedBranch $ExpectedBranch
    if (-not $NoRelease) { New-WeeklyRelease -RepoRoot $RepoRoot -WeekEnd $WeekEnd | Out-Null }
    Info ("Done: {0}" -f $tag)
}
finally { Stop-Op $op | Out-Null }


