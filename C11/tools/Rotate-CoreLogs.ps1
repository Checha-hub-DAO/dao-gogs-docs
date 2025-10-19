<#
.SYNOPSIS
  Проста ротація логів у C03\LOG\ (verify_weekly.log, verify_weekly.csv, LOG.md).
.DESCRIPTION
  Ротує файли за розміром із збереженням N останніх копій (за замовч. 5).
  Може бути викликано окремо або з інших скриптів.
.PARAMETER Root
  Корінь CHECHA_CORE (D:\CHECHA_CORE за замовч.).
.PARAMETER Keep
  Скільки ротацій зберігати (за замовч. 5).
.PARAMETER WeeklyLogMaxMB
  Поріг розміру для verify_weekly.log (MB, за замовч. 5).
.PARAMETER WeeklyCsvMaxMB
  Поріг розміру для verify_weekly.csv (MB, за замовч. 10).
.PARAMETER CoreLogMaxMB
  Поріг розміру для LOG.md (MB, за замовч. 2).
#>
[CmdletBinding()]
param(
    [string]$Root = "D:\CHECHA_CORE",
    [int]$Keep = 5,
    [int]$WeeklyLogMaxMB = 5,
    [int]$WeeklyCsvMaxMB = 10,
    [int]$CoreLogMaxMB = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Rotate-File {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][long]$MaxBytes,
        [int]$Keep = 5
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $fi = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $fi) { return $false }
    if ($fi.Length -lt $MaxBytes) { return $false }
    $dir = Split-Path -Parent $Path
    $name = Split-Path -Leaf $Path
    $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $ext = [IO.Path]::GetExtension($name)
    $base = [IO.Path]::GetFileNameWithoutExtension($name)
    $rot = Join-Path $dir ("{0}.{1}{2}" -f $base, $stamp, $ext)
    Move-Item -LiteralPath $Path -Destination $rot -Force
    Set-Content -LiteralPath $Path -Value "" -Encoding UTF8
    $old = Get-ChildItem -LiteralPath $dir -Filter ("{0}.*{1}" -f $base, $ext) | Sort-Object LastWriteTime -Descending
    $i = 0
    foreach ($f in $old) {
        $i++
        if ($i -le $Keep) { continue }
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
    }
    return $true
}

$logDir = Join-Path $Root "C03\LOG"
$do1 = Rotate-File -Path (Join-Path $logDir "verify_weekly.log") -MaxBytes ($WeeklyLogMaxMB * 1MB) -Keep $Keep
$do2 = Rotate-File -Path (Join-Path $logDir "verify_weekly.csv") -MaxBytes ($WeeklyCsvMaxMB * 1MB) -Keep $Keep
$do3 = Rotate-File -Path (Join-Path $logDir "LOG.md") -MaxBytes ($CoreLogMaxMB * 1MB) -Keep $Keep

Write-Host ("♻️  Ротація завершена: weekly.log={0}, weekly.csv={1}, LOG.md={2}" -f $do1, $do2, $do3)


