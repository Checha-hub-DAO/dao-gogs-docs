<#
  RADAR-FixTimestamps.ps1
  Нормалізує timestamp у artifacts.csv до ISO 8601 (з таймзоною)
#>

[CmdletBinding()]
param(
    [string]$RepoRoot = "D:\CHECHA_CORE",
    [string]$CsvPath,
    [string]$AssumeOffset = "+03:00",  # Europe/Kyiv у жовтні (EEST)
    [switch]$DryRun
)

function Write-Log([string]$m, [string]$lvl = "INFO") {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; Write-Host "[$lvl] $ts $m"
}
function HasOffset([string]$s) { return ($s -match 'Z$') -or ($s -match '[\+\-]\d{2}:\d{2}$') }
function TryParse([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $styles = @(
        'yyyy-MM-ddTHH:mm:ssK', 'yyyy-MM-ddTHH:mm:ss', 'yyyy-MM-dd HH:mm:ss',
        'yyyy-MM-dd', 'dd.MM.yyyy HH:mm', 'dd.MM.yyyy', 'MM/dd/yyyy HH:mm', 'MM/dd/yyyy'
    )
    foreach ($fmt in $styles) {
        $dt = [datetime]::MinValue
        if ([datetime]::TryParseExact($s, $fmt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeLocal, [ref]$dt)) {
            return $dt
        }
    }
    # fallback — загальний парсер .NET
    try { return [datetime]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture) } catch { return $null }
}

try {
    if ([string]::IsNullOrWhiteSpace($CsvPath)) { $CsvPath = Join-Path $RepoRoot 'RADAR\INDEX\artifacts.csv' }
    if (!(Test-Path -LiteralPath $CsvPath)) { throw "Не знайдено індекс: $CsvPath" }
    $rows = Import-Csv -LiteralPath $CsvPath
    if (-not $rows -or $rows.Count -eq 0) { throw "Порожній CSV" }

    $changed = 0; $failed = 0; $total = $rows.Count
    $out = foreach ($r in $rows) {
        $raw = $r.timestamp
        $new = $raw
        $hadOffset = $false

        if ($raw) {
            $hadOffset = HasOffset $raw
            $dt = TryParse $raw
            if ($dt) {
                if ($hadOffset) {
                    # збережемо точний ISO (з наявною зсувною інфою)
                    $new = [System.Xml.XmlConvert]::ToString($dt, [System.Xml.XmlDateTimeSerializationMode]::Local)
                }
                else {
                    # додамо передбачуваний офсет
                    $iso = $dt.ToString("yyyy-MM-dd'T'HH:mm:ss")
                    $new = "$iso$AssumeOffset"
                }
            }
            else {
                $failed++
            }
        }
        else {
            $failed++
        }

        if ($new -ne $raw) { $changed++ }
        $r | Add-Member -NotePropertyName timestamp -NotePropertyValue $new -Force
        $r
    }

    if ($DryRun) {
        Write-Log "DryRun: змінено $changed / $total; непарсованих $failed"
        exit 0
    }

    $bak = "$CsvPath.bak"; Copy-Item -LiteralPath $CsvPath -Destination $bak -Force
    $tmp = [System.IO.Path]::GetTempFileName()
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $hdr = $rows[0].PSObject.Properties.Name
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine(($hdr -join ','))
    foreach ($r in $out) {
        $vals = foreach ($h in $hdr) {
            $v = $r.$h
            if ($null -eq $v) { "" }
            else {
                $s = [string]$v
                if ($s -match '[,"\r\n]') { '"' + ($s -replace '"', '""') + '"' } else { $s }
            }
        }
        [void]$sb.AppendLine(($vals -join ','))
    }
    [System.IO.File]::WriteAllText($tmp, $sb.ToString(), $utf8)
    Move-Item -LiteralPath $tmp -Destination $CsvPath -Force

    $logDir = Join-Path $RepoRoot 'C03_LOG'; if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
    Add-Content -Path (Join-Path $logDir 'RADAR_FIXTIME_LOG.md') -Encoding UTF8 `
    ("- [{0}] File='{1}' | Changed={2}/{3} | FailedParse={4} | AssumeOffset={5}" -f `
        (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $CsvPath, $changed, $total, $failed, $AssumeOffset)

    Write-Log "Готово: змінено $changed / $total; непарсованих $failed"
    exit 0
}
catch {
    Write-Log $_.Exception.Message "ERR"; exit 2
}


