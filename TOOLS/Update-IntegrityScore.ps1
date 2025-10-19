<#
.SYNOPSIS
  Оновлює C12_IntegrityScore на основі останнього VerifyChecksums_*.csv.

.DESCRIPTION
  Зчитує останній CSV з C03_LOG, обчислює інтегральний бал (0–100),
  записує або додає рядок у C07_ANALYTICS\C12_IntegrityScore.csv.
#>

[CmdletBinding()]
param(
    [string]$ChecksumsGlob = "D:\CHECHA_CORE\C03_LOG\VerifyChecksums_*.csv",
    [string]$OutCsv = "D:\CHECHA_CORE\C07_ANALYTICS\C12_IntegrityScore.csv",
    [string]$LogPath = "D:\CHECHA_CORE\C07_ANALYTICS\logs\Update-IntegrityScore.log"
)

# --- helpers ---
function Ensure-Dir([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}
function Write-Log([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    $line; try { $null = $line | Tee-Object -FilePath $LogPath -Append } catch {}
}

Ensure-Dir (Split-Path -Parent $OutCsv)
Ensure-Dir (Split-Path -Parent $LogPath)

Write-Log "START Update-IntegrityScore"
Write-Log "ChecksumsGlob=$ChecksumsGlob"

$latest = Get-ChildItem -Path $ChecksumsGlob -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Desc | Select-Object -First 1

if (-not $latest) {
    Write-Log "[WARN] No VerifyChecksums CSV found."
    Write-Log "END Update-IntegrityScore"
    exit 0
}

Write-Log ("Using file: {0}" -f $latest.FullName)

try {
    $csv = Import-Csv -LiteralPath $latest.FullName
    if (-not $csv) { throw "CSV is empty." }
    $row = $csv | Select-Object -First 1

    # Захист від відсутніх полів
    $WeeksChecked = if ($row.WeeksChecked) { [int]$row.WeeksChecked } else { 0 }
    $Ok = if ($row.Ok -eq "True" -or $row.Ok -eq $true) { $true } else { $false }
    $AnyMismatch = if ($row.AnyMismatch -eq "True" -or $row.AnyMismatch -eq $true) { $true } else { $false }
    $AnyMissing = if ($row.AnyMissing -eq "True" -or $row.AnyMissing -eq $true) { $true } else { $false }
    $AnyExtras = if ($row.AnyExtras -eq "True" -or $row.AnyExtras -eq $true) { $true } else { $false }

    $MismatchCount = if ($row.PSObject.Properties.Name -contains 'MismatchCount') { [int]$row.MismatchCount } else { [int]($AnyMismatch) }
    $MissingCount = if ($row.PSObject.Properties.Name -contains 'MissingCount' ) { [int]$row.MissingCount } else { [int]($AnyMissing) }
    $ExtrasCount = if ($row.PSObject.Properties.Name -contains 'ExtrasCount'  ) { [int]$row.ExtrasCount } else { [int]($AnyExtras) }

    # Формула балу: 100 - (Mismatch*10 + Missing*5 + Extras*2)
    $raw = 100 - ($MismatchCount * 10 + $MissingCount * 5 + $ExtrasCount * 2)
    $Score = [Math]::Max(0, [Math]::Min(100, $raw))

    $rec = [pscustomobject]@{
        Date          = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        WeeksChecked  = $WeeksChecked
        Ok            = $Ok
        AnyMismatch   = $AnyMismatch
        AnyMissing    = $AnyMissing
        AnyExtras     = $AnyExtras
        MismatchCount = $MismatchCount
        MissingCount  = $MissingCount
        ExtrasCount   = $ExtrasCount
        Score         = $Score
        SourceCsv     = $latest.FullName
    }

    if (Test-Path $OutCsv) {
        $rec | Export-Csv -LiteralPath $OutCsv -Append -NoTypeInformation -Encoding UTF8
    }
    else {
        $rec | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
    }

    Write-Log ("[OK] IntegrityScore={0} saved -> {1}" -f $Score, $OutCsv)
}
catch {
    Write-Log ("[ERR] {0}" -f $_.Exception.Message)
    exit 1
}

Write-Log "END Update-IntegrityScore"
exit 0

