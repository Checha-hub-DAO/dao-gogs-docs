# ==========================================================
# Append/replace 'System Health' section in MANIFEST.md (robust)
# ==========================================================
[CmdletBinding()]
param(
  [string]$ManifestPath = "D:\CHECHA_CORE\MANIFEST.md",
  [string]$LogDir       = "D:\CHECHA_CORE\C03_LOG"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ManifestPath)) {
  New-Item -ItemType File -Path $ManifestPath -Force | Out-Null
}

$last = Get-ChildItem -LiteralPath $LogDir -Filter 'CoreHealth_*.md' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

$sectionLines = @()
$sectionLines += '## System Health'
if ($last) {
  $sectionLines += ('- Last check: {0:yyyy-MM-dd HH:mm}' -f $last.LastWriteTime)
  $sectionLines += ('- Report: C03_LOG\{0}' -f $last.Name)
} else {
  $sectionLines += '- Last check: (no logs found)'
}
$replacement = ($sectionLines -join "`r`n") + "`r`n"

# читаємо файл
$body = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction SilentlyContinue
if (-not $body) { $body = "" }

# патерн секції (між заголовками ## ... або до кінця файлу)
$pattern = '##\s*System Health[\s\S]*?(?=^##\s|\Z)'

# надійна заміна через .NET Regex (щоб уникнути аритмії -replace)
Add-Type -AssemblyName System.Text.RegularExpressions | Out-Null
$regexOptions = [System.Text.RegularExpressions.RegexOptions]::Multiline

if ([System.Text.RegularExpressions.Regex]::IsMatch($body, $pattern, $regexOptions)) {
  $newBody = [System.Text.RegularExpressions.Regex]::Replace($body, $pattern, $replacement, $regexOptions)
} else {
  # якщо секції ще нема — додаємо з відступом у кінці
  $newBody = ($body.TrimEnd() + "`r`n`r`n" + $replacement)
}

Set-Content -LiteralPath $ManifestPath -Encoding UTF8 -Value $newBody
Write-Host "[OK] MANIFEST System Health updated → $ManifestPath"
