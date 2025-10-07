[CmdletBinding()]
Param(
  [string]$Root = 'D:\CHECHA_CORE',
  [string]$ToolsRel = 'C11\tools',
  [string]$ArchiveRel = 'C05\ARCHIVE',
  [string]$TaskPath = '\Checha\',
  [string]$TaskName = 'Cleanup-C11-Tools-Weekly'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function New-DirIfMissing([string]$Path){ if(-not (Test-Path $Path)){ New-Item -ItemType Directory -Path $Path | Out-Null } }
function Write-HealthLog([string]$Path,[string]$Level,[string]$Msg){
  $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  Add-Content -Path $Path -Value "$ts [$Level] $Msg"
}

$tools   = Join-Path $Root $ToolsRel
$archive = Join-Path $Root $ArchiveRel
$logDir  = Join-Path $Root 'C03\LOG'
New-DirIfMissing $logDir
$hlog = Join-Path $logDir 'cleanup_health.log'
$ok = $true

# 1) README.md
$readme = Join-Path $tools 'README.md'
if (Test-Path $readme) { Write-HealthLog $hlog 'INFO' "README OK: $readme" } else { $ok=$false; Write-HealthLog $hlog 'WARN' "README missing: $readme" }

# 2) TOOLS_INDEX.md
$index = Join-Path $tools 'TOOLS_INDEX.md'
if (Test-Path $index) { Write-HealthLog $hlog 'INFO' "INDEX OK: $index" } else { $ok=$false; Write-HealthLog $hlog 'WARN' "INDEX missing: $index" }

# 3) cleanup_tools.log
$clog = Join-Path $logDir 'cleanup_tools.log'
if (Test-Path $clog) {
  try { $last = (Get-Content -Path $clog -Tail 1) } catch { $last = $null }
  Write-HealthLog $hlog 'INFO' ("CLEANUP LOG OK: " + ($last ?? '(no tail)'))
} else { $ok=$false; Write-HealthLog $hlog 'WARN' "CLEANUP LOG missing: $clog" }

# 4) Остання сесія архіву
$lastSession = Get-ChildItem -Path $archive -Directory -Filter 'scripts_cleanup_*' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($lastSession) {
  $old = Join-Path $lastSession.FullName 'old_variants'
  $movedCount = (Get-ChildItem -Path $old -File -ErrorAction SilentlyContinue | Measure-Object).Count
  if ($movedCount -eq 0) {
    # Нема що пакувати — це OK (порожня сесія)
    Write-HealthLog $hlog 'INFO' "ARCHIVE SKIPPED (no variants moved): $($lastSession.FullName)"
  } else {
    $zip = Get-ChildItem -Path $lastSession.FullName -Filter 'scripts_*.zip' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $chk = Join-Path $lastSession.FullName 'CHECKSUMS.txt'
    if ($zip -and (Test-Path $chk)) {
      try {
        $line = (Get-Content -Path $chk -TotalCount 1)
        $parts = $line -split '\s+'
        $declared = $parts[1]
        $file = Join-Path $lastSession.FullName $parts[-1]
        if (Test-Path $file) {
          $calc = (Get-FileHash -Path $file -Algorithm SHA256).Hash
          if ($calc -eq $declared) { Write-HealthLog $hlog 'INFO' "ARCHIVE OK: $($zip.Name) SHA256 match" }
          else { $ok=$false; Write-HealthLog $hlog 'WARN' "ARCHIVE SHA256 mismatch: $($zip.FullName)" }
        } else { $ok=$false; Write-HealthLog $hlog 'WARN' "ARCHIVE file missing: $file" }
      } catch { $ok=$false; Write-HealthLog $hlog 'ERROR' "ARCHIVE verify fail: $($_.Exception.Message)" }
    } else {
      $ok=$false; Write-HealthLog $hlog 'WARN' "ARCHIVE incomplete in $($lastSession.FullName) (zip or CHECKSUMS.txt missing)"
    }
  }
} else {
  # Перший прогін без архівів — не фейлимо, лише інформуємо
  Write-HealthLog $hlog 'INFO' "No scripts_cleanup_* yet in $archive"
}

# 5) Задача Планувальника — лише перевірка
try {
  $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop
  $info = $task | Get-ScheduledTaskInfo
  $next = $info.NextRunTime
  $nrOK = $false; if ($next) { try { $nrOK = ($next -gt (Get-Date).AddMinutes(5)) } catch {} }
  if ($nrOK) { Write-HealthLog $hlog 'INFO' ("TASK OK: NextRun=" + $next) } else { $ok=$false; Write-HealthLog $hlog 'WARN' ("TASK NextRun ? : " + $next) }
} catch { $ok=$false; Write-HealthLog $hlog 'WARN' "TASK missing: $TaskPath$TaskName" }

if ($ok) { Write-HealthLog $hlog 'INFO' 'HEALTH: OK'; Write-Host "`n✅ HEALTH: OK" -ForegroundColor Green; exit 0 }
else     { Write-HealthLog $hlog 'ERROR' 'HEALTH: FAIL'; Write-Host "`n❌ HEALTH: FAIL — дивись лог $hlog" -ForegroundColor Red; exit 1 }
