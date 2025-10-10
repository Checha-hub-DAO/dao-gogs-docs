[CmdletBinding()]
param(
  [string]$Root = "D:\CHECHA_CORE",
  [string]$OutCsv = "D:\CHECHA_CORE\C06_FOCUS\Incidents\Incident_Register.csv",
  [string]$OutMd  = "D:\CHECHA_CORE\C06_FOCUS\Incidents\Incident_Register.md"
)

$incDir = Join-Path $Root "C06_FOCUS\Incidents"
$items = Get-ChildItem -LiteralPath $incDir -Filter "INC_*.md" -ErrorAction SilentlyContinue | Sort-Object Name

$rows = @()
foreach($f in $items){
  $txt = Get-Content -LiteralPath $f.FullName -Raw
  $title = ($txt | Select-String -Pattern '^#\s⚠️\s*(.+)$' -AllMatches).Matches.Value -replace '^#\s+⚠️\s*',''
  $date  = ($txt | Select-String -Pattern '^\*\*Дата:\*\*\s*(.+)$' -AllMatches).Matches.Value -replace '^\*\*Дата:\*\*\s*',''
  $ref   = ($txt | Select-String -Pattern '^\*\*Reflex JSON:\*\*\s*(.+)$' -AllMatches).Matches.Value -replace '^\*\*Reflex JSON:\*\*\s*',''
  # Невдалі задачі (якщо є секція Task Health)
  $badTasks = ($txt | Select-String -Pattern '^\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*(\d+)\s*\|$' -AllMatches).Matches |
    ForEach-Object { ($_ -split '\|')[1].Trim() } | Select-Object -Unique
  $rows += [pscustomobject]@{
    IncidentId = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    Date       = $date
    Title      = $title
    ReflexJson = $ref
    FailedTasks= ($badTasks -join ', ')
    File       = $f.Name
  }
}

# CSV
if ($rows.Count -gt 0) {
  $rows | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
}

# Markdown
$md = @()
$md += "# 📕 Incident Register — CheCha CORE"
$md += ""
$md += "| ID | Date | Title | Failed Tasks | File |"
$md += "|:---|:-----|:------|:-------------|:-----|"
foreach($r in $rows){
  $md += "| {0} | {1} | {2} | {3} | {4} |" -f $r.IncidentId,$r.Date,$r.Title,($r.FailedTasks -replace '\|','/'),$r.File
}
Set-Content -LiteralPath $OutMd -Value ($md -join "`r`n") -Encoding UTF8

Write-Host "[OK] Зведений реєстр побудовано:"
Write-Host " - $OutCsv"
Write-Host " - $OutMd"
