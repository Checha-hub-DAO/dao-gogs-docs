[CmdletBinding()]
param(
  [string]$RepoRoot    = "D:\CHECHA_CORE",
  [string]$ReportsRoot = "D:\CHECHA_CORE\REPORTS",
  [datetime]$WeekEnd   = $(Get-Date).Date,
  [string]$KitName     = "Strategic_Achievements_Kit",

  # Mermaid
  [switch]$TryMermaid,
  [string]$MermaidCli  = "mmdc",

  # Git
  [switch]$GitCommit,
  [switch]$GitPush,
  [string]$GitBranch   = "reports",
  [string]$RemoteName  = "origin",

  # _tmp rotation & logs mirror
  [int]$TmpKeepWeeks   = 5,
  [switch]$MirrorLogs,
  [string]$LogsDir     = "D:\CHECHA_CORE\C03_LOG",

  # ARCHIVE maintenance
  [switch]$ArchivePurge,
  [switch]$ArchiveMove,
  [int]$ArchiveKeepMonths = 12,
  [string]$ArchiveMoveTo  = "E:\CHECHA_OFFSITE\REPORTS_ARCHIVE",

  # Post-build verification
  [switch]$VerifyAfterBuild,
  [switch]$VerifyShowExtras,
  [switch]$VerifyFailOnWarning,
  [switch]$VerifySummaryOnly,
  [string]$VerifyScriptPath = "D:\CHECHA_CORE\TOOLS\Verify-ArchiveChecksums.ps1"
)

function Die($msg){ Write-Error "[ERR] $msg"; exit 1 }
function Ensure-Dir([string]$p){ if(!(Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function Has-Git(){ try { & git --version 2>$null | Out-Null; return ($LASTEXITCODE -eq 0) } catch { return $false } }
function In-GitRepo([string]$path){
  try { Push-Location $path; & git rev-parse --is-inside-work-tree 2>$null | Out-Null; $ok = ($LASTEXITCODE -eq 0); Pop-Location; return $ok }
  catch { try{Pop-Location}catch{}; return $false }
}
function Cleanup-OldTmp([string]$tmpRoot, [int]$keepWeeks){
  if ($keepWeeks -lt 1 -or -not (Test-Path $tmpRoot)) { return }
  $cutoff = (Get-Date).Date.AddDays(-7 * $keepWeeks)
  Get-ChildItem -LiteralPath $tmpRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -match '^weekly_(\d{4}-\d{2}-\d{2})_to_(\d{4}-\d{2}-\d{2})$') {
      $end = Get-Date $matches[2]
      if ($end -lt $cutoff) { try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop } catch {} }
    }
  }
}
function Maintain-Archive([string]$archiveRoot, [switch]$Purge, [switch]$Move, [int]$KeepMonths, [string]$MoveTo){
  if (-not $Purge -and -not $Move) { return }
  if ($KeepMonths -lt 1 -or -not (Test-Path $archiveRoot)) { return }
  $cutoff = (Get-Date).Date.AddMonths(-$KeepMonths)
  Get-ChildItem -LiteralPath $archiveRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -match '^\d{4}$') {
      $yearDir = $_.FullName
      Get-ChildItem -LiteralPath $yearDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match '^weekly_(\d{4}-\d{2}-\d{2})_to_(\d{4}-\d{2}-\d{2})$') {
          $end = Get-Date $matches[2]
          if ($end -lt $cutoff) {
            if ($Move) {
              $target = Join-Path $MoveTo (Join-Path $($_.Parent.Name) $_.Name)
              Ensure-Dir (Split-Path $target -Parent)
              try { Move-Item -LiteralPath $_.FullName -Destination $target -Force -ErrorAction Stop } catch {}
            } elseif ($Purge) {
              try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop } catch {}
            }
          }
        }
      }
      if (-not (Get-ChildItem -LiteralPath $yearDir -Force | Where-Object { $_ })) { try { Remove-Item -LiteralPath $yearDir -Force -ErrorAction Stop } catch {} }
    }
  }
}

# Week normalization
$WeekEnd   = [datetime]::ParseExact($WeekEnd.ToString('yyyy-MM-dd'),'yyyy-MM-dd',$null)
$WeekStart = $WeekEnd.AddDays(-6)
$startTag  = $WeekStart.ToString('yyyy-MM-dd')
$endTag    = $WeekEnd.ToString('yyyy-MM-dd')
$weekTag   = "weekly_{0}_to_{1}" -f $startTag, $endTag
$yearTag   = $WeekEnd.ToString('yyyy')

