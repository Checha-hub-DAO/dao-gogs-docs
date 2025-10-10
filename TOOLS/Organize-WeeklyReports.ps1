[CmdletBinding()]
param(
  [string]$ReportsRoot = "D:\CHECHA_CORE\REPORTS"  # де лежать WeeklyChecklist_*.* без тек
)

function Ensure-Dir([string]$p){ if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Path $p -Force | Out-Null } }

$rx = '^WeeklyChecklist_(?<from>\d{4}-\d{2}-\d{2})_to_(?<to>\d{4}-\d{2}-\d{2})\.(?<ext>md|html|csv|xlsx)$'
$files = Get-ChildItem -LiteralPath $ReportsRoot -File -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -match $rx }

if(-not $files){ Write-Host "[INFO] Немає файлів виду WeeklyChecklist_YYYY-MM-DD_to_YYYY-MM-DD.* у корені $ReportsRoot"; exit 0 }

foreach($f in $files){
  if($f.Name -match $rx){
    $from = $matches['from']; $to = $matches['to']
    $year = $from.Substring(0,4)
    $weekDir = Join-Path $ReportsRoot ("WEEKLY\{0}\{1}_to_{2}" -f $year,$from,$to)
    Ensure-Dir $weekDir
    Move-Item -LiteralPath $f.FullName -Destination (Join-Path $weekDir $f.Name) -Force
    Write-Host "[OK] Moved: $($f.Name) -> $weekDir"
  }
}

Write-Host "[DONE] Організація завершена."
