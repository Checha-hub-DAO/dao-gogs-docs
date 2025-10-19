param(
    [string]$ReportsRoot = "D:\CHECHA_CORE\C03_LOG",
    [string]$SumsRoot = "D:\CHECHA_CORE\C03_LOG\checksums",
    [ValidateSet('SHA256', 'SHA1', 'MD5')][string]$Algorithm = 'SHA256',
    [switch]$SummaryOnly,
    [switch]$CsvReport
)

function Get-HashLower([string]$Path, [string]$Alg) {
    try {
        return (Get-FileHash -LiteralPath $Path -Algorithm $Alg).Hash.ToLower()
    }
    catch {
        return $null
    }
}

function Resolve-ReportPath([string]$ReportsRoot, [string]$FileName) {
    $p1 = Join-Path $ReportsRoot $FileName
    if (Test-Path -LiteralPath $p1) { return (Resolve-Path -LiteralPath $p1).Path }
    $p2 = Join-Path (Join-Path $ReportsRoot "visuals") $FileName
    if (Test-Path -LiteralPath $p2) { return (Resolve-Path -LiteralPath $p2).Path }
    $hit = Get-ChildItem -Path $ReportsRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $FileName } | Select-Object -First 1
    if ($hit) { return $hit.FullName }
    return $null
}

$results = New-Object System.Collections.Generic.List[object]
$summary = [ordered]@{ Files = 0; Ok = 0; Mismatch = 0; Missing = 0; BadLines = 0 }

$sumFiles = Get-ChildItem -Path $SumsRoot -Filter "SHA256_SUMS_*.txt" -File -ErrorAction SilentlyContinue
if (-not $sumFiles) {
    Write-Warning "No checksum files found in: $SumsRoot"
    exit 1
}

$lineRegex = '^\s*([A-Fa-f0-9]{32,64})\s{2}(.+?)\s*$'  # 'hash␠␠filename'

foreach ($sf in $sumFiles) {
    $lines = Get-Content -LiteralPath $sf.FullName -ErrorAction SilentlyContinue
    $ln = 0
    foreach ($line in $lines) {
        $ln++
        if ($line -match '^\s*$') { continue }
        $m = [regex]::Match($line, $lineRegex)
        if (-not $m.Success) {
            $results.Add([pscustomobject]@{
                    SumsFile = $sf.Name
                    Line     = $ln
                    FileName = '<PARSE_ERROR>'
                    FilePath = ''
                    Expected = ''
                    Actual   = ''
                    Status   = 'BAD_LINE'
                })
            $summary.BadLines++
            continue
        }
        $expected = $m.Groups[1].Value.ToLower()
        $fileName = $m.Groups[2].Value.Trim()
        $filePath = Resolve-ReportPath -ReportsRoot $ReportsRoot -FileName $fileName

        if (-not $filePath) {
            $results.Add([pscustomobject]@{
                    SumsFile = $sf.Name; Line=$ln; FileName=$fileName; FilePath='';
                    Expected=$expected; Actual=''; Status='MISSING_FILE'
                })
            $summary.Missing++
            continue
        }

        $actual = Get-HashLower -Path $filePath -Alg $Algorithm
        $status = if ($actual -and $actual -eq $expected) { 'OK' } else { 'MISMATCH' }
        if ($status -eq 'OK') { $summary.Ok++ } else { $summary.Mismatch++ }

        $results.Add([pscustomobject]@{
                SumsFile = $sf.Name; Line=$ln; FileName=$fileName; FilePath=$filePath;
                Expected=$expected; Actual=$actual; Status=$status
            })
    }
}

$summary.Files = $results.Count
if (-not $SummaryOnly) {
    $results | Sort-Object Status, FileName | Format-Table -AutoSize | Out-String | Write-Host
}

"SUMMARY:"
$summary.GetEnumerator() | ForEach-Object { "{0,-12} : {1}" -f $_.Key, $_.Value } | Write-Host

if ($CsvReport) {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $csv = Join-Path $SumsRoot ("VerifyReport_{0}.csv" -f $stamp)
    $results | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csv
    Write-Host ("[CSV] saved: {0}" -f $csv)
}

# Exit codes: 0 OK; 2 mismatch; 3 missing; 4 bad lines; 1 generic
if ($summary.Mismatch -eq 0 -and $summary.Missing -eq 0 -and $summary.BadLines -eq 0) {
    exit 0
}
elseif ($summary.Mismatch -gt 0) {
    exit 2
}
elseif ($summary.Missing -gt 0) {
    exit 3
}
elseif ($summary.BadLines -gt 0) {
    exit 4
}
else {
    exit 1
}