# Paths
$archiveRoot = Join-Path $ReportsRoot "ARCHIVE\$yearTag\$weekTag"
Ensure-Dir $archiveRoot
$tmpRoot = Join-Path $RepoRoot "REPORTS\_tmp"
$tmp     = Join-Path $tmpRoot $weekTag
Ensure-Dir $tmp

# Rotate _tmp
Cleanup-OldTmp -tmpRoot $tmpRoot -keepWeeks $TmpKeepWeeks

# Mermaid render
if ($TryMermaid) {
  $mmdcOk = $false
  try { & $MermaidCli --version 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { $mmdcOk = $true } } catch {}
  if ($mmdcOk) {
    foreach ($def in @(
      @{ in = Join-Path $tmp "Strategic_Achievements_Map_Extended.mmd"; out = "Strategic_Achievements_Map_Extended" },
      @{ in = Join-Path $tmp "Strategic_Achievements_Map_Compact.mmd";  out = "Strategic_Achievements_Map_Compact"  }
    )) {
      if (Test-Path $def.in) {
        & $MermaidCli -i $def.in -o (Join-Path $tmp ($def.out + ".png"))  2>$null
        & $MermaidCli -i $def.in -o (Join-Path $tmp ($def.out + ".svg"))  2>$null
      }
    }
  }
}

# README
$readme = Join-Path $tmp "README.md"
if (!(Test-Path $readme)) {
@"
# Strategic Achievements Kit
**Дата формування:** $($WeekEnd.ToString('yyyy-MM-dd'))

(опис вмісту, як раніше)
"@ | Set-Content -Path $readme -Encoding UTF8
}

# Collect files
$expectedNames = @(
  "Strategic_Achievements_Map.png",
  "Strategic_Achievements_Map_Extended.png",
  "Strategic_Achievements_Map_Highlighted.png",
  "Strategic_Achievements_Map_Extended.pdf",
  "Strategic_Achievements_Map_Interactive.html",
  "Strategic_Achievements_Map_Interactive.svg",
  "Strategic_Achievements_Map_Extended.mmd",
  "Strategic_Achievements_Map_Compact.mmd",
  "README.md"
)
$files = foreach ($name in $expectedNames) { $p = Join-Path $tmp $name; if (Test-Path $p) { $p } else { Write-Warning "[miss] $name не знайдено у $tmp" } }
if (-not $files) { Die "Немає жодного артефакту для пакування. Поклади файли у $tmp" }

# Copy to ARCHIVE
foreach ($f in $files) { Copy-Item -LiteralPath $f -Destination $archiveRoot -Force }

# LOG.txt
$log = Join-Path $archiveRoot "LOG.txt"
"Strategic Achievements • $weekTag" | Set-Content -Path $log -Encoding UTF8
"Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Add-Content -Path $log -Encoding UTF8
"" | Add-Content -Path $log -Encoding UTF8
$tot = 0
Get-ChildItem $archiveRoot -File | Sort-Object Name | ForEach-Object {
  $size = $_.Length; $tot += $size
  "{0,-45}  {1,12:N0} bytes  {2}" -f $_.Name, $size, $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') |
    Add-Content -Path $log -Encoding UTF8
}
"" | Add-Content -Path $log -Encoding UTF8
("TOTAL: {0:N0} bytes" -f $tot) | Add-Content -Path $log -Encoding UTF8

# ZIP
$zipName = "{0}_{1}.zip" -f $KitName, $endTag
$zipPath = Join-Path $archiveRoot $zipName
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $archiveRoot "*") -DestinationPath $zipPath

# CHECKSUMS
$checksums = Join-Path $archiveRoot "CHECKSUMS.txt"
"SHA256 checksums for $weekTag" | Set-Content -Path $checksums -Encoding UTF8
Get-ChildItem $archiveRoot -File | ForEach-Object {
  $h = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
  "{0}  {1}" -f $h, $_.Name
} | Add-Content -Path $checksums -Encoding UTF8

Write-Host "[ok] Пакет зібрано:"
Write-Host "  Folder: $archiveRoot"
Write-Host "  ZIP:    $zipPath"
Write-Host "  HASH:   $checksums"

