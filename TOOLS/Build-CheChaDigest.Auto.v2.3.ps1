<# Auto-Digest v2.3 (fixed): MD+TXT -> ZIP + SHA256 + auto-Verify CSV + optional KPI #>
[CmdletBinding()]
param(
  [string]$OutDir   = "D:\CHECHA_CORE\C03_LOG\digests",
  [string]$DateTag  = (Get-Date).ToString('yyyy-MM-dd'),
  [int]   $Tail     = 40,
  [switch]$Open,
  [switch]$Overwrite,
  [switch]$NoKPI            # вимикає KPI-блоки в обох форматах
)

function Die($m){ Write-Host "[ERR] $m" -ForegroundColor Red; exit 1 }
function TailSafe([string]$p, [int]$n){
  if(Test-Path -LiteralPath $p){ Get-Content -LiteralPath $p -Tail $n } else { "<missing: $p>" }
}
function GetTask([string]$n,[string]$tp="\"){
  try{
    $t = Get-ScheduledTask -TaskName $n -TaskPath $tp
    $i = $t | Get-ScheduledTaskInfo
    [pscustomobject]@{Name=$n;State=$t.State;Last=$i.LastRunTime;RC=$i.LastTaskResult;Next=$i.NextRunTime}
  } catch {
    [pscustomobject]@{Name=$n;State="N/A";Last=$null;RC=$null;Next=$null}
  }
}
function GhAuth(){
  $gh = Get-Command gh -ErrorAction SilentlyContinue
  if(-not $gh){ return "gh: not installed" }
  try{
    $s = (gh auth status 2>&1) -join "`n"
    if($s -match "Logged in to"){ "OK" } else { "needs login" }
  } catch { "unknown" }
}

