Set-StrictMode -Version Latest

function Format-Trend {
    param([double]$curr, $prev)
    if (-not $PSBoundParameters.ContainsKey('prev') -or $null -eq $prev -or ($prev -isnot [double] -and $prev -isnot [int])) { return ("{0}%" -f [math]::Round([double]$curr, 1)) }
    $p = [double]$prev; $c = [double]$curr; $d = [math]::Round($c - $p, 1)
    if ($d -gt 0) { return ("{0}% (↑ {1})" -f [math]::Round($c, 1), $d) }
    elseif ($d -lt 0) { return ("{0}% (↓ {1})" -f [math]::Round($c, 1), ([math]::Abs($d))) }
    else { return ("{0}% (→ 0.0)" -f [math]::Round($c, 1)) }
}

function Parse-DoneSharePct {
    param([string]$s)
    if ([string]::IsNullOrWhiteSpace($s) -or $s -eq "—") { return $null }
    $m = [regex]::Match($s, '^\s*([0-9]+(?:\.[0-9]+)?)%'); if ($m.Success) { return [double]$m.Groups[1].Value }; return $null
}

function Get-Median {
    param([double[]]$values)
    if (-not $values -or $values.Count -eq 0) { return 0.0 }
    $sorted = $values | Sort-Object; $n = $sorted.Count
    if ($n % 2 -eq 1) { return [double]$sorted[[int]([math]::Floor($n / 2))] }
    $a = [double]$sorted[($n / 2) - 1]; $b = [double]$sorted[$n / 2]; return [math]::Round( ($a + $b) / 2.0, 1 )
}

function Read-TextUtf8 { param([Parameter(Mandatory)][string]$Path) Get-Content -Path $Path -Encoding UTF8 }
function Write-TextUtf8Bom { param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$Lines) $Lines | Set-Content -Path $Path -Encoding utf8BOM }

function Acquire-ChechaLock {
    param([string]$Path, [int]$TimeoutMinutes = 5)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        try { $fs = [System.IO.File]::Open($Path, 'CreateNew', 'Write', 'None'); $fs.Close(); return }
        catch { if ($sw.Elapsed.TotalMinutes -ge $TimeoutMinutes) { throw "Не вдалося отримати lock за $TimeoutMinutes хв: $Path" }; Start-Sleep -Seconds 2 } 
    }
}
function Release-ChechaLock { param([string]$Path) if (Test-Path $Path) { Remove-Item $Path -Force } }
function Backup-TextFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root)
    if (-not (Test-Path $Path)) { return }; if (-not (Test-Path $Root)) { New-Item -ItemType Directory -Path $Root | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'; $name = Split-Path $Path -Leaf; $dest = Join-Path $Root "$stamp`_$name"; Copy-Item $Path $dest -Force
}

function Write-ProtectedFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$Lines,
        [Parameter(Mandatory)][string]$LockPath,
        [int]$TimeoutMinutes = 5
    )
    Acquire-ChechaLock -Path $LockPath -TimeoutMinutes $TimeoutMinutes
    try { Backup-TextFile -Path $Path -Root $Root; $Lines | Set-Content -Path $Path -Encoding utf8BOM }
    finally { Release-ChechaLock -Path $LockPath }
}

Export-ModuleMember -Function Format-Trend, Parse-DoneSharePct, Get-Median, Read-TextUtf8, Write-TextUtf8Bom, Acquire-ChechaLock, Release-ChechaLock, Backup-TextFile, Write-ProtectedFile