# Mirror logs
if ($MirrorLogs) {
  Ensure-Dir $LogsDir
  Copy-Item -LiteralPath $log -Destination (Join-Path $LogsDir ("LOG_{0}.txt" -f $weekTag)) -Force
  Copy-Item -LiteralPath $checksums -Destination (Join-Path $LogsDir ("CHECKSUMS_{0}.txt" -f $weekTag)) -Force
}

# === Post-build verification ===
if ($VerifyAfterBuild) {
  if (-not (Test-Path $VerifyScriptPath)) {
    Write-Warning "[verify] Verify script not found: $VerifyScriptPath"
  } else {
    $verifyArgs = @(
      "-File", "`"$VerifyScriptPath`"",
      "-ReportsRoot", "`"$ReportsRoot`"",
      "-WeekTag", "`"$weekTag`""
    )
    if ($VerifyShowExtras)   { $verifyArgs += "-ShowExtras" }
    if ($VerifyFailOnWarning){ $verifyArgs += "-FailOnWarning" }
    if ($VerifySummaryOnly)  { $verifyArgs += "-SummaryOnly" }
    # завжди робимо CSV у C03_LOG
    $verifyArgs += @("-CsvReport", "-LogsDir", "`"$LogsDir`"")

    Write-Host "[verify] running Verify-ArchiveChecksums.ps1…"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "pwsh"
    $psi.Arguments = ($verifyArgs -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    if ($out) { Write-Host $out }
    if ($err) { Write-Warning $err }

    if ($p.ExitCode -eq 0) {
      Write-Host "[verify] OK (checksums match)"
    } else {
      Write-Warning "[verify] FAILED (exit $($p.ExitCode)) — перевір деталі вище та CSV у $LogsDir"
      # якщо хочеш «падати» скриптом тут — розкоментуй:
      # exit $p.ExitCode
    }
  }
}

# Git
if ($GitCommit) {
  if (-not (Has-Git)) { Write-Warning "[git] git не знайдено — пропускаю"; return }
  if (-not (In-GitRepo $RepoRoot)) { Write-Warning "[git] $RepoRoot не git-репо — пропускаю"; return }

  Push-Location $RepoRoot
  try {
    & git rev-parse --verify $GitBranch 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { & git checkout -b $GitBranch } else { & git checkout $GitBranch }

    # .gitignore ensure (REPORTS/_tmp/)
    $gitignore  = Join-Path $RepoRoot ".gitignore"
    $ignoreLine = "REPORTS/_tmp/"
    if (Test-Path $gitignore) {
      $lines = Get-Content -LiteralPath $gitignore -ErrorAction SilentlyContinue
      if (-not ($lines -contains $ignoreLine)) {
        Add-Content -LiteralPath $gitignore -Value "`n# auto: ignore CHECHA tmp`n$ignoreLine"
        & git add -- ".gitignore" 2>$null
      }
    } else {
      Set-Content -LiteralPath $gitignore -Encoding UTF8 -Value "# CHECHA: робоча тека для проміжних артефактів — не трекати`n$ignoreLine`n"
      & git add -- ".gitignore" 2>$null
    }

    & git add -- "REPORTS/ARCHIVE/$yearTag/$weekTag" 2>$null
    & git add -- "REPORTS/ARCHIVE/$yearTag/$weekTag/*" 2>$null

    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    & git commit -m ("reports: {0} | {1}" -f $weekTag, $stamp) 2>$null

    $tag = "weekly-{0}_to_{1}" -f $startTag, $endTag
    & git tag -fa $tag -m "weekly rollup $startTag→$endTag" 2>$null

    if ($GitPush) {
      & git push $RemoteName $GitBranch
      $exists = (& git ls-remote --tags $RemoteName "refs/tags/$tag" 2>$null)
      if ($exists) { & git push $RemoteName :refs/tags/$tag }
      & git push $RemoteName "refs/tags/$tag"
    }
  }
  finally { Pop-Location }
}

# ARCHIVE maintenance (after push)
Maintain-Archive -archiveRoot (Join-Path $ReportsRoot "ARCHIVE") `
  -Purge:$ArchivePurge -Move:$ArchiveMove -KeepMonths $ArchiveKeepMonths -MoveTo $ArchiveMoveTo