# Paths & outputs
if(!(Test-Path -LiteralPath $OutDir)){ New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
$md  = Join-Path $OutDir "CheCha_Digest_$DateTag.md"
$txt = Join-Path $OutDir "CheCha_Digest_$DateTag.txt"
$zip = Join-Path $OutDir "CheCha_Digest_$DateTag.zip"
$sha = "$zip.sha256"

# FIX: правильна перевірка існування без помилки '-or'
if((((Test-Path -LiteralPath $md) -or (Test-Path -LiteralPath $txt) -or (Test-Path -LiteralPath $zip))) -and -not $Overwrite){
  Write-Host "[SKIP] Файли існують. Додай -Overwrite" -ForegroundColor Yellow
  exit 0
}

# Sources
$RunAlert      = "D:\CHECHA_CORE\C07_ANALYTICS\Run-Alert.log"
$RestoreLog    = "D:\CHECHA_CORE\C06_FOCUS\FOCUS_RestoreLog.md"
$ChecksumsGlob = "D:\CHECHA_CORE\C03_LOG\VerifyChecksums_*.csv"
$VerifyScript  = "D:\CHECHA_CORE\TOOLS\Verify-ArchiveChecksums.ps1"
$ReportsRoot   = "D:\CHECHA_CORE\REPORTS"

# Auto-generate fresh CSV (silent)
if(Test-Path -LiteralPath $VerifyScript){
  try{
    pwsh -NoProfile -ExecutionPolicy Bypass -File $VerifyScript `
      -ReportsRoot $ReportsRoot -RebuildIfMissing -ShowExtras -SummaryOnly -CsvReport | Out-Null
  } catch { }
}

# Collect
$now    = Get-Date
$raTail = TailSafe $RunAlert $Tail

# errors in last 24h (ParseExact з fallback)
$raErr24 = 0
foreach($line in $raTail){
  if($line -match '^\[(?<ts>\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2})\].*(ERROR|failed|rc=1)'){
    $ts = $Matches.ts
    try {
      $dt = [datetime]::ParseExact($ts,'yyyy-MM-dd HH:mm:ss',[System.Globalization.CultureInfo]::InvariantCulture)
    } catch { $dt = $null }
    if($dt){ if(($now - $dt).TotalHours -lt 24){ $raErr24++ } } else { $raErr24++ }
  }
}
$raStart = $raTail | Where-Object { $_ -match 'START Run-Alert' } | Select-Object -Last 1
$raEnd   = $raTail | Where-Object { $_ -match 'END Run-Alert' }   | Select-Object -Last 1
$raErr   = $raTail | Where-Object { $_ -match '(ERROR|failed|rc=1)' } | Select-Object -Last 1

$restTail = TailSafe $RestoreLog 50 | Where-Object { $_ -match '^\-\s*\[\d{4}\-' } | Select-Object -Last 5

# Fresh CSV parse with safe defaults
$csvLatest = Get-ChildItem -Path $ChecksumsGlob -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 1
$chk = "N/A"
if($csvLatest){
  try{
    $r = Import-Csv -LiteralPath $csvLatest.FullName | Select-Object -First 1
    if($r){
      $ok       = if([string]::IsNullOrWhiteSpace($r.Ok))          { "?" } else { $r.Ok }
      $missing  = if([string]::IsNullOrWhiteSpace($r.AnyMissing))  { "?" } else { $r.AnyMissing }
      $mismatch = if([string]::IsNullOrWhiteSpace($r.AnyMismatch)) { "?" } else { $r.AnyMismatch }
      $extras   = if([string]::IsNullOrWhiteSpace($r.AnyExtras))   { "?" } else { $r.AnyExtras }
      $chk = "Ok=$ok; Missing=$missing; Mismatch=$mismatch; Extras=$extras"
    } else { $chk = "no rows in CSV" }
  } catch { $chk = "CSV parse error" }
}

$tasks = @(
  GetTask -n "CHECHA_Weekly_Publish" -tp "\CHECHA\"
  GetTask -n "LeaderIntel-Daily"     -tp "\"
) | Where-Object { $_ }

$gh = GhAuth

# Compose
$tasksMd = ($tasks | ForEach-Object {
  "- **$($_.Name)** — *$($_.State)*, Last: $(if($_.Last){$_.Last.ToString('dd.MM.yyyy HH:mm')}else{'—'}) (rc=$($_.RC)), Next: $(if($_.Next){$_.Next.ToString('dd.MM.yyyy HH:mm')}else{'—'})"
}) -join "`n"

$mdBody = @"
# ⚡️ CheCha | Щоденний дайджест — $DateTag

## 🧭 Стан системи
CheCha Core — стабільно. Перевірка архівів: **$chk**.

---

## ⚙️ Технічний контур
**Run-Alert (tail):**
• $raStart
• $raEnd
• ERROR: $raErr
• Помилок за 24h: $raErr24

**Планувальник:**
$tasksMd

---

## 📊 Аналітика
- MAT_BALANCE — правка дужки (рядок 60) у роботі.
- MAT_RESTORE — активний, останні події:
$($restTail -join "`n")

---

## 📡 Синхронізація
- GitHub auth: **$gh**.

## 🪶 Підсумок
Тримай курс: точність моніторингу + валідація сповіщень.

_С.Ч._
"@

$txtBody = @"
⚡️ CheCha | Щоденний дайджест — $DateTag

🧭 Стан: архіви → $chk

⚙️ Run-Alert:
$($raStart)
$($raEnd)
ERROR: $($raErr)
Помилок 24h: $raErr24

Планувальник:
$(
  $tasks | ForEach-Object {
    "$($_.Name): $($_.State); Last=$(if($_.Last){$_.Last.ToString('dd.MM HH:mm')}else{'—'}) rc=$($_.RC); Next=$(if($_.Next){$_.Next.ToString('dd.MM HH:mm')}else{'—'})"
  } | Out-String
)".Trim()

📊 Аналітика:
• MAT_BALANCE — дужка
• MAT_RESTORE — події ↓
$($restTail -join "`n")

📡 Sync: GitHub → $gh

_С.Ч._
"@

# Optional KPI footers
if(-not $NoKPI){
  $kpiFooterMd = @"
---

### 📈 KPI-зріз
| Показник | Значення |
|-----------|-----------|
| Помилки Run-Alert (24h) | $raErr24 |
| Перевірка архівів | $chk |
| GitHub Auth | $gh |

_Автогенерація CheCha Digest — $DateTag_
"@
  $kpiFooterTxt = @"

📈 KPI:
• Помилки 24h: $raErr24
• Архіви: $chk
• GitHub: $gh
(Авто CheCha Digest $DateTag)
"@
  $mdBody  += "`n$kpiFooterMd"
  $txtBody += "`n$kpiFooterTxt"
}

# Write
Set-Content -LiteralPath $md  -Value $mdBody  -Encoding UTF8
Set-Content -LiteralPath $txt -Value $txtBody -Encoding UTF8

# ZIP + SHA256
if(Test-Path -LiteralPath $zip){ Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path $md,$txt -DestinationPath $zip -Force
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLower()
Set-Content -LiteralPath $sha -Value "$hash  $(Split-Path $zip -Leaf)" -Encoding ascii

Write-Host "[OK] Digest готовий:" -ForegroundColor Green
Write-Host " - $md"
Write-Host " - $txt"
Write-Host " - $zip"
Write-Host " - $sha"

if($Open){ Invoke-Item $OutDir }
exit 0
